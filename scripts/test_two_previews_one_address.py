#!/usr/bin/env python3
"""
Two previews handed the same address never stop each other (GitHub #835,
`contracts/shared-rules.json` -> `twoPreviewsOneAddress`).

A working folder's previews share its website builder's four addresses, and
each program that starts a preview chooses one on its own, so two copies of
Plantoir (or a copy and an assistant's server) could hand two previews the
same one. The second serving run then stopped the first: 3 of 3 measured on
2026-11-13. A serving run now claims its address, under one lock, before it
builds anything; a run whose address another live preview claimed stops in
words instead.

This runs the REAL claim from build_site.py in two processes at the same
moment, many times, with the claims kept in a scratch folder
(PLANTOIR_PREVIEW_CLAIMS_DIR) rather than the builder's temporary folder.
Pure stdlib, no Docker. The claim needs fcntl, so these skip where there is
none (Windows, which probes its host-global ports just before the bind and
does not run this code). Listed in verify.sh's step 0. Run with:

    python3 scripts/test_two_previews_one_address.py
"""

import json
import multiprocessing
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import build_site  # noqa: E402

try:
    import fcntl  # noqa: F401
    HAS_FCNTL = True
except ImportError:
    HAS_FCNTL = False

TRIALS = 100


def the_rule() -> dict:
    rules = json.loads((SCRIPTS.parent / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    return rules["twoPreviewsOneAddress"]


def claim_and_hold(folder: str, port: int, course: str, section: int, barrier, answers):
    os.environ["PLANTOIR_PREVIEW_CLAIMS_DIR"] = folder
    barrier.wait(timeout=60)            # both start together
    try:
        holder = build_site.claim_the_preview_address(port, course, section)
    except Exception as error:          # reported, so the test fails rather than waits
        holder = f"FAILED: {error!r}"
    answers.put((section, holder))
    barrier.wait(timeout=60)            # both have claimed; the winner still holds it
    barrier.wait(timeout=60)            # the test has looked


@unittest.skipUnless(HAS_FCNTL, "the claim needs fcntl (Windows probes its ports natively)")
class OneAddressOnePreview(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-preview-claims-"))
        os.environ["PLANTOIR_PREVIEW_CLAIMS_DIR"] = str(self.folder)

    def tearDown(self):
        os.environ.pop("PLANTOIR_PREVIEW_CLAIMS_DIR", None)
        shutil.rmtree(self.folder, ignore_errors=True)

    def claim_file(self, port: int) -> Path:
        return self.folder / f"plantoir-preview-address-{port}.claim"

    def a_claim(self, port: int, pid: int, course: str, section: int, started=None):
        """A claim as a run writes it: `started` is the process's own start
        unless the test gives another (a claim left by an earlier process)."""
        if started is None:
            started = build_site._when_a_process_started(pid)
        self.claim_file(port).write_text(json.dumps({"pid": pid, "started": started, "course": course,
                                                     "section": section}), encoding="utf-8")

    def a_live_stranger(self) -> subprocess.Popen:
        """A live process that is not any preview, ended by tearDown."""
        stranger = subprocess.Popen(["sleep", "60"], start_new_session=True)
        self.addCleanup(self.end_the_stranger, stranger)
        return stranger

    def end_the_stranger(self, stranger: subprocess.Popen):
        try:
            os.killpg(stranger.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stranger.wait(timeout=30)

    def test_two_sections_claiming_one_address_at_once_get_it_once(self):
        context = multiprocessing.get_context("spawn")
        both: int = 0
        neither: int = 0
        for trial in range(TRIALS):
            barrier = context.Barrier(3)
            answers = context.Queue()
            claimants = [context.Process(target=claim_and_hold,
                                         args=(str(self.folder), 8081, "EXC2O", section, barrier, answers))
                         for section in (1, 2)]
            for claimant in claimants:
                claimant.start()
            barrier.wait(timeout=60)
            barrier.wait(timeout=60)
            said: dict = {}
            for _ in range(2):
                section, holder = answers.get(timeout=30)
                said[section] = holder
            owners: list = []
            for section, holder in said.items():
                if holder is None:
                    owners.append(section)
            if len(owners) == 2:
                both += 1
            if len(owners) == 0:
                neither += 1
            if len(owners) == 1:
                other = 2 if owners[0] == 1 else 1
                self.assertEqual(said[other], f"EXC2O section {owners[0]}")
            barrier.wait(timeout=60)
            for claimant in claimants:
                claimant.join(timeout=30)
            self.assertFalse(self.claim_file(8081).exists(), "the claim is given back when its build ends")
        self.assertEqual((both, neither), (0, 0),
                         f"in {TRIALS} trials both sections got the address {both} times and neither {neither}")

    def test_a_claim_waits_for_the_lock(self):
        # The look and the write are one step: while another run holds the
        # builder's lock, a claim does not answer. Without the lock it would
        # answer at once, and two runs could both read "free".
        import fcntl
        import time
        lock = open(self.folder / "plantoir-preview-addresses.lock", "a")
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        program = ("import sys; sys.path.insert(0, %r); import build_site; "
                   "print(build_site.claim_the_preview_address(8081, 'EXC2O', 1))") % str(SCRIPTS)
        claimant = subprocess.Popen([sys.executable, "-B", "-c", program], stdout=subprocess.PIPE,
                                    env=dict(os.environ, PLANTOIR_PREVIEW_CLAIMS_DIR=str(self.folder)))
        try:
            time.sleep(3)
            self.assertIsNone(claimant.poll(), "the claim answered while the lock was held")
            self.assertFalse(self.claim_file(8081).exists())
        finally:
            lock.close()
        out, _ = claimant.communicate(timeout=60)
        self.assertEqual(out.decode("utf-8").strip(), "None")

    def test_the_same_section_started_again_takes_its_address_back(self):
        self.a_claim(8081, os.getppid(), "EXC2O", 1)
        self.assertIsNone(build_site.claim_the_preview_address(8081, "EXC2O", 1))

    def test_a_claim_whose_build_has_gone_counts_for_nothing(self):
        gone = subprocess.Popen([sys.executable, "-c", "pass"])
        gone.wait()
        self.claim_file(8082).write_text(json.dumps({"pid": gone.pid, "course": "EXC2O", "section": 1}),
                                         encoding="utf-8")
        self.assertIsNone(build_site.claim_the_preview_address(8082, "EXC2O", 2))

    def test_another_course_on_the_address_is_another_preview(self):
        self.a_claim(8083, os.getppid(), "ICS3U", 1)
        self.assertEqual(build_site.claim_the_preview_address(8083, "EXC2O", 1), "ICS3U section 1")
        self.assertIsNone(build_site.a_claim_that_proves_nothing(8083, "EXC2O", 1), "a proven claim is not left over")

    # --- A claim proves its holder (#835 review H1) -----------------------

    def test_a_live_process_that_did_not_write_the_claim_proves_nothing(self):
        # The builder after a restart: the claim's process id is alive again,
        # but it is some other program's. Before H1 this refused (exit 75)
        # for a preview that did not exist.
        stranger = self.a_live_stranger()
        self.a_claim(8082, stranger.pid, "ICS3U", 2, started="ps:a moment long before this process began")
        self.assertEqual(build_site.a_claim_that_proves_nothing(8082, "MPM2D", 2), "ICS3U section 2")
        self.assertIsNone(build_site.claim_the_preview_address(8082, "MPM2D", 2))
        self.assertEqual(json.loads(self.claim_file(8082).read_text(encoding="utf-8"))["course"], "MPM2D")

    def test_a_claim_without_a_start_proves_nothing(self):
        stranger = self.a_live_stranger()
        self.claim_file(8084).write_text(json.dumps({"pid": stranger.pid, "course": "ICS3U", "section": 1}),
                                         encoding="utf-8")
        self.assertIsNone(build_site.claim_the_preview_address(8084, "EXC2O", 1))

    def test_after_a_restart_a_preview_is_not_refused_for_one_that_does_not_exist(self):
        # The review's reproduction as a run: a claim naming a live process
        # that is not a preview, and a second course's preview asking for
        # the same address, which must build rather than exit 75.
        stranger = self.a_live_stranger()
        self.a_claim(8082, stranger.pid, "ICS3U", 2, started="proc:an-earlier-boot:12345")
        program = ("import sys; sys.path.insert(0, %r); import build_site; "
                   "build_site.refuse_when_the_preview_address_is_another_previews(8082, 'MPM2D', 2); "
                   "print('WENT AHEAD')") % str(SCRIPTS)
        result = subprocess.run([sys.executable, "-B", "-c", program], capture_output=True, timeout=120,
                                env=dict(os.environ, PLANTOIR_PREVIEW_CLAIMS_DIR=str(self.folder)))
        said = result.stdout.decode("utf-8")
        self.assertEqual(result.returncode, 0, said)
        self.assertIn("WENT AHEAD", said)
        self.assertNotIn("cannot be previewed", said)

    def test_a_stopped_preview_gives_its_address_back(self):
        # SIGTERM is what a stop sends first, SIGHUP what a closed terminal
        # sends, SIGINT is Stop in the app: each gives the claim back.
        program = ("import sys, time; sys.path.insert(0, %r); import build_site; "
                   "build_site.claim_the_preview_address(8081, 'EXC2O', 1); print('CLAIMED', flush=True); "
                   "time.sleep(60)") % str(SCRIPTS)
        for stopped_by in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            with self.subTest(stopped_by.name):
                run = subprocess.Popen([sys.executable, "-B", "-c", program], stdout=subprocess.PIPE,
                                       start_new_session=True,
                                       env=dict(os.environ, PLANTOIR_PREVIEW_CLAIMS_DIR=str(self.folder)))
                self.assertEqual(run.stdout.readline().decode("utf-8").strip(), "CLAIMED")
                self.assertTrue(self.claim_file(8081).exists())
                run.send_signal(stopped_by)
                run.communicate(timeout=30)
                self.assertFalse(self.claim_file(8081).exists(), f"{stopped_by.name} left the claim")

    def test_an_unreadable_claim_counts_for_nothing(self):
        self.claim_file(8084).write_text("{not json", encoding="utf-8")
        self.assertIsNone(build_site.claim_the_preview_address(8084, "EXC2O", 1))

    def test_a_refused_run_says_the_contracts_words_and_exits_75(self):
        self.a_claim(8081, os.getpid(), "EXC2O", 1)
        program = ("import sys; sys.path.insert(0, %r); import build_site; "
                   "build_site.refuse_when_the_preview_address_is_another_previews(8081, 'EXC2O', 2)") % str(SCRIPTS)
        result = subprocess.run([sys.executable, "-B", "-c", program], capture_output=True, timeout=120,
                                env=dict(os.environ, PLANTOIR_PREVIEW_CLAIMS_DIR=str(self.folder)))
        rule = the_rule()
        self.assertEqual(result.returncode, rule["exitCode"])
        printed = result.stdout.decode("utf-8").splitlines()
        expected: list = []
        for line in rule["sentences"]["launcher"]:
            expected.append(line.replace("{course}", "EXC2O").replace("{section}", "2")
                            .replace("{other}", "EXC2O section 1"))
        self.assertEqual(printed[-2:], expected)
        held = json.loads(self.claim_file(8081).read_text(encoding="utf-8"))
        self.assertEqual(held["section"], 1, "the refused run leaves the other's claim alone")


# The review's reproduction in a REAL website builder, when asked for: a
# preview killed outright leaves its claim; the builder restarts and hands
# the same process id to an unrelated program; a preview of another course
# asks for that address. Opt-in (needs Docker and an image): give the tag in
# PLANTOIR_PREVIEW_CLAIM_IMAGE. A container of its own, removed after.
REAL_IMAGE = os.environ.get("PLANTOIR_PREVIEW_CLAIM_IMAGE", "")


@unittest.skipUnless(REAL_IMAGE and shutil.which("docker") and sys.platform == "darwin",
                     "set PLANTOIR_PREVIEW_CLAIM_IMAGE to run it in a real website builder")
class AfterARestartInARealBuilder(unittest.TestCase):

    def setUp(self):
        self.container = f"plantoir-preview-claim-{os.getpid()}"
        subprocess.run(["docker", "run", "-d", "--name", self.container, "--entrypoint", "tail",
                        "--mount", f"type=bind,src={SCRIPTS},dst=/opt/test-scripts,readonly",
                        REAL_IMAGE, "-f", "/dev/null"], check=True, capture_output=True, timeout=120)

    def tearDown(self):
        subprocess.run(["docker", "rm", "-f", self.container], capture_output=True, timeout=60)

    def inside(self, script: str, *arguments) -> subprocess.CompletedProcess:
        return subprocess.run(["docker", "exec", self.container, "sh", "-c", script, "sh"] + list(arguments),
                              capture_output=True, timeout=120)

    def test_a_left_claim_whose_id_came_back_does_not_refuse(self):
        claim = ("cd /opt/test-scripts && exec python3 -B -c 'import sys, os, time; import build_site; "
                 "build_site.claim_the_preview_address(8082, \"ICS3U\", 2); print(os.getpid(), flush=True); "
                 "time.sleep(600)'")
        first = subprocess.Popen(["docker", "exec", self.container, "sh", "-c", claim],
                                 stdout=subprocess.PIPE)
        pid = int(first.stdout.readline().decode("utf-8").strip())
        self.inside("kill -9 \"$1\"", str(pid))
        first.wait(timeout=60)
        subprocess.run(["docker", "restart", "-t", "0", self.container], check=True, capture_output=True,
                       timeout=120)
        # Start unrelated programs until the claim's process id is alive again,
        # as it is after a restart (the review: pid 19, three of three).
        # The look is by what the process IS ("sleep 600"), because the
        # process doing the looking can itself be handed that id.
        alive = False
        for _ in range(60):
            subprocess.run(["docker", "exec", "-d", self.container, "sleep", "600"], capture_output=True,
                           timeout=60)
            looked = self.inside("tr '\\0' ' ' < /proc/$1/cmdline 2>/dev/null", str(pid)).stdout
            if looked.strip() == b"sleep 600":
                alive = True
                break
        if not alive:
            self.skipTest(f"the builder did not hand out process id {pid} again")
        left = self.inside("cat /tmp/plantoir-preview-address-8082.claim")
        self.assertIn(b"ICS3U", left.stdout, "the claim outlived the restart")
        asked = self.inside("cd /opt/test-scripts && python3 -B -c 'import build_site; "
                            "build_site.refuse_when_the_preview_address_is_another_previews(8082, \"MPM2D\", 2); "
                            "print(\"WENT AHEAD\")'")
        said = asked.stdout.decode("utf-8")
        self.assertEqual(asked.returncode, 0, said + asked.stderr.decode("utf-8"))
        self.assertIn("WENT AHEAD", said)


class TheServingRunClaimsFirst(unittest.TestCase):
    """Read as text, so it runs everywhere."""

    def test_a_serving_run_claims_before_it_builds(self):
        text = (SCRIPTS / "build_site.py").read_text(encoding="utf-8")
        start = text.index("def build_section_site(")
        claim = text.index("refuse_when_the_preview_address_is_another_previews(port,", start)
        first_copy = text.index("toolchain_paths.COURSES_DIR", start)
        self.assertLess(claim, first_copy, "the claim comes before anything is read or built")
        self.assertIn("if not build_only and os.name != \"nt\":", text[start:claim])

    def test_preview_sh_writes_the_trail_line_for_75(self):
        text = (SCRIPTS.parent / "preview.sh").read_text(encoding="utf-8")
        rules = json.loads((SCRIPTS.parent / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
        entry = None
        for candidate in rules["activityTrail"]["mustRecord"]:
            if candidate["event"] == "build declined, course busy elsewhere":
                entry = candidate
        line = entry["launcherLineWhenItsAddressIsAnotherPreviews"].replace("{course}", "${COURSE}").replace(
            "{section}", "${SECTION}")
        self.assertIn(f'note_on_the_trail "{line}"', text)
        self.assertIn('if [[ "${_build_rc:-0}" -eq ' + str(the_rule()["exitCode"]) + " ]]; then", text)

    def test_preview_sh_writes_the_trail_line_for_a_left_claim(self):
        text = (SCRIPTS.parent / "preview.sh").read_text(encoding="utf-8")
        rules = json.loads((SCRIPTS.parent / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
        entry = None
        for candidate in rules["activityTrail"]["mustRecord"]:
            if candidate["event"] == "preview address held by another account":
                entry = candidate
        line = entry["launcherLineWhenALeftClaimIsTakenOver"].replace("{course}", "${COURSE}").replace(
            "{section}", "${SECTION}").replace("{other}", "${_left_claim}")
        self.assertIn(f'note_on_the_trail "{line}"', text)
        self.assertIn("build_site.a_claim_that_proves_nothing(", text)

    def test_the_sentences_name_no_machinery(self):
        for line in the_rule()["sentences"]["launcher"]:
            for word in ("port", "process", "container", "Docker", "script", "workspace"):
                self.assertNotIn(word, line)


if __name__ == "__main__":
    unittest.main()
