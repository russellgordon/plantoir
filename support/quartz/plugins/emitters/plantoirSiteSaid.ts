// What the SITE found, said as a folder problem (#567): the site's half of
// contracts/shared-rules.json -> siteHealth.checks ->
// runnableCodeShownAsPlainCode - and (#644) of quizzesReadDifferently, the
// quiz safety net's lines, said in the same call.
//
// The runnable-code transformer (transformers/codeRunner.ts) shows a block it
// cannot run as plain code and prints a `plantoir: error:` line for it
// (codeRunnerBlocks.siteDisagrees) - a line in the build's console, which a
// teacher previewing in the app never reads. It also records the block on
// the page's file.data.plantoirSiteDisagreements, and this emitter gathers
// every page's on its FIRST emit and hands them to scripts/site_said.py, run
// by the build's own Python, which words ONE finding through site_health and
// prints it as the `PLANTOIR_HEALTH:` line both apps already read. The quiz
// transformer (transformers/plantoirQuizzes.ts) records each line its safety
// net prints on file.data.plantoirQuizDisagreements the same way (#644), and
// both lists go to site_said.py in ONE call, which words a finding for each
// (the code's first) - one Python start, one once-mark.
//
// An EMITTER, not a pass in Python after the build, for My Progress's reason
// (plantoirProgress.ts): a preview is one `quartz build --serve` process, and
// a Python pass after it would never run there. Every emitter finishes before
// Quartz says it is done, so before a preview's server answers.
//
// Python words it, rather than this file from prepared words, so a finding's
// assembly has ONE implementation, tested on both platforms (#567 ruling 1).
// The call costs 24-31 ms in the image (measured), and is made only when a
// block or a quiz disagrees.
//
// ONCE per process: Quartz 4.5.0 runs an emitter with no `partialEmit` again,
// with every page, on each rebuild a preview makes (quartz/build.ts). Saying
// it again would bring the dialog up while a teacher is editing, and the mac
// and Windows deduplicate a changed finding differently (#567 ruling 2); a
// rebuild keeps its `plantoir: error:` lines. The mark is kept on globalThis,
// so a module loaded afresh in the same process does not say it twice.
//
// quartz/plantoir_site_said.json (written by the build, scripts/site_said.py
// -> write_side_file) is READ, not imported, so a missing or broken file
// costs the finding and never the site; and nothing that goes wrong here
// ever stops the build.

import { execFileSync } from "child_process"
import { readFileSync } from "fs"
import { join } from "path"
import { QuartzEmitterPlugin } from "../types"
import type { SiteDisagreement } from "../transformers/codeRunner"
import type { QuizDisagreement } from "../transformers/plantoirQuizzes"

const SAID_FILE = join("quartz", "plantoir_site_said.json")
const ONCE = "__plantoirSiteSaidOnce"
// Generous: a cold Python on a slow Windows laptop, never the 24-31 ms the
// image takes. Past it, the finding is lost and the build goes on.
const TIMEOUT_MILLISECONDS = 20000

type Said = { python?: string; script?: string; [key: string]: unknown }
type Content = Array<[unknown, { data: Record<string, unknown> }]>

// The publish filter's own rule (patches/publish.ts): on a rebuild Quartz
// hands emitters every page, hidden ones included.
function isHidden(frontmatter: Record<string, unknown> | undefined): boolean {
  const flag = frontmatter?.publish
  return flag === false || flag === "false"
}

// Every entry a transformer recorded under `key`, pages in the order of their
// paths (NFC), each page's entries in the order the site recorded them;
// hidden pages left out.
function gatheredUnder<T extends { page: string }>(content: Content, key: string): T[] {
  const pages: Array<{ path: string; entries: T[] }> = []
  for (const [, file] of content) {
    const recorded = file.data[key] as T[] | undefined
    if (!Array.isArray(recorded) || recorded.length === 0) {
      continue
    }
    if (isHidden(file.data.frontmatter as Record<string, unknown> | undefined)) {
      continue
    }
    const entries: T[] = []
    for (const entry of recorded) {
      entries.push({ ...entry, page: String(entry.page).normalize("NFC") })
    }
    pages.push({ path: entries[0].page, entries })
  }
  pages.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
  const all: T[] = []
  for (const page of pages) {
    for (const entry of page.entries) {
      all.push(entry)
    }
  }
  return all
}

// Every block the code runner recorded (#567).
export function gathered(content: Content): SiteDisagreement[] {
  return gatheredUnder<SiteDisagreement>(content, "plantoirSiteDisagreements")
}

// Every line the quiz safety net printed (#644).
export function gatheredQuizzes(content: Content): QuizDisagreement[] {
  return gatheredUnder<QuizDisagreement>(content, "plantoirQuizDisagreements")
}

// Hand the blocks and the quizzes to the build's Python, in ONE call, and
// pass on what it prints. Answers whether it was called. Never throws.
export function sayWhatTheSiteFound(
  content: Content,
  folder: string = process.cwd(),
  write: (text: string) => void = (text) => {
    process.stdout.write(text)
  },
): boolean {
  try {
    const blocks = gathered(content)
    const quizzes = gatheredQuizzes(content)
    if (blocks.length === 0 && quizzes.length === 0) {
      return false
    }
    const said = JSON.parse(readFileSync(join(folder, SAID_FILE), "utf-8")) as Said
    if (typeof said.python !== "string" || typeof said.script !== "string") {
      return false
    }
    const { python, script, ...rest } = said
    const printed = execFileSync(python, [script], {
      input: JSON.stringify({ ...rest, blocks, quizzes }),
      encoding: "utf-8",
      timeout: TIMEOUT_MILLISECONDS,
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
    })
    if (printed) {
      write(printed.endsWith("\n") ? printed : printed + "\n")
    }
    return true
  } catch (error) {
    write(`ℹ️  Could not say what the website found: ${String((error as Error)?.message ?? error).split("\n")[0]}\n`)
    return false
  }
}

// For the check that runs this file (scripts/check_runner_rules_against_the_site.py):
// forget that this process has said it, so each case starts afresh.
export function forgetWhatWasSaid(): void {
  ;(globalThis as Record<string, unknown>)[ONCE] = false
}

export const PlantoirSiteSaid: QuartzEmitterPlugin = () => ({
  name: "PlantoirSiteSaid",
  async emit(_ctx, content) {
    const memory = globalThis as Record<string, unknown>
    if (memory[ONCE] === true) {
      return []
    }
    memory[ONCE] = true
    sayWhatTheSiteFound(content as unknown as Content)
    return []
  },
})
