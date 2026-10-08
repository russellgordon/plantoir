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
import netlify_badge


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


class TheBlockIsReplacedNotAppendedTests(unittest.TestCase):
    """#462: plantoir.app's site/ is never cleaned, so _headers survives from
    one deploy to the next. The block this writes is marked and replaced; a
    second one beside it would keep an old script's hash in force, and two
    `/*` policies are both enforced, so a changed inline script would be
    blocked the day it changed."""

    OLD_BLOCK = "/*\n  Content-Security-Policy: script-src 'self' 'unsafe-eval' 'sha256-OLD=';\n"

    def write(self, public_dir: Path) -> str:
        deploy.write_netlify_headers_file(public_dir)
        return (public_dir / "_headers").read_text(encoding="utf-8")

    def test_two_deploys_with_different_scripts_leave_one_block_with_only_the_second_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>const a = 1;</script>", encoding="utf-8")
            self.write(public_dir)
            (public_dir / "index.html").write_text("<script>const b = 2;</script>", encoding="utf-8")
            text = self.write(public_dir)

            self.assertEqual(text.count("Content-Security-Policy"), 1)
            self.assertEqual(text.count("/*"), 1)
            self.assertIn(_digest("const b = 2;"), text)
            self.assertNotIn(_digest("const a = 1;"), text)

    def test_a_second_deploy_of_the_same_site_changes_no_byte(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>const a = 1;</script>", encoding="utf-8")
            (public_dir / "_headers").write_text("/*\n  X-Robots-Tag: noindex\n", encoding="utf-8")
            deploy.write_netlify_headers_file(public_dir)
            first = (public_dir / "_headers").read_bytes()
            deploy.write_netlify_headers_file(public_dir)
            self.assertEqual((public_dir / "_headers").read_bytes(), first)

    def test_it_is_written_with_lf_line_endings_on_every_machine(self):
        # Path.write_text on Windows writes CR LF; a deploy of the same site
        # from the PC and from the Mac must give the same bytes.
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>1;</script>", encoding="utf-8")
            (public_dir / "_headers").write_bytes(b"/*\r\n  X-Robots-Tag: noindex\r\n")
            deploy.write_netlify_headers_file(public_dir)
            self.assertNotIn(b"\r", (public_dir / "_headers").read_bytes())

    def test_the_old_appended_blocks_are_cleaned_up(self):
        # What plantoir.app's site/_headers held after three deploys, with a
        # block of somebody's own above them.
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>const a = 1;</script>", encoding="utf-8")
            (public_dir / "_headers").write_text(
                "/*\n  X-Robots-Tag: noindex\n" + self.OLD_BLOCK + self.OLD_BLOCK + "\n" + self.OLD_BLOCK,
                encoding="utf-8")
            text = self.write(public_dir)

            self.assertEqual(text.count("Content-Security-Policy"), 1)
            self.assertEqual(text.count(netlify_badge.MANAGED_MARKER), 1)
            self.assertNotIn("sha256-OLD=", text)
            self.assertTrue(text.startswith("/*\n  X-Robots-Tag: noindex\n"))
            self.assertLess(text.index("X-Robots-Tag"), text.index(netlify_badge.MANAGED_MARKER))

    def test_a_users_own_csp_block_with_other_headers_is_kept(self):
        theirs = "/*\n  Content-Security-Policy: default-src 'self'\n  X-Frame-Options: DENY\n"
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            (public_dir / "_headers").write_text(theirs, encoding="utf-8")
            text = self.write(public_dir)
            self.assertTrue(text.startswith(theirs))
            self.assertEqual(text.count("Content-Security-Policy"), 2)

    def test_a_block_shaped_like_ours_but_with_more_headers_is_kept(self):
        # Our policy line with somebody's header under it is THEIR block.
        theirs = self.OLD_BLOCK + "  X-Frame-Options: DENY\n"
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            (public_dir / "_headers").write_text(theirs, encoding="utf-8")
            text = self.write(public_dir)
            self.assertTrue(text.startswith(theirs))

    def test_user_lines_after_our_block_survive_the_next_deploy(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>const a = 1;</script>", encoding="utf-8")
            self.write(public_dir)
            with open(public_dir / "_headers", "a", encoding="utf-8") as handle:
                handle.write("\n/fonts/*\n  Cache-Control: public, max-age=31536000\n")
            text = self.write(public_dir)
            self.assertIn("/fonts/*\n  Cache-Control: public, max-age=31536000", text)
            self.assertEqual(text.count("Content-Security-Policy"), 1)

    def test_a_marker_somebody_edited_round_takes_only_the_marker(self):
        # The `/*` under our marker was replaced by hand with a block of
        # their own: only the marker line is ours to remove.
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            (public_dir / "_headers").write_text(
                netlify_badge.MANAGED_MARKER + "\n/about/*\n  X-Frame-Options: DENY\n", encoding="utf-8")
            text = self.write(public_dir)
            self.assertTrue(text.startswith("/about/*\n  X-Frame-Options: DENY\n"))
            self.assertEqual(text.count(netlify_badge.MANAGED_MARKER), 1)

    def test_a_header_added_under_our_marked_block_keeps_its_path(self):
        # The obvious edit: a site-wide header added under our `/*`. It must
        # stay under `/*`, never fall under the path above (here /fonts/*).
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>const a = 1;</script>", encoding="utf-8")
            (public_dir / "_headers").write_text("/fonts/*\n  Cache-Control: x\n", encoding="utf-8")
            self.write(public_dir)
            text = (public_dir / "_headers").read_text(encoding="utf-8")
            (public_dir / "_headers").write_text(text + "  X-Frame-Options: DENY\n", encoding="utf-8")

            text = self.write(public_dir)
            self.assertEqual(text.count("Content-Security-Policy"), 1)
            self.assertEqual(text.count(netlify_badge.MANAGED_MARKER), 1)
            self.assertIn("/*\n  X-Frame-Options: DENY", text)
            self.assertIn("/fonts/*\n  Cache-Control: x\n\n/*", text)
            # A second deploy leaves it exactly where it is.
            self.assertEqual(self.write(public_dir), text)

    def test_a_marked_block_first_in_the_file_keeps_an_added_header_under_its_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            (public_dir / "_headers").write_text(
                netlify_badge.MANAGED_MARKER + "\n" + self.OLD_BLOCK + "  X-Frame-Options: DENY\n", encoding="utf-8")
            text = self.write(public_dir)
            self.assertTrue(text.startswith("/*\n  X-Frame-Options: DENY\n"))
            self.assertNotIn("sha256-OLD=", text)


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
