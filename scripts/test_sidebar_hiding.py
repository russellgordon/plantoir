#!/usr/bin/env python3
"""
Issue #265: the "Hide from the site's sidebar" list (`hidden` in
course_config.json) and the built sidebar must agree.

Driven from `contracts/file-formats.json` -> `sidebarHiding`, so the cases are
data both platforms read: this file runs in verify.sh and in Windows'
PythonToolchainTests. Pure Python, temporary folders, no Docker.
"""
import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import contracts
import toolchain_paths
import build_site
import setup_course


class TheBuildNeverChangesHidden(unittest.TestCase):
    """`sidebarHiding.buildKeepsHidden`: preflight adds a discovered folder to
    its scope's list and to `expandable`, and leaves `hidden` exactly as the
    teacher saved it."""

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.cases = contracts.section("file-formats", "sidebarHiding", "buildKeepsHidden", "cases")

    def test_there_are_cases(self):
        self.assertGreaterEqual(len(self.cases), 5)

    def test_every_case(self):
        for case in self.cases:
            with self.subTest(case["name"]):
                self._run_case(case)

    def _run_case(self, case):
        with tempfile.TemporaryDirectory() as temp_name:
            course_dir = Path(temp_name) / "C"
            section_dir = course_dir / "section1"
            section_dir.mkdir(parents=True)
            for name in case["sharedOnDisk"]:
                (course_dir / name).mkdir()
                (course_dir / name / "index.md").write_text("x", encoding="utf-8")
            for name in case["perSectionOnDisk"]:
                (section_dir / name).mkdir()
                (section_dir / name / "index.md").write_text("x", encoding="utf-8")
            config = {
                "shared_files": [],
                "per_section_files": [],
                "expandable": [],
            }
            config.update(case["config"])
            config_path = course_dir / "course_config.json"
            config_path.write_text(json.dumps(config, ensure_ascii=False), encoding="utf-8")

            output = io.StringIO()
            with patch("sys.stdout", output):
                build_site.preflight_update_course_config(course_dir, section_dir, config_path)

            on_disk = json.loads(config_path.read_text(encoding="utf-8"))
            self.assertEqual(on_disk.get("hidden"), case["expectHidden"],
                             "the build changed `hidden`:\n" + output.getvalue())
            self.assertNotIn("Un-hid", output.getvalue())
            for list_key, names in case["expectAdded"].items():
                for name in names:
                    self.assertIn(name, on_disk.get(list_key, []),
                                  f"{name} was not added to {list_key}")
                    self.assertIn(name, on_disk.get("expandable", []),
                                  f"{name} was not added to expandable")


# The v1.3.1 filter, exactly as sections built before issue #265 carry it.
VERSION_1_BLOCK = """Component.Explorer({
    folderClickBehavior: "collapse",
    filterFn: (node) => {
      // CQ4T-OMIT-ANCHOR: do not remove this line; build script overwrites this Set
      const omit = new Set(["Media", "Key Links", "Curriculum Coverage"])
      if (node.isFolder) {
        return !omit.has(node.fileSegmentHint);
      } else {
        return !omit.has(node.data.title);
      }
    },
  })"""


def quartz_shaped_layout(block: str) -> str:
    """Two Explorers, the way Quartz 4.5's layout has them."""
    return (
        'import { PageLayout, SharedLayout } from "./quartz/cfg"\n'
        'import * as Component from "./quartz/components"\n\n'
        "export const defaultContentPageLayout: PageLayout = {\n"
        "  left: [\n    Component.PageTitle(),\n    " + block + ",\n  ],\n}\n\n"
        "export const defaultListPageLayout: PageLayout = {\n"
        "  left: [\n    Component.PageTitle(),\n    " + block + ",\n  ],\n  right: [],\n}\n"
    )


class TheSidebarMatchesStoredTopLevelNames(unittest.TestCase):
    """`sidebarHiding.matchRule`. What the rule DOES is checked against the
    real Quartz by `check_sidebar_hiding_against_the_site.py` (verify.sh);
    this checks, without Node, what the build writes and repairs."""

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.cases = contracts.section("file-formats", "sidebarHiding", "matchRule", "cases")

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.layout = Path(self.temp_dir.name) / "quartz.layout.ts"

    def tearDown(self):
        self.temp_dir.cleanup()

    def _quietly(self, function, *arguments):
        with patch("sys.stdout", io.StringIO()) as output:
            result = function(*arguments)
        return result, output.getvalue()

    def test_the_cases_are_well_formed(self):
        self.assertGreaterEqual(len(self.cases), 10)
        for case in self.cases:
            with self.subTest(case["name"]):
                items = []
                for path in case["paths"]:
                    parts = path.split("/")
                    for depth in range(1, len(parts)):
                        items.append("/".join(parts[:depth]) + "/")
                    items.append(path)
                for item in case["expectHidden"]:
                    self.assertIn(item, items)

    def test_the_omit_set_keeps_the_stored_names(self):
        self.layout.write_text(quartz_shaped_layout(setup_course.EXPLORER_BLOCK), encoding="utf-8")
        self._quietly(build_site.update_quartz_layout, self.layout,
                      ["Key Links.md", "Tasks", 'Bob\'s "Stuff"'])
        text = self.layout.read_text(encoding="utf-8")
        self.assertIn('const omit = new Set(["Key Links.md", "Tasks", "Bob\'s \\"Stuff\\""])', text)
        self.assertEqual(text.count("const omit = new Set(["), 2)

    def test_the_build_hides_media_and_the_coverage_page_by_file_name(self):
        names = build_site.names_the_sidebar_hides(["Tasks"])
        self.assertIn("Media", names)
        self.assertIn(build_site.COVERAGE_PAGE_TITLE + ".md", names)
        again = build_site.names_the_sidebar_hides(["media", "curriculum coverage.md"])
        self.assertEqual(again, ["media", "curriculum coverage.md"])

    def test_the_filter_has_the_shape_the_patchers_and_the_browser_need(self):
        block = setup_course.EXPLORER_BLOCK
        self.assertIn(setup_course.HIDE_RULE_MARKER, block)
        self.assertTrue(build_site._anchor_is_structurally_wired(block))
        match = re.search(r"Component\.Explorer\(\s*\{[\s\S]*?\}\s*\)", block)
        self.assertEqual(match.group(0), block, "a `}` then `)` inside the block cuts it short")
        self.assertNotIn("\\", block, "the patchers use this text as a regex replacement")
        # Quartz bundles with keepNames, which breaks a named inner function
        # once the filter is rebuilt from its text in the browser.
        self.assertIsNone(re.search(r"const\s+\w+\s*=\s*(\(|function)", block))
        self.assertNotIn("function ", block)

    def test_the_repair_brings_an_old_layout_to_the_current_rule(self):
        self.layout.write_text(quartz_shaped_layout(VERSION_1_BLOCK), encoding="utf-8")
        repaired, output = self._quietly(build_site.ensure_sidebar_hide_rule_current, self.layout)
        self.assertTrue(repaired)
        self.assertIn("Brought the sidebar's hide rule up to date", output)
        text = self.layout.read_text(encoding="utf-8")
        self.assertEqual(text.count(setup_course.HIDE_RULE_MARKER), 2)
        self.assertEqual(text.count("Component.Explorer("), 2)
        self.assertNotIn("node.data.title", text)
        self.assertTrue(build_site._anchor_is_structurally_wired(text))

        again, output_again = self._quietly(build_site.ensure_sidebar_hide_rule_current, self.layout)
        self.assertTrue(again)
        self.assertEqual(output_again, "")
        self.assertEqual(self.layout.read_text(encoding="utf-8"), text)

        # The per-build patches that follow still find their fields.
        self._quietly(build_site.update_quartz_layout, self.layout, ["Tasks"])
        self._quietly(build_site.patch_folder_click_behavior, self.layout, True)
        final = self.layout.read_text(encoding="utf-8")
        self.assertEqual(final.count('folderClickBehavior: "collapse"'), 2)
        self.assertEqual(final.count('const omit = new Set(["Tasks"])'), 2)
        self.assertEqual(final.count(setup_course.HIDE_RULE_MARKER), 2)

    def test_a_hand_edited_explorer_is_refused_not_guessed(self):
        self.layout.write_text(
            quartz_shaped_layout("Component.Explorer(myOwnOptions)"), encoding="utf-8"
        )
        repaired, output = self._quietly(build_site.ensure_sidebar_hide_rule_current, self.layout)
        self.assertFalse(repaired)
        self.assertIn("Could not bring the sidebar's hide rule up to date", output)


if __name__ == "__main__":
    unittest.main()
