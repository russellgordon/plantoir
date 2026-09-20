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
import inspect
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


class CloudflareIsNeverTouchedTests(unittest.TestCase):
    """
    Cloudflare Pages (and local_folder, which never even reaches deploy.py)
    must never pay any cost for a problem that is Netlify's alone — not a
    slower deploy, not an extra file, not an extra console line. That
    guarantee currently rests on main()'s cloudflare branch RETURNING before
    any Netlify-only code runs, including badge suppression. Pinned
    structurally here so a future refactor that moves the badge-suppression
    call earlier fails loudly instead of shipping a silent regression that
    also ruins the clean A/B comparison between destinations (deploying
    identical content to both, to check whether a suspected breakage is
    caused by this feature).
    """

    def test_the_cloudflare_branch_returns_before_badge_suppression_runs(self):
        source = inspect.getsource(deploy.main)
        cloudflare_branch_at = source.index('if args.target == "cloudflare":')
        # The return that ends that branch specifically, not some other
        # return elsewhere in main().
        cloudflare_return_at = source.index("return", cloudflare_branch_at)
        badge_call_at = source.index("write_netlify_headers_file(public_dir)")

        self.assertLess(
            cloudflare_return_at, badge_call_at,
            "write_netlify_headers_file() must only be reachable AFTER the "
            "cloudflare branch's own return — a Cloudflare Pages deploy "
            "must never execute this code at all."
        )

    def test_publish_to_cloudflare_never_calls_the_headers_writer(self):
        # Belt and suspenders: the function Cloudflare's path actually calls
        # has no route to the badge-suppression code either.
        source = inspect.getsource(deploy.publish_to_cloudflare)
        self.assertNotIn("write_netlify_headers_file", source)


if __name__ == "__main__":
    unittest.main()
