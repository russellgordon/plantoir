// The own-host row's expected failures (browser-checks/lib/expected_failures.mjs),
// with no browser: run by verify-deploy.sh --self-test (#597's second half).
//   node browser-checks/lib/test_expected_failures.mjs
// Prints one line per case and exits 0 only when every case passed.

import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { outsidePins, pinnedButNotAsked, sortAsked, stoppedFailing } from "./expected_failures.mjs"

const HERE = dirname(fileURLToPath(import.meta.url))
const TODAY = JSON.parse(readFileSync(join(HERE, "..", "rendered_rows.json"), "utf-8")).thirdPartyHostsToday
const LISTED = TODAY.hosts
const PINS = TODAY.pinned
let failures = 0
function expect(name, good, detail) {
  console.log(`${good ? "OK" : "FAIL"}: ${name}${good ? "" : ` (${detail})`}`)
  if (!good) failures += 1
}

const today = new Map([["fonts.googleapis.com", "/css2"], ["fonts.gstatic.com", "/s/plex.woff2"]])

let sorted = sortAsked(today, LISTED, false)
expect("on this Mac a listed host is allowed: no stranger, nothing expected", sorted.strangers.length === 0 && sorted.expected.length === 0, JSON.stringify(sorted))

sorted = sortAsked(today, LISTED, true)
expect("on a deployed site a listed host is an expected failure, never allowed", sorted.strangers.length === 0 && sorted.expected.length === 2, JSON.stringify(sorted))

sorted = sortAsked(new Map([...today, ["example.com", "/pixel.png"]]), LISTED, true)
expect("a host the list does not name is a stranger on a deployed site", sorted.strangers.length === 1 && sorted.strangers[0].host === "example.com" && sorted.expected.length === 2, JSON.stringify(sorted))

sorted = sortAsked(new Map([["example.com", "/pixel.png"]]), LISTED, false)
expect("and on this Mac", sorted.strangers.length === 1, JSON.stringify(sorted))

expect("every listed host asked: nothing stopped failing", stoppedFailing(LISTED, [...LISTED, "example.com"]).length === 0, "")

// The shape #566's first half leaves: Mermaid from the site, the fonts
// still from Google. cdnjs stops failing and must be reported.
const after566a = stoppedFailing(["fonts.googleapis.com", "fonts.gstatic.com", "cdnjs.cloudflare.com"], ["fonts.googleapis.com", "fonts.gstatic.com"])
expect("a listed host no page asked any more is reported, so the list shrinks", after566a.length === 1 && after566a[0] === "cdnjs.cloudflare.com", JSON.stringify(after566a))

expect("an empty list (after #566) has nothing to stop", stoppedFailing([], ["example.com"]).length === 0, "")

// Pins (597b review finding 2): pages and paths.
const mermaid = { host: "cdnjs.cloudflare.com", path: "/ajax/libs/mermaid/11.4.0/mermaid.esm.min.mjs" }
expect("the pinned Mermaid engine from the Diagrams page is inside its pins", outsidePins([mermaid, { host: "fonts.googleapis.com", path: "/css2" }], PINS, "Diagrams").length === 0, "")
let outside = outsidePins([mermaid], PINS, "Quiz")
expect("cdnjs asked from a page it is not pinned to is a stranger", outside.length === 1 && /Quiz page/.test(outside[0]), JSON.stringify(outside))
outside = outsidePins([{ host: "cdnjs.cloudflare.com", path: "/ajax/libs/jquery/3.7.1/jquery.min.js" }], PINS, "Diagrams")
expect("cdnjs asked for another library is a stranger", outside.length === 1 && /outside the paths/.test(outside[0]), JSON.stringify(outside))
expect("a host the list does not name is left to sortAsked", outsidePins([{ host: "example.com", path: "/x" }], PINS, "Quiz").length === 0, "")
const askedBy = new Map([["Diagrams", ["cdnjs.cloudflare.com", "fonts.googleapis.com", "fonts.gstatic.com"]], ["Handout", ["fonts.googleapis.com", "fonts.gstatic.com"]], ["Quiz", ["fonts.googleapis.com", "fonts.gstatic.com"]]])
const missed = pinnedButNotAsked(PINS, askedBy, ["Diagrams", "Handout", "Quiz"])
expect("a pinned page that ran and did not ask its host is reported", missed.length === 1 && missed[0].host === "cdnjs.cloudflare.com" && missed[0].page === "Handout", JSON.stringify(missed))
expect("a pinned page that did not run is not judged", pinnedButNotAsked(PINS, new Map([["Quiz", ["fonts.googleapis.com", "fonts.gstatic.com"]]]), ["Quiz"]).length === 0, "")
expect("one expected line per listed host and engine is the pinned count", TODAY.expectedLinesPerEngine === LISTED.length, `${TODAY.expectedLinesPerEngine} against ${LISTED.length}`)

console.log(failures === 0 ? "DONE: every case passed" : `DONE: ${failures} case(s) failed`)
process.exit(failures === 0 ? 0 : 1)
