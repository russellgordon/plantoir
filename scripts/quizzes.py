#!/usr/bin/env python3
"""
Self-check quizzes (#563): the folder check's half - contracts/shared-rules.json
-> quizCallouts.

A teacher writes a `> [!quiz]` callout on a page; the site's transformer
(support/quartz/plugins/transformers/plantoirQuizzes.ts) turns it into a
question a student can answer and check, by the rules in quizRules.ts. This
file reads the SAME raw text by the same rules so that a quiz that cannot be
checked is reported where every folder problem is - a `plantoir: error:` line
naming the page, the question and the line in the teacher's own file, and the
`quizzesNotReady` finding both apps show - before a student meets it.

It never checks an answer: parse_answer_line is a mirror for validation only,
and comparing what a student typed happens in the browser alone (quizRules.ts
accepts). It writes two files the site reads on every build:

* quartz/plantoir_quiz.json - the words, from the contract. The page's script
  bundles it, so it must change only when the words do.
* quartz/plantoir_quiz_pages.json - which pages this check examined and what
  it found on each, for the transformer's safety net (quizCallouts.safetyNet):
  a quiz the site renders as not ready, or reads differently, that this file
  did not report says so on a `plantoir: error:` line of its own.

Stdlib only, no frontmatter: Windows' PythonToolchainTests discovers
test_quizzes.py and runs it without python-frontmatter.

The reading is line by line, not a Markdown parser, for the reason
markdown_code gives (the apps cannot share one); the contract's recognise
cases pin every shape the two sides must agree on.
"""

import bisect
import json
import re
from pathlib import Path

import contracts
import markdown_code

# The words file the page's script bundles, and the pages file only the
# transformer reads.
WORDS_FILE = "plantoir_quiz.json"
PAGES_FILE = "plantoir_quiz_pages.json"

# The only quiz setting there is (quizRules.OPTIONS).
OPTIONS = ("shuffle",)

# A callout's first line, after its quote markers, as Quartz's
# ObsidianFlavoredMarkdown reads it: `[!type|metadata]+` or `-`, then the
# title. JavaScript's \w (no u flag) is ASCII, so it is spelled out here.
_CALLOUT = re.compile(r"^\[!([A-Za-z0-9_-]+)\|?(.+?)?\]([+-]?)(.*)$")
# One quote marker as CommonMark reads it: up to three spaces, `>`, then one
# optional space or tab.
_ONE_MARKER = re.compile(r"^ {0,3}>[ \t]?")
# A list item's marker: bullet or ordered, then a space or tab (or the end).
_LIST_ITEM = re.compile(r"^( {0,3})([-*+]|[0-9]{1,9}[.)])([ \t]+|$)(.*)$")
# A task box at the start of a list item's text (GFM): [ ], [x] or [X], then
# a space or tab, then more on that line - a box with nothing after it is
# plain text to the site's parser (measured: `- [ ]` and `- [ ] ` alone).
_TASK_BOX = re.compile(r"^\[([ xX])\][ \t]+\S")
# A fence opener on a line's body (after its indent), after any list markers.
_FENCE_OPEN = re.compile(r"^(?:(?:[-*+]|[0-9]{1,9}[.)])[ \t]+)*(`{3,}|~{3,})(.*)$")
# A list marker that opens a container on a line (quizRules.containersOf).
_LIST_OPENER = re.compile(r"^([-*+]|[0-9]{1,9}[.)])[ \t]+")
# The lines that start a block of their own, so they are never a paragraph's
# lazy continuation: a list item, a heading, a fence, a thematic break, a
# table row, an HTML block.
_BLOCK_START = re.compile(
    r"^[ \t]{0,3}(?:[-*+](?:[ \t]|$)|[0-9]{1,9}[.)](?:[ \t]|$)|#{1,6}(?:[ \t]|$)|`{3,}|~{3,}|<"
    r"|(?:-[ \t]*){3,}$|(?:\*[ \t]*){3,}$|(?:_[ \t]*){3,}$)")
# A line inside a quiz that is not paragraph text of the stem: a heading or a
# table row.
_NOT_STEM_TEXT = re.compile(r"^[ \t]{0,3}(?:#{1,6}(?:[ \t]|$)|\|)")
# An HTML block CommonMark opens with a block-level tag (its type 6): it runs
# to the next empty line and swallows whatever Markdown is in it - a list of
# choices included - as the site's parser does.
_HTML_BLOCK = re.compile(
    r"^ {0,3}</?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd"
    r"|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head"
    r"|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param"
    r"|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:[ \t>]|/>|$)",
    re.IGNORECASE)
# CommonMark's HTML block type 7: a line holding only one whole tag (open or
# closing, any name but the raw-text ones), which cannot interrupt a
# paragraph but otherwise runs to the next empty line like type 6.
_HTML_TAG_LINE = re.compile(
    r"^ {0,3}(?:<(?!(?:script|style|pre|textarea)\b)[A-Za-z][A-Za-z0-9-]*(?:[ \t]+[^<>]*)?/?>"
    r"|</[A-Za-z][A-Za-z0-9-]*[ \t]*>)[ \t]*$", re.IGNORECASE)
# A task item, as it would read if it were not inside HTML.
_TASK_ITEM_TEXT = re.compile(r"^ {0,3}(?:[-*+]|[0-9]{1,9}[.)])[ \t]+\[[ xX]\][ \t]+\S")


def _html_block_starts(text: str, after_paragraph: bool) -> bool:
    """Does an HTML block start here (type 6 always; type 7 only where it
    does not continue a paragraph)?"""
    return _HTML_BLOCK.match(text) is not None or (not after_paragraph and _HTML_TAG_LINE.match(text) is not None)


# A quiz callout's first line, once its containers are taken off.
_QUIZ_CALLOUT = re.compile(r"^ {0,3}\[!quiz(?:\||\])", re.IGNORECASE)

# ---- Numbers and answer lines (quizCallouts.answers) - quizRules.ts's mirror ----

_DECIMAL = re.compile(r"^([+\-−]?)([0-9]+(?:\.[0-9]*)?|\.[0-9]+)$")
_FRACTION = re.compile(r"^([+\-−]?)([0-9]+)[ \t]*/[ \t]*([0-9]+)$")
_MATH = re.compile(r"^\$([^$]+)\$$")

# JavaScript's String.prototype.trim: its whitespace and line terminators.
_JS_SPACE = ("\t\n\v\f\r          "
             "        　﻿")


def js_trim(text: str) -> str:
    """JavaScript's trim (quizRules.jsTrim), so both sides cut the same."""
    return text.strip(_JS_SPACE)


def parse_number(text: str):
    """quizRules.parseNumber: a decimal or a fraction, or None."""
    trimmed = js_trim(text)
    decimal = _DECIMAL.match(trimmed)
    if decimal:
        digits = decimal.group(2)
        magnitude = float("0" + digits if digits.startswith(".") else digits)
        return -magnitude if decimal.group(1) in ("-", "−") else magnitude
    fraction = _FRACTION.match(trimmed)
    if fraction:
        denominator = int(fraction.group(3))
        if denominator == 0:
            return None
        magnitude = int(fraction.group(2)) / denominator
        return -magnitude if fraction.group(1) in ("-", "−") else magnitude
    return None


def split_alternatives(line: str) -> list:
    """quizRules.splitAlternatives: a `|` with a space or tab (or the line's
    edge) on both sides separates; `\\|` is a plain `|`."""
    text = js_trim(line)
    pieces = []
    current = ""
    index = 0
    while index < len(text):
        character = text[index]
        if character == "\\" and text[index + 1:index + 2] == "|":
            current += "|"
            index += 2
            continue
        if character == "|":
            before = " " if index == 0 else text[index - 1]
            after = " " if index + 1 >= len(text) else text[index + 1]
            if before in (" ", "\t") and after in (" ", "\t"):
                pieces.append(current)
                current = ""
                index += 1
                continue
        current += character
        index += 1
    pieces.append(current)
    trimmed = []
    for piece in pieces:
        trimmed.append(js_trim(piece))
    return trimmed


def _classify(text: str):
    math = _MATH.match(text)
    if math:
        return {"kind": "math", "text": js_trim(math.group(1))}
    plus_minus = text.find("±")
    ascii_form = text.find("+-")
    at = -1
    width = 0
    if plus_minus >= 0 and (ascii_form < 0 or plus_minus < ascii_form):
        at, width = plus_minus, 1
    elif ascii_form >= 0:
        at, width = ascii_form, 2
    if at >= 0:
        value = parse_number(text[:at])
        if value is not None:
            tolerance = parse_number(text[at + width:])
            if tolerance is None or tolerance < 0:
                return "badTolerance"
            return {"kind": "tolerance", "value": value, "tolerance": tolerance, "text": text}
    value = parse_number(text)
    if value is not None:
        return {"kind": "number", "value": value, "text": text}
    return {"kind": "text", "text": text}


def parse_answer_line(line: str) -> dict:
    """quizRules.parseAnswerLine, for the folder check only: {"alternatives"}
    or {"problem": emptyAlternative | badTolerance}. Never used to check what
    a student typed."""
    alternatives = []
    for piece in split_alternatives(line):
        if piece == "":
            return {"problem": "emptyAlternative"}
        read = _classify(piece)
        if isinstance(read, str):
            return {"problem": read}
        alternatives.append(read)
    return {"alternatives": alternatives}


def options_of(metadata) -> list:
    """The settings after `|` in `[!quiz|...]`: split on `|` and whitespace."""
    found = []
    for piece in re.split(r"[|\s]+", metadata or ""):
        if piece:
            found.append(piece)
    return found


def verdict(model: dict) -> dict:
    """quizRules.verdict: the first problem, in the contract's order, or the
    kind. `answerLine` is the 0-based index of the answer line a problem is
    about."""
    def problem(name, fill=None, answer_line=None):
        return {"problem": name, "fill": fill or {}, "answerLine": answer_line}

    for option in model["options"]:
        if option.lower() not in OPTIONS:
            return problem("unknownOption", {"option": option})
    shuffle = False
    for option in model["options"]:
        if option.lower() == "shuffle":
            shuffle = True
    if model["boxedLists"] > 1:
        return problem("twoChoiceLists")
    if None in model["choices"]:
        return problem("choiceWithoutBox")
    if len(model["answers"]) > 1:
        return problem("twoAnswers")
    has_choices = len(model["choices"]) > 0
    has_answer = len(model["answers"]) == 1
    if has_choices and has_answer:
        return problem("choicesAndAnswer")
    if has_choices and model.get("sketchInAChoice"):
        return problem("sketchInAChoice")
    if has_choices:
        if len(model["choices"]) == 1:
            return problem("oneChoice")
        correct = []
        for index, checked in enumerate(model["choices"]):
            if checked is True:
                correct.append(index)
        if not correct:
            return problem("noCorrectChoice")
        return {"kind": "single" if len(correct) == 1 else "multiple", "shuffle": shuffle,
                "correct": correct, "answers": []}
    if has_answer:
        lines = model["answers"][0]
        if not lines:
            return problem("noAnswerLine")
        for index, line in enumerate(lines):
            parsed = parse_answer_line(line)
            if "problem" in parsed:
                return problem(parsed["problem"], {"n": index + 1}, index)
        if model["blanks"] == 0:
            if len(lines) > 1:
                return problem("oneAnswerLine", {"lines": len(lines)})
            return {"kind": "short", "shuffle": shuffle, "correct": [], "answers": list(lines)}
        if model["blanks"] != len(lines):
            return problem("blanksAndLines", {"blanks": model["blanks"], "lines": len(lines)})
        return {"kind": "fill", "shuffle": shuffle, "correct": [], "answers": list(lines)}
    if model.get("htmlChoices"):
        return problem("choicesInHtml")
    return problem("nothingToCheck")


# ---- Reading a page (quizCallouts.recognise) ---------------------------------------

def _readable_lines(text: str) -> list:
    """The page as the site reads it, line by line: line endings made LF
    (a CR LF or a lone CR is one ending), every `%%` comment taken out the
    way ObsidianFlavoredMarkdown takes it out - before anything else, code
    included - and each line paired with its 1-based line in `text` as
    given."""
    unified = text.replace("\r\n", "\n").replace("\r", "\n")
    # Offsets in `unified` back to lines in `text`: a CR LF counts once in
    # both, so the line numbers agree.
    stripped, origin = markdown_code._without_comments(unified)
    newlines = []
    for index, character in enumerate(unified):
        if character == "\n":
            newlines.append(index)
    lines = []
    start = 0
    while True:
        end = stripped.find("\n", start)
        piece = stripped[start:] if end < 0 else stripped[start:end]
        where = start if origin is None else origin[start]
        lines.append((piece, bisect.bisect_left(newlines, where) + 1))
        if end < 0:
            break
        start = end + 1
    return lines


def _leading(line: str, at: int):
    """Columns of leading spaces and tabs from `at`, and where they end."""
    columns = 0
    index = at
    while index < len(line) and line[index] in " \t":
        columns += 4 - (columns % 4) if line[index] == "\t" else 1
        index += 1
    return columns, index


def _containers(line: str, base: int = 0, lists: bool = False):
    """quizRules.containersOf: each `>` (and, with `lists`, each list marker)
    opens a container only at most three columns past where the container
    around it starts its content (`base` for the page itself: the content
    column of the list item the line belongs to). A `>` further in is the
    text of indented code or of a paragraph (the implementation review's
    S1). Answers (depth, body, whether a list marker was passed)."""
    at = 0
    depth = 0
    allowed = base
    listed = False
    while True:
        columns, index = _leading(line, at)
        if columns - allowed > 3 or index >= len(line):
            break
        if line[index] == ">":
            depth += 1
            at = index + 1
            if at < len(line) and line[at] in " \t":
                at += 1
            allowed = 0
            continue
        marker = _LIST_OPENER.match(line[index:]) if lists else None
        if marker is not None:
            listed = True
            at = index + marker.end()
            allowed = 0
            continue
        break
    return depth, line[at:], listed


def _depth_and_body(line: str, base: int = 0):
    depth, body, _ = _containers(line, base)
    return depth, body


def _quiz_start_anywhere(line: str, base: int = 0) -> bool:
    """A quiz callout's first line behind at least one `>`, wherever it is."""
    depth, body, _ = _containers(line, base, lists=True)
    return depth >= 1 and _QUIZ_CALLOUT.match(body) is not None


def _is_blank(text: str) -> bool:
    return text.strip(" \t") == ""


def _indent(text: str) -> int:
    count = 0
    for character in text:
        if character == " ":
            count += 1
        elif character == "\t":
            count += 4 - (count % 4)
        else:
            break
    return count


def _strip_one_marker(line: str):
    """The line without one quote marker, or None when it has none."""
    marker = _ONE_MARKER.match(line)
    if marker is None:
        return None
    return line[marker.end():]


def _fence_closes(body: str, fence) -> bool:
    """Does `body` close a fence of (character, length)?"""
    stripped = body.strip(" \t")
    run = len(stripped) - len(stripped.lstrip(fence[0]))
    return run >= fence[1] and stripped[:run] == fence[0] * run and stripped[run:].strip(" \t") == ""


def _fence_opens(body: str, base: int = 0):
    columns, index = _leading(body, 0)
    if columns - base > 3:
        return None
    match = _FENCE_OPEN.match(body[index:])
    if match is None:
        return None
    run = match.group(1)
    if run[0] == "`" and "`" in match.group(2):
        return None
    return (run[0], len(run))


def _fence_language(body: str) -> str:
    """The first word of a fence opener's info string (what the site's
    parser calls the code's `lang`), or "" - for a sketch in a choice
    (#578 stage 5: geogebra.LANGUAGE)."""
    _columns, index = _leading(body, 0)
    match = _FENCE_OPEN.match(body[index:])
    if match is None:
        return ""
    words = match.group(2).split()
    return words[0] if words else ""


# A ```geogebra fence's language (geogebra.LANGUAGE; not imported, so this
# file stays free of the sketches' own module).
SKETCH_LANGUAGE = "geogebra"


def _code_spans(text: str) -> list:
    """The contents of every code span in one paragraph's text."""
    ranges = []
    markdown_code._spans_in_paragraph(text, 0, len(text), ranges)
    contents = []
    for start, end in ranges:
        run = 0
        while start + run < end and text[start + run] == "`":
            run += 1
        contents.append(text[start + run:end - run])
    return contents


def is_blank_span(raw: str) -> bool:
    """A blank: a code span holding only three or more underscores, after
    CommonMark takes one space off each end of a span that has both."""
    text = raw.replace("\n", " ")
    if len(text) >= 2 and text.startswith(" ") and text.endswith(" ") and text.strip(" ") != "":
        text = text[1:-1]
    return re.fullmatch(r"_{3,}", text) is not None


def _blanks_in(paragraph: str) -> int:
    count = 0
    for content in _code_spans(paragraph):
        if is_blank_span(content):
            count += 1
    return count


def _read_quiz(entries: list, title: str, metadata) -> dict:
    """One top-level quiz's inner lines (one quote marker off, lazy lines as
    they are), after its title line: the model quizRules.verdict reads, plus
    where each answer line is, and how many quizzes sit inside it."""
    state = {
        "boxedLists": 0, "choices": [], "listKind": None, "listContent": 0,
        "listHasBox": False, "listItems": [], "stem": [], "blanks": _blanks_in(title),
        "listHasSketch": False, "sketchInAChoice": False,
    }
    answers = []
    answer_lines_at = []
    nested_quizzes = []

    def close_list():
        if state["listKind"] is not None and state["listHasBox"]:
            state["boxedLists"] += 1
            if state["boxedLists"] == 1:
                state["choices"] = list(state["listItems"])
                state["sketchInAChoice"] = state["listHasSketch"]
        state["listKind"] = None
        state["listHasBox"] = False
        state["listItems"] = []
        state["listHasSketch"] = False

    def close_stem():
        if state["stem"]:
            state["blanks"] += _blanks_in("\n".join(state["stem"]))
        state["stem"] = []

    fence = None
    quoted_fence = None
    previous_blank = True
    previous_paragraph = False
    index = 0
    while index < len(entries):
        inner, file_line, lazy = entries[index]
        indent = _indent(inner)
        base = state["listContent"] if state["listKind"] is not None and indent >= state["listContent"] else 0
        depth, body = _depth_and_body(inner, base)
        if fence is not None:
            if depth < fence[1]:
                fence = None
            else:
                if _fence_closes(body, fence[0]):
                    fence = None
                index += 1
                previous_blank = False
                previous_paragraph = False
                continue
        if _quiz_start_anywhere(inner, base):
            nested_quizzes.append(file_line)
        if _is_blank(inner):
            close_stem()
            previous_blank = True
            previous_paragraph = False
            index += 1
            continue
        in_item = state["listKind"] is not None and indent >= state["listContent"]
        if depth == 0 and not lazy and not previous_paragraph and _indent(body) - base >= 4:
            # Indented code: never a choice, a callout, a fence or a blank.
            close_stem()
            previous_blank = False
            index += 1
            continue

        if depth >= 1 and not in_item and not lazy:
            # A blockquote inside the quiz, at the quiz's own level: when its
            # first line is `[!answer]` or `[!explain]`, that callout. It runs
            # over the lines that carry its marker, and the lazy lines that
            # continue one of its paragraphs.
            close_stem()
            close_list()
            first = _strip_one_marker(inner)
            callout = None
            if depth == 1 and first is not None:
                callout = _CALLOUT.match(first.lstrip(" \t"))
            kind = callout.group(1).lower() if callout else None
            lines_here = []
            index += 1
            # The title line is a paragraph of its own (the site gives it an
            # empty line after it), so nothing continues it lazily.
            previous_inner_paragraph = callout is None
            while index < len(entries):
                next_inner, next_line, next_lazy = entries[index]
                next_depth, _ = _depth_and_body(next_inner)
                if _is_blank(next_inner):
                    break
                if next_depth >= 1:
                    content = _strip_one_marker(next_inner)
                    if content is None:
                        content = next_inner
                    previous_inner_paragraph = not _is_blank(content)
                    lines_here.append((content, next_line))
                elif previous_inner_paragraph and not _BLOCK_START.match(next_inner):
                    lines_here.append((next_inner, next_line))
                else:
                    break
                if _quiz_start_anywhere(next_inner):
                    nested_quizzes.append(next_line)
                index += 1
            if kind == "answer":
                kept = []
                kept_at = []
                for content, line_number in lines_here:
                    text = js_trim(content)
                    if text != "":
                        kept.append(text)
                        kept_at.append(line_number)
                answers.append(kept)
                answer_lines_at.append(kept_at)
            previous_blank = False
            previous_paragraph = False
            continue

        if depth == 0 and not lazy and not in_item and _html_block_starts(inner, previous_paragraph):
            # An HTML block: everything to the next empty line is HTML - a
            # list of choices in it included, which the quiz then says.
            close_stem()
            close_list()
            while index < len(entries) and not _is_blank(entries[index][0]):
                if _TASK_ITEM_TEXT.match(entries[index][0]):
                    state["htmlChoices"] = True
                index += 1
            previous_blank = False
            previous_paragraph = False
            continue

        item = _LIST_ITEM.match(inner) if depth == 0 and not lazy and not in_item else None
        if item is not None:
            close_stem()
            marker = item.group(2)
            kind = marker if marker in "-*+" else marker[-1]
            if state["listKind"] is not None and kind != state["listKind"]:
                close_list()
            if state["listKind"] is None:
                state["listKind"] = kind
            spaces = item.group(3)
            gap = len(spaces) if 1 <= len(spaces) <= 4 else 1
            state["listContent"] = len(item.group(1)) + len(marker) + gap
            text = item.group(4)
            box = _TASK_BOX.match(text)
            if box is not None:
                state["listHasBox"] = True
                state["listItems"].append(box.group(1) in ("x", "X"))
            else:
                state["listItems"].append(None)
            opened = _fence_opens(text)
            if opened is not None:
                fence = (opened, 0)
                if _fence_language(text) == SKETCH_LANGUAGE:
                    state["listHasSketch"] = True
            previous_blank = False
            previous_paragraph = opened is None
            index += 1
            continue

        opened = _fence_opens(body, base) if depth == 0 and not lazy else None
        if opened is not None:
            close_stem()
            if not in_item:
                close_list()
            elif _fence_language(body) == SKETCH_LANGUAGE:
                # A GeoGebra sketch inside a choice (#578 stage 5): refused
                # if this list turns out to be the quiz's choices.
                state["listHasSketch"] = True
            fence = (opened, 0)
            previous_blank = False
            previous_paragraph = False
            index += 1
            continue

        lazy_in_item = (state["listKind"] is not None and not previous_blank and previous_paragraph
                        and not _BLOCK_START.match(inner))
        if in_item and depth >= 1:
            # A blockquote or callout inside a choice: a GeoGebra sketch in it
            # is still a sketch in that choice (#578 stage 6; the site finds
            # it anywhere under the item). Its own fences are followed so a
            # ```geogebra line quoted inside another fence is not one.
            if quoted_fence is not None:
                if _fence_closes(body, quoted_fence):
                    quoted_fence = None
            else:
                quoted_fence = _fence_opens(body)
                if quoted_fence is not None and _fence_language(body) == SKETCH_LANGUAGE:
                    state["listHasSketch"] = True
        else:
            quoted_fence = None
        if in_item or lazy_in_item:
            # Inside a choice, or a lazy line continuing one.
            previous_blank = False
            previous_paragraph = not _BLOCK_START.match(inner.lstrip(" \t"))
            index += 1
            continue

        close_list()
        if _NOT_STEM_TEXT.match(inner):
            close_stem()
            previous_paragraph = False
        else:
            state["stem"].append(inner)
            previous_paragraph = True
        previous_blank = False
        index += 1
    close_stem()
    close_list()
    return {
        "model": {
            "options": options_of(metadata),
            "boxedLists": state["boxedLists"],
            "choices": state["choices"],
            "answers": answers,
            "blanks": state["blanks"],
            "htmlChoices": state.get("htmlChoices", False),
            "sketchInAChoice": state["sketchInAChoice"],
        },
        "answerLinesAt": answer_lines_at,
        "nestedQuizzes": nested_quizzes,
    }


def quizzes_on_page(text: str) -> list:
    """
    Every quiz on one page's raw text, in order:
    {"n": 1, 2, ... for a top-level quiz, None for one that is not;
     "nested": the ordinal among quizzes that are not at the top level, or
     None; "line": the quiz's first line in `text`; "title": its title,
     trimmed; then "kind" (single | multiple | short | fill) with "correct",
     "answers" and "shuffle", or "problem" with "fill" and "problemLine"
     (the line the problem is on: the answer line for a problem with one
     answer, else the quiz's first line)}.

    A top-level quiz (quizCallouts.recognise.topLevel) is a blockquote that
    starts at the page's left edge - outside any list, fence or other
    blockquote - whose first line, after one `>`, is `[!quiz]`, `[!quiz|...]`,
    `[!quiz]-` or `[!quiz]+` (any case). It runs while lines carry `>` and
    over lazy lines that continue a paragraph; an empty line ends it.
    """
    lines = _readable_lines(text)
    found = []
    top = 0
    nested = 0

    def add_nested(line_number):
        nonlocal nested
        nested += 1
        found.append({"n": None, "nested": nested, "line": line_number, "title": "",
                      "problem": "notAtTopLevel", "fill": {}, "problemLine": line_number})

    fence = None
    list_content = None
    previous_blank = True
    previous_quote = False
    previous_paragraph = False
    index = 0
    while index < len(lines):
        line, file_line = lines[index]
        line_indent = _indent(line)
        base = list_content if list_content is not None and line_indent >= list_content else 0
        depth, body = _depth_and_body(line, base)
        if fence is not None:
            if depth < fence[1]:
                fence = None
            else:
                if _fence_closes(body, fence[0]):
                    fence = None
                index += 1
                previous_blank = False
                previous_paragraph = False
                continue
        if _is_blank(line):
            previous_blank = True
            previous_quote = False
            previous_paragraph = False
            index += 1
            continue
        indent = _indent(line)
        block_start = depth > 0 or _BLOCK_START.match(line) is not None
        if list_content is not None and indent < list_content and (previous_blank or block_start):
            list_content = None
        if list_content is None and depth == 0 and indent >= 4 and not previous_paragraph:
            # Indented code: never a quiz.
            previous_blank = False
            previous_quote = False
            index += 1
            continue
        if depth == 0 and previous_quote and previous_paragraph and not block_start:
            # A lazy line continuing a paragraph in the blockquote above.
            index += 1
            continue
        item = _LIST_ITEM.match(line) if depth == 0 else None
        if item is not None and (list_content is None or indent < list_content):
            spaces = item.group(3)
            gap = len(spaces) if 1 <= len(spaces) <= 4 else 1
            list_content = len(item.group(1)) + len(item.group(2)) + gap
        if depth == 0 and list_content is None and _html_block_starts(line, previous_paragraph):
            # An HTML block at the page's level: to the next empty line,
            # whatever it holds - quiz syntax included - is HTML.
            while index < len(lines) and not _is_blank(lines[index][0]):
                index += 1
            previous_blank = False
            previous_quote = False
            previous_paragraph = False
            continue
        if not previous_paragraph and _indent(body) - (base if depth == 0 else 0) >= 4:
            # Indented code, at the page's level, in a quote or under a list
            # item: never a quiz, a callout or a fence.
            previous_blank = False
            previous_quote = depth > 0
            index += 1
            continue
        opened = _fence_opens(body, base if depth == 0 else 0)
        if opened is not None:
            fence = (opened, depth)
            previous_blank = False
            previous_quote = depth > 0
            previous_paragraph = False
            index += 1
            continue

        first = _strip_one_marker(line)
        start = None
        if depth >= 1 and first is not None and not previous_quote and list_content is None:
            if _depth_and_body(first)[0] == 0:
                callout = _CALLOUT.match(first.lstrip(" \t"))
                if callout is not None and callout.group(1).lower() == "quiz":
                    start = callout
        if start is not None:
            top += 1
            entries = []
            index += 1
            inner_paragraph = False
            while index < len(lines):
                next_line, next_file_line = lines[index]
                if _is_blank(next_line):
                    break
                inner = _strip_one_marker(next_line)
                if inner is not None:
                    entries.append((inner, next_file_line, False))
                    inner_depth, inner_body = _depth_and_body(inner)
                    inner_paragraph = (not _is_blank(inner_body)
                                       and not _BLOCK_START.match(inner_body.lstrip(" \t"))
                                       and not _NOT_STEM_TEXT.match(inner_body))
                    if _LIST_ITEM.match(inner_body) and not _fence_opens(inner_body):
                        inner_paragraph = True
                elif inner_paragraph and not _BLOCK_START.match(next_line):
                    entries.append((next_line, next_file_line, True))
                else:
                    break
                index += 1
            read = _read_quiz(entries, start.group(4), start.group(2))
            result = verdict(read["model"])
            quiz = {"n": top, "nested": None, "line": file_line, "title": js_trim(start.group(4))}
            if "problem" in result:
                quiz["problem"] = result["problem"]
                quiz["fill"] = result["fill"]
                quiz["problemLine"] = file_line
                if result["answerLine"] is not None and read["answerLinesAt"]:
                    quiz["problemLine"] = read["answerLinesAt"][0][result["answerLine"]]
            else:
                quiz["kind"] = result["kind"]
                quiz["correct"] = result["correct"]
                quiz["answers"] = result["answers"]
                quiz["shuffle"] = result["shuffle"]
            found.append(quiz)
            for line_number in read["nestedQuizzes"]:
                add_nested(line_number)
            previous_blank = False
            previous_quote = False
            previous_paragraph = False
            continue

        if _quiz_start_anywhere(line, base):
            add_nested(file_line)
        previous_blank = False
        previous_quote = depth > 0
        previous_paragraph = not _BLOCK_START.match(body.lstrip(" \t")) and not _is_blank(body)
        index += 1
    return found


# ---- Lines in the teacher's own file ------------------------------------------------

def place_in_source(build_quizzes: list, source_text) -> list:
    """
    The same quizzes with "line" and "problemLine" moved into the TEACHER's
    file: each quiz is matched to the one in the source with the same title,
    counting equal titles in order (quizCallouts.lines), and a problem's line
    keeps its distance from the quiz's first line. A quiz that cannot be
    matched loses its lines (quizLineNoLine).
    """
    source = quizzes_on_page(source_text) if source_text is not None else None
    placed = []
    seen = {}
    for quiz in build_quizzes:
        moved = dict(quiz)
        key = ("top" if quiz["n"] is not None else "nested", quiz["title"])
        seen[key] = seen.get(key, 0) + 1
        match = None
        if source is not None:
            count = 0
            for candidate in source:
                candidate_key = ("top" if candidate["n"] is not None else "nested", candidate["title"])
                if candidate_key == key:
                    count += 1
                    if count == seen[key]:
                        match = candidate
                        break
        if match is None:
            moved["line"] = None
            moved["problemLine"] = None
        else:
            offset = (quiz.get("problemLine") or quiz["line"]) - quiz["line"]
            moved["line"] = match["line"]
            moved["problemLine"] = match["line"] + offset
        placed.append(moved)
    return placed


# ---- What a teacher and an assistant read ----------------------------------------------

def rules() -> dict:
    return contracts.section("shared-rules", "quizCallouts")


def reason(problem: dict, words: dict) -> str:
    """The reason in quizCallouts.words.problems, filled in one pass."""
    import site_health
    text = words.get(problem["problem"]) or words.get("nothingToCheck", "")
    fill = {}
    for key, value in (problem.get("fill") or {}).items():
        fill[key] = value
    return site_health.filled(text, fill)


def error_line(page: str, problem: dict, words: dict) -> str:
    """`plantoir: error: Units/Practice.md: quiz 3, line 41: <reason>` -
    `quiz <n>` for a top-level quiz, the line in the teacher's file when it is
    known."""
    where = f"{page}.md"
    if problem.get("n") is not None:
        where += f": quiz {problem['n']}"
        if problem.get("problemLine") is not None:
            where += f", line {problem['problemLine']}"
    elif problem.get("problemLine") is not None:
        where += f": line {problem['problemLine']}"
    return f"plantoir: error: {where}: {reason(problem, words)}"


def check_pages(pages: list, printer=print) -> dict:
    """
    The whole folder check over the pages students can see
    (figures.pages_students_see with must_contain="[!"): one `plantoir:
    error:` line per quiz that cannot be checked, and what the site's
    safety net and the `quizzesNotReady` finding need - and (#644) `places`,
    each examined page's place in the course folder by its path in the
    site's content, so the site's emitter can name a page the safety net
    prints a line for without reading every page again. Never raises for one
    page: a page that cannot be read is left out, as the site leaves it.
    """
    words = rules()["words"]["problems"]
    problems = []
    examined = []
    by_page = {}
    places = {}
    for page in pages:
        place = page["place"]
        examined.append(page["path"])
        places[page["path"]] = place
        quizzes = quizzes_on_page(page["text"])
        if not quizzes:
            continue
        placed = place_in_source(quizzes, page.get("source"))
        top = 0
        nested = 0
        reported_top = []
        reported_nested = []
        lines = []
        nested_lines = []
        for quiz in placed:
            if quiz["n"] is not None:
                top += 1
                lines.append(quiz["line"])
            else:
                nested += 1
                nested_lines.append(quiz["line"])
            if "problem" not in quiz:
                continue
            if quiz["n"] is not None:
                reported_top.append(quiz["n"])
            else:
                reported_nested.append(quiz["nested"])
            printer(error_line(place, quiz, words))
            problems.append({
                "page": place,
                "n": quiz["n"],
                "line": quiz["problemLine"],
                "reason": quiz["problem"],
                "fill": quiz.get("fill") or {},
            })
        by_page[page["path"]] = {"quizzes": top, "problems": reported_top,
                                 "nested": nested, "nestedProblems": reported_nested,
                                 "lines": lines, "nestedLines": nested_lines}
    return {"problems": problems, "examined": sorted(examined), "pages": by_page, "places": places}


def _write_if_changed(path: Path, content) -> bool:
    data = (json.dumps(content, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def quiz_words() -> dict:
    """What quartz/plantoir_quiz.json carries: the words a student reads and
    the reasons a teacher and an assistant read (quizCallouts.words)."""
    words = rules()["words"]
    site = {}
    for key, text in words["site"].items():
        if key != "note":
            site[key] = text
    problems = {}
    for key, text in words["problems"].items():
        if key != "note":
            problems[key] = text
    return {"words": site, "problems": problems}


def write_quiz_files(output_dir, checked=None) -> bool:
    """
    Write quartz/plantoir_quiz.json (the words) and
    quartz/plantoir_quiz_pages.json (what the check examined and found), on
    every build, the same bytes for the same input. Answers whether either
    changed. If the contract cannot be read, the words file is empty and the
    site renders every quiz as not ready rather than with its answers on
    show.
    """
    quartz = Path(output_dir) / "quartz"
    try:
        content = quiz_words()
    except Exception as error:  # a stale contract must not stop a build
        print(f"⚠️ Could not read the words for the self-check questions: {error}")
        content = {"words": {}, "problems": {}}
    pages = {"examined": [], "pages": {}}
    if checked is not None:
        pages = {"examined": checked["examined"], "pages": checked["pages"]}
    changed = _write_if_changed(quartz / WORDS_FILE, content)
    return _write_if_changed(quartz / PAGES_FILE, pages) or changed
