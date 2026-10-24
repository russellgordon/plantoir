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
// so for the teacher and any assistant reading the build. Each such block is
// also RECORDED on the page's file.data.plantoirSiteDisagreements - page,
// language, block, reason and code, exactly what the line says - and the
// emitter plantoirSiteSaid.ts says them all as ONE folder problem
// (#567: siteHealth.checks -> runnableCodeShownAsPlainCode), because a
// teacher previewing in the app never reads the build's console.
//
// A block that can ask for input as it runs carries data-runner-asks="input"
// or "edit" (#583, codeRunnerRule.asksFor): which pages the host isolates
// (scripts/isolation_headers.py, the preview's quartz/cli/plantoirIsolation.mjs)
// is read from it.
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
//
// Text that wraps (#653) rides here too, as markdownPlugins()' SECOND plugin:
// on EVERY page (no `codeRunner:` gate), a ```text fence whose info string
// holds `wrap` (textWrapRule.wrapsText) is wrapped in
// <div class="plantoir-text-wrap"> and nothing else changes - its `lang` and
// `meta` are left as written, so the highlighter treats it exactly as before.
// It shares this plugin's place straight before SyntaxHighlighting rather
// than being a plugin of its own, because a fourth wired plugin would be a
// config anchor edit in build_site.py for ten lines (rejected in the #653
// plan). codeLines.scss styles the wrapper.

import { Root as MdRoot, Code } from "mdast"
import { createHash } from "crypto"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { asksFor, findRunners, filled, MdNode, normaliseProgram, unclosedFenceBefore } from "./codeRunnerRule"
import { TEXT_WRAP_CLASS, wrapsText } from "./textWrapRule"

type RunnerFile = { words: Record<string, string>; carried: string[] }
// quartz/plantoir-runners/<engine>.json, for a `prebuilt` language (#493):
// each block's key, and whether the build has its program.
type Programs = Record<string, { ok: boolean; file?: string; reason?: string }>

const WORDS_FILE = join("quartz", "plantoir_code_runner.json")

// One runnable block the site showed as plain code (#567), as the
// `plantoir: error:` line names it: the page's path in the site's content
// (with .md), the language's fence, the block's number among that language's
// blocks on the page, the reason's key in words, and the code the site read.
export type SiteDisagreement = { page: string; language: string; block: number; reason: string; code: string }

declare module "vfile" {
  interface DataMap {
    plantoirSiteDisagreements: SiteDisagreement[]
  }
}

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
              let reasonKey = "blockNotPrepared"
              if (unclosed) {
                reason = known.words.blockAfterUnclosedFence
                reasonKey = "blockAfterUnclosedFence"
              } else if (carried.includes(runner.language.engine) && notListed && known.words.blockNotCompiled) {
                reason = known.words.blockNotCompiled
                reasonKey = "blockNotCompiled"
              }
              console.log(
                `plantoir: error: ${page}: ${runner.language.fence} block ${runner.n}: ` +
                  filled(reason, runner.language),
              )
              // The same block, recorded for the emitter (#567): the reason
              // by its key, so the finding can say it in words of its own.
              const recorded = (file.data.plantoirSiteDisagreements ?? []) as SiteDisagreement[]
              recorded.push({
                page,
                language: runner.language.fence,
                block: runner.n,
                reason: reasonKey,
                code: code.value,
              })
              file.data.plantoirSiteDisagreements = recorded
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
          const asks = asksFor(runner.language, runner.flags, code.value)
          if (asks !== null) {
            programProperties.dataRunnerAsks = asks
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
      // #653: every page, opted in or not.
      () => (tree: MdRoot) => {
        wrapTextFences(tree as unknown as WrapNode)
      },
    ]
  },
})

type WrapNode = { type: string; lang?: string | null; meta?: string | null; children?: WrapNode[] }

// Each ```text wrap block, wherever it sits (the top level, a list item, a
// quote, a callout, a quiz's explanation), put inside the wrapper in place.
function wrapTextFences(node: WrapNode): void {
  const children = node.children
  if (children === undefined) {
    return
  }
  for (let index = 0; index < children.length; index += 1) {
    const child = children[index]
    if (child.type === "code" && wrapsText(child.lang, child.meta)) {
      const wrapper = {
        type: "plantoirTextWrap",
        data: { hName: "div", hProperties: { className: [TEXT_WRAP_CLASS] } },
        children: [child],
      }
      children[index] = wrapper as unknown as WrapNode
    } else {
      wrapTextFences(child)
    }
  }
}
