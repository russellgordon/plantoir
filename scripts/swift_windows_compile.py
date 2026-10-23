#!/usr/bin/env python3
"""
Runnable Swift on Windows (#570): compile a preview's waiting blocks.

    python swift_windows_compile.py <jobs folder> <cache folder>

The mac runs support/swift/compile.py inside its Swift image. Windows runs
the SAME file, unchanged - its bytes are part of the mac's toolchain id, and
an edit would compile every Mac's blocks again - imported from the working
folder's .toolchain\\support\\swift and adjusted here for a Windows host
(contracts/shared-rules.json -> codeRunnerBlocks.swift.windows.compile):

1. environment(): PATH is the toolchain's bin and System32 only, with
   SystemRoot, and TEMP/TMP/USERPROFILE/HOME in a work folder. compile.py's
   own (PATH=...:/usr/bin:/bin, HOME=/tmp, no SystemRoot) leaves the driver
   unable to make a temporary folder, and every block came back
   "error: permissionDenied" - cached as the code's fault (measured
   2026-10-22).
2. CLANG is clang.exe.
3. OBJECT_ROOT is %LOCALAPPDATA%\\Plantoir\\swift\\work: a FIXED folder per
   block, as /tmp/plantoir-swift/<key> is in the image, so the same code
   gives the same bytes every time (a different folder changed 16 bytes,
   the module hash). Two previews compiling the same block would share it,
   so each block's folder is taken under a lock of its own; a preview that
   finds it taken leaves that job to the other.
4. -nonlib-dependency-scanner on both compiles: without it every compile
   warns about libSwiftScan, and the warning became the first line of every
   cached compile error. The program's bytes are the same with and without.
5. tidy() takes the work folder off in both separators, and keeps a
   failure's words only when they carry `error:` - a failure with no error
   in it is not the compiler's verdict, so compile.py does not cache it
   (its own "the compiler stopped without saying why" path).
6. JOB_SECONDS is jobSecondsOnWindows, and at most mostFullAtOnce
   full-library compiles run at once: wasm-opt -Os on a full-library
   program took 48.9 s alone here (0.13 s flush, 3.7 s compile, 1.3 s link)
   and up to about 150 s with eight running at once, against the mac's 13 s
   for all fifteen gate fragments.
7. A preflight before any job - the tools, the SDK and the work folder are
   there, and one tiny program compiles - so an install or an environment
   that cannot compile anything is never recorded as a fault in the code:
   exit 3, and no job is touched.

The toolchain id on Windows hashes this file too (scripts/swift_blocks.py,
toolchainIdFromOnWindows).
"""

import importlib.util
import os
import shutil
import sys
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import swift_windows_fetch  # noqa: E402
import toolchain_paths  # noqa: E402

PREFLIGHT_FAILED = 3
SMOKE_PROGRAM = 'print("ok")\n'

# The names this file changes in compile.py. scripts/test_swift_windows.py
# checks each one is there, so a renamed function in compile.py fails a test
# here instead of quietly not being patched.
PATCHED = ("environment", "CLANG", "OBJECT_ROOT", "EMBEDDED_COMPILE", "FULL_COMPILE", "tidy",
           "JOB_SECONDS", "compile_one_way", "compile_job", "run", "NotTheCompilers")


def rules() -> dict:
    return contracts.section("shared-rules", "codeRunnerBlocks", "swift", "windows", "compile")


def compile_py() -> Path:
    return toolchain_paths.SUPPORT_DIR / "swift" / "compile.py"


def windows_environment(bin_folder: Path, temporary: Path) -> dict:
    system_root = os.environ.get("SystemRoot") or r"C:\Windows"
    temporary.mkdir(parents=True, exist_ok=True)
    return {"PATH": f"{bin_folder};{Path(system_root) / 'System32'}", "SystemRoot": system_root,
            "TEMP": str(temporary), "TMP": str(temporary), "USERPROFILE": str(temporary),
            "HOME": str(temporary), "LANG": "C.UTF-8"}


def load(install: Path, work_root: Path, source=None):
    """compile.py as a module of its own, adjusted for this PC. Its flag
    lists are built when it is imported, from the PLANTOIR_* variables, so
    they are set first."""
    paths = swift_windows_fetch.tool_paths(install)
    os.environ["PLANTOIR_SWIFTC"] = str(paths["swiftc"])
    os.environ["PLANTOIR_SWIFT_SDK"] = str(paths["sdk"]).replace("\\", "/")
    os.environ["PLANTOIR_WASM_OPT"] = str(paths["wasmOpt"])
    spec = importlib.util.spec_from_file_location("plantoir_swift_compile", str(source or compile_py()))
    module = importlib.util.module_from_spec(spec)
    # No __pycache__ beside compile.py: that folder is the toolchain's own
    # copy, mirrored and compared by the app, and on a Mac hashed for the image.
    writes = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = writes
    for name in PATCHED:
        if not hasattr(module, name):
            raise AttributeError(f"compile.py has no {name} to adjust")
    settings = rules()
    temporary = work_root / "tmp"
    environment = windows_environment(paths["bin"], temporary)
    module.environment = lambda: dict(environment)
    module.CLANG = str(paths["bin"] / "clang.exe")
    module.OBJECT_ROOT = work_root
    for flag in settings["extraCompileFlags"]:
        if flag not in module.EMBEDDED_COMPILE:
            module.EMBEDDED_COMPILE.append(flag)
        if flag not in module.FULL_COMPILE:
            module.FULL_COMPILE.append(flag)
    module.JOB_SECONDS = contracts.section("shared-rules", "codeRunnerBlocks", "swift", "compile",
                                           "jobSecondsOnWindows")

    original_tidy = module.tidy

    def tidy(said: str, work: Path) -> str:
        # Only words carrying `error:` are cached as a compile error. That
        # rule alone would still cache an ENVIRONMENT failure that prints
        # `error:` (measured: "error: permissionDenied" for every block under
        # compile.py's own environment) as the student's mistake: what keeps
        # that out is the environment fix above and the preflight smoke
        # compile in main(), which stops the run before any job when nothing
        # can compile. Do not remove the preflight.
        text = said.replace(str(work) + "\\", "").replace(str(work).replace("\\", "/") + "/", "")
        text = original_tidy(text, work)
        return text if "error:" in text else ""
    module.tidy = tidy

    original_run = module.run

    def run(arguments: list) -> tuple:
        try:
            return original_run(arguments)
        except OSError as error:
            raise module.NotTheCompilers(f"{Path(str(arguments[0])).name}: {error}") from error
    module.run = run

    full_at_once = threading.Semaphore(settings["mostFullAtOnce"])
    original_one_way = module.compile_one_way

    def compile_one_way(sources, compile_flags, link_flags, work, extra_objects=()):
        if compile_flags is module.FULL_COMPILE:
            with full_at_once:
                return original_one_way(sources, compile_flags, link_flags, work, extra_objects)
        return original_one_way(sources, compile_flags, link_flags, work, extra_objects)
    module.compile_one_way = compile_one_way

    original_job = module.compile_job

    def compile_job(job: Path, out: Path) -> str:
        key = job.stem
        lock = swift_windows_fetch.Lock(work_root / "locks" / key)
        lock.path = work_root / "locks" / f"{key}.lock"
        if not lock.try_take():
            return f"{key[:12]} is being compiled by another preview"
        try:
            return original_job(job, out)
        finally:
            lock.give_back()
    module.compile_job = compile_job
    return module


def work_folder() -> Path:
    return swift_windows_fetch.home() / swift_windows_fetch.WORK_FOLDER


def smoke_compile(install: Path, work_root: Path) -> str:
    """Compile one tiny program; answers what went wrong, or ""."""
    try:
        module = load(install, work_root)
    except (OSError, AttributeError, ImportError) as error:
        return str(error)
    paths = swift_windows_fetch.tool_paths(install)
    for name in ("swiftc", "wasmOpt"):
        if not paths[name].is_file():
            return f"{paths[name].name} is missing"
    if not paths["sdk"].is_dir():
        return "the SDK is missing"
    # This process's own folder: two previews starting together each make
    # one, and neither can delete the other's half way through its compile
    # (implementation review). A killed run's leftover is harmless litter
    # in the work folder, which nothing else reads.
    work = work_root / f"_smoke-{os.getpid()}-{uuid.uuid4().hex[:8]}"
    try:
        work.mkdir(parents=True)
        main = work / "main.swift"
        main.write_text(SMOKE_PROGRAM, encoding="utf-8")
        shutil.copyfile(module.SHIM, work / "ReadLineShim.swift")
        binary, said = module.compile_one_way([main, work / "ReadLineShim.swift"], module.EMBEDDED_COMPILE,
                                              module.EMBEDDED_LINK, work)
        if binary is None or not binary.is_file() or binary.stat().st_size == 0:
            return (said.strip().splitlines() or ["no program came out"])[0][:200]
        return ""
    except (module.NotTheCompilers, module.TookTooLong, OSError) as error:
        return (str(error).strip().splitlines() or ["stopped"])[0][:200]
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main(argv: list) -> int:
    log = [item.split("=", 1)[1] for item in argv[1:] if item.startswith("--log=")]
    argv = [item for item in argv if not item.startswith("--log=")]
    if len(argv) != 3:
        print("usage: swift_windows_compile.py <jobs folder> <cache folder> [--log=<file>]", file=sys.stderr)
        return 2
    if log:
        # One log per run, as the mac's compile-$$.log; the console stays quiet.
        sys.stdout = open(log[0], "a", encoding="utf-8")
    jobs_folder, out = Path(argv[1]), Path(argv[2])
    install = swift_windows_fetch.install_dir()
    work_root = work_folder()
    problem = smoke_compile(install, work_root)
    if problem:
        print(f"preflight: nothing compiled, nothing kept: {problem}", flush=True)
        return PREFLIGHT_FAILED
    module = load(install, work_root)
    out.mkdir(parents=True, exist_ok=True)
    jobs = sorted(jobs_folder.glob("*.swift"))
    workers = max(1, os.cpu_count() or 1)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for line in pool.map(lambda job: module.compile_job(job, out), jobs):
            print(line, flush=True)
    shutil.rmtree(jobs_folder, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
