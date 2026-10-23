#!/usr/bin/env python3
"""
Font variables quote one family at a time (#629).

Quartz v4.5.0's joinStyles wrote `--bodyFont: "<choice>", <fallback>`,
quoting the whole typography choice. The "System fonts" choice is stored as
"Helvetica, Arial", so CSS read ONE family of that name, which exists
nowhere, and the browser fell through to the fallback's system-ui (San
Francisco on a Mac, Segoe UI on Windows). `patch_font_variable_stacks`
quotes each family on its own and gives that choice the fallback alone, so
those sites keep the face they always had; a single family comes out byte
for byte as before, so a Google-font site's stylesheet does not change.

The patch runs against an embedded copy of Quartz v4.5.0's own
quartz/util/theme.ts (the file every section's scaffold starts from), with
and without C2-19's `patch_google_font_href`, which edits the same file.

The generated-CSS case runs the patched TypeScript itself, and needs a
`node` of 22.6 or later on PATH (for --experimental-strip-types). Without
one it SKIPS, saying why. That is deliberate: the rule is not written a
second time in Python just to test it. On the mac, verify.sh carries the
real check, reading the font variables out of the Example Course's built
index.css; on Windows, PythonToolchainTests counts a skipped case as a pass,
so a machine without node is not a red suite, and not a proof either.

Stdlib only (build_site imports python-frontmatter only if it is there), so
Windows' PythonToolchainTests discovers and runs it too.

Run with:

    python3 scripts/test_font_variables.py
"""
import contextlib
import io
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import build_site

# Quartz v4.5.0's quartz/util/theme.ts, byte for byte as the image's scaffold
# carries it (measured in quartz-teacher:dev-test with
# `docker run --rm quartz-teacher:dev-test cat /opt/quartz/quartz/util/theme.ts`,
# 2026-10-23). Raw, because it carries backslashes of its own.
THEME_TS_V450 = r'''export interface ColorScheme {
  light: string
  lightgray: string
  gray: string
  darkgray: string
  dark: string
  secondary: string
  tertiary: string
  highlight: string
  textHighlight: string
}

interface Colors {
  lightMode: ColorScheme
  darkMode: ColorScheme
}

export type FontSpecification =
  | string
  | {
      name: string
      weights?: number[]
      includeItalic?: boolean
    }

export interface Theme {
  typography: {
    header: FontSpecification
    body: FontSpecification
    code: FontSpecification
  }
  cdnCaching: boolean
  colors: Colors
  fontOrigin: "googleFonts" | "local"
}

export type ThemeKey = keyof Colors

const DEFAULT_SANS_SERIF =
  'system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol"'
const DEFAULT_MONO = "ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace"

export function getFontSpecificationName(spec: FontSpecification): string {
  if (typeof spec === "string") {
    return spec
  }

  return spec.name
}

function formatFontSpecification(type: "header" | "body" | "code", spec: FontSpecification) {
  if (typeof spec === "string") {
    spec = { name: spec }
  }

  const defaultIncludeWeights = type === "header" ? [400, 700] : [400, 600]
  const defaultIncludeItalic = type === "body"
  const weights = spec.weights ?? defaultIncludeWeights
  const italic = spec.includeItalic ?? defaultIncludeItalic

  const features: string[] = []
  if (italic) {
    features.push("ital")
  }

  if (weights.length > 1) {
    const weightSpec = italic
      ? weights
          .flatMap((w) => [`0,${w}`, `1,${w}`])
          .sort()
          .join(";")
      : weights.join(";")

    features.push(`wght@${weightSpec}`)
  }

  if (features.length > 0) {
    return `${spec.name}:${features.join(",")}`
  }

  return spec.name
}

export function googleFontHref(theme: Theme) {
  const { code, header, body } = theme.typography
  const headerFont = formatFontSpecification("header", header)
  const bodyFont = formatFontSpecification("body", body)
  const codeFont = formatFontSpecification("code", code)

  return `https://fonts.googleapis.com/css2?family=${bodyFont}&family=${headerFont}&family=${codeFont}&display=swap`
}

export interface GoogleFontFile {
  url: string
  filename: string
  extension: string
}

export async function processGoogleFonts(
  stylesheet: string,
  baseUrl: string,
): Promise<{
  processedStylesheet: string
  fontFiles: GoogleFontFile[]
}> {
  const fontSourceRegex = /url\((https:\/\/fonts.gstatic.com\/s\/[^)]+\.(woff2|ttf))\)/g
  const fontFiles: GoogleFontFile[] = []
  let processedStylesheet = stylesheet

  let match
  while ((match = fontSourceRegex.exec(stylesheet)) !== null) {
    const url = match[1]
    const [filename, extension] = url.split("/").pop()!.split(".")
    const staticUrl = `https://${baseUrl}/static/fonts/${filename}.${extension}`

    processedStylesheet = processedStylesheet.replace(url, staticUrl)
    fontFiles.push({ url, filename, extension })
  }

  return { processedStylesheet, fontFiles }
}

export function joinStyles(theme: Theme, ...stylesheet: string[]) {
  return `
${stylesheet.join("\n\n")}

:root {
  --light: ${theme.colors.lightMode.light};
  --lightgray: ${theme.colors.lightMode.lightgray};
  --gray: ${theme.colors.lightMode.gray};
  --darkgray: ${theme.colors.lightMode.darkgray};
  --dark: ${theme.colors.lightMode.dark};
  --secondary: ${theme.colors.lightMode.secondary};
  --tertiary: ${theme.colors.lightMode.tertiary};
  --highlight: ${theme.colors.lightMode.highlight};
  --textHighlight: ${theme.colors.lightMode.textHighlight};

  --headerFont: "${getFontSpecificationName(theme.typography.header)}", ${DEFAULT_SANS_SERIF};
  --bodyFont: "${getFontSpecificationName(theme.typography.body)}", ${DEFAULT_SANS_SERIF};
  --codeFont: "${getFontSpecificationName(theme.typography.code)}", ${DEFAULT_MONO};
}

:root[saved-theme="dark"] {
  --light: ${theme.colors.darkMode.light};
  --lightgray: ${theme.colors.darkMode.lightgray};
  --gray: ${theme.colors.darkMode.gray};
  --darkgray: ${theme.colors.darkMode.darkgray};
  --dark: ${theme.colors.darkMode.dark};
  --secondary: ${theme.colors.darkMode.secondary};
  --tertiary: ${theme.colors.darkMode.tertiary};
  --highlight: ${theme.colors.darkMode.highlight};
  --textHighlight: ${theme.colors.darkMode.textHighlight};
}
`
}
'''

DEFAULT_SANS_SERIF = (
    'system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, '
    '"Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol"'
)
DEFAULT_MONO = "ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace"

# The regular expression the helper must carry exactly. Written into an
# ordinary Python string it would lose a backslash and break every build.
INTENDED_REGEX = r'.replace(/["\\]/g, "")'


def run_quietly(function, *arguments):
    """Run a patch and return what it printed."""
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        function(*arguments)
    return printed.getvalue()


def google_font_href_block(text):
    """The googleFontHref function, from its comment to its closing brace."""
    start = text.index("// A CSS font stack")
    end = text.index("export interface GoogleFontFile")
    return text[start:end]


def node_that_strips_types():
    """The path of a node of 22.6 or later, or None."""
    node = shutil.which("node")
    if node is None:
        return None
    try:
        version = subprocess.run([node, "--version"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.match(r"v(\d+)\.(\d+)", version.strip())
    if match is None:
        return None
    major = int(match.group(1))
    minor = int(match.group(2))
    if major > 22 or (major == 22 and minor >= 6):
        return node
    return None


HARNESS_MTS = '''import { readFileSync } from "node:fs"
import { pathToFileURL } from "node:url"
const theme = await import(pathToFileURL(process.argv[2]).href)
const choices = JSON.parse(readFileSync(process.argv[3], "utf8"))
const colors = { light: "#fff", lightgray: "#eee", gray: "#999", darkgray: "#333", dark: "#000",
  secondary: "#00f", tertiary: "#0f0", highlight: "#ff0", textHighlight: "#ff0" }
const results = []
for (const choice of choices) {
  const typography = { header: choice.header, body: choice.body, code: choice.code }
  results.push(theme.joinStyles({ typography, colors: { lightMode: colors, darkMode: colors } }))
}
console.log(JSON.stringify(results))
'''


class FontVariablePatchTests(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.theme_ts = self.folder / "theme.ts"
        self.head_tsx = self.folder / "Head.tsx"
        self.theme_ts.write_text(THEME_TS_V450, encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_the_embedded_copy_is_quartz_v450(self):
        for line in build_site._FONT_VARIABLE_LINES_V450:
            self.assertEqual(THEME_TS_V450.count(line), 1, line)

    def test_after_the_google_patch_the_variables_call_the_helper(self):
        run_quietly(build_site.patch_google_font_href, self.theme_ts, self.head_tsx)
        google_only = self.theme_ts.read_text(encoding="utf-8")
        printed = run_quietly(build_site.patch_font_variable_stacks, self.theme_ts)
        patched = self.theme_ts.read_text(encoding="utf-8")
        self.assertIn("✅", printed)
        for line in build_site._FONT_VARIABLE_LINES_PATCHED:
            self.assertEqual(patched.count(line), 1, line)
        self.assertNotIn('"${getFontSpecificationName(', patched)
        self.assertEqual(google_font_href_block(patched), google_font_href_block(google_only))
        self.assertEqual(patched.count("function cssFontStack"), 1)
        self.assertEqual(patched.count("export function joinStyles"), 1)

    def test_either_order_gives_the_same_file(self):
        run_quietly(build_site.patch_google_font_href, self.theme_ts, self.head_tsx)
        run_quietly(build_site.patch_font_variable_stacks, self.theme_ts)
        google_first = self.theme_ts.read_text(encoding="utf-8")

        self.theme_ts.write_text(THEME_TS_V450, encoding="utf-8")
        run_quietly(build_site.patch_font_variable_stacks, self.theme_ts)
        run_quietly(build_site.patch_google_font_href, self.theme_ts, self.head_tsx)
        fonts_first = self.theme_ts.read_text(encoding="utf-8")
        self.assertEqual(google_first, fonts_first)

    def test_the_helper_carries_the_regular_expression_as_written(self):
        run_quietly(build_site.patch_font_variable_stacks, self.theme_ts)
        patched = self.theme_ts.read_text(encoding="utf-8")
        self.assertIn(INTENDED_REGEX, patched)
        # What an ordinary Python string would have written instead.
        self.assertNotIn('.replace(/["\\]/g', patched)

    def test_a_second_run_changes_nothing(self):
        run_quietly(build_site.patch_font_variable_stacks, self.theme_ts)
        once = self.theme_ts.read_text(encoding="utf-8")
        printed = run_quietly(build_site.patch_font_variable_stacks, self.theme_ts)
        self.assertEqual(self.theme_ts.read_text(encoding="utf-8"), once)
        self.assertIn("no change", printed)

    def test_a_changed_shape_is_left_alone_with_a_warning(self):
        changed = THEME_TS_V450.replace(build_site._FONT_VARIABLE_LINES_V450[1], "  --bodyFont: inherit;")
        self.theme_ts.write_text(changed, encoding="utf-8")
        printed = run_quietly(build_site.patch_font_variable_stacks, self.theme_ts)
        self.assertEqual(self.theme_ts.read_text(encoding="utf-8"), changed)
        self.assertIn("⚠️ joinStyles not in the expected shape", printed)


class GeneratedFontVariableTests(unittest.TestCase):
    """What the patched joinStyles actually writes, run under node."""

    @classmethod
    def setUpClass(cls):
        cls.node = node_that_strips_types()

    def setUp(self):
        if self.node is None:
            self.skipTest("no node 22.6 or later on PATH to run theme.ts; verify.sh checks the built index.css")
        self.folder = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def stylesheets(self, theme_text, choices):
        """joinStyles' output for each choice, from the given theme.ts text."""
        theme_file = self.folder / "theme.mts"
        theme_file.write_text(theme_text, encoding="utf-8")
        harness = self.folder / "harness.mts"
        harness.write_text(HARNESS_MTS, encoding="utf-8")
        choices_file = self.folder / "choices.json"
        choices_file.write_text(json.dumps(choices), encoding="utf-8")
        completed = subprocess.run(
            [self.node, "--experimental-strip-types", "--no-warnings", str(harness), str(theme_file), str(choices_file)],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def patched_theme(self):
        theme_file = self.folder / "theme.ts"
        theme_file.write_text(THEME_TS_V450, encoding="utf-8")
        run_quietly(build_site.patch_google_font_href, theme_file, self.folder / "Head.tsx")
        run_quietly(build_site.patch_font_variable_stacks, theme_file)
        return theme_file.read_text(encoding="utf-8")

    def test_the_system_font_choice_gets_the_system_stack_first(self):
        system = {"header": "Helvetica, Arial", "body": "Helvetica, Arial", "code": "IBM Plex Mono"}
        css = self.stylesheets(self.patched_theme(), [system])[0]
        self.assertNotIn('"Helvetica, Arial"', css)
        self.assertIn("  --headerFont: " + DEFAULT_SANS_SERIF + ";\n", css)
        self.assertIn("  --bodyFont: " + DEFAULT_SANS_SERIF + ";\n", css)
        self.assertIn('  --codeFont: "IBM Plex Mono", ' + DEFAULT_MONO + ";\n", css)

    def test_a_google_font_site_is_byte_for_byte_unchanged(self):
        choices = [
            {"header": "Playfair Display", "body": "Source Sans 3", "code": "JetBrains Mono"},
            {"header": "Schibsted Grotesk", "body": "Schibsted Grotesk", "code": "IBM Plex Mono"},
            {"header": "Archivo", "body": "Noto Sans", "code": "Ubuntu Mono"},
        ]
        before = self.stylesheets(THEME_TS_V450, choices)
        after = self.stylesheets(self.patched_theme(), choices)
        self.assertEqual(after, before)

    def test_any_other_stack_is_quoted_one_family_at_a_time(self):
        choices = [
            {"header": "Georgia, serif", "body": "DM Sans, Inter", "code": "Menlo, monospace"},
            {"header": "", "body": '"Inter"', "code": "system-ui"},
        ]
        stylesheets = self.stylesheets(self.patched_theme(), choices)
        self.assertIn('  --headerFont: "Georgia", serif, ' + DEFAULT_SANS_SERIF + ";\n", stylesheets[0])
        self.assertIn('  --bodyFont: "DM Sans", "Inter", ' + DEFAULT_SANS_SERIF + ";\n", stylesheets[0])
        self.assertIn('  --codeFont: "Menlo", monospace, ' + DEFAULT_MONO + ";\n", stylesheets[0])
        self.assertIn("  --headerFont: " + DEFAULT_SANS_SERIF + ";\n", stylesheets[1])
        self.assertIn('  --bodyFont: "Inter", ' + DEFAULT_SANS_SERIF + ";\n", stylesheets[1])
        self.assertIn("  --codeFont: system-ui, " + DEFAULT_MONO + ";\n", stylesheets[1])


if __name__ == "__main__":
    unittest.main()
