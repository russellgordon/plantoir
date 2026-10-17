// The `code-python-live` figure (#583): Talking to the User's program run on
// a page the preview isolates, answered `Priya` at its first prompt and
// caught WAITING at its second, with `185` typed in the answer field (never
// sent). The body of an async function run by webwindow.swift --prepare;
// `timeoutMs` is its bound. Returns "ready", or the reason it is not.
const WAITING = "Waiting for your answer…"
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
const waitAt = async (prompt) => {
  while (Date.now() < until) {
    const field = block.querySelector("input.plantoir-runner-answer")
    if (status.textContent === WAITING && field && output.textContent.endsWith(prompt)) return field
    await pause(100)
  }
  return null
}
block.querySelector(".plantoir-runner-run").click()
let field = await waitAt("Player name: ")
if (!field) return "the program never waited at its first prompt; the status reads \"" + status.textContent + "\""
field.value = "Priya"
field.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
field = await waitAt("Minutes practised this week: ")
if (!field) return "the program never waited at its second prompt; the output is " + JSON.stringify(output.textContent)
field.value = "185"
field.dispatchEvent(new Event("input", { bubbles: true }))
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
