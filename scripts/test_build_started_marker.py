#!/usr/bin/env python3
"""
Issue #265: the build notes when it STARTED, so a Save made while a publish was
building is not mistaken for something that publish already sent.

`contracts/app-rules.json` -> `buildFreshness.buildStartedMarker` names the two
files; the apps read them. Pure Python, temporary folders, no Docker. Runs in
verify.sh and in Windows' PythonToolchainTests.
"""
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import contracts
import toolchain_paths
import build_site


class TheBuildNotesWhenItStarted(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.marker = contracts.section("app-rules", "buildFreshness", "buildStartedMarker")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.section_dir = Path(self.temporary.name) / "section1"

    def tearDown(self):
        self.temporary.cleanup()

    def test_the_names_are_the_ones_the_contract_gives(self):
        self.assertEqual(build_site.BUILD_STARTED_MARKER, self.marker["file"])
        self.assertEqual(build_site.BUILD_STARTED_PENDING, self.marker["pending"])
        # Hidden, or the freshness checks would count them as content.
        self.assertTrue(self.marker["file"].startswith("."))
        self.assertTrue(self.marker["pending"].startswith("."))

    def test_a_build_that_starts_leaves_the_last_sites_start_time_alone(self):
        # The site on disk was made by an earlier build: its start time must
        # survive a new build starting, which may yet fail.
        self.section_dir.mkdir(parents=True)
        earlier = self.section_dir / self.marker["file"]
        earlier.write_text("", encoding="utf-8")
        long_ago = time.time() - 3600
        os.utime(earlier, (long_ago, long_ago))

        build_site._mark_build_starting(self.section_dir)

        self.assertAlmostEqual(earlier.stat().st_mtime, long_ago, delta=1)
        self.assertTrue((self.section_dir / self.marker["pending"]).exists())

    def test_a_finished_build_makes_its_start_time_the_sites(self):
        before = time.time()
        build_site._mark_build_starting(self.section_dir)
        pending = self.section_dir / self.marker["pending"]
        started_at = pending.stat().st_mtime
        # Stamped when it was made, not some later moment.
        self.assertLessEqual(abs(started_at - before), 2)

        time.sleep(0.05)
        build_site._mark_build_finished(self.section_dir)

        marker = self.section_dir / self.marker["file"]
        self.assertTrue(marker.exists())
        self.assertFalse(pending.exists())
        self.assertEqual(marker.stat().st_mtime, started_at, "the rename keeps the START time")

    def test_a_new_start_is_stamped_afresh_rather_than_keeping_an_old_pending_time(self):
        # A stopped build leaves its pending file behind; the next build's
        # start must not inherit that older time... nor, worse, a newer one.
        self.section_dir.mkdir(parents=True)
        stale = self.section_dir / self.marker["pending"]
        stale.write_text("", encoding="utf-8")
        long_ago = time.time() - 3600
        os.utime(stale, (long_ago, long_ago))

        build_site._mark_build_starting(self.section_dir)

        self.assertGreater(stale.stat().st_mtime, long_ago + 3000)

    def test_finishing_with_nothing_started_changes_nothing(self):
        self.section_dir.mkdir(parents=True)
        build_site._mark_build_finished(self.section_dir)
        self.assertFalse((self.section_dir / self.marker["file"]).exists())

    def test_the_build_marks_its_start_before_it_reads_the_settings(self):
        # Order is the whole point: a mark made after the settings are read
        # would call a Save in between "already built".
        source = (scripts_dir / "build_site.py").read_text(encoding="utf-8")
        body = source[source.index("def build_section_site("):]
        marked = body.index("_mark_build_starting(host_output_dir)")
        read = body.index("with open(config_file")
        self.assertLess(marked, read)
        # And the start becomes the site's only where the site was copied out.
        finished = body.index("_mark_build_finished(host_output_dir)")
        synced = body.index("if _sync_public_to_host(output_dir, host_output_dir):")
        self.assertLess(synced, finished)


if __name__ == "__main__":
    unittest.main()
