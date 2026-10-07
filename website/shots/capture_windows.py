#!/usr/bin/env python3
"""Take EVERY Windows screenshot plantoir.app uses, autonomously.

Run it from the top of the repository on a Windows machine::

    python website/shots/capture_windows.py

What it does:
1. Locates or builds the Windows application executable (Plantoir.exe).
2. Captures all 5 app-window marketing shots (courses, new-course, progress,
   preview, assistant) in both Light and Dark mode.
3. Launches Microsoft Edge on Windows via Playwright to capture all 6 browser
   screenshots (site-eng2d, site-mcv4u, site-sch3u, coverage, search, site-phone)
   in both Light and Dark mode with native Windows ClearType typography.
4. Assembles the two static color composites (colour-schemes-windows,
   light-and-dark-windows) using the Edge captures.
5. Scales and optimizes all captured PNGs and generates WebP companions.
6. Rebuilds the marketing site (website/build.py).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

REPO = Path(__file__).resolve().parent.parent.parent
WEBSITE = REPO / "website"
IMAGE_DIR = REPO / "site" / "img"
SCRATCH = Path(os.environ.get("TEMP", "C:/temp")) / "plantoir-marketing-shots"
PARTS = SCRATCH / "parts-windows"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from images import prepare, WIDEST_PHONE_PIXELS, WIDEST_WINDOW_PIXELS  # noqa: E402
from composite import fan, side_by_side  # noqa: E402

# Per-section naming, matching the sites redeployed on 2026-08-19 — see the
# note beside the same table in capture.py.
# `title` is how a page window of the site is FOUND to be photographed: the
# start of the home page's own <title>, which is the window's title.
DEMO_COURSES = [
    {"code": "ENG2D", "site": "eng2d-s1-2026-gordon", "title": "Grade 10 English"},
    {"code": "MCV4U", "site": "mcv4u-s1-2026-gordon", "title": "Grade 12 Calculus and Vectors"},
    {"code": "SCH3U", "site": "sch3u-s1-2026-gordon", "title": "Grade 11 Chem"},
]


def announce(message: str) -> None:
    print(f"\n▶︎ {message}", flush=True)


def site_address(code: str) -> str:
    for course in DEMO_COURSES:
        if course["code"] == code:
            return f"https://{course['site']}.netlify.app"
    raise SystemExit(f"No demo site is configured for {code}.")


def find_or_build_plantoir_exe() -> Path:
    candidates = [
        REPO / "windows-app" / "Plantoir" / "bin" / "x64" / "Debug" / "net9.0-windows10.0.19041.0" / "win-x64" / "Plantoir.exe",
        REPO / "windows-app" / "Plantoir" / "bin" / "Release" / "net9.0-windows10.0.19041.0" / "win-x64" / "publish" / "Plantoir.exe",
        REPO / "windows-app" / "Plantoir" / "bin" / "Debug" / "net9.0-windows10.0.19041.0" / "win-x64" / "publish" / "Plantoir.exe",
    ]
    # The NEWEST build of this tree: the staging mode the app scenes need is
    # only in a build made since it was written, and an old publish folder
    # left beside a fresh Debug build would photograph the old app.
    built = [candidate for candidate in candidates if candidate.exists()]
    if built:
        return max(built, key=lambda candidate: candidate.stat().st_mtime)

    announce("Building Plantoir Windows application (Release)")
    subprocess.run([
        "powershell", "-ExecutionPolicy", "Bypass", "-File",
        str(REPO / "windows-app" / "publish.ps1")
    ], cwd=REPO, check=True)
    return candidates[0]


# The class-site shots, by `capture.kind` in shots.json. Each is a page of a
# demo site in an Edge `--app` window, photographed whole by windowshot (#380):
# the window's own corners, no browser toolbar, no shadow of its own (the
# page's stylesheet gives a single Windows window its drop-shadow).
SITE_KINDS = ("browser", "browser-search", "browser-phone")


def site_shots(only: list[str] | None = None) -> list[dict]:
    manifest = json.loads((WEBSITE / "shots.json").read_text(encoding="utf-8"))
    chosen = []
    for shot in manifest["shots"]:
        if shot.get("capture", {}).get("kind") not in SITE_KINDS:
            continue
        if only and shot["id"] not in only:
            continue
        chosen.append(shot)
    return chosen


def open_search(query: str):
    """The site's own search, opened the way a student opens it (Ctrl+K) and
    typed into; refused when no result appears, because a picture of an empty
    panel is the wrong state with nothing to say so."""
    def prepare_page(page) -> None:
        page.keyboard.press("Control+k")
        page.wait_for_selector("#search-container.active, .search-container.active", timeout=10000)
        page.keyboard.type(query, delay=60)
        page.wait_for_selector(".result-card", timeout=10000)
        time.sleep(1.0)
    return prepare_page


def capture_browser_sites(only: list[str] | None = None) -> None:
    """Every class-site shot, in Windows' light and then dark colour mode."""
    from hero_windows import (PHONE_HEIGHT_DIP, PHONE_WIDTH_DIP, capture_page, make_dpi_aware,
                              read_theme, write_theme)
    announce("Photographing the class websites in Edge windows")
    make_dpi_aware()
    PARTS.mkdir(parents=True, exist_ok=True)
    shots = site_shots(only)
    was_apps, was_system = read_theme()
    try:
        for theme in ("light", "dark"):
            write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
            for shot in shots:
                capture = shot["capture"]
                url = site_address(capture["course"]) + capture.get("path", "/")
                part = PARTS / f"{shot['id']}-windows-{theme}.png"
                announce(f"{shot['id']}, {theme}")
                if capture["kind"] == "browser-phone":
                    capture_page(url, "", part, size_dip=(PHONE_WIDTH_DIP, PHONE_HEIGHT_DIP))
                elif capture["kind"] == "browser-search":
                    capture_page(url, "", part, prepare_page=open_search(capture["query"]))
                else:
                    capture_page(url, "", part)
                destination = IMAGE_DIR / part.name
                shutil.copyfile(part, destination)
                widest = WIDEST_PHONE_PIXELS if capture["kind"] == "browser-phone" else WIDEST_WINDOW_PIXELS
                prepare(destination, widest)
                print(f"   saved {destination.name} + WebP")
    finally:
        write_theme(was_apps, was_system)
        print("   Windows colour mode put back")


def build_windows_static_figures() -> None:
    """The fanned colour schemes and the light/dark pair, from whole captures.

    The parts are real windows photographed with their own corners
    (`hero_windows.capture_colour_parts`), never page screenshots: a page
    screenshot has no window, so the figure came out square (#380). A figure
    whose parts are missing is NOT written -- an old one left in place would
    be a picture of something else.
    """
    announce("Assembling Windows Static Color Figures")
    from hero_windows import capture_colour_parts
    PARTS.mkdir(parents=True, exist_ok=True)
    capture_colour_parts(PARTS, DEMO_COURSES)

    fanned = [PARTS / f"home-{course['code'].lower()}-light.png" for course in DEMO_COURSES]
    fan(fanned, IMAGE_DIR / "colour-schemes-windows.png")
    print("   ✓ saved colour-schemes-windows.png + WebP")
    # The same fan taken in Dark Mode, for a page in dark mode (Russell
    # 2026-10-04, "It needs a dark mode version"; the mac's is
    # colour-schemes-dark.png). The light one keeps its name.
    fanned_dark = [PARTS / f"home-{course['code'].lower()}-dark.png" for course in DEMO_COURSES]
    fan(fanned_dark, IMAGE_DIR / "colour-schemes-windows-dark.png")
    print("   ✓ saved colour-schemes-windows-dark.png + WebP")

    pair = [PARTS / "home-eng2d-light.png", PARTS / "home-eng2d-dark.png"]
    side_by_side(pair, IMAGE_DIR / "light-and-dark-windows.png")
    print("   ✓ saved light-and-dark-windows.png + WebP")


def windows_shot_ids() -> list:
    manifest = json.loads((WEBSITE / "shots.json").read_text(encoding="utf-8"))
    ids = []
    for shot in manifest["shots"]:
        if shot.get("windows"):
            ids.append(shot["id"])
    return ids


def main() -> int:
    """Every Windows picture, or one pass of them:

        --sites [id,id]    the class-site shots, in Edge windows
        --figures          the hero and the two colour figures
        --app [scene,...]  the app's own windows, each scene staged by
                           Plantoir.exe --stage-scene and photographed whole
                           (app_scenes_windows.py)

    Each pass takes the desktop: it switches Windows between light and dark
    and puts the colour mode back afterwards.
    """
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    arguments = sys.argv[1:]

    def listed_after(flag: str) -> list[str] | None:
        index = arguments.index(flag)
        if index + 1 < len(arguments) and not arguments[index + 1].startswith("--"):
            return arguments[index + 1].split(",")
        return None

    everything = not any(flag in arguments for flag in ("--sites", "--figures", "--app"))
    if everything or "--sites" in arguments:
        capture_browser_sites(listed_after("--sites") if "--sites" in arguments else None)
    if everything or "--figures" in arguments:
        # The hero is part of a full run (#428 item 6: it used to be taken
        # only by --figures, so a full run left the oldest picture in place).
        from hero_windows import build as build_hero
        announce("Photographing the hero, in light and dark")
        build_hero(find_or_build_plantoir_exe())
        build_windows_static_figures()
    if everything or "--app" in arguments:
        from app_scenes_windows import capture_app_scenes
        capture_app_scenes(find_or_build_plantoir_exe(),
                           listed_after("--app") if "--app" in arguments else None)

    announce("Rebuilding plantoir.app")
    subprocess.run([sys.executable, str(WEBSITE / "build.py")], cwd=REPO, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
