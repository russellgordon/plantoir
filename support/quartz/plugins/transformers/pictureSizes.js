// A picture's own width and height, read from its first bytes, and the
// width and height attributes that follow from it (#612). The rules the
// site's transformer (plantoirPictureSizes.ts) and its checks share, so the
// two cannot drift.
//
// Plain JavaScript (an ES module, like the rest of Quartz), with no imports
// but Node's own fs: the transformer imports it through esbuild, and
// scripts/check_picture_sizes_against_the_site.py imports the SAME file in
// Node and compares every answer with Pillow's (ImageOps.exif_transpose)
// over the corpus in scripts/fixtures/picture-sizes/.
//
// Why the build writes the sizes at all: Quartz writes a picture as
// `width="600" height="auto"` (or both "auto"), so until its bytes arrive a
// picture has NO height, in every engine. On a first visit over a slow
// network everything below it then moves down by the picture's whole height
// as it arrives - 14 jumps of up to 587 px on a 15-picture page, measured in
// WebKit and Chromium alike (#612 plan 1a). With the picture's real width
// and height in the HTML, plus `height: auto` (pictures.scss), the browser
// reserves the right box before a byte has arrived: 0 jumps.
//
// What it reads, and what it answers:
// * PNG - IHDR, and an eXIf chunk before the first IDAT (orientations 5-8
//   swap width and height: both engines rotate a PNG by it, review S2). No
//   IDAT at all is a broken file: null.
// * GIF - the logical screen, but only when the first frame fills it
//   exactly; otherwise Chromium and WebKit draw it at different sizes
//   (review N2), so null.
// * JPEG - the first SOF0-15 (not C4/C8/CC, which are not frames), with the
//   EXIF orientation from APP1 tag 0x0112 in either byte order; 5-8 swap
//   width and height, as `image-orientation: from-image` does. Fill bytes
//   (0xFF 0xFF) before a marker are skipped, as the spec allows.
// * WebP - VP8, VP8L and VP8X. A VP8X with EXIF is null: WebKit honours its
//   orientation and Chromium ignores it (review S2), so no one pair of
//   numbers is right in both.
// * BMP - |width| and |height| (a top-down BMP has a negative height).
// * SVG - the ROOT element's own `width` and `height` only (comments, the
//   prolog and a DOCTYPE skipped; attribute names case-sensitive, as the
//   engines read them - review S4), in px or unitless, or cm/mm/in/pt/pc at
//   96 px to the inch. An SVG with NEITHER, but a viewBox, has a shape and
//   no size: { ratio } only. Anything else (%, em, one of the two) is null.
// * Anything else (HEIC, TIFF, a broken file): null.
//
// null always means "leave the tag exactly as Quartz wrote it". A picture the
// build cannot size is no worse than in 1.8.4: #609's rule still lays it out
// at its real height the moment its bytes arrive.

import { closeSync, openSync, readSync, readFileSync, statSync } from "fs"

// CSS pixels per unit (96 px to the inch).
const CSS_UNITS = { "": 1, px: 1, in: 96, cm: 96 / 2.54, mm: 96 / 25.4, pt: 96 / 72, pc: 16 }

function svgLength(value) {
  if (typeof value !== "string") {
    return null
  }
  const match = /^\s*([0-9]*\.?[0-9]+)\s*(px|in|cm|mm|pt|pc)?\s*$/.exec(value)
  if (match === null) {
    return null
  }
  const length = Number(match[1]) * CSS_UNITS[match[2] ?? ""]
  return length > 0 ? length : null
}

// The text of the root element's start tag, or null. Everything an XML file
// may carry before its root is skipped: a byte order mark, white space, the
// <?xml ...?> prolog and other processing instructions, comments, and a
// DOCTYPE with or without an internal subset in [ ].
function svgRootTag(text) {
  let at = text.charCodeAt(0) === 0xfeff ? 1 : 0
  while (at < text.length) {
    const rest = text.slice(at)
    const space = /^\s+/.exec(rest)
    if (space !== null) {
      at += space[0].length
      continue
    }
    if (rest.startsWith("<?")) {
      const end = text.indexOf("?>", at + 2)
      if (end < 0) {
        return null
      }
      at = end + 2
      continue
    }
    if (rest.startsWith("<!--")) {
      const end = text.indexOf("-->", at + 4)
      if (end < 0) {
        return null
      }
      at = end + 3
      continue
    }
    if (rest.startsWith("<!DOCTYPE") || rest.startsWith("<!doctype")) {
      const subset = text.indexOf("[", at)
      const close = text.indexOf(">", at)
      if (close < 0) {
        return null
      }
      if (subset >= 0 && subset < close) {
        const subsetEnd = text.indexOf("]", subset)
        if (subsetEnd < 0) {
          return null
        }
        const afterSubset = text.indexOf(">", subsetEnd)
        if (afterSubset < 0) {
          return null
        }
        at = afterSubset + 1
      } else {
        at = close + 1
      }
      continue
    }
    const root = /^<(?:[A-Za-z_][\w.-]*:)?svg(?=[\s/>])[^>]*>/.exec(rest)
    return root === null ? null : root[0]
  }
  return null
}

// One attribute of a start tag, by its exact (case-sensitive) name.
function attributeOf(tag, name) {
  const found = new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`).exec(tag)
  if (found === null) {
    return null
  }
  return found[1] ?? found[2]
}

function svgSize(text) {
  const tag = svgRootTag(text)
  if (tag === null) {
    return null
  }
  const widthText = attributeOf(tag, "width")
  const heightText = attributeOf(tag, "height")
  if (widthText === null && heightText === null) {
    // No size of its own: the browser draws it at the column's width, so
    // only a width the teacher gave can size it (sizing it from the viewBox
    // shrank a bare one from 790 to 300 px wide - #612 plan 1b).
    const viewBox = attributeOf(tag, "viewBox")
    if (viewBox === null) {
      return null
    }
    const numbers = viewBox.trim().split(/[\s,]+/)
    if (numbers.length !== 4) {
      return null
    }
    const boxWidth = Number(numbers[2])
    const boxHeight = Number(numbers[3])
    if (!(boxWidth > 0) || !(boxHeight > 0)) {
      return null
    }
    return { ratio: boxHeight / boxWidth }
  }
  const width = svgLength(widthText)
  const height = svgLength(heightText)
  if (width === null || height === null) {
    return null
  }
  return { width, height }
}

// The EXIF orientation in a TIFF block (an APP1 after "Exif\0\0", or a PNG
// eXIf chunk), in either byte order; 1 when there is none or it is unreadable.
function exifOrientation(bytes, tiff, end) {
  if (tiff + 8 > end) {
    return 1
  }
  const order = bytes.toString("latin1", tiff, tiff + 2)
  if (order !== "II" && order !== "MM") {
    return 1
  }
  const little = order === "II"
  function u16(at) {
    return little ? bytes.readUInt16LE(at) : bytes.readUInt16BE(at)
  }
  function u32(at) {
    return little ? bytes.readUInt32LE(at) : bytes.readUInt32BE(at)
  }
  const ifd = tiff + u32(tiff + 4)
  if (ifd + 2 > end) {
    return 1
  }
  const count = u16(ifd)
  for (let entry = 0; entry < count; entry += 1) {
    const at = ifd + 2 + entry * 12
    if (at + 12 > end) {
      return 1
    }
    if (u16(at) === 0x0112) {
      const orientation = u16(at + 8)
      return orientation >= 1 && orientation <= 8 ? orientation : 1
    }
  }
  return 1
}

function turned(width, height, orientation) {
  if (orientation >= 5 && orientation <= 8) {
    return { width: height, height: width }
  }
  return { width, height }
}

function pngSize(bytes) {
  if (bytes.length < 24 || bytes.toString("latin1", 12, 16) !== "IHDR") {
    return null
  }
  const width = bytes.readUInt32BE(16)
  const height = bytes.readUInt32BE(20)
  let orientation = 1
  let at = 8
  while (at + 8 <= bytes.length) {
    const length = bytes.readUInt32BE(at)
    const kind = bytes.toString("latin1", at + 4, at + 8)
    if (kind === "IDAT") {
      return turned(width, height, orientation)
    }
    if (kind === "eXIf") {
      orientation = exifOrientation(bytes, at + 8, Math.min(at + 8 + length, bytes.length))
    }
    at += 12 + length
  }
  // No picture data before the end: a broken (or cut short) file.
  return null
}

function gifSize(bytes) {
  if (bytes.length < 13) {
    return null
  }
  const width = bytes.readUInt16LE(6)
  const height = bytes.readUInt16LE(8)
  const flags = bytes[10]
  let at = 13
  if (flags & 0x80) {
    at += 3 * 2 ** ((flags & 0x07) + 1)
  }
  while (at < bytes.length) {
    const block = bytes[at]
    if (block === 0x21) {
      // An extension: its label, then sub-blocks until an empty one.
      at += 2
      while (at < bytes.length && bytes[at] !== 0) {
        at += bytes[at] + 1
      }
      at += 1
      continue
    }
    if (block === 0x2c) {
      if (at + 9 > bytes.length) {
        return null
      }
      const left = bytes.readUInt16LE(at + 1)
      const top = bytes.readUInt16LE(at + 3)
      const frameWidth = bytes.readUInt16LE(at + 5)
      const frameHeight = bytes.readUInt16LE(at + 7)
      if (left !== 0 || top !== 0 || frameWidth !== width || frameHeight !== height) {
        return null
      }
      return { width, height }
    }
    return null
  }
  return null
}

function jpegSize(bytes) {
  let at = 2
  let orientation = 1
  while (at + 4 <= bytes.length) {
    if (bytes[at] !== 0xff) {
      // Stray bytes between segments, which decoders step over.
      at += 1
      continue
    }
    const marker = bytes[at + 1]
    if (marker === 0xff) {
      // A fill byte before the marker.
      at += 1
      continue
    }
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      at += 2
      continue
    }
    if (marker === 0xd9 || marker === 0xda) {
      // The end of the picture, or its scan, before any frame header.
      return null
    }
    const length = bytes.readUInt16BE(at + 2)
    if (length < 2) {
      return null
    }
    const end = Math.min(at + 2 + length, bytes.length)
    if (marker === 0xe1 && at + 10 <= bytes.length && bytes.toString("latin1", at + 4, at + 10) === "Exif\0\0") {
      orientation = exifOrientation(bytes, at + 10, end)
    }
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      if (at + 9 > bytes.length) {
        return null
      }
      const height = bytes.readUInt16BE(at + 5)
      const width = bytes.readUInt16BE(at + 7)
      return turned(width, height, orientation)
    }
    at += 2 + length
  }
  return null
}

function webpSize(bytes) {
  const kind = bytes.toString("latin1", 12, 16)
  if (kind === "VP8 ") {
    if (bytes.length < 30 || bytes[23] !== 0x9d || bytes[24] !== 0x01 || bytes[25] !== 0x2a) {
      return null
    }
    return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff }
  }
  if (kind === "VP8L") {
    if (bytes.length < 25 || bytes[20] !== 0x2f) {
      return null
    }
    const bits = bytes.readUInt32LE(21)
    return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 }
  }
  if (kind === "VP8X") {
    if (bytes.length < 30) {
      return null
    }
    if (bytes[20] & 0x08) {
      // EXIF: the engines disagree about its orientation (review S2).
      return null
    }
    return { width: bytes.readUIntLE(24, 3) + 1, height: bytes.readUIntLE(27, 3) + 1 }
  }
  return null
}

function bmpSize(bytes) {
  const header = bytes.readUInt32LE(14)
  if (header === 12) {
    return { width: bytes.readUInt16LE(18), height: bytes.readUInt16LE(20) }
  }
  return { width: Math.abs(bytes.readInt32LE(18)), height: Math.abs(bytes.readInt32LE(22)) }
}

// { width, height } in CSS pixels as the browser will draw the picture,
// { ratio } (height over width) for an SVG with a shape and no size, or null.
// `name` is only asked whether the file is an SVG.
export function pictureSize(content, name) {
  const bytes = Buffer.from(content)
  let size = null
  try {
    if (/\.svg$/i.test(name)) {
      size = svgSize(bytes.toString("utf8"))
    } else if (bytes.length >= 8 && bytes.readUInt32BE(0) === 0x89504e47 && bytes.readUInt32BE(4) === 0x0d0a1a0a) {
      size = pngSize(bytes)
    } else if (bytes.length >= 6 && (bytes.toString("latin1", 0, 6) === "GIF87a" || bytes.toString("latin1", 0, 6) === "GIF89a")) {
      size = gifSize(bytes)
    } else if (bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
      size = jpegSize(bytes)
    } else if (bytes.length >= 16 && bytes.toString("latin1", 0, 4) === "RIFF" && bytes.toString("latin1", 8, 12) === "WEBP") {
      size = webpSize(bytes)
    } else if (bytes.length >= 26 && bytes.toString("latin1", 0, 2) === "BM") {
      size = bmpSize(bytes)
    }
  } catch {
    // Read past the end of a file that is cut short, or nonsense: no size.
    return null
  }
  if (size === null || "ratio" in size) {
    return size
  }
  if (!(size.width > 0) || !(size.height > 0)) {
    return null
  }
  return size
}

// The first bytes are nearly always enough (a PNG's IHDR, a JPEG's frame
// header after its EXIF, an SVG's root tag), so a course of photographs is
// not read whole on every build. When they are not - a JPEG with a large
// embedded profile before its frame header, say - the whole file is read
// and asked again, so the answer never depends on where the first read
// stopped.
export const FIRST_READ = 256 * 1024

export function pictureSizeOfFile(path, firstRead = FIRST_READ) {
  const length = statSync(path).size
  if (length <= firstRead) {
    return pictureSize(readFileSync(path), path)
  }
  const start = Buffer.alloc(firstRead)
  const handle = openSync(path, "r")
  let got = 0
  try {
    got = readSync(handle, start, 0, firstRead, 0)
  } finally {
    closeSync(handle)
  }
  const early = pictureSize(start.subarray(0, got), path)
  if (early !== null) {
    return early
  }
  return pictureSize(readFileSync(path), path)
}

// A width or height a teacher (or Quartz) wrote that the build may replace:
// none, or "auto".
function isUnset(value) {
  return value === undefined || value === null || value === "auto"
}

// A whole number of pixels: Quartz's `|600` arrives as the string "600", a
// raw <img width="600"> as the number 600.
function wholePixels(value) {
  if (typeof value === "number") {
    return Number.isInteger(value) && value > 0 ? value : null
  }
  if (typeof value === "string" && /^\d+$/.test(value)) {
    const number = Number(value)
    return number > 0 ? number : null
  }
  return null
}

// The width and height the build writes on one <img>, from the attributes it
// already has (hast properties: width, height, style) and the picture's own
// size. null means touch nothing. The rule (#612 plan 2, review S1):
// * a style attribute, a height that is not "auto" (a teacher's `|600x400`,
//   a raw <img height>) or a width that is neither "auto" nor a whole number
//   (`50%`, `300px`) -> nothing; the tag stays exactly as it was written, so
//   the picture is drawn exactly as in 1.8.4;
// * a whole-number width -> kept, and the height follows the picture's shape;
// * no width -> the picture's own width and height;
// * an SVG with only a shape -> sized only when a width was given.
export function sizedAttributes(properties, size) {
  if (size === null || size === undefined) {
    return null
  }
  if (properties.style !== undefined && properties.style !== null) {
    return null
  }
  if (!isUnset(properties.height)) {
    return null
  }
  const givenWidth = wholePixels(properties.width)
  if (givenWidth === null && !isUnset(properties.width)) {
    return null
  }
  if ("ratio" in size) {
    if (givenWidth === null) {
      return null
    }
    return { width: givenWidth, height: Math.max(1, Math.round(givenWidth * size.ratio)) }
  }
  const width = givenWidth ?? Math.round(size.width)
  return { width, height: Math.max(1, Math.round((width * size.height) / size.width)) }
}
