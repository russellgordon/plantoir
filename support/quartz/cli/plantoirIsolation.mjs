// Live input (#583): the preview's half of which pages are cross-origin
// isolated. Quartz's preview server (cli/handlers.js, patched by
// build_site.py with the marker PLANTOIR-ISOLATION-SERVE) asks headersFor()
// before it serves each file, so a teacher previews what students get on
// Netlify and Cloudflare (scripts/isolation_headers.py writes their
// _headers): COOP and COEP on a page whose runnable code can ask for input
// and that shows nothing from another website the headers would break, and
// COEP on the engine's own folders.
//
// The rule is contracts/shared-rules.json -> codeRunnerBlocks.isolation, and
// it is written twice - here and in isolation_headers.py - because the
// preview decides per request, inside Node, while the publish decides in
// Python. Both run the contract's `cases`
// (scripts/check_runner_rules_against_the_site.py and
// scripts/test_isolation_headers.py), so they cannot drift; the constants
// below are compared with the contract's there too.
//
// It FAILS OPEN (review N7): any error reading or testing a file means the
// file is served as it would have been, never a 500. Plain JavaScript with no
// packages: it runs in Quartz's CLI, not in the site.

import fs from "fs"
import path from "path"

export const PAGE_HEADERS = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
}
export const ENGINE_HEADERS = { "Cross-Origin-Embedder-Policy": "require-corp" }
export const ENGINE_FOLDERS = ["static/pyodide", "static/swift"]
export const ALLOWED_HOSTS = ["cdnjs.cloudflare.com", "fonts.googleapis.com", "fonts.gstatic.com"]
const REASONS = ["frame", "picture", "other"]
const REASON_WORDS = { frame: "notLiveFrame", picture: "notLivePicture", other: "notLiveOther" }
const LINK_RELS_THAT_FETCH = new Set(["stylesheet", "preload", "modulepreload"])

// A start tag whose attribute values may hold anything in quotes - a block's
// code in data-original may say <iframe>, and that is not a frame.
const START_TAG =
  /<([a-zA-Z][a-zA-Z0-9:-]*)((?:\s+[^\s"'>\/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*\/?>/g
const ATTRIBUTE = /([^\s"'>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g
const RAW_TEXT = /<(script|style)\b((?:[^>"']|"[^"]*"|'[^']*')*)>([\s\S]*?)<\/\1\s*>/gi
const COMMENT = /<!--[\s\S]*?-->/g
const CSS_URL = /url\(\s*(['"]?)(.*?)\1\s*\)/gis

function decoded(value) {
  return value
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#([0-9]+);/g, (_, number) => String.fromCodePoint(parseInt(number, 10)))
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&")
}

function hostOf(url) {
  let value = String(url).trim()
  const lowered = value.toLowerCase()
  if (lowered.startsWith("//")) {
    value = "https:" + value
  } else if (!lowered.startsWith("http://") && !lowered.startsWith("https://")) {
    return null
  }
  try {
    return new URL(value).hostname.toLowerCase()
  } catch {
    return ""
  }
}

function makeReader(allowedHosts) {
  const allowed = new Set(allowedHosts.map((host) => host.toLowerCase()))
  const cross = (url) => {
    if (url === undefined || url === null) return false
    const host = hostOf(url)
    return host !== null && !allowed.has(host)
  }
  const srcsetCross = (srcset) => {
    if (!srcset) return false
    for (const candidate of srcset.split(",")) {
      const words = candidate.trim().split(/\s+/)
      if (words[0] && cross(words[0])) return true
    }
    return false
  }
  const cssCross = (css) => {
    for (const match of String(css ?? "").matchAll(CSS_URL)) {
      if (cross(match[2])) return true
    }
    return false
  }
  return { cross, srcsetCross, cssCross }
}

// One built page's verdict, as isolation_headers.page_verdict answers it:
// {verdict: "none" | "live" | "frame" | "picture" | "other", readsInput}.
export function pageVerdict(html, allowedHosts = ALLOWED_HOSTS) {
  const { cross, srcsetCross, cssCross } = makeReader(allowedHosts)
  const asks = new Set()
  const reasons = new Set()
  // Comments go; a script's or a style's text is set aside (a style's is
  // read for url(...)), keeping its start tag for its src.
  let text = String(html).replace(COMMENT, "")
  text = text.replace(RAW_TEXT, (_, name, attributes, body) => {
    if (name.toLowerCase() === "style" && cssCross(body)) reasons.add("other")
    return `<${name}${attributes}>`
  })
  for (const tag of text.matchAll(START_TAG)) {
    const name = tag[1].toLowerCase()
    const values = {}
    for (const attribute of (tag[2] ?? "").matchAll(ATTRIBUTE)) {
      const key = attribute[1].toLowerCase()
      if (key in values) continue
      values[key] = decoded(attribute[2] ?? attribute[3] ?? attribute[4] ?? "")
    }
    if (name === "div" && String(values["class"] ?? "").split(/\s+/).includes("plantoir-runner")) {
      if (values["data-runner-asks"] === "input" || values["data-runner-asks"] === "edit") {
        asks.add(values["data-runner-asks"])
      }
    }
    if (name === "iframe" || name === "frame" || name === "embed" || name === "object") {
      reasons.add("frame")
    } else if (name === "img") {
      if (cross(values.src) || srcsetCross(values.srcset)) reasons.add("picture")
    } else if (name === "source") {
      if (srcsetCross(values.srcset)) reasons.add("picture")
      else if (cross(values.src)) reasons.add("frame")
    } else if (name === "video") {
      if (cross(values.src)) reasons.add("frame")
      if (cross(values.poster)) reasons.add("picture")
    } else if (name === "audio" || name === "track" || name === "script") {
      if (cross(values.src)) reasons.add("other")
    } else if (name === "input") {
      if (String(values.type ?? "").toLowerCase() === "image" && cross(values.src)) reasons.add("picture")
    } else if (name === "image") {
      if (cross(values.href) || cross(values["xlink:href"])) reasons.add("picture")
    } else if (name === "link") {
      const rels = String(values.rel ?? "").toLowerCase().split(/\s+/)
      if (rels.some((rel) => LINK_RELS_THAT_FETCH.has(rel)) && cross(values.href)) reasons.add("other")
    }
    if ("style" in values && cssCross(values.style)) reasons.add("other")
  }
  const readsInput = asks.has("input")
  if (asks.size === 0) return { verdict: "none", readsInput: false }
  for (const reason of REASONS) {
    if (reasons.has(reason)) return { verdict: reason, readsInput }
  }
  return { verdict: "live", readsInput }
}

// The file the preview would serve for an address, as Quartz's server finds
// it: /a/ -> a/index.html, /a -> a.html, /a.html as it is.
function pageFile(publicDir, address) {
  let decodedPath = decodeURIComponent(address.split("?")[0].split("#")[0])
  if (decodedPath.endsWith("/")) decodedPath += "index.html"
  else if (path.posix.extname(decodedPath) === "") decodedPath += ".html"
  if (!decodedPath.endsWith(".html")) return null
  const root = path.resolve(publicDir)
  const file = path.resolve(root, "." + decodedPath)
  if (file !== root && !file.startsWith(root + path.sep)) return null
  return file
}

const verdicts = new Map()
const said = new Set()

function cachedVerdict(file) {
  const stamp = fs.statSync(file).mtimeMs
  const known = verdicts.get(file)
  if (known && known.stamp === stamp) return known.verdict
  const verdict = pageVerdict(fs.readFileSync(file, "utf-8"))
  verdicts.set(file, { stamp, verdict })
  return verdict
}

// The page's file in the course, for the note line (Quartz's contentIndex).
function sourceName(publicDir, file) {
  const slug = path.relative(path.resolve(publicDir), file).split(path.sep).join("/").replace(/\.html$/, "")
  try {
    const index = JSON.parse(fs.readFileSync(path.join(publicDir, "static", "contentIndex.json"), "utf-8"))
    const entry = index[slug]
    if (entry && typeof entry.filePath === "string") return entry.filePath
  } catch {
    // The name the site gives the page will do.
  }
  return slug + ".md"
}

// A page that keeps the box although its code reads input says why, once
// per page while this preview runs (isolation.hosts.preview).
function sayWhy(publicDir, file, verdict) {
  if (said.has(file) || !verdict.readsInput || verdict.verdict === "live") return
  said.add(file)
  try {
    const settings = JSON.parse(fs.readFileSync(path.join("quartz", "plantoir_code_runner.json"), "utf-8"))
    const words = settings.words ?? {}
    if (!words.notLiveBecause || !words[REASON_WORDS[verdict.verdict]]) return
    const reason = words.notLiveBecause.split("{what}").join(words[REASON_WORDS[verdict.verdict]])
    console.log(`plantoir: note: ${sourceName(publicDir, file)}: ${reason}`)
  } catch {
    // Saying why is a courtesy; the page is served either way.
  }
}

// The headers to add to one response of the preview: {} for anything else,
// and {} whenever anything goes wrong (fail open).
export function headersFor(publicDir, address) {
  try {
    const decodedPath = decodeURIComponent(String(address).split("?")[0])
    for (const folder of ENGINE_FOLDERS) {
      if (decodedPath.startsWith("/" + folder + "/")) return { ...ENGINE_HEADERS }
    }
    const file = pageFile(publicDir, String(address))
    if (file === null || !fs.existsSync(file)) return {}
    const verdict = cachedVerdict(file)
    sayWhy(publicDir, file, verdict)
    return verdict.verdict === "live" ? { ...PAGE_HEADERS } : {}
  } catch {
    return {}
  }
}
