// Pictures are laid out at their real height before their bytes arrive
// (#612) and before they scroll into view (#609), in headless Chrome for
// Testing, against a server this check starts itself.
//
// Two causes, one symptom: the text below a picture jumps down by the
// picture's whole height when it gets one. Quartz writes a picture as
// `width="600" height="auto"`, so until its bytes arrive it has no height at
// all (#612: plantoirPictureSizes.ts now writes its real width and height,
// and pictures.scss gives those pictures `height: auto`). And Quartz's
// base.scss gives every img `content-visibility: auto`, so a picture off
// screen is laid out at ZERO height until it nears the window (#609:
// pictures.scss turns that off). Chromium hides the second with scroll
// anchoring and Safari cannot; the layout is the same in both engines - only
// whether the shift can be SEEN differs - so this is asked of Chrome, in
// three phases, on verify.sh's Picture Fixture:
//
//  A. (#612) A first visit on a slow network: the two PNGs' downloads are
//     HELD (Fetch.enable, never answered). Each must already be drawn at its
//     own shape from the page alone, and when the bytes are let through
//     neither picture nor page may change height. Waits on
//     document.fonts.status, NOT document.fonts.ready: Chrome holds that
//     promise until the document finishes loading, which a held picture
//     never lets it do.
//  B. (#609) A fresh visit with every byte arrived: each picture is well
//     below the window (or the check could not fail) and has a height above
//     0 BEFORE anything is scrolled, and scrolling to each in turn changes
//     no picture's height and not the page's. The fixture's third picture,
//     a viewBox-only SVG, is one the build deliberately cannot size, so it
//     is what keeps #609's rule provable now that the PNGs carry sizes.
//  C. (#612) A 390 px window: each sized picture keeps its own shape (the
//     `height: auto` that lets its width shrink without squashing it).
//
//   node browser-checks/picture_heights.mjs <chrome> <site folder>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!chromePath || !siteFolder) {
  console.error("usage: node picture_heights.mjs <chrome> <site folder>")
  process.exit(2)
}
const PAGE = "/Picture-Fixture"
const PICTURES = 3
// The two PNGs' shapes, height over width, as verify.sh draws them. The
// third picture (the viewBox-only SVG) has no entry: the build leaves it
// unsized, and only phase B asks about it.
const SHAPES = { "plantoir-hazard-wide.png": 300 / 900, "plantoir-hazard-tall.png": 1800 / 400 }
const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".svg": "image/svg+xml", ".png": "image/png",
  ".woff2": "font/woff2", ".ttf": "font/ttf", ".woff": "font/woff",
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
      file = file + ".html"
    }
    try {
      const body = readFileSync(file)
      response.writeHead(200, { "Content-Type": TYPES[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-cache" })
      response.end(body)
    } catch {
      response.writeHead(404).end("not found")
    }
  })
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)))
}

const work = mkdtempSync(join(tmpdir(), "plantoir-picture-heights-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1280,900", "--use-mock-keychain",
  "--password-store=basic", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--hide-scrollbars", "--mute-audio", "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })
let siteServer = null
function finish(code, message) {
  console.log(message)
  siteServer?.close()
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}
setTimeout(() => finish(1, "FAIL: the pictures' heights were not checked within 120 s"), 120000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

let buffered = ""
chrome.stderr.on("data", (chunk) => {
  run(chunk).catch((error) => finish(1, "FAIL: could not drive the browser: " + (error?.stack ?? error)))
})

async function run(chunk) {
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
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
    }
  })
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    if (answer?.exceptionDetails) throw new Error(JSON.stringify(answer.exceptionDetails).slice(0, 400))
    return answer?.result?.value
  }
  // The fixture's own pictures, read where they are on the page (document
  // coordinates, so a scroll does not move the numbers).
  const PICTURE_STATE = `(() => {
    const pictures = [...document.querySelectorAll("article img")].filter((picture) => picture.getAttribute("src").includes("plantoir-hazard-"))
    return {
      pictures: pictures.map((picture) => ({
        src: picture.getAttribute("src").split("/").pop(),
        arrived: picture.complete && picture.naturalHeight > 0,
        top: Math.round(picture.getBoundingClientRect().top + scrollY),
        width: Math.round(picture.getBoundingClientRect().width),
        height: Math.round(picture.getBoundingClientRect().height),
      })),
      page: document.documentElement.scrollHeight,
      window: innerHeight,
      scrollY: Math.round(scrollY),
    }
  })()`
  socket.onopen = async () => {
    try {
      await send("Page.enable")
      await send("Runtime.enable")
      siteServer = await serve()
      const base = `http://127.0.0.1:${siteServer.address().port}`

      // A. (#612) The PNGs' bytes held: a first visit on a slow network.
      const held = []
      const heldListener = (event) => {
        const message = JSON.parse(event.data)
        if (message.method === "Fetch.requestPaused") held.push(message.params.requestId)
      }
      socket.addEventListener("message", heldListener)
      const patterns = []
      for (const name of Object.keys(SHAPES)) patterns.push({ urlPattern: `*${name}*`, requestStage: "Request" })
      await send("Fetch.enable", { patterns })
      await send("Page.navigate", { url: base + PAGE })
      let heldState = null
      let heldSteady = 0
      for (let tries = 0; tries < 160 && heldSteady < 4; tries += 1) {
        await pause(250)
        const state = await evaluate(`(() => {
          if (document.readyState === "loading" || document.fonts.status !== "loaded") return null
          return ${PICTURE_STATE}
        })()`).catch(() => null)
        if (state === null || state.pictures.length < PICTURES || held.length < Object.keys(SHAPES).length) {
          heldSteady = 0
          continue
        }
        heldSteady = heldState !== null && state.page === heldState.page ? heldSteady + 1 : 0
        heldState = state
      }
      if (heldState === null || heldSteady < 4) {
        return finish(1, `FAIL: Picture Fixture never settled with its two PNGs' bytes held (${held.length} held): ${JSON.stringify(heldState)}`)
      }
      const heldProblems = []
      for (const picture of heldState.pictures) {
        if (!(picture.src in SHAPES)) continue
        if (picture.arrived) {
          heldProblems.push(`${picture.src} arrived although its bytes were held, so this phase proves nothing`)
        }
        const expected = Math.round(picture.width * SHAPES[picture.src])
        if (picture.width <= 0) {
          heldProblems.push(`${picture.src} had no size at all before its bytes arrived (${picture.width} x ${picture.height} px), so the text below it moved when they did`)
        } else if (Math.abs(picture.height - expected) > 1) {
          heldProblems.push(`${picture.src} was ${picture.width} x ${picture.height} px before its bytes arrived; its own shape makes that ${picture.width} x ${expected}`)
        }
      }
      for (const requestId of held) await send("Fetch.continueRequest", { requestId })
      await send("Fetch.disable")
      socket.removeEventListener("message", heldListener)
      let arrived = null
      for (let tries = 0; tries < 80; tries += 1) {
        await pause(250)
        arrived = await evaluate(PICTURE_STATE)
        if (arrived.pictures.every((picture) => picture.arrived)) break
      }
      if (!arrived.pictures.every((picture) => picture.arrived)) {
        heldProblems.push("the held pictures never arrived once they were let through")
      }
      await pause(250)
      arrived = await evaluate(PICTURE_STATE)
      if (Math.abs(arrived.page - heldState.page) > 1) {
        heldProblems.push(`the page was ${heldState.page} px tall before the pictures' bytes arrived and ${arrived.page} px after: the text below them jumped`)
      }
      for (let index = 0; index < arrived.pictures.length && index < heldState.pictures.length; index += 1) {
        const picture = arrived.pictures[index]
        if (!(picture.src in SHAPES)) continue
        if (Math.abs(picture.height - heldState.pictures[index].height) > 1) {
          heldProblems.push(`${picture.src} was ${heldState.pictures[index].height} px tall before its bytes arrived and ${picture.height} px after`)
        }
      }
      if (heldProblems.length > 0) return finish(1, "FAIL: " + [...new Set(heldProblems)].join("\nFAIL: "))
      const heldSizes = []
      for (const picture of heldState.pictures) {
        if (picture.src in SHAPES) heldSizes.push(`${picture.width} x ${picture.height}`)
      }

      // B. (#609) A fresh visit, every byte let through.
      await send("Page.navigate", { url: "about:blank" })
      await pause(250)
      await send("Page.navigate", { url: base + PAGE })
      // 1. Settled: loaded, every picture's bytes and the faces arrived, and
      // the page's height unchanged for a second (four reads 250 ms apart).
      // Nothing is scrolled while waiting.
      let before = null
      let steady = 0
      for (let tries = 0; tries < 160 && steady < 4; tries += 1) {
        await pause(250)
        const state = await evaluate(`(async () => {
          if (document.readyState !== "complete") return null
          await document.fonts.ready
          return ${PICTURE_STATE}
        })()`).catch(() => null)
        if (state === null || state.pictures.length < PICTURES || !state.pictures.every((picture) => picture.arrived)) {
          steady = 0
          continue
        }
        steady = before !== null && state.page === before.page ? steady + 1 : 0
        before = state
      }
      if (before === null || steady < 4) {
        return finish(1, `FAIL: Picture Fixture never settled with its ${PICTURES} pictures arrived: ${JSON.stringify(before)}`)
      }
      const problems = []
      // 2. Far enough below the window for the check to mean anything, and
      // laid out before any scroll.
      for (const picture of before.pictures) {
        if (picture.top < before.scrollY + 2 * before.window) {
          problems.push(`${picture.src} is only ${picture.top} px down the page, too close to the window (${before.window} px) for this check to fail - the fixture has changed`)
        }
        if (picture.height <= 0) {
          problems.push(`${picture.src}, ${picture.top} px down the page, had no height before it was scrolled to (${picture.height} px)`)
        }
      }
      // 3. Scrolled to each in turn, at once: nothing grows.
      const visited = []
      for (let index = 0; index < before.pictures.length; index += 1) {
        await evaluate(`(async () => {
          document.documentElement.style.scrollBehavior = "auto"
          const pictures = [...document.querySelectorAll("article img")].filter((picture) => picture.getAttribute("src").includes("plantoir-hazard-"))
          pictures[${index}].scrollIntoView({ block: "center", behavior: "instant" })
          await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)))
        })()`)
        await pause(250)
        const after = await evaluate(PICTURE_STATE)
        visited.push(after.page)
        if (after.page !== before.page) {
          problems.push(`the page grew from ${before.page} to ${after.page} px when ${before.pictures[index].src} was scrolled to`)
        }
        for (let other = 0; other < after.pictures.length; other += 1) {
          if (after.pictures[other].height !== before.pictures[other].height) {
            problems.push(`${after.pictures[other].src} was ${before.pictures[other].height} px tall before scrolling and ${after.pictures[other].height} px once ${before.pictures[index].src} was scrolled to`)
          }
        }
      }
      // C. (#612) In a phone's width every sized picture keeps its own shape.
      await send("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 1, mobile: false })
      await pause(500)
      const narrow = await evaluate(PICTURE_STATE)
      const narrowSizes = []
      for (const picture of narrow.pictures) {
        if (!(picture.src in SHAPES)) continue
        const expected = Math.round(picture.width * SHAPES[picture.src])
        narrowSizes.push(`${picture.width} x ${picture.height}`)
        if (picture.width <= 0 || Math.abs(picture.height - expected) > 1) {
          problems.push(`in a 390 px window ${picture.src} was ${picture.width} x ${picture.height} px; its own shape makes that ${picture.width} x ${expected}`)
        }
      }
      if (problems.length > 0) return finish(1, "FAIL: " + [...new Set(problems)].join("\nFAIL: "))
      const described = before.pictures.map((picture) => `${picture.height} px tall at ${picture.top} px down`).join(", ")
      finish(0, `OK: with their bytes held, ${heldSizes.join(" and ")} px from the page alone and unchanged when they arrived (page ${heldState.page} px both ways); ${before.pictures.length} pictures laid out before any scroll (${described}, window ${before.window} px), the page staying ${before.page} px tall scrolling to each (${visited.join(", ")}); ${narrowSizes.join(" and ")} px in a 390 px window`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
