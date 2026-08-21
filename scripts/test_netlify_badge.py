#!/usr/bin/env python3
"""
Unit tests for netlify_badge.py in isolation.

Pure stdlib, no Docker and no network. scripts/test_deploy_netlify_headers.py
already exercises this logic thoroughly through `deploy`'s re-export (and
must keep doing so, since that is what the two apps' callers actually use),
but netlify_badge.py is now imported directly by a second caller
(website/netlify_deploy.py) and deserves its own coverage that does not go
through deploy.py at all — so a change to deploy.py's re-export, or a future
caller that imports netlify_badge.py some other way, is caught here rather
than only where deploy.py happens to be exercised. Run with:

    python3 scripts/test_netlify_badge.py
"""
import base64
import hashlib
import tempfile
import unittest
from pathlib import Path

import netlify_badge


def _digest(body: str) -> str:
    return "'sha256-" + base64.b64encode(hashlib.sha256(body.encode("utf-8")).digest()).decode("ascii") + "'"


class NetlifyBadgeModuleTests(unittest.TestCase):

    def test_module_exposes_the_two_public_functions_deploy_py_re_exports(self):
        self.assertTrue(callable(netlify_badge._collect_inline_script_policy))
        self.assertTrue(callable(netlify_badge.write_netlify_headers_file))

    def test_an_inline_script_is_hashed_by_its_exact_content(self):
        body = "console.log('hello directly from netlify_badge');"
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text(f"<script>{body}</script>", encoding="utf-8")
            hashes, hosts = netlify_badge._collect_inline_script_policy(public_dir)
            self.assertEqual(hashes, [_digest(body)])
            self.assertEqual(hosts, [])

    def test_writes_a_headers_file_with_only_script_src(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>1+1;</script>", encoding="utf-8")
            count = netlify_badge.write_netlify_headers_file(public_dir)
            self.assertEqual(count, 1)

            text = (public_dir / "_headers").read_text(encoding="utf-8")
            self.assertIn("Content-Security-Policy: script-src 'self'", text)
            self.assertNotIn("default-src", text)


class DeployPyReExportsTheSameFunctionsTests(unittest.TestCase):
    """
    deploy.py imports these two functions from netlify_badge rather than
    defining its own copies — pinned here as an identity check (not merely
    "behaves the same") so a future refactor that quietly forks the logic
    back into deploy.py is caught immediately, before behaviour has any
    chance to drift.
    """

    def test_deploy_and_netlify_badge_share_the_exact_same_function_objects(self):
        import deploy

        self.assertIs(deploy._collect_inline_script_policy, netlify_badge._collect_inline_script_policy)
        self.assertIs(deploy.write_netlify_headers_file, netlify_badge.write_netlify_headers_file)


if __name__ == "__main__":
    unittest.main()
