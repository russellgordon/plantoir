// Answers a site's self-check quizzes (#563) in headless Chrome for Testing,
// the way a student does, against a server this check starts itself
// (contracts/shared-rules.json -> quizCallouts: markup, checking, shuffle,
// storage, print).
//
// On the verify fixture's `Quiz Playground` (every kind of question), `Quiz
// Host` (a quiz of its own and another page's, transcluded) and `Quiz
// Printable` (a printable page with quizzes):
//
//  1. each kind, answered wrongly and then rightly, says the contract's
//     words; a blank is marked in words; an empty answer is never checked;
//     the explanation is revealed - its TEXT visible, not only its title -
//     and a graph inside it drawn; Show answer marks the right choice, or
//     shows the answer with its formula set by KaTeX (review S9);
//  2. nothing is asked of any other website, and answering asks the site
//     itself for nothing either;
//  3. a shuffled quiz comes out in another order on some of twenty loads,
//     and goes back to Markdown order for ⌘P;
//  4. a folded quiz's title is a button that Enter opens, and what is inside
//     a fold is inert until then (review S6); a choice that is only a graph
//     is named by the graph's description (S7); pressing Run on code in a
//     choice never ticks it;
//  5. the score is kept across a reload, Start again clears it, and with
//     storage refused every quiz still checks;
//  6. five changes of page by the site's own navigation leave each quiz with
//     ONE set of listeners and one row of buttons, and one listener for
//     printing;
//  7. a transcluded quiz has ids and a radio group of its own and is scored
//     under its own page's name (review S5);
//  8. on paper (print media) nothing a quiz holds back, and no button,
//     shows, and choices are drawn as empty circles; a printable page's
//     handout holds a quiz's question and neither its answer nor its
//     explanation (ruling Q8).
//
// "No network" (#511) is checked as: answering asks no other website and
// nothing of the site itself (graphs and code to run fetch their engines from
// the site, as they do outside a quiz); what a fixture's settings load on
// every page (a font, analytics) is the site's, not the quiz's.
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/quiz_check.mjs <chrome> <site folder>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!chromePath || !siteFolder) {
  console.error("usage: node quiz_check.mjs <chrome> <site folder>")
  process.exit(2)
}

const RULES = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).quizCallouts
const said = (key, values = {}) =>
  RULES.words.site[key].replace(/\{([A-Za-z]+)\}/g, (whole, name) => (name in values ? String(values[name]) : whole))

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".zip": "application/zip", ".svg": "image/svg+xml",
  ".png": "image/png", ".ico": "image/x-icon", ".woff2": "font/woff2", ".xml": "application/xml", ".txt": "text/plain",
}

function serve() {
  const requests = []
  const server = createServer((request, response) => {
    let path = decodeURIComponent(new URL(request.url, "http://x").pathname)
    requests.push(path)
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
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port, requests }))
  })
}

const work = mkdtempSync(join(tmpdir(), "plantoir-quiz-check-"))
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
const timer = setTimeout(() => finish(1, "FAIL: the quizzes were not checked within 300 s"), 300000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// Helpers that run in the page.
const PAGE_HELPERS = `
window.__quiz = {
  quiz: (n) => document.querySelector('.plantoir-quiz[data-quiz-n="' + n + '"]'),
  feedback: (n) => window.__quiz.quiz(n).querySelector(".plantoir-quiz-feedback")?.textContent ?? null,
  choose: (n, places) => {
    for (const choice of window.__quiz.quiz(n).querySelectorAll(".plantoir-quiz-choice")) {
      const input = choice.querySelector("input.plantoir-quiz-input")
      input.checked = places.includes(Number(choice.dataset.choice))
    }
  },
  type: (n, values) => {
    const boxes = Array.from(window.__quiz.quiz(n).querySelectorAll("input.plantoir-quiz-blank"))
    values.forEach((value, index) => {
      boxes[index].value = value
      boxes[index].dispatchEvent(new Event("input", { bubbles: true }))
    })
  },
  press: (n, name) => window.__quiz.quiz(n).querySelector(".plantoir-quiz-" + name).click(),
  order: (n) => Array.from(window.__quiz.quiz(n).querySelectorAll(".plantoir-quiz-choice")).map((choice) => Number(choice.dataset.choice)),
  visibleText: (element) => {
    if (!element) return false
    const box = element.getBoundingClientRect()
    if (box.height <= 0 || box.width <= 0) return false
    // Not clipped by a callout above it that kept an old height.
    let parent = element.parentElement
    while (parent) {
      const style = getComputedStyle(parent)
      if (style.display === "none" || style.visibility === "hidden") return false
      if (style.overflowY === "hidden") {
        const outer = parent.getBoundingClientRect()
        if (box.bottom > outer.bottom + 1) return false
      }
      parent = parent.parentElement
    }
    return true
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
  const offSite = []
  let printedHandout = null
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
    if (message.method === "Network.requestWillBeSent") {
      const url = message.params.request.url
      if (!/^(https?:\/\/127\.0\.0\.1[:/]|data:|blob:|about:)/.test(url)) offSite.push(url)
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
  const problems = []
  const notes = []
  const expect = (what, ok, detail) => {
    if (!ok) problems.push(`${what}${detail === undefined ? "" : ": " + JSON.stringify(detail).slice(0, 300)}`)
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
      await send("Network.enable")
      await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
      siteServer = await serve()
      const base = `http://127.0.0.1:${siteServer.port}`
      const playground = base + "/Quiz-Playground.html"

      // 1. Every kind, wrong then right.
      if (!(await open(playground))) return finish(1, "FAIL: the playground did not load")
      const counted = await evaluate("document.querySelectorAll('.plantoir-quiz[data-built]').length")
      expect("every quiz on the page was set up", counted === 8, counted)
      const rows = await evaluate("Array.from(document.querySelectorAll('.plantoir-quiz')).map((quiz) => quiz.querySelectorAll('.plantoir-quiz-actions').length)")
      expect("each interactive quiz has one row of buttons", JSON.stringify(rows) === JSON.stringify([1, 1, 1, 1, 1, 1, 1, 1]), rows)
      const loadedRequests = siteServer.requests.length
      // The fixture's own site settings ask Google Fonts and an analytics
      // script for themselves on load; answering must ask nobody anything.
      const loadedOffSite = offSite.length

      // Short answer with a formula: empty, wrong, right.
      await evaluate("window.__quiz.press(1, 'check')")
      expect("an empty answer is never checked", (await evaluate("window.__quiz.feedback(1)")) === said("typeFirst"))
      expect("an empty answer reveals nothing", await evaluate("window.__quiz.quiz(1).querySelector('.plantoir-quiz-explain').hidden"))
      await evaluate("window.__quiz.type(1, ['128']); window.__quiz.press(1, 'check')")
      expect("a wrong short answer says notRight", (await evaluate("window.__quiz.feedback(1)")) === said("notRight"))
      await pause(500)
      const explainShown = await evaluate("window.__quiz.visibleText(Array.from(window.__quiz.quiz(1).querySelectorAll('.plantoir-quiz-explain .callout-content p')).find((p) => p.textContent.includes('playground-explain-7f3a')))")
      expect("after a Check the explanation's TEXT is visible, not only its title (M9, S6)", explainShown === true)
      await evaluate("window.__quiz.type(1, ['2 ^ 7']); window.__quiz.press(1, 'check')")
      expect("2 ^ 7 is not 2^7 (answers.math)", (await evaluate("window.__quiz.feedback(1)")) === said("notRight"))
      await evaluate("window.__quiz.type(1, ['$2^7$']); window.__quiz.press(1, 'check')")
      expect("a right short answer says right", (await evaluate("window.__quiz.feedback(1)")) === said("right"))
      await evaluate("window.__quiz.press(1, 'show')")
      const answerShown = await evaluate("(() => { const answer = window.__quiz.quiz(1).querySelector('.plantoir-quiz-answer'); return { hidden: answer.hidden, katex: !!answer.querySelector('.katex'), visible: window.__quiz.visibleText(answer) } })()")
      expect("Show answer shows the answer, its formula set by KaTeX (S9)", !answerShown.hidden && answerShown.katex && answerShown.visible, answerShown)
      expect("Show answer says answerShown", (await evaluate("window.__quiz.feedback(1)")) === said("answerShown"))

      // Multiple choice with a graph in its explanation.
      await evaluate("window.__quiz.press(2, 'check')")
      expect("no choice is never checked", (await evaluate("window.__quiz.feedback(2)")) === said("chooseFirst"))
      await evaluate("window.__quiz.choose(2, [0]); window.__quiz.press(2, 'check')")
      expect("a wrong choice says notRight", (await evaluate("window.__quiz.feedback(2)")) === said("notRight"))
      await evaluate("window.__quiz.quiz(2).querySelector('.plantoir-quiz-explain').scrollIntoView()")
      let drawn = false
      for (let tries = 0; tries < 40 && !drawn; tries += 1) {
        await pause(250)
        drawn = await evaluate("!!window.__quiz.quiz(2).querySelector('.plantoir-quiz-explain .pl-figure svg')")
      }
      expect("the graph in the explanation is drawn once it is revealed", drawn)
      await evaluate("window.__quiz.choose(2, [1]); window.__quiz.press(2, 'check')")
      expect("the right choice says right", (await evaluate("window.__quiz.feedback(2)")) === said("right"))
      await evaluate("window.__quiz.press(2, 'show')")
      const badges = await evaluate("Array.from(window.__quiz.quiz(2).querySelectorAll('.plantoir-quiz-choice')).filter((choice) => choice.querySelector('.plantoir-quiz-badge')).map((choice) => Number(choice.dataset.choice))")
      expect("Show answer marks the right choice in words", JSON.stringify(badges) === "[1]", badges)
      expect("the badge says correctChoice", (await evaluate("window.__quiz.quiz(2).querySelector('.plantoir-quiz-badge').textContent")) === said("correctChoice"))

      // Select all that apply.
      expect("select all says so", (await evaluate("window.__quiz.quiz(3).querySelector('.plantoir-quiz-hint')?.textContent")) === said("selectAll"))
      const described = await evaluate("(() => { const set = window.__quiz.quiz(3).querySelector('fieldset'); return document.getElementById(set.getAttribute('aria-describedby'))?.textContent })()")
      expect("the choices are described by the select-all line", described === said("selectAll"), described)
      await evaluate("window.__quiz.choose(3, [0]); window.__quiz.press(3, 'check')")
      expect("half of select all is not right", (await evaluate("window.__quiz.feedback(3)")) === said("notRight"))
      await evaluate("window.__quiz.choose(3, [0, 2]); window.__quiz.press(3, 'check')")
      expect("all of select all is right", (await evaluate("window.__quiz.feedback(3)")) === said("right"))

      // Fill in the blank: marks in words, tolerance and alternatives.
      await evaluate("window.__quiz.type(4, ['50', 'Standard']); window.__quiz.press(4, 'check')")
      expect("one blank of two says someBlanksRight", (await evaluate("window.__quiz.feedback(4)")) === said("someBlanksRight", { right: 1, count: 2 }))
      const marks = await evaluate("Array.from(window.__quiz.quiz(4).querySelectorAll('.plantoir-quiz-mark')).map((mark) => mark.textContent)")
      expect("each blank is marked in words and a sign", JSON.stringify(marks) === JSON.stringify([said("markWrong"), said("markRight")]), marks)
      const invalid = await evaluate("Array.from(window.__quiz.quiz(4).querySelectorAll('input.plantoir-quiz-blank')).map((box) => box.getAttribute('aria-invalid'))")
      expect("each blank carries aria-invalid", JSON.stringify(invalid) === '["true","false"]', invalid)
      const labels = await evaluate("Array.from(window.__quiz.quiz(4).querySelectorAll('input.plantoir-quiz-blank')).map((box) => box.getAttribute('aria-label'))")
      expect("the blanks are labelled Blank n of count", JSON.stringify(labels) === JSON.stringify([said("blankLabel", { n: 1, count: 2 }), said("blankLabel", { n: 2, count: 2 })]), labels)
      await evaluate("window.__quiz.type(4, ['100.7', 'sea level']); window.__quiz.press(4, 'check')")
      expect("100.7 is inside 100 ± 1", (await evaluate("window.__quiz.feedback(4)")) === said("right"))

      // ±3 is an answer, typed as +-3 (S8).
      await evaluate("window.__quiz.type(8, ['+-3']); window.__quiz.press(8, 'check')")
      expect("+-3 matches ±3", (await evaluate("window.__quiz.feedback(8)")) === said("right"))
      // Enter in a box is Check.
      await evaluate("window.__quiz.type(8, ['4'])")
      await evaluate("window.__quiz.quiz(8).querySelector('input.plantoir-quiz-blank').focus()")
      await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 })
      await send("Input.dispatchKeyEvent", { type: "char", key: "Enter", text: "\r" })
      await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 })
      await pause(200)
      expect("Enter in a box checks it", (await evaluate("window.__quiz.feedback(8)")) === said("notRight"))

      // 4. Folding by keyboard, a figure-only choice's name, Run in a choice.
      const fold = await evaluate("(() => { const quiz = window.__quiz.quiz(6); const title = quiz.querySelector(':scope > .callout-title'); const content = quiz.querySelector(':scope > .callout-content'); return { role: title.getAttribute('role'), tabindex: title.getAttribute('tabindex'), expanded: title.getAttribute('aria-expanded'), inert: content.inert, collapsed: quiz.classList.contains('is-collapsed') } })()")
      expect("a folded quiz's title is a closed button and its content inert (S6)", fold.role === "button" && fold.tabindex === "0" && fold.expanded === "false" && fold.inert === true && fold.collapsed, fold)
      await evaluate("window.__quiz.quiz(6).querySelector(':scope > .callout-title').focus()")
      await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 })
      await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 })
      await pause(500)
      const opened = await evaluate("(() => { const quiz = window.__quiz.quiz(6); return { expanded: quiz.querySelector(':scope > .callout-title').getAttribute('aria-expanded'), inert: quiz.querySelector(':scope > .callout-content').inert, collapsed: quiz.classList.contains('is-collapsed') } })()")
      expect("Enter on the title opens the quiz and its content is no longer inert", opened.expanded === "true" && opened.inert === false && !opened.collapsed, opened)
      const figureName = await evaluate("(() => { const input = window.__quiz.quiz(6).querySelector('.plantoir-quiz-choice[data-choice=\"0\"] input'); const label = input.closest('label').textContent.trim(); const described = document.getElementById(input.getAttribute('aria-describedby'))?.querySelector('figcaption')?.textContent; return { label, described } })()")
      expect("a choice whose words are 'Graph A' is described by its graph's description (S7)", figureName.label === "Graph A" && figureName.described === "an upward parabola", figureName)
      const imageName = await evaluate("window.__quiz.quiz(7).querySelector('.plantoir-quiz-choice[data-choice=\"2\"] .plantoir-quiz-choice-text').textContent.trim()")
      expect("a choice with words keeps its words", imageName === "A picture", imageName)
      const runInChoice = await evaluate("(() => { const choice = window.__quiz.quiz(7).querySelector('.plantoir-quiz-choice[data-choice=\"0\"]'); const run = choice.querySelector('.plantoir-runner-run'); if (!run) return 'no Run button'; run.click(); return choice.querySelector('input.plantoir-quiz-input').checked })()")
      expect("pressing Run on code in a choice does not tick it", runInChoice === false, runInChoice)

      // 2. Nothing from another website; answering asked the site for
      // nothing but the graph engine (and the code's, for the Run above).
      const asked = siteServer.requests.slice(loadedRequests).filter((path) => !path.includes("/static/function-plot/") && !path.includes("/static/pyodide/"))
      expect("answering asked the site for nothing", asked.length === 0, asked)
      expect("answering asked no other website for anything", offSite.length === loadedOffSite, offSite.slice(loadedOffSite))

      // 3. The shuffle, and ⌘P's order.
      const orders = new Set()
      for (let load = 0; load < 20; load += 1) {
        await open(playground)
        orders.add(JSON.stringify(await evaluate("window.__quiz.order(5)")))
      }
      expect("a shuffled quiz comes out in more than one order over twenty loads", orders.size > 1, [...orders])
      const unshuffled = await evaluate("window.__quiz.order(2)")
      expect("a quiz without |shuffle keeps Markdown order", JSON.stringify(unshuffled) === "[0,1,2]", unshuffled)
      await evaluate("window.dispatchEvent(new Event('beforeprint'))")
      const printOrder = await evaluate("window.__quiz.order(5)")
      expect("⌘P puts the choices back in Markdown order", JSON.stringify(printOrder) === "[0,1,2,3,4]", printOrder)
      await evaluate("window.dispatchEvent(new Event('afterprint'))")

      // 8a. On paper.
      await send("Emulation.setEmulatedMedia", { media: "print", features: [{ name: "prefers-color-scheme", value: "light" }] })
      const paper = await evaluate(`(() => {
        const quiz = window.__quiz.quiz(2)
        const shown = (selector) => Array.from(quiz.querySelectorAll(selector)).some((element) => getComputedStyle(element).display !== "none")
        const label = quiz.querySelector(".plantoir-quiz-choice-label")
        return {
          actions: shown(".plantoir-quiz-actions"), feedback: shown(".plantoir-quiz-feedback"),
          explain: shown(".plantoir-quiz-explain"), answer: Array.from(document.querySelectorAll(".plantoir-quiz-answer")).some((element) => getComputedStyle(element).display !== "none"),
          input: shown("input.plantoir-quiz-input"), circle: getComputedStyle(label, "::before").content,
          square: getComputedStyle(window.__quiz.quiz(3).querySelector(".plantoir-quiz-choice-label"), "::before").content,
        }
      })()`)
      await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
      expect("on paper no button, feedback, answer or explanation shows, and boxes are drawn empty",
        !paper.actions && !paper.feedback && !paper.explain && !paper.answer && !paper.input && paper.circle === '"○"' && paper.square === '"□"', paper)

      // 5. The score.
      await open(playground)
      await evaluate("window.localStorage.clear()")
      await open(playground)
      expect("no score before anything is answered", await evaluate("document.querySelector('.plantoir-quiz-score').hidden"))
      await evaluate("window.__quiz.choose(2, [1]); window.__quiz.press(2, 'check')")
      await evaluate("window.__quiz.choose(3, [0]); window.__quiz.press(3, 'check')")
      await evaluate("window.__quiz.choose(3, [0, 2]); window.__quiz.press(3, 'check')")
      await evaluate("window.__quiz.press(4, 'show')")
      const scored = await evaluate("document.querySelector('.plantoir-quiz-score-line').textContent")
      expect("the score counts right on the first try only", scored === said("score", { right: 1, total: 8 }), scored)
      await open(playground)
      const kept = await evaluate("({ hidden: document.querySelector('.plantoir-quiz-score').hidden, line: document.querySelector('.plantoir-quiz-score-line').textContent })")
      expect("the score is kept across a reload", !kept.hidden && kept.line === said("score", { right: 1, total: 8 }), kept)
      const stored = await evaluate("Object.keys(localStorage).filter((key) => key.startsWith('plantoir:quiz:'))")
      expect("the score is kept under plantoir:quiz:<root>:<slug>", JSON.stringify(stored) === '["plantoir:quiz:/:Quiz-Playground"]', stored)
      await evaluate("document.querySelector('.plantoir-quiz-start-again').click()")
      const cleared = await evaluate("({ hidden: document.querySelector('.plantoir-quiz-score').hidden, stored: localStorage.getItem('plantoir:quiz:/:Quiz-Playground'), feedback: window.__quiz.feedback(2), ticked: window.__quiz.quiz(2).querySelectorAll('input:checked').length })")
      expect("Start again clears the score and the answers", cleared.hidden && cleared.stored === null && cleared.feedback === "" && cleared.ticked === 0, cleared)

      // 6. Five changes of page, then back.
      await open(playground)
      const before = await listenersOn("window")
      for (let step = 0; step < 5; step += 1) {
        await evaluate(`window.spaNavigate(new URL(${JSON.stringify(base + "/Quiz-Host.html")}))`)
        await pause(700)
        await evaluate(`window.spaNavigate(new URL(${JSON.stringify(playground)}))`)
        await pause(700)
      }
      await evaluate(PAGE_HELPERS)
      const after = await listenersOn("window")
      expect("five page changes leave one listener for printing", (after.beforeprint ?? 0) === (before.beforeprint ?? 0) && (after.afterprint ?? 0) === (before.afterprint ?? 0), { before, after })
      const root = await listenersOn("window.__quiz.quiz(2)")
      expect("each quiz has one set of listeners after five page changes", root.click === 1 && root.keydown === 1 && root.input === 1, root)
      const rowsAfter = await evaluate("Array.from(document.querySelectorAll('.plantoir-quiz')).map((quiz) => quiz.querySelectorAll('.plantoir-quiz-actions').length).join(',')")
      expect("and one row of buttons each", rowsAfter === "1,1,1,1,1,1,1,1", rowsAfter)
      await evaluate("window.__quiz.choose(2, [1]); window.__quiz.press(2, 'check')")
      expect("a quiz still checks after the page changes", (await evaluate("window.__quiz.feedback(2)")) === said("right"))

      // 7. Transclusion.
      await open(base + "/Quiz-Host.html")
      const host = await evaluate(`(() => {
        const quizzes = Array.from(document.querySelectorAll(".plantoir-quiz"))
        const ids = Array.from(document.querySelectorAll("[id]")).map((element) => element.id)
        const names = quizzes.map((quiz) => quiz.querySelector("input.plantoir-quiz-input").name)
        const labelled = quizzes.map((quiz) => document.getElementById(quiz.querySelector("fieldset").getAttribute("aria-labelledby"))?.textContent.trim())
        return { count: quizzes.length, duplicateIds: ids.length - new Set(ids).size, names, labelled, sources: quizzes.map((quiz) => quiz.dataset.quizSource) }
      })()`)
      expect("a transcluded quiz has ids, a label and a radio group of its own (S5)",
        host.count === 2 && host.duplicateIds === 0 && host.names[0] !== host.names[1] && /Host question/.test(host.labelled[0]) && /Source question/.test(host.labelled[1]), host)
      await evaluate("document.querySelectorAll('.plantoir-quiz')[1].querySelector('.plantoir-quiz-choice[data-choice=\"0\"] input').checked = true; document.querySelectorAll('.plantoir-quiz')[1].querySelector('.plantoir-quiz-check').click()")
      const hostSaved = await evaluate("JSON.parse(localStorage.getItem('plantoir:quiz:/:Quiz-Host') || '{}')")
      expect("a transcluded quiz is scored under its own page's name", hostSaved?.quizzes?.["Quiz-Source#1"]?.firstTry === true && !("Quiz-Host#1" in (hostSaved?.quizzes ?? {})), hostSaved)

      // 5b. Storage refused.
      await send("Page.addScriptToEvaluateOnNewDocument", {
        source: "Object.defineProperty(window, 'localStorage', { get() { throw new Error('refused') } })",
      })
      await open(playground)
      await evaluate("window.__quiz.choose(2, [1]); window.__quiz.press(2, 'check')")
      expect("with storage refused a quiz still checks", (await evaluate("window.__quiz.feedback(2)")) === said("right"))
      await evaluate("window.__quiz.type(4, ['100', 'standard']); window.__quiz.press(4, 'check')")
      expect("and a blank too", (await evaluate("window.__quiz.feedback(4)")) === said("right"))

      // 8b. The printable page's handout (fresh target so storage works again).
      const fresh = await (await fetch(`http://127.0.0.1:${devtools}/json/new?about:blank`, { method: "PUT" })).json()
      notes.push(`handout check in a fresh tab ${fresh.id}`)
      problems.push(...(await checkHandout(fresh.webSocketDebuggerUrl, base + "/Quiz-Printable.html#plantoir-print=withAnswersAtTheEnd&paper=portrait")))

      clearTimeout(timer)
      if (problems.length > 0) {
        return finish(1, "FAIL: " + problems.join("; "))
      }
      finish(0, `OK: 8 quizzes, every kind wrong then right, the shuffle in ${orders.size} orders over 20 loads, the score kept and cleared, five page changes clean, a transcluded quiz on its own, paper and the handout questions only`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}

// The handout as the page prints it: caught in its frame at the moment it
// prints, the way print_handout.mjs catches it.
async function checkHandout(url, pageUrl) {
  const socket = new WebSocket(url)
  let id = 0
  const waiting = new Map()
  const send = (method, params = {}) => new Promise((resolve) => {
    id += 1
    waiting.set(id, resolve)
    socket.send(JSON.stringify({ id, method, params }))
  })
  await new Promise((resolve) => (socket.onopen = resolve))
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
  await send("Page.enable")
  await send("Page.addScriptToEvaluateOnNewDocument", {
    source: `new MutationObserver((changes) => { for (const change of changes) for (const node of change.addedNodes) {
      if (node.tagName === "IFRAME") node.contentWindow.print = () => { window.__handout = node.contentDocument.body.innerText } } })
      .observe(document, { childList: true, subtree: true })`,
  })
  await send("Page.navigate", { url: pageUrl })
  let text = null
  for (let tries = 0; tries < 240 && text === null; tries += 1) {
    await pause(250)
    text = (await evaluate("window.__handout ?? null")) ?? null
  }
  socket.close()
  const problems = []
  if (text === null) {
    problems.push("the printable page's handout was never printed")
    return problems
  }
  if (!/Which is a factor of/.test(text)) problems.push("the handout lost a quiz's question")
  if (/printable-answer-7f3a/.test(text)) problems.push("a quiz's answer is in the handout")
  if (/printable-explain-7f3a/.test(text)) problems.push("a quiz's explanation is in the handout")
  if (/Show answer|\bCheck\b/.test(text)) problems.push("a quiz's buttons are in the handout: " + JSON.stringify(text.slice(0, 1500)))
  if (!/x\^2 \+ x - 6|x2\+x−6|x\s*2\s*\+\s*x\s*−\s*6/.test(text)) problems.push("the page's own folded answer is missing from the key")
  return problems
}
