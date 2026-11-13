#!/usr/bin/env python3
"""
Check a handout made in the Plantoir house style before it is handed over.

    python3 check_handout.py "path/to/Name.tex"
    python3 check_handout.py "path/to/Name.tex" --course-config "courses/CODE/course_config.json"
    python3 check_handout.py --self-test

It reads the source (and its wrappers, its PDFs and the folder it sits in),
prints one line per problem, and exits 1 if there is any. It changes
nothing and deletes nothing. It is an aid, never a requirement: what it
cannot decide from the files is listed at the end of every run, and those
things are checked by looking at every rendered page (the skill's section 8).

Rules (each line it prints starts with the rule's name):
  negative-column   a column of numbers holding a negative value is not an N column
  mixed-column      a column mixing whole numbers and decimals is not an N column
  decimal-places    a column's decimals do not all have the same number of places
  table-border      a table without its full outer border, or a heading shaded with
                    \\cellcolor or a bare \\rowcolor in a tabular
  blank-strut       a blank students write on without the strut that makes its line
                    two lines tall, or a blank typed by hand (underscores, \\hrulefill)
  key-layout        a table or graph only in the answer key, a graph's size or a
                    table's columns switched between the copies, or a tasks column
                    count switched between the copies
  arrowheads        a relation drawn with arrowheads that stops short of the grid's
                    edge, or runs past it (the axis then clips the arrowheads off)
  context-graph     a graph with a context (axes from zero, contextgraph) drawn with
                    arrowheads
  corners           a placeholder left in the corners, or corners that differ from
                    the course's print settings (with --course-config)
  wrappers          the answers, solutions or hints wrapper missing or naming the
                    wrong source
  hints             a hints sheet that is not a block of its own right after
                    \\begin{document}, or hint files with no hints in the source
  build-files       build files or rendered pictures left in the folder
  stale-pdf         a PDF older than its source, or a joined PDF older than its parts
  paper             a PDF that is not letter paper (legal is allowed for a quiz or test)
  courses-folder    the source kept inside a course folder, where the website copies it
  assessment-source an "Adapted from" line on a quiz or test
  firearms          a word about firearms or ammunition

Standard library only. Python 3.8 or later.
"""

import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Reading LaTeX


def strip_comments(text):
    """Blank out every % comment, keeping each line's length so offsets stay true."""
    lines = text.split("\n")
    result = []
    for line in lines:
        cut = None
        index = 0
        while index < len(line):
            character = line[index]
            if character == "\\":
                index += 2
                continue
            if character == "%":
                cut = index
                break
            index += 1
        if cut is None:
            result.append(line)
        else:
            result.append(line[:cut] + " " * (len(line) - cut))
    return "\n".join(result)


def matching_close(text, open_index, opener="{", closer="}"):
    """The index of the bracket that closes the one at open_index, or -1."""
    depth = 0
    index = open_index
    while index < len(text):
        character = text[index]
        if character == "\\":
            index += 2
            continue
        if character == opener:
            depth += 1
        elif character == closer:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return -1


def skip_space(text, index):
    while index < len(text) and text[index] in " \t\n":
        index += 1
    return index


def read_group(text, index, opener="{", closer="}"):
    """(contents, index after the group) when text[index] opens a group, else (None, index)."""
    index = skip_space(text, index)
    if index < len(text) and text[index] == opener:
        close = matching_close(text, index, opener, closer)
        if close < 0:
            return None, index
        return text[index + 1:close], close + 1
    return None, index


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def answer_only_spans(text):
    """
    Spans (start, end) of text that only the answer key shows: the second
    argument of \\qa, the argument of \\onlya, and the true branch of
    \\ifanswers. The hints block (\\ifhints) is reported separately.
    """
    spans = []
    for match in re.finditer(r"\\qa(?![A-Za-z])", text):
        first, after_first = read_group(text, match.end())
        if first is None:
            continue
        start = skip_space(text, after_first)
        second, after_second = read_group(text, after_first)
        if second is None:
            continue
        spans.append((start, after_second))
    for match in re.finditer(r"\\onlya(?![A-Za-z])", text):
        start = skip_space(text, match.end())
        argument, after = read_group(text, match.end())
        if argument is not None:
            spans.append((start, after))
    for start, true_end, false_start, end in if_branches(text, "answers"):
        spans.append((start, true_end))
    return spans


def if_branches(text, name):
    """For every \\if<name>: (start of the true branch, its end, start of the false branch, the \\fi)."""
    results = []
    tokens = list(re.finditer(r"\\(if[A-Za-z@]*|else|fi)(?![A-Za-z@])", text))
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.group(1) == "if" + name:
            depth = 0
            else_at = None
            fi_at = None
            look = index + 1
            while look < len(tokens):
                word = tokens[look].group(1)
                if word.startswith("if"):
                    depth += 1
                elif word == "fi":
                    if depth == 0:
                        fi_at = tokens[look]
                        break
                    depth -= 1
                elif word == "else" and depth == 0 and else_at is None:
                    else_at = tokens[look]
                look += 1
            if fi_at is not None:
                true_end = else_at.start() if else_at is not None else fi_at.start()
                false_start = else_at.end() if else_at is not None else fi_at.start()
                results.append((token.end(), true_end, false_start, fi_at.start()))
        index += 1
    return results


def inside(offset, spans):
    for start, end in spans:
        if start <= offset < end:
            return True
    return False


# ---------------------------------------------------------------------------
# Tables

NUMBER = re.compile(r"^-?\d+(\.\d+)?$")


def expand_column_spec(spec):
    """Turn a column spec into a list of (kind, raw) and border flags."""
    columns = []
    index = 0
    left_rule = False
    right_rule = False
    pending_centering = False
    seen_column = False
    while index < len(spec):
        character = spec[index]
        if character in " \t\n":
            index += 1
            continue
        if character == "|":
            if not seen_column:
                left_rule = True
            right_rule = True
            index += 1
            continue
        right_rule = False
        if character == "*":
            count, after = read_group(spec, index + 1)
            body, after = read_group(spec, after)
            try:
                times = int(count)
            except (TypeError, ValueError):
                times = 1
            spec = spec[:index] + (body or "") * times + spec[after:]
            continue
        if character in "><@!":
            argument, after = read_group(spec, index + 1)
            if character == ">" and argument is not None and "\\centering" in argument:
                pending_centering = True
            index = after if argument is not None else index + 1
            continue
        if character == "N":
            argument, after = read_group(spec, index + 1)
            columns.append(("N", "N"))
            seen_column = True
            index = after if argument is not None else index + 1
            pending_centering = False
            continue
        if character in "pmb":
            argument, after = read_group(spec, index + 1)
            columns.append(("centred" if pending_centering else "left", character))
            seen_column = True
            index = after if argument is not None else index + 1
            pending_centering = False
            continue
        if character in "wW":
            align, after = read_group(spec, index + 1)
            width, after = read_group(spec, after)
            kind = {"c": "centred", "l": "left", "r": "right"}.get((align or "").strip(), "other")
            columns.append((kind, character))
            seen_column = True
            index = after
            pending_centering = False
            continue
        if character in "cC":
            columns.append(("centred", character))
        elif character == "l":
            columns.append(("left", character))
        elif character == "r":
            columns.append(("right", character))
        elif character.isalpha():
            columns.append(("other", character))
        seen_column = True
        pending_centering = False
        index += 1
    return columns, left_rule, right_rule


def cell_values(cell):
    """The values a cell shows in either copy, as plain strings (both branches of \\qa)."""
    texts = [cell]
    expanded = []
    for text in texts:
        match = re.search(r"\\qa(?![A-Za-z])", text)
        if match is None:
            expanded.append(text)
            continue
        first, after_first = read_group(text, match.end())
        second, after_second = read_group(text, after_first)
        if first is None or second is None:
            expanded.append(text)
            continue
        before = text[:match.start()]
        rest = text[after_second:]
        expanded.extend(cell_values(before + first + rest))
        expanded.extend(cell_values(before + second + rest))
    values = []
    for text in expanded:
        cleaned = re.sub(r"\\(rowstrut|vstrut)\s*\{[^{}]*\}", "", text)
        cleaned = re.sub(r"\\makebox\s*(\[[^\]]*\])*", "", cleaned)
        cleaned = re.sub(r"\\(headstrut|centering|hfill|quad|qquad|strut)(?![A-Za-z])", "", cleaned)
        cleaned = re.sub(r"\\onlya\s*\{", "{", cleaned)
        cleaned = re.sub(r"\\onlyq\s*\{", "{", cleaned)
        cleaned = cleaned.replace("\\,", "").replace("\\ ", "").replace("\\!", "")
        cleaned = cleaned.replace("$", "").replace("{", "").replace("}", "")
        cleaned = cleaned.replace("\u2212", "-").replace(" ", "").replace("~", "")
        cleaned = cleaned.strip()
        values.append(cleaned)
    return values


def split_top(text, separator):
    """Split on a separator at brace depth 0 (and not after a backslash)."""
    parts = []
    depth = 0
    current = []
    index = 0
    while index < len(text):
        character = text[index]
        if character == "\\":
            if text.startswith(separator, index) and separator.startswith("\\"):
                if depth == 0:
                    parts.append("".join(current))
                    current = []
                    index += len(separator)
                    continue
            current.append(text[index:index + 2])
            index += 2
            continue
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
        if depth == 0 and text.startswith(separator, index):
            parts.append("".join(current))
            current = []
            index += len(separator)
            continue
        current.append(character)
        index += 1
    parts.append("".join(current))
    return parts


def find_tables(text):
    """Every tabular and NiceTabular: (kind, start offset, spec, options, body)."""
    tables = []
    for match in re.finditer(r"\\begin\{(tabular|NiceTabular)\}", text):
        kind = match.group(1)
        index = match.end()
        options = ""
        position, index_after = read_group(text, index, "[", "]")
        if position is not None:
            index = index_after
        spec, index = read_group(text, index)
        if spec is None:
            continue
        if kind == "NiceTabular":
            trailing, after = read_group(text, index, "[", "]")
            if trailing is not None:
                options = trailing
                index = after
        end = text.find("\\end{" + kind + "}", index)
        if end < 0:
            continue
        tables.append((kind, match.start(), spec, options, text[index:end]))
    return tables


def check_tables(text, problems):
    for kind, start, spec, options, body in find_tables(text):
        line = line_of(text, start)
        columns, left_rule, right_rule = expand_column_spec(spec)
        table_body = body
        if "\\CodeBefore" in table_body and "\\Body" in table_body:
            code_before = table_body[table_body.index("\\CodeBefore"):table_body.index("\\Body")]
            table_body = table_body[table_body.index("\\Body") + len("\\Body"):]
        else:
            code_before = ""
        # Borders
        if kind == "tabular":
            stripped = table_body.strip()
            if not (left_rule and right_rule):
                problems.append(("table-border", line,
                                 "this tabular has no rule at both ends of its column spec ({" + spec.strip() + "}): "
                                 "every table has a full outer border"))
            first_line = stripped.split("\n", 1)[0].strip()
            has_top = stripped.startswith("\\hline") or (stripped.startswith("\\rowcolor") and "\\hline" in first_line) \
                or re.match(r"^(\\rowcolor\s*\{[^}]*\}\s*(\[[^\]]*\]\s*)*)?\\hline", stripped) is not None
            if not stripped.startswith("\\hline") and not has_top:
                problems.append(("table-border", line, "this tabular has no \\hline above its heading row"))
            if not re.search(r"\\hline\s*$", stripped):
                problems.append(("table-border", line, "this tabular has no \\hline below its last row"))
            for row_colour in re.finditer(r"\\rowcolor(?![A-Za-z])", table_body):
                colour, after = read_group(table_body, row_colour.end())
                overhang, _ = read_group(table_body, after, "[", "]")
                if overhang is None:
                    problems.append(("table-border", line + table_body.count("\n", 0, row_colour.start()),
                                     "a bare \\rowcolor in a tabular covers the top rule at 80 dpi: use a NiceTabular "
                                     "(the tables pattern A), or give \\rowcolor both overhang arguments (pattern B)"))
        else:
            if "hvlines" not in options and "hvlines" not in spec:
                problems.append(("table-border", line, "this NiceTabular has no [hvlines]: every table has a full outer border"))
        if "\\cellcolor" in table_body:
            problems.append(("table-border", line, "a heading shaded with \\cellcolor covers the rules: shade the row "
                                                   "(\\rowcolor in \\CodeBefore of a NiceTabular)"))
        # Rows and columns
        rows = []
        for raw_row in split_top(table_body, "\\\\"):
            row = re.sub(r"^\s*\[[^\]]*\]", "", raw_row)
            row = re.sub(r"\\(hline|toprule|midrule|bottomrule)(?![A-Za-z])", "", row)
            row = re.sub(r"\\cline\s*\{[^}]*\}", "", row)
            row = re.sub(r"\\rowcolor\s*\{[^}]*\}(\s*\[[^\]]*\])*", "", row)
            if row.strip() == "":
                continue
            rows.append(split_top(row, "&"))
        if len(rows) < 2 or not columns:
            continue
        first_cells = []
        for row in rows:
            first_cells.append(row[0])
        horizontal = True
        for cell in first_cells:
            numeric = False
            for value in cell_values(cell):
                if NUMBER.match(value):
                    numeric = True
            if numeric:
                horizontal = False
        if horizontal:
            continue   # a horizontal table: one value per column, so nothing to align
        for column_index in range(len(columns)):
            kind_of_column, letter = columns[column_index]
            values = []
            for row in rows[1:]:
                if column_index >= len(row):
                    continue
                cell = row[column_index]
                if "\\multicolumn" in cell or "\\Block" in cell:
                    continue
                for value in cell_values(cell):
                    if NUMBER.match(value):
                        values.append(value)
            if not values:
                continue
            has_negative = False
            has_whole = False
            has_fraction_part = False
            places = set()
            for value in values:
                if value.startswith("-") and value != "-0":
                    has_negative = True
                if "." in value:
                    places.add(len(value.split(".")[1]))
                    if set(value.split(".")[1]) != {"0"}:
                        has_fraction_part = True
                    else:
                        has_whole = True
                else:
                    places.add(0)
                    has_whole = True
            number = column_index + 1
            if len(places) > 1:
                problems.append(("decimal-places", line,
                                 "column " + str(number) + " has values with different numbers of decimal places ("
                                 + ", ".join(sorted(set(values))[:6]) + "): write every value to the same places"))
            if kind_of_column in ("N", "other"):
                continue
            if has_negative:
                problems.append(("negative-column", line,
                                 "column " + str(number) + " holds a negative value but is set '" + letter
                                 + "': a column with any negative value is an N column (each value right-aligned "
                                   "in a box as wide as the widest value without its sign, the box centred)"))
            elif has_whole and has_fraction_part:
                problems.append(("mixed-column", line,
                                 "column " + str(number) + " mixes whole numbers and decimals but is set '" + letter
                                 + "': make it an N column, so the decimal points line up"))


# ---------------------------------------------------------------------------
# Blanks

def check_blanks(text, problems):
    body_start = text.find("\\begin{document}")
    preamble = text[:body_start] if body_start >= 0 else text
    body = text[body_start:] if body_start >= 0 else ""
    offset = body_start if body_start >= 0 else 0
    header_lines = set()
    for match in re.finditer(r"\\fancy(head|foot)", text):
        header_lines.add(line_of(text, match.start()))
    definitions = {}
    for match in re.finditer(r"\\(re)?newcommand\s*\{?\\([A-Za-z]+)\}?", text):
        name = match.group(2)
        index = match.end()
        index = skip_space(text, index)
        while index < len(text) and text[index] == "[":
            close = matching_close(text, index, "[", "]")
            index = skip_space(text, close + 1)
        definition, after = read_group(text, index)
        if definition is not None:
            definitions[name] = (definition, line_of(text, match.start()))
    for name, (definition, line) in definitions.items():
        visible = re.search(r"\\rule\s*(\[[^\]]*\])?\s*\{(?!0pt\})[^}]*\}\s*\{0\.\d+pt\}", definition)
        if visible is None:
            continue
        if "\\marginpar" in definition:
            continue
        used_in_body = False
        for use in re.finditer(r"\\" + name + r"(?![A-Za-z])", body):
            if line_of(text, offset + use.start()) in header_lines:
                continue
            used_in_body = True
        if not used_in_body:
            continue
        strut = re.search(r"\\rule\s*(\[[^\]]*\])?\s*\{0pt\}\s*\{([\d.]+)em\}", definition)
        if strut is None or float(strut.group(2)) < 1.8:
            problems.append(("blank-strut", line,
                             "\\" + name + " draws a blank students write on without an invisible strut about two "
                             "lines tall (\\rule[-0.2em]{0pt}{2.1em} after the rule), so a wrapped prompt has no room"))
    for match in re.finditer(r"\\rule\s*(\[[^\]]*\])?\s*\{(?!0pt\})([^}]*)\}\s*\{0\.\d+pt\}", body):
        absolute = offset + match.start()
        line = line_of(text, absolute)
        if line in header_lines:
            continue
        before = text[max(0, absolute - 400):absolute]
        if "\\totals" in before.split("\n")[-1] or re.search(r"\\totals\s*\{[^}]*$", before):
            continue
        same_line = text.split("\n")[line - 1]
        if re.search(r"\\rule\s*(\[[^\]]*\])?\s*\{0pt\}\s*\{([\d.]+)em\}", same_line):
            continue
        problems.append(("blank-strut", line, "a blank typed by hand with \\rule: use \\fillin, whose strut gives "
                                              "the line the room of two"))
    for match in re.finditer(r"(\\_){3,}|_{4,}|\\hrulefill|\\underline\s*\{\\hspace", body):
        line = line_of(text, offset + match.start())
        problems.append(("blank-strut", line, "a blank made of underscores or \\hrulefill: use \\fillin"))


# ---------------------------------------------------------------------------
# The answer key keeps the question copy's layout

def check_key_layout(text, problems):
    spans = answer_only_spans(text)
    hint_spans = []
    for start, true_end, false_start, end in if_branches(text, "hints"):
        hint_spans.append((start, true_end))
    for match in re.finditer(r"\\begin\{(tabular|NiceTabular|axis|tikzpicture)\}", text):
        if inside(match.start(), hint_spans):
            continue
        if inside(match.start(), spans):
            what = "graph" if match.group(1) in ("axis", "tikzpicture") else "table"
            problems.append(("key-layout", line_of(text, match.start()),
                             "this " + what + " is only in the answer key: author it once, outside the switch, and "
                             "switch only its cells or the plotted answer"))
    for match in re.finditer(r"\\begin\{axis\}", text):
        options, after = read_group(text, match.end(), "[", "]")
        if options and re.search(r"\\(qa|onlya|onlyq|ifanswers)(?![A-Za-z])", options):
            problems.append(("key-layout", line_of(text, match.start()),
                             "this graph's options change between the copies: the key's grid has the question's "
                             "ranges, scale and size"))
    for kind, start, spec, options, body in find_tables(text):
        if re.search(r"\\(qa|onlya|onlyq|ifanswers)(?![A-Za-z])", spec):
            problems.append(("key-layout", line_of(text, start),
                             "this table's columns change between the copies: the key keeps the question's table"))
    for match in re.finditer(r"\\begin\{tasks\}\s*\(([^)]*)\)", text):
        if re.search(r"\\(qa|ifanswers)(?![A-Za-z])", match.group(1)):
            problems.append(("key-layout", line_of(text, match.start()),
                             "the tasks column count changes in the key: the key keeps the worksheet's column count"))


# ---------------------------------------------------------------------------
# Graphs

SAFE_NAMES = {"sqrt": math.sqrt, "abs": abs, "exp": math.exp, "ln": math.log, "log10": math.log10,
              "pi": math.pi, "e": math.e,
              "sin": lambda value: math.sin(math.radians(value)),
              "cos": lambda value: math.cos(math.radians(value)),
              "tan": lambda value: math.tan(math.radians(value))}


def make_function(expression, variable="x"):
    python = expression.replace("^", "**").replace("\\x", "x").replace("\\t", "t")
    python = re.sub(r"(?<=[0-9)])\s*(?=[a-z(])", "*", python)
    if re.search(r"[^0-9a-z_+\-*/().\s]", python):
        return None
    for word in re.findall(r"[a-z_][a-z0-9_]*", python):
        if word not in SAFE_NAMES and word != variable:
            return None
    try:
        code = compile(python, "<plot>", "eval")
    except SyntaxError:
        return None

    def evaluate(value):
        names = dict(SAFE_NAMES)
        names[variable] = value
        return eval(code, {"__builtins__": {}}, names)
    return evaluate


def number_option(options, name):
    match = re.search(r"(?<![A-Za-z])" + name + r"\s*=\s*(-?[\d.]+)", options)
    return float(match.group(1)) if match else None


def check_graphs(text, problems):
    for match in re.finditer(r"\\begin\{axis\}", text):
        options, after = read_group(text, match.end(), "[", "]")
        options = options or ""
        end = text.find("\\end{axis}", after)
        if end < 0:
            continue
        body = text[after:end]
        limits = [number_option(options, "xmin"), number_option(options, "xmax"),
                  number_option(options, "ymin"), number_option(options, "ymax")]
        context = "contextgraph" in options or re.search(r"axis lines\s*=\s*left", options) is not None
        for plot in re.finditer(r"\\addplot(\+)?\s*(\[[^\]]*\])?\s*(\{)", body):
            plot_options = plot.group(2) or ""
            arrowed = ("<->" in plot_options or "latex-latex" in plot_options or "stealth-stealth" in plot_options
                       or "exampleline" in plot_options)
            line = line_of(text, after + plot.start())
            if not arrowed:
                continue
            if context:
                problems.append(("context-graph", line,
                                 "a graph with a context stops at the end points the situation gives it, with no "
                                 "arrowheads"))
                continue
            expression_open = after + plot.start(3) - plot.start(0) + plot.start(0)
            expression_open = after + plot.start(3)
            close = matching_close(text, expression_open)
            if close < 0 or None in limits:
                continue
            expression = text[expression_open + 1:close]
            domain = re.search(r"domain\s*=\s*(-?[\d.]+)\s*:\s*(-?[\d.]+)", plot_options) \
                or re.search(r"domain\s*=\s*(-?[\d.]+)\s*:\s*(-?[\d.]+)", options)
            if domain is None:
                problems.append(("arrowheads", line, "this relation has arrowheads but no domain: without one "
                                                     "it runs past the grid and the axis clips its arrowheads off"))
                continue
            function = make_function(expression)
            if function is None:
                continue
            low, high = float(domain.group(1)), float(domain.group(2))
            xmin, xmax, ymin, ymax = limits
            width = xmax - xmin
            height = ymax - ymin
            try:
                points = []
                for step in range(201):
                    value = low + (high - low) * step / 200
                    points.append((value, float(function(value))))
            except (ValueError, ZeroDivisionError, OverflowError, TypeError):
                continue
            tolerance_x = width * 1e-6
            tolerance_y = height * 1e-6
            outside = False
            for x_value, y_value in points:
                if x_value < xmin - tolerance_x or x_value > xmax + tolerance_x or \
                        y_value < ymin - tolerance_y or y_value > ymax + tolerance_y:
                    outside = True
                    break
            if outside:
                problems.append(("arrowheads", line,
                                 "y = " + expression.strip() + " runs past the grid's edge on domain " + domain.group(1)
                                 + ":" + domain.group(2) + ", so the axis clips its arrowheads off: stop each end at the "
                                 "FIRST edge the curve crosses"))
                continue
            for x_value, y_value in (points[0], points[-1]):
                gap = min((x_value - xmin) / width, (xmax - x_value) / width,
                          (y_value - ymin) / height, (ymax - y_value) / height)
                if gap > 0.06:
                    problems.append(("arrowheads", line,
                                     "y = " + expression.strip() + " ends at (" + format(x_value, "g") + ", "
                                     + format(y_value, "g") + "), well inside the grid: a relation without a context "
                                     "is drawn to the grid's edge"))
                    break


# ---------------------------------------------------------------------------
# Corners

def macro_value(text, name):
    match = re.search(r"\\newcommand\s*\{\\" + name + r"\}\s*\{", text)
    if match is None:
        return None
    value, after = read_group(text, match.end() - 1)
    return value


def corner_text(text, which, place):
    match = re.search(r"\\fancy" + which + r"\s*\[" + place + r"\]\s*\{", text)
    if match is None:
        return ""
    value, after = read_group(text, match.end() - 1)
    value = value or ""
    school = macro_value(text, "schoolname")
    code = macro_value(text, "coursecode")
    if school is not None:
        value = re.sub(r"\\schoolname(?![A-Za-z])", lambda found: school, value)
    if code is not None:
        value = re.sub(r"\\coursecode(?![A-Za-z])", lambda found: code, value)
    return value


def check_corners(text, config_path, problems):
    for placeholder in ("School Name", "Handout Title", "Quiz Title"):
        for match in re.finditer(re.escape(placeholder), text):
            problems.append(("corners", line_of(text, match.start()),
                             "the placeholder '" + placeholder + "' is still there"))
    code = macro_value(text, "coursecode")
    if code is not None and code.strip() == "COURSE":
        problems.append(("corners", line_of(text, text.find("\\newcommand{\\coursecode}")),
                         "the course code is still the placeholder COURSE"))
    if config_path is None:
        return
    try:
        settings = json.loads(Path(config_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        problems.append(("corners", 0, "could not read " + str(config_path) + ": " + str(error)))
        return
    school = str(settings.get("print_school_name") or "").strip()
    school_at = settings.get("print_school_name_at")
    if school_at not in ("header_left", "footer_left", "none"):
        school_at = "header_left"
    code_at = settings.get("print_course_code_at")
    if code_at not in ("header_left", "footer_left", "none"):
        code_at = "footer_left"
    folder_code = Path(config_path).resolve().parent.name
    course_code = str(settings.get("course_code") or folder_code).strip().upper()
    if "print_blanks" not in settings or settings.get("print_blanks") is None:
        blanks = ["name", "date"]
    elif isinstance(settings.get("print_blanks"), list):
        blanks = settings.get("print_blanks")
    else:
        blanks = []
    top_left = corner_text(text, "head", "L")
    bottom_left = corner_text(text, "foot", "L")
    top_right = corner_text(text, "head", "R")
    places = {"header_left": top_left, "footer_left": bottom_left}
    if school:
        for place, value in places.items():
            if place == school_at and school not in value:
                problems.append(("corners", 0, "the course's settings put the school's name '" + school + "' at "
                                 + place + ", and that corner does not carry it"))
            if place != school_at and school in value:
                problems.append(("corners", 0, "the school's name is at " + place + ", but the course's settings put it "
                                 "at " + school_at))
    else:
        school_macro = (macro_value(text, "schoolname") or "").strip()
        if school_macro:
            problems.append(("corners", 0, "the course's settings have no school's name, but the handout prints '"
                             + school_macro + "': it comes only from the settings or from the teacher in this "
                             "conversation (if the teacher gave it, ignore this line)"))
    for place, value in places.items():
        if place == code_at and course_code and course_code not in value:
            problems.append(("corners", 0, "the course's settings put the course code " + course_code + " at "
                             + place + ", and that corner does not carry it"))
    words = {"name": "{Name}", "date": "{Date}", "class_number": "{Class \\#}"}
    for blank, word in words.items():
        present = word in top_right
        if blank in blanks and not present:
            problems.append(("corners", 0, "the course's settings list the " + blank + " blank, and the top-right "
                             "corner does not print it"))
        if blank not in blanks and present:
            problems.append(("corners", 0, "the top-right corner prints the " + blank + " blank, which the course's "
                             "settings do not list"))


# ---------------------------------------------------------------------------
# Files around the source

BUILD_SUFFIXES = (".aux", ".log", ".out", ".fls", ".fdb_latexmk", ".toc", ".xdv", ".bbl", ".blg",
                  ".synctex.gz", ".synctex", ".nav", ".snm")


def wrapper_names(stem):
    return [stem + " - Answers.tex", stem + " - Solutions.tex"]


def check_wrapper(path, stem, define, problems):
    text = path.read_text(encoding="utf-8", errors="replace")
    if "\\def\\" + define + "{}" not in text:
        problems.append(("wrappers", 0, path.name + " does not define \\" + define))
    inputs = re.findall(r"\\input\s*\{([^}]*)\}", text)
    wanted = [stem + ".tex", stem]
    if not inputs or inputs[0].strip().strip('"') not in wanted:
        problems.append(("wrappers", 0, path.name + " does not \\input{" + stem + ".tex}"))


def check_files(source, text, problems):
    folder = source.parent
    stem = source.stem
    parts = [part.lower() for part in source.resolve().parts]
    if "courses" in parts[:-1]:
        problems.append(("courses-folder", 0, "the source is inside a courses folder: every file there that is not a "
                                              "page is copied to the class website, so keep it outside courses/"))
    assessment = "\\score" in text or (folder / (stem + " - Solutions.tex")).exists()
    answers_wrappers = []
    for name in wrapper_names(stem):
        if (folder / name).exists():
            answers_wrappers.append(folder / name)
    if not answers_wrappers:
        problems.append(("wrappers", 0, "no '" + stem + " - Answers.tex' (or '- Solutions.tex' for a quiz or test) "
                                        "beside the source"))
    for wrapper in answers_wrappers:
        check_wrapper(wrapper, stem, "showanswers", problems)
    has_hints_block = re.search(r"\\ifhints(?![A-Za-z])", text) is not None and "\\hint{" in text
    hints_wrapper = folder / (stem + " - Hints.tex")
    hint_files = [folder / (stem + " - Hints.pdf"), folder / (stem + " - with Hints.pdf"), hints_wrapper]
    if has_hints_block:
        if not hints_wrapper.exists():
            problems.append(("wrappers", 0, "the source has hints but no '" + stem + " - Hints.tex' beside it"))
        else:
            check_wrapper(hints_wrapper, stem, "showhints", problems)
    else:
        for hint_file in hint_files:
            if hint_file.exists():
                problems.append(("hints", 0, hint_file.name + " is in the folder, but the source has no hints block"))
                break
    # Build files and rendered pages
    for entry in sorted(folder.iterdir()):
        name = entry.name
        if entry.is_dir():
            if name in (".handout-check", "handout-check"):
                problems.append(("build-files", 0, "the folder '" + name + "' of rendered pages is still there"))
            continue
        lower = name.lower()
        for suffix in BUILD_SUFFIXES:
            if lower.endswith(suffix):
                problems.append(("build-files", 0, "the build file '" + name + "' is still in the folder"))
                break
        if re.search(r"-\d+\.png$", lower):
            problems.append(("build-files", 0, "the rendered page '" + name + "' is still in the folder"))
    # PDFs: fresh, and on the right paper
    pdfs = {}
    for suffix in ("", " - Answers", " - Solutions", " - Hints", " - with Answers", " - with Hints"):
        candidate = folder / (stem + suffix + ".pdf")
        if candidate.exists():
            pdfs[suffix] = candidate
    sources = [source] + answers_wrappers + ([hints_wrapper] if hints_wrapper.exists() else [])
    newest_source = 0.0
    for item in sources:
        newest_source = max(newest_source, item.stat().st_mtime)
    for suffix, pdf in pdfs.items():
        if suffix.startswith(" - with"):
            continue
        if pdf.stat().st_mtime + 1 < source.stat().st_mtime:
            problems.append(("stale-pdf", 0, pdf.name + " is older than " + source.name + ": compile it again"))
    for joined, part in ((" - with Answers", " - Answers"), (" - with Hints", " - Hints")):
        if joined in pdfs:
            for needed in ("", part):
                if needed in pdfs and pdfs[joined].stat().st_mtime + 1 < pdfs[needed].stat().st_mtime:
                    problems.append(("stale-pdf", 0, pdfs[joined].name + " is older than " + pdfs[needed].name
                                     + ": join them again"))
                    break
    if shutil.which("pdfinfo"):
        for suffix, pdf in pdfs.items():
            try:
                output = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, timeout=30).stdout
            except (OSError, subprocess.SubprocessError):
                continue
            size = re.search(r"Page size:\s+([\d.]+) x ([\d.]+)", output)
            if size is None:
                continue
            width, height = round(float(size.group(1))), round(float(size.group(2)))
            if (width, height) == (612, 792):
                continue
            if (width, height) == (612, 1008) and assessment:
                continue
            problems.append(("paper", 0, pdf.name + " is " + str(width) + " x " + str(height)
                             + " pt: a handout is letter paper (612 x 792), a test may be legal"))
    return assessment


def check_hints(text, problems):
    branches = if_branches(text, "hints")
    document = text.find("\\begin{document}")
    uses = list(re.finditer(r"\\hint\s*\{", text))
    body_uses = []
    for use in uses:
        if use.start() > document >= 0:
            body_uses.append(use)
    if not body_uses:
        return
    block = None
    for start, true_end, false_start, end in branches:
        if start > document:
            block = (start, true_end)
            break
    if block is None:
        problems.append(("hints", line_of(text, body_uses[0].start()),
                         "\\hint is used but there is no \\ifhints block: the hints go in one block right after "
                         "\\begin{document}, ending with \\end{document}"))
        return
    between = text[document + len("\\begin{document}"):block[0] - len("\\ifhints")]
    if between.strip():
        problems.append(("hints", line_of(text, block[0]),
                         "the hints block is not the first thing after \\begin{document}, so the hints sheet would "
                         "carry what comes before it"))
    if "\\end{document}" not in text[block[0]:block[1]]:
        problems.append(("hints", line_of(text, block[0]),
                         "the hints block does not end with \\end{document}, so the hints sheet would carry the "
                         "questions too"))
    for use in body_uses:
        if not (block[0] <= use.start() < block[1]):
            problems.append(("hints", line_of(text, use.start()),
                             "a \\hint outside the hints block: put every hint in the block, so the questions and the "
                             "answers compile exactly as they would without hints"))


FIREARMS = re.compile(r"(?<!\\)\b(guns?|rifles?|pistols?|firearms?|ammunition|ammo|bullets?|shotguns?|revolvers?|"
                      r"handguns?|muskets?|gunfire|gunshots?)\b", re.IGNORECASE)


def check_words(text, assessment, problems):
    for match in FIREARMS.finditer(text):
        problems.append(("firearms", line_of(text, match.start()),
                         "'" + match.group(0) + "': contexts never involve firearms or ammunition"))
    if assessment:
        for match in re.finditer(r"Adapted from", text):
            problems.append(("assessment-source", line_of(text, match.start()),
                             "an assessment carries no 'Adapted from' line: it tells students where to look the "
                             "questions up"))


# ---------------------------------------------------------------------------

CANNOT_CHECK = [
    "every table's top edge is there at 80 dpi, and no notch at 600 dpi",
    "each value sits in the middle of its row, half a row from the heading and bottom rules",
    "a graph WITHOUT arrowheads really has a context (a relation with none goes to the edge, with arrowheads)",
    "a context graph stops at the end points its situation gives",
    "no label is crossed by a curve; legends do not cover a curve",
    "nothing is clipped, no box is split across pages, no question is parted from its parts",
    "no answer shows on the student copy, and the hints give no answer away",
    "the key's tables and grids look the same as the question copy's",
    "every answer is right (solve each again, another way)",
]


def check(source, config_path=None):
    source = Path(source)
    raw = source.read_text(encoding="utf-8", errors="replace")
    text = strip_comments(raw)
    problems = []
    check_tables(text, problems)
    check_blanks(text, problems)
    check_key_layout(text, problems)
    check_graphs(text, problems)
    check_corners(text, config_path, problems)
    check_hints(text, problems)
    assessment = check_files(source, text, problems)
    check_words(text, assessment, problems)
    return problems


def report(source, problems):
    lines = []
    for rule, line, message in problems:
        place = (" line " + str(line)) if line else ""
        lines.append(rule + ":" + place + " " + message)
    if problems:
        lines.append("check_handout: " + str(len(problems)) + " problem(s) in " + Path(source).name
                     + ". Fix each, compile again, and run this again.")
    else:
        lines.append("check_handout: nothing found in " + Path(source).name + ".")
    lines.append("Still to check by looking at every rendered page:")
    for item in CANNOT_CHECK:
        lines.append("  - " + item)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Self-test: every rule fires on a source that breaks it, and none fires on a clean one.

CLEAN = r"""\documentclass[11pt]{article}
\newcommand{\schoolname}{}
\newcommand{\coursecode}{MTH1W}
\newcommand{\handouttitle}{Lines}
\newcommand{\fillblank}[2]{#1 \rule[-0.15em]{#2}{0.4pt}}
\newcommand{\fillin}[2][3.2cm]{\ \qa{\rule[-0.2em]{#1}{0.4pt}}{#2}\rule[-0.2em]{0pt}{2.1em}}
\fancyhead[L]{\schoolname}
\fancyhead[R]{\fillblank{Name}{3.2cm}\quad\fillblank{Date}{2.2cm}}
\fancyfoot[L]{\handouttitle\ $\cdot$ \coursecode}
\begin{document}
\ifhints
\begin{description}
  \hint{1}{Look back at the worked example.}
\end{description}
\end{document}
\fi
\begin{NiceTabular}{N{$3$}N{$5$}}[hvlines]
\CodeBefore \rowcolor{tablehead}{1} \Body
\multicolumn{1}{c}{$x$} & \multicolumn{1}{c}{$y$} \\
$-1$ & \qa{}{$5$} \\
$0$ & \qa{}{$-3$} \\
\end{NiceTabular}
\begin{tasks}(2)
  \task \qa{$2x$}{$4$}
\end{tasks}
\begin{tikzpicture}\begin{axis}[gridgraph, xmin=-4, xmax=6, ymin=-6, ymax=6]
  \onlya{\addplot[lineA, <->, >=latex, domain=-1.45:4.45]{-2*x + 3};}
\end{axis}\end{tikzpicture}
\begin{tikzpicture}\begin{axis}[contextgraph, xmin=0, xmax=5, ymin=0, ymax=20]
  \addplot[lineA, domain=0:4]{4.5*x};
\end{axis}\end{tikzpicture}
Its slope is \fillin{$-2$}.
\end{document}
"""

BREAKS = [
    ("negative-column", r"\begin{NiceTabular}{N{$3$}N{$5$}}[hvlines]", r"\begin{NiceTabular}{N{$3$}C}[hvlines]"),
    ("negative-column", r"\begin{NiceTabular}{N{$3$}N{$5$}}[hvlines]", r"\begin{NiceTabular}{N{$3$}c}[hvlines]"),
    ("mixed-column", "N{$5$}}[hvlines]\n\\CodeBefore \\rowcolor{tablehead}{1} \\Body\n\\multicolumn{1}{c}{$x$} & \\multicolumn{1}{c}{$y$} \\\\\n$-1$ & \\qa{}{$5$} \\\\\n$0$ & \\qa{}{$-3$} \\\\",
     "C}[hvlines]\n\\CodeBefore \\rowcolor{tablehead}{1} \\Body\n\\multicolumn{1}{c}{$x$} & \\multicolumn{1}{c}{$y$} \\\\\n$-1$ & \\qa{}{$5.0$} \\\\\n$0$ & \\qa{}{$2.5$} \\\\"),
    ("decimal-places", "$0$ & \\qa{}{$-3$} \\\\", "$0$ & \\qa{}{$-3$} \\\\\n$1$ & $2.5$ \\\\"),
    ("table-border", "[hvlines]", ""),
    ("blank-strut", r"\rule[-0.2em]{0pt}{2.1em}}", "}"),
    ("blank-strut", r"Its slope is \fillin{$-2$}.", r"Its slope is \rule{3cm}{0.4pt}."),
    ("blank-strut", r"Its slope is \fillin{$-2$}.", r"Its slope is \_\_\_\_\_."),
    ("key-layout", r"\onlya{\addplot", r"\onlya{\begin{tikzpicture}\begin{axis}[xmin=0]\end{axis}\end{tikzpicture}\addplot"),
    ("key-layout", r"[gridgraph, xmin=-4,", r"[gridgraph, \qa{width=6cm}{width=4cm}, xmin=-4,"),
    ("key-layout", r"\begin{tasks}(2)", r"\begin{tasks}(\qa{1}{3})"),
    ("arrowheads", "domain=-1.45:4.45", "domain=-4:6"),
    ("arrowheads", "domain=-1.45:4.45", "domain=0:2"),
    ("context-graph", r"\addplot[lineA, domain=0:4]{4.5*x};", r"\addplot[lineA, <->, >=latex, domain=0:4]{4.5*x};"),
    ("corners", r"\newcommand{\coursecode}{MTH1W}", r"\newcommand{\coursecode}{COURSE}"),
    ("corners", r"\newcommand{\schoolname}{}", r"\newcommand{\schoolname}{School Name}"),
    ("hints", "\\end{document}\n\\fi", "\\fi"),
    ("hints", r"Its slope is", r"\hint{2}{Try harder.} Its slope is"),
    ("firearms", "Look back at the worked example.", "Look back at the worked example. firearms"),   # the word alone, no context
]


def self_test():
    failures = []
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary) / "handouts"
        folder.mkdir()
        source = folder / "Lines.tex"

        def write(text):
            source.write_text(text, encoding="utf-8")
            (folder / "Lines - Answers.tex").write_text("\\def\\showanswers{}\n\\input{Lines.tex}\n", encoding="utf-8")
            (folder / "Lines - Hints.tex").write_text("\\def\\showhints{}\n\\input{Lines.tex}\n", encoding="utf-8")

        write(CLEAN)
        clean = check(source)
        if clean:
            failures.append("the clean source reported: " + "; ".join(rule + " " + message for rule, line, message in clean))
        for rule, old, new in BREAKS:
            if old not in CLEAN:
                failures.append("self-test case for " + rule + " does not apply: " + old)
                continue
            write(CLEAN.replace(old, new, 1))
            found = []
            for found_rule, line, message in check(source):
                found.append(found_rule)
            if rule not in found:
                failures.append(rule + " did not fire for: " + new[:60])
        write(CLEAN)
        # Files beside the source
        (folder / "Lines.aux").write_text("", encoding="utf-8")
        (folder / "Lines-1.png").write_bytes(b"")
        found = [rule for rule, line, message in check(source)]
        if found.count("build-files") != 2:
            failures.append("build-files did not fire twice: " + ", ".join(found))
        os.remove(folder / "Lines.aux")
        os.remove(folder / "Lines-1.png")
        os.remove(folder / "Lines - Answers.tex")
        found = [rule for rule, line, message in check(source)]
        if "wrappers" not in found:
            failures.append("wrappers did not fire with no answers wrapper")
        (folder / "Lines - Answers.tex").write_text("\\def\\showanswers{}\n\\input{Other.tex}\n", encoding="utf-8")
        found = [rule for rule, line, message in check(source)]
        if "wrappers" not in found:
            failures.append("wrappers did not fire for a wrapper naming another source")
        write(CLEAN.replace("\\hint{1}", "\\item[1]"))
        (folder / "Lines - with Hints.pdf").write_bytes(b"%PDF-1.4\n")
        found = [rule for rule, line, message in check(source)]
        if "hints" not in found:
            failures.append("hints did not fire for hint files with no hints in the source")
        os.remove(folder / "Lines - with Hints.pdf")
        write(CLEAN)
        (folder / "Lines.pdf").write_bytes(b"%PDF-1.4\n")
        os.utime(folder / "Lines.pdf", (1000000000, 1000000000))
        found = [rule for rule, line, message in check(source)]
        if "stale-pdf" not in found:
            failures.append("stale-pdf did not fire for a PDF older than its source")
        os.remove(folder / "Lines.pdf")
        # A quiz
        quiz = CLEAN.replace("\\begin{document}", "\\begin{document}\n\\score{K 4} Adapted from a textbook.", 1)
        write(quiz)
        found = [rule for rule, line, message in check(source)]
        if "assessment-source" not in found:
            failures.append("assessment-source did not fire on a quiz")
        write(CLEAN)
        # Corners against the course's settings
        course = Path(temporary) / "courses" / "MTH1W"
        course.mkdir(parents=True)
        config = course / "course_config.json"
        config.write_text(json.dumps({"print_school_name": ""}), encoding="utf-8")
        found = [rule for rule, line, message in check(source, config)]
        if "corners" in found:
            failures.append("corners fired for corners that match the settings")
        config.write_text(json.dumps({"print_school_name": "Example Secondary School"}), encoding="utf-8")
        found = [rule for rule, line, message in check(source, config)]
        if "corners" not in found:
            failures.append("corners did not fire for a school's name the handout leaves out")
        config.write_text(json.dumps({"print_blanks": ["name", "date", "class_number"]}), encoding="utf-8")
        found = [rule for rule, line, message in check(source, config)]
        if "corners" not in found:
            failures.append("corners did not fire for a missing Class # blank")
        # Inside courses/
        inside_course = course / "Lines.tex"
        inside_course.write_text(CLEAN, encoding="utf-8")
        found = [rule for rule, line, message in check(inside_course)]
        if "courses-folder" not in found:
            failures.append("courses-folder did not fire for a source inside courses/")
    if failures:
        for failure in failures:
            print("SELF-TEST FAILED: " + failure)
        return 1
    print("check_handout: self-test passed (" + str(len(BREAKS) + 10) + " cases)")
    return 0


def main(arguments):
    if "--self-test" in arguments:
        return self_test()
    config = None
    sources = []
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--course-config" and index + 1 < len(arguments):
            config = arguments[index + 1]
            index += 2
            continue
        sources.append(argument)
        index += 1
    if not sources:
        print(__doc__)
        return 2
    status = 0
    for source in sources:
        path = Path(source)
        if not path.exists():
            print("check_handout: no file " + source)
            status = 2
            continue
        problems = check(path, config)
        print(report(path, problems))
        if problems:
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
