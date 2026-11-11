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

# Engines a site carries only when one of its pages asks for them (#454:
# Paged.js for printable pages; #455 adds Pyodide), each in its own folder.
# Beside the Quartz scaffold, so the container's /opt/vendor and Windows'
# <runtime>\vendor (PLANTOIR_QUARTZ_DIR is <runtime>\quartz there) both follow
# without a variable of their own; set PLANTOIR_VENDOR_DIR to put it elsewhere.
VENDOR_DIR = _env_path("PLANTOIR_VENDOR_DIR", str(QUARTZ_DIR.parent / "vendor"))

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


# The one Node deprecation the site build is known to print, and silenced (#640).
# Quartz v4.5.0's dependencies require Node's built-in `punycode`, and from
# Node 21 every Quartz build prints "[DEP0040] DeprecationWarning: The
# `punycode` module is deprecated" to stderr, which reaches the teacher's
# console as machinery (CLAUDE.md rule 1). Node 20 printed nothing. Only that
# one code is silenced - NOT NODE_NO_WARNINGS, which hides every warning,
# including the ones a real break would print. `--disable-warning` is accepted
# from Node 20.11 (measured on 20.20.2 and 22.23.4): Windows' runtime ran
# Node 20 until #675 and took the flag safely; both run 22.23.4 now.
NODE_QUIET_DEPRECATION = "--disable-warning=DEP0040"


def node_environment(base) -> dict:
    """
    A copy of `base` (an environment mapping) for running Node: everything in
    it kept, with NODE_OPTIONS carrying NODE_QUIET_DEPRECATION. A NODE_OPTIONS
    already set is kept and added to, and the flag is never written twice.
    Every node the build starts - Quartz itself and the figure helper - is
    given this, so none of them prints the punycode line.
    """
    environment = dict(base)
    existing = environment.get("NODE_OPTIONS", "").strip()
    options = existing.split()
    if NODE_QUIET_DEPRECATION not in options:
        options.append(NODE_QUIET_DEPRECATION)
    environment["NODE_OPTIONS"] = " ".join(options)
    return environment


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


# ---------------------------------------------------------------------------
# Which toolchain built a site (#746)
#
# A built site is stamped with the toolchain that built it, and a deploy
# rebuilds a site whose stamp is not the current toolchain's. Without it a
# change to the toolchain - a stylesheet, a script, a patch - reached a site
# only when something ELSE forced a build: 1.9.1's tick-box rule (#693) and
# quiz print rule (#733) were in the app, in the working folder's .toolchain
# and in a freshly tagged image, and a site redeployed under 1.9.1 still
# served 1.9.0's stylesheet, because the deploy found the site up to date
# (nothing the teacher wrote had changed) and the one rebuild it made ran in
# the folder's old workspace. documentation/05-build-pipeline.md ->
# "Which toolchain built a site (#746)" has the measurement.
#
# The identity is PLANTOIR_TOOLCHAIN_ID when a launcher sets it - the mac's
# launchers create each workspace with its image's tag, `teaching-quartz:src-
# <hash of the recipe>`, so the shell can compare a stamp without Python -
# and otherwise a hash of the toolchain files these scripts read (Windows,
# which runs them natively). Either way a stamp the current toolchain did not
# write, or no stamp at all, means "build again": the safe direction, since
# a wrong answer that way costs one build and the other way publishes a stale
# site and says it succeeded.
# ---------------------------------------------------------------------------
TOOLCHAIN_ID_VARIABLE = "PLANTOIR_TOOLCHAIN_ID"

# Beside `.build-started`, in the folder that holds `public/`. Hidden, like
# it, so the freshness checks never count it as content and it is never
# published. contracts/app-rules.json -> buildFreshness.builtWithToolchain.
BUILT_WITH_TOOLCHAIN_MARKER = ".built-with-toolchain"

# Names never part of the toolchain's identity: Python's own caches, which
# appear beside the scripts the first time they are imported, and Node's
# packages, which are pinned by the recipe rather than read from it.
_NOT_THE_TOOLCHAIN = {"__pycache__", "node_modules"}


# The bundled runtime's own record of what it carries (Windows: <runtime>\
# manifest.json, written by fetch-runtime.ps1 and naming every pin - node,
# python, quartz, wrangler, the emoji font, the vendored engines). Beside the
# Quartz scaffold, as VENDOR_DIR is. Part of the identity because the four
# roots below do not cover the runtime: Quartz's ROOT files (quartz.layout.ts,
# where several patches land), node_modules and the vendored engines are not
# hashed, so a runtime-only change (#764's Python, a Quartz patch re-applied,
# an engine bumped) would otherwise leave every site "built by this version".
# documentation/05-build-pipeline.md -> "Which toolchain built a site (#746)"
# -> "Windows". The container has no such file, and the mac names its
# toolchain through PLANTOIR_TOOLCHAIN_ID anyway, so nothing changes there.
RUNTIME_MANIFEST_NAME = "manifest.json"

# Where the toolchain's id is remembered between runs, inside the folder
# PLANTOIR_BUILD_ROOT names (Windows only: %LOCALAPPDATA%\Plantoir\builds\<id>).
TOOLCHAIN_ID_CACHE_NAME = ".toolchain-id.cache"

# A file changed this close to "now" is not trusted to a stat fingerprint
# (git's racy-entry rule): an edit in the same clock tick and to the same size
# would leave size and mtime as they were, and the cached id would be wrong.
_RACY_SECONDS = 2


def _toolchain_roots():
    return (
        ("scripts", SCRIPTS_DIR),
        ("support", SUPPORT_DIR),
        ("contracts", CONTRACTS_DIR),
        ("quartz", QUARTZ_DIR / "quartz"),
    )


def _the_toolchain_files():
    """Every file the identity covers, as (label, relative path, full path,
    size, mtime in ns), sorted by label and path. Stat only - nothing is read,
    so a OneDrive file that is only in the cloud is not downloaded by asking.
    os.scandir and DirEntry.stat, because on Windows the directory listing
    already carries the size and the time: measured on a Lenovo 20QES70500
    (i5-8365U, Windows 11 26200), 13,029 files, 0.34 s against os.walk and
    os.stat's 0.94 s."""
    found = []
    for label, root in _toolchain_roots():
        if not root.is_dir():
            continue
        pending = [(str(root), "")]
        while pending:
            folder, prefix = pending.pop()
            try:
                with os.scandir(folder) as listing:
                    entries = list(listing)
            except OSError:
                continue
            for entry in entries:
                name = entry.name
                if name.startswith("."):
                    continue
                try:
                    if entry.is_dir(follow_symlinks=False):
                        if name in _NOT_THE_TOOLCHAIN:
                            continue
                        pending.append((entry.path, prefix + name + "/"))
                        continue
                    if entry.is_dir():
                        # A link to a folder is not followed, as os.walk did not.
                        continue
                    if name.endswith(".pyc"):
                        continue
                    status = entry.stat(follow_symlinks=True)
                except OSError:
                    continue
                found.append((label, prefix + name, entry.path, status.st_size, status.st_mtime_ns))
    manifest = QUARTZ_DIR.parent / RUNTIME_MANIFEST_NAME
    try:
        status = manifest.stat()
        if manifest.is_file():
            found.append(("runtime", RUNTIME_MANIFEST_NAME, str(manifest), status.st_size, status.st_mtime_ns))
    except OSError:
        pass
    order = {"scripts": 0, "support": 1, "contracts": 2, "quartz": 3, "runtime": 4}
    found.sort(key=lambda item: (order[item[0]], item[1]))
    return found


def _fingerprint_of(files) -> str:
    """Names, sizes and times only - what says, without reading anything,
    that nothing has changed since the id was last worked out. The roots'
    absolute paths are in it too, because the scripts can come from either
    .toolchain or the working folder itself (deploy.ps1's Enter-NativeRuntime)."""
    import hashlib
    digest = hashlib.sha256()
    for label, root in _toolchain_roots():
        digest.update(f"root {label} {root}\n".encode("utf-8", "surrogateescape"))
    digest.update(f"root runtime {QUARTZ_DIR.parent / RUNTIME_MANIFEST_NAME}\n".encode("utf-8", "surrogateescape"))
    for label, relative, _path, size, mtime in files:
        digest.update(f"{label}/{relative}\0{size}\0{mtime}\n".encode("utf-8", "surrogateescape"))
    return "v1-" + digest.hexdigest()


def _hash_of_the_contents(files) -> str:
    """The identity itself: every file by relative path and CONTENT."""
    import hashlib
    digest = hashlib.sha256()
    for label, relative, path, _size, _mtime in files:
        try:
            with open(path, "rb") as handle:
                content = handle.read()
        except OSError:
            continue
        digest.update(f"{label}/{relative}\0".encode("utf-8", "surrogateescape"))
        digest.update(hashlib.sha256(content).digest())
    return "files-" + digest.hexdigest()[:16]


def _toolchain_id_cache():
    """Where the id is remembered, or None. Only when PLANTOIR_BUILD_ROOT is
    set - the native Windows run - so the container never reads or writes one."""
    build_root = os.environ.get("PLANTOIR_BUILD_ROOT", "").strip()
    if not build_root:
        return None
    return Path(build_root) / TOOLCHAIN_ID_CACHE_NAME


def _read_cached_id(cache: Path, fingerprint: str):
    try:
        lines = cache.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return None
    if len(lines) != 2 or lines[0] != fingerprint or not lines[1].startswith("files-"):
        return None
    return lines[1]


def _remember_id(cache: Path, fingerprint: str, identity: str, files) -> None:
    """Written whole through a file of this process's own and moved into
    place. Any failure is ignored - another process reading the cache can
    refuse the move on Windows - and the id is simply worked out next time."""
    import time
    racy_since = time.time_ns() - _RACY_SECONDS * 1_000_000_000
    for _label, _relative, _path, _size, mtime in files:
        if mtime >= racy_since:
            return
    temporary = cache.with_name(f"{cache.name}.{os.getpid()}.tmp")
    try:
        cache.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_text(fingerprint + "\n" + identity + "\n", encoding="utf-8")
        os.replace(temporary, cache)
    except OSError:
        try:
            temporary.unlink()
        except OSError:
            pass


def _hash_of_the_toolchain_files() -> str:
    """A hash of every file under the scripts, support, contracts and the
    Quartz scaffold's own sources, by relative path and content, and of the
    bundled runtime's manifest when there is one. Measured in the container on
    2026-11-01: 12,911 files in 0.3 s. Measured natively on Windows on
    2026-11-11 (Lenovo 20QES70500, i5-8365U, Windows 11 26200, Defender on,
    a working folder outside OneDrive): 13,029 files, 40.8 MB, 3.0 s warm and
    131 s on the first run after the files had gone cold - so where
    PLANTOIR_BUILD_ROOT is set the id is remembered against a stat-only
    fingerprint of the same files and only worked out again when that
    changes."""
    files = _the_toolchain_files()
    cache = _toolchain_id_cache()
    if cache is None:
        return _hash_of_the_contents(files)
    fingerprint = _fingerprint_of(files)
    remembered = _read_cached_id(cache, fingerprint)
    if remembered is not None:
        return remembered
    identity = _hash_of_the_contents(files)
    _remember_id(cache, fingerprint, identity, files)
    return identity


def current_toolchain_id() -> str:
    """The identity of the toolchain this process is running."""
    named = os.environ.get(TOOLCHAIN_ID_VARIABLE, "").strip()
    if named:
        return named
    return _hash_of_the_toolchain_files()


def built_with_toolchain_marker(section_dir: Path) -> Path:
    return Path(section_dir) / BUILT_WITH_TOOLCHAIN_MARKER


def toolchain_that_built(section_dir: Path):
    """The identity a section's built site was stamped with, or None."""
    try:
        text = built_with_toolchain_marker(section_dir).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    text = text.strip()
    if not text:
        return None
    return text


def site_was_built_by_this_toolchain(section_dir: Path, toolchain_id=None) -> bool:
    """True only when the section's built site carries THIS toolchain's stamp."""
    if toolchain_id is None:
        toolchain_id = current_toolchain_id()
    return toolchain_that_built(section_dir) == toolchain_id


def note_the_toolchain_that_built(section_dir: Path, toolchain_id: str) -> None:
    """Stamp a section's built site. Written whole and moved into place; if
    that fails, the old stamp is removed instead, so a site this toolchain
    did not finish stamping is rebuilt rather than taken as current."""
    marker = built_with_toolchain_marker(section_dir)
    temporary = marker.with_name(marker.name + ".writing")
    try:
        temporary.write_text(toolchain_id + "\n", encoding="utf-8")
        os.replace(temporary, marker)
    except OSError as error:
        print(f"⚠️  Could not note which version of Plantoir built this site: {error}")
        for leftover in (temporary, marker):
            try:
                leftover.unlink()
            except OSError:
                pass
