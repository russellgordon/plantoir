// My Progress (#545) in headless Chrome for Testing, the way a student uses
// it, against a server this check starts itself
// (contracts/shared-rules.json -> myProgress).
//
// On the verify fixture's `Progress Fixture` (three items under its success
// criteria, linked from `Unit 1, Day 2`) and the section's My Progress page.
// The section may hold other pages with success criteria - a real course
// has many - so every assertion is on the fixture's OWN row, by its page
// name, and every total is worked out from the manifest the site serves and
// the ticks in the browser, never assumed (the director's ruling, 2026-10-19):
//
//  1. the sidebar's second entry is My Progress, directly under All Classes;
//     Key Links links it once, as its first bullet;
//  2. on a fresh profile the fixture's row reads 0 / 3 under "Unit 1, Day 2",
//     in the "Unit 1" table, every table closed, the hint line shown, no
//     box anywhere on the page (read-only), and the totals agree with the
//     manifest;
//  3. tick two of the fixture's boxes with the mouse, go to My Progress by
//     the site's own navigation: 2 / 3, totals agreeing;
//  4. reload: still 2 / 3;
//  5. untick one on the fixture, go Back: 1 / 3;
//  6. the site's data cleared (a fresh profile for this site): 0 / 3;
//  7. nothing reported to the console.
//
// Kept OUT of scripts/ for the reason task_boxes.mjs is: it needs a browser
// on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/my_progress.mjs <chrome> <site folder>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!chromePath || !siteFolder) {
  console.error("usage: node my_progress.mjs <chrome> <site folder>")
  process.exit(2)
}

const RULES = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).myProgress
const WORDS = RULES.words
const FIXTURE = "Progress Fixture"
const FIXTURE_SLUG = "Progress-Fixture"
const FIXTURE_CLASS = "Unit 1, Day 2"
const FIXTURE_UNIT = "Unit 1"
const countOf = (done, total) => WORDS.count.replace("{done}", String(done)).replace("{total}", String(total))

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".svg": "image/svg+xml", ".png": "image/png",
  ".ico": "image/x-icon", ".woff2": "font/woff2", ".xml": "application/xml", ".txt": "text/plain",
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
      try {
        statSync(file + ".html")
        file = file + ".html"
      } catch {
        response.writeHead(404).end("not found")
        return
      }
    }
    try {
      const body = readFileSync(file)
      response.writeHead(200, { "Content-Type": TYPES[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-cache" })
      response.end(request.method === "HEAD" ? undefined : body)
    } catch {
      response.writeHead(404).end("not found")
    }
  })
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port }))
  })
}

const work = mkdtempSync(join(tmpdir(), "plantoir-my-progress-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1280,900",
  "--use-mock-keychain", "--password-store=basic",
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows", "--hide-scrollbars", "--mute-audio",
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })

let siteServer = null
function finish(code, message) {
  console.log(message)
  siteServer?.server.close()
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}
setTimeout(() => finish(1, "FAIL: My Progress was not checked within 180 s"), 180000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// What the page shows, read in the page: the fixture's row and the class and
// table it sits in, every table's summary, the totals, and whether the
// manifest's numbers, with this browser's ticks, give the same totals.
const READ = `(async () => {
  const holder = document.querySelector("[data-plantoir-progress]")
  if (!holder) return { holder: false }
  const tables = []
  for (const details of holder.querySelectorAll("details.plantoir-progress-unit")) {
    const spans = details.querySelectorAll(":scope > summary > span")
    tables.push({ label: spans[0]?.textContent, count: spans[1]?.textContent, open: details.open })
  }
  let row = null
  for (const link of holder.querySelectorAll("tr.plantoir-progress-page a")) {
    if (link.textContent !== ${JSON.stringify(FIXTURE)}) continue
    const line = link.closest("tr")
    let classRow = line.previousElementSibling
    while (classRow && !classRow.classList.contains("plantoir-progress-class")) classRow = classRow.previousElementSibling
    const unit = line.closest("details")?.querySelector(":scope > summary > span")?.textContent
    row = { count: line.querySelector(".plantoir-progress-count")?.textContent, under: classRow?.textContent ?? null,
            unit, href: new URL(link.href).pathname }
  }
  const totals = []
  for (const item of holder.querySelectorAll(".plantoir-progress-totals li")) {
    const spans = item.querySelectorAll("span")
    totals.push({ label: spans[0]?.textContent, count: spans[1]?.textContent })
  }
  const manifest = await (await fetch("/progress-manifest.json", { cache: "no-cache" })).json()
  const expected = { overall: [0, 0] }
  const add = (label, page) => {
    let done = 0
    for (const item of page.items) {
      const value = localStorage.getItem("plantoir:task:/:" + page.slug + ":" + item.id)
      if (value === "1" || (value === null && item.checked)) done += 1
    }
    expected[label] = expected[label] ?? [0, 0]
    expected[label][0] += done
    expected[label][1] += page.items.length
    expected.overall[0] += done
    expected.overall[1] += page.items.length
  }
  for (const unit of manifest.units) for (const known of unit.classes) for (const page of known.pages) add(unit.label, page)
  for (const page of manifest.other.pages) add(manifest.other.label, page)
  return { holder: true, tables, row, totals, expected, boxes: holder.querySelectorAll("input").length,
           hint: holder.querySelector(".plantoir-progress-hint") !== null }
})()`

let buffered = ""
chrome.stderr.on("data", (chunk) => {
  connect(chunk).catch((error) => finish(1, "FAIL: could not drive the browser: " + (error?.stack ?? error)))
})

async function connect(chunk) {
  if (buffered === null) return
  buffered += chunk.toString()
  const found = /DevTools listening on (ws:\/\/[^\s]+)/.exec(buffered)
  if (!found) return
  buffered = null
  const devtools = new URL(found[1]).port
  const created = await (await fetch(`http://127.0.0.1:${devtools}/json/new?about:blank`, { method: "PUT" })).json()
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
    if (message.method === "Runtime.exceptionThrown") {
      consoleErrors.push(message.params.exceptionDetails?.exception?.description ?? message.params.exceptionDetails?.text)
    }
    if (message.method === "Runtime.consoleAPICalled" && message.params.type === "error") {
      consoleErrors.push(message.params.args.map((arg) => arg.value ?? arg.description).join(" "))
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    if (answer?.exceptionDetails) throw new Error(JSON.stringify(answer.exceptionDetails).slice(0, 400))
    return answer?.result?.value
  }
  const waitForTable = async () => {
    for (let tries = 0; tries < 40; tries += 1) {
      if (await evaluate("document.querySelector('[data-plantoir-progress] .plantoir-progress-totals') !== null")) return true
      await pause(150)
    }
    return false
  }
  const open = async (url) => {
    await send("Page.navigate", { url })
    for (let tries = 0; tries < 80; tries += 1) {
      await pause(250)
      if ((await evaluate("document.readyState")) === "complete") {
        await pause(400)
        return true
      }
    }
    return false
  }
  const go = async (url) => {
    await evaluate(`window.spaNavigate(new URL(${JSON.stringify(url)}))`)
    await pause(700)
  }
  const clickBox = async (index) => {
    const point = await evaluate(`(() => {
      const box = document.querySelectorAll("input.plantoir-task")[${index}]
      box.scrollIntoView({ block: "center", behavior: "instant" })
      const area = box.getBoundingClientRect()
      return { x: area.left + area.width / 2, y: area.top + area.height / 2 }
    })()`)
    for (const type of ["mousePressed", "mouseReleased"]) {
      await send("Input.dispatchMouseEvent", { type, x: point.x, y: point.y, button: "left", clickCount: 1 })
    }
    await pause(150)
  }
  const problems = []
  const expect = (what, ok, detail) => {
    if (!ok) problems.push(`${what}${detail === undefined ? "" : ": " + JSON.stringify(detail).slice(0, 500)}`)
  }
  // The fixture's row, and every total the page shows against the manifest.
  const checkPage = async (when, done) => {
    if (!(await waitForTable())) {
      expect(`${when}: My Progress drew its totals`, false)
      return null
    }
    const seen = await evaluate(READ)
    expect(`${when}: the fixture's row reads ${countOf(done, 3)} under ${FIXTURE_CLASS} in ${FIXTURE_UNIT}`,
      seen.row !== null && seen.row.count === countOf(done, 3) && seen.row.under === FIXTURE_CLASS && seen.row.unit === FIXTURE_UNIT
        && seen.row.href === "/" + FIXTURE_SLUG, seen.row)
    const overall = seen.totals[0]
    expect(`${when}: the overall total is the manifest's with this browser's ticks`,
      overall?.label === WORDS.overall && overall.count === countOf(...seen.expected.overall), { overall, expected: seen.expected.overall })
    for (const line of seen.totals.slice(1)) {
      const want = seen.expected[line.label]
      expect(`${when}: ${line.label}'s total is the manifest's`, want !== undefined && line.count === countOf(...want), { line, want })
    }
    expect(`${when}: every table is closed`, seen.tables.length > 0 && seen.tables.every((table) => table.open === false), seen.tables)
    expect(`${when}: no box can be ticked here`, seen.boxes === 0, seen.boxes)
    return seen
  }

  socket.onopen = async () => {
    try {
      await send("Page.enable")
      await send("Runtime.enable")
      siteServer = await serve()
      const base = `http://127.0.0.1:${siteServer.port}`
      const fixture = `${base}/${FIXTURE_SLUG}`
      const progress = `${base}/My-Progress`

      // 1. The sidebar and Key Links.
      if (!(await open(fixture))) return finish(1, "FAIL: the fixture did not load")
      const sidebar = await evaluate(`Array.from(document.querySelectorAll(".explorer .explorer-ul > li")).slice(0, 3)
        .map((item) => (item.querySelector(".folder-title, a")?.textContent ?? "").trim())`)
      expect("the sidebar's second entry is My Progress, directly under All Classes",
        sidebar[0] === "All Classes" && sidebar[1] === WORDS.title, sidebar)
      expect("the fixture's boxes are tickable", (await evaluate("document.querySelectorAll('input.plantoir-task').length")) === 5)
      await go(`${base}/Key-Links`)
      const keyLinks = await evaluate(`(() => {
        const links = Array.from(document.querySelectorAll("article a.internal")).filter((a) => new URL(a.href).pathname === "/My-Progress")
        const first = document.querySelector("article li a.internal")
        return { links: links.length, first: first ? new URL(first.href).pathname : null }
      })()`)
      expect("Key Links links My Progress once, as its first bullet", keyLinks.links === 1 && keyLinks.first === "/My-Progress", keyLinks)

      // 2. A fresh profile.
      await go(progress)
      const fresh = await checkPage("a fresh profile", 0)
      expect("a fresh profile: the hint line is shown", fresh?.hint === true)

      // 3. Two ticks on the fixture (its second and third boxes are the
      // first two counted ones: the first box is before any heading).
      await go(fixture)
      await clickBox(1)
      await clickBox(2)
      const stored = await evaluate(`Object.keys(localStorage).filter((key) => key.startsWith("plantoir:task:/:${FIXTURE_SLUG}:")).length`)
      expect("two ticks were kept", stored === 2, stored)
      await go(progress)
      const ticked = await checkPage("after two ticks", 2)
      expect("after two ticks: no hint line", ticked?.hint === false)

      // 4. A reload.
      await open(progress)
      await checkPage("after a reload", 2)

      // 5. Untick one, then Back.
      await go(fixture)
      await clickBox(2)
      await evaluate("history.back()")
      await pause(900)
      await checkPage("after an untick and Back", 1)

      // 6. The site's data cleared: a fresh profile for this site.
      await send("Storage.clearDataForOrigin", { origin: base, storageTypes: "local_storage" })
      await open(progress)
      await checkPage("after the site's data was cleared", 0)

      expect("nothing was reported to the console", consoleErrors.length === 0, consoleErrors)
      if (problems.length > 0) {
        return finish(1, "FAIL: " + problems.join("\nFAIL: "))
      }
      finish(0, `OK: My Progress second in the sidebar and first in Key Links; ${FIXTURE}'s row under ${FIXTURE_CLASS} read 0 / 3 fresh, 2 / 3 after two ticks and after a reload, 1 / 3 after an untick and Back, 0 / 3 with the site's data cleared; every total agreed with the manifest (${fresh?.totals?.length ?? 0} totals); read-only, every table closed`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
