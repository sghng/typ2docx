use std::{
    collections::HashMap,
    ops::ControlFlow,
    path::{Path, PathBuf},
    sync::{LazyLock, Mutex},
};

use pyo3::prelude::{pyfunction, pymodule};

use typst::{
    comemo::Track,
    diag::FileResult,
    engine::{Route, Sink, Traced},
    foundations::{Bytes, Content, Datetime},
    math::EquationElem,
    syntax::{FileId, Source, VirtualPath},
    text::{Font, FontBook},
    utils::LazyHash,
    Library, LibraryExt, World, ROUTINES,
};
use typst_eval::eval;

#[pymodule]
mod extract {
    #[pymodule_export]
    use super::extract_equations;
}

#[pyfunction]
#[pyo3(name = "extract")]
fn extract_equations(path: &str, root: Option<&str>) -> Vec<String> {
    let path = Path::new(path)
        .canonicalize()
        .expect("path should be valid");
    let root = match root {
        Some(r) => Path::new(r).canonicalize().expect("root should be valid"),
        None => path.parent().unwrap().canonicalize().unwrap(),
    };

    let world = SimpleWorld::new(&path, &root);
    let mut equations = Vec::new();
    let _ = eval(
        &ROUTINES,
        (&world as &dyn World).track(),
        Traced::default().track(),
        Sink::default().track_mut(),
        Route::default().track(),
        &world.source(world.main()).unwrap(),
    )
    .expect("project should compile")
    .content()
    .traverse(&mut |elem: Content| {
        if elem.to_packed::<EquationElem>().is_some() {
            let span = elem.span();
            let source = world.source(span.id().unwrap()).unwrap();
            equations.push(source.text()[source.range(span).unwrap()].to_string());
        }
        ControlFlow::<(), ()>::Continue(())
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
    fn new(path: &Path, root: &Path) -> Self {
        let root = root.to_path_buf();
        let main = FileId::new(None, VirtualPath::within_root(&path, &root).unwrap());
        let files = Mutex::new(HashMap::new());
        Self { root, main, files }
    }

    /// load a source if isn't loaded already
    fn load_source(&self, id: FileId) -> FileResult<Source> {
        let mut files = self.files.lock().unwrap();
        // TODO: this can be changed to match or HashMap::entry() API
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
