#!/usr/bin/env python3
"""Build the class's results from the marks records, identifiers only: one document and one grade table per
assessment, written into the marking folder. Run it again after any change to a mark: the
documents do not change by themselves, and each one says when it was built and a fingerprint of everything
it was built from.

Part of the plantoir-marking skill. A STARTING POINT: copy it into the marking folder's Scripts/ folder,
adjust it to this teacher (see the two MARK blocks below), run --self-test, and only then use it. It reads
no name mapping table, so it is run directly, not through run_with_names.py.

    python3 -B class_results.py --assessment "<marking folder>/Unit 2 Test" --kit "<test>/Marking Kit/answers.json"
        [--assessment "<marking folder>/<another>" [--kit ...]] --checker ".../plantoir-test-authoring/scripts/check_kit.py"
        --settings "<marking folder>/Marking Settings.md" [--out "<marking folder>/<Term> Results"] [--title "Term 1"]
        [--school "School Name"] [--tex-only]
    python3 -B class_results.py --self-test --checker ".../check_kit.py"

For each --assessment (a folder of the marking folder, as plantoir-marking section 4 lays it out) it reads:

  Marks/Section N/Student A.json    the marks records of a test, each checked with check_kit.py against the
                                    --kit given after it; totals are counted from the points, never read
  Sheets/Section N/Student A - Marks by Question.tex   if there: the marks line build_test_sheet.py wrote
  Marking Settings.md               the "- Half marks:" and "- Percentages:" lines

and writes into --out (the assessment's own Results/ folder when there is one assessment):

  Class Results.tex and .pdf        marks by category for every student, section by section, with the
                                    section's means, when it was built and the fingerprint
  Grades - <Assessment>.csv         one row per student: marks, out of and percent by category
  (every row ends with "built": the build time and the fingerprint)

Russell, 2026-11-13, on the numbers a marked test shows: a point voided for the class is a BONUS for a student
who earned it: it leaves the "out of" for everyone, and a student who earned it keeps the mark, so a category
can read 2 out of 1, 200%. There is no overall percentage, ever: results are by category only. A test marked
by points never mentions levels: levels belong to work marked against a rubric or success criteria, which no
skill marks yet. A category with nothing to count and nothing earned is shown as not counted.

A sheet whose marks line no longer gives the record's totals STOPS the build, naming the
identifier and both numbers. So does a file that is not named like an identifier's record, a sheet with no
record, a sheet whose marks line cannot be read, and an assessment with no record. The documents are built
in a hidden folder and put in place only when every one is built; the last run's are first renamed
"earlier run, do not use", so a build that stops part way leaves no document that looks finished.

Needs tectonic and Poppler's pdftotext for the PDF (--tex-only writes the .tex and the tables without them).
Python standard library only.
"""
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from fractions import Fraction
from pathlib import Path

# MARK: - What you may change for this teacher
#   the document's wording, headings, school name and corners, paper size and colours; the file names; the ways
#   of rounding a percentage the settings may name (ROUNDINGS); the order of the grade table's columns (a report
#   system's own order); charts or a test-against-assignment comparison added to the document
#   (reference/results.md).
DOCUMENT = "Class Results"
GRADES = "Grades - {assessment}.csv"
PAPER = "letterpaper"
ROUNDINGS = {"whole numbers, half up": (0, "half up"), "one decimal, half up": (1, "half up"),
             "whole numbers, down": (0, "down")}
DEFAULT_ROUNDING = "whole numbers, half up"
NOT_COUNTED = "not counted"
SECTION = r"^Section (\d+)$"
SHEET_SUFFIX = " - Marks by Question.tex"

# MARK: - What must not change
#   never print, log or write outside the teacher-only folder any value read from a name mapping table (this
#   script reads none, and writes identifiers only); never print a file name that is not an identifier; capture
#   every program's output and print only counts and identifiers; refuse (exit 1, identifier-only message) when
#   anything is unexpected; never write inside a Plantoir working folder; a voided point is a bonus (in no
#   one's out of, kept by a student who earned it); no overall mark or percentage, ever; no level, ever, for a
#   test; a sheet whose totals differ from its record, an unreadable sheet, a sheet with no record, a file not
#   named like a record and a half mark without the settings' yes each stop the build; every document and every table row carries the build
#   time and a fingerprint of everything read, the settings included; documents are put in place only when all
#   are built, after the last run's are renamed "earlier run, do not use"; no document calls itself correct or
#   complete; the teacher-decides sentence below, word for word.
TEACHER_DECIDES = ("Every mark and comment here is a suggestion drafted for you. Grading is your "
                   "professional responsibility: please read and decide on each one before anything reaches "
                   "a student. I draft; you decide.")
EARLIER = " - earlier run, do not use"
BUILDING = ".building results"


# >>> The identifier rule. ONE rule, carried byte for byte in every plantoir-marking script that reads an
# identifier (redact_scans.py, build_test_sheet.py, make_named_copies.py, class_results.py; 750c fix review M1:
# a loose pattern let a record named like a person through, and the scripts disagreed). An identifier is the
# WHOLE name, matched in full: Student A to Student ZZ, and nothing else. scripts/test_marking_results.py fails if
# the copies differ or the contract's assessment.identifiers.pattern is not this one. A teacher whose papers are
# named another way renames them (redact_scans.py --name-papers does it from the mapping table).
IDENTIFIER = r"^Student [A-Z]{1,2}$"


def is_identifier(text):
    return isinstance(text, str) and re.fullmatch(IDENTIFIER, text) is not None
# <<< The identifier rule.


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding identifiers and counts only."""


def plural(number, word):
    return f"{number} {word}" if number == 1 else f"{number} {word}s"


def number(value):
    return str(int(value)) if float(value).is_integer() else str(value)


def in_a_working_folder(path):
    path = Path(path).resolve()
    for folder in [path] + list(path.parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            return True
    return False


# ---------------------------------------------------------------- the settings


class Settings:
    """What Marking Settings.md says for a test: half marks and the rounding. A - Levels scale: line is not read:
    a test marked by points never mentions levels (Russell, 2026-11-13)."""

    def __init__(self, path):
        if path is None or not Path(path).is_file():
            raise Refusal("give --settings with the course's Marking Settings.md (the half-marks and percentages "
                          "lines are read from it)")
        try:
            self.raw = Path(path).read_bytes()
            text = self.raw.decode("utf-8")
        except (OSError, UnicodeDecodeError):
            raise Refusal("Marking Settings.md could not be read as text")
        self.half_marks = False
        self.rounding = DEFAULT_ROUNDING
        self.rounding_said = False
        seen = set()
        for line in text.splitlines():
            found = re.match(r"\s*[-*]\s*(Half marks|Percentages):\s*(.*?)\s*$", line, re.IGNORECASE)
            if found is None:
                near = re.match(r"\s*[-*]\s*(half[ -]?marks?|percentages?)\s*:", line, re.IGNORECASE)
                if near is not None:
                    raise Refusal("Marking Settings.md has a line that looks like one this script reads but is not written "
                                  "as - Half marks: or - Percentages:; rewrite it so it is not passed over")
                continue
            key = found.group(1).casefold()
            value = found.group(2)
            if key != "half marks":
                value = re.sub(r"\s*\([^()]*\)$", "", value)     # the teacher's words and date, in brackets
            if key in seen:
                raise Refusal(f"Marking Settings.md has the - {found.group(1)}: line twice; keep one")
            seen.add(key)
            if key == "half marks":
                answer = re.match(r"^(yes|no)\s*(\(.*\))?$", value, re.IGNORECASE)
                if answer is None:
                    raise Refusal("the - Half marks: line in Marking Settings.md says neither yes nor no (the teacher's "
                                  "words and the date may follow in brackets)")
                self.half_marks = answer.group(1).casefold() == "yes"
            else:
                if value.casefold() not in ROUNDINGS:
                    raise Refusal("the - Percentages: line in Marking Settings.md is not one of: "
                                  + "; ".join(ROUNDINGS))
                self.rounding = value.casefold()
                self.rounding_said = True
        self.places, self.direction = ROUNDINGS[self.rounding]


def rounded(settings, earned, out_of):
    """The percentage as printed, as a Fraction, by the settings' rounding; None when nothing is counted."""
    if out_of == 0:
        return None
    exact = Fraction(str(earned)) * 100 / out_of
    scale = 10 ** settings.places
    if settings.direction == "half up":
        whole = (exact * scale + Fraction(1, 2)).numerator // (exact * scale + Fraction(1, 2)).denominator
    else:
        whole = (exact * scale).numerator // (exact * scale).denominator
    return Fraction(whole, scale)


def shown(settings, value):
    if value is None:
        return ""
    if settings.places == 0:
        return str(int(value))
    return f"{float(value):.{settings.places}f}"


# ---------------------------------------------------------------- reading one assessment


def read_json(path, what):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        raise Refusal(f"{what} could not be read as JSON; nothing was put in place")


def identifier_files(folder, identifier, problems, where):
    """[(section, identifier, path)] under folder/Section N/ in order (Student Z before Student AA). Anything else
    but a hidden file (a rescan saved beside a record, a file named another way, another folder) is a problem,
    counted and never named."""
    found = []
    strays = 0
    for section_folder in sorted(folder.iterdir(), key=lambda entry: (len(entry.name), entry.name)):
        if section_folder.name.startswith("."):
            continue
        match = re.match(SECTION, section_folder.name)
        if not section_folder.is_dir() or match is None:
            strays += 1
            continue
        for path in sorted(section_folder.iterdir(), key=lambda entry: (len(entry.stem), entry.name)):
            if path.name.startswith("."):
                continue
            if path.suffix == ".json" and path.is_file() and is_identifier(path.stem):
                found.append((int(match.group(1)), path.stem, path))
            else:
                strays += 1
    if strays:
        problems.append(f"{where}: {plural(strays, 'file or folder')} not named like Section N/<identifier>.json "
                        "(a rescan or a copy saved beside a record, or a name that is not an identifier) would "
                        "not be counted; rename or move "
                        + ("it" if strays == 1 else "them") + " (only identifiers like Student A are read)")
    return found


def check_record(checker, kit_path, record_path, label):
    result = subprocess.run([sys.executable, "-B", str(checker), str(kit_path), "--marks", str(record_path)],
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        rules = sorted(set(re.findall(r"\[([a-z-]+)\]", result.stdout)))
        raise Refusal(f"{label}: its marks record does not pass check_kit.py ({', '.join(rules)}); run it yourself "
                      "to see each line; nothing was put in place")


def category_marks(kit, record, label):
    """[(category key, earned, out of)] in the kit's order. A point the kit voids for the whole class is a bonus
    (Russell, 2026-11-13): it is in no one's out of, and a student who earned it keeps the mark, so a category can
    read 2 out of 1. build_test_sheet.py counts it the same way."""
    voided = kit.get("voided", {}) or {}
    result = []
    for category in kit["categories"]:
        earned = 0.0
        out_of = 0
        for point in kit["points"]:
            if point["category"] == category["key"]:
                earned += record["points"][point["id"]]["earned"]
                if point["id"] not in voided:
                    out_of += 1
        result.append((category["key"], earned, out_of))
    return result


def sheet_marks(path):
    """{category key: (earned, out of)} from the marks line of a Marks by Question .tex, or None if unreadable.
    A category with nothing counted reads "K not counted", as (0, 0)."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    match = re.search(r"^\{\\large\\bfseries\\sffamily (.+)\}\\par\\vspace\{2pt\}$", text, re.MULTILINE)
    if match is None:
        return None
    found = {}
    for part in match.group(1).split(" $\\cdot$ "):
        item = re.match(r"^(.+) ([0-9]+(?:\.[0-9]+)?)/([0-9]+)$", part.strip())
        if item is not None:
            found[item.group(1).replace("\\", "")] = (float(item.group(2)), int(item.group(3)))
            continue
        item = re.match(r"^(.+) " + NOT_COUNTED + r"$", part.strip())
        if item is None:
            return None
        found[item.group(1).replace("\\", "")] = (0.0, 0)
    return found


def said_as(key, earned, out_of):
    return f"{key} {NOT_COUNTED}" if out_of == 0 and earned == 0 else f"{key} {number(earned)}/{out_of}"


def read_marks(entry, checker, settings, identifier, problems, notes, read_paths):
    """[(section, identifier, [(key, earned, out of)])] for one assessment's marks records."""
    kit = entry["kit"]
    students = []
    records = identifier_files(entry["folder"] / "Marks", identifier, problems, f"{entry['name']}/Marks")
    if not records:
        problems.append(f"{entry['name']}: there is no marks record in its Marks folder")
    keys = set()
    for section, name, path in records:
        label = f"Section {section}/{name}"
        keys.add((section, name))
        read_paths.append(path)
        # A point is voided for the whole class or for nobody (750c fix review H1): the ruling is the kit's
        # voided list, and every record must void exactly those points. Checked here first, so the stop names
        # the identifier and the points rather than a checker rule.
        try:
            first_look = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, ValueError):
            first_look = None
        if isinstance(first_look, dict) and isinstance(first_look.get("voided", {}), dict):
            in_record = sorted(first_look.get("voided", {}) or {})
            in_kit = sorted(kit.get("voided", {}) or {})
            if in_record != in_kit:
                problems.append(f"{label}: its record voids {', '.join(in_record) or 'nothing'}, and the kit voids "
                                f"{', '.join(in_kit) or 'nothing'} for the whole class; record the ruling in the kit's "
                                "voided and in every record, then build every sheet again")
                continue
        check_record(checker, entry["kit_path"], path, label)
        record = read_json(path, f"{label}'s marks record")
        if record.get("identifier") != name or str(record.get("section")) != str(section):
            raise Refusal(f"{label}: the identifier or section inside its marks record is not its file's and folder's; "
                          "nothing was put in place")
        unmarked = []
        for point in kit["points"]:
            earned = record["points"][point["id"]]["earned"]
            if earned is None:
                unmarked.append(point["id"])
            elif earned == 0.5 and not settings.half_marks:
                raise Refusal(f"{label}: {point['id']} has a half mark, and your marking settings do not record a yes "
                              "to half marks; nothing was put in place")
        if unmarked:
            notes.append(f"{label}: not fully marked ({', '.join(unmarked)}), so it was left out")
            entry["left out"] += 1
            continue
        categories = category_marks(kit, record, label)
        sheet = entry["folder"] / "Sheets" / f"Section {section}" / (name + SHEET_SUFFIX)
        if sheet.is_file():
            read_paths.append(sheet)
            on_sheet = sheet_marks(sheet)
            if on_sheet is None:
                problems.append(f"{label}: its Marks by Question sheet's marks line could not be read, so it cannot be "
                                "compared with its record")
            else:
                said = []
                now = []
                kit_keys = []
                for key, earned, out_of in categories:
                    kit_keys.append(key)
                    printed = on_sheet.get(key)
                    if printed is None or abs(printed[0] - earned) > 1e-9 or printed[1] != out_of:
                        if printed is None:
                            said.append(f"{key} nothing")
                        else:
                            said.append(said_as(key, printed[0], printed[1]))
                        now.append(said_as(key, earned, out_of))
                for key in on_sheet:
                    if key not in kit_keys:
                        said.append(said_as(key, on_sheet[key][0], on_sheet[key][1]))
                        now.append(f"no category {key}")
                if said:
                    problems.append(f"{label}: its sheet says {', '.join(said)}, and its marks record now gives "
                                    f"{', '.join(now)}")
                else:
                    entry["sheets agree"] += 1
        else:
            entry["no sheet"] += 1
        students.append((section, name, categories))
    sheets = entry["folder"] / "Sheets"
    if sheets.is_dir():
        for section_folder in sorted(sheets.iterdir(), key=lambda found: (len(found.name), found.name)):
            match = re.match(SECTION, section_folder.name)
            if not section_folder.is_dir() or match is None:
                continue
            for path in sorted(section_folder.iterdir()):
                if not path.name.endswith(SHEET_SUFFIX):
                    continue
                name = path.name[:-len(SHEET_SUFFIX)]
                if not is_identifier(name):
                    problems.append(f"{entry['name']}/Sheets: a Marks by Question sheet not named like an identifier")
                elif (int(match.group(1)), name) not in keys:
                    problems.append(f"Section {match.group(1)}/{name}: a Marks by Question sheet with no marks record "
                                    "beside it (the record was renamed, moved or deleted)")
    return students


def esc(text):
    text = str(text).replace("\\", "\x00")
    for character in "&%$#_{}":
        text = text.replace(character, "\\" + character)
    text = text.replace("\x00", "\\textbackslash{}")
    text = text.replace("~", "\\textasciitilde{}").replace("^", "\\textasciicircum{}")
    text = text.replace("--", "-{}-").replace("→", "$\\rightarrow$").replace("·", "$\\cdot$")
    return text


def student(section, identifier):
    """The one place make_named_copies.py --document puts a name: \\student{section}{identifier}."""
    return "\\student{" + str(section) + "}{" + identifier + "}"


def preamble(title, course, school):
    return (r"""\documentclass[11pt]{article}
\usepackage[""" + PAPER + r""",margin=0.75in,bottom=0.9in]{geometry}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage[table]{xcolor}
\usepackage{array,longtable}
\usepackage{fancyhdr,lastpage}
\usepackage{needspace}
\setlength{\parindent}{0pt}
\setlength{\parskip}{4pt}
\setlength{\LTleft}{0pt}\setlength{\LTright}{\fill}
\renewcommand{\arraystretch}{1.3}
\definecolor{subtitle}{gray}{0.45}
% A student, by section and identifier: the ONE place make_named_copies.py --document fills a name in.
\newcommand{\student}[2]{#2}
% What kind of copy this is; make_named_copies.py --document changes it on the named copy.
\newcommand{\copykind}[1]{#1}
\newcolumntype{C}[1]{>{\centering\arraybackslash}p{#1}}
\pagestyle{fancy}
\fancyhf{}
\renewcommand{\headrulewidth}{0pt}
\lhead{\small\sffamily\color{gray}""" + esc(school) + r"""}
\lfoot{\small\sffamily\color{gray}""" + esc(title) + (r"\ $\cdot$ " + esc(course) if course else "") + r"""}
\rfoot{\small\sffamily\color{gray}Page \thepage\ of \pageref{LastPage}}
\begin{document}
""")


def heading(text, size="large"):
    """A heading kept with what follows it: a part's heading with room for its first section's heading and the
    first rows of its table, a section's with room for its table's first rows."""
    room = "14" if size == "large" else "8"
    return ("\\Needspace{" + room + "\\baselineskip}{\\" + size + "\\bfseries\\sffamily " + esc(text)
            + "}\\par\\nobreak\\vspace{2pt}\n")


def table_start(columns, header_cells):
    width = ("\\dimexpr(\\textwidth-4.2cm-" + str(2 * (columns + 1)) + "\\tabcolsep-" + str(columns + 2)
             + "\\arrayrulewidth)/" + str(columns) + "\\relax")
    spec = "|>{\\raggedright\\arraybackslash}p{4.2cm}|" + "|".join(["C{" + width + "}"] * columns) + "|"
    head = "\\hline\n\\rowcolor{gray!15}" + " & ".join(header_cells) + "\\\\\n\\hline\n"
    return "{\\small\n\\begin{longtable}{" + spec + "}\n" + head + "\\endfirsthead\n" + head + "\\endhead\n"


def marks_cell(settings, earned, out_of):
    if out_of == 0:
        return NOT_COUNTED if earned == 0 else f"{number(earned)}/0 (a bonus; no percentage)"
    value = rounded(settings, earned, out_of)
    return f"{number(earned)}/{out_of} ({shown(settings, value)}\\%)"


def marks_part(name, kit, students, settings, notes_for_part):
    tex = heading(name + ": marks by category")
    titles = []
    for category in kit["categories"]:
        titles.append(esc(category["key"]) + " " + esc(category["title"]))
    tex += "{\\small " + "; ".join(titles) + ".}\\par\\vspace{4pt}\n"
    sections = sorted(set(section for section, _identifier, _categories in students))
    for section in sections:
        tex += heading(f"Section {section}", "normalsize")
        header = ["\\textbf{Student}"]
        for category in kit["categories"]:
            header.append("\\textbf{" + esc(category["key"]) + "}")
        tex += table_start(len(kit["categories"]), header)
        sums = []
        counts = []
        for _column in range(len(kit["categories"])):
            sums.append(Fraction(0))
            counts.append(0)
        for row_section, identifier, categories in students:
            if row_section != section:
                continue
            cells = [student(section, identifier)]
            for index, (_key, earned, out_of) in enumerate(categories):
                cells.append(marks_cell(settings, earned, out_of))
                if out_of:
                    sums[index] += Fraction(str(earned)) * 100 / out_of
                    counts[index] += 1
            tex += " & ".join(cells) + "\\\\\n\\hline\n"
        means = ["\\textit{Section mean}"]
        for index in range(len(sums)):
            if counts[index] == 0:
                means.append(NOT_COUNTED)
            else:
                means.append(shown(settings, rounded(settings, sums[index] / counts[index] / 100, 1)) + "\\%")
        tex += "\\rowcolor{gray!8}" + " & ".join(means) + "\\\\\n\\hline\n\\end{longtable}}\n"
    for line in notes_for_part:
        tex += "{\\small " + esc(line) + "}\\par\n"
    return tex


def built_from(entries, stamp, fingerprint, settings, assessments_text):
    tex = heading("What this was built from")
    tex += (f"Built on {esc(stamp)} from these records and Marking Settings.md (fingerprint {fingerprint}): "
            + esc(assessments_text) + " After any change to a mark or the settings, run class\\_results.py "
            "again, and then make the named copies again: this document does not change by itself.\\par\n")
    tex += ("{\\small Each category's mark is the sum of its points earned, out of its points. A point the teacher "
            "voided for the class is a bonus: it is in no one's out of, and a student who earned it keeps the mark, as "
            "on the feedback sheet, so a category can read more than its out of. A category with nothing to count and "
            "nothing earned is shown as not counted and left out of the means. There is no overall mark: results are "
            "by category. Percentages are rounded to " + esc(settings.rounding)
            + (" (the - Percentages: line of Marking Settings.md)." if settings.rounding_said else
               " (the default: Marking Settings.md has no - Percentages: line)."))
    tex += "}\\par\\vspace{6pt}\n"
    return tex


# ---------------------------------------------------------------- compiling and checking pages


def compile_and_check(tex, target_pdf, headings):
    """(pages, None) or (None, why): compile in a temporary folder with the output captured, then look at the
    last line of every page for a heading left alone."""
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / "results.tex"
        source.write_text(tex, encoding="utf-8")
        result = subprocess.run(["tectonic", "-c", "minimal", str(source)], capture_output=True, text=True, cwd=folder)
        built = Path(folder) / "results.pdf"
        if result.returncode != 0 or not built.exists():
            first = ""
            for line in result.stderr.splitlines():
                if line.startswith("error:") or line.startswith("!"):
                    first = line.strip()
                    break
            return None, f"{DOCUMENT} did not compile ({first or 'see the .tex'})"
        pages = subprocess.run(["pdftotext", "-layout", str(built), "-"], capture_output=True, text=True).stdout.split("\f")
        pages = [page for page in pages if page.strip()]
        for index, page in enumerate(pages[:-1], start=1):
            lines = [line.strip() for line in page.splitlines() if line.strip()]
            lines = [line for line in lines if not re.match(r"^(Page \d+ of \d+|.*·.*)$", line)]
            if lines:
                last = re.sub(r"\s+", " ", lines[-1])
                for title in headings:
                    if last == title:
                        return None, f"a heading is left alone at the foot of page {index} of {DOCUMENT} ({title})"
        shutil.copyfile(built, target_pdf)
        return len(pages), None


# ---------------------------------------------------------------- the build


def written_names(entries):
    names = [DOCUMENT + ".tex", DOCUMENT + ".pdf"]
    for entry in entries:
        names.append(GRADES.format(assessment=entry["name"]))
    return names


def set_earlier_run_aside(out, entries):
    renamed = 0
    if not out.is_dir():
        return 0
    for name in written_names(entries):
        path = out / name
        if path.is_file():
            stem, dot, suffix = name.rpartition(".")
            os.replace(path, out / (stem + EARLIER + dot + suffix))
            renamed += 1
    return renamed


def remove_earlier_run(out, entries):
    for name in written_names(entries):
        stem, dot, suffix = name.rpartition(".")
        path = out / (stem + EARLIER + dot + suffix)
        if path.is_file():
            os.remove(path)


def fingerprint_of(paths, settings, identifier):
    """12 hex digits of SHA-256 over every file read (kit, records, sheets), the settings and the identifier
    pattern, so a document built from other records or other rounding has another fingerprint."""
    digest = hashlib.sha256()
    for path in sorted(set(paths), key=str):
        digest.update(str(path.name).encode("utf-8") + b"\x00")
        digest.update(path.read_bytes())
    digest.update(b"settings\x00" + settings.raw)
    digest.update(b"identifiers\x00" + identifier.encode("utf-8"))
    return digest.hexdigest()[:12]


def csv_text(rows):
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    for row in rows:
        writer.writerow(row)
    return buffer.getvalue()


def grade_rows(kit, students, settings, built):
    header = ["section", "identifier"]
    for category in kit["categories"]:
        header.extend([f"{category['key']} marks", f"{category['key']} out of", f"{category['key']} %"])
    header.append("built")
    rows = [header]
    for section, identifier, categories in sorted(students, key=lambda row: (row[0], len(row[1]), row[1])):
        row = [str(section), identifier]
        for _key, earned, out_of in categories:
            value = rounded(settings, earned, out_of)
            row.extend([number(earned), str(out_of), shown(settings, value)])
        row.append(built)
        rows.append(row)
    return rows


def build(entries, checker, settings_path, out, title, school, tex_only, identifier):
    if checker is None or not Path(checker).is_file():
        raise Refusal("the kit checker was not found: give --checker with the path to the plantoir-test-authoring "
                      "skill's scripts/check_kit.py")
    if not entries:
        raise Refusal("give at least one --assessment")
    if out is None:
        if len(entries) != 1:
            raise Refusal("give --out (a results folder in the marking folder) when there is more than one assessment")
        out = entries[0]["folder"] / "Results"
    out = Path(out).resolve()
    for path in [out] + [entry["folder"] for entry in entries]:
        if in_a_working_folder(path):
            raise Refusal("a folder given is inside the Plantoir working folder; marking is kept outside it")
    building = out / BUILDING
    try:
        if building.exists():
            shutil.rmtree(building)
        if set_earlier_run_aside(out, entries):
            print("The results of the last run were renamed \"earlier run, do not use\" until this run puts new ones "
                  "in place.")
        return build_in(entries, checker, settings_path, out, building, title, school, tex_only, identifier)
    except Refusal:
        if building.exists():
            shutil.rmtree(building)
        raise
    except Exception as error:   # never a traceback; nothing half built is left in place
        if building.exists():
            shutil.rmtree(building)
        raise Refusal(f"something unexpected went wrong ({type(error).__name__}); no document of this run was put in "
                      "place")


def build_in(entries, checker, settings_path, out, building, title, school, tex_only, identifier):
    settings = Settings(settings_path)
    if not tex_only and (shutil.which("tectonic") is None or shutil.which("pdftotext") is None):
        raise Refusal("tectonic and Poppler's pdftotext are needed for the PDF (on a Mac with Homebrew: brew install "
                      "tectonic poppler), or give --tex-only; nothing was put in place")
    problems = []
    notes = []
    said = []
    read_paths = []
    for entry in entries:
        entry["folder"] = Path(entry["folder"]).resolve()
        entry.update({"left out": 0, "no sheet": 0, "sheets agree": 0, "marks": [], "notes": []})
        if not entry["folder"].is_dir():
            raise Refusal("an --assessment folder was not found")
        if not (entry["folder"] / "Marks").is_dir():
            raise Refusal(f"{entry['name']}: it has no Marks folder, so there is nothing to build from; nothing was put "
                          "in place")
        if True:
            if entry["kit_path"] is None:
                raise Refusal(f"{entry['name']}: give --kit after its --assessment (the marks records are counted from "
                              "the kit's points); nothing was put in place")
            entry["kit"] = read_json(entry["kit_path"], f"{entry['name']}'s kit")
            read_paths.append(Path(entry["kit_path"]))
            before = len(notes)
            entry["marks"] = read_marks(entry, checker, settings, identifier, problems, notes, read_paths)
            entry["notes"] = notes[before:]
            counts = {}
            for section, _name, _categories in entry["marks"]:
                counts[section] = counts.get(section, 0) + 1
            if counts:
                said.append(f"{entry['name']}: " + "; ".join(
                    f"Section {section}: {plural(counts[section], 'marks record')} counted" for section in sorted(counts)))
    if problems:
        for problem in problems:
            print(problem)
        stale = 0
        for problem in problems:
            if "its sheet says" in problem:
                stale += 1
        if stale:
            raise Refusal(f"{plural(stale, 'sheet')} no longer {'gives' if stale == 1 else 'give'} the totals its record "
                          "gives: build those sheets again with build_test_sheet.py, then run this again; nothing was "
                          "put in place")
        raise Refusal(f"{plural(len(problems), 'problem')} in the records; nothing was put in place")
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    fingerprint = fingerprint_of(read_paths, settings, identifier)
    built = f"{stamp} {fingerprint}"
    total_records = 0
    pieces = []
    for entry in entries:
        marks_count = len(entry["marks"])
        total_records += marks_count
        if marks_count:
            pieces.append(f"{entry['name']}, {plural(marks_count, 'marks record')}")
    assessments_text = "; ".join(pieces) + "."
    names = []
    for entry in entries:
        names.append(entry["name"])
    document_title = (title or " and ".join(names)) + ": " + DOCUMENT
    course = ""
    for entry in entries:
        if entry.get("kit") and not course:
            course = str(entry["kit"].get("course", ""))
    tex = preamble(document_title, course, school)
    tex += "{\\LARGE\\bfseries\\sffamily " + esc(document_title) + "}\\par\\vspace{2pt}\n"
    tex += ("{\\color{subtitle}\\sffamily \\copykind{identifiers only} $\\cdot$ teacher only $\\cdot$ built "
            + esc(stamp) + " $\\cdot$ fingerprint " + fingerprint + "}\\par\\vspace{4pt}\n")
    tex += "{\\small\\itshape " + esc(TEACHER_DECIDES) + "}\\par\\vspace{6pt}\n"
    tex += built_from(entries, stamp, fingerprint, settings, assessments_text)
    headings = ["What this was built from"]
    listed = []
    for entry in entries:
        if entry["marks"]:
            tex += marks_part(entry["name"], entry["kit"], entry["marks"], settings, entry["notes"])
            headings.append(entry["name"] + ": marks by category")
    for section in range(1, 100):
        headings.append(f"Section {section}")
    tex += "\\end{document}\n"
    building.mkdir(parents=True)
    staged = [DOCUMENT + ".tex"]
    (building / (DOCUMENT + ".tex")).write_text(tex, encoding="utf-8")
    for entry in entries:
        if entry["marks"]:
            name = GRADES.format(assessment=entry["name"])
            (building / name).write_text(csv_text(grade_rows(entry["kit"], entry["marks"], settings, built)), encoding="utf-8")
            staged.append(name)
    pages = None
    if not tex_only:
        pages, why = compile_and_check(tex, building / (DOCUMENT + ".pdf"), headings)
        if pages is None:
            raise Refusal(why + "; nothing was put in place")
        staged.append(DOCUMENT + ".pdf")
    for name in staged:                      # every document is built; only now are they put in place
        os.replace(building / name, out / name)
    shutil.rmtree(building)
    remove_earlier_run(out, entries)
    for line in said:
        print(line)
    for line in notes:
        print(line)
    for line in listed:
        print(line)
    sheets_agree = 0
    no_sheet = 0
    left_out = 0
    for entry in entries:
        sheets_agree += entry["sheets agree"]
        no_sheet += entry["no sheet"]
        left_out += entry["left out"]
    if sheets_agree:
        print(f"The totals on {plural(sheets_agree, 'sheet')} were compared with the marks records, and agree.")
    if no_sheet:
        print(f"{plural(no_sheet, 'marks record')} with no Marks by Question sheet yet, so not compared.")
    for name in staged:
        if name == DOCUMENT + ".pdf":
            print(f"Wrote {name} ({plural(pages, 'page')}; no heading was left alone at the foot of a page)")
        else:
            print(f"Wrote {name}")
    print(f"Built {stamp} from {plural(total_records, 'record')} and Marking Settings.md (fingerprint {fingerprint}). "
          "These hold identifiers only. After any change to a mark or the settings, run this again and make "
          "the named copies again: they do not change by themselves.")
    return 1 if left_out else 0


# ---------------------------------------------------------------- the self-test


def self_test(checker):
    """An invented kit, records, settings and a sheet, through the main path; the problems it found."""
    kit = {"kit": 1, "test": "A Test About Dice", "course": "MDM4U",
           "categories": [{"key": "K", "title": "Knowledge and Understanding"}, {"key": "T", "title": "Thinking"}],
           "parts": [{"key": "A", "title": "Part A", "category": "K"}, {"key": "B", "title": "Part B", "category": "T"}],
           "questions": [{"id": "A1", "part": "A", "skill": "The chance of one roll", "topics": []},
                         {"id": "B1", "part": "B", "skill": "The chance of two rolls", "topics": []}],
           "points": [{"id": "A1", "question": "A1", "category": "K", "meaning": "question 1"},
                      {"id": "B1.1", "question": "B1", "category": "T", "meaning": "the outcomes counted"},
                      {"id": "B1.2", "question": "B1", "category": "T", "meaning": "the probability"}],
           "versions": {"A": {"source": "Version A.tex", "answers": {"A1": {"answer": "c", "accept": []},
                                                                     "B1.1": {"answer": "36", "accept": []},
                                                                     "B1.2": {"answer": "1/6", "accept": []}}}},
           "strengths": [], "topics": {}}

    def record(identifier, earned, voided):
        points = {}
        for point_id, value in zip(("A1", "B1.1", "B1.2"), earned):
            points[point_id] = {"earned": value, "seen": "", "note": "", "studentNote": "" if value == 1 else "A reason."}
        return {"kit": 1, "identifier": identifier, "section": 1, "version": "A", "points": points,
                "voided": voided, "checks": [], "summary": "", "byQuestion": [], "strengths": [], "focus": [],
                "closing": "", "feedback": {}}

    problems = []
    with tempfile.TemporaryDirectory() as root:
        marking = Path(root) / "Marking"
        assessment = marking / "Unit 1 Test"
        (assessment / "Marks" / "Section 1").mkdir(parents=True)
        (assessment / "Sheets" / "Section 1").mkdir(parents=True)
        kit_path = Path(root) / "answers.json"
        kit_path.write_text(json.dumps(kit), encoding="utf-8")
        voided = {"B1.2": {"reason": "the question did not work", "intended": "a second roll"}}
        (assessment / "Marks" / "Section 1" / "Student A.json").write_text(
            json.dumps(record("Student A", [1, 0, 1], {})), encoding="utf-8")
        (assessment / "Marks" / "Section 1" / "Student B.json").write_text(
            json.dumps(record("Student B", [1, 1, 1], voided)), encoding="utf-8")
        settings = marking / "Marking Settings.md"
        settings.write_text("- Half marks: no\n- Levels scale: 4 83, 3 71, 2 62, 1 51\n", encoding="utf-8")   # never read
        sheet = assessment / "Sheets" / "Section 1" / ("Student A" + SHEET_SUFFIX)
        sheet.write_text("{\\large\\bfseries\\sffamily K 1/1 $\\cdot$ T 2/2}\\par\\vspace{2pt}\n", encoding="utf-8")

        def run(extra):
            return subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--assessment", str(assessment),
                                   "--kit", str(kit_path), "--checker", str(checker), "--settings", str(settings)] + extra,
                                  capture_output=True, text=True, encoding="utf-8")

        split = run(["--tex-only"])
        if split.returncode != 1 or "Section 1/Student B: its record voids B1.2, and the kit voids nothing" not in split.stdout:
            problems.append("records voiding different points did not stop the build")
        kit["voided"] = voided
        kit_path.write_text(json.dumps(kit), encoding="utf-8")
        (assessment / "Marks" / "Section 1" / "Student A.json").write_text(
            json.dumps(record("Student A", [1, 0, 1], voided)), encoding="utf-8")
        stale = run(["--tex-only"])
        if stale.returncode != 1 or "Section 1/Student A: its sheet says T 2/2, and its marks record now gives T 1/1" not in stale.stdout:
            problems.append("a sheet whose totals differ from its record did not stop the build")
        if (assessment / "Results" / (DOCUMENT + ".tex")).exists():
            problems.append("a stopped build put a document in place")
        sheet.write_text("{\\large\\bfseries\\sffamily K 1/1 $\\cdot$ T 1/1}\\par\\vspace{2pt}\n", encoding="utf-8")
        good = run(["--tex-only"])
        if good.returncode != 0:
            problems.append("the invented records were not built")
        try:
            with open(assessment / "Results" / GRADES.format(assessment="Unit 1 Test"), newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
        except OSError:
            rows = []
        if len(rows) != 2 or rows[0].get("T marks") != "1" or rows[0].get("T out of") != "1":
            problems.append("the grade table's marks are not the sum of the points")
        if len(rows) == 2 and (rows[1].get("T marks") != "2" or rows[1].get("T out of") != "1" or rows[1].get("T %") != "200"):
            problems.append("a voided point a student earned was not kept as a bonus (2 out of 1, 200%)")
        if rows and any(("total" in key or "level" in key) for key in rows[0]):
            problems.append("the grade table has an overall mark or a level")
        if len(rows) == 2 and not re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d [0-9a-f]{12}$", rows[0].get("built", "")):
            problems.append("a row of the grade table does not say when it was built")
        tex = (assessment / "Results" / (DOCUMENT + ".tex")).read_text(encoding="utf-8") if (assessment / "Results" / (DOCUMENT + ".tex")).exists() else ""
        if "Total" in tex or "level" in tex.casefold():
            problems.append("the document has an overall mark or a level")
        if shutil.which("tectonic") is not None and shutil.which("pdftotext") is not None:
            compiled = run([])
            if compiled.returncode != 0 or not (assessment / "Results" / (DOCUMENT + ".pdf")).exists():
                problems.append("the invented document did not compile")
        for path in Path(root).rglob("*"):
            if path.is_file() and assessment / "Results" in path.parents and path.suffix not in (".tex", ".pdf", ".csv"):
                problems.append("something else was written in the results folder")
    if problems:
        print("self-test FAILED: " + "; ".join(sorted(set(problems))))
        return 1
    compiled_too = shutil.which("tectonic") is not None and shutil.which("pdftotext") is not None
    print("self-test passed: records voiding different points stopped the build, invented records counted point by "
          "point with a point the kit voids kept as a bonus by the student who earned it (2 out of 1, 200%), a sheet "
          "whose totals differ stopped the build and put nothing in place, no overall mark and no level anywhere "
          "(a Levels scale line in the settings is not read), every row stamped. "
          + ("The PDF was compiled. " if compiled_too else "The PDF was NOT tested: tectonic or pdftotext is not "
             "installed, and it cannot be made without them. ")
          + "This checks the paths the test knows; it is no guarantee about changes it does not reach.")
    return 0


# ---------------------------------------------------------------- the command line


def option(arguments, name, default=None):
    if name in arguments:
        index = arguments.index(name)
        if index + 1 >= len(arguments):
            raise Refusal(f"{name} needs a value")
        return arguments[index + 1]
    return default


def assessments_from(arguments):
    """[{folder, name, kit_path}]: each --kit belongs to the --assessment before it."""
    entries = []
    index = 0
    while index < len(arguments):
        if arguments[index] in ("--assessment", "--kit"):
            if index + 1 >= len(arguments):
                raise Refusal(f"{arguments[index]} needs a value")
            value = arguments[index + 1]
            if arguments[index] == "--assessment":
                entries.append({"folder": Path(value), "name": Path(value).resolve().name, "kit_path": None})
            elif not entries:
                raise Refusal("give --kit after the --assessment it belongs to")
            else:
                entries[-1]["kit_path"] = Path(value)
            index += 2
            continue
        index += 1
    return entries


def main(arguments):
    if not arguments or arguments[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    checker = option(arguments, "--checker")
    if "--self-test" in arguments:
        if checker is None:
            raise Refusal("--self-test needs --checker")
        return self_test(checker)
    return build(assessments_from(arguments), checker, option(arguments, "--settings"), option(arguments, "--out"),
                 option(arguments, "--title"), option(arguments, "--school", ""), "--tex-only" in arguments,
                 IDENTIFIER)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); nothing was put in place")
        sys.exit(1)
