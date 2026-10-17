// The `quiz-chemistry` figure (#587): the first question on the demo SCH3U's
// Check Your Stoichiometry page — a balanced equation in chemistry notation
// and two blanks — answered with the moles right and the mass wrong (4.39 g,
// the answer that skips the mole ratio) and checked: one blank marked right
// and one not, and the explanation open, which names that mistake. The body
// of an async function run by webwindow.swift --prepare; `timeoutMs` is its
// bound. Returns "ready" or the reason it is not. The words are the
// contract's (contracts/shared-rules.json → quizCallouts.words.site:
// someBlanksRight with right 1 and count 2).
const ONE_OF_TWO = "1 of 2 blanks are right. Try again, or show the answer."
const ANSWERS = ["0.0998", "4.39"]
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
let quiz = null
while (Date.now() < until) {
  quiz = document.querySelector('.plantoir-quiz[data-quiz-n="1"][data-built]')
  if (quiz) break
  await pause(100)
}
if (!quiz) return "the first quiz on the page was not made ready"
if (quiz.querySelectorAll(".katex").length === 0) return "the equation was not typeset"
if (quiz.querySelectorAll(".katex-error").length > 0) return "the quiz holds mathematics that did not typeset"
const blanks = Array.from(quiz.querySelectorAll("input.plantoir-quiz-blank"))
if (blanks.length !== 2) return "the first quiz has " + blanks.length + " blanks, not 2"
blanks.sort((a, b) => Number(a.dataset.blank ?? 0) - Number(b.dataset.blank ?? 0))
for (let index = 0; index < blanks.length; index += 1) {
  blanks[index].value = ANSWERS[index]
  blanks[index].dispatchEvent(new Event("input", { bubbles: true }))
}
quiz.querySelector(".plantoir-quiz-check").click()
const feedback = () => quiz.querySelector(".plantoir-quiz-feedback")?.textContent ?? ""
while (Date.now() < until && feedback() !== ONE_OF_TWO) await pause(100)
if (feedback() !== ONE_OF_TWO) return "the feedback reads \"" + feedback() + "\", not \"" + ONE_OF_TWO + "\""
const explain = quiz.querySelector(".plantoir-quiz-explain")
if (!explain || explain.hidden) return "the explanation is not shown"
document.activeElement && document.activeElement.blur && document.activeElement.blur()
// Framing as quiz-math.js.
const overhang = quiz.getBoundingClientRect().bottom - (window.innerHeight - 56)
if (overhang > 0) window.scrollBy(0, overhang)
if (quiz.getBoundingClientRect().top < 40) return "the quiz is " + Math.round(quiz.getBoundingClientRect().height) + " pt tall and does not fit in the window"
return "ready"
