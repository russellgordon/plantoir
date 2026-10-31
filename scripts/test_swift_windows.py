#!/usr/bin/env python3
"""
Runnable Swift on Windows (#570): the fetch, the compile wrapper, the
Windows toolchain id and the words, against contracts/toolchain.json ->
swiftWindows and shared-rules.json -> codeRunnerBlocks.swift.windows.

Runs on both platforms (verify.sh on the mac, PythonToolchainTests on
Windows): nothing here downloads anything or needs Swift. The parts that
need Windows' own expand.exe or msvcrt are skipped elsewhere and say so.
"""

import hashlib
import http.server
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
if (REPO / "contracts").is_dir():
    toolchain_paths.CONTRACTS_DIR = REPO / "contracts"
    contracts.reset_cache()
if (REPO / "support").is_dir():
    toolchain_paths.SUPPORT_DIR = REPO / "support"

import swift_blocks  # noqa: E402
import swift_windows_compile  # noqa: E402
import swift_windows_fetch as fetch  # noqa: E402

ON_WINDOWS = os.name == "nt"


def windows_rules(*keys):
    return contracts.section("shared-rules", "codeRunnerBlocks", "swift", "windows", *keys)


class PinTests(unittest.TestCase):
    def setUp(self):
        self.pins = fetch.pins()

    def test_the_installer_and_its_cabinet_are_pinned_whole(self):
        installer = self.pins["installer"]
        self.assertRegex(installer["sha256"], r"^[0-9a-f]{64}$")
        self.assertTrue(installer["url"].startswith("https://download.swift.org/"))
        end = installer["containerOffset"] + installer["cabinetBytes"]
        self.assertLess(end, installer["bytes"], "the cabinet must end inside the installer")
        self.assertEqual(installer["bytes"] - end, 10622, "the signature measured after the cabinet")
        self.assertIn("CN=Apple Inc.", installer["authenticodeSubjectContains"])

    def test_every_payload_has_apples_own_sha512(self):
        ids = set()
        for payload in self.pins["payloads"]:
            self.assertRegex(payload["sha512"], r"^[0-9A-Fa-f]{128}$")
            self.assertRegex(payload["id"], r"^a\d+$")
            self.assertGreater(payload["bytes"], 0)
            ids.add(payload["id"])
        self.assertEqual(ids, {"a1", "a14", "a10", "a23"})
        names = [payload["name"] for payload in self.pins["payloads"]]
        self.assertIn("bld.noasserts.msi", names)
        self.assertIn("rtl.amd64.msi", names)
        self.assertEqual(self.pins["configuration"], "noasserts")

    def test_the_sdk_is_the_macs_own_pin(self):
        self.assertEqual(self.pins["wasmSdk"], "swiftImage -> pins -> wasmSdk")
        self.assertRegex(fetch.sdk_pin()["sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(self.pins["binaryen"]["sha256"], r"^[0-9a-f]{64}$")
        self.assertIn("x86_64-windows", self.pins["binaryen"]["url"])

    def test_what_is_kept_adds_up(self):
        self.assertEqual(self.pins["keptBytes"], 533231069 + 354685593 + 10343424)
        total = self.pins["installer"]["bytes"] + fetch.sdk_pin()["bytes"] + self.pins["binaryen"]["bytes"]
        self.assertEqual(contracts.section("shared-rules", "codeRunnerBlocks", "swift", "downloadGigabytes")["windows"],
                         f"{total / 1e9:.1f}")


class ToolchainIdTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-swift-winid-"))
        self.recipe = self.folder / "swift"
        self.scripts = self.folder / "scripts"
        shutil.copytree(REPO / "support" / "swift", self.recipe, ignore=shutil.ignore_patterns("__pycache__"))
        self.scripts.mkdir()
        shutil.copyfile(REPO / "scripts" / swift_blocks.WINDOWS_RECIPE_FILE, self.scripts / swift_blocks.WINDOWS_RECIPE_FILE)
        for path in list(self.recipe.iterdir()) + list(self.scripts.iterdir()):
            path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def windows_id(self):
        return swift_blocks.toolchain_id(self.recipe, windows=True, scripts_dir=self.scripts)

    def test_the_macs_id_is_the_formula_it_always_was(self):
        digest = hashlib.sha256()
        for name in swift_blocks.RECIPE_FILES:
            digest.update(name.encode("utf-8") + b"\0")
            digest.update((self.recipe / name).read_bytes())
            digest.update(b"\0")
        self.assertEqual(swift_blocks.toolchain_id(self.recipe, windows=False), digest.hexdigest()[:16])

    def test_a_crlf_checkout_gives_the_same_windows_id(self):
        before = self.windows_id()
        for path in list(self.recipe.iterdir()) + list(self.scripts.iterdir()):
            path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
        self.assertEqual(self.windows_id(), before)

    def test_the_windows_id_is_not_the_macs(self):
        self.assertNotEqual(self.windows_id(), swift_blocks.toolchain_id(self.recipe, windows=False))
        self.assertRegex(self.windows_id(), r"^[0-9a-f]{16}$")

    def test_the_wrapper_and_the_pins_are_in_the_windows_id_and_prose_is_not(self):
        before = self.windows_id()
        wrapper = self.scripts / swift_blocks.WINDOWS_RECIPE_FILE
        original = wrapper.read_bytes()
        wrapper.write_bytes(original + b"# changed\n")
        self.assertNotEqual(self.windows_id(), before)
        wrapper.write_bytes(original)
        block = json.loads(json.dumps(fetch.pins()))
        sdk = fetch.sdk_pin()
        moved = json.loads(json.dumps(block))
        moved["payloads"][1]["sha512"] = "0" * 128
        self.assertNotEqual(fetch.id_digest(moved, sdk), fetch.id_digest(block, sdk))
        self.assertNotEqual(fetch.install_digest(moved, sdk), fetch.install_digest(block, sdk))
        reworded = json.loads(json.dumps(block))
        reworded["installer"]["why"] = "different words"
        reworded["measured"] = "different words"
        self.assertEqual(fetch.id_digest(reworded, sdk), fetch.id_digest(block, sdk))
        self.assertEqual(fetch.install_digest(reworded, sdk), fetch.install_digest(block, sdk))

    def test_the_contract_names_the_files(self):
        named = contracts.section("shared-rules", "codeRunnerBlocks", "swift", "cache", "toolchainIdFromOnWindows")
        files = [item for item in named if "/" in item and "->" not in item]
        self.assertEqual([Path(item).name for item in files],
                         list(swift_blocks.RECIPE_FILES) + [swift_blocks.WINDOWS_RECIPE_FILE])
        for item in files:
            self.assertTrue((REPO / item).is_file(), item)


class FakeInstall:
    """A folder laid out as an install, with nothing that runs in it."""

    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-swift-install-"))
        self.install = self.root / "6.4.0"
        paths = fetch.tool_paths(self.install)
        for keep in fetch.pins()["trim"]["mustKeep"]:
            target = self.install / "toolchain" / Path(keep)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"MZ")
        paths["wasmOpt"].parent.mkdir(parents=True, exist_ok=True)
        paths["wasmOpt"].write_bytes(b"MZ")
        paths["sdk"].mkdir(parents=True, exist_ok=True)
        self.work = self.root / "work"

    def mark_ready(self, digest=None):
        (self.install / fetch.READY_FILE).write_text(json.dumps({"digest": digest or fetch.install_digest()}))

    def remove(self):
        shutil.rmtree(self.root, ignore_errors=True)


class Completed:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode, self.stdout, self.stderr = returncode, stdout, stderr


class CompileWrapperTests(unittest.TestCase):
    def setUp(self):
        self.space = FakeInstall()
        self.module = swift_windows_compile.load(self.space.install, self.space.work)

    def tearDown(self):
        self.space.remove()

    def test_every_name_it_changes_is_in_compile_py(self):
        source = (REPO / "support" / "swift" / "compile.py").read_text(encoding="utf-8")
        for name in swift_windows_compile.PATCHED:
            self.assertRegex(source, rf"(?m)^(def |class )?{name}\b", name)

    def test_the_environment_is_a_windows_one_and_run_uses_it(self):
        environment = self.module.environment()
        self.assertIn("SystemRoot", environment)
        self.assertNotIn("/usr/bin", environment["PATH"])
        self.assertTrue(environment["PATH"].startswith(str(fetch.tool_paths(self.space.install)["bin"])))
        self.assertEqual(environment["TEMP"], environment["TMP"])
        seen = {}

        def fake_run(arguments, **options):
            seen.update(options)
            return Completed(0, "", "")
        original = self.module.subprocess.run
        self.module.subprocess.run = fake_run
        try:
            self.module.run(["swiftc.exe", "-v"])
        finally:
            self.module.subprocess.run = original
        self.assertEqual(seen["env"], environment, "run() must hand the child the Windows environment")
        self.assertEqual(seen["timeout"], contracts.section(
            "shared-rules", "codeRunnerBlocks", "swift", "compile", "jobSecondsOnWindows"))

    def test_the_other_changes(self):
        self.assertTrue(self.module.CLANG.endswith("clang.exe"))
        self.assertEqual(self.module.OBJECT_ROOT, self.space.work)
        for flag in windows_rules("compile", "extraCompileFlags"):
            self.assertIn(flag, self.module.EMBEDDED_COMPILE)
            self.assertIn(flag, self.module.FULL_COMPILE)
        self.assertNotIn("-nonlib-dependency-scanner", self.module.EMBEDDED_LINK)

    def test_tidy_keeps_only_the_compilers_verdict(self):
        work = self.space.work / ("a" * 64)
        said = f"{work}\\main.swift:3:7: error: cannot find 'nmae' in scope"
        self.assertEqual(self.module.tidy(said, work), "main.swift:3:7: error: cannot find 'nmae' in scope")
        self.assertEqual(self.module.tidy(said.replace("\\", "/"), work),
                         "main.swift:3:7: error: cannot find 'nmae' in scope")
        self.assertEqual(self.module.tidy("warning: Unable to locate libSwiftScan", work), "")

    def run_a_job(self, words_of_the_full_compile):
        jobs = self.space.root / "jobs"
        cache = self.space.root / "cache"
        jobs.mkdir()
        cache.mkdir()
        (jobs / ("b" * 64 + ".swift")).write_text("print(nmae)\n", encoding="utf-8")

        def fake_run(arguments, **options):
            name = Path(str(arguments[0])).name
            if name == "clang.exe":
                return Completed(0)
            if "-c" in arguments and "-O" in arguments:
                return Completed(1, "", words_of_the_full_compile)
            return Completed(1, "", "main.swift:1:7: error: an embedded error")
        original = self.module.subprocess.run
        self.module.subprocess.run = fake_run
        try:
            line = self.module.compile_job(jobs / ("b" * 64 + ".swift"), cache)
        finally:
            self.module.subprocess.run = original
        return line, sorted(path.name for path in cache.iterdir())

    def test_a_compile_error_with_an_error_in_it_is_cached(self):
        line, cached = self.run_a_job(f"{self.space.work}\\{'b' * 64}\\main.swift:1:7: error: cannot find 'nmae' in scope")
        self.assertIn("compile error", line)
        self.assertEqual(cached, ["b" * 64 + ".json"])
        entry = json.loads((self.space.root / "cache" / ("b" * 64 + ".json")).read_text())
        self.assertEqual(entry["diagnostics"], "main.swift:1:7: error: cannot find 'nmae' in scope")

    def test_a_failure_with_no_error_in_it_is_never_cached(self):
        line, cached = self.run_a_job("warning: Unable to locate libSwiftScan")
        self.assertIn("not kept", line)
        self.assertEqual(cached, [])

    def test_a_missing_program_is_never_cached(self):
        def missing(arguments, **options):
            raise FileNotFoundError(2, "The system cannot find the file specified")
        jobs = self.space.root / "jobs2"
        jobs.mkdir()
        cache = self.space.root / "cache2"
        cache.mkdir()
        (jobs / ("c" * 64 + ".swift")).write_text("print(1)\n", encoding="utf-8")
        original = self.module.subprocess.run
        self.module.subprocess.run = missing
        try:
            line = self.module.compile_job(jobs / ("c" * 64 + ".swift"), cache)
        finally:
            self.module.subprocess.run = original
        self.assertIn("not kept", line)
        self.assertEqual(list(cache.iterdir()), [])

    def test_the_smoke_folder_is_this_processs_own_and_goes(self):
        made = []
        original = self.module.compile_one_way

        def watch(sources, compile_flags, link_flags, work, extra_objects=()):
            made.append(work)
            return None, "main.swift:1:1: error: stub"
        self.module.compile_one_way = watch
        loader = swift_windows_compile.load
        swift_windows_compile.load = lambda install, work_root: self.module
        try:
            swift_windows_compile.smoke_compile(self.space.install, self.space.work)
        finally:
            swift_windows_compile.load = loader
            self.module.compile_one_way = original
        self.assertEqual(len(made), 1)
        self.assertIn(f"_smoke-{os.getpid()}-", made[0].name)
        self.assertFalse(made[0].exists())

    def test_a_preflight_that_fails_touches_nothing(self):
        jobs = self.space.root / "jobs3"
        jobs.mkdir()
        job = jobs / ("d" * 64 + ".swift")
        job.write_text("print(1)\n", encoding="utf-8")
        cache = self.space.root / "cache3"
        os.environ["PLANTOIR_SWIFT_HOME"] = str(self.space.root)
        try:
            # The fake install's swiftc.exe is two bytes: nothing compiles.
            status = swift_windows_compile.main(["swift_windows_compile.py", str(jobs), str(cache)])
        finally:
            del os.environ["PLANTOIR_SWIFT_HOME"]
        self.assertEqual(status, swift_windows_compile.PREFLIGHT_FAILED)
        self.assertTrue(job.is_file(), "the job is left for the next preview")
        self.assertFalse(cache.exists() and any(cache.iterdir()))

    @unittest.skipUnless(ON_WINDOWS, "the per-block lock is msvcrt's (Windows)")
    def test_a_block_another_preview_is_compiling_is_left_to_it(self):
        held = fetch.Lock(self.space.work / "locks")
        held.path = self.space.work / "locks" / ("e" * 64 + ".lock")
        self.assertTrue(held.try_take())
        try:
            jobs = self.space.root / "jobs4"
            jobs.mkdir()
            job = jobs / ("e" * 64 + ".swift")
            job.write_text("print(1)\n", encoding="utf-8")
            line = self.module.compile_job(job, self.space.root / "cache4")
        finally:
            held.give_back()
        self.assertIn("another preview", line)
        self.assertTrue(job.is_file())


class RangeHandler(http.server.BaseHTTPRequestHandler):
    body = b""
    honour_range = True
    seen = []

    def do_GET(self):
        RangeHandler.seen.append(self.headers.get("Range"))
        start = 0
        wanted = self.headers.get("Range")
        if wanted and self.honour_range:
            start = int(wanted.split("=")[1].split("-")[0])
            self.send_response(206)
        else:
            self.send_response(200)
        data = self.body[start:]
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *arguments):
        pass


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-swift-download-"))
        RangeHandler.body = os.urandom(3 * fetch.CHUNK + 123)
        RangeHandler.honour_range = True
        RangeHandler.seen = []
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RangeHandler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/installer.exe"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_a_partial_download_is_resumed(self):
        destination = self.folder / "installer.exe"
        part = destination.with_name("installer.exe.part")
        part.write_bytes(RangeHandler.body[:1000])
        fetch.download(self.url, destination, len(RangeHandler.body))
        self.assertEqual(destination.read_bytes(), RangeHandler.body)
        self.assertEqual(RangeHandler.seen, ["bytes=1000-"])
        self.assertFalse(part.exists())

    def test_a_server_that_ignores_the_range_starts_again(self):
        RangeHandler.honour_range = False
        destination = self.folder / "installer.exe"
        destination.with_name("installer.exe.part").write_bytes(b"x" * 1000)
        fetch.download(self.url, destination, len(RangeHandler.body))
        self.assertEqual(destination.read_bytes(), RangeHandler.body)

    def test_a_download_of_the_wrong_length_is_not_kept(self):
        with self.assertRaises(fetch.Failed) as raised:
            fetch.download(self.url, self.folder / "installer.exe", len(RangeHandler.body) - 10)
        self.assertEqual(raised.exception.reason, "damaged")
        self.assertFalse((self.folder / "installer.exe").exists())

    def test_offline_says_offline(self):
        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()
        with self.assertRaises(fetch.Failed) as raised:
            fetch.download(f"http://127.0.0.1:{port}/x", self.folder / "x", 10)
        self.assertEqual(raised.exception.reason, "offline")

    def test_a_wrong_hash_is_thrown_away(self):
        path = self.folder / "file"
        path.write_bytes(b"abc")
        with self.assertRaises(fetch.Failed) as raised:
            fetch.check_digest(path, "sha256", "0" * 64)
        self.assertEqual(raised.exception.reason, "damaged")
        self.assertFalse(path.exists())
        path.write_bytes(b"abc")
        fetch.check_digest(path, "sha256", hashlib.sha256(b"abc").hexdigest().upper())

    def test_a_signature_that_is_not_apples_is_refused(self):
        path = self.folder / "file"
        for status, subject in (("Valid", "CN=Somebody Else"), ("NotSigned", ""), ("HashMismatch", "CN=Apple Inc., O=Apple Inc.")):
            path.write_bytes(b"abc")
            with self.subTest(status=status), self.assertRaises(fetch.Failed):
                fetch.check_signature(path, ["CN=Apple Inc.", "O=Apple Inc."], lambda _: (status, subject))
            self.assertFalse(path.exists())
        path.write_bytes(b"abc")
        fetch.check_signature(path, ["CN=Apple Inc.", "O=Apple Inc."],
                              lambda _: ("Valid", "CN=Apple Inc., O=Apple Inc., L=Cupertino, S=California, C=US"))
        self.assertTrue(path.exists())


class CabinetTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-swift-cab-"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def installer_with(self, cabinet: bytes, offset: int, tail: bytes = b"SIGNATURE") -> Path:
        path = self.folder / "installer.exe"
        path.write_bytes(b"\x00" * offset + cabinet + tail)
        return path

    def fake_cabinet(self, size: int) -> bytes:
        return b"MSCF" + b"\0" * 4 + struct.pack("<I", size) + b"\1" * (size - 12)

    def test_the_cabinet_is_carved_exactly(self):
        cabinet = self.fake_cabinet(4096)
        installer = self.installer_with(cabinet, 777)
        out = fetch.carve_cabinet(installer, self.folder / "container.cab", 777, 4096)
        self.assertEqual(out.read_bytes(), cabinet)

    def test_anything_else_at_the_offset_is_refused(self):
        installer = self.installer_with(self.fake_cabinet(4096), 777)
        for offset, size in ((776, 4096), (777, 4095)):
            with self.subTest(offset=offset, size=size), self.assertRaises(fetch.Failed) as raised:
                fetch.carve_cabinet(installer, self.folder / "container.cab", offset, size)
            self.assertEqual(raised.exception.reason, "damaged")
        short = self.installer_with(self.fake_cabinet(4096)[:2000], 777, b"")
        with self.assertRaises(fetch.Failed):
            fetch.carve_cabinet(short, self.folder / "container.cab", 777, 4096)

    @unittest.skipUnless(ON_WINDOWS and shutil.which("makecab"), "makecab.exe and expand.exe are Windows' own")
    def test_a_payload_comes_out_of_a_carved_cabinet_with_expand(self):
        # Two files: expand.exe writes a ONE-file cabinet under the cabinet's
        # own name, and the installer's has 33.
        source = self.folder / "a7"
        source.write_bytes(b"payload " * 5000)
        (self.folder / "a8").write_bytes(b"other " * 300)
        directives = self.folder / "make.ddf"
        lines = [".Set CabinetNameTemplate=real.cab", f".Set DiskDirectoryTemplate={self.folder}",
                 ".Set CompressionType=LZX", f'"{source}"', f'"{self.folder / "a8"}"']
        directives.write_text("\n".join(lines) + "\n", encoding="ascii")
        made = subprocess.run(["makecab", "/F", str(directives)], capture_output=True, text=True, cwd=str(self.folder))
        self.assertEqual(made.returncode, 0, made.stdout)
        cabinet = (self.folder / "real.cab").read_bytes()
        installer = self.installer_with(cabinet, 1312, b"TAIL" * 100)
        carved = fetch.carve_cabinet(installer, self.folder / "container.cab", 1312, len(cabinet))
        payload = {"id": "a7", "name": "thing.msi", "bytes": source.stat().st_size,
                   "sha512": hashlib.sha512(source.read_bytes()).hexdigest().upper()}
        out = fetch.expand_payload(carved, payload, self.folder / "out")
        self.assertEqual(out.name, "thing.msi")
        self.assertEqual(out.read_bytes(), source.read_bytes())
        payload["sha512"] = "0" * 128
        with self.assertRaises(fetch.Failed):
            fetch.expand_payload(carved, payload, self.folder / "out2")


class InstallStepTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-swift-steps-"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_another_installation_is_waited_for_three_times(self):
        answers = [1618, 1618, 1618, 0]
        slept = []
        fetch.administrative_install(self.folder / "x.msi", self.folder / "t", self.folder / "log",
                                     sleep=slept.append, runner=lambda _: Completed(answers.pop(0)))
        self.assertEqual(len(slept), 3)
        answers = [1618] * 4
        with self.assertRaises(fetch.Failed) as raised:
            fetch.administrative_install(self.folder / "x.msi", self.folder / "t", self.folder / "log",
                                         sleep=lambda _: None, runner=lambda _: Completed(answers.pop(0)))
        self.assertEqual(raised.exception.reason, "busy")
        for code, reason in ((112, "noRoom"), (1603, "unpack")):
            with self.subTest(code=code), self.assertRaises(fetch.Failed) as raised:
                fetch.administrative_install(self.folder / "x.msi", self.folder / "t", self.folder / "log",
                                             runner=lambda _: Completed(code))
            self.assertEqual(raised.exception.reason, reason)

    def test_the_trim_keeps_what_compiles_and_brings_the_vc_runtime(self):
        toolchain = self.folder / "toolchain"
        rules = fetch.pins()["trim"]
        for keep in rules["mustKeep"] + ["usr/bin/llvm-objdump.exe", "usr/bin/lld.exe", "usr/lib/swift/x.swiftmodule",
                                         "usr/lib/clang/19/lib/a.lib", "usr/lib/clang/19/include/stdint.h"]:
            path = toolchain / Path(keep)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"x")
        runtime = self.folder / "runtime" / "nested"
        runtime.mkdir(parents=True)
        for name in rules["vcRuntime"]:
            (runtime / name).write_bytes(b"dll")
        fetch.trim(toolchain, rules, self.folder / "runtime")
        self.assertFalse((toolchain / "usr/bin/llvm-objdump.exe").exists())
        self.assertFalse((toolchain / "usr/bin/lld.exe").exists())
        self.assertFalse((toolchain / "usr/lib/swift").exists())
        self.assertFalse((toolchain / "usr/lib/clang/19/lib").exists())
        self.assertTrue((toolchain / "usr/lib/clang/19/include/stdint.h").exists())
        for name in rules["vcRuntime"]:
            self.assertTrue((toolchain / "usr" / "bin" / name).is_file())
        (toolchain / Path(rules["mustKeep"][0])).unlink()
        with self.assertRaises(fetch.Failed):
            fetch.trim(toolchain, rules, self.folder / "runtime")

    def test_a_folder_held_open_for_a_moment_is_still_moved_into_place(self):
        staging = self.folder / "staging-1"
        staging.mkdir()
        (staging / "READY.json").write_text("{}")
        install = self.folder / "6.4.0"
        real = os.replace
        refusals = [PermissionError(5, "Access is denied")] * 2

        def flaky(source, target):
            if refusals:
                raise refusals.pop()
            return real(source, target)
        fetch.os.replace = flaky
        try:
            fetch.rename_into_place(staging, install, sleep=lambda _: None)
        finally:
            fetch.os.replace = real
        self.assertTrue((install / "READY.json").is_file())

    def test_what_a_killed_fetch_left_is_cleaned_up_and_old_versions_pruned(self):
        for name in ("staging-abcd", "old-6.3.0-1", "6.3.0", "6.4.0", fetch.DOWNLOAD_FOLDER, fetch.WORK_FOLDER, "other"):
            (self.folder / name).mkdir()
        fetch.clean_up(self.folder, "6.4.0")
        self.assertEqual(sorted(path.name for path in self.folder.iterdir()),
                         sorted(["6.4.0", fetch.DOWNLOAD_FOLDER, fetch.WORK_FOLDER, "other"]))

    def test_ready_means_this_pins_install_and_its_tools(self):
        space = FakeInstall()
        try:
            self.assertFalse(fetch.is_ready(space.root))
            space.mark_ready("0" * 64)
            self.assertFalse(fetch.is_ready(space.root), "another pin's install is not ready")
            space.mark_ready()
            self.assertTrue(fetch.is_ready(space.root))
            fetch.tool_paths(space.install)["wasmOpt"].unlink()
            self.assertFalse(fetch.is_ready(space.root))
        finally:
            space.remove()

    def test_progress_is_said_every_ten_per_cent_and_never_at_a_hundred(self):
        said = []
        progress = fetch.Progress(1000, said.append)
        tell = progress.callback(0)
        for done in range(0, 1001, 7):
            tell(done)
        tell(1000)
        self.assertEqual(len(said), 9)
        self.assertIn("10%", said[0])
        self.assertIn("90%", said[-1])


class EnsureTests(unittest.TestCase):
    def setUp(self):
        self.space = FakeInstall()
        shutil.rmtree(self.space.install)
        self.said = []

    def tearDown(self):
        self.space.remove()

    def ready_fetch(self, root, say):
        FakeInstall.__init__(self.space)  # lays the install out again
        self.space.mark_ready()
        return {"totalSeconds": 91.6, "downloadedBytes": 2301721200}

    def markers(self):
        return [json.loads(line[len(fetch.MARKER):]) for line in self.said if line.startswith(fetch.MARKER)]

    def test_ready_is_said_once_with_its_marker(self):
        status = fetch.ensure(self.space.root, self.said.append, fetcher=lambda root, say: self.ready_fetch(root, say),
                              course="ICS3U", section="1")
        self.assertEqual(status, fetch.READY)
        self.assertEqual(self.said[0], fetch.printed("gettingReady"))
        self.assertIn(fetch.printed("ready"), self.said)
        self.assertEqual(self.markers(), [{"course": "ICS3U", "section": 1, "ready": True, "seconds": 92,
                                           "downloadedBytes": 2301721200}])
        self.said.clear()
        self.assertEqual(fetch.ensure(self.space.root, self.said.append), fetch.READY)
        self.assertEqual(self.said, [], "an install that is ready says nothing")

    def test_each_failure_has_its_exit_and_its_words(self):
        for reason, status in (("offline", fetch.NOT_DOWNLOADED), ("damaged", fetch.NOT_DOWNLOADED),
                               ("noRoom", fetch.NO_ROOM), ("busy", fetch.NOT_FINISHED), ("unpack", fetch.NOT_FINISHED)):
            self.said.clear()

            def failing(root, say, reason=reason):
                raise fetch.Failed(reason, "test")
            with self.subTest(reason=reason):
                self.assertEqual(fetch.ensure(self.space.root, self.said.append, fetcher=failing), status)
                # The disk filling part way has its own sentence, with no numbers in it (#672).
                self.assertIn(fetch.printed("ranOutOfRoom" if reason == "noRoom" else reason), self.said)
                self.assertEqual(self.markers(), [{"ready": False, "reason": reason}])

    def test_too_little_room_downloads_nothing(self):
        original = fetch.free_gigabytes
        fetch.free_gigabytes = lambda root: 2
        try:
            status = fetch.ensure(self.space.root, self.said.append,
                                  fetcher=lambda root, say: self.fail("nothing is fetched"))
        finally:
            fetch.free_gigabytes = original
        self.assertEqual(status, fetch.NO_ROOM)
        self.assertEqual(self.said[0], fetch.printed("noRoom", gigabytes=fetch.need_gigabytes(), free=2))

    def test_no_printed_line_keeps_a_placeholder(self):
        # #672: a part-way noRoom printed "{gigabytes}" and "{free}" unfilled,
        # and the test above asserted that text, so the suite was green over
        # it. Every ending ensure has is driven here; the marker lines are
        # JSON and carry braces of their own, so they are left out.
        placeholder = re.compile(r"\{[A-Za-z]+\}")
        endings = []

        def progressing(root, say):
            tell = fetch.Progress(1000, say).callback(0)
            tell(500)
            return self.ready_fetch(root, say)
        endings.append(("ready", progressing))
        for reason in ("offline", "damaged", "noRoom", "busy", "unpack"):
            def failing(root, say, reason=reason):
                raise fetch.Failed(reason, "test")
            endings.append((reason, failing))

        def broken(root, say):
            raise RuntimeError("unexpected")
        endings.append(("unexpected", broken))
        for name, fetcher in endings:
            self.said.clear()
            shutil.rmtree(self.space.install, ignore_errors=True)
            with self.subTest(ending=name):
                fetch.ensure(self.space.root, self.said.append, fetcher=fetcher)
                self.assertTrue(self.said)
                self.assert_no_placeholder(placeholder)

        self.said.clear()
        shutil.rmtree(self.space.install, ignore_errors=True)
        original = fetch.free_gigabytes
        fetch.free_gigabytes = lambda root: 2
        try:
            fetch.ensure(self.space.root, self.said.append, fetcher=lambda root, say: self.fail("nothing is fetched"))
        finally:
            fetch.free_gigabytes = original
        with self.subTest(ending="too little room before starting"):
            self.assert_no_placeholder(placeholder)

        if ON_WINDOWS:
            self.said.clear()
            held = fetch.Lock(self.space.root)
            self.assertTrue(held.try_take())
            try:
                fetch.ensure(self.space.root, self.said.append, wait_seconds=0,
                             fetcher=lambda root, say: self.fail("nothing is fetched"))
            finally:
                held.give_back()
            with self.subTest(ending="waited for another"):
                self.assert_no_placeholder(placeholder)

    def assert_no_placeholder(self, placeholder):
        for line in self.said:
            if line.startswith(fetch.MARKER):
                continue
            self.assertIsNone(placeholder.search(line), line)

    @unittest.skipUnless(ON_WINDOWS, "the fetch lock is msvcrt's (Windows)")
    def test_a_second_launcher_waits_then_gives_up(self):
        held = fetch.Lock(self.space.root)
        self.assertTrue(held.try_take())
        try:
            status = fetch.ensure(self.space.root, self.said.append, wait_seconds=0,
                                  fetcher=lambda root, say: self.fail("nothing is fetched"))
        finally:
            held.give_back()
        self.assertEqual(status, fetch.NOT_FINISHED)
        self.assertEqual(self.said[:2], [fetch.printed("waitingForAnother"), fetch.printed("stillGettingReady")])
        self.assertEqual(self.markers(), [{"ready": False, "reason": "waited"}])

    def test_anything_unexpected_is_a_failure_with_its_marker_not_a_traceback(self):
        def broken(root, say):
            raise subprocess.TimeoutExpired("powershell.exe", 300)
        status = fetch.ensure(self.space.root, self.said.append, fetcher=broken)
        self.assertEqual(status, fetch.NOT_FINISHED)
        self.assertIn(fetch.printed("unpack"), self.said)
        self.assertEqual(self.markers(), [{"ready": False, "reason": "unpack"}])

    def test_a_signature_check_that_hangs_is_a_failure(self):
        original = fetch.subprocess.run

        def hangs(*arguments, **options):
            raise subprocess.TimeoutExpired("powershell.exe", 300)
        fetch.subprocess.run = hangs
        try:
            with self.assertRaises(fetch.Failed) as raised:
                fetch.authenticode(self.space.root / "x.exe")
        finally:
            fetch.subprocess.run = original
        self.assertEqual(raised.exception.reason, "unpack")


class WordsTests(unittest.TestCase):
    MACHINERY = ("toolchain", "script", "docker", "container", "compiler", "sdk", "wasm", "msi", "binaryen",
                 "installer", "cabinet", "token", "model")

    def test_no_printed_line_names_the_machinery(self):
        for name, sentence in windows_rules("printed").items():
            with self.subTest(name=name):
                lowered = sentence.lower()
                for word in self.MACHINERY:
                    self.assertNotIn(word, lowered)

    def test_preview_ps1_prints_the_launchers_two_lines_and_plans_before_the_build(self):
        text = (REPO / "preview.ps1").read_text(encoding="utf-8")
        self.assertIn("Making {1} Swift {2} ready to run{3}", text)
        self.assertIn(windows_rules("printed", "couldNotCompile")[len("⚠️  "):], text)
        self.assertEqual(windows_rules("printed", "compiling"), "🦅 Making {count} Swift {noun} ready to run…")
        self.assertLess(text.index("Invoke-RunnableSwift $py"), text.index("'build_site.py') @argList"))
        self.assertIn("swift_windows_fetch.py') ensure", text)
        self.assertIn("swift_windows_compile.py')", text)

    def test_the_trail_names_both_events_and_their_marker(self):
        events = {entry["event"]: entry for entry in contracts.section("shared-rules", "activityTrail", "mustRecord")}
        self.assertIn("Swift got ready on this computer", events)
        failed = events["Swift could not be got ready"]
        self.assertEqual(set(failed["whyWords"]), {"offline", "noRoom", "damaged", "busy", "unpack", "waited"})
        for example in windows_rules("marker", "examples"):
            self.assertTrue(example.startswith(fetch.MARKER))
            json.loads(example[len(fetch.MARKER):])

    def test_the_download_size_fills_the_macs_sentence_unchanged(self):
        reasons = contracts.section("shared-rules", "codeRunnerBlocks", "swift", "reasons")
        problem = {"page": "Unit 1", "block": 1, "line": 3, "reason": "notDownloaded"}
        mac = swift_blocks.reason_sentence(problem, 6, windows=False)
        self.assertEqual(mac, "Swift could not be downloaded to this computer - preview the course again while it is "
                              "connected to the internet (the first time downloads about 1.3 GB)")
        self.assertIn("about 2.3 GB", swift_blocks.reason_sentence(problem, 6, windows=True))
        self.assertNotIn("notOnWindows", reasons)


if __name__ == "__main__":
    unittest.main()
