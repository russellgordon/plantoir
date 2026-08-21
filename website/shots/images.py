#!/usr/bin/env python3
"""Get a screenshot ready to be served.

A capture comes off the screen at the display's own resolution, which is about
twice what the page ever needs and several times the file size a visitor
should be asked to download. Every saved shot is therefore scaled down to
twice its largest drawn size and written twice: a PNG, and a WebP the page
offers first.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

# Twice the widest the page ever draws each kind of shot, so a Retina screen
# still gets a pixel per pixel and nobody downloads more than that.
WIDEST_WINDOW_PIXELS = 1700
WIDEST_PHONE_PIXELS = 720


# There is NO corner masking here any more, and that is the point.
#
# There used to be a `mask_window_corners` that made each shot's four corners
# transparent with a guessed 11-point radius. It existed because the app-window
# shots could arrive from XCUITest's `window.screenshot()`, a RECTANGLE capture
# that bakes the corner curves against whatever was behind them and hands back
# opaque black specks.
#
# Every shot is now taken with `screencapture -o -l <window number>` — macOS's
# own window capture — and that already returns the curve antialiased with the
# corners at alpha 0. Measured, rather than assumed: the four corner pixels of
# such a capture read (0, 0, 0, 0). Masking a correct capture is not harmless,
# either: it multiplies a GUESSED radius over a real one, which erodes the
# curve when the guess is generous and leaves a fringe when it is mean.
#
# If black corners ever come back, the capture is wrong — find out why it did
# not go through `screencapture -l` instead of painting over it here.


def prepare(path: Path, widest: int = WIDEST_WINDOW_PIXELS) -> Path:
    """Scale a capture down if it is oversized, then write PNG and WebP."""
    with Image.open(path) as opened:
        image = opened.convert("RGBA")

    if image.width > widest:
        height = round(image.height * widest / image.width)
        image = image.resize((widest, height), Image.LANCZOS)

    image.save(path, format="PNG", optimize=True)
    image.save(path.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return path
