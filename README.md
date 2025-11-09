# `typ2docx`: Converting Typst Project to Microsoft Word Format

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
> Currently this tool supports macOS only, and it requires several dependencies.
> The package installation is expected to take some time, since it requires
> compiling a Rust library. Read along to know why.

To compile the Rust extension used in this tool, you will need Rust toolchain,
which can be installed via [`rustup`](https://rustup.rs/).

This tool is distributed via PyPI. Installation via
[`uv`](https://docs.astral.sh/uv/getting-started/installation/) is recommended.
To install `typ2docx`, execute the following command:

```sh
uv tool install typ2docx
```

If you want to tinker with this program:

```sh
git clone git@github.com:sghng/typ2docx.git
cd typ2docx
# do your modifications...
uv tool install .
```

For more details, read
[UV's guide on using tools](https://docs.astral.sh/uv/guides/tools/). You may
also use `pipx` or other similar tools to install and run this program.

The following runtime dependencies are also required:

- [Pandoc](https://pandoc.org/), a universal document converter.
- [Saxon](https://www.saxonica.com/), a processor for
  [XSLT 3.0](https://www.w3.org/TR/xslt-30/). The free home edition would
  suffice.
- [Adobe Acrobat](https://acrobat.adobe.com) desktop app for converting PDF to
  `.docx`. Either the free `Acrobat Reader` or the paid `Acrobat Pro` works.

For macOS users, it is recommended to install these dependencies via
[Homebrew](https://brew.sh/) with the following command:

```sh
brew install pandoc saxon adobe-acrobat-reader
```

## Usage

Once the tool is installed, invoke it with the path to the entry point of your
Typst project to convert it into Microsoft Word `.docx` format.

```sh
typ2docx main.typ
```

Run `typ2docx --help` to see the help info on how to use this tool.

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
