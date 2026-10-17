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
// codeRunner.inline.ts, a vendor layer and a pin - nothing else.

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
  prebuilt: boolean // false: the browser runs the source as written
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

// Is a fence with this info string runnable (codeRunnerBlocks.fences)? The
// language is mdast's `lang` (the info string's first word); `run` must be a
// whitespace-separated token of `meta`; flags are the row's own, exact, each
// once, in the row's order.
export function runnerFor(
  lang: string | null | undefined,
  meta: string | null | undefined,
  optedIn: boolean,
): { language: RunnerLanguage; flags: string[] } | null {
  if (!optedIn) {
    return null
  }
  const language = languageFor(lang ?? "")
  if (language === null) {
    return null
  }
  const tokens = (meta ?? "").split(/\s+/).filter((token) => token.length > 0)
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

export function runnerId(slug: string, language: RunnerLanguage, n: number): string {
  return `${slug}-${language.idPrefix}-${n}`
}

// The pieces of mdast this needs, so the file stays free of Quartz's types.
type Position = { start: { line: number } }
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
