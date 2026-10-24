// The `geogebra-sketch` figure (#578): MPM2D's The Slope-Angle Conjecture,
// its sketch (Slope Angle Conjecture.ggb, saved from GeoGebra beside the
// page) opened with a tap and drawn, with the "The sketch" heading and the
// sentence under it above it. The body of an async function run by
// webwindow.swift --prepare; `timeoutMs` is its bound. Returns "ready" or
// the reason it is not. The classes are the site's own
// (support/quartz/components/scripts/geogebra.inline.ts).
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
const frames = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
let figure = null
while (Date.now() < until) {
  figure = document.querySelector("figure.pl-geogebra[data-geogebra]")
  if (figure && figure.querySelector(".pl-geogebra-open")) break
  await pause(100)
}
if (!figure) return "the page has no GeoGebra sketch"
const button = figure.querySelector(".pl-geogebra-open")
if (!button) return "the sketch has no button to open it"
button.click()
const opened = () => figure.classList.contains("pl-geogebra-loaded") && figure.querySelector(".pl-geogebra-applet canvas")
while (Date.now() < until && !opened()) await pause(100)
if (!opened()) {
  const message = figure.querySelector(".pl-geogebra-message")
  return "the sketch did not open" + (message ? ": " + message.textContent : "")
}
// The applet paints its first frame after it says it has loaded: two
// animation frames, then its canvas must have a size.
await frames()
const canvas = figure.querySelector(".pl-geogebra-applet canvas")
if (canvas.getBoundingClientRect().width < 200) return "the sketch's canvas is " + Math.round(canvas.getBoundingClientRect().width) + " pt wide"
document.activeElement && document.activeElement.blur && document.activeElement.blur()
// Framing: the heading above the sketch 64 points below the window's top,
// and refused if the sketch's bottom (its attribution included) is then
// cut off at the window's bottom.
const heading = document.getElementById("the-sketch")
if (!heading) return "the page has no heading with the id the-sketch"
window.scrollBy(0, heading.getBoundingClientRect().top - 64)
await frames()
const bottom = figure.getBoundingClientRect().bottom
if (bottom > window.innerHeight - 8) return "the sketch ends " + Math.round(bottom) + " pt down, below the " + window.innerHeight + " pt window"
return "ready"
