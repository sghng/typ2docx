use std::{
    fs::{read, read_to_string},
    ops::ControlFlow,
    path::{Path, PathBuf},
    sync::LazyLock,
};

use pyo3::{pyfunction, pymodule};

use typst::{
    Library, LibraryExt, ROUTINES, World,
    comemo::Track,
    diag::FileResult,
    engine::{Route, Sink, Traced},
    foundations::{Bytes, Content, Datetime},
    math::EquationElem,
    syntax::{FileId, Source, VirtualPath},
    text::{Font, FontBook},
    utils::LazyHash,
};
use typst_eval::eval;
use typst_kit::{
    download::{Downloader, ProgressSink},
    package::PackageStorage,
};

#[pymodule(gil_used = false)]
mod extract {
    #[pymodule_export]
    use super::extract_equations;
}

#[pyfunction(name = "extract")]
fn extract_equations(path: &str, root: Option<&str>) -> Vec<String> {
    let path = Path::new(path)
        .canonicalize()
        .expect("path should be valid");
    let root = root
        .map_or_else(
            || path.parent().expect("path should have parent"),
            Path::new,
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
        if elem.to_packed::<EquationElem>().is_some() {
            let span = elem.span();
            let source = world
                .source(span.id().expect("spans are attached"))
                .expect("src files should be available");
            equations.push(source.text()[source.range(span).expect("ranges are valid")].into());
        }
        ControlFlow::<(), ()>::Continue(())
    });
    equations
}

/// A minimal World implementation for evaluation and extraction, inspired by SystemWorld in
/// typst-cli.
struct SimpleWorld {
    main: FileId,
    root: PathBuf,
    package_storage: PackageStorage,
}

impl SimpleWorld {
    fn new(path: &Path, root: &Path) -> Self {
        let main = FileId::new(
            None,
            VirtualPath::within_root(path, root).expect("entry point should be in the root"),
        );
        let root = root.to_path_buf();
        let package_storage = PackageStorage::new(
            None,
            None,
            Downloader::new(concat!(
                env!("CARGO_PKG_NAME"),
                "/",
                env!("CARGO_PKG_VERSION")
            )),
        );
        Self {
            main,
            root,
            package_storage,
        }
    }
    fn resolve(&self, id: FileId) -> PathBuf {
        let root = if let Some(spec) = id.package() {
            self.package_storage
                .prepare_package(spec, &mut ProgressSink)
                .expect("package should be prepared")
        } else {
            self.root.clone()
        };
        id.vpath().resolve(&root).expect("file path should resolve")
    }
}

impl World for SimpleWorld {
    fn main(&self) -> FileId {
        self.main
    }
    fn source(&self, id: FileId) -> FileResult<Source> {
        Ok(Source::new(
            id,
            read_to_string(self.resolve(id)).expect("file should be readable as string"),
        ))
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        Ok(Bytes::new(
            read(self.resolve(id)).expect("file should be readable as bytes"),
        ))
    }
    // dummy implementations
    fn library(&self) -> &LazyHash<Library> {
        static LIBRARY: LazyLock<LazyHash<Library>> =
            LazyLock::new(|| LazyHash::new(Library::default()));
        &LIBRARY
    }
    fn book(&self) -> &LazyHash<FontBook> {
        static BOOK: LazyLock<LazyHash<FontBook>> =
            LazyLock::new(|| LazyHash::new(FontBook::new()));
        &BOOK
    }
    fn font(&self, _: usize) -> Option<Font> {
        None
    }
    fn today(&self, _: Option<i64>) -> Option<Datetime> {
        None
    }
}
