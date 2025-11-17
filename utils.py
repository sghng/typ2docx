from asyncio import CancelledError, create_subprocess_exec, get_running_loop, to_thread
from asyncio import run as _run
from collections.abc import Callable
from concurrent.futures import ProcessPoolExecutor
from contextlib import contextmanager
from functools import singledispatch, wraps
from pathlib import Path
from subprocess import CalledProcessError
from sysconfig import get_config_var
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


@singledispatch
async def run(func_or_program, *args, **kwargs):
    raise TypeError(
        "run() argument must be a Callable, str, or Path, not "
        f"{type(func_or_program).__name__}"
    )


_HAS_GIL = get_config_var("Py_GIL_DISABLED") != 1


@run.register
async def _(func: Callable, *args, **kwargs):
    if _HAS_GIL:
        with ProcessPoolExecutor() as executor:
            return await get_running_loop().run_in_executor(
                executor, func, *args, **kwargs
            )
    else:
        return await to_thread(func, *args, **kwargs)


@run.register
@wraps(create_subprocess_exec)
async def _(program: str | Path, *args, **kwargs):
    process = await create_subprocess_exec(program, *args, **kwargs)
    try:
        if returncode := await process.wait():
            raise CalledProcessError(returncode, (program, *args))
    except CancelledError:
        process.kill()
        raise
    finally:
        await process.wait()


def syncify(f):
    return wraps(f)(lambda *args, **kwargs: _run(f(*args, **kwargs)))
