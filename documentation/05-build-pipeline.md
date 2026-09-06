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

## Stage 1: Validation and preflight discovery

After checking that the course, section folder, and `course_config.json`
exist, and that the requested section is one of the course's
`section_numbers`, the script performs **preflight discovery**:

<a name="preflight-discovery"></a>

It scans the course root and section folder for top-level folders/files that
are *not yet listed* in `course_config.json` and appends them. The four copy
lists are add-only — nothing is ever removed from them automatically — but a
newly discovered folder is also taken OUT of `hidden` if it is listed there
and added to `expandable`, so it appears with a chevron like any other. The updated config is written atomically
with a `course_config.backup.json` safety copy.

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

Two of the checks stay quiet unless the other half of the map exists: a
brand-new course has an empty curriculum folder and an empty class folder on
day one, and warning about both would nag every build of a course nobody has
broken.

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

---

[◀ Previous: Course Setup](04-course-setup.md) · [Back to index](README.md) · [Next: Quartz Customizations ▶](06-quartz-customizations.md)
