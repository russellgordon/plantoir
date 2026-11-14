// Which of a course's files a published page uses (#901): the rules the
// site's emitter (plantoirAssets.ts) applies, kept apart from Quartz so they
// can be run on their own (contracts/shared-rules.json -> siteFiles, run by
// scripts/check_site_files_rules_against_the_site.py in the image).
//
// A file goes on the site when a page students can see names it:
//
// * anywhere in the page's tree as Quartz built it (after CrawlLinks, so a
//   wikilink resolves the way Quartz resolved it): EVERY string a property
//   holds is tried as an address from the page, not only the four Quartz
//   rewrites, so raw HTML's <source src>, srcset, poster, <object data>,
//   <embed src>, SVG's href, a style's url(...) and a <style>'s url(...)
//   all count; a GeoGebra sketch's data-geogebra names its file from its own
//   `root`, and its transformer also declares it (file.data.plantoirFiles);
// * through what Plantoir draws outside the tree: the Print button's PDF
//   (printPdfPath, shared with PlantoirMetaLine.tsx so the two cannot
//   disagree) and the footer (its addresses, from the build's side file,
//   resolved from every page as the page's own are);
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

function addressesInValue(name: string, value: string, into: string[]): void {
  const lower = name.toLowerCase()
  if (lower === "style") {
    into.push(...addressesInCss(value))
    return
  }
  if (lower === "datageogebra" || lower === "data-geogebra") {
    const sketch = geogebraSketchAddress(value)
    if (sketch !== null) {
      into.push(sketch)
    }
    return
  }
  if (lower === "srcset" || lower === "imagesrcset") {
    for (const item of value.split(",")) {
      const first = item.trim().split(/\s+/)[0]
      if (first) {
        into.push(first)
      }
    }
    return
  }
  into.push(value)
  const pieces = value.trim().split(/\s+/)
  if (pieces.length > 1) {
    into.push(pieces[0])
  }
}

// Every string in the tree that may be an address, in the order met.
export function addressesInTree(tree: TreeNode): string[] {
  const found: string[] = []
  const walk = (node: TreeNode, inStyle: boolean) => {
    if (node.type === "text" && inStyle && typeof node.value === "string") {
      found.push(...addressesInCss(node.value))
    }
    if (node.type === "raw" && typeof node.value === "string") {
      // Left by an html node no rehype-raw read: never the case with
      // ObsidianFlavoredMarkdown, which reads raw HTML first.
      found.push(...addressesInCss(node.value))
    }
    const properties = node.properties ?? {}
    for (const [name, value] of Object.entries(properties)) {
      if (typeof value === "string") {
        addressesInValue(name, value, found)
      } else if (Array.isArray(value)) {
        if (name.toLowerCase() === "srcset" || name.toLowerCase() === "imagesrcset") {
          addressesInValue(name, value.join(","), found)
          continue
        }
        for (const item of value) {
          if (typeof item === "string") {
            addressesInValue(name, item, found)
          }
        }
      }
    }
    const style = inStyle || node.tagName === "style"
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

export type SideFile = { alwaysCarried?: string[]; footerAddresses?: string[] }

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
    const candidates = addressesInTree(page.tree)
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
