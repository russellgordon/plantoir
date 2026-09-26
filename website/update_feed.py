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
4. Verifies the result with `sign_update --verify` and checks the new item's
   download address and length, then copies feed and notes into
   `website/updates/`. `website/build.py` copies the feed into `site/` byte for
   byte; `--deploy` checks it live.

`--rehearsal <path>` writes the feed to that path instead (it must be under
`website/updates/`), takes `--download-prefix`, and never touches `macos.xml`
or `macos-notes.html`. `--ed-key-file` replaces the Keychain key — for the
tests, which use a throwaway key they make themselves.
"""

from __future__ import annotations

import argparse
import html
import plistlib
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


def notes_section(version: str, build: str, notes_markdown: str, required_warning: bool) -> str:
    """One release's notes as the HTML section the updater shows.

    A deliberately small reading of the approved notes: `#` headings become
    headings, `-` lines become a list, everything else a paragraph. Every
    character is escaped — the notes are text, never markup.
    """
    lines: list[str] = []
    attributes = f'data-sparkle-version="{html.escape(build)}"'
    if required_warning:
        attributes += " data-required-warning"
    lines.append(f"<div {attributes}>")
    lines.append(f"<h2>Plantoir {html.escape(version)}</h2>")
    in_list = False
    for raw in notes_markdown.splitlines():
        line = raw.strip()
        if line.startswith("- ") or line.startswith("* "):
            if not in_list:
                lines.append("<ul>")
                in_list = True
            lines.append(f"<li>{html.escape(line[2:].strip())}</li>")
            continue
        if in_list:
            lines.append("</ul>")
            in_list = False
        if not line:
            continue
        if line.startswith("#"):
            lines.append(f"<h3>{html.escape(line.lstrip('#').strip())}</h3>")
        else:
            lines.append(f"<p>{html.escape(line)}</p>")
    if in_list:
        lines.append("</ul>")
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


def key_arguments(ed_key_file: Path | None) -> list[str]:
    if ed_key_file is not None:
        return ["--ed-key-file", str(ed_key_file)]
    return ["--account", KEYCHAIN_ACCOUNT]


def build_feed(version: str, dmg: Path, notes_markdown: str, required_warning: bool,
               updates_dir: Path, ed_key_file: Path | None = None,
               rehearsal: Path | None = None, download_prefix: str | None = None) -> Path:
    """Build, sign, verify and install the feed. Returns where it was written."""
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

    existing_notes = notes_path.read_text(encoding="utf-8") if notes_path.is_file() else ""
    if rehearsal is not None:
        existing_notes = ""
    section = notes_section(version, build, notes_markdown, required_warning)
    notes = cumulative_notes(existing_notes, section)
    critical = critical_version(notes, required_warning)

    with tempfile.TemporaryDirectory(prefix="plantoir-feed-") as work:
        folder = Path(work) / "archives"
        folder.mkdir()
        shutil.copyfile(dmg, folder / ASSET)
        (folder / "Plantoir-macOS.html").write_text(notes, encoding="utf-8")
        output = Path(work) / "macos.xml"
        if rehearsal is None and feed_path.is_file():
            shutil.copyfile(feed_path, output)
        command = [str(generate)] + key_arguments(ed_key_file) + [
            "--download-url-prefix", prefix,
            "--link", "https://plantoir.app/",
            "--maximum-deltas", "0",
            "--embed-release-notes",
            "-o", str(output),
        ]
        if critical is not None:
            command += ["--critical-update-version", critical]
        command.append(str(folder))
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise Refusal(f"generate_appcast failed:\n{result.stdout}{result.stderr}")

        verify = subprocess.run([str(sign), "--verify"] + key_arguments(ed_key_file) + [str(output)],
                                capture_output=True, text=True)
        if verify.returncode != 0:
            raise Refusal(f"The feed did not verify:\n{verify.stdout}{verify.stderr}")

        sys.path.insert(0, str(WEBSITE))
        import update_feeds
        newest = update_feeds.newest_item(output)
        if newest is None or newest["build"] != build:
            raise Refusal("The new release is not the newest item in the feed.")
        if newest["url"] != prefix + ASSET:
            raise Refusal(f"The new item downloads {newest['url']}, not {prefix + ASSET}.")
        if newest["length"] != str(dmg.stat().st_size):
            raise Refusal(f"The new item says {newest['length']} bytes; the DMG is {dmg.stat().st_size}.")

        updates_dir.mkdir(parents=True, exist_ok=True)
        if rehearsal is not None:
            rehearsal.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(output, rehearsal)
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
