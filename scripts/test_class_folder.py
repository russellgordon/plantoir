#!/usr/bin/env python3
"""
The class-folder rule, run against the SHARED contract.

These cases are not retyped here — they are deserialised from
contracts/class-planning.json -> classFolder, the same data the macOS and
Windows suites run against their own implementations. That is the point: the
rule used to exist four times and disagree, and the build's disagreement
silently changed the Curriculum Coverage map from "pages the course teaches"
to "every published page" for any teacher whose folder was not called
"All Classes".

Run with:

    python3 scripts/test_class_folder.py
"""
import unittest
from pathlib import Path

import build_site
import contracts
import toolchain_paths


def _load_cases():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.section("class-planning", "classFolder")


class ClassFolderContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.contract = _load_cases()

    def test_naming_cases(self):
        cases = self.contract["naming"]["cases"]
        self.assertGreaterEqual(len(cases), 5, "the contract lost naming cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                config = {"per_section_folders": case["perSectionFolders"]}
                self.assertEqual(
                    build_site.class_folder_name(config), case["expect"],
                    case.get("why", ""))

    def test_is_class_page_cases(self):
        cases = self.contract["isClassPage"]["cases"]
        self.assertGreaterEqual(len(cases), 9, "the contract lost isClassPage cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(
                    build_site._is_class_page_path(
                        Path(case["path"]), case["classFolder"]),
                    case["expect"],
                    case.get("why", ""))


class RegressionsTheContractDescribes(unittest.TestCase):
    """
    The two bugs the rule was written to close, asserted directly rather than
    only through the case list — so that deleting a contract case cannot
    quietly delete the protection with it.
    """

    def test_a_shipped_page_named_for_a_class_is_not_a_lesson(self):
        for name in ("Setup/How This Class Works.md",
                     "Setup/Our Classroom Norms.md",
                     "Curriculum/B3. Connections Beyond the Classroom.md"):
            with self.subTest(page=name):
                self.assertFalse(
                    build_site._is_class_page_path(Path(name), "All Classes"))

    def test_the_path_above_the_content_root_cannot_matter(self):
        """
        The rule takes a RELATIVE path, which is what makes a teacher's own
        filing — `.../Classroom/plantoir/courses/...` — unable to reach it.
        """
        self.assertFalse(
            build_site._is_class_page_path(Path("Concepts/Loops.md"), "All Classes"))
        self.assertTrue(
            build_site._is_class_page_path(
                Path("All Classes/Unit 1, Day 1.md"), "All Classes"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
