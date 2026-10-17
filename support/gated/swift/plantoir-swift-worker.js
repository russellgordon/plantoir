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
//
// Live input (#583, codeRunnerBlocks.liveInput): on a cross-origin isolated
// page the run carries a SharedArrayBuffer (`line`), and each readLine()
// past the box's lines posts {type: "ask"} and waits for the student's
// answer - the same reader, buffer layout and copy-before-decode rule as
// Python's worker (written once in each overlay, because support/gated/swift
// and support/gated/pyodide are carried independently).

import { runProgram } from "./plantoir-wasi.mjs"

const modules = new Map()

// The worker's half of a live line (codeRunnerBlocks.liveInput.buffer): Int32
// [0] is the state (0 waiting, 1 a line is there, 2 end of input), Int32 [1]
// the line's length in bytes, and its UTF-8 bytes start at byte 8. Copied
// (slice) before they are decoded: Chrome refuses to decode shared memory.
function liveReader(buffer) {
  const control = new Int32Array(buffer, 0, 2)
  const data = new Uint8Array(buffer, 8)
  return () => {
    Atomics.store(control, 0, 0)
    self.postMessage({ type: "ask" })
    while (Atomics.load(control, 0) === 0) {
      Atomics.wait(control, 0, 0)
    }
    if (Atomics.load(control, 0) !== 1) {
      return null
    }
    const length = Atomics.load(control, 1)
    return new TextDecoder().decode(data.slice(0, length))
  }
}

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
  const live = typeof SharedArrayBuffer === "function" && message.line instanceof SharedArrayBuffer
  const ask = live ? liveReader(message.line) : null
  try {
    const result = await runProgram(module, { lines, out, ask })
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
