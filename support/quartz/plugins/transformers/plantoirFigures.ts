// Diagrams and graphs from a page's own fences (#485 E1): the site's half.
//
// The build (scripts/figures.py) has already drawn every ```tikz on the pages
// students can see and checked every ```functionplot, and left the results in
// quartz/plantoir-figures/ (manifest.json and one <key>.svg per drawing). This
// only PLACES them, in two stages:
//
// * markdown stage - a figure fence becomes `<figure class="pl-figure
//   pl-<engine>">` holding nothing but a figcaption with its description
//   (hidden on screen; what a screen reader reads). Nothing else yet, so that
// * Description (listed BEFORE this plugin in quartz.config.ts) reads the
//   description and never the drawing's lettering, which is hundreds of
//   single glyphs (measured: a page's summary and search card filled with
//   "A B C 3 4 . 5"), and then
// * html stage - the drawing goes in: the TikZ SVG, inline, so it takes the
//   page's colours; or, for a graph, the box function-plot draws into (in the
//   reader's browser: figures.inline.ts) and the graph's text, shown until it
//   is drawn.
//
// No manifest (a site with no figures, or a build that could not prepare
// them) means every fence stays the plain code block it always was - the
// byte-identical guarantee for sites without figures rests on this.
//
// The words come from the manifest, which the build writes from the contract
// (contracts/shared-rules.json -> figureFences.words.site).

import { Root as MdRoot, Code } from "mdast"
import { Element, Root as HtmlRoot, ElementContent } from "hast"
import { visit } from "unist-util-visit"
import { fromHtml } from "hast-util-from-html"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { FullSlug, pathToRoot } from "../../util/path"
// @ts-ignore - plain JavaScript, shared with support/figures/plantoir-figures.mjs
import { ENGINES, keyOf, altOf } from "./figureRules.js"

type Entry = { ok: boolean; alt?: string; svg?: string; plot?: Record<string, unknown> }
type Manifest = {
  words: Record<string, string>
  figures: Record<string, Record<string, Entry>>
}

const WORKSPACE = join("quartz", "plantoir-figures")

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

// The second and later copies of the SAME drawing on a page get their ids
// renamed: the engine names ids after the drawing, so two copies would share
// a clip path, and the first, folded away in a callout, would take the
// second's with it (review N5).
function withOwnIds(svg: string, copy: number): string {
  if (copy <= 1) {
    return svg
  }
  let result = svg
  const ids = new Set<string>()
  for (const match of svg.matchAll(/\bid="([^"]+)"/g)) {
    ids.add(match[1])
  }
  const ordered = [...ids].sort((one, other) => other.length - one.length)
  for (const id of ordered) {
    const renamed = `${id}-pl${copy}`
    result = result
      .split(`id="${id}"`).join(`id="${renamed}"`)
      .split(`#${id})`).join(`#${renamed})`)
      .split(`#${id}"`).join(`#${renamed}"`)
  }
  return result
}

// Quartz colours EVERY svg <text> with the page's grey (base.scss: `text {
// color; fill: var(--darkgray) }`), which beats an SVG's own fill attribute -
// so a TikZ label drawn red came out grey, and on paper black lettering came
// out #4e4e4e (measured in the handout). Each label's own colour, worked out
// from its ancestors as SVG inherits it, is therefore written as an inline
// style; black (and none) is left to figures.scss, which follows the theme,
// and white becomes the page's background colour, as for shapes.
const BLACK = new Set(["#000", "#000000", "black"])
const WHITE = new Set(["#fff", "#ffffff", "white"])

function colourLabels(node: Element, inherited: string | null) {
  const own = node.properties?.fill
  const fill = typeof own === "string" ? own.toLowerCase() : inherited
  if (node.tagName === "text" && fill !== null && fill !== "none" && !BLACK.has(fill)) {
    const colour = WHITE.has(fill) ? "var(--light)" : fill
    node.properties = { ...node.properties, style: `fill:${colour}` }
  }
  for (const child of node.children) {
    if (child.type === "element") {
      colourLabels(child, fill)
    }
  }
}

function readSvg(name: string, copy: number): Element | null {
  try {
    const source = readFileSync(join(process.cwd(), WORKSPACE, name), "utf-8")
    const fragment = fromHtml(withOwnIds(source, copy), { fragment: true, space: "svg" })
    for (const child of fragment.children) {
      if (child.type === "element" && child.tagName === "svg") {
        return child
      }
    }
  } catch {
    return null
  }
  return null
}

export const PlantoirFigures: QuartzTransformerPlugin = () => ({
  name: "PlantoirFigures",
  markdownPlugins() {
    return [
      () => (tree: MdRoot) => {
        const known = manifest()
        if (known === null) {
          return
        }
        visit(tree, "code", (node: Code, index, parent) => {
          const engine = node.lang ?? ""
          if (!ENGINES.includes(engine) || parent === undefined || index === undefined) {
            return
          }
          const key: string = keyOf(node.value)
          const entry = known.figures[engine]?.[key]
          const alt =
            entry?.alt ?? (engine === "tikz" ? altOf(node.value) ?? known.words.untitledDiagram : "")
          parent.children[index] = {
            type: "plantoirFigure",
            data: {
              hName: "figure",
              hProperties: {
                className: ["pl-figure", `pl-${engine}`],
                dataFigureEngine: engine,
                dataFigureKey: key,
                dataFigureSource: engine === "functionplot" ? node.value : undefined,
              },
              hChildren: [element("figcaption", { className: ["pl-sr-only"] }, [text(alt)])],
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
        if (known === null) {
          return
        }
        const words = known.words
        const root = pathToRoot(file.data.slug as FullSlug)
        let fontsLinked = false
        const copies = new Map<string, number>()
        visit(tree, "element", (node: Element) => {
          if (node.tagName !== "figure" || !classesOf(node).includes("pl-figure")) {
            return
          }
          const engine = String(node.properties?.dataFigureEngine ?? "")
          const key = String(node.properties?.dataFigureKey ?? "")
          if (!ENGINES.includes(engine) || key === "") {
            return
          }
          const source = String(node.properties?.dataFigureSource ?? "")
          delete node.properties.dataFigureSource
          const entry = known.figures[engine]?.[key]
          const caption = node.children
          if (engine === "tikz") {
            if (entry === undefined) {
              node.children = [element("p", { className: ["pl-figure-message"] }, [text(words.diagramNeedsPreview)]), ...caption]
              return
            }
            const copy = (copies.get(key) ?? 0) + 1
            copies.set(key, copy)
            let drawing: Element | null = null
            if (entry.ok && entry.svg) {
              drawing = readSvg(entry.svg, copy)
            }
            if (drawing === null) {
              node.properties.className = [...classesOf(node), "pl-figure-failed"]
              node.children = [element("p", { className: ["pl-figure-message"] }, [text(words.diagramCouldNotBeDrawn)]), ...caption]
              return
            }
            drawing.properties = { ...drawing.properties, ariaHidden: "true", focusable: "false" }
            colourLabels(drawing, null)
            const children: ElementContent[] = []
            if (!fontsLinked) {
              // The faces the drawings name, served by the site itself
              // (static/tikz/fonts.css) - once per page, with the first one.
              children.push(element("link", { rel: ["stylesheet"], href: `${root}/static/tikz/fonts.css` }, []))
              fontsLinked = true
            }
            children.push(drawing, ...caption)
            node.children = children
            return
          }
          // A graph: the box it is drawn into, and its own text until then.
          const sourceBox = element("pre", { className: ["pl-plot-source"] }, [element("code", {}, [text(source)])])
          if (entry === undefined) {
            node.children = [element("p", { className: ["pl-figure-message"] }, [text(words.graphNeedsPreview)]), sourceBox, ...caption]
            return
          }
          if (!entry.ok) {
            node.properties.className = [...classesOf(node), "pl-figure-failed"]
            node.children = [element("p", { className: ["pl-figure-message"] }, [text(words.graphCouldNotBeDrawn)]), sourceBox, ...caption]
            return
          }
          node.properties.dataPlot = JSON.stringify(entry.plot ?? {})
          node.properties.dataFigureRoot = root
          node.properties.dataFigureFailed = words.graphCouldNotBeDrawn
          node.properties.dataFigureMissing = words.graphNeedsPreview
          node.children = [element("div", { className: ["pl-plot"], ariaHidden: "true" }, []), sourceBox, ...caption]
        })
      },
    ]
  },
})
