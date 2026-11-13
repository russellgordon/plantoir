#!/usr/bin/env python3
"""Make the named copies of finished identifier sheets, on the teacher's word, at the end. The ONLY script in
the plantoir-marking skill that puts a student's name into anything.

Part of the plantoir-marking skill. A STARTING POINT: copy it into the marking folder's Scripts/ folder,
adjust it to this teacher (see the two MARK blocks below), run --self-test, and only then use it. Run it
through run_with_names.py, never directly:

    python3 -B <skill>/scripts/run_with_names.py --table TABLE --watch <marking folder> --quarantine <teacher-only>/Quarantine --
        python3 -B make_named_copies.py --table TABLE --sheets "<marking folder>/<Assessment>/Sheets" --out "<teacher-only>/<Assessment>/Named"
    python3 -B make_named_copies.py --check-table --table TABLE      (through the runner too: counts only)
    python3 -B make_named_copies.py --self-test

TABLE is the teacher's Name Mapping Table (CSV or tab-separated) with the columns section, identifier and
name (other columns are not read here). For each identifier sheet "Section N/Student A - Feedback.tex" it
puts the name, TeX-escaped, into the sheet's \\studentline{...} (the one place a sheet marks for it),
compiles it in a temporary folder outside both folders with its output captured and thrown away, checks
the name is really printed in the PDF, and moves only the PDF to "<out>/Section N/<name> - Feedback.pdf".
The temporary folder goes with its .tex. It prints counts and identifiers only, never a name, and never
writes in the marking folder.

Needs tectonic and Poppler's pdftotext. Python standard library only.
"""
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

# MARK: - What you may change for this teacher
#   which name column is used and how it is written on the sheet (the name as written in the table by
#   default), the file names of the named copies, which kinds of sheet are named (every
#   "<identifier> - <kind>.tex" by default), the folder names, the wording of the lines it prints.
NAME_COLUMN = "name"
IDENTIFIER = r"^Student [A-Z]{1,2}$"
SECTION = r"^Section (\d+)$"
SHEET = r"^(Student [A-Z]{1,2}) - (.+)\.tex$"
SLOT = re.compile(r"\\studentline\{([^{}]*)\}")

# MARK: - What must not change
#   never print, log or write outside the teacher-only folder any value read from the mapping table;
#   never print a file name that is not an identifier; capture every program's output and print only
#   counts and identifiers; refuse (exit 1, identifier-only message) when anything is unexpected; never
#   pass tectonic --keep-logs or --print; compile only in a temporary folder outside both folders; never
#   write in the marking folder; a named sheet whose name is not printed in its PDF is a failure.

ESCAPES = [("\\", "\\textbackslash{}"), ("&", "\\&"), ("%", "\\%"), ("$", "\\$"), ("#", "\\#"), ("_", "\\_"),
           ("{", "\\{"), ("}", "\\}"), ("~", "\\textasciitilde{}"), ("^", "\\textasciicircum{}")]


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding identifiers and counts only."""


def tex_escaped(name):
    text = name.replace("\\", "\x00")
    for character, replacement in ESCAPES[1:]:
        text = text.replace(character, replacement)
    return text.replace("\x00", ESCAPES[0][1])


def read_table(path):
    """{(section, identifier): name}, refusing a table with rows of the wrong shape (counts only)."""
    try:
        with open(path, newline="", encoding="utf-8-sig") as handle:
            first_line = handle.readline()
            handle.seek(0)
            reader = csv.DictReader(handle, dialect="excel-tab" if "\t" in first_line else "excel")
            columns = [column.strip().casefold() for column in (reader.fieldnames or [])]
            rows = []
            for row in reader:
                cleaned = {}
                for key in row:
                    if key is not None:
                        cleaned[key.strip().casefold()] = (row[key] or "").strip()
                rows.append(cleaned)
    except (OSError, UnicodeDecodeError, csv.Error):
        raise Refusal("the mapping table could not be read; nothing was written")
    for column in ("section", "identifier", NAME_COLUMN):
        if column not in columns:
            raise Refusal(f"the mapping table has no {column} column; nothing was written")
    names = {}
    wrong = 0
    repeated = 0
    for row in rows:
        if not row.get("section", "").isdigit() or not re.match(IDENTIFIER, row.get("identifier", "")) or not row.get(NAME_COLUMN):
            wrong += 1
            continue
        key = (int(row["section"]), row["identifier"])
        if key in names:
            repeated += 1
        names[key] = unicodedata.normalize("NFC", row[NAME_COLUMN])
    if wrong:
        raise Refusal(f"{wrong} rows in the mapping table are not like section 1, Student A, a name; nothing was written")
    if repeated:
        raise Refusal(f"{repeated} rows in the mapping table repeat a section and identifier; nothing was written")
    return names


def file_safe(name):
    return re.sub(r'[\\/:*?"<>|]', "-", name).strip(" .")


def comparable(text):
    """Text as a PDF and a table can both be compared: the font's ligatures (ffi, fi) as their letters,
    a typeset apostrophe as a typed one, and no spaces (750a review M2: O'Testpupil and Griffith failed)."""
    text = unicodedata.normalize("NFKC", text)
    for curly, straight in (("\u2019", "'"), ("\u2018", "'"), ("\u201c", '"'), ("\u201d", '"')):
        text = text.replace(curly, straight)
    return re.sub(r"\s+", "", text)


def printed_text(pdf):
    text = subprocess.run(["pdftotext", str(pdf), "-"], capture_output=True).stdout.decode("utf-8", "replace")
    return comparable(text)


def name_one(tex, name):
    """(pdf bytes, None) or (None, why) for one sheet with the name in its slot."""
    if len(SLOT.findall(tex)) != 1:
        return None, "the sheet does not have exactly one \\studentline"
    named = SLOT.sub(lambda match: "\\studentline{" + tex_escaped(name) + "}", tex)
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / "sheet.tex"
        source.write_text(named, encoding="utf-8")
        result = subprocess.run(["tectonic", "-c", "minimal", str(source)], capture_output=True, cwd=folder)
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        pdf = Path(folder) / "sheet.pdf"
        if result.returncode != 0 or not pdf.exists():
            return None, "the named sheet did not compile"
        if "Missing character" in said:
            return None, "the name could not be set in this sheet's font"
        if comparable(name) not in printed_text(pdf):
            return None, "the name could not be set in this sheet's font"
        return pdf.read_bytes(), None


def in_a_working_folder(path):
    path = Path(path).resolve()
    for folder in [path] + list(path.parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            return True
    return False


def check_table(table):
    """Say whether the table is right, in counts only: rows, sections, and nothing of what a row holds."""
    names = read_table(table)
    sections = {}
    for section, _identifier in names:
        sections[section] = sections.get(section, 0) + 1
    print(f"The mapping table has {len(names)} rows, in " + ", ".join(
        f"section {section} ({count})" for section, count in sorted(sections.items())) +
        "; every row is like section 1, Student A, a name, and no section and identifier repeat.")
    return 0


def make_copies(table, sheets, out):
    if shutil.which("tectonic") is None or shutil.which("pdftotext") is None:
        raise Refusal("tectonic and Poppler's pdftotext are needed; nothing was written")
    sheets = Path(sheets).resolve()
    out = Path(out).resolve()
    marking_folder = sheets.parent.parent
    if in_a_working_folder(out):
        raise Refusal("the named copies must go in the teacher-only folder, outside the Plantoir working folder; nothing was written")
    if out == marking_folder or marking_folder in out.parents or sheets in out.parents:
        raise Refusal("the named copies must go in the teacher-only folder, never in the marking folder; nothing was written")
    names = read_table(table)
    sections = {}
    left_alone = 0
    for folder in sorted(sheets.iterdir()):
        match = re.match(SECTION, folder.name)
        if not folder.is_dir() or match is None:
            left_alone += 1
            continue
        for sheet in sorted(folder.iterdir()):
            sheet_match = re.match(SHEET, sheet.name)
            if sheet_match is None:
                if sheet.suffix != ".pdf":
                    left_alone += 1
                continue
            sections.setdefault(int(match.group(1)), []).append((sheet_match.group(1), sheet_match.group(2), sheet))
    failures = 0
    for section in sorted(sections):
        written = 0
        failed = []
        missing = []
        for identifier, kind, sheet in sections[section]:
            name = names.get((section, identifier))
            if name is None:
                missing.append(identifier)
                continue
            pdf, why = name_one(sheet.read_text(encoding="utf-8"), name)
            if pdf is None:
                failed.append(f"{identifier} {kind}: {why}")
                continue
            target = out / f"Section {section}" / f"{file_safe(name)} - {kind}.pdf"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(pdf)
            written += 1
        line = f"Section {section}: {written} named sheets written"
        if failed:
            line += f"; {len(failed)} not written (" + "; ".join(failed) + ")"
        print(line)
        for identifier in missing:
            print(f"Section {section}/{identifier}: not in the mapping table")
        failures += len(failed) + len(missing)
    if left_alone:
        print(f"{left_alone} files or folders not named like a sheet were left alone")
    print("Named copies are in your teacher-only folder. I have not opened them, and will not.")
    return 0 if failures == 0 else 1


def self_test():
    """An invented table and two invented sheets, through the main path; checks what was printed and written."""
    if shutil.which("tectonic") is None or shutil.which("pdftotext") is None:
        print("self-test skipped: tectonic or pdftotext is not installed")
        return 1
    invented = ["Pupil_Seven", "Testfamily"]
    with tempfile.TemporaryDirectory() as root:
        root_path = Path(root)
        sheets = root_path / "Marking" / "Test" / "Sheets" / "Section 1"
        sheets.mkdir(parents=True)
        sheet = ("\\documentclass{article}\\usepackage[T1]{fontenc}\\usepackage{lmodern}\\newcommand{\\studentline}[1]{#1}"
                 "\\begin{document}Feedback for \\studentline{Student A}\\end{document}\n")
        (sheets / "Student A - Feedback.tex").write_text(sheet, encoding="utf-8")
        (sheets / "Student B - Feedback.tex").write_text(sheet.replace("Student A", "Student B"), encoding="utf-8")
        table = root_path / "Teacher only" / "Name Mapping Table.csv"
        table.parent.mkdir(parents=True)
        table.write_text("section,identifier,name\n1,Student A,Pupil_Seven & Testfamily\n", encoding="utf-8")
        result = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--table", str(table), "--sheets",
                                 str(root_path / "Marking" / "Test" / "Sheets"), "--out", str(root_path / "Teacher only" / "Named")],
                                capture_output=True, text=True)
        said = result.stdout + result.stderr
        problems = []
        for token in invented:
            if token.casefold() in said.casefold():
                problems.append("a name reached the output")
        if "Section 1: 1 named sheets written" not in said or "Section 1/Student B: not in the mapping table" not in said:
            problems.append("the counts were not what the invented table gives")
        written = sorted(path.name for path in (root_path / "Teacher only" / "Named").rglob("*"))
        if written != ["Pupil_Seven & Testfamily - Feedback.pdf", "Section 1"]:
            problems.append("the named folder holds something else")
        for path in (root_path / "Marking").rglob("*"):
            if path.is_file() and path.suffix != ".tex":
                problems.append("something was written in the marking folder")
    if problems:
        print("self-test FAILED: " + "; ".join(sorted(set(problems))))
        return 1
    print("self-test passed: an invented name with TeX characters set and checked, a missing identifier "
          "reported by identifier, nothing written in the marking folder, no name printed. This checks the "
          "paths the test knows; it is no guarantee about changes it does not reach.")
    return 0


def option(arguments, name):
    if name in arguments:
        index = arguments.index(name)
        if index + 1 >= len(arguments):
            raise Refusal(f"{name} needs a value")
        return arguments[index + 1]
    return None


def main(arguments):
    if not arguments or arguments[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if "--self-test" in arguments:
        return self_test()
    if "--check-table" in arguments:
        if option(arguments, "--table") is None:
            raise Refusal("give --table")
        return check_table(option(arguments, "--table"))
    for needed in ("--table", "--sheets", "--out"):
        if option(arguments, needed) is None:
            raise Refusal(f"give {needed}")
    return make_copies(option(arguments, "--table"), option(arguments, "--sheets"), option(arguments, "--out"))


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback: it could carry a name
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); check the named folder")
        sys.exit(1)
