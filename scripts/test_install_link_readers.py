#!/usr/bin/env python3
"""
The installer's and the coverage map's link readers, against the CONTRACT.

`contracts/shared-rules.json` -> `readingALink` says what a wikilink NAMES,
the escaped pipe `[[Page\\|words]]` (how Obsidian writes an alias inside a
table) and a heading followed by an alias `[[Page#Heading|words]]` included.
#294 brought the build's dating walk and both apps into line with it; #314
brings the other five Python readers:

- `setup_course.first_use_dates` — which class's date a payload page takes;
- `setup_course.retargeted_expectation_references` (`WIKI_LINK_TARGET`) —
  pointing a skeleton's placeholder expectation at the payload's own;
- `setup_course.unlink_curriculum_references` — turning links to curriculum
  pages into plain words when a teacher declines the curriculum pages
  (and, #326, comparing by the page a link names, not the whole path);
- `build_site.BLOCK_LINK` via `_pages_the_course_teaches` — which pages the
  course teaches;
- `build_site.TRANSCLUSION` via `_coverage_counts` — what the coverage map
  counts.

Every `readingALink` case is run through every reader (not retyped here), and
each reader has its own fixture on top. Stdlib only and no Docker, so
Windows' `PythonToolchainTests` discovers and runs it too.
"""
import json
import re
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

import build_site
import contracts
import markdown_code
import setup_course
import toolchain_paths

REPO = Path(__file__).resolve().parent.parent


def link_cases():
    """readingALink.cases, from this checkout's contract (or the image's)."""
    repo_contracts = REPO / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    cases = contracts.load("shared-rules")["readingALink"]["cases"]
    assert len(cases) >= 37, "readingALink lost cases"
    return cases


def page_name(name: str) -> str:
    """The page a name refers to: its last path component."""
    return name.split("/")[-1].strip()


REFERENCE = datetime(2026, 9, 1)


class FirstUseDatesTests(unittest.TestCase):
    """A payload page takes the date of the first class that links to it."""

    def payload_with_class(self, root: Path, ordinal: int, body: str) -> Path:
        payload = root / "payload"
        classes = payload / "per_section" / "All Classes"
        classes.mkdir(parents=True)
        (classes / f"Unit 1, Day {ordinal}.md").write_text(
            f"---\ncreated: __CREATED_CLASS_{ordinal}__\n---\n\n{body}", encoding="utf-8")
        return payload

    def test_a_table_link_with_an_escaped_pipe_takes_its_class_date(self):
        with tempfile.TemporaryDirectory() as temp:
            payload = self.payload_with_class(
                Path(temp), 3, "| Task | Notes |\n|---|---|\n| [[Worksheet\\|w]] | due |\n")
            dates = setup_course.first_use_dates(payload, REFERENCE)
        self.assertIn("Worksheet", dates, f"the class's link was not read: {sorted(dates)}")
        self.assertEqual(dates["Worksheet"], setup_course.semester_class_timestamp(3, REFERENCE))
        for key in dates:
            self.assertFalse(key.endswith("\\"), f"{key!r} kept the backslash")

    def test_every_link_shape_reads_as_the_contract_says(self):
        for case in link_cases():
            with self.subTest(case=case["name"]):
                with tempfile.TemporaryDirectory() as temp:
                    payload = self.payload_with_class(Path(temp), 1, case["text"])
                    dates = setup_course.first_use_dates(payload, REFERENCE)
                expected = set()
                for name in case["expect"]:
                    expected.add(page_name(name))
                self.assertEqual(set(dates), expected)


class RetargetTests(unittest.TestCase):
    """A skeleton's placeholder expectation, pointed at the payload's own."""

    RENAMES = {"A1.1": "B1.1"}

    def test_each_shape_changes_the_name_and_nothing_else(self):
        shapes = {
            "| [[A1.1\\|the expectation]] |": "| [[B1.1\\|the expectation]] |",
            "| ![[A1.1\\|300]] |": "| ![[B1.1\\|300]] |",
            "| [[Curriculum/A1.1\\|x]] |": "| [[Curriculum/B1.1\\|x]] |",
            "| [[A1.1#Examples\\|x]] |": "| [[B1.1#Examples\\|x]] |",
            "See [[A1.1#Examples|x]].": "See [[B1.1#Examples|x]].",
            "![[A1.1]]": "![[B1.1]]",
            "[[A1.10|not this one]]": "[[A1.10|not this one]]",
        }
        for written, expected in shapes.items():
            with self.subTest(written=written):
                self.assertEqual(
                    setup_course.retargeted_expectation_references(written, self.RENAMES),
                    expected)

    def test_every_link_shape_reads_as_the_contract_says(self):
        # Renaming each name the case expects changes exactly that link, and
        # keeps the backslash where it was (readingALink.whenRewritten).
        for case in link_cases():
            for name in case["expect"]:
                target = page_name(name)
                with self.subTest(case=case["name"], name=target):
                    renamed = setup_course.retargeted_expectation_references(
                        case["text"], {target: "RENAMED"})
                    self.assertNotEqual(renamed, case["text"], f"{target!r} was not read")
                    self.assertEqual(renamed.count("\\"), case["text"].count("\\"),
                                     "a backslash was dropped or added")
                    self.assertEqual(renamed.replace("RENAMED", target), case["text"])


class UnlinkTests(unittest.TestCase):
    """Curriculum declined: links to curriculum pages become their words."""

    def unlink(self, text: str, names: set) -> str:
        return setup_course.unlink_curriculum_references(text, names)

    def test_a_table_link_becomes_its_words_and_the_cell_stays_one_cell(self):
        self.assertEqual(self.unlink("| a | [[A1.1\\|the words]] |", {"A1.1"}),
                         "| a | the words |")
        self.assertEqual(self.unlink("| [[A1.1#Examples\\|see]] |", {"A1.1"}), "| see |")

    def test_an_embed_with_an_escaped_size_takes_its_line_with_it(self):
        self.assertEqual(self.unlink("before\n![[A1.1\\|300]]\nafter", {"A1.1"}),
                         "before\nafter")

    def test_a_link_written_by_folder_is_unlinked_by_the_page_it_names(self):
        # #326: compared by the last path component, not the whole path.
        self.assertEqual(self.unlink("See [[Curriculum/A1.1|the words]].", {"A1.1"}),
                         "See the words.")
        self.assertEqual(self.unlink("| [[Curriculum/A1.1\\|words]] |", {"A1.1"}), "| words |")
        self.assertEqual(self.unlink("See [[Curriculum/A1.1]].", {"A1.1"}), "See A1.1.")
        self.assertEqual(self.unlink("![[Curriculum/A1.1]]", {"A1.1"}), "")
        self.assertEqual(self.unlink("See [[Concepts/Other|words]].", {"A1.1"}),
                         "See [[Concepts/Other|words]].")

    def test_every_link_shape_reads_as_the_contract_says(self):
        # With every name the case expects declared a curriculum page, no
        # link is left outside code, and every stretch of code is left
        # exactly as written (#313: an example of a link is not a link);
        # with none of them, the text is untouched.
        link = re.compile(r"!?\[\[")
        for case in link_cases():
            with self.subTest(case=case["name"]):
                names = set()
                for name in case["expect"]:
                    names.add(page_name(name))
                unlinked = self.unlink(case["text"], names)
                self.assertEqual(markdown_code.matches_outside_code(link, unlinked), [])
                outside = ""
                carried_to = 0
                for start, end in markdown_code.code_ranges(unlinked):
                    outside += unlinked[carried_to:start]
                    carried_to = end
                outside += unlinked[carried_to:]
                self.assertNotIn("\\|", outside, "an escaped pipe's backslash was left behind")
                # And no other backslash is lost or left: outside code, the
                # unlink removes exactly the escaped pipes of the links it
                # unlinks.
                before = 0
                carried_to = 0
                for start, end in markdown_code.code_ranges(case["text"]):
                    before += case["text"][carried_to:start].count("\\")
                    carried_to = end
                before += case["text"][carried_to:].count("\\")
                escaped_pipes = 0
                for match in markdown_code.matches_outside_code(
                        re.compile(r"!?\[\[[^\]]*\]\]"), case["text"]):
                    escaped_pipes += match.group(0).count("\\|")
                self.assertEqual(outside.count("\\"), before - escaped_pipes)
                for start, end in markdown_code.code_ranges(case["text"]):
                    self.assertIn(case["text"][start:end], unlinked, "code was rewritten")
                self.assertEqual(self.unlink(case["text"], {"Nothing Here"}), case["text"])

    def test_mcmpr11s_assessment_matrix_keeps_its_words_and_loses_its_dead_links(self):
        # The teacher-visible case: MCMPR11's Final Evaluation table carries
        # seven [[K1.15\|test cases]]-style links to British Columbia
        # standards outside any curriculum block. Declining the curriculum
        # pages left all seven pointing at pages that do not exist.
        payload = REPO / "support" / "example_content" / "MCMPR11"
        manifest = json.loads((payload / "manifest.json").read_text(encoding="utf-8"))
        names = setup_course.curriculum_page_names(payload, manifest)
        source = (payload / "shared" / "Tasks" /
                  "Final Evaluation - Software Portfolio and Technical Challenge.md")
        link = re.compile(r"\[\[([^\]|#\\]+)")

        def curriculum_links(text):
            found = []
            for match in link.finditer(text):
                if page_name(match.group(1)) in names:
                    found.append(match.group(1))
            return found

        written = setup_course.strip_curriculum_blocks(
            source.read_text(encoding="utf-8"), keep_content=False)
        self.assertEqual(len(curriculum_links(written)), 7,
                         "the fixture changed: the table no longer carries seven links")
        with tempfile.TemporaryDirectory() as temp:
            destination = Path(temp) / source.name
            self.assertTrue(setup_course.install_payload_file(
                source, destination, "2026-09-08T07:00:00.000+0000",
                include_curriculum=False, page_names=names))
            installed = destination.read_text(encoding="utf-8")
        self.assertEqual(curriculum_links(installed), [])
        self.assertIn("| [[", written)
        self.assertIn("test cases and defensive rewriting", installed)
        self.assertIn("control structures and loops, translating a spec into source code",
                      installed)
        for line in installed.split("\n"):
            if line.startswith("| **Part"):
                self.assertEqual(line.count("|"), 4, f"a cell was split: {line}")


class PagesTheCourseTeachesTests(unittest.TestCase):
    """What a class page links to is taught (build_site.BLOCK_LINK)."""

    def taught(self, class_body: str) -> set:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "All Classes").mkdir()
            (root / "All Classes" / "Unit 1, Day 1.md").write_text(class_body, encoding="utf-8")
            (root / "Worksheet.md").write_text("# Worksheet\n", encoding="utf-8")
            return build_site._pages_the_course_teaches(root, ["All Classes"])

    def test_a_heading_and_an_alias_are_a_link_to_the_page(self):
        self.assertIn("Worksheet", self.taught("| [[Worksheet#Part A\\|a]] |\n"))
        self.assertIn("Worksheet", self.taught("See [[Worksheet#Part A|part A]].\n"))

    def test_a_stray_double_bracket_does_not_swallow_the_next_link(self):
        # Tutorials/Scavenger Hunt.md, in the example course and every
        # skeleton family: inline code showing `[[`, a heading further on,
        # then a real link. A heading group that may cross '[' reads all of
        # it as one garbage link and loses the real one.
        body = ("Type `[[` then a name.\n\n### Custom Display Words\n\n"
                "Come to [[Worksheet|the worksheet]].\n")
        self.assertIn("Worksheet", self.taught(body))

    def test_every_link_shape_reads_as_the_contract_says(self):
        for case in link_cases():
            with self.subTest(case=case["name"]):
                expected = {"Unit 1, Day 1"}
                for name in case["expect"]:
                    expected.add(page_name(name))
                self.assertEqual(self.taught(case["text"]), expected)


class DatingWalkStrayBracketTests(unittest.TestCase):
    """#294's reader (build_site._extract_wikilink_targets), same heading stop."""

    def test_a_stray_double_bracket_in_prose_does_not_swallow_the_next_link(self):
        # This reader skips inline code (#313), so the Scavenger Hunt shape
        # cannot reach it, but a "[[" typed in a sentence can. The heading stops at
        # '[' here too (#314), as Quartz's own wikilinkRegex does.
        text = "I typed [[ by mistake.\n\n## Next\n\nSee [[Worksheet|the worksheet]].\n"
        self.assertIn("worksheet", build_site._extract_wikilink_targets(text))


class CoverageCountsTests(unittest.TestCase):
    """What the coverage map counts (build_site.TRANSCLUSION)."""

    def covered(self, taught_page_body: str, codes: list) -> dict:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            curriculum = root / "Curriculum"
            curriculum.mkdir()
            for code in codes:
                (curriculum / f"{code}.md").write_text(f"# {code}\n", encoding="utf-8")
            (root / "All Classes").mkdir()
            (root / "All Classes" / "Unit 1, Day 1.md").write_text(
                "Today: [[Lesson]]\n", encoding="utf-8")
            (root / "Lesson.md").write_text(taught_page_body, encoding="utf-8")
            specific = {}
            for code in codes:
                specific[code] = code
            covered_by, _ = build_site._coverage_counts(
                root, curriculum, specific, ["All Classes"], ["Tasks"], True)
            counts = {}
            for code in codes:
                counts[code] = len(covered_by[code])
            return counts

    def test_an_embed_with_a_heading_and_an_alias_counts(self):
        self.assertEqual(self.covered("![[A1.1#Examples|see]]\n", ["A1.1"]), {"A1.1": 1})
        self.assertEqual(self.covered("| ![[A1.1#Examples\\|see]] |\n", ["A1.1"]), {"A1.1": 1})

    def test_a_plain_link_does_not_count(self):
        # Unchanged: prose naming an expectation is not a claim to cover it.
        self.assertEqual(self.covered("[[A1.1#Examples|see]]\n", ["A1.1"]), {"A1.1": 0})

    def test_every_link_shape_reads_as_the_contract_says(self):
        # Each case's text made into embeds: every name it expects counts once.
        for case in link_cases():
            with self.subTest(case=case["name"]):
                embedded = case["text"].replace("![[", "[[").replace("[[", "![[")
                codes = []
                for name in case["expect"]:
                    codes.append(page_name(name))
                counts = self.covered(embedded, codes)
                for code in codes:
                    self.assertEqual(counts[code], 1, f"{code!r} not counted")


if __name__ == "__main__":
    unittest.main()
