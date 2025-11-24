# Changelog

## [Unreleased]

[unreleased]: https://github.com/sghng/typ2docx/compare/v0.5.0...main

### Added

- Initial support for Windows through ported PowerShell scripting for merging
  documents. (#26)

## [0.5.0] - 2025-11-20

[0.5.0]: https://github.com/sghng/typ2docx/compare/v0.4.0...v0.5.0

### Changed

- Saxon is now bundled with this tool via
  [`saxonche` package](https://pypi.org/project/saxonche/), one less
  installation step! (#21)

## [0.4.0] - 2025-11-17

[0.4.0]: https://github.com/sghng/typ2docx/compare/v0.3.0...v0.4.0

### Changed

- Refactored the Rust extension to make it more idiomatic and concise. (#15)
- Refactored pipeline with `asyncio`, so that subprocesses can be terminated
  gracefully when an error is encountered in any branch, or when user decided to
  abort the program. (#16)
- As a result of the above refactoring, due to the use of `asyncio.TaskGroup`,
  the minimum Python version is bumped to 3.11.
- Parallelized the invocation of `export` and `extract` using threads on
  free-threaded Python (GIL-disabled) and ProcessPoolExecutor on standard Python
  (GIL-enabled), significantly shortening conversion time. (#19)

## [0.3.0] - 2025-11-14

[0.3.0]: https://github.com/sghng/typ2docx/compare/v0.2.0...v0.3.0

### Added

- Support passing additional flags to Typst compiler via `-- --flags ...`. The
  `--root` flag has special treatment to make sure the math extraction works.
  (#9)

### Changed

- To make `--root` work, we had to create a new source file (e.g.
  `.typ2docx.main.typ`) along the input file, due to
  [a bug in the Typst compiler](https://github.com/typst/typst/issues/7370).
  Therefore, this tool now requires write access to the project directory.

## [0.2.0] - 2025-11-11

[0.2.0]: https://github.com/sghng/typ2docx/compare/v0.1.0...v0.2.0

### Added

- Support for Adobe PDFServices API as the PDF to DOCX engine, enabling use on
  UNIX-like systems where `sh` is available. (#3)

### Changed

- CLI now requires users to specify the desired conversion engine. (#3)
- Minimum supported Python version increased to 3.10 as part of the PDFServices
  integration. (#3)

### Fixed

- Corrected output paths when converting source files located outside the
  current working directory. (#6)
- Improved guidance and reference materials. (#3)

## [0.1.0] - 2025-11-08

[0.1.0]: https://github.com/sghng/typ2docx/releases/tag/v0.1.0

### Added

- Initial release supporting the Acrobat engine on macOS.
