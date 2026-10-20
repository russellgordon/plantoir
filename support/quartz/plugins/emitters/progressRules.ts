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
// way the page's own script reads them from the page (#519 review F1). The
// one call to taskItemId below only CHECKS that a line is the stamp's own
// before its maths is read (#603).
//
// scripts/check_progress_rules_against_the_site.py bundles this very file and
// runs every case in the contract through it in Node.

import { readTicks, taskItemId, taskItemText, TickStore } from "../transformers/taskRules"

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

// One counted item, as the manifest carries it (myProgress.manifest): its id
// and the Markdown's own state ([x]) from the box's stamp; `text`, the words
// a student reads beside the box - the <label> PlantoirTasks wrapped around
// the box and its words - so My Progress can list a page's items in place
// with no fetch (#603); `anchor`, the id the built page gives the
// success-criteria heading the item sits under ("" when it has none), so the
// list links to that part of the page.
//
// `group` (#603, Russell): the words of the nearest SUB-heading inside the
// section above the item ("Knowledge and Understanding" under "Success
// criteria"), so the listed items do not run together; left out when the
// item comes before any sub-heading.
export type CountedItem = { id: string; checked: boolean; text: string; anchor: string; group?: string }

function classesOf(node: Node): string[] {
  const value = node.properties?.className
  if (Array.isArray(value)) {
    const names: string[] = []
    for (const name of value) {
      names.push(String(name))
    }
    return names
  }
  return typeof value === "string" ? value.split(/\s+/) : []
}

// Every text inside a node, hidden or not.
function allText(node: Node): string {
  if (node.type === "text") {
    return node.value ?? ""
  }
  let text = ""
  for (const child of node.children ?? []) {
    text += allText(child)
  }
  return text
}

// The words a student reads, from the built tree: every text, but nothing
// marked aria-hidden. Maths is the exception: the site draws it as HTML
// alone (Quartz's KaTeX, output "html"), every glyph aria-hidden and in
// drawing order - x² reads "x2", a fraction its denominator first - with no
// copy of the TeX. So each maths element is listed as the TeX the teacher
// wrote between its $ signs, in order, from the item's own line (`maths`);
// only when that cannot be matched one for one, as its drawn glyphs.
function shownText(node: Node, maths: string[] | null): string {
  if (node.type === "text") {
    return node.value ?? ""
  }
  if (node.type !== "element") {
    return ""
  }
  if (classesOf(node).includes("katex")) {
    if (maths !== null && maths.length > 0) {
      return maths.shift() as string
    }
    return allText(node)
  }
  const hidden = node.properties?.ariaHidden
  if (hidden === true || hidden === "true") {
    return ""
  }
  // A footnote's mark (GitHub's `<a data-footnote-ref>`, inside a <sup>) is
  // a number to click, not a word of the item: "a source[^1]" lists as "a
  // source", not "a source1".
  if (node.properties?.dataFootnoteRef !== undefined) {
    return ""
  }
  let text = ""
  for (const child of node.children ?? []) {
    text += shownText(child, maths)
  }
  return text
}

function countMaths(node: Node): number {
  if (node.type === "element" && classesOf(node).includes("katex")) {
    return 1
  }
  let found = 0
  for (const child of node.children ?? []) {
    found += countMaths(child)
  }
  return found
}

// The TeX of each `$...$` (or `$$...$$`) on a line, in order; a `\$` is a
// dollar sign, not maths, and nothing inside a code span is maths (`echo
// $HOME` is code - #603 review 1), so code spans are taken out first.
const INLINE_MATHS = /(?<!\\)\$\$?((?:\\.|[^$\\])+?)\$\$?/g
const CODE_SPAN = /(`+)[\s\S]*?\1/g

function mathsOnLine(line: string): string[] {
  const found: string[] = []
  for (const match of line.replace(CODE_SPAN, " ").matchAll(INLINE_MATHS)) {
    found.push(match[1].trim())
  }
  return found
}

// An item's words as listed: white space made single spaces, trimmed, NFC.
// `line` is the item's first line as the site parsed it (the very line its
// id was made from, taskBoxes.itemText) - read ONLY for the TeX of its
// maths, and only when the line really is the stamp's (its id matches) and
// it holds exactly as much maths as the label draws.
function itemWords(label: Node, line: string | null, id: string): string {
  let maths: string[] | null = null
  const drawn = countMaths(label)
  if (drawn > 0 && line !== null && taskItemId(taskItemText(line)) === id) {
    const written = mathsOnLine(line)
    if (written.length === drawn) {
      maths = written
    }
  }
  return shownText(label, maths).replace(/\s+/gu, " ").trim().normalize("NFC")
}

function boxIn(node: Node): Node | null {
  if (node.type === "element" && node.tagName === "input" && typeof node.properties?.dataTaskItem === "string") {
    return node
  }
  for (const child of node.children ?? []) {
    const found = boxIn(child)
    if (found !== null) {
      return found
    }
  }
  return null
}

type Position = { start?: { line?: number } }

// Every stamped box inside one block, in page order, with the words of the
// <label> it sits in.
function stampedBoxes(node: Node, words: string, anchor: string, lines: string[], line: string | null, found: CountedItem[]) {
  let inside = words
  let itemLine = line
  if (node.type === "element" && node.tagName === "li") {
    const start = (node as Node & { position?: Position }).position?.start?.line
    itemLine = typeof start === "number" && start >= 1 && start <= lines.length ? lines[start - 1] : null
  }
  if (node.type === "element" && node.tagName === "label" && classesOf(node).includes("plantoir-task-label")) {
    const box = boxIn(node)
    inside = itemWords(node, itemLine, box === null ? "" : String(box.properties?.dataTaskItem))
  }
  if (node.type === "element" && node.tagName === "input") {
    const id = node.properties?.dataTaskItem
    if (typeof id === "string" && id !== "") {
      const checked = node.properties?.checked
      found.push({ id, checked: checked === true || checked === "" || checked === "checked", text: inside, anchor })
    }
  }
  for (const child of node.children ?? []) {
    stampedBoxes(child, inside, anchor, lines, itemLine, found)
  }
}

// The items one page counts (myProgress.sections): a section opens at a
// heading that is a CHILD OF THE PAGE ITSELF (not one inside a callout, a
// list or a quote) whose words are one of `headings` (normalised), and runs
// to the next such heading of the same or a higher level. Every box inside
// it that PlantoirTasks stamped counts, at any depth - a quiz's boxes carry
// no stamp, so they never count. The same words twice are one id and count
// once, from the first. A box's `checked` is the Markdown's own state ([x]).
//
// `lines` is the page's text as the site parsed it (file.value), read only
// for the TeX of an item's maths (itemWords); without it maths is listed as
// drawn.
export function countedItems(root: Node, headings: string[], lines: string[] = []): CountedItem[] {
  const wanted = new Set<string>()
  for (const heading of headings) {
    wanted.add(normalisedHeading(heading))
  }
  const items: CountedItem[] = []
  const seen = new Set<string>()
  let openLevel = 0
  let anchor = ""
  let group = ""
  for (const child of root.children ?? []) {
    const match = child.type === "element" ? HEADING.exec(child.tagName ?? "") : null
    if (match !== null) {
      const level = Number(match[1])
      if (openLevel !== 0 && level <= openLevel) {
        openLevel = 0
      }
      if (openLevel === 0 && wanted.has(normalisedHeading(textOf(child)))) {
        openLevel = level
        const id = child.properties?.id
        anchor = typeof id === "string" ? id : ""
        group = ""
      } else if (openLevel !== 0) {
        // A deeper heading inside the section: the group its items sit in.
        group = textOf(child).replace(/\s+/gu, " ").trim().normalize("NFC")
      }
      continue
    }
    if (openLevel === 0) {
      continue
    }
    const found: CountedItem[] = []
    stampedBoxes(child, "", anchor, lines, null, found)
    for (const item of found) {
      if (!seen.has(item.id)) {
        seen.add(item.id)
        if (group !== "") {
          item.group = group
        }
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
// `ticked` is each item's own answer, in the manifest's order - what the
// page's expanded row shows (#603), from the same reading as the count, so
// the two can never disagree.
export function rollUp(
  siteRoot: string,
  page: ManifestPage,
  store: TickStore,
): { done: number; total: number; touched: number; ticked: boolean[] } {
  const ids: string[] = []
  for (const item of page.items) {
    ids.push(item.id)
  }
  const ticks = readTicks(siteRoot, page.slug, ids, store)
  let done = 0
  let touched = 0
  const ticked: boolean[] = []
  for (const item of page.items) {
    const tick = ticks[item.id]
    if (tick !== null) {
      touched += 1
    }
    const isDone = tick === true || (tick === null && item.checked)
    if (isDone) {
      done += 1
    }
    ticked.push(isDone)
  }
  return { done, total: page.items.length, touched, ticked }
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
