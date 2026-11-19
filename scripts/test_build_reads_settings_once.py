#!/usr/bin/env python3
"""
One build reads `course_config.json` once (#999).

A build used to open the settings file at least five times: to load it, in
preflight, to ask whether the course is kept for reference, to copy it into
the Quartz folder the site's components import, and to copy it to the output
root. A Save landing between two of those reads gave one build a site made
partly from the old settings and partly from the new. Course Settings saving
as it changes (#986) makes that Save likelier, so the build now reads the file
once, at its start, and every later step uses that reading (`BuildSettings`).

Each test here changes the file AFTER the build's reading, the way a Save
landing mid-build would, and checks the step follows the reading, not the file.
"""
import inspect
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

import build_site


class BuildReadsSettingsOnceTests(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.course = base / "ADA1O"
        self.section = self.course / "section1"
        self.section.mkdir(parents=True)
        self.output = base / "output"
        self.output.mkdir()
        self.config_path = self.course / "course_config.json"
        self.settings_at_start = {
            "course_code": "ADA1O",
            "course_name": "Before the save",
            "section_numbers": [1],
            "shared_folders": [],
            "shared_files": [],
            "per_section_folders": [],
            "per_section_files": [],
            "hidden": [],
            "expandable": [],
        }
        self._write(self.settings_at_start)

    def _write(self, data):
        self.config_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def _save_mid_build(self, **changes):
        """A Save from Course Settings, landing after the build has read."""
        saved = json.loads(self.config_path.read_text(encoding="utf-8"))
        for key, value in changes.items():
            saved[key] = value
        self._write(saved)

    def test_the_quartz_copy_is_the_builds_reading_not_a_later_save(self):
        settings = build_site.BuildSettings.read_from(self.config_path)
        bytes_the_build_read = self.config_path.read_bytes()
        self._save_mid_build(course_name="After the save")

        build_site._copy_course_config_into_quartz(self.course, self.output, settings)

        copied = self.output / "quartz" / "course_config.json"
        self.assertEqual(copied.read_bytes(), bytes_the_build_read)
        self.assertEqual(json.loads(copied.read_text(encoding="utf-8"))["course_name"],
                         "Before the save")

    def test_the_root_copy_is_the_builds_reading_not_a_later_save(self):
        settings = build_site.BuildSettings.read_from(self.config_path)
        self._save_mid_build(course_name="After the save")

        root_copy = self.output / "course_config.json"
        build_site._write_the_build_settings(root_copy, settings)

        self.assertEqual(json.loads(root_copy.read_text(encoding="utf-8"))["course_name"],
                         "Before the save")

    def test_preflight_with_nothing_to_add_keeps_the_builds_reading(self):
        """Before #999 preflight opened the file again and built with
        whatever it found there, while the section check had used the first
        reading."""
        settings = build_site.BuildSettings.read_from(self.config_path)
        bytes_the_build_read = self.config_path.read_bytes()
        self._save_mid_build(course_name="After the save")

        after = build_site.preflight_the_build_settings(
            self.course, self.section, self.config_path, settings)

        self.assertEqual(after.config["course_name"], "Before the save")
        self.assertEqual(after.file_bytes, bytes_the_build_read)

    def test_preflight_that_writes_hands_on_exactly_what_it_wrote(self):
        (self.course / "Concepts").mkdir()
        settings = build_site.BuildSettings.read_from(self.config_path)

        after = build_site.preflight_the_build_settings(
            self.course, self.section, self.config_path, settings)

        self.assertIn("Concepts", after.config["shared_folders"])
        self.assertEqual(after.file_bytes, self.config_path.read_bytes())
        self.assertEqual(json.loads(after.file_bytes.decode("utf-8")), after.config)

    def test_a_rename_during_preflight_becomes_the_one_reading(self):
        """The compare-and-swap's retry (#874 and earlier) reads the newer
        file rather than erase a rename. The build then uses THAT reading for
        every later step: its parsed settings and its bytes agree."""
        (self.course / "Concepts").mkdir()
        settings = build_site.BuildSettings.read_from(self.config_path)
        landed = {"done": False}
        real_discover = build_site.discover_shared_items

        def discover_and_race(course_dir):
            if not landed["done"]:
                landed["done"] = True
                self._save_mid_build(class_folder="All Days")
            return real_discover(course_dir)

        with patch.object(build_site, "discover_shared_items", discover_and_race):
            after = build_site.preflight_the_build_settings(
                self.course, self.section, self.config_path, settings)

        self.assertEqual(after.config.get("class_folder"), "All Days")
        self.assertEqual(json.loads(after.file_bytes.decode("utf-8")), after.config)
        self.assertEqual(after.file_bytes, self.config_path.read_bytes())

    def test_a_course_marked_for_reference_mid_build_is_not_frozen_by_this_build(self):
        settings = build_site.BuildSettings.read_from(self.config_path)
        self._save_mid_build(kept_for_reference=True)

        self.assertFalse(settings.is_frozen())

    def test_a_course_unmarked_mid_build_stays_frozen_for_this_build(self):
        self._save_mid_build(kept_for_reference=True)
        settings = build_site.BuildSettings.read_from(self.config_path)
        self._save_mid_build(kept_for_reference=False)

        self.assertTrue(settings.is_frozen())

    def test_a_marker_the_build_cannot_read_freezes_the_course(self):
        """Fail closed, as `reference_course.cannot_tell` does for the file."""
        self.config_path.write_text('{"course_code": "ADA1O", "kept_for_reference": 1}\n',
                                    encoding="utf-8")
        settings = build_site.BuildSettings.read_from(self.config_path)

        self.assertTrue(settings.is_frozen())

    def test_the_build_opens_the_settings_file_in_one_place(self):
        """A guard on the build function itself, so a step added later cannot
        quietly read the file again: the settings file's path is used only to
        check it exists, to read it once, and to hand preflight its
        compare-and-swap target. Nothing in it asks `reference_course`, which
        opens the file, and nothing copies the file."""
        source = inspect.getsource(build_site.build_section_site)
        uses_of_the_path = []
        for line in source.splitlines():
            if re.search(r"\bconfig_file\b", line):
                uses_of_the_path.append(line.strip())
        allowed = [
            'config_file = course_dir / "course_config.json"',
            "if not config_file.exists():",
            "build_settings = BuildSettings.read_from(config_file)",
            "build_settings = preflight_the_build_settings(course_dir, section_dir, config_file, build_settings)",
        ]
        self.assertEqual(uses_of_the_path, allowed)
        self.assertNotIn("reference_course.is_reference(", source)
        self.assertNotIn("reference_course.cannot_tell(", source)
        self.assertNotIn("preflight_update_course_config(", source)
        self.assertNotIn("_copy_course_config_into_quartz(course_dir, output_dir)\n", source)


if __name__ == "__main__":
    unittest.main()
