// Runnable code (#455): the page's half, in the student's browser.
//
// The transformer (plugins/transformers/codeRunner.ts) wrapped every runnable
// block in div.plantoir-runner around its highlighted code. This builds, on
// each wrapper: an editor (or, for `readonly`, the highlighted code as it
// is), an input box when the program reads input, Run / Stop / Reset, a
// status line and the output - in that order (Q3). It does nothing on a page
// with no wrapper, and nothing is fetched until a student presses Run (or an
// `autorun` block comes into view).
//
// The rules and the words are contracts/shared-rules.json -> codeRunnerBlocks;
// the words, the limits and the engines this site carries arrive in
// quartz/plantoir_code_runner.json, which the build writes from the contract
// on every build and esbuild bundles in here. The language table is
// codeRunnerRule.ts's, shared with the transformer.
//
// THE RUNTIME SEAM: a block's data-runner-runtime picks a class from
// RUNTIMES. PyodideRuntime, the only one, starts static/<engine>/<worker> as
// a module worker (#455 review B1) on the first Run on a page and keeps it
// warm for the rest of the visit; one program runs on a page at a time (Q2);
// Stop ends the thread (the only way to stop Python mid-loop without
// cross-origin isolation, which a folder publish cannot have). A language
// that joins the table adds a class here.

import settings from "../../plantoir_code_runner.json"
import { FullSlug, getFullSlug, pathToRoot } from "../../util/path"
import { filled, fnv1a, languageFor, RunnerLanguage } from "../../plugins/transformers/codeRunnerRule"

type Words = Record<string, string>
type Limits = {
  outputCharacters: number
  loadSeconds: number
  debounceMilliseconds: number
  editorLines: number
  indent: string
}
const WORDS = ((settings as { words?: Words }).words ?? {}) as Words
const LIMITS = ((settings as { limits?: Limits }).limits ?? {
  outputCharacters: 100000,
  loadSeconds: 45,
  debounceMilliseconds: 400,
  editorLines: 24,
  indent: "    ",
}) as Limits

// Why a runtime could not run a program: each is a key in the words.
type Refusal = "couldNotLoad" | "engineMissing" | "stopped"

type RunHandlers = {
  out: (text: string, err: boolean) => void
  done: (error: boolean) => void
}

interface CodeRuntime {
  readonly ready: boolean
  prepare(): Promise<void>
  run(source: string, stdin: string[], handlers: RunHandlers): void
  terminate(): void
}

// Python, by Pyodide, in a module worker the site serves itself.
class PyodideRuntime implements CodeRuntime {
  ready = false
  private worker: Worker | null = null
  private preparing: Promise<void> | null = null
  private refuse: ((reason: Refusal) => void) | null = null
  private handlers: RunHandlers | null = null

  constructor(private readonly workerURL: string) {}

  prepare(): Promise<void> {
    if (this.ready && this.worker !== null) {
      return Promise.resolve()
    }
    if (this.preparing !== null) {
      return this.preparing
    }
    this.preparing = new Promise<void>((resolve, reject) => {
      let settled = false
      const settle = (reason: Refusal | null) => {
        if (settled) {
          return
        }
        settled = true
        window.clearTimeout(watchdog)
        this.refuse = null
        this.preparing = null
        if (reason === null) {
          this.ready = true
          resolve()
        } else {
          this.stopThread()
          reject(reason)
        }
      }
      this.refuse = (reason) => settle(reason)
      // A server that sends .wasm with the wrong type, or a CSP with no wasm
      // permission, never says anything: the watchdog does (review S1).
      const watchdog = window.setTimeout(() => settle("couldNotLoad"), LIMITS.loadSeconds * 1000)
      let worker: Worker
      try {
        worker = new Worker(this.workerURL, { type: "module" })
      } catch {
        settle("couldNotLoad")
        return
      }
      this.worker = worker
      worker.onmessage = (event: MessageEvent) => {
        const message = event.data ?? {}
        if (message.type === "ready") {
          settle(null)
        } else if (message.type === "fail") {
          settle("couldNotLoad")
        } else if (message.type === "out") {
          this.handlers?.out(String(message.text ?? ""), Boolean(message.err))
        } else if (message.type === "done") {
          const handlers = this.handlers
          this.handlers = null
          handlers?.done(Boolean(message.error))
        }
      }
      worker.onerror = (event: Event) => {
        event.preventDefault()
        if (settled) {
          return
        }
        // A worker that could not start says nothing about why, and a 404
        // looks exactly like a wrong type: one request tells them apart.
        fetch(this.workerURL, { method: "HEAD", cache: "no-store" })
          .then((response) => settle(response.status === 404 ? "engineMissing" : "couldNotLoad"))
          .catch(() => settle("couldNotLoad"))
      }
    })
    return this.preparing
  }

  run(source: string, stdin: string[], handlers: RunHandlers) {
    this.handlers = handlers
    this.worker?.postMessage({ type: "run", source, stdin })
  }

  private stopThread() {
    this.worker?.terminate()
    this.worker = null
    this.ready = false
  }

  terminate() {
    this.handlers = null
    if (this.refuse !== null) {
      this.refuse("stopped")
    }
    this.stopThread()
  }
}

const RUNTIMES: Record<string, (workerURL: string) => CodeRuntime> = {
  pyodide: (workerURL) => new PyodideRuntime(workerURL),
}

// ---- One page visit ------------------------------------------------------------

type Block = {
  wrapper: HTMLElement
  language: RunnerLanguage
  run: (automatic: boolean) => void
  // `startNext` false when another block is about to run: a waiting autorun
  // must not start in between.
  stopFor: (word: string, startNext: boolean) => void
  flush: () => void
}

let runtimes = new Map<string, CodeRuntime>()
let running: Block | null = null
let waitingAutoruns: Block[] = []

function word(key: string, language: RunnerLanguage): string {
  return filled(WORDS[key] ?? "", language)
}

function siteRoot(): string {
  return pathToRoot(getFullSlug(window) as FullSlug)
}

function runtimeFor(language: RunnerLanguage): CodeRuntime | null {
  const existing = runtimes.get(language.engine)
  if (existing !== undefined) {
    return existing
  }
  const make = RUNTIMES[language.runtime]
  if (make === undefined) {
    return null
  }
  const url = new URL(`${siteRoot()}/static/${language.engine}/${language.worker}`, location.href).href
  const runtime = make(url)
  runtimes.set(language.engine, runtime)
  return runtime
}

function finished(block: Block, startNext: boolean) {
  if (running === block) {
    running = null
  }
  if (!startNext) {
    return
  }
  const next = waitingAutoruns.shift()
  if (next !== undefined) {
    next.run(true)
  }
}

// Growing code inside an open callout: Quartz fixed the callout's height when
// it was opened (callout.inline.ts), which would clip the editor. Lift it.
function freeOpenCallouts(element: HTMLElement) {
  let parent = element.parentElement
  while (parent !== null) {
    if (parent.classList.contains("callout") && !parent.classList.contains("is-collapsed")) {
      parent.style.maxHeight = ""
    }
    parent = parent.parentElement
  }
}

function storageGet(key: string): string | null {
  try {
    return window.localStorage.getItem(key)
  } catch {
    return null
  }
}

function storageSet(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value)
  } catch {
    // A browser that refuses storage simply forgets.
  }
}

function storageRemove(key: string) {
  try {
    window.localStorage.removeItem(key)
  } catch {
    // As above.
  }
}

function element<K extends keyof HTMLElementTagNameMap>(tag: K, className: string): HTMLElementTagNameMap[K] {
  const made = document.createElement(tag)
  made.className = className
  return made
}

function linesOf(text: string): number {
  return text.split("\n").length
}

function build(wrapper: HTMLElement, base: string): Block | null {
  const language = languageFor(wrapper.dataset.runnerLanguage ?? "")
  if (language === null) {
    return null
  }
  wrapper.dataset.built = "true"
  const flags = (wrapper.dataset.runnerFlags ?? "").split(/\s+/).filter((flag) => flag.length > 0)
  const original = wrapper.dataset.original ?? ""
  const readonly = flags.includes("readonly") || !language.editable
  const id = wrapper.dataset.runnerId ?? ""
  const key = `plantoir:runner:${base}:${id}`
  const inputPattern = new RegExp(language.inputPattern)

  for (const child of Array.from(wrapper.children)) {
    child.classList.add("plantoir-runner-original")
  }
  wrapper.classList.add("plantoir-runner-live")
  if (readonly) {
    wrapper.classList.add("plantoir-runner-readonly")
  }

  // The editor, or nothing for readonly (its highlighted code stays).
  let editor: HTMLTextAreaElement | null = null
  let saidOnLoad = ""
  if (!readonly) {
    editor = element("textarea", "plantoir-runner-editor")
    editor.spellcheck = false
    editor.setAttribute("autocapitalize", "off")
    editor.setAttribute("autocorrect", "off")
    editor.setAttribute("autocomplete", "off")
    editor.setAttribute("wrap", "off")
    editor.setAttribute("aria-label", word("editorLabel", language))
    let code = original
    const saved = storageGet(key)
    if (saved !== null) {
      try {
        const parsed = JSON.parse(saved) as { originalHash?: string; code?: string }
        if (parsed.originalHash === fnv1a(original) && typeof parsed.code === "string") {
          code = parsed.code
        } else {
          // The teacher changed the code since these edits were saved: put
          // them aside, show the new version, and say so - once, because the
          // live key is gone (codeRunnerBlocks.storage, S4).
          storageSet(`${key}:set-aside`, saved)
          storageRemove(key)
          saidOnLoad = word("teacherChangedIt", language)
        }
      } catch {
        storageRemove(key)
      }
    }
    editor.value = code
    wrapper.appendChild(editor)
  }

  const inputBox = element("div", "plantoir-runner-input")
  const inputLabel = element("label", "plantoir-runner-input-label")
  const input = element("textarea", "plantoir-runner-input-lines")
  input.rows = 3
  input.spellcheck = false
  input.setAttribute("autocapitalize", "off")
  input.setAttribute("autocorrect", "off")
  input.setAttribute("autocomplete", "off")
  input.id = `plantoir-runner-input-${Math.random().toString(36).slice(2)}`
  inputLabel.htmlFor = input.id
  inputLabel.textContent = word("inputLabel", language)
  inputBox.append(inputLabel, input)
  wrapper.appendChild(inputBox)

  const controls = element("div", "plantoir-runner-controls")
  const runButton = element("button", "plantoir-runner-run")
  runButton.type = "button"
  runButton.textContent = word("run", language)
  const stopButton = element("button", "plantoir-runner-stop")
  stopButton.type = "button"
  stopButton.textContent = word("stop", language)
  stopButton.disabled = true
  controls.append(runButton, stopButton)
  let resetButton: HTMLButtonElement | null = null
  if (editor !== null) {
    resetButton = element("button", "plantoir-runner-reset")
    resetButton.type = "button"
    resetButton.textContent = word("reset", language)
    controls.appendChild(resetButton)
  }
  wrapper.appendChild(controls)

  const status = element("p", "plantoir-runner-status")
  status.setAttribute("role", "status")
  status.setAttribute("aria-live", "polite")
  status.textContent = saidOnLoad
  wrapper.appendChild(status)

  const output = element("pre", "plantoir-runner-output")
  output.setAttribute("aria-label", word("outputLabel", language))
  output.hidden = true
  wrapper.appendChild(output)

  // What prints when the student has edited the code: a textarea's typed
  // value is not part of a printed (or cloned) page (codeRunnerBlocks.print).
  const printCopy = element("pre", "plantoir-runner-print")
  printCopy.setAttribute("aria-hidden", "true")
  wrapper.appendChild(printCopy)

  const code = () => (editor !== null ? editor.value : original)

  const syncInputAndPrint = () => {
    const current = code()
    inputBox.hidden = !(flags.includes("stdin") || inputPattern.test(current))
    printCopy.textContent = current
    wrapper.classList.toggle("plantoir-runner-edited", current !== original)
  }

  const fit = () => {
    if (editor === null) {
      return
    }
    const wanted = Math.max(1, Math.min(LIMITS.editorLines, linesOf(editor.value)))
    if (editor.rows !== wanted) {
      editor.rows = wanted
      freeOpenCallouts(wrapper)
    }
  }

  // Saved edits: written a moment after the last keystroke, and at once
  // when the page is left.
  let saveTimer: number | null = null
  const save = () => {
    if (saveTimer !== null) {
      window.clearTimeout(saveTimer)
      saveTimer = null
    }
    if (editor === null) {
      return
    }
    if (editor.value === original) {
      storageRemove(key)
    } else {
      storageSet(key, JSON.stringify({ originalHash: fnv1a(original), code: editor.value }))
    }
  }
  const flush = () => {
    if (saveTimer !== null) {
      save()
    }
    syncInputAndPrint()
  }

  // The output, gathered once per animation frame, and its cap (Q5).
  let pending: { text: string; err: boolean }[] = []
  let frame: number | null = null
  let printed = 0
  const paint = () => {
    frame = null
    for (const chunk of pending) {
      const last = output.lastChild
      if (chunk.err) {
        if (last instanceof HTMLSpanElement) {
          last.textContent += chunk.text
        } else {
          const span = element("span", "plantoir-runner-err")
          span.textContent = chunk.text
          output.appendChild(span)
        }
      } else if (last !== null && last.nodeType === Node.TEXT_NODE) {
        ;(last as Text).appendData(chunk.text)
      } else {
        output.appendChild(document.createTextNode(chunk.text))
      }
    }
    pending = []
    if (output.childNodes.length > 0) {
      output.hidden = false
    }
  }
  const clearOutput = () => {
    if (frame !== null) {
      window.cancelAnimationFrame(frame)
      frame = null
    }
    pending = []
    printed = 0
    output.textContent = ""
    output.hidden = true
  }

  let busy = false
  const setBusy = (now: boolean) => {
    busy = now
    runButton.disabled = now
    stopButton.disabled = !now
  }

  const block: Block = {
    wrapper,
    language,
    run: () => undefined,
    stopFor: () => undefined,
    flush,
  }

  const end = (statusWord: string, startNext = true) => {
    if (frame !== null) {
      window.cancelAnimationFrame(frame)
    }
    paint()
    status.textContent = statusWord
    setBusy(false)
    finished(block, startNext)
  }

  block.run = (automatic: boolean) => {
    if (busy) {
      return
    }
    if (location.protocol === "file:") {
      status.textContent = word("needsWebAddress", language)
      return
    }
    if (automatic && running !== null && running !== block) {
      // Autoruns wait their turn (N4).
      if (!waitingAutoruns.includes(block)) {
        waitingAutoruns.push(block)
      }
      return
    }
    if (running !== null && running !== block) {
      running.stopFor(word("stoppedForAnother", running.language), false)
    }
    const runtime = runtimeFor(language)
    if (runtime === null) {
      status.textContent = word("couldNotLoad", language)
      return
    }
    running = block
    flush()
    clearOutput()
    setBusy(true)
    status.textContent = runtime.ready ? word("running", language) : word("loading", language)
    let lines = input.value.split("\n")
    if (input.value.endsWith("\n")) {
      lines = lines.slice(0, -1)
    }
    if (inputBox.hidden || input.value === "") {
      lines = []
    }
    runtime
      .prepare()
      .then(() => {
        if (running !== block) {
          return
        }
        status.textContent = word("running", language)
        runtime.run(code(), lines, {
          out: (text, err) => {
            if (running !== block) {
              return
            }
            printed += text.length
            pending.push({ text, err })
            if (printed > LIMITS.outputCharacters) {
              runtime.terminate()
              end(word("outputTooLong", language))
              return
            }
            if (frame === null) {
              frame = window.requestAnimationFrame(paint)
            }
          },
          done: (error) => {
            if (running !== block) {
              return
            }
            end(error ? word("finishedWithError", language) : word("finished", language))
          },
        })
      })
      .catch((reason: Refusal) => {
        if (running !== block || reason === "stopped") {
          return
        }
        end(word(reason, language))
      })
  }

  block.stopFor = (said: string, startNext: boolean) => {
    if (!busy) {
      return
    }
    runtimeFor(language)?.terminate()
    end(said, startNext)
  }

  runButton.addEventListener("click", () => block.run(false))
  stopButton.addEventListener("click", () => block.stopFor(word("stopped", language), true))
  resetButton?.addEventListener("click", () => {
    if (editor === null) {
      return
    }
    editor.value = original
    if (saveTimer !== null) {
      window.clearTimeout(saveTimer)
      saveTimer = null
    }
    storageRemove(key)
    clearOutput()
    status.textContent = ""
    syncInputAndPrint()
    fit()
  })

  wrapper.addEventListener("keydown", (event: KeyboardEvent) => {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && !event.isComposing) {
      event.preventDefault()
      block.run(false)
    }
  })

  if (editor !== null) {
    const area = editor
    let escapeArmed = false
    area.addEventListener("input", () => {
      fit()
      syncInputAndPrint()
      if (saveTimer !== null) {
        window.clearTimeout(saveTimer)
      }
      saveTimer = window.setTimeout(save, LIMITS.debounceMilliseconds)
    })
    area.addEventListener("focus", fit)
    area.addEventListener("blur", () => {
      escapeArmed = false
    })
    area.addEventListener("keydown", (event: KeyboardEvent) => {
      if (event.isComposing) {
        return
      }
      if (event.key === "Escape") {
        // Escape, then Tab, leaves the editor (the keyboard-trap rule).
        escapeArmed = true
        return
      }
      if (event.key !== "Tab" || event.metaKey || event.ctrlKey || event.altKey) {
        escapeArmed = false
        return
      }
      if (escapeArmed) {
        escapeArmed = false
        return
      }
      event.preventDefault()
      indent(area, event.shiftKey)
    })
  }

  syncInputAndPrint()
  fit()
  freeOpenCallouts(wrapper)

  if (flags.includes("autorun")) {
    const watcher = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            watcher.disconnect()
            block.run(true)
            return
          }
        }
      },
      { threshold: 0.25 },
    )
    watcher.observe(wrapper)
    window.addCleanup(() => watcher.disconnect())
  }
  return block
}

// Tab puts four spaces in (or indents every selected line); Shift-Tab takes
// up to four off each line it touches. Through insertText where the browser
// has it, so the edit can be undone.
function indent(area: HTMLTextAreaElement, outdent: boolean) {
  const unit = LIMITS.indent
  const text = area.value
  const start = area.selectionStart
  const end = area.selectionEnd
  if (!outdent && start === end) {
    replace(area, start, end, unit, start + unit.length, start + unit.length)
    return
  }
  const lineStart = text.lastIndexOf("\n", start - 1) + 1
  let lineEnd = text.indexOf("\n", end > start && text[end - 1] === "\n" ? end - 1 : end)
  if (lineEnd < 0) {
    lineEnd = text.length
  }
  const lines = text.slice(lineStart, lineEnd).split("\n")
  let firstShift = 0
  let totalShift = 0
  const changed: string[] = []
  lines.forEach((line, index) => {
    let shift: number
    let next: string
    if (outdent) {
      let take = 0
      while (take < unit.length && line[take] === " ") {
        take += 1
      }
      next = line.slice(take)
      shift = -take
    } else {
      next = unit + line
      shift = unit.length
    }
    if (index === 0) {
      firstShift = shift
    }
    totalShift += shift
    changed.push(next)
  })
  const replacement = changed.join("\n")
  const newStart = Math.max(lineStart, start + firstShift)
  const newEnd = Math.max(newStart, end + totalShift)
  replace(area, lineStart, lineEnd, replacement, start === end ? newStart : newStart, newEnd)
}

function replace(area: HTMLTextAreaElement, from: number, to: number, text: string, selectFrom: number, selectTo: number) {
  area.focus()
  area.setSelectionRange(from, to)
  let done = false
  try {
    done = document.execCommand("insertText", false, text)
  } catch {
    done = false
  }
  if (!done || area.value.slice(from, from + text.length) !== text) {
    area.setRangeText(text, from, to, "end")
    area.dispatchEvent(new Event("input", { bubbles: true }))
  }
  area.setSelectionRange(selectFrom, selectTo)
}

document.addEventListener("nav", () => {
  const wrappers = Array.from(document.querySelectorAll<HTMLElement>(".plantoir-runner:not([data-built])"))
  if (wrappers.length === 0) {
    return
  }
  const base = new URL(siteRoot() + "/", location.href).pathname
  const blocks: Block[] = []
  for (const wrapper of wrappers) {
    const block = build(wrapper, base)
    if (block !== null) {
      blocks.push(block)
    }
  }
  const flushAll = () => {
    for (const block of blocks) {
      block.flush()
    }
  }
  // The Print button (print.inline.ts) waits for the print copies to be
  // brought up to date before it makes the handout.
  const hooks = window as unknown as { plantoirPrint?: { prepare: Array<() => Promise<void>> } }
  if (!hooks.plantoirPrint) {
    hooks.plantoirPrint = { prepare: [] }
  }
  const prepareForPrint = async () => flushAll()
  hooks.plantoirPrint.prepare.push(prepareForPrint)
  window.addEventListener("pagehide", flushAll)
  window.addEventListener("beforeprint", flushAll)
  window.addCleanup(() => {
    flushAll()
    window.removeEventListener("pagehide", flushAll)
    window.removeEventListener("beforeprint", flushAll)
    const list = hooks.plantoirPrint?.prepare ?? []
    const at = list.indexOf(prepareForPrint)
    if (at >= 0) {
      list.splice(at, 1)
    }
    // Leaving the page ends its programs and their thread.
    for (const runtime of runtimes.values()) {
      runtime.terminate()
    }
    runtimes = new Map()
    running = null
    waitingAutoruns = []
  })
})
