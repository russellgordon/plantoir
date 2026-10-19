// Draws a page's Mermaid diagrams in headless Chrome for Testing under the
// Content-Security-Policy a Netlify publish would send (#594).
//
// The policy that keeps Netlify's ad badge off (scripts/netlify_badge.py)
// once allowed the hosts of <script src> tags only. Quartz's Mermaid loader
// is an inline module that does `await import("https://cdnjs.cloudflare.com/
// .../mermaid.esm.min.mjs")`, and script-src governs that import too, so on
// every Netlify site every diagram stayed as its source text while the same
// page on Cloudflare (no policy) drew it. This serves the built site over a
// local server that sends, on every response, the exact policy line
// write_netlify_headers_file wrote into the site's own _headers - read from
// that file, so it tests the policy the deploy would send, not a copy - and
// checks:
//
// 1. every code.mermaid on the page ends up with a drawn svg (Quartz's
//    loader puts it inside the diagram's container);
// 2. no request was blocked by the policy (Network.loadingFailed with
//    blockedReason "csp").
//
// The diagram engine comes from cdnjs, so this needs the network. When
// cdnjs cannot be reached it prints a line starting "SKIPPED: no network"
// and exits 3, which verify.sh reports as a skip, never a pass.
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/mermaid_draws.mjs <chrome> <site folder> <page path>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder, pagePath] = process.argv.slice(2)
if (!chromePath || !siteFolder || !pagePath) {
  console.error("usage: node mermaid_draws.mjs <chrome> <site folder> <page path>")
  process.exit(2)
}

const NO_NETWORK = 3

// The policy line from the block write_netlify_headers_file writes: `/*`,
// then `  Content-Security-Policy: script-src 'self' 'unsafe-eval' ...`.
function policyFromHeadersFile() {
  let text
  try {
    text = readFileSync(join(siteFolder, "_headers"), "utf-8")
  } catch {
    return null
  }
  const lines = text.split("\n")
  const found = []
  for (let index = 1; index < lines.length; index += 1) {
    const line = lines[index]
    const match = /^\s+Content-Security-Policy:\s*(script-src 'self' 'unsafe-eval'.*)$/.exec(line)
    if (match) found.push(match[1].trim())
  }
  return found.length === 1 ? found[0] : null
}

const POLICY = policyFromHeadersFile()
if (POLICY === null) {
  console.log(`FAIL: ${join(siteFolder, "_headers")} has no single ad-badge policy line - run write_netlify_headers_file on the site first`)
  process.exit(1)
}

// The engine's address, read off the page itself, so a Quartz bump that
// moves it is still what is checked for reachability.
const pageFile = join(siteFolder, pagePath)
let pageText = ""
try {
  pageText = readFileSync(pageFile, "utf-8")
} catch {
  console.log("FAIL: no such page " + pageFile)
  process.exit(1)
}
const engineMatch = /import\(\s*["'`](https:\/\/[^"'`\s]+mermaid[^"'`\s]*)["'`]/.exec(pageText)
const engineUrl = engineMatch ? engineMatch[1] : "https://cdnjs.cloudflare.com/"
try {
  const answer = await fetch(engineUrl, { method: "HEAD", signal: AbortSignal.timeout(10000) })
  if (!answer.ok) {
    console.log(`SKIPPED: no network - ${engineUrl} answered ${answer.status}`)
    process.exit(NO_NETWORK)
  }
} catch (error) {
  console.log(`SKIPPED: no network - ${engineUrl} could not be reached (${error?.cause?.code ?? error?.name ?? error})`)
  process.exit(NO_NETWORK)
}

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".svg": "image/svg+xml",
  ".png": "image/png", ".ico": "image/x-icon", ".woff2": "font/woff2", ".xml": "application/xml", ".txt": "text/plain",
}

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
    file = file + ".html"
  }
  const headers = {
    "Content-Type": TYPES[extname(file)] ?? "application/octet-stream",
    "Cache-Control": "no-cache",
    "Content-Security-Policy": POLICY,
  }
  try {
    const body = readFileSync(file)
    response.writeHead(200, headers)
    response.end(request.method === "HEAD" ? undefined : body)
  } catch {
    response.writeHead(404, headers).end("not found")
  }
})
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve))
const pageUrl = `http://127.0.0.1:${server.address().port}${pagePath.startsWith("/") ? "" : "/"}${pagePath}`

const work = mkdtempSync(join(tmpdir(), "plantoir-mermaid-check-"))
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
  server.close()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}

const timer = setTimeout(() => finish(1, "FAIL: the diagrams were not checked within 90 s"), 90000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const COUNT = `({
  diagrams: document.querySelectorAll("code.mermaid").length,
  drawn: document.querySelectorAll("code.mermaid svg, #mermaid-container svg, .mermaid svg").length,
})`

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
  const blocked = []
  const requested = new Map()
  let documentPolicy = null
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
      return
    }
    if (message.method === "Network.requestWillBeSent") {
      requested.set(message.params.requestId, message.params.request.url)
    }
    if (message.method === "Network.responseReceived" && message.params.type === "Document") {
      const headers = message.params.response.headers ?? {}
      for (const name of Object.keys(headers)) {
        if (name.toLowerCase() === "content-security-policy") documentPolicy = headers[name]
      }
    }
    if (message.method === "Network.loadingFailed" && message.params.blockedReason === "csp") {
      blocked.push(requested.get(message.params.requestId) ?? message.params.requestId)
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    return answer?.result?.value
  }

  socket.onopen = async () => {
    await send("Network.enable")
    await send("Page.enable")
    await send("Network.setCacheDisabled", { cacheDisabled: true })
    await send("Page.navigate", { url: pageUrl })
    let seen = { diagrams: 0, drawn: 0 }
    for (let tries = 0; tries < 120; tries += 1) {
      await pause(250)
      if ((await evaluate("document.readyState")) !== "complete") continue
      seen = (await evaluate(COUNT)) ?? seen
      if (seen.diagrams > 0 && seen.drawn >= seen.diagrams) break
      if (blocked.length > 0 && tries > 20) break
    }
    clearTimeout(timer)
    const problems = []
    if (documentPolicy !== POLICY) problems.push(`the page was not served under the policy from _headers (it carried ${JSON.stringify(documentPolicy)}) - the check would prove nothing`)
    if (seen.diagrams === 0) problems.push("no code.mermaid on the page - the check would prove nothing")
    else if (seen.drawn < seen.diagrams) problems.push(`${seen.drawn} of ${seen.diagrams} diagrams drawn`)
    for (const url of blocked) problems.push(`the policy blocked ${url} (blocked=csp)`)
    const summary = `${seen.drawn} of ${seen.diagrams} diagrams drawn, ${blocked.length} requests blocked by the policy`
    if (problems.length > 0) return finish(1, "FAIL: " + summary + "\n" + problems.join("\n"))
    finish(0, `OK: ${summary}, under the policy _headers carries`)
  }
}
