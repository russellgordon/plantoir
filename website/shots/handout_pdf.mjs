// Prints one printable page's handout to a PDF, the way a teacher's Print
// button does, for the "print" picture on plantoir.app (DECISIONS 35, v1.7.0).
//
// It opens `<page>#plantoir-print=<mode>&paper=<paper>` (the address
// Plantoir's preview hands a browser) in headless Chrome for Testing, catches
// the handout at the moment the page prints it, and prints that handout with
// Chrome's own printer. The same mechanism as browser-checks/print_handout.mjs,
// which CHECKS a fixture; this one only keeps the paper, so a picture of the
// handout is a picture of what printing really produced.
//
//   node website/shots/handout_pdf.mjs <chrome binary> <page url> <output.pdf> [mode] [paper]
//
// mode: questionsOnly (default), answersOnly or withAnswersAtTheEnd;
// paper: portrait (default) or landscape. No packages: Node 22's own
// WebSocket speaks to Chrome directly.

import { spawn } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const [chromePath, pageUrl, output, mode = "questionsOnly", paper = "portrait"] = process.argv.slice(2)
if (!chromePath || !pageUrl || !output) {
  console.error("usage: node handout_pdf.mjs <chrome> <page url> <output.pdf> [mode] [paper]")
  process.exit(2)
}

// The page lays the handout out in a frame and calls its print(); the probe
// keeps that frame's finished document instead of opening a print dialog.
const PROBE = `
(() => {
  const watch = new MutationObserver((changes) => {
    for (const change of changes) {
      for (const node of change.addedNodes) {
        if (node.tagName !== "IFRAME") continue
        node.contentWindow.print = () => {
          const frame = node.contentDocument
          window.__plantoirPrinted = {
            html: frame.documentElement.outerHTML,
            path: frame.documentElement.getAttribute("data-plantoir-print-path"),
            pages: frame.querySelectorAll(".pagedjs_page").length,
          }
        }
      }
    }
  })
  watch.observe(document, { childList: true, subtree: true })
})()
`

const work = mkdtempSync(join(tmpdir(), "plantoir-handout-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
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

setTimeout(() => finish(1, "FAIL: the handout was not printed within 180 s"), 180000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

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
  const open = async (url) => {
    await send("Page.navigate", { url: "about:blank" })
    await send("Page.navigate", { url })
  }

  socket.onopen = async () => {
    // Paper is light whatever the reader's theme.
    await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] })
    await send("Page.enable")
    await send("Page.addScriptToEvaluateOnNewDocument", { source: PROBE })
    await open(`${pageUrl}#plantoir-print=${mode}&paper=${paper}`)
    let printed = null
    for (let tries = 0; tries < 240 && printed === null; tries += 1) {
      await pause(500)
      printed = JSON.parse((await evaluate("JSON.stringify(window.__plantoirPrinted || null)")) ?? "null")
    }
    if (printed === null) {
      const said = (await evaluate("document.querySelector('.plantoir-print-status')?.textContent || ''")) ?? ""
      finish(1, `FAIL: nothing was printed${said ? " - the page said: " + said : ""}`)
      return
    }
    if (printed.path !== "paged") {
      finish(1, `FAIL: the handout was laid out by ${printed.path ?? "nothing"}, not the print layout`)
      return
    }
    // The handout as the page printed it, printed again by Chrome's own
    // printer: the frame's document, laid out pages and all.
    await open(pageUrl)
    await pause(500)
    const tree = await send("Page.getFrameTree")
    const page = printed.html.replace("<head>", `<head><base href="${pageUrl}">`).replace(/<script[^>]*paged[^>]*><\/script>/g, "")
    await send("Page.setDocumentContent", { frameId: tree.frameTree.frame.id, html: page })
    await evaluate("document.fonts.ready.then(() => true)")
    await evaluate("Promise.all(Array.from(document.images).map((image) => image.decode().catch(() => null))).then(() => true)")
    const pdf = await send("Page.printToPDF", { preferCSSPageSize: true, printBackground: true, marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0 })
    writeFileSync(output, Buffer.from(pdf.data, "base64"))
    finish(0, `printed ${mode} on ${paper} paper: ${printed.pages} page(s) -> ${output}`)
  }
}
