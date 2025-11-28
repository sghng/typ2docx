#! /usr/bin/env python3
from asyncio import TaskGroup
from pathlib import Path
from shutil import move
from sys import argv
from typing import Annotated, Literal

from typer import Argument, Option, Typer

from convert import Context, branch1, branch2, docx2docx
from convert import install_acrobat as _install_acrobat
from utils import WorkingDirectory, syncify

try:
    idx = argv.index("--")
    TYPST_OPTS = argv[idx + 1 :]
    argv = argv[:idx]
except ValueError:
    TYPST_OPTS = []

if "--install-acrobat" in argv:
    try:
        _install_acrobat(ctx := Context())
    except FileNotFoundError as e:
        ctx.console.print(
            "[bold red]Error:[/bold red] Couldn't find Adobe Acrobat directory at"
            f"{e.filename}, make sure it's installed!"
        )
    else:
        exit(0)
    finally:
        exit(1)


app = Typer()


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
    # these args are defined here for cli help only,
    # they are actually handled at module level
    install_acrobat: Annotated[
        bool,
        Option(
            "--install-acrobat",
            help="Install trusted functions for Adobe Acrobat.",
        ),
    ] = False,
    typst_opts: Annotated[
        list[str],
        Argument(
            help="Options forwarded to the Typst compiler (must follow --).",
            metavar="[-- TYPST_OPT...]",
        ),
    ] = [],
):
    """Convert a Typst project to DOCX format."""

    with WorkingDirectory(debug) as dir:
        ctx = Context(
            dir=dir,
            input=input,
            output=output or Path.cwd() / input.with_suffix(".docx").name,
            engine=engine,
            debug=debug,
            typst_opts=TYPST_OPTS,
        )
        try:
            async with TaskGroup() as tg:
                tg.create_task(branch1(ctx))
                tg.create_task(branch2(ctx))
        except* Exception as eg:
            raise eg.exceptions[0]

        ctx.console.print("[bold green]Merging[/bold green] DOCX")
        await docx2docx(ctx)
        move(ctx.dir / "out.docx", ctx.output)

    ctx.console.print(f"[bold green]Output saved to[/bold green] {ctx.output}")


if __name__ == "__main__":
    app()
