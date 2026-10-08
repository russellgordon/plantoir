#!/usr/bin/env python3
"""The scenes are photographed in ~/Desktop/Teaching, and both folders go back.

Russell, 2026-10-04: no picture may show "Plantoir Marketing". capture.py
moves the marketing folder to the demo folder's path for the scenes, with the
demo folder set aside, rewrites the courses' absolute paths, and puts both
back (MarketingFolderShownAsTeaching). Proved here on temporary folders.

    python3 website/shots/test_shown_folder.py
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import capture  # noqa: E402


class ShownFolder(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.marketing = root / "Plantoir Marketing"
        (self.marketing / "courses" / "ICS3U").mkdir(parents=True)
        (self.marketing / ".plantoir-marketing-folder").write_text("x", encoding="utf-8")
        self.config = self.marketing / "courses" / "ICS3U" / "course_config.json"
        self.config.write_text(json.dumps({"deploy_folder": str(self.marketing / "School Web Space")}),
                               encoding="utf-8")
        self.shown = root / "Desktop" / "Teaching"
        (self.shown / "courses" / "ENG2D").mkdir(parents=True)
        self.aside = root / "Desktop" / ".aside"
        self.saved = (capture.SHOWN_FOLDER, capture.DEMO_SET_ASIDE)
        capture.SHOWN_FOLDER = self.shown
        capture.DEMO_SET_ASIDE = self.aside

    def tearDown(self):
        capture.SHOWN_FOLDER, capture.DEMO_SET_ASIDE = self.saved
        self._tmp.cleanup()

    def test_the_scenes_see_the_marketing_courses_at_the_shown_path_and_both_go_back(self):
        with capture.MarketingFolderShownAsTeaching(self.marketing) as folder:
            self.assertEqual(folder, self.shown)
            self.assertTrue((folder / "courses" / "ICS3U").is_dir())
            self.assertTrue((self.aside / "courses" / "ENG2D").is_dir())
            written = json.loads((folder / "courses" / "ICS3U" / "course_config.json").read_text(encoding="utf-8"))
            self.assertEqual(written["deploy_folder"], str(self.shown / "School Web Space"))
        self.assertTrue((self.shown / "courses" / "ENG2D").is_dir())
        self.assertFalse(self.aside.exists())
        # Kept at the shown path: rewriting it back on every run changed the
        # config's size and time, and marked the section "— Edited".
        kept = json.loads(self.config.read_text(encoding="utf-8"))
        self.assertEqual(kept["deploy_folder"], str(self.shown / "School Web Space"))
        before = self.config.stat().st_mtime_ns
        with capture.MarketingFolderShownAsTeaching(self.marketing):
            pass
        self.assertEqual(self.config.stat().st_mtime_ns, before, "a second run must not touch the config")

    def test_a_path_with_backslashes_and_a_quote_is_found_in_its_json_form(self):
        # #461: on Windows a path's backslashes are doubled inside JSON, so a
        # search for the raw path matched nothing. Written through json.dumps
        # here, so this mac run proves the Windows shape.
        old = 'C:\\Users\\teacher\\Plantoir "Marketing"'
        new = 'C:\\Users\\teacher\\Desktop\\Teaching'
        self.config.write_text(json.dumps({"deploy_folder": old + "\\School Web Space"}), encoding="utf-8")
        self.assertNotIn(old, self.config.read_text(encoding="utf-8"))
        capture.MarketingFolderShownAsTeaching(self.marketing).rewrite(self.marketing, old, new)
        written = json.loads(self.config.read_text(encoding="utf-8"))
        self.assertEqual(written["deploy_folder"], new + "\\School Web Space")

    def test_both_go_back_when_a_scene_fails(self):
        with self.assertRaises(RuntimeError):
            with capture.MarketingFolderShownAsTeaching(self.marketing):
                raise RuntimeError("a scene died")
        self.assertTrue((self.marketing / "courses" / "ICS3U").is_dir())
        self.assertTrue((self.shown / "courses" / "ENG2D").is_dir())

    def test_a_folder_left_set_aside_is_refused(self):
        self.aside.mkdir(parents=True)
        with self.assertRaises(SystemExit):
            with capture.MarketingFolderShownAsTeaching(self.marketing):
                pass
        self.assertTrue((self.shown / "courses" / "ENG2D").is_dir())

    def test_a_shown_path_that_is_not_the_demo_folder_is_never_moved(self):
        (self.shown / "courses" / "ENG2D").rmdir()
        with self.assertRaises(SystemExit):
            with capture.MarketingFolderShownAsTeaching(self.marketing):
                pass
        self.assertTrue(self.shown.is_dir())
        self.assertTrue(self.marketing.is_dir())


if __name__ == "__main__":
    unittest.main()
