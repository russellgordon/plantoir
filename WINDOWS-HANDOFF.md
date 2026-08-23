# Windows App — Handoff

> **New to this side? Read [`WINDOWS-BOOTSTRAP.md`](WINDOWS-BOOTSTRAP.md)
> first.** It says what to read, what to do in what order, and asks you to
> outline the plan before implementing. This file is the reference it sends
> you to.

Read this first when working on the Windows app — `windows-app/`, WinUI 3,
first take built 2026-08-11 — and especially when syncing it after a run of
macOS-side sessions. It gathers everything a Windows implementation needs; the
deep dives it links to are kept current. **Do not work through it top to
bottom.** Start with "Where Windows actually stands" immediately below for the
genuinely outstanding work, and use `GUI-IMPROVEMENTS.md`'s **Windows status**
section for the per-entry detail behind it.

**A large amount of what used to be tracked here has shipped.** This file was
pruned on 2026-08-22 after a code-level pass (not just a read) confirmed that
most of the work an earlier "ordered work list" described as outstanding is
now actually in `windows-app/` — contracts wired into `Plantoir.Tests`, the
deploy-approval wording, the preview-stop-before-deploy await, the activity
trail, the problem report dialog and redactor, `add_next_class` /
`plan_remember_timetable`, the `LinkGraph` exclusions, `assistantConfirmation`,
the `ReDatePlan` overflow fix, the schedule-asking flow, course renaming, the
native (non-container) local model, the assistant-choice Settings panel, the
credential dialogs, `AutoFillCourseName`'s `names.Short` fix, the Curriculum
Coverage explainers toggle, subject skeletons, and `SectionAdder`'s
course-level page extension. Those write-ups have been moved verbatim to
[`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md) — read them
there if you need the reasoning behind something that already shipped; this
file now holds only what is still genuinely open, plus reference material that
was never a task in the first place.

## Where Windows actually stands (read from the code, 2026-08-22)

**Read this before planning.** `WINDOWS-BOOTSTRAP.md` § 0 asks you to write a
plan before touching anything, and a plan needs to start from what is TRUE on
this side rather than from what the rest of this file describes. **If you find
one of the items below already done, or one of the "done" claims above wrong,
that is a defect in this section** — say so in `MAC-HANDOFF.md`, the same way
this side is expected to say so when the contract is wrong.

### What is still genuinely outstanding

1. ~~A Preview item in a menu bar~~ — ✅ Done 2026-08-22. `MainWindow.xaml`
   gained a top-level "Preview" menu (Back / Forward / Reload Page) between
   File and Help, mirroring `mac-app/QuartzTeachers/App/PreviewCommands.swift`.
   It tracks whichever `SectionDetailView` is currently shown in `DetailHost`
   via a `PreviewChromeChanged` event (raised at the end of `RefreshChrome`)
   rather than polling, and enables/disables exactly as the toolbar
   Back/Forward/Reload buttons already did. **The shortcuts are also truly
   global, matching mac's ⌘[/⌘]/⌘R** (a first pass shipped the menu with
   display-only accelerator text and left this as a known gap; fixed the same
   day once flagged): `MainWindow`'s root Grid now declares its own
   `Ctrl+R`/`Alt+Left`/`Alt+Right` `KeyboardAccelerator`s, identical in
   combo to the pre-existing ones scoped to `SectionDetailView`'s own Grid.
   WinUI 3 resolves a duplicated combo by bubbling from the focused element
   up the visual tree and invoking the first one found — confirmed against
   Microsoft's own "Resolving accelerators" documentation, not assumed — so
   the section-scoped accelerator wins whenever focus is inside the preview
   (and no-ops there without marking the event handled when its guard, e.g.
   `Preview.CanGoBack`, is false, letting the root-level one take over), and
   the root-level one fires from anywhere else (sidebar, path bar). No
   duplicate-registration exception, no double `Reload()` from this scoping.
   Two adversarial sub-agent reviews confirmed this in sequence: the first
   pass (build clean, no leaked `PreviewChromeChanged` subscriptions across
   repeated `DetailHost.Content` swaps, no null-ref risk against a torn-down
   `WebView2`, no collision with `Ctrl+Shift+R` for Reload Courses) surfaced
   the shortcut-scope gap; the second, after the fix, verified the bubble-
   resolution claim against Microsoft's documented algorithm rather than
   trusting the code comment. One residual, PRE-EXISTING and unrelated to
   this change: `WebView2` has a known interop quirk
   (`microsoft-ui-xaml` #6231, WebView2Feedback #1884) where an accelerator's
   `Invoked` can fire twice ~100ms apart when focus is literally inside the
   rendered page content — low severity since `Reload()`/`GoBack()` are
   idempotent, but worth a manual smoke test (press Ctrl+R with a click
   actually inside the preview's page, not just its surrounding chrome) once
   at the machine.

2. ~~The " — Edited" title-bar marker~~ — ✅ Done 2026-08-22 for the
   INTERACTIVE deploy path. `Plantoir.Core/Models/SectionPublishState.cs`
   ports the mac's fingerprinting algorithm (exclusion filter, one-hop
   symlink resolution, self-publishing exclusion — case-insensitively, see
   below) and the `.publish_state/section<N>.json` stamp read/write.
   `MultiDestinationDeployRunner.RunAsync` fingerprints before the build and
   records the stamp (and the `section content marked published` trail
   event, newly added to `ActivityTrail.Event`) only when every configured
   destination succeeded, written before `IsRunning` flips to false so a
   listener refreshing on "run finished" never sees a stale stamp.
   `SectionDetailView` has no per-section OS window — one `MainWindow` shows
   one section at a time — so the marker is applied to the in-pane
   `SectionTitle` header instead, which is this app's equivalent of the
   mac's per-section title bar; `TitleText` (bare, no marker) is untouched
   and still used everywhere a sentence NAMES the section. Refreshes on the
   pane being constructed, `MainWindow.Activated`, and either runner's
   `IsRunning` going false, each off the UI thread and guarded by an
   incrementing generation counter so a stale walk can't overwrite a fresh
   one. Contract-driven tests in `SectionPublishStateTests.cs` (15, all
   green) run the same `contracts/app-rules.json` → `publishedFreshness`
   case list the mac suite runs. Two adversarial-review passes: the first
   caught nothing new (ordering, generation guard, exclusion filter, symlink
   one-hop, atomic stamp write all checked out); a second, narrower pass
   found and fixed a genuinely Windows-specific bug the mac's own filesystem
   never surfaces — `SectionPublishState.IsExcluded` compared the
   self-publishing exclusion path case-SENSITIVELY, so a destination folder
   whose on-disk casing differs from what a teacher typed (NTFS is
   case-insensitive but case-preserving) would silently fail to exclude,
   and a self-publishing course could read "— Edited" permanently; now
   `OrdinalIgnoreCase`, with a regression test.

   ~~Still genuinely outstanding, and NOT done: a scheduled deploy never
   writes the stamp.~~ ✅ Done 2026-08-22 (`GUI-IMPROVEMENTS.md` row 323).
   `TaskScheduling.Schedule` now always writes a wrapper `.ps1` (previously
   only for 2+ destinations), which fingerprints the section — via the
   bundled Python, `scripts/section_fingerprint.py`, since no app process is
   alive at the moment a scheduled deploy actually runs — right before
   running any destination's `deploy.ps1`, then writes a sentinel under
   `%LOCALAPPDATA%\Plantoir\scheduled\pending\` only if every destination
   succeeded. **A day later, a real overnight schedule for this still never
   fired at all — see `GUI-IMPROVEMENTS.md` row 325.** Unrelated to the
   fingerprinting work above: the stored `/TR` command had a doubled-
   backslash quoting bug (`\\\"` instead of a real `\"`) that predates this
   row entirely and had broken every scheduled deploy on Windows since the
   feature first shipped — fixed in `TaskScheduling.TaskRunCommand`. Confirm
   against row 325 before assuming a scheduled deploy actually runs;
   `ScheduledDeployCompletion.ConsumePending()`, wired into
   `MainWindow`'s `Activated` handler, applies and deletes any pending
   sentinel the next time the app runs. Fingerprinting at RUN time (not at
   schedule time) was deliberate — see "A scheduled deploy needs its own
   path to the same record" below, which this closes.

3. **Sampling the local engine's own stderr/stdout into the activity trail**
   (the tail end of "What the engine says now reaches a problem report"
   below). `LocalModel.NoteServerLine` / `RecentServerLog` already keep the
   ring buffer Windows needs; what was still missing as of the mac's
   2026-08-20 write-up is putting any of it on the trail as its own event
   (`assistant engine said` in `shared-rules.json` → `activityTrail.mustRecord`).
   Verify against current `ActivityTrail.cs` / `AssistServerHost`-equivalent
   code rather than assuming either way.

4. **The salvaged capture-dialog fixes on `issue/windows-capture-dialog-fixes`
   have not been built or tested on a real Windows machine** — see "Salvaged
   capture fixes from a stranded branch…" at the end of this file.

5. **Two things to measure, not copy, on real Windows hardware** (see "Two
   things to MEASURE on Windows rather than copy from the mac" below):
   whether the browser needs `127.0.0.1` instead of `localhost` for a preview
   address, and which of the 25 progress markers your own `.ps1`/native
   runtime output actually prints.
6. **The working-folder path bar's fuller gesture set** (double-click to open,
   right-click for a Show/Open menu, hover tooltip, folder icon per crumb) —
   see "The working-folder path bar" below; verify what `BreadcrumbBar`
   currently does against that table before assuming the gap is still open.
7. **The first-deploy marker's destination-scoping** (`AssistWorkspace.cs`
   accepting either folder rather than only the CURRENT destination) — see
   "One divergence found by sweeping" below; verify against current code.
8. **Three deploy-after-preview console races fixed on mac 2026-08-22, not
   yet checked on Windows** — `GUI-IMPROVEMENTS.md` rows 317–318, all SwiftUI
   state races rather than shared code, so nothing ports mechanically, but the
   same shape of bug is worth checking for in whatever Windows equivalent of
   `MultiDestinationDeployRunner`/`ScriptRunner`/the deploy console view
   exists there:
   - **Row 317** — deploying right after a preview flashed "Stopped" first.
     Deploying stops any running preview as an internal step, which on mac
     set the same `wasStoppedByUser` flag the teacher-facing Stop Preview
     button sets, and the panel-choosing logic compared `startedAt`
     timestamps that hadn't been updated for the new deploy yet. Fix: claim
     the console for the deploy panel (fresh `startedAt`, reset run state)
     *before* stopping the preview, not after. Check whether Windows' own
     "which panel is showing" logic has the same ordering dependency, and
     whether its internal preview-stop (if any) is distinguishable from a
     teacher pressing Stop.
   - **Row 318a** — right after clicking Deploy, the console went blank for
     about half a second, because a freshly-reset-but-never-run process
     wrapper is a state the progress view had no rendering for (neither its
     running branch nor its finished branch fired). Mac's fix was a
     `isPreparingDeploy` flag showing a plain "Preparing to deploy…"
     placeholder for that span — check what WinUI's deploy panel draws for a
     brand-new process object with nothing to say yet. The Deploy button
     also stayed clickable through this same window on mac (a re-entrancy
     bug in its own right, allowing a second overlapping deploy); confirm
     Windows' Deploy button disables for the full click-to-real-work span,
     not just while the underlying process reports running.
   - **Row 318b** — mid-deploy, the panel falsely flashed "Done" for up to
     300ms between the build script exiting and the deploy script starting,
     because mac's `MultiDestinationDeployRunner` ran both scripts on one
     `ScriptRunner` and polled `isRunning` every 300ms to detect completion
     — indistinguishable from the whole leg finishing. Fixed by making
     completion event-driven and adding an `isBetweenPhases` flag so the
     view knows "this script exited, but another is about to start" is not
     the same as "actually done." If Windows' build-then-deploy path reuses
     one process wrapper for two scripts back to back, check whether its own
     completion detection is polled (same latency-window risk) and whether
     its progress view can tell the two states apart.

**Everything else this section used to list as an ordered work plan —
contracts wiring, the approval wording, the deploy/preview race, the activity
trail, the problem report, the 2026-08-16 assistant batch (`add_next_class`,
`plan_remember_timetable`, the `LinkGraph` exclusions, `assistantConfirmation`),
the `ReDatePlan` overflow fix, asking for the schedule, course renaming, the
native local model, the assistant-choice Settings panel, the credential
dialogs, and the two small fixes (`AutoFillCourseName`, the Curriculum
Coverage toggle) — was verified DONE in `windows-app/` on 2026-08-22 and its
write-up now lives in
[`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md).**

### One thing NOT to do

Do not port entry 142 (Colima sizing) or entries 244–245 (`launchd`). They are
macOS mechanics. The transferable half of 244–245 is a single lesson worth
having before you touch `TaskScheduling.cs`: register a scheduled job as the
APP, not as the shell it happens to run, or the operating system tells the
teacher that "bash" — or, on the second attempt here, a person's name — wants
to run in the background.

## Windows no longer runs any of this in a container

**Read this before the architecture sections below.** Windows dropped Docker,
WSL2 and the whole image/container model on 2026-08-19 (`GUI-IMPROVEMENTS.md`
entry 290) in favour of a **native runtime**: `windows-app/Vendor/fetch-runtime.ps1`
fetches pinned, portable pieces — Node 20 (zip, no installer), Python 3.11
(the embeddable distribution plus `python-frontmatter` and `Pillow`), a clone
of Quartz v4.5.0 with this repo's `patches/` applied, wrangler, and the Noto
emoji font — into `windows-app/Vendor/runtime/`, which the app then ships
inside its own bundle the same way it ships the assistant's `llama/` engine.
`setup.ps1` / `preview.ps1` / `deploy.ps1` **do still live at the repository
root** (an earlier draft of this note said otherwise; that was wrong) and are
mirrored into a working folder exactly as before, but their bodies changed:
each now calls `Enter-NativeRuntime`, which points a shared set of
`PLANTOIR_*` environment variables at the bundled runtime and the working
folder, then runs `scripts/setup_course.py` / `build_site.py` / `deploy.py`
directly with the runtime's own `python.exe` — no `docker`, no `wsl`, no
image build, no administrator rights, and no one-time "Setting up this PC"
wait. If a copy is missing its bundled runtime the launcher fails outright
("This copy of Plantoir is missing its website builder... Reinstall
Plantoir") rather than falling back to a container path, because there no
longer is one.

What replaces the old container concepts:

- **No image, no tag, no registry.** There is nothing to hash into a
  `teaching-quartz:src-<hash>` tag any more, and `Get-ToolchainHash` /
  `Get-BuildContext` / `Ensure-ContainerRuntime` do not exist in the current
  `.ps1` files — do not port them, and do not go looking for the batching fix
  described further down this file (below, under "The recipe hash is on the
  hot path") as if it still applies; it was superseded by removing the image
  entirely, not fixed further.
- **Isolation between working folders is a hashed *working-folder ID*, not a
  container name.** All three launchers still compute `$WORKDIR_ID` — the
  first 8 hex characters of SHA-256 over the folder's physical path (via
  `GetFinalPathNameByHandleW`, the same Win32 call as before) plus a
  newline, matching the mac's `pwd -P | shasum -a 256` derivation. A
  `$CONTAINER_NAME = "teaching-quartz-$WORKDIR_ID"` variable is still
  assigned in each script for parity with the mac's naming scheme, but
  nothing native reads it — the real use of `$WORKDIR_ID` today is naming a
  per-folder build directory, `%LOCALAPPDATA%\Plantoir\builds\<WORKDIR_ID>`,
  so two working folders' builds never collide, and it moves build output
  entirely **out of the working folder**, because teachers keep working
  folders in OneDrive and a build's thousands of small files would sync and
  lock in place there.
- **Concurrent previews are still isolated by port, exactly as before.**
  `preview.ps1` still probes a free host port block (8081/8091/8101/8111/8121/8131,
  base..base+3 for the site, base+1000..+1003 for Quartz's live-reload
  websocket) and prints the exact "Preview will be available at:" line the
  app watches for. What changed is only what is listening on that port: a
  Node process running directly on the PC, bound to `127.0.0.1` (patched at
  runtime-build time in `fetch-runtime.ps1`, native-only — see the favicon
  entry below), not a container's forwarded port.
- **`preview.ps1 CODE N --stop` reclaims native processes, not a
  container.** It matches `node.exe` / `python.exe` by command line
  (`build_site.py --course=/--section=` for the build, the section's own
  build-root path for the server) and walks parent/child links to catch
  descendants, then kills them with `Stop-Process`. No container, no `docker
  exec`, no engine to stop.

`GUI-IMPROVEMENTS.md` entries 290 and 292 are the log rows for this change;
`MAC-HANDOFF.md` is where its origin and reasoning are written up in full.
The sections below that still described the old Docker/WSL2 container
architecture as current have been corrected to match the above — where the
old material is useful as history (why containers were tried, what WSL2 and
Colima-parity cost, lessons that still generalize), it is kept but labelled
as history, not as what Windows does today.


## What you are building

A native Windows app wrapping the same toolchain the macOS app wraps. The
scripts themselves are **shared and already done**: `scripts/`, `support/`,
and `patches/` (applied to a vendored Quartz clone) all live in this
repository and are shared with the macOS app, which still runs them inside a
Colima container — see the note above for why Windows itself does not. The
PowerShell launchers (`setup.ps1`, `preview.ps1`, `deploy.ps1`) drive that
shared Python natively on Windows; the Windows app's job is the interface:
the same behaviours as the macOS app, driving the `.ps1` launchers instead of
the `.sh` ones.

**The specification is [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md)** — every
numbered entry describes a behaviour the macOS app has, and every one carries
a Windows-porting note. Work through it top to bottom; it is the product of a
great deal of live testing and each entry earned its place.

**This file is kept current as the macOS side changes**, rather than written
once. The macOS working rule is that a change is not finished until its log
entry has a usable Windows note, anything architectural has a section here,
and any guidance the change made WRONG has been corrected. So if something
here contradicts what you find in the repository, the repository is right and
this file has a bug — say so, because that is a defect on the macOS side, not
a judgement call on yours.

## The three load-bearing rules

1. **The GUI never mentions the machinery.** No "toolchain", "script",
   "Docker", "container", or "WSL" in user-facing text. Plain words:
   "Building your website builder…", "Getting this Mac ready…" (yours will
   say "this PC"). **The visible verbs are now BOTH, and they mean different
   things** (entries 140 and 143, reversing entry 103): a PAGE is
   *published* — the `publish:` frontmatter flag deciding whether students
   see it — and the SITE is *deployed* to Netlify, Cloudflare or a folder.
   One word for both makes "I published tomorrow's class" mean a flag to one
   person and a live site to another. Internal names, script file names and
   config keys keep "deploy" throughout.
2. **Use the script logic itself as much as possible.** The app runs the
   real launchers and answers their real prompts; it does not reimplement
   them. Progress comes from parsing their output (milestone markers,
   `#N [k/n]` build steps, "N of M" upload counts, the announced preview
   address).
3. **Free resources whenever possible.** On Windows there is no engine or
   container to stop — the launchers run native processes directly, and
   `preview.ps1 CODE N --stop` kills exactly that section's processes (see
   below). Close a folder's last window → stop that folder's live previews.
   Quit the app → nothing else to release; there is no shared engine.

## Architecture the app must reproduce

- **Working folders**: a folder holding `courses/`, the three launchers,
  and `.toolchain/` (a mirror of `scripts/`, `support/` and the launchers
  themselves, refreshed by the app from its own bundled copy whenever a
  launcher/script file differs — a much smaller mirror than before, now
  that there is no image recipe to carry). The bundled **native runtime**
  (Node, Python, patched Quartz, wrangler, the emoji font — see
  `Vendor/fetch-runtime.ps1`) is separate again: it lives once per Plantoir
  install, not per working folder, and every working folder's launchers
  point at the same copy via `PLANTOIR_RUNTIME`.
- **No image, no tag, no registry.** There is nothing to build or cache
  locally any more — `Get-ToolchainHash` does not exist in the current
  `.ps1` files, and there is no equivalent to reproduce. (History: the old
  container path hashed every file in the build context and tagged
  `teaching-quartz:src-<hash8>`, rebuilding only when the recipe changed —
  see "The recipe hash is on the hot path" below for why that mattered
  while it existed, and note that it no longer does.)
- **Isolation between working folders is a hashed working-folder ID, not a
  container name.** Each launcher computes `$WORKDIR_ID` — the first 8 hex
  characters of SHA-256 over the folder's physical path (via
  `GetFinalPathNameByHandleW`) plus a newline — and uses it to name a
  per-folder build directory, `%LOCALAPPDATA%\Plantoir\builds\<WORKDIR_ID>`,
  outside the working folder entirely (so a working folder kept in OneDrive
  never has its build output synced and locked). A `$CONTAINER_NAME =
  "teaching-quartz-$WORKDIR_ID"` variable is still assigned in each script,
  matching the mac's naming scheme, but nothing native reads it today —
  don't build app logic around a container name existing.
- **Port blocks**: `preview.ps1` still probes a free host port block
  (bases 8081, 8091, 8101, 8111, 8121, 8131): base..base+3 for the preview
  site (four concurrent previews per folder) and base+1000..+1003 for
  Quartz's live-reload websockets. What is listening on those ports is now
  a native Node process bound to `127.0.0.1`, not a container's forwarded
  port. The app leases ports per folder (`PreviewLeases` in the macOS app),
  parses the announced "Preview will be available at:" address rather than
  assuming it, and refuses a duplicate preview of the same section in the
  same folder.
- **Course activity registry** (entry 104): one cross-window record of
  which courses are previewing (the port leases already know) or
  publishing (begin/end records around the publish flow, ended on EVERY
  exit path). "Add Section…" declines while its course is active, with a
  short line naming the blocker ("Available once preview completed").
  Staleness lesson: read the enabled state when the menu OPENS, or make
  registry changes re-render whatever hosts the menu — a state captured
  at an earlier render shows yesterday's answer.
- **Stopping a preview reclaims native processes** (entry 105): killing
  the host-side launcher orphans the build or server process it started
  (an orphaned build burns real CPU). `preview.ps1 CODE N --stop` matches
  that section's `node.exe` / `python.exe` processes by command line and
  working directory (so other sections are safe), walks their descendants,
  and `Stop-Process`es them — and never starts anything itself. Call it
  fire-and-forget — output discarded — wherever a preview ends: stop
  button, navigating away, window close. (History: this used to reclaim
  the container-side processes an orphaned host script would otherwise
  leave running inside Docker; the mechanism moved, the reason for having
  it did not.)
- **Backups and archives** (entry 106): three zip kinds share
  `courses/_backups/<CODE>/`, told apart ONLY by name —
  `<CODE>_backup_<timestamp>.zip` (teacher-made backups),
  `<CODE>_<timestamp>.zip` / `<CODE>-sectionN_<timestamp>.zip`
  (archives from removals), `<timestamp>.zip` (the wizard's automatic
  zips, never listed). Backups get their own sidebar group above
  Archived. Restoring a backup archives the current course FIRST, then
  replaces the course folder's CONTENTS in place — never the folder
  itself (see the Obsidian note below) — and keeps the zip. Deleting a
  backup or an archive is the app's only true deletion; the archive
  confirmation states a FACT about what remains (live course / other
  copies / only remaining copy — a whole-course archive covers a
  section archive, never the reverse).
- **No engine to bootstrap.** `fetch-runtime.ps1` downloads pinned, portable
  Node/Python/Quartz/wrangler binaries once (run before building the
  Windows app, or shipped inside its bundle to a teacher) — there is no
  WSL2, no Docker Engine, and nothing for the app to start, poll, or stop
  at quit. (History: earlier Windows builds provisioned Docker Engine
  inside WSL2 automatically, mirroring the mac's Colima bootstrap — see the
  appendix at the end of this file. That entire path is gone; do not build
  toward it.)
- **BuildKit, the image tag, and "the legacy builder corrupts a layer" are
  mac-only facts now** — Colima still needs them; native Windows has no
  image and no builder of any kind.

## Config is the contract

`course_config.json` is shared between the app, the wizard, and the build.
See [`documentation/08-course-config-reference.md`](documentation/08-course-config-reference.md).
Keys the Windows settings UI must round-trip (per-section maps use
`{"sections": {"sectionN": value}}`):

- `course_code`, `course_name`, `locale`, `section_numbers`, `num_sections`
- `emojis.sections` — header emoji per section (system emoji panel: Win+.)
- `color_schemes` — flat map sectionN → scheme id (`support/colour_schemes.json`)
- `fonts.sections` — header/body/code display names (files in `support/fonts/`,
  name → file by stripping spaces; "Helvetica, Arial" means system default)
- `show_section_marker.sections` — the "S1" in the site header
- `show_grade_in_title.sections` — grade prefix on the landing title
  (legacy: a single course-wide bool; honour it). LITERAL behaviour: the
  switch alone decides; the UI shows an orange warning when the course
  name already contains the grade label, and the teacher resolves it.
- `custom_domains.sections` — the app swaps published-site links' host to
  this domain (path kept, https); entries are normalized (scheme and path
  stripped) on the way in
- `shared_folders`, `shared_files`, `per_section_folders`,
  `per_section_files`, `hidden`, `expandable`, `expandOnFolderClick`,
  `show_reading_time`, `footer_html`
- `deploy_target` ("netlify" default | "cloudflare_pages" | "local_folder") and
  `deploy_folder_path` (entries 101–102) — folder deploys pass
  `--to-folder <path>` to the launcher, which robocopy-mirrors each
  section into `<path>\sectionN`; completion is announced by a
  `PUBLISHED_FOLDER=` line the app turns into a Show-in-Explorer button.
  The Publishing choice appears in BOTH the settings form and the
  new-course wizard (share the control); an empty, missing, or
  unwritable folder blocks save/create with an inline message and is
  checked the moment a folder is chosen; folder-mode progress labels
  never mention Netlify; and the completion adds a note that the pages
  only render properly once uploaded to a web host
- `prepopulate_example_content`, `include_curriculum_pages` (entries
  92–93) — written by the new-course wizard, read by the shared Python
  wizard as its defaults; both forced false when no example content
  exists for the course code
- `use_lcs_terminology` (entry 94) — whether the factory structure
  defaults use LCS's own set-up; the two factory sets live as
  `DEFAULT_*` vs `LCS_*` constants in `scripts/setup_course.py` and the
  Windows equivalent of `WizardDefaults` must mirror them exactly
- `custom_short_name` — the ≤12-character label shown beside the header
  emoji instead of the course code, in club mode. Already implemented on
  Windows (`CourseConfiguration.cs`); listed here because this table is the
  contract and it was missing from it
- `include_curriculum_coverage` and `include_coverage_notes` (entries 125,
  130) — whether the generated `Curriculum Coverage` map page is produced, and
  whether it carries its explanatory sections or the map alone. Read by
  `build_site.py`, both defaulting true. **Implemented on Windows** (verified
  2026-08-22): both keys are read and written in `CourseConfiguration.cs` and
  surfaced as toggles in `NewCourseDialog.cs` and `CourseSettingsView.xaml.cs` —
  this note used to say "not yet implemented" and was stale.
- **Edit keys in place and preserve unknown keys** — the macOS app keeps
  the decoded JSON as a dictionary precisely so future toolchain keys
  survive a settings round-trip. The shared Python wizard does the same in
  the other direction: it copies through every key it does not own, which is
  what lets an app-written setting survive a wizard re-run.

## Example content (entries 92–96)

Ready-made course payloads ship in `support/example_content/<CODE>/` — 37 of
them as of 2026-08-15 and growing, so read the directory rather than any list
written here; detection is by the presence of `manifest.json`, which is what
the code does anyway. (SNC1W is the example course's content converted to
payload form, so a teacher actually teaching Grade 9 science gets it as
starting content; SNC2D is its Grade 10 sequel, and SCH3U/SCH4U carry
chemistry through Grades 11 and 12.) All
the installing, date logic, and curriculum handling is shared Python —
Windows needs exactly three UI behaviours:

- **Detection**: example content exists for a code when the bundled
  `support/example_content/<CODE>/manifest.json` exists; the curriculum
  toggle additionally needs the manifest's `curriculum_folder` to be
  non-empty (reference logic: `ExampleContentCatalog.swift`).
- **Starting Content section** in the new-course wizard: "Pre-populate
  course with example content" (default ON) with "Include Ontario
  curriculum pages" beneath it (default ON, disabled when the first is
  off). When no content exists for the code, this is where the SKELETON
  toggle goes instead (entry 123) — "Start from a <subject> skeleton" —
  and the quiet "empty folders" caption is now the last resort, for a code
  with neither.
- **Structure lock**: when pre-populating, HIDE the folders/files
  editor behind a caption — the payload's manifest is the entire
  structure authority and the Python wizard skips all structure
  prompts.

Authoring new payloads is content work, governed by the repo-local
skill `.claude/skills/example-content/` and checked by its
`lint_payload.py` — no app code changes on either platform. The same skill
holds the skeleton generator and `lint_skeletons.py`; the skeletons are
generated output, so never hand-edit `support/skeletons/`.

Two payload conventions have changed since these entries, both handled by
shared Python: course-level pages now arrive with
`createdSectionN`/`publishForSectionN` (one pair per section — entry 122), and
`Key Links` ends with the site tour (entry 121).

## Behaviours with platform-specific mechanics

- **Obsidian integration** (entry 80): `obsidian://open?path=…` only works
  for vaults REGISTERED in Obsidian's registry — on Windows,
  `%APPDATA%/obsidian/obsidian.json`, same JSON shape. Port the whole
  dance: quit Obsidian if running (its in-memory vault list ignores
  registry edits), seed `support/obsidian_defaults/.obsidian` if the
  course has none, write the registry entry, then open the URI. Sections
  open at their `index.md` (Obsidian opens files, not folders). Enable
  the File Explorer's auto-reveal by patching the vault's
  `workspace.json` whenever Obsidian is closed (a pre-seeded layout is
  discarded on a vault's first open — verified). One more watcher
  lesson (entry 106): Obsidian's file watcher is anchored to the vault
  FOLDER's identity — replace the folder and an open vault shows stale
  files until reopened; replace only its contents and Obsidian
  refreshes itself. Any feature that rewrites a course wholesale (like
  restoring a backup) must swap contents, never the folder.
- **Window restoration** (entries 64–65, 98–99, 106): keep per-window
  state in the app's own store, keyed by something the platform restores
  faithfully. Each entry now carries, beside the folder: the expanded
  course codes, whether the Archived and Backups groups are open, and
  the sidebar selection (`course|CODE`, `section|CODE|N`, `archived|ID`,
  `backup|ID`) — restore all of it when a window claims its entry. Two rules learned the hard
  way: resolve claims on the platform's restoration-complete signal
  rather than polling, and while a claim may still arrive show a quiet
  loading state, never the folder picker the claim is about to replace.
  The scenario test suite in the macOS app is the porting spec.
- **New windows** (entry 84): inherit the folder of the window that was
  key when the command ran; with no windows open, show the folder picker.
  Decide the folder BEFORE first paint or the picker flashes.
- **Updates**: WinSparkle, with its own feed at `site/appcast-windows.xml`
  alongside the mac's `site/appcast-macos.xml` — **per-platform file names from
  the start**, so the two update feeds can never collide. (An earlier draft of
  this line said the two would share one appcast; that is exactly the collision
  the mac side asked to avoid. Deferred on both platforms until the first
  release.)
- **Stable code signing** (entry from the signing fix): sign dev builds
  with a stable identity or Windows will re-prompt for permissions —
  same class of problem as macOS ad-hoc signing.
- **Social cards & OpenGraph preview metadata** (entries 88, 268): nothing to do in C# — `scripts/social_card.py`
  draws the 1200×630 card on every build (inside the container on macOS,
  natively on Windows — see the note above), `patches/Head.tsx`
  wires OpenGraph and Twitter card metadata, and `scripts/build_site.py` / `scripts/deploy.py`
  sync the live site domain into Quartz's `baseUrl` (falling back to `undefined` when unpublished).
  Because the entire flow lives in the shared Python scripts, Windows inherits it automatically
  regardless of which runtime carries them.
- **HISTORY — the recipe hash used to be on the hot path** (entry 118).
  This entry describes a bug that existed only in the old container/image
  architecture and **no longer applies**: Windows dropped the image tag
  entirely on 2026-08-19 (see the note at the top of this file), and
  `Get-ToolchainHash` does not exist in the current `.ps1` files. Kept here
  because the underlying lesson generalises — **keep per-file work out of a
  per-invocation loop** — and because the mac side still hashes something
  comparable for its own image tag. What it used to say: the image tag was
  a SHA-256 over every file in `.toolchain/`, which by 2026-08-15 carried
  **11,378 files** across the example-content payloads and subject
  skeletons; the `.sh` launchers originally spawned one `shasum` process
  per file (36s of a 36.75s preview startup on an M4 Pro) before being
  batched to `find -print0 | sort -z | xargs -0 shasum` (0.16s), and
  `Get-ToolchainHash` in the old `.ps1` files had the same bug in its
  PowerShell dialect — `$combined += (Get-FileHash …).Hash` inside a loop,
  reallocating an immutable string thousands of times — fixed the same way
  by collecting into an array and joining once. If a future Windows change
  reintroduces any per-folder hash (for a future runtime version check, say),
  re-learn this lesson rather than re-discovering it.


## The assistant's division of labour — the rule everything else follows

**The model picks which Swift function to run, and fills in its arguments.
Nothing else.** Every rule about what an action MEANS lives in code. If you
take one thing from this file, take this: it is what makes a small local
model viable, and every problem worth having came from violating it.

The split is measured, not aesthetic. Across the same runs the model:

- **misrouted five of the eleven suggested phrasings in EVERY trial** — it is
  bad at choosing;
- produced **zero wrong courses, zero wrong dates, zero type errors, zero
  invented dates** — it is good at filling in.

So take the choosing away wherever it can be taken, keep the filling in.

Three consequences that follow, each of which cost something to learn:

1. **Tools are coarse.** Given `resolve_links`, `set_publish` and
   `publish_section` separately, and asked to publish tomorrow's class *and
   everything it links to*, the model chose `publish_section` 8 times out of
   8 — skipping the link resolution. Perfectly consistent, and wrong. One
   `publish_class_on` that resolves links itself: right 8 of 8.
2. **Fixed phrasings never reach the model.** The card's unambiguous shapes
   are matched in code. If you reword one, update the matcher too, or the
   shortcut silently stops firing and the phrasing quietly starts being
   routed instead — it will look correct and behave worse.
3. **Absence is the guardrail.** There is no delete tool, so "delete the
   Unit 1 folder" cannot be honoured however confidently it is asked. Not
   judgement — no route.

### Rules belong in the tool, never in an argument

`publish_pages` and `unpublish_pages` used to take an `includeLinked`
boolean with no default, so the MODEL decided. That is the same reasoning
this design exists to keep out of the model, and a boolean is the thing that
inverted polarity on the 3B. It is gone, and the rules are now code:

**Publishing always publishes the pages it links to.** Never publish a page
whose links lead somewhere students cannot see — that is the whole point.

**Unpublishing is NOT the mirror**, and this asymmetry is deliberate:

- unpublish the named page(s);
- also unpublish a linked page **only if that page is linked to ONLY by the
  page(s) being unpublished**. If anything else still links to it, it stays —
  otherwise you create the dead links the publish rule exists to prevent;
- **never** unpublish, whatever the link count: a folder's landing page
  (`index.md` — Concepts, Investigations…), any page in that section's **Key
  Links**, or any **Curriculum** page (detect with `build_site.py`'s own
  rule: any folder segment containing "curriculum").

The plan should say what it **kept** and why — "Ohm's Law stays: Unit 3,
Day 2 still links to it" — not only what it removed. A teacher needs to see
the tool reasoned about it, or they will check by hand and the rule has
bought nothing.

#### Never ask the model for something the window already knows

The tools take `course` and `section` as arguments, and for a long time the
model filled them in. It should never have been asked: the assistant window is
opened FOR one section and its title says so.

The failure this produced is instructive because it is not a stupid one.
**"Unpublish Unit 4, Day 12" was read as section 4**, and the teacher was told
their course has no Section 4 — a perfectly reasonable misreading of a page
name that begins with a number, and one that no amount of describing the
argument would prevent on the next page name that does. It happened more than
once before it was fixed.

So the agent overwrites both arguments with the window's own before anything
runs. It cannot cost routing accuracy, because it changes nothing the model
reads — only what is done with what it said.

**Do this in the agent, not in the tool.** The same tools answer Claude Code
over MCP, where the course and section genuinely ARE the caller's to choose.
It is the window that is about one section, so the window is what binds them.

Worth a sweep of your own surface for the same shape: any argument the
surrounding context already determines should be overwritten on the way in
rather than described more carefully in a schema.

#### A corollary, learned the expensive way: do not fix routing with words

When a probe routes to the wrong tool, the tempting fix is a sentence in the
tool's description telling the model when NOT to use it. **Measure that
before you keep it.** We did, and it was worse.

The case: `publish_pages` takes an optional date range, and a typo'd "publsh
tomorows class … and the stuff it links to" chose it 10/10 with no page named
and an open-ended start date — one lesson turning into the rest of the term.
Adding *"NOT for one day's class — for a single day use publish_class_on"* to
the description fixed that probe and **broke three others**: "Publish Unit 2,
Day 3", a named page with no date in it whatsoever, went to
`publish_class_on` 10 times out of 10, and the window's own suggestion cards
fell from 110/110 to 90/110. A small model reads a sentence naming another
tool as a recommendation rather than a boundary, and it does not reliably
notice which half of a sentence applies to it.

The wording was reverted to the byte and the rule became a conditional in the
tool: an open-ended publish (no pages named, a start date, no end date) is
REFUSED, with a message saying to use `publish_class_on` for one day or to
give both dates for a stretch. Three properties make that better than the
sentence:

- it changes nothing the model reads, so it **cannot** cost routing accuracy
  and needs no re-measurement;
- it is exact, where a description is a hint;
- the refusal comes back as ordinary text, so the model corrects itself on
  the next turn rather than failing at the teacher.

Applied to publishing only. An open-ended UNPUBLISH hides work rather than
exposing it, the same backup undoes it, and a teacher clearing a section back
to a date is a real thing to want.

**The general rule: prompt text is a gamble that has to be re-measured across
the whole suite; a conditional is not.** If you change any description, re-run
every probe, not the one you were fixing — that is the only reason we caught
this instead of shipping a regression that looked like a fix.

#### And when you REMOVE a tool, audit the refusals that pointed at it

Cutting `remember_timetable` from the local list was right — dates the model
supplies are dates it may have invented — but it left three refusals saying
"record them with `remember_timetable` first". The model can no longer see
that tool. **A remedy naming something unreachable is worse than no remedy**,
because the next move available to a model that cannot follow the instruction
is to improvise the dates, which is the exact failure the removal was meant to
prevent.

Two things had to follow the cut, and only one of them was obvious:

1. The messages now name no tool. They say what is missing and that the app is
   asking the teacher — which also stays true over MCP, where the client's
   tool list is different again.
2. **Something else has to actually ask.** On macOS a schedule sheet collects
   dates (typed, from a file, or from a shared sheet link); the tool leaves a
   request and whichever assistant window is showing that section presents it.
   That sheet existed and was already attached to the window — the call that
   sets the request was simply never written, so nothing ever opened it. It
   looked finished from every angle except running it.

So: **if Windows has no equivalent way to ask, `remember_timetable` must stay
on its local list.** The cut is only safe because something else asks. And the
audit worth running after any removal is not "does the surface still route"
but "can every refusal still be acted on by the surface that receives it".

### What the assistant's window must BE — and what it need not look like

Decided 2026-08-16, in answer to "must the bubbles match?" — **no.** The mac's
bubble geometry (13pt insets, 17pt corner radius, Messages' grey and its light
blue selection) was measured against Messages on the same screen, and copying
those numbers onto Windows would produce something that looks like a Mac
application running in the wrong place. **Build a chat that looks at home on
Windows.** WinUI's own type ramp, its own spacing, its own accent colour. Read
the mac's chat sections below for what the arrangement has to achieve, and
ignore the numbers.

What is NOT negotiable is the shape of the interaction, because that is the
product rather than the platform:

1. **It is a CHAT.** Not a form, not a command palette, not a properties panel
   with a text box on it. A teacher types a sentence and gets a sentence back.
2. **Everything goes through the chat — input and output both.** No result
   appears only in a status bar, a toast, a dialog, or a log pane. If the
   assistant did something, the conversation says so, in the conversation.
3. **The one exception is confirming an action**, where buttons appear — as
   they do on the mac for a deploy or a plan. A teacher agreeing to publish to
   students should not have to type "yes" and hope it was understood.
4. **What the teacher chose with a button goes into their chat history**, in
   their own bubble, as though they had typed it. Reading back a conversation
   where the assistant asked, nothing answered, and something plainly happened
   is worse than not being able to read it back at all. The two contract
   scenarios "the deploy card is agreed to" and "the deploy card is cancelled"
   assert exactly this, so your suite can check it rather than your eyes.
5. **A thinking indicator is a MUST.** The local model takes seconds and the
   toolchain takes minutes, and a window that sits still through either one is
   indistinguishable from a window that has crashed. The mac shows one
   indicator for BOTH thinking and running a tool, deliberately: a teacher does
   not care which of the two the assistant is busy with, and two indicators
   invite the question. It hides while a card is waiting for a button — nothing
   is happening then, the teacher is.
6. **Up and Down walk back through what was asked before, as a Terminal
   does — the SAME KEYS as the mac.** Not a per-platform choice: a teacher who
   learns Up on one machine and finds it somewhere else on the other has
   learned nothing. It is also a requirement rather than a nicety — it is how
   somebody re-runs the thing they just ran with one word changed. The
   semantics are in `contracts/assist-cases.json` under `promptHistory`: eight
   step-by-step cases, the key names, and the two situations where the arrows
   must instead do their ordinary job and move the caret (a box holding more
   than one line, and nowhere further to walk — pass the key on rather than
   swallowing it, because a key that silently does nothing reads as a dropped
   keystroke). The two cases that get missed: the half-typed line is put aside
   and handed back rather than lost, and typing ends the walk so Down cannot
   silently replace what was just written.

And the rule that governs all of it, from row 1 of the improvement log: **the
window never names the machinery.** No tool names, no model names, no tokens,
no containers. "The small assistant" and "the larger assistant".

### The parts of those four areas that could NOT be a contract

`shared-rules.json` carries the rules. These are the neighbouring pieces that
are yours, written here because "not in the contract" must never mean "nobody
mentioned it".

**Scheduled deploys — the mechanism, and one refusal that may differ.** Writing
a plist and writing a scheduled task have nothing in common, so only the
refusals are shared. But one of them is a genuine fork: the mac refuses
Cloudflare with no Account ID **because it can pass `--account` in the plist and
therefore has to ask once, up front**. If a Windows scheduled task still cannot
be handed an account, then Cloudflare is not schedulable there at all — and the
right answer is a refusal that SAYS so, not a task that fails at 06:30 in
silence. Check it, and record what you find in `MAC-HANDOFF.md`; the contract
case says which of the two you are looking at.

Two more that stay yours: the plan's own words (the mac's says what has to be
true of the Mac — awake, plugged in, lid open — and yours will say something
different about sleep and Modern Standby), and cancelling, which on the mac is
`launchctl bootout` plus deleting the plist.

**The sidebar filter — the empty state.** The contract says WHAT matches. It
does not say what a teacher sees when nothing does, because that is a view: the
mac shows a short sentence rather than an empty pane, and the rule behind it is
that an empty list looks like a broken app while a sentence looks like an
answer. Say something; the words are yours.

**The transcript — everything except the stripping.** What is stripped is
shared (a colour code is a colour code). How much scrollback is kept, when the
view follows the tail, whether it scrolls on focus — all yours, and all
different in WinUI.

**Curriculum — the plan, not the recognition.** What COUNTS as an expectation
is shared and must be, because `build_site.py` decides what ships and an app
that disagreed would report coverage the site does not have. What a coverage
plan SAYS to a teacher, and how it is offered, is yours.

### The working-folder path bar — reported missing in use, 2026-08-16

The bar under the sidebar that reads "Working folder: … › … › Courses". On the
mac it does four things; on Windows the `BreadcrumbBar` currently does one, and
the difference was found by a teacher using it rather than by any test, which
is the point of writing it down now.

| What | mac | Windows today |
|---|---|---|
| Click a crumb | selects nothing — see below | **reveals it in File Explorer** |
| Double-click a crumb | opens that folder | nothing |
| Right-click a crumb | menu: **Show in Finder** / **Open Folder** | **no menu at all** |
| Hover a crumb | tooltip with the full path | nothing |
| Each crumb shows | the real folder icon + display name | name only |

**The two actions are genuinely different and a teacher wants both.**
*Revealing* opens the folder's PARENT with the folder selected — it answers
"where does this live?". *Opening* opens the folder itself — it answers "what
is in it?". Collapsing them into one gesture loses the other question, and
which one survives is arbitrary. The gestures follow the host file manager
deliberately, so a teacher who has used Finder or Explorer already knows them:
double-click opens, right-click offers both.

**Every crumb is live, not just the last.** That is how a teacher reaches the
folder ABOVE their working folder — to make a sibling, or to see where things
sit — without leaving the app to go and find it.

The testable half is in `contracts/shared-rules.json` → `workingFolderPathBar`:
the crumb list (every ancestor, root first, folder last — on Windows starting
at the drive rather than at `/`), the two actions with each platform's label,
and the gestures. The labels differ on purpose: "Show in Finder" against
"Show in File Explorer".

**The general lesson, which is why this went unnoticed for months.** An
affordance that lives ONLY in a context menu is invisible to everything: no
screenshot shows it, no test on the other side asks for it, and the person
building the other app has no way to know it exists. When a change adds a right
-click menu, a double-click, a hover, or a keyboard shortcut, it needs a line
here **even though nothing on screen changed** — those are exactly the changes
a diff of the UI will not reveal.

### A second: the wizard's own answer keys, and the skeleton question

`course_config.json` carries two GROUPS of keys, and only one of them is the
settings form's. The other three are written once by the wizard, and
`setup_course.py` reads each as the DEFAULT for a question it would otherwise
ask:

| Key | What it decides |
|---|---|
| `use_skeleton` | Whether a course with no ready-made payload starts from its subject's skeleton — folders that suit the subject, four units of class pages to rename, placeholders saying what belongs where — or from nothing at all. |
| `prepopulate_example_content` | Whether one of the 37 ready-made courses is poured in. |
| `include_curriculum_pages` | Whether that payload's Curriculum folder comes with it. |

**`use_skeleton` is not written by the Windows wizard at all** (checked
2026-08-16). The Python then falls back to its own default — `True` — so a
Windows teacher gets a skeleton and is never asked. That is the question MOST
teachers meet, because around 1,900 course codes have a skeleton and no
payload; only 37 have a ready-made course.

**Decided 2026-08-16: match the mac — ask the question and write the answer.**
The alternative was to always start from the skeleton and write
`use_skeleton: true` explicitly, which was defensible; the reason it lost is
that this is a real choice a teacher has, and the two apps should not differ on
whether a teacher gets to make it. Silence was never an option either way,
because the next change to that default in the Python would move Windows and
not the mac.

The mac writes each of these as `capabilityExists && teacherSaidYes` —
`hasSkeleton(code) && startsFromSkeleton` — so a stale `true` in an old config
can never mean anything.

### One divergence found by sweeping, 2026-08-16: the first-deploy marker

`deploy.py` writes a marker the first time a section goes out —
`.netlify_sites/section<N>.json` or `.cloudflare_sites/section<N>.json` — and
both apps read it to answer "has this ever been deployed?". That answer decides
whether a scheduled deploy is allowed, because a FIRST deploy asks what to call
the website and nobody is awake at 06:30 to answer.

**The mac reads the marker for the destination the course is configured for
NOW. `AssistWorkspace.cs` accepts EITHER folder.** So a course deployed to
Netlify and later switched to Cloudflare reads as "already deployed" on
Windows, and a teacher there can schedule the one deploy guaranteed to stop at
a prompt in the dark.

Narrow it to the current destination. The rule and the paths are in
`contracts/file-formats.json` → `firstDeployMarkers`, including the third case:
a folder deploy keeps no marker at all and counts as always-deployed, because
it asks nothing.

Worth knowing how this was found: not by a failing test, but by walking
`documentation/07-deployment.md` and asking which of its facts anything
verifies. Several of these contracts came out of reading the documentation
against the code that way.

### Two things to MEASURE on Windows rather than copy from the mac

Both are in the contracts, and both would be wrong to implement by reading the
mac's answer. They are small, and each is an hour that turns into a day when
skipped.

**1. Whether the browser needs `127.0.0.1` instead of `localhost`.**
`app-rules.json` → `linkRules.browserSafe` says the mac rewrites the preview
address before handing it to the browser. The reason is specific to Safari: it
tries IPv6 (`::1`) first for "localhost", the container publishes the port on
IPv4 only, and the failure reads to a teacher as "the server dropped the
connection" — not as anything to do with addresses. **Find out what Edge does**
before deciding you need the same rewrite. Open a preview, then try
`http://localhost:<port>` in Edge by hand. If it connects first time, drop the
rewrite and say so in `MAC-HANDOFF.md` — that is a finding, not an omission,
and the contract should then note that the rule is mac-only. If Edge behaves
the same way, keep it and the contract stays as it is.

**2. Which progress markers you must match, and which are yours to write.**
`app-rules.json` → `markerOrigins` classifies all twenty-five. Seventeen come
from `scripts/*.py`, which both platforms run, and must match to the
character. Seven come from the launchers, which exist separately as `.sh` and
`.ps1` — those you write, and they already differ: the mac watches for
"Setting up this Mac" where `setup.ps1` prints "Setting up this PC". One is
"elsewhere" (`Quartz v4`, from the Docker build) and wants a human to look.

**Do NOT copy the mac's seven launcher markers into your milestone lists.**
Read your own `.ps1` files and match what they actually print. This fails
silently in the worst way: the app does not crash, the progress bar simply
stops advancing part-way and then jumps at the end, which reads as a slow
build rather than as a bug — and the only way to notice is to watch a whole
deploy with the old and new bars side by side.

### Do not re-derive Plantoir's tests — read `contracts/`

**This is the section that saves you a day per sync.** Six JSON files, written
by the macOS binary, meant to be read by `Plantoir.Tests`. It started as the
assistant's contract and is now the whole product's:

| File | What it holds |
|---|---|
| `contracts/assist-wording.json` | Every sentence the assistant says to a teacher — nineteen, with `{course}` and `{section}` where values go. |
| `contracts/assist-cases.json` | The nine phrasings matched in code, the four near misses that must NOT match, the three tool lists with approvals and plan twins, **the full tool SCHEMAS as a client sends them**, eight scenarios as `given` / `when` / `expectEvents` / `expectReply`, and the arrow-key prompt history. |
| `contracts/app-rules.json` | Launcher arguments per configuration, the validation a teacher reads, failure output turned into a sentence, whether a deploy must build first, the progress markers and where each one's text comes from, the preview's ports. |
| `contracts/schedule-rules.json` | Every accepted date form, how an ambiguous `08/09/2026` column is settled or asked about, what a pasted Google Sheet address becomes. |
| `contracts/class-planning.json` | Which titles carry numbers, what the next class is called, and the ORDER renames must run in. |
| `contracts/course-management.json` | The three kinds of zip and how they are told apart, the section number offered next and the refusals, grade labels from a course code. |
| `contracts/file-formats.json` | Every `course_config.json` key with type and default, and the frontmatter that decides who sees a page — `publish:`, the legacy `draft:` that means the opposite, and the per-section keys. |
| `contracts/shared-rules.json` | What a scheduled deploy refuses and in what ORDER, what the sidebar filter shows, what is stripped from the launchers' output, and what counts as a curriculum expectation. |

An xUnit `[Theory]` with a `MemberData` source that deserialises these is the
whole integration. Nothing in them is macOS-specific: the sentences are the
product's and the sequences are the toolchain's.

**Why this exists.** Every wording change on the mac used to reach you as prose
in `GUI-IMPROVEMENTS.md` and a paragraph here, which you then retyped as tests
by hand — a day of it, and the sentences drifted the moment one side edited
without telling the other. They had been living in four places at once, and
three were already wrong: the identical deploy failure said "the output is in
that section's console in Plantoir" from one code path and "…that section's
window in Plantoir" from another, so which sentence a teacher got depended only
on whether a window happened to be open.

**How it stays true.** `Plantoir --write-contracts contracts` writes all three
files from `AssistWording`, `AssistCardCommand`, the tool surface and
`TaskMilestones`, and the contract tests run the same generator in-process and
fail when what is committed disagrees. A changed sentence therefore fails on the mac in the same
run that changed it, and reaches you as a **diff in `contracts/`** in the same
commit as the Swift. Verified by breaking a sentence on purpose: the suite
failed naming the key and the command to regenerate.

**Four things to know before you use them.**

- **Never hand-edit the GENERATED keys** — `cardPhrasings`, `tools`,
  `milestones`. Those are readouts of mac code; the next regeneration
  overwrites your edit and the diff looks like vandalism.
- **Write the entry to the template.** `MAC-HANDOFF.md` opens with "How to
  write an entry" — title and source, what it fixed and WHY (including what
  was rejected), numbers with the hardware they came from, the file and test
  names to look at, and whether the mac must match it or merely know. That
  file also has a **"Contract cases waiting on the mac"** section at the top,
  which is where a proposed case gets named.
- **You CAN propose an authored case.** `scenarios`, `nearMisses`,
  `promptHistory` and the case lists in the other files survive a mac
  regeneration untouched, so a behaviour you invent can be written as a case
  here — and the MAC suite will then fail until the mac implements it. That is
  the mechanism working, and it has been verified by doing it on purpose. Name
  the case so it reads as a proposal and log it in `MAC-HANDOFF.md`, or the
  failure looks like damage rather than a request.
- **`expectEvents` is an ORDER, not a set.** Every incorrect ordering passes a
  test that only checks all three events occurred — which is exactly how the
  mac shipped a preview that stopped after the writes it was meant to protect.
- **The event names are the contract's own**, deliberately not Swift's. Map
  `stopPreview.begins` / `stopPreview.ends` / `deploy` / `write` /
  `startPreview` / `runLauncherDirectly` onto whatever your app calls them.
  Two `given` flags decide the interesting cases: `sectionWindowOpen: false`
  is the headless path (`Plantoir.Mcp`, and a scheduled deploy), and
  `previewRunning: true` is the case Windows currently gets wrong.
- **Replies are NAMED, not quoted** — `wording.deployed`, not the sentence.
  Look them up in the wording file and substitute `{course}` and `{section}`
  yourself. A test that quotes its own copy of a sentence is how this problem
  started.

**What the contract CANNOT do, so you still write these tests yourself.**
The list is short but each item is a real gap, and a gap nobody names is a gap
both sides assume the other is covering:

| Not in the contract | Why not, and what to do instead |
|---|---|
| **Routing accuracy** | Whether the model picks the right tool for a sentence it actually sees is a measurement, not an assertion — it varies by model, quant and context size. Measured against a real `llama-server`; see [`research/`](research/README.md). The contract can say "deploy now" never reaches the model; it cannot say what the model does with a sentence that does. |
| **Anything with platform mechanics** | How a preview is stopped (WSL2, ConPTY, port leases, container naming) is yours. The contract says a stop must FINISH before a deploy begins; it cannot say what finishing means on your side. |
| **That an await is really an await** | This is the subtle one. The ordering assertion only proves anything if your fake preview emits the stop as TWO events with a real suspension between them, as the mac's does (`stopPreview.begins` … `stopPreview.ends`). A fire-and-forget stop that happens to complete quickly will satisfy a single-event fake and ship the bug the ordering was written to catch. |
| **Transcript composition** | The scenarios assert that named lines appear IN ORDER, never that they are adjacent or last. After an approval the tool's own result is the final line on the mac, and your renderer may differ. Order is portable; arrangement is not. |
| **Anything visual** | Bubble geometry, toolbar disabled states, progress headers, window layout. The contract has no vocabulary for these and should not grow one — that is what `GUI-IMPROVEMENTS.md` is for, and what a screenshot settles in a minute. |
| **Launcher arguments** | That a Cloudflare course deploys to Cloudflare is enforced on the mac by one function (`DeployCommand.arguments`) and by a unit test, not by the contract. If your `Plantoir.Mcp` or scheduled task composes its own arguments, write that test on your side — the bug is silent, and the site simply appears on the wrong host. |
| **Plan mode's offer to stop asking** | Tier-dependent (the smaller assistant cannot turn plan mode off at all), so it is a mac measurement and a mac rule until Windows has measured its own tiers. |

If you find yourself wanting to add one of these to the contract, the answer is
usually a second file rather than a stretched first one — `contracts/windows-*.json`
for behaviour only your side has.


### The tool descriptions are measured, so compare against the contract

`assist-cases.json` → `toolSchemas` now carries the tool definitions **exactly
as each client sends them** — name, description and parameter schema, for both
the 13-tool local surface and the 23-tool MCP one.

The descriptions are the part to take seriously. They are measured artifacts,
not commentary: the "TEACHERS SAY:" phrasings came out of the routing suite,
and one added clarifying sentence in `publish_pages`' description took the
promise-card score from 110/110 to 90/110 and broke three probes that had been
perfect. A small model reads a sentence naming another tool as a
recommendation, not a boundary. **Steer with code, never with a description.**

Two things follow for your side. Compare your own schemas against these rather
than against a description of them — a drifted description is a routing change
nobody will attribute to a wording edit. And when you measure routing against
your own backend, take the surface from the contract:

```
python3 research/ai-assist/tools-from-contract.py local > /tmp/real-tools.json
python3 research/ai-assist/shipped-surface-suite.py 8099 10 /tmp/real-tools.json
```

The suites are plain Python over `http://127.0.0.1:<port>/v1/chat/completions`,
so they run anywhere a llama-server does. `routing-suite.py` is marked
HISTORICAL and hand-writes five tools; do not measure the shipping surface with
it.

### The model's list is SHORTER than the server's

Two lists, deliberately. `definitions` is what the local model sees;
`mcpDefinitions` is what Claude Code sees over MCP. Same tools, same runner,
same rules — the model is simply shown fewer.

- **The `plan_` twins are hidden from the model.** Plan mode calls them from
  CODE when the model picks a write, so the model never needs to name one.
  They were about 30% of the prompt buying nothing. Claude Code KEEPS them:
  it has no plan mode and genuinely needs to ask "what would that do?".
- **`remember_timetable` is hidden from the model.** It takes dates as
  strings, so dates the model supplies are dates it may have invented — and
  a wrong one schedules a class on the wrong day silently. The schedule UI
  owns that path. `read_remembered_timetable` stays, because reading is safe.

Result: 20 tools down to **13** for the model — the six `plan_` twins and
`remember_timetable` are the seven taken off the list. (An earlier draft of
this note said 12; the cuts named above come to 13, and the code and its
tests say 13.) The thirteen are `list_pages`, `read_page`, `check_section`,
`publish_class_on`, `publish_pages`, `unpublish_pages`, `rebuild_preview`,
`undo_last_change`, `deploy_section`, `schedule_deploy`,
`cancel_scheduled_deploy`, `read_remembered_timetable`, `add_next_class`.
Worth doing on Windows too — the routing figures were measured at 15, so a
surface that grows past that is spending accuracy, and one that shrinks below
it should be spending less.


## Quartz serves the OLD site before it builds the new one

This one is inside Quartz, so it is yours as much as ours, and it is invisible
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

## What the conversation looks like, and why

The assistant window is a CHAT, not a form with a log under it. That was a
deliberate change and it is worth stating why before the numbers: a teacher
asking for something, being told what would happen, and agreeing to it is a
conversation, and a window that looks like one is a window they already know
how to use. Nothing here has to be taught.

**One decision is yours, not ours.** These specs describe macOS Messages,
because that is the chat every Mac teacher already has open. The Windows
equivalent may be better served by looking like Windows — Teams and Phone Link
have their own bubble idiom, and a Mac-shaped chat on Windows can read as
foreign rather than familiar. What must carry across is the STRUCTURE (who is
on which side, what counts as a message, when a turn ends); the exact
curvature is a local decision. If you do choose to mimic your platform's
chat, measure it the way we measured ours — see the last paragraph.

### The two sides

| | Teacher | Assistant |
|---|---|---|
| Side | right | left |
| Fill | blue, RGB **(20, 147, 255)** | dark: **(59, 59, 61)**; light: **#E9E9EB** — flat, never translucent |
| Text | white | the ordinary label colour |

**Do not use the system accent colour for the teacher's side.** We did, and it
is a latent bug rather than a shade being slightly off: the accent is whatever
the user chose in system settings, and set to graphite it makes the teacher's
bubbles the same grey as the assistant's — at which point the left/right,
blue/grey distinction the whole window depends on silently disappears. The
blue is its own constant.

**The assistant's grey is a constant too, not a translucent token.** Ours was
"a system grey at 16% opacity" for a while, and a translucent fill can only
ever be as light as the window behind it allows — measured side by side on
the same backdrop it sat visibly darker than Messages'. Flat colours, both
appearances.

### The bubble

Ten rounds of measuring against the real thing, each round correcting the one
before (`GUI-IMPROVEMENTS.md` rows 177–178 have the blow-by-blow). The final
geometry, in points at 13pt text:

| | |
|---|---|
| Corner radius | **17** — an absolute of the design; it does NOT scale with the font |
| Radius rule | `min(17, height/2, width/2)` — single-line bubbles fall out as capsules, no separate branch |
| Visible text inset, each side | 13 |
| Text inset, top and bottom | 7 |
| Tail size | an absolute, like a pen width — one size on every bubble (`tailScale` = 17) |
| Tail drop BELOW the body | 5.1 (0.30 × tailScale) |
| Corner landing on the bottom line | 0.47 × radius — the one tail number that follows the radius |
| Tail tip, INSIDE the body's edge | 6.5 (0.38 × tailScale) |
| Hook rejoins the bottom edge | 14.5 in (0.85 × tailScale); root width ≈ 6.5 |

The two costliest wrong assumptions, both of which survived several rounds:

- **Nothing scales with the font.** The radius measured the same across two
  text sizes; so did the whole tail. An early pass scaled both down by our
  smaller font and every bubble read as subtly wrong beside Messages. (The
  OLD version of this section said the opposite — "scale the proportions to
  the corner radius". That advice cost us three passes. Constants.)
- **Cross-app constants come only from screenshots with BOTH apps in them.**
  Deriving one from two separate captures needs each capture's
  pixels-per-point; we guessed one wrongly and shipped a tail a fifth too
  large. Same screenshot, same screen — the scale cancels out.

Drawing the outline (still one continuous path, not a rectangle plus a
triangle):

- **The corner-to-tail joint is about the TANGENT.** The silhouette reaches
  its deepest inset exactly at the bottom line while travelling straight
  DOWN. A corner that lands travelling horizontally meets the tail in a cusp
  and the tail reads as a comma stuck under the bubble.
- **The jog into the tail gets exactly the radius of height**, held nearly
  flat for the first half with the dive concentrated in the last (a cubic
  with vertical end-tangents; late control ~0.215 of the span, early ~0.30).
  A longer span drifts early and reads as a diagonal cut into the side; a
  weighting that carries inset early reads as the bubble bulging.
- **No sharp vertices anywhere.** The tip is rounded about 1.5pt across, and
  the hook meets the bottom edge in a small curve, not a corner.
- **The underside of the tail is CONCAVE** — a diagonal with a mild sag
  toward the bubble, not a deep scoop. That curve, not the tip, is what makes
  the shape read as a tail.
- **Draw inside the bounds you are given.** Ours drew past its rect at first
  and was clipped — a clipped tail is severed, not pointed.

### Selecting text in a bubble

Messages pins its selection colours the way it pins its bubble colours:
light-appearance selection blue **(174, 218, 255)** behind the selected run
in BOTH appearances, with the selected glyphs painted in the bubble's own
fill. The system's dark-mode selection colour is a grey-slate that reads as
broken beside it. Two porting notes: our UI toolkit's built-in text selection
drew an unstylable grey and we had to drop to the native text control to
style it at all — check yours early; and the hook that styles selection must
be one that runs when selection machinery actually attaches (ours had a
first attempt that configured a text editor that did not exist yet, and it
failed silently).

### Tails mark turns, not messages

One tail per RUN: on the last thing a participant said before the other one
answered. A tail on every bubble makes three sentences look like three
separate attempts to get a word in — and it is the kind of thing that looks
fine in a screenshot of two messages and wrong in a real conversation.

The newest message always has a tail, since its turn has not been answered
yet. Anything nobody SAID — we have one such item, a note that a restore
happened — wears no tail and does not end anyone's turn; the rule looks past
it to the next thing that was actually said.

### What counts as a message

More things than you would first assume, and this is the part that matters
most for how the window reads:

- **What the assistant says.** Obviously.
- **What the teacher types.** Obviously.
- **Tool results.** "The preview is rebuilding now" is the assistant
  ANSWERING. That it came from a tool is machinery, and the teacher is not the
  audience for machinery. As plain lines with an icon these read as a log
  spliced through a conversation.
- **The plan.** It used to live only in the approval card, so pressing Go or
  Cancel destroyed the description of what had just been agreed to — and with
  it the context for everything after. A conversation you cannot scroll back
  through is not a conversation.
- **The question.** "Shall I go ahead?" / "Shall I deploy?" is its own
  message, which is what lets the card below be nothing but buttons.
- **The teacher's ANSWER.** Pressing Go records "Go" as a teacher message, in
  their bubble on their side. Reading back a conversation where the assistant
  asked, nothing answered, and yet something plainly happened is worse than
  not being able to read it back at all.

The general rule: **anything that is part of the conversation belongs IN the
conversation, and a control that owns text destroys that text when it
resolves.** Leave controls the choice and nothing else.

### The typing indicator

**A THOUGHT bubble, not a speech bubble** — a capsule with two plain circles
stepping down toward the speaker, the comic-strip sign for thinking, shown on
the assistant's side whenever the model is thinking or a tool is running —
both are waits with nothing on screen, and a teacher does not care which.
Ours wore the speech tail for a while and it read as off without anyone
being able to say why: a tailed bubble means SAID, circles mean composing.

Measured from a screen recording of Messages, as ratios of the capsule's
height (which equals a single-line message bubble, so the indicator occupies
the slot of exactly the thing it stands for): capsule ~1.7× as wide as tall;
dots 0.24 of the height with a gap about half a dot; the larger circle 0.41,
poking about two points past the lower corner; the smaller 0.14, below and
outside with a sliver of gap. Each dot lags the one before it (about 0.18s)
so the three read as a wave rather than a blink.

**Draw the capsule and both circles as ONE geometry filled once** (whatever
your platform's path-union is). As separate shapes, any translucency doubles
where they overlap and the join shows as a brighter seam.

### The box you type in

- A rounded field — continuous rounded rectangle, radius 17 — with the send
  button INSIDE its right end, rather than a plain field with a button parked
  beside it.
- **Never disable it to mean "busy".** A disabled field cannot hold keyboard
  focus, so the system moves focus to the next thing it can find; ours landed
  on the first disclosure group in the suggestion shelf, which looks like a
  bug in something else entirely. Typing and SENDING are separate
  permissions: the box stays live so a teacher can write their next message
  while they wait — every messaging app allows this — and only the send waits
  for the run to finish.
- **Focus returns to it after every send.** Two commands in a row should not
  need a click in between. This is also what keeps the arrow-key history
  usable, since that depends on the field having focus.
- Up and Down walk the teacher's own previous messages; see the history rules
  recorded in `GUI-IMPROVEMENTS.md` row 157.

### Two small things that are easy to skip

- **Emphasis has to be rendered.** Plans mark their headings bold, and in
  SwiftUI `Text(someStringVariable)` does not parse markdown at all — only
  string literals do — so it reached the teacher as literal asterisks until
  the text was parsed explicitly. Whatever your toolkit is, check how it
  treats a runtime string; several style literals only.
- **The suggestion chips take the pointing-hand cursor.** A plain button style
  keeps the look and suppresses the cursor, so it has to be put back by hand.

### How to get this right in less time than we did

Measure — and close the loop. Guessing produced wrong shapes; one screenshot
and a twenty-line script that read the pixels produced right ones in minutes.
The full method, each part of which was learned by paying for its absence:

1. **Trace silhouettes, don't eyeball.** Per-row min/max of the fill colour
   gives the exact edge profile; every number in the tables above came out
   that way.
2. **Only same-screenshot comparisons.** Both apps in one capture, or the
   pixels-per-point uncertainty eats the answer.
3. **Render YOUR result and measure it the same way.** The passes that
   shipped wrong all trusted arithmetic about what the code would draw;
   the passes that stuck rendered the real control offscreen and walked its
   pixels against the reference trace. Insets especially: native text
   controls put slack around their glyphs that no spec predicts — our final
   paddings are asymmetric (12 leading, 9 trailing) purely to cancel what
   the label actually draws, and only the render-measure loop could have
   found that.
4. **Expect the reference to correct you more than once.** Ten passes, each
   started by a human eye catching what the previous measurement missed, and
   each ending with the pixels agreeing the eye was right.

## Plan mode, undo, and how often to back up

Three decisions taken on the macOS side on 2026-08-15 that Windows should
match, because they are about how much to trust a local router rather than
about either platform.

### Plan mode: the model says what it heard before it acts

A local router is wrong sometimes. Measured over 290 trials, the small model
puts about **one request in five** on the wrong tool. Plan mode turns that
from something that happens into something a teacher declines: a write runs
its `plan_` twin first, the plan is shown in the twin's own words, and
nothing happens until they press Go.

- **Writes only.** Reads answer immediately. Gating "what do students see
  right now?" makes every question two clicks and teaches people to press Go
  without reading — which costs the gate its whole value.
- **Always on for the small model.** On the 1.5B it cannot be turned off at
  all; 79% is not a rate at which anyone should be handed a "stop asking"
  button. The macOS build ignores a remembered "off" answer when it finds
  itself on that tier, so a teacher who turned it off on a capable machine
  does not inherit that on an 8 GB one.
- **Offered off after five in a row, once, on the capable model only.** Trust
  is earned rather than assumed, and the offer arrives while five correct
  plans are still fresh rather than months later in a settings pane. A Cancel
  RESETS the run: somebody who has just stopped the assistant doing the wrong
  thing must not then be asked whether they would like it to stop asking.
- **Deploys always ask, plan mode or not.** A deploy puts work in front of
  students immediately and cannot be taken back by us.

### Undo is not version control, and it should not pretend to be

Worth stating because it is easy to assume otherwise: **courses are not git
repositories.** Nothing in the toolchain runs `git init`. The undo history is
in-memory before/after snapshots of the files each tool touched, held as a
stack for the life of the conversation, and it is gone when the window
closes.

It has one property worth copying exactly: before restoring a file it
compares what is on disk to what it wrote, and **skips anything the teacher
has edited since**. Publishing a class, then spending ten minutes writing it
in Obsidian, then saying "undo that" must not cost those ten minutes.

### Back up once per conversation, not once per command

The macOS build originally zipped the whole course before EVERY write. On an
Obsidian vault full of images that is slow and large, and a chat with six
commands made six near-identical copies.

It now backs up **lazily, once per conversation**: the first write makes the
zip, later writes reuse it, and a conversation that only reads makes none.
That single zip is also what the assistant's **Restore** offers — putting the
section back to how it was when the chat started, which is the safety net
that makes "just do it" mode reasonable to offer at all.

Two details that make the backups usable rather than merely present:

- **Provenance rides in the file name**, so a teacher choosing among several
  can tell what made each one and why — Plantoir before an assistant chat
  about a particular section, or themselves on purpose. A list of five
  identical-looking timestamps is not a choice anybody can make.
- **Prune only the ASSISTANT's own backups**, keeping its five most recent
  per course. A teacher's backup is a decision — they pressed Back Up because
  they were about to do something they were unsure of — and deleting it on a
  schedule they never agreed to is the app overruling them about their own
  work. The assistant's are different in kind: it saves one per conversation
  whether or not anybody asked, so clearing up after itself is its job. A
  teacher with twenty of their own keeps all twenty, and they never crowd out
  the assistant's five, because the two are counted separately.
- And prune ONLY backups at that: archives and the wizard's own zips live in
  the same folder and their parsers deliberately reject each other's forms.

### Restore is section-scoped, though the zip holds the course

The backup contains the whole course; a conversation is about one section. A
whole-course restore would silently revert work done in a sibling section
while the chat was open — a teacher may well have been editing Section 2 in
Obsidian while talking about Section 1. So Restore puts back only the section
the conversation was about, and says so on the button.

**Section-scoped means more than the section's folder**, and this is the part
easy to get wrong. The assistant can publish or unpublish a COURSE-LEVEL
shared page for one section, and that lives in the shared file's frontmatter
as `publishForSection<N>` — outside the section folder entirely. Restoring
only `section<N>/` would leave that half of the conversation's work in place.

The macOS build restores both: the section folder's contents, and — in every
shared page — only the keys carrying THIS section's number, spliced back from
the backup's own lines rather than re-derived. Copying the lines verbatim has
three consequences worth keeping: the older `draftSection<N>` spelling
survives untouched where a course still uses it, a key the conversation ADDED
is removed again, and every other section's keys plus the whole page body stay
byte for byte.

The section folder is emptied and refilled rather than swapped, for the same
reason `restoreBackup` documents: Obsidian holds the folder open.

**Say the surprising part in the confirmation, not in a doc.** Anything the
teacher changed in that section during the conversation goes back too,
including work done in Obsidian, and Plantoir cannot bring that part back.
That sentence belongs in the alert.


## plantoir.app is generated, and its screenshots are taken by a robot (entry 255)

The marketing site used to be one hand-written `site/index.html`. It is now
four pages — home, features, day to day, support — generated by
`python3 website/build.py` from sources in `website/`. Netlify still deploys
`site/`, unchanged, so nothing about hosting moved.

**Nothing here needs a Windows implementation for the site itself.** It is one
site for one product; a second one built on Windows would be a second product.
What Windows owed it was *pictures* — and that harness is now built and used:
`website/shots/capture_windows.py` and `website/shots/hero_windows.py` capture
every id in `website/shots.json` from a real Windows machine, and
`site/img/` carries the `<id>-windows-light.png` / `<id>-windows-dark.png`
pair for every one of them (`hero`, `assistant`, `courses`, `coverage`,
`colour-schemes`, `light-and-dark`, `new-course`, `preview`, `progress`,
`search`, and all four `site-*` shots) — confirmed 2026-08-22. This section
used to describe the harness as future work owed once the Windows app shipped;
it has shipped and this is done. What follows below is now history — how the
mac's own capture mechanism works and why it could not simply be copied — kept
because the lessons in it are real, not because the task is still open.

### What Windows built

Every image on the site exists twice, `<id>-light.png` and `<id>-dark.png`,
because the pages swap them with `<picture>` and
`media="(prefers-color-scheme: dark)"`. The ids are listed in
`website/shots.json` along with their alt text and captions. Windows captures
a third and fourth file per shot — `<id>-windows-light.png`,
`<id>-windows-dark.png` — using the same ids.

### Why the mac's capture mechanism will not port

Three mac-specific things carry this, and each needs its own Windows answer:

- **The window screenshots are native single-window captures, not test-runner
  screenshots.** The tests drive the app with XCUITest, but the pixels come
  from `screencapture -x -o -l <window-id>` — the programmatic equivalent of
  Command-Shift-4, Space, Option-click — because that is the only capture that
  delivers the window's rounded corners genuinely transparent, with macOS's
  own subpixel anti-aliasing. `window.screenshot()` was used first and bakes
  the desktop into the corner curves; masking the corners off afterwards
  approximates the radius and leaves stray fringe pixels, which is exactly the
  rendering-bug look a marketing page cannot carry (fixed in commit
  `63495853`). Whatever Windows uses (WinAppDriver, an accessibility-driven
  harness, `PrintWindow`) has to produce the window alone with its real alpha
  channel, not a screen crop and not a rectangle that gets its corners shaved
  off in post.
- **The window SIZE is forced, not remembered.** Passing
  `-"NSWindow Frame <autosave-name>" "<frame>"` as a launch argument puts the
  frame in AppKit's argument domain, which outranks the saved value — so every
  capture is 1280×800 regardless of where the window was left. The capture
  script saves and restores the remembered frames around the run, because the
  app writes them back on quit. Windows needs an equivalent: force the size,
  and put the teacher's own window size back afterwards.
- **Appearance is switched machine-wide.** There is no per-app override that a
  SwiftUI app reads, so the run sets the Mac to light, captures, sets it to
  dark, captures, and restores whatever it found — in a context manager, so a
  crash mid-run still puts it back. Windows has a per-user app/system theme
  setting; whatever is used there, restoring it is not optional.

### The trap that cost the most time here

`xcodebuild` does **not** hand its own environment to the test runner process.
Setting `MARKETING_WORKSPACE` and running the tests produced a green run with
one skipped test and no screenshots — success, and nothing to show for it. The
variable has to be passed as `TEST_RUNNER_MARKETING_WORKSPACE`, which arrives
in the test as `MARKETING_WORKSPACE`. Expect the same hop in whatever runner
Windows uses, and check the *count of captured images*, never the exit code.

### Three more traps, met on 2026-08-19, that will port themselves

- **The assistant photograph depends on a Settings toggle.** The picture is of
  the "Shall I go ahead?" card — but that card only appears when "ask before
  changing" is on, and the development machine's own copy may have it turned
  off. With it off the assistant does not fail: it CARRIES OUT the request,
  the capture shows "Unpublished 1 page." instead of a plan, and the demo
  course really has a page hidden in it afterwards — which then poisons the
  *other* appearance's capture with "It's already hidden." The harness must
  stage the setting on for the run and restore the teacher's own value after,
  exactly as it stages window frames (`capture.py` does this now). Windows
  keeps an equivalent setting; `capture_windows.py` photographs the assistant
  and needs the same staging.
- **Photograph progress when a step is NAMED, never after a fixed sleep —
  and know which steps can actually appear.** The progress shot used to
  wait for the progress view to exist and then sleep six seconds; on a
  machine with a warm container the whole build finished inside the sleep,
  and the capture showed the finished site — the same picture as `preview`,
  filed as progress. The test now waits for the milestone text to contain
  "Opening the preview" and shoots the moment it does. That sentence and
  not a prettier one, because instrumented 20 Hz polling showed it is the
  ONLY state a capture can reach: the launcher's early lines arrive in one
  buffered chunk, and the pre-build "Launching Quartz preview" line — the
  final milestone's marker — completes every milestone at once, so every
  earlier step is gone before a test can look. A preview then spends the
  whole build, minutes, on a full bar captioned with its last step — a
  product defect recorded in `TODO.md`, and one Windows shares, since the
  milestone tables and the launcher output are the same on both platforms.
  Two smaller traps inside that finding: the milestone sentence is the
  element's accessibility VALUE, and its label is empty — a wait on the
  label alone never fires while the sentence is plainly on screen — and
  the pointer-parking pause inside the save helper once outlived the very
  step being photographed, so park before waiting, not after. The built output is also cleared before EACH
  appearance pass, not once per run — clearing it once left the dark pass
  photographing the light pass's finished build.
- **Launch with window restoration off.** A capture that dies mid-test kills
  the app with two windows open (main plus assistant); every launch after
  that restores both, and every element query in every test then finds two of
  everything and fails with "multiple matching elements". On the mac the fix
  is the `-ApplePersistenceIgnoreState YES` launch argument; whatever Windows
  session-restore mechanism exists, captures must start from exactly one
  window.

### The demo sites were renamed on 2026-08-19

The published demo sites now follow a per-SECTION scheme —
`<code>-s<n>-2026-gordon.netlify.app`, e.g. `eng2d-s1-2026-gordon` — and
ENG2D has a section 2 site of its own. `capture.py`, `capture_windows.py`
and `website/site.json` carry the new names, but
`windows-app/Plantoir/Services/MarketingShotCapturer.cs` still writes the
OLD per-course names (`{code}-gordon-2026-27`) into its fixture configs'
`deploy_site_name`, in two places. Left for the Windows side to update
rather than edited blind from the mac, because the new scheme names a
SECTION and `deploy_site_name` is course-level config: the right value for
those fixtures — probably the section 1 name — is a judgement about how
that capturer uses them. The authoritative record of what is actually
deployed is the demo working folder itself:
`courses/<CODE>/.netlify_sites/section<n>.json`.

### The demo courses, and why those three

The screenshots are taken against a working folder holding ENG2D, MCV4U and
SCH3U, created through the app's own new-course panel rather than by writing
folders directly — so the pictures show what a teacher's folder actually looks
like, not what a script thinks it should. The three codes were chosen so that
between them the class sites show prose, typeset mathematics, and chemistry
notation, which is most of what anyone doubts a Markdown site can do.

Rejected: hand-made screenshots (they go stale silently, which is how a
marketing site ends up showing an interface that no longer exists), and a
headless browser for the class sites (it approximates macOS type rendering,
scrollbars and window chrome rather than showing them).


## The " — Edited" marker: knowing a section has changed since it published (entry 310)

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

## What the engine says now reaches a problem report — without a pipe (2026-08-20)

Answering the gap `MAC-HANDOFF.md` recorded the same day. Until now
`AssistServerHost` sent `llama-server`'s stdout and stderr to
`FileHandle.nullDevice`, so a report from a teacher whose assistant was
misbehaving could carry **nothing the engine had said** — no load error, no
slot warning, no timing. Windows already had `NoteServerLine` for this. The
mac now samples too, and the interesting part is what it does INSTEAD of a
pipe, and how narrow the filter is.

**A file, not a pipe, and the pipe is the trap.** `nullDevice` was never
laziness: a redirected pipe nobody drains fills up, and the engine then blocks
on its next log write, mid-request, looking exactly like a hung model. That is
the wedge Windows had to fix by draining both streams, and discarding the
output is precisely why the mac never had it. Swapping in a `Pipe` would have
traded a diagnostics gap for that bug. So both streams now go to ONE FILE in
the temporary directory, and a bounded tail is read **when somebody asks** —
never on the engine's timetable. A write to a file has no reader to wait for.
`AssistEngineLogTests.testTheEnginesOutputIsNeverReadThroughAPipe` pins it by
reading the source for `Pipe(` and `readabilityHandler`, because every other
test in the file would pass with the wedge back in.

`AssistServerHost.lines(in:since:atMost:)` is a free function taking the mark
by reference, so each look reports what arrived SINCE the last one; it reads at
most the recent 64 KB however long the engine has run, drops the part-line that
skipping ahead lands on, and resets a mark left past the end of a file that has
shrunk. `stop()` closes the handle but deliberately LEAVES the file — the
engine-never-became-ready path calls `stop()` before anybody has looked, and
the reason it never became ready is the last thing in there. `discardEngineLog()`
is the separate step, and a sweep on start removes anything older than a day
that a force-kill left behind.

**The filter is narrow, and the narrowness is measured, not guessed.** Driven
against the bundled engine on this Mac (llama.cpp b10435, Qwen2.5-1.5B, 2026-08-20):

- Lines carry a severity letter as their **second field** —
  `0.46.018.667 E srv send_error: …` — so `E` is the signal.
- **Warnings are deliberately NOT recorded.** A perfectly healthy start prints
  **six** of them: five are a CORS block warning that all origins are allowed
  and no API key is set (which cannot matter on a server bound to 127.0.0.1),
  and one is `control-looking token: 128247 '</s>' was not control-type`, a
  quirk of the weights. Recording warnings would have spent the entire budget
  on noise before the teacher asked anything.
- A word test sits beside the severity test as a fallback, matching `error`,
  `exception`, `failed`, `failure`. The severity field is this build's format
  and a future build could drop it; and it is what catches
  `W srv operator(): got exception: …`, the one warning worth having. Verified
  that none of the six healthy-start lines contain any of those words.

Two lines were provoked deliberately and both are caught: a malformed request
body (`got exception: … parse error`) and an over-long prompt
(`E srv send_error: … request (20030 tokens) exceeds the available context size
(8192 tokens), try increasing it`).

**When it samples.** Three moments, all in `AssistSession`:

1. **The engine never became ready** — the tail is taken with the filter OFF,
   because then every line is the diagnosis, ordinary ones included.
2. **Every fifteen seconds while the window is open**, filtered. Sampling only
   at teardown would have been simpler and would have missed the case this is
   FOR: a teacher whose assistant is misbehaving right now, filing a report
   without closing anything. The loop ends itself once the cap is reached, so a
   badly behaved engine costs a fixed amount of work rather than a permanent one.
3. **On `finish()`**, before the log is discarded.

**Capped at twelve lines per conversation.** The trail is deliberately coarse —
it is a record of what the TEACHER did, and its failure mode is that the one
line that mattered ends up on page forty. Twelve is enough for a model that
will not load and nowhere near enough to bury a morning's work. Lines are cut
to 200 characters, and go through `LogRedactor` on the way in like everything
else — which matters here, because the engine prints the model's full path.

**Verified end to end on the real app**, because none of the unit tests can
prove the wiring holds. A healthy conversation left the trail untouched, which
is the result that matters most — the filter is doing its job. An over-long
prompt then produced, about six seconds later:

```
23:23:36 · MCV4U/1 · the local AI assistant could not answer — The assistant's engine answered with an error (400).
23:23:42 · MCV4U/1 · the assistant's engine said: 0.56.869.873 E srv    send_error: task id = 114, error: request (11965 tokens) exceeds the available context size (8192 tokens), try increasing it
```

The first line is what a report carried BEFORE this change, on its own: an HTTP
status and nothing else. The second is the sentence that explains it. That pair
is the whole argument for the feature. The temporary log folder was empty after
quitting, so `discardEngineLog()` does clean up.

### This adds a contract event, and the Windows suite will go red

`contracts/shared-rules.json` → `activityTrail.mustRecord` gained
**`assistant engine said`**, and `ActivityTrail.Event` gained the matching
case. The test that compares the two lists runs on both platforms, so
**`Plantoir.Tests` will fail until `Plantoir.Core`'s event list gains the same
entry.** That is the mechanism working, not damage: it is a request, and it is
written up in `MAC-HANDOFF.md` as one.

The work on your side is small, because the hard half is already there.
`LocalModel.NoteServerLine` and `RecentServerLog` already keep a 60-line ring
buffer of exactly this output. What is missing is that nothing puts any of it
on the trail. Add the event, sample `RecentServerLog` at the three moments
above, and reuse the filter — **but re-measure the healthy-start noise on your
own engine build before trusting the warning rule.** Vulkan and CPU builds
print different startup lines from the Metal one, and the whole reason
warnings are excluded here is a specific set of six lines that may not be your
six. Say what you measured.

One difference worth keeping rather than closing: Windows drains into memory
because it must (a redirected pipe has to be read), while the mac writes to a
file because it can. Do not "bring the mac into line" by switching it to a
pipe — the file is what makes the no-blocking-read property structural rather
than a promise about always having a reader attached.

## Testing

- The **PowerShell launchers are tested on real Windows** — all three have
  been driven end to end through the app: course creation, preview (including
  `--stop` reclaiming native processes), and publishing to all three
  destinations, most recently a live Cloudflare Pages publish. The appendix at
  the end of this file is **doubly historical**: it documents the WSL2/Docker
  Engine architecture the launchers used before the 2026-08-19 move to the
  native runtime (see the note near the top of this file) — read it for the
  reasoning behind that earlier design and the ConPTY/path-translation lessons
  that still generalise, not as a description of what `setup.ps1` /
  `preview.ps1` / `deploy.ps1` do today, and not as a to-do list.
  (An earlier version of this bullet said they were UNTESTED and told you to
  test them first. That was a week out of date and would have sent a session
  down a dead end.)
- `verify.sh` is the toolchain gate on macOS/Linux; a Windows verify
  script should mirror it, including its cross-check that every helper a
  launcher calls is defined in that same launcher file (a missing helper
  is exit 127 at runtime, on the one path nobody tests).
- Mirror the macOS test discipline: the unit suite runs without Docker;
  presentation regressions get press-and-look tests (entry 81's lesson:
  button logic can be perfect while its dialog never shows).

### Pinning the trail as wired, not merely declared (mac, 2026-08-19)

Windows found the gap (2026-08-19, `MAC-HANDOFF.md`): three trail events sat
in `ActivityTrail.Event`, the contract test compared the enum against
`shared-rules.json` → `activityTrail.mustRecord` and passed — and nothing
ever CALLED them, so a release smoke left zero lines for a course creation,
a preview and a deploy. A list-against-list pin structurally cannot catch a
declared-but-never-called event. The mac now has a second pin, and Windows
should mirror it:

- **A source scan**
  (`mac-app/Tests/QuartzTeachersTests/ActivityTrailWiringTests.swift`):
  for every `Event` case, fail unless `.caseName` is referenced somewhere in
  product source outside the enum's own declaration and outside comments.
  The C# mirror is the same idea over `windows-app/` product sources for
  each `ActivityTrail.Event` member (locate the source tree from the test
  assembly the way the mac test uses `#filePath`). Include a guard that the
  scan actually found a plausible number of source files, so a moved folder
  fails loudly instead of passing vacuously.
- **Its honest limit, so nobody oversells it**: the scan proves a call site
  EXISTS, not that it is reached. The mac additionally runs `noteLaunch()`
  against a scratch store and counts its three lines. Full runtime coverage
  of every event would mean driving every feature in unit tests; REJECTED as
  disproportionate — the failure Windows actually shipped was
  zero-references, which the scan catches outright.
- **The suite-pollution fix differs by platform for a reason.** Windows'
  `[ModuleInitializer]` redirect (`TestTrailRedirect.cs`) is right for xUnit,
  where tests run in their own process. The mac CANNOT use that shape: its
  test target is app-hosted (`TEST_HOST`), so the host app writes its launch
  lines before any test-bundle code loads. Instead the redirect lives in the
  product (`ProblemReportStore.standard` returns a throwaway folder when
  `XCTestConfigurationFilePath` is in the environment), and
  `testTheSuiteWritesToAThrowawayTrail` pins it so a refactor cannot lose it
  silently. Worth a matching pin on Windows: one test asserting the trail
  path is the redirected one, so the module initializer's presence is itself
  under test. Verified on the mac empirically: `activity.txt` byte-identical
  (same SHA-1) before and after a full suite run.

## Documentation map

- [`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md) — write-ups
  for handoff items verified DONE in `windows-app/` as of 2026-08-22, moved out
  of this file for length. Read it for the reasoning behind something that has
  already shipped.
- [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — THE spec (179 entries as of
  2026-08-15). Its **Windows status** section is where coverage is tracked.
- [`documentation/`](documentation/README.md) — toolchain deep dives 01–10.
- [`CLAUDE.md`](CLAUDE.md) — the repository's entry point: conventions,
  testing, setup, and the traps that cost time.
- [`RELEASING.md`](RELEASING.md) — cutting a release, both platforms.
- [`research/ai-assist/`](research/README.md) — the assistant's
  measurements, and `HISTORY.md`, which is the feasibility work, the build
  handoff and the original MCP proposal in one place.
- The WSL2/Docker launcher background — history, superseded by the native
  runtime on 2026-08-19 — is the **appendix at the end of this file**.
- [`mac-app/`](mac-app/README.md) — the reference implementation; when an
  entry's Windows note is thin, read the Swift it references.


---

# Appendix — WSL2/Docker background and the original .ps1 test plan (SUPERSEDED)

> **This entire appendix describes an architecture Windows no longer runs.**
> On 2026-08-19 the launchers dropped the Docker-Engine-inside-WSL2 path this
> appendix documents in favour of a native runtime — see "Windows no longer
> runs any of this in a container" near the top of this file, and
> `GUI-IMPROVEMENTS.md` entry 290. There is no `Ensure-ContainerRuntime`, no
> `docker` function, no image tag, and no WSL2 dependency in the current
> `.ps1` files. **Read what follows as history** — why the WSL2/Docker design
> was chosen over plain Docker Desktop, the `ProcessStartInfo`
> token-injection and path-translation lessons (some of which still
> generalise to the native code, some of which no longer apply at all), and
> the shape of a real end-to-end test pass on Windows 11 — never as a
> description of current behaviour or as a to-do list for new work.

*Folded in from the former `WINDOWS-TESTING.md` on 2026-08-15, back when the
WSL2/Docker path below was current. Two facts in it were corrected on the way
in: the token file is `/tmp/deploy_pat` (renamed when Cloudflare support
arrived, since one file now serves both providers), and deploys are no longer
Netlify-only. Both of those facts are themselves now mac-only, since the
token file and its container no longer exist on Windows.*

> **Status (2026-08-13): the launchers are no longer untested.** — true at
> the time, of the WSL2/Docker launchers this appendix describes. All three
> had been exercised repeatedly on real Windows 11 through the app — course
> creation, preview (including `--stop` reclaiming container-side
> processes), and publishing to all three destinations, most recently a live
> Cloudflare Pages publish end to end. Superseded by the same rewrite: the
> current launchers have been re-tested end to end against the native
> runtime (see "Testing" above), and this status line is left in place only
> as part of the historical record, not as a current claim.
>
> One thing it does NOT cover, and worth knowing: `verify.sh`, the
> toolchain gate named in [`CLAUDE.md`](CLAUDE.md), **cannot run
> on Windows** — it is bash and (as originally written) expected `docker` on
> `PATH`. That remains true today, though the reason has changed: there is no
> longer a `docker` to expect on Windows at all, containerized or otherwise.
> Toolchain changes made on Windows are verified by driving a real publish
> through the app instead.

> **Audience:** a Claude Code session running on the maintainer's Windows 11 Pro
> machine. This file gives you the context needed to test (and fix) this
> toolchain's Windows launchers.
> Read this fully before touching anything. If you are building the Windows
> APP, start with [`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md).

### Mission

The toolchain recently **dropped its Docker Desktop requirement**. On
Windows, the PowerShell launchers (`setup.ps1`, `preview.ps1`, `deploy.ps1`)
now provision and use the **Docker Engine inside WSL2** automatically. That
code was written and parse-checked on macOS but has **never executed on a
real Windows machine**. Your job: exercise it end to end on this machine,
find what breaks, fix it, and report.

### Background (5-minute orientation)

- This repo publishes teaching websites from Obsidian vaults using a Docker
  container that wraps a patched Quartz v4.5.0. There is **no registry**:
  the launchers hash the folder's build recipe and build the image locally
  as `teaching-quartz:src-<hash8>` (`Get-BuildContext` / `Get-ToolchainHash`
  / `Build-ImageIfMissing` in the `.ps1` files). Full architecture docs:
  [`documentation/README.md`](documentation/README.md),
  especially [`documentation/03-launcher-scripts.md`](documentation/03-launcher-scripts.md)
  (the section "Container runtime bootstrap" describes exactly what you are testing).
- The teacher-facing flow is: `setup.bat` (interactive course wizard) →
  `preview.bat COURSE SECTION` (build + serve; the launcher prints the
  host address — each working folder gets its own probed port block) →
  `deploy.bat COURSE SECTION` (delta deploy — Netlify by default,
  `--target cloudflare`, or `--to-folder <path>`).
- Each `.bat` is a thin wrapper that runs the `.ps1` beside it.
- The macOS counterpart of this change (Colima) is **already tested and
  working** — treat the `.sh` scripts as the reference for intended behaviour.

### What the new Windows code does

In each of the three `.ps1` scripts, near the top, there is an identical
block: `Ensure-ContainerRuntime` plus helpers. Its intended behaviour:

1. **Fast path:** if a native `docker` (docker.exe) works, use it unchanged.
2. Otherwise require `wsl` + an installed distribution (else print
   `wsl --install` guidance and exit).
3. Probe `wsl -e docker info` as the default user, then as root
   (`$global:WslUserArgs = @('-u','root')`).
4. If the engine is missing inside WSL, offer to install it:
   `apt-get install docker.io` as root, then `usermod -aG docker <user>`.
5. Start it with `wsl -u root -e sh -c "service docker start"` and poll.
6. On success, define `function global:docker { & wsl $global:WslUserArgs -e docker @args }`
   so every later `docker …` call in the script transparently routes through
   WSL. Bind-mount paths are translated with `Get-MountPath` (wslpath →
   `/mnt/c/...`). `deploy.ps1` additionally has two
   `System.Diagnostics.ProcessStartInfo` invocations that bypass PowerShell
   command resolution — these use `$DOCKER_EXE` / `$DOCKER_PREFIX` variables
   instead.

### Environment notes for this machine

- Windows 11 Pro (build 26100), PowerShell 5.1 minimum target (also test
  under `pwsh` 7 if installed).
- Clone/pull this repo; **test the repo's `.ps1` files directly** (in
  production they reach teachers via the app's `.toolchain/` mirror).
- The repo stores files with **LF line endings** (depending on
  `core.autocrlf`, your checkout may or may not have CRLF). PowerShell
  handles LF `.ps1` fine. If a `.bat` misbehaves with LF endings, invoke the
  `.ps1` directly (`powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1`)
  and note the finding — in production, teachers receive CRLF copies (the
  image build runs `unix2dos`).
- The container image is **built locally by the launcher on first run**
  (BuildKit required — `Ensure-Buildx`); expect the first run to take a few
  minutes and to need the network. A changed recipe changes the tag and
  rebuilds.
- `courses/` is gitignored — a fresh clone has no courses. The setup wizard
  offers to install an Example Course (**EXC2O**); say yes and use it as the
  test fixture throughout.

### Test plan (in order)

Work through these scenarios; after each, note PASS/FAIL and any output worth
keeping.

**1. Static review.** Read `Ensure-ContainerRuntime` in all three `.ps1`
files and flag anything that cannot work on PowerShell 5.1 before running
anything.

**2. Specific mechanisms I could not verify from macOS** — test these in an
interactive PowerShell first:
   - Empty-array argument flattening: `$e = @(); wsl $e -e echo hi` — confirm
     no stray empty argument reaches wsl (this pattern underpins
     `Test-WslDockerReady` and the `docker` function).
   - `$env:WSL_UTF8='1'; wsl -l -q` — confirm clean, parseable distro names.
   - `Get-Command docker -CommandType Application` behaves on PS 5.1 when no
     docker.exe exists (should return nothing, not throw).
   - After `usermod -aG docker <user>`, does `wsl -e docker info` work
     without `wsl --shutdown`? (The scripts fall back to root if not — confirm
     the fallback engages.)

**3. Scenario: engine not installed.** If this machine's WSL distro has no
Docker engine (or remove it: `wsl -u root -e sh -c "apt-get remove -y docker.io"`),
run `.\preview.ps1 EXC2O 1 --build-only` (after setup) or `.\setup.ps1` and
confirm the install offer appears, works, and the run continues to success.

**4. Scenario: engine stopped.** `wsl --shutdown`, then run a launcher —
confirm it starts the engine itself and proceeds.

**5. Scenario: engine running (fast path).** Re-run immediately — confirm no
install/start work is repeated.

**6. End-to-end teacher flow.**
   - `.\setup.bat` → install the Example Course (EXC2O).
   - `.\preview.bat EXC2O 1` → confirm the container is created with a
     `/mnt/c/...` mount, the build succeeds, and `http://localhost:8081`
     renders in a Windows browser (WSL2 localhost forwarding).
   - Check interactive fidelity through the `wsl`-routed `docker exec -it`:
     wizard prompts, and especially the arrow-key colour scheme picker if you
     run a full course setup.
   - `.\preview.bat EXC2O 1 --build-only` then, **only if a Netlify token for
     a throwaway account is available**, `.\deploy.bat EXC2O 1`. Deploys
     create real Netlify sites — skip otherwise and note as untested.

**7. Edge cases.**
   - Run from a folder whose path contains spaces (e.g.
     `C:\Users\<me>\Class Websites Test\`) — mount translation and quoting.
   - Move the folder, run again — the container NAME is derived from the
     folder's path hash, so a moved folder gets a brand-new container (and
     the old one is left stopped); confirm the new one mounts the new
     `/mnt/c/...` path.
   - Two working folders at once: confirm each gets its own container
     (`teaching-quartz-<hash>`) and its own host port block (bases 8081,
     8091, …, each with a +1000 websocket block), and that two previews can
     run simultaneously.
   - `.\preview.ps1 EXC2O 1 --port 8082` — the per-preview port flag.
   - After any build, confirm the merged output contains the generated
     social sharing card (`.merged_output/section1/quartz/static/og-image.png`
     should be a title card in the course's colours, not the stock Quartz
     crystal — the card is drawn by `scripts/social_card.py` inside the
     container, so no Windows-side work is involved).
   - `deploy.ps1`'s token-injection steps (the `ProcessStartInfo` ones) — the
     `$DOCKER_PREFIX` quoting through `wsl.exe` is the riskiest untested
     code; verify `/tmp/deploy_pat` arrives in the container intact
     (test with a dummy: pipe text through the same command shape).

### When you find problems

- Fix them in the working tree, keeping the structure parallel across the
  three `.ps1` files (the block is intentionally identical in each) and
  consistent with the `.sh` reference behaviour.
- Commit to a branch named `windows-wsl2-fixes` with clear messages; do not
  push to `main` directly.
- Finish with a summary: scenarios run, PASS/FAIL each, fixes made, and
  anything that remains untested (e.g., a true fresh `wsl --install` if this
  machine already had WSL).

### Ground rules

- Never uninstall WSL or delete existing WSL distros without asking first.
- Images are only ever built locally; there is nothing to publish.
- Netlify deploys are opt-in only (they create public sites).
- The `.sh` files are macOS-only — do not "fix" them on Windows.

---

### Results — 2026-08-11 (Claude Code, maintainer's Windows 11 machine)

Run on Windows 11 Pro 26200, WSL 2.5.10 (no distro pre-installed —
Ubuntu-24.04 installed for the tests), Docker Engine 29.1.3 inside WSL,
PowerShell 5.1. Fixes were committed to **main** at the maintainer's
direction (overriding this brief's branch instruction). Interactive
runs were driven through `windows-app/PtyDriver`, a ConPTY harness that
gives the launchers a real TTY.

**1. Static review — FAIL → fixed.** Beyond parse-checks (clean), five
faults found and repaired: (a) preview.ps1's image resolution was
inverted — every run without `--image` printed "missing the toolchain's
build recipe" and exited 1; (b) a single trailing flag arrived as a
STRING, so `$Flags[0]` indexed characters ("Unknown option: -") — now
always an array; (c) the three scripts hashed different paths for the
container name (setup hashed the invocation directory before its
Set-Location; casing changed the hash) — all three now hash the
folder's physical path via GetFinalPathNameByHandle, after
Set-Location; (d) no exit-code propagation from the final docker exec;
(e) `Ensure-Buildx` guarded WSL work with an always-true null check.
Also: under `$ErrorActionPreference='Stop'`, PS 5.1 turns wsl.exe
stderr into TERMINATING errors at any redirected call site — probes
that legitimately fail (inspecting a not-yet-built image) killed the
script. The global docker wrapper now relaxes the preference around the
wsl call. Two milestone lines the app watches for were added
("Setting up this PC - a one-time step ...", and preview's
"Starting container if needed ...").

**2. Mechanism checks — PASS.** Empty-array flattening (`wsl $e -e
echo hi` → clean), `WSL_UTF8=1` distro names parse, `Get-Command
docker` returns nothing without throwing when no docker.exe exists.
usermod fallback untested (the test distro runs as root by default).

**3. Engine not installed — PASS (command path).** `apt-get install
docker.io` inside WSL (the script's exact command) installed engine
29.1.3; the interactive install-offer prompt itself was not exercised
end-to-end (the engine was installed before the first full run).

**4. Engine stopped — PASS.** `service docker start` + poll brought the
engine up from cold.

**5. Fast path — PASS.** With the engine running, no install/start work
repeats; runs go straight to the container checks.

**6. End-to-end teacher flow — PASS.**
- `setup.ps1 --install-example`: image built locally from the recipe
  (BuildKit via buildx in WSL), container `teaching-quartz-<hash8>`
  created with `/mnt/c/...` mount, EXC2O installed, and
  `EXAMPLE_COURSE_CODE=EXC2O` printed for the app.
- `preview.ps1 EXC2O 1`: "Preview will be available at:
  http://localhost:8081/" announced; page served HTTP 200 with the
  correct title through WSL2 localhost forwarding.
- Interactive fidelity through the wsl-routed `docker exec -it`:
  works under a pseudo console — with one CRITICAL caveat: the process
  that creates the ConPTY must not itself have redirected stdio, or
  the child inherits stale pipe handles and wsl reports "the input
  device is not a TTY". (The Plantoir app, a GUI process, is naturally
  clean.)
- `deploy.ps1 EXC2O 1` with a throwaway token pre-stored in Credential
  Manager: Netlify site created, 233 files uploaded with streaming
  counts, "✅ Deploy complete.", exit 0, site live over https. The
  first-run token-paste prompt was not exercised (token pre-stored);
  `/tmp/deploy_pat` injection via ProcessStartInfo worked — the token
  reached the container intact.

**7. Edge cases.** Two-folder concurrency, moved-folder recreation,
spaces-in-path, and `--port` were NOT yet exercised on this machine
(the per-folder hash and port-block logic are covered by unit tests in
`windows-app/Plantoir.Tests`). The generated social card was verified
present after the build (`.merged_output/section1/quartz/static/
og-image.png`, 28 KB, drawn in-container). Remaining scenarios are the
first candidates for the next session.

**Untested overall:** a true fresh `wsl --install` (WSL itself was
already present), the docker-group/usermod fallback, and pwsh 7 runs
(everything above ran under Windows PowerShell 5.1).

---



## Salvaged capture fixes from a stranded branch need a Windows build/test pass (2026-08-22)

`issue/mac-site-shots-unmerged` sat unmerged since 2026-08-19 while `dev`
independently re-solved most of what it was doing (the Safari
appearance/address-bar verification in `safari.py`, dropping
`mask_window_corners` for `screencapture -l`'s own transparent corners, and
the one-appearance-per-process Windows capture — all landed 2026-08-20,
superseding the branch's older versions of the same ideas). The branch was
not merged and was left to be deleted; see `MAC-HANDOFF.md`'s "Done" ledger
for the full salvage/discard breakdown.

Three of its Windows-only fixes were still real and NOT on `dev`, so they were
hand-ported from a macOS session (no Windows session involved) into
`issue/windows-capture-dialog-fixes`: `NewCourseDialog.StageForCapture` now
calls the same `Refresh*` methods a teacher's own typing would trigger (it
previously left the staged New Course dialog panel looking empty — no
course-name suggestion, no club row); the staged dialog card's `MaxHeight`
went from 680 to 720 (was cutting the Language/region row through its own
control) and now reads `dialog.Title` instead of hardcoding "New Course";
`AssistWindow` gained `ShowPromptShelfForCapture()` so a staged capture shows
the prompt shelf instead of a blank top third. Full row: `GUI-IMPROVEMENTS.md`
#316.

**This has not been built or tested — there is no .NET SDK on the macOS
machine that ported it.** Before merging: `dotnet build` +
`dotnet test Plantoir.Tests/Plantoir.Tests.csproj`, then a real
`--capture-marketing-shots` run to look at the New Course dialog and assistant
window shots by eye. If either the New Course dialog's field layout or the
assistant window's ready-state layout has changed since 2026-08-19, these
three edits may no longer apply cleanly or may need adjusting to match.

