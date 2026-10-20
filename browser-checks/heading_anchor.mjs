// A link to a heading lands on it (#604), in headless Chrome for Testing,
// against a server this check starts itself.
//
// verify.sh's Anchor Fixture has eight runnable blocks ABOVE `## Test of
// success`. The browser scrolls to `#test-of-success` before their editors
// take their size; Chrome then re-anchors to the fragment by itself, Safari
// and Arc do not. So Chrome's own re-anchoring is switched off here
// (`overflow-anchor: none`, which Safari has never had), and the page's own
// script (headingAnchor.inline.ts) must bring the heading back:
//
//  1. loaded with the hash, once every editor is mounted and the page's
//     height has held for a second: the heading's top is inside the window,
//     near its top;
//  2. loaded again, and the reader scrolls back up with the wheel as soon as
//     it loads: the page leaves them where they scrolled (no yank back);
//  3. nothing reported to the console.
//
//   node browser-checks/heading_anchor.mjs <chrome> <site folder>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!chromePath || !siteFolder) {
  console.error("usage: node heading_anchor.mjs <chrome> <site folder>")
  process.exit(2)
}
const PAGE = "/Anchor-Fixture#test-of-success"
const HEADING = "test-of-success"
const BLOCKS = 8
const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".svg": "image/svg+xml", ".png": "image/png",
  ".woff2": "font/woff2", ".ttf": "font/ttf", ".woff": "font/woff",
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
      response.writeHead(200, { "Content-Type": TYPES[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-cache" })
      response.end(body)
    } catch {
      response.writeHead(404).end("not found")
    }
  })
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)))
}

const work = mkdtempSync(join(tmpdir(), "plantoir-heading-anchor-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1280,900", "--use-mock-keychain",
  "--password-store=basic", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--hide-scrollbars", "--mute-audio", "about:blank",
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
setTimeout(() => finish(1, "FAIL: the heading anchor was not checked within 120 s"), 120000)
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
  const port = new URL(found[1]).port
  const created = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" })).json()
  const socket = new WebSocket(created.webSocketDebuggerUrl)
  let id = 0
  const waiting = new Map()
  const consoleErrors = []
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
    if (message.method === "Runtime.exceptionThrown") consoleErrors.push(message.params.exceptionDetails?.exception?.description ?? message.params.exceptionDetails?.text)
    if (message.method === "Runtime.consoleAPICalled" && message.params.type === "error") {
      consoleErrors.push(message.params.args.map((arg) => arg.value ?? arg.description).join(" "))
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    if (answer?.exceptionDetails) throw new Error(JSON.stringify(answer.exceptionDetails).slice(0, 400))
    return answer?.result?.value
  }
  // Settled: every editor mounted, the faces ready and the page's height
  // unchanged for a second (read four times, 250 ms apart).
  const settle = async () => {
    let last = -1
    let steady = 0
    for (let tries = 0; tries < 120; tries += 1) {
      await pause(250)
      const state = await evaluate(`(async () => { await document.fonts.ready; return { live: document.querySelectorAll(".plantoir-runner-live").length, height: document.documentElement.scrollHeight } })()`).catch(() => null)
      if (state === null || state.live < BLOCKS) continue
      steady = state.height === last ? steady + 1 : 0
      last = state.height
      if (steady >= 4) return true
    }
    return false
  }
  const headingTop = () => evaluate(`(() => { const h = document.getElementById(${JSON.stringify(HEADING)}); return h ? { top: Math.round(h.getBoundingClientRect().top), window: innerHeight, scrollY: Math.round(scrollY) } : null })()`)
  socket.onopen = async () => {
    try {
      await send("Page.enable")
      await send("Runtime.enable")
      // Safari and Arc have no scroll anchoring; switch Chrome's off.
      await send("Page.addScriptToEvaluateOnNewDocument", { source: `document.addEventListener("DOMContentLoaded", () => { const s = document.createElement("style"); s.textContent = "html, body, * { overflow-anchor: none !important; }"; document.head.append(s) })` })
      siteServer = await serve()
      const base = `http://127.0.0.1:${siteServer.address().port}`
      const problems = []
      // 1. Loaded with the hash.
      await send("Page.navigate", { url: base + PAGE })
      if (!(await settle())) return finish(1, "FAIL: Anchor Fixture never settled (its eight editors and its height)")
      const landed = await headingTop()
      if (landed === null || landed.top < 0 || landed.top > landed.window / 3) problems.push(`the heading is not at the top of the window once the page settled: ${JSON.stringify(landed)}`)
      // 2. The reader scrolls up as soon as it loads: left where they went.
      await send("Page.navigate", { url: "about:blank" })
      await pause(300)
      await send("Page.navigate", { url: base + PAGE })
      for (let tries = 0; tries < 40; tries += 1) {
        await pause(100)
        if ((await evaluate("document.readyState").catch(() => "")) === "complete") break
      }
      // Once the browser has scrolled to the hash and the page's scripts have
      // run (a reader cannot scroll a page that is not yet shown).
      for (let tries = 0; tries < 40; tries += 1) {
        if ((await evaluate("scrollY").catch(() => 0)) > 0) break
        await pause(50)
      }
      await pause(300)
      await send("Input.dispatchMouseEvent", { type: "mouseWheel", x: 640, y: 450, deltaX: 0, deltaY: -100000 })
      await pause(200)
      if (!(await settle())) return finish(1, "FAIL: Anchor Fixture never settled the second time")
      const stayed = await headingTop()
      if (stayed === null || stayed.scrollY > 50) problems.push(`the reader scrolled to the top and was moved again: ${JSON.stringify(stayed)}`)
      if (consoleErrors.length > 0) problems.push(`the console reported ${JSON.stringify(consoleErrors).slice(0, 300)}`)
      if (problems.length > 0) return finish(1, "FAIL: " + problems.join("\nFAIL: "))
      finish(0, `OK: the heading ${landed.top} px from the window's top once the eight editors were mounted (scrollY ${landed.scrollY}); a reader who scrolled up at once was left at scrollY ${stayed.scrollY}`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
