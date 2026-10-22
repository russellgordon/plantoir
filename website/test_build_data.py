#!/usr/bin/env python3
"""
Unit tests for what build.py reads from data rather than from the pages.

The counts a page quotes, the Mac-only notes and the download cards all
come from `support/` and `site.json`, and two
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

    def test_what_runs_the_code_is_never_named(self):
        # #562: the Code page says what students get, never what runs it.
        for sentence in ("Python runs on Pyodide.", "Swift is compiled to WebAssembly.",
                         "A wasm file per block.", "It runs in a worker.", "Two web workers."):
            with self.subTest(sentence=sentence):
                self.assertEqual(len(build.machinery_problems("x.html", f"<p>{sentence}</p>")), 1)


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

    def test_the_cards_are_pinned_exactly_where_the_newest_release_lacks_an_installer(self):
        # Windows was pinned to 1.1.0 from v1.2.0 until PlantoirSetup.exe
        # joined v1.4.2 (2026-10-03), and to 1.4.2 for the mac-first v1.4.3
        # cut (2026-10-04) until its installer joined v1.4.3 (2026-10-07), and
        # to 1.4.3 for the mac-first v1.4.4 cut until it joined v1.4.4 (2026-10-08).
        # The Mac card was pinned to 1.4.4 from the Windows-only v1.4.5 cut
        # (2026-10-08) until Plantoir-macOS.dmg joined v1.4.5 the same day.
        # Windows is pinned to 1.4.5 for the mac-only v1.5.0, v1.6.0 and
        # v1.7.0 cuts (2026-10-09), and v1.7.1 (2026-10-11), until PlantoirSetup.exe joins a release
        # again. A release that lacks an installer pins that card, and this
        # test changes with it (the downloads_note in site.json says when).
        site = build.read_json(build.WEBSITE / "site.json")
        pins: dict = {}
        for entry in site["downloads"]:
            pins[entry["platform"]] = entry.get("pinned")
        self.assertIsNone(pins["macOS"])
        # PlantoirSetup.exe joined v1.7.2 on 2026-10-16; the mac-only v1.8.0
        # cut (2026-10-17), the mac-only v1.8.1 cut (2026-10-18), the mac-only
        # v1.8.2 cut (2026-10-19) and the mac-only v1.8.3 cut (2026-10-19) pin
        # Windows to 1.7.2 until its 1.8 installer joins a release, and that
        # cut unpins it again.
        # PlantoirSetup.exe joined v1.8.5 on 2026-10-22 (the Windows catch-up),
        # which unpinned it again.
        self.assertIsNone(pins["Windows"])


class ShortcutTests(unittest.TestCase):

    def test_math_lands_on_the_diagrams_and_graphs_section(self):
        # #486 promised /math; it lands on a section of the Visualizations
        # page (called Interactive until DECISIONS 41 renamed it).
        site = build.read_json(build.WEBSITE / "site.json")
        destinations = {}
        for shortcut in build.shortcuts(site):
            destinations[shortcut["from"]] = shortcut["to"]
        self.assertEqual(destinations.get("math"), "visualizations/#diagrams-and-graphs")
        page = build.shortcut_page(site, destinations["math"])
        self.assertIn('url=../visualizations/#diagrams-and-graphs"', page)

    def test_a_shortcut_to_a_missing_section_or_page_is_a_problem(self):
        site = {"shortcuts": {"to": [{"from": "math", "to": "interactive/#nowhere"},
                                     {"from": "x", "to": "missing/"},
                                     {"from": "features", "to": "interactive/"}]}}
        rendered = {"interactive": '<section id="here"></section>', "features": ""}
        problems = build.shortcut_problems(site, ["interactive", "features"], rendered)
        self.assertEqual(len(problems), 3, problems)

    def test_no_element_is_called_math_on_a_page_with_a_graph(self):
        # function-plot reads window.math, which an element with id="math"
        # becomes: every graph on the page then fails (measured 2026-10-09).
        for name in ("visualizations.html", "printing.html"):
            page = (build.WEBSITE / "pages" / name).read_text(encoding="utf-8")
            self.assertNotIn('id="math"', page, name)


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

    def test_the_real_site_moves_interactive_to_visualizations(self):
        # DECISIONS 41: the header reads in nouns. /interactive/ answers 301
        # with /visualizations/, printing has a page of its own, and the old
        # #printing section is kept on Visualizations as the sentence that
        # points at /printing/, so an old link still lands somewhere useful.
        site = json.loads((build.WEBSITE / "site.json").read_text(encoding="utf-8"))
        self.assertIn({"from": "interactive", "to": "visualizations"}, build.moved_pages(site))
        self.assertEqual(site["nav"], ["index", "features", "visualizations", "printing", "quizzes", "code",
                                       "day-to-day", "deploying", "support"])
        self.assertFalse((build.WEBSITE / "pages" / "interactive.html").exists())
        visualizations = (build.WEBSITE / "pages" / "visualizations.html").read_text(encoding="utf-8")
        self.assertIn('id="printing"', visualizations)
        self.assertIn('href="{{up}}printing/"', visualizations)
        self.assertNotIn("{{shot:print-", visualizations)
        printing = (build.WEBSITE / "pages" / "printing.html").read_text(encoding="utf-8")
        self.assertIn("{{shot:print-page}}", printing)
        self.assertIn("{{shot:print-handout}}", printing)

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

    def test_a_missing_awaited_picture_is_not_deployed(self):
        site = {"version": "1.4.0"}
        shots = {"shots": [{"id": "no-such-shot-anywhere", "awaiting_capture": True}]}
        self.assertIn("no-such-shot-anywhere", build.release_readiness_refusal(site, shots))

    def test_a_missing_picture_waiting_on_a_named_issue_is_deployed(self):
        site = {"version": "1.4.0"}
        shots = {"shots": [{"id": "no-such-shot-anywhere", "awaiting_capture": True, "waiting_on": "#367"}]}
        self.assertIsNone(build.release_readiness_refusal(site, shots))

    def test_waiting_on_must_name_an_issue(self):
        site = {"version": "1.4.0"}
        shots = {"shots": [{"id": "no-such-shot-anywhere", "awaiting_capture": True, "waiting_on": "later"}]}
        self.assertIn("no-such-shot-anywhere", build.release_readiness_refusal(site, shots))

    def test_a_ready_release_deploys(self):
        site = {"version": "1.4.1"}
        self.assertIsNone(build.release_readiness_refusal(site, {"shots": []}))


# A Windows picture that cannot be taken yet, each with what blocks it. Every
# other id must be `windows: true` (Russell, 2026-10-04). Empty again since
# 2026-10-15: v1.7.0's two print pictures (`print-page`, `print-handout`),
# mac only at first, were taken on Windows by `capture_windows.py
# --print-set` on the first unlocked desktop after the 1.7.1 catch-up.
WINDOWS_PICTURE_OWED: dict = {
    # The Code page (#562) and the Quizzes page (#587). Since #590,
    # capture_windows.py --code / --quizzes takes every one of these but the
    # two Swift figures, from native previews of ~/School Web Space and
    # ~/Teaching (preview_pages_windows.py) -- at exactly 2x only (#557), so
    # they are taken in a 4K session at 200%. A shot leaves this list in the
    # commit that marks it `windows: true` (`capture_windows.py --promote`
    # checks the pictures first), which is the release commit whose installer
    # has the feature. The reasons below are what each one still waits on.
    # code-swift and code-swift-live stay owed: Swift stays read-only on
    # Windows until #570 is decided (v1.9.0).
    "code-swift-live": "Swift stays read-only on Windows until #570 is decided (v1.9.0)",
    "code-swift": "Swift stays read-only on Windows until #570 is decided (v1.9.0)",
    "quiz-math": "too tall for the 1280 x 860 window at 2x: quiz-math.js refuses it (767 pt) (#590)",
    "quiz-code-run": "too tall for the 1280 x 860 window at 2x: quiz-code-run.js refuses it (744 pt) (#590)",
}


class CodePagePictureTests(unittest.TestCase):

    def test_every_picture_on_the_code_page_is_there_in_both_appearances(self):
        # #562: each figure on /code/ is a page of a class site after Run or
        # Check, photographed in light AND dark (capture.py --code). A shot
        # with one appearance missing would show a dark-mode visitor the
        # other one, or nothing.
        import re
        page = (build.WEBSITE / "pages" / "code.html").read_text(encoding="utf-8")
        identifiers = re.findall(r"\{\{shot:([a-z0-9-]+)\}\}", page)
        self.assertEqual(identifiers, ["code-python", "code-python-live", "code-python-error", "code-swift-live", "code-swift", "code-quiz"])
        manifest = json.loads((build.WEBSITE / "shots.json").read_text(encoding="utf-8"))
        shots = {shot["id"]: shot for shot in manifest["shots"]}
        for identifier in identifiers:
            with self.subTest(shot=identifier):
                self.assertEqual(shots[identifier]["capture"]["scene"], "code")
                self.assertNotIn("awaiting_capture", shots[identifier])
                for suffix in ("light", "dark"):
                    for extension in ("png", "webp"):
                        picture = build.IMAGE_DIR / f"{identifier}-{suffix}.{extension}"
                        self.assertTrue(picture.is_file(), f"{picture.name} is missing")


class QuizzesPagePictureTests(unittest.TestCase):

    def test_every_picture_on_the_quizzes_page_is_there_in_both_appearances(self):
        # #587: one figure per subject, each a planted quiz page just checked,
        # photographed in light AND dark (capture.py --quizzes), and the Code
        # page's code-quiz again for code highlighted in a question's stem.
        import re
        page = (build.WEBSITE / "pages" / "quizzes.html").read_text(encoding="utf-8")
        identifiers = re.findall(r"\{\{shot:([a-z0-9-]+)\}\}", page)
        self.assertEqual(identifiers, ["quiz-math", "quiz-chemistry", "quiz-english", "code-quiz", "quiz-code-run"])
        manifest = json.loads((build.WEBSITE / "shots.json").read_text(encoding="utf-8"))
        shots = {shot["id"]: shot for shot in manifest["shots"]}
        for identifier in identifiers:
            with self.subTest(shot=identifier):
                expected_scene = "code" if identifier == "code-quiz" else "quizzes"
                self.assertEqual(shots[identifier]["capture"]["scene"], expected_scene)
                self.assertNotIn("awaiting_capture", shots[identifier])
                for suffix in ("light", "dark"):
                    for extension in ("png", "webp"):
                        picture = build.IMAGE_DIR / f"{identifier}-{suffix}.{extension}"
                        self.assertTrue(picture.is_file(), f"{picture.name} is missing")


class FrontPageQuizTests(unittest.TestCase):

    def test_the_front_page_shows_a_quiz_and_links_the_quizzes_page(self):
        index = (build.WEBSITE / "pages" / "index.html").read_text(encoding="utf-8")
        self.assertIn("{{shot:quiz-chemistry}}", index)
        self.assertIn('href="{{up}}quizzes/"', index)

    def test_how_to_write_a_quiz_is_the_quizzes_page(self):
        features = (build.WEBSITE / "pages" / "features.html").read_text(encoding="utf-8")
        self.assertIn('href="{{up}}quizzes/"', features)
        self.assertIn('href="{{up}}quizzes/"', (build.WEBSITE / "pages" / "code.html").read_text(encoding="utf-8"))
        self.assertIn('href="{{up}}quizzes/"', (build.WEBSITE / "pages" / "visualizations.html").read_text(encoding="utf-8"))
        for page in sorted((build.WEBSITE / "pages").glob("*.html")):
            with self.subTest(page=page.name):
                self.assertNotIn("code/#quizzes", page.read_text(encoding="utf-8"))


class PreviewPageSceneTests(unittest.TestCase):
    """A `preview-page` shot is a page of ONE local preview, named by its
    scene. The print set (both platforms) previews MPM2D only, so it must
    take only its own: given the Code page's ICS3U and ICS4U pages it asked
    MPM2D's preview for them, which answers 404, and webwindow refuses a 404
    — the whole print-set run stopped (#562's plan review, S12)."""

    def manifest_shots(self) -> list:
        return json.loads((build.WEBSITE / "shots.json").read_text(encoding="utf-8"))["shots"]

    def test_every_preview_shot_names_a_scene_that_takes_it(self):
        for shot in self.manifest_shots():
            if shot["capture"].get("kind") in ("preview-page", "handout"):
                with self.subTest(shot=shot["id"]):
                    self.assertIn(shot["capture"].get("scene"), ("print-set", "code", "quizzes"))

    def test_the_windows_print_set_takes_only_its_own(self):
        sys.path.insert(0, str(build.WEBSITE / "shots"))
        import print_set_windows
        self.assertEqual([shot["id"] for shot in print_set_windows.shots_of_kind("preview-page")], ["print-page"])
        self.assertEqual([shot["id"] for shot in print_set_windows.shots_of_kind("handout")], ["print-handout"])

    def test_the_windows_code_and_quiz_passes_take_only_their_own(self):
        # #590: capture_windows.py --code / --quizzes (preview_pages_windows.py)
        # take each scene's own pages and not the Swift two, which stay
        # read-only on Windows until #570 is decided (v1.9.0). Plain Python,
        # so it runs on either machine.
        sys.path.insert(0, str(build.WEBSITE / "shots"))
        import preview_pages_windows
        self.assertEqual([shot["id"] for shot in preview_pages_windows.preview_page_shots("code")],
                         ["code-python", "code-python-live", "code-python-error", "code-quiz"])
        self.assertEqual([shot["id"] for shot in preview_pages_windows.preview_page_shots("quizzes")],
                         ["quiz-math", "quiz-chemistry", "quiz-english", "quiz-code-run"])
        self.assertEqual(preview_pages_windows.preview_page_shots("code", ["code-swift"]), [])
        # The two left out are real shots, so leaving them out is a decision
        # rather than a stale name.
        identifiers = [shot["id"] for shot in self.manifest_shots()]
        # Each figure's page, named as the planting steps name it, so the
        # changed-page guard can match their report: a page planted from
        # CODE_PAGES or folders.json, or one of the ready-made course's.
        import demo_folders
        import marketing_folder
        known = set()
        for code, place, _ in marketing_folder.CODE_PAGES:
            known.add(f"{code}/{place}")
        for page in demo_folders.planted_pages():
            known.add(f"{page['course']}/{page['place']}")
        for scene in ("code", "quizzes"):
            for shot in preview_pages_windows.preview_page_shots(scene):
                capture = shot["capture"]
                label = preview_pages_windows.page_label(capture)
                with self.subTest(shot=shot["id"], label=label):
                    place = label.split("/", 1)[1]
                    shared = build.REPO / "support" / "example_content" / capture["course"] / "shared" / place
                    self.assertTrue(label in known or shared.is_file(), label)
        self.assertEqual(preview_pages_windows.page_label({"course": "ICS3U", "path": "/Warm-Ups/Spot-the-Bug"}),
                         "ICS3U/Warm-Ups/Spot the Bug.md")
        for excluded in preview_pages_windows.NOT_ON_WINDOWS:
            with self.subTest(excluded=excluded):
                self.assertIn(excluded, identifiers)
        for shot in preview_pages_windows.preview_page_shots("code") + preview_pages_windows.preview_page_shots("quizzes"):
            with self.subTest(shot=shot["id"]):
                self.assertTrue((build.WEBSITE / "shots" / "prepare" / shot["capture"]["prepare"]).exists())
                self.assertIn(shot["capture"]["workspace"], ("marketing", "demo"))

    @unittest.skipUnless(sys.platform == "darwin", "capture.py is the Mac's")
    def test_the_mac_print_set_and_code_set_take_only_their_own(self):
        sys.path.insert(0, str(build.WEBSITE / "shots"))
        import capture
        self.assertEqual([shot["id"] for shot in capture.shots_of_kind("preview-page", scene="print-set")], ["print-page"])
        self.assertEqual([shot["id"] for shot in capture.shots_of_kind("preview-page", scene="code")],
                         ["code-python", "code-python-live", "code-python-error", "code-swift-live", "code-swift", "code-quiz"])
        for shot in capture.shots_of_kind("preview-page", scene="code"):
            with self.subTest(shot=shot["id"]):
                self.assertTrue((capture.PREPARE_DIR / shot["capture"]["prepare"]).is_file())

    @unittest.skipUnless(sys.platform == "darwin", "capture.py is the Mac's")
    def test_the_quiz_set_takes_one_figure_per_subject_from_its_folder(self):
        sys.path.insert(0, str(build.WEBSITE / "shots"))
        import capture
        shots = capture.shots_of_kind("preview-page", scene="quizzes")
        found: list = []
        for shot in shots:
            found.append((shot["id"], shot["capture"]["workspace"], shot["capture"]["course"]))
            with self.subTest(shot=shot["id"]):
                self.assertTrue((capture.PREPARE_DIR / shot["capture"]["prepare"]).is_file())
                self.assertIs(shot.get("windows"), False)
        self.assertEqual(found, [("quiz-math", "demo", "MCV4U"), ("quiz-chemistry", "demo", "SCH3U"),
                                 ("quiz-english", "demo", "ENG2D"), ("quiz-code-run", "marketing", "ICS3U")])


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


class WindowsPrintDensityTests(unittest.TestCase):

    def test_the_windows_print_pictures_are_twice_their_window(self):
        # #544: the Windows print pictures stand beside the mac's 2x ones in
        # the same <picture>, so they are taken at 2x of the very windows the
        # harness opens -- in a 3840 x 2034 session at 200% (2026-10-16) --
        # and served unscaled (`images.prepare`). At the 1080-pixel console's
        # fitted scale they were 736 x 962 and 1427 x 961, and looked soft.
        import sys
        from PIL import Image
        sys.path.insert(0, str(build.WEBSITE / "shots"))
        from print_set_windows import HANDOUT_SIZE_DIP, PAGE_SIZE_DIP
        with Image.open(build.IMAGE_DIR / "print-handout-windows.png") as handout:
            self.assertEqual(handout.size, (2 * HANDOUT_SIZE_DIP[0], 2 * HANDOUT_SIZE_DIP[1]))
        for theme in ("light", "dark"):
            with Image.open(build.IMAGE_DIR / f"print-page-windows-{theme}.png") as page:
                self.assertEqual(page.size, (2 * PAGE_SIZE_DIP[0], 2 * PAGE_SIZE_DIP[1]), theme)


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
