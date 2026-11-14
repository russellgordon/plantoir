// A refusal the site's own policy makes ON PURPOSE, told apart from one it
// makes by mistake, for the clean-page row of the rendered check
// (browser-checks/rendered_features.mjs, #597's second half).
//
// The one case today is Netlify's badge. Netlify adds an inline script to a
// page on its way to a browser, and the Content-Security-Policy that
// scripts/netlify_badge.py writes leaves 'unsafe-inline' out so that this
// script is refused (documentation/07, "Suppressing Netlify's own ad
// badge"). The first deployed run (2026-11-13) saw exactly one such refusal
// on each of the 11 pages, in both engines, and counted each as a failure of
// the site.
//
// What identifies it is not its wording alone. A site whose policy lost the
// hash of one of its OWN inline scripts (the drift netlify_badge.py exists to
// prevent) is refused with the same words, and that must stay red. So a
// refused inline script is set aside only when it is in the page as the
// browser received it and NOT in the page as the host serves it to a client
// that is not a browser (the injection is made for browsers; measured with
// curl on the first run's Netlify pages, which carried only scripts the
// policy allowed). A refused script that is in the site's own page, or that
// is in neither (made at run time by the page's scripts), is the site's,
// and fails. And only the console lines in the wording rendered_rows.json ->
// refusedByDesign names are set aside, only on a page where such a script
// was found, never a refusal of any other kind.
//
// No packages; Node 22. Tested by test_refused_by_design.mjs.

import { createHash } from "node:crypto"

// The types a browser runs as script (HTML's list of JavaScript MIME types,
// and "module"); a script of any other type (JSON data, a template) is not
// run, so no policy refuses it.
const RUN_AS_SCRIPT = new Set(["", "module", "text/javascript", "application/javascript", "application/ecmascript",
  "application/x-ecmascript", "application/x-javascript", "text/ecmascript", "text/javascript1.0", "text/javascript1.1",
  "text/javascript1.2", "text/javascript1.3", "text/javascript1.4", "text/javascript1.5", "text/jscript", "text/livescript",
  "text/x-ecmascript", "text/x-javascript"])

export function runsAsScript(type) {
  return RUN_AS_SCRIPT.has(String(type ?? "").trim().toLowerCase())
}

// The inline scripts a page's HTML holds, as the parser hands them to the
// policy: the text between the tags, for every <script> with no src whose
// type is run. The same reading as scripts/netlify_badge.py's
// _INLINE_SCRIPT_RE, which is how the policy's hashes were made.
export function inlineScriptsIn(html) {
  const found = []
  const pattern = /<script\b(?![^>]*\bsrc\s*=)([^>]*)>([\s\S]*?)<\/script>/gi
  for (const match of String(html ?? "").matchAll(pattern)) {
    const type = /\btype\s*=\s*["']?([^"'\s>]*)/i.exec(match[1])
    if (runsAsScript(type ? type[1] : "")) found.push(match[2])
  }
  return found
}

export function hashOf(text) {
  return "sha256-" + createHash("sha256").update(text, "utf8").digest("base64")
}

// Whether a policy header lets an inline script with this text run. A header
// can carry several policies joined with ", " (Netlify joins two _headers
// blocks that way); each must allow it. A policy's script-src-elem, else its
// script-src, else its default-src governs; with none, inline script runs.
// 'unsafe-inline' counts only when the list names no hash and no nonce, as
// CSP Level 3 says.
export function policyAllows(header, text) {
  const hash = hashOf(text)
  for (const policy of String(header ?? "").split(",")) {
    const directives = new Map()
    for (const part of policy.split(";")) {
      const words = part.trim().split(/\s+/).filter((word) => word !== "")
      if (words.length > 0 && !directives.has(words[0].toLowerCase())) directives.set(words[0].toLowerCase(), words.slice(1))
    }
    const sources = directives.get("script-src-elem") ?? directives.get("script-src") ?? directives.get("default-src")
    if (!sources) continue
    const hashes = sources.filter((source) => /^'sha(256|384|512)-/i.test(source))
    const nonces = sources.filter((source) => /^'nonce-/i.test(source))
    if (hashes.includes(`'${hash}'`)) continue
    if (hashes.length === 0 && nonces.length === 0 && sources.includes("'unsafe-inline'")) continue
    return false
  }
  return true
}

// Sorts the refused inline scripts of one page.
//   documents  every document the page was sent (its first load, a row's
//              reload, the next page a row went to), each
//              { policy, received, served }: its Content-Security-Policy
//              header, its HTML as the browser received it, and its HTML as
//              the host serves it to a client that is not a browser
//   inTheDom   the texts of the inline scripts the last document holds now
//              (judged by the last document's policy)
// Answers { injected, own, madeAtRunTime }: refused scripts that only the
// browser was sent, refused scripts the site's own pages hold, and refused
// scripts that are in neither (the page's scripts made them). Answers null
// when a document's served copy is missing: without it nothing can be told
// apart, and nothing is set aside.
export function sortRefusedScripts({ documents, inTheDom }) {
  if (!Array.isArray(documents) || documents.length === 0) return null
  const receivedScripts = new Set()
  const servedScripts = new Set()
  for (const document of documents) {
    if (!document || typeof document.served !== "string" || typeof document.received !== "string") return null
    for (const text of inlineScriptsIn(document.received)) receivedScripts.add(text)
    for (const text of inlineScriptsIn(document.served)) servedScripts.add(text)
  }
  const candidates = []
  for (const document of documents) {
    for (const text of inlineScriptsIn(document.received)) candidates.push({ text, policy: document.policy })
  }
  const last = documents[documents.length - 1]
  for (const text of inTheDom ?? []) candidates.push({ text, policy: last.policy })
  const sorted = { injected: [], own: [], madeAtRunTime: [] }
  const seen = new Set()
  for (const candidate of candidates) {
    if (policyAllows(candidate.policy, candidate.text)) continue
    if (seen.has(candidate.text)) continue
    seen.add(candidate.text)
    const one = { hash: hashOf(candidate.text), start: candidate.text.trim().slice(0, 60) }
    if (servedScripts.has(candidate.text)) sorted.own.push(one)
    else if (receivedScripts.has(candidate.text)) sorted.injected.push(one)
    else sorted.madeAtRunTime.push(one)
  }
  return sorted
}

// The entries of rendered_rows.json -> refusedByDesign that apply on `host`.
export function byDesignFor(entries, host) {
  const mine = []
  for (const entry of entries ?? []) {
    if ((entry.hosts ?? []).includes(host)) mine.push(entry)
  }
  return mine
}

// Whether a console line is one of an entry's refusal lines.
export function isRefusalLine(entry, text) {
  for (const pattern of entry.lines ?? []) {
    if (new RegExp(pattern).test(text)) return true
  }
  return false
}

// The judgement for one page: which lines the clean-page row sets aside, and
// what it must fail on whatever the lines say.
//   entries   the refusedByDesign entries for this host
//   sorted    sortRefusedScripts' answer for the page (or null: not looked at)
//   lines     the page's console and refusal lines, as the row collected them
// Answers { setAside: [lines], entry, failures: [sentences] }.
export function judgeRefusals(entries, sorted, lines) {
  const failures = []
  if (!sorted) return { setAside: [], entry: null, failures }
  for (const one of sorted.own) {
    failures.push(`the page's own inline script (${one.hash}, starting "${one.start}") was refused: the page's policy does not list it`)
  }
  for (const one of sorted.madeAtRunTime) {
    failures.push(`an inline script the page's scripts made (${one.hash}, starting "${one.start}") was refused: it is in no page the host sends`)
  }
  if (failures.length > 0 || sorted.injected.length === 0 || entries.length === 0) return { setAside: [], entry: null, failures }
  const entry = entries[0]
  const setAside = []
  for (const text of lines) {
    if (isRefusalLine(entry, text)) setAside.push(text)
  }
  return { setAside, entry, failures }
}
