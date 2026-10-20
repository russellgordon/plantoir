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
//  2. on a fresh profile the fixture's row reads 1 / 4 under "Unit 1, Day 2"
//     (the teacher's [x] counts as done until unticked - Q5),
//     in the "Unit 1" table, every table closed, the hint line shown, no
//     box anywhere on the page (read-only), and the totals agree with the
//     manifest; no date line under the title (Q6);
//  3. tick two of the fixture's boxes with the mouse, go to My Progress by
//     the site's own navigation: 3 / 4, totals agreeing;
//  4. reload: still 3 / 4;
//  5. untick one on the fixture, go Back: 2 / 4;
//  6. the site's data cleared (a fresh profile for this site): 1 / 4;
//  7. nothing reported to the console.
//
// #602 (v1.8.3): the pinned My Progress link has All Classes' computed colour
// and opacity (and weight), in light and in dark (`saved-theme`), and the
// same colour under the mouse; another top-level page keeps Quartz's page
// look (0.75 opacity), so nothing else in the sidebar changed.
// #603 (v1.8.3): every level - unit, class, page row - is closed on a first
// visit and with the site's data cleared, and as the student left it on a
// return by the sidebar's link or a reload; every count sits in a pill;
// an item reads as body text; each class's count is the sum of its pages'; a
// plain click on a unit opens it alone, Option-click opens it and every
// class and page beneath it (and closes them all again); opened with the mouse on its marker, the fixture's row lists its
// four items in page order, the ticked ones marked - exactly as many as its
// count, each the manifest's own reading of this browser's ticks - each a
// link to the fixture at its success-criteria heading; a click on one lands
// there.
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
// Four items count; the teacher wrote the third ticked ([x]), which counts as
// done until the student unticks it (ruling Q5).
const TOTAL = 4
const TEACHER_TICKED = 1
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
  const lists = []
  for (const details of holder.querySelectorAll("details.plantoir-progress-items")) lists.push(details.open)
  for (const link of holder.querySelectorAll("tr.plantoir-progress-page summary > a")) {
    if (link.textContent !== ${JSON.stringify(FIXTURE)}) continue
    const line = link.closest("tr")
    const items = []
    for (const item of line.querySelectorAll("li.plantoir-progress-item")) {
      const itemLink = item.querySelector("a")
      items.push({ text: itemLink?.textContent, ticked: item.dataset.ticked, state: item.querySelector(".plantoir-progress-state")?.textContent,
                   href: itemLink ? new URL(itemLink.href).pathname + new URL(itemLink.href).hash : null,
                   shown: itemLink ? itemLink.checkVisibility() : false,
                   weight: itemLink ? getComputedStyle(itemLink).fontWeight : null, color: itemLink ? getComputedStyle(itemLink).color : null })
    }
    const unit = line.closest("details.plantoir-progress-unit")?.querySelector(":scope > summary > span")?.textContent
    const under = line.closest("details.plantoir-progress-day")?.querySelector(":scope > summary > span")?.textContent ?? null
    row = { count: line.querySelector("td.plantoir-progress-count")?.textContent, under,
            unit, href: new URL(link.href).pathname, open: link.closest("details")?.open, items }
  }
  // #603: every class's level, its count beside its name, and its pages'
  // counts added up; and how many of each level are open.
  const days = []
  for (const day of holder.querySelectorAll("details.plantoir-progress-day")) {
    const spans = day.querySelectorAll(":scope > summary > span")
    let done = 0
    let total = 0
    for (const cell of day.querySelectorAll("td.plantoir-progress-count")) {
      const [a, b] = cell.textContent.split("/")
      done += Number(a)
      total += Number(b)
    }
    days.push({ label: spans[0]?.textContent, count: spans[1]?.textContent, sum: [done, total], open: day.open })
  }
  const openCount = (selector) => { let open = 0; let all = 0; for (const d of holder.querySelectorAll(selector)) { all += 1; if (d.open) open += 1 } return [open, all] }
  const levels = { units: openCount("details.plantoir-progress-unit"), days: openCount("details.plantoir-progress-day"), rows: openCount("details.plantoir-progress-items") }
  const totals = []
  for (const item of holder.querySelectorAll(".plantoir-progress-totals li")) {
    const spans = item.querySelectorAll("span")
    totals.push({ label: spans[0]?.textContent, count: spans[1]?.textContent })
  }
  const manifest = await (await fetch("/progress-manifest.json", { cache: "no-cache" })).json()
  const expected = { overall: [0, 0] }
  let fixtureItems = null
  const add = (label, page) => {
    let done = 0
    const answers = []
    for (const item of page.items) {
      const value = localStorage.getItem("plantoir:task:/:" + page.slug + ":" + item.id)
      const isDone = value === "1" || (value === null && item.checked)
      if (isDone) done += 1
      answers.push({ text: item.text, ticked: isDone ? "true" : "false", anchor: item.anchor })
    }
    if (page.slug === ${JSON.stringify(FIXTURE_SLUG)}) fixtureItems = answers
    expected[label] = expected[label] ?? [0, 0]
    expected[label][0] += done
    expected[label][1] += page.items.length
    expected.overall[0] += done
    expected.overall[1] += page.items.length
  }
  for (const unit of manifest.units) for (const known of unit.classes) for (const page of known.pages) add(unit.label, page)
  for (const page of manifest.other.pages) add(manifest.other.label, page)
  // Every count in a pill: a summary's or a total's count span is one, a
  // page's Ticked cell holds one.
  let counts = 0
  let inPills = 0
  for (const found of holder.querySelectorAll(".plantoir-progress-count")) {
    if (found.tagName === "TH") continue
    counts += 1
    const pill = found.tagName === "TD" ? found.querySelector(":scope > .plantoir-progress-pill") : (found.classList.contains("plantoir-progress-pill") ? found : null)
    if (pill && pill.textContent === found.textContent && getComputedStyle(pill).fontWeight === "400") inPills += 1
  }
  const bodyColor = getComputedStyle(holder.querySelector(".plantoir-progress-intro")).color
  return { holder: true, tables, row, days, levels, lists, counts, inPills, bodyColor, fixtureItems, totals, expected, boxes: holder.querySelectorAll("input").length,
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
  // `folded`: whether this drawing should find every level closed - a first
  // visit, or the site's data cleared. Otherwise the levels are as the
  // student left them (#603), checked where the run opened them.
  const checkPage = async (when, done, folded = true) => {
    if (!(await waitForTable())) {
      expect(`${when}: My Progress drew its totals`, false)
      return null
    }
    const seen = await evaluate(READ)
    expect(`${when}: the fixture's row reads ${countOf(done, TOTAL)} under ${FIXTURE_CLASS} in ${FIXTURE_UNIT}`,
      seen.row !== null && seen.row.count === countOf(done, TOTAL) && seen.row.under === FIXTURE_CLASS && seen.row.unit === FIXTURE_UNIT
        && seen.row.href === "/" + FIXTURE_SLUG, seen.row)
    const overall = seen.totals[0]
    expect(`${when}: the overall total is the manifest's with this browser's ticks`,
      overall?.label === WORDS.overall && overall.count === countOf(...seen.expected.overall), { overall, expected: seen.expected.overall })
    for (const line of seen.totals.slice(1)) {
      const want = seen.expected[line.label]
      expect(`${when}: ${line.label}'s total is the manifest's`, want !== undefined && line.count === countOf(...want), { line, want })
    }
    if (folded) expect(`${when}: every table is closed`, seen.tables.length > 0 && seen.tables.every((table) => table.open === false), seen.tables)
    expect(`${when}: every count is in a pill, in regular weight`, seen.counts > 0 && seen.inPills === seen.counts, { counts: seen.counts, inPills: seen.inPills })
    expect(`${when}: no box can be ticked here`, seen.boxes === 0, seen.boxes)
    if (folded) {
      expect(`${when}: every page's list of items is closed`, seen.lists.length > 0 && seen.lists.every((open) => open === false), seen.lists)
      expect(`${when}: every class is closed`, seen.days.length > 0 && seen.days.every((day) => day.open === false), seen.days)
    }
    for (const day of seen.days) {
      expect(`${when}: ${day.label}'s count is the sum of its pages'`, day.count === countOf(...day.sum), day)
    }
    return seen
  }
  // #603: open the fixture's unit and its row with the mouse - on the row's
  // marker, beside its name, never on the link - and read its list.
  // `modifiers` 1 is Option (Alt), as Chrome's DevTools protocol numbers it.
  const clickAt = async (point, modifiers = 0) => {
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: point.x, y: point.y, modifiers })
    for (const type of ["mousePressed", "mouseReleased"]) {
      await send("Input.dispatchMouseEvent", { type, x: point.x, y: point.y, button: "left", clickCount: 1, modifiers })
    }
    await pause(200)
  }
  const markerOf = (selector) => evaluate(`(() => {
    const summary = ${selector}
    if (!summary) return null
    summary.scrollIntoView({ block: "center", behavior: "instant" })
    const area = summary.getBoundingClientRect()
    return { x: area.left + 4, y: area.top + area.height / 2, open: summary.parentElement.open }
  })()`)
  const FIXTURE_ROW_SUMMARY = `Array.from(document.querySelectorAll("[data-plantoir-progress] tr.plantoir-progress-page summary")).find((summary) => summary.querySelector("a")?.textContent === ${JSON.stringify(FIXTURE)})`
  const expandFixture = async (when, done) => {
    const unitPoint = await markerOf(`document.querySelector("[data-plantoir-progress] tr.plantoir-progress-page summary")?.closest("details.plantoir-progress-unit") && ${FIXTURE_ROW_SUMMARY}?.closest("details.plantoir-progress-unit")?.querySelector(":scope > summary")`)
    if (unitPoint === null) {
      expect(`${when}: the fixture's unit table was found`, false)
      return null
    }
    if (!unitPoint.open) await clickAt(unitPoint)
    const dayPoint = await markerOf(`${FIXTURE_ROW_SUMMARY}?.closest("details.plantoir-progress-day")?.querySelector(":scope > summary")`)
    if (dayPoint === null) {
      expect(`${when}: the fixture's class was found`, false)
      return null
    }
    if (!dayPoint.open) await clickAt(dayPoint)
    const rowPoint = await markerOf(FIXTURE_ROW_SUMMARY)
    if (rowPoint === null) {
      expect(`${when}: the fixture's row was found`, false)
      return null
    }
    if (!rowPoint.open) await clickAt(rowPoint)
    const seen = await evaluate(READ)
    const row = seen.row
    expect(`${when}: the marker opened the fixture's row and did not follow its link`,
      row !== null && row.open === true && (await evaluate("location.pathname")) === "/My-Progress", row)
    const items = row?.items ?? []
    let markedCount = 0
    for (const item of items) if (item.ticked === "true") markedCount += 1
    expect(`${when}: the row lists its ${TOTAL} items, ${done} marked ticked - its count`,
      items.length === TOTAL && markedCount === done && row.count === countOf(markedCount, items.length), { count: row?.count, items })
    const want = seen.fixtureItems ?? []
    let agrees = items.length === want.length
    for (let index = 0; agrees && index < items.length; index += 1) {
      const anchor = want[index].anchor ? "#" + want[index].anchor : ""
      agrees = items[index].text === want[index].text && items[index].ticked === want[index].ticked && items[index].shown
        && items[index].state === (want[index].ticked === "true" ? WORDS.itemTicked : WORDS.itemNotTicked)
        && items[index].href === "/" + FIXTURE_SLUG + anchor && anchor !== ""
    }
    expect(`${when}: each listed item is the manifest's - its words, this browser's tick, a link to its heading`, agrees, { items, want })
    expect(`${when}: an item reads as body text - regular weight, the page's text colour`,
      items.length > 0 && items.every((item) => item.weight === "400" && item.color === seen.bodyColor), { bodyColor: seen.bodyColor, items })
    expect(`${when}: the listed words are the fixture's own`, items[0]?.text === "I can name a variable" && items[3]?.text === "I can read an error message",
      items.map((item) => item.text))
    return seen
  }

  // #603: whether the fixture's unit, class and row are open.
  const fixtureLevels = () => evaluate(`(() => {
    const row = ${FIXTURE_ROW_SUMMARY}?.parentElement
    return { unit: row?.closest("details.plantoir-progress-unit")?.open ?? null, day: row?.closest("details.plantoir-progress-day")?.open ?? null, row: row?.open ?? null }
  })()`)
  const allOpen = (levels) => levels.unit === true && levels.day === true && levels.row === true

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
      expect("the fixture's boxes are tickable", (await evaluate("document.querySelectorAll('input.plantoir-task').length")) === 6)
      await go(`${base}/Key-Links`)
      const keyLinks = await evaluate(`(() => {
        const links = Array.from(document.querySelectorAll("article a.internal")).filter((a) => new URL(a.href).pathname === "/My-Progress")
        const first = document.querySelector("article li a.internal")
        return { links: links.length, first: first ? new URL(first.href).pathname : null }
      })()`)
      expect("Key Links links My Progress once, as its first bullet", keyLinks.links === 1 && keyLinks.first === "/My-Progress", keyLinks)
      // #602: the pinned link looks like All Classes beside it, in both
      // themes and under the mouse; a top-level page keeps the page look.
      // Read on Key Links, where neither it nor the fixture (a top-level
      // page) is the current page, which Quartz marks in its own colour.
      const LOOK = `(() => {
        const read = (link) => { if (!link) return null; const style = getComputedStyle(link); return { color: style.color, opacity: style.opacity, weight: style.fontWeight, family: style.fontFamily } }
        const top = Array.from(document.querySelectorAll(".explorer .explorer-ul > li"))
        const find = (words) => { for (const item of top) { const link = item.querySelector(".folder-title, a"); if (link && link.textContent.trim() === words) return link } return null }
        let page = null
        for (const item of top) { const link = item.querySelector(":scope > a:not(.active)"); if (link && link.textContent.trim() !== ${JSON.stringify(WORDS.title)}) { page = link; break } }
        return { classes: read(find("All Classes")), progress: read(find(${JSON.stringify(WORDS.title)})), otherPage: page ? { name: page.textContent.trim(), ...read(page) } : null }
      })()`
      for (const theme of ["light", "dark"]) {
        await evaluate(`document.documentElement.setAttribute("saved-theme", ${JSON.stringify(theme)})`)
        // Quartz eases a link's colour (base.scss `transition`): read after it.
        await pause(800)
        const look = await evaluate(LOOK)
        expect(`${theme}: My Progress in the sidebar has All Classes' colour, opacity, weight and face`,
          look.classes !== null && look.progress !== null && look.progress.color === look.classes.color && look.progress.opacity === look.classes.opacity
            && look.progress.weight === look.classes.weight && look.progress.family === look.classes.family, look)
        expect(`${theme}: another top-level page keeps the page look (0.75)`, look.otherPage !== null && look.otherPage.opacity === "0.75", look.otherPage)
        const hovered = []
        for (const words of ["All Classes", WORDS.title]) {
          const point = await evaluate(`(() => { for (const item of document.querySelectorAll(".explorer .explorer-ul > li")) { const link = item.querySelector(".folder-title, a"); if (link && link.textContent.trim() === ${JSON.stringify(words)}) { link.scrollIntoView({ block: "center", behavior: "instant" }); const area = link.getBoundingClientRect(); return { x: area.left + area.width / 2, y: area.top + area.height / 2 } } } return null })()`)
          if (point === null) { hovered.push(null); continue }
          await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: point.x, y: point.y })
          await pause(800)
          // Colour AND opacity: a page link turns the same colour under the
          // mouse but stays at 0.75 (#603 review 3).
          hovered.push(await evaluate(`(() => { const link = document.elementFromPoint(${point.x}, ${point.y})?.closest("a"); if (!link) return null; const style = getComputedStyle(link); return style.color + " @ " + style.opacity })()`))
        }
        await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: 1270, y: 890 })
        expect(`${theme}: under the mouse, My Progress has All Classes' colour and opacity`, hovered[0] !== null && hovered[0] === hovered[1], hovered)
      }
      await evaluate(`document.documentElement.setAttribute("saved-theme", "light")`)

      // 2. A fresh profile.
      await go(progress)
      const fresh = await checkPage("a fresh profile", TEACHER_TICKED)
      expect("a fresh profile: the hint line is shown", fresh?.hint === true)
      // #603: a plain click opens the unit alone; Option-click opens it and
      // every class and page beneath it, items shown; Option-click again
      // closes them all.
      const UNIT_SUMMARY = `${FIXTURE_ROW_SUMMARY}?.closest("details.plantoir-progress-unit")?.querySelector(":scope > summary")`
      const levelsInside = `(() => {
        const unit = ${FIXTURE_ROW_SUMMARY}?.closest("details.plantoir-progress-unit")
        const count = (selector) => { let open = 0; let all = 0; for (const d of unit.querySelectorAll(selector)) { all += 1; if (d.open) open += 1 } return [open, all] }
        let shown = 0
        for (const link of unit.querySelectorAll("li.plantoir-progress-item a")) if (link.checkVisibility()) shown += 1
        return { unit: unit.open, days: count("details.plantoir-progress-day"), rows: count("details.plantoir-progress-items"),
                 items: unit.querySelectorAll("li.plantoir-progress-item").length, shown }
      })()`
      const unitPoint = await markerOf(UNIT_SUMMARY)
      if (unitPoint !== null) {
        await clickAt(unitPoint)
        const plain = await evaluate(levelsInside)
        expect("a plain click opens the unit alone", plain.unit === true && plain.days[0] === 0 && plain.rows[0] === 0 && plain.days[1] > 0, plain)
        await clickAt(unitPoint)
        await clickAt(unitPoint, 1)
        const all = await evaluate(levelsInside)
        expect("Option-click opens the unit, every class and every page beneath it, their items shown",
          all.unit === true && all.days[0] === all.days[1] && all.rows[0] === all.rows[1] && all.rows[1] > 0 && all.items > 0 && all.shown === all.items, all)
        await clickAt(unitPoint, 1)
        const none = await evaluate(levelsInside)
        expect("Option-click again closes them all", none.unit === false && none.days[0] === 0 && none.rows[0] === 0, none)
      } else {
        expect("the fixture's unit was found for the Option-click", false)
      }
      await expandFixture("a fresh profile", TEACHER_TICKED)
      expect("no date line under the title", (await evaluate("document.querySelector('.content-meta') === null")) === true)

      // 3. Two ticks on the fixture (its second and third boxes are the
      // first two counted ones: the first box is before any heading).
      await go(fixture)
      await clickBox(1)
      await clickBox(2)
      const stored = await evaluate(`Object.keys(localStorage).filter((key) => key.startsWith("plantoir:task:/:${FIXTURE_SLUG}:")).length`)
      expect("two ticks were kept", stored === 2, stored)
      await go(progress)
      const ticked = await checkPage("after two ticks", TEACHER_TICKED + 2, false)
      expect("after two ticks: no hint line", ticked?.hint === false)
      const opened = await expandFixture("after two ticks", TEACHER_TICKED + 2)
      // A listed item is a link to the fixture at its heading.
      const target = opened?.row?.items?.[0]?.href ?? ""
      const itemPoint = await evaluate(`(() => {
        const link = ${FIXTURE_ROW_SUMMARY}?.closest("td")?.querySelector("li.plantoir-progress-item a")
        if (!link) return null
        link.scrollIntoView({ block: "center", behavior: "instant" })
        const area = link.getBoundingClientRect()
        return { x: area.left + Math.min(20, area.width / 2), y: area.top + area.height / 2 }
      })()`)
      if (itemPoint !== null) await clickAt(itemPoint)
      await pause(700)
      const landed = await evaluate(`({ at: location.pathname + location.hash, heading: location.hash !== "" && document.getElementById(decodeURIComponent(location.hash.slice(1)))?.tagName })`)
      expect("a listed item's link lands on the fixture at its success-criteria heading",
        target !== "" && landed.at === target && /^H[1-6]$/.test(landed.heading ?? ""), { target, landed })
      // Back to My Progress by the site's own link (the sidebar's): the
      // unit, class and row the student opened are still open (#603).
      const sidebarPoint = await evaluate(`(() => {
        for (const item of document.querySelectorAll(".explorer .explorer-ul > li")) {
          const link = item.querySelector(":scope > a")
          if (link && link.textContent.trim() === ${JSON.stringify(WORDS.title)}) {
            link.scrollIntoView({ block: "center", behavior: "instant" })
            const area = link.getBoundingClientRect()
            return { x: area.left + area.width / 2, y: area.top + area.height / 2 }
          }
        }
        return null
      })()`)
      if (sidebarPoint !== null) await clickAt(sidebarPoint)
      await pause(700)
      await checkPage("back by the sidebar's link", TEACHER_TICKED + 2, false)
      const cameBack = await fixtureLevels()
      expect("back by the sidebar's link: the unit, class and row opened are still open", allOpen(cameBack) && (await evaluate("location.pathname")) === "/My-Progress", cameBack)

      // 4. A reload.
      await open(progress)
      await checkPage("after a reload", TEACHER_TICKED + 2, false)
      const reloaded = await fixtureLevels()
      expect("after a reload: the unit, class and row opened are still open", allOpen(reloaded), reloaded)

      // 5. Untick one, then Back.
      await go(fixture)
      await clickBox(2)
      await evaluate("history.back()")
      await pause(900)
      await checkPage("after an untick and Back", TEACHER_TICKED + 1, false)
      await expandFixture("after an untick and Back", TEACHER_TICKED + 1)

      // 6. The site's data cleared: a fresh profile for this site.
      await send("Storage.clearDataForOrigin", { origin: base, storageTypes: "local_storage" })
      await open(progress)
      await checkPage("after the site's data was cleared", TEACHER_TICKED)

      expect("nothing was reported to the console", consoleErrors.length === 0, consoleErrors)
      if (problems.length > 0) {
        return finish(1, "FAIL: " + problems.join("\nFAIL: "))
      }
      finish(0, `OK: My Progress second in the sidebar and first in Key Links; ${FIXTURE}'s row under ${FIXTURE_CLASS} read 1 / 4 fresh (the teacher's [x]), 3 / 4 after two ticks and after a reload, 2 / 4 after an untick and Back, 1 / 4 with the site's data cleared; every total agreed with the manifest (${fresh?.totals?.length ?? 0} totals); read-only, every table closed; #602 the pinned link All Classes' colour, opacity and weight in light and dark and under the mouse, another top-level page still 0.75; #603 every level - unit, class, page - closed on a first visit and with the site's data cleared, and as the student left them back by the sidebar's link and after a reload; every count in a pill; items as body text; each class's count the sum of its pages', a plain click opening the unit alone and Option-click it and everything beneath (Option-click again closing all), the fixture's row opened by its marker listing its 4 items with 1, 3 and 2 marked as its count says, each linking to its heading, one click landing there`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
