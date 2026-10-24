// GeoGebra sketches opened in headless Chrome for Testing under the
// Content-Security-Policy a Netlify publish sends (#578, geogebraFences.policy).
//
// The stock GeoGebra engine never loads under that policy (script-src 'self'
// 'unsafe-eval' <hashes>): its loader runs code as inline script text and
// starts a blob: worker. scripts/geogebra_engine.py makes six exact
// replacements so it loads with the policy unchanged, and the site's loader
// (geogebra.inline.ts) keeps what GeoGebra adds to <head> across Quartz's
// page change. This serves a CLONE of the built site, whose _headers the
// publish's own two writers have written, with the policy line read from
// that file, ON [::1] - never 127.0.0.1 or localhost, where GeoGebra's loader
// takes a path (inline text) no class site takes - and checks, twice: as a
// plain Netlify site, and again cross-origin isolated (COOP + COEP, as a
// page with live input is served):
//
// 1. nothing of GeoGebra is fetched until a tap;
// 2. a tap on the first sketch opens it - a canvas, from the site's own
//    engine and its own copy of the sketch - and a tap on a sketch made from
//    commands opens that too;
// 3. Quartz's page change to a second page with a sketch, a tap there, and
//    back to the first page and a tap again, each open, GeoGebra's loader
//    frame under <html> throughout (the engine's replacement 3);
// 4. for paper: a picture of each open sketch beside it (beforeprint), the
//    applet hidden and the picture shown under print media, the button
//    hidden, and the attribution printed with its address as plain text;
// 5. zero requests refused by the policy, zero securitypolicyviolation
//    events, and from the first tap on, zero requests to any other host
//    (before it, the page's own theme fetches its fonts, which is Quartz's
//    and not GeoGebra's);
// 6. the built site holds exactly ONE file with the sketch's SHA-256
//    (geogebraFences.files: published once);
// 7. the sketch made from commands (stage 3) runs every line, and shows
//    under it exactly the lines geogebraFences.commands.cases says GeoGebra
//    refuses, each in GeoGebra's own words - and not one of the scripting
//    lines that work (SetValue, SetColor, ZoomIn), which evalCommand's own
//    answer would have reported; SetValue(a, 3) has set a to 3;
// 8. the geogebra.org sketch on the second page (stage 4) opens from the
//    site's own copy, with its author and licence linked.
//
// It prints a line starting "OK:" with the time from tap to sketch and the
// bytes fetched, or "FAIL:" with what went wrong.
//
//   node browser-checks/geogebra_applet.mjs <chrome> <site folder> <page A> <page B> <sketch .ggb>
//
// Kept OUT of scripts/ like print_handout.mjs: it needs a browser on the Mac,
// not the image. No packages: Node 22's own WebSocket.

import { spawn } from "node:child_process"
import { createHash } from "node:crypto"
import { createServer } from "node:http"
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"
import { gzipSync } from "node:zlib"

const [chromePath, siteFolder, pageA, pageB, sketchFile] = process.argv.slice(2)
if (!chromePath || !siteFolder || !pageA || !pageB || !sketchFile) {
  console.error("usage: node geogebra_applet.mjs <chrome> <site folder> <page A> <page B> <sketch .ggb>")
  process.exit(2)
}

function policyFromHeadersFile() {
  let text
  try {
    text = readFileSync(join(siteFolder, "_headers"), "utf-8")
  } catch {
    return null
  }
  const found = []
  for (const line of text.split("\n")) {
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

// 6: the sketch is published once.
function filesWithHash(folder, digest) {
  const found = []
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name)
      if (entry.isDirectory()) walk(path)
      else if (entry.isFile() && createHash("sha256").update(readFileSync(path)).digest("hex") === digest) found.push(path.slice(folder.length))
    }
  }
  walk(folder)
  return found
}
const contract = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8")).geogebraFences
const sketchDigest = createHash("sha256").update(readFileSync(sketchFile)).digest("hex")
const copies = filesWithHash(siteFolder, sketchDigest)

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".svg": "image/svg+xml", ".png": "image/png",
  ".ico": "image/x-icon", ".woff2": "font/woff2", ".woff": "font/woff", ".ttf": "font/ttf", ".xml": "application/xml",
  ".txt": "text/plain", ".ggb": "application/vnd.geogebra.file",
}

let isolated = false
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
  if (isolated) {
    headers["Cross-Origin-Opener-Policy"] = "same-origin"
    headers["Cross-Origin-Embedder-Policy"] = "require-corp"
  }
  try {
    const body = readFileSync(file)
    response.writeHead(200, headers)
    response.end(request.method === "HEAD" ? undefined : body)
  } catch {
    response.writeHead(404, headers).end("not found")
  }
})
await new Promise((resolve) => server.listen(0, "::1", resolve))
const origin = `http://[::1]:${server.address().port}`
const urlOf = (page) => origin + (page.startsWith("/") ? "" : "/") + page

const work = mkdtempSync(join(tmpdir(), "plantoir-geogebra-check-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1400,1000",
  "--use-mock-keychain", "--password-store=basic", "--enable-unsafe-swiftshader",
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

const problems = []
const timer = setTimeout(() => finish(1, "FAIL: the sketches were not checked within 300 s\n" + problems.join("\n")), 300000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const WATCH = `window.__plantoirCheck = { violations: [], beforeprint: 0 };
document.addEventListener("securitypolicyviolation", (event) => window.__plantoirCheck.violations.push(event.violatedDirective + " " + (event.blockedURI || "inline")));
window.addEventListener("beforeprint", () => { window.__plantoirCheck.beforeprint += 1 });`

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
  const requests = new Map()
  let blocked = []
  let refusedInLog = []
  let offSite = []
  let tapped = false
  let fetchedSinceTap = []
  let engineRequests = 0
  let bytes = 0
  let refusedLines = 0
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
      return
    }
    if (message.method === "Network.requestWillBeSent") {
      const url = message.params.request.url
      requests.set(message.params.requestId, url)
      if (tapped && !url.startsWith(origin) && !url.startsWith("data:") && !url.startsWith("blob:") && !url.startsWith("about:")) offSite.push(url)
      if (url.includes("/static/geogebra/")) engineRequests += 1
      if (tapped && url.startsWith(origin)) fetchedSinceTap.push(url)
    }
    if (message.method === "Network.loadingFinished") {
      bytes += message.params.encodedDataLength ?? 0
    }
    // The browser's own console line for a refusal, from any frame - GWT's
    // hidden frame included, whose page events this check cannot hear.
    if (message.method === "Log.entryAdded" && /Content Security Policy/i.test(message.params.entry?.text ?? "")) {
      refusedInLog.push(message.params.entry.text.slice(0, 160))
    }
    if (message.method === "Network.loadingFailed" && message.params.blockedReason === "csp") {
      blocked.push(requests.get(message.params.requestId) ?? message.params.requestId)
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    if (answer?.exceptionDetails) return { thrown: answer.exceptionDetails.exception?.description ?? answer.exceptionDetails.text }
    return answer?.result?.value
  }
  const waitFor = async (expression, tries = 120) => {
    for (let attempt = 0; attempt < tries; attempt += 1) {
      const value = await evaluate(expression)
      if (value === true) return true
      await pause(250)
    }
    return false
  }
  // Taps the sketch at `index` on this page and waits for it to open.
  // Answers {opened, ms, bytes} - the time from the tap to the canvas, and
  // what the network carried meanwhile.
  const tap = async (index) => {
    tapped = true
    fetchedSinceTap = []
    const before = bytes
    const ready = await waitFor(`document.querySelectorAll("figure.pl-geogebra .pl-geogebra-open").length > ${index}`, 40)
    if (!ready) return { opened: false, ms: null, bytes: 0, why: "no such sketch on the page" }
    await evaluate(`(() => { window.__plantoirTap = performance.now(); document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-open").click(); return true })()`)
    const opened = await waitFor(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; if (f && f.classList.contains("pl-geogebra-loaded") && f.querySelector(".pl-geogebra-applet canvas")) { window.__plantoirOpened = performance.now(); return true } return false })()`)
    const ms = opened ? Math.round(await evaluate("window.__plantoirOpened - window.__plantoirTap")) : null
    const message = opened ? "" : await evaluate(`document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-message").textContent`)
    // What a host that compresses (Netlify, Cloudflare) would send for it.
    let compressed = 0
    for (const url of new Set(fetchedSinceTap)) {
      try {
        compressed += gzipSync(readFileSync(join(siteFolder, decodeURIComponent(new URL(url).pathname)))).length
      } catch {}
    }
    return { opened, ms, bytes: bytes - before, compressed, requests: new Set(fetchedSinceTap).size, why: message, frame: await frameUnderHtml() }
  }
  // GeoGebra's hidden loader frame: under <html>, which Quartz's page change
  // keeps (the engine's replacement 3), never under <body>, which it
  // replaces - measured without it, Chromium opened no sketch after a page
  // change until a reload.
  const frameUnderHtml = async () => await evaluate(`(() => { const frame = document.getElementById("web3d"); return !!frame && frame.parentElement === document.documentElement })()`)
  const change = async (page) => {
    const target = urlOf(page)
    const changed = await evaluate(`(() => { if (typeof window.spaNavigate !== "function") return false; window.spaNavigate(new URL(${JSON.stringify(target)})); return true })()`)
    if (!changed) return { changed: false, frame: false }
    const arrived = await waitFor(`location.href === ${JSON.stringify(target)} && document.querySelectorAll("figure.pl-geogebra").length > 0`, 40)
    return { changed: arrived, frame: await frameUnderHtml() }
  }

  socket.onopen = async () => {
    await send("Network.enable")
    await send("Page.enable")
    await send("Runtime.enable")
    await send("Log.enable")
    await send("Network.setCacheDisabled", { cacheDisabled: true })
    await send("Page.addScriptToEvaluateOnNewDocument", { source: WATCH })
    const said = []
    if (copies.length !== 1) problems.push(`the site holds ${copies.length} files with the sketch's SHA-256 (${copies.join(", ")}), not exactly one`)
    for (const phase of ["policy", "isolated"]) {
      isolated = phase === "isolated"
      blocked = []
      refusedInLog = []
      offSite = []
      tapped = false
      engineRequests = 0
      await send("Page.navigate", { url: urlOf(pageA) })
      await waitFor(`document.readyState === "complete" && document.querySelectorAll("figure.pl-geogebra").length > 0`, 40)
      await pause(500)
      if (engineRequests !== 0) problems.push(`${phase}: ${engineRequests} requests for GeoGebra before any tap`)
      const first = await tap(0)
      if (!first.opened) problems.push(`${phase}: the first sketch on ${pageA} did not open (${first.why})`)
      const commands = await tap(1)
      if (!commands.opened) problems.push(`${phase}: the sketch made from commands on ${pageA} did not open (${commands.why})`)
      // 7: which of its lines GeoGebra refused, and in what words.
      const ran = await waitFor(`document.querySelectorAll("figure.pl-geogebra")[1].dataset.geogebraCommands === "ran"`, 80)
      const lines = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; const spec = JSON.parse(f.dataset.geogebra); const box = f.querySelector(".pl-geogebra-applet"); const api = window[box.id.replace(/-box$/, "")]; return { commands: spec.commands, shown: Array.from(f.querySelectorAll(":scope > .pl-geogebra-lines li")).map((li) => li.textContent), a: api && typeof api.getValue === "function" ? api.getValue("a") : null, dialogs: f.querySelectorAll(".dialogComponent").length } })()`)
      const said = new Map(contract.commands.cases.map((item) => [item.text, item.said]))
      const wanted = []
      for (const command of lines?.commands ?? []) {
        const words = said.get(command.text)
        if (words) wanted.push(contract.words.site.lineCouldNotRun.replace("{line}", String(command.line)).replace("{said}", words))
      }
      refusedLines = lines?.shown?.length ?? 0
      if (!ran) problems.push(`${phase}: the commands sketch's lines did not finish running`)
      else if (JSON.stringify(lines.shown) !== JSON.stringify(wanted)) problems.push(`${phase}: under the commands sketch: ${JSON.stringify(lines.shown)}, not the contract's ${JSON.stringify(wanted)}`)
      if (lines?.a !== 3) problems.push(`${phase}: SetValue(a, 3) did not set a to 3 (a is ${lines?.a})`)
      if (lines?.dialogs) problems.push(`${phase}: ${lines.dialogs} of GeoGebra's dialogs were left on the page`)
      if (isolated) {
        const crossOriginIsolated = await evaluate("window.crossOriginIsolated")
        if (crossOriginIsolated !== true) problems.push("isolated: the page was not cross-origin isolated - the phase would prove nothing")
      }

      // 4: paper.
      await evaluate(`window.dispatchEvent(new Event("beforeprint"))`)
      const pictured = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[0]; const p = f && f.querySelector(":scope > img.pl-geogebra-print"); return !!p && p.src.startsWith("data:image/png;base64,") && p.src.length > 1000 })()`)
      if (!pictured) problems.push(`${phase}: no picture of the open sketch was made for paper`)
      await send("Emulation.setEmulatedMedia", { media: "print" })
      const paper = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[0]; const shown = (selector) => { const e = f.querySelector(selector); return !!e && getComputedStyle(e).display !== "none" }; return { applet: shown(".pl-geogebra-applet"), picture: shown(":scope > img.pl-geogebra-print"), button: shown(".pl-geogebra-open"), attribution: shown(".pl-geogebra-print-attribution"), address: (f.querySelector(".pl-geogebra-print-addresses") || {}).textContent || "", screenLink: shown(".pl-geogebra-attribution") } })()`)
      await send("Emulation.setEmulatedMedia", { media: "" })
      if (!paper || paper.applet || !paper.picture || paper.button || !paper.attribution || paper.screenLink || !paper.address.includes("https://www.geogebra.org")) {
        problems.push(`${phase}: on paper the sketch is not its picture with the printed attribution: ${JSON.stringify(paper)}`)
      }
      // Does a real print fire beforeprint? Said, not required: the handout's
      // own prepare step does the same work (print.inline.ts).
      const pdf = await send("Page.printToPDF", { printBackground: false })
      const fired = await evaluate("window.__plantoirCheck.beforeprint")
      if (!pdf?.data) problems.push(`${phase}: the page could not be printed to PDF`)

      // 3: the page change, a tap there, and back again.
      const toB = await change(pageB)
      if (!toB.changed) problems.push(`${phase}: Quartz's page change to ${pageB} did not happen`)
      const second = await tap(0)
      if (!second.opened) problems.push(`${phase}: after the page change, the sketch on ${pageB} did not open (${second.why})`)
      // 8 (stage 4): the geogebra.org sketch on page B, from the site's own
      // copy in static/ - its author and licence linked under it.
      const material = await tap(1)
      if (!material.opened) problems.push(`${phase}: the geogebra.org sketch on ${pageB} did not open (${material.why})`)
      const credit = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; return Array.from(f.querySelectorAll(".pl-geogebra-attribution a")).map((a) => a.getAttribute("href")) })()`)
      const wantedCredit = [contract.attribution.engineUrl, contract.attribution.materialUrl.replace("{id}", "plantoirvrfy578"), contract.attribution.licenceUrl]
      if (JSON.stringify(credit) !== JSON.stringify(wantedCredit)) problems.push(`${phase}: the geogebra.org sketch's links are ${JSON.stringify(credit)}, not ${JSON.stringify(wantedCredit)}`)
      const backToA = await change(pageA)
      if (!backToA.changed) problems.push(`${phase}: Quartz's page change back to ${pageA} did not happen`)
      const third = await tap(0)
      if (!third.opened) problems.push(`${phase}: back on ${pageA}, the sketch did not open again (${third.why})`)
      if (!first.frame || !toB.frame || !backToA.frame) {
        problems.push(`${phase}: GeoGebra's loader frame is not under <html> before and after each page change (${first.frame}, ${toB.frame}, ${backToA.frame})`)
      }

      const violations = (await evaluate("window.__plantoirCheck.violations")) ?? []
      for (const url of blocked) problems.push(`${phase}: the policy blocked ${url}`)
      for (const line of refusedInLog) problems.push(`${phase}: the browser said: ${line}`)
      for (const violation of violations) problems.push(`${phase}: securitypolicyviolation ${violation}`)
      for (const url of offSite) problems.push(`${phase}: a request left the site: ${url}`)
      said.push(`${phase}: first sketch ${first.ms} ms and ${first.bytes.toLocaleString("en-CA")} bytes in ${first.requests} requests, ${first.compressed.toLocaleString("en-CA")} gzipped (its loader frame under <html>, kept across both page changes), from commands ${commands.ms} ms (${refusedLines} of its lines refused, as the contract says), after a page change ${second.ms} ms, the geogebra.org sketch's saved copy ${material.ms} ms, back again ${third.ms} ms, ${blocked.length + violations.length + refusedInLog.length} refusals, ${offSite.length} requests off the site, beforeprint ${fired ? "fired" : "not fired"} by printToPDF`)
    }
    clearTimeout(timer)
    if (problems.length > 0) return finish(1, "FAIL: " + problems.join("\n"))
    finish(0, `OK: ${said.join("; ")}; the sketch is on the site once (${copies[0]})`)
  }
}
