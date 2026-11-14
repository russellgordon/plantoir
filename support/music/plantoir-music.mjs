// Tunes drawn from a page's own ```abc fences at BUILD time (#679).
//
// scripts/music.py starts this once per build with the runtime's own node,
// sends it one tune at a time as a JSON line on stdin, and reads one JSON
// line back for each, as support/figures/plantoir-figures.mjs is used for
// TikZ. Nothing here reads a page or writes a file: Python prepares and
// Quartz places.
//
//   node plantoir-music.mjs --engine <folder holding node_modules/abcjs and
//                                     node_modules/linkedom>
//
// First line out: {"ready": true, "abcjs": "<version>"}.
// Each line in:   {"id": "...", "abc": "<the tune as the site will read it>",
//                  "options"?: {...}}  (the options to draw it with; the
//                  --options given at the start when there are none)
// Each line out:  {"id", "ok": true, "html": "<div class=abcjs-container ...>
//                  <svg ...></svg></div>", "notes": n, "staffLines": n,
//                  "width": the drawing's own width (its viewBox's),
//                  "programs": [General MIDI programs, 0-based],
//                  "warnings": [{"line", "column", "said"}]}
//              or {"id", "ok": false, "reason": "nothingToDraw" | "drawingStopped",
//                  "said": "..."}
//
// Two rules that make the build's picture the student's picture
// (contracts/shared-rules.json -> musicFences.drawing):
//
// * The options are musicFences.drawing.options, or drawing.wrap.options
//   for a tune whose lines are too long for the page (scripts/music.py
//   decides, from the width answered here, and sends the tune again), and
//   the build hands the SAME object to the site's loader, which passes it
//   when a student presses Play and the tune is drawn again in place (so
//   the notes it lights are the ones on the page).
// * getBBox answers no size here (linkedom has none) and in the student's
//   browser while the loader draws (music.inline.ts sets it for the length of
//   the call), so abcjs ESTIMATES every text width the same way in both.
//   Measured 2026-11-14: four tunes (a scale with words, eight bars with
//   chord symbols, first and second endings, two voices) drawn here and in
//   headless Chromium 155 and WebKit 2359 are identical once attribute order
//   and the spelling of inline styles are set aside.
//
// Which sounds a tune needs is abcjs's own answer (setUpAudio), never a
// reading of the teacher's setting line: chord symbols play on their own
// program, so a flute tune with chords may need piano too (plan review M2).

import path from "path"
import { createRequire } from "module"
import { pathToFileURL } from "url"
import { createInterface } from "readline"

function argument(name) {
  const at = process.argv.indexOf(name)
  return at >= 0 && at + 1 < process.argv.length ? process.argv[at + 1] : null
}

const engine = argument("--engine")
const optionsText = argument("--options")
if (engine === null || optionsText === null) {
  process.stderr.write("Error: plantoir-music.mjs needs --engine and --options\n")
  process.exit(2)
}
const options = JSON.parse(optionsText)

const { parseHTML } = await import(
  pathToFileURL(path.join(engine, "node_modules", "linkedom", "esm", "index.js")).href
)
const page = parseHTML("<!doctype html><html><head></head><body></body></html>")
globalThis.window = page
globalThis.document = page.document
// No size, so abcjs estimates (its getTextSize falls back to guessWidth on a
// missing height). The site's loader does the same while it draws.
page.Element.prototype.getBBox = function () {
  return { x: 0, y: 0, width: NaN, height: NaN }
}
const require = createRequire(import.meta.url)
const ABCJS = require(path.join(engine, "node_modules", "abcjs"))
const abcjsVersion = require(path.join(engine, "node_modules", "abcjs", "package.json")).version

function plainWords(html) {
  return String(html)
    .replace(/<[^>]*>/g, "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim()
}

// "Music Line:3:10: Expected ']' to end the chords:  G A [B c | d" ->
// {line: 3, column: 10, said: "Expected ']' to end the chords"}. The part
// after a colon and two spaces is abcjs quoting the line back, which the
// teacher has in front of them; it is left out.
function warningOf(text) {
  const words = plainWords(text)
  const match = words.match(/^Music Line:(\d+):(\d+):\s*(.*)$/)
  if (match === null) {
    return { line: null, column: null, said: words.split(":  ")[0].slice(0, 160) }
  }
  const said = String(match[3]).split(/:\s{2,}|: (?=\S.*\|)/)[0].trim()
  return { line: Number(match[1]), column: Number(match[2]), said: said.slice(0, 160) }
}

function programsOf(tune) {
  const found = new Set()
  const audio = tune.setUpAudio({})
  for (const track of audio.tracks ?? []) {
    for (const event of track) {
      if (event !== null && typeof event === "object" && Number.isInteger(event.instrument)) {
        found.add(event.instrument)
      }
    }
  }
  return Array.from(found).sort((one, other) => one - other)
}

// The drawing's own width, its viewBox's: abcjs fits a line of music to its
// staff by closing the notes up, and draws a line it cannot fit wider than
// that, which a page then shrinks (musicFences.drawing.wrap). Every svg of
// the tune counts; the widest is the one a reader meets.
function widthOf(holder) {
  let widest = 0
  for (const svg of holder.querySelectorAll("svg")) {
    const box = String(svg.getAttribute("viewBox") ?? "").trim().split(/\s+/)
    const width = box.length === 4 ? Number(box[2]) : NaN
    if (Number.isFinite(width) && width > widest) {
      widest = width
    }
  }
  return Math.round(widest)
}

function draw(job) {
  const holder = document.createElement("div")
  document.body.replaceChildren(holder)
  let tunes
  try {
    const drawWith = job.options !== null && typeof job.options === "object" ? job.options : options
    tunes = ABCJS.renderAbc(holder, String(job.abc ?? ""), drawWith)
  } catch (error) {
    return { id: job.id, ok: false, reason: "drawingStopped", said: plainWords(error?.message ?? error) }
  }
  const tune = tunes?.[0]
  const warnings = []
  for (const warning of tune?.warnings ?? []) {
    warnings.push(warningOf(warning))
  }
  const staffLines = tune?.lines?.length ?? 0
  const notes = holder.querySelectorAll(".abcjs-note").length
  if (tune === undefined || staffLines === 0 || holder.querySelector("svg") === null) {
    return { id: job.id, ok: false, reason: "nothingToDraw", said: "", warnings }
  }
  let programs = []
  try {
    programs = programsOf(tune)
  } catch (error) {
    return { id: job.id, ok: false, reason: "drawingStopped", said: plainWords(error?.message ?? error) }
  }
  return { id: job.id, ok: true, html: holder.outerHTML, notes, staffLines, width: widthOf(holder), programs, warnings }
}

process.stdout.write(JSON.stringify({ ready: true, abcjs: abcjsVersion }) + "\n")
const lines = createInterface({ input: process.stdin })
for await (const line of lines) {
  if (line.trim() === "") {
    continue
  }
  let job
  try {
    job = JSON.parse(line)
  } catch {
    continue
  }
  process.stdout.write(JSON.stringify(draw(job)) + "\n")
}
