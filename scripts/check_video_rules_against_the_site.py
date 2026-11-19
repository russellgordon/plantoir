#!/usr/bin/env python3
"""
The video rules in the contract, run through the SITE's own pipeline (#692).

NOT named `test_*.py` on purpose, like check_geogebra_rules_against_the_site.py:
it needs the image's Node and Quartz's own node_modules, so it can only run
inside the container (Windows' PythonToolchainTests discovers every
`scripts/test_*.py`). verify.sh runs it in the image.

Every `videoEmbeds.cases` page is read as Quartz reads a page: remark-parse,
then OFM's own Markdown plugins and remark-gfm, then remark-rehype with
allowDangerousHtml, then the html plugins of PlantoirVideo
(support/quartz/plugins/transformers/plantoirVideo.ts) and of Quartz's own
ObsidianFlavoredMarkdown, in that order, the order the build wires them
(build_site._wire_video_transformer; scripts/test_quartz_additions_wiring.py
pins it). Each is bundled from its real source with the image's esbuild, so
OFM's YouTube step is the one that ships, and a player the videos'
transformer did not make, or made wrongly, shows here as OFM's.

Also held to the contract: the fallback titles, every player attribute, and
the notAVideo sentence, as videoRules.js carries them.
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

TRANSFORMERS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers"
OFM_TS = toolchain_paths.QUARTZ_DIR / "quartz" / "plugins" / "transformers" / "ofm.ts"
MODULES = toolchain_paths.QUARTZ_DIR / "node_modules"

ENTRY = """
import { unified } from "unified"
import remarkParse from "remark-parse"
import remarkGfm from "remark-gfm"
import remarkRehype from "remark-rehype"
import { toHtml } from "hast-util-to-html"
import { ObsidianFlavoredMarkdown } from __OFM__
import { PlantoirVideo } from __VIDEO__
export * as rules from __RULES__

const ofm = ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false })
const video = PlantoirVideo()
const ctx = { allSlugs: [], cfg: { configuration: {} }, argv: {} }

export async function render(page) {
  const said = []
  const log = console.log
  console.log = (...parts) => said.push(parts.join(" "))
  try {
    const text = ofm.textTransform ? ofm.textTransform(ctx, page) : page
    const markdown = unified().use(remarkParse).use(ofm.markdownPlugins(ctx)).use(remarkGfm)
    const file = { value: text, data: { relativePath: "Units/Videos.md", slug: "Units/Videos" } }
    const tree = await markdown.run(markdown.parse(text), file)
    const html = unified()
      .use(remarkRehype, { allowDangerousHtml: true })
      .use([...video.htmlPlugins(ctx), ...ofm.htmlPlugins(ctx)])
    const hast = await html.run(tree, file)
    const elements = []
    const walk = (node) => {
      if (node.type === "element") elements.push(node)
      for (const child of node.children ?? []) walk(child)
    }
    walk(hast)
    return { html: toHtml(hast, { allowDangerousHtml: true }), elements, said }
  } finally {
    console.log = log
  }
}
"""

BUILD = """
import { pathToFileURL } from "url"
const esbuild = await import(pathToFileURL(process.argv[2] + "/esbuild/lib/main.js").href)
await esbuild.build({
  entryPoints: [process.argv[3]], bundle: true, format: "esm", platform: "node",
  outfile: process.argv[4], nodePaths: [process.argv[2]], logLevel: "warning",
  plugins: [{
    name: "plantoir-stub-browser-files",
    setup(build) {
      build.onResolve({ filter: /\\.inline(\\.ts)?$|\\.scss$/ }, (args) => ({ path: args.path, namespace: "stub" }))
      build.onLoad({ filter: /.*/, namespace: "stub" }, () => ({ contents: "export default ''", loader: "js" }))
    },
  }],
})
"""

RUNNER = r"""
import { readFileSync } from "fs"
import { pathToFileURL } from "url"
const site = await import(pathToFileURL(process.argv[2]).href)
const block = JSON.parse(readFileSync(process.argv[3], "utf-8"))
const failures = []
const classOf = (node) => {
  const value = node.properties.className
  return Array.isArray(value) ? value : String(value ?? "").split(" ")
}
for (const c of block.cases) {
  const { html, elements, said } = await site.render(c.page)
  const frames = elements.filter((node) => node.tagName === "iframe")
  const pictures = elements.filter((node) => node.tagName === "img")
  const links = elements.filter((node) => node.tagName === "a")
  const notes = said.filter((line) => line.startsWith("plantoir: note: "))
  const expect = c.expect
  if (expect.player) {
    if (frames.length !== 1) { failures.push(`${c.name}: ${frames.length} players, expected one (${html.slice(0, 160)})`); continue }
    const frame = frames[0].properties
    const classes = classOf(frames[0])
    const wanted = [...block.player.class, expect.player.host]
    if (JSON.stringify(classes) !== JSON.stringify(wanted)) failures.push(`${c.name}: class ${JSON.stringify(classes)}`)
    if (frame.src !== expect.player.src) failures.push(`${c.name}: src ${frame.src}, the contract's ${expect.player.src}`)
    if (frame.title !== expect.player.title) failures.push(`${c.name}: title ${JSON.stringify(frame.title)}, the contract's ${JSON.stringify(expect.player.title)}`)
    const attributes = block.player.attributes
    const read = { loading: frame.loading, allow: frame.allow, allowfullscreen: frame.allowFullScreen,
                   referrerpolicy: frame.referrerPolicy, frameborder: String(frame.frameBorder) }
    for (const name of Object.keys(attributes)) {
      if (read[name] !== attributes[name]) failures.push(`${c.name}: ${name} ${JSON.stringify(read[name])}, the contract's ${JSON.stringify(attributes[name])}`)
    }
    if (notes.length !== 0) failures.push(`${c.name}: printed ${JSON.stringify(notes)}`)
  } else if (expect.picture) {
    if (frames.length !== 0 || pictures.length !== 1) failures.push(`${c.name}: ${frames.length} players and ${pictures.length} pictures, expected the picture alone`)
    if ((notes.length === 1) !== expect.note || notes.length > 1) failures.push(`${c.name}: printed ${JSON.stringify(notes)}`)
    if (expect.note && notes.length === 1) {
      const address = pictures[0]?.properties.src ?? ""
      const wanted = "plantoir: note: " + block.notes.notAVideo.replace("{page}", "Units/Videos.md").replace("{line}", "1").replace("{address}", address)
      if (notes[0] !== wanted) failures.push(`${c.name}: the note reads ${JSON.stringify(notes[0])}`)
    }
  } else if (expect.link) {
    if (frames.length !== 0 || links.length !== 1) failures.push(`${c.name}: ${frames.length} players and ${links.length} links`)
  } else if (expect.unchanged !== undefined) {
    if (!html.includes(expect.unchanged)) failures.push(`${c.name}: the pasted code was changed: ${html.slice(0, 200)}`)
    // OFM's rehype-raw makes the pasted code an element AFTER PlantoirVideo
    // has run, so it is an iframe here, and never one of Plantoir's.
    if (frames.some((node) => classOf(node).includes("plantoir-video"))) failures.push(`${c.name}: a player was made from pasted code`)
  } else {
    failures.push(`${c.name}: the case expects nothing this check knows`)
  }
}
if (JSON.stringify(site.rules.FALLBACK_TITLES) !== JSON.stringify(block.titles)) failures.push(`titles: videoRules.js has ${JSON.stringify(site.rules.FALLBACK_TITLES)}`)
if (JSON.stringify(site.rules.PLAYER_ATTRIBUTES) !== JSON.stringify(block.player.attributes)) failures.push(`attributes: videoRules.js has ${JSON.stringify(site.rules.PLAYER_ATTRIBUTES)}`)
if (site.rules.NOT_A_VIDEO !== block.notes.notAVideo) failures.push("notAVideo: videoRules.js says it differently")
console.log(JSON.stringify(failures))
"""


def main() -> int:
    block = contracts.section("shared-rules", "videoEmbeds")
    failures = []
    work = Path(tempfile.mkdtemp(prefix="plantoir-video-rules-"))
    try:
        (work / "package.json").write_text('{"type": "module"}\n', encoding="utf-8")
        entry = (ENTRY.replace("__OFM__", json.dumps(str(OFM_TS)))
                 .replace("__VIDEO__", json.dumps(str(TRANSFORMERS / "plantoirVideo.ts")))
                 .replace("__RULES__", json.dumps(str(TRANSFORMERS / "videoRules.js"))))
        (work / "entry.ts").write_text(entry, encoding="utf-8")
        (work / "build.mjs").write_text(BUILD, encoding="utf-8")
        (work / "runner.mjs").write_text(RUNNER, encoding="utf-8")
        (work / "block.json").write_text(json.dumps(block), encoding="utf-8")
        built = subprocess.run(["node", str(work / "build.mjs"), str(MODULES), str(work / "entry.ts"),
                                str(work / "site.mjs")], capture_output=True, text=True,
                               env=dict(os.environ, NODE_PATH=str(MODULES)))
        if built.returncode != 0:
            failures.append("the site's transformers did not bundle: " + (built.stderr or built.stdout).strip()[-600:])
        else:
            said = subprocess.run(["node", str(work / "runner.mjs"), str(work / "site.mjs"), str(work / "block.json")],
                                  capture_output=True, text=True)
            if said.returncode != 0:
                failures.append("the rules did not run in Node: " + said.stderr.strip()[-600:])
            else:
                failures.extend(json.loads(said.stdout.strip().splitlines()[-1]))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for failure in failures:
        print("   " + failure)
    print(f"{'FAIL' if failures else 'PASS'}: videoEmbeds cases through the site's own Markdown reader, "
          f"PlantoirVideo and Quartz's own YouTube step ({len(block['cases'])} cases, {len(failures)} problem(s))")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
