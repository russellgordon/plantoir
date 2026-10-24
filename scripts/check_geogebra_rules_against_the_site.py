#!/usr/bin/env python3
"""
The GeoGebra fence rules in the contract, run through the SITE's own
Markdown reader (#578).

NOT named `test_*.py` on purpose, like check_figure_rules_against_the_site.py:
it needs the image's Node and Quartz's own node_modules, so it can only run
inside the container (Windows' PythonToolchainTests discovers every
`scripts/test_*.py`). verify.sh runs it in the image.

What scripts/test_geogebra.py cannot reach without Node: the site's
transformer (support/quartz/plugins/transformers/plantoirGeoGebra.ts) finds a
sketch by `keyOf(code.value)` - figureRules.js on the mdast code node the
site's Markdown reader made - while the build keys the same fence by
figures.key_of on markdown_code's body. The two agree only if both read the
same body out of a callout, a list item, tildes and Windows line endings.
So every geogebraFences.keys case (and every fences case's count and line)
is read here by mdast-util-from-markdown, with GitHub's extensions, from
Quartz's own node_modules - the reader under remark-parse - and hashed by
the site's figureRules.js.

Every page goes through the quizzes' own text hook first
(quizRules.nestedTitlesOwnTheirLine, bundled from quizRules.ts with the
image's esbuild), as the site's build does before any Markdown is read: it
adds a line after a nested callout's title inside a quiz, and a fence in a
quiz's explanation must keep its key through it (#578 stage 5). A page with
no quiz comes back from it unchanged.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

RULES_JS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "figureRules.js"
QUIZ_RULES_TS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "quizRules.ts"
ESBUILD = toolchain_paths.QUARTZ_DIR / "node_modules" / "esbuild" / "bin" / "esbuild"

RUNNER = r"""
import { readFileSync } from "fs"
import { pathToFileURL } from "url"
const modules = process.argv[4]
const rules = await import(pathToFileURL(process.argv[2]).href)
const { fromMarkdown } = await import(pathToFileURL(modules + "/mdast-util-from-markdown/index.js").href)
const { gfm } = await import(pathToFileURL(modules + "/micromark-extension-gfm/index.js").href)
const { gfmFromMarkdown } = await import(pathToFileURL(modules + "/mdast-util-gfm/index.js").href)
const block = JSON.parse(readFileSync(process.argv[3], "utf-8"))
const { nestedTitlesOwnTheirLine } = await import(pathToFileURL(process.argv[5]).href)
const codes = (written) => {
  const page = nestedTitlesOwnTheirLine(written)
  const tree = fromMarkdown(page, { extensions: [gfm()], mdastExtensions: [gfmFromMarkdown()] })
  const found = []
  const walk = (node) => {
    if (node.type === "code" && (node.lang ?? "") === "geogebra") found.push(node)
    for (const child of node.children ?? []) walk(child)
  }
  walk(tree)
  return found
}
const failures = []
for (const c of block.keys.cases) {
  const found = codes(c.page)
  if (found.length !== 1) { failures.push(`keys ${c.name}: the site reads ${found.length} sketches`); continue }
  const key = rules.keyOf(found[0].value)
  if (key !== c.key) failures.push(`keys ${c.name}: the site's key ${key.slice(0, 12)}, the contract's ${c.key.slice(0, 12)}`)
}
for (const c of block.fences.cases) {
  const found = codes(c.page).map((node, index) => ({ block: index + 1, line: node.position.start.line }))
  if (JSON.stringify(found) !== JSON.stringify(c.found)) failures.push(`fences ${c.name}: the site reads ${JSON.stringify(found)}`)
}
console.log(JSON.stringify(failures))
"""


def main() -> int:
    block = contracts.section("shared-rules", "geogebraFences")
    failures = []
    work = Path(tempfile.mkdtemp(prefix="plantoir-geogebra-rules-"))
    try:
        (work / "package.json").write_text('{"type": "module"}\n', encoding="utf-8")
        shutil.copyfile(RULES_JS, work / "figureRules.js")
        (work / "runner.mjs").write_text(RUNNER, encoding="utf-8")
        (work / "block.json").write_text(json.dumps(block), encoding="utf-8")
        (work / "quizHook.ts").write_text(
            f'export {{ nestedTitlesOwnTheirLine }} from {json.dumps(str(QUIZ_RULES_TS))}\n', encoding="utf-8")
        subprocess.run([str(ESBUILD), str(work / "quizHook.ts"), "--bundle", "--format=esm", "--platform=node",
                        f"--outfile={work / 'quizHook.mjs'}", "--log-level=warning"], check=True,
                       env=dict(os.environ, NODE_PATH=str(toolchain_paths.QUARTZ_DIR / "node_modules")))
        said = subprocess.run(["node", str(work / "runner.mjs"), str(work / "figureRules.js"),
                               str(work / "block.json"), str(toolchain_paths.QUARTZ_DIR / "node_modules"),
                               str(work / "quizHook.mjs")],
                              capture_output=True, text=True)
        if said.returncode != 0:
            failures.append("the rules did not run in Node: " + said.stderr.strip()[-400:])
        else:
            failures.extend(json.loads(said.stdout.strip().splitlines()[-1]))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for failure in failures:
        print("   " + failure)
    cases = len(block["keys"]["cases"]) + len(block["fences"]["cases"])
    print(f"{'FAIL' if failures else 'PASS'}: geogebraFences keys and fences through the site's own Markdown "
          f"reader ({cases} cases, {len(failures)} problem(s))")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
