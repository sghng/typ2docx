#! /usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from json import dumps
from pathlib import Path
from shutil import copy2, move
from subprocess import CalledProcessError, run
from tempfile import TemporaryDirectory

from extract import extract as extract_equations  # ty: ignore[unresolved-import]
from rich.console import Console
from rich.json import JSON
from typer import Argument, Exit, Option, Typer

HERE = Path(__file__).parent
app = Typer(
    name="typ2docx",
    help="Converting Typst project to DOCX format.",
    rich_markup_mode="rich",
)
console = Console()
DIR = Path.cwd() / ".typ2docx/"
INPUT: Path
OUTPUT: Path
DEBUG: bool = False


@contextmanager
def WorkDirectory():
    global DIR
    if DEBUG:
        DIR.mkdir(exist_ok=True)
        yield
    else:
        with TemporaryDirectory(prefix=".typ2docx_") as tmpdir:
            DIR = Path(tmpdir)
            yield


@app.command()
def extract(
    path: str = Argument(help="Entry point to the Typst project"),
):
    """Extract equations from a Typst project and serialize them to JSON."""
    equations = extract_equations(path)
    console.print(JSON(dumps(equations)))


@app.command()
def convert(
    input: str = Argument(help="Entry point to the Typst project"),
    output: str = Option(
        None,
        "--output",
        "-o",
        help="Output DOCX file path. Defaults to input filename with .docx extension.",
    ),
    debug: bool = Option(
        False,
        "--debug",
        help="Keep intermediate files in working directory for inspection.",
    ),
):
    """Convert a Typst project to DOCX format."""
    global INPUT, OUTPUT, DEBUG
    INPUT = Path(input)
    OUTPUT = Path(output) if output else Path.cwd() / f"{INPUT.stem}.docx"
    DEBUG = debug

    console.print(f"[bold blue]Converting[/bold blue] {INPUT}...")
    if debug:
        console.print(
            "[yellow]Debug mode:[/yellow] Intermediate files will be kept in ./.typ2docx/"
        )

    with WorkDirectory():
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(branch1)
            future2 = executor.submit(branch2)
            future1.result()
            future2.result()
        console.print("[bold green]Merging[/bold green] DOCX")
        docx2docx()
        move(DIR / "out.docx", OUTPUT)
    console.print(f"[bold green]Output saved to[/bold green] {OUTPUT}")


def branch1():
    typ2pdf()
    pdf2docx()


def branch2():
    """Typst -- Pandoc -> DOCX"""
    # use pandoc to convert to DOCX
    console.print("[bold green]Converting[/bold green] TYP -> DOCX with Pandoc")
    typ2typ()
    typ2docx()


def typ2pdf():
    console.print("[bold green]Converting[/bold green] TYP -> PDF with Typst")
    marker_text = "INSERTED BY TYP2DOCX"
    preamble = [
        "// >>> " + marker_text,
        (HERE / "preamble.typ").read_text().rstrip(),
        "// <<< " + marker_text,
        "",
    ]
    preamble = "\n".join(preamble)
    src = INPUT.read_text()

    try:
        INPUT.write_text(preamble + src)  # insert preamble in place
        run(["typst", "compile", INPUT, DIR / "a.pdf"], check=True)
    except CalledProcessError:
        console.print(
            "[bold red]Error:[/bold red] " + "Failed to compile TYP to PDF",
        )
        raise Exit(1)
    finally:
        # cleanup inserted preamble
        src = INPUT.read_text()
        start = src.find("// >>> " + marker_text)
        end = src.find("// <<< " + marker_text)
        if start != -1 and end != -1:
            end += len("// <<< " + marker_text)
            cleaned = src[:start] + src[end:]
            cleaned = cleaned.lstrip()
            INPUT.write_text(cleaned)


def pdf2docx():
    # TODO: other engines
    console.print("[bold green]Converting[/bold green] PDF -> DOCX with Acrobat")
    try:
        run(
            ["osascript", HERE / "acrobat.applescript", DIR / "a.pdf"],
            cwd=DIR,
            check=True,
        )
    except CalledProcessError:
        console.print(
            "[bold red]Error:[/bold red] "
            + "Failed to convert PDF -> DOCX with Acrobat",
        )
        raise Exit(1)


def typ2typ():
    """Typst to Typst (math only)"""
    console.print("[bold green]Extracting[/bold green] math source code")
    # construct source file, empty equations are omitted
    eqs = [eq for eq in extract_equations(str(INPUT)) if eq[1:-1].strip()]
    console.print(f"[bold green]Extracted[/bold green] {len(eqs)} math blocks")
    src = "\n\n".join(eqs)
    (DIR / "b.typ").write_text(src)


def typ2docx():
    """Typst to DOCX (with Pandoc, math only)"""
    try:
        run(["pandoc", "b.typ", "-o", "b.docx"], cwd=DIR, check=True)
    except CalledProcessError:
        console.print(
            "[bold red]Error:[/bold red] "
            + "Failed to convert Typst to DOCX with Pandoc."
        )
        raise Exit(1)


def docx2docx():
    # Saxon evaluates path relative to the xsl, must be copied
    copy2(HERE / "merge.xslt", DIR / "merge.xslt")
    try:
        run(["sh", HERE / "merge.sh"], cwd=DIR, check=True)
    except CalledProcessError:
        console.print(
            "[bold red]Error:[/bold red] " + "Failed to merge DOCX with Saxon"
        )
        raise Exit(1)


if __name__ == "__main__":
    app()
