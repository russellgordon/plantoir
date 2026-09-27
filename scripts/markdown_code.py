#!/usr/bin/env python3
"""
Where a page's CODE is, so that a link written inside code is not read as a
link (#313).

A `[[...]]` or `![[...]]` whose opening brackets sit inside a fenced code
block or an inline code span is an EXAMPLE of a link - the Scavenger Hunt
pages teach the syntax that way - and Quartz v4.5.0 never draws one: its
`ofm.ts` builds links with `mdast-util-find-and-replace` over text nodes only,
so `code` and `inlineCode` are never searched. Every reader and rewriter in
the toolchain asks this module, and nothing else, where code is:

- `build_site._extract_wikilink_targets` (the dating walk),
  `_pages_the_course_teaches` and `_coverage_counts` (the coverage map);
- `setup_course.first_use_dates`, `retargeted_expectation_references` and
  `unlink_curriculum_references` (the installer);
- the example-content linter.

The rule is written down, to be implemented from, in
`contracts/shared-rules.json` -> `readingALink.whatIsCode`, with its limits in
`whatIsCodeLimits` and its cases in `readingALink.cases`. The mac implements
the same rule once, in `MarkdownCode.swift`; the Windows app is owed it. In
short:

1. A fence opens on a line whose body (blockquote markers taken off, then
   leading spaces and tabs) starts with three or more backticks or tildes -
   unless it is backticks with another backtick later on the line, which is
   inline code. It belongs to its opener's quote DEPTH: it closes on a line at
   that depth holding a run of the SAME character at least as long, with
   nothing but whitespace after it, and a line at a smaller depth ends it (a
   fence in a callout ends with the callout). Unclosed, it runs to the end.
2. Paragraphs - for spans only - break at blank lines, fences, a deeper quote,
   and lines that begin a list item, a heading or a table row or are a rule
   line (--- *** ___ ===, frontmatter's --- among them); a heading is a
   paragraph on its own.
3. Within a paragraph a run of N backticks opens a span that closes at the
   next run of EXACTLY N; a run never matched is plain text; outside a span a
   backslash escapes the next character; inside, backslashes are literal.
4. Nothing else is code: not indented code, not HTML <code>, not math, not
   %% comments (#331).

Rejected: a real Markdown parser. It would judge the edges better, but the
Swift app and the C# app cannot share it, and three readers that disagree at
exactly the edges the contract pins is what #313 was filed to end. The
measurement used one (remark, Quartz's own) to JUDGE this rule: over the
39,570 links in support/ they disagree on 0 once TEJ2O's broken fence is
fixed.

Offsets are code points, which is what `re` match positions are. Every
character the rule looks at is ASCII.
"""
import bisect
import re

# Blockquote markers in front of a line: spaces or tabs, '>', repeated, and
# one optional space after the last.
_QUOTE_MARKERS = re.compile(r"^(?:[ \t]*>)+ ?")
# A fence line, on a line's body: the run, and whatever follows it.
_FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")
# The block starts that end a paragraph (so a code span cannot reach past
# them): a list marker, a heading, a table row, and a line of three or more
# of one of - * _ = (a thematic break, a setext underline, the --- around
# frontmatter).
_BLOCK_START = re.compile(
    r"^[ \t]*(?:[-*+](?:[ \t]|$)|[0-9]{1,9}[.)](?:[ \t]|$)|#{1,6}(?:[ \t]|$)|\|"
    r"|(?:-[ \t]*){3,}$|(?:\*[ \t]*){3,}$|(?:_[ \t]*){3,}$|(?:=[ \t]*){3,}$)")
# A heading is one line: the line after it begins a new paragraph.
_HEADING = re.compile(r"^[ \t]*#{1,6}(?:[ \t]|$)")
# Whitespace, for the rule: ASCII only, so every language agrees.
_WHITESPACE = " \t\r\f\v"


def _quote_depth_and_body(line: str):
    """How many blockquote markers open the line, and the line after them."""
    markers = _QUOTE_MARKERS.match(line)
    if markers is None:
        return 0, line
    return markers.group(0).count(">"), line[markers.end():]


def _is_blank(text: str) -> bool:
    return text.strip(_WHITESPACE) == ""


def _spans_in_paragraph(text: str, start: int, end: int, ranges: list) -> None:
    """Inline code spans in text[start:end], appended to `ranges`."""
    position = start
    while position < end:
        character = text[position]
        if character == "\\" and position + 1 < end:
            position += 2
            continue
        if character != "`":
            position += 1
            continue
        run_end = position
        while run_end < end and text[run_end] == "`":
            run_end += 1
        run_length = run_end - position
        closing_end = -1
        scan = run_end
        while scan < end:
            if text[scan] != "`":
                scan += 1
                continue
            other_end = scan
            while other_end < end and text[other_end] == "`":
                other_end += 1
            if other_end - scan == run_length:
                closing_end = other_end
                break
            scan = other_end
        if closing_end < 0:
            # Never closed: the run is plain text, and so is what follows it.
            position = run_end
            continue
        ranges.append((position, closing_end))
        position = closing_end


def code_ranges(text: str) -> list:
    """
    Every stretch of `text` that is code, as sorted, non-overlapping
    (start, end) pairs of code-point offsets, end exclusive.
    """
    ranges = []
    fence_character = None
    fence_length = 0
    fence_depth = 0
    paragraph_start = -1
    paragraph_end = -1
    paragraph_depth = 0

    def close_paragraph():
        nonlocal paragraph_start, paragraph_end
        if paragraph_start >= 0:
            _spans_in_paragraph(text, paragraph_start, paragraph_end, ranges)
        paragraph_start = -1
        paragraph_end = -1

    line_start = 0
    length = len(text)
    while line_start <= length:
        newline = text.find("\n", line_start)
        line_end = length if newline < 0 else newline
        next_start = line_end + 1
        line = text[line_start:line_end]
        if line.endswith("\r"):
            line = line[:-1]
        depth, body = _quote_depth_and_body(line)

        if fence_character is not None and depth < fence_depth:
            # A fence opened inside a callout ends with the callout: a line
            # with fewer > markers is outside both, and is read as such.
            fence_character = None

        if fence_character is not None:
            ranges.append((line_start, min(next_start, length)))
            fence = _FENCE.match(body)
            if depth == fence_depth and fence and fence.group(1)[0] == fence_character \
                    and len(fence.group(1)) >= fence_length \
                    and _is_blank(fence.group(2)):
                fence_character = None
        else:
            fence = _FENCE.match(body)
            if fence and not (fence.group(1)[0] == "`" and "`" in fence.group(2)):
                close_paragraph()
                fence_character = fence.group(1)[0]
                fence_length = len(fence.group(1))
                fence_depth = depth
                ranges.append((line_start, min(next_start, length)))
            elif _is_blank(body):
                close_paragraph()
            else:
                if _BLOCK_START.match(body) or (paragraph_start >= 0 and depth > paragraph_depth):
                    close_paragraph()
                if paragraph_start < 0:
                    paragraph_start = line_start
                    # Compared with the paragraph's FIRST line: an unquoted
                    # line inside a callout paragraph is a lazy continuation
                    # and does not lower it.
                    paragraph_depth = depth
                paragraph_end = line_end
                if _HEADING.match(body):
                    close_paragraph()

        if newline < 0:
            break
        line_start = next_start
    close_paragraph()

    ranges.sort()
    merged = []
    for start, end in ranges:
        if start >= end:
            continue
        if merged and start <= merged[-1][1]:
            if end > merged[-1][1]:
                merged[-1] = (merged[-1][0], end)
            continue
        merged.append((start, end))
    return merged


def _range_holding(ranges: list, position: int):
    """The (start, end) in `ranges` that holds `position`, or None."""
    index = bisect.bisect_right(ranges, (position, float("inf"))) - 1
    if index < 0:
        return None
    start, end = ranges[index]
    if start <= position < end:
        return (start, end)
    return None


def is_in_code(ranges: list, position: int) -> bool:
    """Whether `position` falls inside one of `ranges` (from `code_ranges`)."""
    return _range_holding(ranges, position) is not None


def matches_outside_code(pattern, text: str, ranges: list = None, offset: int = 0):
    """
    The matches of `pattern` in `text` that do not START inside code - the
    one mask every link reader applies (readingALink.whatIsCode, rule 5).

    A match that starts in code is not merely dropped: the search starts
    again where that code ENDS. Dropping it alone would lose the real link
    after an example: in "Type `[[` to start one: [[Real Page]]" the pattern,
    which crosses a `[`, matches from the example's brackets to "Real Page",
    and the real link would never be seen (readingALink.cases, "a stray [[
    inside code does not swallow the link after it"). Quartz never searches
    code at all, so it draws that link.

    The text itself is never changed, so a rewriter can use the offsets.
    `offset` is where `text` sits in the page `ranges` was taken over, for a
    reader that works one line at a time.
    """
    if ranges is None:
        ranges = code_ranges(text)
    found = []
    position = 0
    length = len(text)
    while position <= length:
        match = pattern.search(text, position)
        if match is None:
            break
        holding = _range_holding(ranges, offset + match.start())
        if holding is not None:
            position = holding[1] - offset
            continue
        found.append(match)
        position = match.end() if match.end() > match.start() else match.start() + 1
    return found
