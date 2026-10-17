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
      // last one, input() raises EOFError, as at the end of a file.
      stdin: () => {
        const line = lines.shift()
        if (line === undefined) {
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
  let error = false
  try {
    error = Boolean(run(String(message.source ?? "")))
  } catch (failure) {
    error = true
    self.postMessage({ type: "out", text: String(failure && failure.message ? failure.message : failure) + "\n", err: true })
  }
  self.postMessage({ type: "done", error })
}
