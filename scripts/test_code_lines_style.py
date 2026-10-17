#!/usr/bin/env python3
"""
Every code block's line numbers, and the editor's colours (#585), as the
stylesheets write them.

support/quartz/components/styles/codeLines.scss gives every static code
block on every site, and every runnable block's gutter, ONE line-number style
(rulings R1 and R3): Quartz's dimmed colour, the code font, a box as wide as
the block's longest number, then a 1 px hairline in the theme's muted border
colour - and no programming ligatures in any code (ruling Q5). It reaches the
site only through codeRunner.scss, which @uses it and is carried by
CodeRunner.tsx. codeRunner.scss gives each colour category of the editor
(codeRunnerColour.ts) Shiki's own two custom properties; the values are the
contract's (codeRunnerBlocks.editor.colour.categories). print.scss hangs a
handout's wrapped code line by the number's WHOLE box - digits, the gutter's
padding and hairline, and the gap - or the continuation pokes out to the
left of the code (#585 plan review F4).

scripts/check_runner_rules_against_the_site.py pins the same table to the
image's own Shiki inside the container; this file holds the stylesheets to
the table and to each other where no container is needed. Pure Python with
no shell, so Windows' PythonToolchainTests discovers and runs it too;
verify.sh lists it in step 0. Files are read as UTF-8 explicitly.
"""

import json
import re
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
COMPONENTS = REPOSITORY / "support" / "quartz" / "components"
CODE_LINES = COMPONENTS / "styles" / "codeLines.scss"
RUNNER_STYLES = COMPONENTS / "styles" / "codeRunner.scss"
PRINT_STYLES = COMPONENTS / "styles" / "print.scss"
CARRIER = COMPONENTS / "CodeRunner.tsx"
COLOUR_SCRIPT = COMPONENTS / "scripts" / "codeRunnerColour.ts"
PAGE_SCRIPT = COMPONENTS / "scripts" / "codeRunner.inline.ts"
CONTRACT = REPOSITORY / "contracts" / "shared-rules.json"


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def block_after(source, selector):
    """The declarations of the first rule whose selector line is `selector`."""
    at = source.index(selector + " {")
    opening = source.index("{", at)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1:index]
    raise AssertionError(f"{selector} never closes")


class GutterStyleTests(unittest.TestCase):
    """One style for a static block's numbers and a runnable block's gutter."""

    @classmethod
    def setUpClass(cls):
        cls.lines = read_text(CODE_LINES)
        cls.runner = read_text(RUNNER_STYLES)

    def test_the_mixin_carries_quartzs_colour_the_code_font_and_a_hairline(self):
        mixin = block_after(self.lines, "@mixin plantoir-gutter")
        self.assertIn("color: rgba(115, 138, 148, 0.6);", mixin)
        self.assertIn("font-family: var(--codeFont);", mixin)
        self.assertIn("text-align: right;", mixin)
        self.assertIn("width: calc(var(--plantoir-digits, 2) * 1ch);", mixin)
        self.assertIn("padding-right: 0.75ch;", mixin)
        self.assertIn("border-right: 1px solid var(--lightgray);", mixin)
        self.assertNotIn("background", mixin, "the gutter has no fill")

    def test_every_static_block_and_the_editors_gutter_wear_it(self):
        static = block_after(self.lines, ":root pre > code:not(.mermaid) > [data-line]::before")
        self.assertIn("@include plantoir-gutter;", static)
        gutter = block_after(self.runner, "  & pre.plantoir-runner-gutter")
        self.assertIn("@include lines.plantoir-gutter;", gutter)
        self.assertIn('@use "codeLines" as lines;', self.runner)

    def test_the_static_rule_outranks_quartzs_own(self):
        # Component styles come before Quartz's base styles in index.css:
        # Quartz's widest rule is pre > code[data-line-numbers-max-digits] >
        # [data-line]::before, two attributes or classes and three types.
        self.assertIn(":root pre > code:not(.mermaid) > [data-line]::before {", self.lines)

    def test_a_long_block_gets_a_third_and_a_fourth_digit_without_a_script(self):
        self.assertIn(":root pre > code:has(> [data-line]:nth-child(100)) {\n  --plantoir-digits: 3;", self.lines)
        self.assertIn(":root pre > code:has(> [data-line]:nth-child(1000)) {\n  --plantoir-digits: 4;", self.lines)

    def test_no_ligatures_in_any_code_the_editor_or_its_copy(self):
        ligatures = block_after(self.lines, ":root pre,\n:root pre code,\n:root .plantoir-runner .plantoir-runner-editor")
        self.assertIn("font-variant-ligatures: none;", ligatures)
        shared = block_after(self.runner, "  & .plantoir-runner-cell > .plantoir-runner-editor,\n  & .plantoir-runner-cell > pre.plantoir-runner-colour")
        self.assertIn("font-variant-ligatures: none;", shared)

    def test_the_stylesheet_reaches_the_site(self):
        carrier = read_text(CARRIER)
        self.assertIn('import style from "./styles/codeRunner.scss"', carrier)
        self.assertIn("CodeRunner.css = style", carrier)


class EditorOverlayTests(unittest.TestCase):
    """The coloured copy and the textarea share every metric in ONE rule."""

    @classmethod
    def setUpClass(cls):
        cls.runner = read_text(RUNNER_STYLES)

    def test_one_rule_holds_both_layers_metrics(self):
        shared = block_after(self.runner, "  & .plantoir-runner-cell > .plantoir-runner-editor,\n  & .plantoir-runner-cell > pre.plantoir-runner-colour")
        for declaration in ("font-family: var(--codeFont);", "font-size: max(16px, 0.9em);", "line-height: 1.5;",
                            "tab-size: 4;", "white-space: pre;", "border: 0;", "padding: 0.5rem 0.75rem 0.5rem 1ch;"):
            self.assertIn(declaration, shared)

    def test_the_focus_ring_is_the_frames(self):
        ring = block_after(self.runner, "  & .plantoir-runner-frame:focus-within")
        self.assertIn("outline: 2px solid var(--secondary);", ring)
        inner = block_after(self.runner, "  & .plantoir-runner-cell > .plantoir-runner-editor:focus")
        self.assertIn("outline: none;", inner)

    def test_quartzs_overflow_on_the_copys_code_is_put_back(self):
        code = block_after(self.runner, "  & pre.plantoir-runner-colour > code")
        self.assertIn("overflow: visible;", code)
        self.assertIn("width: max-content;", code)

    def test_the_frame_and_its_copy_never_print(self):
        printing = self.runner[self.runner.index("@media print"):]
        self.assertIn("& .plantoir-runner-frame,", printing)


class ColourCategoryTests(unittest.TestCase):
    """codeRunner.scss, the contract and the tokenizer name the same categories."""

    @classmethod
    def setUpClass(cls):
        with open(CONTRACT, encoding="utf-8") as handle:
            rules = json.load(handle)["codeRunnerBlocks"]
        cls.table = rules["editor"]["colour"]["categories"]
        cls.languages = rules["languages"]
        cls.runner = read_text(RUNNER_STYLES)
        cls.script = read_text(COLOUR_SCRIPT)

    def test_each_categorys_class_sets_shikis_two_properties_to_the_contracts_pair(self):
        for category, (light, dark) in self.table.items():
            with self.subTest(category=category):
                if category == "plain":
                    rule = block_after(self.runner, "  & pre.plantoir-runner-colour > code")
                else:
                    rule = block_after(self.runner, f"  & .plantoir-tok-{category}")
                self.assertIn(f"--shiki-light: {light.lower()};", rule)
                self.assertIn(f"--shiki-dark: {dark.lower()};", rule)

    def test_the_tokenizer_knows_every_category_and_no_other(self):
        listed = re.search(r"export const CATEGORIES: Category\[\] = \[([^\]]*)\]", self.script).group(1)
        names = set(re.findall(r'"([a-z])"', listed))
        self.assertEqual(names, set(self.table) - {"plain"})
        classes = set(re.findall(r"\.plantoir-tok-([a-z]+) \{", self.runner))
        self.assertEqual(classes, set(self.table) - {"plain"})

    def test_every_language_rows_colour_names_a_tokenizer(self):
        for row in self.languages:
            with self.subTest(fence=row["fence"]):
                colour = row["colour"]
                if colour is not None:
                    self.assertIn(f'if (colour === "{colour}") {{', self.script)

    def test_the_page_script_colours_through_the_rows_field(self):
        script = read_text(PAGE_SCRIPT)
        self.assertIn('from "./codeRunnerColour"', script)
        self.assertIn("colourLines(language.colour,", script)


class HandoutHangTests(unittest.TestCase):
    """A handout's wrapped code line starts under the first row's code."""

    def test_the_hang_is_the_numbers_whole_box(self):
        printing = read_text(PRINT_STYLES)
        line = block_after(printing, "  pre > code > [data-plantoir-line]")
        number = block_after(printing, "  pre > code > [data-plantoir-line]::before")
        # digits + the gutter's 0.75ch padding + its 1px hairline + a 1ch gap.
        self.assertIn("padding-left: calc((var(--plantoir-digits, 2) + 1.75) * 1ch + 1px);", line)
        self.assertIn("text-indent: calc((var(--plantoir-digits, 2) + 1.75) * -1ch - 1px);", line)
        self.assertIn("margin-right: 1ch !important;", number)
        mixin = block_after(read_text(CODE_LINES), "@mixin plantoir-gutter")
        self.assertIn("padding-right: 0.75ch;", mixin)
        self.assertIn("border-right: 1px solid", mixin)


if __name__ == "__main__":
    unittest.main()
