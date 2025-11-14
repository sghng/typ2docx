# Changelog

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
