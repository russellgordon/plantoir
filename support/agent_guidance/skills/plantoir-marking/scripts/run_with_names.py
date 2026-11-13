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
  - a file it cannot read (what a picture shows, a PDF without Poppler, anything else) is counted by kind
    as NOT checked;
  - a printed line that holds any form of a name is withheld, and counted.
It then prints the lines that hold none, and three counts: read and clean, holding a name and moved, and
not checked. It exits 1 if anything was withheld, moved or left unchecked, and otherwise with the
command's own exit code.

It is a safety net, not a guarantee. It catches the names in the table, and only in what the command
prints and what it writes in the watched folder. It cannot know a nickname, a family member's name or a
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

NAME_COLUMNS = ("name", "first name", "preferred name", "last name", "surname")
EMAIL_COLUMNS = ("email", "e-mail")
HANDLE_COLUMNS = ("handles", "handle", "username", "github")
REPOSITORY_COLUMNS = ("repository", "repo")
MINIMUM_LENGTH = 2


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding no value from the table."""


def without_accents(text):
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(character for character in decomposed if not unicodedata.combining(character))


def folded(text):
    """Case and accents taken off, so Zoë, ZOE and zoe are one word."""
    return without_accents(unicodedata.normalize("NFC", text)).casefold()


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
        return "", ["PDF"]   # read by pdf_text, from the file on disk
    if data[:2] in (b"\xff\xfe", b"\xfe\xff") or (len(data) >= 4 and data.count(b"\x00") > len(data) // 4):
        for encoding in ("utf-16", "utf-16-le", "utf-16-be"):
            try:
                return data.decode(encoding), []
            except UnicodeDecodeError:
                continue
    try:
        return data.decode("utf-8"), []
    except UnicodeDecodeError:
        return "", ["a file that is not text (" + (Path(name).suffix.lower() or "no extension") + ")"]


def pdf_text(path):
    """A PDF's text, its metadata and its XMP, through Poppler; None when Poppler is not here."""
    if shutil.which("pdftotext") is None or shutil.which("pdfinfo") is None:
        return None
    pieces = []
    for command in (["pdftotext", str(path), "-"], ["pdfinfo", str(path)], ["pdfinfo", "-meta", str(path)]):
        result = subprocess.run(command, capture_output=True)
        pieces.append(result.stdout.decode("utf-8", "replace"))
    return "\n".join(pieces)


def look_at(path, kind):
    """(text to search, kinds not checked) for one new or changed thing in the watched folder."""
    if kind == "folder":
        return "", []
    if kind == "link":
        try:
            return os.readlink(path), []
        except OSError:
            return "", ["a link that could not be read"]
    try:
        data = path.read_bytes()
    except OSError:
        return "", ["a file that could not be opened"]
    text, unread = text_of(data, path.name)
    if "PDF" in unread:
        unread.remove("PDF")
        found = pdf_text(path)
        if found is None:
            unread.append("a PDF (Poppler is not installed, so its text could not be read)")
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
    words, anywhere = tokens_from(read_rows(table))
    if not words and not anywhere:
        raise Refusal("the mapping table holds no names; nothing was run")
    before = snapshot(watch)
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    result = subprocess.run(command, capture_output=True, env=environment, cwd=watch)
    output = (result.stdout + result.stderr).decode("utf-8", "replace")
    # Everything is looked at BEFORE anything is passed on, so a failure here passes nothing on.
    after = snapshot(watch)
    changed = [path for path, state in sorted(after.items()) if before.get(path) != state]
    named_folders = []
    for path in changed:
        if after[path][0] == "folder" and holds_a_name(path.name, words, anywhere):
            if not any(folder in path.parents for folder in named_folders):
                named_folders.append(path)
    for path, state in sorted(after.items()):
        if state[0] == "folder" and holds_a_name(path.name, words, anywhere) and path not in named_folders:
            if not any(folder in path.parents for folder in named_folders):
                named_folders.append(path)   # an old folder named by a name, given a new file
    clean = 0
    moving = list(named_folders)
    unread = {}
    for path in changed:
        if after[path][0] == "folder" or any(folder in path.parents for folder in named_folders):
            continue
        text, kinds = look_at(path, after[path][0])
        relative = str(path.relative_to(Path(watch)))
        if holds_a_name(relative, words, anywhere) or holds_a_name(text, words, anywhere):
            moving.append(path)
            continue
        if kinds:
            for kind in kinds:
                unread[kind] = unread.get(kind, 0) + 1
            continue
        clean += 1
    held_files = 0
    held_folders = 0
    for path in moving:
        target = Path(quarantine) / path.relative_to(Path(watch))
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.is_dir() and not path.is_symlink():
            held_folders += 1
        else:
            held_files += 1
        shutil.move(str(path), str(target))
    withheld = 0
    passed = []
    for line in output.splitlines():
        if holds_a_name(line, words, anywhere):
            withheld += 1
        else:
            passed.append(line)
    for line in passed:
        print(line)
    unread_total = sum(unread.values())
    print(f"run_with_names: {withheld} printed lines were withheld, each holding a word from your table.")
    print(f"Files new or changed in the marking folder: {clean} read and clean; "
          f"{held_files} files and {held_folders} folders held a name and were moved to the quarantine folder; "
          f"{unread_total} could not be read, so were NOT checked" +
          (" (" + "; ".join(f"{count} {kind}" for kind, count in sorted(unread.items())) + ")" if unread else "") + ".")
    if withheld:
        print("A withheld line held a word from your table. If that word is also an everyday word (a name such as "
              "May or Will), this is a false alarm; otherwise the script needs fixing before it is used again.")
    if held_files or held_folders:
        print("The script wrote a name into the marking folder and needs fixing before it is used again. "
              "What was moved is not shown here.")
    if unread_total:
        print("Not fully checked: the files that could not be read were left where they are. Ask the teacher to "
              "look at them, or change the script so it writes text.")
    print("This is a safety net, not a guarantee: it catches the names in your table, in what the script printed "
          "and what it wrote in the marking folder, and nothing else.")
    if withheld or held_files or held_folders or unread_total:
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
