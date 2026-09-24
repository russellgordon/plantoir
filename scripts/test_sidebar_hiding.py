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


if __name__ == "__main__":
    unittest.main()
