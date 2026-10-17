#!/usr/bin/env python3
"""
KaTeX served by the site itself (#494): the copy into a section's
quartz/static/katex, and the patch that points every page at it instead of
cdn.jsdelivr.net.

`install_katex_assets` runs against a stand-in for Quartz's
node_modules/katex, and `patch_katex_local` against an embedded copy of
Quartz v4.5.0's own latex.ts (the file every section's scaffold starts from),
before and after the mhchem patch that also edits it. What the real image
carries, and what a real site links, is checked by verify.sh (§4 pins, 6j).

Stdlib only (build_site imports python-frontmatter only if it is there), so
Windows' PythonToolchainTests discovers and runs it too.

Run with:

    python3 scripts/test_katex_assets.py
"""
import shutil
import tempfile
import unittest
from pathlib import Path

import build_site

# Quartz v4.5.0's quartz/plugins/transformers/latex.ts, byte for byte as the
# image's scaffold carries it (measured in quartz-teacher:dev-test, 2026-10-17).
LATEX_TS_V450 = '''import remarkMath from "remark-math"
import rehypeKatex from "rehype-katex"
import rehypeMathjax from "rehype-mathjax/svg"
//@ts-ignore
import rehypeTypst from "@myriaddreamin/rehype-typst"
import { QuartzTransformerPlugin } from "../types"
import { KatexOptions } from "katex"
import { Options as MathjaxOptions } from "rehype-mathjax/svg"
//@ts-ignore
import { Options as TypstOptions } from "@myriaddreamin/rehype-typst"

interface Options {
  renderEngine: "katex" | "mathjax" | "typst"
  customMacros: MacroType
  katexOptions: Omit<KatexOptions, "macros" | "output">
  mathJaxOptions: Omit<MathjaxOptions, "macros">
  typstOptions: TypstOptions
}

interface MacroType {
  [key: string]: string
}

export const Latex: QuartzTransformerPlugin<Partial<Options>> = (opts) => {
  const engine = opts?.renderEngine ?? "katex"
  const macros = opts?.customMacros ?? {}
  return {
    name: "Latex",
    markdownPlugins() {
      return [remarkMath]
    },
    htmlPlugins() {
      switch (engine) {
        case "katex": {
          return [[rehypeKatex, { output: "html", macros, ...(opts?.katexOptions ?? {}) }]]
        }
        case "typst": {
          return [[rehypeTypst, opts?.typstOptions ?? {}]]
        }
        case "mathjax": {
          return [[rehypeMathjax, { macros, ...(opts?.mathJaxOptions ?? {}) }]]
        }
        default: {
          return [[rehypeMathjax, { macros, ...(opts?.mathJaxOptions ?? {}) }]]
        }
      }
    },
    externalResources() {
      switch (engine) {
        case "katex":
          return {
            css: [{ content: "https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" }],
            js: [
              {
                // fix copy behaviour: https://github.com/KaTeX/KaTeX/blob/main/contrib/copy-tex/README.md
                src: "https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/copy-tex.min.js",
                loadTime: "afterDOMReady",
                contentType: "external",
              },
            ],
          }
      }
    },
  }
}
'''

FACES = ["KaTeX_AMS-Regular", "KaTeX_Main-Regular", "KaTeX_Math-Italic"]


def stand_in_katex(root: Path) -> Path:
    """A node_modules/katex holding what the real package holds that matters here."""
    katex = root / "node_modules" / "katex"
    (katex / "dist" / "contrib").mkdir(parents=True)
    (katex / "dist" / "fonts").mkdir(parents=True)
    (katex / "dist" / "katex.min.css").write_text(".katex{font:normal 1.21em KaTeX_Main}\n", encoding="utf-8")
    (katex / "dist" / "katex.min.js").write_text("/* not carried */\n", encoding="utf-8")
    (katex / "dist" / "contrib" / "copy-tex.min.js").write_text("/* copy-tex */\n", encoding="utf-8")
    (katex / "dist" / "contrib" / "mhchem.min.js").write_text("/* not carried */\n", encoding="utf-8")
    for face in FACES:
        for extension in ("woff2", "woff", "ttf"):
            (katex / "dist" / "fonts" / f"{face}.{extension}").write_bytes(f"{face}.{extension}".encode())
    (katex / "LICENSE").write_text("The MIT License (MIT)\n", encoding="utf-8")
    return katex


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-katex-"))
        self.katex = stand_in_katex(self.folder)
        self.output = self.folder / "section1"
        (self.output / "quartz" / "static").mkdir(parents=True)
        self.said = []

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def install(self):
        return build_site.install_katex_assets(self.output, katex_dir=self.katex, printer=self.said.append)

    def carried(self):
        target = self.output / "quartz" / "static" / "katex"
        return sorted(str(path.relative_to(target)) for path in target.rglob("*") if path.is_file())

    def test_exactly_the_stylesheet_copy_tex_the_woff2_faces_and_the_licence(self):
        self.install()
        self.assertEqual(self.carried(), sorted(
            ["LICENSE", "contrib/copy-tex.min.js", "katex.min.css"] + [f"fonts/{face}.woff2" for face in FACES]))
        css = self.output / "quartz" / "static" / "katex" / "katex.min.css"
        self.assertEqual(css.read_bytes(), (self.katex / "dist" / "katex.min.css").read_bytes())

    def test_a_second_build_copies_nothing(self):
        self.assertEqual(self.install(), 3 + len(FACES))
        self.assertEqual(self.install(), 0)

    def test_a_stale_file_is_removed(self):
        self.install()
        stale = self.output / "quartz" / "static" / "katex" / "fonts" / "KaTeX_Old.woff"
        stale.write_bytes(b"old")
        self.install()
        self.assertFalse(stale.exists())

    def test_a_missing_package_warns_and_never_raises(self):
        shutil.rmtree(self.katex)
        self.assertEqual(self.install(), 0)
        self.assertEqual(len(self.said), 1, self.said)
        self.assertNotIn("{", self.said[0])


class PatchTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-latex-"))
        self.latex = self.folder / "latex.ts"
        self.latex.write_text(LATEX_TS_V450, encoding="utf-8")
        self.said = []

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def patch(self):
        return build_site.patch_katex_local(self.latex, printer=self.said.append)

    def text(self):
        return self.latex.read_text(encoding="utf-8")

    def test_the_patched_file_names_no_cdn_and_links_the_sites_own_copy(self):
        self.assertTrue(self.patch())
        text = self.text()
        self.assertNotIn("cdn.jsdelivr.net", text)
        self.assertIn(build_site.KATEX_LOCAL_MARKER, text)
        self.assertIn('"static/katex/katex.min.css"', text)
        self.assertIn('"static/katex/contrib/copy-tex.min.js"', text)
        self.assertIn('"spa-preserve": true', text)
        self.assertIn("additionalHead", text)
        self.assertIn("externalResources(ctx)", text)
        # The rendering half is untouched.
        self.assertIn('return [[rehypeKatex, { output: "html", macros, ...(opts?.katexOptions ?? {}) }]]', text)

    def test_patching_twice_changes_nothing(self):
        self.patch()
        once = self.text()
        self.assertFalse(self.patch())
        self.assertEqual(self.text(), once)

    def test_it_works_after_the_mhchem_patch(self):
        build_site.patch_katex_mhchem(self.latex)
        self.assertTrue(self.patch())
        self.assertIn("katex/contrib/mhchem", self.text())
        self.assertNotIn("cdn.jsdelivr.net", self.text())

    def test_the_mhchem_patch_works_after_it(self):
        self.patch()
        build_site.patch_katex_mhchem(self.latex)
        self.assertIn("katex/contrib/mhchem", self.text())
        self.assertIn(build_site.KATEX_LOCAL_MARKER, self.text())

    def test_a_file_that_changed_shape_is_left_alone_and_said(self):
        changed = LATEX_TS_V450.replace("katex@0.16.11", "katex@0.16.99")
        self.latex.write_text(changed, encoding="utf-8")
        self.assertFalse(self.patch())
        self.assertEqual(self.text(), changed)
        self.assertEqual(len(self.said), 1, self.said)

    def test_a_missing_file_is_said_and_never_raises(self):
        self.latex.unlink()
        self.assertFalse(self.patch())
        self.assertEqual(len(self.said), 1)


if __name__ == "__main__":
    unittest.main()
