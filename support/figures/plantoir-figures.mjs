#!/usr/bin/env node
// Draws a page's TikZ diagrams and checks its functionplot graphs, for the
// build (#485 E1). Started by scripts/figures.py only when a figure is not
// already in the cache; never by the site, never in a browser.
//
// Protocol, one JSON object per line each way:
//   it says    {"ready": true}                       once it can take work
//   you send   {"load": "tikz"}                      before the first diagram
//   it says    {"loaded": "tikz", "ms": n}           (TeX's engine is ~0.8 s to load,
//                                                    so it is loaded only when needed:
//                                                    a build of graphs alone never pays it)
//   you send   {"id": n, "engine": "tikz", "body": "..."}
//   it says    {"id": n, "ok": true, "svg": "...", "ms": n}
//          or  {"id": n, "ok": false, "reason": "...", "texLine": n|null, "name": ..., "said": "..."}
//   you send   {"id": n, "engine": "functionplot", "body": "..."}
//   it says    {"id": n, "ok": true|false, "plot": {...}, "alt": ..., "unknown": [...], "problems": [...]}
// Jobs run one at a time, in order. The CALLER keeps the clock: a diagram
// that never finishes (`\def\x{\x}\x` loops for ever, measured) is ended by
// figures.py killing this process, never by anything in here.
//
// Arguments: --engine <folder holding node-tikzjax's package.json>
//            --function-plot <function-plot.js>
//            --rules <figureRules.js, from the section's own Quartz>
//            --quartz <Quartz's folder, for js-yaml>

import { createRequire } from "module"
import { join } from "path"
import { pathToFileURL } from "url"
import readline from "readline"

function argument(name) {
  const at = process.argv.indexOf("--" + name)
  return at >= 0 && at + 1 < process.argv.length ? process.argv[at + 1] : null
}

// Everything that goes to the caller goes through here: TeX's own console is
// captured (console.log) and never reaches stdout.
const out = process.stdout
function send(message) {
  out.write(JSON.stringify(message) + "\n")
}

const rules = await import(pathToFileURL(argument("rules")).href)

// function-plot's bundle is a browser build that names `self` as it loads.
globalThis.self = globalThis
let functionPlot = null
const plotPath = argument("function-plot")
try {
  functionPlot = createRequire(plotPath)(plotPath)
} catch (error) {
  functionPlot = null
}

let loadYaml = null
try {
  const yaml = createRequire(join(argument("quartz"), "package.json"))("js-yaml")
  loadYaml = (text) => yaml.load(text)
} catch (error) {
  loadYaml = null
}

let tikz = null

async function loadTikz() {
  if (tikz === null) {
    const engine = createRequire(join(argument("engine"), "package.json"))("node-tikzjax")
    await engine.load()
    tikz = engine
  }
}

async function drawTikz(job) {
  const started = Date.now()
  await loadTikz()
  const source = rules.tidy(job.body)
  const captured = []
  const original = console.log
  console.log = (...parts) => {
    captured.push(parts.join(" "))
  }
  let svg = null
  try {
    svg = await tikz.default(source, { showConsole: true })
  } catch (error) {
    svg = null
  } finally {
    console.log = original
  }
  if (svg !== null && svg.includes("<svg")) {
    return { id: job.id, ok: true, svg, ms: Date.now() - started }
  }
  // The first two things printed are node-tikzjax's own "Rendering input:"
  // and the input itself; TeX speaks after them.
  const texLines = []
  for (const entry of captured.slice(2)) {
    for (const line of String(entry).split("\n")) {
      texLines.push(line)
    }
  }
  const problem = rules.texProblem(texLines)
  return { id: job.id, ok: false, ...problem, ms: Date.now() - started }
}

// Points the evaluator is tried at: function-plot only complains about a
// name it does not know when it evaluates (review S2).
const PROBE_POINTS = [0.5, 1.5, -2.5]
const SAMPLES = 50

function checkPlot(job) {
  if (functionPlot === null || loadYaml === null) {
    return { id: job.id, ok: false, problems: [{ reason: "graphEngineMissing", blockLine: 1 }] }
  }
  const parsed = rules.parseFunctionPlot(job.body, loadYaml)
  const problems = [...parsed.problems]
  const builtIn = functionPlot.$eval.builtIn
  const [xMin, xMax] = parsed.settings.bounds
  for (const line of parsed.functions) {
    if (rules.logTakesOneArgument(line.fn)) {
      problems.push({ reason: "logTakesOneArgument", blockLine: line.blockLine })
      continue
    }
    let failed = false
    for (const x of PROBE_POINTS) {
      try {
        builtIn({ fn: line.fn }, "fn", { x })
      } catch (error) {
        const message = String(error && error.message ? error.message : error)
        const unknown = message.match(/symbol "?([A-Za-z_][A-Za-z0-9_]*)"? is (?:undefined|not defined)/i)
          || message.match(/Undefined symbol ([A-Za-z_][A-Za-z0-9_]*)/i)
          || message.match(/Undefined function ([A-Za-z_][A-Za-z0-9_]*)/i)
        const notAFunction = message.match(/symbol "?([A-Za-z_][A-Za-z0-9_]*)"? must be a function/i)
        if (unknown) {
          problems.push({ reason: "unknownName", blockLine: line.blockLine, name: unknown[1] })
        } else if (notAFunction) {
          problems.push({ reason: "needsTimesSign", blockLine: line.blockLine, name: notAFunction[1] })
        } else {
          problems.push({ reason: "expressionNotUnderstood", blockLine: line.blockLine, said: message })
        }
        failed = true
        break
      }
    }
    if (failed) {
      continue
    }
    // Draws nothing at all between the bounds: `sin x` is NaN everywhere.
    let anyFinite = false
    for (let step = 0; step <= SAMPLES && !anyFinite; step += 1) {
      const x = xMin + ((xMax - xMin) * step) / SAMPLES
      try {
        const y = builtIn({ fn: line.fn }, "fn", { x })
        if (typeof y === "number" && Number.isFinite(y)) {
          anyFinite = true
        }
      } catch (error) {
        // Measured above at three points; a throw here is a point outside
        // the function's domain, which is not a problem.
      }
    }
    if (!anyFinite) {
      problems.push({ reason: "drawsNothing", blockLine: line.blockLine })
    }
  }
  const plot = {
    ...parsed.settings,
    functions: parsed.functions.map((line) => line.fn),
    lines: parsed.functions.map((line) => line.text),
  }
  return {
    id: job.id,
    ok: problems.length === 0 && parsed.functions.length > 0,
    plot,
    alt: parsed.alt,
    unknown: parsed.unknown,
    problems: parsed.functions.length === 0 && problems.length === 0
      ? [{ reason: "noFunctions", blockLine: 1 }]
      : problems,
  }
}

async function handle(message) {
  if (message.load === "tikz") {
    const started = Date.now()
    try {
      await loadTikz()
      send({ loaded: "tikz", ms: Date.now() - started })
    } catch (error) {
      send({ loaded: null, said: String(error && error.message ? error.message : error) })
    }
    return
  }
  if (message.engine === "tikz") {
    send(await drawTikz(message))
    return
  }
  if (message.engine === "functionplot") {
    send(checkPlot(message))
    return
  }
  send({ id: message.id ?? null, ok: false, reason: "unknownEngine" })
}

let queue = Promise.resolve()
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity })
input.on("line", (line) => {
  if (line.trim() === "") {
    return
  }
  let message
  try {
    message = JSON.parse(line)
  } catch (error) {
    return
  }
  queue = queue.then(() => handle(message)).catch((error) => {
    send({ id: message.id ?? null, ok: false, reason: "texSaid", said: String(error) })
  })
})
input.on("close", () => {
  queue.then(() => process.exit(0))
})
send({ ready: true })
