#!/usr/bin/env python3
"""
A build that produces no website must say so, and must not leave the last one
lying where a publish will find it.

A section whose `index.md` is gone still builds without error, and Quartz emits
no root `index.html` for it. Two things used to follow, both silent:

* the build printed "Static build complete" anyway, and `deploy` then said
  "Built site not found - build first" to a teacher who had just built;
* the PREVIOUS build's `public/` stayed on the host, and `deploy` publishes
  whatever it finds there - so a publish reported success and shipped the
  older pages.

These tests pin both halves without Docker: the sync reports whether it
mirrored a site, and the stale mirror is cleared when this build cannot
replace it.
"""
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import build_site


class PublishableSiteTests(unittest.TestCase):

    # MARK: - Setup

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.base = Path(self.temp_dir.name)
        self.output_dir = self.base / "work" / "section1"
        self.host_output_dir = self.base / "host" / "section1"
        (self.output_dir / "public").mkdir(parents=True)
        self.host_output_dir.mkdir(parents=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    # MARK: - Tests

    def test_a_built_site_is_mirrored_and_reported(self):
        """With a root index.html there is a site, and it reaches the host."""
        (self.output_dir / "public" / "index.html").write_text("<html></html>")
        (self.output_dir / "public" / "about.html").write_text("<html></html>")

        mirrored = build_site._sync_public_to_host(self.output_dir, self.host_output_dir)

        self.assertTrue(mirrored)
        self.assertTrue((self.host_output_dir / "public" / "index.html").exists())
        self.assertTrue((self.host_output_dir / "public" / "about.html").exists())

    def test_pages_without_a_front_page_are_not_a_site(self):
        """
        Pages but no root index.html: nothing is mirrored, and the caller is
        told. The guard itself is old; the ANSWER is what was missing, and it
        is what lets the build stop calling itself complete.
        """
        (self.output_dir / "public" / "about.html").write_text("<html></html>")

        mirrored = build_site._sync_public_to_host(self.output_dir, self.host_output_dir)

        self.assertFalse(mirrored)
        self.assertFalse((self.host_output_dir / "public").exists())

    def test_the_last_built_site_is_cleared_when_it_cannot_be_replaced(self):
        """
        The serious half. A publish uploads whatever sits in the host's
        `public/`, so leaving last week's pages there turned a missing front
        page into a publish that reported success and sent out stale work.
        """
        stale = self.host_output_dir / "public"
        stale.mkdir()
        (stale / "index.html").write_text("<html>last week</html>")

        printed = io.StringIO()
        with redirect_stdout(printed):
            build_site._clear_stale_host_site(self.host_output_dir, "ICS3U", 1)

        self.assertFalse(stale.exists())
        said = printed.getvalue()
        self.assertIn("ICS3U", said)
        self.assertIn("Section 1", said)

    def test_clearing_says_nothing_when_there_is_nothing_to_clear(self):
        """
        A section that has never been built must not be told anything about a
        website being removed - the nagging this family of checks must not do.
        """
        printed = io.StringIO()
        with redirect_stdout(printed):
            build_site._clear_stale_host_site(self.host_output_dir, "ICS3U", 1)

        self.assertEqual(printed.getvalue(), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
