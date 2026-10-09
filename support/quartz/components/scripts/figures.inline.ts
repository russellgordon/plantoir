// Graphs drawn in the reader's browser (#485 E1): every
// `<figure class="pl-figure pl-functionplot" data-plot=...>` the site's
// transformer placed (plugins/transformers/plantoirFigures.ts), drawn with
// function-plot from the site's OWN copy (static/function-plot/, which the
// build puts in a site only when a page has a graph) - never from another
// address. TikZ diagrams need nothing here: they were drawn when the site was
// built.
//
// On every page of every site, so it does nothing at all on a page without a
// graph: no script is fetched, no listener is added.
//
// * Each graph is drawn when a tenth of it comes into view, at its figure's
//   width and 0.62 of that in height, and again when the width changes.
// * Zoom (review B2, measured): function-plot listens for zoom on the graph's
//   own surface even with `disableZoom: true`, and while it does a scroll or a
//   finger drag that starts over a graph moves the graph instead of the page.
//   So its zoom listeners are taken off when the teacher turned zoom off and
//   on every touch screen; with a mouse or trackpad dragging still moves the
//   graph, and zooming needs Cmd or Ctrl held - which a trackpad pinch sends -
//   so a plain scroll always scrolls the page.
// * Printing (printablePages.figures, decision 13): the handout waits for
//   window.plantoirPrint.prepare, and ⌘P's beforeprint draws every graph at
//   the bounds the teacher wrote, whatever was zoomed on screen.

type Plot = {
  title?: string
  xLabel?: string
  yLabel?: string
  bounds?: number[]
  disableZoom?: boolean
  grid?: boolean
  functions?: string[]
}
type FunctionPlot = (options: Record<string, unknown>) => unknown
type ListenerEntry = { type: string; name: string; listener: EventListener; options?: AddEventListenerOptions }
type PrintHooks = { prepare: Array<() => Promise<void>> }

const ENGINE = "static/function-plot/function-plot.js"
const HEIGHT_RATIO = 0.62
const SMALLEST_WIDTH = 240

let loading: Promise<boolean> | null = null

function engine(): FunctionPlot | null {
  const found = (window as unknown as { functionPlot?: FunctionPlot }).functionPlot
  return typeof found === "function" ? found : null
}

function loadEngine(root: string): Promise<boolean> {
  if (engine() !== null) {
    return Promise.resolve(true)
  }
  if (loading !== null) {
    return loading
  }
  loading = new Promise((resolve) => {
    const script = document.createElement("script")
    script.src = `${root.replace(/\/$/, "")}/${ENGINE}`
    // Kept across Quartz's page changes, which replace the rest of <head>.
    script.setAttribute("spa-preserve", "")
    script.addEventListener("load", () => resolve(engine() !== null), { once: true })
    script.addEventListener(
      "error",
      () => {
        loading = null
        resolve(false)
      },
      { once: true },
    )
    document.head.appendChild(script)
  })
  return loading
}

function graphsOnThePage(): HTMLElement[] {
  return Array.from(document.querySelectorAll<HTMLElement>("figure.pl-functionplot[data-plot]"))
}

function say(figure: HTMLElement, words: string | undefined) {
  if (!words) {
    return
  }
  let message = figure.querySelector<HTMLElement>(":scope > .pl-figure-message")
  if (message === null) {
    message = document.createElement("p")
    message.className = "pl-figure-message"
    figure.prepend(message)
  }
  message.textContent = words
}

// Takes function-plot's zoom off the graph's surface (review B2), keeping
// d3's own list of listeners in step so nothing re-adds them.
function tameZoom(box: HTMLElement, zoomOff: boolean) {
  const touch = window.matchMedia !== undefined && window.matchMedia("(pointer: coarse)").matches
  for (const surface of box.querySelectorAll(".zoom-and-drag")) {
    const holder = surface as unknown as { __on?: ListenerEntry[] }
    const listeners = holder.__on ?? []
    const kept: ListenerEntry[] = []
    for (const entry of listeners) {
      if (entry.name !== "zoom") {
        kept.push(entry)
        continue
      }
      if (zoomOff || touch) {
        surface.removeEventListener(entry.type, entry.listener, entry.options)
        continue
      }
      if (entry.type === "wheel") {
        surface.removeEventListener(entry.type, entry.listener, entry.options)
        const original = entry.listener
        const gated = function (this: Element, event: Event) {
          const wheel = event as WheelEvent
          if (wheel.ctrlKey || wheel.metaKey) {
            original.call(this, event)
          }
        }
        surface.addEventListener("wheel", gated, { passive: false })
        kept.push({ ...entry, listener: gated })
        continue
      }
      kept.push(entry)
    }
    holder.__on = kept
  }
}

// The figure's own width; inside a folded callout it has none, so the
// article's (a graph drawn for the handout before its callout is opened).
function widthFor(figure: HTMLElement): number {
  const article = figure.closest("article") as HTMLElement | null
  const measured = figure.clientWidth || (article ? article.clientWidth : 0) || 600
  return Math.max(SMALLEST_WIDTH, Math.round(measured))
}

function draw(figure: HTMLElement): boolean {
  const functionPlot = engine()
  const box = figure.querySelector<HTMLElement>(":scope > .pl-plot")
  if (functionPlot === null || box === null) {
    return false
  }
  let plot: Plot
  try {
    plot = JSON.parse(figure.dataset.plot ?? "{}") as Plot
  } catch {
    say(figure, figure.dataset.figureFailed)
    return false
  }
  const width = widthFor(figure)
  const height = Math.round(width * HEIGHT_RATIO)
  const bounds = plot.bounds && plot.bounds.length === 4 ? plot.bounds : [-10, 10, -10, 10]
  box.replaceChildren()
  try {
    functionPlot({
      target: box,
      width,
      height,
      title: plot.title || undefined,
      grid: plot.grid !== false,
      disableZoom: plot.disableZoom === true,
      xAxis: { domain: [bounds[0], bounds[1]], label: plot.xLabel || undefined },
      yAxis: { domain: [bounds[2], bounds[3]], label: plot.yLabel || undefined },
      data: (plot.functions ?? []).map((fn) => ({ fn, graphType: "polyline" })),
    })
  } catch {
    box.replaceChildren()
    figure.classList.remove("pl-plot-drawn")
    say(figure, figure.dataset.figureFailed)
    return false
  }
  const svg = box.querySelector("svg")
  if (svg !== null) {
    // function-plot gives its drawing a size and no viewBox, so it could not
    // be scaled to a page or a narrow screen without one (plan M7).
    const drawnWidth = parseFloat(svg.getAttribute("width") ?? String(width))
    const drawnHeight = parseFloat(svg.getAttribute("height") ?? String(height))
    svg.setAttribute("viewBox", `0 0 ${drawnWidth} ${drawnHeight}`)
    svg.setAttribute("aria-hidden", "true")
    svg.setAttribute("focusable", "false")
  }
  tameZoom(box, plot.disableZoom === true)
  figure.dataset.drawnWidth = String(width)
  figure.classList.add("pl-plot-drawn")
  return true
}

function drawEvery() {
  for (const figure of graphsOnThePage()) {
    draw(figure)
  }
}

// The handout (print.inline.ts) awaits every function here before it is
// made; registered once per page load, whatever page it is.
const hooks = window as unknown as { plantoirPrint?: PrintHooks; plantoirFiguresHooked?: boolean }
if (!hooks.plantoirPrint) {
  hooks.plantoirPrint = { prepare: [] }
}
if (!hooks.plantoirFiguresHooked) {
  hooks.plantoirFiguresHooked = true
  hooks.plantoirPrint.prepare.push(async () => {
    const graphs = graphsOnThePage()
    if (graphs.length === 0) {
      return
    }
    const root = graphs[0].dataset.figureRoot ?? "."
    if (await loadEngine(root)) {
      drawEvery()
    }
  })
}

document.addEventListener("nav", () => {
  const graphs = graphsOnThePage()
  if (graphs.length === 0) {
    return
  }
  const root = graphs[0].dataset.figureRoot ?? "."
  let observer: IntersectionObserver | null = null
  let resizeTimer: number | undefined

  // ⌘P: the graphs at the bounds the teacher wrote, all of them, now -
  // beforeprint gives no time to wait, which is why the engine is fetched as
  // soon as the page has a graph rather than when the first one is seen.
  const beforePrint = () => drawEvery()
  window.addEventListener("beforeprint", beforePrint)

  const onResize = () => {
    window.clearTimeout(resizeTimer)
    resizeTimer = window.setTimeout(() => {
      for (const figure of graphsOnThePage()) {
        if (!figure.classList.contains("pl-plot-drawn")) {
          continue
        }
        if (figure.clientWidth > 0 && String(widthFor(figure)) !== figure.dataset.drawnWidth) {
          draw(figure)
        }
      }
    }, 150)
  }
  window.addEventListener("resize", onResize)

  window.addCleanup(() => {
    window.removeEventListener("beforeprint", beforePrint)
    window.removeEventListener("resize", onResize)
    window.clearTimeout(resizeTimer)
    if (observer !== null) {
      observer.disconnect()
    }
  })

  loadEngine(root).then((ready) => {
    if (!ready) {
      for (const figure of graphsOnThePage()) {
        say(figure, figure.dataset.figureMissing)
      }
      return
    }
    if (typeof IntersectionObserver === "undefined") {
      drawEvery()
      return
    }
    observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            const figure = entry.target as HTMLElement
            observer?.unobserve(figure)
            if (!figure.classList.contains("pl-plot-drawn")) {
              draw(figure)
            }
          }
        }
      },
      { threshold: 0.1 },
    )
    for (const figure of graphsOnThePage()) {
      observer.observe(figure)
    }
  })
})
