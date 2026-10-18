// Runnable code (#455): the thread a page's Python runs in.
//
// Laid over the pinned Pyodide files in a site's static/pyodide/
// (page_features.install_gated_assets: VENDOR_DIR/pyodide, then
// support/gated/pyodide), so it reaches a site only beside the engine it
// starts, and the image and the Windows runtime through support/ with no line
// of its own. Started by the page's script (codeRunner.inline.ts) as a MODULE
// worker: Pyodide 314 refuses a classic worker wherever the page's CSP allows
// data: scripts (#455 review B1, measured in Safari 26.6).
//
// It loads Python once, then runs each program it is sent, and talks back in
// the shapes contracts/shared-rules.json -> codeRunnerBlocks.harness.workerTalks
// names. Every address it loads from is its OWN folder: indexURL,
// packageBaseUrl and cdnUrl all point here, so the one other address inside
// pyodide.mjs (a fallback for packages from a CDN) is never used, and no
// import ever fetches anything (no loadPackagesFromImports).
//
// Before EVERY run the interpreter is put back (codeRunnerBlocks.harness,
// review S3): builtins from a copy taken at load, the three streams, the
// recursion limit, and a fresh empty folder to start in.
//
// Live input (#583, codeRunnerBlocks.liveInput): when the page is
// cross-origin isolated it sends a SharedArrayBuffer with the run (`line`).
// Each input() past the box's lines (there are none on a live page) then
// posts {type: "ask"} and WAITS in Atomics.wait until the page has written
// the student's answer; the answer is echoed through the same `out` path as
// a box line, so the transcript is byte for byte the box's. Stop is still
// terminate(), which ends a thread that is waiting (measured, #583 §0a).

import { loadPyodide } from "./pyodide.mjs"

const HERE = new URL("./", import.meta.url).href

const HARNESS = `
import builtins, linecache, os, shutil, sys, tempfile, traceback

_plantoir_builtins = dict(builtins.__dict__)
_plantoir_streams = (sys.stdin, sys.stdout, sys.stderr)
_plantoir_limit = sys.getrecursionlimit()
_plantoir_home = os.getcwd()


def _plantoir_reset():
    builtins.__dict__.clear()
    builtins.__dict__.update(_plantoir_builtins)
    sys.stdin, sys.stdout, sys.stderr = _plantoir_streams
    sys.setrecursionlimit(_plantoir_limit)
    folder = tempfile.mkdtemp(prefix="run-")
    os.chdir(folder)
    return folder


def _plantoir_run(source):
    """Run one program as main.py. Answers True when it ended with an error."""
    folder = _plantoir_reset()
    linecache.cache["main.py"] = (len(source), None, source.splitlines(True), "main.py")
    failed = False
    try:
        code = compile(source, "main.py", "exec")
    except SyntaxError as error:
        # As CPython prints one: no Traceback header, just where and what.
        traceback.print_exception(type(error), error, None)
        failed = True
    else:
        namespace = {"__name__": "__main__", "__builtins__": builtins}
        try:
            exec(code, namespace)
        except SystemExit:
            pass
        except BaseException as error:
            # Start the traceback at the program's own first frame, so its
            # line numbers are the editor's.
            frame = error.__traceback__
            while frame is not None and frame.tb_frame.f_code.co_filename != "main.py":
                frame = frame.tb_next
            traceback.print_exception(type(error), error, frame)
            failed = True
    finally:
        for stream in (sys.stdout, sys.stderr, sys.__stdout__, sys.__stderr__):
            try:
                stream.flush()
            except Exception:
                pass
        os.chdir(_plantoir_home)
        shutil.rmtree(folder, ignore_errors=True)
    return failed
`

let run = null
let lines = []
// The live line for this run (#583), or null on a page that is not isolated.
let ask = null
// End of input is sticky for the rest of a run, as past the box's last line.
let ended = false

// The worker's half of a live line (codeRunnerBlocks.liveInput.buffer): Int32
// [0] is the state (0 waiting, 1 a line is there, 2 end of input), Int32 [1]
// the line's length in bytes, and its UTF-8 bytes start at byte 8. The bytes
// are COPIED (slice) before they are decoded: Chrome's TextDecoder refuses a
// view of shared memory (#583 gotcha 1, measured in Chrome 155).
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

// The next line for input(): the box's first, then (live) the student's
// answer; null is the end of input.
function nextLine() {
  const line = lines.shift()
  if (line !== undefined) {
    return line
  }
  if (ask === null || ended) {
    return null
  }
  const answer = ask()
  if (answer === null) {
    ended = true
  }
  return answer
}

function writer(err) {
  const decoder = new TextDecoder()
  return {
    isatty: true,
    write(buffer) {
      const text = decoder.decode(buffer, { stream: true })
      if (text.length > 0) {
        self.postMessage({ type: "out", text, err })
      }
      return buffer.length
    },
  }
}

async function start() {
  const began = performance.now()
  try {
    const pyodide = await loadPyodide({
      indexURL: HERE,
      lockFileURL: HERE + "pyodide-lock.json",
      packageBaseUrl: HERE,
      cdnUrl: HERE,
    })
    pyodide.setStdout(writer(false))
    pyodide.setStderr(writer(true))
    pyodide.setStdin({
      // One line for each input(), echoed after its prompt (Q4); past the
      // last one, input() raises EOFError, as at the end of a file. On a live
      // page the line is the student's answer, asked for at that moment.
      stdin: () => {
        const line = nextLine()
        if (line === null) {
          return null
        }
        self.postMessage({ type: "out", text: line + "\n", err: false })
        return line + "\n"
      },
      autoEOF: true,
    })
    pyodide.runPython(HARNESS)
    run = pyodide.globals.get("_plantoir_run")
    self.postMessage({ type: "ready", ms: Math.round(performance.now() - began) })
  } catch (error) {
    self.postMessage({ type: "fail", message: String(error && error.message ? error.message : error) })
  }
}

const ready = start()

self.onmessage = async (event) => {
  const message = event.data || {}
  if (message.type !== "run") {
    return
  }
  await ready
  if (run === null) {
    return
  }
  lines = Array.isArray(message.stdin) ? message.stdin.slice() : []
  ask = typeof SharedArrayBuffer === "function" && message.line instanceof SharedArrayBuffer ? liveReader(message.line) : null
  ended = false
  let error = false
  try {
    error = Boolean(run(String(message.source ?? "")))
  } catch (failure) {
    error = true
    self.postMessage({ type: "out", text: String(failure && failure.message ? failure.message : failure) + "\n", err: true })
  }
  self.postMessage({ type: "done", error })
}
