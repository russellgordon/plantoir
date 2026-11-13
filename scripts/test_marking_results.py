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
import os
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
SHEET_BUILDER = SKILL / "scripts" / "build_test_sheet.py"
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


def kit_for(entry):
    """The contract's base kit, or with `kitPoints` one with that many points per category, every version
    answering each point."""
    kit = json.loads(json.dumps(assessment()["kitFormat"]["base"]))
    if entry.get("kitVoided"):
        kit["voided"] = {}
        for point_id in entry["kitVoided"]:
            kit["voided"][point_id] = {"reason": "the question did not work", "intended": "a second roll"}
    sizes = entry.get("kitPoints")
    if not sizes:
        return kit
    points = []
    for category, part, question in (("K", "A", "A1"), ("T", "B", "B1")):
        for index in range(1, sizes[category] + 1):
            point_id = question if sizes[category] == 1 else f"{question}.{index}"
            points.append({"id": point_id, "question": question, "category": category, "meaning": f"point {index}"})
    kit["points"] = points
    for version in kit["versions"].values():
        answers = {}
        for point in points:
            answers[point["id"]] = {"answer": "an answer", "accept": []}
        version["answers"] = answers
    kit["strengths"] = [{"sentence": "Counting outcomes", "halves": [{"points": [points[0]["id"], points[-1]["id"]],
                                                                      "sentence": None}]}]
    return kit


def earned_list(kit, earned):
    """A list of earned values in the kit's point order, from a list or from a count per category."""
    if isinstance(earned, list):
        return earned
    values = []
    seen = {}
    for point in kit["points"]:
        seen[point["category"]] = seen.get(point["category"], 0) + 1
        values.append(1 if seen[point["category"]] <= earned.get(point["category"], 0) else 0)
    return values


def marks_record(kit, identifier, section, earned, voided):
    points = {}
    for point, value in zip(kit["points"], earned_list(kit, earned)):
        points[point["id"]] = {"earned": value, "seen": "", "note": "", "studentNote": "" if value == 1 else "A reason."}
    record = json.loads(json.dumps(assessment()["kitFormat"]["baseMarks"]))
    record.update({"identifier": identifier, "section": section, "points": points, "voided": {},
                   "summary": "A short summary.", "closing": "Your best work was the first part."})
    for point_id in voided:
        record["voided"][point_id] = {"reason": "the question did not work", "intended": "a second roll"}
    return record


def set_up(case, root):
    """Write the case's marking folder; return (the command, the results folder, {folder: (kit path, kit)})."""
    marking = root / "Marking"
    marking.mkdir(parents=True)
    settings = marking / "Marking Settings.md"
    settings.write_text(case["settings"], encoding="utf-8")
    command = [sys.executable, "-B", str(SCRIPT)]
    kits = {}
    for entry in case["assessments"]:
        folder = marking / entry["folder"]
        folder.mkdir(parents=True)
        command.extend(["--assessment", str(folder)])
        if "marks" in entry:
            kit = kit_for(entry)
            kit_path = root / "Kits" / entry["folder"] / "answers.json"
            kit_path.parent.mkdir(parents=True)
            kit_path.write_text(json.dumps(kit), encoding="utf-8")
            kits[entry["folder"]] = (kit_path, kit)
            command.extend(["--kit", str(kit_path)])
            if entry.get("emptyMarks"):
                (folder / "Marks" / "Section 1").mkdir(parents=True)
            for relative, earned in entry["marks"].items():
                section = int(relative.split("/")[0].split(" ")[1])
                identifier = relative.split("/")[1]
                inside = entry.get("identifierInside", {}).get(relative, identifier)
                if "(" in identifier:
                    inside = identifier.split(" (")[0]
                path = folder / "Marks" / (relative + ".json")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(marks_record(kit, inside, section, earned,
                                                        entry.get("voided", {}).get(relative, []))), encoding="utf-8")
        for relative, line in entry.get("sheets", {}).items():
            path = folder / "Sheets" / (relative + " - Marks by Question.tex")
            path.parent.mkdir(parents=True, exist_ok=True)
            marks_line = "" if line is None else ("{\\large\\bfseries\\sffamily " + line.replace(" \u00b7 ", " $\\cdot$ ")
                                                  + "}\\par\\vspace{2pt}\n")
            path.write_text("\\documentclass{article}\n\\begin{document}\n" + marks_line + "\\end{document}\n",
                            encoding="utf-8")
        if entry.get("emptyRecords"):
            (folder / "Records" / "Section 1").mkdir(parents=True)
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
    return command, out, kits


BUILT = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d [0-9a-f]{12}$")


def table_without_built(test, path):
    """The rows of a table as the case lists them, after checking its built column apart."""
    rows = read_rows(path)
    test.assertEqual(rows[0][-1], assessment()["results"]["builtColumn"], str(path))
    stamps = set()
    for row in rows[1:]:
        test.assertRegex(row[-1], BUILT, str(path))
        stamps.add(row[-1])
    test.assertLessEqual(len(stamps), 1, str(path))
    trimmed = []
    for row in rows:
        trimmed.append(row[:-1])
    return trimmed


class ResultsCaseTests(unittest.TestCase):

    def check_case(self, case, compile_too=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            command, out, kits = set_up(case, root)
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
                self.assertEqual(table_without_built(self, out / f"Grades - {name}.csv"), rows, label)
            for name, rows in case.get("levels", {}).items():
                self.assertEqual(table_without_built(self, out / f"Levels - {name}.csv"), rows, label)
            self.assertFalse((out / ".building results").exists(), label)
            for path in out.iterdir():
                self.assertNotIn("earlier run", path.name, f"{label}: a build that put new documents in place left the old")
            if "sheetLine" in case:
                self.check_sheet(case, kits, root, label)
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

    def check_sheet(self, case, kits, root, label):
        """750c review H1: build_test_sheet.py must print the case's marks line from the same record."""
        entry = case["assessments"][0]
        kit_path, _kit = kits[entry["folder"]]
        record = sorted((root / "Marking" / entry["folder"] / "Marks").rglob("*.json"))[0]
        sheets = root / "Sheets made"
        result = subprocess.run([sys.executable, "-B", str(SHEET_BUILDER), "--kit", str(kit_path), "--marks", str(record),
                                 "--out", str(sheets), "--checker", str(CHECKER)], capture_output=True, text=True,
                                encoding="utf-8")
        if MISSING:
            self.assertIn("tectonic and Poppler's pdftotext are needed", result.stdout, label)
            return
        self.assertEqual(result.returncode, 0, f"{label}: {result.stdout}")
        self.assertIn(record.stem + ": " + case["sheetLine"].replace(" \u00b7 ", " "), result.stdout, label)
        tex = (sheets / (record.stem + " - Marks by Question.tex")).read_text(encoding="utf-8")
        self.assertIn("{\\large\\bfseries\\sffamily " + case["sheetLine"].replace(" \u00b7 ", " $\\cdot$ ") + "}", tex, label)

    def test_every_contract_case(self):
        cases = assessment()["results"]["cases"]
        self.assertGreaterEqual(len(cases), 36)
        for case in cases:
            with self.subTest(case=case["name"]):
                self.check_case(case)

    @unittest.skipIf(MISSING, SKIP_REASON)
    def test_a_case_compiles_to_a_pdf(self):
        for case in assessment()["results"]["cases"]:
            if case["name"].startswith("levels with steps map through an invented scale"):
                self.check_case(case, compile_too=True)
                return
        self.fail("the levels case is not in the contract")

    def test_its_own_self_test_passes(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--self-test", "--checker", str(CHECKER)],
                                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)

    def test_another_scale_gives_another_fingerprint(self):
        # 750c review H3: three runs with three scales printed one fingerprint, so a stale copy looked fresh.
        case = assessment()["results"]["cases"][0]
        printed = set()
        for scale in ("none", "4 83, 3 71, 2 62, 1 51", "4 88, 3 74, 2 63, 1 52"):
            with tempfile.TemporaryDirectory() as folder:
                changed = dict(case, settings="- Half marks: no\n- Levels scale: " + scale + "\n")
                command, out, _kits = set_up(changed, Path(folder))
                result = subprocess.run(command + ["--tex-only"], capture_output=True, text=True, encoding="utf-8")
                self.assertEqual(result.returncode, 0, result.stdout)
                printed.add(re.search(r"fingerprint ([0-9a-f]{12})", result.stdout).group(1))
                built = read_rows(out / "Grades - Unit 1 Test.csv")[1][-1]
                self.assertTrue(built.endswith(re.search(r"fingerprint ([0-9a-f]{12})", result.stdout).group(1)))
                self.assertIn(built.split(" ")[-1], (out / "Class Results.tex").read_text(encoding="utf-8"))
        self.assertEqual(len(printed), 3)

    @unittest.skipIf(os.name == "nt", "the stand-in tectonic is a shell script")
    def test_a_build_killed_half_way_leaves_no_document_that_looks_finished(self):
        # 750c fixes: a stand-in tectonic kills the build while it compiles, after the tables are written.
        case = assessment()["results"]["cases"][0]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            command, out, _kits = set_up(case, root)
            first = subprocess.run(command + ["--tex-only"], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(first.returncode, 0, first.stdout)
            tools = root / "tools"
            tools.mkdir()
            for name in ("tectonic", "pdftotext"):
                (tools / name).write_text("#!/bin/sh\nkill -9 $PPID\n", encoding="utf-8")
                os.chmod(tools / name, 0o755)
            environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ.get("PATH", ""))
            killed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", env=environment)
            self.assertNotEqual(killed.returncode, 0)
            names = sorted(path.name for path in out.iterdir())
            for name in ("Class Results.tex", "Class Results.pdf", "Grades - Unit 1 Test.csv"):
                self.assertNotIn(name, names, "a killed build left a document that looks finished")
            self.assertIn("Class Results - earlier run, do not use.tex", names)
            again = subprocess.run(command + ["--tex-only"], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(again.returncode, 0, again.stdout)
            self.assertFalse((out / ".building results").exists())
            self.assertTrue((out / "Class Results.tex").is_file())

    def test_it_never_writes_inside_a_working_folder(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "courses").mkdir()
            (root / ".toolchain").mkdir()
            case = assessment()["results"]["cases"][0]
            command, out, kits = set_up(case, root)
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

    def test_every_script_carries_the_one_identifier_rule(self):
        # 750c fix review M1: --identifiers took any pattern, matched at its start only, and the scripts that put
        # names in still read the default. One block, byte for byte, matched in full; no option anywhere.
        blocks = set()
        for name in ("redact_scans.py", "build_test_sheet.py", "make_named_copies.py", "class_results.py"):
            source = (SKILL / "scripts" / name).read_text(encoding="utf-8")
            start = source.index("# >>> The identifier rule.")
            blocks.add(source[start:source.index("# <<< The identifier rule.", start)])
            self.assertNotIn("--identifiers", source, name)
            self.assertNotIn("re.match(IDENTIFIER", source, name)
            self.assertNotIn("re.match(identifier", source, name)
        self.assertEqual(len(blocks), 1, "the identifier rule differs between scripts")
        block = blocks.pop()
        self.assertIn('IDENTIFIER = r"' + assessment()["identifiers"]["pattern"] + '"', block)
        self.assertIn("re.fullmatch(IDENTIFIER, text)", block)

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
        self.assertIn(results["roundingLine"] + " " + results["roundings"][0], template)
        script = (SKILL / results["script"]).read_text(encoding="utf-8")
        for rounding in results["roundings"]:
            self.assertIn('"' + rounding + '"', script)


if __name__ == "__main__":
    unittest.main()
