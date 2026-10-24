#!/usr/bin/env python3
"""
Which file each page of a section's site came from (GitHub #518).

Open in Obsidian, pressed for a section while its preview shows a page, opens
the file behind that page. Only the build knows which file made a page, so it
writes `.page-sources.json` beside `public/` (contracts/file-formats.json ->
`pageSourcesList`), and both apps read it
(contracts/shared-rules.json -> `obsidianOpensThePreviewedPage`).

Two modes.

  python3 test_page_sources.py
      Every `slugCases` case through `build_site.page_slug_as_quartz_serves`,
      then a course laid out and copied the way `build_section_site` copies a
      section - the same `remember_vault_source` calls - and the list
      `build_site.page_sources` makes of it checked entry by entry. Needs the
      image (`build_site` imports `frontmatter`); verify.sh runs it there.

  python3 test_page_sources.py --site <section's built output> <course folder>
      A REAL build's list read back: every address a page students see is
      listed under must be a page Quartz actually wrote, and every file it
      names must be there. This is the measurement of the slug rule against
      Quartz itself, rather than against the cases above. Plain Python;
      verify.sh runs it on the host after its build.
"""
import json
import os
import shutil
import sys
import tempfile
import unicodedata
import unittest
from pathlib import Path

sys.dont_write_bytecode = True


def _contract_section():
    here = Path(__file__).resolve().parent
    for candidate in (here.parent / "contracts", Path("/opt/contracts")):
        path = candidate / "shared-rules.json"
        if path.is_file():
            with open(path, encoding="utf-8") as handle:
                return json.load(handle)["obsidianOpensThePreviewedPage"]
    raise FileNotFoundError("contracts/shared-rules.json")


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class PageSourcesTests(unittest.TestCase):

    def setUp(self):
        import build_site
        self.build_site = build_site
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-518-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.course = self.root / "courses" / "ICS3U"
        self.content = self.root / "work" / "content"
        self.section = self.course / "section1"

    # ---- the slug rule ----

    def test_every_slug_case(self):
        cases = _contract_section()["slugCases"]["cases"]
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            with self.subTest(file=case["file"]):
                self.assertEqual(
                    self.build_site.page_slug_as_quartz_serves(Path(case["file"])), case["slug"])

    # ---- the list a build makes ----

    def _copy_like_the_build(self, shared_folders, per_section_folders):
        """The copy in `build_section_site`, in its order: the front page, the
        shared folders, then the per-section folders over them."""
        bs = self.build_site
        bs.forget_vault_sources(self.course)
        self.content.mkdir(parents=True, exist_ok=True)
        front = self.section / "index.md"
        if front.exists():
            shutil.copy2(front, self.content / "index.md")
            bs.remember_vault_source(self.content / "index.md", front, is_section_page=True)
        for name in shared_folders:
            source_folder = self.course / name
            for root, _dirs, files in os.walk(source_folder):
                relative = Path(root).relative_to(self.course)
                (self.content / relative).mkdir(parents=True, exist_ok=True)
                for file in files:
                    shutil.copy2(Path(root) / file, self.content / relative / file)
                    bs.remember_vault_source(self.content / relative / file, Path(root) / file,
                                             is_section_page=False)
        for name in per_section_folders:
            source_folder = self.section / name
            destination = self.content / name
            if source_folder.exists():
                shutil.copytree(source_folder, destination, dirs_exist_ok=True)
                for root, _dirs, files in os.walk(destination):
                    for file in files:
                        copied = Path(root) / file
                        bs.remember_vault_source(copied, source_folder / copied.relative_to(destination),
                                                 is_section_page=True)

    def _lay_out_the_course(self, front_page_text):
        _write(self.section / "index.md", front_page_text)
        _write(self.section / "All Classes" / "Unit 1, Day 3.md", "---\ntitle: Unit 1, Day 3\n---\nToday.\n")
        _write(self.course / "Unit 1" / "Lesson 3.md", "Lesson.\n")
        _write(self.course / "Unit 1" / "_index.md", "The unit.\n")
        _write(self.course / "Unit 1" / unicodedata.normalize("NFD", "Café Notes.md"), "Notes.\n")
        _write(self.course / "Unit 1" / "C++ Basics.md", "Plus.\n")
        _write(self.course / "Unit 1" / "Homework.md", "Shared homework.\n")
        _write(self.course / "Unit 1" / "A B.md", "One.\n")
        _write(self.course / "Unit 1" / "A-B.md", "Two.\n")
        _write(self.course / "Unit 1" / "Notes.MD", "Not a page to Quartz.\n")
        _write(self.course / "Unit 1" / "Hidden.md", "---\npublish: false\n---\nNot yet.\n")
        _write(self.section / "Unit 1" / "Homework.md", "This section's homework.\n")
        _write(self.section / "Unit 1" / "Quiz.md", "---\npublish: false\n---\nQuiz.\n")

    def _the_list(self, front_page_text="---\ntitle: Section 1\n---\n\n![[Unit 1, Day 3]]\n\n"):
        self._lay_out_the_course(front_page_text)
        self._copy_like_the_build(["Unit 1"], ["Unit 1", "All Classes"])
        # A page the build makes itself (My Progress) has no source.
        _write(self.content / "My Progress.md", "Made by the build.\n")
        return self.build_site.page_sources(self.content, self.course, "ICS3U", 1, "test-build")

    def test_the_list_names_each_page_by_its_file(self):
        made = self._the_list()
        self.assertEqual(made["version"], 1)
        self.assertEqual((made["course"], made["section"], made["buildId"]), ("ICS3U", 1, "test-build"))
        pages = made["pages"]
        self.assertEqual(pages["Unit-1/Lesson-3"], {"source": "Unit 1/Lesson 3.md", "hidden": False})
        self.assertEqual(pages["Unit-1/index"], {"source": "Unit 1/_index.md", "hidden": False})
        self.assertEqual(pages["Unit-1/C++-Basics"], {"source": "Unit 1/C++ Basics.md", "hidden": False})
        # The section's page replaced the shared one, so the section's file.
        self.assertEqual(pages["Unit-1/Homework"], {"source": "section1/Unit 1/Homework.md", "hidden": False})
        self.assertEqual(pages["Unit-1/Quiz"], {"source": "section1/Unit 1/Quiz.md", "hidden": True})
        self.assertEqual(pages["Unit-1/Hidden"]["hidden"], True)
        self.assertEqual(pages["All-Classes/Unit-1,-Day-3"]["source"], "section1/All Classes/Unit 1, Day 3.md")

    def test_a_name_is_spelled_as_it_is_on_disk(self):
        pages = self._the_list()["pages"]
        found = None
        for slug, entry in pages.items():
            if unicodedata.normalize("NFC", slug) == "Unit-1/Café-Notes":
                found = entry
        self.assertIsNotNone(found, sorted(pages))
        on_disk = None
        for name in os.listdir(self.course / "Unit 1"):
            if unicodedata.normalize("NFC", name) == "Café Notes.md":
                on_disk = name
        self.assertEqual(found["source"], "Unit 1/" + on_disk)

    def test_two_files_one_address_is_collided(self):
        self.assertEqual(self._the_list()["pages"]["Unit-1/A-B"], {"collided": True})

    def test_what_quartz_makes_no_page_of_and_what_the_build_made_are_not_listed(self):
        pages = self._the_list()["pages"]
        self.assertNotIn("My-Progress", pages)
        self.assertNotIn("Unit-1/Notes", pages)
        self.assertNotIn("Unit-1/Notes.MD", pages)

    def test_a_shared_page_in_a_folder_that_is_per_section_too_names_the_shared_file(self):
        # "Unit 1" is both shared and per-section in this course, and the
        # per-section walk credits every file under it to section1/ - Lesson 3
        # included, which section1/ does not have (#518 plan, noted for a
        # toolchain issue). The list names the shared file that made it.
        pages = self._the_list()["pages"]
        found = self.build_site._vault_sources[self.content / "Unit 1" / "Lesson 3.md"]
        self.assertEqual(found, (self.section / "Unit 1" / "Lesson 3.md", True), "the trap is still there")
        self.assertEqual(pages["Unit-1/Lesson-3"]["source"], "Unit 1/Lesson 3.md")
        for entry in pages.values():
            if "source" in entry:
                self.assertTrue((self.course / entry["source"]).is_file(), entry)

    def test_the_front_page_that_only_embeds_a_class_shows_it(self):
        index = self._the_list()["pages"]["index"]
        self.assertEqual(index, {"source": "section1/index.md", "hidden": False,
                                 "shows": "section1/All Classes/Unit 1, Day 3.md",
                                 "showsHidden": False})

    def test_a_hidden_class_on_a_visible_front_page_is_flagged_as_hidden(self):
        # The front page is visible; the class it embeds is not. The file
        # that opens is the class, so its own flag is what the trail reads.
        self._lay_out_the_course("---\ntitle: Section 1\n---\n\n![[Unit 1, Day 3]]\n\n")
        _write(self.section / "All Classes" / "Unit 1, Day 3.md",
               "---\ntitle: Unit 1, Day 3\npublish: false\n---\nToday.\n")
        self._copy_like_the_build(["Unit 1"], ["Unit 1", "All Classes"])
        index = self.build_site.page_sources(self.content, self.course, "ICS3U", 1, "b")["pages"]["index"]
        self.assertEqual(index["hidden"], False)
        self.assertEqual(index["shows"], "section1/All Classes/Unit 1, Day 3.md")
        self.assertEqual(index["showsHidden"], True)

    def test_a_front_page_with_more_on_it_shows_nothing_else(self):
        index = self._the_list("---\ntitle: Section 1\n---\nWelcome.\n![[Unit 1, Day 3]]\n")["pages"]["index"]
        self.assertEqual(index, {"source": "section1/index.md", "hidden": False})

    def test_an_embed_of_a_page_that_is_not_there_shows_nothing_else(self):
        index = self._the_list("![[Unit 9, Day 9]]\n")["pages"]["index"]
        self.assertNotIn("shows", index)

    def test_the_list_is_written_beside_public_and_never_inside(self):
        self._lay_out_the_course("![[Unit 1, Day 3]]\n")
        self._copy_like_the_build(["Unit 1"], ["Unit 1", "All Classes"])
        output = self.root / "builds" / "ICS3U" / "section1"
        (output / "public").mkdir(parents=True)
        self.build_site._write_page_sources(output, self.content, self.course, "ICS3U", 1, "b1")
        with open(output / ".page-sources.json", encoding="utf-8") as handle:
            written = json.load(handle)
        self.assertEqual(written["buildId"], "b1")
        self.assertEqual(sorted(os.listdir(output)), [".page-sources.json", "public"])
        self.assertEqual(os.listdir(output / "public"), [])

    def test_the_build_writes_it_before_quartz_in_both_modes(self):
        source = Path(self.build_site.__file__).read_text(encoding="utf-8")
        call = source.index("_write_page_sources(host_output_dir, content_root")
        branch = source.index("    if build_only:\n        # A preview for THIS section")
        self.assertLess(call, branch, "written before the preview/publish branch, so a preview has it")
        self.assertLess(source.index("my_progress_slug = _prepare_my_progress("), call)


def check_a_real_site(built: Path, course: Path) -> int:
    """The list a real build wrote, against the pages Quartz wrote."""
    listed = built / ".page-sources.json"
    if (built / "public" / ".page-sources.json").exists():
        print("❌ the list is inside public/, where a deploy would upload it")
        return 1
    try:
        with open(listed, encoding="utf-8") as handle:
            made = json.load(handle)
    except Exception as error:
        print(f"❌ no readable {listed}: {error}")
        return 1
    problems = []
    checked = 0
    pages = made.get("pages", {})
    if pages.get("index", {}).get("source") != "section1/index.md":
        problems.append(f"the front page is listed as {pages.get('index')}")
    for slug, entry in sorted(pages.items()):
        if entry.get("collided"):
            continue
        if not (course / entry["source"]).is_file():
            problems.append(f"{slug}: {entry['source']} is not in the course folder")
        if entry.get("hidden"):
            continue
        checked += 1
        if not (built / "public" / (slug + ".html")).is_file():
            problems.append(f"{slug}: Quartz wrote no {slug}.html")
    if checked == 0:
        problems.append("no page students see is listed")
    for problem in problems:
        print("❌ " + problem)
    print(f"{checked} listed page(s) checked against what Quartz wrote")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--site":
        sys.exit(check_a_real_site(Path(sys.argv[2]), Path(sys.argv[3])))
    unittest.main()
