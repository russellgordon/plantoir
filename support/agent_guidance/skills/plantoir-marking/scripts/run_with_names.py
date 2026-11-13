#!/usr/bin/env python3
"""Run a script that reads the name mapping table, and stop any name it lets out from reaching the assistant.

Part of the plantoir-marking skill, and the one script in it that is NOT a starting point: run it from the
skill folder, and never copy, adapt or change it (Plantoir puts the skill folder back as it shipped when it
next refreshes the working folder; the skill checks its SHA-256 before use). Every script that reads the
mapping table is run through it, the adapted ones above all:

    python3 -B <skill>/scripts/run_with_names.py --table TABLE --watch "<marking folder>"
        --quarantine "<teacher-only folder>/Quarantine" -- python3 -B "<marking folder>/Scripts/make_named_copies.py" ...

It reads the table itself and builds every form a name could take (each part of the name of two letters
or more, the first name column, the whole name, the parts run together, first initial and last name,
each e-mail address and the part before its @, each handle, the user and repository in a repository
address), and compares without regard to case or accents. Then it runs the command IN the watched folder
(so a file written by a relative path is watched too), with everything it prints captured, and before it
passes anything on:
  - every new or changed file, folder and link in the watched (marking) folder is looked at: its name, and
    what it holds where the standard library can read it (UTF-8 and UTF-16 text, gzip, the members of a zip
    such as an xlsx or docx, a PNG's text chunks, and a PDF's text and metadata through Poppler). One that
    holds a name, or a folder named by one, is moved to the quarantine folder on the teacher's side, a
    folder whole;
  - a file it cannot read (what a picture shows, a PDF Poppler cannot read, a link, anything else) is
    counted by kind as NOT checked and moved to the quarantine folder unread, so it is not opened; a link is
    moved as a link, never followed;
  - a printed line that holds any form of a name is withheld, and counted.
It then prints the lines that hold none, and three counts: read and holding none of the forms of the table's names, holding a form
and moved, and not checked and moved unread. Only folders it made, or wrote into, are moved. It exits 1 if anything was withheld, moved or left unchecked, and otherwise with the
command's own exit code.

It is a safety net, not a guarantee. It catches the names in the table, and only in what the command
prints and what it writes in the watched folder. A folder the script writes into whose own name holds a word from the table (an assessment
folder called June Exam, with a student called June) is moved whole, in the safe direction. It cannot
know a nickname, a family member's name or a
name the table does not hold, see what a picture shows, read a name split up, reversed or encoded, notice
a file rewritten at the same size and time, or stop a script that is run without it or writes somewhere
else. Python standard library only.
"""
import csv
import gzip
import io
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import zipfile
import zlib
from pathlib import Path

# MARK: - What must not change
#   This file is never adapted. It never prints, logs or writes any value read from the table; it never
#   prints a withheld line or the path of a quarantined file; it prints counts only about what it caught.

# >>> The name comparison. ONE copy of the rules, carried byte for byte in run_with_names.py and in
# make_named_copies.py (752 fix review H1: the runner, --check-file and --comments gave different answers on
# 7 of 22 lines); scripts/test_marking_comments.py fails if the two copies differ, and runs all three over one
# corpus. A form of a name counts when it is in the text: every part of a name of two letters or more as a
# whole word (a short part on its own too: a missed name is worse than a false alarm), and every form of six
# letters or more anywhere, inside another word as well. Whole words are found three ways at once: as \w+
# (so an e-mail's local part such as an77 is one word), as runs of letters (so Ivo2, Ivo_notes and
# Mark_feedback give Ivo and Mark), and split where a small letter meets a capital (so AnaLi gives Ana and Li).
NAME_COLUMNS = ("name", "first name", "preferred name", "last name", "surname")
EMAIL_COLUMNS = ("email", "e-mail")
HANDLE_COLUMNS = ("handles", "handle", "username", "github")
REPOSITORY_COLUMNS = ("repository", "repo")
MINIMUM_LENGTH = 2
SHORT_LENGTH = 4                 # a name part shorter than this is counted on its own as "short": it may be a word
ANYWHERE_LENGTH = 6              # a form this long is matched inside other words, too


def without_accents(text):
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(character for character in decomposed if not unicodedata.combining(character))


def folded(text):
    """Case and accents taken off, so Qoë, QOE and qoe are one word."""
    return without_accents(unicodedata.normalize("NFC", text)).casefold()


def tokens_from(rows):
    """Every form a name in the table could take, case and accents taken off, as (words, anywhere, short):

    words     name parts of four letters or more, and short forms built from them, matched as whole words;
    anywhere  forms of six letters or more (every such part, the whole name, the parts run together, an e-mail
              address, a handle), matched anywhere, so a bundle id, a slug or a file name is caught;
    short     name parts of two or three letters (Ho, Ed, Le, Ana), each with the other parts of its name. A
              short part on its own counts (short_part_alone), and is reported apart, since it may be an
              everyday word (750a fix review 2, M4)."""
    words = set()
    anywhere = set()
    short = {}

    def add_anywhere(form):
        form = folded(form)
        if len(form) >= ANYWHERE_LENGTH:
            anywhere.add(form)
        elif len(form) >= MINIMUM_LENGTH:
            words.add(form)

    for row in rows:
        parts = []
        for column in NAME_COLUMNS:
            value = row.get(column, "")
            if not value:
                continue
            add_anywhere(value)
            for part in re.split(r"[\s,]+", value):
                part = part.strip(".'\"()")
                for piece in [part] + re.split(r"[-'’]", part):
                    if len(piece) >= MINIMUM_LENGTH and folded(piece) not in [folded(seen) for seen in parts]:
                        parts.append(piece)
        for part in parts:
            if len(folded(part)) >= SHORT_LENGTH:
                words.add(folded(part))
                if len(folded(part)) >= ANYWHERE_LENGTH:
                    anywhere.add(folded(part))
            else:
                partners = short.setdefault(folded(part), set())
                for other in parts:
                    if folded(other) != folded(part):
                        partners.add(folded(other))
        for first in parts:
            for second in parts:
                if folded(first) != folded(second):
                    add_anywhere(first + second)
                    add_anywhere(first[0] + second)
                    for joiner in (".", "-", "_"):
                        add_anywhere(first + joiner + second)
        for column in EMAIL_COLUMNS:
            value = row.get(column, "")
            if "@" in value:
                add_anywhere(value)
                local = value.split("@")[0]
                add_anywhere(local)
                add_anywhere(local.split("+")[-1])
        for column in HANDLE_COLUMNS:
            for handle in re.split(r"[\s,;]+", row.get(column, "")):
                add_anywhere(handle.strip("@"))
        for column in REPOSITORY_COLUMNS:
            address = row.get(column, "")
            match = re.search(r"(?:github\.com|gitlab\.com|bitbucket\.org)[/:]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", address)
            if match:
                for piece in match.groups():
                    add_anywhere(piece)
            elif address:
                add_anywhere(address)
    return words, anywhere, short


def words_in(text):
    """The whole words of a text, folded, found three ways (see the block's opening comment)."""
    found = set()
    for token in re.findall(r"\w+", text):
        found.add(folded(token))
        for run in re.findall(r"[^\W\d_]+", token):
            found.add(folded(run))
            for piece in re.findall(r"[^\W\d_][^\W\d_A-Z]*", run):
                found.add(folded(piece))
    return found


def holds_a_name(text, names):
    words, anywhere, short = names
    flat = folded(text)
    for token in anywhere:
        if token in flat:
            return True
    found = words_in(text)
    if found & words:
        return True
    for part, partners in short.items():
        if part in found and (found & partners or not partners):
            return True
    return False


def short_part_alone(text, names):
    """True when a name part of two or three letters (Ng, Li, Ho) is in the text as a whole word without the rest
    of its name. It cannot be told from an everyday word, so it is counted, never passed (750a fix review 2, M4)."""
    _words, _anywhere, short = names
    found = words_in(text)
    for part in short:
        if part in found:
            return True
    return False


def holds_any_form(text, names):
    """The one answer all three give: does the text hold any form of a name the table holds?"""
    return holds_a_name(text, names) or short_part_alone(text, names)
# <<< The name comparison.


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding no value from the table."""


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


def snapshot(folder):
    """Every file, folder and link under the folder, not following links: path -> (kind, size, time)."""
    state = {}
    for top, folders, files in os.walk(folder, followlinks=False):
        for name in folders + files:
            path = Path(top) / name
            try:
                info = path.lstat()
            except OSError:
                continue
            if path.is_symlink():
                kind = "link"
            elif path.is_dir():
                kind = "folder"
            else:
                kind = "file"
            state[path] = (kind, info.st_size if kind == "file" else 0, info.st_mtime_ns if kind != "folder" else 0)
    return state


PICTURES = {b"\x89PNG": "a picture (PNG)", b"\xff\xd8\xff": "a picture (JPEG)", b"GIF8": "a picture (GIF)"}


def png_text(data):
    """The text chunks of a PNG (tEXt, zTXt, iTXt), which is where a program writes an author or a title."""
    found = []
    position = 8
    while position + 8 <= len(data):
        length = int.from_bytes(data[position:position + 4], "big")
        kind = data[position + 4:position + 8]
        body = data[position + 8:position + 8 + length]
        if kind == b"tEXt":
            found.append(body.replace(b"\x00", b" ").decode("latin-1"))
        elif kind == b"zTXt" and b"\x00" in body:
            keyword, rest = body.split(b"\x00", 1)
            found.append(keyword.decode("latin-1") + " " + zlib.decompress(rest[1:]).decode("latin-1", "replace"))
        elif kind == b"iTXt" and b"\x00" in body:
            parts = body.split(b"\x00", 2)
            if len(parts) == 3 and len(parts[2]) >= 2:
                compressed = parts[1][:1] == b"\x01"
                rest = parts[2][2:].split(b"\x00", 2)
                text = rest[-1] if rest else b""
                if compressed:
                    text = zlib.decompress(text)
                found.append(parts[0].decode("latin-1") + " " + " ".join(piece.decode("utf-8", "replace") for piece in rest[:-1]) +
                             " " + text.decode("utf-8", "replace"))
        position += 12 + length
    return "\n".join(found)


def text_of(data, name, depth=0):
    """(text, kinds not checked): everything readable in these bytes, and what could not be read."""
    if depth > 3:
        return "", ["something nested too deep to open"]
    if data[:2] == b"\x1f\x8b":
        try:
            return text_of(gzip.decompress(data), name, depth + 1)
        except (OSError, EOFError, zlib.error):
            return "", ["a gzip file that would not open"]
    if data[:4] == b"PK\x03\x04":
        texts = []
        unread = []
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for member in archive.infolist():
                    texts.append(member.filename)
                    if member.is_dir():
                        continue
                    inner, inner_unread = text_of(archive.read(member), member.filename, depth + 1)
                    texts.append(inner)
                    for kind in inner_unread:
                        unread.append(kind + " inside a zip (an xlsx, docx or the like)")
        except (zipfile.BadZipFile, RuntimeError, NotImplementedError, zlib.error):
            return "", ["a zip file that would not open (an xlsx, docx or the like)"]
        return "\n".join(texts), unread
    for signature, kind in PICTURES.items():
        if data.startswith(signature):
            text = ""
            if signature == b"\x89PNG":
                try:
                    text = png_text(data)
                except (zlib.error, ValueError):
                    pass
            return text, [kind + ": what it shows"]
    if data[:5] == b"%PDF-":
        return data.decode("latin-1"), ["PDF"]   # its raw bytes now; its text through Poppler in look_at
    if data[:2] in (b"\xff\xfe", b"\xfe\xff") or (len(data) >= 4 and data.count(b"\x00") > len(data) // 4):
        # UTF-16 with or without its mark, either byte order: search every reading, and the bytes with
        # the NULs taken out (750a fix review M1: big-endian with no mark was read as little-endian).
        readings = [data.replace(b"\x00", b"").decode("latin-1")]
        for encoding in ("utf-16", "utf-16-le", "utf-16-be"):
            readings.append(data.decode(encoding, "replace"))
        return "\n".join(readings), []
    try:
        return data.decode("utf-8"), []
    except UnicodeDecodeError:
        return "", ["a file that is not text (" + (Path(name).suffix.lower() or "no extension") + ")"]


def pdf_text(path):
    """A PDF's text, its metadata and its XMP, through Poppler; None when Poppler is not here or cannot read
    it (broken, or locked by a password): an empty answer is never taken for "nothing in it"."""
    if shutil.which("pdftotext") is None or shutil.which("pdfinfo") is None:
        return None
    pieces = []
    for command in (["pdftotext", str(path), "-"], ["pdfinfo", str(path)], ["pdfinfo", "-meta", str(path)]):
        result = subprocess.run(command, capture_output=True)
        if result.returncode != 0:
            return None
        pieces.append(result.stdout.decode("utf-8", "replace"))
    return "\n".join(pieces)


def look_at(path, kind):
    """(text to search, kinds not checked) for one new or changed thing in the watched folder."""
    if kind == "folder":
        return "", []
    if kind == "link":
        return "", ["a link (where it points was not read)"]
    try:
        data = path.read_bytes()
    except OSError:
        return "", ["a file that could not be opened"]
    text, unread = text_of(data, path.name)
    if "PDF" in unread:
        unread.remove("PDF")
        found = pdf_text(path)
        if found is None:
            unread.append("a PDF Poppler could not read (not installed, broken or locked)")
        else:
            text += "\n" + found
    return text, unread


def inside(path, folder):
    path = Path(path).resolve()
    folder = Path(folder).resolve()
    return path == folder or folder in path.parents


def in_a_working_folder(path):
    path = Path(path).resolve()
    for folder in [path] + list(path.parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            return True
    return False


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
    if not Path(watch).is_dir():
        raise Refusal("the marking folder to watch is not there")
    if inside(table, watch):
        raise Refusal("the mapping table is inside the marking folder; move it to the teacher-only folder first")
    if inside(quarantine, watch):
        raise Refusal("the quarantine folder must be on the teacher's side, outside the marking folder")
    if in_a_working_folder(watch) or in_a_working_folder(quarantine):
        raise Refusal("a folder given is inside the Plantoir working folder; marking is kept outside it")
    names = tokens_from(read_rows(table))
    if not names[0] and not names[1] and not names[2]:
        raise Refusal("the mapping table holds no names; nothing was run")
    before = snapshot(watch)
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    result = subprocess.run(command, capture_output=True, env=environment, cwd=watch)
    output = (result.stdout + result.stderr).decode("utf-8", "replace")
    # Everything is looked at BEFORE anything is passed on, so a failure here passes nothing on.
    after = snapshot(watch)
    changed = [path for path, state in sorted(after.items()) if before.get(path) != state]
    named_folders = []
    for path, state in sorted(after.items()):
        if state[0] != "folder" or not holds_a_name(path.name, names):
            continue
        touched = path in changed or any(path in other.parents for other in changed)
        if touched and not any(folder in path.parents for folder in named_folders):
            # a new folder named by a word from the table, or an old one this run wrote into; an old folder
            # the script left alone stays where it is (750a fix review M3: "June Exam")
            named_folders.append(path)
    clean = 0
    moving = list(named_folders)
    unread_paths = []
    short_files = []
    unread = {}
    for path in changed:
        if after[path][0] == "folder" or any(folder in path.parents for folder in named_folders):
            continue
        text, kinds = look_at(path, after[path][0])
        relative = str(path.relative_to(Path(watch)))
        if holds_a_name(relative, names) or holds_a_name(text, names):
            moving.append(path)
            continue
        if short_part_alone(relative, names) or short_part_alone(text, names):
            short_files.append(path)
            continue
        if kinds:
            for kind in kinds:
                unread[kind] = unread.get(kind, 0) + 1
            unread_paths.append(path)
            continue
        clean += 1
    held_files = 0
    held_folders = 0
    for path in moving + unread_paths + short_files:
        target = Path(quarantine) / path.relative_to(Path(watch))
        target.parent.mkdir(parents=True, exist_ok=True)
        if path in moving:
            if path.is_dir() and not path.is_symlink():
                held_folders += 1
            else:
                held_files += 1
        shutil.move(str(path), str(target))   # a link is moved as a link, never followed
    withheld = 0
    short_lines = 0
    passed = []
    for line in output.splitlines():
        if holds_a_name(line, names):
            withheld += 1
        elif short_part_alone(line, names):
            short_lines += 1
        else:
            passed.append(line)
    for line in passed:
        print(line)
    unread_total = len(unread_paths)
    print(f"run_with_names: {withheld} printed lines were withheld, each holding a word from your table.")
    print(f"Files new or changed in the marking folder: {clean} read, holding none of the forms of the names in your table; "
          f"{held_files} files and {held_folders} folders held a word from your table and were moved to the quarantine "
          f"folder; {unread_total} could not be read, so were NOT checked and were moved there unread" +
          (" (" + "; ".join(f"{count} {kind}" for kind, count in sorted(unread.items())) + ")" if unread else "") + ".")
    if short_lines or short_files:
        done = []
        if short_lines:
            done.append(f"{short_lines} printed lines were withheld")
        if short_files:
            done.append(f"{len(short_files)} files were moved to the quarantine folder")
        print(" and ".join(done) + ", each holding a two- or three-letter part of a name in your table on its own "
              "(such as Ng or Li), which cannot be told from an everyday word: not checkable, and it may be a false "
              "alarm.")
    if withheld or held_files or held_folders:
        print("Something held a word from your table: a name, or an everyday word that is also a name (such as May "
              "or Will). If it was a name, the script needs fixing before it is used again; what was held back is "
              "not shown here.")
    if unread_total:
        print("Not fully checked: do not open the files moved unread; the teacher can look at them in the "
              "quarantine folder, or the script can be changed to write text.")
    print("This is a safety net, not a guarantee: it catches the names in your table, in what the script printed "
          "and what it wrote in the marking folder, and nothing else. A nickname, or a name that is not in your "
          "table, cannot be seen.")
    if withheld or held_files or held_folders or unread_total or short_lines or short_files:
        return 1
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback: it could carry a value from the table
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); nothing the script printed was passed on")
        sys.exit(1)
