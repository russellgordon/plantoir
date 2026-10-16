// The sidebar's page marker (#515, support/quartz/components/styles/
// sidebarPageMarker.scss), read off the BUILT sidebar in headless Chrome for
// Testing. The sidebar's rows are drawn in the browser from contentIndex.json
// (patches/explorer.inline.ts clones a <template> per row), so no page's HTML
// holds a row and a text search of the site could not see one: this is why the
// check needs a browser.
//
// On the planted fixture page, inside the planted folder and the folder planted
// inside it, both opened the way a student opens them (a click on the chevron):
//
// 1. every page row carries the dot (a ::before with a drawn box) - checked
//    FIRST, so a site without the rule fails here and says so;
// 2. no folder row carries one, at any depth, and no page at the top level of
//    the sidebar does; the planted folders still have their chevrons;
// 3. the long title wraps, its second line starts exactly under its first
//    letter, and the dot sits left of the first line, inside it;
// 4. the current page's link is still Quartz's highlight colour at full
//    opacity, a hovered link turns the highlight colour, and the dot is the
//    same on the current, hovered and a plain row;
// 5. the dot's colour, blended over the sidebar's own background, against
//    that background: at least 3:1 (WCAG 2.2, 1.4.11). The figure is printed;
//
// then all of it again in DARK mode (emulated, page reloaded), then on the
// planted folder's own FOLDER page (the rule is in the one index.css every page
// links), then under forced colours (each dot at least 3:1 against its row,
// since a forced Canvas-on-Canvas dot still has a box).
//
// Folders stay open between loads (Quartz saves the sidebar's state in
// localStorage, and the profile is fresh per RUN, not per load), so a folder is
// clicked only when it is not already open, and is then asserted open.
// Nothing waits a fixed time for layout: each wait polls for the state it needs.
//
// Kept OUT of scripts/ for the reason print_handout.mjs is: it needs a
// browser on the Mac, not the image. No packages: Node 22's own WebSocket.
//
//   node browser-checks/sidebar_page_marker.mjs <chrome> <fixture page url> <folder page url> \
//        <folder name> <nested folder name> <long page title>

import { spawn } from "node:child_process"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const [chromePath, pageUrl, folderPageUrl, folderName, nestedFolderName, longTitle] = process.argv.slice(2)
const nestedPath = folderName + "/" + nestedFolderName
if (!chromePath || !pageUrl || !folderPageUrl || !folderName || !nestedFolderName || !longTitle) {
  console.error("usage: node sidebar_page_marker.mjs <chrome> <fixture page> <folder page> <folder> <nested folder> <long title>")
  process.exit(2)
}

// WCAG 2.2 SC 1.4.11, non-text contrast.
const LEAST_CONTRAST = 3
// Sub-pixel layout: a line that starts "under the first letter" may differ by
// a fraction of a pixel.
const TOLERANCE = 0.5

const work = mkdtempSync(join(tmpdir(), "plantoir-sidebar-marker-check-"))
const chrome = spawn(chromePath, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1512,900",
  "--use-mock-keychain", "--password-store=basic",
  "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows", "--hide-scrollbars", "--mute-audio",
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] })

function finish(code, message) {
  console.log(message)
  chrome.kill()
  setTimeout(() => {
    rmSync(work, { recursive: true, force: true })
    process.exit(code)
  }, 300)
}

const timer = setTimeout(() => finish(1, "FAIL: the sidebar was not checked within 120 s"), 120000)
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// In the page: the helpers every step below uses. Defined once per load.
const HELPERS = `
(() => {
  const plain = (text) => (text || "").replace(/\\s+/g, " ").trim()
  const ownList = (row) => {
    const outer = row ? row.querySelector(":scope > .folder-outer") : null
    return outer ? outer.querySelector(":scope > ul") : null
  }
  // A folder's row by its path of names, "Discussions/Tasks": each name is
  // looked for among the rows of the list before it only, so a folder inside
  // Discussions that shares its name with a top-level folder is not confused
  // with it.
  const folderRow = (path) => {
    let list = document.querySelector(".explorer .explorer-ul")
    let found = null
    for (const name of path.split("/")) {
      found = null
      if (!list) return null
      for (const row of list.children) {
        const title = row.querySelector(":scope > .folder-container .folder-title")
        if (title && plain(title.textContent) === name) found = row
      }
      if (!found) return null
      list = ownList(found)
    }
    return found
  }
  const pageRowsIn = (list) => {
    const rows = []
    if (!list) return rows
    for (const row of list.children) if (row.matches("li:has(> a)")) rows.push(row)
    return rows
  }
  // "rgb(1, 2, 3)" or "rgba(1, 2, 3, 0.5)" or "color(srgb ...)" -> [r, g, b, a] in 0..1
  const channels = (colour) => {
    const probe = document.createElement("canvas").getContext("2d", { willReadFrequently: true })
    probe.clearRect(0, 0, 1, 1)
    probe.fillStyle = "#000"
    probe.fillStyle = colour
    probe.fillRect(0, 0, 1, 1)
    const [r, g, b, a] = probe.getImageData(0, 0, 1, 1).data
    return [r / 255, g / 255, b / 255, a / 255]
  }
  const resolve = (expression) => {
    const span = document.createElement("span")
    span.style.color = expression
    document.body.appendChild(span)
    const colour = getComputedStyle(span).color
    span.remove()
    return colour
  }
  const backdrop = (element) => {
    for (let node = element; node; node = node.parentElement) {
      const colour = getComputedStyle(node).backgroundColor
      if (channels(colour)[3] === 1) return colour
    }
    return getComputedStyle(document.documentElement).backgroundColor
  }
  const luminance = ([r, g, b]) => {
    const linear = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
  }
  const contrast = (one, other) => {
    const [high, low] = [luminance(one), luminance(other)].sort((x, y) => y - x)
    return (high + 0.05) / (low + 0.05)
  }
  window.__plMarker = { plain, folderRow, ownList, pageRowsIn, channels, resolve, backdrop, contrast, rows: [] }
  return true
})()
`

let buffered = ""
chrome.stderr.on("data", (chunk) => {
  connect(chunk).catch((error) => finish(1, "FAIL: could not drive the browser: " + (error && error.stack || error)))
})

async function connect(chunk) {
  if (buffered === null) return
  buffered += chunk.toString()
  const found = /DevTools listening on (ws:\/\/[^\s]+)/.exec(buffered)
  if (!found) return
  buffered = null
  const port = new URL(found[1]).port
  const created = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" })).json()
  const socket = new WebSocket(created.webSocketDebuggerUrl)
  let id = 0
  const waiting = new Map()
  const send = (method, params = {}) => new Promise((resolve) => {
    id += 1
    waiting.set(id, resolve)
    socket.send(JSON.stringify({ id, method, params }))
  })
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) {
      waiting.get(message.id)(message.result ?? { error: message.error })
      waiting.delete(message.id)
    }
  }
  const evaluate = async (expression) => {
    const answer = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })
    if (answer?.exceptionDetails) throw new Error("in the page: " + JSON.stringify(answer.exceptionDetails).slice(0, 600))
    return answer?.result?.value
  }
  // Polls an expression until it returns something truthy; the answer, or null.
  const until = async (expression, tries = 80) => {
    for (let attempt = 0; attempt < tries; attempt += 1) {
      const value = await evaluate(expression)
      if (value) return value
      await pause(100)
    }
    return null
  }
  const open = async (url) => {
    await send("Page.navigate", { url })
    if (!(await until(`document.readyState === "complete"`))) return false
    // The sidebar is drawn after the page loads, from contentIndex.json.
    if (!(await until(`document.querySelector(".explorer .explorer-ul > li") !== null`))) return false
    await evaluate(HELPERS)
    return true
  }
  // The ::before box of the element at window.__plMarker.rows[index], from the
  // browser's own layout (CDP), or null when the row has no drawn marker.
  const markerBox = async (index) => {
    const handle = await send("Runtime.evaluate", { expression: `window.__plMarker.rows[${index}]` })
    const objectId = handle?.result?.objectId
    if (!objectId) return null
    const described = await send("DOM.describeNode", { objectId, depth: 1 })
    const pseudo = (described?.node?.pseudoElements || []).find((node) => node.pseudoType === "before")
    if (!pseudo) return null
    const model = await send("DOM.getBoxModel", { backendNodeId: pseudo.backendNodeId })
    const quad = model?.model?.border
    if (!quad) return null
    const xs = [quad[0], quad[2], quad[4], quad[6]]
    const ys = [quad[1], quad[3], quad[5], quad[7]]
    const box = { left: Math.min(...xs), right: Math.max(...xs), top: Math.min(...ys), bottom: Math.max(...ys) }
    if (box.right - box.left <= 0 || box.bottom - box.top <= 0) return null
    return box
  }
  // Opens the named folder with a click on its chevron, unless it is open
  // already; then waits until its list has a height that has stopped growing
  // (the folder opens with a .3 s grid transition).
  const openFolder = async (name) => {
    const state = await evaluate(`(() => {
      const row = window.__plMarker.folderRow(${JSON.stringify(name)})
      if (!row) return "missing"
      const outer = row.querySelector(":scope > .folder-outer")
      const icon = row.querySelector(":scope > .folder-container > svg.folder-icon")
      if (!outer || !icon) return "no chevron"
      if (!outer.classList.contains("open")) icon.dispatchEvent(new MouseEvent("click", { bubbles: true }))
      return "ok"
    })()`)
    if (state !== "ok") return state
    let last = -1
    for (let attempt = 0; attempt < 60; attempt += 1) {
      const height = await evaluate(`(() => {
        const row = window.__plMarker.folderRow(${JSON.stringify(name)})
        const outer = row.querySelector(":scope > .folder-outer")
        if (!outer.classList.contains("open")) return -1
        return outer.querySelector(":scope > ul").getBoundingClientRect().height
      })()`)
      if (height > 0 && height === last) return "ok"
      last = height
      await pause(100)
    }
    return last === -1 ? "would not open" : "never stopped opening"
  }

  const problems = []
  const report = {}

  // One full pass over the open sidebar: steps 1 to 5. `mode` names it in the
  // report and in every problem it finds.
  const checkSidebar = async (mode, { geometry = true, current = true } = {}) => {
    const seen = { mode }
    report[mode] = seen
    for (const name of [folderName, nestedPath]) {
      const state = await openFolder(name)
      if (state !== "ok") {
        problems.push(`${mode}: the folder "${name}" ${state === "missing" ? "is not in the sidebar - the check would prove nothing" : state === "no chevron" ? "has no chevron to open it (is it in the course's expandable folders?)" : state}`)
        return
      }
    }
    // Every row to be judged, gathered into window.__plMarker.rows so the
    // browser's layout of each one's ::before can be asked for by index.
    const rows = await evaluate(`(() => {
      const m = window.__plMarker
      const folderList = m.ownList(m.folderRow(${JSON.stringify(folderName)}))
      const nestedList = m.ownList(m.folderRow(${JSON.stringify(nestedPath)}))
      const entries = []
      const add = (row, kind) => {
        m.rows.push(row)
        const link = row.querySelector(":scope > a") || row.querySelector(".folder-title")
        const before = getComputedStyle(row, "::before")
        entries.push({ index: m.rows.length - 1, kind, title: m.plain(link ? link.textContent : row.textContent),
          content: before.content, active: !!row.querySelector(":scope > a.active") })
      }
      m.rows = []
      for (const row of m.pageRowsIn(folderList)) add(row, "page in the folder")
      for (const row of m.pageRowsIn(nestedList)) add(row, "page in the nested folder")
      for (const row of document.querySelectorAll(".explorer li")) {
        if (row.querySelector(":scope > .folder-container")) add(row, "folder")
      }
      for (const row of document.querySelectorAll(".explorer .explorer-ul > li")) {
        if (row.matches("li:has(> a)")) add(row, "page at the top level")
      }
      return entries
    })()`)
    for (const row of rows) row.box = await markerBox(row.index)
    const of = (kind) => rows.filter((row) => row.kind === kind)
    const marked = (row) => row.content !== "none" && row.content !== "normal" && row.box !== null

    // 1. Page rows carry the marker.
    for (const kind of ["page in the folder", "page in the nested folder"]) {
      const pages = of(kind)
      if (pages.length === 0) problems.push(`${mode}: no ${kind} - the check would prove nothing`)
      const bare = pages.filter((row) => !marked(row))
      if (bare.length > 0) problems.push(`${mode}: page rows carry no marker (${kind}): ${bare.map((row) => `"${row.title}"`).join(", ")}`)
    }
    seen.pagesMarked = rows.filter((row) => row.kind.startsWith("page in") && marked(row)).length
    if (problems.length > 0) return

    // 2. Folder rows, and pages at the top level, do not; the chevrons stay.
    const folders = of("folder")
    if (folders.length === 0) problems.push(`${mode}: no folder rows - the check would prove nothing`)
    const markedFolders = folders.filter((row) => row.content !== "none" || row.box !== null)
    if (markedFolders.length > 0) problems.push(`${mode}: folder row carries a marker: ${markedFolders.map((row) => `"${row.title}"`).join(", ")}`)
    const topPages = of("page at the top level")
    if (topPages.length === 0) problems.push(`${mode}: no page at the top level of the sidebar - the check would prove nothing`)
    const markedTop = topPages.filter((row) => row.content !== "none" || row.box !== null)
    if (markedTop.length > 0) problems.push(`${mode}: page at the top level carries a marker: ${markedTop.map((row) => `"${row.title}"`).join(", ")}`)
    seen.foldersBare = folders.length - markedFolders.length
    seen.topPagesBare = topPages.length - markedTop.length

    // 3. The long title: wrapped, hung, dot beside its first line.
    const long = rows.find((row) => row.kind === "page in the folder" && row.title === longTitle)
    if (!long) {
      problems.push(`${mode}: the long-titled page "${longTitle}" is not in the folder - the check would prove nothing`)
      return
    }
    if (geometry) {
      const lines = await evaluate(`(() => {
        const row = window.__plMarker.rows[${long.index}]
        const style = getComputedStyle(row)
        const edge = row.getBoundingClientRect().left + parseFloat(style.borderLeftWidth) + parseFloat(style.paddingLeft)
        const rects = Array.from(row.querySelector(":scope > a").getClientRects()).map((r) => ({ left: r.left, top: r.top, bottom: r.bottom }))
        return { edge, rowLeft: row.getBoundingClientRect().left, rects }
      })()`)
      seen.longTitleLines = lines.rects.length
      if (lines.rects.length < 2) {
        problems.push(`${mode}: the long title did not wrap (${lines.rects.length} line) - the hanging indent is not proven`)
      } else {
        const [first, second] = lines.rects
        if (Math.abs(second.left - first.left) > TOLERANCE) problems.push(`${mode}: the long title's second line starts at ${second.left.toFixed(1)} px, not under its first letter at ${first.left.toFixed(1)} px`)
        if (Math.abs(second.left - lines.edge) > TOLERANCE) problems.push(`${mode}: the long title's second line starts at ${second.left.toFixed(1)} px, not at the row's content edge ${lines.edge.toFixed(1)} px`)
        const dot = long.box
        if (dot.right > first.left + TOLERANCE) problems.push(`${mode}: the dot (to ${dot.right.toFixed(1)} px) is not left of the title (from ${first.left.toFixed(1)} px)`)
        if (dot.left < lines.rowLeft - TOLERANCE) problems.push(`${mode}: the dot (from ${dot.left.toFixed(1)} px) sticks out of its row (from ${lines.rowLeft.toFixed(1)} px)`)
        const middle = (dot.top + dot.bottom) / 2
        if (middle < first.top || middle > first.bottom) problems.push(`${mode}: the dot's middle (${middle.toFixed(1)} px) is not beside the title's first line (${first.top.toFixed(1)}-${first.bottom.toFixed(1)} px)`)
        seen.hang = { dotLeft: +(dot.left - lines.rowLeft).toFixed(2), dotWidth: +(dot.right - dot.left).toFixed(2), titleLeft: +(first.left - lines.rowLeft).toFixed(2), secondLineLeft: +(second.left - lines.rowLeft).toFixed(2) }
      }
      // Every page row, not only the long one: the dot is left of the title's
      // FIRST line and level with it - so a title whose first word is too wide
      // for the line (planted too) does not leave the dot alone on a line.
      let beside = 0
      for (const row of rows.filter((entry) => entry.kind.startsWith("page in") && entry.box !== null)) {
        const first = await evaluate(`(() => {
          const r = window.__plMarker.rows[${row.index}].querySelector(":scope > a").getClientRects()[0]
          return r ? { left: r.left, top: r.top, bottom: r.bottom } : null
        })()`)
        const middle = (row.box.top + row.box.bottom) / 2
        if (!first) problems.push(`${mode}: "${row.title}" has no line to measure`)
        else if (middle < first.top || middle > first.bottom || row.box.right > first.left + TOLERANCE) problems.push(`${mode}: the dot of "${row.title}" (middle ${middle.toFixed(1)} px) is not beside its first line (${first.top.toFixed(1)}-${first.bottom.toFixed(1)} px, from ${first.left.toFixed(1)} px)`)
        else beside += 1
      }
      seen.dotsBesideFirstLine = beside
    }

    // 4. The current page, a hovered link, and the dot on each.
    const active = rows.find((row) => row.active)
    if (current && !active) {
      problems.push(`${mode}: no row is the current page - the check would prove nothing`)
      return
    }
    const style = (index) => evaluate(`(() => {
      const m = window.__plMarker
      const row = m.rows[${index}]
      const link = row.querySelector(":scope > a")
      const before = getComputedStyle(row, "::before")
      return { colour: getComputedStyle(link).color, opacity: getComputedStyle(link).opacity,
               dot: before.backgroundColor + " @ " + before.opacity, tertiary: m.resolve("var(--tertiary)"),
               hovered: link.matches(":hover") }
    })()`)
    // A colour mid-transition (Quartz eases a link's colour over .2 s) is read
    // until two reads agree.
    const settled = async (index, wanted) => {
      let last = null
      for (let attempt = 0; attempt < 40; attempt += 1) {
        const now = await style(index)
        if (last && now.colour === last.colour && (!wanted || wanted(now))) return now
        last = now
        await pause(100)
      }
      return last
    }
    const activeStyle = current ? await settled(active.index) : null
    if (current && (activeStyle.colour !== activeStyle.tertiary || activeStyle.opacity !== "1")) problems.push(`${mode}: the current page's link is ${activeStyle.colour} at ${activeStyle.opacity}, not Quartz's ${activeStyle.tertiary} at 1`)
    const others = rows.filter((row) => row.kind === "page in the folder" && !row.active)
    if (others.length < 2) {
      problems.push(`${mode}: fewer than two other pages in the folder - the hover check would prove nothing`)
      return
    }
    const plainRow = others[others.length - 1]
    const plainStyle = await settled(plainRow.index)
    seen.plainLink = plainStyle.colour + " @ " + plainStyle.opacity
    if (plainStyle.colour === plainStyle.tertiary) problems.push(`${mode}: a plain page's link is already the highlight colour - the hover check would prove nothing`)
    if (current) {
      const hovered = others[0]
      let hoveredStyle = null
      for (let attempt = 0; attempt < 5 && !(hoveredStyle && hoveredStyle.hovered); attempt += 1) {
        const point = await evaluate(`(() => {
          const link = window.__plMarker.rows[${hovered.index}].querySelector(":scope > a")
          link.scrollIntoView({ block: "center" })
          const rect = link.getClientRects()[0]
          return { x: rect.left + Math.min(10, rect.width / 2), y: (rect.top + rect.bottom) / 2 }
        })()`)
        await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: point.x, y: point.y })
        hoveredStyle = await settled(hovered.index, (now) => now.hovered && now.colour === now.tertiary)
      }
      seen.hoveredLink = hoveredStyle.colour + (hoveredStyle.hovered ? " (hovered)" : " (not hovered)")
      if (!hoveredStyle.hovered) problems.push(`${mode}: the mouse could not be put over "${hovered.title}"`)
      else if (hoveredStyle.colour !== hoveredStyle.tertiary) problems.push(`${mode}: a hovered link is ${hoveredStyle.colour}, not Quartz's ${hoveredStyle.tertiary}`)
      if (hoveredStyle.dot !== plainStyle.dot) problems.push(`${mode}: the dot on a hovered row (${hoveredStyle.dot}) is not the dot on a plain row (${plainStyle.dot})`)
      await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: 1500, y: 890 })
    }
    if (current && activeStyle.dot !== plainStyle.dot) problems.push(`${mode}: the dot on the current page's row (${activeStyle.dot}) is not the dot on a plain row (${plainStyle.dot})`)
    seen.dot = plainStyle.dot

    // 5. Contrast against the sidebar's own background.
    const ratio = await evaluate(`(() => {
      const m = window.__plMarker
      const row = m.rows[${plainRow.index}]
      const before = getComputedStyle(row, "::before")
      const [r, g, b, a] = m.channels(before.backgroundColor)
      const alpha = a * parseFloat(before.opacity)
      const ground = m.channels(m.backdrop(row))
      const blended = [r * alpha + ground[0] * (1 - alpha), g * alpha + ground[1] * (1 - alpha), b * alpha + ground[2] * (1 - alpha)]
      return { ratio: m.contrast(blended, ground), ground: m.backdrop(row) }
    })()`)
    seen.contrast = +ratio.ratio.toFixed(2)
    seen.background = ratio.ground
    if (ratio.ratio < LEAST_CONTRAST) problems.push(`${mode}: the dot is ${ratio.ratio.toFixed(2)}:1 against the sidebar's ${ratio.ground}, under ${LEAST_CONTRAST}:1`)
  }

  socket.onopen = async () => {
    await send("Page.enable")
    await send("DOM.enable")
    await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] })
    if (!(await open(pageUrl))) return finish(1, "FAIL: the page or its sidebar did not load " + pageUrl)
    await send("DOM.getDocument", { depth: -1 })
    const lightTheme = await evaluate(`document.documentElement.getAttribute("saved-theme")`)
    if (lightTheme !== "light") problems.push(`light: the page is in ${lightTheme} mode, not light`)
    await checkSidebar("light")

    if (problems.length === 0) {
      await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] })
      if (!(await open(pageUrl))) return finish(1, "FAIL: the page or its sidebar did not load again in dark mode " + pageUrl)
      await send("DOM.getDocument", { depth: -1 })
      const darkTheme = await evaluate(`document.documentElement.getAttribute("saved-theme")`)
      if (darkTheme !== "dark") problems.push(`dark: the page is in ${darkTheme} mode, not dark - the dark check would prove nothing`)
      else await checkSidebar("dark")
    }

    if (problems.length === 0) {
      if (!(await open(folderPageUrl))) return finish(1, "FAIL: the folder page or its sidebar did not load " + folderPageUrl)
      await send("DOM.getDocument", { depth: -1 })
      await checkSidebar("the folder page, dark", { geometry: false, current: false })
    }

    if (problems.length === 0) {
      await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }, { name: "forced-colors", value: "active" }] })
      if (!(await open(pageUrl))) return finish(1, "FAIL: the page or its sidebar did not load under forced colours " + pageUrl)
      await send("DOM.getDocument", { depth: -1 })
      const forced = await evaluate(`matchMedia("(forced-colors: active)").matches`)
      if (!forced) problems.push("forced colours: the browser did not take the emulated forced colours - the check would prove nothing")
      else {
        for (const name of [folderName]) {
          const state = await openFolder(name)
          if (state !== "ok") problems.push(`forced colours: the folder "${name}" ${state}`)
        }
        const dots = await evaluate(`(() => {
          const m = window.__plMarker
          m.rows = m.pageRowsIn(m.ownList(m.folderRow(${JSON.stringify(folderName)})))
          // Chrome forces a background to Canvas but keeps its alpha, so a dot
          // that is "there" can be Canvas on Canvas: what counts is contrast.
          return m.rows.map((row) => {
            const before = getComputedStyle(row, "::before")
            const [r, g, b, a] = m.channels(before.backgroundColor)
            const alpha = a * parseFloat(before.opacity)
            const ground = m.channels(m.backdrop(row))
            const blended = [r * alpha + ground[0] * (1 - alpha), g * alpha + ground[1] * (1 - alpha), b * alpha + ground[2] * (1 - alpha)]
            return { colour: before.backgroundColor, ratio: m.contrast(blended, ground), ground: m.backdrop(row) }
          })
        })()`)
        let drawn = 0
        for (let index = 0; index < dots.length; index += 1) {
          if ((await markerBox(index)) !== null && dots[index].ratio >= LEAST_CONTRAST) drawn += 1
        }
        const lowest = dots.length ? Math.min(...dots.map((dot) => dot.ratio)) : 0
        report["forced colours"] = { pagesSeen: drawn, of: dots.length, dot: dots.length ? dots[0].colour : null, ground: dots.length ? dots[0].ground : null, contrast: +lowest.toFixed(2) }
        if (dots.length === 0 || drawn !== dots.length) problems.push(`forced colours: ${dots.length - drawn} of ${dots.length} page rows have no dot that can be seen (lowest ${lowest.toFixed(2)}:1 against the row, under ${LEAST_CONTRAST}:1)`)
      }
    }

    clearTimeout(timer)
    const good = problems.length === 0
    const light = report.light?.contrast
    const dark = report.dark?.contrast
    const forcedRatio = report["forced colours"]?.contrast
    const summary = `light ${light ?? "-"}:1, dark ${dark ?? "-"}:1, forced colours ${forcedRatio ?? "-"}:1`
    finish(good ? 0 : 1, (good ? `OK: ${summary}\n` : "FAIL: " + problems.join("\n  ") + "\n") + JSON.stringify(report))
  }
}
