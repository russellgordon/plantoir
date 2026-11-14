// YouTube and Vimeo players (#692) at the size Russell set, in headless
// Chrome for Testing AND Playwright's WebKit (Safari's engine), against a
// server this check starts itself.
//
// The page is the page-authoring skill's video example as verify.sh 6n
// built it (the one Authoring Example page holding a `plantoir-video`
// player). EVERY request to another host is refused before it leaves (the
// context's own router), so no player document loads and nothing can play;
// Chrome's audio is muted as well. What is measured is the player's own
// box, which the site's stylesheet decides alone:
//
//  * at a 1300 px window, every player is exactly 600 px wide and 16:9
//    (Quartz's own `.external-embed.youtube { width: 100% }` made the old
//    player 650 x 366 there, measured 2026-11-13);
//  * at a 390 px window, every player fills the article's column and is
//    still 16:9 (358 x 201 measured on the same day);
//  * every player carries a title, loading="lazy", the referrer policy and
//    a privacy-enhanced YouTube or a do-not-track Vimeo address;
//  * the Vimeo player pasted as code keeps its own width attribute and gets
//    none of Plantoir's classes.
//
// Engines come from the same places as the rendered check's
// (rendered_features.mjs): Playwright's driver and WebKit from Plantoir's
// browsers cache (./browser-checks/fetch-browsers.sh), Chrome for Testing
// from the path given. An engine that is not there is a `SKIPPED: <engine>:`
// line, never a pass; with no engine at all the check exits 3.
//
//   node browser-checks/video_players.mjs <chrome> <site folder>
//
// Prints `OK: ...` first on a pass, then `ENGINES: <the engines that ran>`.

import { createServer } from "node:http"
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs"
import { createRequire } from "node:module"
import { homedir } from "node:os"
import { extname, join, normalize } from "node:path"

const [chromePath, siteFolder] = process.argv.slice(2)
if (!siteFolder) {
  console.error("usage: node video_players.mjs <chrome> <site folder>")
  process.exit(2)
}
const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png",
  ".woff2": "font/woff2", ".ttf": "font/ttf", ".woff": "font/woff",
}
const CACHE = join(process.env.PLANTOIR_BROWSERS_CACHE ?? join(homedir(), "Library", "Caches", "Plantoir-dev", "browsers"), "playwright")

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

// { chromium, webkit }: each { type, launch } or null, with why one is missing.
function loadEngines() {
  const missing = {}
  const engines = { chromium: null, webkit: null }
  process.env.PLAYWRIGHT_BROWSERS_PATH = join(CACHE, "engines")
  let playwright = null
  try {
    playwright = createRequire(join(CACHE, "package.json"))("playwright-core")
  } catch {
    const why = `no Playwright driver in ${CACHE} (run ./browser-checks/fetch-browsers.sh)`
    return { engines, missing: { chromium: why, webkit: why } }
  }
  if (chromePath && existsSync(chromePath)) {
    engines.chromium = { type: playwright.chromium, launch: { executablePath: chromePath, args: ["--mute-audio"] } }
  } else {
    missing.chromium = "no Chrome for Testing on this Mac (set PLANTOIR_CHROME; documentation/06-quartz-customizations.md F7)"
  }
  const webkitPath = playwright.webkit.executablePath()
  if (existsSync(webkitPath)) engines.webkit = { type: playwright.webkit, launch: {} }
  else missing.webkit = `Safari's engine is not in ${join(CACHE, "engines")} (run ./browser-checks/fetch-browsers.sh)`
  return { engines, missing }
}

const PLAYERS = () => {
  const article = document.querySelector("article")
  const column = article ? Math.round(article.getBoundingClientRect().width) : 0
  const players = [...document.querySelectorAll("article iframe")].map((frame) => {
    const box = frame.getBoundingClientRect()
    return {
      ours: frame.classList.contains("plantoir-video"),
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
}
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

async function measure(page, width) {
  await page.setViewportSize({ width, height: 900 })
  let last = null
  for (let tries = 0; tries < 40; tries += 1) {
    await pause(250)
    const state = await page.evaluate(PLAYERS).catch(() => null)
    if (state !== null && state.players.length > 0 && last !== null && JSON.stringify(state) === JSON.stringify(last)) return state
    last = state
  }
  return last
}

function judge(wide, narrow) {
  const problems = []
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
  const narrowOurs = narrow.players.filter((each) => each.ours)
  for (const player of narrowOurs) {
    if (Math.abs(player.width - narrow.column) > 1) problems.push(`at 390 px a player is ${player.width} px wide in a ${narrow.column} px column`)
    if (Math.abs(player.height - (player.width * 9) / 16) > 1) problems.push(`at 390 px a player is ${player.width} x ${player.height}, not 16:9`)
  }
  const sizes = ours.length > 0 && narrowOurs.length > 0
    ? `${ours[0].width} x ${ours[0].height} at 1300 px, ${narrowOurs[0].width} x ${narrowOurs[0].height} at 390 px`
    : "no size"
  return { problems, count: ours.length, sizes }
}

async function runEngine(name, engine, base, path) {
  const browser = await engine.type.launch({ headless: true, ...engine.launch })
  let refused = 0
  try {
    const context = await browser.newContext({ viewport: { width: 1300, height: 900 } })
    await context.route("**/*", (route) => {
      if (new URL(route.request().url()).hostname === "127.0.0.1") return route.continue()
      refused += 1
      return route.abort("blockedbyclient")
    })
    const page = await context.newPage()
    await page.goto(base + path, { waitUntil: "load", timeout: 60000 })
    const wide = await measure(page, 1300)
    const narrow = await measure(page, 390)
    if (wide === null || narrow === null) return { name, problems: [`${path} never settled`] }
    return { name, refused, ...judge(wide, narrow) }
  } finally {
    await browser.close().catch(() => {})
  }
}

const PAGE = pageWithPlayers()
if (PAGE === null) {
  console.log("FAIL: no Authoring Example page in the site holds a YouTube or Vimeo player made from the picture form")
  process.exit(1)
}
const { engines, missing } = loadEngines()
const ready = Object.entries(engines).filter(([, engine]) => engine !== null)
if (ready.length === 0) {
  for (const [name, why] of Object.entries(missing)) console.log(`SKIPPED: ${name}: ${why}`)
  console.log("ENGINES: none")
  process.exit(3)
}
const server = await serve()
const base = `http://127.0.0.1:${server.address().port}`
const timer = setTimeout(() => { console.log("FAIL: the players were not measured within 180 s"); process.exit(1) }, 180000)
let outcomes = []
try {
  outcomes = await Promise.all(ready.map(([name, engine]) =>
    runEngine(name, engine, base, PAGE).catch((error) => ({ name, problems: ["could not drive the browser: " + (error?.message ?? error)] }))))
} finally {
  clearTimeout(timer)
  server.close()
}
const failed = outcomes.filter((outcome) => outcome.problems.length > 0)
if (failed.length > 0) {
  console.log("FAIL: " + failed.map((outcome) => `[${outcome.name}] ` + outcome.problems.join("; ")).join(" | "))
} else {
  const said = outcomes.map((outcome) => `${outcome.name}: ${outcome.count} players, each ${outcome.sizes}, ${outcome.refused} requests to other hosts refused`)
  console.log(`OK: on ${PAGE.slice(1)}, titled, lazy, privately addressed, the pasted Vimeo player untouched, nothing played - ${said.join("; ")}`)
}
for (const [name, why] of Object.entries(missing)) console.log(`SKIPPED: ${name}: ${why}`)
console.log("ENGINES: " + outcomes.map((outcome) => outcome.name).join(","))
process.exit(failed.length > 0 ? 1 : 0)
