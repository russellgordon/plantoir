// A built site served the way a host serves it, for the rendered check
// (browser-checks/rendered_features.mjs, #597).
//
// What it does that `python3 -m http.server` does not:
//
// * a page's address without `.html` answers with the page, and a folder's
//   with its index.html, as Netlify and Cloudflare Pages both do;
// * every response carries the headers the site's own `_headers` gives its
//   path, read the way Netlify reads that file (a block's path lines, then
//   its indented `Name: value` lines; `*` matches the rest of a path; the
//   path matched lower-cased, as Netlify does, isolation.pathCases). So the
//   policy that keeps Netlify's badge off and the isolation a page with
//   live input gets are both sent, which is how #594 was caught locally;
// * it listens on [::1] only, never 127.0.0.1 or localhost, where
//   GeoGebra's loader takes a path no class site takes (geogebraFences.policy);
// * a sabotaged copy of the site (browser-checks/lib/sabotage.py) can carry
//   `.rendered-sabotage.json`, which this reads once: `types` sends a path
//   with another Content-Type, `hold` answers a path only after so many
//   milliseconds. A file whose name starts with "." or "_" is never served,
//   as on the hosts.
//
// No packages; Node 22.

import { createServer } from "node:http"
import { readFileSync, statSync } from "node:fs"
import { extname, join, normalize, sep } from "node:path"

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8", ".json": "application/json", ".wasm": "application/wasm",
  ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif",
  ".webp": "image/webp", ".ico": "image/x-icon", ".woff2": "font/woff2", ".woff": "font/woff", ".ttf": "font/ttf",
  ".otf": "font/otf", ".xml": "application/xml", ".txt": "text/plain; charset=utf-8", ".pdf": "application/pdf",
  ".zip": "application/zip", ".ggb": "application/vnd.geogebra.file", ".data": "application/octet-stream",
  ".tar": "application/x-tar", ".whl": "application/octet-stream",
}

// `_headers` as blocks: [{ pattern, headers: [[name, value], ...] }].
export function readHeadersFile(siteFolder) {
  let text
  try {
    text = readFileSync(join(siteFolder, "_headers"), "utf-8")
  } catch {
    return []
  }
  const blocks = []
  let current = null
  for (const raw of text.split("\n")) {
    const line = raw.replace(/\r$/, "")
    if (line.trim() === "" || line.trim().startsWith("#")) continue
    if (/^\S/.test(line)) {
      current = { pattern: line.trim(), headers: [] }
      blocks.push(current)
      continue
    }
    const header = /^\s+([^:]+):\s*(.*)$/.exec(line)
    if (header && current !== null) current.headers.push([header[1].trim(), header[2].trim()])
  }
  return blocks
}

function patternMatches(pattern, path) {
  const wanted = pattern.toLowerCase()
  const asked = path.toLowerCase()
  if (!wanted.includes("*")) return wanted === asked || wanted === asked.replace(/\/$/, "")
  const pieces = wanted.split("*").map((piece) => piece.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
  return new RegExp("^" + pieces.join(".*") + "$").test(asked)
}

// The headers a host would send for `path`: every matching block's, in the
// file's order (Netlify sends each; a name given twice is joined with ", ",
// which is how Netlify combines them).
export function headersFor(blocks, path) {
  const found = {}
  for (const block of blocks) {
    if (!patternMatches(block.pattern, path)) continue
    for (const [name, value] of block.headers) {
      found[name] = name in found ? `${found[name]}, ${value}` : value
    }
  }
  return found
}

function fileFor(siteFolder, path) {
  const root = normalize(siteFolder + sep)
  const candidates = []
  if (path.endsWith("/")) {
    candidates.push(path + "index.html")
  } else {
    candidates.push(path, path + ".html", path + "/index.html")
  }
  for (const candidate of candidates) {
    const file = normalize(join(siteFolder, candidate))
    if (!file.startsWith(root)) return null
    try {
      if (statSync(file).isFile()) return file
    } catch {
      // the next candidate
    }
  }
  return null
}

// Starts the server; answers { origin, close, requests } where `requests`
// counts the paths asked for (the cold-visit row reads what was still open).
export async function startSiteServer(siteFolder) {
  const blocks = readHeadersFile(siteFolder)
  let sabotage = { types: {}, hold: {} }
  try {
    sabotage = { types: {}, hold: {}, ...JSON.parse(readFileSync(join(siteFolder, ".rendered-sabotage.json"), "utf-8")) }
  } catch {
    // An ordinary site has none.
  }
  const server = createServer((request, response) => {
    let path
    try {
      path = decodeURIComponent(new URL(request.url, "http://x").pathname)
    } catch {
      response.writeHead(400).end()
      return
    }
    const name = path.split("/").pop() ?? ""
    const file = name.startsWith(".") || name.startsWith("_") ? null : fileFor(siteFolder, path)
    const headers = { "Cache-Control": "no-cache", ...headersFor(blocks, path) }
    const send = () => {
      if (file === null) {
        response.writeHead(404, { ...headers, "Content-Type": "text/plain; charset=utf-8" })
        response.end("not found")
        return
      }
      const servedPath = "/" + file.slice(normalize(siteFolder + sep).length).split(sep).join("/")
      headers["Content-Type"] = sabotage.types[servedPath] ?? TYPES[extname(file).toLowerCase()] ?? "application/octet-stream"
      let body
      try {
        body = readFileSync(file)
      } catch {
        response.writeHead(404, headers).end("not found")
        return
      }
      response.writeHead(200, headers)
      response.end(request.method === "HEAD" ? undefined : body)
    }
    const held = sabotage.hold[path]
    if (typeof held === "number" && held > 0) {
      setTimeout(send, held)
    } else {
      send()
    }
  })
  await new Promise((resolve, reject) => {
    server.once("error", reject)
    server.listen(0, "::1", resolve)
  })
  const origin = `http://[::1]:${server.address().port}`
  return {
    origin,
    close: () => new Promise((resolve) => {
      server.closeAllConnections?.()
      server.close(() => resolve())
    }),
  }
}
