// My Progress (#545): the site's half that runs when the site is BUILT.
// contracts/shared-rules.json -> myProgress.
//
// An EMITTER, not a pass in Python after the build: a preview is one
// `quartz build --serve` process, and a Python pass after it would never run
// there. Quartz 4.5.0 runs an emitter with no `partialEmit` again, with every
// page, on each rebuild a preview makes (quartz/build.ts), so the manifest
// follows the teacher's edits as the pages do.
//
// It reads the trees AFTER every transformer - so each task box already
// carries PlantoirTasks' stamp (`data-task-item`, the only producer of ids,
// #519 review F1) - and before any page is rendered, so a transcluded
// checklist is still a placeholder and a tree holds only the page's own
// items: the ticks are kept under the page an item is WRITTEN on, and that
// is where it counts.
//
// The build's Python (scripts/my_progress.py) decided before Quartz ran
// whether the section gets the page at all, and wrote quartz/
// plantoir_progress.json: the headings, the words, the classes in the order
// the build dates pages from them, which class first linked each page
// directly, and which pages it read as having counted items. This writes
// public/progress-manifest.json from that and the trees, and says on a
// `plantoir: note:` line wherever the two readings disagree (#545 plan
// review F3), so a dropped tick is never silent.
//
// The plan is READ, not imported, so a missing or broken file costs the
// manifest and never the site.

import { readFileSync } from "fs"
import { join } from "path"
import { QuartzEmitterPlugin } from "../types"
import { FilePath, FullSlug } from "../../util/path"
import { write } from "./helpers"
import { buildManifest, countedItems, CountedPage, Plan } from "./progressRules"

const PLAN_FILE = join("quartz", "plantoir_progress.json")
const MANIFEST_SLUG = "progress-manifest" as FullSlug

const said = new Set<string>()

// Read afresh on every emit - once per build or rebuild, not once per page,
// so there is nothing to gain from keeping it (and a cache keyed on the
// file's time missed a plan written twice in one millisecond, measured in
// the check).
function readPlan(): Plan | null {
  try {
    return JSON.parse(readFileSync(join(process.cwd(), PLAN_FILE), "utf-8")) as Plan
  } catch {
    return null
  }
}

// The publish filter's own rule (patches/publish.ts): on a rebuild Quartz
// hands emitters every page, hidden ones included (#545 plan review F8).
function isHidden(frontmatter: Record<string, unknown> | undefined): boolean {
  const flag = frontmatter?.publish
  return flag === false || flag === "false"
}

function note(page: string, reason: string) {
  const line = `plantoir: note: ${page}: ${reason}`
  if (said.has(line)) {
    return
  }
  said.add(line)
  console.log(line)
}

export const PlantoirProgress: QuartzEmitterPlugin = () => ({
  name: "PlantoirProgress",
  async emit(ctx, content) {
    const plan = readPlan()
    // Switched off, or the teacher's own page by that name: nothing to read.
    // A section where the Python found nothing to count is still read, so a
    // page it missed is said rather than dropped.
    if (plan === null || (plan.page !== true && plan.reason !== "noSuccessCriteria")) {
      return []
    }
    const gate = new Set<string>(plan.gate ?? [])
    const pages: CountedPage[] = []
    for (const [tree, file] of content) {
      const frontmatter = file.data.frontmatter as Record<string, unknown> | undefined
      if (isHidden(frontmatter)) {
        continue
      }
      const path = String(file.data.relativePath ?? "").normalize("NFC")
      const slug = String(file.data.slug ?? "")
      if (slug === plan.slug) {
        continue
      }
      const items = countedItems(tree as never, plan.headings)
      if (items.length === 0) {
        if (gate.has(path)) {
          note(path, plan.notes.gateSaidYes ?? "")
        }
        continue
      }
      if (!gate.has(path)) {
        note(path, plan.notes.gateSaidNo ?? "")
      }
      const title = typeof frontmatter?.title === "string" && frontmatter.title.trim() !== "" ? frontmatter.title.trim() : slug
      pages.push({ path, slug, title, items })
    }
    if (plan.page !== true) {
      return []
    }
    pages.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
    const manifest = buildManifest(plan, pages)
    const written = await write({ ctx, slug: MANIFEST_SLUG, ext: ".json", content: JSON.stringify(manifest) })
    return [written as FilePath]
  },
})
