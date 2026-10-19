// My Progress (#545): the RULES, with nothing of Quartz's in them -
// contracts/shared-rules.json -> myProgress.
//
// Pure: no DOM, no Node. Three readers import this file, each bundled on its
// own:
//
// * the emitter (plantoirProgress.ts), which reads the counted items off the
//   built pages (countedItems) and writes the manifest (buildManifest);
// * the page's own script (components/scripts/progress.inline.ts), which adds
//   up a student's ticks against the manifest (rollUp);
// * the sidebar (explorer.inline.ts, one line the build adds), which puts the
//   page directly under the class folder (pinnedOrder).
//
// Item ids are NEVER worked out here: they are the stamps PlantoirTasks put on
// the boxes (`data-task-item`, taskRules.taskItemId), read from the tree the
// way the page's own script reads them from the page (#519 review F1).
//
// scripts/check_progress_rules_against_the_site.py bundles this very file and
// runs every case in the contract through it in Node.

import { readTicks, TickStore } from "../transformers/taskRules"

// ---- Which headings count -----------------------------------------------------

// A heading's words as the build compares them: Unicode's composed form (NFC),
// curly quotes made straight (the site's parser curls a teacher's ' and ",
// which the build reads as typed), every run of white space made one space,
// trimmed, every trailing punctuation mark and space taken off ("Success
// criteria:" is "success criteria"), lower-cased. The same rule as
// scripts/my_progress.py's normalised_heading.
export function normalisedHeading(text: string): string {
  let words = text.normalize("NFC").replace(/[\u2018\u2019]/g, "'").replace(/[\u201c\u201d]/g, '"')
  words = words.replace(/\s+/gu, " ").trim()
  words = words.replace(/[\p{P}\s]+$/u, "")
  return words.toLowerCase()
}

type Node = {
  type: string
  tagName?: string
  value?: string
  properties?: Record<string, unknown>
  children?: Node[]
}

const HEADING = /^h([1-6])$/

// A heading's text as a student reads it: every text inside it, but not the
// link Quartz appends to each heading (role="anchor"), which carries no words.
function textOf(node: Node): string {
  if (node.type === "text") {
    return node.value ?? ""
  }
  if (node.type === "element" && node.properties?.role === "anchor") {
    return ""
  }
  let text = ""
  for (const child of node.children ?? []) {
    text += textOf(child)
  }
  return text
}

export type CountedItem = { id: string; checked: boolean }

// Every stamped box inside one block, in page order.
function stampedBoxes(node: Node, found: CountedItem[]) {
  if (node.type === "element" && node.tagName === "input") {
    const id = node.properties?.dataTaskItem
    if (typeof id === "string" && id !== "") {
      const checked = node.properties?.checked
      found.push({ id, checked: checked === true || checked === "" || checked === "checked" })
    }
  }
  for (const child of node.children ?? []) {
    stampedBoxes(child, found)
  }
}

// The items one page counts (myProgress.sections): a section opens at a
// heading that is a CHILD OF THE PAGE ITSELF (not one inside a callout, a
// list or a quote) whose words are one of `headings` (normalised), and runs
// to the next such heading of the same or a higher level. Every box inside
// it that PlantoirTasks stamped counts, at any depth - a quiz's boxes carry
// no stamp, so they never count. The same words twice are one id and count
// once, from the first. A box's `checked` is the Markdown's own state ([x]).
export function countedItems(root: Node, headings: string[]): CountedItem[] {
  const wanted = new Set<string>()
  for (const heading of headings) {
    wanted.add(normalisedHeading(heading))
  }
  const items: CountedItem[] = []
  const seen = new Set<string>()
  let openLevel = 0
  for (const child of root.children ?? []) {
    const match = child.type === "element" ? HEADING.exec(child.tagName ?? "") : null
    if (match !== null) {
      const level = Number(match[1])
      if (openLevel !== 0 && level <= openLevel) {
        openLevel = 0
      }
      if (openLevel === 0 && wanted.has(normalisedHeading(textOf(child)))) {
        openLevel = level
      }
      continue
    }
    if (openLevel === 0) {
      continue
    }
    const found: CountedItem[] = []
    stampedBoxes(child, found)
    for (const item of found) {
      if (!seen.has(item.id)) {
        seen.add(item.id)
        items.push(item)
      }
    }
  }
  return items
}

// ---- The manifest ---------------------------------------------------------------

// What the build's Python worked out before Quartz ran (quartz/
// plantoir_progress.json, scripts/my_progress.py): which classes there are, in
// the order the build dates pages from them, and which class first linked
// each page directly.
export type PlanClass = { path: string; title: string; date: string; unit: string; unitOrder: number }
export type Plan = {
  version: number
  page: boolean
  reason: string
  slug: string
  headings: string[]
  words: Record<string, string>
  notes: Record<string, string>
  classes: PlanClass[]
  firstClassOf: Record<string, string>
  gate: string[]
}

export type CountedPage = { path: string; slug: string; title: string; items: CountedItem[] }
export type ManifestPage = { title: string; slug: string; items: CountedItem[] }
export type ManifestClass = { label: string; date: string; pages: ManifestPage[] }
export type ManifestUnit = { label: string; classes: ManifestClass[] }
export type Manifest = {
  version: number
  words: Record<string, string>
  units: ManifestUnit[]
  other: { label: string; pages: ManifestPage[] }
}

function byTitle(a: ManifestPage, b: ManifestPage): number {
  const order = a.title.localeCompare(b.title, "en", { numeric: true, sensitivity: "base" })
  if (order !== 0) {
    return order
  }
  return a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0
}

// The manifest the page reads (myProgress.manifest): every page with at least
// one counted item, under the class that first linked it directly, the
// classes in the plan's order inside their unit, the units by number; a
// class page's own items under itself; everything else under Other pages,
// last, by title. A class with no counted page is left out, and so is a unit
// with no class left.
export function buildManifest(plan: Plan, pages: CountedPage[]): Manifest {
  const classIndex = new Map<string, number>()
  for (let index = 0; index < plan.classes.length; index += 1) {
    classIndex.set(plan.classes[index].path, index)
  }
  const ownPages: ManifestPage[][] = []
  const linkedPages: ManifestPage[][] = []
  for (let index = 0; index < plan.classes.length; index += 1) {
    ownPages.push([])
    linkedPages.push([])
  }
  const other: ManifestPage[] = []
  for (const page of pages) {
    if (page.items.length === 0) {
      continue
    }
    const row: ManifestPage = { title: page.title, slug: page.slug, items: page.items }
    const own = classIndex.get(page.path)
    if (own !== undefined) {
      ownPages[own].push(row)
      continue
    }
    const claimer = plan.firstClassOf[page.path]
    const claimed = claimer === undefined ? undefined : classIndex.get(claimer)
    if (claimed !== undefined) {
      linkedPages[claimed].push(row)
    } else {
      other.push(row)
    }
  }
  const units: ManifestUnit[] = []
  const unitOrder: { label: string; order: number; first: number }[] = []
  const unitsByLabel = new Map<string, ManifestUnit>()
  for (let index = 0; index < plan.classes.length; index += 1) {
    const rows = ownPages[index].sort(byTitle).concat(linkedPages[index].sort(byTitle))
    if (rows.length === 0) {
      continue
    }
    const known = plan.classes[index]
    let unit = unitsByLabel.get(known.unit)
    if (unit === undefined) {
      unit = { label: known.unit, classes: [] }
      unitsByLabel.set(known.unit, unit)
      unitOrder.push({ label: known.unit, order: known.unitOrder, first: index })
    }
    unit.classes.push({ label: known.title, date: known.date, pages: rows })
  }
  unitOrder.sort((a, b) => (a.order !== b.order ? a.order - b.order : a.first - b.first))
  for (const entry of unitOrder) {
    units.push(unitsByLabel.get(entry.label) as ManifestUnit)
  }
  return { version: 1, words: plan.words, units, other: { label: plan.words.otherPages ?? "", pages: other.sort(byTitle) } }
}

// ---- A student's ticks, added up ---------------------------------------------

// One page's done and total (myProgress.rollUp): an item is done when the
// student ticked it, or never touched it and the teacher wrote it ticked
// ([x], ruling Q5); unticked by the student, it is not. Only the manifest's
// own ids are read, so a tick under words that no longer exist is never
// counted. A store that throws reads as nothing touched (readTicks).
export function rollUp(
  siteRoot: string,
  page: ManifestPage,
  store: TickStore,
): { done: number; total: number; touched: number } {
  const ids: string[] = []
  for (const item of page.items) {
    ids.push(item.id)
  }
  const ticks = readTicks(siteRoot, page.slug, ids, store)
  let done = 0
  let touched = 0
  for (const item of page.items) {
    const tick = ticks[item.id]
    if (tick !== null) {
      touched += 1
    }
    if (tick === true || (tick === null && item.checked)) {
      done += 1
    }
  }
  return { done, total: page.items.length, touched }
}

// ---- The sidebar ------------------------------------------------------------------

export type Pin = { slug: string; after: string[] }
type SidebarNode = { isFolder: boolean; slugSegment: string; slug: string }

// The sidebar's top level with My Progress moved to directly after the first
// class folder (myProgress.sidebar) - "All Classes", or a club's own folder -
// or to the top when there is none. Nothing moves when the build made no page
// (an empty slug) or the page is not in the sidebar (hidden).
export function pinnedOrder<T extends SidebarNode>(nodes: T[], pin: Pin): T[] {
  if (pin.slug === "") {
    return nodes
  }
  let pinned = -1
  for (let index = 0; index < nodes.length; index += 1) {
    if (!nodes[index].isFolder && nodes[index].slug === pin.slug) {
      pinned = index
      break
    }
  }
  if (pinned < 0) {
    return nodes
  }
  const rest: T[] = []
  for (let index = 0; index < nodes.length; index += 1) {
    if (index !== pinned) {
      rest.push(nodes[index])
    }
  }
  let place = 0
  for (let index = 0; index < rest.length; index += 1) {
    if (rest[index].isFolder && pin.after.includes(rest[index].slugSegment)) {
      place = index + 1
      break
    }
  }
  rest.splice(place, 0, nodes[pinned])
  return rest
}
