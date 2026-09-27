#!/usr/bin/env python3
"""Write Plantoir-Beta.icon: the real app icon with a "BETA" ribbon across it.

The DEBUG build wears this icon so the development copy in the Dock can be
told apart, at a glance, from the released Plantoir used for real teaching.
The Release configuration never sees it: project.yml names it as the app icon
for Debug only and excludes it from Release builds altogether, so what
publish.sh ships is byte-for-byte the icon it always was.

Everything except the ribbon is COPIED from Plantoir.icon, never redrawn, so
editing the real icon in Icon Composer and re-running this script is the whole
of keeping the two in step:

    python3 mac-app/make-beta-icon.py

`BetaIconTests` fails when Plantoir.icon has changed and this has not been
re-run, which is how the two are kept from drifting apart quietly.

The ribbon is an SVG layer drawn here, with the letters written as PATHS
rather than as <text>: an SVG handed to the icon compiler has no font to rely
on, and block letters built from a few shapes stay legible at the 64-pixel
size the Dock actually shows. Standard library only, deliberately.
"""

import json
import shutil
from pathlib import Path

MAC_APP = Path(__file__).resolve().parent
SOURCE = MAC_APP / "Plantoir.icon"
TARGET = MAC_APP / "Plantoir-Beta.icon"
RIBBON_FILE = "beta-ribbon.svg"

# The icon canvas is 1024 x 1024. The band runs the full width, low enough to
# leave the top of the plant showing and high enough to clear the rounded
# bottom corners.
CANVAS = 1024
BAND_TOP = 676
BAND_HEIGHT = 244
BAND_COLOUR = "#D9480F"
LETTER_COLOUR = "#FFFFFF"

# Letters are drawn on a grid 100 units tall; CAP_HEIGHT scales them up.
CAP_HEIGHT = 172
LETTER_GAP = 16

# Each letter: (advance width, SVG path data in the 100-unit grid).
# Strokes are about 22 units thick, so they survive being shrunk to 8 pixels.
LETTERS = {
    "B": (
        70,
        "M0 0H42C58 0 66 10 66 25C66 36 60 43 52 47C64 50 70 60 70 72"
        "C70 90 60 100 44 100H0Z"
        "M22 19H39C44 19 46 23 46 28C46 34 43 38 38 38H22Z"
        "M22 56H42C48 56 50 61 50 67C50 75 46 81 41 81H22Z",
    ),
    "E": (
        62,
        "M0 0H62V21H22V39H56V59H22V79H62V100H0Z",
    ),
    "T": (
        70,
        "M0 0H70V21H46V100H24V21H0Z",
    ),
    "A": (
        74,
        "M0 100L26 0H48L74 100H52L46.8 80H27.2L22 100Z"
        "M31.9 62H42.1L37 42.3Z",
    ),
}


def ribbon_svg(word: str) -> str:
    """The band and its word, as one SVG the size of the icon canvas."""
    scale: float = CAP_HEIGHT / 100

    total_width: float = 0
    for index, letter in enumerate(word):
        total_width += LETTERS[letter][0]
        if index < len(word) - 1:
            total_width += LETTER_GAP
    total_width_on_canvas: float = total_width * scale

    left: float = (CANVAS - total_width_on_canvas) / 2
    top: float = BAND_TOP + (BAND_HEIGHT - CAP_HEIGHT) / 2

    letter_paths: list[str] = []
    cursor: float = 0
    for letter in word:
        advance, path_data = LETTERS[letter]
        x: float = left + cursor * scale
        letter_paths.append(
            f'<path transform="translate({x:.2f} {top:.2f}) scale({scale:.4f})" '
            f'fill="{LETTER_COLOUR}" fill-rule="evenodd" d="{path_data}"/>'
        )
        cursor += advance + LETTER_GAP

    lines: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">',
        f'<rect x="0" y="{BAND_TOP}" width="{CANVAS}" height="{BAND_HEIGHT}" fill="{BAND_COLOUR}"/>',
    ]
    for path in letter_paths:
        lines.append(path)
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def ribbon_group() -> dict:
    """The ribbon as its own group, on top: flat, opaque, unshadowed."""
    return {
        "layers": [
            {
                "glass": False,
                "hidden": False,
                "image-name": RIBBON_FILE,
                "name": "beta-ribbon",
                "position": {"scale": 1, "translation-in-points": [0, 0]},
            }
        ],
        "shadow": {"kind": "none", "opacity": 0},
        "translucency": {"enabled": False, "value": 0},
    }


def main() -> None:
    if TARGET.exists():
        shutil.rmtree(TARGET)
    shutil.copytree(SOURCE, TARGET)

    (TARGET / "Assets" / RIBBON_FILE).write_text(ribbon_svg("BETA"), encoding="utf-8")

    document: dict = json.loads((SOURCE / "icon.json").read_text(encoding="utf-8"))
    # Icon Composer lists groups front to back, so the ribbon goes FIRST.
    document["groups"].insert(0, ribbon_group())
    (TARGET / "icon.json").write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {TARGET.relative_to(MAC_APP.parent)}")


if __name__ == "__main__":
    main()
