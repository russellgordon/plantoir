#!/usr/bin/env python3
"""
The music fence rules in the contract, run through the SITE's own Markdown
reader and the image's own engine (#679), as check_phet_rules_against_the_site.py
runs PhET's.

NOT named `test_*.py` on purpose: it needs the image's Node, Quartz's own
node_modules and /opt/vendor/music-engine, so it can only run inside the
container (Windows' PythonToolchainTests discovers every `scripts/test_*.py`).
verify.sh runs it in the image.

What scripts/test_music.py cannot reach without them:

* The site's transformer (plantoirMusic.ts) finds a tune's drawing in the
  manifest by `keyOf(code.value)` (figureRules.js on the mdast code node the
  site's Markdown reader made), while the build keys the same fence by
  figures.key_of on markdown_code's body. If the two disagreed, the build
  would say the tune was drawn and the page would show a code block, with no
  folder problem. So every musicFences.fences case is read here by
  mdast-util-from-markdown with GitHub's extensions, from Quartz's own
  node_modules, through the quizzes' own text hook first, and each tune's
  count, line and key compared with the build's.
* Which sounds a tune needs is abcjs's own answer: every
  musicFences.sounds.needed case is drawn by the REAL helper with the
  image's abcjs (music.draw_all), and the engine file a site carries is
  checked against its pin (fileSha256).
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import music  # noqa: E402
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
const failures = []
for (const c of block.cases) {
  const tree = fromMarkdown(nestedTitlesOwnTheirLine(c.page), { extensions: [gfm()], mdastExtensions: [gfmFromMarkdown()] })
  const found = []
  const walk = (node) => {
    if (node.type === "code" && block.languages.includes(node.lang ?? "")) found.push(node)
    for (const child of node.children ?? []) walk(child)
  }
  walk(tree)
  const read = found.map((node, index) => ({ block: index + 1, line: node.position.start.line, key: rules.keyOf(node.value) }))
  if (JSON.stringify(read) !== JSON.stringify(c.expect)) failures.push(`fences ${c.name}: the site reads ${JSON.stringify(read)}`)
}
console.log(JSON.stringify(failures))
"""


def main() -> int:
    contracts.reset_cache()
    failures = []
    cases = []
    for case in music.rules("fences", "cases"):
        expect = [{"block": tune["block"], "line": tune["line"], "key": tune["key"]}
                  for tune in music.tunes_on_page(case["page"])]
        cases.append({"name": case["name"], "page": case["page"], "expect": expect})
    block = {"languages": music.rules("fences", "languages"), "cases": cases}
    work = Path(tempfile.mkdtemp(prefix="plantoir-music-rules-"))
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

    needed = music.rules("sounds", "needed", "cases")
    answers = music.draw_all([{"id": str(index), "abc": case["abc"]} for index, case in enumerate(needed)],
                             music.helper_command())
    for index, case in enumerate(needed):
        answer = answers.get(str(index)) or {}
        if not answer.get("ok"):
            failures.append(f"needed {case['name']}: the helper did not draw it ({answer.get('reason')})")
        elif answer.get("programs") != case["programs"]:
            failures.append(f"needed {case['name']}: abcjs says {answer.get('programs')}")
    pins = {pin["pin"]: pin for pin in contracts.load("toolchain")["pins"]}
    engine_file = music.engine_dir() / "node_modules" / "abcjs" / "dist" / music.ENGINE_FILE
    try:
        if hashlib.sha256(engine_file.read_bytes()).hexdigest() != pins["abcjs"]["fileSha256"]:
            failures.append(f"{music.ENGINE_FILE} is not the pinned file")
    except OSError as error:
        failures.append(f"{music.ENGINE_FILE} could not be read: {error.strerror}")

    for failure in failures:
        print("   " + failure)
    total = len(cases) + len(needed) + 1
    print(f"{'FAIL' if failures else 'PASS'}: musicFences fences through the site's own Markdown reader, the "
          f"sounds abcjs says each tune needs, and the engine's pin ({total} checks, {len(failures)} problem(s))")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
