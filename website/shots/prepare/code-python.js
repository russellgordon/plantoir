// The `code-python` figure (#562): Spot the Bug's program with its bug fixed
// in the editor, run, and its output under it. The body of an async function
// run by webwindow.swift --prepare; `timeoutMs` is its bound. Returns "ready"
// once the status line says codeRunnerBlocks.words.finished, or the reason it
// does not. The words are the contract's (contracts/shared-rules.json).
const FINISHED = "Finished."
const FIXED = 'names = ["Ali", "Bea", "Cy"]\nfor index in range(len(names)):\n    print(names[index])'
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
let block = null
while (Date.now() < until) {
  block = document.querySelector(".plantoir-runner[data-built='true']")
  if (block) break
  await pause(100)
}
if (!block) return "no runnable block was made ready on the page"
const editor = block.querySelector("textarea.plantoir-runner-editor")
if (!editor) return "the block has no editor"
if (!editor.value.includes("range(1, len(names))")) return "the block is not Spot the Bug's program"
editor.value = FIXED
editor.dispatchEvent(new Event("input", { bubbles: true }))
editor.blur()
block.querySelector(".plantoir-runner-run").click()
const status = block.querySelector(".plantoir-runner-status")
const output = block.querySelector(".plantoir-runner-output")
while (Date.now() < until && status.textContent !== FINISHED) await pause(100)
if (status.textContent !== FINISHED) return "the status line reads \"" + status.textContent + "\", not \"" + FINISHED + "\""
if (output.textContent !== "Ali\nBea\nCy\n") return "the output is " + JSON.stringify(output.textContent)
// The section heading above the block at the top of the window, so the
// picture shows what the block is for; the block itself must still fit.
let heading = block.previousElementSibling
while (heading && !/^H[23]$/.test(heading.tagName)) heading = heading.previousElementSibling
if (heading) heading.scrollIntoView({ block: "start" })
if (block.getBoundingClientRect().bottom > window.innerHeight - 24) block.scrollIntoView({ block: "end" })
return "ready"
