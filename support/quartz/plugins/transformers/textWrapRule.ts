// Text that wraps (#653): the RULE, with nothing of Quartz's in it, so the
// transformer (codeRunner.ts's second markdown plugin) and
// scripts/check_runner_rules_against_the_site.py share one copy - the check
// bundles this file alone and runs every contracts/shared-rules.json ->
// textFenceWrapping.fence.cases case through it in Node.
//
// Russell's ruling (2026-10-23): a ```text fence may opt in to wrapping its
// long lines with the word `wrap` (```text wrap); scrolling stays the
// default, so every other block is byte for byte what it was. Only `text`:
// code is read by column, so code never wraps, and `wrap` after any other
// language (```python wrap) is ignored silently - no folder problem, no
// build line - and the runnable-code reader (codeRunnerRule.runnerFor)
// never treats it as a flag.
//
// The info string (mdast's `lang`, then `meta`) is joined and split on
// codeRunnerRule's INFO_SPACE, exactly as runnerFor splits it, so a
// `text<NBSP>wrap` that micromark leaves wholly in `lang` reads as the
// fence the teacher meant. The first word must be exactly `text` (lowercase,
// as codeRunnerBlocks' Q1); `wrap` may be any later word, exactly.
//
// The transformer wraps a flagged block, at the markdown stage, in
// <div class="plantoir-text-wrap">: rehype-pretty-code 0.14 drops every
// property on <pre> and <code> and writes no trace of the meta (measured
// 2026-10-09 for #455, and again for #653), so a wrapper is the only place
// the flag can survive. components/styles/codeLines.scss does the rest.

import { INFO_SPACE } from "./codeRunnerRule"

export const TEXT_WRAP_CLASS = "plantoir-text-wrap"

export function wrapsText(lang: string | null | undefined, meta: string | null | undefined): boolean {
  const words = `${lang ?? ""} ${meta ?? ""}`.split(INFO_SPACE).filter((word) => word.length > 0)
  if (words.length === 0) {
    return false
  }
  if (words[0] !== "text") {
    return false
  }
  return words.slice(1).includes("wrap")
}
