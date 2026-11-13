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
        self.claim_file(8081).write_text(json.dumps({"pid": os.getppid(), "course": "EXC2O", "section": 1}),
                                         encoding="utf-8")
        self.assertIsNone(build_site.claim_the_preview_address(8081, "EXC2O", 1))

    def test_a_claim_whose_build_has_gone_counts_for_nothing(self):
        gone = subprocess.Popen([sys.executable, "-c", "pass"])
        gone.wait()
        self.claim_file(8082).write_text(json.dumps({"pid": gone.pid, "course": "EXC2O", "section": 1}),
                                         encoding="utf-8")
        self.assertIsNone(build_site.claim_the_preview_address(8082, "EXC2O", 2))

    def test_another_course_on_the_address_is_another_preview(self):
        self.claim_file(8083).write_text(json.dumps({"pid": os.getppid(), "course": "ICS3U", "section": 1}),
                                         encoding="utf-8")
        self.assertEqual(build_site.claim_the_preview_address(8083, "EXC2O", 1), "ICS3U section 1")

    def test_an_unreadable_claim_counts_for_nothing(self):
        self.claim_file(8084).write_text("{not json", encoding="utf-8")
        self.assertIsNone(build_site.claim_the_preview_address(8084, "EXC2O", 1))

    def test_a_refused_run_says_the_contracts_words_and_exits_75(self):
        self.claim_file(8081).write_text(json.dumps({"pid": os.getpid(), "course": "EXC2O", "section": 1}),
                                         encoding="utf-8")
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

    def test_the_sentences_name_no_machinery(self):
        for line in the_rule()["sentences"]["launcher"]:
            for word in ("port", "process", "container", "Docker", "script", "workspace"):
                self.assertNotIn(word, line)


if __name__ == "__main__":
    unittest.main()
