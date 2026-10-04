#!/usr/bin/env python3
"""Every Mac window on plantoir.app keeps its whole natural shadow.

Russell, 2026-10-03/04, after a release where some shadows were cut off and
the windows did not match one another: the shadow is "the natural shadow that
would be captured using the built-in tool" — exactly what
`screencapture -x -l <window id>` writes, with the window ACTIVE (macOS draws
a larger, darker shadow round the active window than round an inactive one).
Never `-o`, which leaves the shadow out. Never a drawn, generated, blurred,
scaled or retouched shadow, and no post-processing of it: no trim, no crop,
no scaling of the capture, so the transparent margin the shadow lives in
arrives on the page exactly as wide as macOS made it.

This module is the ONE place a Mac window is photographed from Python
(`capture_window`), and the place the result is measured
(`shadow_margins`, `edge_alpha`). `test_native_corners.py` runs the
measurements over every Mac picture the pages show, so a capture that lost
its shadow, caught its window inactive, or was cropped or scaled fails the
suite rather than shipping. The Swift captures (the UI tests and
`webwindow.swift`) call `screencapture -x -l` the same way.

Stdlib and Pillow only.
"""

from __future__ import annotations

import subprocess
import time
from pathlib import Path

from PIL import Image

# The shadow margin macOS 26 gives an ACTIVE, ordinary titled window on a
# 2x display, in pixels: left, top, right, bottom, measured from the edge of
# the `screencapture -x -l` picture to the first opaque pixel of the window.
# Measured 2026-10-04 on this Mac (MacBook Pro built-in display, 2x): iTerm,
# Safari, Obsidian, Plantoir's main and assistant windows and the page window
# of webwindow.swift all came back with exactly this margin, whatever their
# size. An INACTIVE window comes back with a smaller one, which is how a
# capture taken while its app was in the background is caught.
NATIVE_MARGINS: tuple[int, int, int, int] = (112, 76, 112, 148)

# "Opaque" for the purpose of finding where the window starts. The window's
# own edge is antialiased over a pixel or two; the shadow never comes near
# this.
WINDOW_ALPHA = 250

# The band round the edge that must be transparent: alpha there means a
# shadow ran off the picture, i.e. was cut off.
EDGE_BAND = 3

# The most alpha a WHOLE capture carries in that band. Measured 2026-10-04:
# `screencapture -x -l` of the page window (webwindow.swift) left 8 to 11
# isolated pixels of alpha 1 (of 255) along each side, scattered the length
# of the edge — the shadow's dithering, not its body; an iTerm capture had
# none. A shadow that is really cut off is far darker at the cut: 60 px into
# the bottom margin it is already well above 1 (TheShadowCheckItself). The
# capture is never touched to remove them; the check reads past them.
EDGE_NOISE = 1


def capture_window(number: int | str, destination: Path) -> Path:
    """Photograph one window, shadow and all, by its CoreGraphics number.

    The caller makes the window's app active first and waits about a second
    (`activate_and_settle`), because the shadow of an inactive window is
    smaller and lighter, and the pictures would not match.
    """
    destination.parent.mkdir(parents=True, exist_ok=True)
    taken = subprocess.run(["screencapture", "-x", "-l", str(number), str(destination)],
                           capture_output=True, text=True)
    if taken.returncode != 0 or not destination.exists() or destination.stat().st_size == 0:
        said = taken.stderr.strip() or "nothing"
        raise SystemExit(f"screencapture wrote nothing for window {number} (it said: {said}).")
    return destination


def capture_active_window(application: str, number: int | str, destination: Path, attempts: int = 3) -> Path:
    """Activate `application`, photograph its window, and take it again if the
    shadow came back as an INACTIVE window's.

    Measured 2026-10-04 07:20: the dark how-i-teach pass photographed
    Obsidian with grey traffic lights and a (68, 52, 68, 84) margin — after
    the scheduled-deploy scene, something else had come forward in the
    second between activating and capturing. The picture is retaken, never
    adjusted; after `attempts` the last one is kept and the checks name it.
    """
    for _ in range(attempts):
        activate_and_settle(application)
        capture_window(number, destination)
        if shadow_margins(destination) == NATIVE_MARGINS:
            break
    return destination


def activate_and_settle(application: str, seconds: float = 1.0) -> None:
    """Bring an application to the front and give macOS time to redraw its
    window's shadow as the active one."""
    subprocess.run(["osascript", "-e", f'tell application "{application}" to activate'],
                   capture_output=True)
    time.sleep(seconds)


def shadow_margins(picture: Image.Image | Path) -> tuple[int, int, int, int] | None:
    """Left, top, right and bottom: from each edge of the picture to the first
    opaque pixel of a window. None when there is no opaque window at all."""
    image = _opened(picture)
    alpha = image.getchannel("A")
    opaque = alpha.point(lambda value: 255 if value >= WINDOW_ALPHA else 0)
    box = opaque.getbbox()
    if box is None:
        return None
    return (box[0], box[1], image.width - box[2], image.height - box[3])


def edge_alpha(picture: Image.Image | Path, band: int = EDGE_BAND) -> int:
    """The highest alpha in the outermost `band` pixels on every side.

    0 means nothing reaches the edge of the picture. Anything else is a shadow
    (or a window) that was cut off there.
    """
    image = _opened(picture)
    alpha = image.getchannel("A")
    width, height = image.size
    strips = [
        (0, 0, width, band),
        (0, height - band, width, height),
        (0, 0, band, height),
        (width - band, 0, width, height),
    ]
    highest = 0
    for strip in strips:
        low, high = alpha.crop(strip).getextrema()
        if high > highest:
            highest = high
    return highest


def problems_with_shadow(picture: Path, expected_margins: tuple[int, int, int, int] | None = NATIVE_MARGINS) -> list[str]:
    """Everything wrong with one picture's shadow; empty when it is whole.

    With `expected_margins` None, only the edge is checked (a figure whose
    margin is not a single window's, such as the hero with its padding).
    """
    image = _opened(picture)
    problems: list[str] = []
    if image.mode != "RGBA":
        return [f"{picture.name}: has no transparency, so it cannot carry a window's shadow"]
    edge = edge_alpha(image)
    if edge > EDGE_NOISE:
        problems.append(f"{picture.name}: alpha {edge} in the outermost {EDGE_BAND} px — a shadow is cut off "
                        "at the edge of the picture")
    if expected_margins is not None:
        margins = shadow_margins(image)
        if margins != expected_margins:
            problems.append(f"{picture.name}: shadow margins {margins} (left, top, right, bottom), not the "
                            f"{expected_margins} an active window's `screencapture -x -l` gives — taken "
                            "inactive, with -o, cropped or scaled")
    return problems


def _opened(picture: Image.Image | Path) -> Image.Image:
    if isinstance(picture, Image.Image):
        return picture if picture.mode == "RGBA" else picture.convert("RGBA")
    with Image.open(picture) as opened:
        if "A" not in opened.getbands() and opened.mode != "P":
            return opened.convert("RGB")
        return opened.convert("RGBA")


# The Mac pictures whose margin is not ONE window's, and why. Each is still
# held to the edge check: nothing may be cut off.
#   hero      — three windows cascaded on a canvas with padding round them.
#   schedule  — the notification banner sits above the window's top edge.
FIGURES_WITH_THEIR_OWN_MARGIN = ("hero", "schedule")

# Not a macOS window at all: the phone is the iOS Simulator's screen in a
# device frame drawn by RocketSim, so it has no window shadow to keep.
NOT_A_MAC_WINDOW = ("site-phone",)

# Parts of the hero that are committed beside the pictures the pages show,
# and so are checked too: the hero's sources must match each other.
HERO_SOURCES_COMMITTED = ("hero-plantoir",)


def mac_pictures_to_check(website: Path, image_dir: Path) -> list[tuple[Path, tuple[int, int, int, int] | None]]:
    """Every Mac picture the pages show, with the margin it must have (None:
    the edge check only). PNG only: the WebP beside each is the same picture
    compressed, and lossy compression moves a shadow's faintest alpha by a
    step or two."""
    from corners import images_the_pages_show

    checks: list[tuple[Path, tuple[int, int, int, int] | None]] = []
    for picture in images_the_pages_show(website, image_dir):
        if picture.suffix != ".png":
            continue
        identifier = _identifier(picture.name)
        if identifier in NOT_A_MAC_WINDOW:
            continue
        if identifier in FIGURES_WITH_THEIR_OWN_MARGIN:
            checks.append((picture, None))
        else:
            checks.append((picture, NATIVE_MARGINS))
    for identifier in HERO_SOURCES_COMMITTED:
        for suffix in ("light", "dark"):
            picture = image_dir / f"{identifier}-{suffix}.png"
            if picture.exists():
                checks.append((picture, NATIVE_MARGINS))
    return checks


def shadow_problems_on_the_site(website: Path, image_dir: Path) -> list[str]:
    """Every cut-off or mismatched shadow among the Mac pictures."""
    problems: list[str] = []
    for picture, margins in mac_pictures_to_check(website, image_dir):
        problems.extend(problems_with_shadow(picture, margins))
    return problems


def _identifier(name: str) -> str:
    stem = name.rsplit(".", 1)[0]
    for suffix in ("-light", "-dark"):
        if stem.endswith(suffix):
            return stem[: -len(suffix)]
    return stem
