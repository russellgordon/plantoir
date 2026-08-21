#!/usr/bin/env python3
"""Photograph the three windows the hero composite is made of, on Windows.

The mac takes this picture with ``screencapture -l <window id>``, which hands
back one window with its rounded corners already transparent. Windows has no
equivalent, so every card here is a REGION of the screen: each window is put
at a known place, brought to the front, and the rectangle DWM reports as its
visible frame is grabbed. The corners are masked afterwards, because a screen
grab includes whatever was behind the window at each corner.

The three cards, left to right, are the same three the mac uses -- the notes,
the app publishing them, and the finished site -- with Edge standing in for
Safari:

1. Obsidian, showing a class note in the demo ENG2D vault.
2. Plantoir, staged mid-deploy (``Plantoir.exe --hero-window <theme>``).
3. Microsoft Edge, showing the published class site.

What it borrows and puts back: the Windows app colour mode, Obsidian's list of
vaults, and whatever was frontmost. Edge runs against a scratch profile of its
own, so Russell's tabs, history and sign-ins are never opened.
"""

from __future__ import annotations

import ctypes
import ctypes.wintypes as wintypes
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import winreg
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent.parent
IMAGE_DIR = REPO / "site" / "img"
SCRATCH = Path(os.environ.get("TEMP", "C:/temp")) / "plantoir-marketing-shots"
PARTS = SCRATCH / "parts-hero-windows"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from composite import diagonal_hero, FIGURE_WIDTH  # noqa: E402
from images import prepare, WIDEST_WINDOW_PIXELS  # noqa: E402

WORKSPACE = Path.home() / "Teaching"
VAULT = WORKSPACE / "courses" / "ENG2D"
# The card shows SECTION 1, because everything else in the picture does:
# Plantoir is deploying ENG2D-S1 and Edge is on the section 1 site.
SECTION = 1
# Which class note, though, is not ours to decide -- see most_recent_class().
FALLBACK_CLASS = "Unit 4, Day 22"
# Read from the one table both capture scripts share, so a renamed demo
# site never leaves this harness photographing a dead address.
from capture_windows import DEMO_COURSES  # noqa: E402

SITE_URL = f"https://{DEMO_COURSES[0]['site']}.netlify.app/"

OBSIDIAN_EXE = Path(r"C:\Program Files\Obsidian\Obsidian.exe")
OBSIDIAN_CONFIG = Path(os.environ["APPDATA"]) / "obsidian" / "obsidian.json"
EDGE_EXE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
EDGE_PROFILE = SCRATCH / "edge-profile"

THEME_KEY = r"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"

# Windows 11 rounds a top-level window by 8 device-independent pixels. The grab
# is in real pixels, so the mask has to follow the display's scale or the
# corners keep a crescent of desktop.
CORNER_DIPS = 8


def announce(message: str) -> None:
    print(f"\n> {message}", flush=True)


# ---- Win32 ---------------------------------------------------------------

user32 = ctypes.windll.user32
dwmapi = ctypes.windll.dwmapi

SWP_SHOWWINDOW = 0x0040
SW_RESTORE = 9
DWMWA_EXTENDED_FRAME_BOUNDS = 9
SPI_GETWORKAREA = 0x0030
HWND_BROADCAST = 0xFFFF
WM_SETTINGCHANGE = 0x001A


def make_dpi_aware() -> None:
    """Ask for real pixels. Without this every rectangle comes back scaled."""
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)  # per-monitor aware
    except Exception:
        user32.SetProcessDPIAware()


def scale_factor() -> float:
    hdc = user32.GetDC(0)
    try:
        dpi = ctypes.windll.gdi32.GetDeviceCaps(hdc, 88)  # LOGPIXELSX
    finally:
        user32.ReleaseDC(0, hdc)
    return dpi / 96.0


def work_area() -> tuple[int, int, int, int]:
    rect = wintypes.RECT()
    user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, ctypes.byref(rect), 0)
    return rect.left, rect.top, rect.right, rect.bottom


def windows_of_process(pid: int) -> list[int]:
    """Every visible top-level window belonging to one process id."""
    found: list[int] = []
    proc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.POINTER(ctypes.c_int))

    def callback(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            length = user32.GetWindowTextLengthW(hwnd)
            if length > 0:
                found.append(hwnd)
        return True

    user32.EnumWindows(proc(callback), None)
    return found


def window_titled(fragment: str) -> int | None:
    """The first visible top-level window whose title contains `fragment`."""
    match: list[int] = []
    proc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.POINTER(ctypes.c_int))

    def callback(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length == 0:
            return True
        buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buffer, length + 1)
        if fragment.lower() in buffer.value.lower():
            match.append(hwnd)
            return False
        return True

    user32.EnumWindows(proc(callback), None)
    return match[0] if match else None


def wait_for_window(finder, seconds: float = 30.0) -> int:
    deadline = time.time() + seconds
    while time.time() < deadline:
        hwnd = finder()
        if hwnd:
            return hwnd
        time.sleep(0.5)
    raise SystemExit("No window appeared to photograph.")


def place(hwnd: int, x: int, y: int, width: int, height: int) -> None:
    user32.ShowWindow(hwnd, SW_RESTORE)
    user32.SetWindowPos(hwnd, 0, x, y, width, height, SWP_SHOWWINDOW)
    time.sleep(0.4)
    # Foreground rights are only granted to the process that owns the current
    # foreground window, so a plain SetForegroundWindow is refused about half
    # the time. Attaching to that window's input queue first makes it stick.
    foreground = user32.GetForegroundWindow()
    ours = ctypes.windll.kernel32.GetCurrentThreadId()
    theirs = user32.GetWindowThreadProcessId(foreground, None)
    user32.AttachThreadInput(theirs, ours, True)
    user32.BringWindowToTop(hwnd)
    user32.SetForegroundWindow(hwnd)
    user32.AttachThreadInput(theirs, ours, False)
    time.sleep(0.6)



def press_escape() -> None:
    """Dismiss a popover in the frontmost window."""
    VK_ESCAPE, KEYEVENTF_KEYUP = 0x1B, 0x0002
    user32.keybd_event(VK_ESCAPE, 0, 0, 0)
    user32.keybd_event(VK_ESCAPE, 0, KEYEVENTF_KEYUP, 0)
    time.sleep(0.8)


def frame_bounds(hwnd: int) -> tuple[int, int, int, int]:
    """The VISIBLE frame. GetWindowRect includes an invisible resize border."""
    rect = wintypes.RECT()
    dwmapi.DwmGetWindowAttribute(
        wintypes.HWND(hwnd),
        wintypes.DWORD(DWMWA_EXTENDED_FRAME_BOUNDS),
        ctypes.byref(rect),
        ctypes.sizeof(rect),
    )
    return rect.left, rect.top, rect.right, rect.bottom


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (image.width - 1, image.height - 1)], radius=radius, fill=255
    )
    result = image.convert("RGBA")
    result.putalpha(mask)
    return result


def park_pointer() -> None:
    """Get the pointer out of the frame before the shutter.

    Whatever it rests on eventually says something -- Obsidian's file tree
    answers "91 files, 1 folder" about a second later -- and a tooltip that
    nobody asked for is the hardest kind of wrong image to notice, because the
    picture is otherwise perfect.
    """
    _, _, right, bottom = work_area()
    user32.SetCursorPos(right - 4, bottom - 4)
    time.sleep(1.4)


def photograph(hwnd: int, destination: Path) -> Path:
    from PIL import ImageGrab

    park_pointer()
    left, top, right, bottom = frame_bounds(hwnd)
    image = ImageGrab.grab(bbox=(left, top, right, bottom), all_screens=True)
    radius = max(1, round(CORNER_DIPS * scale_factor()))
    destination.parent.mkdir(parents=True, exist_ok=True)
    rounded(image, radius).save(destination, format="PNG")
    print(f"   part {destination.name} ({image.width}x{image.height})")
    return destination


# ---- What the machine has to be told, and told back ----------------------


def read_theme() -> tuple[int, int]:
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, THEME_KEY) as key:
        apps = winreg.QueryValueEx(key, "AppsUseLightTheme")[0]
        system = winreg.QueryValueEx(key, "SystemUsesLightTheme")[0]
    return apps, system


def write_theme(apps: int, system: int) -> None:
    """Edge and Obsidian's title bar follow the OS, so the OS has to move."""
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, THEME_KEY, 0, winreg.KEY_SET_VALUE) as key:
        winreg.SetValueEx(key, "AppsUseLightTheme", 0, winreg.REG_DWORD, apps)
        winreg.SetValueEx(key, "SystemUsesLightTheme", 0, winreg.REG_DWORD, system)
    user32.SendMessageTimeoutW(
        HWND_BROADCAST, WM_SETTINGCHANGE, 0,
        ctypes.c_wchar_p("ImmersiveColorSet"), 0x0002, 200, None,
    )
    time.sleep(1.0)


def vault_identifier(path: Path) -> str:
    return hashlib.md5(str(path).encode("utf-8")).hexdigest()[:16]


def register_vault() -> dict | None:
    """Add the demo course to Obsidian's vault list; hand back what was there."""
    if not OBSIDIAN_CONFIG.exists():
        return None
    original = json.loads(OBSIDIAN_CONFIG.read_text(encoding="utf-8"))
    updated = json.loads(json.dumps(original))
    vaults = updated.setdefault("vaults", {})
    for entry in vaults.values():
        entry["open"] = False
    vaults[vault_identifier(VAULT)] = {
        "path": str(VAULT),
        "ts": int(time.time() * 1000),
        "open": True,
    }
    OBSIDIAN_CONFIG.write_text(json.dumps(updated), encoding="utf-8")
    return original


def restore_vaults(original: dict | None) -> None:
    if original is None:
        return
    OBSIDIAN_CONFIG.write_text(json.dumps(original), encoding="utf-8")
    print("   Obsidian's vault list put back")


def dress_vault(dark: bool) -> None:
    """Obsidian's own theme, which its frameless window follows."""
    settings = VAULT / ".obsidian"
    settings.mkdir(parents=True, exist_ok=True)
    (settings / "appearance.json").write_text(
        json.dumps({"theme": "obsidian" if dark else "moonstone",
                    "accentColor": ""}, indent=2),
        encoding="utf-8",
    )
    (settings / "app.json").write_text(
        json.dumps({"promptDelete": False,
                    # Reading view, with the YAML block out of sight. Source
                    # mode photographs a wall of "---" and timestamps, and
                    # the properties panel fills half the card with dates
                    # and checkboxes. And Live Preview shows the SOURCE of
                    # whichever line holds the cursor, so the heading it
                    # happens to land on photographs as "## Agenda".
                    "livePreview": True,
                    "defaultViewMode": "preview",
                    "propertiesInDocument": "hidden",
                    "readableLineLength": True}),
        encoding="utf-8")
    (settings / "core-plugins.json").write_text(
        json.dumps({"file-explorer": True, "global-search": True, "editor-status": True}),
        encoding="utf-8",
    )


def stop(process_name: str) -> None:
    subprocess.run(["taskkill", "/F", "/IM", process_name],
                   capture_output=True, text=True)
    time.sleep(1.0)


# ---- The three cards -----------------------------------------------------


def card_geometry() -> tuple[int, int, int, int]:
    """A window as big as the desktop can actually show, at 16:9-ish."""
    left, top, right, bottom = work_area()
    width = min(1680, right - left - 40)
    height = min(960, bottom - top - 40)
    return left + 20, top + 20, width, height


def most_recent_class() -> str:
    """The class the published site is currently showing.

    The three cards only tell one story if the note open in Obsidian is the
    one Edge is displaying beside it, and the site's front page transcludes
    whichever class was published last. Hard-coding the name held for exactly
    as long as it took the demo sites to be redeployed: the note said Day 23
    while the site had moved to Day 22, and nothing in the harness could
    notice. So ask the page.
    """
    import re
    import urllib.request

    try:
        with urllib.request.urlopen(SITE_URL, timeout=20) as response:
            page = response.read().decode("utf-8", errors="replace")
        found = re.search(r"Unit \d+, Day \d+", page)
        if found:
            print(f"   the site's most recent class is {found.group(0)}")
            return found.group(0)
    except Exception as problem:
        print(f"   could not read the site ({problem}); using {FALLBACK_CLASS}")
    return FALLBACK_CLASS


def capture_obsidian(theme: str, x: int, y: int, w: int, h: int) -> Path:
    announce(f"Obsidian, {theme}")
    dress_vault(dark=(theme == "dark"))
    note = f"section{SECTION}/All Classes/{most_recent_class()}"
    address = ("obsidian://open?vault=" + urllib.parse.quote(VAULT.name)
               + "&file=" + urllib.parse.quote(note))
    subprocess.Popen([str(OBSIDIAN_EXE), address])
    hwnd = wait_for_window(lambda: window_titled("Obsidian"), seconds=45)
    time.sleep(3.5)
    place(hwnd, x, y, w, h)
    time.sleep(2.0)
    return photograph(hwnd, PARTS / f"obsidian-{theme}.png")


def capture_plantoir(exe: Path, theme: str, x: int, y: int, w: int, h: int) -> Path:
    announce(f"Plantoir, staged mid-deploy, {theme}")
    process = subprocess.Popen([str(exe), "--hero-window", theme])
    hwnd = wait_for_window(lambda: (windows_of_process(process.pid) or [None])[0], seconds=60)
    time.sleep(3.0)
    place(hwnd, x, y, w, h)
    time.sleep(1.5)
    destination = photograph(hwnd, PARTS / f"plantoir-{theme}.png")
    stop("Plantoir.exe")
    return destination


def capture_edge(theme: str, x: int, y: int, w: int, h: int) -> Path:
    announce(f"Edge on the published site, {theme}")
    # A fresh profile every time. Reusing it across the two themes let Edge
    # restore the previous pass's tab after being force-killed, so the dark
    # card came back with the same page open twice.
    shutil.rmtree(EDGE_PROFILE, ignore_errors=True)
    EDGE_PROFILE.mkdir(parents=True, exist_ok=True)
    subprocess.Popen([
        str(EDGE_EXE),
        f"--user-data-dir={EDGE_PROFILE}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-sync",
        "--disable-search-engine-choice-screen",
        # Edge signs a fresh profile in from the Windows account by itself and
        # then announces it -- "we've also signed you in", over the real email
        # address, straight across the middle of the card.
        "--disable-features=msImplicitSignin,msSyncPromo,msEdgeSplitScreen,"
        "msUndersideButton,msEdgeShoppingAssist",
        f"--window-position={x},{y}",
        f"--window-size={w},{h}",
        SITE_URL,
    ])
    hwnd = wait_for_window(lambda: window_titled("Grade 10 English"), seconds=60)
    time.sleep(4.0)
    place(hwnd, x, y, w, h)
    press_escape()   # belt and braces: any promo bubble that opened anyway
    time.sleep(2.5)
    destination = photograph(hwnd, PARTS / f"edge-{theme}.png")
    stop("msedge.exe")
    return destination


def build(exe: Path, themes=("light", "dark")) -> None:
    make_dpi_aware()
    PARTS.mkdir(parents=True, exist_ok=True)
    x, y, w, h = card_geometry()
    print(f"   cards are {w}x{h} real pixels at {scale_factor():.2f}x")

    was_apps, was_system = read_theme()
    vaults_before = register_vault()
    try:
        for theme in themes:
            write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)

            plantoir = capture_plantoir(exe, theme, x, y, w, h)
            obsidian = capture_obsidian(theme, x, y, w, h)
            stop("Obsidian.exe")
            edge = capture_edge(theme, x, y, w, h)

            destination = IMAGE_DIR / f"hero-windows-{theme}.png"
            diagonal_hero(obsidian, plantoir, edge, destination,
                          stagger_ratio=0.20, figure_width=FIGURE_WIDTH)
            print(f"   saved {destination.name} + WebP")
    finally:
        write_theme(was_apps, was_system)
        restore_vaults(vaults_before)
        stop("Obsidian.exe")
        stop("msedge.exe")
        stop("Plantoir.exe")
        shutil.rmtree(EDGE_PROFILE, ignore_errors=True)
        print("   colour mode, vault list and scratch profile put back")


def main() -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from capture_windows import find_or_build_plantoir_exe

    themes = ("light", "dark")
    if "--only" in sys.argv:
        themes = (sys.argv[sys.argv.index("--only") + 1],)
    build(find_or_build_plantoir_exe(), themes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
