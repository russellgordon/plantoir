#!/usr/bin/env python3
"""
Which pictures on plantoir.app a Windows visitor sees with a drawn shadow.

A Windows capture of a single window arrives without a shadow of its own, so
the stylesheet gives it a drop-shadow filter. The composite (the hero), the
static figures (colour schemes, light and dark) and the phone in its bezel
arrive with their shadows already drawn, or need none, so a filter there would
lay a SECOND shadow over them. A plain `filter: none` cannot keep them flat,
because the Windows rule is the more specific of the two and wins whatever the
order (the v1.4.3 sweep's finding 1), so the Windows rule names them out
instead. This test reads the stylesheet and the BUILT pages and checks which
figures the rule reaches. Pure stdlib. Run with:

    python3 website/test_shot_shadows.py
"""
import re
import sys
import unittest
from html.parser import HTMLParser
from pathlib import Path

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
STYLESHEET = WEBSITE / "assets" / "style.css"
BUILT_PAGES = [REPO / "site" / "index.html", REPO / "site" / "features" / "index.html"]

FLAT_FIGURE_CLASSES = ["shot-composite", "shot-static", "shot-device"]


def windows_shadow_selectors(css: str) -> list:
    """Every selector, under .is-windows, of a rule that draws a drop-shadow."""
    without_comments = re.sub(r"/\*.*?\*/", "", css, flags=re.DOTALL)
    selectors: list = []
    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", without_comments):
        selector_list = match.group(1)
        declarations = match.group(2)
        if "drop-shadow" not in declarations:
            continue
        for selector in selector_list.split(","):
            cleaned = selector.strip()
            if cleaned.startswith(".is-windows"):
                selectors.append(cleaned)
    return selectors


def figure_matches(selector: str, figure_classes: list, img_has_win_src: bool) -> bool:
    """
    Whether `.is-windows <figure part> img[...]` reaches an img inside a figure.

    Only the shape the stylesheet uses is understood: the figure part is a
    run of `.class` and `:not(.class)`, and the img part may ask for
    `[data-win-src]`. Anything else fails the test loudly rather than being
    guessed at.
    """
    parts = selector.split()
    if len(parts) != 3 or parts[0] != ".is-windows" or not parts[2].startswith("img"):
        raise AssertionError("a selector this test cannot read: " + selector)
    figure_part = parts[1]
    img_part = parts[2]
    excluded: list = re.findall(r":not\(\.([\w-]+)\)", figure_part)
    remainder = re.sub(r":not\(\.[\w-]+\)", "", figure_part)
    required: list = re.findall(r"\.([\w-]+)", remainder)
    if re.sub(r"\.[\w-]+", "", remainder) != "":
        raise AssertionError("a selector this test cannot read: " + selector)
    for name in required:
        if name not in figure_classes:
            return False
    for name in excluded:
        if name in figure_classes:
            return False
    if "[data-win-src]" in img_part and not img_has_win_src:
        return False
    return True


class FigureCollector(HTMLParser):
    """Each <figure class="shot …"> with whether an img in it has data-win-src."""

    def __init__(self) -> None:
        super().__init__()
        self.figures: list = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "figure":
            classes = (attributes.get("class") or "").split()
            if "shot" in classes:
                self.current = {"classes": classes, "winSrc": False}
        elif tag == "img" and self.current is not None:
            if "data-win-src" in attributes:
                self.current["winSrc"] = True

    def handle_endtag(self, tag):
        if tag == "figure" and self.current is not None:
            self.figures.append(self.current)
            self.current = None


def built_figures() -> list:
    figures: list = []
    for page in BUILT_PAGES:
        collector = FigureCollector()
        collector.feed(page.read_text(encoding="utf-8"))
        for figure in collector.figures:
            figures.append(figure)
    return figures


def reached_by_shadow(selectors: list, figure: dict) -> bool:
    for selector in selectors:
        if figure_matches(selector, figure["classes"], figure["winSrc"]):
            return True
    return False


class WindowsShadowTests(unittest.TestCase):

    def setUp(self) -> None:
        self.selectors = windows_shadow_selectors(STYLESHEET.read_text(encoding="utf-8"))
        self.figures = built_figures()

    def test_the_stylesheet_still_draws_a_shadow_for_windows(self) -> None:
        self.assertTrue(self.selectors, "no .is-windows rule draws a drop-shadow any more")

    def test_figures_that_carry_their_own_shadow_are_never_reached(self) -> None:
        checked = 0
        for figure in self.figures:
            flat = False
            for name in FLAT_FIGURE_CLASSES:
                if name in figure["classes"]:
                    flat = True
            if not flat or not figure["winSrc"]:
                continue
            checked += 1
            self.assertFalse(reached_by_shadow(self.selectors, figure),
                             "a Windows visitor would see a second shadow on " + " ".join(figure["classes"]))
        # The hero, the two static figures and the phone: if the pages stop
        # carrying them, this test is no longer testing anything.
        self.assertGreaterEqual(checked, 4)

    def test_a_plain_windows_capture_still_gets_its_shadow(self) -> None:
        plain_with_windows_capture = 0
        for figure in self.figures:
            if figure["classes"] == ["shot"] and figure["winSrc"]:
                plain_with_windows_capture += 1
                self.assertTrue(reached_by_shadow(self.selectors, figure))
        self.assertGreater(plain_with_windows_capture, 0)

    def test_a_mac_picture_with_no_windows_capture_gets_no_filter(self) -> None:
        self.assertFalse(reached_by_shadow(self.selectors, {"classes": ["shot"], "winSrc": False}))


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    sys.exit(0 if result.wasSuccessful() else 1)
