// Task boxes students tick (#519): the site's half that runs when the site is
// BUILT. contracts/shared-rules.json -> taskBoxes.
//
// Quartz draws a Markdown task item (`- [ ] Bring a pencil`) as a disabled
// checkbox. On every page, every such box that is NOT inside a self-check
// quiz (whose not-ready choices stay disabled - taskBoxes.which) becomes one
// a student can tick:
//
// * `disabled` comes off; the box keeps the Markdown's own state as its
//   default (`checked` for [x]);
// * it is stamped with the page it was WRITTEN on (`data-task-page`, the
//   slug, so a transcluded copy shares its source's tick) and the item's id
//   (`data-task-item`, taskRules.taskItemId of the item's first line as
//   Quartz parsed it). This file is the ONLY producer of ids (review F1);
// * the box and the item's words, up to the first thing that is not inline
//   text (a nested list, a paragraph, a table...), are wrapped in a <label>,
//   so a click on the words ticks it and the words are the box's name. A
//   link inside still navigates (the HTML activation rule).
//
// Html stage, wired straight after PlantoirQuizzes: every markdown stage has
// run, so each quiz has already been decided and carries its class. A page
// with no task item outside a quiz is left exactly as it was.
//
// NOT Quartz's own `enableCheckbox` (ofm.ts), measured and rejected (#519
// plan M2): it rewrites EVERY checkbox on a page - the quizzes' own inputs
// among them - and keys a tick by the box's position, so adding one item
// moves every tick below it.

import { Element, ElementContent, Root as HtmlRoot } from "hast"
import { QuartzTransformerPlugin } from "../types"
import { taskItemId, taskItemText } from "./taskRules"

type Parent = HtmlRoot | Element

// Inline (phrasing) content: what may sit inside the label beside the box.
// Anything else - a nested list, a paragraph, a table, a figure, a heading,
// a video - ends the label (review F10).
const PHRASING = new Set([
  "a", "abbr", "b", "bdi", "bdo", "br", "cite", "code", "data", "del", "dfn", "em", "i", "img",
  "ins", "kbd", "mark", "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u",
  "var", "wbr", "math", "svg",
])

function classesOf(node: Element): string[] {
  const value = node.properties?.className
  if (Array.isArray(value)) {
    return value.map((item) => String(item))
  }
  return typeof value === "string" ? value.split(/\s+/).filter((name) => name !== "") : []
}

function isCheckbox(node: ElementContent | undefined): node is Element {
  return node !== undefined && node.type === "element" && node.tagName === "input" && node.properties?.type === "checkbox"
}

// The item's own box: the first child (a tight item) or the first child of
// its first paragraph (a loose one), white space before it allowed.
function boxOf(item: Element): { box: Element; holder: Element } | null {
  let first: ElementContent | undefined
  for (const child of item.children) {
    if (child.type === "text" && child.value.trim() === "") {
      continue
    }
    first = child
    break
  }
  if (isCheckbox(first)) {
    return { box: first, holder: item }
  }
  if (first !== undefined && first.type === "element" && first.tagName === "p") {
    for (const child of first.children) {
      if (child.type === "text" && child.value.trim() === "") {
        continue
      }
      return isCheckbox(child) ? { box: child, holder: first } : null
    }
  }
  return null
}

// The box and the inline content after it, into one <label>; trailing white
// space stays outside, so the nested list after it keeps its own line.
function wrapInLabel(holder: Element, box: Element) {
  const start = holder.children.indexOf(box)
  let end = start + 1
  while (end < holder.children.length) {
    const child = holder.children[end]
    if (child.type === "element" && !PHRASING.has(child.tagName)) {
      break
    }
    end += 1
  }
  while (end > start + 1) {
    const last = holder.children[end - 1]
    if (last.type === "text" && last.value.trim() === "") {
      end -= 1
      continue
    }
    break
  }
  const label: Element = {
    type: "element",
    tagName: "label",
    properties: { className: ["plantoir-task-label"] },
    children: holder.children.slice(start, end),
  }
  holder.children.splice(start, end - start, label)
}

function makeTickable(item: Element, lines: string[], slug: string) {
  const found = boxOf(item)
  const line = item.position?.start?.line
  if (found === null || typeof line !== "number" || line < 1 || line > lines.length) {
    // No box, or no place in the page's text to read its words from: left
    // exactly as Quartz drew it (disabled).
    return
  }
  const { box, holder } = found
  const properties = box.properties ?? {}
  delete properties.disabled
  properties.className = ["plantoir-task"]
  properties.dataTaskPage = slug
  properties.dataTaskItem = taskItemId(taskItemText(lines[line - 1]))
  box.properties = properties
  wrapInLabel(holder, box)
}

function walk(node: Parent, insideQuiz: boolean, lines: string[], slug: string) {
  for (const child of node.children) {
    if (child.type !== "element") {
      continue
    }
    const classes = classesOf(child)
    const quiz = insideQuiz || classes.includes("plantoir-quiz")
    if (!quiz && child.tagName === "li" && classes.includes("task-list-item")) {
      makeTickable(child, lines, slug)
    }
    walk(child, quiz, lines, slug)
  }
}

export const PlantoirTasks: QuartzTransformerPlugin = () => ({
  name: "PlantoirTasks",
  htmlPlugins() {
    return [
      () => (tree: HtmlRoot, file) => {
        const value = String(file.value ?? "")
        if (!value.includes("[")) {
          return
        }
        walk(tree, false, value.split("\n"), String(file.data.slug ?? ""))
      },
    ]
  },
})
