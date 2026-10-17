#!/usr/bin/env python3
"""Get a screenshot ready to be served.

Every saved shot is written twice: a PNG, and a WebP the page offers first.
A WINDOW capture -- the Mac's (#434) and, since #557, Windows' -- is served
at its own pixel size, never scaled: the page draws it beside its other-
platform twin at the same CSS size, and a 2x Windows capture cut back to
1700 px looked soft beside the mac's 2784. Only the phone picture is scaled
down (WIDEST_PHONE_PIXELS), being a simulator screen far larger than the
page ever draws it.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

# Twice the widest the page ever draws the phone, so a Retina screen still
# gets a pixel per pixel. (WIDEST_WINDOW_PIXELS = 1700 capped every Windows
# window picture until #557, 2026-10-16; removed so nothing reaches for it.)
WIDEST_PHONE_PIXELS = 720


# There is NO corner masking here any more, and that is the point.
#
# There used to be a `mask_window_corners` that made each shot's four corners
# transparent with a guessed 11-point radius. It existed because the app-window
# shots could arrive from XCUITest's `window.screenshot()`, a RECTANGLE capture
# that bakes the corner curves against whatever was behind them and hands back
# opaque black specks.
#
# Every shot is now taken with `screencapture -x -l <window number>` — macOS's
# own window capture, with the window's natural shadow (#434; it was `-o`,
# shadow off, until 2026-10-04) — and that already returns the curve
# antialiased, with everything outside the window and its shadow at alpha 0. Masking a correct capture is not harmless,
# either: it multiplies a GUESSED radius over a real one, which erodes the
# curve when the guess is generous and leaves a fringe when it is mean.
#
# If black corners ever come back, the capture is wrong — find out why it did
# not go through `screencapture -l` instead of painting over it here.


def serve_as_captured(path: Path) -> Path:
    """Write the WebP beside a Mac window capture, and leave the capture's
    pixels exactly as `screencapture -x -l` made them.

    Every Mac window shot is served at its own size since #434 (2026-10-04).
    Scaling it would scale its shadow, and Russell's rule is the natural
    shadow with no post-processing — and pictures of different widths scaled
    to one width end up with different shadow margins, which is the
    inconsistency that rule was written about. The page draws each picture
    at half its pixel size (build.py), which for a 2x capture is the window's
    own size in points. The PNG is re-saved losslessly (optimize) and the
    WebP is the same picture compressed.
    """
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    image.save(path, format="PNG", optimize=True)
    image.save(path.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return path


def prepare(path: Path, widest: int | None = None) -> Path:
    """Write PNG and WebP, scaling down only when `widest` is given.

    For the PHONE picture (`widest=WIDEST_PHONE_PIXELS`) and the Windows
    pictures. A Windows window capture passes nothing and is never scaled
    (#557, following the print pictures of #544): it stands beside the mac's
    capture, which `serve_as_captured` never scales (#434).
    """
    with Image.open(path) as opened:
        image = opened.convert("RGBA")

    if widest is not None and image.width > widest:
        height = round(image.height * widest / image.width)
        image = image.resize((widest, height), Image.LANCZOS)

    image.save(path, format="PNG", optimize=True)
    image.save(path.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return path
