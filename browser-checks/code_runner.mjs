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
//     put aside and the teacher's code shown, once;
//  4. five changes of page by the site's own navigation, each followed by a
//     run, leave at most ONE thread alive;
//
// then, against the same files served three wrong ways, that the student is
// told rather than left on "Loading…": the worker missing (engineMissing),
// .wasm sent as application/octet-stream and a CSP that allows no wasm
// (couldNotLoad, within the 45 s watchdog).
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/code_runner.mjs <chrome> <site folder> <page path> <second page path>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder, pagePath, secondPath] = process.argv.slice(2)
if (!chromePath || !siteFolder || !pagePath || !secondPath) {
  console.error("usage: node code_runner.mjs <chrome> <site folder> <page path> <second page path>")
  process.exit(2)
}

const RULES = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).codeRunnerBlocks
const LANGUAGE = RULES.languages[0]
const said = (key) => RULES.words[key].split("{language}").join(LANGUAGE.displayName).split("{inputCall}").join(LANGUAGE.inputCall)

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".zip": "application/zip", ".svg": "image/svg+xml",
  ".png": "image/png", ".ico": "image/x-icon", ".woff2": "font/woff2", ".xml": "application/xml", ".txt": "text/plain",
}

// mode: "good" | "missing" (the worker is a 404) | "wasm-type" (.wasm as
// octet-stream) | "no-eval" (a CSP that allows scripts from the site and no wasm)
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
const timer = setTimeout(() => finish(1, "FAIL: the runnable code was not checked within 360 s"), 360000)
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
      buttons: Array.from(block.querySelectorAll(".plantoir-runner-controls > button")).map((button) => button.textContent),
      runDisabled: block.querySelector(".plantoir-runner-run").disabled,
      status: block.querySelector(".plantoir-runner-status").textContent,
      output: output.textContent,
      outputShown: !output.hidden,
      errText: Array.from(output.querySelectorAll(".plantoir-runner-err")).map((span) => span.textContent).join(""),
      printCopy: block.querySelector(".plantoir-runner-print").textContent,
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

      // 3. Saved edits, print, Reset, and the teacher's change.
      await evaluate(`window.__runner.setCode(2, "print('my edit')\\n")`)
      await pause(800)
      const key = await evaluate(`Object.keys(localStorage).filter((name) => name.startsWith("plantoir:runner:") && name.endsWith(window.__runner.state(2).id))[0] ?? null`)
      expect("an edit is saved under plantoir:runner:<base>:<id>", key !== null && /^plantoir:runner:\/.*:/.test(key), key)
      state = await evaluate("window.__runner.state(2)")
      expect("an edit is what prints", state.edited && state.printCopy === "print('my edit')\n", state)
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
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
