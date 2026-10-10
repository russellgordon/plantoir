// Draws a site's graphs in headless Chrome for Testing on pages whose own
// ids would answer the names function-plot reads as its file runs (#502,
// contracts/shared-rules.json → figureFences.pageIds).
//
// A browser makes every element with an id a property of window, so a
// heading "Math" (id="math") answered `window.math`, which function-plot
// 1.25.4 takes for its evaluator, and a heading "Exports" answered
// `window.exports`, where it puts itself. Either made every graph fail - on
// that page and, because the engine is loaded once and kept across Quartz's
// page changes, on every page with a graph visited after it. Three steps:
//
// 1. the page with a `# Math` heading opened first: its id is there, every
//    graph's curve is drawn (an SVG path.line with a real path in it), no
//    graph says it could not be drawn, and window.math is the heading again;
// 2. Quartz's own page change (window.spaNavigate) from there to a second
//    page with graphs: every graph there drawn too;
// 3. the page with an `# Exports` heading opened first in a fresh load: its
//    id is there and every graph is drawn.
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/graphs_draw.mjs <chrome> <math page url> <second page url> <exports page url>

import { spawn } from "node:child_process"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const [chromePath, mathUrl, secondUrl, exportsUrl] = process.argv.slice(2)
if (!chromePath || !mathUrl || !secondUrl || !exportsUrl) {
  console.error("usage: node graphs_draw.mjs <chrome> <math page> <second page> <exports page>")
  process.exit(2)
}

// A drawn curve's path is thousands of characters; an empty or one-segment
// path is not a graph.
const DRAWN_PATH = 100

const work = mkdtempSync(join(tmpdir(), "plantoir-graphs-check-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1512,900",
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

const timer = setTimeout(() => finish(1, "FAIL: the graphs were not checked within 120 s"), 120000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// Every graph on the page brought into view (each is drawn when a tenth of
// it is seen), then waited for: drawn, or saying why not.
const GRAPHS = `
(async () => {
  const graphs = Array.from(document.querySelectorAll("figure.pl-functionplot:not(.pl-figure-failed)"))
  const settled = (figure) => figure.classList.contains("pl-plot-drawn") || figure.querySelector(":scope > .pl-figure-message") !== null
  for (let tries = 0; tries < 40; tries += 1) {
    for (const figure of graphs) if (!settled(figure)) figure.scrollIntoView({ block: "center" })
    if (graphs.every(settled)) break
    await new Promise((resolve) => setTimeout(resolve, 250))
  }
  const results = []
  for (const figure of graphs) {
    let longest = 0
    for (const path of figure.querySelectorAll(".pl-plot svg path.line")) longest = Math.max(longest, (path.getAttribute("d") || "").length)
    const message = figure.querySelector(":scope > .pl-figure-message")
    results.push({ path: longest, says: message ? message.textContent : null })
  }
  return { page: location.pathname, graphs: results }
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
    await send("Page.navigate", { url })
    for (let tries = 0; tries < 60; tries += 1) {
      await pause(250)
      if ((await evaluate("document.readyState")) === "complete") return true
    }
    return false
  }
  const problems = []
  const report = []
  // What one page showed, against what it must.
  const judge = (step, seen, idWanted, idState) => {
    report.push({ step, ...seen, id: idState })
    if (!seen || seen.graphs.length === 0) {
      problems.push(`${step}: no graph on the page to draw - the check would prove nothing`)
      return
    }
    for (const [index, graph] of seen.graphs.entries()) {
      if (graph.says !== null) problems.push(`${step}: graph ${index + 1} says "${graph.says}"`)
      else if (graph.path < DRAWN_PATH) problems.push(`${step}: graph ${index + 1} has no curve (path of ${graph.path} characters)`)
    }
    if (idWanted && idState !== "the heading") problems.push(`${step}: window.${idWanted} is ${idState}, not the page's heading - ${idState === "missing" ? "the fixture no longer has the id, so the check would prove nothing" : "the page's ids were not given back"}`)
  }
  const idState = (name) => `(() => { const element = document.getElementById(${JSON.stringify(name)}); if (element === null) return "missing"; return window[${JSON.stringify(name)}] === element ? "the heading" : String(window[${JSON.stringify(name)}]) })()`

  socket.onopen = async () => {
    await send("Page.enable")
    // 1. The Math page, opened first.
    if (!(await open(mathUrl))) return finish(1, "FAIL: the page did not load " + mathUrl)
    judge("the page with a Math heading, opened first", await evaluate(GRAPHS), "math", await evaluate(idState("math")))
    // 2. Quartz's page change from there.
    const changed = await evaluate(`(async () => {
      if (typeof window.spaNavigate !== "function") return false
      const arrived = new Promise((resolve) => document.addEventListener("nav", () => resolve(true), { once: true }))
      window.spaNavigate(new URL(${JSON.stringify(secondUrl)}))
      return await Promise.race([arrived, new Promise((resolve) => setTimeout(() => resolve(false), 15000))])
    })()`)
    if (!changed) problems.push("the page change to the second page did not happen (window.spaNavigate)")
    await pause(500)
    judge("the second page, reached by the site's own page change from it", await evaluate(GRAPHS), null, null)
    // 3. The Exports page, opened first in a fresh load.
    if (!(await open(exportsUrl))) return finish(1, "FAIL: the page did not load " + exportsUrl)
    judge("the page with an Exports heading, opened first", await evaluate(GRAPHS), "exports", await evaluate(idState("exports")))
    clearTimeout(timer)
    const good = problems.length === 0
    finish(good ? 0 : 1, (good ? "OK: " : "FAIL: " + problems.join("\n  ") + "\n") + JSON.stringify(report))
  }
}
