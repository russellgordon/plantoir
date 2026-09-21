#!/usr/bin/env python3
"""
A course kept for reference is NEVER deployed — every door the shared
toolchain owns.

Three layers, and the middle one is the reason this file RUNS things rather
than reading them:

  * `reference_course` itself: what the marker means, what the school year
    means, and that the sentence it says is the contract's sentence.
  * **`deploy.sh`, started for real.** Its `--to-folder` branch publishes with
    `rsync` on the HOST and exits 0 before the container is ever started, so
    `deploy.py`'s own refusal never runs on that path. A guard written only in
    the shared Python leaves that door wide open — the same shape as the
    live-reload defect of 2026-09-05 — so the refusal has to be in the
    launcher, and a test that only read the launcher could not tell whether it
    fires BEFORE the publish.
  * `deploy.py`, whose refusal comes before it looks for a built site.

**No Docker, no network, no credentials, nothing of the teacher's.** The
launcher runs from a COPY in a scratch folder, because `deploy.sh`'s second
line is `cd "$(dirname "$0")"`.

Pure stdlib. Run with:

    python3 scripts/test_reference_course.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import contracts  # noqa: E402
import reference_course  # noqa: E402

# `build_site` imports several siblings by bare name; the path insert above is
# what makes that work outside the container.
import build_site  # noqa: E402


def _rules() -> dict:
    return contracts.section("shared-rules", "referenceCourses")


def _a_working_folder(tmp: str, folder_name: str, values: dict, section: int = 1) -> Path:
    """A scratch folder with one course in it and a built site to publish."""
    folder = Path(tmp)
    shutil.copy2(REPOSITORY_ROOT / "deploy.sh", folder / "deploy.sh")
    course = folder / "courses" / folder_name
    course.mkdir(parents=True)
    (course / "course_config.json").write_text(json.dumps(values, indent=2), encoding="utf-8")
    built = course / ".merged_output" / f"section{section}" / "public"
    built.mkdir(parents=True)
    (built / "index.html").write_text("<html>a built site</html>", encoding="utf-8")
    return folder


def _run_launcher(folder: Path, arguments: list):
    """The copied launcher, with HOME pointed at the scratch folder.

    HOME matters: `deploy.sh` keeps built websites in
    `$HOME/Library/Application Support/Plantoir/builds/<id>` and MIGRATES a
    course's `.merged_output` there the first time it sees one. Left alone,
    the control test below — the one that must get PAST the refusal — writes a
    builds folder into the real Application Support of whoever runs the suite.
    Found the honest way: it did exactly that once, and the folder had to be
    deleted by hand.
    """
    environment = dict(os.environ)
    environment["HOME"] = str(folder / "home")
    (folder / "home").mkdir(exist_ok=True)
    return subprocess.run(
        ["bash", "./deploy.sh"] + arguments,
        cwd=str(folder), capture_output=True, timeout=180, env=environment,
    )


def _bash_can_reach_a_scratch_folder() -> bool:
    """The same question `test_deploy_sh_questions.py` asks, for the same
    reason: a Windows machine with WSL has a `bash` on PATH that cannot open a
    Windows temporary path at all, and these tests would FAIL there rather
    than skip — inside `dotnet test`, which is a gate on that side."""
    if shutil.which("bash") is None:
        return False
    try:
        with tempfile.TemporaryDirectory() as tmp:
            probe = subprocess.run(
                ["bash", "-c", 'cd "$1" && printf reachable', "_", str(tmp)],
                capture_output=True, timeout=60,
            )
            return probe.stdout.decode("utf-8", "replace").strip() == "reachable"
    except (OSError, subprocess.SubprocessError):
        return False


HAS_BASH = _bash_can_reach_a_scratch_folder()

REFERENCE = {
    "course_code": "ICS3U",
    "course_name": "Introduction to Computer Science",
    "section_numbers": [1],
    "num_sections": 1,
    "kept_for_reference": True,
    "reference_school_year": 2025,
    "deploy_target": "local_folder",
    "deploy_folder_path": "",
}

ORDINARY = {
    "course_code": "ICS4U",
    "course_name": "Computer Science",
    "section_numbers": [1],
    "num_sections": 1,
}


class TheMarker(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def _course(self, values, name="ICS3U-2025"):
        course = Path(self.tmp) / name
        course.mkdir(parents=True, exist_ok=True)
        if values is not None:
            (course / "course_config.json").write_text(
                values if isinstance(values, str) else json.dumps(values), encoding="utf-8"
            )
        return course

    def test_the_marker_key_is_the_contracts_key(self):
        rules = _rules()
        self.assertEqual(rules["markerKey"], reference_course.MARKER_KEY)
        self.assertEqual(rules["schoolYearKey"], reference_course.SCHOOL_YEAR_KEY)
        self.assertTrue(rules["absentMeansFalse"])

    def test_true_means_kept_for_reference(self):
        self.assertTrue(reference_course.is_reference(self._course(REFERENCE)))

    def test_absent_and_false_mean_an_ordinary_course(self):
        self.assertFalse(reference_course.is_reference(self._course(ORDINARY, "ICS4U")))
        self.assertFalse(reference_course.is_reference(
            self._course({"course_code": "ICS4U", "kept_for_reference": False}, "ICS4U-2")
        ))

    def test_a_config_that_cannot_be_read_is_an_ordinary_course(self):
        # The one place this errs toward ALLOWING, deliberately: a course
        # nobody can open must not become undeployable by accident. Safe
        # because the marker is not the only defence — the course is also left
        # with nowhere to deploy to — and because the LAUNCHER's own check,
        # which runs first, fails closed instead.
        self.assertFalse(reference_course.is_reference(self._course("{not json", "BROKEN")))
        self.assertFalse(reference_course.is_reference(self._course(None, "NOCONFIG")))
        self.assertFalse(reference_course.is_reference(Path(self.tmp) / "not-there-at-all"))

    def test_the_school_year_is_the_stored_integer(self):
        self.assertEqual(reference_course.school_year(self._course(REFERENCE)), 2025)
        self.assertIsNone(reference_course.school_year(self._course(ORDINARY, "ICS4U")))
        for odd in ["last year", True, 2025.5, None]:
            values = dict(REFERENCE)
            values["reference_school_year"] = odd
            self.assertIsNone(
                reference_course.school_year(self._course(values, "ODD")),
                "%r is not a school year" % (odd,)
            )

    def test_the_code_a_teacher_reads_is_the_recorded_one(self):
        # The folder and course_code disagree on purpose for a reference
        # course, and the sentence has to name the one a teacher recognises.
        self.assertEqual(reference_course.display_code(self._course(REFERENCE)), "ICS3U")
        self.assertEqual(
            reference_course.display_code(self._course({"course_name": "x"}, "ADA1O-REF")),
            "ADA1O-REF"
        )


@unittest.skipUnless(HAS_BASH, "needs a bash that can reach a scratch folder")
class ThreeReadersAgree(unittest.TestCase):
    """`referenceCourses.markerAgreement`, run against all three readers.

    The shell reader is the REAL `deploy.sh`, started against a scratch folder
    — not the guard copied out of it, because what is being pinned is that the
    refusal fires before anything is published, and only running the launcher
    can show that.

    PowerShell cannot be run here (there is no `pwsh` on the mac), so its half
    is checked two ways: the file must carry the contract's `dotNet` pattern
    verbatim, and each row is evaluated against that pattern with Python's
    `re`, case-insensitively. That is a SIMULATION and is labelled one — it
    relies on two .NET semantics stated in the contract: backslash-s matches a
    newline, and PowerShell's `-match` is case-insensitive by default. If
    either is ever wrong, the row that catches it is "the value in capitals".
    """

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def _folder(self, row) -> Path:
        folder = _a_working_folder(self.tmp, "AGREE", {}, )
        config = folder / "courses" / "AGREE" / "course_config.json"
        if row.get("noConfigFile"):
            config.unlink()
            return folder
        if row.get("configIsADirectory"):
            config.unlink()
            config.mkdir()
            return folder
        text = row.get("configText", "")
        data = text.encode("utf-8")
        if row.get("bom"):
            data = b"\xef\xbb\xbf" + data
        config.write_bytes(data)
        if row.get("unreadable"):
            config.chmod(0o000)
        return folder

    def test_every_row_gets_the_same_answer_from_all_three(self):
        agreement = _rules()["markerAgreement"]
        rows = agreement["cases"]
        self.assertGreaterEqual(len(rows), 17, "The agreement table has lost rows.")
        self.assertEqual(agreement["pattern"]["python"], reference_course.MARKER_PATTERN)

        launcher_source = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        self.assertIn(agreement["pattern"]["posixEre"], launcher_source)
        self.assertIn(agreement["pattern"]["escapedKeyPosixEre"], launcher_source)
        powershell_source = (REPOSITORY_ROOT / "deploy.ps1").read_text(encoding="utf-8")
        self.assertIn(agreement["pattern"]["dotNet"], powershell_source)
        self.assertIn(agreement["pattern"]["escapedKeyDotNet"], powershell_source)
        self.assertEqual(
            agreement["pattern"]["escapedKeyPython"], reference_course.ESCAPED_KEY_PATTERN
        )
        # Case-SENSITIVE, matching `-cmatch`: `-match` treated the KEY as
        # case-insensitive too, so "KEPT_FOR_REFERENCE" refused on Windows
        # while the mac and the Python allowed it.
        dot_net = re.compile(agreement["pattern"]["dotNet"])
        present = re.compile(agreement["pattern"]["presentDotNet"])
        says_false = re.compile(agreement["pattern"]["falseDotNet"])
        escaped_key = re.compile(agreement["pattern"]["escapedKeyDotNet"])

        for row in rows:
            name = row["name"]
            expect = row["expect"]
            self.assertIn(expect, ("refused", "allowed"), name)
            folder = self._folder(row)
            course = folder / "courses" / "AGREE"

            # The INVARIANT, asserted on every row: wherever the APP reads a
            # course as kept for reference, every launcher must refuse. The
            # reverse is allowed — a launcher may refuse what the app calls
            # ordinary, because refusing publishes nothing and freezes
            # nothing. The app's own reading is run from the Swift suite
            # (`ReferenceCourseTests`), which walks these same rows.
            if row.get("appReadsAsReference"):
                self.assertEqual(
                    expect, "refused",
                    "%s: the app would FREEZE AND LOCK this course and a launcher would "
                    "deploy it" % name
                )

            if row.get("unreadable") and os.access(str(course / "course_config.json"), os.R_OK):
                self.skipTest("this account can read a file with no permissions (root?)")

            # 1. The shared Python, which is also what deploy.py asks.
            python_says = (
                reference_course.is_reference(course) or reference_course.cannot_tell(course)
            )
            self.assertEqual(
                python_says, expect == "refused",
                "%s: the shared Python disagrees with the contract" % name
            )

            # 2. The real launcher, publishing to a folder — the one door the
            #    shared Python never reaches.
            destination = Path(self.tmp) / ("out-" + name.replace(" ", "-"))
            destination.mkdir()
            result = _run_launcher(folder, [
                "AGREE", "1", "--to-folder", str(destination), "--image", "no-such-image",
            ])
            said = (result.stdout + result.stderr).decode("utf-8", "replace")
            refused = "is kept for reference, so it is never deployed" in said \
                or "cannot tell whether" in said.lower()
            self.assertEqual(
                refused, expect == "refused",
                "%s: deploy.sh disagrees with the contract. It said: %s" % (name, said)
            )
            if expect == "refused":
                self.assertEqual(result.returncode, 1, "%s: %s" % (name, said))
                self.assertEqual(
                    list(destination.iterdir()), [],
                    "%s: A REFERENCE COURSE WAS PUBLISHED" % name
                )

            # 3. PowerShell's pattern, simulated. Unreadable and missing files
            #    are about reading rather than matching, so they are not
            #    questions the pattern answers.
            if not row.get("unreadable") and not row.get("noConfigFile") \
                    and not row.get("configIsADirectory"):
                text = row.get("configText", "")
                powershell_refuses = escaped_key.search(text) is not None \
                    or dot_net.search(text) is not None or (
                    present.search(text) is not None
                    and dot_net.search(text) is None
                    and says_false.search(text) is None
                )
                self.assertEqual(
                    powershell_refuses, expect == "refused",
                    "%s: deploy.ps1's patterns disagree" % name
                )
            # The mode goes back before the folder goes, or the row that
            # makes a file unreadable leaves one behind.
            try:
                (course / "course_config.json").chmod(0o644)
            except OSError:
                pass
            shutil.rmtree(folder / "courses" / "AGREE", ignore_errors=True)


class TheSentence(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_the_sentence_is_the_contracts_sentence(self):
        template = _rules()["refusal"]["sentence"]
        self.assertIn("{course}", template)
        self.assertEqual(
            reference_course.refusal_sentence("ICS3U"),
            template.replace("{course}", "ICS3U"),
        )

    def test_the_fallback_is_the_same_string(self):
        # The fallback exists so a missing contract still REFUSES rather than
        # falling through to a deploy. It is only safe while it says the same
        # thing, which is what this pins.
        self.assertEqual(reference_course.FALLBACK_REFUSAL, _rules()["refusal"]["sentence"])

    def test_both_launchers_carry_the_same_cannot_tell_sentence(self):
        # The same arrangement the refusal sentence has: a keyed string,
        # carried as a constant in each launcher, compared here. It exists
        # because the app reads a course with an odd marker value as ORDINARY
        # — so a teacher can schedule a deploy on it, and only the launcher
        # refuses, with the app closed.
        wording = _rules()["wording"]
        # The two halves the launcher prints around the course's name.
        headline_start = wording["cannotTellHeadline"].split("{course}")[0].strip()
        headline_end = wording["cannotTellHeadline"].split("{course}")[1].strip()
        for launcher in ["deploy.sh", "deploy.ps1"]:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            self.assertIn(headline_start, text, launcher)
            self.assertIn(headline_end, text, launcher)
            self.assertIn(wording["cannotTellBecauseOddValue"], text, launcher)
            self.assertIn(wording["cannotTellBecauseUnreadable"], text, launcher)

    def test_the_python_says_which_reason(self):
        # deploy.py printed "its settings file could not be read" for every
        # cause, including a file that opened perfectly well and said `1`.
        wording = _rules()["wording"]
        folder = Path(self.tmp) / "WHY"
        folder.mkdir()
        (folder / "course_config.json").write_text(
            '{"course_code": "WHY", "kept_for_reference": 1}', encoding="utf-8"
        )
        self.assertEqual(
            reference_course.why_cannot_tell(folder), wording["cannotTellBecauseOddValue"]
        )
        (folder / "course_config.json").chmod(0o000)
        self.addCleanup((folder / "course_config.json").chmod, 0o644)
        if not os.access(str(folder / "course_config.json"), os.R_OK):
            self.assertEqual(
                reference_course.why_cannot_tell(folder),
                wording["cannotTellBecauseUnreadable"]
            )

    def test_both_launchers_carry_the_same_sentence(self):
        # The launchers cannot read the contract: the host-side check runs
        # before the build recipe is resolved, and under --image it is never
        # resolved at all. So each carries a constant, and this is what stops
        # the three copies drifting into three different explanations of one
        # rule.
        tail = _rules()["refusal"]["sentence"].replace("{course} ", "")
        for launcher in ["deploy.sh", "deploy.ps1"]:
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            self.assertIn("REFERENCE_COURSE_REFUSAL", text, launcher)
            self.assertIn(tail, text, launcher)

    def test_no_machinery_in_the_sentence(self):
        sentence = _rules()["refusal"]["sentence"].lower()
        for word in ["flag", "immutable", "container", "script", "toolchain", "docker"]:
            self.assertNotIn(word, sentence)


@unittest.skipUnless(HAS_BASH, "needs a bash that can reach a scratch folder")
class TheLauncherRefusesBeforePublishing(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_a_reference_course_is_refused_and_nothing_is_published(self):
        folder = _a_working_folder(self.tmp, "ICS3U-2025", REFERENCE)
        result = _run_launcher(folder, ["ICS3U-2025", "1", "--image", "no-such-image"])
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertEqual(result.returncode, 1, said)
        self.assertIn("ICS3U is kept for reference", said)
        # And the code a TEACHER reads, not the folder name.
        self.assertNotIn("ICS3U-2025 is kept for reference", said)

    def test_the_folder_destination_is_refused_too(self):
        # THE DOOR THAT NEEDS THE LAUNCHER. This branch publishes with rsync on
        # the host and exits 0 before the container starts, so deploy.py's
        # refusal never runs on it. If the guard moves later in the file this
        # test goes red — and the destination folder is checked EMPTY, so a
        # refusal that fired after the copy would fail here too.
        folder = _a_working_folder(self.tmp, "ICS3U-2025", REFERENCE)
        destination = Path(self.tmp) / "somewhere"
        destination.mkdir()
        result = _run_launcher(folder, [
            "ICS3U-2025", "1", "--to-folder", str(destination), "--image", "no-such-image",
        ])
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertEqual(result.returncode, 1, said)
        self.assertIn("is kept for reference", said)
        self.assertEqual(list(destination.iterdir()), [], "nothing may reach the folder")
        self.assertNotIn("Moving", said, "the refusal comes before the build output is even linked")

    def test_an_ordinary_course_gets_past_the_check(self):
        # The control. Without it a check that refused EVERYTHING would pass
        # every other test in this class.
        folder = _a_working_folder(self.tmp, "ICS4U", ORDINARY)
        destination = Path(self.tmp) / "somewhere"
        destination.mkdir()
        result = _run_launcher(folder, [
            "ICS4U", "1", "--to-folder", str(destination), "--image", "no-such-image",
        ])
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertNotIn("kept for reference", said)
        self.assertEqual(result.returncode, 0, said)
        self.assertTrue((destination / "section1" / "index.html").exists(), said)

    def test_a_marker_with_no_course_code_still_says_the_sentence(self):
        # Not "still exits 1": it did that already, SILENTLY. `grep -Eo`
        # exits 1 when there is no course_code, `pipefail` propagates it and
        # `set -e` killed the script on that assignment before the echo. The
        # whole design of "no fourth exit code, matched on OUTPUT" rests on
        # the sentence being printed — with no output a scheduled deploy falls
        # back to the generic "did not finish", which is the log-nobody-opens
        # failure this was written to close.
        folder = _a_working_folder(self.tmp, "NOCODE", {"kept_for_reference": True})
        result = _run_launcher(folder, ["NOCODE", "1", "--image", "no-such-image"])
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertEqual(result.returncode, 1, said)
        self.assertIn("is kept for reference, so it is never deployed", said)
        # With no recorded code, the folder name is the only honest name.
        self.assertIn("NOCODE", said)

    def test_a_settings_file_that_cannot_be_read_refuses(self):
        # FAIL CLOSED. "Cannot tell" is not "no".
        folder = _a_working_folder(self.tmp, "ICS3U-2025", REFERENCE)
        config = folder / "courses" / "ICS3U-2025" / "course_config.json"
        config.chmod(0o000)
        self.addCleanup(config.chmod, 0o644)
        if os.access(str(config), os.R_OK):
            self.skipTest("this account can read a file with no permissions (root?)")
        result = _run_launcher(folder, ["ICS3U-2025", "1", "--image", "no-such-image"])
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertEqual(result.returncode, 1, said)
        self.assertIn("cannot tell whether", said.lower(), said)


class DeployPyRefusesFirst(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def _run_deploy_py(self, folder_name: str, values: dict, with_a_built_site: bool):
        courses = Path(self.tmp) / "courses"
        course = courses / folder_name
        course.mkdir(parents=True)
        (course / "course_config.json").write_text(json.dumps(values), encoding="utf-8")
        if with_a_built_site:
            built = course / ".merged_output" / "section1" / "public"
            built.mkdir(parents=True)
            (built / "index.html").write_text("<html>built</html>", encoding="utf-8")
        environment = dict(os.environ)
        environment["PLANTOIR_COURSES_DIR"] = str(courses)
        environment["PLANTOIR_CONTRACTS_DIR"] = str(REPOSITORY_ROOT / "contracts")
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        return subprocess.run(
            [sys.executable, str(REPOSITORY_ROOT / "scripts" / "deploy.py"),
             "--course", folder_name, "--section", "1", "--non-interactive"],
            capture_output=True, timeout=180, env=environment,
        )

    def test_it_refuses_before_looking_for_a_built_site(self):
        # Before, deliberately: a reference course that has never been built
        # would otherwise be told to "run the preview first", which is advice
        # that leads nowhere at all.
        result = self._run_deploy_py("ICS3U-2025", REFERENCE, with_a_built_site=False)
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertEqual(result.returncode, 1, said)
        self.assertIn("ICS3U is kept for reference", said)
        self.assertNotIn("Section directory not found", said)

    def test_an_ordinary_course_gets_past_it(self):
        result = self._run_deploy_py("ICS4U", ORDINARY, with_a_built_site=False)
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertNotIn("kept for reference", said)
        self.assertIn("Section directory not found", said)


class TheBuiltSiteShowsTheRealCode(unittest.TestCase):
    """The title of a reference course's PREVIEW.

    Measured on a real imported course before this: the header read
    "ICS4U-2025 S1". The plan claimed `build_site.py` put `course_code` there
    and it did not — it passed the launcher's argument, which is the folder.
    Decision (h): a teacher reads ICS4U.
    """

    def test_a_reference_course_is_titled_with_its_real_code(self):
        config = {"course_code": "ICS4U", "kept_for_reference": True}
        self.assertEqual(build_site.displayed_course_code(config, "ICS4U-2025"), "ICS4U")

    def test_an_ordinary_course_is_titled_with_the_folder_exactly_as_before(self):
        # The folder is what every path in the build uses, and for an
        # ordinary course the two agree anyway. If they ever did NOT — a
        # hand-edited config — the folder wins, because that is what the rest
        # of the build is working from.
        config = {"course_code": "ICS3U"}
        self.assertEqual(build_site.displayed_course_code(config, "ICS3U"), "ICS3U")
        self.assertEqual(build_site.displayed_course_code({"course_code": "MCV4U"}, "ICS3U"), "ICS3U")

    def test_no_recorded_code_falls_back_to_the_folder(self):
        self.assertEqual(build_site.displayed_course_code({}, "ADA1O-REF"), "ADA1O-REF")
        self.assertEqual(
            build_site.displayed_course_code({"kept_for_reference": True}, "ADA1O-REF"),
            "ADA1O-REF"
        )

    def test_the_header_label_and_the_grade_label_follow_it(self):
        # The grade label reads the FOURTH character, so a suffix that shifts
        # that position gives a wrong grade. ICS4U-2025 survives by luck;
        # MADW-09-2025 does not.
        config = {"course_code": "MADW-09", "kept_for_reference": True}
        code = build_site.displayed_course_code(config, "MADW-09-2025")
        self.assertEqual(code, "MADW-09")
        self.assertEqual(
            build_site.resolve_header_label(config, code),
            build_site.resolve_header_label(config, "MADW-09")
        )


class TheImageCarriesTheModule(unittest.TestCase):

    def test_the_dockerfile_bakes_it(self):
        # deploy.py imports it by bare name, which only resolves if it is baked
        # in beside it. `test_baked_modules.py` catches the general case; this
        # says so in the file that would notice first.
        dockerfile = (REPOSITORY_ROOT / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn("COPY scripts/reference_course.py", dockerfile)


if __name__ == "__main__":
    unittest.main(verbosity=2)
