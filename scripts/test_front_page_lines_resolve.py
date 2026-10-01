"""
The line the app writes on a section's front page must still name the class
once the BUILD has read it (#397).

`contracts/class-planning.json` → `sectionIndexPointer.writtenAs`: the app's
pointer keeps the form the teacher wrote, and the build rewrites a link that
carries a `section<N>/` path into its display name
(`build_site.rewrite_section_wikilinks`). The first version of #397 kept a
section path and dropped the display name, so the site got
`![[section1/All Classes/Thread 1, Day 2]]` — a page it does not have — while
the app reported that the front page had moved (implementation review,
finding 1). Every expected line in `sectionIndexPointer.cases` and in
`todaysClassOnTheFrontPage.cases` is run through the build's own rewrite here,
and must then name the class by its file name, or by its place from the
site's root (Quartz reads a path from there).

`build_site` imports `frontmatter`, so verify.sh runs this in the image
(beside test_dates_follow_the_class.py); Windows' PythonToolchainTests
discovers it with the bundled Python.
"""
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_site  # noqa: E402
import contracts  # noqa: E402
import toolchain_paths  # noqa: E402
EMBED = re.compile(r"!\[\[([^\[\]]+?)\]\]")
SECTION_FOLDER = re.compile(r"(?:^|/)section\d+/")


def _contract(key: str) -> dict:
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.section("class-planning", key)


def _target(inner: str) -> str:
    return inner.split("|")[0].split("#")[0].strip()


def _bare(target: str) -> str:
    name = target.split("/")[-1].strip()
    if name.lower().endswith(".md"):
        name = name[:-3].strip()
    return name


def _site_place(course_path: str) -> str:
    """A class's place from the site's root: its path in the course folder,
    without `.md`, and without the section folder the build copies from."""
    place = course_path[:-3] if course_path.lower().endswith(".md") else course_path
    return re.sub(r"^section\d+/", "", place)


class FrontPageLinesResolveTests(unittest.TestCase):

    # MARK: - Helpers

    def assert_resolves(self, name: str, body: str, title: str, course_path: str) -> int:
        """Runs `body` through the build's rewrite and checks every embed of
        `title` in it. Returns how many were checked."""
        with tempfile.TemporaryDirectory() as folder:
            page = Path(folder) / "index.md"
            page.write_text(body, encoding="utf-8")
            build_site.rewrite_section_wikilinks(page)
            built = page.read_text(encoding="utf-8")
        checked = 0
        for match in EMBED.finditer(built):
            target = _target(match.group(1))
            if _bare(target).lower() != title.lower():
                continue
            checked += 1
            self.assertIsNone(SECTION_FOLDER.search(target), f"{name}: the site gets {match.group(0)}")
            if "/" in target:
                written = target[:-3] if target.lower().endswith(".md") else target
                self.assertEqual(written.lower(), _site_place(course_path).lower(),
                                 f"{name}: the site gets {match.group(0)}, the class is at {_site_place(course_path)}")
        return checked

    # MARK: - Tests

    def test_every_pointer_line_names_its_class_on_the_site(self):
        cases = _contract("sectionIndexPointer")["cases"]
        self.assertGreaterEqual(len(cases), 27)
        checked = 0
        for case in cases:
            if case.get("expectBody") is None:
                continue
            with self.subTest(case=case["name"]):
                point = case["pointAt"]
                course_path = case.get("pointAtPath", f"section1/All Classes/{point}.md")
                found = self.assert_resolves(case["name"], case["expectBody"], point, course_path)
                self.assertGreaterEqual(found, 1, f"{case['name']}: no line names {point}")
                checked += found
        self.assertGreaterEqual(checked, 20)

    def test_every_line_yes_leaves_names_todays_class_on_the_site(self):
        cases = _contract("todaysClassOnTheFrontPage")["cases"]
        checked = 0
        for case in cases:
            after = case.get("expectAfterYes")
            if after is None:
                continue
            with self.subTest(case=case["name"]):
                show = case["expectAsk"]["show"]
                section = case.get("section", 1)
                folder = "All Classes"
                for page_class in case["classes"]:
                    if page_class["title"] == show:
                        folder = page_class.get("folder", "All Classes")
                course_path = f"section{section}/{folder}/{show}.md"
                found = self.assert_resolves(case["name"], after["body"], show, course_path)
                self.assertGreaterEqual(found, 1, f"{case['name']}: no line names {show}")
                checked += found
        self.assertGreaterEqual(checked, 22)

    def test_the_first_version_of_the_line_is_caught(self):
        """The shape the implementation review found, as the first #397
        version wrote it: the check must fail it."""
        with self.assertRaises(AssertionError):
            self.assert_resolves(
                "MPM2DE, first version", "![[section1/All Classes/Thread 1, Day 2]]\n",
                "Thread 1, Day 2", "section1/All Classes/Thread 1, Day 2.md")


if __name__ == "__main__":
    unittest.main()
