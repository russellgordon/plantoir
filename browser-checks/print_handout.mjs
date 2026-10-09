// Prints a printable page the way Plantoir's preview hands it to a browser
// (#454): opens `<page>#plantoir-print=withAnswersAtTheEnd` in a LIGHT page in
// headless Chrome, catches the handout at the moment it is printed, and checks
// every Mermaid diagram in it was DRAWN, not left as its source text.
//
// Why it exists (#454 implementation review B1): opened that way, Print
// starts at the first page load, before Quartz has drawn the diagrams, and in
// light mode nothing waited for them - the verify fixture printed
// "flowchart LR / A[Expand] --> …" in Safari and 0 of 5 diagrams in Chrome.
//
// It also checks the page's Curriculum connection is never printed (#498): the
// fixture carries one (its words and a transcluded expectation) between two
// questions, and it must be on the page on screen, in none of the three
// handouts, and not under ⌘P - with the heading after it still printed. And
// the same block on the page that did NOT opt in must still print under ⌘P,
// as every page's did before.
//
// Kept OUT of scripts/ on purpose: it needs a browser on the Mac, not the
// image, and anything in scripts/ is hashed into the image and shipped.
// verify.sh runs it when a Chrome for Testing is found and says SKIPPED when
// not. No packages: Node 22's own WebSocket speaks to Chrome directly.
//
//   node browser-checks/print_handout.mjs <chrome binary> <page url> [<not-opted page url>]

import { spawn } from "node:child_process"
import { mkdtempSync, rmSync } from "node:fs"
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
const MODES = ["withAnswersAtTheEnd", "questionsOnly", "answersOnly"]

const PROBE = `
(() => {
  const watch = new MutationObserver((changes) => {
    for (const change of changes) {
      for (const node of change.addedNodes) {
        if (node.tagName !== "IFRAME") continue
        node.contentWindow.print = () => {
          const frame = node.contentDocument
          const headings = []
          for (const heading of frame.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
            headings.push((heading.textContent || "").trim())
          }
          window.__plantoirPrinted = {
            diagrams: frame.querySelectorAll("code.mermaid").length,
            drawn: frame.querySelectorAll("code.mermaid > svg").length,
            pages: frame.querySelectorAll(".pagedjs_page").length,
            sourceText: /-->/.test(frame.body.textContent || ""),
            theme: document.documentElement.getAttribute("saved-theme"),
            curriculum: ${CURRICULUM}.test(frame.body.textContent || ""),
            practice: headings.includes("Practice"),
          }
        }
      }
    }
  })
  watch.observe(document, { childList: true, subtree: true })
})()
`

const profile = mkdtempSync(join(tmpdir(), "plantoir-print-check-"))
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
    rmSync(profile, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}

const timer = setTimeout(() => finish(1, "FAIL: the handouts and ⌘P were not all printed within 240 s"), 240000)

let buffered = ""
chrome.stderr.on("data", (chunk) => {
  connect(chunk).catch((error) => finish(1, "FAIL: could not drive the browser: " + error))
})

async function connect(chunk) {
  buffered += chunk.toString()
  const found = /DevTools listening on (ws:\/\/[^\s]+)/.exec(buffered)
  if (!found || buffered === null) return
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
      waiting.get(message.id)(message.result)
      waiting.delete(message.id)
    }
  }
  socket.onopen = async () => {
    await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] })
    await send("Page.enable")
    await send("Page.addScriptToEvaluateOnNewDocument", { source: PROBE })
    // The page's server may still be starting: ask until it answers (15 s),
    // rather than guessing how long to wait.
    for (let tries = 0; tries < 60; tries += 1) {
      try {
        if ((await fetch(pageUrl)).ok) break
      } catch {}
      await new Promise((resolve) => setTimeout(resolve, 250))
    }
    const evaluate = async (expression) => {
      const answer = await send("Runtime.evaluate", { expression, returnByValue: true })
      return answer?.result?.value
    }
    const report = {}
    let good = true
    for (const mode of MODES) {
      // A fresh document for each mode: a change of hash alone is not a page
      // load, and Print starts on a page load.
      await send("Page.navigate", { url: "about:blank" })
      await send("Page.navigate", { url: pageUrl + "#plantoir-print=" + mode })
      let printed = null
      for (let tries = 0; tries < 110 && printed === null; tries += 1) {
        await new Promise((resolve) => setTimeout(resolve, 500))
        printed = JSON.parse((await evaluate("JSON.stringify(window.__plantoirPrinted || null)")) ?? "null")
      }
      report[mode] = printed
      if (printed === null) {
        good = false
        continue
      }
      // The diagram is on the worksheet, so only the modes that print it are
      // asked for it; answersOnly prints the title and the answers alone.
      if (mode !== "answersOnly") {
        good = good && printed.diagrams > 0 && printed.drawn === printed.diagrams && !printed.sourceText &&
          printed.practice
      }
      good = good && printed.pages > 0 && printed.theme === "light" && !printed.curriculum
    }
    // ⌘P: the browser lays the page out itself, by the print stylesheet. What
    // a printed page carries is the article's text as the print media shows it.
    const printedText = async (url) => {
      await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
      await send("Page.navigate", { url: "about:blank" })
      await send("Page.navigate", { url })
      let onScreen = ""
      for (let tries = 0; tries < 60; tries += 1) {
        await new Promise((resolve) => setTimeout(resolve, 250))
        onScreen = (await evaluate(
          "document.readyState === 'complete' && document.querySelector('.center article') ? document.querySelector('.center article').innerText : ''",
        )) ?? ""
        if (onScreen !== "") break
      }
      // One more beat, for the page's own scripts to have run on load.
      await new Promise((resolve) => setTimeout(resolve, 500))
      await send("Emulation.setEmulatedMedia", { media: "print", features: [{ name: "prefers-color-scheme", value: "light" }] })
      const onPaper = (await evaluate("document.querySelector('.center article').innerText")) ?? ""
      return { onScreen, onPaper }
    }
    const worksheet = await printedText(pageUrl)
    report.commandP = {
      curriculumOnScreen: CURRICULUM.test(worksheet.onScreen),
      curriculumOnPaper: CURRICULUM.test(worksheet.onPaper),
      practiceOnPaper: /(^|\n)Practice(\n|$)/.test(worksheet.onPaper),
    }
    good = good && report.commandP.curriculumOnScreen && !report.commandP.curriculumOnPaper &&
      report.commandP.practiceOnPaper
    if (plainUrl) {
      const plain = await printedText(plainUrl)
      report.notOptedCommandP = { curriculumOnPaper: CURRICULUM.test(plain.onPaper) }
      good = good && report.notOptedCommandP.curriculumOnPaper
    }
    clearTimeout(timer)
    finish(good ? 0 : 1, (good ? "OK: " : "FAIL: ") + JSON.stringify(report))
  }
}
