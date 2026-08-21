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

# Per-section naming, matching the sites redeployed on 2026-08-20 — see the
# note beside the same table in capture.py. ENG2D moved to its section 2 site;
# MCV4U and SCH3U are still on section 1.
DEMO_COURSES = [
    {"code": "ENG2D", "site": "eng2d-s2-2026-gordon"},
    {"code": "MCV4U", "site": "mcv4u-s1-2026-gordon"},
    {"code": "SCH3U", "site": "sch3u-s1-2026-gordon"},
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
        REPO / "windows-app" / "Plantoir" / "bin" / "Release" / "net9.0-windows10.0.19041.0" / "win-x64" / "publish" / "Plantoir.exe",
        REPO / "windows-app" / "Plantoir" / "bin" / "Debug" / "net9.0-windows10.0.19041.0" / "win-x64" / "publish" / "Plantoir.exe",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate

    announce("Building Plantoir Windows application (Release)")
    subprocess.run([
        "powershell", "-ExecutionPolicy", "Bypass", "-File",
        str(REPO / "windows-app" / "publish.ps1")
    ], cwd=REPO, check=True)
    return candidates[0]


def capture_app_windows(plantoir_exe: Path) -> None:
    announce("Photographing Plantoir App Windows on Windows")
    # -PassThru + exit $p.ExitCode, not just -Wait: Start-Process alone does not
    # forward the child's exit code to powershell.exe's own, so a crash inside
    # Plantoir.exe (mid-capture, after some images were already saved) came back
    # as a clean check=True pass here every time -- discovered 2026-08-20 when
    # MarketingShotCapturer.RunAsync's own exit-0-on-catch bug hid a crash for two
    # runs in a row, and this would have hidden it a third time even after that
    # side was fixed. Errors are still on screen (Plantoir.exe's own stderr, and
    # %TEMP%\marketing_capture.log), just no longer swallowed by the exit code.
    subprocess.run([
        "powershell", "-Command",
        f"$p = Start-Process '{plantoir_exe}' -ArgumentList '--capture-marketing-shots', "
        f"'{IMAGE_DIR.resolve()}' -Wait -NoNewWindow -PassThru; exit $p.ExitCode"
    ], cwd=REPO, check=True)


def capture_browser_sites() -> None:
    announce("Photographing Class Websites in Microsoft Edge on Windows")
    PARTS.mkdir(parents=True, exist_ok=True)
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge", headless=True)

        for dark in (False, True):
            theme = "dark" if dark else "light"
            print(f"   --- Edge {theme} theme ---", flush=True)

            context = browser.new_context(
                color_scheme=theme,
                viewport={"width": 1280, "height": 860},
                device_scale_factor=2,
            )
            page = context.new_page()

            # 1. site-eng2d
            url = site_address("ENG2D") + "/"
            page.goto(url)
            page.wait_for_load_state("networkidle")
            time.sleep(1.0)
            eng2d_path = IMAGE_DIR / f"site-eng2d-windows-{theme}.png"
            page.screenshot(path=str(eng2d_path))
            prepare(eng2d_path, WIDEST_WINDOW_PIXELS)
            print(f"   ✓ saved {eng2d_path.name}")

            # Save part for static composite
            part_path = PARTS / f"home-eng2d-{theme}.png"
            page.screenshot(path=str(part_path))

            # 2. site-mcv4u
            url = site_address("MCV4U") + "/concepts/derivative-rules"
            page.goto(url)
            page.wait_for_load_state("networkidle")
            time.sleep(1.0)
            mcv4u_path = IMAGE_DIR / f"site-mcv4u-windows-{theme}.png"
            page.screenshot(path=str(mcv4u_path))
            prepare(mcv4u_path, WIDEST_WINDOW_PIXELS)
            print(f"   ✓ saved {mcv4u_path.name}")

            # Save part for static composite
            if not dark:
                page.goto(site_address("MCV4U") + "/")
                page.wait_for_load_state("networkidle")
                time.sleep(0.8)
                page.screenshot(path=str(PARTS / f"home-mcv4u-{theme}.png"))

            # 3. site-sch3u
            url = site_address("SCH3U") + "/style/what-this-site-can-do#diagrams"
            page.goto(url)
            page.wait_for_load_state("networkidle")
            time.sleep(1.0)
            sch3u_path = IMAGE_DIR / f"site-sch3u-windows-{theme}.png"
            page.screenshot(path=str(sch3u_path))
            prepare(sch3u_path, WIDEST_WINDOW_PIXELS)
            print(f"   ✓ saved {sch3u_path.name}")

            # Save part for static composite
            if not dark:
                page.goto(site_address("SCH3U") + "/")
                page.wait_for_load_state("networkidle")
                time.sleep(0.8)
                page.screenshot(path=str(PARTS / f"home-sch3u-{theme}.png"))

            # 4. coverage
            url = site_address("ENG2D") + "/curriculum-coverage"
            page.goto(url)
            page.wait_for_load_state("networkidle")
            time.sleep(1.0)
            cov_path = IMAGE_DIR / f"coverage-windows-{theme}.png"
            page.screenshot(path=str(cov_path))
            prepare(cov_path, WIDEST_WINDOW_PIXELS)
            print(f"   ✓ saved {cov_path.name}")

            # 5. search popover
            url = site_address("ENG2D") + "/"
            page.goto(url)
            page.wait_for_load_state("networkidle")
            time.sleep(0.8)
            page.keyboard.press("Control+k")
            time.sleep(0.4)
            page.keyboard.type("thesis")
            time.sleep(1.0)
            search_path = IMAGE_DIR / f"search-windows-{theme}.png"
            page.screenshot(path=str(search_path))
            prepare(search_path, WIDEST_WINDOW_PIXELS)
            print(f"   ✓ saved {search_path.name}")

            # 6. site-phone (Mobile Edge viewport)
            phone_context = browser.new_context(
                color_scheme=theme,
                viewport={"width": 390, "height": 844},
                is_mobile=True,
                has_touch=True,
                device_scale_factor=2,
            )
            phone_page = phone_context.new_page()
            phone_page.goto(site_address("ENG2D") + "/")
            phone_page.wait_for_load_state("networkidle")
            time.sleep(1.0)
            phone_path = IMAGE_DIR / f"site-phone-windows-{theme}.png"
            phone_page.screenshot(path=str(phone_path))
            prepare(phone_path, WIDEST_PHONE_PIXELS)
            print(f"   ✓ saved {phone_path.name}")
            phone_context.close()

            context.close()

        browser.close()


def build_windows_static_figures() -> None:
    announce("Assembling Windows Static Color Figures")
    fanned = [PARTS / f"home-{course['code'].lower()}-light.png" for course in DEMO_COURSES]
    if all(p.exists() for p in fanned):
        dest = IMAGE_DIR / "colour-schemes-windows.png"
        fan(fanned, dest)
        prepare(dest, WIDEST_WINDOW_PIXELS)
        print("   ✓ saved colour-schemes-windows.png + WebP")

    pair = [PARTS / "home-eng2d-light.png", PARTS / "home-eng2d-dark.png"]
    if all(p.exists() for p in pair):
        dest = IMAGE_DIR / "light-and-dark-windows.png"
        side_by_side(pair, dest)
        prepare(dest, WIDEST_WINDOW_PIXELS)
        print("   ✓ saved light-and-dark-windows.png + WebP")


def main() -> int:
    announce("Photographing Full Windows Suite (App + Edge Browser)")
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    plantoir_exe = find_or_build_plantoir_exe()

    # 1. Browser Sites in Edge (so preview screenshot can embed real site capture)
    capture_browser_sites()

    # 2. App Windows (uses C:\Users\russellgordon\Teaching and embeds site capture)
    capture_app_windows(plantoir_exe)

    # 3. Optimize App Windows
    shot_ids = ["courses", "new-course", "progress", "preview", "assistant"]
    for shot_id in shot_ids:
        for theme in ("light", "dark"):
            png_path = IMAGE_DIR / f"{shot_id}-windows-{theme}.png"
            if png_path.exists():
                prepare(png_path, WIDEST_WINDOW_PIXELS)

    # 4. Static Figures
    build_windows_static_figures()

    # 5. Rebuild site
    announce("Rebuilding plantoir.app")
    subprocess.run([sys.executable, str(WEBSITE / "build.py")], cwd=REPO, check=True)

    print("\n✅ Every screenshot now has an authentic Windows twin captured in Edge and Plantoir on Windows!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
