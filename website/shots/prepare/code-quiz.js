// The `code-quiz` figure (#562): the first question on the marketing ICS3U's
// Check Your Loops page answered correctly and checked, with its explanation
// showing. The body of an async function run by webwindow.swift --prepare;
// `timeoutMs` is its bound. Returns "ready" once the feedback says
// quizCallouts.words.site.right and the explanation is shown, or the reason
// it does not. The words are the contract's (contracts/shared-rules.json).
const RIGHT = "Right!"
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
let quiz = null
while (Date.now() < until) {
  quiz = document.querySelector('.plantoir-quiz[data-quiz-n="1"][data-built]')
  if (quiz) break
  await pause(100)
}
if (!quiz) return "the first quiz on the page was not made ready"
const right = quiz.querySelector('.plantoir-quiz-choice[data-choice="1"] input.plantoir-quiz-input')
if (!right) return "the first quiz has no second choice"
right.click()
quiz.querySelector(".plantoir-quiz-check").click()
const feedback = () => quiz.querySelector(".plantoir-quiz-feedback")?.textContent ?? ""
while (Date.now() < until && feedback() !== RIGHT) await pause(100)
if (feedback() !== RIGHT) return "the feedback reads \"" + feedback() + "\", not \"" + RIGHT + "\""
const explain = quiz.querySelector(".plantoir-quiz-explain")
if (!explain || explain.hidden) return "the explanation is not shown"
document.activeElement && document.activeElement.blur && document.activeElement.blur()
// Framing: the page stays where the scroll to its top left it unless the
// block's bottom (its output included) would be cut off; then the block's
// bottom is brought to a little above the window's edge, so the text above
// it, which says what it is for, stays in the picture.
const overhang = quiz.getBoundingClientRect().bottom - (window.innerHeight - 56)
if (overhang > 0) window.scrollBy(0, overhang)
return "ready"
