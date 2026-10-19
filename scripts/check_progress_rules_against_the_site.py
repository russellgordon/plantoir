#!/usr/bin/env python3
"""
The My Progress rules in the contract, run against what the SITE runs (#545).

NOT named `test_*.py` on purpose, like `check_task_rules_against_the_site.py`:
it needs the image's Node, esbuild and Quartz itself (and python-frontmatter
for the build's date pass), so it can only run inside the container, and
Windows' `PythonToolchainTests` discovers every `scripts/test_*.py`.
`verify.sh` runs it in the image:

    docker run --rm \\
      --mount type=bind,source="$(pwd)/scripts/check_progress_rules_against_the_site.py",target=/opt/scripts/check_progress_rules_against_the_site.py,readonly \\
      quartz-teacher:dev-test python3 /opt/scripts/check_progress_rules_against_the_site.py

`support/quartz/plugins/emitters/progressRules.ts` (the rules) and
`plantoirProgress.ts` (the emitter) are bundled with esbuild, together with
the transformers a page goes through on the site - Quartz's own FrontMatter,
ObsidianFlavoredMarkdown and GitHubFlavoredMarkdown, then PlantoirQuizzes and
PlantoirTasks (the only producer of an item's id), then Quartz's Latex (since
#545's fixes round: a `$$` block is maths there) - and every case in
`contracts/shared-rules.json` -> `myProgress` the site reads is run through
them in Node:

* `headings.cases` through normalisedHeading, and `headings.markupCases`
  through the whole page: the heading counts exactly when the case says;
* `sections.cases` and `gate.cases` through the whole page, then
  countedItems: exactly the case's items, ids and ticks - the build's own
  gate reads the same cases in scripts/test_my_progress.py (#545 plan review
  F3: both readings, every case);
* `rollUp.cases` through rollUp, with a store that throws where a case says;
* `sidebar.cases` through pinnedOrder;
* `grouping.cases`: each case written out as a section's pages, the build's
  own date pass and plan (build_site._prepare_my_progress) run over them, and
  buildManifest run over the plan - each page under the class the case names;
* the emitter itself, over a plan on disk: switched off writes nothing; a
  section where the build found nothing writes nothing and says, on a
  `plantoir: note:` line, a page the site found items on; a section with the
  page writes the manifest, leaves a hidden page out, and notes a page the
  build expected and the site found nothing on (myProgress.notes).

verify.sh 6m reads the manifest back from a real build, and
browser-checks/my_progress.mjs ticks the boxes in a browser.
"""
import contextlib
import io
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

SUPPORT_QUARTZ = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins"
RULE_TS = SUPPORT_QUARTZ / "emitters" / "progressRules.ts"
EMITTER_TS = SUPPORT_QUARTZ / "emitters" / "plantoirProgress.ts"
TASKS_TS = SUPPORT_QUARTZ / "transformers" / "plantoirTasks.ts"
TASK_RULES_TS = SUPPORT_QUARTZ / "transformers" / "taskRules.ts"
QUIZZES_TS = SUPPORT_QUARTZ / "transformers" / "plantoirQuizzes.ts"
QUARTZ_TRANSFORMERS = toolchain_paths.QUARTZ_DIR / "quartz" / "plugins" / "transformers"
NODE_MODULES = toolchain_paths.QUARTZ_DIR / "node_modules"

# The support/quartz files import Quartz's own (`../types`, `../../util/...`)
# by relative path, as they do inside a section's Quartz copy; so they are
# bundled from a copy laid out the same way, inside Quartz's own tree.
BUILD = r"""
import { createRequire } from "module"
const require = createRequire("NODE_MODULES/")
const { build } = require("esbuild")
await build({
  entryPoints: [process.argv[2]], outfile: process.argv[3], bundle: true, platform: "node", format: "esm",
  logLevel: "error", nodePaths: ["NODE_MODULES"], loader: { ".scss": "text", ".node": "empty" }, external: ["lightningcss"],
  banner: { js: 'import { createRequire } from "module"; const require = createRequire(import.meta.url);' },
  plugins: [{ name: "stub", setup(builder) {
    builder.onResolve({ filter: /\.inline(\.ts)?$/ }, (args) => ({ path: args.path, namespace: "stub" }))
    builder.onLoad({ filter: /.*/, namespace: "stub" }, () => ({ contents: 'export default ""', loader: "js" }))
  } }],
})
"""

RUNNER = r"""
import { readFileSync, writeFileSync, mkdirSync, existsSync, rmSync } from "fs"
import { join } from "path"
import { unified } from "unified"
import remarkParse from "remark-parse"
import remarkRehype from "remark-rehype"
import { VFile } from "vfile"
import { FrontMatter } from "QUARTZ_TRANSFORMERS/frontmatter"
import { ObsidianFlavoredMarkdown } from "QUARTZ_TRANSFORMERS/ofm"
import { GitHubFlavoredMarkdown } from "QUARTZ_TRANSFORMERS/gfm"
import { Latex } from "QUARTZ_TRANSFORMERS/latex"
import { PlantoirQuizzes } from "QUIZZES_TS"
import { PlantoirTasks } from "TASKS_TS"
import { taskItemId } from "TASK_RULES_TS"
import { buildManifest, countedItems, normalisedHeading, pinnedOrder, rollUp } from "RULE_TS"
import { PlantoirProgress } from "EMITTER_TS"

const rules = JSON.parse(readFileSync(process.argv[2], "utf-8"))
const plans = JSON.parse(readFileSync(process.argv[3], "utf-8"))
const work = process.argv[4]
const failures = []
let count = 0
const ctx = { cfg: { configuration: { locale: "en-US" } }, allSlugs: [], argv: { output: join(work, "public") } }
// In the order a section's quartz.config.ts has them, Latex included: a
// `$$` block is maths to the site, not a list (#545 implementation review 3).
const transformers = [FrontMatter(), ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }), GitHubFlavoredMarkdown(), PlantoirQuizzes(), PlantoirTasks(), Latex({ renderEngine: "katex" })]

// A page as the site builds it (quartz/processors/parse.ts): the file
// trimmed, every text transform in order, the markdown stage, then the html
// stage - the transformers in the order a section's quartz.config.ts has them.
function built(markdown, relativePath) {
  let value = markdown.trim()
  for (const plugin of transformers) {
    if (plugin.textTransform) value = plugin.textTransform(ctx, value)
  }
  const file = new VFile({ value, path: relativePath })
  file.data.relativePath = relativePath
  file.data.slug = relativePath.replace(/\.md$/, "").replace(/ /g, "-")
  const md = unified().use(remarkParse).use(transformers.flatMap((plugin) => plugin.markdownPlugins?.(ctx) ?? []))
  const html = unified().use(remarkRehype, { allowDangerousHtml: true }).use(transformers.flatMap((plugin) => plugin.htmlPlugins?.(ctx) ?? []))
  const tree = html.runSync(md.runSync(md.parse(file), file), file)
  return [tree, file]
}

const DEFAULTS = rules.headings.defaults
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

for (const c of rules.headings.cases) {
  count += 1
  const wanted = (c.headings ?? DEFAULTS).map(normalisedHeading)
  if (wanted.includes(normalisedHeading(c.heading)) !== c.counts) failures.push(`headings ${JSON.stringify(c.heading)}: counts is not ${c.counts}`)
}
for (const c of rules.headings.markupCases) {
  count += 1
  const [tree] = built(c.markdown + "\n\n- [ ] I can add fractions\n", "Markup.md")
  const items = countedItems(tree, DEFAULTS)
  if ((items.length > 0) !== c.counts) failures.push(`headings markup ${JSON.stringify(c.markdown)}: ${items.length} counted, counts should be ${c.counts}`)
  if (DEFAULTS.map(normalisedHeading).includes(normalisedHeading(c.rendered)) !== c.counts) failures.push(`headings markup ${JSON.stringify(c.markdown)}: its rendered words do not read as the case says`)
}

for (const c of rules.sections.cases) {
  count += 1
  const [tree, file] = built(c.markdown, "Tasks/Fractions.md")
  const items = countedItems(tree, c.headings ?? DEFAULTS, String(file.value).split("\n"))
  const want = c.items.map((text) => taskItemId(text))
  if (!same(items.map((item) => item.id), want)) failures.push(`sections ${c.name}: counted ${JSON.stringify(items)}, expected the ids of ${JSON.stringify(c.items)} ${JSON.stringify(want)}`)
  if (c.checked && !same(items.map((item) => item.checked), c.checked)) failures.push(`sections ${c.name}: ticks ${JSON.stringify(items.map((item) => item.checked))}, expected ${JSON.stringify(c.checked)}`)
  // #603: the words the row lists, off the built page's label - the case's
  // own words unless it says how they are shown - and the heading's anchor.
  const shown = c.shown ?? c.items
  if (!same(items.map((item) => item.text), shown)) failures.push(`sections ${c.name}: listed ${JSON.stringify(items.map((item) => item.text))}, expected ${JSON.stringify(shown)}`)
  if (c.anchors && !same(items.map((item) => item.anchor), c.anchors)) failures.push(`sections ${c.name}: anchors ${JSON.stringify(items.map((item) => item.anchor))}, expected ${JSON.stringify(c.anchors)}`)
}
for (const c of rules.gate.cases) {
  count += 1
  const [tree] = built(c.markdown, "Tasks/Fractions.md")
  const items = countedItems(tree, DEFAULTS)
  if ((items.length > 0) !== c.counts) failures.push(`gate ${c.name}: the site counted ${items.length}, the case says counts ${c.counts}`)
}

// The pipeline is the site's, Latex included: a task line inside a `$$`
// block is maths there, never an item (myProgress.knownLimits - the build's
// gate reads it as one, and the emitter's note says so).
count += 1
{
  const [tree] = built("## Success criteria\n\n$$\n- [ ] x = 1\n$$\n", "Tasks/Maths.md")
  if (countedItems(tree, DEFAULTS).length !== 0) failures.push("the check's pipeline has no maths: a task line inside $$ was counted")
}

for (const c of rules.rollUp.cases) {
  count += 1
  const store = c.throws
    ? { getItem() { throw new Error("refused") } }
    : { getItem: (key) => (key in c.stored ? c.stored[key] : null) }
  const got = rollUp(c.siteRoot, c.page, store)
  if (got.done !== c.done || got.total !== c.total) failures.push(`rollUp ${c.name}: ${got.done} / ${got.total}, expected ${c.done} / ${c.total}`)
  // #603: one reading for the list and the count.
  const ticked = Array.isArray(got.ticked) ? got.ticked : []
  let tickedCount = 0
  for (const answer of ticked) if (answer === true) tickedCount += 1
  if (ticked.length !== c.total || tickedCount !== got.done) failures.push(`rollUp ${c.name}: ticked ${JSON.stringify(got.ticked)} disagrees with ${got.done} / ${got.total}`)
  if (c.ticked && !same(ticked, c.ticked)) failures.push(`rollUp ${c.name}: ticked ${JSON.stringify(got.ticked)}, expected ${JSON.stringify(c.ticked)}`)
}

for (const c of rules.sidebar.cases) {
  count += 1
  const nodes = c.nodes.map(([name, isFolder]) => ({ isFolder, slugSegment: name, slug: isFolder ? name + "/index" : name }))
  const got = pinnedOrder(nodes, c.pin).map((node) => node.slugSegment)
  if (!same(got, c.expect)) failures.push(`sidebar ${c.name}: ${JSON.stringify(got)}, expected ${JSON.stringify(c.expect)}`)
}

for (const c of rules.grouping.cases) {
  count += 1
  const plan = plans[c.name]
  const pages = []
  for (const known of plan.pagesWritten) {
    pages.push({ path: known.path, slug: known.path.replace(/\.md$/, ""), title: known.title, items: [{ id: "00000000", checked: false }] })
  }
  const manifest = buildManifest(plan.plan, pages)
  const under = {}
  for (const unit of manifest.units) for (const known of unit.classes) for (const page of known.pages) under[page.title] = known.label
  for (const page of manifest.other.pages) under[page.title] = null
  for (const [title, label] of Object.entries(c.expect)) {
    if (under[title] !== label) failures.push(`grouping ${c.name}: ${JSON.stringify(title)} is under ${JSON.stringify(under[title])}, expected ${JSON.stringify(label)}`)
  }
}

// The emitter, over a plan on disk.
const said = []
const log = console.log
console.log = (line) => said.push(String(line))
process.chdir(work)
const emitter = PlantoirProgress()
const content = [
  built("## Success criteria\n\n- [ ] I can add fractions\n- [x] I can subtract fractions\n", "Tasks/Fractions.md"),
  built("## Success criteria\n\n| I can | add |\n|---|---|\n", "Tasks/Table.md"),
  built("---\npublish: false\n---\n## Success criteria\n\n- [ ] I can hide\n", "Tasks/Hidden.md"),
]
const basePlan = { version: 1, slug: "My-Progress", headings: DEFAULTS.map(normalisedHeading), words: { otherPages: "Other pages" },
  notes: { gateSaidYes: "said yes", gateSaidNo: "said no", gateSaidNoNoPage: "said no, no page" }, classes: [], firstClassOf: {} }
const manifestFile = join(work, "public", "progress-manifest.json")
const emitWith = async (plan) => {
  mkdirSync(join(work, "quartz"), { recursive: true })
  writeFileSync(join(work, "quartz", "plantoir_progress.json"), JSON.stringify(plan))
  rmSync(join(work, "public"), { recursive: true, force: true })
  said.length = 0
  return await emitter.emit(ctx, content, {})
}
count += 1
let emitted = await emitWith({ ...basePlan, page: false, reason: "switchedOff", gate: [] })
if (emitted.length !== 0 || existsSync(manifestFile) || said.length !== 0) failures.push(`emitter, switched off: wrote ${JSON.stringify(emitted)} and said ${JSON.stringify(said)}`)
count += 1
emitted = await emitWith({ ...basePlan, page: false, reason: "noSuccessCriteria", gate: [] })
if (emitted.length !== 0 || existsSync(manifestFile)) failures.push(`emitter, nothing qualified: wrote ${JSON.stringify(emitted)}`)
if (!same(said, ["plantoir: note: Tasks/Fractions.md: said no, no page"])) failures.push(`emitter, nothing qualified: said ${JSON.stringify(said)}, expected one note for the page the build missed`)
count += 1
emitted = await emitWith({ ...basePlan, page: true, reason: "built", gate: ["Tasks/Fractions.md", "Tasks/Table.md"] })
const first = existsSync(manifestFile) ? readFileSync(manifestFile, "utf-8") : ""
const manifest = first === "" ? null : JSON.parse(first)
const expected = { version: 1, words: { otherPages: "Other pages" }, units: [], other: { label: "Other pages", pages: [
  { title: "Fractions", slug: "Tasks/Fractions", items: [
    { id: taskItemId("I can add fractions"), checked: false, text: "I can add fractions", anchor: "success-criteria" },
    { id: taskItemId("I can subtract fractions"), checked: true, text: "I can subtract fractions", anchor: "success-criteria" },
  ] },
] } }
if (emitted.length !== 1 || !same(manifest, expected)) failures.push(`emitter, built: wrote ${first}, expected ${JSON.stringify(expected)}`)
if (!same(said, ["plantoir: note: Tasks/Table.md: said yes"])) failures.push(`emitter, built: said ${JSON.stringify(said)}, expected one note for the page the build expected and the site found nothing on`)
await emitWith({ ...basePlan, page: true, reason: "built", gate: ["Tasks/Fractions.md", "Tasks/Table.md"] })
if (!existsSync(manifestFile) || readFileSync(manifestFile, "utf-8") !== first) failures.push("emitter, built twice: the manifest's bytes changed")
count += 1
emitted = await emitWith({ ...basePlan, page: true, reason: "built", gate: ["Tasks/Table.md"] })
const listed = existsSync(manifestFile) ? JSON.parse(readFileSync(manifestFile, "utf-8")) : null
if (listed === null || listed.other.pages.length !== 1 || listed.other.pages[0].slug !== "Tasks/Fractions") failures.push(`emitter, a page the build missed: not listed (${JSON.stringify(listed)})`)
if (!same(said, ["plantoir: note: Tasks/Fractions.md: said no"])) failures.push(`emitter, a page the build missed: said ${JSON.stringify(said)}, expected the note that it is listed`)
console.log = log

console.log(JSON.stringify({ count, failures }))
"""


def grouping_plans(folder: Path) -> dict:
    """Each grouping case as a section's pages on disk, through the build's own
    date pass and plan; answers {case name: {plan, pagesWritten}}."""
    import build_site  # needs python-frontmatter: the image has it

    plans = {}
    for case in contracts.section("shared-rules", "myProgress", "grouping", "cases"):
        root = folder / "grouping" / case["name"].replace(" ", "-")
        content = root / "content"
        output = root / "output"
        (content / "All Classes").mkdir(parents=True)
        (content / "Tasks").mkdir()
        (output / "quartz").mkdir(parents=True)
        written = []
        item = "\n## Success criteria\n\n- [ ] I can add fractions\n"
        for known in case["classes"]:
            lines = ["---", f"title: {known['title']}"]
            if known.get("created"):
                lines.append(f"created: {known['created']}")
            if known.get("hidden"):
                lines.append("publish: false")
            lines.append("---")
            links = "".join(f"[[{link}]]\n" for link in known["links"])
            path = f"All Classes/{known['title']}.md"
            (content / path).write_text("\n".join(lines) + "\n" + links + item, encoding="utf-8")
            if not known.get("hidden"):
                written.append({"path": path, "title": known["title"]})
        for title in case["pages"]:
            links = "".join(f"[[{link}]]\n" for link in case.get("pageLinks", {}).get(title, []))
            path = f"Tasks/{title}.md"
            (content / path).write_text(f"---\ntitle: {title}\n---\n{links}{item}", encoding="utf-8")
            written.append({"path": path, "title": title})
        dating = build_site._date_pages_from_their_classes(content, 1, write_back=False)
        with contextlib.redirect_stdout(io.StringIO()):
            build_site._prepare_my_progress(content, output, {"per_section_folders": ["All Classes"]}, 1, "TEST",
                                            dating, None)
        plan = json.loads((output / "quartz" / "plantoir_progress.json").read_text(encoding="utf-8"))
        plans[case["name"]] = {"plan": plan, "pagesWritten": written}
    return plans


def run_the_rules_in_node(folder: Path) -> list:
    builder = folder / "build.mjs"
    builder.write_text(BUILD.replace("NODE_MODULES", str(NODE_MODULES)), encoding="utf-8")
    # Laid out as in a section's Quartz copy, so their relative imports of
    # Quartz's own files resolve.
    tree = folder / "quartz"
    shutil.copytree(toolchain_paths.QUARTZ_DIR / "quartz", tree,
                    ignore=shutil.ignore_patterns("node_modules", ".quartz-cache"))
    for source in (RULE_TS, EMITTER_TS, TASKS_TS, TASK_RULES_TS, QUIZZES_TS,
                   SUPPORT_QUARTZ / "transformers" / "quizRules.ts",
                   SUPPORT_QUARTZ / "transformers" / "codeRunnerRule.ts"):
        relative = source.relative_to(toolchain_paths.SUPPORT_DIR / "quartz")
        target = tree / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    entry = folder / "runner.mjs"
    entry.write_text(
        RUNNER.replace("QUARTZ_TRANSFORMERS", str(tree / "plugins" / "transformers"))
        .replace("RULE_TS", str(tree / "plugins" / "emitters" / "progressRules.ts"))
        .replace("EMITTER_TS", str(tree / "plugins" / "emitters" / "plantoirProgress.ts"))
        .replace("TASK_RULES_TS", str(tree / "plugins" / "transformers" / "taskRules.ts"))
        .replace("TASKS_TS", str(tree / "plugins" / "transformers" / "plantoirTasks.ts"))
        .replace("QUIZZES_TS", str(tree / "plugins" / "transformers" / "plantoirQuizzes.ts")),
        encoding="utf-8")
    bundle = folder / "runner.bundle.mjs"
    subprocess.run(["node", str(builder), str(entry), str(bundle)], check=True, env=dict(os.environ))
    rules = folder / "myProgress.json"
    rules.write_text(json.dumps(contracts.section("shared-rules", "myProgress")), encoding="utf-8")
    plans = folder / "plans.json"
    plans.write_text(json.dumps(grouping_plans(folder)), encoding="utf-8")
    work = folder / "emitter"
    work.mkdir()
    output = subprocess.run(["node", str(bundle), str(rules), str(plans), str(work)], check=True,
                            capture_output=True, text=True).stdout
    result = json.loads(output.strip().splitlines()[-1])
    print(f"progressRules.ts and plantoirProgress.ts: {result['count']} contract cases and emitter checks run in Node "
          f"over Quartz's own transformers, PlantoirQuizzes, PlantoirTasks and Latex")
    return result["failures"]


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        failures = run_the_rules_in_node(Path(name))
    for failure in failures:
        print("FAIL " + failure)
    if failures:
        return 1
    print("OK: the My Progress rules in the contract hold in the site's own code")
    return 0


if __name__ == "__main__":
    sys.exit(main())
