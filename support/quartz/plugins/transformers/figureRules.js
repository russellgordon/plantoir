// Diagrams and graphs drawn from a page's own fences (#485 E1): the rules the
// site's transformer and the build's helper share, so the two cannot drift.
//
// Plain JavaScript (an ES module, like the rest of Quartz), with no imports
// but Node's own crypto: the site's transformer imports it through esbuild,
// and support/figures/plantoir-figures.mjs imports the SAME file from the
// section's copy of Quartz. The build's Python implements tidy() and keyOf()
// again (scripts/figures.py); contracts/shared-rules.json -> figureFences
// holds the cases all three are run against.
//
// What lives here, and nothing else:
// * tidy() - the TikZ plugin's own tidying (obsidian-tikzjax 0.5.2,
//   tidyTikzSource): drop "&nbsp;", trim every line, drop empty lines.
// * keyOf() - the name a figure is cached and looked up by: SHA-256 of the
//   tidied fence. Which ENGINE drew it is not in the key; the cache folder is
//   named after the engine instead (figures.py: engine_id), so a new engine
//   empties the cache without anybody remembering to bump a string.
// * parseFunctionPlot() - obsidian-functionplot 1.2.1's reading of a fence,
//   reproduced exactly, plus the problems a teacher is told about.
// * texProblem() - what TeX's own console says when a diagram fails.

import { createHash } from "crypto"

// The fence languages, exactly as the two Obsidian plugins register them.
export const ENGINES = ["tikz", "functionplot"]

// The settings obsidian-functionplot 1.2.1 reads (DEFAULT_PLOT_OPTIONS), and
// Plantoir's own `alt`. Anything else is reported and ignored, as the plugin
// ignores it.
export const PLOT_DEFAULTS = {
  title: "",
  xLabel: "",
  yLabel: "",
  bounds: [-10, 10, -10, 10],
  disableZoom: false,
  grid: true,
}
const PLOT_KEYS = ["title", "xLabel", "yLabel", "bounds", "disableZoom", "grid", "alt"]

// JavaScript's String.prototype.trim(), line by line - the plugin's rule.
// Python's str.strip() is NOT the same set (review S4), which is why the
// build's copy spells the set out.
export function tidyLines(source) {
  const lines = []
  const from = []
  const raw = String(source).replaceAll("&nbsp;", "").split("\n")
  for (let index = 0; index < raw.length; index += 1) {
    const trimmed = raw[index].trim()
    if (trimmed !== "") {
      lines.push(trimmed)
      from.push(index + 1)
    }
  }
  return { lines, from }
}

export function tidy(source) {
  return tidyLines(source).lines.join("\n")
}

export function keyOf(source) {
  return createHash("sha256").update(tidy(source), "utf8").digest("hex")
}

// `% alt: …` on the FIRST non-empty line of a TikZ fence (Plantoir's
// addition; a TeX comment, so Obsidian draws the same picture). Null when
// there is none.
export function altOf(source) {
  const first = tidyLines(source).lines[0] ?? ""
  const match = first.match(/^%\s*alt\s*:\s*(.*)$/)
  if (!match) {
    return null
  }
  const alt = match[1].trim()
  return alt === "" ? null : alt
}

function isNumber(value) {
  return typeof value === "number" && Number.isFinite(value)
}

// obsidian-functionplot 1.2.1, read from its released main.js:
//   header  = (src.match(/-{3}[^]*-{3}/) || [null])[0]          (greedy)
//   lines   = (header ? src.substring(header.length) : src)
//             .split("\n").map(trim).filter(non-empty)
//   options = {...DEFAULTS, ...parseYaml(header.match(/-{3,}([^]*?)-{3,}/)[1]), functions: lines}
//   data    = lines.map(line => ({ fn: line.split("=")[1], graphType: "polyline" }))
// Note `substring(header.length)` counts from the START of the fence, not
// from where the header was found: a function written above the settings
// is read wrongly by the plugin, so Plantoir says so (settingsMustComeFirst).
//
// `loadYaml` is the YAML reader (js-yaml's load, Quartz's own copy). Answers
// { settings, functions: [{ text, fn, blockLine }], alt, unknown: [names],
//   problems: [{ reason, blockLine, name? }] } - problems that stop the graph
// being drawn. `unknown` never stops it.
export function parseFunctionPlot(source, loadYaml) {
  const text = String(source).replaceAll("\r\n", "\n")
  const problems = []
  const unknown = []
  let settings = { ...PLOT_DEFAULTS }
  let alt = null

  const greedy = text.match(/-{3}[^]*-{3}/)
  let rest = text
  let restStartLine = 1
  if (greedy) {
    const before = text.slice(0, greedy.index)
    if (before.trim() !== "") {
      problems.push({ reason: "settingsMustComeFirst", blockLine: lineOf(text, greedy.index) })
    }
    rest = text.substring(greedy[0].length)
    restStartLine = lineOf(text, greedy[0].length)
    const inner = greedy[0].match(/-{3,}([^]*?)-{3,}/)
    let header = null
    try {
      header = loadYaml(inner ? inner[1] : "")
    } catch (error) {
      problems.push({ reason: "settingsDoNotParse", blockLine: lineOf(text, greedy.index) })
    }
    if (header !== null && header !== undefined && typeof header === "object" && !Array.isArray(header)) {
      for (const key of Object.keys(header)) {
        if (!PLOT_KEYS.includes(key)) {
          unknown.push(key)
          continue
        }
        const value = header[key]
        if (key === "alt") {
          if (value !== null && value !== undefined && String(value).trim() !== "") {
            alt = String(value).trim()
          }
          continue
        }
        // The plugin's own "Plot a function" command writes `title:` with
        // nothing after it, which YAML reads as null: the default stands.
        if (value === null || value === undefined) {
          continue
        }
        settings[key] = value
      }
    } else if (header !== null && header !== undefined && problems.length === 0) {
      problems.push({ reason: "settingsDoNotParse", blockLine: lineOf(text, greedy.index) })
    }
  }

  const bounds = settings.bounds
  if (!Array.isArray(bounds) || bounds.length !== 4 || !bounds.every(isNumber)) {
    problems.push({ reason: "boundsNeedFour", blockLine: greedy ? lineOf(text, greedy.index) : 1 })
    settings.bounds = [...PLOT_DEFAULTS.bounds]
  } else if (!(bounds[0] < bounds[1]) || !(bounds[2] < bounds[3])) {
    problems.push({ reason: "boundsNeedFour", blockLine: greedy ? lineOf(text, greedy.index) : 1 })
    settings.bounds = [...PLOT_DEFAULTS.bounds]
  }
  settings.disableZoom = settings.disableZoom === true
  settings.grid = settings.grid !== false
  for (const name of ["title", "xLabel", "yLabel"]) {
    settings[name] = typeof settings[name] === "string" || isNumber(settings[name]) ? String(settings[name]) : ""
  }

  const functions = []
  const restLines = rest.split("\n")
  for (let index = 0; index < restLines.length; index += 1) {
    const trimmed = restLines[index].trim()
    if (trimmed === "") {
      continue
    }
    const blockLine = restStartLine + index
    const pieces = trimmed.split("=")
    if (pieces.length < 2) {
      problems.push({ reason: "noEquals", blockLine })
      continue
    }
    functions.push({ text: trimmed, fn: pieces[1].trim(), blockLine })
  }
  return { settings, functions, alt, unknown, problems }
}

// The 1-based line of `text` that character `index` sits on.
function lineOf(text, index) {
  let line = 1
  for (let position = 0; position < index && position < text.length; position += 1) {
    if (text[position] === "\n") {
      line += 1
    }
  }
  return line
}

// A two-argument log (`log(x, 2)`): function-plot ignores the base and draws
// the natural log, with no error (review S2). Found in the text, because the
// evaluator never complains.
export function logTakesOneArgument(fn) {
  const at = fn.search(/\blog\s*\(/)
  if (at < 0) {
    return false
  }
  let depth = 0
  for (let position = fn.indexOf("(", at); position < fn.length; position += 1) {
    const character = fn[position]
    if (character === "(") {
      depth += 1
    } else if (character === ")") {
      depth -= 1
      if (depth === 0) {
        return logTakesOneArgument(fn.slice(position + 1))
      }
    } else if (character === "," && depth === 1) {
      return true
    }
  }
  return false
}

// What TeX's console said about a diagram that was not drawn. `logLines` is
// what TeX printed AFTER the input it was given; the input itself starts on
// TeX's line 2 (node-tikzjax puts a one-line preamble in front of it), so
// TeX's `l.N` is the tidied fence's line N - 1 (measured, plan M5).
// Answers { reason, texLine (1-based, in the TIDIED fence, or null), name, said }.
export function texProblem(logLines) {
  let said = null
  let texLine = null
  let name = null
  for (let index = 0; index < logLines.length; index += 1) {
    const line = logLines[index]
    if (said === null && line.startsWith("! ")) {
      said = line.slice(2).trim()
      continue
    }
    if (said !== null && texLine === null) {
      const at = line.match(/^l\.(\d+)\s?(.*)$/)
      if (at) {
        texLine = Math.max(1, parseInt(at[1], 10) - 1)
        const before = at[2] ?? ""
        const command = before.match(/(\\[A-Za-z@]+|\\.)\s*$/)
        if (command) {
          name = command[1]
        }
      }
    }
  }
  if (said === null) {
    return { reason: "texSaid", texLine: null, name: null, said: "" }
  }
  const missingFile = said.match(/File `([^']+)' not found/)
  if (missingFile) {
    return { reason: "missingPackage", texLine, name: missingFile[1].replace(/\.(sty|tex)$/, ""), said }
  }
  if (/Missing \\begin\{document\}/.test(said)) {
    return { reason: "missingDocument", texLine, name: null, said }
  }
  if (/Two \\documentclass or \\documentstyle commands/.test(said)) {
    return { reason: "documentClassNotNeeded", texLine, name: null, said }
  }
  if (/^Undefined control sequence/.test(said)) {
    return { reason: "undefinedCommand", texLine, name, said }
  }
  return { reason: "texSaid", texLine, name: null, said }
}
