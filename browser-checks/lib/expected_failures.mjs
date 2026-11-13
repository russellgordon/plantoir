// What the own-host row (browser-checks/rendered_features.mjs) does with the
// hosts a built site still asks today (rendered_rows.json ->
// thirdPartyHostsToday), kept apart from the browsers so verify-deploy.sh's
// offline self-test can run it (#597's second half).
//
// On this Mac (--site) those hosts are ALLOWED: verify.sh judges the build,
// and a page that asks fewer of them is fine (plan review M3, a subset).
// On a deployed site (--base) the rule is the one the owner set on
// 2026-11-13, "no request leaves the site's own host", so each of them is an
// EXPECTED FAILURE: printed, counted, never a pass and never a failure. #566
// moves the fonts and Mermaid onto the site; then a listed host that no page
// asks for any more is a FAILURE that says to take it off the list, so the
// list shrinks with the fix and the gate tightens on its own.
//
// No packages; Node 22.

// Sorts the other hosts one page asked into strangers (a failure anywhere)
// and expected ones (a failure the list names). `asked` is a Map of host to
// the first thing asked of it; `listed` the list's hosts.
export function sortAsked(asked, listed, deployed) {
  const allowed = new Set(listed)
  const strangers = []
  const expected = []
  for (const [host, what] of asked) {
    if (!allowed.has(host)) strangers.push({ host, what })
    else if (deployed) expected.push({ host, what })
  }
  return { strangers, expected }
}

// The listed hosts that no page asked in one engine's whole run: each is an
// expected failure that stopped failing. `seen` is every host any page
// asked, the strangers' included.
export function stoppedFailing(listed, seen) {
  const asked = new Set(seen)
  const stopped = []
  for (const host of listed) {
    if (!asked.has(host)) stopped.push(host)
  }
  return stopped
}
