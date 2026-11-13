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

Report card comments (#752, for the plantoir-report-comments skill), through the runner too:

    python3 -B make_named_copies.py --longest-first-name --table TABLE
    python3 -B make_named_copies.py --check-file FILE --table TABLE
    python3 -B make_named_copies.py --comments "<marking folder>/<Term> Comments/Comments.json" --table TABLE
        --out "<teacher-only>/<Term> Comments/Named" --limit 450 [--count characters|bytes]

--comments reads the drafts the assistant wrote with identifiers only ({"students": [{"section": 1,
"identifier": "Student A", "cites": [...], "options": ["...", "...", "..."]}]}), refuses the whole run
(writing nothing) when a draft already holds a word from the table before the names go in, uses a
placeholder it does not know, uses a pronoun placeholder the table cannot fill, or names a student the
table does not hold; otherwise it puts each first name in (from the "first name" column, else from a name
written "Last, First") and the pronouns only from a "pronouns" column, counts every comment AFTER the
names are in (Unicode characters after NFC, or UTF-8 bytes with --count bytes), and writes "Report
Comments.csv" and "Report Comments.md" into --out, naming every comment that is over the limit by
identifier and option. --longest-first-name prints one length; --check-file says whether a file (the
teacher's own notes) holds a word from the table, by line number only, so it can be read safely.

Needs tectonic and Poppler's pdftotext for the sheets; the comments need neither. Python standard
library only.
"""
import csv
import io
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
FIRST_NAME_COLUMN = "first name"
PRONOUNS_COLUMN = "pronouns"
OPTIONS_PER_STUDENT = 3
COMMENTS_TABLE = "Report Comments.csv"
COMMENTS_PAGE = "Report Comments.md"
DRAFTS_PAGE = "Comments - Drafts.md"

# MARK: - What must not change
#   never print, log or write outside the teacher-only folder any value read from the mapping table;
#   never print a file name that is not an identifier; capture every program's output and print only
#   counts and identifiers; refuse (exit 1, identifier-only message) when anything is unexpected; never
#   pass tectonic --keep-logs or --print; compile only in a temporary folder outside both folders; never
#   write in the marking folder; a named sheet whose name is not printed in its PDF is a failure.
#   Comments: never print a comment; count the length only AFTER the names are in, on the NFC text;
#   refuse, writing nothing, a draft that holds a word from the table before the names go in; fill a
#   pronoun only from the table's pronouns column, never guess one; never say a comment is within the
#   limit without having counted it.
PLACEHOLDER = re.compile(r"\{([^{}]*)\}")
FIRST_NAME_PLACEHOLDER = "first name"
PRONOUN_PLACEHOLDERS = ("they", "them", "their", "theirs")
PRONOUN_SETS = {"she/her": ("she", "her", "her", "hers"), "he/him": ("he", "him", "his", "his"),
                "they/them": ("they", "them", "their", "theirs")}
SHORT_PART = 4          # a SURNAME part shorter than this counts in a draft only beside another part of its name
ANYWHERE_PART = 6       # a name part this long counts inside another word too (as run_with_names.py does)
# A first name counts as a whole word at ANY length of two letters or more (Ixo, Qo), in a draft and in a
# file: a short first name alone is still a child's name (752 review H1). --check-file, which decides what
# the assistant may READ, counts every short part alone, surnames too, as run_with_names.py does.
CHANGING_VERB = re.compile(r"\{[Tt]hey\}(?:'|\u2019|\s+(?:is|was|are|were|has|have|does|do|isn't|wasn't|aren't|weren't|"
                           r"hasn't|haven't|doesn't|don't|isn\u2019t|wasn\u2019t|aren\u2019t|weren\u2019t|hasn\u2019t|"
                           r"haven\u2019t|doesn\u2019t|don\u2019t)\b)", re.IGNORECASE)

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
    names = {}
    for key, row in read_table_rows(path)[1].items():
        names[key] = row[NAME_COLUMN]
    return names


def as_typed(value):
    """A value from the table as NFC, with a spreadsheet's typographic quotes as typed (750a fix review L3)."""
    value = unicodedata.normalize("NFC", value)
    for curly, straight in (("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"')):
        value = value.replace(curly, straight)
    return value


def read_table_rows(path):
    """(columns, {(section, identifier): row}), every value as typed, refusing a table with rows of the
    wrong shape (counts only)."""
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
    found = {}
    wrong = 0
    repeated = 0
    for row in rows:
        if not row.get("section", "").isdigit() or not re.match(IDENTIFIER, row.get("identifier", "")) or not row.get(NAME_COLUMN):
            wrong += 1
            continue
        key = (int(row["section"]), row["identifier"])
        if key in found:
            repeated += 1
        typed = {}
        for column in row:
            typed[column] = as_typed(row[column])
        found[key] = typed
    if wrong:
        raise Refusal(f"{wrong} rows in the mapping table are not like section 1, Student A, a name; nothing was written")
    if repeated:
        raise Refusal(f"{repeated} rows in the mapping table repeat a section and identifier; nothing was written")
    return columns, found


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
    # Few short words: a two- or three-letter surname (No, To, So) would make the runner withhold the line.
    print(f"Mapping table checked: {len(names)} rows; " + ", ".join(
        f"section {section} ({count})" for section, count in sorted(sections.items())) +
        "; every row well formed, none repeated.")
    return 0


# MARK: - Report card comments (#752)

def folded(text):
    """Case and accents taken off, so Qoë, QOE and qoe are one word (as run_with_names.py compares)."""
    decomposed = unicodedata.normalize("NFKD", text)
    kept = []
    for character in decomposed:
        if not unicodedata.combining(character):
            kept.append(character)
    return "".join(kept).casefold()


def letter_runs(text):
    return re.findall(r"[^\W\d_]+", folded(text))


def first_name_of(row):
    """The first name column, else the part after the comma of a name written "Last, First", else None."""
    given = row.get(FIRST_NAME_COLUMN, "")
    if given:
        return given
    name = row.get(NAME_COLUMN, "")
    if "," in name:
        after = name.split(",", 1)[1].strip()
        if after:
            return after
    return None


def pronouns_of(row):
    """(they, them, their, theirs) from the pronouns column, or None when it is empty or not understood.
    she/her/hers, he/him/his and they/them/theirs are read as the two-word forms (752 review M2)."""
    value = row.get(PRONOUNS_COLUMN, "").replace(" ", "").lower()
    if value in PRONOUN_SETS:
        return PRONOUN_SETS[value]
    parts = value.split("/")
    if len(parts) == 3:
        forms = PRONOUN_SETS.get(parts[0] + "/" + parts[1])
        if forms is not None and parts[2] in (forms[2], forms[3]):
            return forms
    if len(parts) == 4 and all(parts):
        return tuple(parts)
    return None


def name_parts_of(rows):
    """For every row, (the parts of its name and first name, the parts of its first name), folded. With no
    first name to be read, every part of the name counts as a first name's would."""
    everyone = []
    for row in rows.values():
        parts = []
        for column in (NAME_COLUMN, FIRST_NAME_COLUMN):
            for run in letter_runs(row.get(column, "")):
                if len(run) >= 2 and run not in parts:
                    parts.append(run)
        first = first_name_of(row)
        firsts = []
        for run in letter_runs(first if first is not None else row.get(NAME_COLUMN, "")):
            if len(run) >= 2 and run not in firsts:
                firsts.append(run)
        everyone.append((parts, firsts))
    return everyone


def words_from_the_table(text, everyone, every_short_part_alone=False):
    """1-based positions of the words in text that hold a part of a name in the table, counting each
    placeholder as one word. Never the word itself. A first name's part counts as a whole word at any length;
    a surname's part of two or three letters only beside another part of its name, unless
    every_short_part_alone (--check-file), when it counts on its own as well, as in run_with_names.py."""
    words = PLACEHOLDER.sub("\x00", text).split()
    runs_by_word = []
    for word in words:
        runs_by_word.append(letter_runs(word.replace("\x00", " ")))
    positions = []
    for index, runs in enumerate(runs_by_word):
        beside = []
        if index > 0:
            beside.extend(runs_by_word[index - 1])
        if index + 1 < len(runs_by_word):
            beside.extend(runs_by_word[index + 1])
        found = False
        for parts, firsts in everyone:
            for part in parts:
                if len(part) >= ANYWHERE_PART:
                    for run in runs:
                        if part in run:
                            found = True
                elif len(part) >= SHORT_PART or part in firsts or every_short_part_alone:
                    if part in runs:
                        found = True
                elif part in runs:
                    for other in parts:
                        if other != part and (other in beside or other in runs):
                            found = True
        if found:
            positions.append(index + 1)
    return positions


def lines_from_the_table(text, everyone, every_short_part_alone=False):
    """1-based line numbers of the lines in text that hold a part of a name in the table."""
    numbers = []
    for number, line in enumerate(text.splitlines(), start=1):
        if words_from_the_table(line, everyone, every_short_part_alone):
            numbers.append(number)
    return numbers


def filled(option, row, has_pronouns_column):
    """(the comment with the names in, None) or (None, why), why holding no value from the table."""
    problems = []

    def put_in(match):
        inner = match.group(1)
        if inner == FIRST_NAME_PLACEHOLDER:
            first = first_name_of(row)
            if first is None:
                problems.append("the mapping table gives no first name for this student (the first name column is "
                                "empty, and the name is not written Last, First)")
                return ""
            return first
        if inner.lower() in PRONOUN_PLACEHOLDERS and inner in (inner.lower(), inner.capitalize()):
            if not has_pronouns_column:
                problems.append("it uses a pronoun placeholder, and your mapping table has no pronouns column")
                return ""
            forms = pronouns_of(row)
            if forms is None:
                problems.append("it uses a pronoun placeholder, and this student's pronouns in your mapping table are "
                                "empty or not written like she/her, he/him, they/them, or four words such as xe/xem/xyr/xyrs")
                return ""
            form = forms[PRONOUN_PLACEHOLDERS.index(inner.lower())]
            if inner[0].isupper():
                return form[:1].upper() + form[1:]
            return form
        problems.append("it uses a placeholder this script does not know (it knows {first name}, and {they}, {them}, "
                        "{their} and {theirs}, capitalised or not)")
        return ""

    text = PLACEHOLDER.sub(put_in, unicodedata.normalize("NFC", option.strip()))
    if problems:
        return None, problems[0]
    return unicodedata.normalize("NFC", text), None


def measured(text, count):
    if count == "bytes":
        return len(text.encode("utf-8"))
    return len(text)


def plural(number, word):
    return f"{number} {word}" if number == 1 else f"{number} {word}s"


def read_drafts(path):
    """The students in Comments.json, refusing a file not in the skill's shape (no value is printed)."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        raise Refusal("the drafts file could not be read as JSON; nothing was written")
    shape = ('the drafts file is not in the shape the skill gives ({"students": [{"section": 1, "identifier": '
             '"Student A", "cites": [...], "options": [...]}]}); nothing was written')
    if not isinstance(data, dict) or not isinstance(data.get("students"), list):
        raise Refusal(shape)
    students = []
    for entry in data["students"]:
        if not isinstance(entry, dict):
            raise Refusal(shape)
        section = entry.get("section")
        if isinstance(section, str) and section.isdigit():
            section = int(section)
        if isinstance(section, bool):
            raise Refusal(shape)
        identifier = entry.get("identifier")
        options = entry.get("options")
        if not isinstance(section, int) or not isinstance(identifier, str) or not re.match(IDENTIFIER, identifier):
            raise Refusal(shape)
        if not isinstance(options, list):
            raise Refusal(shape)
        for option in options:
            if not isinstance(option, str):
                raise Refusal(shape)
        students.append((section, identifier, options, entry))
    return students


def other_strings(entry):
    """Every string in a student's entry apart from its options and identifier, to look for a name in."""
    found = []

    def walk(value):
        if isinstance(value, str):
            found.append(value)
        elif isinstance(value, list):
            for item in value:
                walk(item)
        elif isinstance(value, dict):
            for key in value:
                walk(key)
                walk(value[key])

    for key in entry:
        if key not in ("options", "identifier", "section"):
            walk(key)
            walk(entry[key])
    return found


def longest_first_name(table):
    _columns, rows = read_table_rows(table)
    longest_characters = 0
    longest_bytes = 0
    missing = 0
    for row in rows.values():
        first = first_name_of(row)
        if first is None:
            missing += 1
            continue
        longest_characters = max(longest_characters, len(first))
        longest_bytes = max(longest_bytes, len(first.encode("utf-8")))
    if missing == len(rows):
        print("No row of your mapping table gives a first name (a first name column, or a name written Last, First).")
        return 1
    print(f"The longest first name in your mapping table is {plural(longest_characters, 'character')} "
          f"({plural(longest_bytes, 'byte')}); the placeholder {{first name}} is 12.")
    if missing:
        print(f"{plural(missing, 'row')} of the table give no first name (no first name column value, and the name is not "
              "written Last, First).")
        return 1
    return 0


def check_file(table, path):
    """Say whether a file holds a word from the table, by line number only. It never calls a file clean: it
    says what it looked for and found, and what it cannot see (752 review H1)."""
    _columns, rows = read_table_rows(table)
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        raise Refusal("the file could not be read as text; it was not checked, so do not open it")
    numbers = lines_from_the_table(text, name_parts_of(rows), every_short_part_alone=True)
    if numbers:
        print("A word from your mapping table is on " + plural(len(numbers), "line") + " of the file (line "
              + ", ".join(str(number) for number in numbers) + "). Do not open it until the teacher has changed it.")
        return 1
    print(f"Looked for every part of every name in your mapping table in {plural(len(text.splitlines()), 'line')} "
          "of the file, and found none. This cannot see a nickname, initials, or a name that is not in your table: "
          "the teacher reads the file once for those before it is opened.")
    return 0


def write_replacing(path, text, encoding):
    """Write next to the file and then put it in place, so a failed run leaves the last good file whole."""
    partial = path.with_name("." + path.name + ".partial")
    with open(partial, "w", encoding=encoding, newline="") as handle:   # Path.write_text has newline= only from 3.10
        handle.write(text)
    os.replace(partial, path)


def set_earlier_run_aside(out):
    """Rename the named comments of an earlier run, so a refused run never leaves comments that no longer
    match the drafts looking current (752 review L2). Returns how many files were renamed."""
    renamed = 0
    for name in (COMMENTS_TABLE, COMMENTS_PAGE):
        path = out / name
        if path.is_file():
            os.replace(path, out / name.replace("Report Comments", "Report Comments - earlier run, do not use"))
            renamed += 1
    return renamed


def is_own_cite(cite, section, identifier):
    """A cite is this student's own marks record (ends Section N/<identifier>.json) or the teacher's notes."""
    text = cite.replace("\\", "/")
    for own in (f"Section {section}/{identifier}.json", "Teacher Notes.md"):
        if text == own or text.endswith("/" + own):
            return True
    return False


def make_comments(table, comments, out, limit, count):
    comments = Path(comments).resolve()
    out = Path(out).resolve()
    marking_folder = comments.parent.parent
    if in_a_working_folder(out) or in_a_working_folder(comments):
        raise Refusal("the comments must stay outside the Plantoir working folder; nothing was written")
    if out == marking_folder or marking_folder in out.parents:
        raise Refusal("the named comments must go in the teacher-only folder, never in the marking folder; nothing was written")
    teacher_only = Path(table).resolve().parent
    if out != teacher_only and teacher_only not in out.parents:
        raise Refusal("the named comments must go in the teacher-only folder that holds the mapping table; nothing was written")
    if count not in ("characters", "bytes"):
        raise Refusal("--count is characters or bytes; nothing was written")
    try:
        limit = int(limit)
    except ValueError:
        raise Refusal("--limit is a whole number of characters; nothing was written")
    if limit < 1:
        raise Refusal("--limit is a whole number of characters; nothing was written")
    columns, rows = read_table_rows(table)
    has_pronouns_column = PRONOUNS_COLUMN in columns
    everyone = name_parts_of(rows)
    students = read_drafts(comments)
    problems = []
    written = []
    not_drafted = []
    seen = set()
    for section, identifier, options, entry in students:
        label = f"Section {section}/{identifier}"
        if (section, identifier) in seen:
            problems.append(f"{label} is in the drafts twice")
            continue
        seen.add((section, identifier))
        row = rows.get((section, identifier))
        if row is None:
            problems.append(f"{label}: not in the mapping table")
            continue
        for value in other_strings(entry):
            if words_from_the_table(value, everyone):
                problems.append(f"{label}: a field other than its options holds a word from your mapping table")
                break
        cites = entry.get("cites", [])
        if not isinstance(cites, list):
            cites = [cites]
        for cite in cites:
            if not isinstance(cite, str) or not is_own_cite(cite, section, identifier):
                problems.append(f"{label}: cites a record that is not this student's own (each record it cites must "
                                f"end Section {section}/{identifier}.json)")
                break
        if not options:
            not_drafted.append(label)
            continue
        if len(options) != OPTIONS_PER_STUDENT:
            problems.append(f"{label} has {plural(len(options), 'option')}, not {OPTIONS_PER_STUDENT}")
            continue
        for number, option in enumerate(options, start=1):
            positions = words_from_the_table(option, everyone)
            if positions:
                problems.append(f"{label} option {number}: word " + ", ".join(str(place) for place in positions) +
                                " holds a word from your mapping table before the names went in")
                continue
            if CHANGING_VERB.search(option):
                problems.append(f"{label} option {number}: a verb after {{they}} changes with the pronoun (they were, "
                                "she was): write one that does not, such as a verb in the past tense other than was")
                continue
            text, why = filled(option, row, has_pronouns_column)
            if text is None:
                problems.append(f"{label} option {number}: {why}")
                continue
            size = measured(text, count)
            written.append({"section": section, "identifier": identifier, "name": row[NAME_COLUMN], "option": number,
                            "size": size, "over": max(0, size - limit), "comment": text})
    drafts_page = comments.parent / DRAFTS_PAGE
    if drafts_page.is_file():
        try:
            drafts_text = drafts_page.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            drafts_text = ""
            problems.append(f"{DRAFTS_PAGE} could not be read as text")
        numbers = lines_from_the_table(drafts_text, everyone)
        if numbers:
            problems.append(f"{DRAFTS_PAGE}: a word from your mapping table is on {plural(len(numbers), 'line')} (line "
                            + ", ".join(str(number) for number in numbers) + ")")
    if problems:
        for problem in problems:
            print(problem)
        if out.is_dir() and set_earlier_run_aside(out):
            print("The named comments from an earlier run no longer match these drafts, so they were renamed "
                  "\"earlier run, do not use\" in the teacher-only folder.")
        raise Refusal(f"{plural(len(problems), 'problem')} in the drafts; nothing was written")
    unit = "byte" if count == "bytes" else "character"
    out.mkdir(parents=True, exist_ok=True)
    table_lines = io.StringIO()
    writer = csv.writer(table_lines)
    writer.writerow(["section", "identifier", "name", "option", f"{unit}s", "over the limit by", "comment"])
    page = ["# Report comments", "",
            "These are drafts for you to read, change and own. Nothing here has been sent anywhere or entered into "
            "your report system.", "",
            f"The limit is {plural(limit, unit)}, counted with the first names in.", ""]
    current = None
    for comment in written:
        writer.writerow([comment["section"], comment["identifier"], comment["name"], comment["option"], comment["size"],
                         comment["over"], comment["comment"]])
        if (comment["section"], comment["identifier"]) != current:
            current = (comment["section"], comment["identifier"])
            page.extend([f"## Section {comment['section']}: {comment['name']} ({comment['identifier']})", ""])
        over = f", OVER THE LIMIT by {comment['over']}" if comment["over"] else ""
        page.extend([f"**Option {comment['option']}** ({plural(comment['size'], unit)}{over})", "", comment["comment"], ""])
    write_replacing(out / COMMENTS_TABLE, table_lines.getvalue(), "utf-8-sig")
    write_replacing(out / COMMENTS_PAGE, "\n".join(page), "utf-8")
    by_section = {}
    for comment in written:
        counted = by_section.setdefault(comment["section"], [0, set()])
        counted[0] += 1
        counted[1].add(comment["identifier"])
    for section in sorted(by_section):
        print(f"Section {section}: {plural(by_section[section][0], 'comment')} written for "
              f"{plural(len(by_section[section][1]), 'student')}")
    for label in not_drafted:
        print(f"{label}: no comment drafted, so none was written")
    drafted_sections = set()
    for key in seen:
        drafted_sections.add(key[0])
    left_out = []
    for key in sorted(rows):
        if key[0] in drafted_sections and key not in seen:
            left_out.append(f"Section {key[0]}/{key[1]}")
    if left_out:
        print(f"{plural(len(left_out), 'student')} in your mapping table, in the sections drafted, "
              f"{'has' if len(left_out) == 1 else 'have'} no entry in the drafts: " + ", ".join(left_out))
    over_the_limit = []
    for comment in written:
        if comment["over"]:
            over_the_limit.append(comment)
            print(f"Section {comment['section']}/{comment['identifier']} option {comment['option']} is "
                  f"{plural(comment['over'], unit)} over the limit of {limit}")
    if not written:
        print("No comment was written: no student in the drafts had options drafted.")
    elif over_the_limit:
        print(f"{plural(len(over_the_limit), 'comment')} over the limit of {plural(limit, unit)}, counted with the first "
              "names in: rewrite each one named above and run this again.")
    else:
        print(f"Every comment written is within the limit of {plural(limit, unit)}, counted with the first names in.")
    print("The named comments are in your teacher-only folder. I have not opened them, and will not.")
    return 1 if over_the_limit else 0


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


def self_test_sheets():
    """An invented table and two invented sheets, through the main path; the problems it found."""
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
    return problems


def self_test_comments():
    """An invented table and invented drafts, through --comments; the problems it found."""
    invented = ["Bartholomewina", "Testfamily", "Zedfamily"]
    problems = []
    with tempfile.TemporaryDirectory() as root:
        root_path = Path(root)
        drafts = root_path / "Marking" / "Term 1 Comments" / "Comments.json"
        drafts.parent.mkdir(parents=True)
        table = root_path / "Teacher only" / "Name Mapping Table.csv"
        table.parent.mkdir(parents=True)
        table.write_text('section,identifier,name,first name\n1,Student A,"Testfamily, Bartholomewina",\n'
                         '1,Student B,"Zedfamily, Qoe\u0308",\n', encoding="utf-8")
        at_the_limit = "{first name} balanced every equation in Part B."
        options = [at_the_limit, "Well done, {first name}.", "{first name} explained each step."]
        drafts.write_text(json.dumps({"students": [
            {"section": 1, "identifier": "Student A", "cites": [], "options": options},
            {"section": 1, "identifier": "Student B", "cites": [], "options": options}]}), encoding="utf-8")
        out = root_path / "Teacher only" / "Term 1 Comments" / "Named"
        result = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--comments", str(drafts), "--table",
                                 str(table), "--out", str(out), "--limit", str(len(at_the_limit))],
                                capture_output=True, text=True, encoding="utf-8")
        said = result.stdout + result.stderr
        for token in invented:
            if token.casefold() in said.casefold():
                problems.append("a name reached the output")
        if f"Section 1/Student A option 1 is 2 characters over the limit of {len(at_the_limit)}" not in said:
            problems.append("a comment at the limit before the name went in was not counted after it")
        if "Student B option 1 is" in said:
            problems.append("a comment within the limit after the name went in was called over")
        try:
            with open(out / COMMENTS_TABLE, newline="", encoding="utf-8-sig") as handle:
                rows = list(csv.DictReader(handle))
        except OSError:
            rows = []
        comments = []
        for row in rows:
            comments.append(row.get("comment", ""))
        if "Well done, Qo\u00eb." not in comments or "Well done, Bartholomewina." not in comments:
            problems.append("the first names were not put in, or not as NFC")
        for path in (root_path / "Marking").rglob("*"):
            if path.is_file() and path != drafts:
                problems.append("something was written in the marking folder")
        drafts.write_text(json.dumps({"students": [
            {"section": 1, "identifier": "Student A", "cites": [], "options": ["Testfamily wrote it.", "b", "c"]}]}),
            encoding="utf-8")
        refused = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--comments", str(drafts), "--table",
                                  str(table), "--out", str(out / "again"), "--limit", "450"],
                                 capture_output=True, text=True, encoding="utf-8")
        if refused.returncode != 1 or (out / "again").exists() or "Testfamily" in refused.stdout + refused.stderr:
            problems.append("a draft holding a name was not refused, or the refusal printed it")
    return problems


def self_test():
    """The named sheets (when tectonic and pdftotext are here) and the comments, each on invented names."""
    problems = self_test_comments()
    sheets_tested = shutil.which("tectonic") is not None and shutil.which("pdftotext") is not None
    if sheets_tested:
        problems.extend(self_test_sheets())
    if problems:
        print("self-test FAILED: " + "; ".join(sorted(set(problems))))
        return 1
    if sheets_tested:
        print("self-test passed: an invented name with TeX characters set and checked, a missing identifier "
              "reported by identifier, nothing written in the marking folder, no name printed; and invented "
              "comments counted after the names went in, as NFC, and a draft holding a name refused. This checks "
              "the paths the test knows; it is no guarantee about changes it does not reach.")
    else:
        print("self-test passed for the comments only: invented comments counted after the names went in, as NFC, "
              "and a draft holding a name refused. The named sheets were NOT tested: tectonic or pdftotext is not "
              "installed, and the sheets cannot be made without them. This checks the paths the test knows; it is no "
              "guarantee about changes it does not reach.")
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
    if "--longest-first-name" in arguments:
        if option(arguments, "--table") is None:
            raise Refusal("give --table")
        return longest_first_name(option(arguments, "--table"))
    if option(arguments, "--check-file") is not None:
        if option(arguments, "--table") is None:
            raise Refusal("give --table")
        return check_file(option(arguments, "--table"), option(arguments, "--check-file"))
    if option(arguments, "--comments") is not None:
        for needed in ("--table", "--out", "--limit"):
            if option(arguments, needed) is None:
                raise Refusal(f"give {needed}")
        return make_comments(option(arguments, "--table"), option(arguments, "--comments"), option(arguments, "--out"),
                             option(arguments, "--limit"), option(arguments, "--count") or "characters")
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
