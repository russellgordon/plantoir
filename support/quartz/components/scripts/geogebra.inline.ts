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
}
type Api = {
  evalCommand: (command: string) => boolean
  getPNGBase64: (exportScale: number, transparent: boolean, dpi: number) => string
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
      borderColor: null,
      useBrowserForJS: false,
      appletOnLoad: (api: Api) => {
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
        window.clearTimeout(timer)
        delete figure.dataset.geogebraOpening
        open.set(figure, api)
        figure.classList.add("pl-geogebra-loaded")
        say(figure, "")
        for (const command of spec.commands) {
          try {
            api.evalCommand(command.text)
          } catch {}
        }
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
