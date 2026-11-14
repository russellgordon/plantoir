#!/usr/bin/env python3
"""
Writes contracts/undo-traces.json: sequences of steps, undos, redos, hand
edits and clearings for Undo and Redo (#899, piece U1), with what each call
must come to, replayed by BOTH apps' suites against their own journal.

The expected results are computed here by a reference model of the list:
the front-matter line model (`editLine`), the whole-file fallback
(`writeFile`), the all-or-nothing content check, the linear list (ruling 9),
the redo branch cut by any new step, and the whole list cleared when Undo
refuses a step whose line was changed by hand (ruling 13) or when a deploy
or a share of unit plans happens (rulings 14 and 16). The Swift
implementation in mac-app/QuartzTeachers/Models/Undo/ is written to the
same rules; a trace both agree on is evidence that the rules, not one
implementation's accidents, decide the outcome.

Deterministic: the same seed gives the same bytes, every run, on any
machine (scripts/test_make_undo_traces.py runs it twice and compares).
Pure stdlib.

    python3 scripts/make_undo_traces.py            # rewrite the contract
    python3 scripts/make_undo_traces.py --check    # exit 1 if it is stale
    PLANTOIR_UNDO_FUZZ=<seed> python3 scripts/make_undo_traces.py --print
"""
import hashlib
import json
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
     "a byte-order mark: the reader sees no block, so the step makes one and the mark stays"),
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
    """JournaledWrite.settingEntry: the traces' writer."""
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


def plan(ops, backward, pages_by_path):
    """UndoCheck.plan: ('ready', {path: new text or None}) or ('changedSince', first, others)."""
    ordered = list(reversed(ops)) if backward else list(ops)
    original = {}
    working = {}
    in_the_way = []
    for op in ordered:
        path = op["path"]
        if path not in original:
            original[path] = pages_by_path.get(path)
            working[path] = original[path]
        state = op_state(op, working[path])
        wanted_from = "after" if backward else "before"
        if state == "neither":
            if path not in in_the_way:
                in_the_way.append(path)
            continue
        if state != wanted_from:
            continue
        if op["kind"] == "writeFile":
            working[path] = op["beforeText"] if backward else op["afterText"]
        else:
            source = op["after"] if backward else op["before"]
            target = op["before"] if backward else op["after"]
            working[path] = moving(op, source, target, working[path])
    if in_the_way:
        return ("changedSince", in_the_way[0], len(in_the_way) - 1)
    changes = {}
    for path in original:
        if original[path] != working[path]:
            changes[path] = working[path]
    return ("ready", changes)


# --------------------------------------------------------------------------
# The list: linear, one for the app.
# --------------------------------------------------------------------------

class Model:
    def __init__(self):
        self.pages = {PATHS[page_id]: START[page_id] for page_id in PAGE_IDS}
        self.steps = []     # [seq, ops, phase]
        self.next_seq = 1

    def on_list(self):
        return [step for step in self.steps if step[2] in ("done", "undone")]

    def head(self):
        found = None
        for step in self.on_list():
            if step[2] == "done":
                found = step
        return found

    def redo_candidate(self):
        for step in self.on_list():
            if step[2] == "undone":
                return step
        return None

    def summary(self):
        head = self.head()
        redo = self.redo_candidate()
        return {"head": head[0] if head else None, "redo": redo[0] if redo else None}

    def step(self, edits, days_ago=0):
        """edits: [(page id, key, line)] -> ('applied', seq) or ('changedNothing',)."""
        ops = []
        new_pages = dict(self.pages)
        for page_id, key, line in edits:
            path = PATHS[page_id]
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
        for step in self.steps:
            if step[2] == "undone":
                step[2] = "dropped"
        seq = self.next_seq
        self.next_seq += 1
        self.steps.append([seq, ops, "done", days_ago])
        self.pages = new_pages
        self.prune()
        return ("applied", seq)

    def prune(self):
        """UndoPruning.prune: past 50 steps, oldest first; and older than 30 days."""
        listed = self.on_list()
        excess = len(listed) - STEPS_KEPT
        for step in listed:
            if excess > 0 or step[3] > DAYS_KEPT:
                step[2] = "pruned"
                excess -= 1

    def clear(self):
        for step in self.steps:
            if step[2] in ("done", "undone"):
                step[2] = "cleared"

    def undo(self, dry=False):
        head = self.head()
        if head is None:
            return ("nothingToUndo",)
        result = plan(head[1], True, self.pages)
        if result[0] == "changedSince":
            if not dry:
                self.clear()
            return result
        if not dry:
            self.write(result[1])
            head[2] = "undone"
        return ("undone", head[0])

    def redo(self, dry=False):
        candidate = self.redo_candidate()
        if candidate is None:
            return ("nothingToRedo",)
        result = plan(candidate[1], False, self.pages)
        if result[0] == "changedSince":
            return result
        if not dry:
            self.write(result[1])
            candidate[2] = "done"
        return ("redone", candidate[0])

    def write(self, changes):
        for path, text in changes.items():
            if text is None:
                self.pages.pop(path, None)
            else:
                self.pages[path] = text

    def hand_edit(self, kind, page_id):
        path = PATHS[page_id]
        text = self.pages.get(path)
        if text is None:
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
    while len(calls) < length and attempts < length * 20:
        attempts += 1
        roll = rng.random()
        if roll < 0.40:
            published = rng.random() < 0.6
            chosen = rng.sample(PAGE_IDS, rng.randint(1, 3))
            line = "publish: true" if published else "publish: false"
            edits = [(page_id, "publish", line) for page_id in sorted(chosen)]
            outcome = model.step(edits)
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
            dry = model.redo(dry=True)
            if dry[0] == "changedSince":
                # What a refused Redo does to the list is not ruled: no trace
                # depends on it.
                continue
            outcome = model.redo()
            call = {"call": "redo", "expect": outcome[0]}
            if outcome[0] == "redone":
                call["seq"] = outcome[1]
        elif roll < 0.95:
            kind = rng.choice(["body", "body", "otherKey", "sameLine", "deletePage"] if rng.random() < 0.2
                              else ["body", "body", "otherKey", "sameLine"])
            page_id = rng.choice(PAGE_IDS)
            if not model.hand_edit(kind, page_id):
                continue
            call = {"call": "handEdit", "kind": kind, "page": page_id}
        else:
            reason = rng.choice(["deploy", "shareUnitPlans"])
            model.clear()
            call = {"call": "clear", "reason": reason}
        call.update(model.summary())
        calls.append(call)

    # Then undo everything that can be, and redo everything that can be.
    while True:
        outcome = model.undo()
        call = {"call": "undo", "expect": outcome[0]}
        if outcome[0] == "undone":
            call["seq"] = outcome[1]
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
        if model.redo(dry=True)[0] == "changedSince":
            break
        outcome = model.redo()
        call = {"call": "redo", "expect": outcome[0]}
        if outcome[0] == "redone":
            call["seq"] = outcome[1]
        call.update(model.summary())
        calls.append(call)
        if outcome[0] != "redone":
            break
    hand_edited = any(call["call"] in ("handEdit", "clear") for call in calls)
    return {"name": "trace-%03d" % number, "handEdits": hand_edited, "calls": calls,
            "afterUndoingAll": undone_to, "final": final_hashes(model)}


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


def generate(seed=SEED, count=TRACE_COUNT):
    rng = random.Random(seed)
    traces = [one_trace(rng, number + 1) for number in range(count)]
    return {
        "note": "Generated by scripts/make_undo_traces.py (seed %d) - never edited by hand; run it again instead, and commit what it writes. Each trace starts from `fixture` in an empty working folder with an empty list; write each page from utf8Hex, its exact bytes (`text` is the same page for reading, but at least one JSON reader, Foundation's, drops a byte-order mark inside a string). A `step` sets each named page's top-level `key` to the exact `line` with JournaledWrite.settingEntry's rule (the entry replaced when the key is there once, inserted after the opening fence when it is not, a block made when the page has none, the page left alone when the key is there twice or the page is gone), and is recorded through the app's own door. `expect` is what the call must come to; `head` and `redo` are the step numbers the folded list must answer after it (null: none). `afterUndoingAll` is every page's SHA-256 (null: absent) once the closing run of undos has stopped; `final` the same after the closing run of redos. A trace with no hand edits and no clearings must end its undos exactly at the fixture. What a REFUSED redo does to the list is not ruled, so no trace contains one. Rules: contracts/shared-rules.json -> undo." % seed,
        "seed": seed,
        "fixture": [{"page": page_id, "path": path, "text": text, "utf8Hex": text.encode("utf-8").hex(), "shape": shape}
                    for page_id, path, text, shape in FIXTURE],
        "fixtureHashes": {page_id: sha(START[page_id]) for page_id in PAGE_IDS},
        "traces": traces,
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
        if CONTRACT.read_bytes() != data:
            print("contracts/undo-traces.json is not what scripts/make_undo_traces.py writes; run it again.")
            return 1
        print("contracts/undo-traces.json is current.")
        return 0
    if fuzz:
        print("PLANTOIR_UNDO_FUZZ is set: use --print, so the committed traces stay the seeded ones.")
        return 2
    CONTRACT.write_bytes(data)
    print("wrote %s (%d traces, %d bytes)" % (CONTRACT.name, len(generate(seed)["traces"]), len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
