"""The update feeds plantoir.app serves: copied, checked, and checked live (#204).

A released Plantoir asks ``https://plantoir.app/updates/macos.xml`` once a day
whether there is a new version (and, from Windows' v1.4.0,
``updates/windows.xml``). Each feed is SIGNED — on the mac the signature is a
trailing comment inside the file, and NetSparkle keeps it in a separate
``windows.xml.signature`` — so the site must serve the exact bytes that were
signed. This module is the one place that knows that:

- ``copy_feeds`` copies ``website/updates/*.xml`` and ``*.signature`` into
  ``site/updates/`` BYTE FOR BYTE. Nothing is parsed and written back: a feed
  re-serialised by any XML library loses its signature, and the updater then
  refuses it — silently on the daily check.
- ``problems_with`` is what ``build.py --check`` asks of each feed: it is well
  formed, it is signed, every download is the platform's own asset under its
  own version's release, and nothing names the other platform's asset — so a
  feed that would offer a Windows installer to a Mac cannot pass.
- ``newest_version`` is what ``build.py --deploy`` compares with
  ``MARKETING_VERSION`` before publishing.
- ``verify_live`` is what a deploy checks afterwards: the live feed is these
  bytes, and its newest download actually exists — the check for a feed that
  points at nothing (deployed before its release was published).

``website/update_feed.py`` WRITES the mac feed at a release cut; this module
only copies and checks. Both are documented in RELEASING.md → "The update
feed (macOS)".
"""

from __future__ import annotations

import hashlib
import re
import shutil
import urllib.error
import urllib.request
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
RELEASE_DOWNLOADS = "https://github.com/russellgordon/plantoir/releases/download/"

# The platform each feed file is for, and the one asset name its downloads may
# carry. Frozen names (RELEASING.md): the site's download cards and the feeds
# both depend on them.
PLATFORM_ASSETS = {
    "macos.xml": "Plantoir-macOS.dmg",
    "windows.xml": "PlantoirSetup.exe",
}


def copy_feeds(source: Path, destination: Path) -> list[Path]:
    """Copy every feed and signature file, byte for byte. Returns what was copied."""
    copied: list[Path] = []
    if not source.is_dir():
        return copied
    for file in sorted(source.iterdir()):
        if not file.is_file():
            continue
        if file.suffix != ".xml" and not file.name.endswith(".xml.signature"):
            continue
        destination.mkdir(parents=True, exist_ok=True)
        target = destination / file.name
        shutil.copyfile(file, target)
        copied.append(target)
    return copied


def items_of(feed: Path) -> list[dict]:
    """Every item in a feed: its version, build, download address and length."""
    root = ElementTree.fromstring(feed.read_bytes())
    items: list[dict] = []
    for item in root.iter("item"):
        short = item.findtext(f"{{{SPARKLE_NAMESPACE}}}shortVersionString") or ""
        build = item.findtext(f"{{{SPARKLE_NAMESPACE}}}version") or ""
        enclosure = item.find("enclosure")
        url = ""
        length = ""
        if enclosure is not None:
            url = enclosure.get("url", "")
            length = enclosure.get("length", "")
        items.append({"short": short.strip(), "build": build.strip(), "url": url, "length": length})
    return items


def build_number(item: dict) -> int:
    """An item's build, as a number; 0 when it is not one."""
    try:
        return int(item["build"])
    except ValueError:
        return 0


def newest_item(feed: Path) -> dict | None:
    """The item with the highest build — the one the updater offers."""
    newest: dict | None = None
    for item in items_of(feed):
        if newest is None or build_number(item) > build_number(newest):
            newest = item
    return newest


def newest_version(feed: Path) -> str | None:
    """The newest item's version ("1.3.2"), or None for a feed with no items."""
    newest = newest_item(feed)
    if newest is None:
        return None
    return newest["short"]


def problems_with(feed: Path) -> list[str]:
    """Why a feed must not be published, or an empty list."""
    problems: list[str] = []
    name = feed.name
    own_asset = PLATFORM_ASSETS.get(name)
    if own_asset is None:
        return [f"updates/{name}: not a feed this site knows (expected one of {', '.join(sorted(PLATFORM_ASSETS))})"]
    data = feed.read_bytes()
    try:
        items = items_of(feed)
    except ElementTree.ParseError as error:
        return [f"updates/{name}: not well-formed XML ({error})"]

    if name == "macos.xml":
        if b"<!-- sparkle-signatures:" not in data:
            problems.append("updates/macos.xml: carries no signature — the app refuses an unsigned feed")
    else:
        signature = feed.with_name(name + ".signature")
        if not signature.is_file():
            problems.append(f"updates/{name}: no {name}.signature beside it")

    if not items:
        problems.append(f"updates/{name}: has no items")
    for item in items:
        expected = f"{RELEASE_DOWNLOADS}v{item['short']}/{own_asset}"
        if item["url"] != expected:
            problems.append(
                f"updates/{name}: {item['short']} ({item['build']}) downloads {item['url'] or 'nothing'}, "
                f"expected {expected}"
            )
    for other_name, other_asset in PLATFORM_ASSETS.items():
        if other_name != name and other_asset.encode() in data:
            problems.append(f"updates/{name}: names {other_asset}, the other platform's download")
    return problems


def verify_live(base_url: str, local_feed: Path, fetch=None) -> str:
    """Confirm the live feed is these bytes and its newest download is there.

    Returns "match", "mismatch" or "unknown" — the same three answers as
    ``netlify_deploy.verify_live``, for the same reason: a network problem is
    not evidence of a bad deploy. ``fetch`` is for tests: (url, method) →
    (status, headers, body).
    """
    if fetch is None:
        fetch = _fetch
    feed_url = f"{base_url.rstrip('/')}/updates/{local_feed.name}"
    try:
        status, _, body = fetch(feed_url, "GET")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print(f"⚠️ Could not fetch {feed_url} ({error}); check it by hand.")
        return "unknown"
    if status != 200:
        print(f"❌ {feed_url} answered {status}.")
        return "mismatch"
    live = hashlib.sha256(body).hexdigest()
    ours = hashlib.sha256(local_feed.read_bytes()).hexdigest()
    if live != ours:
        print(f"❌ {feed_url} is not the feed in site/ (SHA-256 {live[:12]}… against {ours[:12]}…). "
              f"A changed byte breaks its signature.")
        return "mismatch"
    newest = newest_item(local_feed)
    if newest is None:
        print(f"❌ {feed_url} has no items.")
        return "mismatch"
    try:
        status, headers, _ = fetch(newest["url"], "HEAD")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print(f"⚠️ Could not reach {newest['url']} ({error}); check it by hand.")
        return "unknown"
    if status != 200:
        print(f"❌ The newest update, {newest['short']}, points at {newest['url']}, which answered {status}. "
              f"Was the feed deployed before its release was published?")
        return "mismatch"
    length = headers.get("Content-Length", "")
    if length and newest["length"] and length != newest["length"]:
        print(f"❌ {newest['url']} is {length} bytes; the feed says {newest['length']}.")
        return "mismatch"
    print(f"✅ {feed_url} is live, signed as committed, and its newest download ({newest['short']}) is there.")
    return "match"


def _fetch(url: str, method: str) -> tuple[int, dict, bytes]:
    request = urllib.request.Request(
        url, method=method, headers={"Cache-Control": "no-cache", "Pragma": "no-cache"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read() if method == "GET" else b""
            return response.status, dict(response.headers), body
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers or {}), b""


def marketing_version(project_yml: Path) -> str | None:
    """MARKETING_VERSION from mac-app/project.yml, as text."""
    match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', project_yml.read_text(encoding="utf-8"))
    if match is None:
        return None
    return match.group(1)
