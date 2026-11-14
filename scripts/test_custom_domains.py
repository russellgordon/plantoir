#!/usr/bin/env python3
"""
The one Python reader of a section's custom domains (#904) runs every case of
contracts/file-formats.json -> customDomainReading. The mac's
FileFormatsContractTests runs the same cases against
CourseConfiguration.customDomain(forSection:destinationType:).

build_site.py's own use of it (the address a build bakes in) is
scripts/test_build_site_domain_resolution.py, which needs the website
builder's Python; this file needs nothing but the standard library, so
verify.sh runs it on the host, early.

    python3 scripts/test_custom_domains.py
"""

import json
import sys
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

import custom_domains  # noqa: E402


def _the_rule() -> dict:
    with open(REPOSITORY_ROOT / "contracts" / "file-formats.json", encoding="utf-8") as handle:
        return json.load(handle)["customDomainReading"]


class EveryCaseOfTheContract(unittest.TestCase):

    def test_every_case(self):
        rule = _the_rule()
        self.assertGreater(len(rule["cases"]), 0)
        for case in rule["cases"]:
            with self.subTest(case=case["name"]):
                found = custom_domains.for_destination(case["config"], 1, case["destination"])
                self.assertEqual(found, case["expect"])

    def test_the_names_are_all_different(self):
        names = []
        for case in _the_rule()["cases"]:
            self.assertNotIn(case["name"], names)
            names.append(case["name"])

    def test_the_two_shapes_904_found_are_cases(self):
        """The issue's two faults stay pinned: a folder primary's bare
        string, and a wrong type that raised."""
        names = " ".join(case["name"] for case in _the_rule()["cases"])
        self.assertIn("a folder primary", names)
        self.assertIn("a list", names)
        self.assertIn("a number", names)


class TheSettingsThemselvesMayBeAnything(unittest.TestCase):
    """Not a course_config.json at all: still no domain, still no error."""

    def test_not_a_map(self):
        for config in (None, [], "netlify", 7):
            with self.subTest(config=config):
                self.assertEqual(custom_domains.for_destination(config, 1, "netlify"), "")

    def test_the_primary_of_a_course_with_no_settings_is_netlify(self):
        self.assertEqual(custom_domains.primary_destination_type({}), "netlify")
        self.assertEqual(custom_domains.primary_destination_type({"deploy_target": ""}), "netlify")
        self.assertEqual(custom_domains.primary_destination_type({"deploy_target": 3}), "netlify")
        self.assertEqual(custom_domains.primary_destination_type({"deploy_target": "local_folder"}),
                         "local_folder")


if __name__ == "__main__":
    unittest.main()
