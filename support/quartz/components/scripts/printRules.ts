// Printable pages (#454): the rules, with nothing else in them.
//
// No imports and no DOM, so the same file runs in the browser (print.inline.ts
// imports it) and in Node, where scripts/check_print_rules_against_the_site.py
// bundles it and runs every case in contracts/shared-rules.json ->
// printablePages (answerCallouts, labels, titleCleaning, pageLabels) through
// it. A rule changed here without the contract, or there without here, fails
// verify.sh.

export type Role = "answer" | "question" | "unfold" | "none"
export type Part = "questions" | "answers"

// The other spellings Quartz accepts for each callout kind, which it turns
// into the kind itself (quartz/plugins/transformers/ofm.ts). A callout typed
// `[!check]-` arrives as kind "success" titled "Check", so "Check" is that
// kind's default title, not one the teacher chose.
export const KIND_ALIASES: Record<string, string[]> = {
  abstract: ["summary", "tldr"],
  tip: ["hint", "important"],
  success: ["check", "done"],
  question: ["help", "faq"],
  warning: ["attention", "caution"],
  failure: ["missing", "fail"],
  danger: ["error"],
  quote: ["cite"],
}

function normalised(text: string): string {
  return text.toLowerCase().replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
}

// "Solution (click to expand)" -> "Solution". Only a bracketed phrase at the
// END that begins with click or tap: it is an instruction to a reader on
// screen (decision 5). "(see p. 2)" is the teacher's own words.
export function cleanTitle(title: string): string {
  let cleaned = title.trim()
  const instruction = /\s*\(\s*(?:click|tap)\b[^()]*\)\s*$/i
  while (instruction.test(cleaned)) {
    cleaned = cleaned.replace(instruction, "").trim()
  }
  return cleaned
}

function startsWithAnswerWord(title: string, answerTitleWords: string[]): boolean {
  const text = normalised(cleanTitle(title))
  for (const word of answerTitleWords) {
    const pattern = new RegExp("^" + word + "s?(?![\\p{L}\\p{N}])", "u")
    if (pattern.test(text)) {
      return true
    }
  }
  return false
}

// What a callout does on paper. Decided from what was true when the page
// LOADED: a reader who opened an answer on screen must not print it.
export function role(
  kind: string,
  folded: boolean,
  title: string,
  answerKinds: string[],
  answerTitleWords: string[],
): Role {
  if (!folded) {
    return "none"
  }
  if (answerKinds.includes(kind) || startsWithAnswerWord(title, answerTitleWords)) {
    return "answer"
  }
  if (kind === "question") {
    return "question"
  }
  return "unfold"
}

// A title that says nothing about which answer this is.
export function isGenericTitle(title: string, kind: string, answerTitleWords: string[]): boolean {
  const text = normalised(cleanTitle(title))
  if (text === "" || text === normalised(kind)) {
    return true
  }
  const aliases = KIND_ALIASES[kind] ?? []
  if (aliases.includes(text)) {
    return true
  }
  for (const word of answerTitleWords) {
    if (text === word || text === word + "s") {
      return true
    }
  }
  return false
}

function fill(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{([A-Za-z]+)\}/g, (whole: string, key: string) =>
    key in values ? String(values[key]) : whole,
  )
}

// What an answer is called in the answers: its own title, or where it sits.
export function label(
  title: string,
  kind: string,
  listItem: number | null,
  heading: string | null,
  answerNumber: number,
  words: Record<string, string>,
  answerTitleWords: string[],
): string {
  if (!isGenericTitle(title, kind, answerTitleWords)) {
    return cleanTitle(title)
  }
  if (listItem !== null && listItem !== undefined) {
    return fill(words.questionLabel, { n: listItem })
  }
  if (heading !== null && heading !== undefined && heading.trim() !== "") {
    return heading.trim()
  }
  return fill(words.answerLabel, { n: answerNumber })
}

// "Page 1 of 3" over the questions, "Answers 1 of 2" over the answers.
export function pageLabel(part: Part, n: number, total: number, words: Record<string, string>): string {
  const template = part === "answers" ? words.answersPageLabel : words.pageLabel
  return fill(template, { n, total })
}
