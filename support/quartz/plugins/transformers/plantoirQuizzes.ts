// Self-check quizzes (#563): the site's half that runs when the site is BUILT.
//
// A teacher writes, on any page:
//
//   > [!quiz] Which is a factor of $x^2 - 5x + 6$?
//   > - [x] $x - 2$
//   > - [ ] $x + 2$
//
// and the student gets real radio buttons, Check and Show answer. The rules
// (what a quiz is, how an answer line reads, when a quiz cannot be checked)
// are quizRules.ts's - shared with the page's own script - and
// contracts/shared-rules.json -> quizCallouts pins them. Three hooks:
//
// * text: Quartz's ObsidianFlavoredMarkdown gives a callout's title line a
//   paragraph of its own only at the page's left edge, so a nested
//   `> > [!answer]-` followed by `> > $2^7$` put the answer INTO the title
//   (measured, #563 plan M2). Inside a quiz only (ruling Q1), after any
//   nested callout's first line, this adds one line holding just its `>`
//   markers. Line endings are made LF first (review S1: a page saved on
//   Windows), fenced code is skipped (S2), and a page with no quiz outside
//   fenced code is returned exactly as it came
//   (quizRules.nestedTitlesOwnTheirLine).
// * markdown stage (after GitHubFlavoredMarkdown, so a task item's box has
//   been read): every quiz that is a child of the page itself becomes the
//   markup the page's script builds on - choices in a <fieldset>, a box for
//   a short answer, the answer and explanation held back (hidden) until the
//   student answers - and every box's tick is taken off, so the answer key
//   never reaches the page. A quiz that cannot be checked, or one inside a
//   list or another callout (ruling Q3), shows its question and one line
//   saying so, with its answer and explanation removed (Q6). Answer lines
//   are read from the page's own text, never from the parsed tree, which has
//   already turned "quotes" curly and `\|` into `|` (M3).
// * html stage (after Description): ids and labels, blanks into boxes, and
//   the page's search text and summary made again without the answers and
//   explanations (Q5, review S3).
//
// The safety net (quizCallouts.safetyNet, review S4): the folder check
// (scripts/quizzes.py) wrote what it found on each page it examined into
// quartz/plantoir_quiz_pages.json. A quiz this file renders as not ready, or
// reads as fine, that the check read the other way says so on a
// `plantoir: error:` line - quietly agreeing otherwise. Pages the check did
// not examine (a page students cannot see is parsed here too and dropped
// later) are never named. Each line it prints is also recorded on the
// page's file.data.plantoirQuizDisagreements (#644), which the site's
// emitter (emitters/plantoirSiteSaid.ts) says as ONE quizzesReadDifferently
// folder problem, in the same call as the code runner's - a teacher
// previewing in the app never reads the console.

import { Root as MdRoot, Html } from "mdast"
import { Element, ElementContent, Root as HtmlRoot } from "hast"
import { visit } from "unist-util-visit"
import { toString } from "hast-util-to-string"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { escapeHTML } from "../../util/escape"
import { fnv1a } from "./codeRunnerRule"
import {
  filledWords,
  isBlank,
  nestedTitlesOwnTheirLine,
  parseAnswerLine,
  QuizModel,
  splitAlternatives,
  TASK_ITEM_TEXT,
  Verdict,
  verdict,
} from "./quizRules"

type QuizWords = { words: Record<string, string>; problems: Record<string, string> }
type PageFindings = {
  quizzes: number
  problems: number[]
  nested: number
  nestedProblems: number[]
  lines?: Array<number | null>
  nestedLines?: Array<number | null>
}
type QuizPages = { examined: string[]; pages: Record<string, PageFindings> }

// One per `plantoir: error:` line the safety net prints (#644): the page's
// path in the site's content, the quiz's place (only when the counts agree
// and one quiz is read differently), the line the folder check found in the
// teacher's file, the siteHealth -> quizzesReadDifferently -> reasons key,
// and - for shownWithNote - the problem the SITE found, with its values.
export type QuizDisagreement = {
  page: string
  n: number | null
  line: number | null
  reason: "shownWithNote" | "shownWorking" | "countedDifferently" | "nestedReadDifferently"
  problem?: string
  fill?: Record<string, string | number>
}

declare module "vfile" {
  interface DataMap {
    plantoirQuizDisagreements: QuizDisagreement[]
  }
}

const WORDS_FILE = join("quartz", "plantoir_quiz.json")
const PAGES_FILE = join("quartz", "plantoir_quiz_pages.json")

const cache = new Map<string, { stamp: number; value: unknown }>()

// Read, not imported, so a missing file costs the quizzes (every quiz then
// shows as not ready, never with its answers) and never the site; read again
// when the build writes it again (a preview's later builds).
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

// ---- The markdown stage -------------------------------------------------------

type AnyNode = { type: string; children?: AnyNode[]; data?: Record<string, any>; position?: any; [key: string]: any }

function calloutKind(node: AnyNode): string | null {
  if (node.type !== "blockquote") {
    return null
  }
  const kind = node.data?.hProperties?.["data-callout"]
  return typeof kind === "string" ? kind : null
}

function contentOf(quiz: AnyNode): AnyNode | null {
  const second = quiz.children?.[1]
  if (second && second.type === "blockquote" && second.data?.hName === "div") {
    return second
  }
  return null
}

function boxed(list: AnyNode): boolean {
  for (const item of list.children ?? []) {
    if (item.checked === true || item.checked === false) {
      return true
    }
  }
  return false
}

// Every task item's tick off, everywhere inside the quiz: an answer key in a
// student's page source is still an answer key (M7).
function untick(node: AnyNode) {
  if (node.type === "listItem" && (node.checked === true || node.checked === false)) {
    node.checked = false
  }
  for (const child of node.children ?? []) {
    untick(child)
  }
}

function blanksIn(node: AnyNode): number {
  let count = 0
  visit(node as any, "inlineCode", (code: any) => {
    if (isBlank(code.value)) {
      count += 1
    }
  })
  return count
}

function blanksInTitle(html: string): number {
  let count = 0
  for (const match of html.matchAll(/<code>([^<]*)<\/code>/g)) {
    if (isBlank(match[1])) {
      count += 1
    }
  }
  return count
}

// The answer lines, from the page's own text (M3): the lines after the
// [!answer] title, each without up to two `>` markers (the quiz's and the
// answer's), trimmed, empty ones left out.
function answerLines(node: AnyNode, source: string[]): string[] {
  const start = node.position?.start?.line
  const end = node.position?.end?.line
  const lines: string[] = []
  if (typeof start !== "number" || typeof end !== "number") {
    return lines
  }
  for (let line = start + 1; line <= end; line += 1) {
    const text = (source[line - 1] ?? "").replace(/^(?: {0,3}>[ \t]?){0,2}/, "").trim()
    if (text !== "") {
      lines.push(text)
    }
  }
  return lines
}

function optionsOf(metadata: unknown): string[] {
  if (typeof metadata !== "string") {
    return []
  }
  const found: string[] = []
  for (const piece of metadata.split(/[|\s]+/)) {
    if (piece !== "") {
      found.push(piece)
    }
  }
  return found
}

function element(type: string, hName: string, hProperties: Record<string, unknown>, children: AnyNode[] = []): AnyNode {
  return { type, data: { hName, hProperties }, children }
}

function textNode(value: string): AnyNode {
  return { type: "text", value }
}

// A template with one {name} that stands for nodes rather than text
// ("Answer: {answer}"), the rest filled as words.
function wordsAround(template: string, name: string, nodes: AnyNode[], values: Record<string, string | number> = {}): AnyNode[] {
  const at = template.indexOf(`{${name}}`)
  if (at < 0) {
    return [textNode(filledWords(template, values))]
  }
  const result: AnyNode[] = []
  const before = filledWords(template.slice(0, at), values)
  const after = filledWords(template.slice(at + name.length + 2), values)
  if (before !== "") {
    result.push(textNode(before))
  }
  for (const node of nodes) {
    result.push(node)
  }
  if (after !== "") {
    result.push(textNode(after))
  }
  return result
}

type Parse = (text: string) => AnyNode

// One alternative as a student should see it: a `$...$` one through the
// page's own parser (review S9: only a parsed formula node reaches KaTeX),
// a tolerance as "100 (± 1)", anything else as its text.
function shownAlternative(text: string, words: Record<string, string>, parse: Parse | null): AnyNode[] {
  const parsed = parseAnswerLine(text)
  if ("alternatives" in parsed && parsed.alternatives.length === 1) {
    const only = parsed.alternatives[0]
    if (only.kind === "tolerance") {
      // Split where quizRules split it: the first ± or +-.
      const plusMinus = text.indexOf("\u00b1")
      const ascii = text.indexOf("+-")
      const useAscii = ascii >= 0 && (plusMinus < 0 || ascii < plusMinus)
      const at = useAscii ? ascii : plusMinus
      const value = text.slice(0, at).trim()
      const tolerance = text.slice(at + (useAscii ? 2 : 1)).trim()
      return [textNode(filledWords(words.tolerance ?? "{value} (± {tolerance})", { value, tolerance }))]
    }
    if (only.kind === "math" && parse !== null) {
      try {
        const tree = parse(text)
        const first = tree.children?.[0]
        if (first && first.type === "paragraph" && first.children) {
          return first.children
        }
      } catch {
        // Shown as typed below.
      }
    }
  }
  return [textNode(text)]
}

function answerDisplay(lines: string[], words: Record<string, string>, parse: Parse | null): AnyNode {
  const shown: AnyNode[] = []
  lines.forEach((line, lineIndex) => {
    // Each alternative as the teacher wrote it, `$...$` included.
    const texts = splitAlternatives(line)
    // Each alternative as written (the `\|` already a `|`), the first shown
    // as THE answer and the rest after "Also accepted".
    const pieces: AnyNode[] = []
    const first = texts[0] ?? line
    const firstNodes = texts.length > 0 ? shownAlternative(first, words, parse) : [textNode(line)]
    // One blank's answer is "Blank 2: ...", a short answer's "Answer: ...".
    const template = lines.length > 1 ? words.blankAnswerIs ?? "{n}: {answer}" : words.answerIs ?? "{answer}"
    for (const node of wordsAround(template, "answer", firstNodes, { n: lineIndex + 1 })) {
      pieces.push(node)
    }
    if (texts.length > 1) {
      const others: AnyNode[] = []
      texts.slice(1).forEach((text, index) => {
        if (index > 0) {
          others.push(textNode(", "))
        }
        for (const node of shownAlternative(text, words, parse)) {
          others.push(node)
        }
      })
      pieces.push(textNode(" "))
      for (const node of wordsAround(words.alsoAccepted ?? "({answers})", "answers", others)) {
        pieces.push(node)
      }
    }
    shown.push({ type: "paragraph", children: pieces })
  })
  return element("plantoirQuizAnswer", "div", { className: ["plantoir-quiz-answer"], hidden: true }, shown)
}

function notReadyNote(words: Record<string, string>): AnyNode {
  return {
    type: "paragraph",
    data: { hProperties: { className: ["plantoir-quiz-not-ready"] } },
    children: [textNode(words.notReady || "This question can't be checked on this site yet.")],
  }
}

function addClass(node: AnyNode, name: string) {
  const properties = (node.data ??= {}).hProperties ?? (node.data.hProperties = {})
  const existing = properties.className
  if (typeof existing === "string") {
    properties.className = existing + " " + name
  } else if (Array.isArray(existing)) {
    properties.className = [...existing, name]
  } else {
    properties.className = name
  }
}

// A quiz that cannot be checked: its question, its choices with every box
// empty, and one line - its answer and explanation gone (ruling Q6).
function renderNotReady(quiz: AnyNode, problem: string, words: Record<string, string>) {
  untick(quiz)
  const content = contentOf(quiz)
  addClass(quiz, "plantoir-quiz")
  const properties = quiz.data!.hProperties
  properties.dataQuizKind = "notReady"
  properties.dataQuizProblem = problem
  const kept: AnyNode[] = []
  for (const child of content?.children ?? []) {
    const kind = calloutKind(child)
    if (kind === "answer" || kind === "explain") {
      continue
    }
    kept.push(child)
  }
  kept.push(notReadyNote(words))
  if (content !== null) {
    content.children = kept
  } else {
    quiz.children = [...(quiz.children ?? []), element("plantoirQuizContent", "div", { className: "callout-content" }, kept)]
  }
}

function choiceNode(item: AnyNode, index: number, kind: string, words: Record<string, string>): AnyNode {
  const children = item.children ?? []
  const first = children[0]
  const phrasing = first && first.type === "paragraph" ? first.children ?? [] : []
  const more = first && first.type === "paragraph" ? children.slice(1) : children
  const fallback = phrasing.length === 0
  const label = element(
    "plantoirQuizLabel",
    "label",
    { className: ["plantoir-quiz-choice-label"] },
    [
      element("plantoirQuizInput", "input", {
        type: kind === "single" ? "radio" : "checkbox",
        className: ["plantoir-quiz-input"],
      }),
      element(
        "plantoirQuizChoiceText",
        "span",
        { className: ["plantoir-quiz-choice-text"], dataChoiceFallback: fallback ? "true" : undefined },
        fallback ? [textNode(filledWords(words.choiceNumber ?? "Choice {n}", { n: index + 1 }))] : phrasing,
      ),
    ],
  )
  const parts = [label]
  if (more.length > 0) {
    // Outside the label, so pressing Run on code in a choice, or a graph's
    // controls, never ticks it.
    parts.push(element("plantoirQuizChoiceMore", "div", { className: ["plantoir-quiz-choice-more"] }, more))
  }
  return element("plantoirQuizChoice", "div", { className: ["plantoir-quiz-choice"], dataChoice: String(index) }, parts)
}

function renderQuiz(
  quiz: AnyNode,
  result: Exclude<Verdict, { problem: string }>,
  words: Record<string, string>,
  parse: Parse | null,
) {
  untick(quiz)
  addClass(quiz, "plantoir-quiz")
  const properties = quiz.data!.hProperties
  properties.dataQuizKind = result.kind
  if (result.shuffle) {
    properties.dataQuizShuffle = "true"
  }
  properties.dataQuiz = JSON.stringify(
    result.kind === "single" || result.kind === "multiple" ? { correct: result.correct } : { answers: result.answers },
  )
  const content = contentOf(quiz)!
  const children: AnyNode[] = []
  let choicesPlaced = false
  for (const child of content.children ?? []) {
    const kind = calloutKind(child)
    if (child.type === "list" && boxed(child) && !choicesPlaced) {
      choicesPlaced = true
      const items: AnyNode[] = []
      if (result.kind === "multiple") {
        items.push(
          element("plantoirQuizHint", "p", { className: ["plantoir-quiz-hint"] }, [textNode(words.selectAll ?? "")]),
        )
      }
      ;(child.children ?? []).forEach((item, index) => items.push(choiceNode(item, index, result.kind, words)))
      children.push(element("plantoirQuizChoices", "fieldset", { className: ["plantoir-quiz-choices"] }, items))
      continue
    }
    if (kind === "answer") {
      if (result.kind === "short") {
        children.push(
          element("plantoirQuizResponse", "div", { className: ["plantoir-quiz-response"] }, [
            element("plantoirQuizBlank", "input", {
              type: "text",
              className: ["plantoir-quiz-blank"],
              ariaLabel: words.answerLabel ?? "",
              autoComplete: "off",
              autoCapitalize: "off",
              autoCorrect: "off",
              spellCheck: "false",
            }),
          ]),
        )
      }
      children.push(answerDisplay(result.answers, words, parse))
      continue
    }
    if (kind === "explain") {
      children.push(element("plantoirQuizExplain", "div", { className: ["plantoir-quiz-explain"], hidden: true }, [child]))
      continue
    }
    children.push(child)
  }
  content.children = children
}

// A GeoGebra sketch anywhere inside a node (#578 stage 5): the fence as the
// sketches' transformer leaves it - a "plantoirGeoGebra" node, built with
// data.hName, never raw html, which is what lets this see it - or still a
// ```geogebra code block when the build could not show it (the folder check
// refuses a sketch in a choice either way, so the site does too).
const SKETCH_NODE = "plantoirGeoGebra"
const SKETCH_LANGUAGE = "geogebra"

function holdsSketch(node: AnyNode): boolean {
  if (node.type === SKETCH_NODE || (node.type === "code" && node.lang === SKETCH_LANGUAGE)) {
    return true
  }
  for (const child of node.children ?? []) {
    if (holdsSketch(child)) {
      return true
    }
  }
  return false
}

function modelOf(quiz: AnyNode, source: string[]): QuizModel {
  const title = quiz.children?.[0]
  const titleHtml = title && title.type === "html" ? String((title as unknown as Html).value) : ""
  const content = contentOf(quiz)
  let boxedLists = 0
  let choices: Array<boolean | null> = []
  const answers: string[][] = []
  let blanks = blanksInTitle(titleHtml)
  let htmlChoices = false
  let sketchInAChoice = false
  for (const child of content?.children ?? []) {
    const kind = calloutKind(child)
    if (child.type === "list") {
      if (boxed(child)) {
        boxedLists += 1
        if (boxedLists === 1) {
          choices = []
          for (const item of child.children ?? []) {
            choices.push(item.checked === true ? true : item.checked === false ? false : null)
            if (holdsSketch(item)) {
              sketchInAChoice = true
            }
          }
        }
      }
    } else if (kind === "answer") {
      answers.push(answerLines(child, source))
    } else if (child.type === "paragraph") {
      blanks += blanksIn(child)
    } else if (child.type === "html") {
      for (const line of String((child as unknown as Html).value).split("\n")) {
        if (TASK_ITEM_TEXT.test(line)) {
          htmlChoices = true
        }
      }
    }
  }
  return {
    options: optionsOf(quiz.data?.hProperties?.["data-callout-metadata"]),
    boxedLists,
    choices,
    answers,
    blanks,
    htmlChoices,
    sketchInAChoice,
  }
}

// Prints the line and records it (#644) - both or neither, so the folder
// problem has exactly one piece per line (a site without its words prints
// nothing and records nothing).
function sayDisagreement(
  file: { data: any },
  page: string,
  where: string,
  said: Record<string, string>,
  recorded: Omit<QuizDisagreement, "page">,
) {
  const reason = said.readDifferently
  if (reason) {
    console.log(`plantoir: error: ${page}: ${where}: ${reason}`)
    const all = (file.data.plantoirQuizDisagreements ?? []) as QuizDisagreement[]
    all.push({ page, ...recorded })
    file.data.plantoirQuizDisagreements = all
  }
}

function firstNumber(values: Array<number | null> | undefined): number | null {
  const found = values?.find((value) => typeof value === "number")
  return typeof found === "number" ? found : null
}

export const PlantoirQuizzes: QuartzTransformerPlugin = () => ({
  name: "PlantoirQuizzes",
  textTransform(_ctx, src) {
    return nestedTitlesOwnTheirLine(src.toString())
  },
  markdownPlugins() {
    return [
      function (this: any) {
        const processor = this
        const parse: Parse | null =
          processor && typeof processor.parse === "function" ? (text: string) => processor.parse(text) : null
        return (tree: MdRoot, file) => {
          const value = String(file.value ?? "")
          if (!/\[!quiz/i.test(value)) {
            return
          }
          const known = readJson<QuizWords>(WORDS_FILE)
          const words = known?.words ?? {}
          const ready = known !== null && Object.keys(words).length > 0
          const source = value.split("\n")
          const slug = String(file.data.slug ?? "")
          const results: Array<{ n: number; problem: string | null; fill?: Record<string, string | number> }> = []
          let n = 0
          const roots = new Set<AnyNode>()
          for (const child of tree.children as unknown as AnyNode[]) {
            if (calloutKind(child) !== "quiz") {
              continue
            }
            n += 1
            roots.add(child)
            const raw =
              typeof child.position?.start?.offset === "number"
                ? value.slice(child.position.start.offset, child.position.end.offset)
                : ""
            const properties = (child.data ??= {}).hProperties ?? (child.data.hProperties = {})
            properties.dataQuizN = String(n)
            properties.dataQuizSource = slug
            properties.dataQuizHash = fnv1a(raw)
            const result = contentOf(child) === null ? verdict({ options: optionsOf(properties["data-callout-metadata"]), boxedLists: 0, choices: [], answers: [], blanks: 0 }) : verdict(modelOf(child, source))
            if ("problem" in result) {
              results.push({ n, problem: result.problem, fill: result.fill })
              renderNotReady(child, result.problem, words)
            } else if (!ready) {
              results.push({ n, problem: null })
              renderNotReady(child, "wordsMissing", words)
            } else {
              results.push({ n, problem: null })
              renderQuiz(child, result, words, parse)
            }
          }
          // Quizzes inside a list or another callout (ruling Q3).
          let nested = 0
          visit(tree as any, "blockquote", (node: any) => {
            if (roots.has(node) || calloutKind(node) !== "quiz") {
              return
            }
            if (node.data?.hProperties?.dataQuizKind !== undefined) {
              return
            }
            nested += 1
            const properties = node.data.hProperties
            properties.dataQuizNested = String(nested)
            renderNotReady(node, "notAtTopLevel", words)
          })

          // The safety net: only where the folder check looked.
          const checked = readJson<QuizPages>(PAGES_FILE)
          const page = String(file.data.relativePath ?? slug + ".md")
          const flag = (file.data.frontmatter as Record<string, unknown> | undefined)?.publish
          const published = !(flag === false || flag === "false")
          if (checked === null || !published || !checked.examined.includes(page)) {
            return
          }
          const said = known?.problems ?? {}
          const found = checked.pages[page] ?? { quizzes: 0, problems: [], nested: 0, nestedProblems: [] }
          // Named by the question's place and, where the folder check knows
          // it, its line in the teacher's file - never by a count.
          const named = (place: number) => {
            const line = found.lines?.[place - 1]
            return typeof line === "number" ? `quiz ${place}, line ${line}` : `quiz ${place}`
          }
          if (found.quizzes === n && found.nested !== nested) {
            // Only the quizzes inside a list or callout differ: name the
            // first of those the folder check found, by its own line.
            const line = firstNumber(found.nestedLines)
            sayDisagreement(
              file,
              page,
              line !== null ? `a quiz inside a list or another callout at line ${line}` : "a quiz inside a list or another callout",
              said,
              { n: null, line, reason: "nestedReadDifferently" },
            )
            return
          }
          if (found.quizzes !== n) {
            // No place can be trusted when the counts differ: name the first
            // quiz either side found.
            const line = firstNumber(found.lines)
            sayDisagreement(file, page, line !== null ? `the quiz at line ${line}` : "quiz 1", said, {
              n: null,
              line,
              reason: "countedDifferently",
            })
            return
          }
          for (const result of results) {
            const reported = found.problems.includes(result.n)
            if (reported !== (result.problem !== null)) {
              const line = found.lines?.[result.n - 1]
              // The SITE's problem, never assumed: the folder check found
              // nothing, so only the site knows why it shows the note.
              const recorded: Omit<QuizDisagreement, "page"> =
                result.problem !== null
                  ? { n: result.n, line: typeof line === "number" ? line : null, reason: "shownWithNote", problem: result.problem, fill: result.fill ?? {} }
                  : { n: result.n, line: typeof line === "number" ? line : null, reason: "shownWorking" }
              sayDisagreement(file, page, named(result.n), said, recorded)
            }
          }
          if (found.nestedProblems.length !== nested) {
            // The printed line keeps no line; the record names the first
            // quiz inside a list or callout the folder check found.
            sayDisagreement(file, page, "a quiz inside a list or another callout", said, {
              n: null,
              line: firstNumber(found.nestedLines),
              reason: "nestedReadDifferently",
            })
          }
        }
      },
    ]
  },
  htmlPlugins() {
    return [
      () => (tree: HtmlRoot, file) => {
        const quizzes: Element[] = []
        visit(tree, "element", (node: Element) => {
          const className = node.properties?.className
          const classes = Array.isArray(className) ? className.map(String) : String(className ?? "").split(" ")
          if (classes.includes("plantoir-quiz")) {
            quizzes.push(node)
          }
        })
        if (quizzes.length === 0) {
          return
        }
        const known = readJson<QuizWords>(WORDS_FILE)
        const words = known?.words ?? {}
        const slugPart = String(file.data.slug ?? "page").replace(/[^A-Za-z0-9_-]+/g, "-")
        for (const quiz of quizzes) {
          labelQuiz(quiz, slugPart, words)
        }
        redactSearchText(tree, file)
      },
    ]
  },
})

// ---- The html stage -----------------------------------------------------------

function classesOf(node: Element): string[] {
  const className = node.properties?.className
  if (Array.isArray(className)) {
    return className.map(String)
  }
  return String(className ?? "").split(/\s+/).filter((name) => name !== "")
}

function hasClass(node: ElementContent | HtmlRoot, name: string): boolean {
  return node.type === "element" && classesOf(node).includes(name)
}

function childElements(node: Element): Element[] {
  const found: Element[] = []
  for (const child of node.children) {
    if (child.type === "element") {
      found.push(child)
    }
  }
  return found
}

function findFirst(node: Element, test: (candidate: Element) => boolean): Element | null {
  for (const child of childElements(node)) {
    if (test(child)) {
      return child
    }
    const deeper = findFirst(child, test)
    if (deeper !== null) {
      return deeper
    }
  }
  return null
}

function blankInput(n: number, count: number, words: Record<string, string>): Element {
  return {
    type: "element",
    tagName: "input",
    properties: {
      type: "text",
      className: ["plantoir-quiz-blank"],
      dataBlank: String(n - 1),
      ariaLabel: filledWords(words.blankLabel ?? "Blank {n} of {count}", { n, count }),
      autoComplete: "off",
      autoCapitalize: "off",
      autoCorrect: "off",
      spellCheck: "false",
    },
    children: [],
  }
}

// The question's own id, the choices' label, and blanks made into boxes.
function labelQuiz(quiz: Element, slugPart: string, words: Record<string, string>) {
  const n = String(quiz.properties?.dataQuizN ?? `x${quiz.properties?.dataQuizNested ?? "0"}`)
  const stemId = `plq-${slugPart}-${n}-stem`
  const title = findFirst(quiz, (candidate) => hasClass(candidate, "callout-title-inner"))
  if (title !== null) {
    title.properties = { ...title.properties, id: stemId }
  }
  const kind = String(quiz.properties?.dataQuizKind ?? "")
  const content = childElements(quiz).find((child) => hasClass(child, "callout-content")) ?? null
  if (content === null) {
    return
  }
  for (const child of childElements(content)) {
    if (hasClass(child, "plantoir-quiz-choices")) {
      child.properties = { ...child.properties, ariaLabelledby: stemId }
      const hint = childElements(child).find((candidate) => hasClass(candidate, "plantoir-quiz-hint"))
      if (hint !== undefined) {
        const hintId = `plq-${slugPart}-${n}-hint`
        hint.properties = { ...hint.properties, id: hintId }
        child.properties = { ...child.properties, ariaDescribedby: hintId }
      }
      // What follows a choice's words (a graph, an image, code) describes
      // its box, so "Graph A" is read with the graph's description (review
      // S7); a choice with no words of its own is named by its number and
      // that description.
      let index = 0
      for (const choice of childElements(child)) {
        if (!hasClass(choice, "plantoir-quiz-choice")) {
          continue
        }
        index += 1
        const text = findFirst(choice, (candidate) => hasClass(candidate, "plantoir-quiz-choice-text"))
        const more = childElements(choice).find((candidate) => hasClass(candidate, "plantoir-quiz-choice-more"))
        if (more !== undefined) {
          const moreId = `${stemId}-choice-${index}`
          more.properties = { ...more.properties, id: moreId }
          const box = findFirst(choice, (candidate) => candidate.tagName === "input")
          if (box !== null) {
            box.properties = { ...box.properties, ariaDescribedby: moreId }
          }
        }
        if (text !== null && text.properties?.dataChoiceFallback !== undefined && more !== undefined) {
          const caption = findFirst(more, (candidate) => candidate.tagName === "figcaption")
          const image = findFirst(more, (candidate) => candidate.tagName === "img" && typeof candidate.properties?.alt === "string")
          const said = caption !== null ? toString(caption).trim() : image !== null ? String(image.properties.alt).trim() : ""
          const input = findFirst(choice, (candidate) => candidate.tagName === "input")
          if (input !== null && said !== "") {
            input.properties = {
              ...input.properties,
              ariaLabel: `${filledWords(words.choiceNumber ?? "Choice {n}", { n: index })}: ${said}`,
            }
          }
        }
      }
    }
  }
  if (kind !== "fill") {
    return
  }
  // Blanks: in the title, then in the question's own paragraphs.
  const places: Element[] = []
  if (title !== null) {
    places.push(title)
  }
  for (const child of childElements(content)) {
    if (child.tagName === "p") {
      places.push(child)
    }
  }
  const codes: Array<{ parent: Element; index: number }> = []
  const collect = (node: Element) => {
    node.children.forEach((child, index) => {
      if (child.type !== "element") {
        return
      }
      if (child.tagName === "code" && isBlank(toString(child))) {
        codes.push({ parent: node, index })
      } else {
        collect(child)
      }
    })
  }
  for (const place of places) {
    collect(place)
  }
  codes.forEach((code, at) => {
    code.parent.children[code.index] = blankInput(at + 1, codes.length, words)
  })
}

// Description (description.ts), repeated: its link rule and its summary.
const urlRegex = new RegExp(
  /(https?:\/\/)?(?<domain>([\da-z\.-]+)\.([a-z\.]{2,6})(:\d+)?)(?<path>[\/\w\.-]*)(\?[\/\w\.=&;-]*)?/,
  "g",
)
const DESCRIPTION_LENGTH = 150
const MAX_DESCRIPTION_LENGTH = 300

function withoutAnswers(node: any): any {
  if (node === null || typeof node !== "object") {
    return node
  }
  if (node.type === "element" && node.tagName === "input" && node.properties?.dataBlank !== undefined) {
    // A blank reads as "…" ("Fill … and …."), not as nothing.
    return { type: "text", value: "…" }
  }
  if (node.type === "element") {
    const classes = classesOf(node)
    if (classes.includes("plantoir-quiz-answer") || classes.includes("plantoir-quiz-explain")) {
      return null
    }
    if (node.tagName === "figure" && classes.includes("pl-geogebra")) {
      // A GeoGebra sketch reads as its description alone (#578 stage 5), as
      // Description - which runs before the sketch's card is put in - read
      // it on every page without a quiz: never the button, the commands or
      // the attribution. Measured: without this, a quiz page's search text
      // carried "Open the sketch (about 2.9 MB)" and "Made with GeoGebra®".
      const captions: any[] = []
      for (const child of node.children ?? []) {
        if (child?.type === "element" && child.tagName === "figcaption") {
          captions.push(child)
        }
      }
      return { ...node, children: captions }
    }
  }
  if (Array.isArray(node.children)) {
    const children: any[] = []
    for (const child of node.children) {
      const kept = withoutAnswers(child)
      if (kept !== null) {
        children.push(kept)
      }
    }
    return { ...node, children }
  }
  return node
}

// The page's search text (contentIndex.json) and, when the page names no
// description of its own, its summary (the meta description, og:description,
// the RSS item) made again from the page without its quizzes' answers and
// explanations (ruling Q5, review S3). Only on a page with a quiz; a
// top-level [!answer] callout outside a quiz stays searchable as before.
function redactSearchText(tree: HtmlRoot, file: any) {
  let text = escapeHTML(toString(withoutAnswers(tree)))
  text = text.replace(urlRegex, "$<domain>" + "$<path>")
  file.data.text = text
  if (file.data.frontmatter?.description) {
    return
  }
  const sentences = text.replace(/\s+/g, " ").split(/\.\s/)
  let finalDesc = ""
  let sentenceIdx = 0
  while (sentenceIdx < sentences.length) {
    const sentence = sentences[sentenceIdx]
    if (!sentence) break
    const currentSentence = sentence.endsWith(".") ? sentence : sentence + "."
    const nextLength = finalDesc.length + currentSentence.length + (finalDesc ? 1 : 0)
    if (nextLength <= DESCRIPTION_LENGTH || sentenceIdx === 0) {
      finalDesc += (finalDesc ? " " : "") + currentSentence
      sentenceIdx++
    } else {
      break
    }
  }
  file.data.description =
    finalDesc.length > MAX_DESCRIPTION_LENGTH ? finalDesc.slice(0, MAX_DESCRIPTION_LENGTH) + "..." : finalDesc
}
