// The refusals a site's policy makes on purpose (browser-checks/lib/refused_by_design.mjs),
// with no browser: run by verify-deploy.sh --self-test (#597's second half).
//   node browser-checks/lib/test_refused_by_design.mjs
// Prints one line per case and exits 0 only when every case passed.

import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { byDesignFor, hashOf, inlineScriptsIn, isRefusalLine, judgeRefusals, loaderIn, namedHash, policyAllows, refusalMessages, sortRefusedScripts } from "./refused_by_design.mjs"

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

// The second deployed run's shape (2026-11-14, real Netlify): the loader
// after </html>, in the copy served to anything; the refused script built in
// the badge's srcdoc frame, in neither copy of the page. The tail is the
// run's served copy of Runner-Deploy-Check, with the site id replaced.
const LOADER = `<script async src="/.netlify/scripts/hud?variant=public" data-nf-variant="public" data-netlify-site-id="00000000-0000-4000-8000-000000000000" data-app-host="app.netlify.com" data-account-tier="free"></script>`
const SERVED = `${SITE}${LOADER}`
// The badge frame's one script, as Chromium names it (measured 2026-11-14
// against Netlify's own hud.js), and the run's two wordings.
const FRAME_HASH = "sha256-BkKP2XO6WOEc3kXOiLr2ZoY83hamalKjPY9xBcbXVuw="
const REAL_POLICY = "'script-src 'self' 'unsafe-eval' 'sha256-26KsxcYYxZCwmG2ho9eotclt/D8QIgCYU6DUNU46mT4=' 'sha256-AE0EQudVMDsl926YZzlYRgeKgzPan7WBWeH3xMTf9kE='"
const CHROMIUM_FRAME = `Executing inline script violates the following Content Security Policy directive ${REAL_POLICY}. Either the 'unsafe-inline' keyword, a hash ('${FRAME_HASH}'), or a nonce ('nonce-...') is required to enable inline execution. The action has been blocked. (about:srcdoc)`
const WEBKIT_FRAME = `${WEBKIT} (about:srcdoc)`
const PAGE = "https://example.netlify.app/Rendered-Check/Diagrams"
const ENTRY = NETLIFY[0]
const read = (count, carries = true) => {
  const documents = []
  for (let index = 0; index < count; index += 1) documents.push({ url: PAGE, carriesLoader: carries })
  return documents
}
const evidence = (documents, extra = {}) => ({ sorted: sortRefusedScripts({ documents: [{ policy: POLICY, received: SERVED, served: SERVED }], inTheDom: [OWN_ONE, OWN_TWO] }), documents, ownHashes: [hashOf(OWN_ONE), hashOf(OWN_TWO)], ...extra })
const said = (text, at) => ({ text, at })

expect("real run: the loader Netlify appends after </html> is read", loaderIn(ENTRY, SERVED) === true, "")
expect("real run: the loader's address in the page's own text, before </html>, is not the loader", loaderIn(ENTRY, SITE.replace("</body>", `<p>${LOADER.replace("<", "&lt;")}</p><code>${LOADER}</code></body>`)) === false, "")
expect("real run: a page with no </html> carries no loader, and no copy at all is unread", loaderIn(ENTRY, "<p>x</p>") === false && loaderIn(ENTRY, null) === null, "")
expect("real run: Chromium names the refused script's hash; WebKit names none", namedHash(CHROMIUM_FRAME) === FRAME_HASH && namedHash(WEBKIT_FRAME) === null, "")
expect("real run: the page's copies hold the loader as a file, so no inline script of the page is refused", (() => { const sorted = evidence(read(1)).sorted; return sorted.own.length === 0 && sorted.injected.length === 0 && sorted.madeAtRunTime.length === 0 })(), "")

let judged = judgeRefusals(NETLIFY, evidence(read(1)), [said(CHROMIUM_FRAME, "about:srcdoc"), said("Uncaught TypeError: boom", PAGE)])
expect("real run [chromium]: the badge's refusal said in about:srcdoc, one document with the loader, is set aside and nothing else is", judged.failures.length === 0 && judged.setAside.length === 1 && judged.setAside[0].text === CHROMIUM_FRAME, JSON.stringify(judged))
let counted = refusalMessages([WEBKIT_FRAME], [WEBKIT], ["about:srcdoc"])
judged = judgeRefusals(NETLIFY, evidence(read(1)), counted.messages)
expect("real run [webkit]: its console record and its refused record are one message, said in about:srcdoc, and set aside", counted.messages.length === 1 && counted.twins.join() === "0" && judged.failures.length === 0 && judged.setAside.length === 1, JSON.stringify(judged))

judged = judgeRefusals(NETLIFY, evidence(read(1)), [said(CHROMIUM.replace(" (https://example.netlify.app/Rendered-Check/Quiz)", ""), PAGE)])
expect("the same wording said in the page itself is the site's own and fails, whatever the host", judged.setAside.length === 0 && judged.failures.length === 1 && /said in https:\/\/example\.netlify\.app\/Rendered-Check\/Diagrams.*the site's own/.test(judged.failures[0]), JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, evidence(read(1)), [said(WEBKIT, null)])
expect("a refusal whose frame the browser did not name is never set aside", judged.setAside.length === 0 && judged.failures.length === 1 && /did not name/.test(judged.failures[0]), JSON.stringify(judged))

// The fault the policy exists to prevent: a hash of the site's own missing.
const DRIFTED = `script-src 'self' 'unsafe-eval' '${hashOf(OWN_ONE)}'`
let sorted = sortRefusedScripts({ documents: [{ policy: DRIFTED, received: SERVED, served: SERVED }], inTheDom: [] })
judged = judgeRefusals(NETLIFY, { sorted, documents: read(1), ownHashes: [hashOf(OWN_ONE), hashOf(OWN_TWO)] }, [said(CHROMIUM_FRAME, "about:srcdoc"), said(`Executing inline script violates the following Content Security Policy directive 'script-src 'self''. Either the 'unsafe-inline' keyword, a hash ('${hashOf(OWN_TWO)}'), or a nonce is required to enable inline execution.`, PAGE)])
expect("a policy that lost one of the site's own hashes fails beside the badge, and sets nothing aside", sorted.own.length === 1 && judged.setAside.length === 0 && judged.failures.length === 2 && /own inline script/.test(judged.failures[0]), JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, evidence(read(1)), [said(CHROMIUM_FRAME.replace(FRAME_HASH, hashOf(OWN_ONE)), "about:srcdoc")])
expect("a refusal in the frame that names one of the page's own hashes fails", judged.setAside.length === 0 && judged.failures.length === 1 && /hash of one of the page's own inline scripts/.test(judged.failures[0]), JSON.stringify(judged))

// The old stand-in's model: the host writes an inline script into the page.
sorted = sortRefusedScripts({ documents: [{ policy: POLICY, received: SITE.replace("</head>", "<script>window.edge=1</script></head>"), served: SITE }], inTheDom: [] })
judged = judgeRefusals(NETLIFY, { sorted, documents: read(1), ownHashes: [] }, [said(WEBKIT_FRAME.replace("about:srcdoc", PAGE), PAGE)])
expect("an inline script the host writes into the page itself is never set aside", sorted.injected.length === 1 && judged.setAside.length === 0 && judged.failures.length === 2 && /never in the page/.test(judged.failures[0]), JSON.stringify(judged))

judged = judgeRefusals(NETLIFY, evidence(read(1, false)), [said(CHROMIUM_FRAME, "about:srcdoc")])
expect("a refusal in a srcdoc frame on a page whose documents carried no loader fails", judged.setAside.length === 0 && judged.failures.length === 1 && /0 of 1 document\(s\) carrying its loader account for 0/.test(judged.failures[0]), JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, evidence([{ url: PAGE, carriesLoader: true }, { url: PAGE, carriesLoader: null }]), [said(WEBKIT_FRAME, "about:srcdoc"), said(WEBKIT_FRAME, "about:srcdoc")])
expect("a document that could not be read for the loader sets nothing aside, and says so", judged.setAside.length === 0 && judged.failures.length === 1 && /1 of the 2 document\(s\) .* could not be read/.test(judged.failures[0]), JSON.stringify(judged))

// Counted page by page, from the real run's pages: one refusal a document.
judged = judgeRefusals(NETLIFY, evidence(read(1)), [said(CHROMIUM_FRAME, "about:srcdoc"), said(CHROMIUM_FRAME.replace(FRAME_HASH, "sha256-c2Vjb25k"), "about:srcdoc")])
expect("counted: a second refusal in the badge's frame, one document, fails, naming the count", judged.setAside.length === 0 && judged.failures.length === 1 && /^2 refusal\(s\) .* account for 1 .*more than the host's/.test(judged.failures[0]), JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, evidence(read(3)), [said(WEBKIT_FRAME, "about:srcdoc"), said(WEBKIT_FRAME, "about:srcdoc"), said(WEBKIT_FRAME, "about:srcdoc")])
expect("counted: Tasks, loaded, reloaded and taken to My Progress, three documents and three refusals, all set aside", judged.failures.length === 0 && judged.setAside.length === 3 && judged.allowed === 3, JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, evidence(read(3)), [said(WEBKIT_FRAME, "about:srcdoc"), said(WEBKIT_FRAME, "about:srcdoc")])
expect("counted: three documents with the loader and two refusals fails, a refusal not seen", judged.setAside.length === 0 && judged.failures.length === 1 && /^2 refusal\(s\) .* account for 3 .*was not seen/.test(judged.failures[0]), JSON.stringify(judged))
judged = judgeRefusals(NETLIFY, evidence(read(2)), [said(CHROMIUM_FRAME, "about:srcdoc"), said(CHROMIUM_FRAME, "about:srcdoc"), said(CHROMIUM_FRAME, "about:srcdoc")])
expect("counted: Embeds, reloaded once, with three refusals in the frame fails", judged.setAside.length === 0 && judged.failures.length === 1 && /^3 refusal\(s\) .* account for 2 /.test(judged.failures[0]), JSON.stringify(judged))
expect("nothing is looked at on a host no entry names", judgeRefusals([], evidence(read(1)), [said(CHROMIUM_FRAME, "about:srcdoc")]).setAside.length === 0 && judgeRefusals(NETLIFY, null, []).setAside.length === 0, "")

const AT = " (https://example.netlify.app/Rendered-Check/Quiz)"
counted = refusalMessages([WEBKIT + AT], [WEBKIT], [PAGE])
expect("counted: WebKit's one refusal, recorded in the console with its address and again in the refused list, is one message", counted.messages.length === 1 && counted.twins.join() === "0" && counted.messages[0].at === PAGE, JSON.stringify(counted.messages))
counted = refusalMessages([WEBKIT + AT, WEBKIT + AT], [WEBKIT, WEBKIT])
expect("counted: two refusals in the same words are two messages, never one", counted.messages.length === 2 && counted.twins.join() === "0,1", JSON.stringify(counted.messages))
counted = refusalMessages([CHROMIUM], [WEBKIT])
judged = judgeRefusals(NETLIFY, evidence(read(2)), [])
expect("counted: a page whose documents carried the loader and said no refusal sets nothing aside and fails nothing", judged.setAside.length === 0 && judged.failures.length === 0, JSON.stringify(judged))
expect("counted: a refused line with no console twin is a message of its own, with no frame", counted.messages.length === 2 && counted.messages[1].at === null, JSON.stringify(counted.messages))
expect("counted: refusedByDesign carries its frame, its loader and one refusal a document, and none of the first version's keys", ENTRY.frame === "about:srcdoc" && typeof ENTRY.loader === "string" && ENTRY.refusalsPerDocument === 1 && !("refusedScriptsPerDocument" in ENTRY) && !("linesPerRefusedScript" in ENTRY), JSON.stringify(ENTRY))

if (failures > 0) {
  console.log(`${failures} case(s) failed`)
  process.exit(1)
}
