#!/usr/bin/env python3
"""
The plantoir-handouts skill's starters, patterns and checker (#859).

The owner's bar for #859: teachers get handouts at the quality he makes on
his own computer. An assistant imitates what it is shown, so the starters
are finished sheets and the rules an assistant keeps breaking are checked
by something that fails. This file proves both:

- every pattern and the checker named in contracts/shared-rules.json ->
  printablePages.agentGuidance.handoutsSkill ships and is named in the
  skill, every pinned macro is defined and named, and every mustSay phrase
  for the handouts and printing skills is said;
- the two richer patterns repeat starters/Handout.tex's preamble line for
  line, so a box copied from them needs nothing added;
- the checker's own --self-test passes;
- with tectonic and Poppler: every starter and pattern compiles in every
  copy it has, leaves only its PDFs beside its sources, is letter paper in
  Latin Modern, keeps the key's answers off the student copy, makes a
  hints sheet of hints alone, and compiles its question copy to the same
  text with or without the hints block; the checker finds nothing in any of
  them; and a broken copy of the starter for each rule makes the checker
  name that rule (and, for a centred negative column, prints "use N" on
  the page).

Stdlib only. The compile cases skip, saying so, without tectonic or
Poppler; Windows' PythonToolchainTests discovers this file.
"""
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
SKILL = SKILLS / "plantoir-handouts"
CHECKER = SKILL / "tools" / "check_handout.py"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
PREAMBLE_START = "% ---------- The starter's preamble, line for line (a test keeps it so) ----------\n"
PREAMBLE_END = "% ---------- End of the starter's preamble ----------\n"
HAVE_TOOLS = all(shutil.which(tool) for tool in ("tectonic", "pdftotext", "pdfinfo", "pdffonts"))


def guidance():
    with open(SHARED_RULES, encoding="utf-8") as handle:
        return json.load(handle)["printablePages"]["agentGuidance"]


def fold(text):
    return re.sub(r"\s+", " ", text)


def starter_preamble():
    text = (SKILL / "starters" / "Handout.tex").read_text(encoding="utf-8")
    return text[text.index("\\documentclass"):text.index("\n\\begin{document}") + 1]


def run_checker(*arguments):
    return subprocess.run([sys.executable, "-B", str(CHECKER)] + [str(argument) for argument in arguments],
                          capture_output=True, text=True, timeout=120)


def fill_in(text):
    """What a teacher's copy changes: the code and the title."""
    text = text.replace("\\newcommand{\\coursecode}{COURSE}", "\\newcommand{\\coursecode}{MTH1W}")
    text = text.replace("{Handout Title}", "{Graphing Lines}").replace("{Quiz Title}", "{Equations Quiz}")
    return text


def compile_tex(folder, name):
    result = subprocess.run(["tectonic", name], cwd=folder, capture_output=True, text=True, timeout=600)
    return result.returncode, result.stdout + result.stderr


def pdf_text(path):
    return subprocess.run(["pdftotext", "-layout", str(path), "-"], capture_output=True, text=True,
                          timeout=60).stdout


class TheContractNamesWhatShips(unittest.TestCase):

    def test_every_pattern_and_the_checker_ship_and_are_named(self):
        handouts = guidance()["handoutsSkill"]
        skill = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        listed = set(handouts["patterns"])
        on_disk = set()
        for path in (SKILL / "patterns").iterdir():
            if path.is_file():
                on_disk.add("patterns/" + path.name)
        self.assertEqual(listed, on_disk, "patterns lists every file under patterns/, and only those")
        for pattern in handouts["patterns"]:
            self.assertIn("`" + pattern + "`", skill, pattern + " must be named in the skill")
        self.assertTrue((SKILL / handouts["checker"]).is_file())
        self.assertIn("`" + handouts["checker"] + "`", skill)

    def test_every_pinned_macro_is_defined_and_named(self):
        handouts = guidance()["handoutsSkill"]
        skill = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        for starter, macros in handouts["starterMacros"].items():
            source = (SKILL / starter).read_text(encoding="utf-8")
            for macro in macros:
                defined = ("\\newcommand{" + macro + "}") in source or ("\\newlength{" + macro + "}") in source
                self.assertTrue(defined, starter + " must define " + macro)
                self.assertIn("`" + macro, skill, "the skill must name " + macro)

    def test_the_handouts_and_printing_skills_say_what_they_must(self):
        must_say = guidance()["mustSay"]
        for name in ("plantoir-handouts", "plantoir-printing"):
            skill = fold((SKILLS / name / "SKILL.md").read_text(encoding="utf-8"))
            for phrase in must_say[name]:
                self.assertIn(fold(phrase), skill, name + " must say: " + phrase)

    def test_the_rich_patterns_repeat_the_starters_preamble(self):
        preamble = starter_preamble()
        for name in ("worked_examples.tex", "graphs.tex"):
            text = (SKILL / "patterns" / name).read_text(encoding="utf-8")
            self.assertIn(PREAMBLE_START, text, name)
            between = text[text.index(PREAMBLE_START) + len(PREAMBLE_START):text.index(PREAMBLE_END)]
            self.assertEqual(between, preamble, name + " must repeat starters/Handout.tex's preamble line for line")

    def test_no_starter_or_pattern_carries_a_placeholder_school(self):
        for path in list((SKILL / "starters").iterdir()) + list((SKILL / "patterns").iterdir()):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("School Name", text, path.name)


class TheCheckerChecksItself(unittest.TestCase):

    def test_self_test(self):
        result = run_checker("--self-test")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)


@unittest.skipUnless(HAVE_TOOLS, "needs tectonic and Poppler (pdftotext, pdfinfo, pdffonts); skipped")
class EveryStarterAndPatternCompilesAndPasses(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.temporary.name) / "handouts"
        cls.folder.mkdir()
        for source in list((SKILL / "starters").glob("*.tex")) + list((SKILL / "patterns").glob("*.tex")):
            (cls.folder / source.name).write_text(fill_in(source.read_text(encoding="utf-8")), encoding="utf-8")
        for stem in ("worked_examples", "graphs", "tables", "finite_differences"):
            (cls.folder / (stem + " - Answers.tex")).write_text(
                "\\def\\showanswers{}\n\\input{" + stem + ".tex}\n", encoding="utf-8")
        cls.outputs = {}
        for path in sorted(cls.folder.glob("*.tex")):
            code, log = compile_tex(cls.folder, path.name)
            cls.outputs[path.name] = (code, log)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_every_copy_compiles_and_leaves_only_pdfs(self):
        for name, (code, log) in self.outputs.items():
            self.assertEqual(code, 0, name + ":\n" + log[-2000:])
        for entry in self.folder.iterdir():
            self.assertIn(entry.suffix, (".tex", ".pdf"), "left behind: " + entry.name)
        for name in self.outputs:
            self.assertTrue((self.folder / (name[:-4] + ".pdf")).exists(), name)

    def test_letter_paper_in_latin_modern(self):
        for pdf in sorted(self.folder.glob("*.pdf")):
            info = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True).stdout
            self.assertRegex(info, r"Page size:\s+612 x 792", pdf.name)
            fonts = subprocess.run(["pdffonts", str(pdf)], capture_output=True, text=True).stdout
            self.assertIn("LMRoman", fonts, pdf.name)

    def test_the_student_copy_holds_no_answer_and_the_key_holds_them(self):
        questions = pdf_text(self.folder / "Handout.pdf")
        answers = pdf_text(self.folder / "Handout - Answers.pdf")
        for answer in ("goes down by 2", "13.5", "x = 8"):
            self.assertIn(answer, answers.replace("−", "-"), answer)
        for answer in ("goes down by 2", "x = 8"):
            self.assertNotIn(answer, questions.replace("−", "-"), answer)
        self.assertNotIn("use N", questions + answers, "no centred column of negatives in the starter")

    def test_the_hints_sheet_is_the_hints_alone(self):
        hints = pdf_text(self.folder / "Handout - Hints.pdf")
        for number in range(1, 6):
            self.assertIn("Question " + str(number), hints)
        self.assertNotIn("Evaluate each expression", hints)
        self.assertNotIn("Substitute and Evaluate\n", hints.replace("“", "").replace("”", ""))

    def test_the_hints_block_changes_nothing_in_the_other_copies(self):
        source = (self.folder / "Handout.tex").read_text(encoding="utf-8")
        start = source.index("\\ifhints\n{\\LARGE")
        end = source.index("\\end{document}\n\\fi\n", start) + len("\\end{document}\n\\fi\n")
        with tempfile.TemporaryDirectory() as other:
            other_folder = Path(other)
            (other_folder / "Handout.tex").write_text(source[:start] + source[end:], encoding="utf-8")
            (other_folder / "Handout - Answers.tex").write_text(
                "\\def\\showanswers{}\n\\input{Handout.tex}\n", encoding="utf-8")
            for name in ("Handout.tex", "Handout - Answers.tex"):
                code, log = compile_tex(other_folder, name)
                self.assertEqual(code, 0, log[-2000:])
                self.assertEqual(pdf_text(other_folder / (name[:-4] + ".pdf")),
                                 pdf_text(self.folder / (name[:-4] + ".pdf")), name)

    def test_the_checker_finds_nothing_in_any_of_them(self):
        for name in ("Handout.tex", "Quiz.tex", "worked_examples.tex", "graphs.tex", "tables.tex",
                     "finite_differences.tex"):
            result = run_checker(self.folder / name)
            self.assertEqual(result.returncode, 0, name + ":\n" + result.stdout)


BROKEN = [
    # (rule, old, new): one deliberate break of the starter per rule
    ("negative-column", "\\begin{NiceTabular}{N{$3$}N{$5$}}[hvlines]", "\\begin{NiceTabular}{N{$3$}C}[hvlines]"),
    ("mixed-column", "\\begin{NiceTabular}{CN{$18.0$}}[hvlines]", "\\begin{NiceTabular}{CC}[hvlines]"),
    ("decimal-places", "$2$ & \\qa{}{$9.0$} \\\\", "$2$ & \\qa{}{$9$} \\\\"),
    ("table-border", "\\begin{NiceTabular}{N{$3$}N{$5$}}[hvlines]", "\\begin{NiceTabular}{N{$3$}N{$5$}}"),
    ("blank-strut", "\\llap{\\rule[-0.2em]{#1}{0.4pt}}}\\rule[-0.2em]{0pt}{2.1em}}", "\\llap{\\rule[-0.2em]{#1}{0.4pt}}}}"),
    ("key-layout", "\\begin{tikzpicture}\\begin{axis}[gridgraph, x=0.42cm, y=0.42cm,\n    xmin=-4,",
     "\\begin{tikzpicture}\\begin{axis}[gridgraph, x=\\qa{0.42cm}{0.3cm}, y=0.42cm,\n    xmin=-4,"),
    ("key-layout", "\\begin{tasks}(3)\n  \\task \\qa{$3x + y$}", "\\begin{tasks}(\\qa{3}{2})\n  \\task \\qa{$3x + y$}"),
    ("arrowheads", "domain=-1.45:4.45", "domain=-4:6"),
    ("arrowheads", "domain=-1.45:4.45", "domain=0:2"),
    ("context-graph", "\\addplot[lineA, domain=0:4]{4.5*x};", "\\addplot[lineA, <->, >=latex, domain=0:4]{4.5*x};"),
    ("corners", "\\newcommand{\\schoolname}{}", "\\newcommand{\\schoolname}{School Name}"),
    ("hints", "\\end{document}\n\\fi\n", "\\fi\n"),
    ("firearms", "A cyclist starts a ride", "firearms. A cyclist starts a ride"),   # the word alone, no context
]


class EachBreakIsNamed(unittest.TestCase):

    def test_a_broken_copy_of_the_starter_names_its_rule(self):
        starter = fill_in((SKILL / "starters" / "Handout.tex").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "Handout - Answers.tex").write_text("\\def\\showanswers{}\n\\input{Handout.tex}\n", encoding="utf-8")
            (folder / "Handout - Hints.tex").write_text("\\def\\showhints{}\n\\input{Handout.tex}\n", encoding="utf-8")
            (folder / "Handout.tex").write_text(starter, encoding="utf-8")
            clean = run_checker(folder / "Handout.tex")
            self.assertEqual(clean.returncode, 0, clean.stdout)
            for rule, old, new in BROKEN:
                self.assertIn(old, starter, "the break for " + rule + " no longer applies")
                (folder / "Handout.tex").write_text(starter.replace(old, new, 1), encoding="utf-8")
                result = run_checker(folder / "Handout.tex")
                self.assertEqual(result.returncode, 1, rule + ": " + result.stdout)
                self.assertRegex(result.stdout, r"(?m)^" + rule + ":", rule)
            (folder / "Handout.tex").write_text(starter, encoding="utf-8")
            (folder / "Handout.log").write_text("", encoding="utf-8")
            (folder / "Handout-1.png").write_bytes(b"")
            result = run_checker(folder / "Handout.tex")
            self.assertRegex(result.stdout, r"(?m)^build-files:.*Handout\.log")
            self.assertRegex(result.stdout, r"(?m)^build-files:.*Handout-1\.png")

    @unittest.skipUnless(HAVE_TOOLS, "needs tectonic and pdftotext; skipped")
    def test_a_centred_negative_column_prints_use_n_on_the_page(self):
        starter = fill_in((SKILL / "starters" / "Handout.tex").read_text(encoding="utf-8"))
        broken = starter.replace("\\begin{NiceTabular}{N{$3$}N{$3$}}[hvlines]", "\\begin{NiceTabular}{CC}[hvlines]", 1)
        self.assertNotEqual(broken, starter)
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "Handout.tex").write_text(broken, encoding="utf-8")
            code, log = compile_tex(folder, "Handout.tex")
            self.assertEqual(code, 0, log[-2000:])
            self.assertIn("use N", pdf_text(folder / "Handout.pdf"))


if __name__ == "__main__":
    unittest.main()
