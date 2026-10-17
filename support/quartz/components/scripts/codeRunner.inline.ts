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
// RUNTIMES. PyodideRuntime starts static/<engine>/<worker> as
// a module worker (#455 review B1) on the first Run on a page and keeps it
// warm for the rest of the visit; one program runs on a page at a time (Q2);
// Stop ends the thread (the only way to stop Python mid-loop without
// cross-origin isolation, which a folder publish cannot have). A language
// that joins the table adds a class here: SwiftWasmRuntime (#493) runs each
// Swift block's prebuilt program in a thread of its own the same way.
//
// LIVE INPUT (#583, codeRunnerBlocks.liveInput): where the page is
// cross-origin isolated (the host sent COOP and COEP for it - isolation
// rules), a run carries a SharedArrayBuffer and the program asks for each
// line as it reads it: the answer is typed into ONE field at the end of the
// output, kept for the whole run (so an iPad's keyboard stays up between
// prompts), and Return hands it over while the program waits. Where the page
// is not isolated, the input box is filled before Run, as in 1.8.0, with one
// line saying so (words.inputAhead). The transcript is the same either way:
// the worker echoes the line after the prompt in both.

import settings from "../../plantoir_code_runner.json"
import { FullSlug, getFullSlug, pathToRoot } from "../../util/path"
import { filled, fnv1a, languageFor, RunnerLanguage } from "../../plugins/transformers/codeRunnerRule"
import { colourLines, ColouredLine, lineHTML, reusePlan } from "./codeRunnerColour"

type Words = Record<string, string>
type Limits = {
  outputCharacters: number
  loadSeconds: number
  debounceMilliseconds: number
  editorLines: number
  indent: string
  answerCharacters: number
}
const WORDS = ((settings as { words?: Words }).words ?? {}) as Words
const LIMITS = ((settings as { limits?: Limits }).limits ?? {
  outputCharacters: 100000,
  loadSeconds: 45,
  debounceMilliseconds: 400,
  editorLines: 24,
  indent: "    ",
  answerCharacters: 4096,
}) as Limits
// A settings file written before #583 has no answerCharacters.
const ANSWER_CHARACTERS = LIMITS.answerCharacters ?? 4096

// Why a runtime could not run a program: each is a key in the words.
type Refusal = "couldNotLoad" | "engineMissing" | "stopped"

type RunHandlers = {
  out: (text: string, err: boolean) => void
  // `said`, when given, is the status line's words (a Swift program that
  // crashed or gave an exit code); otherwise finished / finishedWithError.
  done: (error: boolean, said?: string) => void
  // A prebuilt program has been fetched and is about to run (#493).
  started?: () => void
  // Live input (#583): the program is waiting for a line.
  ask?: () => void
}

interface CodeRuntime {
  readonly ready: boolean
  prepare(): Promise<void>
  // `program` is a prebuilt block's compiled program's address (#493); a
  // runtime that runs the source as written ignores it. `line` is the live
  // line's shared buffer on an isolated page (#583), or undefined.
  run(source: string, stdin: string[], handlers: RunHandlers, program?: string, line?: SharedArrayBuffer): void
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
        } else if (message.type === "ask") {
          this.handlers?.ask?.()
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

  run(source: string, stdin: string[], handlers: RunHandlers, _program?: string, line?: SharedArrayBuffer) {
    this.handlers = handlers
    this.worker?.postMessage({ type: "run", source, stdin, line })
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

// Swift (#493), compiled ahead of time by the build: each block's program is
// a small WebAssembly file (static/swift-wasm/<key>.wasm), run by
// static/swift/plantoir-swift-worker.js under its hand-rolled WASI shim
// (plantoir-wasi.mjs). The thread starts at once (there is no engine to
// load); each Run sends the program's address, and the thread fetches it once
// per visit and runs a fresh instance. Stop ends the thread, as for Python.
class SwiftWasmRuntime implements CodeRuntime {
  ready = false
  private worker: Worker | null = null
  private preparing: Promise<void> | null = null
  private refuse: ((reason: Refusal) => void) | null = null
  private handlers: RunHandlers | null = null
  private fetching: number | null = null

  constructor(
    private readonly workerURL: string,
    private readonly language: RunnerLanguage,
  ) {}

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
        } else if (message.type === "started") {
          this.stopWatching()
          this.handlers?.started?.()
        } else if (message.type === "out") {
          this.handlers?.out(String(message.text ?? ""), Boolean(message.err))
        } else if (message.type === "ask") {
          this.handlers?.ask?.()
        } else if (message.type === "fail") {
          // The program could not be fetched (missing: the site has no such
          // file) or compiled (a CSP that allows no wasm).
          this.finish(true, word(message.reason === "missing" ? "notReady" : "couldNotLoad", this.language))
        } else if (message.type === "done") {
          let said: string | undefined = undefined
          if (message.crashed) {
            said = word("crashed", this.language)
          } else if (typeof message.exitCode === "number" && message.exitCode !== 0) {
            said = word("exitCode", this.language).split("{code}").join(String(message.exitCode))
          }
          this.finish(Boolean(message.error), said)
        }
      }
      worker.onerror = (event: Event) => {
        event.preventDefault()
        if (settled) {
          return
        }
        fetch(this.workerURL, { method: "HEAD", cache: "no-store" })
          .then((response) => settle(response.status === 404 ? "engineMissing" : "couldNotLoad"))
          .catch(() => settle("couldNotLoad"))
      }
    })
    return this.preparing
  }

  private finish(error: boolean, said?: string) {
    this.stopWatching()
    const handlers = this.handlers
    this.handlers = null
    handlers?.done(error, said)
  }

  private stopWatching() {
    if (this.fetching !== null) {
      window.clearTimeout(this.fetching)
      this.fetching = null
    }
  }

  run(_source: string, stdin: string[], handlers: RunHandlers, program?: string, line?: SharedArrayBuffer) {
    this.handlers = handlers
    // Fetching and compiling the program is watched like loading an engine:
    // a host that never answers ends in couldNotLoad, not "Loading..." for ever.
    this.stopWatching()
    this.fetching = window.setTimeout(() => {
      this.fetching = null
      this.stopThread()
      this.finish(true, word("couldNotLoad", this.language))
    }, LIMITS.loadSeconds * 1000)
    this.worker?.postMessage({ type: "run", wasm: program ?? "", stdin, line })
  }

  private stopThread() {
    this.worker?.terminate()
    this.worker = null
    this.ready = false
  }

  terminate() {
    this.stopWatching()
    this.handlers = null
    if (this.refuse !== null) {
      this.refuse("stopped")
    }
    this.stopThread()
  }
}

const RUNTIMES: Record<string, (workerURL: string, language: RunnerLanguage) => CodeRuntime> = {
  pyodide: (workerURL) => new PyodideRuntime(workerURL),
  "swift-wasm": (workerURL, language) => new SwiftWasmRuntime(workerURL, language),
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
  const runtime = make(url, language)
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

// ---- Live input (#583, codeRunnerBlocks.liveInput) ------------------------------

// Can this document stop a program and ask? Fixed when the document is made:
// a page reached by the site's own links across the isolation line is loaded
// whole (isolation.spa), so it stays true or false for the page's life.
function canAskLive(): boolean {
  const isolated = (self as unknown as { crossOriginIsolated?: boolean }).crossOriginIsolated === true
  return (
    isolated &&
    typeof SharedArrayBuffer === "function" &&
    typeof Atomics === "object" &&
    typeof Atomics.wait === "function"
  )
}

// The page's half of a live line (liveInput.buffer): Int32 [0] the state (0
// waiting, 1 a line is there, 2 end of input), Int32 [1] the line's length in
// bytes, the UTF-8 bytes from byte 8 - room for answerCharacters characters
// of four bytes each.
const LIVE_HEADER_BYTES = 8

function liveBuffer(): SharedArrayBuffer {
  return new SharedArrayBuffer(LIVE_HEADER_BYTES + ANSWER_CHARACTERS * 4)
}

// Hand a line (or the end of input, null) to the waiting program. The line is
// encoded first and then COPIED into the shared memory: Chrome refuses
// TextEncoder.encodeInto into a view of shared memory (#583 review S3,
// measured), where Safari accepts it - so encodeInto would work in one
// browser and fail every answer in the other.
function handOver(buffer: SharedArrayBuffer, line: string | null) {
  const control = new Int32Array(buffer, 0, 2)
  if (line === null) {
    Atomics.store(control, 1, 0)
    Atomics.store(control, 0, 2)
  } else {
    const bytes = new TextEncoder().encode(line)
    new Uint8Array(buffer, LIVE_HEADER_BYTES, bytes.length).set(bytes)
    Atomics.store(control, 1, bytes.length)
    Atomics.store(control, 0, 1)
  }
  Atomics.notify(control, 0)
}

// An answer is cut at answerCharacters CHARACTERS, never inside one (a cut
// by UTF-16 units could split an emoji's surrogate pair - review N8).
function cutAnswer(text: string): string {
  const characters = Array.from(text)
  if (characters.length <= ANSWER_CHARACTERS) {
    return text
  }
  return characters.slice(0, ANSWER_CHARACTERS).join("")
}

// ---- The editor's colour and line numbers (#585) -------------------------------

// The editor's frame: a gutter of line numbers beside a cell in which a
// coloured copy of the code sits under the textarea (codeRunner.scss says
// why each metric is shared). Every line the student has not changed shows
// the highlighted copy's own line - Shiki's spans, byte for byte - and every
// line they have shows codeRunnerColour.ts's colours; only the lines whose
// HTML changed are touched on a keystroke (codeRunnerBlocks.editor.colour).
type Frame = {
  frame: HTMLElement
  // Re-colour now / on the next animation frame.
  render: () => void
  schedule: () => void
  // Follow the textarea's scroll.
  sync: () => void
  // The current code's lines as HTML, for the print copy.
  lines: () => string[]
  theme: string
}

function buildFrame(wrapper: HTMLElement, editor: HTMLTextAreaElement, language: RunnerLanguage, original: string): Frame {
  const frame = element("div", "plantoir-runner-frame")
  const gutter = element("pre", "plantoir-runner-gutter")
  gutter.setAttribute("aria-hidden", "true")
  const numbers = element("span", "")
  gutter.appendChild(numbers)
  const cell = element("div", "plantoir-runner-cell")
  const colour = element("pre", "plantoir-runner-colour")
  colour.setAttribute("aria-hidden", "true")
  const code = document.createElement("code")
  const highlighted = wrapper.querySelector<HTMLElement>(".plantoir-runner-original pre > code")
  const theme = highlighted?.getAttribute("data-theme") ?? "github-light github-dark"
  code.setAttribute("data-theme", theme)
  colour.appendChild(code)
  cell.append(colour, editor)
  frame.append(gutter, cell)

  // The highlighted copy's lines, each kept only where its text is the
  // teacher's line (a blank line holds a space there).
  const originalTexts = original.split("\n")
  const shikiLines: string[] = []
  const originalLines: ColouredLine[] = []
  const highlightedLines = highlighted === null ? [] : Array.from(highlighted.querySelectorAll<HTMLElement>(":scope > [data-line]"))
  if (language.colour !== null && highlightedLines.length === originalTexts.length) {
    const coloured = colourLines(language.colour, original) ?? []
    for (let index = 0; index < originalTexts.length; index += 1) {
      const line = highlightedLines[index]
      const text = originalTexts[index]
      const usable = line.textContent === text || (text.trim() === "" && (line.textContent ?? "").trim() === "")
      shikiLines.push(usable ? line.innerHTML : "")
      // A line that cannot be used gets a state no current line has.
      originalLines.push({ text, state: usable ? (coloured[index]?.state ?? "") : "\u0000unusable", tokens: [] })
    }
  }
  const sameColouring = (first: number, second: number) => shikiLines[first] === shikiLines[second]

  let shown: string[] = []
  let numbered = 0
  const linesNow = (): string[] => {
    const value = editor.value
    const coloured = language.colour === null ? null : colourLines(language.colour, value)
    const texts = value.split("\n")
    const current: ColouredLine[] =
      coloured ?? texts.map((text) => ({ text, state: "", tokens: [[text, ""]] as ColouredLine["tokens"] }))
    const plan = originalLines.length > 0 ? reusePlan(originalLines, current, sameColouring) : []
    const html: string[] = []
    for (let index = 0; index < current.length; index += 1) {
      const reused = plan[index]
      if (current[index].text === "") {
        html.push("")
      } else if (reused !== null && reused !== undefined) {
        html.push(shikiLines[reused])
      } else {
        html.push(lineHTML(current[index].tokens))
      }
    }
    return html
  }

  // The copy is a scroll box of its own, scrolled to the textarea's place:
  // a browser puts a scroll box's text on whole device pixels, so a copy
  // moved by a transform instead sat a fraction of a pixel off the typed
  // letters wherever the block itself did not start on a whole pixel
  // (measured, documentation/06 I11). It stops where the textarea's scroll
  // bars start, so the two have the same room to scroll and no letter shows
  // through a bar.
  const sync = () => {
    colour.style.right = `${Math.max(0, editor.offsetWidth - editor.clientWidth)}px`
    colour.style.bottom = `${Math.max(0, editor.offsetHeight - editor.clientHeight)}px`
    colour.scrollLeft = editor.scrollLeft
    colour.scrollTop = editor.scrollTop
    numbers.style.transform = `translateY(${-editor.scrollTop}px)`
  }

  const render = () => {
    const html = linesNow()
    while (code.children.length < html.length) {
      code.appendChild(element("span", "plantoir-runner-line"))
    }
    while (code.children.length > html.length) {
      code.lastElementChild?.remove()
    }
    const next: string[] = []
    for (let index = 0; index < html.length; index += 1) {
      // Each line carries its own line break, so the copy's text is the
      // textarea's, character for character.
      const markup = index < html.length - 1 ? html[index] + "\n" : html[index]
      next.push(markup)
      if (shown[index] !== markup) {
        code.children[index].innerHTML = markup
      }
    }
    shown = next
    if (html.length !== numbered) {
      numbered = html.length
      const all: string[] = []
      for (let number = 1; number <= numbered; number += 1) {
        all.push(String(number))
      }
      numbers.textContent = all.join("\n")
      gutter.style.setProperty("--plantoir-digits", String(Math.max(2, String(numbered).length)))
    }
    sync()
  }

  let queued: number | null = null
  const schedule = () => {
    if (queued !== null) {
      return
    }
    queued = window.requestAnimationFrame(() => {
      queued = null
      render()
    })
  }

  editor.addEventListener("scroll", sync)
  editor.addEventListener("compositionstart", () => wrapper.classList.add("plantoir-runner-composing"))
  editor.addEventListener("compositionend", () => {
    wrapper.classList.remove("plantoir-runner-composing")
    render()
  })
  const resized = new ResizeObserver(() => sync())
  resized.observe(editor)
  window.addCleanup(() => resized.disconnect())

  return { frame, render, schedule, sync, lines: linesNow, theme }
}

// ---- One block ----------------------------------------------------------------

// The editor (#455): the student's copy of the code, or the teacher's when
// nothing is saved. Built in ONE function so a later change to how the
// editor looks (#585) can wrap it without reaching into build(). Answers the
// editor and what the status line says on load (a set-aside edit).
function buildEditor(language: RunnerLanguage, original: string, key: string): { editor: HTMLTextAreaElement; saidOnLoad: string } {
  const editor = element("textarea", "plantoir-runner-editor")
  editor.spellcheck = false
  editor.setAttribute("autocapitalize", "off")
  editor.setAttribute("autocorrect", "off")
  editor.setAttribute("autocomplete", "off")
  editor.setAttribute("wrap", "off")
  editor.setAttribute("aria-label", word("editorLabel", language))
  let saidOnLoad = ""
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
  return { editor, saidOnLoad }
}

function build(wrapper: HTMLElement, base: string, live: boolean): Block | null {
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
  // A prebuilt block's program (#493): its address from the site's root, or
  // why the build has none (then Run stays off and words.notReady says so).
  const programPath = wrapper.dataset.runnerWasm ?? ""
  const unready = language.prebuilt && programPath === ""
  const program = programPath === "" ? undefined : new URL(`${siteRoot()}/${programPath}`, location.href).href

  for (const child of Array.from(wrapper.children)) {
    child.classList.add("plantoir-runner-original")
  }
  wrapper.classList.add("plantoir-runner-live")
  if (readonly) {
    wrapper.classList.add("plantoir-runner-readonly")
  }

  // The editor in its frame (#585), or nothing for readonly (its
  // highlighted code stays, with the numbers every code block has).
  let editor: HTMLTextAreaElement | null = null
  let editorFrame: Frame | null = null
  let saidOnLoad = ""
  if (!readonly) {
    const made = buildEditor(language, original, key)
    editor = made.editor
    saidOnLoad = made.saidOnLoad
    editorFrame = buildFrame(wrapper, editor, language, original)
    wrapper.appendChild(editorFrame.frame)
  }

  // A language a student cannot edit (Swift) says so once, under its code.
  if (!language.editable) {
    const note = element("p", "plantoir-runner-note")
    note.textContent = word("cannotEdit", language)
    wrapper.appendChild(note)
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
  inputBox.appendChild(inputLabel)
  // Where the page cannot stop to ask (it is not isolated), one short line
  // says why the answers go here first (#583, words.inputAhead).
  if (!live) {
    const ahead = element("p", "plantoir-runner-input-ahead")
    ahead.textContent = word("inputAhead", language)
    inputBox.appendChild(ahead)
  }
  inputBox.appendChild(input)
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
  // Live input's end of input (#583): Ctrl-D in the answer field does the
  // same, but an iPad's keyboard has no Ctrl-D. Shown only while a live run
  // has its answer field.
  const endButton = element("button", "plantoir-runner-end")
  endButton.type = "button"
  endButton.textContent = word("endInput", language)
  endButton.hidden = true
  controls.appendChild(endButton)
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
  status.textContent = unready ? word("notReady", language) : saidOnLoad
  wrapper.appendChild(status)

  const output = element("pre", "plantoir-runner-output")
  output.setAttribute("aria-label", word("outputLabel", language))
  output.hidden = true
  wrapper.appendChild(output)

  // What prints when the student has edited the code: a textarea's typed
  // value is not part of a printed (or cloned) page (codeRunnerBlocks.print).
  // Built as a static block is - pre > code > span[data-line] - so it prints
  // coloured and numbered as one does (#585).
  const printCopy = element("pre", "plantoir-runner-print")
  printCopy.setAttribute("aria-hidden", "true")
  const printCode = document.createElement("code")
  printCode.setAttribute("data-theme", editorFrame?.theme ?? "github-light github-dark")
  printCode.setAttribute("data-language", language.fence)
  printCopy.appendChild(printCode)
  wrapper.appendChild(printCopy)

  const code = () => (editor !== null ? editor.value : original)

  // Does the block read input as it stands (the stdin flag, or the row's
  // input pattern in the current code)?
  const readsInput = () => flags.includes("stdin") || inputPattern.test(code())

  const syncInput = () => {
    const current = code()
    // A live page never shows the box: the program asks as it runs.
    inputBox.hidden = live || !readsInput()
    wrapper.classList.toggle("plantoir-runner-edited", current !== original)
  }

  // The print copy, brought up to date only when the page may be printed or
  // left (flush): rebuilding it on every keystroke cost a 500-line program
  // 29 ms at a sixfold CPU slowdown (#585 plan review S2).
  const syncPrint = () => {
    if (editorFrame === null) {
      return
    }
    const lines = editorFrame.lines()
    printCode.textContent = ""
    for (let index = 0; index < lines.length; index += 1) {
      if (index > 0) {
        printCode.appendChild(document.createTextNode("\n"))
      }
      const line = document.createElement("span")
      line.setAttribute("data-line", "")
      line.innerHTML = lines[index] === "" ? " " : lines[index]
      printCode.appendChild(line)
    }
  }

  const fit = () => {
    if (editor === null) {
      return
    }
    const wanted = Math.max(1, Math.min(LIMITS.editorLines, linesOf(editor.value)))
    if (editor.rows !== wanted) {
      editor.rows = wanted
      freeOpenCallouts(wrapper)
      editorFrame?.sync()
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
    syncInput()
    syncPrint()
  }

  // A live run's answer field (#583): ONE for the whole run, always the
  // output's last child, so what the program prints (the echo of an answer
  // among it) goes in before it and the focus never has to leave it.
  let answer: HTMLInputElement | null = null

  // The field fills the rest of its line (at least 8 characters wide: the
  // stylesheet's min-width), measured after each paint.
  const sizeAnswer = () => {
    if (answer === null) {
      return
    }
    answer.style.width = ""
    const box = output.getBoundingClientRect()
    const style = window.getComputedStyle(output)
    const right = box.right - (parseFloat(style.paddingRight) || 0) - (parseFloat(style.borderRightWidth) || 0)
    const room = Math.floor(right - answer.getBoundingClientRect().left - 2)
    answer.style.width = `${Math.max(room, 0)}px`
  }

  // The output, gathered once per animation frame, and its cap (Q5).
  let pending: { text: string; err: boolean }[] = []
  let frame: number | null = null
  let printed = 0
  const paint = () => {
    frame = null
    for (const chunk of pending) {
      const last = answer !== null ? answer.previousSibling : output.lastChild
      if (chunk.err) {
        if (last instanceof HTMLSpanElement) {
          last.textContent += chunk.text
        } else {
          const span = element("span", "plantoir-runner-err")
          span.textContent = chunk.text
          output.insertBefore(span, answer)
        }
      } else if (last !== null && last.nodeType === Node.TEXT_NODE) {
        ;(last as Text).appendData(chunk.text)
      } else {
        output.insertBefore(document.createTextNode(chunk.text), answer)
      }
    }
    pending = []
    if (output.childNodes.length > 0) {
      output.hidden = false
    }
    sizeAnswer()
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
    // Reset during a live run keeps the field the program is answered in.
    if (answer !== null) {
      output.appendChild(answer)
      output.hidden = false
    }
  }

  let busy = false
  // Set the first time this block really starts: an autorun that comes into
  // view after a student already ran it by hand does not run it again.
  let started = false
  const setBusy = (now: boolean) => {
    busy = now
    runButton.disabled = now || unready
    stopButton.disabled = !now
  }
  setBusy(false)

  const block: Block = {
    wrapper,
    language,
    run: () => undefined,
    stopFor: () => undefined,
    flush,
  }

  // ---- Live input for this block (#583, codeRunnerBlocks.liveInput) ----
  // One live run: its shared line, whether a person started it (Run, or
  // Cmd/Ctrl-Enter) rather than an autorun, whether the program is waiting
  // now, whether the student has ended the input (sticky for the run), and
  // the lines typed or pasted ahead of the program's asking for them.
  type LiveRun = {
    buffer: SharedArrayBuffer
    byPerson: boolean
    asking: boolean
    ended: boolean
    ahead: string[]
    asks: number
  }
  let liveRun: LiveRun | null = null

  // Answer a waiting program from what the student has typed, if anything.
  const answerIfWaiting = () => {
    if (liveRun === null || !liveRun.asking) {
      return
    }
    if (liveRun.ended) {
      liveRun.asking = false
      handOver(liveRun.buffer, null)
      status.textContent = word("running", language)
      return
    }
    const next = liveRun.ahead.shift()
    if (next === undefined) {
      return
    }
    liveRun.asking = false
    handOver(liveRun.buffer, next)
    status.textContent = word("running", language)
  }

  // A line the student sent (Return, or a line of a paste), or the end of
  // input (null: Ctrl-D or words.endInput). Lines sent before the program
  // asks wait their turn, as typing ahead in a terminal does.
  const send = (line: string | null) => {
    if (liveRun === null || liveRun.ended) {
      return
    }
    if (line === null) {
      liveRun.ended = true
      liveRun.ahead = []
    } else {
      liveRun.ahead.push(cutAnswer(line))
    }
    answerIfWaiting()
  }

  const focusAnswer = () => {
    if (answer === null) {
      return
    }
    answer.focus({ preventScroll: true })
    answer.scrollIntoView({ block: "nearest" })
  }

  const makeAnswer = (): HTMLInputElement => {
    if (answer !== null) {
      return answer
    }
    const field = element("input", "plantoir-runner-answer")
    field.type = "text"
    field.setAttribute("aria-label", word("answerLabel", language))
    field.setAttribute("enterkeyhint", "send")
    field.setAttribute("autocapitalize", "off")
    field.setAttribute("autocorrect", "off")
    field.setAttribute("autocomplete", "off")
    field.spellcheck = false
    field.addEventListener("keydown", (event: KeyboardEvent) => {
      // The Return that commits an IME candidate (kana, pinyin) is not an
      // answer: Safari sends it with isComposing false and keyCode 229
      // (review N1).
      if (event.isComposing || event.keyCode === 229) {
        return
      }
      if (event.key === "Enter" && !event.metaKey && !event.ctrlKey && !event.altKey) {
        // Never submits a form, checks a quiz or opens a fold around it.
        event.preventDefault()
        event.stopPropagation()
        const line = field.value
        field.value = ""
        send(line)
        return
      }
      if ((event.key === "d" || event.key === "D") && event.ctrlKey && !event.metaKey && !event.altKey) {
        // Ctrl-D ends the input, as in a terminal; anything typed on the
        // line goes first.
        event.preventDefault()
        event.stopPropagation()
        if (field.value !== "") {
          send(field.value)
          field.value = ""
        }
        send(null)
        return
      }
      if (event.key === "Escape") {
        // Quartz's own Escape would move the focus to the search button
        // (review N2), as the editor's handler explains.
        event.stopPropagation()
      }
    })
    // A field of one line strips the line breaks out of a paste (review
    // S2, measured in both browsers), so a paste with several lines is taken
    // here: every line but the last is sent, as typing it and pressing
    // Return would, and the last stays in the field.
    field.addEventListener("paste", (event: ClipboardEvent) => {
      const text = event.clipboardData?.getData("text") ?? ""
      if (!/[\r\n]/.test(text)) {
        return
      }
      event.preventDefault()
      const parts = text.split(/\r\n|\r|\n/)
      const start = field.selectionStart ?? field.value.length
      const finish = field.selectionEnd ?? field.value.length
      const after = field.value.slice(finish)
      const toSend: string[] = [field.value.slice(0, start) + parts[0]]
      for (let index = 1; index < parts.length - 1; index += 1) {
        toSend.push(parts[index])
      }
      const last = parts[parts.length - 1]
      field.value = last + after
      field.setSelectionRange(last.length, last.length)
      for (const line of toSend) {
        send(line)
      }
    })
    output.appendChild(field)
    output.hidden = false
    endButton.hidden = false
    answer = field
    return field
  }

  // The program asks for a line. What it printed first (the prompt) is
  // painted NOW, before the field is used: the worker's "ask" arrives
  // before the next animation frame's paint (review S1, measured).
  const asked = () => {
    if (liveRun === null) {
      return
    }
    if (frame !== null) {
      window.cancelAnimationFrame(frame)
      frame = null
    }
    paint()
    liveRun.asking = true
    liveRun.asks += 1
    if (liveRun.ended || liveRun.ahead.length > 0) {
      answerIfWaiting()
      return
    }
    // The focus moves only when a person started this run (its first ask)
    // or is already inside this block: an autorun never takes it.
    const focusInside = wrapper.contains(document.activeElement)
    makeAnswer()
    sizeAnswer()
    status.textContent = word("waitingForInput", language)
    if (focusInside || (liveRun.byPerson && liveRun.asks === 1)) {
      focusAnswer()
    }
  }

  const endLive = () => {
    liveRun = null
    if (answer !== null) {
      answer.remove()
      answer = null
    }
    endButton.hidden = true
  }

  const end = (statusWord: string, startNext = true) => {
    if (frame !== null) {
      window.cancelAnimationFrame(frame)
    }
    paint()
    endLive()
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
    if (unready) {
      status.textContent = word("notReady", language)
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
    // A queued autorun the student starts by hand runs once, not again when
    // its turn comes (#455 review N1).
    const queued = waitingAutoruns.indexOf(block)
    if (queued >= 0) {
      waitingAutoruns.splice(queued, 1)
    }
    running = block
    started = true
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
    // A live page's run carries its shared line (#583). When a person
    // pressed Run on code that reads input, the answer field is made and
    // focused NOW, inside the press: iPadOS raises its keyboard only for a
    // focus inside a tap (review S7), and the program's first ask comes
    // about a second later, when Python has loaded.
    let line: SharedArrayBuffer | undefined = undefined
    if (live) {
      liveRun = { buffer: liveBuffer(), byPerson: !automatic, asking: false, ended: false, ahead: [], asks: 0 }
      line = liveRun.buffer
      if (!automatic && readsInput()) {
        makeAnswer()
        sizeAnswer()
        focusAnswer()
      }
    }
    runtime
      .prepare()
      .then(() => {
        if (running !== block) {
          return
        }
        // A prebuilt program is still being fetched: "Loading" until it starts.
        if (!language.prebuilt) {
          status.textContent = word("running", language)
        }
        runtime.run(code(), lines, {
          started: () => {
            if (running === block) {
              status.textContent = word("running", language)
            }
          },
          ask: () => {
            if (running === block) {
              asked()
            }
          },
          out: (text, err) => {
            if (running !== block) {
              return
            }
            // Only what is left of the allowance reaches the page: one big
            // print would otherwise be painted whole, however large (#455
            // review S1: print("x" * 50_000_000) painted 50 million).
            const room = LIMITS.outputCharacters - printed
            if (text.length > room) {
              if (room > 0) {
                pending.push({ text: text.slice(0, room), err })
              }
              printed = LIMITS.outputCharacters
              runtime.terminate()
              end(word("outputTooLong", language))
              return
            }
            printed += text.length
            pending.push({ text, err })
            if (frame === null) {
              frame = window.requestAnimationFrame(paint)
            }
          },
          done: (error, said) => {
            if (running !== block) {
              return
            }
            end(said ?? (error ? word("finishedWithError", language) : word("finished", language)))
          },
        }, program, line)
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
  endButton.addEventListener("click", () => send(null))
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
    syncInput()
    syncPrint()
    fit()
    editorFrame?.render()
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
      syncInput()
      // An input method's text is drawn by the textarea until it is done.
      if (!wrapper.classList.contains("plantoir-runner-composing")) {
        editorFrame?.schedule()
      }
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
        // Escape, then Tab, leaves the editor (the keyboard-trap rule). Kept
        // from Quartz's own Escape handler, which would move the focus to the
        // search button (search.inline.ts, hideSearch) and so make the next
        // Tab land back in this editor (measured in the iPad simulator).
        escapeArmed = true
        event.stopPropagation()
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

  syncInput()
  syncPrint()
  fit()
  editorFrame?.render()
  freeOpenCallouts(wrapper)

  if (flags.includes("autorun")) {
    const watcher = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            watcher.disconnect()
            if (!started) {
              block.run(true)
            }
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
  const live = canAskLive()
  const blocks: Block[] = []
  for (const wrapper of wrappers) {
    const block = build(wrapper, base, live)
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
