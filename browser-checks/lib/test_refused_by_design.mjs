// The refusals a site's policy makes on purpose (browser-checks/lib/refused_by_design.mjs),
// with no browser: run by verify-deploy.sh --self-test (#597's second half).
//   node browser-checks/lib/test_refused_by_design.mjs
// Prints one line per case and exits 0 only when every case passed.

import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { byDesignFor, hashOf, inlineScriptsIn, isRefusalLine, judgeRefusals, policyAllows, refusalMessages, sortRefusedScripts } from "./refused_by_design.mjs"

const HERE = dirname(fileURLToPath(import.meta.url))
const ENTRIES = JSON.parse(readFileSync(join(HERE, "..", "rendered_rows.json"), "utf-8")).refusedByDesign
let failures = 0
function expect(name, good, detail) {
  console.log(`${good ? "OK" : "FAIL"}: ${name}${good ? "" : ` (${detail})`}`)
  if (!good) failures += 1
}

// A page the way Quartz writes it: two inline scripts of its own and one
// that is data, never run.
const OWN_ONE = 'const fetchData = fetch("./static/contentIndex.json").then(data => data.json())'
const OWN_TWO = "function toggle(){document.body.classList.toggle(\"open\")}"
const DATA = '{"not":"run"}'
const SITE = `<html><head><script type="application/javascript" spa-preserve>${OWN_ONE}</script><script type="application/json">${DATA}</script><script src="/static/postscript.js"></script></head><body><script type="module">${OWN_TWO}</script></body></html>`
const BADGE = "(function(){var b=document.createElement('iframe');document.body.append(b)})()"
const WITH_BADGE = SITE.replace("</head>", `<script>${BADGE}</script></head>`)
const POLICY = `script-src 'self' 'unsafe-eval' '${hashOf(OWN_ONE)}' '${hashOf(OWN_TWO)}' https://cdnjs.cloudflare.com;`
// The two wordings measured on the first deployed run (2026-11-13).
const CHROMIUM = `Executing inline script violates the following Content Security Policy directive 'script-src 'self' 'unsafe-eval' '${hashOf(OWN_ONE)}''. Either the 'unsafe-inline' keyword, a hash ('sha256-x'), or a nonce ('nonce-...') is required to enable inline execution. (https://example.netlify.app/Rendered-Check/Quiz)`
const WEBKIT = "Refused to execute a script because its hash, its nonce, or 'unsafe-inline' does not appear in the script-src directive of the Content Security Policy."
const NETLIFY = byDesignFor(ENTRIES, "netlify")

expect("the page's run scripts are read, its data script and its linked script are not", JSON.stringify(inlineScriptsIn(SITE)) === JSON.stringify([OWN_ONE, OWN_TWO]), JSON.stringify(inlineScriptsIn(SITE)))
expect("a hash the policy lists lets a script run; one it does not list does not", policyAllows(POLICY, OWN_ONE) && !policyAllows(POLICY, BADGE), POLICY)
expect("'unsafe-inline' beside a hash lets nothing else in (CSP Level 3)", !policyAllows(`script-src 'unsafe-inline' '${hashOf(OWN_ONE)}'`, BADGE), "")
expect("a page with no script policy refuses no inline script", policyAllows("frame-ancestors 'self'", BADGE), "")
expect("two policies joined: both must allow", !policyAllows(`script-src 'unsafe-inline', ${POLICY}`, BADGE) && policyAllows(`default-src 'self' '${hashOf(BADGE)}', script-src '${hashOf(BADGE)}'`, BADGE), "")
expect("refusedByDesign applies on Netlify and on no other host", NETLIFY.length === 1 && byDesignFor(ENTRIES, "cloudflare").length === 0 && byDesignFor(ENTRIES, "folder").length === 0, JSON.stringify(ENTRIES))
expect("both engines' wordings are the badge's refusal lines", isRefusalLine(NETLIFY[0], CHROMIUM) && isRefusalLine(NETLIFY[0], WEBKIT), "")
expect("a refused import or a refused eval is not one of them", !isRefusalLine(NETLIFY[0], "Refused to load the script 'https://example.com/x.js' because it violates the following Content Security Policy directive: \"script-src 'self'\"")
  && !isRefusalLine(NETLIFY[0], "Refused to evaluate a string as JavaScript because 'unsafe-eval' is not an allowed source of script"), "")

// The first run's shape: the badge only in what the browser received.
let sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: WITH_BADGE, served: SITE }], inTheDom: [OWN_ONE, BADGE, OWN_TWO] })
expect("a script only the browser was sent, refused, is the host's (injected)", sorted && sorted.injected.length === 1 && sorted.own.length === 0 && sorted.madeAtRunTime.length === 0, JSON.stringify(sorted))
let judged = judgeRefusals(NETLIFY, sorted, [CHROMIUM, "Uncaught TypeError: boom"])
expect("then its refusal line is set aside, and nothing else is", judged.failures.length === 0 && judged.setAside.length === 1 && judged.setAside[0] === CHROMIUM, JSON.stringify(judged))

// The fault the policy exists to prevent: a hash of the site's own missing.
const DRIFTED = `script-src 'self' 'unsafe-eval' '${hashOf(OWN_ONE)}'`
sorted = sortRefusedScripts({ documents: [{ policy: DRIFTED, received: WITH_BADGE, served: SITE }], inTheDom: [] })
judged = judgeRefusals(NETLIFY, sorted, [CHROMIUM, CHROMIUM])
expect("a policy that lost one of the site's own hashes fails, badge or no badge, and sets nothing aside", sorted.own.length === 1 && judged.failures.length === 1 && judged.setAside.length === 0 && /own inline script/.test(judged.failures[0]), JSON.stringify(judged))

// A script the host sends to everyone is the site's, whoever wrote it.
sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: WITH_BADGE, served: WITH_BADGE }], inTheDom: [] })
judged = judgeRefusals(NETLIFY, sorted, [WEBKIT])
expect("a refused script in the page as the host serves it to anything is the site's own, and fails", sorted.own.length === 1 && sorted.injected.length === 0 && judged.failures.length === 1 && judged.setAside.length === 0, JSON.stringify(sorted))

// A script the page's own scripts made, refused, is the site's too.
sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: SITE, served: SITE }], inTheDom: [OWN_ONE, "window.made = 1"] })
judged = judgeRefusals(NETLIFY, sorted, [WEBKIT])
expect("a refused script the page made at run time fails", sorted.madeAtRunTime.length === 1 && judged.failures.length === 1 && judged.setAside.length === 0, JSON.stringify(sorted))

// No badge: a refusal line on its own is never set aside.
sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: SITE, served: SITE }], inTheDom: [OWN_ONE, OWN_TWO] })
judged = judgeRefusals(NETLIFY, sorted, [WEBKIT])
expect("with no refused script found, a refusal line stays a failure", judged.setAside.length === 0 && judged.failures.length === 0, JSON.stringify(judged))

// Without the page as served, nothing can be told apart.
expect("a page whose served copy could not be fetched sets nothing aside", sortRefusedScripts({ documents: [{ policy: POLICY, received: WITH_BADGE, served: null }], inTheDom: [] }) === null
  && judgeRefusals(NETLIFY, null, [WEBKIT]).setAside.length === 0, "")

// A row that reloads, then goes to the next page: every document counts.
const NEXT = SITE.replace("toggle", "toggleNext")
const NEXT_POLICY = `${POLICY.replace(";", "")} '${hashOf(OWN_TWO.replace("toggle", "toggleNext"))}';`
sorted = sortRefusedScripts({ documents: [
  { policy: POLICY, received: WITH_BADGE, served: SITE },
  { policy: NEXT_POLICY, received: NEXT.replace("</head>", `<script>${BADGE}</script></head>`), served: NEXT },
], inTheDom: [BADGE] })
expect("a reload and the next page: the badge once, as the host's, nothing of the site's", sorted && sorted.injected.length === 1 && sorted.own.length === 0 && sorted.madeAtRunTime.length === 0, JSON.stringify(sorted))

// Counted page by page (597b fix review, d1): one refused script a document
// that only the browser was sent, one line for each, as the first run
// measured; anything more fails and says the count.
sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: WITH_BADGE, served: SITE }], inTheDom: [] })
judged = judgeRefusals(NETLIFY, sorted, [CHROMIUM, CHROMIUM, CHROMIUM])
expect("counted: three refusal lines in the badge's wording where one badge accounts for one fail, naming the count, and nothing is set aside", judged.setAside.length === 0 && judged.failures.length === 1 && /^3 refusal lines .* account for 1 /.test(judged.failures[0]), JSON.stringify(judged))
const SECOND = "(function(){window.second=1})()"
const TWO_INJECTED = WITH_BADGE.replace("</head>", `<script>${SECOND}</script></head>`)
sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: TWO_INJECTED, served: SITE }], inTheDom: [] })
judged = judgeRefusals(NETLIFY, sorted, [WEBKIT, WEBKIT])
expect("counted: a second refused script the host sent the browser alone, in one document, fails, naming the count", sorted.injectedPerDocument.join() === "2" && judged.setAside.length === 0 && judged.failures.length === 1 && /^2 refused inline scripts the host sent the browser alone in one document/.test(judged.failures[0]), JSON.stringify(judged))
const RELOADED = [{ policy: POLICY, received: WITH_BADGE, served: SITE }, { policy: POLICY, received: WITH_BADGE, served: SITE }]
sorted = sortRefusedScripts({ documents: RELOADED, inTheDom: [BADGE] })
judged = judgeRefusals(NETLIFY, sorted, [CHROMIUM, CHROMIUM])
expect("counted: a page reloaded once was sent the badge twice, and its two lines are set aside", sorted.injectedPerDocument.join() === "1,1" && judged.failures.length === 0 && judged.setAside.length === 2 && judged.allowed === 2, JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, sorted, [CHROMIUM, CHROMIUM, CHROMIUM])
expect("counted: a page reloaded once with three lines in the badge's wording fails", judged.failures.length === 1 && judged.setAside.length === 0 && /^3 refusal lines .* account for 2 /.test(judged.failures[0]), JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, sorted, [CHROMIUM])
expect("counted: a page reloaded once with one line in the badge's wording, where it was sent the badge twice, fails", judged.failures.length === 1 && judged.setAside.length === 0 && /^1 refusal lines .* account for 2 .*was not seen/.test(judged.failures[0]), JSON.stringify(judged))
// A page with a frame of the site's own (a PhET simulation's copy, #674):
// the checker lists the frame's document first and the page's last. A
// stand-in edge that added the badge to both (2026-11-14, both engines) gave
// two lines, one from each document, which both are set aside for.
const SIM_OWN = "window.phet={chipper:{}}"
const SIM = `<html><head><script>${SIM_OWN}</script></head><body></body></html>`
const SIM_WITH_BADGE = SIM.replace("<head>", `<head><script>${BADGE}</script>`)
const SIM_POLICY = POLICY.replace(";", ` '${hashOf(SIM_OWN)}';`)
sorted = sortRefusedScripts({ documents: [{ policy: SIM_POLICY, received: SIM_WITH_BADGE, served: SIM }, { policy: SIM_POLICY, received: WITH_BADGE, served: SITE }], inTheDom: [OWN_ONE, OWN_TWO] })
judged = judgeRefusals(NETLIFY, sorted, [WEBKIT, WEBKIT])
expect("counted: the badge in a page and in its own simulation's frame is two scripts, and their two lines are set aside", sorted.injectedPerDocument.join() === "1,1" && judged.failures.length === 0 && judged.setAside.length === 2, JSON.stringify(judged))
sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: SIM_WITH_BADGE, served: SIM }, { policy: SIM_POLICY, received: WITH_BADGE, served: SITE }], inTheDom: [] })
judged = judgeRefusals(NETLIFY, sorted, [WEBKIT, WEBKIT])
expect("a simulation's own script that its frame's policy does not list is the site's, and fails", sorted.own.length === 1 && judged.failures.length === 1 && /own inline script/.test(judged.failures[0]), JSON.stringify(judged))
const AT = " (https://example.netlify.app/Rendered-Check/Quiz)"
let counted = refusalMessages([WEBKIT + AT], [WEBKIT])
expect("counted: WebKit's one refusal, recorded in the console with its address and again in the refused list, is one message", counted.messages.length === 1 && counted.twinOf.get(WEBKIT) === WEBKIT + AT, JSON.stringify(counted.messages))
counted = refusalMessages([WEBKIT + AT, WEBKIT + AT], [WEBKIT, WEBKIT])
expect("counted: two refusals in the same words are two messages, never one", counted.messages.length === 2, JSON.stringify(counted.messages))
counted = refusalMessages([CHROMIUM], [WEBKIT])
expect("counted: a refused line with no console twin is a message of its own", counted.messages.length === 2, JSON.stringify(counted.messages))
expect("counted: refusedByDesign carries the two counts, one a document and one a script", NETLIFY[0].refusedScriptsPerDocument === 1 && NETLIFY[0].linesPerRefusedScript === 1 && !("expectedLinesPerEngine" in NETLIFY[0]), JSON.stringify(NETLIFY[0]))

if (failures > 0) {
  console.log(`${failures} case(s) failed`)
  process.exit(1)
}
