#!/usr/bin/env python3
"""
Two writers, one `course_config.json`, and neither may silently erase the other.

`preflight_update_course_config` reads the configuration, spends a while
scanning the course's folders, and writes what it computed. The APP writes the
same file in that window — renaming a folder does, and it writes at once rather
than at Save, because the folder has really moved. The loser of that race used
to be silent: preflight wrote its own older read back and the rename's keys
vanished, leaving folders moved and the configuration naming the old name.

The write is a compare-and-swap now. This test forces the race rather than
hoping for it: a scan that mutates the file mid-flight, exactly as a rename
landing at the wrong moment would.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import build_site


class ConfigWriteRaceTests(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.course = base / "ADA1O"
        self.section = self.course / "section1"
        (self.section / "All Classes").mkdir(parents=True)
        (self.course / "Concepts").mkdir(parents=True)
        self.config = self.course / "course_config.json"
        self._write({
            "course_code": "ADA1O",
            "section_numbers": [1],
            "shared_folders": [],
            "shared_files": [],
            "per_section_folders": [],
            "per_section_files": [],
            "hidden": [],
            "expandable": [],
        })

    def _write(self, data):
        self.config.write_text(json.dumps(data, indent=2) + "\n")

    def _read(self):
        return json.loads(self.config.read_text())

    def test_a_write_that_lands_mid_scan_is_not_erased(self):
        """
        The app renames a folder while preflight is scanning. Preflight must
        notice and read again, rather than writing its older copy back.
        """
        landed = {"done": False}
        real_discover = build_site.discover_shared_items

        def discover_and_race(course_dir):
            # The app's write, landing at the worst possible moment: after
            # preflight read the file and before it writes.
            if not landed["done"]:
                landed["done"] = True
                config = self._read()
                config["class_folder"] = "All Days"
                config["curriculum_folder"] = "Expectations"
                self._write(config)
            return real_discover(course_dir)

        with patch.object(build_site, "discover_shared_items", discover_and_race):
            build_site.preflight_update_course_config(
                self.course, self.section, self.config
            )

        after = self._read()
        self.assertEqual(
            after.get("class_folder"), "All Days",
            "the rename's key was erased by preflight writing its older read back",
        )
        self.assertEqual(after.get("curriculum_folder"), "Expectations")

    def test_it_still_does_its_own_job(self):
        """The guard must not stop preflight discovering anything."""
        build_site.preflight_update_course_config(self.course, self.section, self.config)
        after = self._read()
        self.assertIn("Concepts", after.get("shared_folders", []))
        self.assertIn("All Classes", after.get("per_section_folders", []))

    def test_a_file_that_never_settles_does_not_spin(self):
        """
        Bounded. A configuration being rewritten continuously must leave the
        build carrying on rather than retrying for ever.
        """
        rewrites = {"count": 0}
        real_discover = build_site.discover_shared_items

        def always_race(course_dir):
            rewrites["count"] += 1
            config = self._read()
            config["footer_html"] = f"changed {rewrites['count']}"
            self._write(config)
            return real_discover(course_dir)

        with patch.object(build_site, "discover_shared_items", always_race):
            result = build_site.preflight_update_course_config(
                self.course, self.section, self.config
            )
        self.assertIsInstance(result, dict)
        self.assertLessEqual(rewrites["count"], 4, "it retried more than its own bound")


if __name__ == "__main__":
    unittest.main(verbosity=2)
