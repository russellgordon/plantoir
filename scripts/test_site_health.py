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
            {"media_target_exists": False},
            {"section_index_exists": False},
            {"hand_written_coverage_page": True},
        ):
            broken = dict(HEALTHY)
            broken.update(facts)
            wired.update(_names(site_health.findings(broken, "ICS3U", 1)))

        in_contract = {entry["name"] for entry
                       in contracts.section("shared-rules", "siteHealth", "checks")}
        self.assertEqual(wired, in_contract,
                         "a check in the contract is not wired up, or vice versa")

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
