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
//    site's own copy, with its author and licence linked;
// 9. on the quiz page, when one is given (stage 5, geogebraFences.quizzes):
//    nothing of GeoGebra is fetched when it loads; the sketch in a
//    question's EXPLANATION is not visible, and still nothing is fetched
//    once the question is answered and the explanation shown - until its
//    button is tapped, when it opens; the sketch in the QUESTION of a
//    shuffled quiz opens, and after a print (beforeprint and afterprint,
//    which put the choices in Markdown order and back) it is the same
//    applet, in the same place, outside the choices, still running
//    commands; and Start again hides the explanation's open sketch, and a
//    second answer shows the same applet again, not zero-sized, still
//    running commands;
// 10. once the commands sketch's lines have run (#755): no GeoGebra shade
//    (.gwt-PopupPanelGlass) is left anywhere on the page, the sketch's own
//    canvas is what lies at its centre, and its slider a, dragged with real
//    pointer events (Input.dispatchMouseEvent), changes value - read through
//    the applet before and after. Then the MUST-FAIL: one of GeoGebra's
//    dialogs taken off the page the way the loader did before #755 (dialog
//    and shade removed, never closed) leaves GeoGebra modal, and the same
//    drag must NOT move the slider; if it does, the drag proves nothing.
//    A DOM count alone passed on the broken loader: each dialog that is
//    removed rather than closed leaves the app ignoring pointer input.
// 11. GeoGebra's reset icon (#792), pressed with real pointer events at the
//    place it is painted on the canvas, on the commands sketch and on the
//    file sketch, each after a real drag has moved something (slider a,
//    point A): the construction read through the applet comes back to what
//    it opened as (every object, a at 3, A where it was), with no shade over
//    it and its canvas on top, and it takes a drag again. Before #792 the
//    commands sketch came back with no object at all and the file sketch
//    was removed (an empty box), which is how this item fails on the old
//    loader. Chromium only here; WebKit was measured by hand
//    (documentation/06, "The reset icon").
// 12. Real key presses while a sketch's lines run (#792 review M1): the
//    third sketch on page B, 150 lines that each make a point, is opened
//    and Shift+Tab then Space are pressed again and again with the focus in
//    it until its lines have run. Every point must be there, and again after
//    a press on its reset icon. Before the fix a reset reached through the
//    keyboard got in while the lines ran: a sketch left half built, and that
//    half kept as its start.
//
// 13. While the first sketch opens (#756), pressed with a REAL pointer at
//    its button's centre (#761), never a scripted click: the engine's
//    first request is HELD (Fetch.requestPaused) so the in-between state
//    can be read, then let go. Inside the sketch's own card, where the
//    student pressed, the contract's words.site.loading and under it
//    words.site.loadingFirstTime show, in a polite live region, readable
//    (contrast at least 4.5) in light and dark, the card on top of the
//    applet's box laid out underneath it; the figure's height and the
//    page's scroll height stay within 1 px from before the press, through
//    every change while it opens, to the drawn sketch (before #756 the
//    page grew by one sketch height while the engine arrived, 393.6 px on
//    the fixture page, which is how this item fails on the old loader);
//    the spinner turns, and is still when the reader asks for less motion;
//    once drawn, the words are gone and the sketch's canvas is at its
//    centre. Then the fourth sketch on the first page, from a file and not
//    yet opened, pressed with its file refused (Fetch.failRequest): the
//    words go, the button is back, and the contract's
//    words.site.couldNotLoad is said below the sketch. No picture is taken
//    here: a screenshot made Chrome fetch the theme's font again, which
//    the off-site count then reported (measured); the pictures to look at
//    come from the issue's own measurements.
//
// It prints a line starting "OK:" with the time from tap to sketch and the
// bytes fetched, or "FAIL:" with what went wrong.
//
//   node browser-checks/geogebra_applet.mjs <chrome> <site folder> <page A> <page B> <sketch .ggb> [<quiz page>]
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

const [chromePath, siteFolder, pageA, pageB, sketchFile, quizPage] = process.argv.slice(2)
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
  // 13 (#756): what happens to a request Fetch pauses - "hold" keeps it
  // until let go, "fail" refuses it, anything else lets it through.
  let fetchMode = "pass"
  let held = []
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
      return
    }
    if (message.method === "Fetch.requestPaused") {
      const requestId = message.params.requestId
      if (fetchMode === "hold") held.push(requestId)
      else if (fetchMode === "fail") void send("Fetch.failRequest", { requestId, errorReason: "Failed" })
      else void send("Fetch.continueRequest", { requestId })
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
  // With `watch` (13, #756), the button is pressed with a real pointer and
  // `watch.during()` reads the sketch while it opens, before the wait.
  const tap = async (index, watch = null) => {
    tapped = true
    fetchedSinceTap = []
    const before = bytes
    const ready = await waitFor(`document.querySelectorAll("figure.pl-geogebra .pl-geogebra-open").length > ${index}`, 40)
    if (!ready) return { opened: false, ms: null, bytes: 0, why: "no such sketch on the page" }
    if (watch === null) {
      await evaluate(`(() => { window.__plantoirTap = performance.now(); document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-open").click(); return true })()`)
    } else {
      const pressed = await pressOpen(index)
      if (pressed.why) return { opened: false, ms: null, bytes: 0, why: pressed.why }
      await watch.during()
    }
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
  // 13 (#756): presses the open button of the sketch at `index` the way a
  // person does - move, press, release at its centre (Input.dispatchMouseEvent),
  // never a scripted click (#761) - once the button is what lies there.
  const pressOpen = async (index) => {
    const place = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; f.scrollIntoView({ block: "center", behavior: "instant" }); const b = f.querySelector(".pl-geogebra-open"); const r = b.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + r.height / 2; const top = document.elementFromPoint(x, y); return { x, y, onButton: !!top && b.contains(top) } })()`)
    if (!place || place.thrown) return { why: `its button could not be found: ${place?.thrown}` }
    if (!place.onButton) return { why: "its button is not what lies at the button's centre, so a press there would miss it" }
    const mouse = (type, buttons) => send("Input.dispatchMouseEvent", { type, x: place.x, y: place.y, button: "left", buttons, clickCount: type === "mouseMoved" ? 0 : 1 })
    await mouse("mouseMoved", 0)
    await evaluate("(() => { window.__plantoirTap = performance.now(); return true })()")
    await mouse("mousePressed", 1)
    await mouse("mouseReleased", 0)
    return {}
  }
  // 13 (#756): the sketch at `index`, its card's words and the sizes that
  // must not move. `figure` and `scroll` are the figure's height and the
  // page's scroll height; the rest describe the card's live region.
  const opening = async (index) => await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; const card = f.querySelector(":scope > .pl-geogebra-card"); const region = card && card.querySelector(":scope > .pl-geogebra-loading"); const box = f.querySelector(":scope > .pl-geogebra-applet"); const message = f.querySelector(":scope > .pl-geogebra-message"); const button = f.querySelector(".pl-geogebra-open"); const rgb = (text) => (text.match(/[0-9.]+/g) || []).slice(0, 3).map(Number); const lum = (c) => { const [r, g, b] = c.map((v) => { v = v / 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }); return 0.2126 * r + 0.7152 * g + 0.0722 * b }; const ratio = (a, b) => { const [x, y] = [lum(rgb(a)), lum(rgb(b))].sort((p, q) => q - p); return Math.round(((x + 0.05) / (y + 0.05)) * 100) / 100 }; const out = { figure: f.getBoundingClientRect().height, scroll: document.documentElement.scrollHeight, opening: f.classList.contains("pl-geogebra-opening"), loaded: f.classList.contains("pl-geogebra-loaded"), boxShown: !!box && !box.hidden, button: !!button && !button.disabled && getComputedStyle(button).visibility !== "hidden" && getComputedStyle(card).display !== "none", message: message && !message.hidden ? message.textContent : "" }; if (!region) return { ...out, region: false }; const r = region.getBoundingClientRect(); const c = card.getBoundingClientRect(); const style = getComputedStyle(region); const lines = Array.from(region.querySelectorAll(".pl-geogebra-loading-line")); const spinner = region.querySelector(".pl-geogebra-spinner"); const top = document.elementFromPoint(c.left + c.width / 2, c.top + c.height / 2); return { ...out, region: true, role: region.getAttribute("role"), live: region.getAttribute("aria-live"), text: region.textContent, lines: lines.map((line) => line.textContent), contrast: lines.map((line) => ratio(getComputedStyle(line).color, style.backgroundColor)), visible: r.width > 0 && r.height > 0 && Number(style.opacity) > 0 && style.visibility !== "hidden", inCard: r.top >= c.top - 0.5 && r.bottom <= c.bottom + 0.5 && r.left >= c.left - 0.5 && r.right <= c.right + 0.5, cardOnTop: !!top && card.contains(top), spinner: spinner ? getComputedStyle(spinner).animationName : null } })()`)
  // 13 (#756): every change to the figure while it opens, and every frame
  // until it is drawn, records the figure's height and the page's scroll
  // height; read back as their least and greatest.
  const watchSizes = async (index) => await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; const seen = { figure: [Infinity, -Infinity], scroll: [Infinity, -Infinity], samples: 0 }; window.__plantoirSizes = seen; const take = () => { if (f.classList.contains("pl-geogebra-loaded")) return; const h = f.getBoundingClientRect().height, s = document.documentElement.scrollHeight; seen.figure = [Math.min(seen.figure[0], h), Math.max(seen.figure[1], h)]; seen.scroll = [Math.min(seen.scroll[0], s), Math.max(seen.scroll[1], s)]; seen.samples += 1 }; window.__plantoirSizesWatcher = new MutationObserver(take); window.__plantoirSizesWatcher.observe(f, { attributes: true, childList: true, subtree: true }); const frame = () => { take(); if (!f.classList.contains("pl-geogebra-loaded")) requestAnimationFrame(frame) }; requestAnimationFrame(frame); return true })()`)
  // 13 (#756): the first sketch opened with its engine held, read while it
  // opens, then let go. Answers what `tap` answers, with `said` and
  // `problems` for this item.
  const opensInItsBox = async (phase) => {
    const found = []
    const words = [contract.words.site.loading, contract.words.site.loadingFirstTime]
    await evaluate(`document.querySelectorAll("figure.pl-geogebra")[0].scrollIntoView({ block: "center", behavior: "instant" })`)
    const before = await opening(0)
    await watchSizes(0)
    held = []
    fetchMode = "hold"
    await send("Fetch.enable", { patterns: [{ urlPattern: "*/static/geogebra/HTML5/*", requestStage: "Request" }] })
    let during = null
    let dark = null
    let still = null
    const opened = await tap(0, {
      during: async () => {
        // At once: the words are put in by the press itself.
        const atPress = await opening(0)
        if (!atPress.region || !atPress.visible || !atPress.opening) found.push(`${phase}: right after the press, the first sketch's card does not show its words: ${JSON.stringify(atPress)}`)
        // Then the box laid out under the card, its engine held.
        const laidOut = await waitFor(`(() => { const box = document.querySelectorAll("figure.pl-geogebra")[0].querySelector(":scope > .pl-geogebra-applet"); return !box.hidden })()`, 120)
        for (let attempt = 0; attempt < 120 && held.length === 0; attempt += 1) await pause(250)
        if (!laidOut || held.length === 0) found.push(`${phase}: the first sketch's box was ${laidOut ? "" : "not "}laid out and ${held.length} of the engine's requests were held, so the state while it opens could not be read`)
        during = await opening(0)
        const theme = await evaluate(`document.documentElement.getAttribute("saved-theme")`)
        await evaluate(`(() => { document.documentElement.setAttribute("saved-theme", "dark"); return true })()`)
        dark = await opening(0)
        await evaluate(`(() => { const theme = ${JSON.stringify(theme)}; if (theme === null) document.documentElement.removeAttribute("saved-theme"); else document.documentElement.setAttribute("saved-theme", theme); return true })()`)
        await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-reduced-motion", value: "reduce" }] })
        still = await opening(0)
        await send("Emulation.setEmulatedMedia", { media: "", features: [] })
        fetchMode = "pass"
        for (const requestId of held) await send("Fetch.continueRequest", { requestId })
        held = []
      },
    })
    fetchMode = "pass"
    await send("Fetch.disable")
    const sizes = await evaluate(`(() => { window.__plantoirSizesWatcher && window.__plantoirSizesWatcher.disconnect(); return window.__plantoirSizes })()`)
    const after = await opening(0)
    const centre = await evaluate(`(() => { const box = document.querySelectorAll("figure.pl-geogebra")[0].querySelector(".pl-geogebra-applet"); const r = box.getBoundingClientRect(); const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return !!top && top.tagName === "CANVAS" && box.contains(top) })()`)
    if (during !== null) {
      if (!during.region || during.role !== "status" || during.live !== "polite") found.push(`${phase}: the first sketch's card has no polite live region: ${JSON.stringify({ region: during.region, role: during.role, live: during.live })}`)
      if (JSON.stringify(during.lines) !== JSON.stringify(words)) found.push(`${phase}: while the first sketch opens its card says ${JSON.stringify(during.lines)}, not the contract's ${JSON.stringify(words)}`)
      if (!during.visible || !during.inCard || !during.cardOnTop) found.push(`${phase}: while the first sketch opens its words are not seen inside its card on top of the box: ${JSON.stringify({ visible: during.visible, inCard: during.inCard, cardOnTop: during.cardOnTop, boxShown: during.boxShown })}`)
      if (!during.boxShown) found.push(`${phase}: the first sketch's box was not laid out while it opened, so GeoGebra could not measure it`)
      if (during.message !== "") found.push(`${phase}: while the first sketch opens the line below it says ${JSON.stringify(during.message)}, a second live region saying it again`)
      for (const [theme, read] of [["light", during], ["dark", dark]]) {
        for (const ratio of read?.contrast ?? []) if (!(ratio >= 4.5)) found.push(`${phase}: in ${theme}, a line of the first sketch's words has contrast ${ratio}, under 4.5`)
      }
      if (during.spinner !== "pl-geogebra-spin") found.push(`${phase}: the first sketch's spinner does not turn (${during.spinner})`)
      if (still?.spinner !== "none") found.push(`${phase}: with less motion asked for, the first sketch's spinner still turns (${still?.spinner})`)
    }
    const moved = (range, from) => Math.max(Math.abs(range[0] - from), Math.abs(range[1] - from))
    if (!sizes || sizes.samples === 0) found.push(`${phase}: no size was read while the first sketch opened`)
    else {
      if (moved(sizes.figure, before.figure) > 1 || Math.abs(after.figure - before.figure) > 1) found.push(`${phase}: the first sketch's figure was ${before.figure} px tall before the press, ${sizes.figure[0]} to ${sizes.figure[1]} px while it opened (${sizes.samples} readings) and ${after.figure} px once drawn: the page moved`)
      if (moved(sizes.scroll, before.scroll) > 1 || Math.abs(after.scroll - before.scroll) > 1) found.push(`${phase}: the page's scroll height was ${before.scroll} px before the press, ${sizes.scroll[0]} to ${sizes.scroll[1]} px while the first sketch opened and ${after.scroll} px once drawn`)
    }
    if (opened.opened && (after.opening || (after.region && (after.visible || after.text !== "")) || !centre)) found.push(`${phase}: once drawn, the first sketch still shows its words, or its canvas is not at its centre: ${JSON.stringify({ opening: after.opening, visible: after.visible, text: after.text, canvasAtCentre: centre })}`)
    const said = `the first sketch pressed for real, its card saying the contract's two lines while its engine was held (contrast ${during?.contrast?.join(" and ")} light, ${dark?.contrast?.join(" and ")} dark), the figure ${Math.round(before.figure * 100) / 100} px tall throughout (${sizes?.samples ?? 0} readings)`
    return { ...opened, found, said }
  }
  // 13 (#756): the sketch from a file at `index` on this page, not opened
  // yet, pressed with its file refused (Fetch.failRequest): its words go,
  // its button comes back, and the contract's couldNotLoad is said below
  // it. On the page already showing, so no page load is added to the run.
  const couldNotOpen = async (phase, index) => {
    const found = []
    const fromAFile = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; return !!f && JSON.parse(f.dataset.geogebra).sketch !== null && !f.classList.contains("pl-geogebra-loaded") })()`)
    if (fromAFile !== true) return [`${phase}: the sketch at ${index} on ${pageA} is not an unopened sketch from a file, so its file cannot be refused`]
    fetchMode = "fail"
    await send("Fetch.enable", { patterns: [{ urlPattern: "*.ggb", requestStage: "Request" }] })
    const pressed = await pressOpen(index)
    let gave = false
    if (pressed.why) found.push(`${phase}: with its file refused, ${pressed.why}`)
    else gave = await waitFor(`(() => { const m = document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(":scope > .pl-geogebra-message"); return !m.hidden && m.textContent === ${JSON.stringify(contract.words.site.couldNotLoad)} })()`, 80)
    fetchMode = "pass"
    await send("Fetch.disable")
    const after = await opening(index)
    if (!gave) found.push(`${phase}: with its file refused, the sketch never said the contract's couldNotLoad below it: ${JSON.stringify({ message: after.message })}`)
    else if (after.opening || !after.button || after.boxShown || (after.region && (after.visible || after.text !== ""))) found.push(`${phase}: with its file refused, the sketch is not back to its button with the contract's couldNotLoad below it: ${JSON.stringify({ message: after.message, opening: after.opening, button: after.button, boxShown: after.boxShown, words: after.text })}`)
    return found
  }
  // Drags the knob of slider `name` in the sketch at `index` with real
  // pointer events (Input.dispatchMouseEvent: press, ten moves with the
  // button held, release) toward the middle of its range, and reads its
  // value through the applet before and after (#755). The knob is found
  // from the slider's own XML: its place on the graphics view in pixels, its
  // width, and its range.
  const dragSlider = async (index, name) => {
    // The page may still be scrolling (the tap's own focus, smoothly): the
    // knob is found once the page has stood still for three frames.
    await evaluate(`new Promise((resolve) => { let last = -1, still = 0, frames = 0; const look = () => { frames += 1; still = scrollY === last ? still + 1 : 0; last = scrollY; if (still >= 3 || frames > 300) resolve(true); else requestAnimationFrame(look) }; requestAnimationFrame(look) })`)
    const knob = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; const box = f.querySelector(".pl-geogebra-applet"); const api = window[box.id.replace(/-box$/, "")]; if (!api) return { why: "no applet" }; const slider = /<slider ([^>]*)>/.exec(api.getXML(${JSON.stringify(name)}) || ""); if (!slider) return { why: "it is not a slider" }; const read = (key) => Number((new RegExp("\\\\b" + key + '="([^"]*)"').exec(slider[1]) || [])[1]); if (!/absoluteScreenLocation="true"/.test(slider[1])) return { why: "its place is not given in pixels" }; let canvas = null; for (const each of Array.from(box.querySelectorAll("canvas"))) { if (canvas === null || each.width * each.height > canvas.width * canvas.height) canvas = each } if (canvas === null) return { why: "no canvas" }; const r = canvas.getBoundingClientRect(); const scale = r.width / canvas.offsetWidth; const value = api.getValue(${JSON.stringify(name)}); const min = read("min"), max = read("max"), width = read("width"); const at = (v) => r.left + (read("x") + ((v - min) / (max - min)) * width) * scale; const middle = (min + max) / 2; return { before: value, x: at(value), y: r.top + read("y") * scale, toX: at(value === middle ? min : middle) } })()`)
    if (!knob || knob.why || knob.thrown) return { why: knob?.why ?? knob?.thrown ?? "no answer" }
    const mouse = (type, x, buttons) => send("Input.dispatchMouseEvent", { type, x, y: knob.y, button: "left", buttons, clickCount: type === "mouseMoved" ? 0 : 1 })
    await mouse("mouseMoved", knob.x, 0)
    await pause(50)
    await mouse("mousePressed", knob.x, 1)
    await pause(50)
    for (let step = 1; step <= 10; step += 1) {
      await mouse("mouseMoved", knob.x + ((knob.toX - knob.x) * step) / 10, 1)
      await pause(30)
    }
    await mouse("mouseReleased", knob.toX, 0)
    await pause(100)
    const after = await evaluate(`(() => { const box = document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-applet"); return window[box.id.replace(/-box$/, "")].getValue(${JSON.stringify(name)}) })()`)
    return { before: knob.before, after }
  }
  // What the sketch at `index` holds, through the applet: its objects, the
  // value of slider a and the place of point A (#792).
  const construction = async (index) => await evaluate(`(() => { const box = document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-applet"); const api = window[box.id.replace(/-box$/, "")]; const read = (fn) => { try { return fn() } catch (error) { return "threw" } }; return { names: read(() => api.getAllObjectNames().join(",")), a: read(() => api.exists("a") ? api.getValue("a") : null), A: read(() => api.exists("A") ? [api.getXcoord("A"), api.getYcoord("A")] : null), canvas: !!box.querySelector("canvas") } })()`)
  // Drags point `name` in the sketch at `index` two units up and to the
  // right with real pointer events, found from the graphics view's own
  // coordinate system in the applet's XML (#792).
  const dragPoint = async (index, name) => {
    const point = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; f.scrollIntoView({ block: "center", behavior: "instant" }); const box = f.querySelector(".pl-geogebra-applet"); const api = window[box.id.replace(/-box$/, "")]; if (!api || !api.exists(${JSON.stringify(name)})) return { why: "no such point" }; const system = /<coordSystem ([^>]*)\\/>/.exec(api.getXML() || ""); if (!system) return { why: "no coordinate system in the XML" }; const read = (key) => Number((new RegExp("\\\\b" + key + '="([^"]*)"').exec(system[1]) || [])[1]); let canvas = null; for (const each of Array.from(box.querySelectorAll("canvas"))) { if (canvas === null || each.width * each.height > canvas.width * canvas.height) canvas = each } if (canvas === null) return { why: "no canvas" }; const r = canvas.getBoundingClientRect(); const scale = r.width / canvas.offsetWidth; const at = (x, y) => [r.left + (read("xZero") + x * read("scale")) * scale, r.top + (read("yZero") - y * read("yscale")) * scale]; const x = api.getXcoord(${JSON.stringify(name)}), y = api.getYcoord(${JSON.stringify(name)}); const [fromX, fromY] = at(x, y); const [toX, toY] = at(x + 2, y + 2); return { fromX, fromY, toX, toY } })()`)
    if (!point || point.why || point.thrown) return { why: point?.why ?? point?.thrown ?? "no answer" }
    const mouse = (type, x, y, buttons) => send("Input.dispatchMouseEvent", { type, x, y, button: "left", buttons, clickCount: type === "mouseMoved" ? 0 : 1 })
    await mouse("mouseMoved", point.fromX, point.fromY, 0)
    await pause(50)
    await mouse("mousePressed", point.fromX, point.fromY, 1)
    await pause(50)
    for (let step = 1; step <= 10; step += 1) {
      await mouse("mouseMoved", point.fromX + ((point.toX - point.fromX) * step) / 10, point.fromY + ((point.toY - point.fromY) * step) / 10, 1)
      await pause(30)
    }
    await mouse("mouseReleased", point.toX, point.toY, 0)
    await pause(100)
    return { done: true }
  }
  // Presses GeoGebra's reset icon (showResetIcon: the two arrows in a circle)
  // on the sketch at `index` with a real pointer: move, press, release at the
  // icon, never a scripted click or the applet's own reset() (#761, #792).
  // The icon is no element of the page: GeoGebra 5.4.933.1 paints it onto
  // the graphics view's canvas, at geogebraFences.reset.icon (its centre,
  // in from the view's right edge and down from its top, at the sketch's
  // own size), scaled with the sketch. A press that misses it changes
  // nothing, which the reads after it then report. Answers the place pressed.
  const pressReset = async (index) => {
    const icon = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; f.scrollIntoView({ block: "center", behavior: "instant" }); const box = f.querySelector(".pl-geogebra-applet"); let canvas = null; for (const each of Array.from(box.querySelectorAll("canvas"))) { if (canvas === null || each.width * each.height > canvas.width * canvas.height) canvas = each } if (canvas === null) return { why: "no canvas" }; const r = canvas.getBoundingClientRect(); const scale = r.width / canvas.offsetWidth; const x = r.right - ${contract.reset.icon.fromRight} * scale, y = r.top + ${contract.reset.icon.fromTop} * scale; const top = document.elementFromPoint(x, y); return { x, y, onCanvas: top === canvas } })()`)
    if (!icon || icon.why || icon.thrown) return { why: icon?.why ?? icon?.thrown ?? "no answer" }
    if (!icon.onCanvas) return { why: "the sketch's canvas is not what lies under its reset icon" }
    const mouse = (type, buttons) => send("Input.dispatchMouseEvent", { type, x: icon.x, y: icon.y, button: "left", buttons, clickCount: type === "mouseMoved" ? 0 : 1 })
    await mouse("mouseMoved", 0)
    await pause(30)
    await mouse("mousePressed", 1)
    await pause(30)
    await mouse("mouseReleased", 0)
    return { x: Math.round(icon.x), y: Math.round(icon.y) }
  }
  // Waits for the sketch at `index` to hold `wanted` again after a reset:
  // its own construction is what is waited on, never a clock; 10 s is only
  // the bound past which it never will.
  const constructionComesBack = async (index, wanted) => {
    let now = null
    for (let attempt = 0; attempt < 40; attempt += 1) {
      now = await construction(index)
      if (JSON.stringify(now) === JSON.stringify(wanted)) return { back: true, now }
      await pause(250)
    }
    return { back: false, now }
  }
  // 11 (#792): GeoGebra's reset icon pressed for real on the sketch at
  // `index`, after `change` has moved something a student can move. The
  // construction must come back to `start` (every object, slider a at the
  // value it opened with, point A where it was), with no shade over it and
  // the canvas on top, and still take a drag.
  const resetComesBack = async (phase, index, kind, start, change) => {
    const moved = await change()
    if (moved.why) return `${phase}: on the ${kind}, the drag before the reset could not run: ${moved.why}`
    const changed = await construction(index)
    if (JSON.stringify(changed) === JSON.stringify(start)) return `${phase}: on the ${kind}, the drag before the reset changed nothing, so the reset would prove nothing`
    const pressed = await pressReset(index)
    if (pressed.why) return `${phase}: on the ${kind}, the reset icon could not be pressed: ${pressed.why}`
    const comes = await constructionComesBack(index, start)
    if (!comes.back) return `${phase}: on the ${kind}, the press at (${pressed.x}, ${pressed.y}), where geogebraFences.reset.icon puts the reset icon, did not bring it back to what it opened as, ${JSON.stringify(start)}: it holds ${JSON.stringify(comes.now)}. Either the icon is no longer there to press (a sketch it misses is left as dragged), or reset did not put it back`
    const usable = await evaluate(`(() => { const box = document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-applet"); const r = box.getBoundingClientRect(); const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return { shades: document.querySelectorAll(".gwt-PopupPanelGlass").length, onTop: !!top && top.tagName === "CANVAS" && box.contains(top), top: top ? top.tagName + "." + top.className : null } })()`)
    if (usable?.shades !== 0 || !usable?.onTop) return `${phase}: after a reset the ${kind} is shaded over: ${usable?.shades} shades, ${usable?.top} at its centre`
    const again = await change()
    if (again.why) return `${phase}: after a reset the ${kind} could not be dragged: ${again.why}`
    const draggedAgain = await construction(index)
    if (JSON.stringify(draggedAgain) === JSON.stringify(start)) return `${phase}: after a reset the ${kind} no longer takes a drag`
    return ""
  }
  // 12 (#792 review M1): the sketch at `index` on this page is tapped open
  // and, while its lines run, Shift+Tab and Space are pressed again and
  // again with real key events (Input.dispatchKeyEvent) with the focus in
  // it - which reaches GeoGebra's reset icon through its own keyboard
  // cycle - until its lines have run. Every line makes one point, so all
  // of them must be there once they have, and again after a real press on
  // the reset icon: a reset that got in while they ran left a sketch half
  // built, and kept that half as its start.
  const keysWhileLinesRun = async (phase, index) => {
    tapped = true
    const ready = await waitFor(`document.querySelectorAll("figure.pl-geogebra .pl-geogebra-open").length > ${index}`, 40)
    if (!ready) return { why: "no such sketch on the page" }
    await evaluate(`(() => { document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-open").click(); return true })()`)
    const loaded = await waitFor(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[${index}]; return !!f && f.classList.contains("pl-geogebra-loaded") && !!f.querySelector(".pl-geogebra-applet canvas") })()`, 240)
    if (!loaded) return { why: "it did not open" }
    const ran = `document.querySelectorAll("figure.pl-geogebra")[${index}].dataset.geogebraCommands === "ran"`
    const key = async (type, key, code, keyCode, modifiers, text) => send("Input.dispatchKeyEvent", { type, key, code, windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode, modifiers, ...(text ? { text } : {}) })
    let presses = 0
    let pressedBeforeRan = false
    while (presses < 400 && (await evaluate(ran)) !== true) {
      await evaluate(`(() => { const box = document.querySelectorAll("figure.pl-geogebra")[${index}].querySelector(".pl-geogebra-applet"); if (!box.contains(document.activeElement)) { let canvas = null; for (const each of Array.from(box.querySelectorAll("canvas"))) { if (canvas === null || each.width * each.height > canvas.width * canvas.height) canvas = each } canvas.focus() } return true })()`)
      await key("rawKeyDown", "Tab", "Tab", 9, 8)
      await key("keyUp", "Tab", "Tab", 9, 8)
      await key("keyDown", " ", "Space", 32, 0, " ")
      await key("keyUp", " ", "Space", 32, 0)
      presses += 1
      pressedBeforeRan = true
    }
    if (!pressedBeforeRan) return { why: "its lines had run before a key could be pressed, so the keys prove nothing" }
    if (!(await waitFor(ran, 120))) return { why: "its lines did not finish running" }
    const wanted = await evaluate(`JSON.parse(document.querySelectorAll("figure.pl-geogebra")[${index}].dataset.geogebra).commands.length`)
    const count = async () => { const now = await construction(index); return now.names === "threw" ? -1 : now.names === "" ? 0 : now.names.split(",").length }
    const built = await count()
    const pressed = await pressReset(index)
    if (pressed.why) return { why: `its reset icon could not be pressed: ${pressed.why}` }
    let afterReset = -1
    for (let attempt = 0; attempt < 40; attempt += 1) {
      afterReset = await count()
      if (afterReset === wanted) break
      await pause(250)
    }
    return { presses, wanted, built, afterReset }
  }
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
    let dragSaid = ""
    let resetSaid = ""
    let keysSaid = ""
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
      const first = await opensInItsBox(phase)
      if (!first.opened) problems.push(`${phase}: the first sketch on ${pageA} did not open (${first.why})`)
      problems.push(...first.found)
      const commands = await tap(1)
      if (!commands.opened) problems.push(`${phase}: the sketch made from commands on ${pageA} did not open (${commands.why})`)
      // 7: which of its lines GeoGebra refused, and in what words.
      const ran = await waitFor(`document.querySelectorAll("figure.pl-geogebra")[1].dataset.geogebraCommands === "ran"`, 80)
      // What each sketch holds as it opened, for the reset (11, #792).
      const fileAtStart = await construction(0)
      const linesAtStart = await construction(1)
      const lines = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; const spec = JSON.parse(f.dataset.geogebra); const box = f.querySelector(".pl-geogebra-applet"); const api = window[box.id.replace(/-box$/, "")]; return { commands: spec.commands, shown: Array.from(f.querySelectorAll(":scope > .pl-geogebra-lines li")).map((li) => li.textContent), a: api && typeof api.getValue === "function" ? api.getValue("a") : null, dialogs: f.querySelectorAll(".dialogComponent").length } })()`)
      const refusals = new Map(contract.commands.cases.map((item) => [item.text, item.said]))
      const wanted = []
      for (const command of lines?.commands ?? []) {
        const words = refusals.get(command.text)
        if (words) wanted.push(contract.words.site.lineCouldNotRun.replace("{line}", String(command.line)).replace("{said}", words))
      }
      refusedLines = lines?.shown?.length ?? 0
      if (!ran) problems.push(`${phase}: the commands sketch's lines did not finish running`)
      else if (JSON.stringify(lines.shown) !== JSON.stringify(wanted)) problems.push(`${phase}: under the commands sketch: ${JSON.stringify(lines.shown)}, not the contract's ${JSON.stringify(wanted)}`)
      if (lines?.a !== 3) problems.push(`${phase}: SetValue(a, 3) did not set a to 3 (a is ${lines?.a})`)
      if (lines?.dialogs) problems.push(`${phase}: ${lines.dialogs} of GeoGebra's dialogs were left on the page`)
      // 10 (#755): the sketch a student can actually use once its lines have
      // run - no shade left, the sketch itself on top, and its slider moved
      // by a real drag - and the must-fail: the same drag after a dialog is
      // taken off the page the way the loader did before #755 (and its
      // shade with it) does NOT move the slider, so the drag can tell.
      const usable = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; f.scrollIntoView({ block: "center", behavior: "instant" }); const box = f.querySelector(".pl-geogebra-applet"); const r = box.getBoundingClientRect(); const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return { shades: document.querySelectorAll(".gwt-PopupPanelGlass").length, onTop: !!top && top.tagName === "CANVAS" && box.contains(top), top: top ? top.tagName + "." + top.className : null } })()`)
      if (usable?.shades !== 0) problems.push(`${phase}: ${usable?.shades} of GeoGebra's shades (.gwt-PopupPanelGlass) were left on the page once the commands sketch's lines had run - the sketch reads as a black box`)
      if (!usable?.onTop) problems.push(`${phase}: at the commands sketch's centre the page shows ${usable?.top}, not the sketch's canvas`)
      const drag = await dragSlider(1, "a")
      if (drag.why) problems.push(`${phase}: the commands sketch's slider a could not be dragged: ${drag.why}`)
      else if (drag.after === drag.before) problems.push(`${phase}: a real drag on the commands sketch's slider a left it at ${drag.before} - GeoGebra is not taking pointer input`)
      // 11 (#792): the reset icon, pressed for real, on the sketch written
      // as lines and on the sketch from a file. Before #792 the first came
      // back empty (only the axes) and the second was removed, an empty box.
      const linesReset = await resetComesBack(phase, 1, "sketch written as lines", linesAtStart, async () => {
        const dragged = await dragSlider(1, "a")
        return dragged.why ? dragged : { done: true }
      })
      if (linesReset) problems.push(linesReset)
      const fileReset = await resetComesBack(phase, 0, "sketch from a file", fileAtStart, async () => await dragPoint(0, "A"))
      if (fileReset) problems.push(fileReset)
      resetSaid = linesReset || fileReset ? "" : `, the reset icon pressed for real on both, each back as it opened (${(linesAtStart.names.match(/,/g) ?? []).length + 1} objects and a = ${linesAtStart.a}; ${fileAtStart.names}) and dragged again`
      const removedTheOldWay = await evaluate(`(async () => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; const box = f.querySelector(".pl-geogebra-applet"); const api = window[box.id.replace(/-box$/, "")]; const came = new Promise((resolve) => { const watcher = new MutationObserver(() => { const dialog = box.querySelector(".dialogComponent"); if (dialog === null) return; dialog.remove(); for (const shade of Array.from(document.querySelectorAll(".gwt-PopupPanelGlass"))) shade.remove(); watcher.disconnect(); resolve(true) }); watcher.observe(box, { childList: true, subtree: true }); setTimeout(() => { watcher.disconnect(); resolve(false) }, 10000) }); api.setErrorDialogsActive(true); api.evalCommand(${JSON.stringify(contract.commands.endOfLine)}); api.setErrorDialogsActive(false); return await came })()`)
      const mustFail = removedTheOldWay === true ? await dragSlider(1, "a") : { why: "no dialog came to remove" }
      if (mustFail.why) problems.push(`${phase}: the must-fail could not run: ${mustFail.why}`)
      else if (mustFail.after !== mustFail.before) problems.push(`${phase}: must-fail did not fail: with a dialog removed from the page the way the loader did before #755, the drag still moved a from ${mustFail.before} to ${mustFail.after}, so the drag check proves nothing`)
      dragSaid = `slider a dragged ${drag.before} to ${drag.after} (${usable?.shades} shades left), and ${mustFail.before} to ${mustFail.after} after a dialog removed the old way`
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
      // 12 (#792 review M1): keys pressed while a long sketch's lines run.
      const keyed = await keysWhileLinesRun(phase, 2)
      if (keyed.why) problems.push(`${phase}: the long sketch on ${pageB}: ${keyed.why}`)
      else if (keyed.built !== keyed.wanted || keyed.afterReset !== keyed.wanted) problems.push(`${phase}: with Shift+Tab and Space pressed ${keyed.presses} times while the long sketch's ${keyed.wanted} lines ran, it held ${keyed.built} of their ${keyed.wanted} points once they had run, and ${keyed.afterReset} after a press on its reset icon: a reset got in while the lines ran`)
      else keysSaid = `, ${keyed.presses} presses of Shift+Tab and Space while a ${keyed.wanted}-line sketch ran left all ${keyed.wanted} of its points, and its reset brought back all ${keyed.afterReset}`
      const backToA = await change(pageA)
      if (!backToA.changed) problems.push(`${phase}: Quartz's page change back to ${pageA} did not happen`)
      const third = await tap(0)
      if (!third.opened) problems.push(`${phase}: back on ${pageA}, the sketch did not open again (${third.why})`)
      if (!first.frame || !toB.frame || !backToA.frame) {
        problems.push(`${phase}: GeoGebra's loader frame is not under <html> before and after each page change (${first.frame}, ${toB.frame}, ${backToA.frame})`)
      }

      // 13 (#756): a sketch whose file is refused, on the page now showing.
      const notOpened = await couldNotOpen(phase, 3)
      problems.push(...notOpened)

      // 9 (stage 5): sketches in self-check questions.
      let quizSaid = ""
      if (quizPage) {
        engineRequests = 0
        // A fresh page load: the theme's own font requests come before any
        // tap, as on the first page, and are Quartz's, not GeoGebra's.
        tapped = false
        await send("Page.navigate", { url: urlOf(quizPage) })
        await waitFor(`document.readyState === "complete" && document.querySelectorAll(".plantoir-quiz figure.pl-geogebra").length >= 2 && document.querySelector(".plantoir-quiz-check") !== null`, 40)
        await pause(500)
        const atLoad = engineRequests
        if (atLoad !== 0) problems.push(`${phase}: ${atLoad} requests for GeoGebra when the quiz page loaded`)
        const where = await evaluate(`(() => { const all = Array.from(document.querySelectorAll("figure.pl-geogebra")); return all.map((f) => ({ quiz: !!f.closest(".plantoir-quiz"), explain: !!f.closest(".plantoir-quiz-explain"), choices: !!f.closest(".plantoir-quiz-choices"), visible: f.checkVisibility() })) })()`)
        const stem = where?.[0]
        const explained = where?.[1]
        if (!stem || !stem.quiz || stem.explain || stem.choices || !stem.visible) problems.push(`${phase}: the quiz page's first sketch is not a visible sketch in a question: ${JSON.stringify(stem)}`)
        if (!explained || !explained.explain || explained.visible) problems.push(`${phase}: the explanation's sketch is not hidden inside the explanation before the answer: ${JSON.stringify(explained)}`)
        // Answer the explanation's question rightly, as a student would.
        const answered = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; const quiz = f.closest(".plantoir-quiz"); const right = JSON.parse(quiz.dataset.quiz).correct[0]; quiz.querySelector('.plantoir-quiz-choice[data-choice="' + right + '"] input').click(); quiz.querySelector(".plantoir-quiz-check").click(); return true })()`)
        const shown = answered === true && await waitFor(`document.querySelectorAll("figure.pl-geogebra")[1].checkVisibility()`, 20)
        await pause(500)
        const afterAnswer = engineRequests
        if (!shown) problems.push(`${phase}: answering the question did not show its explanation's sketch`)
        if (afterAnswer !== 0) problems.push(`${phase}: ${afterAnswer} requests for GeoGebra once the explanation was shown, before its button was tapped`)
        const inExplanation = await tap(1)
        if (!inExplanation.opened) problems.push(`${phase}: the sketch in the explanation did not open (${inExplanation.why})`)
        const inQuestion = await tap(0)
        if (!inQuestion.opened) problems.push(`${phase}: the sketch in the shuffled question did not open (${inQuestion.why})`)
        await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[0]; window.__plantoirStem = { box: f.querySelector(".pl-geogebra-applet"), parent: f.parentElement }; window.dispatchEvent(new Event("beforeprint")); window.dispatchEvent(new Event("afterprint")); return true })()`)
        const kept = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[0]; const box = f.querySelector(".pl-geogebra-applet"); const api = window[box.id.replace(/-box$/, "")]; let ran = null; try { api.evalCommand("plantoirAfterPrint = 7"); ran = api.getValue("plantoirAfterPrint") } catch (error) { ran = String(error) } return { same: box === window.__plantoirStem.box, connected: box.isConnected, parent: f.parentElement === window.__plantoirStem.parent, outsideChoices: !f.closest(".plantoir-quiz-choices"), canvas: !!box.querySelector("canvas"), ran } })()`)
        if (!kept || !kept.same || !kept.connected || !kept.parent || !kept.outsideChoices || !kept.canvas || kept.ran !== 7) {
          problems.push(`${phase}: after a print, the sketch in the shuffled question is not the same working applet in its place: ${JSON.stringify(kept)}`)
        }
        // Start again hides the explanation (and its open sketch) again;
        // answering again shows it: the same applet, still drawn at its
        // size and still running commands (stage 5 review, item 2).
        await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; window.__plantoirExplained = f.querySelector(".pl-geogebra-applet"); document.querySelector(".plantoir-quiz-start-again").click(); return true })()`)
        const hiddenAgain = await waitFor(`!document.querySelectorAll("figure.pl-geogebra")[1].checkVisibility()`, 20)
        if (!hiddenAgain) problems.push(`${phase}: Start again did not hide the explanation's sketch`)
        await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; const quiz = f.closest(".plantoir-quiz"); const right = JSON.parse(quiz.dataset.quiz).correct[0]; quiz.querySelector('.plantoir-quiz-choice[data-choice="' + right + '"] input').click(); quiz.querySelector(".plantoir-quiz-check").click(); return true })()`)
        const shownAgain = await waitFor(`document.querySelectorAll("figure.pl-geogebra")[1].checkVisibility()`, 20)
        await pause(500)
        const again = await evaluate(`(() => { const f = document.querySelectorAll("figure.pl-geogebra")[1]; const box = f.querySelector(".pl-geogebra-applet"); const size = box ? box.getBoundingClientRect() : { width: 0, height: 0 }; const canvas = box ? box.querySelector("canvas") : null; const drawn = canvas ? canvas.getBoundingClientRect() : { width: 0, height: 0 }; let ran = null; try { const api = window[box.id.replace(/-box$/, "")]; api.evalCommand("plantoirShownAgain = 5"); ran = api.getValue("plantoirShownAgain") } catch (error) { ran = String(error) } return { same: box === window.__plantoirExplained, connected: !!box && box.isConnected, width: Math.round(size.width), height: Math.round(size.height), canvasWidth: Math.round(drawn.width), canvasHeight: Math.round(drawn.height), ran } })()`)
        if (!shownAgain || !again || !again.same || !again.connected || again.width === 0 || again.height === 0 || again.canvasWidth === 0 || again.canvasHeight === 0 || again.ran !== 5) {
          problems.push(`${phase}: hidden by Start again and shown again, the explanation's sketch is not the same working applet at its size: ${JSON.stringify(again)}`)
        }
        quizSaid = `, on the quiz page ${atLoad} requests at load and ${afterAnswer} once the explanation was shown, its sketch ${inExplanation.ms} ms after the tap, the question's ${inQuestion.ms} ms, the same applet after a print, and the explanation's the same applet at ${again?.width}×${again?.height} after Start again and a second answer`
      }

      const violations = (await evaluate("window.__plantoirCheck.violations")) ?? []
      for (const url of blocked) problems.push(`${phase}: the policy blocked ${url}`)
      for (const line of refusedInLog) problems.push(`${phase}: the browser said: ${line}`)
      for (const violation of violations) problems.push(`${phase}: securitypolicyviolation ${violation}`)
      for (const url of offSite) problems.push(`${phase}: a request left the site: ${url}`)
      said.push(`${phase}: ${first.said}, then ${first.ms} ms and ${first.bytes.toLocaleString("en-CA")} bytes in ${first.requests} requests, ${first.compressed.toLocaleString("en-CA")} gzipped (its loader frame under <html>, kept across both page changes), from commands ${commands.ms} ms (${refusedLines} of its lines refused, as the contract says; ${dragSaid}${resetSaid}${keysSaid}), after a page change ${second.ms} ms, the geogebra.org sketch's saved copy ${material.ms} ms, back again ${third.ms} ms${quizSaid}, ${blocked.length + violations.length + refusedInLog.length} refusals, ${offSite.length} requests off the site, beforeprint ${fired ? "fired" : "not fired"} by printToPDF`)
    }
    clearTimeout(timer)
    if (problems.length > 0) return finish(1, "FAIL: " + problems.join("\n"))
    finish(0, `OK: ${said.join("; ")}; the sketch is on the site once (${copies[0]})`)
  }
}
