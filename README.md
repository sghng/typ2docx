# `typ2docx`: Convert Typst Project to Microsoft Word Format

`typ2docx` is a command line tool that converts a Typst project to Microsoft
Word `.docx` format, with tables, cross-references, most of the styles, and most
importantly the math markups preserved.

You're encouraged to read this document thoroughly before using it, as I
employed many non-trivial hacks for this non-trivial problem! (It involves 6
different programming languages!)

If this tool enhanced your workflow, especially if it helped with your academic
publication, please consider crediting this project or sponsoring me :heart:.

## Installation

> [!NOTE]
>
> Currently this tool only supports macOS and Linux systems, as it requires a
> `bash` script and some cli dependencies!

### Prerequisite

To compile the Rust extension used in this tool, you will need Rust toolchain,
which can be installed via [`rustup`](https://rustup.rs/).

This tool is distributed via PyPI. Installation via
[`uv`](https://docs.astral.sh/uv/getting-started/installation/) is recommended.
You may also use `pipx` or other similar tools to install and run this program.

For more details, read
[`uv`'s guide on using tools](https://docs.astral.sh/uv/guides/tools/).

### Tool Installation

You may execute the following command:

```sh
uv tool install typ2docx
```

> [!NOTE]
>
> The package installation process is expected to take some time, since it
> requires compiling a Rust library. Read along to know why.

If you want to tinker with this program:

```sh
git clone git@github.com:sghng/typ2docx.git
cd typ2docx
# do your modifications...
uv tool install .
```

### Runtime Dependencies

The following runtime dependencies are also required:

- [Pandoc](https://pandoc.org/), a universal document converter.
- [Saxon](https://www.saxonica.com/), a processor for
  [XSLT 3.0](https://www.w3.org/TR/xslt-30/). The free home edition would
  suffice.
- One of the supported engines as specified in
  [this section](#pdf-docx-engines).

`pandoc` and `saxon` should be available in `PATH`.

For macOS users, it is recommended to install these dependencies via
[Homebrew](https://brew.sh/) with the following command:

```sh
brew install pandoc saxon
```

For Windows users, it is recommended to install via `winget`:

```pwsh
winget install pandoc
```

Linux users should use the package manager specific to your distro for
installation.

## Usage

Once the tool is installed, invoke it with the path to the entry point of your
Typst project and specify an engine to convert it into Microsoft Word `.docx`
format. For example:

```sh
typ2docx main.typ -e acrobat
```

Run `typ2docx --help` to see the help info on how to use this tool.

### PDF -> DOCX Engines

You need to specify the engine used to convert a PDF to `.docx` file. Currently
there are two supported engines:

- **[Adobe Acrobat](https://acrobat.adobe.com)**: Pass `-e acrobat` to use this
  engine. It uses Acrobat desktop app with some GUI automation to export a PDF
  to `.docx`. Either the free Acrobat Reader or the paid Acrobat Pro would work.
  This is only supported on macOS now.
- **[Adobe PDFServices API](https://developer.adobe.com/document-services/apis/pdf-services/)**:
  Pass `-e pdfservices` to use this engine. It requires internet connection and
  valid PDFServices API credentials. This service comes with 500 free
  conversions per month, which should be enough for most people. You will also
  need to set `PDF_SERVICES_CLIENT_ID` and `PDF_SERVICES_CLIENT_SECRET` for this
  engine to work. For example:

  ```sh
  PDF_SERVICES_CLIENT_ID=xxx PDF_SERVICES_CLIENT_SECRET=xxx typ2docx main.typ -e pdfservices
  ```

## What It Does and Does Not

There are some known issues -- which may or may not be a real issue depending on
your use cases. Read the [_Motivation_](#motivation) section to understand why I
built this tool.

- Text in SVG/PDF images are distorted.
- Some spaces between inline equations and regular text are missing.
- Not all stylings are preserved. (This is expected, just like for any file
  format conversion.)

## Similar Tools

- [Adobe Acrobat](https://acrobat.adobe.com) does a great job in converting PDF
  to `.docx`, but the math equations are completely messed up.
- [Microsoft Word](https://www.microsoft.com/en-us/microsoft-365/word) can also
  convert a PDF to `.docx` format. In my experience, it doesn't work as well as
  Adobe Acrobat.
- [`pdf2docx`](https://pypi.org/project/pdf2docx/) Python library doesn't work
  for most of my PDF files.
- [Pandoc](https://pandoc.org) provides superb support for math markup when
  converting `.typ` file to `.docx`, but its support for Typst is very limited.
  For example, it doesn't recognize basic functions like `#stroke`. It also
  doesn't support latest features in Typst, such as embedding PDF as image.
- [`typlite`](https://docs.rs/crate/typlite/) is a tool developed by the author
  of `tinymist`. Its support for conversion to `.docx` is limited, as it relies
  on HTML as an intermediary. Styles and cross-references are lost, and math are
  rendered as images.

## Motivation

This tool is developed so that a `.docx` export that meets the basic requirement
of academic paper submission can be produced. These requirements are very loose,
since the press has their own process for making a manuscript publication ready.

- Cross-referencing is NOT required.
- Figures are NOT required. They can be included as standalone attachments, as
  long as the names are matched.
- NO typesetting required.

With these said, the only true requirement is the quality of math equations,
which must be retained effectively. And in Microsoft Word, it should be in
Office Math Markup Language (OMML).

This tool is developed primarily to address the equation output problem.

## Solution

The idea is to export with both Adobe Acrobat and Pandoc, and merge the best
part in the two exports together.

- Branch 1
  - A preamble is injected to the Typst project entry point, so that all math
    are rendered as markers.
  - Typst compiles the project into PDF file.
  - Adobe Acrobat converts this PDF into `.docx` format. This process is
    automated with an AppleScript.
- Branch 2
  - A Rust lib extracts all math source code in a Typst project.
  - The source code are put into a new Typst source file, in order of their
    appearance in original document.
  - This source file is converted to `.docx` with Pandoc, they are cleanly
    formatted with MathML.
- The two Microsoft Word files are unpacked. A XLST script merges the
  `document.xml` files by examining the markers. The result is finally repacked
  into a `.docx` file as output.

The math source code can not be extracted with purely static analysis or regex
matching, since the location where a content is defined can be different from
where it shows up in document, and multiple source files can be involved via
`#include` and `#import`. This necessitates the use of `typst` and `typst-eval`
Rust crates for parsing as well as evaluating the Typst project.

## Contribution

You are more than welcome to contribute by raising issues or opening pull
requests!
