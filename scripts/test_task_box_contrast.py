#!/usr/bin/env python3
"""
A task box students tick (#519) can be seen, and its ticked words read, in
every colour scheme (contracts/shared-rules.json -> taskBoxes.look).

support/quartz/components/styles/tasks.scss draws the box's edge and its tick
in a scheme colour, with no fill, and keeps a ticked item's words in a scheme
colour too. On screen (outside `@media print`) each must stand out from the
page's background, --light: the edge and the tick are controls' marks, so at
least 3:1 (WCAG 2.2, 1.4.11 non-text contrast); the words are text, so at
least 4.5:1 (1.4.3). This holds every colour the stylesheet names for them to
its minimum in all the schemes of support/colour_schemes.json, light and
dark - read here, not retyped, so a scheme added there is checked here too.
A ticked box has no fill: Quartz's fill (--secondary, with the tick in
--light) is what fell to 1.06:1.

On paper, a page in the dark theme prints its box in a fixed ink
(`$paper-ink`), since the dark theme's --darkgray is a light colour that
vanished on white paper (measured, browser-checks/task_boxes.mjs); that ink
is held to 3:1 on white.

Pure Python with no shell, so Windows' PythonToolchainTests discovers and runs
it as well. Files are read as UTF-8 explicitly.
"""

import json
import re
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
SCHEMES_FILE = REPOSITORY / "support" / "colour_schemes.json"
STYLESHEET = REPOSITORY / "support" / "quartz" / "components" / "styles" / "tasks.scss"

BOX = 'input[type="checkbox"].plantoir-task'
TICKED_ITEM = ".page article li.task-list-item:has(> .plantoir-task-label > input.plantoir-task:checked)"

# (selector, property, what it is, least contrast)
MARKS = [
    (BOX, "border-color", "an unticked box's edge", 3.0),
    (BOX + ":checked", "border-color", "a ticked box's edge", 3.0),
    (BOX + ":checked::after", "border-color", "the tick", 3.0),
    (TICKED_ITEM, "color", "a ticked item's words", 4.5),
    (TICKED_ITEM, "text-decoration-color", "the line through them", 3.0),
]


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def without_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    lines = []
    for line in source.splitlines():
        lines.append(line.split("//", 1)[0])
    return "\n".join(lines)


def split_selector_list(prelude):
    """Splits `a, b:has(c, d)` at its top-level commas only."""
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
    pairs = {}
    for statement in body.split(";"):
        if ":" in statement:
            name, value = statement.split(":", 1)
            name = name.strip()
            if re.fullmatch(r"-?[a-z][a-z-]*", name):
                pairs[name] = value.strip()
    return pairs


def rules_in(source):
    """Every rule: its selectors with nesting resolved as Sass resolves it,
    its own declarations, and whether it sits inside `@media print`."""
    found = []

    def walk(text, parents, in_print):
        position = 0
        while True:
            opening = text.find("{", position)
            if opening == -1:
                return
            prelude_start = max(text.rfind(";", position, opening), text.rfind("}", position, opening)) + 1
            prelude = text[max(prelude_start, position):opening].strip()
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
                walk(body, parents, in_print or prelude.replace(" ", "") == "@mediaprint")
            else:
                selectors = []
                for part in split_selector_list(prelude):
                    if not parents:
                        selectors.append(part)
                    else:
                        for parent in parents:
                            selectors.append(part.replace("&", parent) if "&" in part else parent + " " + part)
                own = body
                while "{" in own:
                    own = re.sub(r"[^{};]*\{[^{}]*\}", "", own)
                found.append((selectors, declarations_in(own), in_print))
                walk(body, selectors, in_print)
            position = cursor

    walk(without_comments(source), [], False)
    return found


def screen_value(selector, prop):
    """The last value the stylesheet gives `prop` under `selector` on screen."""
    value = None
    for selectors, declarations, in_print in rules_in(read_text(STYLESHEET)):
        if not in_print and selector in selectors and prop in declarations:
            value = declarations[prop]
    return value


def channels(hex_colour):
    text = hex_colour.strip().lstrip("#")
    if len(text) == 3:
        text = "".join(character * 2 for character in text)
    return [int(text[index:index + 2], 16) / 255 for index in (0, 2, 4)]


def luminance(rgb):
    total = 0.0
    for weight, channel in zip((0.2126, 0.7152, 0.0722), rgb):
        linear = channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
        total += weight * linear
    return total


def contrast(one, other):
    first = luminance(one)
    second = luminance(other)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)


class TheBoxCanBeSeen(unittest.TestCase):

    def test_every_mark_names_a_scheme_colour(self):
        for selector, prop, what, _ in MARKS:
            value = screen_value(selector, prop)
            self.assertIsNotNone(value, f"tasks.scss gives {what} no {prop} on screen ({selector})")
            self.assertRegex(value, r"^var\(--[a-z]+\)$", f"{what} is not a scheme colour: {value}")

    def test_a_ticked_box_has_no_fill(self):
        self.assertEqual(screen_value(BOX + ":checked", "background-color"), "transparent")

    def test_every_mark_stands_out_in_every_scheme(self):
        with open(SCHEMES_FILE, encoding="utf-8") as handle:
            schemes = json.load(handle)
        self.assertGreater(len(schemes), 40)
        too_faint = []
        report = []
        for selector, prop, what, least in MARKS:
            variable = re.fullmatch(r"var\(--([a-z]+)\)", screen_value(selector, prop) or "")
            self.assertIsNotNone(variable, what)
            lowest = {}
            for scheme in schemes:
                for mode in ("lightMode", "darkMode"):
                    palette = scheme["colors"][mode]
                    ratio = contrast(channels(palette[variable.group(1)]), channels(palette["light"]))
                    if mode not in lowest or ratio < lowest[mode][0]:
                        lowest[mode] = (ratio, scheme["id"])
                    if ratio < least:
                        too_faint.append(f"{what}: {scheme['id']} {mode} {ratio:.2f}:1 (needs {least}:1)")
            report.append(f"{what} (--{variable.group(1)}): light at least {lowest['lightMode'][0]:.2f}:1 "
                          f"({lowest['lightMode'][1]}), dark at least {lowest['darkMode'][0]:.2f}:1 ({lowest['darkMode'][1]})")
        print("\n" + "\n".join(report))
        self.assertEqual(too_faint, [])

    def test_the_dark_themes_paper_ink_stands_out_on_white(self):
        source = without_comments(read_text(STYLESHEET))
        ink = re.search(r"\$paper-ink:\s*(#[0-9a-fA-F]{3,6})\s*;", source)
        self.assertIsNotNone(ink, "tasks.scss has no $paper-ink")
        self.assertGreaterEqual(contrast(channels(ink.group(1)), [1.0, 1.0, 1.0]), 3.0)
        used = [selectors for selectors, declarations, in_print in rules_in(read_text(STYLESHEET))
                if in_print and declarations.get("border-color") == "$paper-ink"]
        self.assertTrue(any(':root[saved-theme="dark"]' in selector for selectors in used for selector in selectors),
                        "the paper ink is not used for the dark theme's boxes on paper")


if __name__ == "__main__":
    unittest.main()
