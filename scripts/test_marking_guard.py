#!/usr/bin/env python3
"""
The plantoir-marking skill's runner (#750, piece 750a): scripts/run_with_names.py, the one script that is
never adapted. An adapted script's own --self-test is adapted along with it, so it proves nothing about
the adaptation (750 plan review R3); the runner is the net under every script that reads the mapping
table.

A deliberately leaky "adapted" script is run under it, with an invented mapping table: it prints a row of
the table, prints a name run together and lower-cased, prints an e-mail's local part, writes a row into
the marking folder, writes a file whose NAME holds a name, and raises an exception whose message carries
a name (so a traceback reaches stderr). Nothing of the table may reach the runner's output or stay in the
marking folder: the lines are withheld and counted, the files moved to the teacher-only quarantine and
counted, and the run exits 1. A clean script's lines are passed on and its exit code kept. A table or a
quarantine inside the watched folder is refused, and the runner says it is a safety net, not a guarantee.

Stdlib only (the PDF case skips without pdftotext and tectonic). Windows' PythonToolchainTests discovers
this file.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SKILL = REPOSITORY / "support" / "agent_guidance" / "skills" / "plantoir-marking"
RUNNER = SKILL / "scripts" / "run_with_names.py"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
TABLE = ("section,identifier,name,first name,email,handles\n"
         "1,Student A,\"Testfamily, Pupilseven\",Pupilseven,pseven.testfamily@school.example,pupil7tf\n"
         "1,Student B,\"Samplefamily-Otherline, Pupileight\",Pupileight,,\n")
TOKENS = ["Testfamily", "Pupilseven", "pseven.testfamily", "pupil7tf", "Samplefamily", "Otherline", "Pupileight",
          "pupilseventestfamily"]

LEAKY = r'''
import csv, sys
from pathlib import Path
table, marking = sys.argv[1], Path(sys.argv[2])
rows = list(csv.DictReader(open(table, encoding="utf-8")))
print("Section 1: 2 sheets made")
print(rows[0])
print("made " + (rows[0]["first name"] + rows[0]["name"].split(",")[0]).lower())
print("mailed " + rows[0]["email"].split("@")[0])
print("Student B done")
(marking / "notes.txt").write_text("for " + rows[1]["name"], encoding="utf-8")
(marking / (rows[0]["first name"] + ".txt")).write_text("x", encoding="utf-8")
(marking / "clean.txt").write_text("Student A: K 3/4", encoding="utf-8")
raise RuntimeError("could not finish " + rows[1]["first name"])
'''

CLEAN = r'''
import sys
print("Section 1: 2 sheets made")
print("Student B: not in the mapping table")
sys.exit(3)
'''

PDF_WRITER = r'''
import subprocess, sys, csv
from pathlib import Path
rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
folder = Path(sys.argv[2])
tex = folder / "sheet.tex"
tex.write_text("\\documentclass{article}\\begin{document}" + rows[0]["first name"] + "\\end{document}", encoding="utf-8")
subprocess.run(["tectonic", "-c", "minimal", str(tex)], capture_output=True, cwd=folder)
tex.unlink()
print("one sheet")
'''


def run(runner, root, script_text, extra=()):
    marking = root / "Marking"
    teacher = root / "Marking - Teacher Only"
    marking.mkdir(exist_ok=True)
    teacher.mkdir(exist_ok=True)
    table = teacher / "Name Mapping Table.csv"
    table.write_text(TABLE, encoding="utf-8")
    script = root / "adapted.py"
    script.write_text(script_text, encoding="utf-8")
    command = [sys.executable, "-B", str(runner), "--table", str(table), "--watch", str(marking), "--quarantine",
               str(teacher / "Quarantine"), *extra, "--", sys.executable, "-B", str(script), str(table), str(marking)]
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8"), marking, teacher


def every_text_under(folder):
    found = ""
    for path in Path(folder).rglob("*"):
        found += str(path.relative_to(folder)) + "\n"
        if path.is_file():
            found += path.read_bytes().decode("utf-8", "replace") + "\n"
    return found


class RunnerTests(unittest.TestCase):

    def test_a_leaky_script_lets_nothing_of_the_table_through(self):
        with tempfile.TemporaryDirectory() as folder:
            result, marking, teacher = run(RUNNER, Path(folder), LEAKY)
            said = result.stdout + result.stderr
            for token in TOKENS:
                self.assertNotIn(token.casefold(), said.casefold(), "a name reached the runner's output")
                self.assertNotIn(token.casefold(), every_text_under(marking).casefold(), "a name stayed in the marking folder")
            self.assertIn("Section 1: 2 sheets made", said)
            self.assertIn("Student B done", said)
            self.assertIn("held a name and were withheld", said)
            self.assertIn("2 held a name and were moved to the quarantine folder", said)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(sorted(path.name for path in marking.iterdir()), ["clean.txt"])
            self.assertEqual(len(list((teacher / "Quarantine").iterdir())), 2)

    def test_a_clean_script_is_passed_through_with_its_exit_code(self):
        with tempfile.TemporaryDirectory() as folder:
            result, _marking, _teacher = run(RUNNER, Path(folder), CLEAN)
            self.assertIn("Section 1: 2 sheets made\nStudent B: not in the mapping table\n", result.stdout)
            self.assertIn("0 printed lines held a name and were withheld", result.stdout)
            self.assertEqual(result.returncode, 3)

    def test_it_says_it_is_a_net_and_not_a_lock(self):
        says = json.loads(SHARED_RULES.read_text(encoding="utf-8"))["assessment"]["scriptPrivacy"]["runner"]["says"]
        with tempfile.TemporaryDirectory() as folder:
            result, _marking, _teacher = run(RUNNER, Path(folder), CLEAN)
            self.assertIn(says, result.stdout)

    def test_a_table_inside_the_marking_folder_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "Marking").mkdir()
            table = root / "Marking" / "Name Mapping Table.csv"
            table.write_text(TABLE, encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(RUNNER), "--table", str(table), "--watch", str(root / "Marking"),
                                     "--quarantine", str(root / "Q"), "--", sys.executable, "-c", "print('ran')"],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("the mapping table is inside the marking folder", result.stdout)
            self.assertNotIn("ran", result.stdout)

    @unittest.skipIf(shutil.which("pdftotext") is None or shutil.which("tectonic") is None,
                     "pdftotext or tectonic not found here; the PDF case needs both")
    def test_a_pdf_holding_a_name_is_moved(self):
        with tempfile.TemporaryDirectory() as folder:
            result, marking, teacher = run(RUNNER, Path(folder), PDF_WRITER)
            self.assertIn("1 held a name and were moved to the quarantine folder", result.stdout)
            self.assertFalse((marking / "sheet.pdf").exists())
            self.assertTrue((teacher / "Quarantine" / "sheet.pdf").exists())


if __name__ == "__main__":
    unittest.main()
