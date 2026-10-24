#!/usr/bin/env python3
"""preview.sh's Swift step prints the PLANTOIR_SWIFT: line on every ending
but "already there" (GitHub #635, contracts/shared-rules.json ->
codeRunnerBlocks.swift.mac).

This cuts preview.sh's runnable-Swift block out - from its
`# -------------------- Runnable Swift (#493)` line to the bare
`prepare_runnable_swift` - and runs it with bash 3.2, the bash a teacher's
Mac has, against a scratch folder. `docker` is a small stand-in: it answers
the plan, the image check, the free-space check and the image build as each
case says, and it runs `swift_blocks.py got-ready` - the REAL script, with
the repository's contract - where preview.sh would run it in the website
builder. The build lock is moved into the scratch folder and its wait
shortened, after checking both are the literals the contract names; the
real /tmp lock is never touched.

macOS only, as test_helper_bootstrap.py: the block is the Mac's (Windows
has no image to build, and runs the Python half through test_swift_blocks.py).
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
BLOCK_START = "# -------------------- Runnable Swift (#493)"
BASH = "/bin/bash"
ON_A_MAC = sys.platform == "darwin" and Path(BASH).exists()
LOCK_LITERAL = '/tmp/plantoir-swift-build-$(id -u).lock'
WAIT_LITERAL = 'if [ "$waited" -ge 1200 ]; then'
MARKER = "PLANTOIR_SWIFT:"
REAL_LOG = REPOSITORY_ROOT / "scripts" / "fixtures" / "swift-image-build" / "cached.log"
# The fallback preview.sh prints itself when the website builder said nothing
# a teacher can read (#642): its echo line, held equal to mac.printed.unpack.
FALLBACK_START = 'echo "'

DOCKER_STUB = """#!/bin/bash
# The stand-in docker: every call is written down, and answered from $STUB.
echo "$*" >> "$STUB/calls"
case "$1" in
  exec)
    shift 2
    case "$*" in
      *"swift_blocks.py plan"*)
        cat "$STUB/plan" ;;
      *"swift_blocks.py got-ready"*)
        shift 2
        # A builder that cannot be asked prints nothing; an older copy of the
        # script prints only the marker (#642's fallback, both cases).
        [ -f "$STUB/got-ready-silent" ] && exit 1
        if [ -f "$STUB/got-ready-only-marker" ]; then
          echo 'PLANTOIR_SWIFT: {"ready": false, "reason": "offline"}'
          exit 0
        fi
        PLANTOIR_CONTRACTS_DIR="$STUB_CONTRACTS" exec python3 "$STUB_SCRIPTS/swift_blocks.py" "$@" ;;
      "df -Pk /")
        echo "Filesystem 1024-blocks Used Available Capacity Mounted"
        echo "overlay 100000000 1 $(cat "$STUB/free-kilobytes") 1% /" ;;
    esac ;;
  image)
    [ -f "$STUB/image-present" ] ;;
  buildx)
    case "$2" in
      version) exit 0 ;;
      build)
        cat "$STUB/build-log"
        status=$(cat "$STUB/build-exit")
        [ "$status" = "0" ] && touch "$STUB/image-present"
        exit "$status" ;;
    esac ;;
  run) exit 0 ;;
  *) exit 0 ;;
esac
"""


def swift_block():
    lines = (REPOSITORY_ROOT / "preview.sh").read_text(encoding="utf-8").split("\n")
    block = []
    inside = False
    for line in lines:
        if line.startswith(BLOCK_START):
            inside = True
        if inside:
            block.append(line)
            if line == "prepare_runnable_swift":
                return "\n".join(block)
    return ""


def the_mac_rules():
    shared = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    return shared["codeRunnerBlocks"]["swift"]


def pin_bytes(*names):
    toolchain = json.loads((REPOSITORY_ROOT / "contracts" / "toolchain.json").read_text(encoding="utf-8"))
    total = 0
    for pin in toolchain["swiftImage"]["pins"]:
        if pin["pin"] in names:
            total += pin["bytes"]
    return total


@unittest.skipUnless(ON_A_MAC, "preview.sh's Swift step runs on a Mac only")
class SwiftLauncherMarkerTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.block = swift_block()

    def setUp(self):
        self.world = Path(tempfile.mkdtemp(prefix="plantoir-swift-marker-"))
        self.stub = self.world / "stub"
        self.bin = self.world / "bin"
        self.root = self.world / "cache"
        self.context = self.world / "toolchain"
        for folder in (self.stub, self.bin, self.root / "jobs" / "run", self.context / "support" / "swift"):
            folder.mkdir(parents=True)
        (self.context / "support" / "swift" / "Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        docker = self.bin / "docker"
        docker.write_text(DOCKER_STUB, encoding="utf-8")
        docker.chmod(0o755)
        (self.stub / "plan").write_text(
            f"root={self.root}\ncache={self.root / 'cache'}\njobs={self.root / 'jobs' / 'run'}\ncount=2\n",
            encoding="utf-8")
        self.set_free_gigabytes(50)
        self.lock = self.world / "swift-build.lock"

    def tearDown(self):
        shutil.rmtree(self.world, ignore_errors=True)

    def set_free_gigabytes(self, gigabytes):
        (self.stub / "free-kilobytes").write_text(str(gigabytes * 1048576), encoding="utf-8")

    def set_build(self, log_text, status):
        (self.stub / "build-log").write_text(log_text, encoding="utf-8")
        (self.stub / "build-exit").write_text(str(status), encoding="utf-8")

    def run_block(self, wait_seconds=1200):
        block = self.block.replace(LOCK_LITERAL, str(self.lock))
        block = block.replace(WAIT_LITERAL, f'if [ "$waited" -ge {wait_seconds} ]; then')
        prologue = "\n".join([
            'CONTAINER_NAME="teaching-quartz-test"',
            'COURSE="ICS3U"',
            'SECTION="2"',
            'FULL_REBUILD=""',
            f'resolve_build_context() {{ echo "{self.context}"; }}',
            'toolchain_hash() { echo "abcd1234"; }',
            'bind_mount_argument() { echo "type=bind,source=$1,target=$2"; }',
        ])
        environment = {
            "PATH": ":".join([str(self.bin), "/usr/bin", "/bin", "/usr/sbin", "/sbin"]),
            "STUB": str(self.stub),
            "STUB_CONTRACTS": str(REPOSITORY_ROOT / "contracts"),
            "STUB_SCRIPTS": str(REPOSITORY_ROOT / "scripts"),
            "HOME": str(self.world),
            "LANG": "en_US.UTF-8",
        }
        result = subprocess.run([BASH, "-c", prologue + "\n" + block], capture_output=True, text=True,
                                env=environment, timeout=60)
        return result.stdout

    def markers_in(self, output):
        found = []
        for line in output.split("\n"):
            if line.startswith(MARKER):
                found.append(json.loads(line[len(MARKER):].strip()))
        return found

    def the_one_marker(self, output, sentence_part):
        markers = self.markers_in(output)
        self.assertEqual(len(markers), 1, output)
        lines = output.split("\n")
        sentence_at = -1
        marker_at = -1
        for index, line in enumerate(lines):
            if sentence_part in line and sentence_at < 0:
                sentence_at = index
            if line.startswith(MARKER):
                marker_at = index
        self.assertGreaterEqual(sentence_at, 0, output)
        self.assertLess(sentence_at, marker_at, "the teacher's sentence comes before the line for the app")
        return markers[0]

    # MARK: - The text itself

    def test_the_block_is_cut_and_carries_the_literals_the_contract_names(self):
        self.assertTrue(self.block.endswith("\nprepare_runnable_swift"), "the block was not found in preview.sh")
        self.assertIn(LOCK_LITERAL, self.block)
        self.assertIn(WAIT_LITERAL, self.block)
        self.assertEqual(the_mac_rules()["windows"]["waitSeconds"], 1200,
                         "the build lock's wait is the contract's waitSeconds (the trail's '20 minutes')")

    # MARK: - Each ending

    def test_an_image_already_there_prints_nothing(self):
        (self.stub / "image-present").touch()
        output = self.run_block()
        self.assertEqual(self.markers_in(output), [], output)
        self.assertIn("Making 2 Swift programs ready to run", output)

    def test_too_little_room_says_no_room(self):
        self.set_free_gigabytes(3)
        marker = self.the_one_marker(self.run_block(), "Not enough free space to get Swift ready")
        self.assertEqual(marker, {"course": "ICS3U", "section": 2, "ready": False, "reason": "noRoom"})
        self.assertNotIn("buildx build", (self.stub / "calls").read_text(encoding="utf-8"), "it built anyway")

    def test_a_wait_that_gives_up_says_waited(self):
        self.lock.mkdir()
        # Held by a launcher that is alive: this test's own process.
        (self.lock / "pid").write_text(str(os.getpid()), encoding="utf-8")
        marker = self.the_one_marker(self.run_block(wait_seconds=0), "Swift is still being got ready")
        self.assertEqual(marker, {"course": "ICS3U", "section": 2, "ready": False, "reason": "waited"})
        self.assertTrue(self.lock.is_dir(), "another launcher's lock was taken")

    def test_a_first_build_counts_what_it_downloaded(self):
        fresh = REAL_LOG.read_text(encoding="utf-8").replace("#6 CACHED", "#6 DONE 61.4s").replace(
            "#9 CACHED", "#9 DONE 4.1s")
        self.set_build(fresh, 0)
        marker = self.the_one_marker(self.run_block(), "Swift is ready.")
        self.assertEqual(marker["downloadedBytes"], pin_bytes("swiftToolchainArm64", "wasmSdk", "binaryenArm64"))
        self.assertEqual(marker["ready"], True)
        self.assertEqual((marker["course"], marker["section"]), ("ICS3U", 2))
        self.assertIsInstance(marker["seconds"], int)
        self.assertFalse(self.lock.exists(), "the build lock was not given back")

    def test_a_build_from_cached_layers_downloaded_nothing(self):
        self.set_build(REAL_LOG.read_text(encoding="utf-8"), 0)
        marker = self.the_one_marker(self.run_block(), "Swift is ready.")
        self.assertEqual(marker["downloadedBytes"], 0)

    def test_a_failed_build_says_why(self):
        """#642: the sentence is the one for the reason the log gives
        (mac.printed), printed before the marker, and state.json is what
        mac.stateForReason says. Until #642 every case here printed offline's
        sentence and wrote {state: notDownloaded}."""
        rules = the_mac_rules()["mac"]
        cases = [
            ("#6 0.31 curl: (6) Could not resolve host: download.swift.org\n#6 ERROR: exit code: 6\n", "offline"),
            ("#6 180.77 curl: (92) HTTP/2 stream 1 was not closed cleanly: INTERNAL_ERROR (err 2)\n"
             "#6 ERROR: exit code: 92\n", "offline"),
            ("#6 45.0 /tmp/swift.tar.gz: FAILED\n#6 45.0 sha256sum: WARNING: 1 computed checksum did NOT match\n"
             "#6 ERROR: exit code: 1\n", "damaged"),
            ("#6 48.1 tar: Cannot write: No space left on device\n#6 ERROR: exit code: 2\n", "noRoom"),
            ("#9 0.80 curl: (22) The requested URL returned error: 404\n#9 ERROR: exit code: 22\n", "unpack"),
        ]
        for log_text, reason in cases:
            with self.subTest(log_text.split("\n")[0]):
                (self.stub / "image-present").unlink(missing_ok=True)
                (self.root / "state.json").unlink(missing_ok=True)
                self.set_build(log_text, 1)
                output = self.run_block()
                marker = self.the_one_marker(output, rules["printed"][reason])
                self.assertEqual(marker, {"course": "ICS3U", "section": 2, "ready": False, "reason": reason})
                for other, sentence in rules["printed"].items():
                    if other != reason:
                        self.assertNotIn(sentence, output, f"{reason} also said {other}'s sentence")
                expected = {"reason": reason}
                if rules["stateForReason"][reason] is not None:
                    expected["state"] = rules["stateForReason"][reason]
                self.assertEqual(json.loads((self.root / "state.json").read_text(encoding="utf-8")), expected)
                self.assertFalse(self.lock.exists(), "the build lock was not given back")

    def test_a_builder_that_cannot_be_asked_still_tells_the_teacher(self):
        """#642: when the website builder prints nothing, preview.sh prints
        mac.printed.unpack itself and writes no state.json, so the blocks say
        "preview the course again" rather than blaming the internet."""
        (self.stub / "got-ready-silent").touch()
        self.set_build("#6 0.31 curl: (6) Could not resolve host: download.swift.org\n#6 ERROR: exit code: 6\n", 1)
        output = self.run_block()
        self.assertIn(the_mac_rules()["mac"]["printed"]["unpack"], output)
        self.assertEqual(self.markers_in(output), [], output)
        self.assertFalse((self.root / "state.json").exists(), "a state.json nobody chose was written")
        self.assertFalse(self.lock.exists(), "the build lock was not given back")

    def test_a_builder_that_prints_only_the_marker_still_tells_the_teacher(self):
        """#642, director's ruling 2: an older swift_blocks.py ignores --state
        and prints the marker alone; the fallback fires then too, before it."""
        (self.stub / "got-ready-only-marker").touch()
        self.set_build("#6 ERROR: exit code: 1\n", 1)
        output = self.run_block()
        marker = self.the_one_marker(output, the_mac_rules()["mac"]["printed"]["unpack"])
        self.assertEqual(marker["ready"], False)
        self.assertFalse((self.root / "state.json").exists())

    def test_the_fallback_is_mac_printed_unpack_word_for_word(self):
        unpack = the_mac_rules()["mac"]["printed"]["unpack"]
        self.assertIn(f'{FALLBACK_START}{unpack}"', self.block)
        offline = the_mac_rules()["mac"]["printed"]["offline"]
        self.assertNotIn(offline, self.block, "preview.sh still carries a failure's sentence of its own")

if __name__ == "__main__":
    unittest.main()
