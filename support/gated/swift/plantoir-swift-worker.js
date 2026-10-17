// Runnable Swift (#493): the thread a page's Swift programs run in.
//
// Copied into a site's static/swift/ beside plantoir-wasi.mjs, only when a
// page students can see has a ```swift run block (page_features'
// install_gated_assets; the Swift row's engine is this overlay alone, because
// its "engine" - each block's compiled program - is made per course, in
// static/swift-wasm/). Started by the page's script (codeRunner.inline.ts,
// SwiftWasmRuntime) as a module worker, like Python's.
//
// Each Run sends the address of the block's program and the input box's
// lines. The program is fetched once per visit and compiled from its bytes -
// never compileStreaming, which refuses a .wasm a host sends with the wrong
// type (review N4: a self-hosted folder often does) - and run in a FRESH
// instance every time (a Swift program runs once). Talks back in the shapes
// contracts/shared-rules.json -> codeRunnerBlocks.swift.workerTalks names.

import { runProgram } from "./plantoir-wasi.mjs"

const modules = new Map()

async function moduleFor(url) {
  const known = modules.get(url)
  if (known !== undefined) {
    return known
  }
  const response = await fetch(url)
  if (!response.ok) {
    const failure = new Error(String(response.status))
    failure.missing = response.status === 404
    throw failure
  }
  const module = await WebAssembly.compile(await response.arrayBuffer())
  modules.set(url, module)
  return module
}

self.postMessage({ type: "ready", ms: 0 })

self.onmessage = async (event) => {
  const message = event.data || {}
  if (message.type !== "run") {
    return
  }
  let module
  try {
    module = await moduleFor(String(message.wasm ?? ""))
  } catch (failure) {
    self.postMessage({ type: "fail", reason: failure && failure.missing ? "missing" : "couldNotLoad" })
    return
  }
  self.postMessage({ type: "started" })
  const lines = Array.isArray(message.stdin) ? message.stdin.slice() : []
  const out = (text, err) => self.postMessage({ type: "out", text, err })
  try {
    const result = await runProgram(module, { lines, out })
    if (result.crashed) {
      self.postMessage({ type: "done", error: true, crashed: true })
    } else {
      self.postMessage({ type: "done", error: result.exit !== 0, exitCode: result.exit })
    }
  } catch (failure) {
    // Anything else (a program asking for something no browser gives it):
    // said in the output, and the run ends with an error.
    out(String(failure && failure.message ? failure.message : failure) + "\n", true)
    self.postMessage({ type: "done", error: true, crashed: true })
  }
}
