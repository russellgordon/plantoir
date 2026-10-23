#!/usr/bin/env python3
"""
A front page whose title Plantoir wrote with an unquoted ": " before 1.8.1 is
quoted by the BUILD, so the section has its website again (GitHub #584).

The cases are not retyped here: they are deserialised from
contracts/shared-rules.json -> buildRepairs.frontPageTitleQuoted.cases, and
each is run through `build_site._front_page_title_quoted`, byte for byte. The
front page itself is copied the way `build_section_site` copies it — through
`build_site.copy_the_section_front_page`, the very function the build calls —
on a course folder laid out as a teacher's, and every repair is built AGAIN:
the second build must change no file and say nothing, because a page rewritten
after a build has started makes the app build once more (#265).

Run against a build_site.py from before the repair, the same file fails on
what the build DOES — the front page hidden, the teacher's page unchanged —
and not only on a missing name: `_copy_the_front_page` below falls back to
the steps the build ran before.

`build_site` imports `frontmatter`, which lives only inside the container on
the mac, so this CANNOT be run on the mac host. verify.sh runs it in the image:

    docker run --rm \\
      -v "$(pwd)/scripts/test_front_page_title_repair.py:/opt/scripts/test_front_page_title_repair.py:ro" \\
      -v "$(pwd)/scripts/test_dates_follow_the_class.py:/opt/scripts/test_dates_follow_the_class.py:ro" \\
      -v "$(pwd)/scripts/test_unreadable_page_settings.py:/opt/scripts/test_unreadable_page_settings.py:ro" \\
      quartz-teacher:dev-test python3 /opt/scripts/test_front_page_title_repair.py

(the other two are mounted for the helpers it shares with them). Windows'
`PythonToolchainTests` discovers it, and needs python-frontmatter 1.3.0 and
PyYAML 6.0.3 on that interpreter: what the build cannot read is the reader's.
"""
import contextlib
import io
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

import build_site
import contracts
import reference_course
import toolchain_paths
from test_dates_follow_the_class import _link_or_skip
from test_unreadable_page_settings import WORDS_THE_CONSOLE_MUST_NOT_SAY

WIZARD_PAGE = ("---\ntitle: Grade 12 Physics: Mechanics, Section 1\ncreated: 2026-09-02T08:00\n"
               "publish: true\n---\n\n![[Day 1]]\n")
WIZARD_PAGE_QUOTED = ("---\ntitle: \"Grade 12 Physics: Mechanics, Section 1\"\ncreated: 2026-09-02T08:00\n"
                      "publish: true\n---\n\n![[Day 1]]\n")
CONFIG = {"course_code": "SPH4U", "course_name": "Physics: Mechanics", "section_numbers": [1]}


def _use_the_repository_contracts() -> None:
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def _rule(*keys):
    _use_the_repository_contracts()
    return contracts.section("shared-rules", "buildRepairs", *keys)


def _read_exactly(path: Path) -> str:
    with open(path, "r", encoding="utf-8", newline="") as handle:
        return handle.read()


def _write_exactly(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def _filled(template: str, **values) -> str:
    filled = template
    for name, value in values.items():
        filled = filled.replace("{" + name + "}", str(value))
    return filled


def _copy_the_front_page(course_dir: Path, content_root: Path, frozen_course: bool) -> None:
    """The front page's copy, exactly as `build_section_site` makes it — or,
    against a build_site.py from before #584, the steps that file ran, so the
    failure is the behaviour and not a missing name."""
    copy_step = getattr(build_site, "copy_the_section_front_page", None)
    if copy_step is not None:
        copy_step(course_dir, course_dir / "section1", content_root, CONFIG, 1, False, "SPH4U", frozen_course)
        return
    section_index = course_dir / "section1" / "index.md"
    dest = content_root / "index.md"
    shutil.copy2(section_index, dest)
    build_site.remember_vault_source(dest, section_index, is_section_page=True)
    build_site.process_frontmatter(dest, 1)
    build_site.set_landing_title(dest, CONFIG, 1, False)


class FrontPageTitleRepairTests(unittest.TestCase):

    def setUp(self):
        _use_the_repository_contracts()
        self.root = Path(tempfile.mkdtemp(prefix="front-page-title-"))
        self.addCleanup(self._remove_the_scratch_folder)

    def _remove_the_scratch_folder(self):
        # A read-only page cannot be deleted on Windows until it is writable.
        for folder, _, files in os.walk(self.root):
            for name in files:
                try:
                    os.chmod(os.path.join(folder, name), stat.S_IREAD | stat.S_IWRITE)
                except OSError:
                    pass
        shutil.rmtree(self.root, ignore_errors=True)

    # ---- the course folder and one build of its front page ----

    def _course(self, page: str, kept_for_reference: bool = False, name: str = "SPH4U") -> Path:
        course_dir = self.root / "courses" / name
        _write_exactly(course_dir / "section1" / "index.md", page)
        config = dict(CONFIG)
        if kept_for_reference:
            config["kept_for_reference"] = True
            config["reference_school_year"] = 2025
        _write_exactly(course_dir / "course_config.json", json.dumps(config, indent=2))
        return course_dir

    def _build(self, course_dir: Path):
        """One build of the front page: what it printed, and whether the
        section was left without one."""
        content_root = Path(tempfile.mkdtemp(prefix="content-", dir=self.root))
        build_site.forget_vault_sources(course_dir)
        forget = getattr(build_site, "forget_unreadable_pages", None)
        if forget is not None:
            forget()
        frozen_course = reference_course.is_reference(course_dir) or reference_course.cannot_tell(course_dir)
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            _copy_the_front_page(course_dir, content_root, frozen_course)
        hidden = build_site._front_page_cannot_be_published(content_root)
        return printed.getvalue(), hidden, content_root

    def _marker_lines(self, printed: str) -> list:
        prefix = _rule("marker", "prefix")
        found = []
        for line in printed.splitlines():
            if prefix in line:
                found.append(line)
        return found

    def _assert_no_hidden_file_is_left(self, course_dir: Path):
        leftovers = []
        for entry in (course_dir / "section1").iterdir():
            if entry.name.startswith("."):
                leftovers.append(entry.name)
        self.assertEqual(leftovers, [], "the write's hidden file was left beside the page")

    def _assert_the_console_names_no_machinery(self, printed: str):
        for line in printed.splitlines():
            if line.startswith(_rule("marker", "prefix")):
                continue
            for word in WORDS_THE_CONSOLE_MUST_NOT_SAY:
                self.assertNotIn(word, line.lower(), line)

    # ---- the rule, case by case ----

    def test_every_case_in_the_contract(self):
        cases = _rule("frontPageTitleQuoted", "cases")
        self.assertEqual(len(cases), 23)
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(build_site._front_page_title_quoted(case["page"]), case["quoted"])

    def test_every_quoted_case_reads_and_changes_one_line(self):
        import frontmatter
        for case in _rule("frontPageTitleQuoted", "cases"):
            if case["quoted"] is None:
                continue
            with self.subTest(case=case["name"]):
                before = case["page"].splitlines(keepends=True)
                after = case["quoted"].splitlines(keepends=True)
                self.assertEqual(len(before), len(after))
                changed = 0
                for index in range(len(before)):
                    if before[index] != after[index]:
                        changed += 1
                self.assertEqual(changed, 1)
                page = self.root / (case["name"].replace(" ", "-") + ".md")
                _write_exactly(page, case["page"])
                with self.assertRaises(Exception):
                    frontmatter.load(page)
                _write_exactly(page, case["quoted"])
                frontmatter.load(page)

    # ---- the build ----

    def test_the_build_quotes_the_teachers_front_page_and_keeps_its_website(self):
        course_dir = self._course(WIZARD_PAGE)
        printed, hidden, content_root = self._build(course_dir)

        self.assertFalse(hidden, "the front page is still hidden, so the section has no website:\n" + printed)
        self.assertEqual(_read_exactly(course_dir / "section1" / "index.md"), WIZARD_PAGE_QUOTED)
        self.assertNotIn("🙈", printed)
        self._assert_no_hidden_file_is_left(course_dir)

        sentence = _filled(_rule("frontPageTitleQuoted", "sentence"), course="SPH4U", section=1)
        self.assertIn(sentence, printed.splitlines())
        markers = self._marker_lines(printed)
        self.assertEqual(len(markers), 1, printed)
        payload = json.loads(markers[0][len(_rule("marker", "prefix")):])
        self.assertEqual(payload, {"course": "SPH4U", "section": 1,
                                   "repair": "frontPageTitleQuoted", "page": "section1/index"})
        example = _rule("marker", "examples")[0]
        self.assertEqual(markers[0], example, "the line the build prints is the contract's example")
        self._assert_the_console_names_no_machinery(printed)

        # The landing title is worked out from the settings, as before.
        self.assertIn("Physics: Mechanics", _read_exactly(content_root / "index.md"))

    def test_a_second_build_changes_nothing_and_says_nothing(self):
        course_dir = self._course(WIZARD_PAGE)
        self._build(course_dir)
        page = course_dir / "section1" / "index.md"
        written = _read_exactly(page)
        written_at = os.stat(page).st_mtime_ns

        printed, hidden, _ = self._build(course_dir)
        self.assertFalse(hidden)
        self.assertEqual(_read_exactly(page), written)
        self.assertEqual(os.stat(page).st_mtime_ns, written_at)
        self.assertEqual(self._marker_lines(printed), [])
        self.assertNotIn("🔧", printed)

    def test_a_course_kept_for_reference_has_its_copy_quoted_and_its_page_left(self):
        course_dir = self._course(WIZARD_PAGE, kept_for_reference=True)
        self._assert_left_as_it_was(course_dir, "reference")

    def test_a_read_only_page_has_its_copy_quoted_and_is_left(self):
        course_dir = self._course(WIZARD_PAGE.replace("\n", "\r\n"))
        page = course_dir / "section1" / "index.md"
        os.chmod(page, stat.S_IREAD)
        self._assert_left_as_it_was(course_dir, "locked", original=WIZARD_PAGE.replace("\n", "\r\n"))

    def test_a_linked_page_has_its_copy_quoted_and_is_left(self):
        course_dir = self._course(WIZARD_PAGE)
        page = course_dir / "section1" / "index.md"
        elsewhere = self.root / "elsewhere" / "index.md"
        _write_exactly(elsewhere, WIZARD_PAGE)
        page.unlink()
        _link_or_skip(self, page, elsewhere)
        self._assert_left_as_it_was(course_dir, "linked")
        self.assertEqual(_read_exactly(elsewhere), WIZARD_PAGE, "a file outside the course was rewritten")

    def _assert_left_as_it_was(self, course_dir: Path, reason: str, original: str = WIZARD_PAGE):
        printed, hidden, content_root = self._build(course_dir)
        self.assertFalse(hidden, "the build's copy should be quoted, so the website keeps its front page:\n"
                         + printed)
        self.assertEqual(_read_exactly(course_dir / "section1" / "index.md"), original)
        self.assertEqual(self._marker_lines(printed), [], "only the copy was put right: nothing for the trail")
        sentence = _filled(_rule("frontPageTitleQuoted", "sentenceLeftAsItWas"), course="SPH4U", section=1,
                           reason=_rule("frontPageTitleQuoted", "reasons")[reason])
        self.assertIn(sentence, printed.splitlines())
        self.assertNotIn(_filled(_rule("frontPageTitleQuoted", "sentence"), course="SPH4U", section=1), printed)
        self._assert_no_hidden_file_is_left(course_dir)
        self._assert_the_console_names_no_machinery(printed)

    def test_a_page_saved_while_the_build_ran_is_kept_and_nothing_is_said(self):
        """The rewrite refused at its last step — here the page changed after
        it was read; Finder's Locked from the container, or a file held open
        on Windows, refuse it the same way: the copy is still quoted, and no
        sentence or trail line claims the page was put right."""
        course_dir = self._course(WIZARD_PAGE)
        page = course_dir / "section1" / "index.md"
        saved = WIZARD_PAGE + "A line the teacher typed meanwhile.\n"
        real_replace = build_site._replace_the_page_safely

        def obsidian_saves_first(source, original, rewritten, *arguments, **keywords):
            _write_exactly(page, saved)
            return real_replace(source, original, rewritten, *arguments, **keywords)

        build_site._replace_the_page_safely = obsidian_saves_first
        self.addCleanup(setattr, build_site, "_replace_the_page_safely", real_replace)
        printed, hidden, _ = self._build(course_dir)
        self.assertFalse(hidden, printed)
        self.assertEqual(_read_exactly(page), saved)
        self.assertEqual(self._marker_lines(printed), [])
        self.assertNotIn("🔧", printed)
        self._assert_no_hidden_file_is_left(course_dir)

    def test_a_shape_the_rule_refuses_is_hidden_as_before(self):
        page = "---\ntitle: Physics: Mechanics, Section 1\npublish: [oops\n---\n"
        course_dir = self._course(page)
        printed, hidden, _ = self._build(course_dir)
        self.assertTrue(hidden)
        self.assertIn("🙈 Hidden from students until its settings can be read: section1/index", printed)
        self.assertEqual(_read_exactly(course_dir / "section1" / "index.md"), page)
        self.assertEqual(self._marker_lines(printed), [])
        self.assertNotIn("🔧", printed)

    # ---- the words ----

    def test_the_fallbacks_are_the_contracts(self):
        self.assertEqual(build_site._FALLBACK_REPAIRED_PREFIX, _rule("marker", "prefix"))
        self.assertEqual(build_site._FALLBACK_TITLE_QUOTED_SENTENCE, _rule("frontPageTitleQuoted", "sentence"))
        self.assertEqual(build_site._FALLBACK_TITLE_LEFT_SENTENCE,
                         _rule("frontPageTitleQuoted", "sentenceLeftAsItWas"))
        self.assertEqual(build_site._FALLBACK_TITLE_LEFT_REASONS, _rule("frontPageTitleQuoted", "reasons"))

    def test_the_marker_is_kept_out_of_the_console(self):
        cases = contracts.section("shared-rules", "transcriptStripping", "machineLines", "cases")
        lines = []
        for case in cases:
            lines.append(case["line"])
        self.assertIn(_rule("marker", "examples")[0], lines)


if __name__ == "__main__":
    unittest.main(verbosity=2)
