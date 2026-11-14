// A refusal the site's own policy makes ON PURPOSE, told apart from one it
// makes by mistake, for the clean-page row of the rendered check
// (browser-checks/rendered_features.mjs, #597's second half).
//
// The one case today is Netlify's badge. Netlify appends a loader after the
// page's own `</html>`, `<script async src="/.netlify/scripts/hud?variant=public"
// data-nf-variant="public" …>`, a file of its own origin that the policy's
// 'self' lets run. The loader builds `iframe#nl-badge-frame` and writes the
// badge into its `srcdoc`, with one inline script; a srcdoc frame takes its
// page's policy, and the Content-Security-Policy scripts/netlify_badge.py
// writes leaves 'unsafe-inline' out, so that script is refused
// (documentation/07, "Suppressing Netlify's own ad badge"; #625 settled the
// frame, measured at about:srcdoc:85). The first two deployed runs
// (2026-11-13 and 14) saw it on each of the 11 pages, in both engines.
//
// What identifies it is not its wording alone. A site whose policy lost the
// hash of one of its OWN inline scripts (the drift netlify_badge.py exists to
// prevent) is refused with the same words, and that must stay red. What is
// certain is WHERE it is said: in the badge's srcdoc frame (the console
// message's own address is about:srcdoc), which no page a site builds makes,
// and never in the page itself, where the site's own scripts run. So a
// message is set aside only when it is in the wording rendered_rows.json ->
// refusedByDesign names, said in its frame, on a page whose every document
// was read for the loader, and only as many as the documents that carried
// the loader account for.
//
// The first version of this rule (597b's fix) looked for the refused script
// in the page's own HTML as the browser received it and not as the host
// serves it to anything else. It was proven against a stand-in that wrote
// the script into the page; the real edge writes a loader that is a file,
// sent to curl as well as to browsers, and the refused script is built in
// the frame at run time, so it was in neither copy and nothing was set
// aside (second deployed run, 2026-11-14: 2 FAIL, 6 EXPECTED where 8 were
// predicted). The reading of the page's own copies stays, to NAME a refused
// script of the site's own (sortRefusedScripts), never to set one aside.
//
// And they are COUNTED, page by page (597b fix review, d1): exactly
// `refusalsPerDocument` messages for each document that carried the
// loader (WebKit's two records of one message counted once, by the caller).
// The loader is an async script, which the load event waits for, and it
// mounts the frame at once, so every document a row waited on is refused
// once: Tasks (loaded, reloaded, taken to My Progress) 3, Embeds (reloaded)
// 2, every other page 1. A second refusal in the frame, or one fewer, fails
// the page and names the count.
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
//              reload, the next page a row went to, and a frame's document
//              from the site's own host, such as a PhET simulation's copy,
//              #674, listed first so the page's own is last), each
//              { policy, received, served }: its Content-Security-Policy
//              header, its HTML as the browser received it, and its HTML as
//              the host serves it to a client that is not a browser
//   inTheDom   the texts of the inline scripts the last document holds now
//              (judged by the last document's policy)
// Answers { injected, own, madeAtRunTime, injectedPerDocument }: refused
// scripts that only the browser was sent, refused scripts the site's own
// pages hold, refused scripts that are in neither (the page's scripts made
// them), and for each document the number of refused scripts only the
// browser was sent in it. Answers null when a document's served copy is
// missing: without it nothing can be told apart, and nothing is set aside.
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
  // Counted in each document as it was received, a script repeated in one
  // document counted each time it is there, since each is refused.
  sorted.injectedPerDocument = []
  for (const document of documents) {
    let count = 0
    for (const text of inlineScriptsIn(document.received)) {
      if (!policyAllows(document.policy, text) && !servedScripts.has(text)) count += 1
    }
    sorted.injectedPerDocument.push(count)
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

// Whether a document's HTML carries an entry's loader: the tag the host
// appends AFTER the page's own `</html>` (Netlify's
// `<script async src="/.netlify/scripts/hud?variant=public" data-nf-variant="public" …>`,
// measured 2026-11-14 on the second deployed run's served copy and on a
// live test site; #625 settled the same tag). Read only after the last
// `</html>`, which no page a site builds writes anything past, so a page
// that merely mentions the address in its own text is not counted.
// Answers null when there is no HTML to read.
//
// The last `</html>` is found in the HTML itself, never in a lowercased
// copy: lowercasing can make a string LONGER (U+0130, "İ", becomes two code
// units), so an index found in the copy points past the tag in the original.
// The PhET simulation the Simulation page frames holds eleven of them in its
// translations, so the first deployed run with a frame (stack 12,
// 2026-11-14) read its loader 11 characters late, inside the tag, and
// counted 1 of 2 documents where both carried it (measured again on a local
// stand-in edge, both engines, with the real gas-properties 1.1.12).
export function loaderIn(entry, html) {
  if (typeof html !== "string") return null
  let after = -1
  for (const match of html.matchAll(/<\/html>/gi)) after = match.index + match[0].length
  if (after < 0) return false
  return new RegExp(entry.loader).test(html.slice(after))
}

// The hash Chromium names for the script it refused ("Either the
// 'unsafe-inline' keyword, a hash ('sha256-…'), or a nonce … is required"),
// or null: WebKit's wording names none.
export function namedHash(text) {
  const found = /a hash \('(sha(?:256|384|512)-[A-Za-z0-9+/=]+)'\)/.exec(String(text ?? ""))
  return found ? found[1] : null
}

// The judgement for one page: which refusal messages the clean-page row
// sets aside, and what it must fail on whatever the messages say.
//   entries    the refusedByDesign entries for this host
//   evidence   what readRefusals saw on the page:
//                sorted      sortRefusedScripts' answer (or null)
//                documents   one { url, carriesLoader } for every document
//                            the page was sent (true, false, or null when
//                            neither copy could be read)
//                ownHashes   the hashes of the inline scripts in the page as
//                            the host serves it
//   messages   the page's refusal and console lines as messages, each
//              { text, at }: at is the address of the frame the browser said
//              it in (null when the record carried none)
// Answers { setAside: [messages], entry, failures: [sentences], allowed }.
//
// Set aside only what is CERTAIN to be Netlify's badge (second deployed
// run, 2026-11-14): a message in the entry's wording, said in the entry's
// frame (about:srcdoc: the badge is built in a srcdoc frame by the loader,
// and no page a site builds makes one), on a page whose every document can
// be read for the loader, and exactly `refusalsPerDocument` of them for each
// document that carried it. A refusal said in the page itself is never set
// aside, whatever the host: that is where the site's own scripts run.
export function judgeRefusals(entries, evidence, messages) {
  const failures = []
  if (!entries || entries.length === 0 || !evidence) return { setAside: [], entry: null, failures }
  const entry = entries[0]
  const sorted = evidence.sorted ?? null
  if (sorted) {
    for (const one of sorted.own) {
      failures.push(`the page's own inline script (${one.hash}, starting "${one.start}") was refused: the page's policy does not list it`)
    }
    for (const one of sorted.madeAtRunTime) {
      failures.push(`an inline script the page's scripts made (${one.hash}, starting "${one.start}") was refused: it is in no page the host sends`)
    }
    for (const one of sorted.injected) {
      failures.push(`an inline script the host added to the page itself (${one.hash}, starting "${one.start}") was refused: ${entry.name} is built in its ${entry.frame} frame, never in the page`)
    }
  }
  const own = new Set(evidence.ownHashes ?? [])
  const inFrame = []
  for (const message of messages ?? []) {
    if (!isRefusalLine(entry, message.text)) continue
    const hash = namedHash(message.text)
    const naming = hash ? `, naming ${hash}` : ""
    if (message.at !== entry.frame) {
      failures.push(`a refusal in the wording of ${entry.name}, said in ${message.at ? message.at : "a frame the browser did not name"}${naming}, where ${entry.name} is refused in ${entry.frame}: the site's own`)
    } else if (hash && own.has(hash)) {
      failures.push(`a refusal in ${entry.frame} naming ${hash}, the hash of one of the page's own inline scripts: the site's own`)
    } else inFrame.push(message)
  }
  const documents = evidence.documents ?? []
  let carried = 0
  let unread = 0
  for (const document of documents) {
    if (document.carriesLoader === true) carried += 1
    else if (document.carriesLoader !== false) unread += 1
  }
  const perDocument = entry.refusalsPerDocument ?? 1
  const allowed = carried * perDocument
  if (inFrame.length > 0 && unread > 0) {
    failures.push(`${unread} of the ${documents.length} document(s) the page was sent could not be read for ${entry.name}'s loader, so its ${inFrame.length} refusal(s) in ${entry.frame} cannot be counted`)
  } else if (inFrame.length > allowed) {
    failures.push(`${inFrame.length} refusal(s) in the wording of ${entry.name} in ${entry.frame}, where the ${carried} of ${documents.length} document(s) carrying its loader account for ${allowed} (rendered_rows.json -> refusedByDesign.refusalsPerDocument): a refusal more than the host's`)
  } else if (inFrame.length > 0 && inFrame.length < allowed) {
    // Measured equal on every page in both engines (2026-11-14): the loader
    // runs before the load event, so every document a row waited on was
    // refused once. Fewer means a refusal was not seen, and the count can no
    // longer be trusted, so it errs red. None at all sets nothing aside, and
    // the row is judged on the rest.
    failures.push(`${inFrame.length} refusal(s) in the wording of ${entry.name} in ${entry.frame}, where the ${carried} of ${documents.length} document(s) carrying its loader account for ${allowed} (rendered_rows.json -> refusedByDesign.refusalsPerDocument): a refusal of the host's script was not seen`)
  }
  if (failures.length > 0) return { setAside: [], entry: null, failures, allowed }
  return { setAside: inFrame, entry, failures, allowed }
}

// The page's console and refusal lines as MESSAGES, for counting (597b fix
// review, d1), each { text, at } with the address of the frame it was said
// in (consoleWhere, in step with consoleLines; null where none was kept).
// WebKit's "Refused to" line is recorded twice by the rendered check, in its
// console list with the page's address after it and in its refused list
// without (measured 2026-11-14), so each refused line that has a console
// twin is one message, matched one for one: two refusals with the same
// words are still two. Answers { messages, twins }: twins[i] is the index of
// the console line refused line i is a copy of, or -1.
export function refusalMessages(consoleLines, refusedLines, consoleWhere = []) {
  const said = consoleLines ?? []
  const messages = []
  for (let index = 0; index < said.length; index += 1) messages.push({ text: said[index], at: consoleWhere[index] ?? null, console: index })
  const twins = []
  const used = new Set()
  for (const text of refusedLines ?? []) {
    let twin = -1
    for (let index = 0; index < said.length; index += 1) {
      const line = said[index]
      if (!used.has(index) && (line === text || line.startsWith(text + " ("))) {
        twin = index
        break
      }
    }
    twins.push(twin)
    if (twin >= 0) used.add(twin)
    else messages.push({ text, at: null, refused: twins.length - 1 })
  }
  return { messages, twins }
}
