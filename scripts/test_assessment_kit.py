#!/usr/bin/env python3
"""
The marking kit format (#751) and the `plantoir-test-authoring` skill's
templates.

The kit is what that skill writes and what `plantoir-marking` (#750) reads,
so its format is a contract: `contracts/shared-rules.json` -> `assessment`
-> `kitFormat`. Every case there is applied to its base kit (or base marks
record), written to a temporary file and run through the skill's own
`scripts/check_kit.py`, the way an assistant runs it: a refused case must
exit 1 naming its rule in square brackets, an accepted one exit 0.

The skill's worked example must pass that checker too, its marks template
must hold exactly the example's points, its example checks script must say
OK and must fail, naming the question, when an answer is changed, and every
file `assessment.agentGuidance.testAuthoringSkill.templates` lists must be
there. Its Marking Guide must name every point of the example kit and carry
the sentence that says the teacher decides, and no example file may carry a
firearms or ammunition context.

Stdlib only. Windows' PythonToolchainTests discovers this file; the
scripts are run with the interpreter running this test.
"""
import copy
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SKILLS = REPOSITORY / "support" / "agent_guidance" / "skills"
SKILL = SKILLS / "plantoir-test-authoring"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
KIT_FOLDER = SKILL / "templates" / "Marking Kit"
# Words an invented example must never use (the rule: contexts you invent
# never involve firearms or ammunition).
FIREARMS_WORDS = re.compile(
    r"\b(firearms?|guns?|handguns?|shotguns?|rifles?|pistols?|revolvers?|ammunition|ammo|reload\w*|gunpowder)\b",
    re.IGNORECASE,
)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def assessment():
    return read_json(SHARED_RULES)["assessment"]


def run_checker(*arguments):
    checker = SKILL / assessment()["agentGuidance"]["testAuthoringSkill"]["kitChecker"]
    return subprocess.run(
        [sys.executable, "-B", str(checker), *[str(argument) for argument in arguments]],
        capture_output=True, text=True, encoding="utf-8",
    )


def apply_case(document, case):
    """A copy of the document with the case's `remove` and `set` applied."""
    changed = copy.deepcopy(document)
    for path in case.get("remove", []):
        container = changed
        for step in path[:-1]:
            container = container[step]
        del container[path[-1]]
    for change in case.get("set", []):
        path = change["path"]
        container = changed
        for step in path[:-1]:
            container = container[step]
        last = path[-1]
        if isinstance(container, list) and last == len(container):
            container.append(change["value"])
        else:
            container[last] = change["value"]
    return changed


class KitFormatCases(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-kit-"))

    def tearDown(self):
        shutil.rmtree(self.folder)

    def test_every_case_is_accepted_or_refused_as_the_contract_says(self):
        rules = assessment()["kitFormat"]
        cases = rules["cases"]
        self.assertGreaterEqual(len(cases), 20, "the contract lost kit cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                kit_path = self.folder / "answers.json"
                if case["file"] == "kit":
                    kit_path.write_text(json.dumps(apply_case(rules["base"], case)), encoding="utf-8")
                    result = run_checker(kit_path)
                else:
                    kit_path.write_text(json.dumps(rules["base"]), encoding="utf-8")
                    marks_path = self.folder / "marks.json"
                    marks_path.write_text(json.dumps(apply_case(rules["baseMarks"], case)), encoding="utf-8")
                    result = run_checker(kit_path, "--marks", marks_path)
                output = result.stdout + result.stderr
                if case["expect"] == "accepted":
                    self.assertEqual(result.returncode, 0, output)
                    self.assertTrue(result.stdout.startswith("OK"), output)
                else:
                    self.assertEqual(result.returncode, 1, output)
                    self.assertIn("[" + case["rule"] + "]", output)

    def test_the_forbidden_keys_are_the_checkers(self):
        source = (SKILL / "scripts" / "check_kit.py").read_text(encoding="utf-8")
        listed = re.search(r"FORBIDDEN_KEYS = (\[.*?\])", source).group(1)
        self.assertEqual(json.loads(listed), assessment()["kitFormat"]["forbiddenKeys"])

    def test_the_checker_prints_no_value_from_a_marks_record(self):
        rules = assessment()["kitFormat"]
        marks = copy.deepcopy(rules["baseMarks"])
        marks["points"]["A1"]["seen"] = "Testpupil Invented wrote this"
        marks["points"]["A1"]["earned"] = 3
        kit_path = self.folder / "answers.json"
        kit_path.write_text(json.dumps(rules["base"]), encoding="utf-8")
        marks_path = self.folder / "marks.json"
        marks_path.write_text(json.dumps(marks), encoding="utf-8")
        result = run_checker(kit_path, "--marks", marks_path)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Testpupil", result.stdout + result.stderr)


class TheSkillsTemplates(unittest.TestCase):
    def test_every_listed_template_is_there(self):
        listed = assessment()["agentGuidance"]["testAuthoringSkill"]["templates"]
        self.assertIn("templates/Marking Kit/answers.json", listed)
        for relative in listed:
            self.assertTrue((SKILL / relative).is_file(), relative)

    def test_the_worked_example_passes_the_checker_with_its_marks_template(self):
        result = run_checker(KIT_FOLDER / "answers.json", "--marks", KIT_FOLDER / "marks-template.json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_the_marks_template_holds_exactly_the_examples_points_unmarked(self):
        kit = read_json(KIT_FOLDER / "answers.json")
        template = read_json(KIT_FOLDER / "marks-template.json")
        point_ids = [point["id"] for point in kit["points"]]
        self.assertEqual(list(template["points"].keys()), point_ids)
        for point_id in point_ids:
            self.assertIsNone(template["points"][point_id]["earned"], point_id)
        self.assertIsNone(template["identifier"])

    def test_the_examples_versions_put_right_answers_under_different_letters(self):
        kit = read_json(KIT_FOLDER / "answers.json")
        self.assertGreaterEqual(len(kit["versions"]), 2)
        for point in kit["points"]:
            letters = []
            for key in kit["versions"]:
                entry = kit["versions"][key]["answers"][point["id"]]
                if entry.get("misconceptions"):
                    letters.append(entry["answer"])
            self.assertEqual(len(letters), len(set(letters)), point["id"])

    def test_the_example_checks_say_ok_and_fail_on_a_changed_answer(self):
        with tempfile.TemporaryDirectory(prefix="plantoir-checks-") as scratch:
            copied = Path(scratch) / "Unit 2 Test"
            shutil.copytree(SKILL / "templates", copied)
            script = copied / "Checks" / "check_answers.py"
            passing = subprocess.run([sys.executable, "-B", str(script)], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(passing.returncode, 0, passing.stdout + passing.stderr)
            kit_path = copied / "Marking Kit" / "answers.json"
            kit = read_json(kit_path)
            kit["versions"]["B"]["answers"]["B2.1"]["answer"] = "2.37 g"
            kit_path.write_text(json.dumps(kit), encoding="utf-8")
            failing = subprocess.run([sys.executable, "-B", str(script)], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(failing.returncode, 1)
            self.assertIn("Version B, B2.1", failing.stdout)

    def test_the_marking_guide_names_every_point_and_says_the_teacher_decides(self):
        guide = (SKILL / "templates" / "Marking Guide.tex").read_text(encoding="utf-8")
        kit = read_json(KIT_FOLDER / "answers.json")
        for point in kit["points"]:
            self.assertIn("\\pid{" + point["id"] + "}", guide, point["id"])
        folded = re.sub(r"\s+", " ", guide)
        self.assertIn("Please read and decide on all of it before it reaches a student; I draft, you decide.", folded)

    def test_no_example_carries_a_firearms_context(self):
        for path in sorted((SKILL / "templates").rglob("*")):
            if path.is_file():
                found = FIREARMS_WORDS.findall(path.read_text(encoding="utf-8"))
                self.assertEqual(found, [], str(path.relative_to(SKILL)))
        base = json.dumps(assessment()["kitFormat"])
        self.assertEqual(FIREARMS_WORDS.findall(base), [])

    def test_the_skill_is_named_as_its_folder_with_a_short_enough_description(self):
        text = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("\nname: plantoir-test-authoring\n", text)
        description = re.search(r"^description: (.*)$", text, re.MULTILINE).group(1)
        self.assertLessEqual(len(description), 1024)

    def test_the_offered_templates_name_is_the_handouts_skills(self):
        name = read_json(SHARED_RULES)["printablePages"]["agentGuidance"]["handoutsSkill"]["offeredTemplate"]["name"]
        folded = re.sub(r"\s+", " ", (SKILL / "SKILL.md").read_text(encoding="utf-8"))
        self.assertIn('"' + name + '"', folded)


if __name__ == "__main__":
    unittest.main()
