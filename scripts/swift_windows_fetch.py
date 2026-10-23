#!/usr/bin/env python3
"""
Runnable Swift on Windows (#570): get Swift ready on this PC, once.

The mac compiles a course's ```swift run blocks in a second container image
the launcher builds the first time a preview needs it (#493; preview.sh,
prepare_runnable_swift). Windows has no container, so preview.ps1 runs this
instead, IN THE FOREGROUND as the mac builds its image, the first time a
preview has a block to compile:

    python swift_windows_fetch.py ensure

and then compiles with scripts/swift_windows_compile.py. Everything it uses
is pinned in contracts/toolchain.json -> swiftWindows; every sentence it
prints is codeRunnerBlocks.swift.windows.printed in shared-rules.json.

The steps, none of which needs administrator rights (measured 2026-10-22,
documentation/12-windows-app.md -> "Runnable Swift on Windows"):

1. download the swift.org Windows installer (2.1 GB), RESUMING a partial
   download with HTTP Range, and check its SHA-256 and its Authenticode
   signer (Apple Inc.);
2. copy the solid cabinet attached to it out ('MSCF' at the pinned offset,
   cbCabinet bytes, checked against the pins), keeping the installer until
   Swift is ready, so a step that fails later needs no second download;
3. take the four payloads out with Windows' own expand.exe and check each
   against Apple's own SHA-512 (the bundle's Burn manifest);
4. `msiexec /a` the noasserts compiler and the runtime into folders (an
   administrative extraction: no elevation, no UAC);
5. trim to the measured set and put the VC++ runtime DLLs beside the tools;
6. download and unpack the wasm SDK (the mac's own pin) and wasm-opt;
7. compile one tiny program through the real wrapper - an install that
   cannot compile is never marked ready - then write READY.json and rename
   the folder into place.

One fetch at a time per PC: a lock held for the life of the process
(msvcrt.locking, so a killed fetch releases it by dying). A second launcher
waits for the first, up to WAIT_SECONDS, as the mac's build lock does. Once
the lock is held, every staging-* folder a killed fetch left is removed, and
a version folder for other pins is pruned (the mac prunes superseded images).

Exit status of `ensure`: 0 ready; 10 too little room (state noRoom); 11 not
downloaded (offline, or a download that was not what was pinned: state
notDownloaded); 12 could not be finished (another installation running, an
unpack that failed, or the wait for another launcher gave up: no state, so
the build says notCompiled). It prints one PLANTOIR_SWIFT: line when it got
Swift ready or failed to (activityTrail.mustRecord).
"""

import hashlib
import json
import os
import re
import secrets
import shutil
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402

READY = 0
NO_ROOM = 10
NOT_DOWNLOADED = 11
NOT_FINISHED = 12

# The mac's take_the_swift_build_lock waits 1,200 s for another launcher.
WAIT_SECONDS = 1200
MARKER = "PLANTOIR_SWIFT:"
READY_FILE = "READY.json"
LOCK_FILE = "fetch.lock"
DOWNLOAD_FOLDER = "download"
WORK_FOLDER = "work"
CHUNK = 1 << 20
# Defender and the indexer hold a freshly written folder open for a moment.
RENAME_TRIES = 20


class Failed(Exception):
    """Getting Swift ready stopped; `reason` is offline, noRoom, damaged,
    busy or unpack (activityTrail -> "Swift could not be got ready")."""

    def __init__(self, reason: str, detail: str = ""):
        super().__init__(f"{reason}: {detail}")
        self.reason = reason
        self.detail = detail


# ---- pins and places --------------------------------------------------------------

def pins() -> dict:
    return contracts.section("toolchain", "swiftWindows")


def sdk_pin() -> dict:
    for pin in contracts.section("toolchain", "swiftImage", "pins"):
        if pin["pin"] == "wasmSdk":
            return pin
    raise KeyError("swiftImage has no wasmSdk pin")


def windows_rules() -> dict:
    return contracts.section("shared-rules", "codeRunnerBlocks", "swift", "windows")


def printed(name: str, **values) -> str:
    text = windows_rules()["printed"][name]
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return text


_PROSE = re.compile(r"(^note$|^why$|Why$|^measured$|^rejected$)")


def install_digest(block=None, sdk=None) -> str:
    """What an install is OF: every pin but the prose. A READY.json carrying
    another digest is not this install (a moved pin fetches again)."""
    block = pins() if block is None else block
    sdk = sdk_pin() if sdk is None else sdk

    def strip(value):
        if isinstance(value, dict):
            return {key: strip(item) for key, item in value.items() if not _PROSE.search(key)}
        if isinstance(value, list):
            return [strip(item) for item in value]
        return value
    data = {"swiftWindows": strip(block), "wasmSdk": {"url": sdk["url"], "sha256": sdk["sha256"]}}
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode("utf-8")).hexdigest()


def id_digest(block=None, sdk=None) -> bytes:
    """What the PROGRAMS depend on, for the toolchain id: the hashes of
    everything compiled with, and nothing a `why` edit could move."""
    block = pins() if block is None else block
    sdk = sdk_pin() if sdk is None else sdk
    data = {"installer": block["installer"]["sha256"],
            "payloads": [payload["sha512"].lower() for payload in block["payloads"]],
            "configuration": block["configuration"],
            "sdk": sdk["sha256"], "binaryen": block["binaryen"]["sha256"]}
    return json.dumps(data, sort_keys=True).encode("utf-8")


def home() -> Path:
    """%LOCALAPPDATA%\\Plantoir\\swift (PLANTOIR_SWIFT_HOME for a test)."""
    explicit = os.environ.get("PLANTOIR_SWIFT_HOME", "").strip()
    if explicit:
        return Path(explicit)
    base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    return Path(base) / "Plantoir" / "swift"


def install_dir(root=None) -> Path:
    return (home() if root is None else Path(root)) / pins()["version"]


def sdk_folder_name(sdk=None) -> str:
    sdk = sdk_pin() if sdk is None else sdk
    return sdk["value"]


def tool_paths(install: Path) -> dict:
    """Where the compile wrapper finds everything, in an install (or in a
    staging folder about to become one)."""
    sdk = sdk_folder_name()
    return {
        "swiftc": install / "toolchain" / "usr" / "bin" / "swiftc.exe",
        "bin": install / "toolchain" / "usr" / "bin",
        "sdk": install / "sdk" / f"{sdk}.artifactbundle" / sdk / "wasm32-unknown-wasip1",
        "wasmOpt": install / "binaryen" / Path(pins()["binaryen"]["member"]),
    }


def is_ready(root=None) -> bool:
    install = install_dir(root)
    try:
        ready = json.loads((install / READY_FILE).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not isinstance(ready, dict) or ready.get("digest") != install_digest():
        return False
    paths = tool_paths(install)
    for keep in pins()["trim"]["mustKeep"]:
        if not (install / "toolchain" / Path(keep)).is_file():
            return False
    return paths["wasmOpt"].is_file() and paths["sdk"].is_dir()


# ---- the lock ---------------------------------------------------------------------

class Lock:
    """One fetch per PC. Held by a byte lock on an open file, which the
    system releases when the process ends however it ends."""

    def __init__(self, root: Path):
        self.path = root / LOCK_FILE
        self.handle = None

    def try_take(self) -> bool:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        handle = open(self.path, "a+b")
        try:
            if os.name == "nt":
                import msvcrt
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            handle.close()
            return False
        self.handle = handle
        return True

    def take(self, wait_seconds: float, waited=None, sleep=time.sleep) -> bool:
        began = time.monotonic()
        told = False
        while not self.try_take():
            if not told and waited is not None:
                waited()
                told = True
            if time.monotonic() - began >= wait_seconds:
                return False
            sleep(2)
        return True

    def give_back(self) -> None:
        if self.handle is not None:
            try:
                if os.name == "nt":
                    import msvcrt
                    self.handle.seek(0)
                    msvcrt.locking(self.handle.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
            self.handle.close()
            self.handle = None


def clean_up(root: Path, keep: str) -> None:
    """With the lock held: every staging-* a killed fetch left, and every
    version folder but `keep` (pruned as the mac prunes superseded images)."""
    try:
        entries = list(root.iterdir())
    except OSError:
        return
    for entry in entries:
        if not entry.is_dir():
            continue
        if entry.name.startswith("staging-") or entry.name.startswith("old-"):
            shutil.rmtree(entry, ignore_errors=True)
        elif entry.name not in (keep, DOWNLOAD_FOLDER, WORK_FOLDER) and re.match(r"^\d+\.\d+", entry.name):
            shutil.rmtree(entry, ignore_errors=True)


# ---- room -------------------------------------------------------------------------

def free_gigabytes(root: Path) -> int:
    probe = root
    while not probe.exists() and probe.parent != probe:
        probe = probe.parent
    return int(shutil.disk_usage(str(probe)).free / (1024 ** 3))


def need_gigabytes() -> int:
    return contracts.section("shared-rules", "codeRunnerBlocks", "swift", "room", "needGigabytes")


# ---- downloading ------------------------------------------------------------------

def _no_room(error: OSError) -> bool:
    return getattr(error, "errno", None) == 28 or getattr(error, "winerror", None) in (39, 112)


def download(url: str, destination: Path, total: int, say=print, progress=None, opener=None) -> Path:
    """`destination` whole, resumed from `destination.part` with Range when a
    part is there. `progress(done)` is called as bytes arrive. Raises
    Failed(offline | noRoom | damaged)."""
    part = destination.with_name(destination.name + ".part")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and destination.stat().st_size == total:
        return destination
    have = part.stat().st_size if part.is_file() else 0
    if have > total:
        part.unlink()
        have = 0
    request = urllib.request.Request(url, headers={"User-Agent": "Plantoir"})
    if have:
        request.add_header("Range", f"bytes={have}-")
    opener = opener or urllib.request.urlopen
    try:
        with opener(request, timeout=60) as response:
            status = getattr(response, "status", 200)
            if have and status != 206:
                have = 0  # the server ignored the range: start again
            mode = "ab" if have else "wb"
            done = have
            try:
                with open(part, mode) as out:
                    while True:
                        data = response.read(CHUNK)
                        if not data:
                            break
                        out.write(data)
                        done += len(data)
                        if progress is not None:
                            progress(done)
            except OSError as error:
                if _no_room(error):
                    raise Failed("noRoom", str(error)) from error
                raise
    except Failed:
        raise
    except urllib.error.HTTPError as error:
        if error.code == 416 and have == total:
            pass
        else:
            raise Failed("offline", f"HTTP {error.code}") from error
    except (urllib.error.URLError, OSError, TimeoutError) as error:
        if isinstance(error, OSError) and _no_room(error):
            raise Failed("noRoom", str(error)) from error
        raise Failed("offline", str(error)) from error
    size = part.stat().st_size
    if size != total:
        if size > total:
            part.unlink()
            raise Failed("damaged", f"{size} bytes, {total} pinned")
        raise Failed("offline", f"the download stopped at {size} of {total} bytes")
    os.replace(part, destination)
    return destination


def digest_of(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with open(path, "rb") as source:
        while True:
            data = source.read(CHUNK * 4)
            if not data:
                break
            digest.update(data)
    return digest.hexdigest()


def check_digest(path: Path, algorithm: str, expected: str) -> None:
    found = digest_of(path, algorithm)
    if found.lower() != expected.lower():
        try:
            path.unlink()
        except OSError:
            pass
        raise Failed("damaged", f"{path.name}: {algorithm} {found}, {expected.lower()} pinned")


def authenticode(path: Path) -> tuple:
    """(status, subject) of the file's Authenticode signature, by Windows'
    own Get-AuthenticodeSignature."""
    script = ("$s = Get-AuthenticodeSignature -LiteralPath $env:PLANTOIR_SIGNED_FILE; "
              "[string]$s.Status; if ($s.SignerCertificate) { $s.SignerCertificate.Subject } else { '' }")
    environment = dict(os.environ, PLANTOIR_SIGNED_FILE=str(path))
    done = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                          capture_output=True, text=True, env=environment, timeout=300)
    lines = (done.stdout or "").strip().splitlines() + ["", ""]
    return lines[0].strip(), lines[1].strip()


def check_signature(path: Path, wanted: list, reader=authenticode) -> None:
    status, subject = reader(path)
    if status != "Valid" or any(part not in subject for part in wanted):
        try:
            path.unlink()
        except OSError:
            pass
        raise Failed("damaged", f"signature {status or 'missing'}: {subject or 'no signer'}")


# ---- unpacking --------------------------------------------------------------------

def carve_cabinet(installer: Path, out: Path, offset: int, size: int) -> Path:
    """The cabinet attached to the installer, exactly as pinned: 'MSCF' at
    `offset`, cbCabinet == `size`, and inside the file."""
    length = installer.stat().st_size
    with open(installer, "rb") as source:
        source.seek(offset)
        header = source.read(36)
        if len(header) < 12 or header[:4] != b"MSCF":
            raise Failed("damaged", "no cabinet at the pinned offset")
        (cabinet_bytes,) = struct.unpack("<I", header[8:12])
        if cabinet_bytes != size or offset + size > length:
            raise Failed("damaged", f"cabinet of {cabinet_bytes} bytes at {offset} in {length}")
        source.seek(offset)
        left = size
        try:
            with open(out, "wb") as target:
                while left:
                    data = source.read(min(CHUNK * 8, left))
                    if not data:
                        raise Failed("damaged", "the cabinet ends early")
                    target.write(data)
                    left -= len(data)
        except OSError as error:
            if _no_room(error):
                raise Failed("noRoom", str(error)) from error
            raise Failed("unpack", str(error)) from error
    return out


def system_tool(name: str) -> str:
    root = os.environ.get("SystemRoot") or r"C:\Windows"
    candidate = Path(root) / "System32" / name
    return str(candidate) if candidate.is_file() else name


def run_tool(arguments: list, failure: str, timeout: int = 1800) -> subprocess.CompletedProcess:
    try:
        done = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise Failed(failure, f"{Path(arguments[0]).name}: {error}") from error
    return done


def expand_payload(cabinet: Path, payload: dict, out: Path) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    done = run_tool([system_tool("expand.exe"), str(cabinet), f"-F:{payload['id']}", str(out)], "unpack")
    found = out / payload["id"]
    if done.returncode != 0 or not found.is_file():
        raise Failed("unpack", f"expand {payload['id']}: {(done.stdout or done.stderr or '').strip()[-200:]}")
    if found.stat().st_size != payload["bytes"]:
        raise Failed("damaged", f"{payload['name']}: {found.stat().st_size} bytes, {payload['bytes']} pinned")
    named = out / payload["name"]
    os.replace(found, named)
    check_digest(named, "sha512", payload["sha512"])
    return named


def administrative_install(msi: Path, target: Path, log: Path, sleep=time.sleep, runner=None) -> None:
    """`msiexec /a`: the MSI's files into `target`, no elevation. 1618 is
    another installation running: wait and try again, three times."""
    runner = runner or (lambda arguments: run_tool(arguments, "unpack"))
    target.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        done = runner([system_tool("msiexec.exe"), "/a", str(msi), f"TARGETDIR={target}", "/qn",
                       "/L*v", str(log)])
        if done.returncode in (0, 3010):
            return
        if done.returncode == 1618 and attempt < 3:
            sleep(30)
            continue
        if done.returncode == 1618:
            raise Failed("busy", "another installation is running (1618)")
        if done.returncode == 112:
            raise Failed("noRoom", "msiexec: the disk is full (112)")
        raise Failed("unpack", f"msiexec /a {msi.name} exited {done.returncode}")


def _remove(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path, ignore_errors=True)
    else:
        try:
            path.unlink()
        except OSError:
            pass


def trim(toolchain: Path, rules: dict, runtime: Path) -> None:
    """The measured set: `remove` (globs, relative to the toolchain root)
    goes, `mustKeep` must stay, and the VC++ runtime DLLs from the runtime
    MSI go beside the tools."""
    for pattern in rules["remove"]:
        for found in sorted(toolchain.glob(pattern)):
            _remove(found)
    for keep in rules["mustKeep"]:
        if not (toolchain / Path(keep)).is_file():
            raise Failed("unpack", f"{keep} is missing after the trim")
    bin_folder = toolchain / "usr" / "bin"
    for name in rules["vcRuntime"]:
        found = sorted(runtime.rglob(name))
        if not found:
            raise Failed("unpack", f"{name} is not in the runtime")
        shutil.copyfile(found[0], bin_folder / name)


def untar(archive: Path, into: Path, member=None) -> None:
    into.mkdir(parents=True, exist_ok=True)
    arguments = [system_tool("tar.exe"), "-xzf", str(archive), "-C", str(into)]
    if member:
        arguments.append(member)
    done = run_tool(arguments, "unpack")
    if done.returncode != 0:
        raise Failed("unpack", f"tar {archive.name}: {(done.stderr or '').strip()[-200:]}")


def move(source: Path, target: Path, tries: int = RENAME_TRIES, sleep=time.sleep) -> None:
    """A folder renamed, trying again while something still holds a file in
    it open: measured 2026-10-22, the compiler's folder could not be renamed
    the moment msiexec had written it ("Access is denied")."""
    for attempt in range(tries):
        try:
            os.replace(source, target)
            return
        except OSError as error:
            if attempt == tries - 1:
                raise Failed("unpack", f"could not move {source.name}: {error}") from error
            sleep(1)


def rename_into_place(staging: Path, install: Path, tries: int = RENAME_TRIES, sleep=time.sleep) -> None:
    """Defender and the indexer hold a new folder open for a moment: try
    again rather than fail a 2 GB fetch on its last step."""
    if install.exists():
        aside = install.with_name(f"old-{install.name}-{secrets.token_hex(4)}")
        for attempt in range(tries):
            try:
                os.replace(install, aside)
                break
            except OSError:
                if attempt == tries - 1:
                    raise Failed("unpack", f"could not move the older {install.name} aside")
                sleep(1)
        shutil.rmtree(aside, ignore_errors=True)
    for attempt in range(tries):
        try:
            os.replace(staging, install)
            return
        except OSError as error:
            if attempt == tries - 1:
                raise Failed("unpack", f"could not move the new folder into place: {error}") from error
            sleep(1)


# ---- the whole fetch --------------------------------------------------------------

class Progress:
    """`gettingReadyPercent` about every ten per cent of the downloads: the
    mac's image build goes quiet for minutes; a school line takes six."""

    def __init__(self, total: int, say):
        self.total = total
        self.say = say
        self.done_before = 0
        self.last_tenth = 0

    def callback(self, base: int):
        def tell(done: int) -> None:
            tenth = int((base + done) * 10 / self.total)
            if tenth > self.last_tenth and tenth < 10:
                self.last_tenth = tenth
                self.say(printed("gettingReadyPercent", percent=tenth * 10))
        return tell


def fetch(root: Path, say=print, signature_reader=authenticode, smoke=None) -> dict:
    """Everything, into a staging folder of this run's own, then renamed into
    place. Answers what READY.json says. Raises Failed."""
    block = pins()
    sdk = sdk_pin()
    began = time.monotonic()
    seconds = {}
    downloads = root / DOWNLOAD_FOLDER
    staging = root / f"staging-{secrets.token_hex(4)}"
    staging.mkdir(parents=True)
    installer_pin = block["installer"]
    total = installer_pin["bytes"] + sdk["bytes"] + block["binaryen"]["bytes"]
    progress = Progress(total, say)
    try:
        step = time.monotonic()
        installer = download(installer_pin["url"], downloads / Path(installer_pin["url"]).name,
                             installer_pin["bytes"], say, progress.callback(0))
        sdk_archive = download(sdk["url"], downloads / Path(sdk["url"]).name, sdk["bytes"], say,
                               progress.callback(installer_pin["bytes"]))
        binaryen_archive = download(block["binaryen"]["url"], downloads / Path(block["binaryen"]["url"]).name,
                                    block["binaryen"]["bytes"], say,
                                    progress.callback(installer_pin["bytes"] + sdk["bytes"]))
        seconds["download"] = round(time.monotonic() - step, 1)
        say(printed("unpacking"))
        step = time.monotonic()
        check_digest(installer, "sha256", installer_pin["sha256"])
        check_digest(sdk_archive, "sha256", sdk["sha256"])
        check_digest(binaryen_archive, "sha256", block["binaryen"]["sha256"])
        check_signature(installer, installer_pin["authenticodeSubjectContains"], signature_reader)
        seconds["check"] = round(time.monotonic() - step, 1)

        step = time.monotonic()
        # The installer stays until Swift is ready: a step that fails after
        # this point is tried again without downloading 2.1 GB again (it was,
        # once, measured: a folder that could not be renamed). The peak is
        # then about 4.5 GB, inside room.needGigabytes.
        cabinet = carve_cabinet(installer, staging / "container.cab", installer_pin["containerOffset"],
                                installer_pin["cabinetBytes"])
        payloads = staging / "payloads"
        for payload in block["payloads"]:
            expand_payload(cabinet, payload, payloads)
        cabinet.unlink()
        seconds["expand"] = round(time.monotonic() - step, 1)

        step = time.monotonic()
        compiler = staging / "msi-compiler"
        runtime = staging / "msi-runtime"
        names = [payload["name"] for payload in block["payloads"]]
        compiler_msi = next(name for name in names if name.startswith("bld.") and name.endswith(".msi"))
        runtime_msi = next(name for name in names if name.startswith("rtl.") and name.endswith(".msi"))
        # The logs go beside the downloads: kept when a step fails, deleted
        # with them once Swift is ready.
        administrative_install(payloads / compiler_msi, compiler, downloads / "msi-compiler.log")
        administrative_install(payloads / runtime_msi, runtime, downloads / "msi-runtime.log")
        shutil.rmtree(payloads, ignore_errors=True)
        found = sorted(compiler.rglob("swiftc.exe"))
        if not found:
            raise Failed("unpack", "the compiler MSI held no swiftc.exe")
        move(found[0].parents[2], staging / "toolchain")
        shutil.rmtree(compiler, ignore_errors=True)
        trim(staging / "toolchain", block["trim"], runtime)
        shutil.rmtree(runtime, ignore_errors=True)
        seconds["install"] = round(time.monotonic() - step, 1)

        step = time.monotonic()
        untar(sdk_archive, staging / "sdk")
        untar(binaryen_archive, staging / "binaryen", block["binaryen"]["member"])
        seconds["sdk"] = round(time.monotonic() - step, 1)

        step = time.monotonic()
        smoke = smoke or _smoke
        smoke(staging, root / WORK_FOLDER)
        seconds["smoke"] = round(time.monotonic() - step, 1)

        kept = sum(item.stat().st_size for item in staging.rglob("*") if item.is_file())
        ready = {"digest": install_digest(block, sdk), "version": block["version"], "keptBytes": kept,
                 "seconds": seconds, "totalSeconds": round(time.monotonic() - began, 1),
                 "downloadedBytes": total}
        (staging / READY_FILE).write_text(json.dumps(ready, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        rename_into_place(staging, install_dir(root))
        shutil.rmtree(downloads, ignore_errors=True)
        return ready
    except Failed:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    except OSError as error:
        shutil.rmtree(staging, ignore_errors=True)
        if _no_room(error):
            raise Failed("noRoom", str(error)) from error
        raise Failed("unpack", str(error)) from error


def _smoke(install: Path, work_root: Path) -> None:
    import swift_windows_compile
    problem = swift_windows_compile.smoke_compile(install, work_root)
    if problem:
        raise Failed("unpack", f"the first program did not compile: {problem}")


# ---- ensure: the launcher's command ------------------------------------------------

def marker(outcome: dict) -> str:
    return MARKER + " " + json.dumps(outcome, sort_keys=True)


def ensure(root=None, say=print, wait_seconds=WAIT_SECONDS, fetcher=fetch, course=None, section=None) -> int:
    root = home() if root is None else Path(root)
    where = {}
    if course:
        where["course"] = course
    if section:
        try:
            where["section"] = int(section)
        except ValueError:
            pass
    if is_ready(root):
        return READY
    root.mkdir(parents=True, exist_ok=True)
    lock = Lock(root)
    if not lock.take(wait_seconds, waited=lambda: say(printed("waitingForAnother"))):
        say(printed("stillGettingReady"))
        return NOT_FINISHED
    try:
        clean_up(root, pins()["version"])
        if is_ready(root):
            # Another launcher finished while this one waited.
            return READY
        free = free_gigabytes(root)
        if free < need_gigabytes():
            say(printed("noRoom", gigabytes=need_gigabytes(), free=free))
            say(marker(dict(where, ready=False, reason="noRoom")))
            return NO_ROOM
        say(printed("gettingReady"))
        try:
            ready = fetcher(root, say)
        except Failed as failure:
            say(printed(failure.reason))
            say(marker(dict(where, ready=False, reason=failure.reason)))
            _log(root, f"could not get Swift ready: {failure}")
            if failure.reason == "noRoom":
                return NO_ROOM
            if failure.reason in ("offline", "damaged"):
                return NOT_DOWNLOADED
            return NOT_FINISHED
        say(printed("ready"))
        say(marker(dict(where, ready=True, seconds=int(round(ready["totalSeconds"])),
                        downloadedBytes=ready["downloadedBytes"])))
        _log(root, f"Swift got ready: {json.dumps(ready, sort_keys=True)}")
        return READY
    finally:
        lock.give_back()


def _log(root: Path, line: str) -> None:
    try:
        with open(root / "fetch.log", "a", encoding="utf-8") as log:
            log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " " + line + "\n")
    except OSError:
        pass


def _argument(argv: list, name: str):
    for item in argv:
        if item.startswith(f"--{name}="):
            return item.split("=", 1)[1]
    return None


def main(argv: list) -> int:
    if len(argv) >= 2 and argv[1] == "ensure":
        return ensure(course=_argument(argv, "course"), section=_argument(argv, "section"))
    if len(argv) >= 2 and argv[1] == "status":
        print("ready" if is_ready() else "absent")
        return 0
    if len(argv) >= 2 and argv[1] == "paths":
        for name, value in tool_paths(install_dir()).items():
            print(f"{name}={value}")
        return 0
    print("usage: swift_windows_fetch.py ensure | status | paths", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
