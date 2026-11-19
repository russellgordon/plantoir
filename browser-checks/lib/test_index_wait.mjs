// The wait for a page's own index request (browser-checks/lib/index_wait.mjs),
// with no browser: run by verify-deploy.sh --self-test (#597's second half,
// 597b fix review, d2).
//   node browser-checks/lib/test_index_wait.mjs
// Prints one line per case and exits 0 only when every case passed.

import { INDEX_WAIT_CEILING_MS, indexWaitNote, untilFetchDataSettles } from "./index_wait.mjs"

let failures = 0
function expect(name, good, detail) {
  console.log(`${good ? "OK" : "FAIL"}: ${name}${good ? "" : ` (${detail})`}`)
  if (!good) failures += 1
}

// The page's `fetchData` is a global of its inline script; here it is set on
// globalThis, which the bare name inside the waited function reads.
delete globalThis.fetchData
expect("a page with no fetchData has nothing in flight: the wait answers at once", untilFetchDataSettles(50) === "none", "")

globalThis.fetchData = new Promise((resolve) => setTimeout(() => resolve({}), 10))
let answer = await untilFetchDataSettles(500)
expect("an index that answers inside the ceiling: arrived", answer === "arrived", answer)

globalThis.fetchData = Promise.reject(new Error("bad JSON"))
globalThis.fetchData.catch(() => {})
answer = await untilFetchDataSettles(500)
expect("an index that fails: arrived (the next document asks again and reports it)", answer === "arrived", answer)

globalThis.fetchData = new Promise(() => {})
const started = Date.now()
answer = await untilFetchDataSettles(60)
expect("an index that never answers: the wait gives up at its ceiling and says so", answer === "gave up" && Date.now() - started >= 55, `${answer} after ${Date.now() - started} ms`)
delete globalThis.fetchData

expect("a row whose waits reached the ceiling says so with the count; one that did not adds nothing",
  indexWaitNote(2) === `; the page's own request for the search index had not answered after ${INDEX_WAIT_CEILING_MS / 1000} s, 2 time(s), so the row went on without it` && indexWaitNote(0) === "", indexWaitNote(2))
expect("the ceiling is 30 s, as measured against a never-answering index (597b fix review, d2)", INDEX_WAIT_CEILING_MS === 30000, String(INDEX_WAIT_CEILING_MS))

if (failures > 0) {
  console.log(`${failures} case(s) failed`)
  process.exit(1)
}
