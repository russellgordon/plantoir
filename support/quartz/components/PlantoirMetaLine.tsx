// Printable pages (#454): the page's date line, with a Print button at its
// trailing edge when the page asks for one.
//
// Wraps the date line (ContentMeta) in the CONTENT layout only - build_site.py
// makes that edit - so folder and tag pages never get a button. A page that
// asks for nothing renders exactly the date line it always did, byte for
// byte: decision 7 says pages that have not opted in print as before, and the
// first half of that is that their HTML has not changed.
//
// Two kinds of button:
// * `printPdf:` (resolved by the build against the course's Media folder) -> a
//   plain link to the PDF. No menu, no script, no print engine. It wins over
//   `printable` (decision 14).
// * `printable: true` -> a Print button that makes a handout in the page itself
//   (print.inline.ts), with a small menu for questions only and answers only.
//
// The words and the corners come from quartz/plantoir_print.json, which the
// build writes from the contract and the course's settings on every build. It
// is READ here rather than imported, so a missing file costs the button and
// never the site: the page then renders exactly as an unprinted page does.

import { readFileSync } from "fs"
import { join } from "path"
import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"
import { concatenateResources } from "../util/resources"
import { FilePath, FullSlug, joinSegments, pathToRoot, slugifyFilePath } from "../util/path"
import style from "./styles/print.scss"
// @ts-ignore
import script from "./scripts/print.inline"

type Corners = { topLeft: string; topRight: string; bottomLeft: string; bottomRight: string }
type PrintSettings = {
  corners: Corners
  words: Record<string, string>
  answerKinds: string[]
  answerTitleWords: string[]
  defaultMode: string
}

function readPrintSettings(): PrintSettings | null {
  try {
    const text = readFileSync(join(process.cwd(), "quartz", "plantoir_print.json"), "utf-8")
    return JSON.parse(text) as PrintSettings
  } catch {
    return null
  }
}

// A CSS string, quoted and escaped, for a margin box's `content`. Spaces
// become non-breaking: a corner is ONE line, and a narrow margin box would
// otherwise wrap "Page 1 of 3" onto three (measured in Safari).
function cssString(text: string): string {
  const escaped = text.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ")
  return '"' + escaped.replace(/ /g, "\\0000a0") + '"'
}

// The same, keeping ordinary spaces so the text can wrap.
function cssPlainString(text: string): string {
  return '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ") + '"'
}

// "Page {n} of {total}" as a CSS content value counting the whole document:
// what the browser's own Print (⌘P) can do, where nothing paginates the
// questions and the answers separately.
function countedLabel(template: string): string {
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

// The page box and its four corners. The browser's own Print reads this from
// the page (Chrome and Edge print margin boxes; Safari and Firefox do not),
// and the handout passes the same text to the print layout with the bottom
// right corner replaced by each page's own label.
export function pageRules(corners: Corners, pageLabelTemplate: string): string {
  const box = "font-family: var(--bodyFont), sans-serif; font-size: 9pt; color: #333; white-space: nowrap; vertical-align: bottom;"
  // The top left corner may take two lines: a long school name sharing it
  // with the course code, beside three blanks, printed ON TOP of the blanks
  // when every corner was one line (implementation review S3, measured).
  // Its spaces stay ordinary so it can wrap; the blanks and the page label
  // never do.
  const wrapping =
    "font-family: var(--bodyFont), sans-serif; font-size: 9pt; color: #333; white-space: normal; vertical-align: bottom;"
  return (
    "@page { size: letter; margin: 0.9in 0.75in; " +
    `@top-left { content: ${cssPlainString(corners.topLeft)}; ${wrapping} } ` +
    `@top-right { content: ${cssString(corners.topRight)}; ${box} } ` +
    `@bottom-left { content: ${cssString(corners.bottomLeft)}; ${box} } ` +
    `@bottom-right { content: ${countedLabel(pageLabelTemplate)}; ${box} } }`
  )
}

// A printer, drawn inline the way Quartz draws its search and dark-mode icons
// (#497): no image file to fetch, the button's own colour through
// currentColor, and hidden from screen readers so the button is still read
// as its label alone. Hidden on paper with the button itself.
function PrinterGlyph() {
  return (
    <svg
      class="plantoir-print-glyph"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M7 8V3h10v5" />
      <path d="M7 17H5a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2" />
      <path d="M7 13h10v8H7z" />
    </svg>
  )
}

export default ((inner: QuartzComponent) => {
  const Inner = inner

  const PlantoirMetaLine: QuartzComponent = (props: QuartzComponentProps) => {
    const frontmatter = (props.fileData.frontmatter ?? {}) as Record<string, unknown>
    const pdf =
      typeof frontmatter.printPdf === "string" && frontmatter.printPdf.trim() !== ""
        ? frontmatter.printPdf.trim()
        : null
    const printable = frontmatter.printable === true
    if (pdf === null && !printable) {
      return <Inner {...props} />
    }
    const settings = readPrintSettings()
    if (settings === null) {
      return <Inner {...props} />
    }
    const words = settings.words
    const root = pathToRoot(props.fileData.slug as FullSlug)

    let button
    if (pdf !== null) {
      const href = joinSegments(root, slugifyFilePath(("Media/" + pdf) as FilePath))
      button = (
        <a class="plantoir-print plantoir-print-pdf" href={href} target="_blank" rel="noopener">
          <PrinterGlyph />
          {words.print}
        </a>
      )
    } else {
      button = (
        <div class="plantoir-print" data-root={root + "/"}>
          <button type="button" class="plantoir-print-button" data-mode={settings.defaultMode}>
            <PrinterGlyph />
            {words.print}
          </button>
          <details class="plantoir-print-more">
            <summary aria-label={words.moreWaysToPrint} title={words.moreWaysToPrint}></summary>
            <div class="plantoir-print-menu">
              <button type="button" data-mode="questionsOnly">
                {words.questionsOnly}
              </button>
              <button type="button" data-mode="answersOnly">
                {words.answersOnly}
              </button>
            </div>
          </details>
          <span class="plantoir-print-status" role="status" aria-live="polite"></span>
        </div>
      )
    }

    return (
      <div
        class="plantoir-meta-line"
        data-plantoir-printable={printable ? "true" : undefined}
        data-settings={printable ? JSON.stringify(settings) : undefined}
      >
        <Inner {...props} />
        {button}
        {printable && (
          <style
            id="plantoir-print-page"
            dangerouslySetInnerHTML={{ __html: pageRules(settings.corners, words.pageLabel) }}
          />
        )}
      </div>
    )
  }

  PlantoirMetaLine.displayName = inner.displayName
  // The inner component's own resources travel with it (review S7), the way
  // DesktopOnly and Flex carry theirs, so the date line keeps its styles even
  // if a layout one day wraps every ContentMeta.
  PlantoirMetaLine.css = concatenateResources(inner.css, style)
  PlantoirMetaLine.beforeDOMLoaded = inner.beforeDOMLoaded
  PlantoirMetaLine.afterDOMLoaded = concatenateResources(inner.afterDOMLoaded, script)
  return PlantoirMetaLine
}) satisfies QuartzComponentConstructor<QuartzComponent>
