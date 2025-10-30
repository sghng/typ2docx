#! /usr/bin/env python3

import json
import subprocess
from pathlib import Path

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
    pretty: bool = typer.Option(
        False, "--pretty", "-p", help="Pretty-print JSON output"
    ),
):
    """Extract equations from a Typst project and serialize them to JSON."""
    equations = extract_equations(path)
    if pretty:
        console.print(JSON(json.dumps(equations)))
    else:
        print(json.dumps(equations))


@app.command()
def convert(
    path: str = typer.Argument(..., help="Entry point to the Typst project"),
):
    """Convert a Typst project to DOCX format."""
    console.print(f"[bold blue]Converting[/bold blue] {path}...")
    typ2pdf(Path(path))


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
        result = subprocess.run(["typst", "compile", path, "tmp.pdf"])
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


def main():
    app()


if __name__ == "__main__":
    main()
