#!/usr/bin/env python3
"""The teacher's own steps: the two that touch the teacher-only folder, run by the TEACHER, never the assistant.

Part of the plantoir-marking skill, and NOT a starting point: it is never copied, adapted or changed. The
two launchers in the marking folder ("Box the papers" and "Put names on the sheets", a .command on a Mac and
a .bat on Windows) check its SHA-256 and the runner's before they run it, and the skill names all of them.

    python3 -I -B teacher_only.py box MARKING_FOLDER       (run by "Box the papers", in the teacher's window)
    python3 -I -B teacher_only.py names MARKING_FOLDER     (run by "Put names on the sheets")
    python3 -I -B teacher_only.py --verify "<marking folder>/<Assessment>"   (the assistant, before any read)

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
#   stops; and it never says a name is covered, removed or safe.

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
IDENTIFIER = re.compile(r"^Student [A-Z]{1,2}$")
SECTION = re.compile(r"^Section \d+$")
NO_OPEN = "PLANTOIR_MARKING_NO_OPEN"     # set only by the repository's tests, so a test run opens no window
THE_FOLDER = "your teacher-only folder"
BOX_OPTIONS = ("--label", "--box", "--dpi", "--identifiers")

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
COVER_INTRODUCTION = ("Your assistant was asked to tell you these four things before it read any paper. They are "
                      "printed here so that you read them whichever assistant you use:")
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
    or the teacher closed it."""
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


def verify(assessment):
    """Exit 0 only when '<Assessment>/Redacted' holds exactly the papers the teacher typed yes for."""
    assessment = Path(assessment)
    record_path = assessment / RECORD
    now = papers_in(assessment / REDACTED)
    if record_path.is_file() and now:
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
    """The extra options for the boxing script, from the request: only --label, --box, --dpi, --identifiers."""
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
    if inside_a_working_folder(marking):
        raise Refusal("this marking folder is inside the Plantoir working folder; marking is kept outside it. "
                      "Nothing was done")
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
            steps = [["--longest-first-name", "--table", table]]
            what = "find the length of the longest first name in your table (a number, never the name)"
            if (marking / folder / "Teacher Notes.md").is_file():
                steps.append(["--check-file", str(marking / folder / "Teacher Notes.md"), "--table", table])
                what += ", and check your Teacher Notes for any word from your table (by line number only)"
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
    if inside_a_working_folder(marking):
        raise Refusal("this marking folder is inside the Plantoir working folder; marking is kept outside it. "
                      "Nothing was done")
    if not (marking / NAMES_REQUEST).is_file():
        raise Refusal("your assistant has not asked for a step that needs names yet. Nothing was done")
    request = read_json(marking / NAMES_REQUEST, NAMES_REQUEST)
    script = marking / "Scripts" / "make_named_copies.py"
    if not script.is_file():
        raise Refusal("make_named_copies.py is not in the Scripts folder; ask your assistant to copy it there. "
                      "Nothing was done")
    what, writes_names, _steps = names_steps(request, marking, Path(THE_FOLDER))   # checks the request first
    say(f"Put names on the sheets: this will {what}.")
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
    line = (f"Done. What it said is in '{NAMES_SAID}' in the marking folder, for your assistant to read. Nothing in "
            f"{THE_FOLDER} is shown to your assistant.")
    say(line)
    said.append("Done.")
    write_what_it_said(marking / NAMES_SAID, said, teacher_only)
    return worst


# ---------------------------------------------------------------- the command line


def interactive_input(prompt):
    try:
        return input(prompt)
    except EOFError:
        return None


def main(arguments):
    if len(arguments) == 2 and arguments[0] == "--verify":
        return verify(arguments[1])
    if len(arguments) != 2 or arguments[0] not in ("box", "names"):
        print(__doc__)
        return 0
    if not sys.stdin.isatty():
        raise Refusal("this step is for the teacher to run by double-clicking it, in its own window. Nothing was done")
    step = box if arguments[0] == "box" else names
    return step(arguments[1], interactive_input, print)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}.")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nStopped. Nothing more was done.")
        sys.exit(1)
    except Exception as error:   # never a traceback: it could carry a path holding a name
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}). No paper was moved unless this "
              "window said so.")
        sys.exit(1)
