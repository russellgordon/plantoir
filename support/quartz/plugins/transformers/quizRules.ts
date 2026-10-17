// Self-check quizzes (#563): the ONE implementation of the rules a quiz is
// read and checked by - contracts/shared-rules.json -> quizCallouts.
//
// Pure: no DOM, no imports, no Node. The site's transformer
// (plantoirQuizzes.ts) uses it to decide what each quiz is when the site is
// built, and the page's own script (components/scripts/quiz.inline.ts) uses
// it to check a student's answer in the browser, so the two can never
// disagree. scripts/check_quiz_rules_against_the_site.py bundles this very
// file and runs every case in the contract through it. The Python half
// (scripts/quizzes.py) mirrors parseAnswerLine and verdict for the folder
// check; it never checks an answer, so accepts and normalise live here only.

export type Alternative =
  | { kind: "number"; value: number; text: string }
  | { kind: "tolerance"; value: number; tolerance: number; text: string }
  | { kind: "math"; text: string }
  | { kind: "text"; text: string }

export type LineProblem = "emptyAlternative" | "badTolerance"

export type ParsedLine = { alternatives: Alternative[] } | { problem: LineProblem }

// What a quiz holds, as plain data (quizCallouts.recognise): its settings
// (the words after `|` in `[!quiz|...]`), how many lists hold a boxed item,
// the boxed list's items (true for [x], false for [ ], null for an item with
// no box), each [!answer]'s lines (markers off, trimmed, blank lines left
// out), and how many blanks the question has.
export type QuizModel = {
  options: string[]
  boxedLists: number
  choices: Array<boolean | null>
  answers: string[][]
  blanks: number
}

export type QuizKind = "single" | "multiple" | "short" | "fill"

export type Verdict =
  | { kind: QuizKind; shuffle: boolean; correct: number[]; answers: string[] }
  | { problem: string; fill: Record<string, string | number>; answerLine: number | null }

// The only quiz setting there is.
export const OPTIONS = ["shuffle"]

// JavaScript's own trim, named so the Python mirror (figures.js_trim) is
// visibly the same rule.
export function jsTrim(text: string): string {
  return text.trim()
}

// ---- Numbers (quizCallouts.answers.numbers) ----------------------------------
// A decimal with an optional sign (+, - or the minus sign U+2212), with or
// without a leading digit; or a fraction of two whole numbers with a
// denominator that is not 0, spaces allowed around the slash. ASCII digits
// only. NOT numbers: 1e3, 0x10, Infinity, "", 1,5, 1 000, 1 1/2, ½.
const DECIMAL = /^([+\-−]?)([0-9]+(?:\.[0-9]*)?|\.[0-9]+)$/
const FRACTION = /^([+\-−]?)([0-9]+)[ \t]*\/[ \t]*([0-9]+)$/

export function parseNumber(text: string): number | null {
  const trimmed = jsTrim(text)
  const decimal = DECIMAL.exec(trimmed)
  if (decimal !== null) {
    const magnitude = parseFloat(decimal[2].startsWith(".") ? "0" + decimal[2] : decimal[2])
    return decimal[1] === "-" || decimal[1] === "−" ? -magnitude : magnitude
  }
  const fraction = FRACTION.exec(trimmed)
  if (fraction !== null) {
    const denominator = parseInt(fraction[3], 10)
    if (denominator === 0) {
      return null
    }
    const magnitude = parseInt(fraction[2], 10) / denominator
    return fraction[1] === "-" || fraction[1] === "−" ? -magnitude : magnitude
  }
  return null
}

function close(a: number, b: number): boolean {
  return Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a), Math.abs(b))
}

// ---- One answer line (quizCallouts.answers.parse) ----------------------------
// The alternatives are separated by a `|` with a space or tab (or the line's
// edge) on both sides. `\|` is a `|` that separates nothing; every other
// backslash stays as typed. Each alternative is trimmed.
export function splitAlternatives(line: string): string[] {
  const text = jsTrim(line)
  const pieces: string[] = []
  let current = ""
  let index = 0
  while (index < text.length) {
    const character = text[index]
    if (character === "\\" && text[index + 1] === "|") {
      current += "|"
      index += 2
      continue
    }
    if (character === "|") {
      const before = index === 0 ? " " : text[index - 1]
      const after = index + 1 >= text.length ? " " : text[index + 1]
      if ((before === " " || before === "\t") && (after === " " || after === "\t")) {
        pieces.push(current)
        current = ""
        index += 1
        continue
      }
    }
    current += character
    index += 1
  }
  pieces.push(current)
  const trimmed: string[] = []
  for (const piece of pieces) {
    trimmed.push(jsTrim(piece))
  }
  return trimmed
}

const MATH = /^\$([^$]+)\$$/

function classify(text: string): Alternative | LineProblem {
  const math = MATH.exec(text)
  if (math !== null) {
    return { kind: "math", text: jsTrim(math[1]) }
  }
  // A tolerance is a number, then ± (or +-), then a number that is not
  // negative. Text whose part before the ± is not a number (±3, x = ±3) is
  // an ordinary answer; a number then ± then anything but such a number is
  // a mistake to report.
  const plusMinus = text.indexOf("±")
  const ascii = text.indexOf("+-")
  let at = -1
  let width = 0
  if (plusMinus >= 0 && (ascii < 0 || plusMinus < ascii)) {
    at = plusMinus
    width = 1
  } else if (ascii >= 0) {
    at = ascii
    width = 2
  }
  if (at >= 0) {
    const value = parseNumber(text.slice(0, at))
    if (value !== null) {
      const tolerance = parseNumber(text.slice(at + width))
      if (tolerance === null || tolerance < 0) {
        return "badTolerance"
      }
      return { kind: "tolerance", value, tolerance, text }
    }
  }
  const value = parseNumber(text)
  if (value !== null) {
    return { kind: "number", value, text }
  }
  return { kind: "text", text }
}

export function parseAnswerLine(line: string): ParsedLine {
  const alternatives: Alternative[] = []
  for (const piece of splitAlternatives(line)) {
    if (piece === "") {
      return { problem: "emptyAlternative" }
    }
    const read = classify(piece)
    if (typeof read === "string") {
      return { problem: read }
    }
    alternatives.push(read)
  }
  return { alternatives }
}

// ---- Checking a student's answer (quizCallouts.answers.check) ----------------
// NFKC, then toLowerCase() with no locale, JavaScript's trim, runs of
// whitespace to one space, curly quotes to straight ones (iPad and iPhone
// keyboards type them), and +- to ±.
export function normalise(text: string): string {
  return jsTrim(text.normalize("NFKC").toLowerCase())
    .replace(/\s+/g, " ")
    .replace(/[’‘ʼ]/g, "'")
    .replace(/[“”„]/g, '"')
    .replace(/\+-/g, "±")
}

// Does `input` match one of the line's alternatives? An empty answer is never
// checked (the page says typeFirst), so it is never accepted.
export function accepts(alternatives: Alternative[], input: string): boolean {
  const typed = normalise(input)
  if (typed === "") {
    return false
  }
  const math = MATH.exec(typed)
  const bare = math !== null ? jsTrim(math[1]) : typed
  const typedNumber = parseNumber(bare)
  for (const alternative of alternatives) {
    if (alternative.kind === "number") {
      if (typedNumber !== null && close(typedNumber, alternative.value)) {
        return true
      }
    } else if (alternative.kind === "tolerance") {
      if (typedNumber !== null) {
        const slack = 1e-9 * Math.max(1, Math.abs(alternative.value))
        if (
          typedNumber >= alternative.value - alternative.tolerance - slack &&
          typedNumber <= alternative.value + alternative.tolerance + slack
        ) {
          return true
        }
      }
    } else if (bare === normalise(alternative.text)) {
      return true
    }
  }
  return false
}

// ---- Shuffling (quizCallouts.shuffle) ----------------------------------------
// Fisher-Yates from the last place down, `random` answering in [0, 1).
export function shuffledOrder(n: number, random: () => number): number[] {
  const order: number[] = []
  for (let index = 0; index < n; index += 1) {
    order.push(index)
  }
  for (let index = n - 1; index > 0; index -= 1) {
    const other = Math.floor(random() * (index + 1))
    const kept = order[index]
    order[index] = order[other]
    order[other] = kept
  }
  return order
}

// ---- What a quiz is (quizCallouts.recognise) ---------------------------------
// The first problem found, in this order, or the kind. `answerLine` is the
// 0-based index, among the [!answer]'s lines, of the line a problem is about.
export function verdict(model: QuizModel): Verdict {
  const problem = (name: string, fill: Record<string, string | number> = {}, answerLine: number | null = null) => ({
    problem: name,
    fill,
    answerLine,
  })
  for (const option of model.options) {
    if (!OPTIONS.includes(option.toLowerCase())) {
      return problem("unknownOption", { option })
    }
  }
  const shuffle = model.options.some((option) => option.toLowerCase() === "shuffle")
  if (model.boxedLists > 1) {
    return problem("twoChoiceLists")
  }
  if (model.choices.includes(null)) {
    return problem("choiceWithoutBox")
  }
  if (model.answers.length > 1) {
    return problem("twoAnswers")
  }
  const hasChoices = model.choices.length > 0
  const hasAnswer = model.answers.length === 1
  if (hasChoices && hasAnswer) {
    return problem("choicesAndAnswer")
  }
  if (hasChoices) {
    if (model.choices.length === 1) {
      return problem("oneChoice")
    }
    const correct: number[] = []
    model.choices.forEach((checked, index) => {
      if (checked === true) {
        correct.push(index)
      }
    })
    if (correct.length === 0) {
      return problem("noCorrectChoice")
    }
    return { kind: correct.length === 1 ? "single" : "multiple", shuffle, correct, answers: [] }
  }
  if (hasAnswer) {
    const lines = model.answers[0]
    if (lines.length === 0) {
      return problem("noAnswerLine")
    }
    for (let index = 0; index < lines.length; index += 1) {
      const parsed = parseAnswerLine(lines[index])
      if ("problem" in parsed) {
        return problem(parsed.problem, { n: index + 1 }, index)
      }
    }
    if (model.blanks === 0) {
      if (lines.length > 1) {
        return problem("oneAnswerLine", { lines: lines.length })
      }
      return { kind: "short", shuffle, correct: [], answers: lines.slice() }
    }
    if (model.blanks !== lines.length) {
      return problem("blanksAndLines", { blanks: model.blanks, lines: lines.length })
    }
    return { kind: "fill", shuffle, correct: [], answers: lines.slice() }
  }
  return problem("nothingToCheck")
}

// A blank in a question: a code span holding only three or more underscores.
// `value` is the span as the site's parser reads it, which has already taken
// one space off each end of a span that has both (CommonMark); the Python
// mirror takes that space off the raw span itself.
export function isBlank(value: string): boolean {
  return /^_{3,}$/.test(value)
}

// The words a teacher reads, with {name} filled in one pass.
export function filledWords(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{([A-Za-z]+)\}/g, (whole: string, key: string) =>
    key in values ? String(values[key]) : whole,
  )
}

// ---- The text hook (plantoirQuizzes.ts): nested titles inside a quiz (M2) ----
// Quartz's ObsidianFlavoredMarkdown gives a callout's title line a paragraph
// of its own only at the page's left edge, so a nested `> > [!answer]-`
// followed by `> > $2^7$` put the answer INTO the title (#563 plan M2).
// Inside a quiz only (ruling Q1), after any nested callout's first line,
// this adds one line holding just its `>` markers. Line endings are made LF
// first (review S1), fenced code is skipped (S2), and a page with no quiz
// outside fenced code comes back exactly as it came. Here rather than in
// the transformer so the check script can run it in Node with nothing else.

const MARKERS = /^(?:[ \t]*>)+[ \t]?/
const FENCE_OPEN = /^[ \t]*(?:(?:[-*+]|[0-9]{1,9}[.)])[ \t]+)*(`{3,}|~{3,})(.*)$/
const BLOCK_START =
  /^[ \t]{0,3}(?:[-*+](?:[ \t]|$)|[0-9]{1,9}[.)](?:[ \t]|$)|#{1,6}(?:[ \t]|$)|`{3,}|~{3,}|<|(?:-[ \t]*){3,}$|(?:\*[ \t]*){3,}$|(?:_[ \t]*){3,}$)/
// A quiz callout's first line, behind any list markers and at least one `>`.
const QUIZ_START = /^((?:[ \t]*(?:[-*+]|[0-9]{1,9}[.)])[ \t]+)*(?:[ \t]*>[ \t]*)+)\[!quiz(?:\||\])/i
// Any callout's first line, behind its `>` markers.
const CALLOUT_LINE = /^((?:[ \t]*>[ \t]*)+)\[![\w-]+(?:\|.*?)?\][+-]?.*$/

function depthAndBody(line: string): [number, string] {
  const markers = MARKERS.exec(line)
  if (markers === null) {
    return [0, line]
  }
  return [(markers[0].match(/>/g) ?? []).length, line.slice(markers[0].length)]
}

function fenceOpens(body: string): [string, number] | null {
  const match = FENCE_OPEN.exec(body)
  if (match === null) {
    return null
  }
  if (match[1][0] === "`" && match[2].includes("`")) {
    return null
  }
  return [match[1][0], match[1].length]
}

function fenceCloses(body: string, fence: [string, number]): boolean {
  const stripped = body.replace(/^[ \t]+|[ \t]+$/g, "")
  let run = 0
  while (run < stripped.length && stripped[run] === fence[0]) {
    run += 1
  }
  return run >= fence[1] && stripped.slice(run).trim() === ""
}

function isBlankLine(text: string): boolean {
  return /^[ \t]*$/.test(text)
}

export function nestedTitlesOwnTheirLine(source: string): string {
  if (!/\[!quiz/i.test(source)) {
    return source
  }
  const lines = source.replace(/\r\n?/g, "\n").split("\n")
  const out: string[] = []
  let found = false
  let fence: { mark: [string, number]; depth: number } | null = null
  let quizDepth = 0
  let paragraph = false
  for (const line of lines) {
    out.push(line)
    const [depth, body] = depthAndBody(line)
    if (fence !== null) {
      if (depth < fence.depth) {
        fence = null
      } else {
        if (fenceCloses(body, fence.mark)) {
          fence = null
        }
        continue
      }
    }
    if (isBlankLine(line)) {
      quizDepth = 0
      paragraph = false
      continue
    }
    if (quizDepth > 0 && depth === 0 && (!paragraph || BLOCK_START.test(line))) {
      quizDepth = 0
    }
    const opened = fenceOpens(body)
    if (opened !== null) {
      fence = { mark: opened, depth }
      paragraph = false
      continue
    }
    if (quizDepth > 0 && depth > quizDepth) {
      const nested = CALLOUT_LINE.exec(line)
      if (nested !== null && depthAndBody(nested[1])[0] > quizDepth) {
        out.push(nested[1].replace(/[ \t]+$/, ""))
        paragraph = false
        continue
      }
    } else {
      const start = QUIZ_START.exec(line)
      if (start !== null) {
        found = true
        quizDepth = depth
        // ObsidianFlavoredMarkdown already did this for a quiz at the left
        // edge (`^> *\[`); one indented, or inside a quote, gets it here.
        // One behind a list marker is left as it is.
        if (!/^> *\[/.test(line) && !/[-*+0-9]/.test(start[1].replace(/[ \t>]/g, ""))) {
          out.push(start[1].replace(/[ \t]+$/, ""))
        }
        paragraph = false
        continue
      }
    }
    paragraph = !isBlankLine(body) && (!BLOCK_START.test(body) || /^[ \t]*(?:[-*+]|[0-9]{1,9}[.)])[ \t]/.test(body))
  }
  return found ? out.join("\n") : source
}
