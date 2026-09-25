#!/usr/bin/env python3
"""
The site-health checks, and the words they say.

Pure stdlib, no Docker and no network: `site_health` deliberately imports
nothing from `build_site` and touches no filesystem, so it can be tested
without building a site. The sentences are read from the SHARED contract
rather than retyped, which is the property that keeps the two apps from
wording the same problem differently.

Run with:

    python3 scripts/test_site_health.py
"""
import json
import unittest
from pathlib import Path

import contracts
import site_health
import toolchain_paths

HEALTHY = {
    "coverage_wanted": True,
    "curriculum_found": True,
    "class_pages_found": True,
    "graded_folders_found": True,
    "media_target_exists": True,
    "section_index_exists": True,
    "hand_written_coverage_page": False,
}


def _names(found) -> list:
    return [item.name for item in found]


class SiteHealthTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def test_a_healthy_course_says_nothing(self):
        """The one that matters most: no nagging on a course that is fine."""
        self.assertEqual(site_health.findings(dict(HEALTHY), "ICS3U", 1), [])

    def test_every_contract_check_can_actually_fire(self):
        """
        A check nobody can trigger is a sentence that will never be read. This
        walks the contract rather than a list written here, so adding a check
        to the contract without wiring it up fails.
        """
        wired = set()
        for facts in (
            {"curriculum_found": False},
            {"class_pages_found": False},
            {"graded_folders_found": False},
            {"media_target_exists": False},
            {"section_index_exists": False},
            {"hand_written_coverage_page": True},
            {"unreadable_pages": [{"page": "Concepts/Arrays", "line": 4}]},
        ):
            broken = dict(HEALTHY)
            broken.update(facts)
            wired.update(_names(site_health.findings(broken, "ICS3U", 1)))

        in_contract = {entry["name"] for entry
                       in contracts.section("shared-rules", "siteHealth", "checks")}
        self.assertEqual(wired, in_contract,
                         "a check in the contract is not wired up, or vice versa")

    def test_a_brand_new_course_is_not_nagged(self):
        """
        The failure mode this feature must not have.

        The wizard creates an empty curriculum folder AND an empty class folder
        and switches the map on, so on day one a perfectly healthy new course
        has neither expectations nor lessons. An unconditional pair of checks
        fired two non-fixable warnings on every build of a course nobody had
        broken, with no way to silence them short of turning off a feature the
        teacher had just enabled.
        """
        fresh = dict(HEALTHY)
        fresh["curriculum_found"] = False
        fresh["class_pages_found"] = False
        self.assertEqual(site_health.findings(fresh, "ICS3U", 1), [])

    def test_each_half_of_the_map_complains_only_when_the_other_exists(self):
        """
        Complain that the expectations are missing once there are lessons, and
        that the lessons are missing once there are expectations. Either way
        round, the teacher is told about something they can act on.
        """
        lost_curriculum = dict(HEALTHY)
        lost_curriculum["curriculum_found"] = False
        self.assertEqual(_names(site_health.findings(lost_curriculum, "ICS3U", 1)),
                         ["curriculumCoverageFoundNothing"])

        lost_classes = dict(HEALTHY)
        lost_classes["class_pages_found"] = False
        self.assertEqual(_names(site_health.findings(lost_classes, "ICS3U", 1)),
                         ["courseTeachesNothing"])

    def test_the_checks_can_never_break_the_build_they_are_checking(self):
        """
        This is the first code in a build that MUST read a contract at run
        time, and contracts.load deliberately raises rather than guessing. A
        stale PLANTOIR_CONTRACTS_DIR or an older pinned image would otherwise
        kill a build that used to succeed, AFTER the content merge. A health
        check that destroys the build it was checking is worse than the silent
        failure it replaces.
        """
        original = toolchain_paths.CONTRACTS_DIR
        toolchain_paths.CONTRACTS_DIR = Path("/nowhere/at/all")
        contracts.reset_cache()
        try:
            lines = []
            site_health.announce_or_stay_quiet(dict(HEALTHY), "ICS3U", 1, printer=lines.append)
            self.assertEqual(len(lines), 1)
            self.assertIn("Skipped the folder checks", lines[0])
        finally:
            toolchain_paths.CONTRACTS_DIR = original
            contracts.reset_cache()

    def test_the_curriculum_check_is_silent_when_the_map_is_switched_off(self):
        facts = dict(HEALTHY)
        facts["coverage_wanted"] = False
        facts["curriculum_found"] = False
        facts["class_pages_found"] = False
        self.assertEqual(site_health.findings(facts, "ICS3U", 1), [],
                         "a course that switched the map off must not be nagged about it")

    def test_the_sentence_names_the_course_and_section(self):
        facts = dict(HEALTHY)
        facts["curriculum_found"] = False
        found = site_health.findings(facts, "ADA1O", 3)[0]
        self.assertIn("ADA1O", found.sentence)
        self.assertIn("3", found.sentence)
        self.assertNotIn("{course}", found.sentence)
        self.assertNotIn("{section}", found.sentence)

    def test_the_curriculum_finding_is_not_offered_as_fixable(self):
        """
        The check that must never grow a Fix button. Recreating an empty
        folder satisfies an existence check while leaving the map missing —
        it would silence the warning and fix nothing.
        """
        facts = dict(HEALTHY)
        facts["curriculum_found"] = False
        self.assertFalse(site_health.findings(facts, "ICS3U", 1)[0].fixable)

    def test_a_missing_index_and_a_missing_media_folder_are_fixable(self):
        facts = dict(HEALTHY)
        facts["section_index_exists"] = False
        facts["media_target_exists"] = False
        for item in site_health.findings(facts, "ICS3U", 1):
            self.assertTrue(item.fixable, item.name)

    def test_the_graded_folders_check_fires_when_pool_is_missing(self):
        facts = dict(HEALTHY)
        facts["graded_folders_found"] = False
        found = site_health.findings(facts, "ICS3U", 1)
        self.assertEqual(_names(found), ["noGradedFolders"])
        self.assertIn("ICS3U", found[0].sentence)
        self.assertIn("1", found[0].sentence)

    def test_the_graded_folders_check_is_silent_when_the_map_is_switched_off(self):
        facts = dict(HEALTHY)
        facts["coverage_wanted"] = False
        facts["graded_folders_found"] = False
        self.assertEqual(site_health.findings(facts, "ICS3U", 1), [],
                         "a course with the map off must not be warned about marks folders")

    def test_the_graded_folders_finding_is_not_offered_as_fixable(self):
        facts = dict(HEALTHY)
        facts["graded_folders_found"] = False
        self.assertFalse(site_health.findings(facts, "ICS3U", 1)[0].fixable)


class TheContractsExampleLinesAreRealOutput(unittest.TestCase):
    """
    The contract carries EXAMPLE marker lines, and the apps parse those to prove
    they can read what this module writes.

    That only means anything if the examples are what the module still produces.
    An adversarial review pointed out that the Swift test was round-tripping a
    dictionary Swift had built ITSELF — so a change here (section emitted as a
    string, a renamed key, a different separator) would have gone unnoticed on
    both platforms while findings silently stopped being read.
    """

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def test_the_examples_match_what_this_module_emits(self):
        facts = {"coverage_wanted": True, "curriculum_found": False,
                 "class_pages_found": True, "media_target_exists": False,
                 "section_index_exists": True, "hand_written_coverage_page": False,
                 "unreadable_pages": [{"page": "Concepts/Arrays", "line": 4},
                                      {"page": "section1/Unit 1/Day 3", "line": None}]}
        lines = []
        site_health.announce(site_health.findings(facts, "ICS3U", 1), printer=lines.append)
        emitted = [line for line in lines if line.startswith(site_health.marker_prefix())]

        examples = contracts.section("shared-rules", "siteHealth", "marker", "examples")
        self.assertEqual(
            emitted, examples,
            "the marker lines this module writes no longer match the examples in "
            "the contract that the apps are tested against. Regenerate the "
            "examples deliberately — the apps parse them to prove they can read "
            "real output."
        )

    def test_an_example_carries_the_types_the_apps_expect(self):
        """`section` in particular: the apps read it as a number."""
        for line in contracts.section("shared-rules", "siteHealth", "marker", "examples"):
            payload = json.loads(line[len(site_health.marker_prefix()):].strip())
            self.assertIsInstance(payload["name"], str)
            self.assertIsInstance(payload["sentence"], str)
            self.assertIsInstance(payload["detail"], str)
            self.assertIsInstance(payload["fixable"], bool)
            self.assertIsInstance(payload["course"], str)
            self.assertIsInstance(payload["section"], int)


class UnreadablePageSettingsTests(unittest.TestCase):
    """
    `pageSettingsUnreadable` (#246): ONE finding per section build naming every
    page the build hid because it could not read its settings. The words are
    the contract's; these check how they are put together.
    """

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        for entry in contracts.section("shared-rules", "siteHealth", "checks"):
            if entry["name"] == "pageSettingsUnreadable":
                cls.entry = entry

    def found(self, pages, front_page=False):
        facts = dict(HEALTHY)
        facts["unreadable_pages"] = pages
        facts["front_page_unreadable"] = front_page
        found = site_health.findings(facts, "ICS3U", 1)
        self.assertEqual(_names(found), ["pageSettingsUnreadable"], "one finding, never one per page")
        return found[0]

    def expected(self, key, **fill):
        return site_health.filled(self.entry[key], dict({"course": "ICS3U", "section": "1"}, **fill))

    def test_one_page_is_named_in_the_sentence(self):
        item = self.found([{"page": "Concepts/Arrays", "line": 4}])
        self.assertEqual(item.sentence, self.expected("sentence", page="Concepts/Arrays"))
        self.assertIn(self.expected("pageWithLine", page="Concepts/Arrays", line="4"), item.detail)
        self.assertFalse(item.fixable)

    def test_a_page_with_no_line_is_named_without_one(self):
        item = self.found([{"page": "Concepts/Arrays", "line": None}])
        self.assertIn(self.expected("pageWithoutLine", page="Concepts/Arrays"), item.detail)
        self.assertNotIn(self.expected("pageWithLine", page="Concepts/Arrays", line="None"), item.detail)

    def test_several_pages_are_counted_in_the_sentence(self):
        item = self.found([{"page": "A", "line": 2}, {"page": "B", "line": None}])
        self.assertEqual(item.sentence, self.expected("sentenceForSeveral", count="2"))
        self.assertIn(self.expected("pageWithLine", page="A", line="2") + ", "
                      + self.expected("pageWithoutLine", page="B"), item.detail)

    def test_eleven_pages_name_ten_and_count_the_rest(self):
        pages = [{"page": f"Page {number:02d}", "line": None} for number in range(11)]
        item = self.found(pages)
        for number in range(10):
            self.assertIn(f"Page {number:02d}", item.detail)
        self.assertNotIn("Page 10", item.detail)
        self.assertIn(self.expected("andMore", count="1"), item.detail)

    def test_the_front_page_says_what_it_costs(self):
        item = self.found([{"page": "section1/index", "line": 3}], front_page=True)
        self.assertTrue(item.detail.endswith(self.expected("frontPage")))
        self.assertNotIn(self.expected("frontPage"),
                         self.found([{"page": "Concepts/Arrays", "line": 3}]).detail)

    def test_nothing_is_left_unfilled_and_the_detail_is_one_line(self):
        item = self.found([{"page": "A", "line": 2}, {"page": "B", "line": None}], front_page=True)
        for text in (item.sentence, item.detail):
            self.assertNotIn("{", text)
            self.assertNotIn("}", text)
            self.assertNotIn("\n", text)

    def test_a_page_named_with_braces_is_named_as_it_is(self):
        """A teacher can name a page "{course} notes"; one pass never re-reads
        what it has just put in, so it is not expanded into the course code."""
        item = self.found([{"page": "{course} notes", "line": None}])
        self.assertIn("{course} notes", item.sentence)
        self.assertIn("{course} notes", item.detail)
        self.assertNotIn("ICS3U notes", item.sentence + item.detail)
        several = self.found([{"page": "{section}", "line": 2}, {"page": "{pages}", "line": None}])
        self.assertIn("{section}", several.detail)
        self.assertIn("{pages}", several.detail)
        # Placeholders filled AFTER the page name are the ones a replacement
        # made one after another would expand: {pages} in the sentence, and
        # {line} in the page's own entry.
        self.assertIn("{pages}", self.found([{"page": "{pages}", "line": None}]).sentence)
        named_line = self.found([{"page": "{line}", "line": 7}])
        self.assertIn("{line}", named_line.detail)
        self.assertNotIn(self.expected("pageWithLine", page="7", line="7"), named_line.detail)

    def test_no_word_of_it_names_the_machinery(self):
        for key, value in self.entry.items():
            if key in ("name", "why", "fill") or not isinstance(value, str):
                continue
            for word in ("toolchain", "script", "docker", "container", "wsl", "python",
                         "json", "stdout", "quartz", "repository", "config", "yaml",
                         "frontmatter", "symlink", "vault"):
                self.assertNotIn(word, value.lower(), f"{key} says {word!r}")


class MarkerLineTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def test_each_finding_emits_one_parseable_line(self):
        facts = dict(HEALTHY)
        facts["curriculum_found"] = False
        facts["media_target_exists"] = False
        lines = []
        site_health.announce(site_health.findings(facts, "ICS3U", 2), printer=lines.append)

        prefix = site_health.marker_prefix()
        machine = [line for line in lines if line.startswith(prefix)]
        self.assertEqual(len(machine), 2)
        for line in machine:
            payload = json.loads(line[len(prefix):].strip())
            self.assertEqual(payload["course"], "ICS3U")
            self.assertEqual(payload["section"], 2)
            self.assertTrue(payload["sentence"])
            self.assertIn("fixable", payload)

    def test_a_healthy_course_prints_nothing_at_all(self):
        lines = []
        site_health.announce(site_health.findings(dict(HEALTHY), "ICS3U", 1), printer=lines.append)
        self.assertEqual(lines, [])

    def test_the_marker_survives_a_sentence_with_a_newline_in_it(self):
        """
        The apps parse these out of a line-based transcript, so the JSON must
        be one line whatever the wording contains.
        """
        item = site_health.Finding("x", "a\nb", "c\nd", False, "ICS3U", 1)
        lines = []
        site_health.announce([item], printer=lines.append)
        machine = [line for line in lines if line.startswith(site_health.marker_prefix())]
        self.assertEqual(len(machine), 1)
        self.assertEqual(len(machine[0].split("\n")), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
