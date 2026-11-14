#!/usr/bin/env python3
"""
Which course files a site carries (#901), run against what the SITE runs.

NOT named `test_*.py` on purpose, like `check_progress_rules_against_the_site.py`:
it needs the image's Node, esbuild and Quartz itself, so it can only run
inside the container, and Windows' `PythonToolchainTests` discovers every
`scripts/test_*.py`. `verify.sh` runs it in the image:

    docker run --rm \\
      --mount type=bind,source="$(pwd)/scripts/check_site_files_rules_against_the_site.py",target=/opt/scripts/check_site_files_rules_against_the_site.py,readonly \\
      quartz-teacher:dev-test python3 /opt/scripts/check_site_files_rules_against_the_site.py

`support/quartz/plugins/emitters/siteFilesRules.ts` (the rules) and
`plantoirAssets.ts` (the emitter) are bundled with esbuild, together with
the transformers a page goes through on the site that decide its addresses -
Quartz's own FrontMatter, ObsidianFlavoredMarkdown, GitHubFlavoredMarkdown
and CrawlLinks (`shortest`, as a section's quartz.config.ts has it) - and
every case in `contracts/shared-rules.json` -> `siteFiles` the site reads is
run through them in Node:

* `slugCases` through Quartz's own slugifyFilePath, which
  scripts/site_files.py ports (test_site_files.py runs the port);
* `resolveCases` through resolvedFromPage;
* every attribute in `addresses` against Quartz's own HTML parser
  (property-information), so the emitter looks for each under the name the
  tree really holds it by;
* `addressFixture`'s pages parsed by Quartz's own HTML parser and read by
  addressesThePagesUse: exactly the fixture's `needed` (the Python test reads
  the same fixture twice more, by site_files and by an element table of its
  own);
* `cases`: each a small course written to content/, its pages built, and the
  emitter run over the PUBLISHED pages, as Quartz's first emit hands them,
  and again over every page, as a rebuild does: exactly the case's files
  are copied, at their addresses. The same cases through Quartz's own Assets
  emitter must FAIL every case that leaves a file off (today's behaviour,
  proved against the real old emitter);
* then scripts/site_files.py's check over each case's built pages (each
  tree as HTML, with the Print button's link and the footer a page draws
  outside its tree, and the description meta tags Quartz's Head fills from
  the page's opening text): no hole and no unreferenced file, so the second
  reading agrees with the first on every case.
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
import site_files  # noqa: E402
import toolchain_paths  # noqa: E402

SUPPORT_QUARTZ = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins"
RULES_TS = SUPPORT_QUARTZ / "emitters" / "siteFilesRules.ts"
EMITTER_TS = SUPPORT_QUARTZ / "emitters" / "plantoirAssets.ts"
NODE_MODULES = toolchain_paths.QUARTZ_DIR / "node_modules"

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
import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync, statSync } from "fs"
import { join, dirname, relative } from "path"
import { unified } from "unified"
import remarkParse from "remark-parse"
import remarkRehype from "remark-rehype"
import { toHtml } from "hast-util-to-html"
import { toString } from "hast-util-to-string"
import { fromHtml } from "hast-util-from-html"
import { find, html as htmlSchema } from "property-information"
import { VFile } from "vfile"
import { FrontMatter } from "QUARTZ_TRANSFORMERS/frontmatter"
import { ObsidianFlavoredMarkdown } from "QUARTZ_TRANSFORMERS/ofm"
import { GitHubFlavoredMarkdown } from "QUARTZ_TRANSFORMERS/gfm"
import { CrawlLinks } from "QUARTZ_TRANSFORMERS/links"
import { Assets } from "QUARTZ_EMITTERS/assets"
import { slugifyFilePath, pathToRoot, joinSegments } from "QUARTZ_UTIL/path"
import { glob } from "QUARTZ_UTIL/glob"
import { resolvedFromPage, isHiddenPage, printPdfPath, addressesThePagesUse } from "RULES_TS"
import { PlantoirAssets } from "EMITTER_TS"

const rules = JSON.parse(readFileSync(process.argv[2], "utf-8"))
const sides = JSON.parse(readFileSync(process.argv[3], "utf-8"))
const work = process.argv[4]
const failures = []
let count = 0
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)
const IGNORE = ["private", "templates", ".obsidian"]

for (const [path, slug] of rules.slugCases) {
  count += 1
  const got = slugifyFilePath(path)
  if (got !== slug) failures.push(`slug ${JSON.stringify(path)}: Quartz says ${JSON.stringify(got)}, the case ${JSON.stringify(slug)}`)
}
// Every attribute the one list names is Quartz's own name for it: the tree
// the emitter reads holds each under the parser's property name.
for (const rule of rules.addresses.attributes) {
  count += 1
  const got = find(htmlSchema, rule.attribute).property
  if (got !== rule.property) failures.push(`address attribute ${rule.attribute}: Quartz's parser calls it ${got}, the list ${rule.property}`)
}
// The third reading's fixture (addressFixture), parsed by Quartz's own HTML
// parser and read by the emitter's own function: exactly the files the
// fixture says a page needs.
{
  count += 1
  const fixture = rules.addressFixture
  const fileAddresses = new Set(fixture.files.map((fp) => slugifyFilePath(fp)))
  const pages = []
  for (const [name, text] of Object.entries(fixture.pages)) {
    pages.push({ slug: name.replace(/\.html$/, ""), tree: fromHtml(text), frontmatter: {}, declared: [] })
  }
  const used = [...addressesThePagesUse(pages, fileAddresses, { addresses: rules.addresses }, (fp) => slugifyFilePath(fp))].sort()
  const needed = [...fixture.needed].sort()
  if (!same(used, needed)) failures.push(`addressFixture: the emitter's reader needs ${JSON.stringify(used)}, the fixture ${JSON.stringify(needed)}`)
}
for (const [page, address, resolved] of rules.resolveCases) {
  count += 1
  const got = resolvedFromPage(page, address)
  if (got !== resolved) failures.push(`resolve ${JSON.stringify(address)} on ${page}: ${JSON.stringify(got)}, expected ${JSON.stringify(resolved)}`)
}

function filesUnder(folder) {
  const found = []
  const walk = (at) => {
    for (const name of readdirSync(at)) {
      const full = join(at, name)
      if (statSync(full).isDirectory()) walk(full)
      else found.push(relative(folder, full).split("\\").join("/"))
    }
  }
  try { walk(folder) } catch {}
  return found.sort()
}

async function drain(generator) {
  for await (const _ of generator) {}
}

let caseNumber = 0
for (const c of rules.cases) {
  caseNumber += 1
  const root = join(work, "case" + caseNumber)
  const content = join(root, "content")
  rmSync(root, { recursive: true, force: true })
  for (const name of c.files) {
    mkdirSync(dirname(join(content, name)), { recursive: true })
    writeFileSync(join(content, name), "file " + name)
  }
  for (const [name, markdown] of Object.entries(c.pages)) {
    mkdirSync(dirname(join(content, name)), { recursive: true })
    writeFileSync(join(content, name), markdown)
  }
  mkdirSync(join(root, "quartz"), { recursive: true })
  writeFileSync(join(root, "quartz", "plantoir_site_files.json"), JSON.stringify(sides[c.name]))
  const allFiles = await glob("**/*.*", content, IGNORE)
  const ctx = {
    argv: { directory: content, output: join(root, "public") },
    cfg: { configuration: { ignorePatterns: IGNORE, locale: "en-US" } },
    allFiles,
    allSlugs: allFiles.map((fp) => slugifyFilePath(fp)),
  }
  const transformers = [FrontMatter(), ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }), GitHubFlavoredMarkdown(), CrawlLinks({ markdownLinkResolution: "shortest" })]
  const every = []
  for (const name of Object.keys(c.pages).sort()) {
    let value = readFileSync(join(content, name), "utf-8").trim()
    for (const plugin of transformers) if (plugin.textTransform) value = plugin.textTransform(ctx, value)
    const file = new VFile({ value, path: join(content, name) })
    file.data.relativePath = name
    file.data.slug = slugifyFilePath(name)
    file.data.filePath = join(content, name)
    const md = unified().use(remarkParse).use(transformers.flatMap((plugin) => plugin.markdownPlugins?.(ctx) ?? []))
    const html = unified().use(remarkRehype, { allowDangerousHtml: true }).use(transformers.flatMap((plugin) => plugin.htmlPlugins?.(ctx) ?? []))
    const tree = html.runSync(md.runSync(md.parse(file), file), file)
    if (c.declared && c.declared[name]) file.data.plantoirFiles = [...c.declared[name]]
    every.push([tree, file])
  }
  const published = every.filter(([, file]) => !isHiddenPage(file.data.frontmatter))
  const expect = [...c.carried].sort()
  const allAddresses = c.files.map((fp) => slugifyFilePath(fp)).sort()
  const leftOff = allAddresses.filter((address) => !expect.includes(address))
  if (!same(leftOff, [...c.leftOff].sort())) failures.push(`case ${c.name}: carried and leftOff do not cover its files`)
  const cwd = process.cwd()
  process.chdir(root)
  try {
    for (const [label, pages] of [["first emit", published], ["rebuild", every]]) {
      count += 1
      rmSync(join(root, "public"), { recursive: true, force: true })
      await drain(PlantoirAssets().emit(ctx, pages, {}))
      const got = filesUnder(join(root, "public"))
      if (!same(got, expect)) failures.push(`case ${c.name} (${label}): carried ${JSON.stringify(got)}, expected ${JSON.stringify(expect)}`)
    }
    // Quartz's own emitter over the same case: every case that leaves a
    // file off must fail with it, or the case proves nothing.
    count += 1
    rmSync(join(root, "public"), { recursive: true, force: true })
    await drain(Assets().emit(ctx, published, {}))
    const old = filesUnder(join(root, "public"))
    if (leftOff.length > 0 && same(old, expect)) failures.push(`case ${c.name}: Quartz's own emitter passes it, so it proves nothing`)
    if (leftOff.length === 0 && !same(old, expect)) failures.push(`case ${c.name}: Quartz's own emitter carries ${JSON.stringify(old)}`)
    // The built pages, for the check written in Python: each tree as HTML,
    // with what a page draws outside its tree.
    rmSync(join(root, "public"), { recursive: true, force: true })
    await drain(PlantoirAssets().emit(ctx, published, {}))
    for (const [tree, file] of published) {
      const slug = file.data.slug
      const rootPath = pathToRoot(slug)
      let body = toHtml(tree, { allowDangerousHtml: true })
      const pdf = printPdfPath(file.data.frontmatter)
      if (pdf !== null) body += `<a class="plantoir-print plantoir-print-pdf" href="${joinSegments(rootPath, slugifyFilePath(pdf))}">Print</a>`
      if (c.footer) body += `<footer>${c.footer}</footer>`
      // What Quartz's Head writes from the page's opening text (#901 review
      // W1): a description is text, and a page that only mentions a file's
      // name must not make the check put it back.
      const description = toString(tree).trim().slice(0, 160)
      const metas = [["name", "description"], ["property", "og:description"], ["name", "twitter:description"], ["property", "og:image:alt"]]
      let head = `<title>${toHtml({ type: "text", value: String(file.data.frontmatter?.title ?? "") })}</title>`
      for (const [kind, name] of metas) {
        head += toHtml({ type: "element", tagName: "meta", properties: { [kind]: name, content: description }, children: [] })
      }
      head += `<meta property="og:image" content="https://example.org/static/og-image.png">`
      if (file.data.plantoirFiles) {
        for (const declared of file.data.plantoirFiles) {
          body += `<figure data-geogebra='${JSON.stringify({ sketch: slugifyFilePath(declared), root: rootPath })}'></figure>`
        }
      }
      const target = join(root, "public", slug + ".html")
      mkdirSync(dirname(target), { recursive: true })
      writeFileSync(target, `<!DOCTYPE html><html><head>${head}</head><body>${body}</body></html>`)
    }
  } finally {
    process.chdir(cwd)
  }
}

console.log(JSON.stringify({ count, failures, cases: rules.cases.length }))
"""


def side_files_of_the_cases() -> dict:
    sides = {}
    for case in contracts.section("shared-rules", "siteFiles", "cases"):
        sides[case["name"]] = site_files.side_file(case.get("footer", ""))
    return sides


def run_the_rules_in_node(folder: Path) -> list:
    builder = folder / "build.mjs"
    builder.write_text(BUILD.replace("NODE_MODULES", str(NODE_MODULES)), encoding="utf-8")
    tree = folder / "quartz"
    shutil.copytree(toolchain_paths.QUARTZ_DIR / "quartz", tree,
                    ignore=shutil.ignore_patterns("node_modules", ".quartz-cache"))
    for source in (RULES_TS, EMITTER_TS):
        target = tree / source.relative_to(toolchain_paths.SUPPORT_DIR / "quartz")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    entry = folder / "runner.mjs"
    entry.write_text(
        RUNNER.replace("QUARTZ_TRANSFORMERS", str(tree / "plugins" / "transformers"))
        .replace("QUARTZ_EMITTERS", str(tree / "plugins" / "emitters"))
        .replace("QUARTZ_UTIL", str(tree / "util"))
        .replace("RULES_TS", str(tree / "plugins" / "emitters" / "siteFilesRules.ts"))
        .replace("EMITTER_TS", str(tree / "plugins" / "emitters" / "plantoirAssets.ts")),
        encoding="utf-8")
    bundle = folder / "runner.bundle.mjs"
    subprocess.run(["node", str(builder), str(entry), str(bundle)], check=True, env=dict(os.environ))
    rules = folder / "siteFiles.json"
    rules.write_text(json.dumps(contracts.section("shared-rules", "siteFiles")), encoding="utf-8")
    sides = folder / "sides.json"
    sides.write_text(json.dumps(side_files_of_the_cases()), encoding="utf-8")
    work = folder / "cases"
    work.mkdir()
    output = subprocess.run(["node", str(bundle), str(rules), str(sides), str(work)], check=True,
                            capture_output=True, text=True).stdout
    result = json.loads(output.strip().splitlines()[-1])
    failures = list(result["failures"])
    # The second reading, over each case's built pages and carried files.
    checked = 0
    for number, case in enumerate(contracts.section("shared-rules", "siteFiles", "cases"), start=1):
        root = work / f"case{number}"
        outcome = site_files.check(root / "public", root / "content", repair=False)
        checked += 1
        for key in ("putBack", "putBackFailed", "unreferenced"):
            if outcome[key]:
                failures.append(f"case {case['name']}: the check after the build counts {key} {outcome[key]}")
        if outcome["carried"] != len(case["carried"]) or outcome["leftOff"] != len(case["leftOff"]):
            failures.append(f"case {case['name']}: the check counts {outcome['carried']} carried and "
                            f"{outcome['leftOff']} left off")
    print(f"siteFilesRules.ts and plantoirAssets.ts: {result['count']} contract cases and emitter runs in Node "
          f"over Quartz's own FrontMatter, ObsidianFlavoredMarkdown, GitHubFlavoredMarkdown and CrawlLinks, "
          f"{result['cases']} courses against Quartz's own Assets as well; scripts/site_files.py's check "
          f"over the {checked} built courses")
    return failures


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        failures = run_the_rules_in_node(Path(name))
    for failure in failures:
        print("FAIL " + failure)
    if failures:
        return 1
    print("OK: the site's files in the contract hold in the site's own code, and the check agrees")
    return 0


if __name__ == "__main__":
    sys.exit(main())
