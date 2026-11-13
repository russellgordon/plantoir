#!/usr/bin/env python3
"""Build a test feedback sheet (for the student) and a marks-by-question sheet (for the teacher) from one
marks record and the test's marking kit. Identifiers only: no sheet this writes holds a name.

Part of the plantoir-marking skill. A STARTING POINT: copy it into the marking folder's Scripts/ folder,
adjust it to this teacher (see the two MARK blocks below), run --self-test, and only then use it.

    python3 -B build_test_sheet.py --kit "<test>/Marking Kit/answers.json" --marks "Marks/Section 1/Student A.json"
        --out "Sheets/Section 1" --checker "<working folder>/.claude/skills/plantoir-test-authoring/scripts/check_kit.py"
        [--settings "Marking Settings.md"] [--school "School Name"] [--site https://...] [--links checked-links.json]
    python3 -B build_test_sheet.py --self-test --checker ".../check_kit.py"

Writes "<identifier> - Feedback.tex/.pdf" and "<identifier> - Marks by Question.tex/.pdf" into --out. The
student line of each is \\studentline{<identifier>}: the one place make_named_copies.py fills a name in,
on the teacher's word, at the end. The kit and the marks record are first checked with the
plantoir-test-authoring skill's check_kit.py (--checker), which this never copies or changes.

The default sheet, for every teacher (the order has a reason: students read marks first and stop):
title, student line, summary, strengths, issues by question (where marks were lost, and why), areas to
focus on, overall comments, then the marks, by question and by category, last. Every lost mark carries
a plain-words reason (the point's studentNote), or the sheet is not built. A half mark is refused
unless the settings file records the teacher's yes to half marks ("- Half marks: yes").

Links: a focus item's topics become links only to pages listed in --links (a JSON list of the page
paths that answered when the assistant fetched them on the section's site, --site). A link that did
not answer is left off.

Needs tectonic and Poppler's pdftotext. Python standard library only.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# MARK: - What you may change for this teacher
#   the sheet's wording (the headings, the leads, the closing words), the school name and corners, the
#   fonts and colours, the paper size, which sections the sheet has and their order (the teacher
#   decides; marks last is the default because students read marks first and stop), how strengths
#   are chosen, how many focus items, the levels scale if the teacher marks in levels.
ISSUES_TITLE = "Issues by question"
ISSUES_LEAD = "Where marks were lost, and why. Full marks given with the benefit of the doubt are listed too."
STRENGTHS_TITLE = "Strengths"
STRENGTHS_LEAD = "You showed a good understanding of:"
FOCUS_TITLE = "Areas to focus on"
FOCUS_NONE = "Nothing to focus on from this test: keep going."
CLOSING_TITLE = "Overall comments"
MARKS_TITLE = "Your marks"
NOTHING_LOST = "Nothing lost: full marks on every question."
PAPER = "letterpaper"
MAX_FOCUS = 4
IDENTIFIER = r"^Student [A-Z]{1,2}$"

# MARK: - What must not change
#   never print, log or write outside the teacher-only folder any value read from a name mapping table
#   (this script reads none); never print a file name that is not an identifier; capture every
#   program's output and print only counts and identifiers; refuse (exit 1, identifier-only message)
#   when anything is unexpected; every lost mark carries a plain-words reason; the student line is
#   \studentline{identifier} and nothing else; a sheet that does not compile is never left half-built;
#   never write inside a Plantoir working folder; and the teacher-decides sentence below, word for word.
TEACHER_DECIDES = ("Every mark, level and comment here is a suggestion drafted for you. Grading is your "
                   "professional responsibility: please read and decide on each one before anything reaches "
                   "a student. I draft; you decide.")


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding identifiers only."""


# ---------------------------------------------------------------- reading the kit and the record


def read_json(path, what):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise Refusal(f"{what} could not be read as JSON")


def check_with_kit_checker(checker, kit_path, marks_path):
    if checker is None or not Path(checker).is_file():
        raise Refusal("the kit checker was not found: give --checker with the path to the "
                      "plantoir-test-authoring skill's scripts/check_kit.py")
    result = subprocess.run([sys.executable, "-B", str(checker), str(kit_path), "--marks", str(marks_path)],
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        rules = re.findall(r"\[([a-z-]+)\]", result.stdout)
        raise Refusal("the kit or the marks record does not pass check_kit.py (" + ", ".join(sorted(set(rules))) + "); "
                      "run it yourself to see each line")


def half_marks_allowed(settings_path):
    if settings_path is None or not Path(settings_path).is_file():
        return False
    for line in Path(settings_path).read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*[-*]\s*Half marks:\s*(\w+)", line, re.IGNORECASE)
        if match:
            return match.group(1).casefold() == "yes"
    return False


class Sheet:
    """Everything the two sheets say, worked out from the kit and one marks record."""

    def __init__(self, kit, marks, half_marks, site, checked_links):
        self.kit = kit
        self.marks = marks
        identifier = marks.get("identifier") or ""
        if not re.match(IDENTIFIER, identifier):
            raise Refusal("the marks record's identifier is not like Student A")
        self.identifier = identifier
        self.points = marks["points"]
        self.voided = marks.get("voided", {})
        self.categories = kit["categories"]
        self.parts = kit["parts"]
        self.questions = kit["questions"]
        self.kit_points = kit["points"]
        for point in self.kit_points:
            earned = self.points[point["id"]]["earned"]
            if earned is None:
                raise Refusal(f"{identifier}: {point['id']} is not marked yet")
            if earned == 0.5 and not half_marks:
                raise Refusal(f"{identifier}: {point['id']} has a half mark, and your marking settings do not "
                              "record a yes to half marks")
            if earned < 1 and point["id"] not in self.voided and not self.points[point["id"]].get("studentNote", "").strip():
                raise Refusal(f"{identifier}: {point['id']} lost a mark and has no studentNote (one sentence to "
                              "the student saying why)")
        if not str(marks.get("closing", "")).strip():
            raise Refusal(f"{identifier}: the marks record needs a closing paragraph for {CLOSING_TITLE}")
        if len(marks.get("focus", [])) > MAX_FOCUS:
            raise Refusal(f"{identifier}: more than {MAX_FOCUS} focus items")
        self.site = (site or "").rstrip("/")
        self.checked_links = set(checked_links)
        for item in marks.get("focus", []):
            for topic in item.get("topics", []):
                if topic not in kit.get("topics", {}):
                    raise Refusal(f"{identifier}: a focus item names a topic the kit does not have")

    def counted(self, point_id):
        return point_id not in self.voided

    def category_marks(self):
        """[(category, earned, out of)] in the kit's order."""
        result = []
        for category in self.categories:
            earned = 0.0
            out_of = 0
            for point in self.kit_points:
                if point["category"] == category["key"]:
                    earned += self.points[point["id"]]["earned"]
                    if self.counted(point["id"]):
                        out_of += 1
            result.append((category, earned, out_of))
        return result

    def question_result(self, question_id):
        earned = 0.0
        out_of = 0
        for point in self.kit_points:
            if point["question"] == question_id:
                earned += self.points[point["id"]]["earned"]
                if self.counted(point["id"]):
                    out_of += 1
        return earned, out_of

    def question_notes(self, question_id):
        """The marker's notes for a question (byQuestion), else the studentNotes of its lost points."""
        for row in self.marks.get("byQuestion", []):
            if row.get("q") == question_id and str(row.get("notes", "")).strip():
                return str(row["notes"]).strip()
        notes = []
        for point in self.kit_points:
            if point["question"] == question_id:
                note = self.points[point["id"]].get("studentNote", "").strip()
                if note and (self.points[point["id"]]["earned"] < 1 or not self.counted(point["id"])):
                    notes.append(note)
        for point_id, voided in self.voided.items():
            for point in self.kit_points:
                if point["id"] == point_id and point["question"] == question_id:
                    notes.append("One mark in this question is not counted for anyone: " + str(voided.get("reason", "")).strip())
        return " ".join(notes)

    def benefit_of_the_doubt(self, question_id):
        for row in self.marks.get("byQuestion", []):
            if row.get("q") == question_id and row.get("benefitOfTheDoubt"):
                return True
        return False

    def issue_rows(self):
        """[(part, question, skill, result, notes)] for questions with a mark lost or a benefit of the doubt."""
        rows = []
        for part in self.parts:
            for question in self.questions:
                if question["part"] != part["key"]:
                    continue
                earned, out_of = self.question_result(question["id"])
                lost = earned < out_of
                voided_here = False
                for point in self.kit_points:
                    if point["question"] == question["id"] and not self.counted(point["id"]):
                        voided_here = True
                if lost or voided_here or self.benefit_of_the_doubt(question["id"]):
                    rows.append((part, question["id"], question["skill"], f"{number(earned)} of {out_of}",
                                 self.question_notes(question["id"])))
        return rows

    def strengths(self):
        lines = []
        for strength in self.kit.get("strengths", []):
            secure = []
            for half in strength["halves"]:
                all_earned = True
                for point_id in half["points"]:
                    if self.counted(point_id) and self.points[point_id]["earned"] < 1:
                        all_earned = False
                secure.append(all_earned)
            if secure and all(secure):
                lines.append(strength["sentence"])
            else:
                for half, flag in zip(strength["halves"], secure):
                    if flag and half.get("sentence"):
                        lines.append(half["sentence"])
        return lines

    def links_for(self, item):
        links = []
        for topic in item.get("topics", []):
            for page in self.kit["topics"][topic]["pages"]:
                if not self.site or page["path"] not in self.checked_links:
                    continue
                address = self.site + "/" + page["path"] + ("#" + page["anchor"] if page.get("anchor") else "")
                titles = [title for title, _address in links]
                if page["title"] not in titles:
                    links.append((page["title"], address))
                break
        return links


def number(value):
    return str(int(value)) if float(value).is_integer() else str(value)


# ---------------------------------------------------------------- LaTeX


def esc(text):
    """Plain text for LaTeX: every special character, the symbols a marker types, and break points in code."""
    text = str(text).replace("\\", "\x00")
    for character in "&%$#_{}":
        text = text.replace(character, "\\" + character)
    text = text.replace("\x00", "\\textbackslash{}")
    text = text.replace("--", "-{}-")
    text = text.replace("~", "\\textasciitilde{}").replace("^", "\\textasciicircum{}")
    text = text.replace("<", "\\textless{}").replace(">", "\\textgreater{}")
    for symbol, command in (("≥", "$\\geq$"), ("≤", "$\\leq$"), ("≠", "$\\neq$"), ("←", "$\\leftarrow$"),
                            ("→", "$\\rightarrow$"), ("–", "--"), ("—", "---"), ("÷", "$\\div$"), ("×", "$\\times$")):
        text = text.replace(symbol, command)
    for token in (")", "\\{", "\\}", ",", ";"):
        text = text.replace(token, token + "\\allowbreak{}")
    text = re.sub(r"\\allowbreak\{\}(?=\}*(?:[,.;:)\]'\"’”]|\\\}))", "", text)
    return text


def inline(text):
    """Plain text with `code`, **bold** and *a term* to LaTeX: code in monospace, a term in italic, and
    "what the student wrote" in curly double quotes."""
    text = re.sub(r'"([^"`]+)"', lambda found: "\x01" + found.group(1) + "\x02", str(text))
    return inline_spans(text).replace("\x01", "``").replace("\x02", "''")


def inline_spans(text):
    out = ""
    position = 0
    for match in re.finditer(r"`([^`]+)`|\*\*([^*]+)\*\*|\*([^*\s][^*]*)\*", str(text)):
        out += esc(re.sub(r"(^|[\s(\[])'(?=\w)", lambda found: found.group(1) + "`", str(text)[position:match.start()]))
        if match.group(1) is not None:
            out += "\\texttt{\\frenchspacing " + esc(match.group(1)) + "}"
        elif match.group(2) is not None:
            out += "\\textbf{" + esc(match.group(2)) + "}"
        else:
            out += "\\textit{" + esc(match.group(3)) + "}"
        position = match.end()
    return out + esc(re.sub(r"(^|[\s(\[])'(?=\w)", lambda found: found.group(1) + "`", str(text)[position:]))


def preamble(title, course, school):
    return r"""\documentclass[11pt]{article}
\usepackage[""" + PAPER + r""",margin=0.75in,bottom=0.9in]{geometry}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage[table]{xcolor}
\usepackage{fancyvrb}
\usepackage{array,longtable}
\usepackage{fancyhdr,lastpage}
\usepackage{enumitem}
\usepackage{needspace}
\usepackage[hidelinks]{hyperref}
\setlength{\parindent}{0pt}
\setlength{\LTleft}{0pt}\setlength{\LTright}{\fill}\setlength{\LTpre}{0pt}\setlength{\LTpost}{0pt}
\setlength{\parskip}{4pt}
\setlength{\emergencystretch}{1.5em}
\definecolor{subtitle}{gray}{0.45}
\definecolor{good}{RGB}{0,128,0}
\definecolor{gap}{RGB}{200,95,0}
\definecolor{link}{RGB}{0,90,200}
% The student line: the ONE place a name is filled in, by make_named_copies.py, on the teacher's word.
\newcommand{\studentline}[1]{{\color{subtitle}\sffamily #1 $\cdot$ """ + esc(course) + r"""}\par\vspace{6pt}}
\pagestyle{fancy}
\fancyhf{}
\renewcommand{\headrulewidth}{0pt}
\lhead{\small\sffamily\color{gray}""" + esc(school) + r"""}
\lfoot{\small\sffamily\color{gray}""" + esc(title) + r"""\ $\cdot$ """ + esc(course) + r"""}
\rfoot{\small\sffamily\color{gray}Page \thepage\ of \pageref{LastPage}}
\begin{document}
"""


def verbatim(code):
    for symbol, plain in (("←", "<-"), ("→", "->"), ("≥", ">="), ("≤", "<="), ("≠", "!="), ("÷", "/"), ("×", "*")):
        code = code.replace(symbol, plain)
    return "\\begin{Verbatim}[fontsize=\\small,xleftmargin=0pt]\n" + code.rstrip("\n") + "\n\\end{Verbatim}\n"


COLUMNS = ("{p{0.9cm}>{\\raggedright\\arraybackslash}p{4.3cm}p{1.6cm}"
           ">{\\raggedright\\arraybackslash}p{\\dimexpr\\textwidth-6.8cm-8\\tabcolsep}}")
HEAD = ("\\hline\n\\rowcolor{gray!30}\\multicolumn{4}{|l|}{\\rule{0pt}{2.6ex}"
        "\\makebox[\\dimexpr0.9cm+2\\tabcolsep][l]{\\textbf{Q}}"
        "\\makebox[\\dimexpr4.3cm+2\\tabcolsep][l]{\\textbf{Skill}}"
        "\\makebox[\\dimexpr1.6cm+2\\tabcolsep][l]{\\textbf{Result}}"
        "\\textbf{Notes}\\rule[-1ex]{0pt}{0pt}}\\\\\n\\hline\n")


def part_row(part, continued=False):
    label = esc(part["title"]) + ("~{\\small (continued)}" if continued else "")
    return "\\rowcolor{gray!15}\\multicolumn{4}{|l|}{\\sffamily\\bfseries\\rule{0pt}{2.4ex}" + label + "\\rule[-1ex]{0pt}{0pt}}\\\\*\n"


def feedback_tex(sheet, school):
    kit = sheet.kit
    title = kit["test"] + ": Feedback"
    tex = preamble(kit["test"] + ": Feedback", kit["course"], school)
    tex += "{\\LARGE\\bfseries\\sffamily " + esc(title) + "}\\par\\vspace{2pt}\n"
    tex += "\\studentline{" + esc(sheet.identifier) + "}\n"
    tex += inline(sheet.marks.get("summary", "")) + "\\par\\vspace{6pt}\n"
    strengths = sheet.strengths()
    if strengths:
        tex += ("\\needspace{5\\baselineskip}{\\large\\bfseries\\sffamily " + esc(STRENGTHS_TITLE) + "}\\par\\nobreak\\vspace{1pt}\n"
                + esc(STRENGTHS_LEAD) + "\\par\\nobreak\\vspace{-4pt}\n\\begin{itemize}[nosep,leftmargin=1.4em]\n")
        for line in strengths:
            tex += "\\item " + inline(line) + "\n"
        tex += "\\end{itemize}\\vspace{6pt}\n"
    rows = sheet.issue_rows()
    title_rows = ("\\multicolumn{4}{@{}l}{\\large\\bfseries\\sffamily " + esc(ISSUES_TITLE) + "}\\\\*[1pt]\n"
                  "\\multicolumn{4}{@{}l}{\\small\\sffamily\\color{subtitle}" + esc(ISSUES_LEAD) + "}\\\\*[3pt]\n")
    groups = []
    for part, question, skill, result, notes in rows:
        if not groups or groups[-1][0]["key"] != part["key"]:
            groups.append((part, []))
        groups[-1][1].append((question, skill, result, notes))
    table_columns = "{|" + COLUMNS[1:-1] + "|}"
    if not groups:
        tex += ("\\begin{longtable}" + table_columns + "\n" + title_rows + HEAD + "\\endfirsthead\n"
                "\\multicolumn{4}{|l|}{" + esc(NOTHING_LOST) + "}\\\\\n\\hline\n\\end{longtable}\n")
    for index, (part, part_rows) in enumerate(groups):
        if index == 0:
            first_head = title_rows + HEAD
            toggle = ""
        else:
            tex += "\\Needspace{12\\baselineskip}\n"
            first_head = "\\PartFirstHead\n"
            toggle = ("\\ifdim\\pagegoal=\\maxdimen\\gdef\\PartFirstHead{" + HEAD.replace("\n", "") +
                      "}\\else\\gdef\\PartFirstHead{\\noalign{\\vskip-\\arrayrulewidth}\\hline}\\fi\n")
        tex += (toggle + "\\begin{longtable}" + table_columns + "\n" + first_head + "\\endfirsthead\n"
                + HEAD + part_row(part, continued=True) + "\\endhead\n")
        tex += part_row(part)
        for question, skill, result, notes in part_rows:
            tex += f"\\rule{{0pt}}{{2.6ex}}{esc(question)} & {inline(skill)} & {esc(result)} & {inline(notes)}\\\\[3pt]\n"
        tex += "\\hline\n\\end{longtable}\n"
    focus = sheet.marks.get("focus", [])
    heading = "{\\large\\bfseries\\sffamily " + esc(FOCUS_TITLE) + "}\\par\\vspace{7pt}\n"
    tex += "\\vspace{8pt}\\begingroup\\setlength{\\parskip}{0pt}\n"
    if not focus:
        tex += "\\noindent\\begin{minipage}{\\linewidth}\n" + heading + esc(FOCUS_NONE) + "\\par\\end{minipage}\\par\n"
    for index, item in enumerate(focus, start=1):
        body = "\\textbf{" + inline(item.get("title", "")) + "} " + inline(item.get("body", "")) + "\\par\n"
        if item.get("code"):
            body += verbatim(item["code"])
        links = sheet.links_for(item)
        if links:
            body += ("\\vspace{4pt}{\\small\\sffamily\\color{subtitle}Read: " + " $\\cdot$ ".join(
                "\\href{" + address.replace("%", "\\%").replace("#", "\\#") + "}{\\textcolor{link}{" + esc(page_title) + "}}"
                for page_title, address in links) + "}\\par\n")
        # Each item is one unsplittable block; the heading shares the first item's block, so it is never
        # left alone at the foot of a page.
        tex += ("\\noindent\\begin{minipage}{\\linewidth}\\setlength{\\parskip}{0pt}\n" + (heading if index == 1 else "")
                + "\\makebox[2.1em][l]{\\textbf{" + str(index) + ".}}\\begin{minipage}[t]{\\dimexpr\\linewidth-2.1em\\relax}"
                "\\setlength{\\parskip}{0pt}\n" + body + "\\end{minipage}\\end{minipage}\\par\\vspace{14pt}\n")
    tex += "\\endgroup\n"
    tex += ("\\vspace{6pt}\\noindent\\begin{minipage}{\\linewidth}{\\large\\bfseries\\sffamily " + esc(CLOSING_TITLE)
            + "}\\par\\vspace{3pt}\n" + inline(sheet.marks["closing"]) + "\\par\n")
    tex += "\\vspace{10pt}{\\large\\bfseries\\sffamily " + esc(MARKS_TITLE) + "}\\par\\vspace{3pt}\n"
    tex += ("\\begin{tabular}{|>{\\raggedright\\arraybackslash}p{5.4cm}>{\\raggedright\\arraybackslash}"
            "p{\\dimexpr\\textwidth-8.6cm-6\\tabcolsep}>{\\raggedleft\\arraybackslash}p{2.8cm}|}\n\\hline\n"
            "\\rowcolor{gray!30}\\textbf{Category} & \\textbf{By question} & \\textbf{Marks earned}\\\\\n\\hline\n")
    for category, earned, out_of in sheet.category_marks():
        by_question = []
        for question in sheet.questions:
            question_points = [point for point in sheet.kit_points
                               if point["question"] == question["id"] and point["category"] == category["key"]]
            if question_points:
                question_earned, question_out_of = sheet.question_result(question["id"])
                by_question.append(f"{question['id']}: {number(question_earned)} of {question_out_of}")
        tex += (f"\\rule{{0pt}}{{2.6ex}}{esc(category['title'])} & " + " $\\cdot$ ".join(esc(part) for part in by_question)
                + f" & {number(earned)}/{out_of}\\\\[2pt]\n")
    tex += "\\hline\n\\end{tabular}\\par\\end{minipage}\n\\end{document}\n"
    return tex


def teacher_tex(sheet, school):
    kit = sheet.kit
    marks_line = " $\\cdot$ ".join(f"{esc(category['key'])} {number(earned)}/{out_of}"
                                   for category, earned, out_of in sheet.category_marks())
    tex = preamble(kit["test"] + ": Marks by question (teacher only)", kit["course"], school)
    tex += "{\\Large\\bfseries\\sffamily " + esc(kit["test"]) + ": Marks by question}\\par\\vspace{2pt}\n"
    tex += "{\\large\\bfseries\\sffamily " + marks_line + "}\\par\\vspace{2pt}\n"
    tex += "\\studentline{" + esc(sheet.identifier) + "}\n"
    tex += ("{\\small\\sffamily Section " + esc(sheet.marks.get("section", "")) + " $\\cdot$ Version "
            + esc(sheet.marks.get("version", "")) + " $\\cdot$ teacher only}\\par\\vspace{4pt}\n")
    tex += "{\\small\\itshape " + esc(TEACHER_DECIDES) + "}\\par\\vspace{6pt}\n"
    checks = sheet.marks.get("checks", [])
    if checks:
        tex += "{\\bfseries\\sffamily\\color{gap} CHECK}\\par\\vspace{-4pt}\n\\begin{itemize}[nosep,leftmargin=1.4em]\n"
        for check in checks:
            tex += "\\item " + inline(check if isinstance(check, str) else json.dumps(check)) + "\n"
        tex += "\\end{itemize}\\vspace{6pt}\n"
    else:
        tex += "{\\sffamily\\color{subtitle} No CHECK flags from the marker.}\\par\\vspace{6pt}\n"
    columns = ("{|p{1.1cm}>{\\raggedright\\arraybackslash}p{3.8cm}p{1.0cm}>{\\raggedright\\arraybackslash}p{4.2cm}"
               ">{\\raggedright\\arraybackslash}p{\\dimexpr\\textwidth-10.1cm-10\\tabcolsep}|}")
    head = ("\\hline\n\\rowcolor{gray!30}\\textbf{ID} & \\textbf{Earned by} & \\textbf{Mark} & \\textbf{Seen on the paper}"
            " & \\textbf{Note}\\\\\n\\hline\n")
    for category, earned, out_of in sheet.category_marks():
        category_points = [point for point in sheet.kit_points if point["category"] == category["key"]]
        if not category_points:
            continue
        tex += "\\Needspace{8\\baselineskip}\\vspace{4pt}\n\\begin{longtable}" + columns + "\n" + head + "\\endfirsthead\n" + head + "\\endhead\n"
        tex += (f"\\multicolumn{{5}}{{|l|}}{{\\bfseries\\sffamily {esc(category['title'])}: "
                f"{number(earned)}/{out_of}}}\\\\\n\\hline\n")
        for point in category_points:
            record = sheet.points[point["id"]]
            colour = "good" if record["earned"] >= 1 else "gap"
            note = record.get("note", "")
            if not sheet.counted(point["id"]):
                colour = "subtitle"
                note = "Not counted (the teacher's ruling): " + str(sheet.voided[point["id"]].get("reason", "")) + (" " + note if note else "")
            tex += (f"\\texttt{{{esc(point['id'])}}} & {esc(point['meaning'])} & \\textcolor{{{colour}}}{{{number(record['earned'])}}}"
                    f" & {inline(record.get('seen', ''))} & {inline(note)}\\\\\n")
        tex += "\\hline\n\\end{longtable}\n"
    tex += "\\end{document}\n"
    return tex


# ---------------------------------------------------------------- compiling and checking pages


HEADINGS = [STRENGTHS_TITLE, ISSUES_TITLE, FOCUS_TITLE, CLOSING_TITLE, MARKS_TITLE]


def compile_and_check(tex, target_pdf, identifier, part_titles):
    """Compile in a temporary folder (output captured, never printed), then look at every page's last line."""
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / "sheet.tex"
        source.write_text(tex, encoding="utf-8")
        result = subprocess.run(["tectonic", "-c", "minimal", str(source)], capture_output=True, text=True, cwd=folder)
        if result.returncode != 0:
            first = ""
            for line in result.stderr.splitlines():
                if line.startswith("error:") or line.startswith("!"):
                    first = line.strip()
                    break
            raise Refusal(f"{identifier}: the sheet did not compile ({first or 'see the .tex'})")
        built = Path(folder) / "sheet.pdf"
        pages = subprocess.run(["pdftotext", "-layout", str(built), "-"], capture_output=True, text=True).stdout.split("\f")
        pages = [page for page in pages if page.strip()]
        stranded = HEADINGS + list(part_titles) + ["Q Skill"]
        for index, page in enumerate(pages[:-1], start=1):
            lines = [line.strip() for line in page.splitlines() if line.strip()]
            lines = [line for line in lines if not re.match(r"^(Page \d+ of \d+|.*·.*)$", line)]
            if lines:
                last = re.sub(r"\s+", " ", lines[-1])
                for heading in stranded:
                    if last == heading or last.startswith(heading + " (continued)") or last.startswith(heading) and len(last) < len(heading) + 25:
                        raise Refusal(f"{identifier}: a heading is left alone at the foot of page {index} ({heading})")
        Path(target_pdf).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(built, target_pdf)
        return len(pages)


def build(kit_path, marks_path, out, checker, settings, school, site, links_path):
    if shutil.which("tectonic") is None or shutil.which("pdftotext") is None:
        raise Refusal("tectonic and Poppler's pdftotext are needed (on a Mac with Homebrew: brew install tectonic poppler)")
    for folder in [Path(out).resolve()] + list(Path(out).resolve().parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            raise Refusal("the sheets folder is inside the Plantoir working folder; marking is kept outside it")
    check_with_kit_checker(checker, kit_path, marks_path)
    kit = read_json(kit_path, "the kit")
    marks = read_json(marks_path, "the marks record")
    checked = read_json(links_path, "the checked links") if links_path else []
    sheet = Sheet(kit, marks, half_marks_allowed(settings), site, checked)
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    part_titles = [part["title"] for part in kit["parts"]]
    built = []
    for suffix, tex in (("Feedback", feedback_tex(sheet, school)), ("Marks by Question", teacher_tex(sheet, school))):
        stem = f"{sheet.identifier} - {suffix}"
        pages = compile_and_check(tex, out / (stem + ".pdf"), sheet.identifier, part_titles)
        (out / (stem + ".tex")).write_text(tex, encoding="utf-8")
        built.append(f"{suffix} {pages} page" + ("s" if pages != 1 else ""))
    totals = " ".join(f"{category['key']} {number(earned)}/{out_of}" for category, earned, out_of in sheet.category_marks())
    print(f"{sheet.identifier}: {totals}; checks {len(marks.get('checks', []))}; " + ", ".join(built))
    return 0


# ---------------------------------------------------------------- the self-test


def self_test(checker):
    """An invented kit and record, built; then the refusals the sheet must make."""
    kit = {"kit": 1, "test": "A Test About Dice", "course": "MDM4U",
           "categories": [{"key": "K", "title": "Knowledge and Understanding"}, {"key": "T", "title": "Thinking"}],
           "parts": [{"key": "A", "title": "Part A", "category": "K"}, {"key": "B", "title": "Part B", "category": "T"}],
           "questions": [{"id": "A1", "part": "A", "skill": "The chance of one roll", "topics": ["chance"]},
                         {"id": "B1", "part": "B", "skill": "The chance of two rolls", "topics": ["chance"]}],
           "points": [{"id": "A1", "question": "A1", "category": "K", "meaning": "question 1"},
                      {"id": "B1.1", "question": "B1", "category": "T", "meaning": "the outcomes counted"},
                      {"id": "B1.2", "question": "B1", "category": "T", "meaning": "the probability", "followThrough": ["B1.1"]}],
           "versions": {"A": {"source": "Version A.tex", "answers": {"A1": {"answer": "c", "accept": []},
                                                                     "B1.1": {"answer": "36", "accept": []},
                                                                     "B1.2": {"answer": "1/6", "accept": []}}}},
           "strengths": [{"sentence": "Counting outcomes", "halves": [{"points": ["A1", "B1.1"], "sentence": None}]}],
           "topics": {"chance": {"when": "Counting.", "pages": [{"title": "Probability", "path": "Concepts/Probability", "anchor": ""}]}}}
    marks = {"kit": 1, "identifier": "Student A", "section": 1, "version": "A",
             "points": {"A1": {"earned": 1, "seen": "c", "note": "", "studentNote": ""},
                        "B1.1": {"earned": 0, "seen": "12", "note": "one die counted", "studentNote": "Two dice give 6 times 6 outcomes."},
                        "B1.2": {"earned": 1, "seen": "2/12", "note": "follows through", "studentNote": ""}},
             "voided": {}, "checks": [], "summary": "A short summary.", "byQuestion": [], "strengths": [],
             "focus": [{"title": "Counting.", "body": "Count both dice.", "topics": ["chance"]}],
             "closing": "Your first answer was right.", "feedback": {}}
    problems = []
    with tempfile.TemporaryDirectory() as root:
        kit_path = Path(root) / "answers.json"
        kit_path.write_text(json.dumps(kit), encoding="utf-8")

        def attempt(record):
            marks_path = Path(root) / "Student A.json"
            marks_path.write_text(json.dumps(record), encoding="utf-8")
            return subprocess.run([sys.executable, "-B", os.path.abspath(__file__), "--kit", str(kit_path), "--marks",
                                   str(marks_path), "--out", str(Path(root) / "Sheets"), "--checker", str(checker)],
                                  capture_output=True, text=True)

        good = attempt(marks)
        if good.returncode != 0 or not (Path(root) / "Sheets" / "Student A - Feedback.pdf").exists():
            problems.append("the invented sheet was not built")
        no_reason = json.loads(json.dumps(marks))
        no_reason["points"]["B1.1"]["studentNote"] = ""
        if "has no studentNote" not in attempt(no_reason).stdout:
            problems.append("a lost mark with no reason was not refused")
        half = json.loads(json.dumps(marks))
        half["points"]["B1.1"]["earned"] = 0.5
        if "half mark" not in attempt(half).stdout:
            problems.append("a half mark was not refused without the settings' yes")
    if problems:
        print("self-test FAILED: " + "; ".join(problems))
        return 1
    print("self-test passed: an invented sheet built; a lost mark with no reason and an unasked half mark refused. "
          "This checks the paths the test knows; it is no guarantee about changes it does not reach.")
    return 0


def option(arguments, name, default=None):
    if name in arguments:
        index = arguments.index(name)
        if index + 1 >= len(arguments):
            raise Refusal(f"{name} needs a value")
        return arguments[index + 1]
    return default


def main(arguments):
    if not arguments or arguments[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    checker = option(arguments, "--checker")
    if "--self-test" in arguments:
        if checker is None:
            raise Refusal("--self-test needs --checker")
        return self_test(checker)
    for needed in ("--kit", "--marks", "--out"):
        if option(arguments, needed) is None:
            raise Refusal(f"give {needed}")
    return build(option(arguments, "--kit"), option(arguments, "--marks"), option(arguments, "--out"), checker,
                 option(arguments, "--settings"), option(arguments, "--school", ""), option(arguments, "--site"),
                 option(arguments, "--links"))


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); no sheet was left half-built")
        sys.exit(1)
