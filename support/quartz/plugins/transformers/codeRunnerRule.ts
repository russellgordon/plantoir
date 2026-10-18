// Runnable code (#455): the RULES, with nothing of Quartz's in them, so the
// transformer (codeRunner.ts) and the page's own script
// (components/scripts/codeRunner.inline.ts) share one copy, and
// scripts/check_runner_rules_against_the_site.py can bundle this file alone
// and run every case in contracts/shared-rules.json -> codeRunnerBlocks
// (fences, fences.pageShapes, ids) through it in Node.
//
// LANGUAGES is the literal mirror of codeRunnerBlocks.languages - the ONE
// table everything reads (the fence rule, the ids, which engine a block
// needs, the words' {language}). The check script compares it with the
// contract field for field; scripts/page_features.py holds the Python mirror.
// A second language is a row here, a row there, a runtime class in
// codeRunner.inline.ts, a vendor layer and a pin - nothing else. Swift (#493)
// is the second: `prebuilt`, so its vendor layer is the compile step
// (scripts/swift_blocks.py, support/swift) and its pin the Swift image's.
// `colour` (#585) names the tokenizer in components/scripts/
// codeRunnerColour.ts that colours the language's editor.

export type RunnerLanguage = {
  fence: string // the info string's first word, exactly (lowercase, Q1)
  idPrefix: string // "py" -> <slug>-py-<n>
  displayName: string // fills {language} in the words
  runtime: string // which class in codeRunner.inline.ts runs it
  engine: string // the folder under static/ the site carries
  worker: string // the file inside static/<engine>/ the page starts
  editable: boolean
  flags: string[] // the tokens after `run` this language accepts
  inputCall: string // fills {inputCall}
  inputPattern: string // shows the input box without the stdin flag
  prebuilt: boolean // false: the browser runs the source as written; true: the build compiled it (#493)
  colour: string | null // the editor's colours (#585): codeRunnerColour.ts's tokenizer for this language, or none
}

export const LANGUAGES: RunnerLanguage[] = [
  {
    fence: "python",
    idPrefix: "py",
    displayName: "Python",
    runtime: "pyodide",
    engine: "pyodide",
    worker: "plantoir-worker.js",
    editable: true,
    flags: ["readonly", "stdin", "autorun"],
    inputCall: "input()",
    inputPattern: "\\binput\\s*\\(",
    prebuilt: false,
    colour: "python",
  },
  {
    fence: "swift",
    idPrefix: "swift",
    displayName: "Swift",
    runtime: "swift-wasm",
    engine: "swift",
    worker: "plantoir-swift-worker.js",
    editable: false,
    flags: ["stdin", "autorun"],
    inputCall: "readLine()",
    inputPattern: "\\breadLine\\s*\\(",
    prebuilt: true,
    colour: "swift",
  },
]

export function languageFor(fence: string): RunnerLanguage | null {
  for (const language of LANGUAGES) {
    if (language.fence === fence) {
      return language
    }
  }
  return null
}

// The separators between the words of an info string, the SAME set as the
// build's (page_features.INFO_SPACE): tab, space and Unicode's space
// separators, NBSP among them (Option-Space on a Mac) - #455 review N2.
// micromark splits mdast's `lang` from `meta` on space and tab only, so a
// fence written `python<NBSP>run` arrives with all of it in `lang`; joining
// the two and splitting again reads it as the build does. Not \s, which adds
// U+FEFF where Python's str.split() adds \x1c-\x1f and \x85.
export const INFO_SPACE = /[\t \u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]+/

// Is a fence with this info string runnable (codeRunnerBlocks.fences)? The
// info string (mdast's `lang`, then `meta`) is split on INFO_SPACE; its first
// word is the language, exactly; `run` must be one of the other words; flags
// are the row's own, exact, each once, in the row's order.
export function runnerFor(
  lang: string | null | undefined,
  meta: string | null | undefined,
  optedIn: boolean,
): { language: RunnerLanguage; flags: string[] } | null {
  if (!optedIn) {
    return null
  }
  const words = `${lang ?? ""} ${meta ?? ""}`.split(INFO_SPACE).filter((word) => word.length > 0)
  if (words.length === 0) {
    return null
  }
  const language = languageFor(words[0])
  if (language === null) {
    return null
  }
  const tokens = words.slice(1)
  if (!tokens.includes("run")) {
    return null
  }
  const flags: string[] = []
  for (const flag of language.flags) {
    if (tokens.includes(flag)) {
      flags.push(flag)
    }
  }
  return { language, flags }
}

// Can a block ask for input as it runs (#583, codeRunnerBlocks.liveInput.asks)?
// "input" when it reads input as written (the stdin flag, or the row's input
// pattern in its code), "edit" when only because a student can edit it (an
// editable language without `readonly` - they may add the call), or null. The
// transformer writes it on the wrapper as data-runner-asks; a page's headers
// and the publish's note line read that, never the language table.
export function asksFor(language: RunnerLanguage, flags: string[], code: string): "input" | "edit" | null {
  if (flags.includes("stdin") || new RegExp(language.inputPattern).test(code)) {
    return "input"
  }
  if (language.editable && !flags.includes("readonly")) {
    return "edit"
  }
  return null
}

export function runnerId(slug: string, language: RunnerLanguage, n: number): string {
  return `${slug}-${language.idPrefix}-${n}`
}

// The pieces of mdast this needs, so the file stays free of Quartz's types.
type Position = { start: { line: number; offset?: number }; end?: { offset?: number } }
export type MdNode = {
  type: string
  lang?: string | null
  meta?: string | null
  value?: string
  position?: Position
  children?: MdNode[]
}

export type FoundRunner = {
  node: MdNode
  parent: MdNode
  index: number
  language: RunnerLanguage
  flags: string[]
  id: string
  n: number // this language's count on the page, from 1
}

// A fence opened on a line that opens a list item holding ANOTHER container
// on that same line (`- - ```python run`, `1. > ```python run`) is a code
// block to Quartz's parser, but the build's reader treats it as nested
// (markdown_code.fenced_blocks) and never makes it runnable - so neither does
// the site (codeRunnerBlocks.fences.pageShapes, review S2). Quotes before the
// first list marker (`> - ```...`) are fine on both sides.
function opensAfterANestedContainer(node: MdNode, ancestors: MdNode[]): boolean {
  const line = node.position?.start.line
  if (line === undefined) {
    return false
  }
  let sawListItem = false
  for (const ancestor of ancestors) {
    if (ancestor.type !== "listItem" && ancestor.type !== "blockquote") {
      continue
    }
    if (ancestor.position?.start.line !== line) {
      continue
    }
    if (sawListItem) {
      return true
    }
    if (ancestor.type === "listItem") {
      sawListItem = true
    }
  }
  return false
}

// Every runnable block on a page, in document order, with its id.
export function findRunners(tree: MdNode, optedIn: boolean, slug: string): FoundRunner[] {
  const found: FoundRunner[] = []
  if (!optedIn) {
    return found
  }
  const counts = new Map<string, number>()
  const walk = (node: MdNode, ancestors: MdNode[]) => {
    const children = node.children ?? []
    for (let index = 0; index < children.length; index += 1) {
      const child = children[index]
      if (child.type === "code") {
        const runner = runnerFor(child.lang, child.meta, true)
        if (runner !== null && !opensAfterANestedContainer(child, [...ancestors, node])) {
          const n = (counts.get(runner.language.fence) ?? 0) + 1
          counts.set(runner.language.fence, n)
          found.push({
            node: child,
            parent: node,
            index,
            language: runner.language,
            flags: runner.flags,
            id: runnerId(slug, runner.language, n),
            n,
          })
        }
        continue
      }
      walk(child, [...ancestors, node])
    }
  }
  walk(tree, [])
  return found
}

// {language} and {inputCall} filled from the table row.
export function filled(text: string, language: RunnerLanguage): string {
  return text.split("{language}").join(language.displayName).split("{inputCall}").join(language.inputCall)
}

// The code a `prebuilt` block's program was compiled from (#493:
// contracts/shared-rules.json -> codeRunnerBlocks.swift.cacheKey), the SAME
// rule as scripts/swift_blocks.normalise: split on "\n"; spaces, tabs and
// carriage returns (and form feeds and vertical tabs) off the end of each
// line; the indentation every non-blank line shares off; blank lines at the
// start and the end dropped. Its SHA-256 is the block's key, which the
// transformer computes with node's crypto (not here: this file is bundled
// into the page's script too).
export function normaliseProgram(body: string): { text: string; droppedAtTop: number } {
  let lines = body.split("\n").map((line) => line.replace(/[ \t\r\f\v]+$/, ""))
  let shared: string | null = null
  for (const line of lines) {
    if (line === "") {
      continue
    }
    const indent = /^[ \t]*/.exec(line)![0]
    if (shared === null) {
      shared = indent
    } else {
      let common = 0
      while (common < shared.length && common < indent.length && shared[common] === indent[common]) {
        common += 1
      }
      shared = shared.slice(0, common)
    }
  }
  if (shared !== null && shared.length > 0) {
    const cut = shared.length
    lines = lines.map((line) => (line === "" ? line : line.slice(cut)))
  }
  let droppedAtTop = 0
  while (lines.length > 0 && lines[0] === "") {
    lines.shift()
    droppedAtTop += 1
  }
  while (lines.length > 0 && lines[lines.length - 1] === "") {
    lines.pop()
  }
  return { text: lines.join("\n"), droppedAtTop }
}

// FNV-1a, 32 bits, over UTF-16 code units, as hex: the hash a student's
// saved edits remember the teacher's code by (codeRunnerBlocks.storage). Not
// crypto.subtle, which a preview reached over a school network's plain http
// does not have.
export function fnv1a(text: string): string {
  let hash = 0x811c9dc5
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index)
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash.toString(16).padStart(8, "0")
}

// Was a fenced code block ABOVE this one on the page never closed? The
// likeliest reason the build's reader and the site disagree about a block
// (#455 review N3: an unclosed fence in a list item, which the site closes at
// the end of the item and the build's reader carries on through). Read from
// the page's own text at each earlier code node's position: a block whose
// first line opens a fence (``` or ~~~, after quote and list markers) and
// whose last line is not a closing run of the same character, at least as
// long, was never closed.
const OPENER = /^(?:[ \t]*(?:>|[-*+]|[0-9]{1,9}[.)])[ \t]*)*(`{3,}|~{3,})/
export function unclosedFenceBefore(tree: MdNode, source: string, block: MdNode): boolean {
  const before = block.position?.start.offset
  if (before === undefined) {
    return false
  }
  let unclosed = false
  const walk = (node: MdNode) => {
    for (const child of node.children ?? []) {
      if (child.type === "code") {
        const start = child.position?.start.offset
        const end = child.position?.end?.offset
        if (start !== undefined && end !== undefined && start < before) {
          const lines = source.slice(start, end).split("\n")
          const opened = OPENER.exec(lines[0])
          if (opened !== null) {
            const last = lines.length > 1 ? lines[lines.length - 1].replace(/^[ \t>]*/, "") : ""
            const closing = /^(`{3,}|~{3,})[ \t]*$/.exec(last)
            if (closing === null || closing[1][0] !== opened[1][0] || closing[1].length < opened[1].length) {
              unclosed = true
            }
          }
        }
        continue
      }
      walk(child)
    }
  }
  walk(tree)
  return unclosed
}
