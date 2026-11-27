#!/usr/bin/env python3
"""
Tests for scripts/make_undo_traces.py and the cases of
contracts/shared-rules.json -> undo (#899, piece U1).

Pure stdlib, no Docker, no network; Windows' suite runs this file through
PythonToolchainTests like every other scripts/test_*.py. What it pins:

- the generator is deterministic: two runs give the same bytes, and the
  committed contracts/undo-traces.json is exactly what it writes;
- the traces are well formed (twenty, of five to forty generated calls,
  each with an expectation and the list's head and redo after it);
- a trace with no hand edits ends its undos exactly at the fixture: undo-all
  is the identity;
- a refused undo clears the list, a refused redo drops only the redo
  (rulings 13 and 20), and no trace holds a deploy's clearing (ruling 17);
- the reference model agrees with the contract's own checkCases and
  stackCases, so the cases and the traces cannot drift apart;
- a reference of the deployed-ness rule agrees with deployedCases.

Run with:

    python3 -B scripts/test_make_undo_traces.py
"""
import json
import re
import unicodedata
import unittest
from pathlib import Path

import make_undo_traces as traces

REPO = Path(__file__).resolve().parent.parent


def shared_undo():
    with open(REPO / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
        return json.load(handle)["undo"]


def json_cases():
    # undo-json-cases.json: the editJSON byte cases, kept out of
    # shared-rules.json because Windows PowerShell 5.1 cannot read them (#899 W6).
    with open(REPO / "contracts" / "undo-json-cases.json", encoding="utf-8") as handle:
        return json.load(handle)


# The one contract file no PowerShell reads, because some of its rows must hold
# keys that differ only by case (ContractFilesWindowsPowerShellReadsTests).
NOT_FOR_WINDOWS_POWERSHELL = ["undo-json-cases.json"]


def windows_powershell_problems(text):
    """What would stop Windows PowerShell 5.1's ConvertFrom-Json reading this
    JSON text: an object with two keys equal ignoring case (it builds each
    object as a case-insensitive dictionary, comparing character by character
    as .NET's OrdinalIgnoreCase does), or an empty key. A model of the rule
    for this Mac; Windows runs the real ConvertFrom-Json on every file."""
    problems = []

    def fold(key):
        folded = ""
        for character in key:
            upper = character.upper()
            folded += upper if len(upper) == 1 else character
        return folded

    def look(pairs):
        seen = {}
        for key, _ in pairs:
            if key == "":
                problems.append("an empty key")
            folded = fold(key)
            if folded in seen and seen[folded] != key:
                problems.append("keys %r and %r differ only by case" % (seen[folded], key))
            seen[folded] = key
        return dict(pairs)

    json.loads(text, object_pairs_hook=look)
    return problems


def committed():
    with open(REPO / "contracts" / "undo-traces.json", encoding="utf-8") as handle:
        return json.load(handle)


# ASCII digits only (#1004-b): Python's \d, like .NET's, matches any Unicode digit.
FRAGMENT = re.compile(r"^([0-9]{8}T[0-9]{6}Z)-(.+)\.json$")


def nfc(text):
    return unicodedata.normalize("NFC", text)


def deployed_answer(case):
    """undo.rule.deployed: only the destinations the section deploys to now
    are read; the newest fragment of each says what that website shows; a
    move offers to deploy when a website shows a page as the course has it
    before the move, for a page whose visibility the move changes. A site
    marker with no fragment cannot tell; places compare in NFC."""
    destinations = case["destinations"]
    markers = set(case.get("siteMarkers", []))
    if case.get("recordListed") is False:
        # #1004-b: a folder that is there and cannot be listed: what every
        # destination deployed to now shows is unknown.
        return "cannotTell" if destinations else "noOffer"
    newest = {}
    for fragment in case["record"]:
        found = FRAGMENT.match(fragment["name"])
        if not found:
            continue
        stamp, destination = found.group(1), found.group(2)
        if destination not in destinations:
            continue
        if destination not in newest or stamp > newest[destination][0]:
            newest[destination] = (stamp, fragment.get("places"))
    deployed = False
    cannot_tell = False
    for destination in destinations:
        if destination not in newest:
            if destination in markers:
                deployed = True
                cannot_tell = True
            continue
        deployed = True
        places = newest[destination][1]
        if places is None:
            cannot_tell = True
            continue
        shown = {nfc(place) for place in places}
        for move in case["moves"]:
            path = move["path"]
            place = nfc("/".join(path.split("/")[2:])[:-3])
            if move["visibleBefore"] != move["visibleAfter"] and (place in shown) == move["visibleBefore"]:
                return "offerToDeploy"
    if not deployed:
        return "noOffer"
    if cannot_tell or case.get("changesMoreThanVisibility"):
        return "cannotTell"
    return "noOffer"


# Cases the mac's Foundation acts on and this model, like Windows, is not
# measured to copy (#899 W6 review 2): keys beyond ASCII (sorted by Unicode
# collation there, canonically equivalent keys taken for one), a byte-order
# mark at the start of a key or text, a number with an exponent and more than
# 17 digits or more than 38 without. Held by name, as Windows'
# NamedGapLedger holds them: the model must REFUSE each (no bytes; cannot
# tell both ways), never give bytes or a verdict of its own, and the
# contract's answer must still differ.
REFUSED_HERE_EDIT_JSON = (
    "a new object's keys beyond ASCII: the mac sorts them by Unicode collation (an emoji first, \u00e9 between E and f, a full-width \uff21 beside A, \u00df after ss, a tab passed over)",
    "a new object holding \u00e9 written two ways (one character, and e with a combining accent): the mac takes them for one key",
    "a key path part beyond ASCII finds the member the file spells another way (\u00e9 as one character in the op, e with a combining accent in the file)",
    "a key path part beyond ASCII, spelled as the file spells it",
    "the Kelvin sign in a file's key is the letter K to the mac: the member is found and its value moved",
    "a file's key that starts with a byte-order mark (written \\ufeff) is the key without it to the mac: the member is found and its value moved",
)
REFUSED_HERE_CHECK = (
    "editJSON: a file's number spelled with an exponent and more than 17 digits is read by the mac as a decimal number, whose double is not the nearest one: the step's value is that double",
    "editJSON: a file's number spelled with an exponent and more than 17 digits, the step's value its nearest double, which the mac does not read from it",
    "editJSON: a member holding an object whose key is \u00e9 written as e with a combining accent, the step's value \u00e9 as one character",
    "editJSON: a key path part \u00e9 as one character, the file's key e with a combining accent, the step having added the member",
    "editJSON: a member holding text that starts with a byte-order mark (written \\ufeff), which the mac reads without it",
    "editJSON: a file's key that is the Kelvin sign, the key path the letter K, the step having added the member",
    "editJSON: another member's number written with 168 digits after the point, which the mac cannot read: the file is not JSON there",
)


def undone_as_read(step, path, text):
    """A file as a reader compares it after an Undo: its JSON value when the
    step planned it member by member (U4a), its text otherwise."""
    if text is not None and any(member["path"] == path for member in step.get("members", [])):
        return json.loads(text)
    return text


class ActionTraceTests(unittest.TestCase):
    """U3: the action traces, made from the steps the Mac recorded from the
    real action code (contracts/undo-action-steps.json)."""

    def test_every_recorded_step_is_reproduced_by_its_ops_both_ways(self):
        for step in traces.read_action_steps():
            pages, _ = traces.action_fixture(step)
            model = traces.Model(pages=pages)
            outcome = traces.make_recorded_step(model, step)
            self.assertEqual(outcome[0], "applied", step["name"])
            self.assertEqual([op["kind"] for op in outcome[2]], step["ops"], step["name"] + ": the op kinds")
            undone = traces.plan(outcome[2], True, dict(model.pages))
            self.assertEqual(undone[0], "ready", step["name"])
            for entry in step["files"]:
                # U4b2-12: a page a folder's move carries is undone at its
                # folder's old place.
                place = traces.place_before_the_moves(entry["path"], step.get("folderMoves", []))
                self.assertEqual(undone_as_read(step, entry["path"], undone[1].get(place, model.pages.get(place))),
                                 undone_as_read(step, entry["path"], entry["before"]),
                                 step["name"] + ": " + entry["path"] + " undone")
            for tree in step.get("trees", []):
                self.assertIsNone(undone[1].get(tree["path"], "kept"), step["name"] + ": " + tree["path"] + " taken out")

    def test_a_member_by_member_file_is_made_by_the_member_rule_bytes(self):
        # U4a: the after the Mac recorded is exactly what the members'
        # editJSON ops leave, applied in order to its before.
        for step in traces.read_action_steps():
            for entry in step["files"]:
                members = [member for member in step.get("members", []) if member["path"] == entry["path"]]
                if not members:
                    continue
                data = entry["before"].encode("utf-8")
                for member in members:
                    op = {"kind": "editJSON", "path": member["path"], "keyPath": member["keyPath"]}
                    for side in ("before", "after"):
                        if side in member:
                            op[side] = member[side]
                    data = traces.json_bytes_moved(op, False, data)
                self.assertEqual(data.decode("utf-8"), entry["after"], step["name"])

    def test_a_rollover_after_a_deploy_is_undone_leaving_its_marker_apart(self):
        # U3b, Russell's ruling of 2026-11-19 on Q3: some rollover trace has
        # a deploy fill the marker's place and a later undo of the step
        # that names the marker as left apart, not a refusal.
        found = False
        for trace in committed()["actionTraces"]:
            deployed = False
            for call in trace["calls"]:
                if call["call"] == "deploy":
                    deployed = True
                if deployed and call["call"] == "undo" and call.get("leftApart"):
                    found = True
        self.assertTrue(found, "no action trace undoes a rollover after a deploy")

    def test_there_are_about_120_action_traces_and_each_starts_with_its_step(self):
        steps = traces.read_action_steps()
        document = committed()
        self.assertEqual(len(document["actionTraces"]), len(steps) * traces.ACTION_TRACES_PER_STEP)
        if steps:
            self.assertGreaterEqual(len(document["actionTraces"]), 120)
        names = {step["name"] for step in steps}
        for trace in document["actionTraces"]:
            self.assertIn(trace["step"], names)
            self.assertEqual(trace["calls"][0]["call"], "action")
            self.assertEqual(trace["calls"][0]["expect"], "applied")

    def test_undoing_an_action_with_no_hand_edits_gives_back_its_befores(self):
        steps = {step["name"]: step for step in traces.read_action_steps()}
        for trace in committed()["actionTraces"]:
            if trace["handEdits"]:
                continue
            step = steps[trace["step"]]
            for entry in step["files"]:
                if any(member["path"] == entry["path"] for member in step.get("members", [])):
                    # U4a: an Undo puts each member's VALUE back, spelled
                    # compactly, so the file's values are its before's, not
                    # its bytes (test_every_recorded_step_... checks them).
                    continue
                wanted = None if entry["before"] is None else traces.sha(entry["before"])
                if traces.is_carried(entry["path"], step.get("folderMoves", [])):
                    # U4b2-12: a page a folder's move carries is named at the
                    # new place, empty once the step is undone (its before is
                    # back at the old place, in the folder's listing).
                    wanted = None
                self.assertEqual(trace["afterUndoingAll"][entry["path"]], wanted, trace["name"] + " " + entry["path"])
            for tree in step.get("trees", []):
                self.assertIsNone(trace["afterUndoingAll"][tree["path"]], trace["name"] + " " + tree["path"])

    def test_a_rename_step_undone_ends_at_its_fixture_and_redone_at_the_recorded_after(self):
        # U4b2-12: a step recorded with folderMoves (Rename folder) starts
        # from each folder's listing at its old place; undone, every folder
        # is back at its old name with every page's bytes as before and
        # nothing at the new name; redone, every file the step names holds
        # its recorded after and the folder's other pages moved untouched.
        found = 0
        for step in traces.read_action_steps():
            if "folderMoves" not in step:
                continue
            found += 1
            start, _ = traces.action_fixture(step)
            for moved in step["folderMoves"]:
                for inside, text in moved["files"].items():
                    self.assertEqual(start[moved["from"] + "/" + inside], text, step["name"])
                self.assertFalse(any(path.startswith(moved["to"] + "/") for path in start), step["name"])
            model = traces.Model(pages=dict(start))
            outcome = traces.make_recorded_step(model, step)
            self.assertEqual(outcome[0], "applied", step["name"])
            self.assertEqual([op["kind"] for op in outcome[2]], step["ops"], step["name"])
            self.assertEqual(model.undo()[0], "undone", step["name"])
            self.assertEqual(set(model.pages), set(start), step["name"] + ": the places after the undo")
            for path, text in start.items():
                self.assertEqual(undone_as_read(step, path, model.pages[path]), undone_as_read(step, path, text),
                                 step["name"] + ": " + path + " undone")
            self.assertEqual(model.redo()[0], "redone", step["name"])
            wanted = {}
            for moved in step["folderMoves"]:
                for inside, text in moved["files"].items():
                    wanted[moved["to"] + "/" + inside] = text
            for entry in step["files"]:
                wanted[entry["path"]] = entry["after"]
            self.assertEqual(set(model.pages), set(wanted), step["name"] + ": the places after the redo")
            for path, text in wanted.items():
                self.assertEqual(undone_as_read(step, path, model.pages[path]), undone_as_read(step, path, text),
                                 step["name"] + ": " + path + " redone")
        self.assertEqual(found, 2)

    def test_a_refused_undo_of_a_rename_names_the_renamed_folder(self):
        # U4b2-12 (UndoOp.placeAsFound, U4b): a page taken out of the folder
        # at its new name since; the Undo is refused naming the folder where
        # the teacher finds it, the new name, never the old one; a refused
        # Redo names the old name, where the folder is then.
        step = [recorded for recorded in traces.read_action_steps() if recorded["name"] == "renameFolder"][0]
        moved = step["folderMoves"][0]
        pages, _ = traces.action_fixture(step)
        model = traces.Model(pages=pages)
        self.assertEqual(traces.make_recorded_step(model, step)[0], "applied")
        self.assertTrue(model.hand_edit_path("deletePage", moved["to"] + "/Loops.md"))
        self.assertEqual(model.undo(), ("changedSince", moved["to"], 0))
        pages, _ = traces.action_fixture(step)
        model = traces.Model(pages=pages)
        traces.make_recorded_step(model, step)
        self.assertEqual(model.undo()[0], "undone")
        self.assertTrue(model.hand_edit_path("body", moved["from"] + "/Loops.md"))
        self.assertEqual(model.redo(), ("changedSince", moved["from"], 1))

    def test_a_rename_trace_hashes_each_folder_by_its_listing_at_both_ends(self):
        # U4b2-12: every rename trace with no hand edits ends its undos with
        # each folder's listing (its recorded listingSha) at the old name and
        # nothing at the new one, and its redos the other way round, the
        # folder at the new name holding the carried pages' afters.
        steps = {step["name"]: step for step in traces.read_action_steps()}
        traced = 0
        for trace in committed()["actionTraces"]:
            step = steps[trace["step"]]
            if "folderMoves" not in step:
                continue
            traced += 1
            if trace["handEdits"]:
                continue
            for moved in step["folderMoves"]:
                after = dict(moved["files"])
                for entry in step["files"]:
                    inside = traces.part_inside(moved["to"], entry["path"])
                    if inside:
                        after[inside] = entry["after"]
                self.assertEqual(trace["afterUndoingAll"][moved["from"]], moved["listingSha"], trace["name"])
                self.assertIsNone(trace["afterUndoingAll"][moved["to"]], trace["name"])
                self.assertIsNone(trace["final"][moved["from"]], trace["name"])
                self.assertEqual(trace["final"][moved["to"]],
                                 traces.listing_sha({"folders": moved["folders"], "files": after}), trace["name"])
        self.assertEqual(traced, 2 * traces.ACTION_TRACES_PER_STEP)

    def test_the_twenty_seeded_traces_are_unchanged_by_the_action_traces(self):
        with_steps = traces.generate()
        without = traces.generate(steps=[])
        self.assertEqual(with_steps["traces"], without["traces"])


class GeneratorTests(unittest.TestCase):

    def test_two_runs_write_the_same_bytes(self):
        first = traces.render(traces.generate())
        second = traces.render(traces.generate())
        self.assertEqual(first, second)

    def test_the_committed_traces_are_what_the_generator_writes(self):
        # Read as LF: a Windows checkout with core.autocrlf has CR LF on disk
        # (the contract review's WRONG 5; documentation/12 on reading text).
        written = (REPO / "contracts" / "undo-traces.json").read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(
            written, traces.render(traces.generate()),
            "contracts/undo-traces.json is stale: run python3 scripts/make_undo_traces.py",
        )

    def test_a_checkout_with_crlf_line_endings_is_still_current(self):
        # Windows' checkout (core.autocrlf=true) has CR LF on disk; --check
        # and the comparison above must still call it current.
        import io
        import tempfile
        from contextlib import redirect_stdout
        original = traces.CONTRACT
        with tempfile.TemporaryDirectory() as folder:
            crlf = Path(folder) / "undo-traces.json"
            crlf.write_bytes(traces.render(traces.generate()).replace(b"\n", b"\r\n"))
            traces.CONTRACT = crlf
            try:
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(traces.main(["--check"]), 0)
            finally:
                traces.CONTRACT = original

    def test_another_seed_gives_other_traces(self):
        self.assertNotEqual(traces.render(traces.generate(seed=1)), traces.render(traces.generate()))

    def test_twenty_traces_each_with_expectations(self):
        document = committed()
        self.assertEqual(len(document["traces"]), traces.TRACE_COUNT)
        for trace in document["traces"]:
            calls = trace["calls"]
            self.assertGreaterEqual(len(calls), traces.SHORTEST, trace["name"])
            for call in calls:
                self.assertIn(call["call"], ("step", "undo", "redo", "handEdit", "note", "move"), call)
                self.assertIn("head", call)
                self.assertIn("redo", call)
                if call["call"] in ("step", "undo", "redo", "move"):
                    self.assertIn("expect", call)

    def test_a_refused_redo_drops_only_the_redo(self):
        # Ruling 20: refused once with its reason, then Redo has nothing and
        # the head (what Undo acts on) is where it was.
        found = 0
        for trace in committed()["traces"]:
            previous = None
            for call in trace["calls"]:
                if call["call"] == "redo" and call["expect"] == "changedSince":
                    found += 1
                    self.assertTrue(call["droppedTheRedo"])
                    self.assertIsNone(call["redo"])
                    self.assertEqual(call["head"], previous["head"], trace["name"])
                previous = call
        self.assertGreater(found, 0, "no trace holds a refused redo")

    def test_the_traces_reach_every_outcome_u1_rules_on(self):
        seen = set()
        for trace in committed()["traces"]:
            for call in trace["calls"]:
                seen.add((call["call"], call.get("expect") or call.get("kind") or call.get("reason")))
        for wanted in [("step", "applied"), ("step", "changedNothing"), ("undo", "undone"),
                       ("undo", "changedSince"), ("undo", "nothingToUndo"), ("redo", "redone"),
                       ("redo", "nothingToRedo"), ("handEdit", "body"), ("handEdit", "sameLine"),
                       ("handEdit", "otherKey"), ("note", None), ("redo", "changedSince"), ("move", "applied")]:
            self.assertIn(wanted, seen)
        for call, _ in seen:
            self.assertNotEqual(call, "clear", "a deploy or a share of unit plans clears nothing (rulings 17 and 18)")

    def test_undoing_everything_without_hand_edits_is_the_identity(self):
        document = committed()
        clean = [trace for trace in document["traces"] if not trace["handEdits"]]
        self.assertTrue(clean, "no trace without hand edits to check the identity on")
        for trace in clean:
            self.assertEqual(trace["afterUndoingAll"], document["fixtureHashes"], trace["name"])

    def test_a_refused_undo_clears_the_list(self):
        for trace in committed()["traces"]:
            for call in trace["calls"]:
                if call["call"] == "undo" and call["expect"] == "changedSince":
                    self.assertTrue(call["clearedTheList"])
                    self.assertIsNone(call["head"])
                    self.assertIsNone(call["redo"])


class LineModelTests(unittest.TestCase):

    def test_every_fixture_change_is_reproduced_by_its_ops_both_ways(self):
        for page_id, path, text, _ in traces.FIXTURE:
            for line in ("publish: true", "publish: false"):
                after = traces.setting_entry("publish", line, text)
                if after is None or after == text:
                    continue
                ops = traces.ops_for_change(path, text, after)
                if ops[0]["kind"] == "writeFile":
                    continue
                result = traces.plan(ops, True, {path: after})
                self.assertEqual(result, ("ready", {path: text}, []), page_id)

    def test_a_body_edit_leaves_the_line_op_undoable(self):
        _, path, text, _ = traces.FIXTURE[0]
        after = traces.setting_entry("publish", "publish: true", text)
        ops = traces.ops_for_change(path, text, after)
        self.assertEqual(ops[0]["kind"], "editLine")
        edited = after + "Written since.\n"
        result = traces.plan(ops, True, {path: edited})
        self.assertEqual(result, ("ready", {path: text + "Written since.\n"}, []))


class RelinkRecoveryByStateTests(unittest.TestCase):
    """Windows' recovery of a relink where the link stands, by state
    (opKinds.move; review 2 of mac-1, LOW 2): what is at the place and
    what is set aside decide, a rule for every state."""

    PLACE = "courses/TST1O/section1/Unit 1, Day 4.md"

    def settled(self, at_the_place, set_aside):
        op = {"kind": "move", "from": self.PLACE, "to": self.PLACE,
              "linkShaBefore": traces.sha("Unit 1, Day 3.md"),
              "linkShaAfter": traces.sha("Unit 1, Day 5.md")}
        pages = {self.PLACE + traces.SET_ASIDE: set_aside}
        if at_the_place is not None:
            pages[self.PLACE] = at_the_place
        return traces.settle_what_was_set_aside([op], pages, True)

    def test_the_place_empty_takes_back_whatever_was_set_aside(self):
        for set_aside in (("link", "Unit 1, Day 3.md"), "Teacher's save.\n"):
            self.assertEqual(self.settled(None, set_aside), {self.PLACE: set_aside})

    def test_a_link_of_the_steps_at_the_place_gives_the_teachers_item_back(self):
        self.assertEqual(self.settled(("link", "Unit 1, Day 5.md"), "Teacher's save.\n"),
                         {self.PLACE: "Teacher's save.\n"})
        self.assertEqual(self.settled(("link", "Unit 1, Day 5.md"), ("link", "Unit 1, Day 3.md")),
                         {self.PLACE: ("link", "Unit 1, Day 5.md")})

    def test_a_third_item_at_the_place_keeps_the_teachers_item_visible(self):
        kept = "courses/TST1O/section1/Unit 1, Day 4 (kept by Undo).md"
        self.assertEqual(self.settled("Another save.\n", "Teacher's save.\n"),
                         {self.PLACE: "Another save.\n", kept: "Teacher's save.\n"})

    def test_a_third_item_at_the_place_removes_a_link_of_the_steps_set_aside(self):
        self.assertEqual(self.settled("Another save.\n", ("link", "Unit 1, Day 3.md")),
                         {self.PLACE: "Another save.\n"})


def safe_path(path):
    if not isinstance(path, str) or not path:
        return False
    parts = path.split("/")
    if path.startswith("/") or "\\" in path or "\0" in path or any(part in ("", ".", "..") for part in parts):
        return False
    return not (len(path) >= 2 and path[1] == ":" and path[0].isalpha())


def is_blob_name(name):
    return isinstance(name, str) and re.fullmatch(r"[0-9a-f]{64}", name) is not None


def overlap(first, second):
    """Without regard to case: one place on a case-insensitive volume, by
    the model's one comparison (U4b2-9)."""
    return traces.places_overlap(first, second)


def relink_shape_is_known(op):
    """UndoOp.relinkShapeIsKnown (U4b3 relink-2, opKinds.move)."""
    if op.get("kind") != "move" or traces.is_case_only_move(op):
        return False
    before, after = op.get("linkShaBefore"), op.get("linkShaAfter")
    if not is_blob_name(before) or not is_blob_name(after) or before == after:
        return False
    blobs = op.get("blobs")
    return isinstance(blobs, list) and len(blobs) == 2 and before in blobs and after in blobs


def readable_op(op):
    """UndoOp.shapeIsKnown, as the contract's opKinds and unknown say."""
    kind = op.get("kind")
    if kind not in KINDS_KNOWN:
        return False
    for key in ("blobs",):
        if key in op and not (isinstance(op[key], list) and all(is_blob_name(name) for name in op[key])):
            return False
    for key in ("beforeSha", "afterSha", "sha", "listingSha", "linkSha", "linkShaBefore", "linkShaAfter"):
        if key in op and op[key] is not None and not is_blob_name(op[key]):
            return False
    if kind in ("move", "moveApart", "setAside"):
        if "path" in op or not safe_path(op.get("from")) or not safe_path(op.get("to")):
            return False
        # Two exceptions: a capitalisation-only rename (U4b), and a relink
        # where the link stands (mac-1: from and to one path byte for byte,
        # a move carrying the relinking pair).
        if overlap(op["from"], op["to"]) and not traces.is_case_only_move(op) and not traces.is_a_relink_in_place(op):
            return False
        # Exactly one content form: sha, listingSha, linkSha (U4b2-14), or
        # the relinking pair linkShaBefore and linkShaAfter counted as ONE
        # (U4b3 relink): both given, different, and blobs exactly the two;
        # a move only, never a capitalisation-only one.
        forms = [key in op for key in ("sha", "listingSha", "linkSha")].count(True)
        if "linkShaBefore" in op or "linkShaAfter" in op:
            if not relink_shape_is_known(op):
                return False
            forms += 1
        return forms == 1
    if kind == "external":
        target = op.get("target")
        if "path" in op or not isinstance(target, str) or ":" not in target:
            return False
        family, name = target.split(":", 1)
        if family not in EXTERNAL_TARGETS_KNOWN or not name:
            return False
        return "before" in op or "after" in op
    path = op.get("path")
    if not safe_path(path):
        return False
    if kind in ("editLine", "replaceText", "writeFile", "recompute"):
        for key in ("before", "after", "key", "afterKey", "contextBefore", "contextAfter"):
            if key in op and op[key] is not None and not isinstance(op[key], str):
                return False
    if kind == "editLine":
        return isinstance(op.get("key"), str) and (op.get("before") is not None or op.get("after") is not None)
    if kind == "recompute":
        # A maintainer a reader does not know is a re-derivation it cannot
        # run (opKinds.recompute).
        return op.get("maintainer") in MAINTAINERS_KNOWN
    if kind == "replaceText":
        parts = [op.get(key) for key in ("before", "after", "contextBefore", "contextAfter")]
        if any(not isinstance(part, str) for part in parts):
            return False
        return parts[2] + parts[0] + parts[3] != parts[2] + parts[1] + parts[3]
    if kind == "editJSON":
        key_path = op.get("keyPath")
        if "element" in op or not isinstance(key_path, list) or not key_path or not all(isinstance(k, str) for k in key_path):
            return False
        if "before" not in op and "after" not in op:
            return False
        if "before" in op and "after" in op and traces.json_equal(op["before"], op["after"]):
            return False
        return True
    if kind in ("createTree", "removeTree"):
        if kind == "removeTree" and "heldBy" in op:
            return False
        return is_blob_name(op.get("listingSha")) and op["listingSha"] in op.get("blobs", [])
    return True


KINDS_KNOWN = ("writeFile", "editLine", "recompute", "replaceText", "editJSON", "move", "moveApart", "setAside",
               "createTree", "removeTree", "external")
EXTERNAL_TARGETS_KNOWN = ("preference", "scheduledDeploy")
MAINTAINERS_KNOWN = ("sectionFrontPage",)
HOLDS_KNOWN = ("section", "course")


def readable_step(step):
    """UndoStep's reading, as stepKeys and unknown.unreadableStep say:
    a `holds` it does not know, or an op it cannot read, makes the step
    unreadable; `madeBy`, `class` and `action.key` are open strings."""
    if "holds" in step and step["holds"] not in HOLDS_KNOWN:
        return False
    for op in step["ops"]:
        if not readable_op(op):
            return False
    # opKinds.wholeOps: no other op shares a whole op's places, but for its
    # two exceptions. U4b3, the second: a place handed over, by exactly the
    # two ops of the pair, each place once, in a step that carries no edit.
    handed = traces.handovers(step["ops"])
    if handed:
        if traces.carried_edits(step["ops"]):
            return False
        places = [traces.place_left(step["ops"][leaver]) for leaver, _ in handed]
        for first in range(len(places)):
            for second in range(first + 1, len(places)):
                if traces.part_inside(places[first], places[second]) == "":
                    return False
    whole = ("move", "moveApart", "setAside", "createTree", "removeTree", "external")
    for index, op in enumerate(step["ops"]):
        if op["kind"] not in whole:
            continue
        mine = [op[key] for key in ("path", "from", "to") if key in op]
        for other_index, other in enumerate(step["ops"]):
            if other_index == index:
                continue
            if op.get("target") is not None and other.get("target") == op.get("target"):
                return False
            if other_index > index and traces.move_carries(op, other):
                # U4b: an edit inside what a move moved, at its new place,
                # after the move (opKinds.wholeOps' order).
                continue
            theirs = [other[key] for key in ("path", "from", "to") if key in other]
            for a in mine:
                for b in theirs:
                    if overlap(a, b) and not handed_over(a, b, index, other_index, step["ops"], handed):
                        return False
    return True


def handed_over(mine, theirs, first, second, ops, handed):
    """UndoStep.isHandedOver (U4b3): two places two ops name are the one
    place a handover between exactly those two ops hands over."""
    for leaver, filler in handed:
        if {leaver, filler} != {first, second}:
            continue
        place = traces.place_left(ops[leaver])
        if traces.part_inside(place, mine) == "" and traces.part_inside(place, theirs) == "":
            return True
    return False


def made_by_parts(made_by):
    """stepKeys.madeBy: who is before the first colon, the id after the last."""
    first = made_by.find(":")
    if first < 0:
        return made_by, None, None
    last = made_by.rfind(":")
    client = made_by[first + 1:last] if last > first else None
    return made_by[:first], client, made_by[last + 1:]


class ContractCaseTests(unittest.TestCase):

    def current_text(self, current):
        if "text" in current:
            return current["text"], True
        if "bytesHex" in current:
            data = bytes.fromhex(current["bytesHex"])
            try:
                return data.decode("utf-8"), True
            except UnicodeDecodeError:
                return None, False
        return None, not current.get("folder")

    CHECK_KEYS = {"name", "op", "current", "undo", "redo", "why"}

    def item_bytes(self, current):
        """The bytes at a place a case describes: None for absent, False for
        a folder or a tree."""
        if current.get("absent"):
            return None
        if "text" in current:
            return current["text"].encode("utf-8")
        if "bytesHex" in current:
            return bytes.fromhex(current["bytesHex"])
        return False

    def prepared(self, given):
        """The op as the replay decodes it: texts turned into their hashes,
        a listing into its hash and blobs (checkCasesHow)."""
        op = {key: value for key, value in given.items()}
        if op.get("kind") == "writeFile":
            op["beforeSha"] = None if op.get("beforeText") is None else traces.sha(op["beforeText"])
            op["afterSha"] = None if op.get("afterText") is None else traces.sha(op["afterText"])
        if "contentText" in op:
            op["sha"] = traces.sha(op.pop("contentText"))
        if "linkTarget" in op:
            op["linkSha"] = traces.sha(op.pop("linkTarget"))
        if "linkTargetBefore" in op or "linkTargetAfter" in op:
            # U4b3 relink: the two texts, their hashes, both blobs (unless
            # the case gives its own blobs).
            names = []
            if "linkTargetBefore" in op:
                op["linkShaBefore"] = traces.sha(op.pop("linkTargetBefore"))
                names.append(op["linkShaBefore"])
            if "linkTargetAfter" in op:
                op["linkShaAfter"] = traces.sha(op.pop("linkTargetAfter"))
                names.append(op["linkShaAfter"])
            op.setdefault("blobs", names)
        if "listing" in op:
            tree = op.pop("listing")
            op["listingSha"] = traces.listing_sha(tree)
            if op["kind"] in ("createTree", "removeTree"):
                op["blobs"] = [op["listingSha"]] + [traces.sha(text) for text in tree["files"].values()]
        for key in [key for key, value in op.items() if value is None and key in ("beforeSha", "afterSha")]:
            del op[key]
        return op

    def test_a_relink_beside_link_sha_is_not_readable(self):
        """U4b3 relink-2: linkSha given beside the pair is a shape this
        version cannot read (no shared row yet: Windows reads linkSha and
        ignores the pair until its piece 21b)."""
        before, after = traces.sha("Unit 1, Day 3.md"), traces.sha("Unit 1, Day 4.md")
        relink = {"kind": "move", "from": "courses/TST1O/section1/Unit 1, Day 4.md",
                  "to": "courses/TST1O/section1/Unit 1, Day 5.md",
                  "linkShaBefore": before, "linkShaAfter": after, "blobs": [before, after]}
        self.assertTrue(readable_op(relink))
        self.assertFalse(readable_op(dict(relink, linkSha=before)))
        self.assertFalse(readable_op(dict(relink, kind="moveApart")))

    def test_check_cases(self):
        cases = shared_undo()["checkCases"]
        self.assertGreaterEqual(len(cases), 90)
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(set(case) - self.CHECK_KEYS, set(), "a key the replay does not check")
                op = self.prepared(case["op"])
                if not readable_op(op):
                    self.assertEqual(case["undo"], "notReadable")
                    self.assertEqual(case["redo"], "notReadable")
                    continue
                current = case["current"]
                kind = op["kind"]
                unreadable_now = current.get("cannotBeRead") or any(
                    isinstance(side, dict) and side.get("cannotBeRead")
                    for side in (current.get("atFrom"), current.get("atTo")))
                if kind != "recompute" and kind != "external" and unreadable_now:
                    # The director's ruling on U2b's review: a read that
                    # fails is "cannot tell now", never changed since.
                    self.assertEqual(case["undo"], "cannotTell")
                    self.assertEqual(case["redo"], "cannotTell")
                    continue
                if kind == "recompute":
                    # No check (opKinds.recompute): re-derived, never compared.
                    state = "after"
                elif kind in ("move", "moveApart", "setAside"):
                    # U4b2-9: listedAs, a third spelling, is the model's to
                    # judge (move_state), never the harness's.
                    state = traces.move_state(op, current["atFrom"], current["atTo"], current.get("listedAs"))
                elif kind in ("createTree", "removeTree"):
                    state = traces.tree_state(op, current)
                elif kind == "external":
                    state = traces.external_state(op, current)
                elif kind == "replaceText":
                    data = self.item_bytes(current)
                    state = traces.replace_text_state(op, data if data else None)
                elif kind == "editJSON":
                    data = self.item_bytes(current)
                    state = traces.edit_json_state(op, data if data else None)
                else:
                    if "before" in case["op"] and case["op"]["before"] is None:
                        op["before"] = None
                    if "after" in case["op"] and case["op"]["after"] is None:
                        op["after"] = None
                    op.setdefault("beforeSha", None)
                    op.setdefault("afterSha", None)
                    text, is_absent_or_text = self.current_text(current)
                    if text is None and not is_absent_or_text:
                        state = "neither"
                    elif text is None and kind == "writeFile":
                        state = traces.op_state(op, None)
                    else:
                        state = traces.op_state(op, text)
                undo = {"after": "canUndo", "before": "alreadyBack", "neither": "changedSince", "cannotTell": "cannotTell"}[state]
                redo = {"before": "canRedo", "after": "alreadyRedone", "neither": "changedSince", "cannotTell": "cannotTell"}[state]
                if case["name"] in REFUSED_HERE_CHECK:
                    self.assertEqual((undo, redo), ("cannotTell", "cannotTell"), "held: refused as cannot tell, never judged")
                    self.assertNotEqual((undo, redo), (case["undo"], case["redo"]), "held, and it now agrees: take it off the list")
                    continue
                self.assertEqual(undo, case["undo"])
                self.assertEqual(redo, case["redo"])

    def test_edit_json_cases(self):
        # The bytes of an editJSON move (the hard review of U2b, LOW a).
        cases = json_cases()["editJSONCases"]
        self.assertGreaterEqual(len(cases), 6)
        for case in cases:
            with self.subTest(case=case["name"]):
                out = traces.json_bytes_moved(case["op"], case["direction"] == "undo", case["file"].encode("utf-8"))
                if case["name"] in REFUSED_HERE_EDIT_JSON:
                    self.assertIsNone(out, "held: refused, never bytes of its own")
                    self.assertIsNotNone(case["result"], "held, and the contract now refuses it too: take it off the list")
                    continue
                self.assertEqual(None if out is None else out.decode("utf-8"), case["result"])

    def test_every_held_case_is_still_in_the_contract(self):
        names = set()
        for case in shared_undo()["checkCases"] + json_cases()["editJSONCases"]:
            names.add(case["name"])
        for name in REFUSED_HERE_EDIT_JSON + REFUSED_HERE_CHECK:
            self.assertIn(name, names)

    def test_the_number_limits_are_the_contracts_rule(self):
        # undo.numberSpellingRule, the one rule Windows' UndoJson checks too.
        rule = shared_undo()["numberSpellingRule"]
        self.assertEqual(rule["exponentCharactersAtMost"], traces.MAC_EXPONENT_CHARACTERS_AT_MOST)
        self.assertEqual(rule["digitsWithAnExponentAtMost"], traces.MEASURED_DIGITS_WITH_AN_EXPONENT)
        self.assertEqual(rule["digitsWithoutAnExponentAtMost"], traces.MEASURED_DIGITS_WITHOUT_AN_EXPONENT)
        self.assertGreaterEqual(len(shared_undo()["numberSpellingCases"]), 30)

    def test_number_spelling_cases(self):
        # Each spelling as the member a of {"a": <spelling>, "b": 1}: not JSON,
        # cannot tell (read, never as measured), minus infinity, or the double.
        for case in shared_undo()["numberSpellingCases"]:
            with self.subTest(case["name"]):
                self.assertEqual(set(case), {"name", "spelling", "reads"})
                data = ('{"a": ' + case["spelling"] + ', "b": 1}\n').encode("utf-8")
                read = traces._mac_read(data)
                reads = case["reads"]
                if reads == "notJSON":
                    self.assertIsNone(read)
                    continue
                self.assertIsNotNone(read)
                if reads == "cannotTell":
                    self.assertIsInstance(read["a"], traces._Unmeasured)
                    continue
                self.assertNotIsInstance(read["a"], traces._Unmeasured)
                wanted = float("-inf") if reads == "minusInfinity" else reads
                self.assertEqual(read["a"], wanted)

    def test_listing_cases(self):
        cases = shared_undo()["listingCases"]
        self.assertGreaterEqual(len(cases), 3)
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(traces.listing_text(case["tree"]), case["listing"])
                self.assertEqual(traces.listing_sha(case["tree"]), case["listingSha"])

    STACK_KEYS = {"name", "calls", "head", "redo", "onTheList", "onTheListCount", "oldestOnTheList",
                  "expectLast", "cleared", "clearedSeq", "linesWritten", "onTheDisk", "physicallyPruned",
                  "blobKept", "interrupted", "markers", "folderKept", "movedFolder", "caseOnlyFolder", "rederived", "nothingMovedOutside",
                  "keptOriginalLeft", "foreignKeptOriginalUntouched", "keptWhatItReplacedLines", "keptBesideThePage", "why",
                  "leftApart", "schoolYear", "cloudflareMarkers", "leftoverMarkers", "startsAtTheNextLogin",
                  "refusalNamed", "madeFolder", "handedOver",
                  # U4b2-4: the whole of the line's words, which the model
                  # does not write; the Swift replay checks it.
                  "keptWhatItReplacedSays",
                  # Review 1 of U4b2-10: empty folders, which the model does
                  # not hold (folder_of_pages); the Swift replay checks it.
                  "foldersInside", "linkedFolder", "linkedPage", "laterLinks", "hopLink"}

    # U4b2-4: the two pages wholeFileStepOnTwoPagesNamedIndex writes.
    TWO_PAGES_NAMED_INDEX = ("courses/TST1O/Section 1/Classes/index.md", "courses/TST1O/Section 2/Classes/index.md")

    MARKER_FROM = "courses/TST1O/.netlify_sites/section1.json"
    MARKER_TO = "courses/TST1O/.netlify_sites/section1.previous.json"
    OLD_MARKER = "{\"site_id\": \"aaa-111\"}\n"
    NEW_MARKER = "{\"site_id\": \"bbb-222\"}\n"
    EXTRA = "courses/TST1O/extra"
    EXTRA_TREE = {"folders": ["sub"], "files": {"a.md": "A\n", "sub/b.md": "B\n"}}
    SETTINGS = "courses/TST1O/settings.json"
    NOTES = "courses/TST1O/notes.md"
    PREFERENCE = "preference:undoCasesPreference"
    CLOUDFLARE_FROM = "courses/TST1O/.cloudflare_sites/section1.json"
    CLOUDFLARE_TO = "courses/TST1O/.cloudflare_sites/section1.previous.json"
    CLOUDFLARE_MARKER = "{\"project\": \"tst1o-s1-2025\"}\n"
    LEFTOVER_FROM = "courses/TST1O/.netlify_sites/section1.from-built-output.json"
    LEFTOVER_TO = "courses/TST1O/.netlify_sites/section1.from-built-output.previous.json"
    LEFTOVER = "{\"site_id\": \"ccc-333\"}\n"
    SCHEDULE = "scheduledDeploy:org.plantoir.deploy.undo-cases"
    SCHEDULE_VALUE = {"plist": "cGxpc3Q=", "script": "c2NyaXB0"}

    def kind_call(self, call, model):
        """U2's calls (stackCasesHow), on the model's pages. Answers what
        `last` becomes, or None."""
        pages = model.pages
        if call == "moveTheMarker":
            if pages.get(self.MARKER_FROM) is None and pages.get(self.MARKER_TO) is None:
                pages[self.MARKER_FROM] = self.OLD_MARKER
            content = pages.get(self.MARKER_FROM) or ""
            return model.ops_step([{"kind": "move", "from": self.MARKER_FROM, "to": self.MARKER_TO, "sha": traces.sha(content)}])
        if call == "rollOverOntoANewWebsite":
            # U3b: one step of the year's setting and the marker moved aside
            # as a `moveApart` (stackCasesHow).
            if pages.get(self.MARKER_FROM) is None and pages.get(self.MARKER_TO) is None:
                pages[self.MARKER_FROM] = self.OLD_MARKER
            if pages.get(self.SETTINGS) is None:
                pages[self.SETTINGS] = "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n"
            content = pages.get(self.MARKER_FROM) or ""
            year = {"kind": "editJSON", "path": self.SETTINGS, "keyPath": ["school_year"], "before": "2025-2026", "after": "2026-2027"}
            marker = {"kind": "moveApart", "from": self.MARKER_FROM, "to": self.MARKER_TO, "sha": traces.sha(content)}
            return model.ops_step([year, marker])
        if call == "rollOverOntoNewWebsitesOnTwoHosts":
            # U3b, records as a group: the year and both hosts' markers.
            if pages.get(self.MARKER_FROM) is None and pages.get(self.MARKER_TO) is None:
                pages[self.MARKER_FROM] = self.OLD_MARKER
            if pages.get(self.CLOUDFLARE_FROM) is None and pages.get(self.CLOUDFLARE_TO) is None:
                pages[self.CLOUDFLARE_FROM] = self.CLOUDFLARE_MARKER
            if pages.get(self.SETTINGS) is None:
                pages[self.SETTINGS] = "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n"
            year = {"kind": "editJSON", "path": self.SETTINGS, "keyPath": ["school_year"], "before": "2025-2026", "after": "2026-2027"}
            netlify = {"kind": "moveApart", "from": self.MARKER_FROM, "to": self.MARKER_TO, "sha": traces.sha(self.OLD_MARKER)}
            cloudflare = {"kind": "moveApart", "from": self.CLOUDFLARE_FROM, "to": self.CLOUDFLARE_TO,
                          "sha": traces.sha(self.CLOUDFLARE_MARKER)}
            return model.ops_step([year, netlify, cloudflare])
        if call == "rollOverTurningOffASchedule":
            # U3b: the year and the deploy set for later turned off.
            if pages.get(self.SETTINGS) is None:
                pages[self.SETTINGS] = "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n"
            pages[self.SCHEDULE] = self.SCHEDULE_VALUE
            year = {"kind": "editJSON", "path": self.SETTINGS, "keyPath": ["school_year"], "before": "2025-2026", "after": "2026-2027"}
            return model.ops_step([year, {"kind": "external", "target": self.SCHEDULE, "before": self.SCHEDULE_VALUE}])
        if call == "rollOverSettingALeftoverAside":
            # U3b, the review of U3b's fixes, LOW 3: the year, the record as
            # a `moveApart`, and a leftover no deploy reads as a `setAside`.
            if pages.get(self.MARKER_FROM) is None and pages.get(self.MARKER_TO) is None:
                pages[self.MARKER_FROM] = self.OLD_MARKER
            if pages.get(self.LEFTOVER_FROM) is None and pages.get(self.LEFTOVER_TO) is None:
                pages[self.LEFTOVER_FROM] = self.LEFTOVER
            if pages.get(self.SETTINGS) is None:
                pages[self.SETTINGS] = "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n"
            year = {"kind": "editJSON", "path": self.SETTINGS, "keyPath": ["school_year"], "before": "2025-2026", "after": "2026-2027"}
            marker = {"kind": "moveApart", "from": self.MARKER_FROM, "to": self.MARKER_TO, "sha": traces.sha(self.OLD_MARKER)}
            leftover = {"kind": "setAside", "from": self.LEFTOVER_FROM, "to": self.LEFTOVER_TO, "sha": traces.sha(self.LEFTOVER)}
            return model.ops_step([year, marker, leftover])
        if call == "removeTheKeptLeftover":
            pages.pop(self.LEFTOVER_TO, None)
            return None
        if call == "theScheduleStartsOnlyAtTheNextLogin":
            model.schedules_start_at_the_next_login = True
            return None
        if call == "theScheduleCannotBeSetNow":
            model.refuses_schedules = True
            return None
        if call == "deployANewMarker":
            pages[self.MARKER_FROM] = self.NEW_MARKER
            return None
        if call == "makeAFolder":
            listing = traces.listing_sha(self.EXTRA_TREE)
            return model.ops_step([{"kind": "createTree", "path": self.EXTRA, "listingSha": listing, "blobs": [listing]}])
        if call == "addAFileToTheFolder":
            tree = {"folders": self.EXTRA_TREE["folders"], "files": dict(self.EXTRA_TREE["files"], **{"c.md": "C\n"})}
            pages[self.EXTRA] = ("tree", traces.listing_sha(tree))
            return None
        if call == "removeTheFolder":
            listing = pages[self.EXTRA][1]
            return model.ops_step([{"kind": "removeTree", "path": self.EXTRA, "listingSha": listing, "blobs": [listing]}])
        if call == "editTheSettings":
            if pages.get(self.SETTINGS) is None:
                pages[self.SETTINGS] = "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n"
            current = json.loads(pages[self.SETTINGS]).get("school_year")
            after = "2025-2026" if current == "2026-2027" else "2026-2027"
            op = {"kind": "editJSON", "path": self.SETTINGS, "keyPath": ["school_year"], "after": after}
            if current is not None:
                op["before"] = current
            return model.ops_step([op])
        if call == "editTheSettingsByHand":
            pages[self.SETTINGS] = "{\"course_name\": \"Test\", \"school_year\": \"2030-2031\"}\n"
            return None
        if call == "editAHunk":
            if pages.get(self.NOTES) is None:
                pages[self.NOTES] = "Intro.\nLine one: old.\nEnd.\n"
            is_new = "Line one: new." in pages[self.NOTES]
            return model.ops_step([{"kind": "replaceText", "path": self.NOTES, "before": "new" if is_new else "old",
                                    "after": "old" if is_new else "new", "contextBefore": "Line one: ", "contextAfter": ".\n"}])
        if call == "setAPreference":
            op = {"kind": "external", "target": self.PREFERENCE, "after": "b"}
            if self.PREFERENCE in pages:
                op["before"] = pages[self.PREFERENCE]
                if pages[self.PREFERENCE] == "b":
                    op["after"] = "a"
            return model.ops_step([op])
        if call == "changeThePreferenceByHand":
            pages[self.PREFERENCE] = "z"
            return None
        if call == "moveThePageAside":
            source, destination = "courses/TST1O/old/a.md", "courses/TST1O/a.md"
            if pages.get(source) is None and pages.get(destination) is None:
                pages[source] = "page\n"
            return model.ops_step([{"kind": "move", "from": source, "to": destination, "sha": traces.sha("page\n")}])
        if call in ("moveThePageIntoAFolder", "moveThePageBetweenFolders"):
            # U4b2-2: one move into courses/TST1O/new.
            source, destination = {
                "moveThePageIntoAFolder": ("courses/TST1O/b.md", "courses/TST1O/new/b.md"),
                "moveThePageBetweenFolders": ("courses/TST1O/old/c.md", "courses/TST1O/new/c.md"),
            }[call]
            if pages.get(source) is None and pages.get(destination) is None:
                pages[source] = "page\n"
            return model.ops_step([{"kind": "move", "from": source, "to": destination, "sha": traces.sha("page\n")}])
        if call == "linkItsNewFolderOutside":
            model.linked_outside.add("courses/TST1O/new")
            for inside in list(pages):
                if inside.startswith("courses/TST1O/new/"):
                    pages.pop(inside)
            return None
        if call == "linkItsOldFolderOutside":
            model.linked_outside.add("courses/TST1O/old")
            pages.pop("courses/TST1O/old/a.md", None)
            return None
        if call == "forgetTheMaintainer":
            model.maintainer_registered = False
            return None
        if call in ("moveALinkToAFolder", "renameAPerSectionFolderThatIsALink"):
            # U4b2-14: a link to a folder elsewhere in the course, moved as
            # itself and judged by its target. U4b2-15: Rename folder's plan
            # of a per-section folder that is that link makes the same step
            # (stackCasesHow); the plan itself is the Swift replay's to check.
            if pages.get(self.LINK_FROM) is None and pages.get(self.LINK_TO) is None:
                for name, text in self.LIBRARY_FILES.items():
                    pages[self.LIBRARY + "/" + name] = text
                pages[self.LINK_FROM] = ("link", self.LINK_TARGET)
            return model.ops_step([{"kind": "move", "from": self.LINK_FROM, "to": self.LINK_TO,
                                    "linkSha": traces.sha(self.LINK_TARGET)}])
        if call == "moveAFolderWithAPageEditedInside":
            if traces.folder_of_pages(pages, self.MEDIA) is None and traces.folder_of_pages(pages, self.RENAMED) is None:
                for name, text in self.MEDIA_FILES.items():
                    pages[self.MEDIA + "/" + name] = text
            tree = traces.folder_of_pages(pages, self.MEDIA)
            if tree is None:
                return "noFolderToMove"
            move = {"kind": "move", "from": self.MEDIA, "to": self.RENAMED, "listingSha": traces.listing_sha(tree)}
            edit = {"kind": "replaceText", "path": self.RENAMED + "/a.md", "before": "old", "after": "new",
                    "contextBefore": "Line one: ", "contextAfter": ".\n"}
            return model.ops_step([move, edit])
        if call == "moveAFolderWithAFileMadeInANewFolderInside":
            # U4b2-10: the same step, and a file made in a folder (sub) that
            # was not there, inside the moved folder.
            if traces.folder_of_pages(pages, self.MEDIA) is None and traces.folder_of_pages(pages, self.RENAMED) is None:
                for name, text in self.MEDIA_FILES.items():
                    pages[self.MEDIA + "/" + name] = text
            tree = traces.folder_of_pages(pages, self.MEDIA)
            if tree is None:
                return "noFolderToMove"
            move = {"kind": "move", "from": self.MEDIA, "to": self.RENAMED, "listingSha": traces.listing_sha(tree)}
            edit = {"kind": "replaceText", "path": self.RENAMED + "/a.md", "before": "old", "after": "new",
                    "contextBefore": "Line one: ", "contextAfter": ".\n"}
            return model.ops_step([move, edit] + traces.ops_for_change(self.RENAMED + "/sub/x.md", None, "X\n"))
        if call in ("moveAFolderHoldingAnEmptyFolderAndMakingAFolderInIt",
                    "moveAFolderHoldingAnEmptyFolderAndMakingFilesInItAndBesideIt"):
            # Review 1 of U4b2-10, MEDIUM 1. The model holds a folder as its
            # files only, so the content's own empty sub is not in it: the
            # step is made and judged without it (the outcome is the same;
            # the Swift replay checks foldersInside).
            if traces.folder_of_pages(pages, self.MEDIA) is None and traces.folder_of_pages(pages, self.RENAMED) is None:
                for name, text in self.MEDIA_FILES.items():
                    pages[self.MEDIA + "/" + name] = text
            tree = traces.folder_of_pages(pages, self.MEDIA)
            if tree is None:
                return "noFolderToMove"
            made = {"moveAFolderHoldingAnEmptyFolderAndMakingAFolderInIt": {self.RENAMED + "/sub/deeper/x.md": "X\n"},
                    "moveAFolderHoldingAnEmptyFolderAndMakingFilesInItAndBesideIt": {self.RENAMED + "/sub/x.md": "X\n",
                                                                                      self.RENAMED + "/new/y.md": "Y\n"}}[call]
            ops = [{"kind": "move", "from": self.MEDIA, "to": self.RENAMED, "listingSha": traces.listing_sha(tree)},
                   {"kind": "replaceText", "path": self.RENAMED + "/a.md", "before": "old", "after": "new",
                    "contextBefore": "Line one: ", "contextAfter": ".\n"}]
            for path in sorted(made):
                ops += traces.ops_for_change(path, None, made[path])
            return model.ops_step(ops)
        if call == "finderRecordsAWindowInTheMadeFolder":
            # Never listed (listingCases): nothing the model holds.
            return None
        if call == "addAFolderInsideTheMadeFolder":
            pages[self.RENAMED + "/sub/mine/y.md"] = "Y\n"
            return None
        if call == "renameAFolderInCaseOnly":
            spellings = [self.CASE_ONLY_FROM, self.CASE_ONLY_TO, self.CASE_ONLY_BY_HAND]
            if all(traces.folder_of_pages(pages, spelling) is None for spelling in spellings):
                for name, text in self.MEDIA_FILES.items():
                    pages[self.CASE_ONLY_FROM + "/" + name] = text
            tree = traces.folder_of_pages(pages, self.CASE_ONLY_FROM)
            if tree is None:
                return "noFolderToMove"
            move = {"kind": "move", "from": self.CASE_ONLY_FROM, "to": self.CASE_ONLY_TO, "listingSha": traces.listing_sha(tree)}
            edit = {"kind": "replaceText", "path": self.CASE_ONLY_TO + "/a.md", "before": "old", "after": "new",
                    "contextBefore": "Line one: ", "contextAfter": ".\n"}
            return model.ops_step([move, edit])
        if call == "spellTheFolderAnotherWay":
            for path in [path for path in pages if isinstance(path, str) and path.startswith(self.CASE_ONLY_TO + "/")]:
                pages[self.CASE_ONLY_BY_HAND + path[len(self.CASE_ONLY_TO):]] = pages.pop(path)
            return None
        if call == "addAFileInsideTheMovedFolder":
            pages[self.RENAMED + "/c.md"] = "C\n"
            return None
        if call == "leaveAKeptCopyInsideTheMovedFolder":
            # The model holds no staged files: the step's own kept copy is
            # never content (opKinds.wholeOps, the part-two review's M1).
            return None
        if call == "editThePageInsideByHand":
            pages[self.RENAMED + "/a.md"] = "Hand.\n"
            return None
        if call == "stepEditingInsideALinksMove":
            # Review 1 of U4b2-14: a link's move and an edit under its `to`.
            ops = [{"kind": "move", "from": self.LINK_FROM, "to": self.LINK_TO, "linkSha": traces.sha(self.LINK_TARGET)},
                   {"kind": "replaceText", "path": self.LINK_TO + "/a.md", "before": "old", "after": "new",
                    "contextBefore": "Line one: ", "contextAfter": ".\n"}]
            seq = model.begin(ops, readable=readable_step({"ops": ops}))
            model.find(seq)["phase"] = "done"
            return None
        if call == "makeRoomWithALaterClassThatIsALink":
            # U4b3 part 2: Insert Class's plan of room for one class at Day 2
            # with Day 3 a link to a file elsewhere, as the step it must make
            # (stackCasesHow): the link moved as itself to Day 4, Day 4's
            # date written into the file it leads to under this section's key
            # (it is a course-level page), its title kept, Day 2's page
            # renamed into the place the link left, the new class at Day 2.
            # The plan itself is the Swift replay's to check.
            if pages.get(self.linked_day(3)) is None and pages.get(self.linked_day(4)) is None:
                for number in (1, 2):
                    pages[self.linked_day(number)] = self.linked_text(number, number)
                pages[self.LINKED_FILE] = self.linked_text(3, 3)
                pages[self.linked_day(3)] = ("link", self.LINKED_TARGET)
            two = pages.get(self.linked_day(2))
            return self.vetted_ops_step(model,
                [{"kind": "move", "from": self.linked_day(3), "to": self.linked_day(4),
                  "linkSha": traces.sha(self.LINKED_TARGET)}]
                + traces.ops_for_change(self.LINKED_FILE, pages[self.LINKED_FILE], self.linked_redated())
                + traces.ops_for_change(self.linked_day(3), None, self.linked_text(3, 3, body=2))
                + traces.ops_for_change(self.linked_day(2), two, "New.\n"))
        if call == "makeRoomWithALaterClassThatIsABrokenLink":
            # Russell, 2026-11-26 ("Never refuse"): the same course with the
            # file the link leads to taken away. The link is moved as itself
            # to Day 4 and nothing is written for it or through it; Day 2's
            # page is renamed into the place it left, the new class at Day 2.
            if pages.get(self.linked_day(3)) is None and pages.get(self.linked_day(4)) is None:
                for number in (1, 2):
                    pages[self.linked_day(number)] = self.linked_text(number, number)
                pages[self.linked_day(3)] = ("link", self.LINKED_TARGET)
            pages.pop(self.LINKED_FILE, None)
            two = pages.get(self.linked_day(2))
            return self.vetted_ops_step(model,
                [{"kind": "move", "from": self.linked_day(3), "to": self.linked_day(4),
                  "linkSha": traces.sha(self.LINKED_TARGET)}]
                + traces.ops_for_change(self.linked_day(3), None, self.linked_text(3, 3, body=2))
                + traces.ops_for_change(self.linked_day(2), two, "New.\n"))
        if call == "makeRoomWithALaterClassLinkedToAnEarlierClass":
            # Relink-5: Day 3 a link to Day 1's own page, a class page the
            # plan leaves: the link moved as itself to Day 4, its text kept,
            # nothing written through it; Day 2's page renamed into the place
            # it left, the new class at Day 2.
            earlier = "Unit 1, Day 1.md"
            if pages.get(self.linked_day(3)) is None and pages.get(self.linked_day(4)) is None:
                for number in (1, 2):
                    pages[self.linked_day(number)] = self.linked_text(number, number)
                pages[self.LINKED_FILE] = self.linked_text(3, 3)
                pages[self.linked_day(3)] = ("link", earlier)
            two = pages.get(self.linked_day(2))
            return self.vetted_ops_step(model,
                [{"kind": "move", "from": self.linked_day(3), "to": self.linked_day(4), "linkSha": traces.sha(earlier)}]
                + traces.ops_for_change(self.linked_day(3), None, self.linked_text(3, 3, body=2))
                + traces.ops_for_change(self.linked_day(2), two, "New.\n"))
        if call in ("makeRoomWithALaterClassLinkedToAClassItRenames", "makeRoomWithALaterClassLinkedToALinkedClass"):
            # Relink-5 (review B's probe; review C's with Day 3 a link to the
            # file elsewhere): Day 4 a link holding `Unit 1, Day 3.md`, a
            # class page the plan renames: renamed to Day 5 and re-pointed at
            # `Unit 1, Day 4.md` in one relinking move, nothing written
            # through it.
            old, new = "Unit 1, Day 3.md", "Unit 1, Day 4.md"
            plain = call == "makeRoomWithALaterClassLinkedToAClassItRenames"
            if pages.get(self.linked_day(3)) is None and pages.get(self.linked_day(4)) is None:
                for number in (1, 2):
                    pages[self.linked_day(number)] = self.linked_text(number, number)
                pages[self.LINKED_FILE] = self.linked_text(3, 3)
                pages[self.linked_day(3)] = self.linked_text(3, 3) if plain else ("link", self.LINKED_TARGET)
                pages[self.linked_day(4)] = ("link", old)
            two, three = pages.get(self.linked_day(2)), pages.get(self.linked_day(3))
            ops = [{"kind": "move", "from": self.linked_day(4), "to": self.linked_day(5),
                    "linkShaBefore": traces.sha(old), "linkShaAfter": traces.sha(new),
                    "blobs": [traces.sha(old), traces.sha(new)],
                    "linkTexts": {traces.sha(old): old, traces.sha(new): new}}]
            if plain:
                ops += traces.ops_for_change(self.linked_day(4), None, self.linked_text(4, 4, body=3))
                ops += traces.ops_for_change(self.linked_day(3), three, self.linked_text(3, 3, body=2))
            else:
                ops.append({"kind": "move", "from": self.linked_day(3), "to": self.linked_day(4),
                            "linkSha": traces.sha(self.LINKED_TARGET)})
                ops += traces.ops_for_change(self.LINKED_FILE, pages[self.LINKED_FILE], self.linked_redated())
                ops += traces.ops_for_change(self.linked_day(3), None, self.linked_text(3, 3, body=2))
            return self.vetted_ops_step(model, ops + traces.ops_for_change(self.linked_day(2), two, "New.\n"))
        if call == "makeRoomWithALaterClassLinkedThroughALinkInside":
            # mac-2 (U4b3 ruling 6, "re-point the in-between link"): Day 4 a
            # link to hop.md, a link inside the working folder that is not a
            # class page, holding Day 3's page, which the plan renames: Day
            # 4's link moved as itself to Day 5, its text kept, and hop.md
            # re-pointed where it stands (one relinking move naming the one
            # place twice), nothing written through either link.
            old, new = self.HOP_BEFORE, self.HOP_AFTER
            if pages.get(self.linked_day(3)) is None and pages.get(self.linked_day(4)) is None:
                for number in (1, 2):
                    pages[self.linked_day(number)] = self.linked_text(number, number)
                pages[self.LINKED_FILE] = self.linked_text(3, 3)
                pages[self.linked_day(3)] = self.linked_text(3, 3)
                pages[self.HOP] = ("link", old)
                pages[self.linked_day(4)] = ("link", self.HOP_FROM_DAY4)
            two, three = pages.get(self.linked_day(2)), pages.get(self.linked_day(3))
            ops = [{"kind": "move", "from": self.linked_day(4), "to": self.linked_day(5),
                    "linkSha": traces.sha(self.HOP_FROM_DAY4)},
                   {"kind": "move", "from": self.HOP, "to": self.HOP,
                    "linkShaBefore": traces.sha(old), "linkShaAfter": traces.sha(new),
                    "blobs": [traces.sha(old), traces.sha(new)],
                    "linkTexts": {traces.sha(old): old, traces.sha(new): new}}]
            self.assertTrue(traces.is_a_relink_in_place(ops[1]))
            ops += traces.ops_for_change(self.linked_day(4), None, self.linked_text(4, 4, body=3))
            ops += traces.ops_for_change(self.linked_day(3), three, self.linked_text(3, 3, body=2))
            return self.vetted_ops_step(model, ops + traces.ops_for_change(self.linked_day(2), two, "New.\n"))
        if call == "handAPlaceOverAfterALinksMove":
            # U4b3 door-4, shape A: the link leaves Day 3, a new page fills it.
            if pages.get(self.day(3)) is None and pages.get(self.day(4)) is None:
                pages[self.HANDED_LIBRARY + "/Day 3.md"] = "Linked.\n"
                pages[self.day(3)] = ("link", self.handed_target(3))
            return self.vetted_ops_step(model, [
                {"kind": "move", "from": self.day(3), "to": self.day(4), "linkSha": traces.sha(self.handed_target(3))},
            ] + traces.ops_for_change(self.day(3), None, "New.\n"))
        if call == "handAPlaceOverBeforeALinksMove":
            # Shape B: Day 3's page moves up a day, the link fills Day 3, a
            # new page fills Day 2.
            if pages.get(self.day(2)) is None and pages.get(self.day(3)) is None:
                pages[self.HANDED_LIBRARY + "/Day 2.md"] = "Two.\n"
                pages[self.day(2)] = ("link", self.handed_target(2))
                pages[self.day(3)] = "Three.\n"
            return self.vetted_ops_step(model,
                traces.ops_for_change(self.day(4), None, "Three.\n")
                + traces.ops_for_change(self.day(3), "Three.\n", None)
                + [{"kind": "move", "from": self.day(2), "to": self.day(3), "linkSha": traces.sha(self.handed_target(2))}]
                + traces.ops_for_change(self.day(2), None, "New.\n"))
        if call == "editTheHandedOverPageByHand":
            pages[self.day(3)] = "Hand.\n"
            return None
        if call in ("stepFillingAPlaceBeforeItIsLeft", "stepHandingOverAFoldersPlace"):
            if call == "stepFillingAPlaceBeforeItIsLeft":
                ops = traces.ops_for_change(self.day(3), None, "New.\n") + [
                    {"kind": "move", "from": self.day(3), "to": self.day(4), "linkSha": traces.sha(self.handed_target(3))}]
            else:
                folder = "courses/TST1O/section1/media"
                ops = [{"kind": "move", "from": folder, "to": "courses/TST1O/section1/renamed", "listingSha": "a" * 64}
                       ] + traces.ops_for_change(folder, None, "New.\n")
            seq = model.begin(ops, readable=readable_step({"ops": ops}))
            model.find(seq)["phase"] = "done"
            return None
        if call == "stepEditingInsideAMovesFrom":
            ops = [{"kind": "move", "from": self.MEDIA, "to": self.RENAMED, "listingSha": "a" * 64},
                   {"kind": "replaceText", "path": self.MEDIA + "/a.md", "before": "old", "after": "new",
                    "contextBefore": "Line one: ", "contextAfter": ".\n"}]
            seq = model.begin(ops, readable=readable_step({"ops": ops}))
            model.find(seq)["phase"] = "done"
            return None
        self.fail("unknown call " + call)

    MEDIA = "courses/TST1O/media"
    RENAMED = "courses/TST1O/renamed"
    MEDIA_FILES = {"a.md": "Intro.\nLine one: old.\nEnd.\n", "b.md": "B\n"}
    CASE_ONLY_FROM = "courses/TST1O/Media"
    CASE_ONLY_TO = "courses/TST1O/media"
    CASE_ONLY_BY_HAND = "courses/TST1O/MEDIA"

    def case_only_folder(self, model):
        """U4b's caseOnlyFolder: the spelling the folder is listed under,
        then what its a.md holds. The model keys pages as spelled."""
        for spelling in (self.CASE_ONLY_FROM, self.CASE_ONLY_TO, self.CASE_ONLY_BY_HAND):
            if traces.folder_of_pages(model.pages, spelling) is not None:
                text = model.pages.get(spelling + "/a.md")
                page = "none"
                if text is not None:
                    page = "new" if "Line one: new." in text else "old" if "Line one: old." in text else "byHand"
                return spelling.rsplit("/", 1)[1] + ", " + page
        return "none"

    HANDED_LIBRARY = "courses/TST1O/library"

    def vetted_ops_step(self, model, ops):
        """JournaledWrite.perform(ops:): a step is read back as a reader of
        this version reads it before anything is written (vet), so one
        this version cannot read is refused and nothing is made."""
        if not readable_step({"ops": ops}):
            return "refused"
        return model.ops_step(ops)

    def day(self, number):
        return "courses/TST1O/section1/Unit 1, Day %d.md" % number

    def handed_target(self, number):
        return "../library/Day %d.md" % number

    LINKED_CLASSES = "courses/TST1O/section1/All Classes"
    LINKED_DATES = ("2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16", "2026-09-18", "2026-09-22")
    LINKED_TARGET = "../../elsewhere/Unit 1, Day 3.md"
    LINKED_FILE = "courses/TST1O/elsewhere/Unit 1, Day 3.md"

    # mac-2: the in-between link of makeRoomWithALaterClassLinkedThroughALinkInside.
    HOP = "courses/TST1O/elsewhere/hop.md"
    HOP_FROM_DAY4 = "../../elsewhere/hop.md"
    HOP_BEFORE = "../section1/All Classes/Unit 1, Day 3.md"
    HOP_AFTER = "../section1/All Classes/Unit 1, Day 4.md"

    def hop_link(self, model):
        """mac-2's hopLink: the text hop.md holds as a link, notALink, or
        nothing."""
        held = model.pages.get(self.HOP)
        if held is None:
            return "nothing"
        if isinstance(held, tuple) and held[0] == "link":
            return held[1]
        return "notALink"

    def linked_day(self, number):
        return self.LINKED_CLASSES + "/Unit 1, Day %d.md" % number

    def linked_text(self, number, meeting, body=None):
        """A class page of makeRoomWithALaterClassThatIsALink: its title,
        its meeting day's date, and the body of the day it was laid as."""
        return ("---\ntitle: Unit 1, Day %d\npublish: true\ncreated: %sT07:00:00.000-0400\n---\n\nDay %d.\n"
                % (number, self.LINKED_DATES[meeting - 1], body or number))

    def linked_redated(self):
        """The linked file after Insert Class: as laid, its title kept, with
        createdSection1 set to Day 4's meeting date at the top of its
        settings (a course-level page takes this section's key)."""
        return ("---\ncreatedSection1: %sT07:00:00.000-0400\n" % self.LINKED_DATES[3]) + self.linked_text(3, 3)[len("---\n"):]

    def linked_page(self, model):
        """U4b3 part 2's linkedPage: which place holds the link, its target
        there, and what the file it leads to holds."""
        at_new, at_old = model.pages.get(self.linked_day(4)), model.pages.get(self.linked_day(3))
        new_is_link = isinstance(at_new, tuple) and at_new[0] == "link"
        old_is_link = isinstance(at_old, tuple) and at_old[0] == "link"
        place, link = "neither", None
        if new_is_link and old_is_link:
            place, link = "both", at_new
        elif new_is_link:
            place, link = "new", at_new
        elif old_is_link:
            place, link = "old", at_old
        target = link[1] if link is not None else "notALink"
        held = model.pages.get(self.LINKED_FILE)
        file = "changed"
        if held is None:
            file = "gone"
        elif held == self.linked_text(3, 3):
            file = "asLaidDown"
        elif held == self.linked_redated():
            file = "redatedForThisSection"
        return place + ", " + target + ", " + file

    def later_links(self, model):
        """Relink-5's laterLinks: Day 1, 3, 4 and 5 of the linked course,
        each a link's text, a page's last line and created date, or
        nothing."""
        parts = []
        for number in (1, 3, 4, 5):
            held = model.pages.get(self.linked_day(number))
            what = "nothing"
            if isinstance(held, tuple) and held[0] == "link":
                what = "link " + held[1]
            elif isinstance(held, str):
                lines = [line for line in held.split("\n") if line]
                created = "none"
                for line in held.split("\n"):
                    if line.startswith("created: "):
                        created = line[len("created: "):][:10]
                        break
                what = "page %s %s" % (lines[-1] if lines else "", created)
            parts.append("Day %d: %s" % (number, what))
        return "; ".join(parts)

    def handed_over(self, model):
        """U4b3 door-4's handedOver: what Day 2, Day 3 and Day 4 hold, then
        whether the pages the links lead to are as the calls laid them."""
        parts = []
        for number in (2, 3, 4):
            held = model.pages.get(self.day(number))
            if held is None:
                what = "nothing"
            elif isinstance(held, tuple) and held[0] == "link":
                what = "link " + held[1]
            elif isinstance(held, str):
                what = "page " + (held[:-1] if held.endswith("\n") else held)
            else:
                what = "other"
            parts.append("Day %d: %s" % (number, what))
        laid = {"Day 2.md": "Two.\n", "Day 3.md": "Linked.\n"}
        library = "untouched"
        for path, held in model.pages.items():
            if isinstance(path, str) and path.startswith(self.HANDED_LIBRARY + "/"):
                if laid.get(path[len(self.HANDED_LIBRARY) + 1:]) != held:
                    library = "changed"
        parts.append("library: " + library)
        return "; ".join(parts)

    LINK_FROM = "courses/TST1O/section1/media"
    LINK_TO = "courses/TST1O/section1/renamed"
    LINK_TARGET = "../library"
    LIBRARY = "courses/TST1O/library"
    LIBRARY_FILES = {"a.md": "A\n", "pictures/b.md": "B\n"}

    def linked_folder(self, model):
        """U4b2-14's linkedFolder: which place holds the link, its target
        there, and whether the folder it leads to is as the call made it."""
        at_new, at_old = model.pages.get(self.LINK_TO), model.pages.get(self.LINK_FROM)
        place, link = "neither", at_new
        if at_new is not None and at_old is not None:
            place = "both"
        elif at_new is not None:
            place = "renamed"
        elif at_old is not None:
            place, link = "media", at_old
        target = link[1] if isinstance(link, tuple) and link[0] == "link" else "notALink"
        library = {}
        for name in self.LIBRARY_FILES:
            library[name] = model.pages.get(self.LIBRARY + "/" + name)
        untouched = "untouched" if library == self.LIBRARY_FILES else "changed"
        return place + ", " + target + ", " + untouched

    def moved_folder(self, model):
        """U4b's movedFolder: which place holds the folder, then what its
        a.md holds."""
        at_new = traces.folder_of_pages(model.pages, self.RENAMED) is not None
        at_old = traces.folder_of_pages(model.pages, self.MEDIA) is not None
        place, folder = "neither", self.RENAMED
        if at_new and at_old:
            place = "both"
        elif at_new:
            place = "renamed"
        elif at_old:
            place, folder = "media", self.MEDIA
        text = model.pages.get(folder + "/a.md")
        page = "none"
        if text is not None:
            page = "new" if "Line one: new." in text else "old" if "Line one: old." in text else "byHand"
        return place + ", " + page

    def made_folder(self, model):
        """U4b2-10's madeFolder: what sub holds wherever the moved folder
        is. The model holds folders as their files only, so a folder holding
        nothing is not there: it never answers `empty`."""
        folder = self.RENAMED if traces.folder_of_pages(model.pages, self.RENAMED) is not None else self.MEDIA
        tree = traces.folder_of_pages(model.pages, folder + "/sub")
        if tree is None:
            return "none"
        names = set()
        for inside in tree["files"]:
            names.add(inside.split("/")[0])
        return ", ".join(sorted(names, key=lambda name: name.encode("utf-8")))

    def markers(self, model):
        source, destination = model.pages.get(self.MARKER_FROM), model.pages.get(self.MARKER_TO)
        if source is None and destination == self.OLD_MARKER:
            return "moved"
        if source == self.OLD_MARKER and destination is None:
            return "movedBack"
        if source == self.NEW_MARKER and destination == self.OLD_MARKER:
            return "bothKept"
        return (source, destination)

    KIND_CALLS = ("moveTheMarker", "rollOverOntoANewWebsite", "deployANewMarker", "makeAFolder", "addAFileToTheFolder", "removeTheFolder",
                  "editTheSettings", "editTheSettingsByHand", "editAHunk", "setAPreference",
                  "changeThePreferenceByHand", "forgetTheMaintainer", "moveThePageAside", "linkItsOldFolderOutside",
                  "rollOverOntoNewWebsitesOnTwoHosts", "rollOverTurningOffASchedule", "theScheduleCannotBeSetNow",
                  "rollOverSettingALeftoverAside", "removeTheKeptLeftover", "theScheduleStartsOnlyAtTheNextLogin",
                  "moveAFolderWithAPageEditedInside", "addAFileInsideTheMovedFolder", "editThePageInsideByHand",
                  "stepEditingInsideAMovesFrom", "renameAFolderInCaseOnly", "spellTheFolderAnotherWay",
                  "leaveAKeptCopyInsideTheMovedFolder", "moveThePageIntoAFolder", "moveThePageBetweenFolders",
                  "linkItsNewFolderOutside", "moveAFolderWithAFileMadeInANewFolderInside", "addAFolderInsideTheMadeFolder",
                  "moveAFolderHoldingAnEmptyFolderAndMakingAFolderInIt",
                  "moveAFolderHoldingAnEmptyFolderAndMakingFilesInItAndBesideIt", "finderRecordsAWindowInTheMadeFolder",
                  "moveALinkToAFolder", "stepEditingInsideALinksMove", "renameAPerSectionFolderThatIsALink",
                  "handAPlaceOverAfterALinksMove", "handAPlaceOverBeforeALinksMove", "editTheHandedOverPageByHand",
                  "stepFillingAPlaceBeforeItIsLeft", "stepHandingOverAFoldersPlace",
                  "makeRoomWithALaterClassThatIsALink", "makeRoomWithALaterClassLinkedToAnEarlierClass",
                  "makeRoomWithALaterClassThatIsABrokenLink", "makeRoomWithALaterClassLinkedToAClassItRenames",
                  "makeRoomWithALaterClassLinkedToALinkedClass", "makeRoomWithALaterClassLinkedThroughALinkInside")

    def leftover_markers(self, model):
        source, destination = model.pages.get(self.LEFTOVER_FROM), model.pages.get(self.LEFTOVER_TO)
        if source is None and destination == self.LEFTOVER:
            return "moved"
        if source == self.LEFTOVER and destination is None:
            return "movedBack"
        if source is None and destination is None:
            return "gone"
        return (source, destination)

    def cloudflare_markers(self, model):
        source, destination = model.pages.get(self.CLOUDFLARE_FROM), model.pages.get(self.CLOUDFLARE_TO)
        if source is None and destination == self.CLOUDFLARE_MARKER:
            return "moved"
        if source == self.CLOUDFLARE_MARKER and destination is None:
            return "movedBack"
        return (source, destination)

    def test_stack_cases(self):
        folder_b = "@B/"
        for case in shared_undo()["stackCases"]:
            with self.subTest(case=case["name"]):
                unknown = set(case) - self.STACK_KEYS
                self.assertEqual(unknown, set(), "a key the replay does not check")
                self.assertIn("head", case)
                self.assertIn("redo", case)
                p1 = traces.PATHS["p1"]
                p2 = traces.PATHS["p2"]
                pages = {p1: traces.START["p1"], p2: traces.START["p2"], folder_b + p1: traces.START["p1"]}
                model = traces.Model(pages)
                last = None
                cleared = []
                held = []
                lines_written_by_the_deploy = None

                def one_step(path, days_ago=0):
                    now = traces.reading("publish", model.pages[path])
                    line = "publish: false" if now == ("entry", "publish: true") else "publish: true"
                    return model.step([(path, "publish", line)], days_ago=days_ago)

                def flipped(path):
                    now = traces.reading("publish", model.pages[path])
                    line = "publish: false" if now == ("entry", "publish: true") else "publish: true"
                    return traces.setting_entry("publish", line, model.pages[path])

                def begin_held():
                    after = flipped(p1)
                    held.append((model.begin(traces.ops_for_change(p1, model.pages[p1], after)), after))

                for call in case["calls"]:
                    if call == "step":
                        last = one_step(p1)
                    elif call == "stepOn:p2":
                        last = one_step(p2)
                    elif call == "step@B":
                        last = one_step(folder_b + p1)
                    elif call.startswith("step:") and call.endswith("daysAgo"):
                        last = one_step(p1, days_ago=int(call[len("step:"):-len("daysAgo")]))
                    elif call.startswith("steps:"):
                        for _ in range(int(call.split(":")[1])):
                            last = one_step(p1)
                    elif call.startswith("clock:"):
                        model.clock = float(call.split(":")[1])
                    elif call == "undo":
                        had = model.highest
                        last = model.undo()
                        if last[0] in ("changedSince", "contentMissing") and model.last_clearing == had:
                            cleared.append((last[0], had))
                    elif call == "redo":
                        last = model.redo()
                    elif call == "editTheLineByHand":
                        self.assertTrue(model.hand_edit_path("sameLine", p1))
                    elif call == "undoWhileAStepBegins":
                        # Another process begins a step after this undo has
                        # checked its ops and before it answers the refusal.
                        dry = model.undo(dry=True)
                        begin_held()
                        if dry[0] == "changedSince":
                            if model.clear():
                                cleared.append(("changedSince", model.highest))
                            model.prune()
                        last = dry
                    elif call == "newestSegmentGoesWhileRead":
                        # #1004: the reader refuses a listed newest segment
                        # that is gone when it opens it (pruning never takes
                        # the newest): the list cannot be read, so the undo
                        # changes nothing and clears nothing.
                        last = ("listUnavailable",)
                    elif call == "deploy":
                        # Not on the list: the model is not told of it at all.
                        lines_written_by_the_deploy = 0
                    elif call == "note":
                        model.note()
                    elif call.startswith("cleared:"):
                        # Honoured whatever its reason: a reader never checks it.
                        model.clear()
                        cleared.append((call[len("cleared:"):], model.highest))
                    elif call == "goLive":
                        if model.clear():
                            cleared.append(("wentLive", model.highest))
                        model.prune()
                    elif call == "wholeFileStep":
                        before = model.pages[p1]
                        after = flipped(p1) + "A line the step added.\n"
                        ops = traces.ops_for_change(p1, before, after)
                        self.assertEqual([op["kind"] for op in ops], ["writeFile"])
                        seq = model.begin(ops)
                        model.pages[p1] = after
                        model.finish(seq)
                        last = ("applied", seq)
                    elif call == "wholeFileStepOnTwoPagesNamedIndex":
                        ops = []
                        for path in self.TWO_PAGES_NAMED_INDEX:
                            model.pages[path] = "What " + path + " held before the step.\n"
                            ops += traces.ops_for_change(path, model.pages[path], "What the step left in " + path + ".\n")
                        self.assertEqual([op["kind"] for op in ops], ["writeFile", "writeFile"])
                        seq = model.begin(ops)
                        for path in self.TWO_PAGES_NAMED_INDEX:
                            model.pages[path] = "What the step left in " + path + ".\n"
                        model.finish(seq)
                        last = ("applied", seq)
                    elif call in ("firstIndexAfterContentGoneAndCannotBeStored", "secondIndexBeforeContentGoneAndCannotBeStored"):
                        first = call.startswith("first")
                        path = self.TWO_PAGES_NAMED_INDEX[0 if first else 1]
                        newest = model.on_list()[-1]
                        for op in newest["ops"]:
                            if op["kind"] == "writeFile" and op["path"] == path:
                                text = op["afterText"] if first else op["beforeText"]
                                model.removed_texts.add(text)
                                model.unstorable_texts.add(text)
                    elif call == "keepTheOriginalOfTheSecondIndex":
                        path = self.TWO_PAGES_NAMED_INDEX[1]
                        newest = model.on_list()[-1]
                        for op in newest["ops"]:
                            if op["kind"] == "writeFile" and op["path"] == path:
                                model.kept.setdefault(path, []).append(op["beforeText"])
                    elif call == "removeContent":
                        model.content_removed = True
                    elif call == "contentCannotBeStored":
                        model.content_cannot_be_stored = True
                    elif call == "beforeContentGoneAndCannotBeStored":
                        # Only the newest step's before text of p1 is gone
                        # from the list, and the list will not take it again.
                        newest = model.on_list()[-1]
                        for op in newest["ops"]:
                            if op["kind"] == "writeFile" and op["path"] == p1:
                                model.removed_texts.add(op["beforeText"])
                                model.unstorable_texts.add(op["beforeText"])
                    elif call == "afterContentGone":
                        # Only the newest step's after text of p1 is gone
                        # from the list (U4a review 1, LOW 4).
                        newest = model.on_list()[-1]
                        for op in newest["ops"]:
                            if op["kind"] == "writeFile" and op["path"] == p1:
                                model.removed_texts.add(op["afterText"])
                    elif call == "keepTheOriginal":
                        # The newest step's kept original of p1: what p1
                        # held before its whole-file op (U3c).
                        newest = model.on_list()[-1]
                        for op in newest["ops"]:
                            if op["kind"] == "writeFile" and op["path"] == p1:
                                model.kept.setdefault(p1, []).append(op["beforeText"])
                    elif call == "makeTheKeptOriginalUnreadable":
                        model.kept_unreadable = True
                    elif call == "changeTheKeptOriginal":
                        for path in model.kept:
                            model.kept[path] = [text + "A line added to the kept original.\n" for text in model.kept[path]]
                    elif call == "foreignKeptOriginal":
                        # Another list's kept original under the next step's
                        # name: the model's pages and list never see it; the
                        # Swift replay checks it is untouched.
                        pass
                    elif call == "begin:dead@B":
                        path = folder_b + p1
                        after = flipped(path)
                        model.begin(traces.ops_for_change(path, model.pages[path], after), dead=True)
                    elif call == "moveFolder:B":
                        model.unreachable.add("@B")
                    elif call == "restoreFolder:B":
                        model.unreachable.discard("@B")
                    elif call == "foreignLine":
                        model.foreign_line()
                    elif call == "foreignBlobLine":
                        # Two lines of a newer version (its begin and applied)
                        # with one number: the model counts the number and
                        # the barrier; its blob is the Swift replay's to check.
                        model.foreign_line()
                    elif call.startswith("stepFromAnotherVersion:"):
                        variant = call[len("stepFromAnotherVersion:"):]
                        before = model.pages[p1]
                        after = flipped(p1)
                        ops = [dict(op) for op in traces.ops_for_change(p1, before, after)]
                        step = {"seq": model.highest + 1, "madeAt": "now", "madeBy": "menu", "class": "A",
                                "holds": "section", "action": {"key": "publishPages", "arguments": {"pageCount": "1"}},
                                "ops": ops}
                        front = {"kind": "recompute", "path": "courses/TST1O/Section 1/index.md", "section": 1}
                        if variant == "theFrontPageMaintainer":
                            ops.append(dict(front, maintainer="sectionFrontPage"))
                        elif variant == "aMaintainerNobodyKnows":
                            ops.append(dict(front, maintainer="aMaintainerNobodyKnows"))
                        elif variant == "aHoldsNobodyKnows":
                            step["holds"] = "workingFolder"
                        elif variant == "openStrings":
                            step["madeBy"] = "outsideAssistant:A client: with colons:session-7"
                            step["class"] = "Z"
                            step["action"] = {"key": "aKeyNobodyKnows", "arguments": {}}
                            self.assertEqual(made_by_parts(step["madeBy"]),
                                             ("outsideAssistant", "A client: with colons", "session-7"))
                        elif variant == "aKeyOnAKnownOp":
                            ops[0]["onlyWhen"] = "aConditionNobodyKnows"
                        elif variant == "twoWholeOpsOnOnePlace":
                            listing = traces.listing_sha({})
                            ops.append({"kind": "createTree", "path": "courses/TST1O/made", "listingSha": listing, "blobs": [listing]})
                            ops.append({"kind": "createTree", "path": "courses/TST1O/made/inner", "listingSha": listing, "blobs": [listing]})
                        else:
                            self.fail("unknown variant " + variant)
                        seq = model.begin(ops, readable=readable_step(step))
                        model.pages[p1] = after
                        model.finish(seq)
                    elif call == "aSegmentNamedWithOtherDigits":
                        # #1004-b: undoJournal.files, six ASCII digits: a
                        # name with other digits is not a segment, so the
                        # step written in it is never read.
                        pass
                    elif call == "stepWithAMadeAtThatIsNotAMoment":
                        # #1004-b: unreadable (a barrier); for the limits it
                        # carries the time of the step before (no time of its own).
                        before = model.pages[p1]
                        after = flipped(p1)
                        seq = model.begin(traces.ops_for_change(p1, before, after), readable=False, no_time=True)
                        model.pages[p1] = after
                        model.finish(seq)
                    elif call == "foreignStep":
                        seq = model.begin([{"kind": "aKindNobodyKnows", "from": "a", "to": "b"}], readable=False)
                        model.find(seq)["phase"] = "done"
                    elif call in self.KIND_CALLS:
                        answered = self.kind_call(call, model)
                        if answered is not None:
                            last = answered
                    elif call == "begin:held":
                        begin_held()
                    elif call == "finish:held":
                        seq, after = held.pop()
                        model.pages[p1] = after
                        model.finish(seq)
                    else:
                        self.fail("unknown call " + call)
                summary = model.summary()
                self.assertEqual(summary["head"], case["head"])
                self.assertEqual(summary["redo"], case["redo"])
                listed = model.offered_seqs()
                if "onTheList" in case:
                    self.assertEqual(listed, case["onTheList"])
                if "onTheListCount" in case:
                    self.assertEqual(len(listed), case["onTheListCount"])
                    self.assertEqual(listed[0], case["oldestOnTheList"])
                if "onTheDisk" in case:
                    self.assertEqual([step["seq"] for step in model.on_list()], case["onTheDisk"])
                if "physicallyPruned" in case:
                    self.assertEqual([step["seq"] for step in model.steps if step["phase"] == "pruned"], case["physicallyPruned"])
                if "expectLast" in case:
                    self.assertEqual(last[0], case["expectLast"])
                if "cleared" in case:
                    self.assertIn(case["cleared"], [reason for reason, _ in cleared])
                if "clearedSeq" in case:
                    self.assertEqual(cleared[-1][1], case["clearedSeq"])
                if "linesWritten" in case:
                    self.assertEqual(lines_written_by_the_deploy, case["linesWritten"])
                if "interrupted" in case:
                    self.assertEqual([step["seq"] for step in model.steps if step["phase"] == "interrupted"], case["interrupted"])
                if "markers" in case:
                    self.assertEqual(self.markers(model), case["markers"])
                if "cloudflareMarkers" in case:
                    self.assertEqual(self.cloudflare_markers(model), case["cloudflareMarkers"])
                if "leftoverMarkers" in case:
                    self.assertEqual(self.leftover_markers(model), case["leftoverMarkers"])
                if "startsAtTheNextLogin" in case:
                    self.assertEqual(model.starts_at_the_next_login, case["startsAtTheNextLogin"])
                if "movedFolder" in case:
                    self.assertEqual(self.moved_folder(model), case["movedFolder"])
                if "madeFolder" in case:
                    self.assertEqual(self.made_folder(model), case["madeFolder"])
                if "linkedFolder" in case:
                    self.assertEqual(self.linked_folder(model), case["linkedFolder"])
                if "handedOver" in case:
                    self.assertEqual(self.handed_over(model), case["handedOver"])
                if "linkedPage" in case:
                    self.assertEqual(self.linked_page(model), case["linkedPage"])
                if "laterLinks" in case:
                    self.assertEqual(self.later_links(model), case["laterLinks"])
                if "hopLink" in case:
                    self.assertEqual(self.hop_link(model), case["hopLink"])
                if "caseOnlyFolder" in case:
                    self.assertEqual(self.case_only_folder(model), case["caseOnlyFolder"])
                if "folderKept" in case:
                    self.assertEqual(isinstance(model.pages.get(self.EXTRA), tuple), case["folderKept"])
                if "rederived" in case:
                    self.assertEqual(model.rederived, case["rederived"])
                if "keptOriginalLeft" in case:
                    # A kept copy the row itself left (a model holds none).
                    foreign = "foreignKeptOriginal" in case["calls"] or "leaveAKeptCopyInsideTheMovedFolder" in case["calls"]
                    self.assertEqual(bool(model.kept) or foreign, case["keptOriginalLeft"])
                if "keptBesideThePage" in case:
                    self.assertEqual(len(model.kept.get(p1, [])), case["keptBesideThePage"])
                if "keptWhatItReplacedLines" in case:
                    self.assertEqual(model.kept_what_it_replaced_lines, case["keptWhatItReplacedLines"])
                if "leftApart" in case:
                    self.assertEqual(list(last[2]) if len(last) > 2 else [], case["leftApart"])
                if "refusalNamed" in case:
                    self.assertEqual(last[0], "changedSince")
                    self.assertEqual(last[1], case["refusalNamed"])
                if "schoolYear" in case:
                    self.assertEqual(json.loads(model.pages[self.SETTINGS])["school_year"], case["schoolYear"])

    def test_recovery_cases_with_a_moved_folder(self):
        """undo.recoveryCases' U4b rows (withAMovedFolder): a step killed
        between its move and the edits it carries settles whole, judged by
        content. The model holds no staged files, so
        keptCopyLeftInsideTheFolder is the Swift replay's alone."""
        cases = [case for case in shared_undo()["recoveryCases"] if case.get("withAMovedFolder")]
        self.assertEqual(len(cases), 13)
        first, second = "courses/TST1O/Section 1/Classes/A.md", "courses/TST1O/Section 1/Classes/B.md"
        before_text = "---\ntitle: A\npublish: false\n---\nBody.\n"
        texts = {first: before_text, second: before_text.replace("title: A", "title: B")}
        pages = dict(texts)
        for name, text in self.MEDIA_FILES.items():
            pages[self.MEDIA + "/" + name] = text
        ops = []
        for path, text in texts.items():
            ops += traces.ops_for_change(path, text, text.replace("publish: false", "publish: true"))
        tree = traces.folder_of_pages(pages, self.MEDIA)
        ops.append({"kind": "move", "from": self.MEDIA, "to": self.RENAMED, "listingSha": traces.listing_sha(tree)})
        ops.append({"kind": "replaceText", "path": self.RENAMED + "/a.md", "before": "old", "after": "new",
                    "contextBefore": "Line one: ", "contextAfter": ".\n"})
        after_pages = traces.stopped_part_way(ops, False, pages, None)
        phases = {("step", "nothingTookEffect"): "failed", ("step", "completed"): "done", ("step", "rolledBack"): "rolledBack",
                  ("undo", "nothingTookEffect"): "done", ("undo", "completed"): "undone", ("undo", "rolledBack"): "done",
                  ("redo", "nothingTookEffect"): "undone", ("redo", "completed"): "done", ("redo", "rolledBack"): "undone"}
        for case in cases:
            with self.subTest(case["name"]):
                work, stop = case["work"], case["stopAt"]
                swapped = int(stop.split(":")[1]) if stop.startswith("beforeSwap:") else None
                starting = after_pages if work == "undo" else pages
                left = traces.stopped_part_way(ops, work == "undo", starting, swapped)
                edited = case.get("handEdit")
                if edited is not None:
                    left = self.edited_by_hand(left, edited, first, second)
                outcome, settled, named = traces.recover(ops, left, work != "undo")
                self.assertEqual(phases.get((work, outcome), outcome), case["phase"])
                wanted = {"before": (pages[first], pages[second]), "after": (after_pages[first], after_pages[second]),
                          "firstBeforeSecondEdited": (pages[first], left.get(second))}[case["files"]]
                self.assertEqual((settled.get(first), settled.get(second)), wanted)
                self.assertEqual(self.moved_folder(type("Settled", (), {"pages": settled})), case["movedFolder"])
                if "pathsNamed" in case:
                    pages_named = {"first": first, "second": second}
                    self.assertEqual(named, [pages_named.get(page, page) for page in case["pathsNamed"]])
                else:
                    self.assertEqual(named, [])

    def test_recovery_cases_with_a_handed_over_place(self):
        """undo.recoveryCases' U4b3 door-5 rows (withAHandedOverPlace): a
        step that hands a place over, killed before any of its swaps, going
        forward or back, settles whole, judged by content with the pair
        judged together (door-3)."""
        cases = [case for case in shared_undo()["recoveryCases"] if case.get("withAHandedOverPlace")]
        self.assertEqual(len(cases), 10)
        phases = {("step", "nothingTookEffect"): "failed", ("step", "completed"): "done", ("step", "rolledBack"): "rolledBack",
                  ("undo", "nothingTookEffect"): "done", ("undo", "completed"): "undone", ("undo", "rolledBack"): "done"}
        calls = {"afterALinksMove": "handAPlaceOverAfterALinksMove", "beforeALinksMove": "handAPlaceOverBeforeALinksMove"}
        for case in cases:
            with self.subTest(case["name"]):
                pages = {}
                if case["withAHandedOverPlace"] == "afterALinksMove":
                    pages[self.HANDED_LIBRARY + "/Day 3.md"] = "Linked.\n"
                    pages[self.day(3)] = ("link", self.handed_target(3))
                    ops = ([{"kind": "move", "from": self.day(3), "to": self.day(4), "linkSha": traces.sha(self.handed_target(3))}]
                           + traces.ops_for_change(self.day(3), None, "New.\n"))
                else:
                    self.assertEqual(calls[case["withAHandedOverPlace"]], "handAPlaceOverBeforeALinksMove")
                    pages[self.HANDED_LIBRARY + "/Day 2.md"] = "Two.\n"
                    pages[self.day(2)] = ("link", self.handed_target(2))
                    pages[self.day(3)] = "Three.\n"
                    ops = (traces.ops_for_change(self.day(4), None, "Three.\n")
                           + traces.ops_for_change(self.day(3), "Three.\n", None)
                           + [{"kind": "move", "from": self.day(2), "to": self.day(3), "linkSha": traces.sha(self.handed_target(2))}]
                           + traces.ops_for_change(self.day(2), None, "New.\n"))
                self.assertTrue(traces.handovers(ops))
                work, stop = case["work"], case["stopAt"]
                swapped = int(stop.split(":")[1])
                after_pages = traces.stopped_part_way(ops, False, pages, None)
                starting = after_pages if work == "undo" else pages
                left = traces.stopped_part_way(ops, work == "undo", starting, swapped)
                stopped = left
                if case.get("handEdit") == "handedOverPlace":
                    left = dict(left)
                    left[self.day(3)] = "Someone else's.\n"
                taken = "courses/TST1O/section1/Unit 1, Day 3 (kept by Undo).md"
                if case.get("visibleNameTaken"):
                    left = dict(left)
                    left[taken] = "earlier\n"
                outcome, settled, named = traces.recover(ops, left, work != "undo")
                # U4b3 kept-original-named: a removed page whose place is
                # taken is kept under a visible name, named once each.
                settled, kept_lines = traces.keep_pages_whose_place_is_taken(ops, starting, stopped, settled, outcome)
                self.assertEqual(len(kept_lines), case.get("keptPageLines", 0))
                if "keptVisibleAs" in case:
                    self.assertEqual(kept_lines, [(self.day(3), case["keptVisibleAs"])])
                    self.assertEqual(settled.get(case["keptVisibleAs"]), "Three.\n")
                if case.get("visibleNameTaken"):
                    self.assertEqual(settled.get(taken), "earlier\n")
                self.assertEqual(phases.get((work, outcome), outcome), case["phase"])
                settled_model = type("Settled", (), {"pages": settled})
                if case["files"] != "unchecked":
                    wanted = {"before": pages, "after": after_pages}[case["files"]]
                    self.assertEqual(self.handed_over(settled_model), self.handed_over(type("Wanted", (), {"pages": wanted})))
                self.assertEqual(self.handed_over(settled_model), case["handedOver"])
                self.assertEqual(named, case.get("pathsNamed", []))

    def relinked_days(self, model, days=(3, 4, 5)):
        """U4b3 relink-3's files: what Day 3, Day 4 and Day 5 (or the days
        given) hold, each a page by its text, a link by its text, or
        nothing."""
        parts = []
        for number in days:
            held = model.get(self.day(number))
            if held is None:
                parts.append("Day %d: nothing" % number)
            elif isinstance(held, tuple) and held[0] == "link":
                parts.append("Day %d: link %s" % (number, held[1]))
            else:
                parts.append("Day %d: page %s" % (number, held))
        return "; ".join(parts)

    def test_recovery_cases_with_a_relink(self):
        """undo.recoveryCases' U4b3 relink-3 rows (withARelink): a step
        holding a relinking move, killed before a swap or inside the
        relink's (relinkStaged, relinkRenamedIn), going forward or back,
        settles whole: recovery first removes the link the interrupted swap
        had just made when both stand, then judges by content. mac-1's
        inPlace rows: a relink where the link stands, stopped with its new
        link staged (relinkStaged) or just after its one swap
        (relinkSwapped), settles on the text the place holds."""
        cases = [case for case in shared_undo()["recoveryCases"] if case.get("withARelink")]
        self.assertEqual(len(cases), 21)
        phases = {("step", "nothingTookEffect"): "failed", ("step", "completed"): "done", ("step", "rolledBack"): "rolledBack",
                  ("undo", "nothingTookEffect"): "done", ("undo", "completed"): "undone", ("undo", "rolledBack"): "done"}
        old, new = "Unit 1, Day 3.md", "Unit 1, Day 4.md"

        def relink(start, end, before_text, after_text):
            return {"kind": "move", "from": self.day(start), "to": self.day(end),
                    "linkShaBefore": traces.sha(before_text), "linkShaAfter": traces.sha(after_text),
                    "blobs": [traces.sha(before_text), traces.sha(after_text)],
                    "linkTexts": {traces.sha(before_text): before_text, traces.sha(after_text): after_text}}

        for case in cases:
            with self.subTest(case["name"]):
                self.assertIn(case["withARelink"], ("alone", "leavingAHandedOverPlace", "chained", "chainedThree", "thenAMove", "inPlace"))
                days = (3, 4, 5)
                if case["withARelink"] == "chained":
                    # Review D of U4b3: two relinks that chain, highest first.
                    days = (4, 5, 6)
                    one, two, three = "Unit 1, Day 1.md", "Unit 1, Day 2.md", "Unit 1, Day 3.md"
                    pages = {self.day(4): ("link", one), self.day(5): ("link", two)}
                    ops = [relink(5, 6, two, three), relink(4, 5, one, two)]
                elif case["withARelink"] == "thenAMove":
                    # Review F of U4b3: a relink, then a plain link move into its place.
                    days = (4, 5, 6)
                    two, three = "Unit 1, Day 2.md", "Unit 1, Day 3.md"
                    pages = {self.day(4): ("link", two), self.day(5): ("link", two)}
                    ops = [relink(5, 6, two, three), {"kind": "move", "from": self.day(4), "to": self.day(5), "linkSha": traces.sha(two)}]
                elif case["withARelink"] == "chainedThree":
                    # Review F of U4b3: three relinks that chain, highest first.
                    days = (4, 5, 6, 7)
                    texts = ["Unit 1, Day %d.md" % number for number in range(1, 5)]
                    pages = {self.day(4): ("link", texts[0]), self.day(5): ("link", texts[1]), self.day(6): ("link", texts[2])}
                    ops = [relink(6, 7, texts[2], texts[3]), relink(5, 6, texts[1], texts[2]), relink(4, 5, texts[0], texts[1])]
                elif case["withARelink"] == "inPlace":
                    # mac-1: Day 4's link re-pointed where it stands.
                    pages = {self.day(3): "Three.\n", self.day(4): ("link", old)}
                    ops = [relink(4, 4, old, "Unit 1, Day 5.md")]
                    self.assertTrue(traces.is_a_relink_in_place(ops[0]))
                    self.assertEqual(traces.handovers(ops), [])
                else:
                    pages = {self.day(3): "Three.\n", self.day(4): ("link", old)}
                    ops = [relink(4, 5, old, new)]
                if case["withARelink"] == "leavingAHandedOverPlace":
                    ops.append({"kind": "move", "from": self.day(3), "to": self.day(4), "sha": traces.sha("Three.\n")})
                    ops += traces.ops_for_change(self.day(3), None, "New.\n")
                    self.assertTrue(traces.handovers(ops))
                work, stop = case["work"], case["stopAt"]
                if stop == "beforeApplied":
                    point, number = "beforeSwap", None
                else:
                    point, number = stop.split(":")
                    number = int(number)
                inside = None if point == "beforeSwap" else point
                after_pages = traces.stopped_part_way(ops, False, pages, None)
                starting = after_pages if work == "undo" else pages
                left = traces.stopped_part_way(ops, work == "undo", starting, number, inside)
                if inside == "relinkRenamedIn" and case["withARelink"] == "alone":
                    self.assertIsNotNone(left.get(self.day(4)))
                    self.assertIsNotNone(left.get(self.day(5)))
                outcome, settled, named = traces.recover(ops, left, work != "undo")
                self.assertEqual(phases.get((work, outcome), outcome), case["phase"])
                wanted = {"before": pages, "after": after_pages}[case["files"]]
                self.assertEqual(self.relinked_days(settled, days), self.relinked_days(wanted, days))
                self.assertEqual(named, case.get("pathsNamed", []))

    def test_chained_link_moves_killed_at_every_point_lose_no_link(self):
        """Review F of U4b3, MEDIUM: two and three chained relinks (as
        Insert Class makes them, highest first), and a plain link move
        chained to a relink either way round, killed before each swap,
        inside each relink's (relinkStaged, relinkRenamedIn) and after the
        last (beforeApplied, beforeUndone), going forward or back: recovery
        leaves every link exactly as before or exactly as after the step
        and settles it whole, never interrupted."""
        def relink(start, end, before_text, after_text):
            return {"kind": "move", "from": self.day(start), "to": self.day(end),
                    "linkShaBefore": traces.sha(before_text), "linkShaAfter": traces.sha(after_text),
                    "blobs": [traces.sha(before_text), traces.sha(after_text)],
                    "linkTexts": {traces.sha(before_text): before_text, traces.sha(after_text): after_text}}

        def move(start, end, link_text):
            return {"kind": "move", "from": self.day(start), "to": self.day(end), "linkSha": traces.sha(link_text)}

        def text(day):
            return "Unit 1, Day %d.md" % day

        shapes = []
        for count in (2, 3):
            pages = {}
            ops = []
            for number in range(count):
                pages[self.day(4 + number)] = ("link", text(1 + number))
            for number in reversed(range(count)):
                ops.append(relink(4 + number, 5 + number, text(1 + number), text(2 + number)))
            shapes.append(("%d chained" % count, pages, ops, tuple(range(4, 5 + count))))
        shapes.append(("a move then a relink into its place",
                       {self.day(4): ("link", text(1)), self.day(5): ("link", text(2))},
                       [move(5, 6, text(2)), relink(4, 5, text(1), text(2))], (4, 5, 6)))
        shapes.append(("a relink then a move into its place",
                       {self.day(4): ("link", text(2)), self.day(5): ("link", text(2))},
                       [relink(5, 6, text(2), text(3)), move(4, 5, text(2))], (4, 5, 6)))
        kills = 0
        for label, pages, ops, days in shapes:
            after_pages = traces.stopped_part_way(ops, False, pages, None)
            wanted = (self.relinked_days(pages, days), self.relinked_days(after_pages, days))
            self.assertNotEqual(wanted[0], wanted[1])
            for backward in (False, True):
                starting = after_pages if backward else pages
                order = list(reversed(ops)) if backward else list(ops)
                for swapped in list(range(len(ops))) + [None]:
                    for inside in (None, "relinkStaged", "relinkRenamedIn"):
                        if inside is not None and (swapped is None or "linkShaBefore" not in order[swapped]):
                            continue
                        name = "%s, %s, stopped at %s %s" % (label, "back" if backward else "forward", swapped, inside)
                        with self.subTest(name):
                            left = traces.stopped_part_way(ops, backward, starting, swapped, inside)
                            outcome, settled, _ = traces.recover(ops, left, not backward)
                            self.assertNotEqual(outcome, "interrupted")
                            self.assertIn(self.relinked_days(settled, days), wanted)
                            kills += 1
        # Per shape and way: before each swap, both moments inside each
        # relink's, and the end.
        self.assertEqual(kills, 2 * (2 * 3 + 1) + 2 * (3 * 3 + 1) + 2 * 2 * (2 + 2 + 1))

    def edited_by_hand(self, pages, page, first, second):
        """recoveryCasesHow's handEdit: `first` or `second`, the publish line
        changed by hand (the traces' sameLine edit); `carried`, the line
        `Line one: ...` of a.md set to `Line one: by hand.`, wherever its
        folder is now (U4b2-13)."""
        pages = dict(pages)
        if page == "carried":
            for folder in (self.RENAMED, self.MEDIA):
                path = folder + "/a.md"
                if pages.get(path) is not None:
                    lines = pages[path].split("\n")
                    for index, line in enumerate(lines):
                        if line.startswith("Line one: "):
                            lines[index] = "Line one: by hand."
                    pages[path] = "\n".join(lines)
                    return pages
            self.fail("no a.md to change by hand")
        holder = type("Edited", (), {"pages": pages})()
        self.assertTrue(traces.Model.hand_edit_path(holder, "sameLine", {"first": first, "second": second}[page]))
        return holder.pages

    def test_the_clear_reasons_are_the_four_written(self):
        # Rulings 17 and 18 took the deploy and the share of unit plans off;
        # the director's rulings 1 and 3 on U1's third round added the flip
        # of the switch and an Undo refused for missing content. A reader
        # never checks the reason (stackCases: a reason no reader knows).
        self.assertEqual(shared_undo()["clearReasons"], ["changedSince", "interrupted", "contentMissing", "wentLive"])

    def test_deployed_cases(self):
        # A reference of undo.rule.deployed, written from the words alone,
        # against the contract's cases (UndoWebsite.answer on the mac).
        for case in shared_undo()["deployedCases"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(set(case) - {"name", "moves", "changesMoreThanVisibility", "record", "recordListed", "destinations",
                                              "siteMarkers", "answer", "why"}, set())
                self.assertEqual(deployed_answer(case), case["answer"])

    def test_the_format_names_every_event_and_the_clearing(self):
        with open(REPO / "contracts" / "file-formats.json", encoding="utf-8") as handle:
            journal = json.load(handle)["undoJournal"]
        events = set(journal["events"])
        self.assertEqual(events, {"begin", "applied", "rolledBack", "interrupted", "undoing", "undone",
                                  "redoing", "redone", "failed", "dropped", "pruned", "cleared", "note",
                                  "filesReplacedByARestore"})

    def test_files_replaced_by_a_restore_folds_as_the_contracts_row_says(self):
        with open(REPO / "contracts" / "file-formats.json", encoding="utf-8") as handle:
            moves = json.load(handle)["undoJournal"]["folding"]["moves"]
        rows = [row for row in moves if row["on"] == "filesReplacedByARestore"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["from"], "in flight (begun, undoing, redoing)")
        self.assertEqual(rows[0]["to"], "(no move: its paths join the step's files set aside)")
        model = traces.Model()
        in_flight = model.begin([])
        model.files_replaced_by_a_restore(in_flight, ["courses/ICS3U/a.md"])
        model.files_replaced_by_a_restore(in_flight, ["courses/ICS3U/a.md", "courses/ICS3U/b.md"])
        step = model.find(in_flight)
        self.assertEqual(step["phase"], "begun")
        self.assertEqual(step["setAside"], ["courses/ICS3U/a.md", "courses/ICS3U/b.md"])
        model.finish(in_flight)
        # Not in flight: "anything else" -> ignored.
        model.files_replaced_by_a_restore(in_flight, ["courses/ICS3U/c.md"])
        self.assertEqual(step["phase"], "done")
        self.assertEqual(step["setAside"], ["courses/ICS3U/a.md", "courses/ICS3U/b.md"])


class ContractFileReadabilityTests(unittest.TestCase):
    """Every contract file that Windows PowerShell reads, or may, stays
    readable by its ConvertFrom-Json (#899 W6: shared-rules.json once held
    keys X1 and x1, and windows-app/test_launcher_rules.ps1 could not start)."""

    def test_the_rule_sees_what_windows_powershell_refuses(self):
        self.assertEqual(len(windows_powershell_problems('{"a": {"X1": 1, "x1": 2}}')), 1)
        self.assertEqual(len(windows_powershell_problems('{"a": [{"": 1}]}')), 1)
        self.assertEqual(windows_powershell_problems('{"a": {"X1": 1, "x2": 2, "\u212a": 3, "k": 4}}'), [])

    def test_every_other_contract_file_is_readable_by_windows_powershell(self):
        names = []
        for path in sorted((REPO / "contracts").glob("*.json")):
            names.append(path.name)
            if path.name in NOT_FOR_WINDOWS_POWERSHELL:
                continue
            with self.subTest(path.name):
                self.assertEqual(windows_powershell_problems(path.read_text(encoding="utf-8")), [])
        self.assertIn("shared-rules.json", names)
        for name in NOT_FOR_WINDOWS_POWERSHELL:
            self.assertIn(name, names)

    def test_the_edit_json_cases_live_only_in_their_own_file(self):
        self.assertNotIn("editJSONCases", shared_undo())
        self.assertNotIn("editJSONCasesHow", shared_undo())
        self.assertGreaterEqual(len(json_cases()["editJSONCases"]), 16)


class HandedOverOrderTests(unittest.TestCase):
    """U4b3 door-4: a step that hands a place over is swapped in the step's
    order, reversed going back (opKinds.wholeOps' second exception), as
    UndoCheck.plan orders its targets (doors 1 and 2)."""

    def test_shape_b_goes_in_the_steps_order_and_back_reversed(self):
        day = "courses/TST1O/section1/Unit 1, Day %d.md"
        ops = (traces.ops_for_change(day % 4, None, "Three.\n")
               + traces.ops_for_change(day % 3, "Three.\n", None)
               + [{"kind": "move", "from": day % 2, "to": day % 3, "linkSha": traces.sha("../library/Day 2.md")}]
               + traces.ops_for_change(day % 2, None, "New.\n"))
        self.assertEqual(len(traces.handovers(ops)), 2)
        forward = []
        for group in traces.swap_groups(ops, False):
            forward.append(group[0].get("path") or group[0]["from"])
        self.assertEqual(forward, [day % 4, day % 3, day % 2, day % 2])
        backward = []
        for group in traces.swap_groups(ops, True):
            backward.append(group[0].get("path") or group[0]["from"])
        self.assertEqual(backward, [day % 2, day % 2, day % 3, day % 4])


class OneComparisonTests(unittest.TestCase):
    """U4b2-9: the model's one comparison for "at or inside", and the
    capitalisation-only move's sides told apart by the moved item's own part."""

    def test_the_part_inside_a_place_is_found_without_regard_to_case(self):
        self.assertEqual(traces.part_inside("courses/X/renamed", "courses/X/Renamed/a/b.md"), "a/b.md")
        self.assertEqual(traces.part_inside("courses/X/renamed", "courses/X/RENAMED"), "")
        self.assertIsNone(traces.part_inside("courses/X/renamed", "courses/X/renamedToo/a.md"))

    def test_a_case_only_move_tells_its_sides_apart_by_the_folders_own_part(self):
        move = {"kind": "move", "from": "courses/TST1O/Media", "to": "courses/TST1O/media", "listingSha": "a" * 64}
        at_from = {"kind": "replaceText", "path": "courses/tst1o/Media/a.md"}
        at_to = {"kind": "replaceText", "path": "courses/tst1o/media/a.md"}
        self.assertFalse(traces.move_carries(move, at_from))
        self.assertTrue(traces.move_carries(move, at_to))


if __name__ == "__main__":
    unittest.main(verbosity=2)
