// Tests for browser-checks/lib/site_server.mjs (#597): a built site served
// the way a host serves it. No browser, no network.
//
//   node browser-checks/lib/test_site_server.mjs

import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { headersFor, readHeadersFile, startSiteServer } from "./site_server.mjs"

const site = mkdtempSync(join(tmpdir(), "plantoir-site-server-test-"))
let failures = 0
const expect = (what, ok, detail = "") => {
  if (!ok) failures += 1
  console.log(`${ok ? "ok  " : "FAIL"} ${what}${ok ? "" : " - " + detail}`)
}
try {
  mkdirSync(join(site, "Rendered-Check"))
  mkdirSync(join(site, "static", "pyodide"), { recursive: true })
  writeFileSync(join(site, "index.html"), "<p>home</p>")
  writeFileSync(join(site, "Rendered-Check", "index.html"), "<p>folder</p>")
  writeFileSync(join(site, "Rendered-Check", "Python.html"), "<p>python</p>")
  writeFileSync(join(site, "static", "pyodide", "pyodide.asm.wasm"), "wasm")
  writeFileSync(join(site, "static", "slow.css"), "p {}")
  writeFileSync(join(site, ".rendered-sabotage.json"), JSON.stringify({ types: { "/static/pyodide/pyodide.asm.wasm": "application/octet-stream" }, hold: { "/static/slow.css": 400 } }))
  writeFileSync(join(site, "_headers"), [
    "# Plantoir: a comment line",
    "/static/pyodide/*",
    "  Cross-Origin-Embedder-Policy: require-corp",
    "/rendered-check/python",
    "  Cross-Origin-Opener-Policy: same-origin",
    "  Cross-Origin-Embedder-Policy: require-corp",
    "/*",
    "  Content-Security-Policy: script-src 'self'",
    "",
  ].join("\n"))

  const blocks = readHeadersFile(site)
  expect("reads three blocks from _headers, comments left out", blocks.length === 3, JSON.stringify(blocks))
  const python = headersFor(blocks, "/Rendered-Check/Python")
  expect("a page's path is matched lower-cased, as Netlify does", python["Cross-Origin-Opener-Policy"] === "same-origin", JSON.stringify(python))
  expect("and the splat block applies too", python["Content-Security-Policy"] === "script-src 'self'", JSON.stringify(python))
  expect("a splat matches the rest of a path", headersFor(blocks, "/static/pyodide/pyodide.asm.wasm")["Cross-Origin-Embedder-Policy"] === "require-corp")
  expect("a page another block names gets no isolation", !("Cross-Origin-Opener-Policy" in headersFor(blocks, "/Rendered-Check/Swift")))

  const server = await startSiteServer(site)
  try {
    expect("listens on [::1]", server.origin.startsWith("http://[::1]:"), server.origin)
    const get = (path) => fetch(server.origin + path)
    let answer = await get("/Rendered-Check/Python")
    expect("a page without .html answers with the page", answer.status === 200 && (await answer.text()) === "<p>python</p>")
    expect("with the headers its path has", answer.headers.get("cross-origin-opener-policy") === "same-origin")
    answer = await get("/Rendered-Check/")
    expect("a folder answers with its index.html", answer.status === 200 && (await answer.text()) === "<p>folder</p>")
    answer = await get("/_headers")
    expect("_headers is never served", answer.status === 404)
    answer = await get("/.rendered-sabotage.json")
    expect("a dot file is never served", answer.status === 404)
    answer = await get("/../etc/passwd")
    expect("nothing outside the folder", answer.status === 404 || answer.status === 403)
    answer = await get("/static/pyodide/pyodide.asm.wasm")
    expect("a sabotage's type is sent", answer.headers.get("content-type") === "application/octet-stream", answer.headers.get("content-type"))
    const began = Date.now()
    answer = await get("/static/slow.css")
    expect("a sabotage's hold holds", Date.now() - began >= 380, `${Date.now() - began} ms`)
    answer = await get("/Nothing-Here")
    expect("a missing page answers 404", answer.status === 404)
  } finally {
    await server.close()
  }
} finally {
  rmSync(site, { recursive: true, force: true })
}
console.log(failures === 0 ? "OK: site_server" : `FAIL: site_server, ${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
