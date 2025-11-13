from contextlib import contextmanager
from pathlib import Path


@contextmanager
def TempFile(path: Path, content: str = ""):
    path.write_text(content)
    yield path
    path.unlink(missing_ok=True)
