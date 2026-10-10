// Prints a long page that is NOT printable under ⌘P (#501) in headless Chrome
// for Testing, and reads the PAPER back - its ink, not only its text.
//
// Quartz has no print rules of its own, so ⌘P used to lay the screen's page
// out at the paper's width: under 800 px in Chrome, the phone layout, whose
// folder list (open on a page loaded at desktop width) is an opaque panel
// drawn OVER the article. The covered words stayed in the PDF's TEXT layer,
// so reading the text back found every one of them; what showed the loss
// was the ink under them, and the folder list read into the paragraphs.
// Since #501 one print block in the shared stylesheet takes the sidebars
// away and caps the column (contracts/shared-rules.json →
// printablePages.everyOtherPage). The page is loaded in a 1512 px window, as
// a teacher's laptop loads it, then printed on letter paper, portrait and
// landscape, and checked with poppler's pdftotext, pdfinfo and pdftoppm:
//
// 1. no sidebar's words on paper - the lines of every element the contract's
//    `hidden` names, read from the page on screen, that the rest of the page
//    does not also carry;
// 2. every paragraph, heading and list item of the article whole in the
//    PDF's text, in order of words (a folder list read into a paragraph
//    breaks it);
// 3. INK under every paragraph's sentinel (plantoir-plain-para-NN): the
//    darkest pixel in the word's box, on the page rendered in grey at 100
//    dpi, at most 200 of 255;
// 4. no word past the paper's edge (18 pt from it).
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket
// speaks to Chrome, and pdftoppm's PGM is read by hand.
//
//   node browser-checks/print_plain_page.mjs <chrome binary> <page url>
//
// PLANTOIR_PRINT_CHECK_KEEP=<folder> keeps the PDFs there.

import { execFileSync, spawn } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, readFileSync, readdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const [chromePath, pageUrl] = process.argv.slice(2)
if (!chromePath || !pageUrl) {
  console.error("usage: node print_plain_page.mjs <chrome> <url>")
  process.exit(2)
}

const RULE = JSON.parse(readFileSync(new URL("../contracts/shared-rules.json", import.meta.url), "utf-8"))
  .printablePages.everyOtherPage
const SENTINEL = /plantoir-plain-para-(\d\d)/
const SENTINELS = 40
const DPI = 100
const INKED = 200
const EDGE = 18

const work = mkdtempSync(join(tmpdir(), "plantoir-plain-print-check-"))
const profile = join(work, "profile")
const keep = process.env.PLANTOIR_PRINT_CHECK_KEEP || ""
if (keep) mkdirSync(keep, { recursive: true })
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check",
  // A teacher's laptop window: the page is LOADED at desktop width, which is
  // what leaves the folder list open when it is then printed.
  "--window-size=1512,900",
  "--use-mock-keychain", "--password-store=basic",
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows", "--hide-scrollbars", "--mute-audio",
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })

function finish(code, message) {
  console.log(message)
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}

const timer = setTimeout(() => finish(1, "FAIL: the plain page was not printed within 180 s"), 180000)

const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
const poppler = (tool, args) => execFileSync(tool, args, { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] })
// Words a line break split at a hyphen are joined again, and runs of space
// are one space.
const plainText = (text) => text.replace(/-\s*\n\s*/g, "-").replace(/\s+/g, " ").trim()
const unescape = (text) => text.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&amp;/g, "&")

// pdftoppm -gray writes binary PGM: "P5", width, height, maximum, then one
// byte a pixel.
function readPgm(file) {
  const bytes = readFileSync(file)
  const fields = []
  let at = 0
  while (fields.length < 4) {
    while (/\s/.test(String.fromCharCode(bytes[at]))) at += 1
    let field = ""
    while (!/\s/.test(String.fromCharCode(bytes[at]))) {
      field += String.fromCharCode(bytes[at])
      at += 1
    }
    fields.push(field)
  }
  at += 1
  return { width: Number(fields[1]), height: Number(fields[2]), pixels: bytes.subarray(at) }
}

function darkestIn(image, box) {
  const scale = DPI / 72
  const left = Math.max(0, Math.floor(box.xMin * scale))
  const top = Math.max(0, Math.floor(box.yMin * scale))
  const right = Math.min(image.width, Math.max(left + 1, Math.ceil(box.xMax * scale)))
  const bottom = Math.min(image.height, Math.max(top + 1, Math.ceil(box.yMax * scale)))
  let darkest = 255
  for (let y = top; y < bottom; y += 1) {
    for (let x = left; x < right; x += 1) {
      const value = image.pixels[y * image.width + x]
      if (value < darkest) darkest = value
    }
  }
  return darkest
}

// What one PDF says, against what the page showed on screen.
function readPdf(file, paper, onScreen) {
  const problems = []
  const info = poppler("pdfinfo", [file])
  const pages = Number((/Pages:\s+(\d+)/.exec(info) || [])[1])
  const size = (/Page size:\s+([\d.]+) x ([\d.]+)/.exec(info) || []).slice(1).map(Number)
  const wanted = paper === "landscape" ? [792, 612] : [612, 792]
  if (Math.round(size[0]) !== wanted[0] || Math.round(size[1]) !== wanted[1]) problems.push(`${paper}: paper ${size.join("x")}, not ${wanted.join("x")}`)
  const words = plainText(poppler("pdftotext", [file, "-"]))

  // 1. No sidebar's words on paper.
  const sidebarOnPaper = []
  for (const line of onScreen.sidebarLines) if (words.includes(line)) sidebarOnPaper.push(line)
  if (sidebarOnPaper.length > 0) problems.push(`${paper}: the sidebar printed ${sidebarOnPaper.slice(0, 6).map((line) => JSON.stringify(line)).join(", ")}`)

  // 2. Every paragraph whole in the text.
  const broken = []
  for (const paragraph of onScreen.paragraphs) if (!words.includes(paragraph)) broken.push(paragraph.slice(0, 48))
  if (broken.length > 0) problems.push(`${paper}: ${broken.length} of ${onScreen.paragraphs.length} paragraphs not whole in the printed text: ${broken.slice(0, 4).map((text) => JSON.stringify(text)).join(", ")}`)

  // 3. Ink under every sentinel, and 4. no word past the paper's edge.
  const boxes = poppler("pdftotext", ["-bbox", file, "-"])
  const shots = join(work, `shot-${paper}`)
  mkdirSync(shots)
  execFileSync("pdftoppm", ["-r", String(DPI), "-gray", file, join(shots, "p")])
  const images = readdirSync(shots).sort()
  const inked = new Set()
  const noInk = []
  const pastTheEdge = []
  boxes.split("<page ").slice(1).forEach((sheet, index) => {
    const width = Number((/^width="([\d.]+)"/.exec(sheet) || [])[1])
    const image = readPgm(join(shots, images[index]))
    for (const match of sheet.matchAll(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)<\/word>/g)) {
      const box = { xMin: Number(match[1]), yMin: Number(match[2]), xMax: Number(match[3]), yMax: Number(match[4]) }
      const word = unescape(match[5])
      if (box.xMax > width - EDGE) pastTheEdge.push(`p${index + 1}:${word}`)
      const sentinel = SENTINEL.exec(word)
      if (!sentinel) continue
      if (darkestIn(image, box) <= INKED) inked.add(sentinel[1])
      else noInk.push(`p${index + 1}:${sentinel[1]}`)
    }
  })
  if (noInk.length > 0) problems.push(`${paper}: ${noInk.length} paragraphs with no ink under their first word: ${noInk.slice(0, 12).join(" ")}`)
  const missing = []
  for (let number = 0; number < SENTINELS; number += 1) {
    const name = String(number).padStart(2, "0")
    if (!inked.has(name) && !noInk.some((entry) => entry.endsWith(":" + name))) missing.push(name)
  }
  if (missing.length > 0) problems.push(`${paper}: sentinels not on paper at all: ${missing.join(" ")}`)
  if (pastTheEdge.length > 0) problems.push(`${paper}: ${pastTheEdge.length} words past the paper's edge: ${pastTheEdge.slice(0, 6).join(" ")}`)
  return { pages, inked: inked.size, noInk: noInk.length, pastTheEdge: pastTheEdge.length, sidebarOnPaper: sidebarOnPaper.length, broken: broken.length, problems }
}

// Read from the page on SCREEN: the article's paragraphs, and the lines of
// every sidebar the contract hides that the rest of the page does not carry.
const ON_SCREEN = `
(() => {
  const hidden = ${JSON.stringify(RULE.hidden)}
  const tidy = (text) => text.replace(/\\s+/g, " ").trim()
  const article = document.querySelector(".center article")
  if (!article) return null
  const paragraphs = []
  for (const element of article.querySelectorAll("p, li, h2, h3")) {
    if (element.closest("pre, table, .katex-display")) continue
    const text = tidy(element.innerText || "")
    if (text.length > 0) paragraphs.push(text)
  }
  const elsewhere = document.body.cloneNode(true)
  for (const selector of hidden) for (const element of elsewhere.querySelectorAll(selector)) element.remove()
  const rest = tidy(elsewhere.textContent || "")
  const sidebarLines = []
  for (const selector of hidden) {
    for (const element of document.querySelectorAll(selector)) {
      for (const line of (element.innerText || "").split("\\n")) {
        const text = tidy(line)
        if (text.length >= 4 && !rest.includes(text) && !sidebarLines.includes(text)) sidebarLines.push(text)
      }
    }
  }
  return { paragraphs, sidebarLines }
})()
`

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
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? message.error)
      waiting.delete(message.id)
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    return answer?.result?.value
  }
  socket.onopen = async () => {
    await send("Page.enable")
    await send("Emulation.setEmulatedMedia", { media: "", features: [{ name: "prefers-color-scheme", value: "light" }] })
    await send("Page.navigate", { url: pageUrl })
    let onScreen = null
    for (let tries = 0; tries < 60 && onScreen === null; tries += 1) {
      await pause(250)
      if ((await evaluate("document.readyState")) !== "complete") continue
      onScreen = (await evaluate(ON_SCREEN)) ?? null
    }
    // One more beat, for the page's own scripts to have run on load.
    await pause(1000)
    if (onScreen === null) return finish(1, "FAIL: the page did not load " + pageUrl)
    onScreen = (await evaluate(ON_SCREEN)) ?? onScreen
    const problems = []
    if (onScreen.paragraphs.length < SENTINELS) problems.push(`only ${onScreen.paragraphs.length} paragraphs on screen; the fixture has ${SENTINELS}`)
    if (onScreen.sidebarLines.length === 0) problems.push("no sidebar words on screen to look for: the check would prove nothing")
    const report = { paragraphs: onScreen.paragraphs.length, sidebarLines: onScreen.sidebarLines.length }
    for (const landscape of [false, true]) {
      const paper = landscape ? "landscape" : "portrait"
      // ⌘P's own defaults: no backgrounds, the browser's margins.
      const pdf = await send("Page.printToPDF", { landscape, preferCSSPageSize: true, printBackground: false })
      const file = join(work, `plain-${paper}.pdf`)
      writeFileSync(file, Buffer.from(pdf.data, "base64"))
      if (keep) writeFileSync(join(keep, `plain-${paper}.pdf`), Buffer.from(pdf.data, "base64"))
      const read = readPdf(file, paper, onScreen)
      problems.push(...read.problems)
      delete read.problems
      report[paper] = read
    }
    clearTimeout(timer)
    const good = problems.length === 0
    finish(good ? 0 : 1, (good ? "OK: " : "FAIL: " + problems.join("\n  ") + "\n") + JSON.stringify(report))
  }
}
