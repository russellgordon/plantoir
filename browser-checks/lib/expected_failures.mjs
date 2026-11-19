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

// Each listed host is pinned to the pages that may ask it and the paths it
// may be asked for (rendered_rows.json -> thirdPartyHostsToday.pinned; 597b
// review finding 2): a listed host asked from another page, or for another
// path (cdnjs for a second library, say), is a stranger, on this Mac and on
// a deployed site alike. `asks` is every { host, path } one page asked.
export function outsidePins(asks, pins, pageName) {
  const outside = []
  for (const one of asks) {
    const pin = pins[one.host]
    if (!pin) continue
    const pageAllowed = pin.pages === "*" || pin.pages.includes(pageName)
    let pathAllowed = false
    for (const prefix of pin.paths) {
      if (one.path.startsWith(prefix)) pathAllowed = true
    }
    if (!pageAllowed) outside.push(`asked ${one.host}${one.path} from the ${pageName} page, which thirdPartyHostsToday does not pin to it`)
    else if (!pathAllowed) outside.push(`asked ${one.host} for ${one.path}, outside the paths thirdPartyHostsToday pins it to (${pin.paths.join(", ")})`)
  }
  return outside
}

// The pinned pages that ran in one engine and did not ask their host: the
// expected failure moved or shrank, so the pin is shortened with it.
// `askedBy` maps a page to the hosts it asked; `ran` lists the pages.
export function pinnedButNotAsked(pins, askedBy, ran) {
  const missed = []
  for (const [host, pin] of Object.entries(pins)) {
    const pages = pin.pages === "*" ? ran : pin.pages
    for (const page of pages) {
      if (!ran.includes(page)) continue
      if (!(askedBy.get(page) ?? []).includes(host)) missed.push({ host, page })
    }
  }
  return missed
}
