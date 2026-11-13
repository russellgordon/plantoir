// GeoGebra sketches opened in the reader's browser (#578): every
// `<figure class="pl-figure pl-geogebra" data-geogebra=...>` the site's
// transformer placed (plugins/transformers/plantoirGeoGebra.ts) becomes a
// sketch students can drag when they tap its button - from the site's OWN
// copy of GeoGebra (static/geogebra/, which the build puts in a site only
// when a page has a sketch) and the site's own copy of the sketch, never
// from geogebra.org.
//
// On every page of every site, so it does nothing at all until a tap: no
// file is fetched and nothing watches the page (geogebraFences.engine).
//
// * A tap loads deployggb.js once, fetches the sketch (same origin), and
//   makes the applet from it (ggbBase64) with the web3d codebase, offline,
//   in English, scaled down to the page (scaleContainerClass).
// * Quartz's page change (geogebraFences.spa): each applet is removed
//   (api.remove) when the page changes, which also takes GeoGebra's own
//   styles and libraries out of <head> - the next tap puts them back. What
//   keeps a second sketch working is the engine's replacement 3
//   (scripts/geogebra_engine.py): GeoGebra's hidden loader frame goes under
//   <html>, which Quartz keeps, not <body>, which it replaces (measured
//   without it: Chromium opened no sketch after a page change until a
//   reload). deployggb.js itself is marked spa-preserve and kept.
// * GeoGebra's reset icon (geogebraFences.reset) puts a sketch back to how
//   it opened: a sketch from a file reloads its file, and what a sketch's
//   lines built is made its file once they have run (keepAsStart), so it
//   reloads that. The appletOnLoad each reset brings keeps the sketch.
// * Printing (geogebraFences.print): the handout's prepare step and ⌘P's
//   beforeprint put a picture of each open sketch as it stands beside it;
//   the print styles show the picture in place of the applet. Nothing on
//   the page is moved, so nothing has to be put back.

type Command = { line: number; text: string }
type Spec = {
  sketch: string | null
  app: string
  width: number
  height: number
  commands: Command[]
  toolbar: boolean
  algebra: boolean
  root: string
  loading: string
  couldNotLoad: string
  lineCouldNotRun: string
  endOfLine: string
}
type Api = {
  evalCommand: (command: string) => boolean
  setErrorDialogsActive: (active: boolean) => void
  getPNGBase64: (exportScale: number, transparent: boolean, dpi: number) => string
  getBase64: () => string
  setBase64: (base64: string, callback: () => void) => void
  exists: (name: string) => boolean
  setVisible: (name: string, visible: boolean) => void
  setAuxiliary: (name: string, auxiliary: boolean) => void
  deleteObject: (name: string) => void
  newConstruction: () => void
  remove: () => void
}
type Applet = { setHTML5Codebase: (codebase: string, offline: boolean) => void; inject: (container: string) => void }
type AppletConstructor = new (parameters: Record<string, unknown>, html5: boolean) => Applet
type PrintHooks = { prepare: Array<() => Promise<void>> }

const DEPLOY = "static/geogebra/deployggb.js"
const CODEBASE = "static/geogebra/HTML5/5.0/web3d/"
// How long a tap may take before the student is told it did not open: the
// engine's first load is about 2.9 MB compressed, measured ready in 0.6 to
// 1.0 s on a fast connection; a slow school network gets a minute.
const GIVE_UP_MS = 60000

let deploy: Promise<boolean> | null = null
let made = 0
// Counts Quartz's page changes. A sketch that finishes opening after the
// page it was tapped on has gone marks nothing on the page now showing
// (stage 2 review item 3): its figure may be gone, or a figure on the new
// page may happen to be the same element Quartz kept.
let pageChanges = 0
// How long the teacher's lines may take to run, all together, before the
// rest are left (geogebraFences.commands): measured 1 to 9 ms a line.
const LINES_GIVE_UP_MS = 10000
// The applets open on this page, by their figure.
const open = new Map<HTMLElement, Api>()

function appletConstructor(): AppletConstructor | null {
  const found = (window as unknown as { GGBApplet?: AppletConstructor }).GGBApplet
  return typeof found === "function" ? found : null
}

function address(root: string, path: string): string {
  return new URL(`${root.replace(/\/$/, "")}/${path}`, window.location.href).href
}

function loadDeploy(root: string): Promise<boolean> {
  if (appletConstructor() !== null) {
    return Promise.resolve(true)
  }
  if (deploy !== null) {
    return deploy
  }
  deploy = new Promise((resolve) => {
    const script = document.createElement("script")
    script.src = address(root, DEPLOY)
    script.setAttribute("spa-preserve", "")
    script.addEventListener("load", () => resolve(appletConstructor() !== null), { once: true })
    script.addEventListener(
      "error",
      () => {
        deploy = null
        script.remove()
        resolve(false)
      },
      { once: true },
    )
    document.head.appendChild(script)
  })
  return deploy
}

async function sketchAsBase64(url: string): Promise<string> {
  const answer = await fetch(url)
  if (!answer.ok) {
    throw new Error(`the sketch answered ${answer.status}`)
  }
  const bytes = new Uint8Array(await answer.arrayBuffer())
  let binary = ""
  for (let start = 0; start < bytes.length; start += 32768) {
    binary += String.fromCharCode.apply(null, Array.from(bytes.subarray(start, start + 32768)))
  }
  return btoa(binary)
}

function say(figure: HTMLElement, words: string) {
  const message = figure.querySelector<HTMLElement>(":scope > .pl-geogebra-message")
  if (message === null) {
    return
  }
  message.textContent = words
  message.hidden = words === ""
}

// What one of GeoGebra's error dialogs says: its message lines, without its
// title ("Error") or its buttons ("OK", "Close", "Show Online Help").
function dialogSays(dialog: Element): string {
  const lines: string[] = []
  for (const label of Array.from(dialog.querySelectorAll(".dialogContent .gwt-Label"))) {
    const text = (label.textContent ?? "").trim()
    if (text !== "") {
      lines.push(text)
    }
  }
  return lines.join(" ")
}

// Closes one of GeoGebra's error dialogs the way a student's tap on it would
// (#755): through its own button, never by taking it off the page. Each
// dialog GeoGebra opens is modal - it lays a shade (.gwt-PopupPanelGlass)
// over the sketch and the app ignores pointer input while it is open - and
// only its own close puts both right. Removing the dialog from the page,
// which this loader did until #755, left one shade per line (14 lines, 14
// shades, a black box) and the app still modal: with the shades removed
// as well, a slider dragged with real pointer events did not move
// (measured in headless Chromium 1243 and WebKit 2359 over HTTP: a stayed
// at 1; closed through its button, 1 to 3, no shade left).
//
// The dialogs GeoGebra 5.4.933.1 opens for a refused line or the marker
// have "Close" beside "Show Online Help", or "OK" alone (measured, every
// contract case). The help button opens geogebra.org, so it is never the
// one pressed: a lone button is pressed, otherwise the plain text button.
// click() closes the dialog at once, before it is drawn (measured: off the
// page when click returns, in both engines). Should a later engine not
// close it, it is taken off the page as before, so it is still never drawn.
function closeDialog(dialog: Element) {
  const buttons = Array.from(dialog.querySelectorAll<HTMLButtonElement>(".dialogBtnPanel button"))
  let close: HTMLButtonElement | null = null
  if (buttons.length === 1) {
    close = buttons[0]
  } else {
    close = dialog.querySelector<HTMLButtonElement>(".dialogBtnPanel button.materialTextButton")
  }
  if (close !== null) {
    close.click()
  }
  if (dialog.isConnected) {
    dialog.remove()
  }
}

// Runs the fence's commands, one line at a time, and answers the lines
// GeoGebra refused, with its own words (geogebraFences.commands).
//
// evalCommand's answer cannot be used: it is false for scripting commands
// that WORK (SetValue, ZoomIn, SetColor) and for real errors alike
// (measured). GeoGebra's own error dialog is what tells them apart - but it
// appears a few milliseconds AFTER the line, not during it. So after each
// line a command GeoGebra does not know (endOfLine) is run as well: its
// dialog always comes, and comes after the line's own, so whatever dialog
// arrives before it is the line's (measured in Chromium and WebKit: in
// order, every time). Each dialog is read and then closed through its own
// button (closeDialog) as it is added, before it is drawn. No waiting on a
// clock: the wait ends when the marker's dialog arrives, and
// LINES_GIVE_UP_MS is only a last resort.
//
// On that last resort, dialogs for lines already run are still on their
// way: turning dialogs off does not stop one already queued (measured,
// #755). So the watcher stays until the last marker run has arrived,
// closing what comes, and only then lets go - never left open over the
// sketch, and still no clock. Should that marker never come, the watcher
// would close every dialog a student opens with a tool (Slider, Text...)
// the moment it opens; so it also lets go at the student's first
// pointerdown or keydown inside the sketch, since any dialog a student
// opens follows their own input. The accepted cost: a queued line's
// dialog that arrives after that first touch is drawn, and the student
// closes it by hand, which is GeoGebra's ordinary behaviour.
type Ran = { refused: Array<{ line: number; said: string }>; complete: boolean }

async function runCommands(api: Api, box: HTMLElement, spec: Spec): Promise<Ran> {
  const refused: Array<{ line: number; said: string }> = []
  if (spec.commands.length === 0) {
    try {
      api.setErrorDialogsActive(false)
    } catch {}
    return { refused, complete: true }
  }
  const seen: string[] = []
  const marker = spec.endOfLine.replace(/\(.*$/, "")
  const isMarker = (said: string) => said.includes(marker)
  let markersRun = 0
  let markersSeen = 0
  let finished = false
  let arrived: (() => void) | null = null
  const take = () => {
    for (const dialog of Array.from(box.querySelectorAll(".dialogComponent"))) {
      const said = dialogSays(dialog)
      seen.push(said)
      if (isMarker(said)) {
        markersSeen += 1
      }
      closeDialog(dialog)
    }
    if (finished && markersSeen >= markersRun) {
      letGo()
    }
    if (arrived !== null) {
      arrived()
    }
  }
  const watcher = new MutationObserver(take)
  watcher.observe(box, { childList: true, subtree: true })
  // The student's first touch inside the sketch, once lines are over.
  const letGo = () => {
    watcher.disconnect()
    box.removeEventListener("pointerdown", touched, true)
    box.removeEventListener("keydown", touched, true)
  }
  const touched = () => letGo()
  const giveUpAt = performance.now() + LINES_GIVE_UP_MS
  try {
    try {
      api.setErrorDialogsActive(true)
    } catch {}
    for (const command of spec.commands) {
      const from = seen.length
      try {
        api.evalCommand(command.text)
      } catch {}
      markersRun += 1
      try {
        api.evalCommand(spec.endOfLine)
      } catch {}
      take()
      while (!seen.slice(from).some(isMarker)) {
        const left = giveUpAt - performance.now()
        if (left <= 0) {
          return { refused, complete: false }
        }
        const came = await new Promise<boolean>((resolve) => {
          const timer = window.setTimeout(() => resolve(false), left)
          arrived = () => {
            window.clearTimeout(timer)
            resolve(true)
          }
        })
        arrived = null
        if (!came) {
          return { refused, complete: false }
        }
      }
      const said: string[] = []
      for (const text of seen.slice(from)) {
        if (!isMarker(text) && text !== "") {
          said.push(text)
        }
      }
      if (said.length > 0) {
        refused.push({ line: command.line, said: said.join(" ") })
      }
    }
    return { refused, complete: true }
  } finally {
    try {
      api.setErrorDialogsActive(false)
    } catch {}
    // Lets go now if every marker has come (the ordinary end), otherwise
    // when the last one does or at the student's first touch, whichever
    // is first (the last resort above).
    finished = true
    if (markersSeen < markersRun) {
      box.addEventListener("pointerdown", touched, { capture: true, once: true })
      box.addEventListener("keydown", touched, { capture: true, once: true })
    }
    take()
  }
}

// Makes what the fence's lines built the sketch's starting state, so that
// GeoGebra's own reset icon (showResetIcon: two arrows in a circle, painted
// on the graphics view's canvas at its top right, not an element of the
// page) puts the sketch back to it (#792).
//
// Reset returns an applet to the file it was LOADED with. A sketch written
// as lines is loaded empty and built afterwards, so until #792 reset left
// only the axes. Measured in headless Chromium 1243 and WebKit 2359 with a
// real press: no object left, appletOnLoad not called again, and no client,
// add or clear listener event that the page could act on. Loading the built
// construction back in as the applet's file (setBase64 of getBase64) does
// not call appletOnLoad, and makes reset reload it: every object with the
// same XML, each slider at the value the lines gave it, the view the lines
// zoomed to. No line runs again, so a reset opens no dialog, lays no shade
// and has nothing to stack, however often it is pressed. It took 41 to 65
// ms. It looks the same, with three differences measured: a selection the
// lines made (SelectObjects) is cleared; RandomBetween and the other random
// numbers are drawn again, by this load and by every reset, as GeoGebra
// does for every file; and WebKit no longer draws a 1 px frame round the
// applet (Chromium: one small patch of 46 px redrawn on a sketch with the
// toolbar and the algebra view).
//
// Answers when GeoGebra's own callback says the construction is loaded.
// LINES_GIVE_UP_MS is only a last resort, should it never say so. Keeps
// nothing when getBase64 gives no file (an empty string, or a throw).
function keepAsStart(api: Api): Promise<boolean> {
  return new Promise((resolve) => {
    let timer: number | undefined = undefined
    let answered = false
    const answer = (loaded: boolean) => {
      if (answered) {
        return
      }
      answered = true
      window.clearTimeout(timer)
      resolve(loaded)
    }
    // Nothing is kept when GeoGebra gives no file: setBase64 of "" empties
    // the sketch and never calls back (measured, #792 review L1).
    let file: unknown = null
    try {
      file = api.getBase64()
    } catch {
      file = null
    }
    if (typeof file !== "string" || file === "") {
      answer(false)
      return
    }
    timer = window.setTimeout(() => answer(false), LINES_GIVE_UP_MS)
    try {
      api.setBase64(file, () => answer(true))
    } catch {
      answer(false)
    }
  })
}

// Loads `file` into the applet again, or empties it when there is none:
// where a sketch's lines start from (#792). Answers when GeoGebra says it
// is loaded; LINES_GIVE_UP_MS is only a last resort.
function startFrom(api: Api, file: string | null): Promise<boolean> {
  return new Promise((resolve) => {
    if (file === null) {
      try {
        api.newConstruction()
        resolve(true)
      } catch {
        resolve(false)
      }
      return
    }
    let timer: number | undefined = undefined
    let answered = false
    const answer = (loaded: boolean) => {
      if (answered) {
        return
      }
      answered = true
      window.clearTimeout(timer)
      resolve(loaded)
    }
    timer = window.setTimeout(() => answer(false), LINES_GIVE_UP_MS)
    try {
      api.setBase64(file, () => answer(true))
    } catch {
      answer(false)
    }
  })
}

// A hidden number put into the construction before the lines run and
// taken out after (#792). A reset while they run empties the construction
// or reloads the file without it, and nothing else tells the page, so its
// absence afterwards is how the loader knows the lines did not all run on
// the construction now showing.
const UNTOUCHED = "plantoirLinesUntouched"

function markUntouched(api: Api) {
  try {
    api.evalCommand(`${UNTOUCHED} = 1`)
    api.setVisible(UNTOUCHED, false)
    api.setAuxiliary(UNTOUCHED, true)
  } catch {}
}

function stillUntouched(api: Api): boolean {
  try {
    return api.exists(UNTOUCHED)
  } catch {
    return false
  }
}

function unmark(api: Api) {
  try {
    api.deleteObject(UNTOUCHED)
  } catch {}
}

// Holds back a person's presses, touches, Space and Enter on a sketch while
// its lines run and while keepAsStart loads what they built (#792), so that
// the reset icon, or anything else on the sketch, cannot act on a
// construction still being made. Measured on a 163-line sketch, the reset
// icon pressed again and again until the lines were done (14 to 17
// presses): without the hold, 5 objects of 155 were left in Chromium and 8
// in WebKit; with it, all 155. The reset icon is also in GeoGebra's own
// keyboard cycle: Shift+Tab then Space, again and again with the focus in
// the sketch, left 130 of 155 (Chromium) and 0 (WebKit), one run each,
// before Space and Enter were held (#792 review M1). Tab still moves the focus, and the page
// still scrolls with Space when the focus is outside the sketch (measured
// while the lines ran). Answers the function that lets presses through
// again.
function holdPresses(box: HTMLElement): () => void {
  const kinds = ["pointerdown", "pointerup", "mousedown", "mouseup", "touchstart", "touchend", "click", "keydown", "keypress", "keyup"]
  const hold = (event: Event) => {
    // Only a person's own press: runCommands closes GeoGebra's dialogs with
    // a click() of their button, which must still reach it (#755).
    if (!event.isTrusted) {
      return
    }
    // Of the keys, only those that press what has the focus: Space and
    // Enter. Tab still moves the focus, and the other keys are left alone.
    if (event instanceof KeyboardEvent && event.key !== " " && event.key !== "Spacebar" && event.key !== "Enter") {
      return
    }
    event.stopPropagation()
    if (event.cancelable) {
      event.preventDefault()
    }
  }
  for (const kind of kinds) {
    box.addEventListener(kind, hold, true)
  }
  return () => {
    for (const kind of kinds) {
      box.removeEventListener(kind, hold, true)
    }
  }
}

function filled(template: string, values: Record<string, string>): string {
  return template.replace(/\{([A-Za-z]+)\}/g, (whole, name) => (name in values ? values[name] : whole))
}

// The lines GeoGebra refused, under the sketch, each in its own words.
function showRefused(figure: HTMLElement, box: HTMLElement, spec: Spec, refused: Array<{ line: number; said: string }>) {
  figure.querySelector(":scope > .pl-geogebra-lines")?.remove()
  if (refused.length === 0) {
    return
  }
  const list = document.createElement("ul")
  list.className = "pl-geogebra-lines"
  for (const item of refused) {
    const entry = document.createElement("li")
    entry.textContent = filled(spec.lineCouldNotRun, { line: String(item.line), said: item.said })
    list.appendChild(entry)
  }
  box.after(list)
}

function specOf(figure: HTMLElement): Spec | null {
  try {
    return JSON.parse(figure.dataset.geogebra ?? "") as Spec
  } catch {
    return null
  }
}

async function openSketch(figure: HTMLElement, button: HTMLButtonElement) {
  const spec = specOf(figure)
  const box = figure.querySelector<HTMLElement>(":scope > .pl-geogebra-applet")
  if (spec === null || box === null || open.has(figure) || figure.dataset.geogebraOpening === "yes") {
    return
  }
  const tappedOnPage = pageChanges
  const samePage = () => tappedOnPage === pageChanges && figure.isConnected
  figure.dataset.geogebraOpening = "yes"
  button.disabled = true
  say(figure, spec.loading)
  let settled = false
  // True once the sketch has opened: a later appletOnLoad is its reset.
  let opened = false
  // The applet as the latest load handed it over: a reset passes a new one.
  let current: Api | null = null
  const failed = () => {
    if (settled) {
      return
    }
    settled = true
    if (!samePage()) {
      return
    }
    delete figure.dataset.geogebraOpening
    button.disabled = false
    box.hidden = true
    box.replaceChildren()
    say(figure, spec.couldNotLoad)
  }
  const timer = window.setTimeout(failed, GIVE_UP_MS)
  // Runs the fence's lines and makes what they built the sketch's file
  // (keepAsStart), only ever from a construction the lines ran on from its
  // start to their end (#792 review M1). Should a reset come while they run
  // (presses, Space and Enter are held, so only something unforeseen), the
  // marker is gone: the sketch starts again from its file, or empty, and
  // the lines run again. Measured with the hold taken out and Shift+Tab and
  // Space pressed again and again: 2 runs in Chromium, 3 in WebKit, all 155
  // objects kept. After three tries, or when the lines gave up, nothing is
  // kept, and reset reloads the file the sketch was loaded with, as before
  // #792.
  const buildFromLines = async (file: string | null) => {
    let ran: Ran = { refused: [], complete: false }
    let whole = false
    for (let attempt = 0; attempt < 3 && !whole; attempt += 1) {
      const api = current
      if (api === null || !samePage() || !open.has(figure)) {
        return
      }
      if (attempt > 0 && !(await startFrom(api, file))) {
        break
      }
      markUntouched(api)
      ran = await runCommands(api, box, spec)
      const resetMeanwhile = current !== api || !stillUntouched(api)
      if (!resetMeanwhile) {
        // Run to their end, or given up (LINES_GIVE_UP_MS): only the first
        // is kept, and a give-up is not tried again.
        whole = ran.complete
        break
      }
    }
    if (!samePage() || !open.has(figure) || current === null) {
      return
    }
    const api = current
    unmark(api)
    showRefused(figure, box, spec, ran.refused)
    if (whole) {
      await keepAsStart(api)
    }
    try {
      api.setErrorDialogsActive(false)
    } catch {}
  }
  try {
    if (!(await loadDeploy(spec.root))) {
      throw new Error("GeoGebra did not load")
    }
    const parameters: Record<string, unknown> = {
      id: `plantoirGeoGebra${(made += 1)}`,
      appName: spec.app,
      width: spec.width,
      height: spec.height,
      scaleContainerClass: "pl-geogebra-applet",
      allowUpscale: false,
      language: "en",
      showToolBar: spec.toolbar,
      showMenuBar: false,
      showAlgebraInput: false,
      enableRightClick: false,
      enableShiftDragZoom: true,
      showResetIcon: true,
      // On while the fence's lines run, so GeoGebra says what it refused;
      // off after (runCommands), so nothing a student does opens an error dialog.
      errorDialogsActive: true,
      borderColor: null,
      useBrowserForJS: false,
      appletOnLoad: (api: Api) => {
        // Called again each time the sketch's reset icon reloads the file
        // it was loaded with (#792): a sketch from a file, or one whose
        // lines keepAsStart has made its file. That is the same sketch, still
        // open on this page, so it is kept, never removed - removing it here
        // left an empty white box, measured, on a sketch from a file.
        if (opened) {
          if (!samePage() || !open.has(figure)) {
            try {
              api.remove()
            } catch {}
            return
          }
          open.set(figure, api)
          current = api
          try {
            api.setErrorDialogsActive(false)
          } catch {}
          return
        }
        // Finished after the page changed, or after the student was told
        // it did not open: removed at once, never left running.
        if (settled || !samePage()) {
          settled = true
          try {
            api.remove()
          } catch {}
          return
        }
        settled = true
        opened = true
        window.clearTimeout(timer)
        delete figure.dataset.geogebraOpening
        open.set(figure, api)
        current = api
        figure.classList.add("pl-geogebra-loaded")
        say(figure, "")
        if (spec.commands.length === 0) {
          void runCommands(api, box, spec).then(() => {
            if (samePage() && open.has(figure)) {
              figure.dataset.geogebraCommands = "ran"
            }
          })
          return
        }
        const letPressesThrough = holdPresses(box)
        const file = typeof parameters.ggbBase64 === "string" ? parameters.ggbBase64 : null
        void buildFromLines(file)
          .catch(() => {})
          .then(() => {
            if (samePage() && open.has(figure)) {
              figure.dataset.geogebraCommands = "ran"
            }
          })
          .finally(letPressesThrough)
      },
    }
    if (spec.sketch !== null) {
      // `sketch` is the file's address from the top of the site (the
      // transformer's slugifyFilePath), so it is joined to `root` here.
      parameters.ggbBase64 = await sketchAsBase64(address(spec.root, spec.sketch))
    } else {
      parameters.perspective = spec.algebra ? "AG" : "G"
    }
    if (spec.sketch !== null && spec.algebra) {
      parameters.perspective = "AG"
    }
    const Applet = appletConstructor()
    if (Applet === null || settled) {
      throw new Error("GeoGebra did not load")
    }
    box.id = `${parameters.id}-box`
    box.hidden = false
    const applet = new Applet(parameters, true)
    applet.setHTML5Codebase(address(spec.root, CODEBASE), true)
    applet.inject(box.id)
  } catch {
    window.clearTimeout(timer)
    failed()
  }
}

// A picture of every open sketch as it stands, beside it, for paper
// (geogebraFences.print). getPNGBase64 answers at once, which beforeprint
// needs: it gives no time to wait.
function pictureEveryOpenSketch() {
  for (const [figure, api] of open) {
    if (!figure.isConnected) {
      continue
    }
    let png = ""
    try {
      png = api.getPNGBase64(1, false, 96) ?? ""
    } catch {
      png = ""
    }
    if (png === "") {
      continue
    }
    let picture = figure.querySelector<HTMLImageElement>(":scope > img.pl-geogebra-print")
    if (picture === null) {
      picture = document.createElement("img")
      picture.className = "pl-geogebra-print"
      picture.alt = ""
      figure.querySelector(":scope > .pl-geogebra-applet")?.after(picture)
    }
    picture.src = `data:image/png;base64,${png}`
  }
}

const hooks = window as unknown as { plantoirPrint?: PrintHooks; plantoirGeoGebraHooked?: boolean }
if (!hooks.plantoirPrint) {
  hooks.plantoirPrint = { prepare: [] }
}
if (!hooks.plantoirGeoGebraHooked) {
  hooks.plantoirGeoGebraHooked = true
  hooks.plantoirPrint.prepare.push(async () => {
    pictureEveryOpenSketch()
  })
  window.addEventListener("beforeprint", pictureEveryOpenSketch)
}

document.addEventListener("nav", () => {
  const figures = Array.from(document.querySelectorAll<HTMLElement>("figure.pl-geogebra[data-geogebra]"))
  if (figures.length === 0) {
    return
  }
  for (const figure of figures) {
    const button = figure.querySelector<HTMLButtonElement>(".pl-geogebra-open")
    if (button === null) {
      continue
    }
    const tapped = () => {
      void openSketch(figure, button)
    }
    button.addEventListener("click", tapped)
    window.addCleanup(() => button.removeEventListener("click", tapped))
  }
  window.addCleanup(() => {
    pageChanges += 1
    for (const [figure, api] of open) {
      try {
        api.remove()
      } catch {}
      open.delete(figure)
    }
  })
})
