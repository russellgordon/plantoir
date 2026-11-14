// PhET simulations from a page's own fences (#674): the site's half.
//
// The build (scripts/phet.py) has already read every ```phet fence on the
// pages students can see, made sure this computer has a copy of each
// simulation they name (downloaded from PhET the first time and kept), put
// the copy and its picture in quartz/static/phet/<sim>/, and left what the
// site needs in quartz/plantoir-phet/manifest.json. This only PLACES them,
// in two stages, as plantoirGeoGebra.ts does:
//
// * markdown stage - a fence the manifest knows becomes `<figure
//   class="pl-figure pl-phet">` holding nothing but a figcaption with its
//   description (hidden on screen; what a screen reader reads). An mdast
//   node with data.hName, never a raw html node, so the quiz reader sees a
//   figure, not markup.
// * html stage - the card goes in: the simulation's picture in a box of the
//   simulation's own shape, its title, the teacher's description, the button
//   that opens it (phet.inline.ts makes the frame only then), what a printout
//   says, and the credit line PhET's licence asks for, under every card
//   (phetFences.attribution).
//
// A fence the manifest does not know (a site with no simulation, one that
// cannot be shown, a build that could not prepare them) stays the plain code
// block it always was: the byte-identical guarantee for sites without
// simulations rests on this.
//
// The frame's address is `<root>/static/phet/<sim>/?` and the build's query,
// which always starts yotta=false&allowLinks=false (phetFences.address): the
// root is pathToRoot of the page, so it holds under a site served from a
// sub-path too.

import { Root as MdRoot, Code } from "mdast"
import { Element, Root as HtmlRoot, ElementContent } from "hast"
import { visit } from "unist-util-visit"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { FullSlug, pathToRoot } from "../../util/path"
// @ts-ignore - plain JavaScript, shared with the figures transformer
import { keyOf } from "./figureRules.js"

type Entry = {
  ok: boolean
  sim: string
  title: string
  alt: string
  locale: string
  query: string
  folder: string
  picture: { path: string; width: number | null; height: number | null } | null
  size: string
  version: string
}
type Manifest = {
  words: Record<string, string>
  attribution: Record<string, string>
  // By page (its path in the site's content, NFC), then by fence key.
  pages: Record<string, Record<string, Entry>>
}

const WORKSPACE = join("quartz", "plantoir-phet")
const LANGUAGE = "phet"
// The shape a PhET simulation lays itself out in (its layout bounds,
// 1024 by 618): the frame takes it at the page's width, so the simulation
// is never cropped and its logo stays in view (the licence's brand rule).
const LAYOUT_RATIO = "1024 / 618"

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

function simulationsOf(known: Manifest, file: { data: { relativePath?: unknown } }): Record<string, Entry> | null {
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

// PhET's own sentence, word for word (phetFences.attribution.sentence),
// with its licence name and its address made links. On paper it prints as
// the same sentence, the address in it.
function attribution(links: Record<string, string>): Element {
  const sentence = links.sentence
  const children: ElementContent[] = []
  const licenceAt = sentence.indexOf(links.licenceName)
  const siteAt = sentence.indexOf(links.siteUrl)
  if (licenceAt < 0 || siteAt < 0 || siteAt < licenceAt) {
    children.push(text(sentence))
  } else {
    children.push(text(sentence.slice(0, licenceAt)))
    children.push(element("a", { href: links.licenceUrl, rel: ["license"] }, [text(links.licenceName)]))
    children.push(text(sentence.slice(licenceAt + links.licenceName.length, siteAt)))
    children.push(element("a", { href: links.siteUrl }, [text(links.siteUrl)]))
    children.push(text(sentence.slice(siteAt + links.siteUrl.length)))
  }
  return element("p", { className: ["pl-phet-attribution"] }, children)
}

export const PlantoirPhet: QuartzTransformerPlugin = () => ({
  name: "PlantoirPhet",
  markdownPlugins() {
    return [
      () => (tree: MdRoot, file) => {
        const known = manifest()
        const simulations = known === null ? null : simulationsOf(known, file)
        if (simulations === null) {
          return
        }
        visit(tree, "code", (node: Code, index, parent) => {
          if ((node.lang ?? "") !== LANGUAGE || parent === undefined || index === undefined) {
            return
          }
          const key: string = keyOf(node.value)
          const entry = simulations[key]
          if (entry === undefined || !entry.ok) {
            return
          }
          parent.children[index] = {
            type: "plantoirPhet",
            data: {
              hName: "figure",
              hProperties: { className: ["pl-figure", "pl-phet"], dataPhetKey: key, dataPhetSim: entry.sim },
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
        const simulations = known === null ? null : simulationsOf(known, file)
        if (known === null || simulations === null) {
          return
        }
        const words = known.words
        const root = pathToRoot(file.data.slug as FullSlug)
        visit(tree, "element", (node: Element) => {
          if (node.tagName !== "figure" || !classesOf(node).includes("pl-phet")) {
            return
          }
          const key = String(node.properties?.dataPhetKey ?? "")
          const entry = simulations[key]
          if (entry === undefined) {
            return
          }
          node.properties.dataPhet = JSON.stringify({
            sim: entry.sim,
            url: `${root}/${entry.folder}?${entry.query}`,
            title: entry.alt,
            loading: words.loading,
            loadingFirstTime: words.loadingFirstTime,
            couldNotLoad: words.couldNotLoad,
          })
          node.properties.style = `--pl-phet-ratio: ${LAYOUT_RATIO}`
          const stage: ElementContent[] = []
          if (entry.picture !== null) {
            const picture: Record<string, unknown> = {
              className: ["pl-phet-picture"],
              src: `${root}/${entry.picture.path}`,
              alt: "",
              loading: "lazy",
              decoding: "async",
            }
            if (entry.picture.width && entry.picture.height) {
              picture.width = entry.picture.width
              picture.height = entry.picture.height
            }
            stage.push(element("img", picture, []))
          }
          // Where the card says the simulation is on its way (#756's
          // lesson): empty until a tap, said once, inside the box tapped.
          stage.push(element("div", { className: ["pl-phet-loading"], role: "status", ariaLive: "polite" }, []))
          const children: ElementContent[] = [
            element("div", { className: ["pl-phet-stage"] }, stage),
            element("div", { className: ["pl-phet-card"] }, [
              element("p", { className: ["pl-phet-title"] }, [text(entry.title)]),
              element("p", { className: ["pl-phet-description"] }, [text(entry.alt)]),
              element("button", { type: "button", className: ["pl-phet-open"] }, [
                text(filled(words.open, { size: entry.size })),
              ]),
            ]),
            element("p", { className: ["pl-phet-message"], role: "status", hidden: true }, []),
            element("p", { className: ["pl-phet-print-note"] }, [text(words.printNote)]),
            attribution(known.attribution),
          ]
          const caption = node.children.find(
            (child) => child.type === "element" && child.tagName === "figcaption",
          ) as Element | undefined
          node.children = caption !== undefined ? [...children, caption] : children
        })
      },
    ]
  },
})
