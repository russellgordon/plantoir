#!/usr/bin/env python3
"""
A section's record of its problems (#717: contracts/shared-rules.json ->
sectionProblems; scripts/section_problems.py).

Every `rowCases` case through the real `made_after_build`; the site's merge
(site_said.py) replacing its rows only in its own build's record; a deploy's
refusal kept, carried and cleared; when a row was first found surviving two
builds; the build's own write through `build_site`'s facts; and the record
never failing a build.

Pure stdlib, no Docker and no network, so Windows' PythonToolchainTests runs
it too. verify.sh runs it, and drives a real broken diagram through two
sections end to end.

Run with:

    python3 scripts/test_section_problems.py
"""
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

REPO_CONTRACTS = Path(__file__).resolve().parent.parent / "contracts"
if REPO_CONTRACTS.is_dir():
    toolchain_paths.CONTRACTS_DIR = REPO_CONTRACTS
contracts.reset_cache()

import section_problems  # noqa: E402
import site_health  # noqa: E402
import site_said  # noqa: E402

HEALTHY = {"media_target_exists": True, "section_index_exists": True}
BUILT_AT = "2026-11-01T13:00:00Z"
FIGURE = {"page": "Unit 1/Graphs", "engine": "tikz", "key": "k1", "block": 2, "line": 14, "blockLine": 3,
          "reason": "undefinedCommand", "name": "\\foo", "said": ""}
FIGURE_ID = "figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1"


def rules(*keys):
    return contracts.section("shared-rules", "sectionProblems", *keys)


def built(facts, previous=None, build_id="B2", course="MPM2D", section=1, pages=None):
    every = dict(HEALTHY)
    every.update(facts)
    return section_problems.made_after_build(previous, course, section, build_id, "preview", every,
                                             pages if pages is not None else [], BUILT_AT)


def previous_record(rows, course="MPM2D", section=1, site_said_complete=True):
    return {"version": 1, "course": course, "section": section, "buildId": "B1",
            "builtAt": "2026-10-30T08:00:00Z", "rows": rows, "siteSaidComplete": site_said_complete}


class RowCases(unittest.TestCase):

    def test_every_row_case(self):
        cases = rules("rowCases", "cases")
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            with self.subTest(case=case["name"]):
                previous = None
                if case["previous"] is not None:
                    previous = previous_record(case["previous"]["rows"])
                record = built(case["facts"], previous)
                expect = case["expect"]
                ids = [row["id"] for row in record["rows"]]
                self.assertEqual(ids, expect["ids"])
                self.assertEqual(record["changed"]["new"], expect["new"])
                self.assertEqual(record["changed"]["gone"], expect["gone"])
                carried = [row["id"] for row in record["rows"] if row.get("carried")]
                self.assertEqual(carried, expect["carried"])
                if "pages" in expect:
                    self.assertEqual([row["page"] for row in record["rows"]], expect["pages"])
                if "firstSeen" in expect:
                    self.assertEqual([row["firstSeen"] for row in record["rows"]], expect["firstSeen"])
                for row, pieces in zip(record["rows"], expect.get("itemHas") or []):
                    for piece in pieces:
                        self.assertIn(piece, row["item"])

    def test_every_check_is_a_kind_and_every_kind_has_a_label_and_a_scope(self):
        kinds = section_problems.kinds()
        for entry in contracts.section("shared-rules", "siteHealth", "checks"):
            self.assertIn(entry["name"], kinds, entry["name"])
        for kind, spec in kinds.items():
            self.assertTrue(spec["label"], kind)
            self.assertIn(spec["scope"], ("page", "section", "course"), kind)
            self.assertIn(spec["from"], ("build", "site", "deploy"), kind)
            if spec.get("facts"):
                self.assertIn(kind, section_problems._MAKERS, kind)
                detail = site_health._checks_by_name()[kind]["detail"]
                self.assertIn("{" + spec["item"] + "}", detail, f"{kind}'s item is a placeholder of its detail")
        state = rules("rowState")
        for kind in state["clearsAcrossSections"]:
            self.assertEqual(kinds[kind]["scope"], "page", kind)
        self.assertNotIn("linksIntoHiddenPages", state["clearsAcrossSections"])
        for kind in state["notAboutThePage"]:
            self.assertIn(kind, state["clearsAcrossSections"])

    def test_a_row_says_what_the_folder_problem_says_about_its_item(self):
        """The row is worded by the finding's own maker with the one item: its
        sentence is the singular sentence and its item the piece the
        finding's detail names - so the console, the HEALTH line and the table
        word a diagram's reason through the same function."""
        record = built({"figure_problems": [FIGURE]})
        row = record["rows"][0]
        finding = site_health.findings(dict(HEALTHY, figure_problems=[FIGURE]), "MPM2D", 1)[0]
        self.assertEqual(row["sentence"], finding.sentence)
        self.assertEqual(row["detail"], finding.detail)
        self.assertIn(row["item"], finding.detail)
        self.assertFalse(row["fixable"])
        self.assertEqual(row["reason"], "undefinedCommand")

    def test_one_row_per_item_of_a_several_finding(self):
        second = dict(FIGURE, key="k2", block=3, line=30)
        record = built({"figure_problems": [FIGURE, second]})
        self.assertEqual(len(record["rows"]), 2)
        finding = site_health.findings(dict(HEALTHY, figure_problems=[FIGURE, second]), "MPM2D", 1)[0]
        for row in record["rows"]:
            self.assertIn(row["item"], finding.detail)
            self.assertNotEqual(row["sentence"], finding.sentence, "each row is the singular sentence")

    def test_a_fixable_problem_is_fixable_in_its_row(self):
        record = built({"section_index_exists": False})
        self.assertEqual([row["kind"] for row in record["rows"]], ["sectionIndexMissing"])
        self.assertTrue(record["rows"][0]["fixable"])


class Prompts(unittest.TestCase):

    def test_a_prompt_is_one_bounded_line_with_no_percent_and_no_double_quote(self):
        said = "! Undefined control sequence.\nl.4 \\foo % a comment \"quoted\"\n" + "x" * 900
        record = built({"figure_problems": [dict(FIGURE, reason="texSaid", said=said)]})
        prompt = record["rows"][0]["prompt"]
        self.assertNotIn("\n", prompt)
        self.assertNotIn("%", prompt)
        self.assertNotIn('"', prompt)
        self.assertLessEqual(len(prompt), rules("prompt", "maxCharacters"))
        self.assertTrue(prompt.endswith("…"))

    def test_ten_prompts_fit_a_windows_command_line_with_room_to_spare(self):
        self.assertLess(10 * rules("prompt", "maxCharacters"), 8191 // 2)


class FirstSeen(unittest.TestCase):

    def test_two_builds_keep_when_it_was_first_found(self):
        folder = Path(tempfile.mkdtemp())
        try:
            facts = dict(HEALTHY, figure_problems=[FIGURE])
            said = []
            section_problems.write_after_build(folder, "MPM2D", 1, "B1", "preview", facts, ["Unit 1/Graphs"],
                                               printer=said.append, built_at="2026-10-30T08:00:00Z")
            section_problems.write_after_build(folder, "MPM2D", 1, "B2", "deploy", facts, ["Unit 1/Graphs"],
                                               printer=said.append, built_at=BUILT_AT)
            record = section_problems.read(folder / section_problems.RECORD_FILE)
            self.assertEqual(record["rows"][0]["firstSeen"], "2026-10-30T08:00:00Z")
            self.assertEqual(record["rows"][0]["lastSeen"], BUILT_AT)
            self.assertEqual(record["occasion"], "deploy")
            self.assertEqual(record["changed"], {"new": [], "gone": []})
            prefix = section_problems.marker_prefix()
            markers = [json.loads(line[len(prefix):]) for line in said if line.startswith(prefix)]
            self.assertEqual([(m["new"], m["gone"], m["rows"]) for m in markers], [(1, 0, 1), (0, 0, 1)])
            self.assertEqual(markers[1]["alertKey"], "B2")
        finally:
            shutil.rmtree(folder)

    def test_another_sections_or_courses_record_is_not_the_previous_one(self):
        record = built({"figure_problems": [FIGURE]},
                       previous_record([{"id": FIGURE_ID, "from": "build", "firstSeen": "2026-10-01T00:00:00Z"}],
                                       section=2))
        self.assertEqual(record["before"], [])
        self.assertEqual(record["rows"][0]["firstSeen"], BUILT_AT)


class TheSiteSays(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.path = self.folder / section_problems.RECORD_FILE

    def tearDown(self):
        shutil.rmtree(self.folder)

    def _write(self, record):
        self.path.write_text(json.dumps(record), encoding="utf-8")

    def _carried_site_row(self):
        return {"id": "runnableCodeShownAsPlainCode|Unit 2/Loops|python|1", "kind": "runnableCodeShownAsPlainCode",
                "page": "Unit 2/Loops", "from": "site", "firstSeen": "2026-10-30T08:00:00Z", "carried": True}

    def test_the_site_saying_nothing_takes_its_carried_rows_away(self):
        record = built({}, previous_record([self._carried_site_row()]))
        self.assertTrue(record["rows"][0]["carried"])
        self._write(record)
        said = []
        section_problems.merge_site_said(self.path, "B2", [], [], "MPM2D", 1, printer=said.append)
        merged = section_problems.read(self.path)
        self.assertEqual(merged["rows"], [])
        self.assertTrue(merged["siteSaidComplete"])
        self.assertEqual(merged["changed"]["gone"], ["runnableCodeShownAsPlainCode|Unit 2/Loops|python|1"])
        self.assertEqual(merged["alertKey"], "B2", "the site's merge keeps the build's alert key")
        self.assertEqual(len(said), 1)

    def test_the_site_saying_again_keeps_when_it_was_first_found(self):
        self._write(built({}, previous_record([self._carried_site_row()])))
        section_problems.merge_site_said(
            self.path, "B2",
            [{"page": "Unit 2/Loops", "language": "python", "block": 1, "line": 6, "reason": "blockNotPrepared"}],
            [], "MPM2D", 1, printer=lambda line: None)
        merged = section_problems.read(self.path)
        self.assertEqual(len(merged["rows"]), 1)
        self.assertEqual(merged["rows"][0]["firstSeen"], "2026-10-30T08:00:00Z")
        self.assertNotIn("carried", merged["rows"][0])
        self.assertEqual(merged["changed"], {"new": [], "gone": []})

    def test_only_its_own_builds_record(self):
        self._write(built({}, previous_record([self._carried_site_row()]), build_id="B3"))
        before = self.path.read_bytes()
        said = []
        section_problems.merge_site_said(self.path, "B2", [], [], "MPM2D", 1, printer=said.append)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(said, [])

    def test_site_said_merges_through_its_command_line_after_its_health_line(self):
        self._write(built({}, previous_record([self._carried_site_row()])))
        payload = {"course": "MPM2D", "section": 1, "places": {}, "swiftNamed": [],
                   "problems": {"file": str(self.path), "buildId": "B2"},
                   "blocks": [{"page": "Units/Other.md", "language": "python", "block": 1,
                               "reason": "blockNotPrepared", "code": "print(1)"}]}
        printed = []
        site_said.say(payload, printer=printed.append)
        health = site_health.marker_prefix()
        problems = section_problems.marker_prefix()
        order = [line.split(":")[0] + ":" for line in printed if line.startswith("PLANTOIR_")]
        self.assertEqual(order, [health, problems])
        merged = section_problems.read(self.path)
        self.assertEqual([row["id"] for row in merged["rows"]], ["runnableCodeShownAsPlainCode|Units/Other|python|1"])

    def test_a_side_file_names_the_record_only_when_given_one(self):
        output = self.folder / "site"
        site_said.write_side_file(output, "MPM2D", 1, {}, [], self.folder)
        written = json.loads((output / "quartz" / site_said.SIDE_FILE).read_text(encoding="utf-8"))
        self.assertNotIn("problems", written)
        site_said.write_side_file(output, "MPM2D", 1, {}, [], self.folder,
                                  problems={"file": self.path, "buildId": "B2"})
        written = json.loads((output / "quartz" / site_said.SIDE_FILE).read_text(encoding="utf-8"))
        self.assertEqual(written["problems"], {"file": str(self.path), "buildId": "B2"})


class TheDeployRefuses(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.path = self.folder / section_problems.RECORD_FILE

    def tearDown(self):
        shutil.rmtree(self.folder)

    def test_a_refusal_is_a_row_with_a_new_alert_key_and_none_clears_it(self):
        self.path.write_text(json.dumps(built({"figure_problems": [FIGURE]})), encoding="utf-8")
        said = []
        section_problems.record_deploy_refusals(self.folder, "B2", "MPM2D", "1",
                                                [("Media/talk.mp4", 40 * 1024 * 1024)], printer=said.append)
        record = section_problems.read(self.path)
        self.assertEqual([row["id"] for row in record["rows"]], [FIGURE_ID, "filesTooLargeForCloudflare|Media/talk.mp4"])
        refusal = record["rows"][1]
        words = rules("deployRefusals", "filesTooLargeForCloudflare")
        self.assertEqual(refusal["sentence"], site_health.filled(words["sentence"], {"course": "MPM2D", "section": "1"}))
        self.assertEqual(refusal["item"], "Media/talk.mp4 (40.0 MB)")
        self.assertEqual(record["section"], 1)
        self.assertNotEqual(record["alertKey"], "B2", "a newly refused deploy keys a new alert")
        self.assertIn("filesTooLargeForCloudflare|Media/talk.mp4", record["changed"]["new"])
        # A preview carries it, never clears it.
        again = built({"figure_problems": [FIGURE]}, record, build_id="B3")
        self.assertEqual([row["id"] for row in again["rows"] if row.get("carried")],
                         ["filesTooLargeForCloudflare|Media/talk.mp4"])
        self.path.write_text(json.dumps(again), encoding="utf-8")
        # A deploy that reaches the check with nothing too large clears it.
        section_problems.record_deploy_refusals(self.folder, "B3", "MPM2D", "1", [], printer=said.append)
        cleared = section_problems.read(self.path)
        self.assertEqual([row["id"] for row in cleared["rows"]], [FIGURE_ID])
        self.assertEqual(cleared["alertKey"], "B3")

    def test_nothing_refused_and_nothing_kept_writes_nothing(self):
        said = []
        section_problems.record_deploy_refusals(self.folder, "B1", "MPM2D", "1", [], printer=said.append)
        self.assertFalse(self.path.exists())
        self.assertEqual(said, [])

    def test_a_section_with_no_record_gets_one_for_the_refusal(self):
        section_problems.record_deploy_refusals(self.folder, "B1", "MPM2D", "1", [("big.pdf", 26 * 1024 * 1024)],
                                                printer=lambda line: None)
        record = section_problems.read(self.path)
        self.assertEqual(record["pagesShown"], [])
        self.assertEqual(record["rows"][0]["kind"], "filesTooLargeForCloudflare")

    def test_deploy_py_clears_only_a_course_that_no_longer_goes_to_cloudflare(self):
        import deploy
        course = self.folder / "COURSE"
        course.mkdir()
        self.assertTrue(deploy.deploys_to_cloudflare(course), "unreadable settings never clear on a guess")
        (course / "course_config.json").write_text(json.dumps({"deploy_target": "netlify"}), encoding="utf-8")
        self.assertFalse(deploy.deploys_to_cloudflare(course))
        (course / "course_config.json").write_text(json.dumps(
            {"deploy_target": "netlify", "additional_deploy_targets": [{"type": "cloudflare_pages"}]}), encoding="utf-8")
        self.assertTrue(deploy.deploys_to_cloudflare(course))


class NeverBreaksABuild(unittest.TestCase):

    def test_a_record_that_cannot_be_written_is_one_plain_line(self):
        folder = Path(tempfile.mkdtemp())
        try:
            blocker = folder / "section1"
            blocker.write_text("a file where the folder belongs", encoding="utf-8")
            said = []
            section_problems.write_after_build(blocker, "MPM2D", 1, "B1", "preview", dict(HEALTHY), [],
                                               printer=said.append)
            self.assertEqual(len(said), 1)
            self.assertTrue(said[0].startswith("ℹ️  "))
            self.assertNotIn("PLANTOIR_", said[0])
        finally:
            shutil.rmtree(folder)

    def test_an_unreadable_previous_record_is_no_previous_record(self):
        folder = Path(tempfile.mkdtemp())
        try:
            (folder / section_problems.RECORD_FILE).write_text("{not json", encoding="utf-8")
            section_problems.write_after_build(folder, "MPM2D", 1, "B1", "preview",
                                               dict(HEALTHY, figure_problems=[FIGURE]), [], printer=lambda line: None)
            record = section_problems.read(folder / section_problems.RECORD_FILE)
            self.assertEqual(record["changed"]["new"], [FIGURE_ID])
        finally:
            shutil.rmtree(folder)


class TheMarker(unittest.TestCase):

    def test_the_example_is_what_the_code_prints(self):
        example = rules("marker", "examples")[0]
        prefix = section_problems.marker_prefix()
        payload = json.loads(example[len(prefix):])
        said = []
        record = {"course": payload["course"], "section": payload["section"], "buildId": payload["buildId"],
                  "alertKey": payload["alertKey"], "rows": [{}] * payload["rows"],
                  "changed": {"new": [""] * payload["new"], "gone": [""] * payload["gone"]}}
        section_problems.announce(record, printer=said.append)
        self.assertEqual(said, [example])

    def test_the_marker_is_machinery(self):
        rule = contracts.section("shared-rules", "transcriptStripping", "machineLines", "rule")
        self.assertIn("PLANTOIR_", rule)
        self.assertRegex(section_problems.marker_prefix(), r"^PLANTOIR_[A-Z_]+:$")


class TheBuildWritesIt(unittest.TestCase):
    """build_site.py writes the record in its ALWAYS section, after the pages
    it shows are known and before the links checklist's offer (source order,
    the way test_build_started_marker pins its own)."""

    def test_the_record_is_written_after_the_pages_shown_and_before_the_offer(self):
        source = (Path(__file__).resolve().parent / "build_site.py").read_text(encoding="utf-8")
        pages = source.index("    visible_places_here = _visible_places(content_root)\n")
        record = source.index("    section_problems.write_after_build(")
        offer = source.index("    _offer_the_links_checklist(content_root, course_dir, course_code, section_number,\n"
                             "                               frozen_course, _this_build_id)")
        health = source.index("    site_health.announce_or_stay_quiet(health_facts, course_code, section_number)")
        quartz = source.index("    _write_site_said(output_dir, content_root, course_code, section_number, swift_here,")
        self.assertLess(health, pages)
        self.assertLess(pages, record)
        self.assertLess(record, offer)
        self.assertLess(record, quartz)


if __name__ == "__main__":
    unittest.main()
