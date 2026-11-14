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
//   a <meta> whose content is defined to be an address, or a <style>'s
//   url(...). Alt text, a link's title, aria-label, a description, any other
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
// A file named only by another file (a teacher's HTML that loads its own
// script), only by a hidden page, or only by a page a published page embeds
// that is itself hidden, is not carried: a student can reach none of them.
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

export function addressesInCss(text: string): string[] {
  const found: string[] = []
  for (const match of String(text).matchAll(CSS_URL)) {
    found.push(match[2].trim())
  }
  return found
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
  const walk = (node: TreeNode, inStyle: boolean) => {
    if (node.type === "text" && inStyle && typeof node.value === "string") {
      found.push(...addressesInCss(node.value))
    }
    const tagName = typeof node.tagName === "string" ? node.tagName : ""
    const properties = node.properties ?? {}
    if (tagName.toLowerCase() === "meta") {
      const named = stringOf(properties.property) ?? stringOf(properties.name)
      const content = stringOf(properties.content)
      if (named !== null && content !== null && metaNames.has(named)) {
        found.push(content)
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

// quartz/plantoir_site_files.json (siteFiles.sideFile). Without `addresses`
// no attribute is read, so every file a page shows is left to the check
// after the build, which puts it back and fails the gates.
export type SideFile = { alwaysCarried?: string[]; footerAddresses?: string[]; addresses?: AddressRules }

// The addresses (Quartz's slugs of content paths) of every file the
// published pages use, among `fileAddresses`.
export function addressesThePagesUse(
  pages: SitePage[],
  fileAddresses: Set<string>,
  side: SideFile,
  slugOf: (contentPath: string) => string,
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
  return used
}
