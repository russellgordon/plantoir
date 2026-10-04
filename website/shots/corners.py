#!/usr/bin/env python3
"""Tell a window's REAL corner from a drawn one, by reading the pixels.

Every picture on plantoir.app is made from whole macOS window captures —
`screencapture -x -l <window id>`, the window capture with its natural shadow
(#434) — which hand back the window with its own rounded corners, the pixels
outside the curve transparent but for the shadow (well under OPAQUE). Nothing is cropped through a corner and nothing
re-draws one. This module is how that is CHECKED rather than hoped for: the
gate in `test_native_corners.py` and the check `capture.py` runs before it
calls a picture finished both use it.

How a picture is read:

1. Its windows are found as the opaque shapes in its alpha channel (a figure
   of two windows side by side has two; a cascade of overlapping windows has
   one shape whose outer corners are real window corners).
2. At each outer corner of each shape, the area left transparent outside the
   curve gives the corner's radius, and a walk down the window beside the
   corner gives the window's height.
3. A corner fails when it is OPAQUE (a rectangle: a screen grab, a crop, or a
   page screenshot with no window at all) or when its radius is a smaller
   fraction of its window's height than any macOS window's (a rounded mask
   drawn by hand). A ratio, not a pixel count, so it means the same thing on
   a full-size capture and on a figure scaled to a third.

The numbers behind the threshold are beside SMALLEST_REAL_RADIUS.
"""

from __future__ import annotations

import math
from collections import deque
from pathlib import Path

from PIL import Image

# Alpha at or above this is "the window"; below it is outside the curve.
OPAQUE = 128

# A real macOS window's corner radius, as a fraction of the window's height,
# is at least this. Measured 2026-09-27 (macOS 26): 0.0199 for a plain
# titled window (the page window, `webwindow.swift`), 0.0214 Obsidian, 0.0225
# the assistant, 0.032 Safari, 0.038 Plantoir's main window, 0.19 a
# notification banner — and the ratio holds under scaling (the page window is
# 0.0188 on the two-up figure, at a third of its size). The drawn masks this
# replaced measured 0.0099 to 0.0128. Half-way between the two groups.
SMALLEST_REAL_RADIUS = 0.0155

# Windows 11 rounds every window by the same 8 DIPs whatever its size, so the
# ratio falls as the window grows and cannot be held to the mac's number.
# Measured 2026-10-03 on Windows.Graphics.Capture pictures at 2x (#380):
# 0.0142 Plantoir and Edge at 640 DIPs tall, 0.0130 Obsidian, 0.0105 a page
# window 860 DIPs tall, and 0.0091 to 0.0136 once assembled into the figures.
# This floor is 8 DIPs on a window 2,000 DIPs tall: below it a corner was
# drawn, and a square one fails before the ratio is asked for. The masks
# hero_windows.py used to draw measured 0.0099 to 0.0128 -- INSIDE the real
# range -- so for a Windows picture this gate catches a square corner and
# little else; the rule is kept by the code that no longer draws.
SMALLEST_REAL_WINDOWS_RADIUS = 0.004

# The Windows figures retaken as whole native captures so far (#380). The
# single-window Windows shots are still square page and content pictures;
# when they are retaken this list goes and `include_windows=True` takes over.
WINDOWS_FIGURES_RETAKEN = ("hero", "colour-schemes", "light-and-dark")


def is_windows_picture(name: str) -> bool:
    """A picture taken on Windows: `<id>-windows.png`, `<id>-windows-dark.webp`."""
    stem = name.rsplit(".", 1)[0]
    return stem.endswith("-windows") or "-windows-" in stem


# A diagonal run longer than this fraction of the shape's shorter side is not
# a corner at all but empty canvas (the outside corner of a cascade, say), and
# is not judged.
NOT_A_CORNER_FRACTION = 0.15

# Shapes smaller than this, in pixels on a side, are shadows' stray specks
# or text, not windows.
SMALLEST_WINDOW = 80

# Component-finding is done on a reduced copy, for speed; corners are always
# measured at full size.
REDUCTION = 4


def window_shapes(alpha: Image.Image) -> list[tuple[int, int, int, int]]:
    """The bounding box of every opaque shape, at full size."""
    width, height = alpha.size
    small_width = max(1, width // REDUCTION)
    small_height = max(1, height // REDUCTION)
    small = alpha.resize((small_width, small_height), Image.NEAREST)
    pixels = small.load()
    seen: set[tuple[int, int]] = set()
    boxes: list[tuple[int, int, int, int]] = []
    for start_y in range(small_height):
        for start_x in range(small_width):
            if (start_x, start_y) in seen or pixels[start_x, start_y] < OPAQUE:
                continue
            left, top, right, bottom = start_x, start_y, start_x, start_y
            queue: deque[tuple[int, int]] = deque([(start_x, start_y)])
            seen.add((start_x, start_y))
            while queue:
                x, y = queue.popleft()
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
                for next_x, next_y in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= next_x < small_width and 0 <= next_y < small_height:
                        if (next_x, next_y) not in seen and pixels[next_x, next_y] >= OPAQUE:
                            seen.add((next_x, next_y))
                            queue.append((next_x, next_y))
            if (right - left + 1) * REDUCTION < SMALLEST_WINDOW:
                continue
            if (bottom - top + 1) * REDUCTION < SMALLEST_WINDOW:
                continue
            boxes.append(exact_box(alpha, left * REDUCTION, top * REDUCTION,
                                   min(width, (right + 1) * REDUCTION),
                                   min(height, (bottom + 1) * REDUCTION)))
    return boxes


def exact_box(alpha: Image.Image, left: int, top: int, right: int, bottom: int) -> tuple[int, int, int, int]:
    """Tighten a reduced-size box to the exact opaque pixels near it."""
    width, height = alpha.size
    region = (max(0, left - REDUCTION), max(0, top - REDUCTION),
              min(width, right + REDUCTION), min(height, bottom + REDUCTION))
    opaque = alpha.crop(region).point(lambda value: 255 if value >= OPAQUE else 0)
    found = opaque.getbbox()
    if found is None:
        return (left, top, right - 1, bottom - 1)
    return (region[0] + found[0], region[1] + found[1],
            region[0] + found[2] - 1, region[1] + found[3] - 1)


def corner_problems(path: Path) -> list[str]:
    """Everything wrong with the corners in one picture; empty when all are real."""
    with Image.open(path) as opened:
        if "A" not in opened.getbands() and opened.mode != "P":
            return [f"{path.name}: has no transparency at all, so no window in it can have its real corners"]
        image = opened.convert("RGBA")
    alpha = image.getchannel("A")
    boxes = window_shapes(alpha)
    if not boxes:
        return [f"{path.name}: no window found in it"]
    problems: list[str] = []
    for box in boxes:
        problems.extend(problems_in_shape(path.name, alpha, box))
    return problems


def problems_in_shape(name: str, alpha: Image.Image, box: tuple[int, int, int, int]) -> list[str]:
    left, top, right, bottom = box
    shorter_side = min(right - left + 1, bottom - top + 1)
    corner_box = max(8, round(shorter_side * NOT_A_CORNER_FRACTION * 2 / 3))
    pixels = alpha.load()
    corners = [
        ("top-left", left, top, 1, 1),
        ("top-right", right, top, -1, 1),
        ("bottom-left", left, bottom, 1, -1),
        ("bottom-right", right, bottom, -1, -1),
    ]
    problems: list[str] = []
    judged = 0
    system = "macOS"
    smallest = SMALLEST_REAL_RADIUS
    if is_windows_picture(name):
        system = "Windows"
        smallest = SMALLEST_REAL_WINDOWS_RADIUS
    for label, corner_x, corner_y, step_x, step_y in corners:
        diagonal = 0
        while diagonal <= corner_box and pixels[corner_x + step_x * diagonal,
                                                corner_y + step_y * diagonal] < OPAQUE:
            diagonal += 1
        if diagonal > corner_box:
            # Empty canvas, not a corner: the outside corner of a cascade.
            continue
        judged += 1
        where = f"{name}: the window at {left},{top} ({right - left + 1}x{bottom - top + 1}) has a {label} corner"
        if diagonal == 0:
            problems.append(f"{where} that is square and opaque — not a {system} window capture")
            continue
        radius = corner_radius(pixels, corner_x, corner_y, step_x, step_y, corner_box)
        height = window_height(pixels, alpha.size[1], corner_x + step_x * corner_box, corner_y, step_y)
        if height == 0:
            continue
        ratio = radius / height
        if ratio < smallest:
            problems.append(f"{where} whose curve is {ratio:.4f} of the window's height — tighter than any "
                            f"real {system} window (at least {smallest}); a drawn corner")
    if judged == 0:
        problems.append(f"{name}: the window at {left},{top} has no corner that could be read")
    return problems


def corner_radius(pixels, corner_x: int, corner_y: int, step_x: int, step_y: int, size: int) -> float:
    """The corner's radius, from the AREA cut away outside the curve.

    Counting the area rather than measuring one row makes the answer steady
    to a fraction of a pixel after scaling: a quarter-circle corner of radius
    r leaves (1 - pi/4) r squared outside it.
    """
    outside = 0
    for across in range(size):
        for down in range(size):
            if pixels[corner_x + step_x * across, corner_y + step_y * down] < OPAQUE:
                outside += 1
    return math.sqrt(outside / (1 - math.pi / 4))


def window_height(pixels, image_height: int, column: int, corner_y: int, step_y: int) -> int:
    """How tall the window is, walking from its corner along one column.

    Walked in a column just inside the corner, so in a cascade or a fan of
    overlapping windows it measures THIS window, not the whole pile.
    """
    offset = 0
    while 0 <= corner_y + step_y * offset < image_height and pixels[column, corner_y + step_y * offset] < OPAQUE:
        offset += 1
    height = 0
    while 0 <= corner_y + step_y * (offset + height) < image_height \
            and pixels[column, corner_y + step_y * (offset + height)] >= OPAQUE:
        height += 1
    return height


def images_the_pages_show(website: Path, image_dir: Path, include_windows: bool = False) -> list[Path]:
    """Every picture the pages put in front of a Mac visitor, PNG and WebP.

    Read from shots.json and the pages themselves, so a shot added to either is
    checked without anyone remembering to list it here. A shot still waiting
    for its capture is skipped, because build.py shows nothing for it.
    """
    import json
    import re

    manifest = json.loads((website / "shots.json").read_text(encoding="utf-8"))
    shots_by_id: dict[str, dict] = {}
    for shot in manifest["shots"]:
        shots_by_id[shot["id"]] = shot
    used: list[str] = []
    for page in sorted((website / "pages").glob("*.html")):
        for identifier in re.findall(r"\{\{shot:([a-z0-9-]+)", page.read_text(encoding="utf-8")):
            if identifier not in used:
                used.append(identifier)
    paths: list[Path] = []
    for identifier in used:
        shot = shots_by_id.get(identifier)
        if shot is None or shot.get("awaiting_capture"):
            continue
        stems: list[str] = []
        if shot.get("static"):
            stems.append(identifier)
            if shot.get("dark"):
                stems.append(f"{identifier}-dark")
            if include_windows:
                stems.append(f"{identifier}-windows")
        else:
            stems.append(f"{identifier}-light")
            stems.append(f"{identifier}-dark")
            if include_windows:
                stems.append(f"{identifier}-windows-light")
                stems.append(f"{identifier}-windows-dark")
        for stem in stems:
            for suffix in (".png", ".webp"):
                candidate = image_dir / f"{stem}{suffix}"
                if candidate.exists():
                    paths.append(candidate)
    return paths


def windows_figures_retaken(image_dir: Path) -> list[Path]:
    """The Windows figures already retaken natively, PNG and WebP (#380)."""
    paths: list[Path] = []
    for identifier in WINDOWS_FIGURES_RETAKEN:
        for stem in (f"{identifier}-windows", f"{identifier}-windows-light", f"{identifier}-windows-dark"):
            for suffix in (".png", ".webp"):
                candidate = image_dir / f"{stem}{suffix}"
                if candidate.exists():
                    paths.append(candidate)
    return paths


if __name__ == "__main__":
    import sys

    repo = Path(__file__).resolve().parent.parent.parent
    with_windows = "--windows" in sys.argv
    for picture in images_the_pages_show(repo / "website", repo / "site" / "img", with_windows):
        found = corner_problems(picture)
        verdict = "native" if not found else "DRAWN/OPAQUE"
        print(f"{verdict:13s} {picture.name}")
        for line in found:
            print(f"              {line}")
