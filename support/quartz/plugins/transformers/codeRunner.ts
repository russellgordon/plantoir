// Runnable code (#455): the site's half that runs when the site is BUILT.
//
// On a page whose frontmatter says `codeRunner: true`, every runnable block
// (codeRunnerRule.findRunners: ```python run, the language table's rule) is
// wrapped, at the MARKDOWN stage, in
//
//   <div class="plantoir-runner" data-runner-id data-runner-flags
//        data-runner-language data-runner-runtime data-runner-engine
//        data-original>  ...the block, highlighted as always...  </div>
//
// and nothing else changes: the info string (meta) is left as it was, so the
// highlighter treats the block exactly as before, and a page that does not
// opt in - or a block that is not runnable - comes out byte for byte as it
// did. A wrapper rather than attributes on <pre>/<code> because
// rehype-pretty-code 0.14 drops every property on those two (measured
// 2026-10-09); the wrapper survives at the top level, in lists, in quotes and
// in folded callouts. It must run BEFORE SyntaxHighlighting, which is where
// build_site.wire_quartz_additions puts it. `data-original` is mdast's value,
// the teacher's code exactly (the highlighted copy has had blank lines turned
// into spaces).
//
// The safety net (codeRunnerBlocks.siteDisagrees, review S2): the build wrote
// the engines this site carries into quartz/plantoir_code_runner.json. A
// runnable block whose language's engine is not there stays plain code - a
// student never meets a Run button that can never work - and one line says
// so for the teacher and any assistant reading the build.
//
// The page's own script (components/scripts/codeRunner.inline.ts) builds the
// editor and the buttons on top of the wrapper.

import { Root as MdRoot, Code } from "mdast"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { findRunners, filled, MdNode } from "./codeRunnerRule"

type RunnerFile = { words: Record<string, string>; carried: string[] }

const WORDS_FILE = join("quartz", "plantoir_code_runner.json")

let cached: { stamp: number; file: RunnerFile | null } | null = null

// Read, not imported, so a missing file costs the Run buttons and never the
// site; re-read when the build writes it again (a preview's later builds).
function runnerFile(): RunnerFile | null {
  const path = join(process.cwd(), WORDS_FILE)
  let stamp = -1
  try {
    stamp = statSync(path).mtimeMs
  } catch {
    cached = null
    return null
  }
  if (cached === null || cached.stamp !== stamp) {
    try {
      cached = { stamp, file: JSON.parse(readFileSync(path, "utf-8")) as RunnerFile }
    } catch {
      cached = { stamp, file: null }
    }
  }
  return cached.file
}

export const CodeRunnerFences: QuartzTransformerPlugin = () => ({
  name: "CodeRunnerFences",
  markdownPlugins() {
    return [
      () => (tree: MdRoot, file) => {
        if (file.data.frontmatter?.codeRunner !== true) {
          return
        }
        const slug = String(file.data.slug ?? "")
        const runners = findRunners(tree as unknown as MdNode, true, slug)
        if (runners.length === 0) {
          return
        }
        const known = runnerFile()
        const carried = known?.carried ?? []
        const page = String(file.data.relativePath ?? slug + ".md")
        for (const runner of runners) {
          const code = runner.node as unknown as Code
          if (!carried.includes(runner.language.engine) || !known?.words?.blockNotPrepared) {
            if (known?.words?.blockNotPrepared) {
              console.log(
                `plantoir: error: ${page}: ${runner.language.fence} block ${runner.n}: ` +
                  filled(known.words.blockNotPrepared, runner.language),
              )
            }
            continue
          }
          const wrapper = {
            type: "plantoirRunner",
            data: {
              hName: "div",
              hProperties: {
                className: ["plantoir-runner"],
                dataRunnerId: runner.id,
                dataRunnerFlags: runner.flags.join(" "),
                dataRunnerLanguage: runner.language.fence,
                dataRunnerRuntime: runner.language.runtime,
                dataRunnerEngine: runner.language.engine,
                dataOriginal: code.value,
              },
            },
            children: [code],
          }
          ;(runner.parent.children as unknown[])[runner.index] = wrapper
        }
      },
    ]
  },
})
