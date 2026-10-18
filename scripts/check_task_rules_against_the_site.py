#!/usr/bin/env python3
"""
The task-box rules in the contract, run against what the SITE runs (#519).

NOT named `test_*.py` on purpose, like `check_quiz_rules_against_the_site.py`:
it needs the image's Node, esbuild and Quartz itself, so it can only run
inside the container, and Windows' `PythonToolchainTests` discovers every
`scripts/test_*.py`. `verify.sh` runs it in the image:

    docker run --rm \
      --mount type=bind,source="$(pwd)/scripts/check_task_rules_against_the_site.py",target=/opt/scripts/check_task_rules_against_the_site.py,readonly \
      quartz-teacher:dev-test python3 /opt/scripts/check_task_rules_against_the_site.py

`support/quartz/plugins/transformers/taskRules.ts` (the rules) and
`plantoirTasks.ts` (the transformer - the ONLY producer of an item's id) are
bundled with esbuild, together with Quartz's own ObsidianFlavoredMarkdown
text transform and the parser the site reads a page with (unified,
remark-parse, remark-gfm, remark-rehype), and every case in
`contracts/shared-rules.json` -> `taskBoxes` is run through them in Node:

* `itemText.cases`: Quartz's text transform turns each case's Markdown into
  its `quartzReads` (or leaves it as it is, when the case has none) - the
  rewritten shapes of review F1, pinned against Quartz itself; then the
  transformer, run over the page as Quartz parses it, stamps every box with
  the case's ids in order, each `taskItemId(taskItemText(line))` of the
  item's line, and the item's text read from that line is the case's;
* `itemId.cases` and `itemId.tickedOrNot` through taskItemId (and
  taskItemText);
* `key.cases` through siteRootFrom and taskKey;
* `readApi.cases` through readTicks, with a store that throws for the case
  that says so.

verify.sh 6l reads the same cases back from a real build, and
browser-checks/task_boxes.mjs ticks them in a browser.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

TRANSFORMERS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers"
RULE_TS = TRANSFORMERS / "taskRules.ts"
TRANSFORMER_TS = TRANSFORMERS / "plantoirTasks.ts"
OFM_TS = toolchain_paths.QUARTZ_DIR / "quartz" / "plugins" / "transformers" / "ofm.ts"
NODE_MODULES = toolchain_paths.QUARTZ_DIR / "node_modules"

# Bundles the runner with esbuild's own API (from Quartz's node_modules), so
# Quartz's files can be imported with their browser scripts and styles
# stubbed out: only the text transform is wanted from them.
BUILD = r"""
import { createRequire } from "module"
const require = createRequire("NODE_MODULES/")
const { build } = require("esbuild")
await build({
  entryPoints: [process.argv[2]], outfile: process.argv[3], bundle: true, platform: "node", format: "esm",
  logLevel: "error", nodePaths: ["NODE_MODULES"], loader: { ".scss": "text" }, external: ["lightningcss"],
  banner: { js: 'import { createRequire } from "module"; const require = createRequire(import.meta.url);' },
  plugins: [{ name: "stub", setup(builder) {
    builder.onResolve({ filter: /\.inline(\.ts)?$/ }, (args) => ({ path: args.path, namespace: "stub" }))
    builder.onLoad({ filter: /.*/, namespace: "stub" }, () => ({ contents: 'export default ""', loader: "js" }))
  } }],
})
"""

RUNNER = r"""
import { readFileSync } from "fs"
import { unified } from "unified"
import remarkParse from "remark-parse"
import remarkGfm from "remark-gfm"
import remarkRehype from "remark-rehype"
import { VFile } from "vfile"
import { ObsidianFlavoredMarkdown } from "OFM_TS"
import { PlantoirTasks } from "TRANSFORMER_TS"
import { readTicks, siteRootFrom, taskItemId, taskItemText, taskKey } from "RULE_TS"

const rules = JSON.parse(readFileSync(process.argv[2], "utf-8"))
const failures = []
let count = 0
const ofm = ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false })
const tasks = PlantoirTasks()
const TASK_LINE = /^(?:[ \t]*>)*[ \t]*(?:(?:[-*+]|[0-9]{1,9}[.)])[ \t]+)+\[[ xX]\]/

// The page as Quartz builds it: the whole file trimmed, then the text
// transform, then the parser, then the transformer's html stage.
function stamped(markdown, slug) {
  const value = ofm.textTransform({}, markdown.trim())
  const processor = unified().use(remarkParse).use(remarkGfm).use(remarkRehype)
  const file = new VFile({ value })
  file.data.slug = slug
  const tree = processor.runSync(processor.parse(file), file)
  for (const plugin of tasks.htmlPlugins()) plugin()(tree, file)
  const boxes = []
  const visit = (node, label) => {
    if (node.type === "element" && node.tagName === "input" && node.properties?.type === "checkbox") {
      boxes.push({ id: node.properties.dataTaskItem, page: node.properties.dataTaskPage,
                   disabled: node.properties.disabled === true || node.properties.disabled === "",
                   labelled: label, className: node.properties.className })
    }
    const inLabel = label || (node.type === "element" && node.tagName === "label")
    for (const child of node.children ?? []) visit(child, inLabel)
  }
  visit(tree, false)
  return { value, boxes }
}

for (const c of rules.itemText.cases) {
  count += 1
  const reads = ofm.textTransform({}, c.markdown)
  const expected = c.quartzReads ?? c.markdown
  if (reads !== expected) failures.push(`itemText ${c.name}: Quartz reads ${JSON.stringify(reads)}, the contract says ${JSON.stringify(expected)}`)
  const texts = expected.split("\n").filter((line) => TASK_LINE.test(line)).map((line) => taskItemText(line))
  const want = c.items.map((item) => item.text)
  if (JSON.stringify(texts) !== JSON.stringify(want)) failures.push(`itemText ${c.name}: ${JSON.stringify(texts)}, expected ${JSON.stringify(want)}`)
  for (const item of c.items) {
    if (taskItemId(item.text) !== item.id) failures.push(`itemText ${c.name}: ${JSON.stringify(item.text)} is ${taskItemId(item.text)}, the contract says ${item.id}`)
  }
  const { boxes } = stamped(c.markdown, "Task-Fixture")
  const ids = boxes.map((box) => box.id)
  if (JSON.stringify(ids) !== JSON.stringify(c.items.map((item) => item.id))) {
    failures.push(`itemText ${c.name}: the transformer stamped ${JSON.stringify(ids)}, expected ${JSON.stringify(c.items.map((item) => item.id))}`)
  }
  for (const box of boxes) {
    if (box.disabled || !box.labelled || box.page !== "Task-Fixture" || JSON.stringify(box.className) !== '["plantoir-task"]') {
      failures.push(`itemText ${c.name}: a box was not made tickable: ${JSON.stringify(box)}`)
    }
  }
}

for (const c of rules.itemId.cases) {
  count += 1
  if (taskItemId(c.text) !== c.id) failures.push(`itemId ${JSON.stringify(c.text)}: ${taskItemId(c.text)}, the contract says ${c.id}`)
}
count += 1
for (const line of rules.itemId.tickedOrNot.lines) {
  const id = taskItemId(taskItemText(line))
  if (id !== rules.itemId.tickedOrNot.id) failures.push(`tickedOrNot ${JSON.stringify(line)}: ${id}`)
}

for (const c of rules.key.cases) {
  count += 1
  const root = siteRootFrom(c.pageSlug, c.href)
  if (root !== c.siteRoot) failures.push(`key ${c.href}: site root ${root}, the contract says ${c.siteRoot}`)
  const key = taskKey(c.siteRoot, c.pageSlug, c.itemId)
  if (key !== c.key) failures.push(`key ${c.href}: ${key}, the contract says ${c.key}`)
}

for (const c of rules.readApi.cases) {
  count += 1
  const store = c.throws
    ? { getItem() { throw new Error("refused") } }
    : { getItem: (key) => (key in c.stored ? c.stored[key] : null) }
  const got = readTicks(c.siteRoot, c.pageSlug, c.itemIds, store)
  if (JSON.stringify(got) !== JSON.stringify(c.expect)) failures.push(`readApi ${c.name}: ${JSON.stringify(got)}, expected ${JSON.stringify(c.expect)}`)
}

console.log(JSON.stringify({ count, failures }))
"""


def run_the_rules_in_node(folder: Path) -> list:
    builder = folder / "build.mjs"
    builder.write_text(BUILD.replace("NODE_MODULES", str(NODE_MODULES)), encoding="utf-8")
    entry = folder / "runner.mjs"
    entry.write_text(RUNNER.replace("RULE_TS", str(RULE_TS)).replace("TRANSFORMER_TS", str(TRANSFORMER_TS))
                     .replace("OFM_TS", str(OFM_TS)), encoding="utf-8")
    bundle = folder / "runner.bundle.mjs"
    subprocess.run(["node", str(builder), str(entry), str(bundle)], check=True, env=dict(os.environ))
    rules = folder / "taskBoxes.json"
    rules.write_text(json.dumps(contracts.section("shared-rules", "taskBoxes")), encoding="utf-8")
    output = subprocess.run(["node", str(bundle), str(rules)], check=True, capture_output=True, text=True).stdout
    result = json.loads(output.strip().splitlines()[-1])
    print(f"taskRules.ts and plantoirTasks.ts: {result['count']} contract cases run in Node over Quartz's own text transform and parser")
    return result["failures"]


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        failures = run_the_rules_in_node(Path(name))
    for failure in failures:
        print("FAIL " + failure)
    if failures:
        return 1
    print("OK: the task-box rules in the contract hold in the site's own code")
    return 0


if __name__ == "__main__":
    sys.exit(main())
