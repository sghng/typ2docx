use std::collections::HashMap;
use std::env;
use std::ops::ControlFlow;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use comemo::Track;
use typst::diag::{FileError, FileResult};
use typst::foundations::{Bytes, Content, Datetime};
use typst::math::EquationElem;
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};
use typst_eval::eval;

fn main() {
    let arg = env::args()
        .nth(1)
        .expect("Usage: extract <path-to-typ-file>");
    let file_path = Path::new(&arg);

    let world = match SimpleWorld::new(file_path) {
        Ok(w) => w,
        Err(e) => {
            eprintln!("Error creating world: {}", e);
            std::process::exit(1);
        }
    };

    let mut equations: Vec<(FileId, String)> = Vec::new();
    let mut sink = typst::engine::Sink::default();

    // Evaluate the main file
    let main = world.main();
    let source = match world.source(main) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error reading source: {}", e);
            std::process::exit(1);
        }
    };

    let routines = &typst::ROUTINES;
    let traced = typst::engine::Traced::default();

    let content = match eval(
        routines,
        (&world as &dyn World).track(),
        traced.track(),
        sink.track_mut(),
        typst::engine::Route::default().track(),
        &source,
    ) {
        Ok(m) => m.content(),
        Err(diagnostics) => {
            eprintln!("Evaluation errors:");
            for diag in diagnostics {
                eprintln!("  {}", diag.message);
            }
            std::process::exit(1);
        }
    };

    // Traverse the content tree to find equations in document order
    extract_equations(&content, &world, &mut equations);

    if equations.is_empty() {
        println!("No equations found.");
    } else {
        println!("Found {} equation(s) in document order:\n", equations.len());
        for (i, (file_id, eq_text)) in equations.iter().enumerate() {
            let file_name = file_id.vpath().as_rootless_path().display();
            println!("Equation {} (from {}):\n{}\n", i + 1, file_name, eq_text);
        }
    }
}

fn extract_equations(content: &Content, world: &dyn World, equations: &mut Vec<(FileId, String)>) {
    let _ = content.traverse(&mut |elem: Content| -> ControlFlow<()> {
        if let Some(_eq) = elem.to_packed::<EquationElem>() {
            // Get the source text from the span
            let span = elem.span();

            // Try to get the file ID from the span
            if let Some(file_id) = span.id() {
                // Try to load the source file
                match world.source(file_id) {
                    Ok(source) => {
                        // Get the byte range for this span
                        if let Some(range) = source.range(span) {
                            let text = &source.text()[range];
                            equations.push((file_id, text.to_string()));
                        } else {
                            // Span range might not be found - try to extract plain text
                            let text = elem.plain_text();
                            if !text.is_empty() {
                                equations.push((file_id, format!("[no range: {}]", text)));
                            }
                        }
                    }
                    Err(e) => {
                        // File might not be loaded - try to extract what we can
                        let text = elem.plain_text();
                        if !text.is_empty() {
                            equations.push((file_id, format!("[load failed: {}]", text)));
                        }
                    }
                }
            } else {
                // Span is detached
                let text = elem.plain_text();
                if !text.is_empty() {
                    equations.push((world.main(), format!("[detached: {}]", text)));
                }
            }
        }
        ControlFlow::Continue(())
    });
}

/// A simple World implementation for file-based Typst projects.
struct SimpleWorld {
    project_root: PathBuf,
    main: FileId,
    files: Mutex<HashMap<FileId, Source>>,
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
}

impl SimpleWorld {
    fn new(main_path: &Path) -> Result<Self, String> {
        // First canonicalize the main file path
        let main_path_canonical = main_path.canonicalize().map_err(|e| {
            format!(
                "Failed to resolve main file '{}': {}",
                main_path.display(),
                e
            )
        })?;

        // Then get the project root from the canonicalized main file's parent
        // Also canonicalize the project root to handle symlinks correctly
        let project_root = main_path_canonical
            .parent()
            .ok_or_else(|| {
                format!(
                    "Main file '{}' has no parent directory",
                    main_path_canonical.display()
                )
            })?
            .canonicalize()
            .map_err(|e| format!("Failed to canonicalize project root: {}", e))?;

        let main_vpath =
            VirtualPath::within_root(&main_path_canonical, &project_root).ok_or_else(|| {
                format!(
                    "Main file '{}' is outside project root '{}'",
                    main_path_canonical.display(),
                    project_root.display()
                )
            })?;

        let main_id = FileId::new(None, main_vpath);

        // For equation extraction, we don't need fonts, but World trait requires them
        // Use an empty font book - equations will still be extracted correctly
        let fonts = Vec::new();
        let book = FontBook::new();

        Ok(Self {
            project_root,
            main: main_id,
            files: Mutex::new(HashMap::default()),
            library: LazyHash::new(Library::default()),
            book: LazyHash::new(book),
            fonts,
        })
    }

    fn load_source(&self, id: FileId) -> FileResult<Source> {
        let mut files = self.files.lock().unwrap();
        if let Some(source) = files.get(&id) {
            return Ok(source.clone());
        }

        // Try to resolve the path relative to the project root
        let path = match id.vpath().resolve(&self.project_root) {
            Some(p) => p,
            None => {
                // If direct resolution fails, try resolving relative to the project root
                // VirtualPath is always relative to the project root and starts with /
                let relative_path = id.vpath().as_rootless_path();
                let full_path = self.project_root.join(relative_path);

                // Verify the file exists and is within the project root
                if full_path.exists() && full_path.starts_with(&self.project_root) {
                    full_path
                } else {
                    return Err(FileError::NotFound(id.vpath().as_rootless_path().into()));
                }
            }
        };

        // Verify the file exists before trying to read it
        if !path.exists() {
            return Err(FileError::NotFound(path.clone()));
        }

        let content = std::fs::read_to_string(&path).map_err(|e| FileError::from_io(e, &path))?;

        let source = Source::new(id, content);
        files.insert(id, source.clone());
        Ok(source)
    }
}

impl World for SimpleWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    fn main(&self) -> FileId {
        self.main
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        // Typst's evaluation handles cycle detection, so we just load sources
        self.load_source(id)
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        let path = id
            .vpath()
            .resolve(&self.project_root)
            .ok_or_else(|| FileError::NotFound(id.vpath().as_rootless_path().into()))?;

        let bytes = std::fs::read(&path).map_err(|_| FileError::NotFound(path.clone()))?;
        Ok(Bytes::new(bytes))
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    fn today(&self, _: Option<i64>) -> Option<Datetime> {
        None
    }
}
