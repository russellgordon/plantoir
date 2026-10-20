// A link to a heading lands ON the heading (#604), site-wide.
//
// The browser scrolls to `#heading` as soon as the page is laid out - before
// the runnable code's editors, the diagrams and graphs, the maths' faces and
// the pictures above the heading have taken their size, so the heading is
// pushed down past the window. Chrome scrolls to it again later; Safari and
// Arc do not (measured on ICS3U, issue #604: 1,706 px short at +1 s).
//
// So, on every page shown with a hash (Quartz's `nav`: the first load and
// every page change), the heading is scrolled to again each time the page's
// content actually changes size (a ResizeObserver on the page's column - the
// one signal every late piece shares, whatever draws it) and once the faces
// are ready - and again whenever something else moves the window off it
// (measured: the sidebar smooth-scrolls its current entry into view, which
// on a long sidebar drags the whole window past the heading). It stops the
// moment the reader moves (a wheel, a touch, a key, a press), at the next
// page, or after a cap; no hash, no heading: nothing.

let stopWatching: (() => void) | null = null

const READER_MOVED = ["wheel", "touchstart", "keydown", "mousedown"]
const CAP_MS = 8000

document.addEventListener("nav", () => {
  stopWatching?.()
  if (location.hash.length < 2) {
    return
  }
  let heading: HTMLElement | null = null
  try {
    heading = document.getElementById(decodeURIComponent(location.hash.slice(1)))
  } catch {
    return
  }
  const column = document.querySelector(".center")
  if (heading === null || column === null) {
    return
  }
  const target = heading
  // Where the heading rests once landed: the window's top, or lower when the
  // page ends too soon for it to get there.
  let rest = 0
  const land = () => {
    if (target.isConnected) {
      // At once, not smoothly (the site's `scroll-behavior: smooth`): a
      // correction should not animate, and a smooth scroll still running
      // would carry on past a reader's own wheel (measured in the check).
      target.scrollIntoView({ block: "start", behavior: "instant" })
      rest = target.getBoundingClientRect().top
    }
  }
  const moved = () => {
    if (target.isConnected && Math.abs(target.getBoundingClientRect().top - rest) > 2) {
      land()
    }
  }
  const observer = new ResizeObserver(land)
  const stop = () => {
    observer.disconnect()
    window.removeEventListener("scroll", moved)
    for (const name of READER_MOVED) {
      window.removeEventListener(name, stop, true)
    }
    window.clearTimeout(cap)
    if (stopWatching === stop) {
      stopWatching = null
    }
  }
  const cap = window.setTimeout(stop, CAP_MS)
  for (const name of READER_MOVED) {
    window.addEventListener(name, stop, { capture: true, passive: true })
  }
  stopWatching = stop
  observer.observe(column)
  window.addEventListener("scroll", moved, { passive: true })
  document.fonts?.ready.then(() => {
    if (stopWatching === stop) {
      land()
    }
  })
})
