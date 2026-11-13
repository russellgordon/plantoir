#!/usr/bin/env python3
"""
The teacher runs the steps that touch names (#750, piece 750d): scripts/teacher_only.py and the two
launchers of the plantoir-marking skill, "Box the papers" and "Put names on the sheets".

Six trials with outside assistants found one listing the teacher-only folder on its first command, so the
assistant is never told where that folder is: the teacher double-clicks a launcher, which asks for it in its
own window, boxes the papers there, puts them in one file with the four privacy points on its cover, and
moves them to where the assistant reads only when the teacher types yes. This file proves, on invented data
with long invented canary names planted in every place a name could be (a misnamed scan, the mapping
table, a file in Check/ and in Named/) and a marker word in the teacher-only folder's own path:

  - no path to the teacher-only folder is written anywhere the assistant reads (the marking folder and the
    working folder), or printed by either launcher, on any step;
  - no name is printed by either launcher on any path: a yes, a no, a refusal, a crash, a missing tool;
  - no boxed paper is in the marking folder before the yes: the launcher is killed at every step and the
    folder looked at;
  - a launcher never says names are covered, and the cover carries the four privacy points word for word
    from contracts/shared-rules.json -> assessment -> teacherRun;
  - the pinned files carry the SHA-256 the skill names, and a launcher refuses a changed one before it
    runs anything;
  - every typedPathCases, answerCases, boxOptionCases and namesRequestCases case;
  - the skill and the report-comments skill never give the assistant a command holding the teacher-only
    folder, and the set-up records the marking folder only.

The launchers are run as scripts in a pseudo-terminal with their questions answered on standard input
(PLANTOIR_MARKING_NO_OPEN keeps the combined file from opening in a window). The real double-click is NOT
measured here. Needs Poppler, bash and a POSIX pseudo-terminal for the runs, and skips them, saying so,
without; the text cases run everywhere. Windows' PythonToolchainTests discovers this file.
"""
import contextlib
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SKILLS = REPOSITORY / "support" / "agent_guidance" / "skills"
SKILL = SKILLS / "plantoir-marking"
COMMENTS_SKILL = SKILLS / "plantoir-report-comments"
SCRIPTS = SKILL / "scripts"
TEACHER_ONLY = SCRIPTS / "teacher_only.py"
LAUNCHERS = SKILL / "launchers"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
FIXTURES = REPOSITORY / "scripts" / "fixtures" / "marking"
BLANK = FIXTURES / "blank-quiz-letter.pdf"
POPPLER = ("pdftoppm", "pdfinfo", "pdftotext", "pdfunite", "pdfseparate")
MISSING = [tool for tool in POPPLER if shutil.which(tool) is None]
CAN_DRIVE = os.name == "posix" and shutil.which("bash") is not None and not MISSING
DRIVE_SKIP = "needs Poppler, bash and a POSIX pseudo-terminal to run the launchers (" + (", ".join(MISSING) or os.name) + ")"
# Invented, ten letters or more, so none can turn up by chance in a PDF's bytes or a signature (trial review M4).
CANARIES = ("Plimbertonix", "Quarvelloshade", "Zentrovialdine", "Brumhollowick", "Vesperanthique", "Glossomarvetti")
MARKER = "Tomarkerqzxvpathk"
ASSESSMENT = "Unit 1 Test"

# Nothing a test runs may open a file or show a chooser on the screen (750d: tests that called box() in this
# process opened the combined file, because the switch was set only for subprocesses). The switch goes into
# THIS process's environment before anything is imported or run, so every subprocess inherits it too, and the
# module's subprocess is guarded so a real opener fails the test instead of reaching the screen.
os.environ["PLANTOIR_MARKING_NO_OPEN"] = "1"
SCREEN_PROGRAMS = ("open", "osascript", "qlmanage", "powershell", "explorer", "xdg-open")
sys.path.insert(0, str(SCRIPTS))
import teacher_only  # noqa: E402  (the file under test, imported for its pure functions)
sys.path.pop(0)


class GuardedSubprocess:
    """teacher_only's subprocess, refusing any program that would put something on the screen."""

    def __getattr__(self, name):
        return getattr(subprocess, name)

    def run(self, command, *arguments, **options):
        program = os.path.basename(str(command[0])) if isinstance(command, (list, tuple)) and command else ""
        if program in SCREEN_PROGRAMS:
            raise AssertionError("a test reached a real " + program + ": nothing may open on the screen")
        return subprocess.run(command, *arguments, **options)


teacher_only.subprocess = GuardedSubprocess()
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_marking_redact as redact_tests  # noqa: E402  (its invented scans)
sys.path.pop(0)


HERE = Path(__file__).resolve().parent
# Since the third trial a marking folder inside the system's temporary folder is refused at set-up, so every
# invented class is made beside this file, outside it, as a real marking folder is. A checkout that is itself in
# a temporary folder cannot do that: those tests skip, saying so (the third trial's export, under /private/tmp,
# failed one test for this reason).
def in_a_temporary_folder(path):
    """Worked out here, not by the file under test, so a must-fail run of an older teacher_only.py still runs."""
    real = os.path.realpath(str(path))
    for folder in (tempfile.gettempdir(), os.environ.get("TMPDIR", ""), "/tmp", "/private/tmp", "/var/tmp"):
        if folder and os.path.isdir(folder):
            top = os.path.realpath(folder)
            if real == top or real.startswith(top.rstrip(os.sep) + os.sep):
                return True
    return False


CHECKOUT_IN_A_TEMPORARY_FOLDER = in_a_temporary_folder(HERE)
OUTSIDE_SKIP = "this checkout is inside the system's temporary folder, where a marking folder is refused"


def new_root(test):
    """A fresh folder outside the system's temporary folders, removed when the test ends."""
    if CHECKOUT_IN_A_TEMPORARY_FOLDER:
        raise unittest.SkipTest(OUTSIDE_SKIP)
    root = Path(tempfile.mkdtemp(prefix=".teacher-run-", dir=str(HERE)))
    test.addCleanup(shutil.rmtree, root, True)
    return root


@contextlib.contextmanager
def a_root():
    if CHECKOUT_IN_A_TEMPORARY_FOLDER:
        raise unittest.SkipTest(OUTSIDE_SKIP)
    root = tempfile.mkdtemp(prefix=".teacher-run-", dir=str(HERE))
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def contract():
    return json.loads(SHARED_RULES.read_text(encoding="utf-8"))


def teacher_run():
    return contract()["assessment"]["teacherRun"]


def folded(text):
    return re.sub(r"\s+", " ", text).strip()


def files_under(folder):
    found = []
    for top, _folders, files in os.walk(folder):
        for name in files:
            found.append(Path(top) / name)
    return found


def leaks_in(folder, tokens):
    """[(token, path relative to the folder)] for every token in any file's name or bytes under the folder."""
    found = []
    for path in files_under(folder):
        data = path.read_bytes()
        for token in tokens:
            if token.casefold() in str(path.relative_to(folder)).casefold() or token.encode("utf-8") in data:
                found.append((token, str(path.relative_to(folder))))
    return found


class Class:
    """An invented class: a working folder, a marking folder set up as the skill says, and the teacher's own
    teacher-only folder beside it, with canaries planted in every place a name could be."""

    template = None

    @classmethod
    def build_template(cls):
        if cls.template is None:
            cls.template = Path(tempfile.mkdtemp(prefix="teacher-run-scans-"))
            redact_tests.build_scans(BLANK, cls.template, {"upright, answers on every page", "grey and speckled"})
        return cls.template

    def __init__(self, root, skill_folder=SKILL):
        self.root = Path(root)
        self.working = self.root / "Working"
        (self.working / "courses" / "ABC9X" / ".internal" / "marking").mkdir(parents=True)
        (self.working / ".toolchain").mkdir()
        self.marking = self.root / "Marking" / "ABC9X"
        self.teacher_only = self.root / "Marking" / ("ABC9X - Teacher Only " + MARKER)
        self.set_up_by_the_assistant(skill_folder)
        self.teacher_puts_the_scans()

    def set_up_by_the_assistant(self, skill_folder):
        """What the skill's section 4 and 7 have the assistant do: the marking folder only."""
        marking = self.marking
        (marking / "Scripts").mkdir(parents=True)
        (marking / ASSESSMENT).mkdir()
        for name in os.listdir(LAUNCHERS):
            shutil.copyfile(LAUNCHERS / name, marking / name)
            if name.endswith(".command"):
                (marking / name).chmod(stat.S_IRWXU)
        (marking / "Skill folder.txt").write_text(str(skill_folder) + "\n", encoding="utf-8")
        for script in ("redact_scans.py", "make_named_copies.py"):
            shutil.copyfile(SCRIPTS / script, marking / "Scripts" / script)
        (marking / ASSESSMENT / "Box request.json").write_text(json.dumps(
            {"blank": str(BLANK), "script": "Scripts/redact_scans.py", "options": []}), encoding="utf-8")
        pointer = {"folder": str(marking), "syncAccepted": [], "teacherSaid": "beside my other marking",
                   "recorded": "2026-11-13"}
        (self.working / "courses" / "ABC9X" / ".internal" / "marking" / "marking.json").write_text(
            json.dumps(pointer), encoding="utf-8")

    def teacher_puts_the_scans(self):
        teacher_only = self.teacher_only
        section = teacher_only / ASSESSMENT / "Originals" / "Section 1"
        section.mkdir(parents=True)
        for scan in (self.build_template() / "Section 1").iterdir():
            shutil.copyfile(scan, section / scan.name)
        shutil.copyfile(section / "Student A.pdf", section / (CANARIES[0] + " " + CANARIES[1] + ".pdf"))
        (teacher_only / "Name Mapping Table.csv").write_text(
            "section,identifier,name,first name\n"
            f"1,Student A,\"{CANARIES[0]}, {CANARIES[1]}\",{CANARIES[1]}\n"
            f"1,Student B,\"{CANARIES[2]}, {CANARIES[3]}\",{CANARIES[3]}\n", encoding="utf-8")
        (teacher_only / ASSESSMENT / "Check").mkdir()
        (teacher_only / ASSESSMENT / "Check" / (CANARIES[4] + " notes.txt")).write_text(CANARIES[4], encoding="utf-8")
        (teacher_only / ASSESSMENT / "Named").mkdir()
        (teacher_only / ASSESSMENT / "Named" / (CANARIES[5] + " - Feedback.pdf")).write_text(CANARIES[5], encoding="utf-8")

    def leaks(self):
        """Every canary or marker found anywhere the assistant reads."""
        tokens = CANARIES + (MARKER,)
        return leaks_in(self.marking, tokens) + leaks_in(self.working, tokens)

    def boxed_papers_in_the_marking_folder(self):
        found = []
        for path in files_under(self.marking):
            if path.suffix.lower() == ".pdf":
                found.append(str(path.relative_to(self.marking)))
        return found


def teacher(answers, points="yes"):
    """The teacher at a function-level step: yes (or `points`) to the four privacy points whenever they are
    asked about, and each of `answers` in turn to everything else; None (the window closed) when they run out."""
    def ask(prompt):
        if prompt == teacher_only.ASK_POINTS:
            return points
        return answers.pop(0) if answers else None
    return ask


def environment():
    return dict(os.environ, PLANTOIR_MARKING_NO_OPEN="1", PYTHONDONTWRITEBYTECODE="1")


def drive(argv, answers, cwd, kill_when=None, timeout=240, env=None, points="yes"):
    """Run argv in a pseudo-terminal with echo off, answering each (prompt, reply) in turn when its prompt has
    been printed. kill_when: when this text is printed, the whole process group is killed. Returns (what was
    printed, exit status, killed)."""
    import pty
    import select
    import termios
    pid, descriptor = pty.fork()
    if pid == 0:
        try:
            attributes = termios.tcgetattr(0)
            attributes[3] = attributes[3] & ~termios.ECHO
            termios.tcsetattr(0, termios.TCSANOW, attributes)
            os.chdir(str(cwd))
            os.execve(argv[0], argv, env or environment())
        finally:
            os._exit(127)
    printed = b""
    position = 0
    queue = list(answers)
    killed = False
    points_answered = 0
    started = time.time()
    while True:
        if time.time() - started > timeout:
            os.killpg(pid, signal.SIGKILL)
            raise AssertionError("the launcher did not finish in time:\n" + printed.decode("utf-8", "replace"))
        ready, _, _ = select.select([descriptor], [], [], 0.1)
        if ready:
            try:
                data = os.read(descriptor, 65536)
            except OSError:
                data = b""
            if not data:
                break
            printed += data
        text = printed.decode("utf-8", "replace")
        if kill_when is not None and not killed and kill_when in text:
            os.killpg(pid, signal.SIGKILL)
            killed = True
        if points is not None and not killed and text.count(POINTS_PROMPT) > points_answered:
            points_answered += 1
            os.write(descriptor, (points + "\n").encode("utf-8"))
        answered = True
        while answered and queue and not killed:
            answered = False
            for index, (prompt, reply) in enumerate(queue):
                if prompt in text[position:]:
                    # A later prompt can come first (a step that stops early skips the questions before it).
                    position = text.index(prompt, position) + len(prompt)
                    os.write(descriptor, (reply + "\n").encode("utf-8"))
                    del queue[:index + 1]
                    answered = True
                    break
    _pid, status = os.waitpid(pid, 0)
    os.close(descriptor)
    return printed.decode("utf-8", "replace").replace("\r\n", "\n"), status, killed


def box_the_papers(a_class, answers, kill_when=None):
    return drive(["/bin/bash", str(a_class.marking / "Box the papers.command")], answers, a_class.marking, kill_when)


def put_names(a_class, answers, kill_when=None):
    return drive(["/bin/bash", str(a_class.marking / "Put names on the sheets.command")], answers, a_class.marking,
                 kill_when)


FOLDER_PROMPT = "Drag it into this window"
MADE_LIST = "Made while marking.txt"   # contracts: assessment -> teacherRun -> madeList, inside Work
POINTS_PROMPT = "Type yes when you have read these four points"
YES_PROMPT = "Type yes when you have looked through every page"
CLOSE_PROMPT = "Press Return to close this window"


def the_folder(a_class, answer_yes):
    answers = [(FOLDER_PROMPT, str(a_class.teacher_only))]
    if answer_yes is not None:
        answers.append((YES_PROMPT, answer_yes))
    answers.append((CLOSE_PROMPT, ""))
    return answers


@unittest.skipUnless(CAN_DRIVE, DRIVE_SKIP)
class BoxThePapersTests(unittest.TestCase):

    def setUp(self):
        self.root = new_root(self)
        self.a_class = Class(self.root)

    def assertNothingLeaked(self, printed):
        for token in CANARIES + (MARKER,):
            self.assertNotIn(token.casefold(), printed.casefold(), f"{token} was printed:\n{printed}")
        self.assertEqual(self.a_class.leaks(), [], "a name or the teacher-only path reached a folder the assistant reads")
        for claim in (r"\bcovered\b", r"\bremoved\b", r"\bsafe\b", r"names are hidden"):
            self.assertIsNone(re.search(claim, printed.casefold()), f"a launcher must not claim '{claim}'")

    def test_the_papers_reach_the_marking_folder_only_on_yes(self):
        printed, status, _killed = box_the_papers(self.a_class, the_folder(self.a_class, "yes"))
        self.assertEqual(os.waitstatus_to_exitcode(status), 0, printed)
        self.assertIn("Moved the 2 papers into 'Unit 1 Test/Redacted'", printed)
        self.assertIn("1 files or folders not named like an identifier were left alone", printed)
        self.assertNothingLeaked(printed)
        redacted = self.a_class.marking / ASSESSMENT / "Redacted"
        self.assertEqual(sorted(path.name for path in redacted.rglob("*.pdf")), ["Student A.pdf", "Student B.pdf"])
        record = json.loads((self.a_class.marking / ASSESSMENT / "Teacher looked.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted(record), ["looked", "papers"], "identifiers, SHA-256 and the date, never a path")
        verified = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--verify", str(self.a_class.marking / ASSESSMENT)],
                                  capture_output=True, text=True)
        self.assertEqual(verified.returncode, 0, verified.stdout)
        self.assertIn("read only these: Section 1/Student A; Section 1/Student B.", verified.stdout)
        said = (self.a_class.marking / ASSESSMENT / "Box the papers - what it said.txt").read_text(encoding="utf-8")
        self.assertIn("The teacher typed yes", said)
        self.assertTrue((self.a_class.teacher_only / ASSESSMENT / "Check" / teacher_only.COMBINED).is_file())
        self.assertFalse((self.a_class.teacher_only / ASSESSMENT / "Holding").exists(), "the holding folder is emptied")

    def test_a_no_moves_nothing(self):
        printed, _status, _killed = box_the_papers(self.a_class, the_folder(self.a_class, "no"))
        self.assertIn("Nothing was moved", printed)
        self.assertNothingLeaked(printed)
        self.assertEqual(self.a_class.boxed_papers_in_the_marking_folder(), [])
        self.assertFalse((self.a_class.marking / ASSESSMENT / "Teacher looked.json").exists())
        verified = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--verify", str(self.a_class.marking / ASSESSMENT)],
                                  capture_output=True, text=True)
        self.assertEqual(verified.returncode, 1)

    def test_killed_at_every_step_no_boxed_paper_is_in_the_marking_folder(self):
        # At the folder question, while the papers are boxed, while the combined file is made and at the yes.
        for kill_when in (FOLDER_PROMPT, "Boxing the papers", "papers written", YES_PROMPT):
            a_class = Class(self.root / ("kill " + str(abs(hash(kill_when)))))
            printed, _status, killed = box_the_papers(a_class, the_folder(a_class, None), kill_when=kill_when)
            self.assertTrue(killed, f"never reached '{kill_when}':\n{printed}")
            self.assertEqual(a_class.boxed_papers_in_the_marking_folder(), [], f"killed at '{kill_when}'")
            self.assertFalse((a_class.marking / ASSESSMENT / "Teacher looked.json").exists())
            self.assertEqual(a_class.leaks(), [], f"killed at '{kill_when}'")

    def test_the_teacher_is_asked_again_for_anything_but_yes_or_no(self):
        printed, _status, _killed = box_the_papers(self.a_class, [
            (FOLDER_PROMPT, str(self.a_class.teacher_only)), (YES_PROMPT, "y"), ("Please type yes or no", "yes"),
            (CLOSE_PROMPT, "")])
        self.assertIn("Moved the 2 papers", printed)

    def test_a_folder_dragged_in_is_read_as_the_terminal_writes_it(self):
        dragged = str(self.a_class.teacher_only).replace(" ", "\\ ") + " "
        printed, _status, _killed = box_the_papers(self.a_class, [
            (FOLDER_PROMPT, dragged), (YES_PROMPT, "yes"), (CLOSE_PROMPT, "")])
        self.assertIn("Moved the 2 papers", printed)
        self.assertNothingLeaked(printed)

    def test_a_path_an_adapted_script_prints_is_never_passed_on(self):
        # An adapted boxing script may well print the folders it was given; the teacher-only one is put back as
        # "your teacher-only folder" in every line the launcher prints and in what it writes for the assistant.
        script = self.a_class.marking / "Scripts" / "redact_scans.py"
        source = script.read_text(encoding="utf-8")
        script.write_text(source.replace('if __name__ == "__main__":',
                                         'if __name__ == "__main__":\n    print("Boxing from " + " ".join(sys.argv[1:3]))', 1),
                          encoding="utf-8")
        printed, _status, _killed = box_the_papers(self.a_class, the_folder(self.a_class, "yes"))
        self.assertIn("Boxing from your teacher-only folder/Unit 1 Test/Originals", printed)
        self.assertNothingLeaked(printed)

    def test_a_refusal_prints_no_name_and_no_path(self):
        os.remove(self.a_class.teacher_only / "Name Mapping Table.csv")
        printed, _status, _killed = box_the_papers(self.a_class, [(FOLDER_PROMPT, str(self.a_class.teacher_only)),
                                                                  (CLOSE_PROMPT, "")])
        self.assertIn("Stopped: your teacher-only folder has no 'Name Mapping Table.csv'", printed)
        self.assertNothingLeaked(printed)
        inside = self.a_class.marking / "Teacher Only"
        inside.mkdir()
        (inside / "Name Mapping Table.csv").write_text("section,identifier,name\n", encoding="utf-8")
        printed, _status, _killed = box_the_papers(self.a_class, [(FOLDER_PROMPT, str(inside)), (CLOSE_PROMPT, "")])
        self.assertIn("must be beside the marking folder, not inside it", printed)
        self.assertEqual(self.a_class.boxed_papers_in_the_marking_folder(), [])

    def test_a_crash_prints_no_name_and_no_path(self):
        check = self.a_class.teacher_only / ASSESSMENT / "Check"
        shutil.rmtree(check)
        check.write_text("not a folder", encoding="utf-8")
        printed, _status, _killed = box_the_papers(self.a_class, the_folder(self.a_class, None))
        self.assertIn("Stopped: something unexpected went wrong", printed)
        self.assertNotIn("Traceback", printed)
        self.assertNothingLeaked(printed)
        self.assertEqual(self.a_class.boxed_papers_in_the_marking_folder(), [])

    def test_a_missing_tool_prints_no_name_and_moves_nothing(self):
        # Run past the launcher, so the PATH it adds Homebrew to does not bring Poppler back.
        bare = self.root / "bin"
        bare.mkdir()
        os.symlink(sys.executable, bare / "python3")
        env = dict(environment(), PATH=str(bare) + os.pathsep + "/usr/bin:/bin")
        printed, _status, _killed = drive([sys.executable, "-I", "-B", str(TEACHER_ONLY), "box", str(self.a_class.marking)],
                                          [(FOLDER_PROMPT, str(self.a_class.teacher_only))], self.a_class.marking, env=env)
        self.assertIn("Poppler is not installed", printed)
        self.assertNothingLeaked(printed)
        self.assertEqual(self.a_class.boxed_papers_in_the_marking_folder(), [])

    def test_a_plain_pipe_is_stopped(self):
        # What this proves and no more: input piped in (not a terminal) stops before anything is asked. It
        # catches an accidental pipe. It does NOT stop an assistant that runs a launcher through a
        # pseudo-terminal (this file's own drive() does exactly that); the skill forbids it, and the re-trial
        # checks for it (750d review H1). Each layer stops on its own.
        for command, refusal in ((["/bin/bash", str(self.a_class.marking / "Box the papers.command")],
                                  "Stopped: Box the papers is for the teacher to double-click"),
                                 (["/bin/bash", str(self.a_class.marking / "Put names on the sheets.command")],
                                  "Stopped: Put names on the sheets is for the teacher to double-click"),
                                 ([sys.executable, "-I", "-B", str(TEACHER_ONLY), "box", str(self.a_class.marking)],
                                  "Stopped: this step is for the teacher to run by double-clicking it")):
            result = subprocess.run(command, input=str(self.a_class.teacher_only) + "\nyes\n", capture_output=True,
                                    text=True, cwd=str(self.a_class.marking), env=environment())
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn(refusal, result.stdout)
            self.assertNotIn("Drag it", result.stdout)
        self.assertEqual(self.a_class.boxed_papers_in_the_marking_folder(), [])

    def test_a_changed_script_is_refused_before_anything_runs(self):
        for changed in ("teacher_only.py", "run_with_names.py"):
            copy = self.root / ("skill " + changed)
            shutil.copytree(SKILL, copy)
            with open(copy / "scripts" / changed, "a", encoding="utf-8") as handle:
                handle.write("\n# a well-meant change\n")
            (self.a_class.marking / "Skill folder.txt").write_text(str(copy) + "\n", encoding="utf-8")
            printed, _status, _killed = box_the_papers(self.a_class, the_folder(self.a_class, "yes"))
            self.assertIn("are not the ones Plantoir shipped, so nothing was run", printed, changed)
            self.assertNotIn("Drag it", printed, changed)
            self.assertEqual(self.a_class.boxed_papers_in_the_marking_folder(), [], changed)

    def test_the_cover_carries_the_four_privacy_points_word_for_word(self):
        box_the_papers(self.a_class, the_folder(self.a_class, "no"))
        combined = self.a_class.teacher_only / ASSESSMENT / "Check" / teacher_only.COMBINED
        text = folded(subprocess.run(["pdftotext", str(combined), "-"], capture_output=True, text=True).stdout)
        rules = teacher_run()
        self.assertIn(folded(rules["privacyHeading"]), text)
        for number, point in enumerate(rules["privacyPoints"], start=1):
            self.assertIn(folded(f"{number}. {point}"), text, f"point {number}")
        self.assertIn("does not prove who looked", text)
        first_paper = text.index("Section 1/Student A")
        self.assertLess(text.index(folded(rules["privacyPoints"][3])), first_paper, "the points come first")

    def test_the_combined_file_is_exactly_the_boxed_papers(self):
        box_the_papers(self.a_class, the_folder(self.a_class, "yes"))
        combined = self.a_class.teacher_only / ASSESSMENT / "Check" / teacher_only.COMBINED
        redacted = sorted((self.a_class.marking / ASSESSMENT / "Redacted").rglob("*.pdf"))
        cover_pages = redact_tests.page_count(combined) - sum(redact_tests.page_count(path) for path in redacted) - len(redacted)
        self.assertIn(cover_pages, (1, 2), "a cover, then a page naming each paper, then the paper")
        text = subprocess.run(["pdftotext", str(combined), "-"], capture_output=True, text=True).stdout
        self.assertLess(text.index("Section 1/Student A"), text.index("Section 1/Student B"))


@unittest.skipUnless(CAN_DRIVE, DRIVE_SKIP)
class PutNamesTests(unittest.TestCase):

    def setUp(self):
        self.root = new_root(self)
        self.a_class = Class(self.root)

    def request(self, request):
        (self.a_class.marking / "Names request.json").write_text(json.dumps(request), encoding="utf-8")

    def said(self):
        return (self.a_class.marking / "Put names on the sheets - what it said.txt").read_text(encoding="utf-8")

    def test_the_table_check_and_the_comment_facts_reach_the_assistant_as_counts(self):
        self.request({"do": "check-table"})
        printed, _status, _killed = put_names(self.a_class, [(FOLDER_PROMPT, str(self.a_class.teacher_only)), (CLOSE_PROMPT, "")])
        self.assertIn("Asked: check-table", self.said())
        (self.a_class.marking / "Term 1 Comments").mkdir()
        notes = self.a_class.teacher_only / "Term 1 Comments" / "Teacher Notes.md"
        notes.parent.mkdir()
        notes.write_text("Student A: steady work.\nStudent B: " + CANARIES[3] + " led the group.\n", encoding="utf-8")
        self.request({"do": "comment-facts", "term": "Term 1"})
        more, _status, _killed = put_names(self.a_class, [(FOLDER_PROMPT, str(self.a_class.teacher_only)), (CLOSE_PROMPT, "")])
        said = self.said()
        self.assertRegex(said, r"\b14\b", "the longest first name, as a number: " + said)
        self.assertIn("(line 2)", said)
        self.assertFalse((self.a_class.marking / "Term 1 Comments" / teacher_only.CHECKED_NOTES).exists(),
                         "notes holding a word from the table are not given to the assistant")
        for text in (printed, more):
            for token in (MARKER,) + CANARIES:
                self.assertNotIn(token.casefold(), text.casefold())
        self.assertEqual(self.a_class.leaks(), [])

    def test_every_notes_release_case(self):
        # 750d second trial: an assistant read the notes in the same command that looked for the check's result.
        # Now the notes are kept in the teacher-only folder, and the marking folder gets only a checked copy.
        (self.a_class.marking / "Term 1 Comments").mkdir()
        checked = self.a_class.marking / "Term 1 Comments" / teacher_only.CHECKED_NOTES
        for case in teacher_run()["notesReleaseCases"]:
            folder = self.a_class.teacher_only / "Term 1 Comments"
            folder.mkdir(exist_ok=True)
            source = (self.a_class.marking if case.get("notesIn") == "marking" else self.a_class.teacher_only) / \
                "Term 1 Comments" / "Teacher Notes.md"
            for old in (folder / "Teacher Notes.md", self.a_class.marking / "Term 1 Comments" / "Teacher Notes.md"):
                if old.exists():
                    os.remove(old)
            if case.get("notes") is not None:
                source.write_text(case["notes"].replace("{name}", CANARIES[3]), encoding="utf-8")
            self.request({"do": "comment-facts", "term": "Term 1"})
            printed, _status, _killed = put_names(self.a_class, [(FOLDER_PROMPT, str(self.a_class.teacher_only)),
                                                                 (CLOSE_PROMPT, "")])
            self.assertEqual(checked.exists(), case["released"], f"{case}:\n{printed}")
            if case["released"]:
                first = checked.read_text(encoding="utf-8").splitlines()[0]
                self.assertTrue(first.startswith(teacher_only.CHECKED_MARK), first)
                self.assertIn(hashlib.sha256(source.read_bytes()).hexdigest(), first, "the record carries the notes' hash")
            if case.get("refused"):
                self.assertIn("Stopped: your notes are in", printed)
            for line in case.get("lines", []):
                self.assertIn(f"(line {line})", printed)
            self.assertNotIn(CANARIES[3].casefold(), printed.casefold())
            if case.get("notesIn") == "marking":
                os.remove(source)

    @unittest.skipIf(shutil.which("tectonic") is None, "tectonic not found; the named sheets compile")
    def test_the_named_sheets_go_to_the_teacher_only_folder_on_yes_only(self):
        sheets = self.a_class.marking / ASSESSMENT / "Sheets" / "Section 1"
        sheets.mkdir(parents=True)
        for identifier in ("Student A", "Student B"):
            (sheets / (identifier + " - Feedback.tex")).write_text(
                "\\documentclass{article}\\newcommand{\\studentline}[1]{#1}\\begin{document}\\studentline{"
                + identifier + "}\\end{document}\n", encoding="utf-8")
        self.request({"do": "sheets", "assessment": ASSESSMENT})
        printed, _status, _killed = put_names(self.a_class, [(FOLDER_PROMPT, str(self.a_class.teacher_only)),
                                                             ("Type yes to go ahead", "no"), (CLOSE_PROMPT, "")])
        self.assertIn("Nothing was done", printed)
        named = self.a_class.teacher_only / ASSESSMENT / "Named" / "Section 1"
        self.assertFalse(named.exists())
        printed, _status, _killed = put_names(self.a_class, [(FOLDER_PROMPT, str(self.a_class.teacher_only)),
                                                             ("Type yes to go ahead", "yes"), (CLOSE_PROMPT, "")])
        self.assertEqual(len(list(named.glob("*.pdf"))), 2, printed)
        for token in CANARIES + (MARKER,):
            self.assertNotIn(token.casefold(), printed.casefold())
        self.assertEqual(self.a_class.leaks(), [])


class ContractCaseTests(unittest.TestCase):

    def test_every_typed_path_case(self):
        for case in teacher_run()["typedPathCases"]:
            self.assertEqual(teacher_only.typed_path(case["typed"], windows=case["windows"]), case["folder"], case)

    def test_every_box_option_case(self):
        for case in teacher_run()["boxOptionCases"]:
            if case["accepted"]:
                self.assertEqual(teacher_only.box_options(case["options"]), case["options"])
            else:
                with self.assertRaises(teacher_only.Refusal, msg=str(case)):
                    teacher_only.box_options(case["options"])

    def test_every_names_request_case(self):
        with a_root() as root:
            marking = Path(root) / "Marking"
            (marking / ASSESSMENT / "Results").mkdir(parents=True)
            (marking / ASSESSMENT / "Results" / "Class Results.tex").write_text("", encoding="utf-8")
            (marking / "Term 1 Comments").mkdir()
            for case in teacher_run()["namesRequestCases"]:
                if case["accepted"]:
                    _what, writes, steps = teacher_only.names_steps(case["request"], marking, Path(root) / "TO")
                    self.assertEqual(writes, case["writesNames"], case)
                    for arguments in steps:
                        self.assertIn("--table", arguments)
                else:
                    with self.assertRaises(teacher_only.Refusal, msg=str(case)):
                        teacher_only.names_steps(case["request"], marking, Path(root) / "TO")

    @unittest.skipIf(MISSING, "Poppler is not installed here; the answer cases box papers")
    def test_every_answer_case(self):
        template = Class.build_template()
        for case in teacher_run()["answerCases"]:
            with a_root() as root:
                a_class = Class(root)
                answers = [str(a_class.teacher_only)] + list(case["answers"])

                ask = teacher(answers)

                printed = []
                try:
                    teacher_only.box(a_class.marking, ask, printed.append)
                except teacher_only.Refusal as refusal:
                    printed.append(str(refusal))
                moved = (a_class.marking / ASSESSMENT / "Redacted").exists()
                self.assertEqual(moved, case["moved"], f"{case}:\n" + "\n".join(printed))
                self.assertEqual(a_class.leaks(), [], case)
        self.assertTrue(template.exists())

    def test_the_privacy_points_are_the_skills_and_the_scripts_word_for_word(self):
        rules = teacher_run()
        self.assertEqual(rules["privacyHeading"], teacher_only.PRIVACY_HEADING)
        self.assertEqual(rules["privacyPoints"], teacher_only.PRIVACY_POINTS)
        skill = folded((SKILL / "SKILL.md").read_text(encoding="utf-8"))
        self.assertIn(folded(rules["privacyHeading"]), skill)
        for number, point in enumerate(rules["privacyPoints"], start=1):
            self.assertIn(folded(f"{number}. {point}"), skill, f"point {number}")


@unittest.skipIf(MISSING, "Poppler is not installed here; the record cases box papers")
class VerifyTests(unittest.TestCase):

    def test_the_check_refuses_anything_but_exactly_what_the_teacher_said_yes_to(self):
        with a_root() as root:
            a_class = Class(root)
            answers = [str(a_class.teacher_only), "yes"]
            teacher_only.box(a_class.marking, teacher(answers), lambda _line: None)
            assessment = a_class.marking / ASSESSMENT

            def check():
                return subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--verify", str(assessment)],
                                      capture_output=True, text=True).returncode

            self.assertEqual(check(), 0)
            paper = assessment / "Redacted" / "Section 1" / "Student A.pdf"
            original = paper.read_bytes()
            paper.write_bytes(original + b"\n")
            self.assertEqual(check(), 1, "a changed paper")
            paper.write_bytes(original)
            planted = assessment / "Redacted" / "Section 1" / "Student Q.png"
            planted.write_bytes(original)
            self.assertEqual(check(), 1, "an added file of any kind")
            os.remove(planted)
            self.assertEqual(check(), 0)
            os.remove(assessment / "Teacher looked.json")
            self.assertEqual(check(), 1, "no record")

    def test_a_whole_class_in_one_scan_is_split_then_named_then_boxed(self):
        # Box request.json's wholeClass: the first double-click splits the stack and asks for the paper column;
        # the next names the papers from the table, through the runner, and boxes them.
        with a_root() as root:
            a_class = Class(root)
            originals = a_class.teacher_only / ASSESSMENT / "Originals"
            shutil.rmtree(originals)
            pages = []
            for _paper in range(2):
                pages += [redact_tests.render(BLANK, 1), redact_tests.render(BLANK, 2)]
            redact_tests.write_image_pdf(a_class.teacher_only / ASSESSMENT / "Whole class.pdf", pages)
            originals.mkdir()
            request = a_class.marking / ASSESSMENT / "Box request.json"
            request.write_text(json.dumps({"blank": str(BLANK), "script": "Scripts/redact_scans.py", "options": [],
                                           "wholeClass": {"file": "Whole class.pdf", "pagesPerPaper": 2, "section": 1}}),
                               encoding="utf-8")
            said = []
            answers = [str(a_class.teacher_only)]
            self.assertEqual(teacher_only.box(a_class.marking, teacher(answers),
                                              said.append), 1)
            self.assertIn("Fill in the paper column", "\n".join(said))
            self.assertTrue((a_class.teacher_only / ASSESSMENT / "Check" / "Papers to name.pdf").is_file())
            table = a_class.teacher_only / "Name Mapping Table.csv"
            table.write_text(table.read_text(encoding="utf-8").replace("first name\n", "first name,paper\n", 1)
                             .replace(f"{CANARIES[1]}\n", f"{CANARIES[1]},2\n").replace(f"{CANARIES[3]}\n", f"{CANARIES[3]},1\n"),
                             encoding="utf-8")
            said = []
            answers = [str(a_class.teacher_only), "yes"]
            self.assertEqual(teacher_only.box(a_class.marking, teacher(answers),
                                              said.append), 0, "\n".join(said))
            redacted = a_class.marking / ASSESSMENT / "Redacted" / "Section 1"
            self.assertEqual(sorted(path.name for path in redacted.iterdir()), ["Student A.pdf", "Student B.pdf"])
            for token in CANARIES + (MARKER,):
                self.assertNotIn(token.casefold(), "\n".join(said).casefold())
            self.assertEqual(a_class.leaks(), [])

    def test_anything_in_the_holding_folder_but_a_boxed_paper_is_refused(self):
        with a_root() as root:
            holding = Path(root) / "Holding" / "Section 1"
            holding.mkdir(parents=True)
            shutil.copyfile(BLANK, holding / "Student A.pdf")
            for planted in ("Student B.png", CANARIES[0] + ".pdf", "Student C.PDF"):
                shutil.copyfile(BLANK, holding / planted)
                with self.assertRaises(teacher_only.Refusal) as raised:
                    teacher_only.prepare(Path(root) / "Holding", Path(root) / "Check", ASSESSMENT)
                self.assertNotIn(CANARIES[0], str(raised.exception))
                os.remove(holding / planted)
            os.symlink(BLANK, holding / "Student D.pdf")
            with self.assertRaises(teacher_only.Refusal):
                teacher_only.prepare(Path(root) / "Holding", Path(root) / "Check", ASSESSMENT)


class NothingOnTheScreenTests(unittest.TestCase):

    def test_no_test_can_reach_a_real_opener_or_chooser(self):
        self.assertEqual(os.environ.get(teacher_only.NO_OPEN), "1", "the switch is set for this process")
        self.assertEqual(environment().get(teacher_only.NO_OPEN), "1", "and for every subprocess")
        self.assertIsNone(teacher_only.open_for_the_teacher(TEACHER_ONLY))
        self.assertIsNone(teacher_only.chosen_in_a_window())
        with self.assertRaises(AssertionError):
            teacher_only.subprocess.run(["open", str(TEACHER_ONLY)])

    def test_every_opener_is_behind_the_switch(self):
        # Each place teacher_only.py could put something on the screen reads the switch first.
        source = TEACHER_ONLY.read_text(encoding="utf-8")
        for function in ("def open_for_the_teacher", "def chosen_in_a_window"):
            body = source[source.index(function):].split("\ndef ", 1)[0]
            self.assertIn("os.environ.get(NO_OPEN)", body.split("try:", 1)[0], function)
        for program in ('"open"', '"osascript"', "startfile", '"powershell"'):
            for line_number, line in enumerate(source.splitlines(), start=1):
                if program in line and not line.lstrip().startswith("#"):
                    enclosing = source[:source.index(line)].rsplit("\ndef ", 1)[1].split("(")[0]
                    self.assertIn(enclosing, ("open_for_the_teacher", "chosen_in_a_window"), f"line {line_number}")


class PinTests(unittest.TestCase):

    def test_the_skill_names_the_sha256_of_every_pinned_file(self):
        skill = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        for relative in teacher_run()["pinned"]:
            digest = hashlib.sha256((SKILL / relative).read_bytes()).hexdigest()
            self.assertIn(f"`{digest}`  {Path(relative).name}", skill, f"{relative} must be pinned as {digest}")

    def test_each_launcher_checks_the_two_scripts_it_runs(self):
        teacher = hashlib.sha256(TEACHER_ONLY.read_bytes()).hexdigest()
        runner = hashlib.sha256((SCRIPTS / "run_with_names.py").read_bytes()).hexdigest()
        checks = set()
        for name in teacher_run()["launchers"]:
            text = (LAUNCHERS / name).read_bytes().decode("utf-8")
            self.assertIn(f'TEACHER_ONLY_SHA256={teacher}', text.replace('"', ""), f"{name}: teacher_only.py is {teacher}")
            self.assertIn(f'RUNNER_SHA256={runner}', text.replace('"', ""), f"{name}: run_with_names.py is {runner}")
            self.assertIn("-I -B", text)
            self.assertIn("teacher_only.py", text)
            step = "box" if name.startswith("Box") else "names"
            self.assertIn(f'STEP={step}', text.replace('"', ""), name)
            check = re.search(r'CHECK="([^"]+)"', text) or re.search(r'-c "([^"]+)"', text)
            checks.add(check.group(1))
            self.assertNotIn("%", check.group(1).replace("%PYTHON%", ""), "a % in the .bat's -c would be eaten by cmd")
        self.assertEqual(len(checks), 1, "every launcher runs the same check")

    def test_line_endings_hold_the_pins_on_every_checkout(self):
        for name in teacher_run()["launchers"]:
            data = (LAUNCHERS / name).read_bytes()
            if name.endswith(".bat"):
                self.assertEqual(data.count(b"\n"), data.count(b"\r\n"), f"{name}: cmd reads CRLF")
            else:
                self.assertNotIn(b"\r", data, name)
        self.assertNotIn(b"\r", TEACHER_ONLY.read_bytes())
        self.assertNotIn(b"\r", (SCRIPTS / "render_pages.py").read_bytes())
        attributes = (REPOSITORY / ".gitattributes").read_text(encoding="utf-8")
        self.assertIn("support/agent_guidance/skills/plantoir-marking/scripts/teacher_only.py text eol=lf", attributes)
        self.assertIn("support/agent_guidance/skills/plantoir-marking/scripts/render_pages.py text eol=lf", attributes)
        self.assertIn("support/agent_guidance/skills/plantoir-marking/launchers/*.command text eol=lf", attributes)
        self.assertIn("support/agent_guidance/skills/plantoir-marking/launchers/*.bat text eol=crlf", attributes)


class PathAndStrayWriteTests(unittest.TestCase):

    def test_every_hide_path_case(self):
        with a_root() as root:
            a_class = Class(root)
            teacher = a_class.teacher_only
            forms = {"full": str(teacher), "relative": os.path.relpath(str(teacher), str(a_class.marking)),
                     "uri": Path(os.path.realpath(str(teacher))).as_uri()[len("file://"):], "name": teacher.name}
            for case in teacher_run()["hidePathCases"]:
                printed = case["printed"]
                for key, value in forms.items():
                    printed = printed.replace("{" + key + "}", value)
                if "{uri}" in case["printed"]:
                    printed = "file://" + printed.split("file://", 1)[-1] if "file://" in printed else printed.replace(
                        "Open ", "Open file://", 1)
                shown = teacher_only.hide_the_folder(printed, teacher)
                self.assertEqual(shown, case["shows"], case["why"])
                self.assertNotIn(MARKER, shown)

    @unittest.skipIf(MISSING, "Poppler is not installed here; the boxing runs")
    def test_every_stray_write_case(self):
        writes = {
            "nowhere": "",
            "marking": "open(os.path.join(os.getcwd(), 'redact.log'), 'w').write(' '.join(sys.argv))",
            "marking-cache": "shutil.copytree(sys.argv[1], os.path.join(os.getcwd(), 'Unit 1 Test', 'cache'))",
            "teacher-only": "shutil.copytree(sys.argv[1], os.path.join(os.path.dirname(sys.argv[2]), 'cache'))",
            "outside": "open(os.path.join(OUTSIDE, 'copy.txt'), 'w').write(sys.argv[1])",
        }
        # Outside both folders AND outside the temporary folder the wall allows: a folder in this checkout.
        outside = Path(tempfile.mkdtemp(prefix=".teacher-run-outside-", dir=str(Path(__file__).resolve().parent)))
        self.addCleanup(shutil.rmtree, outside, True)
        walled = sys.platform == "darwin" and os.path.isfile("/usr/bin/sandbox-exec")
        for case in teacher_run()["strayWriteCases"]:
            if case.get("platform") == "mac" and not walled:
                continue
            # With the Mac's wall, and (except where only the wall can see it) without it, so the snapshot is
            # proved on its own, as it runs on Windows.
            for wall in ([True, False] if case.get("platform") != "mac" else [True]):
                with a_root() as root:
                    a_class = Class(root)
                    script = a_class.marking / "Scripts" / "redact_scans.py"
                    if writes[case["writes"]]:
                        script.write_text(script.read_text(encoding="utf-8").replace(
                            'if __name__ == "__main__":', 'if __name__ == "__main__" and len(sys.argv) > 3 and not '
                            'sys.argv[1].startswith("--"):\n    OUTSIDE = ' + repr(str(outside)) + '\n    '
                            + writes[case["writes"]] + '\nif __name__ == "__main__":', 1),
                            encoding="utf-8")
                    original = getattr(teacher_only, "walled", None)
                    if not wall and original is not None:
                        teacher_only.walled = lambda command, writable: command
                    printed = []
                    answers = [str(a_class.teacher_only), "yes"]
                    try:
                        teacher_only.box(a_class.marking, teacher(answers), printed.append)
                        stopped = False
                    except teacher_only.Refusal as refusal:
                        printed.append(str(refusal))
                        stopped = True
                    finally:
                        if original is not None:
                            teacher_only.walled = original
                    label = f"{case['name']} (wall {wall})"
                    self.assertEqual(stopped, case["stopped"], label + ":\n" + "\n".join(printed))
                    self.assertEqual((a_class.marking / ASSESSMENT / "Redacted").exists(), not case["stopped"], label)
                    self.assertEqual(a_class.boxed_papers_in_the_marking_folder() if case["stopped"] else [], [], label)
                    self.assertFalse((a_class.marking / "redact.log").exists(), label)
                    self.assertFalse((a_class.marking / ASSESSMENT / "cache").exists(), label)
                    self.assertFalse((a_class.teacher_only / ASSESSMENT / "cache").exists(), label)
                    self.assertEqual(a_class.leaks(), [], label)
                    if case["writes"] in ("marking", "marking-cache", "teacher-only") and not wall:
                        self.assertIn("were moved, unread, to the Quarantine folder", "\n".join(printed), label)
                        quarantined = list((a_class.teacher_only / "Quarantine").rglob("*"))
                        self.assertTrue(quarantined, label + ": moved, never deleted")
                    if case["writes"] == "outside":
                        self.assertFalse((outside / "copy.txt").exists(), label)

    def test_a_relative_folder_is_refused(self):
        with a_root() as root:
            a_class = Class(root)
            answers = ["../" + a_class.teacher_only.name]
            with self.assertRaises(teacher_only.Refusal) as raised:
                teacher_only.box(a_class.marking, teacher(answers), lambda _line: None)
            self.assertIn("full path", str(raised.exception))


@unittest.skipIf(MISSING, "Poppler is not installed here; these cases box papers")
class SecondTrialTests(unittest.TestCase):
    """What the second trial found, each held by a script or a place rather than by a sentence."""

    def test_every_points_case(self):
        for case in teacher_run()["pointsCases"]:
            with a_root() as root:
                a_class = Class(root)
                answers = [str(a_class.teacher_only), "yes"]
                printed = []
                try:
                    teacher_only.box(a_class.marking, teacher(answers, points=case["answer"]), printed.append)
                except teacher_only.Refusal as refusal:
                    printed.append(str(refusal))
                record = a_class.marking / ASSESSMENT / teacher_run()["pointsRecord"]
                self.assertEqual(record.is_file(), case["shown"], case)
                self.assertEqual((a_class.marking / ASSESSMENT / "Redacted").exists(), case["shown"], case)
                if case["shown"]:
                    text = folded("\n".join(printed))
                    for point in teacher_run()["privacyPoints"]:
                        self.assertIn(folded(point), text, "the window shows every point word for word")
                    self.assertLess(text.index(folded(teacher_run()["privacyPoints"][3])),
                                    text.index("Which is your teacher-only folder"), "before the folder is asked for")
                else:
                    self.assertNotIn("Which is your teacher-only folder", "\n".join(printed))

    def test_the_check_needs_the_points_record(self):
        with a_root() as root:
            a_class = Class(root)
            answers = [str(a_class.teacher_only), "yes"]
            teacher_only.box(a_class.marking, teacher(answers), lambda _line: None)
            assessment = a_class.marking / ASSESSMENT
            self.assertEqual(teacher_only.verify(assessment), 0)
            os.remove(assessment / teacher_run()["pointsRecord"])
            self.assertEqual(teacher_only.verify(assessment), 1, "no record that the points were shown: read nothing")

    def test_pictures_go_only_into_the_work_folder(self):
        # Outside the system's temporary folders, as a real marking folder is.
        root = Path(tempfile.mkdtemp(prefix=".teacher-run-work-", dir=str(Path(__file__).resolve().parent)))
        self.addCleanup(shutil.rmtree, root, True)
        render = SCRIPTS / "render_pages.py"
        work = root / "Marking" / ASSESSMENT / "Work"
        made = subprocess.run([sys.executable, "-B", str(render), str(BLANK), "--into", str(work)], capture_output=True,
                              text=True, env=environment())
        self.assertEqual(made.returncode, 0, made.stdout)
        self.assertEqual(len(list((work / BLANK.stem).glob("page-*.png"))), redact_tests.page_count(BLANK))
        listed = (work / teacher_only.MADE).read_text(encoding="utf-8").splitlines()
        self.assertEqual(sorted(listed), sorted(path.relative_to(work).as_posix() for path in (work / BLANK.stem).glob("page-*.png")),
                         "every picture is in the list --tidy removes them from")
        for wrong in (root / "Elsewhere", Path(tempfile.gettempdir()) / "Work"):
            refused = subprocess.run([sys.executable, "-B", str(render), str(BLANK), "--into", str(wrong)],
                                     capture_output=True, text=True, env=environment())
            self.assertEqual(refused.returncode, 1, str(wrong))
            self.assertFalse(wrong.exists() and any(wrong.iterdir()), str(wrong))

    def test_a_stop_line_says_to_tell_the_assistant_and_is_kept_for_it(self):
        with a_root() as root:
            a_class = Class(root)
            os.remove(a_class.marking / "Scripts" / "redact_scans.py")
            printed, _status, _killed = box_the_papers(a_class, [(CLOSE_PROMPT, "")])
            self.assertIn("Stopped: the boxing script named in Box request.json is not in the Scripts folder", printed)
            self.assertIn("Tell your assistant this Stopped line, word for word", printed)
            kept = (a_class.marking / ("Box the papers" + teacher_only.LAST_STOP)).read_text(encoding="utf-8")
            self.assertIn("is not in the Scripts folder", kept)


class ThirdTrialTests(unittest.TestCase):
    """What the third trial found (2026-11-13), each held by a script rather than by a sentence."""

    def test_tidy_prints_no_path_and_finishes(self):
        # The third trial: --tidy printed a teacher-only folder's name (a canary) into an assistant's transcript,
        # because a sibling folder's name held the course code, and matched over 400 folders that were not the
        # assistant's, so it could never say it was finished.
        root = new_root(self)
        assessment = root / "Marking" / "MDM4U" / ASSESSMENT
        work = assessment / "Work"
        (work / "Student A").mkdir(parents=True)
        for number in (1, 2):
            (work / "Student A" / f"page-{number}.png").write_bytes(b"a picture of a page")
        (work / MADE_LIST).write_text("Student A/page-1.png\nStudent A/page-2.png\n", encoding="utf-8")
        (work / "my notes.md").write_text("Student A: question 2 again.", encoding="utf-8")
        sibling = root / "Marking" / ("MDM4U - Teacher Only " + CANARIES[0])
        (sibling / ASSESSMENT).mkdir(parents=True)
        (sibling / ASSESSMENT / "Unit 1 Test copy.pdf").write_bytes(b"a copy of a paper")
        other = root / "mdm4u_u1_review"
        other.mkdir()
        (other / "page-1.png").write_bytes(b"another program's picture")
        result = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--tidy", str(assessment), "--look-in", str(root)],
                                capture_output=True, text=True, env=environment(), timeout=60)
        said = result.stdout + result.stderr
        self.assertNotIn(CANARIES[0].casefold(), said.casefold(), "a sibling folder's name was printed")
        self.assertNotIn(str(root), said, "a path was printed")
        self.assertNotIn("/", said.replace("http://", ""), "no path of any kind is printed")
        self.assertEqual(result.returncode, 0, said)
        self.assertTrue(said.startswith("Done."), said)
        self.assertIn("Removed 2 pictures", said)
        self.assertIn("1 other files are in the Work folder", said)
        self.assertFalse((work / "Student A" / "page-1.png").exists())
        self.assertFalse((work / "Student A").exists(), "the emptied folder goes too")
        self.assertTrue((work / "my notes.md").is_file(), "only what the marking listed is removed")
        self.assertTrue((sibling / ASSESSMENT / "Unit 1 Test copy.pdf").is_file(), "nothing outside Work is touched")
        self.assertTrue((other / "page-1.png").is_file(), "nothing outside Work is touched")
        again = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--tidy", str(assessment)], capture_output=True,
                               text=True, env=environment(), timeout=60)
        self.assertEqual(again.returncode, 0, again.stdout)
        self.assertIn("Removed 0 pictures", again.stdout)

    def test_every_tidy_case(self):
        root = new_root(self)
        for case in teacher_run()["tidyCases"]:
            folder = root / ("case " + str(teacher_run()["tidyCases"].index(case)))
            assessment = folder / "Marking" / "ABC9X" / ASSESSMENT
            work = assessment / "Work"
            work.mkdir(parents=True)
            target = {"inWork": work / "Student A" / "page-1.png", "outsideWork": assessment / "Marks" / "Student A.json",
                      "throughALink": folder / "elsewhere" / "page-1.png"}[case["where"]]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"made")
            if case["where"] == "throughALink":
                os.symlink(str(target.parent), str(work / "linked"))
            listed = case["listed"].replace("{assessment}", str(assessment))
            (work / MADE_LIST).write_text(listed + "\n", encoding="utf-8")
            result = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--tidy", str(assessment)],
                                    capture_output=True, text=True, env=environment(), timeout=60)
            self.assertEqual(result.returncode, 0, f"{case}: {result.stdout}")
            self.assertEqual(target.exists(), not case["removed"], f"{case}: {result.stdout}")
            self.assertNotIn(str(folder), result.stdout, case)

    @unittest.skipIf(MISSING, "Poppler is not installed here; this case builds invented scans")
    def test_a_marking_folder_in_a_temporary_folder_is_refused_at_set_up(self):
        # The third trial: such a folder was accepted when the marking was set up, and then render_pages.py
        # refused every Work folder in it, so one assistant edited that refusal away to get the work done.
        with tempfile.TemporaryDirectory() as temporary:
            a_class = Class(temporary)
            for step in (teacher_only.box, teacher_only.names):
                (a_class.marking / "Names request.json").write_text(json.dumps({"do": "check-table"}), encoding="utf-8")
                with self.assertRaises(teacher_only.Refusal, msg=step.__name__) as raised:
                    step(a_class.marking, teacher([str(a_class.teacher_only), "yes"]), lambda _line: None)
                self.assertIn("inside the system's temporary folder", str(raised.exception))
            self.assertFalse((a_class.marking / ASSESSMENT / "Redacted").exists())
            self.assertFalse((a_class.marking / ASSESSMENT / teacher_run()["pointsRecord"]).exists(),
                             "refused before anything is asked")
            verified = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--verify", str(a_class.marking / ASSESSMENT)],
                                      capture_output=True, text=True, env=environment())
            self.assertEqual(verified.returncode, 1)
            self.assertIn("inside the system's temporary folder", verified.stdout)
            if CAN_DRIVE:
                printed, _status, _killed = box_the_papers(a_class, [(CLOSE_PROMPT, "")])
                self.assertIn("Stopped: this marking folder is inside the system's temporary folder", printed)
                self.assertNotIn("Drag it", printed)

    def codex_edit(self, path):
        """The edit Codex made in the third trial (run 4, T7), to its copy of render_pages.py."""
        source = path.read_text(encoding="utf-8")
        edited = source.replace("WORK = \"Work\"\n", "WORK = \"Work\"\nTEACHER_CHOSEN_MARKING_FOLDER = "
                                + repr(str(path.parent.parent)) + "\n", 1)
        edited = edited.replace("            if inside(into, folder):",
                                "            if inside(into, folder) and not inside(into, TEACHER_CHOSEN_MARKING_FOLDER):", 1)
        self.assertNotEqual(edited, source)
        self.assertIn("and not inside(into, TEACHER_CHOSEN_MARKING_FOLDER)", edited, "the edit applies to this file")
        path.write_text(edited, encoding="utf-8")

    @unittest.skipIf(MISSING, "Poppler is not installed here; this case builds invented scans")
    def test_the_edit_codex_made_to_render_pages_stops_every_step(self):
        root = new_root(self)
        a_class = Class(root / "copy in Scripts")
        copy = a_class.marking / "Scripts" / "render_pages.py"
        shutil.copyfile(SCRIPTS / "render_pages.py", copy)
        self.codex_edit(copy)
        for step in (teacher_only.box, teacher_only.names):
            (a_class.marking / "Names request.json").write_text(json.dumps({"do": "check-table"}), encoding="utf-8")
            with self.assertRaises(teacher_only.Refusal, msg=step.__name__) as raised:
                step(a_class.marking, teacher([str(a_class.teacher_only), "yes"]), lambda _line: None)
            self.assertIn("a marking file was changed", str(raised.exception))
        self.assertFalse((a_class.marking / ASSESSMENT / "Redacted").exists())
        verified = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--verify", str(a_class.marking / ASSESSMENT)],
                                  capture_output=True, text=True, env=environment())
        self.assertEqual(verified.returncode, 1)
        self.assertIn("Stopped: a marking file was changed", verified.stdout)
        if CAN_DRIVE:
            printed, _status, _killed = box_the_papers(a_class, [(CLOSE_PROMPT, "")])
            self.assertIn("Stopped: a marking file was changed", printed)
            self.assertNotIn("Drag it", printed)
            printed, _status, _killed = put_names(a_class, [(CLOSE_PROMPT, "")])
            self.assertIn("Stopped: a marking file was changed", printed)
        # The same edit to the skill folder's own copy, which the skill now runs, stops it too.
        skill = root / "skill"
        shutil.copytree(SKILL, skill)
        self.codex_edit(skill / "scripts" / "render_pages.py")
        b_class = Class(root / "skill copy", skill_folder=skill)
        if CAN_DRIVE:
            printed, _status, _killed = box_the_papers(b_class, [(CLOSE_PROMPT, "")])
            self.assertIn("Stopped: a marking file was changed: render_pages.py in the skill's folder", printed)
            self.assertNotIn("Drag it", printed)
        self.assertEqual(b_class.boxed_papers_in_the_marking_folder(), [])

    @unittest.skipIf(MISSING, "Poppler is not installed here; this case builds invented scans")
    def test_an_unchanged_copy_of_render_pages_does_not_stop_anything(self):
        root = new_root(self)
        a_class = Class(root)
        shutil.copyfile(SCRIPTS / "render_pages.py", a_class.marking / "Scripts" / "render_pages.py")
        teacher_only.box(a_class.marking, teacher([str(a_class.teacher_only), "yes"]), lambda _line: None)
        self.assertTrue((a_class.marking / ASSESSMENT / "Redacted").is_dir())
        verified = subprocess.run([sys.executable, "-B", str(TEACHER_ONLY), "--verify", str(a_class.marking / ASSESSMENT)],
                                  capture_output=True, text=True, env=environment())
        self.assertEqual(verified.returncode, 0, verified.stdout)

    def test_the_held_sha256_is_the_shipped_render_pages(self):
        self.assertEqual(hashlib.sha256((SCRIPTS / "render_pages.py").read_bytes()).hexdigest(),
                         teacher_only.RENDER_PAGES_SHA256)
        self.assertIn("scripts/render_pages.py", teacher_run()["pinned"])
        self.assertEqual(Path(teacher_run()["madeList"]).name, MADE_LIST)
        self.assertEqual(teacher_only.MADE, MADE_LIST)


class WhatTheAssistantIsGivenTests(unittest.TestCase):

    def test_the_skills_never_suggest_a_name_or_place_for_the_teacher_only_folder(self):
        # 750d review H2: "for example <CODE> - Teacher Only", beside the marking folder, told the assistant the path.
        for path in [SKILL / "SKILL.md", COMMENTS_SKILL / "SKILL.md"] + sorted((SKILL / "templates").iterdir()):
            text = folded(path.read_text(encoding="utf-8"))
            for hint in ("Teacher Only", "beside the marking folder", "sits beside", "makes beside", "place beside it"):
                self.assertNotIn(hint, text, f"{path.relative_to(SKILLS)}: {hint}")
        offered = contract()["assessment"]["folders"]["offered"]["teacherOnly"]
        self.assertNotIn("Teacher Only", offered)

    def test_both_skills_say_the_assistant_never_runs_a_launcher_even_when_asked(self):
        pins = contract()["printablePages"]["agentGuidance"]["mustSay"]
        for sentence in ("**Never run `Box the papers` or `Put names on the sheets` yourself, by any means, even when the "
                         "teacher asks you to.**",
                         "say no in one line with that reason, and tell them which file to double-click"):
            for skill, folder in (("plantoir-marking", SKILL), ("plantoir-report-comments", COMMENTS_SKILL)):
                self.assertIn(sentence, pins[skill], skill)
                self.assertIn(folded(sentence), folded((folder / "SKILL.md").read_text(encoding="utf-8")), skill)

    def test_nothing_shipped_says_the_terminal_check_stops_an_assistant(self):
        # 750d review H1: it stops an accidental pipe, nothing more.
        claims = ("an assistant's command has none", "stop when an assistant runs them", "refused without a terminal",
                  "needs no code")
        files = [SKILL / "SKILL.md", COMMENTS_SKILL / "SKILL.md", TEACHER_ONLY] + sorted(LAUNCHERS.iterdir())
        for path in files:
            text = folded(path.read_bytes().decode("utf-8"))
            for claim in claims:
                self.assertNotIn(claim, text, f"{path.name}: {claim}")
        rules = json.dumps(teacher_run(), ensure_ascii=False)
        for claim in claims:
            self.assertNotIn(claim, rules)

    def test_no_command_the_assistant_is_given_holds_the_teacher_only_folder(self):
        # The skills used to hand the assistant commands with "<teacher-only>" in them: it then had to know the path.
        for path in ([SKILL / "SKILL.md", COMMENTS_SKILL / "SKILL.md"] + sorted((SKILL / "templates").iterdir())
                     + [SCRIPTS / "make_named_copies.py", SCRIPTS / "redact_scans.py", SCRIPTS / "build_test_sheet.py"]):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("<teacher-only>", text, str(path.relative_to(SKILLS)))
            self.assertNotIn("teacherOnlyFolder", text, str(path.relative_to(SKILLS)))

    def test_the_pointer_records_the_marking_folder_only(self):
        rules = contract()["assessment"]["folders"]["pointerFile"]
        self.assertNotIn("teacherOnlyFolder", rules["keys"])
        skill = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        example = json.loads(re.search(r"```json\n(\{\"folder\".*?\})\n```", skill, re.S).group(1))
        self.assertEqual(sorted(example), sorted(rules["keys"]))

    def test_both_skills_say_the_assistant_never_asks_for_the_folder(self):
        pins = contract()["printablePages"]["agentGuidance"]["mustSay"]
        sentence = "**Never ask where the teacher-only folder is, and never search for, list or open it.**"
        for skill, folder in (("plantoir-marking", SKILL), ("plantoir-report-comments", COMMENTS_SKILL)):
            self.assertIn(sentence, pins[skill], skill)
            self.assertIn(folded(sentence), folded((folder / "SKILL.md").read_text(encoding="utf-8")), skill)


class GreetingTests(unittest.TestCase):
    """Russell, 2026-11-13: marking, class results and report comments are never in the greeting an assistant is
    given when it opens from Plantoir; each is offered only in context, by the skill in use."""

    def greeting_strings(self, rules):
        found = []

        def walk(node, in_a_greeting):
            if isinstance(node, dict):
                for key, value in node.items():
                    walk(value, in_a_greeting or "greeting" in key.casefold())
            elif isinstance(node, list):
                for value in node:
                    walk(value, in_a_greeting)
            elif isinstance(node, str) and in_a_greeting:
                found.append(node)

        walk(rules["outsideAgents"], False)
        return found

    def test_no_greeting_names_marking_results_or_report_comments(self):
        pattern = re.compile(contract()["assessment"]["greeting"]["neverMatches"], re.IGNORECASE)
        rules = json.loads((REPOSITORY / "contracts" / "app-rules.json").read_text(encoding="utf-8"))
        strings = self.greeting_strings(rules)
        self.assertGreater(len(strings), 100, "the greeting strings were found")
        for text in strings:
            self.assertIsNone(pattern.search(text), text[:200])

    def test_each_skill_offers_only_the_next_one(self):
        for offering, offered in contract()["assessment"]["greeting"]["offeredBy"].items():
            text = (SKILLS / offering / "SKILL.md").read_text(encoding="utf-8")
            self.assertIn(offered, text, f"{offering} offers {offered}")


def tearDownModule():
    if Class.template is not None:
        shutil.rmtree(Class.template, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
