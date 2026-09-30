#!/usr/bin/env python3
"""
The links checklist's offer (#379): which hidden pages the section window
offers to publish, in which group, ticked or not, and with which date — and
the file the build writes it to.

The cases are not retyped here. They are deserialised from
contracts/class-planning.json -> datingPagesAClassBrings.fromTheLinksChecklist
(the rule) and contracts/shared-rules.json -> linksChecklist.buildCases (what
the build does with the file). Each case is laid out the way
test_links_into_hidden_pages.py lays out a section's merged content: a page in
section1/ lands at the top of the content, every page is remembered against
its source in the course folder, so the names the offer carries are the places
a teacher would look.

Needs python-frontmatter (the build's own import), like the other tests that
import `build_site`; verify.sh runs it in the image, and Windows'
PythonToolchainTests discovers it.

Run with:

    python3 scripts/test_links_checklist.py
"""
import json
import tempfile
import unittest
from pathlib import Path

import build_site
import contracts
import toolchain_paths


def _load(file: str, *path):
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.section(file, *path)


def lay_out(case: dict, course_folder: Path, content_root: Path) -> None:
    """Writes each page twice — the teacher's file and the build's copy — and
    remembers one against the other, the way build_section_site does."""
    build_site.forget_vault_sources(course_folder)
    published = []
    for page in case["pages"]:
        place = page["path"]
        source = course_folder / (place + ".md")
        is_section_page = place.startswith("section1/")
        copied = content_root / ((place[len("section1/"):] if is_section_page else place) + ".md")
        front = []
        if not page.get("visible", True):
            front.append("publish: false")
        if page.get("created"):
            front.append(f"created: {page['created']}")
        text = ""
        if front:
            text = "---\n" + "\n".join(front) + "\n---\n"
        for link in page.get("links", []):
            text += f"[[{link}]]\n"
        if not page.get("links"):
            text += "Something to read.\n"
        for path in (source, copied):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        build_site.remember_vault_source(copied, source, is_section_page)
        if page.get("published"):
            published.append(place)
    if published:
        record = course_folder / ".publish_state" / "section1.published-pages"
        record.mkdir(parents=True, exist_ok=True)
        (record / "20260901T120000Z-netlify.json").write_text(
            json.dumps({"version": 1, "course": "TEST", "section": 1, "buildId": "earlier",
                        "places": published}), encoding="utf-8")


def rows_by_place(document) -> dict:
    found = {}
    if document is None:
        return found
    for row in document["pages"]:
        found[row["place"]] = row
    return found


class OfferRuleTests(unittest.TestCase):
    """class-planning.json -> datingPagesAClassBrings.fromTheLinksChecklist."""

    @classmethod
    def setUpClass(cls):
        cls.rule = _load("class-planning", "datingPagesAClassBrings", "fromTheLinksChecklist")

    def tearDown(self):
        build_site.forget_vault_sources()

    def offer_for(self, case: dict):
        with tempfile.TemporaryDirectory() as temporary:
            course_folder = Path(temporary) / "TEST"
            content_root = Path(temporary) / "content"
            lay_out(case, course_folder, content_root)
            said = []
            document = build_site._offer_the_links_checklist(
                content_root, course_folder, "TEST", 1, False, "this-build", printer=said.append)
            written = build_site._links_checklist_path(course_folder, 1)
            on_disk = json.loads(written.read_text(encoding="utf-8")) if written.exists() else None
            return document, on_disk, said

    def test_every_case_offers_what_the_contract_says(self):
        self.assertGreaterEqual(len(self.rule["cases"]), 12)
        for case in self.rule["cases"]:
            with self.subTest(case=case["name"]):
                document, on_disk, said = self.offer_for(case)
                if case.get("expectNoOffer"):
                    self.assertIsNone(document, "An offer was made with nothing to offer")
                    self.assertIsNone(on_disk, "A file was written with nothing to offer")
                    continue
                self.assertIsNotNone(on_disk, "No offer file was written")
                self.assertEqual(document, on_disk, "The file is not the offer")
                rows = rows_by_place(document)
                for place, expected in case.get("expect", {}).items():
                    self.assertIn(place, rows, f"“{place}” is not offered")
                    for key, value in expected.items():
                        self.assertEqual(rows[place][key], value,
                                         f"“{place}”: {key} is {rows[place][key]!r}, expected {value!r}")
                for place in case.get("expectAbsent", []):
                    self.assertNotIn(place, rows, f"“{place}” is offered and must not be")

    def test_the_offer_carries_the_build_and_the_marker_names_it(self):
        case = self.rule["cases"][0]
        document, on_disk, said = self.offer_for(case)
        self.assertEqual(on_disk["buildId"], "this-build")
        self.assertEqual(on_disk["course"], "TEST")
        self.assertEqual(on_disk["section"], 1)
        prefix = _load("shared-rules", "linksChecklist", "marker", "prefix")
        markers = [line for line in said if line.startswith(prefix)]
        self.assertEqual(len(markers), 1, f"Expected one marker line, got {said}")
        marker = json.loads(markers[0][len(prefix):])
        self.assertEqual(marker["buildId"], "this-build")
        self.assertEqual(marker["pages"], len(on_disk["pages"]))

    def test_every_row_carries_every_key_the_file_format_names(self):
        keys = _load("file-formats", "linksChecklistOffer", "rowKeys")
        for case in self.rule["cases"]:
            document, _, _ = self.offer_for(case)
            if document is None:
                continue
            for row in document["pages"]:
                self.assertEqual(sorted(row.keys()), sorted(keys.keys()), case["name"])
                self.assertIn(row["group"], _load("file-formats", "linksChecklistOffer", "groups"))
                self.assertIn(row["why"], _load("file-formats", "linksChecklistOffer", "whyValues"))


class OfferFileTests(unittest.TestCase):
    """shared-rules.json -> linksChecklist.buildCases: what the build does
    with the file, and what it never does to a page."""

    @classmethod
    def setUpClass(cls):
        cls.cases = _load("shared-rules", "linksChecklist", "buildCases")

    def tearDown(self):
        build_site.forget_vault_sources()

    def case_named(self, start: str) -> dict:
        for case in self.cases:
            if case["name"].startswith(start):
                return case
        self.fail(f"No build case starts “{start}”")

    def test_an_unattended_build_publishes_nothing(self):
        case = self.case_named("i.")
        with tempfile.TemporaryDirectory() as temporary:
            course_folder = Path(temporary) / "TEST"
            content_root = Path(temporary) / "content"
            lay_out(case, course_folder, content_root)
            before = {}
            for path in sorted(list(course_folder.rglob("*.md")) + list(content_root.rglob("*.md"))):
                before[path] = path.read_bytes()
            build_site._offer_the_links_checklist(content_root, course_folder, "TEST", 1, False,
                                                  "b1", printer=lambda line: None)
            self.assertTrue(build_site._links_checklist_path(course_folder, 1).exists(),
                            "The offer should have been written for this case to mean anything")
            for path, content in before.items():
                self.assertEqual(path.read_bytes(), content, f"{path.name} was changed by the build")

    def test_an_empty_offer_removes_the_file(self):
        case = self.case_named("ii.")
        with tempfile.TemporaryDirectory() as temporary:
            course_folder = Path(temporary) / "TEST"
            content_root = Path(temporary) / "content"
            lay_out(case, course_folder, content_root)
            path = build_site._links_checklist_path(course_folder, 1)
            build_site._offer_the_links_checklist(content_root, course_folder, "TEST", 1, False,
                                                  "b1", printer=lambda line: None)
            self.assertTrue(path.exists())
            # The teacher publishes the page in Obsidian; the next build.
            for fixed in case["thenPublished"]:
                for root in (course_folder, content_root):
                    for page in root.rglob(Path(fixed).name + ".md"):
                        page.write_text("Something to read.\n", encoding="utf-8")
            said = []
            build_site._offer_the_links_checklist(content_root, course_folder, "TEST", 1, False,
                                                  "b2", printer=said.append)
            self.assertFalse(path.exists(), "An empty offer left the old file behind")
            self.assertTrue(any('"pages": 0' in line for line in said), said)

    def test_a_course_kept_for_reference_gets_no_offer(self):
        case = self.case_named("iii.")
        with tempfile.TemporaryDirectory() as temporary:
            course_folder = Path(temporary) / "TEST"
            content_root = Path(temporary) / "content"
            lay_out(case, course_folder, content_root)
            path = build_site._links_checklist_path(course_folder, 1)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("{}", encoding="utf-8")
            build_site._offer_the_links_checklist(content_root, course_folder, "TEST", 1, True,
                                                  "b1", printer=lambda line: None)
            self.assertFalse(path.exists(), "A course kept for reference was given an offer")


class VisiblePlacesTests(unittest.TestCase):
    """The list a deploy records: the pages this build shows."""

    def tearDown(self):
        build_site.forget_vault_sources()

    def test_the_list_names_visible_pages_only_by_their_place(self):
        case = {"pages": [
            {"path": "section1/All Classes/Unit 1, Day 1", "created": "2026-09-08T07:00:00.000+0000",
             "links": ["Hidden"]},
            {"path": "Concepts/Shown", "visible": True},
            {"path": "Concepts/Hidden", "visible": False},
        ]}
        with tempfile.TemporaryDirectory() as temporary:
            course_folder = Path(temporary) / "TEST"
            content_root = Path(temporary) / "content"
            lay_out(case, course_folder, content_root)
            places = build_site._visible_places(content_root)
            self.assertIn("Concepts/Shown", places)
            self.assertIn("section1/All Classes/Unit 1, Day 1", places)
            self.assertNotIn("Concepts/Hidden", places)


if __name__ == "__main__":
    unittest.main()
