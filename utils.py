import atexit
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
    _EXECUTOR = ProcessPoolExecutor()
    atexit.register(_EXECUTOR.shutdown)

    @run.register
    async def _(func: Callable, *args, **kwargs):
        return await get_running_loop().run_in_executor(
            _EXECUTOR, partial(func, *args, **kwargs)
        )


@run.register
async def _(program: str | Path, *args, **kwargs):
    process = await create_subprocess_exec(program, *args, **kwargs)
    try:
        stdout, _ = await process.communicate()
        if returncode := process.returncode:
            raise CalledProcessError(returncode, (program, *args))
        return stdout
    except CancelledError:
        process.kill()
        raise
    finally:
        await process.wait()


def syncify(f):
    return wraps(f)(lambda *args, **kwargs: _run(f(*args, **kwargs)))


class Listener:
    def __init__(self, port=0):
        self.msg: str
        listener = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(*_):
                pass

            def do_POST(self):
                listener.msg = self.rfile.read(
                    int(self.headers.get("Content-Length", 0))
                ).decode()
                self.send_response(200)
                self.flush_headers()

        self._server = HTTPServer(("", port), Handler)
        self.port = self._server.server_port

    def __call__(self):
        self._server.handle_request()
        self._server.server_close()
        return self.msg
