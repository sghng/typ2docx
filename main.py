#! /usr/bin/env python3
import subprocess
from pathlib import Path
from time import sleep

import typer
from extract import extract as extract_equations  # ty: ignore[unresolved-import]
from rich.console import Console
from rich.json import JSON

app = typer.Typer(
    name="typ2docx",
    help="Converting Typst project to DOCX format.",
    rich_markup_mode="rich",
)
console = Console()


@app.command()
def extract(
    path: str = typer.Argument(help="Entry point to the Typst project"),
):
    """Extract equations from a Typst project and serialize them to JSON."""
    import json

    equations = extract_equations(path)
    console.print(JSON(json.dumps(equations)))


@app.command()
def convert(
    path: str = typer.Argument(..., help="Entry point to the Typst project"),
):
    """Convert a Typst project to DOCX format."""
    from concurrent.futures import ThreadPoolExecutor

    path: Path = Path(path)
    console.print(f"[bold blue]Converting[/bold blue] {path}...")
    with ThreadPoolExecutor(max_workers=2) as executor:
        future1 = executor.submit(branch1, path)
        future2 = executor.submit(branch2, path)

        # Wait for both to complete
        result1 = future1.result()
        result2 = future2.result()

    subprocess.run(["./merge.sh"])


def branch1(path: Path):
    typ2pdf(path)
    pdf2docx(path)


def branch2(path: Path):
    # construct source file
    eqs = extract_equations(str(path))
    src = "\n\n".join(eqs)
    with open("typ2docx.b.typ", "w") as f:
        f.write(src)

    # use pandoc to convert to DOCX
    subprocess.run(["pandoc", "typ2docx.b.typ", "-o", "typ2docx.b.docx"])


def marker(i: int):
    return rf"\@\@MATH{i}\@\@"


def typ2pdf(path: Path):
    marker_text = "INSERTED BY TYP2DOCX"
    preamble = [
        "// >>> " + marker_text,
        Path("preamble.typ").read_text().rstrip(),
        "// <<< " + marker_text,
        "",
    ]
    preamble = "\n".join(preamble)
    src = path.read_text()

    try:
        path.write_text(preamble + src)  # insert preamble in place
        result = subprocess.run(["typst", "compile", path, "typ2docx.a.pdf"])
        if result.returncode != 0:
            raise RuntimeError("Typst compilation failed")

    finally:
        # cleanup inserted preamble
        src = path.read_text()
        start = src.find("// >>> " + marker_text)
        end = src.find("// <<< " + marker_text)
        if start != -1 and end != -1:
            end += len("// <<< " + marker_text)
            cleaned = src[:start] + src[end:]
            cleaned = cleaned.lstrip()
            path.write_text(cleaned)


def pdf2docx(path: Path):
    # TODO: other engines
    result = subprocess.run(["./acrobat.applescript"])
    if result.returncode != 0:
        raise RuntimeError("Failed to convert pdf -> docx with Acrobat")
    # sleep(1)  # for safety


def main():
    app()


if __name__ == "__main__":
    main()
