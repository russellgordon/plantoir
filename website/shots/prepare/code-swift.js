// The `code-swift` figure (#562): the marketing ICS4U's read-only Swift
// block given a name and an age in its input box and run. The body of an
// async function run by webwindow.swift --prepare; `timeoutMs` is its bound.
// Returns "ready" once the status line says codeRunnerBlocks.words.finished
// and the greeting is in the output, or the reason it does not.
const FINISHED = "Finished."
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
let block = null
while (Date.now() < until) {
  block = document.querySelector(".plantoir-runner[data-built='true']")
  if (block) break
  await pause(100)
}
if (!block) return "no runnable block was made ready on the page"
if (block.querySelector("textarea.plantoir-runner-editor")) return "the Swift block has an editor; it should be read-only"
const box = block.querySelector(".plantoir-runner-input-lines")
if (!box || block.querySelector(".plantoir-runner-input").hidden) return "the block shows no input box"
box.value = "Priya\n14"
box.dispatchEvent(new Event("input", { bubbles: true }))
block.querySelector(".plantoir-runner-run").click()
const status = block.querySelector(".plantoir-runner-status")
const output = block.querySelector(".plantoir-runner-output")
while (Date.now() < until && status.textContent !== FINISHED) await pause(100)
if (status.textContent !== FINISHED) return "the status line reads \"" + status.textContent + "\", not \"" + FINISHED + "\""
if (!output.textContent.includes("Hello, Priya! Next year you will be 15.")) return "the output is " + JSON.stringify(output.textContent)
// Framing: the page stays where the scroll to its top left it unless the
// block's bottom (its output included) would be cut off; then the block's
// bottom is brought to a little above the window's edge, so the text above
// it, which says what it is for, stays in the picture.
const overhang = block.getBoundingClientRect().bottom - (window.innerHeight - 56)
if (overhang > 0) window.scrollBy(0, overhang)
return "ready"
