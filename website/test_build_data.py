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

    def test_a_school_year_is_not_a_count(self):
        self.assertEqual(build.typed_count_problems("x", "Reference Courses, 2025–26, and a course"), [])

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

    def test_neither_card_is_pinned_while_the_newest_release_has_both_installers(self):
        # Windows was pinned to 1.1.0 from v1.2.0 until PlantoirSetup.exe
        # joined v1.4.2 (2026-10-03), and to 1.4.2 for the mac-first v1.4.3
        # cut (2026-10-04) until its installer joined v1.4.3 (2026-10-07).
        # A release that lacks an installer pins that card again, and this
        # test changes with it (the downloads_note in site.json says when).
        site = build.read_json(build.WEBSITE / "site.json")
        pins: dict = {}
        for entry in site["downloads"]:
            pins[entry["platform"]] = entry.get("pinned")
        self.assertIsNone(pins["macOS"])
        self.assertIsNone(pins["Windows"])


class NewInTests(unittest.TestCase):

    def test_new_in_matches_on_major_minor(self):
        self.assertTrue(build.new_in_is_current({"version": "1.4.1", "new_in": {"version": "1.4"}}))
        self.assertFalse(build.new_in_is_current({"version": "1.5.0", "new_in": {"version": "1.4"}}))

    def test_new_in_items_carry_counts_not_numbers(self):
        site = build.read_json(build.WEBSITE / "site.json")
        html = build.new_in_html(site, build.site_counts())
        self.assertIn(build.site_counts()["ready_made_ontario"] + " Ontario courses", html)
        self.assertNotIn("{{ready_made", html)


class FragmentTests(unittest.TestCase):

    def test_a_link_to_a_missing_section_is_a_problem(self):
        rendered = {"index": '<a href="./features/#nowhere">x</a>', "features": '<section id="here"></section>'}
        self.assertEqual(len(build.broken_fragment_problems(rendered)), 1)

    def test_a_link_to_a_section_that_exists_is_fine(self):
        rendered = {"index": '<a href="./features/#here">x</a>', "features": '<section id="here"></section>'}
        self.assertEqual(build.broken_fragment_problems(rendered), [])


class RedirectTests(unittest.TestCase):
    """A page that moved keeps its old address (#443: /publishing/ became
    /deploying/), and nothing on the site still points at the old one."""

    SITE = {"nav": ["index", "deploying"], "redirects": {"moved": [{"from": "publishing", "to": "deploying"}]}}

    def test_the_old_address_and_everything_under_it_redirect_permanently(self):
        text = build.redirects_text(self.SITE)
        self.assertIn("/publishing    /deploying/    301!", text)
        self.assertIn("/publishing/*    /deploying/:splat    301!", text)

    def test_the_real_site_moves_publishing_to_deploying(self):
        site = json.loads((build.WEBSITE / "site.json").read_text(encoding="utf-8"))
        self.assertIn({"from": "publishing", "to": "deploying"}, build.moved_pages(site))
        self.assertIn("deploying", site["nav"])
        self.assertNotIn("publishing", site["nav"])
        self.assertFalse((build.WEBSITE / "pages" / "publishing.html").exists())
        self.assertTrue((build.WEBSITE / "pages" / "deploying.html").exists())

    def test_a_clean_move_has_no_problems(self):
        rendered = {"features": '<a href="../deploying/#on-a-schedule">how</a>'}
        self.assertEqual(build.redirect_problems(self.SITE, ["index", "deploying"], rendered), [])

    def test_a_link_to_the_old_address_is_a_problem(self):
        rendered = {"features": '<a href="../publishing/#on-a-schedule">how</a>'}
        problems = build.redirect_problems(self.SITE, ["index", "deploying"], rendered)
        self.assertEqual(len(problems), 1)
        self.assertIn("features.html links to publishing/", problems[0])

    def test_a_root_relative_or_absolute_link_to_the_old_address_is_a_problem(self):
        for href in ("/publishing/", "/publishing/#on-a-schedule", "https://plantoir.app/publishing/"):
            rendered = {"features": f'<a href="{href}">how</a>'}
            problems = build.redirect_problems(self.SITE, ["index", "deploying"], rendered)
            self.assertEqual(len(problems), 1, href)

    def test_a_link_that_only_ends_in_the_old_name_is_not_a_problem(self):
        rendered = {"features": '<a href="https://example.com/publishing/">elsewhere</a>'}
        self.assertEqual(build.redirect_problems(self.SITE, ["index", "deploying"], rendered), [])

    def test_serve_answers_head_and_get_for_the_old_address_with_the_same_301(self):
        import functools
        import http.client
        import socketserver
        import threading

        class QuietHandler(build.MovedPagesHandler):
            def log_message(self, format, *arguments):
                pass

        with tempfile.TemporaryDirectory() as temporary:
            handler = functools.partial(QuietHandler, directory=temporary)
            with socketserver.ThreadingTCPServer(("127.0.0.1", 0), handler) as server:
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                try:
                    port = server.server_address[1]
                    for method in ("GET", "HEAD"):
                        for path, expected in (("/publishing", "/deploying/"),
                                               ("/publishing/", "/deploying/"),
                                               ("/publishing/index.html", "/deploying/index.html")):
                            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                            connection.request(method, path)
                            response = connection.getresponse()
                            response.read()
                            connection.close()
                            self.assertEqual(response.status, 301, f"{method} {path}")
                            self.assertEqual(response.getheader("Location"), expected, f"{method} {path}")
                finally:
                    server.shutdown()

    def test_a_missing_new_page_or_a_lingering_old_one_is_a_problem(self):
        self.assertEqual(len(build.redirect_problems(self.SITE, ["index"], {})), 1)
        self.assertEqual(len(build.redirect_problems(self.SITE, ["index", "deploying", "publishing"], {})), 1)

    def test_the_old_pages_built_copy_is_removed(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "publishing").mkdir()
            (output / "publishing" / "index.html").write_text("old", encoding="utf-8")
            (output / "deploying").mkdir()
            build.remove_moved_output(self.SITE, output)
            self.assertFalse((output / "publishing").exists())
            self.assertTrue((output / "deploying").exists())


class DeployWordTests(unittest.TestCase):
    """DEPLOY puts a site online; PUBLISH only marks a page (#443). Every
    "publish" the site shows must be one of the page-marking sentences build.py
    names; the rest say deploy. The site's half of scripts/test_deploy_words.py,
    turned round: an allowlist rather than a list of old phrases, because the
    site is small enough to name every sentence that may say publish."""

    def test_the_sites_own_words_say_deploy_for_a_deploy(self):
        found: list[str] = []
        for page in build.load_pages():
            name = page["slug"] + ".html"
            found += build.deploy_word_problems(name, page["body"])
            for key in ("title", "description", "nav_label"):
                found += build.deploy_word_problems(f"{name} {key}", page[key], readable=False)
        for layout in sorted((build.WEBSITE / "layout").glob("*.html")):
            found += build.deploy_word_problems(layout.name, layout.read_text(encoding="utf-8"))
        shots = json.loads((build.WEBSITE / "shots.json").read_text(encoding="utf-8"))["shots"]
        for shot in shots:
            for key, text in build.shot_texts(shot):
                found += build.deploy_word_problems(f"shots.json {shot['id']} {key}", text, readable=False)
        site = json.loads((build.WEBSITE / "site.json").read_text(encoding="utf-8"))
        for key, text in build.site_json_texts(site):
            found += build.deploy_word_problems(f"site.json {key}", text, readable=False)
        self.assertEqual(found, [], "the site says publish for a deploy (#443)")

    def test_a_deploy_in_the_old_word_is_refused(self):
        self.assertTrue(build.deploy_word_problems("x", "<p>A failed publish changes nothing.</p>"))
        self.assertTrue(build.deploy_word_problems("x", "Publish on a schedule, and hear how it went.", readable=False))
        self.assertTrue(build.deploy_word_problems("x", "<h2>Publishing</h2>"))
        self.assertTrue(build.deploy_word_problems("x", "It is never published.", readable=False))

    def test_marking_a_page_is_allowed_and_code_is_not_read(self):
        self.assertEqual(build.deploy_word_problems("x", "<li>Publish or hold back a class.</li>"), [])
        self.assertEqual(build.deploy_word_problems("x", "<p>A line reading <code>publishForSection1: true</code>.</p>"), [])
        # The allowed sentence still counts when the page wraps it over two lines.
        self.assertEqual(build.deploy_word_problems("x", "<p>until you publish it\n  and deploy.</p>"), [])

    def test_a_shot_waiting_for_its_retake_is_read_by_its_new_words(self):
        shot = {"id": "s", "alt": "saying it published on its own.", "retake": {"alt": "saying it deployed on its own."},
                "parts": {"banner": {"expectText": ["deployed on its own"]}}}
        keys = [key for key, _ in build.shot_texts(shot)]
        self.assertEqual(keys, ["retake alt", "banner expectText"])
        shot["parts"]["banner"]["expectText"] = ["published on its own"]
        found = []
        for key, text in build.shot_texts(shot):
            found += build.deploy_word_problems(key, text, readable=False)
        self.assertEqual(len(found), 1)


class ReleaseReadinessTests(unittest.TestCase):

    def test_pages_ahead_of_the_release_are_not_deployed(self):
        site = {"version": "1.3.1", "new_in": {"version": "1.4"}}
        self.assertIn("Not deploying", build.release_readiness_refusal(site, {"shots": []}))

    def test_a_missing_awaited_picture_is_not_deployed(self):
        site = {"version": "1.4.0", "new_in": {"version": "1.4"}}
        shots = {"shots": [{"id": "no-such-shot-anywhere", "awaiting_capture": True}]}
        self.assertIn("no-such-shot-anywhere", build.release_readiness_refusal(site, shots))

    def test_a_missing_picture_waiting_on_a_named_issue_is_deployed(self):
        site = {"version": "1.4.0", "new_in": {"version": "1.4"}}
        shots = {"shots": [{"id": "no-such-shot-anywhere", "awaiting_capture": True, "waiting_on": "#367"}]}
        self.assertIsNone(build.release_readiness_refusal(site, shots))

    def test_waiting_on_must_name_an_issue(self):
        site = {"version": "1.4.0", "new_in": {"version": "1.4"}}
        shots = {"shots": [{"id": "no-such-shot-anywhere", "awaiting_capture": True, "waiting_on": "later"}]}
        self.assertIn("no-such-shot-anywhere", build.release_readiness_refusal(site, shots))

    def test_a_ready_release_deploys(self):
        site = {"version": "1.4.1", "new_in": {"version": "1.4"}}
        self.assertIsNone(build.release_readiness_refusal(site, {"shots": []}))


# A Windows picture that cannot be taken yet, each with what blocks it. Every
# other id must be `windows: true` (Russell, 2026-10-04). Empty since that day:
# `schedule`, the last, is the sheet alone on Windows, because Windows'
# notification is no window Windows.Graphics.Capture can be given (Russell's
# ruling, 2026-10-04).
WINDOWS_PICTURE_OWED: dict = {}


class WindowsSwapTests(unittest.TestCase):

    def test_windows_false_shows_the_mac_picture_to_everybody(self):
        # `preview` has -windows files on disk; with `windows: false` they are
        # not offered, because the alt text and caption describe the Mac one.
        shot = {"id": "preview", "alt": "a", "caption": "c", "windows": False}
        self.assertNotIn("data-win-src", build.picture_element(shot, [], "", "./"))
        shot["windows"] = True
        self.assertIn("data-win-src", build.picture_element(shot, [], "", "./"))

    def test_windows_false_covers_a_static_figure_too(self):
        # #375: colour-schemes and light-and-dark are one image each; their
        # Windows versions carried drawn corners, so Windows visitors are
        # shown the Mac figure until Windows retakes them with real ones.
        # A -windows file on disk is still not offered.
        import shutil
        real = build.IMAGE_DIR / "colour-schemes.png"
        with tempfile.TemporaryDirectory() as scratch:
            folder = Path(scratch)
            shutil.copy(real, folder / "colour-schemes.png")
            shutil.copy(real, folder / "colour-schemes-windows.png")
            saved = build.IMAGE_DIR
            build.IMAGE_DIR = folder
            try:
                shot = {"id": "colour-schemes", "alt": "a", "caption": "c", "static": True, "windows": False}
                self.assertNotIn("data-win", build.picture_element(shot, [], "", "./"))
                del shot["windows"]
                self.assertIn("data-win-src", build.picture_element(shot, [], "", "./"))
            finally:
                build.IMAGE_DIR = saved

    def test_every_shot_has_its_windows_picture(self):
        # Russell, 2026-10-04: "Every screenshot must be windows." No id may
        # show a Windows visitor the Mac picture, so every one is marked
        # `windows: true` and its files are there (#380, #370).
        manifest = json.loads((build.WEBSITE / "shots.json").read_text(encoding="utf-8"))
        for shot in manifest["shots"]:
            if shot["id"] in WINDOWS_PICTURE_OWED:
                # Still owed, by name, and only while it is still false.
                self.assertIs(shot.get("windows"), False, shot["id"] + " has its picture now: take it off WINDOWS_PICTURE_OWED")
                continue
            with self.subTest(shot=shot["id"]):
                self.assertIs(shot.get("windows"), True)
                html = build.picture_element(shot, [], "", "./")
                self.assertIn("data-win-src", html)

    def test_a_windows_alt_is_swapped_only_with_a_windows_picture(self):
        # `windowsAlt`: words for the Windows picture where the shared alt
        # names something only the Mac picture shows. The Mac's alt is
        # untouched; base.html swaps data-win-alt as it swaps the image.
        shot = {"id": "preview", "alt": "the mac words", "caption": "c", "windowsAlt": "the windows words"}
        html = build.picture_element(shot, [], "", "./")
        self.assertIn('alt="the mac words"', html)
        self.assertIn('data-win-alt="the windows words"', html)
        shot["windows"] = False
        self.assertNotIn("data-win-alt", build.picture_element(shot, [], "", "./"))
        layout = (build.WEBSITE / "layout" / "base.html").read_text(encoding="utf-8")
        self.assertIn("data-win-alt", layout)


class DarkStaticFigureTests(unittest.TestCase):
    """A static figure marked `dark: true` gives a dark page its Dark Mode
    file, keeps `<id>.png` as the light one, and is a PROBLEM when the dark
    file is missing (colour-schemes, Russell 2026-10-04)."""

    def test_the_real_manifest_marks_colour_schemes_dark_and_its_files_exist(self):
        manifest = json.loads((build.WEBSITE / "shots.json").read_text(encoding="utf-8"))
        shot = [entry for entry in manifest["shots"] if entry["id"] == "colour-schemes"][0]
        self.assertTrue(shot.get("static"))
        self.assertTrue(shot.get("dark"))
        problems: list = []
        html = build.picture_element(shot, problems, "", "./")
        self.assertEqual(problems, [])
        self.assertIn('srcset="./img/colour-schemes-dark.webp"', html)
        self.assertIn('media="(prefers-color-scheme: dark)"', html)
        self.assertIn('src="./img/colour-schemes.png"', html)

    def test_a_missing_dark_file_is_a_problem(self):
        import shutil
        real = build.IMAGE_DIR / "colour-schemes.png"
        with tempfile.TemporaryDirectory() as scratch:
            folder = Path(scratch)
            shutil.copy(real, folder / "colour-schemes.png")
            shutil.copy(real.with_suffix(".webp"), folder / "colour-schemes.webp")
            saved = build.IMAGE_DIR
            build.IMAGE_DIR = folder
            try:
                problems: list = []
                shot = {"id": "colour-schemes", "alt": "a", "caption": "c", "static": True, "dark": True}
                html = build.picture_element(shot, problems, "", "./")
                self.assertEqual(len(problems), 1, problems)
                self.assertIn("colour-schemes-dark.png", problems[0])
                self.assertNotIn("prefers-color-scheme", html)
            finally:
                build.IMAGE_DIR = saved


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
