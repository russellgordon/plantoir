#!/usr/bin/env python3
"""
Which folders count for marks, run against the SHARED contract.

The cases are deserialised from `contracts/shared-rules.json` -> gradedFolders,
never retyped. What they protect is a teacher's marks: an expectation counts as
ASSESSED when a page addressing it lives in one of these folders, and that is
what Ontario asks a course to be able to show.

`build_site` imports `frontmatter`, which lives only inside the container, so
this cannot run on the host. verify.sh runs it in the image.
"""
import unittest
from pathlib import Path

import build_site
import contracts
import setup_course
import toolchain_paths


class GradedFolderContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.contract = contracts.section("shared-rules", "gradedFolders")

    def test_every_case(self):
        cases = self.contract["cases"]
        self.assertGreaterEqual(len(cases), 9, "the contract lost graded-folder cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(
                    build_site._is_graded_path(
                        case["path"], case["graded"], case["configured"]),
                    case["expect"],
                    case.get("why", ""))


class AbsentIsNotEmpty(unittest.TestCase):
    """
    The distinction the whole migration rests on. Getting it wrong breaks
    courses in both directions: treating absent as empty takes every assessed
    mark off every existing course, and treating empty as absent ignores a
    teacher who deliberately cleared the list.
    """

    def test_absent_means_the_historical_rule(self):
        names, configured = build_site.graded_folder_names({})
        self.assertEqual(names, [])
        self.assertFalse(configured)
        self.assertTrue(build_site._is_graded_path("Tasks/x.md", names, configured))
        self.assertTrue(
            build_site._is_graded_path("Thinking Tasks/x.md", names, configured),
            "a course that counted 'Thinking Tasks' yesterday must count it today")

    def test_empty_means_the_teacher_said_none(self):
        names, configured = build_site.graded_folder_names({"graded_folders": []})
        self.assertEqual(names, [])
        self.assertTrue(configured)
        self.assertFalse(build_site._is_graded_path("Tasks/x.md", names, configured))

    def test_a_configured_pool_is_taken_literally(self):
        names, configured = build_site.graded_folder_names(
            {"graded_folders": ["Tasks", "Tests"]})
        self.assertEqual(names, ["Tasks", "Tests"])
        self.assertTrue(configured)
        self.assertTrue(build_site._is_graded_path("Tests/quiz.md", names, configured))
        self.assertFalse(build_site._is_graded_path("Thinking Tasks/x.md", names, configured))

    def test_an_explicit_null_reads_as_cleared_not_unset(self):
        """
        The key is PRESENT, so the teacher has been asked. Absent is reserved
        for a course that never was. Both platforms agreed on this by accident
        and nothing said which answer was intended.
        """
        names, configured = build_site.graded_folder_names({"graded_folders": None})
        self.assertEqual(names, [])
        self.assertTrue(configured)
        self.assertFalse(build_site._is_graded_path("Tasks/x.md", names, configured))

    def test_blank_entries_are_ignored_rather_than_matching_everything(self):
        names, configured = build_site.graded_folder_names(
            {"graded_folders": ["", "Tasks", None]})
        self.assertEqual(names, ["Tasks"])
        self.assertFalse(build_site._is_graded_path("Concepts/x.md", names, configured))


class HowThePageDescribesTheRule(unittest.TestCase):
    """
    The Curriculum Coverage page explains itself in prose, and that prose is
    read by a teacher deciding whether the map is right. It said "the Tasks
    folder" whatever they had chosen, which reads as a broken map.
    """

    def test_a_course_never_asked_is_described_by_what_actually_happens(self):
        words = build_site._graded_folders_in_words([], False)
        self.assertIn("task", words)
        # NOT "mentions tasks": the rule is the substring "task", so a folder
        # called "Task 1" counts and that wording would say it did not.
        self.assertNotIn("mentions tasks", words)

    def test_the_course_s_own_folders_are_named(self):
        self.assertEqual(build_site._graded_folders_in_words(["Tests"], True), "**Tests**")
        self.assertEqual(
            build_site._graded_folders_in_words(["Thinking Tasks", "Tasks"], True),
            "**Thinking Tasks** and **Tasks**")

    def test_a_cleared_pool_says_so(self):
        self.assertEqual(build_site._graded_folders_in_words([], True), "no folder at present")

    def test_a_folder_name_cannot_break_the_page(self):
        """These names are the teacher's own, and Markdown is not inert."""
        words = build_site._graded_folders_in_words(["Tasks*", "[[Quizzes]]"], True)
        self.assertNotIn("**Tasks***", words)
        self.assertNotIn("[[Quizzes]]", words)


class GradedFoldersForReconciliation(unittest.TestCase):
    """
    setup_course.graded_folders_for reconciles declared and inferred pools
    against the actual folder lists the course ends with.
    """

    def test_declared_pool_reconciles_against_actual_folders(self):
        manifest = {"graded_folders": ["Tasks"]}
        result = setup_course.graded_folders_for(manifest, ["Tasks", "Concepts"], ["All Classes"])
        self.assertEqual(result, ["Tasks"])

    def test_declared_pool_drops_removed_folders(self):
        manifest = {"graded_folders": ["Tasks"]}
        result = setup_course.graded_folders_for(manifest, ["Concepts", "Examples"], [])
        self.assertEqual(result, [])

    def test_declared_pool_preserves_per_section_graded_folder(self):
        manifest = {"graded_folders": ["Tasks", "Section Tasks"]}
        result = setup_course.graded_folders_for(manifest, ["Concepts"], ["Section Tasks"])
        self.assertEqual(result, ["Section Tasks"])

    def test_inferred_pool_finds_task_folders(self):
        result = setup_course.graded_folders_for(None, ["Thinking Tasks", "Concepts"], [])
        self.assertEqual(result, ["Thinking Tasks"])

    def test_inferred_pool_empty_when_no_task_folders(self):
        result = setup_course.graded_folders_for(None, ["Concepts", "Examples"], [])
        self.assertEqual(result, [])

    def test_manifest_with_explicit_none_graded_folders_returns_empty_list(self):
        manifest = {"graded_folders": None}
        result = setup_course.graded_folders_for(manifest, ["Tasks"], [])
        self.assertEqual(result, [], "explicit null means asked and answered none, not fallback to inferred tasks")

    def test_shared_or_per_section_folders_none_safe(self):
        manifest = {"graded_folders": ["Tasks"]}
        result = setup_course.graded_folders_for(manifest, None, None)
        self.assertEqual(result, [])

    def test_declared_pool_deduplicates_matching_folders(self):
        manifest = {"graded_folders": ["Tasks", "tasks", "Tasks"]}
        result = setup_course.graded_folders_for(manifest, ["Tasks"], [])
        self.assertEqual(result, ["Tasks"])


class HasGradedFoldersTests(unittest.TestCase):
    """
    build_site._has_graded_folders checks whether any folder in the merged
    tree counts for marks.
    """

    def test_configured_pool_finds_existing_folder(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Tasks").mkdir()
            self.assertTrue(build_site._has_graded_folders(root, ["Tasks"], True))
            self.assertTrue(build_site._has_graded_folders(root, ["tasks"], True))

    def test_configured_pool_returns_false_when_folder_missing(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Concepts").mkdir()
            self.assertFalse(build_site._has_graded_folders(root, ["Tasks"], True))

    def test_configured_empty_pool_returns_false(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Tasks").mkdir()
            self.assertFalse(build_site._has_graded_folders(root, [], True))

    def test_unconfigured_pool_finds_task_folder(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Thinking Tasks").mkdir()
            self.assertTrue(build_site._has_graded_folders(root, [], False))

    def test_unconfigured_pool_returns_false_when_no_task_folder(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Concepts").mkdir()
            self.assertFalse(build_site._has_graded_folders(root, [], False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
