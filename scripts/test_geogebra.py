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
import io
import json
import shutil
import tempfile
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


class Space:
    """A site's content folder, its output folder, and a vendor folder with
    (or without) GeoGebra's engine."""

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

    def file(self, relative: str, data: bytes):
        path = self.content.joinpath(*relative.split("/"))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def page(self, relative: str, text: str, source=None):
        self.file(relative, text.encode("utf-8"))
        return {"place": relative[:-3], "text": text, "source": source, "path": relative}

    def prepare(self, pages):
        return geogebra.prepare(pages, self.output, self.content, vendor_dir=self.vendor,
                                printer=self.said.append)

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


class PassTests(unittest.TestCase):

    def setUp(self):
        self.space = Space()

    def tearDown(self):
        self.space.close()

    def manifest(self):
        path = self.space.output / "quartz" / geogebra.WORKSPACE / "manifest.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def test_a_file_sketch_is_published_once_with_its_thumbnail(self):
        self.space.file("Unit 1/Lines.ggb", a_sketch(700, 400))
        page = self.space.page("Unit 1/Lesson.md", "```geogebra\nfile: Lines.ggb\nalt: Two lines.\n```\n")
        outcome = self.space.prepare([page])
        self.assertEqual(outcome["counts"]["geogebra"], 1)
        entry = list(self.manifest()["sketches"].values())[0]
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

    def test_the_fence_size_wins_and_commands_alone_have_a_size(self):
        self.space.file("Lines.ggb", a_sketch(700, 400))
        pages = [self.space.page("A.md", "```geogebra\nfile: Lines.ggb\nwidth: 500\nheight: 300\n```\n"),
                 self.space.page("B.md", "```geogebra\nf(x) = x^2\n```\n")]
        self.space.prepare(pages)
        sizes = sorted((entry["width"], entry["height"], entry["source"] is None)
                       for entry in self.manifest()["sketches"].values())
        self.assertEqual(sizes, [(500, 300, False), (800, 500, True)])

    def test_the_size_on_the_button_counts_the_engine_too(self):
        self.space.prepare([self.space.page("B.md", "```geogebra\nf(x) = x^2\n```\n")])
        entry = list(self.manifest()["sketches"].values())[0]
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
        self.assertEqual(list(self.manifest()["sketches"].values())[0]["alt"],
                         rules("words", "site", "untitledSketch"))

    def test_without_the_engine_nothing_is_shown(self):
        space = Space(engine=False)
        try:
            outcome = space.prepare([space.page("A.md", "```geogebra\nf(x) = x\n```\n")])
            self.assertEqual(outcome["counts"]["geogebra"], 0)
            self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["engineMissing"])
        finally:
            space.close()

    def test_a_geogebra_org_sketch_is_not_fetched_yet(self):
        outcome = self.space.prepare([self.space.page("A.md", "```geogebra\nmaterial_id: ju3f2kbg\n```\n")])
        self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["materialCouldNotBeFetched"])
        outcome = self.space.prepare([self.space.page("A.md", "```geogebra\nmaterial_id: a sketch\n```\n")])
        self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["materialNotUnderstood"])

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

    def test_the_manifest_carries_the_words_and_the_attribution(self):
        self.space.prepare([self.space.page("A.md", "```geogebra\nf(x) = x\n```\n")])
        manifest = self.manifest()
        self.assertEqual(manifest["words"], rules("words", "site"))
        self.assertEqual(manifest["attribution"]["engineUrl"], "https://www.geogebra.org")


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
