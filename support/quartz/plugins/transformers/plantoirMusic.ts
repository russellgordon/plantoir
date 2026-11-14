// Tunes from a page's own ```abc fences (#679): the site's half.
//
// The build (scripts/music.py) has already read every ```abc and
// ```music-abc fence on the pages students can see, DRAWN each with abcjs
// (support/music/plantoir-music.mjs), put the engine and the sounds the
// tunes with Play need in quartz/static/abcjs/, and left what the site needs
// in quartz/plantoir-music/manifest.json. This only PLACES them, in two
// stages, as plantoirPhet.ts does:
//
// * markdown stage - a fence the manifest knows becomes `<figure
//   class="pl-figure pl-music">` holding nothing but a figcaption with its
//   description (hidden on screen; what a screen reader reads). An mdast
//   node with data.hName, never a raw html node, so the quiz reader sees a
//   figure, not markup, and Description reads the caption alone.
// * html stage - the drawing goes in (the build's own SVG, in abcjs's
//   container), and under it, for a tune with Play, the controls and the
//   sounds' credit line (musicFences.credit). A tune inside a quiz's choice
//   gets neither (musicFences.quizzes): a press on Play there would also
//   choose the answer. The quizzes' markdown stage has run by now, so a
//   choice is found by its class.
//
// A fence the manifest does not know (a site with no tune, one that could
// not be drawn, a build that could not prepare them) stays the plain code
// block it always was: the byte-identical guarantee for sites without tunes
// rests on this.

import { Root as MdRoot, Code } from "mdast"
import { Element, Root as HtmlRoot, ElementContent } from "hast"
import { visit } from "unist-util-visit"
import { fromHtml } from "hast-util-from-html"
import { readFileSync, statSync } from "fs"
import { join } from "path"
import { QuartzTransformerPlugin } from "../types"
import { FullSlug, pathToRoot } from "../../util/path"
// @ts-ignore - plain JavaScript, shared with the figures transformer
import { keyOf } from "./figureRules.js"

type Entry = {
  ok: boolean
  html: string
  alt: string
  play: boolean
  abc: string
  sounds: string[]
  notes: number
}
type Manifest = {
  words: Record<string, string>
  credit: Record<string, string>
  options: Record<string, unknown>
  playable: boolean
  soundsFolder: string
  engine: string
  // By page (its path in the site's content, NFC), then by fence key.
  pages: Record<string, Record<string, Entry>>
}

const WORKSPACE = join("quartz", "plantoir-music")
// musicFences.fences.languages
const LANGUAGES = ["abc", "music-abc"]
// The class a quiz's choice carries (plantoirQuizzes.ts).
const CHOICE = "plantoir-quiz-choice"

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

function tunesOf(known: Manifest, file: { data: { relativePath?: unknown } }): Record<string, Entry> | null {
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

// The build's drawing: abcjs's container div holding its SVG.
function drawing(html: string): Element | null {
  try {
    const fragment = fromHtml(html, { fragment: true })
    for (const child of fragment.children) {
      if (child.type === "element" && child.tagName === "div") {
        const classes = classesOf(child)
        child.properties.className = [...classes, "pl-music-drawing"]
        return child
      }
    }
  } catch {
    return null
  }
  return null
}

// The credit line, its licence's name a link (musicFences.credit).
function credit(links: Record<string, string>): Element {
  const sentence = links.sentence
  const at = sentence.indexOf(links.licenceName)
  const children: ElementContent[] = []
  if (at < 0) {
    children.push(text(sentence))
  } else {
    children.push(text(sentence.slice(0, at)))
    children.push(element("a", { href: links.licenceUrl, rel: ["license"] }, [text(links.licenceName)]))
    children.push(text(sentence.slice(at + links.licenceName.length)))
  }
  return element("p", { className: ["pl-music-credit"] }, children)
}

function titleOf(entry: Entry, words: Record<string, string>): string {
  const match = entry.abc.match(/^[ \t]*T:[ \t]*(.+?)[ \t]*$/m)
  return match ? match[1] : words.untitledTune
}

export const PlantoirMusic: QuartzTransformerPlugin = () => ({
  name: "PlantoirMusic",
  markdownPlugins() {
    return [
      () => (tree: MdRoot, file) => {
        const known = manifest()
        const tunes = known === null ? null : tunesOf(known, file)
        if (tunes === null) {
          return
        }
        visit(tree, "code", (node: Code, index, parent) => {
          if (!LANGUAGES.includes(node.lang ?? "") || parent === undefined || index === undefined) {
            return
          }
          const key: string = keyOf(node.value)
          const entry = tunes[key]
          if (entry === undefined || !entry.ok) {
            return
          }
          parent.children[index] = {
            type: "plantoirMusic",
            data: {
              hName: "figure",
              hProperties: { className: ["pl-figure", "pl-music"], dataMusicKey: key },
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
        const tunes = known === null ? null : tunesOf(known, file)
        if (known === null || tunes === null) {
          return
        }
        const words = known.words
        const root = pathToRoot(file.data.slug as FullSlug)
        const place = (node: Element, inChoice: boolean) => {
          if (node.tagName === "figure" && classesOf(node).includes("pl-music")) {
            const key = String(node.properties?.dataMusicKey ?? "")
            const entry = tunes[key]
            const drawn = entry === undefined ? null : drawing(entry.html)
            if (entry === undefined || drawn === null) {
              return
            }
            const caption = node.children.find(
              (child) => child.type === "element" && child.tagName === "figcaption",
            ) as Element | undefined
            const children: ElementContent[] = [drawn]
            if (entry.play && !inChoice) {
              const title = titleOf(entry, words)
              node.properties.dataMusic = JSON.stringify({
                abc: entry.abc,
                options: known.options,
                engine: `${root}/${known.engine}`,
                sounds: `${root}/${known.soundsFolder}`,
                // The sound folders this tune's notes are asked from
                // (`<sounds><name>-mp3/<note>.mp3`, by abcjs at the press):
                // named here so a reader of the page alone (#901: a site
                // carries only what its pages name) can tell which it needs.
                soundNames: entry.sounds,
                play: words.play,
                stop: words.stop,
                playLabel: filled(words.playLabel, { title }),
                stopLabel: filled(words.stopLabel, { title }),
                gettingReady: words.gettingReady,
                couldNotPlay: words.couldNotPlay,
              })
              children.push(
                element("div", { className: ["pl-music-controls"] }, [
                  element(
                    "button",
                    { type: "button", className: ["pl-music-play"], ariaLabel: filled(words.playLabel, { title }) },
                    [text(words.play)],
                  ),
                  element("span", { className: ["pl-music-status"], role: "status", ariaLive: "polite" }, []),
                ]),
              )
              children.push(credit(known.credit))
            }
            node.children = caption !== undefined ? [...children, caption] : children
            return
          }
          const here = inChoice || classesOf(node).includes(CHOICE)
          for (const child of node.children) {
            if (child.type === "element") {
              place(child, here)
            }
          }
        }
        for (const child of tree.children) {
          if (child.type === "element") {
            place(child, false)
          }
        }
      },
    ]
  },
})
