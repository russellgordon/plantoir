// Runs a site's runnable code (#455) in headless Chrome for Testing, the way
// a student does, against a server this check starts itself - so it can also
// play the servers that break it (contracts/shared-rules.json ->
// codeRunnerBlocks: harness, stdin, output, loading, storage, print).
//
// On the verify fixture's page of runnable blocks (`Runner Fixture`), served
// as a host serves it:
//
//  1. loading the page fetches NOTHING of the engine; a block is built with
//     an editor, Run / Stop / Reset, a status line and an output;
//  2. Run prints; a NameError's traceback names the line the editor shows it
//     on; input() takes the input box's lines, echoes them after the prompt
//     and raises EOFError past the last; `while True: pass` is stopped by Stop
//     and a second Run works; a run on another block stops the first and says
//     so; one block's `builtins.print = ...` does not reach the next run;
//  3. an edit is kept (localStorage) and printed (the print copy), Reset
//     takes it away; a saved edit of code the teacher has since changed is
//     put aside and the teacher's code shown, once; Tab indents, Shift-Tab
//     takes it off, and Escape then Tab leaves the editor;
//  4. five changes of page by the site's own navigation, each followed by a
//     run, leave at most ONE thread alive;
//
//  5. live input (#583), with the files served as a host serves them with
//     the isolation headers (the preview's own rule, quartz/cli/
//     plantoirIsolation.mjs, decides which): the box never shows; Run on
//     code that reads input makes and focuses the answer field; the prompt
//     is on the page before the field is used; Return answers, and the
//     transcript is BYTE FOR BYTE the box's for the same program and
//     answers; Ctrl-D, and the end button, give EOFError and the end is
//     sticky; a two-line paste answers two input() calls; an answer being
//     composed by an input method is not sent; Escape keeps the focus;
//     Stop while it waits, and another block's Run, end it; the echoes
//     count toward the cap; an autorun that asks takes no focus and holds
//     the queue; and the site's own links load a page WHOLE across the
//     isolation line (both ways, the frame on the far side loading) while a
//     page change that stays on one side is still the site's own; and a
//     printable runner page's handout, made on an isolated page, still
//     loads KaTeX's stylesheet and faces in its print frame. Served
//     without the headers, the box shows its words.inputAhead line;
//
//  6. the editor's colours and line numbers (#585): an editable block is a
//     frame - gutter, coloured copy, textarea; an unedited block's copy is
//     the highlighted copy's own lines byte for byte and its text the
//     editor's; typed lines are the tokenizer's while the line above stays
//     Shiki's; undo, an input method, a saved edit and Reset keep the copy
//     in step; a scrolled editor's copy and gutter follow it; the coloured
//     letters sit exactly under the typed ones (0 strong pixels, light
//     theme, colour spans out - with a half-pixel control that must show);
//     the focus ring is the frame's; a plain block's numbers and the gutter
//     wear one style; no ligatures anywhere in code; and an edited block
//     prints coloured and numbered (⌘P, read back with pdftotext);
//
// then, against the same files served three wrong ways, that the student is
// told rather than left on "Loading…": the worker missing (engineMissing),
// .wasm sent as application/octet-stream and a CSP that allows no wasm
// (couldNotLoad, within the 45 s watchdog).
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/code_runner.mjs <chrome> <site folder> <page path> <second page path> [<autorun page path>]

import { spawn } from "node:child_process"
import { headersFor } from "../support/quartz/cli/plantoirIsolation.mjs"
import { createServer } from "node:http"
import { execFileSync } from "node:child_process"
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder, pagePath, secondPath, autorunPath] = process.argv.slice(2)
if (!chromePath || !siteFolder || !pagePath || !secondPath) {
  console.error("usage: node code_runner.mjs <chrome> <site folder> <page path> <second page path>")
  process.exit(2)
}

const RULES = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).codeRunnerBlocks
const LANGUAGE = RULES.languages[0]
const said = (key) => RULES.words[key].split("{language}").join(LANGUAGE.displayName).split("{inputCall}").join(LANGUAGE.inputCall)
// The live-input pages verify.sh plants beside the runner pages (#583).
const LIVE_PLAIN = "/Live-Plain-Link.html"
const LIVE_AUTORUN = "/Live-Autorun.html"

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".zip": "application/zip", ".svg": "image/svg+xml",
  ".png": "image/png", ".ico": "image/x-icon", ".woff2": "font/woff2", ".xml": "application/xml", ".txt": "text/plain",
}

// mode: "good" | "missing" (the worker is a 404) | "wasm-type" (.wasm as
// octet-stream) | "no-eval" (a CSP that allows scripts from the site and no wasm)
// | "isolated" (as a host with #583's headers serves it: the preview's rule)
function serve(mode) {
  const engineRequests = []
  const server = createServer((request, response) => {
    let path = decodeURIComponent(new URL(request.url, "http://x").pathname)
    if (path.endsWith("/")) path += "index.html"
    if (path.includes("/static/pyodide/")) engineRequests.push(path)
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
    if (mode === "missing" && path.endsWith("/plantoir-worker.js")) {
      response.writeHead(404).end("not found")
      return
    }
    let type = TYPES[extname(file)] ?? "application/octet-stream"
    if (mode === "wasm-type" && file.endsWith(".wasm")) type = "application/octet-stream"
    const headers = { "Content-Type": type, "Cache-Control": "no-cache" }
    if (mode === "no-eval") headers["Content-Security-Policy"] = "script-src 'self' 'unsafe-inline'"
    if (mode === "isolated") Object.assign(headers, headersFor(siteFolder, new URL(request.url, "http://x").pathname))
    try {
      const body = readFileSync(file)
      response.writeHead(200, headers)
      response.end(request.method === "HEAD" ? undefined : body)
    } catch {
      response.writeHead(404).end("not found")
    }
  })
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port, engineRequests }))
  })
}

const work = mkdtempSync(join(tmpdir(), "plantoir-runner-check-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1280,900",
  "--use-mock-keychain", "--password-store=basic",
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows", "--hide-scrollbars", "--mute-audio",
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })

const servers = []
function finish(code, message) {
  console.log(message)
  for (const { server } of servers) server.close()
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}
const timer = setTimeout(() => finish(1, "FAIL: the runnable code was not checked within 600 s"), 600000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// Helpers that run in the page.
const PAGE_HELPERS = `
window.__runner = {
  blocks: () => Array.from(document.querySelectorAll(".plantoir-runner")),
  block: (index) => window.__runner.blocks()[index],
  state: (index) => {
    const block = window.__runner.block(index)
    if (!block) return null
    const output = block.querySelector(".plantoir-runner-output")
    return {
      id: block.dataset.runnerId,
      built: block.dataset.built === "true",
      editor: !!block.querySelector("textarea.plantoir-runner-editor"),
      code: block.querySelector("textarea.plantoir-runner-editor")?.value ?? null,
      inputShown: !block.querySelector(".plantoir-runner-input").hidden,
      buttons: Array.from(block.querySelectorAll(".plantoir-runner-controls > button")).filter((button) => !button.hidden).map((button) => button.textContent),
      runDisabled: block.querySelector(".plantoir-runner-run").disabled,
      status: block.querySelector(".plantoir-runner-status").textContent,
      output: output.textContent,
      outputShown: !output.hidden,
      errText: Array.from(output.querySelectorAll(".plantoir-runner-err")).map((span) => span.textContent).join(""),
      answerShown: !!block.querySelector("input.plantoir-runner-answer"),
      answerFocused: document.activeElement === block.querySelector("input.plantoir-runner-answer"),
      beforeAnswer: (() => {
        const field = block.querySelector("input.plantoir-runner-answer")
        let text = ""
        for (let node = output.firstChild; node !== null && node !== field; node = node.nextSibling) text += node.textContent
        return field ? text : null
      })(),
      endShown: !(block.querySelector(".plantoir-runner-end")?.hidden ?? true),
      ahead: block.querySelector(".plantoir-runner-input-ahead")?.textContent ?? null,
      // The print copy's lines (#585: pre > code > span[data-line], a blank
      // line holding a space as a static block's does).
      printLines: Array.from(block.querySelectorAll(".plantoir-runner-print > code > [data-line]")).map((line) => line.textContent.replace(/ +$/, "")),
      edited: block.classList.contains("plantoir-runner-edited"),
    }
  },
  setCode: (index, code) => {
    const editor = window.__runner.block(index).querySelector("textarea.plantoir-runner-editor")
    editor.value = code
    editor.dispatchEvent(new Event("input", { bubbles: true }))
  },
  setInput: (index, text) => {
    window.__runner.block(index).querySelector(".plantoir-runner-input-lines").value = text
  },
  press: (index, name) => window.__runner.block(index).querySelector(".plantoir-runner-" + name).click(),
  // #585: the editor's frame - its coloured copy, its gutter, the textarea.
  frame: (index) => {
    const block = window.__runner.block(index)
    const area = block.querySelector("textarea.plantoir-runner-editor")
    const copy = block.querySelector("pre.plantoir-runner-colour")
    const code = copy ? copy.querySelector(":scope > code") : null
    const gutter = block.querySelector("pre.plantoir-runner-gutter")
    const frame = block.querySelector(".plantoir-runner-frame")
    const shiki = Array.from(block.querySelectorAll(".plantoir-runner-original pre > code > [data-line]"))
    return {
      framed: !!frame && !!copy && !!gutter && !!area && frame.contains(area),
      value: area ? area.value : null,
      copyText: code ? code.textContent : null,
      copyLines: code ? Array.from(code.children).map((line) => line.innerHTML.replace(/\\n$/, "")) : [],
      shikiLines: shiki.map((line) => (line.textContent.trim() === "" ? "" : line.innerHTML)),
      tokenizerSpans: code ? code.querySelectorAll("[class^='plantoir-tok-']").length : 0,
      numbers: gutter ? gutter.textContent.split("\\n") : [],
      scroll: area ? [area.scrollLeft, area.scrollTop] : null,
      copyScroll: copy ? [copy.scrollLeft, copy.scrollTop] : null,
      numbersMoved: gutter ? gutter.firstElementChild.style.transform : null,
      composing: block.classList.contains("plantoir-runner-composing"),
    }
  },
  answer: (index) => window.__runner.block(index).querySelector("input.plantoir-runner-answer"),
  paste: (index, text) => {
    const data = new DataTransfer()
    data.setData("text/plain", text)
    window.__runner.answer(index).dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
  },
  settled: async (index, words, seconds) => {
    const until = Date.now() + seconds * 1000
    while (Date.now() < until) {
      const status = window.__runner.block(index).querySelector(".plantoir-runner-status").textContent
      if (words.includes(status)) return status
      await new Promise((resolve) => setTimeout(resolve, 100))
    }
    return window.__runner.block(index).querySelector(".plantoir-runner-status").textContent
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
  const workers = new Set()
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
    if (message.method === "Target.attachedToTarget" && message.params.targetInfo.type === "worker") {
      workers.add(message.params.sessionId)
    }
    if (message.method === "Target.detachedFromTarget") {
      workers.delete(message.params.sessionId)
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
        await pause(300)
        return true
      }
    }
    return false
  }
  const problems = []
  const expect = (what, ok, detail) => {
    if (!ok) problems.push(`${what}${detail === undefined ? "" : ": " + JSON.stringify(detail).slice(0, 300)}`)
  }
  const ENDED = [said("finished"), said("finishedWithError"), said("stopped"), said("couldNotLoad"),
    said("engineMissing"), said("outputTooLong"), said("needsWebAddress")]
  const runBlock = async (index, code, seconds = 60) => {
    if (code !== null) await evaluate(`window.__runner.setCode(${index}, ${JSON.stringify(code)})`)
    await evaluate(`window.__runner.press(${index}, "run")`)
    await evaluate(`window.__runner.settled(${index}, ${JSON.stringify(ENDED)}, ${seconds})`)
    await pause(150)
    return evaluate(`window.__runner.state(${index})`)
  }

  socket.onopen = async () => {
    try {
      await send("Page.enable")
      await send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true })
      const good = await serve("good")
      servers.push(good)
      const base = `http://127.0.0.1:${good.port}`

      // 1. Loading costs nothing; the blocks are built.
      if (!(await open(base + pagePath))) return finish(1, "FAIL: the page did not load")
      await pause(1000)
      expect("loading the page fetched the engine", good.engineRequests.length === 0, good.engineRequests)
      const count = await evaluate("window.__runner.blocks().length")
      expect("the page has runnable blocks to check", count >= 3, count)
      const first = await evaluate("window.__runner.state(0)")
      expect("the first block is built with an editor and Run, Stop, Reset", first && first.built && first.editor
        && JSON.stringify(first.buttons) === JSON.stringify([said("run"), said("stop"), said("reset")]), first)

      // 2. Running.
      const started = Date.now()
      let state = await runBlock(0, 'print("hello from the check")\nprint(6 * 7)')
      const firstRunMs = Date.now() - started
      expect("Run prints", state.output === "hello from the check\n42\n" && state.status === said("finished"), state)
      expect("the first Run fetched the engine", good.engineRequests.length > 0)
      const second = Date.now()
      state = await runBlock(0, 'print("again")')
      const secondRunMs = Date.now() - second
      expect("a second Run prints", state.output === "again\n", state)
      state = await runBlock(0, "x = 1\ny = 2\nprint(z)\n")
      expect("a NameError names the editor's line", /File "main\.py", line 3, in <module>/.test(state.errText)
        && /NameError: name 'z' is not defined/.test(state.errText) && state.status === said("finishedWithError"), state)
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify('name = input("Name? ")\nprint("Hello,", name)\nprint(input("More? "))')})`)
      const inputShown = (await evaluate("window.__runner.state(0)")).inputShown
      expect("the input box shows for code that calls input()", inputShown)
      await evaluate(`window.__runner.setInput(0, "Ada")`)
      state = await runBlock(0, null)
      expect("input() reads the box, echoes after the prompt, and raises EOFError past the last line",
        state.output.startsWith("Name? Ada\nHello, Ada\nMore? ") && /EOFError/.test(state.errText), state)
      // Stop a program that never ends; then Run again.
      await evaluate(`window.__runner.setCode(0, "while True:\\n    pass\\n")`)
      await evaluate(`window.__runner.press(0, "run")`)
      await evaluate(`window.__runner.settled(0, ${JSON.stringify([said("running")])}, 30)`)
      await pause(1500)
      await evaluate(`window.__runner.press(0, "stop")`)
      state = await evaluate("window.__runner.state(0)")
      expect("Stop stops a program that never ends", state.status === said("stopped") && !state.runDisabled, state)
      state = await runBlock(0, 'print("after stop")')
      expect("Run works again after Stop", state.output === "after stop\n" && state.status === said("finished"), state)
      // One program at a time.
      await evaluate(`window.__runner.setCode(0, "while True:\\n    pass\\n")`)
      await evaluate(`window.__runner.press(0, "run")`)
      await evaluate(`window.__runner.settled(0, ${JSON.stringify([said("running")])}, 30)`)
      state = await runBlock(1, 'print("second block")')
      const stoppedFirst = await evaluate("window.__runner.state(0)")
      expect("Run on another block stops the first and says so", stoppedFirst.status === said("stoppedForAnother")
        && state.output === "second block\n", { first: stoppedFirst.status, second: state })
      // One block's mischief does not reach the next run.
      await runBlock(1, 'import builtins\nbuiltins.print = lambda *a, **k: None\nopen("x.txt", "w").write("x")')
      state = await runBlock(1, 'import os\nprint("visible", os.path.exists("x.txt"))')
      expect("each Run starts from a reset interpreter", state.output === "visible False\n", state)
      // Too much output.
      state = await runBlock(1, 'while True:\n    print("x" * 1000)')
      expect("too much output stops the program and says so", state.status === said("outputTooLong"), state.status)
      // One print far over the cap is cut at the cap on the page (review S1:
      // it used to be painted whole - 5 million characters here).
      state = await runBlock(1, 'print("x" * 5_000_000)')
      expect("one huge print is cut at the cap", state.status === said("outputTooLong")
        && state.output.length <= RULES.output.maxCharacters, { status: state.status, painted: state.output.length })

      // 3. Saved edits, print, Reset, and the teacher's change.
      await evaluate(`window.__runner.setCode(2, "print('my edit')\\n")`)
      await pause(800)
      const key = await evaluate(`Object.keys(localStorage).filter((name) => name.startsWith("plantoir:runner:") && name.endsWith(window.__runner.state(2).id))[0] ?? null`)
      expect("an edit is saved under plantoir:runner:<base>:<id>", key !== null && /^plantoir:runner:\/.*:/.test(key), key)
      state = await evaluate("window.__runner.state(2)")
      // The print copy is brought up to date when the page may be printed
      // (#585 plan review S2), so the check prints first.
      await evaluate(`(() => { window.dispatchEvent(new Event("beforeprint")); return 1 })()`)
      state = await evaluate("window.__runner.state(2)")
      expect("an edit is what prints", state.edited && JSON.stringify(state.printLines) === JSON.stringify(["print('my edit')", ""]), state)
      await open(base + pagePath)
      state = await evaluate("window.__runner.state(2)")
      expect("a saved edit is there after a reload", state.code === "print('my edit')\n", state)
      await evaluate(`window.__runner.press(2, "reset")`)
      await pause(200)
      const keyAfterReset = await evaluate(`localStorage.getItem(${JSON.stringify(key)})`)
      state = await evaluate("window.__runner.state(2)")
      expect("Reset puts the teacher's code back and forgets the edit", keyAfterReset === null && !state.edited, { keyAfterReset, state })
      await evaluate(`localStorage.setItem(${JSON.stringify(key)}, JSON.stringify({ originalHash: "00000000", code: "print('old')" }))`)
      await open(base + pagePath)
      state = await evaluate("window.__runner.state(2)")
      const setAside = await evaluate(`localStorage.getItem(${JSON.stringify(key + ":set-aside")})`)
      const live = await evaluate(`localStorage.getItem(${JSON.stringify(key)})`)
      expect("a saved edit of changed code is put aside and the teacher's shown, with the words", state.status === said("teacherChangedIt")
        && setAside !== null && live === null && state.code !== "print('old')", { status: state.status, setAside, live })
      await open(base + pagePath)
      state = await evaluate("window.__runner.state(2)")
      expect("the teacher's change is said once", state.status === "", state.status)

      // Keyboard: Tab indents, Shift-Tab takes it off, Escape then Tab leaves
      // the editor - and not for the search button (Quartz's own Escape).
      await evaluate(`(() => { const e = window.__runner.block(0).querySelector("textarea.plantoir-runner-editor"); e.value = "print(1)\\n"; e.dispatchEvent(new Event("input", { bubbles: true })); e.focus(); e.setSelectionRange(0, 0); return 1 })()`)
      const press = async (key, keyCode, modifiers = 0) => {
        await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key, code: key, windowsVirtualKeyCode: keyCode, modifiers })
        await send("Input.dispatchKeyEvent", { type: "keyUp", key, code: key, windowsVirtualKeyCode: keyCode, modifiers })
        await pause(150)
      }
      const editorState = `(() => { const e = window.__runner.block(0).querySelector("textarea.plantoir-runner-editor"); return { value: e.value, focused: document.activeElement === e, active: document.activeElement ? (document.activeElement.className || document.activeElement.tagName) : null } })()`
      await press("Tab", 9)
      const tabbed = await evaluate(editorState)
      await press("Tab", 9, 8)
      const untabbed = await evaluate(editorState)
      await press("Escape", 27)
      const escaped = await evaluate(editorState)
      await press("Tab", 9)
      const left = await evaluate(editorState)
      expect("Escape alone keeps the focus in the editor (Quartz's own Escape would move it to the search button)", escaped.focused, escaped)
      expect("Tab indents by four spaces and keeps the focus", tabbed.value === "    print(1)\n" && tabbed.focused, tabbed)
      expect("Shift-Tab takes the indent off", untabbed.value === "print(1)\n" && untabbed.focused, untabbed)
      expect("Escape then Tab leaves the editor, and not for the search button", !left.focused && !/search/.test(String(left.active)), left)

      // 6. The editor's colours and line numbers (#585: codeRunnerBlocks.
      // editor.colour, editor.lineNumbers). Block 0 is edited throughout;
      // block 1 is left as the teacher wrote it; the page's last block is a
      // plain ```python block.
      await evaluate(`(() => { for (const name of Object.keys(localStorage)) if (name.startsWith("plantoir:runner:")) localStorage.removeItem(name); return 1 })()`)
      await open(base + pagePath)
      const frameOf = (index) => evaluate(`window.__runner.frame(${index})`)
      const settle = () => evaluate("new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(1))))")
      let frame = await frameOf(1)
      expect("an editable block is a frame: the gutter, then the coloured copy under the textarea", frame.framed, frame)
      expect("an unedited block's coloured copy is the highlighted copy's own lines, byte for byte, and its text the editor's",
        frame.copyText === frame.value && frame.copyLines.length > 0 && JSON.stringify(frame.copyLines) === JSON.stringify(frame.shikiLines)
        && frame.tokenizerSpans === 0, frame)
      expect("the gutter numbers every line of the editor from 1", JSON.stringify(frame.numbers) === JSON.stringify(frame.value.split("\n").map((line, at) => String(at + 1))), frame)
      // Typing: the line typed is the tokenizer's, the line above Shiki's own.
      await evaluate(`(() => { const area = window.__runner.block(0).querySelector("textarea.plantoir-runner-editor"); area.focus(); area.setSelectionRange(area.value.length, area.value.length); return 1 })()`)
      const shikiFirst = (await frameOf(0)).shikiLines[0]
      await send("Input.insertText", { text: "\nfor n in range(3):\n" })
      await press("Tab", 9)
      await send("Input.insertText", { text: 'print(f"{n:>3}", end="")' })
      await settle()
      frame = await frameOf(0)
      expect("typed code: the copy's text is the editor's, the new lines coloured by the tokenizer and the untouched line still Shiki's",
        frame.copyText === frame.value && frame.tokenizerSpans > 0 && frame.copyLines[0] === shikiFirst && frame.numbers.length === 3, frame)
      await evaluate(`(() => { document.execCommand("undo"); return 1 })()`)
      await settle()
      frame = await frameOf(0)
      expect("undo: the copy follows the editor", frame.copyText === frame.value, frame)
      // An input method's text is the textarea's own until it is done.
      await send("Input.imeSetComposition", { text: "かな", selectionStart: 2, selectionEnd: 2 })
      await settle()
      const composed = await frameOf(0)
      await send("Input.insertText", { text: "かな" })
      await settle()
      frame = await frameOf(0)
      expect("while an input method composes the copy waits, and catches up when it is done",
        composed.composing && !frame.composing && frame.copyText === frame.value && frame.value.includes("かな"), { composed, frame })
      // A saved edit, loaded with the page, is coloured and numbered.
      await pause(800)
      await open(base + pagePath)
      frame = await frameOf(0)
      expect("a saved edit loads coloured and numbered", frame.value.includes("かな") && frame.copyText === frame.value
        && frame.numbers.length === frame.value.split("\n").length, frame)
      await evaluate(`window.__runner.press(0, "reset")`)
      await settle()
      frame = await frameOf(0)
      expect("Reset: the copy is the highlighted copy's own lines again", frame.copyText === frame.value
        && JSON.stringify(frame.copyLines) === JSON.stringify(frame.shikiLines), frame)
      // Scrolling: the copy and the gutter follow the editor.
      const LONG = 'print("' + "a long line that runs well past the right edge of the editor, ".repeat(3) + '")'
      const forty = Array.from({ length: 40 }, (_, at) => `n = ${at + 1}`).join("\n") + "\n" + LONG
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify(forty)})`)
      await settle()
      await evaluate(`(() => { const area = window.__runner.block(0).querySelector("textarea.plantoir-runner-editor"); area.scrollTop = area.scrollHeight; area.scrollLeft = 150; area.dispatchEvent(new Event("scroll")); return 1 })()`)
      await settle()
      frame = await frameOf(0)
      expect("a scrolled editor: the copy scrolled to the same place, the gutter moved with it, 41 numbers",
        frame.scroll[1] > 0 && frame.scroll[0] > 0 && JSON.stringify(frame.copyScroll) === JSON.stringify(frame.scroll)
        && frame.numbersMoved === `translateY(${-frame.scroll[1]}px)` && frame.numbers.length === 41, frame)
      // The coloured letters sit exactly under the typed ones (#585 plan
      // review F2's recipe): light theme; A is the textarea's own text in
      // black, B the copy's text in black with its colour spans taken out;
      // a pixel more than 40/255 apart in any channel is strong. A copy
      // half a pixel off must show (the control), or the measure is blind.
      await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 2, mobile: false })
      await evaluate(`(() => {
        document.documentElement.setAttribute("saved-theme", "light")
        const style = document.createElement("style")
        style.id = "plantoir-align-check"
        style.textContent = ".al-a .plantoir-runner-colour { visibility: hidden !important } .al-a .plantoir-runner-cell > .plantoir-runner-editor { color: #000 !important; -webkit-text-fill-color: #000 !important; caret-color: transparent !important }"
          + " .al-b .plantoir-runner-colour code, .al-b .plantoir-runner-colour code * { color: #000 !important } .al-b .plantoir-runner-cell > .plantoir-runner-editor { caret-color: transparent !important }"
        document.head.appendChild(style)
        window.__diff = async (first, second) => {
          const load = async (data) => { const bitmap = await createImageBitmap(await (await fetch("data:image/png;base64," + data)).blob()); const canvas = new OffscreenCanvas(bitmap.width, bitmap.height); const paint = canvas.getContext("2d"); paint.drawImage(bitmap, 0, 0); return paint.getImageData(0, 0, bitmap.width, bitmap.height) }
          const a = await load(first)
          const b = await load(second)
          if (a.width !== b.width || a.height !== b.height) return -1
          let strong = 0
          for (let at = 0; at < a.data.length; at += 4) {
            if (Math.max(Math.abs(a.data[at] - b.data[at]), Math.abs(a.data[at + 1] - b.data[at + 1]), Math.abs(a.data[at + 2] - b.data[at + 2])) > 40) strong += 1
          }
          return strong
        }
        return 1
      })()`)
      const aligned = async (index) => {
        await evaluate(`(() => { window.__runner.block(${index}).scrollIntoView({ block: "center" }); window.__runner.block(${index}).querySelector("textarea.plantoir-runner-editor").dispatchEvent(new Event("scroll")); return 1 })()`)
        await settle()
        const clip = await evaluate(`(() => { const box = window.__runner.block(${index}).querySelector(".plantoir-runner-cell").getBoundingClientRect(); return { x: box.x + scrollX, y: box.y + scrollY, width: box.width, height: box.height, scale: 1 } })()`)
        const shot = async () => (await send("Page.captureScreenshot", { format: "png", clip, captureBeyondViewport: true })).data
        await evaluate(`(() => { document.documentElement.classList.add("al-a"); return 1 })()`)
        await settle()
        const typed = await shot()
        await evaluate(`(() => { for (const line of window.__runner.block(${index}).querySelectorAll(".plantoir-runner-colour code > span")) line.textContent = line.textContent; document.documentElement.classList.remove("al-a"); document.documentElement.classList.add("al-b"); return 1 })()`)
        await settle()
        const copied = await shot()
        await evaluate(`(() => { window.__runner.block(${index}).querySelector(".plantoir-runner-colour code").style.transform = "translate(0.5px, 0)"; return 1 })()`)
        await settle()
        const off = await shot()
        await evaluate(`(() => { const block = window.__runner.block(${index}); block.querySelector(".plantoir-runner-colour code").style.transform = ""; document.documentElement.classList.remove("al-b"); block.querySelector("textarea.plantoir-runner-editor").dispatchEvent(new Event("input", { bubbles: true })); return 1 })()`)
        await settle()
        return { strong: await evaluate(`window.__diff(${JSON.stringify(typed)}, ${JSON.stringify(copied)})`), control: await evaluate(`window.__diff(${JSON.stringify(typed)}, ${JSON.stringify(off)})`) }
      }
      const alignedShort = await aligned(1)
      const alignedLong = await aligned(0)
      await evaluate(`(() => { document.getElementById("plantoir-align-check").remove(); return 1 })()`)
      await send("Emulation.clearDeviceMetricsOverride")
      expect("the coloured letters sit exactly under the typed ones, a short block and a long line scrolled both ways (0 strong pixels), and half a pixel off shows (10,000 pixels at least on the 24-row block)",
        alignedShort.strong === 0 && alignedLong.strong === 0 && alignedShort.control > 300 && alignedLong.control >= 10000, { alignedShort, alignedLong })
      // The focus ring is the frame's (#585 plan review F3).
      const ring = await evaluate(`(() => { const block = window.__runner.block(1); const area = block.querySelector("textarea.plantoir-runner-editor"); area.focus(); const frame = getComputedStyle(block.querySelector(".plantoir-runner-frame")); return { frame: frame.outlineStyle + " " + frame.outlineWidth, area: getComputedStyle(area).outlineStyle } })()`)
      expect("the editor's focus ring is drawn on its frame, uncut by the frame's corner", ring.frame === "solid 2px" && ring.area === "none", ring)
      // One gutter style for a static block's numbers and the editor's.
      const styles = await evaluate(`(() => {
        const pick = (style) => ({ color: style.color, font: style.fontFamily, align: style.textAlign, line: style.borderRightWidth + " " + style.borderRightStyle + " " + style.borderRightColor })
        const statics = Array.from(document.querySelectorAll("pre > code > [data-line]")).filter((line) => !line.closest(".plantoir-runner"))
        const gutter = window.__runner.block(1).querySelector("pre.plantoir-runner-gutter")
        const ligatures = [document.querySelector("pre > code"), document.querySelector("article p > code"), window.__runner.block(1).querySelector("textarea.plantoir-runner-editor"), window.__runner.block(1).querySelector("pre.plantoir-runner-colour > code"), window.__runner.block(1).querySelector("pre.plantoir-runner-output")].map((element) => getComputedStyle(element).fontVariantLigatures)
        return { staticLine: statics.length > 0 ? pick(getComputedStyle(statics[0], "::before")) : null, gutter: pick(getComputedStyle(gutter)), ligatures }
      })()`)
      expect("a static block's numbers and the editor's gutter wear one style: colour, font, alignment and a 1 px hairline",
        styles.staticLine !== null && JSON.stringify(styles.staticLine) === JSON.stringify(styles.gutter) && /^1px solid/.test(styles.gutter.line), styles)
      expect("no ligatures in a static block, inline code in prose, the editor, its copy or the output", styles.ligatures.every((value) => value === "none"), styles.ligatures)
      // An edited block prints coloured and numbered, as a static block does.
      const WRAPPED = 'print("edited-585-b: a line a student made much longer than the printed page is wide, so that on paper it has to wrap WRAPTAIL-585")'
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify('print("edited-585-a")\n')} + ${JSON.stringify(WRAPPED)})`)
      await evaluate(`(() => { window.dispatchEvent(new Event("beforeprint")); return 1 })()`)
      state = await evaluate("window.__runner.state(0)")
      const printedSpans = await evaluate(`window.__runner.block(0).querySelectorAll(".plantoir-runner-print > code > [data-line] [style*='--shiki-light'], .plantoir-runner-print > code > [data-line] [class^='plantoir-tok-']").length`)
      const pdf = await send("Page.printToPDF", { printBackground: false, preferCSSPageSize: false })
      const pdfFile = join(work, "edited.pdf")
      writeFileSync(pdfFile, Buffer.from(pdf.data, "base64"))
      const printedText = execFileSync("pdftotext", ["-layout", pdfFile, "-"], { encoding: "utf-8" })
      expect("an edited block prints its lines coloured and numbered as a static block's, a long one wrapped whole (⌘P)",
        JSON.stringify(state.printLines) === JSON.stringify(['print("edited-585-a")', WRAPPED]) && printedSpans > 0
        && /\b1\s+print\("edited-585-a"\)/.test(printedText) && /\b2\s+print\("edited-585-b:/.test(printedText) && printedText.includes("WRAPTAIL-585"), { lines: state.printLines, printedSpans, printed: printedText.slice(0, 600) })
      await evaluate(`window.__runner.press(0, "reset")`)

      // 4. Page changes leave at most one thread.
      await runBlock(0, 'print("warm")')
      let most = workers.size
      for (let step = 0; step < 5; step += 1) {
        const target = step % 2 === 0 ? base + secondPath : base + pagePath
        const changed = await evaluate(`(async () => {
          if (typeof window.spaNavigate !== "function") return false
          const arrived = new Promise((resolve) => document.addEventListener("nav", () => resolve(true), { once: true }))
          window.spaNavigate(new URL(${JSON.stringify(target)}))
          return await Promise.race([arrived, new Promise((resolve) => setTimeout(() => resolve(false), 15000))])
        })()`)
        expect(`page change ${step + 1} happened`, changed)
        await pause(500)
        await evaluate(PAGE_HELPERS)
        if ((await evaluate("window.__runner.blocks().length")) > 0) {
          await runBlock(0, `print("page ${step + 1}")`)
        }
        await pause(300)
        most = Math.max(most, workers.size)
      }
      await pause(500)
      expect("five page changes leave at most one thread alive", workers.size <= 1 && most <= 1, { now: workers.size, most })

      // Autoruns (N4): the second waits for the first; started by hand while
      // it waits, it runs once, not again when its turn comes (review N1).
      if (autorunPath) {
        await open(base + autorunPath)
        // Whichever block comes into view first runs; the other waits, with
        // nothing in its status. Press Run on the one that waits.
        const waiting = await evaluate(`(async () => {
          const busy = [${JSON.stringify(said("loading"))}, ${JSON.stringify(said("running"))}]
          const status = (i) => window.__runner.block(i).querySelector(".plantoir-runner-status").textContent
          for (let tries = 0; tries < 300; tries += 1) {
            if (busy.includes(status(0)) && status(1) === "") return 1
            if (busy.includes(status(1)) && status(0) === "") return 0
            await new Promise((resolve) => setTimeout(resolve, 20))
          }
          return -1
        })()`)
        expect("one autorun runs while the other waits", waiting >= 0, waiting)
        if (waiting >= 0) {
          await evaluate(`(() => { window.__finishes = 0; window.__log = []; const status = window.__runner.block(${waiting}).querySelector(".plantoir-runner-status"); new MutationObserver((records) => { for (const record of records) for (const node of record.addedNodes) { window.__log.push(node.textContent); if (node.textContent === ${JSON.stringify(said("finished"))}) window.__finishes += 1 } }).observe(status, { childList: true, characterData: true, subtree: true }); return 1 })()`)
          // Give the waiting block's own view-watcher time to queue it.
          await pause(600)
          // Still waiting at the press, or the case proves nothing.
          const stillWaiting = await evaluate(`window.__runner.block(${waiting}).querySelector(".plantoir-runner-status").textContent === ""`)
          expect("the waiting autorun is still waiting when Run is pressed", stillWaiting)
          await evaluate(`window.__runner.press(${waiting}, "run")`)
          await pause(12000)
          const finishes = await evaluate("window.__finishes")
          const log = await evaluate("window.__log")
          expect("an autorun started by hand while it waits runs once", finishes === 1, { finishes, log })
        }
      }

      // 5. Live input (#583).
      const ASKING = 'name = input("Name? ")\nprint("Hello", name)\nage = input("Age? ")\nprint(int(age) + 1)\n'
      const ANSWERS = ["Zoë", "15"]
      // The box's transcript first, on a page that is not isolated.
      await open(base + pagePath)
      expect("served without the headers, the page is not isolated", (await evaluate("self.crossOriginIsolated === true")) === false)
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify(ASKING)})`)
      state = await evaluate("window.__runner.state(0)")
      expect("where the page cannot stop to ask, the box shows with its words.inputAhead line", state.inputShown && state.ahead === said("inputAhead"), state)
      await evaluate(`window.__runner.setInput(0, ${JSON.stringify(ANSWERS.join("\n"))})`)
      const boxRun = await runBlock(0, null)
      expect("the box's run of the asking program finishes", boxRun.status === said("finished") && boxRun.output === "Name? Zoë\nHello Zoë\nAge? 15\n16\n", boxRun)

      const isolatedServer = await serve("isolated")
      servers.push(isolatedServer)
      const liveBase = `http://127.0.0.1:${isolatedServer.port}`
      const waitFor = async (index, words, seconds = 20) => evaluate(`window.__runner.settled(${index}, ${JSON.stringify(words)}, ${seconds})`)
      const WAITING = [said("waitingForInput")]
      const answerWith = async (text) => {
        if (text.length > 0) await send("Input.insertText", { text })
        await press("Enter", 13)
      }
      await open(liveBase + pagePath)
      expect("served with the headers, the page is cross-origin isolated", (await evaluate("self.crossOriginIsolated === true")) === true)
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify(ASKING)})`)
      state = await evaluate("window.__runner.state(0)")
      expect("on a live page the box never shows", !state.inputShown, state)
      await evaluate(`window.__runner.press(0, "run")`)
      state = await evaluate("window.__runner.state(0)")
      expect("Run on code that reads input makes the answer field and focuses it at once", state.answerShown && state.answerFocused && state.endShown, state)
      let asked = await waitFor(0, WAITING)
      state = await evaluate("window.__runner.state(0)")
      expect("the program waits at its first prompt, painted before the field", asked === said("waitingForInput") && state.beforeAnswer === "Name? ", state)
      // An answer still being composed by an input method is not sent (N1).
      await evaluate(`(() => { const field = window.__runner.answer(0); field.value = "かな"
        field.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", isComposing: true, bubbles: true, cancelable: true }))
        const late = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
        Object.defineProperty(late, "keyCode", { get: () => 229 })
        field.dispatchEvent(late); return 1 })()`)
      await pause(300)
      state = await evaluate("window.__runner.state(0)")
      const composing = await evaluate("window.__runner.answer(0).value")
      expect("Return while an input method composes sends nothing", state.status === said("waitingForInput") && composing === "かな", { status: state.status, composing })
      await evaluate("(() => { window.__runner.answer(0).value = ''; return 1 })()")
      await press("Escape", 27)
      state = await evaluate("window.__runner.state(0)")
      expect("Escape in the answer field keeps the focus there", state.answerFocused, state)
      await answerWith(ANSWERS[0])
      asked = await waitFor(0, WAITING)
      state = await evaluate("window.__runner.state(0)")
      expect("Return answers, the answer is echoed after the prompt, and the program asks again with the field still focused",
        state.beforeAnswer === "Name? Zoë\nHello Zoë\nAge? " && state.answerFocused, state)
      await answerWith(ANSWERS[1])
      await waitFor(0, [said("finished"), said("finishedWithError")])
      await pause(150)
      state = await evaluate("window.__runner.state(0)")
      expect("the live transcript is byte for byte the box's", state.output === boxRun.output && state.errText === boxRun.errText
        && state.status === said("finished") && !state.answerShown && !state.endShown, { live: state.output, box: boxRun.output })

      // The end of input: Ctrl-D, and the button; sticky.
      const TWO = 'print(input("A? "))\nprint(input("B? "))\n'
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify(TWO)})`)
      await evaluate(`window.__runner.press(0, "run")`)
      await waitFor(0, WAITING)
      await answerWith("x")
      await waitFor(0, WAITING)
      await press("d", 68, 2)
      await waitFor(0, [said("finished"), said("finishedWithError")])
      state = await evaluate("window.__runner.state(0)")
      await evaluate(`window.__runner.setInput(0, "x")`)
      expect("Ctrl-D ends the input: EOFError, after the transcript so far", state.output.startsWith("A? x\nx\nB? ") && /EOFError/.test(state.errText)
        && state.status === said("finishedWithError"), state)
      await evaluate(`window.__runner.press(0, "run")`)
      await waitFor(0, WAITING)
      await evaluate(`window.__runner.press(0, "end")`)
      await waitFor(0, [said("finished"), said("finishedWithError")])
      state = await evaluate("window.__runner.state(0)")
      expect("the words.endInput button ends the input too", state.output.startsWith("A? ") && /EOFError/.test(state.errText), state)
      const EVERY = 'import sys\nfor line in sys.stdin:\n    print(line.strip().upper())\nprint("done")\n'
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify(EVERY)})`)
      await evaluate(`window.__runner.press(0, "run")`)
      await waitFor(0, WAITING)
      await answerWith("a")
      await waitFor(0, WAITING)
      await answerWith("b")
      await waitFor(0, WAITING)
      await press("d", 68, 2)
      await waitFor(0, [said("finished"), said("finishedWithError")])
      state = await evaluate("window.__runner.state(0)")
      expect("a program that reads every line ends at Ctrl-D", state.output === "a\nA\nb\nB\ndone\n" && state.status === said("finished"), state)

      // A paste of two lines answers two input() calls (S2).
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify(ASKING)})`)
      await evaluate(`window.__runner.press(0, "run")`)
      await waitFor(0, WAITING)
      await evaluate(`window.__runner.paste(0, ${JSON.stringify("Ada\n15\n")})`)
      await waitFor(0, [said("finished"), said("finishedWithError")])
      state = await evaluate("window.__runner.state(0)")
      expect("a paste of two lines answers two input() calls", state.output === "Name? Ada\nHello Ada\nAge? 15\n16\n", state)

      // Stop while it waits; another block's Run while it waits.
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify('input("Wait? ")\n')})`)
      await evaluate(`window.__runner.press(0, "run")`)
      await waitFor(0, WAITING)
      await evaluate(`window.__runner.press(0, "stop")`)
      state = await evaluate("window.__runner.state(0)")
      expect("Stop ends a program that waits, and the field goes", state.status === said("stopped") && !state.answerShown && !state.endShown, state)
      state = await runBlock(0, 'print("after a stop")')
      expect("Run works again after stopping a program that waited", state.output === "after a stop\n", state)
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify('input("Wait? ")\n')})`)
      await evaluate(`window.__runner.press(0, "run")`)
      await waitFor(0, WAITING)
      state = await runBlock(1, 'print("the other block")')
      const stoppedWaiting = await evaluate("window.__runner.state(0)")
      expect("another block's Run stops a program that waits", stoppedWaiting.status === said("stoppedForAnother") && !stoppedWaiting.answerShown
        && state.output === "the other block\n", { first: stoppedWaiting, second: state.output })

      // The echoes count toward the cap.
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify("while True:\n    input()\n")})`)
      await evaluate(`window.__runner.press(0, "run")`)
      await waitFor(0, WAITING)
      await evaluate(`window.__runner.paste(0, ${JSON.stringify(("x".repeat(4000) + "\n").repeat(26))})`)
      const capped = await waitFor(0, [said("outputTooLong"), said("finished"), said("finishedWithError")])
      expect("the echoes of the answers count toward the output cap", capped === said("outputTooLong"), capped)

      // An autorun that asks takes no focus and holds the queue.
      await open(liveBase + LIVE_AUTORUN)
      const autorunWaits = await waitFor(0, WAITING)
      // The second autorun comes into view only now, while the first waits.
      await evaluate("(() => { window.__runner.block(1).scrollIntoView(); return 1 })()")
      await pause(1000)
      state = await evaluate("window.__runner.state(0)")
      const queuedBlock = await evaluate("window.__runner.state(1)")
      expect("an autorun that asks waits, takes no focus, and the next autorun waits its turn", autorunWaits === said("waitingForInput")
        && state.answerShown && !state.answerFocused && queuedBlock.status === "", { first: state, second: queuedBlock.status })
      await evaluate("window.__runner.answer(0).focus()")
      await answerWith("Ada")
      await waitFor(1, [said("finished")])
      state = await evaluate("window.__runner.state(0)")
      const queuedAfter = await evaluate("window.__runner.state(1)")
      expect("answered, the autorun finishes and the queued one runs", state.output === "Name? Ada\nHi Ada\n" && queuedAfter.output === "second\n", { first: state.output, second: queuedAfter.output })

      // Across the isolation line by the site's own links: a whole load.
      const follow = async (fromPath, linkPart) => {
        await open(liveBase + fromPath)
        await evaluate("(() => { window.__plantoirSamePage = true; return 1 })()")
        const before = await evaluate("self.crossOriginIsolated === true")
        await evaluate(`(() => { const link = Array.from(document.querySelectorAll("article a, .center a")).find((a) => decodeURIComponent(a.getAttribute("href") || "").includes(${JSON.stringify(linkPart)})); link.click(); return 1 })()`)
        for (let tries = 0; tries < 80; tries += 1) {
          await pause(250)
          const here = await evaluate(`decodeURIComponent(location.pathname).includes(${JSON.stringify(linkPart)}) && document.readyState === "complete"`)
          if (here) break
        }
        await pause(800)
        return { before, after: await evaluate("self.crossOriginIsolated === true"), whole: await evaluate("window.__plantoirSamePage !== true") }
      }
      let crossing = await follow(LIVE_PLAIN, "Runner-Playground")
      expect("a link from a plain page to a runner page loads it whole, isolated", !crossing.before && crossing.after && crossing.whole, crossing)
      await evaluate(PAGE_HELPERS)
      await evaluate(`window.__runner.setCode(0, ${JSON.stringify('print(input("Name? "))\n')})`)
      await evaluate(`window.__runner.press(0, "run")`)
      expect("reached by a link, the runner page asks live", (await waitFor(0, WAITING)) === said("waitingForInput"))
      crossing = await follow(LIVE_AUTORUN, "Live-Framed")
      const frameLoaded = await evaluate(`(() => { const frame = document.querySelector("iframe.plantoir-live-frame"); try { return !!frame && !!frame.contentDocument && frame.contentDocument.body.textContent.length > 0 } catch { return false } })()`)
      expect("a link from a runner page to a page with a frame loads it whole, not isolated, and the frame loads", crossing.before && !crossing.after && crossing.whole && frameLoaded, { crossing, frameLoaded })
      const staying = await evaluate(`(async () => {
        window.__plantoirSamePage = true
        const arrived = new Promise((resolve) => document.addEventListener("nav", () => resolve(true), { once: true }))
        window.spaNavigate(new URL(${JSON.stringify(liveBase + LIVE_PLAIN)}))
        return await Promise.race([arrived, new Promise((resolve) => setTimeout(() => resolve(false), 15000))]) && window.__plantoirSamePage === true
      })()`)
      expect("a page change that stays on one side of the line is still the site's own", staying)

      // A printable runner page's handout on an isolated page: the print
      // frame inherits the page's headers and must still load KaTeX's
      // stylesheet and faces from the site (caught at the moment it is
      // printed, the way maths_offline.mjs catches it).
      await open(liveBase + pagePath)
      await evaluate(`(() => {
        window.__printFrame = null
        new MutationObserver((changes) => {
          for (const change of changes) for (const node of change.addedNodes) {
            if (node.tagName !== "IFRAME") continue
            node.contentWindow.print = () => {
              const frame = node.contentDocument
              window.__printFrame = {
                sheets: Array.from(frame.querySelectorAll('link[rel="stylesheet"]')).map((link) => {
                  let rules = -1
                  try { rules = link.sheet ? link.sheet.cssRules.length : 0 } catch { rules = -1 }
                  return { href: link.href, rules }
                }),
                faces: Array.from(frame.fonts).filter((face) => face.status === "loaded").map((face) => face.family.replace(/["']/g, "")),
                formulas: frame.querySelectorAll(".katex").length,
              }
            }
          }
        }).observe(document.body, { childList: true })
        return 1
      })()`)
      await evaluate(`(async () => {
        const arrived = new Promise((resolve) => document.addEventListener("nav", () => resolve(true), { once: true }))
        window.spaNavigate(new URL(${JSON.stringify(liveBase + secondPath + "#plantoir-print=questionsOnly&paper=portrait")}))
        return await Promise.race([arrived, new Promise((resolve) => setTimeout(() => resolve(false), 15000))])
      })()`)
      let printFrame = null
      for (let tries = 0; tries < 120 && printFrame === null; tries += 1) {
        await pause(250)
        printFrame = await evaluate("window.__printFrame")
      }
      const printableIsolated = await evaluate("self.crossOriginIsolated === true")
      const katexSheet = (printFrame?.sheets ?? []).filter((sheet) => sheet.href.includes("katex.min.css"))
      expect("a printable runner page's handout on an isolated page loads KaTeX's stylesheet and faces in its print frame",
        printableIsolated && printFrame !== null && katexSheet.length === 1 && katexSheet[0].rules > 0 && printFrame.formulas > 0
        && printFrame.faces.some((face) => face.startsWith("KaTeX")), { printableIsolated, printFrame })

      // The three wrong servers.
      const wrong = {}
      for (const [mode, word] of [["missing", said("engineMissing")], ["wasm-type", said("couldNotLoad")], ["no-eval", said("couldNotLoad")]]) {
        const bad = await serve(mode)
        servers.push(bad)
        await open(`http://127.0.0.1:${bad.port}${pagePath}`)
        const begun = Date.now()
        await evaluate(`window.__runner.press(0, "run")`)
        const status = await evaluate(`window.__runner.settled(0, ${JSON.stringify(ENDED)}, ${RULES.loading.watchdogSeconds + 10})`)
        wrong[mode] = { status, seconds: Math.round((Date.now() - begun) / 100) / 10 }
        expect(`a server that ${mode === "missing" ? "lacks the worker" : mode === "wasm-type" ? "sends .wasm as octet-stream" : "allows no wasm"} ends in the contract's words`, status === word, wrong[mode])
      }

      clearTimeout(timer)
      const ok = problems.length === 0
      finish(ok ? 0 : 1, (ok ? "OK: " : "FAIL: " + problems.join("\n  ") + "\n")
        + JSON.stringify({ firstRunMs, secondRunMs, engineFiles: new Set(good.engineRequests).size, wrong }))
    } catch (error) {
      finish(1, "FAIL: " + (problems.length > 0 ? problems.join("\n  ") + "\n  and then: " : "") + (error?.stack ?? error))
    }
  }
}
