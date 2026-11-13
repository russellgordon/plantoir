#!/usr/bin/env python3
"""The teacher's own steps: the two that touch the teacher-only folder, run by the TEACHER, never the assistant.

Part of the plantoir-marking skill, and NOT a starting point: it is never copied, adapted or changed. The
two launchers in the marking folder ("Box the papers" and "Put names on the sheets", a .command on a Mac and
a .bat on Windows) check its SHA-256 and the runner's before they run it, and the skill names all of them.

    python3 -I -B teacher_only.py box MARKING_FOLDER       (run by "Box the papers", in the teacher's window)
    python3 -I -B teacher_only.py names MARKING_FOLDER     (run by "Put names on the sheets")
    python3 -I -B teacher_only.py --verify "<marking folder>/<Assessment>"   (the assistant, before any read)
    python3 -I -B teacher_only.py --tidy "<marking folder>/<Assessment>"
                                                           (the assistant, before it calls marking finished)
    python3 -I -B teacher_only.py --points-shown "<marking folder>/<Term> Comments"
                                                           (the assistant, before it reads a marks record for comments)

Since the second trial (750d, 2026-11-13): Box the papers prints the four privacy points in its own window and
takes the teacher's yes to them before it asks for the folder, and records that they were shown (an assistant
did not say them in two runs); the teacher's notes for report comments are kept in the teacher-only folder and
reach the marking folder only as a checked copy this file writes (an assistant read the notes before the name
check had run).

Since the third trial (750d, 2026-11-13): --tidy removes only the pictures render_pages.py listed in
"<Assessment>/Work/Made while marking.txt", and prints counts and never a path (it used to look through the
system's temporary folders by name, printed every folder it matched, a teacher-only folder's name among them,
and matched over 400 folders that were not the assistant's, so it could never finish). A marking folder inside
the system's temporary folder is refused by both of the teacher's steps and by --verify. And render_pages.py,
whose refusal of temporary folders an assistant edited away in its copy, is checked against the SHA-256 held
here (RENDER_PAGES_SHA256) by both steps and by --verify, in the skill's folder and in the marking folder's
Scripts/: a changed copy stops with a "Stopped:" line that says a marking file was changed.

Since the fourth trial (750d, 2026-11-13): the check covers the file, not two paths. render_pages.py is checked in
every skill home (this file's, the one "Skill folder.txt" names, and the other of .claude and .agents in the same
working folder), and in the marking folder at any depth, where any Python file that renders pages as
render_pages.py does (pdftoppm with one of RENDERER_MARKS) must be the shipped file; --tidy runs the same check.
What no hash can see: an assistant that calls pdftoppm itself, or writes a renderer with none of the marks, or
runs one from outside these folders. Nothing here stops that; the skill forbids it.

#750, piece 750d. Russell, 2026-11-12: "script runs, teacher checks the papers, confirms names are redacted,
then agent based marking begins. Simple." Six trials found an assistant's FIRST command could list the
teacher-only folder, which put a student's name in its transcript. So the assistant is never told where
that folder is. The teacher double-clicks a launcher, which asks for the folder in its own window; this
file boxes the papers through the adapted boxing script and the runner into a holding folder on the
teacher's side, makes ONE file of them with the four privacy points on its cover, and asks the teacher to
type yes once they have looked through every page. Only on yes do the boxed papers move into
"<Assessment>/Redacted" in the marking folder, with a record of what was moved (identifiers and SHA-256,
never a path). On anything else nothing moves.

What it prints, and what it writes in the marking folder, holds identifiers, counts and plain sentences:
never a name, and never the teacher-only folder's path (each line from another script has that path put
back as "your teacher-only folder", and passed through the runner, which withholds any line holding a word
from the name mapping table).

It is a safety net against an accident and a well-meant change, not a lock. Nothing in this file or in a
launcher can stop an assistant that runs a launcher itself and types the yes: its check that its input is a
terminal stops an accidental pipe and nothing more, and an assistant could run it through a
pseudo-terminal. An assistant that set out to find the teacher-only folder could look for it, and one that
edited this file and every pin together would not be caught by the pins. The design holds because the
assistant is never told where the teacher-only folder is, is told never to run these steps (even when the
teacher asks) and to wait for the teacher, and because the teacher starts them; an assistant that ran one
would be doing what the skill forbids, and the re-trial checks for it.

What the teacher trusts: that the boxing script the assistant adapted does only what it says. This file runs
it with the teacher-only folder open to it, so on a Mac it is run under sandbox-exec, able to write only
into that assessment's folder on the teacher's side and the temporary folder, and on every system anything
the boxing step wrote outside the folder it was given (in the marking folder or the teacher-only folder) is
moved, unread and never deleted, into the teacher-only Quarantine folder, and the step stops before anything
is put together for the teacher's look, saying how many. A write outside both folders is stopped on a Mac
only, by the sandbox; on Windows it cannot be seen. That is why the teacher looks through the boxed papers.

Needs Poppler (pdfinfo, pdfunite) for the combined file, and the Python standard library. Python 3.9 or later.
"""
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
from pathlib import Path

# MARK: - What must not change
#   This file is never adapted. It never prints, or writes in the marking folder, a value read from the name
#   mapping table or the teacher-only folder's path; it moves boxed papers into the marking folder only after
#   the teacher types yes in this window, and only the papers it put in the file the teacher looked through;
#   it stops when its input is not a terminal (that catches an accidental pipe, nothing more); it moves to the
#   teacher's Quarantine, never deleting, anything the boxing step wrote outside the folder it was given, and
#   stops; it refuses a marking folder inside the system's temporary folder, and stops when render_pages.py is
#   not the file whose SHA-256 it holds; --tidy removes only files listed in the Work folder's list that are
#   inside the Work folder, and prints no path; and it never says a name is covered, removed or safe.

SCRIPTS = Path(__file__).resolve().parent
RUNNER = SCRIPTS / "run_with_names.py"
TABLE = "Name Mapping Table.csv"
SKILL_FOLDER_FILE = "Skill folder.txt"
BOX_REQUEST = "Box request.json"
NAMES_REQUEST = "Names request.json"
BOX_SAID = "Box the papers - what it said.txt"
NAMES_SAID = "Put names on the sheets - what it said.txt"
ORIGINALS = "Originals"
HOLDING = "Holding"
CHECK = "Check"
NAMED = "Named"
QUARANTINE = "Quarantine"
REDACTED = "Redacted"
COMBINED = "Redacted papers to look through.pdf"
RECORD = "Teacher looked.json"
POINTS_RECORD = "Privacy points shown.json"
NOTES = "Teacher Notes.md"
CHECKED_NOTES = "Teacher Notes (checked).md"
CHECKED_MARK = "<!-- Checked by Put names on the sheets"
WORK = "Work"
MADE = "Made while marking.txt"          # render_pages.py's list of the pictures it wrote, inside Work
RENDER_PAGES = "render_pages.py"
# The SHA-256 of render_pages.py as Plantoir ships it. This file is pinned by both launchers, so the value cannot
# be changed without that being seen too (750d third trial: an assistant edited its copy's refusal of temporary
# folders away and told no one).
RENDER_PAGES_SHA256 = "4440359bb35d986d450fa684aa3e1c3427335804d012e4ac2afdc8c0ac91b819"
LAST_STOP = " - last stop.txt"
# The two sentences a "Stopped: a marking file was changed" line carries (contracts: teacherRun.checkedFiles).
SAYS_THE_SKILL = ("render_pages.py in the plantoir-marking skill's own folder, in your working folder, is not the one "
                  "Plantoir shipped. Plantoir puts the skill back as it shipped the next time it opens your working "
                  "folder: open it in Plantoir, then double-click again, and ask your assistant what it changed.")
SAYS_A_COPY = ("Copies of render_pages.py in the marking folder ({n}), under its own name or another, are not the one "
               "Plantoir shipped. Ask your assistant to remove them (render_pages.py is run from the skill's folder, "
               "never copied) and to tell you what it had changed.")
ASK_POINTS = "Type yes when you have read these four points, or no to stop: "
IDENTIFIER = re.compile(r"^Student [A-Z]{1,2}$")
SECTION = re.compile(r"^Section \d+$")
NO_OPEN = "PLANTOIR_MARKING_NO_OPEN"     # set by every test and harness: nothing is opened and no chooser is shown
THE_FOLDER = "your teacher-only folder"
BOX_OPTIONS = ("--label", "--box", "--dpi")

# The four privacy points, word for word as the skill says them and as contracts/shared-rules.json ->
# assessment -> teacherRun -> privacyPoints holds them; the cover of the combined file carries them.
PRIVACY_HEADING = "Before we start, four things about your students' privacy:"
PRIVACY_POINTS = [
    "Whatever I read is sent to the AI service I run on, so that I can work on it. That includes every boxed "
    "paper. Please turn off model training for the account you use with me (on claude.ai: Settings, Privacy, "
    "\"Help improve Claude\"; on ChatGPT: Settings, Data controls, \"Improve the model for everyone\", where "
    "offered; as of November 2026, so check the names), check what your provider keeps for your kind of "
    "account, and check that your school or board allows student work to be processed by this service.",
    "I work with identifiers only (Student A, Student B). I never ask where your teacher-only folder is, and I "
    "never open your name mapping table, a class list, an original scan, or anything in that folder. You run "
    "the two steps that touch names yourself, by double-clicking a file in your marking folder. The first boxes "
    "the name line at the top of each page whose blank test has a name blank and puts all the boxed papers in "
    "one file for you; they reach the folder I read only after you have looked through every page of it and "
    "typed yes. Your look is what confirms the names are redacted, and I never open that file. A name written "
    "anywhere else (in a margin, inside an answer, on a page with no name blank) is not boxed, and I would see it.",
    "If I see what looks like a name anywhere, I will not repeat it in any message or file. I will tell you only "
    "the identifier and the page, and leave that page until you say.",
    "The files I write stay on this computer, in the folders you choose. I never send, upload or publish "
    "anything; giving work back to students is yours to do.",
]
# The report-comments skill's four points (contracts: teacherRun.commentPrivacyPoints), shown by Put names on the
# sheets before a report-comments step asks for the folder (750d fourth trial: the two skills now handle the
# points the same way).
COMMENT_POINTS = [
    "Whatever I read is sent to the AI service I run on, so that I can work on it. That includes the marks records "
    "and feedback I draft the comments from. Please check that model training is turned off for the account you use "
    "with me (on claude.ai: Settings, Privacy, \"Help improve Claude\"; on ChatGPT: Settings, Data controls, \"Improve "
    "the model for everyone\", where offered; as of November 2026, so check the names), and that your school or board "
    "allows this work to be processed by this service.",
    "I work with identifiers only (Student A, Student B), and I write {first name} in every comment where the first "
    "name goes. I never ask where your teacher-only folder is, and I never open your name mapping table, a class "
    "list, your report system or an export from it, or anything in that folder. You put the first names in yourself "
    "at the end, by double-clicking \"Put names on the sheets\" in your marking folder: it writes them into your "
    "teacher-only folder and tells me only counts.",
    "If I see what looks like a name anywhere, I will not repeat it in any message or file. I will tell you only the "
    "identifier and where it is.",
    "The files I write stay on this computer, in the folders you chose for marking. I never send, upload or enter "
    "anything; putting the comments into your report system is yours to do.",
]
# The fourth trial: the window printed the points, which are in the assistant's voice ("Whatever I read"), under a
# line that said the assistant does not repeat them. Now it says whose words they are.
WINDOW_INTRODUCTION = ("Four things about your students' privacy, in your assistant's words (\"I\" is your assistant). "
                       "Please read them here, in this window; your assistant does not say them again:")
COVER_INTRODUCTION = ("These four things were shown in the Box the papers window before any paper was boxed, and you "
                      "typed yes to them. They are in your assistant's words (\"I\" is your assistant):")
LOOK_FOR = ("Look through every page of every paper after this one. Look for any part of a name, and anything else "
            "that says who wrote it (a signature, initials, a student number). The boxing does not check how each "
            "page was scanned: on a page scanned upside down the name line is at the foot, and on a page scanned "
            "shifted or shrunk part of the name can show just below the black box; and a name written anywhere "
            "else on a page is not boxed.")
NOT_PROVED = ("This file does not prove who looked, or how carefully. The papers reach your assistant only when "
              "you type yes in the Box the papers window.")
ASK_YES = "Type yes when you have looked through every page of every paper and no part of a name shows, or no if something shows: "


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding no name and no teacher-only path."""


# ---------------------------------------------------------------- folders


def inside(path, folder):
    path = Path(path).resolve()
    folder = Path(folder).resolve()
    return path == folder or folder in path.parents


def inside_a_working_folder(path):
    """True when the path, or a folder above it, is a Plantoir working folder (it holds courses/ and .toolchain/)."""
    path = Path(path).resolve()
    for folder in [path] + list(path.parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            return True
    return False


def temporary_folders():
    found = []
    for folder in (tempfile.gettempdir(), os.environ.get("TMPDIR", ""), "/tmp", "/private/tmp", "/var/tmp"):
        if folder and os.path.isdir(folder) and os.path.realpath(folder) not in found:
            found.append(os.path.realpath(folder))
    return found


def inside_a_temporary_folder(path):
    """True when the path is inside one of the system's temporary folders, which anyone on the computer can read
    and the system empties (750d third trial: a marking folder there was accepted at set-up, and then
    render_pages.py refused every Work folder in it, so one assistant edited that refusal away)."""
    for folder in temporary_folders():
        if inside(path, folder):
            return True
    return False


def the_marking_folder_is_usable(marking):
    """A Refusal, worded for the teacher, when the marking folder is in a place marking is never kept."""
    if inside_a_working_folder(marking):
        raise Refusal("this marking folder is inside the Plantoir working folder; marking is kept outside it. "
                      "Nothing was done")
    if inside_a_temporary_folder(marking):
        raise Refusal("this marking folder is inside the system's temporary folder, which anyone on this computer can "
                      "read and which the system empties. Marking is kept in a folder you choose in your home folder, "
                      "such as Marking. Ask your assistant to set the marking up there. Nothing was done")


SKILL_HOMES = (".claude", ".agents")
# What makes a script a page renderer, for a copy of render_pages.py under another name (750d fourth trial: an
# edited copy as Scripts/render_local.py was not checked). Each is in render_pages.py; none is in the other
# shipped scripts (redact_scans.py calls pdftoppm for JPEG pages only, and names none of the rest).
RENDERER_MARKS = (b"-png", b"check_the_folder", b"render_pages", b"Made while marking")


def skill_homes(marking):
    """Every plantoir-marking skill folder the marking could be using: this file's own, the one the marking
    folder's 'Skill folder.txt' names, and for each the other home in the same working folder (.claude and
    .agents: Codex reads .agents, Claude Code reads .claude, and the fourth trial edited the one 'Skill
    folder.txt' did not name)."""
    found = []

    def add(folder):
        folder = Path(os.path.realpath(str(folder)))
        if folder not in found:
            found.append(folder)

    add(SCRIPTS.parent)
    try:
        named = (Path(marking) / SKILL_FOLDER_FILE).read_text(encoding="utf-8").splitlines()[0].strip()
    except (OSError, UnicodeDecodeError, IndexError):
        named = ""
    if named and Path(named).is_absolute() and Path(named).is_dir():
        add(named)
    for folder in list(found):
        if folder.parent.name == "skills" and folder.parent.parent.name in SKILL_HOMES:
            for home in SKILL_HOMES:
                other = folder.parent.parent.parent / home / "skills" / folder.name
                if other.is_dir():
                    add(other)
    return found


def renders_pages(path):
    """True for a Python file that renders pages as pictures as render_pages.py does."""
    try:
        data = Path(path).read_bytes()
    except OSError:
        return False
    return b"pdftoppm" in data and any(mark in data for mark in RENDERER_MARKS)


def changed_marking_files(marking):
    """(skill homes with a changed render_pages.py, copies in the marking folder that are changed) as counts.
    In every skill home render_pages.py must be the file Plantoir shipped, and any other script there that
    renders pages is a change. In the marking folder, at any depth, every render_pages.py and every other Python
    file that renders pages must be the shipped file. teacher_only.py and run_with_names.py are checked by the
    launchers before this file runs. Counts only: a copy's name is the assistant's choice and is never printed."""
    in_the_skill = 0
    for home in skill_homes(marking):
        scripts = home / "scripts"
        shipped = scripts / RENDER_PAGES
        changed = shipped.is_symlink() or not shipped.is_file() or sha256_of(shipped) != RENDER_PAGES_SHA256
        if scripts.is_dir():
            for entry in scripts.iterdir():
                if entry.name in (RENDER_PAGES, "teacher_only.py", "run_with_names.py") or entry.suffix != ".py":
                    continue
                if entry.is_symlink() or (entry.is_file() and renders_pages(entry)):
                    changed = True
        if changed:
            in_the_skill += 1
    in_the_marking_folder = 0
    for top, folders, files in os.walk(str(marking), followlinks=False):
        for name in files:
            path = Path(top) / name
            if name != RENDER_PAGES and not name.endswith(".py"):
                continue
            if path.is_symlink():
                if name == RENDER_PAGES:
                    in_the_marking_folder += 1
                continue
            if name == RENDER_PAGES or renders_pages(path):
                if sha256_of(path) != RENDER_PAGES_SHA256:
                    in_the_marking_folder += 1
    return in_the_skill, in_the_marking_folder


def what_was_changed(marking):
    """The sentence a Stopped line carries when a marking file was changed, or None."""
    in_the_skill, in_the_marking_folder = changed_marking_files(marking)
    if not in_the_skill and not in_the_marking_folder:
        return None
    parts = []
    if in_the_skill:
        parts.append(SAYS_THE_SKILL)
    if in_the_marking_folder:
        parts.append(SAYS_A_COPY.replace("{n}", str(in_the_marking_folder)))
    return "a marking file was changed. " + " ".join(parts) + " Nothing was done"


def the_marking_files_are_as_shipped(marking):
    changed = what_was_changed(marking)
    if changed:
        raise Refusal(changed)


def typed_path(typed, windows=None):
    """The folder a teacher typed or dragged into the window: a drag on a Mac gives the path with each space
    written as a backslash and a space, and a trailing space; on Windows it gives the path in double quotes."""
    if windows is None:
        windows = os.name == "nt"
    text = typed.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    if windows:
        return text
    unescaped = ""
    escaped = False
    for character in text:
        if escaped:
            unescaped += character
            escaped = False
        elif character == "\\":
            escaped = True
        else:
            unescaped += character
    return unescaped


def chosen_in_a_window():
    """The system's own folder chooser, shown by this window, never by the assistant. None if it cannot be shown
    or the teacher closed it, and None, showing nothing, when PLANTOIR_MARKING_NO_OPEN is set (every test)."""
    if os.environ.get(NO_OPEN):
        return None
    try:
        if sys.platform == "darwin":
            result = subprocess.run(["osascript", "-e", 'POSIX path of (choose folder with prompt '
                                     '"Choose your teacher-only folder")'], capture_output=True, text=True)
        elif os.name == "nt":
            script = ("Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object "
                      "System.Windows.Forms.FolderBrowserDialog; $dialog.Description = 'Choose your teacher-only "
                      "folder'; if ($dialog.ShowDialog() -eq 'OK') { $dialog.SelectedPath }")
            result = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True)
        else:
            return None
    except OSError:
        return None
    chosen = result.stdout.strip()
    if result.returncode != 0 or not chosen:
        return None
    return chosen


def ask_for_the_teacher_only_folder(marking, ask, say):
    """The teacher-only folder, from the teacher, checked; a Refusal if it is not usable."""
    say("Which is your teacher-only folder (the one with your name mapping table and the original scans)?")
    say("(Keep it beside your marking folder, outside your Plantoir working folder, and named as you like.)")
    answer = ask("Drag it into this window and press Return, or press Return alone to choose it in a window: ")
    if answer is None:
        raise Refusal("no folder was given; nothing was done")
    folder = typed_path(answer)
    if not folder:
        folder = chosen_in_a_window()
        if folder is None:
            raise Refusal("no folder was chosen; nothing was done. Double-click again and drag the folder into "
                          "the window")
    folder = Path(os.path.expanduser(folder))
    if not folder.is_absolute():
        raise Refusal("give the folder's full path: drag it into the window. Nothing was done")
    if not folder.is_dir():
        raise Refusal("that is not a folder I can open; nothing was done")
    if inside(folder, marking) or inside(marking, folder):
        raise Refusal("the teacher-only folder must be beside the marking folder, not inside it or around it; "
                      "nothing was done")
    if inside_a_working_folder(folder):
        raise Refusal(THE_FOLDER + " is inside the Plantoir working folder, where it could be built into a "
                      "class website or copied with a course; move it outside. Nothing was done")
    if inside_a_temporary_folder(folder):
        raise Refusal(THE_FOLDER + " is inside the system's temporary folder, which anyone on this computer can read "
                      "and which the system empties; keep it in your home folder. Nothing was done")
    if not (folder / TABLE).is_file():
        raise Refusal(f"{THE_FOLDER} has no '{TABLE}' in it; put your name mapping table there and double-click "
                      "again. Nothing was done")
    return folder


def hide_the_folder(text, teacher_only):
    """The text with the teacher-only folder's path, in every spelling it could be printed in, put back as
    'your teacher-only folder'."""
    full = {str(teacher_only), str(Path(teacher_only).resolve()), os.path.realpath(str(teacher_only))}
    spellings = set()
    for spelling in full | {Path(teacher_only).name}:
        # as written, as a relative path or a file:// address would hold it (750d review M2)
        spellings |= {spelling, urllib.parse.quote(spelling), urllib.parse.quote(spelling, safe="")}
    for spelling in sorted(spellings, key=len, reverse=True):
        if spelling:
            text = text.replace(spelling, THE_FOLDER)
    return text


# ---------------------------------------------------------------- what was written, and the record


def sha256_of(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def papers_in(folder):
    """{relative path with / : SHA-256, or "link" or "folder"} of EVERY entry under the folder, whatever its name,
    case or type. Links are listed as links, never followed."""
    found = {}
    folder = Path(folder)
    if not folder.is_dir():
        return found
    for top, folders, files in os.walk(folder, followlinks=False):
        for name in folders + files:
            path = Path(top) / name
            relative = path.relative_to(folder).as_posix()
            if path.is_symlink():
                found[relative] = "link"
            elif path.is_dir():
                found[relative] = "folder"
            else:
                found[relative] = sha256_of(path)
    return dict(sorted(found.items()))


def natural(text):
    """Section 2 before Section 10, Student B before Student AA, as a class list runs."""
    key = []
    for token in re.findall(r"\d+|[^\W\d_]+|[\W_]+", text):
        if token.isdigit():
            key.append((0, int(token), ""))
        else:
            key.append((1, len(token), token.casefold()))
    return key


def papers_of_a_batch(holding):
    """[(identifier label such as 'Section 1/Student A', relative path)] of the holding folder, in class-list
    order; a Refusal, naming no file, when anything there is not a boxed paper named by an identifier."""
    entries = papers_in(holding)
    papers = []
    odd = 0
    for relative, kind in entries.items():
        parts = relative.split("/")
        if kind == "link":
            odd += 1
        elif kind == "folder":
            if len(parts) != 1 or not SECTION.match(parts[0]):
                odd += 1
        elif not relative.endswith(".pdf") or not IDENTIFIER.match(parts[-1][:-4]):
            odd += 1
        elif len(parts) == 2 and not SECTION.match(parts[0]):
            odd += 1
        elif len(parts) > 2:
            odd += 1
        else:
            papers.append((relative[:-4], relative))
    if odd:
        raise Refusal(f"the boxing left {odd} things that are not a boxed paper named by an identifier (Section N/"
                      "Student A.pdf), so nothing was put together for you to look through, and nothing was moved")
    papers.sort(key=lambda paper: natural(paper[0]))
    return papers


def points_text(points=None):
    points = PRIVACY_POINTS if points is None else points
    return PRIVACY_HEADING + "\n" + "\n".join(f"{number}. {point}" for number, point in enumerate(points, start=1))


def show_the_privacy_points(folder, ask, say, points=None):
    """The four points, word for word, in the teacher's own window, and the teacher's yes to them, recorded in
    the assessment's folder: whichever assistant the teacher uses, the teacher has seen them before any paper
    reaches it. A no, or a closed window, stops everything."""
    say("")
    say(WINDOW_INTRODUCTION)
    say(points_text(points))
    say("")
    while True:
        answer = ask(ASK_POINTS)
        if answer is None or answer.strip().casefold() in ("no", "n"):
            raise Refusal("the four privacy points were not acknowledged, so nothing was done")
        if answer.strip().casefold() == "yes":
            break
        say("Please type yes or no.")
    Path(folder).mkdir(parents=True, exist_ok=True)
    Path(folder, POINTS_RECORD).write_text(json.dumps({
        "shown": datetime.datetime.now().isoformat(timespec="seconds"),
        "points": hashlib.sha256(points_text(points).encode("utf-8")).hexdigest()}, indent=1), encoding="utf-8")


def points_were_shown(assessment, points=None):
    try:
        record = json.loads((Path(assessment) / POINTS_RECORD).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return record.get("points") == hashlib.sha256(points_text(points).encode("utf-8")).hexdigest()


def points_shown(folder):
    """For report comments: exit 0 only when Put names on the sheets showed the report-comments skill's four
    points in the teacher's window and the teacher typed yes to them, for this term's comments folder."""
    if points_were_shown(folder, COMMENT_POINTS):
        print("The teacher read the four privacy points in Put names on the sheets and typed yes; you may read the "
              "marks records.")
        return 0
    print("Not yet: the teacher has not read the four privacy points in Put names on the sheets. Write the "
          "comment-facts request and ask the teacher to double-click Put names on the sheets; read no marks record "
          "until then.")
    return 1


def verify(assessment):
    """Exit 0 only when '<Assessment>/Redacted' holds exactly the papers the teacher typed yes for, after the four
    privacy points were shown in the teacher's window."""
    assessment = Path(assessment)
    try:
        the_marking_folder_is_usable(assessment.resolve().parent)
        the_marking_files_are_as_shipped(assessment.resolve().parent)
    except Refusal as refusal:
        print(f"Stopped: {refusal}. Read no paper.")
        return 1
    record_path = assessment / RECORD
    now = papers_in(assessment / REDACTED)
    if record_path.is_file() and now and points_were_shown(assessment):
        try:
            record = json.loads(record_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            record = {}
        if record.get("papers") == now:
            papers = []
            for relative, kind in now.items():
                if kind not in ("link", "folder"):
                    papers.append(relative[:-4])
            papers.sort(key=natural)
            print(f"The teacher typed yes in Box the papers for these {len(papers)} papers ({record.get('looked', '')}), "
                  "after they were put in one file to look through; read only these: " + "; ".join(papers) + ".")
            return 0
    print("Not confirmed: the redacted folder does not hold exactly the papers the teacher typed yes for (no papers "
          "yet, a changed or added file of any kind, or no record). Ask the teacher to double-click Box the papers "
          "in the marking folder; read no paper until then.")
    return 1


# ---------------------------------------------------------------- the combined file


class PdfWriter:
    """Pages of Helvetica text only, in WinAnsiEncoding (so an apostrophe reads back as typed)."""

    def __init__(self):
        self.objects = []
        self.pages = []

    def add(self, body):
        self.objects.append(body)
        return len(self.objects)

    def page(self, content):
        stream = self.add(b"<</Length %d>>stream\n" % len(content) + content + b"\nendstream")
        self.pages.append(stream)

    def write(self, path):
        pages_number = self.add(b"")
        font = self.add(b"<</Type/Font/Subtype/Type1/BaseFont/Helvetica/Encoding/WinAnsiEncoding>>")
        kids = []
        for stream in self.pages:
            kids.append(self.add(b"<</Type/Page/Parent %d 0 R/MediaBox[0 0 612 792]/Resources<</Font<</F1 %d 0 R>>>>"
                                 b"/Contents %d 0 R>>" % (pages_number, font, stream)))
        kid_list = b" ".join(b"%d 0 R" % kid for kid in kids)
        self.objects[pages_number - 1] = b"<</Type/Pages/Kids[%s]/Count %d>>" % (kid_list, len(kids))
        catalog = self.add(b"<</Type/Catalog/Pages %d 0 R>>" % pages_number)
        body = bytearray(b"%PDF-1.4\n")
        offsets = []
        for number, data in enumerate(self.objects, start=1):
            offsets.append(len(body))
            body += b"%d 0 obj\n" % number + data + b"\nendobj\n"
        start = len(body)
        body += b"xref\n0 %d\n0000000000 65535 f \n" % (len(self.objects) + 1)
        for offset in offsets:
            body += b"%010d 00000 n \n" % offset
        body += b"trailer<</Size %d/Root %d 0 R>>\nstartxref\n%d\n%%%%EOF\n" % (len(self.objects) + 1, catalog, start)
        Path(path).write_bytes(bytes(body))


def pdf_text(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)").encode("cp1252", "replace")


def wrapped(text, width):
    lines = []
    line = ""
    for word in text.split():
        if line and len(line) + 1 + len(word) > width:
            lines.append(line)
            line = word
        else:
            line = (line + " " + word) if line else word
    if line:
        lines.append(line)
    return lines


def cover(writer, assessment, count):
    """The first page (or pages) of the combined file: the four privacy points, what to look for, and what the
    file does not prove."""
    blocks = [(18, "Redacted papers to look through"), (11, f"{assessment}: {count} papers"), (0, ""),
              (10, COVER_INTRODUCTION), (0, ""), (10, PRIVACY_HEADING)]
    for number, point in enumerate(PRIVACY_POINTS, start=1):
        blocks.append((10, f"{number}. {point}"))
    blocks += [(0, ""), (12, "What to look for"), (10, LOOK_FOR), (0, ""), (10, NOT_PROVED)]
    content = b""
    y = 740
    for size, text in blocks:
        if size == 0:
            y -= 8
            continue
        for line in wrapped(text, 98 if size <= 10 else 70):
            if y < 60:
                writer.page(content)
                content = b""
                y = 740
            content += b"BT /F1 %d Tf 54 %d Td (%s) Tj ET\n" % (size, y, pdf_text(line))
            y -= size + 4
    writer.page(content)


def page_count(pdf):
    result = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True)
    match = re.search(r"Pages:\s+(\d+)", result.stdout)
    if result.returncode != 0 or match is None:
        raise Refusal("a boxed paper could not be read, so nothing was put together for you to look through, and "
                      "nothing was moved")
    return int(match.group(1))


def prepare(holding, check, assessment):
    """Put exactly the papers in the holding folder in ONE file in the check folder, after a cover; return
    ({relative path: SHA-256}, papers, pages)."""
    for tool in ("pdfinfo", "pdfunite"):
        if shutil.which(tool) is None:
            raise Refusal("Poppler is not installed (" + tool + " not found). On a Mac with Homebrew: brew install "
                          "poppler. Nothing was moved")
    papers = papers_of_a_batch(holding)
    if not papers:
        raise Refusal("no paper was boxed, so there is nothing to look through, and nothing was moved")
    check = Path(check)
    check.mkdir(parents=True, exist_ok=True)
    if (check / COMBINED).exists():
        os.remove(check / COMBINED)
    batch = papers_in(holding)
    pages = 0
    with tempfile.TemporaryDirectory(dir=str(check)) as folder:
        parts = []
        writer = PdfWriter()
        cover(writer, assessment, len(papers))
        writer.write(Path(folder) / "cover.pdf")
        parts.append(str(Path(folder) / "cover.pdf"))
        for index, (label, relative) in enumerate(papers):
            separator = PdfWriter()
            separator.page(b"BT /F1 28 Tf 72 640 Td (%s) Tj ET\n" % pdf_text(label))
            separator.write(Path(folder) / f"caption-{index}.pdf")
            parts += [str(Path(folder) / f"caption-{index}.pdf"), str(Path(holding) / relative)]
            pages += page_count(Path(holding) / relative)
        made = subprocess.run(["pdfunite"] + parts + [str(Path(folder) / "combined.pdf")], capture_output=True)
        if made.returncode != 0:
            raise Refusal("the papers could not be put in one file, so nothing was moved")
        shutil.move(str(Path(folder) / "combined.pdf"), str(check / COMBINED))
    return batch, papers, pages


def move_on_yes(holding, assessment_folder, batch):
    """Move the papers the teacher looked through into '<Assessment>/Redacted', with the record written LAST."""
    if papers_in(holding) != batch:
        raise Refusal("the papers changed after they were put in the file you looked through, so nothing was moved. "
                      "Double-click Box the papers again")
    assessment_folder = Path(assessment_folder)
    record = assessment_folder / RECORD
    redacted = assessment_folder / REDACTED
    if record.exists():
        os.remove(record)
    if redacted.exists() or redacted.is_symlink():
        earlier = assessment_folder / (".earlier redacted papers " + str(os.getpid()))
        os.rename(redacted, earlier)
        if earlier.is_dir() and not earlier.is_symlink():
            shutil.rmtree(earlier)
        else:
            os.remove(earlier)
    redacted.mkdir(parents=True)
    for relative, kind in batch.items():
        if kind == "folder":
            (redacted / relative).mkdir(parents=True, exist_ok=True)
    for relative, kind in batch.items():
        if kind not in ("folder", "link"):
            (redacted / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(Path(holding) / relative), str(redacted / relative))
    moved = papers_in(redacted)
    if moved != batch:
        raise Refusal("the papers did not all arrive as they were, so no yes is recorded for them; double-click Box "
                      "the papers again")
    record.write_text(json.dumps({"looked": datetime.datetime.now().isoformat(timespec="seconds"), "papers": moved},
                                 indent=1), encoding="utf-8")
    shutil.rmtree(holding, ignore_errors=True)


# ---------------------------------------------------------------- the requests the assistant writes


def read_json(path, what):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise Refusal(f"{what} could not be read; ask your assistant to write it again. Nothing was done")
    if not isinstance(value, dict):
        raise Refusal(f"{what} is not in the right shape; ask your assistant to write it again. Nothing was done")
    return value


def plain_folder_name(name):
    """A folder name inside the marking folder: one part, no path, nothing hidden."""
    return (isinstance(name, str) and name.strip() == name and name != "" and not name.startswith(".")
            and "/" not in name and "\\" not in name and ":" not in name and name not in (".", ".."))


def inside_one_folder(relative):
    """A relative path that stays inside the folder it is read from."""
    if not isinstance(relative, str) or relative == "" or relative.startswith(("/", "\\")) or ":" in relative:
        return False
    for part in re.split(r"[/\\]", relative):
        if part in ("", ".", ".."):
            return False
    return True


def box_options(options):
    """The extra options for the boxing script, from the request: only --label, --box and --dpi."""
    if options is None:
        return []
    if not isinstance(options, list) or len(options) % 2 != 0:
        raise Refusal(f"the options in {BOX_REQUEST} are not in pairs; ask your assistant to write it again. "
                      "Nothing was done")
    checked = []
    for index in range(0, len(options), 2):
        flag, value = options[index], options[index + 1]
        if flag not in BOX_OPTIONS or not isinstance(value, str) or value.startswith("--"):
            raise Refusal(f"{BOX_REQUEST} asks for an option the boxing does not take from it ("
                          + ", ".join(BOX_OPTIONS) + " only); ask your assistant to write it again. Nothing was done")
        checked += [flag, value]
    return checked


def box_request(marking, ask, say):
    """(assessment name, its request) of an assessment in the marking folder that is ready to box."""
    ready = []
    for entry in sorted(Path(marking).iterdir(), key=lambda path: natural(path.name)):
        if entry.is_dir() and not entry.is_symlink() and plain_folder_name(entry.name) and (entry / BOX_REQUEST).is_file():
            ready.append(entry.name)
    if not ready:
        raise Refusal("no assessment in this marking folder is ready to box yet: ask your assistant to set up the "
                      "boxing first. Nothing was done")
    chosen = ready[0]
    if len(ready) > 1:
        for number, name in enumerate(ready, start=1):
            say(f"  {number}. {name}")
        answer = ask("Which assessment's papers? Type its number and press Return: ")
        if answer is None or not answer.strip().isdigit() or not 1 <= int(answer.strip()) <= len(ready):
            raise Refusal("no assessment was chosen; nothing was done")
        chosen = ready[int(answer.strip()) - 1]
    return chosen, read_json(Path(marking) / chosen / BOX_REQUEST, BOX_REQUEST)


def runner_command(teacher_only, marking, command):
    return [sys.executable, "-I", "-B", str(RUNNER), "--table", str(teacher_only / TABLE), "--watch", str(marking),
            "--quarantine", str(teacher_only / QUARANTINE), "--"] + command


def walled(command, writable):
    """On a Mac, the command run so that it can write only into the given folders and the temporary folder
    (750d review M1): sandbox-exec, with a profile that denies every write and allows those. Elsewhere, the
    command as it is (the snapshot in a_boxing_step still catches writes into either folder)."""
    sandbox = "/usr/bin/sandbox-exec"
    if sys.platform != "darwin" or not os.path.isfile(sandbox):
        return command
    folders = [os.path.realpath(str(folder)) for folder in writable]
    folders += [os.path.realpath(tempfile.gettempdir()), "/dev"]
    allowed = ""
    for folder in folders:
        allowed += ' (subpath "' + folder.replace("\\", "\\\\").replace('"', '\\"') + '")'
    return [sandbox, "-p", "(version 1)(allow default)(deny file-write*)(allow file-write*" + allowed + ")"] + command


def written_state(folder, leave_out):
    """{path: (kind, size, time)} of every entry under the folder but those under leave_out; links not followed."""
    state = {}
    for top, folders, files in os.walk(folder, followlinks=False):
        for name in folders + files:
            path = Path(top) / name
            if any(path == skipped or skipped in path.parents for skipped in leave_out):
                continue
            try:
                info = path.lstat()
            except OSError:
                continue
            kind = "link" if path.is_symlink() else ("folder" if path.is_dir() else "file")
            state[path] = (kind, info.st_size if kind == "file" else 0, info.st_mtime_ns if kind == "file" else 0)
    return state


def a_boxing_step(script_command, allowed, teacher_only, marking, assessment, say, said):
    """Run one step of the adapted boxing script through the runner, walled on a Mac to that assessment's folder
    on the teacher's side; then move anything it wrote outside `allowed` (in the marking folder or the
    teacher-only folder) to the teacher's Quarantine, unread and never deleted, and stop when there was any."""
    quarantine = teacher_only / QUARANTINE
    allowed = [Path(path) for path in allowed] + [quarantine]
    before = {**written_state(marking, []), **written_state(teacher_only, allowed)}
    code = run_and_say(runner_command(teacher_only, marking, walled(script_command, [teacher_only / assessment])),
                       teacher_only, say, said)
    after = {**written_state(marking, []), **written_state(teacher_only, allowed)}
    strays = []
    for path, state in sorted(after.items()):
        if before.get(path) == state or (state[0] == "folder" and path in before):
            continue
        if any(other in path.parents for other in strays):
            continue
        strays.append(path)
    if strays:
        held = quarantine / ("From the boxing " + datetime.datetime.now().strftime("%Y-%m-%d %H.%M.%S"))
        for path in strays:
            side, root = ("marking folder", marking) if inside(path, marking) else ("teacher-only folder", teacher_only)
            target = held / side / path.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(target))
        raise Refusal(f"the boxing script wrote {len(strays)} things outside the folder it was given; they were moved, "
                      f"unread, to the {QUARANTINE} folder in {THE_FOLDER}, and nothing was put together for you to "
                      "look through or moved. Tell your assistant the boxing script needs looking at")
    return code


def run_and_say(command, teacher_only, say, said):
    """Run a command with its output captured, and pass on its lines with the teacher-only folder's path put back
    as 'your teacher-only folder'. Returns its exit code."""
    result = subprocess.run(command, capture_output=True)
    output = (result.stdout + result.stderr).decode("utf-8", "replace")
    for line in hide_the_folder(output, teacher_only).splitlines():
        say(line)
        said.append(line)
    return result.returncode


def write_what_it_said(path, said, teacher_only):
    text = hide_the_folder("\n".join(said) + "\n", teacher_only)
    Path(path).write_text(text, encoding="utf-8")


def open_for_the_teacher(path):
    if os.environ.get(NO_OPEN):
        return
    try:
        if sys.platform == "darwin":
            subprocess.run(["open", str(path)], capture_output=True)
        elif os.name == "nt":
            os.startfile(str(path))
    except OSError:
        pass


def a_whole_class_first(request, teacher_only, assessment, marking, script, say, said):
    """A whole class scanned in one file: split it, wait for the teacher's paper column, then name the papers.
    Returns True when the boxing may go on."""
    whole = request.get("wholeClass")
    if whole is None:
        return True
    if not isinstance(whole, dict) or not inside_one_folder(whole.get("file", "")) \
            or not isinstance(whole.get("pagesPerPaper"), int) or not isinstance(whole.get("section"), int):
        raise Refusal(f"the whole-class part of {BOX_REQUEST} is not in the right shape; ask your assistant to write "
                      "it again. Nothing was done")
    into = teacher_only / assessment / ORIGINALS / f"Section {whole['section']}"
    numbered = sorted(into.glob("Paper *.pdf")) if into.is_dir() else []
    named = [path for path in (into.iterdir() if into.is_dir() else []) if IDENTIFIER.match(path.stem)]
    if not numbered and not named:
        stack = teacher_only / assessment / whole["file"]
        if not stack.is_file():
            raise Refusal(f"the whole-class scan is not in {THE_FOLDER} yet (put it in the '{assessment}' folder "
                          "there, named as your assistant said). Nothing was done")
        a_boxing_step([sys.executable, "-B", str(script), "--stack", str(stack), "--pages-per-paper",
                       str(whole["pagesPerPaper"]), "--into", str(into), "--check-dir",
                       str(teacher_only / assessment / CHECK)], [into, teacher_only / assessment / CHECK],
                      teacher_only, marking, assessment, say, said)
        say("Fill in the paper column of your name mapping table from 'Papers to name.pdf' in the Check folder, then "
            "double-click Box the papers again. Nothing was boxed yet.")
        return False
    if numbered:
        code = a_boxing_step([sys.executable, "-B", str(script), "--name-papers", str(teacher_only / TABLE),
                              "--section", str(whole["section"]), "--into", str(into)], [into],
                             teacher_only, marking, assessment, say, said)
        if code != 0:
            say("Some papers could not be named from your table. Fix the paper column, then double-click Box the "
                "papers again. Nothing was boxed yet.")
            return False
    return True


# ---------------------------------------------------------------- the two steps


def box(marking, ask, say):
    """Box the papers: everything up to the teacher's yes happens on the teacher's side."""
    marking = Path(marking).resolve()
    the_marking_folder_is_usable(marking)
    the_marking_files_are_as_shipped(marking)
    assessment, request = box_request(marking, ask, say)
    script = request.get("script", "Scripts/redact_scans.py")
    if not inside_one_folder(script) or not (marking / script).is_file() or not inside(marking / script, marking / "Scripts"):
        raise Refusal(f"the boxing script named in {BOX_REQUEST} is not in the Scripts folder; ask your assistant to "
                      "copy it there. Nothing was done")
    script = (marking / script).resolve()
    blank = request.get("blank")
    if not isinstance(blank, str) or not blank:
        raise Refusal(f"{BOX_REQUEST} does not say where the blank test is; ask your assistant. Nothing was done")
    blank = Path(blank) if Path(blank).is_absolute() else marking / blank
    if not blank.is_file():
        raise Refusal("the blank test is not where your assistant said; ask your assistant. Nothing was done")
    options = box_options(request.get("options"))
    say(f"Box the papers: {assessment}.")
    show_the_privacy_points(marking / assessment, ask, say)
    teacher_only = ask_for_the_teacher_only_folder(marking, ask, say)
    if inside(blank, teacher_only):
        raise Refusal(f"the blank test must not be in {THE_FOLDER}; ask your assistant. Nothing was done")
    originals = teacher_only / assessment / ORIGINALS
    if not originals.is_dir():
        originals.mkdir(parents=True)
        raise Refusal(f"there were no scans for {assessment} yet, so I made the folder for them: put each paper, named "
                      f"Student A.pdf and so on, in '{assessment}/{ORIGINALS}/Section 1' (one Section folder per "
                      f"class) in {THE_FOLDER}, then double-click again. Nothing was done")
    said = []
    try:
        whole_class_done = a_whole_class_first(request, teacher_only, assessment, marking, script, say, said)
    except Refusal as refusal:
        said.append(f"Stopped: {refusal}")
        write_what_it_said(marking / assessment / BOX_SAID, said, teacher_only)
        raise
    if not whole_class_done:
        write_what_it_said(marking / assessment / BOX_SAID, said, teacher_only)
        return 1
    holding = teacher_only / assessment / HOLDING
    say("Boxing the papers. This takes a few seconds a paper.")
    try:
        a_boxing_step([sys.executable, "-B", str(script), str(originals), str(holding), "--blank", str(blank)] + options,
                      [holding], teacher_only, marking, assessment, say, said)
        batch, papers, pages = prepare(holding, teacher_only / assessment / CHECK, assessment)
    except Refusal as refusal:
        said.append(f"Stopped: {refusal}")
        write_what_it_said(marking / assessment / BOX_SAID, said, teacher_only)
        raise
    line = (f"{len(papers)} papers, {pages} pages, are in one file for you to look through: '{COMBINED}', in the "
            f"'{CHECK}' folder of '{assessment}' in {THE_FOLDER}. Its first page says what to look for.")
    say(line)
    said.append(line)
    open_for_the_teacher(teacher_only / assessment / CHECK / COMBINED)
    say(LOOK_FOR)
    while True:
        answer = ask(ASK_YES)
        if answer is None or answer.strip().casefold() in ("no", "n"):
            line = (f"Nothing was moved: no paper is in the folder your assistant reads. Tell your assistant the "
                    "identifier and page where something shows (never the name). Rescan that paper, or ask your "
                    "assistant to move the box, then double-click Box the papers again.")
            say(line)
            said.append("The teacher did not type yes. " + line)
            write_what_it_said(marking / assessment / BOX_SAID, said, teacher_only)
            return 1
        if answer.strip().casefold() == "yes":
            break
        say("Please type yes or no.")
    move_on_yes(holding, marking / assessment, batch)
    line = (f"The teacher typed yes. Moved the {len(papers)} papers into '{assessment}/{REDACTED}' in the marking "
            "folder. Tell your assistant they are ready.")
    say(line)
    said.append(line)
    write_what_it_said(marking / assessment / BOX_SAID, said, teacher_only)
    return 0


# Each kind of names request: what it is called, whether it writes named files (and so asks for a yes), the
# folder it reads in the marking folder, and the arguments for make_named_copies.py. 750c's --document and
# --grades are here so that its merge needs no change to this file.
def names_steps(request, marking, teacher_only):
    table = str(teacher_only / TABLE)
    kind = request.get("do")
    if kind == "check-table":
        return "check your name mapping table (counts only)", False, [["--check-table", "--table", table]]
    if kind in ("sheets", "document", "grades"):
        assessment = request.get("assessment")
        if not plain_folder_name(assessment) or not (marking / assessment).is_dir():
            raise Refusal(f"{NAMES_REQUEST} names an assessment that is not in the marking folder; ask your assistant. "
                          "Nothing was done")
        out = str(teacher_only / assessment / NAMED)
        if kind == "sheets":
            return (f"put the names on the feedback sheets of {assessment}, into '{assessment}/{NAMED}' in {THE_FOLDER}",
                    True, [["--table", table, "--sheets", str(marking / assessment / "Sheets"), "--out", out]])
        file = request.get("file")
        if not inside_one_folder(file) or not (marking / assessment / file).is_file():
            raise Refusal(f"{NAMES_REQUEST} names a file that is not in {assessment}; ask your assistant. Nothing was done")
        flag = "--document" if kind == "document" else "--grades"
        return (f"put the names on {Path(file).name} of {assessment}, into '{assessment}/{NAMED}' in {THE_FOLDER}",
                True, [[flag, str(marking / assessment / file), "--table", table, "--out", out]])
    if kind in ("comment-facts", "comments"):
        term = request.get("term")
        folder = f"{term} Comments" if isinstance(term, str) else ""
        if not plain_folder_name(term) or not (marking / folder).is_dir():
            raise Refusal(f"{NAMES_REQUEST} names a term whose comments folder is not in the marking folder; ask your "
                          "assistant. Nothing was done")
        if kind == "comment-facts":
            if (marking / folder / NOTES).is_file():
                if (marking / folder / CHECKED_NOTES).is_file():
                    os.remove(marking / folder / CHECKED_NOTES)
                raise Refusal(f"your notes are in '{folder}' in the marking folder, where your assistant could read them "
                              f"before they are checked. Move '{NOTES}' into a '{folder}' folder in {THE_FOLDER}, then "
                              "double-click again. Nothing was done")
            steps = [["--longest-first-name", "--table", table]]
            what = ("find the length of the longest first name in your table (a number, never the name), and check "
                    f"'{folder}/{NOTES}' in {THE_FOLDER}, if you wrote one, before a copy of it is given to your assistant")
            return what, False, steps
        limit = request.get("limit")
        count = request.get("count", "characters")
        if not isinstance(limit, int) or limit < 1 or count not in ("characters", "bytes"):
            raise Refusal(f"{NAMES_REQUEST} gives no limit, or an unknown way to count; ask your assistant. Nothing "
                          "was done")
        return (f"put the first names into the {term} report comments, into '{folder}/{NAMED}' in {THE_FOLDER}", True,
                [["--comments", str(marking / folder / "Comments.json"), "--table", table, "--out",
                  str(teacher_only / folder / NAMED), "--limit", str(limit), "--count", count]])
    raise Refusal(f"{NAMES_REQUEST} asks for something this step does not do; ask your assistant. Nothing was done")


def names(marking, ask, say):
    """Put names on the sheets, and the other steps that read the name mapping table."""
    marking = Path(marking).resolve()
    the_marking_folder_is_usable(marking)
    the_marking_files_are_as_shipped(marking)
    if not (marking / NAMES_REQUEST).is_file():
        raise Refusal("your assistant has not asked for a step that needs names yet. Nothing was done")
    request = read_json(marking / NAMES_REQUEST, NAMES_REQUEST)
    script = marking / "Scripts" / "make_named_copies.py"
    if not script.is_file():
        raise Refusal("make_named_copies.py is not in the Scripts folder; ask your assistant to copy it there. "
                      "Nothing was done")
    what, writes_names, _steps = names_steps(request, marking, Path(THE_FOLDER))   # checks the request first
    say(f"Put names on the sheets: this will {what}.")
    if request.get("do") in ("comment-facts", "comments"):
        show_the_privacy_points(marking / f"{request['term']} Comments", ask, say, points=COMMENT_POINTS)
    teacher_only = ask_for_the_teacher_only_folder(marking, ask, say)
    what, writes_names, steps = names_steps(request, marking, teacher_only)
    if writes_names:
        while True:
            answer = ask("Type yes to go ahead, or no to stop: ")
            if answer is None or answer.strip().casefold() in ("no", "n"):
                say("Nothing was done.")
                write_what_it_said(marking / NAMES_SAID, [f"Asked: {request.get('do')}.", "The teacher did not go ahead. "
                                                          "Nothing was done."], teacher_only)
                return 1
            if answer.strip().casefold() == "yes":
                break
            say("Please type yes or no.")
    said = [f"Asked: {request.get('do')}, {datetime.datetime.now().isoformat(timespec='seconds')}."]
    worst = 0
    for arguments in steps:
        code = run_and_say(runner_command(teacher_only, marking, [sys.executable, "-B", str(script)] + arguments),
                           teacher_only, say, said)
        worst = max(worst, code)
    if request.get("do") == "comment-facts":
        worst = max(worst, release_the_notes(teacher_only, marking, f"{request['term']} Comments", say, said))
    line = (f"Done. What it said is in '{NAMES_SAID}' in the marking folder, for your assistant to read. Nothing in "
            f"{THE_FOLDER} is shown to your assistant.")
    say(line)
    said.append("Done.")
    write_what_it_said(marking / NAMES_SAID, said, teacher_only)
    return worst


def the_name_comparison():
    """The runner's own comparison (pinned beside this file, checked by the launcher), so the decision to release
    the teacher's notes is made by never-adapted code."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("run_with_names_pinned", str(RUNNER))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def release_the_notes(teacher_only, marking, folder, say, said):
    """The teacher's notes, kept in the teacher-only folder, reach the marking folder only as a checked copy that
    begins with a record of the check and the SHA-256 of the notes it came from. Any old copy goes first, so a
    copy that exists is a copy of notes that passed. Returns 0, or 1 when the notes hold a word from the table."""
    source = teacher_only / folder / NOTES
    checked = marking / folder / CHECKED_NOTES
    if checked.exists() or checked.is_symlink():
        os.remove(checked)
    if not source.is_file():
        line = f"No '{NOTES}' in '{folder}' in {THE_FOLDER}, so no notes were given to your assistant."
        say(line)
        said.append(line)
        return 0
    runner = the_name_comparison()
    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        raise Refusal(f"your notes could not be read as text; save '{NOTES}' as plain text and double-click again")
    names = runner.tokens_from(runner.read_rows(teacher_only / TABLE))
    lines = text.splitlines()
    held = []
    for number, line in enumerate(lines, start=1):
        if runner.holds_any_form(line, names):
            held.append(number)
    if held:
        line = (f"A word from your name table is on {len(held)} line(s) of your notes (line "
                + ", ".join(str(number) for number in held) + "). It may be a name, or an everyday word that is also a "
                "name. Change those lines, then double-click again. Your notes were NOT given to your assistant.")
        say(line)
        said.append(line)
        return 1
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    record = (f"{CHECKED_MARK}, {datetime.datetime.now().isoformat(timespec='seconds')}: no line holds a word from the "
              f"name table. SHA-256 of the notes it came from: {digest}. It cannot see a nickname, initials or a name "
              "that is not in the table. -->")
    checked.write_text(record + "\n" + text + ("" if text.endswith("\n") else "\n"), encoding="utf-8")
    line = (f"Your notes held no word from your name table, so a checked copy is in '{folder}/{CHECKED_NOTES}' in the "
            "marking folder for your assistant. A nickname, initials or a name that is not in your table cannot be "
            "seen by the check: read your notes once yourself.")
    say(line)
    said.append(line)
    return 0


def tidy(assessment):
    """Remove the pictures render_pages.py made while marking, and nothing else: each file listed in
    '<Assessment>/Work/Made while marking.txt' that is a plain file inside that Work folder (never a link, never
    through one). Prints counts only, never a path (750d third trial: the old --tidy looked through the system's
    temporary folders by name, printed every folder it matched, a teacher-only folder's name among them, and
    matched over 400 folders that were not the assistant's, so it could never finish). Exit 0 when it is done."""
    assessment = Path(assessment)
    changed = what_was_changed(assessment.resolve().parent)
    if changed:
        # The fourth trial: an edit made after the last teacher step was never seen. --tidy, which the skill
        # requires before the marking is called finished, runs the same check. Counts only, never a path.
        print(f"Not finished: {changed}. Nothing was removed; run this again once it is put right.")
        return 1
    work = assessment / WORK
    if work.is_symlink() or (work.exists() and not work.is_dir()):
        print("Not finished: the assessment's Work folder is not a plain folder, so nothing was removed. Ask the "
              "teacher to look at it.")
        return 1
    if not work.is_dir():
        print("Done: this assessment has no Work folder, so there was nothing to remove. --tidy looks nowhere else: "
              "a copy made anywhere else, and anything already sent to the AI service, cannot be found by it.")
        return 0
    real_work = Path(os.path.realpath(str(work)))
    listed = work / MADE
    entries = []
    if listed.is_file() and not listed.is_symlink():
        try:
            entries = listed.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            print("Not finished: the list of what was made could not be read, so nothing was removed. Ask the teacher "
                  "to look at the Work folder.")
            return 1
    removed, gone, refused, failed = 0, 0, 0, 0
    folders = set()
    for entry in entries:
        if not entry.strip():
            continue
        if not inside_one_folder(entry):
            refused += 1
            continue
        path = work / entry
        through_a_link = False
        for parent in [path] + list(path.parents):
            if parent == work:
                break
            if parent.is_symlink():
                through_a_link = True
                break
        if through_a_link:
            refused += 1
            continue
        if not path.exists():
            gone += 1
            continue
        if not path.is_file() or not inside(path, real_work):
            refused += 1
            continue
        try:
            os.remove(path)
            removed += 1
            folders.add(path.parent)
        except OSError:
            failed += 1
    for folder in sorted(folders, key=lambda folder: len(folder.parts), reverse=True):
        try:
            if folder != work and inside(folder, real_work) and not folder.is_symlink() and not any(folder.iterdir()):
                os.rmdir(folder)
        except OSError:
            pass
    if failed == 0 and listed.is_file() and not listed.is_symlink():
        os.remove(listed)
    left = 0
    for _top, _folders, files in os.walk(work, followlinks=False):
        left += len(files)
    summary = f"Removed {removed} pictures the marking made in the Work folder"
    if gone:
        summary += f"; {gone} listed were already gone"
    if refused:
        summary += f"; {refused} listed lines were not a picture inside the Work folder, so they were left alone"
    summary += (f". {left} other files are in the Work folder, which the marking did not list; they were left where "
                "they are, inside the marking folder.") if left else "."
    if failed:
        print(f"Not finished: {failed} listed pictures could not be removed. {summary} Ask the teacher to remove the "
              "Work folder's pictures, then run this again.")
        return 1
    print(f"Done. {summary} --tidy looks nowhere else: a copy made anywhere else (the system's temporary folder "
          "included), and anything already sent to the AI service, cannot be found by it.")
    return 0


# ---------------------------------------------------------------- the command line


def interactive_input(prompt):
    try:
        return input(prompt)
    except EOFError:
        return None


def main(arguments):
    if len(arguments) == 2 and arguments[0] == "--verify":
        return verify(arguments[1])
    if len(arguments) == 2 and arguments[0] == "--points-shown":
        return points_shown(arguments[1])
    if len(arguments) >= 2 and arguments[0] == "--tidy":
        return tidy(arguments[1])   # anything after it (an earlier copy's --look-in) is not used
    if len(arguments) != 2 or arguments[0] not in ("box", "names"):
        print(__doc__)
        return 0
    if not sys.stdin.isatty():
        raise Refusal("this step is for the teacher to run by double-clicking it, in its own window. Nothing was done")
    step = box if arguments[0] == "box" else names
    title = "Box the papers" if arguments[0] == "box" else "Put names on the sheets"
    stale = Path(arguments[1], title + LAST_STOP)
    if stale.is_file():
        os.remove(stale)   # what a last stop said is about that run only
    return step(arguments[1], interactive_input, print)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        stop = f"Stopped: {refusal}."
        print(stop)
        print("Tell your assistant this Stopped line, word for word: it holds no name, and it says what to put right.")
        if len(sys.argv) == 3 and sys.argv[1] in ("box", "names") and os.path.isdir(sys.argv[2]):
            title = "Box the papers" if sys.argv[1] == "box" else "Put names on the sheets"
            try:
                Path(sys.argv[2], title + LAST_STOP).write_text(stop + "\n", encoding="utf-8")
            except OSError:
                pass
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nStopped. Nothing more was done.")
        sys.exit(1)
    except Exception as error:   # never a traceback: it could carry a path holding a name
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}). No paper was moved unless this "
              "window said so.")
        sys.exit(1)
