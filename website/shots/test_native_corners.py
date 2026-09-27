#!/usr/bin/env python3
"""Every picture on plantoir.app keeps its window's own corners.

Russell's rule, 2026-09-27: the pictures are made ONLY with macOS's own window
capture (`screencapture -x -o -l <window id>`, the Option-click capture),
kept whole. No crop through a window, no corner painted back on, no rounded
mask drawn by hand. This test opens every picture the pages show a Mac
visitor — read from `shots.json` and the pages, both PNG and WebP — and fails
on any corner that is square (a screen grab or a crop) or tighter than any
real macOS window (a drawn mask of the kind composite.py used). A mask drawn
at a window's REAL radius cannot be told from the real curve by pixels, so
this is a guard, not a proof: DRAWN_BUT_NOT_DETECTABLE names any such
picture still on the site, and the rule itself lives in the code that no
longer draws. How a corner is read, and the
measurements behind the thresholds: `corners.py`.

The Windows pictures (`-windows-`) are not judged here: they are taken on
Windows, whose own harness owes the same rule (see website/SCREENSHOTS.md).

Stdlib and Pillow only; no app, no network.

    python3 website/shots/test_native_corners.py
"""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))

from PIL import Image, ImageDraw  # noqa: E402

import corners  # noqa: E402

# Pictures the pages show that are known to be wrong and are somebody's work
# in flight, each with who owns it. A gap listed here must STILL be failing:
# once it is fixed, the test says so and it comes off the list.
NAMED_GAPS: dict[str, str] = {}


class CommittedPictures(unittest.TestCase):

    def test_every_picture_the_pages_show_has_real_window_corners(self):
        pictures = corners.images_the_pages_show(REPO / "website", REPO / "site" / "img")
        self.assertTrue(pictures, "no pictures found — is site/img/ there?")
        found: list[str] = []
        for picture in pictures:
            if picture.name in NAMED_GAPS:
                continue
            found.extend(corners.corner_problems(picture))
        self.assertEqual(found, [], "\n" + "\n".join(found))

    def test_every_named_gap_is_still_a_gap(self):
        for name, owner in NAMED_GAPS.items():
            picture = REPO / "site" / "img" / name
            self.assertTrue(corners.corner_problems(picture),
                            f"{name} passes now — take it off NAMED_GAPS ({owner})")


# Pictures known to carry a drawn corner that this reader CANNOT see, so the
# gate above passes them. Each is owed a retake; the list is here so that the
# pass above is not read as "clean".
#
# `schedule`: its banner was cut out of Notification Center's window and a
# rounded mask drawn over it at the banner's MEASURED radius (2e11471d). The
# ratio test cannot tell a mask drawn at the real radius from the real curve,
# and the banner sits inside the same shape as the window below it. The
# retake with the new crop (scenes.banner_in_window) was paused on
# 2026-09-27 when Russell was at the Mac.
DRAWN_BUT_NOT_DETECTABLE: dict[str, str] = {
    "schedule-light.png": "retake owed: capture.py --only notification-banner, then compose",
    "schedule-dark.png": "retake owed: capture.py --only notification-banner, then compose",
}


class PicturesStillOwed(unittest.TestCase):

    def test_no_picture_is_known_to_carry_a_drawn_corner(self):
        if DRAWN_BUT_NOT_DETECTABLE:
            owed = "; ".join(f"{name}: {why}" for name, why in DRAWN_BUT_NOT_DETECTABLE.items())
            self.skipTest(f"known drawn corners the reader cannot see — {owed}")


class TheCheckItself(unittest.TestCase):
    """The reader is proved against pictures made here, so a threshold that
    drifts cannot quietly pass everything."""

    def window_capture(self) -> Path:
        # A real capture from this repository: any single-window shot will do.
        for name in ("courses-light.png", "site-eng2d-light.png", "preview-light.png"):
            path = REPO / "site" / "img" / name
            if path.exists():
                return path
        self.skipTest("no single-window capture in site/img to test the reader against")

    def test_a_real_window_capture_passes(self):
        self.assertEqual(corners.corner_problems(self.window_capture()), [])

    def test_a_square_rectangle_fails(self):
        with Image.open(self.window_capture()) as opened:
            opaque = Image.new("RGBA", opened.size, (240, 240, 240, 255))
        path = Path(self.tmp) / "square.png"
        opaque.save(path)
        self.assertTrue(corners.corner_problems(path))

    def test_a_crop_with_a_small_drawn_mask_fails(self):
        with Image.open(self.window_capture()) as opened:
            image = opened.convert("RGBA")
        # What composite.py used to do: cut the toolbar off a 2x Safari
        # capture (1616 px tall once cut), paint 18 px corners on, and scale
        # the result to a third. Here at this picture's own size, in the same
        # proportion to its height.
        cut = image.crop((0, 100, image.width, image.height))
        radius = round(cut.height * 18 / 1616)
        mask = Image.new("L", cut.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (cut.width - 1, cut.height - 1)], radius=radius, fill=255)
        cut.putalpha(mask)
        small = cut.resize((cut.width // 2, cut.height // 2), Image.Resampling.LANCZOS)
        path = Path(self.tmp) / "drawn.png"
        small.save(path)
        self.assertTrue(corners.corner_problems(path))

    def test_a_picture_with_no_transparency_fails(self):
        path = Path(self.tmp) / "flat.webp"
        Image.new("RGB", (400, 300), (250, 250, 250)).save(path)
        self.assertTrue(corners.corner_problems(path))

    def setUp(self):
        import tempfile
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()


if __name__ == "__main__":
    unittest.main()
