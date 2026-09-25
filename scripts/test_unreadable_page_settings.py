#!/usr/bin/env python3
"""
A page whose settings the build cannot read is HIDDEN, and named (GitHub #246).

The cases are not retyped here: they are deserialised from
contracts/shared-rules.json -> unreadablePageSettings.cases, and each is run
through the build's own `process_frontmatter`, the way `build_section_site`
runs every page it copies. What the SITE then does with the result is held by
`build_site._is_draft`, which `check_visibility_against_the_site.py` keeps in
agreement with the site; that file also runs these cases down the rest of the
chain, through Quartz's own reader.

The words a teacher reads are `siteHealth.checks[pageSettingsUnreadable]`, and
`test_site_health.py` covers them. This covers the rule, the line, the console,
the front page, and the two ways hiding can fail.

`build_site` imports `frontmatter`, which lives only inside the container on
the mac, so this CANNOT be run on the mac host. verify.sh runs it in the image:

    docker run --rm -v "$(pwd)/scripts/test_unreadable_page_settings.py:/opt/scripts/test_unreadable_page_settings.py:ro" \
      quartz-teacher:dev-test python3 /opt/scripts/test_unreadable_page_settings.py

Windows' `PythonToolchainTests` discovers it, and needs python-frontmatter
1.3.0 and PyYAML 6.0.3 on that interpreter: the line numbers are the reader's.
"""
import contextlib
import io
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

import build_site
import contracts
import toolchain_paths

# Words that would mean the console is quoting the reader or naming the
# machinery. The console goes into problem reports.
WORDS_THE_CONSOLE_MUST_NOT_SAY = ["frontmatter", "yaml", "error", "exception", "traceback", "could not read frontmatter"]


def _use_the_repository_contracts() -> None:
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def _cases() -> list:
    _use_the_repository_contracts()
    return contracts.section("shared-rules", "unreadablePageSettings", "cases")


def _read_exactly(path: Path) -> str:
    with open(path, "r", encoding="utf-8", newline="") as handle:
        return handle.read()


def _write_exactly(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def _body_below_the_settings(text: str) -> str:
    """What follows the closing fence, line endings and all."""
    import frontmatter
    _, body = frontmatter.YAMLHandler().split(text)
    return body


def _forget() -> None:
    forget = getattr(build_site, "forget_unreadable_pages", None)
    if forget is not None:
        forget()


def _unreadable() -> list:
    """The build's record, or an empty one on a build from before it."""
    return list(getattr(build_site, "_unreadable_pages", []))


class Build:
    """One page laid out as a teacher's course and copied the way
    `build_section_site` copies it: the teacher's file, the build's copy, and
    the record of where the copy came from."""

    # MARK: - Initializer

    def __init__(self, root: Path, relative: str):
        self.course = root / "courses" / "TEST"
        self.content = root / "content"
        self.source = self.course / relative
        self.copy = self.content / relative.split("/", 1)[-1] if relative.startswith("section") else self.content / relative
        build_site.forget_vault_sources(self.course)
        _forget()

    # MARK: - Functions

    def run(self, text: str, section: int = 1) -> str:
        """Writes the page, copies it, processes the copy, returns what was printed."""
        _write_exactly(self.source, text)
        self.copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(self.source, self.copy)
        build_site.remember_vault_source(self.copy, self.source, is_section_page=True)
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            build_site.process_frontmatter(self.copy, section)
        return printed.getvalue()


class TheContractCases(unittest.TestCase):

    def test_every_case(self):
        cases = _cases()
        self.assertGreaterEqual(len(cases), 18, "the contract lost cases")
        for case in cases:
            with self.subTest(case["name"]), tempfile.TemporaryDirectory() as folder:
                build = Build(Path(folder), "Concepts/Arrays.md")
                printed = build.run(case["page"], case["section"])
                after = _read_exactly(build.copy)

                self.assertEqual(
                    build_site._is_draft(after), case["expectHidden"],
                    f"the site would {'show' if case['expectHidden'] else 'hide'} it; "
                    f"the build's copy reads {after!r}",
                )
                self.assertEqual(_read_exactly(build.source), case["page"],
                                 "the teacher's own file was changed")

                recorded = _unreadable()
                if case["expectReadable"]:
                    self.assertEqual(recorded, [], "a page the build can read was recorded as unreadable")
                    self.assertNotIn("🙈", printed)
                    continue

                self.assertEqual(len(recorded), 1, "an unreadable page was not recorded")
                copy, name, line = recorded[0]
                self.assertEqual(copy, build.copy)
                self.assertEqual(name, "Concepts/Arrays", "the page is named by its place in the course folder")
                self.assertEqual(line, case["expectLine"], "the line the reader stopped near")
                self.assertEqual(_body_below_the_settings(after), _body_below_the_settings(case["page"]),
                                 "the body below the settings changed")

                self.assertIn("Concepts/Arrays", printed, "the console does not name the page")
                if case["expectLine"] is not None:
                    self.assertIn(f"near line {case['expectLine']}", printed)
                lowered = printed.lower()
                for word in WORDS_THE_CONSOLE_MUST_NOT_SAY:
                    self.assertNotIn(word, lowered, f"the console says {word!r}")
                settings = case["page"].replace("\r\n", "\n").replace("\r", "\n").split("\n")
                for setting in settings[1:]:
                    words = setting.strip()
                    if words and words != "---" and len(words) > 3:
                        self.assertNotIn(words, printed, "the console quotes the page's own settings")

    def test_a_second_build_of_the_same_page_hides_it_the_same_way(self):
        # The copy is made afresh from the teacher's file on every build, so
        # this is what every build after the first does.
        for case in _cases():
            if case["expectReadable"]:
                continue
            with self.subTest(case["name"]), tempfile.TemporaryDirectory() as folder:
                build = Build(Path(folder), "Concepts/Arrays.md")
                build.run(case["page"], case["section"])
                first = _read_exactly(build.copy)
                _forget()
                build.run(case["page"], case["section"])
                self.assertEqual(_read_exactly(build.copy), first)
                self.assertEqual(len(_unreadable()), 1)


class WhenHidingItselfIsHard(unittest.TestCase):

    UNREADABLE = "---\npublishForSection1: true\nyes: value\n---\nBody\n"

    def test_a_page_that_is_not_utf8_is_hidden_and_named(self):
        with tempfile.TemporaryDirectory() as folder:
            build = Build(Path(folder), "Concepts/Arrays.md")
            build.source.parent.mkdir(parents=True, exist_ok=True)
            build.source.write_bytes(b"---\npublishForSection1: true\ntitle: caf\xe9\n---\nBody\n")
            build.copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(build.source, build.copy)
            build_site.remember_vault_source(build.copy, build.source, is_section_page=True)
            with contextlib.redirect_stdout(io.StringIO()):
                build_site.process_frontmatter(build.copy, 1)
            self.assertTrue(build_site._is_draft(_read_exactly(build.copy)))
            self.assertEqual(len(_unreadable()), 1)

    def test_a_copy_that_cannot_be_rewritten_is_removed(self):
        # Mocked rather than made read-only: the image runs as root, which
        # writes through any mode, and NTFS ignores a folder's mode — so a
        # chmod-based test would run nowhere at all.
        with tempfile.TemporaryDirectory() as folder:
            build = Build(Path(folder), "Concepts/Arrays.md")
            real_open = open

            def refusing_open(path, mode="r", *args, **kwargs):
                if "w" in mode and Path(path) == build.copy:
                    raise PermissionError("refused for the test")
                return real_open(path, mode, *args, **kwargs)

            build_site.open = refusing_open
            try:
                build.run(self.UNREADABLE)
            finally:
                del build_site.open
            self.assertFalse(build.copy.exists(), "a page that could not be hidden was left in the site")
            self.assertEqual(len(_unreadable()), 1, "the removed page was not named")

    def test_a_copy_that_can_be_neither_rewritten_nor_removed_stops_the_build(self):
        with tempfile.TemporaryDirectory() as folder:
            build = Build(Path(folder), "Concepts/Arrays.md")
            real_open = open
            real_unlink = os.unlink

            def refusing_open(path, mode="r", *args, **kwargs):
                if "w" in mode and Path(path) == build.copy:
                    raise PermissionError("refused for the test")
                return real_open(path, mode, *args, **kwargs)

            def refusing_unlink(path, *args, **kwargs):
                if Path(path) == build.copy:
                    raise PermissionError("refused for the test")
                return real_unlink(path, *args, **kwargs)

            build_site.open = refusing_open
            os.unlink = refusing_unlink
            try:
                with self.assertRaises(SystemExit) as stopped:
                    build.run(self.UNREADABLE)
            finally:
                del build_site.open
                os.unlink = real_unlink
            self.assertEqual(stopped.exception.code, 1)


class TheFrontPage(unittest.TestCase):

    FRONT_PAGE = "---\npublishForSection1: true\ntitle: \"a\"b\"\n---\n# Welcome\n"

    def facts(self, content: Path) -> dict:
        return {
            "section_index_exists": ((content / "index.md").exists()
                                     or build_site._front_page_cannot_be_published(content)),
            "front_page_unreadable": build_site._front_page_cannot_be_published(content),
            "unreadable_pages": build_site._unreadable_page_facts(),
        }

    def test_an_unreadable_front_page_is_hidden_named_and_clears_the_last_site(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            build = Build(root, "section1/index.md")
            build.run(self.FRONT_PAGE)
            facts = self.facts(build.content)
            self.assertTrue(facts["front_page_unreadable"])
            self.assertTrue(facts["section_index_exists"],
                            "a hidden front page is THERE: 'has no front page' and its repair must not fire")
            self.assertEqual(facts["unreadable_pages"], [{"page": "section1/index", "line": 3}])

            host = root / "host"
            (host / "public").mkdir(parents=True)
            (host / "public" / "index.html").write_text("last week's", encoding="utf-8")
            printed = io.StringIO()
            with contextlib.redirect_stdout(printed):
                build_site._clear_a_site_this_build_cannot_replace(facts, host, "ICS3U", 1)
            self.assertFalse((host / "public").exists(), "the last built site would go out stale")
            self.assertNotIn("without a front page", printed.getvalue())

    def test_a_readable_front_page_leaves_the_last_site_alone(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            build = Build(root, "section1/index.md")
            build.run("---\ntitle: Welcome\n---\n# Welcome\n")
            host = root / "host"
            (host / "public").mkdir(parents=True)
            with contextlib.redirect_stdout(io.StringIO()):
                build_site._clear_a_site_this_build_cannot_replace(self.facts(build.content), host, "ICS3U", 1)
            self.assertTrue((host / "public").exists())

    def test_a_front_page_whose_copy_had_to_be_removed_is_still_not_missing(self):
        with tempfile.TemporaryDirectory() as folder:
            build = Build(Path(folder), "section1/index.md")
            real_open = open

            def refusing_open(path, mode="r", *args, **kwargs):
                if "w" in mode and Path(path) == build.copy:
                    raise PermissionError("refused for the test")
                return real_open(path, mode, *args, **kwargs)

            build_site.open = refusing_open
            try:
                build.run(self.FRONT_PAGE)
            finally:
                del build_site.open
            facts = self.facts(build.content)
            self.assertFalse(build.copy.exists())
            self.assertTrue(facts["section_index_exists"])
            self.assertTrue(facts["front_page_unreadable"])

    def test_what_a_publish_says_is_what_the_app_explains(self):
        """Every `failureExplanations` case about the unreadable front page
        must be what the build actually prints, or the app's explanation is
        matching a line nobody prints."""
        _use_the_repository_contracts()
        cases = contracts.section("app-rules", "failureExplanations", "cases")
        facts = {"front_page_unreadable": True, "section_index_exists": True}
        printed = {
            "\n".join(build_site._nothing_to_publish("ICS3U", 1, facts, 3)),
            "\n".join(build_site._nothing_to_publish("ICS3U", 1, facts, None)),
        }
        matched = 0
        for case in cases:
            if "front page could not be read" not in case["output"]:
                continue
            matched += 1
            first_lines = "\n".join(case["output"].split("\n")[:2])
            self.assertIn(first_lines, printed, case["output"])
        self.assertGreaterEqual(matched, 3)

        missing = "\n".join(build_site._nothing_to_publish(
            "ICS3U", 1, {"front_page_unreadable": False, "section_index_exists": False}, None))
        self.assertNotIn("could not be read", missing)
        for text in printed:
            self.assertNotIn("no front page, so no website was produced", text,
                             "the app would read it as the MISSING front page")


if __name__ == "__main__":
    unittest.main(verbosity=2)
