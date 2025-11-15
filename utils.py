from asyncio import CancelledError, create_subprocess_exec
from asyncio import run as aiorun
from contextlib import contextmanager
from functools import wraps
from pathlib import Path
from subprocess import CalledProcessError


@contextmanager
def TempFile(path: Path, content: str = ""):
    path.write_text(content)
    yield path
    path.unlink(missing_ok=True)


@wraps(create_subprocess_exec)
async def run(*args, **kwargs):
    process = await create_subprocess_exec(*args, **kwargs)
    try:
        returncode = await process.wait()
    except CancelledError:
        process.terminate()
        raise
    if returncode:
        raise CalledProcessError(returncode, args)


def syncify(f):
    return wraps(f)(lambda *args, **kwargs: aiorun(f(*args, **kwargs)))
