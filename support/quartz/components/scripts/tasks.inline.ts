// Task boxes students tick (#519): the page's half, in the student's browser.
// contracts/shared-rules.json -> taskBoxes.
//
// The transformer (plugins/transformers/plantoirTasks.ts) left every task box
// outside a quiz enabled, inside a <label>, stamped with the page it was
// written on and the item's id. This keeps each tick in the student's own
// browser (localStorage, taskRules.taskKey) and puts the boxes back the way
// the student left them on every page shown. Nothing is sent anywhere, and
// nothing is written until a box is changed: no entry means the Markdown's
// own state ([ ] or [x]) applies.
//
// * ONE change listener, on the document, added once when the script first
//   runs - never per page, so changing page never stacks them.
// * On every page shown (Quartz's `nav`, which also fires on the first load
//   and on Back), every box's `checked` is ASSIGNED, from the stored tick or
//   else from the Markdown's own state (defaultChecked). Never left alone:
//   Quartz's router patches the new page into the old one's elements, so a
//   box can be the previous page's, still holding its tick (#519 plan M5).
// * A box in a link's preview or a search result is the page's, not the
//   student's: never saved from (the styles make them unclickable).

import { readTicks, siteRootFrom, taskKey, TICKED, UNTICKED } from "../../plugins/transformers/taskRules"

const BOX = "input.plantoir-task"
const PREVIEW = ".popover, .preview-container"

const store = {
  getItem(key: string): string | null {
    return window.localStorage.getItem(key)
  },
}

function siteRoot(): string {
  return siteRootFrom(document.body.dataset.slug ?? "", location.href)
}

function boxesOnThePage(): HTMLInputElement[] {
  const found: HTMLInputElement[] = []
  for (const box of document.querySelectorAll<HTMLInputElement>(BOX)) {
    if (box.closest(PREVIEW) === null) {
      found.push(box)
    }
  }
  return found
}

document.addEventListener("change", (event) => {
  const box = event.target
  if (!(box instanceof HTMLInputElement) || !box.matches(BOX) || box.closest(PREVIEW) !== null) {
    return
  }
  const page = box.dataset.taskPage ?? ""
  const item = box.dataset.taskItem ?? ""
  try {
    window.localStorage.setItem(taskKey(siteRoot(), page, item), box.checked ? TICKED : UNTICKED)
  } catch {
    // A browser that refuses storage: the box still ticks, and forgets.
  }
  // The same item shown twice (a page transcluded twice) stays in step.
  for (const other of boxesOnThePage()) {
    if (other !== box && other.dataset.taskPage === page && other.dataset.taskItem === item) {
      other.checked = box.checked
    }
  }
})

document.addEventListener("nav", () => {
  const boxes = boxesOnThePage()
  if (boxes.length === 0) {
    return
  }
  const root = siteRoot()
  const itemsByPage: Record<string, string[]> = {}
  for (const box of boxes) {
    const page = box.dataset.taskPage ?? ""
    if (!(page in itemsByPage)) {
      itemsByPage[page] = []
    }
    itemsByPage[page].push(box.dataset.taskItem ?? "")
  }
  const ticksByPage: Record<string, Record<string, boolean | null>> = {}
  for (const page of Object.keys(itemsByPage)) {
    ticksByPage[page] = readTicks(root, page, itemsByPage[page], store)
  }
  for (const box of boxes) {
    const tick = ticksByPage[box.dataset.taskPage ?? ""][box.dataset.taskItem ?? ""]
    box.checked = tick ?? box.defaultChecked
  }
})
