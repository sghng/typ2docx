#! /usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path
from shutil import copy2, move
from subprocess import CalledProcessError, run
from sys import argv
from tempfile import TemporaryDirectory
from typing import Annotated, Literal, Optional

from rich.console import Console
from typer import Argument, Exit, Option, Typer

from extract import extract  # ty: ignore[unresolved-import]
from pdfservices import export
from utils import TempFile

app = Typer()
console = Console()

HERE: Path = Path(__file__).parent
DIR: Path

INPUT: Path
OUTPUT: Path
ENGINE: str
DEBUG: bool

try:
    idx = argv.index("--")
    TYPST_OPTS = argv[idx + 1 :]
    argv = argv[:idx]
except ValueError:
    TYPST_OPTS = []


@contextmanager
def WorkDirectory():
    global DIR
    if DEBUG:
        DIR = Path.cwd() / ".typ2docx/"
        DIR.mkdir(exist_ok=True)
        yield
    else:
        with TemporaryDirectory(prefix=".typ2docx_") as tmpdir:
            DIR = Path(tmpdir)
            yield


@app.command()
def main(
    input: Annotated[Path, Argument(help="Entry point to the Typst project")],
    engine: Annotated[
        Literal["acrobat", "pdfservices"],
        Option("-e", "--engine", help="The engine used to convert PDF to DOCX."),
    ],
    output: Annotated[
        Optional[Path],
        Option(
            "-o",
            "--output",
            help="Output DOCX file path.",
            show_default="input.with_suffix('.docx')",
        ),
    ] = None,
    debug: Annotated[
        bool,
        Option(
            "-d",
            "--debug",
            help="Keep intermediate files in working directory for inspection.",
        ),
    ] = False,
    # defined here for cli help only, handled in main
    typst_opts: Annotated[
        list[str],
        Argument(
            help="Options forwarded to the Typst compiler (must follow --).",
            metavar="[-- TYPST_OPT...]",
        ),
    ] = [],
):
    """Convert a Typst project to DOCX format."""

    global INPUT, OUTPUT, DEBUG, ENGINE
    INPUT, OUTPUT, ENGINE, DEBUG = (
        input,
        output or Path.cwd() / input.with_suffix(".docx").name,
        engine,
        debug,
    )

    console.print(f"[bold blue]Converting[/bold blue] {INPUT}...")
    if debug:
        console.print(
            "[yellow]Debug mode:[/yellow] "
            "Intermediate files will be kept in ./.typ2docx/"
        )

    with WorkDirectory():
        with ThreadPoolExecutor() as executor:
            future1 = executor.submit(lambda: (typ2pdf(), pdf2docx()))
            future2 = executor.submit(lambda: (typ2typ(), typ2docx()))
            future1.result()
            future2.result()
        console.print("[bold green]Merging[/bold green] DOCX")
        docx2docx()
        move(DIR / "out.docx", OUTPUT)
    console.print(f"[bold green]Output saved to[/bold green] {OUTPUT}")


def typ2pdf():
    console.print("[bold green]Converting[/bold green] TYP -> PDF with Typst")
    try:
        with TempFile(
            INPUT.with_name(f".typ2docx.{INPUT.name}"),
            (HERE / "preamble.typ").read_text() + INPUT.read_text(),
        ) as input:
            try:
                run(["typst", "compile", *TYPST_OPTS, input, DIR / "a.pdf"], check=True)
            except CalledProcessError:
                console.print(
                    "[bold red]Error:[/bold red] "
                    "Failed to compile Typst project to PDF."
                )
                raise Exit(1)
    except PermissionError:
        console.print(
            "[bold red]Error:[/bold red] Failed to compile Typst project to PDF. "
            "Write access to the project directory is required!"
        )
        raise Exit(1)


def pdf2docx():
    match ENGINE:
        case "pdfservices":
            console.print(
                "[bold green]Converting[/bold green] "
                "PDF -> DOCX with Adobe PDFServices API"
            )
            try:
                export(DIR / "a.pdf")
            except ValueError:
                console.print(
                    "[bold red]Error:[/bold red] Make sure you have "
                    "PDF_SERVICES_CLIENT_ID and PDF_SERVICES_CLIENT_SECRET "
                    "set in environment!",
                )
                raise Exit(1)
            except RuntimeError as e:
                console.print(
                    "[bold red]Error:[/bold red] Failed to convert PDF -> DOCX "
                    f"with Adobe PDFServices API: {e}"
                )
                raise Exit(1)
        case "acrobat":
            console.print(
                "[bold green]Converting[/bold green] PDF -> DOCX with Adobe Acrobat"
            )
            try:
                run(
                    ["osascript", HERE / "acrobat.applescript", DIR / "a.pdf"],
                    cwd=DIR,
                    check=True,
                )
            except CalledProcessError:
                console.print(
                    "[bold red]Error:[/bold red] "
                    "Failed to convert PDF -> DOCX with Acrobat"
                )
                raise Exit(1)
        case _:
            raise NotImplementedError("More engines support incoming!")


def typ2typ():
    """Typst to Typst (math only)"""

    console.print("[bold green]Extracting[/bold green] math source code")

    try:
        root = TYPST_OPTS[TYPST_OPTS.index("--root") + 1]
    except ValueError:
        root = None
    except IndexError:
        console.print(
            "[bold red]Error:[/bold red] "
            "Failed to extract equations. The --root flag requires a value."
        )
        raise Exit(1)

    try:
        eqs: list[str] = extract(str(INPUT), root)
    except BaseException as e:  # PanicException is derived from BaseException
        if type(e).__name__ == "PanicException":
            console.print(
                "[bold red]Error:[/bold red] "
                "Failed to extract equations, make sure the Typst project compiles."
            )
            raise Exit(1)
        else:
            raise e

    console.print(f"[bold green]Extracted[/bold green] {len(eqs)} math blocks")
    eqs = [eq for eq in eqs if eq[1:-1].strip()]  # empty equations are omitted
    src = "\n\n".join(eqs)
    (DIR / "b.typ").write_text(src)


def typ2docx():
    """Typst to DOCX (with Pandoc, math only)"""
    console.print("[bold green]Converting[/bold green] TYP -> DOCX with Pandoc")
    try:
        run(["pandoc", "b.typ", "-o", "b.docx"], cwd=DIR, check=True)
    except CalledProcessError:
        console.print(
            "[bold red]Error:[/bold red] Failed to convert Typst -> DOCX with Pandoc"
        )
        raise Exit(1)


def docx2docx():
    # Saxon evaluates path relative to the xsl, must be copied
    copy2(HERE / "merge.xslt", DIR / "merge.xslt")
    try:
        run(["sh", HERE / "merge.sh"], cwd=DIR, check=True)
    except CalledProcessError:
        console.print("[bold red]Error:[/bold red] Failed to merge DOCX with Saxon")
        raise Exit(1)


if __name__ == "__main__":
    app()
