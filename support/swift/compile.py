#!/usr/bin/env python3
"""
Runnable Swift (#493): compile a preview's waiting blocks to WebAssembly.

Runs INSIDE the Swift image (support/swift/Dockerfile), which the launcher
starts once per preview that has blocks to compile, with no network:

    docker run --rm --network none --mount <cache>:<cache> IMAGE \
        python3 /opt/plantoir-swift/compile.py <jobs folder> <cache folder>

`<jobs folder>` holds one `<key>.swift` per block (scripts/swift_blocks.py
wrote them, `<key>` being the SHA-256 of the block's normalised code, which is
exactly what is in the file); `<cache folder>` is the toolchain id's own
folder of the course's Swift cache. For each job this writes
`<key>.wasm` and `<key>.json` there - each by a temporary name and a rename,
so a reader never sees half a file - and then deletes the job. Jobs run in
parallel, one per CPU.

Each block is compiled the way #493's Phase 0 measured (contracts/
shared-rules.json -> codeRunnerBlocks.swift.compile):

1. Embedded Swift (`-Osize`, the readLine shim beside the block, the Unicode
   tables linked): about 12-110 KB a block.
2. If that does not compile, OR the optimised binary contains
   PLACEHOLDER (Embedded Swift compiled a `print` of a value it cannot print
   and would show that sentence instead), the full standard library (`-O`):
   about 0.9 MB a block, brotli'd.
3. If neither compiles, `{ok: false, reason: compileError}` with the FULL
   compiler's diagnostics - the one that describes ordinary Swift.

Every compile is two steps, `-c` to a fixed object path, then a link (spike
G4: the one-call driver puts a random temporary path into the binary). The
object path is `/tmp/plantoir-swift/<key>/main.o`, the same for the same
code every time, so a block's bytes are the same in every run of one image.

PATH is pinned to the toolchain and /usr/bin:/bin, and wasm-opt is called by
its absolute path, never found on PATH: clang runs any wasm-opt it finds on
PATH by itself during the link, which changes the output (Phase 0 trap 1).
`-swift-version 5` is pinned (Phase 0 trap 2: Swift 6 mode changes an
Embedded verdict). `-assert-config Debug` keeps the `Fatal error:` line a
trap prints. readLine() flushes stdout before it reads (ReadLineShim.swift
for Embedded, FlushBeforeRead.c by `--wrap` for the full library), so a
prompt printed with `terminator: ""` comes before the echoed input. The link caps memory at MAX_MEMORY (review S5: with no maximum a
runaway list grew to 2 GB in a student's tab before it trapped).

The values here are this image's: they are part of the toolchain id
(scripts/swift_blocks.py hashes this file), so a changed flag compiles every
block again. The three PLANTOIR_* variables exist only so the gate can be run
against a Mac's own toolchain while developing; the image never sets them.
"""

import json
import os
import shutil
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SWIFT_VERSION = "6.4.0"
WASM_OPT_VERSION = "version_133"

SWIFTC = os.environ.get("PLANTOIR_SWIFTC", "/opt/swift/usr/bin/swiftc")
SDK = os.environ.get(
    "PLANTOIR_SWIFT_SDK",
    "/opt/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1")
WASM_OPT = os.environ.get("PLANTOIR_WASM_OPT", "/opt/binaryen/bin/wasm-opt")
SHIM = Path(__file__).resolve().parent / "ReadLineShim.swift"
FLUSH = Path(__file__).resolve().parent / "FlushBeforeRead.c"
CLANG = os.path.join(os.path.dirname(SWIFTC), "clang")

# The sentence Embedded Swift prints where it cannot print a value.
PLACEHOLDER = b"cannot print value in embedded Swift"

# 256 MB: a runaway list traps in about a tenth of a second instead of
# growing to 2 GB (review S5, measured in node and both browsers).
MAX_MEMORY = 268435456

# A compile that takes longer than this is abandoned and NOT cached (review
# S3: a failure that is not the compiler's must never be remembered - nor is
# one of wasm-opt or of the readLine flush, NotTheCompilers).
JOB_SECONDS = 180

# Diagnostics kept per block: enough for the first errors, never a page.
MOST_DIAGNOSTIC_CHARACTERS = 4000

OBJECT_ROOT = Path("/tmp/plantoir-swift")

COMMON = ["-target", "wasm32-unknown-wasip1", "-sdk", f"{SDK}/WASI.sdk", "-static-stdlib",
          # spike G2: the wasm builtins live in the SDK, not the Linux toolchain.
          "-Xclang-linker", "-resource-dir", "-Xclang-linker",
          f"{SDK}/swift.xctoolchain/usr/lib/swift_static/clang"]

EMBEDDED_COMPILE = COMMON + [
    "-resource-dir", f"{SDK}/swift.xctoolchain/usr/lib/swift",
    "-enable-experimental-feature", "Embedded", "-wmo",
    "-Osize", "-assert-config", "Debug", "-swift-version", "5"]
EMBEDDED_LINK = COMMON + [
    "-resource-dir", f"{SDK}/swift.xctoolchain/usr/lib/swift",
    "-enable-experimental-feature", "Embedded",
    "-Xlinker", "-lc++", "-Xlinker", "-lswift_Concurrency", "-lswiftUnicodeDataTables",
    "-Xlinker", f"--max-memory={MAX_MEMORY}"]

FULL_COMPILE = COMMON + [
    "-resource-dir", f"{SDK}/swift.xctoolchain/usr/lib/swift_static",
    "-O", "-assert-config", "Debug", "-swift-version", "5"]
FULL_LINK = COMMON + [
    "-resource-dir", f"{SDK}/swift.xctoolchain/usr/lib/swift_static",
    "-Xlinker", f"--max-memory={MAX_MEMORY}",
    # readLine() flushes stdout first (FlushBeforeRead.c).
    "-Xlinker", "--wrap=swift_stdlib_readLine_stdin"]

FLUSH_COMPILE = ["--target=wasm32-unknown-wasip1", f"--sysroot={SDK}/WASI.sdk", "-Os", "-c"]

WASM_OPT_FLAGS = ["-Os", "--strip-debug", "--strip-producers"]


def environment() -> dict:
    """PATH pinned: the toolchain's own folder, then /usr/bin:/bin."""
    return {"PATH": f"{os.path.dirname(SWIFTC)}:/usr/bin:/bin", "HOME": "/tmp", "LANG": "C.UTF-8"}


class TookTooLong(Exception):
    pass


class NotTheCompilers(Exception):
    """A step after Swift accepted the code failed (wasm-opt, or compiling
    the readLine flush): the code is not at fault, so nothing is cached and
    the next preview tries again (review S3)."""


def run(arguments: list) -> tuple:
    try:
        done = subprocess.run(arguments, capture_output=True, text=True, env=environment(),
                              timeout=JOB_SECONDS)
    except subprocess.TimeoutExpired as error:
        raise TookTooLong(str(error)) from error
    said = (done.stdout or "") + (done.stderr or "")
    # Killed (out of memory, a signal): not the code's fault (review S3 of
    # the implementation review, measured under --memory 50m: every kill
    # came back as a negative status). Decided by the status ALONE, never by
    # reading the words - the compiler echoes the student's code, which may
    # well say "killed" (the fixes review's F1).
    if done.returncode < 0:
        raise NotTheCompilers(said or f"stopped by signal {-done.returncode}")
    return done.returncode, said


def compile_one_way(sources: list, compile_flags: list, link_flags: list, work: Path, extra_objects=()) -> tuple:
    """`-c` to work/main.o, then link to work/main.wasm, then wasm-opt to
    work/main.opt.wasm. Answers (path of the optimised binary or None, the
    compiler's words)."""
    objects = work / "obj"
    shutil.rmtree(objects, ignore_errors=True)
    objects.mkdir(parents=True)
    module_cache = work / "module-cache"
    status, said = run([SWIFTC] + compile_flags + ["-module-cache-path", str(module_cache), "-c"]
                       + [str(source) for source in sources] + ["-o", str(objects / "main.o")])
    if status != 0:
        return None, said
    status, linked = run([SWIFTC] + link_flags + [str(objects / "main.o")] + [str(item) for item in extra_objects]
                         + ["-o", str(objects / "main.wasm")])
    if status != 0:
        return None, said + linked
    status, optimised = run([WASM_OPT] + WASM_OPT_FLAGS + [str(objects / "main.wasm"),
                                                           "-o", str(objects / "main.opt.wasm")])
    if status != 0:
        raise NotTheCompilers(optimised)
    return objects / "main.opt.wasm", said


def tidy(said: str, work: Path) -> str:
    """The compiler's words with the job's folder taken off its file names,
    so `main.swift:3:7: error: ...` reads as the block's own line 3."""
    text = said.replace(str(work) + "/", "")
    if len(text) > MOST_DIAGNOSTIC_CHARACTERS:
        text = text[:MOST_DIAGNOSTIC_CHARACTERS] + "\n..."
    return text.strip()


def write_atomically(path: Path, data: bytes) -> None:
    """By a temporary name that is this process's and thread's own, so two
    launchers compiling the same key never take each other's (review N3,
    and the fixes review's nit 3)."""
    # os.getpid() is 1 in every container, so a random suffix makes it certain.
    temporary = path.with_name(f".{path.name}.{os.getpid()}.{threading.get_ident()}.{uuid.uuid4().hex}.tmp")
    temporary.write_bytes(data)
    try:
        os.replace(temporary, path)
    except FileNotFoundError:
        pass


def compile_job(job: Path, out: Path) -> str:
    """Compile one job; answers a line for the log."""
    key = job.stem
    work = OBJECT_ROOT / key
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    began = time.monotonic()
    try:
        main = work / "main.swift"
        shutil.copyfile(job, main)
        shutil.copyfile(SHIM, work / "ReadLineShim.swift")
        sdk = "embedded"
        binary, said = compile_one_way([main, work / "ReadLineShim.swift"], EMBEDDED_COMPILE, EMBEDDED_LINK, work)
        if binary is not None and PLACEHOLDER in binary.read_bytes():
            binary = None
        if binary is None:
            sdk = "full"
            flush = work / "flush.o"
            status, flush_said = run([CLANG] + FLUSH_COMPILE + [str(FLUSH), "-o", str(flush)])
            if status != 0:
                raise NotTheCompilers(flush_said)
            binary, said = compile_one_way([main], FULL_COMPILE, FULL_LINK, work, extra_objects=[flush])
        seconds = round(time.monotonic() - began, 2)
        if binary is None and not tidy(said, work):
            # A failure with no words from the compiler is not a verdict on
            # the code: never cached (review S3).
            raise NotTheCompilers("the compiler stopped without saying why")
        if binary is None:
            entry = {"ok": False, "reason": "compileError", "diagnostics": tidy(said, work),
                     "swift": SWIFT_VERSION, "wasmOpt": WASM_OPT_VERSION}
            write_atomically(out / f"{key}.json", (json.dumps(entry, sort_keys=True) + "\n").encode("utf-8"))
            line = f"{key[:12]} compile error ({seconds} s)"
        else:
            data = binary.read_bytes()
            write_atomically(out / f"{key}.wasm", data)
            entry = {"ok": True, "sdk": sdk, "bytes": len(data), "swift": SWIFT_VERSION,
                     "wasmOpt": WASM_OPT_VERSION}
            write_atomically(out / f"{key}.json", (json.dumps(entry, sort_keys=True) + "\n").encode("utf-8"))
            line = f"{key[:12]} {sdk} {len(data)} bytes ({seconds} s)"
        job.unlink(missing_ok=True)
        return line
    except TookTooLong:
        job.unlink(missing_ok=True)
        return f"{key[:12]} took longer than {JOB_SECONDS} s and was not kept"
    except NotTheCompilers as failure:
        job.unlink(missing_ok=True)
        first = (str(failure).strip().splitlines() or [""])[0][:200]
        return f"{key[:12]} could not be finished and was not kept: {first}"
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main(argv: list) -> int:
    if len(argv) != 3:
        print("usage: compile.py <jobs folder> <cache folder>", file=sys.stderr)
        return 2
    jobs_folder, out = Path(argv[1]), Path(argv[2])
    out.mkdir(parents=True, exist_ok=True)
    jobs = sorted(jobs_folder.glob("*.swift"))
    workers = max(1, os.cpu_count() or 1)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for line in pool.map(lambda job: compile_job(job, out), jobs):
            print(line, flush=True)
    shutil.rmtree(jobs_folder, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
