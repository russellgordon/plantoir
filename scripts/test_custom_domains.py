#!/usr/bin/env python3
"""
The one Python reader of a section's custom domains (#904) runs every case of
contracts/file-formats.json -> customDomainReading. The mac's
FileFormatsContractTests runs the same cases against
CourseConfiguration.customDomain(forSection:destinationType:).

deploy.py's per-destination reader, leg_custom_domain, asks it too and runs
every case here (DeployAsksTheSameReader). build_site.py's own use of it (the
address a build bakes in) is
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


class DeployAsksTheSameReader(unittest.TestCase):
    """deploy.py's per-destination reader, `leg_custom_domain` (#799), asks
    custom_domains.for_destination rather than keeping its own copy. At the
    join of #799 and #904 the two bodies differed on 4 of 24 shapes (the
    Fable sweep of the deploy-freshness batch, two of them contract cases),
    so every case runs through it as well, from a real course_config.json."""

    def test_every_case_through_deploy(self):
        import tempfile
        import deploy  # noqa: E402  (imported here: it is the larger module)
        for case in _the_rule()["cases"]:
            for section in (1, "1"):
                with self.subTest(case=case["name"], section=section):
                    with tempfile.TemporaryDirectory() as folder:
                        (Path(folder) / "course_config.json").write_text(
                            json.dumps(case["config"]), encoding="utf-8")
                        found = deploy.leg_custom_domain(Path(folder), section, case["destination"])
                    self.assertEqual(found, deploy.clean_base_url(case["expect"]))

    def test_deploy_reads_the_key_nowhere_else(self):
        source = (REPOSITORY_ROOT / "scripts" / "deploy.py").read_text(encoding="utf-8")
        self.assertNotIn('.get("custom_domains")', source)
        self.assertIn("custom_domains.for_destination(", source)
        build = (REPOSITORY_ROOT / "scripts" / "build_site.py").read_text(encoding="utf-8")
        self.assertNotIn('config.get("deploy_target") or "netlify"', build,
                         "the primary is asked one way: custom_domains.primary_destination_type")


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
