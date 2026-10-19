// My Progress (#545): the page's half, in the student's browser.
// contracts/shared-rules.json -> myProgress.
//
// The build wrote the page (`My Progress.md`, one placeholder element) and the
// manifest (public/progress-manifest.json: every page with counted items,
// grouped by the class that first linked it). This reads the manifest and the
// student's own ticks (#519's keys, through taskRules.readTicks) and draws the
// totals and one closed table per unit. Read-only: no box here can be ticked;
// each row links back to its page, so ticking happens with the page in view.
// Nothing is sent anywhere and nothing is written.
//
// * On every page shown (Quartz's `nav`, which also fires on the first load
//   and on Back), and only on the page that holds the placeholder - never in
//   a link's preview. Drawn again from scratch, every table closed.
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

type Row = { page: ManifestPage; done: number; total: number }

function tableOf(words: Record<string, string>, root: string, groups: { label: string | null; rows: Row[] }[]): HTMLElement {
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
  for (const group of groups) {
    if (group.label !== null) {
      const classRow = element("tr", "plantoir-progress-class")
      const classCell = element("th", "", group.label)
      classCell.setAttribute("colspan", "2")
      classCell.setAttribute("scope", "colgroup")
      classRow.append(classCell)
      body.append(classRow)
    }
    for (const row of group.rows) {
      const line = element("tr", "plantoir-progress-page")
      const pageCell = element("td", "")
      const link = element("a", "internal", row.page.title) as HTMLAnchorElement
      link.href = root + row.page.slug
      pageCell.append(link)
      const doneCell = element("td", "plantoir-progress-count", count(words, row.done, row.total))
      line.append(pageCell, doneCell)
      body.append(line)
    }
  }
  table.append(body)
  return table
}

function rowsOf(root: string, pages: ManifestPage[], totals: { done: number; total: number; touched: number }): Row[] {
  const rows: Row[] = []
  for (const page of pages) {
    const sum = rollUp(root, page, store)
    totals.done += sum.done
    totals.total += sum.total
    totals.touched += sum.touched
    rows.push({ page, done: sum.done, total: sum.total })
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
  overallLine.append(element("span", "", words.overall ?? ""), element("span", "plantoir-progress-count", count(words, overall.done, overall.total)))
  totals.append(overallLine)
  for (const section of sections) {
    const line = element("li", "")
    line.append(element("span", "", section.label), element("span", "plantoir-progress-count", count(words, section.done, section.total)))
    totals.append(line)
  }
  drawn.push(totals)
  if (overall.touched === 0) {
    drawn.push(element("p", "plantoir-progress-hint", words.noTicksYet ?? ""))
  }
  for (const section of sections) {
    const details = element("details", "plantoir-progress-unit") as HTMLDetailsElement
    const summary = element("summary", "")
    summary.append(element("span", "", section.label), element("span", "plantoir-progress-count", count(words, section.done, section.total)))
    details.append(summary, tableOf(words, root, section.groups))
    drawn.push(details)
  }
  holder.replaceChildren(...drawn)
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
  } catch {
    holder.replaceChildren(element("p", "plantoir-progress-empty", unreadable))
  }
})
