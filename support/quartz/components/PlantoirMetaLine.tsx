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
// * `printable: true` -> a Print button that opens a menu (#499, decision 29):
//   portrait or landscape, then Questions only, Answers only, Both. Nothing
//   prints until one is chosen; the handout is made in the page itself
//   (print.inline.ts).
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
import { codeBoxRules, countedLabel, cssPlainString, cssString, fontFaceRules, footerLeft, pageBoxRules } from "./scripts/printRules"
// @ts-ignore
import script from "./scripts/print.inline"

type Corners = { topLeft: string; topRight: string; bottomLeft: string; bottomRight: string }
type PrintSettings = {
  corners: Corners
  words: Record<string, string>
  answerKinds: string[]
  answerTitleWords: string[]
  curriculumHeadings: string[]
}

function readPrintSettings(): PrintSettings | null {
  try {
    const text = readFileSync(join(process.cwd(), "quartz", "plantoir_print.json"), "utf-8")
    return JSON.parse(text) as PrintSettings
  } catch {
    return null
  }
}

// The page box and its four corners for ⌘P, and the faces the page prints in
// (#499). The browser's own Print reads this from the page (Chrome and Edge
// print margin boxes; Safari and Firefox do not); the handout writes its own
// from the same rules (printRules.pageBoxRules) with the paper's size and
// each page's labels. No size here: ⌘P's own dialog decides portrait or
// landscape (printablePages.paper).
export function pageRules(corners: Corners, words: Record<string, string>, title: string, root: string): string {
  return (
    fontFaceRules(root) +
    "\n" +
    pageBoxRules(null, {
      topLeft: cssPlainString(corners.topLeft),
      topRight: cssString(corners.topRight),
      bottomLeft: cssString(footerLeft(title, corners.bottomLeft, "questions", words)),
      bottomRight: countedLabel(words.pageLabel),
    }) +
    "\n@media print { " +
    codeBoxRules("html.plantoir-printable") +
    " }"
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
      // The menu (#499, decision 29): paper first, so a teacher sees it before
      // choosing (plan review N2), then the three ways of printing in the
      // contract's order. Each choice prints; the summary only opens it.
      button = (
        <div class="plantoir-print" data-root={root + "/"}>
          <details class="plantoir-print-menu-box">
            <summary class="plantoir-print-button">
              <PrinterGlyph />
              {words.print}
            </summary>
            <div class="plantoir-print-menu">
              <div class="plantoir-print-paper" role="radiogroup" aria-label={words.paper}>
                <label>
                  <input type="radio" name="plantoir-print-paper" value="portrait" checked />
                  {words.portrait}
                </label>
                <label>
                  <input type="radio" name="plantoir-print-paper" value="landscape" />
                  {words.landscape}
                </label>
              </div>
              {/* Safari's print window opens on Portrait whatever the page asks,
                  and covers the page while it is open, so this is said in the
                  menu, before it opens (#499 fix review S2). */}
              <p class="plantoir-print-paper-note">{words.landscapeInDialog}</p>
              <button type="button" data-mode="questionsOnly">
                {words.questionsOnly}
              </button>
              <button type="button" data-mode="answersOnly">
                {words.answersOnly}
              </button>
              <button type="button" data-mode="withAnswersAtTheEnd">
                {words.both}
              </button>
            </div>
          </details>
          <span class="plantoir-print-status" role="status" aria-live="polite"></span>
        </div>
      )
    }

    // The page's own title and description travel with the settings: the
    // footer names the page (printablePages.footer), and a description prints
    // under the title in grey, as the LaTeX handouts' instructions do.
    const title = typeof frontmatter.title === "string" ? frontmatter.title.trim() : ""
    const subtitle = typeof frontmatter.description === "string" ? frontmatter.description.trim() : ""
    const pageSettings = printable ? JSON.stringify({ ...settings, page: { title, subtitle } }) : undefined

    return (
      <div
        class="plantoir-meta-line"
        data-plantoir-printable={printable ? "true" : undefined}
        data-settings={pageSettings}
      >
        <Inner {...props} />
        {button}
        {printable && (
          <style
            id="plantoir-print-page"
            dangerouslySetInnerHTML={{ __html: pageRules(settings.corners, words, title, root + "/") }}
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
