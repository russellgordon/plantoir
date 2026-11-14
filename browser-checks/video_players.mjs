// YouTube and Vimeo players (#692) at the size Russell set, in headless
// Chrome for Testing, against a server this check starts itself.
//
// The page is the page-authoring skill's video example as verify.sh 6n
// built it (the one Authoring Example page holding a `plantoir-video`
// player). EVERY request to another host is refused before it leaves
// (Fetch.failRequest), so no player document loads and nothing can play;
// the audio is muted as well. What is measured is the player's own box,
// which the site's stylesheet decides alone:
//
//  * at a 1300 px window, every player is exactly 600 px wide and 16:9
//    (Quartz's own `.external-embed.youtube { width: 100% }` made the old
//    player 650 x 366 there, measured 2026-11-13);
//  * at a 390 px window, every player fills the article's column and is
//    still 16:9 (358 x 201 measured on the same day);
//  * every player carries a title, loading="lazy", the referrer policy and
//    a privacy-enhanced YouTube or a do-not-track Vimeo address;
//  * the Vimeo player pasted as code keeps its own width and height
//    attributes and gets none of Plantoir's classes.
//
// The layout is the same in WebKit (measured 2026-11-13 by the #692
// planner: the same numbers before the change in both engines), so this is
// asked of Chrome, as picture_heights.mjs is.
//
//   node browser-checks/video_players.mjs <chrome> <site folder>

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!chromePath || !siteFolder) {
  console.error("usage: node video_players.mjs <chrome> <site folder>")
  process.exit(2)
}
const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png",
  ".woff2": "font/woff2", ".ttf": "font/ttf", ".woff": "font/woff",
}

function pageWithPlayers() {
  for (const name of readdirSync(siteFolder).sort()) {
    if (!/^Authoring-Example-\d+\.html$/.test(name)) continue
    if (readFileSync(join(siteFolder, name), "utf-8").includes("plantoir-video")) return "/" + name.replace(/\.html$/, "")
  }
  return null
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

const PAGE = pageWithPlayers()
if (PAGE === null) {
  console.log("FAIL: no Authoring Example page in the site holds a YouTube or Vimeo player made from the picture form")
  process.exit(1)
}

const work = mkdtempSync(join(tmpdir(), "plantoir-video-players-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1300,900", "--use-mock-keychain",
  "--password-store=basic", "--hide-scrollbars", "--mute-audio", "--autoplay-policy=user-gesture-required",
  "about:blank",
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
setTimeout(() => finish(1, "FAIL: the players were not measured within 90 s"), 90000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

const PLAYERS = `(() => {
  const article = document.querySelector("article")
  const column = article ? Math.round(article.getBoundingClientRect().width) : 0
  const players = [...document.querySelectorAll("article iframe")].map((frame) => {
    const box = frame.getBoundingClientRect()
    return {
      ours: frame.classList.contains("plantoir-video"),
      classes: frame.className,
      src: frame.getAttribute("src"),
      title: frame.getAttribute("title"),
      loading: frame.getAttribute("loading"),
      referrer: frame.getAttribute("referrerpolicy"),
      widthAttribute: frame.getAttribute("width"),
      width: Math.round(box.width * 100) / 100,
      height: Math.round(box.height * 100) / 100,
    }
  })
  return { column, players }
})()`

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
  let refused = 0
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
      return
    }
    if (message.method === "Fetch.requestPaused") {
      const asked = new URL(message.params.request.url)
      if (asked.hostname === "127.0.0.1") {
        send("Fetch.continueRequest", { requestId: message.params.requestId })
      } else {
        refused += 1
        send("Fetch.failRequest", { requestId: message.params.requestId, errorReason: "BlockedByClient" })
      }
    }
  })
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    if (answer?.exceptionDetails) throw new Error(JSON.stringify(answer.exceptionDetails).slice(0, 400))
    return answer?.result?.value
  }
  const measure = async (width) => {
    await send("Emulation.setDeviceMetricsOverride", { width, height: 900, deviceScaleFactor: 1, mobile: false })
    let last = null
    for (let tries = 0; tries < 40; tries += 1) {
      await pause(250)
      const state = await evaluate(`document.readyState === "complete" ? ${PLAYERS} : null`).catch(() => null)
      if (state !== null && state.players.length > 0 && last !== null && JSON.stringify(state) === JSON.stringify(last)) return state
      last = state
    }
    return last
  }
  socket.onopen = async () => {
    try {
      await send("Page.enable")
      await send("Runtime.enable")
      await send("Fetch.enable", { patterns: [{ urlPattern: "*", requestStage: "Request" }] })
      siteServer = await serve()
      await send("Emulation.setDeviceMetricsOverride", { width: 1300, height: 900, deviceScaleFactor: 1, mobile: false })
      await send("Page.navigate", { url: `http://127.0.0.1:${siteServer.address().port}${PAGE}` })
      const wide = await measure(1300)
      const narrow = await measure(390)
      const problems = []
      if (wide === null || narrow === null) return finish(1, `FAIL: ${PAGE} never settled`)
      const ours = wide.players.filter((player) => player.ours)
      const pasted = wide.players.filter((player) => !player.ours && (player.src ?? "").startsWith("https://player.vimeo.com/"))
      if (ours.length < 2) problems.push(`${ours.length} players made from the picture form, expected at least the YouTube and the Vimeo one`)
      if (pasted.length !== 1) problems.push(`${pasted.length} pasted Vimeo players, expected one`)
      for (const player of ours) {
        if (player.width !== 600) problems.push(`at 1300 px a player is ${player.width} px wide, not 600 (${player.src})`)
        if (Math.abs(player.height - (player.width * 9) / 16) > 1) problems.push(`at 1300 px a player is ${player.width} x ${player.height}, not 16:9 (${player.src})`)
        if (!player.title) problems.push(`a player has no title (${player.src})`)
        if (player.loading !== "lazy") problems.push(`a player loads at once, not lazily (${player.src})`)
        if (player.referrer !== "strict-origin-when-cross-origin") problems.push(`a player's referrer policy is ${player.referrer} (${player.src})`)
        const privately = (player.src ?? "").startsWith("https://www.youtube-nocookie.com/embed/")
          || /^https:\/\/player\.vimeo\.com\/video\/\d+\?(h=[A-Za-z0-9]+&)?dnt=1/.test(player.src ?? "")
        if (!privately) problems.push(`a player's address is neither privacy-enhanced YouTube nor do-not-track Vimeo: ${player.src}`)
      }
      for (const player of pasted) {
        if (player.widthAttribute !== "640") problems.push(`the pasted Vimeo player lost its own width (${player.widthAttribute})`)
      }
      for (const player of narrow.players.filter((each) => each.ours)) {
        if (Math.abs(player.width - narrow.column) > 1) problems.push(`at 390 px a player is ${player.width} px wide in a ${narrow.column} px column`)
        if (Math.abs(player.height - (player.width * 9) / 16) > 1) problems.push(`at 390 px a player is ${player.width} x ${player.height}, not 16:9`)
      }
      if (problems.length > 0) return finish(1, "FAIL: " + problems.join("; "))
      const sizes = `${ours[0].width} x ${ours[0].height} at 1300 px, ${narrow.players.find((each) => each.ours).width} x ${narrow.players.find((each) => each.ours).height} at 390 px`
      return finish(0, `OK: ${ours.length} players on ${PAGE.slice(1)}, each ${sizes}, titled, lazy, privately addressed; the pasted Vimeo player untouched; ${refused} requests to other hosts refused, so nothing played`)
    } catch (error) {
      finish(1, "FAIL: " + (error?.stack ?? error))
    }
  }
}
