#!/usr/bin/env python3
"""
The build's check for links into hidden pages (#333), against the shared
cases in `contracts/shared-rules.json` -> `siteHealth.linksIntoHiddenPages`,
and the one finding it becomes.

Each case is laid out the way a build lays out a section's merged content: a
page in `section1/` lands at the top of the content, every other page keeps
its place, and each copy is remembered against its source in the course
folder, so the names the check reports are the places a teacher would look.

Needs python-frontmatter (the build's own import), like the other tests that
import `build_site`; verify.sh runs it in the image.

Run with:

    python3 scripts/test_links_into_hidden_pages.py
"""
import tempfile
import unittest
from pathlib import Path

import build_site
import contracts
import site_health
import toolchain_paths


def _lay_out(case: dict, course_folder: Path, content_root: Path) -> None:
    build_site.forget_vault_sources(course_folder)
    for page in case["pages"]:
        place = page["path"]
        source = course_folder / place
        is_section_page = place.startswith("section1/")
        copied = content_root / (place[len("section1/"):] if is_section_page else place)
        text = page.get("body", "")
        if not page.get("visible", True):
            text = "---\npublish: false\n---\n" + text
        for path in (source, copied):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        build_site.remember_vault_source(copied, source, is_section_page)


class LinksIntoHiddenPagesTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.cases = contracts.section("shared-rules", "siteHealth", "linksIntoHiddenPages", "cases")

    def tearDown(self):
        build_site.forget_vault_sources()

    def _pairs(self, case: dict) -> list:
        with tempfile.TemporaryDirectory() as temporary:
            course_folder = Path(temporary) / "ICS3U"
            content_root = Path(temporary) / "content"
            _lay_out(case, course_folder, content_root)
            found = build_site._links_into_hidden_pages(content_root)
        pairs = []
        for entry in found:
            pairs.append([entry["from"], entry["to"]])
        return pairs

    def test_every_case(self):
        self.assertGreaterEqual(len(self.cases), 10)
        for case in self.cases:
            with self.subTest(case["name"]):
                self.assertEqual(self._pairs(case), case["expect"])

    def test_the_finding_names_ten_and_counts_the_rest(self):
        for case in self.cases:
            if "expectDetailNames" not in case:
                continue
            with self.subTest(case["name"]):
                facts = {"coverage_wanted": False, "media_target_exists": True,
                         "section_index_exists": True}
                pairs = self._pairs(case)
                facts["links_into_hidden_pages"] = [{"from": one, "to": two} for one, two in pairs]
                found = site_health.findings(facts, "ICS3U", 1)
                self.assertEqual([item.name for item in found], ["linksIntoHiddenPages"])
                detail = found[0].detail
                self.assertEqual(detail.count("→"), case["expectDetailNames"])
                entry = None
                for check in contracts.section("shared-rules", "siteHealth", "checks"):
                    if check["name"] == "linksIntoHiddenPages":
                        entry = check
                more = site_health.filled(entry["andMore"], {"count": case["expectAndMore"]})
                self.assertTrue(detail.endswith(more + "."), detail)

    def test_two_pairs_are_one_marker_line(self):
        """ONE finding per section build, never one per link: both apps key a
        finding on name, course and section, so two would collide (#246)."""
        facts = {"coverage_wanted": False, "media_target_exists": True,
                 "section_index_exists": True,
                 "links_into_hidden_pages": [
                     {"from": "section1/All Classes/Unit 1, Day 2", "to": "Concepts/A"},
                     {"from": "section1/All Classes/Unit 1, Day 3", "to": "Concepts/B"}]}
        found = site_health.findings(facts, "ICS3U", 1)
        self.assertEqual(len(found), 1)
        self.assertIn("2 links", found[0].sentence)
        printed = []
        site_health.announce(found, printer=printed.append)
        prefix = site_health.marker_prefix()
        marker_lines = [line for line in printed if line.startswith(prefix)]
        self.assertEqual(len(marker_lines), 1)

    def test_one_pair_names_the_hidden_page(self):
        facts = {"coverage_wanted": False, "media_target_exists": True,
                 "section_index_exists": True,
                 "links_into_hidden_pages": [{"from": "section1/index", "to": "{course} notes"}]}
        found = site_health.findings(facts, "ICS3U", 1)
        self.assertIn("“{course} notes”", found[0].sentence)
        self.assertFalse(found[0].fixable)

    def test_an_embed_of_the_index_is_read_even_though_the_dating_walk_drops_it(self):
        """The dating walk's reader drops links to index and Key Links; this
        check must not inherit that, or a visible page embedding a hidden
        folder landing page would go unlisted."""
        case = {"pages": [
            {"path": "section1/All Classes/Unit 1, Day 2.md", "visible": True,
             "body": "![[Concepts/index]]\n"},
            {"path": "Concepts/index.md", "visible": False, "body": "Body\n"}]}
        self.assertEqual(self._pairs(case),
                         [["section1/All Classes/Unit 1, Day 2", "Concepts/index"]])

    def test_a_path_is_resolved_before_a_name(self):
        """By name alone this link is ambiguous (one Evidence is visible, so
        the every-candidate rule would stay quiet); written with its folder
        it names the hidden one. The build's reading, not a shared case: the
        mac's graph holds one page per title."""
        case = {"pages": [
            {"path": "section1/All Classes/Unit 1, Day 2.md", "visible": True,
             "body": "[[Concepts/Evidence]]\n"},
            {"path": "Concepts/Evidence.md", "visible": False, "body": "Body\n"},
            {"path": "Tasks/Evidence.md", "visible": True, "body": "Body\n"}]}
        self.assertEqual(self._pairs(case),
                         [["section1/All Classes/Unit 1, Day 2", "Concepts/Evidence"]])

    def test_a_name_shared_by_a_visible_page_is_not_listed(self):
        case = {"pages": [
            {"path": "section1/All Classes/Unit 1, Day 2.md", "visible": True,
             "body": "[[Evidence]]\n"},
            {"path": "Concepts/Evidence.md", "visible": False, "body": "Body\n"},
            {"path": "Tasks/Evidence.md", "visible": True, "body": "Body\n"}]}
        self.assertEqual(self._pairs(case), [])


if __name__ == "__main__":
    unittest.main()
