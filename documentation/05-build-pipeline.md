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
discovered folder is also taken OUT of `hidden` if it is listed there
and added to `expandable`, so it appears with a chevron like any other. The updated config is written atomically
with a `course_config.backup.json` safety copy.

**The one thing discovery does not do is re-add what the teacher took away.**
Names the teacher removed in Course Settings are recorded in `excluded_items`
(keyed `shared` / `per_section`), and preflight skips them: not discovered, not
un-hidden, not expanded, and — since 2026-08-24 — actively **dropped** from
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

### Curriculum date synchronization

Pages listing folder contents in Quartz sort by date, and this toolchain
[configures dates to mean *created*](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)
(from frontmatter, never from git). Curriculum-expectation pages are written
once at course setup and never touched again, which would leave them sorted
to the bottom of list pages forever. The build therefore finds the **newest
`created` timestamp anywhere in the section's content**, then bumps every
file inside any folder whose name contains "curriculum" up to that
timestamp (only if older). Curriculum pages thus float alongside current
content without the teacher ever editing them.

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

Two of the checks stay quiet unless the other half of the map exists: a
brand-new course has an empty curriculum folder and an empty class folder on
day one, and warning about both would nag every build of a course nobody has
broken.

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

- **Do not read the findings from a tail.** Every other structured-line reader in
  the mac's `ScriptRunner` works from `recentText(maximumCharacters: 8000)`, and
  the health lines print in the MIDDLE of a build. On any real build they are
  long past that window by the end. Collect them as output arrives. The mac test
  floods 400 lines after the finding to prove the point.
- **Hide the marker line from the console a teacher reads.** A raw JSON blob is
  machinery (rule 1). The human sentence is printed separately, so nothing is
  lost. The mac drops it in `TranscriptBuilder`, and reads findings from the raw
  text BEFORE handing it there.
- **Show it once.** The mac holds findings in view state rather than reading them
  off the runner at render time, so a teacher who dismisses the dialog and
  carries on editing does not meet it again on the next redraw. A healthy course
  must see nothing at all — the failure mode for this whole feature is nagging,
  and a warning dismissed by habit is dismissed when it matters.

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
that the folder exists and is writable. `deploy.py` then writes the entire
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

**You did this first, in row 290, and the mac has now caught up.** This section
exists because the mac's answer looks nothing like yours, and somebody reading
the two side by side will wonder which is right. Both are: the difference is
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

**Your side is unchanged and should stay unchanged.** `PLANTOIR_BUILD_ROOT` →
`%LOCALAPPDATA%\Plantoir\builds\<folder id>`, honoured by
`scripts/toolchain_paths.py` → `merged_output_root()`, which does not nest a
`.merged_output` level when the variable is set. That flat layout is already
pinned by `scripts/test_deploy_course_dir_resolution.py` and is the reason
`deploy.py` derives the course directory from `COURSES_ROOT / <code>` rather
than by climbing from the built section — the fix that was YOURS, and the shape
this piece reused.

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
`pwd -P | shasum -a 256 | cut -c1-8` that already names the folder's container,
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

**Your layout has the same hole in a different shape.** You have no link, so
the "no link means clear it" rule cannot be copied — but
`%LOCALAPPDATA%\Plantoir\builds\<id>\<CODE>` outlives an archived course
exactly the way the mac's did, and a restore into that code will find it. Worth
checking; worth writing down either way if it turns out a platform is already safe,
because "we checked and it cannot happen here" is as useful to this side as a
fix.

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
