from asyncio import (
    CancelledError,
    create_subprocess_exec,
    get_running_loop,
    to_thread,
)
from asyncio import run as _run
from collections.abc import Callable
from concurrent.futures import ProcessPoolExecutor
from contextlib import contextmanager
from functools import partial, singledispatch, wraps
from http.server import BaseHTTPRequestHandler, HTTPServer
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
        f"{type(func_or_program).__name__!r}"
    )


if get_config_var("Py_GIL_DISABLED"):
    run.register(to_thread)
else:

    @run.register
    async def _(func: Callable, *args, **kwargs):
        with ProcessPoolExecutor() as executor:
            return await get_running_loop().run_in_executor(
                executor, partial(func, *args, **kwargs)
            )


@run.register
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


class Listener:
    def __init__(self, port=0):
        class Handler(BaseHTTPRequestHandler):
            log_message = lambda *_: None

            def do_POST(handler):
                self.msg = handler.rfile.read(
                    int(handler.headers.get("Content-Length", 0))
                ).decode()

        self.server = HTTPServer(("127.0.0.1", port), Handler)
        self.port = self.server.server_port
        self.msg: str

    def __call__(self):
        self.server.handle_request()
        return self.msg
