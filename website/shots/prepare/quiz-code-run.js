// The `quiz-code-run` figure (#587): the marketing ICS3U's Check Your Loops
// page with its first four questions answered (the third wrong first, then
// right), and the fifth — a program in its stem that students run — run,
// answered and checked: its output, right, the explanation, and under it the
// page's score with Start again. The body of an async function run by
// webwindow.swift --prepare; `timeoutMs` is its bound. Returns "ready" or
// the reason it is not. The words are the contracts'
// (contracts/shared-rules.json → quizCallouts.words.site: right,
// notRight — the third question is a one-blank fill, which says what a short
// answer says when it is wrong (feedback.blanks, #588) — score with right 4
// and total 5; codeRunnerBlocks.words.finished).
const RIGHT = "Right!"
const NOT_RIGHT = "Not quite. Try again, or show the answer."
const SCORE = "4 of 5 right on the first try"
const FINISHED = "Finished."
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
const quizNumbered = (n) => document.querySelector('.plantoir-quiz[data-quiz-n="' + n + '"][data-built]')
while (Date.now() < until && !quizNumbered(5)) await pause(100)
for (let n = 1; n <= 5; n += 1) {
  if (!quizNumbered(n)) return "quiz " + n + " on the page was not made ready"
}
const feedbackOf = (n) => quizNumbered(n).querySelector(".plantoir-quiz-feedback")?.textContent ?? ""
const choose = (n, places) => {
  for (const choice of quizNumbered(n).querySelectorAll(".plantoir-quiz-choice")) {
    const input = choice.querySelector("input.plantoir-quiz-input")
    if (places.includes(Number(choice.dataset.choice)) !== input.checked) input.click()
  }
}
const type = (n, text) => {
  const box = quizNumbered(n).querySelector("input.plantoir-quiz-blank, input.plantoir-quiz-answer")
  box.value = text
  box.dispatchEvent(new Event("input", { bubbles: true }))
}
const check = async (n, expected) => {
  quizNumbered(n).querySelector(".plantoir-quiz-check").click()
  while (Date.now() < until && feedbackOf(n) !== expected) await pause(50)
  return feedbackOf(n) === expected
}
choose(1, [1])
if (!(await check(1, RIGHT))) return "quiz 1 reads \"" + feedbackOf(1) + "\""
choose(2, [0, 1])
if (!(await check(2, RIGHT))) return "quiz 2 reads \"" + feedbackOf(2) + "\""
type(3, "2")
if (!(await check(3, NOT_RIGHT))) return "quiz 3, answered 2, reads \"" + feedbackOf(3) + "\""
type(3, "-2")
if (!(await check(3, RIGHT))) return "quiz 3, answered -2, reads \"" + feedbackOf(3) + "\""
type(4, "4")
if (!(await check(4, RIGHT))) return "quiz 4 reads \"" + feedbackOf(4) + "\""
const fifth = quizNumbered(5)
const runner = fifth.querySelector(".plantoir-runner")
if (!runner) return "quiz 5 has no runnable block"
if (runner.closest(".plantoir-quiz-choice") || runner.closest(".plantoir-quiz-explain")) return "quiz 5's program is not in its question"
while (Date.now() < until && runner.dataset.built !== "true") await pause(100)
runner.querySelector(".plantoir-runner-run").click()
const status = runner.querySelector(".plantoir-runner-status")
const output = runner.querySelector(".plantoir-runner-output")
while (Date.now() < until && status.textContent !== FINISHED) await pause(100)
if (status.textContent !== FINISHED) return "the status line reads \"" + status.textContent + "\", not \"" + FINISHED + "\""
if (output.textContent !== "2\n5\n8\n") return "the output is " + JSON.stringify(output.textContent)
choose(5, [1])
if (!(await check(5, RIGHT))) return "quiz 5 reads \"" + feedbackOf(5) + "\""
const explain = fifth.querySelector(".plantoir-quiz-explain")
if (!explain || explain.hidden) return "quiz 5's explanation is not shown"
const score = document.querySelector(".plantoir-quiz-score")
while (Date.now() < until && !(score && score.textContent.includes(SCORE))) await pause(100)
if (!score || !score.textContent.includes(SCORE)) return "the score reads \"" + (score ? score.textContent : "") + "\""
document.activeElement && document.activeElement.blur && document.activeElement.blur()
// Framing: the score's bottom a little above the window's edge, and refused
// if that pushes the fifth question's top under the title bar.
window.scrollBy(0, score.getBoundingClientRect().bottom - (window.innerHeight - 56))
if (fifth.getBoundingClientRect().top < 40) return "the fifth quiz and the score are " + Math.round(score.getBoundingClientRect().bottom - fifth.getBoundingClientRect().top) + " pt tall and do not fit in the window"
return "ready"
