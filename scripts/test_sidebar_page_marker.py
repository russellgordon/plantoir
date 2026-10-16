#!/usr/bin/env python3
"""
The sidebar's page marker (#515) can be seen in every colour scheme, and
leaves the sidebar's links alone.

support/quartz/components/styles/sidebarPageMarker.scss puts a small dot
before each page inside an open folder of "Navigate this site", so a title
that wraps onto a second line is not read as two pages. The dot must be seen:
WCAG 2.2 success criterion 1.4.11 (non-text contrast) asks for at least 3:1
against what is next to it, here the sidebar's background, --light. Its
colour is a scheme's own --dark (or whichever variable the stylesheet names)
drawn at the stylesheet's opacity, so what a student sees is that colour
BLENDED over --light. This holds the blend to 3:1 in all 43 schemes, light and
dark, from support/colour_schemes.json - read here, not retyped, so a scheme
added there is checked here too. The browser check
(browser-checks/sidebar_page_marker.mjs, run by verify.sh) measures the same
figure off the built site for the one scheme the example course uses.

It also holds the stylesheet to its promise that the current page's colour
and a link's hover colour are Quartz's, unchanged: no rule in it may style a
link, :hover or .active. A rule's SUBJECT is what it styles - the last
compound of its selector - so `li:has(> a)` styles the li and is allowed,
and `li > a` styles the link and is not. Comments are taken out first, since
they talk about links.

And it holds the two places the stylesheet depends on: it is imported by
PlantoirMetaLine.tsx and handed to concatenateResources, which is how it
reaches the site's index.css; and no file in support/quartz/components/styles
is named after a stylesheet of Quartz's own explorer, because
install_quartz_additions copies support/quartz over Quartz by path and would
replace it.

Pure Python with no shell, so Windows' PythonToolchainTests discovers and runs
it as well; verify.sh lists it in step 0. Files are read as UTF-8 explicitly.
"""

import json
import re
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
SCHEMES_FILE = REPOSITORY / "support" / "colour_schemes.json"
COMPONENTS = REPOSITORY / "support" / "quartz" / "components"
STYLESHEET = COMPONENTS / "styles" / "sidebarPageMarker.scss"
CARRIER = COMPONENTS / "PlantoirMetaLine.tsx"

LEAST_CONTRAST = 3.0
MARKER_SELECTOR = ".explorer .explorer-content .folder-outer > ul > li:has(> a)"


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def without_comments(source):
    """SCSS with its // line comments and /* block */ comments taken out.
    A // inside a string (a url, say) would be cut wrongly, and this file
    has none; the check below fails loudly if that ever changes the rules."""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    lines = []
    for line in source.splitlines():
        lines.append(line.split("//", 1)[0])
    return "\n".join(lines)


def rules_in(source):
    """Every rule's full selector list, nesting resolved the way Sass resolves
    it (`&` stands for the parent; a selector with no `&` is a descendant),
    paired with its own declarations. At-rules (@media) are walked into and
    are not themselves selectors."""
    found = []

    def walk(text, parents):
        position = 0
        while True:
            opening = text.find("{", position)
            if opening == -1:
                return
            prelude_start = max(text.rfind(";", position, opening), text.rfind("}", position, opening)) + 1
            prelude_start = max(prelude_start, position)
            prelude = text[prelude_start:opening].strip()
            depth = 1
            cursor = opening + 1
            while depth > 0:
                if text[cursor] == "{":
                    depth += 1
                elif text[cursor] == "}":
                    depth -= 1
                cursor += 1
            body = text[opening + 1:cursor - 1]
            if prelude.startswith("@"):
                walk(body, parents)
            else:
                selectors = []
                for part in split_selector_list(prelude):
                    if not parents:
                        selectors.append(part)
                    else:
                        for parent in parents:
                            selectors.append(part.replace("&", parent) if "&" in part else parent + " " + part)
                own = re.sub(r"\{.*\}", "", body, flags=re.DOTALL) if "{" in body else body
                found.append((selectors, declarations_in(own)))
                walk(body, selectors)
            position = cursor

    walk(without_comments(source), [])
    return found


def split_selector_list(prelude):
    """Splits `a, b:is(c, d)` at its top-level commas only."""
    parts = []
    depth = 0
    current = ""
    for character in prelude:
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        if character == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += character
    if current.strip():
        parts.append(current.strip())
    return parts


def declarations_in(body):
    """A rule's own `property: value;` pairs, nested rules already removed."""
    pairs = {}
    for statement in body.split(";"):
        if ":" in statement:
            name, value = statement.split(":", 1)
            name = name.strip()
            if re.fullmatch(r"-?[a-z][a-z-]*", name):
                pairs[name] = value.strip()
    return pairs


def subject_of(selector):
    """The last compound of a selector - what it styles - with every
    :has(...)/:not(...)/:is(...)/:where(...) argument taken out, since those
    only say WHICH element is styled."""
    flattened = selector
    while True:
        shorter = re.sub(r":(has|not|is|where)\([^()]*\)", "", flattened)
        if shorter == flattened:
            break
        flattened = shorter
    compounds = re.split(r"\s*[>+~]\s*|\s+", flattened.strip())
    return compounds[-1]


def channels(hex_colour):
    text = hex_colour.strip().lstrip("#")
    if len(text) == 3:
        text = "".join(character * 2 for character in text)
    return [int(text[index:index + 2], 16) / 255 for index in (0, 2, 4)]


def luminance(rgb):
    total = 0.0
    weights = (0.2126, 0.7152, 0.0722)
    for weight, channel in zip(weights, rgb):
        linear = channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
        total += weight * linear
    return total


def contrast(one, other):
    first = luminance(one)
    second = luminance(other)
    lighter = max(first, second)
    darker = min(first, second)
    return (lighter + 0.05) / (darker + 0.05)


def blend(colour, alpha, ground):
    mixed = []
    for top, bottom in zip(colour, ground):
        mixed.append(top * alpha + bottom * (1 - alpha))
    return mixed


def the_marker_rule():
    """The ::before rule under the marker's selector: its colour variable
    and its opacity, as the stylesheet writes them."""
    for selectors, declarations in rules_in(read_text(STYLESHEET)):
        if selectors == [MARKER_SELECTOR + "::before"] and "background-color" in declarations:
            colour = re.fullmatch(r"var\(--([a-z]+)\)", declarations["background-color"])
            opacity = declarations.get("opacity", "1")
            return (colour.group(1) if colour else None), float(opacity)
    return None, None


class TheMarkerCanBeSeen(unittest.TestCase):

    def test_the_stylesheet_names_a_scheme_colour_and_an_opacity(self):
        variable, opacity = the_marker_rule()
        self.assertIsNotNone(variable, f"no `background-color: var(--…)` in the {MARKER_SELECTOR}::before rule of {STYLESHEET.name}")
        self.assertTrue(0 < opacity <= 1, f"the dot's opacity {opacity} is not between 0 and 1")

    def test_the_dot_is_at_least_three_to_one_on_every_schemes_sidebar(self):
        variable, opacity = the_marker_rule()
        self.assertIsNotNone(variable)
        with open(SCHEMES_FILE, encoding="utf-8") as handle:
            schemes = json.load(handle)
        self.assertGreater(len(schemes), 0)
        too_faint = []
        lowest = {}
        for scheme in schemes:
            for mode in ("lightMode", "darkMode"):
                palette = scheme["colors"][mode]
                ground = channels(palette["light"])
                dot = blend(channels(palette[variable]), opacity, ground)
                ratio = contrast(dot, ground)
                if mode not in lowest or ratio < lowest[mode][0]:
                    lowest[mode] = (ratio, scheme["id"])
                if ratio < LEAST_CONTRAST:
                    too_faint.append(f"{scheme['id']} {mode}: {ratio:.2f}:1")
        print(f"\n--{variable} at {opacity} over --light, {len(schemes)} schemes: "
              f"light at least {lowest['lightMode'][0]:.2f}:1 ({lowest['lightMode'][1]}), "
              f"dark at least {lowest['darkMode'][0]:.2f}:1 ({lowest['darkMode'][1]})")
        self.assertEqual(too_faint, [], f"the sidebar's page dot is under {LEAST_CONTRAST}:1 (WCAG 2.2, 1.4.11)")


class TheLinksAreLeftAlone(unittest.TestCase):

    def test_the_stylesheet_has_its_rules(self):
        rules = rules_in(read_text(STYLESHEET))
        every = []
        for selectors, _ in rules:
            every.extend(selectors)
        self.assertIn(MARKER_SELECTOR, every)
        self.assertIn(MARKER_SELECTOR + "::before", every)

    def test_no_rule_styles_a_link_its_hover_or_the_current_page(self):
        styled = []
        for selectors, _ in rules_in(read_text(STYLESHEET)):
            for selector in selectors:
                subject = subject_of(selector)
                element = re.match(r"[a-zA-Z][a-zA-Z0-9-]*", subject)
                if (element and element.group(0).lower() == "a") or ":hover" in subject or ".active" in subject:
                    styled.append(selector)
        self.assertEqual(styled, [], "the marker's stylesheet must not style the sidebar's links, their hover or the current page")

    def test_the_subject_reader_tells_a_row_from_a_link(self):
        # So the test above cannot pass by reading nothing.
        self.assertEqual(subject_of("ul > li:has(> a)"), "li")
        self.assertEqual(subject_of("ul > li:has(> a)::before"), "li::before")
        self.assertEqual(subject_of("ul li > a"), "a")
        self.assertEqual(subject_of("ul li > a:hover"), "a:hover")
        self.assertEqual(subject_of(".x a.active"), "a.active")


class TheStylesheetReachesTheSite(unittest.TestCase):

    def test_plantoir_meta_line_imports_it_and_hands_it_on(self):
        carrier = read_text(CARRIER)
        imported = re.search(r'^import\s+(\w+)\s+from\s+"\./styles/sidebarPageMarker\.scss"', carrier, flags=re.MULTILINE)
        self.assertIsNotNone(imported, f"{CARRIER.name} does not import styles/sidebarPageMarker.scss")
        handed_on = re.search(r"PlantoirMetaLine\.css\s*=\s*concatenateResources\(([^)]*)\)", carrier)
        self.assertIsNotNone(handed_on)
        names = []
        for name in handed_on.group(1).split(","):
            names.append(name.strip())
        self.assertIn(imported.group(1), names, "the marker's stylesheet is imported but not added to PlantoirMetaLine.css")

    def test_no_stylesheet_replaces_quartzs_own_explorer_styles(self):
        self.assertFalse((COMPONENTS / "styles" / "explorer.scss").exists(),
                         "support/quartz/components/styles/explorer.scss would replace Quartz's own in every section")


if __name__ == "__main__":
    unittest.main()
