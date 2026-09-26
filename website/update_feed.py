#!/usr/bin/env python3
"""Build and sign the mac's update feed at a release cut (#204).

    python3 website/update_feed.py macos --version 1.3.2 \\
        --dmg mac-app/dist/Plantoir-macOS.dmg --notes approved-notes.md [--required-warning]

Run by the `cut-release` skill AFTER the GitHub release is published (never
before: the feed would offer a download that does not exist yet), from the
EXACT DMG that was uploaded — after `codesign`, notarization and `stapler
staple`, each of which changes its bytes.

What it does, in order — and what it refuses:

1. Mounts the DMG read-only and reads the app's version and build. A DMG whose
   version is not `--version` is refused: that is a bundle built before the
   bump, the mistake `cut-release` step 5 exists to catch.
2. Prepends this release's notes to `website/updates/macos-notes.html` — the
   CUMULATIVE notes, one `<div data-sparkle-version="<build>">` per release,
   newest first. The updater shows the notes of the version it offers; the
   style line at the top hides every section for the version a teacher is
   already on and older, so a teacher who skipped a release still reads its
   warning (`contracts/shared-rules.json` → `appUpdates.notes`).
3. In a fresh folder — the DMG, those notes, and the current feed — runs
   Sparkle's `generate_appcast`, signing with the `plantoir-macos` Keychain key
   (the tools read it; nothing here prints it). A release with a REQUIRED
   warning is marked critical from every version (no Skip, no Remind Me
   Later); otherwise the newest earlier release that had one stays critical
   for teachers below it.
   Since #312 the app carries the website builder's helpers and a ~450 MB
   DMG, so the new item carries DELTAS from the three newest builds already
   in the feed (`--maximum-deltas 3`): their DMGs are fetched from the
   addresses the feed itself gives — the exact bytes teachers installed, so
   no copy has to be kept anywhere — checked for length and build, and put
   beside this one under their build's name. generate_appcast REWRITES the
   item of every archive it is given — measured with --versions: the earlier
   item's download pointed at THIS release and lost its notes — so each
   earlier item is put back exactly as it was in the feed, the feed is signed
   again with the same key, and every earlier item must then compare equal
   to the one that was there, or the cut is refused. The
   `.delta` files are written beside the DMG, to be uploaded to the same
   release (their addresses use the same prefix). A Swift-only release's
   delta measured 3.7 MB against a 466 MB DMG.
4. Verifies the result with `sign_update --verify` and checks the new item's
   download address and length, then copies feed and notes into
   `website/updates/`. `website/build.py` copies the feed into `site/` byte for
   byte; `--deploy` checks it live.

`--rehearsal <path>` writes the feed to that path instead (it must be under
`website/updates/` and is never committed), takes `--download-prefix`, keeps
its own cumulative notes beside it, names the download
`Plantoir-macOS-REHEARSAL.dmg` (the name `publish.sh --rehearsal-feed` gives
it, which `cut-release` refuses to attach), and never touches `macos.xml` or
`macos-notes.html`. Run it once per rehearsal build, oldest first, so the
second run sees the first's notes — which is how the rehearsal checks that
the notes of the installed version are hidden. `--ed-key-file` replaces the Keychain key — for the
tests, which use a throwaway key they make themselves.
"""

from __future__ import annotations

import argparse
import html
import plistlib
import urllib.request
import xml.etree.ElementTree as ElementTree
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
SPARKLE_BIN = REPO / "mac-app" / "Vendor" / "Sparkle" / "bin"
KEYCHAIN_ACCOUNT = "plantoir-macos"
DOWNLOADS = "https://github.com/russellgordon/plantoir/releases/download/"
ASSET = "Plantoir-macOS.dmg"
REHEARSAL_ASSET = "Plantoir-macOS-REHEARSAL.dmg"
# How many earlier builds the new item carries a delta from (#312). Each costs
# one earlier DMG downloaded at the cut (~450 MB) and a few MB uploaded.
MAXIMUM_DELTAS = 3
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
STYLE_LINE = ("<style>div.sparkle-installed-version, div.sparkle-installed-version ~ div "
              "{ display: none; }</style>")


class Refusal(Exception):
    """Something that must stop the cut, in a sentence."""


def tool(name: str) -> Path:
    path = SPARKLE_BIN / name
    if not path.is_file():
        raise Refusal(f"{path} is missing — run mac-app/Vendor/fetch-sparkle.sh first.")
    return path


def read_dmg_version(dmg: Path) -> tuple[str, str]:
    """(version, build) of the one app inside a DMG, mounted read-only."""
    with tempfile.TemporaryDirectory(prefix="plantoir-feed-mount-") as mount:
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, str(dmg)],
                       check=True, capture_output=True)
        try:
            apps = sorted(Path(mount).glob("*.app"))
            if len(apps) != 1:
                raise Refusal(f"{dmg.name} holds {len(apps)} apps; expected exactly one.")
            with open(apps[0] / "Contents" / "Info.plist", "rb") as handle:
                info = plistlib.load(handle)
            return str(info.get("CFBundleShortVersionString", "")), str(info.get("CFBundleVersion", ""))
        finally:
            subprocess.run(["hdiutil", "detach", mount, "-quiet"], capture_output=True)


# Lines the approved GitHub notes carry that do not belong in the Mac's update
# window (the slice-2 review's M1): a label for the OTHER platform, and the
# Downloads section with its SHA-256 table. The cut-release skill writes the
# notes in exactly this shape ("Write the notes"), and marks platform-only
# lines "(Windows)" / "(macOS)".
OTHER_PLATFORM_LABEL = "(Windows)"
OWN_PLATFORM_LABEL = "(macOS)"
SECTIONS_NOT_SHOWN = ("downloads",)


def inline(text: str) -> str:
    """Escape a line, then turn back on what the notes template uses inline:
    **bold**, `code` and [a link](https://…). Nothing else becomes markup."""
    # Code first, set aside, so nothing inside backticks becomes bold or a link.
    spans: list[str] = []

    def keep_code(match: re.Match) -> str:
        spans.append(f"<code>{html.escape(match.group(1), quote=True)}</code>")
        return f"\x00{len(spans) - 1}\x00"

    text = re.sub(r"`([^`]+)`", keep_code, text)
    escaped = html.escape(text, quote=True)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', escaped)
    for index, span in enumerate(spans):
        escaped = escaped.replace(f"\x00{index}\x00", span)
    return escaped


def heading_text(line: str) -> str | None:
    """The text of a heading line — `## New` or a line that is only `**New**` — or None."""
    if line.startswith("#"):
        return line.lstrip("#").strip()
    match = re.fullmatch(r"\*\*([^*]+)\*\*:?", line)
    if match:
        return match.group(1).strip()
    return None


def notes_for_the_mac(notes_markdown: str) -> list[str]:
    """The approved notes, less what a Mac's update window must not show:
    the Downloads section (its checksum table and the line under it), every
    line labelled for Windows, and table rows anywhere. "(macOS)" labels are
    dropped, since every line in this window is about the Mac."""
    kept: list[str] = []
    skipping_section = False
    for raw in notes_markdown.splitlines():
        line = raw.strip()
        heading = heading_text(line)
        if heading is not None:
            skipping_section = heading.lower() in SECTIONS_NOT_SHOWN
            if skipping_section:
                continue
        if skipping_section:
            continue
        if line.startswith("|"):
            continue
        if OTHER_PLATFORM_LABEL in line:
            continue
        # The one-platform sentence the skill requires ("Windows: no changes…")
        # is about the other download, not this one.
        if line.lower().startswith("windows:") or line.lower().startswith("- windows:"):
            continue
        kept.append(line.replace(" " + OWN_PLATFORM_LABEL, "").replace(OWN_PLATFORM_LABEL, "").rstrip())
    return kept


def rendered_lines(kept: list[str]) -> list[str]:
    """The kept lines as HTML: headings, bullets, `> ` quotes and paragraphs.

    A heading with nothing under it — every item under "Fixed" was a Windows
    one, say — is dropped rather than shown empty (the third review's L6).
    """
    blocks: list[tuple[str, list[str]]] = []   # (heading html or "", its body lines)
    current_heading: str = ""
    current_body: list[str] = []
    in_list = False
    for line in kept:
        heading = heading_text(line) if line else None
        if heading is not None:
            if in_list:
                current_body.append("</ul>")
                in_list = False
            blocks.append((current_heading, current_body))
            current_heading = f"<h3>{inline(heading)}</h3>"
            current_body = []
            continue
        if line.startswith("- ") or line.startswith("* "):
            if not in_list:
                current_body.append("<ul>")
                in_list = True
            current_body.append(f"<li>{inline(line[2:].strip())}</li>")
            continue
        if in_list:
            current_body.append("</ul>")
            in_list = False
        if not line:
            continue
        if line.startswith(">"):
            current_body.append(f"<blockquote><p>{inline(line.lstrip('>').strip())}</p></blockquote>")
        else:
            current_body.append(f"<p>{inline(line)}</p>")
    if in_list:
        current_body.append("</ul>")
    blocks.append((current_heading, current_body))
    lines: list[str] = []
    for heading, body in blocks:
        if heading and not body:
            continue
        if heading:
            lines.append(heading)
        lines.extend(body)
    return lines


def notes_section(version: str, build: str, notes_markdown: str, required_warning: bool) -> str:
    """One release's notes as the HTML section the updater shows.

    A small reading of the approved notes, covering what the cut-release
    template uses: headings (`#` or a line that is only **bold**), bullets,
    `> ` quotes, **bold**, `code` and links. Every character is escaped first —
    the notes are text, and only those shapes become markup; a heading left
    with nothing under it is dropped.
    """
    body = rendered_lines(notes_for_the_mac(notes_markdown))
    lines: list[str] = []
    attributes = f'data-sparkle-version="{html.escape(build)}"'
    if required_warning:
        attributes += " data-required-warning"
    lines.append(f"<div {attributes}>")
    lines.append(f"<h2>Plantoir {html.escape(version)}</h2>")
    lines.extend(body)
    lines.append("</div>")
    return "\n".join(lines)


def cumulative_notes(existing: str, section: str) -> str:
    """The new section first, under the one style line, and every earlier one after."""
    body = existing.replace(STYLE_LINE, "").strip()
    parts = [STYLE_LINE, section]
    if body:
        parts.append(body)
    return "\n".join(parts) + "\n"


def critical_version(notes: str, required_warning: bool) -> str | None:
    """What to pass as `--critical-update-version`, or None for no flag.

    "" (critical from every version) when THIS release has a required warning;
    otherwise the build of the newest earlier release that had one, so a
    teacher below it still cannot skip past its warning.
    """
    if required_warning:
        return ""
    marker = "data-required-warning"
    for line in notes.splitlines():
        if line.startswith("<div ") and marker in line and 'data-sparkle-version="' in line:
            start = line.index('data-sparkle-version="') + len('data-sparkle-version="')
            return line[start:line.index('"', start)]
    return None


def earlier_builds(existing_feed: Path, build: str) -> list[dict]:
    """The newest MAXIMUM_DELTAS items already in the feed, other than this build.

    The builds IN THE FEED, not the newest tags: releases before Sparkle, and
    Windows-only tags, are not in it, and no app below the feed's oldest item
    can ever ask for a delta (the plan review's H4).
    """
    if not existing_feed.is_file():
        return []
    import update_feeds
    items = [item for item in update_feeds.items_of(existing_feed) if item["build"] != build]
    items.sort(key=update_feeds.build_number, reverse=True)
    return items[:MAXIMUM_DELTAS]


def download_earlier_dmg(item: dict, folder: Path) -> Path:
    """An earlier release's DMG, from the address its feed item gives."""
    target = folder / f"download-{item['build']}.dmg"
    with urllib.request.urlopen(item["url"]) as response, open(target, "wb") as handle:
        shutil.copyfileobj(response, handle)
    return target


def items_by_build(feed: Path) -> dict[str, bytes]:
    """Each item of a feed, keyed by its build, as canonical XML — so an item
    can be compared across a run of generate_appcast, which rewrites the file."""
    ElementTree.register_namespace("sparkle", SPARKLE_NS)
    root = ElementTree.fromstring(feed.read_bytes())
    found: dict[str, bytes] = {}
    for item in root.iter("item"):
        build = (item.findtext(f"{{{SPARKLE_NS}}}version") or "").strip()
        found[build] = ElementTree.canonicalize(ElementTree.tostring(item), strip_text=True).encode()
    return found


def deltas_of(feed: Path, build: str) -> list[dict]:
    """The delta enclosures of one item: from which build, where, how long."""
    root = ElementTree.fromstring(feed.read_bytes())
    for item in root.iter("item"):
        if (item.findtext(f"{{{SPARKLE_NS}}}version") or "").strip() != build:
            continue
        found: list[dict] = []
        for deltas in item.findall(f"{{{SPARKLE_NS}}}deltas"):
            for enclosure in deltas.findall("enclosure"):
                found.append({
                    "from": enclosure.get(f"{{{SPARKLE_NS}}}deltaFrom", ""),
                    "url": enclosure.get("url", ""),
                    "length": enclosure.get("length", ""),
                })
        return found
    return []


ITEM_PATTERN = re.compile(r"<item>.*?</item>", re.DOTALL)
SIGNATURE_PATTERN = re.compile(r"\n?<!-- sparkle-signatures:.*?-->\n?", re.DOTALL)


def item_texts(text: str) -> dict[str, str]:
    """Each item of a feed as the text it was written with, keyed by its build."""
    found: dict[str, str] = {}
    for match in ITEM_PATTERN.finditer(text):
        build = re.search(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>", match.group(0))
        if build:
            found[build.group(1)] = match.group(0)
    return found


def restore_earlier_items(written: str, original: str, build: str) -> str:
    """The feed generate_appcast wrote, with every item but `build` put back
    as it was in `original`, and no signature (it no longer matches)."""
    before = item_texts(original)

    def put_back(match: re.Match) -> str:
        text = match.group(0)
        found = re.search(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>", text)
        if found and found.group(1) != build and found.group(1) in before:
            return before[found.group(1)]
        return text

    return SIGNATURE_PATTERN.sub("\n", ITEM_PATTERN.sub(put_back, written)).rstrip("\n") + "\n"


def key_arguments(ed_key_file: Path | None) -> list[str]:
    if ed_key_file is not None:
        return ["--ed-key-file", str(ed_key_file)]
    return ["--account", KEYCHAIN_ACCOUNT]


def build_feed(version: str, dmg: Path, notes_markdown: str, required_warning: bool,
               updates_dir: Path, ed_key_file: Path | None = None,
               rehearsal: Path | None = None, download_prefix: str | None = None,
               earlier_dmg=download_earlier_dmg) -> Path:
    """Build, sign, verify and install the feed. Returns where it was written.

    `earlier_dmg(item, folder) -> Path` fetches an earlier release's DMG for a
    delta; the tests hand theirs over directly. Deltas land beside `dmg`.
    """
    generate = tool("generate_appcast")
    sign = tool("sign_update")

    dmg_version, build = read_dmg_version(dmg)
    if dmg_version != version:
        raise Refusal(f"{dmg.name} is Plantoir {dmg_version}, not {version}: a bundle built before "
                      f"the version was raised. Rebuild it with publish.sh -Sign.")
    if not build.isdigit():
        raise Refusal(f"{dmg.name} has build '{build}', which is not a number — publish.sh sets it.")

    feed_path = updates_dir / "macos.xml"
    notes_path = updates_dir / "macos-notes.html"
    if rehearsal is not None:
        if updates_dir.resolve() not in rehearsal.resolve().parents:
            raise Refusal(f"A rehearsal feed must be written under {updates_dir}, not {rehearsal}.")
        if rehearsal.resolve() == feed_path.resolve():
            raise Refusal("A rehearsal must never write the real feed.")
        if not download_prefix:
            raise Refusal("A rehearsal needs --download-prefix (the pre-release's download address).")
    prefix = download_prefix or f"{DOWNLOADS}v{version}/"
    asset = ASSET
    existing_feed = feed_path
    if rehearsal is not None:
        asset = REHEARSAL_ASSET
        existing_feed = rehearsal
        notes_path = rehearsal.with_name(rehearsal.stem + "-notes.html")

    existing_notes = notes_path.read_text(encoding="utf-8") if notes_path.is_file() else ""
    section = notes_section(version, build, notes_markdown, required_warning)
    notes = cumulative_notes(existing_notes, section)
    critical = critical_version(notes, required_warning)

    sys.path.insert(0, str(WEBSITE))
    import update_feeds

    with tempfile.TemporaryDirectory(prefix="plantoir-feed-") as work:
        folder = Path(work) / "archives"
        folder.mkdir()
        shutil.copyfile(dmg, folder / asset)
        (folder / (Path(asset).stem + ".html")).write_text(notes, encoding="utf-8")
        # The earlier releases a delta is made from, each under its own build's
        # name: every release's asset has the same name, so they cannot share
        # one folder as downloaded.
        downloads = Path(work) / "earlier"
        downloads.mkdir()
        earlier = earlier_builds(existing_feed, build)
        for item in earlier:
            fetched = Path(earlier_dmg(item, downloads))
            if item["length"] and str(fetched.stat().st_size) != item["length"]:
                raise Refusal(f"The DMG for build {item['build']} is {fetched.stat().st_size} bytes; "
                              f"its feed item says {item['length']}.")
            if read_dmg_version(fetched)[1] != item["build"]:
                raise Refusal(f"The DMG at {item['url']} is not build {item['build']}.")
            shutil.copyfile(fetched, folder / f"Plantoir-{item['build']}.dmg")
        output = Path(work) / "macos.xml"
        before: dict[str, bytes] = {}
        original_text = ""
        if existing_feed.is_file():
            shutil.copyfile(existing_feed, output)
            before = items_by_build(output)
            original_text = output.read_text(encoding="utf-8")
        command = [str(generate)] + key_arguments(ed_key_file) + [
            "--download-url-prefix", prefix,
            "--link", "https://plantoir.app/",
            "--maximum-deltas", str(MAXIMUM_DELTAS),
            # Write THIS item only; the earlier DMGs are delta sources, and
            # without this generate_appcast infers items for them too, with
            # this release's download prefix (the plan review's H4).
            "--versions", build,
            "--embed-release-notes",
            "-o", str(output),
        ]
        if critical is not None:
            command += ["--critical-update-version", critical]
        command.append(str(folder))
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise Refusal(f"generate_appcast failed:\n{result.stdout}{result.stderr}")
        if earlier:
            # Put the earlier items back as they were, and sign again.
            output.write_text(restore_earlier_items(output.read_text(encoding="utf-8"), original_text, build),
                              encoding="utf-8")
            signed = subprocess.run([str(sign)] + key_arguments(ed_key_file) + [str(output)],
                                    capture_output=True, text=True)
            if signed.returncode != 0:
                raise Refusal(f"Signing the feed again failed:\n{signed.stdout}{signed.stderr}")

        verify = subprocess.run([str(sign), "--verify"] + key_arguments(ed_key_file) + [str(output)],
                                capture_output=True, text=True)
        if verify.returncode != 0:
            raise Refusal(f"The feed did not verify:\n{verify.stdout}{verify.stderr}")

        # Every item that was in the feed and is still in it is unchanged.
        after = items_by_build(output)
        for earlier_build, earlier_xml in before.items():
            if earlier_build == build or earlier_build not in after:
                continue
            if after[earlier_build] != earlier_xml:
                raise Refusal(f"generate_appcast changed the item for build {earlier_build}; "
                              f"only this release's item may change.")
        deltas = deltas_of(output, build)
        wanted = sorted(item["build"] for item in earlier)
        if sorted(delta["from"] for delta in deltas) != wanted:
            raise Refusal(f"The new item carries deltas from {sorted(d['from'] for d in deltas)}; "
                          f"expected {wanted}.")
        delta_files: list[Path] = []
        for delta in deltas:
            name = delta["url"].rsplit("/", 1)[-1]
            if not delta["url"].startswith(prefix) or not name.endswith(".delta") or not (folder / name).is_file():
                raise Refusal(f"A delta downloads {delta['url']}, which this cut did not make under {prefix}.")
            delta_files.append(folder / name)

        newest = update_feeds.newest_item(output)
        if newest is None or newest["build"] != build:
            raise Refusal("The new release is not the newest item in the feed.")
        if newest["url"] != prefix + asset:
            raise Refusal(f"The new item downloads {newest['url']}, not {prefix + asset}.")
        if newest["length"] != str(dmg.stat().st_size):
            raise Refusal(f"The new item says {newest['length']} bytes; the DMG is {dmg.stat().st_size}.")

        # Beside the DMG, to be uploaded to the same release.
        for delta_file in delta_files:
            shutil.copyfile(delta_file, dmg.parent / delta_file.name)
            print(f"   delta from an earlier build: {dmg.parent / delta_file.name} "
                  f"({delta_file.stat().st_size:,} bytes) — upload it to the release beside the DMG")

        updates_dir.mkdir(parents=True, exist_ok=True)
        if rehearsal is not None:
            rehearsal.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(output, rehearsal)
            notes_path.write_text(notes, encoding="utf-8")
            return rehearsal
        shutil.copyfile(output, feed_path)
        notes_path.write_text(notes, encoding="utf-8")
        return feed_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Build and sign the mac's update feed at a release cut.")
    parser.add_argument("platform", choices=["macos"], help="only the mac's feed is built here")
    parser.add_argument("--version", required=True)
    parser.add_argument("--dmg", required=True, type=Path)
    parser.add_argument("--notes", required=True, type=Path, help="the approved notes for this release")
    parser.add_argument("--required-warning", action="store_true",
                        help="this release has a warning a teacher must read before updating")
    parser.add_argument("--updates-dir", type=Path, default=WEBSITE / "updates")
    parser.add_argument("--ed-key-file", type=Path, help="for tests: a throwaway key instead of the Keychain's")
    parser.add_argument("--rehearsal", type=Path, help="write a rehearsal feed here, never the real one")
    parser.add_argument("--download-prefix", help="with --rehearsal: the pre-release's download address")
    arguments = parser.parse_args()
    try:
        written = build_feed(
            arguments.version, arguments.dmg, arguments.notes.read_text(encoding="utf-8"),
            arguments.required_warning, arguments.updates_dir, arguments.ed_key_file,
            arguments.rehearsal, arguments.download_prefix,
        )
    except Refusal as refusal:
        print(f"❌ {refusal}", file=sys.stderr)
        return 1
    print(f"✅ Wrote and verified {written}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
