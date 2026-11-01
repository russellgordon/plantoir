#!/usr/bin/env python3
"""Course setup and the destination a course deploys to (GitHub #668).

A NEW course deploys to Cloudflare Pages wherever it is made (Russell,
2026-11-01: "Cloudflare everywhere"): both apps' new-course windows write
`deploy_target: cloudflare_pages`, and course setup at the command line
writes the same when there is no saved file at all.

Two other halves are pinned with it:
- a re-run keeps the destination a saved file names (the apps write the
  file, then run setup over it), and
- a re-run over a saved file that names NO destination writes none - that
  course was made before the other destinations existed and deploys to
  Netlify, and must keep doing so (publishingDestinations.whyTheyDiffer).

The runs are the real one, `setup_course.setup_course`, driven exactly as
test_graded_folders_rerun.py and test_graded_folders_new_course.py drive it,
whose harnesses it borrows. Listed in verify.sh; Windows' PythonToolchainTests
discovers it.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import setup_course  # noqa: E402
import test_graded_folders_new_course as new_course_harness  # noqa: E402
import test_graded_folders_rerun as rerun_harness  # noqa: E402
import toolchain_paths  # noqa: E402


def a_saved_course(saved: dict) -> dict:
    return {
        "name": "deploy target",
        "directories": [],
        "sharedFolders": [],
        "perSectionFolders": [],
        "saved": saved,
    }


class SetupKeepsTheDestination(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()

    def rerun_setup(self, saved: dict) -> dict:
        return rerun_harness.SetupRerunKeepsTheMarksPool.rerun_setup(self, a_saved_course(saved))

    def test_a_new_course_written_for_cloudflare_stays_on_cloudflare(self):
        written = self.rerun_setup({"deploy_target": "cloudflare_pages"})
        self.assertEqual(written.get("deploy_target"), "cloudflare_pages")

    def test_the_contracts_new_course_default_survives_setup(self):
        default = contracts.section("app-rules", "publishingDestinations", "newCourseDefault")
        written = self.rerun_setup({"deploy_target": default})
        self.assertEqual(written.get("deploy_target"), default)

    def test_a_saved_course_that_names_no_destination_is_given_none(self):
        written = self.rerun_setup({})
        self.assertNotIn("deploy_target", written,
                         "a re-run gave an older course a destination; it deploys to "
                         "Netlify by the absent-key fallback and must keep doing so")

    def test_a_new_course_made_at_the_command_line_deploys_to_the_default(self):
        default = contracts.section("app-rules", "publishingDestinations", "newCourseDefault")
        self.assertEqual(setup_course.NEW_COURSE_DEPLOY_TARGET, default,
                         "setup_course.py and the contract disagree about the new-course default")
        written = new_course_harness.NewCourseGetsItsMarksPool.create_course(
            self, "ADA1O", takes_example=False, keeps_skeleton=True
        )
        self.assertEqual(written.get("deploy_target"), default,
                         "a course made with setup.sh did not get the new-course default")


if __name__ == "__main__":
    unittest.main()
