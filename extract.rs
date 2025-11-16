use std::{
    collections::HashMap,
    fs::{read, read_to_string},
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
    let root = root
        .map_or_else(
            || path.parent().expect("path should have parent"),
            |r| Path::new(r),
        )
        .canonicalize()
        .expect("root should be valid");

    let world = SimpleWorld::new(&path, &root);
    let mut equations = Vec::new();
    let _ = eval(
        &ROUTINES,
        (&world as &dyn World).track(),
        Traced::default().track(),
        Sink::default().track_mut(),
        Route::default().track(),
        &world
            .source(world.main())
            .expect("src for main should be available"),
    )
    .expect("project should compile")
    .content()
    .traverse(&mut |elem: Content| {
        if let Some(_) = elem.to_packed::<EquationElem>() {
            let span = elem.span();
            let source = world
                .source(span.id().expect("spans are attached"))
                .expect("src files should be available");
            equations
                .push(source.text()[source.range(span).expect("ranges are valid")].to_string());
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
        let main = FileId::new(
            None,
            VirtualPath::within_root(&path, &root).expect("entry point should be in the root"),
        );
        let files = Mutex::new(HashMap::new());
        Self { root, main, files }
    }
}

static LIBRARY: LazyLock<LazyHash<Library>> = LazyLock::new(|| LazyHash::new(Library::default()));
static FONT_BOOK: LazyLock<LazyHash<FontBook>> = LazyLock::new(|| LazyHash::new(FontBook::new()));

impl World for SimpleWorld {
    fn main(&self) -> FileId {
        self.main
    }
    fn source(&self, id: FileId) -> FileResult<Source> {
        Ok(self
            .files
            .lock()
            .unwrap()
            .entry(id)
            .or_insert_with(|| {
                Source::new(
                    id,
                    read_to_string(
                        id.vpath()
                            .resolve(&self.root)
                            .expect("src files should be present"),
                    )
                    .expect("src files should be readable"),
                )
            })
            .clone())
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        Ok(Bytes::new(
            read(
                id.vpath()
                    .resolve(&self.root)
                    .expect("file should be available"),
            )
            .expect("file should be readable"),
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
