#!/usr/bin/env python3
"""
Writes contracts/undo-traces.json: sequences of steps, undos, redos, hand
edits and neutral `note` lines for Undo and Redo (#899, piece U1), with what
each call must come to, replayed by BOTH apps' suites against their own
journal.

The expected results are computed here by a reference model of the list:
the front-matter line model (`editLine`), the whole-file fallback
(`writeFile`), the all-or-nothing content check, the linear list (ruling 9),
the redo branch cut by any new step, the whole list cleared when Undo
refuses a step whose line was changed by hand (ruling 13), and only the redo
branch dropped when Redo is refused the same way (ruling 20). A deploy and
sharing unit plans are not on the list and clear nothing (rulings 17 and
18), so no trace holds one. The Swift
implementation in mac-app/QuartzTeachers/Models/Undo/ is written to the
same rules; a trace both agree on is evidence that the rules, not one
implementation's accidents, decide the outcome.

Deterministic: the same seed gives the same bytes, every run, on any
machine (scripts/test_make_undo_traces.py runs it twice and compares).
Pure stdlib. It lives in scripts/, which ships inside the app and each
working folder's .toolchain/, only because Windows' suite discovers every
scripts/test_*.py there (PythonToolchainTests); teachers never run it.
A checkout with CR LF line endings (Windows' core.autocrlf) is compared
as LF.

    python3 scripts/make_undo_traces.py            # rewrite the contract
    python3 scripts/make_undo_traces.py --check    # exit 1 if it is stale
    PLANTOIR_UNDO_FUZZ=<seed> python3 scripts/make_undo_traces.py --print
"""
import functools
import hashlib
import json
import math
import os
import random
import sys
from pathlib import Path

SEED = 899
TRACE_COUNT = 20
SHORTEST = 5
LONGEST = 40
STEPS_KEPT = 50
DAYS_KEPT = 30
CONTRACT = Path(__file__).resolve().parent.parent / "contracts" / "undo-traces.json"
# U3: each daily page action's step, recorded by the Mac from the real action
# code (UndoActionStepsTests writes it; never typed by hand), from which the
# action traces below are made: ACTION_TRACES_PER_STEP traces per step.
ACTION_STEPS = Path(__file__).resolve().parent.parent / "contracts" / "undo-action-steps.json"
ACTION_TRACES_PER_STEP = 6
ACTION_SHORTEST = 2
ACTION_LONGEST = 12

# --------------------------------------------------------------------------
# The fixture: one section's pages, each a shape the line model must handle.
# --------------------------------------------------------------------------

SECTION = "courses/TST1O/Section 1/Classes/"

FIXTURE = [
    ("p1", SECTION + "Unit 1, Day 1.md",
     "---\ntitle: Unit 1, Day 1\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400\n---\n\n# Unit 1, Day 1\n\nToday we start.\n",
     "plain, line feeds"),
    ("p2", SECTION + "Unit 1, Day 2.md",
     "---\r\ntitle: Unit 1, Day 2\r\npublish: false\r\ncreated: 2026-09-09T07:00:00.000-0400\r\n---\r\n\r\n# Unit 1, Day 2\r\n\r\nWritten on Windows.\r\n",
     "carriage returns on every line"),
    ("p3", SECTION + "Unit 1, Day 3.md",
     "---\ntitle: Unit 1, Day 3\npublish: false # not yet\ncreated: 2026-09-10T07:00:00.000-0400\n---\n\nA comment rides on the line.\n",
     "a comment on the publish line"),
    ("p4", SECTION + "Unit 1, Day 4.md",
     "---\ntitle: Unit 1, Day 4\ncreated: 2026-09-11T07:00:00.000-0400\n---\n\nNo publish key yet.\n",
     "no publish key: the step inserts one"),
    ("p5", SECTION + "Unit 1, Day 5.md",
     "# Unit 1, Day 5\n\nNo front matter at all.\n",
     "no front matter: the step makes the block"),
    ("p6", SECTION + "Unit 1, Day 6.md",
     "\ufeff---\ntitle: Unit 1, Day 6\npublish: false\n---\n\nA byte-order mark before the fence.\n",
     "a byte-order mark: today's publish reads the page without it and writes it back without it, so the step is the whole file and its undo puts the mark back"),
    ("p7", SECTION + "Unit 1, Day 7.md",
     "---\ntitle: Unit 1, Day 7\ntags:\n  - review\n  - quiz\npublish: false\n---\n\nAn entry that runs on to the lines below it.\n",
     "a key whose value runs on to indented lines"),
    ("p8", SECTION + "Unit 1, Day 8.md",
     "---\ntitle: Unit 1, Day 8\npublish: false\npublish: true\n---\n\nThe key twice: never a guess.\n",
     "the publish key twice: the writer leaves it alone"),
]

PAGE_IDS = [page_id for page_id, _, _, _ in FIXTURE]
PATHS = {page_id: path for page_id, path, _, _ in FIXTURE}
START = {page_id: text for page_id, _, text, _ in FIXTURE}

# --------------------------------------------------------------------------
# The front-matter line model: the same rules as UndoFrontMatter and
# UndoLineOps in JournaledWrite.swift, and the fence rules of
# PageVisibilityReader.fenceIndices.
# --------------------------------------------------------------------------


def trim_cr(line):
    return line[:-1] if line.endswith("\r") else line


def trim_yaml_spaces(text):
    return trim_cr(text).strip(" \t")


def is_fence(line):
    bare = trim_cr(line).rstrip(" \t")
    return len(bare) >= 3 and all(character == "-" for character in bare)


def is_opening_fence(line):
    return is_fence(trim_yaml_spaces(line))


def fence_indices(text):
    lines = text.split("\n")
    open_index = 0
    while open_index < len(lines):
        if trim_yaml_spaces(lines[open_index]) != "":
            break
        open_index += 1
    if open_index >= len(lines) or not is_opening_fence(lines[open_index]):
        return None
    index = open_index + 1
    while index < len(lines):
        if is_fence(lines[index]):
            return open_index, index
        index += 1
    return None


def opens_a_fence(text):
    for line in text.split("\n"):
        if trim_yaml_spaces(line) == "":
            continue
        return is_opening_fence(line)
    return False


def top_level_key(raw_line):
    line = trim_cr(raw_line)
    if line == "" or line[0] in " \t#-":
        return None
    if ":" not in line:
        return None
    key = line[:line.index(":")].strip()
    if len(key) >= 2 and key[0] in "\"'" and key[-1] == key[0]:
        key = key[1:-1]
    return key or None


def continues_a_value(raw_line):
    line = trim_cr(raw_line)
    if line == "":
        return False
    if line[0] in " \t":
        return line.strip() != ""
    return line[0] == "-" and not line.startswith("---")


class Layout:
    def __init__(self, text):
        fences = fence_indices(text)
        if fences is None:
            raise ValueError("no block")
        self.lines = text.split("\n")
        self.open_index, self.close_index = fences
        self.entries = []
        index = self.open_index + 1
        while index < self.close_index:
            key = top_level_key(self.lines[index])
            if key is None:
                index += 1
                continue
            end = index + 1
            while end < self.close_index and continues_a_value(self.lines[end]):
                end += 1
            self.entries.append((key, index, end))
            index = end

    def entries_for(self, key):
        return [entry for entry in self.entries if entry[0] == key]

    def text_of(self, entry):
        return "\n".join(self.lines[entry[1]:entry[2]])

    def key_before(self, entry):
        previous = None
        for candidate in self.entries:
            if candidate[1] == entry[1]:
                return previous
            previous = candidate[0]
        return previous


def layout_of(text):
    try:
        return Layout(text)
    except ValueError:
        return None


ABSENT = ("absent",)
UNREADABLE = ("unreadable",)


def reading(key, text):
    layout = layout_of(text)
    if layout is None:
        return UNREADABLE if opens_a_fence(text) else ABSENT
    found = layout.entries_for(key)
    if not found:
        return ABSENT
    if len(found) > 1:
        return UNREADABLE
    return ("entry", layout.text_of(found[0]))


def matches(read, expected):
    if read == ABSENT:
        return expected is None
    if read == UNREADABLE:
        return False
    return expected is not None and read[1] == expected


def moving(op, source, target, text):
    if not matches(reading(op["key"], text), source):
        return None
    if source == target:
        return text
    layout = layout_of(text)
    if layout is None:
        if target is None or not op.get("createdTheBlock"):
            return None
        return "---\n" + target + "\n---\n" + text
    lines = list(layout.lines)
    found = layout.entries_for(op["key"])
    if found:
        entry = found[0]
        if target is not None:
            lines[entry[1]:entry[2]] = target.split("\n")
            return "\n".join(lines)
        del lines[entry[1]:entry[2]]
        only = len(layout.entries) == 1
        empty = only and layout.close_index - layout.open_index - 1 == entry[2] - entry[1]
        if op.get("createdTheBlock") and empty and layout.open_index == 0:
            del lines[0:2]
        return "\n".join(lines)
    if target is None:
        return text
    insert_at = layout.open_index + 1
    if op.get("afterKey") is not None:
        anchors = layout.entries_for(op["afterKey"])
        if len(anchors) == 1:
            insert_at = anchors[0][2]
    lines[insert_at:insert_at] = target.split("\n")
    return "\n".join(lines)


def edit_line(path, key, before, after, after_key, created):
    op = {"kind": "editLine", "path": path, "key": key, "before": before, "after": after, "afterKey": after_key}
    if created:
        op["createdTheBlock"] = True
    return op


def verified(ops, before, after):
    forward = before
    for op in ops:
        forward = moving(op, op["before"], op["after"], forward)
        if forward is None:
            return None
    if forward != after:
        return None
    backward = after
    for op in reversed(ops):
        backward = moving(op, op["after"], op["before"], backward)
        if backward is None:
            return None
    if backward != before:
        return None
    return ops


def line_ops(path, before, after):
    if before == after:
        return []
    after_layout = layout_of(after)
    if after_layout is None:
        return None
    before_layout = layout_of(before)
    result = []
    if before_layout is None:
        if len(after_layout.entries) != 1:
            return None
        entry = after_layout.entries[0]
        result.append(edit_line(path, entry[0], None, after_layout.text_of(entry), None, True))
        return verified(result, before, after)
    seen = set()
    for entry in after_layout.entries:
        if entry[0] in seen:
            return None
        seen.add(entry[0])
        in_before = before_layout.entries_for(entry[0])
        if len(in_before) > 1:
            return None
        after_text = after_layout.text_of(entry)
        before_text = before_layout.text_of(in_before[0]) if in_before else None
        if before_text == after_text:
            continue
        result.append(edit_line(path, entry[0], before_text, after_text, after_layout.key_before(entry), False))
    for entry in before_layout.entries:
        if entry[0] in seen:
            continue
        if len(before_layout.entries_for(entry[0])) > 1:
            return None
        seen.add(entry[0])
        result.append(edit_line(path, entry[0], before_layout.text_of(entry), None, before_layout.key_before(entry), False))
    if not result:
        return None
    return verified(result, before, after)


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def ops_for_change(path, before, after):
    """The ops of one file's change: lines where they reproduce it, else the file."""
    whole = {"kind": "writeFile", "path": path,
             "beforeSha": None if before is None else sha(before),
             "afterSha": None if after is None else sha(after),
             "beforeText": before, "afterText": after}
    if before is None or after is None:
        return [whole]
    found = line_ops(path, before, after)
    return found if found else [whole]


def setting_entry(key, line, text):
    """JournaledWrite.settingEntry: the traces' writer. A leading byte-order
    mark is dropped first, as today's publish drops it."""
    if text.startswith("\ufeff"):
        text = text[1:]
    layout = layout_of(text)
    if layout is None:
        return "---\n" + line + "\n---\n" + text
    found = layout.entries_for(key)
    if len(found) > 1:
        return None
    lines = list(layout.lines)
    if found:
        entry = found[0]
        replacement = line
        if lines[entry[1]].endswith("\r") and not line.endswith("\r"):
            replacement += "\r"
        lines[entry[1]:entry[2]] = [replacement]
        return "\n".join(lines)
    replacement = line
    if lines[layout.open_index].endswith("\r") and not line.endswith("\r"):
        replacement += "\r"
    lines.insert(layout.open_index + 1, replacement)
    return "\n".join(lines)


def op_state(op, current):
    """UndoCheck.state: 'before', 'after' or 'neither'. current is text or None."""
    if op["kind"] == "replaceText":
        return replace_text_state(op, None if current is None else current.encode("utf-8"))
    if op["kind"] == "editJSON":
        return edit_json_state(op, None if current is None else current.encode("utf-8"))
    if op["kind"] == "writeFile":
        current_sha = None if current is None else sha(current)
        if current_sha == op["beforeSha"]:
            return "before"
        if current_sha == op["afterSha"]:
            return "after"
        return "neither"
    if current is None:
        return "neither"
    read = reading(op["key"], current)
    if matches(read, op["before"]):
        return "before"
    if matches(read, op["after"]):
        return "after"
    return "neither"


# --------------------------------------------------------------------------
# The kinds U2 defines (file-formats.json -> undoJournal.opKinds): the
# reference for undo.checkCases and undo.listingCases. Content only.
# --------------------------------------------------------------------------

def listing_text(tree):
    """A folder's listing (opKinds.createTree): one line per item inside,
    `folder <path>` or `file <sha256> <path>`, in the order of the paths'
    UTF-8 bytes, each ending in a line feed. tree: {"folders": [...],
    "files": {path: text}}."""
    entries = []
    ignored = ".DS_Store"   # the Finder's own record, never listed
    for folder in tree.get("folders", []):
        if folder.split("/")[-1] == ignored:
            continue
        entries.append((folder.encode("utf-8"), "folder " + folder + "\n"))
    for path, text in tree.get("files", {}).items():
        if path.split("/")[-1] == ignored:
            continue
        entries.append((path.encode("utf-8"), "file " + sha(text) + " " + path + "\n"))
    entries.sort()
    return "".join(line for _, line in entries)


def listing_sha(tree):
    return sha(listing_text(tree))


def occurrences(needle, haystack):
    found = []
    if not needle or len(needle) > len(haystack):
        return found
    for start in range(len(haystack) - len(needle) + 1):
        if haystack[start:start + len(needle)] == needle:
            found.append(start)
    return found


def hunk_place(window, other, data):
    """A window is found when it occurs exactly once and every occurrence
    of the other window lies inside that one (opKinds.replaceText)."""
    mine = occurrences(window, data)
    if len(mine) != 1:
        return None
    start, end = mine[0], mine[0] + len(window)
    for other_start in occurrences(other, data):
        if other_start < start or other_start + len(other) > end:
            return None
    return start


def replace_text_state(op, data):
    if data is None:
        return "neither"
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return "neither"
    before = (op["contextBefore"] + op["before"] + op["contextAfter"]).encode("utf-8")
    after = (op["contextBefore"] + op["after"] + op["contextAfter"]).encode("utf-8")
    if hunk_place(before, after, data) is not None:
        return "before"
    if hunk_place(after, before, data) is not None:
        return "after"
    return "neither"


ABSENT_MEMBER = object()


def json_equal(first, second):
    """Compared as JSON: true is never 1, numbers by value, strings code
    point for code point, objects by members, arrays in order."""
    if isinstance(first, bool) or isinstance(second, bool):
        return isinstance(first, bool) and isinstance(second, bool) and first == second
    if first is None or second is None:
        return first is None and second is None
    if isinstance(first, (int, float)) and isinstance(second, (int, float)):
        return float(first) == float(second)
    if isinstance(first, str) and isinstance(second, str):
        return first == second
    if isinstance(first, list) and isinstance(second, list):
        return len(first) == len(second) and all(json_equal(a, b) for a, b in zip(first, second))
    if isinstance(first, dict) and isinstance(second, dict):
        return first.keys() == second.keys() and all(json_equal(first[k], second[k]) for k in first)
    return False


def edit_json_state(op, data):
    if data is None:
        return "neither"
    top = _mac_read(data)
    if not isinstance(top, dict):
        return "neither"
    current = top
    for part in op["keyPath"]:
        if not isinstance(current, dict):
            return "neither"
        if part not in current:
            current = ABSENT_MEMBER
            break
        current = current[part]

    # What the model is not measured to read as the mac's Foundation reads
    # it (#899 W6 review 2): cannot tell, as on Windows.
    if not _path_measured(op["keyPath"], top) or (
            current is not ABSENT_MEMBER and not _measured(current)) or any(
            side in op and not _measured(op[side]) for side in ("before", "after")):
        return "cannotTell"

    # A whole number beyond 2^53, in the file or the record, cannot be
    # compared exactly through a double: cannot tell (the third hard review).
    if (current is not ABSENT_MEMBER and not _exact(current)) or any(
            side in op and not _exact(op[side]) for side in ("before", "after")):
        return "cannotTell"
    def matches(side):
        if side not in op:
            return current is ABSENT_MEMBER
        return current is not ABSENT_MEMBER and json_equal(current, op[side])

    if matches("before"):
        return "before"
    if matches("after"):
        return "after"
    return "neither"


def _skip(data, at):
    while at < len(data) and data[at] in b" \t\n\r":
        at += 1
    return at


def _scan_string(data, at):
    if at >= len(data) or data[at] != 0x22:
        return None
    index = at + 1
    while index < len(data):
        if data[index] == 0x5C:
            index += 2
            continue
        if data[index] == 0x22:
            return index + 1, json.loads(data[at:index + 1].decode("utf-8"))
        index += 1
    return None


def _scan_value(data, at):
    if at >= len(data):
        return None
    first = data[at]
    if first == 0x22:
        found = _scan_string(data, at)
        return found[0] if found else None
    if first in (0x7B, 0x5B):
        depth = 0
        index = at
        while index < len(data):
            byte = data[index]
            if byte == 0x22:
                found = _scan_string(data, index)
                if not found:
                    return None
                index = found[0]
                continue
            if byte in (0x7B, 0x5B):
                depth += 1
            elif byte in (0x7D, 0x5D):
                depth -= 1
                if depth == 0:
                    return index + 1
            index += 1
        return None
    index = at
    while index < len(data) and data[index] not in b" \t\n\r,}]":
        index += 1
    return index if index > at else None


def _scan_object(data, at):
    """[(name, nameStart, colonBytes, valueStart, valueEnd, leadBytes)], close."""
    if at >= len(data) or data[at] != 0x7B:
        return None
    members = []
    index = at + 1
    lead_start = index
    while True:
        index = _skip(data, index)
        if index >= len(data):
            return None
        if data[index] == 0x7D:
            return members, index
        lead = data[lead_start:index]
        found = _scan_string(data, index)
        if not found:
            return None
        name_end, name = found
        colon = _skip(data, name_end)
        if colon >= len(data) or data[colon] != 0x3A:
            return None
        value_start = _skip(data, colon + 1)
        value_end = _scan_value(data, value_start)
        if value_end is None:
            return None
        members.append((name, index, data[name_end:value_start], value_start, value_end, lead))
        index = _skip(data, value_end)
        if index >= len(data):
            return None
        if data[index] == 0x2C:
            index += 1
            lead_start = index
            continue
        if data[index] == 0x7D:
            return members, index
        return None


def _exact(value):
    """A double holds every number exactly as written: no whole number
    beyond 2^53 (the second hard review of U2b)."""
    if isinstance(value, bool):
        return True
    if isinstance(value, (int, float)):
        if isinstance(value, float) and math.isinf(value):
            return False
        return not (float(value).is_integer() and abs(value) >= 9007199254740992)
    if isinstance(value, list):
        return all(_exact(element) for element in value)
    if isinstance(value, dict):
        return all(_exact(element) for element in value.values())
    return True


# What the mac's Foundation does with an editJSON value, as far as it is
# MEASURED (macOS 26.7.3, 2026-11-20, through the mac's own code; the same
# rules as Windows' UndoJson and UndoMacKeyOrder). Anything not measured is
# refused, never guessed at (#899 W6 review 2).

class _Unmeasured(float):
    """A number a file spells in a way not measured to read as the mac reads it."""


_PUNCTUATION = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$"


# undo.numberSpellingRule (measured through the mac's reader, macOS 26.7.3,
# 2026-11-20, #899 W6 review 3): the most characters the mac reads after a
# number's e or E, its sign and leading zeros included (1e0005, 1e+005 and
# 1e-999 are read; 1e00005, 1e+0005, 1e-0001 and 0e99999 make the file one it
# cannot read), and the most digits read as it reads them, with an exponent
# and without. Windows' UndoJson holds the same three.
MAC_EXPONENT_CHARACTERS_AT_MOST = 4
MEASURED_DIGITS_WITH_AN_EXPONENT = 17
MEASURED_DIGITS_WITHOUT_AN_EXPONENT = 38


def _exponent_read_by_the_mac(spelling):
    """A spelling with no exponent, or at most MAC_EXPONENT_CHARACTERS_AT_MOST
    characters after its e or E. A file holding any other is not JSON."""
    marker = max(spelling.find("e"), spelling.find("E"))
    if marker < 0:
        return True
    characters_after_it = len(spelling) - marker - 1
    return characters_after_it <= MAC_EXPONENT_CHARACTERS_AT_MOST


def _spelling_measured(spelling):
    """At most 17 digits with an exponent, 38 without, counted from the
    first digit that is not a leading zero of the integer part."""
    unsigned = spelling[1:] if spelling.startswith("-") else spelling
    marker = max(unsigned.find("e"), unsigned.find("E"))
    mantissa = unsigned[:marker] if marker >= 0 else unsigned
    whole, _, fraction = mantissa.partition(".")
    digits = len(whole.lstrip("0")) + len(fraction)
    if marker >= 0:
        return digits <= MEASURED_DIGITS_WITH_AN_EXPONENT
    return digits <= MEASURED_DIGITS_WITHOUT_AN_EXPONENT


def _read_number(spelling):
    """The double the mac's reader takes from a measured spelling: a fixed
    spelling with a point and more than 17 digits is a decimal number, its
    digits summed in 16-bit pieces and divided by ten once per place; minus
    infinity beyond the range below zero; refused (not JSON) above it, and
    for an exponent the mac does not read."""
    if not _exponent_read_by_the_mac(spelling):
        raise ValueError("an exponent the mac does not read")
    nearest = float(spelling)
    if not _spelling_measured(spelling):
        return _Unmeasured(0.0 if math.isinf(nearest) else nearest)
    if math.isinf(nearest):
        if nearest < 0:
            return nearest
        raise ValueError("beyond a double's range")
    if "e" in spelling.lower() or "." not in spelling:
        return int(spelling) if "." not in spelling and "e" not in spelling.lower() else nearest
    negative = spelling.startswith("-")
    unsigned = spelling[1:] if negative else spelling
    whole, _, fraction = unsigned.partition(".")
    whole = whole.lstrip("0")
    if len(whole) + len(fraction) <= 17:
        return nearest
    mantissa = int(whole + fraction)
    exponent = -len(fraction)
    while mantissa != 0 and mantissa % 10 == 0:
        mantissa //= 10
        exponent += 1
    pieces = []
    while mantissa != 0:
        pieces.append(mantissa & 0xFFFF)
        mantissa >>= 16
    read = 0.0
    for piece in reversed(pieces):
        read = read * 65536 + piece
    for _ in range(-exponent):
        read /= 10
    for _ in range(exponent):
        read *= 10
    return -read if negative else read


def _refuse_constant(name):
    raise ValueError("not JSON: " + name)


def _holds_half_a_pair(value):
    if isinstance(value, str):
        for character in value:
            if 0xD800 <= ord(character) <= 0xDFFF:
                return True
        return False
    if isinstance(value, list):
        for element in value:
            if _holds_half_a_pair(element):
                return True
        return False
    if isinstance(value, dict):
        for key, element in value.items():
            if _holds_half_a_pair(key) or _holds_half_a_pair(element):
                return True
        return False
    return False


def _mac_read(data):
    """The file as the mac's reader reads it, or None where it cannot (not
    UTF-8, not JSON, a number above a double's range, half a surrogate pair)."""
    try:
        value = json.loads(data.decode("utf-8"), parse_float=_read_number, parse_int=_read_number,
                           parse_constant=_refuse_constant)
    except (UnicodeDecodeError, ValueError):
        return None
    if _holds_half_a_pair(value):
        return None
    return value


def _measured_key(key):
    for character in key:
        if not 0x20 <= ord(character) <= 0x7E:
            return False
    return True


def _measured(value):
    """Every key printable ASCII, no text starting with a byte-order mark,
    every number read as measured."""
    if isinstance(value, _Unmeasured):
        return False
    if isinstance(value, str):
        return not value.startswith("\ufeff")
    if isinstance(value, list):
        for element in value:
            if not _measured(element):
                return False
        return True
    if isinstance(value, dict):
        for key, element in value.items():
            if not _measured_key(key) or not _measured(element):
                return False
        return True
    return True


def _numbers_measured(value):
    if isinstance(value, _Unmeasured):
        return False
    if isinstance(value, list):
        for element in value:
            if not _numbers_measured(element):
                return False
        return True
    if isinstance(value, dict):
        for element in value.values():
            if not _numbers_measured(element):
                return False
        return True
    return True


def _path_measured(key_path, top):
    """Each part, and every key of each object on the way, printable ASCII;
    and the file holding only numbers read as measured."""
    if not _numbers_measured(top):
        return False
    current = top
    for part in key_path:
        if not _measured_key(part):
            return False
        if not isinstance(current, dict):
            return True
        for key in current:
            if not _measured_key(key):
                return False
        if part not in current:
            return True
        current = current[part]
    return True


def _key_pieces(key):
    pieces = []
    index = 0
    while index < len(key):
        character = key[index]
        if character.isdigit() and character.isascii():
            end = index
            while end < len(key) and key[end].isdigit() and key[end].isascii():
                end += 1
            run = key[index:end]
            without_zeros = run.lstrip("0")
            pieces.append((1, "%010d" % len(without_zeros) + without_zeros, len(run) - len(without_zeros)))
            index = end
            continue
        if character in _PUNCTUATION:
            pieces.append((0, "%02d" % _PUNCTUATION.index(character), 0))
        elif "a" <= character <= "z":
            pieces.append((2, character, 0))
        elif "A" <= character <= "Z":
            pieces.append((2, character.lower(), 1))
        else:
            pieces.append((3, "%06d" % ord(character), 0))
        index += 1
    return pieces


def _ordinal(text):
    return text.encode("utf-16-le")


def _mac_key_order(first, second):
    """Windows' UndoMacKeyOrder: the mac's order for printable ASCII keys."""
    one, other = _key_pieces(first), _key_pieces(second)
    shared = min(len(one), len(other))
    for index in range(shared):
        if one[index][0] != other[index][0]:
            return -1 if one[index][0] < other[index][0] else 1
        if one[index][1] != other[index][1]:
            return -1 if one[index][1] < other[index][1] else 1
    if len(one) != len(other):
        return -1 if len(one) < len(other) else 1
    for index in range(shared):
        if one[index][2] != other[index][2]:
            return -1 if one[index][2] < other[index][2] else 1
    if first == second:
        return 0
    return -1 if _ordinal(first) < _ordinal(second) else 1


def _spell_number(value):
    if float(value).is_integer():
        return str(int(value))
    return "%.17g" % value


def _spelled(value):
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return _spell_number(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        parts = []
        for element in value:
            parts.append(_spelled(element))
        return "[" + ",".join(parts) + "]"
    names = sorted(value, key=functools.cmp_to_key(_mac_key_order))
    parts = []
    for name in names:
        parts.append(json.dumps(name, ensure_ascii=False) + ":" + _spelled(value[name]))
    return "{" + ",".join(parts) + "}"


def _spell(value):
    if not _exact(value) or not _measured(value):
        return None
    return _spelled(value).encode("utf-8")


def _setting(key_path, value, tree, wanted):
    """The tree with the member set (or taken out), or None when a part on
    the way is missing or not an object."""
    if not isinstance(tree, dict):
        return None
    copy = dict(tree)
    first = key_path[0]
    if len(key_path) == 1:
        if wanted:
            copy[first] = value
        else:
            copy.pop(first, None)
        return copy
    if first not in copy:
        return None
    inner = _setting(key_path[1:], value, copy[first], wanted)
    if inner is None:
        return None
    copy[first] = inner
    return copy


def json_bytes_moved(op, backward, data):
    """opKinds.editJSON's move: only the member's bytes change (the hard
    review of U2b, LOW a), and the result must read back, as the mac reads
    it, as the file with that one member changed. None when it cannot be
    done safely."""
    top = _mac_read(data)
    if not isinstance(top, dict) or not _path_measured(op["keyPath"], top):
        return None
    wanted_key = "before" if backward else "after"
    expected = _setting(op["keyPath"], op.get(wanted_key), top, wanted_key in op)
    if expected is None:
        return None
    moved = _json_bytes_moved(op, wanted_key, data)
    if moved is None or moved is data:
        return moved
    read_back = _mac_read(moved)
    if read_back is None or not json_equal(read_back, expected):
        return None
    return moved


def _json_bytes_moved(op, wanted_key, data):
    key_path = op["keyPath"]
    start = _skip(data, 0)
    for depth, part in enumerate(key_path):
        scanned = _scan_object(data, start)
        if scanned is None:
            return None
        members, close = scanned
        found = [member for member in members if member[0] == part]
        if len(found) > 1:
            return None
        last = depth == len(key_path) - 1
        if not found:
            if not last:
                return None
            if wanted_key not in op:
                return data
            value = _spell(op[wanted_key])
            name = _spell(part)
            if value is None:
                return None
            if members:
                tail = members[-1]
                insert = b"," + tail[5] + name + tail[2] + value
                at = tail[4]
            else:
                insert = name + b": " + value
                at = close
            return data[:at] + insert + data[at:]
        member = found[0]
        if not last:
            start = member[3]
            continue
        if wanted_key in op:
            spelled = _spell(op[wanted_key])
            if spelled is None:
                return None
            return data[:member[3]] + spelled + data[member[4]:]
        position = members.index(member)
        if position + 1 < len(members):
            return data[:member[1]] + data[members[position + 1][1]:]
        if position > 0:
            return data[:members[position - 1][4]] + data[member[4]:]
        inside = _skip(data, start + 1)
        return data[:inside] + data[member[4]:]
    return None


def tree_reading(item):
    """An item spec of the cases: absent, a file, or a folder (listing)."""
    if item is None or item.get("absent"):
        return ("absent",)
    if "tree" in item:
        if item["tree"].get("links"):
            return ("other",)
        return ("tree", listing_sha(item["tree"]))
    if "link" in item:
        # U4b2-14: a link is read by the bytes it holds, never followed.
        return ("link", sha(item["link"]))
    if "treeSha" in item:
        return ("tree", item["treeSha"])
    if item.get("folder"):
        return ("tree", listing_sha({}))
    return ("file", sha(item["text"]) if "text" in item else None)


def move_state(op, at_from, at_to, listed_as=None):
    """opKinds.move, judged as a PAIR (#897 piece B, seam 1). `listed_as`
    (checkCasesHow's listedAs, U4b2-9) is the spelling the folder lists a
    capitalisation-only move's one item under: at `from` or `to` it is the
    pair as given; any other spelling is neither side (UndoCheck.wholeState's
    `.another`), whatever the item holds."""
    if listed_as is not None and is_case_only_move(op) and listed_as not in (op["from"], op["to"]):
        return "neither"
    def side(item):
        reading = tree_reading(item)
        if reading[0] == "absent":
            return "free"
        if "sha" in op:
            return "holds" if reading == ("file", op["sha"]) else "else"
        if "linkSha" in op:
            # U4b2-14: a link moved as itself, judged by its target.
            return "holds" if reading == ("link", op["linkSha"]) else "else"
        return "holds" if reading == ("tree", op["listingSha"]) else "else"
    source, destination = side(at_from), side(at_to)
    if source == "free" and destination == "holds":
        return "after"
    if source == "holds" and destination == "free":
        return "before"
    return "neither"


def tree_state(op, item):
    reading = tree_reading(item)
    if reading[0] in ("file", "other", "link"):
        return "neither"
    present = reading[0] == "tree"
    if present and reading[1] != op["listingSha"]:
        return "neither"
    if op["kind"] == "createTree":
        return "after" if present else "before"
    return "before" if present else "after"


def external_state(op, current):
    if current.get("unreadable"):
        return "neither"
    absent = current.get("absent", False)

    def matches(side):
        if side not in op:
            return absent
        return not absent and json_equal(current["preference"], op[side])

    if matches("before"):
        return "before"
    if matches("after"):
        return "after"
    return "neither"


def plan(ops, backward, pages_by_path, content_missing=False, available=None, used=None, leaves_apart=False):
    """UndoCheck.plan: ('ready', {path: new text or None}, left_apart),
    ('changedSince', first, others), or ('contentMissing', path) when a
    whole-file op needs a blob and the list's content is gone
    (`content_missing`). `available(path, text)` says whether a text the
    list's content no longer holds can still be had (written back since, or
    a kept original beside the page whose hash matches: Russell's ruling of
    2026-11-20, 15:20); each such use is added to `used` as (path, text
    taken, text the page held, the other text). With `leaves_apart` (an
    Undo or a Redo, never the making of a step), a `moveApart` found changed
    since is left where it is and named in left_apart, and the rest goes
    ahead (U3b, Russell's ruling of 2026-11-19 on Q3), as is an external op
    on a scheduledDeploy. The step's moveApart ops (a section's website
    records) go as a GROUP: when any one is changed since, every one not
    already where it is wanted is left apart (the director's decision of
    2026-11-20, on #899). A `setAside` (a leftover no deploy reads) stands
    apart ON ITS OWN, never one of that group (the review of U3b's fixes,
    LOW 3). A move, a moveApart or a setAside needs no blob (it is a
    rename, judged by its hash), so no kept original is ever looked for
    for one (the merge of U3b and U3c)."""
    ordered = list(reversed(ops)) if backward else list(ops)
    # U4b (opKinds.wholeOps' order): an edit named inside a move's new place,
    # after the move, is carried by it. Forward it is judged where the file
    # is before the move and made after it; backward it is taken back first,
    # and the move is judged as if it were.
    carriers = carried_edits(ops)
    moving_now = set()
    group_stays_apart = leaves_apart and any(
        op["kind"] == "moveApart" and whole_state(op, pages_by_path) == "neither" for op in ordered
    )
    original = {}
    working = {}
    in_the_way = []
    whole_changes = {}
    left_apart = []
    wanted_from = "after" if backward else "before"
    linked = pages_by_path.get(LINKED_OUTSIDE, set())
    for op in ordered:
        kind = op["kind"]
        if kind == "recompute":
            continue
        places = [op[key] for key in ("path", "from", "to") if key in op]
        leading_out = None
        for place in places:
            if leading_out is None and any(place == folder or place.startswith(folder + "/") for folder in linked):
                leading_out = place
        if leading_out is not None:
            # A place that now leads outside the working folder through a
            # link: a change since, nothing moved (the second hard review of
            # U2b, MEDIUM 2). Named by the first of the op's places, in the
            # order path, from, to, that leads out, never the other side of
            # a move (U4b2-2).
            if leading_out not in in_the_way:
                in_the_way.append(leading_out)
            continue
        if kind in WHOLE_KINDS:
            # Judged whole against what is there (opKinds.wholeOps).
            seen = pages_by_path
            carries = any(carrier is op for carrier in carriers.values())
            if backward and carries:
                seen = dict(pages_by_path)
                for path, carrier in carriers.items():
                    if carrier is op and path in working:
                        if working[path] is None:
                            seen.pop(path, None)
                        else:
                            seen[path] = working[path]
            state = whole_state(op, seen)
            place = op.get("path") or op.get("from") or op.get("target")
            if group_stays_apart and kind == "moveApart" and state in ("neither", wanted_from):
                left_apart.append(place)
                continue
            if state == "neither":
                if leaves_apart and stands_apart(op):
                    left_apart.append(place)
                    continue
                if place not in in_the_way:
                    in_the_way.append(place)
                continue
            if state != wanted_from:
                continue
            if content_missing and kind in ("createTree", "removeTree"):
                # A tree is never made or taken out unless the list holds
                # everything needed to make it (the hard review of U2b, HIGH 2).
                return ("contentMissing", place)
            if carries and not backward:
                moving_now.add(op["to"])
            whole_changes.update(whole_moved(op, backward, seen))
            continue
        path = op["path"]
        if path not in original:
            read_path = path
            carrier = carriers.get(path)
            if carrier is not None and carrier["to"] in moving_now:
                read_path = place_before_the_move(path, carrier)
            original[path] = pages_by_path.get(read_path)
            working[path] = original[path]
        state = op_state(op, working[path])
        if state == "neither":
            if path not in in_the_way:
                in_the_way.append(path)
            continue
        if state != wanted_from:
            continue
        if op["kind"] == "writeFile":
            target = op["beforeText"] if backward else op["afterText"]
            if content_missing and target is not None:
                if available is None or not available(path, target):
                    return ("contentMissing", path)
                if used is not None:
                    other = op["afterText"] if backward else op["beforeText"]
                    used.append((path, target, working[path], other))
            working[path] = target
        elif kind == "replaceText":
            moved = hunk_moved(op, backward, working[path])
            if moved is None:
                if path not in in_the_way:
                    in_the_way.append(path)
                continue
            working[path] = moved
        elif kind == "editJSON":
            moved = json_moved(op, backward, working[path])
            if moved is None:
                if path not in in_the_way:
                    in_the_way.append(path)
                continue
            working[path] = moved
        else:
            source = op["after"] if backward else op["before"]
            target = op["before"] if backward else op["after"]
            working[path] = moving(op, source, target, working[path])
    if in_the_way:
        return ("changedSince", in_the_way[0], len(in_the_way) - 1)
    file_changes = {}
    for path in original:
        if original[path] != working[path]:
            file_changes[path] = working[path]
    # Forward, a carried edit goes in after its move; backward, before it.
    changes = {}
    if backward:
        changes.update(file_changes)
        changes.update(whole_changes)
    else:
        changes.update(whole_changes)
        changes.update(file_changes)
    return ("ready", changes, left_apart)


EDIT_KINDS = ("writeFile", "editLine", "replaceText", "editJSON")


def part_inside(place, path):
    """UndoOp.partInside (U4b2-9): the part of `path` inside `place`,
    spelled as `path` spells it ("" for the place itself), or None when it
    is neither the place nor inside it. Part by part, without regard to
    case: the ONE comparison for "at or inside" (places overlapping, a
    move carrying an edit, a carried page's place before the move)."""
    place_parts, path_parts = place.split("/"), path.split("/")
    if len(path_parts) < len(place_parts):
        return None
    for mine, theirs in zip(place_parts, path_parts):
        if mine.lower() != theirs.lower():
            return None
    return "/".join(path_parts[len(place_parts):])


def places_overlap(first, second):
    """UndoOp.placesOverlap: the same place, or one a folder holding the
    other, by part_inside."""
    return part_inside(first, second) is not None or part_inside(second, first) is not None


def place_before_the_move(path, move):
    """UndoOp.placeBeforeTheMove: a path inside a move's `to`, at the same
    place under its `from`."""
    inside = part_inside(move["to"], path)
    if inside is None:
        return path
    return move["from"] + "/" + inside if inside else move["from"]


def move_carries(move, edit):
    """UndoOp.moveCarries: an edit of the file a move moved, or of a file
    inside the folder it moved, named at the new place and nothing inside
    the old one (U4b, opKinds.wholeOps). At or inside `to` is part_inside,
    without regard to case (U4b2-9)."""
    if move.get("kind") != "move" or edit.get("kind") not in EDIT_KINDS or "path" not in edit:
        return False
    if "linkSha" in move:
        # A link's move carries nothing (review 1 of U4b2-14).
        return False
    if part_inside(move["to"], edit["path"]) is None:
        return False
    if is_case_only_move(move):
        # One place under two spellings: named at the new one. Only the
        # moved item's own part is compared as spelled (review 1 of
        # U4b2-9, L3).
        depth = len(move["from"].split("/"))
        return edit["path"].split("/")[depth - 1] != move["from"].split("/")[depth - 1]
    return not places_overlap(move["from"], edit["path"])


def is_case_only_move(op):
    """UndoOp.isCaseOnlyMove (U4b): a move whose from and to are spelled
    alike but for case, in their last part only. The model's pages are
    keyed as spelled, as on a case-sensitive volume, where the ordinary
    pair rule gives the answers the spelling a case-insensitive folder
    lists gives."""
    if op.get("kind") != "move":
        return False
    source, destination = op.get("from"), op.get("to")
    if not isinstance(source, str) or not isinstance(destination, str) or source == destination:
        return False
    if source.lower() != destination.lower():
        return False
    return source.rsplit("/", 1)[0] == destination.rsplit("/", 1)[0] if "/" in source else "/" not in destination


def carried_edits(ops):
    """Each edit's path a move of the step carries (the edit after the
    move), with that move."""
    found = {}
    for index, move in enumerate(ops):
        for edit in ops[index + 1:]:
            if move_carries(move, edit):
                found[edit["path"]] = move
    return found


def swap_groups(ops, backward):
    """The order a swap makes a step's changes in (UndoCheck.plan's targets),
    one group of ops per target: forward, each move that carries edits
    first, then each file in the order the ops first name it, then every
    other whole op; backward, each file in the reversed ops' order, then
    every whole op, reversed (U4b, opKinds.wholeOps' order)."""
    ordered = list(reversed(ops)) if backward else list(ops)
    carriers = carried_edits(ops)
    carrying = [op for op in ordered if any(carrier is op for carrier in carriers.values())]
    leading = [] if backward else [[op] for op in carrying]
    files, by_path, wholes = [], {}, []
    for op in ordered:
        if op["kind"] == "recompute" or any(group[0] is op for group in leading):
            continue
        if op["kind"] in WHOLE_KINDS:
            wholes.append([op])
            continue
        if op["path"] not in by_path:
            by_path[op["path"]] = []
            files.append(by_path[op["path"]])
        by_path[op["path"]].append(op)
    return leading + files + wholes


def stopped_part_way(ops, backward, pages, swapped):
    """What a step's swap leaves when its process is killed before the
    target numbered `swapped` (None: every target in): each group made in
    turn, judged and moved on its own."""
    pages = dict(pages)
    groups = swap_groups(ops, backward)
    for group in groups[:len(groups) if swapped is None else swapped]:
        result = plan(group, backward, pages)
        assert result[0] == "ready", result
        for path, text in result[1].items():
            if text is None:
                pages.pop(path, None)
            else:
                pages[path] = text
    return pages


def move_is_at_its_old_place(move, pages):
    """Nothing at a move's `to` and something at its `from`."""
    def there(place):
        return pages.get(place) is not None or folder_of_pages(pages, place) is not None
    return not there(move["to"]) and there(move["from"])


def recovery_states(ops, pages):
    """UndoRecovery.fileStates: where each place of a step stands now. An
    edit a move carries is read where its folder is now, and the move is
    judged as if the step's edits inside it were taken back (U4b). The
    model holds no staged files, so it cannot show the swap's own kept
    originals inside the folder being left out: only the Swift replay
    shows that."""
    carriers = carried_edits(ops)
    states = {}
    for op in ops:
        kind = op["kind"]
        if kind == "recompute":
            continue
        if kind in WHOLE_KINDS:
            place = op.get("path") or op.get("from") or op.get("target")
            seen = pages
            if any(carrier is op for carrier in carriers.values()):
                old_place = move_is_at_its_old_place(op, pages)
                seen = dict(pages)
                for path, carrier in carriers.items():
                    if carrier is not op:
                        continue
                    side = place_before_the_move(path, carrier) if old_place else path
                    edits = [dict(edit, path=side) for edit in ops if edit.get("path") == path]
                    taken_back = plan(edits, True, seen)
                    if taken_back[0] == "ready" and side in taken_back[1]:
                        seen[side] = taken_back[1][side]
            states[place] = whole_state(op, seen)
            continue
        path = op["path"]
        read_path = path
        carrier = carriers.get(path)
        if carrier is not None and move_is_at_its_old_place(carrier, pages):
            read_path = place_before_the_move(path, carrier)
        state = op_state(op, pages.get(read_path))
        earlier = states.get(path)
        states[path] = state if earlier in (None, state) else "neither"
    return states


def recover(ops, pages, started_from_before):
    """UndoRecovery.settle, live: nothing took effect, completed, or what
    took effect put back, judged by content alone; anything neither is in
    the way. Answers (outcome, pages)."""
    start, end = ("before", "after") if started_from_before else ("after", "before")
    states = recovery_states(ops, pages)
    if any(state == "neither" for state in states.values()):
        return ("interrupted", pages)
    if all(state == start for state in states.values()):
        return ("nothingTookEffect", pages)
    if all(state == end for state in states.values()):
        return ("completed", pages)
    at_end = [op for op in ops if op["kind"] != "recompute"
              and states.get(op.get("path") or op.get("from") or op.get("target")) == end]
    result = plan(at_end, started_from_before, pages)
    if result[0] != "ready":
        return ("interrupted", pages)
    pages = dict(pages)
    for path, text in result[1].items():
        if text is None:
            pages.pop(path, None)
        else:
            pages[path] = text
    return ("rolledBack", pages)


def folder_of_pages(pages, place):
    """A folder the model holds as its files (U4b): the files under `place`
    as a tree, or None when it holds none."""
    prefix = place + "/"
    files = {}
    folders = set()
    for path, value in pages.items():
        if isinstance(path, str) and path.startswith(prefix) and value is not None and not isinstance(value, tuple):
            inside = path[len(prefix):]
            files[inside] = value
            parts = inside.split("/")[:-1]
            for depth in range(1, len(parts) + 1):
                folders.add("/".join(parts[:depth]))
    if not files:
        return None
    return {"folders": sorted(folders), "files": files}


WHOLE_KINDS = ("move", "moveApart", "setAside", "createTree", "removeTree", "external")
SCHEDULED_DEPLOY = "scheduledDeploy:"


def stands_apart(op):
    """UndoOp.standsApart: a moveApart, a setAside, or an external op on a
    deploy set for later."""
    if op["kind"] in ("moveApart", "setAside"):
        return True
    return op["kind"] == "external" and op.get("target", "").startswith(SCHEDULED_DEPLOY)


def set_or_leave_apart(model, result):
    """The swap of an Undo or a Redo (UndoSwap.swap's leaveApart): a deploy
    set for later that cannot be set now (launchd refuses it, or the write
    is off the main thread: `refuses_schedules`) is left as it is and named
    after what the check left apart; the rest goes in."""
    changes = {}
    left_apart = list(result[2])
    model.starts_at_the_next_login = []
    for path, text in result[1].items():
        if model.refuses_schedules and path.startswith(SCHEDULED_DEPLOY):
            left_apart.append(path)
            continue
        if model.schedules_start_at_the_next_login and path.startswith(SCHEDULED_DEPLOY) and text is not None:
            # Back on disk, not started now: it starts at the next login,
            # named so, never as left apart (the re-review of U3b's fixes,
            # LOW 2; UndoExternalWrite.startsAtTheNextLogin).
            model.starts_at_the_next_login.append(path)
        changes[path] = text
    return changes, left_apart
LINKED_OUTSIDE = "\0linkedOutside"
# What a deploy after a rollover onto a new website writes in the place the
# marker left (an action trace's `deploy` call, U3b).
DEPLOYED_MARKER = "{\"site_id\": \"this-year\"}"


def page_item(value):
    """A model page as an item spec: text, a tree (("tree", listing sha)),
    a link (("link", its target), U4b2-14), a preference value, or absent
    (None)."""
    if value is None:
        return {"absent": True}
    if isinstance(value, tuple) and value[0] == "tree":
        return {"treeSha": value[1]}
    if isinstance(value, tuple) and value[0] == "link":
        return {"link": value[1]}
    return {"text": value}


def whole_state(op, pages):
    kind = op["kind"]
    if kind in ("move", "moveApart", "setAside"):
        def side(place):
            if pages.get(place) is None and "listingSha" in op:
                tree = folder_of_pages(pages, place)
                if tree is not None:
                    return {"tree": tree}
            return page_item(pages.get(place))
        return move_state(op, side(op["from"]), side(op["to"]))
    if kind in ("createTree", "removeTree"):
        return tree_state(op, page_item(pages.get(op["path"])))
    target = op["target"]
    if target in pages:
        return external_state(op, {"preference": pages[target]})
    return external_state(op, {"absent": True})


def whole_moved(op, backward, pages):
    kind = op["kind"]
    if kind in ("move", "moveApart", "setAside"):
        source, destination = (op["to"], op["from"]) if backward else (op["from"], op["to"])
        if pages.get(source) is None and "listingSha" in op:
            # A folder held as its files: each one moves (U4b).
            moved = {}
            prefix = source + "/"
            for path, value in pages.items():
                if isinstance(path, str) and path.startswith(prefix):
                    moved[path] = None
            for path, value in pages.items():
                if isinstance(path, str) and path.startswith(prefix):
                    moved[destination + path[len(source):]] = value
            return moved
        return {destination: pages.get(source), source: None}
    if kind in ("createTree", "removeTree"):
        makes = (kind == "createTree") != backward
        return {op["path"]: ("tree", op["listingSha"]) if makes else None}
    wanted = "before" if backward else "after"
    return {op["target"]: op[wanted] if wanted in op else None}


def hunk_moved(op, backward, text):
    if text is None:
        return None
    data = text.encode("utf-8")
    before = (op["contextBefore"] + op["before"] + op["contextAfter"]).encode("utf-8")
    after = (op["contextBefore"] + op["after"] + op["contextAfter"]).encode("utf-8")
    source, target = (after, before) if backward else (before, after)
    start = hunk_place(source, target, data)
    if start is None:
        return None
    return (data[:start] + target + data[start + len(source):]).decode("utf-8")


def json_moved(op, backward, text):
    """The member moved by the member rule (json_bytes_moved): only its own
    bytes change, as on both apps, so an action trace's settings file
    (U4a, Course Settings) hashes the same after an Undo on every side."""
    if text is None:
        return None
    moved = json_bytes_moved(op, backward, text.encode("utf-8"))
    if moved is None:
        return None
    return moved.decode("utf-8")


# --------------------------------------------------------------------------
# The list: linear, one for the app.
# --------------------------------------------------------------------------

GRACE_DAYS = 30
CLOCK_TOLERANCE_DAYS = 1.0
# UndoSwitch.undoRefusedForMissingContentClearsTheList (held question M9).
UNDO_REFUSED_FOR_MISSING_CONTENT_CLEARS = True


class Model:
    """The list, as UndoFold and UndoPruning keep it. Times are in days
    from an arbitrary zero; `clock` is what the computer's clock reads."""

    def __init__(self, pages=None):
        if pages is None:
            pages = {PATHS[page_id]: START[page_id] for page_id in PAGE_IDS}
        self.pages = pages
        self.steps = []        # dicts: seq, ops, phase, made, readable, clearedInFlight, dead
        self.barriers = []     # seq numbers of lines this version cannot read
        self.highest = 0
        self.last_clearing = 0
        self.clock = 0.0
        self.newest_written = None
        self.unreachable = set()   # working folders that cannot be reached
        self.content_removed = False   # the list's content/ was taken away
        # U3c: texts written back into the list after its content was taken
        # away, the kept originals beside each page ({path: [text, ...]}),
        # whether the list takes new content, and how many 'undo kept what
        # it replaced' lines were written.
        self.stored = set()
        self.kept = {}
        self.content_cannot_be_stored = False
        # The second review of U3c: texts whose blob alone is gone from the
        # list, and texts the list will not take again.
        self.removed_texts = set()
        self.unstorable_texts = set()
        self.kept_what_it_replaced_lines = 0
        self.kept_unreadable = False   # every kept original cannot be read now
        self.maintainer_registered = True   # UndoMaintainers has a runner
        self.linked_outside = set()   # folders replaced by a link to outside
        self.rederived = 0   # how many times a recompute's runner ran
        self.refuses_schedules = False   # every write to a scheduledDeploy fails
        self.schedules_start_at_the_next_login = False   # a scheduledDeploy set back is not started now
        self.starts_at_the_next_login = []   # what the last undo or redo named so

    # -- the fold -----------------------------------------------------

    def write_line(self):
        if self.newest_written is None or self.clock > self.newest_written:
            self.newest_written = self.clock

    def on_list(self):
        return [step for step in self.steps if step["phase"] in ("done", "undone", "begun")]

    def effective_times(self):
        result = {}
        running = None
        for step in self.steps:
            if running is None or step["made"] > running:
                running = step["made"]
            result[step["seq"]] = running
        return result

    def reference_time(self):
        judged = self.clock
        for time in self.effective_times().values():
            if time > judged and time - self.clock <= CLOCK_TOLERANCE_DAYS:
                judged = time
        return judged

    def offer(self):
        """UndoFold.offer: (undo, redo, offered seqs); undo and redo are a
        step dict, 'nothing', 'busy' or 'notReadable'."""
        judged = self.reference_time()
        times = self.effective_times()
        listed = self.on_list()
        expired = 0
        for step in listed:
            if times[step["seq"]] < judged - DAYS_KEPT:
                expired = step["seq"]
        remaining = [step for step in listed if step["seq"] > expired]
        skip = max(0, len(remaining) - STEPS_KEPT)
        if skip:
            expired = max(expired, remaining[skip - 1]["seq"])
        offered = remaining[skip:]
        newest = None
        for step in offered:
            if step["phase"] != "undone":
                newest = step
        blocked = False
        for seq in self.barriers:
            if seq <= self.last_clearing or seq <= expired:
                continue
            if newest is None or seq >= newest["seq"]:
                blocked = True
        for step in listed:
            if not step["readable"] and step["seq"] > expired and (newest is None or step["seq"] >= newest["seq"]):
                blocked = True
        if newest is not None and newest["phase"] == "begun":
            return ("busy", "busy", offered)
        floor = newest["seq"] if newest else 0
        redo = "nothing"
        for step in offered:
            if step["phase"] == "undone" and step["seq"] > floor:
                redo = step
                break
        undo = newest if newest is not None else "nothing"
        if blocked:
            return ("notReadable", "notReadable", offered)
        if undo != "nothing" and not undo["readable"]:
            return ("notReadable", "notReadable", offered)
        if redo != "nothing" and not redo["readable"]:
            redo = "notReadable"
        return (undo, redo, offered)

    def head(self):
        found = None
        for step in self.offer()[2]:
            if step["phase"] == "done":
                found = step
        return found

    def summary(self):
        head = self.head()
        redo = self.offer()[1]
        return {"head": head["seq"] if head else None,
                "redo": redo["seq"] if isinstance(redo, dict) else None}

    def offered_seqs(self):
        return [step["seq"] for step in self.offer()[2]]

    # -- writing --------------------------------------------------------

    def begin(self, ops, readable=True, made=None, dead=False):
        self.highest += 1
        seq = self.highest
        self.steps.append({"seq": seq, "ops": ops, "phase": "begun",
                           "made": self.clock if made is None else made,
                           "readable": readable, "clearedInFlight": False, "dead": dead})
        self.write_line()
        return seq

    def note(self):
        """A neutral line: every reader passes over it."""
        self.write_line()

    def finish(self, seq, phase="done"):
        step = self.find(seq)
        for other in self.steps:
            if other["phase"] == "undone" and other["seq"] < seq and phase == "done":
                other["phase"] = "dropped"
        if step["clearedInFlight"] and phase in ("done", "undone"):
            phase = "cleared"
        step["phase"] = phase
        self.write_line()
        self.prune()

    def find(self, seq):
        for step in self.steps:
            if step["seq"] == seq:
                return step
        return None

    def foreign_line(self):
        """A line from a newer version: its number counts, nothing else."""
        self.highest += 1
        self.barriers.append(self.highest)
        self.write_line()
        return self.highest

    def ops_step(self, ops):
        """JournaledWrite.perform(ops:): written down, then planned forward
        from the pages as a Redo is, then made."""
        seq = self.begin(ops)
        result = plan(ops, False, self.pages)
        if result[0] != "ready":
            self.finish(seq, phase="failed")
            return result
        self.write(result[1])
        self.finish(seq)
        return ("applied", seq)

    def files_step(self, changes, recomputes, moves=(), members=(), trees=()):
        """JournaledWrite.perform(UndoStepDraft): one action's files, each
        before and after, as ops (lines where they reproduce the change,
        otherwise the whole file), in the order the action planned them,
        the recompute ops last. ('applied', seq, ops) or ('changedNothing',)."""
        ops = []
        for path, before, after in changes:
            if before == after:
                continue
            # U4a: a JSON file planned member by member is its editJSON ops,
            # in the order recorded.
            file_members = [member for member in members if member["path"] == path]
            if file_members:
                for member in file_members:
                    op = {"kind": "editJSON", "path": path, "keyPath": member["keyPath"]}
                    for side in ("before", "after"):
                        if side in member:
                            op[side] = member[side]
                    ops.append(op)
                continue
            ops.extend(ops_for_change(path, before, after))
        for moved in moves:
            # U3b: each file moved, after the files (JournaledStep's order).
            ops.append({"kind": "moveApart" if moved.get("standsApart") else "move",
                        "from": moved["from"], "to": moved["to"], "sha": sha(moved["content"])})
        for tree in trees:
            # U4a: each folder made, after the moves (JournaledStep's order).
            ops.append({"kind": "createTree", "path": tree["path"], "listingSha": listing_sha(tree)})
        if not ops:
            return ("changedNothing",)
        for kept in recomputes:
            ops.append({"kind": "recompute", "path": kept["path"], "maintainer": kept["maintainer"],
                        "section": kept.get("section")})
        seq = self.begin(ops)
        for path, before, after in changes:
            if after is None:
                self.pages.pop(path, None)
            else:
                self.pages[path] = after
        for moved in moves:
            self.pages[moved["to"]] = self.pages.pop(moved["from"])
        for tree in trees:
            self.pages[tree["path"]] = ("tree", listing_sha(tree))
        self.finish(seq)
        return ("applied", seq, ops)

    def holds_a_recompute(self, step):
        return any(op["kind"] == "recompute" for op in step["ops"])

    def step(self, edits, days_ago=0, pages_key=None):
        """edits: [(path, key, line)] -> ('applied', seq) or ('changedNothing',)."""
        ops = []
        new_pages = dict(self.pages)
        for path, key, line in edits:
            text = new_pages.get(path)
            if text is None:
                continue
            changed = setting_entry(key, line, text)
            if changed is None:
                continue
            new_pages[path] = changed
        for path in sorted(new_pages):
            if new_pages[path] != self.pages.get(path):
                ops.extend(ops_for_change(path, self.pages.get(path), new_pages[path]))
        if not ops:
            return ("changedNothing",)
        seq = self.begin(ops, made=self.clock - days_ago)
        self.pages = new_pages
        self.finish(seq)
        return ("applied", seq)

    def prune(self):
        """UndoPruning.prune: one oldest run, past 50 or past 30 + 30 days.
        A dead process's step still in flight is closed `interrupted` there
        rather than stopping the run; a running one stops it."""
        trust = self.newest_written is None or self.newest_written - self.clock <= CLOCK_TOLERANCE_DAYS
        times = self.effective_times()
        listed = self.on_list()
        remaining = len(listed)
        for step in listed:
            too_many = remaining > STEPS_KEPT
            too_old = trust and times[step["seq"]] < self.clock - (DAYS_KEPT + GRACE_DAYS)
            if step["phase"] == "begun":
                if not step["dead"] or (not too_many and not too_old):
                    break
                step["phase"] = "interrupted"
                remaining -= 1
                continue
            if not too_many and not too_old:
                break
            step["phase"] = "pruned"
            remaining -= 1

    def clear(self):
        """A `cleared` line: done and undone steps leave the list, and a step
        in flight leaves it when its work ends (one rule for every clearing)."""
        if not any(step["phase"] in ("done", "undone", "begun") for step in self.steps):
            return False
        self.last_clearing = self.highest
        for step in self.steps:
            if step["phase"] in ("done", "undone"):
                step["phase"] = "cleared"
            elif step["phase"] == "begun":
                step["clearedInFlight"] = True
        self.write_line()
        return True

    def newest_in_flight(self):
        found = None
        for step in self.offer()[2]:
            if step["phase"] != "undone":
                found = step
        return found

    def busy(self):
        """What a step in flight at the top makes of Undo and Redo: not
        available when its process is gone and its folder cannot be
        reached (ruling 10), otherwise under way."""
        step = self.newest_in_flight()
        if step is not None and step["dead"] and self.folder_of(step) in self.unreachable:
            return ("notAvailable",)
        return ("anotherChangeIsUnderWay",)

    def folder_of(self, step):
        for op in step["ops"]:
            if op.get("path", "").startswith("@"):
                return op["path"].split("/", 1)[0]
        return "@A"

    def undo(self, dry=False):
        undo, _, _ = self.offer()
        if undo == "nothing":
            return ("nothingToUndo",)
        if undo == "busy":
            return self.busy()
        if undo == "notReadable":
            return ("notAvailable",)
        if self.folder_of(undo) in self.unreachable:
            return ("notAvailable",)
        if self.holds_a_recompute(undo) and not self.maintainer_registered:
            return ("notAvailable",)
        used = []
        result = plan(undo["ops"], True, dict(self.pages, **{LINKED_OUTSIDE: self.linked_outside}), self.content_missing(),
                      self.available, used, leaves_apart=True)
        used = self.taken_from_kept_originals(used)
        if result[0] == "contentMissing" and self.kept_unreadable and self.kept.get(result[1]):
            # A kept original that cannot be read may be the one: cannot
            # tell now, the list kept (the first review of U3c, LOW 5).
            return ("cannotTellNow", result[1])
        if result[0] == "contentMissing" and not UNDO_REFUSED_FOR_MISSING_CONTENT_CLEARS:
            return result
        if result[0] in ("changedSince", "contentMissing"):
            if not dry:
                self.clear()
                self.prune()
            return result
        changes, left_apart = set_or_leave_apart(self, result)
        if not dry:
            not_whole = self.store_what_kept_originals_give(used)
            if self.store_what_the_other_direction_needs(undo["ops"], True, used):
                not_whole = True
            self.write(changes)
            if self.holds_a_recompute(undo):
                self.rederived += 1
            undo["phase"] = "undone"
            self.write_line()
            self.tidy_kept_copies()
            self.remove_superseded_kept_copies()
            if not_whole:
                # The Redo stays offered, resting on what is kept beside the
                # page (Russell's ruling of 2026-11-20, night).
                self.kept_what_it_replaced_lines += 1
            self.prune()
        return ("undone", undo["seq"], left_apart)

    def redo(self, dry=False):
        _, candidate, _ = self.offer()
        if candidate == "nothing":
            return ("nothingToRedo",)
        if candidate == "busy":
            return self.busy()
        if candidate == "notReadable":
            return ("notAvailable",)
        if self.folder_of(candidate) in self.unreachable:
            return ("notAvailable",)
        if self.holds_a_recompute(candidate) and not self.maintainer_registered:
            return ("notAvailable",)
        used = []
        result = plan(candidate["ops"], False, dict(self.pages, **{LINKED_OUTSIDE: self.linked_outside}), self.content_missing(),
                      self.available, used, leaves_apart=True)
        used = self.taken_from_kept_originals(used)
        if result[0] in ("changedSince", "contentMissing"):
            if not dry:
                # Ruling 20: refused once, then only the redo branch goes.
                for step in self.steps:
                    if step["phase"] == "undone" and step["seq"] >= candidate["seq"]:
                        step["phase"] = "dropped"
                self.write_line()
            return result
        changes, left_apart = set_or_leave_apart(self, result)
        if not dry:
            not_whole = self.store_what_kept_originals_give(used)
            if self.store_what_the_other_direction_needs(candidate["ops"], False, used):
                not_whole = True
            self.write(changes)
            if self.holds_a_recompute(candidate):
                self.rederived += 1
            candidate["phase"] = "done"
            self.write_line()
            self.tidy_kept_copies()
            self.remove_superseded_kept_copies()
            if not_whole:
                # Its Undo stays offered, resting on what is kept beside the
                # page; cleared only if it is refused then (Russell's ruling
                # of 2026-11-20, night).
                self.kept_what_it_replaced_lines += 1
            self.prune()
        return ("redone", candidate["seq"], left_apart)

    def content_missing(self):
        """Whether any content the list held is gone: all of it, or one blob."""
        return self.content_removed or bool(self.removed_texts)

    def in_the_list(self, text):
        """Whether the list's content holds this text now."""
        if text in self.stored:
            return True
        return not self.content_removed and text not in self.removed_texts

    def storable(self, text):
        """Whether the list would take this text now."""
        return not self.content_cannot_be_stored and text not in self.unstorable_texts

    def available(self, path, text):
        """Content the step needs: in the list, written back since, or a
        kept original beside its page that can be read now."""
        if self.in_the_list(text):
            return True
        return not self.kept_unreadable and text in self.kept.get(path, [])

    def taken_from_kept_originals(self, used):
        """Of the plan's uses, those the list itself could not give: only
        those are taken from a kept original."""
        return [use for use in used if not self.in_the_list(use[1])]

    def store_what_kept_originals_give(self, used):
        """Before the swap (the first review of U3c, MEDIUM): the kept
        original's text, and what the page held as the other direction's
        text when it is exactly that, written back into the list. True when
        anything could not be: what the page held is then kept beside it,
        and a kept original whose own text the list would not take stays
        (the second review's MEDIUM: `tidy_kept_copies` keeps it)."""
        not_whole = False
        for path, taken, outgoing, other in used:
            if self.storable(taken):
                self.stored.add(taken)
            else:
                not_whole = True
            if other is None or self.in_the_list(other):
                continue
            if outgoing == other and self.storable(outgoing):
                self.stored.add(outgoing)
                continue
            not_whole = True
            self.kept.setdefault(path, []).append(outgoing)
        return not_whole

    def store_what_the_other_direction_needs(self, ops, backward, used):
        """Before the swap (U4a, the U3c review 3 LOW 3 fix): each page a
        whole-file op moves from the list, whose outgoing text the other
        direction needs and the list lacks, has that text written into the
        list; when the list will not take it, it is kept beside the page
        instead, unless a kept copy there already holds it. True when
        anything is kept beside a page."""
        taken_from_kept = set(use[0] for use in used)
        kept_any = False
        for op in ops:
            if op["kind"] != "writeFile" or op["path"] in taken_from_kept:
                continue
            path = op["path"]
            other = op["afterText"] if backward else op["beforeText"]
            if other is None or self.in_the_list(other) or self.pages.get(path) != other:
                continue
            if self.storable(other):
                self.stored.add(other)
                continue
            if other in self.kept.get(path, []):
                continue
            self.kept.setdefault(path, []).append(other)
            kept_any = True
        return kept_any

    def remove_superseded_kept_copies(self):
        """UndoRecovery.removeSupersededKeptCopies (U3c review 3, LOW 1):
        after each move, the kept copies beside a page thinned to one per
        content, so Undo and Redo again and again never pile them up."""
        for path in list(self.kept):
            one_of_each = []
            for text in self.kept[path]:
                if text not in one_of_each:
                    one_of_each.append(text)
            self.kept[path] = one_of_each

    def tidy_kept_copies(self):
        """A kept original whose page holds the same text is a copy: gone,
        unless the list does not hold that text (the second review of U3c,
        MEDIUM)."""
        for path in list(self.kept):
            self.kept[path] = [text for text in self.kept[path]
                               if text != self.pages.get(path) or not self.in_the_list(text)]
            if not self.kept[path]:
                del self.kept[path]

    def write(self, changes):
        for path, text in changes.items():
            if text is None:
                self.pages.pop(path, None)
            else:
                self.pages[path] = text

    def hand_edit(self, kind, page_id):
        return self.hand_edit_path(kind, PATHS[page_id])

    def hand_edit_path(self, kind, path):
        text = self.pages.get(path)
        if text is None:
            return False
        if not isinstance(text, str) and kind != "deletePage":
            # A folder (U4a, Add folder's tree): only removing it changes it.
            return False
        if kind == "body":
            self.pages[path] = text + "A line the teacher wrote in Obsidian.\n"
            return True
        if kind == "deletePage":
            del self.pages[path]
            return True
        layout = layout_of(text)
        if layout is None:
            return False
        key = "title" if kind == "otherKey" else "publish"
        found = layout.entries_for(key)
        if len(found) != 1:
            return False
        lines = list(layout.lines)
        entry = found[0]
        old = lines[entry[1]]
        ending = "\r" if old.endswith("\r") else ""
        lines[entry[1]] = trim_cr(old) + " (edited)" + ending if kind == "otherKey" else trim_cr(old) + " # checked" + ending
        self.pages[path] = "\n".join(lines)
        return True


# --------------------------------------------------------------------------
# Generating the traces.
# --------------------------------------------------------------------------

def one_trace(rng, number):
    model = Model()
    calls = []
    length = rng.randint(SHORTEST, LONGEST)
    attempts = 0
    redo_next = False
    while len(calls) < length and attempts < length * 20:
        attempts += 1
        roll = rng.random()
        if redo_next:
            roll = 0.70
            redo_next = False
        if roll < 0.40:
            published = rng.random() < 0.6
            chosen = rng.sample(PAGE_IDS, rng.randint(1, 3))
            line = "publish: true" if published else "publish: false"
            edits = [(page_id, "publish", line) for page_id in sorted(chosen)]
            outcome = model.step([(PATHS[page_id], key, value) for page_id, key, value in edits])
            call = {"call": "step", "action": "publishPages" if published else "hidePages",
                    "set": [{"page": page_id, "key": key, "line": value} for page_id, key, value in edits],
                    "expect": outcome[0]}
            if outcome[0] == "applied":
                call["seq"] = outcome[1]
        elif roll < 0.65:
            outcome = model.undo()
            call = {"call": "undo", "expect": outcome[0]}
            if outcome[0] == "undone":
                call["seq"] = outcome[1]
            if outcome[0] == "changedSince":
                call["page"] = page_named(outcome[1])
                call["others"] = outcome[2]
                call["clearedTheList"] = True
        elif roll < 0.80:
            outcome = model.redo()
            call = {"call": "redo", "expect": outcome[0]}
            if outcome[0] == "redone":
                call["seq"] = outcome[1]
            if outcome[0] == "changedSince":
                call["page"] = page_named(outcome[1])
                call["others"] = outcome[2]
                call["droppedTheRedo"] = True
        elif roll < 0.86:
            # U2: a page moved aside to the section's Archive folder, one
            # `move` judged as a pair (opKinds.move), through the door that
            # plans a step forward.
            present = [page_id for page_id in PAGE_IDS
                       if model.pages.get(PATHS[page_id]) is not None
                       and model.pages.get(archived(PATHS[page_id])) is None]
            if not present:
                continue
            page_id = rng.choice(present)
            source = PATHS[page_id]
            outcome = model.ops_step([{"kind": "move", "from": source, "to": archived(source),
                                       "sha": sha(model.pages[source])}])
            call = {"call": "move", "page": page_id, "to": archived(source), "expect": outcome[0]}
            if outcome[0] == "applied":
                call["seq"] = outcome[1]
        elif roll < 0.95:
            kind = rng.choice(["body", "body", "otherKey", "sameLine", "deletePage"] if rng.random() < 0.2
                              else ["body", "body", "otherKey", "sameLine"])
            page_id = rng.choice(PAGE_IDS)
            candidate = model.offer()[1]
            if isinstance(candidate, dict) and rng.random() < 0.5:
                # Half the time, a page the next Redo would change, so the
                # traces hold refused redos (ruling 20) as well as undos.
                page_id = page_named(rng.choice([op.get("path") or op.get("from") for op in candidate["ops"]]))
                kind = "sameLine"
                redo_next = rng.random() < 0.5
            if not model.hand_edit(kind, page_id):
                redo_next = False
                continue
            call = {"call": "handEdit", "kind": kind, "page": page_id}
        else:
            model.note()
            call = {"call": "note"}
        call.update(model.summary())
        calls.append(call)

    # Then undo everything that can be, and redo everything that can be.
    while True:
        outcome = model.undo()
        call = {"call": "undo", "expect": outcome[0]}
        if outcome[0] == "undone":
            call["seq"] = outcome[1]
            if outcome[2]:
                call["leftApart"] = outcome[2]
        if outcome[0] == "changedSince":
            call["page"] = page_named(outcome[1])
            call["others"] = outcome[2]
            call["clearedTheList"] = True
        call.update(model.summary())
        calls.append(call)
        if outcome[0] != "undone":
            break
    undone_to = final_hashes(model)
    while True:
        outcome = model.redo()
        call = {"call": "redo", "expect": outcome[0]}
        if outcome[0] == "redone":
            call["seq"] = outcome[1]
            if outcome[2]:
                call["leftApart"] = outcome[2]
        if outcome[0] == "changedSince":
            call["page"] = page_named(outcome[1])
            call["others"] = outcome[2]
            call["droppedTheRedo"] = True
        call.update(model.summary())
        calls.append(call)
        if outcome[0] != "redone":
            break
    hand_edited = any(call["call"] == "handEdit" for call in calls)
    return {"name": "trace-%03d" % number, "handEdits": hand_edited, "calls": calls,
            "afterUndoingAll": undone_to, "final": final_hashes(model)}


def read_action_steps(path=None):
    """The recorded steps, or [] before the Mac has recorded any."""
    source = ACTION_STEPS if path is None else path
    if not source.exists():
        return []
    document = json.loads(source.read_bytes().decode("utf-8"))
    return document.get("steps", [])


def action_trace(rng, recorded, number):
    """One trace of a recorded action step: the step made from the files it
    names (their befores, an empty list), then undos, redos, hand edits of
    its files and notes, then the closing undos and redos."""
    files = recorded["files"]
    paths = [entry["path"] for entry in files]
    moves = recorded.get("moves", [])
    members = recorded.get("members", [])
    trees = recorded.get("trees", [])
    paths.extend(tree["path"] for tree in trees)
    pages = {}
    for entry in files:
        if entry["before"] is not None:
            pages[entry["path"]] = entry["before"]
    for moved in moves:
        pages[moved["from"]] = moved["content"]
        paths.extend([moved["from"], moved["to"]])
    apart = [moved for moved in moves if moved.get("standsApart")]
    model = Model(pages=dict(pages))
    calls = []
    changes = [(entry["path"], entry["before"], entry["after"]) for entry in files]
    outcome = model.files_step(changes, recorded.get("recomputes", []), moves, members, trees)
    call = {"call": "action", "step": recorded["name"], "expect": outcome[0]}
    if outcome[0] == "applied":
        call["seq"] = outcome[1]
        call["ops"] = [op["kind"] for op in outcome[2]]
    call.update(model.summary())
    calls.append(call)

    length = rng.randint(ACTION_SHORTEST, ACTION_LONGEST)
    attempts = 0
    while len(calls) < length and attempts < length * 20:
        attempts += 1
        roll = rng.random()
        if apart and roll >= 0.65 and roll < 0.75:
            # U3b: a deploy writes a new marker in the place a rollover's
            # marker left (when it is free), and nothing to the list.
            place = apart[0]["from"]
            if model.pages.get(place) is not None:
                continue
            model.pages[place] = DEPLOYED_MARKER
            call = {"call": "deploy", "path": place, "text": DEPLOYED_MARKER}
            call.update(model.summary())
            calls.append(call)
            continue
        if roll < 0.35:
            outcome = model.undo()
            call = {"call": "undo", "expect": outcome[0]}
            if outcome[0] == "undone":
                call["seq"] = outcome[1]
                if outcome[2]:
                    call["leftApart"] = outcome[2]
            if outcome[0] == "changedSince":
                call["path"] = outcome[1]
                call["others"] = outcome[2]
                call["clearedTheList"] = True
        elif roll < 0.65:
            outcome = model.redo()
            call = {"call": "redo", "expect": outcome[0]}
            if outcome[0] == "redone":
                call["seq"] = outcome[1]
                if outcome[2]:
                    call["leftApart"] = outcome[2]
            if outcome[0] == "changedSince":
                call["path"] = outcome[1]
                call["others"] = outcome[2]
                call["droppedTheRedo"] = True
        elif roll < 0.90:
            kind = rng.choice(["body", "body", "otherKey", "sameLine", "deletePage"])
            path = rng.choice(paths)
            if not model.hand_edit_path(kind, path):
                continue
            call = {"call": "handEdit", "kind": kind, "path": path}
        else:
            model.note()
            call = {"call": "note"}
        call.update(model.summary())
        calls.append(call)

    while True:
        outcome = model.undo()
        call = {"call": "undo", "expect": outcome[0]}
        if outcome[0] == "undone":
            call["seq"] = outcome[1]
            if outcome[2]:
                call["leftApart"] = outcome[2]
        if outcome[0] == "changedSince":
            call["path"] = outcome[1]
            call["others"] = outcome[2]
            call["clearedTheList"] = True
        call.update(model.summary())
        calls.append(call)
        if outcome[0] != "undone":
            break
    undone_to = path_hashes(model, paths)
    while True:
        outcome = model.redo()
        call = {"call": "redo", "expect": outcome[0]}
        if outcome[0] == "redone":
            call["seq"] = outcome[1]
            if outcome[2]:
                call["leftApart"] = outcome[2]
        if outcome[0] == "changedSince":
            call["path"] = outcome[1]
            call["others"] = outcome[2]
            call["droppedTheRedo"] = True
        call.update(model.summary())
        calls.append(call)
        if outcome[0] != "redone":
            break
    hand_edited = any(call["call"] == "handEdit" for call in calls)
    return {"name": "action-%03d" % number, "step": recorded["name"], "handEdits": hand_edited,
            "calls": calls, "afterUndoingAll": undone_to, "final": path_hashes(model, paths)}


def path_hashes(model, paths):
    """Each path's SHA-256 (null: absent); a folder's is its listing's."""
    result = {}
    for path in paths:
        text = model.pages.get(path)
        if isinstance(text, tuple):
            result[path] = text[1]
        else:
            result[path] = None if text is None else sha(text)
    return result


def archived(path):
    """Where a `move` call puts a fixture page: the section's Archive folder."""
    return path.replace("/Classes/", "/Archive/", 1)


def page_named(path):
    for page_id in PAGE_IDS:
        if PATHS[page_id] == path:
            return page_id
    return path


def final_hashes(model):
    result = {}
    for page_id in PAGE_IDS:
        text = model.pages.get(PATHS[page_id])
        result[page_id] = None if text is None else sha(text)
    return result


def generate(seed=SEED, count=TRACE_COUNT, steps=None):
    rng = random.Random(seed)
    traces = [one_trace(rng, number + 1) for number in range(count)]
    if steps is None:
        steps = read_action_steps()
    action_rng = random.Random(seed * 1000 + 3)
    action_traces = []
    for recorded in steps:
        for _ in range(ACTION_TRACES_PER_STEP):
            action_traces.append(action_trace(action_rng, recorded, len(action_traces) + 1))
    return {
        "note": "Generated by scripts/make_undo_traces.py (seed %d) - never edited by hand; run it again instead, and commit what it writes. Each trace starts from `fixture` in an empty working folder with an empty list; write each page from utf8Hex, its exact bytes (`text` is the same page for reading, but at least one JSON reader, Foundation's, drops a byte-order mark inside a string). A `step` sets each named page's top-level `key` to the exact `line` with JournaledWrite.settingEntry's rule (the entry replaced when the key is there once, inserted after the opening fence when it is not, a block made when the page has none, the page left alone when the key is there twice or the page is gone), and is recorded through the app's own door. `expect` is what the call must come to; `head` and `redo` are the step numbers the folded list must answer after it (null: none). `afterUndoingAll` is every page's SHA-256 (null: absent) once the closing run of undos has stopped; `final` the same after the closing run of redos. A `note` call appends one neutral note line (file-formats.json -> undoJournal.events.note: its seq the highest in the journal, with keys a reader does not know) and must change nothing. A `move` call (U2) moves the named page to `to`, in the section's Archive folder, as one `move` op (file-formats.json -> undoJournal.opKinds.move: from the page's path, its `sha` the SHA-256 of the page's bytes now) made through the door that plans a step's ops forward (the mac's JournaledWrite.perform(ops:)); a step or hand edit naming a page that is not at its path leaves it alone. A refused undo clears the list (clearedTheList); a refused redo drops only the redo branch (droppedTheRedo, ruling 20). A trace with no hand edits must end its undos exactly at the fixture. Rules: contracts/shared-rules.json -> undo." % seed,
        "seed": seed,
        "fixture": [{"page": page_id, "path": path, "text": text, "utf8Hex": text.encode("utf-8").hex(), "shape": shape}
                    for page_id, path, text, shape in FIXTURE],
        "fixtureHashes": {page_id: sha(START[page_id]) for page_id in PAGE_IDS},
        "traces": traces,
        "actionNote": "U3: the daily page actions' traces, made from contracts/undo-action-steps.json, where the Mac records each action's step from the real action code (UndoActionStepsTests; never typed by hand). Each starts in an empty working folder with an empty list, every file the step names written from its `before` (none when null). An `action` call makes the named recorded step through the door (the mac's JournaledWrite.perform with an UndoStepDraft: each file's before and after, its ops worked out by the door's own rule, editLine where the lines reproduce the change and writeFile otherwise, in the order recorded, then the step's recompute ops) and must come to `expect` with the op kinds `ops` in that order. Hand edits name a file by `path`; a refused undo or redo names the first file in the way by `path`. A step recorded with `moves` (U3b, the rollover) also writes each moved file's `content` at its `from` first, and its action is made through the door that takes every kind (the mac's JournaledWrite.perform(ops:)): the files' ops as above, then one `move` per moved file (`moveApart` when it standsApart), then the recompute ops; its moved places are hashed in `afterUndoingAll` and `final` too. A step recorded with `members` (U4a, Course Settings) has each file they name made as those editJSON ops, in the order recorded, instead of the door's rule (the member moved by the member rule's bytes, undo-json-cases.json -> editJSONCases); one recorded with `trees` (U4a, Add folder) also makes each folder as one `createTree` (its listing and every file's bytes in the list), after the moves; a folder is hashed as its listing's SHA-256 in `afterUndoingAll` and `final`, and only a `deletePage` hand edit changes one. A `deploy` call writes `text` at `path` (a new marker in the place a rollover's marker left) and nothing to the list; an undo or redo whose `leftApart` is given must name exactly those places as left apart (none when it is absent). Undo and Redo re-derive a recompute op as the app does (a front page whose course has no settings is left alone). `afterUndoingAll` and `final` are keyed by path. Everything else as `note` says.",
        "actionTraces": action_traces,
    }


def render(document):
    """Stable bytes: one call per line, so a diff of the file reads as calls."""
    out = ["{"]
    out.append('  "note": %s,' % json.dumps(document["note"], ensure_ascii=False))
    out.append('  "seed": %d,' % document["seed"])
    out.append('  "fixture": [')
    rows = [json.dumps(row, ensure_ascii=False) for row in document["fixture"]]
    out.append(",\n".join("    " + row for row in rows))
    out.append("  ],")
    out.append('  "fixtureHashes": %s,' % json.dumps(document["fixtureHashes"]))
    out.append('  "traces": [')
    traces = []
    for trace in document["traces"]:
        lines = ["    {"]
        lines.append('      "name": %s,' % json.dumps(trace["name"]))
        lines.append('      "handEdits": %s,' % json.dumps(trace["handEdits"]))
        lines.append('      "calls": [')
        lines.append(",\n".join("        " + json.dumps(call, ensure_ascii=False) for call in trace["calls"]))
        lines.append("      ],")
        lines.append('      "afterUndoingAll": %s,' % json.dumps(trace["afterUndoingAll"]))
        lines.append('      "final": %s' % json.dumps(trace["final"]))
        lines.append("    }")
        traces.append("\n".join(lines))
    out.append(",\n".join(traces))
    out.append("  ],")
    out.append('  "actionNote": %s,' % json.dumps(document["actionNote"], ensure_ascii=False))
    out.append('  "actionTraces": [')
    action_traces = []
    for trace in document["actionTraces"]:
        lines = ["    {"]
        lines.append('      "name": %s,' % json.dumps(trace["name"]))
        lines.append('      "step": %s,' % json.dumps(trace["step"]))
        lines.append('      "handEdits": %s,' % json.dumps(trace["handEdits"]))
        lines.append('      "calls": [')
        lines.append(",\n".join("        " + json.dumps(call, ensure_ascii=False) for call in trace["calls"]))
        lines.append("      ],")
        lines.append('      "afterUndoingAll": %s,' % json.dumps(trace["afterUndoingAll"], ensure_ascii=False))
        lines.append('      "final": %s' % json.dumps(trace["final"], ensure_ascii=False))
        lines.append("    }")
        action_traces.append("\n".join(lines))
    out.append(",\n".join(action_traces))
    out.append("  ]")
    out.append("}")
    return ("\n".join(out) + "\n").encode("utf-8")


def main(arguments):
    fuzz = os.environ.get("PLANTOIR_UNDO_FUZZ")
    seed = int(fuzz) if fuzz else SEED
    data = render(generate(seed))
    if "--print" in arguments:
        sys.stdout.buffer.write(data)
        return 0
    if "--check" in arguments:
        if CONTRACT.read_bytes().replace(b"\r\n", b"\n") != data:
            print("contracts/undo-traces.json is not what scripts/make_undo_traces.py writes; run it again.")
            return 1
        print("contracts/undo-traces.json is current.")
        return 0
    if fuzz:
        print("PLANTOIR_UNDO_FUZZ is set: use --print, so the committed traces stay the seeded ones.")
        return 2
    CONTRACT.write_bytes(data)
    made = generate(seed)
    print("wrote %s (%d traces, %d action traces, %d bytes)" % (CONTRACT.name, len(made["traces"]), len(made["actionTraces"]), len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
