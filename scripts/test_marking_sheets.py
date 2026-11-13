#!/usr/bin/env python3
"""
The plantoir-marking skill's test sheet (#750, piece 750a): scripts/build_test_sheet.py, and the skill's
files.

The sheet builder is run against the plantoir-test-authoring skill's worked example kit (#751) and an
invented marks record (scripts/fixtures/marking/example-marks.json): the student's sheet has its sections
in the default order with the marks last, every lost mark's reason on it, a link only to a page that was
checked, no total, and the identifier on its one \\studentline; the teacher's sheet carries the sentence
that says the teacher decides. It refuses a lost mark with no reason, a half mark the settings did not
say yes to (and accepts one they did), and every refused kit and marks case of
assessment.kitFormat, naming check_kit.py's rule. It leaves only the sheets' .tex and .pdf behind.

The skill itself: every file assessment.agentGuidance.markingSkill lists is there; every script but the
runner has both MARK blocks and a --self-test, and the runner only the second; the name and description;
the offered template's name; no firearms or ammunition context in any file the skill ships.

The sheet cases need tectonic and pdftotext and skip, saying so, without them. Stdlib only otherwise.
Windows' PythonToolchainTests discovers this file.
"""
import copy
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SKILLS = REPOSITORY / "support" / "agent_guidance" / "skills"
SKILL = SKILLS / "plantoir-marking"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
BUILDER = SKILL / "scripts" / "build_test_sheet.py"
CHECKER = SKILLS / "plantoir-test-authoring" / "scripts" / "check_kit.py"
EXAMPLE_KIT = SKILLS / "plantoir-test-authoring" / "templates" / "Marking Kit" / "answers.json"
EXAMPLE_MARKS = REPOSITORY / "scripts" / "fixtures" / "marking" / "example-marks.json"
MISSING = [tool for tool in ("tectonic", "pdftotext") if shutil.which(tool) is None]
SKIP_REASON = ", ".join(MISSING) + " not found here; the sheet cases compile and read PDFs"
FIREARMS_WORDS = re.compile(
    r"\b(firearms?|guns?|handguns?|shotguns?|rifles?|pistols?|revolvers?|ammunition|ammo|reload\w*|gunpowder)\b",
    re.IGNORECASE,
)


def contract():
    return json.loads(SHARED_RULES.read_text(encoding="utf-8"))


def build(kit, marks, out, *extra):
    root = Path(out).parents[1]
    kit_path = root / "answers.json"
    marks_path = root / "Student A.json"
    kit_path.write_text(json.dumps(kit), encoding="utf-8")
    marks_path.write_text(json.dumps(marks), encoding="utf-8")
    return subprocess.run([sys.executable, "-B", str(BUILDER), "--kit", str(kit_path), "--marks", str(marks_path),
                           "--out", str(out), "--checker", str(CHECKER), *[str(value) for value in extra]],
                          capture_output=True, text=True, encoding="utf-8")


def pdf_text(path):
    text = subprocess.run(["pdftotext", str(path), "-"], capture_output=True).stdout.decode("utf-8", "replace")
    return unicodedata.normalize("NFKC", text)   # the font's ligatures (ﬁ, ﬀ) read as their letters


def apply(base, case):
    """A kitFormat case's remove and set, as test_assessment_kit.py applies them."""
    data = copy.deepcopy(base)
    for path in case.get("remove", []):
        target = data
        for key in path[:-1]:
            target = target[key]
        del target[path[-1]]
    for change in case.get("set", []):
        target = data
        for key in change["path"][:-1]:
            target = target[key]
        last = change["path"][-1]
        if isinstance(target, list) and last == len(target):
            target.append(change["value"])
        else:
            target[last] = change["value"]
    return data


@unittest.skipIf(MISSING, SKIP_REASON)
class SheetTests(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="marking-sheet-"))
        self.kit = json.loads(EXAMPLE_KIT.read_text(encoding="utf-8"))
        self.marks = json.loads(EXAMPLE_MARKS.read_text(encoding="utf-8"))
        self.out = self.folder / "Sheets" / "Section 1"

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_the_sheet_has_its_sections_in_order_with_the_marks_last(self):
        links = self.folder / "checked-links.json"
        links.write_text(json.dumps(["Concepts/Balancing-Equations"]), encoding="utf-8")
        result = build(self.kit, self.marks, self.out, "--school", "School Name", "--site", "https://example.org/snc2d-1",
                       "--links", links)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Student A: K 3/4 T 5/6 C 2/3 A 3/3; checks 1;", result.stdout)
        text = re.sub(r"\s+", " ", pdf_text(self.out / "Student A - Feedback.pdf"))
        order = ["Student A", "Strengths", "Issues by question", "Areas to focus on", "Overall comments", "Your marks"]
        positions = [text.find(heading) for heading in order]
        self.assertNotIn(-1, positions, text)
        self.assertEqual(positions, sorted(positions), "the sections are in the default order, marks last")
        # A lost point's reason is its question's byQuestion notes when the marker wrote them, else its studentNote.
        for point in ("A2", "C1.3"):
            note = self.marks["points"][point]["studentNote"]
            self.assertIn(" ".join(note.split()[:6]), text, f"{point}'s reason is on the sheet")
        self.assertIn("Oxygen was counted as 12 on the right instead of 14", text, "B1.3's reason is on the sheet")
        self.assertIn("Full marks: your own words", text, "a benefit-of-the-doubt row is listed")
        self.assertNotIn("A4 Comparing", text, "a question with full marks and no note is not listed")
        self.assertNotRegex(text, r"\b13/16\b", "no total on the student's sheet")
        feedback_tex = (self.out / "Student A - Feedback.tex").read_text(encoding="utf-8")
        self.assertIn("https://example.org/snc2d-1/Concepts/Balancing-Equations", feedback_tex)
        self.assertNotIn("Concepts/Evidence", feedback_tex, "a page that was not checked is not linked")
        for name in ("Feedback", "Marks by Question"):
            tex = (self.out / f"Student A - {name}.tex").read_text(encoding="utf-8")
            self.assertEqual(len(re.findall(r"\\studentline\{Student A\}", tex)), 1, name)
        teacher = re.sub(r"\s+", " ", pdf_text(self.out / "Student A - Marks by Question.pdf"))
        self.assertIn("I draft; you decide.", teacher)
        self.assertEqual(sorted(path.name for path in self.out.iterdir()),
                         ["Student A - Feedback.pdf", "Student A - Feedback.tex",
                          "Student A - Marks by Question.pdf", "Student A - Marks by Question.tex"])

    def test_a_lost_mark_with_no_reason_is_refused(self):
        self.marks["points"]["B1.3"]["studentNote"] = ""
        result = build(self.kit, self.marks, self.out)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Student A: B1.3 lost a mark and has no studentNote", result.stdout)
        self.assertFalse(self.out.exists() and any(self.out.iterdir()))

    def test_a_half_mark_needs_the_teachers_yes(self):
        self.marks["points"]["B1.3"]["earned"] = 0.5
        refused = build(self.kit, self.marks, self.out)
        self.assertEqual(refused.returncode, 1)
        self.assertIn("has a half mark, and your marking settings do not record a yes to half marks", refused.stdout)
        settings = self.folder / "Marking Settings.md"
        settings.write_text("# Marking Settings\n\n- Half marks: yes (the teacher, 2026-11-12)\n", encoding="utf-8")
        accepted = build(self.kit, self.marks, self.out, "--settings", settings)
        self.assertEqual(accepted.returncode, 0, accepted.stdout)
        self.assertIn("T 5.5/6", accepted.stdout)

    def test_every_refused_kit_and_marks_case_is_refused_by_the_builder(self):
        kit_format = contract()["assessment"]["kitFormat"]
        counted = 0
        for case in kit_format["cases"]:
            if case["expect"] != "refused" or case["file"] not in ("kit", "marks") or "kitSet" in case:
                continue
            kit = apply(kit_format["base"], case) if case["file"] == "kit" else kit_format["base"]
            marks = apply(kit_format["baseMarks"], case) if case["file"] == "marks" else kit_format["baseMarks"]
            with self.subTest(case["name"]):
                result = build(kit, marks, self.out)
                self.assertEqual(result.returncode, 1, case["name"])
                self.assertIn("does not pass check_kit.py", result.stdout, case["name"])
                self.assertIn(case["rule"], result.stdout, case["name"])
                counted += 1
        self.assertGreater(counted, 20)

    def test_its_own_self_test_passes(self):
        result = subprocess.run([sys.executable, "-B", str(BUILDER), "--self-test", "--checker", str(CHECKER)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class SkillFileTests(unittest.TestCase):

    def guidance(self):
        return contract()["assessment"]["agentGuidance"]["markingSkill"]

    def test_every_listed_file_is_there(self):
        guidance = self.guidance()
        for relative in guidance["scripts"] + guidance["templates"] + guidance["references"]:
            self.assertTrue((SKILL / relative).is_file(), relative)
        self.assertIn(guidance["runner"], guidance["scripts"])

    def test_every_script_but_the_runner_is_a_starting_point_with_a_self_test(self):
        privacy = contract()["assessment"]["scriptPrivacy"]
        guidance = self.guidance()
        for relative in guidance["scripts"]:
            source = (SKILL / relative).read_text(encoding="utf-8")
            self.assertIn(privacy["mustNotChangeMark"], source, relative)
            self.assertNotIn("traceback.print", source, relative)
            if relative == guidance["runner"]:
                self.assertNotIn(privacy["mayChangeMark"], source, "the runner is never adapted")
            else:
                self.assertIn(privacy["mayChangeMark"], source, relative)
                self.assertIn(privacy["selfTest"], source, relative)

    def test_the_skill_is_named_as_its_folder_with_a_short_enough_description(self):
        text = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("\nname: plantoir-marking\n", text)
        description = re.search(r"^description: (.*)$", text, re.MULTILINE).group(1)
        self.assertLessEqual(len(description), 1024)
        for relative in self.guidance()["scripts"] + self.guidance()["templates"] + self.guidance()["references"]:
            self.assertIn(relative.split("/", 1)[1], text, f"the skill names {relative}")

    def test_every_marking_pin_is_in_the_skill_once(self):
        # The same walk the mac suite makes over both written homes, here over the source, so a sentence taken
        # out of SKILL.md fails a Python test too.
        pins = contract()["printablePages"]["agentGuidance"]["mustSay"]["plantoir-marking"]
        folded = re.sub(r"\s+", " ", (SKILL / "SKILL.md").read_text(encoding="utf-8"))
        for pin in pins:
            self.assertEqual(folded.count(re.sub(r"\s+", " ", pin)), 1, pin)

    def test_every_brief_runs_the_check_before_reading_a_paper(self):
        # 750a fix review 3, M3: a marker started from a saved brief read a paper with no --verify.
        for name in ("templates/Marker Brief.md", "templates/Reviewer Brief.md"):
            text = (SKILL / name).read_text(encoding="utf-8")
            first = text.index("## First, before reading anything")
            self.assertLess(first, text.index("## Read"), name)
            self.assertIn("redact_scans.py\" --verify", text, name)
            self.assertIn("read nothing and report", text, name)
            self.assertNotIn("blanked", text, name)

    def test_the_skill_names_the_runners_own_sha256(self):
        # 750a review L6: the runner can be edited in place until Plantoir next refreshes the folder, so
        # the skill has the assistant check it first; the hash it gives must be the shipped file's.
        import hashlib
        runner = SKILL / self.guidance()["runner"]
        digest = hashlib.sha256(runner.read_bytes()).hexdigest()
        self.assertIn("It must print `" + digest + "`", (SKILL / "SKILL.md").read_text(encoding="utf-8"))
        # 750a fix review M5: the pin is of LF bytes, and .gitattributes checks this one file out with LF on
        # every platform, so a Windows checkout under core.autocrlf hashes the same.
        self.assertNotIn(b"\r", runner.read_bytes())
        attributes = (REPOSITORY / ".gitattributes").read_text(encoding="utf-8")
        self.assertIn("support/agent_guidance/skills/plantoir-marking/scripts/run_with_names.py text eol=lf", attributes)

    def test_the_offered_templates_name_is_the_handouts_skills(self):
        name = contract()["printablePages"]["agentGuidance"]["handoutsSkill"]["offeredTemplate"]["name"]
        for relative in ("SKILL.md", "reference/template.md"):
            folded = re.sub(r"\s+", " ", (SKILL / relative).read_text(encoding="utf-8"))
            self.assertIn('"' + name + '"', folded, relative)

    def test_no_file_carries_a_firearms_context(self):
        for path in sorted(SKILL.rglob("*")):
            if path.is_file():
                text = path.read_text(encoding="utf-8")
                found = FIREARMS_WORDS.findall(text)
                if path.name == "SKILL.md" or path.name == "Marker Brief.md":
                    # The rule itself names them once: "never involve firearms or ammunition".
                    found = [word for word in found if word.lower() not in ("firearms", "ammunition")]
                self.assertEqual(found, [], str(path.relative_to(SKILL)))
        self.assertEqual(FIREARMS_WORDS.findall(EXAMPLE_MARKS.read_text(encoding="utf-8")), [])


if __name__ == "__main__":
    unittest.main()
