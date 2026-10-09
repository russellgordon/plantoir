#!/usr/bin/env python3
"""
Diagrams and graphs drawn from a page's fences (#485 E1): the build's half,
against the CONTRACT.

The cases are not retyped here. They are deserialised from
`contracts/shared-rules.json` -> `figureFences` (fences, tidy, cacheKey, alt,
siteCarriesEngine, cache, timing, words) and `siteHealth.checks`
(figuresCouldNotBeDrawn).

**Stdlib only, and no Node.** The drawing engine is a stand-in written here in
Python that speaks the helper's protocol (support/figures/plantoir-figures.mjs),
so the cache, the clock, the restart after a diagram that never finishes, the
gate and the words are all tested on any machine - Windows' PythonToolchainTests
discovers this file. What the REAL engine says (texErrors, the functionplot
parse and expression cases, the TypeScript key) is checked in the image by
`scripts/check_figure_rules_against_the_site.py` (verify.sh).

Run with:

    python3 scripts/test_figures.py
"""
import json
import os
import shutil
import sys
import tempfile
import textwrap
import threading
import time
import unittest
from pathlib import Path

import contracts
import figures
import page_features
import site_health
import toolchain_paths


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def rules(*keys):
    return contracts.section("shared-rules", "figureFences", *keys)


# The stand-in for the drawing engine. It speaks the helper's protocol and
# draws nothing: a body holding SLEEP never answers, FAIL fails as TeX would,
# FONTS:a,b names those faces in its drawing, and a graph using ln( is refused.
# Every start is counted in the file named by its first argument.
STAND_IN = textwrap.dedent('''
    import json, sys, time
    with open(sys.argv[1], "a") as starts:
        starts.write("started\\n")
    if len(sys.argv) > 2 and sys.argv[2] == "never-ready":
        time.sleep(60)
    def send(message):
        sys.stdout.write(json.dumps(message) + "\\n")
        sys.stdout.flush()
    send({"ready": True})
    for line in sys.stdin:
        message = json.loads(line)
        if message.get("load") == "tikz":
            if len(sys.argv) > 2 and sys.argv[2] == "no-tikz":
                send({"loaded": None, "said": "Cannot find module 'node-tikzjax'"})
            else:
                send({"loaded": "tikz", "ms": 1})
            continue
        body = message["body"]
        if "SLEEP" in body:
            time.sleep(60)
        if message["engine"] == "tikz":
            if "FAIL" in body:
                send({"id": message["id"], "ok": False, "reason": "undefinedCommand",
                      "texLine": 2, "name": "\\\\foo", "said": "Undefined control sequence."})
                continue
            faces = ["cmr10"]
            for word in body.split():
                if word.startswith("FONTS:"):
                    faces = word[len("FONTS:"):].split(",")
            texts = "".join('<text font-family="%s">x</text>' % face for face in faces)
            send({"id": message["id"], "ok": True,
                  "svg": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">' + texts + "</svg>"})
            continue
        lines = [line.strip() for line in body.split("\\n") if line.strip() and "---" not in line and ":" not in line]
        if "ln(" in body:
            send({"id": message["id"], "ok": False, "plot": {"lines": lines}, "alt": None, "unknown": [],
                  "problems": [{"reason": "unknownName", "blockLine": 1, "name": "ln"}]})
            continue
        send({"id": message["id"], "ok": True, "alt": None, "unknown": [],
              "plot": {"bounds": [-10, 10, -10, 10], "lines": lines,
                       "functions": [line.split("=")[1].strip() for line in lines]},
              "problems": []})
''')

DOC = "\\begin{document}\n\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\end{tikzpicture}\n\\end{document}"


class Workspace:
    """A section's output folder, a cache, a vendor folder with the BaKoMa
    faces and function-plot, and the stand-in engine."""

    def __init__(self, mode=None):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-figures-"))
        self.output = self.folder / "builds" / "ICS3U" / "section1"
        (self.output / "quartz" / "static").mkdir(parents=True)
        self.cache = self.folder / "builds" / "ICS3U" / figures.CACHE_FOLDER
        self.vendor = self.folder / "vendor"
        bakoma = self.vendor / figures.TIKZ_ENGINE / "node_modules" / "node-tikzjax" / "css" / "bakoma"
        (bakoma / "ttf").mkdir(parents=True)
        for face in ("cmr10", "cmmi10", "cmsy10", "cmr7"):
            (bakoma / "ttf" / f"{face}.ttf").write_bytes(b"TTF " + face.encode())
        (bakoma / "LICENCE").write_text("BaKoMa Fonts Licence\n", encoding="utf-8")
        (self.vendor / figures.GRAPH_ENGINE).mkdir(parents=True)
        (self.vendor / figures.GRAPH_ENGINE / "function-plot.js").write_text("/* graphs */\n", encoding="utf-8")
        (self.vendor / figures.GRAPH_ENGINE / "LICENSE").write_text("MIT\n", encoding="utf-8")
        self.support = Path(__file__).resolve().parent.parent / "support"
        self.stand_in = self.folder / "stand_in.py"
        self.stand_in.write_text(STAND_IN, encoding="utf-8")
        self.starts = self.folder / "starts.txt"
        self.command = [sys.executable, str(self.stand_in), str(self.starts)] + ([mode] if mode else [])
        self.said = []

    def started(self) -> int:
        if not self.starts.is_file():
            return 0
        return self.starts.read_text().count("started")

    def prepare(self, pages, full_rebuild=False, job_seconds=figures.JOB_SECONDS, start_seconds=10):
        return figures.prepare(pages, self.output, self.cache, full_rebuild=full_rebuild,
                               command=self.command, vendor_dir=self.vendor, support_dir=self.support,
                               printer=self.said.append, job_seconds=job_seconds,
                               start_seconds=start_seconds)

    def manifest(self):
        path = self.output / "quartz" / figures.WORKSPACE / "manifest.json"
        if not path.is_file():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def close(self):
        shutil.rmtree(self.folder, ignore_errors=True)


def page(text, place="Unit 1/Page", source=None):
    return {"place": place, "text": text, "source": source}


class FenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def test_every_fence_case(self):
        cases = rules("fences", "cases")
        self.assertGreaterEqual(len(cases), 10, "the contract lost fence cases")
        for case in cases:
            found = []
            for figure in figures.figures_on_page(case["page"]):
                found.append({"engine": figure["engine"], "block": figure["block"], "line": figure["line"]})
            self.assertEqual(found, case["found"], case["name"])

    def test_every_tidy_case(self):
        cases = rules("tidy", "cases")
        self.assertGreaterEqual(len(cases), 8)
        for case in cases:
            self.assertEqual(figures.tidy(case["body"]), case["tidy"], repr(case["body"]))

    def test_the_cache_key(self):
        for case in rules("cacheKey", "cases"):
            self.assertEqual(figures.key_of(case["body"]), case["key"])

    def test_every_tikz_alt_case(self):
        cases = [case for case in rules("alt", "cases") if case["engine"] == "tikz"]
        self.assertGreaterEqual(len(cases), 5)
        for case in cases:
            self.assertEqual(figures.tikz_alt(case["body"]), case["alt"], repr(case["body"]))

    def test_the_generated_description(self):
        said = rules("words", "site")
        case = [case for case in rules("alt", "cases")
                if case["engine"] == "functionplot" and case["alt"].startswith("Graph of")][0]
        plot = {"lines": ["y = 2x + 1", "y = -x + 4"], "bounds": [-5, 5, -5, 5]}
        self.assertEqual(figures.describe_plot(plot, said), case["alt"])

    def test_a_line_in_the_teachers_file_survives_a_rewritten_front_matter(self):
        # The build's copy has its settings rewritten (three lines become
        # five); the line named must be the one in the teacher's own file.
        source = "---\ntitle: T\n---\nIntro.\n\n```tikz\n\\begin{document}\n\n\\foo\n\\end{document}\n```\n"
        built = "---\ntitle: T\ncreated: 2026-10-09\nmodified: 2026-10-09\n---\nIntro.\n\n```tikz\n" \
                "\\begin{document}\n\n\\foo\n\\end{document}\n```\n"
        figure = figures.figures_on_page(built)[0]
        figure["place"] = "Unit 1/Page"
        figure["fileLine"] = figures._file_line_of(figure, figures.figures_on_page(source))
        located = figures._located(figure, {"reason": "undefinedCommand", "texLine": 2, "name": "\\foo"})
        self.assertEqual(located["blockLine"], 3)
        self.assertEqual(located["line"], 9, "line 9 of the teacher's page holds \\foo")


class PrepareTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.space = Workspace()

    def tearDown(self):
        self.space.close()

    def test_every_site_carries_engine_case(self):
        cases = rules("siteCarriesEngine", "cases")
        self.assertGreaterEqual(len(cases), 5)
        for case in cases:
            space = Workspace()
            try:
                pages = []
                for index, entry in enumerate(case["pages"]):
                    text = entry["text"]
                    if case["drawnFonts"]:
                        text = text.replace("\\begin{document}", "\\begin{document}\nFONTS:" + ",".join(case["drawnFonts"]))
                    if entry["visible"]:
                        pages.append(page(text, place=f"Page {index}"))
                outcome = space.prepare(pages)
                page_features.install_gated_assets(space.output, outcome["counts"], vendor_dir=space.vendor,
                                                   printer=space.said.append)
                static = space.output / "quartz" / "static"
                self.assertEqual((static / "function-plot").is_dir(), case["functionPlot"], case["name"])
                self.assertEqual(outcome["fonts"], case["fonts"], case["name"])
                if case["fonts"]:
                    self.assertEqual(sorted(path.name for path in (static / "tikz").iterdir()), case["files"], case["name"])
                else:
                    self.assertFalse((static / "tikz").exists(), case["name"])
            finally:
                space.close()

    def test_a_site_without_figures_starts_nothing_and_writes_nothing(self):
        before = sorted(str(path) for path in self.space.output.rglob("*"))
        outcome = self.space.prepare([page("No figures here.\n\n```python\nprint(1)\n```\n")])
        after = sorted(str(path) for path in self.space.output.rglob("*"))
        self.assertEqual(before, after)
        self.assertEqual(self.space.started(), 0)
        self.assertEqual(outcome["figures"], 0)
        self.assertEqual(self.space.said, [])

    def test_a_second_build_draws_nothing_and_never_starts_the_engine(self):
        pages = [page("```tikz\n" + DOC + "\n```\n\n```functionplot\ny = x\n```\n")]
        first = self.space.prepare(pages)
        self.assertEqual(first["drawn"], 1)
        self.assertEqual(self.space.started(), 1)
        second = self.space.prepare(pages)
        self.assertEqual(second["drawn"], 0)
        self.assertEqual(second["fromBefore"], 2)
        self.assertEqual(self.space.started(), 1, "everything was cached, so nothing was started")
        self.assertTrue(any("Drew 0 diagrams (2 from before)" in line for line in self.space.said), self.space.said)

    def test_the_manifest_carries_the_drawing_the_words_and_the_graph(self):
        tikz_body = "% alt: A line\n" + DOC
        self.space.prepare([page("```tikz\n" + tikz_body + "\n```\n\n```functionplot\ny = x\n```\n")])
        manifest = self.space.manifest()
        key = figures.key_of(tikz_body)
        entry = manifest["figures"]["tikz"][key]
        self.assertEqual(entry["alt"], "A line")
        self.assertTrue((self.space.output / "quartz" / figures.WORKSPACE / entry["svg"]).is_file())
        self.assertEqual(manifest["words"], rules("words", "site"))
        graph = manifest["figures"]["functionplot"][figures.key_of("y = x")]
        self.assertTrue(graph["ok"])
        self.assertEqual(graph["alt"], "Graph of y = x, for x from -10 to 10.")

    def test_a_failed_diagram_is_located_in_the_teachers_file_and_reported(self):
        source = "---\ntitle: Similar\n---\n\n```tikz\n\\begin{document}\n\n\\foo FAIL\n\\end{document}\n```\n"
        outcome = self.space.prepare([page(source, place="Units/Similar Triangles", source=source)])
        self.assertEqual(len(outcome["problems"]), 1)
        problem = outcome["problems"][0]
        self.assertEqual((problem["engine"], problem["block"], problem["reason"]), ("tikz", 1, "undefinedCommand"))
        self.assertEqual(problem["line"], 8, "the stand-in names tidied line 2, which is the page's line 8")
        said = [line for line in self.space.said if line.startswith("plantoir: error:")]
        self.assertEqual(said, ["plantoir: error: Units/Similar Triangles.md: tikz block 1, line 8: "
                                "\\foo isn't a command LaTeX knows here"])
        self.assertFalse(self.space.manifest()["figures"]["tikz"][figures.key_of(
            "\\begin{document}\n\n\\foo FAIL\n\\end{document}")]["ok"])

    def test_a_diagram_without_alt_is_a_note_and_never_a_problem(self):
        outcome = self.space.prepare([page("```tikz\n" + DOC + "\n```\n", place="P")])
        self.assertEqual(outcome["problems"], [])
        notes = [line for line in self.space.said if line.startswith("plantoir: note:")]
        self.assertEqual(len(notes), 1, self.space.said)
        self.assertIn("% alt:", notes[0])

    def test_a_diagram_that_never_finishes_is_stopped_the_rest_drawn_and_not_cached(self):
        slow = "\\begin{document}\nSLEEP\n\\end{document}"
        quick = "\\begin{document}\nquick\n\\end{document}"
        pages = [page("```tikz\n" + slow + "\n```\n\n```tikz\n" + quick + "\n```\n")]
        started = time.monotonic()
        outcome = self.space.prepare(pages, job_seconds=2)
        self.assertLess(time.monotonic() - started, 20)
        self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["tookTooLong"])
        self.assertEqual(outcome["drawn"], 1, "the diagram after it was still drawn")
        self.assertEqual(self.space.started(), 2, "the engine was started again for the rest")
        cached = sorted(path.name for path in self.space.cache.rglob("*.json"))
        self.assertEqual(cached, [f"tikz-{figures.key_of(quick)}.json"], "tookTooLong is never cached")

    def test_an_engine_that_cannot_draw_diagrams_still_checks_graphs_and_caches_nothing_for_them(self):
        space = Workspace(mode="no-tikz")
        try:
            outcome = space.prepare([page("```tikz\n" + DOC + "\n```\n\n```functionplot\ny = x\n```\n")])
            self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["engineMissing"])
            self.assertEqual(outcome["counts"][figures.GRAPH_ENGINE], 1)
            names = sorted(path.name.split("-")[0] for path in space.cache.rglob("*.json"))
            self.assertEqual(names, ["functionplot"])
        finally:
            space.close()

    def test_an_engine_that_never_starts_fails_every_figure_without_hanging(self):
        space = Workspace(mode="never-ready")
        try:
            started = time.monotonic()
            outcome = space.prepare([page("```functionplot\ny = x\n```\n")], start_seconds=2)
            self.assertLess(time.monotonic() - started, 20)
            self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["engineMissing"])
        finally:
            space.close()

    def test_a_full_rebuild_draws_again(self):
        pages = [page("```tikz\n" + DOC + "\n```\n")]
        self.space.prepare(pages)
        outcome = self.space.prepare(pages, full_rebuild=True)
        self.assertEqual(outcome["drawn"], 1)

    def test_a_graph_that_cannot_be_drawn_is_reported_and_the_site_carries_no_engine(self):
        outcome = self.space.prepare([page("```functionplot\ny = ln(x)\n```\n", place="Logs")])
        self.assertEqual(outcome["counts"][figures.GRAPH_ENGINE], 0)
        self.assertEqual(outcome["problems"][0]["reason"], "unknownName")
        self.assertEqual(outcome["problems"][0]["name"], "ln")

    def test_figures_go_when_the_last_one_does(self):
        self.space.prepare([page("```tikz\n" + DOC + "\n```\n")])
        self.assertTrue((self.space.output / "quartz" / "static" / "tikz").is_dir())
        self.space.prepare([page("No figures any more.")])
        self.assertFalse((self.space.output / "quartz" / "static" / "tikz").exists())
        self.assertFalse((self.space.output / "quartz" / figures.WORKSPACE).exists())


class PagesTests(unittest.TestCase):
    def test_only_pages_students_can_see_outside_media(self):
        folder = Path(tempfile.mkdtemp(prefix="plantoir-figure-pages-"))
        try:
            (folder / "Media").mkdir()
            (folder / "Unit 1").mkdir()
            (folder / "Unit 1" / "Seen.md").write_text("```tikz\nx\n```\n", encoding="utf-8")
            (folder / "Unit 1" / "Hidden.md").write_text("---\npublish: false\n---\n```tikz\nx\n```\n", encoding="utf-8")
            (folder / "Media" / "Notes.md").write_text("```tikz\nx\n```\n", encoding="utf-8")
            (folder / "Plain.md").write_text("No fences.\n", encoding="utf-8")
            pages = figures.pages_students_see(
                folder, lambda text: "publish: false" in text,
                lambda path: path.relative_to(folder).as_posix()[:-3], lambda path: None,
                skip=lambda first: first == "Media")
            self.assertEqual([entry["place"] for entry in pages], ["Unit 1/Seen"])
        finally:
            shutil.rmtree(folder, ignore_errors=True)


class CacheTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-figure-cache-"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_another_engines_folder_is_removed_and_old_entries_pruned(self):
        old = figures.Cache(self.folder, "aaaa")
        old.put("tikz", "k1", {"ok": True})
        cache = figures.Cache(self.folder, "bbbb")
        cache.put("tikz", "fresh", {"ok": True})
        cache.put("tikz", "stale", {"ok": True})
        stale = self.folder / "bbbb" / "tikz-stale.json"
        long_ago = time.time() - (rules("cache", "pruneDays") + 1) * 86400
        os.utime(stale, (long_ago, long_ago))
        cache.prune()
        self.assertFalse((self.folder / "aaaa").exists())
        self.assertIsNotNone(cache.get("tikz", "fresh"))
        self.assertIsNone(cache.get("tikz", "stale"))

    def test_a_half_written_entry_is_not_cached(self):
        cache = figures.Cache(self.folder, "cccc")
        (self.folder / "cccc").mkdir(parents=True)
        (self.folder / "cccc" / "tikz-half.json").write_text('{"ok": tr', encoding="utf-8")
        self.assertIsNone(cache.get("tikz", "half"))

    def test_two_writers_never_leave_a_broken_entry(self):
        cache = figures.Cache(self.folder, "dddd")
        big = {"ok": True, "svg": "<svg>" + "x" * 200000 + "</svg>"}

        def write():
            for _ in range(20):
                cache.put("tikz", "same", big)

        threads = [threading.Thread(target=write) for _ in range(4)]
        for thread in threads:
            thread.start()
        for _ in range(50):
            entry = cache.get("tikz", "same")
            self.assertIn(entry, (None, big))
        for thread in threads:
            thread.join()
        self.assertEqual(cache.get("tikz", "same"), big)
        self.assertEqual([path.name for path in (self.folder / "dddd").iterdir()], ["tikz-same.json"])

    def test_clearing_never_fails_over_a_file_already_gone(self):
        cache = figures.Cache(self.folder, "eeee")
        cache.clear()
        cache.put("tikz", "a", {"ok": True})
        cache.clear()
        self.assertIsNone(cache.get("tikz", "a"))

    def test_the_engine_id_follows_each_file(self):
        files = [self.folder / name for name in ("a", "b")]
        files[0].write_text("one", encoding="utf-8")
        first = figures.engine_id(files)
        files[1].write_text("two", encoding="utf-8")
        self.assertNotEqual(figures.engine_id(files), first)
        self.assertEqual(len(first), 16)

    def test_the_engine_id_is_made_of_what_the_contract_says(self):
        use_the_repository_contract()
        named = rules("cache", "engineIdFrom")
        support = Path(__file__).resolve().parent.parent / "support"
        made = figures.engine_files(support, Path("/vendor"))
        self.assertEqual(len(made), len(named))
        for path, name in zip(made, named):
            self.assertTrue(path.as_posix().endswith(name.split(" ")[0].replace("support/", "")), (path, name))


class FontTests(unittest.TestCase):
    def test_fonts_css_names_each_face_once_and_blocks_until_loaded(self):
        css = figures.fonts_css(["cmr10", "cmmi10"])
        self.assertEqual(css.count("@font-face"), 2)
        self.assertIn('src: url("cmr10.ttf") format("truetype")', css)
        self.assertIn("font-display: block", css)

    def test_the_faces_an_svg_names(self):
        svg = '<svg><text font-family="cmr10">a</text><g font-family="cmmi10"><text font-family="cmr10">b</text></g></svg>'
        self.assertEqual(figures.fonts_in(svg), ["cmmi10", "cmr10"])


class PinTests(unittest.TestCase):
    """contracts/toolchain.json -> pins nodeTikzjax: the version the image
    installs is the one support/figures says, the lockfile resolves, and the
    contract names (the Dockerfile half is ToolchainContractTests')."""

    def test_the_tikz_engine_pin_matches_its_package_and_lockfile(self):
        use_the_repository_contract()
        pins = {pin["pin"]: pin for pin in contracts.section("toolchain", "pins")}
        figures_folder = Path(__file__).resolve().parent.parent / "support" / "figures"
        package = json.loads((figures_folder / "package.json").read_text(encoding="utf-8"))
        lock = json.loads((figures_folder / "package-lock.json").read_text(encoding="utf-8"))
        version = pins["nodeTikzjax"]["value"]
        self.assertEqual(package["dependencies"], {"node-tikzjax": version})
        self.assertEqual(lock["packages"][""]["dependencies"], {"node-tikzjax": version})
        self.assertEqual(lock["packages"]["node_modules/node-tikzjax"]["version"], version)
        self.assertIn(version, pins["nodeTikzjax"]["dockerfileContains"])
        self.assertIn(pins["functionPlot"]["value"], pins["functionPlot"]["dockerfileContains"])


class TimingTests(unittest.TestCase):
    def test_the_clock_is_the_contracts(self):
        use_the_repository_contract()
        self.assertEqual(figures.JOB_SECONDS, rules("timing", "perDiagramSeconds"))
        self.assertEqual(figures.START_SECONDS, rules("timing", "startSeconds"))
        self.assertEqual(figures.PRUNE_DAYS, rules("cache", "pruneDays"))


class WordsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def test_every_reason_the_build_can_give_has_words(self):
        reasons = rules("words", "reasons")
        named = set()
        for case in rules("texErrors", "cases"):
            if case["reason"]:
                named.add(case["reason"])
        for case in rules("functionplot", "parseCases"):
            if case.get("problem"):
                named.add(case["problem"]["reason"])
        for case in rules("functionplot", "expressionCases", "cases"):
            if case["problem"]:
                named.add(case["problem"])
        named.update(["engineMissing", "graphEngineMissing", "unknownSetting", "missingAlt"])
        self.assertEqual(sorted(named - set(reasons)), [])

    def test_no_word_names_the_machinery(self):
        forbidden = contracts.section("shared-rules", "userFacingLabelWords", "forbidden")
        said = list(rules("words", "site").values()) + list(rules("words", "reasons").values())
        for check in contracts.section("shared-rules", "siteHealth", "checks"):
            if check["name"] == "figuresCouldNotBeDrawn":
                said += [check["sentence"], check["sentenceForSeveral"], check["detail"]]
        for sentence in said:
            words = set(sentence.lower().replace("’", "'").split())
            for word in forbidden:
                self.assertNotIn(word, words, sentence)

    def test_the_folder_problem_names_each_figure(self):
        problems = [
            {"page": "Units/Similar Triangles", "engine": "tikz", "block": 2, "line": 14,
             "reason": "undefinedCommand", "name": "\\foo"},
            {"page": "Logs", "engine": "functionplot", "block": 1, "line": None, "blockLine": 3,
             "reason": "tookTooLong"},
        ]
        facts = {"media_target_exists": True, "section_index_exists": True, "figure_problems": problems}
        found = [item for item in site_health.findings(facts, "MPM2D", 1) if item.name == "figuresCouldNotBeDrawn"]
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].sentence, "2 diagrams and graphs in MPM2D Section 1 could not be drawn.")
        self.assertIn("“Units/Similar Triangles”, diagram 2, line 14: \\foo isn't a command LaTeX knows here",
                      found[0].detail)
        self.assertIn("“Logs”, graph 1, line 3 of the graph: it took longer than 20 seconds", found[0].detail)
        self.assertFalse(found[0].fixable)

    def test_one_figure_is_named_in_the_sentence(self):
        facts = {"media_target_exists": True, "section_index_exists": True,
                 "figure_problems": [{"page": "{course} notes", "engine": "tikz", "block": 1, "line": 5,
                                      "reason": "missingDocument"}]}
        found = [item for item in site_health.findings(facts, "MPM2D", 1) if item.name == "figuresCouldNotBeDrawn"]
        self.assertEqual(found[0].sentence, "A diagram or graph on “{course} notes” in MPM2D Section 1 could not be drawn.")

    def test_more_than_ten_are_counted_not_listed(self):
        problems = [{"page": f"P{index}", "engine": "tikz", "block": 1, "line": 1, "reason": "missingDocument"}
                    for index in range(12)]
        facts = {"media_target_exists": True, "section_index_exists": True, "figure_problems": problems}
        found = [item for item in site_health.findings(facts, "MPM2D", 1) if item.name == "figuresCouldNotBeDrawn"]
        self.assertIn("and 2 more", found[0].detail)
        self.assertNotIn("“P10”", found[0].detail)

    def test_the_graphs_engine_missing_says_so_in_its_own_words(self):
        folder = Path(tempfile.mkdtemp(prefix="plantoir-figure-gate-"))
        try:
            said = []
            (folder / "out" / "quartz" / "static").mkdir(parents=True)
            page_features.install_gated_assets(folder / "out", {"function-plot": 2}, vendor_dir=folder / "vendor",
                                               printer=said.append)
            self.assertEqual(len(said), 1)
            self.assertIn("graph", said[0])
            self.assertNotIn("print", said[0])
        finally:
            shutil.rmtree(folder, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
