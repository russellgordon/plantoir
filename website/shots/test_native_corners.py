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
sys.path.insert(1, str(HERE.parent))  # build.py, for the deploy's own check

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


# A mask drawn at a window's REAL radius cannot be told from the real curve
# by pixels. Any picture known to carry one goes here, with what it is owed,
# and the test below reports it rather than letting the pass read as "clean".
# Empty since 2026-09-27, when `schedule` was retaken from a native capture
# of Notification Center's window.
DRAWN_BUT_NOT_DETECTABLE: dict[str, str] = {}


class PicturesStillOwed(unittest.TestCase):

    def test_no_picture_is_known_to_carry_a_drawn_corner(self):
        self.assertEqual(DRAWN_BUT_NOT_DETECTABLE, {})


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


class TheDeployRefuses(unittest.TestCase):
    """`build.py --deploy` asks the same question before publishing (#375),
    because the failure this rule exists for was a deploy."""

    def test_the_committed_pictures_let_the_deploy_through(self):
        import build
        self.assertIsNone(build.native_corners_refusal())

    def test_a_square_picture_on_a_page_stops_the_deploy(self):
        import json
        import shutil
        import tempfile
        import build
        with tempfile.TemporaryDirectory() as scratch:
            website = Path(scratch) / "website"
            image_dir = Path(scratch) / "img"
            (website / "pages").mkdir(parents=True)
            image_dir.mkdir()
            manifest = {"shots": [{"id": "courses", "alt": "a"}]}
            (website / "shots.json").write_text(json.dumps(manifest), encoding="utf-8")
            (website / "pages" / "index.html").write_text("{{shot:courses}}", encoding="utf-8")
            real = REPO / "site" / "img" / "courses-light.png"
            if not real.exists():
                self.skipTest("no courses-light.png to build the test from")
            shutil.copy(real, image_dir / "courses-light.png")
            shutil.copy(real, image_dir / "courses-dark.png")
            self.assertIsNone(build.native_corners_refusal(website, image_dir))
            with Image.open(real) as opened:
                Image.new("RGBA", opened.size, (240, 240, 240, 255)).save(image_dir / "courses-dark.png")
            refusal = build.native_corners_refusal(website, image_dir)
            self.assertIsNotNone(refusal)
            self.assertIn("courses-dark.png", refusal)
            self.assertNotIn("courses-light.png", refusal)


if __name__ == "__main__":
    unittest.main()
