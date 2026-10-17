#!/usr/bin/env python3
"""
Self-check quizzes (#563): the folder check's half, against the contract -
contracts/shared-rules.json -> quizCallouts.

Every recognise case (what each quiz on a page is, its place, its line), every
answers.parse case through the mirror, the `plantoir: error:` line, the line
moved into the teacher's own file, the quizzesNotReady finding, the two files
the site reads, and the pages the check reads. The site's own half - the same
cases through quizRules.ts and Quartz - is
scripts/check_quiz_rules_against_the_site.py and verify.sh 6k.

Stdlib only, no frontmatter; Windows' PythonToolchainTests discovers it.

Run with:

    python3 scripts/test_quizzes.py
"""
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import contracts
import figures
import quizzes
import site_health
import toolchain_paths


def rules():
    return contracts.section("shared-rules", "quizCallouts")


def simple(quiz: dict) -> dict:
    """A quiz as the contract writes it."""
    if "problem" in quiz:
        result = {"problem": quiz["problem"]}
        if quiz.get("fill"):
            result["fill"] = quiz["fill"]
        result["line"] = quiz["problemLine"]
        return result
    result = {"kind": quiz["kind"]}
    if quiz["kind"] in ("single", "multiple"):
        result["correct"] = quiz["correct"]
    else:
        result["answers"] = quiz["answers"]
    result["shuffle"] = quiz["shuffle"]
    result["line"] = quiz["line"]
    return result


class QuizContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def test_every_recognise_case(self):
        cases = rules()["recognise"]["cases"]
        self.assertGreaterEqual(len(cases), 27)
        for case in cases:
            with self.subTest(case["name"]):
                found = quizzes.quizzes_on_page(case["markdown"])
                self.assertEqual([simple(quiz) for quiz in found], case["quizzes"])
                if case["untouched"]:
                    self.assertEqual(found, [])

    def test_top_level_quizzes_are_numbered_and_the_others_are_not(self):
        page = ("> [!quiz] One?\n> - [x] a\n> - [ ] b\n\n"
                "- item\n  > [!quiz] In a list.\n  > - [x] a\n\n"
                "> [!quiz] Two?\n> - [ ] a\n> - [x] b\n")
        found = quizzes.quizzes_on_page(page)
        self.assertEqual([quiz["n"] for quiz in found], [1, None, 2])
        self.assertEqual([quiz["nested"] for quiz in found], [None, 1, None])

    def test_the_problems_are_looked_for_in_the_contracts_order(self):
        order = rules()["recognise"]["order"]
        problems = set(rules()["words"]["problems"]) - {"note", "readDifferently", "notAtTopLevel"}
        self.assertEqual(set(order), problems)
        # An unknown setting is found before anything else, and nothing to
        # check only when nothing else is wrong.
        self.assertEqual(order[0], "unknownOption")
        self.assertEqual(order[-1], "nothingToCheck")
        model = {"options": ["wobble"], "boxedLists": 2, "choices": [None], "answers": [[], []], "blanks": 0}
        self.assertEqual(quizzes.verdict(model)["problem"], "unknownOption")
        model["options"] = []
        self.assertEqual(quizzes.verdict(model)["problem"], "twoChoiceLists")
        model["boxedLists"] = 1
        self.assertEqual(quizzes.verdict(model)["problem"], "choiceWithoutBox")
        model["choices"] = [True, False]
        self.assertEqual(quizzes.verdict(model)["problem"], "twoAnswers")
        model["answers"] = [["a"]]
        self.assertEqual(quizzes.verdict(model)["problem"], "choicesAndAnswer")

    def test_every_parse_case(self):
        for case in rules()["answers"]["parse"]["cases"]:
            with self.subTest(case["line"]):
                got = quizzes.parse_answer_line(case["line"])
                expected = case["expect"]
                if "problem" in expected:
                    self.assertEqual(got, {"problem": expected["problem"]})
                    continue
                self.assertIn("alternatives", got)
                self.assertEqual(len(got["alternatives"]), len(expected["alternatives"]))
                for mine, theirs in zip(got["alternatives"], expected["alternatives"]):
                    self.assertEqual(mine["kind"], theirs["kind"])
                    for key in ("value", "tolerance"):
                        if key in theirs:
                            self.assertAlmostEqual(mine[key], theirs[key], places=9)
                    if "text" in theirs:
                        self.assertEqual(mine["text"], theirs["text"])

    def test_numbers_are_what_the_contract_says_and_no_more(self):
        for text, value in (("0.5", 0.5), (".5", 0.5), ("5.", 5.0), ("1/2", 0.5), ("1 / 2", 0.5),
                            ("-0", 0.0), ("−3", -3.0), ("+4", 4.0), ("2/4", 0.5)):
            self.assertAlmostEqual(quizzes.parse_number(text), value, msg=text)
        for text in ("1e3", "0x10", "Infinity", "", "1,5", "1 000", "1 1/2", "½", "1/0", "１２"):
            self.assertIsNone(quizzes.parse_number(text), text)

    def test_the_mirror_never_checks_an_answer(self):
        self.assertFalse(hasattr(quizzes, "accepts"))
        self.assertFalse(hasattr(quizzes, "normalise"))

    def test_a_commented_out_quiz_does_not_move_the_numbers(self):
        page = "> [!quiz] One?\n> - [x] a\n> - [ ] b\n\n%%\n> [!quiz] Hidden\n%%\n\n> [!quiz] Two?\n> - [ ] a\n"
        found = quizzes.quizzes_on_page(page)
        self.assertEqual([quiz["n"] for quiz in found], [1, 2])
        self.assertEqual(found[1]["problem"], "oneChoice")
        self.assertEqual(found[1]["line"], 9, "the line in the page as written, comment included")


class QuizLinesTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        QuizContractTests.setUpClass()

    def test_the_error_line(self):
        words = rules()["words"]["problems"]
        line = quizzes.error_line("Units/Practice", {"n": 3, "problemLine": 41, "problem": "noCorrectChoice"},
                                  words)
        self.assertTrue(line.startswith("plantoir: error: Units/Practice.md: quiz 3, line 41: "))
        self.assertTrue(line.endswith(words["noCorrectChoice"]))
        nested = quizzes.error_line("Units/Practice", {"n": None, "problemLine": 7, "problem": "notAtTopLevel"},
                                    words)
        self.assertTrue(nested.startswith("plantoir: error: Units/Practice.md: line 7: "))
        filled = quizzes.error_line("P", {"n": 1, "problemLine": None, "problem": "blanksAndLines",
                                          "fill": {"blanks": 2, "lines": 1}}, words)
        self.assertEqual(filled, "plantoir: error: P.md: quiz 1: "
                         + words["blanksAndLines"].replace("{blanks}", "2").replace("{lines}", "1"))

    def test_lines_are_moved_into_the_teachers_file(self):
        source = ("---\ntitle: Practice\n---\n\n> [!quiz] Simplify.\n> - [x] a\n> - [ ] b\n\n"
                  "> [!quiz] Simplify.\n> > [!answer]-\n> > a |  | b\n")
        # The build's copy carries extra frontmatter lines and the same quizzes.
        build = "---\ntitle: Practice\ncreated: 2026-10-17\nmodified: 2026-10-17\n---\n" + source[source.index("\n> [!quiz]"):]
        found = quizzes.quizzes_on_page(build)
        placed = quizzes.place_in_source(found, source)
        self.assertEqual([quiz["line"] for quiz in placed], [5, 9])
        # The second shares its title with the first, and its problem keeps
        # its distance from the quiz's first line: the answer line.
        self.assertEqual(placed[1]["problemLine"], 11)

    def test_a_quiz_that_cannot_be_matched_has_no_line(self):
        found = quizzes.quizzes_on_page("> [!quiz] Only in the build.\n> - [x] a\n")
        placed = quizzes.place_in_source(found, "Nothing here.\n")
        self.assertIsNone(placed[0]["line"])
        self.assertIsNone(quizzes.place_in_source(found, None)[0]["line"])


class QuizzesFindingTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        QuizContractTests.setUpClass()

    def entry(self):
        for check in contracts.section("shared-rules", "siteHealth", "checks"):
            if check["name"] == "quizzesNotReady":
                return check
        self.fail("quizzesNotReady is not in the contract")

    def facts(self, problems):
        return {"media_target_exists": True, "section_index_exists": True, "quiz_problems": problems}

    def test_it_is_never_offered_a_repair(self):
        never = contracts.section("shared-rules", "siteHealth", "repair", "neverOffered", "checks")
        self.assertIn("quizzesNotReady", never)
        self.assertFalse(self.entry()["fixable"])

    def test_one_question(self):
        found = site_health.findings(self.facts([
            {"page": "{course} notes", "n": 3, "line": 41, "reason": "noCorrectChoice", "fill": {}}]), "MPM2D", 1)
        self.assertEqual([item.name for item in found], ["quizzesNotReady"])
        entry = self.entry()
        reason = rules()["words"]["problems"]["noCorrectChoice"]
        # A page called "{course} notes" is named as it is (one pass).
        self.assertEqual(found[0].sentence, site_health.filled(
            entry["sentence"], {"page": "{course} notes", "course": "MPM2D", "section": "1"}))
        self.assertIn("“{course} notes”", found[0].sentence)
        self.assertIn("“{course} notes”, question 3, line 41: " + reason, found[0].detail)

    def test_several_with_and_without_lines(self):
        problems = [
            {"page": "A", "n": 1, "line": 5, "reason": "oneChoice", "fill": {}},
            {"page": "B", "n": 2, "line": None, "reason": "blanksAndLines", "fill": {"blanks": 2, "lines": 1}},
            {"page": "C", "n": None, "line": 9, "reason": "notAtTopLevel", "fill": {}},
            {"page": "D", "n": None, "line": None, "reason": "notAtTopLevel", "fill": {}},
        ]
        found = site_health.findings(self.facts(problems), "MPM2D", 1)[0]
        self.assertTrue(found.sentence.startswith("4 "))
        words = rules()["words"]["problems"]
        self.assertIn("“B”, question 2: " + words["blanksAndLines"].replace("{blanks}", "2").replace("{lines}", "1"),
                      found.detail)
        self.assertIn("“C”, line 9: " + words["notAtTopLevel"], found.detail)
        self.assertIn("“D”: " + words["notAtTopLevel"], found.detail)
        self.assertIn("; ", found.detail)

    def test_more_than_ten_are_counted_not_listed(self):
        problems = []
        for number in range(12):
            problems.append({"page": f"P{number}", "n": 1, "line": 1, "reason": "oneChoice", "fill": {}})
        found = site_health.findings(self.facts(problems), "MPM2D", 1)[0]
        self.assertIn("P9", found.detail)
        self.assertNotIn("P10", found.detail)
        self.assertIn(self.entry()["andMore"].replace("{count}", "2"), found.detail)

    def test_no_shown_sentence_names_the_machinery(self):
        banned = ("docker", "container", "toolchain", "script", "pyodide", "webassembly", "worker", "transformer")
        texts = [value for key, value in self.entry().items() if isinstance(value, str) and key not in ("fill", "why")]
        for section in ("site", "problems"):
            for key, value in rules()["words"][section].items():
                if key != "note":
                    texts.append(value)
        for text in texts:
            for word in banned:
                self.assertNotIn(word, text.lower(), text)


class QuizFilesTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        QuizContractTests.setUpClass()

    def setUp(self):
        self.output = Path(tempfile.mkdtemp(prefix="plantoir-quizzes-"))

    def tearDown(self):
        shutil.rmtree(self.output, ignore_errors=True)

    def test_the_words_file_is_the_contracts_and_the_same_bytes_twice(self):
        checked = quizzes.check_pages([], printer=lambda line: None)
        self.assertTrue(quizzes.write_quiz_files(self.output, checked))
        words = json.loads((self.output / "quartz" / quizzes.WORDS_FILE).read_text(encoding="utf-8"))
        expected_site = {key: value for key, value in rules()["words"]["site"].items() if key != "note"}
        self.assertEqual(words["words"], expected_site)
        self.assertEqual(words["problems"]["readDifferently"], rules()["words"]["problems"]["readDifferently"])
        self.assertFalse(quizzes.write_quiz_files(self.output, checked), "same input, same bytes")

    def test_the_pages_file_says_what_was_examined_and_found(self):
        pages = [
            {"place": "Units/Practice", "path": "Units/Practice.md", "source": None,
             "text": "> [!quiz] One?\n> - [x] a\n> - [ ] b\n\n> [!quiz] Two?\n> - [ ] a\n> - [ ] b\n\n"
                     "> [!example]\n> > [!quiz] In a callout.\n> > - [x] a\n"},
            {"place": "Other", "path": "Other.md", "source": None, "text": "> [!note] No quiz.\n"},
        ]
        said = []
        checked = quizzes.check_pages(pages, printer=said.append)
        self.assertEqual(checked["examined"], ["Other.md", "Units/Practice.md"])
        self.assertEqual(checked["pages"], {"Units/Practice.md": {"quizzes": 2, "problems": [2], "nested": 1,
                                                                  "nestedProblems": [1], "lines": [None, None],
                                                                  "nestedLines": [None]}})
        self.assertEqual(len(said), 2)
        self.assertTrue(said[0].startswith("plantoir: error: Units/Practice.md: quiz 2: "))
        self.assertTrue(said[1].startswith("plantoir: error: Units/Practice.md: "))
        self.assertEqual([problem["reason"] for problem in checked["problems"]], ["noCorrectChoice", "notAtTopLevel"])
        quizzes.write_quiz_files(self.output, checked)
        written = json.loads((self.output / "quartz" / quizzes.PAGES_FILE).read_text(encoding="utf-8"))
        self.assertEqual(written["examined"], checked["examined"])

    def test_a_contract_that_cannot_be_read_writes_empty_words(self):
        original = toolchain_paths.CONTRACTS_DIR
        toolchain_paths.CONTRACTS_DIR = Path("/nowhere/at/all")
        contracts.reset_cache()
        try:
            quizzes.write_quiz_files(self.output, None)
        finally:
            toolchain_paths.CONTRACTS_DIR = original
            contracts.reset_cache()
        words = json.loads((self.output / "quartz" / quizzes.WORDS_FILE).read_text(encoding="utf-8"))
        self.assertEqual(words, {"words": {}, "problems": {}})


class PagesStudentsSeeTests(unittest.TestCase):

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-quiz-pages-"))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_must_contain_reads_quiz_pages_and_skips_the_rest(self):
        (self.root / "Units").mkdir()
        (self.root / "Units" / "Quiz.md").write_text("> [!quiz] Q\n", encoding="utf-8")
        (self.root / "Fence.md").write_text("```python\nprint(1)\n```\n", encoding="utf-8")
        (self.root / "Hidden.md").write_text("HIDDEN\n> [!quiz] Q\n", encoding="utf-8")
        (self.root / "Media").mkdir()
        (self.root / "Media" / "Note.md").write_text("> [!quiz] Q\n", encoding="utf-8")

        def read(**extra):
            return figures.pages_students_see(self.root, lambda text: "HIDDEN" in text,
                                              lambda page: page.stem, lambda page: None,
                                              skip=lambda part: part == "Media", **extra)

        quiz_pages = read(must_contain="[!")
        self.assertEqual([page["path"] for page in quiz_pages], ["Units/Quiz.md"])
        self.assertEqual([page["path"] for page in read()], ["Fence.md"], "the default is still the fence test")


if __name__ == "__main__":
    unittest.main(verbosity=2)
