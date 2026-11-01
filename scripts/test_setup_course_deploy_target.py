#!/usr/bin/env python3
"""Course setup keeps the destination the desktop apps chose (GitHub #668).

Both apps' new-course windows write `deploy_target` into course_config.json
and then run course setup over it. Since #668 a new course is written as
`cloudflare_pages`, so a setup run that dropped the key would quietly send
that course's first deploy to Netlify instead, which is what an absent key
means (contracts/app-rules.json -> publishingDestinations.whyTheyDiffer).

The other half is pinned too: setup run at the command line on a course
with NO saved destination writes none, so a course made with setup.sh deploys
to Netlify, like deploy.sh's own default. That was a decision, not an
oversight; changing the launchers' default was rejected with the fallback.

The run is the real one, `setup_course.setup_course`, driven exactly as
test_graded_folders_rerun.py drives it (Return at every prompt), whose
harness it borrows.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
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

    def test_a_course_with_no_destination_is_given_none(self):
        written = self.rerun_setup({})
        self.assertNotIn("deploy_target", written,
                         "setup wrote a destination of its own; a command-line course "
                         "is meant to deploy to Netlify by the absent-key fallback")


if __name__ == "__main__":
    unittest.main()
