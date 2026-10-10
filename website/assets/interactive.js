// The Visualizations and Printing pages (v1.7.0, one Interactive page until
// DECISIONS 41): a Copy button on every block a teacher would type, and the
// live graphs, drawn by function-plot 1.25.4 —
// the same file, byte for byte, a class site carries when a page has a
// graph (#485 E1; licence in function-plot-LICENSE.txt). An external file
// because the site's policy allows no inline code but the one in the layout.

(function () {
  "use strict"

  // ---- Copy buttons ----

  function addCopyButton(block) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "copy"
    button.textContent = "Copy"
    button.addEventListener("click", function () {
      const text = block.querySelector("code").textContent
      navigator.clipboard.writeText(text).then(
        function () {
          button.textContent = "Copied"
          setTimeout(function () { button.textContent = "Copy" }, 1600)
        },
        function () {
          button.textContent = "Select and copy"
        }
      )
    })
    block.appendChild(button)
  }

  // ---- Graphs ----

  // The class site's proportions: a graph is 0.62 times as tall as it is wide.
  const HEIGHT_RATIO = 0.62

  function drawGraph(figure) {
    const box = figure.querySelector(".plot")
    const plot = JSON.parse(figure.dataset.plot)
    const width = Math.max(240, Math.round(box.clientWidth || 560))
    box.replaceChildren()
    const data = []
    for (const fn of plot.functions) {
      data.push({ fn: fn, graphType: "polyline" })
    }
    window.functionPlot({
      target: box,
      width: width,
      height: Math.round(width * HEIGHT_RATIO),
      grid: true,
      xAxis: { domain: [plot.bounds[0], plot.bounds[1]] },
      yAxis: { domain: [plot.bounds[2], plot.bounds[3]] },
      data: data,
    })
    const svg = box.querySelector("svg")
    if (svg) {
      svg.setAttribute("viewBox", "0 0 " + svg.getAttribute("width") + " " + svg.getAttribute("height"))
      svg.setAttribute("aria-hidden", "true")
    }
    figure.classList.add("drawn")
  }

  // function-plot reads `window.math` when it exists, and a browser makes
  // every element with an id a property of window: a section with
  // id="math" made every graph fail with "o[t] is not a function" (measured,
  // Chrome for Testing 155). So this page has no element with that id; the
  // /math address lands on #diagrams-and-graphs.

  // A plain scroll over a graph scrolls the page, as it does on a class site;
  // ⌘ or Ctrl with the scroll zooms. Stopped on the way down, before the
  // graph's own zoom hears it, and never prevented, so the page still moves.
  function letTheWheelScroll(figure) {
    figure.addEventListener("wheel", function (event) {
      if (!event.ctrlKey && !event.metaKey) {
        event.stopPropagation()
      }
    }, { capture: true })
  }

  function start() {
    for (const block of document.querySelectorAll("pre.fence")) {
      addCopyButton(block)
    }
    if (typeof window.functionPlot !== "function") {
      return
    }
    const graphs = document.querySelectorAll("figure.live-graph")
    for (const figure of graphs) {
      letTheWheelScroll(figure)
      try {
        drawGraph(figure)
      } catch (error) {
        figure.classList.remove("drawn")
      }
    }
    let lastWidth = window.innerWidth
    window.addEventListener("resize", function () {
      if (Math.abs(window.innerWidth - lastWidth) < 40) {
        return
      }
      lastWidth = window.innerWidth
      for (const figure of graphs) {
        try {
          drawGraph(figure)
        } catch (error) {
          figure.classList.remove("drawn")
        }
      }
    })
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start)
  } else {
    start()
  }
})()
