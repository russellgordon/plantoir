// The `code-python-error` figure (#562): Reading an Error Message's program
// given `abc` in its input box and run, so it ends in the traceback the page
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
const box = block.querySelector(".plantoir-runner-input-lines")
if (!box || block.querySelector(".plantoir-runner-input").hidden) return "the block shows no input box"
box.value = "abc"
box.dispatchEvent(new Event("input", { bubbles: true }))
block.querySelector(".plantoir-runner-run").click()
const status = block.querySelector(".plantoir-runner-status")
const output = block.querySelector(".plantoir-runner-output")
while (Date.now() < until && status.textContent !== FINISHED_WITH_AN_ERROR) await pause(100)
if (status.textContent !== FINISHED_WITH_AN_ERROR) return "the status line reads \"" + status.textContent + "\", not \"" + FINISHED_WITH_AN_ERROR + "\""
if (!/line 2[\s\S]*ValueError: invalid literal for int\(\) with base 10: 'abc'/.test(output.textContent)) return "the output is " + JSON.stringify(output.textContent)
let heading = block.previousElementSibling
while (heading && !/^H[23]$/.test(heading.tagName)) heading = heading.previousElementSibling
if (heading) heading.scrollIntoView({ block: "start" })
if (block.getBoundingClientRect().bottom > window.innerHeight - 24) block.scrollIntoView({ block: "end" })
return "ready"
