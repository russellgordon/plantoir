#!/usr/bin/env python3
"""
A runnable block the SITE showed as plain code, said as one folder problem
(#567: contracts/shared-rules.json -> siteHealth.checks ->
runnableCodeShownAsPlainCode; scripts/site_said.py).

Pure stdlib, no Docker and no network - so Windows' PythonToolchainTests runs
it too. The site's half (the transformer recording and the emitter calling
site_said.py) is run in the image by check_runner_rules_against_the_site.py,
and end to end by verify.sh.

Run with:

    python3 scripts/test_site_disagreements.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import page_features  # noqa: E402
import site_health  # noqa: E402
import site_said  # noqa: E402
import toolchain_paths  # noqa: E402

SCRIPT = Path(__file__).resolve().parent / "site_said.py"
REPO_CONTRACTS = Path(__file__).resolve().parent.parent / "contracts"
NAME = "runnableCodeShownAsPlainCode"

# The page from codeRunnerBlocks.fences.pageShapes' review N3 case: a fence
# left open in a list item, then a runnable block. Its frontmatter makes the
# runnable block's opening line line 10 of the teacher's file.
UNCLOSED = ("---\ntitle: Loops\ncodeRunner: true\n---\n"
            "- step one\n  ```python\n  print(1)\n- step two\n\n```python run\nprint(2)\n```\n")


def _check() -> dict:
    for entry in contracts.section("shared-rules", "siteHealth", "checks"):
        if entry["name"] == NAME:
            return entry
    raise AssertionError(f"{NAME} is not in the contract")


class SiteDisagreementTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        if REPO_CONTRACTS.is_dir():
            toolchain_paths.CONTRACTS_DIR = REPO_CONTRACTS
        contracts.reset_cache()

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-site-said-"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    # ---- the contract's cases ------------------------------------------------

    def test_every_contract_case_is_worded_as_the_contract_says(self):
        cases = _check()["cases"]
        self.assertGreaterEqual(len(cases), 4, "the contract lost cases")
        table = site_health._checks_by_name()
        for case in cases:
            found = site_health.site_disagreements_finding(
                {"site_disagreements": case["blocks"]}, case["course"], case["section"], table)
            self.assertEqual(found.name, NAME, case["name"])
            self.assertEqual(found.sentence, case["sentence"], case["name"])
            if "detail" in case:
                self.assertEqual(found.detail, case["detail"], case["name"])
            else:
                self.assertTrue(found.detail.endswith(case["detailEndsWith"]), case["name"] + ": " + found.detail)
            self.assertFalse(found.fixable, case["name"])
            self.assertEqual(found.course, case["course"])
            self.assertEqual(found.section, case["section"])

    def test_nothing_the_teacher_reads_names_the_machinery(self):
        """Rule 1, through the nested `reasons` too, which the apps' sweeps
        (top-level strings only) do not reach."""
        forbidden = ["toolchain", "script", "docker", "container", "wsl", "python",
                     "json", "stdout", "quartz", "repository", "config",
                     "yaml", "frontmatter", "symlink", "vault"]
        entry = _check()
        shown = []
        for key, value in entry.items():
            if key in ("name", "why", "fill", "cases"):
                continue
            if isinstance(value, str):
                shown.append((key, value))
            elif isinstance(value, dict):
                for inner, text in value.items():
                    shown.append((f"{key}.{inner}", text))
        self.assertIn("reasons.blockAfterUnclosedFence", [key for key, _ in shown])
        for key, text in shown:
            for word in forbidden:
                self.assertNotIn(word, text.lower(), f"{NAME}.{key} says \"{word}\" to a teacher")

    def test_every_reason_the_site_records_has_words(self):
        # The transformer records these keys (codeRunner.ts), the same three
        # the `plantoir: error:` line chooses between.
        reasons = _check()["reasons"]
        for key in ("blockAfterUnclosedFence", "blockNotPrepared", "blockNotCompiled"):
            self.assertIn(key, reasons)
            self.assertIn(key, contracts.section("shared-rules", "codeRunnerBlocks", "words"))

    def test_it_is_never_offered_a_repair(self):
        never = contracts.section("shared-rules", "siteHealth", "repair", "neverOffered", "checks")
        self.assertIn(NAME, never)

    # ---- from what the site recorded to the facts ---------------------------------

    def test_the_line_is_found_in_the_teachers_file(self):
        self.assertEqual(site_said.opening_line(UNCLOSED, "python", "print(2)"), 10)

    def test_the_line_is_found_in_a_callout_and_a_list(self):
        page = "> [!example]- Try it\n> ```python run\n> x = 1\n> print(x)\n> ```\n"
        self.assertEqual(site_said.opening_line(page, "python", "x = 1\nprint(x)"), 2)
        page = "1. item\n   ```swift run\n   let a = 1\n   ```\n"
        self.assertEqual(site_said.opening_line(page, "swift", "let a = 1"), 2)

    def test_no_line_when_several_blocks_hold_the_same_code(self):
        page = "```python run\nprint(1)\n```\n\n```python run\nprint(1)\n```\n"
        self.assertIsNone(site_said.opening_line(page, "python", "print(1)"))

    def test_no_line_when_nothing_matches(self):
        self.assertIsNone(site_said.opening_line(UNCLOSED, "python", "print(3)"))
        self.assertIsNone(site_said.opening_line(UNCLOSED, "swift", "print(2)"))
        self.assertIsNone(site_said.opening_line(None, "python", "print(2)"))

    def test_a_block_without_run_is_not_its_opening_line(self):
        page = "```python\nprint(2)\n```\n"
        self.assertIsNone(site_said.opening_line(page, "python", "print(2)"))

    def _said(self, places=None, swift_named=None):
        return {"course": "ICS3U", "section": 1, "content": str(self.folder / "content"),
                "places": places or {}, "swiftNamed": swift_named or []}

    def test_the_page_is_named_by_its_place_and_its_line_read_from_its_source(self):
        source = self.folder / "Unit 1" / "Loops.md"
        source.parent.mkdir(parents=True)
        source.write_text(UNCLOSED, encoding="utf-8")
        said = self._said({"Units/Loops.md": {"place": "Unit 1/Loops", "source": str(source)}})
        facts = site_said.facts_from_site(said, [
            {"page": "Units/Loops.md", "language": "python", "block": 1,
             "reason": "blockAfterUnclosedFence", "code": "print(2)"}])
        self.assertEqual(facts, [{"page": "Unit 1/Loops", "language": "python", "block": 1,
                                  "line": 10, "reason": "blockAfterUnclosedFence"}])

    def test_a_page_the_build_did_not_place_is_named_by_its_path_and_read_from_the_content(self):
        page = self.folder / "content" / "Units" / "Strings.md"
        page.parent.mkdir(parents=True)
        page.write_text(UNCLOSED, encoding="utf-8")
        facts = site_said.facts_from_site(self._said(), [
            {"page": "Units/Strings.md", "language": "python", "block": 1,
             "reason": "blockAfterUnclosedFence", "code": "print(2)"}])
        self.assertEqual(facts[0]["page"], "Units/Strings")
        self.assertEqual(facts[0]["line"], 10)

    def test_a_page_named_in_another_unicode_form_is_still_found(self):
        """Amendment 6: the site's path and the build's are NFC'd on both sides."""
        composed = unicodedata.normalize("NFC", "Units/Café.md")
        decomposed = unicodedata.normalize("NFD", "Units/Café.md")
        self.assertNotEqual(composed, decomposed)
        said = self._said({decomposed: {"place": "Unit 1/Café", "source": None}})
        facts = site_said.facts_from_site(said, [
            {"page": composed, "language": "python", "block": 1, "reason": "blockNotPrepared", "code": ""}])
        self.assertEqual(facts[0]["page"], unicodedata.normalize("NFC", "Unit 1/Café"))

    def test_pages_come_in_path_order_and_blocks_in_the_sites_order(self):
        facts = site_said.facts_from_site(self._said(), [
            {"page": "b.md", "language": "python", "block": 2, "reason": "blockNotPrepared", "code": ""},
            {"page": "a.md", "language": "python", "block": 1, "reason": "blockNotPrepared", "code": ""},
            {"page": "b.md", "language": "python", "block": 1, "reason": "blockNotPrepared", "code": ""},
        ])
        self.assertEqual([(fact["page"], fact["block"]) for fact in facts], [("a", 1), ("b", 2), ("b", 1)])

    def test_a_swift_block_already_named_is_left_out(self):
        """Amendment 5: one block, one finding - swiftCouldNotBePrepared said it."""
        said = self._said({"Units/Strings.md": {"place": "Unit 1/Strings", "source": None}},
                          [["Unit 1/Strings", 1]])
        facts = site_said.facts_from_site(said, [
            {"page": "Units/Strings.md", "language": "swift", "block": 1, "reason": "blockNotCompiled", "code": ""},
            {"page": "Units/Strings.md", "language": "swift", "block": 2, "reason": "blockNotCompiled", "code": ""},
            {"page": "Units/Strings.md", "language": "python", "block": 1, "reason": "blockNotPrepared", "code": ""},
        ])
        self.assertEqual([(fact["language"], fact["block"]) for fact in facts], [("swift", 2), ("python", 1)])

    # ---- the command line the site's emitter runs ---------------------------------

    def _run(self, stdin: bytes):
        environment = dict(os.environ, PLANTOIR_CONTRACTS_DIR=str(toolchain_paths.CONTRACTS_DIR),
                           PYTHONDONTWRITEBYTECODE="1")
        return subprocess.run([sys.executable, str(SCRIPT)], input=stdin, capture_output=True,
                              env=environment, timeout=60, cwd=str(self.folder))

    def test_the_command_line_prints_exactly_one_marker_and_nothing_else_found(self):
        """Amendment 1, the MUST: ONLY this finding - never the folder checks
        whose facts are not here (Media, the front page), which
        announce_or_stay_quiet would have said falsely."""
        payload = dict(self._said(), blocks=[
            {"page": "Units/Loops.md", "language": "python", "block": 1,
             "reason": "blockAfterUnclosedFence", "code": "print(2)"},
            {"page": "Units/Strings.md", "language": "swift", "block": 1,
             "reason": "blockNotCompiled", "code": "print(1)"}])
        done = self._run(json.dumps(payload).encode("utf-8"))
        self.assertEqual(done.returncode, 0, done.stderr)
        printed = done.stdout.decode("utf-8")
        prefix = site_health.marker_prefix()
        markers = [line for line in printed.splitlines() if prefix in line]
        self.assertEqual(len(markers), 1, printed)
        finding = json.loads(markers[0][markers[0].index(prefix) + len(prefix):])
        self.assertEqual(finding["name"], NAME)
        self.assertEqual(finding["course"], "ICS3U")
        self.assertEqual(finding["section"], 1)
        self.assertEqual(finding["sentence"], "2 blocks of code in ICS3U Section 1 show as plain code, with no Run button.")
        self.assertEqual(printed.count("⚠️"), 1, printed)
        self.assertIn("⚠️  " + finding["sentence"], printed)

    def test_the_command_line_says_nothing_when_every_block_is_already_named(self):
        payload = dict(self._said({"Units/Strings.md": {"place": "Unit 1/Strings", "source": None}},
                                  [["Unit 1/Strings", 1]]),
                       blocks=[{"page": "Units/Strings.md", "language": "swift", "block": 1,
                                "reason": "blockNotCompiled", "code": ""}])
        done = self._run(json.dumps(payload).encode("utf-8"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.decode("utf-8"), "")

    def test_the_command_line_survives_what_it_is_handed(self):
        for stdin in (b"", b"not json", b"[1, 2]", "{\"blocks\": [{\"page\": 7}]".encode("utf-8")):
            done = self._run(stdin)
            self.assertEqual(done.returncode, 0, (stdin, done.stderr))
            self.assertNotIn(site_health.marker_prefix(), done.stdout.decode("utf-8"), stdin)

    def test_the_command_line_survives_a_contract_it_cannot_read(self):
        payload = dict(self._said(), blocks=[{"page": "a.md", "language": "python", "block": 1,
                                              "reason": "blockNotPrepared", "code": ""}])
        environment = dict(os.environ, PLANTOIR_CONTRACTS_DIR=str(self.folder / "nowhere"),
                           PYTHONDONTWRITEBYTECODE="1")
        done = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(payload).encode("utf-8"),
                              capture_output=True, env=environment, timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr)
        printed = done.stdout.decode("utf-8")
        self.assertNotIn(site_health.marker_prefix(), printed)
        self.assertEqual(len(printed.strip().splitlines()), 1, printed)

    # ---- the side file the build writes ------------------------------------------------

    def test_the_side_file_says_what_the_emitter_needs_and_is_written_once(self):
        output = self.folder / "site"
        places = {"Units/Loops.md": {"place": "Unit 1/Loops", "source": "/c/Unit 1/Loops.md"}}
        self.assertTrue(site_said.write_side_file(output, "ICS3U", 2, places, [["Unit 1/Strings", 3]],
                                                  self.folder / "content"))
        written = json.loads((output / "quartz" / site_said.SIDE_FILE).read_text(encoding="utf-8"))
        self.assertEqual(written["python"], sys.executable)
        self.assertEqual(Path(written["script"]), SCRIPT)
        self.assertEqual(written["course"], "ICS3U")
        self.assertEqual(written["section"], 2)
        self.assertEqual(written["places"], places)
        self.assertEqual(written["swiftNamed"], [["Unit 1/Strings", 3]])
        self.assertEqual(written["content"], str(self.folder / "content"))
        self.assertFalse(site_said.write_side_file(output, "ICS3U", 2, places, [["Unit 1/Strings", 3]],
                                                   self.folder / "content"),
                         "the same input must give the same bytes")

    def test_the_runner_words_the_page_bundles_carry_no_path(self):
        """The page's script bundles plantoir_code_runner.json, so nothing of
        the build machine may ride in it - which is why the side file is its
        own."""
        words = json.dumps(page_features.runner_words())
        for key in ('"python"', '"script"', '"places"', '"course"', '"section"', '"swiftNamed"'):
            self.assertNotIn(key, words)


if __name__ == "__main__":
    unittest.main()
