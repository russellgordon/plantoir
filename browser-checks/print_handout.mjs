// Prints the verify fixture's printable page the way a teacher does (#454,
// #498, #499) in headless Chrome for Testing, and reads the PAPER back.
//
// For each of the three ways of printing, on portrait and on landscape paper,
// it opens `<page>#plantoir-print=<mode>&paper=<paper>` (the address
// Plantoir's preview hands to a browser), catches the handout at the moment
// it is printed, prints that handout to a PDF with Chrome's own printer, and
// checks with poppler's pdftotext, pdfinfo and pdffonts that:
//
// - the print layout ran (never the browser-flow fallback), counted every
//   piece of the handout and found all of it on a page, none cut off;
// - every question's words, every answer, every one of the 110 lines of code
//   with ITS OWN line number (1 to 110, none broken into digits), every table
//   row, and the words before and after every picture, drawing, diagram and
//   formula are in the PDF's text - questions only in the modes that print
//   questions, answers only in the modes that print answers (#499: Russell's
//   print lost three questions, 18 lines of code and its page numbers);
// - the paper is letter in the orientation chosen, every page carries its
//   label ("Page 2 of 9", "Answers 1 of 2") about 0.4 in above the paper's
//   edge, and the text is set in Latin Modern;
// - no callout prints a box except the worked example's peach one, code
//   keeps a hairline box with no fill on every piece (DECISIONS 30), no page
//   holds a heading alone, the Mermaid diagram is DRAWN (#454 review B1), and
//   the Curriculum connection is printed nowhere (#498);
//
// then that the Print menu prints nothing until a way of printing is chosen,
// in the contract's order, with the paper remembered, and that ⌘P on the page
// leaves orientation to the browser's own dialog and still leaves the
// Curriculum connection off - while the page that did NOT opt in prints its
// own under ⌘P, as every page did before.
//
// Kept OUT of scripts/ on purpose: it needs a browser on the Mac, not the
// image, and anything in scripts/ is hashed into the image and shipped.
// verify.sh runs it when a Chrome for Testing is found and says SKIPPED when
// not. No packages: Node 22's own WebSocket speaks to Chrome directly.
//
//   node browser-checks/print_handout.mjs <chrome binary> <page url> [<not-opted page url>]
//
// PLANTOIR_PRINT_CHECK_KEEP=<folder> keeps the PDFs there.

import { execFileSync, spawn } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const [chromePath, pageUrl, plainUrl] = process.argv.slice(2)
if (!chromePath || !pageUrl) {
  console.error("usage: node print_handout.mjs <chrome> <url> [<not-opted url>]")
  process.exit(2)
}

// The fixture's Curriculum connection: its own words, and the start of the
// expectation it transcludes (EXC2O's B1.1).
const CURRICULUM = /plantoir-curriculum-sentinel-7f3a|assess impacts of climate change/
const FOOTNOTE = /plantoir-footnote-sentinel-7f3a/
// What the worksheet must carry (verify.sh's fixture): every question's
// words, and the words on both sides of every hazard the reviews named.
const QUESTIONS = [
  "plantoir-print-sentinel-7f3a", "Simplify", "Factor", "Self-check: which expansions",
  "plantoir-qstem-3", "plantoir-qstem-4", "plantoir-qstem-5",
  "The first term", "The last term", "The middle term",
  "plantoir-example-sentinel-7f3a", "plantoir-wrap-sentinel",
  "plantoir-before-tall", "plantoir-after-tall", "plantoir-before-viewbox", "plantoir-after-viewbox",
  "plantoir-before-mermaid", "plantoir-after-mermaid", "MM-01", "MM-30",
  "plantoir-before-katex", "plantoir-after-katex", "plantoir-before-table", "plantoir-after-table",
  "plantoir-footnote-sentinel-7f3a", "Need a hint?",
]
const ANSWERS = [
  "a difference of squares", "Questions 1 and 2 of the practice list", "crosses the axis",
  "plantoir-ans-3a", "plantoir-ans-3b", "plantoir-ans-5",
  "plantoir-before-answer-picture", "plantoir-after-answer-picture",
]
// Words only the questions carry, and only the answers: neither may leak.
const ONLY_QUESTIONS = ["plantoir-qstem-3", "plantoir-qstem-5", "plantoir-example-sentinel-7f3a", "CODE-001"]
const ONLY_ANSWERS = ["plantoir-ans-3a", "plantoir-ans-5", "Questions 1 and 2 of the practice list"]
const CODE_LINES = 110
const TABLE_ROWS = 40
const RUNS = [
  ["questionsOnly", "portrait"], ["answersOnly", "portrait"], ["withAnswersAtTheEnd", "portrait"],
  ["questionsOnly", "landscape"], ["answersOnly", "landscape"], ["withAnswersAtTheEnd", "landscape"],
]

const PROBE = `
(() => {
  const watch = new MutationObserver((changes) => {
    for (const change of changes) {
      for (const node of change.addedNodes) {
        if (node.tagName !== "IFRAME") continue
        node.contentWindow.print = () => {
          const frame = node.contentDocument
          const view = node.contentWindow
          const at = (name) => frame.documentElement.getAttribute(name)
          const boxes = []
          for (const callout of frame.querySelectorAll("blockquote.callout")) {
            const style = view.getComputedStyle(callout)
            const tinted = !/^(transparent|rgba\\(0, 0, 0, 0\\))$/.test(style.backgroundColor)
            const framed = parseFloat(style.borderTopWidth) > 0 || parseFloat(style.borderLeftWidth) > 0
            if (tinted || framed) boxes.push(callout.getAttribute("data-callout") + " " + style.backgroundColor)
          }
          const icons = Array.from(frame.querySelectorAll(".callout-icon")).filter((icon) => view.getComputedStyle(icon).display !== "none").length
          const headingOnly = []
          Array.from(frame.querySelectorAll(".pagedjs_page")).forEach((page, index) => {
            const area = page.querySelector(".pagedjs_page_content")
            if (!area) return
            const copy = area.cloneNode(true)
            const headings = copy.querySelectorAll("h1, h2, h3, h4, h5, h6")
            for (const heading of headings) heading.remove()
            const rest = copy.querySelectorAll("img, svg, [data-line]").length + (copy.textContent || "").trim().length
            if (headings.length > 0 && rest === 0) headingOnly.push(index + 1)
          })
          const numbers = []
          for (const number of frame.querySelectorAll(".plantoir-answers .plantoir-number, .plantoir-answers .plantoir-part-mark")) {
            numbers.push((number.textContent || "").trim())
          }
          // Code keeps a hairline box and no fill (DECISIONS 30), on every
          // piece of a block that splits across pages.
          const code = []
          for (const pre of frame.querySelectorAll(".pagedjs_page pre:not(:has(> code.mermaid))")) {
            const style = view.getComputedStyle(pre)
            const sides = [style.borderTopWidth, style.borderRightWidth, style.borderBottomWidth, style.borderLeftWidth].map(parseFloat)
            const filled = !/^(transparent|rgba\\(0, 0, 0, 0\\))$/.test(style.backgroundColor)
            code.push({ boxed: sides.every((width) => width > 0 && width < 1.5), filled, sides: sides.join("/"), fill: style.backgroundColor })
          }
          const firstPage = frame.querySelector(".pagedjs_page")
          window.__plantoirPrinted = {
            html: frame.documentElement.outerHTML,
            path: at("data-plantoir-print-path"),
            expected: Number(at("data-plantoir-expected")),
            found: Number(at("data-plantoir-found")),
            overflowing: Number(at("data-plantoir-overflowing")),
            pages: frame.querySelectorAll(".pagedjs_page").length,
            pageWidth: firstPage ? Math.round(firstPage.getBoundingClientRect().width) : 0,
            diagrams: frame.querySelectorAll("code.mermaid").length,
            drawn: frame.querySelectorAll("code.mermaid > svg").length,
            sourceText: /-->/.test(frame.body.textContent || ""),
            theme: document.documentElement.getAttribute("saved-theme"),
            curriculum: ${CURRICULUM}.test(frame.body.textContent || ""),
            boxes, icons, headingOnly, numbers, code,
            example: !!frame.querySelector('blockquote.callout[data-callout="example"]'),
          }
        }
      }
    }
  })
  watch.observe(document, { childList: true, subtree: true })
})()
`

const work = mkdtempSync(join(tmpdir(), "plantoir-print-check-"))
const profile = join(work, "profile")
const keep = process.env.PLANTOIR_PRINT_CHECK_KEEP || ""
if (keep) mkdirSync(keep, { recursive: true })
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check",
  // Without these a fresh profile waits on the Mac's keychain, and every
  // navigation hangs with no error (measured, Chrome for Testing 155).
  "--use-mock-keychain", "--password-store=basic",
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows", "--hide-scrollbars", "--mute-audio",
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })

function finish(code, message) {
  console.log(message)
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}

const timer = setTimeout(() => finish(1, "FAIL: the handouts and ⌘P were not all printed within 600 s"), 600000)

const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
const poppler = (tool, args) => execFileSync(tool, args, { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] })
// Words a line break split at a hyphen are joined again, and runs of space
// are one space: the sentinels are looked for in the words, not the layout.
const plainText = (text) => text.replace(/-\s*\n\s*/g, "-").replace(/\s+/g, " ")

// What the PDF says, checked against what the fixture holds.
function readPdf(file, mode, paper, printed) {
  const problems = []
  const info = poppler("pdfinfo", [file])
  const pages = Number((/Pages:\s+(\d+)/.exec(info) || [])[1])
  const size = (/Page size:\s+([\d.]+) x ([\d.]+)/.exec(info) || []).slice(1).map(Number)
  const wanted = paper === "landscape" ? [792, 612] : [612, 792]
  if (Math.round(size[0]) !== wanted[0] || Math.round(size[1]) !== wanted[1]) problems.push(`paper ${size.join("x")}, not ${wanted.join("x")}`)
  if (pages !== printed.pages) problems.push(`${pages} PDF pages for ${printed.pages} laid out`)
  const layout = poppler("pdftotext", ["-layout", file, "-"])
  const words = plainText(poppler("pdftotext", [file, "-"]))
  const questions = mode !== "answersOnly"
  const answers = mode !== "questionsOnly"
  for (const sentinel of questions ? QUESTIONS : []) if (!words.includes(sentinel)) problems.push(`missing ${sentinel}`)
  for (const sentinel of answers ? ANSWERS : []) if (!words.includes(sentinel)) problems.push(`missing answer ${sentinel}`)
  for (const sentinel of questions ? [] : ONLY_QUESTIONS) if (words.includes(sentinel)) problems.push(`the answers carry ${sentinel}`)
  for (const sentinel of answers ? [] : ONLY_ANSWERS) if (words.includes(sentinel)) problems.push(`the worksheet carries ${sentinel}`)
  if (questions) {
    // Each line of code with its own number beside it, 1 to 110.
    const numbered = new Map()
    for (const match of layout.matchAll(/(\d+)\s+n = (\d+)\s+# CODE-(\d{3})/g)) {
      numbered.set(Number(match[3]), Number(match[1]))
    }
    const wrong = []
    for (let line = 1; line <= CODE_LINES; line += 1) {
      if (numbered.get(line) !== line) wrong.push(`${line}:${numbered.get(line) ?? "missing"}`)
    }
    if (wrong.length > 0) problems.push(`code lines without their own number: ${wrong.slice(0, 8).join(" ")}${wrong.length > 8 ? " …" : ""}`)
    for (let row = 1; row <= TABLE_ROWS; row += 1) {
      const name = "TROW-" + String(row).padStart(2, "0")
      if (!words.includes(name)) problems.push(`missing ${name}`)
    }
  }
  if (CURRICULUM.test(words)) problems.push("the Curriculum connection is printed")
  if (/\[!/.test(words)) problems.push("a callout's [! marker is printed")
  // Every page its own label, low on the page but where a printer reaches.
  const sheets = layout.split("\f").slice(0, pages)
  sheets.forEach((sheet, index) => {
    if (!/(Page|Answers)\s+\d+\s+of\s+\d+/.test(sheet)) problems.push(`page ${index + 1} has no page label`)
  })
  const boxes = poppler("pdftotext", ["-bbox", file, "-"])
  const height = paper === "landscape" ? 612 : 792
  let labelled = 0
  for (const match of boxes.matchAll(/<word xMin="[\d.]+" yMin="([\d.]+)" xMax="[\d.]+" yMax="([\d.]+)">(Page|Answers)<\/word>/g)) {
    const bottom = Number(match[2])
    if (bottom < height - 72) continue
    labelled += 1
    if (bottom > height - 20) problems.push(`a page label ${(height - bottom).toFixed(1)} pt from the paper's edge`)
  }
  if (labelled < pages) problems.push(`${labelled} page labels in the footer for ${pages} pages`)
  const fonts = poppler("pdffonts", [file])
  for (const face of ["LMRoman10-Regular", "LMSans10-Bold"].concat(questions ? ["LMMono10-Regular"] : [])) {
    if (!fonts.includes(face)) problems.push(`not set in ${face}`)
  }
  return { pages, problems }
}

let buffered = ""
chrome.stderr.on("data", (chunk) => {
  connect(chunk).catch((error) => finish(1, "FAIL: could not drive the browser: " + error))
})

async function connect(chunk) {
  if (buffered === null) return
  buffered += chunk.toString()
  const found = /DevTools listening on (ws:\/\/[^\s]+)/.exec(buffered)
  if (!found) return
  buffered = null
  const port = new URL(found[1]).port
  // A NEW page, as puppeteer makes one: the blank page Chrome starts with
  // never answered a navigation (measured, headless Chrome 155).
  const created = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" })).json()
  const socket = new WebSocket(created.webSocketDebuggerUrl)
  let id = 0
  const waiting = new Map()
  const send = (method, params = {}) => new Promise((resolve) => {
    id += 1
    waiting.set(id, resolve)
    socket.send(JSON.stringify({ id, method, params }))
  })
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    return answer?.result?.value
  }
  const light = { features: [{ name: "prefers-color-scheme", value: "light" }] }
  const open = async (url) => {
    await send("Page.navigate", { url: "about:blank" })
    await send("Page.navigate", { url })
  }
  const waitForPrint = async () => {
    let printed = null
    for (let tries = 0; tries < 240 && printed === null; tries += 1) {
      await pause(500)
      printed = JSON.parse((await evaluate("JSON.stringify(window.__plantoirPrinted || null)")) ?? "null")
    }
    return printed
  }
  // The handout as the browser printed it, printed again by Chrome's own
  // printer into a PDF: the frame's document, laid out pages and all.
  const toPdf = async (html, file) => {
    await open(pageUrl)
    await pause(500)
    const tree = await send("Page.getFrameTree")
    const page = html.replace("<head>", `<head><base href="${pageUrl}">`).replace(/<script[^>]*paged[^>]*><\/script>/g, "")
    await send("Page.setDocumentContent", { frameId: tree.frameTree.frame.id, html: page })
    await evaluate("document.fonts.ready.then(() => true)")
    await evaluate("Promise.all(Array.from(document.images).map((image) => image.decode().catch(() => null))).then(() => true)")
    const pdf = await send("Page.printToPDF", { preferCSSPageSize: true, printBackground: true, marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0 })
    writeFileSync(file, Buffer.from(pdf.data, "base64"))
  }

  socket.onopen = async () => {
    await send("Emulation.setEmulatedMedia", light)
    await send("Page.enable")
    await send("Page.addScriptToEvaluateOnNewDocument", { source: PROBE })
    // The page's server may still be starting: ask until it answers (15 s),
    // rather than guessing how long to wait.
    for (let tries = 0; tries < 60; tries += 1) {
      try {
        if ((await fetch(pageUrl)).ok) break
      } catch {}
      await pause(250)
    }
    const report = {}
    const problems = []
    for (const [mode, paper] of RUNS) {
      const run = `${mode}/${paper}`
      // A fresh document for each: a change of hash alone is not a page load,
      // and Print starts on a page load.
      await open(`${pageUrl}#plantoir-print=${mode}&paper=${paper}`)
      const printed = await waitForPrint()
      if (printed === null) {
        const said = await evaluate("document.querySelector('.plantoir-print-status')?.textContent || ''")
        problems.push(`${run}: nothing was printed${said ? " - the page said: " + said : ""}`)
        continue
      }
      const here = []
      if (printed.path !== "paged") here.push(`laid out by ${printed.path ?? "nothing"}, not the print layout`)
      if (!(printed.expected > 0 && printed.found === printed.expected)) here.push(`${printed.found} of ${printed.expected} pieces laid out`)
      if (printed.overflowing !== 0) here.push(`${printed.overflowing} pieces run off their page`)
      if (printed.theme !== "light") here.push("printed from a dark page")
      if (printed.curriculum) here.push("the Curriculum connection is in the handout")
      const boxes = printed.boxes.filter((box) => !box.startsWith("example "))
      if (boxes.length > 0) here.push(`callouts printed in boxes: ${boxes.join(", ")}`)
      if (printed.icons > 0) here.push(`${printed.icons} callout icons printed`)
      if (printed.headingOnly.length > 0) here.push(`pages holding a heading alone: ${printed.headingOnly.join(", ")}`)
      const wantedWidth = paper === "landscape" ? 1056 : 816
      if (Math.abs(printed.pageWidth - wantedWidth) > 2) here.push(`pages ${printed.pageWidth} px wide, not ${wantedWidth}`)
      if (mode !== "answersOnly") {
        if (!(printed.diagrams > 0 && printed.drawn === printed.diagrams && !printed.sourceText)) here.push("a diagram printed undrawn")
        if (!printed.example || !printed.boxes.some((box) => box.startsWith("example "))) here.push("the worked example lost its box")
        // The 110-line program splits across pages: at least two pieces, each boxed.
        if (printed.code.length < 3) here.push(`${printed.code.length} pieces of code laid out`)
        if (printed.code.some((piece) => !piece.boxed || piece.filled)) here.push("a piece of code printed without its hairline box, or with a fill: " + JSON.stringify(printed.code))
      }
      if (mode !== "questionsOnly") {
        for (const number of ["2.", "3.", "5.", "a)", "b)"]) {
          if (!printed.numbers.includes(number)) here.push(`the answers have no ${number}`)
        }
      }
      const file = join(keep || work, `${mode}-${paper}.pdf`)
      await toPdf(printed.html, file)
      const paperRead = readPdf(file, mode, paper, printed)
      here.push(...paperRead.problems)
      report[run] = { pages: paperRead.pages, laidOut: `${printed.found}/${printed.expected}` }
      for (const problem of here) problems.push(`${run}: ${problem}`)
    }

    // The menu: nothing prints until a choice, in the contract's order, and
    // the paper is remembered (#499, decision 29).
    await open(pageUrl)
    for (let tries = 0; tries < 60; tries += 1) {
      await pause(250)
      if (await evaluate("document.readyState === 'complete' && !!document.querySelector('.plantoir-print-button')")) break
    }
    await pause(500)
    const menu = JSON.parse(await evaluate(`(() => {
      const box = document.querySelector(".plantoir-print")
      const order = Array.from(box.querySelectorAll(".plantoir-print-menu input, .plantoir-print-menu button")).map((element) => element.value || element.dataset.mode)
      const shownBefore = box.querySelector("details").open
      box.querySelector("summary").click()
      return JSON.stringify({ order, shownBefore, shownAfter: box.querySelector("details").open })
    })()`))
    await pause(1500)
    const printedOnOpen = await evaluate("!!window.__plantoirPrinted")
    await evaluate(`(() => {
      const box = document.querySelector(".plantoir-print")
      const landscape = box.querySelector('input[value="landscape"]')
      landscape.checked = true
      landscape.dispatchEvent(new Event("change", { bubbles: true }))
      box.querySelector('button[data-mode="questionsOnly"]').click()
      return true
    })()`)
    const chosen = await waitForPrint()
    await open(pageUrl)
    await pause(2500)
    const remembered = await evaluate("document.querySelector('.plantoir-print input[value=\"landscape\"]')?.checked === true")
    await evaluate("localStorage.removeItem('plantoir-print-paper'); true")
    report.menu = { order: menu.order, printedOnOpen, chosenPageWidth: chosen?.pageWidth ?? null, remembered }
    if (menu.order.join(",") !== "portrait,landscape,questionsOnly,answersOnly,withAnswersAtTheEnd") problems.push(`menu order ${menu.order.join(",")}`)
    if (menu.shownBefore || !menu.shownAfter) problems.push("Print did not open the menu")
    if (printedOnOpen) problems.push("opening the menu printed")
    if (!chosen || Math.abs(chosen.pageWidth - 1056) > 2) problems.push("choosing Landscape then Questions only did not print landscape")
    if (!remembered) problems.push("the paper chosen was not remembered")

    // ⌘P: the browser lays the page out itself, by the print stylesheet.
    const printedText = async (url) => {
      await send("Emulation.setEmulatedMedia", { media: "", ...light })
      await open(url)
      let onScreen = ""
      for (let tries = 0; tries < 60; tries += 1) {
        await pause(250)
        onScreen = (await evaluate(
          "document.readyState === 'complete' && document.querySelector('.center article') ? document.querySelector('.center article').innerText : ''",
        )) ?? ""
        if (onScreen !== "") break
      }
      // One more beat, for the page's own scripts to have run on load.
      await pause(500)
      await send("Emulation.setEmulatedMedia", { media: "print", ...light })
      const onPaper = (await evaluate("document.querySelector('.center article').innerText")) ?? ""
      return { onScreen, onPaper }
    }
    const worksheet = await printedText(pageUrl)
    // Orientation is the dialog's under ⌘P (printablePages.paper): asked for
    // landscape, Chrome's printer must give landscape, which it does only
    // when the page's own box names no size.
    const sizes = {}
    for (const landscape of [false, true]) {
      const pdf = await send("Page.printToPDF", { landscape, preferCSSPageSize: true, printBackground: false })
      const file = join(work, `commandP-${landscape ? "landscape" : "portrait"}.pdf`)
      writeFileSync(file, Buffer.from(pdf.data, "base64"))
      sizes[landscape ? "landscape" : "portrait"] = (/Page size:\s+([\d.]+ x [\d.]+)/.exec(poppler("pdfinfo", [file])) || [])[1]
    }
    await send("Emulation.setEmulatedMedia", { media: "", ...light })
    report.commandP = {
      curriculumOnScreen: CURRICULUM.test(worksheet.onScreen),
      curriculumOnPaper: CURRICULUM.test(worksheet.onPaper),
      practiceOnPaper: /(^|\n)Practice(\n|$)/.test(worksheet.onPaper),
      footnoteOnPaper: FOOTNOTE.test(worksheet.onPaper),
      sizes,
    }
    if (!(report.commandP.curriculumOnScreen && !report.commandP.curriculumOnPaper &&
      report.commandP.practiceOnPaper && report.commandP.footnoteOnPaper)) problems.push("⌘P printed the Curriculum connection or left out what should print")
    if (sizes.portrait !== "612 x 792" || sizes.landscape !== "792 x 612") problems.push(`⌘P paper ${JSON.stringify(sizes)}: the page decided the orientation, not the dialog`)
    if (plainUrl) {
      const plain = await printedText(plainUrl)
      report.notOptedCommandP = { curriculumOnPaper: CURRICULUM.test(plain.onPaper) }
      if (!report.notOptedCommandP.curriculumOnPaper) problems.push("the page that did not opt in no longer prints its Curriculum connection under ⌘P")
    }
    clearTimeout(timer)
    const good = problems.length === 0
    finish(good ? 0 : 1, (good ? "OK: " : "FAIL: " + problems.slice(0, 40).join("\n  ") + "\n") + JSON.stringify(report))
  }
}
