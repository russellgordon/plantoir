// The course's files a site carries (#901): Quartz's own Assets emitter,
// which copied EVERY file in content/ that is not a page, replaced by one
// that copies only the files a page students can see uses
// (contracts/shared-rules.json -> siteFiles; the rules are in
// siteFilesRules.ts beside this file).
//
// The same walk as Assets (`glob("**", ...)` with its ignore patterns, so a
// file with no extension is offered too, which ctx.allFiles leaves out) and
// the same destination (slugifyFilePath), so a file that is carried is at
// exactly the address it always was. `content` is the PUBLISHED pages on the
// first emit; a rebuild hands every page, so hidden ones are skipped by the
// publish filter's own rule.
//
// build_site.py swaps `Plugin.Assets()` for `Plugin.PlantoirAssets()` in each
// section's quartz.config.ts (ALWAYS section, idempotent, marker
// PLANTOIR-SITE-FILES), and reads the built site again afterwards
// (scripts/site_files.py): a file a page needs that this left out is put back
// and said, and the gates fail on it.
//
// quartz/plantoir_site_files.json (written by the build) is READ, not
// imported: the files always carried, the footer's addresses, and which
// attributes hold an address (siteFiles.addresses, the one list this and
// scripts/site_files.py both follow). Without it only the root favicon is
// always carried and no attribute is read, so every file a page uses is left
// to the check after the build, which puts it back and fails the gates.

import { readFileSync } from "fs"
import fs from "fs"
import path from "path"
import { FilePath, joinSegments, slugifyFilePath } from "../../util/path"
import { glob } from "../../util/glob"
import { QuartzEmitterPlugin } from "../types"
import { addressesThePagesUse, SideFile, SitePage, TreeNode } from "./siteFilesRules"

const SIDE_FILE = path.join("quartz", "plantoir_site_files.json")
const LAST_USED = "__plantoirSiteFilesLastUsed"

type Content = Array<[unknown, { data: Record<string, unknown> }]>

function sideFile(): SideFile {
  try {
    const parsed = JSON.parse(readFileSync(SIDE_FILE, "utf-8"))
    if (parsed !== null && typeof parsed === "object") {
      return parsed as SideFile
    }
  } catch {
    // Missing or broken: the defaults below, and the check after the build
    // puts back every file a page uses.
  }
  return { alwaysCarried: ["favicon.ico"], footerAddresses: [] }
}

function sitePages(content: Content): SitePage[] {
  const pages: SitePage[] = []
  for (const [tree, file] of content) {
    const declared = file.data.plantoirFiles
    pages.push({
      slug: String(file.data.slug ?? ""),
      tree: tree as TreeNode,
      frontmatter: file.data.frontmatter as Record<string, unknown> | undefined,
      declared: Array.isArray(declared) ? (declared as string[]) : [],
    })
  }
  return pages
}

const slugOf = (contentPath: string): string => slugifyFilePath(contentPath as FilePath)

async function filesOffered(directory: string, ignorePatterns: string[]): Promise<FilePath[]> {
  return await glob("**", directory, ["**/*.md", ...ignorePatterns])
}

async function copyOne(directory: string, output: string, fp: FilePath): Promise<FilePath | null> {
  const dest = joinSegments(output, slugOf(fp)) as FilePath
  try {
    await fs.promises.mkdir(path.dirname(dest), { recursive: true })
    await fs.promises.copyFile(joinSegments(directory, fp), dest)
  } catch (error) {
    // A file that vanished between the walk and the copy (a preview's
    // rebuild: documentation 05, ENOENT copyfile) is skipped, never fatal.
    if ((error as NodeJS.ErrnoException)?.code === "ENOENT") {
      return null
    }
    throw error
  }
  return dest
}

export const PlantoirAssets: QuartzEmitterPlugin = () => {
  return {
    name: "PlantoirAssets",
    async *emit(ctx, content) {
      const { argv, cfg } = ctx
      const offered = await filesOffered(argv.directory, cfg.configuration.ignorePatterns)
      const addresses = new Set<string>()
      for (const fp of offered) {
        addresses.add(slugOf(fp))
      }
      const used = addressesThePagesUse(sitePages(content as unknown as Content), addresses, sideFile(), slugOf)
      ;(globalThis as Record<string, unknown>)[LAST_USED] = used
      for (const fp of offered) {
        if (!used.has(slugOf(fp))) {
          continue
        }
        const dest = await copyOne(argv.directory, argv.output, fp)
        if (dest !== null) {
          yield dest
        }
      }
    },
    // Reached only by Quartz's own watcher, which no teacher reaches
    // (documentation 05, "A running preview does not follow edits"): the
    // set is worked out again from every page, a file newly used or changed
    // is copied, and one no longer used is removed.
    async *partialEmit(ctx, content, _resources, changeEvents) {
      const { argv, cfg } = ctx
      const offered = await filesOffered(argv.directory, cfg.configuration.ignorePatterns)
      const addresses = new Set<string>()
      for (const fp of offered) {
        addresses.add(slugOf(fp))
      }
      const used = addressesThePagesUse(sitePages(content as unknown as Content), addresses, sideFile(), slugOf)
      const before = ((globalThis as Record<string, unknown>)[LAST_USED] as Set<string> | undefined) ?? new Set<string>()
      ;(globalThis as Record<string, unknown>)[LAST_USED] = used
      const changed = new Set<string>()
      for (const event of changeEvents) {
        changed.add(slugOf(event.path))
      }
      for (const fp of offered) {
        const address = slugOf(fp)
        if (used.has(address) && (!before.has(address) || changed.has(address))) {
          const dest = await copyOne(argv.directory, argv.output, fp)
          if (dest !== null) {
            yield dest
          }
        }
      }
      for (const address of before) {
        if (!used.has(address)) {
          await fs.promises.unlink(joinSegments(argv.output, address)).catch(() => {})
        }
      }
    },
  }
}
