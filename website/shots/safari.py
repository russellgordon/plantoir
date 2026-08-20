#!/usr/bin/env python3
"""Capture a web page as a real Safari window.

Everything a visitor sees of a class site -- the type rendering, the
scrollbars, the window chrome -- comes from macOS, so the screenshots are
taken from a real browser on a real screen rather than from a headless
renderer that only approximates it.

The window this opens is a NEW one, addressed by its own id, and it is closed
again at the end. Whatever Safari windows were already open are not touched,
and the application that was in front beforehand is put back in front.
"""

from __future__ import annotations

import subprocess
import time
from pathlib import Path

from PIL import Image

def osascript(script: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def frontmost_application() -> str:
    return osascript(
        'tell application "System Events" to get name of first process whose frontmost is true'
    )


# Where a page stops reading as light and starts reading as dark, measured
# rather than picked: across the sixteen class-site shots on the site today,
# every light page's band medians 248-249 and every dark one 17-21. The
# midpoint is nowhere near either cluster, so the split is decisive rather
# than a judgement call — 107 below the nearest dark page, 120 above the
# nearest light one.
DARK_BELOW = 128


# The Safari profile the captures are taken in, when it exists.
#
# A profile has its OWN storage, history and cookies, and ordinary window
# chrome — which is exactly what Windows gets from `--user-data-dir`, and what
# a private window can never give, since Safari marks a private window with a
# dark address bar on purpose. A profile therefore starts with no theme saved
# for any class site, and nothing done in ordinary browsing can reach it.
#
# It is made by hand, once per Mac: Safari > Settings > Profiles > Start Using
# Profiles (or +), named exactly this. Safari offers no way to create one
# programmatically, which is fine for something done once.
#
# **The NAME is deliberately a single symbol, and that is not decoration.**
# Safari puts the profile's name in the window's own toolbar, so a profile
# called "Screenshots" would stamp that word across the top of every class
# site on plantoir.app — a caption about our photography, in a picture meant
# to be about a teacher's website. U+239A CLEAR SCREEN SYMBOL is one glyph
# wide and says nothing. If you rename the profile, rename it here, and keep
# it short for the same reason.
#
# When it is absent the run still works — an ordinary window, with
# `verify_appearance` catching the fault the profile would have prevented.
CAPTURE_PROFILE = "\u239a"  # ⎚


def open_profile_window(profile: str) -> bool:
    """Open a new Safari window in `profile`, if that profile exists.

    Safari has had profiles since 17, and its File menu grows a route to them
    the moment one exists — but the SHAPE of that route differs by version:
    some builds add a flat "New <profile> Window" item, others turn "New
    Window" into a submenu listing the profiles by name. Both are handled,
    because guessing wrong means quietly opening an ordinary window and never
    noticing.

    Answers True when a profile window was opened, False when there is no
    profile to open one in — the caller then falls back to an ordinary
    window, which is a lesser but honest arrangement.

    Menu items are matched BY NAME, never by position: a menu that grows an
    entry shifts every index below it, and this menu grows an entry exactly
    when a profile is added.
    """
    script = """
    tell application "Safari" to activate
    delay 0.5
    tell application "System Events" to tell process "Safari"
      set fileMenu to menu 1 of menu bar item "File" of menu bar 1
      repeat with anItem in menu items of fileMenu
        set itemName to ""
        try
          set itemName to name of anItem as text
        end try
        if itemName is "New PROFILE_NAME Window" then
          click anItem
          return "opened"
        end if
      end repeat
      repeat with anItem in menu items of fileMenu
        set itemName to ""
        try
          set itemName to name of anItem as text
        end try
        if itemName is "New Window" and (count of menus of anItem) > 0 then
          repeat with subItem in menu items of menu 1 of anItem
            set subName to ""
            try
              set subName to name of subItem as text
            end try
            if subName is "PROFILE_NAME" then
              click subItem
              return "opened"
            end if
          end repeat
        end if
      end repeat
      return "no profile"
    end tell
    """.replace("PROFILE_NAME", profile)
    try:
        answer = osascript(script)
    except subprocess.CalledProcessError:
        return False
    if answer != "opened":
        print(
            f'   No Safari profile named "{profile}" - capturing in an ordinary window.\n'
            f"   Making one (Safari > Settings > Profiles) keeps a light/dark choice saved\n"
            f"   during ordinary browsing out of these shots."
        )
        return False
    time.sleep(1.2)
    return True


class WrongAppearance(SystemExit):
    """A capture came out light in a dark pass, or the other way round."""


def page_is_dark(path: Path) -> bool:
    """Whether a captured page reads as dark, from the page itself.

    The MEDIAN luminance of a band well inside the content — middle 60%
    across, lower 60% down. Median rather than mean because a page is mostly
    background with text scattered over it, and the median ignores the text
    while a mean is dragged around by it. The band avoids the window chrome
    at the top, which is tinted by the system appearance and would answer a
    different question than the one being asked.
    """
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    left = int(image.width * 0.20)
    right = int(image.width * 0.80)
    top = int(image.height * 0.40)
    band = image.crop((left, top, right, image.height)).convert("L")

    # The median from the HISTOGRAM rather than from a list of pixels: it is
    # exact over every pixel in the band, it does not build a list of several
    # million of them, and it uses no API Pillow has deprecated.
    counts = band.histogram()
    total = 0
    for count in counts:
        total += count
    seen = 0
    median = 0
    for value in range(len(counts)):
        seen += counts[value]
        if seen >= total // 2:
            median = value
            break
    return median < DARK_BELOW


def verify_appearance(path: Path, expect_dark: bool, what: str) -> None:
    """Stop the run when a shot was taken in the wrong appearance.

    This is what replaced the private window (see `SafariWindow.__enter__`).
    A class site follows the system appearance UNLESS somebody has toggled
    that site's own light/dark switch, which it remembers in local storage —
    so an ordinary Safari window can serve a light page in the middle of a
    dark pass. That produces a screenshot which is WRONG and looks RIGHT,
    the worst kind this harness can make.

    The remedy named below is the whole reason this check is worth having:
    it is one click on the site's own toggle, and it is not obvious unless
    somebody says so.
    """
    if page_is_dark(path) == expect_dark:
        return
    wanted = "dark" if expect_dark else "light"
    got = "light" if expect_dark else "dark"
    raise WrongAppearance(
        f"{what} came out {got} during the {wanted} pass ({path.name}).\n"
        f"That site has a {got} theme saved in Safari's local storage, which overrides "
        f"the system appearance. Open it in Safari, click the site's own light/dark "
        f"toggle until it follows the system again, then re-run this pass."
    )


class SafariWindow:
    """One throwaway Safari window, used for a run of captures."""

    # MARK: - Initializer

    def __init__(self, width: int, height: int, left: int = 60, top: int = 60):
        self.width: int = width
        self.height: int = height
        self.left: int = left
        self.top: int = top
        self.window_id: str = ""
        self.previous_application: str = ""

    # MARK: - Functions

    def __enter__(self) -> "SafariWindow":
        self.previous_application = frontmost_application()
        osascript('tell application "Safari" to activate')
        time.sleep(0.6)
        # A window in the capture PROFILE if there is one, an ordinary
        # window otherwise. **Never a private one** — this is a rule, not
        # a preference.
        #
        # A private window wears a dark address bar, deliberately, as Safari's
        # way of telling you where you are. On a marketing page that is a
        # black band across the top of every class-site screenshot, next to
        # shots that do not have one. It sticks out, and no visitor can be
        # told why it is there.
        #
        # It WAS private, for a real reason: a class site remembers a
        # light/dark choice in local storage, and a choice saved during
        # ordinary browsing once overrode the appearance a dark pass had set
        # machine-wide, so one course was photographed light in a dark run.
        # That reason has not gone away — it is answered differently now, by
        # `verify_appearance` below, which CHECKS each capture instead of
        # trying to control the storage it came from. Checking is the better
        # trade even setting the address bar aside: the private window
        # prevented the fault silently, and a check that fails says which
        # site, which pass, and what to do about it.
        #
        # (Windows solved the same problem with `--user-data-dir`, a
        # throwaway Edge profile — clean storage, ordinary chrome. Safari
        # takes no such flag, which is why the mac needs its own answer.)
        if not open_profile_window(CAPTURE_PROFILE):
            osascript('tell application "System Events" to keystroke "n" using command down')
        time.sleep(1.2)
        self.window_id = osascript('tell application "Safari" to return id of front window')
        self.resize(self.width, self.height)
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> bool:
        if self.window_id:
            try:
                osascript(f'tell application "Safari" to close window id {self.window_id}')
            except subprocess.CalledProcessError:
                pass
        if self.previous_application:
            try:
                osascript(f'tell application "{self.previous_application}" to activate')
            except subprocess.CalledProcessError:
                pass
        return False

    def resize(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        right = self.left + width
        bottom = self.top + height
        osascript(
            f'tell application "Safari" to set bounds of window id {self.window_id} '
            f'to {{{self.left}, {self.top}, {right}, {bottom}}}'
        )
        time.sleep(0.4)

    def load(self, url: str, settle_seconds: float = 3.0) -> None:
        """Load a page, and land anchors where they claim to point.

        A URL with a fragment is loaded in two stages: the page first, so
        diagrams and mathematics finish rendering and the layout stops
        moving, then the fragment, so the scroll happens against the final
        layout. Scrolled in one step, Safari jumps to where the anchor WAS
        before the diagrams above it reflowed the page — the capture then
        shows the section above the one the caption names.
        """
        if "#" in url:
            page = url.split("#")[0]
            osascript(
                f'tell application "Safari" to set URL of document of window id {self.window_id} to "{page}"'
            )
            time.sleep(settle_seconds)
            osascript(
                f'tell application "Safari" to set URL of document of window id {self.window_id} to "{url}"'
            )
            time.sleep(1.5)
            self.unfocus_address_bar()
            return
        osascript(
            f'tell application "Safari" to set URL of document of window id {self.window_id} to "{url}"'
        )
        time.sleep(settle_seconds)
        self.unfocus_address_bar()

    def unfocus_address_bar(self) -> None:
        """Escape, so the address field is not selected in the photograph.

        A new window opens with the address field focused, and loading a page
        programmatically does not move focus — every capture then shows the
        full URL selected in blue, which reads as somebody mid-edit.
        """
        osascript(
            f'tell application "Safari"\n'
            f'  set index of window id {self.window_id} to 1\n'
            f'  activate\n'
            f'end tell\n'
            'tell application "System Events" to key code 53'
        )
        time.sleep(0.4)

    def press(self, keystroke: str, using: str = "") -> None:
        """Send a keystroke to THIS window through System Events.

        Safari's own AppleScript vocabulary cannot type into a page, and
        running JavaScript from an Apple Event is off by default and cannot be
        turned on programmatically. System Events can, which is how the search
        panel gets opened and typed into.

        The window is raised by ID first. Activating Safari alone fronts
        whatever window was already frontmost — once, the developer's own
        logged-in browser window — and the keystrokes landed there.
        """
        modifier = f" using {using}" if using else ""
        osascript(
            f'tell application "Safari"\n'
            f'  set index of window id {self.window_id} to 1\n'
            f'  activate\n'
            f'end tell\n'
            f'delay 0.4\n'
            f'tell application "System Events" to keystroke "{keystroke}"{modifier}'
        )
        time.sleep(1.0)

    def capture(self, destination: Path) -> Path:
        """Save the window itself, by window number.

        `screencapture -l` grabs that WINDOW's contents — the same thing the
        Option-click window capture gives: no shadow, transparent corners, and
        crucially independent of what is in front of it.

        The region capture this replaces photographed a RECTANGLE OF SCREEN. It
        depended on Safari having finished coming to the front, and when that
        lost a race the result was a screenshot of whatever was behind — once, a
        terminal window filed as a class website. A wrong screenshot that looks
        like a right one is the worst failure this harness has, so the mechanism
        that allows it is gone.
        """
        destination.parent.mkdir(parents=True, exist_ok=True)
        number = self.window_number()
        subprocess.run(
            ["screencapture", "-x", "-o", "-l", str(number), str(destination)],
            check=True,
        )
        if not destination.exists() or destination.stat().st_size == 0:
            raise SystemExit(f"screencapture wrote nothing for window {number}.")
        return destination

    def window_number(self) -> int:
        """The CoreGraphics window number for THIS Safari window.

        Read fresh each time: window numbers survive a page load, but not a
        window being closed and reopened, and a stale one captures nothing.

        Matched on the frame this object set, never "the biggest Safari
        window": the biggest one was once the developer's own logged-in
        Netlify dashboard, restored by Safari at launch, and three class-site
        captures photographed it instead of the page the harness had loaded.
        """
        helper = Path(__file__).resolve().parent / "windowid.swift"
        result = subprocess.run(
            ["swift", str(helper), "Safari",
             str(self.left), str(self.top), str(self.width), str(self.height)],
            capture_output=True, text=True,
        )
        if result.returncode != 0 or not result.stdout.strip():
            raise SystemExit(f"Could not find Safari's window: {result.stderr.strip()}")
        return int(result.stdout.strip())


def image_scale(path: Path, width_in_points: int) -> int:
    """How many pixels the display draws per point, as a whole number."""
    with Image.open(path) as image:
        pixels_wide = image.size[0]
    if width_in_points <= 0:
        return 1
    return max(1, round(pixels_wide / width_in_points))
