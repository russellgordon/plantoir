"""
Tests for the rendered check's two Python helpers (#597): planting the
fixture pages and taking them out again, and the sabotages' guard rails.

    python3 browser-checks/lib/test_rendered_lib.py

No Docker, no browser, no network. verify.sh runs it in 6h-r before the
rendered check, so a planting that would leave a course changed fails there
first.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import plant_rendered  # noqa: E402
import sabotage  # noqa: E402

ROWS = json.loads((HERE.parent / "rendered_rows.json").read_text(encoding="utf-8"))


def make_course(root: Path, config: dict) -> Path:
    course = root / "courses" / "ABC1O"
    course.mkdir(parents=True)
    # Written as the app writes it, byte for byte what remove must restore.
    (course / "course_config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    return course


class PlantAndRemove(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-rendered-test-"))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_plant_then_remove_leaves_the_course_byte_for_byte(self):
        course = make_course(self.root, {"course_code": "ABC1O", "shared_folders": ["Concepts"], "fonts": "{'a': 1}"})
        before = (course / "course_config.json").read_bytes()
        self.assertEqual(plant_rendered.plant(course), 0)
        folder = course / plant_rendered.FOLDER
        pages = sorted(path.name for path in folder.glob("*.md"))
        self.assertEqual(pages, sorted(path.name for path in plant_rendered.PAGES.glob("*.md")))
        self.assertIn(plant_rendered.FOLDER, json.loads((course / "course_config.json").read_text())["shared_folders"])
        with zipfile.ZipFile(folder / plant_rendered.SKETCH_NAME) as sketch:
            self.assertIn('label="A"', sketch.read("geogebra.xml").decode("utf-8"))
        self.assertTrue((folder / plant_rendered.PDF_NAME).read_bytes().startswith(b"%PDF-"))
        self.assertTrue((folder / plant_rendered.PICTURE_NAME).read_bytes().startswith(b"\x89PNG"))
        self.assertEqual(plant_rendered.remove(course), 0)
        self.assertFalse(folder.exists())
        self.assertEqual((course / "course_config.json").read_bytes(), before)

    def test_remove_after_the_settings_changed_takes_out_only_its_entry(self):
        course = make_course(self.root, {"course_code": "ABC1O", "shared_folders": ["Concepts"]})
        plant_rendered.plant(course)
        config = json.loads((course / "course_config.json").read_text())
        config["hidden"] = ["Media"]
        (course / "course_config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        plant_rendered.remove(course)
        after = json.loads((course / "course_config.json").read_text())
        self.assertEqual(after["shared_folders"], ["Concepts"])
        self.assertEqual(after["hidden"], ["Media"])

    def test_a_folder_of_the_teachers_own_is_never_replaced(self):
        course = make_course(self.root, {"shared_folders": []})
        own = course / plant_rendered.FOLDER
        own.mkdir()
        (own / "Mine.md").write_text("a teacher's page\n", encoding="utf-8")
        self.assertEqual(plant_rendered.plant(course), 1)
        self.assertEqual(plant_rendered.remove(course), 0)
        self.assertTrue((own / "Mine.md").is_file())

    def test_an_already_shared_folder_is_left_shared(self):
        course = make_course(self.root, {"shared_folders": [plant_rendered.FOLDER]})
        before = (course / "course_config.json").read_bytes()
        plant_rendered.plant(course)
        self.assertEqual((course / "course_config.json").read_bytes(), before)
        plant_rendered.remove(course)
        self.assertEqual((course / "course_config.json").read_bytes(), before)


class Sabotages(unittest.TestCase):
    def test_every_sabotage_has_a_way_to_be_done_and_aims_at_a_real_row(self):
        rows = {row["name"]: row for row in ROWS["rows"]}
        named = [one["name"] for one in ROWS["sabotages"]]
        self.assertEqual(sorted(named), sorted(sabotage.DOERS))
        for one in ROWS["sabotages"]:
            self.assertIn(one["aims"], rows, one["name"])
            self.assertIn(one["page"], ROWS["pages"], one["name"])
            target = rows[one["aims"]]
            self.assertIn(target["page"], (one["page"], "*"), one["name"])
            for other in one["alsoRed"]:
                self.assertIn(other, rows, one["name"])
            self.assertTrue(one["reason"].strip(), one["name"])

    def test_every_row_but_embeds_is_proven_red_by_some_sabotage(self):
        aimed = {one["aims"] for one in ROWS["sabotages"]}
        unproven = [row["name"] for row in ROWS["rows"] if row["name"] not in aimed]
        # Embeds run on deployed sites only; their proof is #597's second half.
        self.assertEqual(unproven, ["embeds"])

    def test_every_fixture_page_is_named(self):
        pages = {path.stem for path in plant_rendered.PAGES.glob("*.md")}
        self.assertEqual(pages, set(ROWS["pages"]))
        for page, address in ROWS["pages"].items():
            self.assertEqual(address, "Rendered-Check/" + page.replace(" ", "-"))

    def test_refuses_a_folder_without_the_pages(self):
        empty = Path(tempfile.mkdtemp(prefix="plantoir-rendered-test-"))
        try:
            answer = subprocess.run([sys.executable, str(HERE / "sabotage.py"), "apply", str(empty), "clean page"],
                                    capture_output=True, text=True)
            self.assertEqual(answer.returncode, 1)
            self.assertIn("none of the rendered check's pages", answer.stdout)
        finally:
            shutil.rmtree(empty)

    def test_refuses_a_courses_real_site(self):
        root = Path(tempfile.mkdtemp(prefix="plantoir-rendered-test-"))
        try:
            site = root / "EXC2O" / ".merged_output" / "section1" / "public"
            (site / "Rendered-Check").mkdir(parents=True)
            (site / "Rendered-Check" / "Diagrams.html").write_text("<head></head>", encoding="utf-8")
            answer = subprocess.run([sys.executable, str(HERE / "sabotage.py"), "apply", str(site), "tikz size"],
                                    capture_output=True, text=True)
            self.assertEqual(answer.returncode, 1)
            self.assertIn("refuses a course's real site", answer.stdout)
            self.assertEqual((site / "Rendered-Check" / "Diagrams.html").read_text(encoding="utf-8"), "<head></head>")
        finally:
            shutil.rmtree(root)


if __name__ == "__main__":
    unittest.main()
