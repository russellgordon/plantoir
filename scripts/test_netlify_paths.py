#!/usr/bin/env python3
"""
Page addresses on Netlify (#628): a Netlify publish lower-cases the path of
each same-site link in memory as it uploads (scripts/netlify_paths.py, called
by deploy.py's _build_files_manifest), and the site's router and link
previews do the same for the links they make themselves, on a marked page
only (build_site.py -> PLANTOIR-SERVED-CASE).

The cases are not retyped here: contracts/shared-rules.json ->
netlifyPageAddresses.cases are read from the contract and run against
netlify_paths.served_href. The rest pins what the cases cannot carry: which
attributes and elements are edited (and that data-slug, <guid>, scripts and
the CSP's hashes are not), that the bytes Netlify is sent are the bytes its
manifest names, that public/ is never written, and the build's edit.

Stdlib only, so it runs on Windows too (PythonToolchainTests).

    python3 scripts/test_netlify_paths.py
    python3 scripts/test_netlify_paths.py --site <built public/>   # verify.sh 6

The second form checks a REAL built site, which this file's fixtures only
imitate: every page transformed keeps its inline scripts' hash set, changes
nothing on a second pass, keeps every data-slug, and leaves no capital in the
path of a same-site page link.
"""
import contextlib
import hashlib
import html
import inspect
import io
import os
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

import build_site
import contracts
import deploy
import netlify_badge
import netlify_paths
import toolchain_paths


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def rule(*keys):
    return contracts.section("shared-rules", "netlifyPageAddresses", *keys)


HOST = "ics3u-s2-2026-27.russellgordon.ca"
MARKER = ' data-plantoir-paths="lowercase"'

# Quartz's alias page, exactly as quartz/plugins/emitters/aliases.ts writes it,
# and the regex quartz/components/scripts/util.ts -> fetchCanonical finds its
# target with.
ALIAS_PAGE = """
        <!DOCTYPE html>
        <html lang="en-us">
        <head>
        <title>Concepts/Functions</title>
        <link rel="canonical" href="../Concepts/Functions">
        <meta name="robots" content="noindex">
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="0; url=../Concepts/Functions">
        </head>
        </html>
        """
FETCH_CANONICAL = re.compile(r'<link rel="canonical" href="([^"]*)">')

INLINE_SCRIPT = 'document.querySelector("a").href = "./Concepts/Functions"; const tag = \'<a href="./Key-Links">\''


def quartz_page(links: int = 8) -> str:
    """A page shaped like Quartz's: internal links carrying data-slug, a
    stylesheet and a picture with capitals, an inline script that writes a
    link, and code showing a link."""
    anchors = ""
    for number in range(links):
        anchors += (
            f'<a href="./All-Classes/Thread-1,-Day-{number}/../../Concepts/Functions#Scope-Rules" '
            f'class="internal" data-slug="Concepts/Functions-{number}">Day {number}</a>\n'
        )
    return (
        '<!DOCTYPE html>\n<html lang="en"><head><title>Home</title>'
        '<link href="./Index.css" rel="stylesheet" type="text/css" spa-preserve/>'
        f'<script type="module">{INLINE_SCRIPT}</script></head>\n'
        '<body data-slug="index">\n'
        + anchors
        + '<img src="./Media/Functions---Scope-Highlight.png" alt="Scope"/>\n'
        '<a href="https://Example.com/Some/Page">elsewhere</a>\n'
        '<a href="#Heading-One">here</a>\n'
        '<a href=./Key-Links>unquoted</a>\n'
        "<a href='./Course-Outline?Week=One'>single</a>\n"
        '<a href="./&Eacute;valuation/Notes">accented</a>\n'
        '<pre><code>&lt;a href="./Concepts/Functions"&gt;</code></pre>\n'
        '</body></html>\n'
    )


def path_has_capitals(raw: str) -> bool:
    """Whether the raw path text of a link (up to ? or #) has an ASCII
    capital outside a reference or a %-escape."""
    text = re.sub(r"&[#A-Za-z0-9]+;?", "", raw)
    text = re.sub(r"%[0-9A-Fa-f]{2}", "", text)
    text = re.split(r"[?#]", text, maxsplit=1)[0]
    return re.search(r"[A-Z]", text) is not None


class ContractCaseTests(unittest.TestCase):

    def setUp(self):
        use_the_repository_contract()

    def test_every_case_is_served_as_the_contract_says(self):
        host = rule("ownHost")
        for case in rule("cases"):
            with self.subTest(href=case["href"]):
                self.assertEqual(netlify_paths.served_href(case["href"], host), case["expected"], case["why"])

    def test_every_case_is_unchanged_by_a_second_pass(self):
        host = rule("ownHost")
        for case in rule("cases"):
            with self.subTest(href=case["href"]):
                self.assertEqual(netlify_paths.served_href(case["expected"], host), case["expected"])

    def test_the_marker_is_the_contracts_in_the_publish_and_in_the_build(self):
        marker = rule("marker")
        self.assertEqual(netlify_paths.MARKER_ATTRIBUTE, marker["attribute"])
        self.assertEqual(netlify_paths.MARKER_VALUE, marker["value"])
        self.assertEqual(build_site.SERVED_CASE_MARKER, marker["buildEditMarker"])
        # The site's script reads the attribute through dataset, which spells
        # data-plantoir-paths as plantoirPaths.
        camel = re.sub(r"-([a-z])", lambda found: found.group(1).upper(), marker["attribute"][len("data-"):])
        self.assertIn(f'dataset.{camel} !== \\"{marker["value"]}\\"', inspect.getsource(build_site))

    def test_every_rejected_option_says_why(self):
        for option in rule("rejected"):
            self.assertTrue(option["option"] and option["why"])


class PageTests(unittest.TestCase):

    def test_page_links_are_lower_cased_and_nothing_else_moves(self):
        page = quartz_page()
        served = netlify_paths.served_html(page, HOST)
        self.assertEqual(served.count(MARKER), 1)
        self.assertTrue(served.startswith('<!DOCTYPE html>\n<html' + MARKER + ' lang="en">'))
        unmarked = served.replace(MARKER, "", 1)
        self.assertEqual(len(unmarked), len(page), "only the marker may add bytes")
        for ours, theirs in zip(unmarked, page):
            if ours != theirs:
                self.assertTrue("A" <= theirs <= "Z" and ours == theirs.lower(), (theirs, ours))
        self.assertIn('href="./all-classes/thread-1,-day-0/../../concepts/functions#Scope-Rules"', served)
        self.assertIn("<a href=./key-links>", served)
        self.assertIn("href='./course-outline?Week=One'", served)
        self.assertIn('href="./&Eacute;valuation/notes"', served)

    def test_data_slug_is_never_rewritten(self):
        page = quartz_page(links=8)
        served = netlify_paths.served_html(page, HOST)
        slugs = re.findall(r'data-slug="([^"]*)"', page)
        self.assertEqual(len(slugs), 9)
        self.assertEqual(re.findall(r'data-slug="([^"]*)"', served), slugs)

    def test_scripts_code_pictures_styles_and_other_hosts_are_left_alone(self):
        served = netlify_paths.served_html(quartz_page(), HOST)
        self.assertIn(INLINE_SCRIPT, served)
        self.assertIn('&lt;a href="./Concepts/Functions"&gt;', served)
        self.assertIn('src="./Media/Functions---Scope-Highlight.png"', served)
        self.assertIn('href="./Index.css"', served)
        self.assertIn('href="https://Example.com/Some/Page"', served)
        self.assertIn('href="#Heading-One"', served)

    def test_the_csp_hashes_are_the_same_before_and_after(self):
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            page = quartz_page()
            Path(before, "index.html").write_text(page, encoding="utf-8")
            Path(after, "index.html").write_text(netlify_paths.served_html(page, HOST), encoding="utf-8")
            self.assertEqual(
                netlify_badge._collect_inline_script_policy(Path(before)),
                netlify_badge._collect_inline_script_policy(Path(after)),
            )
            self.assertTrue(netlify_badge._collect_inline_script_policy(Path(before))[0])

    def test_a_second_pass_changes_nothing(self):
        once = netlify_paths.served_html(quartz_page(), HOST)
        self.assertEqual(netlify_paths.served_html(once, HOST), once)

    def test_an_alias_page_still_redirects_through_fetch_canonical(self):
        served = netlify_paths.served_html(ALIAS_PAGE, HOST)
        found = FETCH_CANONICAL.search(served)
        self.assertIsNotNone(found, "fetchCanonical's regex no longer finds the alias page's target")
        self.assertEqual(found.group(1), "../concepts/functions")
        self.assertIn('<meta http-equiv="refresh" content="0; url=../concepts/functions">', served)
        self.assertIn('<html' + MARKER + ' lang="en-us">', served)
        self.assertEqual(served.replace(MARKER, "").lower(), ALIAS_PAGE.lower())

    def test_a_file_with_no_html_tag_has_its_links_rewritten_and_no_marker(self):
        fragment = '<p>See <a href="Part-Two.html">Part Two</a></p>\n'
        served = netlify_paths.served_html(fragment, HOST)
        self.assertEqual(served, '<p>See <a href="part-two.html">Part Two</a></p>\n')
        self.assertNotIn("data-plantoir-paths", served)

    def test_a_page_with_a_base_keeps_its_links(self):
        page = '<html><head><base href="https://Other.example/Root/"></head><body><a href="Some/Page">x</a></body></html>'
        served = netlify_paths.served_html(page, HOST)
        self.assertIn('<a href="Some/Page">', served)
        self.assertEqual(served.count(MARKER), 1)

    def test_a_page_already_marked_is_not_marked_twice(self):
        page = '<html data-plantoir-paths="lowercase"><body><a href="./A">a</a></body></html>'
        self.assertEqual(netlify_paths.served_html(page, HOST), page.replace("./A", "./a"))

    def test_a_file_that_is_not_utf8_is_sent_as_it_is(self):
        data = b'<html><a href="./Caf\xe9">x</a></html>'
        self.assertIs(netlify_paths.served_file("Media/Old.html", data, HOST), data)

    def test_only_pages_the_sitemap_and_the_feed_are_rewritten(self):
        for name in ("index.html", "Concepts/Functions.html", "Media/Old.HTM", "sitemap.xml", "index.xml"):
            self.assertTrue(netlify_paths.rewrites(name), name)
        for name in ("index.css", "postscript.js", "static/contentIndex.json", "Media/sitemap.xml", "Media/index.xml", "Media/Picture.PNG"):
            self.assertFalse(netlify_paths.rewrites(name), name)
        data = b'<a href="./Concepts/Functions">'
        self.assertIs(netlify_paths.served_file("static/contentIndex.json", data, HOST), data)


class FeedTests(unittest.TestCase):

    def test_the_sitemap_lowercases_every_loc_on_the_sections_host(self):
        sitemap = (
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url>\n'
            f'    <loc>https://{HOST}/All-Classes/Thread-1,-Day-1</loc>\n'
            '    <lastmod>2026-10-13T11:00:00.000Z</lastmod>\n'
            '  </url><url>\n'
            '    <loc>https://Elsewhere.example/Not-Ours</loc>\n'
            '  </url></urlset>'
        )
        served = netlify_paths.served_file("sitemap.xml", sitemap.encode(), HOST).decode()
        self.assertIn(f"<loc>https://{HOST}/all-classes/thread-1,-day-1</loc>", served)
        self.assertIn("<loc>https://Elsewhere.example/Not-Ours</loc>", served)
        self.assertNotIn("data-plantoir-paths", served)

    def test_the_feed_lowercases_link_and_never_guid_or_description(self):
        feed = (
            '<?xml version="1.0" encoding="UTF-8" ?>\n<rss version="2.0">\n<channel>\n'
            f'<link>https://{HOST}</link>\n'
            '<item>\n<title>Unit 4, Day 24</title>\n'
            f'<link>https://{HOST}/All-Classes/Unit-4,-Day-24</link>\n'
            f'<guid>https://{HOST}/All-Classes/Unit-4,-Day-24</guid>\n'
            f'<description>See https://{HOST}/Concepts/Functions and f&#039; Q&amp;A</description>\n'
            '</item>\n</channel>\n</rss>'
        )
        served = netlify_paths.served_file("index.xml", feed.encode(), HOST).decode()
        self.assertIn(f"<link>https://{HOST}/all-classes/unit-4,-day-24</link>", served)
        self.assertIn(f"<guid>https://{HOST}/All-Classes/Unit-4,-Day-24</guid>", served)
        self.assertIn(f"<description>See https://{HOST}/Concepts/Functions and f&#039; Q&amp;A</description>", served)
        self.assertIn(f"<link>https://{HOST}</link>", served)


class PublicFolder:
    """A stand-in public/: a page, a nested page, a picture, the sitemap."""

    def __init__(self, root: Path):
        self.root = root
        (root / "Concepts").mkdir()
        (root / "index.html").write_text(quartz_page(), encoding="utf-8")
        (root / "Concepts" / "Functions.html").write_text(ALIAS_PAGE, encoding="utf-8")
        (root / "Concepts" / "Picture.PNG").write_bytes(b"\x89PNG not really")
        (root / "sitemap.xml").write_text(f"<urlset><url><loc>https://{HOST}/Concepts/Functions</loc></url></urlset>", encoding="utf-8")

    def snapshot(self) -> dict:
        state = {}
        for path in sorted(self.root.rglob("*")):
            if path.is_file():
                state[path.relative_to(self.root).as_posix()] = (path.read_bytes(), path.stat().st_mtime_ns)
        return state


class DeployTests(unittest.TestCase):
    """The bytes Netlify is sent are the bytes its manifest names."""

    def setUp(self):
        self.original_api = deploy.netlify_api
        self.posted = []
        self.uploaded = {}

        def stand_in_api(method, path, token, payload=None, headers=None, data=None):
            if method == "POST":
                self.posted.append(payload)
                return {"id": "deploy-1", "required": sorted(set(payload["files"].values()))}
            self.uploaded[path] = data
            return {}

        deploy.netlify_api = stand_in_api

    def tearDown(self):
        deploy.netlify_api = self.original_api

    def publish(self, root: Path):
        response = deploy.create_delta_deploy("site", "token", root, own_host=HOST)
        with contextlib.redirect_stdout(io.StringIO()):
            deploy._upload_required_files(response["id"], "token", root, response["required"], response["_sha_to_pairs"])
        return self.posted[-1]["files"]

    def test_each_upload_is_the_bytes_its_digest_names_and_pages_go_up_lower_cased(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            PublicFolder(root)
            manifest = self.publish(root)
            by_path = {}
            for path, data in self.uploaded.items():
                by_path["/" + path.split("/files/", 1)[1]] = data
            self.assertEqual(set(by_path), set(manifest), "every file is required here, so every one goes up")
            for remote, digest in manifest.items():
                self.assertEqual(hashlib.sha1(by_path[remote]).hexdigest(), digest, remote)
            home = by_path["/index.html"]
            self.assertIn(MARKER.encode(), home)
            self.assertIn(b'href="./all-classes/thread-1,-day-0/../../concepts/functions#Scope-Rules"', home)
            self.assertNotEqual(manifest["/index.html"], hashlib.sha1((root / "index.html").read_bytes()).hexdigest())
            self.assertIn(b"https://" + HOST.encode() + b"/concepts/functions</loc>", by_path["/sitemap.xml"])
            self.assertEqual(by_path["/Concepts/Picture.PNG"], (root / "Concepts" / "Picture.PNG").read_bytes())

    def test_public_is_never_written(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder = PublicFolder(root)
            before = folder.snapshot()
            self.publish(root)
            self.assertEqual(folder.snapshot(), before)

    def test_a_second_publish_names_the_same_digests(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            PublicFolder(root)
            first = self.publish(root)
            second = self.publish(root)
            self.assertEqual(first, second)

    def test_the_upload_keeps_its_signature(self):
        self.assertEqual(
            list(inspect.signature(deploy._upload_required_files).parameters),
            ["deploy_id", "token", "root", "required_shas", "sha_to_pairs"],
        )

    def test_the_section_address_reaches_the_manifest(self):
        source = inspect.getsource(deploy.main)
        self.assertIn("own_host=target_domain", source)

    def test_cloudflare_never_sees_the_rewrite(self):
        for function in (deploy.publish_to_cloudflare, deploy.deploy_to_cloudflare):
            source = inspect.getsource(function)
            self.assertNotIn("netlify_paths", source)
            self.assertNotIn("_build_files_manifest", source)
            self.assertNotIn("create_delta_deploy", source)


SPA_SHAPE = (
    'import micromorph from "micromorph"\n'
    'import { fetchCanonical } from "./util"\n'
    "\n"
    "const getOpts = ({ target }: Event) => {\n"
    '  return { url: new URL(href), scroll: "routerNoscroll" in a.dataset ? false : undefined }\n'
    "}\n"
    "async function navigate(url: URL, isBack: boolean = false) {\n"
    "  if (isNavigating) return\n"
    "}\n"
)
POPOVER_SHAPE = (
    'import { fetchCanonical } from "./util"\n'
    "async function mouseEnterHandler() {\n"
    "  const targetUrl = new URL(link.href)\n"
    "}\n"
)


class BuildEditTests(unittest.TestCase):

    def wired(self, name: str, text: str) -> tuple[str, str]:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / name
            path.write_text(text, encoding="utf-8")
            said = io.StringIO()
            with contextlib.redirect_stdout(said):
                build_site._wire_served_case(path)
                build_site._wire_served_case(path)
            return path.read_text(encoding="utf-8"), said.getvalue()

    def test_the_router_asks_for_the_served_address_once_after_two_builds(self):
        text, said = self.wired("spa.inline.ts", SPA_SHAPE)
        self.assertEqual(said, "")
        self.assertEqual(text.count(build_site.SERVED_CASE_MARKER), 1)
        self.assertEqual(text.count("function plantoirServedCase"), 1)
        self.assertIn("url: plantoirServedCase(new URL(href))", text)
        self.assertIn("{\n  url = plantoirServedCase(url)\n  if (isNavigating) return\n", text)

    def test_the_link_previews_ask_for_the_served_address(self):
        text, said = self.wired("popover.inline.ts", POPOVER_SHAPE)
        self.assertEqual(said, "")
        self.assertEqual(text.count(build_site.SERVED_CASE_MARKER), 1)
        self.assertIn("const targetUrl = plantoirServedCase(new URL(link.href))", text)

    def test_the_edit_is_a_no_op_without_the_mark_and_off_the_sites_origin(self):
        function = build_site._SERVED_CASE_FUNCTION
        self.assertIn('if (document.documentElement.dataset.plantoirPaths !== "lowercase") return url', function)
        self.assertIn("if (url.origin !== window.location.origin) return url", function)
        # The query and the fragment stay: only the pathname is set, and a
        # %-escape is passed through whole.
        self.assertIn("served.pathname = url.pathname.replace(/%[0-9A-Fa-f]{2}|[A-Z]+/g", function)
        self.assertNotIn(".search", function)
        self.assertNotIn(".hash", function)

    def test_an_anchor_that_moved_leaves_the_file_as_quartz_wrote_it(self):
        moved = SPA_SHAPE.replace("  if (isNavigating) return\n", "  if (busy) return\n")
        text, said = self.wired("spa.inline.ts", moved)
        self.assertEqual(text, moved)
        self.assertIn("⚠️", said)

    def test_every_build_wires_both_files(self):
        source = inspect.getsource(build_site.wire_quartz_additions)
        self.assertIn('"spa.inline.ts", _wire_served_case)', source)
        self.assertIn('"popover.inline.ts", _wire_served_case)', source)

    def test_quartzs_own_files_take_the_edit(self):
        """Against Quartz's real files where they are (the image's
        /opt/quartz); verify.sh step 6 checks a built section's copy."""
        candidates = [Path("/opt/quartz/quartz/components/scripts")]
        found = None
        for folder in candidates:
            if (folder / "spa.inline.ts").is_file() and (folder / "popover.inline.ts").is_file():
                found = folder
        if found is None:
            self.skipTest("no Quartz scaffold on this machine (verify.sh step 6 checks the built one)")
        for name in ("spa.inline.ts", "popover.inline.ts"):
            text, said = self.wired(name, (found / name).read_text(encoding="utf-8"))
            self.assertEqual(said, "", name)
            self.assertEqual(text.count(build_site.SERVED_CASE_MARKER), 1, name)


def check_site(public: Path) -> list:
    """Problems with the transform over a REAL built site (verify.sh 6)."""
    problems = []
    host = ""
    with tempfile.TemporaryDirectory() as temporary:
        served_root = Path(temporary) / "public"
        shutil.copytree(public, served_root)
        pages = 0
        links = 0
        for path in sorted(served_root.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(served_root).as_posix()
            if not netlify_paths.rewrites(relative):
                continue
            data = path.read_bytes()
            served = netlify_paths.served_file(relative, data, host)
            if netlify_paths.served_file(relative, served, host) != served:
                problems.append(f"{relative}: a second pass changed it")
            if relative.endswith(".html"):
                pages += 1
                before = data.decode("utf-8", errors="ignore")
                after = served.decode("utf-8", errors="ignore")
                if re.findall(r'data-slug="([^"]*)"', before) != re.findall(r'data-slug="([^"]*)"', after):
                    problems.append(f"{relative}: a data-slug moved")
                if "<html" in before and after.count(MARKER) != 1:
                    problems.append(f"{relative}: the marker is on it {after.count(MARKER)} time(s)")
                for raw in re.findall(r'<a\s[^>]*?href="([^"]*)"', after):
                    decoded = html.unescape(raw).strip()
                    if decoded.startswith(("#", "//")) or re.match(r"^[A-Za-z][A-Za-z0-9+.\-]*:", decoded):
                        continue
                    links += 1
                    if path_has_capitals(raw):
                        problems.append(f"{relative}: {raw} still has a capital in its path")
                if '<link rel="canonical"' in before and not FETCH_CANONICAL.search(after):
                    problems.append(f"{relative}: fetchCanonical's regex no longer finds the alias page's target")
            path.write_bytes(served)
        if netlify_badge._collect_inline_script_policy(public) != netlify_badge._collect_inline_script_policy(served_root):
            problems.append("the inline scripts' hashes or hosts changed")
        if pages == 0 or links == 0:
            problems.append(f"nothing was checked ({pages} pages, {links} links)")
        print(f"checked {pages} pages and {links} same-site links")
    if any("data-plantoir-paths" in path.read_text(encoding="utf-8", errors="ignore") for path in public.rglob("*.html")):
        problems.append("a page the BUILD wrote carries the marker, which only a Netlify publish adds")
    return problems


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--site":
        found = check_site(Path(sys.argv[2]))
        for problem in found:
            print("   " + problem)
        sys.exit(1 if found else 0)
    unittest.main()
