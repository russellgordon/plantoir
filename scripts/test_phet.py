#!/usr/bin/env python3
"""
PhET simulations from a page's fences (#674), and the folder every download
a page needs is kept in (keptDownloads), against the CONTRACT.

The cases are not retyped here. They are deserialised from
`contracts/shared-rules.json` -> `phetFences` (fences, settings, simNames,
locale, address, stop, siteCarries) and `keptDownloads` (where, prune,
marker, stop), and `siteHealth.checks` (phetSimulationsNotReady).

PhET is never asked: a local server of the test's own plays it, answering
the metadata, a stub "simulation" (a small web page carrying the markers the
checks read, written here) and a picture, and counts what it was asked.
Stdlib only, so Windows' PythonToolchainTests runs it too. What the SITE does
with the manifest is checked in a browser (browser-checks/rendered_features.mjs,
the phet row, from verify.sh).

Run with:

    python3 scripts/test_phet.py
"""
import http.server
import json
import os
import shutil
import tempfile
import threading
import time
import unittest
from pathlib import Path

import contracts
import kept_downloads
import phet
import section_problems
import site_health
import toolchain_paths


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def rules(*keys):
    return contracts.section("shared-rules", "phetFences", *keys)


def kept_rules(*keys):
    return contracts.section("shared-rules", "keptDownloads", *keys)


PNG = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x02\x58\x00\x00\x01\x6a\x08\x06\x00\x00\x00"
       b"\x00\x00\x00\x00\x00\x00\x00\x00IEND\xaeB`\x82")


def a_simulation(extra: bytes = b"") -> bytes:
    """A stub of PhET's all-languages file: a web page holding what the
    checks read, and nothing of PhET's."""
    needed = "\n".join(rules("download", "checks", "mustContain")).encode("utf-8")
    return (b"<!DOCTYPE html>\n<html><head><title>Stub</title>\n" + needed
            + b"\n</head><body><script>var stub = 1;</script>\n" + extra + b"</body></html>\n")


ANALYTICS = (b'<script defer src="https://static.cloudflareinsights.com/beacon.min.js/v1" '
             b'data-cf-beacon=\'{"token":"x"}\'></script>\n')


class FakePhet:
    """A local server answering as phet.colorado.edu does, in one of the
    contract's moods: answers, down, cutOff, wrongFile, notFound,
    withAnalytics, oddAnswer."""

    def __init__(self, mood="answers", sims=("gas-properties",)):
        self.mood = mood
        self.sims = set(sims)
        self.asked = []
        fake = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                fake.asked.append(self.path)
                body, status, length = fake.answer(self.path)
                self.send_response(status)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(length if length is not None else len(body)))
                self.end_headers()
                try:
                    self.wfile.write(body)
                except OSError:
                    pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def answer(self, path):
        if "/services/metadata/" in path:
            wanted = path.split("simulation=")[-1] if "simulation=" in path else None
            if wanted is None:
                projects = [{"name": f"html/{sim}", "version": {"string": "1.0.0"},
                             "simulations": [{"name": sim, "localizedSimulations": {"en": {"title": sim}}}]}
                            for sim in sorted(self.sims | {"gas-properties", "projectile-motion"})]
                return json.dumps({"projects": projects}).encode(), 200, None
            if self.mood == "oddAnswer":
                # The shape the implementation review measured reaching the
                # pass's catch-all: `projects` holding a string.
                return json.dumps({"projects": ["html/" + wanted]}).encode(), 200, None
            if self.mood == "notFound" or wanted not in self.sims:
                return b'{"error": ["No sims found with the criteria provided"]}', 200, None
            return json.dumps({"projects": [{"name": f"html/{wanted}", "version": {"string": "1.1.12"},
                                             "simulations": [{"name": wanted, "localizedSimulations": {
                                                 "en": {"title": "Gas Properties"},
                                                 "fr": {"title": "Propriétés des gaz"}}}]}]}).encode(), 200, None
        if path.endswith("_all.html"):
            if self.mood == "wrongFile":
                return b"<!DOCTYPE html><html><body>Sign in to the school network</body></html>", 200, None
            if self.mood == "cutOff":
                body = a_simulation()
                return body, 200, len(body) + 500
            if self.mood == "withAnalytics":
                return a_simulation(ANALYTICS), 200, None
            return a_simulation(), 200, None
        if path.endswith("-600.png"):
            return PNG, 200, None
        return b"", 404, None

    def site(self):
        fetcher = kept_downloads.Fetcher(["127.0.0.1"], schemes=("http",), timeout=5)
        return phet.PhetSite(fetcher=fetcher, base=self.base)

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class DownServer:
    """Nothing listening: every request is refused, as with no internet."""

    def site(self):
        fetcher = kept_downloads.Fetcher(["127.0.0.1"], schemes=("http",), timeout=2)
        return phet.PhetSite(fetcher=fetcher, base="http://127.0.0.1:9")


def page(text, place="Unit 3/Gas Laws"):
    return {"place": place, "text": text, "source": text, "path": place + ".md"}


GAS = "Gases.\n\n```phet\nsim: gas-properties\nalt: Pump gas into a box.\nlocale: fr\nscreens: 1\n```\n"


class Scratch(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-phet-"))
        self.output = self.root / "section1"
        (self.output / "quartz" / "static").mkdir(parents=True)
        self.kept = self.root / "builds" / ".downloaded"
        self.servers = []

    def tearDown(self):
        for server in self.servers:
            server.close()
        shutil.rmtree(self.root, ignore_errors=True)

    def fake(self, mood="answers"):
        server = FakePhet(mood)
        self.servers.append(server)
        return server

    def prepare(self, pages, site, **more):
        lines = []
        outcome = phet.prepare(pages, self.output, self.kept, course_locale=more.pop("locale", "en-US"),
                               course="SCH3U", section=1, site=site, printer=lines.append, **more)
        return outcome, lines


# ---- phetFences.download: what counts as "no such simulation" ------------------------

class MetadataShapeTests(unittest.TestCase):
    """Only PhET's own answer for a misspelt name (an `error`, no projects)
    reads as no such simulation; an empty answer of any other shape is
    damaged, so the build stops rather than deploy a page without its
    simulation under a misspelling's Problems row."""

    def setUp(self):
        use_the_repository_contract()

    def metadata(self, answer: bytes):
        class Fetcher:
            def get(self, url):
                return answer
        return phet.PhetSite(fetcher=Fetcher(), base="http://127.0.0.1:1").metadata("gas-properties")

    def test_phets_own_answer_for_a_misspelt_name_is_no_such_simulation(self):
        self.assertIsNone(self.metadata(b'{"error": ["No sims found with the criteria provided"]}'))

    def test_an_empty_answer_is_damaged(self):
        for answer in (b"{}", b"null", b'{"projects": []}', b'{"projects": [{}]}', b"[]",
                       b'{"projects": [{"name": "html/other", "simulations": [{"name": "other"}]}]}'):
            with self.subTest(answer.decode()):
                with self.assertRaises(kept_downloads.DownloadFailed) as failed:
                    self.metadata(answer)
                self.assertEqual(failed.exception.reason, "damaged")


# ---- phetFences: reading ----------------------------------------------------------

class FenceTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()

    def test_every_fences_case(self):
        for case in rules("fences", "cases"):
            with self.subTest(case["name"]):
                found = [{"block": one["block"], "line": one["line"]} for one in phet.simulations_on_page(case["page"])]
                self.assertEqual(found, case["found"])

    def test_every_page_with_a_simulation_is_one_the_scan_keeps(self):
        # The build reads only the pages its scan keeps (pages_students_see's
        # must_contain), so a fence the reader finds and the scan skips is a
        # page that deploys without its simulation and says nothing: ``` phet.
        for case in rules("fences", "cases"):
            if not case["found"]:
                continue
            with self.subTest(case["name"]):
                with tempfile.TemporaryDirectory() as folder:
                    content = Path(folder)
                    (content / "Page.md").write_text(case["page"], encoding="utf-8")
                    kept = phet.pages_students_see(content, lambda text: False, lambda page: "Page",
                                                   lambda page: None)
                self.assertEqual([page["path"] for page in kept], ["Page.md"])

    def test_every_key_case(self):
        # The site's half of these cases is scripts/check_phet_rules_against_the_site.py (verify.sh).
        for case in rules("keys", "cases"):
            with self.subTest(case["name"]):
                found = phet.simulations_on_page(case["page"])
                self.assertEqual(len(found), 1)
                self.assertEqual(found[0]["key"], case["key"])

    def test_every_settings_case(self):
        for case in rules("settings", "cases"):
            with self.subTest(case["name"]):
                read = phet.read_fence(case["body"])
                self.assertEqual(read["settings"], case["settings"])
                self.assertEqual(read["problems"], case["problems"])
                self.assertEqual(read["notes"], case["notes"])

    def test_every_sim_name_case(self):
        for case in rules("simNames", "cases"):
            with self.subTest(case["value"]):
                self.assertEqual(phet.sim_name_of(case["value"]), case["sim"])

    def test_every_locale_case(self):
        for case in rules("locale", "cases"):
            with self.subTest(case["name"]):
                answer = phet.resolve_locale(case["fence"], case["course"], case["languages"])
                self.assertEqual(answer["locale"], case["locale"])
                self.assertEqual(answer["fellBack"], case["fellBack"])

    def test_every_address_case_starts_with_the_fixed_settings(self):
        fixed = "&".join(rules("address", "fixed"))
        self.assertEqual(fixed, "yotta=false&allowLinks=false")
        for case in rules("address", "cases"):
            with self.subTest(case["query"]):
                query = phet.address_query(case["locale"], case["screens"])
                self.assertEqual(query, case["query"])
                self.assertTrue(query.startswith(fixed + "&"))

    def test_a_pasted_phet_frame_is_found(self):
        text = '<iframe src="https://phet.colorado.edu/sims/html/gas-properties/latest/gas-properties_en.html" width="800"></iframe>'
        self.assertEqual(phet.pasted_frames_on_page(text), 1)
        self.assertEqual(phet.pasted_frames_on_page('<iframe src="https://www.youtube.com/embed/x"></iframe>'), 0)

    def test_every_reason_and_site_word_is_written(self):
        said = rules("words")
        for key in ("simulationNotNamed", "simulationNotUnderstood", "simulationNotFound", "simulationNotFoundNear",
                    "screensNotUnderstood", "localeNotUnderstood", "missingAlt", "unknownSetting",
                    "notInThisLanguage", "pastedPhetFrame"):
            self.assertIn(key, said["reasons"])
        for key in ("open", "size", "loading", "loadingFirstTime", "couldNotLoad", "untitled", "printNote"):
            self.assertIn(key, said["site"])
        # CLAUDE.md rule 1: nothing a teacher or student reads names the machinery.
        everything = json.dumps(said, ensure_ascii=False).lower()
        for word in ("cache", "metadata", "iframe", "docker", "container", "script"):
            self.assertNotIn(word, everything)


# ---- keptDownloads ------------------------------------------------------------------

class KeptDownloadsTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-kept-"))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_every_where_case(self):
        builds = self.root / "builds" / "abcd1234"
        course = self.root / "work" / "courses" / "SCH3U"
        course.mkdir(parents=True)
        (builds / "SCH3U").mkdir(parents=True)
        for case in kept_rules("where", "cases"):
            with self.subTest(case["name"]):
                link = course / ".merged_output"
                if link.is_symlink() or link.is_file():
                    link.unlink()
                elif link.is_dir():
                    shutil.rmtree(link)
                environ = {}
                if case["layout"] == "buildRoot":
                    environ["PLANTOIR_BUILD_ROOT"] = str(builds)
                elif case["layout"] == "link":
                    link.symlink_to(builds / "SCH3U", target_is_directory=True)
                else:
                    link.mkdir()
                expected = case["expect"].replace("{buildRoot}", str(builds)).replace(
                    "{builds}", str(builds.resolve())).replace("{course}", str(course))
                self.assertEqual(str(kept_downloads.root_for(course, environ=environ)), expected)

    def test_the_folder_is_the_one_the_contract_names(self):
        self.assertEqual(kept_downloads.FOLDER, kept_rules("where", "folder"))
        self.assertEqual(kept_downloads.MARKER, kept_rules("marker", "prefix"))
        self.assertEqual(kept_downloads.RECORD, kept_rules("entries", "record"))
        # The apps' sweep keeps the same folder (buildOutputLocation).
        sweep = contracts.section("shared-rules", "buildOutputLocation", "keptDownloadsSurviveTheSweep")
        self.assertEqual(sweep["folder"], kept_downloads.FOLDER)

    def test_an_entry_is_kept_checked_and_found_again(self):
        store = kept_downloads.Store(self.root, "phet")
        entry = store.put("gas-properties", "1.1.12", {"simulation.html": b"abc"}, about={"titles": {"en": "Gas"}})
        self.assertIsNotNone(entry)
        again = store.get("gas-properties")
        self.assertEqual(again["version"], "1.1.12")
        self.assertEqual(again["about"]["titles"]["en"], "Gas")
        # Changed since it was kept: thrown away, and not found.
        (again["folder"] / "simulation.html").write_bytes(b"abd")
        self.assertIsNone(store.get("gas-properties"))
        self.assertFalse((self.root / "phet" / "gas-properties" / "1.1.12").exists())

    def test_a_pinned_file_that_does_not_match_is_refused_before_it_is_kept(self):
        store = kept_downloads.Store(self.root, "sounds")
        with self.assertRaises(ValueError):
            store.put("flute", "1", {"a.mp3": b"x"}, expected={"a.mp3": "0" * 64})
        self.assertEqual(store.versions("flute"), [])
        good = kept_downloads.sha256_of(b"x")
        self.assertIsNotNone(store.put("flute", "1", {"a.mp3": b"x"}, expected={"a.mp3": good}))
        self.assertIsNotNone(store.get("flute", "1", expected={"a.mp3": good}))
        self.assertIsNone(store.get("flute", "1", expected={"a.mp3": "1" * 64}))

    def test_a_name_that_could_leave_the_folder_is_never_kept(self):
        store = kept_downloads.Store(self.root, "phet")
        self.assertIsNone(store.put("../outside", "1", {"x": b"y"}))
        self.assertIsNone(store.put("ok", "../1", {"x": b"y"}))
        self.assertFalse((self.root / "outside").exists())

    def test_the_second_of_two_builds_keeps_the_first_copy(self):
        store = kept_downloads.Store(self.root, "phet")
        first = store.put("ph-scale", "1.0", {"simulation.html": b"first"})
        second = store.put("ph-scale", "1.0", {"simulation.html": b"second"})
        self.assertEqual((second["folder"] / "simulation.html").read_bytes(), b"first")
        self.assertEqual(first["folder"], second["folder"])
        leftovers = [entry.name for entry in (self.root / "phet" / "ph-scale").iterdir() if entry.name.startswith(".")]
        self.assertEqual(leftovers, [])

    def test_a_version_folder_left_without_its_record_is_replaced(self):
        store = kept_downloads.Store(self.root, "phet")
        left = self.root / "phet" / "gas-properties" / "1.1.12"
        left.mkdir(parents=True)
        (left / "simulation.html").write_bytes(b"left half removed")
        entry = store.put("gas-properties", "1.1.12", {"simulation.html": b"the real one"})
        self.assertIsNotNone(entry)
        self.assertEqual((entry["folder"] / "simulation.html").read_bytes(), b"the real one")

    def test_a_half_written_entry_is_never_read(self):
        store = kept_downloads.Store(self.root, "phet")
        hidden = self.root / "phet" / "ph-scale" / ".1.0.99.99.tmp"
        hidden.mkdir(parents=True)
        (hidden / "simulation.html").write_bytes(b"half")
        self.assertIsNone(store.get("ph-scale"))
        self.assertEqual(store.versions("ph-scale"), [])

    def test_every_prune_case(self):
        self.assertEqual(kept_rules("prune", "days"), 90)
        for case in kept_rules("prune", "cases"):
            with self.subTest(case["name"]):
                store = kept_downloads.Store(self.root / case["name"].replace(" ", "-"), "phet")
                entry = store.put("ph-scale", "1.0", {"simulation.html": b"x"})
                then = time.time() - case["daysSinceUsed"] * 86400
                os.utime(entry["folder"] / "kept.json", (then, then))
                store.prune()
                self.assertEqual(store.get("ph-scale") is not None, case["kept"])

    def test_the_newest_version_kept_is_used(self):
        store = kept_downloads.Store(self.root, "phet")
        store.put("ph-scale", "1.2.9", {"simulation.html": b"old"})
        store.put("ph-scale", "1.10.0", {"simulation.html": b"new"})
        self.assertEqual(store.get("ph-scale")["version"], "1.10.0")

    def test_every_marker_case(self):
        for case in kept_rules("marker", "cases"):
            with self.subTest(case["line"]):
                line = kept_downloads.marker_line(case["kind"], case["course"], case["section"],
                                                  downloaded=case.get("downloaded"), failed=case.get("failed"))
                self.assertEqual(line, case["line"])

    def test_every_stop_case(self):
        for case in kept_rules("stop", "cases"):
            with self.subTest(case["name"]):
                lines = kept_downloads.stop_lines(case["kind"], case["course"], case["section"],
                                                  case["missing"], case["reason"])
                self.assertEqual(lines, case["lines"])
                self.assertIn(kept_rules("stop", "markerWords"), lines[0])
                self.assertIn(kept_rules("stop", "markerWordsAlso"), lines[0])
                # The first line, lifted, begins with the course code (FailureExplainer.liftedSentence).
                self.assertTrue(lines[0].startswith("❌ " + case["course"] + " "))

    def test_a_cut_off_body_and_a_redirect_elsewhere_are_offline(self):
        fake = FakePhet("cutOff")
        try:
            fetcher = kept_downloads.Fetcher(["127.0.0.1"], schemes=("http",), timeout=5)
            with self.assertRaises(kept_downloads.DownloadFailed) as raised:
                fetcher.get(fake.base + "/sims/html/gas-properties/1.1.12/gas-properties_all.html")
            self.assertEqual(raised.exception.reason, "offline")
            with self.assertRaises(kept_downloads.DownloadFailed) as raised:
                fetcher.get("https://example.com/x")
            self.assertEqual(raised.exception.reason, "offline")
            with self.assertRaises(kept_downloads.DownloadFailed) as raised:
                fetcher.get(fake.base + "/nothing-here")
            self.assertEqual(raised.exception.reason, "notFound")
        finally:
            fake.close()

    def test_the_fetcher_never_asks_for_html(self):
        # keptDownloads.asking.accept: an HTML Accept is what made PhET's
        # servers add an analytics script (measured 2026-11-13).
        self.assertEqual(kept_rules("asking", "accept"), "*/*")
        seen = {}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                seen["accept"] = self.headers.get("Accept")
                self.send_response(200)
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"ok")

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            fetcher = kept_downloads.Fetcher(["127.0.0.1"], schemes=("http",), timeout=5)
            self.assertEqual(fetcher.get(f"http://127.0.0.1:{server.server_address[1]}/x"), b"ok")
            self.assertEqual(seen["accept"], "*/*")
        finally:
            server.shutdown()
            server.server_close()


# ---- phetFences: the whole pass, against a PhET of the test's own -----------------

class PrepareTests(Scratch):
    def test_every_stop_case(self):
        for case in rules("stop", "cases"):
            with self.subTest(case["name"]):
                shutil.rmtree(self.kept, ignore_errors=True)
                shutil.rmtree(self.output / "quartz" / "static" / "phet", ignore_errors=True)
                shutil.rmtree(self.output / "quartz" / phet.WORKSPACE, ignore_errors=True)
                if case["kept"]:
                    answering = self.fake("answers")
                    first, _ = self.prepare([page(GAS)], answering.site())
                    self.assertIsNone(first["stop"])
                    shutil.rmtree(self.output / "quartz" / "static" / "phet", ignore_errors=True)
                    shutil.rmtree(self.output / "quartz" / phet.WORKSPACE, ignore_errors=True)
                if case["phet"] == "down":
                    server = DownServer()
                    site = server.site()
                else:
                    server = self.fake(case["phet"])
                    site = server.site()
                outcome, lines = self.prepare([page(GAS)], site)
                expect = case["expect"]
                self.assertEqual((outcome["stop"] or {}).get("reason"), expect["stop"])
                self.assertEqual(outcome["shown"], expect["shown"])
                self.assertEqual([problem["reason"] for problem in outcome["problems"]], expect["problems"])
                if "requests" in expect:
                    self.assertEqual(site.fetcher.requests, expect["requests"])
                kept = kept_downloads.Store(self.kept, "phet").get("gas-properties")
                if "kept" in expect:
                    self.assertEqual(kept is not None, expect["kept"])
                if expect.get("keptHasNo"):
                    data = (kept["folder"] / phet.SIMULATION_FILE).read_bytes()
                    self.assertNotIn(expect["keptHasNo"].encode(), data)
                    self.assertEqual(data, a_simulation())
                if expect["stop"]:
                    # Nothing written to the site when it stops.
                    self.assertFalse((self.output / "quartz" / "static" / "phet").exists())
                    self.assertFalse((self.output / "quartz" / phet.WORKSPACE).exists())

    def test_the_site_gets_the_simulation_its_picture_and_the_credit(self):
        outcome, lines = self.prepare([page(GAS)], self.fake().site())
        folder = self.output / "quartz" / "static" / "phet" / "gas-properties"
        self.assertEqual(sorted(entry.name for entry in folder.iterdir()), sorted(rules("siteCarries", "files")))
        self.assertEqual((folder / "index.html").read_bytes(), a_simulation())
        self.assertIn(rules("attribution", "sentence"), (folder / "ABOUT.txt").read_text(encoding="utf-8"))
        manifest = json.loads((self.output / "quartz" / phet.WORKSPACE / "manifest.json").read_text(encoding="utf-8"))
        entry = next(iter(manifest["pages"]["Unit 3/Gas Laws.md"].values()))
        self.assertEqual(entry["query"], "yotta=false&allowLinks=false&locale=fr&screens=1")
        self.assertEqual(entry["title"], "Propriétés des gaz")
        self.assertEqual(entry["folder"], "static/phet/gas-properties/")
        self.assertEqual(entry["picture"]["path"], "static/phet/gas-properties/screenshot.png")
        self.assertEqual(manifest["attribution"]["sentence"], rules("attribution", "sentence"))
        self.assertEqual(outcome["counts"], {"phet": 1})
        self.assertEqual(outcome["downloaded"], ["gas-properties"])
        self.assertIsNotNone(phet.downloaded_line(outcome, "SCH3U", 1))

    def test_a_simulation_no_page_shows_leaves_the_site(self):
        self.prepare([page(GAS)], self.fake().site())
        outcome, _ = self.prepare([page("No simulation here.")], self.fake().site())
        self.assertFalse((self.output / "quartz" / "static" / "phet").exists())
        self.assertFalse((self.output / "quartz" / phet.WORKSPACE).exists())
        self.assertEqual(outcome["counts"], {"phet": 0})

    def test_one_download_serves_two_pages_and_two_courses(self):
        server = self.fake()
        site = server.site()
        self.prepare([page(GAS), page(GAS, place="Unit 3/Review")], site)
        simulation_requests = [path for path in server.asked if path.endswith("_all.html")]
        self.assertEqual(len(simulation_requests), 1)
        # Another course's build in the same working folder asks nothing.
        other = self.fake()
        outcome, _ = self.prepare([page(GAS, place="Other")], other.site())
        self.assertEqual(other.asked, [])
        self.assertEqual(outcome["fromBefore"], ["gas-properties"])

    def test_a_course_in_french_gets_french_with_no_setting(self):
        text = "```phet\nsim: gas-properties\nalt: A box of gas.\n```\n"
        self.prepare([page(text)], self.fake().site(), locale="fr-CA")
        manifest = json.loads((self.output / "quartz" / phet.WORKSPACE / "manifest.json").read_text(encoding="utf-8"))
        entry = next(iter(manifest["pages"]["Unit 3/Gas Laws.md"].values()))
        self.assertEqual(entry["locale"], "fr")
        self.assertIn("locale=fr", entry["query"])

    def test_a_language_the_simulation_lacks_is_a_note_in_english(self):
        text = "```phet\nsim: gas-properties\nalt: A box of gas.\nlocale: de\n```\n"
        outcome, lines = self.prepare([page(text)], self.fake().site())
        self.assertEqual([note["reason"] for note in outcome["notes"]], ["notInThisLanguage"])
        self.assertTrue(any(line.startswith("plantoir: note: Unit 3/Gas Laws.md: phet block 1, line ") for line in lines))

    def test_the_list_of_names_is_asked_once_however_many_names_are_wrong(self):
        text = ("```phet\nsim: gas-propertys\nalt: A.\n```\n\n```phet\nsim: gas-propertiez\nalt: B.\n```\n"
                "\n```phet\nsim: gaz-properties\nalt: C.\n```\n")
        server = self.fake()
        outcome, _ = self.prepare([page(text)], server.site())
        self.assertEqual(len(outcome["problems"]), 3)
        whole_list = [path for path in server.asked if "/services/metadata/" in path and "simulation=" not in path]
        self.assertEqual(len(whole_list), 1)

    def test_a_name_phet_does_not_have_offers_the_closest(self):
        text = "```phet\nsim: gas-propertys\nalt: A box of gas.\n```\n"
        outcome, lines = self.prepare([page(text)], self.fake().site())
        self.assertEqual(outcome["problems"][0]["near"], "gas-properties")
        self.assertIn("(the closest it has: gas-properties)", lines[-1])
        self.assertTrue(lines[-1].startswith("plantoir: error: Unit 3/Gas Laws.md: phet block 1, line 2: "))

    def test_a_pasted_frame_is_a_note(self):
        text = '<iframe src="https://phet.colorado.edu/sims/html/ph-scale/latest/ph-scale_en.html"></iframe>\n'
        outcome, lines = self.prepare([page(text)], self.fake().site())
        self.assertEqual([note["reason"] for note in outcome["notes"]], ["pastedPhetFrame"])

    def test_the_stop_names_every_page_and_counts_each_simulation_once(self):
        two = [page(GAS), page(GAS, place="Unit 3/Review")]
        outcome, lines = self.prepare(two, DownServer().site())
        self.assertEqual(outcome["stop"]["reason"], "offline")
        printed = phet.stop_lines(outcome, "SCH3U", 1)
        self.assertIn("a science simulation", printed[0])
        self.assertEqual(printed[1].strip(), "“gas-properties” on “Unit 3/Gas Laws”")
        self.assertEqual(printed[2].strip(), "“gas-properties” on “Unit 3/Review”")
        self.assertEqual(printed[-1], kept_downloads.marker_line("phet", "SCH3U", 1, failed={"count": 1, "reason": "offline"}))


# ---- The build stops (build_site.py) ---------------------------------------------------

class BuildStopTests(Scratch):
    def test_the_build_stops_with_the_lines_and_the_marker_before_quartz_runs(self):
        import contextlib
        import io
        import inspect
        import build_site
        outcome, _ = self.prepare([page(GAS)], DownServer().site())
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed), self.assertRaises(SystemExit) as stopped:
            build_site._stop_for_phet(outcome, "SCH3U", 1)
        self.assertEqual(stopped.exception.code, 1)
        lines = [line for line in printed.getvalue().split("\n") if line.strip()]
        self.assertEqual(lines, phet.stop_lines(outcome, "SCH3U", 1))
        self.assertTrue(lines[0].startswith("❌ SCH3U Section 1 was not built: "))
        self.assertTrue(lines[-1].startswith(kept_downloads.MARKER))
        # The stop comes before anything is said about the site's health,
        # before Quartz's files are wired and before Quartz is run.
        source = inspect.getsource(build_site.build_section_site)
        stop_at = source.index("_stop_for_phet(phet_here")
        for later in ("site_health.announce_or_stay_quiet(", "wire_quartz_additions(output_dir)", '"bootstrap-cli.mjs"'):
            self.assertLess(stop_at, source.index(later), later)


class PassFailsTests(Scratch):
    """phetFences.stop.passFails: a fault in the pass itself never gives a
    build that reports success with its simulations missing."""

    def test_every_pass_fails_case(self):
        import contextlib
        import io
        import build_site
        for case in rules("stop", "passFails", "cases"):
            with self.subTest(case["name"]):
                content = self.root / "content" / case["name"].replace(" ", "-").replace(",", "")
                for relative, text in case["pages"].items():
                    (content / relative).parent.mkdir(parents=True, exist_ok=True)
                    (content / relative).write_text(text, encoding="utf-8")
                (self.output / "quartz" / "static" / "phet" / "left").mkdir(parents=True, exist_ok=True)
                real_prepare = phet.prepare
                real_pages = phet.pages_students_see

                def broken(*args, **kwargs):
                    raise OSError(28, "No space left on device")

                if case["fails"] == "prepare":
                    phet.prepare = broken
                else:
                    phet.pages_students_see = broken
                printed = io.StringIO()
                try:
                    with contextlib.redirect_stdout(printed):
                        outcome = build_site._prepare_phet(content, self.output, self.root / "course", {},
                                                           "SPH3U", 1)
                finally:
                    phet.prepare = real_prepare
                    phet.pages_students_see = real_pages
                expect = case["expect"]
                self.assertEqual((outcome.get("stop") or {}).get("reason"), expect["stop"])
                self.assertFalse((self.output / "quartz" / "static" / "phet").exists())
                said = printed.getvalue()
                self.assertIn("(No space left on device)", said)
                self.assertNotIn(str(self.root), said)
                if expect["stop"]:
                    self.assertEqual(phet.stop_lines(outcome, "SPH3U", 1), expect["lines"])
                    stopped = io.StringIO()
                    with contextlib.redirect_stdout(stopped), self.assertRaises(SystemExit) as exit_code:
                        build_site._stop_for_phet(outcome, "SPH3U", 1)
                    self.assertEqual(exit_code.exception.code, 1)

    def test_the_console_never_names_pythons_class_for_the_fault(self):
        import contextlib
        import io
        import build_site
        content = self.root / "content" / "class-name"
        content.mkdir(parents=True, exist_ok=True)
        (content / "Gases.md").write_text("```phet\nsim: gas-properties\n```\n", encoding="utf-8")
        real_prepare = phet.prepare
        for fault in (AttributeError("x"), RuntimeError("x"), KeyError("x"), TimeoutError(), OSError("x")):
            with self.subTest(type(fault).__name__):
                def broken(*args, **kwargs):
                    raise fault
                phet.prepare = broken
                printed = io.StringIO()
                try:
                    with contextlib.redirect_stdout(printed):
                        outcome = build_site._prepare_phet(content, self.output, self.root / "course", {},
                                                           "SPH3U", 1)
                finally:
                    phet.prepare = real_prepare
                self.assertEqual(outcome["stop"]["reason"], "notReady")
                self.assertEqual(printed.getvalue().strip(), "⚠️ Could not prepare the science simulations.")

    def test_when_nothing_can_be_told_the_build_stops_naming_nothing(self):
        def broken():
            raise RuntimeError("no pages")
        self.assertIsNone(phet.places_after_a_failed_pass(broken, self.root / "not-there" / "\0"))
        self.assertEqual(phet.places_after_a_failed_pass(broken, self.root / "empty"), [])


# ---- The folder problem --------------------------------------------------------------

class ProblemTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()

    def test_every_site_health_case(self):
        table = {entry["name"]: entry for entry in contracts.section("shared-rules", "siteHealth", "checks")}
        entry = table["phetSimulationsNotReady"]
        for case in entry["cases"]:
            with self.subTest(case["name"]):
                finding = site_health.phet_finding({"phet_problems": case["simulations"]}, case["course"],
                                                   case["section"], table)
                self.assertEqual(finding.sentence, case["sentence"])
                self.assertEqual(finding.detail, case["detail"])

    def test_the_kind_is_a_section_problem_kind(self):
        kinds = {entry["kind"]: entry for entry in contracts.section("shared-rules", "sectionProblems", "kinds")}
        self.assertEqual(kinds["phetSimulationsNotReady"]["facts"], "phet_problems")
        self.assertIn("phetSimulationsNotReady", section_problems._MAKERS)


if __name__ == "__main__":
    unittest.main()
