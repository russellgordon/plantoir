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


# macOS rounds a window's corners, and a window screenshot bakes those curves
# against whatever was behind them — which comes out as opaque BLACK specks at
# all four corners, invisible on a dark page and obvious on a light one. The
# radius is in points; it is scaled to the capture below.
WINDOW_CORNER_RADIUS_POINTS = 11


def mask_window_corners(path: Path, width_in_points: int) -> Path:
    """Make a window capture's four corners transparent with antialiasing."""
    from PIL import ImageChops

    with Image.open(path) as opened:
        image = opened.convert("RGBA")

    scale = max(1, round(image.width / width_in_points)) if width_in_points else 2
    radius = WINDOW_CORNER_RADIUS_POINTS * scale

    # 4x supersampling ensures smooth subpixel antialiasing at the corner curves
    ss_scale = 4
    big_size = (image.width * ss_scale, image.height * ss_scale)
    big_mask = Image.new("L", big_size, 0)
    ImageDraw.Draw(big_mask).rounded_rectangle(
        [(0, 0), (big_size[0] - 1, big_size[1] - 1)],
        radius=radius * ss_scale,
        fill=255,
    )
    mask = big_mask.resize(image.size, Image.Resampling.LANCZOS)

    combined_alpha = ImageChops.multiply(image.split()[3], mask)
    image.putalpha(combined_alpha)
    image.save(path, format="PNG")
    return path


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
