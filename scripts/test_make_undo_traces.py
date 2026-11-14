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
        written = (REPO / "contracts" / "undo-traces.json").read_bytes()
        self.assertEqual(
            written, traces.render(traces.generate()),
            "contracts/undo-traces.json is stale: run python3 scripts/make_undo_traces.py",
        )

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

    def test_stack_cases(self):
        for case in shared_undo()["stackCases"]:
            with self.subTest(case=case["name"]):
                model = traces.Model()
                last = None
                written_before = None

                def one_step(days_ago=0):
                    now = traces.reading("publish", model.pages[traces.PATHS["p1"]])
                    line = "publish: false" if now == ("entry", "publish: true") else "publish: true"
                    return model.step([("p1", "publish", line)], days_ago=days_ago)

                cleared = None
                for call in case["calls"]:
                    if call == "step":
                        last = one_step()
                    elif call == "step:31daysAgo":
                        last = one_step(days_ago=31)
                    elif call.startswith("steps:"):
                        for _ in range(int(call.split(":")[1])):
                            last = one_step()
                    elif call == "undo":
                        before = model.head()
                        last = model.undo()
                        if last[0] == "changedSince" and before is not None:
                            cleared = "changedSince"
                    elif call == "redo":
                        last = model.redo()
                    elif call == "editTheLineByHand":
                        self.assertTrue(model.hand_edit("sameLine", "p1"))
                    elif call.startswith("clear:"):
                        written_before = len(model.on_list())
                        model.clear()
                        cleared = call.split(":")[1]
                    else:
                        self.fail("unknown call " + call)
                summary = model.summary()
                self.assertEqual(summary["head"], case["head"])
                self.assertEqual(summary["redo"], case["redo"])
                listed = [step[0] for step in model.on_list()]
                if "onTheList" in case:
                    self.assertEqual(listed, case["onTheList"])
                if "onTheListCount" in case:
                    self.assertEqual(len(listed), case["onTheListCount"])
                    self.assertEqual(listed[0], case["oldestOnTheList"])
                if "expectLast" in case:
                    self.assertEqual(last[0], case["expectLast"])
                if "cleared" in case:
                    self.assertEqual(cleared, case["cleared"])
                if case.get("linesWritten") == 0:
                    self.assertEqual(written_before, 0)

    def test_the_clear_reasons_are_the_three_ruled(self):
        self.assertEqual(shared_undo()["clearReasons"], ["changedSince", "deploy", "shareUnitPlans"])

    def test_the_format_names_every_event_and_the_clearing(self):
        with open(REPO / "contracts" / "file-formats.json", encoding="utf-8") as handle:
            journal = json.load(handle)["undoJournal"]
        events = set(journal["events"])
        self.assertEqual(events, {"begin", "applied", "rolledBack", "undoing", "undone", "redoing",
                                  "redone", "failed", "dropped", "pruned", "cleared"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
