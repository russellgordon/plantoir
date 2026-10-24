// GeoGebra sketches from a page's own fences (#578): the site's half.
//
// The build (scripts/geogebra.py) has already read every ```geogebra fence
// on the pages students can see, found and checked each sketch's file, and
// left what the site needs in quartz/plantoir-geogebra/manifest.json (and
// each sketch's thumbnail in quartz/static/geogebra-sketches/). This only
// PLACES them, in two stages, as plantoirFigures.ts does:
//
// * markdown stage - a fence the manifest knows becomes `<figure
//   class="pl-figure pl-geogebra">` holding nothing but a figcaption with its
//   description (hidden on screen; what a screen reader reads). Built as an
//   mdast node with data.hName, never a raw html node (plan section 3.6:
//   the quiz reader must see a figure, not markup). Description, listed
//   before this plugin, therefore reads the description and never the
//   sketch's commands.
// * html stage - the card goes in: the sketch's thumbnail, its caption, the
//   button that opens it (geogebra.inline.ts loads the engine only then),
//   the commands in a <details> for a reader without scripts, and the
//   attribution GeoGebra's licence asks for, on screen and in its print form.
//
// A fence the manifest does not know (a site with no sketch, a sketch that
// cannot be shown, a build that could not prepare them) stays the plain code
// block it always was - the byte-identical guarantee for sites without
// sketches rests on this.
//
// The sketch's FILE is published once, by Quartz's own Assets emitter, which
// copies every file under content/ that is not a page to slugifyFilePath of
// its path. The address is made here with that same function, so the two
// cannot disagree (geogebraFences.files).

import { Root as MdRoot, Code } from "mdast"
import { Element, Root as HtmlRoot, ElementContent } from "hast"
import { visit } from "unist-util-visit"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { FilePath, FullSlug, pathToRoot, slugifyFilePath } from "../../util/path"
// @ts-ignore - plain JavaScript, shared with the figures transformer
import { keyOf } from "./figureRules.js"

type Command = { line: number; text: string }
type Entry = {
  ok: boolean
  app: string
  width: number
  height: number
  alt: string
  caption?: string | null
  commands: Command[]
  toolbar: boolean
  algebra: boolean
  // A teacher's file is published by Quartz from content/ (contentPath); a
  // geogebra.org sketch has no file there, so the build wrote the site's
  // copy into static/ (storePath, from the top of the site).
  source: { kind: string; contentPath?: string; storePath?: string } | null
  thumbnail: { name: string; width: number; height: number } | null
  attribution: { kind: string; author?: string; id?: string }
  size: string
}
type Manifest = {
  words: Record<string, string>
  // The command run after each of the fence's lines (geogebraFences.commands).
  endOfLine: string
  attribution: Record<string, string>
  // By page (its path in the site's content, NFC), then by fence key:
  // the same fence on two pages can name two different files beside them.
  pages: Record<string, Record<string, Entry>>
}

const WORKSPACE = join("quartz", "plantoir-geogebra")
const LANGUAGE = "geogebra"

let cached: { stamp: number; manifest: Manifest | null } | null = null

function manifest(): Manifest | null {
  const path = join(process.cwd(), WORKSPACE, "manifest.json")
  let stamp = -1
  try {
    stamp = statSync(path).mtimeMs
  } catch {
    cached = null
    return null
  }
  if (cached === null || cached.stamp !== stamp) {
    try {
      cached = { stamp, manifest: JSON.parse(readFileSync(path, "utf-8")) as Manifest }
    } catch {
      cached = { stamp, manifest: null }
    }
  }
  return cached.manifest
}

// This page's sketches, by fence key, or null.
function sketchesOf(known: Manifest, file: { data: { relativePath?: unknown } }): Record<string, Entry> | null {
  const page = String(file.data.relativePath ?? "").normalize("NFC")
  return known.pages?.[page] ?? null
}

function text(value: string): ElementContent {
  return { type: "text", value }
}

function element(tagName: string, properties: Record<string, unknown>, children: ElementContent[]): Element {
  return { type: "element", tagName, properties: properties as Element["properties"], children }
}

function classesOf(node: Element): string[] {
  const value = node.properties?.className
  if (Array.isArray(value)) {
    return value.map((item) => String(item))
  }
  return typeof value === "string" ? value.split(/\s+/) : []
}

function filled(template: string, values: Record<string, string>): string {
  return template.replace(/\{([A-Za-z]+)\}/g, (whole, name) => (name in values ? values[name] : whole))
}

// The attribution GeoGebra's licence asks for (geogebraFences.attribution):
// on screen, linked; on paper, one line with the addresses as plain text.
function attribution(entry: Entry, words: Record<string, string>, links: Record<string, string>): ElementContent[] {
  const screen: ElementContent[] = [element("a", { href: links.engineUrl }, [text(words.madeWith)])]
  const printed: ElementContent[] = []
  const addresses: string[] = [links.engineUrl]
  if (entry.attribution.kind === "material" && entry.attribution.author && entry.attribution.id) {
    const sketchUrl = links.materialUrl.replace("{id}", entry.attribution.id)
    screen.push(
      text(" · "),
      element("a", { href: sketchUrl }, [text(filled(words.createdBy, { author: entry.attribution.author }))]),
      text(" · "),
      element("a", { href: links.licenceUrl, rel: ["license"] }, [text(words.licenceName)]),
    )
    printed.push(text(filled(words.printAttributionMaterial, { author: entry.attribution.author })))
    addresses.push(sketchUrl, links.licenceUrl)
  } else {
    printed.push(text(words.printAttributionFile))
  }
  return [
    element("p", { className: ["pl-geogebra-attribution"] }, screen),
    element("p", { className: ["pl-geogebra-print-attribution"] }, [
      ...printed,
      element("span", { className: ["pl-geogebra-print-addresses"] }, [text(addresses.join("  "))]),
    ]),
  ]
}

export const PlantoirGeoGebra: QuartzTransformerPlugin = () => ({
  name: "PlantoirGeoGebra",
  markdownPlugins() {
    return [
      () => (tree: MdRoot, file) => {
        const known = manifest()
        const sketches = known === null ? null : sketchesOf(known, file)
        if (sketches === null) {
          return
        }
        visit(tree, "code", (node: Code, index, parent) => {
          if ((node.lang ?? "") !== LANGUAGE || parent === undefined || index === undefined) {
            return
          }
          const key: string = keyOf(node.value)
          const entry = sketches[key]
          if (entry === undefined || !entry.ok) {
            return
          }
          parent.children[index] = {
            type: "plantoirGeoGebra",
            data: {
              hName: "figure",
              hProperties: { className: ["pl-figure", "pl-geogebra"], dataGeogebraKey: key },
              hChildren: [element("figcaption", { className: ["pl-sr-only"] }, [text(entry.alt)])],
            },
          } as unknown as Code
        })
      },
    ]
  },
  htmlPlugins() {
    return [
      () => (tree: HtmlRoot, file) => {
        const known = manifest()
        const sketches = known === null ? null : sketchesOf(known, file)
        if (known === null || sketches === null) {
          return
        }
        const words = known.words
        const root = pathToRoot(file.data.slug as FullSlug)
        visit(tree, "element", (node: Element) => {
          if (node.tagName !== "figure" || !classesOf(node).includes("pl-geogebra")) {
            return
          }
          const key = String(node.properties?.dataGeogebraKey ?? "")
          const entry = sketches[key]
          if (entry === undefined) {
            return
          }
          let sketch: string | null = null
          if (entry.source !== null && entry.source.kind === "file" && entry.source.contentPath) {
            sketch = slugifyFilePath(entry.source.contentPath as FilePath)
          } else if (entry.source !== null && entry.source.kind === "material" && entry.source.storePath) {
            sketch = entry.source.storePath
          }
          node.properties.dataGeogebra = JSON.stringify({
            sketch,
            app: entry.app,
            width: entry.width,
            height: entry.height,
            commands: entry.commands,
            toolbar: entry.toolbar,
            algebra: entry.algebra,
            root,
            loading: words.loading,
            couldNotLoad: words.couldNotLoad,
            lineCouldNotRun: words.lineCouldNotRun,
            endOfLine: known.endOfLine,
          })
          node.properties.style = `--pl-geogebra-width: ${entry.width}px; --pl-geogebra-ratio: ${entry.width} / ${entry.height}`

          const card: ElementContent[] = []
          if (entry.thumbnail !== null) {
            card.push(
              element(
                "img",
                {
                  className: ["pl-geogebra-thumbnail"],
                  src: `${root}/static/geogebra-sketches/${entry.thumbnail.name}`,
                  alt: "",
                  width: entry.thumbnail.width,
                  height: entry.thumbnail.height,
                  loading: "lazy",
                  decoding: "async",
                },
                [],
              ),
            )
          }
          card.push(
            element("button", { type: "button", className: ["pl-geogebra-open"] }, [
              text(filled(words.openSketch, { size: entry.size })),
            ]),
          )
          const children: ElementContent[] = [
            element("div", { className: ["pl-geogebra-card"] }, card),
            element("div", { className: ["pl-geogebra-applet"], hidden: true }, []),
            element("p", { className: ["pl-geogebra-message"], role: "status", hidden: true }, []),
          ]
          // A caption, when the fence gives one, under the sketch; the
          // description stays the figcaption, what a screen reader reads.
          if (entry.caption) {
            children.push(element("p", { className: ["pl-geogebra-caption"] }, [text(entry.caption)]))
          }
          if (entry.commands.length > 0) {
            const lines = entry.commands.map((command) => command.text).join("\n")
            children.push(
              element("details", { className: ["pl-geogebra-commands"] }, [
                element("summary", {}, [text(words.commandsSummary)]),
                element("pre", {}, [element("code", {}, [text(lines)])]),
              ]),
            )
          }
          children.push(element("p", { className: ["pl-geogebra-print-note"] }, [text(words.printNote)]))
          children.push(...attribution(entry, words, known.attribution))
          const caption = node.children.find(
            (child) => child.type === "element" && child.tagName === "figcaption",
          ) as Element | undefined
          node.children = caption !== undefined ? [...children, caption] : children
        })
      },
    ]
  },
})
