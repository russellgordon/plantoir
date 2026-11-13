"""The Markdown subset a Help page may use, parsed into blocks.

Anything outside the subset is REFUSED with the file and line, so a page
renders the same in Help Viewer, on the web and (later) on Windows, and
nothing a writer types is passed through as HTML. The subset:

- `##` and `###` headings (the page title is the outline's, rendered as h1);
- paragraphs; numbered (`1.`) and bulleted (`-`) lists, one level of nesting;
- `**bold**`, `*italic*`, `` `code` ``, links `[words](page:<id>)` and
  `[words](https://...)`;
- fenced blocks with a language (```` ```text wrap ````, ```` ```swift ````);
  a bare ```` ```text ```` is refused, the house rule for text blocks;
- pipe tables with a header row;
- one callout kind, `> [!note]`;
- tokens: `{{menu:}}`, `{{control:}}`, `{{say:}}`, `{{fact:}}`, `{{key:}}`,
  `{{count:}}` inline; `{{picture:}}` with an `alt:` line, and
  `{{mac}}`...`{{/mac}}` / `{{windows}}`...`{{/windows}}` as blocks.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from .problems import Problems

# One line of source text with the line number it came from.
Line = Tuple[int, str]

HEADING = re.compile(r"^(#+)\s+(.*)$")
FENCE = re.compile(r"^```(.*)$")
LIST_ITEM = re.compile(r"^( *)(\d+\.|-)\s+(.*)$")
TABLE_SEPARATOR = re.compile(r"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")
PICTURE = re.compile(r"^\{\{picture:([^{}]*)\}\}\s*$")
PLATFORM_OPEN = re.compile(r"^\{\{(mac|windows)\}\}\s*$")
PLATFORM_CLOSE = re.compile(r"^\{\{/(mac|windows)\}\}\s*$")
FENCE_LANGUAGE = re.compile(r"^[a-z0-9][a-z0-9+#-]*$")

# Inline syntax, tried in this order at each position.
INLINE = re.compile(
    r"(?P<code>`[^`\n]+`)"
    r"|(?P<token>\{\{[^{}\n]*\}\})"
    r"|(?P<link>\[(?P<link_words>[^\]\n]+)\]\((?P<link_target>[^)\s]+)\))"
    r"|(?P<bold>\*\*(?P<bold_inner>.+?)\*\*)"
    r"|(?P<italic>\*(?P<italic_inner>[^*\s][^*]*?)\*)"
)
# A "<" followed at once by a letter, "/" or "!" is the start of a tag or a
# comment; "a < b" is not.
RAW_HTML = re.compile(r"<[/!]?[A-Za-z!-][^>\n]*>?")
INLINE_TOKENS = ["menu", "control", "say", "fact", "key", "count"]


def _block(kind: str, line: int, **fields: Any) -> Dict[str, Any]:
    block: Dict[str, Any] = {"kind": kind, "line": line}
    for name in fields:
        block[name] = fields[name]
    return block


def check_inline_syntax(file: str, line: int, text: str, problems: Problems) -> None:
    """Refuse raw HTML and unknown tokens in one line of inline text."""
    outside_code: str = re.sub(r"`[^`\n]+`", " ", text)
    if RAW_HTML.search(outside_code) is not None:
        problems.fail(file, line, "raw HTML is not part of the page format: " + repr(RAW_HTML.search(outside_code).group(0)))
    for token in re.finditer(r"\{\{([^{}\n]*)\}\}", outside_code):
        inside: str = token.group(1)
        name: str = inside.split(":", 1)[0]
        if name in ("picture", "mac", "/mac", "windows", "/windows"):
            problems.fail(file, line, "`{{" + inside + "}}` goes on a line of its own")
        elif name not in INLINE_TOKENS or ":" not in inside:
            problems.fail(file, line, "unknown token `{{" + inside + "}}`")
    unmatched: str = re.sub(r"\{\{[^{}\n]*\}\}", "", outside_code)
    if "{{" in unmatched or "}}" in unmatched:
        problems.fail(file, line, "a token is not closed with }}")


class Parser:
    """Turns a page body into a list of blocks, refusing what is outside the subset."""

    def __init__(self, file: str, problems: Problems) -> None:
        self.file = file
        self.problems = problems

    def fail(self, line: int, message: str) -> None:
        self.problems.fail(self.file, line, message)

    def parse(self, lines: List[str], first_line: int) -> List[Dict[str, Any]]:
        numbered: List[Line] = []
        offset: int = 0
        for text in lines:
            numbered.append((first_line + offset, text.rstrip("\r")))
            offset += 1
        blocks: List[Dict[str, Any]] = self._parse_lines(numbered, inside_platform=False)
        self._check_heading_order(blocks)
        return blocks

    # MARK: the block reader

    def _parse_lines(self, lines: List[Line], inside_platform: bool) -> List[Dict[str, Any]]:
        blocks: List[Dict[str, Any]] = []
        index: int = 0
        paragraph: List[Line] = []

        def close_paragraph() -> None:
            if len(paragraph) > 0:
                blocks.append(_block("paragraph", paragraph[0][0], lines=list(paragraph)))
                del paragraph[:]

        while index < len(lines):
            number, text = lines[index]
            stripped: str = text.strip()

            if stripped == "":
                close_paragraph()
                index += 1
                continue

            fence = FENCE.match(stripped)
            if fence is not None and text.startswith("```"):
                close_paragraph()
                index = self._read_fence(lines, index, fence.group(1).strip(), blocks)
                continue

            platform = PLATFORM_OPEN.match(stripped)
            if platform is not None:
                close_paragraph()
                index = self._read_platform(lines, index, platform.group(1), inside_platform, blocks)
                continue
            if PLATFORM_CLOSE.match(stripped) is not None:
                close_paragraph()
                self.fail(number, "`" + stripped + "` closes a platform run that is not open")
                index += 1
                continue

            picture = PICTURE.match(stripped)
            if picture is not None:
                close_paragraph()
                index = self._read_picture(lines, index, picture.group(1).strip(), blocks)
                continue

            heading = HEADING.match(text)
            if heading is not None:
                close_paragraph()
                level: int = len(heading.group(1))
                if level == 1:
                    self.fail(number, "a page has one h1, its outline title; start sections with ##")
                elif level > 3:
                    self.fail(number, "headings go to ### and no deeper")
                else:
                    check_inline_syntax(self.file, number, heading.group(2), self.problems)
                    blocks.append(_block("heading", number, level=level, text=heading.group(2).strip()))
                index += 1
                continue

            if stripped.startswith(">"):
                close_paragraph()
                index = self._read_callout(lines, index, blocks)
                continue

            if stripped.startswith("|"):
                close_paragraph()
                index = self._read_table(lines, index, blocks)
                continue

            if LIST_ITEM.match(text) is not None and (len(paragraph) == 0 or LIST_ITEM.match(text).group(1) == ""):
                close_paragraph()
                index = self._read_list(lines, index, blocks)
                continue

            if stripped.startswith("!["):
                self.fail(number, "pictures are written {{picture:<scene>}} with an alt: line, not ![...]")
            elif re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped) is not None:
                self.fail(number, "horizontal rules are not part of the page format")
            elif stripped.lower().startswith("alt:"):
                self.fail(number, "an alt: line belongs directly under a {{picture:}} line")
            check_inline_syntax(self.file, number, stripped, self.problems)
            paragraph.append((number, stripped))
            index += 1

        close_paragraph()
        return blocks

    def _read_fence(self, lines: List[Line], start: int, info: str, blocks: List[Dict[str, Any]]) -> int:
        number: int = lines[start][0]
        words: List[str] = info.split()
        language: str = ""
        wrap: bool = False
        if len(words) == 0:
            self.fail(number, "a fenced block names its language (```text wrap, ```swift, ...)")
        else:
            language = words[0]
            extra: List[str] = words[1:]
            if FENCE_LANGUAGE.match(language) is None:
                self.fail(number, "`" + language + "` is not a language name")
            if extra == ["wrap"]:
                wrap = True
            elif len(extra) > 0:
                self.fail(number, "after the language a fence may say only `wrap`")
            if language == "text" and not wrap:
                self.fail(number, "a text block is written ```text wrap, so long lines wrap (house rule)")
        body: List[str] = []
        index: int = start + 1
        while index < len(lines):
            if lines[index][1].strip() == "```":
                blocks.append(_block("code", number, language=language, wrap=wrap, text="\n".join(body)))
                return index + 1
            body.append(lines[index][1])
            index += 1
        self.fail(number, "this fenced block is never closed with ```")
        return index

    def _read_platform(
        self, lines: List[Line], start: int, platform: str, inside_platform: bool, blocks: List[Dict[str, Any]]
    ) -> int:
        number: int = lines[start][0]
        if inside_platform:
            self.fail(number, "platform runs may not nest")
        inner: List[Line] = []
        index: int = start + 1
        while index < len(lines):
            stripped: str = lines[index][1].strip()
            closing = PLATFORM_CLOSE.match(stripped)
            if closing is not None:
                if closing.group(1) != platform:
                    self.fail(lines[index][0], "`" + stripped + "` closes a {{" + platform + "}} run")
                children = self._parse_lines(inner, inside_platform=True)
                blocks.append(_block("platform", number, platform=platform, children=children))
                return index + 1
            if PLATFORM_OPEN.match(stripped) is not None:
                self.fail(lines[index][0], "platform runs may not nest")
                index += 1
                continue
            inner.append(lines[index])
            index += 1
        self.fail(number, "{{" + platform + "}} is never closed with {{/" + platform + "}}")
        return index

    def _read_picture(self, lines: List[Line], start: int, scene: str, blocks: List[Dict[str, Any]]) -> int:
        number: int = lines[start][0]
        alt: str = ""
        next_index: int = start + 1
        if next_index < len(lines) and lines[next_index][1].strip().lower().startswith("alt:"):
            alt = lines[next_index][1].strip()[4:].strip()
            check_inline_syntax(self.file, lines[next_index][0], alt, self.problems)
            next_index += 1
        if alt == "":
            self.fail(number, "{{picture:" + scene + "}} needs alt text on the line below it (alt: ...)")
        if scene == "":
            self.fail(number, "{{picture:}} names a scene")
        blocks.append(_block("picture", number, scene=scene, alt=alt))
        return next_index

    def _read_callout(self, lines: List[Line], start: int, blocks: List[Dict[str, Any]]) -> int:
        number, text = lines[start]
        if text.strip() != "> [!note]":
            self.fail(number, "the only quote block is a `> [!note]` callout, on a line of its own")
        inner: List[Line] = []
        index: int = start + 1
        while index < len(lines) and lines[index][1].strip().startswith(">"):
            content: str = lines[index][1].strip()[1:]
            if content.startswith(" "):
                content = content[1:]
            if content.strip().startswith(">") or content.strip().startswith("[!"):
                self.fail(lines[index][0], "a callout holds plain text, lists and links, not another quote")
            inner.append((lines[index][0], content))
            index += 1
        children = self._parse_lines(inner, inside_platform=True)
        for child in children:
            if child["kind"] not in ("paragraph", "list"):
                self.fail(child["line"], "a callout holds paragraphs and lists only")
        if len(children) == 0:
            self.fail(number, "this callout is empty")
        blocks.append(_block("note", number, children=children))
        return index

    def _split_row(self, text: str) -> List[str]:
        inner: str = text.strip()
        if inner.startswith("|"):
            inner = inner[1:]
        if inner.endswith("|"):
            inner = inner[:-1]
        cells: List[str] = []
        for cell in inner.split("|"):
            cells.append(cell.strip())
        return cells

    def _read_table(self, lines: List[Line], start: int, blocks: List[Dict[str, Any]]) -> int:
        number: int = lines[start][0]
        rows: List[Line] = []
        index: int = start
        while index < len(lines) and lines[index][1].strip().startswith("|"):
            rows.append(lines[index])
            index += 1
        if len(rows) < 2 or TABLE_SEPARATOR.match(rows[1][1].strip()) is None:
            self.fail(number, "a table starts with a header row and a |---| line")
            return index
        header: List[str] = self._split_row(rows[0][1])
        aligns: List[str] = []
        for cell in self._split_row(rows[1][1]):
            if cell.startswith(":") and cell.endswith(":"):
                aligns.append("center")
            elif cell.endswith(":"):
                aligns.append("right")
            else:
                aligns.append("")
        if len(aligns) != len(header):
            self.fail(rows[1][0], "the |---| line has a different number of columns from the header")
        for cell in header:
            check_inline_syntax(self.file, rows[0][0], cell, self.problems)
        body: List[Tuple[int, List[str]]] = []
        for row_number, row_text in rows[2:]:
            cells: List[str] = self._split_row(row_text)
            if len(cells) != len(header):
                self.fail(row_number, "this row has " + str(len(cells)) + " cells; the header has " + str(len(header)))
            for cell in cells:
                check_inline_syntax(self.file, row_number, cell, self.problems)
            body.append((row_number, cells))
        blocks.append(_block("table", number, header=header, aligns=aligns, rows=body))
        return index

    def _read_list(self, lines: List[Line], start: int, blocks: List[Dict[str, Any]]) -> int:
        first = LIST_ITEM.match(lines[start][1])
        ordered: bool = first is not None and first.group(2) != "-"
        items: List[Dict[str, Any]] = []
        index: int = start
        while index < len(lines):
            number, text = lines[index]
            if text.strip() == "":
                # A blank line ends the list unless the next line carries on it.
                if index + 1 < len(lines):
                    following = LIST_ITEM.match(lines[index + 1][1])
                    if following is not None and (following.group(1) != "" or (following.group(2) != "-") == ordered):
                        index += 1
                        continue
                break
            match = LIST_ITEM.match(text)
            if match is not None:
                indent: int = len(match.group(1))
                item_ordered: bool = match.group(2) != "-"
                check_inline_syntax(self.file, number, match.group(3), self.problems)
                if indent == 0:
                    if item_ordered != ordered:
                        break
                    items.append({"line": number, "lines": [(number, match.group(3).strip())], "children": None})
                elif indent <= 4:
                    if len(items) == 0:
                        self.fail(number, "a nested list item needs an item above it")
                        index += 1
                        continue
                    parent: Dict[str, Any] = items[-1]
                    if parent["children"] is None:
                        parent["children"] = {"kind": "list", "line": number, "ordered": item_ordered, "items": []}
                    elif parent["children"]["ordered"] != item_ordered:
                        self.fail(number, "a nested list keeps one kind of marker")
                    parent["children"]["items"].append(
                        {"line": number, "lines": [(number, match.group(3).strip())], "children": None}
                    )
                else:
                    self.fail(number, "lists nest one level only")
                index += 1
                continue
            if text.startswith("  ") and len(items) > 0:
                # A continuation line of the item above.
                check_inline_syntax(self.file, number, text.strip(), self.problems)
                target: Dict[str, Any] = items[-1]
                if target["children"] is not None and len(target["children"]["items"]) > 0 and text.startswith("    "):
                    target = target["children"]["items"][-1]
                target["lines"].append((number, text.strip()))
                index += 1
                continue
            break
        blocks.append(_block("list", lines[start][0], ordered=ordered, items=items))
        return index

    def _check_heading_order(self, blocks: List[Dict[str, Any]]) -> None:
        seen_level_two: bool = False
        for block in walk_blocks(blocks):
            if block["kind"] != "heading":
                continue
            if block["level"] == 2:
                seen_level_two = True
            elif block["level"] == 3 and not seen_level_two:
                self.fail(block["line"], "a ### heading comes under a ## heading")


def walk_blocks(blocks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Every block, nested ones included, in reading order."""
    result: List[Dict[str, Any]] = []
    for block in blocks:
        result.append(block)
        if block["kind"] in ("platform", "note"):
            for child in walk_blocks(block["children"]):
                result.append(child)
    return result


def parse_body(file: str, lines: List[str], first_line: int, problems: Problems) -> List[Dict[str, Any]]:
    return Parser(file, problems).parse(lines, first_line)


def split_inline(text: str) -> List[Tuple[str, Optional[Any]]]:
    """Splits inline text into ("text", str) and syntax pieces, for the renderer
    and for the readable-text extractor alike."""
    pieces: List[Tuple[str, Optional[Any]]] = []
    position: int = 0
    for match in INLINE.finditer(text):
        if match.start() > position:
            pieces.append(("text", text[position:match.start()]))
        if match.group("code") is not None:
            pieces.append(("code", match.group("code")[1:-1]))
        elif match.group("token") is not None:
            pieces.append(("token", match.group("token")[2:-2]))
        elif match.group("link") is not None:
            pieces.append(("link", (match.group("link_words"), match.group("link_target"))))
        elif match.group("bold") is not None:
            pieces.append(("bold", match.group("bold_inner")))
        else:
            pieces.append(("italic", match.group("italic_inner")))
        position = match.end()
    if position < len(text):
        pieces.append(("text", text[position:]))
    return pieces


def readable_inline(text: str) -> str:
    """What a reader reads of a line, for the word checks: code spans and
    tokens become spaces of the same width (so offsets still hold), link
    targets go, emphasis markers go."""
    result: List[str] = []
    for kind, value in split_inline(text):
        if kind == "text":
            result.append(str(value))
        elif kind in ("code", "token"):
            result.append(" ")
        elif kind == "link":
            words, _target = value
            result.append(readable_inline(words))
        else:
            result.append(readable_inline(str(value)))
    return "".join(result)
