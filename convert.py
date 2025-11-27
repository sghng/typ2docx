from os import environ, pathsep
from pathlib import Path
from shutil import move
from subprocess import CalledProcessError
from sys import executable, platform

from pydantic import BaseModel, ConfigDict
from pypdf import PdfWriter
from rich.console import Console
from typer import Exit

from extract import extract
from pdfservices import export
from utils import Listener, TempFile, run

HERE: Path = Path(__file__).parent


class Context(BaseModel):
    model_config = ConfigDict(frozen=True, arbitrary_types_allowed=True)

    dir: Path
    input: Path
    output: Path
    engine: str
    debug: bool = False
    typst_opts: list[str]
    console: Console


async def branch1(ctx: Context):
    await typ2pdf(ctx)
    await pdf2docx(ctx)


async def branch2(ctx: Context):
    await typ2typ(ctx)
    await typ2docx(ctx)


async def typ2pdf(ctx: Context):
    ctx.console.print("[bold green]Converting[/bold green] TYP -> PDF with Typst")
    try:
        with TempFile(
            ctx.input.with_name(f".typ2docx.{ctx.input.name}"),
            (HERE / "preamble.typ").read_text() + ctx.input.read_text(),
        ) as input:
            await run("typst", "compile", *ctx.typst_opts, input, ctx.dir / "a.pdf")
    except PermissionError:
        ctx.console.print(
            "[bold red]Error:[/bold red] Failed to compile Typst project to PDF. "
            "Write access to the project directory is required!"
        )
    except CalledProcessError:
        ctx.console.print(
            "[bold red]Error:[/bold red] Failed to compile Typst project to PDF."
        )
    else:
        return
    raise Exit(1)


async def _pdf2docx_pdfservices(ctx: Context):
    ctx.console.print(
        "[bold green]Converting[/bold green] PDF -> DOCX with Adobe PDFServices API"
    )
    try:
        await run(export, ctx.dir / "a.pdf")
    except ValueError:
        ctx.console.print(
            "[bold red]Error:[/bold red] Make sure you have "
            "PDF_SERVICES_CLIENT_ID and PDF_SERVICES_CLIENT_SECRET "
            "set in environment!",
        )
    except RuntimeError as e:
        ctx.console.print(
            "[bold red]Error:[/bold red] Failed to convert PDF -> DOCX "
            f"with Adobe PDFServices API: {e}"
        )
    else:
        return
    raise Exit(1)


async def _pdf2docx_acrobat(ctx: Context):
    ctx.console.print(
        "[bold green]Converting[/bold green] PDF -> DOCX with Adobe Acrobat"
    )

    # FIXME: this won't work here, must be installed before Acrobat is launched
    script = (
        Path.home()
        / "Library/Application Support/Adobe/Acrobat/DC/JavaScripts"
        / "typ2docx.js"
    )
    script.parent.mkdir(exist_ok=True)
    script.unlink(missing_ok=True)
    script.symlink_to(HERE / "typ2docx.js")

    listener = Listener()
    injector = PdfWriter(ctx.dir / "a.pdf")
    injector.add_js(
        f"const PORT = {listener.port};\n" + (HERE / "export.js").read_text()
    )
    with open(ctx.dir / "a-injected.pdf", "wb") as f:
        injector.write(f)

    try:
        await run("open", "-g", "-a", "Adobe Acrobat", ctx.dir / "a-injected.pdf")
        # TODO: handle errors
        path = Path(listener())
        if platform == "darwin":
            path = Path("/", *path.parts[2:])
        # TODO: get the dir for non Pro version of Acrobat
        # TODO: closing Acrobat afterwards
        move(path, ctx.dir / "a.docx")
    except CalledProcessError:
        ctx.console.print(
            "[bold red]Error:[/bold red] Make sure Adobe Acrobat is installed!"
        )
    except FileNotFoundError:
        ctx.console.print(
            "[bold red]Error:[/bold red] Couldn't find the Acrobat exported file!"
        )
    else:
        return
    raise Exit(1)


async def pdf2docx(ctx: Context):
    match ctx.engine:
        case "pdfservices":
            await _pdf2docx_pdfservices(ctx)
        case "acrobat":
            await _pdf2docx_acrobat(ctx)
        case _:
            raise NotImplementedError(f"Unknown engine: {ctx.engine}")


async def typ2typ(ctx: Context):
    """Typst to Typst (math only)"""

    ctx.console.print("[bold green]Extracting[/bold green] math source code")

    try:
        root = ctx.typst_opts[ctx.typst_opts.index("--root") + 1]
    except ValueError:
        root = None
    except IndexError:
        ctx.console.print(
            "[bold red]Error:[/bold red] "
            "Failed to extract equations. The --root flag requires a value."
        )
        raise Exit(1)

    try:
        eqs: list[str] = await run(extract, str(ctx.input), root)
    except BaseException as e:  # PanicException is derived from BaseException
        if type(e).__name__ == "PanicException":
            ctx.console.print(
                "[bold red]Error:[/bold red] "
                "Failed to extract equations, make sure the Typst project compiles."
            )
            raise Exit(1)
        else:
            raise e

    ctx.console.print(f"[bold green]Extracted[/bold green] {len(eqs)} math blocks")
    eqs = [eq for eq in eqs if eq[1:-1].strip()]  # empty equations are omitted
    src = "\n\n".join(eqs)
    (ctx.dir / "b.typ").write_text(src)


async def typ2docx(ctx: Context):
    """Typst to DOCX (with Pandoc, math only)"""
    ctx.console.print("[bold green]Converting[/bold green] TYP -> DOCX with Pandoc")
    try:
        await run("pandoc", "b.typ", "-o", "b.docx", cwd=ctx.dir)
    except CalledProcessError:
        ctx.console.print(
            "[bold red]Error:[/bold red] Failed to convert Typst -> DOCX with Pandoc"
        )
        raise Exit(1)


async def docx2docx(ctx: Context):
    shell, ext = ("pwsh", "ps1") if platform == "win32" else ("sh", "sh")
    try:
        await run(
            shell,
            HERE / f"merge.{ext}",
            cwd=ctx.dir,
            env=environ
            | {"PATH": f"{Path(executable).parent}{pathsep}{environ['PATH']}"},
        )
    except CalledProcessError:
        ctx.console.print("[bold red]Error:[/bold red] Failed to merge DOCX with Saxon")
        raise Exit(1)
