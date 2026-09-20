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

`build_site` imports `frontmatter`, which lives only inside the container, so
this CANNOT be run on the host. verify.sh runs it in the image:

    docker run --rm -v "$(pwd)/scripts/test_class_folder.py:/opt/scripts/test_class_folder.py:ro" \
      quartz-teacher:dev-test python3 /opt/scripts/test_class_folder.py

Reading the contract from the image's own /opt/contracts is deliberate: it makes
this the end-to-end check that the contract really travels with the toolchain,
not just that the rule is right.
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
        self.assertGreaterEqual(len(cases), 10, "the contract lost naming cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                # A case with no `classFolder` is a course that has never
                # recorded one, which is every course made before the key
                # existed. Those must go on getting the old guess.
                config = {"per_section_folders": case["perSectionFolders"]}
                if case.get("classFolder"):
                    config["class_folder"] = case["classFolder"]
                self.assertEqual(
                    build_site.class_folder_name(config), case["expect"],
                    case.get("why", ""))

    def test_membership_cases(self):
        cases = self.contract["membership"]["cases"]
        self.assertGreaterEqual(len(cases), 6, "the contract lost membership cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                config = {"per_section_folders": case["perSectionFolders"]}
                if case.get("classFolder"):
                    config["class_folder"] = case["classFolder"]
                self.assertEqual(
                    build_site.class_folder_names(config), case["expect"],
                    case.get("why", ""))

    def test_is_class_page_cases(self):
        cases = self.contract["isClassPage"]["cases"]
        self.assertGreaterEqual(len(cases), 12, "the contract lost isClassPage cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(
                    build_site._is_class_page_path(
                        case["path"], case["classFolders"]),
                    case["expect"],
                    case.get("why", ""))


class RegressionsTheContractDescribes(unittest.TestCase):
    """
    The two bugs the rule was written to close, asserted directly rather than
    only through the case list — so that deleting a contract case cannot
    quietly delete the protection with it.
    """

    def test_a_page_is_never_a_lesson_because_of_its_NAME(self):
        """
        Defence in depth, and labelled as such: under segment EQUALITY these
        could not match anyway. The test exists so that a future change to
        prefix or substring matching fails here rather than quietly
        reclassifying shipped content.
        """
        for name in ("Setup/How This Class Works.md",
                     "Setup/Our Classroom Norms.md",
                     "Curriculum/B3. Connections Beyond the Classroom.md",
                     "All Classes.md"):
            with self.subTest(page=name):
                self.assertFalse(
                    build_site._is_class_page_path(name, ["All Classes"]))

    def test_a_working_folder_named_for_classes_cannot_reach_the_rule(self):
        """
        The REAL bug this closes on the Python side, tested where it lives.

        The old rule walked `page.parts` of an ABSOLUTE path — `content_root`
        is absolute, so `rglob` yields absolute paths — which meant a teacher
        whose working folder was `~/Documents/All Classes` made every page in
        every course a lesson. The rule itself is a pure segment matcher and
        cannot know what is above the content root; what protects it is the
        CALLER passing `relative_to(content_root)`, so that is what this
        exercises.
        """
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            # The content root itself lives inside a folder named for classes.
            content_root = Path(temp) / "All Classes" / "courses" / "ICS3U" / "content"
            (content_root / "Concepts").mkdir(parents=True)
            (content_root / "Concepts" / "Loops.md").write_text("# Loops", encoding="utf-8")

            taught = build_site._pages_the_course_teaches(content_root, ["All Classes"])
            self.assertIsNone(
                taught,
                "a page under a WORKING FOLDER named 'All Classes' is not a lesson; "
                "the old rule read the whole absolute path and thought it was"
            )

            # And a real class page in a real class folder still counts.
            (content_root / "All Classes").mkdir()
            (content_root / "All Classes" / "Unit 1, Day 1.md").write_text(
                "# Day 1", encoding="utf-8")
            taught = build_site._pages_the_course_teaches(content_root, ["All Classes"])
            self.assertIsNotNone(taught)
            self.assertIn("Unit 1, Day 1", taught)

    def test_two_class_folders_both_count(self):
        """
        The regression the membership rule exists to prevent: first-match-wins
        naming plus equality matching would resolve ["Class Resources",
        "All Classes"] to the first, match zero pages, and drop the coverage
        map back to "every published page".
        """
        config = {"per_section_folders": ["Class Resources", "All Classes"]}
        self.assertEqual(build_site.class_folder_name(config), "Class Resources")
        self.assertEqual(build_site.class_folder_names(config),
                         ["Class Resources", "All Classes"])
        self.assertTrue(build_site._is_class_page_path(
            "All Classes/Unit 1, Day 1.md", build_site.class_folder_names(config)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
