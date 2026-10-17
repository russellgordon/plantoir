#!/usr/bin/env python3
"""
The setup wizard's own backup leaves Plantoir's Obsidian add-ons out (#495,
plan review S8) - the second writer that zips a whole course, beside the mac's
CourseArchiver.

Runs `contracts/shared-rules.json` -> `obsidianAddOnsForFigures.backups.cases`
against `setup_course.backup_existing_course_dir`: a folder under
`.obsidian/plugins` that carries Plantoir's `.plantoir` marker is left out, the
teacher's own add-ons and the list are kept. By MARKER, never by name.

Pure stdlib, no Docker. Run with:

    python3 scripts/test_backup_leaves_plantoir_addons.py
"""

import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

import setup_course  # noqa: E402


def backups_rules() -> dict:
    with open(REPOSITORY_ROOT / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
        return json.load(handle)["obsidianAddOnsForFigures"]["backups"]


class WizardBackupLeavesPlantoirsAddOnsOut(unittest.TestCase):

    def test_every_backups_case(self):
        cases = backups_rules()["cases"]
        self.assertGreaterEqual(len(cases), 2)
        for case in cases:
            with self.subTest(case["name"]), tempfile.TemporaryDirectory() as scratch:
                course = Path(scratch) / "courses" / "MPM2D"
                plugins = course / ".obsidian" / "plugins"
                plugins.mkdir(parents=True)
                (course / ".obsidian" / "app.json").write_text("{}", encoding="utf-8")
                (course / ".obsidian" / "community-plugins.json").write_text("[]", encoding="utf-8")
                (course / "index.md").write_text("# Hi\n", encoding="utf-8")
                for folder, state in case["plugins"].items():
                    (plugins / folder).mkdir()
                    (plugins / folder / "main.js").write_text("x", encoding="utf-8")
                    if state.get("marker"):
                        (plugins / folder / ".plantoir").write_text(
                            '{"addedBy":"Plantoir","version":"0.5.2"}', encoding="utf-8")
                zip_path = setup_course.backup_existing_course_dir(course, Path(scratch) / "_backups")
                with zipfile.ZipFile(zip_path) as archive:
                    names = set(archive.namelist())
                for path in case["inZip"]:
                    self.assertIn(path, names, f"{path} is missing from the wizard's backup")
                for path in case["notInZip"]:
                    self.assertNotIn(path, names, f"{path} is in the wizard's backup")
                self.assertIn("index.md", names)

    def test_a_folder_called_plugins_elsewhere_is_kept(self):
        """The rule is a place (.obsidian/plugins), not a name."""
        with tempfile.TemporaryDirectory() as scratch:
            course = Path(scratch) / "MPM2D"
            elsewhere = course / "Unit 1" / "plugins" / "obsidian-tikzjax"
            elsewhere.mkdir(parents=True)
            (elsewhere / ".plantoir").write_text("{}", encoding="utf-8")
            (elsewhere / "notes.md").write_text("mine", encoding="utf-8")
            zip_path = setup_course.backup_existing_course_dir(course, Path(scratch) / "_backups")
            with zipfile.ZipFile(zip_path) as archive:
                self.assertIn("Unit 1/plugins/obsidian-tikzjax/notes.md", archive.namelist())


if __name__ == "__main__":
    unittest.main()
