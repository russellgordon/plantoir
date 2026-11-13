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

Class results (#750, 750c, for class_results.py's documents), through the runner too:

    python3 -B make_named_copies.py --document "<marking folder>/<Assessment>/Results/Class Results.tex" --table TABLE
        --out "<teacher-only>/<Assessment>/Named"
    python3 -B make_named_copies.py --grades "<marking folder>/<Assessment>/Results/Grades - <Assessment>.csv"
        --table TABLE --out "<teacher-only>/<Assessment>/Named"

--document fills every \\student{N}{Student A} of an identifier document with the TeX-escaped name and the
identifier, compiles it in a temporary folder with its output captured and thrown away, checks every name is
printed in the PDF, and writes only "<out>/<document> (Names).pdf". --grades reads a grade table
class_results.py wrote (section, identifier, then numbers and levels), refuses the whole run (writing
nothing) when a cell holds a word from the table or more than a number or a level, or when a student is not
in the table, and writes "<out>/<table> (Names).csv" with the name first, ordered by section and then by
name, for the teacher to copy into the school's report system. Both refuse an --out outside the teacher-only
folder that holds the mapping table.

Needs tectonic and Poppler's pdftotext for the sheets and --document; the comments and --grades need
neither. Python standard library only.
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
DOCUMENT_SLOT = re.compile(r"\\student\{(\d+)\}\{([^{}]*)\}")
BUILT = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d [0-9a-f]{12}$")
NAMED_SUFFIX = " (Names)"
GRADE_CELL_LENGTH = 16
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
#   Results: write the named document and the named grade table only into the teacher-only folder that holds
#   the mapping table; refuse, writing nothing, a grade table whose cells hold a word from the table or more
#   than a number or a level, or a student the table does not hold; a named document whose names are not all
#   printed in its PDF is a failure.
PLACEHOLDER = re.compile(r"\{([^{}]*)\}")
FIRST_NAME_PLACEHOLDER = "first name"
PRONOUN_PLACEHOLDERS = ("they", "them", "their", "theirs")
PRONOUN_SETS = {"she/her": ("she", "her", "her", "hers"), "he/him": ("he", "him", "his", "his"),
                "they/them": ("they", "them", "their", "theirs")}
# After {they} or {They}, only a verb that reads the same for she, he and they is accepted: an ALLOW-list,
# because a deny-list of auxiliaries let "They explains" through (752 fix review M2). Adverbs before it are
# skipped; anything else (a present-tense verb, a contraction, "and", the end of the comment) is refused.
UNCHANGING_AFTER_THEY = {"can", "could", "will", "would", "should", "might", "must", "may", "did", "had"}
PAST_TENSE_IRREGULAR = {"made", "wrote", "took", "gave", "found", "knew", "showed", "chose", "drew", "got", "kept", "led",
                        "left", "met", "put", "ran", "read", "said", "saw", "set", "spent", "stood", "thought", "told",
                        "understood", "won", "built", "brought", "began", "came", "went", "grew", "caught", "taught",
                        "held", "sought", "felt", "heard", "lost", "meant", "paid", "sent", "sat", "spoke", "threw",
                        "wore", "worked", "did", "had", "drove", "flew", "forgot", "rose", "sang", "swam", "tried",
                        "applied", "replied", "studied", "copied"}
PRESENT_ENDING_IN_ED = {"need", "proceed", "succeed", "exceed", "feed", "bleed", "breed", "heed", "speed", "seed", "weed",
                        "embed", "shred", "wed"}
SKIPPED_BEFORE_THE_VERB = {"also", "always", "often", "still", "never", "now", "even", "again", "then", "first", "each",
                           "both", "all", "already", "usually", "sometimes", "consistently", "clearly", "carefully"}
THEY_PLACEHOLDER = re.compile(r"\{[Tt]hey\}")


ESCAPES = [("\\", "\\textbackslash{}"), ("&", "\\&"), ("%", "\\%"), ("$", "\\$"), ("#", "\\#"), ("_", "\\_"),
           ("{", "\\{"), ("}", "\\}"), ("~", "\\textasciitilde{}"), ("^", "\\textasciicircum{}")]


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


def names_in(rows):
    """The table's forms of every name, as the runner builds them (the shared block above)."""
    return tokens_from(list(rows.values()))


def words_from_the_table(text, names):
    """1-based positions of the words in text that hold a form of a name in the table, counting each
    placeholder as one word, by the one comparison the runner makes. Never the word itself. A text that holds
    a form across words (none is known today) gives position 0."""
    plain = PLACEHOLDER.sub("\x00", text)
    if not holds_any_form(plain.replace("\x00", " "), names):
        return []
    positions = []
    for index, word in enumerate(plain.split(), start=1):
        if holds_any_form(word.replace("\x00", " "), names):
            positions.append(index)
    return positions or [0]


def lines_from_the_table(text, names):
    """1-based line numbers of the lines in text that hold a form of a name in the table."""
    numbers = []
    for number, line in enumerate(text.splitlines(), start=1):
        if holds_any_form(line, names):
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
    numbers = lines_from_the_table(text, names_in(rows))
    if numbers:
        print("A word from your mapping table is on " + plural(len(numbers), "line") + " of the file (line "
              + ", ".join(str(number) for number in numbers) + "). It could be a name, or an everyday word that is "
              "also a name in your table. Do not open the file: ask the teacher to read that line, and to change it, "
              "or, if it is not about a student, to tell you to go on, naming the line.")
        return 1
    print(f"Looked for the forms of the {plural(len(rows), 'name')} in your mapping table in "
          f"{plural(len(text.splitlines()), 'line')} of the file, and found none of them. A nickname, initials, or a "
          "name that is not in your table cannot be seen by this check: the teacher reads the file once for those "
          "before it is opened.")
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


def changing_verb_after_they(option):
    """1-based word positions (each placeholder one word) of a word after {they} that may change with the
    pronoun: everything but a modal, did, had, or a past tense, once adverbs are skipped."""
    plain = PLACEHOLDER.sub(lambda found: "\x00they\x00" if found.group(1) in ("they", "They") else "\x00", option)
    words = plain.split()
    positions = []
    for index, word in enumerate(words):
        if word != "\x00they\x00" and not word.startswith("\x00they\x00"):
            continue
        if word != "\x00they\x00":           # glued to it: {they}'s, {they}'re, {They},
            positions.append(index + 1)
            continue
        verdict = index + 1
        for later in range(index + 1, len(words)):
            bare = re.sub(r"[^A-Za-z'\u2019]", "", words[later]).lower()
            if bare in SKIPPED_BEFORE_THE_VERB or (bare.endswith("ly") and len(bare) > 4):
                continue
            accepted = (bare in UNCHANGING_AFTER_THEY or bare in PAST_TENSE_IRREGULAR or
                        (bare.endswith("ed") and bare not in PRESENT_ENDING_IN_ED))
            verdict = None if accepted else later + 1
            break
        if verdict is not None:
            positions.append(verdict)
    return positions


def own_record(cite, section, identifier, marking_folder, comments_folder):
    """True only for this student's own marks record, a file inside this marking folder at
    <Assessment>/Marks/Section N/<identifier>.json: a relative path with no "..", not absolute, not in the
    comments folder, and there (752 fix review L1)."""
    text = cite.replace("\\", "/")
    if not text or text.startswith("/") or re.match(r"^[A-Za-z]:", text):
        return False
    parts = text.split("/")
    if ".." in parts or "." in parts or "" in parts or len(parts) != 4:
        return False
    assessment, marks, section_folder, file_name = parts
    if marks != "Marks" or section_folder != f"Section {section}" or file_name != f"{identifier}.json":
        return False
    if assessment.startswith(".") or (marking_folder / assessment).resolve() == comments_folder.resolve():
        return False
    path = (marking_folder / text).resolve()
    if marking_folder.resolve() not in path.parents:
        return False
    return path.is_file()

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
    everyone = names_in(rows)
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
            if not isinstance(cite, str) or not own_record(cite, section, identifier, marking_folder, comments.parent):
                problems.append(f"{label}: cites something that is not this student's own marks record in this marking "
                                f"folder (each cite is <Assessment>/Marks/Section {section}/{identifier}.json, and that "
                                "file must be there)")
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
                                " holds a word from your mapping table before the names went in (it could be a name, "
                                "or an everyday word that is also a name in your table: rewrite this option without it)")
                continue
            verbs = changing_verb_after_they(option)
            if verbs:
                problems.append(f"{label} option {number}: word " + ", ".join(str(place) for place in verbs) +
                                " after {they} may change with the pronoun (they were, she was; they explain, she "
                                "explains): write a past tense other than was or were, or can or would")
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
                            + ", ".join(str(number) for number in numbers) + "; it could be a name, or an everyday word "
                            "that is also a name in your table: rewrite that line without it)")
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
    print("The named comments are in your teacher-only folder. I have not opened them, and I do not open them.")
    return 1 if over_the_limit else 0


# MARK: - Class results (#750, 750c)

def named_out_for(table, source, out, what):
    """The --out folder, refused unless it is inside the teacher-only folder that holds the table, apart from
    the source's own folder, and outside any working folder."""
    out = Path(out).resolve()
    source = Path(source).resolve()
    teacher_only = Path(table).resolve().parent
    if in_a_working_folder(out) or in_a_working_folder(source):
        raise Refusal(f"the named {what} must stay outside the Plantoir working folder; nothing was written")
    if out != teacher_only and teacher_only not in out.parents:
        raise Refusal(f"the named {what} must go in the teacher-only folder that holds the mapping table; nothing was written")
    if teacher_only == source.parent or teacher_only in source.parents:
        raise Refusal(f"the {what} to name must be the identifier one in the marking folder, not a file in the "
                      "teacher-only folder; nothing was written")
    if out == source.parent or source.parent in out.parents:
        raise Refusal(f"the named {what} must go in the teacher-only folder, never in the marking folder; nothing was written")
    return out


def make_named_document(table, document, out):
    if shutil.which("tectonic") is None or shutil.which("pdftotext") is None:
        raise Refusal("tectonic and Poppler's pdftotext are needed; nothing was written")
    out = named_out_for(table, document, out, "document")
    names = read_table(table)
    try:
        tex = Path(document).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        raise Refusal("the document could not be read as text; nothing was written")
    slots = DOCUMENT_SLOT.findall(tex)
    if not slots:
        raise Refusal("the document has no \\student{section}{identifier} for a name to go in; nothing was written")
    strange = 0
    for _section, identifier in slots:
        if not re.match(IDENTIFIER, identifier):
            strange += 1
    if strange:
        raise Refusal(f"{plural(strange, 'place')} in the document marked \\student hold something not like an "
                      "identifier; nothing was written")
    missing = []
    for section, identifier in slots:
        label = f"Section {section}/{identifier}"
        if (int(section), identifier) not in names and label not in missing:
            missing.append(label)
    if missing:
        raise Refusal(f"{plural(len(missing), 'student')} in the document {'is' if len(missing) == 1 else 'are'} not "
                      "in the mapping table (" + ", ".join(missing) + "); nothing was written")

    def put_in(match):
        name = names[(int(match.group(1)), match.group(2))]
        return "\\student{" + match.group(1) + "}{" + tex_escaped(name) + " (" + match.group(2) + ")}"

    named = DOCUMENT_SLOT.sub(put_in, tex)
    named = named.replace("\\copykind{identifiers only}", "\\copykind{with names, do not hand out}")
    stem = Path(document).stem
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / "document.tex"
        source.write_text(named, encoding="utf-8")
        result = subprocess.run(["tectonic", "-c", "minimal", str(source)], capture_output=True, cwd=folder)
        said = (result.stdout + result.stderr).decode("utf-8", "replace")
        pdf = Path(folder) / "document.pdf"
        if result.returncode != 0 or not pdf.exists():
            raise Refusal(f"the named copy of {stem} did not compile; nothing was written")
        if "Missing character" in said:
            raise Refusal(f"a name could not be set in the font of {stem}; nothing was written")
        printed = printed_text(pdf)
        # Each student's name AND identifier, as put in, counted on the page: a name printed once does not stand
        # for two students of that name, and a name inside another name is not this one (750c review, L5).
        wanted = {}
        for section, identifier in set(slots):
            form = comparable(names[(int(section), identifier)] + " (" + identifier + ")")
            wanted.setdefault(form, []).append(f"Section {section}/{identifier}")
        unset = []
        for form, labels in wanted.items():
            if printed.count(form) < len(labels):
                unset.extend(sorted(labels))
        if unset:
            raise Refusal(f"the name of {', '.join(unset)} could not be set in the font of {stem}; nothing was written")
        stranded = heading_left_alone(named, pdf)
        if stranded:
            raise Refusal(f"with the names in, a heading of {stem} is left alone at the foot of page {stranded}: keep more "
                          "room with its headings in the identifier document (its \\Needspace) and run this again; "
                          "nothing was written")
        out.mkdir(parents=True, exist_ok=True)
        target = out / (stem + NAMED_SUFFIX + ".pdf")
        partial = out / ("." + target.name + ".partial")
        shutil.copyfile(pdf, partial)
        os.replace(partial, target)
    students = set(slots)
    print(f"{stem}{NAMED_SUFFIX}.pdf written, with the names of {plural(len(students), 'student')} put in.")
    print("The named copy is in your teacher-only folder. I have not opened it, and I do not open it.")
    return 0


def heading_left_alone(tex, pdf):
    """The number of the first page whose last line, footers aside, is one of the document's headings
    ({\\large\\bfseries\\sffamily ...}), or 0. Names make rows taller, so the named copy breaks its pages
    in other places than the identifier one."""
    headings = set()
    for found in re.finditer(r"\\(?:LARGE|large|normalsize)\\bfseries\\sffamily ([^{}]+)\}", tex):
        headings.add(re.sub(r"\s+", " ", found.group(1).replace("\\", "")).strip())
    text = subprocess.run(["pdftotext", "-layout", str(pdf), "-"], capture_output=True).stdout.decode("utf-8", "replace")
    pages = [page for page in text.split("\f") if page.strip()]
    for index, page in enumerate(pages[:-1], start=1):
        lines = [line.strip() for line in page.splitlines() if line.strip()]
        lines = [line for line in lines if not re.match(r"^(Page \d+ of \d+|.*·.*)$", line)]
        if lines and re.sub(r"\s+", " ", lines[-1]) in headings:
            return index
    return 0


def read_grades(path):
    """(header, [(section, identifier, row)]) from a grade table class_results.py wrote, refusing any other shape."""
    try:
        with open(path, newline="", encoding="utf-8-sig") as handle:
            rows = list(csv.reader(handle))
    except (OSError, UnicodeDecodeError, csv.Error):
        raise Refusal("the grade table could not be read; nothing was written")
    if not rows or [cell.strip().casefold() for cell in rows[0][:2]] != ["section", "identifier"] or len(rows[0]) < 3:
        raise Refusal("the grade table does not start with the columns section and identifier, as class_results.py "
                      "writes it; nothing was written")
    if rows[0][-1].strip().casefold() != "built":
        raise Refusal("the grade table has no built column (when it was built, and its fingerprint), as class_results.py "
                      "writes it; build it again with class_results.py; nothing was written")
    found = []
    built = set()
    for row in rows[1:]:
        if not row:
            continue
        if len(row) != len(rows[0]) or not row[0].strip().isdigit() or not re.match(IDENTIFIER, row[1].strip()):
            raise Refusal("a row of the grade table is not like 1, Student A, then its marks; nothing was written")
        if not BUILT.match(row[-1]):
            raise Refusal("a row of the grade table has a built cell not as class_results.py writes it; nothing was written")
        built.add(row[-1])
        found.append((int(row[0].strip()), row[1].strip(), row))
    if len(built) > 1:
        raise Refusal("the rows of the grade table were built at different times; build it again with class_results.py; "
                      "nothing was written")
    return rows[0], found


def make_named_grades(table, grades, out):
    out = named_out_for(table, grades, out, "grade table")
    _columns, rows = read_table_rows(table)
    everyone = names_in(rows)
    header, students = read_grades(grades)
    problems = []
    seen = set()
    for section, identifier, row in students:
        label = f"Section {section}/{identifier}"
        if (section, identifier) in seen:
            problems.append(f"{label} is in the grade table twice")
            continue
        seen.add((section, identifier))
        if (section, identifier) not in rows:
            problems.append(f"{label}: not in the mapping table")
        for column, cell in enumerate(row[2:-1], start=3):
            if len(cell) > GRADE_CELL_LENGTH or holds_any_form(cell, everyone):
                problems.append(f"{label}: column {column} holds a word from your mapping table, or more than a number "
                                "or a level")
                break
    for column, cell in enumerate(header[2:], start=3):
        if holds_any_form(cell, everyone):
            problems.append(f"the heading of column {column} holds a word from your mapping table")
    target = out / (Path(grades).stem + NAMED_SUFFIX + ".csv")
    if problems:
        for problem in problems:
            print(problem)
        if target.is_file():
            os.replace(target, out / (Path(grades).stem + NAMED_SUFFIX + " - earlier run, do not use.csv"))
            print("The named grade table from an earlier run no longer matches, so it was renamed \"earlier run, do not "
                  "use\" in the teacher-only folder.")
        raise Refusal(f"{plural(len(problems), 'problem')} in the grade table; nothing was written")
    ordered = sorted(students, key=lambda student: (student[0], folded(rows[(student[0], student[1])][NAME_COLUMN]),
                                                    student[1]))
    lines = io.StringIO()
    writer = csv.writer(lines)
    writer.writerow(["name"] + header)
    for section, identifier, row in ordered:
        writer.writerow([rows[(section, identifier)][NAME_COLUMN]] + row)
    out.mkdir(parents=True, exist_ok=True)
    write_replacing(target, lines.getvalue(), "utf-8-sig")
    by_section = {}
    for section, _identifier, _row in students:
        by_section[section] = by_section.get(section, 0) + 1
    for section in sorted(by_section):
        print(f"Section {section}: {plural(by_section[section], 'row')} written, ordered by name")
    left_out = []
    for key in sorted(rows):
        if key[0] in by_section and key not in seen:
            left_out.append(f"Section {key[0]}/{key[1]}")
    if left_out:
        print(f"{plural(len(left_out), 'student')} in your mapping table, in the sections here, "
              f"{'has' if len(left_out) == 1 else 'have'} no row in the grade table: " + ", ".join(left_out))
    if students:
        stamp, fingerprint = students[0][2][-1].rsplit(" ", 1)
        print(f"Its rows say they were built {stamp}, fingerprint {fingerprint}, as class_results.py wrote them. After any "
              "change to a mark, a level or the settings, build the results again and then this again.")
    print(f"{target.name} is in your teacher-only folder. I have not opened it, and I do not open it.")
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
    print("Named copies are in your teacher-only folder. I have not opened them, and I do not open them.")
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


def self_test_results(compile_too):
    """An invented table, grade table and identifier document, through --grades (and --document when
    tectonic is here); the problems it found."""
    invented = ["Zedfamily", "Testfamily", "Bartholomewina", "Qoe"]
    problems = []
    with tempfile.TemporaryDirectory() as root:
        root_path = Path(root)
        results = root_path / "Marking" / "Unit 1 Test" / "Results"
        results.mkdir(parents=True)
        table = root_path / "Teacher only" / "Name Mapping Table.csv"
        table.parent.mkdir(parents=True)
        table.write_text('section,identifier,name\n1,Student A,"Zedfamily, Qoe"\n1,Student B,"Testfamily, Bartholomewina"\n',
                         encoding="utf-8")
        grades = results / "Grades - Unit 1 Test.csv"
        grades.write_text("section,identifier,K marks,K out of,built\n1,Student A,3,4,2026-11-13 09:00 0123456789ab\n"
                          "1,Student B,4,4,2026-11-13 09:00 0123456789ab\n", encoding="utf-8")
        out = root_path / "Teacher only" / "Unit 1 Test" / "Named"
        result = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--grades", str(grades), "--table",
                                 str(table), "--out", str(out)], capture_output=True, text=True, encoding="utf-8")
        said = result.stdout + result.stderr
        try:
            with open(out / "Grades - Unit 1 Test (Names).csv", newline="", encoding="utf-8-sig") as handle:
                rows = list(csv.reader(handle))
        except OSError:
            rows = []
        if [row[:3] for row in rows[1:]] != [["Testfamily, Bartholomewina", "1", "Student B"], ["Zedfamily, Qoe", "1", "Student A"]]:
            problems.append("the named grade table was not written with the names first, ordered by name")
        grades.write_text("section,identifier,K marks,built\n1,Student A,Zedfamily,2026-11-13 09:00 0123456789ab\n",
                          encoding="utf-8")
        refused = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--grades", str(grades), "--table",
                                  str(table), "--out", str(out / "again")], capture_output=True, text=True, encoding="utf-8")
        if refused.returncode != 1 or (out / "again").exists():
            problems.append("a grade table holding a name was not refused")
        said += refused.stdout + refused.stderr
        if compile_too:
            document = results / "Class Results.tex"
            document.write_text("\\documentclass{article}\\usepackage[T1]{fontenc}\\usepackage{lmodern}"
                                "\\newcommand{\\student}[2]{#2}\\begin{document}\\student{1}{Student A} and "
                                "\\student{1}{Student B}\\end{document}\n", encoding="utf-8")
            named = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--document", str(document),
                                    "--table", str(table), "--out", str(out)], capture_output=True, text=True, encoding="utf-8")
            said += named.stdout + named.stderr
            if named.returncode != 0 or not (out / "Class Results (Names).pdf").exists():
                problems.append("the named document was not written")
        for token in invented:
            if token.casefold() in said.casefold():
                problems.append("a name reached the output")
        for path in (root_path / "Marking").rglob("*"):
            if path.is_file() and path.parent != results:
                problems.append("something was written in the marking folder")
    return problems


def self_test():
    """The named sheets (when tectonic and pdftotext are here), the comments and the results, each on invented names."""
    problems = self_test_comments()
    sheets_tested = shutil.which("tectonic") is not None and shutil.which("pdftotext") is not None
    problems.extend(self_test_results(sheets_tested))
    if sheets_tested:
        problems.extend(self_test_sheets())
    if problems:
        print("self-test FAILED: " + "; ".join(sorted(set(problems))))
        return 1
    if sheets_tested:
        print("self-test passed: an invented name with TeX characters set and checked, a missing identifier "
              "reported by identifier, nothing written in the marking folder, no name printed; invented "
              "comments counted after the names went in, as NFC, and a draft holding a name refused; and an invented "
              "grade table and results document named, ordered by name, and a grade table holding a name refused. "
              "This checks the paths the test knows; it is no guarantee about changes it does not reach.")
    else:
        print("self-test passed for the comments and the grade table only: invented comments counted after the names "
              "went in, as NFC, and a draft holding a name refused; an invented grade table named, ordered by name, and "
              "one holding a name refused. The named sheets and documents were NOT tested: tectonic or pdftotext is not "
              "installed, and they cannot be made without them. This checks the paths the test knows; it is no "
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
    if option(arguments, "--document") is not None or option(arguments, "--grades") is not None:
        for needed in ("--table", "--out"):
            if option(arguments, needed) is None:
                raise Refusal(f"give {needed}")
        if option(arguments, "--document") is not None:
            return make_named_document(option(arguments, "--table"), option(arguments, "--document"), option(arguments, "--out"))
        return make_named_grades(option(arguments, "--table"), option(arguments, "--grades"), option(arguments, "--out"))
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
