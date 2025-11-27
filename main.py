#! /usr/bin/env python3
from asyncio import TaskGroup
from pathlib import Path
from shutil import move
from sys import argv
from typing import Annotated, Literal

from rich.console import Console
from typer import Argument, Exit, Option, Typer

from convert import Context, branch1, branch2, docx2docx
from utils import WorkingDirectory, syncify

app = Typer()
console = Console()

try:
    idx = argv.index("--")
    TYPST_OPTS = argv[idx + 1 :]
    argv = argv[:idx]
except ValueError:
    TYPST_OPTS = []


@app.command()
@syncify
async def main(
    input: Annotated[Path, Argument(help="Entry point to the Typst project")],
    engine: Annotated[
        Literal["acrobat", "pdfservices"],
        Option("-e", "--engine", help="The engine used to convert PDF to DOCX."),
    ],
    output: Annotated[
        Path | None,
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

    output = output or Path.cwd() / input.with_suffix(".docx").name

    console.print(f"[bold blue]Converting[/bold blue] {input}...")
    if debug:
        console.print(
            "[yellow]Debug mode:[/yellow] "
            "Intermediate files will be kept in ./.typ2docx/"
        )

    with WorkingDirectory(debug) as dir:
        ctx = Context(
            dir=dir,
            input=input,
            output=output,
            engine=engine,
            debug=debug,
            typst_opts=TYPST_OPTS,
            console=console,
        )

        try:
            async with TaskGroup() as tg:
                tg.create_task(branch1(ctx))
                tg.create_task(branch2(ctx))
        except* Exit as eg:
            raise eg.exceptions[0]

        console.print("[bold green]Merging[/bold green] DOCX")
        await docx2docx(ctx)
        move(dir / "out.docx", output)

    console.print(f"[bold green]Output saved to[/bold green] {output}")


if __name__ == "__main__":
    app()
