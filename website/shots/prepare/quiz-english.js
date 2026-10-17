// The `quiz-english` figure (#587): the sight passage on the demo ENG2D's
// Check Your Reading page, and under it the first question — select all
// that apply — answered with both right choices ticked and checked: right,
// with the explanation open. The body of an async function run by
// webwindow.swift --prepare; `timeoutMs` is its bound. Returns "ready" or
// the reason it is not. The words are the contract's
// (contracts/shared-rules.json → quizCallouts.words.site: right, selectAll).
const RIGHT = "Right!"
const SELECT_ALL = "Select all that apply."
const RIGHT_CHOICES = [0, 1]
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
let quiz = null
while (Date.now() < until) {
  quiz = document.querySelector('.plantoir-quiz[data-quiz-n="1"][data-built]')
  if (quiz) break
  await pause(100)
}
if (!quiz) return "the first quiz on the page was not made ready"
if (!quiz.textContent.includes(SELECT_ALL)) return "the first quiz does not say \"" + SELECT_ALL + "\""
let passage = null
for (const quote of document.querySelectorAll("article blockquote")) {
  if (!quote.classList.contains("callout") && quote.textContent.includes("He counted the tins twice")) {
    passage = quote
    break
  }
}
if (!passage) return "the passage is not on the page"
const choices = Array.from(quiz.querySelectorAll(".plantoir-quiz-choice"))
for (const choice of choices) {
  const input = choice.querySelector("input.plantoir-quiz-input")
  if (RIGHT_CHOICES.includes(Number(choice.dataset.choice)) && !input.checked) input.click()
}
quiz.querySelector(".plantoir-quiz-check").click()
const feedback = () => quiz.querySelector(".plantoir-quiz-feedback")?.textContent ?? ""
while (Date.now() < until && feedback() !== RIGHT) await pause(100)
if (feedback() !== RIGHT) return "the feedback reads \"" + feedback() + "\", not \"" + RIGHT + "\""
const explain = quiz.querySelector(".plantoir-quiz-explain")
if (!explain || explain.hidden) return "the explanation is not shown"
document.activeElement && document.activeElement.blur && document.activeElement.blur()
// Framing as quiz-math.js, with the passage's top as the top that must stay
// in the picture: the question is about it.
const overhang = quiz.getBoundingClientRect().bottom - (window.innerHeight - 56)
if (overhang > 0) window.scrollBy(0, overhang)
if (passage.getBoundingClientRect().top < 40) return "the passage and the quiz are " + Math.round(quiz.getBoundingClientRect().bottom - passage.getBoundingClientRect().top) + " pt tall and do not fit in the window"
return "ready"
