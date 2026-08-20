#!/usr/bin/env python3
"""Draw the Plantoir brand images from the Icon Composer source.

One source of truth for every image that carries the Plantoir mark: the social
card served at plantoir.app, the Bluesky and Instagram profile photos, the
Bluesky profile banner, and the favicon every class site wears in the browser
tab. All of them are drawn from ``mac-app/Plantoir.icon`` and the palette below,
so the mark can never drift between them.

The plant is rasterised from the *actual* SVG path in the .icon bundle rather
than composited from a pre-rendered PNG. That costs us a small path parser (see
``Path``) and buys us the guarantee that editing the icon in Icon Composer and
re-running this script is enough -- there is no second copy of the artwork to
forget about.

Usage::

    python scripts/brand_images.py                 # -> brand/ and support/favicon/
    python scripts/brand_images.py --install-card  # also -> site/social-card.png

``--install-card`` overwrites the deployed og:image. Look at the output first;
it will not be byte-identical to a hand-made card.

The favicon set in ``support/favicon/`` is written on every run rather than
behind a flag, because it SHIPS: the Docker image bakes ``support/`` and
``scripts/build_site.py`` copies the set into every site it builds. Leaving it
behind a flag is how it would come to disagree with the app icon.

Requires Pillow, which the Docker image already installs (see Dockerfile).
Unlike scripts/social_card.py this is a release-time tool, not part of the
course build -- nothing in the Quartz pipeline calls it.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

REPO = Path(__file__).resolve().parent.parent
ICON_DIR = REPO / "mac-app" / "Plantoir.icon"
FONTS = REPO / "support" / "fonts"
FAVICON_DIR = REPO / "support" / "favicon"


# ---------------------------------------------------------------------------
# Palette
#
# These mirror the CSS custom properties in site/index.html (:root). If you
# change one there, change it here. The two greens are NOT interchangeable:
# --green-deep is the wordmark, --green is the rule, the link and the mark.
# ---------------------------------------------------------------------------

PAPER = (0xF7, 0xEE, 0xDA)        # --paper       card + banner background
INK_SOFT = (0x6E, 0x68, 0x58)     # --ink-soft    tagline
GREEN = (0x3E, 0x8C, 0x26)        # --green       rule, link, tagline verbs
GREEN_DEEP = (0x2D, 0x66, 0x20)   # --green-deep  wordmark

# Sampled from the Icon Composer export (Plantoir-iOS-Default-1024x1024@1x.png).
# The plant reads #3E8D26 rather than the pure green in icon.json because the
# layer's translucency blends it into the background; and the background ramp
# runs the full height of the canvas, not to the 0.7 stop the JSON implies.
# Both are rendering behaviours we cannot recover from the JSON alone.
GLYPH = (0x3E, 0x8D, 0x26)
ICON_TOP = (0xFE, 0xFC, 0xEE)
ICON_BOTTOM = (0xD3, 0xC0, 0x99)

# The tile on the social card is a lighter crop of that same ramp.
TILE_TOP = (0xF9, 0xF5, 0xE5)
TILE_BOTTOM = (0xD7, 0xC6, 0xA2)

WORDMARK = "Plantoir"
TAGLINE_CARD = ["Turns Markdown notes into a fast,", "searchable class website you own."]
DOMAIN = "plantoir.app"

# Banner tagline. Each line is a list of (text, emphasised?) runs; emphasised
# runs are set in --green semibold so the three verbs carry the line.
TAGLINE_BANNER = [
    [("Plan", True), (" the plot. ", False), ("Plant", True), (" your notes.", False)],
    [("Grow", True), (" a class website you own.", False)],
]

SUPERSAMPLE = 4  # the path is filled at 1-bit, so we oversample for smooth edges


# ---------------------------------------------------------------------------
# SVG path -> polygons
# ---------------------------------------------------------------------------

_TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?")


class SvgPath:
    """A minimal SVG path parser that flattens to polylines.

    Supports every command the Phosphor icons use (M L H V C S Q T A Z, both
    cases). Curves and arcs are sampled rather than kept analytic, because the
    only thing we do with the result is fill it.
    """

    def __init__(self, d: str, samples: int = 24):
        self.samples = samples
        self.subpaths: list[list[tuple[float, float]]] = []
        self._parse(d)

    # -- helpers ----------------------------------------------------------
    def _cubic(self, p0, p1, p2, p3):
        pts = []
        for i in range(1, self.samples + 1):
            t = i / self.samples
            u = 1 - t
            pts.append((
                u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
            ))
        return pts

    def _quad(self, p0, p1, p2):
        pts = []
        for i in range(1, self.samples + 1):
            t = i / self.samples
            u = 1 - t
            pts.append((
                u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1],
            ))
        return pts

    def _arc(self, p0, rx, ry, rot, large, sweep, p1):
        """Endpoint -> centre parameterisation (SVG spec F.6.5), then sample."""
        if rx == 0 or ry == 0 or p0 == p1:
            return [p1]
        rx, ry = abs(rx), abs(ry)
        phi = math.radians(rot)
        cos_p, sin_p = math.cos(phi), math.sin(phi)

        dx2, dy2 = (p0[0] - p1[0]) / 2.0, (p0[1] - p1[1]) / 2.0
        x1 = cos_p * dx2 + sin_p * dy2
        y1 = -sin_p * dx2 + cos_p * dy2

        # Scale up the radii if they are too small to span the endpoints.
        lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1:
            s = math.sqrt(lam)
            rx, ry = rx * s, ry * s

        num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        co = math.sqrt(max(0.0, num / den)) if den else 0.0
        if large == sweep:
            co = -co
        cx1 = co * rx * y1 / ry
        cy1 = -co * ry * x1 / rx

        cx = cos_p * cx1 - sin_p * cy1 + (p0[0] + p1[0]) / 2.0
        cy = sin_p * cx1 + cos_p * cy1 + (p0[1] + p1[1]) / 2.0

        def angle(ux, uy, vx, vy):
            dot = ux * vx + uy * vy
            n = math.hypot(ux, uy) * math.hypot(vx, vy)
            if n == 0:
                return 0.0
            a = math.acos(max(-1.0, min(1.0, dot / n)))
            return -a if (ux * vy - uy * vx) < 0 else a

        theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if not sweep and delta > 0:
            delta -= 2 * math.pi
        elif sweep and delta < 0:
            delta += 2 * math.pi

        n = max(4, int(self.samples * abs(delta) / math.pi))
        pts = []
        for i in range(1, n + 1):
            t = theta + delta * i / n
            pts.append((
                cos_p * rx * math.cos(t) - sin_p * ry * math.sin(t) + cx,
                sin_p * rx * math.cos(t) + cos_p * ry * math.sin(t) + cy,
            ))
        return pts

    # -- parser -----------------------------------------------------------
    def _parse(self, d: str):
        toks = _TOKEN.findall(d)
        i = 0
        cur = (0.0, 0.0)
        start = (0.0, 0.0)
        sub: list[tuple[float, float]] = []
        cmd = ""
        prev_cubic_ctrl = None
        prev_quad_ctrl = None

        def num():
            nonlocal i
            v = float(toks[i])
            i += 1
            return v

        def flush():
            nonlocal sub
            if len(sub) > 2:
                self.subpaths.append(sub)
            sub = []

        while i < len(toks):
            if re.match(r"^[A-Za-z]$", toks[i]):
                cmd = toks[i]
                i += 1
                if cmd in "Zz":
                    flush()
                    cur = start
                    continue
            rel = cmd.islower()
            c = cmd.upper()
            ox, oy = cur if rel else (0.0, 0.0)

            if c == "M":
                x, y = num() + ox, num() + oy
                flush()
                cur = start = (x, y)
                sub = [cur]
                cmd = "l" if rel else "L"  # subsequent pairs are implicit lineto
            elif c == "L":
                cur = (num() + ox, num() + oy)
                sub.append(cur)
            elif c == "H":
                cur = (num() + ox, cur[1])
                sub.append(cur)
            elif c == "V":
                cur = (cur[0], num() + oy)
                sub.append(cur)
            elif c in ("C", "S"):
                if c == "C":
                    c1 = (num() + ox, num() + oy)
                else:
                    c1 = (2 * cur[0] - prev_cubic_ctrl[0], 2 * cur[1] - prev_cubic_ctrl[1]) \
                        if prev_cubic_ctrl else cur
                c2 = (num() + ox, num() + oy)
                end = (num() + ox, num() + oy)
                sub.extend(self._cubic(cur, c1, c2, end))
                prev_cubic_ctrl, cur = c2, end
                prev_quad_ctrl = None
                continue
            elif c in ("Q", "T"):
                if c == "Q":
                    c1 = (num() + ox, num() + oy)
                else:
                    c1 = (2 * cur[0] - prev_quad_ctrl[0], 2 * cur[1] - prev_quad_ctrl[1]) \
                        if prev_quad_ctrl else cur
                end = (num() + ox, num() + oy)
                sub.extend(self._quad(cur, c1, end))
                prev_quad_ctrl, cur = c1, end
                prev_cubic_ctrl = None
                continue
            elif c == "A":
                rx, ry, rot = num(), num(), num()
                large, sweep = int(num()), int(num())
                end = (num() + ox, num() + oy)
                sub.extend(self._arc(cur, rx, ry, rot, large, sweep, end))
                cur = end
            else:
                i += 1  # unknown command; skip a token rather than spin
                continue
            prev_cubic_ctrl = prev_quad_ctrl = None
        flush()


def _viewbox(svg_text: str) -> tuple[float, float]:
    m = re.search(r'viewBox="([\d.\-\s]+)"', svg_text)
    if not m:
        return 256.0, 256.0
    parts = [float(v) for v in m.group(1).split()]
    return parts[2], parts[3]


def load_glyph_path() -> tuple[SvgPath, float]:
    """Return the plant path and the side of its (square) viewBox."""
    d, w = load_glyph_data()
    return SvgPath(d), w


def load_glyph_data() -> tuple[str, float]:
    """Return the plant's raw SVG path data and the side of its viewBox."""
    svg = (ICON_DIR / "Assets" / "plant.svg").read_text(encoding="utf-8")
    d = re.search(r'\sd="([^"]+)"', svg).group(1)
    w, _ = _viewbox(svg)
    return d, w


def load_glyph_silhouette_data() -> tuple[str, float]:
    """The mark's OUTER contour only, as SVG path data.

    plant.svg is three subpaths in this order: the silhouette of the whole
    plant, then the counter (the open middle) of each leaf. Dropping the last
    two and filling what is left gives the same mark in a solid weight -- the
    same relationship Phosphor's own "regular" and "fill" weights have, and the
    reason the favicon can be a fill without being a different drawing.
    """
    d, w = load_glyph_data()
    subpaths = [part for part in re.split(r"(?=[Mm])", d) if part.strip()]
    return subpaths[0], w


def glyph_ink_box(counters: bool = True) -> tuple[float, float, float, float]:
    """(x, y, width, height) of the mark's actual ink inside its viewBox.

    The viewBox is square but the plant is not: it fills 240x192 of the 256,
    sitting low and hard against the left edge. Centring the VIEWBOX -- which
    is what the app icon does -- therefore leaves the mark visibly low. At 16
    pixels that is a wasted row, so the favicon centres this box instead.
    """
    path, _ = load_glyph_path()
    subpaths = path.subpaths if counters else path.subpaths[:1]
    xs: list[float] = []
    ys: list[float] = []
    for sp in subpaths:
        for x, y in sp:
            xs.append(x)
            ys.append(y)
    return min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)


def render_glyph(px: float, color, bold_units: float = 0.0, counters: bool = True):
    """Rasterise the plant at ``px`` wide, anti-aliased, as RGBA.

    ``bold_units`` strokes the outline in the fill colour, in viewBox units, to
    thicken the regular-weight glyph for small display sizes. The fill uses the
    even-odd rule (XOR of the subpath masks), which is what keeps the leaf
    counters open.

    ``counters=False`` drops the two counter subpaths, giving the solid weight
    of the same mark -- see ``load_glyph_silhouette_data``.
    """
    path, vb = load_glyph_path()
    subpaths = path.subpaths if counters else path.subpaths[:1]
    ss = SUPERSAMPLE
    side = int(round(px * ss))
    scale = side / vb

    fill = Image.new("1", (side, side), 0)
    for sp in subpaths:
        layer = Image.new("1", (side, side), 0)
        ImageDraw.Draw(layer).polygon([(x * scale, y * scale) for x, y in sp], fill=1)
        fill = ImageChops.logical_xor(fill, layer)

    if bold_units > 0:
        stroke = Image.new("1", (side, side), 0)
        sd = ImageDraw.Draw(stroke)
        w = max(1, int(round(bold_units * scale)))
        for sp in subpaths:
            pts = [(x * scale, y * scale) for x, y in sp]
            sd.line(pts + [pts[0]], fill=1, width=w, joint="curve")
        fill = ImageChops.logical_or(fill, stroke)

    mask = fill.convert("L").resize((int(round(px)), int(round(px))), Image.LANCZOS)
    out = Image.new("RGBA", mask.size, color + (0,))
    out.putalpha(mask)
    return out


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------

def vertical_gradient(size, top, bottom) -> Image.Image:
    w, h = size
    ramp = Image.new("RGB", (1, h))
    px = ramp.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(int(round(a + (b - a) * t)) for a, b in zip(top, bottom))
    return ramp.resize((w, h), Image.NEAREST)


def rounded_mask(size, radius) -> Image.Image:
    ss = 4
    w, h = size
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * ss - 1, h * ss - 1], radius=radius * ss, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def paste_with_shadow(base, layer, xy, dy, blur, opacity):
    """Composite ``layer`` onto ``base`` under a soft neutral drop shadow."""
    if opacity > 0:
        shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
        solid = Image.new("RGBA", layer.size, (0, 0, 0, int(round(255 * opacity))))
        solid.putalpha(ImageChops.multiply(solid.split()[3], layer.split()[3]))
        shadow.paste(solid, (xy[0], xy[1] + dy), solid)
        base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    base.alpha_composite(layer, xy)


def font(weight: str, size: float) -> ImageFont.FreeTypeFont:
    """Poppins Regular or Medium.

    The brand uses exactly these two weights -- no SemiBold anywhere. That is
    measured, not assumed: matching the original card's ink coverage pins the
    wordmark to Medium 96 and the domain line to Medium 26. (The site's CSS
    sets h1 to weight 600, which is misleading here; the card is its own
    artifact and was not rendered from that stylesheet.)
    """
    files = {"regular": "Poppins.ttf", "medium": "Poppins-Medium.ttf"}
    p = FONTS / files[weight]
    if not p.is_file():
        sys.exit(
            f"Missing {p.name} in support/fonts/.\n"
            "The bundled Poppins.ttf is Regular only; the wordmark, the domain\n"
            "line and the banner's emphasised verbs all need Medium. Add it from\n"
            "the Google Fonts Poppins family (OFL, same licence as the fonts\n"
            "already here)."
        )
    return ImageFont.truetype(str(p), size)


def draw_runs(draw, x, y, runs, anchor="ls"):
    """Draw (text, font, colour) runs on one baseline. Returns total width."""
    total = sum(f.getlength(t) for t, f, _ in runs)
    cx = x - total / 2 if anchor == "ms" else x
    for text, f, color in runs:
        draw.text((cx, y), text, font=f, fill=color, anchor="ls")
        cx += f.getlength(text)
    return total


def icon_tile(side, radius_frac=0.295):
    """The rounded app-icon tile: ramp, mark, and the mark's own shadow.

    ``radius_frac`` is an empirical best fit to the original card, not the
    icon's true geometry. Apple's tile is a superellipse; approximating it with
    a circular-arc rounded rectangle needs a noticeably larger radius than the
    ~0.2258 a squircle nominally corresponds to. Fitting it properly would mean
    drawing the superellipse -- worth doing if the tile ever needs to be exact.
    """
    tile = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    bg = vertical_gradient((side, side), TILE_TOP, TILE_BOTTOM).convert("RGBA")
    bg.putalpha(rounded_mask((side, side), int(round(side * radius_frac))))
    tile.alpha_composite(bg)

    g = side * 0.703  # the plant layer's own scale in icon.json (22.5 x 32pt / 1024)
    glyph = render_glyph(g, GLYPH)
    off = int((side - g) / 2)  # floor, which lands the mark exactly as the original card has it
    paste_with_shadow(tile, glyph, (off, off), dy=max(1, int(side * 0.008)),
                      blur=side * 0.009, opacity=0.30)
    return tile


# ---------------------------------------------------------------------------
# The images
# ---------------------------------------------------------------------------

def build_social_card() -> Image.Image:
    """1200x630 og:image. Geometry measured from the original site/social-card.png."""
    W, H = 1200, 630
    img = Image.new("RGBA", (W, H), PAPER + (255,))
    d = ImageDraw.Draw(img)

    tile = icon_tile(260)
    paste_with_shadow(img, tile, (108, 185), dy=10, blur=14, opacity=0.20)

    x = 444
    d.text((x, 260), WORDMARK, font=font("medium", 96), fill=GREEN_DEEP, anchor="ls")
    ft = font("regular", 33)
    for i, line in enumerate(TAGLINE_CARD):
        d.text((x, 322 + i * 46), line, font=ft, fill=INK_SOFT, anchor="ls")
    d.text((x, 431), DOMAIN, font=font("medium", 26), fill=GREEN, anchor="ls")

    d.rectangle([0, 622, W, H], fill=GREEN)
    return img.convert("RGB")


def build_avatar(side: int, glyph_frac: float, bold_units: float,
                 shadow: tuple[int, float, float]) -> Image.Image:
    """Square, full-bleed profile photo. Both platforms crop it to a circle."""
    img = vertical_gradient((side, side), ICON_TOP, ICON_BOTTOM).convert("RGBA")
    g = side * glyph_frac
    glyph = render_glyph(g, GLYPH, bold_units=bold_units)
    off = int(round((side - g) / 2))
    dy, blur, opacity = shadow
    paste_with_shadow(img, glyph, (off, off), dy=dy, blur=blur, opacity=opacity)
    return img.convert("RGB")


def build_banner() -> Image.Image:
    """1500x500 (3:1) Bluesky banner.

    No mark: Bluesky overlays the avatar at bottom-left (about x 40-250,
    y 395-500 at this size) and it already carries the plant. Drawing it here
    too reads as a duplicate. The type is centred so it survives the mobile
    crop and stays clear of that corner.
    """
    W, H = 1500, 500
    img = Image.new("RGBA", (W, H), PAPER + (255,))
    d = ImageDraw.Draw(img)

    f_word = font("medium", 96)
    f_tag = font("regular", 40)
    f_verb = font("medium", 40)
    f_link = font("medium", 30)

    asc, desc = 0.73, 0.21  # Poppins ascender / descender as a fraction of em
    gap_tag, line_h, gap_link = 28, 56, 30

    top_to_first = asc * 96
    block = (top_to_first + gap_tag + asc * 40 + line_h + gap_link + asc * 30 + desc * 30)
    y = (H - block) / 2 - 13 + top_to_first  # lifted clear of the rule

    d.text((W / 2, y), WORDMARK, font=f_word, fill=GREEN_DEEP, anchor="ms")
    y += gap_tag + asc * 40
    for i, line in enumerate(TAGLINE_BANNER):
        runs = [(t, f_verb if em else f_tag, GREEN if em else INK_SOFT) for t, em in line]
        draw_runs(d, W / 2, y + i * line_h, runs, anchor="ms")
    y += line_h + gap_link + asc * 30
    d.text((W / 2, y), DOMAIN, font=f_link, fill=GREEN, anchor="ms")

    d.rectangle([0, H - 11, W, H], fill=GREEN)
    return img.convert("RGB")


# ---------------------------------------------------------------------------
# The favicon
#
# Every site Plantoir builds used to wear Quartz's own logo in the browser tab,
# because Quartz ships quartz/static/icon.png and its Head links it. This set
# replaces it, and it is a DIFFERENT drawing of the same mark for a reason
# worth keeping:
#
#   * The app icon is the regular weight -- an outline plant with an open
#     counter and a midrib inside each leaf. Rendered at 16 pixels those
#     interior lines land on top of the outline and the mark turns to mush; it
#     was measured by rendering it and looking, not assumed.
#   * The solid weight survives it. At 16 it still reads as two leaves and a
#     stem, and at 180 it is a clean fill of the same silhouette.
#   * REJECTED: keeping the outline for the large sizes and using the solid one
#     only for 16 and 24 inside the .ico. It would have matched the Dock icon
#     more closely at 180 -- but browsers that support icon.svg render THAT at
#     whatever size they like, so the outline would have come back at 16 for
#     most of Chrome and Firefox. One mark at every size beats fidelity at the
#     one size nobody looks at.
#   * REJECTED: darkening the green for contrast. The brand green on the tile
#     is about 3:1, which is thin for a hairline stroke and ample for a solid
#     shape -- and the solid weight is what we ship.
#
# There is no drop shadow: at 16 pixels it is a grey smear round the mark, and
# it costs contrast exactly where there is least to spare.
# ---------------------------------------------------------------------------

# The mark's ink width as a fraction of the tile. The app icon's own value is
# 0.66 (0.703 of the viewBox, of which the ink is 240/256). A favicon is looked
# at small, where margin is wasted pixels, so it runs wider.
FAVICON_INK = 0.78

# Matches icon_tile()'s empirical fit rather than the 0.2237 the Windows .ico
# uses, so the favicon and the tile on plantoir.app's social card wear the same
# silhouette. At 16 pixels the two radii differ by less than a pixel anyway.
FAVICON_RADIUS_FRAC = 0.295

# What goes in the .ico. 16 is a Windows tab at 100% scaling, 32 is the same
# tab on any Retina Mac, 48 is what Windows uses for a desktop shortcut.
ICO_SIZES = (16, 32, 48)

# iOS masks apple-touch-icon.png with its own squircle, so this one is square
# and opaque -- rounded corners would be rounded twice and the transparency
# would show through as grey.
APPLE_TOUCH_SIDE = 180

# The general-purpose PNG. It replaces Quartz's icon.png so that nothing in a
# built site carries somebody else's logo, even unlinked.
ICON_PNG_SIDE = 512


def _hex(color) -> str:
    return "#%02X%02X%02X" % color


def favicon_tile(side: int, rounded: bool = True) -> Image.Image:
    """The favicon at one size: the icon's ramp, and the mark in solid weight."""
    tile = vertical_gradient((side, side), TILE_TOP, TILE_BOTTOM).convert("RGBA")
    if rounded:
        tile.putalpha(rounded_mask((side, side), int(round(side * FAVICON_RADIUS_FRAC))))

    _, vb = load_glyph_data()
    ink_x, ink_y, ink_w, ink_h = glyph_ink_box(counters=False)
    box = side * FAVICON_INK * vb / ink_w          # the viewBox side, in pixels
    glyph = render_glyph(box, GLYPH, counters=False)
    scale = box / vb
    off_x = int(round(side / 2 - (ink_x + ink_w / 2) * scale))
    off_y = int(round(side / 2 - (ink_y + ink_h / 2) * scale))
    tile.alpha_composite(glyph, (off_x, off_y))
    return tile


def favicon_svg() -> str:
    """The same tile as SVG, which is what every current browser prefers.

    Written from the path data rather than traced from a bitmap, so it stays
    the icon's own artwork at any size a browser asks for.
    """
    d, vb = load_glyph_silhouette_data()
    ink_x, ink_y, ink_w, ink_h = glyph_ink_box(counters=False)
    side = 256.0
    scale = side * FAVICON_INK / ink_w
    tx = side / 2 - (ink_x + ink_w / 2) * scale
    ty = side / 2 - (ink_y + ink_h / 2) * scale
    radius = side * FAVICON_RADIUS_FRAC
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{side:g}" height="{side:g}"'
        f' viewBox="0 0 {side:g} {side:g}">\n'
        f'<!-- Plantoir. Generated by scripts/brand_images.py from'
        f' mac-app/Plantoir.icon - do not hand-edit. -->\n'
        f'<defs><linearGradient id="plantoir-tile" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{_hex(TILE_TOP)}"/>'
        f'<stop offset="1" stop-color="{_hex(TILE_BOTTOM)}"/></linearGradient></defs>\n'
        f'<rect width="{side:g}" height="{side:g}" rx="{radius:g}" ry="{radius:g}"'
        f' fill="url(#plantoir-tile)"/>\n'
        f'<g transform="translate({tx:.4f} {ty:.4f}) scale({scale:.6f})">'
        f'<path fill="{_hex(GLYPH)}" d="{d}"/></g>\n'
        f'</svg>\n'
    )


def write_favicons(out: Path) -> list[str]:
    """Write the whole favicon set. Returns one description line per file.

    Every size in the .ico is drawn at that size rather than downsampled from
    one big one: the mark is redrawn from the path at 16, so the anti-aliasing
    is decided by the renderer instead of by a resize.
    """
    out.mkdir(parents=True, exist_ok=True)
    written: list[str] = []

    svg_path = out / "icon.svg"
    svg_path.write_text(favicon_svg(), encoding="utf-8")
    written.append(f"icon.svg  vector  {svg_path.stat().st_size} bytes")

    # Largest first: Pillow skips any requested size bigger than the image it
    # is saving FROM, so handing it the 16 first silently produced a one-entry
    # .ico that looked fine in every viewer and was missing 32 and 48.
    frames = [favicon_tile(size) for size in sorted(ICO_SIZES, reverse=True)]
    ico_path = out / "favicon.ico"
    frames[0].save(ico_path, "ICO",
                   sizes=[(size, size) for size in ICO_SIZES],
                   append_images=frames[1:],
                   # BMP entries, not PNG-compressed ones. It costs about 13 KB
                   # and buys the one thing a favicon cannot afford to get
                   # wrong: being readable by everything, including the older
                   # Safari that is exactly why the .ico is here at all.
                   bitmap_format="bmp")
    sizes_text = ", ".join(str(size) for size in ICO_SIZES)
    written.append(f"favicon.ico  {sizes_text}  {ico_path.stat().st_size} bytes")

    apple = favicon_tile(APPLE_TOUCH_SIDE, rounded=False).convert("RGB")
    apple_path = out / "apple-touch-icon.png"
    apple.save(apple_path, "PNG", optimize=True)
    written.append(f"apple-touch-icon.png  {APPLE_TOUCH_SIDE}x{APPLE_TOUCH_SIDE}"
                   f"  {apple_path.stat().st_size // 1024} KB")

    png = favicon_tile(ICON_PNG_SIDE)
    png_path = out / "icon.png"
    png.save(png_path, "PNG", optimize=True)
    written.append(f"icon.png  {ICON_PNG_SIDE}x{ICON_PNG_SIDE}"
                   f"  {png_path.stat().st_size // 1024} KB")

    return written


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Draw the Plantoir brand images.")
    ap.add_argument("--out", default=str(REPO / "brand"), help="output directory (default: brand/)")
    ap.add_argument("--install-card", action="store_true",
                    help="also overwrite site/social-card.png (the deployed og:image)")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    if not ICON_DIR.is_dir():
        sys.exit(f"Cannot find the icon source at {ICON_DIR}")

    images = {
        "social-card.png": build_social_card(),
        # Bluesky renders large; keep the mark at the icon's own scale.
        "avatar-bluesky.png": build_avatar(1024, 0.703, 0.0, (8, 9, 0.30)),
        # Instagram stores at 320 and shows 32px in feed, so the mark runs a
        # little larger and the strokes are thickened to survive the downsample.
        "avatar-instagram.png": build_avatar(1080, 0.723, 3.0, (7, 8, 0.28)),
        "banner-bluesky.png": build_banner(),
    }

    for name, img in images.items():
        p = out / name
        img.save(p, "PNG", optimize=True)
        print(f"  {p.relative_to(REPO) if p.is_relative_to(REPO) else p}  "
              f"{img.width}x{img.height}  {p.stat().st_size // 1024} KB")

    favicons = write_favicons(FAVICON_DIR)
    print(f"\n  {FAVICON_DIR.relative_to(REPO)}/ -- the icon every built site wears:")
    for line in favicons:
        print(f"    {line}")

    if args.install_card:
        dest = REPO / "site" / "social-card.png"
        images["social-card.png"].save(dest, "PNG", optimize=True)
        print(f"\n  installed -> {dest.relative_to(REPO)}  (deployed og:image)")
    else:
        print("\n  social-card.png written to the output directory only.")
        print("  Compare it against site/social-card.png, then re-run with")
        print("  --install-card if you want it deployed.")


if __name__ == "__main__":
    main()
