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


def committed():
    with open(REPO / "contracts" / "undo-traces.json", encoding="utf-8") as handle:
        return json.load(handle)


FRAGMENT = re.compile(r"^(\d{8}T\d{6}Z)-(.+)\.json$")


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
                self.assertEqual(result, ("ready", {path: text}), page_id)

    def test_a_body_edit_leaves_the_line_op_undoable(self):
        _, path, text, _ = traces.FIXTURE[0]
        after = traces.setting_entry("publish", "publish: true", text)
        ops = traces.ops_for_change(path, text, after)
        self.assertEqual(ops[0]["kind"], "editLine")
        edited = after + "Written since.\n"
        result = traces.plan(ops, True, {path: edited})
        self.assertEqual(result, ("ready", {path: text + "Written since.\n"}))


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
    return first == second or first.startswith(second + "/") or second.startswith(first + "/")


def readable_op(op):
    """UndoOp.shapeIsKnown, as the contract's opKinds and unknown say."""
    kind = op.get("kind")
    if kind not in KINDS_KNOWN:
        return False
    for key in ("blobs",):
        if key in op and not (isinstance(op[key], list) and all(is_blob_name(name) for name in op[key])):
            return False
    for key in ("beforeSha", "afterSha", "sha", "listingSha"):
        if key in op and op[key] is not None and not is_blob_name(op[key]):
            return False
    if kind == "move":
        if "path" in op or not safe_path(op.get("from")) or not safe_path(op.get("to")):
            return False
        if overlap(op["from"], op["to"]):
            return False
        return ("sha" in op) != ("listingSha" in op)
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


KINDS_KNOWN = ("writeFile", "editLine", "recompute", "replaceText", "editJSON", "move",
               "createTree", "removeTree", "external")
EXTERNAL_TARGETS_KNOWN = ("preference",)
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
    return True


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
        if "listing" in op:
            tree = op.pop("listing")
            op["listingSha"] = traces.listing_sha(tree)
            if op["kind"] in ("createTree", "removeTree"):
                op["blobs"] = [op["listingSha"]] + [traces.sha(text) for text in tree["files"].values()]
        for key in [key for key, value in op.items() if value is None and key in ("beforeSha", "afterSha")]:
            del op[key]
        return op

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
                if kind == "recompute":
                    # No check (opKinds.recompute): re-derived, never compared.
                    state = "after"
                elif kind == "move":
                    state = traces.move_state(op, current["atFrom"], current["atTo"])
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
                undo = {"after": "canUndo", "before": "alreadyBack", "neither": "changedSince"}[state]
                redo = {"before": "canRedo", "after": "alreadyRedone", "neither": "changedSince"}[state]
                self.assertEqual(undo, case["undo"])
                self.assertEqual(redo, case["redo"])

    def test_listing_cases(self):
        cases = shared_undo()["listingCases"]
        self.assertGreaterEqual(len(cases), 3)
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(traces.listing_text(case["tree"]), case["listing"])
                self.assertEqual(traces.listing_sha(case["tree"]), case["listingSha"])

    STACK_KEYS = {"name", "calls", "head", "redo", "onTheList", "onTheListCount", "oldestOnTheList",
                  "expectLast", "cleared", "clearedSeq", "linesWritten", "onTheDisk", "physicallyPruned",
                  "blobKept", "interrupted", "markers", "folderKept", "rederived"}

    MARKER_FROM = "courses/TST1O/.netlify_sites/section1.json"
    MARKER_TO = "courses/TST1O/.netlify_sites/section1.previous.json"
    OLD_MARKER = "{\"site_id\": \"aaa-111\"}\n"
    NEW_MARKER = "{\"site_id\": \"bbb-222\"}\n"
    EXTRA = "courses/TST1O/extra"
    EXTRA_TREE = {"folders": ["sub"], "files": {"a.md": "A\n", "sub/b.md": "B\n"}}
    SETTINGS = "courses/TST1O/settings.json"
    NOTES = "courses/TST1O/notes.md"
    PREFERENCE = "preference:undoCasesPreference"

    def kind_call(self, call, model):
        """U2's calls (stackCasesHow), on the model's pages. Answers what
        `last` becomes, or None."""
        pages = model.pages
        if call == "moveTheMarker":
            if pages.get(self.MARKER_FROM) is None and pages.get(self.MARKER_TO) is None:
                pages[self.MARKER_FROM] = self.OLD_MARKER
            content = pages.get(self.MARKER_FROM) or ""
            return model.ops_step([{"kind": "move", "from": self.MARKER_FROM, "to": self.MARKER_TO, "sha": traces.sha(content)}])
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
        if call == "forgetTheMaintainer":
            model.maintainer_registered = False
            return None
        self.fail("unknown call " + call)

    def markers(self, model):
        source, destination = model.pages.get(self.MARKER_FROM), model.pages.get(self.MARKER_TO)
        if source is None and destination == self.OLD_MARKER:
            return "moved"
        if source == self.OLD_MARKER and destination is None:
            return "movedBack"
        if source == self.NEW_MARKER and destination == self.OLD_MARKER:
            return "bothKept"
        return (source, destination)

    KIND_CALLS = ("moveTheMarker", "deployANewMarker", "makeAFolder", "addAFileToTheFolder", "removeTheFolder",
                  "editTheSettings", "editTheSettingsByHand", "editAHunk", "setAPreference",
                  "changeThePreferenceByHand", "forgetTheMaintainer")

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
                    elif call == "removeContent":
                        model.content_removed = True
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
                        else:
                            self.fail("unknown variant " + variant)
                        seq = model.begin(ops, readable=readable_step(step))
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
                if "folderKept" in case:
                    self.assertEqual(isinstance(model.pages.get(self.EXTRA), tuple), case["folderKept"])
                if "rederived" in case:
                    self.assertEqual(model.rederived, case["rederived"])

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
                self.assertEqual(set(case) - {"name", "moves", "changesMoreThanVisibility", "record", "destinations",
                                              "siteMarkers", "answer", "why"}, set())
                self.assertEqual(deployed_answer(case), case["answer"])

    def test_the_format_names_every_event_and_the_clearing(self):
        with open(REPO / "contracts" / "file-formats.json", encoding="utf-8") as handle:
            journal = json.load(handle)["undoJournal"]
        events = set(journal["events"])
        self.assertEqual(events, {"begin", "applied", "rolledBack", "interrupted", "undoing", "undone",
                                  "redoing", "redone", "failed", "dropped", "pruned", "cleared", "note"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
