#!/usr/bin/env python3
"""
A value from a course's settings is written into the site's TypeScript as a
properly escaped string (GitHub #871).

The build writes a club's short label (and the emoji and course code beside
it), the locale, a custom domain, the font names and the colour values into
quartz.config.ts, and the footer into Footer.tsx, each INSIDE a string. Before
#871 they were written as typed: a `"` ended the string and the site did not
build, and a `\\` was read as an escape. The rule and its cases are
`contracts/shared-rules.json` -> `typescriptStrings`.

Pinned here:

  * every contract case through `build_site.typescript_string`, and the
    literal it writes reads back as the value (as JSON, which is a subset of
    JavaScript's string literals, and with Node when one is on PATH);
  * every writer that puts such a value in a file: the title line, the locale,
    the base URL, the three fonts and the footer, each over every case, each
    read back from the file it wrote;
  * each writer run a second time over its own escaped output, which must
    replace the value whole rather than stop at the first `\\"` inside it.

Pure stdlib; Node is optional. Windows' PythonToolchainTests discovers and
runs it. Run with:

    python3 scripts/test_typescript_strings.py
"""
import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))
os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))
os.environ.setdefault("PLANTOIR_SUPPORT_DIR", str(REPOSITORY_ROOT / "support"))

import build_site  # noqa: E402
import contracts  # noqa: E402

RULES = contracts.load("shared-rules")["typescriptStrings"]
CASES = RULES["cases"]

# The head of Quartz v4.5.0's quartz.config.ts, as test_quartz_analytics_off.py
# carries it, with its typography block.
QUARTZ_CONFIG = '''const config: QuartzConfig = {
  configuration: {
    pageTitle: "Quartz 4",
    pageTitleSuffix: "",
    enableSPA: true,
    locale: "en-US",
    baseUrl: "quartz.jzhao.xyz",
    theme: {
      typography: {
        header: "Schibsted Grotesk",
        body: "Source Sans Pro",
        code: "IBM Plex Mono",
      },
    },
  },
}
'''

# The part of Quartz v4.5.0's Footer.tsx the build rewrites.
FOOTER_TSX = '''export default (() => {
  const Footer: QuartzComponent = ({ displayClass, cfg }: QuartzComponentProps) => {
    return (
      <footer class={`${displayClass ?? ""}`}>
        <p>Created with Quartz</p>
      </footer>
    )
  }
}) satisfies QuartzComponentConstructor
'''

NODE = shutil.which("node")

# A whole double-quoted JavaScript string literal, escapes included. Written
# out here rather than taken from build_site, so the writers are read back by
# a pattern they did not supply.
A_STRING_LITERAL = r'"(?:[^"\\\n]|\\.)*"'


def read_back(literal: str) -> str:
    """The string a JavaScript reader gets from `literal`."""
    return json.loads(literal)


def quietly(action):
    with contextlib.redirect_stdout(io.StringIO()):
        return action()


def the_value_of(text: str, key: str) -> str:
    """The literal after `key:` in `text`, read back."""
    match = re.search(key + r"\s*:\s*(" + A_STRING_LITERAL + ")", text)
    if match is None:
        raise AssertionError(f"no {key} string in:\n{text}")
    return read_back(match.group(1))


class TheRuleTests(unittest.TestCase):

    def test_every_case_is_written_as_the_contract_says(self):
        for case in CASES:
            with self.subTest(case["name"]):
                self.assertEqual(build_site.typescript_string(case["raw"]), case["written"])

    def test_every_written_literal_reads_back_as_the_value(self):
        for case in CASES:
            with self.subTest(case["name"]):
                self.assertEqual(read_back(case["written"]), case["raw"])

    def test_node_reads_every_literal_back_as_the_value(self):
        if NODE is None:
            self.skipTest("no node on PATH")
        lines = []
        for case in CASES:
            lines.append(build_site.typescript_string(case["raw"]))
            # The footer's literal exactly as the contract says it is written.
            lines.append(case["footerWritten"] if "footerWritten" in case else "null")
        program = ("const values = [" + ",\n".join(lines) + "];\n"
                   "process.stdout.write(JSON.stringify(values));\n")
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "read.mjs"
            script.write_text(program, encoding="utf-8")
            result = subprocess.run([NODE, str(script)], capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(result.stdout)
        index = 0
        for case in CASES:
            with self.subTest(case["name"]):
                self.assertEqual(values[index], case["raw"])
                if "footerWritten" in case:
                    self.assertEqual(values[index + 1], case["raw"])
            index += 2

    def test_the_patterns_match_a_whole_escaped_literal(self):
        for case in CASES:
            with self.subTest(case["name"]):
                literal = case["written"]
                match = re.fullmatch(build_site.TS_DOUBLE_QUOTED, literal)
                if "\n" in literal:
                    self.fail("a written literal never holds a raw line break")
                self.assertIsNotNone(match, literal)


class TheWritersTests(unittest.TestCase):

    def patched(self, text: str, action) -> str:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "quartz.config.ts"
            path.write_text(text, encoding="utf-8")
            quietly(lambda: action(path))
            return path.read_text(encoding="utf-8")

    def test_the_title_line_reads_back_as_the_label(self):
        for case in CASES:
            with self.subTest(case["name"]):
                def write(path):
                    build_site.update_page_title(path, case["raw"], 2, "📚", True)
                once = self.patched(QUARTZ_CONFIG, write)
                self.assertEqual(the_value_of(once, "pageTitle"), "📚 " + case["raw"] + " S2")
                twice = self.patched(once, write)
                self.assertEqual(twice, once)

    def test_the_title_line_without_a_section_marker(self):
        for case in CASES:
            with self.subTest(case["name"]):
                def write(path):
                    build_site.update_page_title(path, case["raw"], 2, "📚", False)
                text = self.patched(QUARTZ_CONFIG, write)
                self.assertEqual(the_value_of(text, "pageTitle"), "📚 " + case["raw"])

    def test_an_emoji_with_a_quote_reads_back(self):
        def write(path):
            build_site.update_page_title(path, "CLUB", 1, '"', True)
        text = self.patched(QUARTZ_CONFIG, write)
        self.assertEqual(the_value_of(text, "pageTitle"), '" CLUB S1')

    def test_the_locale_reads_back_and_is_replaced_whole(self):
        for case in CASES:
            with self.subTest(case["name"]):
                def write(path):
                    build_site.patch_quartz_locale(path, case["raw"])
                once = self.patched(QUARTZ_CONFIG, write)
                self.assertEqual(the_value_of(once, "locale"), case["raw"])

                def back(path):
                    build_site.patch_quartz_locale(path, "fr-CA")
                again = self.patched(once, back)
                self.assertEqual(again, QUARTZ_CONFIG.replace('"en-US"', '"fr-CA"'))

    def test_the_base_url_reads_back_and_is_replaced_whole(self):
        for case in CASES:
            raw = case["raw"]
            if build_site.clean_base_url(raw) != raw:
                continue  # clean_base_url trims the ends; covered by its own tests
            if raw == "":
                continue  # an empty domain is written `undefined`
            with self.subTest(case["name"]):
                def write(path):
                    build_site.patch_quartz_base_url(path, raw)
                once = self.patched(QUARTZ_CONFIG, write)
                self.assertEqual(the_value_of(once, "baseUrl"), raw)

                def back(path):
                    build_site.patch_quartz_base_url(path, "quartz.jzhao.xyz")
                self.assertEqual(self.patched(once, back), QUARTZ_CONFIG)

    def test_every_font_reads_back_and_is_replaced_whole(self):
        for case in CASES:
            with self.subTest(case["name"]):
                def write(path):
                    build_site.patch_typography_fonts(path, case["raw"], case["raw"], case["raw"])
                once = self.patched(QUARTZ_CONFIG, write)
                for key in ("header", "body", "code"):
                    self.assertEqual(the_value_of(once, key), case["raw"])

                def back(path):
                    build_site.patch_typography_fonts(path, "Schibsted Grotesk", "Source Sans Pro", "IBM Plex Mono")
                self.assertEqual(self.patched(once, back), QUARTZ_CONFIG)

    def footer_written(self, footer_tsx: str, html: str) -> str:
        with tempfile.TemporaryDirectory() as tmp:
            layout = Path(tmp) / "quartz.layout.ts"
            layout.write_text("footer: Component.Footer({ links: {} }),\n", encoding="utf-8")
            footer = Path(tmp) / "Footer.tsx"
            footer.write_text(footer_tsx, encoding="utf-8")
            quietly(lambda: build_site.inject_custom_footer_components(layout, footer, html))
            return footer.read_text(encoding="utf-8")

    def the_footer_html(self, text: str) -> str:
        match = re.search(r"__html: (" + A_STRING_LITERAL + r") \}\}", text)
        if match is None:
            raise AssertionError(f"no footer string in:\n{text}")
        return read_back(match.group(1))

    def test_the_footer_reads_back_and_is_replaced_whole(self):
        for case in CASES:
            with self.subTest(case["name"]):
                once = self.footer_written(FOOTER_TSX, case["raw"])
                self.assertEqual(self.the_footer_html(once), case["raw"])
                if "footerWritten" in case:
                    self.assertIn("__html: " + case["footerWritten"] + " }}", once)
                twice = self.footer_written(once, case["raw"])
                self.assertEqual(twice, once)
                other = self.footer_written(once, "<p>Plain</p>")
                self.assertEqual(self.the_footer_html(other), "<p>Plain</p>")
                self.assertEqual(other.count("<footer"), 1)
                self.assertEqual(other.count("</footer>"), 1)

    def test_a_footer_group_reference_is_text(self):
        text = self.footer_written(FOOTER_TSX, "<p>a\\1b</p>")
        self.assertEqual(self.the_footer_html(text), "<p>a\\1b</p>")
        self.assertNotIn("Created with Quartz", text)

    def test_the_colours_are_quoted_the_same_way(self):
        block = build_site.format_colors_block({"lightMode": {"light": "#faf8f8"}, "darkMode": {"light": "#161618"}})
        self.assertIn('light: "#faf8f8",', block)
        self.assertIn('light: "#161618",', block)


if __name__ == "__main__":
    unittest.main(verbosity=1)
