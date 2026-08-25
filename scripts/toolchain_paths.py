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

# The Plantoir contract: the shared case data both apps' test suites run, and
# which these scripts now read too, so one rule has one home rather than three
# implementations that drift. See scripts/contracts.py for what reads it.
#
# It has to be BAKED INTO THE IMAGE (Dockerfile: COPY contracts/), because the
# container's only bind mount is `courses` — the working folder's .toolchain/
# is not mounted and the app bundle is on the host, so neither can be read
# from in here.
CONTRACTS_DIR = _env_path("PLANTOIR_CONTRACTS_DIR", "/opt/contracts")

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


def hardlink_mirror(src: Path, dst: Path) -> None:
    """
    Mirror src into dst by HARDLINKING each file (falling back to a copy
    when a link is refused or crosses volumes). Used for the Media folder on
    native Windows instead of a junction: a junction is an NTFS mount
    point, and current Windows refuses to TRAVERSE user-made mount points
    during directory enumeration (WinError 448) - which killed the coverage
    builder's walk over content/ in the first real end-user test. Hardlinks
    are ordinary directory entries: nothing to distrust, no privileges
    needed, and no bytes copied.
    """
    import shutil
    src = Path(src)
    dst = Path(dst)
    # A junction left here by an OLDER build must go first: mkdir would
    # accept it and iterdir would then enumerate THROUGH it — the very
    # traversal Windows refuses (WinError 448). lstat-based, never follows.
    remove_stale_reparse_point(dst)
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
            hardlink_mirror(entry, target)
            continue
        try:
            if target.exists():
                s, t = entry.stat(), target.stat()
                if s.st_ino and s.st_ino == t.st_ino and s.st_dev == t.st_dev:
                    continue  # already the very same file
                target.unlink()
            try:
                os.link(str(entry), str(target))
            except OSError:
                shutil.copy2(str(entry), str(target))
        except OSError:
            pass


def remove_stale_reparse_point(path: Path) -> bool:
    """
    Remove a junction or symlink an OLDER build left at `path` (Windows
    only; no-op elsewhere and for real folders). Callers must use this
    BEFORE any exists()/stat() on the path: a stat goes THROUGH the reparse
    point and raises WinError 448 before repair code would run, while this
    check uses lstat, which never traverses. Removing the link never
    touches its target.
    """
    if os.name != "nt" or not is_reparse_point(path):
        return False
    try:
        os.rmdir(str(path))
        return True
    except OSError:
        try:
            os.unlink(str(path))
            return True
        except OSError:
            return False


def is_reparse_point(path: Path) -> bool:
    """True for junctions and symlinks alike (Windows); False elsewhere."""
    try:
        import stat as stat_module
        attributes = os.lstat(str(path)).st_file_attributes
        return bool(attributes & stat_module.FILE_ATTRIBUTE_REPARSE_POINT)
    except (OSError, AttributeError):
        return False


def link_directory(target: Path, link: Path) -> str:
    """
    Make `link` carry the directory `target`'s contents without copying the
    bytes, and say how ("symlink", "hardlinks", or "copy").

    On Linux/macOS a symlink always works. On Windows, NO reparse point of
    any kind is ever created: symlinks need privileges a school-managed
    laptop refuses, and a junction is an NTFS mount point that current
    Windows refuses to TRAVERSE from the installed app's processes
    (WinError 448, "untrusted mount point") — even a bare stat through one
    dies. Both smoke-test failures of 2026-08-20 were exactly this, at two
    different call sites, so the rule lives here at the single choke point
    every call site uses: Windows gets a hardlink MIRROR — ordinary
    directory entries, no privileges, no copied bytes, nothing to distrust.
    """
    if os.name == "nt":
        hardlink_mirror(target, link)
        return "hardlinks"
    try:
        os.symlink(str(target), str(link))
        return "symlink"
    except OSError:
        pass
    import shutil
    shutil.copytree(str(target), str(link), symlinks=True)
    return "copy"
