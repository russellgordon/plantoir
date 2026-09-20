#!/usr/bin/env python3
"""
Unit tests for netlify_deploy.py's Netlify ad-badge suppression.

Pure stdlib, no Docker and no network, and no live Netlify call: these test
that netlify_deploy.py wires up the shared scripts/netlify_badge.py logic
correctly against a temporary folder standing in for site/, mirroring
scripts/test_deploy_netlify_headers.py for the class-site path. Run with:

    python3 website/test_netlify_deploy_headers.py
"""
import tempfile
import unittest
from pathlib import Path

import netlify_deploy


class NetlifyDeployWiresUpBadgeSuppressionTests(unittest.TestCase):

    def test_netlify_deploy_re_exports_write_netlify_headers_file(self):
        self.assertTrue(callable(netlify_deploy.write_netlify_headers_file))

    def test_netlify_deploy_shares_the_exact_same_function_as_scripts_deploy_py(self):
        # Both deploy paths — class sites (scripts/deploy.py) and the
        # marketing site (website/netlify_deploy.py) — must run the IDENTICAL
        # scanning logic, not two copies that could drift apart.
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
        import deploy

        self.assertIs(netlify_deploy.write_netlify_headers_file, deploy.write_netlify_headers_file)

    def test_the_websites_own_build_output_gets_a_headers_file_with_a_script_src_csp(self):
        with tempfile.TemporaryDirectory() as tmp:
            site_dir = Path(tmp)
            (site_dir / "index.html").write_text(
                '<html><body><script>console.log("plantoir.app");</script></body></html>',
                encoding="utf-8",
            )
            count = netlify_deploy.write_netlify_headers_file(site_dir)
            self.assertEqual(count, 1)

            text = (site_dir / "_headers").read_text(encoding="utf-8")
            self.assertIn("Content-Security-Policy: script-src 'self'", text)

    def test_only_script_src_is_set_never_default_src(self):
        with tempfile.TemporaryDirectory() as tmp:
            site_dir = Path(tmp)
            (site_dir / "index.html").write_text("<html><body>Hello</body></html>", encoding="utf-8")
            (site_dir / "features").mkdir()
            (site_dir / "features" / "index.html").write_text(
                '<script src="../assets/app.js"></script>', encoding="utf-8"
            )

            netlify_deploy.write_netlify_headers_file(site_dir)

            text = (site_dir / "_headers").read_text(encoding="utf-8")
            self.assertIn("script-src", text)
            self.assertNotIn("default-src", text)
            self.assertNotIn("img-src", text)
            self.assertNotIn("style-src", text)


if __name__ == "__main__":
    unittest.main()
