// Whose refusal a "Refused to display" console line is
// (browser-checks/lib/frame_refusals.mjs), with no browser: run by
// verify-deploy.sh --self-test (#597's second half, 597b fix review MINOR 2).
//   node browser-checks/lib/test_frame_refusals.mjs
// Prints one line per case and exits 0 only when every case passed.

import { whoseRefusal } from "./frame_refusals.mjs"

let failures = 0
function expect(name, said, wanted) {
  const good = said === wanted
  console.log(`${good ? "OK" : "FAIL"}: ${name}${good ? "" : ` (said ${said}, wanted ${wanted})`}`)
  if (!good) failures += 1
}

const own = ["https://www.youtube-nocookie.com/embed/abc?rel=0", "https://www.geogebra.org/material/iframe/id/xyz"]
const nested = ["https://googleads.g.doubleclick.net/pagead/frame", "https://www.youtube-nocookie.com/inner/frame"]

// WebKit names the full address.
expect("a refused frame of the page itself is the page's (WebKit's full address)",
  whoseRefusal("https://www.geogebra.org/material/iframe/id/xyz", own, nested), "page")
expect("a refused frame inside an embed is the embed's (WebKit's full address)",
  whoseRefusal("https://googleads.g.doubleclick.net/pagead/frame", own, nested), "embed")
expect("the page's own frame matched without its query",
  whoseRefusal("https://www.youtube-nocookie.com/embed/abc", own, nested), "page")

// Chromium names only the origin.
expect("an origin only the page's own frames used is the page's (Chromium)",
  whoseRefusal("https://www.geogebra.org/", own, nested), "page")
expect("an origin only an embed's inner frames used is the embed's (Chromium)",
  whoseRefusal("https://googleads.g.doubleclick.net/", own, nested), "embed")
expect("an origin both used is set aside, the request half judging the page's own frame",
  whoseRefusal("https://www.youtube-nocookie.com/", own, nested), "embed")

// The safe direction.
expect("an address the page never asked for stays the page's",
  whoseRefusal("https://player.vimeo.com/video/1", own, nested), "page")
expect("an origin nobody asked for stays the page's",
  whoseRefusal("https://player.vimeo.com/", own, nested), "page")
expect("with no embed frames at all, a refusal is the page's",
  whoseRefusal("https://www.geogebra.org/", own, []), "page")
expect("an address that does not parse stays the page's",
  whoseRefusal("not an address", own, nested), "page")

console.log(failures === 0 ? "DONE: every case passed" : `DONE: ${failures} case(s) failed`)
process.exit(failures === 0 ? 0 : 1)
