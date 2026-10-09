// Printable pages (#454): the Print button, and ⌘P on a printable page.
//
// Bundled into every site's postscript.js, so it must be INERT on a page that
// has not opted in: on each page load it takes the "printable" mark off the
// page first and puts it back only when this page carries the button (review
// B2 - Quartz's single-page navigation keeps <html> between pages, so a mark
// left behind would make the next, ordinary page print as a worksheet).
//
// Pressing Print makes the handout IN THE PAGE: the article is cloned, its
// answers lifted to the end, its folded hints opened, and the result paginated
// by Paged.js inside an iframe that sits ON SCREEN but invisible (measured:
// off screen, Safari paginated one page every ~8 s; on screen, 11 pages in
// 192 ms), then printed from there. The plan and every measurement are in
// documentation/06-quartz-customizations.md, section F.

import { cleanTitle, label, pageLabel, role } from "./printRules"

type Mode = "withAnswersAtTheEnd" | "questionsOnly" | "answersOnly"
type Corners = { topLeft: string; topRight: string; bottomLeft: string; bottomRight: string }
type Settings = {
  corners: Corners
  words: Record<string, string>
  answerKinds: string[]
  answerTitleWords: string[]
  defaultMode: Mode
}
type PrintHooks = { prepare: Array<() => Promise<void>> }

const PRINTABLE = "plantoir-printable"
const FROM_DARK = "plantoir-printing-from-dark"
const MODES: Mode[] = ["withAnswersAtTheEnd", "questionsOnly", "answersOnly"]
// A code block longer than this many lines may break across pages; a shorter
// one moves whole to the next page. About two thirds of a letter page.
const SPLITTABLE_LINES = 25
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
  const original = document.querySelector(".center article")
  const article = (original ? original.cloneNode(true) : document.createElement("article")) as HTMLElement

  for (const control of article.querySelectorAll(
    ".clipboard-button, .expand-button, #mermaid-container, .mermaid-controls",
  )) {
    control.remove()
  }

  const entries: HTMLElement[] = []
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
      const named = label(
        titleText,
        callout.getAttribute("data-callout") ?? "",
        listItemNumber(callout, article),
        nearestHeading(callout, article),
        answerNumber,
        words,
        settings.answerTitleWords,
      )
      setTitle(callout, named)
      callout.remove()
      entries.push(callout)
    } else if (calloutRole === "question") {
      setTitle(callout, cleanTitle(titleText))
      const body = callout.querySelector(":scope > .callout-content")
      const entry = callout.cloneNode(false) as HTMLElement
      const heading = callout.querySelector(":scope > .callout-title")
      if (heading) {
        entry.appendChild(heading.cloneNode(true))
      }
      if (body) {
        entry.appendChild(body)
        entries.push(entry)
      }
    } else {
      setTitle(callout, cleanTitle(titleText))
    }
  }

  if (mode !== "answersOnly") {
    if (title) {
      center.appendChild(title.cloneNode(true))
    }
    center.appendChild(article)
  } else if (title) {
    center.appendChild(title.cloneNode(true))
  }

  if (mode !== "questionsOnly" && entries.length > 0) {
    const answers = document.createElement("section")
    answers.className = "plantoir-answers"
    if (mode === "answersOnly") {
      answers.classList.add("plantoir-answers-only")
    }
    const heading = document.createElement("h2")
    heading.textContent = words.answersHeading
    answers.appendChild(heading)
    for (const entry of entries) {
      answers.appendChild(entry)
    }
    center.appendChild(answers)
  }

  // Line numbers written out: the print layout does not carry the site's
  // line counter across, and every line printed as 1 (measured in Safari).
  for (const code of center.querySelectorAll("pre > code")) {
    let number = 0
    for (const line of code.querySelectorAll(":scope > [data-line]")) {
      number += 1
      line.setAttribute("data-plantoir-line", String(number))
    }
  }
  for (const pre of center.querySelectorAll("pre")) {
    const lines = pre.querySelectorAll("[data-line]").length || (pre.textContent ?? "").split("\n").length
    if (lines > SPLITTABLE_LINES) {
      pre.classList.add("plantoir-splittable")
    }
  }
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

async function imagesReady(within: HTMLElement) {
  const waits: Promise<unknown>[] = []
  for (const image of within.querySelectorAll("img")) {
    image.loading = "eager"
    waits.push(image.decode().catch(() => undefined))
  }
  await Promise.all(waits)
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

function makeFrame(): HTMLIFrameElement {
  const frame = document.createElement("iframe")
  frame.setAttribute("aria-hidden", "true")
  frame.tabIndex = -1
  // ON screen, invisible: off screen, Safari paginates a page every ~8 s.
  frame.style.cssText =
    "position:fixed;left:0;top:0;width:8.5in;height:11in;opacity:0;pointer-events:none;border:0;"
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
function copyPageStylesheets(doc: Document, indexCss: string | null) {
  for (const element of document.head.querySelectorAll('link[rel="stylesheet"], style')) {
    if (element instanceof HTMLLinkElement && element.href === indexCss) {
      continue
    }
    const copy = doc.importNode(element, true) as HTMLElement
    copy.setAttribute("data-pagedjs-ignore", "")
    doc.head.appendChild(copy)
  }
}

function labelPages(doc: Document, mode: Mode, words: Record<string, string>) {
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
    const text =
      index < firstAnswerPage
        ? pageLabel("questions", index + 1, firstAnswerPage, words)
        : pageLabel("answers", index - firstAnswerPage + 1, answerPages, words)
    // No-break spaces: a corner is one line (see PlantoirMetaLine.cssString).
    page.style.setProperty("--plantoir-page-label", JSON.stringify(text.replace(/ /g, "\u00a0")))
  })
}

// What the print layout must see in the text it is handed, not only in the
// site's stylesheet: it decides where pages break by matching these against
// the handout BEFORE it is placed in the frame, where a rule scoped to the
// frame's <html> matches nothing (measured: the answers did not start on a
// fresh page until this was added).
const LAYOUT_RULES = [
  ".plantoir-answers { break-before: page; }",
  ".plantoir-answers-only { break-before: auto; }",
  "h1, h2, h3, h4, h5, h6 { break-after: avoid; }",
  "blockquote.callout, table, figure, .katex-display, .pl-figure, pre:not(.plantoir-splittable) { break-inside: avoid; }",
].join("\n")

// The page box for the print layout: the page's own rules, with the bottom
// right corner taking each page's label instead of counting the document.
function pagedRules(): string {
  const own = document.getElementById("plantoir-print-page")?.textContent ?? ""
  const labelled = own.replace(
    /@bottom-right \{ content: [^;]*;/,
    "@bottom-right { content: var(--plantoir-page-label);",
  )
  return labelled + "\n" + LAYOUT_RULES
}

function say(status: Element | null, text: string) {
  if (status) {
    status.textContent = text
  }
}

async function printHandout(mode: Mode, box: HTMLElement, settings: Settings) {
  if (busy) {
    return
  }
  const words = settings.words
  const status = box.querySelector(".plantoir-print-status")
  const more = box.querySelector("details.plantoir-print-more") as HTMLDetailsElement | null
  if (more) {
    more.open = false
  }

  // Plantoir's own preview cannot print or open a window, so it asks the app
  // to open this page in the teacher's web browser, which prints it at once
  // (shared-rules.json -> printablePages.previewPane).
  const app = (window as unknown as {
    webkit?: { messageHandlers?: { plantoirPrint?: { postMessage: (message: unknown) => void } } }
  }).webkit?.messageHandlers?.plantoirPrint
  if (app) {
    say(status, words.openingInBrowser)
    app.postMessage({ mode, url: location.href.split("#")[0] })
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
    if (theme === "dark") {
      // Diagrams are drawn for the theme on screen; draw them light first.
      // Never written to the reader's saved preference.
      const diagrams = Array.from(document.querySelectorAll(".center code.mermaid"))
      html.setAttribute("saved-theme", "light")
      document.dispatchEvent(new CustomEvent("themechange", { detail: { theme: "light" } }))
      if (diagrams.length > 0) {
        await diagramsRedrawn(diagrams, 5000)
      }
    }
    for (const prepare of hooks.plantoirPrint?.prepare ?? []) {
      await prepare()
    }

    const handout = buildHandout(mode, settings)
    await imagesReady(handout)
    frame = makeFrame()
    const doc = frame.contentDocument!
    const indexCss = indexStylesheet()
    copyPageStylesheets(doc, indexCss)

    let paginated = false
    try {
      await loadScript(doc, (box.dataset.root ?? "./") + "static/pagedjs/paged.min.js")
      const engine = (frame.contentWindow as unknown as {
        PagedModule?: { Previewer: new () => { preview: Function } }
      }).PagedModule
      if (!engine || !indexCss) {
        throw new Error("no print layout")
      }
      await stylesheetsLoaded(doc)
      const previewer = new engine.Previewer()
      const content = doc.importNode(handout, true)
      await previewer.preview(content, [indexCss, { [location.href]: pagedRules() }], doc.body)
      labelPages(doc, mode, words)
      paginated = true
    } catch {
      paginated = false
    }
    if (!paginated) {
      // Without the print layout the browser lays the handout out itself:
      // corners where it prints margin boxes, one count for the document.
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
      await stylesheetsLoaded(doc)
    }

    frame.contentWindow!.addEventListener("afterprint", () => restore(), { once: true })
    say(status, "")
    frame.contentWindow!.focus()
    frame.contentWindow!.print()
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
  html.classList.add(PRINTABLE)

  if (box) {
    for (const button of box.querySelectorAll("button[data-mode]")) {
      const press = () => {
        const wanted = (button as HTMLElement).dataset.mode as Mode
        printHandout(MODES.includes(wanted) ? wanted : settings.defaultMode, box, settings)
      }
      button.addEventListener("click", press)
      window.addCleanup(() => button.removeEventListener("click", press))
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

  // Opened by Plantoir's preview to print: start at once, once.
  const asked = /^#plantoir-print=([A-Za-z]+)$/.exec(location.hash)
  if (box && asked) {
    history.replaceState(history.state, "", location.pathname + location.search)
    const wanted = asked[1] as Mode
    printHandout(MODES.includes(wanted) ? wanted : settings.defaultMode, box, settings)
  }
})
