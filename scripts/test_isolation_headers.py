#!/usr/bin/env python3
"""
Live input (#583): which pages a publish isolates, and the `_headers` block
that does it on Netlify and Cloudflare Pages (scripts/isolation_headers.py),
against contracts/shared-rules.json -> codeRunnerBlocks.isolation.

The cases are not retyped here: `isolation.cases` (a built page's HTML ->
live, or why not) and `isolation.pathCases` (a built file -> the rule paths
each host was MEASURED to match, 2026-10-17) are read from the contract. The
preview's half of the same rule (support/quartz/cli/plantoirIsolation.mjs)
runs the same cases in the image (check_runner_rules_against_the_site.py).

Stdlib only, so it runs on Windows too (PythonToolchainTests).

    python3 scripts/test_isolation_headers.py
"""
import json
import tempfile
import unittest
from pathlib import Path

import contracts
import isolation_headers
import netlify_badge
import toolchain_paths


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def isolation(*keys):
    return contracts.section("shared-rules", "codeRunnerBlocks", "isolation", *keys)


def words():
    return contracts.section("shared-rules", "codeRunnerBlocks", "words")


def case_html(name):
    for case in isolation("cases"):
        if case["name"] == name:
            return case["html"]
    raise KeyError(name)


LIVE_INPUT = "a block that reads input"
LIVE_EDIT = "Quartz's own head and a block a student can edit"
FRAMED = "a YouTube frame"
FRAMED_NO_INPUT = "a GeoGebra frame"
NO_BLOCK = "a page with no runnable block"


class SiteFolder:
    """A stand-in for a built public/."""

    def __init__(self, root: Path):
        self.root = root

    def page(self, relative: str, case_name: str):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(case_html(case_name), encoding="utf-8")

    def engine(self, folder: str):
        (self.root / folder).mkdir(parents=True, exist_ok=True)
        (self.root / folder / "x.js").write_text("", encoding="utf-8")

    def headers(self) -> str:
        path = self.root / "_headers"
        return path.read_text(encoding="utf-8") if path.is_file() else ""

    def blocks(self) -> list:
        """Each of our blocks in _headers, as its list of lines."""
        markers = isolation("markers")
        found = []
        current = None
        for line in self.headers().splitlines():
            if line == markers["begin"]:
                current = []
            elif line == markers["end"] and current is not None:
                found.append(current)
                current = None
            elif current is not None:
                current.append(line)
        return found


class ContractCaseTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()

    def test_every_page_case_has_the_contracts_verdict(self):
        for case in isolation("cases"):
            with self.subTest(case=case["name"]):
                self.assertEqual(isolation_headers.page_verdict(case["html"]),
                                 {"verdict": case["verdict"], "readsInput": case["readsInput"]})

    def test_every_measured_path_is_spelled_as_each_host_matches_it(self):
        for case in isolation("pathCases"):
            for host in ("netlify", "cloudflare"):
                with self.subTest(file=case["file"], host=host):
                    self.assertEqual(isolation_headers.page_paths(case["file"], host), case[host])

    def test_the_reasons_are_the_words_the_note_line_uses(self):
        for reason in isolation_headers.REASONS:
            with self.subTest(reason=reason):
                self.assertIn(isolation_headers._REASON_WORD[reason], words())


class BlockTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()
        self.temp = tempfile.TemporaryDirectory()
        self.site = SiteFolder(Path(self.temp.name))

    def tearDown(self):
        self.temp.cleanup()

    def make_site(self):
        self.site.page("Units/Loops.html", LIVE_INPUT)
        self.site.page("Units/Café.html", LIVE_EDIT)
        self.site.page("Units/index.html", LIVE_EDIT)
        self.site.page("Units/Video.html", FRAMED)
        self.site.page("Units/Plain.html", NO_BLOCK)
        self.site.engine("static/pyodide")

    def test_netlify_gets_the_engine_folder_and_each_live_page_in_its_spelling(self):
        self.make_site()
        outcome = isolation_headers.write_isolation_headers(self.site.root, "netlify")
        blocks = self.site.blocks()
        self.assertEqual(len(blocks), 1)
        page = isolation("headers", "page")
        engine = isolation("headers", "engine")
        want = ["/static/pyodide/*"] + [f"  {name}: {value}" for name, value in engine.items()]
        # Reads input first, then the rest in path order.
        for path in ["/units/loops", "/units/caf%C3%A9", "/units/"]:
            want.append(path)
            want.extend(f"  {name}: {value}" for name, value in page.items())
        self.assertEqual(blocks[0], want)
        self.assertEqual(outcome["live"], ["Units/Loops.html", "Units/Café.html", "Units/index.html"])
        self.assertEqual([item["file"] for item in outcome["notLive"]], ["Units/Video.html"])
        self.assertEqual(outcome["capped"], [])

    def test_cloudflare_gets_its_own_spelling(self):
        self.make_site()
        isolation_headers.write_isolation_headers(self.site.root, "cloudflare")
        paths = [line for line in self.site.blocks()[0] if not line.startswith(" ")]
        self.assertEqual(paths, ["/static/pyodide/*", "/Units/Loops", "/Units/Caf%C3%A9", "/Units/"])

    def test_an_engine_the_site_does_not_carry_gets_no_rule(self):
        self.make_site()
        isolation_headers.write_isolation_headers(self.site.root, "netlify")
        self.assertNotIn("/static/swift/*", self.site.headers())
        self.site.engine("static/swift")
        isolation_headers.write_isolation_headers(self.site.root, "netlify")
        self.assertIn("/static/swift/*", self.site.headers())

    def test_the_block_is_replaced_never_appended_and_other_lines_are_kept(self):
        self.make_site()
        (self.site.root / "_headers").write_text("/teacher/*\n  X-Teacher: kept\n", encoding="utf-8")
        for host in ("netlify", "cloudflare", "netlify"):
            isolation_headers.write_isolation_headers(self.site.root, host)
        self.assertEqual(len(self.site.blocks()), 1)
        self.assertIn("/teacher/*\n  X-Teacher: kept\n", self.site.headers())
        self.assertIn("/units/loops", self.site.headers())
        self.assertNotIn("/Units/Loops\n", self.site.headers())

    def test_the_badge_rule_keeps_the_block_and_the_block_keeps_the_badge_rule(self):
        self.make_site()
        for _ in range(2):
            isolation_headers.write_isolation_headers(self.site.root, "netlify")
            netlify_badge.write_netlify_headers_file(self.site.root)
        text = self.site.headers()
        self.assertEqual(len(self.site.blocks()), 1)
        self.assertEqual(text.count(netlify_badge.MANAGED_MARKER), 1)
        self.assertEqual(text.count("Content-Security-Policy:"), 1)

    def test_no_live_page_takes_the_block_out_and_leaves_the_rest(self):
        self.make_site()
        isolation_headers.write_isolation_headers(self.site.root, "netlify")
        for name in ("Units/Loops.html", "Units/Café.html", "Units/index.html"):
            (self.site.root / name).unlink()
        isolation_headers.write_isolation_headers(self.site.root, "netlify")
        self.assertFalse((self.site.root / "_headers").exists())
        (self.site.root / "_headers").write_text("/teacher/*\n  X-Teacher: kept\n", encoding="utf-8")
        isolation_headers.write_isolation_headers(self.site.root, "netlify")
        self.assertEqual(self.site.headers(), "/teacher/*\n  X-Teacher: kept\n")

    def test_an_unended_block_is_taken_out_up_to_the_next_plantoir_block(self):
        markers = isolation("markers")
        text = f"/a\n  X: 1\n\n{markers['begin']}\n/old\n  Y: 2\n\n{netlify_badge.MANAGED_MARKER}\n/*\n  Z: 3\n"
        kept = isolation_headers.without_our_block(text, markers)
        self.assertNotIn("/old", kept)
        self.assertIn(netlify_badge.MANAGED_MARKER, kept)
        self.assertIn("/a\n  X: 1", kept)

    def test_cloudflare_stops_at_its_hundred_rules_and_the_note_says_how_many(self):
        self.site.engine("static/pyodide")
        for number in range(120):
            self.site.page(f"Units/Edit-{number:03d}.html", LIVE_EDIT)
        for number in range(5):
            self.site.page(f"Units/Ask-{number:03d}.html", LIVE_INPUT)
        (self.site.root / "_headers").write_text("/a\n  X: 1\n/b\n  X: 2\n/c\n  X: 3\n", encoding="utf-8")
        outcome = isolation_headers.write_isolation_headers(self.site.root, "cloudflare")
        most = isolation("hosts", "cloudflareMostRules")
        rules = [line for line in self.site.headers().splitlines()
                 if line.strip() and not line.startswith((" ", "#"))]
        self.assertEqual(len(rules), most)
        self.assertEqual(len(outcome["live"]), most - 3 - 1)
        # The pages whose code reads input are never the ones left out.
        for number in range(5):
            self.assertIn(f"Units/Ask-{number:03d}.html", outcome["live"])
        self.assertEqual(len(outcome["capped"]), 125 - (most - 3 - 1))
        notes = isolation_headers.note_lines(self.site.root, outcome)
        self.assertEqual(notes, ["plantoir: note: " + words()["notLiveCapped"].replace("{count}", str(len(outcome["capped"])))])
        # Netlify has no such limit.
        outcome = isolation_headers.write_isolation_headers(self.site.root, "netlify")
        self.assertEqual(len(outcome["live"]), 125)
        self.assertEqual(outcome["capped"], [])

    def test_a_page_that_keeps_the_box_although_it_reads_input_is_named_once_with_why(self):
        self.make_site()
        self.site.page("Units/Applet.html", FRAMED_NO_INPUT)
        index = self.site.root / "static" / "contentIndex.json"
        index.parent.mkdir(parents=True, exist_ok=True)
        index.write_text(json.dumps({"Units/Video": {"slug": "Units/Video", "filePath": "Units/Video.md"}}),
                         encoding="utf-8")
        outcome = isolation_headers.write_isolation_headers(self.site.root, "netlify")
        notes = isolation_headers.note_lines(self.site.root, outcome)
        reason = words()["notLiveBecause"].replace("{what}", words()["notLiveFrame"])
        self.assertEqual(notes, [f"plantoir: note: Units/Video.md: {reason}"])

    def test_a_publish_never_fails_over_the_headers(self):
        self.make_site()
        said = []
        original = isolation_headers._rules

        def broken():
            raise contracts.ContractMissing("no contract")

        isolation_headers._rules = broken
        try:
            outcome = isolation_headers.publish_headers(self.site.root, "netlify", printer=said.append)
        finally:
            isolation_headers._rules = original
        self.assertEqual(outcome, {"live": [], "notLive": [], "capped": []})
        self.assertFalse((self.site.root / "_headers").exists())
        self.assertEqual(len(said), 1)

    def test_what_the_publish_says_names_no_machinery(self):
        self.make_site()
        said = []
        isolation_headers.publish_headers(self.site.root, "netlify", printer=said.append)
        for line in said:
            for word in ("pyodide", "webassembly", "wasm", "worker", "thread", "docker", "container",
                         "toolchain", "header", "isolat", "sharedarraybuffer"):
                self.assertNotIn(word, line.lower())


if __name__ == "__main__":
    unittest.main()
