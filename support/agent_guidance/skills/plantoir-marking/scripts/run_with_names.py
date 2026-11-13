#!/usr/bin/env python3
"""Run a script that reads the name mapping table, and stop any name it lets out from reaching the assistant.

Part of the plantoir-marking skill, and the one script in it that is NOT a starting point: run it from the
skill folder, and never copy, adapt or change it (Plantoir puts the skill folder back as it shipped).
Every script that reads the mapping table is run through it, the adapted ones above all:

    python3 -B <skill>/scripts/run_with_names.py --table TABLE --watch "<marking folder>"
        --quarantine "<teacher-only folder>/Quarantine" -- python3 -B "<marking folder>/Scripts/make_named_copies.py" ...

It reads the table itself and builds every form a name could take (each part of the name of two letters
or more, the first name column, the whole name, the parts run together, first initial and last name,
each e-mail address and the part before its @, each handle, the user and repository in a repository
address), then runs the command with everything it prints captured:
  - a printed line that holds any of them is withheld, and counted;
  - every file the command creates or changes in the watched (marking) folder is read (a PDF through
    pdftotext when Poppler is here) and, if it holds any of them or its path does, moved to the
    quarantine folder on the teacher's side, and counted.
It prints the lines that hold none, then one closing line of counts. It exits 1 if anything was withheld
or moved, and otherwise with the command's own exit code.

It is a safety net, not a guarantee. It catches the names in the table, and only in what the command
prints and what it writes in the watched folder. It cannot know a nickname, a family member's name or
a name the table does not hold, it cannot see what a picture shows, and it cannot stop a script that is
run without it or that writes somewhere else. Python standard library only.
"""
import csv
import os
import re
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path

# MARK: - What must not change
#   This file is never adapted. It never prints, logs or writes any value read from the table; it never
#   prints a withheld line or the path of a quarantined file; it prints counts only about what it caught.

NAME_COLUMNS = ("name", "first name", "preferred name", "last name", "surname")
EMAIL_COLUMNS = ("email", "e-mail")
HANDLE_COLUMNS = ("handles", "handle", "username", "github")
REPOSITORY_COLUMNS = ("repository", "repo")
MINIMUM_LENGTH = 2


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding no value from the table."""


def folded(text):
    return unicodedata.normalize("NFC", text).casefold()


def read_rows(path):
    try:
        with open(path, newline="", encoding="utf-8-sig") as handle:
            first_line = handle.readline()
            handle.seek(0)
            reader = csv.DictReader(handle, dialect="excel-tab" if "\t" in first_line else "excel")
            rows = []
            for row in reader:
                cleaned = {}
                for key in row:
                    if key is not None:
                        cleaned[key.strip().casefold()] = (row[key] or "").strip()
                rows.append(cleaned)
            return rows
    except (OSError, UnicodeDecodeError, csv.Error):
        raise Refusal("the mapping table could not be read")


def tokens_from(rows):
    """(whole-word tokens, anywhere tokens): every form a name in the table could take, case-folded."""
    words = set()
    anywhere = set()
    for row in rows:
        parts = []
        for column in NAME_COLUMNS:
            value = row.get(column, "")
            if not value:
                continue
            anywhere.add(folded(value))
            for part in re.split(r"[\s,]+", value):
                part = part.strip(".'\"()")
                if len(part) >= MINIMUM_LENGTH:
                    parts.append(part)
                    words.add(folded(part))
                    for piece in re.split(r"[-']", part):
                        if len(piece) >= MINIMUM_LENGTH:
                            words.add(folded(piece))
        unique = []
        for part in parts:
            if folded(part) not in [folded(seen) for seen in unique]:
                unique.append(part)
        for first in unique:
            for second in unique:
                if first != second:
                    anywhere.add(folded(first + second))
                    anywhere.add(folded(first[0] + second))
                    for joiner in (".", "-", "_"):
                        anywhere.add(folded(first + joiner + second))
        for column in EMAIL_COLUMNS:
            value = row.get(column, "")
            if "@" in value:
                anywhere.add(folded(value))
                local = value.split("@")[0]
                if len(local) >= 3:
                    anywhere.add(folded(local))
                    anywhere.add(folded(local.split("+")[-1]))
        for column in HANDLE_COLUMNS:
            for handle in re.split(r"[\s,;]+", row.get(column, "")):
                handle = handle.strip("@")
                if len(handle) >= 3:
                    anywhere.add(folded(handle))
        for column in REPOSITORY_COLUMNS:
            address = row.get(column, "")
            match = re.search(r"(?:github\.com|gitlab\.com|bitbucket\.org)[/:]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", address)
            if match:
                for piece in match.groups():
                    if len(piece) >= 3:
                        anywhere.add(folded(piece))
            elif address:
                anywhere.add(folded(address))
    return words, anywhere


def holds_a_name(text, words, anywhere):
    text = folded(text)
    for token in anywhere:
        if token and token in text:
            return True
    for word in re.findall(r"\w+", text):
        if word in words:
            return True
    return False


def snapshot(folder):
    state = {}
    for path in Path(folder).rglob("*"):
        if path.is_file():
            try:
                info = path.stat()
            except OSError:
                continue
            state[path] = (info.st_size, info.st_mtime_ns)
    return state


def readable_text(path):
    if path.suffix.lower() == ".pdf":
        if shutil.which("pdftotext") is None:
            return None
        result = subprocess.run(["pdftotext", str(path), "-"], capture_output=True)
        return result.stdout.decode("utf-8", "replace")
    try:
        return path.read_bytes().decode("utf-8", "replace")
    except OSError:
        return None


def inside(path, folder):
    path = Path(path).resolve()
    folder = Path(folder).resolve()
    return path == folder or folder in path.parents


def main(arguments):
    if "--" not in arguments:
        print(__doc__)
        return 0
    split = arguments.index("--")
    own, command = arguments[:split], arguments[split + 1:]

    def option(name):
        if name in own and own.index(name) + 1 < len(own):
            return own[own.index(name) + 1]
        raise Refusal(f"give {name}")

    table, watch, quarantine = option("--table"), option("--watch"), option("--quarantine")
    if not command:
        raise Refusal("give the command to run after --")
    if inside(table, watch):
        raise Refusal("the mapping table is inside the marking folder; move it to the teacher-only folder first")
    if inside(quarantine, watch):
        raise Refusal("the quarantine folder must be on the teacher's side, outside the marking folder")
    words, anywhere = tokens_from(read_rows(table))
    if not words and not anywhere:
        raise Refusal("the mapping table holds no names; nothing was run")
    before = snapshot(watch)
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    result = subprocess.run(command, capture_output=True, env=environment)
    output = (result.stdout + result.stderr).decode("utf-8", "replace")
    withheld = 0
    for line in output.splitlines():
        if holds_a_name(line, words, anywhere):
            withheld += 1
        else:
            print(line)
    after = snapshot(watch)
    checked = 0
    moved = 0
    unread = 0
    for path, state in sorted(after.items()):
        if before.get(path) == state:
            continue
        checked += 1
        relative = path.resolve().relative_to(Path(watch).resolve())
        text = readable_text(path)
        if text is None:
            unread += 1
        if holds_a_name(str(relative), words, anywhere) or (text is not None and holds_a_name(text, words, anywhere)):
            target = Path(quarantine) / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(target))
            moved += 1
    summary = (f"run_with_names: {withheld} printed lines held a name and were withheld; {checked} new or changed files "
               f"in the marking folder checked, {moved} held a name and were moved to the quarantine folder")
    if unread:
        summary += f"; {unread} could not be read as text, so were not checked"
    print(summary + ".")
    if withheld or moved:
        print("The script needs fixing before it is used again. The withheld lines and the moved files are not shown here.")
    print("This is a safety net, not a guarantee: it catches the names in your table, in what the script printed "
          "and what it wrote in the marking folder, and nothing else.")
    if withheld or moved:
        return 1
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback: it could carry a value from the table
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); nothing was passed on")
        sys.exit(1)
