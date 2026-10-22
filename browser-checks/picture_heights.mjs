// Pictures are laid out at their real height before they scroll into view
// (#609), in headless Chrome for Testing, against a server this check starts
// itself.
//
// Quartz's own base.scss gives every img `content-visibility: auto`, so a
// picture off screen is laid out at ZERO height and takes its real height
// only when it nears the window. Chromium absorbs the shift with scroll
// anchoring; Safari has none, so there the text below jumps down by the
// picture's height mid-scroll. support/quartz/components/styles/pictures.scss
// turns that off for every picture. The layout is the same in both engines -
// only whether the shift can be SEEN differs - so this is asked of Chrome:
//
//  1. verify.sh's Picture Fixture loaded in a laptop-sized window; every
//     picture's bytes and the page's faces arrived (before that, a picture
//     has no height in any engine, with or without the rule - #612);
//  2. each picture is well below the window (or the check could not fail),
//     and has a height above 0 BEFORE anything is scrolled;
//  3. scrolled to each picture in turn: the page's height and every
//     picture's height are what they were before scrolling.
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
const PICTURES = 2
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
  // The fixture's own pictures, read where they are on the page (document
  // coordinates, so a scroll does not move the numbers).
  const PICTURE_STATE = `(() => {
    const pictures = [...document.querySelectorAll("article img")].filter((picture) => picture.getAttribute("src").includes("plantoir-hazard-"))
    return {
      pictures: pictures.map((picture) => ({
        src: picture.getAttribute("src").split("/").pop(),
        arrived: picture.complete && picture.naturalHeight > 0,
        top: Math.round(picture.getBoundingClientRect().top + scrollY),
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
      if (problems.length > 0) return finish(1, "FAIL: " + [...new Set(problems)].join("\nFAIL: "))
      const described = before.pictures.map((picture) => `${picture.height} px tall at ${picture.top} px down`).join(" and ")
      finish(0, `OK: ${before.pictures.length} pictures laid out before any scroll (${described}, window ${before.window} px); the page stayed ${before.page} px tall scrolling to each (${visited.join(", ")})`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
