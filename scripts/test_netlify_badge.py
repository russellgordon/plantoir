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

    def test_allows_unsafe_eval_but_never_unsafe_inline(self):
        """
        'unsafe-eval' has to be in the policy — Quartz's Explorer sidebar
        (patches/explorer.inline.ts) builds its sort/filter/map functions via
        `new Function(...)`, and without it every page's sidebar silently
        stayed empty on a real Netlify deploy while Cloudflare (no CSP at
        all) was unaffected — caught by A/B testing the two targets and
        reading the browser's own `unhandledrejection`. 'unsafe-inline' must
        stay absent regardless, since that is the one keyword Netlify's own
        badge needs to render at all — the two are independent CSP keywords,
        and adding the former must never let the latter back in.
        """
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text("<script>1+1;</script>", encoding="utf-8")
            netlify_badge.write_netlify_headers_file(public_dir)

            text = (public_dir / "_headers").read_text(encoding="utf-8")
            self.assertIn("'unsafe-eval'", text)
            self.assertNotIn("'unsafe-inline'", text)


# Copied from the inline <script type="module"> of a real built page
# (ICS3U section 1, Style/What-This-Site-Can-Do.html, 2026-10-19): Quartz's
# Mermaid loader, minified, as the browser receives it.
QUARTZ_MERMAID_LOADER = (
    'document.addEventListener("nav",async()=>{let t=document.querySelector(".center")'
    '.querySelectorAll("code.mermaid");if(t.length===0)return;'
    'H||=await import("https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.4.0/mermaid.esm.min.mjs");'
    'let a=H.default,i=new WeakMap;});'
)


class ScriptsThatLoadCodeAreAllowedTheirHostsTests(unittest.TestCase):
    """#594: script-src governs a dynamic import() as it governs a
    <script src>. The policy collected only <script src> hosts, so Quartz's
    Mermaid loader - an inline module importing from cdnjs - was blocked on
    every Netlify site and every diagram stayed as source text."""

    def hosts_for(self, files: dict) -> list:
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            for name, text in files.items():
                path = public_dir / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            hashes, hosts = netlify_badge._collect_inline_script_policy(public_dir)
            return hosts

    def test_quartzs_own_mermaid_loader_allows_cdnjs(self):
        hosts = self.hosts_for({"Style/What-This-Site-Can-Do.html":
                                f'<script type="module">{QUARTZ_MERMAID_LOADER}</script>'})
        # Mermaid's own chunks load from the same host, so nothing else.
        self.assertEqual(hosts, ["https://cdnjs.cloudflare.com"])

    def test_the_policy_written_to_headers_names_cdnjs(self):
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp)
            (public_dir / "index.html").write_text(
                f'<script type="module">{QUARTZ_MERMAID_LOADER}</script>', encoding="utf-8")
            netlify_badge.write_netlify_headers_file(public_dir)
            text = (public_dir / "_headers").read_text(encoding="utf-8")
            self.assertIn(" https://cdnjs.cloudflare.com;", text)
            self.assertNotIn("'unsafe-inline'", text)

    def test_an_inline_module_importing_from_cdnjs_allows_it(self):
        hosts = self.hosts_for({"index.html":
                                "<script type=\"module\">const m = await import('https://cdnjs.cloudflare.com/x/y.mjs')</script>"})
        self.assertEqual(hosts, ["https://cdnjs.cloudflare.com"])

    def test_the_same_import_inside_postscript_js_allows_it(self):
        hosts = self.hosts_for({"index.html": '<script src="./postscript.js" type="module"></script>',
                                "postscript.js": QUARTZ_MERMAID_LOADER})
        self.assertEqual(hosts, ["https://cdnjs.cloudflare.com"])

    def test_an_import_in_a_teachers_own_mjs_in_static_allows_its_host(self):
        hosts = self.hosts_for({"index.html": "<p>Hello</p>",
                                "static/demo/widget.mjs": "export const w = () => import(`https://esm.sh/canvas-confetti@1`)"})
        self.assertEqual(hosts, ["https://esm.sh"])

    def test_a_fetch_is_not_a_script_source_and_allows_nothing(self):
        hosts = self.hosts_for({"index.html": '<script>fetch("https://api.example/data.json")</script>',
                                "postscript.js": 'fetch("https://api.example/other");const u="https://api.example/x.mjs"'})
        self.assertEqual(hosts, [])

    def test_same_origin_imports_need_no_host(self):
        hosts = self.hosts_for({"index.html": '<script type="module">import("./x.mjs");import("/static/x.mjs")</script>',
                                "postscript.js": 'await import("./chunk.mjs")'})
        self.assertEqual(hosts, [])

    def test_a_template_with_a_substitution_names_no_fixed_host(self):
        hosts = self.hosts_for({"postscript.js": "await import(`https://${cdn}/x.mjs`)"})
        self.assertEqual(hosts, [])

    def test_a_method_named_import_is_not_a_dynamic_import(self):
        hosts = self.hosts_for({"postscript.js": 'this.index[t].import("https://not.a.script/x")'})
        self.assertEqual(hosts, [])

    def test_import_hosts_and_script_src_hosts_are_one_sorted_list(self):
        hosts = self.hosts_for({
            "a.html": '<script src="https://cdn.jsdelivr.net/npm/x.js"></script>'
                      f'<script type="module">{QUARTZ_MERMAID_LOADER}</script>',
            "b.html": f'<script type="module">{QUARTZ_MERMAID_LOADER}</script>',
            "postscript.js": QUARTZ_MERMAID_LOADER,
        })
        self.assertEqual(hosts, ["https://cdn.jsdelivr.net", "https://cdnjs.cloudflare.com"])


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
