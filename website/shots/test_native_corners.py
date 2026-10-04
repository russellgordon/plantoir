#!/usr/bin/env python3
"""Every picture on plantoir.app keeps its window's own corners.

Russell's rule, 2026-09-27: the pictures are made ONLY with macOS's own window
capture (`screencapture -x -l <window id>` since #434, shadow included —
`NaturalShadows` below holds that shadow whole and the same everywhere),
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

Of the Windows pictures (`-windows-`), the three figures retaken as whole
Windows.Graphics.Capture pictures are judged (#380: hero, colour-schemes,
light-and-dark — `corners.WINDOWS_FIGURES_RETAKEN`), against Windows' own
measurements. The single-window Windows shots are still owed the same retake
and are not judged until they have it (see website/SCREENSHOTS.md).

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
import shadow  # noqa: E402

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

    def test_the_windows_figures_retaken_natively_keep_their_corners(self):
        pictures = corners.windows_figures_retaken(REPO / "site" / "img")
        # Two static figures and the hero in light and dark, each PNG and WebP.
        self.assertEqual(len(pictures), 8, [picture.name for picture in pictures])
        found: list[str] = []
        for picture in pictures:
            found.extend(corners.corner_problems(picture))
        self.assertEqual(found, [], "\n" + "\n".join(found))

    def test_a_square_windows_picture_fails_whatever_its_ratio(self):
        import tempfile
        with tempfile.TemporaryDirectory() as scratch:
            square = Path(scratch) / "hero-windows-light.png"
            Image.new("RGBA", (400, 300), (240, 240, 240, 255)).save(square)
            self.assertTrue(corners.corner_problems(square))

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


class NaturalShadows(unittest.TestCase):
    """Every Mac window keeps its whole natural shadow (#434, Russell
    2026-10-03/04): exactly what `screencapture -x -l` writes with the window
    active — never cut off, never `-o`, never scaled, and the same on every
    picture. Checked on the PNGs the pages show; `shadow.py` says which
    figures are judged on their edge only, and why."""

    def test_no_shadow_on_the_site_is_cut_off_or_mismatched(self):
        problems = shadow.shadow_problems_on_the_site(REPO / "website", REPO / "site" / "img")
        self.assertEqual(problems, [], "\n" + "\n".join(problems))

    def test_every_single_window_picture_has_one_and_the_same_margin(self):
        margins_seen: dict[tuple, list[str]] = {}
        for picture, expected in shadow.mac_pictures_to_check(REPO / "website", REPO / "site" / "img"):
            if expected is None:
                continue
            margins_seen.setdefault(shadow.shadow_margins(picture), []).append(picture.name)
        self.assertEqual(len(margins_seen), 1, margins_seen)
        self.assertEqual(list(margins_seen), [shadow.NATIVE_MARGINS])

    def test_every_exemption_names_a_shot_that_exists(self):
        # An exemption from the margin rule for a shot that no longer exists
        # would be one nobody reads again.
        import json
        manifest = json.loads((REPO / "website" / "shots.json").read_text(encoding="utf-8"))
        identifiers = [shot["id"] for shot in manifest["shots"]]
        for identifier in shadow.FIGURES_WITH_THEIR_OWN_MARGIN + shadow.NOT_A_MAC_WINDOW:
            self.assertIn(identifier, identifiers)

    def test_the_hero_has_clear_canvas_all_round(self):
        # Russell's check for the hero is strict: its padding means the
        # outermost pixels are exactly transparent, not merely dithered.
        for suffix in ("light", "dark"):
            picture = REPO / "site" / "img" / f"hero-{suffix}.png"
            self.assertEqual(shadow.edge_alpha(picture), 0, picture.name)
            margins = shadow.shadow_margins(picture)
            for side in range(4):
                self.assertGreater(margins[side], shadow.NATIVE_MARGINS[side], picture.name)


class TheShadowCheckItself(unittest.TestCase):
    """Proved against pictures made here from a real capture, so a threshold
    that drifts cannot quietly pass everything."""

    def setUp(self):
        import tempfile
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        for name in ("courses-light.png", "preview-light.png", "site-eng2d-light.png"):
            path = REPO / "site" / "img" / name
            if path.exists():
                with Image.open(path) as opened:
                    self.capture = opened.convert("RGBA")
                return
        self.skipTest("no single-window capture in site/img")

    def tearDown(self):
        self._tmp.cleanup()

    def saved(self, image: Image.Image, name: str) -> Path:
        path = self.tmp / name
        image.save(path)
        return path

    def test_a_real_capture_passes(self):
        self.assertEqual(shadow.problems_with_shadow(self.saved(self.capture, "real.png")), [])

    def test_a_shadow_cut_off_at_the_bottom_fails_the_edge(self):
        cut = self.capture.crop((0, 0, self.capture.width, self.capture.height - 60))
        problems = shadow.problems_with_shadow(self.saved(cut, "cut.png"), expected_margins=None)
        self.assertTrue(problems)
        self.assertIn("cut off", problems[0])

    def test_a_capture_taken_with_minus_o_fails_the_margin(self):
        margins = shadow.shadow_margins(self.capture)
        window_only = self.capture.crop((margins[0], margins[1], self.capture.width - margins[2],
                                         self.capture.height - margins[3]))
        self.assertTrue(shadow.problems_with_shadow(self.saved(window_only, "no-shadow.png")))

    def test_a_scaled_capture_fails_the_margin(self):
        smaller = self.capture.resize((self.capture.width * 2 // 3, self.capture.height * 2 // 3),
                                      Image.Resampling.LANCZOS)
        problems = shadow.problems_with_shadow(self.saved(smaller, "scaled.png"))
        self.assertTrue(problems)
        self.assertIn("margins", problems[-1])

    def test_a_trimmed_capture_fails_the_margin_even_with_a_clean_edge(self):
        # Trimmed by 20 px all round: the edge is still transparent, but the
        # margin is no longer the active window's.
        trimmed = self.capture.crop((20, 20, self.capture.width - 20, self.capture.height - 20))
        problems = shadow.problems_with_shadow(self.saved(trimmed, "trimmed.png"))
        self.assertTrue(problems)

    def test_no_alpha_at_all_fails(self):
        self.assertTrue(shadow.problems_with_shadow(self.saved(self.capture.convert("RGB"), "flat.png")))

    def test_a_cascade_of_whole_captures_keeps_every_shadow(self):
        import composite
        parts = [self.saved(self.capture, f"part{index}.png") for index in range(3)]
        figure = composite.native_cascade(parts, self.tmp / "hero.png")
        self.assertEqual(shadow.problems_with_shadow(figure, expected_margins=None), [])
        with Image.open(figure) as opened:
            margins = shadow.shadow_margins(opened)
        # Padding outside each window's whole shadow, on every side.
        native = shadow.shadow_margins(self.capture)
        for side in range(4):
            self.assertGreater(margins[side], native[side])

    def test_a_fan_and_a_pair_keep_one_windows_margin_outside(self):
        import composite
        parts = [self.saved(self.capture, f"card{index}.png") for index in range(3)]
        native = shadow.shadow_margins(self.capture)
        for figure in (composite.native_fan(parts, self.tmp / "fan.png"),
                       composite.native_side_by_side(parts[:2], self.tmp / "pair.png")):
            self.assertEqual(shadow.problems_with_shadow(figure, native), [], figure.name)


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
