#!/usr/bin/env python3
"""
The runnable-code rules in the contract, run against what the SITE runs (#455).

NOT named `test_*.py` on purpose, like `check_print_rules_against_the_site.py`:
it needs the image's Node, esbuild, Quartz's own Markdown parser and
python-frontmatter, so it can only run inside the container, and Windows'
`PythonToolchainTests` discovers every `scripts/test_*.py`. `verify.sh` runs
it in the image:

    docker run --rm \
      --mount type=bind,source="$(pwd)/scripts/check_runner_rules_against_the_site.py",target=/opt/scripts/check_runner_rules_against_the_site.py,readonly \
      quartz-teacher:dev-test python3 /opt/scripts/check_runner_rules_against_the_site.py

Three halves:

1. `support/quartz/plugins/transformers/codeRunnerRule.ts` - the file the
   site's transformer and the page's script both import - is bundled with
   Quartz's own unified, remark-parse and remark-gfm (the parser the site
   reads a page with), and every case in `contracts/shared-rules.json` ->
   `codeRunnerBlocks` (`fences`, `fences.pageShapes`, `ids`) is run through it
   in Node, with its `LANGUAGES` compared with the contract's table field for
   field; and the transformer itself (codeRunner.ts) is run over a page whose
   engine the site does and does not carry, to pin `siteDisagrees`: plain
   code and one `plantoir: error:` line, and no line for a page students
   cannot see. Since #493 also every `swift.cacheKey` case (the site's
   normalising and key), and Swift blocks whose program the build has, could
   not make, or never saw.
2. Every `pageShapes` case is read by the BUILD's side too
   (page_features.runner_fences), so the two readers are seen to agree where
   the contract says they do (review S2).
3. Every typed line in `contracts/file-formats.json` ->
   `pageOptIns.codeRunnerReadingCases` is put through the build's own reader
   (python-frontmatter, after `build_site.process_frontmatter`).
4. Live input (#583): every `liveInput.asksCases` case through
   codeRunnerRule.asksFor (what the transformer writes as data-runner-asks);
   every `isolation.cases` case through the preview's rule
   (quartz/cli/plantoirIsolation.mjs) AND the publish's
   (isolation_headers.py), with the preview's constants compared with the
   contract's; the preview's headers for a page, the engine folders, an
   encoded name and a file that cannot be read (it fails open); and both
   patches to Quartz itself (the preview's server, the router) made on the
   image's own files, ONCE however often the build runs, leaving each file
   still valid.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_site  # noqa: E402
import contracts  # noqa: E402
import page_features  # noqa: E402
import toolchain_paths  # noqa: E402

RULE_TS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "codeRunnerRule.ts"
TRANSFORMER_TS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "codeRunner.ts"
ISOLATION_MJS = toolchain_paths.SUPPORT_DIR / "quartz" / "cli" / "plantoirIsolation.mjs"
NODE_MODULES = toolchain_paths.QUARTZ_DIR / "node_modules"
ESBUILD = NODE_MODULES / "esbuild" / "bin" / "esbuild"

RUNNER = r"""
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync } from "fs"
import { tmpdir } from "os"
import { join } from "path"
import { unified } from "unified"
import remarkParse from "remark-parse"
import remarkGfm from "remark-gfm"
import { createHash } from "crypto"
import { LANGUAGES, runnerFor, findRunners, filled, normaliseProgram, asksFor } from "RULE_TS"
import { CodeRunnerFences, programKey } from "TRANSFORMER_TS"
import { pageVerdict, headersFor, PAGE_HEADERS, ENGINE_HEADERS, ENGINE_FOLDERS, ALLOWED_HOSTS } from "ISOLATION_MJS"

const rules = JSON.parse(readFileSync(process.argv[2], "utf-8"))
const failures = []
let count = 0
const parse = (text) => unified().use(remarkParse).use(remarkGfm).parse(text)

// The table, field for field.
count += 1
if (JSON.stringify(LANGUAGES) !== JSON.stringify(rules.languages)) {
  failures.push(`languages: the site's table is ${JSON.stringify(LANGUAGES)}`)
}
for (const c of rules.fences.cases) {
  count += 1
  const got = runnerFor(c.lang, c.meta, c.optedIn)
  if (!c.runner) {
    if (got !== null) failures.push(`fences ${c.name}: a runner with ${JSON.stringify(got.flags)}`)
    continue
  }
  if (got === null) failures.push(`fences ${c.name}: not a runner`)
  else if (got.language.fence !== (c.fence ?? c.lang) || JSON.stringify(got.flags) !== JSON.stringify(c.flags)) {
    failures.push(`fences ${c.name}: ${got.language.fence} ${JSON.stringify(got.flags)}`)
  }
}
for (const c of rules.fences.pageShapes.cases) {
  count += 1
  const found = findRunners(parse(c.page), true, "Shapes")
  const bodies = found.map((runner) => runner.node.value)
  if (found.length !== c.runners || JSON.stringify(bodies) !== JSON.stringify(c.siteBodies)) {
    failures.push(`pageShapes ${c.name}: the site finds ${found.length} with ${JSON.stringify(bodies)}`)
  }
  if (findRunners(parse(c.page), false, "Shapes").length !== 0) failures.push(`pageShapes ${c.name}: runners on a page that does not opt in`)
}
for (const c of rules.ids.cases) {
  count += 1
  const ids = findRunners(parse(c.page), true, c.slug).map((runner) => runner.id)
  if (JSON.stringify(ids) !== JSON.stringify(c.ids)) failures.push(`ids ${c.slug}: ${JSON.stringify(ids)}`)
}
// The Swift cache key (#493, codeRunnerBlocks.swift.cacheKey): the site's
// normalising, and its key as the transformer computes it.
for (const c of rules.swift.cacheKey.cases) {
  count += 1
  const got = normaliseProgram(c.body)
  const key = createHash("sha256").update(got.text, "utf8").digest("hex")
  if (got.text !== c.normalised || got.droppedAtTop !== c.droppedAtTop || key !== c.key || programKey(c.body) !== c.key) {
    failures.push(`swift.cacheKey ${c.name}: ${JSON.stringify(got)} ${key}`)
  }
}
// The transformer itself (siteDisagrees): a runnable block whose engine the
// site does not carry stays plain code and is named on a plantoir: error:
// line - unless students cannot see the page.
const words = Object.fromEntries(Object.entries(rules.words).filter(([key]) => key !== "note"))
const transform = CodeRunnerFences().markdownPlugins()[0]()
const page = "```python run\nprint(1)\n```\n"
const notPrepared = "plantoir: error: Units/Loops.md: python block 1: " + filled(words.blockNotPrepared, LANGUAGES[0])
const afterUnclosed = "plantoir: error: Units/Loops.md: python block 1: " + filled(words.blockAfterUnclosedFence, LANGUAGES[0])
// Review N3's page: a fence left open in a list item, then a runnable block.
const unclosedPage = "- step one\n  ```python\n  print(1)\n- step two\n\n```python run\nprint(2)\n```\n"
const transformerCases = [
  { name: "the engine is carried", carried: ["pyodide"], publish: undefined, wrapped: true, line: null },
  { name: "the engine is not carried", carried: [], publish: undefined, wrapped: false, line: notPrepared },
  { name: "the engine is not carried, on a page students cannot see", carried: [], publish: false, wrapped: false, line: null },
  { name: "the engine is not carried, after an unclosed fence", carried: [], publish: undefined, wrapped: false, line: afterUnclosed, page: unclosedPage },
]
// Swift's blocks (#493): the key looked up in quartz/plantoir-runners/swift.json.
const swiftRow = LANGUAGES.find((language) => language.fence === "swift")
const swiftPage = "```swift run\nprint(1)\n```\n"
const swiftKey = programKey("print(1)")
const swiftNotCompiled = "plantoir: error: Units/Loops.md: swift block 1: " + filled(words.blockNotCompiled, swiftRow)
const swiftNotPrepared = "plantoir: error: Units/Loops.md: swift block 1: " + filled(words.blockNotPrepared, swiftRow)
transformerCases.push(
  { name: "a Swift block whose program the build has", carried: ["swift"], programs: { [swiftKey]: { ok: true, file: swiftKey + ".wasm", sdk: "embedded" } }, wrapped: true, line: null, page: swiftPage, wasm: `static/swift-wasm/${swiftKey}.wasm` },
  { name: "a Swift block the build could not compile", carried: ["swift"], programs: { [swiftKey]: { ok: false, reason: "compileError" } }, wrapped: true, line: null, page: swiftPage, unready: "compileError" },
  { name: "a Swift block whose key the build never saw", carried: ["swift"], programs: {}, wrapped: false, line: swiftNotCompiled, page: swiftPage },
  { name: "a Swift block on a site that does not carry Swift", carried: [], programs: {}, wrapped: false, line: swiftNotPrepared, page: swiftPage },
)
const home = process.cwd()
for (const c of transformerCases) {
  count += 1
  const site = mkdtempSync(join(tmpdir(), "plantoir-runner-site-"))
  mkdirSync(join(site, "quartz"))
  writeFileSync(join(site, "quartz", "plantoir_code_runner.json"), JSON.stringify({ words, carried: c.carried, limits: {} }))
  if (c.programs !== undefined) {
    mkdirSync(join(site, "quartz", "plantoir-runners"))
    writeFileSync(join(site, "quartz", "plantoir-runners", "swift.json"), JSON.stringify(c.programs))
  }
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25)
  process.chdir(site)
  const said = []
  const log = console.log
  console.log = (line) => said.push(String(line))
  const text = c.page ?? page
  const tree = parse(text)
  transform(tree, { value: text, data: { frontmatter: { codeRunner: true, publish: c.publish }, slug: "Units/Loops", relativePath: "Units/Loops.md" } })
  console.log = log
  process.chdir(home)
  const text2 = JSON.stringify(tree)
  const wrapped = text2.includes('"plantoirRunner"')
  const lined = c.line === null ? said.length === 0 : said.length === 1 && said[0] === c.line
  const wasmRight = c.wasm === undefined ? !text2.includes("dataRunnerWasm") : text2.includes(`"dataRunnerWasm":"${c.wasm}"`)
  const unreadyRight = c.unready === undefined ? !text2.includes("dataRunnerUnready") : text2.includes(`"dataRunnerUnready":"${c.unready}"`)
  if (wrapped !== c.wrapped || !lined || !wasmRight || !unreadyRight) {
    failures.push(`transformer, ${c.name}: wrapped ${wrapped}, said ${JSON.stringify(said)}, program ${wasmRight}, unready ${unreadyRight}`)
  }
}
// Live input (#583): which blocks can ask (data-runner-asks).
for (const c of rules.liveInput.asksCases) {
  count += 1
  const language = LANGUAGES.find((row) => row.fence === c.language)
  const got = asksFor(language, c.flags, c.code)
  if (got !== c.asks) failures.push(`liveInput.asksCases ${c.name}: ${JSON.stringify(got)}`)
}
// ...and the transformer writes it on the wrapper.
{
  count += 1
  const site = mkdtempSync(join(tmpdir(), "plantoir-runner-site-"))
  mkdirSync(join(site, "quartz"))
  writeFileSync(join(site, "quartz", "plantoir_code_runner.json"), JSON.stringify({ words, carried: ["pyodide"], limits: {} }))
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25)
  process.chdir(site)
  const asking = "```python run\nname = input()\n```\n\n```python run readonly\nprint(1)\n```\n\n```python run\nprint(2)\n```\n"
  const tree = parse(asking)
  const log = console.log
  console.log = () => undefined
  transform(tree, { value: asking, data: { frontmatter: { codeRunner: true }, slug: "Units/Asks", relativePath: "Units/Asks.md" } })
  console.log = log
  process.chdir(home)
  const asks = []
  const walk = (node) => {
    if (node.type === "plantoirRunner") asks.push(node.data.hProperties.dataRunnerAsks ?? null)
    for (const child of node.children ?? []) walk(child)
  }
  walk(tree)
  if (JSON.stringify(asks) !== JSON.stringify(["input", null, "edit"])) failures.push(`the transformer's data-runner-asks: ${JSON.stringify(asks)}`)
}
// Which pages are isolated: the preview's rule, every contract case.
count += 1
if (JSON.stringify(PAGE_HEADERS) !== JSON.stringify(rules.isolation.headers.page)
  || JSON.stringify(ENGINE_HEADERS) !== JSON.stringify(rules.isolation.headers.engine)
  || JSON.stringify(ENGINE_FOLDERS) !== JSON.stringify(rules.isolation.engineFolders)
  || JSON.stringify(ALLOWED_HOSTS) !== JSON.stringify(rules.isolation.allowedHosts)) {
  failures.push("isolation: the preview's headers, engine folders or allowed hosts are not the contract's")
}
for (const c of rules.isolation.cases) {
  count += 1
  const got = pageVerdict(c.html, rules.isolation.allowedHosts)
  if (got.verdict !== c.verdict || got.readsInput !== c.readsInput) failures.push(`isolation.cases ${c.name}: the preview says ${JSON.stringify(got)}`)
}
// The preview's headers, per address, and failing open.
{
  const live = rules.isolation.cases.find((c) => c.verdict === "live" && c.readsInput).html
  const framed = rules.isolation.cases.find((c) => c.verdict === "frame").html
  const site = mkdtempSync(join(tmpdir(), "plantoir-isolation-site-"))
  const pub = join(site, "public")
  mkdirSync(join(pub, "Units"), { recursive: true })
  mkdirSync(join(pub, "static", "pyodide"), { recursive: true })
  mkdirSync(join(pub, "static", "swift"), { recursive: true })
  mkdirSync(join(pub, "Broken.html"))
  writeFileSync(join(pub, "Units", "Loops.html"), live)
  writeFileSync(join(pub, "Units", "Café.html"), live)
  writeFileSync(join(pub, "Units", "index.html"), live)
  writeFileSync(join(pub, "Units", "Framed.html"), framed)
  writeFileSync(join(pub, "Units", "Plain.html"), "<p>Plain</p>")
  writeFileSync(join(pub, "static", "pyodide", "pyodide.mjs"), "")
  const expectations = [
    ["/Units/Loops", PAGE_HEADERS], ["/Units/Loops.html", PAGE_HEADERS], ["/Units/Caf%C3%A9", PAGE_HEADERS],
    ["/Units/", PAGE_HEADERS], ["/Units/Framed", {}], ["/Units/Plain", {}], ["/Units/Missing", {}],
    ["/static/pyodide/pyodide.mjs", ENGINE_HEADERS], ["/static/swift/plantoir-swift-worker.js", ENGINE_HEADERS],
    ["/static/swift-wasm/abc.wasm", {}], ["/index.css", {}], ["/Broken", {}], ["/Broken.html", {}],
    ["/../../etc/passwd", {}], ["/Units/%E0%A4%A", {}],
  ]
  for (const [address, want] of expectations) {
    count += 1
    const got = headersFor(pub, address)
    if (JSON.stringify(got) !== JSON.stringify(want)) failures.push(`the preview's headers for ${address}: ${JSON.stringify(got)}`)
  }
}
console.log(JSON.stringify({ count, failures }))
"""


def run_the_rules_in_node(folder: Path) -> list:
    entry = folder / "runner.mjs"
    entry.write_text(RUNNER.replace("RULE_TS", str(RULE_TS)).replace("TRANSFORMER_TS", str(TRANSFORMER_TS))
                     .replace("ISOLATION_MJS", str(ISOLATION_MJS)), encoding="utf-8")
    bundle = folder / "runner.bundle.mjs"
    environment = dict(os.environ, NODE_PATH=str(NODE_MODULES))
    subprocess.run([str(ESBUILD), str(entry), "--bundle", "--format=esm", "--platform=node",
                    f"--outfile={bundle}", "--log-level=warning"], check=True, env=environment)
    rules = folder / "codeRunnerBlocks.json"
    rules.write_text(json.dumps(contracts.section("shared-rules", "codeRunnerBlocks")), encoding="utf-8")
    output = subprocess.run(["node", str(bundle), str(rules)], check=True, capture_output=True, text=True).stdout
    result = json.loads(output.strip().splitlines()[-1])
    print(f"codeRunnerRule.ts: {result['count']} contract cases run in Node over Quartz's own parser")
    return result["failures"]


def run_the_shapes_through_the_build() -> list:
    failures = []
    cases = contracts.section("shared-rules", "codeRunnerBlocks", "fences", "pageShapes", "cases")
    for case in cases:
        found = page_features.runner_fences(case["page"], True)
        if len(found) != case["runners"]:
            failures.append(f"pageShapes {case['name']}: the build finds {len(found)}, the contract says {case['runners']}")
    print(f"pageShapes: {len(cases)} shapes read by the build's fence reader")
    return failures


def read_through_the_build(folder: Path, lines: list, key: str):
    page = folder / "page.md"
    page.write_text("---\n" + "\n".join(lines) + "\n---\nBody.\n", encoding="utf-8")
    build_site.process_frontmatter(page, 1)
    return build_site.frontmatter.load(page).get(key)


def run_the_typed_lines(folder: Path) -> list:
    failures = []
    cases = contracts.section("file-formats", "pageOptIns", "codeRunnerReadingCases", "cases")
    for case in cases:
        got = read_through_the_build(folder, case["lines"], "codeRunner")
        if got != case["codeRunner"] or type(got) is not type(case["codeRunner"]):
            failures.append(f"codeRunnerReadingCases {case['lines']}: the build reads {got!r}, the contract says {case['codeRunner']!r}")
    print(f"codeRunnerReadingCases: {len(cases)} typed lines read through the build")
    return failures


def run_the_isolation_cases_through_the_publish() -> list:
    """The same isolation.cases through isolation_headers.py, the publish's
    half: the preview's and the publish's rule agree case for case."""
    import isolation_headers
    failures = []
    rules = contracts.section("shared-rules", "codeRunnerBlocks", "isolation")
    for case in rules["cases"]:
        got = isolation_headers.page_verdict(case["html"])
        if got != {"verdict": case["verdict"], "readsInput": case["readsInput"]}:
            failures.append(f"isolation.cases {case['name']}: the publish says {got}")
    print(f"isolation.cases: {len(rules['cases'])} pages read by the publish's rule")
    return failures


def run_the_quartz_patches(folder: Path) -> list:
    """Both of #583's edits to Quartz, made on copies of the image's own
    files three times over: each marker once, and each file still valid."""
    failures = []
    quartz = toolchain_paths.QUARTZ_DIR / "quartz"
    for source, wire, marker, name in (
        # .mjs for the copy: the original is a module only because Quartz's
        # package.json says so, and `node --check` reads a .js elsewhere as
        # CommonJS.
        (quartz / "cli" / "handlers.js", build_site._wire_isolation_serve, build_site.ISOLATION_SERVE_MARKER, "handlers.mjs"),
        (quartz / "components" / "scripts" / "spa.inline.ts", build_site._wire_isolation_nav, build_site.ISOLATION_NAV_MARKER, "spa.inline.ts"),
    ):
        target = folder / name
        target.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
        for _ in range(3):
            wire(target)
        text = target.read_text(encoding="utf-8")
        if text.count(marker) != 1:
            failures.append(f"{name}: {marker} is there {text.count(marker)} times after three builds")
        if name.endswith(".mjs"):
            checked = subprocess.run(["node", "--check", str(target)], capture_output=True, text=True)
        else:
            checked = subprocess.run([str(ESBUILD), str(target), "--log-level=error"],
                                     capture_output=True, text=True)
        if checked.returncode != 0:
            failures.append(f"{name}: no longer valid once patched: {checked.stderr.strip()[:300]}")
    print("Quartz's preview server and router: patched once each, and still valid")
    return failures


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        folder = Path(name)
        failures = (run_the_rules_in_node(folder) + run_the_shapes_through_the_build() + run_the_typed_lines(folder)
                    + run_the_isolation_cases_through_the_publish() + run_the_quartz_patches(folder))
    for failure in failures:
        print("FAIL " + failure)
    if failures:
        return 1
    print("OK: the runnable-code rules in the contract hold in the site and in the build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
