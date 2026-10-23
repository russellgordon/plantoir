// KaTeX from the site itself (#494), in headless Chrome for Testing.
//
//  1. A page with maths, opened with EVERY request to anywhere but the site
//     refused (an offline classroom, a CDN that is down): the maths is set
//     in KaTeX's own face (document.fonts has KaTeX_Main loaded, and a
//     formula is drawn in it), its stylesheet came from the site, and
//     nothing was asked of cdn.jsdelivr.net.
//  2. Print after a change of page by the site's own navigation, from a
//     page at the site's top to a printable page one folder down (#455
//     review S1): Quartz keeps a stylesheet link across page changes with
//     its RELATIVE address, which then resolves one folder off - a 404. The
//     print frame must still get KaTeX's stylesheet and the site's own,
//     loaded with their rules - caught in the frame at the moment it is
//     printed, the way print_handout.mjs catches it.
//
// Kept OUT of scripts/ for the reason print_handout.mjs is. No packages:
// Node 22's own WebSocket.
//
//   node browser-checks/maths_offline.mjs <chrome> <maths page url> <top-level page url> <printable page url one folder down>

import { spawn } from "node:child_process"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const [chromePath, mathsUrl, startUrl, printableUrl] = process.argv.slice(2)
if (!chromePath || !mathsUrl || !startUrl || !printableUrl) {
  console.error("usage: node maths_offline.mjs <chrome> <maths page> <top-level page> <printable page one folder down>")
  process.exit(2)
}
const SITE = new URL(mathsUrl).origin

const work = mkdtempSync(join(tmpdir(), "plantoir-maths-check-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1280,900",
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
const timer = setTimeout(() => finish(1, "FAIL: the maths were not checked within 120 s"), 120000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const FONTS = `
(async () => {
  await document.fonts.ready
  const formula = document.querySelector(".katex .mord, .katex .mathnormal")
  if (formula) formula.getBoundingClientRect()
  await new Promise((resolve) => setTimeout(resolve, 500))
  await document.fonts.ready
  const loaded = []
  document.fonts.forEach((face) => { if (face.status === "loaded") loaded.push(face.family.replace(/["']/g, "")) })
  const sheets = Array.from(document.querySelectorAll('link[rel="stylesheet"]')).map((link) => link.sheet ? link.sheet.href : "(not loaded) " + link.getAttribute("href"))
  return {
    formulas: document.querySelectorAll(".katex").length,
    face: formula ? getComputedStyle(formula).fontFamily : null,
    loaded: Array.from(new Set(loaded)),
    katexSheets: sheets.filter((href) => href.includes("katex")),
  }
})()
`

// Catches the print frame when the page prints it, and says which of its
// stylesheets loaded.
const PROBE = `
(() => {
  window.__frameSheets = null
  const watch = new MutationObserver((changes) => {
    for (const change of changes) {
      for (const node of change.addedNodes) {
        if (node.tagName !== "IFRAME") continue
        node.contentWindow.print = () => {
          // A real print sends these (#576): the page puts itself back only once it has seen one.
          node.contentWindow.dispatchEvent(new Event("beforeprint"))
          const frame = node.contentDocument
          window.__frameSheets = Array.from(frame.querySelectorAll('link[rel="stylesheet"]')).map((link) => {
            let rules = -1
            try { rules = link.sheet ? link.sheet.cssRules.length : 0 } catch { rules = -1 }
            return { href: link.href, rules }
          })
          node.contentWindow.dispatchEvent(new Event("afterprint"))
        }
      }
    }
  })
  watch.observe(document.body, { childList: true })
  return true
})()
`

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
  const refused = []
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
      return
    }
    if (message.method === "Fetch.requestPaused") {
      const url = message.params.request.url
      if (url.startsWith(SITE) || url.startsWith("data:")) {
        send("Fetch.continueRequest", { requestId: message.params.requestId })
      } else {
        refused.push(url)
        send("Fetch.failRequest", { requestId: message.params.requestId, errorReason: "InternetDisconnected" })
      }
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    return answer?.result?.value
  }
  const open = async (url) => {
    await send("Page.navigate", { url })
    for (let tries = 0; tries < 60; tries += 1) {
      await pause(250)
      if ((await evaluate("document.readyState")) === "complete") return true
    }
    return false
  }
  const problems = []
  socket.onopen = async () => {
    await send("Page.enable")
    await send("Fetch.enable", { patterns: [{ urlPattern: "*" }] })

    // 1. Offline maths.
    if (!(await open(mathsUrl))) return finish(1, "FAIL: the page did not load " + mathsUrl)
    const fonts = await evaluate(FONTS)
    if (!fonts || fonts.formulas === 0) problems.push("the page has no formula - the check would prove nothing")
    if (!fonts?.loaded.includes("KaTeX_Main") && !fonts?.loaded.includes("KaTeX_Math")) problems.push(`KaTeX's faces did not load: ${JSON.stringify(fonts?.loaded)}`)
    if (!fonts?.face || !/KaTeX/.test(fonts.face)) problems.push(`the formula is not set in KaTeX's face: ${fonts?.face}`)
    if (!fonts || fonts.katexSheets.length !== 1 || !fonts.katexSheets[0].startsWith(SITE)) problems.push(`KaTeX's stylesheet did not come from the site: ${JSON.stringify(fonts?.katexSheets)}`)
    const toCdn = refused.filter((url) => url.includes("jsdelivr"))
    if (toCdn.length > 0) problems.push(`the page asked the CDN for ${toCdn.join(", ")}`)

    // 2. Print after a change of page, from the top to one folder down.
    if (!(await open(startUrl))) return finish(1, "FAIL: the page did not load " + startUrl)
    await evaluate(PROBE)
    const changed = await evaluate(`(async () => {
      if (typeof window.spaNavigate !== "function") return false
      const arrived = new Promise((resolve) => document.addEventListener("nav", () => resolve(true), { once: true }))
      window.spaNavigate(new URL(${JSON.stringify(printableUrl + "#plantoir-print=questionsOnly&paper=portrait")}))
      return await Promise.race([arrived, new Promise((resolve) => setTimeout(() => resolve(false), 15000))])
    })()`)
    if (!changed) problems.push("the page change to the printable page did not happen")
    let sheets = null
    for (let tries = 0; tries < 120 && sheets === null; tries += 1) {
      await pause(250)
      sheets = await evaluate("window.__frameSheets")
    }
    const relativeHref = await evaluate(`(() => { const link = document.querySelector('link[href*="katex.min.css"]'); return link ? [link.getAttribute("href"), link.href, link.sheet && link.sheet.href] : null })()`)
    if (sheets === null) {
      problems.push("the handout was never printed after the page change")
    } else {
      const katex = sheets.filter((sheet) => sheet.href.includes("katex.min.css"))
      if (katex.length !== 1 || katex[0].rules <= 0) problems.push(`the print frame did not load KaTeX's stylesheet: ${JSON.stringify(katex)}`)
      const unloaded = sheets.filter((sheet) => sheet.href.startsWith(SITE) && sheet.rules <= 0)
      if (unloaded.length > 0) problems.push(`the print frame lost the site's stylesheets: ${JSON.stringify(unloaded)}`)
    }
    clearTimeout(timer)
    const ok = problems.length === 0
    finish(ok ? 0 : 1, (ok ? "OK: " : "FAIL: " + problems.join("\n  ") + "\n")
      + JSON.stringify({ fonts, refused: refused.length, frame: sheets, preserved: relativeHref }))
  }
}
