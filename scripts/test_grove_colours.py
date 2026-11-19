#!/usr/bin/env python3
"""
Grove Colours: one scheme kept under two ids (GitHub #891).

A colour scheme used to be stored under an id that named one school. Russell
ruled on 2026-11-13 that it is kept, renamed "Grove Colours" and offered to
everyone, that a course already using it looks exactly the same, and that
neither opening its settings nor re-running the command-line set-up rewrites
its colours. support/colour_schemes.json therefore holds two entries with the
same name and colours: the listed `grove-colours`, and the old id marked
"listed": false with "sameAs": "grove-colours". The rule the pickers follow is
contracts/shared-rules.json -> colourSchemePicker, and its cases run here
against setup_course.schemes_to_list, as the mac's ColourSchemePickerTests run
them against ColourSchemeCatalog.schemesToList.

The old id is never written in this file: it is read from the scheme list,
the one shipped file that has to hold it.

Pure Python with no shell, so Windows' PythonToolchainTests runs it as well.
"""

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
sys.path.insert(0, str(HERE))

import build_site  # noqa: E402
import setup_course  # noqa: E402
import social_card  # noqa: E402

SCHEMES_FILE = REPOSITORY / "support" / "colour_schemes.json"
SHARED_RULES_FILE = REPOSITORY / "contracts" / "shared-rules.json"
NEW_ID = "grove-colours"
NAME = "Grove Colours"


def read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def is_listed(scheme):
    return scheme.get("listed", True) is not False


def unlisted_twin_of(schemes, listed_id):
    for scheme in schemes:
        if not is_listed(scheme) and scheme.get("sameAs") == listed_id:
            return scheme
    return None


def ids_of(schemes):
    result = []
    for scheme in schemes:
        result.append(scheme.get("id"))
    return result


class TheTwoEntries(unittest.TestCase):

    def setUp(self):
        self.schemes = read_json(SCHEMES_FILE)
        self.new = build_site.find_scheme_by_id(self.schemes, NEW_ID)
        self.twin = unlisted_twin_of(self.schemes, NEW_ID)

    def test_grove_colours_is_listed_under_its_new_id(self):
        self.assertIsNotNone(self.new)
        self.assertEqual(self.new["name"], NAME)
        self.assertTrue(is_listed(self.new))

    def test_the_old_id_is_kept_unlisted_with_the_same_name_and_colours(self):
        self.assertIsNotNone(self.twin, "the old entry must stay, or courses that use it change colour")
        self.assertNotEqual(self.twin["id"], NEW_ID)
        self.assertEqual(self.twin["name"], NAME)
        self.assertEqual(self.twin["colors"], self.new["colors"])

    def test_every_unlisted_entry_names_a_listed_one_with_its_name_and_colours(self):
        for scheme in self.schemes:
            if is_listed(scheme):
                continue
            same = build_site.find_scheme_by_id(self.schemes, scheme.get("sameAs"))
            self.assertIsNotNone(same, f"{scheme['id']}: sameAs names no entry")
            self.assertTrue(is_listed(same), f"{scheme['id']}: sameAs names an unlisted entry")
            self.assertEqual(scheme["name"], same["name"], scheme["id"])
            self.assertEqual(scheme["colors"], same["colors"], scheme["id"])

    def test_ids_are_unique(self):
        ids = ids_of(self.schemes)
        self.assertEqual(len(ids), len(set(ids)))


class EveryReaderDrawsTheSameColours(unittest.TestCase):
    """A course on either id looks the same: the website, the Coverage tab
    and the sharing card all find the colours."""

    def setUp(self):
        self.schemes = read_json(SCHEMES_FILE)
        self.old_id = unlisted_twin_of(self.schemes, NEW_ID)["id"]
        self.colours = build_site.find_scheme_by_id(self.schemes, NEW_ID)["colors"]

    def test_the_build_finds_both_ids(self):
        for scheme_id in (self.old_id, NEW_ID):
            found = build_site.find_scheme_by_id(build_site.load_colour_schemes(), scheme_id)
            self.assertIsNotNone(found, scheme_id)
            self.assertEqual(found["colors"], self.colours, scheme_id)

    def test_the_coverage_tab_finds_both_ids(self):
        for scheme_id in (self.old_id, NEW_ID):
            config = {"color_schemes": {"section1": scheme_id}}
            self.assertEqual(build_site.coverage_tab_scheme_colours(config, 1), self.colours, scheme_id)

    def test_the_sharing_card_finds_both_ids(self):
        for scheme_id in (self.old_id, NEW_ID):
            self.assertEqual(social_card._load_scheme_colors(scheme_id), self.colours["lightMode"], scheme_id)


class ThePickerRule(unittest.TestCase):
    """shared-rules.json -> colourSchemePicker.cases, through the
    command-line picker's list."""

    def setUp(self):
        self.schemes = read_json(SCHEMES_FILE)
        self.rule = read_json(SHARED_RULES_FILE)["colourSchemePicker"]

    def expected_ids(self, takes_the_place_of, twin_id):
        result = []
        for scheme in self.schemes:
            if not is_listed(scheme):
                continue
            if scheme["id"] == takes_the_place_of:
                result.append(twin_id)
            else:
                result.append(scheme["id"])
        return result

    def test_the_contract_cases(self):
        self.assertTrue(len(self.rule["cases"]) >= 5)
        for case in self.rule["cases"]:
            if "sectionSchemeIsTheUnlistedTwinOf" in case:
                twin = unlisted_twin_of(self.schemes, case["sectionSchemeIsTheUnlistedTwinOf"])
                stored = twin["id"]
                selected = stored
                expected = self.expected_ids(case.get("twinTakesThePlaceOf"), stored)
            else:
                stored = case["sectionScheme"]
                selected = case["selected"]
                expected = self.expected_ids(None, None)
            listed = setup_course.schemes_to_list(self.schemes, stored)
            self.assertEqual(ids_of(listed), expected, case["name"])
            names = []
            for scheme in listed:
                names.append(scheme["name"])
            self.assertEqual(len(names), len(set(names)), case["name"] + ": a name is shown twice")
            if selected:
                self.assertIn(selected, ids_of(listed) + [case.get("sectionScheme")], case["name"])

    def test_enter_on_a_rerun_keeps_the_old_id(self):
        """The command-line picker starts on the section's own scheme, so
        Enter keeps the id the course already has: nothing is rewritten."""
        old_id = unlisted_twin_of(self.schemes, NEW_ID)["id"]
        original_getch = setup_course.getch
        original_render = setup_course.render_scheme_preview_for_section
        try:
            setup_course.getch = lambda: "ENTER"
            setup_course.render_scheme_preview_for_section = lambda *arguments: None
            for stored in (old_id, NEW_ID, "quartz-standard", "coastal-breeze"):
                chosen = setup_course.interactive_pick_scheme_for_section(
                    self.schemes, section_number=1, default_id=stored)
                self.assertEqual(chosen, stored)
        finally:
            setup_course.getch = original_getch
            setup_course.render_scheme_preview_for_section = original_render

    def test_a_new_course_is_never_offered_the_old_id(self):
        old_id = unlisted_twin_of(self.schemes, NEW_ID)["id"]
        for stored in (None, "", "quartz-standard", NEW_ID):
            self.assertNotIn(old_id, ids_of(setup_course.schemes_to_list(self.schemes, stored)))


if __name__ == "__main__":
    unittest.main()
