#!/usr/bin/env python3
"""
The plantoir-marking skill's named step (#750, piece 750a): scripts/make_named_copies.py, the only script
that puts a student's name into anything.

Every case in contracts/shared-rules.json -> assessment -> namedCopies -> cases is run the way the skill
runs it: an invented mapping table in a teacher-only folder, identifier sheets in a marking folder, the
script as a subprocess. After every case: the lines the case names are printed, the named PDFs it names
are written and nothing else, no value of the table (no word of any name) is in what the script printed,
nothing new is in the marking folder, and no .tex, .log or .aux is in the named folder. A written copy
must really carry its name: pdftotext finds it.

Also: the script's own --self-test; and its source never passes tectonic --keep-logs or --print.

Needs tectonic and Poppler's pdftotext; every case skips, saying so, where either is missing. Stdlib only
otherwise. Windows' PythonToolchainTests discovers this file.
"""
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
SKILL = REPOSITORY / "support" / "agent_guidance" / "skills" / "plantoir-marking"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
SCRIPT = SKILL / "scripts" / "make_named_copies.py"
MISSING = [tool for tool in ("tectonic", "pdftotext") if shutil.which(tool) is None]
SKIP_REASON = ", ".join(MISSING) + " not found here; the named-copy cases compile and read PDFs"

PLAIN = ("\\documentclass{article}\n\\usepackage[T1]{fontenc}\n\\usepackage{lmodern}\n"
         "\\newcommand{\\studentline}[1]{#1}\n\\begin{document}\nFeedback for \\studentline{IDENT}\n\\end{document}\n")
BROKEN = PLAIN.replace("\\studentline{IDENT}\n", "\\studentline{IDENT} \\notamacrohere\n")


def named_copies():
    return json.loads(SHARED_RULES.read_text(encoding="utf-8"))["assessment"]["namedCopies"]


def table_words(table):
    """Every word of every name in an invented table, to look for in what the script printed."""
    words = set()
    for line in table.splitlines()[1:]:
        name = line.split(",", 2)[2] if line.count(",") >= 2 else ""
        for word in re.findall(r"\w+", name):
            if len(word) >= 2 and not re.match(r"^(Student|Co)$", word):
                words.add(word)
    return words


def run_case(script, case, root):
    marking = root / "Marking"
    teacher = root / "Marking - Teacher Only"
    sheets = marking / "Test" / "Sheets"
    for relative, kind in case["sheets"].items():
        path = sheets / (relative + ".tex")
        path.parent.mkdir(parents=True, exist_ok=True)
        identifier = Path(relative).name.split(" - ")[0]
        path.write_text((PLAIN if kind == "plain" else BROKEN).replace("IDENT", identifier), encoding="utf-8")
    teacher.mkdir(parents=True, exist_ok=True)
    table = teacher / "Name Mapping Table.csv"
    table.write_text(case["table"], encoding="utf-8")
    out = marking / "Test" / "Named" if case.get("out") == "marking" else teacher / "Test" / "Named"
    before = sorted(str(path) for path in marking.rglob("*"))
    result = subprocess.run([sys.executable, "-B", str(script), "--table", str(table), "--sheets", str(sheets),
                             "--out", str(out)], capture_output=True, text=True, encoding="utf-8")
    after = sorted(str(path) for path in marking.rglob("*"))
    return result, out, before, after


@unittest.skipIf(MISSING, SKIP_REASON)
class NamedCopyTests(unittest.TestCase):

    def test_every_contract_case(self):
        for case in named_copies()["cases"]:
            with self.subTest(case["name"]), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                result, out, before, after = run_case(SCRIPT, case, root)
                said = result.stdout + result.stderr
                self.assertEqual(result.returncode, case["exit"], f"{case['name']}: {said}")
                for line in case["says"]:
                    self.assertIn(line, said, case["name"])
                for word in table_words(case["table"]):
                    self.assertNotIn(word.casefold(), said.casefold(), f"{case['name']}: a name reached the output")
                self.assertEqual(before, after, f"{case['name']}: something was written in the marking folder")
                written = []
                if out.exists():
                    for path in sorted(out.rglob("*")):
                        if path.is_file():
                            written.append(str(path.relative_to(out)))
                            self.assertNotIn(path.suffix, (".tex", ".log", ".aux"), case["name"])
                self.assertEqual(written, case["written"], case["name"])
                for relative in written:
                    text = subprocess.run(["pdftotext", str(out / relative), "-"], capture_output=True).stdout.decode("utf-8")
                    name = relative.split("/", 1)[1].rsplit(" - ", 1)[0]
                    self.assertIn(re.sub(r"\s+", "", unicodedata.normalize("NFC", name)),
                                  re.sub(r"\s+", "", unicodedata.normalize("NFC", text)), f"{case['name']}: the name is not printed")

    def test_the_script_never_keeps_or_prints_tectonics_logs(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for flag in named_copies()["neverPassed"]:
            self.assertNotIn('"' + flag + '"', source)

    def test_every_escaped_character_is_escaped(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for character in named_copies()["escaped"]:
            self.assertIn('("' + character.replace("\\", "\\\\") + '", ', source, character)

    def test_its_own_self_test_passes(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--self-test"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
