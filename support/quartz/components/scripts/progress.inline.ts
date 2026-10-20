// My Progress (#545): the page's half, in the student's browser.
// contracts/shared-rules.json -> myProgress.
//
// The build wrote the page (`My Progress.md`, one placeholder element) and the
// manifest (public/progress-manifest.json: every page with counted items,
// grouped by the class that first linked it). This reads the manifest and the
// student's own ticks (#519's keys, through taskRules.readTicks) and draws the
// totals and one closed table per unit. Read-only: no box here can be ticked;
// each row links back to its page, so ticking happens with the page in view.
// Each row also opens (#603), closed on load, to list that page's items -
// their words, whether each is ticked (the same reading as the count), each
// a link to the part of the page it is on.
// Nothing is sent anywhere. The one thing written is which levels the
// student left open (#603, Russell's smoke test), in this browser beside the
// ticks, so a return - by the site's links, Back or a reload - finds every
// level as it was left; a first visit finds everything folded.
//
// * On every page shown (Quartz's `nav`, which also fires on the first load
//   and on Back), and only on the page that holds the placeholder - never in
//   a link's preview. Drawn again from scratch, every level as remembered.
// * A generation counter drops a fetch that comes back after the student has
//   moved on, so a slow answer never draws onto another page.
// * Drawn with the DOM only (textContent), never as HTML: a page's title is
//   the teacher's words.

import { siteRootFrom } from "../../plugins/transformers/taskRules"
import { Manifest, ManifestPage, rollUp } from "../../plugins/emitters/progressRules"

const HOLDER = "[data-plantoir-progress]"
const PREVIEW = ".popover, .preview-container"

const store = {
  getItem(key: string): string | null {
    return window.localStorage.getItem(key)
  },
}

let generation = 0

function element(tag: string, className: string, text?: string): HTMLElement {
  const made = document.createElement(tag)
  if (className !== "") {
    made.className = className
  }
  if (text !== undefined) {
    made.textContent = text
  }
  return made
}

function count(words: Record<string, string>, done: number, total: number): string {
  return (words.count ?? "{done} / {total}").replace("{done}", String(done)).replace("{total}", String(total))
}

// A count in its pill (#603): set apart from the title beside it, in the
// look of Quartz's tag chips.
function pill(words: Record<string, string>, done: number, total: number): HTMLElement {
  return element("span", "plantoir-progress-count plantoir-progress-pill", count(words, done, total))
}

// ---- Which levels are open, remembered (#603) ----------------------------

const OPEN_KEY_PREFIX = "plantoir:progress-open:"

function openKey(root: string): string {
  return OPEN_KEY_PREFIX + root
}

function rememberedOpen(root: string): Set<string> {
  const open = new Set<string>()
  try {
    const kept = window.localStorage.getItem(openKey(root))
    const list = kept === null ? [] : (JSON.parse(kept) as unknown)
    if (Array.isArray(list)) {
      for (const name of list) {
        if (typeof name === "string") {
          open.add(name)
        }
      }
    }
  } catch {
    // Storage refused or unreadable: everything folded, as on a first visit.
  }
  return open
}

function rememberOpen(holder: HTMLElement, root: string) {
  const open: string[] = []
  for (const details of holder.querySelectorAll<HTMLDetailsElement>("details[data-level]")) {
    if (details.open) {
      open.push(details.dataset.level ?? "")
    }
  }
  try {
    window.localStorage.setItem(openKey(root), JSON.stringify(open))
  } catch {
    // Storage refused: the levels are simply not remembered.
  }
}

type Row = { page: ManifestPage; done: number; total: number; ticked: boolean[] }

// One page's cell: the page's name, a link back to it, as the summary of a
// CLOSED <details> - the same open-and-close as each unit's table - whose
// body lists the page's items. A click on the name follows the link (an
// interactive element in a summary does not toggle it); a click beside it,
// or on the marker, opens the list.
function pageCell(words: Record<string, string>, root: string, row: Row): HTMLElement {
  const cell = element("td", "")
  const details = element("details", "plantoir-progress-items") as HTMLDetailsElement
  details.dataset.level = "page:" + row.page.slug
  const summary = element("summary", "")
  const link = element("a", "internal", row.page.title) as HTMLAnchorElement
  link.href = root + row.page.slug
  summary.append(link)
  const list = element("ul", "plantoir-progress-item-list")
  let groupShown = ""
  for (let index = 0; index < row.page.items.length; index += 1) {
    const item = row.page.items[index]
    // The section's sub-heading above the items under it (#603), once.
    const group = typeof item.group === "string" ? item.group : ""
    if (group !== "" && group !== groupShown) {
      list.append(element("li", "plantoir-progress-group", group))
    }
    groupShown = group
    const ticked = row.ticked[index] === true
    const line = element("li", "plantoir-progress-item")
    line.dataset.ticked = ticked ? "true" : "false"
    const mark = element("span", "plantoir-progress-mark")
    mark.setAttribute("aria-hidden", "true")
    const state = element("span", "plantoir-progress-state", ticked ? (words.itemTicked ?? "") : (words.itemNotTicked ?? ""))
    const anchor = typeof item.anchor === "string" && item.anchor !== "" ? "#" + item.anchor : ""
    const itemLink = element("a", "internal plantoir-progress-item-link", item.text ?? "") as HTMLAnchorElement
    itemLink.href = root + row.page.slug + anchor
    line.append(mark, state, itemLink)
    list.append(line)
  }
  details.append(summary, list)
  cell.append(details)
  return cell
}

function tableOf(words: Record<string, string>, root: string, rows: Row[]): HTMLElement {
  const table = element("table", "plantoir-progress-table")
  const head = element("thead", "")
  const headRow = element("tr", "")
  const pageHeading = element("th", "", words.pageColumn ?? "")
  pageHeading.setAttribute("scope", "col")
  const doneHeading = element("th", "plantoir-progress-count", words.doneColumn ?? "")
  doneHeading.setAttribute("scope", "col")
  headRow.append(pageHeading, doneHeading)
  head.append(headRow)
  table.append(head)
  const body = element("tbody", "")
  for (const row of rows) {
    const line = element("tr", "plantoir-progress-page")
    const doneCell = element("td", "plantoir-progress-count")
    doneCell.append(pill(words, row.done, row.total))
    line.append(pageCell(words, root, row), doneCell)
    body.append(line)
  }
  table.append(body)
  return table
}

// What a unit opens to (#603): each class its own CLOSED <details> - the
// class's name and its count (the sum of its pages), as the unit's summary
// carries the unit's - holding the table of its pages; Other pages, which
// have no class, the table alone.
function unitContent(words: Record<string, string>, root: string, unitLabel: string, groups: { label: string | null; rows: Row[] }[]): HTMLElement[] {
  const made: HTMLElement[] = []
  for (const group of groups) {
    if (group.label === null) {
      made.push(tableOf(words, root, group.rows))
      continue
    }
    let done = 0
    let total = 0
    for (const row of group.rows) {
      done += row.done
      total += row.total
    }
    const day = element("details", "plantoir-progress-day") as HTMLDetailsElement
    day.dataset.level = "class:" + unitLabel + "\u0000" + group.label
    const summary = element("summary", "")
    summary.append(element("span", "", group.label), pill(words, done, total))
    day.append(summary, tableOf(words, root, group.rows))
    made.push(day)
  }
  return made
}

function rowsOf(root: string, pages: ManifestPage[], totals: { done: number; total: number; touched: number }): Row[] {
  const rows: Row[] = []
  for (const page of pages) {
    const sum = rollUp(root, page, store)
    totals.done += sum.done
    totals.total += sum.total
    totals.touched += sum.touched
    rows.push({ page, done: sum.done, total: sum.total, ticked: sum.ticked })
  }
  return rows
}

function draw(holder: HTMLElement, manifest: Manifest, root: string) {
  const words = manifest.words ?? {}
  const overall = { done: 0, total: 0, touched: 0 }
  const sections: { label: string; done: number; total: number; groups: { label: string | null; rows: Row[] }[] }[] = []
  for (const unit of manifest.units ?? []) {
    const totals = { done: 0, total: 0, touched: 0 }
    const groups: { label: string | null; rows: Row[] }[] = []
    for (const known of unit.classes) {
      groups.push({ label: known.label, rows: rowsOf(root, known.pages, totals) })
    }
    overall.done += totals.done
    overall.total += totals.total
    overall.touched += totals.touched
    sections.push({ label: unit.label, done: totals.done, total: totals.total, groups })
  }
  const otherPages = manifest.other?.pages ?? []
  if (otherPages.length > 0) {
    const totals = { done: 0, total: 0, touched: 0 }
    const rows = rowsOf(root, otherPages, totals)
    overall.done += totals.done
    overall.total += totals.total
    overall.touched += totals.touched
    sections.push({ label: manifest.other.label, done: totals.done, total: totals.total, groups: [{ label: null, rows }] })
  }

  const drawn: HTMLElement[] = []
  drawn.push(element("p", "plantoir-progress-intro", words.intro ?? ""))
  if (sections.length === 0) {
    drawn.push(element("p", "plantoir-progress-empty", words.nothingYet ?? ""))
    holder.replaceChildren(...drawn)
    return
  }
  const totals = element("ul", "plantoir-progress-totals")
  const overallLine = element("li", "plantoir-progress-overall")
  overallLine.append(element("span", "", words.overall ?? ""), pill(words, overall.done, overall.total))
  totals.append(overallLine)
  for (const section of sections) {
    const line = element("li", "")
    line.append(element("span", "", section.label), pill(words, section.done, section.total))
    totals.append(line)
  }
  drawn.push(totals)
  if (overall.touched === 0) {
    drawn.push(element("p", "plantoir-progress-hint", words.noTicksYet ?? ""))
  }
  for (const section of sections) {
    const details = element("details", "plantoir-progress-unit") as HTMLDetailsElement
    const summary = element("summary", "")
    details.dataset.level = "unit:" + section.label
    summary.append(element("span", "", section.label), pill(words, section.done, section.total))
    details.append(summary, ...unitContent(words, root, section.label, section.groups))
    drawn.push(details)
  }
  holder.replaceChildren(...drawn)
  // As the student left them; nothing remembered, everything folded.
  const open = rememberedOpen(root)
  for (const details of holder.querySelectorAll<HTMLDetailsElement>("details[data-level]")) {
    details.open = open.has(details.dataset.level ?? "")
  }
}

// Option-click (Alt) on any marker, as in the Finder (#603): that level and
// every level inside it open, or all close, together. A plain click - and
// Enter or Space on a focused summary - opens or closes that level alone,
// the browser's own behaviour. A click on a page's name follows its link.
function openOrCloseEverythingInside(event: MouseEvent) {
  if (!event.altKey) {
    return
  }
  const target = event.target as Element | null
  const summary = target?.closest("summary")
  if (!summary || target?.closest("a") !== null) {
    return
  }
  const details = summary.parentElement
  if (!(details instanceof HTMLDetailsElement)) {
    return
  }
  event.preventDefault()
  const opening = !details.open
  details.open = opening
  for (const inside of details.querySelectorAll("details")) {
    inside.open = opening
  }
}

function holderOnThePage(): HTMLElement | null {
  for (const found of document.querySelectorAll<HTMLElement>(HOLDER)) {
    if (found.closest(PREVIEW) === null) {
      return found
    }
  }
  return null
}

document.addEventListener("nav", async () => {
  generation += 1
  const mine = generation
  const holder = holderOnThePage()
  if (holder === null) {
    return
  }
  const root = siteRootFrom(document.body.dataset.slug ?? "", location.href)
  const unreadable = holder.dataset.unreadable ?? ""
  let manifest: Manifest | null = null
  try {
    const answer = await fetch(root + "progress-manifest.json", { cache: "no-cache" })
    if (answer.ok) {
      manifest = (await answer.json()) as Manifest
    }
  } catch {
    manifest = null
  }
  if (mine !== generation || !holder.isConnected) {
    return
  }
  if (manifest === null) {
    holder.replaceChildren(element("p", "plantoir-progress-empty", unreadable))
    return
  }
  try {
    draw(holder, manifest, root)
    // A property, not addEventListener: drawn again on every page shown,
    // the holder still has exactly one.
    holder.onclick = openOrCloseEverythingInside
    // `toggle` does not bubble, so it is caught on the way down; once per
    // holder (a drawing again of the same holder keeps the one listener).
    if (holder.dataset.remembering !== "yes") {
      holder.dataset.remembering = "yes"
      holder.addEventListener("toggle", () => rememberOpen(holder, root), true)
    }
  } catch {
    holder.replaceChildren(element("p", "plantoir-progress-empty", unreadable))
  }
})
