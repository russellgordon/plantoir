// Self-check quizzes (#563): the page's half, in the student's browser.
//
// The transformer (plugins/transformers/plantoirQuizzes.ts) left each quiz as
// Quartz's callout with real radio buttons, checkboxes or text boxes, its
// answer and explanation hidden. This adds Check and Show answer, the
// feedback, the shuffle, keyboard folding, and - after the page's last quiz -
// the score for this page in this browser. It does nothing on a page with no
// quiz (no listener, no request), and nothing here ever asks the network for
// anything: the answers are in the page, and this is a self-check.
//
// The rules (accepts, shuffledOrder) are quizRules.ts's, the same file the
// transformer decided what each quiz is with. The words are
// contracts/shared-rules.json -> quizCallouts.words.site, which the build
// writes into quartz/plantoir_quiz.json on every build and esbuild bundles in
// here.

import settings from "../../plantoir_quiz.json"
import { FullSlug, getFullSlug, pathToRoot } from "../../util/path"
import { accepts, filledWords, parseAnswerLine, shuffledOrder } from "../../plugins/transformers/quizRules"

const WORDS = ((settings as { words?: Record<string, string> }).words ?? {}) as Record<string, string>

function word(key: string, values: Record<string, string | number> = {}): string {
  return filledWords(WORDS[key] ?? "", values)
}

type Saved = { v: 1; quizzes: Record<string, { hash: string; firstTry: boolean }> }

function storageGet(key: string): string | null {
  try {
    return window.localStorage.getItem(key)
  } catch {
    return null
  }
}

function storageSet(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value)
  } catch {
    // A browser that refuses storage simply forgets.
  }
}

function storageRemove(key: string) {
  try {
    window.localStorage.removeItem(key)
  } catch {
    // As above.
  }
}

function readSaved(key: string): Saved {
  const text = storageGet(key)
  if (text !== null) {
    try {
      const parsed = JSON.parse(text) as Saved
      if (parsed && parsed.v === 1 && typeof parsed.quizzes === "object" && parsed.quizzes !== null) {
        return parsed
      }
    } catch {
      // A damaged entry is the same as none.
    }
  }
  return { v: 1, quizzes: {} }
}

function made<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text = ""): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag)
  element.className = className
  if (text !== "") {
    element.textContent = text
  }
  return element
}

// Growing content inside an open callout: Quartz fixed the callout's height
// when it was drawn or opened (callout.inline.ts), which would clip feedback,
// a revealed answer or an explanation measured while hidden (#563 plan M9).
function freeOpenCallouts(from: HTMLElement) {
  let current: HTMLElement | null = from
  while (current !== null) {
    if (current.classList.contains("callout") && !current.classList.contains("is-collapsed")) {
      current.style.maxHeight = ""
    }
    current = current.parentElement
  }
}

// Folding by keyboard (review S6): Quartz's fold titles listen for clicks
// only, and a folded callout's content stays focusable. Inside a quiz, a
// fold title is a button, and folded content is inert until opened.
function syncFold(callout: HTMLElement) {
  const title = callout.querySelector(":scope > .callout-title") as HTMLElement | null
  const content = callout.querySelector(":scope > .callout-content") as HTMLElement | null
  const collapsed = callout.classList.contains("is-collapsed")
  if (title !== null && callout.classList.contains("is-collapsible")) {
    title.setAttribute("role", "button")
    title.setAttribute("tabindex", "0")
    title.setAttribute("aria-expanded", collapsed ? "false" : "true")
  }
  if (content !== null) {
    content.inert = collapsed
  }
}

let instances = 0

type Quiz = {
  root: HTMLElement
  id: string
  hash: string
  kind: string
  answered: () => boolean
  reset: () => void
  restoreOrder: () => void
  reapplyOrder: () => void
}

function setUp(root: HTMLElement, record: (quiz: Quiz, right: boolean) => void, cleanups: Array<() => void>): Quiz | null {
  root.dataset.built = "true"
  const kind = root.dataset.quizKind ?? ""
  // Every collapsible callout in the quiz, the quiz's own fold included.
  const folds: HTMLElement[] = []
  if (root.classList.contains("is-collapsible")) {
    folds.push(root)
  }
  for (const inner of root.querySelectorAll<HTMLElement>(".callout.is-collapsible")) {
    folds.push(inner)
  }
  for (const fold of folds) {
    syncFold(fold)
  }
  if (kind === "notReady" || kind === "") {
    return null
  }
  instances += 1
  const instance = instances
  const content = root.querySelector(":scope > .callout-content") as HTMLElement | null
  if (content === null) {
    return null
  }
  let data: { correct?: number[]; answers?: string[] } = {}
  try {
    data = JSON.parse(root.dataset.quiz ?? "{}")
  } catch {
    data = {}
  }

  // Ids of this instance's own: a quiz shown twice (a transclusion) must not
  // share its label with the other copy (review S5).
  const title = root.querySelector(":scope > .callout-title .callout-title-inner") as HTMLElement | null
  if (title !== null && title.id !== "") {
    const others = document.querySelectorAll(`[id="${CSS.escape(title.id)}"]`)
    if (others.length > 1) {
      const renamed = `${title.id}-${instance}`
      for (const labelled of root.querySelectorAll(`[aria-labelledby="${CSS.escape(title.id)}"]`)) {
        labelled.setAttribute("aria-labelledby", renamed)
      }
      title.id = renamed
    }
  }
  const hint = root.querySelector(".plantoir-quiz-hint") as HTMLElement | null
  if (hint !== null && hint.id !== "" && document.querySelectorAll(`[id="${CSS.escape(hint.id)}"]`).length > 1) {
    const renamed = `${hint.id}-${instance}`
    root.querySelector(".plantoir-quiz-choices")?.setAttribute("aria-describedby", renamed)
    hint.id = renamed
  }

  const fieldset = root.querySelector(".plantoir-quiz-choices") as HTMLFieldSetElement | null
  const choices = fieldset ? Array.from(fieldset.querySelectorAll<HTMLElement>(":scope > .plantoir-quiz-choice")) : []
  const inputs: HTMLInputElement[] = []
  for (const choice of choices) {
    const input = choice.querySelector("input.plantoir-quiz-input") as HTMLInputElement | null
    if (input !== null) {
      input.name = `plantoir-quiz-${instance}`
      inputs.push(input)
    }
  }
  const blanks = Array.from(root.querySelectorAll<HTMLInputElement>("input.plantoir-quiz-blank"))
  blanks.sort((a, b) => Number(a.dataset.blank ?? 0) - Number(b.dataset.blank ?? 0))
  // A blank in a folding quiz's title: a click into it is typing, not
  // folding (Quartz's listener sits on the title).
  const keepClickInBox = (event: Event) => event.stopPropagation()
  for (const blank of blanks) {
    if (blank.closest(".callout-title") !== null) {
      blank.addEventListener("click", keepClickInBox)
      cleanups.push(() => blank.removeEventListener("click", keepClickInBox))
    }
  }

  // The shuffle: by moving the choices, so reading and Tab order follow
  // what is seen. Markdown order comes back for printing.
  const markdownOrder = choices.slice()
  let shuffled = choices.slice()
  if (root.dataset.quizShuffle === "true" && fieldset !== null && choices.length > 1) {
    const order = shuffledOrder(choices.length, Math.random)
    shuffled = []
    for (const place of order) {
      shuffled.push(choices[place])
    }
    for (const choice of shuffled) {
      fieldset.appendChild(choice)
    }
  }
  const placeInOrder = (order: HTMLElement[]) => {
    if (fieldset === null || root.dataset.quizShuffle !== "true") {
      return
    }
    for (const choice of order) {
      fieldset.appendChild(choice)
    }
  }

  // Check, Show answer, and what they say.
  const actions = made("div", "plantoir-quiz-actions")
  const check = made("button", "plantoir-quiz-check", word("check"))
  check.type = "button"
  const show = made("button", "plantoir-quiz-show", word("showAnswer"))
  show.type = "button"
  actions.append(check, show)
  const feedback = made("p", "plantoir-quiz-feedback")
  feedback.setAttribute("role", "status")
  feedback.setAttribute("aria-live", "polite")
  const answer = root.querySelector(".plantoir-quiz-answer") as HTMLElement | null
  const explains = Array.from(root.querySelectorAll<HTMLElement>(".plantoir-quiz-explain"))
  const before = answer ?? explains[0] ?? null
  if (before !== null && before.parentElement === content) {
    content.insertBefore(actions, before)
  } else {
    content.appendChild(actions)
  }
  actions.after(feedback)

  let firstDone = false
  let rightNow = false

  const relayout = () => freeOpenCallouts(root)

  const revealExplanations = () => {
    for (const wrapper of explains) {
      wrapper.hidden = false
      // Opened as it is shown: the explanation is the point of answering.
      for (const callout of wrapper.querySelectorAll<HTMLElement>(".callout")) {
        callout.classList.remove("is-collapsed")
        callout.style.maxHeight = ""
        syncFold(callout)
      }
    }
    relayout()
  }

  const say = (text: string) => {
    feedback.textContent = text
    relayout()
  }

  const clearMarks = () => {
    for (const mark of root.querySelectorAll(".plantoir-quiz-mark")) {
      mark.remove()
    }
    for (const blank of blanks) {
      blank.removeAttribute("aria-invalid")
    }
  }

  const onCheck = () => {
    let right = false
    if (kind === "single" || kind === "multiple") {
      const picked: number[] = []
      for (const choice of choices) {
        const input = choice.querySelector("input.plantoir-quiz-input") as HTMLInputElement | null
        if (input?.checked) {
          picked.push(Number(choice.dataset.choice ?? -1))
        }
      }
      if (picked.length === 0) {
        say(word("chooseFirst"))
        return
      }
      const correct = data.correct ?? []
      right = picked.length === correct.length && picked.every((place) => correct.includes(place))
      say(right ? word("right") : word("notRight"))
    } else {
      const lines = data.answers ?? []
      const boxes = kind === "short" ? blanks.slice(0, 1) : blanks
      for (const box of boxes) {
        if (box.value.trim() === "") {
          say(word("typeFirst"))
          box.focus()
          return
        }
      }
      clearMarks()
      let rightCount = 0
      boxes.forEach((box, index) => {
        const parsed = parseAnswerLine(lines[index] ?? "")
        const ok = "alternatives" in parsed && accepts(parsed.alternatives, box.value)
        if (ok) {
          rightCount += 1
        }
        if (kind === "fill") {
          box.setAttribute("aria-invalid", ok ? "false" : "true")
          const mark = made("span", "plantoir-quiz-mark " + (ok ? "is-right" : "is-wrong"), ok ? word("markRight") : word("markWrong"))
          box.after(mark)
        } else {
          box.setAttribute("aria-invalid", ok ? "false" : "true")
        }
      })
      right = rightCount === boxes.length
      if (right) {
        say(word("right"))
      } else if (kind === "fill") {
        say(word("someBlanksRight", { right: rightCount, count: boxes.length }))
      } else {
        say(word("notRight"))
      }
    }
    rightNow = right
    root.classList.toggle("is-right", right)
    if (!firstDone) {
      firstDone = true
      record(quiz, right)
    }
    revealExplanations()
  }

  const onShow = () => {
    if (kind === "single" || kind === "multiple") {
      const correct = data.correct ?? []
      for (const choice of choices) {
        if (correct.includes(Number(choice.dataset.choice ?? -1)) && !choice.querySelector(".plantoir-quiz-badge")) {
          const label = choice.querySelector(".plantoir-quiz-choice-label")
          label?.appendChild(made("span", "plantoir-quiz-badge", word("correctChoice")))
        }
      }
    } else if (answer !== null) {
      answer.hidden = false
    }
    say(word("answerShown"))
    if (!firstDone) {
      firstDone = true
      record(quiz, rightNow)
    }
    revealExplanations()
  }

  const onClick = (event: Event) => {
    const target = event.target as HTMLElement | null
    if (target === null) {
      return
    }
    if (target.closest(".plantoir-quiz-check") === check) {
      onCheck()
      return
    }
    if (target.closest(".plantoir-quiz-show") === show) {
      onShow()
      return
    }
    // Quartz's own listener on the title has just folded or unfolded it.
    const title = target.closest(".callout-title")
    if (title !== null && root.contains(title)) {
      const callout = title.parentElement as HTMLElement
      syncFold(callout)
    }
  }
  const onKey = (event: KeyboardEvent) => {
    const target = event.target as HTMLElement | null
    if (target === null) {
      return
    }
    if (event.key === "Enter" && target instanceof HTMLInputElement && target.classList.contains("plantoir-quiz-blank")) {
      event.preventDefault()
      onCheck()
      return
    }
    if ((event.key === "Enter" || event.key === " ") && target.classList.contains("callout-title") && target.getAttribute("role") === "button") {
      event.preventDefault()
      target.click()
    }
  }
  const onInput = (event: Event) => {
    const target = event.target as HTMLElement | null
    if (target instanceof HTMLInputElement && target.classList.contains("plantoir-quiz-blank")) {
      target.removeAttribute("aria-invalid")
      const mark = target.nextElementSibling
      if (mark !== null && mark.classList.contains("plantoir-quiz-mark")) {
        mark.remove()
      }
    }
  }
  root.addEventListener("click", onClick)
  root.addEventListener("keydown", onKey)
  root.addEventListener("input", onInput)
  cleanups.push(() => {
    root.removeEventListener("click", onClick)
    root.removeEventListener("keydown", onKey)
    root.removeEventListener("input", onInput)
  })

  const quiz: Quiz = {
    root,
    id: `${root.dataset.quizSource ?? ""}#${root.dataset.quizN ?? ""}`,
    hash: root.dataset.quizHash ?? "",
    kind,
    answered: () => firstDone,
    reset: () => {
      firstDone = false
      rightNow = false
      root.classList.remove("is-right")
      for (const input of inputs) {
        input.checked = false
      }
      for (const blank of blanks) {
        blank.value = ""
      }
      clearMarks()
      for (const badge of root.querySelectorAll(".plantoir-quiz-badge")) {
        badge.remove()
      }
      if (answer !== null) {
        answer.hidden = true
      }
      for (const wrapper of explains) {
        wrapper.hidden = true
      }
      feedback.textContent = ""
      relayout()
    },
    restoreOrder: () => placeInOrder(markdownOrder),
    reapplyOrder: () => placeInOrder(shuffled),
  }
  return quiz
}

document.addEventListener("nav", () => {
  const roots = Array.from(document.querySelectorAll<HTMLElement>(".plantoir-quiz:not([data-built])"))
  if (roots.length === 0) {
    return
  }
  const slug = getFullSlug(window)
  const base = new URL(pathToRoot(slug as FullSlug) + "/", location.href).pathname
  const key = `plantoir:quiz:${base}:${slug}`
  const saved = readSaved(key)
  const cleanups: Array<() => void> = []
  const quizzes: Quiz[] = []
  let scoreBox: HTMLElement | null = null
  let scoreLine: HTMLElement | null = null

  const updateScore = () => {
    if (scoreBox === null || scoreLine === null) {
      return
    }
    let right = 0
    let answered = 0
    for (const quiz of quizzes) {
      const entry = saved.quizzes[quiz.id]
      if (entry !== undefined && entry.hash === quiz.hash) {
        answered += 1
        if (entry.firstTry) {
          right += 1
        }
      }
    }
    scoreBox.hidden = answered === 0
    scoreLine.textContent = word("score", { right, total: quizzes.length })
  }

  const record = (quiz: Quiz, right: boolean) => {
    const entry = saved.quizzes[quiz.id]
    if (entry !== undefined && entry.hash === quiz.hash) {
      return
    }
    saved.quizzes[quiz.id] = { hash: quiz.hash, firstTry: right }
    storageSet(key, JSON.stringify(saved))
    updateScore()
  }

  for (const root of roots) {
    const quiz = setUp(root, record, cleanups)
    if (quiz !== null) {
      quizzes.push(quiz)
    }
  }
  if (quizzes.length === 0) {
    return
  }

  // The page's score, after the page's last quiz (or the block holding it).
  const last = quizzes[quizzes.length - 1].root
  const article = last.closest("article")
  let anchor: HTMLElement = last
  while (anchor.parentElement !== null && anchor.parentElement !== article) {
    anchor = anchor.parentElement
  }
  scoreBox = made("div", "plantoir-quiz-score")
  scoreLine = made("p", "plantoir-quiz-score-line")
  scoreLine.setAttribute("role", "status")
  const startAgain = made("button", "plantoir-quiz-start-again", word("startAgain"))
  startAgain.type = "button"
  scoreBox.append(scoreLine, startAgain)
  anchor.after(scoreBox)
  const onStartAgain = () => {
    storageRemove(key)
    saved.quizzes = {}
    for (const quiz of quizzes) {
      quiz.reset()
    }
    updateScore()
    quizzes[0].root.querySelector<HTMLElement>("input, .callout-title[role=button]")?.focus()
  }
  startAgain.addEventListener("click", onStartAgain)
  updateScore()

  // ⌘P prints the choices in Markdown order (the handout makes its own copy
  // and puts them back there itself, print.inline.ts).
  const beforePrint = () => {
    for (const quiz of quizzes) {
      quiz.restoreOrder()
    }
  }
  const afterPrint = () => {
    for (const quiz of quizzes) {
      quiz.reapplyOrder()
    }
  }
  window.addEventListener("beforeprint", beforePrint)
  window.addEventListener("afterprint", afterPrint)

  window.addCleanup(() => {
    for (const cleanup of cleanups) {
      cleanup()
    }
    startAgain.removeEventListener("click", onStartAgain)
    window.removeEventListener("beforeprint", beforePrint)
    window.removeEventListener("afterprint", afterPrint)
  })
})
