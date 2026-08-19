"""
Where the toolchain's fixed folders live — the ONE place that knows.

Inside the container these are the /opt and /teaching paths the Dockerfile
bakes, and nothing changes: every value below defaults to the container
location. Running NATIVELY on Windows (no container, no WSL2), the launcher
points these at the app's bundled runtime and the working folder by setting
the PLANTOIR_* environment variables before invoking Python.

Why environment variables rather than arguments: four scripts share these
roots, several of them re-invoke each other (deploy.py runs build_site.py),
and an argument would have to be threaded through every call site on both
platforms. The environment crosses those boundaries on its own, and the
container simply never sets it.
"""

import os
import tempfile
from pathlib import Path


def _env_path(name: str, default: str) -> Path:
    value = os.environ.get(name, "").strip()
    return Path(value) if value else Path(default)


# The bundled support/ tree: course lookups, colour schemes, fonts, locales,
# example content, skeletons, Obsidian defaults.
SUPPORT_DIR = _env_path("PLANTOIR_SUPPORT_DIR", "/opt/support")

# The patched Quartz scaffold sites are copied from, with its pre-installed
# node_modules beside it.
QUARTZ_DIR = _env_path("PLANTOIR_QUARTZ_DIR", "/opt/quartz")

# Where these scripts themselves live (deploy.py re-invokes build_site.py).
SCRIPTS_DIR = _env_path("PLANTOIR_SCRIPTS_DIR", "/opt/scripts")

# The teacher's courses. In the container this is the bind mount; natively it
# is <working folder>/courses.
COURSES_DIR = _env_path("PLANTOIR_COURSES_DIR", "/teaching/courses")

# Scratch space for the fast internal build tree. The container builds on its
# own ext4 disk because the 9P mount is slow; natively any local temp dir is
# equally fast.
WORK_DIR = _env_path(
    "PLANTOIR_WORK_DIR",
    "/tmp/quartz-builds" if os.name != "nt" else str(Path(tempfile.gettempdir()) / "quartz-builds"),
)


# The colour emoji font for social sharing cards. In the container it comes
# from the Debian package; natively the launcher points here at the bundled
# copy in the runtime's fonts folder.
EMOJI_FONT = os.environ.get("PLANTOIR_EMOJI_FONT", "").strip() or None

# Node's CLI shims are .cmd batch files on Windows, and subprocess's list
# form resolves an exact file name, never PATHEXT — "npx" alone would be
# "file not found" natively while working perfectly in the container.
NPM = "npm.cmd" if os.name == "nt" else "npm"
NPX = "npx.cmd" if os.name == "nt" else "npx"
WRANGLER = "wrangler.cmd" if os.name == "nt" else "wrangler"


class _WriteOutcome:
    """Shaped like the CompletedProcess the old `tee` subprocess returned, so
    the call sites' returncode/stderr checks read on unchanged."""

    def __init__(self, returncode: int, stderr: bytes):
        self.returncode = returncode
        self.stderr = stderr


def write_file(path, data: bytes) -> _WriteOutcome:
    """
    Drop-in for the historical `subprocess.run(["tee", path], input=...)`
    idiom, which existed to dodge silent write failures over the container's
    9P mount and which fails outright on Windows (no `tee`). A plain write,
    reporting failure the way the old call did.
    """
    try:
        Path(str(path)).write_bytes(data)
        return _WriteOutcome(0, b"")
    except OSError as error:
        return _WriteOutcome(1, str(error).encode("utf-8"))


def merged_output_root(course_dir: Path) -> Path:
    """
    Where a course's built sites land (.merged_output). By default beside the
    course content, as always. PLANTOIR_BUILD_ROOT moves it out of the working
    folder entirely — set by the Windows app so builds never churn inside a
    OneDrive-synced folder (thousands of small files per build, and OneDrive
    both uploads them all and holds locks mid-build).
    """
    build_root = os.environ.get("PLANTOIR_BUILD_ROOT", "").strip()
    if build_root:
        return Path(build_root) / course_dir.name
    return course_dir / ".merged_output"


def mirror_tree(src: Path, dst: Path) -> None:
    """
    The `rsync -a --delete` equivalent for hosts without rsync (Windows
    native): copy what is new or changed (by size and mtime), delete what no
    longer exists. The alternative the code used to fall back on — delete
    the whole tree and re-copy it — runs on every tick of the preview's
    sync watcher, which is a lot of churn for a one-file edit.
    """
    import shutil
    src = Path(src)
    dst = Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    src_entries = {entry.name: entry for entry in src.iterdir()}
    for existing in dst.iterdir():
        if existing.name in src_entries:
            continue
        if existing.is_dir() and not existing.is_symlink():
            shutil.rmtree(existing, ignore_errors=True)
        else:
            try:
                existing.unlink()
            except OSError:
                pass
    for name, entry in src_entries.items():
        target = dst / name
        if entry.is_dir() and not entry.is_symlink():
            if target.exists() and not target.is_dir():
                try:
                    target.unlink()
                except OSError:
                    continue
            mirror_tree(entry, target)
            continue
        try:
            if target.exists():
                s, t = entry.stat(), target.stat()
                if s.st_size == t.st_size and abs(s.st_mtime - t.st_mtime) < 1:
                    continue
            shutil.copy2(entry, target)
        except OSError:
            pass


def link_directory(target: Path, link: Path) -> str:
    """
    Make `link` refer to the directory `target` without copying it, and say
    how ("symlink", "junction", or "copy").

    On Linux/macOS a symlink always works. On Windows, creating a symlink
    needs administrator rights or Developer Mode — precisely what a teacher's
    school-managed laptop refuses — while an NTFS directory JUNCTION needs no
    privilege at all. The copy fallback is last because for node_modules it
    duplicates hundreds of megabytes per section.
    """
    try:
        os.symlink(str(target), str(link))
        return "symlink"
    except OSError:
        pass
    if os.name == "nt":
        try:
            import _winapi
            _winapi.CreateJunction(str(target), str(link))
            return "junction"
        except Exception:
            pass
    import shutil
    shutil.copytree(str(target), str(link), symlinks=True)
    return "copy"
