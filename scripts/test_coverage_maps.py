#!/usr/bin/env python3
"""
The curriculum coverage maps (#128): one per declared curriculum folder, and an
expectation-code rule that admits the College Board's `1.A`.

The FIRST test of the coverage map there has ever been — before #128 nothing in
scripts/, the mac suite or verify.sh called `build_curriculum_coverage`, which
is how the build came to disagree with the contract about `b2.3` without
anybody noticing.

The rule cases are deserialised from `contracts/shared-rules.json`
(`curriculumRules.isExpectationCode`, `curriculumRules.coveragePageTitles`,
`specialNames.curriculumFoldersResolution`), the lists both apps run too. The
single-map output is held to goldens captured from origin/dev BEFORE the
change: a course with one map gets exactly the page it always had.

Pure Python, temporary folders, no Docker: verify.sh runs it on the mac host
and Windows' PythonToolchainTests discovers it.
"""
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import build_site  # noqa: E402
import contracts  # noqa: E402
import toolchain_paths  # noqa: E402


def use_the_repository_contracts():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


# === Fixtures (the goldens were captured over exactly these) =================

ONTARIO_PAGES = {
    "A1.1": "Explain the first idea.",
    "A1.2": "Explain the second idea.",
    "A2.1": "Use a tool safely.",
    "B1.1": "Describe a system.",
    "A1. Understanding": "Overall expectation A1.",
    "A2. Tools": "Overall expectation A2.",
    "B1. Systems": "Overall expectation B1.",
}

BACKLINKS_SAMPLE = """export default (() => {
  function Backlinks() {
    // CQ4T-STRUCTURAL-ANCHOR: do not remove; build_site.py rewrites this line
    const structural = new Set<string>([""])
    return null
  }
})
"""

STAMP = "2026-09-03T08:45:00.000-0400"


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_ontario_course(content_root: Path, folder: str, second_folder: str = None):
    for stem, text in ONTARIO_PAGES.items():
        write(content_root / folder / f"{stem}.md", f"---\ntitle: {stem}\n---\n{text}\n")
    codes = [stem for stem in ONTARIO_PAGES if "." in stem and " " not in stem]
    write(content_root / folder / "index.md",
          "---\ntitle: Expectations\n---\n" + "\n".join(f"![[{code}]]" for code in codes) + "\n")
    write(content_root / "All Classes" / "Unit 1, Day 1.md",
          "---\ntitle: Unit 1, Day 1\n---\n## Curriculum connection\n![[A1.1]]\n\nToday: [[Quiz]]\n")
    write(content_root / "Tasks" / "Quiz.md",
          "---\ntitle: Quiz\n---\n## Curriculum connection\n![[A2.1]]\n")
    bullets = [f"- [[{folder}/index|Curriculum expectations]]"]
    if second_folder:
        (content_root / second_folder).mkdir(parents=True, exist_ok=True)
        bullets.append(f"- [[{second_folder}/index|{second_folder}]]")
    bullets.append("- [[Course Outline]]")
    write(content_root / "Key Links.md", "---\ntitle: Key Links\n---\n" + "\n".join(bullets) + "\n")


def build(content_root: Path, configured: list, printer=None):
    """The coverage part of a build, the way build_section_site runs it."""
    output = io.StringIO()
    with redirect_stdout(output):
        maps = build_site.build_curriculum_coverage(
            content_root, "ICS3U", class_folders=["All Classes"],
            graded_folders=["Tasks"], graded_was_configured=True,
            configured_folders=configured, include_notes=True,
            first_class_stamp=STAMP)
        build_site.link_coverage_from_key_links(content_root, maps)
    return maps, output.getvalue()


# Captured from origin/dev ff1213ed7b80c001310a13b45136518d14af2e38, BEFORE any #128 edit, by
# running that commit's build_curriculum_coverage / link_coverage_from_key_links (twice) /
# set_backlinks_structural_pages / names_the_sidebar_hides(["Private"]) over the two fixtures
# below. Never re-capture these after editing the build: a golden taken from the code it
# checks proves nothing (plan risk 6).
GOLDEN = {
    'single': {
        'page': '---\ntitle: Curriculum Coverage\npublish: true\ncreated: 2026-09-03T08:45:00.000-0400\nenableToc: true\n---\nEvery expectation in ICS3U, coloured by how many pages address it.\nThe map is built from this site\'s own links each time the site is built, so\nit cannot drift from the course.\n\n<div class="coverage-panel">\n<div class="coverage-map"><div class="coverage-strand"><div class="coverage-letter">A</div><div class="coverage-chips"><a class="internal coverage-chip coverage-chip-no" href="Curriculum/A1.-Understanding">A1</a><a class="internal coverage-chip coverage-chip-yes" href="Curriculum/A2.-Tools">A2</a></div><a class="internal coverage-cell coverage-1" href="Curriculum/A1.1" aria-label="A1.1, addressed once"><span class="coverage-code">A1.1</span></a><a class="internal coverage-cell coverage-0" href="Curriculum/A1.2" aria-label="A1.2, not yet addressed"><span class="coverage-code">A1.2</span></a><a class="internal coverage-cell coverage-1" href="Curriculum/A2.1" data-assessed="true" aria-label="A2.1, addressed once, included in assessed work"><span class="coverage-code">A2.1</span></a></div><div class="coverage-strand"><div class="coverage-letter">B</div><div class="coverage-chips"><a class="internal coverage-chip coverage-chip-no" href="Curriculum/B1.-Systems">B1</a></div><a class="internal coverage-cell coverage-0" href="Curriculum/B1.1" aria-label="B1.1, not yet addressed"><span class="coverage-code">B1.1</span></a></div></div>\n<hr class="coverage-rule">\n<div class="coverage-legend">\n<div class="coverage-legend-row"><span class="coverage-key coverage-0"></span><span class="coverage-legend-label">Not yet addressed</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-1"></span><span class="coverage-legend-label">Addressed once</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-2"></span><span class="coverage-legend-label">Addressed twice</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-3"></span><span class="coverage-legend-label">Addressed three times</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-4"></span><span class="coverage-legend-label">Addressed four or more times</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-2" data-assessed="true"></span><span class="coverage-legend-label">Included in assessed work — the cell carries a ring</span></div>\n</div>\n</div>\n\nHover any cell to preview the expectation. The row of small chips under\neach strand letter is that strand\'s overall expectations: green when\nassessed work addresses them, red when nothing marked does.\n\n## Where this course stands\n\n| | |\n| --- | --- |\n| Specific expectations | 4 |\n| Not yet addressed | 2 |\n| Addressed by exactly one page | 2 |\n| Overall expectations with no assessed work | 2 |\n\n## What counts\n\nA page addresses an expectation when it **transcludes** it — when the\nexpectation\'s own wording appears on the page, under a *Curriculum\nconnection* heading. That is the deliberate form.\n\nA passing mention in prose does not count. A concept page can discuss an\nidea, and even link to the expectation behind it in a sentence, without\nclaiming to have addressed it — which is why the number here is usually\nlower than the backlinks count on the expectation\'s own page, and why it\nmeans more. If a page genuinely covers an expectation, put it in that\npage\'s *Curriculum connection* rather than leaving it as a mention.\n\n**Only pages this course teaches count.** The page carrying the\nconnection has to be reachable from a class page — linked from one\ndirectly, or from a page a class page links to. A page written in August\nand never put into a class has addressed nothing yet, and a page reached\nonly from Key Links is a reference, not a lesson.\n\n**Only published pages count.** A page marked `publish: false` is not on\nthe site yet, so it cannot have addressed anything — next week\'s lesson,\nwritten early, leaves the map exactly where it was until the day it is\npublished.\n\nAn expectation counts as **assessed** when one of those pages is in a\nfolder that counts for marks — **Tasks** for this course, which you\ncan change in Settings. Ontario asks that every overall expectation be\nevaluated for marks at least once; the chips under each strand letter\nanswer that, and the ring on a cell shows which specific expectations carry\nassessed work.\n\n## Reading it honestly\n\nRed is not failure — in September everything is red, and that is what the\nfirst months of a course look like. What matters is the direction of\ntravel, and whether anything is still red in May.\n\nA strand of red in the skills strand usually means something different:\nthose expectations are being met in every investigation without being\ncited by code. If that is the case here, it is worth citing a few of them\nwhere they genuinely apply rather than leaving the record silent.\n',
        'keyLinks': '---\ntitle: Key Links\n---\n- [[Curriculum/index|Curriculum expectations]]\n- [[Curriculum Coverage]]\n- [[Course Outline]]\n',
        'backlinks': 'export default (() => {\n  function Backlinks() {\n    // CQ4T-STRUCTURAL-ANCHOR: do not remove; build_site.py rewrites this line\n    const structural = new Set<string>(["Curriculum Coverage", "Curriculum-Coverage", "Curriculum", "Curriculum"])\n    return null\n  }\n})\n',
        'sidebar': ['Private', 'Media', 'Curriculum Coverage.md'],
    },
    'lcs': {
        'page': '---\ntitle: Curriculum Coverage\npublish: true\ncreated: 2026-09-03T08:45:00.000-0400\nenableToc: true\n---\nEvery expectation in ICS3U, coloured by how many pages address it.\nThe map is built from this site\'s own links each time the site is built, so\nit cannot drift from the course.\n\n<div class="coverage-panel">\n<div class="coverage-map"><div class="coverage-strand"><div class="coverage-letter">A</div><div class="coverage-chips"><a class="internal coverage-chip coverage-chip-no" href="Ontario-Curriculum/A1.-Understanding">A1</a><a class="internal coverage-chip coverage-chip-yes" href="Ontario-Curriculum/A2.-Tools">A2</a></div><a class="internal coverage-cell coverage-1" href="Ontario-Curriculum/A1.1" aria-label="A1.1, addressed once"><span class="coverage-code">A1.1</span></a><a class="internal coverage-cell coverage-0" href="Ontario-Curriculum/A1.2" aria-label="A1.2, not yet addressed"><span class="coverage-code">A1.2</span></a><a class="internal coverage-cell coverage-1" href="Ontario-Curriculum/A2.1" data-assessed="true" aria-label="A2.1, addressed once, included in assessed work"><span class="coverage-code">A2.1</span></a></div><div class="coverage-strand"><div class="coverage-letter">B</div><div class="coverage-chips"><a class="internal coverage-chip coverage-chip-no" href="Ontario-Curriculum/B1.-Systems">B1</a></div><a class="internal coverage-cell coverage-0" href="Ontario-Curriculum/B1.1" aria-label="B1.1, not yet addressed"><span class="coverage-code">B1.1</span></a></div></div>\n<hr class="coverage-rule">\n<div class="coverage-legend">\n<div class="coverage-legend-row"><span class="coverage-key coverage-0"></span><span class="coverage-legend-label">Not yet addressed</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-1"></span><span class="coverage-legend-label">Addressed once</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-2"></span><span class="coverage-legend-label">Addressed twice</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-3"></span><span class="coverage-legend-label">Addressed three times</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-4"></span><span class="coverage-legend-label">Addressed four or more times</span></div>\n<div class="coverage-legend-row"><span class="coverage-key coverage-2" data-assessed="true"></span><span class="coverage-legend-label">Included in assessed work — the cell carries a ring</span></div>\n</div>\n</div>\n\nHover any cell to preview the expectation. The row of small chips under\neach strand letter is that strand\'s overall expectations: green when\nassessed work addresses them, red when nothing marked does.\n\n## Where this course stands\n\n| | |\n| --- | --- |\n| Specific expectations | 4 |\n| Not yet addressed | 2 |\n| Addressed by exactly one page | 2 |\n| Overall expectations with no assessed work | 2 |\n\n## What counts\n\nA page addresses an expectation when it **transcludes** it — when the\nexpectation\'s own wording appears on the page, under a *Curriculum\nconnection* heading. That is the deliberate form.\n\nA passing mention in prose does not count. A concept page can discuss an\nidea, and even link to the expectation behind it in a sentence, without\nclaiming to have addressed it — which is why the number here is usually\nlower than the backlinks count on the expectation\'s own page, and why it\nmeans more. If a page genuinely covers an expectation, put it in that\npage\'s *Curriculum connection* rather than leaving it as a mention.\n\n**Only pages this course teaches count.** The page carrying the\nconnection has to be reachable from a class page — linked from one\ndirectly, or from a page a class page links to. A page written in August\nand never put into a class has addressed nothing yet, and a page reached\nonly from Key Links is a reference, not a lesson.\n\n**Only published pages count.** A page marked `publish: false` is not on\nthe site yet, so it cannot have addressed anything — next week\'s lesson,\nwritten early, leaves the map exactly where it was until the day it is\npublished.\n\nAn expectation counts as **assessed** when one of those pages is in a\nfolder that counts for marks — **Tasks** for this course, which you\ncan change in Settings. Ontario asks that every overall expectation be\nevaluated for marks at least once; the chips under each strand letter\nanswer that, and the ring on a cell shows which specific expectations carry\nassessed work.\n\n## Reading it honestly\n\nRed is not failure — in September everything is red, and that is what the\nfirst months of a course look like. What matters is the direction of\ntravel, and whether anything is still red in May.\n\nA strand of red in the skills strand usually means something different:\nthose expectations are being met in every investigation without being\ncited by code. If that is the case here, it is worth citing a few of them\nwhere they genuinely apply rather than leaving the record silent.\n',
        'keyLinks': '---\ntitle: Key Links\n---\n- [[Ontario Curriculum/index|Curriculum expectations]]\n- [[Curriculum Coverage]]\n- [[College Board Curriculum/index|College Board Curriculum]]\n- [[Course Outline]]\n',
        'backlinks': 'export default (() => {\n  function Backlinks() {\n    // CQ4T-STRUCTURAL-ANCHOR: do not remove; build_site.py rewrites this line\n    const structural = new Set<string>(["Curriculum Coverage", "Curriculum-Coverage", "Ontario Curriculum", "Ontario-Curriculum"])\n    return null\n  }\n})\n',
        'sidebar': ['Private', 'Media', 'Curriculum Coverage.md'],
    },
}


class TheCodeRule(unittest.TestCase):
    """T1: `curriculumRules.isExpectationCode` against the build."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contracts()
        cls.cases = contracts.section("shared-rules", "curriculumRules", "isExpectationCode", "cases")

    def test_there_are_cases(self):
        self.assertGreaterEqual(len(self.cases), 20)

    def test_every_case(self):
        for case in self.cases:
            with self.subTest(code=case["code"]):
                self.assertEqual(build_site.is_expectation_code(case["code"]), case["expect"])

    def test_a_trailing_newline_is_not_a_code(self):
        self.assertFalse(build_site.is_expectation_code("A1.1\n"))
        self.assertFalse(build_site.is_expectation_code("1.A\n"))

    def test_the_sort_key_orders_both_shapes(self):
        codes = ["12.A", "B1.1", "1.b", "A10.1", "1.A", "a2.1", "2.C"]
        self.assertEqual(sorted(codes, key=build_site.code_sort_key),
                         ["a2.1", "A10.1", "B1.1", "1.A", "1.b", "2.C", "12.A"])
        self.assertEqual(build_site.strand_of("b2.3"), "B")
        self.assertEqual(build_site.strand_of("12.A"), "12")
        self.assertEqual(build_site.overall_of("b2.3"), "B2")
        self.assertIsNone(build_site.overall_of("1.A"))


class TheTitles(unittest.TestCase):
    """T2: `curriculumRules.coveragePageTitles`."""

    def test_every_case(self):
        use_the_repository_contracts()
        cases = contracts.section("shared-rules", "curriculumRules", "coveragePageTitles", "cases")
        self.assertGreaterEqual(len(cases), 6)
        for case in cases:
            with self.subTest(folders=case["folders"]):
                self.assertEqual(build_site.coverage_page_titles(case["folders"], case["primary"]),
                                 case["titles"])


class WhichFolders(unittest.TestCase):
    """T3: `specialNames.curriculumFoldersResolution` — `mapped` and `titles`
    against the build, over real folders; a folder in `withPages` holds one
    expectation page (nested, so the walk has to recurse to find it)."""

    def test_every_case(self):
        use_the_repository_contracts()
        cases = contracts.section("shared-rules", "specialNames", "curriculumFoldersResolution", "cases")
        self.assertGreaterEqual(len(cases), 12)
        for case in cases:
            with self.subTest(case=case["name"]), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                for name in case["folders"]:
                    (root / name).mkdir()
                    write(root / name / "index.md", "x")
                for name in case["withPages"]:
                    write(root / name / "Unit 1" / "A1.1.md", "x")
                config = {"curriculum_folders": case["curriculumFolders"],
                          "curriculum_folder": case["curriculumFolder"]}
                configured = build_site.configured_curriculum_folders(config)
                plan = build_site.plan_coverage_maps(root, configured)
                self.assertEqual([folder.name for folder, _ in plan], case["mapped"])
                self.assertEqual([title for _, title in plan], case["titles"])


class TwoMaps(unittest.TestCase):
    """T4: a course with an Ontario and a nested College Board folder."""

    def make(self, root: Path):
        make_ontario_course(root, "Ontario Curriculum", "College Board Curriculum")
        board = root / "College Board Curriculum"
        write(board / "Unit 1" / "1.A.md", "---\ntitle: 1.A\n---\nInvestigate.\n")
        write(board / "Unit 1" / "1.B.md", "---\ntitle: 1.B\n---\nDesign.\n")
        # A College Board page that cross-references an Ontario expectation:
        # curriculum material, not a lesson — it must not count for A1.2.
        write(board / "Unit 1" / "Notes.md", "---\ntitle: Notes\n---\n![[A1.2]]\n")
        write(board / "index.md", "---\ntitle: CB\n---\n![[1.A]]\n![[1.B]]\n")
        write(root / "All Classes" / "Unit 1, Day 2.md",
              "---\ntitle: Unit 1, Day 2\n---\n![[1.A]]\n\n[[Project]]\n[[Notes]]\n")
        write(root / "Tasks" / "Project.md", "---\ntitle: Project\n---\n![[1.B]]\n")

    def test_two_maps(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make(root)
            configured = ["Ontario Curriculum", "College Board Curriculum"]
            maps, console = build(root, configured)
            self.assertEqual([item["title"] for item in maps],
                             ["Curriculum Coverage", "College Board Curriculum Coverage"])
            self.assertEqual([item["folder"] for item in maps],
                             ["Ontario Curriculum", "College Board Curriculum"])
            self.assertEqual([item["expectations"] for item in maps], [4, 2])

            ontario = (root / "Curriculum Coverage.md").read_text(encoding="utf-8")
            board = (root / "College Board Curriculum Coverage.md").read_text(encoding="utf-8")
            self.assertIn('aria-label="A1.1, addressed once"', ontario)
            self.assertIn('aria-label="A1.2, not yet addressed"', ontario,
                          "a College Board page's cross-reference counted as Ontario coverage")
            self.assertIn('aria-label="1.A, addressed once"', board)
            self.assertIn('aria-label="1.B, addressed once, included in assessed work"', board)
            self.assertIn('href="College-Board-Curriculum/Unit-1/1.A"', board)
            self.assertIn('title: "College Board Curriculum Coverage"', board)
            self.assertIn("Every expectation in College Board Curriculum for ICS3U", board)
            self.assertIn("Every expectation in Ontario Curriculum for ICS3U", ontario)
            self.assertNotIn("coverage-chips", board)
            self.assertNotIn("Overall expectations with no assessed work", board)
            self.assertNotIn("chips under each strand letter", board)
            self.assertIn("Overall expectations with no assessed work", ontario)
            self.assertIn("🗺️  College Board Curriculum Coverage (College Board Curriculum): 2 expectations", console)

            key_links = (root / "Key Links.md").read_text(encoding="utf-8").split("\n")
            ontario_bullet = key_links.index("- [[Ontario Curriculum/index|Curriculum expectations]]")
            self.assertEqual(key_links[ontario_bullet + 1], "- [[Curriculum Coverage]]")
            board_bullet = key_links.index("- [[College Board Curriculum/index|College Board Curriculum]]")
            self.assertEqual(key_links[board_bullet + 1], "- [[College Board Curriculum Coverage]]")
            before = "\n".join(key_links)
            build_site.link_coverage_from_key_links(root, maps)
            self.assertEqual((root / "Key Links.md").read_text(encoding="utf-8"), before,
                             "a second pass added the maps to Key Links again")

            hidden = build_site.names_the_sidebar_hides(["Private"], [item["title"] for item in maps])
            self.assertIn("Curriculum Coverage.md", hidden)
            self.assertIn("College Board Curriculum Coverage.md", hidden)

            backlinks = root / "Backlinks.tsx"
            backlinks.write_text(BACKLINKS_SAMPLE, encoding="utf-8")
            with redirect_stdout(io.StringIO()):
                build_site.set_backlinks_structural_pages(
                    backlinks, root, build_site.plan_coverage_maps(root, configured))
            text = backlinks.read_text(encoding="utf-8")
            for name in ("Curriculum-Coverage", "College-Board-Curriculum-Coverage",
                         "Ontario-Curriculum", "College-Board-Curriculum"):
                self.assertIn(f'"{name}"', text)

            # A map is never a lesson, whatever it is called.
            self.assertFalse(build_site._is_class_page(Path("College Board Curriculum Coverage.md")))

    def test_the_marker(self):
        use_the_repository_contracts()
        lines = []
        build_site.announce_coverage_maps(
            [{"title": "Curriculum Coverage", "folder": "Ontario Curriculum", "expectations": 4}],
            "ICS3U", 1, printer=lines.append)
        build_site.announce_coverage_maps([], "ICS3U", 2, printer=lines.append)
        prefix = contracts.section("shared-rules", "coverageMapsBuilt", "marker", "prefix")
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertTrue(line.startswith(prefix + " "))
        first = json.loads(lines[0][len(prefix):])
        self.assertEqual(first, {"course": "ICS3U", "section": 1, "maps": [
            {"title": "Curriculum Coverage", "folder": "Ontario Curriculum", "expectations": 4}]})
        self.assertEqual(json.loads(lines[1][len(prefix):])["maps"], [])
        # The contract's own examples are what this function prints.
        for example in contracts.section("shared-rules", "coverageMapsBuilt", "marker", "examples"):
            payload = json.loads(example[len(prefix):])
            printed = []
            build_site.announce_coverage_maps(payload["maps"], payload["course"], payload["section"],
                                              printer=printed.append)
            self.assertEqual(printed, [example])

    def test_a_declared_second_folder_without_pages_renames_nothing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            make_ontario_course(root, "Ontario Curriculum", "College Board Curriculum")
            maps, _ = build(root, ["Ontario Curriculum", "College Board Curriculum"])
            self.assertEqual([item["title"] for item in maps], ["Curriculum Coverage"])

    def test_an_undeclared_second_folder_gets_no_map(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make(root)
            maps, _ = build(root, [])
            self.assertEqual([item["folder"] for item in maps], ["College Board Curriculum"],
                             "the scan is a fallback: one folder, the alphabetically first with pages")
            maps, _ = build(root, ["Ontario Curriculum"])
            self.assertEqual([item["folder"] for item in maps], ["Ontario Curriculum"])


class OneMapIsUnchanged(unittest.TestCase):
    """T5: byte for byte what origin/dev wrote, for a Curriculum/ course and for
    the LCS default (Ontario with pages, College Board empty, nothing declared)."""

    def run_fixture(self, folder, second, configured):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "content"
            make_ontario_course(root, folder, second)
            maps, _ = build(root, configured)
            build_site.link_coverage_from_key_links(root, maps)
            backlinks = Path(temp) / "Backlinks.tsx"
            backlinks.write_text(BACKLINKS_SAMPLE, encoding="utf-8")
            with redirect_stdout(io.StringIO()):
                build_site.set_backlinks_structural_pages(
                    backlinks, root, build_site.plan_coverage_maps(root, configured))
            return {
                "page": (root / "Curriculum Coverage.md").read_text(encoding="utf-8"),
                "keyLinks": (root / "Key Links.md").read_text(encoding="utf-8"),
                "backlinks": backlinks.read_text(encoding="utf-8"),
                "sidebar": build_site.names_the_sidebar_hides(["Private"], [item["title"] for item in maps]),
            }

    def test_a_curriculum_folder_course(self):
        self.assertEqual(self.run_fixture("Curriculum", None, ["Curriculum"]), GOLDEN["single"])

    def test_the_lcs_default(self):
        self.assertEqual(self.run_fixture("Ontario Curriculum", "College Board Curriculum", []),
                         GOLDEN["lcs"])

    def test_the_lcs_default_declared_in_the_order_the_apps_write(self):
        self.assertEqual(self.run_fixture("Ontario Curriculum", "College Board Curriculum",
                                          ["Ontario Curriculum", "College Board Curriculum"]),
                         GOLDEN["lcs"])


class NestedAndRepeated(unittest.TestCase):
    """T6 and T7."""

    def test_a_repeated_code_keeps_the_shallowest_page(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "Curriculum"
            write(folder / "2019 version" / "A1.1.md", "old")
            write(folder / "(old)" / "A1.1.md", "older")
            write(folder / "A1.1.md", "current")
            lines = []
            specific, _ = build_site._collect_expectations(folder, printer=lines.append)
            self.assertEqual(specific["A1.1"], folder / "A1.1.md")
            self.assertEqual(len(lines), 2)
            self.assertIn("the map uses A1.1", lines[0])

    def test_units_repeating_a_skill_are_one_cell(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "College Board Curriculum"
            write(folder / "Unit 1" / "1.A.md", "x")
            write(folder / "Unit 2" / "1.A.md", "x")
            lines = []
            specific, _ = build_site._collect_expectations(folder, printer=lines.append)
            self.assertEqual(list(specific), ["1.A"])
            self.assertEqual(specific["1.A"], folder / "Unit 1" / "1.A.md")
            self.assertEqual(lines, ["⚠️  College Board Curriculum has two pages called 1.A — "
                                     "the map uses Unit 1/1.A"])

    def test_numbered_and_heading_pages_are_not_cells(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "College Board Curriculum"
            write(folder / "12.3.md", "x")
            write(folder / "1. Computational Solution Design.md", "x")
            write(folder / "1.A.md", "x")
            specific, overall = build_site._collect_expectations(folder, printer=lambda line: None)
            self.assertEqual(list(specific), ["1.A"])
            self.assertEqual(overall, {})


class LowerCaseCodes(unittest.TestCase):
    """Review finding 6: a lower-case `b2.3` is strand B and overall B2."""

    def test_one_chip_and_it_counts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            write(root / "Curriculum" / "b2.3.md", "x")
            write(root / "Curriculum" / "B2.1.md", "x")
            write(root / "Curriculum" / "B2. Systems.md", "x")
            write(root / "All Classes" / "Unit 1, Day 1.md", "---\ntitle: Unit 1, Day 1\n---\n[[Test]]\n")
            write(root / "Tasks" / "Test.md", "---\ntitle: Test\n---\n![[B2.3]]\n")
            maps, _ = build(root, ["Curriculum"])
            page = (root / "Curriculum Coverage.md").read_text(encoding="utf-8")
            self.assertEqual(page.count('class="coverage-letter"'), 1)
            self.assertEqual(page.count("coverage-chip coverage-chip-"), 1)
            self.assertIn("coverage-chip coverage-chip-yes", page)
            self.assertIn('aria-label="b2.3, addressed once, included in assessed work"', page)
            self.assertIn("| Overall expectations with no assessed work | 0 |", page)


if __name__ == "__main__":
    unittest.main()
