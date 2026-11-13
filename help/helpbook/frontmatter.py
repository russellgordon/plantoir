"""A page's front matter: `key: value` lines between two `---` lines, lists as
`- item` lines under a key with no value. Our own reader, so no third-party
YAML module is needed and nothing a writer types is interpreted beyond this.

The outline owns a page's identity (title, question, section, assistant flag,
scenes): front matter may not restate any of them.
"""

from __future__ import annotations

import re
from typing import Dict, List, Tuple, Union

from .problems import Problems

Value = Union[str, bool, List[str]]

ALLOWED_KEYS = [
    "id",
    "checked",
    "covers",
    "keywords",
    "description",
    "indexed",
    "factsChecked",
    "authority",
]
LIST_KEYS = ["covers", "keywords"]
OWNED_BY_THE_OUTLINE = ["title", "question", "section", "assistant", "scenes", "sceneIds", "anchor"]

KEY_LINE = re.compile(r"^([A-Za-z][A-Za-z0-9]*):(.*)$")
ITEM_LINE = re.compile(r"^\s*-\s+(.*)$")


def _scalar(text: str) -> Value:
    stripped = text.strip()
    if stripped == "true":
        return True
    if stripped == "false":
        return False
    if len(stripped) >= 2 and stripped[0] == stripped[-1] and stripped[0] in "\"'":
        return stripped[1:-1]
    return stripped


def read_front_matter(file: str, text: str, problems: Problems) -> Tuple[Dict[str, Value], List[str], int]:
    """Split a page into its fields and its body lines.

    Returns the fields, the body's lines, and the source line number of the
    body's first line, so every later finding can name its line.
    """
    lines: List[str] = text.split("\n")
    fields: Dict[str, Value] = {}
    if len(lines) == 0 or lines[0].strip() != "---":
        problems.fail(file, 1, "a page starts with front matter between two --- lines")
        return fields, lines, 1
    closing: int = -1
    index: int = 1
    while index < len(lines):
        if lines[index].strip() == "---":
            closing = index
            break
        index += 1
    if closing < 0:
        problems.fail(file, 1, "the front matter has no closing --- line")
        return fields, [], len(lines) + 1

    current_list_key: str = ""
    index = 1
    while index < closing:
        line: str = lines[index]
        line_number: int = index + 1
        index += 1
        if line.strip() == "":
            continue
        item = ITEM_LINE.match(line)
        if item is not None and current_list_key != "":
            existing = fields[current_list_key]
            if isinstance(existing, list):
                existing.append(str(_scalar(item.group(1))))
            continue
        key_match = KEY_LINE.match(line)
        if key_match is None:
            problems.fail(file, line_number, "front matter lines are `key: value` or `- item`, not " + repr(line))
            current_list_key = ""
            continue
        key: str = key_match.group(1)
        value_text: str = key_match.group(2)
        current_list_key = ""
        if key in OWNED_BY_THE_OUTLINE:
            problems.fail(
                file,
                line_number,
                "`" + key + "` comes from help/outline.json only; front matter may not restate it",
            )
            continue
        if key not in ALLOWED_KEYS:
            problems.fail(file, line_number, "unknown front matter key `" + key + "`")
            continue
        if key in fields:
            problems.fail(file, line_number, "`" + key + "` is given twice")
            continue
        if key in LIST_KEYS:
            if value_text.strip() != "":
                problems.fail(file, line_number, "`" + key + "` is a list: put each item on its own `- item` line")
                fields[key] = []
                continue
            fields[key] = []
            current_list_key = key
            continue
        fields[key] = _scalar(value_text)

    body: List[str] = lines[closing + 1:]
    return fields, body, closing + 2
