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
- a trace with no hand edits and no clearing ends its undos exactly at the
  fixture: undo-all is the identity;
- the reference model agrees with the contract's own checkCases and
  stackCases, so the cases and the traces cannot drift apart.

Run with:

    python3 -B scripts/test_make_undo_traces.py
"""
import json
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
                self.assertIn(call["call"], ("step", "undo", "redo", "handEdit", "clear"), call)
                self.assertIn("head", call)
                self.assertIn("redo", call)
                if call["call"] in ("step", "undo", "redo"):
                    self.assertIn("expect", call)

    def test_no_trace_holds_a_refused_redo(self):
        # What a refused Redo does to the list is not ruled.
        for trace in committed()["traces"]:
            for call in trace["calls"]:
                if call["call"] == "redo":
                    self.assertIn(call["expect"], ("redone", "nothingToRedo"), trace["name"])

    def test_the_traces_reach_every_outcome_u1_rules_on(self):
        seen = set()
        for trace in committed()["traces"]:
            for call in trace["calls"]:
                seen.add((call["call"], call.get("expect") or call.get("kind") or call.get("reason")))
        for wanted in [("step", "applied"), ("step", "changedNothing"), ("undo", "undone"),
                       ("undo", "changedSince"), ("undo", "nothingToUndo"), ("redo", "redone"),
                       ("redo", "nothingToRedo"), ("handEdit", "body"), ("handEdit", "sameLine"),
                       ("handEdit", "otherKey"), ("clear", "deploy"), ("clear", "shareUnitPlans")]:
            self.assertIn(wanted, seen)

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


def readable_op(op):
    """UndoOp.shapeIsKnown, as the contract's opKinds and unknown say."""
    kind = op.get("kind")
    path = op.get("path")
    if kind not in ("writeFile", "editLine", "recompute") or not isinstance(path, str):
        return False
    parts = path.split("/")
    if path.startswith("/") or "\\" in path or any(part in ("", ".", "..") for part in parts):
        return False
    for key in ("before", "after", "key", "afterKey"):
        if key in op and op[key] is not None and not isinstance(op[key], str):
            return False
    if kind == "editLine":
        return isinstance(op.get("key"), str) and (op.get("before") is not None or op.get("after") is not None)
    return True


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

    def test_check_cases(self):
        cases = shared_undo()["checkCases"]
        self.assertGreaterEqual(len(cases), 20)
        for case in cases:
            with self.subTest(case=case["name"]):
                op = dict(case["op"])
                if not readable_op(op):
                    self.assertEqual(case["undo"], "notReadable")
                    self.assertEqual(case["redo"], "notReadable")
                    continue
                if op["kind"] == "writeFile":
                    op["beforeSha"] = None if op["beforeText"] is None else traces.sha(op["beforeText"])
                    op["afterSha"] = None if op["afterText"] is None else traces.sha(op["afterText"])
                text, is_absent_or_text = self.current_text(case["current"])
                if text is None and not is_absent_or_text:
                    state = "neither"
                elif text is None and op["kind"] == "writeFile":
                    state = traces.op_state(op, None)
                else:
                    state = traces.op_state(op, text)
                undo = {"after": "canUndo", "before": "alreadyBack", "neither": "changedSince"}[state]
                redo = {"before": "canRedo", "after": "alreadyRedone", "neither": "changedSince"}[state]
                self.assertEqual(undo, case["undo"])
                self.assertEqual(redo, case["redo"])

    STACK_KEYS = {"name", "calls", "head", "redo", "onTheList", "onTheListCount", "oldestOnTheList",
                  "expectLast", "cleared", "clearedSeq", "linesWritten", "onTheDisk", "physicallyPruned",
                  "blobKept", "pendingRuling"}

    def test_stack_cases(self):
        folder_b = "@B/"
        for case in shared_undo()["stackCases"]:
            with self.subTest(case=case["name"]):
                unknown = set(case) - self.STACK_KEYS
                self.assertEqual(unknown, set(), "a key the replay does not check")
                self.assertIn("head", case)
                self.assertIn("redo", case)
                p1 = traces.PATHS["p1"]
                pages = {p1: traces.START["p1"], folder_b + p1: traces.START["p1"]}
                model = traces.Model(pages)
                last = None
                cleared = []
                held = None
                lines_before = None

                def one_step(path, days_ago=0):
                    now = traces.reading("publish", model.pages[path])
                    line = "publish: false" if now == ("entry", "publish: true") else "publish: true"
                    return model.step([(path, "publish", line)], days_ago=days_ago)

                for call in case["calls"]:
                    if call == "step":
                        last = one_step(p1)
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
                        if last[0] == "changedSince":
                            cleared.append(("changedSince", had))
                    elif call == "redo":
                        last = model.redo()
                    elif call == "editTheLineByHand":
                        self.assertTrue(model.hand_edit_path("sameLine", p1))
                    elif call.startswith("clear:"):
                        lines_before = len(cleared)
                        if model.clear():
                            cleared.append((call.split(":")[1], model.highest))
                        model.prune()
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
                    elif call == "foreignStep":
                        seq = model.begin([{"kind": "move", "from": "a", "to": "b"}], readable=False)
                        model.find(seq)["phase"] = "done"
                    elif call == "begin:held":
                        now = traces.reading("publish", model.pages[p1])
                        line = "publish: false" if now == ("entry", "publish: true") else "publish: true"
                        after = traces.setting_entry("publish", line, model.pages[p1])
                        held = (model.begin(traces.ops_for_change(p1, model.pages[p1], after)), after)
                    elif call == "finish:held":
                        model.pages[p1] = held[1]
                        model.finish(held[0])
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
                    self.assertEqual(len(cleared) - (lines_before or 0), case["linesWritten"])

    def test_the_clear_reasons_are_the_four_ruled(self):
        self.assertEqual(shared_undo()["clearReasons"], ["changedSince", "deploy", "shareUnitPlans", "interrupted"])

    def test_the_format_names_every_event_and_the_clearing(self):
        with open(REPO / "contracts" / "file-formats.json", encoding="utf-8") as handle:
            journal = json.load(handle)["undoJournal"]
        events = set(journal["events"])
        self.assertEqual(events, {"begin", "applied", "rolledBack", "interrupted", "undoing", "undone",
                                  "redoing", "redone", "failed", "dropped", "pruned", "cleared"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
