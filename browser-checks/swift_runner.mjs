// Runs a site's runnable Swift blocks (#493) in headless Chrome for Testing,
// the way a student does, against a server this check starts itself
// (contracts/shared-rules.json -> codeRunnerBlocks.swift: site, workerTalks,
// wasi, traps). On verify.sh's planted page `Swift Playground`, whose blocks
// are, in order: 1 a greeting that reads two lines (swift-gate 01), 2 a loop
// that never ends, 3 an index out of range (swift-gate 10), 4 exit(3), 5 a
// block that does not compile, 6 a block that needs the full library
// (swift-gate 05):
//
//  1. loading the page fetches nothing of Swift; every block is read-only
//     (no editor, Run and Stop only) with words.cannotEdit under it, and the
//     input box shows for code that calls readLine();
//  2. Run with input prints the greeting, each input line echoed after its
//     prompt; changed input and Run again changes the output;
//  3. Stop ends the loop at once, and Run works again;
//  4. the index out of range shows its `Fatal error:` line and words.crashed;
//  5. exit(3) ends with words.exitCode, 3 filled in;
//  6. the block that did not compile says words.notReady with Run off;
//  7. the full-library block prints swift-gate 05's expected output;
//
// and it reports the first Run's time and the bytes fetched for an Embedded
// block and a full-library block (the closing comment's measurements).
//
//   node browser-checks/swift_runner.mjs <chrome> <site folder> <page path>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder, pagePath] = process.argv.slice(2)
if (!chromePath || !siteFolder || !pagePath) {
  console.error("usage: node swift_runner.mjs <chrome> <site folder> <page path>")
  process.exit(2)
}

const RULES = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).codeRunnerBlocks
const LANGUAGE = RULES.languages.find((row) => row.fence === "swift")
const said = (key) => RULES.words[key].split("{language}").join(LANGUAGE.displayName).split("{inputCall}").join(LANGUAGE.inputCall)
const gate = (name) => readFileSync(new URL(`../swift-gate/${name}`, import.meta.url), "utf-8")

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".svg": "image/svg+xml", ".png": "image/png",
  ".ico": "image/x-icon", ".woff2": "font/woff2", ".xml": "application/xml", ".txt": "text/plain",
}

function serve() {
  const swiftRequests = []
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
      if (path.includes("/static/swift")) swiftRequests.push({ path, bytes: body.length })
      response.writeHead(200, { "Content-Type": TYPES[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-cache" })
      response.end(request.method === "HEAD" ? undefined : body)
    } catch {
      response.writeHead(404).end("not found")
    }
  })
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port, swiftRequests }))
  })
}

const work = mkdtempSync(join(tmpdir(), "plantoir-swift-check-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1280,900",
  "--use-mock-keychain", "--password-store=basic",
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows", "--hide-scrollbars", "--mute-audio",
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })

let served = null
function finish(code, message) {
  console.log(message)
  served?.server.close()
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}
const timer = setTimeout(() => finish(1, "FAIL: the Swift blocks were not checked within 240 s"), 240000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const PAGE_HELPERS = `
window.__swift = {
  block: (index) => document.querySelectorAll(".plantoir-runner")[index],
  state: (index) => {
    const block = window.__swift.block(index)
    if (!block) return null
    const output = block.querySelector(".plantoir-runner-output")
    return {
      count: document.querySelectorAll(".plantoir-runner").length,
      built: block.dataset.built === "true",
      editor: !!block.querySelector("textarea.plantoir-runner-editor"),
      note: block.querySelector(".plantoir-runner-note")?.textContent ?? null,
      inputShown: !block.querySelector(".plantoir-runner-input").hidden,
      buttons: Array.from(block.querySelectorAll(".plantoir-runner-controls > button")).map((button) => button.textContent),
      runDisabled: block.querySelector(".plantoir-runner-run").disabled,
      status: block.querySelector(".plantoir-runner-status").textContent,
      output: output.textContent,
    }
  },
  setInput: (index, text) => { window.__swift.block(index).querySelector(".plantoir-runner-input-lines").value = text },
  press: (index, name) => window.__swift.block(index).querySelector(".plantoir-runner-" + name).click(),
  settled: async (index, words, seconds) => {
    const until = Date.now() + seconds * 1000
    while (Date.now() < until) {
      const status = window.__swift.block(index).querySelector(".plantoir-runner-status").textContent
      if (words.includes(status) || words.some((word) => word.endsWith("*") && status.startsWith(word.slice(0, -1)))) return status
      await new Promise((resolve) => setTimeout(resolve, 50))
    }
    return window.__swift.block(index).querySelector(".plantoir-runner-status").textContent
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
    if (answer?.exceptionDetails) throw new Error(JSON.stringify(answer.exceptionDetails).slice(0, 400))
    return answer?.result?.value
  }
  const problems = []
  const expect = (what, ok, detail) => {
    if (!ok) problems.push(`${what}${detail === undefined ? "" : ": " + JSON.stringify(detail).slice(0, 400)}`)
  }
  const ENDED = [said("finished"), said("finishedWithError"), said("stopped"), said("couldNotLoad"), said("crashed"),
    said("notReady"), said("exitCode").split("{code}")[0] + "*"]
  const run = async (index, input, seconds = 60) => {
    if (input !== null) await evaluate(`window.__swift.setInput(${index}, ${JSON.stringify(input)})`)
    const began = Date.now()
    await evaluate(`window.__swift.press(${index}, "run")`)
    await evaluate(`window.__swift.settled(${index}, ${JSON.stringify(ENDED)}, ${seconds})`)
    const ms = Date.now() - began
    await pause(150)
    return { ...(await evaluate(`window.__swift.state(${index})`)), ms }
  }

  socket.onopen = async () => {
    try {
      await send("Page.enable")
      served = await serve()
      const url = `http://127.0.0.1:${served.port}${pagePath}`
      await send("Page.navigate", { url })
      let loaded = false
      for (let tries = 0; tries < 80 && !loaded; tries += 1) {
        await pause(250)
        loaded = (await evaluate("document.readyState")) === "complete"
      }
      if (!loaded) return finish(1, "FAIL: the page did not load")
      await evaluate(PAGE_HELPERS)
      await pause(800)

      // 1. Nothing fetched; read-only blocks with their note.
      expect("loading the page fetched something of Swift", served.swiftRequests.length === 0, served.swiftRequests)
      const first = await evaluate("window.__swift.state(0)")
      expect("the page has the six planted Swift blocks", first && first.count === 6, first)
      expect("a Swift block is read-only with Run and Stop and the cannot-edit note", first && first.built && !first.editor
        && JSON.stringify(first.buttons) === JSON.stringify([said("run"), said("stop")]) && first.note === said("cannotEdit"), first)
      expect("the input box shows for code that calls readLine()", first && first.inputShown, first)

      // 2. Run with input; then changed input.
      let state = await run(0, "Ada\n15")
      const embeddedFirstRun = { ms: state.ms, bytes: served.swiftRequests.filter((r) => r.path.endsWith(".wasm")).reduce((sum, r) => sum + r.bytes, 0) }
      expect("Run prints the greeting with each input echoed after its prompt",
        state.output === "What is your name?\nAda\nHello, Ada! Your name has 3 letters.\nHow old are you?\n15\nNext year you will be 16.\nYou can learn to drive in 1 years.\n"
        && state.status === said("finished"), state)
      state = await run(0, "Zoë\n17")
      expect("changed input changes the output", state.output.includes("Hello, Zoë! Your name has 3 letters.")
        && state.output.includes("You are old enough to drive in Ontario.") && state.status === said("finished"), state)

      // 3. Stop a loop that never ends; Run works again.
      await evaluate(`window.__swift.press(1, "run")`)
      await evaluate(`window.__swift.settled(1, ${JSON.stringify([said("running")])}, 30)`)
      await pause(1500)
      const stopBegan = Date.now()
      await evaluate(`window.__swift.press(1, "stop")`)
      state = await evaluate("window.__swift.state(1)")
      const stopMs = Date.now() - stopBegan
      expect("Stop ends a loop that never ends", state.status === said("stopped") && !state.runDisabled && state.output === "spinning\n", state)
      state = await run(0, "Ada\n15")
      expect("Run works again after Stop", state.status === said("finished"), state)

      // 4. A trap shows its Fatal error line.
      state = await run(2, "7")
      expect("an index out of range shows its Fatal error line and the crash words",
        state.output.includes("You asked for day 7.") && state.output.includes("Fatal error: Index out of range")
        && state.status === said("crashed"), state)

      // 5. exit(3).
      state = await run(3, null)
      expect("exit(3) ends with the exit code words", state.output === "leaving with 3\n"
        && state.status === said("exitCode").split("{code}").join("3"), state)

      // 6. The block that did not compile.
      state = await evaluate("window.__swift.state(4)")
      expect("a block that did not compile is not ready, with Run off", state.status === said("notReady") && state.runDisabled, state)

      // 7. The full library.
      const before = served.swiftRequests.length
      await evaluate(`window.__swift.setInput(5, ${JSON.stringify(gate("05-arrays.stdin").replace(/\n$/, ""))})`)
      state = await run(5, null)
      const fullFirstRun = { ms: state.ms, bytes: served.swiftRequests.slice(before).filter((r) => r.path.endsWith(".wasm")).reduce((sum, r) => sum + r.bytes, 0) }
      const wanted = gate("05-arrays.expected").replace("Type some whole numbers separated by spaces:\n",
        "Type some whole numbers separated by spaces:\n" + gate("05-arrays.stdin"))
      expect("the full-library block prints what swift-gate 05 expects", state.output === wanted && state.status === said("finished"), state)

      clearTimeout(timer)
      const ok = problems.length === 0
      finish(ok ? 0 : 1, (ok ? "OK: " : "FAIL: " + problems.join("\n  ") + "\n")
        + JSON.stringify({ embeddedFirstRun, fullFirstRun, stopMs }))
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
