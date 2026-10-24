#!/usr/bin/env python3
"""
GeoGebra sketches from a page's fences (#578): the build's half, against the
CONTRACT.

The cases are not retyped here. They are deserialised from
`contracts/shared-rules.json` -> `geogebraFences` (fences, settings,
materialIds, files, keys, siteCarriesEngine, words) and `siteHealth.checks`
(geogebraSketchesNotReady).

Stdlib only, so Windows' PythonToolchainTests runs it too. What the SITE does
with the manifest is checked in the image (scripts/
check_geogebra_rules_against_the_site.py: every key case through the site's
own Markdown reader) and in a browser (browser-checks/geogebra_applet.mjs),
both from verify.sh.

Run with:

    python3 scripts/test_geogebra.py
"""
import http.server
import io
import json
import os
import shutil
import socket
import tempfile
import threading
import time
import unittest
import zipfile
from pathlib import Path

import contracts
import figures
import geogebra
import page_features
import site_health
import toolchain_paths


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def rules(*keys):
    return contracts.section("shared-rules", "geogebraFences", *keys)


# A 1x1 PNG, for a sketch's thumbnail.
PNG = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x02\x00\x00\x00\x01\x08\x06\x00\x00\x00"
       b"\xf4\"\x7f\x8a\x00\x00\x00\x0bIDATx\x9cc\xf8\x0f\x00\x01\x01\x01\x00\x18\xdd\x8d\xb0"
       b"\x00\x00\x00\x00IEND\xaeB`\x82")


def a_sketch(width=640, height=360, app="classic", thumbnail=True) -> bytes:
    xml = (f'<?xml version="1.0" encoding="utf-8"?>\n<geogebra format="5.0" app="{app}">\n'
           f'<gui><window width="900" height="700" /></gui>\n'
           f'<euclidianView>\n<size  width="{width}" height="{height}"/>\n</euclidianView>\n'
           f'<construction></construction>\n</geogebra>\n')
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as sketch:
        sketch.writestr("geogebra.xml", xml)
        if thumbnail:
            sketch.writestr("geogebra_thumbnail.png", PNG)
    return buffer.getvalue()


def no_xml() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as sketch:
        sketch.writestr("something.txt", "not a sketch")
    return buffer.getvalue()


def a_closed_port() -> int:
    """A local port nothing listens on."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def an_offline_fetcher():
    """A fetcher whose geogebra.org is a local port nothing answers on: what
    a build without the network meets. Every test uses one of these or the
    stub's - never the real API."""
    port = a_closed_port()
    return geogebra.MaterialFetcher(api=f"http://127.0.0.1:{port}/v1.0/materials/{{id}}",
                                    hosts=["127.0.0.1"], schemes=["http"], timeout=2)


class StubGeoGebra:
    """
    geogebra.org's two answers, served by a local server of our own
    (geogebraFences.fetch): the materials API and the .ggb. It counts every
    request it is sent, so "asked nothing" is measured where the asking
    would arrive. Sketches: `stubsketch` (one applet), `twoapplets`,
    `textonly`, `notaggb1` (its .ggb is not a GeoGebra file), `gone1234`
    (404), `brokenapi` (500), `awayaway` (its .ggb redirects off the hosts).
    """

    def __init__(self):
        stub = self
        self.requests = []
        self.sketch = a_sketch(1430, 759)

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *arguments):
                pass

            def do_GET(self):
                stub.requests.append(self.path)
                path = self.path.split("?")[0]
                base = f"http://127.0.0.1:{stub.port}"
                if path.startswith("/v1.0/materials/"):
                    material = path.rsplit("/", 1)[1]
                    if material == "gone1234":
                        return self.answer(404, b'{"error": "not found"}')
                    if material == "brokenapi":
                        return self.answer(500, b"oops")
                    applet = {"type": "G", "url": f"{base}/resource/{material}.ggb"}
                    elements = {"twoapplets": [applet, dict(applet)],
                                "textonly": [{"type": "T", "url": ""}]}.get(material, [applet])
                    body = {"id": material, "title": "Slope Angle Conjecture", "visibility": "S",
                            "deleted": False, "creator": {"displayname": "Russell Gordon"},
                            "elements": elements}
                    return self.answer(200, json.dumps(body).encode("utf-8"), "application/json")
                if path == "/resource/notaggb1.ggb":
                    return self.answer(200, b"<html>not a sketch</html>")
                if path == "/resource/awayaway.ggb":
                    self.send_response(302)
                    self.send_header("Location", "http://localhost:1/elsewhere.ggb")
                    self.end_headers()
                    return None
                if path.startswith("/resource/"):
                    return self.answer(200, stub.sketch, "application/vnd.geogebra.file")
                return self.answer(404, b"")

            def answer(self, code, body, kind="text/plain"):
                self.send_response(code)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def fetcher(self):
        return geogebra.MaterialFetcher(api=f"http://127.0.0.1:{self.port}/v1.0/materials/{{id}}?scope=extended",
                                        hosts=["127.0.0.1"], schemes=["http"], timeout=5)

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class Space:
    """A site's content folder, its output folder, a vendor folder with
    (or without) GeoGebra's engine, and the course's saved copies of
    geogebra.org sketches (outside the content, as beside built sites)."""

    def __init__(self, engine=True):
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-geogebra-test-"))
        self.content = self.root / "content"
        self.output = self.root / "section"
        self.vendor = self.root / "vendor"
        self.content.mkdir()
        (self.output / "quartz" / "static").mkdir(parents=True)
        if engine:
            (self.vendor / "geogebra").mkdir(parents=True)
            (self.vendor / "geogebra" / "deployggb.js").write_text("// GeoGebra\n", encoding="utf-8")
        self.said = []
        self.cache = self.root / "builds" / "COURSE" / geogebra.CACHE_FOLDER
        self.fetcher = an_offline_fetcher()

    def file(self, relative: str, data: bytes):
        path = self.content.joinpath(*relative.split("/"))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def page(self, relative: str, text: str, source=None):
        self.file(relative, text.encode("utf-8"))
        return {"place": relative[:-3], "text": text, "source": source, "path": relative}

    def prepare(self, pages, fetcher=None, full_rebuild=False):
        return geogebra.prepare(pages, self.output, self.content, vendor_dir=self.vendor,
                                printer=self.said.append, cache_root=self.cache,
                                fetcher=fetcher or self.fetcher, full_rebuild=full_rebuild)

    def scan(self):
        return geogebra.pages_students_see(self.content, lambda text: "publish: false" in text,
                                           lambda page: page.relative_to(self.content).as_posix()[:-3],
                                           lambda page: None)

    def tree(self) -> dict:
        found = {}
        for path in sorted(self.content.rglob("*")):
            if path.is_file():
                found[path.relative_to(self.content).as_posix()] = path.read_bytes()
        return found

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


class ContractCaseTests(unittest.TestCase):

    def test_every_fences_case(self):
        cases = rules("fences", "cases")
        self.assertGreaterEqual(len(cases), 6)
        for case in cases:
            found = [{"block": sketch["block"], "line": sketch["line"]}
                     for sketch in geogebra.sketches_on_page(case["page"])]
            self.assertEqual(found, case["found"], case["name"])

    def test_every_settings_case(self):
        cases = rules("settings", "cases")
        self.assertGreaterEqual(len(cases), 16)
        for case in cases:
            read = geogebra.read_fence(case["body"])
            self.assertEqual(read["settings"], case["settings"], case["name"])
            self.assertEqual(read["commands"], case["commands"], case["name"])
            self.assertEqual(read["problems"], case["problems"], case["name"])
            self.assertEqual(read["notes"], case["notes"], case["name"])

    def test_every_material_id_case(self):
        cases = rules("materialIds", "cases")
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            self.assertEqual(geogebra.material_id_of(case["value"]), case["id"], case["value"])

    def test_every_files_case(self):
        cases = rules("files", "cases")
        self.assertGreaterEqual(len(cases), 12)
        largest = rules("files", "largestFileMegabytes") * 1024 * 1024
        for case in cases:
            space = Space()
            try:
                for entry in case["files"]:
                    name, _, kind = entry.partition(":")
                    data = {"": a_sketch(), "notAZip": b"not a zip at all", "noXml": no_xml()}[kind]
                    space.file(name, data)
                written = [path for path in space.content.rglob("*") if path.is_file()]
                if len(written) < len(case["files"]):
                    # Two names that differ only in capitals are ONE file on
                    # a Mac's or a PC's disk; the case runs where the disk
                    # keeps both (the image, Netlify's own).
                    continue
                found = geogebra.find_file(case["value"], case["page"], space.content)
                reason = "fileNotFound" if found is None else None
                if found is not None:
                    read = geogebra.read_sketch(space.content / found, largest)
                    if not read["ok"]:
                        reason = read["reason"]
                        found = None
                self.assertEqual(found, case["found"], case["name"])
                self.assertEqual(reason, case["reason"], case["name"])
            finally:
                space.close()

    def test_a_file_larger_than_the_limit_is_refused(self):
        space = Space()
        try:
            space.file("Unit 1/Big.ggb", a_sketch())
            read = geogebra.read_sketch(space.content / "Unit 1" / "Big.ggb", 100)
            self.assertEqual(read["reason"], "fileTooLarge")
        finally:
            space.close()

    def test_every_key_case(self):
        cases = rules("keys", "cases")
        self.assertGreaterEqual(len(cases), 8)
        top = None
        for case in cases:
            found = geogebra.sketches_on_page(case["page"])
            self.assertEqual(len(found), 1, case["name"])
            self.assertEqual(found[0]["key"], case["key"], case["name"])
            self.assertEqual(found[0]["key"], figures.key_of(found[0]["body"]), case["name"])
            if top is None:
                top = case["key"]
            elif "the same key" in case["name"]:
                self.assertEqual(case["key"], top, case["name"])
            else:
                self.assertNotEqual(case["key"], top, case["name"])

    def test_every_site_carries_engine_case(self):
        cases = rules("siteCarriesEngine", "cases")
        self.assertGreaterEqual(len(cases), 5)
        for case in cases:
            space = Space()
            try:
                for index, entry in enumerate(case["pages"]):
                    space.page(f"Page {index}.md", entry["text"])
                outcome = space.prepare(space.scan())
                self.assertEqual(outcome["counts"]["geogebra"], case["geogebra"], case["name"])
                page_features.install_gated_assets(space.output, outcome["counts"], vendor_dir=space.vendor,
                                                   printer=space.said.append)
                carried = (space.output / "quartz" / "static" / "geogebra").is_dir()
                self.assertEqual(carried, case["geogebra"] > 0, case["name"])
                self.assertEqual((space.output / "quartz" / geogebra.WORKSPACE).is_dir(), case["geogebra"] > 0,
                                 case["name"])
            finally:
                space.close()

    def test_every_finding_case(self):
        check = None
        for item in contracts.section("shared-rules", "siteHealth", "checks"):
            if item["name"] == "geogebraSketchesNotReady":
                check = item
        self.assertIsNotNone(check)
        self.assertIn("geogebraSketchesNotReady", contracts.section(
            "shared-rules", "siteHealth", "repair", "neverOffered", "checks"))
        for case in check["cases"]:
            found = [item for item in site_health.findings({"geogebra_problems": case["sketches"],
                                                            "media_target_exists": True,
                                                            "section_index_exists": True},
                                                           case["course"], case["section"])
                     if item.name == "geogebraSketchesNotReady"]
            self.assertEqual(len(found), 1, case["name"])
            self.assertEqual(found[0].sentence, case["sentence"], case["name"])
            self.assertEqual(found[0].detail, case["detail"], case["name"])


    def test_every_manifest_case(self):
        # Stage 2 review item 1: by page AND fence, so each page shows its
        # own file and the folder problem names the page that cannot.
        cases = rules("manifest", "cases")
        self.assertGreaterEqual(len(cases), 1)
        for case in cases:
            space = Space()
            try:
                for entry in case["files"]:
                    name, _, kind = entry.partition(":")
                    space.file(name, a_sketch(width=600 if kind == "one" else 700))
                pages = [space.page(path, text) for path, text in sorted(case["pages"].items())]
                outcome = space.prepare(pages)
                manifest = json.loads((space.output / "quartz" / geogebra.WORKSPACE / "manifest.json")
                                      .read_text(encoding="utf-8"))
                shown = {}
                for page, sketches in manifest["pages"].items():
                    for entry in sketches.values():
                        shown[page] = entry["source"]["contentPath"]
                self.assertEqual(shown, case["shown"], case["name"])
                self.assertEqual([{"page": problem["page"], "reason": problem["reason"]}
                                  for problem in outcome["problems"]], case["problems"], case["name"])
            finally:
                space.close()


class PassTests(unittest.TestCase):

    def setUp(self):
        self.space = Space()

    def tearDown(self):
        self.space.close()

    def manifest(self):
        path = self.space.output / "quartz" / geogebra.WORKSPACE / "manifest.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def entries(self) -> list:
        """Every entry in the manifest, page by page."""
        found = []
        for page in sorted(self.manifest()["pages"]):
            for key in sorted(self.manifest()["pages"][page]):
                found.append(self.manifest()["pages"][page][key])
        return found

    def test_a_file_sketch_is_published_once_with_its_thumbnail(self):
        self.space.file("Unit 1/Lines.ggb", a_sketch(700, 400))
        page = self.space.page("Unit 1/Lesson.md", "```geogebra\nfile: Lines.ggb\nalt: Two lines.\n```\n")
        outcome = self.space.prepare([page])
        self.assertEqual(outcome["counts"]["geogebra"], 1)
        entry = self.entries()[0]
        self.assertEqual(entry["source"], {"kind": "file", "contentPath": "Unit 1/Lines.ggb"})
        self.assertEqual((entry["width"], entry["height"]), (700, 400))
        self.assertEqual(entry["alt"], "Two lines.")
        self.assertEqual(entry["attribution"], {"kind": "file"})
        # Nothing of the sketch is copied: Quartz publishes the one in content/.
        written = [path for path in self.space.output.rglob("*") if path.is_file()]
        self.assertFalse([path for path in written if path.suffix.lower() == ".ggb"])
        pictures = list((self.space.output / "quartz" / "static" / geogebra.THUMBNAILS).iterdir())
        self.assertEqual([path.read_bytes() for path in pictures], [PNG])
        self.assertEqual(entry["thumbnail"]["width"], 2)

    def test_one_file_on_several_fences_is_one_picture(self):
        self.space.file("Lines.ggb", a_sketch())
        pages = [self.space.page("A.md", "```geogebra\nfile: Lines.ggb\nalt: One.\n```\n"),
                 self.space.page("B.md", "```geogebra\nfile: Lines.ggb\nalt: Two.\n```\n")]
        self.space.prepare(pages)
        self.assertEqual(len(self.entries()), 2)
        pictures = list((self.space.output / "quartz" / "static" / geogebra.THUMBNAILS).iterdir())
        self.assertEqual(len(pictures), 1)

    def test_the_fence_size_wins_and_commands_alone_have_a_size(self):
        self.space.file("Lines.ggb", a_sketch(700, 400))
        pages = [self.space.page("A.md", "```geogebra\nfile: Lines.ggb\nwidth: 500\nheight: 300\n```\n"),
                 self.space.page("B.md", "```geogebra\nf(x) = x^2\n```\n")]
        self.space.prepare(pages)
        sizes = sorted((entry["width"], entry["height"], entry["source"] is None)
                       for entry in self.entries())
        self.assertEqual(sizes, [(500, 300, False), (800, 500, True)])

    def test_the_size_on_the_button_counts_the_engine_too(self):
        self.space.prepare([self.space.page("B.md", "```geogebra\nf(x) = x^2\n```\n")])
        entry = self.entries()[0]
        megabytes = rules("engine", "firstLoadBytes", "gzipped") / 1_000_000
        self.assertEqual(entry["size"], f"about {round(megabytes, 1)} MB")

    def test_a_tilde_fence_is_found_by_the_page_scan(self):
        # Must-fail for plan review finding 9: one scan for ```geogebra
        # alone never reads this page.
        self.space.page("Only Tildes.md", "~~~geogebra\nf(x) = x\n~~~\n")
        self.space.page("Only Backticks.md", "```geogebra\nf(x) = x\n```\n")
        self.space.page("Hidden.md", "---\npublish: false\n---\n~~~geogebra\nf(x) = x\n~~~\n")
        paths = [page["path"] for page in self.space.scan()]
        self.assertEqual(paths, ["Only Backticks.md", "Only Tildes.md"])

    def test_a_sketch_that_cannot_be_shown_is_said_with_its_line(self):
        text = "Intro.\n\n```geogebra\nalt: Lines.\nfile: Nowhere.ggb\n```\n"
        outcome = self.space.prepare([self.space.page("Unit 1/Lesson.md", text, source=text)])
        self.assertEqual(outcome["counts"]["geogebra"], 0)
        self.assertEqual(len(outcome["problems"]), 1)
        problem = outcome["problems"][0]
        self.assertEqual((problem["reason"], problem["line"], problem["file"]), ("fileNotFound", 5, "Nowhere.ggb"))
        self.assertIn("plantoir: error: Unit 1/Lesson.md: geogebra block 1, line 5: Nowhere.ggb isn't beside the page",
                      "\n".join(self.space.said))
        self.assertFalse((self.space.output / "quartz" / geogebra.WORKSPACE).exists())

    def test_a_sketch_without_alt_is_a_note_not_a_problem(self):
        outcome = self.space.prepare([self.space.page("A.md", "```geogebra\nf(x) = x\n```\n")])
        self.assertEqual(outcome["problems"], [])
        self.assertEqual([note["reason"] for note in outcome["notes"]], ["missingAlt"])
        self.assertEqual(self.entries()[0]["alt"],
                         rules("words", "site", "untitledSketch"))

    def test_without_the_engine_nothing_is_shown(self):
        space = Space(engine=False)
        try:
            outcome = space.prepare([space.page("A.md", "```geogebra\nf(x) = x\n```\n")])
            self.assertEqual(outcome["counts"]["geogebra"], 0)
            self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["engineMissing"])
        finally:
            space.close()

    def test_a_geogebra_org_address_that_is_not_one(self):
        outcome = self.space.prepare([self.space.page("A.md", "```geogebra\nmaterial_id: a sketch\n```\n")])
        self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["materialNotUnderstood"])
        self.assertEqual(self.space.fetcher.requests, 0)

    def test_the_teachers_files_are_never_written(self):
        self.space.file("Media/Lines.ggb", a_sketch())
        pages = [self.space.page("Unit 2/Copied.md", "```geogebra\nfile: Old/Lines.ggb\n```\n"),
                 self.space.page("Unit 2/Bad.md", "```geogebra\nfile: Gone.ggb\n```\n")]
        before = self.space.tree()
        self.space.prepare(pages)
        self.space.prepare(pages)
        self.assertEqual(self.space.tree(), before)

    def test_with_no_sketch_left_the_site_files_go(self):
        self.space.file("Lines.ggb", a_sketch())
        self.space.prepare([self.space.page("A.md", "```geogebra\nfile: Lines.ggb\n```\n")])
        self.assertTrue((self.space.output / "quartz" / "static" / geogebra.THUMBNAILS).is_dir())
        self.space.prepare([])
        self.assertFalse((self.space.output / "quartz" / geogebra.WORKSPACE).exists())
        self.assertFalse((self.space.output / "quartz" / "static" / geogebra.THUMBNAILS).exists())

    def test_the_manifest_carries_the_line_marker(self):
        # Stage 3: the loader runs geogebraFences.commands.endOfLine after
        # each line, and reads the dialogs before it as the line's.
        self.space.prepare([self.space.page("A.md", "```geogebra\nf(x) = x\n```\n")])
        self.assertEqual(self.manifest()["endOfLine"], rules("commands", "endOfLine"))
        self.assertIn("{line}", rules("words", "site", "lineCouldNotRun"))
        self.assertIn("{said}", rules("words", "site", "lineCouldNotRun"))
        cases = rules("commands", "cases")
        self.assertGreaterEqual(len([case for case in cases if case["said"] is None]), 5)
        self.assertGreaterEqual(len([case for case in cases if case["said"]]), 3)
        marker = rules("commands", "endOfLine").split("(")[0]
        for case in cases:
            self.assertNotIn(marker, case["text"])
            if case["said"]:
                self.assertNotIn(marker, case["said"])

    def test_the_manifest_carries_the_words_and_the_attribution(self):
        self.space.prepare([self.space.page("A.md", "```geogebra\nf(x) = x\n```\n")])
        manifest = self.manifest()
        self.assertEqual(manifest["words"], rules("words", "site"))
        self.assertEqual(manifest["attribution"]["engineUrl"], "https://www.geogebra.org")


class MaterialTests(unittest.TestCase):
    """A geogebra.org sketch, fetched ONCE and kept by the fence (stage 4),
    against a local stub of geogebra.org - never the real API."""

    FENCE = "```geogebra\nmaterial_id: https://www.geogebra.org/m/stubsketch\nalt: Three triangles.\n```\n"

    def setUp(self):
        self.space = Space()
        self.stub = StubGeoGebra()

    def tearDown(self):
        self.stub.close()
        self.space.close()

    def entries(self):
        manifest = json.loads((self.space.output / "quartz" / geogebra.WORKSPACE / "manifest.json")
                              .read_text(encoding="utf-8"))
        return [entry for page in manifest["pages"].values() for entry in page.values()]

    def key(self, fence=None):
        return geogebra.sketches_on_page(fence or self.FENCE)[0]["key"]

    def seed(self, fence=None):
        geogebra.SavedCopies(self.space.cache).put(self.key(fence), {
            "id": "stubsketch", "title": "Slope Angle Conjecture", "author": "Russell Gordon",
            "ggb": self.stub.sketch})

    def test_every_cache_case(self):
        cases = rules("cache", "cases")
        self.assertGreaterEqual(len(cases), 6)
        self.assertEqual(rules("cache", "folder"), geogebra.CACHE_FOLDER)
        self.assertEqual(rules("cache", "pruneDays"), figures.PRUNE_DAYS)
        for case in cases:
            space = Space()
            try:
                fence = self.FENCE
                if case["saved"]:
                    geogebra.SavedCopies(space.cache).put(geogebra.sketches_on_page(fence)[0]["key"], {
                        "id": "stubsketch", "title": "T", "author": "A", "ggb": self.stub.sketch})
                if case.get("fenceChanged"):
                    fence = fence.replace("alt: Three triangles.\n", "alt: Three triangles.\nversion: 2\n")
                fetcher = self.stub.fetcher() if case["online"] else an_offline_fetcher()
                before = len(self.stub.requests)
                outcome = None
                for _ in range(case["builds"]):
                    outcome = space.prepare([space.page("A.md", fence)], fetcher=fetcher,
                                            full_rebuild=case["fullRebuild"])
                self.assertEqual(fetcher.requests, case["requests"], case["name"])
                if case["online"]:
                    # Measured where the asking would arrive, not only counted.
                    self.assertEqual(len(self.stub.requests) - before, case["requests"], case["name"])
                self.assertEqual(outcome["counts"]["geogebra"] == 1, case["shown"], case["name"])
                self.assertEqual([problem["reason"] for problem in outcome["problems"]],
                                 [case["reason"]] if case["reason"] else [], case["name"])
            finally:
                space.close()

    def test_a_fetched_sketch_is_kept_under_the_fence_and_carried_once(self):
        outcome = self.space.prepare([self.space.page("A.md", self.FENCE)], fetcher=self.stub.fetcher())
        self.assertEqual((outcome["fetched"], outcome["fromBefore"]), (1, 0))
        key = self.key()
        self.assertTrue((self.space.cache / f"{key}.ggb").is_file())
        self.assertEqual(json.loads((self.space.cache / f"{key}.json").read_text(encoding="utf-8")),
                         {"id": "stubsketch", "title": "Slope Angle Conjecture", "author": "Russell Gordon"})
        entry = self.entries()[0]
        self.assertEqual(entry["source"], {"kind": "material",
                                           "storePath": f"static/{geogebra.THUMBNAILS}/{key[:16]}.ggb"})
        self.assertEqual(entry["attribution"], {"kind": "material", "author": "Russell Gordon",
                                                "id": "stubsketch", "title": "Slope Angle Conjecture"})
        self.assertEqual((entry["width"], entry["height"]), (1430, 759))
        site = self.space.output / "quartz" / "static" / geogebra.THUMBNAILS
        self.assertEqual((site / f"{key[:16]}.ggb").read_bytes(), self.stub.sketch)
        self.assertEqual(sorted(path.suffix for path in site.iterdir()), [".ggb", ".png"])
        self.assertIn("📐 Sketches from geogebra.org: 1 copied now, 0 kept from before.", self.space.said)
        # Only the two requests, to the API and for the .ggb.
        self.assertEqual([path.split("?")[0] for path in self.stub.requests],
                         ["/v1.0/materials/stubsketch", "/resource/stubsketch.ggb"])

    def test_one_fence_on_two_pages_is_fetched_once(self):
        fetcher = self.stub.fetcher()
        self.space.prepare([self.space.page("A.md", self.FENCE), self.space.page("B.md", self.FENCE)],
                           fetcher=fetcher)
        self.assertEqual(fetcher.requests, 2)
        self.assertEqual(len(self.entries()), 2)

    def test_keyed_by_the_fence_not_the_id(self):
        # Must-fail for "key on the material id": two fences naming the same
        # sketch are two saved copies, and changing one fetches it again.
        self.seed()
        other = self.FENCE.replace("alt: Three triangles.", "alt: Three triangles, again.")
        fetcher = self.stub.fetcher()
        self.space.prepare([self.space.page("A.md", self.FENCE), self.space.page("B.md", other)], fetcher=fetcher)
        self.assertEqual(fetcher.requests, 2)
        self.assertEqual(sorted(path.name for path in self.space.cache.iterdir()),
                         sorted([f"{self.key()}.ggb", f"{self.key()}.json",
                                 f"{self.key(other)}.ggb", f"{self.key(other)}.json"]))

    def test_what_geogebra_org_says_is_said(self):
        for material, reason in (("gone1234", "materialNotFound"), ("brokenapi", "materialCouldNotBeFetched"),
                                 ("twoapplets", "materialHasSeveralSketches"), ("textonly", "materialHasNoSketch"),
                                 ("notaggb1", "materialHasNoSketch"), ("awayaway", "materialCouldNotBeFetched")):
            space = Space()
            try:
                fence = f"```geogebra\nmaterial_id: {material}\n```\n"
                outcome = space.prepare([space.page("A.md", fence)], fetcher=self.stub.fetcher())
                self.assertEqual([(problem["reason"], problem["id"]) for problem in outcome["problems"]],
                                 [(reason, material)], material)
                # Nothing is kept from an answer that could not be shown.
                self.assertFalse(space.cache.exists() and any(space.cache.iterdir()), material)
            finally:
                space.close()

    def test_a_host_that_is_not_geogebra_orgs_is_never_asked(self):
        fetcher = geogebra.MaterialFetcher(api=f"http://127.0.0.1:{self.stub.port}/v1.0/materials/{{id}}",
                                           hosts=["api.geogebra.org"], schemes=["http"], timeout=2)
        self.assertEqual(fetcher.material("stubsketch")["reason"], "materialCouldNotBeFetched")
        self.assertEqual(self.stub.requests, [])
        https_only = geogebra.MaterialFetcher(api=f"http://127.0.0.1:{self.stub.port}/v1.0/materials/{{id}}",
                                              hosts=["127.0.0.1"], timeout=2)
        self.assertEqual(https_only.material("stubsketch")["reason"], "materialCouldNotBeFetched")
        self.assertEqual(self.stub.requests, [])
        # The contract's own: https, geogebra.org's hosts.
        real = geogebra.MaterialFetcher()
        self.assertEqual(real.schemes, ("https",))
        self.assertTrue(real.api.startswith("https://api.geogebra.org/"))

    def test_a_copy_unused_for_90_days_goes_and_one_in_use_stays(self):
        self.seed()
        old_fence = "```geogebra\nmaterial_id: stubsketch\nversion: old\n```\n"
        self.seed(old_fence)
        long_ago = time.time() - (figures.PRUNE_DAYS + 1) * 86400
        for path in self.space.cache.iterdir():
            os.utime(path, (long_ago, long_ago))
        fetcher = self.stub.fetcher()
        self.space.prepare([self.space.page("A.md", self.FENCE)], fetcher=fetcher)
        # The fence in use was pruned too (it had not been used in 90 days)
        # and fetched again; the old one is gone and stays gone.
        names = sorted(path.name for path in self.space.cache.iterdir())
        self.assertEqual(names, sorted([f"{self.key()}.ggb", f"{self.key()}.json"]))
        self.assertEqual(fetcher.requests, 2)
        # Used now, so the next build keeps it and asks nothing.
        again = self.stub.fetcher()
        self.space.prepare([self.space.page("A.md", self.FENCE)], fetcher=again)
        self.assertEqual(again.requests, 0)
        self.assertGreater((self.space.cache / f"{self.key()}.json").stat().st_mtime, long_ago + 86400)

    def test_the_teachers_files_are_never_written(self):
        page = self.space.page("A.md", self.FENCE)
        before = self.space.tree()
        self.space.prepare([page], fetcher=self.stub.fetcher())
        self.assertEqual(self.space.tree(), before)

    def test_without_the_engine_nothing_is_fetched(self):
        space = Space(engine=False)
        try:
            fetcher = self.stub.fetcher()
            outcome = space.prepare([space.page("A.md", self.FENCE)], fetcher=fetcher)
            self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["engineMissing"])
            self.assertEqual(fetcher.requests, 0)
        finally:
            space.close()


class WiringTests(unittest.TestCase):
    """The transformer stands straight after Figures and before Quizzes, on a
    fresh site and on one wired before #578 (plan section 3.4)."""

    CONFIG = "plugins: {\n  transformers: [\n    Plugin.Description(),\n    Plugin.Latex(),\n  ],\n}\n"

    def wire(self, text):
        import build_site
        folder = Path(tempfile.mkdtemp(prefix="plantoir-geogebra-wire-"))
        try:
            config = folder / "quartz.config.ts"
            config.write_text(text, encoding="utf-8")
            for step in (build_site._wire_figures_transformer, build_site._wire_quizzes_transformer,
                         build_site._wire_geogebra_transformer, build_site._wire_tasks_transformer):
                step(config)
            once = config.read_text(encoding="utf-8")
            build_site._wire_geogebra_transformer(config)
            self.assertEqual(config.read_text(encoding="utf-8"), once)
            return once
        finally:
            shutil.rmtree(folder, ignore_errors=True)

    def order(self, text):
        names = ["PlantoirFigures", "PlantoirGeoGebra", "PlantoirQuizzes", "PlantoirTasks"]
        return sorted(names, key=lambda name: text.index(f"Plugin.{name}()"))

    def test_a_fresh_site(self):
        self.assertEqual(self.order(self.wire(self.CONFIG)),
                         ["PlantoirFigures", "PlantoirGeoGebra", "PlantoirQuizzes", "PlantoirTasks"])

    def test_a_site_wired_before_578(self):
        old = self.CONFIG.replace("    Plugin.Description(),\n",
                                  "    Plugin.Description(),\n    Plugin.PlantoirFigures(),\n"
                                  "    Plugin.PlantoirQuizzes(),\n    Plugin.PlantoirTasks(),\n")
        self.assertEqual(self.order(self.wire(old)),
                         ["PlantoirFigures", "PlantoirGeoGebra", "PlantoirQuizzes", "PlantoirTasks"])


if __name__ == "__main__":
    use_the_repository_contract()
    unittest.main()
