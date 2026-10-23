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
// 8. the page's copy button copies the long block as written: 120 lines, no
//    ellipsis, no line break where a line wrapped (plan review finding 5).
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

    // 8. The copy button copies the block as written.
    const copied = await evaluate(`(async () => {
      let text = null
      const writeText = navigator.clipboard.writeText.bind(navigator.clipboard)
      navigator.clipboard.writeText = (value) => { text = value; return Promise.resolve() }
      window.__wrap.figures()[0].querySelector("pre > .clipboard-button").click()
      for (let tries = 0; tries < 50 && text === null; tries += 1) await new Promise((done) => setTimeout(done, 20))
      navigator.clipboard.writeText = writeText
      return text
    })()`)
    if (typeof copied !== "string") problems.push("the copy button copied nothing")
    else {
      const lines = copied.replace(/\n$/, "").split("\n")
      const url = "https://example.com/" + "a".repeat(400)
      const wrong = []
      if (copied.includes("…")) wrong.push("it holds an ellipsis")
      if (lines.length !== LINES) wrong.push(`${lines.length} lines, not ${LINES}`)
      if (lines[URL_LINE - 1] !== url) wrong.push(`line ${URL_LINE} is ${JSON.stringify((lines[URL_LINE - 1] || "").slice(0, 40))}…`)
      if (lines[0] !== "line 1" || lines[LINES - 1] !== `line ${LINES}`) wrong.push("its first or last line is not as written")
      if (lines[1] !== lines[99] || lines[1].length < 200 || lines[101] !== "    " + lines[1] || lines[102] !== "\t" + lines[1]) wrong.push("a long line is not whole")
      if (wrong.length) problems.push(`the copy button's text is not the block as written: ${wrong.join("; ")}`)
      report.copied = { lines: lines.length, characters: copied.length }
    }

    // Dark, then a phone's width.
    await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "dark" }] })
    if (!(await open())) return finish(1, "FAIL: Wrap Fixture did not load again in dark mode")
    await checkTheBlocks("dark, 1512 px")
    await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
    await send("Emulation.setDeviceMetricsOverride", { width: 390, height: 900, deviceScaleFactor: 2, mobile: true })
    if (!(await open())) return finish(1, "FAIL: Wrap Fixture did not load at 390 px")
    await checkTheBlocks("light, 390 px")
  } catch (error) {
    return finish(1, "FAIL: " + (error && error.stack || error))
  }

  clearTimeout(timer)
  const light = report["light, 1512 px"]
  const phone = report["light, 390 px"]
  const summary = light && phone
    ? `${LINES} lines, ${light.rows} rows at 1512 px and ${phone.rows} at 390 px, digits 3, every row at x ${light.x} px, line ${URL_LINE}'s ${light.urlRows} rows full from the first, about ${report.charactersPerRow} characters a row at 1512 px`
    : "incomplete"
  finish(problems.length === 0 ? 0 : 1, (problems.length === 0 ? `OK: ${summary}\n` : "FAIL: " + problems.join("\n  ") + "\n") + JSON.stringify(report))
}
