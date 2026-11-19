// The wait a row of the rendered check makes before it takes the page
// somewhere else (a reload, the next page): until the page's own request for
// the site's search index has answered, with a ceiling (#597's second half,
// browser-checks/rendered_features.mjs).
//
// Quartz asks for static/contentIndex.json as a page loads (its inline
// script's `fetchData`, which nothing catches), and a navigation that cancels
// that request makes WebKit throw "TypeError: Load failed" into the page,
// which the clean-page row counts as the row's own fault (measured
// 2026-11-13 in headless WebKit with 0.5 s of latency). So the wait is on the
// page's own promise, the real dependency, never a fixed sleep.
//
// Reaching the ceiling is never silent (597b fix review, d2): the answer says
// so, the row's line says so with a count, and verify-deploy.sh carries it
// into its Result block. An index that never answers would otherwise pass the
// clean-page row with no word about it.
//
// No packages. Tested by test_index_wait.mjs.

// How long a row waits for the index before it goes on without it.
export const INDEX_WAIT_CEILING_MS = 30000

// Run INSIDE the page (page.evaluate serialises it, so it uses nothing from
// this module). Answers "none" when the page has no `fetchData` (nothing in
// flight to cancel), "arrived" when it settled, either way (a broken index
// is reported by the next document, which asks again), and "gave up" when
// the ceiling came first.
export function untilFetchDataSettles(ceiling) {
  const pending = typeof fetchData === "undefined" ? null : fetchData
  if (!pending || typeof pending.then !== "function") return "none"
  return Promise.race([
    pending.then(() => "arrived", () => "arrived"),
    new Promise((resolve) => setTimeout(() => resolve("gave up"), ceiling)),
  ])
}

// The words added to a row's line when its waits reached the ceiling.
export function indexWaitNote(count, ceiling = INDEX_WAIT_CEILING_MS) {
  if (!(count > 0)) return ""
  return `; the page's own request for the search index had not answered after ${Math.round(ceiling / 1000)} s, ${count} time(s), so the row went on without it`
}
