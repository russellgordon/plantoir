// Printable pages (#454, #499): the Print menu, and ⌘P on a printable page.
//
// Bundled into every site's postscript.js, so it must be INERT on a page that
// has not opted in: on each page load it takes the "printable" mark off the
// page first and puts it back only when this page carries the button (review
// B2 - Quartz's single-page navigation keeps <html> between pages, so a mark
// left behind would make the next, ordinary page print as a worksheet).
//
// Pressing Print opens a menu and prints nothing until a way of printing is
// chosen (#499, decision 29). The handout is made IN THE PAGE: the article is
// cloned, its answers lifted to an answer key, its questions numbered as the
// LaTeX handouts number them, its folded hints opened, and the result
// paginated by Paged.js inside an iframe that sits ON SCREEN but invisible
// (measured: off screen, Safari paginated one page every ~8 s; on screen, 11
// pages in 192 ms), checked for anything left out (completeness), then
// printed from there. The plan and every measurement are in
// documentation/06-quartz-customizations.md, section F.

import {
  answerPlace,
  boxedOnPaper,
  codeBoxRules,
  cleanTitle,
  cssPlainString,
  cssString,
  fitFormula,
  fontFaceRules,
  footerLeft,
  isCurriculumHeading,
  isWideTable,
  leftOffPaper,
  mayPrint,
  numberQuestions,
  pageBoxRules,
  pageLabel,
  paperBox,
  partColumns,
  partLetter,
  questionNumber,
  role,
} from "./printRules"
import type { Block, Paper } from "./printRules"

type Mode = "questionsOnly" | "answersOnly" | "withAnswersAtTheEnd"
type Corners = { topLeft: string; topRight: string; bottomLeft: string; bottomRight: string }
type Settings = {
  corners: Corners
  words: Record<string, string>
  answerKinds: string[]
  answerTitleWords: string[]
  curriculumHeadings: string[]
  page?: { title?: string; subtitle?: string }
}
type PrintHooks = { prepare: Array<() => Promise<void>> }
// An answer on its way to the answer key: its label, the question and part it
// belongs to (printRules.answerPlace), and what the teacher wrote in it.
type Entry = { label: string; question: number | null; part: string | null; body: Node[] }

const PRINTABLE = "plantoir-printable"
// On every element of the page's Curriculum connection (#498): never printed.
const CURRICULUM = "data-plantoir-curriculum"
const FROM_DARK = "plantoir-printing-from-dark"
// The contract's order (printablePages.modes.list): the menu's order too.
const MODES: Mode[] = ["questionsOnly", "answersOnly", "withAnswersAtTheEnd"]
const PAPERS: Paper[] = ["portrait", "landscape"]
// The paper last chosen, remembered by this browser (a convenience only:
// nothing breaks when storage is refused).
const PAPER_KEY = "plantoir-print-paper"
// A code block longer than this many lines may break across pages; a shorter
// one moves whole to the next page. About two thirds of a letter page.
const SPLITTABLE_LINES = 25
// How far, in CSS pixels, a laid-out element may sit past its page's edge
// before the handout counts as cut off (rounding, not content).
const OVERFLOW_TOLERANCE = 1.5
// How far, in CSS pixels, a line may hang below the page and lose only the
// space under its letters (its leading), not a letter.
const LEADING_TOLERANCE = 3
// How much wider a formula's character is than a letter of text, near enough.
const MATH_WIDTH = 1.5
// Room kept under a picture that fills a page, for its caption.
const CAPTION_ROOM_IN = 0.45
// What the completeness check counts (printablePages.completeness): every
// element that carries words or a picture. Not anything inside a drawing
// (a diagram's own labels are the drawing's), not an icon inside a link, not
// KaTeX's own strokes.
const COUNTED = [
  "p:not(svg *)",
  "li:not(svg *)",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "tr",
  "dt",
  "dd",
  "figcaption",
  "pre > code > [data-line]",
  "img",
  "svg:not(svg svg):not(.katex svg):not(a svg):not(.plantoir-print-glyph)",
  ".katex-display",
  ".plantoir-number",
  ".plantoir-part-mark",
].join(", ")
// The colours a Mermaid diagram is drawn from (mermaid.inline.ts's cssVars).
const DIAGRAM_COLOURS = [
  "--secondary",
  "--tertiary",
  "--gray",
  "--light",
  "--lightgray",
  "--highlight",
  "--dark",
  "--darkgray",
]

// Engines that draw only in the browser (#485 E1's functionplot, #455's code
// runner) add a function here that finishes drawing everything on the page;
// each is awaited before the handout is made.
const hooks = window as unknown as { plantoirPrint?: PrintHooks }
if (!hooks.plantoirPrint) {
  hooks.plantoirPrint = { prepare: [] }
}

let busy = false

function readSettings(box: HTMLElement): Settings | null {
  try {
    return JSON.parse(box.dataset.settings ?? "") as Settings
  } catch {
    return null
  }
}

function fill(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{([A-Za-z]+)\}/g, (whole: string, key: string) =>
    key in values ? String(values[key]) : whole,
  )
}

function rememberedPaper(): Paper {
  try {
    const kept = localStorage.getItem(PAPER_KEY)
    if (kept === "landscape") {
      return "landscape"
    }
  } catch {}
  return "portrait"
}

function rememberPaper(paper: Paper) {
  try {
    localStorage.setItem(PAPER_KEY, paper)
  } catch {}
}

function titleOf(callout: Element): string {
  const inner = callout.querySelector(":scope > .callout-title .callout-title-inner")
  return inner ? (inner.textContent ?? "").trim() : ""
}

function setTitle(callout: Element, text: string) {
  const inner = callout.querySelector(":scope > .callout-title .callout-title-inner")
  if (inner) {
    inner.textContent = text
  }
}

// Read when the page LOADS (plan finding C): a student who opened an answer
// on screen toggles the very class this reads.
function stampRoles(settings: Settings) {
  const callouts = document.querySelectorAll(".center article blockquote.callout")
  for (const callout of callouts) {
    const element = callout as HTMLElement
    element.dataset.plantoirRole = role(
      element.getAttribute("data-callout") ?? "",
      element.classList.contains("is-collapsed"),
      titleOf(element),
      settings.answerKinds,
      settings.answerTitleWords,
    )
  }
}

// The page's Curriculum connection, marked when the page loads so that ⌘P's
// stylesheet and the handout both leave it off paper (#498). The rule - which
// heading, and how far its section runs - is printRules.leftOffPaper's, run on
// the siblings of each heading that names it.
function stampCurriculum(settings: Settings) {
  const words = settings.curriculumHeadings ?? []
  const parents: Set<Element> = new Set()
  for (const heading of document.querySelectorAll(
    ".center article h1, .center article h2, .center article h3, .center article h4, .center article h5, .center article h6",
  )) {
    if (heading.parentElement && isCurriculumHeading(heading.textContent ?? "", words)) {
      parents.add(heading.parentElement)
    }
  }
  for (const parent of parents) {
    const children = Array.from(parent.children)
    const blocks: Block[] = []
    for (const child of children) {
      if (child.matches("section[data-footnotes]")) {
        blocks.push({ heading: null, level: 1 })
        continue
      }
      const level = /^H[1-6]$/.test(child.tagName) ? parseInt(child.tagName.slice(1), 10) : 0
      blocks.push({ heading: level > 0 ? (child.textContent ?? "") : null, level })
    }
    const leftOff = leftOffPaper(blocks, words)
    children.forEach((child, index) => {
      if (leftOff[index]) {
        child.setAttribute(CURRICULUM, "")
      }
    })
  }
}

// Every diagram drawn again: Quartz's Mermaid code empties each diagram the
// moment the theme changes and puts a new drawing in when it is done, so the
// drawings are back when every diagram holds one again. Watched rather than
// announced, so nothing in the site's own Mermaid script changes - it is
// inlined into every page, printable or not. Gives up after `milliseconds`.
function diagramsRedrawn(diagrams: Element[], milliseconds: number): Promise<void> {
  return new Promise((resolve) => {
    let finished = false
    // The finished drawing is the diagram's own child; while Mermaid is still
    // drawing, an svg sits inside a temporary box instead (measured: printing
    // on the first svg found printed a blank space where the diagram goes).
    const allDrawn = () =>
      diagrams.every((diagram) => diagram.querySelector(":scope > svg") !== null)
    const finish = () => {
      if (finished) {
        return
      }
      finished = true
      observer.disconnect()
      clearTimeout(timer)
      // One more frame, for the pie charts' re-fit that follows the drawing.
      requestAnimationFrame(() => resolve())
    }
    const observer = new MutationObserver(() => {
      if (allDrawn()) {
        finish()
      }
    })
    for (const diagram of diagrams) {
      observer.observe(diagram, { childList: true, subtree: true })
    }
    const timer = setTimeout(finish, milliseconds)
    if (allDrawn()) {
      finish()
    }
  })
}

function listItemNumber(element: Element, article: Element): number | null {
  const item = element.closest("li")
  if (!item || !article.contains(item)) {
    return null
  }
  const list = item.parentElement
  if (!list || list.tagName !== "OL") {
    return null
  }
  const start = parseInt(list.getAttribute("start") ?? "1", 10)
  let index = 0
  for (const sibling of list.children) {
    if (sibling === item) {
      break
    }
    if (sibling.tagName === "LI") {
      index += 1
    }
  }
  return (isNaN(start) ? 1 : start) + index
}

function nearestHeading(element: Element, article: Element): string | null {
  let found: string | null = null
  for (const heading of article.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
    const position = heading.compareDocumentPosition(element)
    if (position & Node.DOCUMENT_POSITION_FOLLOWING) {
      found = (heading.textContent ?? "").trim()
    }
  }
  return found
}

function unfold(callout: HTMLElement) {
  callout.classList.remove("is-collapsed")
  callout.style.maxHeight = ""
}

function headingLevel(element: Element): number {
  return /^H[1-6]$/.test(element.tagName) ? parseInt(element.tagName.slice(1), 10) : 0
}

// What a callout holds, taken out of it: the answer key and the questions
// print the teacher's words, not the callout around them (paperLook).
function contentsOf(callout: Element): Node[] {
  const body = callout.querySelector(":scope > .callout-content")
  return body ? Array.from(body.childNodes) : []
}

// The words a reader sees, for deciding how many columns parts take
// (questionItems.columns): KaTeX's hidden copy of each formula (its MathML)
// is left out, or every formula would count twice, and a formula's
// characters count one and a half - set with the spacing around its signs,
// "5(2x + 3y) - 4(3x - 5y)" is as wide as 26 letters of text, and counted
// plainly it was squeezed into three columns and wrapped (measured against
// Get Ready for Linear Systems, question 4).
function visibleLength(element: Element): number {
  const copy = element.cloneNode(true) as Element
  for (const hidden of copy.querySelectorAll(".katex-mathml, annotation")) {
    hidden.remove()
  }
  let formulas = 0
  for (const formula of copy.querySelectorAll(".katex")) {
    formulas += (formula.textContent ?? "").replace(/\s+/g, "").length
  }
  const all = (copy.textContent ?? "").replace(/\s+/g, " ").trim().length
  return Math.round(all + formulas * (MATH_WIDTH - 1))
}

// More than a line of text: a picture, code, a table, a list, a displayed
// formula, a quotation or a second paragraph.
function holdsABlock(element: Element): boolean {
  if (
    element.querySelector(
      "pre, table, img, figure, ul, ol, blockquote, .katex-display, hr, svg:not(.katex svg)",
    ) !== null
  ) {
    return true
  }
  return element.querySelectorAll(":scope > p").length > 1
}

function numberSpan(text: string): HTMLElement {
  const span = document.createElement("span")
  span.className = "plantoir-number"
  span.textContent = text
  return span
}

// Lettered parts side by side (questionItems.columns): each part a mark and
// what the teacher wrote, in one, two or three columns.
function partsGrid(parts: Array<{ letter: string; body: Node[]; source: Element }>, words: Record<string, string>): HTMLElement {
  const lengths: number[] = []
  let anyBlock = false
  for (const part of parts) {
    lengths.push(visibleLength(part.source))
    anyBlock = anyBlock || holdsABlock(part.source)
  }
  const columns = partColumns(lengths, anyBlock)
  const grid = document.createElement("div")
  grid.className = "plantoir-parts plantoir-columns-" + columns
  grid.style.setProperty("--plantoir-columns", String(columns))
  for (const part of parts) {
    const cell = document.createElement("div")
    cell.className = "plantoir-part"
    const mark = document.createElement("span")
    mark.className = "plantoir-part-mark"
    mark.textContent = fill(words.partMark, { part: part.letter })
    const body = document.createElement("div")
    body.className = "plantoir-part-body"
    for (const node of part.body) {
      body.appendChild(node)
    }
    cell.appendChild(mark)
    cell.appendChild(body)
    grid.appendChild(cell)
  }
  return grid
}

// A numbered item, as the LaTeX handouts' `\q{3}`: the number in the left
// margin, in the first line of what follows it, so the two never part.
function questionItem(number: string, stem: Node[], extraClass: string): HTMLElement {
  const item = document.createElement("div")
  item.className = "plantoir-question " + extraClass
  const body = document.createElement("div")
  body.className = "plantoir-stem"
  for (const node of stem) {
    body.appendChild(node)
  }
  item.appendChild(body)
  const first = body.firstElementChild
  if (first && /^(P|H[1-6])$/.test(first.tagName)) {
    first.insertBefore(numberSpan(number), first.firstChild)
  } else if (first && first.classList.contains("plantoir-parts") && first.firstElementChild) {
    first.firstElementChild.insertBefore(numberSpan(number), first.firstElementChild.firstChild)
  } else {
    const line = document.createElement("p")
    line.className = "plantoir-number-line"
    line.appendChild(numberSpan(number))
    body.insertBefore(line, body.firstChild)
  }
  return item
}

// An ordered list directly inside a question is its lettered parts.
function letterTheParts(stem: Element, words: Record<string, string>) {
  for (const list of Array.from(stem.querySelectorAll(":scope > ol"))) {
    const start = parseInt(list.getAttribute("start") ?? "1", 10)
    const parts: Array<{ letter: string; body: Node[]; source: Element }> = []
    let index = 0
    for (const item of Array.from(list.children)) {
      if (item.tagName !== "LI") {
        continue
      }
      parts.push({
        letter: partLetter((isNaN(start) ? 1 : start) + index),
        body: Array.from(item.childNodes),
        source: item,
      })
      index += 1
    }
    if (parts.length > 0) {
      // The words before the parts stay on their page with them, as the
      // LaTeX handouts' `\q[n]` keeps a stem with its parts.
      list.previousElementSibling?.classList.add("plantoir-keep-with-next")
      list.replaceWith(partsGrid(parts, words))
    }
  }
}

function paragraphOf(text: string): HTMLElement {
  const paragraph = document.createElement("p")
  paragraph.textContent = text
  return paragraph
}

// The handout, built from a copy of the article. Nothing on the page itself
// is changed.
function buildHandout(mode: Mode, settings: Settings): HTMLElement {
  const words = settings.words
  const page = document.createElement("div")
  page.className = "page"
  const center = document.createElement("div")
  center.className = "center"
  page.appendChild(center)

  const title = document.querySelector(".center h1.article-title")
  const pageTitle = (settings.page?.title ?? "").trim() || (title?.textContent ?? "").trim()
  const original = document.querySelector(".center article")
  const article = (original ? original.cloneNode(true) : document.createElement("article")) as HTMLElement

  for (const control of article.querySelectorAll(
    ".clipboard-button, .expand-button, #mermaid-container, .mermaid-controls",
  )) {
    control.remove()
  }
  // Before anything is lifted or labelled: nothing in it is printed, in any
  // mode, and no heading of it names an answer (#498).
  for (const element of article.querySelectorAll(`[${CURRICULUM}]`)) {
    element.remove()
  }

  // The questions, in page order (questionItems): headings that are question
  // labels, and question callouts that are not inside an answer or a list.
  const questions: Element[] = []
  const questionTitles: string[] = []
  for (const element of article.querySelectorAll(
    "h1, h2, h3, h4, h5, h6, blockquote.callout[data-callout='question']",
  )) {
    if (headingLevel(element) > 0) {
      if (questionNumber(element.textContent ?? "", words.questionLabel) !== null) {
        questions.push(element)
        questionTitles.push((element.textContent ?? "").trim())
      }
      continue
    }
    const kind = (element as HTMLElement).dataset.plantoirRole
    if (
      (kind === "question" || kind === "none") &&
      !element.parentElement?.closest("blockquote.callout") &&
      !element.closest("li")
    ) {
      questions.push(element)
      questionTitles.push(cleanTitle(titleOf(element)))
    }
  }
  const numbers = numberQuestions(questionTitles, words.questionLabel)
  const numberOf: Map<Element, number> = new Map()
  questions.forEach((element, index) => numberOf.set(element, numbers[index]))

  // The answers, lifted out with where they belong (labels).
  const entries: Entry[] = []
  let answerNumber = 0
  for (const node of Array.from(article.querySelectorAll("blockquote.callout"))) {
    const callout = node as HTMLElement
    unfold(callout)
    const titleText = titleOf(callout)
    if (!article.contains(callout)) {
      // Inside an answer already lifted: it travels with that answer.
      setTitle(callout, cleanTitle(titleText))
      continue
    }
    const calloutRole = callout.dataset.plantoirRole
    if (calloutRole === "answer") {
      answerNumber += 1
      const place = answerPlace(
        titleText,
        callout.getAttribute("data-callout") ?? "",
        listItemNumber(callout, article),
        nearestHeading(callout, article),
        answerNumber,
        words,
        settings.answerTitleWords,
      )
      callout.remove()
      entries.push({ ...place, body: contentsOf(callout) })
    } else if (calloutRole === "question") {
      const cleaned = cleanTitle(titleText)
      const number = numberOf.get(callout)
      const body = contentsOf(callout)
      if (number !== undefined) {
        entries.push({ label: fill(words.numberLabel, { n: number }), question: number, part: null, body })
        const stem: Node[] = []
        if (questionNumber(cleaned, words.questionLabel) === null) {
          stem.push(paragraphOf(cleaned))
        }
        callout.replaceWith(questionItem(fill(words.numberLabel, { n: number }), stem, ""))
      } else {
        // In a list or inside another callout: its title stays, as a title.
        entries.push({ label: cleaned, question: null, part: null, body })
        for (const child of Array.from(callout.querySelectorAll(":scope > .callout-content"))) {
          child.remove()
        }
        setTitle(callout, cleaned)
      }
    } else {
      setTitle(callout, cleanTitle(titleText))
      const number = numberOf.get(callout)
      if (number !== undefined) {
        // An unfolded question: its title, then its body, is the question
        // (the director's ruling 499-6).
        const cleaned = cleanTitle(titleText)
        const stem: Node[] = []
        if (questionNumber(cleaned, words.questionLabel) === null) {
          stem.push(paragraphOf(cleaned))
        }
        for (const child of contentsOf(callout)) {
          stem.push(child)
        }
        callout.replaceWith(questionItem(fill(words.numberLabel, { n: number }), stem, ""))
      } else if (boxedOnPaper(callout.getAttribute("data-callout") ?? "")) {
        callout.classList.add("plantoir-boxed")
      }
    }
  }

  // Question headings become numbered items: the heading's number, and what
  // follows it up to the next heading of the same or a higher level.
  for (const heading of questions) {
    const level = headingLevel(heading)
    if (level === 0 || !heading.parentElement) {
      continue
    }
    const stem: Node[] = []
    let next = heading.nextSibling
    while (next) {
      if (next.nodeType === Node.ELEMENT_NODE) {
        const element = next as Element
        const nextLevel = headingLevel(element)
        if (
          (nextLevel > 0 && nextLevel <= level) ||
          element.classList.contains("plantoir-question") ||
          element.matches("section[data-footnotes]")
        ) {
          break
        }
      }
      const following = next.nextSibling
      stem.push(next)
      next = following
    }
    const number = fill(words.numberLabel, { n: numberOf.get(heading) ?? 0 })
    heading.replaceWith(questionItem(number, stem, ""))
  }
  for (const stem of article.querySelectorAll(".plantoir-question > .plantoir-stem")) {
    letterTheParts(stem, words)
  }

  if (mode !== "answersOnly") {
    if (title) {
      center.appendChild(title.cloneNode(true))
    }
    const subtitle = (settings.page?.subtitle ?? "").trim()
    if (subtitle !== "") {
      const line = paragraphOf(subtitle)
      line.className = "plantoir-subtitle"
      center.appendChild(line)
    }
    center.appendChild(article)
  }

  if (mode !== "questionsOnly" && entries.length > 0) {
    const answers = document.createElement("div")
    answers.className = "plantoir-answers"
    if (mode === "answersOnly") {
      answers.classList.add("plantoir-answers-only")
    }
    const heading = document.createElement("h1")
    heading.className = "plantoir-answers-title"
    heading.textContent = pageTitle !== "" ? fill(words.answersTitle, { title: pageTitle }) : words.answersHeading
    answers.appendChild(heading)
    let index = 0
    while (index < entries.length) {
      const entry = entries[index]
      if (entry.question !== null && entry.part !== null) {
        // One question's parts, gathered under its number (review N1).
        const parts: Array<{ letter: string; body: Node[]; source: Element }> = []
        while (
          index < entries.length &&
          entries[index].question === entry.question &&
          entries[index].part !== null
        ) {
          const source = document.createElement("div")
          for (const node of entries[index].body) {
            source.appendChild(node.cloneNode(true))
          }
          parts.push({ letter: entries[index].part as string, body: entries[index].body, source })
          index += 1
        }
        answers.appendChild(
          questionItem(fill(words.numberLabel, { n: entry.question }), [partsGrid(parts, words)], "plantoir-answer"),
        )
        continue
      }
      if (entry.question !== null) {
        answers.appendChild(
          questionItem(fill(words.numberLabel, { n: entry.question }), entry.body, "plantoir-answer"),
        )
      } else {
        const titled = document.createElement("div")
        titled.className = "plantoir-answer plantoir-titled"
        const named = paragraphOf(entry.label)
        named.className = "plantoir-label"
        titled.appendChild(named)
        for (const node of entry.body) {
          titled.appendChild(node)
        }
        answers.appendChild(titled)
      }
      index += 1
    }
    center.appendChild(answers)
  }

  // Line numbers written out: the print layout does not carry the site's
  // line counter across, and every line printed as 1 (measured in Safari).
  // Each block also says how many digits its numbers take, so "100" is never
  // broken into "1 / 0 / 0" by the narrow box the site gives a number (#499,
  // fault 2: Russell's printed listing read 1, 6, 1, 7, ...).
  for (const code of center.querySelectorAll("pre > code")) {
    let number = 0
    for (const line of code.querySelectorAll(":scope > [data-line]")) {
      number += 1
      line.setAttribute("data-plantoir-line", String(number))
      // A blank line holds only a space, which the layout does not break
      // before, so Safari left one straddling the foot of a page with its
      // number cut off (measured, Safari 26.6). A zero-width space in its
      // place breaks like any other line.
      if ((line.textContent ?? "").trim() === "") {
        line.textContent = "\u200b"
      }
    }
    ;(code as HTMLElement).style.setProperty("--plantoir-digits", String(Math.max(2, String(number).length)))
  }
  for (const pre of center.querySelectorAll("pre")) {
    if (pre.querySelector(":scope > code.mermaid")) {
      // A diagram is one picture: scaled to the page, never let out of its
      // box - letting it flow stopped the whole layout (review B2).
      pre.classList.add("plantoir-diagram")
      continue
    }
    // Code flows onto the next page instead of scrolling: the print layout
    // will not split a box that scrolls, and printed a 125-line program on
    // two pages with 6,250 px of each cut off (#499, fault 6).
    pre.classList.add("plantoir-flowing", "plantoir-code")
    const lines = pre.querySelectorAll("[data-line]").length || (pre.textContent ?? "").split("\n").length
    if (lines > SPLITTABLE_LINES) {
      pre.classList.add("plantoir-splittable")
      // Quartz's figure around the code is kept whole too; let it split with
      // its code, or the heading above is stranded alone (review S2).
      const figure = pre.closest("figure")
      if (figure) {
        figure.classList.add("plantoir-splittable")
      }
    }
  }
  markWideTables(center)
  // An SVG with a size and no viewBox cannot be scaled to the page.
  for (const svg of center.querySelectorAll("svg")) {
    if (!svg.getAttribute("viewBox")) {
      const width = parseFloat(svg.getAttribute("width") ?? "")
      const height = parseFloat(svg.getAttribute("height") ?? "")
      if (width > 0 && height > 0) {
        svg.setAttribute("viewBox", `0 0 ${width} ${height}`)
      }
    }
  }
  return page
}

function markWideTables(within: Element) {
  for (const table of within.querySelectorAll("table")) {
    const row = table.querySelector("tr")
    if (row && isWideTable(row.children.length)) {
      table.classList.add("plantoir-wide-table")
    }
  }
}

// Every picture loaded, then given its own size: the print layout measures
// the page before a picture in its frame has loaded, and a picture with no
// size of its own is laid out 0 px tall (#499 fault 6, review B1). Taken from
// the picture's NATURAL size - never from the page on screen, where Quartz
// skips laying out anything off screen and every picture below the fold
// measured 0 × 0. A width the teacher gave (`|300`) is kept.
async function imagesReady(within: HTMLElement) {
  const waits: Promise<unknown>[] = []
  for (const image of within.querySelectorAll("img")) {
    image.loading = "eager"
    waits.push(image.decode().catch(() => undefined))
  }
  await Promise.all(waits)
  for (const image of within.querySelectorAll("img")) {
    const naturalWidth = image.naturalWidth
    const naturalHeight = image.naturalHeight
    if (naturalWidth <= 0 || naturalHeight <= 0) {
      continue
    }
    const given = parseFloat(image.getAttribute("width") ?? "")
    const width = given > 0 ? given : naturalWidth
    image.setAttribute("width", String(Math.round(width)))
    image.setAttribute("height", String(Math.round((width * naturalHeight) / naturalWidth)))
  }
}

function stylesheetsLoaded(doc: Document): Promise<void> {
  const waits: Promise<void>[] = []
  for (const link of doc.querySelectorAll('link[rel="stylesheet"]')) {
    const sheet = link as HTMLLinkElement
    if (sheet.sheet) {
      continue
    }
    waits.push(
      new Promise((resolve) => {
        sheet.addEventListener("load", () => resolve(), { once: true })
        sheet.addEventListener("error", () => resolve(), { once: true })
        setTimeout(resolve, 3000)
      }),
    )
  }
  return Promise.all(waits).then(() => undefined)
}

// The handout's faces, loaded before anything is measured (a line set in a
// fallback face and printed in Latin Modern would not fit where it was put).
// A face that cannot be had in 4 s is printed in the fallback.
async function fontsReady(doc: Document) {
  const loads: Promise<unknown>[] = []
  for (const face of [
    '10.95pt "Plantoir LM Roman"',
    'bold 10.95pt "Plantoir LM Roman"',
    'italic 10.95pt "Plantoir LM Roman"',
    'bold italic 10.95pt "Plantoir LM Roman"',
    'bold 12pt "Plantoir LM Sans"',
    '9pt "Plantoir LM Mono"',
  ]) {
    loads.push(doc.fonts.load(face).catch(() => undefined))
  }
  await Promise.race([Promise.all(loads), new Promise((resolve) => setTimeout(resolve, 4000))])
}

function loadScript(doc: Document, source: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const tag = doc.createElement("script")
    tag.src = source
    tag.onload = () => resolve()
    tag.onerror = () => reject(new Error("the print layout could not be loaded"))
    doc.head.appendChild(tag)
  })
}

function indexStylesheet(): string | null {
  for (const link of document.head.querySelectorAll('link[rel="stylesheet"]')) {
    const href = (link as HTMLLinkElement).href
    if (/\/index\.css(\?|$)/.test(href)) {
      return href
    }
  }
  return null
}

function makeFrame(paper: Paper): HTMLIFrameElement {
  const box = paperBox(paper)
  const frame = document.createElement("iframe")
  frame.setAttribute("aria-hidden", "true")
  frame.tabIndex = -1
  // ON screen, invisible: off screen, Safari paginates a page every ~8 s.
  frame.style.cssText =
    `position:fixed;left:0;top:0;width:${box.widthIn}in;height:${box.heightIn}in;` +
    "opacity:0;pointer-events:none;border:0;"
  document.body.appendChild(frame)
  const doc = frame.contentDocument!
  doc.open()
  doc.write("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>")
  doc.close()
  doc.documentElement.className = "plantoir-print-frame"
  doc.documentElement.setAttribute("saved-theme", "light")
  doc.documentElement.lang = document.documentElement.lang
  const base = doc.createElement("base")
  base.href = location.href
  doc.head.appendChild(base)
  return frame
}

// Every stylesheet the page uses, except the site's own (index.css), which
// the print layout reads and rewrites itself. Fonts and maths need theirs,
// or labels lay out in a fallback font. Marked so the layout leaves them be.
// The handout's own faces go in the same way, by full address.
function copyPageStylesheets(doc: Document, indexCss: string | null, root: string) {
  for (const element of document.head.querySelectorAll('link[rel="stylesheet"], style')) {
    if (element instanceof HTMLLinkElement && element.href === indexCss) {
      continue
    }
    const copy = doc.importNode(element, true) as HTMLElement
    copy.setAttribute("data-pagedjs-ignore", "")
    doc.head.appendChild(copy)
  }
  const faces = doc.createElement("style")
  faces.setAttribute("data-pagedjs-ignore", "")
  faces.textContent = fontFaceRules(new URL(root, location.href).href)
  doc.head.appendChild(faces)
}

// The two corners that change from page to page: the page label, and the
// footer's words, which name the answers on an answer page (footer).
function labelPages(doc: Document, mode: Mode, settings: Settings, pageTitle: string) {
  const words = settings.words
  const pages = Array.from(doc.querySelectorAll(".pagedjs_page")) as HTMLElement[]
  let firstAnswerPage = pages.length
  if (mode === "answersOnly") {
    firstAnswerPage = 0
  } else if (mode === "withAnswersAtTheEnd") {
    const index = pages.findIndex((page) => page.querySelector(".plantoir-answers") !== null)
    if (index >= 0) {
      firstAnswerPage = index
    }
  }
  const answerPages = pages.length - firstAnswerPage
  pages.forEach((page, index) => {
    const answers = index >= firstAnswerPage
    const text = answers
      ? pageLabel("answers", index - firstAnswerPage + 1, answerPages, words)
      : pageLabel("questions", index + 1, firstAnswerPage, words)
    const footer = footerLeft(pageTitle, settings.corners.bottomLeft, answers ? "answers" : "questions", words)
    // No-break spaces: a corner is one line (printRules.cssString).
    page.style.setProperty("--plantoir-page-label", JSON.stringify(text.replace(/ /g, " ")))
    page.style.setProperty("--plantoir-footer-left", JSON.stringify(footer.replace(/ /g, " ")))
  })
}

// A displayed formula wider than the page is set smaller until it fits, as
// LaTeX's \resizebox would - a formula of 59 terms printed to "+ a12" and
// stopped at the paper's edge (#499 review S1). One that would have to
// shrink below printRules.MIN_FORMULA_SCALE is broken between its terms instead, where
// KaTeX breaks a formula in a line of text, so it prints whole and
// readable. Measured in the frame at the paper's width before the layout,
// then the measuring copy is thrown away. A single term wider than the page
// (a huge matrix) still runs off, and the completeness check refuses it.
async function fitWideFormulas(doc: Document, handout: HTMLElement, paper: Paper, indexCss: string | null) {
  if (!handout.querySelector(".katex-display") || !indexCss) {
    return
  }
  const link = doc.createElement("link")
  link.rel = "stylesheet"
  link.href = indexCss
  doc.head.appendChild(link)
  await stylesheetsLoaded(doc)
  const measure = doc.createElement("div")
  measure.style.cssText = `position:absolute;left:0;top:0;width:${paperBox(paper).contentWidthIn}in;visibility:hidden;`
  measure.appendChild(doc.importNode(handout, true))
  doc.body.appendChild(measure)
  // KaTeX's own faces load only once a formula is laid out; measured in a
  // fallback face, a 13-term formula read 799 px for 896 and was not shrunk
  // enough (fix review S1).
  void measure.offsetWidth
  await doc.fonts.ready
  for (const display of measure.querySelectorAll(".katex-display")) {
    const formula = display.querySelector(":scope > .katex") as HTMLElement | null
    const stamp = display.getAttribute("data-plantoir-c")
    if (!formula || stamp === null) {
      continue
    }
    const room = display.getBoundingClientRect().width
    const wide = formula.scrollWidth
    {
      const fit = fitFormula(room, wide)
      const original = handout.querySelector(`.katex-display[data-plantoir-c="${stamp}"]`) as HTMLElement | null
      if (fit.scale !== null) {
        original?.style.setProperty("font-size", fit.scale + "em")
      } else if (fit.wraps) {
        original?.classList.add("plantoir-formula-wraps")
      }
    }
  }
  measure.remove()
  link.remove()
}

// What the print layout must see in the text it is handed, not only in the
// site's stylesheet: it decides where pages break by matching these against
// the handout BEFORE it is placed in the frame, where a rule scoped to the
// frame's <html> matches nothing (measured: the answers did not start on a
// fresh page until this was added). Classes the handout adds, not `:has()`,
// so the layout's own reading of the rules cannot drop them.
function layoutRules(paper: Paper): string {
  const box = paperBox(paper)
  const tallest = Math.max(1, box.contentHeightIn - CAPTION_ROOM_IN)
  return [
    ".plantoir-answers { break-before: page; }",
    ".plantoir-answers-only { break-before: auto; }",
    "h1, h2, h3, h4, h5, h6 { break-after: avoid; }",
    "blockquote.callout, figure:not(.plantoir-splittable), .katex-display, .pl-figure, pre:not(.plantoir-splittable), .plantoir-parts:not(.plantoir-columns-1), .plantoir-number-line { break-inside: avoid; }",
    ".plantoir-number-line, .plantoir-keep-with-next { break-after: avoid; }",
    "figure.plantoir-splittable { break-inside: auto; }",
    "pre.plantoir-flowing, pre.plantoir-flowing > code, .katex-display, .table-container { overflow: visible !important; }",
    "img { content-visibility: visible !important; }",
    // Every picture and drawing kept within one page, scaled down whole
    // (review B2: a 3,134 px diagram printed as three pages of arrows and
    // stopped the layout; a portrait screenshot ran 338 px off its page).
    `img, pre.plantoir-diagram svg, .pl-figure > svg, .pl-figure > img { max-width: 100% !important; max-height: ${tallest}in !important; object-fit: contain; }`,
    `pre.plantoir-diagram svg { width: auto !important; height: auto !important; }`,
    codeBoxRules(""),
  ].join("\n")
}

// The page box for the handout: the paper's size, the corners from the
// course's settings, and the two corners that change from page to page.
function pagedRules(paper: Paper, settings: Settings): string {
  return (
    pageBoxRules(paperBox(paper).size, {
      topLeft: cssPlainString(settings.corners.topLeft),
      topRight: cssString(settings.corners.topRight),
      bottomLeft: "var(--plantoir-footer-left)",
      bottomRight: "var(--plantoir-page-label)",
    }) +
    "\n" +
    layoutRules(paper)
  )
}

// Was everything laid out, and does all of it fit on its page
// (printablePages.completeness)? Counted against the stamps put on the
// handout before it was laid out.
// A piece with no words and no picture in it.
function emptyPiece(element: Element): boolean {
  const words = (element.textContent ?? "").replace(/[\s\u200b]/g, "")
  return words === "" && element.querySelector("img, svg") === null
}

function checkComplete(doc: Document, expected: number): { found: number; overflowing: string[] } {
  const found: Set<string> = new Set()
  const overflowing: string[] = []
  // An UNSPLIT element counts as cut off only when no unsplit copy of it
  // sits whole on a page: Safari leaves copies of table rows in the column
  // the layout throws away while the same rows print whole on the next page
  // (measured, Safari 26.6: the fixture's first two rows at x = 1,920 px
  // beside a 672 px page). Split pieces are judged on their own, above.
  const whole: Set<string> = new Set()
  const cutOff: Map<string, string> = new Map()
  for (const page of doc.querySelectorAll(".pagedjs_page")) {
    const area = page.querySelector(".pagedjs_page_content") ?? page.querySelector(".pagedjs_area")
    if (!area) {
      continue
    }
    const edge = area.getBoundingClientRect()
    for (const element of page.querySelectorAll("[data-plantoir-c]")) {
      const id = element.getAttribute("data-plantoir-c") ?? ""
      found.add(id)
      const view = doc.defaultView
      const shown = view ? view.getComputedStyle(element).display !== "none" : true
      const rect = element.getBoundingClientRect()
      if (!shown) {
        continue
      }
      // A piece of an element the layout split between pages. An EMPTY one
      // is no loss: Safari splits a line of code before its words, leaving an
      // empty 4 px piece whose box reaches into the column the layout throws
      // away while "import SwiftUI" prints on the next page (counted, it
      // refused MVVM Review on both papers; measured, Safari 26.6). Any other
      // piece is measured, and what it loses is lost - never excused by a
      // whole copy elsewhere, because its other pieces hold OTHER words.
      // Skipping every split piece printed a 60-line formula and a 90-line
      // table row half-missing while saying nothing was lost (fix review B1).
      const split = element.hasAttribute("data-split-to") || element.hasAttribute("data-split-from")
      if (split && emptyPiece(element)) {
        continue
      }
      if (element instanceof (view as unknown as typeof window).HTMLImageElement) {
        // A picture that loaded but was laid out with no height is missing
        // from the page as surely as one cut off (review B1).
        if (element.naturalWidth > 0 && rect.height < 1) {
          overflowing.push(id + " (a picture with no height)")
          continue
        }
      }
      if (rect.width <= 0 && rect.height <= 0) {
        if (!split) {
          whole.add(id)
        }
        continue
      }
      // A displayed formula's box is always the column's width; the formula
      // inside it is what runs off the page (review S1).
      // Its own box never grows, so it is the formula's scroll width that
      // says (measured: a 59-term formula's box 724 px, its width 4,342).
      const inner = element.classList.contains("katex-display") ? element.querySelector(":scope > .katex") : null
      if (inner && inner.scrollWidth > inner.clientWidth + OVERFLOW_TOLERANCE) {
        overflowing.push(`${id} a formula ${inner.scrollWidth - inner.clientWidth}px too wide`)
        continue
      }
      // Piece by piece (getClientRects): what lies in the column the layout
      // throws away, or below the page, is lost height; what runs past the
      // page's right or left edge in its own column is lost width. A line's
      // leading may hang below the page by LEADING_TOLERANCE without losing a
      // letter (Safari left 2 px of a 15 px line of code there, measured).
      let lostHeight = 0
      let lostWidth = 0
      for (const piece of Array.from(element.getClientRects())) {
        if (piece.width <= 0 && piece.height <= 0) {
          continue
        }
        if (piece.left >= edge.right - OVERFLOW_TOLERANCE) {
          lostHeight += piece.height
          continue
        }
        lostHeight += Math.max(0, piece.bottom - Math.max(edge.bottom, piece.top))
        lostWidth = Math.max(lostWidth, piece.right - edge.right, edge.left - piece.left)
      }
      if (lostHeight > LEADING_TOLERANCE || lostWidth > OVERFLOW_TOLERANCE) {
        const past = Math.max(lostHeight, lostWidth)
        const what = element.className && typeof element.className === "string" ? "." + element.className.split(" ")[0] : ""
        const reason = `${id} ${element.tagName.toLowerCase()}${what} ${Math.round(past)}px`
        if (split) {
          overflowing.push(reason)
        } else {
          cutOff.set(id, reason)
        }
      } else if (!split) {
        whole.add(id)
      }
    }
  }
  for (const [id, reason] of cutOff) {
    if (!whole.has(id)) {
      overflowing.push(reason)
    }
  }
  return { found: found.size, overflowing: Array.from(new Set(overflowing)) }
}

function say(status: Element | null, text: string) {
  if (status) {
    status.textContent = text
  }
}

async function printHandout(mode: Mode, paper: Paper, box: HTMLElement, settings: Settings) {
  if (busy) {
    return
  }
  const words = settings.words
  const status = box.querySelector(".plantoir-print-status")
  const menu = box.querySelector("details.plantoir-print-menu-box") as HTMLDetailsElement | null
  if (menu) {
    menu.open = false
  }

  // Plantoir's own preview cannot print or open a window, so it asks the app
  // to open this page in the teacher's web browser, which prints it at once
  // (shared-rules.json -> printablePages.previewPane).
  const app = (window as unknown as {
    webkit?: { messageHandlers?: { plantoirPrint?: { postMessage: (message: unknown) => void } } }
  }).webkit?.messageHandlers?.plantoirPrint
  if (app) {
    say(status, words.openingInBrowser)
    app.postMessage({ mode, paper, url: location.href.split("#")[0] })
    setTimeout(() => say(status, ""), 6000)
    return
  }

  busy = true
  say(status, words.preparing)
  const html = document.documentElement
  const theme = html.getAttribute("saved-theme")
  let frame: HTMLIFrameElement | null = null
  let restored = false
  const restore = () => {
    if (restored) {
      return
    }
    restored = true
    if (theme === "dark") {
      html.setAttribute("saved-theme", "dark")
      document.dispatchEvent(new CustomEvent("themechange", { detail: { theme: "dark" } }))
    }
    frame?.remove()
    busy = false
  }

  try {
    // Diagrams are drawn for the theme on screen: draw them light first on a
    // dark page (never written to the reader's saved preference). And wait
    // for them on EVERY page: opened from Plantoir's preview, Print starts at
    // the first page load, before Quartz has drawn anything, and a light page
    // printed every diagram as its source text (implementation review B1,
    // measured: 0 of 5 drawn in Chrome, Mermaid source in Safari's PDF).
    // Returns at once when every diagram is already drawn.
    const diagrams = Array.from(document.querySelectorAll(".center code.mermaid"))
    if (theme === "dark") {
      html.setAttribute("saved-theme", "light")
      document.dispatchEvent(new CustomEvent("themechange", { detail: { theme: "light" } }))
    }
    if (diagrams.length > 0) {
      await diagramsRedrawn(diagrams, 8000)
    }
    for (const prepare of hooks.plantoirPrint?.prepare ?? []) {
      await prepare()
    }

    const root = box.dataset.root ?? "./"
    const pageTitle =
      (settings.page?.title ?? "").trim() ||
      (document.querySelector(".center h1.article-title")?.textContent ?? "").trim()
    const handout = buildHandout(mode, settings)
    await imagesReady(handout)
    // Counted before the layout sees it (completeness).
    let expected = 0
    for (const element of handout.querySelectorAll(COUNTED)) {
      element.setAttribute("data-plantoir-c", String(expected))
      expected += 1
    }
    frame = makeFrame(paper)
    const doc = frame.contentDocument!
    const indexCss = indexStylesheet()
    copyPageStylesheets(doc, indexCss, root)
    await fontsReady(doc)
    await fitWideFormulas(doc, handout, paper, indexCss)

    let paginated = false
    try {
      await loadScript(doc, root + "static/pagedjs/paged.min.js")
      const engine = (frame.contentWindow as unknown as {
        PagedModule?: { Previewer: new () => { preview: Function } }
      }).PagedModule
      if (!engine || !indexCss) {
        throw new Error("no print layout")
      }
      await stylesheetsLoaded(doc)
      await fontsReady(doc)
      const previewer = new engine.Previewer()
      const content = doc.importNode(handout, true)
      await previewer.preview(content, [indexCss, { [location.href]: pagedRules(paper, settings) }], doc.body)
      labelPages(doc, mode, settings, pageTitle)
      paginated = true
    } catch {
      paginated = false
    }
    if (paginated) {
      const pictures: Promise<unknown>[] = []
      for (const image of doc.querySelectorAll("img")) {
        pictures.push((image as HTMLImageElement).decode().catch(() => undefined))
      }
      await Promise.all(pictures)
      const result = checkComplete(doc, expected)
      doc.documentElement.setAttribute("data-plantoir-print-path", "paged")
      doc.documentElement.setAttribute("data-plantoir-expected", String(expected))
      doc.documentElement.setAttribute("data-plantoir-found", String(result.found))
      doc.documentElement.setAttribute("data-plantoir-overflowing", String(result.overflowing.length))
      if (!mayPrint(expected, result.found, result.overflowing.length)) {
        // Nothing is printed with anything missing (completeness).
        console.warn(
          `Plantoir: this handout was not printed: ${expected - result.found} of ${expected} pieces were not laid out, ` +
            `${result.overflowing.length} ran off their page: ` +
            result.overflowing.slice(0, 20).join(", "),
        )
        say(status, words.incomplete)
        restore()
        return
      }
    } else {
      // Without the print layout the browser lays the handout out itself:
      // everything prints, corners only where the browser prints margin
      // boxes, one count for the document. Said in the console and on the
      // frame, so the browser check fails if the fixture ever takes it.
      console.warn("Plantoir: the print layout could not be used; the browser laid this handout out itself.")
      doc.body.innerHTML = ""
      if (indexCss) {
        const link = doc.createElement("link")
        link.rel = "stylesheet"
        link.href = indexCss
        doc.head.appendChild(link)
      }
      const rules = doc.createElement("style")
      rules.textContent = document.getElementById("plantoir-print-page")?.textContent ?? ""
      doc.head.appendChild(rules)
      doc.body.appendChild(doc.importNode(handout, true))
      doc.documentElement.setAttribute("data-plantoir-print-path", "fallback")
      await stylesheetsLoaded(doc)
    }

    frame.contentWindow!.addEventListener("afterprint", () => restore(), { once: true })
    say(status, "")
    frame.contentWindow!.focus()
    frame.contentWindow!.print()
    // print() returns when the dialog closes in Safari, Chrome and Edge
    // (measured), and afterprint has normally put things back already. If a
    // browser never sends afterprint, the page must not be left light with a
    // dead button until a reload (review N4).
    restore()
  } catch {
    say(status, words.couldNotPrepare)
    restore()
  }
}

document.addEventListener("nav", () => {
  const html = document.documentElement
  html.classList.remove(PRINTABLE, FROM_DARK)

  const line = document.querySelector(
    ".plantoir-meta-line[data-plantoir-printable]",
  ) as HTMLElement | null
  if (!line) {
    return
  }
  const box = line.querySelector("div.plantoir-print") as HTMLElement | null
  const settings = readSettings(line)
  if (!settings) {
    return
  }
  stampRoles(settings)
  stampCurriculum(settings)
  const article = document.querySelector(".center article")
  if (article) {
    markWideTables(article)
  }
  // Code keeps its box under ⌘P too (paperLook.code); a diagram is no code.
  // And its numbers a box as wide as its longest: under ⌘P "100" printed as
  // "10" over "0" until the digits went with it (#499 review S2).
  for (const pre of document.querySelectorAll(".center article pre")) {
    if (!pre.querySelector(":scope > code.mermaid")) {
      pre.classList.add("plantoir-code")
      const code = pre.querySelector(":scope > code") as HTMLElement | null
      if (code) {
        const lines = code.querySelectorAll(":scope > [data-line]").length
        code.style.setProperty("--plantoir-digits", String(Math.max(2, String(lines).length)))
      }
    }
  }
  html.classList.add(PRINTABLE)

  if (box) {
    const menu = box.querySelector("details.plantoir-print-menu-box") as HTMLDetailsElement | null
    // A page with no answers offers questions only: the other two would print
    // a title alone (printablePages.modes.menu, #499 plan review N5).
    const hasAnswers =
      document.querySelector(
        '.center article blockquote.callout[data-plantoir-role="answer"], .center article blockquote.callout[data-plantoir-role="question"]',
      ) !== null
    if (!hasAnswers) {
      for (const button of box.querySelectorAll(
        'button[data-mode="answersOnly"], button[data-mode="withAnswersAtTheEnd"]',
      )) {
        ;(button as HTMLElement).hidden = true
      }
    }
    const radios = Array.from(box.querySelectorAll('input[name="plantoir-print-paper"]')) as HTMLInputElement[]
    const kept = rememberedPaper()
    for (const radio of radios) {
      radio.checked = radio.value === kept
      const choose = () => {
        if (radio.checked && PAPERS.includes(radio.value as Paper)) {
          rememberPaper(radio.value as Paper)
        }
      }
      radio.addEventListener("change", choose)
      window.addCleanup(() => radio.removeEventListener("change", choose))
    }
    const chosenPaper = (): Paper => {
      for (const radio of radios) {
        if (radio.checked && PAPERS.includes(radio.value as Paper)) {
          return radio.value as Paper
        }
      }
      return "portrait"
    }
    for (const button of box.querySelectorAll("button[data-mode]")) {
      const press = () => {
        const wanted = (button as HTMLElement).dataset.mode as Mode
        if (MODES.includes(wanted)) {
          printHandout(wanted, chosenPaper(), box, settings)
        }
      }
      button.addEventListener("click", press)
      window.addCleanup(() => button.removeEventListener("click", press))
    }
    if (menu) {
      // Escape, or a click anywhere else, closes the menu. Inside the menu,
      // Escape is kept from the site's own Escape handler, which hides the
      // search and moved focus to the search button (#499 review N2).
      const onMenuKey = (event: KeyboardEvent) => {
        if (event.key === "Escape" && menu.open) {
          event.stopPropagation()
          menu.open = false
          ;(menu.querySelector("summary") as HTMLElement | null)?.focus()
        }
      }
      const onKey = (event: KeyboardEvent) => {
        if (event.key === "Escape" && menu.open) {
          menu.open = false
        }
      }
      menu.addEventListener("keydown", onMenuKey)
      const onClick = (event: MouseEvent) => {
        if (menu.open && !menu.contains(event.target as Node)) {
          menu.open = false
        }
      }
      document.addEventListener("keydown", onKey)
      document.addEventListener("click", onClick)
      window.addCleanup(() => {
        menu.removeEventListener("keydown", onMenuKey)
        document.removeEventListener("keydown", onKey)
        document.removeEventListener("click", onClick)
      })
    }
  }

  // ⌘P: questions only, laid out by the browser (decision 7), in light
  // colours. Diagrams already drawn dark cannot be re-drawn in time, so the
  // stylesheet inverts them while printing (review S5).
  let wasDark = false
  // Titles lose "(click to expand)" on paper too (decision 5), and get their
  // own words back afterwards.
  const titlesBefore: Map<Element, string> = new Map()
  const beforePrint = () => {
    if (busy) {
      return
    }
    for (const inner of document.querySelectorAll(".center article .callout-title-inner")) {
      const shown = (inner.textContent ?? "").trim()
      const cleaned = cleanTitle(shown)
      if (cleaned !== shown) {
        titlesBefore.set(inner, inner.innerHTML)
        inner.textContent = cleaned
      }
    }
    wasDark = html.getAttribute("saved-theme") === "dark"
    if (wasDark) {
      // A diagram drawn dark keeps the dark colours it was drawn with, so
      // that inverting it as a whole gives dark lines and words on light
      // shapes; flipping only the page's colours left light words on light
      // shapes (measured in Chrome).
      const page = getComputedStyle(html)
      for (const diagram of document.querySelectorAll(".center pre:has(> code.mermaid)")) {
        for (const name of DIAGRAM_COLOURS) {
          ;(diagram as HTMLElement).style.setProperty(name, page.getPropertyValue(name))
        }
      }
      html.classList.add(FROM_DARK)
      html.setAttribute("saved-theme", "light")
    }
  }
  const afterPrint = () => {
    for (const [inner, markup] of titlesBefore) {
      inner.innerHTML = markup
    }
    titlesBefore.clear()
    if (wasDark) {
      for (const diagram of document.querySelectorAll(".center pre:has(> code.mermaid)")) {
        for (const name of DIAGRAM_COLOURS) {
          ;(diagram as HTMLElement).style.removeProperty(name)
        }
      }
      html.classList.remove(FROM_DARK)
      html.setAttribute("saved-theme", "dark")
      wasDark = false
    }
  }
  window.addEventListener("beforeprint", beforePrint)
  window.addEventListener("afterprint", afterPrint)
  window.addCleanup(() => {
    window.removeEventListener("beforeprint", beforePrint)
    window.removeEventListener("afterprint", afterPrint)
  })

  // Opened by Plantoir's preview to print: start at once, once, with the
  // way of printing and the paper chosen there (previewPane).
  const asked = /^#plantoir-print=([A-Za-z]+)(?:&paper=([A-Za-z]+))?$/.exec(location.hash)
  if (box && asked) {
    history.replaceState(history.state, "", location.pathname + location.search)
    const wanted = asked[1] as Mode
    const paper: Paper = asked[2] === "landscape" ? "landscape" : "portrait"
    if (MODES.includes(wanted)) {
      printHandout(wanted, paper, box, settings)
    }
  }
})
