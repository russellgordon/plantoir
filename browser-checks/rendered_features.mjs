// The rendered check (#597, #807): every kind of diagram, sketch, graph,
// formula, quiz, task box and runnable program on the fixture pages, checked
// in Chrome AND in Safari's engine, the way a student's press reaches them.
//
// The rows, the sabotages and every list the rows judge against are data:
// browser-checks/rendered_rows.json. This file is how each row is checked.
// The pages are browser-checks/fixtures/rendered/, planted as
// `Rendered Check/` by browser-checks/lib/plant_rendered.py (verify.sh into
// EXC2O; verify-deploy.sh into the course it publishes), so the local check
// and the deployed one read the same pages.
//
//   node browser-checks/rendered_features.mjs --site <built site folder> [options]
//   node browser-checks/rendered_features.mjs --base <https://…/ ending in /> --host netlify|cloudflare|github|folder [options]
//
//   --engines chromium,webkit   which engines (default both)
//   --chrome <path>             Chrome for Testing (else PLANTOIR_CHROME, else documentation/06 F7's copy)
//   --only <row>[,<row>…]       run these rows only (and the page rows they share a page with)
//   --expect-red <sabotage>|all with --site only: copy the site, break it one way
//                               (browser-checks/lib/sabotage.py), and pass only when
//                               the row it aims at FAILS for its own reason, in every
//                               engine, and every other row on that page still passes
//                               but the ones rendered_rows.json says it may turn red
//   --json <file>               also write every result as JSON
//
// --site serves the folder with browser-checks/lib/site_server.mjs: each page
// under its address without .html, with the headers the folder's own
// _headers gives it (the Netlify policy and the isolation a page with live
// input gets), on [::1] (GeoGebra's rule). Write the _headers first, the way
// a Netlify publish does (verify.sh does, on a copy).
//
// Every line is `OK: <row> [<engine>]: …`, `FAIL: …` or `SKIPPED: …`.
// Exit 0 when every row asked for passed in every engine asked for; 1 when
// anything FAILED (a missing engine never hides a failure); 3 when nothing
// failed but an engine, or the network a row needs, was not there (a SKIP
// the caller reports by name, never a pass). PLANTOIR_REQUIRE_ENGINES=
// chromium,webkit makes a missing engine a FAILURE (the release gate).
//
// Presses are real: Playwright's click waits for the element to be visible,
// still and the topmost thing at its centre before the engine's own pointer
// events go to it, and pointer drags and keys are the engine's own input,
// never a scripted .click() (#761). Waits are on the state asked about,
// with a ceiling, never a fixed sleep (#819). Nothing plays: media requests
// are refused, Chromium is muted, and no embed is pressed.
//
// Needs Playwright's driver from browser-checks/fetch-browsers.sh's cache
// (playwright-core 1.63.0, pinned by package-lock.json). Node 22 or later.

import { execFileSync } from "node:child_process"
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { createRequire } from "node:module"
import { homedir, tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { startSiteServer } from "./lib/site_server.mjs"

const HERE = dirname(fileURLToPath(import.meta.url))
const ROWS = JSON.parse(readFileSync(join(HERE, "rendered_rows.json"), "utf-8"))
const CONTRACT = JSON.parse(readFileSync(join(HERE, "..", "contracts", "shared-rules.json"), "utf-8"))
const QUIZ_WORDS = CONTRACT.quizCallouts.words.site
const PROGRESS_WORDS = CONTRACT.myProgress.words
const RESET_ICON = CONTRACT.geogebraFences.reset.icon

// The device's own families: a theme font that is one of these is never
// downloaded, so the fonts row has nothing to judge for it.
const DEVICE_FAMILIES = new Set(["system-ui", "-apple-system", "blinkmacsystemfont", "segoe ui", "roboto", "helvetica",
  "helvetica neue", "arial", "georgia", "times", "times new roman", "verdana", "courier", "courier new", "menlo",
  "monaco", "sf mono", "sfmono-regular", "ui-monospace", "ui-sans-serif", "ui-serif", "sans-serif", "serif",
  "monospace", "cursive", "fantasy"])
const MEDIA = /\.(mp3|mp4|m4a|m4v|webm|ogg|oga|ogv|wav|flac|aac|mov)(\?|$)/i

// -------------------- arguments --------------------

function parseArguments(list) {
  const options = { engines: ["chromium", "webkit"], only: null, expectRed: null, host: null }
  for (let index = 0; index < list.length; index += 1) {
    const name = list[index]
    const value = list[index + 1]
    if (name === "--site") { options.site = value; index += 1 }
    else if (name === "--base") { options.base = value; index += 1 }
    else if (name === "--host") { options.host = value; index += 1 }
    else if (name === "--engines") { options.engines = value.split(",").filter((one) => one !== ""); index += 1 }
    else if (name === "--chrome") { options.chrome = value; index += 1 }
    else if (name === "--only") { options.only = value.split(","); index += 1 }
    else if (name === "--expect-red") { options.expectRed = value; index += 1 }
    else if (name === "--json") { options.json = value; index += 1 }
    else throw new Error(`unknown argument ${name}`)
  }
  if (!options.site === !options.base) throw new Error("give exactly one of --site <folder> or --base <url>")
  if (options.base && !options.base.endsWith("/")) throw new Error("--base must end in /")
  if (options.base && !options.host) throw new Error("--base needs --host")
  if (options.site && !options.host) options.host = "local"
  if (options.expectRed && !options.site) throw new Error("--expect-red needs --site: it breaks a copy of a folder")
  for (const engine of options.engines) {
    if (engine !== "chromium" && engine !== "webkit") throw new Error(`unknown engine ${engine}`)
  }
  return options
}

let options
try {
  options = parseArguments(process.argv.slice(2))
} catch (error) {
  console.log("FAIL: " + error.message)
  console.log("usage: node rendered_features.mjs --site <folder> | --base <url/> --host <name> [--engines chromium,webkit] [--chrome <path>] [--only <rows>] [--expect-red <sabotage>|all] [--json <file>]")
  process.exit(2)
}
const REQUIRED = new Set((process.env.PLANTOIR_REQUIRE_ENGINES ?? "").split(",").filter((one) => one !== ""))

// -------------------- engines --------------------

const CACHE = join(process.env.PLANTOIR_BROWSERS_CACHE ?? join(homedir(), "Library", "Caches", "Plantoir-dev", "browsers"), "playwright")

function findChrome() {
  if (options.chrome) return options.chrome
  if (process.env.PLANTOIR_CHROME) return process.env.PLANTOIR_CHROME
  const root = join(homedir(), "Library", "Caches", "Plantoir-dev", "browsers", "chrome")
  let found = null
  try {
    for (const version of readdirSync(root).sort()) {
      for (const platform of readdirSync(join(root, version))) {
        const binary = join(root, version, platform, "Google Chrome for Testing.app", "Contents", "MacOS", "Google Chrome for Testing")
        if (existsSync(binary)) found = binary
      }
    }
  } catch {
    // No copy: the engine is reported missing below.
  }
  return found
}

// Answers { chromium, webkit } (each a Playwright browser type or null) and
// why one is missing.
function loadEngines() {
  const missing = {}
  let playwright = null
  // The engine lives in Plantoir's own cache, never Playwright's shared one
  // (fetch-browsers.sh; plan review M1). Set before the driver is loaded:
  // it reads the variable once.
  process.env.PLAYWRIGHT_BROWSERS_PATH = join(CACHE, "engines")
  try {
    const require = createRequire(join(CACHE, "package.json"))
    playwright = require("playwright-core")
    const wanted = JSON.parse(readFileSync(join(HERE, "package-lock.json"), "utf-8")).packages["node_modules/playwright-core"].version
    const got = require("playwright-core/package.json").version
    if (got !== wanted) {
      playwright = null
      missing.driver = `the cache holds Playwright ${got}, the lockfile pins ${wanted} (run ./browser-checks/fetch-browsers.sh)`
    }
  } catch {
    missing.driver = `no Playwright driver in ${CACHE} (run ./browser-checks/fetch-browsers.sh)`
  }
  const engines = { chromium: null, webkit: null }
  const chrome = findChrome()
  for (const engine of options.engines) {
    if (playwright === null) {
      missing[engine] = missing.driver
      continue
    }
    if (engine === "chromium") {
      if (chrome && existsSync(chrome)) engines.chromium = { type: playwright.chromium, launch: { executablePath: chrome, args: ["--mute-audio"] } }
      else missing.chromium = "no Chrome for Testing on this Mac (set PLANTOIR_CHROME; documentation/06-quartz-customizations.md F7)"
    }
    if (engine === "webkit") {
      const path = playwright.webkit.executablePath()
      if (existsSync(path)) engines.webkit = { type: playwright.webkit, launch: {} }
      else missing.webkit = `Safari's engine (${path.split("/").slice(-2, -1)[0]}) is not in ${join(CACHE, "engines")} (run ./browser-checks/fetch-browsers.sh)`
    }
  }
  return { engines, missing }
}

// -------------------- results --------------------

const results = []
function say(state, row, engine, detail, page) {
  results.push({ state, row, engine, detail, page })
  console.log(`${state}: ${row}${engine ? ` [${engine}]` : ""}: ${detail}`)
}

// -------------------- the network some rows need --------------------

async function reachable(url) {
  try {
    const answer = await fetch(url, { method: "HEAD", signal: AbortSignal.timeout(8000) })
    return answer.status < 500 ? null : `${url} answered ${answer.status}`
  } catch (error) {
    return `${url} could not be reached (${error?.cause?.code ?? error?.name ?? error})`
  }
}

async function networkState() {
  const [cdnjs, google] = await Promise.all([
    reachable("https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.4.0/mermaid.esm.min.mjs"),
    reachable("https://fonts.googleapis.com/css2?family=IBM+Plex+Mono"),
  ])
  return { cdnjs, google }
}

// -------------------- one page, one engine --------------------

const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// Polls `test` (a function evaluated in the page) until it answers something
// truthy or `ceiling` ms pass; answers the last value.
async function waitInPage(page, test, ceiling, argument) {
  const until = Date.now() + ceiling
  let last = null
  while (Date.now() < until) {
    try {
      last = await page.evaluate(test, argument)
    } catch (error) {
      last = null
      if (/Target closed|has been closed/.test(String(error))) throw error
    }
    if (last) return last
    await pause(150)
  }
  return last
}

// A fresh context for one page in one engine, with everything the common rows
// judge recorded from its first request on.
async function openContext(browser, engine, origin) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
  if (engine === "chromium") {
    await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin }).catch(() => {})
  }
  const record = { offSite: [], aborted: new Set(), console: [], pageErrors: [], refused: [], mixed: [] }
  const siteHost = new URL(origin).host
  const allowed = new Set(ROWS.thirdPartyHostsToday.hosts)
  // Every request, from every frame and every worker, through the context's
  // own router: WebKit hands a worker's requests to no page or context
  // listener (#597 review H1, measured).
  await context.route("**/*", async (route) => {
    const request = route.request()
    let url
    try {
      url = new URL(request.url())
    } catch {
      return route.continue()
    }
    if (url.protocol !== "http:" && url.protocol !== "https:") return route.continue()
    if (request.resourceType() === "media" || MEDIA.test(url.pathname)) {
      record.aborted.add(request.url())
      return route.abort()
    }
    if (url.host === siteHost) return route.continue()
    let fromEmbed = false
    try {
      let frame = request.frame()
      while (frame) {
        const frameUrl = frame.url()
        if (/^https?:/.test(frameUrl) && new URL(frameUrl).host !== siteHost) fromEmbed = true
        frame = frame.parentFrame()
      }
      if (request.isNavigationRequest() && request.frame().parentFrame() !== null) fromEmbed = true
    } catch {
      // A worker's request has no frame: it is the page's own.
    }
    record.offSite.push({ host: url.host, path: url.pathname, fromEmbed })
    if (fromEmbed || allowed.has(url.host)) return route.continue()
    // Recorded and refused: nothing the site should not ask for leaves this Mac.
    record.aborted.add(request.url())
    return route.abort()
  })
  return { context, record }
}

function watchPage(page, record) {
  page.on("console", (message) => {
    const text = message.text()
    if (/Mixed Content/i.test(text)) record.mixed.push(text)
    if (/Refused to /.test(text)) record.refused.push(text)
    if (message.type() !== "error") return
    const at = message.location()?.url ?? ""
    if (record.aborted.has(at)) return
    for (const aborted of record.aborted) {
      if (text.includes(aborted)) return
    }
    record.console.push(text)
  })
  page.on("pageerror", (error) => record.pageErrors.push(String(error?.message ?? error)))
  page.on("requestfailed", (request) => {
    if (record.aborted.has(request.url())) return
    const why = request.failure()?.errorText ?? ""
    if (/BLOCKED|blocked/.test(why)) record.refused.push(`${request.url()} (${why})`)
  })
}

// -------------------- the rows --------------------

const PAGE_HASH = { Anchor: "#test-of-success" }
const NO_ANCHORING = `document.addEventListener("DOMContentLoaded", () => { const s = document.createElement("style"); s.textContent = "html, body, * { overflow-anchor: none !important; }"; document.head.append(s) })`

function pageUrl(base, page) {
  return base + ROWS.pages[page] + (PAGE_HASH[page] ?? "")
}

async function openPage(context, record, url) {
  const page = await context.newPage()
  watchPage(page, record)
  await page.goto(url, { waitUntil: "load", timeout: 60000 })
  return page
}

const ROW_CHECKS = {}

ROW_CHECKS.mermaid = async ({ page, network }) => {
  if (network.cdnjs) return { skip: `no network - ${network.cdnjs}; the diagram engine comes from cdnjs until #566` }
  // Drawn: an svg in the diagram's code element with groups in it and its
  // labels' words (the source text is gone once Mermaid has drawn).
  const drawn = () => {
    const all = Array.from(document.querySelectorAll("code.mermaid"))
    if (all.length === 0) return null
    let done = 0
    for (const code of all) {
      const svg = code.querySelector("svg")
      if (svg && svg.querySelectorAll("g").length > 0 && /\S/.test(svg.querySelector("g")?.textContent ?? "")) done += 1
    }
    return done === all.length ? { done, all: all.length } : null
  }
  const first = await waitInPage(page, drawn, 30000)
  if (!first) {
    const count = await page.evaluate(() => document.querySelectorAll("code.mermaid").length)
    return { fail: `${count} diagram(s) on the page and not every one drawn: a diagram stayed as source text` }
  }
  const toggle = page.locator("button.darkmode, .darkmode").first()
  if ((await toggle.count()) === 0) return { fail: "the page has no dark-mode button to press" }
  const before = await page.evaluate(() => document.documentElement.getAttribute("saved-theme"))
  await toggle.click({ timeout: 10000 })
  const switched = await waitInPage(page, (was) => document.documentElement.getAttribute("saved-theme") !== was, 5000, before)
  if (!switched) return { fail: "the dark-mode button, pressed, did not change the page's theme" }
  const again = await waitInPage(page, drawn, 30000)
  if (!again) return { fail: "after the dark-mode button was pressed, a diagram stayed as source text" }
  return { ok: `${first.all} diagram(s) drawn, and drawn again in ${await page.evaluate(() => document.documentElement.getAttribute("saved-theme"))}` }
}

ROW_CHECKS.katex = async ({ page }) => {
  const set = await page.evaluate(() => ({ formulas: document.querySelectorAll(".katex").length, errors: document.querySelectorAll(".katex-error").length }))
  if (set.formulas === 0) return { fail: "no formula set on the page (.katex)" }
  if (set.errors > 0) return { fail: `${set.errors} formula(s) shown as a KaTeX error` }
  const faces = await page.evaluate(async () => {
    try {
      await document.fonts.load('1em "KaTeX_Main"', "a+b=c")
    } catch {
      // judged by the faces' own status below
    }
    await document.fonts.ready
    const found = []
    for (const face of document.fonts) {
      if (face.family.replace(/["']/g, "") === "KaTeX_Main") found.push(face.status)
    }
    return found
  })
  if (!faces.includes("loaded")) return { fail: `no KaTeX_Main face loaded (${faces.length} declared: ${faces.join(", ") || "none"})` }
  return { ok: `${set.formulas} formula(s) set in KaTeX_Main, ${faces.filter((one) => one === "loaded").length} of its faces loaded` }
}

ROW_CHECKS.tikz = async ({ page }) => {
  const box = await waitInPage(page, () => { const svg = document.querySelector(".pl-tikz svg"); if (!svg) return null; const r = svg.getBoundingClientRect(); return { width: Math.round(r.width), height: Math.round(r.height) } }, 5000)
  if (!box) return { fail: "the drawing's svg is not on the page" }
  if (box.width < 1 || box.height < 1) return { fail: `the drawing has no size (${box.width} by ${box.height} px)` }
  return { ok: `the drawing is ${box.width} by ${box.height} px` }
}

ROW_CHECKS.graph = async ({ page }) => {
  const segments = await waitInPage(page, () => { let most = 0; for (const path of document.querySelectorAll(".pl-plot svg path.line")) { const d = path.getAttribute("d") ?? ""; most = Math.max(most, (d.match(/[LlCcQqHhVv]/g) ?? []).length) } return most > 1 ? most : null }, 20000)
  if (!segments) return { fail: "no curve drawn: no path.line with more than one segment" }
  return { ok: `a curve of ${segments} segments drawn` }
}

// Runs block `index` of the page's runnable code and waits for `wanted` in its
// output; the status line's words are reported when it never comes.
async function runBlock(page, index, wanted, ceiling, answer, live) {
  const block = page.locator(".plantoir-runner").nth(index)
  const run = block.locator(".plantoir-runner-run")
  await run.waitFor({ state: "visible", timeout: 30000 })
  if (answer !== undefined && !live) {
    await block.locator(".plantoir-runner-input-lines").fill(answer)
  }
  await run.click({ timeout: 15000 })
  if (answer !== undefined && live) {
    const field = block.locator(".plantoir-runner-answer")
    try {
      await field.waitFor({ state: "visible", timeout: ceiling })
    } catch {
      const status = await block.locator(".plantoir-runner-status").textContent().catch(() => "")
      return { fail: `the program that reads a line never asked for it live (its status: "${(status ?? "").trim()}")` }
    }
    await page.keyboard.type(answer)
    await page.keyboard.press("Enter")
  }
  const output = await waitInPage(page, ({ index, wanted }) => {
    const box = document.querySelectorAll(".plantoir-runner")[index]
    const text = box?.querySelector(".plantoir-runner-output")?.textContent ?? ""
    return text.includes(wanted) ? text : null
  }, ceiling, { index, wanted })
  if (!output) {
    const said = await page.evaluate((index) => {
      const box = document.querySelectorAll(".plantoir-runner")[index]
      return { status: box?.querySelector(".plantoir-runner-status")?.textContent ?? "", output: box?.querySelector(".plantoir-runner-output")?.textContent ?? "" }
    }, index)
    return { fail: `did not print ${wanted} (its status: "${said.status.trim()}", its output: "${said.output.trim().slice(0, 120)}")` }
  }
  return { ok: true }
}

function expectsIsolation() {
  return ["local", "netlify", "cloudflare"].includes(options.host)
}

ROW_CHECKS.python = async ({ page }) => {
  const isolated = await page.evaluate(() => self.crossOriginIsolated === true)
  if (expectsIsolation() && !isolated) return { fail: `the Python page is not cross-origin isolated on ${options.host}, where its live input needs it (#583)` }
  const started = Date.now()
  const first = await runBlock(page, 0, "42", 60000)
  if (first.fail) return { fail: "Run " + first.fail }
  const firstSeconds = ((Date.now() - started) / 1000).toFixed(1)
  const second = await runBlock(page, 1, "Hello, World", 30000, "World", isolated)
  if (second.fail) return { fail: "the program that reads a line " + second.fail }
  return { ok: `Run printed 42 (${firstSeconds} s, the engine's first load included), and a typed World came back as Hello, World ${isolated ? "live, in its answer field" : "from its box"}` }
}

ROW_CHECKS.swift = async ({ page }) => {
  const first = await runBlock(page, 0, "42", 60000)
  if (first.fail) return { fail: "Run " + first.fail }
  return { ok: "Run printed 42" }
}

ROW_CHECKS.quiz = async ({ page }) => {
  const quiz = page.locator(".plantoir-quiz").first()
  if ((await quiz.count()) === 0) return { fail: "the quiz did not answer: there is no quiz on the page" }
  const feedback = quiz.locator(".plantoir-quiz-feedback")
  const check = quiz.locator(".plantoir-quiz-check")
  try {
    await check.waitFor({ state: "visible", timeout: 10000 })
  } catch {
    return { fail: "the quiz did not answer: it has no Check button" }
  }
  const choose = async (words) => {
    await quiz.locator(".plantoir-quiz-choice").filter({ hasText: words }).locator("input").first().click({ timeout: 10000 })
    await check.click({ timeout: 10000 })
    return (await waitInPage(page, () => document.querySelector(".plantoir-quiz .plantoir-quiz-feedback")?.textContent || null, 5000)) ?? ""
  }
  const wrong = await choose("32")
  if (wrong.trim() !== QUIZ_WORDS.notRight) return { fail: `the quiz did not answer a wrong choice with quizCallouts.words.site.notRight: it said "${wrong.trim()}"` }
  const right = await choose("42")
  if (right.trim() !== QUIZ_WORDS.right) return { fail: `the quiz did not answer the right choice with quizCallouts.words.site.right: it said "${right.trim()}"` }
  if ((await feedback.count()) !== 1) return { fail: "the quiz did not answer in one place" }
  return { ok: "a wrong choice, then the right one, each answered in the contract's words" }
}

ROW_CHECKS.tasks = async ({ page, context, record, base }) => {
  const box = page.locator("input.plantoir-task").first()
  try {
    await box.waitFor({ state: "visible", timeout: 10000 })
  } catch {
    return { fail: "there is no task box on the page" }
  }
  if (await box.isChecked()) return { fail: "the first box was ticked before anyone pressed it" }
  await box.click({ timeout: 10000 })
  if (!(await box.isChecked())) return { fail: "the box did not tick when pressed" }
  await page.reload({ waitUntil: "load" })
  const kept = await waitInPage(page, () => document.querySelector("input.plantoir-task")?.checked === true, 5000)
  if (!kept) return { fail: "a tick did not survive a reload" }
  return { ok: "a box ticked by a real press was still ticked after a reload" }
}

ROW_CHECKS.progress = async ({ page, base }) => {
  await page.goto(base + "My-Progress", { waitUntil: "load", timeout: 60000 })
  const row = await waitInPage(page, () => {
    const holder = document.querySelector("[data-plantoir-progress]")
    if (!holder) return { why: "no My Progress on the page" }
    for (const link of holder.querySelectorAll("a")) {
      if (/Rendered-Check\/Tasks/.test(link.getAttribute("href") ?? "")) {
        const tableRow = link.closest("tr") ?? link.parentElement
        return { text: (tableRow?.textContent ?? "").replace(/\s+/g, " ").trim() }
      }
    }
    return null
  }, 10000)
  if (!row || row.why) return { fail: `My Progress did not read the Tasks page: ${row?.why ?? "no row for it"}` }
  const wanted = PROGRESS_WORDS.count.replace("{done}", "1").replace("{total}", "2")
  if (!row.text.includes(wanted)) return { fail: `My Progress did not read 1 of 2 on the Tasks page's row: it reads "${row.text}"` }
  return { ok: `My Progress reads ${wanted} on the Tasks page's row` }
}

// GeoGebra: the applet behind figure `index`, read through its own API.
function pointA(index) {
  const box = document.querySelectorAll("figure.pl-geogebra")[index]?.querySelector(".pl-geogebra-applet")
  const api = box && window[box.id.replace(/-box$/, "")]
  if (!api || !api.exists || !api.exists("A")) return null
  return [api.getXcoord("A"), api.getYcoord("A")]
}
function objectCount(index) {
  const box = document.querySelectorAll("figure.pl-geogebra")[index]?.querySelector(".pl-geogebra-applet")
  const api = box && window[box.id.replace(/-box$/, "")]
  try {
    return api.getAllObjectNames().length
  } catch {
    return -1
  }
}
// Whether point A of the file sketch is away from `start` (moved) or back at it.
async function pointAMoved(page, start, ceiling) {
  const deadline = Date.now() + ceiling
  while (Date.now() < deadline) {
    const now = await page.evaluate(pointA, 0).catch(() => null)
    if (now && (Math.abs(now[0] - start[0]) > 0.5 || Math.abs(now[1] - start[1]) > 0.5)) return now
    await pause(150)
  }
  return null
}
async function pointABack(page, start, ceiling) {
  const deadline = Date.now() + ceiling
  while (Date.now() < deadline) {
    const now = await page.evaluate(pointA, 0).catch(() => null)
    if (now && Math.abs(now[0] - start[0]) < 0.01 && Math.abs(now[1] - start[1]) < 0.01) return true
    await pause(150)
  }
  return false
}

async function openSketch(page, index) {
  const figure = page.locator("figure.pl-geogebra").nth(index)
  await figure.locator(".pl-geogebra-open").click({ timeout: 15000 })
  // Open, or the loader's own words that it could not (couldNotLoad), the
  // positive signal that ends the wait early (plan review M2).
  const outcome = await waitInPage(page, (index) => {
    const f = document.querySelectorAll("figure.pl-geogebra")[index]
    if (!f) return null
    if (f.classList.contains("pl-geogebra-loaded") && f.querySelector(".pl-geogebra-applet canvas")) return { open: true }
    const message = f.querySelector(":scope > .pl-geogebra-message")
    if (message && !message.hidden && message.textContent.trim() !== "") return { open: false, said: message.textContent.trim() }
    return null
  }, 90000, index)
  return outcome ?? { open: false, said: "nothing within 90 s" }
}

// Where on the page a point of the sketch's graphics view lies, from the
// view's own coordinate system in the applet's XML.
async function pointOnScreen(page, index, name, dx, dy) {
  return await page.evaluate(({ index, name, dx, dy }) => {
    const figure = document.querySelectorAll("figure.pl-geogebra")[index]
    figure.scrollIntoView({ block: "center", behavior: "instant" })
    const box = figure.querySelector(".pl-geogebra-applet")
    const api = window[box.id.replace(/-box$/, "")]
    if (!api || !api.exists(name)) return { why: "no such point" }
    const system = /<coordSystem ([^>]*)\/>/.exec(api.getXML() || "")
    if (!system) return { why: "no coordinate system in the XML" }
    const read = (key) => Number((new RegExp("\\b" + key + '="([^"]*)"').exec(system[1]) || [])[1])
    let canvas = null
    for (const each of Array.from(box.querySelectorAll("canvas"))) {
      if (canvas === null || each.width * each.height > canvas.width * canvas.height) canvas = each
    }
    if (canvas === null) return { why: "no canvas" }
    const r = canvas.getBoundingClientRect()
    const scale = r.width / canvas.offsetWidth
    const at = (x, y) => [r.left + (read("xZero") + x * read("scale")) * scale, r.top + (read("yZero") - y * read("yscale")) * scale]
    const x = api.getXcoord(name), y = api.getYcoord(name)
    const [fromX, fromY] = at(x, y)
    const [toX, toY] = at(x + dx, y + dy)
    return { fromX, fromY, toX, toY }
  }, { index, name, dx, dy })
}

async function dragPoint(page, index) {
  const point = await pointOnScreen(page, index, "A", 2, 2)
  if (!point || point.why) return point?.why ?? "no answer"
  // Paced like a hand (geogebra_applet.mjs's drag): GeoGebra reads a press
  // that is followed at once by its moves as a tap.
  await page.mouse.move(point.fromX, point.fromY)
  await pause(50)
  await page.mouse.down()
  await pause(50)
  for (let step = 1; step <= 10; step += 1) {
    await page.mouse.move(point.fromX + ((point.toX - point.fromX) * step) / 10, point.fromY + ((point.toY - point.fromY) * step) / 10)
    await pause(30)
  }
  await page.mouse.up()
  await pause(100)
  return null
}

async function pressReset(page, index) {
  const icon = await page.evaluate(({ index, fromRight, fromTop }) => {
    const figure = document.querySelectorAll("figure.pl-geogebra")[index]
    figure.scrollIntoView({ block: "center", behavior: "instant" })
    const box = figure.querySelector(".pl-geogebra-applet")
    let canvas = null
    for (const each of Array.from(box.querySelectorAll("canvas"))) {
      if (canvas === null || each.width * each.height > canvas.width * canvas.height) canvas = each
    }
    if (canvas === null) return { why: "no canvas" }
    const r = canvas.getBoundingClientRect()
    const scale = r.width / canvas.offsetWidth
    const x = r.right - fromRight * scale, y = r.top + fromTop * scale
    return { x, y, onCanvas: document.elementFromPoint(x, y) === canvas }
  }, { index, fromRight: RESET_ICON.fromRight, fromTop: RESET_ICON.fromTop })
  if (!icon || icon.why) return icon?.why ?? "no answer"
  if (!icon.onCanvas) return "the sketch's canvas is not what lies under its reset icon"
  await page.mouse.click(icon.x, icon.y)
  return null
}

const SKETCH_STATE = {}

ROW_CHECKS.geogebra = async ({ page, engine }) => {
  SKETCH_STATE[engine] = { open: false }
  if ((await page.locator("figure.pl-geogebra").count()) < 2) return { fail: "the sketch did not open: the page has fewer than two sketches" }
  const opened = await openSketch(page, 0)
  if (!opened.open) return { fail: `the file sketch did not open on a real press (the page said: ${opened.said})` }
  const start = await waitInPage(page, pointA, 10000, 0)
  if (!start) return { fail: "the file sketch did not open: no point A in it" }
  SKETCH_STATE[engine] = { open: true, start }
  return { ok: `the file sketch opened on a real press, A at (${start.join(", ")})` }
}

ROW_CHECKS["geogebra drag"] = async ({ page, engine }) => {
  const state = SKETCH_STATE[engine]
  if (!state?.open) return { fail: "did not move: the file sketch is not open" }
  // The sabotage that removes a dialog the old way (#755) acts once the
  // sketch is open; wait for it to finish when it is there, so the drag
  // meets the state it made.
  await waitInPage(page, () => { const f = document.querySelector("figure.pl-geogebra"); return !f.dataset.renderedSabotage || f.dataset.renderedSabotage === "dialog removed" }, 10000)
  const why = await dragPoint(page, 0)
  if (why) return { fail: `did not move: the drag could not run (${why})` }
  const moved = await pointAMoved(page, state.start, 3000)
  if (!moved) return { fail: `point A did not move under a real drag: it is still at (${state.start.join(", ")})` }
  state.dragged = true
  return { ok: `point A dragged from (${state.start.join(", ")}) to (${moved.map((n) => Math.round(n * 10) / 10).join(", ")})` }
}

ROW_CHECKS["geogebra reset"] = async ({ page, engine }) => {
  const state = SKETCH_STATE[engine]
  if (!state?.open) return { fail: "the file sketch is not open" }
  if (!state.dragged) {
    const why = await dragPoint(page, 0)
    const moved = await pointAMoved(page, state.start, 3000)
    if (why || !moved) return { fail: "the drag before the reset did not move A, so the reset would prove nothing" }
  }
  const why = await pressReset(page, 0)
  if (why) return { fail: `the reset icon could not be pressed: ${why}` }
  const back = await pointABack(page, state.start, 10000)
  if (!back) return { fail: `a real press on the reset icon did not put A back at (${state.start.join(", ")})` }
  return { ok: "a real press on the reset icon put A back where the sketch opened it" }
}

ROW_CHECKS["geogebra keys"] = async ({ page }) => {
  const index = 1
  const figure = page.locator("figure.pl-geogebra").nth(index)
  await figure.locator(".pl-geogebra-open").click({ timeout: 15000 })
  const loaded = await waitInPage(page, (index) => { const f = document.querySelectorAll("figure.pl-geogebra")[index]; return !!f && f.classList.contains("pl-geogebra-loaded") && !!f.querySelector(".pl-geogebra-applet canvas") }, 90000, index)
  if (!loaded) return { fail: "the 150-line sketch did not open, so no points" }
  const ran = (index) => document.querySelectorAll("figure.pl-geogebra")[index].dataset.geogebraCommands === "ran"
  let presses = 0
  while (presses < 400 && !(await page.evaluate(ran, index))) {
    await page.evaluate((index) => {
      const box = document.querySelectorAll("figure.pl-geogebra")[index].querySelector(".pl-geogebra-applet")
      if (!box.contains(document.activeElement)) {
        let canvas = null
        for (const each of Array.from(box.querySelectorAll("canvas"))) {
          if (canvas === null || each.width * each.height > canvas.width * canvas.height) canvas = each
        }
        canvas?.focus()
      }
    }, index)
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Space")
    presses += 1
  }
  if (presses === 0) return { fail: "its lines had run before a key could be pressed, so the keys prove nothing about its points" }
  if (!(await waitInPage(page, ran, 60000, index))) return { fail: "the 150-line sketch's lines did not finish running, so not all its points" }
  const wanted = await page.evaluate((index) => JSON.parse(document.querySelectorAll("figure.pl-geogebra")[index].dataset.geogebra).commands.length, index)
  const built = await page.evaluate(objectCount, index)
  if (built !== wanted) return { fail: `with Shift+Tab and Space pressed ${presses} times while its lines ran, the sketch held ${built} of its ${wanted} points` }
  const why = await pressReset(page, index)
  if (why) return { fail: `its reset icon could not be pressed (${why}), so its points after a reset are unknown` }
  let afterReset = -1
  for (let attempt = 0; attempt < 60 && afterReset !== wanted; attempt += 1) {
    afterReset = await page.evaluate(objectCount, index)
    if (afterReset !== wanted) await pause(200)
  }
  if (afterReset !== wanted) return { fail: `after a press on its reset icon the sketch held ${afterReset} of its ${wanted} points` }
  return { ok: `${presses} presses of Shift+Tab and Space while its lines ran left all ${wanted} points, and its reset brought back all ${wanted}` }
}

ROW_CHECKS.embeds = async ({ page, record }) => {
  const frames = await page.evaluate(() => Array.from(document.querySelectorAll("article iframe")).map((frame) => frame.src))
  if (frames.length < 4) return { fail: `the Embeds page holds ${frames.length} frames, not the four planted` }
  const answered = new Map()
  page.on("response", (response) => {
    const request = response.request()
    if (request.isNavigationRequest() && request.frame() !== page.mainFrame()) answered.set(request.url(), response.status())
  })
  await page.reload({ waitUntil: "load", timeout: 60000 })
  await pause(3000)
  const problems = []
  for (const src of frames) {
    let status = null
    for (const [url, code] of answered) {
      if (url.split("?")[0] === src.split("?")[0] || url.startsWith(src)) status = code
    }
    if (status === null) problems.push(`${new URL(src).host} answered nothing`)
    else if (status < 200 || status > 299) problems.push(`${new URL(src).host} answered ${status}`)
  }
  if (problems.length > 0) return { fail: "a frame's document did not answer 2xx: " + problems.join("; ") }
  return { ok: `all ${frames.length} frames' documents answered 2xx` }
}

ROW_CHECKS.pdf = async ({ page, context }) => {
  const href = await page.evaluate(() => { const link = Array.from(document.querySelectorAll("article a")).find((a) => /\.pdf(\?|#|$)/i.test(a.getAttribute("href") ?? "")); return link ? link.href : null })
  if (!href) return { fail: "the handout has no link to a PDF" }
  const answer = await context.request.get(href, { failOnStatusCode: false, timeout: 30000 })
  const type = answer.headers()["content-type"] ?? ""
  if (answer.status() !== 200) return { fail: `the PDF link answered ${answer.status()}` }
  if (!/application\/pdf/.test(type)) return { fail: `the PDF link answered 200 with ${type || "no type"}, not application/pdf` }
  return { ok: `the PDF link answered 200 ${type}` }
}

// Stubs the print frame's print() (nothing reaches a printer) and records
// what the print layout made, at the moment it would have printed.
const PRINT_PROBE = `(() => {
  new MutationObserver((changes) => {
    for (const change of changes) {
      for (const node of change.addedNodes) {
        if (node.tagName !== "IFRAME") continue
        const stub = () => {
          try {
            node.contentWindow.print = () => {
              node.contentWindow.dispatchEvent(new Event("beforeprint"))
              const frame = node.contentDocument
              const faces = []
              for (const face of frame.fonts) faces.push(face.family.replace(/["']/g, "") + ":" + face.status)
              window.__plantoirRenderedPrint = {
                pages: frame.querySelectorAll(".pagedjs_page").length,
                diagrams: frame.querySelectorAll(".pagedjs_page code.mermaid svg, .pagedjs_page pre svg").length,
                faces,
              }
              node.contentWindow.dispatchEvent(new Event("afterprint"))
            }
          } catch (error) {
            window.__plantoirRenderedPrint = { error: String(error) }
          }
        }
        stub()
        node.addEventListener("load", stub)
      }
    }
  }).observe(document, { childList: true, subtree: true })
})()`

ROW_CHECKS.print = async ({ page }) => {
  const button = page.locator(".plantoir-print-button")
  try {
    await button.waitFor({ state: "visible", timeout: 10000 })
  } catch {
    return { fail: "the handout has no Print button" }
  }
  await button.click({ timeout: 10000 })
  await page.locator('.plantoir-print-menu button[data-mode="questionsOnly"]').click({ timeout: 10000 })
  const printed = await waitInPage(page, () => window.__plantoirRenderedPrint ?? null, 60000)
  if (!printed) {
    const status = await page.locator(".plantoir-print-status").textContent().catch(() => "")
    return { fail: `the print layout never reached print() (the page says "${(status ?? "").trim()}")` }
  }
  if (printed.error) return { fail: `the print layout could not be read: ${printed.error}` }
  if (printed.pages < 1) return { fail: "the print layout laid out no page: Print fell back to the browser's own layout" }
  if (printed.diagrams < 1) return { fail: `the print layout laid out ${printed.pages} page(s) without the diagram drawn on them` }
  const latin = printed.faces.filter((face) => /LM Roman|Latin Modern/i.test(face))
  if (!latin.some((face) => face.endsWith(":loaded"))) return { fail: `the print layout's Latin Modern face is not loaded (${latin.join(", ") || "none declared"})` }
  return { ok: `the print layout laid out ${printed.pages} page(s) with the diagram drawn, ${latin.filter((face) => face.endsWith(":loaded")).length} Latin Modern face(s) loaded` }
}

// Records every write to the clipboard and how it ended (#597 review L1:
// WebKit refuses readText, and has no clipboard permission to grant).
const CLIPBOARD_SPY = `(() => {
  window.__plantoirCopies = []
  const install = () => {
    if (!navigator.clipboard || navigator.clipboard.__plantoirSpied) return
    const real = navigator.clipboard.writeText.bind(navigator.clipboard)
    navigator.clipboard.writeText = (text) => {
      const entry = { text, state: "pending" }
      window.__plantoirCopies.push(entry)
      const answer = real(text)
      answer.then(() => { entry.state = "resolved" }, (error) => { entry.state = "rejected: " + error })
      return answer
    }
    navigator.clipboard.__plantoirSpied = true
  }
  install()
  document.addEventListener("DOMContentLoaded", install)
})()`

ROW_CHECKS.copy = async ({ page }) => {
  const pre = page.locator("article pre").filter({ has: page.locator(":scope > .clipboard-button") }).first()
  if ((await pre.count()) === 0) return { fail: "the text block has no copy button" }
  await pre.scrollIntoViewIfNeeded()
  const area = await pre.boundingBox()
  await page.mouse.move(area.x + area.width / 2, area.y + 8)
  const shown = await waitInPage(page, () => { const button = document.querySelector("article pre > .clipboard-button"); return button && getComputedStyle(button).opacity === "1" ? true : null }, 5000)
  if (!shown) return { fail: "the copy button did not show when the pointer came over the block" }
  const aim = await page.evaluate(() => {
    const button = document.querySelector("article pre > .clipboard-button")
    const box = button.getBoundingClientRect()
    const x = box.left + box.width / 2, y = box.top + box.height / 2
    const hit = document.elementFromPoint(x, y)
    const expected = Array.from(button.parentElement.querySelectorAll("code [data-line]")).map((line) => line.textContent).join("\n")
    return { x, y, inside: button === hit || button.contains(hit), hit: hit ? hit.tagName + "." + hit.className : null, expected }
  })
  await page.mouse.click(aim.x, aim.y)
  const copied = await waitInPage(page, () => { const copies = window.__plantoirCopies ?? []; const last = copies[copies.length - 1]; return last && last.state !== "pending" ? last : null }, 5000)
  if (!aim.inside) return { fail: `the copy button is not what a pointer at its centre hits (${aim.hit})${copied ? "" : ", and the press copied nothing"}` }
  if (!copied) return { fail: "the copy button, pressed, wrote nothing to the clipboard" }
  if (copied.state !== "resolved") return { fail: `the copy button's write did not succeed: ${copied.state}` }
  const normalise = (text) => text.replace(/\n+$/, "")
  if (aim.expected && normalise(copied.text) !== normalise(aim.expected)) return { fail: `the copy button wrote something other than the block (${copied.text.length} characters, the block has ${aim.expected.length})` }
  return { ok: `the copy button, pressed at its centre, wrote the block's ${copied.text.length} characters` }
}

// Opened with #test-of-success (PAGE_HASH). In Chromium the scroll anchoring
// Safari has never had is switched off from the first paint (NO_ANCHORING).
ROW_CHECKS["heading anchor"] = async ({ page }) => {
  let last = -1
  let steady = 0
  let settled = false
  for (let tries = 0; tries < 120 && !settled; tries += 1) {
    await pause(250)
    const state = await page.evaluate(async () => { await document.fonts.ready; return { live: document.querySelectorAll(".plantoir-runner-live").length, height: document.documentElement.scrollHeight } }).catch(() => null)
    if (state === null || state.live < 8) continue
    steady = state.height === last ? steady + 1 : 0
    last = state.height
    if (steady >= 4) settled = true
  }
  if (!settled) return { fail: "the page never settled (its eight editors and its height), so the heading was not in the top third" }
  const before = await page.evaluate(() => { const h = document.getElementById("test-of-success"); return h ? Math.round(h.getBoundingClientRect().top) : null })
  if (before === null) return { fail: "the page has no #test-of-success heading" }
  // What a slow network does: something above the heading takes its size
  // after the page was shown. On this Mac every piece arrives first, so the
  // page never moves by itself and the row would pass with the landing gone.
  await page.evaluate(() => {
    // First the window is moved by a script, as the sidebar's own scroll to
    // its current entry moves it (#604's measurement); a script's scroll
    // also ends WebKit's own keeping of a fragment in view, which otherwise
    // hides a missing landing on this Mac (measured 2026-11-13).
    window.scrollBy({ top: 400, behavior: "instant" })
    const first = document.querySelector("article .plantoir-runner")
    let top = first
    while (top && top.parentElement && top.parentElement.tagName !== "ARTICLE") top = top.parentElement
    const late = document.createElement("div")
    late.dataset.renderedCheckLate = ""
    late.style.height = "1500px"
    ;(top ?? document.querySelector("article").firstElementChild).before(late)
  })
  let landed = null
  let still = 0
  for (let tries = 0; tries < 40 && still < 4; tries += 1) {
    await pause(150)
    const now = await page.evaluate(() => ({ top: Math.round(document.getElementById("test-of-success").getBoundingClientRect().top), window: innerHeight }))
    still = landed && landed.top === now.top ? still + 1 : 0
    landed = now
  }
  if (landed.top < 0 || landed.top > landed.window / 3) return { fail: `the heading is not in the top third of the window once the page settled: ${landed.top} px from the top of a ${landed.window} px window` }
  return { ok: `the heading is ${landed.top} px from the window's top once the eight editors were mounted and 1,500 px arrived above it (${before} px before)` }
}

// -------------------- the rows every page carries --------------------

async function judgeFonts(page, network) {
  if (network.google) return { skip: `no network - ${network.google}; the theme's fonts come from Google until #566` }
  const outcome = await page.evaluate(async (deviceFamilies) => {
    const device = new Set(deviceFamilies)
    const style = getComputedStyle(document.documentElement)
    const chosen = []
    for (const variable of ["--headerFont", "--bodyFont", "--codeFont"]) {
      const stack = style.getPropertyValue(variable)
      for (const raw of stack.split(",")) {
        const family = raw.trim().replace(/^["']|["']$/g, "")
        if (family === "") continue
        if (!device.has(family.toLowerCase()) && !chosen.includes(family)) chosen.push(family)
        break
      }
    }
    const judged = []
    for (const family of chosen) {
      try {
        await document.fonts.load(`1em "${family}"`)
      } catch {
        // judged by the faces' own status below
      }
      const states = []
      for (const face of document.fonts) {
        if (face.family.replace(/["']/g, "") === family) states.push(face.status)
      }
      judged.push({ family, loaded: states.filter((one) => one === "loaded").length, declared: states.length })
    }
    return judged
  }, Array.from(DEVICE_FAMILIES))
  const missing = outcome.filter((one) => one.loaded === 0)
  if (missing.length > 0) return { fail: missing.map((one) => `no face of ${one.family} loaded (${one.declared} declared)`).join("; ") }
  return { ok: outcome.length === 0 ? "the theme uses the device's own fonts only" : outcome.map((one) => `${one.family}: ${one.loaded} of ${one.declared} faces loaded`).join("; ") }
}

function expectedLine(text) {
  for (const entry of ROWS.expectedConsole) {
    if (entry.hosts.includes(options.host) && new RegExp(entry.pattern).test(text)) return true
  }
  return false
}

function judgeClean(record) {
  const said = []
  for (const text of record.console) if (!expectedLine(text)) said.push("console: " + text.slice(0, 200))
  for (const text of record.pageErrors) said.push("page error: " + text.slice(0, 200))
  for (const text of record.refused) if (!expectedLine(text) && !said.some((one) => one.includes(text.slice(0, 80)))) said.push("refused: " + text.slice(0, 200))
  for (const text of record.mixed) said.push("mixed content: " + text.slice(0, 200))
  if (said.length > 0) return { fail: `${said.length} thing(s) reported: ${said.slice(0, 4).join(" | ")}` }
  return { ok: "nothing reported to the console, no page error, nothing refused" }
}

function judgeOwnHost(record) {
  const allowed = new Set(ROWS.thirdPartyHostsToday.hosts)
  const asked = new Map()
  for (const one of record.offSite) {
    if (one.fromEmbed) continue
    if (!asked.has(one.host)) asked.set(one.host, one.path)
  }
  const strangers = []
  for (const [host, path] of asked) if (!allowed.has(host)) strangers.push(`${host}${path}`)
  if (strangers.length > 0) return { fail: `asked another host for ${strangers.slice(0, 4).join(", ")}` }
  return { ok: asked.size === 0 ? "nothing asked of any other host" : `asked only ${Array.from(asked.keys()).sort().join(", ")} (thirdPartyHostsToday, until #566)` }
}

// -------------------- the cold visit (#625) --------------------

async function coldSample(browser, base) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
  try {
    await context.route("**/*", (route) => (route.request().resourceType() === "media" ? route.abort() : route.continue()))
    const page = await context.newPage()
    await page.goto(pageUrl(base, "Python"), { waitUntil: "commit", timeout: 30000 })
    const painted = await waitInPage(page, () => {
      const paint = performance.getEntriesByType("paint").find((entry) => entry.name === "first-contentful-paint")
      return paint ? { fcp: Math.round(paint.startTime), responseStart: Math.round(performance.getEntriesByType("navigation")[0]?.responseStart ?? 0) } : null
    }, 15000)
    return painted ?? { fcp: null }
  } finally {
    await context.close()
  }
}

async function coldVisit(browser, base) {
  const samples = []
  let retries = 0
  const slow = (sample) => sample.fcp === null || sample.fcp > 3000
  for (let index = 0; index < 5; index += 1) {
    const sample = await coldSample(browser, base)
    samples.push(sample)
    // Two slow ones already fail the row: no need to wait for more.
    if (samples.filter(slow).length >= 2) break
  }
  let slowCount = samples.filter(slow).length
  if (slowCount === 1) {
    retries = 1
    const again = await coldSample(browser, base)
    if (!slow(again)) {
      const at = samples.findIndex(slow)
      samples[at] = { ...again, retried: true }
      slowCount = 0
    }
  }
  const values = samples.map((sample) => (sample.fcp === null ? Infinity : sample.fcp)).sort((a, b) => a - b)
  const median = values[Math.floor(values.length / 2)]
  const shown = samples.map((sample) => (sample.fcp === null ? "never" : `${sample.fcp} ms`)).join(", ")
  if (slowCount >= 2 || median > 3000) return { fail: `${slowCount} of ${samples.length} cold visits took over 3 s to first contentful paint (${shown}; median ${median === Infinity ? "never" : median + " ms"})` }
  return { ok: `first contentful paint ${shown} over ${samples.length} cold visits (median ${median} ms)${retries ? `; answered on retry: ${retries}` : ""}` }
}

// -------------------- running pages --------------------

function rowsWanted() {
  const all = ROWS.rows.filter((row) => !row.hosts || row.hosts.includes(options.host))
  if (!options.only) return all
  const unknown = options.only.filter((name) => !ROWS.rows.some((row) => row.name === name))
  if (unknown.length > 0) throw new Error(`no such row: ${unknown.join(", ")}`)
  return all.filter((row) => options.only.includes(row.name) || row.page === "*")
}

// Runs every row of `pageName` in one engine, then the rows every page
// carries; answers [{ row, state, detail }].
async function runPage(browser, engine, base, pageName, rows, network) {
  const outcomes = []
  const pageRows = rows.filter((row) => row.page === pageName && (!row.engines || row.engines.includes(engine)))
  const { context, record } = await openContext(browser, engine, new URL(base).origin)
  try {
    if (pageRows.some((row) => row.name === "print")) await context.addInitScript(PRINT_PROBE)
    if (pageRows.some((row) => row.name === "copy")) await context.addInitScript(CLIPBOARD_SPY)
    if (engine === "chromium" && pageRows.some((row) => row.name === "heading anchor")) await context.addInitScript(NO_ANCHORING)
    let page
    try {
      page = await openPage(context, record, pageUrl(base, pageName))
    } catch (error) {
      for (const row of pageRows) outcomes.push({ row: row.name, state: "FAIL", detail: `the ${pageName} page did not load: ${String(error.message ?? error).split("\n")[0]}` })
      return outcomes
    }
    for (const row of pageRows) {
      if (row.name === "cold visit") continue
      let outcome
      try {
        outcome = await Promise.race([
          ROW_CHECKS[row.name]({ page, context, record, base, engine, network }),
          pause(180000).then(() => ({ fail: "no answer within 3 minutes" })),
        ])
      } catch (error) {
        outcome = { fail: String(error.message ?? error).split("\n")[0] }
      }
      outcomes.push(toOutcome(row.name, outcome))
    }
    const common = rows.filter((row) => row.page === "*" && !(row.except ?? []).includes(pageName))
    for (const row of common) {
      let outcome
      if (row.name === "fonts") {
        try {
          outcome = await judgeFonts(page, network)
        } catch (error) {
          outcome = { fail: String(error.message ?? error).split("\n")[0] }
        }
      } else if (row.name === "clean page") outcome = judgeClean(record)
      else if (row.name === "own host") outcome = judgeOwnHost(record)
      outcomes.push(toOutcome(row.name, outcome))
    }
  } finally {
    await context.close().catch(() => {})
  }
  if (pageRows.some((row) => row.name === "cold visit")) {
    let outcome
    try {
      outcome = await coldVisit(browser, base)
    } catch (error) {
      outcome = { fail: String(error.message ?? error).split("\n")[0] }
    }
    outcomes.push(toOutcome("cold visit", outcome))
  }
  return outcomes
}

function toOutcome(row, outcome) {
  if (outcome?.skip) return { row, state: "SKIPPED", detail: outcome.skip }
  if (outcome?.fail) return { row, state: "FAIL", detail: outcome.fail }
  return { row, state: "OK", detail: outcome?.ok ?? "passed" }
}

function pagesFor(rows) {
  const pages = []
  for (const row of rows) if (row.page !== "*" && !pages.includes(row.page)) pages.push(row.page)
  return pages
}

async function runEngine(engineName, engine, base, pages, rows, network, report) {
  const browser = await engine.type.launch({ headless: true, ...engine.launch })
  try {
    for (const pageName of pages) {
      const outcomes = await runPage(browser, engineName, base, pageName, rows, network)
      for (const outcome of outcomes) report(engineName, pageName, outcome)
    }
  } finally {
    await browser.close().catch(() => {})
  }
}

// -------------------- main --------------------

async function plainRun(engines, network) {
  const rows = rowsWanted()
  const pages = pagesFor(rows)
  let server = null
  let base = options.base
  if (options.site) {
    server = await startSiteServer(options.site)
    base = server.origin + "/"
  }
  const started = Date.now()
  const collected = []
  try {
    await Promise.all(Object.entries(engines).filter(([, engine]) => engine !== null).map(([name, engine]) =>
      runEngine(name, engine, base, pages, rows, network, (engineName, pageName, outcome) => collected.push({ engine: engineName, page: pageName, ...outcome }))))
  } finally {
    await server?.close()
  }
  // One line per row and engine: the page rows as they are, the rows every
  // page carries summed over the pages (and the first page that failed).
  for (const engineName of options.engines) {
    for (const row of rows) {
      const mine = collected.filter((one) => one.engine === engineName && one.row === row.name)
      if (mine.length === 0) continue
      const failed = mine.filter((one) => one.state === "FAIL")
      const skipped = mine.filter((one) => one.state === "SKIPPED")
      if (row.page !== "*") {
        say(mine[0].state, row.name, engineName, mine[0].detail, mine[0].page)
      } else if (failed.length > 0) {
        say("FAIL", row.name, engineName, failed.map((one) => `${one.page}: ${one.detail}`).join(" || "))
      } else if (skipped.length === mine.length) {
        say("SKIPPED", row.name, engineName, skipped[0].detail)
      } else {
        say("OK", row.name, engineName, `${mine.length - skipped.length} pages - ${mine.filter((one) => one.state === "OK").map((one) => one.page).join(", ")}; e.g. ${mine.find((one) => one.state === "OK").detail}`)
      }
    }
  }
  return { seconds: Math.round((Date.now() - started) / 1000) }
}

function copySite(from) {
  const to = mkdtempSync(join(tmpdir(), "plantoir-rendered-red-"))
  try {
    execFileSync("cp", ["-Rc", from + "/.", to + "/"], { stdio: "ignore" })
  } catch {
    execFileSync("cp", ["-R", from + "/.", to + "/"], { stdio: "ignore" })
  }
  return to
}

async function redRun(engines, network) {
  const named = options.expectRed === "all" ? ROWS.sabotages.filter((one) => one.gate !== false) : ROWS.sabotages.filter((one) => one.name === options.expectRed)
  if (named.length === 0) throw new Error(`no sabotage called ${options.expectRed}`)
  if (options.expectRed === "all") {
    for (const one of ROWS.sabotages) if (one.gate === false) say("NOTE", `sabotage ${one.name}`, null, one.whyNotEveryGate)
  }
  const started = Date.now()
  const live = Object.entries(engines).filter(([, engine]) => engine !== null)
  const browsers = {}
  for (const [name, engine] of live) browsers[name] = await engine.type.launch({ headless: true, ...engine.launch })
  try {
    // Three sabotages at a time, each with its own copy, server and
    // contexts (plan review M2: one after another took 344 s on this Mac).
    const queue = named.slice()
    const runOne = async (sabotage) => {
      const began = Date.now()
      const aimed = ROWS.rows.find((row) => row.name === sabotage.aims)
      const rows = ROWS.rows.filter((row) => (row.page === sabotage.page || (row.page === "*" && !(row.except ?? []).includes(sabotage.page))) && (!row.hosts || row.hosts.includes(options.host)))
      const copy = copySite(options.site)
      let server = null
      try {
        const applied = execFileSync("python3", [join(HERE, "lib", "sabotage.py"), "apply", copy, sabotage.name], { encoding: "utf-8" }).trim()
        server = await startSiteServer(copy)
        const base = server.origin + "/"
        await Promise.all(live.map(async ([name]) => {
          if (aimed.engines && !aimed.engines.includes(name)) return
          if (sabotage.engines && !sabotage.engines.includes(name)) {
            say("NOTE", `sabotage ${sabotage.name}`, name, `not run in ${name}: ${sabotage.whyEngines}`)
            return
          }
          if ((aimed.needsNetwork === "cdnjs" && network.cdnjs) || (aimed.needsNetwork === "google" && network.google)) {
            say("SKIPPED", `sabotage ${sabotage.name}`, name, `no network - ${network.cdnjs ?? network.google}`)
            return
          }
          const outcomes = await runPage(browsers[name], name, base, sabotage.page, rows, network)
          const target = outcomes.find((one) => one.row === sabotage.aims)
          const problems = []
          if (!target) problems.push(`${sabotage.aims} did not run`)
          else if (target.state !== "FAIL") problems.push(`${sabotage.aims} ${target.state === "OK" ? "PASSED" : "was " + target.state} on its sabotage (${target.detail})`)
          else if (!target.detail.includes(sabotage.reason)) problems.push(`${sabotage.aims} failed, but not for its own reason (wanted "${sabotage.reason}", it said: ${target.detail})`)
          const others = []
          for (const one of outcomes) {
            if (one.row === sabotage.aims) continue
            if (one.state === "FAIL" && !sabotage.alsoRed.includes(one.row)) problems.push(`${one.row} went red too, which this sabotage may not do (${one.detail})`)
            if (one.state === "OK") others.push(one.row)
          }
          const took = Math.round((Date.now() - began) / 1000)
          if (problems.length > 0) say("FAIL", `sabotage ${sabotage.name}`, name, `${applied} - ` + problems.join("; "))
          else say("OK", `sabotage ${sabotage.name}`, name, `${sabotage.aims} failed for its own reason: ${target.detail}${others.length ? `; ${others.join(", ")} still passed` : ""} (${took} s)`)
        }))
      } catch (error) {
        say("FAIL", `sabotage ${sabotage.name}`, null, `could not be run: ${String(error.message ?? error).split("\n")[0]}`)
      } finally {
        await server?.close()
        rmSync(copy, { recursive: true, force: true })
      }
    }
    const workers = []
    for (let worker = 0; worker < 3; worker += 1) {
      workers.push((async () => {
        while (queue.length > 0) await runOne(queue.shift())
      })())
    }
    await Promise.all(workers)
  } finally {
    for (const browser of Object.values(browsers)) await browser.close().catch(() => {})
  }
  return { seconds: Math.round((Date.now() - started) / 1000) }
}

const { engines, missing } = loadEngines()
let engineMissing = false
for (const engine of options.engines) {
  if (engines[engine] !== null) continue
  if (REQUIRED.has(engine)) say("FAIL", "engine", engine, `required by PLANTOIR_REQUIRE_ENGINES and not here: ${missing[engine]}`)
  else {
    say("SKIPPED", "engine", engine, missing[engine])
    engineMissing = true
  }
}
let timing = { seconds: 0 }
if (Object.values(engines).some((engine) => engine !== null)) {
  const network = await networkState()
  try {
    timing = options.expectRed ? await redRun(engines, network) : await plainRun(engines, network)
  } catch (error) {
    say("FAIL", "the check", null, String(error.message ?? error).split("\n")[0])
  }
}
const failed = results.some((one) => one.state === "FAIL")
const skipped = engineMissing || results.some((one) => one.state === "SKIPPED")
console.log(`DONE: ${results.filter((one) => one.state === "OK").length} OK, ${results.filter((one) => one.state === "FAIL").length} FAIL, ${results.filter((one) => one.state === "SKIPPED").length} SKIPPED in ${timing.seconds} s (${options.expectRed ? "sabotage " + options.expectRed : options.host}; engines ${options.engines.join(", ")})`)
if (options.json) writeFileSync(options.json, JSON.stringify({ host: options.host, expectRed: options.expectRed, seconds: timing.seconds, results }, null, 2))
process.exit(failed ? 1 : skipped ? 3 : 0)
