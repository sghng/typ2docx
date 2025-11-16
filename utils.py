from asyncio import CancelledError, create_subprocess_exec
from asyncio import run as _run
from contextlib import contextmanager
from functools import wraps
from pathlib import Path
from subprocess import CalledProcessError
from tempfile import TemporaryDirectory


@contextmanager
def WorkingDirectory(debug: bool = False):
    if debug:
        dir = Path.cwd() / ".typ2docx/"
        dir.mkdir(exist_ok=True)
        yield dir
    else:
        with TemporaryDirectory(prefix="typ2docx_") as dir:
            yield Path(dir)


@contextmanager
def TempFile(path: Path, content: str = ""):
    path.write_text(content)
    yield path
    path.unlink(missing_ok=True)


@wraps(create_subprocess_exec)
async def run(*args, **kwargs):
    process = await create_subprocess_exec(*args, **kwargs)
    try:
        if returncode := await process.wait():
            raise CalledProcessError(returncode, args)
    except CancelledError:
        process.kill()
        raise
    finally:
        await process.wait()


def syncify(f):
    return wraps(f)(lambda *args, **kwargs: _run(f(*args, **kwargs)))
