#!/usr/bin/env python3
"""
The plantoir-marking skill's class results (#750, piece 750c): scripts/class_results.py, which builds the
class's results from the marks records (and from level records, only when a Records folder is there),
identifiers only, and make_named_copies.py's two modes for them, --grades and --document.

Every case in contracts/shared-rules.json -> assessment -> results -> cases is run as the skill runs it: an
invented marking folder holding the contract's base kit (kitFormat.base), marks records, Marks by Question
sheets and level records, the teacher's Marking Settings.md, and the script as a subprocess with --tex-only.
Every case in namedCopies.gradeCases is run directly and through the runner, with an invented mapping table
in a teacher-only folder; namedCopies.documentCases need tectonic and Poppler and skip, saying so, without.
After every named case: no word of the table is in what was printed, and nothing new is in the marking folder.

Also: both scripts' --self-test; one case compiled to a PDF (when tectonic is here); the skill names the
script and its reference, and the settings template carries the scale line the script reads.

Stdlib only. Windows' PythonToolchainTests discovers this file.
"""
import csv
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
SKILL = SKILLS / "plantoir-marking"
SCRIPT = SKILL / "scripts" / "class_results.py"
NAMES = SKILL / "scripts" / "make_named_copies.py"
RUNNER = SKILL / "scripts" / "run_with_names.py"
CHECKER = SKILLS / "plantoir-test-authoring" / "scripts" / "check_kit.py"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
MISSING = [tool for tool in ("tectonic", "pdftotext") if shutil.which(tool) is None]
SKIP_REASON = ", ".join(MISSING) + " not found here; these cases compile and read PDFs"


def contract():
    return json.loads(SHARED_RULES.read_text(encoding="utf-8"))


def assessment():
    return contract()["assessment"]


def read_rows(path):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        return list(csv.reader(handle))


def listing(folder):
    found = []
    for path in sorted(folder.rglob("*")):
        found.append((str(path), path.stat().st_size, path.stat().st_mtime_ns))
    return found


def table_words(table):
    """Every word of every name in an invented table, to look for in what was printed."""
    words = set()
    for row in csv.DictReader(table.splitlines()):
        for word in re.findall(r"[^\W\d_]+", row.get("name") or ""):
            if len(word) >= 2 and word not in ("Co",):
                words.add(word.casefold())
    return words


# ---------------------------------------------------------------- class_results.py


def marks_record(base_marks, kit, identifier, section, earned, voided):
    record = json.loads(json.dumps(base_marks))
    record["identifier"] = identifier
    record["section"] = section
    for point, value in zip(kit["points"], earned):
        record["points"][point["id"]]["earned"] = value
        record["points"][point["id"]]["studentNote"] = "" if value == 1 else "A reason."
    record["voided"] = {}
    for point_id in voided:
        record["voided"][point_id] = {"reason": "the question did not work", "intended": "a second roll"}
    return record


def set_up(case, root):
    """Write the case's marking folder; return (the command, the results folder)."""
    kitformat = assessment()["kitFormat"]
    kit = kitformat["base"]
    marking = root / "Marking"
    marking.mkdir(parents=True)
    kit_path = root / "Kit" / "answers.json"
    kit_path.parent.mkdir(parents=True)
    kit_path.write_text(json.dumps(kit), encoding="utf-8")
    settings = marking / "Marking Settings.md"
    settings.write_text(case["settings"], encoding="utf-8")
    command = [sys.executable, "-B", str(SCRIPT)]
    for entry in case["assessments"]:
        folder = marking / entry["folder"]
        folder.mkdir(parents=True)
        command.extend(["--assessment", str(folder)])
        if "marks" in entry:
            command.extend(["--kit", str(kit_path)])
            for relative, earned in entry["marks"].items():
                section = int(relative.split("/")[0].split(" ")[1])
                identifier = relative.split("/")[1]
                inside = entry.get("identifierInside", {}).get(relative, identifier)
                path = folder / "Marks" / (relative + ".json")
                path.parent.mkdir(parents=True, exist_ok=True)
                record = marks_record(kitformat["baseMarks"], kit, inside, section, earned,
                                      entry.get("voided", {}).get(relative, []))
                path.write_text(json.dumps(record), encoding="utf-8")
        for relative, line in entry.get("sheets", {}).items():
            path = folder / "Sheets" / (relative + " - Marks by Question.tex")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("\\documentclass{article}\n\\begin{document}\n{\\large\\bfseries\\sffamily "
                            + line.replace(" \u00b7 ", " $\\cdot$ ") + "}\\par\\vspace{2pt}\n\\end{document}\n",
                            encoding="utf-8")
        for relative, levels in entry.get("records", {}).items():
            path = folder / "Records" / (relative + ".json")
            path.parent.mkdir(parents=True, exist_ok=True)
            shaped = {}
            for key, pair in levels.items():
                shaped[key] = {"first": pair[0], "revised": pair[1]}
            path.write_text(json.dumps({"identifier": relative.split("/")[1], "section": int(relative.split(" ")[1].split("/")[0]),
                                        "levels": shaped}), encoding="utf-8")
    if len(case["assessments"]) > 1:
        out = marking / "Term 1 Results"
        command.extend(["--out", str(out)])
    else:
        out = marking / case["assessments"][0]["folder"] / "Results"
    command.extend(["--checker", str(CHECKER), "--settings", str(settings)])
    return command, out


class ResultsCaseTests(unittest.TestCase):

    def check_case(self, case, compile_too=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            command, out = set_up(case, root)
            if case.get("earlier"):
                out.mkdir(parents=True)
                (out / "Class Results.tex").write_text("an earlier run", encoding="utf-8")
                (out / "Grades - Unit 1 Test.csv").write_text("an earlier run", encoding="utf-8")
            if not compile_too:
                command.append("--tex-only")
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", cwd=folder)
            said = result.stdout + result.stderr
            label = case["name"]
            self.assertEqual(result.returncode, case["exit"], f"{label}: {said}")
            for line in case.get("says", []):
                self.assertIn(line, said, label)
            for word in case.get("saysNot", []):
                self.assertNotIn(word, said, label)
            for word in assessment()["results"]["neverSays"]:
                self.assertIsNone(re.search(r"\b" + word + r"\b", said, re.IGNORECASE), f"{label}: it said {word}")
            if case.get("earlier"):
                self.assertTrue((out / "Class Results - earlier run, do not use.tex").is_file(), label)
                self.assertTrue((out / "Grades - Unit 1 Test - earlier run, do not use.csv").is_file(), label)
            if case.get("written") is False:
                self.assertFalse((out / "Class Results.tex").exists(), f"{label}: a stopped build wrote a document")
                self.assertFalse(out.exists() and any(path.suffix == ".csv" and "earlier run" not in path.name
                                                      for path in out.iterdir()), f"{label}: a stopped build wrote a table")
                return
            for name, rows in case.get("grades", {}).items():
                self.assertEqual(read_rows(out / f"Grades - {name}.csv"), rows, label)
            for name, rows in case.get("levels", {}).items():
                self.assertEqual(read_rows(out / f"Levels - {name}.csv"), rows, label)
            tex = (out / "Class Results.tex").read_text(encoding="utf-8")
            folded = re.sub(r"\s+", " ", tex)
            for text in case.get("document", []):
                self.assertIn(text, folded, label)
            place = -1
            for text in case.get("documentInOrder", []):
                self.assertGreater(folded.find(text), place, f"{label}: {text} is out of order")
                place = folded.find(text)
            self.assertIn("I draft; you decide.", tex, label)
            if compile_too:
                self.assertTrue((out / "Class Results.pdf").is_file(), label)
                printed = subprocess.run(["pdftotext", str(out / "Class Results.pdf"), "-"], capture_output=True,
                                         text=True).stdout
                self.assertIn("What this was built from", printed, label)
                self.assertIn("Student A", printed, label)

    def test_every_contract_case(self):
        cases = assessment()["results"]["cases"]
        self.assertGreaterEqual(len(cases), 15)
        for case in cases:
            with self.subTest(case=case["name"]):
                self.check_case(case)

    @unittest.skipIf(MISSING, SKIP_REASON)
    def test_a_case_compiles_to_a_pdf(self):
        for case in assessment()["results"]["cases"]:
            if case["name"].startswith("levels with steps map through"):
                self.check_case(case, compile_too=True)
                return
        self.fail("the levels case is not in the contract")

    def test_its_own_self_test_passes(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--self-test", "--checker", str(CHECKER)],
                                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)

    def test_it_never_writes_inside_a_working_folder(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "courses").mkdir()
            (root / ".toolchain").mkdir()
            case = assessment()["results"]["cases"][0]
            command, out = set_up(case, root)
            result = subprocess.run(command + ["--tex-only"], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 1)
            self.assertIn("inside the Plantoir working folder", result.stdout)
            self.assertFalse(out.exists())


# ---------------------------------------------------------------- make_named_copies.py --grades and --document


def named_folders(root):
    return root / "Marking", root / "Marking - Teacher Only"


class NamedResultsTests(unittest.TestCase):

    def run_named(self, case, root, arguments, out, through_runner):
        marking, teacher = named_folders(root)
        table = teacher / "Name Mapping Table.csv"
        before = listing(marking)
        command = [sys.executable, "-B", str(NAMES)] + arguments + ["--table", str(table), "--out", str(out)]
        if through_runner:
            command = [sys.executable, "-B", str(RUNNER), "--table", str(table), "--watch", str(marking),
                       "--quarantine", str(teacher / "Quarantine"), "--"] + command
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", cwd=str(root))
        said = result.stdout + result.stderr
        label = case["name"] + (" (through the runner)" if through_runner else "")
        if through_runner:
            self.assertIn("0 printed lines were withheld", said, label)
            self.assertIn("0 files and 0 folders held a word from your table", said, label)
        self.assertEqual(result.returncode, case["exit"], f"{label}: {said}")
        for line in case["says"]:
            self.assertIn(line, said, label)
        for word in table_words(case["table"]):
            self.assertIsNone(re.search(r"\b" + re.escape(word) + r"\b", said.casefold()), f"{label}: a name reached the output")
        if case.get("out") != "marking":
            self.assertEqual(before, listing(marking), f"{label}: something was written in the marking folder")
        return label

    def check_grade_case(self, case, through_runner):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            marking, teacher = named_folders(root)
            grades = marking / "Unit 1 Test" / "Results" / "Grades - Unit 1 Test.csv"
            grades.parent.mkdir(parents=True)
            grades.write_text(case["grades"], encoding="utf-8")
            teacher.mkdir(parents=True)
            (teacher / "Name Mapping Table.csv").write_text(case["table"], encoding="utf-8")
            if case.get("out") == "marking":
                out = marking / "Unit 1 Test" / "Named"
            else:
                out = teacher / "Unit 1 Test" / "Named"
            label = self.run_named(case, root, ["--grades", str(grades)], out, through_runner)
            named = out / "Grades - Unit 1 Test (Names).csv"
            if case["rows"] is None:
                self.assertFalse(named.exists(), f"{label}: a refused run wrote the named table")
            else:
                self.assertEqual(read_rows(named), case["rows"], label)
                self.assertEqual(sorted(path.name for path in out.iterdir()), [named.name], label)

    def test_every_grade_case(self):
        for case in assessment()["namedCopies"]["gradeCases"]:
            with self.subTest(case=case["name"]):
                self.check_grade_case(case, through_runner=False)

    def test_every_grade_case_through_the_runner(self):
        for case in assessment()["namedCopies"]["gradeCases"]:
            with self.subTest(case=case["name"]):
                self.check_grade_case(case, through_runner=True)

    @unittest.skipIf(MISSING, SKIP_REASON)
    def test_every_document_case(self):
        for case in assessment()["namedCopies"]["documentCases"]:
            with self.subTest(case=case["name"]):
                with tempfile.TemporaryDirectory() as folder:
                    root = Path(folder)
                    marking, teacher = named_folders(root)
                    document = marking / "Unit 1 Test" / "Results" / "Class Results.tex"
                    document.parent.mkdir(parents=True)
                    body = ""
                    for section, identifier in case["students"]:
                        body += "\\student{" + str(section) + "}{" + identifier + "} has a row.\\par\n"
                    document.write_text("\\documentclass{article}\n\\usepackage[T1]{fontenc}\n\\usepackage{lmodern}\n"
                                        "\\newcommand{\\student}[2]{#2}\n\\begin{document}\n{\\large\\bfseries\\sffamily "
                                        "Results}\\par\n" + body + "\\end{document}\n", encoding="utf-8")
                    teacher.mkdir(parents=True)
                    (teacher / "Name Mapping Table.csv").write_text(case["table"], encoding="utf-8")
                    out = teacher / "Unit 1 Test" / "Named"
                    label = self.run_named(case, root, ["--document", str(document)], out, through_runner=True)
                    named = out / "Class Results (Names).pdf"
                    self.assertEqual(named.exists(), case["written"], label)
                    if case["written"]:
                        printed = re.sub(r"\s+", "", subprocess.run(["pdftotext", str(named), "-"], capture_output=True,
                                                                    text=True).stdout)
                        for row in csv.DictReader(case["table"].splitlines()):
                            self.assertIn(re.sub(r"\s+", "", row["name"]), printed.replace("\u2019", "'"), label)

    def test_its_own_self_test_passes(self):
        result = subprocess.run([sys.executable, "-B", str(NAMES), "--self-test"], capture_output=True, text=True,
                                encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)
        self.assertIn("grade table", result.stdout)


# ---------------------------------------------------------------- the skill's files


class SkillFileTests(unittest.TestCase):

    def test_the_skill_names_the_script_and_its_reference(self):
        results = assessment()["results"]
        guidance = assessment()["agentGuidance"]["markingSkill"]
        self.assertIn(results["script"], guidance["scripts"])
        self.assertIn(results["reference"], guidance["references"])
        skill = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("class_results.py", skill)
        self.assertIn("reference/results.md", skill)
        self.assertIn("--grades", skill)
        self.assertIn("--document", skill)
        reference = (SKILL / results["reference"]).read_text(encoding="utf-8")
        self.assertIn(results["scaleLine"], reference)
        self.assertIn(results["noRevisionTitle"], (SKILL / results["script"]).read_text(encoding="utf-8"))

    def test_the_settings_template_carries_the_scale_line_the_script_reads(self):
        results = assessment()["results"]
        template = (SKILL / "templates" / results["scaleFrom"]).read_text(encoding="utf-8")
        self.assertIn(results["scaleLine"] + " none", template)


if __name__ == "__main__":
    unittest.main()
