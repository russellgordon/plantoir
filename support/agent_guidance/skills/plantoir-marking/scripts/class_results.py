#!/usr/bin/env python3
"""Build the class's results from the marks records, identifiers only: one document and one grade table per
assessment, written into the marking folder. Run it again after any change to a mark or a level: the
documents do not change by themselves, and each one says when it was built and from which records.

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
  Records/Section N/Student A.json  levels for each category, first and revised, ONLY IF the folder is there
                                    ({"identifier": "Student A", "section": 1, "levels": {"K": {"first": "3",
                                    "revised": "3+"}}}, reference/results.md); no skill writes them yet for a
                                    coding assignment, so the document says plainly when there are none
  Sheets/Section N/Student A - Marks by Question.tex   if there: the marks line build_test_sheet.py wrote

and writes into --out (the assessment's own Results/ folder when there is one assessment):

  Class Results.tex and .pdf        marks by category for every student, section by section, with the
                                    section's means; levels first and revised; the students with no revised
                                    levels; when it was built, from which records, and which parts had none
  Grades - <Assessment>.csv         one row per student: marks, out of and percent by category, and the total
  Levels - <Assessment>.csv         one row per student with a level record: first, revised, the level and its
                                    percent from the scale

Each total is the sum of its points. A sheet whose marks line no longer gives the totals the points give
STOPS the build, naming the identifier and both numbers: the student was told something the record no
longer says. The levels scale comes from Marking Settings.md ("- Levels scale: 4+ 95, 4 90, ..."), never
from this script. The named copy of the document and the named grade table for a report system are made
only by make_named_copies.py (--document, --grades), through the runner, into the teacher-only folder.

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
from pathlib import Path

# MARK: - What you may change for this teacher
#   the document's wording, headings, school name and corners, paper size and colours; the file names; how a
#   level is read from a percentage (LEVEL_FROM_PERCENT: "at or below", the highest level whose percentage is at
#   or below the mark, or "nearest"); how a percentage is rounded; the columns of the grade tables (a report
#   system's own order); weighting categories differently for an overall mark (the default is the plain sum of
#   points); charts or a test-against-assignment comparison added to the document (reference/results.md).
DOCUMENT = "Class Results"
GRADES = "Grades - {assessment}.csv"
LEVELS = "Levels - {assessment}.csv"
PAPER = "letterpaper"
LEVEL_FROM_PERCENT = "at or below"
NO_REVISION_TITLE = "No revised levels"
IDENTIFIER = r"^Student [A-Z]{1,2}$"
SECTION = r"^Section (\d+)$"
SHEET_SUFFIX = " - Marks by Question.tex"

# MARK: - What must not change
#   never print, log or write outside the teacher-only folder any value read from a name mapping table (this
#   script reads none, and writes identifiers only); never print a file name that is not an identifier; capture
#   every program's output and print only counts and identifiers; refuse (exit 1, identifier-only message) when
#   anything is unexpected; never write inside a Plantoir working folder; a total is the sum of its points, and a
#   sheet whose totals differ from its points stops the build with the identifier and both numbers; a level
#   that is not on the teacher's scale stops it; a half mark is counted only with the settings' yes; on a stop,
#   nothing new is written and the documents of an earlier run are renamed "earlier run, do not use"; every
#   document says when it was built and from which records, and never calls itself correct or complete; the
#   teacher-decides sentence below, word for word.
TEACHER_DECIDES = ("Every mark, level and comment here is a suggestion drafted for you. Grading is your "
                   "professional responsibility: please read and decide on each one before anything reaches "
                   "a student. I draft; you decide.")
EARLIER = " - earlier run, do not use"


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding identifiers and counts only."""


def plural(number, word):
    return f"{number} {word}" if number == 1 else f"{number} {word}s"


def number(value):
    return str(int(value)) if float(value).is_integer() else str(value)


def percent(earned, out_of):
    """A whole percent, halves rounded up, or None when nothing is counted."""
    if out_of == 0:
        return None
    return int(earned * 100.0 / out_of + 0.5 + 1e-9)


def in_a_working_folder(path):
    path = Path(path).resolve()
    for folder in [path] + list(path.parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            return True
    return False


# ---------------------------------------------------------------- the settings


def read_settings(path):
    """(half marks allowed, the scale as [(level, percent)] highest first, or None)."""
    if path is None or not Path(path).is_file():
        raise Refusal("give --settings with the course's Marking Settings.md (the half-marks line and the levels scale are read from it)")
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        raise Refusal("Marking Settings.md could not be read as text")
    half_marks = False
    scale = None
    for line in text.splitlines():
        half = re.match(r"\s*[-*]\s*Half marks:\s*(\w+)", line, re.IGNORECASE)
        if half:
            half_marks = half.group(1).casefold() == "yes"
        found = re.match(r"\s*[-*]\s*Levels scale:\s*(.*)$", line, re.IGNORECASE)
        if found:
            scale = read_scale(found.group(1).strip())
    return half_marks, scale


def read_scale(value):
    if value == "" or value.casefold().startswith("none"):
        return None
    entries = []
    seen = set()
    for item in value.split(","):
        match = re.match(r"^\s*(\S{1,8})\s+(\d{1,3}(?:\.\d+)?)\s*%?\s*$", item)
        if match is None:
            raise Refusal("the levels scale in Marking Settings.md could not be read: write it as "
                          "- Levels scale: 4+ 95, 4 90, 4- 85 (each level, a space, its percent, commas between)")
        if match.group(1) in seen:
            raise Refusal("the levels scale in Marking Settings.md names a level twice")
        seen.add(match.group(1))
        entries.append((match.group(1), float(match.group(2))))
    entries.sort(key=lambda entry: -entry[1])
    return entries


def level_for(scale, value):
    """The level a percentage reaches on the teacher's scale, by LEVEL_FROM_PERCENT."""
    if scale is None or value is None:
        return ""
    if LEVEL_FROM_PERCENT == "nearest":
        best = scale[0]
        for entry in scale:
            if abs(entry[1] - value) < abs(best[1] - value):
                best = entry
        return best[0]
    for level, at_least in scale:
        if value + 1e-9 >= at_least:
            return level
    return "below " + scale[-1][0]


def percent_for(scale, level):
    for entry_level, value in scale:
        if entry_level == level:
            return value
    return None


# ---------------------------------------------------------------- reading one assessment


def read_json(path, what):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        raise Refusal(f"{what} could not be read as JSON")


def identifier_files(folder, counter):
    """[(section, identifier, path)] under folder/Section N/ in order (Student Z before Student AA), counting
    anything else in counter['left alone']."""
    found = []
    for section_folder in sorted(folder.iterdir(), key=lambda found: (len(found.name), found.name)):
        match = re.match(SECTION, section_folder.name)
        if not section_folder.is_dir() or match is None:
            counter["left alone"] += 1
            continue
        for path in sorted(section_folder.iterdir(), key=lambda found: (len(found.stem), found.name)):
            if path.suffix == ".json" and path.is_file() and re.match(IDENTIFIER, path.stem):
                found.append((int(match.group(1)), path.stem, path))
            else:
                counter["left alone"] += 1
    return found


def check_record(checker, kit_path, record_path, label):
    result = subprocess.run([sys.executable, "-B", str(checker), str(kit_path), "--marks", str(record_path)],
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        rules = sorted(set(re.findall(r"\[([a-z-]+)\]", result.stdout)))
        raise Refusal(f"{label}: its marks record does not pass check_kit.py ({', '.join(rules)}); run it yourself "
                      "to see each line; nothing was written")


def category_marks(kit, record):
    """[(category key, earned, out of)] in the kit's order, counted as build_test_sheet.py counts them: a point
    the teacher removed from the count (voided) is left out of "out of", and a mark earned on it still counts."""
    voided = record.get("voided", {}) or {}
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


def total_marks(kit, record):
    """(earned, out of) over every point, counted on its own, to be checked against the categories' sum."""
    voided = record.get("voided", {}) or {}
    earned = 0.0
    out_of = 0
    for point in kit["points"]:
        earned += record["points"][point["id"]]["earned"]
        if point["id"] not in voided:
            out_of += 1
    return earned, out_of


def sheet_marks(path):
    """{category key: (earned, out of)} from the marks line of a Marks by Question .tex, or None if unreadable."""
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
        if item is None:
            return None
        found[item.group(1).replace("\\", "")] = (float(item.group(2)), int(item.group(3)))
    return found


def read_marks(entry, checker, half_marks, counter, problems, notes):
    """[(section, identifier, [(key, earned, out of)], (earned, out of))] for the marks records of one assessment."""
    kit = entry["kit"]
    students = []
    for section, identifier, path in identifier_files(entry["folder"] / "Marks", counter):
        label = f"Section {section}/{identifier}"
        check_record(checker, entry["kit_path"], path, label)
        record = read_json(path, f"{label}'s marks record")
        if record.get("identifier") != identifier or str(record.get("section")) != str(section):
            raise Refusal(f"{label}: the identifier or section inside its marks record is not its file's and folder's; "
                          "nothing was written")
        unmarked = []
        for point in kit["points"]:
            earned = record["points"][point["id"]]["earned"]
            if earned is None:
                unmarked.append(point["id"])
            elif earned == 0.5 and not half_marks:
                raise Refusal(f"{label}: {point['id']} has a half mark, and your marking settings do not record a yes "
                              "to half marks; nothing was written")
        if unmarked:
            notes.append(f"{label}: not fully marked ({', '.join(unmarked)}), so it was left out")
            counter["left out"] += 1
            continue
        categories = category_marks(kit, record)
        total = total_marks(kit, record)
        summed = 0.0
        summed_out_of = 0
        for _key, earned, out_of in categories:
            summed += earned
            summed_out_of += out_of
        if abs(summed - total[0]) > 1e-9 or summed_out_of != total[1]:
            raise Refusal(f"{label}: its categories add up to {number(summed)}/{summed_out_of}, and its points to "
                          f"{number(total[0])}/{total[1]}; nothing was written")
        sheet = entry["folder"] / "Sheets" / f"Section {section}" / (identifier + SHEET_SUFFIX)
        if sheet.is_file():
            on_sheet = sheet_marks(sheet)
            if on_sheet is None:
                counter["unreadable sheets"].append(label)
            else:
                said = []
                now = []
                for key, earned, out_of in categories:
                    printed = on_sheet.get(key)
                    if printed is None or abs(printed[0] - earned) > 1e-9 or printed[1] != out_of:
                        said.append(f"{key} " + (f"{number(printed[0])}/{printed[1]}" if printed else "nothing"))
                        now.append(f"{key} {number(earned)}/{out_of}")
                if said:
                    problems.append(f"{label}: its sheet says {', '.join(said)}, and its marks record now gives "
                                    f"{', '.join(now)}")
                else:
                    counter["sheets agree"] += 1
        else:
            counter["no sheet"] += 1
        students.append((section, identifier, categories, total))
    return students


LEVEL_TEXT = re.compile(r"^[^\s\\{}$&%#_^~]{1,8}$")
CATEGORY_KEY = re.compile(r"^[A-Za-z][A-Za-z0-9]{0,11}$")


def read_levels(entry, scale, counter, problems):
    """([(section, identifier, {key: (first, revised)})], [category keys in order]) for one assessment's Records."""
    students = []
    keys = []
    for section, identifier, path in identifier_files(entry["folder"] / "Records", counter):
        label = f"Section {section}/{identifier}"
        record = read_json(path, f"{label}'s level record")
        shape = f"{label}: its level record is not in the shape reference/results.md gives; nothing was written"
        if not isinstance(record, dict) or record.get("identifier") != identifier:
            raise Refusal(shape)
        if "section" in record and str(record.get("section")) != str(section):
            raise Refusal(shape)
        levels = record.get("levels")
        if not isinstance(levels, dict) or not levels:
            raise Refusal(shape)
        found = {}
        for key, pair in levels.items():
            if not CATEGORY_KEY.match(str(key)) or not isinstance(pair, dict):
                raise Refusal(shape)
            first = pair.get("first")
            revised = pair.get("revised")
            for value in (first, revised):
                if value is not None and (not isinstance(value, str) or not LEVEL_TEXT.match(value)):
                    raise Refusal(shape)
            if first is None:
                raise Refusal(shape)
            if scale is not None:
                for value in (first, revised):
                    if value is not None and percent_for(scale, value) is None:
                        problems.append(f"{label}: {key} level {value} is not on the levels scale in Marking Settings.md")
            if key not in keys:
                keys.append(key)
            found[key] = (first, revised)
        students.append((section, identifier, found))
    return students, keys


# ---------------------------------------------------------------- LaTeX


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


def marks_cell(earned, out_of, scale):
    value = percent(earned, out_of)
    cell = f"{number(earned)}/{out_of}"
    if value is not None:
        cell += f" ({value}\\%)"
    level = level_for(scale, None if value is None else float(earned * 100.0 / out_of))
    if level:
        cell += " " + esc(level)
    return cell


def marks_part(name, kit, students, scale, notes_for_part):
    tex = heading(name + ": marks by category")
    titles = []
    for category in kit["categories"]:
        titles.append(esc(category["key"]) + " " + esc(category["title"]))
    tex += "{\\small " + "; ".join(titles) + ".}\\par\\vspace{4pt}\n"
    sections = sorted(set(section for section, _identifier, _categories, _total in students))
    for section in sections:
        tex += heading(f"Section {section}", "normalsize")
        header = ["\\textbf{Student}"]
        for category in kit["categories"]:
            header.append("\\textbf{" + esc(category["key"]) + "}")
        header.append("\\textbf{Total}")
        tex += table_start(len(kit["categories"]) + 1, header)
        sums = [0.0] * (len(kit["categories"]) + 1)
        counted = 0
        for row_section, identifier, categories, total in students:
            if row_section != section:
                continue
            counted += 1
            cells = [student(section, identifier)]
            for index, (_key, earned, out_of) in enumerate(categories):
                cells.append(marks_cell(earned, out_of, scale))
                sums[index] += 0.0 if out_of == 0 else earned * 100.0 / out_of
            cells.append("\\textbf{" + marks_cell(total[0], total[1], scale) + "}")
            sums[-1] += 0.0 if total[1] == 0 else total[0] * 100.0 / total[1]
            tex += " & ".join(cells) + "\\\\\n\\hline\n"
        means = ["\\textit{Section mean}"]
        for value in sums:
            means.append(f"{int(value / counted + 0.5 + 1e-9)}\\%")
        tex += "\\rowcolor{gray!8}" + " & ".join(means) + "\\\\\n\\hline\n\\end{longtable}}\n"
    for line in notes_for_part:
        tex += "{\\small " + esc(line) + "}\\par\n"
    return tex


def levels_part(name, students, keys, scale):
    tex = heading(name + ": levels, first and revised")
    sections = sorted(set(section for section, _identifier, _levels in students))
    no_revision = []
    for section in sections:
        tex += heading(f"Section {section}", "normalsize")
        header = ["\\textbf{Student}"]
        for key in keys:
            header.append("\\textbf{" + esc(key) + "}")
        tex += table_start(len(keys), header)
        for row_section, identifier, levels in students:
            if row_section != section:
                continue
            cells = [student(section, identifier)]
            revised_any = False
            for key in keys:
                if key not in levels:
                    cells.append("")
                    continue
                first, revised = levels[key]
                cell = esc(first) + " $\\rightarrow$ " + (esc(revised) if revised is not None else "none")
                if revised is not None:
                    revised_any = True
                current = revised if revised is not None else first
                if scale is not None:
                    cell += f" ({number(percent_for(scale, current))}\\%)"
                cells.append(cell)
            if not revised_any:
                no_revision.append((section, identifier))
            tex += " & ".join(cells) + "\\\\\n\\hline\n"
        tex += "\\end{longtable}}\n"
    tex += heading(NO_REVISION_TITLE, "normalsize")
    if no_revision:
        listed = []
        for section, identifier in no_revision:
            listed.append(student(section, identifier) + f" (Section {section})")
        tex += "Students whose level record has no revised level: " + ", ".join(listed) + ".\\par\n"
    else:
        tex += "Every student with a level record has at least one revised level.\\par\n"
    return tex, no_revision


def built_from(entries, stamp, fingerprint, scale, assessments_text):
    tex = heading("What this was built from")
    tex += (f"Built on {esc(stamp)} from these records (fingerprint {fingerprint}): " + esc(assessments_text) + " "
            "After any change to a mark or a level, run class\\_results.py again: this document does not change by "
            "itself.\\par\n")
    for entry in entries:
        if entry["missing"]:
            tex += "{\\small " + esc(entry["missing"]) + "}\\par\n"
    tex += ("{\\small Each category's mark is the sum of its points earned, out of the points counted; a point "
            "the teacher removed from the count is not in the out of, and a mark earned on it still counts, as on "
            "the feedback sheet. The total is the sum of every point. Percentages are rounded to the nearest whole "
            "number. ")
    if scale is None:
        tex += ("Marking Settings.md gives no levels scale, so no level is worked out from a percentage and no "
                "percentage from a level.")
    else:
        rule = ("the highest level on the scale at or below its percentage" if LEVEL_FROM_PERCENT != "nearest"
                else "the level on the scale nearest its percentage")
        tex += ("Levels use the scale in Marking Settings.md (" + ", ".join(esc(level) + " " + number(value) for level, value in scale)
                + "): a mark's level is " + rule + ", and a level's percent is the scale's.")
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
        target_pdf.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(built, target_pdf)
        return len(pages), None


# ---------------------------------------------------------------- the build


def written_names(entries):
    names = [DOCUMENT + ".tex", DOCUMENT + ".pdf"]
    for entry in entries:
        names.append(GRADES.format(assessment=entry["name"]))
        names.append(LEVELS.format(assessment=entry["name"]))
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


def fingerprint_of(paths):
    digest = hashlib.sha256()
    for path in sorted(paths, key=str):
        digest.update(str(path.name).encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()[:12]


def csv_text(rows):
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    for row in rows:
        writer.writerow(row)
    return buffer.getvalue()


def grade_rows(kit, students, scale):
    header = ["section", "identifier"]
    for category in kit["categories"]:
        header.extend([f"{category['key']} marks", f"{category['key']} out of", f"{category['key']} %"])
        if scale is not None:
            header.append(f"{category['key']} level")
    header.extend(["total", "total out of", "total %"])
    if scale is not None:
        header.append("total level")
    rows = [header]
    for section, identifier, categories, total in sorted(students, key=lambda row: (row[0], len(row[1]), row[1])):
        row = [str(section), identifier]
        for _key, earned, out_of in list(categories) + [("total", total[0], total[1])]:
            value = percent(earned, out_of)
            row.extend([number(earned), str(out_of), "" if value is None else str(value)])
            if scale is not None:
                row.append(level_for(scale, None if value is None else earned * 100.0 / out_of))
        rows.append(row)
    return rows


def level_rows(students, keys, scale):
    header = ["section", "identifier"]
    for key in keys:
        header.extend([f"{key} first", f"{key} revised", f"{key} level"])
        if scale is not None:
            header.append(f"{key} %")
    rows = [header]
    for section, identifier, levels in sorted(students, key=lambda row: (row[0], len(row[1]), row[1])):
        row = [str(section), identifier]
        for key in keys:
            first, revised = levels.get(key, (None, None))
            current = revised if revised is not None else first
            row.extend([first or "", revised or "", current or ""])
            if scale is not None:
                row.append("" if current is None else number(percent_for(scale, current)))
        rows.append(row)
    return rows


def write_replacing(path, text):
    partial = path.with_name("." + path.name + ".partial")
    with open(partial, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    os.replace(partial, path)


def build(entries, checker, settings, out, title, school, tex_only):
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
    try:
        return build_in(entries, checker, settings, out, title, school, tex_only)
    except Refusal:
        if set_earlier_run_aside(out, entries):
            print("The results of an earlier run may no longer match the records, so they were renamed \"earlier run, "
                  "do not use\".")
        raise


def build_in(entries, checker, settings, out, title, school, tex_only):
    half_marks, scale = read_settings(settings)
    if not tex_only and (shutil.which("tectonic") is None or shutil.which("pdftotext") is None):
        raise Refusal("tectonic and Poppler's pdftotext are needed for the PDF (on a Mac with Homebrew: brew install "
                      "tectonic poppler), or give --tex-only; nothing was written")
    counter = {"left alone": 0, "left out": 0, "no sheet": 0, "sheets agree": 0, "unreadable sheets": []}
    problems = []
    notes = []
    said = []
    read_paths = []
    for entry in entries:
        entry["folder"] = Path(entry["folder"]).resolve()
        if not entry["folder"].is_dir():
            raise Refusal("an --assessment folder was not found")
        has_marks = (entry["folder"] / "Marks").is_dir()
        has_records = (entry["folder"] / "Records").is_dir()
        if not has_marks and not has_records:
            raise Refusal(f"{entry['name']}: it has no Marks folder and no Records folder, so there is nothing to build "
                          "from; nothing was written")
        entry["marks"] = []
        entry["levels"] = ([], [])
        entry["notes"] = []
        if has_marks:
            if entry["kit_path"] is None:
                raise Refusal(f"{entry['name']}: give --kit after its --assessment (the marks records are counted from "
                              "the kit's points); nothing was written")
            entry["kit"] = read_json(entry["kit_path"], f"{entry['name']}'s kit")
            before = len(notes)
            entry["marks"] = read_marks(entry, checker, half_marks, counter, problems, notes)
            entry["notes"] = notes[before:]
            read_paths.append(Path(entry["kit_path"]))
            for _section, _identifier, path in identifier_files(entry["folder"] / "Marks", {"left alone": 0}):
                read_paths.append(path)
            counts = {}
            for section, _identifier, _categories, _total in entry["marks"]:
                counts[section] = counts.get(section, 0) + 1
            said.append(f"{entry['name']}: " + ("; ".join(f"Section {section}: {plural(counts[section], 'marks record')} counted"
                                                          for section in sorted(counts)) or "no marks record counted"))
        if has_records:
            entry["levels"] = read_levels(entry, scale, counter, problems)
            for _section, _identifier, path in identifier_files(entry["folder"] / "Records", {"left alone": 0}):
                read_paths.append(path)
            counts = {}
            for section, _identifier, _levels in entry["levels"][0]:
                counts[section] = counts.get(section, 0) + 1
            said.append(f"{entry['name']}: " + ("; ".join(f"Section {section}: {plural(counts[section], 'level record')} counted"
                                                          for section in sorted(counts)) or "no level record counted"))
        if not has_records:
            entry["missing"] = (f"{entry['name']}: there is no Records folder, so this document has no levels, no "
                                "revision summary and no list of students with no revised levels for it.")
        elif not has_marks:
            entry["missing"] = (f"{entry['name']}: there is no Marks folder, so this document has no marks by category "
                                "for it.")
        else:
            entry["missing"] = ""
        if entry["missing"]:
            said.append(entry["missing"].replace("this document has", "the documents have"))
    if problems:
        for problem in problems:
            print(problem)
        stale = 0
        for problem in problems:
            if "its sheet says" in problem:
                stale += 1
        if stale:
            raise Refusal(f"{plural(stale, 'sheet')} no longer {'gives' if stale == 1 else 'give'} the totals the points "
                          "give: build those sheets again "
                          "with build_test_sheet.py, then run this again; nothing was written")
        raise Refusal(f"{plural(len(problems), 'problem')} in the records; nothing was written")
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    fingerprint = fingerprint_of(read_paths)
    total_records = 0
    pieces = []
    for entry in entries:
        marks_count = len(entry["marks"])
        levels_count = len(entry["levels"][0])
        total_records += marks_count + levels_count
        if marks_count:
            pieces.append(f"{entry['name']}, {plural(marks_count, 'marks record')}")
        if levels_count:
            pieces.append(f"{entry['name']}, {plural(levels_count, 'level record')}")
    assessments_text = "; ".join(pieces) + "." if pieces else "no record."
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
            + esc(stamp) + "}\\par\\vspace{4pt}\n")
    tex += "{\\small\\itshape " + esc(TEACHER_DECIDES) + "}\\par\\vspace{6pt}\n"
    tex += built_from(entries, stamp, fingerprint, scale, assessments_text)
    headings = ["What this was built from", NO_REVISION_TITLE]
    no_revision_said = []
    for entry in entries:
        if entry["marks"]:
            tex += marks_part(entry["name"], entry["kit"], entry["marks"], scale, entry["notes"])
            headings.append(entry["name"] + ": marks by category")
        if entry["levels"][0]:
            part, no_revision = levels_part(entry["name"], entry["levels"][0], entry["levels"][1], scale)
            tex += part
            headings.append(entry["name"] + ": levels, first and revised")
            if no_revision:
                labels = []
                for section, identifier in no_revision:
                    labels.append(f"Section {section}/{identifier}")
                no_revision_said.append(f"{entry['name']}: {plural(len(no_revision), 'student')} with no revised levels: "
                                        + ", ".join(labels))
    for section in range(1, 100):
        headings.append(f"Section {section}")
    tex += "\\end{document}\n"
    pages = None
    if not tex_only:
        pages, why = compile_and_check(tex, out / ".results.pdf.partial", headings)
        if pages is None:
            partial = out / ".results.pdf.partial"
            if partial.exists():
                os.remove(partial)
            raise Refusal(why + "; nothing was written")
    out.mkdir(parents=True, exist_ok=True)
    written = []
    write_replacing(out / (DOCUMENT + ".tex"), tex)
    written.append(DOCUMENT + ".tex")
    if pages is not None:
        os.replace(out / ".results.pdf.partial", out / (DOCUMENT + ".pdf"))
        written.append(f"{DOCUMENT}.pdf ({plural(pages, 'page')}; no heading was left alone at the foot of a page)")
    elif (out / (DOCUMENT + ".pdf")).is_file():
        os.replace(out / (DOCUMENT + ".pdf"), out / (DOCUMENT + EARLIER + ".pdf"))
    for entry in entries:
        grades = out / GRADES.format(assessment=entry["name"])
        levels = out / LEVELS.format(assessment=entry["name"])
        if entry["marks"]:
            write_replacing(grades, csv_text(grade_rows(entry["kit"], entry["marks"], scale)))
            written.append(grades.name)
        elif grades.is_file():
            os.replace(grades, out / (grades.stem + EARLIER + grades.suffix))
        if entry["levels"][0]:
            write_replacing(levels, csv_text(level_rows(entry["levels"][0], entry["levels"][1], scale)))
            written.append(levels.name)
        elif levels.is_file():
            os.replace(levels, out / (levels.stem + EARLIER + levels.suffix))
    for line in said:
        print(line)
    for line in notes:
        print(line)
    for line in no_revision_said:
        print(line)
    if counter["sheets agree"]:
        print(f"The totals on {plural(counter['sheets agree'], 'sheet')} were compared with the marks records, and agree.")
    if counter["no sheet"]:
        print(f"{plural(counter['no sheet'], 'marks record')} with no Marks by Question sheet yet, so not compared.")
    if counter["unreadable sheets"]:
        print(f"{plural(len(counter['unreadable sheets']), 'sheet')} whose marks line could not be read, so not compared: "
              + ", ".join(counter["unreadable sheets"]))
    if counter["left alone"]:
        print(f"{plural(counter['left alone'], 'file')} not named like an identifier "
              + ("was" if counter["left alone"] == 1 else "were") + " left alone")
    for name in written:
        print(f"Wrote {name}")
    print(f"Built {stamp} from {plural(total_records, 'record')} (fingerprint {fingerprint}). These hold identifiers "
          "only. After any change to a mark or a level, run this again: they do not change by themselves.")
    return 1 if counter["left out"] or counter["unreadable sheets"] else 0


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

    def record(identifier, earned):
        points = {}
        for point_id, value in zip(("A1", "B1.1", "B1.2"), earned):
            points[point_id] = {"earned": value, "seen": "", "note": "", "studentNote": "" if value == 1 else "A reason."}
        return {"kit": 1, "identifier": identifier, "section": 1, "version": "A", "points": points, "voided": {},
                "checks": [], "summary": "", "byQuestion": [], "strengths": [], "focus": [], "closing": "", "feedback": {}}

    problems = []
    with tempfile.TemporaryDirectory() as root:
        marking = Path(root) / "Marking"
        assessment = marking / "Unit 1 Test"
        (assessment / "Marks" / "Section 1").mkdir(parents=True)
        (assessment / "Sheets" / "Section 1").mkdir(parents=True)
        kit_path = Path(root) / "answers.json"
        kit_path.write_text(json.dumps(kit), encoding="utf-8")
        (assessment / "Marks" / "Section 1" / "Student A.json").write_text(json.dumps(record("Student A", [1, 0, 1])), encoding="utf-8")
        (assessment / "Marks" / "Section 1" / "Student B.json").write_text(json.dumps(record("Student B", [1, 1, 1])), encoding="utf-8")
        settings = marking / "Marking Settings.md"
        settings.write_text("- Half marks: no\n- Levels scale: 4 80, 3 70, 2 60, 1 50\n", encoding="utf-8")
        sheet = assessment / "Sheets" / "Section 1" / ("Student A" + SHEET_SUFFIX)
        sheet.write_text("{\\large\\bfseries\\sffamily K 1/1 $\\cdot$ T 2/2}\\par\\vspace{2pt}\n", encoding="utf-8")

        def run(extra):
            return subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--assessment", str(assessment),
                                   "--kit", str(kit_path), "--checker", str(checker), "--settings", str(settings)] + extra,
                                  capture_output=True, text=True, encoding="utf-8")

        stale = run(["--tex-only"])
        if stale.returncode != 1 or "Section 1/Student A: its sheet says T 2/2, and its marks record now gives T 1/2" not in stale.stdout:
            problems.append("a sheet whose totals differ from the points did not stop the build")
        if (assessment / "Results" / (DOCUMENT + ".tex")).exists():
            problems.append("a stopped build wrote a document")
        sheet.write_text("{\\large\\bfseries\\sffamily K 1/1 $\\cdot$ T 1/2}\\par\\vspace{2pt}\n", encoding="utf-8")
        (assessment / "Records" / "Section 1").mkdir(parents=True)
        (assessment / "Records" / "Section 1" / "Student A.json").write_text(json.dumps(
            {"identifier": "Student A", "section": 1, "levels": {"K": {"first": "2", "revised": "3"}}}), encoding="utf-8")
        (assessment / "Records" / "Section 1" / "Student B.json").write_text(json.dumps(
            {"identifier": "Student B", "section": 1, "levels": {"K": {"first": "3", "revised": None}}}), encoding="utf-8")
        good = run(["--tex-only"])
        if good.returncode != 0:
            problems.append("the invented records were not built")
        try:
            with open(assessment / "Results" / GRADES.format(assessment="Unit 1 Test"), newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
        except OSError:
            rows = []
        if len(rows) != 2 or rows[0].get("T marks") != "1" or rows[0].get("total %") != "67" or rows[0].get("total level") != "2":
            problems.append("the grade table's totals are not the sum of the points")
        if "Unit 1 Test: 1 student with no revised levels: Section 1/Student B" not in good.stdout:
            problems.append("a student with no revised level was not listed")
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
    print("self-test passed: invented records counted point by point, a sheet whose totals differ stopped the build and "
          "wrote nothing, levels read through an invented scale, a student with no revised level listed. This checks "
          "the paths the test knows; it is no guarantee about changes it does not reach.")
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
                 option(arguments, "--title"), option(arguments, "--school", ""), "--tex-only" in arguments)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); nothing was written")
        sys.exit(1)
