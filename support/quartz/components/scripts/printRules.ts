// Printable pages (#454, #499): the rules, with nothing else in them.
//
// No imports and no DOM, so the same file runs in the browser (print.inline.ts
// imports it), in the build (PlantoirMetaLine.tsx imports it for ⌘P's corner)
// and in Node, where scripts/check_print_rules_against_the_site.py bundles it
// and runs every case in contracts/shared-rules.json -> printablePages
// (answerCallouts, labels, titleCleaning, pageLabels, curriculumConnection,
// questionItems, paper, footer, paperLook, completeness) through it. A rule
// changed here without the contract, or there without here, fails verify.sh.

export type Role = "answer" | "question" | "unfold" | "none"
export type Part = "questions" | "answers"

// The other spellings Quartz accepts for each callout kind, which it turns
// into the kind itself (quartz/plugins/transformers/ofm.ts). A callout typed
// `[!check]-` arrives as kind "success" titled "Check", so "Check" is that
// kind's default title, not one the teacher chose.
export const KIND_ALIASES: Record<string, string[]> = {
  abstract: ["summary", "tldr"],
  tip: ["hint", "important"],
  success: ["check", "done"],
  question: ["help", "faq"],
  warning: ["attention", "caution"],
  failure: ["missing", "fail"],
  danger: ["error"],
  quote: ["cite"],
}

function normalised(text: string): string {
  return text.toLowerCase().replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
}

// "Solution (click to expand)" -> "Solution". Only a bracketed phrase at the
// END that begins with click or tap: it is an instruction to a reader on
// screen (decision 5). "(see p. 2)" is the teacher's own words.
export function cleanTitle(title: string): string {
  let cleaned = title.trim()
  const instruction = /\s*\(\s*(?:click|tap)\b[^()]*\)\s*$/i
  while (instruction.test(cleaned)) {
    cleaned = cleaned.replace(instruction, "").trim()
  }
  return cleaned
}

function startsWithAnswerWord(title: string, answerTitleWords: string[]): boolean {
  const text = normalised(cleanTitle(title))
  for (const word of answerTitleWords) {
    const pattern = new RegExp("^" + word + "s?(?![\\p{L}\\p{N}])", "u")
    if (pattern.test(text)) {
      return true
    }
  }
  return false
}

// What a callout does on paper. Decided from what was true when the page
// LOADED: a reader who opened an answer on screen must not print it.
export function role(
  kind: string,
  folded: boolean,
  title: string,
  answerKinds: string[],
  answerTitleWords: string[],
): Role {
  if (!folded) {
    return "none"
  }
  if (answerKinds.includes(kind) || startsWithAnswerWord(title, answerTitleWords)) {
    return "answer"
  }
  if (kind === "question") {
    return "question"
  }
  return "unfold"
}

// A title that says nothing about which answer this is.
export function isGenericTitle(title: string, kind: string, answerTitleWords: string[]): boolean {
  const text = normalised(cleanTitle(title))
  if (text === "" || text === normalised(kind)) {
    return true
  }
  const aliases = KIND_ALIASES[kind] ?? []
  if (aliases.includes(text)) {
    return true
  }
  for (const word of answerTitleWords) {
    if (text === word || text === word + "s") {
      return true
    }
  }
  return false
}

function fill(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{([A-Za-z]+)\}/g, (whole: string, key: string) =>
    key in values ? String(values[key]) : whole,
  )
}

function escaped(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// The number in a question label - questionLabel with any number, in any
// capitals ("### Question 3" -> 3) - or null when the text is not one.
export function questionNumber(text: string, template: string): number | null {
  const pieces: string[] = template.split("{n}")
  if (pieces.length !== 2) {
    return null
  }
  const pattern = new RegExp("^" + escaped(pieces[0]) + "(\\d+)" + escaped(pieces[1]) + "$", "i")
  const found = pattern.exec(text.trim())
  return found ? parseInt(found[1], 10) : null
}

// A question's number on paper (#499), for each question on the page in page
// order: a question label keeps its own number; anything else - a self-check
// titled in the teacher's own words - takes the number after the one before
// it, so the worksheet reads 1., 2., 3. as the LaTeX handouts do.
export function numberQuestions(titles: string[], template: string): number[] {
  const numbers: number[] = []
  let last = 0
  for (const title of titles) {
    const own = questionNumber(title, template)
    const number = own !== null ? own : last + 1
    numbers.push(number)
    last = number
  }
  return numbers
}

// A part's letter: 1 -> a, 26 -> z, 27 -> aa.
export function partLetter(n: number): string {
  let letters = ""
  let rest = n
  while (rest > 0) {
    const index = (rest - 1) % 26
    letters = String.fromCharCode(97 + index) + letters
    rest = Math.floor((rest - 1) / 26)
  }
  return letters
}

// What an answer is called in the answers, and where it belongs: the label
// printed, the question's number (null when it has none) and the part's
// letter (null when it is not a part). Answers of one question's parts are
// gathered under that question's number in the answers (review N1).
export type AnswerPlace = { label: string; question: number | null; part: string | null }

export function answerPlace(
  title: string,
  kind: string,
  listItem: number | null,
  heading: string | null,
  answerNumber: number,
  words: Record<string, string>,
  answerTitleWords: string[],
): AnswerPlace {
  const trimmed = heading !== null && heading !== undefined ? heading.trim() : ""
  const headingNumber = trimmed !== "" ? questionNumber(trimmed, words.questionLabel) : null
  if (!isGenericTitle(title, kind, answerTitleWords)) {
    return { label: cleanTitle(title), question: null, part: null }
  }
  if (listItem !== null && listItem !== undefined) {
    // Under a heading that is itself a question ("### Question 3" over a
    // list), the items are its PARTS: "3. a)". It read "Question 3, part 1"
    // until #499 and "Question 3 · Question 1" before the #454 fix review.
    if (headingNumber !== null) {
      const part = partLetter(listItem)
      return { label: fill(words.partLabel, { n: headingNumber, part }), question: headingNumber, part }
    }
    const item: string = fill(words.numberLabel, { n: listItem })
    // Under another heading the item's number alone repeats across lists
    // (the verify fixture's practice list beside "Question 1", #454 review N2).
    if (trimmed !== "") {
      return { label: trimmed + " · " + item, question: null, part: null }
    }
    return { label: item, question: listItem, part: null }
  }
  if (headingNumber !== null) {
    return { label: fill(words.numberLabel, { n: headingNumber }), question: headingNumber, part: null }
  }
  if (trimmed !== "") {
    return { label: trimmed, question: null, part: null }
  }
  return { label: fill(words.answerLabel, { n: answerNumber }), question: null, part: null }
}

// The label alone (contract: labels).
export function label(
  title: string,
  kind: string,
  listItem: number | null,
  heading: string | null,
  answerNumber: number,
  words: Record<string, string>,
  answerTitleWords: string[],
): string {
  return answerPlace(title, kind, listItem, heading, answerNumber, words, answerTitleWords).label
}

// How many columns a question's lettered parts print in (#499, the LaTeX
// `tasks` look): three when every part is short, two when every part fits
// half a line, otherwise one - and one whenever a part holds more than a
// line of text (a picture, code, a second paragraph, a list). `lengths` are
// the parts' text lengths in characters.
export const PART_COLUMN_LIMITS = { three: 24, two: 48 }

export function partColumns(lengths: number[], anyBlock: boolean): number {
  if (anyBlock || lengths.length < 2) {
    return 1
  }
  let longest = 0
  for (const length of lengths) {
    longest = Math.max(longest, length)
  }
  if (longest <= PART_COLUMN_LIMITS.three) {
    return Math.min(3, lengths.length)
  }
  if (longest <= PART_COLUMN_LIMITS.two) {
    return 2
  }
  return 1
}

// A page's Curriculum connection (#498) is never printed: it says which
// expectations the page addresses, which is for the teacher and the coverage
// map, not for a student's worksheet. Is this heading one? Its words in any
// capitals, singular or plural, with a closing colon or full stop allowed:
// "Curriculum Connections:" is one, "Making a curriculum connection" is not.
export function isCurriculumHeading(heading: string, curriculumHeadings: string[]): boolean {
  const text = normalised(heading).replace(/[:.]+$/, "").trim()
  for (const words of curriculumHeadings) {
    const wanted = normalised(words)
    if (text === wanted || text === wanted + "s") {
      return true
    }
  }
  return false
}

// One element of a run of siblings: a heading (its text and level, 1 to 6),
// the page's footnotes (heading null, level 1: Quartz puts them after the
// LAST section, so they follow a Curriculum connection at the end of a page
// and must still print), or anything else (heading null, level 0).
export type Block = { heading: string | null; level: number }

// Which of a run of siblings are left off paper: a Curriculum connection
// heading, and everything after it up to the next heading of the same or a
// higher level - the section as the page's table of contents draws it. A
// deeper heading inside it goes with it.
export function leftOffPaper(blocks: Block[], curriculumHeadings: string[]): boolean[] {
  const result: boolean[] = []
  // The level of the Curriculum connection heading being left off, or 0.
  let openLevel = 0
  for (const block of blocks) {
    if (block.level > 0) {
      if (openLevel > 0 && block.level <= openLevel) {
        openLevel = 0
      }
      if (openLevel === 0 && block.heading !== null && isCurriculumHeading(block.heading, curriculumHeadings)) {
        openLevel = block.level
      }
    }
    result.push(openLevel > 0)
  }
  return result
}

// "Page 1 of 3" over the questions, "Answers 1 of 2" over the answers.
export function pageLabel(part: Part, n: number, total: number, words: Record<string, string>): string {
  const template = part === "answers" ? words.answersPageLabel : words.pageLabel
  return fill(template, { n, total })
}


// The paper a handout is laid out on (#499): US letter, portrait or
// landscape, chosen in the Print menu. The print layout lays the pages out
// BEFORE the browser's own print dialog opens and cannot learn what is chosen
// there, so the menu is where the orientation is decided; the size it writes
// makes Chrome's and Edge's dialogs follow it. ⌘P writes no size at all, so
// the browser's own dialog decides (commandP).
export type Paper = "portrait" | "landscape"

export const MARGINS_IN = { top: 0.75, side: 0.75, bottom: 0.9 }

export function paperBox(paper: string): { size: string; widthIn: number; heightIn: number; contentWidthIn: number; contentHeightIn: number } {
  const landscape = paper === "landscape"
  const widthIn = landscape ? 11 : 8.5
  const heightIn = landscape ? 8.5 : 11
  return {
    size: landscape ? "letter landscape" : "letter",
    widthIn,
    heightIn,
    contentWidthIn: Math.round((widthIn - 2 * MARGINS_IN.side) * 100) / 100,
    contentHeightIn: Math.round((heightIn - MARGINS_IN.top - MARGINS_IN.bottom) * 100) / 100,
  }
}

// The bottom-left corner of a printed page (#499, the LaTeX footer): the
// page's title - with answersTitle's words on the answer pages - then what the
// course's settings place there (the course code, by default), joined by
// " · ". An empty title leaves the settings' text alone.
export function footerLeft(title: string, settingsText: string, part: Part, words: Record<string, string>): string {
  const named = title.trim()
  const pieces: string[] = []
  if (named !== "") {
    pieces.push(part === "answers" ? fill(words.answersTitle, { title: named }) : named)
  }
  if (settingsText.trim() !== "") {
    pieces.push(settingsText.trim())
  }
  return pieces.join(" · ")
}

// Which callouts keep a box on paper (#499): only a worked example, as the
// LaTeX handouts' peach box. Every other callout prints as plain text under a
// bold title - a handout has no coloured boxes behind text (decision 26).
export function boxedOnPaper(kind: string): boolean {
  return kind.trim().toLowerCase() === "example"
}

// A displayed formula wider than the page (#499 review S1): set smaller when
// it would still be at least MIN_FORMULA_SCALE of its size, as LaTeX's
// \resizebox; otherwise broken between its terms. `room` and `wide` are in
// the same unit. Contract: paperLook.formulas.
export const MIN_FORMULA_SCALE = 0.7

export function fitFormula(room: number, wide: number): { scale: number | null; wraps: boolean } {
  if (room <= 0 || wide <= room + 1) {
    return { scale: null, wraps: false }
  }
  const scale = Math.floor((room / wide) * 1000) / 1000
  if (scale >= MIN_FORMULA_SCALE) {
    return { scale, wraps: false }
  }
  return { scale: null, wraps: true }
}

// A table this wide prints in 9 pt type, so a timetable fits without
// breaking its words (#499 review S3). Contract: paperLook.tables.
export const WIDE_TABLE_COLUMNS = 8

export function isWideTable(columns: number): boolean {
  return columns >= WIDE_TABLE_COLUMNS
}

// Fenced code on paper (DECISIONS 30, paperLook.code): a monospaced face,
// its line numbers, and a hairline box with no fill - the second box a
// handout keeps, beside a worked example's. One rule for the handout and ⌘P.
export const CODE_BOX = { border: "0.5pt solid #999999", paddingPt: 4 }

export function codeBoxRules(scope: string): string {
  return (
    `${scope} pre.plantoir-code { border: ${CODE_BOX.border} !important; border-radius: 0 !important; ` +
    `padding: ${CODE_BOX.paddingPt}pt !important; background: none !important; box-shadow: none !important; ` +
    `box-decoration-break: clone; -webkit-box-decoration-break: clone; }`
  )
}

// Whether a laid-out handout may be printed (#499, review B2): every piece of
// the handout that was laid out must be on a page, and none may run off the
// edge of the page it is on by more than `tolerance` pixels. Otherwise
// nothing is printed and the reader is told (words.incomplete): a handout
// with a question, a line of code or an answer missing is worse than none.
export function mayPrint(expected: number, found: number, overflowing: number): boolean {
  return expected > 0 && found >= expected && overflowing === 0
}

// ---- The page box, as CSS text (#454, #499) ---------------------------------
// Shared by ⌘P (PlantoirMetaLine writes it into the page) and the handout
// (print.inline.ts hands it to the print layout), so the two cannot drift.

// A CSS string, quoted and escaped, for a margin box's `content`. Spaces
// become non-breaking: a corner is ONE line, and a narrow margin box would
// otherwise wrap "Page 1 of 3" onto three (measured in Safari, #454).
export function cssString(text: string): string {
  const escapedText = text.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ")
  return '"' + escapedText.replace(/ /g, "\\0000a0") + '"'
}

// The same, keeping ordinary spaces so the text can wrap.
export function cssPlainString(text: string): string {
  return '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ") + '"'
}

// "Page {n} of {total}" as a CSS content value counting the whole document:
// what the browser's own Print (⌘P) can do, where nothing paginates the
// questions and the answers separately.
export function countedLabel(template: string): string {
  const pieces: string[] = []
  const pattern = /\{(n|total)\}/g
  let last = 0
  let match: RegExpExecArray | null = pattern.exec(template)
  while (match !== null) {
    if (match.index > last) {
      pieces.push(cssString(template.slice(last, match.index)))
    }
    pieces.push(match[1] === "n" ? "counter(page)" : "counter(pages)")
    last = match.index + match[0].length
    match = pattern.exec(template)
  }
  if (last < template.length) {
    pieces.push(cssString(template.slice(last)))
  }
  return pieces.join(" ")
}

// The faces a handout is set in (paperLook), carried in the site beside the
// print layout (static/pagedjs/fonts) and loaded only when a page is printed.
// `base` is where the site's root is, as a URL or a path ending in "/".
export const FONT_FACES: Array<{ family: string; file: string; weight: string; style: string }> = [
  { family: "Plantoir LM Roman", file: "lmroman10-regular.otf", weight: "normal", style: "normal" },
  { family: "Plantoir LM Roman", file: "lmroman10-bold.otf", weight: "bold", style: "normal" },
  { family: "Plantoir LM Roman", file: "lmroman10-italic.otf", weight: "normal", style: "italic" },
  { family: "Plantoir LM Roman", file: "lmroman10-bolditalic.otf", weight: "bold", style: "italic" },
  { family: "Plantoir LM Sans", file: "lmsans10-bold.otf", weight: "bold", style: "normal" },
  { family: "Plantoir LM Mono", file: "lmmono10-regular.otf", weight: "normal", style: "normal" },
]

export function fontFaceRules(base: string): string {
  const rules: string[] = []
  for (const face of FONT_FACES) {
    rules.push(
      `@font-face { font-family: "${face.family}"; src: url("${base}static/pagedjs/fonts/${face.file}") format("opentype"); ` +
        `font-weight: ${face.weight}; font-style: ${face.style}; font-display: block; }`,
    )
  }
  return rules.join("\n")
}

// The page box and its four corners. `size` is null for ⌘P (the browser's own
// dialog decides, paper) and the paper's size for the handout; each corner is
// a CSS `content` value (a quoted string, a counter, or a var()).
const CORNER_TEXT =
  'font-family: "Plantoir LM Roman", "Latin Modern Roman", "CMU Serif", Georgia, serif; font-size: 10pt; color: #666; white-space: nowrap; vertical-align: middle;'
// The top left corner may take two lines: a long school name sharing it with
// the course code, beside three blanks, printed ON TOP of the blanks when
// every corner was one line (#454 implementation review S3, measured).
const CORNER_WRAPPING =
  'font-family: "Plantoir LM Roman", "Latin Modern Roman", "CMU Serif", Georgia, serif; font-size: 10pt; color: #666; white-space: normal; vertical-align: middle;'

export function pageBoxRules(
  size: string | null,
  corners: { topLeft: string; topRight: string; bottomLeft: string; bottomRight: string },
): string {
  const sized = size !== null ? `size: ${size}; ` : ""
  const margin = `margin: ${MARGINS_IN.top}in ${MARGINS_IN.side}in ${MARGINS_IN.bottom}in; `
  return (
    "@page { " +
    sized +
    margin +
    `@top-left { content: ${corners.topLeft}; ${CORNER_WRAPPING} } ` +
    `@top-right { content: ${corners.topRight}; ${CORNER_TEXT} } ` +
    `@bottom-left { content: ${corners.bottomLeft}; ${CORNER_TEXT} } ` +
    `@bottom-right { content: ${corners.bottomRight}; ${CORNER_TEXT} } }`
  )
}
