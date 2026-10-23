#!/usr/bin/env python3
"""
Runnable Swift (#493): which blocks need compiling, and what the site gets.

A ```swift run block on a page that opts in (`codeRunner: true`) runs in the
student's browser as a small WebAssembly program, compiled ahead of time:
Swift has no interpreter a browser can carry. The compiling happens in a
SECOND image, `teaching-quartz-swift:src-<hash>` (support/swift), which the
launcher on the host starts only when a preview has blocks no earlier build
compiled - a teacher who never writes Swift never downloads it. The build
itself never compiles: it runs in the main container, which has no way to
start another one. On Windows (#570), which has no container, preview.ps1
runs `plan` with the bundled Python, gets Swift ready the first time with
swift_windows_fetch.py and compiles with swift_windows_compile.py - the same
compile.py, adjusted for the host - and the build's `prepare` is this one.

So there are two halves, and this module is both:

* `plan` - run by the LAUNCHER through `docker exec`, before the build
  (`python3 /opt/scripts/swift_blocks.py plan --course=C --format=lines`). It
  reads the course's own pages, finds every Swift block on a page that opts
  in, and writes each one the cache does not hold yet into a job folder of
  this run's own (review S3: two builds of one course never share one). It
  prints one JSON line: where the cache is, where the jobs are, how many.
  It reads more pages than the build will show (hidden pages, other
  sections): that costs a compile, never a wrong answer.
* `prepare` - run by build_site.py on every build (the ALWAYS section),
  after the launcher compiled: each block's binary is copied into the
  site's quartz/static/swift-wasm/, quartz/plantoir-runners/swift.json tells
  the site's transformer which blocks have one, and every block that has
  none is a problem - a `plantoir: error:` line and ONE folder problem
  (siteHealth -> swiftCouldNotBePrepared). The build is never stopped (#493
  ruling Q1): the preview has to open so the teacher can fix the block.

The KEY of a block is the SHA-256 of its normalised code (`normalise`: each
line's trailing spaces off, the common indentation off, blank lines at either
end dropped) - exactly the text that is compiled, so a diagnostic's line maps
back to the teacher's file. The site's transformer computes the same key
from what its own parser read (codeRunnerRule.ts, normaliseProgram; the
contract's codeRunnerBlocks.swift.cacheKey.cases pin both). The cache lives
beside the course's built sites, outside the teacher's folder:

    <builds>/<CODE>/.swift-cache/<toolchain id>/<key>.wasm and <key>.json
    <builds>/<CODE>/.swift-cache/jobs/<run>/<key>.swift   (while compiling)
    <builds>/<CODE>/.swift-cache/state.json               (only when the
                                                           launcher could not
                                                           compile at all)

The TOOLCHAIN ID hashes the Swift image's recipe files, which state the
toolchain, SDK and binaryen pins, the base image, every flag and the PATH -
so a changed pin or flag compiles everything again, and nothing else does
(#485's engine_id pattern; a hand-bumped version string would miss a move).
The key never depends on the binary (review S4).

Contract: contracts/shared-rules.json -> codeRunnerBlocks.swift.
"""

import hashlib
import json
import os
import re
import secrets
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import page_features  # noqa: E402
import toolchain_paths  # noqa: E402

FENCE = "swift"
CACHE_FOLDER = ".swift-cache"
JOBS_FOLDER = "jobs"
# The launcher's logs, one per run (implementation review N3).
LOGS_FOLDER = "logs"
STATE_FILE = "state.json"
STATIC_FOLDER = "swift-wasm"
MANIFEST = Path("plantoir-runners") / "swift.json"

# The Swift image's recipe: what the toolchain id is made of (and what the
# launcher hashes, with the rest of support/swift, to tag the image).
RECIPE_FILES = ("Dockerfile", "compile.py", "ReadLineShim.swift", "FlushBeforeRead.c")

PRUNE_DAYS = 90
# A job folder no run cleaned up (a killed launcher) is removed after a day.
ORPHAN_JOB_SECONDS = 86400

# The first error the compiler names, as `main.swift:<line>:<column>: error: ...`.
FIRST_ERROR = re.compile(r"^main\.swift:(\d+):\d+: error: (.*)$", re.M)

# The trailing whitespace taken off each line - explicit, so the site's
# TypeScript (codeRunnerRule.ts) takes off the same characters.
TRAILING = " \t\r\f\v"


def normalise(body: str):
    """
    The code that is compiled, from a block's body, and how many blank lines
    were dropped from its top: split on "\\n", each line's trailing spaces
    and tabs off, the indentation every non-blank line shares off, and blank
    lines at the start and the end dropped. Answers (text, dropped).
    """
    lines = [line.rstrip(TRAILING) for line in body.split("\n")]
    shared = None
    for line in lines:
        if line == "":
            continue
        indent = line[:len(line) - len(line.lstrip(" \t"))]
        if shared is None:
            shared = indent
        else:
            common = 0
            while common < len(shared) and common < len(indent) and shared[common] == indent[common]:
                common += 1
            shared = shared[:common]
    if shared:
        lines = [line[len(shared):] if line != "" else line for line in lines]
    dropped = 0
    while lines and lines[0] == "":
        lines.pop(0)
        dropped += 1
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines), dropped


def key_of(body: str) -> str:
    """A block's cache key: SHA-256 of its normalised code, as hex."""
    text, _ = normalise(body)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# On Windows (#570) the id also hashes the compile wrapper and the pins of
# what is fetched (codeRunnerBlocks.swift.cache.toolchainIdFromOnWindows).
WINDOWS_RECIPE_FILE = "swift_windows_compile.py"


def toolchain_id(swift_dir=None, windows=None, scripts_dir=None) -> str:
    """16 hex: SHA-256 over the recipe files' names and bytes, in order.

    On Windows each file's CR LF is made LF first (a Windows checkout writes
    CR LF, and the id must not differ by accident), and the Windows compile
    wrapper and the hashes of what swift_windows_fetch.py fetches follow, so
    a Windows cache and a Mac cache never share an id for different
    compilers. The Mac's id is exactly what it was: nothing is normalised
    there."""
    windows = (os.name == "nt") if windows is None else windows
    folder = Path(swift_dir) if swift_dir is not None else toolchain_paths.SUPPORT_DIR / "swift"
    digest = hashlib.sha256()

    def add(name: str, data: bytes) -> None:
        digest.update(name.encode("utf-8") + b"\0")
        digest.update(data.replace(b"\r\n", b"\n") if windows else data)
        digest.update(b"\0")
    for name in RECIPE_FILES:
        add(name, (folder / name).read_bytes())
    if windows:
        scripts = Path(scripts_dir) if scripts_dir is not None else Path(__file__).resolve().parent
        add(WINDOWS_RECIPE_FILE, (scripts / WINDOWS_RECIPE_FILE).read_bytes())
        import swift_windows_fetch
        digest.update(b"swiftWindows\0" + swift_windows_fetch.id_digest() + b"\0")
    return digest.hexdigest()[:16]


def swift_fences(body: str, opted_in) -> list:
    """The page's runnable Swift blocks, read by the build's fence reader
    (page_features.runner_fences): [{"line", "body", "n"}], n counting the
    page's Swift blocks from 1."""
    found = []
    for runner in page_features.runner_fences(body, opted_in):
        if runner["fence"] != FENCE:
            continue
        found.append({"line": runner["line"], "body": runner["body"], "n": len(found) + 1})
    return found


# ---- plan: the launcher's half ---------------------------------------------------

_OPTS_IN = re.compile(r"^codeRunner[ \t]*:[ \t]*['\"]?(?:true|yes|on)['\"]?[ \t]*(?:#.*)?$", re.M | re.I)


def _says_it_opts_in(text: str) -> bool:
    """Does the page's settings block LOOK like it opts in? Generous on
    purpose (a quoted "true" does not opt in, and is still compiled): plan
    may compile a block the build will not show, never miss one it will."""
    if not text.startswith("---"):
        return False
    end = text.find("\n---", 3)
    if end < 0:
        return False
    return _OPTS_IN.search(text[3:end]) is not None


def course_pages(course_dir) -> list:
    """Every page of the course as the teacher keeps it: each .md under the
    course folder, outside any folder whose name starts with a dot (the
    built sites, Obsidian's own) and outside Media."""
    root = Path(course_dir)
    pages = []
    for page in sorted(root.rglob("*.md")):
        parts = page.relative_to(root).parts
        if any(part.startswith(".") for part in parts) or (parts and parts[0].strip().lower() == "media"):
            continue
        pages.append(page)
    return pages


def blocks_to_compile(texts) -> list:
    """The distinct normalised programs on pages that opt in, in page order."""
    seen = set()
    programs = []
    for text in texts:
        if "swift" not in text or not _says_it_opts_in(text):
            continue
        for block in swift_fences(text, True):
            program, _ = normalise(block["body"])
            key = hashlib.sha256(program.encode("utf-8")).hexdigest()
            if key in seen:
                continue
            seen.add(key)
            programs.append((key, program))
    return programs


def is_cached(entry) -> bool:
    """Does a cache entry name its block's outcome? A program, or the
    compiler's verdict WITH its words. An entry with no diagnostics (written
    by an earlier compile.py when the compiler was killed) is a miss
    (implementation review S3)."""
    if not isinstance(entry, dict):
        return False
    if entry.get("ok"):
        return True
    return bool(str(entry.get("diagnostics") or "").strip())


def clear_failures(cache: Path) -> int:
    """--full-rebuild: every cached FAILURE goes, so each is compiled again;
    programs stay, because a key names its code and its recipe."""
    cleared = 0
    try:
        entries = sorted(cache.glob("*.json"))
    except OSError:
        return 0
    for path in entries:
        entry = _read_json(path)
        if isinstance(entry, dict) and entry.get("ok") is False:
            try:
                path.unlink()
                cleared += 1
            except OSError:
                pass
    return cleared


def plan(course_dir, cache_root, swift_dir=None, now=None, full_rebuild=False, windows=None) -> dict:
    """
    Write a job for every Swift block the cache does not hold, into a job
    folder of this run's own. Answers {"root", "cache", "jobs", "count"}:
    `root` the course's .swift-cache (what the launcher mounts), `cache` this
    toolchain's folder in it, `jobs` this run's job folder (None when there
    is nothing to compile).
    """
    now = time.time() if now is None else now
    root = Path(cache_root)
    cache = root / toolchain_id(swift_dir, windows)
    if full_rebuild:
        clear_failures(cache)
    texts = []
    for page in course_pages(course_dir):
        try:
            texts.append(page.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError):
            continue
    waiting = []
    for key, program in blocks_to_compile(texts):
        if is_cached(_read_json(cache / f"{key}.json")):
            continue
        waiting.append((key, program))
    # A new run: whatever the last one could not do is said again only if it
    # happens again.
    try:
        (root / STATE_FILE).unlink()
    except OSError:
        pass
    _remove_orphan_jobs(root, now)
    jobs = None
    if waiting:
        jobs = root / JOBS_FOLDER / f"{int(now)}-{os.getpid()}-{secrets.token_hex(4)}"
        jobs.mkdir(parents=True, exist_ok=True)
        cache.mkdir(parents=True, exist_ok=True)
        for key, program in waiting:
            (jobs / f"{key}.swift").write_text(program + "\n", encoding="utf-8")
    return {"root": str(root), "cache": str(cache), "jobs": str(jobs) if jobs else None, "count": len(waiting)}


def _remove_orphan_jobs(root: Path, now: float) -> None:
    """A killed run's job folder, and launcher logs, after a day."""
    for folder in (root / JOBS_FOLDER, root / LOGS_FOLDER):
        try:
            runs = list(folder.iterdir())
        except OSError:
            continue
        for run in runs:
            try:
                if now - run.stat().st_mtime > ORPHAN_JOB_SECONDS:
                    if run.is_dir():
                        shutil.rmtree(run, ignore_errors=True)
                    else:
                        run.unlink()
            except OSError:
                pass


# ---- prepare: the build's half -----------------------------------------------------

def _reasons() -> dict:
    import contracts
    return contracts.section("shared-rules", "codeRunnerBlocks", "swift", "reasons")


def missing_reason(state, windows: bool) -> str:
    """Why a block has no binary (codeRunnerBlocks.swift.reasonCases), the
    same on both platforms since Windows compiles Swift too (#570): the
    launcher found too little free space; Swift could not be downloaded; or
    no program and nothing recorded (a compile that did not finish, or no
    launcher ran, as in deploy.py's own rebuild). `windows` decides only
    what the sentence says the download is (downloadGigabytes)."""
    if isinstance(state, dict) and state.get("state") == "noRoom":
        return "noRoom"
    if isinstance(state, dict) and state.get("state") == "notDownloaded":
        return "notDownloaded"
    return "notCompiled"


def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def first_error(diagnostics: str):
    """(line within the block, the message) of the compiler's first error,
    or (None, its first line)."""
    found = FIRST_ERROR.search(diagnostics or "")
    if found is not None:
        return int(found.group(1)), found.group(2).strip()
    for line in (diagnostics or "").splitlines():
        if line.strip():
            return None, line.strip()
    return None, ""


def _file_line_of(block: dict, key: str, source_text):
    """The opening fence's line in the TEACHER's page, by the block holding
    the same code (the n-th first, then any)."""
    if not source_text:
        return None
    candidates = swift_fences(source_text, True)
    for candidate in candidates:
        if candidate["n"] == block["n"] and key_of(candidate["body"]) == key:
            return candidate["line"]
    for candidate in candidates:
        if key_of(candidate["body"]) == key:
            return candidate["line"]
    return None


def download_gigabytes(windows=None) -> str:
    """codeRunnerBlocks.swift.downloadGigabytes for the platform the build
    runs on: what the first download is, in notDownloaded's sentence."""
    windows = (os.name == "nt") if windows is None else windows
    try:
        import contracts
        sizes = contracts.section("shared-rules", "codeRunnerBlocks", "swift", "downloadGigabytes")
        return sizes["windows" if windows else "mac"]
    except Exception:
        return ""


def reason_sentence(problem: dict, gigabytes, windows=None) -> str:
    import site_health
    reasons = _reasons()
    text = reasons.get(problem["reason"]) or reasons["notCompiled"]
    return site_health.filled(text, {"said": problem.get("said") or "", "gigabytes": gigabytes,
                                     "downloadGigabytes": download_gigabytes(windows)})


def error_line(problem: dict, gigabytes, windows=None) -> str:
    """`plantoir: error: Units/Loops.md: swift block 2, line 14: ...`."""
    where = f"{problem['page']}.md: swift block {problem['block']}"
    if problem.get("line") is not None:
        where += f", line {problem['line']}"
    return f"plantoir: error: {where}: {reason_sentence(problem, gigabytes, windows)}"


def _write_if_changed(path: Path, data: bytes) -> bool:
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)
    return True


def prepare(pages: list, output_dir, cache_root, swift_dir=None, windows=None, printer=print,
            now=None) -> dict:
    """
    Put each Swift block's binary into the site and say which blocks have
    none. `pages` are the pages students can see: [{"place", "codeRunner"
    (as parsed), "body", "source" (the teacher's file's text or None)}].
    Never compiles and never raises past its caller's guard. Answers
    {"problems": [...], "blocks": n, "ready": n}.
    """
    now = time.time() if now is None else now
    windows = (os.name == "nt") if windows is None else windows
    root = Path(cache_root)
    try:
        cache = root / toolchain_id(swift_dir, windows)
    except OSError:
        cache = None
    state = _read_json(root / STATE_FILE)
    try:
        import contracts
        gigabytes = contracts.section("shared-rules", "codeRunnerBlocks", "swift", "room", "needGigabytes")
    except Exception:
        gigabytes = ""
    static = Path(output_dir) / "quartz" / "static" / STATIC_FOLDER
    notes = _notes()
    older = _older_caches(root, cache)
    manifest = {}
    wanted = {}
    problems = []
    blocks = 0
    from_before = 0
    not_in_this_cache = 0
    large = []
    for page in pages:
        for block in swift_fences(page.get("body") or "", page_features.opts_in(page.get("codeRunner"))):
            blocks += 1
            program, dropped = normalise(block["body"])
            key = hashlib.sha256(program.encode("utf-8")).hexdigest()
            entry = _read_json(cache / f"{key}.json") if cache is not None else None
            if entry is not None:
                try:
                    os.utime(cache / f"{key}.json", None)
                except OSError:
                    pass
            if entry is not None and entry.get("ok") and (cache / f"{key}.wasm").is_file():
                wanted[f"{key}.wasm"] = cache / f"{key}.wasm"
                manifest[key] = {"ok": True, "file": f"{key}.wasm", "sdk": entry.get("sdk")}
                try:
                    os.utime(cache / f"{key}.wasm", None)
                except OSError:
                    pass
                _note_if_large(large, page, block, cache / f"{key}.wasm")
                continue
            if not is_cached(entry):
                not_in_this_cache += 1
                # The previous recipe's program for the same code is SERVED
                # until this recipe compiles it (implementation review N2):
                # the site keeps working through an offline preview or a
                # full disk after Plantoir was updated.
                served = None
                for folder in older:
                    candidate = _read_json(folder / f"{key}.json")
                    if isinstance(candidate, dict) and candidate.get("ok") and (folder / f"{key}.wasm").is_file():
                        served = (folder, candidate)
                        break
                    if isinstance(candidate, dict) and candidate.get("ok") is False and is_cached(candidate):
                        # The previous recipe's compile error for the same
                        # code is still the code's fault: said as one, not as
                        # lack of room or a download (the fixes review's nit 5).
                        entry = candidate
                        break
                if served is not None:
                    folder, candidate = served
                    wanted[f"{key}.wasm"] = folder / f"{key}.wasm"
                    manifest[key] = {"ok": True, "file": f"{key}.wasm", "sdk": candidate.get("sdk")}
                    from_before += 1
                    _note_if_large(large, page, block, folder / f"{key}.wasm")
                    continue
            file_line = _file_line_of(block, key, page.get("source"))
            if entry is not None and entry.get("ok") is False and is_cached(entry):
                block_line, said = first_error(entry.get("diagnostics") or "")
                line = None
                if file_line is not None:
                    line = file_line + dropped + (block_line if block_line is not None else 1)
                problem = {"page": page["place"], "block": block["n"], "line": line,
                           "blockLine": block_line, "reason": "compileError", "said": said}
                manifest[key] = {"ok": False, "reason": "compileError"}
            else:
                reason = missing_reason(state, windows)
                problem = {"page": page["place"], "block": block["n"], "line": file_line,
                           "blockLine": None, "reason": reason, "said": ""}
                manifest[key] = {"ok": False, "reason": reason}
            problems.append(problem)

    copied = _sync_files(wanted, static) if wanted else 0
    if not wanted:
        shutil.rmtree(static, ignore_errors=True)
    data = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        _write_if_changed(Path(output_dir) / "quartz" / MANIFEST, data)
    except OSError as error:
        printer(f"⚠️ Could not set up the Swift programs students run: {error}")
    ready = sum(1 for entry in manifest.values() if entry["ok"])
    if blocks:
        noun = "program" if blocks == 1 else "programs"
        printer(f"🦅 {ready} of {blocks} Swift {noun} on this site ready to run"
                + (f" ({copied} copied in)." if copied else "."))
    for problem in problems:
        printer(error_line(problem, gigabytes, windows))
    if from_before and notes:
        printer("plantoir: note: " + notes["fromBefore"].replace("{count}", str(from_before)))
    for item in large:
        printer(large_note(item, notes))
    # Old toolchains' folders go only once this one holds every block the
    # site needs (review N5): an offline preview after a recipe change must
    # not throw away the only binaries that work - which it now serves.
    if cache is not None and not not_in_this_cache:
        prune(root, cache.name, now)
    return {"problems": problems, "blocks": blocks, "ready": ready, "fromBefore": from_before,
            "large": large}


def _notes() -> dict:
    try:
        import contracts
        return contracts.section("shared-rules", "codeRunnerBlocks", "swift", "notes")
    except Exception:
        return {}


def _older_caches(root: Path, cache) -> list:
    """Every other toolchain's folder, newest first."""
    try:
        folders = [folder for folder in root.iterdir() if folder.is_dir()
                   and folder.name not in (JOBS_FOLDER, LOGS_FOLDER) and (cache is None or folder != cache)]
    except OSError:
        return []
    return sorted(folders, key=lambda folder: folder.stat().st_mtime, reverse=True)


def _note_if_large(large: list, page: dict, block: dict, path: Path) -> None:
    """A program over notes.largeBytes is named on a `plantoir: note:` line
    (implementation review S2): a 46 MB program per block is a cost a
    teacher should hear about, not a fault."""
    try:
        size = path.stat().st_size
    except OSError:
        return
    limit = _notes().get("largeBytes")
    if isinstance(limit, int) and size > limit:
        large.append({"page": page["place"], "block": block["n"], "bytes": size})


def large_note(item: dict, notes: dict) -> str:
    """`plantoir: note: Units/Dates.md: swift block 2: ...`."""
    megabytes = f"{item['bytes'] / 1_000_000:.1f}"
    text = (notes.get("large") or "").replace("{megabytes}", megabytes)
    return f"plantoir: note: {item['page']}.md: swift block {item['block']}: {text}"


def _sync_files(wanted: dict, target: Path) -> int:
    """`target` holds exactly `wanted` ({name: source}); counts copies."""
    copied = 0
    target.mkdir(parents=True, exist_ok=True)
    for name, source in sorted(wanted.items()):
        destination = target / name
        try:
            if destination.is_file() and destination.stat().st_size == source.stat().st_size \
                    and destination.read_bytes() == source.read_bytes():
                continue
            shutil.copyfile(source, destination)
            copied += 1
        except OSError:
            continue
    for existing in sorted(target.iterdir()):
        if existing.name not in wanted:
            if existing.is_dir():
                shutil.rmtree(existing, ignore_errors=True)
            else:
                existing.unlink()
    return copied


def prune(root: Path, keep: str, now: float) -> None:
    """Every other toolchain's folder, and this one's entries unused for
    PRUNE_DAYS (prepare touches each entry it uses)."""
    try:
        folders = list(root.iterdir())
    except OSError:
        return
    for folder in folders:
        # The launcher's logs stay (#570: they were removed by every prune).
        if folder.is_dir() and folder.name not in (keep, JOBS_FOLDER, LOGS_FOLDER):
            shutil.rmtree(folder, ignore_errors=True)
    try:
        entries = list((root / keep).iterdir())
    except OSError:
        return
    for entry in entries:
        try:
            if entry.is_file() and now - entry.stat().st_mtime > PRUNE_DAYS * 86400:
                entry.unlink()
        except OSError:
            pass


def health_finding_facts(outcome: dict) -> list:
    """The `swift_problems` fact for site_health: one entry per block."""
    return list(outcome.get("problems") or [])


# ---- The command line (the launcher's) --------------------------------------------

def _argument(argv: list, name: str):
    for index, item in enumerate(argv):
        if item.startswith(f"--{name}="):
            return item.split("=", 1)[1]
        if item == f"--{name}" and index + 1 < len(argv):
            return argv[index + 1]
    return None


def main(argv: list) -> int:
    if len(argv) < 2 or argv[1] != "plan":
        print("usage: swift_blocks.py plan --course=CODE [--format=lines]", file=sys.stderr)
        return 2
    course = _argument(argv, "course")
    if not course:
        print("usage: swift_blocks.py plan --course=CODE [--format=lines]", file=sys.stderr)
        return 2
    course_dir = toolchain_paths.COURSES_DIR / course
    if not course_dir.is_dir():
        print("count=0" if _argument(argv, "format") == "lines"
              else json.dumps({"root": None, "cache": None, "jobs": None, "count": 0}))
        return 0
    cache_root = toolchain_paths.merged_output_root(course_dir) / CACHE_FOLDER
    # The real place, so the launcher on the host mounts the same string
    # (.merged_output is a link to the builds folder, at its own path).
    try:
        cache_root.mkdir(parents=True, exist_ok=True)
        cache_root = cache_root.resolve()
    except OSError:
        pass
    planned = plan(course_dir, cache_root, full_rebuild="--full-rebuild" in argv)
    if _argument(argv, "format") == "lines":
        # For the launcher, which has no JSON reader on a teacher's Mac: one
        # KEY=value line each, the value everything after the first "=".
        print(f"root={planned['root'] or ''}")
        print(f"cache={planned['cache'] or ''}")
        print(f"jobs={planned['jobs'] or ''}")
        print(f"count={planned['count']}")
    else:
        print(json.dumps(planned))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
