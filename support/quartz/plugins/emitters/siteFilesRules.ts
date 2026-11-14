// Which of a course's files a published page uses (#901): the rules the
// site's emitter (plantoirAssets.ts) applies, kept apart from Quartz so they
// can be run on their own (contracts/shared-rules.json -> siteFiles, run by
// scripts/check_site_files_rules_against_the_site.py in the image).
//
// A file goes on the site when a page students can see names it:
//
// * in the page's tree as Quartz built it (after CrawlLinks, so a wikilink
//   resolves the way Quartz resolved it), in a place that HOLDS AN ADDRESS:
//   one of the attributes in siteFiles.addresses on one of its elements
//   (src, href, srcset, poster, an object's data, SVG's href, a style's
//   url(...), a GeoGebra sketch's data-geogebra, read from its own `root`),
//   a <meta> whose content is defined to be an address, a refresh's
//   address, or an address in a <style>'s CSS (url(...), @import, image-set).
//   Alt text, a link's title, aria-label, a description, any other
//   attribute, text and code are never addresses: a page that only MENTIONS
//   a file's name does not use it. The list is the contract's, handed in
//   through the build's side file (sideFile.keys.addresses), so this file
//   and scripts/site_files.py follow one list;
// * through what Plantoir draws outside the tree: the Print button's PDF
//   (printPdfPath, shared with PlantoirMetaLine.tsx so the two cannot
//   disagree), a file a transformer declares (file.data.plantoirFiles) and
//   the footer (its addresses, from the side file, resolved from every page
//   as the page's own are);
// * or it is always carried (the site's root favicon.ico, written into
//   content/ by the build).
//
// A file a CARRIED file loads is carried too (siteFiles.followed, 901a fix
// review I1): a carried HTML, SVG or CSS file (a teacher's own page shown in
// a frame, a stylesheet a page links) is read at the same places, from its
// own address, transitively, breadth first with a visited set, and only a
// course file is followed. Past siteFiles.followed.limits it throws
// FollowLimitReached rather than stop quietly. JavaScript is never read
// (siteFiles.knownLimits).
//
// A file named only by a hidden page, or only by a page a published page
// embeds that is itself hidden, is not carried: a student can reach neither.
//
// No imports, so `node --experimental-strip-types` runs this file alone; the
// emitter hands in Quartz's own slugifyFilePath.

export type TreeNode = {
  type?: string
  tagName?: string
  value?: string
  properties?: Record<string, unknown>
  children?: TreeNode[]
}

const BASE = "https://site.invalid/"
const SCHEME = /^[A-Za-z][A-Za-z0-9+.-]*:/
const CSS_URL = /url\(\s*(['"]?)([\s\S]*?)\1\s*\)/gi
// CSS's other two places that hold an address as a plain string (901a fix
// review, I2): `@import "x.css"` and the strings inside image-set(...).
// scripts/site_files.py has the same three, letter for letter.
const CSS_IMPORT = /@import\s+(['"])([\s\S]*?)\1/gi
const IMAGE_SET = /image-set\(/gi
// A refresh: the time, a separator, an optional url=, then the address.
const REFRESH = /^\s*[0-9.]+\s*[;,]?\s*(?:url\s*=\s*)?([\s\S]*)$/i

// The publish filter's own rule (patches/publish.ts). On a rebuild Quartz
// hands emitters every page, hidden ones included, so the emitter checks.
export function isHiddenPage(frontmatter: Record<string, unknown> | undefined): boolean {
  const flag = frontmatter?.publish
  return flag === false || flag === "false"
}

// The content path of a page's own PDF (#454), or null: what the Print button
// links to. PlantoirMetaLine.tsx slugifies the same path for its href.
export function printPdfPath(frontmatter: Record<string, unknown> | undefined): string | null {
  const pdf = frontmatter?.printPdf
  if (typeof pdf !== "string" || pdf.trim() === "") {
    return null
  }
  return "Media/" + pdf.trim()
}

// Every address a piece of CSS holds (siteFiles.addresses.reads.css): each
// url(...), each string after @import, and each string directly inside an
// image-set(...) or -webkit-image-set(...).
export function addressesInCss(text: string): string[] {
  const css = String(text ?? "")
  const found: string[] = []
  for (const match of css.matchAll(CSS_URL)) {
    found.push(match[2].trim())
  }
  for (const match of css.matchAll(CSS_IMPORT)) {
    found.push(match[2].trim())
  }
  for (const item of stringsInImageSets(css)) {
    found.push(item)
  }
  return found
}

// The quoted strings at the first level of each image-set(...). A url(...)
// inside it is read by CSS_URL, and a type("...") is one level deeper, so
// neither is taken here.
function stringsInImageSets(text: string): string[] {
  const found: string[] = []
  for (const match of text.matchAll(IMAGE_SET)) {
    let depth = 1
    let position = (match.index ?? 0) + match[0].length
    while (position < text.length && depth > 0) {
      const character = text[position]
      if (character === "'" || character === '"') {
        const closing = text.indexOf(character, position + 1)
        if (closing < 0) {
          break
        }
        if (depth === 1) {
          found.push(text.slice(position + 1, closing).trim())
        }
        position = closing + 1
        continue
      }
      if (character === "(") {
        depth += 1
      } else if (character === ")") {
        depth -= 1
      }
      position += 1
    }
  }
  return found
}

// The address in a refresh meta tag's content (addresses.reads.refresh), or null.
export function refreshAddress(content: string): string | null {
  const match = REFRESH.exec(String(content ?? ""))
  if (match === null) {
    return null
  }
  let rest = match[1].trim()
  if (rest.startsWith("'") || rest.startsWith('"')) {
    const closing = rest.indexOf(rest[0], 1)
    rest = closing >= 0 ? rest.slice(1, closing) : rest.slice(1)
  }
  rest = rest.trim()
  return rest === "" ? null : rest
}

// `<root>/<sketch>` from a data-geogebra JSON, or null.
export function geogebraSketchAddress(value: string): string | null {
  let data: unknown
  try {
    data = JSON.parse(value)
  } catch {
    return null
  }
  if (data === null || typeof data !== "object") {
    return null
  }
  const sketch = (data as Record<string, unknown>).sketch
  let root = (data as Record<string, unknown>).root
  if (typeof sketch !== "string" || sketch === "") {
    return null
  }
  if (typeof root !== "string" || root === "") {
    root = "."
  }
  return String(root).replace(/\/+$/, "") + "/" + sketch
}

// siteFiles.addresses.attributes: an attribute that holds an address, the
// elements it holds one on, and how its value is read.
export type AddressAttribute = {
  attribute: string
  property: string
  elements: string[]
  read: string
}

// siteFiles.addresses, as the side file carries it.
export type AddressRules = {
  attributes?: AddressAttribute[]
  metaContent?: string[]
  metaHttpEquiv?: string[]
}

function ruleFor(rules: AddressRules, tagName: string, name: string): AddressAttribute | null {
  const tag = tagName.toLowerCase()
  const lower = name.toLowerCase()
  for (const rule of rules.attributes ?? []) {
    if (rule.property !== name && rule.attribute !== lower) {
      continue
    }
    if (rule.elements.includes("*") || rule.elements.includes(tag)) {
      return rule
    }
  }
  return null
}

function jsonUrl(value: string): string | null {
  try {
    const data = JSON.parse(value) as Record<string, unknown> | null
    if (data !== null && typeof data === "object" && typeof data.url === "string") {
      return data.url
    }
  } catch {
    // Not JSON: no address.
  }
  return null
}

// The addresses one attribute's value holds, read as its rule says
// (siteFiles.addresses.reads).
function addressesInValue(read: string, value: string, into: string[]): void {
  if (read === "css") {
    into.push(...addressesInCss(value))
  } else if (read === "geogebraSketch") {
    const sketch = geogebraSketchAddress(value)
    if (sketch !== null) {
      into.push(sketch)
    }
  } else if (read === "jsonUrl") {
    const url = jsonUrl(value)
    if (url !== null) {
      into.push(url)
    }
  } else if (read === "fromSiteRoot") {
    if (value.trim() !== "") {
      into.push("/" + value.trim().replace(/^\/+/, ""))
    }
  } else if (read === "srcset") {
    for (const item of value.split(",")) {
      const first = item.trim().split(/\s+/)[0]
      if (first) {
        into.push(first)
      }
    }
  } else if (read === "address") {
    into.push(value)
  }
}

function stringOf(value: unknown): string | null {
  if (typeof value === "string") {
    return value
  }
  if (Array.isArray(value)) {
    const parts: string[] = []
    for (const item of value) {
      if (typeof item === "string" || typeof item === "number") {
        parts.push(String(item))
      }
    }
    return parts.join(",")
  }
  return null
}

// Every address the tree holds, in the order met: only the places
// siteFiles.addresses names.
export function addressesInTree(tree: TreeNode, rules: AddressRules): string[] {
  const found: string[] = []
  const metaNames = new Set(rules.metaContent ?? [])
  const metaHttpEquiv = new Set<string>()
  for (const kind of rules.metaHttpEquiv ?? []) {
    metaHttpEquiv.add(kind.toLowerCase())
  }
  const walk = (node: TreeNode, inStyle: boolean) => {
    if (node.type === "text" && inStyle && typeof node.value === "string") {
      found.push(...addressesInCss(node.value))
    }
    const tagName = typeof node.tagName === "string" ? node.tagName : ""
    const properties = node.properties ?? {}
    if (tagName.toLowerCase() === "meta") {
      // `property` is read before `name` when a <meta> has both, in both
      // readers (siteFiles.addresses.metaRule).
      const named = stringOf(properties.property) ?? stringOf(properties.name)
      const content = stringOf(properties.content)
      if (named !== null && content !== null && metaNames.has(named)) {
        found.push(content)
      }
      const httpEquiv = stringOf(properties.httpEquiv)
      if (httpEquiv !== null && content !== null && metaHttpEquiv.has(httpEquiv.trim().toLowerCase())) {
        const refreshed = refreshAddress(content)
        if (refreshed !== null) {
          found.push(refreshed)
        }
      }
    }
    if (node.type === "element") {
      for (const [name, value] of Object.entries(properties)) {
        const rule = ruleFor(rules, tagName, name)
        if (rule === null) {
          continue
        }
        if (Array.isArray(value) && rule.read !== "srcset") {
          for (const item of value) {
            if (typeof item === "string") {
              addressesInValue(rule.read, item, found)
            }
          }
          continue
        }
        const text = stringOf(value)
        if (text !== null) {
          addressesInValue(rule.read, text, found)
        }
      }
    }
    const style = inStyle || tagName === "style"
    for (const child of node.children ?? []) {
      walk(child, style)
    }
  }
  walk(tree, false)
  return found
}

// The address below the site's root that `address`, written on the page at
// `pageSlug`, asks a browser for: decoded, no query or fragment, no leading
// slash. null for another site's address, an anchor, or nothing.
export function resolvedFromPage(pageSlug: string, address: string): string | null {
  const value = String(address ?? "").trim()
  if (value === "" || value.startsWith("#") || value.startsWith("//") || SCHEME.test(value)) {
    return null
  }
  let url: URL
  try {
    url = new URL(value, BASE + pageSlug)
  } catch {
    return null
  }
  if (url.origin !== "https://site.invalid") {
    return null
  }
  let path: string
  try {
    path = decodeURIComponent(url.pathname)
  } catch {
    return null
  }
  return path.replace(/^\/+/, "")
}

export type SitePage = {
  slug: string
  tree: TreeNode
  frontmatter?: Record<string, unknown>
  // Content paths a transformer recorded on file.data.plantoirFiles.
  declared?: string[]
}

// siteFiles.followed, as the side file carries it.
export type Followed = {
  kinds?: Record<string, string>
  limits?: { depth?: number; files?: number }
  limitReached?: string
}

// quartz/plantoir_site_files.json (siteFiles.sideFile). Without `addresses`
// no attribute is read, and without `followed` no carried file is read, so
// every file a page uses is left to the check after the build, which puts
// it back and fails the gates.
export type SideFile = {
  alwaysCarried?: string[]
  footerAddresses?: string[]
  addresses?: AddressRules
  followed?: Followed
}

// How the emitter hands a carried file to the rules: its content path (null
// for no course file), its text (null when it cannot be read; asked only of
// a file of a followed kind, so no picture is ever read), and Quartz's own
// HTML parser, so this file needs no import.
export type CarriedFiles = {
  contentPathOf: (address: string) => string | null
  textOf: (address: string) => string | null
  parseHtml: (text: string) => TreeNode
}

// Thrown when more carried files load one another than followed.limits
// allows. The emitter carries every file then, and says so.
export class FollowLimitReached extends Error {
  constructor(message: string) {
    super(message)
    this.name = "FollowLimitReached"
  }
}

// "html", "css" or null, by the content path's ending, lower-cased
// (siteFiles.followed.kinds).
export function kindOfCarriedFile(contentPath: string, followed: Followed | undefined): string | null {
  const lower = contentPath.toLowerCase()
  for (const [ending, kind] of Object.entries(followed?.kinds ?? {})) {
    if (lower.endsWith(ending)) {
      return kind
    }
  }
  return null
}

// `used`, with every course file a carried HTML, SVG or CSS file loads,
// transitively: each is read at the same places as a page, its addresses
// resolved from its OWN address, and only a course file is followed.
// scripts/site_files.follow_carried_files is the same walk.
export function followCarriedFiles(
  used: Set<string>,
  fileAddresses: Set<string>,
  side: SideFile,
  carried: CarriedFiles,
): Set<string> {
  const followed = side.followed
  const depthLimit = Number(followed?.limits?.depth ?? 16)
  const filesLimit = Number(followed?.limits?.files ?? 10000)
  const result = new Set<string>(used)
  const queue: Array<[string, number]> = []
  for (const address of [...used].sort()) {
    queue.push([address, 0])
  }
  const visited = new Set<string>()
  let read = 0
  let position = 0
  while (position < queue.length) {
    const [address, depth] = queue[position]
    position += 1
    if (visited.has(address)) {
      continue
    }
    visited.add(address)
    if (!fileAddresses.has(address)) {
      continue
    }
    const contentPath = carried.contentPathOf(address)
    if (contentPath === null) {
      continue
    }
    const kind = kindOfCarriedFile(contentPath, followed)
    if (kind === null) {
      continue
    }
    if (depth >= depthLimit || read >= filesLimit) {
      throw new FollowLimitReached(String(followed?.limitReached ?? "too many files load one another"))
    }
    read += 1
    const text = carried.textOf(address)
    if (text === null) {
      continue
    }
    const found = kind === "html" ? addressesInTree(carried.parseHtml(text), side.addresses ?? {}) : addressesInCss(text)
    for (const candidate of found) {
      const target = resolvedFromPage(address, candidate)
      if (target === null || !fileAddresses.has(target)) {
        continue
      }
      result.add(target)
      if (!visited.has(target)) {
        queue.push([target, depth + 1])
      }
    }
  }
  return result
}

// The addresses (Quartz's slugs of content paths) of every file the
// published pages use, among `fileAddresses`, and, given `carried`, every
// file those load in turn (followCarriedFiles).
export function addressesThePagesUse(
  pages: SitePage[],
  fileAddresses: Set<string>,
  side: SideFile,
  slugOf: (contentPath: string) => string,
  carried?: CarriedFiles,
): Set<string> {
  const used = new Set<string>()
  const footer = side.footerAddresses ?? []
  for (const page of pages) {
    if (isHiddenPage(page.frontmatter)) {
      continue
    }
    const candidates = addressesInTree(page.tree, side.addresses ?? {})
    for (const address of footer) {
      candidates.push(address)
    }
    for (const candidate of candidates) {
      const target = resolvedFromPage(page.slug, candidate)
      if (target !== null && fileAddresses.has(target)) {
        used.add(target)
      }
    }
    const pdf = printPdfPath(page.frontmatter)
    if (pdf !== null) {
      const target = slugOf(pdf)
      if (fileAddresses.has(target)) {
        used.add(target)
      }
    }
    for (const declared of page.declared ?? []) {
      const target = slugOf(declared)
      if (fileAddresses.has(target)) {
        used.add(target)
      }
    }
  }
  for (const name of side.alwaysCarried ?? []) {
    const target = slugOf(name)
    if (fileAddresses.has(target)) {
      used.add(target)
    }
  }
  if (carried === undefined) {
    return used
  }
  return followCarriedFiles(used, fileAddresses, side, carried)
}
