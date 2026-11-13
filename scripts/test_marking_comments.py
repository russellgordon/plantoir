#!/usr/bin/env python3
"""
Report card comments (#752): the plantoir-report-comments skill, and make_named_copies.py --comments, the
step that puts the first names into comments the assistant drafted with identifiers only.

Every case in contracts/shared-rules.json -> assessment -> commentNames -> cases is run the way the skill
runs it: an invented mapping table in a teacher-only folder, the drafts in a marking folder, the script as
a subprocess, once directly and once through the never-adapted runner (run_with_names.py). After every
case: the lines the case names are printed; Report Comments.csv holds exactly the rows the case gives
(each comment and its size typed and counted by hand in the contract), or nothing is written; no word of
any name in the table is in what was printed; nothing new is in the marking folder; and the runner
withheld no line and moved nothing.

Also: --longest-first-name and --check-file print numbers, never a name; the script's own --self-test;
and the skill's files (both are written, the scripts it uses are in plantoir-marking, every phrase the
contract pins is in it once, the skill that mentions it names it, both root files name it, the offered
template is named as the handouts skill names it, and no firearms or ammunition context in any file).

Needs nothing but Python: the comments are not compiled. Windows' PythonToolchainTests discovers this file.
"""
import csv
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
GUIDANCE = REPOSITORY / "support" / "agent_guidance"
SKILLS = GUIDANCE / "skills"
SKILL = SKILLS / "plantoir-report-comments"
MARKING = SKILLS / "plantoir-marking"
SCRIPT = MARKING / "scripts" / "make_named_copies.py"
RUNNER = MARKING / "scripts" / "run_with_names.py"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
FIREARMS_WORDS = re.compile(
    r"\b(firearms?|guns?|handguns?|shotguns?|rifles?|pistols?|revolvers?|ammunition|ammo|reload\w*|gunpowder)\b",
    re.IGNORECASE,
)


def contract():
    return json.loads(SHARED_RULES.read_text(encoding="utf-8"))


def comment_names():
    return contract()["assessment"]["commentNames"]


def table_words(table):
    """Every word of every name in an invented table, to look for in what was printed."""
    words = set()
    for row in csv.DictReader(table.splitlines()):
        for column in ("name", "first name"):
            for word in re.findall(r"[^\W\d_]+", row.get(column) or ""):
                if len(word) >= 2:
                    words.add(word.casefold())
    return words


def folders(root):
    marking = root / "Marking"
    teacher = root / "Marking - Teacher Only"
    return marking, teacher


def set_up(case, root):
    marking, teacher = folders(root)
    drafts = marking / "Term 1 Comments" / "Comments.json"
    drafts.parent.mkdir(parents=True, exist_ok=True)
    drafts.write_text(json.dumps({"term": "Term 1", "students": case["students"]}), encoding="utf-8")
    if "draftsPage" in case:
        (drafts.parent / "Comments - Drafts.md").write_text(case["draftsPage"], encoding="utf-8")
    teacher.mkdir(parents=True, exist_ok=True)
    table = teacher / "Name Mapping Table.csv"
    table.write_text(case["table"], encoding="utf-8")
    if case.get("out") == "marking":
        out = marking / "Term 1 Comments" / "Named"
    else:
        out = teacher / "Term 1 Comments" / "Named"
    arguments = ["--comments", str(drafts), "--table", str(table), "--out", str(out), "--limit", str(case["limit"])]
    if "count" in case:
        arguments.extend(["--count", case["count"]])
    return drafts, table, out, arguments


def listing(folder):
    found = []
    for path in sorted(folder.rglob("*")):
        found.append((str(path), path.stat().st_size, path.stat().st_mtime_ns))
    return found


def written_rows(out):
    path = out / "Report Comments.csv"
    if not path.exists():
        return None
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        unit = "bytes" if "bytes" in reader.fieldnames else "characters"
        for row in reader:
            rows.append({"section": int(row["section"]), "identifier": row["identifier"], "option": int(row["option"]),
                         "comment": row["comment"], "size": int(row[unit]), "over": int(row["over the limit by"])})
    return rows


class CommentNameCaseTests(unittest.TestCase):

    def check_case(self, case, through_runner):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            marking, teacher = folders(root)
            drafts, table, out, arguments = set_up(case, root)
            before = listing(marking)
            command = [sys.executable, "-B", str(SCRIPT)] + arguments
            if through_runner:
                command = [sys.executable, "-B", str(RUNNER), "--table", str(table), "--watch", str(marking),
                           "--quarantine", str(teacher / "Quarantine"), "--"] + command
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", cwd=folder)
            said = result.stdout + result.stderr
            label = case["name"] + (" (through the runner)" if through_runner else "")
            if through_runner:
                self.assertIn("0 printed lines were withheld", said, label)
                self.assertIn("0 files and 0 folders held a word from your table", said, label)
                self.assertFalse((teacher / "Quarantine").exists() and any((teacher / "Quarantine").iterdir()), label)
            self.assertEqual(result.returncode, case["exit"], f"{label}: {said}")
            for line in case["says"]:
                self.assertIn(line, said, label)
            for word in table_words(case["table"]):
                self.assertIsNone(re.search(r"\b" + re.escape(word) + r"\b", said.casefold()),
                                  f"{label}: a name reached the output")
            self.assertEqual(before, listing(marking), f"{label}: something was written in the marking folder")
            rows = written_rows(out)
            if case.get("written") is False:
                self.assertIsNone(rows, f"{label}: a refused run wrote the named comments")
                if case.get("out") != "marking":
                    self.assertFalse(out.exists() and any(out.iterdir()), f"{label}: a refused run wrote something")
            else:
                self.assertEqual(rows, case["filled"], label)
                page = (out / "Report Comments.md").read_text(encoding="utf-8")
                for row in case["filled"]:
                    self.assertIn(row["comment"], page, label)
                for path in out.iterdir():
                    self.assertIn(path.name, ("Report Comments.csv", "Report Comments.md"), label)

    def test_every_contract_case(self):
        for case in comment_names()["cases"]:
            with self.subTest(case["name"]):
                self.check_case(case, through_runner=False)

    def test_every_contract_case_through_the_runner(self):
        for case in comment_names()["cases"]:
            with self.subTest(case["name"]):
                self.check_case(case, through_runner=True)

    def test_every_placeholder_the_contract_names_is_filled_by_the_script(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for placeholder in comment_names()["placeholders"]:
            self.assertIn('"' + placeholder.strip("{}") + '"', source, placeholder)

    def test_the_longest_first_name_is_a_number_never_a_name(self):
        with tempfile.TemporaryDirectory() as folder:
            table = Path(folder) / "Name Mapping Table.csv"
            table.write_text('section,identifier,name,first name\n1,Student A,"Testfamily, Bartholomewina",\n'
                             '1,Student B,"Zedfamily, Zoë",Zoë\n', encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--longest-first-name", "--table", str(table)],
                                    capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("The longest first name in your mapping table is 14 characters (14 bytes)", result.stdout)
            for word in ("Bartholomewina", "Testfamily", "Zedfamily", "Zoë"):
                self.assertNotIn(word.casefold(), (result.stdout + result.stderr).casefold())

    def test_a_teachers_notes_are_checked_by_line_number_only(self):
        with tempfile.TemporaryDirectory() as folder:
            table = Path(folder) / "Name Mapping Table.csv"
            table.write_text('section,identifier,name,first name\n1,Student A,"Testfamily, Alphaname",Alphaname\n',
                             encoding="utf-8")
            notes = Path(folder) / "Teacher Notes.md"
            notes.write_text("# Notes\n\nStudent A led the group.\nStudent A: Alphaname explained it well.\n",
                             encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--check-file", str(notes), "--table", str(table)],
                                    capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("A word from your mapping table is on 1 line of the file (line 4)", result.stdout)
            self.assertNotIn("alphaname", (result.stdout + result.stderr).casefold())
            notes.write_text("# Notes\n\nStudent A led the group.\n", encoding="utf-8")
            clean = subprocess.run([sys.executable, "-B", str(SCRIPT), "--check-file", str(notes), "--table", str(table)],
                                   capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(clean.returncode, 0, clean.stdout)
            self.assertIn("none holds a word from your mapping table", clean.stdout)
            self.assertIn("is not found", clean.stdout, "the clean line must say what it cannot find")

    def test_its_own_self_test_passes(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--self-test"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)


class SkillFileTests(unittest.TestCase):

    def guidance(self):
        return contract()["assessment"]["agentGuidance"]["reportCommentsSkill"]

    def test_every_listed_file_is_there_and_every_script_it_uses(self):
        guidance = self.guidance()
        self.assertEqual(SKILL.name, guidance["skill"])
        self.assertTrue((SKILL / "SKILL.md").is_file())
        for relative in guidance["references"]:
            self.assertTrue((SKILL / relative).is_file(), relative)
        text = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        for relative in guidance["uses"]:
            self.assertTrue((SKILLS / relative).is_file(), f"{relative} must be in the skill it belongs to")
            self.assertIn(relative.rsplit("/", 1)[1], text, f"the skill must say how to run {relative}")
        for relative in guidance["references"]:
            self.assertIn(relative, text, f"the skill names {relative}")

    def test_the_skill_is_named_as_its_folder_with_a_short_enough_description(self):
        text = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\nname: plantoir-report-comments\n"))
        description = re.search(r"^description: (.*)$", text, re.MULTILINE).group(1)
        self.assertLessEqual(len(description), 1024)
        self.assertIn("This working folder holds courses for Plantoir", text)
        self.assertIn("read_how_i_teach", text)

    def test_every_pin_is_in_the_skill_once(self):
        pins = contract()["printablePages"]["agentGuidance"]["mustSay"]["plantoir-report-comments"]
        self.assertGreater(len(pins), 10)
        folded = re.sub(r"\s+", " ", (SKILL / "SKILL.md").read_text(encoding="utf-8"))
        for pin in pins:
            self.assertEqual(folded.count(re.sub(r"\s+", " ", pin)), 1, pin)

    def test_the_skills_that_mention_it_and_both_root_files_name_it(self):
        name = self.guidance()["skill"]
        for mentioning in self.guidance()["mentionedBy"]:
            text = (SKILLS / mentioning / "SKILL.md").read_text(encoding="utf-8")
            self.assertTrue("`" + name + "`" in text, f"{mentioning} must name `{name}`")
        for root_file in contract()["printablePages"]["agentGuidance"]["rootFiles"]:
            self.assertTrue(name in (GUIDANCE / root_file).read_text(encoding="utf-8"), f"{root_file} must name {name}")

    def test_the_offered_templates_name_is_the_handouts_skills(self):
        name = contract()["printablePages"]["agentGuidance"]["handoutsSkill"]["offeredTemplate"]["name"]
        for relative in ["SKILL.md"] + self.guidance()["references"]:
            folded = re.sub(r"\s+", " ", (SKILL / relative).read_text(encoding="utf-8"))
            self.assertIn('"' + name + '"', folded, relative)

    def test_the_example_comments_carry_placeholders_and_no_name(self):
        # The reference's examples are drafts as the skill writes them: {first name}, never a name or a pronoun.
        text = (SKILL / "reference" / "template.md").read_text(encoding="utf-8")
        examples = re.findall(r"```text wrap\n(.*?)\n```", text, re.DOTALL)
        self.assertGreaterEqual(len(examples), 3)
        for example in examples:
            self.assertIn("{first name}", example)
            self.assertIsNone(re.search(r"\b(he|she|his|her|him|hers)\b", example, re.IGNORECASE), example)
            self.assertLessEqual(len(example.replace("{first name}", "Bartholomewina")), 450, example)

    def test_no_file_carries_a_firearms_context(self):
        for path in sorted(SKILL.rglob("*")):
            if path.is_file():
                found = FIREARMS_WORDS.findall(path.read_text(encoding="utf-8"))
                if path.name == "SKILL.md":
                    # The rule itself names them once: "never involve firearms or ammunition".
                    found = [word for word in found if word.lower() not in ("firearms", "ammunition")]
                self.assertEqual(found, [], str(path.relative_to(SKILL)))


if __name__ == "__main__":
    unittest.main()
