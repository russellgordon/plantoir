// Runnable Swift (#493): run every swift-gate/ fragment's compiled program
// through the site's own WASI shim (support/gated/swift/plantoir-wasi.mjs) in
// Node, and check what swift-gate/expected.json says of each - the standard
// library compile.py chose, the output against `.expected`, the trap and its
// `Fatal error:` line - plus four checks of the shim itself:
//
//  * the transcript: input lines are echoed straight after the prompt
//    (review S6), one line per read;
//  * the MUST-FAIL (spike G5): with every right on fds 0-2 (seek and tell
//    included), Embedded Swift's `Fatal error:` line is LOST on a trap, and
//    with the shim's rights it is kept - so the rule cannot be dropped
//    without this check going red;
//  * a program that grows a list for ever traps at the memory cap quickly;
//  * a program that recurses for ever ends as a crash, not a hang.
//
// Kept beside the browser checks, out of scripts/ and the image: it needs a
// Node 22 on the Mac. verify.sh runs it after compiling the fragments in the
// Swift image:
//
//   node browser-checks/wasi_run.mjs <swift-gate folder> <folder of NN-name.wasm and NN-name.json>
//
// Prints one table row per fragment (for the closing comment), then OK or the
// failures.

import { readFileSync, existsSync } from "node:fs"
import { join } from "node:path"
import { runProgram, ALL_RIGHTS } from "../support/gated/swift/plantoir-wasi.mjs"

const [gate, compiled] = process.argv.slice(2)
if (!gate || !compiled) {
  console.error("usage: node wasi_run.mjs <swift-gate folder> <compiled folder>")
  process.exit(2)
}

const expected = JSON.parse(readFileSync(join(gate, "expected.json"), "utf-8")).fragments
const failures = []
const rows = []

function linesOf(name) {
  const path = join(gate, `${name}.stdin`)
  if (!existsSync(path)) return []
  const text = readFileSync(path, "utf-8")
  if (text === "") return []
  const lines = text.split("\n")
  if (text.endsWith("\n")) lines.pop()
  return lines
}

async function run(name, options = {}) {
  const module = await WebAssembly.compile(readFileSync(join(compiled, `${name}.wasm`)))
  let stdout = ""
  let stderr = ""
  const began = performance.now()
  const result = await runProgram(module, {
    lines: linesOf(name),
    echo: options.echo ?? false,
    rights: options.rights,
    out: (text, err) => {
      if (err) stderr += text
      else stdout += text
    },
  })
  return { result, stdout, stderr, seconds: (performance.now() - began) / 1000 }
}

for (const [name, wants] of Object.entries(expected)) {
  const info = existsSync(join(compiled, `${name}.json`)) ? JSON.parse(readFileSync(join(compiled, `${name}.json`), "utf-8")) : null
  if (info === null || !info.ok) {
    failures.push(`${name}: not compiled (${info ? info.reason : "no entry"})`)
    rows.push(`| ${name} | - | - | - | not compiled |`)
    continue
  }
  if (info.sdk !== wants.sdk) {
    failures.push(`${name}: compiled with the ${info.sdk} library, expected ${wants.sdk}`)
  }
  let outcome
  try {
    outcome = await run(name)
  } catch (error) {
    failures.push(`${name}: ${error}`)
    continue
  }
  const { result, stdout, stderr, seconds } = outcome
  const want = readFileSync(join(gate, `${name}.expected`), "utf-8")
  let verdict = "MATCH"
  if (wants.trap) {
    if (!result.crashed) {
      failures.push(`${name}: expected a trap, got exit ${result.exit}`)
      verdict = "NO TRAP"
    } else if (wants.fatal && !(stdout + stderr).includes(wants.fatal)) {
      failures.push(`${name}: trapped without "${wants.fatal}" in its output`)
      verdict = "TRAP, NO FATAL LINE"
    } else if (!stdout.startsWith(want)) {
      failures.push(`${name}: the output before the trap is ${JSON.stringify(stdout)}`)
      verdict = "DIFF"
    } else {
      verdict = `TRAP (${result.error.constructor.name})`
    }
    if (wants.withinSeconds && seconds > wants.withinSeconds) {
      failures.push(`${name}: took ${seconds.toFixed(2)} s to trap, more than ${wants.withinSeconds}`)
    }
  } else if (result.crashed || result.exit !== 0) {
    failures.push(`${name}: ${result.crashed ? "trapped: " + result.error : "exit " + result.exit}`)
    verdict = "FAILED"
  } else if (stdout !== want) {
    failures.push(`${name}: output differs:\n${stdout}\n--- expected ---\n${want}`)
    verdict = "DIFF"
  }
  const imports = WebAssembly.Module.imports(await WebAssembly.compile(readFileSync(join(compiled, `${name}.wasm`)))).length
  rows.push(`| ${name} | ${info.sdk} | ${info.bytes.toLocaleString("en-CA")} | ${imports} | ${verdict} (${seconds.toFixed(2)} s) |`)
}

// The transcript (S6): each input line straight after its prompt.
{
  const { stdout } = await run("01-greeting", { echo: true })
  const lines = linesOf("01-greeting")
  const want = "What is your name?\n" + lines[0] + "\nHello, "
  if (!stdout.startsWith(want)) failures.push(`the transcript does not echo the input after the prompt: ${JSON.stringify(stdout.slice(0, 60))}`)
}

// The must-fail (G5): every right, seek and tell included, loses the line.
{
  const kept = await run("10-out-of-range")
  const lost = await run("10-out-of-range", { rights: ALL_RIGHTS })
  const fatal = expected["10-out-of-range"].fatal
  if (!(kept.stdout + kept.stderr).includes(fatal)) failures.push("G5: the Fatal-error line is missing with the shim's rights")
  if ((lost.stdout + lost.stderr).includes(fatal)) {
    failures.push("G5 must-fail did not fail: with seek and tell rights the Fatal-error line was still kept, so the check proves nothing")
  }
  rows.push(`| G5 must-fail | rights with seek and tell | - | - | Fatal-error line ${(lost.stdout + lost.stderr).includes(fatal) ? "KEPT (check broken)" : "lost, as it must be"} |`)
}

console.log("| fragment | library | bytes | imports | result |")
console.log("|---|---|---|---|---|")
for (const row of rows) console.log(row)
for (const failure of failures) console.log("FAIL " + failure)
if (failures.length > 0) process.exit(1)
console.log(`OK: ${Object.keys(expected).length} fragments and the shim's four checks`)
