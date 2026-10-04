#!/usr/bin/env python3
"""A class-site picture taken for an anchor shows that anchor's heading.

v1.4.3 shipped `site-sch3u` (`…#diagrams`) and `site-sch3u-chemistry`
(`…#mathematics-and-chemistry`) both showing the page's "Backlinks" end:
the scroll to the anchor landed, and the find-bar step that takes focus out
of the address field then moved the page. Every other check passed. The
rule now: the photograph itself is read with text recognition, and the
heading the fragment names must be in the page column, near the top
(`safari.anchor_heading_in_view`). `capture.py` refuses a capture that fails
it; this test holds the committed pictures to it, so a wrong one cannot ship.

The rule is proved on boxes made here; the committed pictures need macOS's
text recognition (`ocr.swift`), and are skipped where `swift` is missing.

    python3 website/shots/test_browser_anchors.py
"""
import json
import shutil
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))

import safari  # noqa: E402

WIDTH = 2784
HEIGHT = 1944


class TheRule(unittest.TestCase):

    def test_the_heading_near_the_top_of_the_page_column_passes(self):
        boxes = [(756, 189, 586, 48, "Mathematics and chemistry")]
        self.assertTrue(safari.anchor_heading_in_view(boxes, "mathematics-and-chemistry", WIDTH, HEIGHT))

    def test_the_same_words_in_the_table_of_contents_do_not_count(self):
        # Measured on the wrong picture: the right-hand "Navigate this page"
        # list says "Mathematics and chemistry" near the top whatever the
        # scroll, while the page column shows Backlinks.
        boxes = [
            (760, 755, 170, 36, "Backlinks"),
            (2096, 743, 420, 36, "Mathematics and chemistry"),
            (2095, 844, 149, 33, "Diagrams"),
        ]
        self.assertFalse(safari.anchor_heading_in_view(boxes, "mathematics-and-chemistry", WIDTH, HEIGHT))
        self.assertFalse(safari.anchor_heading_in_view(boxes, "diagrams", WIDTH, HEIGHT))

    def test_the_heading_far_down_the_page_does_not_count(self):
        boxes = [(756, 1500, 300, 48, "Diagrams")]
        self.assertFalse(safari.anchor_heading_in_view(boxes, "diagrams", WIDTH, HEIGHT))

    def test_a_longer_line_that_merely_contains_the_words_does_not_count(self):
        boxes = [(756, 300, 1200, 40, "Writing chemistry with \\ce{} and diagrams")]
        self.assertFalse(safari.anchor_heading_in_view(boxes, "diagrams", WIDTH, HEIGHT))

    def test_the_heading_words_come_from_the_fragment(self):
        self.assertEqual(safari.heading_words("mathematics-and-chemistry"),
                         safari.heading_words("Mathematics and chemistry"))


@unittest.skipIf(shutil.which("swift") is None, "needs macOS text recognition (swift ocr.swift)")
class TheCommittedPictures(unittest.TestCase):

    def test_every_anchored_class_site_picture_shows_its_heading(self):
        manifest = json.loads((REPO / "website" / "shots.json").read_text(encoding="utf-8"))
        checked = 0
        problems: list[str] = []
        for shot in manifest["shots"]:
            path = shot.get("capture", {}).get("path", "")
            if "#" not in path or shot.get("capture", {}).get("kind") != "browser":
                continue
            fragment = path.split("#", 1)[1]
            for suffix in ("light", "dark"):
                picture = REPO / "site" / "img" / f"{shot['id']}-{suffix}.png"
                problem = safari.anchor_heading_problem(picture, fragment)
                if problem is not None:
                    problems.append(f"{picture.name}: {problem}")
                checked += 1
        self.assertEqual(checked, 4, "site-sch3u and site-sch3u-chemistry, light and dark")
        self.assertEqual(problems, [], "\n" + "\n".join(problems))


if __name__ == "__main__":
    unittest.main()
