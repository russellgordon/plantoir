// Whose refusal a console "Refused to display '<url>' in a frame" line is,
// for the rendered check's embeds and clean-page rows (#597's second half,
// 597b fix review MINOR 2).
//
// The check watches two signs of a frame the provider refuses to be shown in:
// the frame's document failing after it answered (the request half), and
// this console line (the console half). The request half counts only a frame
// of the page itself, never one inside a teacher's embed: an inner frame a
// provider opens is the embed's own business. The console half has to skip
// the same frames, or a provider's own refused inner frame turns a run red
// with nothing wrong on the site's side. Measured 2026-11-13 (headless
// Chrome for Testing 155 and WebKit 2359, local servers): a refused frame
// nested inside an allowed one logs this line to the page's console in both
// engines, and the line's location names no frame (WebKit gives none,
// Chromium gives chrome-error://chromewebdata/). So the line is matched by
// the address it names against the frames the page asked for.
//
// Chromium names only the refused frame's ORIGIN ('http://host/'), WebKit
// its full address. An origin that only an embed's inner frames used is the
// embed's; one that both the page's own frames and an embed's inner frames
// used is set aside as well, because the request half judges the page's own
// frame in both engines, for X-Frame-Options and frame-ancestors alike. A line
// naming an address the page never asked for stays the page's (the safe
// direction: it fails rather than passes).

function withoutQuery(address) {
  return String(address).split("?")[0].split("#")[0]
}

function originOf(address) {
  try {
    return new URL(address).origin
  } catch {
    return ""
  }
}

function namesExactly(frames, address) {
  for (const frame of frames) {
    if (frame === address || withoutQuery(frame) === withoutQuery(address)) return true
  }
  return false
}

function sharesOrigin(frames, origin) {
  if (origin === "") return false
  for (const frame of frames) {
    if (originOf(frame) === origin) return true
  }
  return false
}

// whoseRefusal(<address the line names>, <the page's own frames' addresses>,
// <addresses of frames inside an embed>) -> "page" or "embed"
export function whoseRefusal(refusedAddress, ownFrames, nestedFrames) {
  if (namesExactly(ownFrames, refusedAddress)) return "page"
  if (namesExactly(nestedFrames, refusedAddress)) return "embed"
  let originOnly = false
  try {
    const url = new URL(refusedAddress)
    originOnly = url.pathname === "/" && url.search === ""
  } catch {
    return "page"
  }
  if (!originOnly) return "page"
  const origin = originOf(refusedAddress)
  if (sharesOrigin(nestedFrames, origin)) return "embed"
  return "page"
}
