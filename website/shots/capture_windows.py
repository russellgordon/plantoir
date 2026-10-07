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

``--provision-demo <folder>`` instead gives a demo working folder the state
``marketing/folders.json`` describes, through ``plantoir-mcp.exe``
(``demo_folders.py``, shared with the Mac). Every run first checks that spec
against the ready-made courses (``test_demo_folders.py``).
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

# The demo courses and their sites: marketing/folders.json → demo.courses, the
# one place both demo folders are described (#445), read by capture.py and the
# mac's UI tests too. Per-section naming, matching the sites redeployed on
# 2026-08-19. `title` is how a page window of the site is FOUND to be
# photographed: the start of the home page's own <title>, which is the
# window's title (folders.json's `siteTitle`).
import demo_folders  # noqa: E402


def _demo_courses() -> list:
    courses = []
    for course in demo_folders.demo_courses():
        courses.append({"code": course["code"], "site": course["site"], "title": course["siteTitle"],
                        "sections": course["sections"], "colourScheme": course["colourScheme"]})
    return courses


DEMO_COURSES = _demo_courses()


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
    """One run per appearance, with Windows switched into it first.

    Not one run photographing both: a WinUI brush read from
    Application.Current.Resources resolves against the theme the app LAUNCHED
    in, whatever RequestedTheme the window's content carries. Photographing
    dark from a light-launched process produced a white dialog card with white
    text on it, and assistant bubbles in light grey on a dark window.
    """
    announce("Photographing Plantoir App Windows on Windows")
    from hero_windows import read_theme, write_theme

    was_apps, was_system = read_theme()
    try:
        for theme in ("light", "dark"):
            print(f"   --- Plantoir {theme} appearance ---", flush=True)
            write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
            # -PassThru + exit $p.ExitCode, not just -Wait: Start-Process alone
            # does not forward the child's exit code to powershell.exe's own,
            # so a crash inside Plantoir.exe (mid-capture, after some images
            # were already saved) came back as a clean check=True pass here
            # every time -- discovered 2026-08-20 when
            # MarketingShotCapturer.RunAsync's own exit-0-on-catch bug hid a
            # crash for two runs in a row, and this would have hidden it a
            # third time even after that side was fixed. Errors are still on
            # screen (Plantoir.exe's own stderr, and
            # %TEMP%\marketing_capture.log), just no longer swallowed by the
            # exit code.
            subprocess.run([
                "powershell", "-Command",
                f"$p = Start-Process '{plantoir_exe}' -ArgumentList "
                f"'--capture-marketing-shots', '{IMAGE_DIR.resolve()}', "
                f"'--theme', '{theme}' -Wait -NoNewWindow -PassThru; exit $p.ExitCode"
            ], cwd=REPO, check=True)
    finally:
        write_theme(was_apps, was_system)
        print("   Windows colour mode put back")


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

            # 2. site-mcv4u
            url = site_address("MCV4U") + "/concepts/derivative-rules"
            page.goto(url)
            page.wait_for_load_state("networkidle")
            time.sleep(1.0)
            mcv4u_path = IMAGE_DIR / f"site-mcv4u-windows-{theme}.png"
            page.screenshot(path=str(mcv4u_path))
            prepare(mcv4u_path, WIDEST_WINDOW_PIXELS)
            print(f"   ✓ saved {mcv4u_path.name}")

            # 3. site-sch3u
            url = site_address("SCH3U") + "/style/what-this-site-can-do#diagrams"
            page.goto(url)
            page.wait_for_load_state("networkidle")
            time.sleep(1.0)
            sch3u_path = IMAGE_DIR / f"site-sch3u-windows-{theme}.png"
            page.screenshot(path=str(sch3u_path))
            prepare(sch3u_path, WIDEST_WINDOW_PIXELS)
            print(f"   ✓ saved {sch3u_path.name}")

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


def check_the_folders_spec() -> None:
    """Run the shared check that a clone can make both demo folders
    (test_demo_folders.py). No `dotnet test` runs website/shots tests, so on
    Windows this is where it is gated; a red run stops the capture."""
    announce("Checking marketing/folders.json against the ready-made courses")
    subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "test_demo_folders.py")],
                   cwd=REPO, check=True)


def provision_demo(folder: Path, plantoir_exe: Path) -> int:
    """Give a demo folder folders.json's state, through plantoir-mcp.exe.

    The courses themselves are made by the app's own new-course panel first
    (ENG2D sections 1 and 2, MCV4U 1, SCH3U 1 — folders.json → demo.courses),
    exactly as on the Mac; this step then sets each section's colour scheme,
    the teacher's last name and the sites' stand-in markers, and asks the
    app's own door to put every front page on the latest class dated on or
    before January 15 with every class after it unpublished. The same
    demo_folders.py the Mac runs; only the door differs.
    """
    import marketing_folder
    mcp_exe = plantoir_exe.parent / "plantoir-mcp.exe"
    if not mcp_exe.exists():
        print(f"   plantoir-mcp.exe is not beside {plantoir_exe}; publish.ps1 puts it there.", file=sys.stderr)
        return 1
    report = marketing_folder.Report()
    left = demo_folders.apply_demo_state(folder, demo_folders.windows_server(mcp_exe, folder), report)
    print(f"   {marketing_folder.summary(report)}")
    for line in left:
        print(f"   still to do: {line}", file=sys.stderr)
    return 1 if left else 0


def main() -> int:
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    check_the_folders_spec()
    plantoir_exe = find_or_build_plantoir_exe()

    # Give a demo folder folders.json's state: `--provision-demo <folder>`.
    if "--provision-demo" in sys.argv:
        index = sys.argv.index("--provision-demo")
        if index + 1 >= len(sys.argv):
            print("--provision-demo needs the demo working folder after it.", file=sys.stderr)
            return 2
        return provision_demo(Path(sys.argv[index + 1]).expanduser(), plantoir_exe)

    # Only the three figures made of whole window captures (#380): the hero
    # and the two colour figures. Takes the desktop for a few minutes.
    if "--figures" in sys.argv:
        from hero_windows import build as build_hero
        announce("Photographing the hero, in light and dark")
        build_hero(plantoir_exe)
        build_windows_static_figures()
        return 0

    announce("Photographing Full Windows Suite (App + Edge Browser)")

    # 1. Browser Sites in Edge (so preview screenshot can embed real site capture)
    capture_browser_sites()

    # 2. App Windows (uses C:\Users\russellgordon\Teaching and embeds site capture)
    capture_app_windows(plantoir_exe)

    # 3. Optimize App Windows
    # The ids Windows takes are marked `windows: true` in shots.json, the one
    # list both harnesses read — this used to be a list of its own here.
    shot_ids = windows_shot_ids()
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
