#!/usr/bin/env python3
"""
Unit tests for deploy.py's Netlify ad-badge suppression.

Pure stdlib, no Docker and no network — these test the file-scanning and
_headers-writing logic directly against a temporary folder standing in for
a built public/. Run with:

    python3 scripts/test_deploy_netlify_headers.py

verify.sh runs this early, before the (slow) Docker build, since nothing
here needs the image.
"""
import base64
import hashlib
import tempfile
import unittest
from pathlib import Path

import deploy


def _digest(body: str) -> str:
    return "'sha256-" + base64.b64encode(hashlib.sha256(body.encode("utf-8")).digest()).decode("ascii") + "'"


class InlineScriptPolicyTests(unittest.TestCase):

    def test_a_page_with_no_scripts_yields_an_empty_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<html><body>Hello</body></html>", encoding="utf-8")
            hashes, hosts = deploy._collect_inline_script_policy(public_dir)
            self.assertEqual(hashes, [])
            self.assertEqual(hosts, [])

    def test_external_same_origin_scripts_need_no_hash_or_host(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text(
                '<script src="./prescript.js"></script><script src="../postscript.js"></script>',
                encoding="utf-8",
            )
            hashes, hosts = deploy._collect_inline_script_policy(public_dir)
            self.assertEqual(hashes, [])
            self.assertEqual(hosts, [])

    def test_an_inline_script_is_hashed_by_its_exact_content(self):
        body = "console.log('hello from a Quartz page');"
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text(f"<script>{body}</script>", encoding="utf-8")
            hashes, hosts = deploy._collect_inline_script_policy(public_dir)
            self.assertEqual(hashes, [_digest(body)])
            self.assertEqual(hosts, [])

    def test_the_same_inline_script_on_many_pages_is_one_hash_not_many(self):
        body = "console.log('shared across every page');"
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            for name in ("index.html", "about.html", "sub/deep.html"):
                page = public_dir / name
                page.parent.mkdir(parents=True, exist_ok=True)
                page.write_text(f"<script>{body}</script>", encoding="utf-8")
            hashes, hosts = deploy._collect_inline_script_policy(public_dir)
            self.assertEqual(hashes, [_digest(body)])

    def test_a_cross_origin_script_src_is_allow_listed_by_its_origin(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text(
                '<script src="https://cdn.jsdelivr.net/npm/katex/dist/contrib/auto-render.min.js"></script>',
                encoding="utf-8",
            )
            hashes, hosts = deploy._collect_inline_script_policy(public_dir)
            self.assertEqual(hashes, [])
            self.assertEqual(hosts, ["https://cdn.jsdelivr.net"])

    def test_a_teachers_own_embedded_script_is_covered_automatically(self):
        # Nothing here special-cases Quartz's own scripts — whatever a
        # teacher pastes into their notes gets hashed the same way, which is
        # the whole point of scanning the build rather than hardcoding a list.
        body = "window.dispatchEvent(new CustomEvent('demo-ready'));"
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "custom-demo.html").write_text(f"<script>{body}</script>", encoding="utf-8")
            hashes, hosts = deploy._collect_inline_script_policy(public_dir)
            self.assertEqual(hashes, [_digest(body)])


class WriteHeadersFileTests(unittest.TestCase):

    def test_writes_a_headers_file_with_only_script_src(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>1+1;</script>", encoding="utf-8")
            count = deploy.write_netlify_headers_file(public_dir)
            self.assertEqual(count, 1)

            text = (public_dir / "_headers").read_text(encoding="utf-8")
            self.assertIn("Content-Security-Policy: script-src 'self'", text)
            # Only script-src is set — everything else (images, styles,
            # fonts, connections) must stay unrestricted.
            self.assertNotIn("default-src", text)
            self.assertNotIn("img-src", text)
            self.assertNotIn("style-src", text)

    def test_an_existing_headers_file_is_extended_not_clobbered(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            (public_dir / "_headers").write_text("/*\n  X-Robots-Tag: noindex\n", encoding="utf-8")

            deploy.write_netlify_headers_file(public_dir)

            text = (public_dir / "_headers").read_text(encoding="utf-8")
            self.assertIn("X-Robots-Tag: noindex", text)
            self.assertIn("Content-Security-Policy", text)

    def test_is_deterministic_across_repeated_builds(self):
        # The delta-deploy algorithm relies on identical content hashing
        # identically build after build (documentation/07-deployment.md,
        # "Why determinism matters") — _headers must hold to the same rule,
        # or every deploy would re-upload it for nothing.
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "a.html").write_text("<script>const x = 1;</script>", encoding="utf-8")
            (public_dir / "b.html").write_text("<script>const y = 2;</script>", encoding="utf-8")

            deploy.write_netlify_headers_file(public_dir)
            first = (public_dir / "_headers").read_text(encoding="utf-8")

            (public_dir / "_headers").unlink()
            deploy.write_netlify_headers_file(public_dir)
            second = (public_dir / "_headers").read_text(encoding="utf-8")

            self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
