#!/usr/bin/env python3
"""Build plantoir.app from the sources in this folder.

The finished site is written to ``site/`` at the top of the repository, which
is what Netlify deploys. Nothing here is served: page sources, the layout and
the screenshot harness stay outside the published folder.

Usage::

    python3 website/build.py             # write site/
    python3 website/build.py --check     # report problems, write nothing
    python3 website/build.py --serve     # preview locally; rebuild on refresh
    python3 website/build.py --deploy    # build, then publish to plantoir.app

Publishing is deliberately a separate, explicit flag: the Netlify site is not
connected to GitHub, so plantoir.app changes ONLY when --deploy (or
website/netlify_deploy.py directly) is run. Build, look at site/ locally,
deploy when it is right.

A page is one file in ``website/pages/``: a short front matter block, then the
body as HTML. Everything shared -- masthead, navigation, footer, the head tags
-- lives in ``website/layout/base.html`` so it cannot drift between pages.

Screenshots are referenced by name rather than by path::

    {{shot:courses}}

which expands to a <picture> that serves the dark-appearance capture to a
visitor whose computer is set to dark, and the light one otherwise. The alt
text and caption come from ``website/shots.json``; the image dimensions are
read from the PNG itself so the page reserves the right space before the image
arrives. A named shot with no file yet builds as a labelled placeholder and a
warning, so the site can be built before the captures are taken.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
import sys
from pathlib import Path

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
OUTPUT = REPO / "site"
IMAGE_DIR = OUTPUT / "img"


# ---------- Reading the sources ----------

def read_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def split_front_matter(text: str) -> tuple[dict, str]:
    """Separate a page's leading `---` block from its body."""
    if not text.startswith("---\n"):
        raise ValueError("a page must begin with a --- front matter block")
    end = text.find("\n---\n", 4)
    if end == -1:
        raise ValueError("the front matter block is never closed with ---")
    header = text[4:end]
    body = text[end + 5:]

    fields: dict = {}
    for line in header.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            raise ValueError(f"front matter line is not `key: value`: {line}")
        key, value = stripped.split(":", 1)
        fields[key.strip()] = value.strip()
    return fields, body


def load_pages() -> list[dict]:
    pages: list[dict] = []
    for path in sorted((WEBSITE / "pages").glob("*.html")):
        fields, body = split_front_matter(path.read_text(encoding="utf-8"))
        missing = []
        for required in ("title", "description", "nav_label"):
            if required not in fields:
                missing.append(required)
        if missing:
            raise ValueError(f"{path.name} is missing front matter: {', '.join(missing)}")
        fields["slug"] = path.stem
        fields["body"] = body
        pages.append(fields)
    return pages


# ---------- Images ----------

def png_size(path: Path) -> tuple[int, int]:
    """Width and height of a PNG, read from its header."""
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def picture_element(shot: dict, problems: list[str], modifier: str, up: str) -> str:
    """The <picture> for one screenshot, or a placeholder when it is missing."""
    identifier = shot["id"]

    # A STATIC shot is one image that does not follow the visitor's colour
    # scheme, because the colours in it are the subject. A figure showing what
    # three different courses look like, or that a built site does both light
    # and dark, would be arguing against itself if it changed to match the
    # reader's own setting.
    if shot.get("static"):
        return static_element(shot, problems, modifier, up)

    light = IMAGE_DIR / f"{identifier}-light.png"
    dark = IMAGE_DIR / f"{identifier}-dark.png"
    win_light = IMAGE_DIR / f"{identifier}-windows-light.png"
    win_dark = IMAGE_DIR / f"{identifier}-windows-dark.png"

    classes = ["shot"]
    if shot.get("capture", {}).get("kind") == "composite":
        classes.append("shot-composite")
    if modifier:
        classes.append(f"shot-{modifier}")
    classes_html = " ".join(classes)

    caption = shot.get("caption", "")
    caption_html = ""
    if caption:
        caption_html = f"\n    <figcaption>{caption}</figcaption>"

    if not light.exists() or not dark.exists():
        problems.append(f"screenshot '{identifier}' has not been captured yet")
        return (
            f'<figure class="{classes_html}">\n'
            f'    <div class="shot-missing">Screenshot pending: {identifier}</div>'
            f'{caption_html}\n'
            f'</figure>'
        )

    width, height = png_size(light)
    display_width = width // 2
    display_height = height // 2

    has_windows = win_light.exists() and win_dark.exists()
    win_prefix = f"{identifier}-windows-" if has_windows else ""

    sources: list[str] = []
    for scheme in ("dark", "light"):
        path = dark if scheme == "dark" else light
        query = ' media="(prefers-color-scheme: dark)"' if scheme == "dark" else ""

        if path.with_suffix(".webp").exists():
            win_webp_attr = ""
            if has_windows and (IMAGE_DIR / f"{win_prefix}{scheme}.webp").exists():
                win_webp_attr = f' data-win-srcset="{up}img/{win_prefix}{scheme}.webp"'
            sources.append(
                f'      <source srcset="{up}img/{identifier}-{scheme}.webp"{win_webp_attr} '
                f'type="image/webp"{query}>'
            )

        if scheme == "dark":
            win_png_attr = ""
            if has_windows:
                win_png_attr = f' data-win-srcset="{up}img/{win_prefix}dark.png"'
            sources.append(
                f'      <source srcset="{up}img/{identifier}-dark.png"{win_png_attr}{query}>'
            )

    joined = "\n".join(sources)
    win_src_attr = f' data-win-src="{up}img/{win_prefix}light.png"' if has_windows else ""

    return (
        f'<figure class="{classes_html}">\n'
        f'    <picture>\n'
        f'{joined}\n'
        f'      <img src="{up}img/{identifier}-light.png"{win_src_attr} alt="{shot["alt"]}"\n'
        f'           width="{display_width}" height="{display_height}" loading="lazy" decoding="async">\n'
        f'    </picture>{caption_html}\n'
        f'</figure>'
    )


# ---------- Assembling ----------

def static_element(shot: dict, problems: list[str], modifier: str, up: str) -> str:
    """One image, served to everybody, whatever their colour scheme."""
    identifier = shot["id"]
    source = IMAGE_DIR / f"{identifier}.png"
    win_source = IMAGE_DIR / f"{identifier}-windows.png"
    has_windows = win_source.exists()

    classes = "shot shot-static"
    if modifier:
        classes = f"shot shot-static shot-{modifier}"

    caption = shot.get("caption", "")
    caption_html = f"\n    <figcaption>{caption}</figcaption>" if caption else ""

    if not source.exists():
        problems.append(f"screenshot '{identifier}' has not been captured yet")
        return (
            f'<figure class="{classes}">\n'
            f'    <div class="shot-missing">Screenshot pending: {identifier}</div>'
            f'{caption_html}\n'
            f'</figure>'
        )

    width, height = png_size(source)
    webp = source.with_suffix(".webp")
    win_webp = IMAGE_DIR / f"{identifier}-windows.webp"

    webp_source = ""
    if webp.exists():
        win_webp_attr = f' data-win-srcset="{up}img/{identifier}-windows.webp"' if (has_windows and win_webp.exists()) else ""
        webp_source = f'      <source srcset="{up}img/{identifier}.webp"{win_webp_attr} type="image/webp">\n'

    win_src_attr = f' data-win-src="{up}img/{identifier}-windows.png"' if has_windows else ""

    return (
        f'<figure class="{classes}">\n'
        f'    <picture>\n'
        f'{webp_source}'
        f'      <img src="{up}img/{identifier}.png"{win_src_attr} alt="{shot["alt"]}"\n'
        f'           width="{width // 2}" height="{height // 2}" loading="lazy" decoding="async">\n'
        f'    </picture>{caption_html}\n'
        f'</figure>'
    )


SHOT_TOKEN = re.compile(r"\{\{shot:([a-z0-9-]+)(?:\|([a-z-]+))?\}\}")


def expand_shots(body: str, shots: dict, problems: list[str], page_name: str, up: str) -> str:
    def replace(match: re.Match) -> str:
        identifier = match.group(1)
        modifier = match.group(2) or ""
        shot = shots.get(identifier)
        if shot is None:
            problems.append(f"{page_name} refers to an unknown screenshot: {identifier}")
            return ""
        return picture_element(shot, problems, modifier, up)

    return SHOT_TOKEN.sub(replace, body)


def demo_links_html(site: dict) -> str:
    """The list of live example class sites, or nothing when they are off.

    The sites are built and published by ``website/shots/capture.py`` when the
    screenshots are taken, and their addresses are recorded in site.json. Set
    ``show_links`` to false there and the block disappears from the page --
    which is what to do if the example sites are ever taken down.
    """
    demo = site.get("demo_sites", {})
    if not demo.get("show_links"):
        return ""

    rows: list[str] = []
    for entry in demo.get("sites", []):
        rows.append(
            f'    <li><span class="label">{entry["code"]}</span> '
            f'<a href="{entry["url"]}">{entry["label"]}</a></li>'
        )
    if not rows:
        return ""
    joined = "\n".join(rows)
    return f'<ul class="links">\n{joined}\n  </ul>'


def navigation_html(pages: list[dict], order: list[str], current_slug: str, up: str) -> str:
    links: list[str] = []
    for slug in order:
        page = None
        for candidate in pages:
            if candidate["slug"] == slug:
                page = candidate
        if page is None:
            continue
        href = up if slug == "index" else f"{up}{slug}/"
        if slug == current_slug:
            links.append(
                f'<a href="{href}" aria-current="page">{page["nav_label"]}</a>'
            )
        else:
            links.append(f'<a href="{href}">{page["nav_label"]}</a>')
    return "\n      ".join(links)


def plain_navigation_html(pages: list[dict], order: list[str], up: str) -> str:
    """The footer's copy of the navigation: no current-page marking, since
    the footer is a way out of the page rather than a description of it."""
    links: list[str] = []
    for slug in order:
        for candidate in pages:
            if candidate["slug"] == slug:
                href = up if slug == "index" else f"{up}{slug}/"
                links.append(f'<a href="{href}">{candidate["nav_label"]}</a>')
    return "\n    ".join(links)


def substitute(template: str, values: dict) -> str:
    result = template
    for key, value in values.items():
        result = result.replace("{{" + key + "}}", str(value))
    return result


def output_path(slug: str) -> Path:
    if slug == "index":
        return OUTPUT / "index.html"
    return OUTPUT / slug / "index.html"


def build(check_only: bool) -> int:
    site = read_json(WEBSITE / "site.json")
    shot_list = read_json(WEBSITE / "shots.json")["shots"]
    shots = {}
    for shot in shot_list:
        shots[shot["id"]] = shot

    pages = load_pages()
    template = (WEBSITE / "layout" / "base.html").read_text(encoding="utf-8")
    problems: list[str] = []

    site_values = {
        "site_name": site["name"],
        "headline": site["headline"],
        "tagline": site["tagline"],
        "base_url": site["base_url"],
        "repo_url": site["repo_url"],
        "support_email": site["support_email"],
        "version": site["version"],
        "released": site["released"],
        "demo_links": demo_links_html(site),
    }

    written: list[Path] = []
    for page in pages:
        # How far this page sits below the site root. Every reference is
        # written relative to it — stylesheet, images, icon, navigation — so
        # the site works wherever it is put: at a domain root, or in a folder
        # on somebody else's server. Root-absolute paths looked fine on
        # plantoir.app and broke the moment the site was tried in a
        # subdirectory, where /assets/style.css means the DOMAIN's /assets.
        up = "./" if page["slug"] == "index" else "../"

        body = expand_shots(page["body"], shots, problems, page["slug"] + ".html", up)
        body = substitute(body, dict(site_values, up=up))

        canonical = site["base_url"]
        if page["slug"] != "index":
            canonical = f"{site['base_url']}/{page['slug']}"

        values = dict(site_values)
        values.update({
            "title": page["title"],
            "description": page["description"],
            "canonical": canonical,
            "up": up,
            "nav": navigation_html(pages, site["nav"], page["slug"], up),
            "nav_plain": plain_navigation_html(pages, site["nav"], up),
            "body": body,
            "body_class": page.get("body_class", ""),
        })

        html = substitute(template, values)
        leftover = re.findall(r"\{\{[a-z_]+\}\}", html)
        if leftover:
            problems.append(f"{page['slug']}.html left placeholders unfilled: {', '.join(sorted(set(leftover)))}")

        destination = output_path(page["slug"])
        if not check_only:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(html, encoding="utf-8")
        written.append(destination)

    if not check_only:
        assets = OUTPUT / "assets"
        assets.mkdir(parents=True, exist_ok=True)
        for asset in sorted((WEBSITE / "assets").iterdir()):
            if asset.is_file():
                shutil.copy2(asset, assets / asset.name)

    for problem in problems:
        print(f"⚠️  {problem}", file=sys.stderr)

    if check_only:
        if problems:
            print(f"\n{len(problems)} problem(s) found.", file=sys.stderr)
            return 1
        print(f"✅ {len(written)} page(s) check out.")
        return 0

    print(f"✅ Built {len(written)} page(s) into {OUTPUT.relative_to(REPO)}/")
    for path in written:
        print(f"   - {path.relative_to(REPO)}")
    if problems:
        print("\nThe site was written, but the warnings above still need attention.", file=sys.stderr)
        return 1
    return 0


def newest_source_time() -> float:
    """The most recent modification time anywhere in the website sources.

    Cheap enough to run per page request: the sources are a few dozen files.
    site/ itself is excluded — it is the OUTPUT, and rebuilding touches it.
    """
    newest = 0.0
    for file in WEBSITE.rglob("*"):
        if file.is_file() and not file.name.startswith("."):
            newest = max(newest, file.stat().st_mtime)
    return newest


def serve(port: int) -> int:
    """Preview site/ locally, rebuilding whenever a source file has changed.

    Each request for a page checks the sources' modification times and
    rebuilds first if anything moved, so the loop is: edit, refresh the
    browser, see it. Stop with Ctrl+C.
    """
    import functools
    import http.server
    import socketserver

    built_from = newest_source_time()

    class PreviewHandler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self) -> None:
            nonlocal built_from
            # Rebuild only ahead of page loads, not for every image the page
            # then pulls in — one check per refresh, not thirty.
            wants_page = self.path.endswith("/") or self.path.endswith(".html")
            if wants_page:
                current = newest_source_time()
                if current > built_from:
                    print("✏️  Sources changed — rebuilding…", flush=True)
                    build(check_only=False)
                    built_from = current
            super().do_GET()

        def end_headers(self) -> None:
            # Without this the browser caches assets heuristically and an
            # edited stylesheet or screenshot can survive a refresh — the
            # copied images keep their original (old) timestamps, which
            # makes the heuristic window days long. A preview never caches.
            self.send_header("Cache-Control", "no-store")
            super().end_headers()

        def log_message(self, format: str, *args) -> None:
            pass  # one line per asset drowns the rebuild messages

    class PreviewServer(socketserver.ThreadingTCPServer):
        # Without this, a just-stopped preview leaves its socket in
        # TIME_WAIT and an immediate restart silently hops to the next
        # port — the browser tab from last time then shows stale pages.
        allow_reuse_address = True

    handler = functools.partial(PreviewHandler, directory=str(OUTPUT))
    last_error: OSError | None = None
    for candidate in range(port, port + 10):
        try:
            with PreviewServer(("127.0.0.1", candidate), handler) as server:
                address = f"http://localhost:{candidate}/"
                print(f"\n🔎 Previewing at {address} — edit a source,")
                print("   refresh the browser, and the page rebuilds. Ctrl+C stops it.")
                # Open the browser only for a person at a terminal: a piped or
                # scripted run (tests, agents) must not fling windows around.
                if sys.stdout.isatty():
                    import webbrowser
                    webbrowser.open(address)
                try:
                    server.serve_forever()
                except KeyboardInterrupt:
                    print("\nPreview stopped.")
                return 0
        except OSError as error:
            last_error = error  # port in use; try the next one
    print(f"Could not find a free port near {port}: {last_error}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Build plantoir.app into site/.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="report problems without writing anything",
    )
    parser.add_argument(
        "--deploy",
        action="store_true",
        help="after a clean build, publish site/ to plantoir.app on Netlify",
    )
    parser.add_argument(
        "--serve",
        action="store_true",
        help="after building, preview site/ locally, rebuilding on refresh",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8930,
        help="port for --serve (default 8930; the next free one is tried if busy)",
    )
    parser.add_argument(
        "--verify-deploy",
        action="store_true",
        help="build nothing; fetch https://plantoir.app and confirm it is serving "
             "the version in site.json (exit 0 match, 1 unknown/network problem, "
             "2 confirmed mismatch)",
    )
    arguments = parser.parse_args()
    if arguments.verify_deploy:
        if arguments.check or arguments.deploy or arguments.serve:
            parser.error("--verify-deploy stands alone: it neither builds nor deploys")
        import netlify_deploy
        return {"match": 0, "mismatch": 2, "unknown": 1}[netlify_deploy.verify_live()]
    if arguments.check and (arguments.deploy or arguments.serve):
        parser.error("--check writes nothing, so there is nothing to publish or preview")
    if arguments.deploy and arguments.serve:
        parser.error("--serve is for looking before you publish; run --deploy after")
    result = build(check_only=arguments.check)
    if arguments.serve:
        if result != 0:
            print("Serving anyway — fix the warnings above and refresh.", file=sys.stderr)
        return serve(arguments.port)
    if arguments.deploy:
        if result != 0:
            print("Not deploying: fix the build warnings above first.", file=sys.stderr)
            return result
        import netlify_deploy
        return netlify_deploy.deploy()
    return result


if __name__ == "__main__":
    raise SystemExit(main())
