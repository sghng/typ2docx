# Changelog

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
