#!/usr/bin/env python3
"""Assemble the figures that are made of more than one window.

**The Mac figures (since #434, 2026-10-04) are built only by the `native_`
functions and `banner_over_window` below.** Each part is a whole
`screencapture -x -l` capture WITH the window's natural shadow, placed whole
with `Image.alpha_composite` so overlapping shadows blend the way they do on
a desktop: never scaled, never trimmed, never cropped, and no shadow drawn.
The canvas is computed to hold every capture in full, so no shadow can be
cut off. `fan`, `side_by_side`, `with_shadow` and `diagonal_hero` are what
the WINDOWS harness (capture_windows.py, hero_windows.py) still uses; the
Mac no longer calls them.

**Every part is a whole macOS window capture, and stays whole.** Each comes
from `screencapture -x -o -l <window id>` — the Option-click window capture —
with the window's own rounded corners, transparent outside the curve. This
module only PLACES them: it never crops through a window, never re-rounds a
corner, and never draws a shape. Scaling is Lanczos, of a whole image. A
shadow, where there is one, is made from the capture's own alpha channel, so
it follows the real curve. (Until 2026-09-27 this file cut Safari's toolbar
off the class-site captures and painted an 18 px rounded mask over the cut;
Russell saw the painted corners on the live site, and the code is gone.
`test_native_corners.py` fails on a square corner, or one drawn tighter than
any real window's.)

- `colour-schemes` fans three course home pages out like a hand of cards, so
  the different colour schemes sit side by side and can be compared.
- `light-and-dark` puts one site's two schemes next to each other.

Both make a point about COLOUR, which is why they are static images on the
marketing page. Their parts are photographed in a window with no browser
around it (`webwindow.swift`), so the subject is the sites, not three
browsers — and the edge of each part is the window's real edge.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageFilter

from shadow import shadow_margins

# The finished figures are the same width as every other screenshot on the
# page, so the column edges line up down the whole site.
FIGURE_WIDTH = 1700

SHADOW_BLUR = 26
SHADOW_STRENGTH = 0.40
SHADOW_DROP = 8


def with_shadow(card: Image.Image) -> Image.Image:
    """The card on a transparent canvas with a soft shadow beneath it.

    The shadow is the card's OWN alpha channel, darkened, moved down a little
    and blurred — so it has exactly the window's real corner curve, because it
    is made of it. Nothing is drawn. The card itself is pasted back untouched.
    """
    pad = SHADOW_BLUR * 2
    canvas = Image.new("RGBA", (card.width + pad * 2, card.height + pad * 2), (0, 0, 0, 0))
    card_alpha = card.getchannel("A")
    shadow_alpha = card_alpha.point(lambda value: round(value * SHADOW_STRENGTH))
    shadow_layer = Image.new("RGBA", card.size, (0, 0, 0, 0))
    shadow_layer.paste(Image.new("RGBA", card.size, (0, 0, 0, 255)), (0, 0), shadow_alpha)
    canvas.alpha_composite(shadow_layer, (pad, pad + SHADOW_DROP))
    canvas = canvas.filter(ImageFilter.GaussianBlur(SHADOW_BLUR / 2))
    canvas.alpha_composite(card, (pad, pad))
    return canvas


def whole_captures(sources: list[Path]) -> list[Image.Image]:
    """Open each capture as it is, and bring them all to one height.

    Whole images, scaled with Lanczos: the corner curve and its transparency
    scale with the rest of the window.
    """
    cards: list[Image.Image] = []
    for path in sources:
        with Image.open(path) as opened:
            cards.append(opened.convert("RGBA"))
    if not cards:
        raise SystemExit("Nothing to assemble.")
    height = cards[0].height
    for card in cards:
        height = min(height, card.height)
    scaled: list[Image.Image] = []
    for card in cards:
        if card.height != height:
            width = round(card.width * height / card.height)
            card = card.resize((width, height), Image.Resampling.LANCZOS)
        scaled.append(card)
    return scaled


def save_figure(canvas: Image.Image, destination: Path, figure_width: int = FIGURE_WIDTH) -> Path:
    """Trim the empty canvas round the figure, scale it whole, write PNG and WebP.

    The trim is to the bounding box of everything visible, shadows included,
    so it only ever removes fully transparent canvas — never part of a window.
    """
    visible = canvas.getbbox()
    if visible:
        canvas = canvas.crop(visible)
    if canvas.width != figure_width:
        height = round(canvas.height * figure_width / canvas.width)
        canvas = canvas.resize((figure_width, height), Image.Resampling.LANCZOS)
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, format="PNG", optimize=True)
    canvas.save(destination.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return destination


def fan(sources: list[Path], destination: Path, visible_fraction: float = 0.42) -> Path:
    """Overlap several whole captures, left one behind, right one in front.

    Each card shows `visible_fraction` of its width before the next one covers
    it — enough of the left edge of each site, which is where its colours and
    its typeface live, to compare them at a glance. Every card keeps its own
    corners; the ones in front simply lie over the ones behind.
    """
    cards = whole_captures(sources)
    pad = SHADOW_BLUR * 2
    step = round(cards[0].width * visible_fraction)
    total_width = step * (len(cards) - 1) + cards[-1].width + pad * 2
    canvas = Image.new("RGBA", (total_width, cards[0].height + pad * 2), (0, 0, 0, 0))
    index = 0
    for card in cards:
        canvas.alpha_composite(with_shadow(card), (step * index, 0))
        index += 1
    return save_figure(canvas, destination)


def side_by_side(sources: list[Path], destination: Path, gap: int = 60) -> Path:
    """Whole captures next to each other, the same height, nothing overlapping."""
    cards = whole_captures(sources)
    total_width = gap * (len(cards) - 1)
    for card in cards:
        total_width += card.width
    canvas = Image.new("RGBA", (total_width, cards[0].height), (0, 0, 0, 0))
    offset = 0
    for card in cards:
        canvas.alpha_composite(card, (offset, 0))
        offset += card.width + gap
    return save_figure(canvas, destination)


def diagonal_hero(
    obsidian_path: Path,
    plantoir_path: Path,
    safari_path: Path,
    destination: Path,
    stagger_ratio: float = 0.20,
    figure_width: int = FIGURE_WIDTH,
) -> Path:
    """Cascade 3 windows diagonally with equal horizontal and vertical stagger.

    1. Back / Top-Left: Obsidian note editor & vault tree
    2. Middle: Plantoir deploying progress view
    3. Front / Bottom-Right: Safari viewing the live published class site
    """
    raw_images = [
        Image.open(obsidian_path).convert("RGBA"),
        Image.open(plantoir_path).convert("RGBA"),
        Image.open(safari_path).convert("RGBA"),
    ]

    base_height = 800
    cards: list[Image.Image] = []
    for img in raw_images:
        aspect = img.width / img.height
        w = round(base_height * aspect)
        # The whole capture, scaled with Lanczos: its real corner curve scales with it.
        resized = img.resize((w, base_height), Image.Resampling.LANCZOS)
        cards.append(resized)

    card_w = cards[1].width
    card_h = base_height

    # Equal horizontal and vertical stagger for 1:1 diagonal visual symmetry
    stagger = round(card_w * stagger_ratio)
    pad = SHADOW_BLUR * 2

    total_w = card_w + stagger * 2 + pad * 2
    total_h = card_h + stagger * 2 + pad * 2

    canvas = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))

    offsets = [
        (0, 0),
        (stagger, stagger),
        (stagger * 2, stagger * 2),
    ]

    for card, (offset_x, offset_y) in zip(cards, offsets):
        canvas.alpha_composite(with_shadow(card), (offset_x, offset_y))

    return save_figure(canvas, destination, figure_width)



# ---------- Per-appearance composites (v1.4.0 scenes) ----------
#
# These are ordinary light/dark PAIRS once assembled — `build.py` serves them
# like any window shot — built from parts the scenes photograph once per
# appearance. Each part is a real `screencapture -l` of a real window; the
# composite only places them, it never paints over one.


def window_body(card: Image.Image) -> tuple[int, int, int, int]:
    """Where the window itself sits inside a shadowed capture: its left and
    top offset, and its width and height. The shadow margin round it is the
    capture's own."""
    margins = shadow_margins(card)
    if margins is None:
        raise SystemExit("A part has no opaque window in it; it cannot be placed.")
    left, top, right, bottom = margins
    return (left, top, card.width - left - right, card.height - top - bottom)


def open_whole(sources: list[Path]) -> list[Image.Image]:
    """Each capture exactly as it was taken: not scaled, not trimmed."""
    cards: list[Image.Image] = []
    for path in sources:
        with Image.open(path) as opened:
            cards.append(opened.convert("RGBA"))
    if not cards:
        raise SystemExit("Nothing to assemble.")
    return cards


def place_whole(cards: list[Image.Image], window_positions: list[tuple[int, int]],
                destination: Path, padding: int = 0) -> Path:
    """Lay whole shadowed captures out, back to front, and save the figure.

    `window_positions` says where each WINDOW's top-left corner goes (its
    shadow extends round it by the capture's own margin). The canvas is the
    union of every whole capture plus `padding` on each side, so every shadow
    is on it in full; nothing is trimmed afterwards. PNG and WebP, at the
    captures' own size.
    """
    placed: list[tuple[Image.Image, int, int]] = []
    smallest_x = None
    smallest_y = None
    largest_x = None
    largest_y = None
    index = 0
    for card in cards:
        body_left, body_top, body_width, body_height = window_body(card)
        window_x, window_y = window_positions[index]
        card_x = window_x - body_left
        card_y = window_y - body_top
        placed.append((card, card_x, card_y))
        if smallest_x is None or card_x < smallest_x:
            smallest_x = card_x
        if smallest_y is None or card_y < smallest_y:
            smallest_y = card_y
        if largest_x is None or card_x + card.width > largest_x:
            largest_x = card_x + card.width
        if largest_y is None or card_y + card.height > largest_y:
            largest_y = card_y + card.height
        index += 1
    canvas = Image.new("RGBA", (largest_x - smallest_x + padding * 2, largest_y - smallest_y + padding * 2),
                       (0, 0, 0, 0))
    for card, card_x, card_y in placed:
        canvas.alpha_composite(card, (card_x - smallest_x + padding, card_y - smallest_y + padding))
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, format="PNG", optimize=True)
    canvas.save(destination.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return destination


def native_cascade(sources: list[Path], destination: Path, stagger_ratio: float = 0.20,
                   padding: int = 48) -> Path:
    """The hero: windows cascaded diagonally, back to front, each whole with
    its own natural shadow, on a canvas that holds every shadow plus padding.

    The stagger is the same across and down, a fifth of the middle window's
    width, as the cascade has been since GUI-IMPROVEMENTS row 280.
    """
    cards = open_whole(sources)
    middle = cards[len(cards) // 2]
    stagger = round(window_body(middle)[2] * stagger_ratio)
    positions: list[tuple[int, int]] = []
    for index in range(len(cards)):
        positions.append((stagger * index, stagger * index))
    return place_whole(cards, positions, destination, padding)


def native_fan(sources: list[Path], destination: Path, visible_fraction: float = 0.42) -> Path:
    """Overlap whole captures left to right, the left one behind; tops of the
    windows aligned. Each shows `visible_fraction` of its window before the
    next covers it."""
    cards = open_whole(sources)
    step = round(window_body(cards[0])[2] * visible_fraction)
    positions: list[tuple[int, int]] = []
    for index in range(len(cards)):
        positions.append((step * index, 0))
    return place_whole(cards, positions, destination)


def native_side_by_side(sources: list[Path], destination: Path, gap: int = 96) -> Path:
    """Whole captures next to each other, windows top-aligned, `gap` pixels
    between one window and the next. The shadows between them overlap and
    blend, as two windows' shadows do on a desktop."""
    cards = open_whole(sources)
    positions: list[tuple[int, int]] = []
    window_x = 0
    for card in cards:
        positions.append((window_x, 0))
        window_x += window_body(card)[2] + gap
    return place_whole(cards, positions, destination)


def banner_over_window(window: Path, banner: Path, destination: Path, margin_fraction: float = 0.012) -> Path:
    """A notification banner laid over a window's top-right corner.

    macOS draws the banner at the top right of the SCREEN; placing it at the
    window's top right keeps the figure the size of the window while reading
    the way a teacher sees it. Both parts are whole: the window with its
    natural shadow, the banner as Notification Center drew it, its own shadow
    included; neither is scaled. The canvas holds both in full.
    """
    cards = open_whole([window, banner])
    base = cards[0]
    card = cards[1]
    body_left, body_top, body_width, body_height = window_body(base)
    banner_left, banner_top, banner_width, banner_height = window_body(card)
    margin = max(8, round(body_width * margin_fraction))
    # Room above the window for the banner to sit partly outside it, so it
    # reads as something on top of the window rather than part of it.
    lift = round(banner_height * 0.35)
    positions = [
        (0, lift),
        (body_width - banner_width - margin, 0),
    ]
    return place_whole(cards, positions, destination)
