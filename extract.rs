use std::collections::HashMap;
use std::env;
use std::ops::ControlFlow;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};

use comemo::Track;
use typst::diag::FileResult;
use typst::engine::{Route, Sink, Traced};
use typst::foundations::{Bytes, Content, Datetime};
use typst::math::EquationElem;
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::ROUTINES;
use typst::{Library, LibraryExt, World};
use typst_eval::eval;

fn main() {
    let arg = env::args().nth(1).unwrap();
    let path = Path::new(&arg);

    let world = SimpleWorld::new(path);

    let content = eval(
        &ROUTINES,
        (&world as &dyn World).track(),
        Traced::default().track(),
        Sink::default().track_mut(),
        Route::default().track(),
        &world.source(world.main()).unwrap(),
    )
    .unwrap()
    .content();

    let equations = extract(&content, &world);

    if !equations.is_empty() {
        println!("Found {} equations:\n", equations.len());
        for (i, eq_text) in equations.iter().enumerate() {
            println!("Eq {}: {}\n", i + 1, eq_text);
        }
    }
}

/// Extract equation sources by traversing the content
fn extract(content: &Content, world: &dyn World) -> Vec<String> {
    let mut equations: Vec<String> = Vec::new();
    // TODO: make the traversal more efficient
    let _ = content.traverse(&mut |elem: Content| -> ControlFlow<()> {
        if let Some(_) = elem.to_packed::<EquationElem>() {
            let span = elem.span();
            let file_id = span.id().unwrap();
            let source = world.source(file_id).unwrap();
            equations.push(source.text()[source.range(span).unwrap()].to_string());
        }
        ControlFlow::Continue(())
    });
    equations
}

/// A minimal World implementation for evaluation and extraction
struct SimpleWorld {
    /// root dir of the project
    root: PathBuf,
    /// main file id
    main: FileId,
    files: Mutex<HashMap<FileId, Source>>,
}

impl SimpleWorld {
    fn new(path: &Path) -> Self {
        let path = path.canonicalize().unwrap();
        let root = path.parent().unwrap().canonicalize().unwrap();
        let main = FileId::new(None, VirtualPath::within_root(&path, &root).unwrap());
        let files = Mutex::new(HashMap::new());
        Self { root, main, files }
    }

    /// load a source if isn't loaded already
    fn load_source(&self, id: FileId) -> FileResult<Source> {
        let mut files = self.files.lock().unwrap();
        if let Some(source) = files.get(&id) {
            return Ok(source.clone());
        }
        let source = Source::new(
            id,
            std::fs::read_to_string(id.vpath().resolve(&self.root).unwrap()).unwrap(),
        );
        files.insert(id, source.clone());
        Ok(source)
    }
}

static LIBRARY: LazyLock<LazyHash<Library>> = LazyLock::new(|| LazyHash::new(Library::default()));
static FONT_BOOK: LazyLock<LazyHash<FontBook>> = LazyLock::new(|| LazyHash::new(FontBook::new()));

impl World for SimpleWorld {
    fn main(&self) -> FileId {
        self.main
    }
    fn source(&self, id: FileId) -> FileResult<Source> {
        self.load_source(id)
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        Ok(Bytes::new(
            std::fs::read(id.vpath().resolve(&self.root).unwrap()).unwrap(),
        ))
    }
    // dummy implementations
    fn library(&self) -> &LazyHash<Library> {
        &LIBRARY
    }
    fn book(&self) -> &LazyHash<FontBook> {
        &FONT_BOOK
    }
    fn font(&self, _: usize) -> Option<Font> {
        None
    }
    fn today(&self, _: Option<i64>) -> Option<Datetime> {
        None
    }
}
