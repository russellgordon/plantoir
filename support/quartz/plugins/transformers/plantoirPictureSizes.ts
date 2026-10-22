// Pictures get their real width and height in the HTML (#612): the site's
// half that runs when the site is BUILT. The reading and the attribute rule
// are in pictureSizes.js; this file finds each picture's file and writes
// what that rule answers.
//
// Html stage, wired straight after PlantoirTasks, and so after CrawlLinks:
// every `src` is already final, relative to the page. For each <img> whose
// src is a file in the course (not a remote address, not data:):
//
// * the src is decoded, stripped of ?query and #hash, joined to the page's
//   folder and tidied of `.` and `..`, then looked up among the course's own
//   files by the name Quartz's Assets emitter writes each one at
//   (slugifyFilePath), so the lookup is exactly the inverse of where the
//   picture went;
// * the file's size is read (cached by path, modification time and length -
//   a copy that keeps the old time still has a new length, review S5);
// * `width`, `height` and the marker `data-pl-sized` are written, and only
//   that marker gets pictures.scss's `height: auto`, so the shape keeps the
//   box right in a narrow window while a teacher's typed `|600x400` is drawn
//   exactly as before (#612 plan Q1).
//
// A picture it cannot find or size - remote, missing, broken, an SVG with
// only a viewBox and no width given, a raw <img> with a % width or a style -
// is left exactly as Quartz wrote it, and #609's rule still lays it out at
// its real height once its bytes arrive.
//
// In a preview (`quartz build --serve`) a rebuild refreshes ctx.allFiles and
// ctx.allSlugs (patches/build.ts), so a picture ADDED during a preview is
// sized when its page is rebuilt. Known gap: a picture REPLACED with one of a
// different size keeps the old width and height on pages not rebuilt since -
// a page not edited during that preview - until the preview restarts. A
// publish is always a fresh build and is never affected.
//
// Rejected (#612 plan 2): a Pillow pass over the built site (a preview's
// rebuilds run in Node, with no Python in the loop, so the first edit would
// lose every size); a Pillow-written list of sizes read here (the same for a
// publish, but a picture added during a preview stays unsized, at twice the
// code); `sharp` (in Quartz's node_modules but used by nothing Plantoir
// runs, and its Windows binary has never been exercised); a global
// `img { height: auto }` (it changes a teacher's `|600x400`: 600 x 400 drawn
// as 600 x 300); sizing an SVG from its viewBox alone (790 px wide today,
// 300 px sized).

import { Element, Root as HtmlRoot } from "hast"
import { visit } from "unist-util-visit"
import { statSync } from "node:fs"
import { QuartzTransformerPlugin } from "../types"
import { FullSlug, joinSegments } from "../../util/path"
import { pictureSizeOfFile, sizedAttributes } from "./pictureSizes.js"

type PictureSize = { width: number; height: number } | { ratio: number } | null

// One answer per file, kept while its modification time and length agree.
const sizeCache = new Map<string, { modified: number; length: number; size: PictureSize }>()

function sizeOfFile(path: string): PictureSize {
  let modified = 0
  let length = 0
  try {
    const facts = statSync(path)
    if (!facts.isFile()) {
      return null
    }
    modified = facts.mtimeMs
    length = facts.size
  } catch {
    return null
  }
  const known = sizeCache.get(path)
  if (known !== undefined && known.modified === modified && known.length === length) {
    return known.size
  }
  let size: PictureSize = null
  try {
    size = pictureSizeOfFile(path)
  } catch {
    size = null
  }
  sizeCache.set(path, { modified, length, size })
  return size
}

// The course's files by the name each is written at, built once per list of
// files (review N1): a preview's rebuild replaces ctx.allSlugs with a new
// array, so the map is rebuilt exactly when the course's files change.
let slugMapFor: readonly string[] | null = null
let fileBySlug = new Map<string, string>()

function filesBySlug(allSlugs: readonly string[], allFiles: readonly string[]): Map<string, string> {
  if (slugMapFor === allSlugs) {
    return fileBySlug
  }
  const map = new Map<string, string>()
  for (let index = 0; index < allSlugs.length && index < allFiles.length; index += 1) {
    map.set(allSlugs[index], allFiles[index])
  }
  slugMapFor = allSlugs
  fileBySlug = map
  return map
}

function isRemote(src: string): boolean {
  return /^[a-z][a-z0-9+.-]*:/i.test(src) || src.startsWith("//")
}

// The picture's slug, from the page's folder and a src relative to the page.
function slugOfPicture(pageSlug: string, src: string): string | null {
  let target = ""
  try {
    target = decodeURIComponent(src.split(/[?#]/)[0])
  } catch {
    return null
  }
  if (target === "") {
    return null
  }
  const folder = pageSlug.includes("/") ? pageSlug.slice(0, pageSlug.lastIndexOf("/")) : ""
  const start = target.startsWith("/") ? target : joinSegments(folder, target)
  const parts: string[] = []
  for (const part of start.split("/")) {
    if (part === "" || part === ".") {
      continue
    }
    if (part === "..") {
      parts.pop()
    } else {
      parts.push(part)
    }
  }
  return parts.join("/")
}

export const PlantoirPictureSizes: QuartzTransformerPlugin = () => ({
  name: "PlantoirPictureSizes",
  htmlPlugins(ctx) {
    return [
      () => (tree: HtmlRoot, file) => {
        const pageSlug = (file.data.slug ?? "") as FullSlug
        visit(tree, "element", (node: Element) => {
          if (node.tagName !== "img") {
            return
          }
          const properties = node.properties ?? {}
          const src = properties.src
          if (typeof src !== "string" || src === "" || isRemote(src)) {
            return
          }
          const pictureSlug = slugOfPicture(pageSlug, src)
          if (pictureSlug === null) {
            return
          }
          const fileName = filesBySlug(ctx.allSlugs, ctx.allFiles).get(pictureSlug)
          if (fileName === undefined) {
            return
          }
          const sized = sizedAttributes(properties, sizeOfFile(joinSegments(ctx.argv.directory, fileName)))
          if (sized === null) {
            return
          }
          properties.width = sized.width
          properties.height = sized.height
          properties.dataPlSized = ""
          node.properties = properties
        })
      },
    ]
  },
})
