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
// A `prebuilt` language's block (Swift, #493) carries one more attribute:
// data-runner-wasm="static/swift-wasm/<key>.wasm" when the build has its
// program (quartz/plantoir-runners/swift.json, written by
// scripts/swift_blocks.py), or data-runner-unready="<reason>" when the build
// said why not; a block whose key is not in that list at all stays plain
// code with its own line (words.blockNotCompiled).
//
// The page's own script (components/scripts/codeRunner.inline.ts) builds the
// editor and the buttons on top of the wrapper.

import { Root as MdRoot, Code } from "mdast"
import { createHash } from "crypto"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { findRunners, filled, MdNode, normaliseProgram, unclosedFenceBefore } from "./codeRunnerRule"

type RunnerFile = { words: Record<string, string>; carried: string[] }
// quartz/plantoir-runners/<engine>.json, for a `prebuilt` language (#493):
// each block's key, and whether the build has its program.
type Programs = Record<string, { ok: boolean; file?: string; reason?: string }>

const WORDS_FILE = join("quartz", "plantoir_code_runner.json")

const cache = new Map<string, { stamp: number; value: unknown }>()

// Read, not imported, so a missing file costs the Run buttons and never the
// site; re-read when the build writes it again (a preview's later builds).
function readJson<T>(relative: string): T | null {
  const path = join(process.cwd(), relative)
  let stamp = -1
  try {
    stamp = statSync(path).mtimeMs
  } catch {
    cache.delete(relative)
    return null
  }
  const known = cache.get(relative)
  if (known === undefined || known.stamp !== stamp) {
    let value: unknown = null
    try {
      value = JSON.parse(readFileSync(path, "utf-8"))
    } catch {
      value = null
    }
    cache.set(relative, { stamp, value })
    return value as T | null
  }
  return known.value as T | null
}

function runnerFile(): RunnerFile | null {
  return readJson<RunnerFile>(WORDS_FILE)
}

function programsOf(engine: string): Programs | null {
  return readJson<Programs>(join("quartz", "plantoir-runners", `${engine}.json`))
}

// A block's key (codeRunnerBlocks.swift.cacheKey): SHA-256 of its normalised code.
export function programKey(code: string): string {
  return createHash("sha256").update(normaliseProgram(code).text, "utf8").digest("hex")
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
        // A page students cannot see is parsed here too and dropped later
        // (patches/publish.ts, the same test): no line about it.
        const flag = file.data.frontmatter?.publish
        const published = !(flag === false || flag === "false")
        for (const runner of runners) {
          const code = runner.node as unknown as Code
          // A `prebuilt` block (#493) also needs its key in the build's list
          // of programs; one that is missing there is the same safety-net
          // case as an engine the site does not carry (siteDisagrees).
          let program: { ok: boolean; file?: string; reason?: string } | undefined = undefined
          let notListed = false
          if (runner.language.prebuilt) {
            program = programsOf(runner.language.engine)?.[programKey(code.value)]
            notListed = program === undefined
          }
          if (!carried.includes(runner.language.engine) || !known?.words?.blockNotPrepared || notListed) {
            if (known?.words?.blockNotPrepared && published) {
              // Say what is wrong when it can be seen: an unclosed fence above.
              const unclosed =
                known.words.blockAfterUnclosedFence !== undefined &&
                unclosedFenceBefore(tree as unknown as MdNode, String(file.value ?? ""), runner.node)
              let reason = known.words.blockNotPrepared
              if (unclosed) {
                reason = known.words.blockAfterUnclosedFence
              } else if (carried.includes(runner.language.engine) && notListed && known.words.blockNotCompiled) {
                reason = known.words.blockNotCompiled
              }
              console.log(
                `plantoir: error: ${page}: ${runner.language.fence} block ${runner.n}: ` +
                  filled(reason, runner.language),
              )
            }
            continue
          }
          const programProperties: Record<string, string> = {}
          if (program !== undefined) {
            if (program.ok && program.file) {
              programProperties.dataRunnerWasm = `static/${runner.language.engine}-wasm/${program.file}`
            } else {
              programProperties.dataRunnerUnready = program.reason ?? "notCompiled"
            }
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
                ...programProperties,
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
