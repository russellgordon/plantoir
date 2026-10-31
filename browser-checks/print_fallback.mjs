// The Print button's fallback - the browser laying the handout out itself,
// when the print layout cannot be used - asked to print the way each browser
// really answers print() (#576), in headless Chrome for Testing against a
// server this check starts itself.
//
// In Safari the fallback printed nothing: "Preparing to print…", then
// nothing (measured in Safari 26.6, 3 of 3 forced runs). It called print()
// on its frame while the frame was still fetching faces and pictures; WebKit
// then returns at once, sends no print event, and prints when the frame has
// loaded - and the page had already taken the frame away. Since #576 the
// fallback waits for the frame's faces and pictures first, and the page is
// put back only once the print is known to have happened
// (contracts/shared-rules.json -> printablePages.printRequest).
//
// Chrome prints whatever state the frame is in and headless Chrome opens no
// dialog, so the frame's print() is REPLACED by a stand-in that answers the
// way a given browser does, and what the page does around it is read. The
// print layout's script is answered with a 404 (Fetch), so every case takes
// the fallback. The fixture is Discussions/Print Fallback Fixture: a
// printable page one folder down, with a table of contents, 16 code blocks
// and two pictures. Every case runs in its own browser context, at once, so
// the three that wait out the budget wait together.
//
//  A. Pictures and faces held back (1.5 s and 1 s a request): at print()
//     every picture in the frame has arrived and its faces have loaded.
//  B. A print put off, WebKit's way: print() returns with nothing sent,
//     beforeprint and afterprint come later on the PAGE's window (Safari
//     sends the frame's there). The frame is still there at beforeprint, the
//     words have gone, and the page is put back after afterprint.
//  C. A print that never comes: print() returns with nothing sent, ever.
//     The page is put back and says words.couldNotPrepare by the budget.
//  D. Pictures that never arrive: words.couldNotPrepare by the budget, and
//     print() never called.
//  E. A print put off that sends beforeprint and no afterprint: the frame
//     stays at beforeprint, the page is put back by the budget saying
//     nothing, and the button prints again when pressed.
//  F. Headless Chrome's own print(), not replaced (beforeprint on the frame
//     inside print(), no afterprint, measured): the page is put back at once
//     and says nothing. A guard, not a must-fail: the old code passed it.
//  W. The PRINT LAYOUT (not the fallback) that never finishes: once Print is
//     pressed, the site's stylesheet Paged.js asks for is never answered. The
//     budget covers that path too: words.couldNotPrepare by the budget, no
//     print(), the page put back - not "Preparing to print…" for good.
//
// A to E each FAILED on the code before #576, and W on #576's first version
// (b3c9820f9), proven by copy-and-restore of print.inline.ts, 2026-10-23
// (documentation/06-quartz-customizations.md F3).
//
//   node browser-checks/print_fallback.mjs <chrome> <site folder> [page path]

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!chromePath || !siteFolder) {
  console.error("usage: node print_fallback.mjs <chrome> <site folder>")
  process.exit(2)
}
const PAGES = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).printablePages
const WORDS = PAGES.words
const BUDGET = PAGES.printRequest.budgetMs
const PAGE = process.argv[4] || "/Discussions/Print-Fallback-Fixture.html"
const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".svg": "image/svg+xml", ".png": "image/png",
  ".woff2": "font/woff2", ".ttf": "font/ttf", ".woff": "font/woff", ".otf": "font/otf",
}

function serve() {
  const server = createServer((request, response) => {
    let path = decodeURIComponent(new URL(request.url, "http://x").pathname)
    if (path.endsWith("/")) path += "index.html"
    let file = normalize(join(siteFolder, path))
    if (!file.startsWith(normalize(siteFolder))) {
      response.writeHead(403).end()
      return
    }
    try {
      if (statSync(file).isDirectory()) file = join(file, "index.html")
    } catch {
      file = file + ".html"
    }
    try {
      const body = readFileSync(file)
      // no-cache, as a published site answers: the frame asks again for what
      // the page already has, so a held picture is held for the frame too.
      response.writeHead(200, { "Content-Type": TYPES[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-cache" })
      response.end(body)
    } catch {
      response.writeHead(404).end("not found")
    }
  })
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)))
}

// In every page before its own scripts: the frame's print() replaced by the
// case's stand-in (window.__printPlan), and what happens around it recorded.
const STAND_IN = `
(() => {
  const now = () => Math.round(performance.now())
  const record = { framesMade: 0, calls: [], atBefore: null, atAfter: null, afterAfter: null }
  window.__print = record
  const status = () => document.querySelector(".plantoir-print-status")?.textContent ?? ""
  new MutationObserver((changes) => {
    for (const change of changes) for (const node of change.addedNodes) {
      if (node.tagName !== "IFRAME") continue
      record.framesMade += 1
      const plan = window.__printPlan
      if (plan === "real") continue
      const view = node.contentWindow
      view.print = () => {
        const frame = node.contentDocument
        let pending = 0
        for (const image of frame.images) if (!image.complete || image.naturalWidth === 0) pending += 1
        record.calls.push({ at: now(), fonts: frame.fonts.status, pending, pictures: frame.images.length,
          path: frame.documentElement.getAttribute("data-plantoir-print-path"), status: status() })
        if (plan === "prints") {
          view.dispatchEvent(new Event("beforeprint"))
          view.dispatchEvent(new Event("afterprint"))
          return
        }
        if (plan === "putOff" || plan === "putOffNoAfter") {
          setTimeout(() => {
            const there = node.isConnected
            dispatchEvent(new Event("beforeprint"))
            record.atBefore = { at: now(), there, status: status() }
            if (plan === "putOffNoAfter") return
            setTimeout(() => {
              record.atAfter = { at: now(), there: node.isConnected }
              dispatchEvent(new Event("afterprint"))
              setTimeout(() => { record.afterAfter = { there: node.isConnected, status: status() } }, 100)
            }, 500)
          }, 300)
        }
        // "never": nothing is sent, ever.
      }
    }
  }).observe(document, { childList: true, subtree: true })
})()
`

const work = mkdtempSync(join(tmpdir(), "plantoir-print-fallback-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--use-mock-keychain", "--password-store=basic",
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows", "--hide-scrollbars", "--mute-audio", "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })
let siteServer = null
function finish(code, message) {
  console.log(message)
  siteServer?.close()
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}
setTimeout(() => finish(1, `FAIL: the print fallback was not checked within ${(BUDGET + 60000) / 1000} s`), BUDGET + 60000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

let buffered = ""
chrome.stderr.on("data", (chunk) => {
  run(chunk).catch((error) => finish(1, "FAIL: could not drive the browser: " + (error?.stack ?? error)))
})

async function run(chunk) {
  if (buffered === null) return
  buffered += chunk.toString()
  const found = /DevTools listening on (ws:\/\/[^\s]+)/.exec(buffered)
  if (!found) return
  buffered = null
  siteServer = await serve()
  const base = `http://127.0.0.1:${siteServer.address().port}`
  const browser = new WebSocket(found[1])
  await new Promise((resolve) => browser.addEventListener("open", resolve, { once: true }))
  let id = 0
  const waiting = new Map()
  const listeners = new Map()
  browser.addEventListener("message", (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
    } else if (message.method && listeners.has(message.sessionId)) {
      listeners.get(message.sessionId)(message)
    }
  })
  const sendOn = (sessionId) => (method, params = {}) => new Promise((resolve) => {
    id += 1
    waiting.set(id, resolve)
    browser.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }))
  })
  const toBrowser = sendOn(null)

  // One case: its own context (its own cache), its pictures and faces held
  // as `hold` says, the print layout's script refused, the page opened and
  // Questions only pressed with the stand-in `plan`.
  async function openCase(plan, hold) {
    const { browserContextId } = await toBrowser("Target.createBrowserContext", { disposeOnDetach: true })
    const { targetId } = await toBrowser("Target.createTarget", { url: "about:blank", browserContextId, width: 1280, height: 900 })
    const { sessionId } = await toBrowser("Target.attachToTarget", { targetId, flatten: true })
    const send = sendOn(sessionId)
    const evaluate = async (expression) => {
      const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
      if (answer?.exceptionDetails) throw new Error(JSON.stringify(answer.exceptionDetails).slice(0, 400))
      return answer?.result?.value
    }
    const refused = []
    let pressed = false
    listeners.set(sessionId, (message) => {
      if (message.method !== "Fetch.requestPaused") return
      const { requestId, request } = message.params
      const path = new URL(request.url).pathname
      // W: the stylesheet the print layout fetches, never answered once
      // Print is pressed (the page itself has it already).
      if (hold.layoutAfterPress && pressed && /\/index\.css$/.test(path)) return
      if (!hold.layoutAfterPress && /paged\.min\.js$/.test(path)) {
        refused.push(path)
        send("Fetch.fulfillRequest", { requestId, responseCode: 404, body: "" })
        return
      }
      const isPicture = /plantoir-hazard-[a-z]+\.png$/.test(path)
      const isFace = /\.(woff2?|otf|ttf)$/.test(path)
      const wait = isPicture ? hold.pictures : isFace ? hold.faces : 0
      if (wait === Infinity) return
      setTimeout(() => send("Fetch.continueRequest", { requestId }), wait)
    })
    await send("Fetch.enable", { patterns: [{ urlPattern: "*", requestStage: "Request" }] })
    await send("Page.enable")
    await send("Page.addScriptToEvaluateOnNewDocument", { source: STAND_IN + `;window.__printPlan = ${JSON.stringify(plan)};` })
    await send("Page.navigate", { url: base + PAGE })
    // Ready when the page's own print code has run for this page (it marks
    // <html> printable on the page change) - not on load, which a picture
    // held for ever never lets happen.
    let ready = false
    for (let tries = 0; tries < 120 && !ready; tries += 1) {
      await pause(250)
      ready = (await evaluate("document.documentElement.classList.contains('plantoir-printable') && !!document.querySelector('.plantoir-print button[data-mode=\"questionsOnly\"]')").catch(() => false)) === true
    }
    if (!ready) throw new Error(`${plan}: the fixture's Print button never appeared`)
    await pause(300)
    const press = () => { pressed = true; return evaluate(`(() => {
      window.__pressedAt = Math.round(performance.now())
      document.querySelector('.plantoir-print button[data-mode="questionsOnly"]').click()
      return window.__pressedAt
    })()`) }
    const state = () => evaluate(`({
      now: Math.round(performance.now()), pressedAt: window.__pressedAt,
      status: document.querySelector(".plantoir-print-status")?.textContent ?? "",
      frames: document.querySelectorAll("iframe").length,
      theme: document.documentElement.getAttribute("saved-theme"),
      print: window.__print,
    })`)
    return { plan, press, state, refused, close: () => toBrowser("Target.disposeBrowserContext", { browserContextId }) }
  }

  // Polls `state` until `done` says so or `limit` ms pass; the last state.
  async function until(one, done, limit) {
    const started = Date.now()
    let last = await one.state()
    while (!done(last) && Date.now() - started < limit) {
      await pause(200)
      last = await one.state()
    }
    return last
  }

  const problems = []
  const measured = []
  const expect = (label, ok, detail) => {
    if (!ok) problems.push(`${label}${detail === undefined ? "" : ": " + JSON.stringify(detail)}`)
  }
  const late = BUDGET + 3000

  async function caseA() {
    const one = await openCase("prints", { pictures: 1500, faces: 1000 })
    await one.press()
    const last = await until(one, (state) => state.print.calls.length > 0 && state.frames === 0, 15000)
    const call = last.print.calls[0]
    measured.push(`A: print() ${call ? call.at - last.pressedAt : "never"} ms after the press, fonts ${call?.fonts}, ${call?.pending}/${call?.pictures} pictures pending`)
    expect("A: the print layout's script was refused, so the fallback was used", one.refused.length > 0 && call?.path === "fallback", { refused: one.refused, call })
    expect("A: at print() every picture in the frame had arrived and its faces had loaded", !!call && call.pending === 0 && call.pictures === 2 && call.fonts === "loaded", call)
    expect("A: after a print that sent both events the page was put back at once, saying nothing", last.frames === 0 && last.status === "", last)
    await one.close()
  }

  async function caseB() {
    const one = await openCase("putOff", { pictures: 0, faces: 0 })
    await one.press()
    const last = await until(one, (state) => state.print.afterAfter !== null, 15000)
    const call = last.print.calls[0]
    measured.push(`B: frame there at beforeprint ${last.print.atBefore?.there}, after afterprint ${last.print.afterAfter?.there}`)
    expect("B: the fallback printed", call?.path === "fallback", call)
    expect("B: a print put off finds the frame still there at beforeprint, the words gone", last.print.atBefore?.there === true && last.print.atBefore?.status === "", last.print.atBefore)
    expect("B: still there at afterprint", last.print.atAfter?.there === true, last.print.atAfter)
    expect("B: put back after afterprint, saying nothing", last.print.afterAfter?.there === false && last.print.afterAfter?.status === "" && last.frames === 0, last)
    await one.close()
  }

  async function caseC() {
    const one = await openCase("never", { pictures: 0, faces: 0 })
    await one.press()
    const early = await until(one, (state) => state.print.calls.length > 0, 15000)
    await pause(1000)
    const waitingState = await one.state()
    const last = await until(one, (state) => state.frames === 0 && state.status === WORDS.couldNotPrepare, late)
    measured.push(`C: put back ${last.now - last.pressedAt} ms after the press, saying couldNotPrepare: ${last.status === WORDS.couldNotPrepare}`)
    expect("C: the fallback printed", early.print.calls[0]?.path === "fallback", early.print.calls[0])
    expect("C: a second after a print() that sent nothing, the frame is kept and the words still say preparing", waitingState.frames === 1 && waitingState.status === WORDS.preparing, waitingState)
    expect("C: a print that never comes is put back saying words.couldNotPrepare by the budget", last.frames === 0 && last.status === WORDS.couldNotPrepare && last.now - last.pressedAt <= late, last)
    await one.close()
  }

  async function caseD() {
    const one = await openCase("prints", { pictures: Infinity, faces: 0 })
    await one.press()
    const last = await until(one, (state) => state.status === WORDS.couldNotPrepare, late)
    measured.push(`D: ${last.status === WORDS.couldNotPrepare ? "couldNotPrepare " + (last.now - last.pressedAt) + " ms after the press" : "still " + JSON.stringify(last.status)}, print() called ${last.print.calls.length} times`)
    expect("D: pictures that never arrive: words.couldNotPrepare by the budget, nothing printed, the page put back",
      last.status === WORDS.couldNotPrepare && last.print.calls.length === 0 && last.frames === 0 && last.now - last.pressedAt <= late, last)
    await one.close()
  }

  async function caseE() {
    const one = await openCase("putOffNoAfter", { pictures: 0, faces: 0 })
    await one.press()
    const before = await until(one, (state) => state.print.atBefore !== null, 15000)
    const last = await until(one, (state) => state.frames === 0, late)
    measured.push(`E: frame there at beforeprint ${before.print.atBefore?.there}, put back ${last.now - last.pressedAt} ms after the press, saying ${JSON.stringify(last.status)}`)
    expect("E: the frame is still there at a late beforeprint", before.print.atBefore?.there === true, before.print.atBefore)
    expect("E: a print that began and never sent afterprint is put back by the budget, saying nothing", last.frames === 0 && last.status === "" && last.now - last.pressedAt <= late, last)
    // The button is free again: a second press reaches print() again.
    await one.press()
    const again = await until(one, (state) => state.print.calls.length >= 2, 15000)
    expect("E: the button prints again once the page is put back", again.print.calls.length >= 2, again.print.calls)
    await one.close()
  }

  async function caseF() {
    const one = await openCase("real", { pictures: 0, faces: 0 })
    await one.press()
    const last = await until(one, (state) => state.print.framesMade > 0 && state.frames === 0, 15000)
    measured.push(`F: headless Chrome's own print(): put back ${last.now - last.pressedAt} ms after the press, saying ${JSON.stringify(last.status)}`)
    expect("F: headless Chrome's own print() (beforeprint inside it, no afterprint) puts the page back at once, saying nothing",
      last.print.framesMade > 0 && last.frames === 0 && last.status === "" && last.now - last.pressedAt < 10000, last)
    await one.close()
  }

  async function caseW() {
    const one = await openCase("prints", { pictures: 0, faces: 0, layoutAfterPress: true })
    await one.press()
    const last = await until(one, (state) => state.status === WORDS.couldNotPrepare && state.frames === 0, late)
    measured.push(`W: ${last.status === WORDS.couldNotPrepare ? "couldNotPrepare " + (last.now - last.pressedAt) + " ms after the press" : "still " + JSON.stringify(last.status)}, print() called ${last.print.calls.length} times`)
    expect("W: a print layout that never finishes: words.couldNotPrepare by the budget, nothing printed, the page put back",
      last.status === WORDS.couldNotPrepare && last.print.calls.length === 0 && last.frames === 0 && last.now - last.pressedAt <= late, last)
    await one.close()
  }

  const settled = await Promise.allSettled([caseA(), caseB(), caseC(), caseD(), caseE(), caseF(), caseW()])
  for (const outcome of settled) {
    if (outcome.status === "rejected") problems.push("a case could not be run: " + (outcome.reason?.stack ?? outcome.reason))
  }
  browser.close()
  if (problems.length > 0) {
    finish(1, "FAIL: " + problems.join("\n  ") + "\n" + measured.join("; "))
  } else {
    finish(0, "OK: " + measured.join("; "))
  }
}
