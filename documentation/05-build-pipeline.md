# 5. The Build Pipeline (`build_site.py`)

[◀ Previous: Course Setup](04-course-setup.md) · [Back to index](README.md) · [Next: Quartz Customizations ▶](06-quartz-customizations.md)

`scripts/build_site.py` (~4,300 lines) is the engine of the toolchain. Given
a course code and section number, it assembles a complete, customized Quartz
site and either serves it (preview mode, the default) or builds it statically
(`--build-only`, used by deploy).

To achieve maximum performance across all host operating systems (especially
Windows WSL2 and macOS Colima/Lima mounts), the pipeline uses a **dual-workspace
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
   times); Windows' `BuildFreshness` owes the same. The reasoning and what was
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
the page is hidden in every section whatever it said. The teacher's own file
is never touched — this runs on the copy in `content/`, which is deleted and
re-copied on every build, so the rule is ALWAYS-section by construction and
existing course folders pick it up without `--full-rebuild`; and
`_write_the_date_back` already refuses a source it cannot parse.

Then, once per section build, ONE `pageSettingsUnreadable` site-health finding
names every such page (at most ten, then "and N more"), each with the line the
reader stopped near where it can tell. Its words are
`contracts/shared-rules.json` → `siteHealth.checks[pageSettingsUnreadable]`;
the cases are `unreadablePageSettings.cases`, run by
`scripts/test_unreadable_page_settings.py` through the real
`process_frontmatter`, and by `check_visibility_against_the_site.py` on down
through Quartz's own reader to the site. It is never offered a repair
(`siteHealth.repair.neverOffered`): rewriting a teacher's settings means
guessing what they meant. It reaches the trail through the existing `folder
problem found` line, which carries the check's NAME and never a page's.

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
  pointer's job.
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
  folder's index, Key Links or Curriculum Coverage. A page two links away is
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
  followed by an alias did not match at all, and a page a class linked to only
  that way was reset to the course's FIRST class date by the first pass instead
  of taking its class's. **That changes dates in teachers' vaults on the next
  build after #294 ships**, in every existing folder, because both passes run
  on every build and rewrite the teacher's files: such a page moves from the
  first class's date to its own class's. It is the right change, and not only
  because the link is a link: the mac app's re-date already read `[[P#h|a]]`
  as a link to P (its name stops at `#`), so until #294 the app and the build
  disagreed about those pages and the build won by overwriting on every build.
  Measured: 0 such links in the shipped payloads and skeletons, so no shipped
  page moves; teacher-written ones will. No log line changes and none becomes
  untrue — "Gave N of your page(s) the date of the first class that links to
  them" and the first pass's "Synced non-class pages" line count whatever
  moved, as they always did. The install-time readers in
  `setup_course.py`, and the curriculum-coverage patterns (which already read
  `\|` but share the old group order), are
  [#314](https://github.com/russellgordon/plantoir/issues/314).
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
a teacher's expectation pages — `_find_curriculum_folder` wants a page named for
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
`_find_curriculum_folder` found a folder and `_collect_expectations`
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
  that keeps Netlify uploads small.
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
and a `--build-only` run that mirrored nothing prints "Nothing to publish …
it has no front page, so no website was produced" and **exits non-zero**. That
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
