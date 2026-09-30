#!/usr/bin/env python3
"""
The command-line setup asks the apps' course-code rule of a typed code
(GitHub #402).

Until #402, `setup_course.py` refused only a leading dot, so `./setup.sh`
could make "CAFÉ", "C++" or "A;B" — codes neither app can make. It now holds
`CourseCodeRule` whole, and this file is its gate. Nothing here is retyped:

- every `contracts/course-management.json → courseCode.problems` and
  `.normalized` case runs through `course_code_trouble` and
  `normalized_course_code`, BOTH sentences — the same cases the mac's
  CourseManagementContractTests and Windows' ContractTests run;
- every `courseCode.commandLine.cases` entry drives `ask_for_course_code`
  with scripted answers against a scratch courses/ folder, and checks what it
  returned, how often it asked, and what it said;
- the kept-as-it-is note is held against the rule both apps' answer pumps
  apply to a line (it must not read as a question) and against
  `shared-rules.json → userFacingLabelWords.forbidden` (CLAUDE.md rule 1).

Pure Python, no shell, no Docker: verify.sh runs it in step 0 and Windows'
PythonToolchainTests discovers it. JSON is read as UTF-8 explicitly, because
on Windows open() would otherwise use the locale's code page.

Run with:

    python3 scripts/test_course_code_rule.py
"""
import builtins
import contextlib
import io
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import setup_course  # noqa: E402
import toolchain_paths  # noqa: E402

REPOSITORY = Path(__file__).resolve().parent.parent
COURSE_MANAGEMENT_FILE = REPOSITORY / "contracts" / "course-management.json"
SHARED_RULES_FILE = REPOSITORY / "contracts" / "shared-rules.json"

# A prompt loop that asks more than this has stopped accepting anything.
MOST_ASKS = 10

# What both apps' answer pumps take to be a question waiting for an answer
# (mac NewCourseCreator.pumpAnswers, Windows NewCourseCreator.cs): a line
# that ends this way. A note ending like this would be answered as a prompt.
ENDINGS_THAT_READ_AS_A_PROMPT = (":", ": ", ">", "?")

# The non-ASCII characters that upper-case INTO a code the rule accepts.
# Measured for #402 over every code point (0x80–0x10FFFF), in Python and in
# Swift: the same ten on both, because both upper-case BEFORE checking.
# Windows' CourseCodeValidator checks first and refuses them — refusal
# direction, recorded rather than fixed.
NON_ASCII_THAT_UPPER_CASE_INTO_A_CODE = "ßıſﬀﬁﬂﬃﬄﬅﬆ"


def read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def course_code_contract():
    return read_json(COURSE_MANAGEMENT_FILE)["courseCode"]


class TheRuleIsTheContracts(unittest.TestCase):

    def test_every_problem_case_reads_as_the_contract_says(self):
        cases = course_code_contract()["problems"]
        self.assertGreater(len(cases), 0)
        for case in cases:
            with self.subTest(typed=case["typed"], existing=case["existing"]):
                trouble = setup_course.course_code_trouble(
                    case["typed"],
                    existing_codes=case["existing"],
                    current_code=case.get("currentCode"),
                )
                if trouble is None:
                    said, short = None, None
                else:
                    said, short = trouble
                self.assertEqual(said, case["expectProblem"])
                self.assertEqual(short, case["expectShort"])

    def test_every_normalized_case(self):
        for case in course_code_contract()["normalized"]:
            with self.subTest(typed=case["typed"]):
                self.assertEqual(
                    setup_course.normalized_course_code(case["typed"]), case["expect"]
                )

    def test_the_limit_is_the_contracts(self):
        self.assertEqual(
            setup_course.COURSE_CODE_MOST_CHARACTERS,
            course_code_contract()["mostCharacters"],
        )

    def test_exactly_these_ten_non_ascii_characters_upper_case_into_a_code(self):
        # Pins the order (upper-case, THEN check) that makes the Python agree
        # with the mac. Checking first passes every contract case — none holds
        # one of these — and disagrees with the mac at exactly these ten.
        accepted = []
        for code_point in range(0x80, 0x110000):
            if 0xD800 <= code_point <= 0xDFFF:
                continue
            character = chr(code_point)
            # In the MIDDLE, so a character that is only trimmed as
            # whitespace (U+00A0, U+2000…) is not mistaken for one that
            # upper-cases into the rule.
            if setup_course.course_code_trouble("A" + character + "B") is None:
                accepted.append(character)
        self.assertEqual("".join(accepted), NON_ASCII_THAT_UPPER_CASE_INTO_A_CODE)


class TheCommandLineAsks(unittest.TestCase):

    def run_case(self, case, courses):
        typed = case["typed"]
        folder = courses / typed.upper()
        if case["existingCourse"] is True:
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "course_config.json").write_text("{}", encoding="utf-8")
        elif case["existingCourse"] == "folderWithoutSettings":
            folder.mkdir(parents=True, exist_ok=True)

        # A refused code is followed by an ordinary one, so the loop ends.
        answers = [typed, "ICS3U"]
        asked = []
        said = []

        def ask(prompt_text, default_value):
            self.assertEqual(prompt_text, setup_course.COURSE_CODE_PROMPT)
            asked.append(prompt_text)
            if len(asked) > MOST_ASKS:
                raise AssertionError("the course code prompt is looping")
            return answers[min(len(asked), len(answers)) - 1]

        returned = setup_course.ask_for_course_code(courses, ask=ask, say=said.append)
        return returned, asked, said

    def test_every_command_line_case(self):
        cases = course_code_contract()["commandLine"]["cases"]
        self.assertGreater(len(cases), 0)
        for case in cases:
            with self.subTest(typed=case["typed"], existing=case["existingCourse"]):
                with tempfile.TemporaryDirectory() as scratch:
                    returned, asked, said = self.run_case(case, Path(scratch))
                expected_said = []
                if case.get("said") is not None:
                    expected_said = [case["said"]]
                self.assertEqual(said, expected_said)
                if case["expect"] == "refused":
                    self.assertEqual(len(asked), 2, "a refused code is asked for again")
                    self.assertEqual(returned, "ICS3U")
                else:
                    self.assertEqual(case["expect"], "accepted")
                    self.assertEqual(len(asked), 1)
                    self.assertEqual(returned, case["typed"].upper())

    def test_an_absolute_path_is_never_let_through(self):
        # The damaging direction: a path to a folder OUTSIDE courses/ that
        # happens to hold a course_config.json. pathlib would join it as that
        # path, not as a folder under courses/.
        with tempfile.TemporaryDirectory() as outside_folder:
            outside = Path(outside_folder).resolve() / "ELSEWHERE"
            outside.mkdir()
            (outside / "course_config.json").write_text("{}", encoding="utf-8")
            with tempfile.TemporaryDirectory() as scratch:
                answers = [str(outside), "ICS3U"]
                said = []

                def ask(prompt_text, default_value):
                    return answers.pop(0)

                returned = setup_course.ask_for_course_code(
                    Path(scratch), ask=ask, say=said.append
                )
        self.assertEqual(returned, "ICS3U")
        self.assertEqual(said, ["❌ A course code can only use letters, numbers, spaces and dashes."])


class TheNote(unittest.TestCase):

    def every_note(self):
        notes = []
        for sentence in (
            "A course code can’t have two spaces in a row.",
            "A course code can only use letters, numbers, spaces and dashes.",
            "A course code can be at most 12 characters.",
            "WORK is a name Plantoir keeps for its own use. Choose a different course code.",
        ):
            notes.append(setup_course.COURSE_CODE_KEPT_AS_IT_IS.format(code="C++", rule=sentence))
        return notes

    def test_the_note_is_not_a_prompt(self):
        for note in self.every_note():
            for ending in ENDINGS_THAT_READ_AS_A_PROMPT:
                self.assertFalse(note.endswith(ending), note)
            self.assertNotIn("\n", note)

    def test_the_note_names_no_machinery(self):
        forbidden = read_json(SHARED_RULES_FILE)["userFacingLabelWords"]["forbidden"]
        for note in self.every_note():
            words = re.findall(r"[a-z0-9]+", note.lower())
            for word in words:
                self.assertNotIn(word, forbidden, note)


class TheExampleCourseCodes(unittest.TestCase):

    def test_the_example_course_codes_pass_the_rule(self):
        self.assertIsNone(setup_course.course_code_trouble(setup_course.EXAMPLE_COURSE_CODE))
        with tempfile.TemporaryDirectory() as scratch:
            for _ in range(200):
                code = setup_course._generate_alt_example_code(Path(scratch))
                self.assertIsNone(setup_course.course_code_trouble(code), code)
            # The fallback shape, when every random draw collides.
            self.assertIsNone(setup_course.course_code_trouble("EX012O"))


class TheAppsWayIn(unittest.TestCase):
    """New Course the way BOTH apps drive it, end to end through the wizard.

    mac `NewCourseCreator.createCourse` and Windows' `NewCourseCreator.cs`
    write courses/<CODE>/course_config.json FIRST, then run the setup and
    answer every "Enter the course code" prompt with the code and every other
    prompt with Return. If the Python ever refused a code an app had
    accepted, the prompt would come back and the app would send the same code
    until its safety valve — a New Course run that never finishes. So this
    plays that pump against the REAL `setup_course.setup_course`, in-process
    (no terminal, no Docker), and asserts the code is asked for exactly ONCE
    and the course is made. `WORK` is the live case: Windows' rule has no
    WORK yet, so its New Course accepts it, and the wizard must let the course
    through with the note rather than refuse it.
    """

    MOST_PROMPTS = 300

    def create_the_way_an_app_does(self, code):
        temporary = Path(tempfile.mkdtemp(prefix="plantoir-app-course-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        courses = temporary / "courses"
        course = courses / code
        course.mkdir(parents=True)
        # The shape the mac's wizard writes (NewCourseCreatorIntegrationTests'
        # configuration), before the setup starts.
        written_first = {
            "course_code": code,
            "course_name": "App Created Course",
            "locale": "en-US",
            "num_sections": 1,
            "section_numbers": [1],
            "shared_folders": ["Concepts", "Exercises"],
            "per_section_folders": ["All Classes"],
            "prepopulate_example_content": False,
            "color_schemes": {"section1": "quartz-standard"},
        }
        (course / "course_config.json").write_text(
            json.dumps(written_first, indent=2) + "\n", encoding="utf-8"
        )

        code_prompts = [0]
        prompts = [0]

        def pump(prompt=""):
            prompts[0] += 1
            if prompts[0] > self.MOST_PROMPTS:
                raise RuntimeError("the wizard kept asking; an app would never finish")
            if "Enter the course code" in str(prompt):
                code_prompts[0] += 1
                return code
            return ""

        original_courses = toolchain_paths.COURSES_DIR
        original_quartz = toolchain_paths.QUARTZ_DIR
        original_input = builtins.input
        original_getch = setup_course.getch
        output = io.StringIO()
        toolchain_paths.COURSES_DIR = courses
        toolchain_paths.QUARTZ_DIR = temporary / "no-quartz-here"
        builtins.input = pump
        setup_course.getch = lambda: "ENTER"
        try:
            with contextlib.redirect_stdout(output):
                setup_course.setup_course(no_backup=True)
        finally:
            toolchain_paths.COURSES_DIR = original_courses
            toolchain_paths.QUARTZ_DIR = original_quartz
            builtins.input = original_input
            setup_course.getch = original_getch

        written = json.loads((course / "course_config.json").read_text(encoding="utf-8"))
        return code_prompts[0], written, output.getvalue(), course

    def test_an_app_created_course_is_asked_for_its_code_once(self):
        for code in ("ZZT2O", "MTEL-12", "AP CALC", "WORK"):
            with self.subTest(code=code):
                asked, written, said, course = self.create_the_way_an_app_does(code)
                self.assertEqual(asked, 1, f"{code}: the app would answer again and again")
                self.assertEqual(written.get("course_code"), code)
                self.assertTrue((course / "section1").is_dir(), f"{code}: no section was made")
                self.assertNotIn("❌", said, f"{code}: {said}")
                noted = "is kept as it is" in said
                self.assertEqual(noted, code == "WORK", f"{code}: {said}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
