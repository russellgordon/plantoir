// Ticks a site's task boxes (#519) in headless Chrome for Testing, the way a
// student does - with the mouse and the keyboard - against a server this
// check starts itself (contracts/shared-rules.json -> taskBoxes).
//
// On the verify fixture's `Task Fixture` (every itemText case and a
// Checklist), `Task Host` (the Checklist transcluded twice), `Task Twin A`
// and `B` (two pages alike in every element but their items' words), `Task
// CRLF`, `Task Printable` and `Quiz Fixture` (not-ready quizzes):
//
//  1. every box shows the Markdown's own state and nothing is written when a
//     page loads (taskBoxes.default);
//  2. a click on a box writes exactly the contract's key with "1"; unticking
//     a teacher's [x] writes "0"; a reload keeps both (persistence);
//  3. a click on the item's words ticks it; a link inside the words
//     navigates and ticks nothing; Tab then Space ticks it, with a visible
//     focus ring;
//  4. a transcluded box shows and sets its SOURCE page's tick, and two copies
//     on one page stay in step (transclusion);
//  5. five round trips by the site's own navigation leave the right state and
//     one change listener; a page reached by the router shows ITS OWN state,
//     not the last page's - proved on the twins, where the router is first
//     seen to REUSE the previous page's box element (review F3);
//  6. a tick kept under another text's id ticks nothing (textChange);
//  7. a not-ready quiz's boxes stay disabled and unstamped, and clicking them
//     writes nothing (which);
//  8. with storage refused, boxes still tick and the console stays clean;
//  1b. on screen the box's edge and tick, and a ticked item's words, are the
//     page's dark grey, with no fill (taskBoxes.look);
// 10. the handout (Print > Questions only) carries the student's ticks
//     (taskBoxes.print, ruling Q1);
//  9. on paper (⌘P, background graphics off) a ticked box is inked and an
//     unticked one is an empty box, in the light and the dark theme - read
//     from the PDF's pixels with poppler's pdftoppm, as
//     print_plain_page.mjs reads its ink (review F6).
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/task_boxes.mjs <chrome> <site folder>
//
// PLANTOIR_TASK_CHECK_KEEP=<folder> keeps the PDFs there.

import { execFileSync, spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!chromePath || !siteFolder) {
  console.error("usage: node task_boxes.mjs <chrome> <site folder>")
  process.exit(2)
}

const RULES = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).taskBoxes
const caseItem = (name, index = 0) => RULES.itemText.cases.find((c) => c.name.startsWith(name)).items[index]
const PENCIL = caseItem("a plain item")
const CHAPTER = caseItem("a ticked item")
const LAPTOP = caseItem("a * marker")
const LUNCH = caseItem("a + marker")
const EDITOR = caseItem("an ordered item, 1.")
const ELSEWHERE = RULES.itemId.cases[1].id // an id no item on Task CRLF has
const keyOf = (page, id) => `plantoir:task:/:${page}:${id}`

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

const work = mkdtempSync(join(tmpdir(), "plantoir-task-boxes-"))
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
const timer = setTimeout(() => finish(1, "FAIL: the task boxes were not checked within 300 s"), 300000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// Helpers that run in the page.
const PAGE_HELPERS = `
window.__task = {
  boxes: () => Array.from(document.querySelectorAll("input.plantoir-task")),
  box: (id, n = 0) => document.querySelectorAll('input.plantoir-task[data-task-item="' + id + '"]')[n],
  state: () => window.__task.boxes().map((box) => (box.checked ? "x" : "_")).join(""),
  defaults: () => window.__task.boxes().map((box) => (box.defaultChecked ? "x" : "_")).join(""),
  stored: () => Object.keys(localStorage).filter((key) => key.startsWith("plantoir:task:")).sort()
    .map((key) => key + "=" + localStorage.getItem(key)),
  centre: (element) => {
    element.scrollIntoView({ block: "center", behavior: "instant" })
    const box = element.getBoundingClientRect()
    return { x: box.left + box.width / 2, y: box.top + box.height / 2 }
  },
}
true
`

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
  const open = async (url) => {
    await send("Page.navigate", { url })
    for (let tries = 0; tries < 80; tries += 1) {
      await pause(250)
      if ((await evaluate("document.readyState")) === "complete") {
        await evaluate(PAGE_HELPERS)
        await pause(400)
        return true
      }
    }
    return false
  }
  const go = async (url) => {
    await evaluate(`window.spaNavigate(new URL(${JSON.stringify(url)}))`)
    await pause(700)
    await evaluate(PAGE_HELPERS)
  }
  // A real mouse click at an element's centre (or at a point inside it).
  const clickAt = async (point) => {
    for (const type of ["mousePressed", "mouseReleased"]) {
      await send("Input.dispatchMouseEvent", { type, x: point.x, y: point.y, button: "left", clickCount: 1 })
    }
    await pause(150)
  }
  const click = async (expression) => clickAt(await evaluate(`window.__task.centre(${expression})`))
  const key = async (name, code, keyCode, text) => {
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: name, code, windowsVirtualKeyCode: keyCode })
    if (text) await send("Input.dispatchKeyEvent", { type: "char", key: name, text })
    await send("Input.dispatchKeyEvent", { type: "keyUp", key: name, code, windowsVirtualKeyCode: keyCode })
    await pause(150)
  }
  const problems = []
  const measured = []
  const expect = (what, ok, detail) => {
    if (!ok) problems.push(`${what}${detail === undefined ? "" : ": " + JSON.stringify(detail).slice(0, 400)}`)
  }
  const listenersOn = async (expression) => {
    const handle = await send("Runtime.evaluate", { expression })
    const listed = await send("DOMDebugger.getEventListeners", { objectId: handle.result.objectId })
    const counts = {}
    for (const listener of listed.listeners ?? []) counts[listener.type] = (counts[listener.type] ?? 0) + 1
    return counts
  }

  socket.onopen = async () => {
    try {
      await send("Page.enable")
      await send("Runtime.enable")
      await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
      siteServer = await serve()
      const base = `http://127.0.0.1:${siteServer.port}`
      const fixture = base + "/Task-Fixture.html"
      const host = base + "/Task-Host.html"

      // 1. The Markdown's own state, and nothing written on load.
      if (!(await open(fixture))) return finish(1, "FAIL: Task Fixture did not load")
      const count = await evaluate("window.__task.boxes().length")
      expect("the fixture's boxes were made tickable", count > 20, count)
      const first = await evaluate("({ state: window.__task.state(), defaults: window.__task.defaults(), stored: window.__task.stored() })")
      expect("every box shows the Markdown's own state", first.state === first.defaults && first.state.includes("x") && first.state.includes("_"), first)
      expect("nothing is written when a page loads", first.stored.length === 0, first.stored)

      // 1b. The look on screen (taskBoxes.look): edge and tick in the
      // page's dark grey, no fill, a ticked item's words in it too.
      const look = await evaluate(`(() => {
        const probe = document.createElement("span")
        probe.style.color = "var(--darkgray)"
        document.body.appendChild(probe)
        const darkgray = getComputedStyle(probe).color
        probe.remove()
        const ticked = window.__task.boxes().find((box) => box.checked)
        const unticked = window.__task.boxes().find((box) => !box.checked)
        return {
          darkgray,
          untickedEdge: getComputedStyle(unticked).borderTopColor,
          tickedEdge: getComputedStyle(ticked).borderTopColor,
          tickedFill: getComputedStyle(ticked).backgroundColor,
          tick: getComputedStyle(ticked, "::after").borderRightColor,
          words: getComputedStyle(ticked.closest("li")).color,
        }
      })()`)
      expect("on screen the edges, the tick and a ticked item's words are the page's dark grey, with no fill",
        look.untickedEdge === look.darkgray && look.tickedEdge === look.darkgray && look.tick === look.darkgray &&
        look.words === look.darkgray && look.tickedFill === "rgba(0, 0, 0, 0)", look)

      // 2. A click writes the contract's key; unticking an [x] writes "0".
      await click(`window.__task.box(${JSON.stringify(PENCIL.id)})`)
      const afterTick = await evaluate("window.__task.stored()")
      expect("a click on a box writes exactly the contract's key with 1",
        JSON.stringify(afterTick) === JSON.stringify([`${keyOf("Task-Fixture", PENCIL.id)}=1`]), afterTick)
      await click(`window.__task.box(${JSON.stringify(CHAPTER.id)})`)
      expect("unticking a teacher's [x] writes 0", (await evaluate(`localStorage.getItem(${JSON.stringify(keyOf("Task-Fixture", CHAPTER.id))})`)) === "0")
      await open(fixture)
      const reloaded = await evaluate(`({ pencil: window.__task.box(${JSON.stringify(PENCIL.id)}).checked, chapter: window.__task.box(${JSON.stringify(CHAPTER.id)}).checked })`)
      expect("a reload keeps both", reloaded.pencil === true && reloaded.chapter === false, reloaded)

      // 3. The words, a link inside them, and the keyboard.
      const words = await evaluate(`(() => {
        const label = window.__task.box(${JSON.stringify(LAPTOP.id)}).closest("label")
        const range = document.createRange()
        range.selectNodeContents(label.lastChild)
        label.scrollIntoView({ block: "center", behavior: "instant" })
        const box = range.getBoundingClientRect()
        return { x: box.left + box.width / 2, y: box.top + box.height / 2, text: label.textContent.trim() }
      })()`)
      await clickAt(words)
      expect("a click on the item's words ticks it", (await evaluate(`localStorage.getItem(${JSON.stringify(keyOf("Task-Fixture", LAPTOP.id))})`)) === "1", words)
      expect("the words are the box's name", words.text === LAPTOP.text, words)
      await evaluate(`window.__task.box(${JSON.stringify(EDITOR.id)}).focus()`)
      await key("Tab", "Tab", 9)
      const focused = await evaluate(`(() => {
        const box = document.activeElement
        const style = getComputedStyle(box)
        return { item: box.dataset.taskItem, visible: box.matches(":focus-visible"), outline: style.outlineStyle + " " + style.outlineWidth }
      })()`)
      // Tab from "Open the editor" lands on the next box, "Save your file".
      const next = caseItem("an ordered item, 1)")
      expect("Tab reaches the next box with a visible focus ring", focused.item === next.id && focused.visible && focused.outline === "solid 2px", focused)
      await key(" ", "Space", 32, " ")
      expect("Space ticks it", (await evaluate(`localStorage.getItem(${JSON.stringify(keyOf("Task-Fixture", next.id))})`)) === "1")
      const linked = await evaluate(`(() => {
        const link = Array.from(document.querySelectorAll(".plantoir-task-label a")).find((a) => a.textContent.includes("Task Host"))
        return { id: link.closest("label").querySelector("input").dataset.taskItem }
      })()`)
      await click(`Array.from(document.querySelectorAll(".plantoir-task-label a")).find((a) => a.textContent.includes("Task Host"))`)
      await pause(900)
      await evaluate(PAGE_HELPERS)
      const afterLink = await evaluate(`({ slug: document.body.dataset.slug, stored: localStorage.getItem(${JSON.stringify(keyOf("Task-Fixture", "LINKED"))}.replace("LINKED", ${JSON.stringify(linked.id)})) })`)
      expect("a link inside an item's words navigates and ticks nothing", afterLink.slug === "Task-Host" && afterLink.stored === null, afterLink)

      // 4. Transclusion: the source's tick, and two copies in step.
      await open(host)
      const transcluded = await evaluate(`(() => {
        const boxes = window.__task.boxes()
        return { pages: boxes.map((box) => box.dataset.taskPage), state: window.__task.state() }
      })()`)
      expect("the host's own box carries its page and the transcluded ones their source's",
        JSON.stringify(transcluded.pages) === JSON.stringify(["Task-Host", "Task-Fixture", "Task-Fixture", "Task-Fixture", "Task-Fixture", "Task-Fixture", "Task-Fixture"]), transcluded)
      const sharpen = await evaluate("window.__task.boxes()[1].dataset.taskItem")
      await click("window.__task.boxes()[1]")
      const inStep = await evaluate(`({ copies: Array.from(document.querySelectorAll('input.plantoir-task[data-task-item="${sharpen}"]')).map((box) => box.checked), stored: localStorage.getItem(${JSON.stringify(keyOf("Task-Fixture", ""))} + ${JSON.stringify(sharpen)}) })`)
      expect("a transcluded box sets its source's key, and both copies tick together", inStep.stored === "1" && JSON.stringify(inStep.copies) === "[true,true]", inStep)
      expect("nothing is kept under the host's name for another page's item",
        (await evaluate(`localStorage.getItem(${JSON.stringify(keyOf("Task-Host", ""))} + ${JSON.stringify(sharpen)})`)) === null)

      // 5. Five round trips, the twins, and one change listener.
      await open(fixture)
      const listenersBefore = await listenersOn("document")
      const fixtureState = await evaluate("window.__task.state()")
      for (let step = 0; step < 5; step += 1) {
        await go(host)
        await go(fixture)
      }
      const roundTrips = await evaluate("window.__task.state()")
      expect("five round trips leave the page as the student left it", roundTrips === fixtureState, { fixtureState, roundTrips })
      await go(host)
      const hostAgain = await evaluate(`window.__task.state()`)
      // The host's own box, then the Checklist twice: Sharpen, Find ([x]), Read.
      expect("the host still shows the source's tick after the trips", hostAgain === "_xx_xx_", hostAgain)
      const listenersAfter = await listenersOn("document")
      expect("one change listener, however many pages are shown", (listenersAfter.change ?? 0) === (listenersBefore.change ?? 0) && (listenersBefore.change ?? 0) >= 1, { listenersBefore, listenersAfter })

      await open(base + "/Task-Twin-A.html")
      await evaluate("window.__task.boxes()[0].__twin = 'A'")
      await click("window.__task.boxes()[0]")
      await go(base + "/Task-Twin-B.html")
      const twinB = await evaluate("({ slug: document.body.dataset.slug, reused: window.__task.boxes()[0].__twin === 'A', state: window.__task.state(), item: window.__task.boxes()[0].dataset.taskItem })")
      expect("the router reused Twin A's box for Twin B (so the next check is not vacuous)", twinB.slug === "Task-Twin-B" && twinB.reused, twinB)
      expect("a page reached by the router shows its own state, not the last page's", twinB.state === "__", twinB)
      await go(base + "/Task-Twin-A.html")
      expect("and the first page's tick is still its own", (await evaluate("window.__task.state()")) === "x_")
      measured.push(`twins: Twin B reused Twin A's box ${twinB.reused ? "yes" : "no"}`)

      // 6. A tick under another text's id ticks nothing.
      await evaluate(`localStorage.setItem(${JSON.stringify(keyOf("Task-CRLF", ELSEWHERE))}, "1")`)
      await open(base + "/Task-CRLF.html")
      const crlf = await evaluate("({ state: window.__task.state(), defaults: window.__task.defaults(), items: window.__task.boxes().map((box) => box.dataset.taskItem) })")
      expect("the CR LF page's boxes carry the contract's ids", JSON.stringify(crlf.items) === JSON.stringify(caseItemsOf("a page saved with CR LF")), crlf)
      expect("a tick kept under another text's id ticks nothing", crlf.state === crlf.defaults, crlf)

      // 7. Not-ready quizzes keep their boxes as Quartz drew them.
      await open(base + "/Quiz-Fixture.html")
      const quizBoxes = await evaluate(`(() => {
        const inside = Array.from(document.querySelectorAll('.plantoir-quiz li.task-list-item > input, .plantoir-quiz li.task-list-item > p > input'))
        return { count: inside.length, disabled: inside.filter((box) => box.disabled).length, stamped: inside.filter((box) => box.matches(".plantoir-task, [data-task-item]")).length }
      })()`)
      expect("a not-ready quiz's boxes stay disabled and unstamped", quizBoxes.count > 0 && quizBoxes.disabled === quizBoxes.count && quizBoxes.stamped === 0, quizBoxes)
      if (quizBoxes.count > 0) {
        await click(`document.querySelector('.plantoir-quiz li.task-list-item > input')`)
      }
      const quizStored = await evaluate("Object.keys(localStorage).filter((key) => key.includes(':Quiz-Fixture'))")
      expect("clicking one writes nothing", quizStored.length === 0, quizStored)

      // 9. On paper: ink for a tick, an empty box otherwise, both themes - on
      // a printable page (which prints in its light colours whatever the
      // theme) and on one that is not (which keeps the dark theme's).
      await evaluate("localStorage.clear()")
      for (const theme of ["light", "dark"]) {
        for (const [name, page, ticked, unticked, tick] of [
          ["printable", "/Task-Printable.html", ["Printable", "second"], ["Printable", "first"], null],
          ["plain", "/Task-Twin-A.html", ["Twin", "A", "first"], ["Twin", "A", "second"], 0],
        ]) {
          await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: theme }] })
          await open(base + page)
          await evaluate(`document.documentElement.setAttribute("saved-theme", ${JSON.stringify(theme)})`)
          if (tick !== null) {
            await evaluate(`(() => { const box = window.__task.boxes()[${tick}]; if (!box.checked) box.click() })()`)
          }
          const ink = await inkOnPaper(send, theme, name, ticked, unticked)
          measured.push(`paper ${name} ${theme}: ${ink.ticked.inside} inked pixels inside the ticked box, ${ink.unticked.inside} inside the unticked one`)
          expect(`on paper (${name}, ${theme}) both boxes are drawn in ink, the ticked one with its tick inside and the unticked one empty`,
            ink.ticked.found && ink.unticked.found && ink.ticked.inside >= 20 && ink.unticked.inside <= 3, ink)
        }
      }
      await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })

      // 10. The handout carries the student's ticks (taskBoxes.print, ruling
      // Q1): a tick on the first item and an untick of the teacher's [x] on
      // the second, then Print > Questions only, read from the handout's
      // frame at the moment it prints.
      await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
      await evaluate("localStorage.clear()")
      await open(base + "/Task-Printable.html")
      await click("window.__task.boxes()[0]")
      await click("window.__task.boxes()[1]")
      const onScreen = await evaluate("window.__task.state()")
      await send("Page.addScriptToEvaluateOnNewDocument", {
        source: `new MutationObserver((changes) => { for (const change of changes) for (const node of change.addedNodes) {
          if (node.tagName === "IFRAME") node.contentWindow.print = () => {
            window.__handoutBoxes = Array.from(node.contentDocument.querySelectorAll("input.plantoir-task")).map((box) => (box.checked ? "x" : "_")).join("")
          } } }).observe(document, { childList: true, subtree: true })`,
      })
      // From another page, so the address with the print request is a new
      // document (the same page with only a new #fragment is not).
      await open(base + "/Task-Twin-B.html")
      await send("Page.navigate", { url: base + "/Task-Printable.html#plantoir-print=questionsOnly&paper=portrait" })
      let handoutBoxes = null
      for (let tries = 0; tries < 240 && handoutBoxes === null; tries += 1) {
        await pause(250)
        handoutBoxes = (await evaluate("window.__handoutBoxes ?? null").catch(() => null)) ?? null
      }
      expect("the handout shows the student's ticks, as the page did", onScreen === "x__" && handoutBoxes === onScreen, { onScreen, handoutBoxes })
      measured.push(`handout boxes ${handoutBoxes} (the page showed ${onScreen})`)

      // 8. Storage refused: boxes still tick, and the task boxes add no error
      // to the console. Quartz's own scripts already report a refused store
      // on every page (its theme and its sidebar), so a page with no task box
      // is the baseline: the fixture's load must add nothing to it, and a
      // tick must report nothing at all.
      await send("Page.addScriptToEvaluateOnNewDocument", {
        source: "Object.defineProperty(window, 'localStorage', { get() { throw new Error('refused') } })",
      })
      consoleErrors.length = 0
      await open(base + "/Help-Sessions.html")
      const baseline = consoleErrors.length
      consoleErrors.length = 0
      await open(fixture)
      const onLoad = consoleErrors.slice()
      consoleErrors.length = 0
      const refusedBefore = await evaluate(`window.__task.box(${JSON.stringify(PENCIL.id)}).checked`)
      await click(`window.__task.box(${JSON.stringify(PENCIL.id)})`)
      const refusedAfter = await evaluate(`window.__task.box(${JSON.stringify(PENCIL.id)}).checked`)
      expect("with storage refused a box still ticks", refusedBefore === false && refusedAfter === true, { refusedBefore, refusedAfter })
      expect("and a tick reports nothing to the console", consoleErrors.length === 0, consoleErrors)
      expect("and loading the boxes adds no error to Quartz's own", onLoad.length === baseline, { baseline, onLoad })
      // ... and a handout from the Print button keeps the ticks made on this
      // page (review F1: the print hook re-read the refused store and put
      // every box back to the Markdown's state, on the handout and on screen).
      await open(base + "/Task-Printable.html")
      await click("window.__task.boxes()[0]")
      const refusedPage = await evaluate("window.__task.state()")
      await evaluate("window.__handoutBoxes = null")
      await evaluate(`(() => { document.querySelector("summary.plantoir-print-button").click(); document.querySelector('.plantoir-print-menu button[data-mode="questionsOnly"]').click() })()`)
      let refusedHandout = null
      for (let tries = 0; tries < 240 && refusedHandout === null; tries += 1) {
        await pause(250)
        refusedHandout = (await evaluate("window.__handoutBoxes ?? null").catch(() => null)) ?? null
      }
      await pause(500)
      const refusedAfter2 = await evaluate("window.__task.state()")
      expect("with storage refused, a handout keeps the ticks made on the page, and so does the page",
        refusedPage === "xx_" && refusedHandout === refusedPage && refusedAfter2 === refusedPage, { refusedPage, refusedHandout, refusedAfter2 })
      measured.push(`storage refused: handout ${refusedHandout} (the page showed ${refusedPage})`)

      clearTimeout(timer)
      if (problems.length > 0) {
        return finish(1, "FAIL: " + problems.join("; "))
      }
      finish(0, `OK: ${count} boxes on the fixture, ticks kept and restored, words, a link, Tab and Space, a transcluded copy in step, five round trips and one listener, the router's reused box showing its own page, a not-ready quiz left alone, storage refused, ${measured.join("; ")}`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}

function caseItemsOf(name) {
  return RULES.itemText.cases.find((c) => c.name.startsWith(name)).items.map((item) => item.id)
}

// ⌘P with background graphics off (the browser's default), read back from
// the PDF's pixels: the box left of "Printable second item" ([x]) against
// the one left of "Printable first item" ([ ]), at 150 dpi in grey.
const DPI = 150
async function inkOnPaper(send, theme, name, tickedWords, untickedWords) {
  await send("Emulation.setEmulatedMedia", { media: "print", features: [{ name: "prefers-color-scheme", value: theme }] })
  const pdf = await send("Page.printToPDF", { printBackground: false, paperWidth: 8.5, paperHeight: 11 })
  await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: theme }] })
  const folder = join(work, `paper-${name}-${theme}`)
  mkdirSync(folder)
  const file = join(folder, "page.pdf")
  writeFileSync(file, Buffer.from(pdf.data, "base64"))
  if (process.env.PLANTOIR_TASK_CHECK_KEEP) writeFileSync(join(process.env.PLANTOIR_TASK_CHECK_KEEP, `paper-${name}-${theme}.pdf`), Buffer.from(pdf.data, "base64"))
  const sheets = execFileSync("pdftotext", ["-bbox", file, "-"], { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] }).split("<page ").slice(1)
  // The box just left of an item's first words, on whichever sheet holds them.
  const boxBefore = (sequence) => {
    for (let sheet = 0; sheet < sheets.length; sheet += 1) {
      const words = Array.from(sheets[sheet].matchAll(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)<\/word>/g))
        .map((match) => ({ xMin: Number(match[1]), yMin: Number(match[2]), xMax: Number(match[3]), yMax: Number(match[4]), word: match[5] }))
      const at = words.findIndex((_, index) => sequence.every((word, offset) => words[index + offset]?.word === word))
      if (at < 0) continue
      const page = String(sheet + 1)
      const prefix = join(folder, `p${page}`)
      execFileSync("pdftoppm", ["-r", String(DPI), "-gray", "-singlefile", "-f", page, "-l", page, file, prefix], { stdio: ["ignore", "ignore", "ignore"] })
      const image = readPgm(prefix + ".pgm")
      const word = words[at]
      const height = word.yMax - word.yMin
      return boxInk(image, { xMin: word.xMin - 3 * height, xMax: word.xMin - 1, yMin: word.yMin, yMax: word.yMax })
    }
    return { found: false, words: "not on paper" }
  }
  return { ticked: boxBefore(tickedWords), unticked: boxBefore(untickedWords) }
}

function readPgm(file) {
  const bytes = readFileSync(file)
  const fields = []
  let at = 0
  while (fields.length < 4) {
    while (/\s/.test(String.fromCharCode(bytes[at]))) at += 1
    let field = ""
    while (!/\s/.test(String.fromCharCode(bytes[at]))) {
      field += String.fromCharCode(bytes[at])
      at += 1
    }
    fields.push(field)
  }
  at += 1
  return { width: Number(fields[1]), height: Number(fields[2]), pixels: bytes.subarray(at) }
}

// A box drawn in INK, left of a word: its sides are the columns where ink
// (darker than 200 of 255) runs unbroken up and down through the word's
// middle for most of a box's height, and its top and bottom are where its
// left side's run ends; what is inside is counted - pixels darker than
// mid-grey, three pixels in from each edge. Not found: no side in ink, so the
// box does not show on paper (Quartz's own unticked box, in its light grey).
function boxInk(image, area) {
  const scale = DPI / 72
  // The box is not centred on the word's own box, so each row from the top
  // of the word to its middle is tried as the row its sides cross.
  for (let row = Math.round(area.yMin * scale); row <= Math.round(((area.yMin + area.yMax) / 2) * scale); row += 1) {
    const found = boxInkThrough(image, area, row)
    if (found.found) return found
  }
  return { found: false }
}

function boxInkThrough(image, area, middle) {
  const scale = DPI / 72
  const left = Math.max(0, Math.floor(area.xMin * scale))
  const right = Math.min(image.width, Math.ceil(area.xMax * scale))
  const inked = (x, y) => y >= 0 && y < image.height && image.pixels[y * image.width + x] < 200
  const side = Math.round(12 * scale) // the box: 16 CSS px, 12 pt
  const runOf = (x) => {
    let up = 0
    while (up < 2 * side && inked(x, middle - up - 1)) up += 1
    let down = 0
    while (down < 2 * side && inked(x, middle + down + 1)) down += 1
    return inked(x, middle) ? { up, down, length: up + down + 1 } : { up: 0, down: 0, length: 0 }
  }
  const sides = []
  for (let x = left; x < right; x += 1) {
    const run = runOf(x)
    if (run.length >= 0.6 * side) sides.push({ x, run })
  }
  if (sides.length < 2 || sides[sides.length - 1].x - sides[0].x < 0.6 * side) return { found: false }
  const boxLeft = sides[0].x
  const boxRight = sides[sides.length - 1].x
  const boxTop = middle - sides[0].run.up
  const boxBottom = middle + sides[0].run.down
  let inside = 0
  for (let y = boxTop + 3; y <= boxBottom - 3; y += 1) {
    for (let x = boxLeft + 3; x <= boxRight - 3; x += 1) {
      if (image.pixels[y * image.width + x] < 128) inside += 1
    }
  }
  return { found: true, inside, width: boxRight - boxLeft + 1, height: boxBottom - boxTop + 1 }
}
