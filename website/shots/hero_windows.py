#!/usr/bin/env python3
"""Photograph the three windows the hero composite is made of, on Windows.

The mac takes this picture with ``screencapture -l <window id>``, which hands
back one window with its rounded corners already transparent. Windows' answer
is Windows.Graphics.Capture, asked for ONE window by its handle: the frame it
returns carries the window's own alpha, so the corners Windows 11 rounds are
already transparent. ``windowshot`` (beside this file) is that capture, and
every card here is one whole picture from it -- nothing cropped, nothing
masked, no corner drawn (website/SCREENSHOTS.md, "The one rule"; #380).

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

# A window sized in real pixels doesn't scale with the display: the original
# 1680x960 cap was tuned on a 1920x1080-at-150% machine (a work area of
# 1920x1008 real pixels, 1280x672 DIPs), where it read as "almost the whole
# screen". The same real-pixel number on a 200%-scaled screen is only
# 840x480 DIPs -- a physically small window whose UI barely shows anything.
# Expressed in DIPs instead (the size that cap actually was, in points) and
# multiplied by the display's own scale, a card occupies the same fraction
# of the desktop everywhere.
CARD_WIDTH_DIP = 1120
CARD_HEIGHT_DIP = 640


def announce(message: str) -> None:
    print(f"\n> {message}", flush=True)


# ---- Win32 ---------------------------------------------------------------

user32 = ctypes.windll.user32
dwmapi = ctypes.windll.dwmapi

SWP_SHOWWINDOW = 0x0040
SW_RESTORE = 9
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


def window_title(hwnd: int) -> str:
    length = user32.GetWindowTextLengthW(hwnd)
    buffer = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buffer, length + 1)
    return buffer.value


def window_titled(fragment: str, pid: int | None = None) -> int | None:
    """The ONE visible top-level window whose title contains `fragment`.

    With `pid`, only that process's windows are asked: the window a capture
    launched is the one it photographs, never another window that happens to
    show the same page (#428 item 6). Without it, a SECOND window with the
    same title is a refusal rather than a coin toss — the first version
    returned whichever one EnumWindows met first.
    """
    match: list[int] = []
    proc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.POINTER(ctypes.c_int))

    def callback(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        if user32.GetWindowTextLengthW(hwnd) == 0:
            return True
        if pid is not None:
            owner = wintypes.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
            if owner.value != pid:
                return True
        if fragment.lower() in window_title(hwnd).lower():
            match.append(hwnd)
        return True

    user32.EnumWindows(proc(callback), None)
    if len(match) > 1:
        raise SystemExit(f"{len(match)} windows are titled like {fragment!r}; close the others so the "
                         "capture cannot photograph the wrong one.")
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


def press_chord(*virtual_keys: int) -> None:
    """Press several keys together, e.g. press_chord(VK_CONTROL, ord('P'))."""
    KEYEVENTF_KEYUP = 0x0002
    for vk in virtual_keys:
        user32.keybd_event(vk, 0, 0, 0)
    for vk in reversed(virtual_keys):
        user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)


def type_text(text: str) -> None:
    KEYEVENTF_KEYUP = 0x0002
    VK_SHIFT = 0x10
    for character in text:
        scanned = user32.VkKeyScanW(ord(character))
        vk = scanned & 0xFF
        # The high byte says which modifiers the character needs: without
        # Shift, "How I Teach" arrived as "how i teach".
        shifted = bool((scanned >> 8) & 1)
        if shifted:
            user32.keybd_event(VK_SHIFT, 0, 0, 0)
        user32.keybd_event(vk, 0, 0, 0)
        user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)
        if shifted:
            user32.keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0)
        time.sleep(0.02)


def reveal_active_file() -> None:
    """Obsidian's own "Reveal current file in navigation" command.

    Opening a note does not reliably scroll and expand the sidebar to show
    it -- what actually happens depends on the "Reveal active file" setting,
    which a fresh vault has never had a reason to turn on, and even turned
    on it can settle mid-scroll rather than on the note itself. The command
    does both deterministically, regardless of that setting, which is what
    makes the sidebar worth photographing instead of three collapsed
    top-level folders.
    """
    VK_CONTROL = 0x11
    VK_RETURN = 0x0D
    press_chord(VK_CONTROL, ord('P'))
    time.sleep(0.6)
    type_text("Reveal current file")
    time.sleep(0.8)
    press_chord(VK_RETURN)
    time.sleep(1.2)


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


WINDOWSHOT = Path(__file__).resolve().parent / "windowshot"
WINDOWSHOT_EXE = (WINDOWSHOT / "bin" / "x64" / "Release" / "net9.0-windows10.0.22621.0"
                  / "win-x64" / "windowshot.exe")


def windowshot_exe() -> Path:
    """The window-capture tool, built when it is missing or older than its source."""
    sources = [WINDOWSHOT / "Program.cs", WINDOWSHOT / "windowshot.csproj"]
    newest = max(source.stat().st_mtime for source in sources)
    if not WINDOWSHOT_EXE.exists() or WINDOWSHOT_EXE.stat().st_mtime < newest:
        print("   building windowshot")
        built = subprocess.run(["dotnet", "build", "-c", "Release", "-p:Platform=x64", str(WINDOWSHOT)],
                               capture_output=True, text=True)
        if built.returncode != 0 or not WINDOWSHOT_EXE.exists():
            raise SystemExit("windowshot did not build:\n" + built.stdout[-2000:])
    return WINDOWSHOT_EXE


def photograph(hwnd: int, destination: Path) -> Path:
    """One window, whole, with the corners and the alpha Windows gave it.

    Measured 2026-10-03 on a Plantoir window at 2x: the corner pixels come
    back at alpha 7 to 40 and rise to 255 along an antialiased curve, and the
    1 DIP accent border Windows 11 draws round a window is in the picture at
    about alpha 113 -- part of the window, so it is kept. The display scale
    the window was drawn at is written beside the picture (`<name>.json`),
    because a corner is 8 DIPs and only the scale says how many pixels that was.
    """
    park_pointer()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        destination.unlink()
    taken = subprocess.run([str(windowshot_exe()), str(hwnd), str(destination)],
                           capture_output=True, text=True)
    if taken.returncode != 0 or not destination.exists():
        raise SystemExit(f"Could not photograph the window for {destination.name}: {taken.stderr.strip()}")
    facts = json.loads(taken.stdout)
    destination.with_suffix(".json").write_text(json.dumps(facts), encoding="utf-8")
    print(f"   part {destination.name} ({facts['width']}x{facts['height']} at {facts['scale']}x)")
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


def stop_matching(process_name: str, command_line_contains: str) -> None:
    """Kill only the processes whose command line names our own scratch data.

    `stop("msedge.exe")` kills every Edge process on the machine, scratch
    profile or not -- on a machine where Edge is also someone's actual
    browser, that closes whatever they had open with no warning. Edge forks
    many helper processes per window, all named msedge.exe, so it is not
    enough to find "the" pid either: every one of them is asked, and only
    the ones launched against our own `--user-data-dir` answer.
    """
    query = (
        "Get-CimInstance Win32_Process -Filter \"Name='" + process_name + "'\" "
        "| Where-Object { $_.CommandLine -and $_.CommandLine.Contains('" + command_line_contains + "') } "
        "| ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", query],
                   capture_output=True, text=True)
    time.sleep(1.0)


# ---- The three cards -----------------------------------------------------


def card_geometry() -> tuple[int, int, int, int]:
    """A window as big as the desktop can actually show, at 16:9-ish."""
    left, top, right, bottom = work_area()
    scale = scale_factor()
    width = min(round(CARD_WIDTH_DIP * scale), right - left - 40)
    height = min(round(CARD_HEIGHT_DIP * scale), bottom - top - 40)
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
    # Any Obsidian already open would take the address and show it in ITS
    # window; the one photographed must be the one launched here (#428 item 6).
    stop("Obsidian.exe")
    process = subprocess.Popen([str(OBSIDIAN_EXE), address])
    hwnd = wait_for_window(lambda: window_titled("Obsidian", pid=process.pid), seconds=45)
    time.sleep(3.5)
    place(hwnd, x, y, w, h)
    time.sleep(1.5)
    # Without this the sidebar is three collapsed top-level folders --
    # correct, but not a picture of anything. Reveal walks the active file's
    # ancestors open and scrolls to it, showing real class notes instead.
    reveal_active_file()
    return photograph(hwnd, PARTS / f"obsidian-{theme}.png")


def capture_plantoir(exe: Path, theme: str, x: int, y: int, w: int, h: int) -> Path:
    """Plantoir's window, staged mid-deploy by the app's own "hero" scene
    (MarketingShotCapturer.cs) on the demo folder, at the card's size."""
    from app_scenes_windows import end_everything_naming, stage
    announce(f"Plantoir, staged mid-deploy, {theme}")
    pid, outcome, state = stage(exe, "hero", theme, WORKSPACE)
    try:
        if outcome != "staged":
            raise SystemExit(f"The hero's Plantoir window was not staged: {outcome}")
        hwnd = (windows_of_process(pid) or [None])[0]
        if hwnd is None:
            raise SystemExit("The hero's Plantoir window did not appear.")
        place(hwnd, x, y, w, h)
        time.sleep(1.5)
        return photograph(hwnd, PARTS / f"plantoir-{theme}.png")
    finally:
        end_everything_naming(WORKSPACE, pid)
        shutil.rmtree(state, ignore_errors=True)


# Edge, as this side's stand-in for Safari and for the mac's page window. A
# scratch profile of its own every time (reusing it let Edge restore the
# previous pass's tab after being force-killed, so the dark card came back
# with the same page open twice), and these switches, because Edge signs a
# fresh profile in from the Windows account by itself and then announces it --
# "we've also signed you in", over the real email address, straight across the
# middle of the card.
EDGE_FLAGS = [
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-sync",
    "--disable-search-engine-choice-screen",
    "--disable-features=msImplicitSignin,msSyncPromo,msEdgeSplitScreen,"
    "msUndersideButton,msEdgeShoppingAssist",
]
# The page is driven over the DevTools protocol (Playwright's connect_over_cdp)
# in the very window that is photographed: scrolled to an anchor, the search
# opened, and -- the part a timer cannot do -- CHECKED before the shutter.
CDP_PORT = 9339


def launch_edge(target: list[str], x: int, y: int, w: int, h: int) -> subprocess.Popen:
    shutil.rmtree(EDGE_PROFILE, ignore_errors=True)
    EDGE_PROFILE.mkdir(parents=True, exist_ok=True)
    return subprocess.Popen([
        str(EDGE_EXE),
        f"--user-data-dir={EDGE_PROFILE}",
        f"--remote-debugging-port={CDP_PORT}",
        *EDGE_FLAGS,
        f"--window-position={x},{y}",
        f"--window-size={w},{h}",
        *target,
    ])


def edge_window(process: subprocess.Popen, title_fragment: str, seconds: float = 60) -> int:
    """The window of the Edge THIS capture launched, never another one showing
    the same page (#428 item 6): asked by the launched process's id. Edge on a
    profile no other Edge has open keeps its windows in that process."""
    return wait_for_window(lambda: window_titled(title_fragment, pid=process.pid), seconds=seconds)


def capture_edge(theme: str, x: int, y: int, w: int, h: int) -> Path:
    announce(f"Edge on the published site, {theme}")
    process = launch_edge([SITE_URL], x, y, w, h)
    try:
        hwnd = edge_window(process, "Grade 10 English")
        time.sleep(4.0)
        place(hwnd, x, y, w, h)
        press_escape()   # belt and braces: any promo bubble that opened anyway
        time.sleep(2.5)
        return photograph(hwnd, PARTS / f"edge-{theme}.png")
    finally:
        stop_matching("msedge.exe", str(EDGE_PROFILE))


PAGE_WIDTH_DIP = 1280
PAGE_HEIGHT_DIP = 860
PHONE_WIDTH_DIP = 390
PHONE_HEIGHT_DIP = 844

# What "the page has stopped moving" is measured by: the document's height,
# the scroll position, where the anchor's heading sits, and how many drawings
# there are. Mathematics and diagrams are drawn by scripts after the load and
# reflow the page, so an anchor scrolled to before they finish lands on the
# wrong section -- which is what the mac's v1.4.3 site-sch3u pictures shipped
# showing.
LAYOUT_SIGNATURE = """(fragment) => {
  const target = fragment ? document.getElementById(fragment) : null;
  const box = target ? target.getBoundingClientRect() : null;
  return JSON.stringify([document.documentElement.scrollHeight, window.scrollY,
                         box ? Math.round(box.top) : null, document.querySelectorAll('svg').length]);
}"""


def wait_until_still(page, fragment: str | None = None, timeout: float = 20.0) -> bool:
    """Three identical layout signatures 0.5 s apart; True when it settled."""
    deadline = time.time() + timeout
    seen: list[str] = []
    while time.time() < deadline:
        seen.append(page.evaluate(LAYOUT_SIGNATURE, fragment))
        if len(seen) >= 3 and seen[-1] == seen[-2] == seen[-3]:
            return True
        time.sleep(0.5)
    return False


def anchor_problem(page, fragment: str) -> str | None:
    """None when the heading `fragment` names is at the top of the page column:
    in the upper 30% of the viewport and in its left 60% (the page's own table
    of contents, on the right, carries the same words) -- the mac's rule
    (`safari.anchor_heading_in_view`), read from the page rather than by OCR."""
    found = page.evaluate("""(fragment) => {
      const target = document.getElementById(fragment);
      if (!target) return null;
      const box = target.getBoundingClientRect();
      return [box.left, box.top, window.innerWidth, window.innerHeight, target.textContent.trim()];
    }""", fragment)
    if found is None:
        return f"the page has no heading #{fragment}"
    left, top, width, height, text = found
    if -2 <= top < height * 0.30 and left < width * 0.6:
        return None
    return f"the heading #{fragment} ({text!r}) is at {top:.0f} of {height} px, not near the top of the page"


def land_on_anchor(page, fragment: str) -> None:
    """Scroll the finished page to `fragment`'s heading, and refuse a picture
    whose heading is not where the caption says it is."""
    for _ in range(3):
        # To the heading, then a little back, so it does not sit flush against
        # the title bar (the mac's lands under Safari's toolbar the same way).
        page.evaluate("(f) => { document.getElementById(f)?.scrollIntoView({block: 'start'});"
                      " window.scrollBy(0, -24); }", fragment)
        wait_until_still(page, fragment, timeout=10.0)
        if anchor_problem(page, fragment) is None:
            return
    raise SystemExit(f"#{fragment}: {anchor_problem(page, fragment)}. Nothing past this point was taken.")


def capture_page(url: str, title_fragment: str, destination: Path, *,
                 size_dip: tuple[int, int] = (PAGE_WIDTH_DIP, PAGE_HEIGHT_DIP), prepare_page=None) -> Path:
    """One page of a class site in a window with no browser round it.

    Edge's `--app=` window is this side's counterpart of the mac's page window
    (`webwindow.swift`): a title bar and the page, nothing else, and its own
    edge is the picture's edge. The window photographed is the one THIS call
    launched (`edge_window`). An address with a fragment is loaded without it,
    left to finish drawing, then scrolled and checked (`land_on_anchor`).
    `prepare_page(page)` does anything else the picture needs (the search).
    The appearance is the machine's, so the caller switches Windows first.
    """
    from playwright.sync_api import sync_playwright

    left, top, right, bottom = work_area()
    scale = scale_factor()
    width = min(round(size_dip[0] * scale), right - left - 40)
    height = min(round(size_dip[1] * scale), bottom - top - 40)
    x, y = left + 20, top + 20
    page_address, _, fragment = url.partition("#")
    process = launch_edge([f"--app={page_address}"], x, y, width, height)
    try:
        hwnd = edge_window(process, "")
        place(hwnd, x, y, width, height)
        press_escape()
        with sync_playwright() as playwright:
            browser = playwright.chromium.connect_over_cdp(f"http://127.0.0.1:{CDP_PORT}")
            page = browser.contexts[0].pages[0]
            page.wait_for_load_state("networkidle")
            # The page must be in the colour mode Windows is in. Edge's `--app`
            # window on a fresh profile drew its title bar dark and the page
            # LIGHT while Windows was dark (measured 2026-10-04: every dark
            # site picture of the first run; `--force-dark-mode` changed
            # nothing). So the machine's scheme is handed to the page and the
            # page loaded again -- from the top, with the browser's scroll
            # restoration off: a plain reload kept the scroll it had and the
            # site's own opening scroll (the sidebar bringing the current page
            # into view, 300 px on derivative-rules) ran again on top of it, so
            # site-mcv4u came out 300 px further down in one scheme than the
            # other. Rejected too: opening on about:blank and navigating, which
            # turned the app window into an ordinary browser window, tabs and
            # address bar included. Then the site's own theme is CHECKED.
            dark = read_theme()[0] == 0
            page.emulate_media(color_scheme="dark" if dark else "light")
            page.evaluate("history.scrollRestoration = 'manual'; window.scrollTo(0, 0)")
            page.reload()
            page.wait_for_load_state("networkidle")
            drawn = page.evaluate("document.documentElement.getAttribute('saved-theme')")
            if drawn != ("dark" if dark else "light"):
                raise SystemExit(f"{url}: the page drew itself {drawn!r} while Windows is "
                                 f"{'dark' if dark else 'light'}")
            page.evaluate("document.fonts.ready.then(() => true)")
            if title_fragment and title_fragment.lower() not in window_title(hwnd).lower():
                raise SystemExit(f"{url}: the window says {window_title(hwnd)!r}, not {title_fragment!r}")
            if not wait_until_still(page, fragment or None):
                raise SystemExit(f"{url}: the page never stopped moving")
            if fragment:
                land_on_anchor(page, fragment)
            if prepare_page is not None:
                prepare_page(page)
                wait_until_still(page, fragment or None, timeout=10.0)
            else:
                # Nothing the picture is about has focus; a focused search box
                # photographs with a heavy outline round it.
                page.evaluate("document.activeElement && document.activeElement.blur()")
            time.sleep(1.0)
            place(hwnd, x, y, width, height)   # in front, so its title bar is the active one
            if fragment and anchor_problem(page, fragment) is not None:
                raise SystemExit(f"{url}: {anchor_problem(page, fragment)} (it moved before the shutter)")
            return photograph(hwnd, destination)
    finally:
        stop_matching("msedge.exe", str(EDGE_PROFILE))


def capture_colour_parts(parts: Path, courses: list[dict]) -> None:
    """The home pages the two colour figures are made of: every course in
    light AND dark -- the fan has a Dark Mode version too (shots.json
    `dark: true`, Russell 2026-10-04) -- and the light/dark pair is the first
    course's two."""
    make_dpi_aware()
    was_apps, was_system = read_theme()
    try:
        for theme in ("light", "dark"):
            write_theme(0 if theme == "dark" else 1, 0 if theme == "dark" else 1)
            for course in courses:
                announce(f"{course['code']} home page, {theme}")
                capture_page(f"https://{course['site']}.netlify.app/", course["title"],
                             parts / f"home-{course['code'].lower()}-{theme}.png")
    finally:
        write_theme(was_apps, was_system)
        shutil.rmtree(EDGE_PROFILE, ignore_errors=True)
        print("   colour mode and scratch profile put back")


def build(exe: Path, themes=("light", "dark")) -> None:
    make_dpi_aware()
    # The demo folder the hero shows, made by the app when it is not whole.
    from app_scenes_windows import DEMO, ensure_folders
    ensure_folders(exe, {DEMO})
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
        stop_matching("msedge.exe", str(EDGE_PROFILE))
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
