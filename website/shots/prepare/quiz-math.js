// The `quiz-math` figure (#587): the first question on the demo MCV4U's
// Check Your Curve Sketching page — a root estimated from the graph inside
// the question — answered 0.35 and checked: right, within the tolerance the
// teacher wrote, with the explanation open. The body of an async function
// run by webwindow.swift --prepare; `timeoutMs` is its bound. Returns "ready"
// or the reason it is not. The words are the contract's
// (contracts/shared-rules.json → quizCallouts.words.site: right).
const RIGHT = "Right!"
const ESTIMATE = "0.35"
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
let quiz = null
while (Date.now() < until) {
  quiz = document.querySelector('.plantoir-quiz[data-quiz-n="1"][data-built]')
  if (quiz && quiz.querySelector("figure.pl-functionplot[data-drawn-width] svg")) break
  await pause(100)
}
if (!quiz) return "the first quiz on the page was not made ready"
if (!quiz.querySelector("figure.pl-functionplot[data-drawn-width] svg")) return "the graph in the question was not drawn"
if (quiz.querySelectorAll(".katex").length === 0) return "the question's mathematics was not typeset"
const blank = quiz.querySelector("input.plantoir-quiz-blank")
if (!blank) return "the first quiz has no blank"
blank.value = ESTIMATE
blank.dispatchEvent(new Event("input", { bubbles: true }))
quiz.querySelector(".plantoir-quiz-check").click()
const feedback = () => quiz.querySelector(".plantoir-quiz-feedback")?.textContent ?? ""
while (Date.now() < until && feedback() !== RIGHT) await pause(100)
if (feedback() !== RIGHT) return "the feedback reads \"" + feedback() + "\", not \"" + RIGHT + "\""
const explain = quiz.querySelector(".plantoir-quiz-explain")
if (!explain || explain.hidden) return "the explanation is not shown"
document.activeElement && document.activeElement.blur && document.activeElement.blur()
// Framing (as code-quiz.js): the quiz's bottom brought a little above the
// window's edge if it would be cut off — and refused if that pushes the
// question's top under the title bar, so a cut-off figure fails here.
const overhang = quiz.getBoundingClientRect().bottom - (window.innerHeight - 56)
if (overhang > 0) window.scrollBy(0, overhang)
if (quiz.getBoundingClientRect().top < 40) return "the quiz is " + Math.round(quiz.getBoundingClientRect().height) + " pt tall and does not fit in the window"
return "ready"
