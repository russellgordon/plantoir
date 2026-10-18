// The `code-python-error` figure (#562): Reading an Error Message's program
// run and answered `abc` as it asks (#583), so it ends in the traceback the page
// teaches from. The body of an async function run by webwindow.swift
// --prepare; `timeoutMs` is its bound. Returns "ready" once the status line
// says codeRunnerBlocks.words.finishedWithError and the output holds the
// ValueError, or the reason it does not.
const FINISHED_WITH_AN_ERROR = "Finished with an error."
const until = Date.now() + timeoutMs
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))
let block = null
while (Date.now() < until) {
  block = document.querySelector(".plantoir-runner[data-built='true']")
  if (block) break
  await pause(100)
}
if (!block) return "no runnable block was made ready on the page"
if (self.crossOriginIsolated !== true) return "the page is not cross-origin isolated, so it cannot ask as the program runs"
const status = block.querySelector(".plantoir-runner-status")
const output = block.querySelector(".plantoir-runner-output")
// Since #583 the preview isolates the page: the program asks, and `abc` is
// typed in the field after its prompt and sent with Return.
block.querySelector(".plantoir-runner-run").click()
let field = null
while (Date.now() < until && !(status.textContent === "Waiting for your answer…" && (field = block.querySelector("input.plantoir-runner-answer")))) await pause(100)
if (!field) return "the program never asked; the status reads \"" + status.textContent + "\""
field.value = "abc"
field.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
while (Date.now() < until && status.textContent !== FINISHED_WITH_AN_ERROR) await pause(100)
if (status.textContent !== FINISHED_WITH_AN_ERROR) return "the status line reads \"" + status.textContent + "\", not \"" + FINISHED_WITH_AN_ERROR + "\""
if (!/line 2[\s\S]*ValueError: invalid literal for int\(\) with base 10: 'abc'/.test(output.textContent)) return "the output is " + JSON.stringify(output.textContent)
// Framing (#583): answering moved the focus to the field, which can scroll
// the page, so the picture is framed afresh - the section's heading near the
// top when the whole block fits under it, otherwise the block's bottom (the
// field, or the output) a little above the window's edge.
let heading = block.previousElementSibling
while (heading && !/^H[23]$/.test(heading.tagName)) heading = heading.previousElementSibling
const blockBottom = block.getBoundingClientRect().bottom + window.scrollY
let top = heading ? heading.getBoundingClientRect().top + window.scrollY - 24 : window.scrollY
if (blockBottom - top > window.innerHeight - 56) top = blockBottom - (window.innerHeight - 56)
window.scrollTo(0, Math.max(0, top))
await pause(300)
return "ready"
