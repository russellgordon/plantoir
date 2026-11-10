// Text that wraps (#653, contracts/shared-rules.json -> textFenceWrapping),
// read off the BUILT Wrap Fixture page in headless Chrome for Testing. How a
// wrapped line looks - where its rows start, where its number and its
// ellipses sit - is layout, so no text search of the site can see it: this
// is why the check needs a browser.
//
// At 1512 x 900 in light, then dark (emulated, page reloaded), then at a
// phone's 390 px:
//
// 1. FIRST: the long ```text wrap block is inside div.plantoir-text-wrap and
//    does NOT scroll (Quartz scrolls `pre > code`, so its code's scrollWidth
//    is read) - so a site without the change, or without the wrapper, fails
//    here and says so;
// 2. the ```text and ```python wrap blocks DO scroll, every line one row;
// 3. the long block: --plantoir-digits 3; every line's rows (its height over
//    the line-height) are the rows its text sits on; every row of every line
//    starts at one x, a one-row line's; lines 2, 100, 101, 102 and 103 wrap;
//    line 101 (one unbreakable URL) has text on its FIRST row;
// 4. each line's two pseudo-elements, by their boxes (CDP): the number's box
//    starts at the line's top and is one row high; the ellipses' box runs
//    the line's full height; its content is the ellipsis string; the two
//    share one right edge (one hairline);
// 5. the highlighted lines 2 and 101 keep their tint over every row;
// 6. the folded callout's block (opened by a click), the list item's and the
//    quiz explanation's (shown by answering the quiz) wrap too;
//
// then, once, at 1512:
//
// 7. under print media the long block's lines are laid out as the plain
//    block's are (padding, white-space, no ellipses: print.scss governs); and
//    on screen, a <pre> marked plantoir-flowing (what the handout does to
//    each block) gets none of it;
// 8. the page's copy button, pressed by a REAL pointer (CDP Input events:
//    moved onto the block, then moved, pressed and released at the button's
//    centre), copies the long block as written: 120 lines, no ellipsis, no
//    line break where a line wrapped (plan review finding 5); the button is
//    what a pointer at its centre hits, the write resolves and the clipboard
//    reads it back; the plain block beside it is pressed the same way; and
//    the must-fail: the button stacked as before #759 must be missed (#759).
//    Pressed again at 390 px.
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
// Nothing waits a fixed time for layout: each wait polls for what it needs.
//
//   node browser-checks/text_wrap.mjs <chrome> <Wrap Fixture page url>

import { spawn } from "node:child_process"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const [chromePath, pageUrl] = process.argv.slice(2)
if (!chromePath || !pageUrl) {
  console.error("usage: node text_wrap.mjs <chrome> <Wrap Fixture page url>")
  process.exit(2)
}

// Sub-pixel layout: two rows that start "at one x" may differ by a fraction.
const TOLERANCE = 0.5
const LINES = 120
const WRAPPING_LINES = [2, 100, 101, 102, 103]
const HIGHLIGHTED_LINES = [2, 101]
const URL_LINE = 101
// Written to the clipboard before each press of a copy button (step 8).
const SENTINEL = "plantoir-text-wrap-check: nothing copied yet"

const work = mkdtempSync(join(tmpdir(), "plantoir-text-wrap-check-"))
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

const timer = setTimeout(() => finish(1, "FAIL: the text blocks were not checked within 120 s"), 120000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// In the page: the helpers every step below uses. Defined once per load.
const HELPERS = `
(() => {
  const figures = () => Array.from(document.querySelectorAll("article figure[data-rehype-pretty-code-figure]"))
  const codeOf = (figure) => figure.querySelector("pre > code")
  const linesOf = (figure) => Array.from(codeOf(figure).querySelectorAll(":scope > [data-line]"))
  const lineHeight = (figure) => parseFloat(getComputedStyle(codeOf(figure)).lineHeight)
  const scrolls = (figure) => {
    const code = codeOf(figure)
    const pre = figure.querySelector("pre")
    return code.scrollWidth > code.clientWidth || pre.scrollWidth > pre.clientWidth
  }
  // The rows a line's TEXT sits on (a Range over its contents, so the
  // pseudo-elements are not counted), and where each row starts.
  const rowsOf = (line) => {
    const range = document.createRange()
    range.selectNodeContents(line)
    const rects = Array.from(range.getClientRects()).filter((rect) => rect.width > 0)
    const tops = []
    for (const rect of rects) {
      const top = Math.round(rect.top)
      if (!tops.includes(top)) tops.push(top)
    }
    tops.sort((a, b) => a - b)
    const lefts = []
    for (const top of tops) {
      let left = Infinity
      for (const rect of rects) if (Math.round(rect.top) === top && rect.left < left) left = rect.left
      lefts.push(left)
    }
    return { tops, lefts }
  }
  const measure = (figure) => {
    const lh = lineHeight(figure)
    const out = []
    for (const line of linesOf(figure)) {
      const box = line.getBoundingClientRect()
      const text = rowsOf(line)
      out.push({
        top: box.top, bottom: box.bottom, height: box.height,
        rows: Math.round(box.height / lh), textRows: text.tops.length,
        firstTextTop: text.tops.length ? text.tops[0] - box.top : null,
        lefts: text.lefts,
        background: getComputedStyle(line).backgroundColor,
        after: getComputedStyle(line, "::after").content,
      })
    }
    return { lh, lines: out }
  }
  window.__wrap = { figures, codeOf, linesOf, lineHeight, scrolls, rowsOf, measure }
  return true
})()
`

let buffered = ""
chrome.stderr.on("data", (chunk) => {
  connect(chunk).catch((error) => finish(1, "FAIL: could not drive the browser: " + (error && error.stack || error)))
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
      waiting.get(message.id)(message.result ?? { error: message.error })
      waiting.delete(message.id)
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    if (answer?.exceptionDetails) throw new Error("in the page: " + JSON.stringify(answer.exceptionDetails).slice(0, 600))
    return answer?.result?.value
  }
  const until = async (expression, tries = 80) => {
    for (let attempt = 0; attempt < tries; attempt += 1) {
      const value = await evaluate(expression)
      if (value) return value
      await pause(100)
    }
    return null
  }
  const open = async () => {
    await send("Page.navigate", { url: pageUrl })
    if (!(await until(`document.readyState === "complete"`))) return false
    if (!(await until(`document.querySelectorAll("article figure[data-rehype-pretty-code-figure]").length >= 6`))) return false
    await evaluate("document.fonts.ready.then(() => true)")
    // The copy buttons are Quartz's own, added on its "nav" event.
    if (!(await until(`document.querySelector("article pre > .clipboard-button") !== null`))) return false
    await evaluate(HELPERS)
    await send("DOM.getDocument", { depth: -1 })
    return true
  }
  // A line's ::before or ::after box, read by CDP: its border quad.
  const pseudoBox = async (figureIndex, lineIndex, which) => {
    const handle = await send("Runtime.evaluate", { expression: `window.__wrap.linesOf(window.__wrap.figures()[${figureIndex}])[${lineIndex}]` })
    const objectId = handle?.result?.objectId
    if (!objectId) return null
    const described = await send("DOM.describeNode", { objectId, depth: 1 })
    const pseudo = (described?.node?.pseudoElements || []).find((node) => node.pseudoType === which)
    if (!pseudo) return null
    const model = await send("DOM.getBoxModel", { backendNodeId: pseudo.backendNodeId })
    const quad = model?.model?.border
    if (!quad) return null
    const xs = [quad[0], quad[2], quad[4], quad[6]]
    const ys = [quad[1], quad[3], quad[5], quad[7]]
    return { left: Math.min(...xs), right: Math.max(...xs), top: Math.min(...ys), bottom: Math.max(...ys) }
  }

  await new Promise((resolve) => { socket.onopen = resolve })

  // The clipboard, for step 8: granted to the page's origin through the
  // browser's own endpoint, and the page given focus, which a clipboard
  // call needs and a headless page does not otherwise have.
  const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()
  const browserSocket = new WebSocket(version.webSocketDebuggerUrl)
  await new Promise((resolve) => { browserSocket.onopen = resolve })
  const granted = await new Promise((resolve) => {
    browserSocket.onmessage = (event) => resolve(JSON.parse(event.data))
    browserSocket.send(JSON.stringify({ id: 1, method: "Browser.grantPermissions",
      params: { origin: new URL(pageUrl).origin, permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"] } }))
  })
  // Left open to the end: Chrome drops a session's permission overrides when
  // that session closes (measured: closed here, readText was refused).
  if (granted.error) return finish(1, "FAIL: the clipboard could not be granted to the page: " + JSON.stringify(granted.error))
  await send("Emulation.setFocusEmulationEnabled", { enabled: true })

  const problems = []
  const report = {}

  // Steps 1 to 6, in whatever the window is now.
  const checkTheBlocks = async (where) => {
    const said = (text) => problems.push(`${where}: ${text}`)
    // 1. FIRST: the flagged block wraps.
    const first = await evaluate(`(() => {
      const figure = window.__wrap.figures()[0]
      return { wrapped: !!figure.closest(".plantoir-text-wrap"), scrolls: window.__wrap.scrolls(figure),
               lines: window.__wrap.linesOf(figure).length }
    })()`)
    if (!first.wrapped || first.scrolls) {
      said(`the long text wrap block ${first.wrapped ? "is in its wrapper" : "is in no wrapper"} and ${first.scrolls ? "scrolls sideways" : "does not scroll"} (it must be wrapped and not scroll)`)
      return
    }
    if (first.lines !== LINES) said(`the long block has ${first.lines} lines, expected ${LINES}`)
    // 2. The text and python wrap blocks scroll, a row per line.
    for (const [index, name] of [[1, "the plain text block"], [2, "the python wrap block"]]) {
      const plain = await evaluate(`(() => {
        const figure = window.__wrap.figures()[${index}]
        const m = window.__wrap.measure(figure)
        return { wrapped: !!figure.closest(".plantoir-text-wrap"), scrolls: window.__wrap.scrolls(figure), rows: m.lines.map((line) => line.rows) }
      })()`)
      if (plain.wrapped || !plain.scrolls || plain.rows.some((rows) => rows !== 1)) {
        said(`${name} ${plain.wrapped ? "is wrapped" : "is not wrapped"}, ${plain.scrolls ? "scrolls" : "does NOT scroll"}, rows ${JSON.stringify(plain.rows)} (it must scroll, one row a line)`)
      }
    }
    // 3. The long block's rows.
    const block = await evaluate(`(() => {
      const figure = window.__wrap.figures()[0]
      return { digits: getComputedStyle(window.__wrap.codeOf(figure)).getPropertyValue("--plantoir-digits").trim(), ...window.__wrap.measure(figure) }
    })()`)
    if (block.digits !== "3") said(`--plantoir-digits is ${JSON.stringify(block.digits)}, expected 3`)
    const oneRow = block.lines.find((line) => line.rows === 1)
    const x = oneRow ? oneRow.lefts[0] : null
    let rowsInAll = 0
    let leftsOff = 0
    block.lines.forEach((line, index) => {
      const number = index + 1
      rowsInAll += line.rows
      if (line.rows !== line.textRows) said(`line ${number}: ${line.rows} rows high, its text on ${line.textRows}`)
      for (const left of line.lefts) if (x === null || Math.abs(left - x) > TOLERANCE) leftsOff += 1
      if (WRAPPING_LINES.includes(number) && line.rows < 2) said(`line ${number} did not wrap (${line.rows} row)`)
      if (!WRAPPING_LINES.includes(number) && line.rows !== 1) said(`line ${number} wrapped onto ${line.rows} rows`)
    })
    if (leftsOff > 0) said(`${leftsOff} rows do not start at the one-row lines' x (${x})`)
    const url = block.lines[URL_LINE - 1]
    if (url.firstTextTop === null || url.firstTextTop > block.lh / 2) said(`line ${URL_LINE} (one unbreakable run) has no text on its first row (its text starts ${url.firstTextTop} px down)`)
    // 4. The pseudo-elements' boxes, every line.
    let pseudoProblems = 0
    let firstPseudoProblem = null
    for (let index = 0; index < block.lines.length; index += 1) {
      const line = block.lines[index]
      const number = await pseudoBox(0, index, "before")
      const ellipses = await pseudoBox(0, index, "after")
      const wrong = []
      if (!number) wrong.push("no number box")
      else {
        if (Math.abs(number.top - line.top) > TOLERANCE) wrong.push(`the number is ${(number.top - line.top).toFixed(2)} px below the line's top`)
        if (Math.abs((number.bottom - number.top) - block.lh) > 1) wrong.push(`the number's box is ${(number.bottom - number.top).toFixed(2)} px high, a row is ${block.lh}`)
      }
      if (!ellipses) wrong.push("no ellipsis box")
      else {
        if (Math.abs(ellipses.top - line.top) > TOLERANCE || Math.abs(ellipses.bottom - line.bottom) > TOLERANCE) wrong.push(`the ellipses run ${ellipses.top.toFixed(2)}-${ellipses.bottom.toFixed(2)}, the line ${line.top.toFixed(2)}-${line.bottom.toFixed(2)}`)
        if (number && Math.abs(ellipses.right - number.right) > TOLERANCE) wrong.push(`the ellipses' right edge ${ellipses.right.toFixed(2)} is not the number's ${number.right.toFixed(2)}`)
      }
      if (!line.after.includes("…") || !line.after.startsWith('"\\a')) wrong.push(`its ::after content is ${line.after.slice(0, 30)}`)
      if (wrong.length) {
        pseudoProblems += 1
        if (firstPseudoProblem === null) firstPseudoProblem = `line ${index + 1}: ${wrong.join("; ")}`
      }
    }
    if (pseudoProblems) said(`${pseudoProblems} lines' number or ellipses are out of place, first ${firstPseudoProblem}`)
    // 5. Highlighted lines keep their tint over every row.
    for (const number of HIGHLIGHTED_LINES) {
      const line = block.lines[number - 1]
      if (line.background === "rgba(0, 0, 0, 0)" || line.background === "transparent") said(`highlighted line ${number} has no tint`)
    }
    // 6. The callout's, the list item's and the quiz explanation's blocks.
    const shown = await evaluate(`(async () => {
      const figures = window.__wrap.figures()
      const callout = figures[3].closest(".callout")
      if (callout && callout.classList.contains("is-collapsed")) callout.querySelector(".callout-title").click()
      const quiz = figures[5].closest(".plantoir-quiz")
      const explain = figures[5].closest(".plantoir-quiz-explain")
      if (quiz && explain && explain.hidden) {
        quiz.querySelector('.plantoir-quiz-choice[data-choice="0"] input').checked = true
        quiz.querySelector(".plantoir-quiz-check").click()
      }
      return { callout: !!callout, quiz: !!quiz, explain: !!explain }
    })()`)
    if (!shown.callout || !shown.quiz || !shown.explain) said(`the folded callout, the quiz or its explanation is missing: ${JSON.stringify(shown)}`)
    for (const [index, name] of [[3, "the folded callout's block"], [4, "the list item's block"], [5, "the quiz explanation's block"]]) {
      const settled = await until(`(() => {
        const figure = window.__wrap.figures()[${index}]
        const box = figure.getBoundingClientRect()
        return box.width > 0 && box.height > 0
      })()`, 40)
      if (!settled) {
        said(`${name} was never shown`)
        continue
      }
      const nested = await evaluate(`(() => {
        const figure = window.__wrap.figures()[${index}]
        const m = window.__wrap.measure(figure)
        return { wrapped: !!figure.closest(".plantoir-text-wrap"), scrolls: window.__wrap.scrolls(figure), rows: m.lines[0].rows, textRows: m.lines[0].textRows, after: m.lines[0].after.slice(0, 4) }
      })()`)
      if (!nested.wrapped || nested.scrolls || nested.rows < 2 || nested.rows !== nested.textRows || !nested.after.startsWith('"\\a')) {
        said(`${name} does not wrap: ${JSON.stringify(nested)}`)
      }
    }
    report[where] = { rows: rowsInAll, lineHeight: block.lh, x: x === null ? null : +x.toFixed(2), urlRows: url.rows }
  }

  // 8. A press of a block's copy button the way a person makes it: the
  // pointer moves onto the block (Quartz shows the button on pre:hover),
  // then moves, presses and releases at the button's centre, with CDP's
  // Input events, which the browser hit-tests as it does a mouse's. What
  // the press writes is taken from the argument of a PASS-THROUGH
  // writeText (it still calls the real one, and its promise must resolve),
  // never a stub, which would hide a refused write. Before each press a
  // sentinel is written to the clipboard (through the real writeText, so it
  // is not counted as the press's); after it the clipboard is read back and
  // must hold what the press wrote, not the sentinel - so a failure says
  // which half broke: the press (no write), the write (refused), or the
  // clipboard (not what was written). Measured 2026-11-10 with Chrome for
  // Testing 155 --headless=new on macOS 26: that clipboard is the headless
  // browser's own, not the Mac's pasteboard (pbpaste unchanged by a run).
  const pressCopy = async (figureIndex) => {
    const placed = await evaluate(`(async () => {
      if (!window.__copies) {
        window.__copies = []
        const real = navigator.clipboard.writeText.bind(navigator.clipboard)
        window.__realWriteText = real
        navigator.clipboard.writeText = (value) => {
          const entry = { text: value, state: "pending" }
          window.__copies.push(entry)
          return real(value).then((result) => { entry.state = "resolved"; return result },
                                  (error) => { entry.state = "rejected: " + error; throw error })
        }
      }
      await window.__realWriteText(${JSON.stringify(SENTINEL)})
      const pre = window.__wrap.figures()[${figureIndex}].querySelector("pre")
      // The button sits at the block's top right: bring that top into view.
      window.scrollBy({ top: pre.getBoundingClientRect().top - innerHeight / 3, behavior: "instant" })
      const box = pre.getBoundingClientRect()
      return { x: box.left + box.width / 2, y: box.top + 8, copies: window.__copies.length }
    })()`)
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: placed.x, y: placed.y })
    const shown = await until(`getComputedStyle(window.__wrap.figures()[${figureIndex}].querySelector("pre > .clipboard-button")).opacity === "1"`, 30)
    const aim = await evaluate(`(() => {
      const figure = window.__wrap.figures()[${figureIndex}]
      const button = figure.querySelector("pre > .clipboard-button")
      const box = button.getBoundingClientRect()
      const x = box.left + box.width / 2, y = box.top + box.height / 2
      const hit = document.elementFromPoint(x, y)
      // The rows whose LETTERS the button lies over, line by line (for
      // knownLimits): measured 2026-11-10, a 30.8 px button over 25.6 px
      // rows reaches 2 px into the second row's box, above its letters.
      const under = []
      for (const [index, line] of window.__wrap.linesOf(figure).entries()) {
        const rect = line.getBoundingClientRect()
        if (rect.top >= box.bottom) break
        if (rect.bottom > box.top) {
          const rows = window.__wrap.rowsOf(line).tops
          let count = 0
          for (const top of rows) if (top < box.bottom && top + window.__wrap.lineHeight(figure) > box.top) count += 1
          under.push({ line: index + 1, rows: count })
        }
      }
      return { x, y, height: +box.height.toFixed(2), inside: !!hit && button.contains(hit),
               hit: hit ? hit.tagName.toLowerCase() + (hit.hasAttribute("data-line") ? "[data-line]" : "") + " in " + (hit.parentElement ? hit.parentElement.tagName.toLowerCase() : "nothing") : "nothing",
               under }
    })()`)
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: aim.x, y: aim.y })
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: aim.x, y: aim.y, button: "left", buttons: 1, clickCount: 1 })
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: aim.x, y: aim.y, button: "left", buttons: 0, clickCount: 1 })
    const settled = await until(`window.__copies.length > ${placed.copies} && window.__copies[window.__copies.length - 1].state !== "pending"`, 20)
    const copy = settled ? await evaluate(`window.__copies[window.__copies.length - 1]`) : null
    const readBack = await evaluate(`navigator.clipboard.readText().then((text) => text, (error) => "READ FAILED: " + error)`)
    // Move off, so the button hides again before the next press.
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: 1, y: 1 })
    return { shown: !!shown, ...aim, copy, readBack }
  }
  const asWritten = (copied) => {
    const lines = copied.replace(/\n$/, "").split("\n")
    const url = "https://example.com/" + "a".repeat(400)
    const wrong = []
    if (copied.includes("…")) wrong.push("it holds an ellipsis")
    if (lines.length !== LINES) wrong.push(`${lines.length} lines, not ${LINES}`)
    if (lines[URL_LINE - 1] !== url) wrong.push(`line ${URL_LINE} is ${JSON.stringify((lines[URL_LINE - 1] || "").slice(0, 40))}…`)
    if (lines[0] !== "line 1" || lines[LINES - 1] !== `line ${LINES}`) wrong.push("its first or last line is not as written")
    if (lines[1] !== lines[99] || lines[1].length < 200 || lines[101] !== "    " + lines[1] || lines[102] !== "\t" + lines[1]) wrong.push("a long line is not whole")
    return wrong
  }
  const checkTheCopyButton = async (where, withTheMustFail) => {
    const said = (text) => problems.push(`${where}: ${text}`)
    const pressed = []
    // The long wrapped block, then the plain one beside it as the comparison.
    for (const [index, name] of [[0, "the long text wrap block"], [1, "the plain text block"]]) {
      const press = await pressCopy(index)
      pressed.push(press)
      if (!press.shown) said(`${name}'s copy button did not appear when the pointer moved onto the block`)
      if (!press.inside) {
        said(`a pointer at the centre of ${name}'s copy button hits ${press.hit}, not the button, so pressing it copies nothing`)
        continue
      }
      if (!press.copy) {
        said(`${name}'s copy button, pressed, wrote nothing to the clipboard`)
        continue
      }
      if (press.copy.state !== "resolved") said(`${name}'s clipboard write did not succeed: ${press.copy.state}`)
      if (press.readBack !== press.copy.text) said(`the clipboard read back after ${name}'s press is not what it wrote (${press.readBack === SENTINEL ? "it still holds the sentinel" : String(press.readBack).slice(0, 200)})`)
      if (index === 0) {
        const wrong = asWritten(press.copy.text)
        if (wrong.length) said(`the copy button's text is not the block as written: ${wrong.join("; ")}`)
      } else {
        const lines = press.copy.text.replace(/\n$/, "").split("\n")
        if (lines.length !== 2 || lines[1] !== "short" || lines[0].length < 200) said(`the plain block's copy is not its two lines as written`)
      }
    }
    const wrapped = pressed[0]
    report[`copy, ${where}`] = { button: wrapped.height, under: wrapped.under, characters: wrapped.copy ? wrapped.copy.text.length : null }
    if (!withTheMustFail) return
    // The must-fail: the same press with the button stacked as it was before
    // #759 (z-index auto, the pre not isolated) must MISS - hit a line, and
    // write nothing - or the press above proves nothing.
    await evaluate(`(() => {
      const pre = window.__wrap.figures()[0].querySelector("pre")
      pre.style.isolation = "auto"
      pre.querySelector(":scope > .clipboard-button").style.zIndex = "auto"
      return true
    })()`)
    const old = await pressCopy(0)
    await evaluate(`(() => {
      const pre = window.__wrap.figures()[0].querySelector("pre")
      pre.style.isolation = ""
      pre.querySelector(":scope > .clipboard-button").style.zIndex = ""
      return true
    })()`)
    if (old.inside || old.copy || old.readBack !== SENTINEL) said(`must-fail did not fail: with the copy button stacked as before #759 a real press ${old.inside ? "still reached the button" : "hit " + old.hit}${old.copy ? " and copied" : ""}${old.readBack !== SENTINEL ? " and the clipboard lost the sentinel" : ""}, so the press check proves nothing`)
    report.mustFail = { hit: old.hit, copied: !!old.copy, sentinelKept: old.readBack === SENTINEL }
  }

  try {
    await send("Page.enable")
    await send("DOM.enable")
    await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
    if (!(await open())) return finish(1, "FAIL: Wrap Fixture did not load: " + pageUrl)
    await checkTheBlocks("light, 1512 px")

    // How many characters a row holds at this width (for knownLimits).
    report.charactersPerRow = await evaluate(`(() => {
      const figure = window.__wrap.figures()[0]
      const line = window.__wrap.linesOf(figure)[0]
      const probe = document.createElement("span")
      probe.textContent = "a".repeat(200)
      probe.style.whiteSpace = "pre"
      window.__wrap.codeOf(figure).appendChild(probe)
      const ch = probe.getBoundingClientRect().width / 200
      probe.remove()
      const style = getComputedStyle(line)
      const room = line.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)
      return Math.floor(room / ch)
    })()`)

    // 7. Print media: print.scss governs, exactly as for the plain block.
    await send("Emulation.setEmulatedMedia", { media: "print", features: [{ name: "prefers-color-scheme", value: "light" }] })
    const paper = await evaluate(`(() => {
      const read = (index) => {
        const figure = window.__wrap.figures()[index]
        const line = window.__wrap.linesOf(figure)[0]
        const code = window.__wrap.codeOf(figure)
        const style = getComputedStyle(line)
        return { padding: style.paddingLeft, textIndent: style.textIndent, position: style.position, whiteSpace: getComputedStyle(code).whiteSpace,
                 after: getComputedStyle(line, "::after").content, beforePosition: getComputedStyle(line, "::before").position }
      }
      return { wrapped: read(0), plain: read(1) }
    })()`)
    if (JSON.stringify(paper.wrapped) !== JSON.stringify(paper.plain)) problems.push(`on paper the wrapped block is laid out as ${JSON.stringify(paper.wrapped)}, the plain one as ${JSON.stringify(paper.plain)}`)
    await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
    const flowing = await evaluate(`(() => {
      const read = (index) => {
        const figure = window.__wrap.figures()[index]
        const line = window.__wrap.linesOf(figure)[0]
        const style = getComputedStyle(line)
        return { padding: style.paddingLeft, position: style.position, whiteSpace: getComputedStyle(window.__wrap.codeOf(figure)).whiteSpace,
                 after: getComputedStyle(line, "::after").content, beforePosition: getComputedStyle(line, "::before").position }
      }
      const pre = window.__wrap.figures()[0].querySelector("pre")
      pre.classList.add("plantoir-flowing")
      const marked = read(0)
      pre.classList.remove("plantoir-flowing")
      return { marked, plain: read(1), back: read(0).after.startsWith('"\\\\a') }
    })()`)
    if (JSON.stringify(flowing.marked) !== JSON.stringify(flowing.plain) || !flowing.back) problems.push(`a pre marked plantoir-flowing (the handout's) is laid out as ${JSON.stringify(flowing.marked)}, the plain one as ${JSON.stringify(flowing.plain)}`)

    // 8. The copy button, pressed by a real pointer, copies the block as
    //    written (#759). A scripted .click() dispatches ON the button
    //    whatever lies over it, so it passed while a real pointer at the
    //    button's centre hit the first line's span and nothing was copied.
    await checkTheCopyButton("light, 1512 px", true)

    // Dark, then a phone's width.
    await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "dark" }] })
    if (!(await open())) return finish(1, "FAIL: Wrap Fixture did not load again in dark mode")
    await checkTheBlocks("dark, 1512 px")
    await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
    await send("Emulation.setDeviceMetricsOverride", { width: 390, height: 900, deviceScaleFactor: 2, mobile: true })
    if (!(await open())) return finish(1, "FAIL: Wrap Fixture did not load at 390 px")
    await checkTheBlocks("light, 390 px")
    await checkTheCopyButton("light, 390 px", false)
  } catch (error) {
    return finish(1, "FAIL: " + (error && error.stack || error))
  }

  clearTimeout(timer)
  const light = report["light, 1512 px"]
  const phone = report["light, 390 px"]
  const summary = light && phone
    ? `${LINES} lines, ${light.rows} rows at 1512 px and ${phone.rows} at 390 px, digits 3, every row at x ${light.x} px, line ${URL_LINE}'s ${light.urlRows} rows full from the first, about ${report.charactersPerRow} characters a row at 1512 px; the copy button pressed by a real pointer copied ${report["copy, light, 1512 px"]?.characters} characters as written at 1512 px and at 390 px, and stacked as before #759 it was missed (${report.mustFail?.hit})`
    : "incomplete"
  finish(problems.length === 0 ? 0 : 1, (problems.length === 0 ? `OK: ${summary}\n` : "FAIL: " + problems.join("\n  ") + "\n") + JSON.stringify(report))
}
