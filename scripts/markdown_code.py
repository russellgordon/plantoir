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
4. Nothing else is code: not indented code, not HTML <code>, not math, and
   not %% comments - those are masked separately, FIRST (#331, below).

A comment is never a link either (#331; `readingALink.whatIsAComment`).
Quartz v4.5.0 removes every `%%...%%` from the RAW page before it parses
anything (`ofm.ts:130`, `:160-163`): lazy, left to right, across lines, code
or not, and a `%%` with no partner is plain text. So this module does the
same, in the same order: `comment_ranges` finds the comments on the page as
written, and `code_ranges` finds code in the page WITH EVERY COMMENT REMOVED,
mapping the ranges back to the page's own offsets. `not_a_link_ranges` is the
two merged, and it is what every link reader and rewriter masks with.

`code_ranges` still returns CODE ONLY, and that is load-bearing: the
curriculum markers `%%curriculum-start%%` / `%%curriculum-end%%` ARE
comments, and `build_site._curriculum_blocks_outside_code` asks whether a
marker is in code. Folding comments into `code_ranges` would skip every
block and empty every coverage map while the build stayed green.

Rejected: finding code on the page as written (simpler). Checked against
Quartz's order it gets two contract cases wrong - "a fence opened inside a
comment is not a fence" and "a backtick inside a comment does not pair with
code after it" - though both agree with Quartz over all 39,570 shipped links.

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


def comment_ranges(text: str) -> list:
    """
    Every `%%...%%` comment on the page as written, as sorted (start, end)
    pairs of code-point offsets, end exclusive, both `%%` included. Scanned
    left to right: a `%%` opens a comment that closes at the next `%%`, across
    lines and whether or not either sits in code; a last `%%` with no partner
    is text. Quartz's lazy comment pattern, applied before anything else.
    """
    found = []
    position = 0
    while True:
        start = text.find("%%", position)
        if start < 0:
            break
        end = text.find("%%", start + 2)
        if end < 0:
            break
        found.append((start, end + 2))
        position = end + 2
    return found


def code_ranges(text: str) -> list:
    """
    Every stretch of `text` that is code, as sorted, non-overlapping
    (start, end) pairs of code-point offsets, end exclusive.

    Code is found in the page with its comments removed (Quartz's order,
    #331) and mapped back to the page's own offsets. The stripped text never
    leaves this function: nothing may write it back. Comments are NOT in the
    result - see the module docstring for why that matters.
    """
    comments = comment_ranges(text)
    if not comments:
        return _code_ranges_as_written(text)
    kept_pieces = []
    origin = []
    last = 0
    for start, end in comments:
        kept_pieces.append(text[last:start])
        origin.extend(range(last, start))
        last = end
    kept_pieces.append(text[last:])
    origin.extend(range(last, len(text)))
    origin.append(len(text))
    mapped = []
    for start, end in _code_ranges_as_written("".join(kept_pieces)):
        mapped.append((origin[start], origin[end - 1] + 1))
    return mapped


def not_a_link_ranges(text: str) -> list:
    """
    Code and comments together, sorted and merged: every stretch of `text` in
    which a `[[` (or the `!` of `![[`) does not start a link.
    """
    both = sorted(code_ranges(text) + comment_ranges(text))
    merged = []
    for start, end in both:
        if merged and start <= merged[-1][1]:
            if end > merged[-1][1]:
                merged[-1] = (merged[-1][0], end)
            continue
        merged.append((start, end))
    return merged


def _code_ranges_as_written(text: str) -> list:
    """The #313 rule over `text` exactly as given (no comment removal)."""
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
    """Whether `position` falls inside one of `ranges` (from `code_ranges`
    or `not_a_link_ranges`)."""
    return _range_holding(ranges, position) is not None


def matches_outside_code(pattern, text: str, ranges: list = None, offset: int = 0):
    """
    The matches of `pattern` in `text` that do not START inside code or a
    `%%` comment - the one mask every link reader applies
    (readingALink.whatIsCode, rule 5, and whatIsAComment). The name is kept
    for its callers; the default mask is `not_a_link_ranges` since #331.

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
        ranges = not_a_link_ranges(text)
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


# ---- Fenced blocks, read whole (#485 E1) -----------------------------------
#
# The figure fences (```tikz, ```functionplot) are found with the SAME fence
# rule as above - in callouts at any depth, in list items, with backticks or
# tildes - over the page with its `%%` comments removed first, as Quartz
# removes them (#455 plan, finding F): a fence inside a comment is gone, and a
# `%%` inside a fence eats what Quartz eats. What this adds is the block's
# CONTENT, which the masks above never needed.

# A list item's marker and the spaces after it, on the line a fence opens on.
_LIST_MARKER = re.compile(r"^[ \t]*(?:[-*+]|[0-9]{1,9}[.)])[ \t]+")


def _column(prefix: str) -> int:
    """The column `prefix` ends at, a tab moving to the next multiple of 4 -
    CommonMark's tab stop. Obsidian indents list items with TABS by default
    (E1 fix review F1)."""
    column = 0
    for character in prefix:
        column = column + 4 - column % 4 if character == "\t" else column + 1
    return column


def _without_indent(line: str, columns: int) -> str:
    """`line` with leading spaces and tabs taken off up to `columns` columns
    (tabs counted to the next multiple of 4), as a fence's content loses its
    opener's indent. A tab reaching past the column is taken off whole."""
    column = 0
    position = 0
    while position < len(line) and column < columns and line[position] in " \t":
        column = column + 4 - column % 4 if line[position] == "\t" else column + 1
        position += 1
    return line[position:]


def _strip_quote_markers(line: str, depth: int) -> str:
    """`line` with its first `depth` blockquote markers (and the one space
    after each) taken off, the way CommonMark reads a line inside a fence
    that sits in a quote: a deeper `>` is the code's own text."""
    position = 0
    for _ in range(depth):
        scan = position
        while scan < len(line) and line[scan] in " \t":
            scan += 1
        if scan >= len(line) or line[scan] != ">":
            break
        position = scan + 1
        if position < len(line) and line[position] == " ":
            position += 1
    return line[position:]


def _without_comments(text: str):
    """The page with every `%%` comment removed, and for each character of
    the result its offset in `text` (plus one past the end)."""
    comments = comment_ranges(text)
    if not comments:
        return text, None
    kept_pieces = []
    origin = []
    last = 0
    for start, end in comments:
        kept_pieces.append(text[last:start])
        origin.extend(range(last, start))
        last = end
    kept_pieces.append(text[last:])
    origin.extend(range(last, len(text)))
    origin.append(len(text))
    return "".join(kept_pieces), origin


def fenced_blocks(text: str) -> list:
    """
    Every fenced code block on the page, in order, as dicts:
    {"lang": the info string's first word as written, "meta": the rest of it,
     "body": the content with the quote markers of the fence's depth and up
     to the opener's own indent taken off each line, joined with "\\n",
     "line": the 1-based line of the OPENING fence in `text` as given}.

    The rule is the one `code_ranges` uses (readingALink.whatIsCode); an
    unclosed fence runs to the end of the page, and a line at a smaller quote
    depth ends it. A fence opened on a list marker's own line (`- ```tikz`,
    `1. ```functionplot`) IS a block here (#485 E1 review S1: the site's
    parser draws one, so the build must draw it too); its content lines lose
    up to the fence's own column of indent, as CommonMark's list item does.
    `code_ranges` keeps its #313 rule unchanged.
    """
    stripped, origin = _without_comments(text)
    found = []
    open_block = None

    def close():
        nonlocal open_block
        if open_block is not None:
            found.append({
                "lang": open_block["lang"],
                "meta": open_block["meta"],
                "body": "\n".join(open_block["lines"]),
                "line": open_block["line"],
            })
        open_block = None

    line_start = 0
    length = len(stripped)
    while line_start <= length:
        newline = stripped.find("\n", line_start)
        line_end = length if newline < 0 else newline
        line = stripped[line_start:line_end]
        if line.endswith("\r"):
            line = line[:-1]
        depth, body = _quote_depth_and_body(line)

        if open_block is not None and depth < open_block["depth"]:
            close()

        if open_block is not None:
            content = _strip_quote_markers(line, open_block["depth"])
            fence = _FENCE.match(content)
            if depth == open_block["depth"] and fence \
                    and fence.group(1)[0] == open_block["char"] \
                    and len(fence.group(1)) >= open_block["length"] \
                    and _is_blank(fence.group(2)):
                close()
            else:
                open_block["lines"].append(_without_indent(content, open_block["indent"]))
        else:
            fence = _FENCE.match(body)
            marker = 0
            if not fence:
                after_marker = _LIST_MARKER.match(body)
                if after_marker:
                    fence = _FENCE.match(body[after_marker.end():])
                    marker = after_marker.end()
            if fence and not (fence.group(1)[0] == "`" and "`" in fence.group(2)):
                info = fence.group(2).strip(_WHITESPACE)
                words = info.split(None, 1)
                where = line_start if origin is None else origin[line_start]
                open_block = {
                    "char": fence.group(1)[0],
                    "length": len(fence.group(1)),
                    "depth": depth,
                    "indent": _column(body[:marker + len(body[marker:]) - len(body[marker:].lstrip(" \t"))]),
                    "lang": words[0] if words else "",
                    "meta": words[1] if len(words) > 1 else "",
                    "line": text.count("\n", 0, where) + 1,
                    "lines": [],
                }

        if newline < 0:
            break
        line_start = line_end + 1
    close()
    return found
