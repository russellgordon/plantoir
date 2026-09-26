#!/usr/bin/env python3
"""
The front page, and every page a class brings, take their CLASS's date —
in the site AND in the teacher's own files (GitHub #275 and #276).

The cases are not retyped here: they are deserialised from
contracts/class-planning.json ->
  sectionIndexPointer.dateCases            (the front page),
  datingPagesAClassBrings.atBuildTime      (the pages a class brings), and
  datingPagesAClassBrings.atBuildTime.writingCases (the splice itself),
and from contracts/shared-rules.json -> readingALink (what a link names, #294).

Each case is laid out as a teacher's course folder, then copied and read the
way `build_section_site` copies and reads a section — the same
`remember_vault_source` calls, the same `process_frontmatter` — and the date
passes are run over that copy, in the order the build runs them. Every case is
then built AGAIN, and the second build must change no file: a page rewritten
after a build has started makes the app build once more (#265), so a pass that
rewrote something on every build would rebuild on every publish.

`build_site` imports `frontmatter`, which lives only inside the container, so
this CANNOT be run on the host. verify.sh runs it in the image:

    docker run --rm -v "$(pwd)/scripts/test_dates_follow_the_class.py:/opt/scripts/test_dates_follow_the_class.py:ro" \
      quartz-teacher:dev-test python3 /opt/scripts/test_dates_follow_the_class.py
"""
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

import build_site
import class_pages
import contracts
import frontmatter
import toolchain_paths


def _load(*path):
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.section("class-planning", *path)


def _remember(copy: Path, source: Path, is_section_page: bool) -> None:
    # Looked up rather than called directly so that the SAME file, run
    # against a build_site.py from before this pass existed, fails on what
    # the site and the files say (the page still dated install day) rather
    # than on a missing name — which is what a must-fail has to show.
    remember = getattr(build_site, "remember_vault_source", None)
    if remember is not None:
        remember(copy, source, is_section_page=is_section_page)


class CourseFolder:
    """One case laid out as a teacher's course folder, built section by
    section the way the build does it."""

    # MARK: - Initializer

    def __init__(self, root: Path, case: dict):
        self.root = root
        self.case = case
        self.course = root / "courses" / "TEST"
        self.files_by_title: dict[str, Path] = {}
        self.write_the_teachers_files()

    # MARK: - Functions

    def write_page(self, path: Path, frontmatter_text: str, body: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        if frontmatter_text == "":
            text = body
        else:
            text = "---\n" + frontmatter_text + "---\n" + body
        path.write_text(text, encoding="utf-8")

    def write_the_teachers_files(self) -> None:
        for page_class in self.case.get("classes", []):
            section = page_class.get("section", self.case.get("section", 1))
            lines = [f"title: {page_class['title']}",
                     "publish: " + ("true" if page_class.get("visible", True) else "false")]
            if page_class.get("created") is not None:
                lines.append(f"created: {page_class['created']}")
            body = "".join(f"[[{link}]]\n" for link in page_class.get("links", []))
            path = self.course / f"section{section}" / "All Classes" / f"{page_class['title']}.md"
            self.write_page(path, "\n".join(lines) + "\n", body)
            self.files_by_title.setdefault(page_class["title"], path)
        for page in self.case.get("pages", []):
            body = "".join(f"[[{link}]]\n" for link in page.get("links", [])) or "Something to read.\n"
            if "section" in page:
                path = self.course / f"section{page['section']}" / page["folder"] / f"{page['title']}.md"
            else:
                path = self.course / page["folder"] / f"{page['title']}.md"
            self.write_page(path, page["frontmatter"], body)
            self.files_by_title[page["title"]] = path
        if "indexText" in self.case:
            section = self.case.get("section", 1)
            index = self.course / f"section{section}" / "index.md"
            index.parent.mkdir(parents=True, exist_ok=True)
            index.write_text(self.case["indexText"], encoding="utf-8")
            self.files_by_title["index"] = index

    def snapshot(self) -> dict:
        found = {}
        for path in sorted(self.course.rglob("*.md")):
            found[path] = path.read_bytes()
        return found

    def build(self, section: int, write_back: bool = True) -> tuple[Path, dict]:
        """Copies section `section` the way `build_section_site` does, then
        runs the two date passes. Returns the copy and what was rewritten."""
        content = self.root / f"content{section}"
        if content.exists():
            shutil.rmtree(content)
        content.mkdir()
        section_dir = self.course / f"section{section}"
        forget = getattr(build_site, "forget_vault_sources", None)
        if forget is not None:
            forget(self.course)

        index = section_dir / "index.md"
        if index.exists():
            shutil.copy2(index, content / "index.md")
            _remember(content / "index.md", index, True)
            build_site.process_frontmatter(content / "index.md", section)

        for path in sorted(self.course.rglob("*.md")):
            relative = path.relative_to(self.course)
            if relative.parts[0].startswith("section"):
                continue
            copy = content / relative
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, copy)
            _remember(copy, path, False)
            build_site.process_frontmatter(copy, section)

        if section_dir.exists():
            for path in sorted(section_dir.rglob("*.md")):
                relative = path.relative_to(section_dir)
                if relative.as_posix() == "index.md":
                    continue
                copy = content / relative
                copy.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, copy)
                _remember(copy, path, True)
                build_site.process_frontmatter(copy, section)

        first = build_site._find_first_class_created(content)
        if first is not None:
            build_site._sync_non_class_pages_created(content, first)
        date_pass = getattr(build_site, "_date_pages_from_their_classes", None)
        if date_pass is None:
            return content, {"front_page": None, "site_pages": 0, "rewritten": []}
        return content, date_pass(content, section, write_back=write_back)


class DatesFollowTheClassTests(unittest.TestCase):

    # MARK: - Set up and tear down

    @classmethod
    def setUpClass(cls):
        cls.front_page_cases = _load("sectionIndexPointer", "dateCases")
        cls.at_build_time = _load("datingPagesAClassBrings", "atBuildTime")

    def setUp(self):
        self.temporary = Path(tempfile.mkdtemp())
        self.original_word = build_site.unit_word()
        self.original_scheme = build_site._class_page_scheme

    def tearDown(self):
        build_site.set_unit_word(self.original_word)
        build_site.set_class_page_scheme(self.original_scheme)
        forget = getattr(build_site, "forget_vault_sources", None)
        if forget is not None:
            forget()
        shutil.rmtree(self.temporary, ignore_errors=True)

    # MARK: - Helpers

    def use_the_course_words(self, case: dict) -> None:
        build_site.set_unit_word(case.get("unitWord", class_pages.DEFAULT_UNIT_WORD))
        build_site.set_class_page_scheme(case.get("classPageScheme", class_pages.UNIT_DAY_SCHEME))

    def folder_for(self, case: dict, index: int) -> CourseFolder:
        root = self.temporary / f"case{index}"
        root.mkdir()
        return CourseFolder(root, case)

    def date_the_build_reads(self, path: Path, section: int):
        metadata = frontmatter.load(path).metadata
        per_section_key = f"createdSection{section}"
        if per_section_key in metadata:
            return metadata[per_section_key]
        return metadata.get("created")

    # MARK: - Tests

    def test_the_front_page_takes_the_date_of_the_class_it_shows(self):
        cases = self.front_page_cases["cases"]
        self.assertGreaterEqual(len(cases), 9, "the contract lost front-page date cases")
        for index, case in enumerate(cases):
            with self.subTest(case=case["name"]):
                self.use_the_course_words(case)
                folder = self.folder_for(case, index)
                section = case.get("section", 1)
                original = folder.files_by_title["index"].read_bytes()
                original_date = frontmatter.loads(case["indexText"]).get("created")

                content, result = folder.build(section)
                site_date = frontmatter.load(content / "index.md").get("created")
                file_date = self.date_the_build_reads(folder.files_by_title["index"], section)
                expected_day = case["expectCreatedDay"]
                if expected_day is None:
                    self.assertEqual(site_date, original_date)
                    self.assertEqual(folder.files_by_title["index"].read_bytes(), original,
                                     "a front page that keeps its own date must not be written")
                    self.assertEqual(result["rewritten"], [])
                else:
                    named = None
                    for page_class in case["classes"]:
                        if page_class["title"] in case["indexText"]:
                            named = page_class["created"]
                    self.assertEqual(site_date, named)
                    self.assertTrue(str(site_date).startswith(expected_day))
                    self.assertEqual(file_date, named, "the teacher's front page was not rewritten")
                    self.assertIn(f"section{section}/index", result["rewritten"])

                self.assert_a_second_build_writes_nothing(folder, [section])

    def test_the_pages_a_class_brings_take_its_date(self):
        cases = self.at_build_time["cases"]
        self.assertGreaterEqual(len(cases), 14, "the contract lost build-time date cases")
        for index, case in enumerate(cases):
            with self.subTest(case=case["name"]):
                self.use_the_course_words(case)
                folder = self.folder_for(case, index)
                sections = case.get("sections", [1])
                before = folder.snapshot()

                rewritten: list[str] = []
                content = None
                for section in sections:
                    content, result = folder.build(section)
                    rewritten.extend(result["rewritten"])
                last_section = sections[-1]

                for title, value in case.get("expectCreated", {}).items():
                    copy = self.copy_of(content, title)
                    self.assertEqual(frontmatter.load(copy).get("created"), value, f"{title} (site)")
                    self.assertEqual(self.date_the_build_reads(folder.files_by_title[title], last_section),
                                     value, f"{title} (file)")
                for title, day in case.get("expectCreatedDay", {}).items():
                    # A plain YAML date reads back as a date, not as text, so
                    # the case names the DAY rather than a string to match.
                    copy = self.copy_of(content, title)
                    self.assertEqual(str(frontmatter.load(copy).get("created")), day, f"{title} (site)")
                    self.assertEqual(str(self.date_the_build_reads(folder.files_by_title[title], last_section)),
                                     day, f"{title} (file)")
                for title, keys in case.get("expectFileKeys", {}).items():
                    metadata = frontmatter.load(folder.files_by_title[title]).metadata
                    for key, value in keys.items():
                        if value is None:
                            self.assertNotIn(key, metadata, f"{title}: {key}")
                        else:
                            self.assertEqual(metadata.get(key), value, f"{title}: {key}")
                for title in case.get("expectUnchanged", []):
                    path = folder.files_by_title[title]
                    self.assertEqual(path.read_bytes(), before[path], f"{title} was written")

                names = sorted(set(name.split("/")[-1] for name in rewritten))
                self.assertEqual(names, sorted(case["expectRewritten"]))

                self.assert_a_second_build_writes_nothing(folder, sections)

    def test_the_splice_writes_one_key_and_nothing_else(self):
        cases = self.at_build_time["writingCases"]["cases"]
        self.assertGreaterEqual(len(cases), 13)
        for case in cases:
            with self.subTest(case=case["name"]):
                written = build_site._setting_frontmatter_value(
                    case["before"], case["write"]["key"], case["write"]["value"])
                self.assertEqual(written, case["after"])

    def test_the_teachers_file_is_written_only_when_its_date_is_wrong(self):
        # Beside the contract's cases, the guard every write passes: a page
        # already carrying the class's date is not opened for writing at all.
        page = self.temporary / "Already Right.md"
        page.write_text("---\ncreatedSection1: 2026-09-24T07:00:00.000+0000\n---\nBody\n", encoding="utf-8")
        stamp = page.stat().st_mtime_ns
        wrote = build_site._write_date_into_the_teachers_page(
            page, False, 1, "2026-09-24T07:00:00.000+0000")
        self.assertFalse(wrote)
        self.assertEqual(page.stat().st_mtime_ns, stamp)

    def one_class_linking(self, title: str) -> dict:
        return {
            "unitWord": "Thread",
            "classes": [{"title": "Thread 1, Day 3", "created": "2026-09-24T07:00:00.000+0000",
                         "visible": True, "links": [title]}],
            "pages": [{"title": title, "folder": "Exercises",
                       "frontmatter": "createdSection1: 2026-09-08T07:00:00.000+0000\n"}],
        }

    def test_a_page_that_is_a_link_to_a_file_elsewhere_is_never_written_through(self):
        # The build reads it — the site is dated — but the file it points at
        # lives outside this course, or is shared by another, so it is named
        # and left alone.
        case = self.one_class_linking("Kept Elsewhere")
        self.use_the_course_words(case)
        folder = self.folder_for(case, 97)
        page = folder.files_by_title["Kept Elsewhere"]
        elsewhere = self.temporary / "elsewhere.md"
        shutil.move(page, elsewhere)
        page.symlink_to(elsewhere)
        original = elsewhere.read_bytes()

        content, result = folder.build(1)
        self.assertEqual(elsewhere.read_bytes(), original, "the build wrote through the link")
        self.assertTrue(page.is_symlink(), "the link was replaced")
        self.assertEqual(result["rewritten"], [])
        self.assertEqual(result["left_linked"], ["Exercises/Kept Elsewhere"])
        self.assertEqual(frontmatter.load(self.copy_of(content, "Kept Elsewhere")).get("created"),
                         "2026-09-24T07:00:00.000+0000", "the site is still dated")

        printed: list[str] = []
        build_site.announce_dated_pages(result, "TEST", 1, printer=printed.append)
        self.assertEqual(len(printed), 1)
        self.assertIn("Exercises/Kept Elsewhere", printed[0])

    def test_a_page_inside_a_linked_folder_is_never_written_through(self):
        # The build copies a shared folder that is itself a link (os.walk
        # follows the folder it is given), so the check looks at every folder
        # between the page and the course folder, not only at the page.
        course = self.temporary / "courses" / "TEST"
        elsewhere = self.temporary / "elsewhere-folder"
        elsewhere.mkdir(parents=True)
        (elsewhere / "Notes.md").write_text("---\ntitle: Notes\n---\nBody\n", encoding="utf-8")
        course.mkdir(parents=True)
        (course / "Exercises").symlink_to(elsewhere, target_is_directory=True)
        (course / "Plain.md").write_text("---\ntitle: Plain\n---\nBody\n", encoding="utf-8")
        build_site.forget_vault_sources(course)
        self.assertTrue(build_site._reaches_the_page_through_a_link(course / "Exercises" / "Notes.md"))
        self.assertFalse(build_site._reaches_the_page_through_a_link(course / "Plain.md"))

    def test_a_page_with_two_names_is_never_written(self):
        case = self.one_class_linking("Two Names")
        self.use_the_course_words(case)
        folder = self.folder_for(case, 95)
        page = folder.files_by_title["Two Names"]
        other_name = self.temporary / "other-name.md"
        os.link(page, other_name)
        original = page.read_bytes()

        content, result = folder.build(1)
        self.assertEqual(page.read_bytes(), original)
        self.assertEqual(other_name.read_bytes(), original)
        self.assertEqual(result["left_linked"], ["Exercises/Two Names"])

    def test_a_page_that_changed_after_it_was_read_is_not_overwritten(self):
        # An Obsidian save landing between the read and the write: the build
        # keeps the teacher's save and writes nothing (the next build dates it).
        page = self.temporary / "Saved Meanwhile.md"
        page.write_text("---\ncreatedSection1: 2026-09-08T07:00:00.000+0000\n---\nTyped just now\n",
                        encoding="utf-8")
        what_the_build_read = "---\ncreatedSection1: 2026-09-08T07:00:00.000+0000\n---\nOlder\n"
        rewritten = "---\ncreatedSection1: 2026-09-24T07:00:00.000+0000\n---\nOlder\n"
        before = page.read_bytes()
        self.assertFalse(build_site._replace_the_page_safely(page, what_the_build_read, rewritten))
        self.assertEqual(page.read_bytes(), before)
        self.assertEqual(sorted(path.name for path in self.temporary.iterdir()), ["Saved Meanwhile.md"],
                         "a half-made file was left beside the page")

    def test_a_write_that_fails_part_way_leaves_the_page_whole(self):
        # A Stop, a full disk or a refused rename: the page is the old one,
        # whole, and nothing is left beside it.
        page = self.temporary / "Interrupted.md"
        text = "---\ncreatedSection1: 2026-09-08T07:00:00.000+0000\n---\nBody\n"
        page.write_text(text, encoding="utf-8")
        real_replace = build_site.os.replace

        def refuse(source, destination):
            raise OSError("interrupted")

        build_site.os.replace = refuse
        try:
            wrote = build_site._write_date_into_the_teachers_page(
                page, False, 1, "2026-09-24T07:00:00.000+0000")
        finally:
            build_site.os.replace = real_replace
        self.assertIsNone(wrote)
        self.assertEqual(page.read_text(encoding="utf-8"), text)
        self.assertEqual(sorted(path.name for path in self.temporary.iterdir()), ["Interrupted.md"])

    def test_a_read_only_page_is_named_and_left_alone_even_for_root(self):
        # The build runs as ROOT in the container, and root passes os.access
        # for every file: the first version rewrote a 0444 page there. The
        # mode bits are read instead, so this holds for any user — os.access
        # is made to answer the way it does for root, to prove it.
        case = self.one_class_linking("Read Only")
        self.use_the_course_words(case)
        folder = self.folder_for(case, 94)
        page = folder.files_by_title["Read Only"]
        original = page.read_bytes()
        os.chmod(page, 0o444)
        real_access = build_site.os.access

        def as_root(path, mode, *arguments, **keywords):
            return True

        build_site.os.access = as_root
        try:
            content, result = folder.build(1)
        finally:
            build_site.os.access = real_access
            os.chmod(page, 0o644)
        self.assertEqual(page.read_bytes(), original, "the build rewrote a read-only page")
        self.assertEqual(result["rewritten"], [])
        self.assertEqual(result["left_locked"], ["Exercises/Read Only"])
        self.assertEqual(frontmatter.load(self.copy_of(content, "Read Only")).get("created"),
                         "2026-09-24T07:00:00.000+0000", "the site is still dated")

        printed: list[str] = []
        build_site.announce_dated_pages(result, "TEST", 1, printer=printed.append)
        self.assertEqual(len(printed), 1)
        self.assertIn("Exercises/Read Only", printed[0])

    def test_a_date_that_would_read_back_differently_is_quoted(self):
        # A plain `2026-09-24` is a DATE to YAML, not the string the class
        # carried; written plain it would never read back equal, and the page
        # would be rewritten on every build.
        self.assertEqual(build_site._yaml_text_for_date("2026-09-24"), '"2026-09-24"')
        self.assertEqual(build_site._yaml_text_for_date("2026-09-24T07:00:00.000+0000"),
                         "2026-09-24T07:00:00.000+0000")

    def test_a_course_kept_for_reference_is_dated_on_the_site_only(self):
        # The build passes write_back=False for a course kept for reference
        # (reference_course.is_reference): last year's course is frozen on
        # purpose, so its site copy is dated and its files are not touched.
        case = self.at_build_time["cases"][0]
        self.use_the_course_words(case)
        folder = self.folder_for(case, 99)
        before = folder.snapshot()
        content, result = folder.build(1, write_back=False)
        self.assertEqual(result["rewritten"], [])
        self.assertEqual(folder.snapshot(), before)
        self.assertEqual(frontmatter.load(self.copy_of(content, "Using Aggregate Functions")).get("created"),
                         case["expectCreated"]["Using Aggregate Functions"])

    def test_the_build_names_what_it_rewrote_the_way_the_contract_shows(self):
        # The line the apps read, compared with the contract's own example so
        # the printer and the readers (PagesDatedByTheBuildTests on the mac)
        # cannot drift apart. Nothing is printed when nothing was rewritten.
        rules = contracts.load("shared-rules")["pagesDatedByTheBuild"]
        printed: list[str] = []
        build_site.announce_dated_pages(
            {"rewritten": ["section1/index", "Exercises/Using Aggregate Functions"]},
            "ICS4U", 1, printer=printed.append)
        self.assertEqual(len(printed), 2)
        self.assertNotIn(rules["marker"]["prefix"], printed[0], "the first line is the teacher's")
        self.assertEqual(printed[1], rules["marker"]["examples"][0])

        nothing: list[str] = []
        build_site.announce_dated_pages({"rewritten": []}, "ICS4U", 1, printer=nothing.append)
        self.assertEqual(nothing, [])

    def test_every_link_shape_reads_as_the_contract_says(self):
        # shared-rules.json -> readingALink (#294): what a wikilink NAMES,
        # including the escaped pipe Obsidian writes for an alias inside a
        # table, [[Ohm's Law\|Ohm]]. The build already read that shape; this
        # is the guard that keeps it reading it, and the reorder that made it
        # read [[Page#Heading|words]] as well. The build compares names by
        # their last path component AND by the whole path, lowercased, so it
        # holds both for each name the case expects - and nothing else.
        _load("sectionIndexPointer")  # points `contracts` at this checkout's files
        rules = contracts.load("shared-rules")["readingALink"]
        cases = rules["cases"]
        self.assertGreaterEqual(len(cases), 34, "readingALink lost cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                read = build_site._extract_wikilink_targets(case["text"])
                expected = set()
                for name in case["expect"]:
                    expected.add(name.split("/")[-1].strip().lower())
                    expected.add(name.lower())
                self.assertEqual(read, expected)
                for target in read:
                    self.assertFalse(target.endswith("\\"), f"{target!r} kept the backslash")

    def test_a_page_a_class_links_to_by_a_heading_with_an_alias_takes_its_date(self):
        # [[Worksheet#Part A\|part A]], written on Day 3. Before #294 the
        # build did not read a heading followed by an alias as a link at all,
        # so the worksheet was reset to the course's FIRST class date (Day 1)
        # while the mac's re-date gave it Day 3's. Now both say Day 3.
        case = {
            "name": "a heading and an escaped alias",
            "classes": [
                {"title": "Unit 1, Day 1", "created": "2026-09-08T07:00:00.000+0000",
                 "visible": True, "links": []},
                {"title": "Unit 1, Day 3", "created": "2026-09-10T07:00:00.000+0000",
                 "visible": True, "links": ["Worksheet#Part A\\|part A"]},
            ],
            "pages": [
                {"title": "Worksheet", "folder": "Exercises",
                 "frontmatter": "createdSection1: 2026-09-01T07:00:00.000+0000\npublishForSection1: true\n"},
            ],
        }
        self.use_the_course_words(case)
        folder = self.folder_for(case, 0)
        self.assertIn("[[Worksheet#Part A\\|part A]]",
                      folder.files_by_title["Unit 1, Day 3"].read_text(encoding="utf-8"))
        content, result = folder.build(1)
        self.assertEqual(frontmatter.load(self.copy_of(content, "Worksheet")).get("created"),
                         "2026-09-10T07:00:00.000+0000")
        self.assertEqual(self.date_the_build_reads(folder.files_by_title["Worksheet"], 1),
                         "2026-09-10T07:00:00.000+0000")
        self.assert_a_second_build_writes_nothing(folder, [1])

    # MARK: - Assertions

    def copy_of(self, content: Path, title: str) -> Path:
        for path in content.rglob(f"{title}.md"):
            return path
        self.fail(f"{title} is not in the build's copy")

    def assert_a_second_build_writes_nothing(self, folder: CourseFolder, sections: list) -> None:
        settled = folder.snapshot()
        for section in sections:
            content, result = folder.build(section)
            self.assertEqual(result["rewritten"], [], "a second build rewrote pages")
        self.assertEqual(folder.snapshot(), settled, "a second build changed the teacher's files")


if __name__ == "__main__":
    unittest.main()
