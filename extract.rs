use std::collections::HashMap;
use std::env;
use std::ops::ControlFlow;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use comemo::Track;
use typst::diag::FileResult;
use typst::foundations::{Bytes, Content, Datetime};
use typst::math::EquationElem;
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};
use typst_eval::eval;

fn main() {
    let arg = env::args().nth(1).unwrap();
    let file_path = Path::new(&arg);

    let world = SimpleWorld::new(file_path);
    let mut equations: Vec<(FileId, String)> = Vec::new();
    let mut sink = typst::engine::Sink::default();

    let content = eval(
        &typst::ROUTINES,
        (&world as &dyn World).track(),
        typst::engine::Traced::default().track(),
        sink.track_mut(),
        typst::engine::Route::default().track(),
        &world.source(world.main()).unwrap(),
    )
    .unwrap()
    .content();

    extract_equations(&content, &world, &mut equations);

    if !equations.is_empty() {
        println!("Found {} equation(s) in document order:\n", equations.len());
        for (i, (file_id, eq_text)) in equations.iter().enumerate() {
            println!(
                "Equation {} (from {}):\n{}\n",
                i + 1,
                file_id.vpath().as_rootless_path().display(),
                eq_text
            );
        }
    }
}

fn extract_equations(content: &Content, world: &dyn World, equations: &mut Vec<(FileId, String)>) {
    let _ = content.traverse(&mut |elem: Content| -> ControlFlow<()> {
        if let Some(_eq) = elem.to_packed::<EquationElem>() {
            let span = elem.span();
            let file_id = span.id().unwrap_or(world.main());
            let source = world.source(file_id).unwrap();
            equations.push((
                file_id,
                source.text()[source.range(span).unwrap()].to_string(),
            ));
        }
        ControlFlow::Continue(())
    });
}

/// A dummy World implementation for file-based Typst projects.
struct SimpleWorld {
    project_root: PathBuf,
    main: FileId,
    files: Mutex<HashMap<FileId, Source>>,
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
}

impl SimpleWorld {
    fn new(main_path: &Path) -> Self {
        let main_path_canonical = main_path.canonicalize().unwrap();
        let project_root = main_path_canonical
            .parent()
            .unwrap()
            .canonicalize()
            .unwrap();
        let main = FileId::new(
            None,
            VirtualPath::within_root(&main_path_canonical, &project_root).unwrap(),
        );
        Self {
            project_root,
            main,
            files: Mutex::new(HashMap::new()),
            library: LazyHash::new(Library::default()),
            book: LazyHash::new(FontBook::new()),
            fonts: Vec::new(),
        }
    }

    fn load_source(&self, id: FileId) -> FileResult<Source> {
        let mut files = self.files.lock().unwrap();
        if let Some(source) = files.get(&id) {
            return Ok(source.clone());
        }
        let source = Source::new(
            id,
            std::fs::read_to_string(
                id.vpath()
                    .resolve(&self.project_root)
                    .unwrap_or_else(|| self.project_root.join(id.vpath().as_rootless_path())),
            )
            .unwrap(),
        );
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
        self.load_source(id)
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        Ok(Bytes::new(
            std::fs::read(id.vpath().resolve(&self.project_root).unwrap()).unwrap(),
        ))
    }
    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }
    fn today(&self, _: Option<i64>) -> Option<Datetime> {
        None
    }
}
