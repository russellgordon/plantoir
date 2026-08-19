#!/usr/bin/env python3
"""Build the two figures that are assembled rather than photographed.

Both make a point about COLOUR, which is why they are static images on the
marketing page: a figure showing what three courses look like would be arguing
against itself if it changed to match the reader's own colour scheme.

- `colour-schemes` fans three course home pages out like a hand of cards, so
  the different Quartz schemes sit side by side and can be compared.
- `light-and-dark` puts one site's two schemes next to each other.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

# The finished figures are the same width as every other screenshot on the
# page, so the column edges line up down the whole site.
FIGURE_WIDTH = 1700

CORNER_RADIUS = 18
SHADOW_BLUR = 26


def rounded(image: Image.Image, radius: int = CORNER_RADIUS) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (image.width - 1, image.height - 1)], radius=radius, fill=255
    )
    result = image.convert("RGBA")
    result.putalpha(mask)
    return result


def with_shadow(card: Image.Image) -> Image.Image:
    """A soft drop shadow, so overlapping cards read as a stack."""
    from PIL import ImageFilter

    pad = SHADOW_BLUR * 2
    canvas = Image.new("RGBA", (card.width + pad * 2, card.height + pad * 2), (0, 0, 0, 0))

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shape = Image.new("L", card.size, 0)
    ImageDraw.Draw(shape).rounded_rectangle(
        [(0, 0), (card.width - 1, card.height - 1)], radius=CORNER_RADIUS, fill=105
    )
    shadow.paste((0, 0, 0, 105), (pad, pad + 6), shape)
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR / 2))

    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(card, (pad, pad), card)
    return canvas


# The browser's own chrome, in points, at the top of a Safari capture. Cropped
# off for the fanned figure: three sets of traffic lights and three address
# bars stacked up read as three browser windows, when the subject is the three
# SITES. The full-window captures elsewhere on the page keep their chrome.
CHROME_POINTS = 52


def without_chrome(image: Image.Image, width_in_points: int = 1280) -> Image.Image:
    scale = max(1, round(image.width / width_in_points))
    top = CHROME_POINTS * scale
    if top >= image.height:
        return image
    return image.crop((0, top, image.width, image.height))


def fan(sources: list[Path], destination: Path, visible_fraction: float = 0.42) -> Path:
    """Overlap several captures horizontally, left one behind, right one in front.

    Each card shows `visible_fraction` of its width before the next one covers
    it — enough of the left edge of each site, which is where its colours and
    its typeface live, to compare them at a glance.
    """
    cards = [rounded(without_chrome(Image.open(path).convert("RGBA"))) for path in sources]
    if not cards:
        raise SystemExit("Nothing to fan out.")

    # Every card the same height, so the fan sits on one line.
    height = min(card.height for card in cards)
    scaled = []
    for card in cards:
        if card.height != height:
            width = round(card.width * height / card.height)
            card = card.resize((width, height), Image.LANCZOS)
        scaled.append(card)

    step = round(scaled[0].width * visible_fraction)
    total = step * (len(scaled) - 1) + scaled[-1].width

    canvas = Image.new("RGBA", (total, height), (0, 0, 0, 0))
    for index, card in enumerate(scaled):
        shadowed = with_shadow(card)
        canvas.alpha_composite(shadowed, (step * index - SHADOW_BLUR * 2,
                                          max(0, -SHADOW_BLUR * 2)))

    # Trim to the drawn area, then scale to the page's figure width.
    canvas = canvas.crop(canvas.getbbox())
    if canvas.width != FIGURE_WIDTH:
        height = round(canvas.height * FIGURE_WIDTH / canvas.width)
        canvas = canvas.resize((FIGURE_WIDTH, height), Image.LANCZOS)

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, format="PNG", optimize=True)
    canvas.save(destination.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return destination


def side_by_side(sources: list[Path], destination: Path, gap: int = 34) -> Path:
    """Two captures next to each other, same size, nothing overlapping."""
    cards = [rounded(without_chrome(Image.open(path).convert("RGBA"))) for path in sources]
    height = min(card.height for card in cards)
    scaled = []
    for card in cards:
        if card.height != height:
            width = round(card.width * height / card.height)
            card = card.resize((width, height), Image.LANCZOS)
        scaled.append(card)

    total = sum(card.width for card in scaled) + gap * (len(scaled) - 1)
    canvas = Image.new("RGBA", (total, height), (0, 0, 0, 0))
    offset = 0
    for card in scaled:
        canvas.alpha_composite(card, (offset, 0))
        offset += card.width + gap

    if canvas.width != FIGURE_WIDTH:
        height = round(canvas.height * FIGURE_WIDTH / canvas.width)
        canvas = canvas.resize((FIGURE_WIDTH, height), Image.LANCZOS)

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, format="PNG", optimize=True)
    canvas.save(destination.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return destination


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
    from PIL import ImageFilter

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
        resized = img.resize((w, base_height), Image.LANCZOS)
        cards.append(rounded(resized, radius=CORNER_RADIUS))

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

    for card, (ox, oy) in zip(cards, offsets):
        shadow_canvas = Image.new("RGBA", (card.width + pad * 2, card.height + pad * 2), (0, 0, 0, 0))
        shape = Image.new("L", card.size, 0)
        ImageDraw.Draw(shape).rounded_rectangle(
            [(0, 0), (card.width - 1, card.height - 1)], radius=CORNER_RADIUS, fill=105
        )
        shadow_canvas.paste((0, 0, 0, 105), (pad, pad + 8), shape)
        shadow_canvas = shadow_canvas.filter(ImageFilter.GaussianBlur(SHADOW_BLUR / 2))

        canvas.alpha_composite(shadow_canvas, (ox, oy))
        canvas.alpha_composite(card, (ox + pad, oy + pad))

    bbox = canvas.getbbox()
    if bbox:
        canvas = canvas.crop(bbox)

    if canvas.width != figure_width:
        h = round(canvas.height * figure_width / canvas.width)
        canvas = canvas.resize((figure_width, h), Image.LANCZOS)

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, format="PNG", optimize=True)
    canvas.save(destination.with_suffix(".webp"), format="WEBP", quality=88, method=6)
    return destination

