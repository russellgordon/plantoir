# 5. The Build Pipeline (`build_site.py`)

[◀ Previous: Course Setup](04-course-setup.md) · [Back to index](README.md) · [Next: Quartz Customizations ▶](06-quartz-customizations.md)

`scripts/build_site.py` (~4,300 lines) is the engine of the toolchain. Given
a course code and section number, it assembles a complete, customized Quartz
site and either serves it (preview mode, the default) or builds it statically
(`--build-only`, used by deploy).

To achieve maximum performance across all host operating systems (especially
macOS Colima/Lima mounts, and historically Windows WSL2), the pipeline uses a **dual-workspace
architecture**:

```
course_config.json ─┐
shared folders ─────┤                       ┌─▶ preview: quartz build --serve :8081-8084
section<N>/ ────────┼─▶ /tmp/quartz-builds/ ─┤            (fast ext4 AST/esbuild)
patched Quartz ─────┤    (internal ext4)     │                    │
support files ──────┘                        │                    ▼
                                             └─▶ rsync ──▶ .merged_output/section<N>/public/
                                                 (mirror)   (a link, OUTSIDE
                                                                  │  the working folder)
                                                                  └─▶ deploy: deploy.py / deploy.ps1
```

1. **Active build workspace (`/tmp/quartz-builds/<CODE>/section<N>/`)**: Sits
   on container-internal native Linux ext4 storage. The Quartz scaffold,
   pre-baked `node_modules` symlinks, TypeScript transpilation, esbuild bundling,
   and AST walks run here at native disk speeds without crossing virtual host mounts.
2. **Host-mirrored output (`courses/<CODE>/.merged_output/section<N>/public/`)**:
   Receives the final built static assets (`public/`) and `course_config.json` via
   differential `rsync -a --delete` (with `shutil.copytree` fallback). Host-side
   components (`BuildFreshness`, `SectionDetailView`, `ScheduledDeploy`, and `deploy.py`)
   read from this path directly on the host filesystem.

   **Beside `public/`, the build notes when it STARTED** (issue #265, fix
   round): `build_site.py` makes `section<N>/.build-started.pending` before it
   reads the settings or any page, and renames it to `.build-started` once the
   site has been copied out — so `.build-started` always describes the site
   that is there, and a build that fails, is stopped or is a preview leaves it
   alone. The file's modification time IS the start; nothing reads its
   contents. It exists because freshness used to be judged against
   `index.html`'s time, the END of the build, and a Save made while a publish
   was building is older than that page: the next Publish called the site up
   to date and sent the same old build. Measured: a file created from inside
   the Colima container on a bind mount is stamped by the host's clock, the
   same clock as the teacher's Save. Readers: `BuildFreshness.needsRebuild`
   and the scheduled publish's shell (both compare with the EARLIER of the two
   times); Windows' `BuildFreshness.NeedsRebuild` makes the same choice since
   #272 (2026-09-30; its scheduled wrapper builds unconditionally, so it has no
   second reader). The reasoning and what was
   rejected: [09 → "Two windows, one course"](09-mac-app.md#two-windows-one-course);
   the rule: `contracts/app-rules.json` → `buildFreshness.buildStartedMarker`.

**One known extra rebuild, written down so it is not re-found.** Preflight rewrites `course_config.json` after the marker whenever it discovers a new item (a folder or file that arrived in Obsidian since the last build), so the config is then newer than the marker and the next Publish rebuilds once for nothing (measured 2026-09-24: `needsRebuild` true after a build that discovered `Extra Notes.md`). It errs toward rebuilding and settles after one build; not worth a special case.

   **That path is a link, and the built site is not inside the working
   folder.** Since 2026-09-05 `courses/<CODE>/.merged_output` is a symlink to
   `~/Library/Application Support/Plantoir/builds/<folder id>/<CODE>` on
   macOS, and Windows writes to `%LOCALAPPDATA%\Plantoir\builds\<folder id>`
   through `PLANTOIR_BUILD_ROOT` (no link and no `.merged_output` level —
   `toolchain_paths.merged_output_root()` is the one place that knows). The
   built site is derived and can always be made again, but a synced folder
   uploads every build of it, Time Machine backs it up, and a zip or a Finder
   copy of the course carries it. The link means every reader above keeps
   naming the path it already names; the launchers bind-mount the builds
   folder into the container at the SAME absolute path so it resolves
   identically on both sides. The rule, and what was rejected, is in
   [`contracts/shared-rules.json`](../contracts/shared-rules.json) →
   `buildOutputLocation`.

   **"Every reader keeps naming the path it already names" is true on the MAC
   only, and assuming otherwise cost a real bug.** The link is what makes it
   true there. Windows has no link, so a reader that names
   `courses/<CODE>/.merged_output` on that platform is naming a place nothing
   writes to any more — and `BuildFreshness`, the one thing that decides
   whether a publish rebuilds first, was exactly such a reader until
   2026-09-06. It answered from a location Windows had abandoned while the
   publish came from the real one: always "rebuild" on a course made since the
   move, and — on a course still carrying a leftover `.merged_output` — "no
   rebuild needed" about a file that was not what would be published. On
   Windows the build path is now named once in C# by
   `Plantoir.Core/Models/BuildOutputLocation.cs`, which takes the folder id
   from `FolderContainers.FolderIdentifier` rather than deriving it a second
   time. **Anything on that platform that needs to find a built site should
   ask that type, and nothing should spell `.merged_output` by hand.**

## Stage 1: Validation and preflight discovery

After checking that the course, section folder, and `course_config.json`
exist, and that the requested section is one of the course's
`section_numbers`, the script performs **preflight discovery**:

<a name="preflight-discovery"></a>

It scans the course root and section folder for top-level folders/files that
are *not yet listed* in `course_config.json` and appends them. A newly
discovered folder is also added to `expandable`, so it appears with a chevron like any other. The updated config is written atomically
with a `course_config.backup.json` safety copy.

**Preflight never changes `hidden`** (issue #265, 2026-09-24). It used to take
a newly discovered folder OUT of `hidden` and write the list back ("Un-hid newly
discovered folder"). Measured with the real preflight on five folder shapes — a
hidden per-section folder moved to the course root, the same name made at both
levels, a name listed in one scope and made in the other, and a folder ticked
hidden before it was listed, shared or per-section — every one looped: the build
un-hid it and erased the tick from the file, the app went on showing the tick,
the next Save put it back, and the next build took it out again. `hidden` is now
written by the setup wizard and the apps only; a "new" folder already named in it
stays hidden, which errs the safe way (hiding from the sidebar never unpublishes
a page). Nothing depended on the rewrite: the build copies the FILE into the
output, and adds `Media` and the coverage page to the sidebar's list in memory
(`names_the_sidebar_hides`) without writing them back. Rejected: limiting the
un-hide to names the teacher "could not have ticked" — Course Settings offers
only listed names, so every entry was ticked by somebody or is a legacy entry
nobody should lose silently. Cases: `contracts/file-formats.json` →
`sidebarHiding.buildKeepsHidden`, run by `scripts/test_sidebar_hiding.py`.

**The app does not save over what preflight added, either.** Course Settings
used to write its whole in-memory copy, so a Save from a window that had read the
file before a build dropped the folders that build had appended (the next build
rediscovered them). Since #265 a Save writes only the settings that window
changed — see [09 → "Two windows, one course"](09-mac-app.md#two-windows-one-course).

**The one thing discovery does not do is re-add what the teacher took away.**
Names the teacher removed in Course Settings are recorded in `excluded_items`
(keyed `shared` / `per_section`), and preflight skips them: not discovered, not
not expanded, and — since 2026-08-24 — actively **dropped** from
`shared_folders`, `shared_files`, `per_section_folders` and `per_section_files`
if it finds one back in a copy list, with the config written back. So the four
copy lists are *not* add-only: `excluded_items` is authoritative. The exclusion
is by NAME — matched exactly, case included — and does not expire, because
discovery cannot tell "the folder I excluded" from "the new folder I just
made", which is the rule teachers are told about in
`contracts/shared-rules.json` → `specialNames.contentStructureTip`. An excluded
folder that already has an `index.md` gets a sentinel-delimited note explaining
why, removed again on re-inclusion. See
[`08-course-config-reference.md`](08-course-config-reference.md) for the key.

**Rationale:** teachers create folders in Obsidian mid-course. Without
discovery, every new folder would require re-running the setup wizard;
with it, the folder just shows up on the next preview. Reserved names
(`Media`, `.obsidian`, `.merged_output`, `node_modules`, `course_config.json`,
OS junk files) are excluded from discovery.

<a name="how-i-teach"></a>

### The teacher's How I Teach page never reaches a site (#209)

`How I Teach.md` at the top of a course folder is the teacher's own account of
how the course is taught, read by the outside doors
([10 → "Telling an outside assistant how the course is taught"](10-local-ai-assistant.md#telling-an-outside-assistant-how-the-course-is-taught-209)).
Before #209, discovery listed it like any top-level file and the site
published it — measured on a scratch course, at the course's top level and at
`section1/`'s, both. `publish: false` cannot be the guarantee (a later
`publishForSection<N>: true` beats it, and a page typed in Obsidian has no
flag at all), so the build keeps it off by LOCATION, asking
`scripts/how_i_teach.py` at four points, all in the ALWAYS section so no
course needs `--full-rebuild`:

1. **Discovery** — `discover_shared_items` / `discover_section_items` never
   list it.
2. **Preflight** — a name ALREADY listed in `shared_files` /
   `per_section_files` (a course whose page predates the rule) is dropped and
   the configuration written back, the way an excluded name is; the in-memory
   config a build is handed without a write (`_dropping_excluded_items`) drops
   it too.
3. **The copy lists** are filtered where they are READ, not in each loop, so a
   copy loop added later inherits the rule.
4. **A final sweep** (`remove_from_content_root`) deletes any match from the
   top of the merged `content/` before the health checks and Quartz — the
   backstop that makes the guarantee a property of the output. Top level only:
   inside a folder the name is an ordinary page, and the sweep only ever
   touches the build's own copy, never the teacher's folder.

The name is matched whole, after NFC, with only A–Z folded; at the top of a
section folder too, because a section's top-level files land in the same place.
The console says `howITeachPage.keptOffTheWebsiteLine` when a page is found,
and names a LOOK-ALIKE ("How I Teach 1") that WILL be published
(`lookAlikeLine`) — that silent publication is the failure the exact name risks.
When a page the settings had listed is dropped, the build prints
`PLANTOIR_KEPT_OFF: {json}`, which the app writes on the trail
(`How I Teach page kept off the website`) — once, at the transition, not on every
build. Gates: `scripts/test_how_i_teach.py` (Windows runs it too), and
`verify.sh`'s real build, which plants pages with sentinel phrases and greps the
whole of `public/` (pages, `contentIndex.json`, sitemap, RSS) — the reserved
two absent, the look-alike present so the check cannot pass by building nothing.

**One residual, needing no code** (plan review): a site built for PUBLISHING
before the update, while such a page existed, and not rebuilt since, still holds
the page, and a publish that uploads that existing build sends it. A new image
tag does not by itself rebuild a site. It applies only to a teacher whose page
was already public before the update; the first build after the update removes
it (`public/` is cleaned and mirrored with `rsync --delete`), and every preview
build is rebuilt before it is published.

## Stage 2: Scaffold management

The container build workspace `/tmp/quartz-builds/<CODE>/section<N>/` is
created on first build (or wiped and recreated with `--full-rebuild`) by staging
from `/opt/quartz` — the pinned v4.5.0 checkout carrying the
[image-level patches](06-quartz-customizations.md#a-components-replaced-at-image-build-time)
and [setup-time patches](06-quartz-customizations.md#b-patches-applied-at-setup-time-to-the-scaffold).

Because staging happens on native ext4 storage within the container, copying the
scaffold takes **< 0.1 seconds**, and `/opt/quartz/node_modules` is symlinked
directly into the build folder. The host output folder
`courses/<CODE>/.merged_output/section<N>/` is created to receive the mirrored
`public/` build outputs — inside the builds folder the link points at, not
inside the working folder.

On a fresh scaffold, the script immediately applies the **first-build
patches** (Graph removal, locales, date-handling config, folder-page
behaviour, date format, styles, transclusion support, fonts — all enumerated
in [customizations §C1](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)).
On subsequent builds the scaffold (including its `node_modules` symlink) is reused
for speed, and only the **every-build patches**
([§C2](06-quartz-customizations.md#c2-applied-on-every-build)) run — these
are the ones driven by settings a teacher might change between builds
(colour scheme, footer, title, locale, reading time, Explorer behaviour,
hidden list).

All patches are **idempotent**: each one detects "already applied" and does
nothing, so running the build repeatedly is safe.

> **Why `tee`?** Many patch functions write files via
> `subprocess.run(["tee", path], input=…)` rather than Python file writes.
> This is a defensive choice from debugging bind-mount write issues —
> `tee` reports failures loudly and behaves consistently on the mounted
> filesystem.

## Stage 3: Content assembly

The `content/` folder inside the output is **deleted and rebuilt from
scratch on every build** — content is cheap to copy, and this guarantees
deletions and renames in the vault propagate.

<a name="media-handling"></a>

1. **Media symlink.** `content/Media` is created as a *relative symlink* to
   the course-level `Media/` folder rather than a copy. Media is the largest
   folder in a course (images, video); with, say, three sections, copying
   would quadruple disk usage and slow every build. A symlink means zero
   copies and instant availability. (`Media` is also forced into the hidden
   list so it never appears in the sidebar.)
2. **Section home page.** `section<N>/index.md` is copied to
   `content/index.md` — the site's front page.
3. **Shared folders and files** are copied in, preserving structure.
4. **Per-section folders and files** are copied from `section<N>/`.

During copying, every Markdown file passes through two transformations:

<a name="frontmatter-processing"></a>

### Frontmatter processing (the multi-section trick)

For the section being built (say section 3), each file's frontmatter is
rewritten:

- `publishForSection3` → `publish` (and `createdSection3` → `created`)
- Failing that, the legacy `draftSection3` (or a plain `draft`) is read and
  **inverted** into `publish`, so a course written before the change builds
  exactly as it always did.
- *All* per-section keys — both spellings — are then deleted.

**The rewrite is not a rewrite of those keys alone — it is a full YAML round
trip, and that is the root of an entire class of bug.** `process_frontmatter`
uses `frontmatter.load` / `frontmatter.dumps` (python-frontmatter → PyYAML,
**YAML 1.1**), so what Quartz eventually parses has already been NORMALISED:
`no`/`off` have become `false` and `yes`/`on` have become `true`, `FALSE` has
become lowercase `false`, an inline `# comment` is gone, and anything PyYAML
could not resolve has become a quoted string. A tool that reads the teacher's
raw line and a tool that reads the built site are therefore answering two
different questions, and until 2026-09-18 both apps answered the wrong one —
`publish: true # why` made Plantoir list a live page as held back. The measured
table, and the rule both apps now implement, is
[08 → Whether students see a page](08-course-config-reference.md#whether-students-see-a-page);
`scripts/check_visibility_against_the_site.py` re-measures it on every
`verify.sh` run.

Two consequences worth knowing here. Frontmatter the round trip cannot parse —
tab indentation, an unclosed quote, `yes:` used as a key — is HIDDEN, in the
build's copy only, and named (#246, below); until 2026-09-25 the function
warned and left the copy exactly as it found it, and Quartz then either
stopped the whole build or published the page. And the `pip install` in the Dockerfile pins
python-frontmatter and PyYAML deliberately, because the visibility table rests
on YAML 1.1 and a PyYAML that moved to YAML 1.2 would republish pages teachers
had hidden with nothing failing anywhere.

So a shared file marked `publishForSection1: true, publishForSection3: false`
is published on Section 1's site but excluded from Section 3's — one file,
independent publication state per section. This mechanism is why the workshop
"quest" about a missing *Thread 2, Day 11* page has the answer it does: the
page was not published for that section.

Quartz decides visibility with `PublishFlag` (`patches/publish.ts`), which
drops a page only when it says `publish: false`. That matters more than the
renaming: Quartz's stock `ExplicitPublish` filter would have required
`publish: true` on every page and silently removed every page that forgot it —
including all of the curriculum pages. A missing flag should never make work
vanish, so the patched filter keeps the forgiving default and only the word
changes.

### A page whose settings cannot be read is hidden (#246)

**The rule.** When `frontmatter.load` raises on a page, `process_frontmatter`
rewrites the BUILD'S copy to `---\npublish: false\n---` followed by the
page's own body, byte for byte (split off by python-frontmatter's own
`YAMLHandler().split`, which does no YAML), records the page, and prints one
line: `🙈 Hidden from students until its settings can be read: <page> (near
line N)`. `publish: false` is the one key every section reads as hidden, so
the page is hidden in every section whatever it said. The hiding never
touches the teacher's own file — it runs on the copy in `content/`, which is
deleted and re-copied on every build, so the rule is ALWAYS-section by
construction and existing course folders pick it up without `--full-rebuild`;
and `_write_date_into_the_teachers_page` already refuses a source it cannot
parse. **One shape never reaches it (#584):** a section front page whose title
Plantoir wrote with an unquoted `: ` before 1.8.1 is quoted first, by
`copy_the_section_front_page`, in the copy always and in the teacher's page
when it may be changed — `contracts/shared-rules.json` → `buildRepairs`, and
[04 → "A course made before 1.8.1 is put right by its next
build"](04-course-setup.md) for the rule, what was measured and what was
rejected.

Then, once per section build, ONE `pageSettingsUnreadable` site-health finding
names every such page (at most ten, then "and N more"), each with the line the
reader stopped near where it can tell. Its words are
`contracts/shared-rules.json` → `siteHealth.checks[pageSettingsUnreadable]`;
the cases are `unreadablePageSettings.cases`, run by
`scripts/test_unreadable_page_settings.py` through the real
`process_frontmatter`, and by `check_visibility_against_the_site.py` on down
through Quartz's own reader to the site. It is never offered a repair
(`siteHealth.repair.neverOffered`): rewriting a teacher's settings means
guessing what they meant. The front-page title above is the one exception,
because Plantoir wrote it and there is nothing to guess — and it is the BUILD
that puts it right, unasked, not a button. It reaches the trail through the
existing `folder problem found` line, which carries the check's NAME and never
a page's.

**Why: Russell, 2026-09-21, option B.** "A page that wrongly DISAPPEARS is
noticed and harmless; one that wrongly APPEARS cannot be undone." A page
whose settings the build cannot read might be one the teacher meant to keep
from students, so it is hidden rather than risked. The finding is what makes
"noticed" true.

**What happened before, measured** (python-frontmatter 1.3.0 / PyYAML 6.0.3 /
gray-matter with js-yaml `JSON_SCHEMA`, the image's own, 2026-09-25). When
PyYAML raised, the function printed `⚠️ Could not read frontmatter from <path>:
<PyYAML's message>` and returned, leaving the copy untouched, so Quartz parsed
the ORIGINAL block itself. Of the shapes in
`copyingAPageBetweenCourses.builderAgreement`, **18** raise when the page is
opened as a file, as the build opens it:

| What Quartz then did | How many | Which |
|---|---|---|
| could not read it either, so `process.exit(1)`: **the whole build stopped** with a developer's error | 14 | a list whose indentation decreases, a combining mark after a colon, a vertical tab, `"a"b"`, `,comma`, a column-0 list item, an indented continuation holding a colon, `key:value`, `a: b: c`, an unclosed quote, `-- -`, `%YAML`, an undefined alias, a tab indent |
| read it, and **published the page** unless it also carried a plain `publish: false` | 4 | a date that cannot be (`2025-09-93`), the 29th of February with a colon in its offset, `yes:` as a key, U+2028 |

The headline is the second row: a page hidden only by `publishForSection1:
false` — which is what the app writes for a course-level page — carrying
`yes: value` was PUBLISHED (measured by `check_visibility_against_the_site.py`
against the old `build_site.py`: "the contract says hidden and the site says
visible").

**The plan's count and the review's count were both off, and a third number
is the true one.** The plan said 18 raising / 13 stopping / 5 read; its review
said 19 / 15 / 4, counting "a LONE carriage return". The lone carriage return
raises only when the block is handed to python-frontmatter as TEXT
(`frontmatter.loads`), which is how `builderAgreement` measured it; the build
calls `frontmatter.load` on the FILE, which opens it with universal newlines,
so the carriage returns become line ends, the block ends at the first `---`,
and it is READ. It is in `unreadablePageSettings.cases` as a readable case for
that reason. Measured in the image, and `builderAgreement`'s own `why` for it
already says the build uses universal newlines.

**Incidence.** 0 of 14,699 real and shipped pages raise today (the planner's
walk: 12,490 under `support/`, 1,620 in a real 2026-27 working folder, 589 in
the 2023-24 iCloud courses), so no existing site changes on the first build
after the update. 25 real pages open with an EMPTY block (`---` then `---`):
PyYAML reads that as no keys and the page is shown, and it stays shown — it is
a case.

**"Near line N", and how it is counted.** The line is counted from the
character INDEX PyYAML reports (`problem_mark.index`, or a `ReaderError`'s
`position`) into the text python-frontmatter handed it, which begins with the
newline that ends the opening fence — so newlines before the index, plus one,
is the file's line with the opening `---` as line 1. **Not** from
`problem_mark.line`: PyYAML counts U+2028, U+2029, U+0085 and a lone `\r` as
line breaks, which an editor does not show, so U+2028 on line 3 reports 5 by
its own count and 4 by the index. Of the 18 shapes, 15 carry a position: 10
point AT the wrong line and 5 one or two past it (a key with no space after
its colon, `-- -`, `%YAML` and U+2028 one past; an unclosed quote two past, at
the closing fence). A date that cannot be, a key that is a number, date or
yes/no, and the offset February 29th give none, and the words then name the
page alone. Hence "near".

**What the console no longer says.** The old line printed PyYAML's message,
which QUOTES the page's own text (`title: A page: with a colon`) into a
console that goes into problem reports, and said "frontmatter". The new line
carries the page's place in the course folder (`section1/index`,
`Concepts/Arrays`) — the name a teacher finds it by in Obsidian — and nothing
of the reader's.

**When hiding itself fails.** A copy that cannot be rewritten is REMOVED
(named just the same); a copy that can be neither rewritten nor removed stops
the build with a plain two-line refusal, in the manner of the hide-filter
hardening: a build that cannot promise the page is hidden must not produce a
site. Both are tested by making the write and the removal refuse rather than
by file modes, because the image runs as root (which writes through any mode)
and NTFS ignores a folder's mode — a mode-based test would have run nowhere.

**An unreadable FRONT PAGE** is hidden like any other page, so Quartz emits no
root `index.html` and there is no website. What that costs is not what any
other hidden page costs, so it gets its own words throughout:

* its own console line (`🙈 The settings at the top of the front page of … could
  not be read, near line N, so the website has no front page until they are
  fixed, and it cannot be published.`) and the finding's `frontPage` sentence
  added to the detail;
* a teacher whose site is already live keeps the OLD published site: the
  refusal comes in the build, before the deploy, so nothing is uploaded and
  what students see does not change until the front page is fixed;
* the last built site is CLEARED, exactly as for a missing front page
  (`_clear_a_site_this_build_cannot_replace` → `_clear_stale_host_site`,
  whose 🗑️ line says the front page is hidden rather than missing), so a
  publish cannot send out last week's pages;
* `section_index_exists` stays TRUE — the page is there, even in the one case
  where its copy had to be removed to hide it — so `sectionIndexMissing` does
  not fire and its repair (which would find the page and say "already put
  right") is not offered;
* a publish build prints its OWN refusal (`_nothing_to_publish`), never the
  missing front page's "no front page, so no website was produced … Put the
  front page back", and the apps turn it into their own card:
  `contracts/app-rules.json` → `failureExplanations`, the three cases whose
  output says the front page's settings could not be read (with a line,
  without, and followed by the deploy's "Built site not found", which must not
  win). `test_unreadable_page_settings.py` checks each of those outputs
  against what `_nothing_to_publish` prints, so the app cannot be matching a
  line nobody prints;
* the "📆 The front page now carries the date …" line is not said of it: only
  the hidden copy was dated.

Measured end to end on 2026-09-25 by building a copy of `courses/EXC2O` in the
image with the new scripts: `Learning Goals` given `publishForSection1: false`
and `yes: value` built with the page absent from `public/` and one finding;
then `section1/index.md` given `title: "Section "1"` built with no root
`index.html`, the previous `public/` removed, the refusal naming line 2, exit
1, and the teacher's file unchanged but for the edit.

**Rejected, so nobody proposes them again:**

* **Deleting the page from the build instead of hiding it.** A missing page is
  a different state: an unreadable `index.md` would fire `sectionIndexMissing`,
  whose repair finds the page and says it was already put right.
* **A rule in Quartz's publish filter (`patches/publish.ts`).** Quartz cannot
  read 14 of the 18 shapes at all, so the hide has to happen before Quartz sees
  the original block.
* **Stopping the build**, which is what used to happen for most shapes. One
  typo withheld every other update, including a scheduled publish the teacher
  was counting on (`siteHealth.scheduledDeployPublishesAnyway`).
* **One finding per page.** Both apps key a finding on name, course and
  section (the mac's `SiteHealthFinding.id`, Windows'
  `SiteHealthFinding.Identity`), so per-page findings would collide in
  SwiftUI's `ForEach` and in Windows' de-duplication.
* **A once-only "newly hidden since the update" list.** It needs state
  carried across builds, and the finding already repeats on every build while
  the page is broken.
* **Also hiding a block whose END cannot be found** (an indented closing
  fence, a block never closed). It cannot be told from a page that begins
  with a horizontal rule, which is a case here. Where such a block ends was
  [#188](https://github.com/russellgordon/plantoir/issues/188)'s question, and
  its answer left the build alone: the apps now agree with python-frontmatter
  that an indented `---` closes nothing, so the page has no block and is
  published, as before.
* **Making the apps' readers call such a page hidden.** They would need a twin
  of PyYAML in Swift and C#, and #207's certifier is deliberately stricter, so
  it would flag readable pages. The dangerous disagreement (the app says
  hidden, the site shows it) is now impossible; the one left (the app says
  shown, the site hides it) is the mild direction, and the finding announces
  it.
* **Printing PyYAML's message**, for the reason above.
* **Filling the finding's words one placeholder after another.** Since #246 a
  value can be a page name a teacher typed, and a page called `{pages}` or
  `{line}` would be expanded by a later replacement. `site_health.filled` does
  one pass, and `test_site_health.py` proves the difference by swapping the
  sequential version back in (1 test goes red).

**Consequences for the copy guard.** `CopiedPageText`'s check that the builder
reads a copy the same way (#207, `copyingAPageBetweenCourses.builderAgreement`)
still refuses these shapes: a copy that arrives hidden by accident, and is
named as a problem on every build, is not a clean copy. Whether it can now be
relaxed is a follow-up and was not done here.

### Wikilink rewriting

In Obsidian, a link into section content looks like
`[[section2/All Classes/Thread 2, Day 8|Thread 2, Day 8]]`. In the built
site there is no `section2/` prefix — the section's content *is* the site
root. The build rewrites any aliased wikilink whose target contains a
`section<digits>/` path down to its alias: `[[Thread 2, Day 8]]`. Quartz
then resolves it by file name, which works because that file was copied into
the content tree. (The same is done for transclusions, `![[…]]`.)

**Where this applies.** `rewrite_section_wikilinks` runs on the section's
`index.md`, on every markdown file inside a per-section folder, and on
per-section loose files — that is, on content that came from
`section<N>/`. Shared content is copied with frontmatter processing only, so
a section-path wikilink written in a SHARED page is not rewritten, and
would reach the site as a broken link. Nothing in the example course or the
payloads writes one — a shared page is read by every section, so it has no
one section to link into — but Obsidian produces that form whenever a
teacher links across folders, so a shared page pointing at a class page
needs the plain `[[Thread 2, Day 8]]` form.

<a name="dates-drive-everything"></a>

### Dates: which page carries which, and who writes them

Pages listing folder contents in Quartz sort by date, and this toolchain
[configures dates to mean *created*](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)
(from frontmatter, never from git). Two passes run on EVERY build, in the
ALWAYS part of `build_section_site`, after the content has been copied and read
for this section (`process_frontmatter` has already turned `createdSection<N>`
into `created` in the build's copy):

1. **Pages no class brings** — `_sync_non_class_pages_created`. Sidebar pages,
   Key Links, Curriculum pages and anything no class page links to, directly or
   through other pages, take the first class's date (`class-planning.json` → `datingNonClassPages`), in the
   build's COPY only. (This section used to describe a "bump every curriculum
   page up to the newest date". Nothing does that any more: measured
   2026-09-24, `_is_in_curriculum_folder` is defined and called nowhere, and
   curriculum pages get the first class's date from this pass like every other
   page nothing links to.)
2. **The front page and the pages a class links to directly** — `_date_pages_from_their_classes`
   (GitHub #275, #276, 2026-09-25). This one REWRITES THE TEACHER'S OWN FILES.

A page reached only THROUGH another shared page is in neither population: the
first pass skips it (a class reaches it) and the second does not date it (no
class links it directly), so it keeps its own date — and an undated one stays
undated.

#### The rules (`sectionIndexPointer.dateCases`, `datingPagesAClassBrings.atBuildTime`)

- **The front page** (`section<N>/index.md`) takes the date of the class page
  its embed names — the first `![[…]]` line naming one of this section's class
  pages, found exactly as the app's pointer finds it
  (`sectionIndexPointer.found`) — when that class is VISIBLE and dated. No class
  embed, or an embed naming a hidden or undated class: the page keeps its own
  date and is not written. The build never moves the embed; that is the
  pointer's job. **The embed is read OUTSIDE code and `%%` comments** (#397,
  2026-09-30): the front page's body is masked with
  `markdown_code.not_a_link_ranges`, and a line whose `![[` starts inside the
  mask is skipped — Quartz never draws a class line a teacher parked in a
  comment or a fence, so dating the page from it put a date above a class
  students could not see. A `.md` typed after the class's name is read too.
  Measured on a scratch copy: before the mask the two new `dateCases` (a
  comment, a fence) failed (`FAILED (failures=2)`), after it they pass; 0 of
  the 89 shipped front pages change. The app's pointer reads the line the same
  way, and Preview's question about today's class depends on it
  (`documentation/09-mac-app.md` → "Today's class on the front page (#397)").
- **A page a class links to DIRECTLY** takes the date of the EARLIEST visible,
  dated class of this section that links to it (ties by title), EVEN OVER A DATE
  OF ITS OWN — including one the teacher typed on the page. **A date typed on a
  page that a class links to no longer decides its date: its first class's
  date wins, on the site and in the file**, on every build; to date such a page
  by hand, link it from the class whose date it should carry. In the FILE that
  means: on a shared (course-level) page, a typed `createdSection<N>` is
  rewritten, and a typed plain `created:` STAYS, byte for byte — the build adds
  `createdSection<N>` above it, which the site reads in preference, so editing
  that `created:` later changes nothing; on a section's own page, `created`
  (or the `createdSection<N>` it already uses) is rewritten. (Nothing in the app says this
  to a teacher yet: a sentence for them is Russell's wording pass, not this
  piece's.) "Links to directly" means the wikilinks written on the class page
  itself, resolved by relative path and by file name (`_pages_a_page_links_to`,
  shared with the first pass's walk) — never onto another class page, a
  folder's index, Key Links or any curriculum coverage map (#128). A page two links away is
  not dated by the class at all.

  **Which shapes are links** (`_extract_wikilink_targets`, the one reader both
  passes share; contract `shared-rules.json` → `readingALink`, run by
  `scripts/test_dates_follow_the_class.py`): `[[Page]]`, `[[Page|words]]`,
  `[[Page#Heading]]`, and the escaped pipe Obsidian writes for an alias inside
  a table, `[[Page\|words]]` — whose backslash is never part of the name — and,
  **since [#294](https://github.com/russellgordon/plantoir/issues/294),
  `[[Page#Heading|words]]` and `[[Page#Heading\|words]]`**, the form
  Obsidian's own autocomplete writes for a heading link with an alias. Until
  then the pattern put its alias group BEFORE its heading group, so a heading
  followed by an alias was not a link to either pass. **After #294 ships, three
  groups of pages whose only link of that kind is this shape change on the next
  build, in every existing folder** (measured with the real functions against
  the old and new pattern):

  - **Linked directly from a visible, dated class** — the second pass now dates
    it. On the SITE it moves from the first class's date (the first pass's
    stamp) to its class's; in the TEACHER'S FILE it moves from whatever date
    the file held — its install-day stamp, or a date the teacher typed — to its
    class's, as for any page a class links to (the file rules above), and the
    page is named in the "Gave N of your page(s)…" line and on the trail
    (`pagesDatedByTheBuild`).
  - **Linked that way only from a HIDDEN or UNDATED class** — the first pass's
    walk starts from every class page, so the page is now reached and no longer
    reset: on the SITE it moves from the first class's date to its own date
    (for a page copied from a template, the install-day stamp). The file is not
    touched — the first pass writes the build's copy only.
  - **Reached only THROUGH such a link** (a hub page carrying `[[P#h|a]]`, and
    what it leads to) — likewise now reached, so it keeps its own date on the
    site instead of the first class's; the file is not touched.

  The last two are the rule stated above ("a page reached only THROUGH another
  shared page … keeps its own date") applying to links it used to miss. It is
  the right change, and not only because the link is a link: the mac app's
  re-date already read `[[P#h|a]]` as a link to P (its name stops at `#`), so
  until #294 the app and the build disagreed about those pages and the build
  won by overwriting on every build. Measured: 0 such links in `support/`
  (payloads, skeletons and the example course, code stripped — the old and new
  readers give identical targets on all 12,490 files), so no shipped page
  moves; teacher-written ones will. No log line's wording changes and none
  becomes untrue.

  **A stray `[[` followed by a heading cannot swallow the link after it** (since
  [#314](https://github.com/russellgordon/plantoir/issues/314)): the heading
  group stops at `[`, as Quartz's own `wikilinkRegex` does. This reader skips
  inline code (since #313, below), but a `[[` typed in a sentence, followed later by a `#` and a
  real `[[Page|words]]`, otherwise read as one link with a garbage name and
  the real one was lost. Only the heading group stops at `[`; the name still
  crosses it, so a stray `[[` with no `#` before the next link still swallows
  it — left as it is, since no shipped page has that shape and widening the
  name is a change to `readingALink.rule` itself. Measured: 0 change on all
  12,490 files in `support/`.

  **The other readers of the same shapes, since #314.** The installer's three
  (`setup_course.py`: `first_use_dates`, `WIKI_LINK_TARGET` for retargeting a
  template's expectation, `unlink_curriculum_references`) now stop the name
  before a backslash right in front of `]`, `|` or `#`, as `readingALink.rule`
  says — all three had read `[[P\|a]]` as a page called `P\`. The coverage
  map's two (`BLOCK_LINK`, behind "pages the course teaches", and
  `TRANSCLUSION`, what it counts as covered) already read `\|` but had the old
  alias-before-heading order, so `[[P#h|a]]` and `![[A1.1#h\|a]]` matched
  nothing. They were NOT given #294's plain reorder: those two stripped fenced
  code but not inline code (until #313, below), and on `Tutorials/Scavenger Hunt.md` (the example
  course and every skeleton family, 90 files) the reordered pattern ran from
  "type `` `[[` ``" through a `### Custom Display Words` heading and swallowed
  the real `[[Help Sessions|…]]` after it. With the heading stopping at `[`:
  0 differences over all 12,490 files, fences-only or inline-stripped. Every
  `readingALink` case runs through every one of these readers in
  `scripts/test_install_link_readers.py`, which `verify.sh` lists and Windows'
  `PythonToolchainTests` discovers. Rejected: one shared `wiki_links.py` for
  all six readers — each needs different groups, and a new sibling module is a
  Dockerfile change (`test_baked_modules.py` exists because one was once
  missed); and stripping inline code in `_pages_the_course_teaches`, which
  changes what counts as taught by a different rule (#313's question — since
  answered, below, WITH a shared module: the mask is one rule every reader
  needs identically, which the six patterns were not).

  **A link written inside code is not a link, for every one of these readers**
  (since [#313](https://github.com/russellgordon/plantoir/issues/313)). A
  `[[…]]` whose brackets start inside a fenced block or an inline code span is
  an example of the syntax, and Quartz draws none. `scripts/markdown_code.py`
  is the one Python definition of where code is — `readingALink.whatIsCode`,
  implemented identically by the mac's `MarkdownCode` (measured: the two agree
  offset for offset on all 12,490 files in `support/`) — and every reader here
  asks it: `_extract_wikilink_targets` (both date passes), `BLOCK_LINK` behind
  "pages the course teaches", `TRANSCLUSION` in the coverage count, and the
  installer's three. It is baked beside `class_pages.py` (a Dockerfile `COPY`,
  guarded by `test_baked_modules.py` and `verify.sh`'s baked-file check).
  What changed: the dating walk used to strip ```` ``` ```` fences and one-line
  spans with two regexes, so a `~~~` fence, a span across two lines of a
  paragraph, a ```` ``` ```` held inside ```` ```` ```` and an escaped backtick
  were all read wrongly; the coverage map's two readers stripped fences only;
  the installer's three stripped nothing. The coverage count now also reads a
  `%%curriculum-start%%` block only where its markers are OUTSIDE code
  (`_curriculum_blocks_outside_code`) — a fenced example of a curriculum block
  on a page that teaches how to write one used to count as coverage — and a
  marker shown inside a fence neither opens nor closes a block, so a fenced
  example cannot swallow the real block after it. A match that starts in code
  is not simply dropped: the search starts again where that code ENDS, or an
  example `` `[[` `` would swallow the real link after it. Measured over
  `support/` with Quartz's own parser: 1,896 of 39,570 links sit in code, 0 in
  indented code (which the rule deliberately does not recognise); the build
  read 7 of them as links before, all on TEJ2O's "Control Something with
  Code", whose fence inside a list had fallen out to column 0 — fixed in the
  same piece, so its coverage is unchanged. `scripts/test_markdown_code.py`
  runs every case through the dating walk and a rename, and checks the
  coverage count; `verify.sh` lists it and Windows' `PythonToolchainTests`
  discovers it. The why, the table built in Quartz, and what was rejected are
  in [10 → Code is never a link](10-local-ai-assistant.md#code-is-never-a-link-313).

  **A `%%` comment is never a link either** (since
  [#331](https://github.com/russellgordon/plantoir/issues/331)). Quartz v4.5.0
  removes every `%%…%%` from the RAW page before it reads anything
  (`ofm.ts:130`, `:160–163`): lazily, left to right, across lines, whether or
  not a `%%` sits in code, and a `%%` with no partner is plain text. So
  `markdown_code.py` does the same, in the same order: `comment_ranges` finds
  the comments on the page as written, `code_ranges` finds code in the page
  WITH EVERY COMMENT REMOVED and maps the ranges back to the page's own
  offsets, and `not_a_link_ranges` is the two merged — the default mask of
  `matches_outside_code`, so every reader above, the installer's three and the
  linters mask comments without being told. **The trap this is built around:
  the curriculum markers `%%curriculum-start%%` and `%%curriculum-end%%` ARE
  comments** (Quartz pairs lazily, so each marker is a whole comment and the
  block between them is not). `_coverage_counts` therefore asks two different
  questions: whether a MARKER is in code (`code_ranges`, which still returns
  code only) and whether a LINK is a link (`not_a_link_ranges`). Folding the
  comments into `code_ranges` would skip every block and empty every coverage
  map while the build stayed green; `readingALink.cases` → "the curriculum
  markers are comments, and what sits between them is not" and
  `test_markdown_code.CommentTests.test_code_ranges_hold_code_only` guard it.
  Measured in Quartz's own order over all of `support/`: 344 of the 39,570
  matches sit inside a comment, all in skeletons (294 naming What This Site
  Can Do, 50 Help Sessions); 100 page-to-page edges existed only inside
  comments, none from a class page, and no class page of 3,944 reaches fewer
  pages; both targets keep plain links, so the site check gains no orphan; 0
  of the 344 sit inside a curriculum block. The rule agrees with Quartz on all
  39,570 and on the 12 new cases; finding code on the page as written (R1)
  also agrees on the corpus but gets two of the cases wrong. Found on the way
  and fixed: AVI1O's and TEJ4M's `Tasks/_DUPLICATE ME.md` wrote "%%" in the
  prose of their note, which closed the comment early and put the rest of the
  teacher's note on the site of every copy (new courses only); the payload
  linter now refuses a page with an odd number of `%%`.
- **A class dated with a plain YAML date** (`created: 2026-09-24`, unquoted —
  what Obsidian's Date property writes) counts, as midnight in Toronto. Until
  the fix round `_parse_created_value` read it as no date at all, so such a
  class dated nothing and a page it linked took a LATER class's date (measured:
  Day 2's 09-24 instead of Day 1's 09-10). That also widens the first pass and
  `_find_first_class_created`, which read dates through the same function.
- **Per section.** The build of section N reads section N's classes and writes
  section N's keys only: a course-level page gets `createdSection<N>` (never a
  plain `created:` shared by every section, and never another section's key); a
  page inside `section<N>/` gets `created`, unless it already uses
  `createdSection<N>`, which the build reads first. A plain `created:` already on
  a shared page is left alone — it still dates the sections with no key of their
  own.
- **The value is the class's own, copied**, not re-formatted: converting a
  timestamp to Toronto time can move its calendar day near midnight UTC, and the
  page must show the day its class shows. It is written plain where that reads
  back as the same value and double-quoted where it would not (a bare
  `2026-09-24` string would read back as a DATE, and be rewritten every build).

#### Measured: why nothing dated Russell's pages (2026-09-24, ICS4U section 1)

The front page said `created: 2026-09-08…` (the day the course was made) above
`![[Thread 1, Day 3]]`, dated 09-24. `Exercises/Using Aggregate Functions`
carried `createdSection1: 2026-09-08T07:00:00.000+0000` and
`publishForSection1: true` — install day, very likely inherited from the
`_DUPLICATE ME` template it was copied from, whose own text promises the dates
"will be set automatically". Three writers existed and none was on his path:

- the app's pointer (`SectionIndexPointer.repointIndex`) and the assistant's
  publish-time rule run only when the ASSISTANT publishes — Day 3 was published
  in Obsidian — and the publish-time rule moves only pages that are still
  HIDDEN, which this one was not;
- the installer's `first_use_dates` runs once, at pre-population;
- the build's first pass explicitly skipped both pages: `index.md` since
  `61ae2ab5` (2026-08-18, "so the landing page retains its newest published
  class's date" — preserving a date the mac pointer writes, not deciding that
  the build must not date it), and every page reachable from a class since
  `6ddc3fd0` (2026-08-17 — the pass set out to date only pages NO class brings,
  leaving linked pages to the installer and the assistant). **Neither skip is a
  decision to leave the page undated; both assumed another writer.** Do not
  "restore the design" by folding the new pass into the first one: they date
  different populations with different dates, and are kept as two named passes.

On `origin/dev` before the change, `scripts/test_dates_follow_the_class.py`
fails 16 cases and errors 9; the ICS4U front page and Using Aggregate Functions
both stay at `2026-09-08T07:00:00.000+0000`.

#### Why the teacher's files, and not only the site — and what was REJECTED

- **Build-output-only was REJECTED by Russell (2026-09-25 07:40)**, overriding
  the plan review's recommendation. The review's reasons were real: a write on
  every preview can meet a page open in Obsidian; a page changed after a build
  has started makes the app build once more (#265's `.build-started` marker —
  see "When the stamp is written" below); iCloud churn. Russell wants the files
  to carry the true dates, so that Obsidian, the app, the assistant and the site
  agree. What keeps the cost down is idempotence: a page is written ONLY when
  the date the build would read for this section differs, so after the first
  build of a course the pass writes nothing, and #265's extra build happens once
  rather than on every publish. The test builds every case twice and requires
  the second build to write no file.
- **(B) "never earlier than the class"** — keep a later date typed by hand — was
  the other option put to Russell on 2026-09-24; he chose (A), the class's date
  even over the page's own, because it has no judgement call inside it and a date
  on a site ordered by date is a statement about the course.
- **Filling only undated pages** (the first plan) — fixes nothing for Russell's
  page, which HAS a date; the review measured this on the real file shape.
- **Hidden classes dating pages** — a class students cannot see has not been
  taught; a page only a hidden class brings keeps its own date until the class
  is published.
- **One `created:` for a shared page** (Russell, 07:45) — the last section
  built would win for every section.
- **Following links THROUGH pages** — REJECTED on 2026-09-25, after it had been
  built that way, by the implementation review's measurement. Courses link hub
  pages from Day 1 ("How Marks Work", "Learning Goals") that link half the
  course, so the earliest class claimed nearly everything it could reach. On
  the EXC2O fixture the first build rewrote 105 pages and **98 of them were
  given Unit 1, Day 1's 2026-09-08** — `Concepts/Cellular Respiration`, which
  its October class links directly, among them, by the chain Day 1 → `Setup/How
  Marks Work` → `Tasks/Lab Reports` → `Investigations/Investigating
  Photosynthesis` → it. Across the 39 payloads (every class treated as visible)
  **2,150 of 5,177 reached pages took an EARLIER class than the first one
  linking them directly** — ICS4U 133 of 136 (59 through `Learning Goals`),
  SNC1W 107 of 150 (88 through `How Marks Work`), MHF4U 142 of 148. The walk had
  been harmless while the plan only FILLED missing dates; once choice (A) let it
  overwrite, it rewrote installer-dated, visible pages and reported success.
  Russell's words were "the first Unit x, Day y page that LINKED to them", and
  the installer (`first_use_dates`) already followed direct links only. The
  contract's hub case (How Marks Work → Lab Reports → Investigating
  Photosynthesis) pins it: the page in between keeps its own date, and the page
  a later class links directly takes THAT class's date. Also rejected: walking
  through pages for UNDATED pages only — it infers a date nobody set from a page
  in between, which the rule does not ask for.

#### How the write is made — a line splice, never a re-serialisation

`_setting_frontmatter_value` changes one key line and nothing else: the apps'
own fence rule (three or more dashes; blank lines before the opening fence
skipped — `PageVisibilityReader.fenceIndices`; since #188 the CLOSING fence must
start at column 0, as python-frontmatter's does, while the opening one may be
indented — so a line of indented dashes is part of the value above it and goes
with it, where it used to end the block early and make a write that read back
wrong and was dropped; `documentation/08-course-config-reference.md` has the
measurement); the LAST line naming the key,
because it is the one YAML keeps; the lines below it that belong to its value go
with it (`continuationLineIndices`' rule from #176, which #199 applies to the
apps' own date and title writers — ported to Python here because #199 had not
landed on `dev` when this was written; if the two ever disagree, the contract's
`writingCases` are the arbiter); a missing key goes at the top of the block,
and only into a block with a column-0 level for it — the apps' rule from #186,
`_place_for_a_new_top_level_key`, so a block whose first line is indented or
is not a key is refused rather than given a key that adopts that line; a
page with no frontmatter gets a block. Not touched at all: a block opened and
never closed (which since #188 includes one whose only closing-looking line is
INDENTED — the apps' visibility writer prepends a block on that shape instead,
and 08 says why the two differ), a tab-indented block, a file starting with a
byte-order mark.
A `# note` at the end of the key's line stays (a `#` inside quotes, or in the
middle of a word, is part of the value). Every write is read back the way the
build reads it before it is saved, and refused unless this section's date is now
the class's and every other key and the whole body are exactly as they were.

**The write is never made in place.** `_replace_the_page_safely` writes the new
text to a hidden file beside the page (`.<name>.….plantoir-dating`), flushes it
to disk, copies the page's permissions onto it, re-reads the page, and renames
the new file over it in one step ONLY if the page still holds exactly the text
the date was worked out from. A Stop part-way through leaves the old page or the
new one, never a truncated one; an Obsidian save that lands after the read is
kept, and the next build dates it. The cost, accepted: a renamed-in file is a
new file to the file system, so its creation time is the time of the write,
and it does not carry the page's extended attributes across — measured by the
fix-round review on macOS 26 through the container, a `user.` attribute was
lost 4 times of 4 and a Finder tag 1 time of 3 (it came back in the other two,
presumably restored by macOS — not something to rely on). Nothing in Plantoir
or the build reads either (only frontmatter dates count), but Obsidian's file
list sorted by "created time" will move a rewritten page, and a Finder tag on
one can go. Writing in place would keep both, and stays REJECTED: a Stop or an
editor save part-way through leaves a torn page, and a torn page is worse than
a lost tag. The
first version truncated and wrote in place with no re-check — a window of a few milliseconds per page, across the
~100 writes of a course's first build, on the teacher's own file.

**Links are never written through.** A page that is a symbolic link, one inside
a folder that is (between the page and the course folder — the build's copy
follows a shared folder that is itself a link), or a file with a second name
(a hard link) is left alone: measured, the first version rewrote a file OUTSIDE
the course through a link, and two courses sharing one page would overwrite
each other's `createdSection1` on alternate builds. Its site copy is still
dated; the console names it ("Left the date on N page(s) as it was, because
each one also lives somewhere else…"), and it is not on the trail, because
nothing was written.

**A read-only page is not written either**, and that IS checked before the
write, from the page's mode bits (no write bit for owner, group or anyone):
a rename would replace a file that an ordinary write refuses. It is read from
the mode bits and not from `os.access` because the build runs as ROOT in the
container, where `os.access` says yes to every file — the fix-round review
measured the first version rewriting a 0444 page there, mode kept.
`test_a_read_only_page_is_named_and_left_alone_even_for_root` makes
`os.access` answer as it does for root. Its site copy is still dated, and the
console names it ("Left the date on N page(s) as it was, because each one is
locked or set so it cannot be changed…"). **Finder's Locked flag (`uchg`) is
NOT checked before** — Linux cannot see it (no `st_flags`), so the check finds
nothing in the container. What was measured, as root in the image against a
`uchg` page under `$HOME`: the HOST refuses the rename, the page is unchanged,
and `_replace_the_page_safely` removes its hidden file, so none is left
behind. That page is skipped silently (not named), and the next build tries
again. Python run on the Mac itself (the tests) does see the flag and names
the page as it names a read-only one; Windows has no such flag, and its
read-only attribute shows up in the mode bits, so the native build there
refuses and names a read-only page.

**A course kept for reference is dated on its site only** — its files are
never rewritten (`write_back=False` when `reference_course.is_reference` or
`cannot_tell`). Last year's course is frozen on purpose, often with its files
locked, and a preview of it is a look rather than an edit. This was the
implementer's call, not Russell's ruling, and is flagged as such
(`atBuildTime.aCourseKeptForReference`).

**Where a page came from** is recorded as the build copies it
(`remember_vault_source`, beside each `shutil.copy2`): the section's
`index.md`, each shared folder and file (a course page), each per-section folder
and file (a section page). A page the build made itself has no source and is
never written back.

#### The trail

When anything was rewritten, the build prints a plain sentence and one
`PLANTOIR_DATED: {"course", "section", "pages"}` line naming each page by its
place in the course folder (`shared-rules.json` → `pagesDatedByTheBuild`). The
mac records it as "pages dated by the build" (`PagesDatedByTheBuild`,
`ScriptRunner`), shows the teacher only the sentence, and prints nothing when
nothing changed. A SCHEDULED publish records the same line from its own log:
`ScheduledDeploy.recordFolderProblems` already reads that run's part of the log
(from `logSizeBeforeRunning`) for `PLANTOIR_HEALTH:` lines, and now hands it to
`notePagesDatedByTheBuild` too — and, since #153, to `noteFolderProblems`,
which leaves that run's `folder problem found` lines (Stage 3.5 → "The
overnight path's trail line"). The first version left it out, saying the app
was not reading that console — wrong, since the scheduled run IS Plantoir
(`--run-scheduled-deploy`) and reads its log in-process; and a scheduled publish
is often the first build after a class goes visible, so the likeliest to rewrite
files. The sentence the build prints is "Gave N of your page(s) the date of the
first class that links to them".

The front page's title repair (#584) reports the same way under its own
prefix: one `PLANTOIR_REPAIRED: {"course", "section", "repair", "page"}` line
per repair WRITTEN into a teacher's page (`shared-rules.json` →
`buildRepairs.marker`), which the mac records as `folder problem repaired`
(`BuildRepairReport`, read in `ScriptRunner` and in
`ScheduledDeploy.recordFolderProblems` beside `PLANTOIR_DATED:`); Windows
records it the same (`BuildRepairReport.cs`, read in `ScriptRunner`,
`ScheduledHealthFindings` and `plantoir-mcp`'s `LauncherRunner`, #645). A separate
prefix rather than a second use of `PLANTOIR_DATED:` so that a later repair
joins it under its own `repair` key; a reader that meets a key it does not
know records nothing. Nothing is printed when only the build's copy was
quoted.


**"Get Ready for the Start of the Year" (#96) deliberately does NOT read these
dates.** Its rule decides which pages go into draft from LINKS — which classes
link a page directly, by position — because straight after a rollover a page's
stored date comes from a transitive walk and says the first day about pages
first used in Unit 3 (measured: 53 SNC1W and 79 ICS3U concepts left published
by a date-based rule). So a change to how pages are dated here changes nothing
it hides; the only date it reads is a CLASS page's own, for the "already
taught" warning. `documentation/10-local-ai-assistant.md` → "Getting a section
ready for the start of the year".

### Which pages are class pages: the word AND the scheme (#267)

What the build counts as a class page — for the curriculum coverage map's
"pages the course teaches", and for the first-class date non-class pages
inherit — is `class_pages.class_page_pattern(word, scheme)`, set once per build
by `set_unit_word` and `set_class_page_scheme` from `course_config.json`.
`unit_day` (absent, empty or unknown) is `^<word>\s+(\d+),\s*Day\s+(\d+)$`;
`numbered` — a club — is `^<word>\s+(\d+)$`, and its first class is
`<word> 1` (leading zeros allowed). The same rule both apps read through
`class-planning.json` → `pageNaming`. The build prints which scheme it is using.

**No build patch, so no ALWAYS-section rule applies**: the pattern is read
fresh on every build, and nothing is written into a course. REJECTED: a
free-form pattern key (`"{word} {n}"`) — every planner would need a parser for
a regex a teacher wrote. A course whose pages are "Week N" but whose file names
no scheme (Russell's `CODING`) is read as `unit_day` and so finds no class
pages, exactly as before: nothing converts a course by building it.

## Stage 3.5: Checking the folders this course depends on

Once the shared and per-section folders have been merged into `content/`, and
before Quartz builds anything, `scripts/site_health.py` asks whether the
features that depend on particular folders can still work.

**It runs HERE for two reasons.** Every check is defined over the MERGED tree,
which does not exist until the copying above has finished — so there is nothing
for a check to look at earlier, and an app could only ask these questions by
reimplementing the merge in Swift and C#. And a check that guarded only the
GUI's button would be bypassed by the assistant, by `Plantoir --mcp-stdio`, by
the launchers, and by the scheduled deploy, which runs with the app closed.

It is NOT a complete guard on publishing, and it is worth being precise: a
deploy of a build made in an earlier session carries no health output of its
own, because `deploy.py` publishes an existing `public/` unless a live preview
is attached, and `deploy.sh --to-folder` never enters the Python at all. The
findings are recorded when the BUILD happens.

**Every check asks whether the FEATURE produced anything**, never whether a
folder exists. Recreating an empty `Ontario Curriculum` folder does not restore
a teacher's expectation pages — `_find_curriculum_folders` wants a page named for
an expectation code — so an existence check with a "fix it for me" button would
have silenced the warning and left the map missing.

Each finding is printed twice: once as a sentence a teacher reads, and once as
a `PLANTOIR_HEALTH: {json}` line that the apps parse out of the console
transcript they already read. The teacher-facing sentence travels INSIDE that
line rather than being written again in Swift and C#, which is what stops the
same problem being worded differently on the two platforms. The sentences
themselves live in `contracts/shared-rules.json` → `siteHealth.checks`.

**The marker line is hidden from every surface a teacher reads**, and printing
the sentence separately is what makes that free. A JSON payload is machinery
(`CLAUDE.md` rule 1), so each app drops the line on its way into the console —
and on Windows also on its way into the assistant's progress messages and the
tail it reports back, which is a second surface and was leaking until
2026-09-06. Anything that narrates raw launcher output is such a surface; the
question to ask of a new one is not whether it shows the transcript but whether
it shows a LINE.

**The mac's assistant surface was CHECKED on 2026-09-25 (#153), and narrates
no line.** The in-app assistant and `Plantoir --mcp-stdio` build their answers
from `AssistWording` plus `SiteHealthFinding.appending` — each finding's
sentence and detail, read from the runner's findings, never from its
transcript — and `AssistMCPServer` sends no progress notifications. Nothing in
`Models/Assist/` or `Views/Assist/` reads `displayText` or `recentText`.
`SiteHealthFindingTests.testTheAssistantsAnswerCarriesAGluedFindingAndNoMachinery`
pins it. The `--mcp-stdio` process also WRITES the trail line: it runs a real
`ScriptRunner`, and its trail store is the ordinary one. The one hole on this
surface was the glued marker below, which was missing from the answer because
it was never read at all.

One check is about a PAGE rather than a folder: `pageSettingsUnreadable`
names the pages the build hid because it could not read their settings (#246,
"A page whose settings cannot be read is hidden" above). It is the LAST
finding a build emits, so the others keep their places — the marker examples
and #153's console cases are captured in that order.

Two of the checks stay quiet unless the other half of the map exists: a
brand-new course has an empty curriculum folder and an empty class folder on
day one, and warning about both would nag every build of a course nobody has
broken.

**A skeleton course can now have expectations to map, and its map is all
red.** Until
[#251](https://github.com/russellgordon/plantoir/issues/251) (2026-09-22) a
course made from a subject's skeleton had two pages in its Curriculum
folder — a generic index and a placeholder called `A1.1` — so
`_find_curriculum_folders` found a folder and `_collect_expectations`
returned exactly one specific expectation. Switching the map on there would
have drawn a single cell for an expectation that does not exist. A teacher
who declines the ready-made pages for one of the 39 codes that have them
now gets that code's real expectations installed into the skeleton, so the
map is built from the same 47-and-12 (ICS4U) the payload course draws.

**Day one it is entirely red, by design.** Coverage counts the site's own
links from lessons to expectations and a skeleton course has none yet, so
`_coverage_counts` returns `covered: 0, assessed: 0` for every cell. That
is the intended reading rather than a defect to special-case — the page's
caption already says "red in September, greener as the year goes on" — and
`site_health` is quiet about it for the same reason the paragraph above
gives.

### Links into hidden pages (#333)

`linksIntoHiddenPages` is the second check about PAGES rather than folders,
and the last finding a build emits (after `pageSettingsUnreadable`, so the
existing examples keep their order). A class published by its own flag — in
Obsidian, by the assistant, by #96's Get Ready — can link to pages that are
still hidden, and students who follow such a link find nothing. The director's
ruling on [#333](https://github.com/russellgordon/plantoir/issues/333): the
BUILD warns, because it is the one place that sees every publish (a flag
flipped by hand, scheduled deploys, the MCP server). **Since #379 the warning
is also an offer**: the build works out which hidden pages publishing would
bring back to life and the section window shows them as a checklist — see
"The links checklist (#379)" below. What #333 said here ("the app's publish
does not start taking pages with it") was reversed on 2026-09-29, and why is
written there.

- **The rule** (`_links_into_hidden_pages` in `build_site.py`; contract
  `siteHealth.checks` → `linksIntoHiddenPages.rule`, cases
  `siteHealth.linksIntoHiddenPages.cases`): after the merge and after the How
  I Teach sweep, every page students can see has its links read — wikilinks
  and embeds, and Markdown-style links in either shape
  (`followingLinks.markdownStyleLinks`), all through the code and comment
  mask. A link is resolved by its PATH first (`[[Concepts/Evidence]]`), then
  by its name; when a name belongs to several pages it is listed only if
  EVERY one of them is hidden, because which of two same-named pages Quartz
  picks is not this check's to guess. Embeds count; pictures and files do
  not; a link to a page that does not exist does not (check_section does not
  list one either); and How I Teach, removed rather than hidden, resolves to
  nothing. Each (from, to) pair once, named by its place in the course folder.
- **One finding per section build**, naming at most ten pairs and counting the
  rest, never one per link: both apps key a finding on name, course and
  section, so per-link findings would collide (#246).
- **No repair BUTTON — but, since #379, a checklist.** #333 said: the two
  fixes are opposite choices — publish the page the link leads to, or take the
  link off the page it is on — and only the teacher knows which is meant. #379
  keeps the choice with the teacher and offers ONE of the two fixes, page by
  page: ticking is publishing, leaving a box unticked is the other. The check
  stays in `siteHealth.repair.neverOffered.checks` because that list is about
  the alert's Fix button, which is still never offered for it (`fixable`
  stays false); the #333 reason moved to `neverOffered.reversed`. Scheduled
  deploys still publish as they are (`scheduledDeployPublishesAnyway`).
- **The trail line** is the family's existing "found a problem with this
  course's folders (linksIntoHiddenPages)". "Folders" is a stretch for links,
  exactly as it already is for `pageSettingsUnreadable`; rewording the family
  is its own case and was not done here. It never carries a page name.
- **Measured (2026-09-26):** 0 links from a visible page into a hidden one
  across all 39 payloads as installed, so a new course is not nagged. An
  emulation of #96's rule (not its code) flipping SNC1W's second class
  visible lists `Unit 1, Day 2 → What Counts as Evidence`, the dead link #333
  describes. And a real second finding the emulation surfaced: the section
  front page EMBEDS the newest class (`![[Unit 5, Day 17]]`), which only the
  assistant's publish and unpublish repoint, so after classes are hidden by
  hand the front page embeds a hidden class and the check lists it. Correct,
  and wanted.
- **Get Ready (#96) is the common way a course arrives in this state, and the
  warning is TRUE there.** Get Ready keeps Day 1, what Day 1 links to directly
  and Key Links visible, and hides every page first used by a later class — so
  the pages it keeps still link to pages it hid (its sheet lists them under
  "links left pointing at hidden pages"). The front page's embed is NOT the
  cause: Get Ready repoints it after its stray-key pass. So the first build
  after Get Ready lists those links, ten named and the rest counted, and the
  warning clears as the classes they lead to are published. Ruled 2026-09-27
  on the implementation review (S1): the warning stays and #96 does not change
  what it keeps — keeping what Day 1 reaches was measured and rejected in #96's
  own plan (16–25 concepts would stay up). The review's rough emulation put
  the pairs left at 16–44 per payload course (SNC1W 18, ICS3U 44); an estimate,
  not #96's code.
- **The build's reading is the site's.** The assistant's check_section reads
  the teacher's folder by title and the build reads merged content by stem,
  so the two may differ on a page whose title is not its file name; the
  shared cases use title == file name and hold for both
  (`SiteHealthContractTests.testTheLinksIntoHiddenPagesCasesHoldForTheSectionGraph`).
  Two pages sharing a name, one hidden, is deliberately not a shared case: the
  mac's graph holds one page per title.

Rejected (in #333): the app's publish taking a class's pages with it (the
issue's other option — a flag flipped in Obsidian bypasses every app path);
one finding per link; a repair button (still rejected — #379's checklist is a
separate path, not a button on the alert); limiting the check to links FROM
class pages (check_section already lists every visible page's dead links, and
two definitions of "a dead link" is what #313 ended).

### The links checklist (#379)

Russell, 2026-09-29, on v1.4.0: after a build, ICS4U Section 1 said "11 links
on pages students can see … lead to pages hidden from them", then one
paragraph of ten `"from" → "to"` pairs run together, "and 1 more", and OK. "It
is TRYING to be helpful, and it is not." A teacher could neither read the list
nor act on it. The finding stays exactly as it was (its cases, the marker, the
console line, the trail line, `fixable: false`); what is new is an OFFER the
build writes beside it, and a checklist in the app that acts on it. Decisions:
the issue's comment "Decisions — Russell, 2026-09-29" (it wins over the body),
and the director's rulings on the plan and its review.

**The shape, in one sentence.** The build works out the offer and writes it to
`courses/<CODE>/.publish_state/section<N>.links-checklist.json`; the app reads
that file after a build it watched, or when the section window next appears
after one it did not, and shows a checklist; the app's existing publish writer
publishes and dates the ticked pages. The rule is shared Python, so Windows
inherits it; the sheet and the writes are each app's.

**The rule** (`_links_checklist_offer` in `build_site.py`; contract
`class-planning.json` → `datingPagesAClassBrings.fromTheLinksChecklist`, 21
cases run by `scripts/test_links_checklist.py`). After the merge, the How I
Teach sweep and BOTH date passes, from every VISIBLE, DATED class of the
section, links are followed up to TWO steps — by the #333 finding's own
reader (path first, then name; a shared name lands on a hidden page only when
every one is hidden). A link onto a class is not entered; a hidden class is
not walked from; the walk does not go through a folder index or Key Links.

- **Used by a class** (`fromAClass`): hidden pages reached at step 1 or 2,
  claimed by the earliest visible class that reaches them (date, then title).
  A page a class links DIRECTLY in the way the build's date pass reads links
  already carries that class's date — the build gave it on this build, hidden
  or not (`atBuildTime`, which has no visibility check) — so the checklist
  writes no date for it (`why: datedByTheBuild`). This is recorded as an
  exception to Russell's decision 4 (director's ruling N8): for those pages
  the build's rule wins even over "published before". Decision 4 governs
  step-2 and other-group pages.
- **Linked from other pages** (`notReachedByAClass`): every other hidden page
  a visible page, OR an offered page, links to — closed transitively, stopping
  at class pages — so publishing everything ticked leaves no new dead link and
  the checklist does not come back one layer at a time (Q8). Dated as the
  first class of the year (`datingNonClassPages`).
- **Classes not yet published** (`class`): hidden classes such a link lands
  on. Never walked through, never dated, never ticked by default (decision 1).
  A class ticked by the teacher is published the way the assistant's publish
  of that class would be (Q2): its own pages come with it, dated by that class,
  its date untouched. Where a page is both a row and brought by a ticked class,
  the CLASS's date wins — one merged plan per press, one write per page
  (ruling F2). It does NOT repoint the front page (ruling F1): `apply` gained
  `repointsTheFrontPage`, false from the checklist only, and the sheet says so
  in one sentence when a class row is shown.
- **Ticking.** Everything in the two page groups starts ticked (decision 1),
  EXCEPT a page that a hidden class links directly while no visible class
  does: it starts unticked, saying which class uses it first ("first used in
  … — it will come with that class"). Measured by the planner over the 39
  payloads with an emulation (not the product code): straight after Get Ready
  (#96) a default-ticked sheet would offer a median of 56 pages (16–82), e.g.
  SNC1W's Final Examination through "How Marks Work", dated Unit 1, Day 1 — one
  press would have undone Get Ready and misdated the year. The literal form of
  that ruling ("a page a hidden class links directly") would ALSO have
  unticked a visible class's own material when a later class links it too, so
  the rule is "and no visible class does" (plan review, finding 5; cases j, k).
  **This narrowing is Russell's decision now, not only the run's.** His
  original decision (decision 1) was that every page in the two page groups
  stays ticked; the v1.4.1 run narrowed it unattended and listed it as a
  ruling he might reverse. Asked on 2026-10-03, with the measurement above in
  front of him, he chose to KEEP the page unticked. Do not propose ticking it
  by default again without a new measurement.
- **Dates are days.** The offer carries `YYYY-MM-DD` as the class's value
  writes it, never converted to another time zone, because the app writes a
  `CalendarDay` exactly as the assistant's date moves do (ruling N9).
- **Folder indexes and Key Links** can be offered (a hidden one is still a
  dead link) but are never given a date (`structuralNeverDated`).
- **Rows that come under another row (#385).** A page no page students can
  see links, reached only through other offered pages, carries `dependsOn`:
  the offered, NON-class rows that link it, nearest to a visible page first
  (fewest offered pages between, a breadth-first count), then by place, never
  truncated. It is `[]` for a page a visible page links and always `[]` for a
  class row — the walk never goes through a class, and a class publishes what
  it links through the class plan. The apps publish such a row only when one
  of those rows is published, and list it under the first
  (`shared-rules.json` → `linksChecklist.followingARow`; the sheet's half is
  in [09 → The links checklist](09-mac-app.md#the-links-checklist-379)).
  Before this, untick a hidden hub and the worksheets behind it stayed ticked
  and went out with nothing students can see linking to them. Cases l–q; an
  invariant test checks, over every case, that each parent is a non-class row
  of the same offer and never the row itself, and that following the first
  parent always ends (so the sheet's nesting cannot loop). **Measured** over
  the 39 payloads laid out as an APPROXIMATE Get Ready (an emulation, not Get
  Ready itself): 2,463 offered rows; 44 depend on another row, in 9 payloads
  (SNC1W 24, MCR3U 7, SCH4U 3, ADA1O 2, SBI3U 2, SBI4U 2, SCH3U 2, MCV4U 1,
  SNC2D 1); 18 have two or more parents; 21 sit under a row of the OTHER
  group; the deepest chain is 2; ADA1O has two pages that link only each
  other. All 44 sit under a row that starts unticked and start unticked
  themselves (a later class uses each first), so straight after Get Ready
  this changes the sheet's LAYOUT, not what a default press publishes; it
  bites in the ordinary authoring case, a hidden hub with hidden worksheets
  behind it. **Rejected:** only the NEARER parents (a DAG) — a page linked by
  a near row that is left and a far one that goes would stay hidden while a
  published page links it; working `dependsOn` out in the app from
  `linkedFrom`, which is capped at 10 (176 of 2,463 rows at the cap) and does
  not say which linkers are visible; a class as a parent or a dependant;
  giving a dependant its parent's date (#379's dating is not reopened); and
  changing the build's `title` to the name the sheet shows (`title_of` also
  feeds class detection and sort keys — the app names rows itself, #362's
  way). The marker's `ticked` still counts rows whose OWN tick is on: nothing
  reads it, and the app's trail line carries what would really be published.

**Why two steps is not a build-time rule.** At build time it would rewrite
VISIBLE pages through hubs on every build — measured and rejected on
2026-09-25 (EXC2O: Day 1 claimed 98 of the 105 pages rewritten; ICS4U 133 of
136 through Learning Goals). And dating a hidden step-2 page at build time
would write Day 1's date into SNC1W's Final Examination while it is still
hidden. Two steps applies only to hidden pages, only when the teacher
publishes them from the sheet.

**"Published before" is a record, not a key on the page** (Q3, accepted;
`datingPagesAClassBrings.publishedBeforeIsRecorded`, which replaces
`neverPublishedIsInferred`). The obvious sign — a date already on the page —
is meaningless: 7,114 of the 7,118 payload pages that carry a publish flag
also carry `created:`, because `setup_course.py` writes it on every page it
makes. Reading it as "published" would switch the dating off everywhere while
every fixture-built test passed; case f carries the page that must move
anyway. The record and how it is written are in
[07 → The published-pages record](07-deployment.md#the-published-pages-record-379).
Honest limit: pages published and hidden before v1.4.1 have no record and take
the class's date once — the first deploy records only the pages visible at
that deploy.

**The file and the marker.** Written atomically on every build (preview,
deploy, scheduled, terminal, MCP), removed when the offer is empty (a dead
link fixed in Obsidian stops being offered), never written — and removed —
for a course kept for reference. `.publish_state` is hidden, so neither
fingerprint nor `BuildFreshness` sees it. The offer is renamed into place
before the marker below is printed, so reading it when the marker ARRIVES —
mid-build, before the site is built — is safe. The #333 finding is announced
BEFORE the date passes run and the offer is written AFTER them, so the app
does not act on the finding: the build prints `PLANTOIR_LINKS_CHECKLIST:
{course, section, buildId, pages, ticked}` once the file is written, and the
app shows the checklist only for an offer carrying that build's id (plan
review, finding 14). A builder older than the app prints nothing, and the
finding goes in the alert exactly as before — the alert is the floor.

**Nothing publishes unattended.** Neither the build nor `deploy.py` changes a
page's visibility (build case i byte-compares every page). A scheduled, MCP
or terminal publish goes out as it is (decision 3), and the checklist is
offered when the teacher next opens that section.

**Noted, not measured: a build in progress** (plan review, note 16): the sheet refuses
while the course is being published, but not while a preview builds; the
build's date writer only renames over an unchanged page, so nothing is
corrupted, and the next build offers again correctly.

Rejected: publishing unattended as if every box were ticked, and refusing to
publish until the links are dealt with (decision 3); a page key such as
`firstPublishedSection<N>`; making `atBuildTime` two steps; computing the
offer in Swift (Windows would owe the walk in C#, and the mac cannot run the
Python outside the builder); carrying the offer only on a console line (a
terminal or MCP publish leaves no console the app reads); an undo; offering
the checklist after every build; `fixable: true`; changing the assistant's
reach to two steps (`linksChecklist.knownDifference`); locked "comes with"
rows under a ticked class (one summary line instead, a cut the director
allowed — reversed by [#398](https://github.com/russellgordon/plantoir/issues/398)
in v1.4.2: the app now shows each row a ticked class brings as coming with
it, from the planner's own plan; the offer the build writes is unchanged,
`documentation/09-mac-app.md` → "Rows a ticked class brings (#398)"); and, with
[#385](https://github.com/russellgordon/plantoir/issues/385) (v1.4.2), the
rejections in the bullet "Rows that come under another row" above and in
`linksChecklist.rejected`.

### Where they run, and where they honestly do not

They run in the toolchain rather than in the app because the GUI button is one of
five ways a build starts — the assistant, the MCP server, the launchers and the
scheduled task all bypass it, and the scheduled one runs with the app closed.

**Be careful repeating the "before anything is published" claim**, because an
earlier version of this section overstated it and it was corrected: `deploy.py`
publishes an EXISTING `public/` and only rebuilds when a live preview is
attached, and `deploy.sh --to-folder` never enters the Python at all. So a deploy
of a build made in an earlier session carries no health output of its own. The
findings are recorded when the BUILD happens. That is acceptable; claiming
otherwise is not.

### The sentence is not the app's to write

Each finding is printed twice: once as a human sentence, and once as
`PLANTOIR_HEALTH: {json}` carrying `name`, `sentence`, `detail`, `fixable`,
`course`, `section`. **Display the `sentence` and `detail` the line carries.**
Do not compose one from the `name` — the whole reason the wording travels in
the payload is so that the same problem cannot be worded differently on the two
platforms, and the sentences have one home in
`contracts/shared-rules.json` → `siteHealth.checks`.

A progress marker would not have done: those are matched loosely and getting one
wrong is silent (see `app-rules.json` → `markerOrigins`). A prefixed JSON line is
unambiguous and carries structure a sentence cannot.

### How long a machine line may be (#666)

**The rule** (`contracts/shared-rules.json` → `machineLineLength`): every
`PLANTOIR_` JSON line the shared Python prints is at most `maxCharacters`
(4,000) characters long, prefix included. The lines that carry an unbounded
list are printed through `scripts/machine_line.py`:

- `PLANTOIR_DATED:` (`build_site.announce_dated_pages`), `PLANTOIR_KEPT_OFF:`
  (`how_i_teach.announce`) and `PLANTOIR_MAPS:` (`build_site.announce_coverage_maps`)
  go through `machine_line.listed`. A line that fits is printed exactly as
  before. A longer one keeps the FIRST k entries, k as large as fits (found by
  halving), and adds `"count"` (how many there were) and `"more"` (how many it
  left out) after the list.
- `PLANTOIR_HEALTH:` (`site_health.announce`) goes through
  `machine_line.fitted`. Every finding that names a list is made through
  `site_health.shortenable`, which remembers how to make it again with a
  smaller `most`. A finding whose line would be too long is remade naming
  fewer than ten blocks or pages, its `andMore` saying how many it left out.
  Its sentence keeps the true count, so no new key is needed. The console's own
  two lines above it keep all ten. `site_said.py`'s two findings go through
  the same `shortenable`.
- The bounded markers (`PLANTOIR_MY_PROGRESS:`, `PLANTOIR_REPAIRED:`,
  `PLANTOIR_LINKS_CHECKLIST:`, both copies of `PLANTOIR_SWIFT:`, and deploy.py's
  space-separated `PLANTOIR_CLOUDFLARE_REMADE:`) are printed as they always
  were. `test_machine_line_length.py` holds each under the cap at its worst
  plausible size, so a list added to one later is caught.

JSON is never cut mid-text, so a reader parses a shortened line exactly as it
parses a whole one. A reader that WORDS a count (the DATED, KEPT_OFF and MAPS
trail lines) takes `count` when it is there, so its "and N more" also counts
what the line left out. Without that the trail would say "the build gave 206
pages…" for a build that dated 300 (the count-first reasoning of
`pagesDatedByTheBuild.trailLine.why`). Russell's ruling on the plan: the true
count travels as its own field, and both apps' readers use it (Windows in
#666, the mac by its own issue).

**The numbers.** The mac's kernel pseudo terminal never splits a line.
Windows' pseudo console does, when a line longer than the console wraps on the
bottom row while Quartz's spinner redraws (#662, measured on a Lenovo
20QES70500, i5-8365U, Windows 11 Pro 26200): a 611-character finding split at
400 columns. #662 widened the app's console to 8,192 columns, the widest
Windows PowerShell 5.1 can afford (doc 12 → "How wide the console is, and
why"). But nothing bounded the lines. `PLANTOIR_DATED:` runs to about 40
characters a page, so about 200 pages pass 8,192, and a ten-block health
finding is about 2,300. The cap is 4,000, HALF the narrowest limit, because a
"character" is counted three ways: Python counts code points, the app's carry
guard (`ScriptRunner`, 8,000) counts UTF-16 units, and the console counts
cells. A CJK character or an emoji is two of either. The Windows suite pins
`2 × maxCharacters` against both (`MachineLineLengthContractTests`). The
contract's cases, run through the REAL emitters: 51 pages of one long name
are 4,029 characters whole, so the line keeps 50, at 3,975 characters; 300
short pages keep 206; 200 kept-off pages keep 154; 100 maps keep 42; ten
links with ~190-character page names (4,382 whole) name 9.

**Rejected:**
- **(b) a side file per payload**, as `PLANTOIR_LINKS_CHECKLIST:` does. Both
  apps' readers would change, a scheduled record keeps lines rather than
  files, and there would be a fourth kind of file to clean up. Russell chose
  (a) on #666.
- **A 32,767-column console.** PowerShell 5.1 pads progress to the width
  (over 280 s for a 2 MB download), and a wider console only moves the limit.
- **Chopping the text at N.** The JSON no longer parses and the reader
  records nothing, which is today's bug made certain instead of occasional.
- **A cap per reader.** The Python prints the line, so one cap in one place
  reaches every reader, the scheduled record included. A reader cannot mend a
  line that has already split.
- **Shortening without the count.** The trail would under-count, which is
  the one thing the trail lines' count-first shape exists to prevent.

### Three traps, all met here

- **Do not read the findings from a tail.** Most other structured-line readers in
  the mac's `ScriptRunner` work from `recentText(maximumCharacters: 8000)`, and
  the health lines print in the MIDDLE of a build. (The preview's announced
  address is the other exception since #235: it is printed even EARLIER, lost
  the same way, and now read from the same carried-over lines as they arrive —
  `documentation/09-mac-app.md` → "Where the address comes from".) On any real build they are
  long past that window by the end. Collect them as output arrives. The mac test
  floods 400 lines after the finding to prove the point.
- **Hide the marker line from the console a teacher reads — a line CARRYING
  it, whole, and while it is still arriving.** A raw JSON blob is machinery
  (rule 1). The human sentence is printed separately, so nothing is lost. The
  mac drops it in `TranscriptBuilder`, and reads findings from the raw text
  BEFORE handing it there. Until #153 (2026-09-25) the mac tested only the
  START of a line, and two leaks followed, both MEASURED by compiling the real
  `TranscriptBuilder`, `SiteHealthFinding` and `PagesDatedByTheBuild`
  standalone: fed `"Building…"`, then the marker and `\r\n`, then `"done"`,
  the console showed `Building…PLANTOIR_HEALTH: {"name": …}` and
  `findings(in:)` returned **0** — the finding was DROPPED, so no dialog, no
  trail line and nothing in the assistant's answer; and fed `"ok\r\n"` then
  the first 60 characters of a marker, both `displayText` and `recentText`
  ended in the half payload until its newline arrived. Now `isMarkerLine` is
  `contains`, the parse reads from the prefix onward (`range(of:)`), and the
  line under construction is hidden while it carries a marker
  (`visibleCurrentLine`) — which is Windows' own rule, adopted
  (`CarriesTheHealthMarker`, `VisibleCurrentLine`, `IndexOf`). The same
  applies to `PLANTOIR_DATED:`, whose trail read is unaffected because it
  reads the raw text, never the transcript. The prompt check also refuses a
  marker line: half a payload cut after `"sentence":` ends in a colon, which
  it would otherwise have offered as a question — `looksLikeQuestion`
  answers false for any marker line, pinned by
  `SiteHealthFindingTests.testHalfAMarkerIsNeverAQuestion`. The cases are
  `contracts/shared-rules.json` → `siteHealth.marker.consoleCases`.

  How a glue could arise: `site_health.py` prints each line whole, so it takes
  something ELSE writing half a line into the same terminal first (stderr
  chatter with no newline). Not observed on a real build; the leak and the
  drop were measured on the code. Parsing from the prefix also means an escape
  sequence left in front of a marker no longer hides it, since findings are
  parsed from the raw line, where #235's per-line colour stripping does not
  apply.

  **Residuals, named rather than fixed** (all the same on Windows): a chunk
  ending in the middle of the PREFIX (`…PLANTOIR_HE`) shows that fragment
  for one refresh — it is not JSON, and a rule hiding every line ending in a
  prefix of the prefix would hide ordinary text ending in "P"; two markers
  glued on ONE line parse as neither, because the JSON parse from the first
  prefix fails — it needs a missing newline between two `print`s, so it is
  theoretical; and the chatter in front of a glued marker leaves the problem
  report as well as the console (`writeRecordOfRun` reads `displayText`).
  **Rejected:** keeping that chatter by cutting the line at the prefix. It
  would differ from Windows, and half a line is not a sentence anybody needs.
- **Show it once.** The mac holds findings in view state rather than reading them
  off the runner at render time, so a teacher who dismisses the dialog and
  carries on editing does not meet it again on the next redraw. A healthy course
  must see nothing at all — the failure mode for this whole feature is nagging,
  and a warning dismissed by habit is dismissed when it matters.

### The overnight path's trail line (#153)

A scheduled publish runs with the app closed, so its findings reach a teacher
through a record the app reads later (`findingsSentinelURL`, consumed by
`takeFolderProblems`). Until 2026-09-25 that was ALL they did on the mac: no
`folder problem found` line was written anywhere on that path — not by the
run, and not when the record was read — so the case the check exists for left
no trace on the trail.

Now `ScheduledDeploy.recordFolderProblems`, in the `--run-scheduled-deploy`
process at the end of the run, hands the run's part of the log to
`noteFolderProblems`, which writes one line per DISTINCT finding in the same
words the console path writes (`SiteHealthFinding.trailSentence`, one home for
two writers). `takeFolderProblems` notes nothing, so one run's finding is one
trail line whether or not anybody opens the section. The line is stamped when
the run FINISHES rather than when the build printed it — minutes apart, the
same as the dated-pages line. A log found shorter than its offset (rotated
mid-run) is read whole, so an older night's findings are noted again; the
record has always had the same edge.

The sentence's apostrophe changed with it: the mac wrote `course's`, while
`activityTrail.mustRecord` → "folder problem found" → `carries` and Windows'
`TrailSentence` both say `course’s`. The mac is the one that moved;
`testTheTrailSentenceIsTheContractsOwn` reads the example out of `carries`.
Older trail files keep the straight form, which nothing parses.

**Rejected:** (a) writing the line in `takeFolderProblems`, when the section is
opened — Windows' shape (`ScheduledHealthFindings.Take`, dated to the record's
write time). On the mac it would date nothing better and leave NO line for a
teacher who never opens that section: the argument
`scheduledPublishStopped.trail` already won. (b) #84's per-run capture of the
output in place of the byte offset — launchd owns the child's stdout, so a
capture means either a pipe that must be drained (the thing that wedged the
Windows assistant's server) or a change to the generated agent, which reaches
only jobs scheduled after an upgrade; the offset is tested, handles rotation,
and the dated-pages reader shares its text. The log split is on scalars now
(`linesOf`) — hardening only, since launchd hands the child a plain file and
the launchers ask for a terminal only when they have one, so the log has
`\n` endings today.

### Offering to put it right

Two of the five findings are repairable — a missing `Media` folder and a missing
section front page — and three are NOT. The line is the whole design: **a fix
must restore the FEATURE, not merely satisfy the check.** Recreating an empty
curriculum folder would silence "the curriculum map could not be built" and
leave the map missing, because that folder only counts once it holds a page
named for an expectation code. A button that makes a warning go away without
fixing anything is worse than none, since the teacher then believes it is dealt
with.

**Decide from the check's NAME, not from `fixable` alone.** The flag in the
payload means "this kind of thing is repairable"; what has to be true before an app
show a button is that YOUR app has a repair for it.

Three things the mac had to learn the hard way, all worth copying:

- **Never overwrite.** Both repairs check first, so pressing twice — or pressing
  after fixing it in Obsidian — changes nothing. The test that matters writes a
  teacher's own front page first and asserts it survives.
- **Report the outcome, including failure.** Both restores can fail (a read-only
  volume, a file sitting where the folder should be). Reporting only success
  made a failed repair indistinguishable from a successful one — the dialog just
  closed either way, which is silence on the failure path in the feature written
  to end silence.
- **Say what has not changed yet, and offer the RIGHT next step.** The folder is
  back on disk; the preview still shows how things were. A teacher who is told
  "put the Media folder back" will go and look at their site next. Offer the
  preview on BOTH occasions — including after a publish, because that is how a
  teacher checks the repair worked. What changes is the SENTENCE: after a
  publish it must name who is still seeing the old site (students) and what
  changes that (publishing again).

  This reversed an earlier decision, and the reasoning is the useful part. The
  preview was withheld after a publish on the grounds that it does not change
  what students see. True, and beside the point: withholding it removed
  something useful in order to prevent a misunderstanding that the words already
  prevent.

  Three things that fell out of widening the offer, all of which apply to both apps:

  - **The publish sentence must not assert a past publish.** It is shown after a
    FAILED deploy too, and for a section publishing for the first time nothing
    has ever gone out. Say what publishing WILL do, not what it did.
  - **Guard the preview against every publisher, not just the app's own button.** On
    the mac the assistant publishes the same section in the same process,
    invisible to the view's own deploy runner; the guard had to move to
    `CourseActivity`. While publish-origin findings offered no button this was
    unreachable — widening the offer is what made it a hazard.
  - **A preview build is never deploy-fresh** (`app-rules.json` →
    `buildFreshness`), so previewing after a successful publish means the next
    publish rebuilds. Correct, and largely moot: the repair puts content back,
    which forces a rebuild anyway.

  **Call the button "Preview Again", not "Build Again".** Russell asked what
  "Build Again" meant, which was the answer: the label never said WHAT would be
  built, and the thing on offer already has a name the teacher knows. Note this
  is a CLARITY point, not a rule 1 one — "build" is ordinary vocabulary in this
  product ("Click Preview to build this section's website") and does not need
  hunting down elsewhere.

One mac-specific mechanic that may not have a counterpart elsewhere: a view presents one
alert at a time, so the outcome is shown from a state change AFTER the first
dialog has gone rather than raised inside its button action — asking for a second
while the first is dismissing loses one of them, and the one lost is the report
the teacher just asked for.

`FolderProblemRepaired` is a separate trail event from `FolderProblemFound`, on
purpose: one records that something is wrong, the other that somebody acted on
it, and a trail that could not tell them apart leaves "did they ever fix it?"
unanswerable. Both are in `contracts/shared-rules.json` → `activityTrail`, and
the repair rules themselves are in `siteHealth.repair`.


## The curriculum coverage maps: one per curriculum folder (#128)

Until #128 a course had ONE coverage map, built from ONE folder, and its
expectation pages had to be named like `A1.1`. A course keeping both an
`Ontario Curriculum` and a `College Board Curriculum` folder (every LCS course
has both) got a map from Ontario only, while Course Settings and "Folders
Plantoir uses" named College Board — and College Board's pages, named `1.A`,
were never expectations to the build at all (#90, measured on this Mac
2026-09-06). Now every curriculum folder the course DECLARES that holds an
expectation page has a map of its own.

**Which folders.** `configured_curriculum_folders(config)`: the new list key
`curriculum_folders`, in the course's own order, then the legacy
`curriculum_folder` if it is not already there (non-strings, empties,
path-like names and repeats in any letter case dropped). `_find_curriculum_folders`
keeps every declared folder that holds at least one expectation page — found
in any letter case, the ON-DISK spelling kept — in declared order. Only when no
declared folder holds a page does the old scan run, and it still gives exactly
ONE folder: the alphabetically first top-level folder whose name mentions
"curriculum" and holds a LETTER-FIRST page (`A1.1`, the only shape before this
piece), and only if there is none, the first holding any expectation page.
That preference is the fix for the implementation review's finding 1,
measured: with the widened code rule and a plain alphabetical scan, a scratch
LCS course whose `College Board Curriculum` held `1.A` pages had Ontario's map
silently replaced by College Board's under the same title, because `College`
sorts before `Ontario`. A golden (Ontario with pages, College Board with `1.A`
pages, nothing declared) holds it byte for byte to what 92a7099a built. The scan is a FALLBACK, never additive:
Russell's ruling on the plan. A course made from scratch declares nothing, so
the scan is still its real path, and its site is unchanged. The whole rule is
`contracts/shared-rules.json` → `specialNames.curriculumFoldersResolution`,
run against the build by `scripts/test_coverage_maps.py` and against the apps
by their contract suites.

**Titles.** The PRIMARY folder's map — the first declared name, or the one
folder the scan found — is always `Curriculum Coverage`; every other map is
`<Folder> Coverage`, and a title that would repeat another gets ` (2)`
(`curriculumRules.coveragePageTitles`). So a course with one map keeps the page,
its address and every link to it, byte for byte (the goldens in
`test_coverage_maps.py` were captured from origin/dev 92a7099a before any edit:
a `Curriculum/` course and the LCS default, Ontario with pages and College
Board empty), and a course that declares a second folder later gets a SECOND
page rather than two renamed ones. Only a non-primary title is written quoted
in the page's frontmatter, because a folder's name can carry a colon.

**The code rule** (`is_expectation_code`, `fullmatch`) admits three shapes:
letter, digits, dot, digits (`A1.1`, `b2.3`); digits, dot, ONE letter (`1.A`,
a College Board skill); and two to four CAPITAL letters, a hyphen, digits, a
dot, one capital letter (`CRD-1.A`, `AAP-2.B`, a College Board learning
objective — added for Russell's marketing course). Still refused: `12.3`,
`B2`, `A1. Heading`, `1.A.1` and `CRD-1.A.1`. Measured before widening: 2,842
curriculum pages ship under `support/` (39 payloads, 50 skeleton families —
2,214 codes, 494 overall headings, 89 indexes and a handful of about-pages),
zero lower-case codes, zero digit-first or hyphenated stems, zero subfolders —
and none of them changes classification. The build had DISAGREED with the
contract about `b2.3` (its regex was upper-case only) since the contract was
written, because nothing ran the contract's cases against the build; the new
test does.

**Order and columns.** `code_sort_key`: letter-first codes, then skills, then
learning objectives by prefix, number and letter; `strand_of` gives the column
— the upper-cased letter (so `b2.3` joins B), the skill number, or the
learning-objective prefix (`CRD`). Only letter-first strands have overall
expectations and chips; a map with none leaves out the chip sentence, the
"Overall expectations with no assessed work" row and the chip part of the
notes, and an empty chips `div` is never written. The old sort key read
`int(code.split(".")[0][1:])`, which is `int("")` for `1.A`: widening the rule
without replacing it would have stopped every such build with a traceback.
The same `overall_of` decides what an overall expectation's page lists under
"When did we do this?": every page that links it or any of its specific
expectations in the same folder (#505, `documentation/06-quartz-customizations.md`
→ D1).

**Nested pages and repeats.** Pages are collected RECURSIVELY, shallowest
first then by path — a plain path sort puts `(old)/A1.1` and `2019 version/A1.1`
ahead of the top-level `A1.1` (measured), and the map would point at the
archive. A code met twice in one folder is one cell, the first page kept, with
one console line naming it (`⚠️  College Board Curriculum has two pages called
1.A — the map uses Unit 1/1.A`). Recursion changes nothing for shipped content
(no subfolders) but does change a single-map course whose teacher keeps
subfolders inside the curriculum folder: their nested pages now count.

**Counting.** A page in ANY mapped folder never counts, and neither does any
map page: a College Board page that transcludes `![[A1.1]]` is curriculum
material, not a lesson that addressed Ontario's A1.1. A link finds its
expectation in any letter case, as Obsidian and Quartz resolve it. The
"taught" crawl is done once per build for every map.

**Everywhere else a title was a literal.** Key Links gets each map directly
under the bullet pointing into its folder (the "…curriculum expectations]]"
wording fallback applies only with one map); the Backlinks panel skips every
title and every mapped folder, in both spellings; the sidebar hides every
map's file (and `Curriculum Coverage.md` always); class-page detection and both
date passes ask `_is_coverage_page_name`, fed by `set_coverage_titles` (the
`set_unit_word` pattern: one build is one process). `handWrittenCoveragePage`
names the colliding title through `{page}`.

**The trail.** Every build whose section wants the map prints
`PLANTOIR_MAPS: {"course", "section", "maps": [{title, folder, expectations}]}`
— an empty list included, because "my College Board map is missing" is the
question it answers (`coverageMapsBuilt`). The mac reads it from the console
(`ScriptRunner`) and from a scheduled publish's log
(`ScheduledDeploy.recordFolderProblems`) and writes `curriculum maps built`.
Nothing is printed when the map is switched off for the section. And since
this piece, the mac keeps EVERY line carrying `PLANTOIR_` + capitals and a
colon out of the console by one rule (`BuildMarkerLine`,
`transcriptStripping.machineLines`), so the next marker cannot reach a
teacher as raw JSON the way `PLANTOIR_DATED:` still does on Windows (#279).

**Setup.** `setup_course.py` writes `curriculum_folders` (the manifest's one
folder) for a course with nothing recorded, keeps a saved list exactly, and
writes the list's FIRST (primary) folder in the legacy `curriculum_folder` as
well — Russell's ruling on the implementation review: an older Plantoir on a
second Mac reads only that key, and a primary folder renamed to something
without "curriculum" in it would otherwise leave that Mac publishing no map.
Both apps and the renamer do the same whenever they write the list. Setup used
to write `curriculum_folder` from the manifest unconditionally, and because the saved-keys merge only restores keys
the fresh dict lacks, a re-run put `Curriculum` (or null) back over a name a
rename had recorded — `test_setup_curriculum_folders.py` is the must-fail.
Manifests keep their singular key: 89 of 89 declare exactly one folder.

**The apps** protect and name from the same rule, reading the course's
SHARED folders on disk for expectation pages
(`CurriculumFolderRule.foldersWithPages`): while the map is on only the LAST
folder with a map is refused, the others ask first
(`removeCurriculumFolderWithItsMapConfirmation`), and a folder with no pages is
an ordinary folder — on the LCS default, Ontario (which holds the map) is the
one refused, where the by-name rule used to protect the empty College Board.
While no folder holds a page they fall back to the single by-name folder, so
an empty new course is protected exactly as before. Both apps OFFER to declare
a folder whose name mentions "curriculum" under "Curriculum folders"
(`curriculumFoldersOffer`); the map folders are shown ticked, then every
declared folder (so a folder ticked before its first page stays ticked), and
the first tick never drops the map the scan found. A rename of any of them materialises
`curriculum_folders`, with the new name in the old one's place.

**Rejected, so nobody re-proposes them.**
- Turning `curriculum_folder` into string-or-list: every reader branches on
  type forever, and an old reader handed a list builds a path out of it. A new
  key is ignored cleanly by old readers, and both apps keep unknown keys.
- An array in manifests: no manifest has two folders.
- A by-name ADDITIVE scan (the plan's first design): a teacher keeping
  `Ontario Curriculum (2008)` beside the revised curriculum would get a second,
  overlapping map — and, before the primary-title ruling, the real map renamed.
  An overlap rule ("skip a folder whose codes repeat another map's") is not
  safe either: a split-grade ICS3U/ICS4U course legitimately has `A1.1` in both.
- `<Folder> Coverage` for every map, and `Curriculum Coverage` for whichever map
  sorts first: both rename existing pages.
- A per-map switch: one switch covers every map; a teacher who wants one map
  fewer unticks the folder.
- Bulk-migrating existing configs, and dropping the legacy key's READ.
- A health finding for "a curriculum folder with no pages": every LCS course
  not teaching AP would be nagged on day one.
- `1.A.1`/`CRD-1.A.1` (essential knowledge): not measured on a real course.

**Known limits.** A code in two folders counts on both maps (matching is by
page name). (This used to say the assistant recognised curriculum pages only
by a folder name mentioning "curriculum"; since #614 it reads the declared
folders too, so a declared `AP CSP` folder's pages are offered and protected —
`10-local-ai-assistant.md` → "A curriculum folder is the one the course
declares, or one named for it (#614)".) Russell's own
College Board layout was not measured (the working folders are his); the two
read-only commands for him are in the #128 hand-over.

**Adding a second curriculum.** Nothing ships the College Board's pages — the
framework's text is the teacher's to bring. A teacher makes the folder
(`College Board Curriculum`), ticks it under Course Settings → "Curriculum
folders", and asks Revise With ▸ Claude… to draft one page per code from the
framework they have; the next build draws its map.


## Printable pages: what the build does (#454, v1.6.0)

The site side is [06 → F](06-quartz-customizations.md#f-additions-installed-every-build-printable-pages-454-v200);
the build's share is four steps, all in the ALWAYS section so every existing
section picks them up on its next build:

1. **`install_quartz_additions`** (beside `install_patched_backlinks`) copies
   `support/quartz/**` into the section's Quartz copy where the bytes differ.
   Read only from `SUPPORT_DIR`, so verify.sh's `check_baked` proves the image.
2. **`_resolve_print_settings_of_pages`**, after the How I Teach sweep and
   BEFORE the folder checks, reads every processed page's `printable` and
   `printPdf` with python-frontmatter. A `printPdf` that resolves against the
   course's Media folder (`page_features.resolve_print_pdf`, by the folder's
   own listing, without regard to capitals) is rewritten to the folder's
   spelling; one that does not is taken off the build's copy and becomes a
   `printPdfNotFound` fact, so the folder check says it where every folder
   problem is said (review S3 — a console line is where a teacher using the
   app never looks). It never refuses a build: one attachment must not stop a
   site, and refusing would break the preview the teacher is using to fix it.
   It also counts the pages that need the print engine.
3. **`page_features.install_gated_assets`** puts `/opt/vendor/pagedjs` into the
   section's `quartz/static` when that count is above zero, and takes it out
   when it is zero (one plain line: "This site carries the print layout for 2
   pages.").
4. **`print_settings.write`** writes `quartz/plantoir_print.json` (the corners
   from the course's `print_*` settings, the words, the rules), then
   **`wire_quartz_additions`** makes its two marker edits — after every other
   edit to `quartz.layout.ts`, so nothing rewrites the wrapped line. A stale
   contract makes step 4 print a warning, never stop the build.

The PDF itself needs no copying: Quartz's Assets emitter already copies every
non-page file in `content/` (Media included, through the build's link to it)
to the site at Quartz's slug of its path. Measured on a real course: 179 PDFs
under `Media/`, `&` and spaces included, at exactly that slug.

**Compatibility:** none of this changes a page that does not opt in — verify.sh
plants one and checks it (06 → F, "Compatibility").

## Diagrams and graphs: what the build does (#485 E1, v1.7.0)

A teacher writes ` ```tikz ` (a LaTeX TikZ picture, as the Obsidian TikZJax
plugin reads it) or ` ```functionplot ` (a graph of y = f(x), in
obsidian-functionplot 1.2.1's syntax). **Python prepares and Quartz
places**: `scripts/figures.py` does everything that can fail, and the site's
transformer (06 → G) only reads what it left. Not inside Quartz, because a
figure that cannot be drawn must reach the teacher as a folder problem and a
preview build never returns; the cache and the clock are Python's; and this
file runs on Windows, where every `scripts/test_*.py` runs. The rules and
cases: `contracts/shared-rules.json` → `figureFences`.

1. **When.** ALWAYS section, straight after the printable pages' scan and
   BEFORE the folder checks (`_prepare_figures` in `build_site.py`), so a
   failure is said where every folder problem is said. It never stops a
   build: if the pass itself fails, the fences stay plain code on the site
   and the build says so in one line.
2. **Which pages.** `figures.pages_students_see`: every processed page the
   gate's own rule (`_is_draft`) shows, outside Media. The fence is the
   opt-in — no page setting, no course switch.
3. **Finding fences.** `markdown_code.fenced_blocks`: the #313 fence rule
   (any quote depth, list items, backticks or tildes), run after every `%%`
   comment is removed as Quartz removes it. The language is the info
   string's first word, exactly.
4. **Keys and the cache.** A figure is named by SHA-256 of its *tidied*
   fence (obsidian-tikzjax's own tidying: drop `&nbsp;`, trim each line with
   JavaScript's trim set, drop empty lines). The cache is
   `<course's builds folder>/.figure-cache/<engine id>/<engine>-<key>.json`
   — shared by sections, outside the teacher's folder, kept when the website
   builder is remade. The **engine id** is SHA-256 over the lockfile, the
   helper, `figureRules.js` and function-plot.js, so a changed engine empties
   the cache by itself (review S3: a hand-bumped version string missed svgo
   moving under the lockfile). Entries unused for 90 days are pruned;
   `--full-rebuild` clears this engine's. Writes go to a temporary file and
   are moved into place, and a missing or half-written entry is a miss
   (review S7: previewing one section while publishing another is the
   supported way of working). Windows refuses that move onto a file another
   build has open or is replacing at the same moment; the entry is then
   simply not cached (another writer has stored the same key) and the
   writer removes its own temporary file rather than leaving it beside the
   entry (2026-10-15; retrying was rejected, since it adds build time to store
   what is already stored). A build whose figures are all cached never
   starts Node: "📐 Drew 0 diagrams (12 from before)".
5. **The helper.** `support/figures/plantoir-figures.mjs`, one process per
   build, JSON lines each way (protocol at the top of the file). It says
   `ready` once it can take work; TeX's engine is loaded only before the
   first diagram (`{"load": "tikz"}`, 474 ms measured), so a build of graphs
   alone never pays for it (review N1). Python keeps the clock on a reader
   thread (no `select`, so it works on Windows): **120 s to start, then 20 s
   per diagram** — 25 times the slowest measured (pgfplots, 842 ms). A
   diagram past its 20 s is ended by killing the helper, which is started
   again for the rest; it is `tookTooLong` and NOT cached, so the next build
   tries again (review S5 — a slow moment must not become a permanent
   failure). `\def\x{\x}\x` loops for ever and says nothing, measured;
   that is the case the clock exists for.
6. **What is answered.** TikZ: the SVG, or the reason from TeX's console —
   the first `! ` line, and `l.N`, which is the tidied fence's line N − 1
   (node-tikzjax puts a one-line preamble in front; measured), mapped back
   through the tidying to the fence's line and then, by re-finding the same
   fence in the teacher's own file (`remember_vault_source`), to the line in
   their file. Reasons: `undefinedCommand`, `missingPackage`,
   `missingDocument`, `documentClassNotNeeded` (an Overleaf paste — the line
   is NOT removed, so Obsidian and the site still agree; review S6),
   `texSaid`, `tookTooLong`, `engineMissing`. functionplot: the 1.2.1 parse,
   then each function tried at three points with function-plot's own
   evaluator (a name it does not know is only found by evaluating) and
   sampled at 51 points across the bounds (`sin x` is NaN everywhere and
   would draw nothing); `log(x, 2)` is refused from the text, because the
   evaluator silently drops the base (review S2).
7. **What the site gets.** `quartz/plantoir-figures/manifest.json` (the
   site's words from the contract, and per figure: drawn or not, its
   description, the SVG's file or the graph's settings) and one `<key>.svg`
   per drawing. No figures: no folder, and the transformer leaves every page
   exactly as it was. `static/tikz/` holds exactly the faces the drawings
   name, `fonts.css` and the BaKoMa `LICENCE` (three faces, 87,840 bytes, on
   the verify fixture); `static/function-plot/` rides the #454 gate
   (`page_features.GATED_ASSETS`), counted by pages with a graph that CAN be
   drawn, with its own words in the build's output (review S9).
8. **What the teacher and an assistant are told.** One folder problem per
   section build, `figuresCouldNotBeDrawn` (page, figure, line, reason; at
   most ten named), surfaced by both apps and recorded on the trail as the
   existing "found a problem with this course's folders" — **no new trail
   event**: the app does nothing new a teacher can see. And one line per
   figure for an assistant (issue #485 §7.5):
   `plantoir: error: Units/Similar Triangles.md: tikz block 2, line 14: …`;
   a drawing with no `% alt:` and a graph setting nobody reads are
   `plantoir: note:` lines only (ruling E1-3).
   (`quizzesNotReady`, #563, is reported the same way: see "Self-check
   quizzes: what the build does".)

**Measured** (M4 Pro, Colima at 6 CPUs, the dev-test image, Node 20.20.2):
the verify fixture's first build drew its 7 distinct diagrams and checked 5
graphs; the scratch EXC2O build took 5.3 s with them drawn and 2.9 s with
all of them cached. Single diagrams: triangles 74 ms, a TeX error 19–43 ms,
circuitikz 664 ms, pgfplots 842 ms.

**Measured on Windows** (#503, 2026-10-15; i5-8365U, 16 GB, Windows 11 Pro
26200, the native runtime, Node 20.18.1, `preview.ps1 --build-only` of a fresh
section whose one page has three diagrams, a graph and `printable: true`):
**19.2 s** for the first build and **5.7 s** for the second, every figure from
the cache; the engine's load 1.4–1.8 s (1.6 s the first time after it was
fetched), the contract's triangle 0.33–0.45 s; a diagram that never ends
stopped at its 20-second clock and the next one drawn, both in 23.5 s. The
first build is mostly the new section's Quartz scaffold, not TeX (18.6 s with
one diagram). The rest, and what was checked in the browser:
[12 → Diagrams and graphs](12-windows-app.md#diagrams-and-graphs-485-e1-v170-the-runtime-carries-the-engines-503).

**The live-preview edge.** The preview's live reload re-reads `content/`,
not the teacher's vault, so a fence edited in Obsidian reaches the site on
the next Preview, which runs this pass again. A fence Quartz sees with no
manifest entry says it could not be drawn — never "appears once previewed",
which would stay on the page for ever if the build simply could not see the
fence (review S1 found exactly that for a fence opened on a list marker's
line, which the build now reads). `words.site.graphNeedsPreview` is only for
a site whose graph engine is missing in the reader's browser.

**Known limit, deliberately not reported as a folder problem.** The build
finds fences with the toolchain's own fence rule, not a full Markdown parser,
so a few shapes the site's parser reads differently still slip past it
(measured by the fix review): a nested list marker (`- - ```tikz`), a fence
whose content is less indented than the marker's text (lazy lines), a
numbered fence straight after a paragraph line, a closing fence at column 0
under a bullet. Each shows students "couldn't be drawn" (or turns the next
figure into plain code), and Obsidian shows the same shapes broken too.
(Since #455 the fence reader OPENS the nested-marker block as the site does,
marked `nested`, so the fences after it are read alike; figures still leave
the nested one itself undrawn, as before — runnable code's review S2.) Not
raised as a finding because the only place that knows is Quartz's own
parse, after the folder checks have been said; a post-build scan for a
failed figure with no manifest failure would do it and is the way to add it
if a teacher ever meets one. Fences in a list item opened on the marker's
line and indented with tabs (Obsidian's default) ARE read, since the E1
reviews.

**Rejected:** rendering inside Quartz (no way to stop a build-long wait or
reach the folder checks); raw `<svg>` in the processed Markdown (`ofm.ts`
rewrites raw text, and the drawing's single glyphs flooded the page's
description); SVGs as `<img>` (no page fonts and no theme colours); a cache
in the teacher's vault; a `math_engines.json` switch (the fence is the
opt-in); stopping the build on a figure (`--strict`).

## Runnable code: what the build does (#455, v1.8.0)

A page that says `codeRunner: true` turns its ` ```python run ` blocks into
programs students edit and run in their browser; the site's half is
[06 → I](06-quartz-customizations.md#i-runnable-code-455-v180), the rules
`contracts/shared-rules.json` → `codeRunnerBlocks`. The build's share is the
#454 gate again, plus one file, all in the ALWAYS section:

1. **Counting** (`_count_runner_pages`, straight after `_prepare_figures`):
   the same pages figures read (`figures.pages_students_see` — the gate's own
   visibility rule, outside Media), each read with python-frontmatter after
   `process_frontmatter` has written it back (so `codeRunner: yes` is
   `true`), and `page_features.runner_engines_on_page` asks two things: does
   the page opt in, and does it hold a runnable block of a language in the
   table (`page_features.runner_fences`, over `markdown_code.fenced_blocks`,
   the #313 fence rule)? A page that opts in with no runnable block counts for
   nothing (#455 Q1, 2026-10-17: with two languages the key alone cannot say
   which engine to carry; the price is the known limit below). page_features
   never imports frontmatter, so its test still runs on Windows.
2. **The gate.** The counts join print's and graphs' in
   `page_features.install_gated_assets`, which since #455 takes a LIST of
   sources per engine, later winning file by file: `VENDOR_DIR/<engine>` (the
   five pinned Pyodide files and the README, see 02) and
   `SUPPORT_DIR/gated/<engine>` (`plantoir-worker.js`, the page's thread). One
   sync, not a copy after it: a copy after the sync would be deleted as an
   extra and copied again on every build. The vendor folder IS the engine: an
   overlay alone installs nothing and says so ("…this copy of Plantoir is
   missing what runs it, so students will see the code without a Run
   button.") - except for a `prebuilt` language (Swift, #493), whose overlay
   is all its engine is (`page_features.OVERLAY_IS_THE_ENGINE`; below). The carried line: "▶️ This site carries what runs Python for 3
   pages." No engine with no runnable block: verify.sh 6c checks
   `static/pyodide` leaves with the last one.
3. **The words file** (`page_features.write_runner_words`, straight after the
   gate): `quartz/plantoir_code_runner.json` holds the words and limits from
   the contract and **the engines the gate actually installed**. The page's
   script bundles it (esbuild); the transformer reads it with `fs` at build
   time, and leaves any runnable block whose engine is NOT carried as the
   plain code it was, with one line an assistant reads:
   `plantoir: error: Units/Loops.md: python block 2: ` +
   `codeRunnerBlocks.words.blockNotPrepared` (siteDisagrees, review S2). So a
   block the build did not count can never become a Run button that says
   "isn't on this site yet" to students for ever. No line for a page students
   cannot see: Quartz parses those too and drops them later (the transformer
   applies `patches/publish.ts`'s own test). Since #567 the same blocks are
   also ONE folder problem, said from the site's build — "The safety net
   becomes a folder problem" below.
4. **The KaTeX copy** (#494, `install_katex_assets`, beside the gate, EVERY
   site): Quartz's own `node_modules/katex` — `dist/katex.min.css`,
   `dist/contrib/copy-tex.min.js`, the 20 woff2 faces and `LICENSE` — into
   `quartz/static/katex`, same-bytes skip, extras removed, a missing package
   one line. Its patch to latex.ts (`patch_katex_local`, beside
   `patch_katex_mhchem`) is 06 → C2-26.

**The live-preview edge.** The preview's own rebuilds (a page edited while
it serves) do not run the gate or rewrite the words file. A page that gains
`codeRunner: true` or its first runnable block while a preview is ALREADY
running therefore shows its blocks as plain code, with the `plantoir: error:`
line in the preview's output, until the next Preview — never a Run button
that cannot work. A page that already had runnable code keeps working. Such
a block is NOT a folder problem: the site says its folder problem on the
preview's first build only (#567, below).

**Known limit.** The build counts runnable blocks with the toolchain's fence
rule, not Quartz's parser. Every shape the reviews measured is now read alike
(`codeRunnerBlocks.fences.pageShapes`, checked through both readers in the
image by `check_runner_rules_against_the_site.py`); a fence opened after a
second container on a list marker's line (`- - ```python run`) is runnable on
NEITHER side; a lazy line in a list item gives both sides one runner but
different bodies (the site's is the one that runs). A shape nobody has
measured that the two read differently shows as plain code with the
`plantoir: error:` line above — the safety net — and, since #567, as the
`runnableCodeShownAsPlainCode` folder problem, said from the site's build
because only Quartz's parse knows, after the folder checks have been said.

**Rejected:** a course-level switch (Russell, 2026-10-05: per page only); the
key alone deciding (above); downloading Pyodide when a site is built (a build
would need the network); copying the worker into `/opt/vendor` (it would
need its own line in both runtimes) or into every site's `static/` (a site
without runnable code would carry it).

### The safety net becomes a folder problem (#567, v1.9.0)

A teacher previewing in the app never reads the build's console, so the
safety net's `plantoir: error:` line above told an assistant and nobody
else. Since #567 the same blocks are one folder problem,
`siteHealth.checks` → `runnableCodeShownAsPlainCode`, with the dialog, the
assistant's answer and the trail line every other folder problem gets. It is
one of the TWO checks said from the site's build rather than before it
(`siteHealth.whereItRuns`; the other is the quiz safety net's, #644, in the
next section, said by the same emitter in the same call), and that is the
whole design:

1. **The transformer records.** `codeRunner.ts`, in the branch that prints
   the line (and only for a page students can see), also pushes
   `{page, language, block, reason, code}` onto the page's
   `file.data.plantoirSiteDisagreements` — the page's path in the site with
   `.md`, the fence, the block's number among that language's blocks, the
   reason's KEY (`blockAfterUnclosedFence`, `blockNotCompiled` or
   `blockNotPrepared`, the same choice the line makes) and the code the site
   read. The line itself is byte for byte what it was.
2. **An emitter gathers.** `support/quartz/plugins/emitters/plantoirSiteSaid.ts`
   (exported and put before `Plugin.Assets()` by `_wire_emitters_index` and
   `_wire_site_said_emitter`, each with its own idempotency check, so a
   section wired for My Progress before #567 gets it) writes no file. On its
   FIRST emit in the process it gathers every page's blocks, pages in
   path order (NFC), and — only when there are any — runs the build's own
   Python with `execFileSync(python, [site_said.py], {input, timeout: 20 s,
   windowsHide: true})`, the data on stdin, and passes what it prints to
   stdout. A failure of any kind is one `ℹ️` line; the site is never at risk.
   Every emitter finishes before Quartz says it is done, so the marker is in
   the output before a preview's server answers.
3. **Python words it.** `scripts/site_said.py` puts its own folder on
   `sys.path` first (the #358 trap: Windows' embeddable Python replaces
   `sys.path`, and `site_health.py` has no entry point of its own), maps each
   path to the page's place in the course folder, finds `{line}` in the
   teacher's own file by the code the site read (ONE opening ```` ``` ```` of
   that language with `run` whose following lines hold it; none or several →
   `blockLineNoLine`), leaves out every Swift block `swiftCouldNotBePrepared`
   already names (one block, one finding), and builds ONLY this finding —
   `site_health.site_disagreements_finding`, then `site_health.announce([it])`
   in its own `try`. Never `announce_or_stay_quiet`: with no folder facts it
   says "the Media folder is not there" and "no front page" falsely (plan
   review, MUST 1). It reads and writes UTF-8 whatever the console's code
   page, and always exits 0.
4. **The side file.** `site_said.write_side_file`, in the ALWAYS section
   straight after the runner's words, writes `quartz/plantoir_site_said.json`:
   `sys.executable`, the script's path, the course and section, the content
   folder, `places` (every opted-in page students can see: its place and the
   teacher's file it came from) and `swiftNamed`. Same input, same bytes. NOT
   `plantoir_code_runner.json`: the page's script bundles that one, and the
   build machine's paths must never reach students (a test pins it).

**Once per process.** Quartz 4.5.0 calls an emitter again, with every page,
on each live rebuild. The emitter marks `globalThis` on its first emit and
says nothing after, so a preview's later rebuilds keep only their
`plantoir: error:` lines (Russell's ruling 2): re-announcing would bring the
dialog up mid-edit, and the two apps deduplicate a CHANGED finding
differently (the mac appends it, Windows drops it by `Identity`).

**Measured.** The call costs **24-31 ms** in the image (the planner's three
timings of the Python start: 35, 26 and 24 ms; the plan review's 24-31 ms;
28 ms for the whole first emit in verify.sh's run of
`check_runner_rules_against_the_site.py` in the image, 2026-10-23),
**41-43 ms** on the mac host (M-series, Homebrew Python 3.14, the whole emit
through `check_runner_rules_against_the_site.py`), and nothing on a site
where no block disagrees, which is every site that is fine. For Python the
net fires only when the site carries no Python engine at all (a carried
engine wraps a block the build did not count as a WORKING block); for Swift
it fires per block whose key is not in `plantoir-runners/swift.json` — which
is why verify.sh's end-to-end fixture (Plain Code Fixture) is a Swift block
after a list fence left open. **On Windows the call took 180-470 ms** over 16
runs under load (i5-8365U), and the first check there found the finding's
611-character machine line split in two by the pseudo console's then
400-column screen, so no dialog and no trail line: the app's launcher runs
have a wider screen since #662 (`documentation/12-windows-app.md` → "How wide
the console is, and why"). A one-block finding is 531-611 characters; ten
blocks or more (the most it names) about 2,300.

**Rejected:** a Python pass after Quartz (a preview is one
`quartz build --serve` process that never returns, so it would never run —
My Progress's #545 rejection again); Python's public-sync watcher thread
reading a file the site writes (it polls once a second, racing the server
start the preview and the assistant wait on; reasoned, not measured);
the emitter wording the finding itself from words Python prepared (#485's
"Python prepares, Quartz places" shape — a second implementation of a
finding's assembly, testable only by verify.sh on the mac); Python
predicting the shapes with a reader of its own (it guesses at the site's
parse and misses the shapes nobody measured, which is why the net exists);
reusing My Progress's emitter (a different feature with its own switch and
its own early returns, which would put this finding behind them); one
marker per page or block (both apps key a finding on name, course and
section, #246); piping node's output through Python to catch the line (it
would change the terminal the app's progress markers come through); and
reusing `words.blockNotPrepared`'s words in the dialog ("if this line comes
back" has no line there — the check has `reasons` of its own).

### …and the quiz safety net (#644, v1.9.0)

The self-check quizzes have a safety net of their own (below, "The safety
net", `quizCallouts.safetyNet`): where the site and the folder check read a
question differently, the site prints `plantoir: error: <page>: <where>:
<readDifferently>`. Like the code runner's line, a teacher previewing in the
app never saw it. Worse, in the direction that matters the teacher was told
NOTHING: the site shows a short note in place of Check, and
`quizzesNotReady`, worked out before the site exists, has nothing to say,
because the folder check found nothing wrong. Since #644 those lines are a
second site-said folder problem, `siteHealth.checks` →
`quizzesReadDifferently`, on #567's path with no new reader:

1. **The transformer records what it prints.** `plantoirQuizzes.ts`'s
   `sayDisagreement` pushes `{page, n, line, reason, problem?, fill?}` onto
   `file.data.plantoirQuizDisagreements` inside the branch that prints, so
   there is exactly one record per line, and a site without its words
   prints nothing and records nothing. The printed line is byte for byte
   what it was. The four places it is called give the four `reasons` keys:
   `shownWithNote` (a quiz the site shows as not ready that the check
   passed, carrying the problem the SITE found and its values, never an
   assumed `choicesInHtml`), `shownWorking` (the other way round),
   `countedDifferently` (the top-level counts differ) and
   `nestedReadDifferently` (only the quizzes inside a list or callout
   differ, or their problems do). `line` is the one the folder check already
   wrote into `plantoir_quiz_pages.json`: `lines[n-1]`, the first of
   `lines`, or the first of `nestedLines`. Python never looks a line up
   again, unlike #567's blocks.
2. **One emitter, one call.** `plantoirSiteSaid.ts` gathers both lists
   (`gathered` and `gatheredQuizzes`, the same rule: NFC, pages in path
   order, hidden pages left out) and makes ONE `execFileSync` when either is
   non-empty, with `{…, blocks, quizzes}` on stdin, the same once-mark and
   the same 20 s timeout. Its `ℹ️` failure line no longer names blocks of
   code ("Could not say what the website found: …").
3. **Python says both.** `site_said.say` builds the code's finding, then the
   quizzes' (`quiz_facts_from_site`, then
   `site_health.quizzes_read_differently_finding`), each in its own `try`,
   so one that fails costs only itself and one `ℹ️` line, and announces them
   together, the code's first. It is still never `announce_or_stay_quiet`.
4. **Places without a second scan.** `quizzes.check_pages` returns `places`,
   each EXAMINED page's place by its path in the site's content (recorded
   before the page's quizzes are read, so a page the site counts quizzes on
   and the check does not still has one). `_check_quizzes` hands them on,
   and `_write_site_said` adds `{"place", "source": None}` for each path not
   already there, so a code page keeps its `source`.

**Measured** (2026-10-23, Quartz's own ObsidianFlavoredMarkdown, GFM and
the transformer, bundled in the scratchpad over a course folder's own Quartz 4.5.0, the plan review's harness; confirmed in the image by verify.sh): `<img
alt="x>y" …>` on the line straight after the quiz's title reads as `single`
and fine to the folder check, and as `notReady` / `choicesInHtml` to the
site. That is direction `shownWithNote`, and verify.sh's end-to-end fixture
(Quiz Read Differently) uses it. With an empty `>` line on either side of
the `<img>` the two agree (`single`), which matches the advice
`words.problems.choicesInHtml` gives. An open `<pre>` straight after the
title fires the same way. The extra call costs one Python start
only when nothing else had already caused one (quizzes alone disagreeing);
when a block disagrees too, both findings ride the same start.

**Rejected:** merging into `quizzesNotReady` (both apps key a finding on
name, course and section, #246, so the two would replace each other, and
that check is said before the site exists); a second emitter or a second
call to `site_said.py` (a second Python start and a second once-mark); a
second `pages_students_see` scan to place the quiz pages (the folder check
already reads each page it examines); Python finding the lines again (the
folder check already found them, and the printed line already uses them);
assuming the site's problem is `choicesInHtml`. `shownWorking` is kept
although it contradicts `quizzesNotReady`'s own words: in that direction the
folder check over-reported, the contradiction is honest, and the finding
stays one piece per console line (director's ruling). The nested `reasons`
are swept for machinery words by `test_site_disagreements.py`, not by the
apps' sweeps, which read top-level strings only.

### Live input: what the build adds (#583, v1.8.1)

The transformer marks each runnable block that can ask for input with
`data-runner-asks="input"` (it reads input as written) or `"edit"` (a
student can edit it), from `codeRunnerRule.asksFor`. Two edits to Quartz
itself, both in the ALWAYS section and idempotent (`wire_quartz_additions`):
the preview server's `cli/handlers.js` (`PLANTOIR-ISOLATION-SERVE`) sends the
isolation headers per request, and the router's `spa.inline.ts`
(`PLANTOIR-ISOLATION-NAV`) loads a page whole across the isolation line.
Three more beside them since #628 (`PLANTOIR-SERVED-CASE`, `_wire_served_case`):
the router, the link previews and search's result previews ask for a page's lower-case address, only on
a page a Netlify publish marked (07 → "Page addresses on Netlify"). The
build itself prints no note: in preview mode Quartz builds inside its server,
after `build_site.py` could read anything, so the `plantoir: note:` line for
a runner page that keeps the box is printed by the preview's server (once per
page) and by each publish (06 → I11, 07).

## Runnable Swift: what the launcher and the build do (#493, v1.8.0)

A ` ```swift run ` block on a page that opts in runs as a small WebAssembly
program compiled AHEAD of time (Swift has no interpreter a browser can
carry), read-only: a student changes the input, not the code. The site's half
is [06 → I10](06-quartz-customizations.md#i10-swift-493); the rules are
`contracts/shared-rules.json` → `codeRunnerBlocks.swift`; the image that
compiles is [02 → The Swift image](02-docker-image.md#the-swift-image-493-v180).
Three steps, in three places, because **the build cannot compile**: it runs
inside the website builder, which has no way to start another container (a
Docker socket inside it was rejected - a container that can start
containers can do anything on the Mac).

1. **Plan** - `preview.sh`'s `prepare_runnable_swift`, just before the
   build (03 → preview.sh), runs `python3 /opt/scripts/swift_blocks.py plan
   --course=C --format=lines` inside the website builder. It reads EVERY page
   of the course as the teacher keeps it (each `.md` outside dot-folders and
   Media - not the build's merged copy, which does not exist yet), keeps the
   pages whose settings look like they opt in (generously: a quoted `"true"`
   is compiled though it does not opt in), finds their Swift blocks with the
   build's own fence reader, and writes each block the cache does not hold
   into `<builds>/<CODE>/.swift-cache/jobs/<run>/<key>.swift` - a folder of
   this run's own (review S3: two builds of one course must never share a
   job folder, or one deletes the other's job and caches a failure for a
   valid block). It prints `root=`, `cache=`, `jobs=`, `count=` lines (a
   teacher's Mac has no JSON reader the launcher can count on). It reads
   hidden pages and other sections too: that costs a compile, never a wrong
   answer.
2. **Compile** - only when there are jobs, in the Swift image (built the first
   time, after a free-space check), one `docker run --rm --network none` with
   the cache folder mounted at its own path: `compile.py` compiles the jobs in
   parallel and writes `<key>.wasm` and `<key>.json` beside the others.
3. **Prepare** - `build_site.py`'s `_prepare_runnable_swift`, ALWAYS, straight
   after the runner count: for every Swift block on a page students can see
   that opts in (the gate's own visibility rule and python-frontmatter, as the
   count), it copies the block's program into `quartz/static/swift-wasm/`
   (synced: a program no page uses any more is removed - the garbage
   collection), writes `quartz/plantoir-runners/swift.json` ({key: ok and
   file, or not ok and the reason}), and names every block without a program
   on a `plantoir: error:` line and as ONE folder problem,
   `siteHealth` → `swiftCouldNotBePrepared` (in the facts as `swift_problems`).
   It says "🦅 8 of 9 Swift programs on this site ready to run."

**The key** is the SHA-256 of the block's normalised code (trailing spaces
off, the shared indentation off, blank lines at either end dropped) - exactly
the text compiled, so a diagnostic's line maps back: the opening fence's line
in the teacher's file, plus the blank lines dropped from the top, plus the
error's line in the program. The site's transformer computes the same key
from what Quartz's parser read (`codeRunnerRule.normaliseProgram`; both
sides run `swift.cacheKey.cases`). The key never depends on the compiled
program (review S4).

**The cache** is `<builds>/<CODE>/.swift-cache/<toolchain id>/`, beside the
figure cache and like it outside the teacher's folder, shared by the course's
sections. The **toolchain id** is 16 hex of SHA-256 over the Swift image's
recipe files (`Dockerfile`, `compile.py`, `ReadLineShim.swift`,
`FlushBeforeRead.c`), which state every pin, flag and the PATH - so a moved
pin or flag compiles every block again (#493 acceptance 12, pinned by
`test_swift_blocks.py`) and nothing else does. A compile error is cached too
(an unchanged broken block is not compiled again); a compile that took longer
than 180 s is not, nor one whose wasm-opt step or readLine flush failed, nor one killed by a
signal or that failed with no diagnostics (review S3, and the implementation
review's S3, measured: under `--memory 50m` a valid block used to be cached as
a compileError with empty diagnostics, for ever; an entry an earlier
compile.py wrote that way is now a miss, so it heals). A failure that is not
the compiler's is never remembered. **Pruning** happens in prepare, and ONLY when this toolchain's
folder holds every block the site needs (review N5): an offline preview
after a recipe change would otherwise throw away the only programs that
work - and until this toolchain compiles a block, prepare SERVES the newest
older toolchain's program for the same code (the key names the code), with
one `plantoir: note:` line (`swift.notes.fromBefore`; implementation review
N2: before, the kept folder only helped a revert, and every block was "not
ready"). Then every other toolchain's folder goes, and this one's entries
unused for 90 days. `--full-rebuild` (the launcher passes it to plan) clears
cached FAILURES, so a block that did not compile is compiled again; it keeps
programs, because a key names its code and its toolchain, so a program is
never stale (`swift.cacheCases`). Building twice compiles nothing
the second time (acceptance 10; verify.sh checks the page comes out the same).

**When a block has no program**, the reason is said on a `plantoir: error:`
line per block, and in the folder problem ONCE per cause: each compile error
by its block and line, every other reason once, count first ("17 blocks on 4
pages: not made ready to run - …"; implementation review S4: a cause every
block shares was said ten times and "and 7 more";
`swiftCouldNotBePrepared.groupingCases`). The reasons
(`swift.reasons`, pinned by `swift.reasonCases`):

| Reason | When |
|---|---|
| `compileError` | Swift found an error; the line is the first error's, in the teacher's file, and the words carry the compiler's own message. The block shows its code with Run off ("This program isn't ready to run yet."). |
| `noRoom` | the launcher found less than 6 GB free for the Swift image, or the disk filled part way through getting Swift ready (`state.json` beside the cache says so; plan removes it at the start of every run). |
| `notDownloaded` | the launcher could not get Swift ready because it had no internet connection or its download was not what was pinned - on a Mac, building the Swift image (about 1.3 GB the first time; since #642 only these two causes, `mac.stateForReason`); on Windows, fetching it (about 2.3 GB) (`state.json`: `{state: notDownloaded}`); the sentence names the download, filled per platform from `swift.downloadGigabytes`, and the internet. |
| `notCompiled` | nothing recorded, and the sentence says only "preview the course again" (implementation review N1: it used to blame the internet for causes that have nothing to do with it): a compile that did not finish (killed, too slow, wasm-opt failed - none is cached, so the next preview tries again), a wait for another launcher's download that gave up, a Mac image build that failed for any other cause (#642: `state.json` then holds only `{reason: unpack}`), or no launcher ran - deploy.py's own rebuild for a different web address (`rebuild_for_production`, review N1) runs `build_site.py --build-only` INSIDE the container and uses whatever a preview compiled. |

Until v1.8.6 a fifth reason, `notOnWindows`, said Windows could not compile
Swift (#493 option (b)); it went when Windows began compiling (#570), and the
`reasonCases` now pin the same three reasons on both platforms.

**Notes, not problems.** A block whose program is over 5 MB is named on a
`plantoir: note:` line (`swift.notes.large`, implementation review S2): a
multi-argument print or `print(array)` costs about 3.4 MB, and `import
Foundation` with formatters and JSON measured 46 MB, which every student
downloads on that block's first Run. So is the count of programs served from
the previous recipe (`notes.fromBefore`). Neither is a folder problem.

The build is never stopped by any of them (#493 ruling Q1, the #485 E1
precedent): a failed build would also stop the preview the teacher needs to
fix the block. The issue's acceptance 11 ("fails the build") was ruled out
for that reason.

**On Windows** (#570, v1.8.6) there is no container, so `preview.ps1` does
the same three steps natively: the shared plan with the bundled Python, then
`scripts/swift_windows_fetch.py ensure` in place of building the image (the
swift.org Windows installer, checked and unpacked without elevation into
`%LOCALAPPDATA%\Plantoir\swift\6.4.0` the first time - about 2.3 GB
downloaded, 0.9 GB kept, with a percent line while it downloads), then
`scripts/swift_windows_compile.py`, which runs this same `compile.py`,
unchanged, with a Windows environment and limits. Prepare is the one above.
The Windows toolchain id hashes the wrapper and the fetched pins too
(`cache.toolchainIdFromOnWindows`). What is fetched, what was measured
(a full-library block takes about 50 s here, almost all wasm-opt) and where
Windows deliberately differs is in
[12 → Runnable Swift on Windows](12-windows-app.md#runnable-swift-on-windows-570-the-macs-493-v186).

**Scheduled publishes** run the same launcher (`preview.sh --build-only`), so
they compile too, and build the Swift image if a preview never did (ruling
Q4). In practice a preview has already filled the cache.

**Recorded on the trail, on both platforms** (#570 on Windows, #635 on the
mac, v1.9.0). Getting Swift ready leaves "Swift got ready on this computer"
(seconds, gigabytes downloaded) or "Swift could not be got ready" (why), from
one `PLANTOIR_SWIFT:` line (`codeRunnerBlocks.swift.windows.marker`) that the
app reads from the console and from a scheduled publish's log. On a Mac,
`preview.sh` asks for it after building the Swift image (03 → preview.sh), and
`swift_blocks.py got-ready` writes it from the build's own log
(`codeRunnerBlocks.swift.mac`, cases in `bytesCases` and `reasonCases`):

| Ending on a Mac | Line |
|---|---|
| the image was already there, or another launcher built it while this one waited, or this copy has no `support/swift` | none |
| built | `ready: true`, the build's seconds, and `downloadedBytes` |
| under 6 GB free (before anything was downloaded) | `noRoom` |
| the build lock was held for longer than 1,200 s (`windows.waitSeconds`) | `waited` |
| the build failed, and its failed step or BuildKit's summary says "no space left" (any case) or `curl: (23)` | `noRoom` |
| ... says `computed checksum did NOT match` or `.tar.gz: FAILED` (sha256sum against the pin) | `damaged` |
| ... names a curl network failure ((6), (7), (16), (18), (28), (35), (52), (55), (56), (92)), a name that could not be resolved, `dial tcp`, or a timeout | `offline` |
| any other failure: a moved pin's HTTP 404 (`curl: (22)`), a certificate curl could not check (`curl: (60)`), a crashed SDK install, a daemon error | `unpack` |

`busy` (another installation running) is Windows' alone. **The reason is read
only from the failed step's lines** (`#N ERROR`, then every `#N ` line) and the
lines of no step (the closing summary): a step that succeeded can print
anything, and apt warnings mention resolving and space. The Swift Dockerfile
carries none of the needles, so its excerpt in the summary decides nothing
(`test_swift_blocks.py` checks it).

**The bytes are the pins of the download steps that RAN.** The build prints
nothing about what it downloaded (`curl -fsSL`), so `downloadedBytes` sums
`toolchain.json` → `swiftImage.pins` `bytes` for each download step with no
`#N CACHED` line: the toolchain and SDK step is found by the SDK's URL in its
header, binaryen's by its URLs, and the architecture is the header's `case
"<arch>" in` - BuildKit prints each RUN header with its ARGs EXPANDED, so a
`$WASM_SDK_URL` needle never matches (found by the plan's review against a
real log, now `scripts/fixtures/swift-image-build/cached.log`), and it numbers
steps in the order it reaches them, so CACHED is matched by number. First
build on Apple silicon: 1,300,864,747 B ("1.3 GB"); Intel: 1,326,607,137 B.
**Measured, why the CACHED case matters:** this Mac's four
`teaching-quartz-swift:src-*` images (2026-10-17) share their first seven
layers and differ only in the `COPY compile.py …` layer, so an update that
changes compile.py rebuilds in seconds downloading nothing, and the line then
says "0.0 GB downloaded" - true, and it tells a helper the update rebuilt from
what was there. apt's packages and the base image are not counted (the scope
of `swiftImage.measured`). `verify.sh` checks the sum against the build log
BuildKit really printed whenever its Swift gate builds the image (the whole
pin sum under `--no-cache`), and requires both download steps' headers to be
found in it, so a parser that found none cannot pass by saying 0.

**Rejected:** making the Dockerfile print curl's byte count - the Dockerfile
is in the toolchain id, so every cached Swift program on every Mac would be
compiled again, and 1.3 GB downloaded again, for a number on the trail;
`docker image inspect`'s size (2.24 GB on disk, 504 MB compressed: neither is
what was downloaded); a fixed 1.3 GB (false after the cached rebuild, and a
second copy of the pins); a new script for it (it would need its own baked
copy check and verify line for nothing `swift_blocks.py` cannot carry, and
that file is not in the toolchain id).

**What the teacher is told when the build fails** (#642, v1.9.0). Until
then `preview.sh` printed the sentence that is now `mac.printed.offline` and
wrote `{state: notDownloaded}` for EVERY failed build, so a full disk or a
damaged download was blamed on the internet in all three places a teacher
reads it, while the trail line alone said why. Now the one reading of the log
decides all of it: `swift_blocks.py got-ready --outcome=failed
--state=<cache root>/state.json` writes the state, prints the sentence before
the marker, and names the same reason in the marker.

| The build's reason | `state.json` | each block, and the folder problem | the console (`mac.printed`) |
|---|---|---|---|
| `noRoom` (the disk filled part way) | `{reason: noRoom, state: noRoom}` | `reasons.noRoom` | `noRoom`: this Mac ran out of space part way, free some and preview again |
| `offline` | `{reason: offline, state: notDownloaded}` | `reasons.notDownloaded` | `offline`: the sentence it always printed, byte for byte |
| `damaged` | `{reason: damaged, state: notDownloaded}` | `reasons.notDownloaded` | `damaged`: Windows' own sentence, true here too |
| `unpack` (anything else) | `{reason: unpack}` | `reasons.notCompiled` | `unpack`: it could not be got ready on this Mac, preview again |

The mapping is Windows' `ensureExit` exactly (10, 11, 12), and
`test_swift_blocks.py` holds the two equal by running `ensure` with a failing
fetch for each reason. `reason` is a record for a helper reading the cache
folder; nothing reads it. When the website builder prints nothing a teacher
can read (it could not be asked, or an older copy printed only the marker),
`preview.sh` prints `mac.printed.unpack` itself, from a literal the launcher
test holds equal to the contract, and writes no state. The page students see
does not change: `codeRunner.ts` shows `words.notReady` whatever the reason.
The trail's event is unchanged (rule 5): its line already names the reason,
and that reason is now what chooses the sentence.

**Measured** with the dev tree's Python, before the change: `curl: (16)`,
`(55)`, `(92)` and `(60)` all read as `unpack`. (16) is an HTTP/2 framing
error, (55) a failure sending, (92) an HTTP/2 stream not closed cleanly -
each a connection that dropped, which `offline`'s trail words already
cover - so they are `offline` now, each with a
`mac.reasonCases` case. **(60), a certificate curl could not check, stays
`unpack` on purpose**, with a case pinning it: neither "go online" nor "try
again" fixes it, and a network that intercepts encrypted connections is a
real case at a school.

**Known limit.** A content filter that answers 403 for download.swift.org is
`curl: (22)`, so `unpack`, and the teacher is told to preview again - when the
real fix is a network the filter does not block. A 404 from a moved pin is the
same code, whose fix is a Plantoir update; neither is told apart from the log.

**Rejected:** bash reading the reason out of the marker and choosing the
sentence (JSON parsed by `case` patterns, and a second copy of four sentences
that only a text test would keep in step); new block reasons `damaged` and
`unpack` (new folder-problem words both platforms render, and Windows would
have to write new states to reach them, when the three existing reasons
already name the right fix for each cause); `damaged` → `notCompiled` (it
would differ from Windows, and at a school the likeliest cause of a download
that is not what was pinned is a portal or filter answering in place of the
real server, for which "while it is connected to the internet" is the right
advice); `(60)` as `offline` or a reason of its own (above); moving the
free-space check's and the wait's sentences into the contract too (correct,
and not needed: they already say the right thing).

**Known limit.** The build's fence reader and Quartz's parser read a lazy line
in a list item differently (`fences.pageShapes`): the build compiles the body
IT read and the site looks for the key of a shorter body, finds none, and
shows the block as plain code with a `plantoir: error:` line
(`words.blockNotCompiled`) and, since #567, as the
`runnableCodeShownAsPlainCode` folder problem. The fence reader was deliberately NOT changed to
follow lazy lines (the brief keeps the fence rule as #455 left it; the safety
net names the block). A Swift block the build's reader cannot see at all is
never compiled, and is named the same way.

**Rejected:** compiling in the build (it cannot start the Swift image); a
Docker socket in the main container; the toolchain in the main image (every
teacher would download 1.3 GB for a language most never use); failing the
build on a compile error (ruling Q1); clearing the cache on `--full-rebuild`;
a hand-bumped toolchain version in the key; caching a failure that was not
the compiler's; one job folder per course.

## GeoGebra sketches: what the build does (#578, v1.9.0)

A teacher writes a ` ```geogebra ` fence — `file:` naming a `.ggb` saved
from GeoGebra, or GeoGebra commands one per line, as in its Input Bar — and
students get a sketch they can drag, opened with a tap and served by the
class site itself. The same split as the figures above: **Python prepares
and Quartz places.** `scripts/geogebra.py` does everything that can fail;
the site's transformer and loader (06 → Q) only read what it left. The rules
and cases: `contracts/shared-rules.json` → `geogebraFences`. Three kinds of
sketch: a teacher's `.ggb` (`file:`), GeoGebra commands alone, and a sketch
on geogebra.org (`material_id:`, fetched once and kept — item 9).

1. **When.** ALWAYS section, straight after the figures pass and BEFORE the
   folder checks (`_prepare_geogebra`), so a sketch that cannot be shown is
   said where every folder problem is said. It never stops a build.
2. **Which pages — TWO scans.** `geogebra.pages_students_see` runs
   `figures.pages_students_see` once with `must_contain="```geogebra"` and
   once with `"~~~geogebra"`, merged by path. `must_contain` is a plain
   substring test, so one scan alone never reads a page whose only sketch is
   in tildes (plan review finding 9; `test_geogebra.py`
   `test_a_tilde_fence_is_found_by_the_page_scan` is its must-fail, measured
   red with the second scan taken out).
3. **Reading a fence** (`read_fence`, ruling Q1): leading `key: value` lines
   whose key is one of the Obsidian GeoGebra plugin's (`file`,
   `material_id`, `app`, `height`, `width`, `alt`, `caption`, `toolbar`,
   `algebra`) or `version` are settings; the first line that is not starts
   the commands, so GeoGebra's own `a: x + y = 3` is a command. A `---` line
   ends the settings; a block that opens with `---` is read to the next one.
   `version:` does nothing but change the fence — the documented way to make
   a changed geogebra.org sketch be fetched again (stage 4). Every case is in
   `geogebraFences.settings.cases`. Three slips are said at build time
   (stage 2 review item 4), because otherwise a student would be the first
   to see them: a `---` block that is never closed is a problem
   (`settingsNotClosed` — it would have read every command as a setting and
   left it out); `file:` with no name is `fileHasNoName`, not a
   `fileNotFound` naming nothing; and a KNOWN key written among the commands
   — in capitals (`File: x.ggb`), or after the line that started the
   commands — is a `plantoir: note:` (`settingAmongCommands`), since it will
   run as a GeoGebra command that GeoGebra refuses. Only a known key is
   noted, so GeoGebra's own `slope: Slope(a)` passes silently. **A note is
   not a folder problem** (stage 3+4 review item 3): it is a line in the
   build's own output, which the app does not show the teacher, so the one
   who sees the slip is usually the student, under the sketch: "Line {n}
   couldn't run" (`lineCouldNotRun`, Q3 in 06). And not every such line is
   refused: `height: 400` among the commands is a GeoGebra command that
   makes a NUMBER called `height`, so the sketch opens, the box keeps its
   own height, and nothing is said on the page at all.
4. **The key.** A sketch is found by `figures.key_of` — figureFences'
   `cacheKey` rule, REUSED, so the build and the site (which hashes the mdast
   code value with `figureRules.keyOf`) agree by a rule both already run.
   `check_geogebra_rules_against_the_site.py` runs every `keys` case through
   the site's own Markdown reader in the image: a callout, a callout in a
   callout, a list item, tildes, Windows line endings and trailing spaces
   give the same key; `version: 2` gives a new one.
5. **The file, and why it is published ONCE** (plan review finding 4).
   `find_file` looks the name up by LISTING each folder — exact spelling
   first, then one differing only in capitals or Unicode form (Netlify and
   Cloudflare are case-sensitive) — beside the page, then from the top of the
   course folder, then by its file name alone in `Media`. It must be a zip
   holding `geogebra.xml` (read, never unpacked; size from its first
   `<euclidianView><size>`, the app from `<geogebra app=…>`) and at most
   20 MB. **A file Quartz leaves out of the site is not found** (stage 2
   review item 6): one under `private/`, `templates/` or `.obsidian/` at the
   top of the course folder (Quartz's `ignorePatterns`, root only and
   case-sensitive — measured with Quartz's own globby in the image:
   `private/a.ggb` left out, `Private/f.ggb` and `U/private/b.ggb`
   published), or with any part of its path starting with a dot (the file
   walk skips those). Said once as `fileNotFound`, never found here and then
   missing on the site. **Nothing is copied:** Quartz's Assets emitter already publishes
   every file under `content/` that is not a page, at `slugifyFilePath` of
   its path, so the manifest records the path in `content/` and the
   transformer makes the address with that same function. Measured on the
   slope-angle sketch: 1,594,544 bytes on the site once, plus its 32,484-byte
   thumbnail — against 3,221,572 had it been copied into `static/` as well.
   **Rejected:** copying it (twice the bytes); taking the source out of
   `content/` (a page linking the file for download would break, and
   `content/Media` mirrors the teacher's own folder, which the build never
   edits). A file beside a page reaches the site only from a folder the
   course SHARES: a page listed by name in `shared_files` brings no file with
   it, so the guidance says to keep a sketch beside a page in a folder, or in
   `Media`.
6. **What the site gets.** `quartz/plantoir-geogebra/manifest.json` — the
   site's words and the attribution addresses from the contract, and, by
   PAGE and then by fence key (06 → Q2: the same fence on two pages can name
   two files), per sketch its app, size (the fence's `width:`/`height:` win), description,
   caption, commands with their lines, toolbar/algebra, where its file is in
   `content/`, its thumbnail, and the size the button names (the sketch's
   bytes plus the engine's first load, 2,864,256 bytes gzipped: "about
   4.5 MB" for the slope-angle sketch, measured 4,473,431 compressed). The
   `.ggb`'s own `geogebra_thumbnail.png` goes to
   `quartz/static/geogebra-sketches/`, named by its own SHA-256 so one file
   on several fences is one picture. No sketch that can be shown: neither
   folder, and every fence stays the code block it was.
7. **The gate.** `counts["geogebra"]` — pages students can see with a sketch
   that can be shown — goes to `page_features.install_gated_assets`, which
   copies `/opt/vendor/geogebra` (02 → "/opt/vendor/geogebra": 117 files,
   27,093,283 bytes) to `static/geogebra` only then, and takes it out when
   none is left ("📐 This site carries GeoGebra for the sketches on 2
   pages."). A build without the engine says `engineMissing` and shows none.
8. **What the teacher and an assistant are told.** One folder problem per
   section build, `geogebraSketchesNotReady` (page, sketch, line — the
   setting's own line for a setting, the opening fence's otherwise; at most
   ten), never offered a repair; one `plantoir: error:` line per sketch
   (`Investigations/GeoGebra Missing.md: geogebra block 1, line 8: …`); a
   sketch with no `alt:` is a `plantoir: note:` only. **No new trail event**:
   problems reach the trail through the existing folder-problem line, as the
   figures' do.
9. **A sketch from geogebra.org: FETCHED ONCE, kept by the fence** (#578
   stage 4; ruling Q2 and plan review finding 2; `geogebraFences.fetch` and
   `.cache`). The first build that meets a `material_id:` fence asks
   GeoGebra's public materials API
   (`https://api.geogebra.org/v1.0/materials/{id}?scope=extended&embed=creator`)
   what the sketch is, then downloads the `.ggb` of its ONE applet (the
   element of type `G`), checks it as a teacher's file is checked, and only
   then saves it in **`<builds>/<course>/.geogebra-cache/`** — beside the
   course's built sites, outside the teacher's folder, shared by the sections
   (08 names it) — as `<key>.ggb` plus `<key>.json` (id, title, author),
   **keyed by the fence's own key**, not the sketch's id. A build whose fence
   has a saved copy asks geogebra.org NOTHING. Changing the fence — the skill
   says: add or change `version: 2` — gives a new key, so the next build
   fetches again: that is how a teacher gets a sketch they edited on
   geogebra.org, with no new button in either app (none exists, and none was
   invented). `--full-rebuild` leaves the copies alone (`_prepare_geogebra`
   passes `full_rebuild` and `geogebra.prepare` deliberately ignores it); a
   copy unused for 90 days goes (`figures.PRUNE_DAYS`, the same rule). The
   site's copy is written to `quartz/static/geogebra-sketches/<key[:16]>.ggb`
   — a geogebra.org sketch has no file in `content/` for Quartz to publish —
   and the card names the author and the licence (06 → Q4). Said: "📐
   Sketches from geogebra.org: 1 copied now, 0 kept from before." Problems:
   no copy and no network (or a timeout, a server error, a redirect off
   geogebra.org's hosts) is `materialCouldNotBeFetched`, a folder problem,
   and the fence stays code; 403/404/410 or `deleted` is `materialNotFound`;
   no applet is `materialHasNoSketch`, two or more `materialHasSeveralSketches`;
   a download that is not a GeoGebra file is `materialHasNoSketch` and is
   never kept. **A download cut off on the way** (stage 3+4 review items 1
   and 2) is `materialCouldNotBeFetched` and is never kept: a body shorter
   than its `Content-Length` (`read(n)` returns what came rather than
   raising, so `MaterialFetcher._get` compares the two) and a chunked answer
   that stops (`http.client.IncompleteRead`, an `HTTPException` and NOT an
   `OSError`, which is why both fetch paths name it). Whatever else a fetch
   raises is that ONE sketch's `materialCouldNotBeFetched` (`_material`'s
   catch), so `_prepare_geogebra`'s catch-all — which drops the whole
   manifest — is never reached by a fetch, and the `file:` sketches on the
   same site are prepared as ever. Tests: `test_a_cut_off_download_…`
   (three stub answers: the API cut short, the `.ggb` cut short, the `.ggb`
   chunked and cut) and `test_a_failed_fetch_takes_no_other_sketch_down`;
   must-fails, each red: the `HTTPException` catch removed, the length
   check removed, the per-sketch catch removed. A failed fetch is not
   remembered: 06 → Q3 says what that costs a build.

   **Measured** (2026-10-24, one request for ju3f2kbg by hand): HTTP 200,
   1,598 bytes of JSON — `title`, `visibility` "S", `deleted` false,
   `creator.displayname` "Russell Gordon", and one `elements` entry of type
   `G` whose `url` is the 1,594,544-byte `.ggb`. That `.ggb` holds its own
   `geogebra_thumbnail.png`, so the element's `previewUrl` picture is not
   fetched (one request fewer, and the same thumbnail path as a teacher's
   file). The image's Python trusts 148 certificate authorities by default,
   so https to geogebra.org needs nothing added. **Tests never call the real
   API**: `test_geogebra.py` `MaterialTests` serves both answers from a local
   server of its own, through the same code, and counts the requests where
   they arrive; verify.sh plants a saved copy for an id geogebra.org does not
   have, so a build that asked anyway would fail rather than pass.
   **Must-fails** (copy-and-restore, each red): keyed by the id → four
   tests; a request despite a saved copy → three; `--full-rebuild` clearing
   → the cache case. **Rejected:** asking every build (a class site would
   change under the teacher, and every preview would need the network);
   keying by the id (an edited sketch could never be fetched again); clearing
   on a full rebuild (figures do, because a new engine draws differently — a
   reason that does not apply here); fetching the preview picture as well.

**`file:` is plain text, not a link.** Obsidian's rename does not rewrite
it, and Copy a Page does not carry the file (it copies a page's links and
embeds; below, "`Media` is mirrored WHOLE"). Both arrive as `fileNotFound`
naming the line, and the lookup by file name in `Media` is what makes "put
the .ggb in Media" the fix.

**Measured** (2026-10-24, M4 Pro, macOS 26.6, Chrome for Testing 155, the
verify fixture, a clone served on `[::1]` under the publish's own
`_headers`): the planted sketch opened in 582–612 ms from the tap, 16
requests, 8,917,110 bytes as served (2,835,223 compressed); a sketch from
commands on the same page 40 ms; after Quartz's page change 253–259 ms;
cross-origin isolated the same; 0 refusals, 0 requests off the site. The
slope-angle sketch (1.6 MB, with its picture): 698–769 ms, 18 requests,
10,644,945 bytes (4,473,431 compressed).

## Self-check quizzes: what the build does (#563, v1.8.0)

A `> [!quiz]` callout at the left edge of a page becomes a question students
answer and check in their browser; the site's half is
[06 → J](06-quartz-customizations.md#j-self-check-quizzes-563-v180), the rules
`contracts/shared-rules.json` → `quizCallouts`. There is no frontmatter key
and no engine to gate: the callout opts the page in, and the script and
styles ride every site's shared `postscript.js` and `index.css` (ruling Q2).
The build's share is a folder check and two files, ALWAYS, beside the
runnable-code count (`_check_quizzes`):

1. **Reading.** `figures.pages_students_see(..., must_contain="[!")` - the
   gate's own visibility rule, outside Media, only pages that could hold a
   callout - then `quizzes.quizzes_on_page` on each build copy's raw text.
   The reader is line by line, not a Markdown parser (the reason
   `markdown_code` gives): line endings made LF (CR LF and a lone CR, review
   S1), `%%` comments taken out first as ObsidianFlavoredMarkdown takes them
   (S10, keeping a map back to the page's own lines), fenced code skipped
   at any quote depth, then what `quizCallouts.rule` says a top-level quiz
   is. Inside one: the first list holding a task box is the choices (a box
   needs words after it on its line - measured: `- [ ]` alone is plain text
   to the site's parser; a `>` four or more columns past its container's
   content is indented code, and an HTML block - a block-level tag, or a
   line holding only one tag - swallows what follows it to the next empty
   line, as the site reads both: quiz syntax in one at the page's level is
   no quiz, and a list of choices in one makes the quiz `choicesInHtml`, on
   both sides; a ` ```geogebra ` or ` ~~~geogebra ` fence opened inside an
   item of the choices makes it `sketchInAChoice` — #578 stage 5, 06 → Q7 —
   whether or not the sketch itself can be shown, because the site refuses
   it either way); a nested `> [!answer]` or
   `> [!explain]` at the
   quiz's own level is that callout; the rest is the question, whose
   paragraphs (and title) are where blanks are counted. `verdict` - the
   mirror of quizRules.ts's, with the problems in `recognise.order` - says
   what the quiz is. The mirror PARSES answer lines (`parse_answer_line`)
   and never checks what a student typed: that is quizRules.ts's alone.
2. **Lines in the teacher's file.** A build copy can carry lines the
   teacher's page does not (rewritten frontmatter, a removed region), so
   each quiz is matched to the one in the teacher's page with the same
   title, counting equal titles in order (review N8), and a problem keeps
   its distance from the quiz's first line - the answer line for an answer
   problem, otherwise the quiz's first line. One that cannot be matched
   loses its line (`quizLineNoLine`).
3. **What the teacher and an assistant are told.** One line per quiz that
   cannot be checked:
   `plantoir: error: Units/Practice.md: quiz 3, line 41: <quizCallouts.words.problems[reason]>`
   (`line 41` alone for a quiz inside a list or callout, which has no
   place), and ONE folder problem per section build, `quizzesNotReady`
   (at most ten named, after every other finding), surfaced by both apps
   and recorded on the trail as the existing "found a problem with this
   course's folders" - no new trail event. It never stops a build (the
   ruling for #493): one question must not keep a site from being built,
   and refusing would break the preview the teacher is fixing it in. Not
   repairable (`siteHealth.repair.neverOffered`).
4. **The two files** (`quizzes.write_quiz_files`, every build, the same
   bytes for the same input): `quartz/plantoir_quiz.json` carries only the
   words (`words.site`, `words.problems`), because the page's script
   bundles it and must change only when the words do; and
   `quartz/plantoir_quiz_pages.json` carries `examined` (every page read,
   by its path in the site's content) and, for each page with a quiz, how
   many top-level and nested quizzes it found and which it reported. The
   transformer reads both with `fs` (mtime-cached). An unreadable contract
   writes empty words, and the site then renders every quiz as not ready -
   never with its answers on show.

**The safety net** (`quizCallouts.safetyNet`, review S4). The site renders
what IT read; for a page this check examined and that is published, it
compares counts and, quiz by quiz, whether each side found a problem, and
says `plantoir: error: <page>: quiz <n>, line <L>: <readDifferently>`
where they differ (the line from the pages file's `lines`; when the
top-level counts differ, "the quiz at line L" of the first quiz the check
found; when only the quizzes in a list or callout differ, "a quiz inside a
list or another callout at line L" from `nestedLines`) - quiet otherwise. It relies on `build --concurrency 1` (the line
reaches the build's output from the one parsing thread, review N1). Since
#644 each line is also recorded, and the site's emitter says them all as
ONE `quizzesReadDifferently` folder problem, after any
`runnableCodeShownAsPlainCode` and in the same call (above, "…and the quiz
safety net").
Measured: a `- [ ] ` choice with nothing after the box was read as a box
here and as text by the site, and the net said so on its first build; the
rule was then corrected on both sides and pinned (`aBoxNeedsWordsAfterIt`).
A page students cannot see is parsed by Quartz too and never named.

**The live-preview edge.** As for runnable code: the preview's own rebuilds
do not re-run the check or rewrite the files, so a quiz added while a
preview serves is rendered by the site's own reading (its verdict is the
site's, the same rules), and its folder problem and any safety-net line
come with the next Preview.

**Measured** (2026-10-17, M4 Pro, macOS 26.6, the branch's image): the
verify fixture's 35 quizzes (every recognise case on one page) were read
alike by both sides - every kind and every problem, with no safety-net
line; EXC2O built with the pre-branch image and with this branch is 297 of
302 pages and feeds identical once Quartz's random list ids and build
times are set aside, the other five being folder and tag listings ordered
by build time, which differ between two builds of the SAME image too
(measured: six differ there); MPM2D's `Similar Triangles Practice` (eight
top-level `[!answer]-` callouts), a page of look-alikes and its CR LF twin
are identical.

## Stage 4: Configuration patching

The remaining per-section settings from `course_config.json` are applied to
the scaffold: the sidebar omit set, folder click behaviour, footer HTML,
page title (emoji + course code or custom label + optional `S<N>` marker),
locale, per-section colour scheme, and the social-media-preview emitter
toggle. Each is detailed in
[customizations §C2](06-quartz-customizations.md#c2-applied-on-every-build).

**Before the omit set is written, the section's copy of the sidebar filter is
brought up to date** (`ensure_sidebar_hide_rule_current`, issue #265). Each
section's `quartz.layout.ts` is a copy made once, when the section is first
built, so a change to the filter (`setup_course.EXPLORER_BLOCK`) reaches only new
sections unless something repairs the old ones. It runs right after the anchor
check, in the ALWAYS part of the build, and is idempotent: a file whose every
`Component.Explorer(` block carries `CQ4T-HIDE-RULE: v2` is left byte for byte;
otherwise every block is replaced with the current one (the omit set and
`folderClickBehavior` are rewritten just after, as on every build) and the result
must carry the marker in every block and a wired anchor — or the build refuses,
the way the anchor check does, rather than guess at a hand-edited file. **On the
mac this seldom runs**: a changed toolchain gets a new container, whose
`/tmp/quartz-builds` is empty, so the section is recopied from the image, which
already has v2. On Windows the build folder (`%TEMP%\quartz-builds`) persists, and
this is where the change actually lands. It was proved the Windows way on the
mac: a v1.3.1 build into a persisted `PLANTOIR_WORK_DIR`, then a rebuild with the
new scripts and no `--full-rebuild` — the console said "Reusing existing" and
"Brought the sidebar's hide rule up to date", and the built sidebar hid exactly
the stored names. What the rule itself is: [06 → B1](06-quartz-customizations.md).

Two more things happen here, fresh on every build:

- **The landing-page title is computed** (`computed_landing_title`) from
  the CURRENT settings — `course_name`, the per-section
  `show_grade_in_title` toggle (default on; a legacy course-wide boolean
  is honoured), and the per-section `show_section_marker` setting, which
  governs the `", Section N"` suffix — and written into the MERGED copy of
  `content/index.md` only. The teacher's source file is never rewritten,
  a course rename reaches the site on the next build, and the behaviour is
  deliberately literal: no name is ever edited to avoid a repeated grade
  (the app warns instead, and the teacher decides).
- **The social sharing card is drawn.** `social_card.py` (Pillow) renders
  a 1200×630 card — the section's colour-scheme light background, the
  course name large in the header font (scheme `secondary` colour,
  auto-sized, at most two lines), and the course emoji beside the course
  code (plus the `S<N>` marker when enabled) in the body font — and writes
  it over the scaffold's `quartz/static/og-image.png`, which the site's
  head already links as its share image. No logo and no domain (Apple's
  share sheet overlays the domain itself). A failed draw prints a warning
  and never fails the build.

Additionally, `course_config.json` itself is copied to
`<output>/quartz/course_config.json` and the patched Explorer components'
import paths are pointed at it — the Explorer *reads course configuration at
site-build time* to know which folders are expandable.

## Stage 5: Dependencies and the actual Quartz build

**A build for publishing stops that section's preview.**
<a id="a-build-for-publishing-stops-that-sections-preview"></a>
A preview does not stop when the launcher that started it is killed: on the mac
the Python and the node server both live inside the container, and the Python's
sync watcher keeps mirroring the SERVE build to the host every second. A
`--build-only` run alongside one is therefore overwritten within a second of
finishing, and what gets published is the preview — live-reload client and all.
So `--build-only` stops the preview serving that section first.

It is matched by the section's own BUILD DIRECTORY, which is on the serve
process's command line, and deliberately **not** by port: a build-only run is
never given one, so an earlier version killed whatever held the default 8081 —
a different section's preview, in the ordinary case of previewing one section
while publishing another. Match on the directory plus a trailing separator, or
`section1` also matches `section10`.

The process list comes from `stop_preview.read_snapshot()`, which asks the
platform: `/proc` on Linux and inside the container, `Get-CimInstance
Win32_Process` natively on Windows. Until 2026-09-05 `/proc` was the only
reader, so on Windows the list came back empty, this stopped nothing, and the
overwrite race above was live on that platform for every publish made while a
preview was running. That is why the reader is a dispatcher rather than a
constant: a rule that silently answers "nothing" on one platform is worse than
one that is missing there, because it looks implemented.

**Which processes belong to a section is one rule, and it lives in
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`stopPreview`,** implemented once in `scripts/stop_preview.py`. Read that
before changing anything here. It answers two different questions:

| | Asked by | What it stops |
|---|---|---|
| `everything` | the launcher's `--stop` | the server, the build, the driver, and every child of them |
| `servingOnly` | `build_site.py --build-only`, above | only the preview SERVER that would overwrite the build |

The distinction is not fussiness: a build for publishing must never stop a
build, because the build it is protecting is itself a build of this section,
and the process asking is the one the rule would otherwise recognise.

A process belongs to the section on any ONE of three kinds of evidence —
its working directory is inside the section's build folder, its command line
NAMES that folder, or it is `build_site.py` carrying this course and this
section — **plus every descendant of a match.** It is a disjunction because
until 2026-09-05 this question was answered in three separate places
(`preview.sh`, `preview.ps1`, and here), and those three turned out not to be
three copies of one rule but three PARTIAL ones: a working directory sees a
child launched by a relative path, which carries no directory to match on
(`npm install` runs exactly that way), while a command line sees the Python
driver, which never calls `os.chdir` — it passes `cwd=` to its CHILDREN — and
therefore sits in the container's `/teaching` for the whole build. Through
every in-process phase of a build the driver is the only process there is to
find, and a sweep by working directory found nothing and said so. Only the
PowerShell copy walked descendants.

Every comparison ends at a BOUNDARY rather than being a substring test. That
is not a detail either: `…/section1` is a prefix of `…/section10` and
`--section=1` is a prefix of `--section=10`, and both had already stopped the
wrong section on one platform.


- **Pre-baked dependencies:** If `node_modules` is not present in the workspace,
  it is symlinked instantly from `/opt/quartz/node_modules` in the image. `npm install`
  is only invoked if explicitly requested with `--force-npm-install`.
- The environment sets `TZ=UTC` and a fixed `SOURCE_DATE_EPOCH`
  (2024-01-01), nudging build tooling toward reproducible output —
  part of the [determinism strategy](07-deployment.md#why-determinism-matters)
  that keeps Netlify uploads small. It is built by
  `toolchain_paths.node_environment`, which also adds
  `--disable-warning=DEP0040` to `NODE_OPTIONS` (#640): on Node 22 Quartz
  v4.5.0 prints a `punycode` deprecation on every build, and only that one
  warning is silenced ([02](02-docker-image.md) → "Node 22 (#640)").
- **Preview mode (default):** kills any process holding the requested
  port (`lsof`, that port only — several previews can run at once). This is
  the one place a port is still the right handle, because here the port is
  known and leased; everywhere else, see the rule above. Starts a
  lightweight background synchronization watcher thread that polls `public/` and
  mirrors changes to the host's `.merged_output/section<N>/public/`, then
  runs `npx quartz build --concurrency 1 --serve --port <8081-8084>
  --wsPort <port+1000>` (the websocket port keeps concurrent previews'
  live reload from colliding). The teacher browses the HOST address the
  launcher printed; Quartz rebuilds on file changes.
- **Build-only mode:** `npx quartz build --concurrency 1`, verifies
  `public/` exists in `/tmp/quartz-builds/...`, and performs a one-shot
  sync to the host `.merged_output/section<N>/public/` and `course_config.json`.
  This is the path `deploy` uses.

> **Why `--concurrency 1`?** Quartz's parallel transpile workers can stall
> or crash silently inside a resource-constrained Docker container. A serial
> build is modestly slower but reliable.

### Stopping a build: exit 130, and no traceback

Pressing Cancel in the progress view while a preview is building goes through the app's
cancel path (`ScriptRunner.cancelByUser`), which types a `^C` into the
console. Through the launcher's `docker exec -it` that arrives inside the
container as SIGINT, and Python raises `KeyboardInterrupt` wherever the build
happens to be — usually inside a `subprocess.run` waiting on node. Until
2026-09-23 nothing caught it, so the last thing in the console, and in any
problem report, was a Python traceback: measured in a real report of
2026-09-19 as 21 lines and 1,230 characters of container paths and
`subprocess` internals, sitting inside the 8,000-character tail the app reads
for failure explanations and the preview address (GitHub #223).

`main()` now catches `KeyboardInterrupt` around `build_section_site` and calls
`sys.exit(130)`, printing nothing. Measured with the real `main()` and the
build replaced by a long `subprocess.run`: before, exit −2 (killed by SIGINT)
and 33 lines of traceback on stderr; after, exit 130 and nothing.
`subprocess.run` has already killed its child by the time the interrupt
reaches `main()`, so no node server is left behind. Pinned by
`scripts/test_stop_quietly.py`, which Windows' `PythonToolchainTests` runs too
(its real-SIGINT case skips there).

- **Why 130 and not 0.** 130 is what a shell reports for a program killed by
  SIGINT, and what `docker exec` passed on before, so every reader of the exit
  status sees exactly what it saw. 0 was REJECTED: `deploy.py` runs this build
  with `check=True`, and a Stop during a publish's rebuild would read as a
  finished build and go on to upload a half-built site.
- **Why nothing is printed.** A line here would be a new sentence a teacher
  reads, owed to the wording pass and the contract, for a moment the app
  already describes itself (the task's "stopped" outcome).
- **One handler, not one per `subprocess.run`.** The issue offered both;
  `build_site.py` has no bare `except:` and no `except BaseException`, so
  nothing inside the build can swallow the interrupt and carry on, and the one
  handler covers the npm install, the build-only run and the serve run alike.
- **This is the `^C` path only — do not "extend" it to SIGTERM.** The app's
  other stop (`stopByUser`, which terminates the host shell) and
  `stop_preview.py` (SIGTERM by default) already end Python without a
  traceback, because SIGTERM does not raise `KeyboardInterrupt`.
- **A publish, the same way (GitHub #259, 2026-09-25).** `scripts/deploy.py`
  had no `KeyboardInterrupt` handling either, so Cancel during a publish still
  printed its traceback. It now enters through `run_until_stopped()`, which
  calls `main()` and turns `KeyboardInterrupt` into `sys.exit(130)`, printing
  nothing. Measured with the real `deploy.py` under `pty.fork()` and a `^C`
  written to the pty, the build swapped for a long `subprocess.run` (host
  Python 3.14; the image's 3.11 prints fewer caret lines): during the
  production rebuild, exit −2 and 26 lines with one traceback before, exit 130
  and nothing after; at the surname question (`input()`), exit −2 and 10 lines
  before, exit 130 and nothing after.
  - **Around `main()`, not inside it.** Wrapping `main()`'s ~290-line body was
    REJECTED (a re-indent diff over the whole publish path), and so was moving
    the body into a new function: `test_deploy_netlify_headers.py` reads
    `inspect.getsource(deploy.main)` to prove the Cloudflare branch returns
    before the badge writer, so `main`'s body has to stay in `main`. One
    handler covers every place a publish can be waiting — the rebuild's
    `subprocess.run`, both questions, an upload, wrangler — and the two
    guards below cover a child that is seen leaving first.
  - **The Cancel that arrives through the build first.** The `^C` reaches the
    rebuild child and `deploy.py` together. Usually `deploy.py` is still in
    `waitpid` and hears its own interrupt first; if the child's exit is seen
    first, `subprocess.run` raises `CalledProcessError` with 130 (the build's
    own quiet exit) or −2 (killed outright), and `rebuild_for_production` used
    to print "Production rebuild failed" and exit 1. It now exits 130 for
    those two statuses (`build_was_stopped_by_the_teacher`), and 1 for any
    other. Not reproduced by hand — the race is narrow — so it is pinned by a
    test that raises the error directly.
  - **The Cancel that arrives through wrangler first.** The same race on the
    Cloudflare leg: `deploy_to_cloudflare` exits 130 when wrangler reports 130,
    −2 or 0xC000013A (Ctrl-C on Windows) —
    `STATUSES_OF_A_PROGRAM_STOPPED_BY_A_CANCEL`, which the rebuild's guard
    reads too — instead of raising "Cloudflare's deploy tool exited with
    code …" with a traceback. Measured inside the image with a stand-in API
    that never answers: **wrangler 4.80.0 exits 0 on SIGINT** (its `pages`
    commands install a handler that calls `process.exit()`), so the guard
    cannot see that shape — `deploy.py`'s own interrupt is what covers it, and
    with the whole group signalled, as the app's `^C` does, the real wrangler
    run exits 130 with nothing on stderr and no wrangler left running. (A
    harness that starts Python with SIGINT ignored — any `&` job in a
    non-interactive shell — shows the danger: wrangler leaves with 0 and the
    leg reads as published. Restore `default_int_handler` in such a harness.)
  - **A Cancel during the upload stops the upload.** Until the #259 fix round
    it did not: the uploads ran in a `with ThreadPoolExecutor` block, and
    leaving that block on the `KeyboardInterrupt` waits for the executor to
    RUN every upload still queued. Measured with the real `deploy.py` under a
    pty, `netlify_api` stubbed (40 files, 0.4 s per PUT, 5 workers) and the
    `^C` about a second in: **25 of 40 uploads started after the Cancel**, and
    it took 2.3 s to leave. Now `_upload_required_files` drops the queue
    (`shutdown(wait=False, cancel_futures=True)`) and sets `stop_uploading`,
    so an upload waiting out a 429 gives up instead of retrying for up to a
    minute: **0 of 40 after the Cancel**, 0.23 s, three runs of three. The
    uploads already in flight — at most five — still finish.
  - **What reaches the site, and what does not.** Neither host publishes a
    half-finished upload, so a Cancel in the middle leaves the published site
    exactly as it was:
    - Netlify's file-digest deploy is created with `draft: false`, and Netlify
      documents that it goes live when its state reaches `ready` — after every
      required file has arrived. A deploy whose files never all arrive never
      becomes the published one. (Netlify does document a cancel call, `POST /deploys/{id}/cancel`, but it is deliberately not used here: a deploy whose files have all arrived goes live regardless, and one still receiving files stays a draft anyway;
      the unfinished one is simply left waiting, and nothing is sent after the
      Cancel to tidy it up — a network call during a Cancel was REJECTED, since
      the app ends the launcher two seconds after its `^C`.)
    - wrangler uploads every asset first and creates the Pages deployment —
      the step that changes the site — only after (`pages deploy` in
      wrangler 4.80.0's `cli.js`: `upload(…)`, then `POST …/deployments`).
      A Cancel before that step publishes nothing; `subprocess.run` kills
      wrangler 0.25 s after the interrupt if it has not left on its own.

    **The one window where a Cancel does not stop it:** a Cancel that lands
    after the last files are already on their way — Netlify's final uploads
    in flight, or wrangler past its deployment step — or after the upload has
    finished. The publish then completes and the site changes, while the app
    reports the task as cancelled (it decides by its own flags, and has no way
    to know which side of that moment the `^C` landed). The window is the
    last second or two of the upload; nothing in the app's wording claims the
    site is unchanged, and whether a sentence should say so is a wording
    decision left open, not taken here.
  - Nothing else to tidy on the way out: the token file is removed by
    `deploy.sh` before Python starts, and the publish registry belongs to the
    app.
  - Pinned by the second class in `scripts/test_stop_quietly.py`: the
    in-process 130, the program's entry going through `run_until_stopped()`
    (the first case alone would pass with the entry put back to `main()`), the
    rebuild that left first, and a real SIGINT sent to the whole process group
    mid-rebuild (POSIX only). On `origin/dev` before the change: 3 failures and
    1 error, three runs out of three. The fix round added three more: wrangler
    that left first; 40 stubbed uploads with a real SIGINT to the main thread
    at the 15th (at most 25 may start in all — the old code started 40); and
    five uploads turned away with 429 that must give up within 5 s of the
    Cancel (the old code retried for 61 s; POSIX only, since nothing wakes a
    main thread whose every upload is waiting without a real signal). On the
    first round's `deploy.py`: 2 failures and 1 error.
- **Which button.** Only the progress view's Cancel types a `^C`; the Stop
  Preview and console Stop buttons end the process without one and never
  showed the traceback (measured by the same review).

## A section with no `index.md` cannot be PUBLISHED

Found while testing the deploy path on the mac; it broke identically on Windows
because it is in `scripts/`. Left open by the special-folders branch as a
separate piece, and closed on 2026-09-01. The reasoning is kept because the
second half of it was never on anybody's list.

**What it was.** `_sync_public_to_host` (`build_site.py`) copies the built site
back to the host only when `public/index.html` exists — and Quartz emits no root
`index.html` without an `index.md`. So the build SUCCEEDED and printed "Static
build complete", the sync was silently skipped, and `deploy.py` then reported
"Built site not found … Build first: ./preview.sh CODE N --build-only",
telling the teacher to do the thing they had just done.

**The guard is still right** — do not publish half a build. What was wrong is
that its answer went nowhere. The sync now RETURNS whether it mirrored a site,
and a `--build-only` run that mirrored nothing prints "Nothing to deploy for
… it has no front page, so no website was produced" ("Nothing to publish …"
before v1.4.4, #443) and **exits non-zero**. That
matters more than the sentence: a publish runs `preview.sh --build-only` and
then `deploy`, so failing the build stops the run at the step that KNOWS the
reason. The mac already shows the folder-problem dialog on a failed build, so
the teacher gets **Put them back** → **Preview Again**; check that each app's
failed-build path does the same rather than swallowing the findings.

**The half nobody had named, and the worse one.** The skipped sync left the
PREVIOUS build's `public/` on the host, and `deploy.py` uploads whatever it
finds there. So: delete a front page, build, publish — and the teacher is told
the publish succeeded while students get last week's pages. Nothing anywhere
said so. `_clear_stale_host_site` now removes that mirror whenever the merged
tree has no `index.md`, in BOTH preview and build modes, which turns a silent
wrong answer into an honest refusal. Nothing of the teacher's is lost:
`.merged_output` is derived from their notes and every successful build
rewrites it wholesale with `rsync --delete`.

**What each app owes.** The Python is shared, so (almost) nothing. The exception is
`FailureExplainer.cs`, which gains `MissingFrontPageExplanation` — already
written on this side — and it must be asked **BEFORE** `MissingBuildExplanation`.
A publish puts both lines in one transcript, and "hasn't been built yet" is the
wrong thing to say to somebody who just watched it build. That ordering is a
contract case (`app-rules.json` → `failureExplanations`, the case whose
`output` carries both lines), so chaining it the other way round fails the
suite rather than shipping quietly.

**One thing to check rather than copy.** `_clear_stale_host_site` calls
`shutil.rmtree` on the host's `public/` — which under `PLANTOIR_BUILD_ROOT` is
outside the working folder, so outside OneDrive, which is the point of that
variable. If a scanner or an open handle makes the removal fail, the build says
so and carries on rather than dying; but the stale-publish risk returns for
that run. Worth one real test on a machine with OneDrive running, and tell the
the other side what you find.

**A front page that is THERE but hidden** (#246: its settings could not be
read) produces no website in exactly the same way, and is cleared the same
way — but it is not missing, so it says so in its own words and never offers
to put the page back. See "A page whose settings cannot be read is hidden
(#246)" above.

The `sectionIndexMissing` health check understated the same thing — "the site
will open on whatever page happens to come first" is true of a PREVIEW, and for
publishing there is no site at all. Its detail in `shared-rules.json` →
`siteHealth.checks` now names both outcomes, so a teacher can tell whether they
may carry on for now or must fix it before they publish.

## Quartz serves the OLD site before it builds the new one

This one is inside Quartz, so it belongs to both platforms, and it is invisible
until somebody edits a page and looks.

`quartz build --serve` does this, in this order (its own `cli/handlers.js`):

```
server.listen(argv.port)
console.log("Started a Quartz server listening at http://localhost:PORT")
await build(clientRefresh)
```

**It starts serving the existing `public/` before it rebuilds it.** So the
moment a preview launches, the server answers `200` — with the PREVIOUS build.
The fresh one lands seconds later.

Anything that decides "the preview is ready" from the server responding will
therefore show the site as it was BEFORE the teacher's change, with nothing on
screen to suggest it. Ours did, and the symptoms were maddening in a specific
way worth recognising:

- editing a page, previewing, and seeing the old page;
- stopping and starting the preview, and still seeing the old page;
- **doing the same thing slowly and having it work**, because the build had
  quietly finished in the meantime;
- pressing Reload by hand and having it come right.

We suspected three innocent components before finding this — the merge, the
build, and our own web view — and every one of them was provably correct: the
merged content, the built `public/`, and the file timestamps all showed a
current site while the screen showed an old one.

Two rules follow:

1. **Wait for the BUILD, not for the server — and watch the OUTPUT FILE, not
   the console.** Note the time before launching the build, then wait until
   `<section>/public/index.html` is newer than that. It means exactly what has
   to be true before a teacher is shown anything, and unlike Quartz's progress
   lines it cannot be changed by a version bump or swallowed by a spinner. We
   tried matching its emit line first; the file is strictly better.
1b. **Clear the web view's caches before loading, not just its cache policy.**
   A Quartz site is a single-page app: a no-cache policy governs the main HTML
   request while the scripts, styles and the content the page fetches for
   itself still come from the cache — so a fresh index.html can still assemble
   the previous site out of parts. This looked exactly like a build problem
   and was not. Clear disk, memory and fetch caches; leave local storage and
   cookies alone so the preview keeps its light/dark setting.

2. **Reload only when you never saw that line.** We first reloaded
   unconditionally, as cheap insurance, and it was worse than the problem it
   insured against: every preview in the app flickered, for a case that by
   then could not happen. The signal tells you which situation you are in, so
   let it decide — no line, no certainty, so reload; line, so leave the
   teacher's page alone.

Bound the wait (we allow 120 seconds) so a Quartz that never prints the line
cannot leave a teacher watching a spinner: show the preview anyway, and that
is exactly the case the conditional reload covers.

**And bound the SILENCE after the server line, which is a different wait
entirely** — added 2026-09-20 for
[issue #225](https://github.com/russellgordon/plantoir/issues/225). Waiting for
the built page to change answers "has this build landed?"; it says nothing
about whether the teacher's machine can reach the site, and on a Mac that
could not, the app waited ten minutes and then said nothing. So on the mac
this wait now also ends early when the run has announced its server and then
gone quiet for 45 seconds — it hands on to the polling below rather than
failing there, since a site that is answering should still be shown. The rule,
the measurements and what was rejected are in
[`09-mac-app.md`](09-mac-app.md) → "A preview that never appears"; the numbers
and sentences are in `contracts/app-rules.json` →
`previewPorts.whenThePreviewNeverAppears`.

## The “ — Edited” marker: knowing a section has changed since it published

Russell asked for the thing Pages does — `Untitled 3 — Edited` in the title
bar — for a section window: if any page the section uses, or shares with
other sections, has changed since the last publish, say so. And explicitly:
without impacting performance.

**The first finding was that nothing recorded when a section last
published.** Not in `course_config.json`, not in the trail, nowhere on
either platform. The `.netlify_sites` / `.cloudflare_sites` markers record
that a section has EVER published, not when or with what. So the feature is
half "compare two things" and half "start recording one of them".

### The shared file — match this exactly

`courses/<CODE>/.publish_state/section<N>.json`:

```json
{
  "destinations" : [ "netlify" ],
  "fingerprint" : "9f2c…",
  "publishedAt" : "2026-08-22T13:46:32Z"
}
```

Written by whichever app publishes, read by both.

**Be careful about how far to push that.** The fingerprint embeds each
file's size and modification date, so it holds up when both apps look at
the SAME folder — a working folder on a shared drive, or a USB disk moved
between two machines, where the dates are the file system's and do not
change. It does NOT survive a course folder being copied between machines
by a means that rewrites modification dates, and no algorithm that avoids
reading file contents could. So implement it to match, expect a shared
folder to agree, and do not promise a teacher that a course zipped up on
one machine and unzipped on another keeps its marker: it will read as
edited, and one publish puts it right.

Matching matters, then, wherever the two apps can see the same folder, so
treat the algorithm as a wire format rather than an implementation detail:

1. Walk `courses/<CODE>/`, skipping hidden entries.
2. Keep each regular file whose relative path passes the filter below.
3. For each, one line: `relativePath|sizeInBytes|microsecondsSinceEpoch`,
   where the path uses `/` separators and the microseconds are the
   modification date times 1,000,000, TRUNCATED to an integer.
4. Sort the lines as plain strings, join with `\n`, SHA-256, lowercase hex.

`SectionPublishState.fingerprint` is the reference. Note step 3's separator
and step 4's sort — a `List<string>` sorted with a culture-aware comparer
will not agree with Swift's, so sort ordinally.

### What counts, and why it is NOT read from the configuration

The obvious implementation reads `shared_folders`, `shared_files`,
`per_section_folders` and `per_section_files` out of `course_config.json`
and fingerprints those. It is wrong, and the reason is easy to miss:
`build_site.py` DISCOVERS new top-level folders during its preflight and
appends them to those lists AFTERWARDS. A folder the teacher made this
morning is a genuine input to the site and is not in the configuration
yet — so a configuration-driven fingerprint would be blind to it until the
next publish, which is the exact publish the marker exists to prompt.

So the rule is derived from what is on disk: everything non-hidden under
the course folder, minus

- another section's `section<M>/` folder (`section3` yes, `sections` and
  `section3b` no — those are folders a teacher is free to make),
- `node_modules` and the legacy non-hidden `merged_output`,
- `.DS_Store` / `Thumbs.db`,
- `course_config.backup.json` and any `*.tmp`.

**The How I Teach page (#209) is left out — under the fingerprint's RULE 2**
(since [#330](https://github.com/russellgordon/plantoir/issues/330),
2026-09-26). It never reaches a site, so editing it must not mark the section
"— Edited" or make the next Publish rebuild for nothing. But this list is a
wire format held byte for byte by three implementations that cannot change in
the same hour, so the change is VERSIONED rather than made
(`contracts/app-rules.json` → `publishedFreshness.fingerprintRules`):

- **Rule 1** is everything above. **Rule 2** is rule 1 less `How I Teach.md` at
  a reserved place — the top of the course, or the top of `section<N>/`
  (`HowITeachPage.isAtAReservedPlace` / `how_i_teach.is_reserved_place`, the
  same NFC-then-ASCII-only fold as `howITeachPage.matching`). Inside any other
  folder it is an ordinary page and counts; a look-alike counts.
  `filesCountedUnderRule2.cases` pins it.
- **The stamp says which rule it was taken under**: `fingerprintRule`, absent in
  every stamp written before #330 (and by Windows until it moves), which means
  1. The reader compares under the stamp's own rule; a rule it does not know
  counts as EDITED, as an unreadable stamp does. `stampRuleCases.cases` pins it.
- **Who computes what.** The mac: Swift, in-process, interactive and launchd
  alike — it never runs `section_fingerprint.py` — and it writes rule 2.
  Windows interactive: C#. Windows scheduled: `section_fingerprint.py`, run by
  the wrapper (`TaskScheduling.cs`), whose value the C# app records and later
  compares. So the coupling that must never break is C# ↔ Python, both on
  Windows — which is why **`section_fingerprint.py` takes `--rule 2` and KEEPS
  rule 1 as its default**: a rule-2 value compared by the C# app under rule 1
  would be a false "Edited" for every scheduled Windows teacher whose course
  has the page. Windows flips the C#, the wrapper and the stamp together, in
  one MUST issue. Do not "fix" the default on its own.
- **The property that keeps it safe:** for a course with no How I Teach page at
  a reserved place, rules 1 and 2 hash identically. So the upgrade costs
  nothing there; a course WITH the page shows "— Edited" once, on the first
  edit of that page after the upgrade (its stamp is still rule 1), and the
  next publish writes rule 2.
- **The accepted window.** A course folder shared by a Mac and a PC: the mac
  reads the PC's stamps correctly as rule 1; the PC reads the mac's rule-2
  stamps as if rule 1, a false "Edited" only for a course with the page, until
  the PC publishes. Windows alone is unaffected.

Rejected: changing all three unversioned (whichever lands second gives every
teacher with the page a false "Edited" until their next publish, and a shared
folder an argument that never settles); leaving the page out by its content,
frontmatter say (the fingerprint deliberately reads no page).

`course_config.json` itself COUNTS — fonts, the sidebar and the coverage map
are inputs to the built site as surely as a page is. `Media/` counts, because
it is symlinked into the build. `hidden_explorer_components*` counts, because
it decides what the sidebar shows.

Two of those exclusions are load-bearing rather than tidy, and both were
found by reading `build_site.py` rather than by testing:

- **`.publish_state` is hidden on purpose.** The stamp is written into the
  course folder at the end of a publish. Counted, every publish would end by
  declaring the section edited — an indicator permanently stuck on.
- **`course_config.backup.json` and `course_config.json.tmp`** are written
  by `_atomic_write_json_with_backup` during the build's own preflight,
  whenever discovery finds something new. Same failure, less often, and
  therefore harder to diagnose.

`contracts/app-rules.json` → `publishedFreshness.filesCounted` runs all
sixteen of these as data. Wire that up before anything else here; it is the
half most likely to drift.

### Symlinks — the defect this shipped with, found by adversarial review

`FileManager`'s directory enumerator neither follows a symlink nor reports
it as a regular file. The first cut of this dropped every such entry, so a
`Media` folder symlinked into the teacher's Obsidian vault — exactly the
arrangement `build_site.py`'s own `_ensure_media_symlink` sets up —
contributed nothing at all, and every change inside it read as "up to
date". `.NET`'s `Directory.EnumerateFiles` has the same shape of trap
(`FileSystemInfo.LinkTarget`, and `EnumerationOptions` does not recurse
into a directory link by default), so do not assume you have escaped it.

The rule now: resolve links by hand, ONE hop.

- A link to a FILE contributes its target's size and date, recorded under
  the LINK's own relative path.
- A link to a FOLDER is walked, with each entry's path prefixed by the
  link's path. Links inside that walk are not followed — one hop is what a
  vault arrangement needs, and refusing the second is what stops a link
  pointing at its own parent from walking forever.
- A BROKEN link contributes where it points, so that repointing or
  removing it is visible rather than silent.

### A course that publishes into itself

Nothing stops a teacher choosing `courses/ICS3U/site` as their "publish to
a folder on this computer" destination — `deployFolderProblem` checks only
that the path is a full one (#227), that the folder exists and that it is
writable. `deploy.sh` then writes the entire
built site there, INSIDE the folder being fingerprinted, so each publish
would differ from the last and the window would say " — Edited"
permanently. Exclude the configured local destination, and everything under
it, whenever it resolves to a path inside the course folder. Contract cases
in `publishedFreshness.selfPublishing`.

### When the stamp is written

In `MultiDestinationDeployRunner.run()`, and only when
`outcome.allSucceeded`. A course publishing to two hosts, one of which
failed, has NOT published, and its marker must stay up — that is the whole
point of having redundant destinations mean something.

**The fingerprint is taken when the FIRST upload begins, not when the last
one ends.** A publish takes minutes; a page the teacher edits while it
uploads did not go out, and stamping the finishing state would mark that
edit as published. That is the one direction this feature must never fail
in: an early marker costs a needless publish, a late one costs a class that
never saw the page.

**It is taken before the BUILD, not merely before the first upload** — the
build is the longest part of a publish and the part that actually reads the
content. The first cut took it after the build and was wrong; the review
caught it against this document's own wording.

The cost of taking it that early is real and was accepted: `build_site.py`'s
preflight appends newly discovered folders to `course_config.json`, so a
publish that discovers one ends with the section still marked edited. That
is true rather than spurious — the teacher did add a folder — and it clears
itself at the next publish, when there is nothing left to discover. The
alternative hides a real edit, and this feature must not fail in that
direction.

### A scheduled deploy needs its own path to the same record

The other half the review found. A scheduled deploy does not go through the
deploy runner at all: launchd runs a generated shell script, so the flagship
"publish tomorrow's class overnight" feature published perfectly and left
the title bar saying " — Edited" until somebody published again by hand.

On the mac the fix was cheap because the agent ALREADY launches the app
binary rather than `/bin/bash` (for an unrelated and much sharper reason —
a bare interpreter has no application identity, so macOS grants it no
access to a working folder on the Desktop). So:

1. The plist's arguments carry `--scheduled-section <workspace> <CODE> <N>`.
2. The app fingerprints the section BEFORE running the script.
3. The script tracks each destination's own result — `ALL_OK`, deliberately
   not `&&`-chaining, since one destination failing must not stop the
   others — and on total success writes a sentinel file naming where it
   went.
4. After the script exits, the app records the publish if the sentinel is
   there, and consumes it either way so tonight's failure cannot read as
   tomorrow's success.

The sentinel exists because the script ends by booting its own launchd
agent out, so the script's exit status belongs to `launchctl` and not to
the deploy. Whatever Windows uses for scheduling (Task Scheduler) needs the
equivalent: something the scheduled run can say "every destination
succeeded" with, that is not its exit code.

**Done on Windows, 2026-08-22** (`GUI-IMPROVEMENTS.md` row 323). Windows'
version of the same shape, adjusted for the one real difference: Task
Scheduler runs `powershell.exe` directly rather than the app binary, so
there is no in-process C# alive at the moment the deploy actually happens
to fingerprint the section from.

1. `TaskScheduling.Schedule` always writes a wrapper `.ps1` now (previously
   only for 2+ destinations) — the wrapper is where all of this lives.
2. The wrapper fingerprints the section itself, before running any
   destination's `deploy.ps1`, via the app's own bundled Python
   (`scripts/section_fingerprint.py` — see that file for why this is a
   THIRD copy of the algorithm rather than reusing the C#). Fingerprinting
   happens at RUN time, not at schedule time, on purpose — see the rejected
   alternative below.
3. Each destination's `deploy.ps1` line is run un-chained (same "redundancy"
   rule as the mac), tracking `$allSucceeded` in the wrapper's own
   PowerShell state rather than an `ALL_OK` file convention — there is no
   equivalent of launchd booting its own agent out here, so the wrapper's
   own exit code would actually be trustworthy, but the sentinel is written
   regardless, to keep the two platforms' shapes matching and because the
   app still needs SOMETHING durable to read on next launch.
4. Only if every destination succeeded, the wrapper writes a JSON sentinel
   under `%LOCALAPPDATA%\Plantoir\scheduled\pending\` — course code, section,
   course directory, fingerprint, destination types/names, and a UTC
   timestamp.
5. `ScheduledDeployCompletion.ConsumePending()` — called from `MainWindow`'s
   `Activated` handler, subscribed before any `SectionDetailView` exists so
   it runs before that view's own marker refresh on the SAME activation —
   applies every pending sentinel (`SectionPublishState.RecordPublish` +
   the `SectionContentMarkedPublished` trail event, reusing the existing
   event rather than adding a new one) and deletes it either way, so a
   sentinel that failed to apply cleanly cannot sit there being reread
   forever, or be mistaken later for a deploy that never happened.

**Rejected: fingerprinting at SCHEDULE time instead of RUN time.** Far
cheaper — the app already has everything it needs in C# the moment the
teacher clicks Schedule, so this could have been a small addition to
`TaskScheduling.Schedule` with no Python involved at all. Rejected because
it is wrong in the direction that lies to the teacher: an edit made to the
section between scheduling it and the overnight run still goes out
correctly (the deploy publishes whatever is on disk at run time), but a
schedule-time fingerprint would stamp the STALE, pre-edit fingerprint —
so the marker would say "— Edited" about content that had, in fact, just
published. Fingerprinting at run time, in the wrapper, right before the
deploy — the same moment the mac's launchd path fingerprints — is the only
version that is correct either way, hence the third Python copy of the
algorithm rather than a cheaper C#-only shortcut.

### One false negative, written down so it is not a surprise

Restoring a page from a backup that preserves its modification date, where
the length happens to be unchanged, reads as UP TO DATE. `cp -p`, `rsync
-a`, unzipping and Time Machine all preserve modification dates. This is
the price of never reading file contents, which is what makes the check
cheap enough to run whenever a window comes to the front, and the cure —
hashing every byte of every page — costs more than the marker is worth.
Publishing is never blocked by the marker, so a teacher who suspects it can
simply publish. It is a contract case (`whenShown`) so that nobody
"discovers" it later and treats it as a bug.

### What is shown

`base` is the existing title (`ICS3U-S1`); the marker appends `" — Edited"`
— em dash, spaces either side, capital E, all of it Pages'. Contract cases
in `publishedFreshness.marker`.

**A section that has never published shows NO marker.** Pages does the
opposite (`Untitled 3 — Edited` on a document never saved), and it was
rejected here on purpose: a marker that is on for every new course from the
moment it is created is a marker teachers learn to ignore, which costs the
one it is for. An unreadable or corrupt stamp is treated identically to no
stamp, so a course predating this feature is quiet rather than shouting.

### One accepted imprecision, so nobody "fixes" it

A course-level page shared by every section marks EVERY section edited —
even though editing only `publishForSection3` in fact changes only section
3's site. Being exact means parsing the frontmatter of every shared page on
every check, which is reading files, which is the cost the whole design
avoids. The wording was chosen to stay true either way: a page this section
uses, or shares, has changed. It is early, not wrong.

### The refresh triggers, and the watcher NOT built

The mac recomputes on four events: the window appearing, the app becoming
active, this window becoming key, and a run finishing. Note that
`NSWindow.didBecomeKeyNotification` fires for EVERY window and panel in the
app — the assistant, a settings sheet, an alert — and app activation fires
alongside it, so several walks really can be in flight at once. Each
refresh therefore carries a generation number and a result is applied only
if it is still the current one; without that, a walk begun before a publish
can land after one begun afterwards and re-assert " — Edited" about a
section that has just gone out. Whatever Windows uses for its own
activation events needs the same guard.

Never on a timer, and never from `body` — a view that recomputed it while rendering
would walk the course folder every time a console line arrived during a
publish. The walk runs off the main thread, so a course on a slow network
volume cannot stutter a window coming to the front.

An FSEvents stream over the course folder was considered and deliberately
NOT built, on either platform. Neither app runs one today, the marker only
matters at the instant somebody looks at the title bar, and a watcher is a
cost paid continuously for an answer wanted occasionally. If the
on-activate refresh ever feels stale in practice, that is the moment to add
one — for the frontmost course only, coalesced — and not before.

Windows owes its own equivalents of the two mac-specific pieces: setting
the window title (WinUI does it on the window, not through a
`navigationTitle` modifier) and the activation events.

### The trail

New event `section content marked published`, in `ActivityTrail.Event` and
in `shared-rules.json` → `activityTrail.mustRecord`. It matters more than a
routine line because the marker is DERIVED: its presence and its absence
look identical on disk, so "it still says Edited after I published" has
nothing to look at without it. The line also records that the publish
succeeded at EVERY destination rather than merely at one.

## Built websites live outside the working folder

**Windows did this first, in row 290, and the mac caught up on 2026-09-05.**
This section exists because the mac's answer looks nothing like Windows', and
somebody reading the two side by side will wonder which is right. Both are: the difference is
the machinery, and copying either one onto the other platform would be a
mistake.

### What changed on the mac, and what it did NOT change on Windows

A section's built site used to be written to `courses/<CODE>/.merged_output`,
inside the working folder. It is derived — every file comes from the teacher's
notes and can be produced again — and Plantoir's own backups already skipped it
by name, but nothing OUTSIDE Plantoir did: a synced folder uploads every build
and charges it against the teacher's quota, Time Machine backs it up, a zip or
a Finder copy of the course carries it, Get Info counts it.

Measured on the small `EXC2O` course the mac's verification suite builds:
**331 files and 9.8 MB for one section**, and the cost is paid on EVERY build
rather than once, because Quartz emits its whole output fresh each time and the
mirror copies every file that has a new timestamp. A real course with media is
many times that.

**Windows is unchanged and should stay unchanged.** `PLANTOIR_BUILD_ROOT` →
`%LOCALAPPDATA%\Plantoir\builds\<folder id>`, honoured by
`scripts/toolchain_paths.py` → `merged_output_root()`, which does not nest a
`.merged_output` level when the variable is set. That flat layout is already
pinned by `scripts/test_deploy_course_dir_resolution.py` and is the reason
`deploy.py` derives the course directory from `COURSES_ROOT / <code>` rather
than by climbing from the built section — Windows' fix, and the shape this
piece reused.

### Why the mac could not just set the variable

Three reasons, and each of them is a mac fact:

1. **The build runs in a container that mounts only `courses/`.** A build root
   outside the working folder is invisible in there until a second mount
   exists — and `preview.sh`'s "does this container need recreating" check
   compared only the courses mount, so an added mount needed its own recreate
   rule as well.
2. **Six readers name the path today**, on both sides of the mount:
   `deploy.sh` (`MERGED_DIR_HOST`, `SECTION_DIR_IN_CONTAINER`), `preview.sh`
   (`OUTPUT_PATH`, and stop mode), and in Swift `BuildFreshness`,
   `ScheduledDeploy` and `SectionDetailView` — plus the shell freshness check
   `ScheduledDeploy` WRITES OUT for launchd, `verify.sh`, `verify-deploy.sh`
   and the screenshot harness.
3. **A launchd deploy and a teacher at the command line have no app.** If the
   app set a variable and they did not, the two would build into different
   places and `BuildFreshness` would call every build stale.

So: `courses/<CODE>/.merged_output` is a **symlink** to
`~/Library/Application Support/Plantoir/builds/<folder id>/<CODE>`, and the
launchers bind-mount that builds folder into the container **at the same
absolute path**, unconditionally, so the link resolves identically inside and
out and all six readers keep working untouched. The folder id is the same
`/bin/pwd -P | shasum -a 256 | cut -c1-8` that already names the folder's
container — the disk's own spelling of the folder, so a folder reached in
another case or Unicode form is still one folder (#189; [03](03-launcher-scripts.md)
→ "One folder, one spelling") —
so a folder's container and its builds folder cannot disagree about which
folder they belong to. It has to be under `$HOME` because the Colima VM mounts
only the home folder.

**Done for every working folder, not only the synced ones.** The benefit is not
confined to syncing — a backup, a copy, a zip and a folder size are all smaller
for it — and one code path is one code path: a rule that ran only for folders
Plantoir believes are synced would be a rule tested in one case and running in
another, and the detection is deliberately not certain enough to hang behaviour
on.

### Rejected, so nobody re-proposes them

- **One environment variable, as on Windows.** The three reasons above.
- **Computing the path at every reader.** Ten places name it; each one is a
  chance for two of them to disagree, and the failure mode of disagreeing is a
  publish that ships the wrong bytes.
- **A `.nosync` suffix.** iCloud-only — Dropbox and OneDrive ignore it — and it
  moves the path just as much as this does.

### What was MEASURED rather than read

The open question was whether a sync client would follow the link and upload
the target anyway, which would have defeated the whole thing. Tested on a real
Mac on 2026-09-05, giving a real iCloud Drive folder and a real
`~/Library/CloudStorage/Dropbox` a throwaway course folder holding a real note
and a `.merged_output` symlink to an outside folder with a 3 MB file in it:

- **iCloud** kept it as a link and reported the LINK as uploaded, at **82
  bytes** — the length of the target path — with `isUbiquitousItem` true and
  the 3 MB nowhere.
- **Dropbox** kept it as a link, tagged the LINK with its own extended
  attributes, and left the target folder outside Dropbox with none at all, so
  it had not reached through it.
- `du` of the synced folder counted 4 KB either way.
- **OneDrive is not installed on that Mac and was not tested.** If you can
  test the Windows equivalent cheaply it is worth knowing, even though your
  layout does not depend on it.

The consequence is worth knowing on both platforms: the LINK syncs, so a teacher
with two Macs receives one naming a home folder that does not exist there. A
link pointing anywhere other than this machine's own builds folder is replaced
before anything builds.

### The finding nobody had listed, and the one that belongs to both apps

**Archiving, restoring or replacing a course removes the link, but not the
build standing outside it.** And a course restored from a backup carries the
timestamps it had when it was archived, which can be OLDER than the site that
was built from it. So an adopted build would read as "already up to date" and
publish last month's pages, with every check agreeing. The rule that answers it
is one line: **a build folder with no link pointing at it is CLEARED, never
adopted** — the link is what says a build belongs to this course. Archiving a
course or a section discards its build outright as well, so the clearing is a
safety net rather than the only defence. Renaming a course is the exception:
its build is carried across, because a rename used to cost nothing and should
still cost nothing.

**The Windows layout has the same hole in a different shape.** There is no link
there, so the "no link means clear it" rule cannot be copied — but
`%LOCALAPPDATA%\Plantoir\builds\<id>\<CODE>` outlives an archived course
exactly the way the mac's did, and a restore into that code will find it. Worth
checking; worth writing down either way if it turns out a platform is already safe,
because "we checked and it cannot happen here" is as useful as a fix.

**And a builds folder for a working folder that no longer exists is litter
nobody can name**, because the id is a hash and cannot be read backwards. The
mac writes `working-folder.txt` beside each builds folder and sweeps the ones
whose folder is gone — **only when that path was under the home folder**, since
"the folder is not there" and "the disk is not plugged in" look identical from
there and only the home volume is always mounted. You have the same problem and
can use the same answer.

### What an adversarial review found afterwards, and what travels

Row 403. Three of the thirteen findings are worth your attention rather than
just ours:

- **An access DENIAL must never read as "the folder is gone".** The launch
  sweep asked `fileExists`, which answers false for a folder Plantoir is not
  ALLOWED to look at exactly as readily as for one that has been deleted — and
  a working folder on the Desktop or in Documents sits behind a permission
  grant that can be absent at launch or reset by a re-signed build. Every
  launch would have deleted that folder's built websites. It asks `lstat` now
  and treats only `ENOENT`/`ENOTDIR` as deletion. Whatever you use before
  deleting a builds folder, ask the same question of it.
- **A test that matches a function's DEFINITION passes on a launcher that never
  calls it.** The contract test here matched the strings
  `container_has_builds_mount` and the mount flag — both satisfied by the
  definition and a comment — and `setup.sh` had no call site at all and passed
  anyway. Assert the CALL, on its own line.
- **If anything other than the app can move build output, it owes the trail
  the same line.** Only the app recorded the move, so a move done at the
  command line, or by a publish launchd ran at six in the morning weeks before
  the app was next opened, left no line ever. The launchers append it
  themselves now.

A fourth finding was made, acted on, and then REVERSED by the next review, and
the reversal is the part worth carrying: it was proposed that a link naming
ANOTHER Mac's builds folder should let this Mac ADOPT its own existing build
rather than clear it, saving a rebuild on every switch between two machines.
That is unsafe. A Mac cannot tell "the folder came back unchanged" from "the
folder was archived and restored while I was shut", and in the second case the
pages it would adopt a build for are OLDER than that build — so the freshness
check says up to date and the teacher publishes what they undid. Clearing costs
one rebuild, which is cheap and visible. **The general rule, which holds as
much as ours: never adopt a build you cannot prove belongs to the content as it
now stands.** A generation stamp — a UUID written beside the link and copied
into the build, adopted only when the two match — would buy both, and is
written down in the contract as the design to build if it is ever worth it.

And one that cannot happen to you at all, noted so nobody goes looking: your
build root is per-machine and never travels, so there is no foreign link to
read.

The second review also found the trap worth remembering about TESTING any
"we put it back" branch: the first version of the test made the course folder
read-only, which fails the MOVE rather than the link, so the branch never ran
and the test passed with the put-back deleted. Fail the step in the MIDDLE, and
re-check by putting the fault back.

### Two mac-specific traps, recorded because they cost time

- **`preview.sh --stop` finds a preview's processes by WORKING DIRECTORY**, and
  `/proc/<pid>/cwd` is the RESOLVED path — never the spelling a process used to
  get there. The sweep had to learn the resolved form as well, or `--stop`
  would report success and leave the build running. Your `--stop` uses
  `Win32_Process` on command lines and paths; if any part of it compares a path
  the teacher's process arrived by rather than the one it is in, it has the
  same bug waiting.
- **`shutil.rmtree` refuses a symlink**, which the research had flagged as a
  blocker for `--full-rebuild`. It turned out not to matter: that path removes
  the CONTAINER's `/tmp/quartz-builds` tree, not the host output. Written down
  because the research said otherwise and somebody will read it.

### The one thing a release note must carry: BOTH Macs have to be updated

A working folder synced between two Macs now needs both of them on this version
or later, and this is not a nicety. The mac's OLD `build_site.py` fails outright
on a link whose target is missing — `mkdir` raises `File exists` — and nothing
that shipped before 2026-09-05 can repair it. It is worse than one stale machine
failing on its own, because the launchers and `.toolchain/` live INSIDE the
synced folder: an older app "refreshes any launcher that differs" back to its
own copies, and a publish scheduled with launchd on the up-to-date Mac then runs
whatever `deploy.sh` is in the folder that morning — an old one recreates the
container without the mount and fails the same way. Before this change a version
mismatch between two Macs was harmless.

The lesson is portable even though the mechanism is not, and it is worth asking
before assuming a platform is clear: **what does an OLD
`plantoir-mcp.exe`, or an old app, do with a working folder a NEW one has
touched?** The answer here was "it cannot recover, and it drags the good machine
back with it".

### The upgrade path, which is the part that ships to real teachers

Everything a teacher already has survives, and nothing is one-way: the built
site is MOVED, never rebuilt from scratch and never deleted; `.netlify_sites/`
and `.cloudflare_sites/` are untouched because they live BESIDE
`.merged_output`, not inside it; the launchd scripts already written out keep
naming the old path and keep working through the link; and a container without
the mount is recreated once, which a toolchain change does anyway.

The rule that makes it safe is worth stating plainly, because either platform will
need the same discipline whenever you change where builds go: **every step is
allowed to fail without stopping the run, and the fallback is the OLD
behaviour.** The mac launchers run under `set -euo pipefail`, so an unguarded
`ln`, `mv` or `mkdir` would have turned "the built website could not be moved"
into "publishing is broken", silently, on a read-only folder or a full disk. If
the move succeeds and the link then fails, the move is put BACK — a course with
its site in the old place still publishes; a course with neither has lost its
website for nothing.

`scripts/test_build_output_link.sh` runs the real launcher block against every
one of those states and is wired into `verify.sh`. It is shell rather than
Python, so it does not run on Windows, but the STATES it lists are the ones
worth checking on any platform that moves build output.

---

[◀ Previous: Course Setup](04-course-setup.md) · [Back to index](README.md) · [Next: Quartz Customizations ▶](06-quartz-customizations.md)

## Which file each page came from (#518)

Every build of a section — a preview AND a publish — writes
`.page-sources.json` into the section's built output, beside `public/` and
`.visible-pages.json`, never inside `public/`, so no deploy uploads it. It
maps each address Quartz serves (the page's slug below the site's root) to the
file in the course folder it was made from, as a POSIX path with its `.md`,
and whether students see it. Open in Obsidian reads it to open the page a
section's preview shows (`09-mac-app.md` → "Open in Obsidian opens the page
the preview shows (#518)"). Format: `contracts/file-formats.json` →
`pageSourcesList`.

**Where and when.** `_write_page_sources` runs immediately before the
`if build_only:` branch that either builds for publishing or serves the
preview — after My Progress, the How I Teach sweep, the #246 hiding and every
other pass that adds or removes a page — so the list matches what Quartz
reads. It has to be before the branch: the serve branch never reaches the
publish-only `_write_visible_places`, and a preview is exactly when the list
is wanted. Atomic (`_write_json_atomically`), and a failure to write it
prints a warning and never fails the build: without it the app opens the
section as before. In the ALWAYS part of the build, so every existing folder
gets it on its next build.

**What it is made from.** `_vault_sources`, which the content copy already
fills for the date pass (#275). Per entry: `page_slug_as_quartz_serves`
(`_quartz_page_slug`, plus Quartz 4.5.0's two departures measured 2026-10-21
on 38 names — only an exact `.md` is a page, and a last segment `_index` is
`index`; `obsidianOpensThePreviewedPage.slugCases`); two files making one
address are written `{collided: true}` with no file; a page the build made
(My Progress, a coverage map), a file no longer there and one outside the
course folder after links are followed are left out; `hidden` is the build's
own `_is_draft`. The front page's entry gains `shows` when the teacher's
`section<N>/index.md` — read from the teacher's file, not the build's copy,
which gains a title and may gain the section marker — is nothing but a single
`![[…]]` line below its settings, naming exactly one page (Russell's ruling
1: open the class the front page shows), and with it `showsHidden`, the
build's `_is_draft` of THAT class page: the front page can be visible while
the class it embeds is hidden, and the trail's "(hidden from students)" is
said of the file that opens, so the front page's own `hidden` cannot stand
in for it (#518 implementation review).

**One correction, one trap left alone.** The per-section folder copy credits
EVERY file under a folder it copied to the section, so when a folder name is
both shared and per-section, a shared page copied there first is credited to
a section file that does not exist. The list names the shared file at the
same place instead. The record itself (`_vault_sources`, which the date pass
also writes back through) is unchanged; that trap is a toolchain issue of its
own (#518's plan, recommended for v2.0.0).

**Measured against Quartz itself.** `scripts/test_page_sources.py` runs the
slug cases and a course copied the way the build copies it, in the image
under `verify.sh`; then `verify.sh` reads the real EXC2O build's list back
(`--site`) and requires a `public/<slug>.html` for every listed page students
see, and every listed file in the course folder.

**Rejected:** writing it only in a publish (a preview is the case it is for);
comparing its `buildId` with the preview's (the app never learns which build
a preview shows, and `.build-id` moves on Rebuild Preview before the list
does — diagnosis only); keeping it inside `public/` (every deploy route ships
`public/`).

## `Media` is mirrored WHOLE, so a picture is uploaded before its page is

Every build copies the course's `Media` folder into the build tree entire —
not the subset the published pages happen to name. So a picture that arrives
in `Media` is in the next deploy's `public/Media` whether or not any visible
page shows it.

That has always been true of anything a teacher drops in there by hand.
Since 2026-09-21 it is also true of something Plantoir puts there on their
behalf: "Copy a Page from This Course…" (issue #207) copies a page's pictures
and files into the destination's `Media`, and the page itself arrives HIDDEN.
Measured on a real build of a real course: none of the copied pages appears in
the built site — zero occurrences of any of their titles across 282 rendered
pages — while the two PDFs and the 1.1 MB picture they brought ARE in
`public/Media`.

This is not a regression and it is not a leak of anything a student can find
by reading the site: nothing links to those files until the page is published.
It is written down because "why is last year's PDF on my site already?" is a
question somebody will ask, and the answer is a rule about `Media` rather than
anything the copy did.

A GeoGebra sketch named by `file:` (#578) is the one file Copy a Page leaves
behind: the fence's `file:` line is plain text, not a link or an embed, so
the copy does not see it and the copied page's sketch is `fileNotFound`
until the `.ggb` is put in the destination's `Media` (where the build's
lookup finds it by its name alone) or the line is changed.
