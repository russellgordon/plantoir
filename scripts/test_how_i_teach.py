#!/usr/bin/env python3
"""
The teacher's How I Teach page is never on the website (#209) — the build's
half, against the CONTRACT.

The name cases are not retyped here: they are read from
`contracts/shared-rules.json` -> `howITeachPage.nameCases`, the list the macOS
suite runs against `HowITeachPage` and the Windows suite will run against its
own listing. The build's rule is shared Python, so this file is the Windows
gate for it too — `PythonToolchainTests` discovers every `scripts/test_*.py`.

Stdlib only. `build_site` imports without python-frontmatter (it is optional
at import time), and nothing here calls `process_frontmatter`, so these run
on a machine without it rather than skipping. The copy loops themselves run
only inside a real build, so `verify.sh` covers them against the real image
(its "How I Teach page never reaches the site" block); what is tested here is
what each function can actually be made to fail.
"""
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import contracts
import toolchain_paths


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


use_the_repository_contract()

import build_site
import how_i_teach


def rule(*keys):
    return contracts.section("shared-rules", "howITeachPage", *keys)


class NameCaseTests(unittest.TestCase):
    """Every `nameCases` case, as the build reads it."""

    def setUp(self):
        use_the_repository_contract()

    def test_there_are_cases_to_run(self):
        self.assertGreaterEqual(len(rule("nameCases")), 10)

    def test_every_name_case(self):
        for case in rule("nameCases"):
            with self.subTest(path=case["path"]):
                self.assertEqual(
                    how_i_teach.is_reserved_place(case["path"]), case["reserved"],
                    f"{case['path']!r}: {case['why']}",
                )

    def test_the_fallback_name_is_the_contracts(self):
        # Edit either and this goes red: the fallback exists only for a
        # contract that cannot be read, and must never be a second answer.
        self.assertEqual(how_i_teach._FALLBACK_FILE_NAME, rule("fileName"))
        self.assertEqual(how_i_teach._FALLBACK_KEPT_OFF_LINE, rule("keptOffTheWebsiteLine"))
        self.assertEqual(how_i_teach._FALLBACK_LOOK_ALIKE_LINE, rule("lookAlikeLine"))
        self.assertEqual(how_i_teach._FALLBACK_MARKER_PREFIX, rule("keptOffMarker", "prefix"))

    def test_a_look_alike_is_named_and_the_page_is_not(self):
        self.assertTrue(how_i_teach.looks_like_the_page("How I Teach 1.md"))
        self.assertTrue(how_i_teach.looks_like_the_page("how i teach ICS4U.md"))
        self.assertFalse(how_i_teach.looks_like_the_page("How I Teach.md"))
        self.assertFalse(how_i_teach.looks_like_the_page("HOW I TEACH.MD"))
        self.assertFalse(how_i_teach.looks_like_the_page("How I Teach 1.txt"))
        self.assertFalse(how_i_teach.looks_like_the_page("Teaching Notes.md"))


class CourseOnDisk(unittest.TestCase):
    """A scratch course with the page at both reserved places and one near-miss."""

    def setUp(self):
        use_the_repository_contract()
        self.temp = tempfile.TemporaryDirectory()
        self.course_dir = Path(self.temp.name) / "ICS4U"
        self.section_dir = self.course_dir / "section1"
        self.section_dir.mkdir(parents=True)
        (self.course_dir / "Concepts").mkdir()
        (self.course_dir / "How I Teach.md").write_text("course page\n", encoding="utf-8")
        (self.section_dir / "HOW I TEACH.md").write_text("section page\n", encoding="utf-8")
        (self.course_dir / "Concepts" / "How I Teach.md").write_text("ordinary\n", encoding="utf-8")
        (self.course_dir / "How I Teach 1.md").write_text("duplicate\n", encoding="utf-8")
        (self.course_dir / "Key Links.md").write_text("links\n", encoding="utf-8")
        (self.section_dir / "index.md").write_text("front\n", encoding="utf-8")
        self.config_path = self.course_dir / "course_config.json"

    def tearDown(self):
        self.temp.cleanup()

    def write_config(self, config):
        self.config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


class DiscoveryTests(CourseOnDisk):

    def test_discovery_never_lists_the_page_at_the_top_of_the_course(self):
        folders, files = build_site.discover_shared_items(self.course_dir)
        self.assertNotIn("How I Teach.md", files)
        self.assertIn("How I Teach 1.md", files, "a look-alike is an ordinary page")
        self.assertIn("Key Links.md", files)
        self.assertIn("Concepts", folders)

    def test_discovery_never_lists_the_page_at_the_top_of_a_section(self):
        _, files = build_site.discover_section_items(self.section_dir)
        self.assertNotIn("HOW I TEACH.md", files)


class PreflightTests(CourseOnDisk):

    def test_an_already_listed_page_is_dropped_and_written_back(self):
        # A course whose page predates the rule: discovery used to list it.
        self.write_config({
            "shared_folders": ["Concepts"],
            "shared_files": ["Key Links.md", "How I Teach.md"],
            "per_section_folders": [],
            "per_section_files": ["HOW I TEACH.md"],
        })
        with redirect_stdout(io.StringIO()):
            returned = build_site.preflight_update_course_config(
                self.course_dir, self.section_dir, self.config_path
            )
        written = json.loads(self.config_path.read_text(encoding="utf-8"))
        for config in (returned, written):
            self.assertNotIn("How I Teach.md", config["shared_files"])
            self.assertNotIn("HOW I TEACH.md", config["per_section_files"])
            self.assertIn("Key Links.md", config["shared_files"])

    def test_the_config_a_build_is_handed_without_a_write_drops_it_too(self):
        corrected = build_site._dropping_excluded_items({
            "shared_files": ["how i teach.md", "Key Links.md"],
            "per_section_files": ["How I Teach.md"],
        })
        self.assertEqual(corrected["shared_files"], ["Key Links.md"])
        self.assertEqual(corrected["per_section_files"], [])

    def test_the_copy_lists_are_filtered_where_they_are_read(self):
        kept, dropped = how_i_teach.keep_off_the_site(["A.md", "HOW I TEACH.MD", "How I Teach 1.md"])
        self.assertEqual(kept, ["A.md", "How I Teach 1.md"])
        self.assertEqual(dropped, ["HOW I TEACH.MD"])


class SweepTests(CourseOnDisk):

    def test_the_sweep_removes_the_page_from_the_top_of_the_content_only(self):
        content = Path(self.temp.name) / "content"
        (content / "Concepts").mkdir(parents=True)
        (content / "How I Teach.md").write_text("x", encoding="utf-8")
        (content / "Concepts" / "How I Teach.md").write_text("y", encoding="utf-8")
        (content / "index.md").write_text("z", encoding="utf-8")
        removed = build_site.how_i_teach.remove_from_content_root(content)
        self.assertEqual(removed, ["How I Teach.md"])
        self.assertFalse((content / "How I Teach.md").exists())
        self.assertTrue((content / "Concepts" / "How I Teach.md").exists(),
                        "inside a folder it is an ordinary page — the sweep is not recursive")
        self.assertTrue((content / "index.md").exists())
        # The teacher's own folder is never touched by the sweep.
        self.assertTrue((self.course_dir / "How I Teach.md").exists())


class AnnouncementTests(unittest.TestCase):

    def setUp(self):
        use_the_repository_contract()

    def said(self, **arguments):
        lines = []
        how_i_teach.announce(printer=lines.append, **arguments)
        return lines

    def test_a_page_found_is_said_once_with_no_marker(self):
        lines = self.said(course="ICS4U", section_number=1, found_here=True,
                          look_alikes=[], dropped_places=[])
        self.assertEqual(lines, [rule("keptOffTheWebsiteLine")])

    def test_nothing_found_says_nothing(self):
        self.assertEqual(self.said(course="ICS4U", section_number=1, found_here=False,
                                   look_alikes=[], dropped_places=[]), [])

    def test_a_look_alike_is_named(self):
        lines = self.said(course="ICS4U", section_number=1, found_here=False,
                          look_alikes=["How I Teach 1.md"], dropped_places=[])
        self.assertEqual(lines, [rule("lookAlikeLine").replace("{name}", "How I Teach 1")])

    def test_a_listed_page_dropped_prints_the_marker_the_app_reads(self):
        lines = self.said(course="ICS4U", section_number=2, found_here=True,
                          look_alikes=[], dropped_places=["How I Teach", "section2/How I Teach"])
        self.assertEqual(lines[0], rule("keptOffTheWebsiteLine"))
        prefix = rule("keptOffMarker", "prefix")
        self.assertTrue(lines[-1].startswith(prefix + " "), lines[-1])
        payload = json.loads(lines[-1][len(prefix):])
        self.assertEqual(payload, {"course": "ICS4U", "section": 2,
                                   "pages": ["How I Teach", "section2/How I Teach"]})

    def test_the_marker_matches_the_contracts_own_example(self):
        example = rule("keptOffMarker", "examples")[0]
        lines = self.said(course="ICS4U", section_number=1, found_here=True,
                          look_alikes=[], dropped_places=["How I Teach"])
        self.assertEqual(lines[-1], example)


if __name__ == "__main__":
    unittest.main()
