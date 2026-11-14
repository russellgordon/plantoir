// PhET simulations opened in the reader's browser (#674): every `<figure
// class="pl-figure pl-phet" data-phet=...>` the site's transformer placed
// (plugins/transformers/plantoirPhet.ts) opens its simulation when a student
// taps its button - from the class site's OWN copy (static/phet/<sim>/,
// which the build puts in a site only when a page shows that simulation),
// never from phet.colorado.edu.
//
// On every page of every site, so it does nothing at all until a tap: no
// file is fetched and nothing watches the page.
//
// * A tap makes one frame, in the picture's own box (the simulation's
//   shape, so nothing on the page moves), at the address the build wrote:
//   yotta=false&allowLinks=false first, always, then the language and the
//   screens (phetFences.address). While it opens, the box says so, once,
//   in a polite live region (#756's lesson). When the frame's document has
//   loaded AND is the simulation (its own `phet` object is there), the
//   picture goes and the simulation shows; anything else, or a minute with
//   no simulation, says couldNotLoad below the box and the button works
//   again.
// * Quartz's page change replaces the page's body, and the frame with it,
//   which frees the simulation's memory (an iPad holds little); a frame
//   that finishes opening after its page has gone marks nothing.
// * Printing: a frame prints blank or cropped, so the print styles show the
//   simulation's picture in its place (phet.scss); nothing is moved, so
//   nothing has to be put back.

type PhetSpec = {
  sim: string
  url: string
  title: string
  loading: string
  loadingFirstTime: string
  couldNotLoad: string
}

// How long a tap may take before the student is told it did not open: a
// simulation is about 1 MB as a browser downloads it, measured open in 0.5
// to 0.65 s on this Mac's line; a slow school network gets a minute.
const PHET_GIVE_UP_MS = 60000

// Counts Quartz's page changes: a frame that loads after its page has gone
// must mark nothing on the page now showing.
let phetPageChanges = 0

function phetSay(region: HTMLElement | null, lines: string[]) {
  if (region === null) {
    return
  }
  region.replaceChildren()
  for (const words of lines) {
    if (words === "") {
      continue
    }
    const line = document.createElement("span")
    line.textContent = words
    region.appendChild(line)
  }
}

function phetIsTheSimulation(frame: HTMLIFrameElement): boolean {
  try {
    const inside = frame.contentWindow as unknown as { phet?: unknown } | null
    return inside !== null && typeof inside.phet === "object" && inside.phet !== null
  } catch {
    return false
  }
}

function openSimulation(figure: HTMLElement, button: HTMLButtonElement) {
  const state = figure.dataset.phetState
  if (state === "opening" || state === "open") {
    return
  }
  let spec: PhetSpec
  try {
    spec = JSON.parse(figure.dataset.phet ?? "") as PhetSpec
  } catch {
    return
  }
  const stage = figure.querySelector<HTMLElement>(":scope > .pl-phet-stage")
  const message = figure.querySelector<HTMLElement>(":scope > .pl-phet-message")
  if (stage === null) {
    return
  }
  const region = stage.querySelector<HTMLElement>(":scope > .pl-phet-loading")
  const page = phetPageChanges
  figure.dataset.phetState = "opening"
  button.disabled = true
  if (message !== null) {
    message.hidden = true
    message.textContent = ""
  }
  phetSay(region, [spec.loading, spec.loadingFirstTime])
  for (const old of Array.from(stage.querySelectorAll(":scope > iframe"))) {
    old.remove()
  }
  const frame = document.createElement("iframe")
  frame.className = "pl-phet-simulation"
  frame.title = spec.title
  frame.setAttribute("allow", "fullscreen")
  let settled = false
  const failed = () => {
    if (settled || page !== phetPageChanges || !figure.isConnected) {
      return
    }
    settled = true
    window.clearTimeout(timer)
    frame.remove()
    figure.dataset.phetState = "failed"
    figure.classList.remove("pl-phet-loaded")
    phetSay(region, [])
    button.disabled = false
    if (message !== null) {
      message.textContent = spec.couldNotLoad
      message.hidden = false
    }
  }
  const timer = window.setTimeout(failed, PHET_GIVE_UP_MS)
  frame.addEventListener("load", () => {
    if (settled || page !== phetPageChanges || !figure.isConnected) {
      return
    }
    if (!phetIsTheSimulation(frame)) {
      // An error page, or a school network's sign-in page, in its place.
      failed()
      return
    }
    settled = true
    window.clearTimeout(timer)
    figure.dataset.phetState = "open"
    figure.classList.add("pl-phet-loaded")
    phetSay(region, [])
  })
  frame.addEventListener("error", failed)
  frame.src = spec.url
  stage.appendChild(frame)
}

document.addEventListener("nav", () => {
  const figures = Array.from(document.querySelectorAll<HTMLElement>("figure.pl-phet[data-phet]"))
  if (figures.length === 0) {
    return
  }
  for (const figure of figures) {
    const button = figure.querySelector<HTMLButtonElement>(".pl-phet-open")
    if (button === null) {
      continue
    }
    const tapped = () => {
      openSimulation(figure, button)
    }
    button.addEventListener("click", tapped)
    window.addCleanup(() => button.removeEventListener("click", tapped))
  }
  window.addCleanup(() => {
    phetPageChanges += 1
  })
})
