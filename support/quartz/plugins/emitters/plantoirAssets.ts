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
// imported: the files always carried, the footer's addresses, which
// attributes hold an address (siteFiles.addresses, the one list this and
// scripts/site_files.py both follow) and how a carried HTML, SVG or CSS file
// is followed (siteFiles.followed). Without it only the root favicon is
// always carried and no attribute is read, so every file a page uses is left
// to the check after the build, which puts it back and fails the gates.
//
// A carried file is read from content/ only when it is of a followed kind,
// parsed by Quartz's own HTML parser (hast-util-from-html, which
// plantoirFigures.ts uses too) or read as CSS. When more carried files load
// one another than followed.limits allows, this carries EVERY file, as
// Quartz's own Assets did, and says so on a plantoir: error: line: a file
// wrongly left out breaks a page silently, which is the worse direction.

import { readFileSync } from "fs"
import fs from "fs"
import path from "path"
import { fromHtml } from "hast-util-from-html"
import { FilePath, joinSegments, slugifyFilePath } from "../../util/path"
import { glob } from "../../util/glob"
import { QuartzEmitterPlugin } from "../types"
import { addressesThePagesUse, CarriedFiles, SideFile, SitePage, TreeNode } from "./siteFilesRules"

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

// The course's files as the rules read a carried one: by address, the first
// content path met for it, as scripts/site_files.course_files keeps.
function carriedFiles(directory: string, offered: FilePath[]): CarriedFiles {
  const byAddress = new Map<string, FilePath>()
  for (const fp of offered) {
    const address = slugOf(fp)
    if (!byAddress.has(address)) {
      byAddress.set(address, fp)
    }
  }
  return {
    contentPathOf: (address) => byAddress.get(address) ?? null,
    textOf: (address) => {
      const fp = byAddress.get(address)
      if (fp === undefined) {
        return null
      }
      try {
        return readFileSync(joinSegments(directory, fp), "utf-8")
      } catch {
        return null
      }
    },
    parseHtml: (text) => fromHtml(text) as unknown as TreeNode,
  }
}

// Every address the published pages use, and the files those load. Past the
// follow limit, every file (siteFiles.followed.limits), said loudly.
function addressesUsed(content: Content, addresses: Set<string>, directory: string, offered: FilePath[]): Set<string> {
  try {
    return addressesThePagesUse(sitePages(content), addresses, sideFile(), slugOf, carriedFiles(directory, offered))
  } catch (error) {
    if ((error as Error)?.name === "FollowLimitReached") {
      console.error("plantoir: error: " + (error as Error).message)
      return new Set<string>(addresses)
    }
    throw error
  }
}

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
      const used = addressesUsed(content as unknown as Content, addresses, argv.directory, offered)
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
      const used = addressesUsed(content as unknown as Content, addresses, argv.directory, offered)
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
