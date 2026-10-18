// Task boxes students tick (#519): the RULES, with nothing of Quartz's in
// them - contracts/shared-rules.json -> taskBoxes.
//
// Pure: no DOM, no Node. The site's transformer (plantoirTasks.ts) is the
// ONLY producer of an item's id: it reads the item's first line as Quartz
// parsed it (after every text transform - Obsidian links to a heading are
// rewritten, %%comments%% removed, a callout's title given a line of its
// own; review F1) and stamps the id on the box. The page's own script
// (components/scripts/tasks.inline.ts) never works an id out; it reads the
// stamp, and keeps a tick under taskKey. #545 (My progress) reads ticks
// through readTicks with the ids it finds on the built pages
// (`data-task-item`), so it never re-derives one.
//
// scripts/check_task_rules_against_the_site.py bundles this very file and
// runs every case in the contract through it in Node.

import { fnv1a } from "./codeRunnerRule"

// A task item's first line: any `>` quote markers, the indent, one or more
// list markers, the box and the space after it.
const TASK_LINE = /^(?:[ \t]*>)*[ \t]*(?:(?:[-*+]|[0-9]{1,9}[.)])[ \t]+)+\[[ xX]\](?:[ \t]+|$)/

// ASCII white space only, so the rule reads the same in any language that
// mirrors it: a no-break space, a byte-order mark or U+0085 inside an item
// is a character of its text (review F9).
const SPACE = /[ \t\n\r\f\v]+/g

// The text an item's id is made from: its first line, as Quartz parsed it,
// with the markers and the box taken off, ASCII white space trimmed and each
// run of it made one space, in Unicode's composed form (NFC), so a file
// saved in the decomposed form keeps its ticks. A line that is not a task
// item's (it should not happen) is used whole, trimmed the same way.
export function taskItemText(line: string): string {
  const match = TASK_LINE.exec(line)
  const rest = match === null ? line : line.slice(match[0].length)
  return rest.replace(SPACE, " ").replace(/^ /, "").replace(/ $/, "").normalize("NFC")
}

// An item's id: FNV-1a over the text's UTF-16 code units, eight hex digits
// (the hash runnable code already keys a student's edits with). From the
// text alone, so adding or moving an item never moves another's tick, the
// box's own [ ] or [x] is not part of it, and two items with the same words
// on one page share one tick (ruling Q5).
export function taskItemId(text: string): string {
  return fnv1a(text)
}

// The site's root path - "/" on a site at the root of its host, "/ics3u/"
// under a folder - from the page's slug and its address, as the quizzes and
// the runnable code work it out.
export function siteRootFrom(pageSlug: string, href: string): string {
  const parts = pageSlug.split("/").filter((part) => part !== "")
  const ups: string[] = []
  for (let index = 0; index < parts.length - 1; index += 1) {
    ups.push("..")
  }
  const relative = ups.length === 0 ? "." : ups.join("/")
  return new URL(relative + "/", href).pathname
}

// Where one tick is kept: per site, per page the item was WRITTEN on (a
// transcluded copy shares its source's tick), per item.
export function taskKey(siteRoot: string, pageSlug: string, itemId: string): string {
  return `plantoir:task:${siteRoot}:${pageSlug}:${itemId}`
}

export const TICKED = "1"
export const UNTICKED = "0"

export type TickStore = { getItem(key: string): string | null }

// The ticks a student has made on one page's items: true (ticked), false
// (unticked - a teacher's [x] the student took off), or null (never
// touched: the Markdown's own state applies). A store that throws, or a
// value that is neither "1" nor "0", reads as null.
export function readTicks(
  siteRoot: string,
  pageSlug: string,
  itemIds: string[],
  store: TickStore,
): Record<string, boolean | null> {
  const ticks: Record<string, boolean | null> = {}
  for (const itemId of itemIds) {
    let value: string | null = null
    try {
      value = store.getItem(taskKey(siteRoot, pageSlug, itemId))
    } catch {
      value = null
    }
    ticks[itemId] = value === TICKED ? true : value === UNTICKED ? false : null
  }
  return ticks
}
