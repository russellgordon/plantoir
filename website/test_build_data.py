#!/usr/bin/env python3
"""
Unit tests for what build.py reads from data rather than from the pages.

The counts a page quotes, the Mac-only notes, the download cards and the
"New this year" list all come from `support/` and `site.json`, and two
`--check` refusals keep them that way: a count typed into a page, and a word
for the machinery. Pure stdlib, no network. Run with:

    python3 website/test_build_data.py
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build  # noqa: E402


def make_support(root: Path, payloads: dict, catalogue: list) -> Path:
    """A folder shaped like support/: payload manifests and the Ontario list."""
    support = root / "support"
    for code, jurisdiction in payloads.items():
        folder = support / "example_content" / code
        folder.mkdir(parents=True)
        manifest: dict = {"shared_folders": []}
        if jurisdiction is not None:
            manifest["jurisdiction"] = jurisdiction
        (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    listing: dict = {}
    for code in catalogue:
        listing[code] = {"formal_name": code, "short_name": code}
    (support / "ontario_secondary_courses.json").write_text(json.dumps(listing), encoding="utf-8")
    return support


class CountsTests(unittest.TestCase):

    def test_counts_follow_the_folders(self):
        catalogue: list = []
        for number in range(260):
            catalogue.append(f"AAA{number:03d}")
        with tempfile.TemporaryDirectory() as temporary:
            support = make_support(
                Path(temporary),
                {"AAA000": None, "AAA001": "ON", "BCX11": "BC"},
                catalogue,
            )
            counts = build.site_counts(support)
        self.assertEqual(counts["ready_made_ontario"], "2")
        self.assertEqual(counts["ready_made_bc"], "1")
        self.assertEqual(counts["ready_made_other_sentence"], ", and one British Columbia course")
        self.assertEqual(counts["skeleton_codes_exact"], "258")
        self.assertEqual(counts["skeleton_codes"], "300")

    def test_two_british_columbia_courses_are_counted_in_words(self):
        with tempfile.TemporaryDirectory() as temporary:
            support = make_support(Path(temporary), {"A": "BC", "B": "BC"}, ["X"])
            counts = build.site_counts(support)
        self.assertEqual(counts["ready_made_other_sentence"], ", and two British Columbia courses")

    def test_no_other_jurisdiction_says_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            support = make_support(Path(temporary), {"A": None}, ["A", "B"])
            counts = build.site_counts(support)
        self.assertEqual(counts["ready_made_other_sentence"], "")

    def test_real_counts_are_consistent(self):
        counts = build.site_counts()
        payloads = list((build.SUPPORT / "example_content").glob("*/manifest.json"))
        self.assertEqual(int(counts["ready_made_ontario"]) + int(counts["ready_made_bc"]), len(payloads))
        # One of the payloads is British Columbia's; "39 Ontario" was wrong.
        self.assertGreaterEqual(int(counts["ready_made_bc"]), 1)
        catalogue = json.loads((build.SUPPORT / "ontario_secondary_courses.json").read_text(encoding="utf-8"))
        ontario_payload_codes: set = set()
        for manifest_path in payloads:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if str(manifest.get("jurisdiction", "ON")).upper() == "ON":
                ontario_payload_codes.add(manifest_path.parent.name)
        outline_codes = 0
        for code in catalogue:
            if code not in ontario_payload_codes:
                outline_codes += 1
        self.assertEqual(counts["skeleton_codes_exact"], str(outline_codes))

    def test_about_rounds_to_the_nearest_hundred(self):
        self.assertEqual(build.about(1892), "1,900")
        self.assertEqual(build.about(1849), "1,800")


class TypedCountTests(unittest.TestCase):

    def test_typed_count_is_refused(self):
        problems = build.typed_count_problems("x.html", "<p>For 38 Ontario courses, a ready-made course.</p>")
        self.assertEqual(len(problems), 1)
        self.assertIn("x.html:1", problems[0])

    def test_line_number_points_at_the_source(self):
        problems = build.typed_count_problems("x.html", "<p>one</p>\n<p>about 1,900 other codes</p>", first_line=10)
        self.assertEqual(len(problems), 1)
        self.assertIn("x.html:11", problems[0])

    def test_placeholder_is_not_a_typed_count(self):
        problems = build.typed_count_problems("x.html", "<p>For {{ready_made_ontario}} Ontario courses.</p>")
        self.assertEqual(problems, [])

    def test_a_number_in_another_sentence_is_not_a_count(self):
        body = "<p>Windows 10 or 11 (64-bit). A few gigabytes, plus whatever your courses need.</p>"
        self.assertEqual(build.typed_count_problems("x.html", body), [])

    def test_the_real_pages_type_no_count(self):
        for page in build.load_pages():
            self.assertEqual(build.typed_count_problems(page["slug"], page["body"], page["body_line"]), [])


class MachineryTests(unittest.TestCase):

    def test_machinery_word_is_refused(self):
        problems = build.machinery_problems("x.html", "<p>The toolchain builds it.</p>")
        self.assertEqual(len(problems), 1)

    def test_code_and_comments_are_not_read(self):
        body = "<p>Set <code>SUEnableAutomaticChecks</code>.</p><!-- the docker image -->"
        self.assertEqual(build.machinery_problems("x.html", body), [])

    def test_an_api_token_is_allowed(self):
        # Cloudflare asks for an "API token" by that name.
        self.assertEqual(build.machinery_problems("x.html", "<p>Create an API token.</p>"), [])

    def test_the_real_pages_name_no_machinery(self):
        for page in build.load_pages():
            self.assertEqual(build.machinery_problems(page["slug"], page["body"], page["body_line"]), [])


class AvailabilityTests(unittest.TestCase):

    SITE = {"availability": {"note": "On the Mac.", "features": {"clubs": {"windows": False},
                                                                 "maps": {"windows": True}}}}

    def test_availability_renders_until_windows_has_it(self):
        problems: list = []
        self.assertIn("On the Mac.", build.expand_availability("{{availability:clubs}}", self.SITE, problems, "x"))
        self.assertEqual(build.expand_availability("{{availability:maps}}", self.SITE, problems, "x"), "")
        self.assertEqual(problems, [])

    def test_an_unknown_key_is_a_problem(self):
        problems: list = []
        build.expand_availability("{{availability:nothing}}", self.SITE, problems, "x")
        self.assertEqual(len(problems), 1)

    def test_every_key_the_pages_use_is_known(self):
        site = build.read_json(build.WEBSITE / "site.json")
        for page in build.load_pages():
            problems: list = []
            build.expand_availability(page["body"], site, problems, page["slug"])
            self.assertEqual(problems, [])


class DownloadTests(unittest.TestCase):

    def test_download_cards_from_data(self):
        site = {"downloads": [
            {"platform": "macOS", "asset": "Plantoir-macOS.dmg", "meta": "Mac", "pinned": None},
            {"platform": "Windows", "asset": "PlantoirSetup.exe", "meta": "PC", "pinned": "1.1.0"},
        ]}
        html = build.download_cards_html(site)
        self.assertIn("{{repo_url}}/releases/latest/download/Plantoir-macOS.dmg", html)
        self.assertIn("{{repo_url}}/releases/download/v1.1.0/PlantoirSetup.exe", html)
        self.assertIn("PC &middot; version 1.1.0", html)
        self.assertNotIn("Mac &middot; version", html)

    def test_the_windows_card_is_pinned_until_its_installer_ships_again(self):
        site = build.read_json(build.WEBSITE / "site.json")
        pins: dict = {}
        for entry in site["downloads"]:
            pins[entry["platform"]] = entry.get("pinned")
        self.assertIsNone(pins["macOS"])
        self.assertEqual(pins["Windows"], "1.1.0")


class NewInTests(unittest.TestCase):

    def test_new_in_matches_on_major_minor(self):
        self.assertTrue(build.new_in_is_current({"version": "1.4.1", "new_in": {"version": "1.4"}}))
        self.assertFalse(build.new_in_is_current({"version": "1.5.0", "new_in": {"version": "1.4"}}))

    def test_new_in_items_carry_counts_not_numbers(self):
        site = build.read_json(build.WEBSITE / "site.json")
        html = build.new_in_html(site, build.site_counts())
        self.assertIn(build.site_counts()["ready_made_ontario"] + " Ontario courses", html)
        self.assertNotIn("{{ready_made", html)


class AwaitingCaptureTests(unittest.TestCase):

    def test_a_shot_awaiting_capture_renders_nothing_and_is_not_a_problem(self):
        problems: list = []
        shot = {"id": "no-such-shot-anywhere", "alt": "a", "caption": "c", "awaiting_capture": True}
        self.assertEqual(build.picture_element(shot, problems, "", "./"), "")
        self.assertEqual(problems, [])
        notes = build.awaiting_capture_notes({"no-such-shot-anywhere": shot})
        self.assertEqual(len(notes), 1)

    def test_a_missing_shot_without_the_flag_is_still_a_problem(self):
        problems: list = []
        shot = {"id": "no-such-shot-anywhere", "alt": "a", "caption": "c"}
        build.picture_element(shot, problems, "", "./")
        self.assertEqual(len(problems), 1)


if __name__ == "__main__":
    unittest.main()
