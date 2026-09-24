#!/usr/bin/env python3
"""
What a club starts with, and the class folder a course setup writes (#267).

A course whose pages carry ONE number ("Week 3") is poured no ready-made
course and no skeleton — every page those ship is "Unit 1, Day 1", which is
not a class page under its scheme. It starts instead with each section's
front page headed in its own words and showing the first page, and that first
page. Measured by driving the real `setup_course.py` through a pty for a
club with per_section_folders ["Resources", "All Meetings"]: six Markdown
files, `section1/All Meetings/Week 1.md` among them, and `class_folder`
still "All Meetings" afterwards.

Run with:

    python3 scripts/test_club_start.py
"""
import re
import sys
import unittest
from pathlib import Path
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))

import class_pages  # noqa: E402
from setup_course import ClubStart, class_folder_to_record  # noqa: E402

NOW = "2026-09-24T09:00:00.000-0400"

CLUB = {
    "per_section_folders": ["Resources", "All Meetings"],
    "class_folder": "All Meetings",
    "unit_word": "Week",
    "class_page_scheme": "numbered",
    "front_page_heading": "Most Recent Meeting",
    "class_noun": "meeting",
}


class ClassFolderToRecordTests(unittest.TestCase):

    def test_a_recorded_folder_survives_a_folder_listed_above_it(self):
        self.assertEqual(
            class_folder_to_record(["Resources", "All Meetings"], {"class_folder": "All Meetings"}),
            "All Meetings",
            "The guess alone says Resources, and every planner would look there",
        )

    def test_a_course_with_nothing_recorded_still_gets_the_guess(self):
        self.assertEqual(class_folder_to_record(["Handouts", "All Classes"], {}), "All Classes")
        self.assertEqual(class_folder_to_record(["Resources", "All Meetings"], {}), "Resources")


class ClubStartTests(unittest.TestCase):

    def setUp(self):
        self.start = ClubStart.from_config(CLUB)

    def test_the_front_page_names_the_first_page_under_the_clubs_heading(self):
        self.assertEqual(self.start.front_page_body(), "# Most Recent Meeting\n\n![[Week 1]]\n")

    def test_the_first_page_is_a_class_page_under_its_own_scheme(self):
        pattern = class_pages.class_page_pattern(
            class_pages.word_from_config(CLUB), class_pages.scheme_from_config(CLUB))
        self.assertTrue(re.match(pattern, self.start.first_page_title))
        self.assertTrue(re.match(
            class_pages.first_class_pattern("Week", "numbered"), self.start.first_page_title))

    def test_the_first_page_is_published_dated_and_untagged(self):
        text = self.start.first_page_text(NOW)
        self.assertIn("\ntitle: Week 1\n", text)
        self.assertIn(
            "\npublish: true\n", text,
            "The front page embeds it; a withheld page behind a published embed "
            "is a broken landing page the assistant would not repair",
        )
        self.assertIn(f"\ncreated: {NOW}\n", text)
        self.assertNotIn("unit-", text, "A club has no units, so no unit tag")
        self.assertIn("All Meetings", text)
        self.assertNotIn("All Classes", text)
        self.assertNotIn("Day", text)

    def test_an_absent_heading_takes_the_clubs_default(self):
        start = ClubStart.from_config({**CLUB, "front_page_heading": ""})
        self.assertEqual(start.heading, "Most Recent Meeting")

    def test_the_first_page_is_written_once_and_never_over_a_teachers_page(self):
        with tempfile.TemporaryDirectory() as folder:
            section = Path(folder) / "section1"
            self.start.write_first_page(section, NOW)
            page = section / "All Meetings" / "Week 1.md"
            self.assertTrue(page.exists())
            page.write_text("mine", encoding="utf-8")
            self.start.write_first_page(section, NOW)
            self.assertEqual(page.read_text(encoding="utf-8"), "mine")


if __name__ == "__main__":
    unittest.main()
