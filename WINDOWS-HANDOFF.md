# Windows App — Handoff

> **New to this side? Read [`WINDOWS-BOOTSTRAP.md`](WINDOWS-BOOTSTRAP.md)
> first.** It says what to read, what to do in what order, and asks you to
> outline the plan before implementing. This file is the reference it sends
> you to.

Read this first when working on the Windows app — `windows-app/`, WinUI 3,
first take built 2026-08-11 — and especially when syncing it after a run of
macOS-side sessions. It gathers everything a Windows implementation needs; the
deep dives it links to are kept current. **Do not work through it top to
bottom.** Outstanding work is not in this file at all — it is in [GitHub
issues](https://github.com/russellgordon/plantoir/issues), filtered by the
`windows` label. Read "Where Windows actually stands" immediately below for
what is true on this side, and use `GUI-IMPROVEMENTS.md`'s **Windows status**
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
there if you need the reasoning behind something that already shipped. Since
2026-09-08 this file holds no task list at all: it is reference material, and
what is still open is in GitHub issues.

## Where Windows actually stands (read from the code, 2026-08-22)

**Read this before planning.** `WINDOWS-BOOTSTRAP.md` § 0 asks you to write a
plan before touching anything, and a plan needs to start from what is TRUE on
this side rather than from what the rest of this file describes. **If you find
an issue already done, or one of the "done" claims above wrong, say so** — on
the issue itself, the same way this side is expected to say so when the
contract is wrong.

### The outstanding work is in GitHub issues

Moved there on 2026-09-08, replacing the numbered list this section used to
carry. Open work is at
<https://github.com/russellgordon/plantoir/issues?q=is%3Aopen+label%3Awindows>;
a milestone says which release it is pinned to.

**Keeping it there is the standing instruction that the list used to be**
(`CLAUDE.md` rule 3). A macOS session that creates work for Windows opens an
issue labelled `windows`, in the same session, saying what the change is, what
Windows inherits free, what they owe, and where the section explaining it is.
The numbered list is gone rather than archived: every item on it was either
struck through as done — and the shipped record of that is
`GUI-IMPROVEMENTS.md` and
[`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md) — or still open,
in which case it is now issues #66 and #68–#70, plus #99 (which absorbed the
old item 42).

Everything below this point is reference material: it was never a task list,
and it is what this file is for now.


### One thing NOT to do

Do not port entry 142 (Colima sizing) or entries 244–245 (`launchd`). They are
macOS mechanics. The transferable half of 244–245 is a single lesson worth
having before you touch `TaskScheduling.cs`: register a scheduled job as the
APP, not as the shell it happens to run, or the operating system tells the
teacher that "bash" — or, on the second attempt here, a person's name — wants
to run in the background.


## A test host that segfaults, and the six levers that look like they should fix it

Written 2026-09-07, for whoever meets a modal that kills a test process rather
than failing an assertion. It is macOS mechanics — none of the code transfers —
but the SHAPE of the fault and the way it was cornered do, and the dead ends are
the expensive part. Item 39 in the outstanding list says what, if anything, you
owe. This is the manual.

### The fault

The mac unit suite hosts the real app, so its tests act on the real window. A
test setting `renameProblem` puts a genuine `NSAlert` sheet on screen; clearing
it takes the sheet down. All 38 crash reports from 2026-09-01 to 09-07 share one
stack, and every one carries `libXCTestBundleInject.dylib` — they are all test
hosts. Innermost last:

    XCTest pumps the runloop
      CA::Transaction::commit()
        -[NSWindow _layoutViewTree]                  <- a layout pass starts
          NSHostingView.layout()
            +[NSAnimationContext runAnimationGroup:]
              ViewGraph.updateOutputs -> preferencesDidChange()
                AppKitDialogBridge.updateExistingAlert(allAlerts:id:)
                  NSWindowEndWindowModalSession
                    -[NSWindow(NSSheets) _orderOutRelativeToWindow:]
                      -[NSSheetMoveHelper closeSheet]
                        -[NSMoveHelper _doAnimation] <- spins a NESTED runloop
                          the display cycle is re-entered -> null deref

Two independent things have to be true at once, and naming both is what made it
tractable. SwiftUI ends the modal session from **inside a layout pass**; and
AppKit's sheet animation **spins a nested runloop** — in its own private
`_NSMoveTimerRunLoopMode` — to drive itself. A nested runloop entered from inside
a display-cycle callback re-enters the display cycle. It is one call stack on one
thread. **It is not a race**, which is the single most useful thing to know: no
delay, no extra settling and no ordering tweak could ever have made it safe, and
an afternoon spent adding sleeps would have been an afternoon wasted.

### The six levers that do not work, with numbers

Every one of these is the obvious answer, and all five are dead. Measured on
macOS 26.6 (25G72) by swizzling `-[NSMoveHelper _doAnimation]` and timing it, in
a standalone AppKit probe rather than in the suite:

| lever | close animation |
|---|---|
| nothing (baseline) | 0.268 s |
| `-NSAutomaticWindowAnimationsEnabled NO` | 0.268 s |
| `NSWindow.animationBehavior = .none` on the sheet | 0.264 s |
| the same on the sheet's PARENT window | 0.270 s |
| `endSheet` inside a zero-duration `NSAnimationContext` group | 0.267 s |
| `-NSOrderOutSheetWhenEnded NO` | 0.266 s |
| parent window never ordered on screen | 0.264 s |

The first is the cruel one. `NSAutomaticWindowAnimationsEnabled` is the key
everybody reaches for, it is real, and AppKit **reads it on this very path** —
hooking `-[NSUserDefaults objectForKey:]` during a sheet close shows it consulted
alongside `NSOrderOutSheetWhenEnded` — and then ignores it for the sheet move. A
reviewer checking "is this key real?" gets yes; only measuring gets the truth.
Reduce Motion was not tried and is near-certainly dead too: no accessibility key
appears among the four read on that path.

### What does work: the class's own switch

`NSSheetMoveHelper` declares its own `-shouldSkipAnimation`, overriding
`NSMoveHelper`'s. Forcing it to answer true is how AppKit itself takes a sheet
out of the animation. One `method_setImplementation` on the SUBCLASS's own
method, in the test bundle only.

**It is AppKit's own branch, not a hole punched in AppKit.** Disassembling
`-[NSMoveHelper _doAnimation]` on macOS 26.6: the flag is read at +192, and true
branches to +216 → `_stopAnimation` → return at +252 — before the
`CFRunLoopRunInMode` at +488. That is the identical branch AppKit takes when its
own `inhibitWindowAnimations` is set. A logging implementation over the live
selector shows `shouldSkipAnimation` is consulted from exactly one place,
`_doAnimation`, reached from `openSheet`/`closeSheet`/`animateResizeToFrame:`
and nowhere else — so a sheet RESIZE is covered by the same switch, and nothing
but the animation is gated by it.

| | `_doAnimation` runs | nested mode entered | open / close blocked |
|---|---|---|---|
| unchanged | 2 | **yes** | 0.281 s / 0.267 s |
| force `shouldSkipAnimation` | 2 | no | 0.020 s / 0.008 s |
| empty `_doAnimation` override | 0 | no | 0.020 s / 0.005 s |

Sheet frame identical in all three, completion handler run, window takes another
sheet afterwards.

**The empty override was tried first and rejected, and the reason generalises.**
Both work. The switch is better because AppKit's own skip path leaves the state
AppKit intends to leave, BY CONSTRUCTION, rather than by our having probed that
dropping `setUpAnimation`/`cleanUpAnimation` happens to be symmetric; because the
switch is declared on the sheet subclass, so scoping needs no `class_addMethod`
and no fallback branch to reason about, where `_doAnimation` is declared only on
`NSMoveHelper`, which animates ordinary window moves too; and because it puts the
test host in a configuration the framework already ships to real people instead
of one nobody runs. **Where a framework has its own switch for the behaviour you
want off, use the switch rather than removing the behaviour** — that is the part
worth carrying to WinUI.

### Two things about testing it that cost time

**A test that cannot fail is not a test.** The first version raised a sheet,
closed it, and asserted the sheet had gone — which passes identically with the
fix removed, because the assertions come after a sleep that outlasts the 0.268 s
animation. It looked like a regression test for a day. The version that works
registers a `CFRunLoopObserver` for `_NSMoveTimerRunLoopMode` and asserts it
never fires: it watches for **the exact frame in the crash stack**, has no timing
threshold to go flaky on a busy machine, and was checked by putting the fault
back and watching it fail. If you pin an intermittent, pin the mechanism, not a
symptom you can outlast.

**Measure with enough runs to mean something.** The rate here was about one run
in three, so a fix "confirmed" by two green runs would be confirmed 44% of the
time by doing nothing at all. Baseline and fix were each run 30 times, same
command, same machine, same session.

**And measure at the scope the GATE runs, not the scope that reproduces
fastest.** This is the one that nearly shipped a defect. The single class was
clean 30 times out of 30, which is where an honest-looking session would have
stopped. The full suite then aborted 8 times out of 8 — a DIFFERENT crash, an
over-released `_NSWindowTransformAnimation`, in the class that happens to run
next alphabetically. It was caused by the tidy-up a review had asked for
(closing the window the new test borrowed), and a single-class loop can never
see it, because the damage only lands on whatever runs afterwards. Isolating it
took four runs, and the fourth is the one that mattered — reproducing it with
the fix TURNED OFF, which is what proved the crash had nothing to do with the
fix and everything to do with the tidy-up. **When two things changed and
something broke, turn one of them off rather than reasoning about which is more
suspicious.**

### And the half of it that is a product rule, not a test rule

This mechanism is reachable in the SHIPPING app, and has fired once:
`GUI-IMPROVEMENTS.md` row 391, 2026-09-05, when a rename dismissed a sheet and
raised an alert in the same breath. `contracts/shared-rules.json` →
`siteHealth.repair.oneAlertAtATime` is the rule against it, and its stated reason
used to say only that one of the two alerts is lost. It now says what actually
happened. **A rule whose reason understates the consequence is a rule somebody
will trade away**, and that is the reason to keep the sentence accurate rather
than tidy.

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
  that section's `node.exe` / `python.exe` processes by COMMAND LINE —
  never the working directory, which `Win32_Process` does not expose at
  all — walks their descendants, and `Stop-Process`es them, and never
  starts anything itself. (Corrected 2026-09-05: this said "command line
  and working directory" for months, which is the mac's mechanism, not
  this one. The rule both platforms must agree on is now written down
  once, in `contracts/shared-rules.json` → `stopPreview`.) Call it
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
| `prepopulate_example_content` | Whether one of the 38 ready-made courses is poured in. |
| `include_curriculum_pages` | Whether that payload's Curriculum folder comes with it. |

**`use_skeleton` was not written by the Windows wizard at all** (checked
2026-08-16; written since 2026-09-07, item 25). The Python then fell back to
its own default — `True` — so a Windows teacher got a skeleton and was never
asked. That is the question MOST teachers meet, because around 1,900 course
codes have a skeleton and no payload; only 38 have a ready-made course.

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

### A divergence flagged by sweeping, 2026-08-16 — checked again 2026-08-23, not present

`deploy.py` writes a marker the first time a section goes out —
`.netlify_sites/section<N>.json` or `.cloudflare_sites/section<N>.json` — and
both apps read it to answer "has this ever been deployed?". That answer decides
whether a scheduled deploy is allowed, because a FIRST deploy asks what to call
the website and nobody is awake at 06:30 to answer.

The mac reads the marker for the destination the course is configured for NOW.
This section originally warned that `AssistWorkspace.cs` accepted EITHER
folder — so a course deployed to Netlify and later switched to Cloudflare
would read as "already deployed" on Windows, letting a teacher schedule the
one deploy guaranteed to stop at a prompt in the dark. **Re-checked 2026-08-23
(item 7 above): that is not how the current code behaves.**
`DeployCommand.HasDeployedBefore`/`FirstDeployMarkerPath` are keyed by the
specific destination type, and every caller passes the CURRENT destination's
type — never both. A regression test
(`ScheduledDeployTests.ASwitchedDestinationIsNotConsideredDeployedJustBecauseTheOldOneWas`)
now pins exactly the switched-destination scenario this section described.

The rule and the paths are in `contracts/file-formats.json` →
`firstDeployMarkers`, including the third case: a folder deploy keeps no
marker at all and counts as always-deployed, because it asks nothing. That
file's `knownDivergence` field, which used to describe this Windows bug, is
now removed.

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
the same way, keep it and the contract stays as it is. **Still open as of
2026-08-23** — Windows already applies the rewrite (`OutputParsers.cs`,
`SectionDetailView.xaml.cs`), but with the mac's generic rationale copied into
the comment rather than a recorded Edge test. Low-risk to leave as-is; still
worth doing the hand test and recording the result either way.

**2. Which progress markers you must match, and which are yours to write.**
`app-rules.json` → `markerOrigins` classifies twenty-eight. Nineteen come
from `scripts/*.py`, which both platforms run, and must match to the
character. Seven come from the launchers, which exist separately as `.sh` and
`.ps1` — those you write, and they already differ; since the native runtime
landed they do not even pair up, so `knownDivergence.macOnlyLauncherMarkers`
lists the mac phrasings a milestone here must never watch for. Two are
"elsewhere" (`Quartz v4` and `Done processing`, both Quartz's own output) and
want a human to look.

**This example is now WRONG and is kept only as a warning: an earlier version
of this section said "the mac watches for 'Setting up this Mac' where
`setup.ps1` prints 'Setting up this PC'."** `setup.ps1` printed that once, but
stopped the day Windows moved to a fully native toolchain (`b356a1f`,
2026-08-19, "Native toolchain (no container)" in `setup.ps1`) — no WSL2, no
Docker, no one-time machine setup, no container to start at all. Nobody
updated `TaskMilestones.cs`'s launcher markers to match, and nothing caught
it for four days: `Setting up this PC`, `Building your website builder`,
`Ensuring container is running`, and `Starting container if needed` all sat
in the milestone lists matching text that could never appear again, so the
first two-to-three stages of most progress bars silently could never be
reached — fixed 2026-08-23, see item 5 above and `GUI-IMPROVEMENTS.md` row
352. **The lesson: "read your own `.ps1` files" is not a one-time
measurement, it is a claim that rots the moment those files are rewritten.**
`TaskMilestoneLauncherMarkerTests` (`ParsingTests.cs`) now reads the actual
`.ps1` files rather than trusting a milestone list frozen in C#, specifically
so the next launcher rewrite fails a test instead of silently stalling a
teacher's progress bar again.

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
- **Write it to the template.** `MAC-HANDOFF.md` opens with "How to write an
  issue for the mac" — title and source, what it fixed and WHY (including what
  was rejected), numbers with the hardware they came from, the file and test
  names to look at, and whether the mac must match it or merely know. Something
  it must DO is a GitHub issue labelled `mac`; something it need only KNOW goes
  in that file's "For awareness" section. **A proposed contract case is an
  issue**, so the red mac suite it causes reads as a request.
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
the 13-tool local surface and the 32-tool MCP one. (It said 23; corrected
2026-09-06 when the list was first run against this side. `plantoir-mcp.exe`
serves 37, and the twelve it has beyond the contract are named in
`AssistSurfaceContractTests` and in `MAC-HANDOFF.md`.) The mac's own test has
pinned that sum for longer than the prose said so; it is 22 + 10 MCP-only = 32 since all six of the tools sorted as the mac's landed on 2026-09-08. What the two
surfaces do and do not share is item 41 and "The two MCP surfaces are not the
same product" below.

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

### The two MCP surfaces are not the same product

Written 2026-09-06 after a mac audit asked whether the parity list was
COMPLETE rather than whether it was correct. The numbered item is 41; this is
the manual for it.

**The measurement.** `Plantoir.Mcp/PlantoirTools.cs` declares **37** distinct
`[McpServerTool(Name = "…")]` names. `AssistToolSurface.swift` served **25**
when this was measured (22 tools plus three MCP-only). The set difference was
exactly **12, all yours, none the mac's**, and not one of the twelve appeared
anywhere under `mac-app/QuartzTeachers` or in `contracts/` — there was no
half-built mac version of any of them:

`add_classes`, `back_up_course`, `explain_publishing`, `list_courses`,
`list_recent_changes`, `make_room_for_classes`, `plan_add_classes`,
`plan_make_room_for_classes`, `plan_sync_page_dates`, `read_timetable`,
`roll_over_section`, `sync_page_dates`.

**Seven of those twelve are the mac's now**, and the surface is **32** (22 plus
ten MCP-only). All six tools this sorting judged the mac should have were built
on 2026-09-08 — `list_courses`, the `add_classes` pair, the
`make_room_for_classes` pair, `explain_publishing` and `back_up_course`
(`GUI-IMPROVEMENTS.md` rows 452–456, and item 46 below). So the set difference
is **5**, and the sentence above about none of them existing on the mac
describes the day it was measured rather than today. What is left is what the
sorting said to leave: `read_timetable` and `list_recent_changes`, which are
Windows-shaped by design; `sync_page_dates`, which needs a teacher's problem
first; and `plan_sync_page_dates` and `roll_over_section`, whose writes are
covered by decisions recorded elsewhere.

**Why neither suite noticed — and how it is now caught.** Not a subset check
— an earlier write-up said that and was wrong. `Assert.Equal` on `HashSet`s is
set equality in both directions, and it is a good test; it simply pins a
**different class**. It compares the contract against
`AssistAgent.ForTheLocalModel` and `.DeploysToStudents`, which is the in-app
assistant, while the 37 live in `PlantoirTools`. Its `mcpOnly` third compares
the contract against three names typed inline in the test file. Twelve
additions went through that gap without a single red test.

**Windows closed it, on the same day and from the other direction.**
`AssistSurfaceContractTests` (branch `issue/29-windows-contract-case-lists`,
merged after the audit's branch was cut) reads `PlantoirTools` by
**reflection** and pins the twelve extras BY NAME, failing both when an
unrecorded tool appears and when a listed one is adopted into the contract and
not deleted. It reads `toolSchemas` for both surfaces and checks arguments and
types, not just names. The audit said "nothing on either platform enumerates
`PlantoirTools`' names" and "no Windows test reads `toolSchemas` at all"; both
were true where it stood and false by the time it merged.

**What the mac was going to propose, and why it is WITHDRAWN.** An AUTHORED
`assist-cases.json` key — `mcpToolNames` — that Windows asserted its 37
against and the mac its 25 plus a "not served here, and why" list. It is not
needed: reflection on the Windows side gets the complete list from the
compiler, with no new contract key and no second home for it.

**REJECTED even before that: a MAC test that regexes the names straight out of
`PlantoirTools.cs`.** It is feasible — `AssistContractTests` already locates
the repository root from `#filePath` — and it was the first design. An
attribute reformatted across two lines makes the regex find FEWER names, and
fewer names all of which are accounted for reports **success**. A drift
detector whose failure mode is a false green is worse than none, because it
will be believed. It also couples a gate to source rather than to data. Both
problems vanish when the enumeration happens on the side that owns the code,
which is the general lesson: **enumerate a platform's surface on that
platform, and cross the gap with the RESULT.**

**The sorting is still not in any contract, and that is deliberate.** The "and
why" half of it is an unapproved product decision, and committing it would
make that decision into the acceptance list both suites run. Windows' test
carries the twelve names with no verdict attached, which is exactly the right
amount to pin before Russell has chosen. The sorting is in `MAC-HANDOFF.md`
under "Windows' MCP server has drifted a dozen tools ahead of the mac's".

**What the sorting concluded, in one paragraph**, so this file is readable on
its own: six of the twelve are product the mac should have — `list_courses`
and `back_up_course` and `explain_publishing` as MCP-only tools that cost no
routing, `add_classes` and `make_room_for_classes` as WIDENINGS of something
that already ships rather than new features (`add_next_class` already calls
`PlaceholderClassPlanner.apply`, and a `duplicate` key on the same call
already reaches `ClassInsertionPlanner.plan(count: 1)` — so the ENGINES are
both wired up already). Note the limit: `duplicate` is not on
`add_next_class`' published schema at all, only on the hardcoded card phrasing
`AssistCardCommand.swift:85`, so no model and no MCP client can reach it — the
mac needs a schema argument, not just a bigger count. And `roll_over_section`
because of the defect in item 41's first open part. Two are
Windows-shaped and stay yours: `read_timetable`, because the mac puts
spreadsheet reading behind its schedule sheet on purpose and has no file-path
argument anywhere on its surface; and `list_recent_changes`, because both mac
clients already show or hold that history. `sync_page_dates` needs a teacher's
problem first — the mac has no engine for it AND nothing on the mac reports
the date drift it fixes, because the mac has no equivalent of your `DateAudit`.
The three `plan_` twins travel with their writes and are not separate
decisions.

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
- **`re_date_classes` is hidden from the model**, and this bullet was missing
  while the count beside it already said nine. The phrasings that reach it are
  matched in CODE (`AssistCardCommand.swift`), and re-dating a whole section
  rewrites the date on every page in it — far too large a change to reach
  through a router that is right four times in five. Like the others it still
  RUNS, and Claude Code still sees it.

Result: 22 tools down to **13** for the model — the seven `plan_` twins,
`remember_timetable` and `re_date_classes` are the nine taken off the list.
(An earlier draft of this note said 12; the cuts named above come to 13, and
the code and its tests say 13. It then said 20 down to 13 with six twins and
seven taken off, which was true when it was written and had gone stale by
2026-09-06 — the local list has stayed 13 throughout, but the surface it is
drawn from grew.) The thirteen are `list_pages`, `read_page`, `check_section`,
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

## WinUI scroll bars overlay content — always reserve a trailing gutter

Found 2026-08-22, testing the model-in-use guard written up in
`MAC-HANDOFF.md`'s done ledger (and `GUI-IMPROVEMENTS.md` row 421):
`AssistantSettingsDialog`'s
"On this PC" housekeeping rows put a Stop/Remove/Download button flush against
the `ScrollViewer`'s right edge, and the vertical scroll bar drew right over
top of it — reported directly: "the scroll bar goes over the buttons — that
seems a poor UI choice? […] scroll bars should never occlude content on a
lower layer."

**Why it happens.** WinUI's default `ScrollBar` visual (`MouseIndicator` mode)
is an OVERLAY — it takes no layout space of its own and floats over whatever
the `ScrollViewer`'s content places at its trailing edge. A `ScrollViewer`
with no padding gives the scroll bar nothing to float over except the
content itself, so anything docked to that edge — here, a button in the
right-hand column of a two-column `Grid` — sits directly underneath it.

**The fix, and the convention going forward**: give the `ScrollViewer` extra
padding on the trailing side specifically — `Padding = new Thickness(0, 0, 20, 0)`
in `AssistantSettingsDialog.cs`, 20px being enough to clear the thumb's hit
target with room to spare. Not a fix specific to Settings: **any `ScrollViewer`
whose content places an interactive control (a button, a toggle, a link)
flush against the trailing edge needs the same trailing gutter**, checked at
the point that content is designed, not discovered by a teacher clicking
through a scrolled-down dialog. `SectionDetailView.xaml.cs`'s own
`ScrollViewer` already does this by convention (`Padding="36,28,48,28"` —
more on the right than the left), which is what made this fixable by pattern-
matching rather than by inventing a number from nothing.

**Swept the rest of the app for the same shape and found nothing else
wrong**: `NewCourseDialog`'s form scroller and `CourseSettingsView`'s have no
buttons docked to their trailing edge (toggles and text fields, not a
two-column button row), and `AssistWindow`'s transcript scroller holds chat
bubbles, not edge-docked controls. The housekeeping rows were the only place
in the app with this exact shape today — but the rule is the general one
above, not "fix this one dialog."

**For the mac**: SwiftUI's `ScrollView` on macOS behaves differently — its
system scroll bar is also typically an overlay, but AppKit's own controls
already carry enough of their own trailing inset in most list/form contexts
that this specific defect has not been reported there. Worth a quick look if
a similar "button under the scroll bar" report ever comes in on that side,
but this is not a ported behaviour — it is a Windows-specific rendering fact
(the `MouseIndicator` overlay model) with no mac equivalent bug to fix in
lockstep.

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
- **A test that proves a date was FRESHENED must compare against a date in the
  PAST, and yours already does — keep it that way.** `ModelTests.cs:179` reads
  `Assert.DoesNotContain("2025-01-01", index)`, and the date being safely in the
  past is what makes it a real assertion. The mac's twin used a date that was
  "today" when it was written, and on **2026-09-08** the clock reached it: the
  correctly-freshened value became the very string the test was checking for
  absence of, so a passing behaviour failed its own test. `dev` was red that
  morning for every branch, on a test nobody had touched in three weeks. Fixed
  on the mac by moving the fixture to 2020-01-15. **Do not "modernise" your
  fixture dates to something recent** — the whole point of that literal is that
  the clock can never catch up with it.
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

### A stub launcher must answer every mode the app calls, and must not name a port (mac, 2026-08-23)

The mac's one end-to-end preview test drives the real app against a fake
`preview.sh` that serves a one-page site. It had been failing for days with
`OSError: [Errno 48] Address already in use`, and it leaked an orphan server
that held port 8081 overnight — a leftover once made a REAL preview fail, which
reads like a broken toolchain rather than like test litter. Three separate
faults, and the interesting part is that only the third was the actual cause.
Windows has the same shape of test to write (`preview.ps1` driven by the app),
so all three are worth having before you write it.

- **The stub never implemented `--stop`, and that was the real bug.** Ending a
  preview runs `preview.sh <course> <section> --stop` and the app WAITS for
  that to finish before the next preview starts (mac: `PreviewStopper`). The
  stub ignored its arguments, so `--stop` fell through to "start a server" —
  which never exits. The restart then waited forever on a stop that could not
  complete, and the second server's attempt to bind the port the first one
  still held produced the `Address already in use` line everybody was chasing.
  **The error message named the symptom and hid the cause.** A stub stands in
  for a launcher, so it owes every mode the app invokes; answering only the
  happy path buys a failure that looks like a port problem.
- **A hard-coded port is a test that asserts ownership of a shared machine.**
  The stub asked for 8081. Anything else holding it fails the run for reasons
  that look like a product bug — and on this Mac something did: an unrelated
  `ssh -L` tunnel of Russell's, listening on 8081 all along. The fix costs
  nothing, because the app already scrapes the port out of the launcher's own
  output (`Preview will be available at: http://localhost:<port>/`). The stub
  now binds port 0, lets the kernel choose, and announces what it got — bind
  BEFORE announcing, so there is no window in which the announced port is not
  yet taken. Two runs can now overlap, and a teacher's real preview can be up
  at the same time. **Windows: do not let a stub name 8081**; read the port
  back from the announcement the same way.
- **A sandboxed UI-test runner cannot spawn a process, and fails silently at
  it.** The mac's first attempt at cleanup put `pkill` in `tearDown` behind a
  `try?`. It never ran — XCUITest's runner has no permission to spawn a child
  at all — and the swallowed error made dead code look like working cleanup
  for days. Proved by having it write a marker file that never appeared. The
  reaper is now a raw `kill()` on a pid the stub records before `exec` (which
  preserves the id). Check whether your Windows UI-test host has the same
  restriction before trusting a `Process.Start`-based teardown, and prefer
  `Process.GetProcessById` + `Kill()` on a recorded id, which needs no spawn.
- **Do not oversell the teardown reaper — it does NOT cover an interrupted
  run**, which is the case that actually hurt. An adversarial review caught
  this claim being made here in its first draft. Teardown does not execute
  when a run is killed, and the mac's recorded pid is stranded in a
  per-run `cq4t-fixture-<UUID>` folder that is never handed out again, so no
  later run can find it. **The port change is what makes an interrupted run
  harmless**, because the orphan then holds a kernel-assigned port nobody is
  waiting for rather than the one a real preview needs. The reaper earns its
  place on a narrower case: a server that outlived the test BODY, because the
  test failed before it could stop the preview. If Windows wants genuine
  interrupted-run cleanup, it has to come from outside the run — a known
  fixed pid-file location, or a verify step — not from teardown.
- **Record the pid BEFORE anything slow.** The mac's stub first wrote its pid
  after two `sleep 1` calls, which left a two-second window where a test that
  finished quickly tore down, found no pid file, and leaked the orphan anyway
  — the same review found it. The shell's `$$` is the same value at the top of
  the script as at the bottom, and `exec` preserves it, so there is no reason
  to wait.
- **If the stub kills by pid in more than one place, name-check in ALL of
  them.** The mac's Swift reaper checked the process name and its own shell
  `--stop` path did not, which is the stated invariant broken in one of the
  two places that needed it. Note the two need different matching: the kernel
  reports the short name (`Python`) while `ps -o comm=` reports a full path,
  so one wants a prefix test and the other a substring test.
- **Never reap by process NAME alone.** A pid is reused once its owner is
  reaped, so "something answers to this number" does not justify a kill — that
  is how a test murders an unrelated program of the teacher's. The mac scopes
  the kill to a pid the stub itself wrote, and additionally checks the running
  process's name before signalling. That check has one trap worth stealing:
  Homebrew's `python3` runs through a `Python.app` framework stub, so the
  kernel reports `Python` with a capital P, while `/usr/bin/python3` reports
  `python3` — a case-SENSITIVE test passes on one machine and silently reaps
  nothing on the other. Compare lowercased.
- **What was rejected.** Cleaning up from outside the test run (a wrapper
  script, or a `verify.sh` step) was rejected: it fixes the litter but leaves
  the test itself failing on any busy machine, and it puts the cleanup
  somewhere nobody reads when the test breaks. Keeping a fixed port and simply
  killing whatever holds it first was rejected outright — on a developer's own
  machine that is someone else's process.

One more thing the mac learned here that is NOT about stubs. The app will not
show a preview until the section's built `index.html` has CHANGED, and it
waits up to 120 seconds for that (mac: `waitForPreviewServer` phase 2). A stub
that serves a site from anywhere other than the folder a real build writes into
never trips the check, so the preview arrives two minutes late and the test
times out first — which looks like the server never came up. The stub must
BUILD INTO the watched folder. Whatever Windows' equivalent staleness check
is, its stub owes it the same honesty.

One consequence to know rather than fix: the app still takes a lease from
8081–8084 and still passes `--port <n>`, and the stub now ignores that flag in
favour of what the kernel gives it. That is deliberate — the announcement line
is the contract, and a launcher that could not honour `--port` would still
work — but it does mean this test no longer proves anything about a launcher
HONOURING `--port`, and nothing else covers it on either platform. Do not read
the flag as dead; read it as untested.

## Documentation map

- [`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md) — write-ups
  for handoff items verified DONE in `windows-app/` as of 2026-08-22, moved out
  of this file for length. Read it for the reasoning behind something that has
  already shipped.
- [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — THE spec (179 entries as of
  2026-08-15). Its **Windows status** section is where coverage is tracked.
- [`documentation/`](documentation/README.md) — toolchain deep dives 01–11.
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

**✅ Verified 2026-08-23, on a real Windows machine, with the OS appearance
actually switched to match each capture** (the way `capture_windows.py`
itself does it — the full detour is in `WINDOWS-HANDOFF-COMPLETED.md`, under
the salvaged capture-dialog fixes: a first verification pass skipped that step, misread
the result as a product bug, and nearly shipped an unnecessary and broken
code change before the real cause was found). `dotnet build` (0 warnings, 0
errors) and `dotnet test Plantoir.Tests/Plantoir.Tests.csproj` (655/655)
both pass, and `--capture-marketing-shots` — run once with the real OS theme
set to Light and once set to Dark — confirms all three edits visually in
both: the New Course dialog shows populated suggestions, an uncut
Language/region row, and the real "New Course or Club" title, with its card
correctly matching the surrounding window's theme; the assistant window
shows the prompt shelf instead of a blank top third.


## Docker images used to leak forever on the mac — and why you inherit nothing (2026-08-23)

Recorded here because the finding sounds like it must apply to both sides, and
it does not. On the mac, the builder image is tagged
`teaching-quartz:src-<hash of the build recipe>`, so every recipe change mints
a new tag and orphans the previous one. Nothing in the repository had ever
removed one: 139 images and 50 GB on this dev machine, ~115 of them
`teaching-quartz` tags. Containers were never the problem — each launcher
already removes its own container by name before recreating it, and the name
is a hash of the working folder, so it is one container per folder replaced in
place.

The mac fix is `prune_superseded_images()` in `setup.sh`, `preview.sh` and
`deploy.sh`: after a build SUCCEEDS, remove every `teaching-quartz:src-*` tag
except the one just built, skipping any a container still references. It keeps
exactly one tag; the "keep the previous one for a cheap downgrade" idea was
rejected because an older Plantoir carries its own bundled recipe and rebuilds
its tag regardless. `docker builder prune` was rejected outright: it is global
with no per-project filter, and this machine's Docker is shared with other
projects.

Three guards on it, each of which an adversarial review found MISSING in the
first version — worth having in writing, because all three look like
over-caution until you see the case:

- **Do nothing unless the tag just built is one of ours.** `--image` lets a
  caller point the image at anything, and "remove everything except the tag I
  was given" then means "remove every real tag on the machine, including every
  other working folder's current one".
- **Do nothing to an image younger than about a day.** The container check is
  a point-in-time read, and a folder that is mid-recreate — container removed,
  replacement not yet started — references nothing for a second or two. A
  build finishing in another folder inside that window would delete the image
  it is about to run, and the teacher would see a registry-pull failure for an
  image that exists on no registry. The same guard stops two folders on
  different recipes from deleting each other's image on every switch.
- **Ask Docker for the age, never compute it.** `docker image inspect
  '{{.Created}}'` returns LOCAL time with an offset, not the UTC `Z` it
  resembles, so comparing it against a UTC cutoff is silently wrong by the
  machine's offset. `{{.CreatedSince}}` from `docker images` is Docker's own
  human age string and has no timezone in it at all.

One correction to the paragraph above, for honesty: **containers are cleaned
up per working folder, but nothing cleans up a DELETED working folder's
container.** That orphan now permanently pins its image against this cleanup —
the one image that can never be reclaimed is the one nobody will ever use
again. Small (an orphan per deleted folder, and a teacher deletes none), noted
so the write-up is not read as "container hygiene is solved".

**Windows has nothing to port.** You dropped Docker on 2026-08-19 for the
native runtime — no image, no tag, no container, nothing to accumulate. (An
earlier `TODO-TODAY.md` note on the mac claimed "their launchers have the same
gap"; that was written without checking the `.ps1` files and is wrong.) Do not
add a cleanup for images that do not exist.

**The question worth asking on that side is the analogous one, not the same
one:** when a teacher installs a new Plantoir, is a superseded
`Vendor/runtime/` — or an old model download under `%LOCALAPPDATA%` — left
behind anywhere it can accumulate across a school year? That is the shape of
the failure the mac hit: a disk filling with something the teacher has never
heard of and cannot connect to this app. Nobody here can see a Windows
machine to answer it, so it is a question rather than a finding.

## Which folders count for marks: absent is not empty (2026-08-23)

The Curriculum Coverage map shows an expectation as ASSESSED — the ring on a
cell, and Ontario's ask that every overall expectation be evaluated at least
once — when a page addressing it lives in a folder that counts for marks. That
used to be hardcoded in `build_site.py` as *any folder whose name contains
"task"*, and a teacher who called theirs "Tests", or renamed "Tasks", silently
lost every assessed mark on the map with nothing said.

It is now `graded_folders` in `course_config.json`, matched by EXACT
folder-segment name at any depth (so `Tasks/Unit 1/Quiz.md` still counts, and a
page is never assessed because of what it is CALLED).

### The one mistake that matters on your side

**`GradedFolders` must distinguish ABSENT from EMPTY.** A plain
`List<string>` that defaults to empty when the key is missing would tell the
build "this teacher has no graded folders", and every course made before this
key existed would lose every assessed mark on its map — silently, because a map
with no rings still renders and still looks finished.

- ABSENT means the teacher has never been asked. The build applies the
  historical substring rule, and the course keeps exactly the marks it had.
- EMPTY (`[]`) means they were asked and cleared it. That is a real answer and
  is honoured.

The mac models it as `[String]?` and REMOVES the key when set to nil
(`CourseConfiguration.swift`). Whatever you use, make the round trip preserve
"no key at all" — and check your serialiser, because both apps write this file
wholesale from an in-memory copy.

### Do not seed existing courses

The obvious migration — write `["Tasks"]` into every course — is wrong, and the
repository proves it rather than the reasoning alone. All 38 payloads use
"Tasks", but the mathematics skeleton family ships **"Thinking Tasks"**: the
substring rule counted it, an exact pool of `["Tasks"]` does not. Seeding would
have quietly stripped that course's assessed marks.

Nothing is written back from a BUILD either. Be precise about why, because the
first version of this paragraph overstated it: both apps DO preserve keys they
do not recognise, so a build's write is not dropped in general. The real risk is
narrower and quite sufficient — an app holding a copy of the file it loaded
BEFORE the build wrote the key overwrites it at the next save, and a teacher
with Settings open while a preview runs is ordinary, not a corner case.

**One thing you will notice immediately: `FileFormats_CourseConfigKeys_MatchesContract`
is RED on your side, deliberately.** `contracts/file-formats.json` now documents
`graded_folders` and `CourseConfiguration.cs` does not read it yet. That is the
contract working as designed (CLAUDE.md rule 4) — a request, not damage. It goes
green when you add the property, and the absent-vs-empty note above is the whole
of what it has to get right.

### What the Settings control does, and why

The mac's is a checklist of the course's folders, under a "Marks" heading. When
the course has never been asked, it shows the folders the build CURRENTLY counts
already ticked, so a teacher sees what is actually happening rather than a blank
list. Nothing is written until they change something — and the moment they do,
the answer is explicit and the historical rule stops applying to that course.

### Content declares its own pool

All 38 payload manifests and all 50 skeleton families now carry
`graded_folders`, and both linters refuse a manifest without one or one naming a
folder the course does not have. `setup_course.py` writes it at creation from
the manifest — shared Python, so you inherit that unchanged.

Declared rather than inferred deliberately: inference is a substring while the
build matches exactly, and those two agree for 88 of the 89 courses here and
disagree for the one that would have been broken by it.

### Where the rules live

`contracts/shared-rules.json` → `gradedFolders` (9 cases, run by
`scripts/test_graded_folders.py` in the image) and `contracts/file-formats.json`
for the key itself.

## Folder problems: the checks, and the four places they have to surface (2026-08-23)

Certain folder and file names carry behaviour — the curriculum folder, the folder
holding class pages, `Media`, a section's `index.md` — and nothing stopped a
teacher deleting or renaming one in Obsidian. The features then failed SILENTLY,
the Curriculum Coverage map worst of all: it still rendered, still looked
healthy, and was wrong.

**The checks are shared Python and you inherit them unchanged.**
`scripts/site_health.py` runs inside `build_site.py`, after the content merge and
before Quartz builds. You run the same file, so there is nothing to reimplement.
What you owe is the front end.

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

### The sentence is not yours to write

Each finding is printed twice: once as a human sentence, and once as
`PLANTOIR_HEALTH: {json}` carrying `name`, `sentence`, `detail`, `fixable`,
`course`, `section`. **Display the `sentence` and `detail` the line carries.**
Do not compose your own from the `name` — the whole reason the wording travels in
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
payload means "this kind of thing is repairable"; what has to be true before you
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

  Three things that fell out of widening the offer, all of which apply to you:

  - **The publish sentence must not assert a past publish.** It is shown after a
    FAILED deploy too, and for a section publishing for the first time nothing
    has ever gone out. Say what publishing WILL do, not what it did.
  - **Guard the preview against every publisher, not just your own button.** On
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

One mac-specific mechanic that may or may not apply to you: a view presents one
alert at a time, so the outcome is shown from a state change AFTER the first
dialog has gone rather than raised inside its button action — asking for a second
while the first is dismissing loses one of them, and the one lost is the report
the teacher just asked for.

`FolderProblemRepaired` is a separate trail event from `FolderProblemFound`, on
purpose: one records that something is wrong, the other that somebody acted on
it, and a trail that could not tell them apart leaves "did they ever fix it?"
unanswerable. Both are in `contracts/shared-rules.json` → `activityTrail`, and
the repair rules themselves are in `siteHealth.repair`.

### A section with no index.md cannot be PUBLISHED — ✅ FIXED 2026-09-01, in shared Python, so you inherit it

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
the teacher gets **Put them back** → **Preview Again**; check that your own
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

**What you owe.** The Python is shared, so (almost) nothing. The exception is
`FailureExplainer.cs`, which gains `MissingFrontPageExplanation` — already
written on this side — and it must be asked **BEFORE** `MissingBuildExplanation`.
A publish puts both lines in one transcript, and "hasn't been built yet" is the
wrong thing to say to somebody who just watched it build. That ordering is a
contract case (`app-rules.json` → `failureExplanations`, the case whose
`output` carries both lines), so chaining it the other way round fails your
suite rather than shipping quietly.

**One thing to check rather than copy.** `_clear_stale_host_site` calls
`shutil.rmtree` on the host's `public/` — which under `PLANTOIR_BUILD_ROOT` is
outside the working folder, so outside OneDrive, which is the point of that
variable. If a scanner or an open handle makes the removal fail, the build says
so and carries on rather than dying; but the stale-publish risk returns for
that run. Worth one real test on a machine with OneDrive running, and tell the
mac what you find.

The `sectionIndexMissing` health check understated the same thing — "the site
will open on whatever page happens to come first" is true of a PREVIEW, and for
publishing there is no site at all. Its detail in `shared-rules.json` →
`siteHealth.checks` now names both outcomes, so a teacher can tell whether they
may carry on for now or must fix it before they publish.

### Renaming a course folder from inside the app — mac shipped 2026-09-01, Windows still to build

The `TODO.md` item deferred on 2026-08-23 while planning the special-folders
work, built on the mac once Russell chose the full scope. **You do not have it
yet**, and the contract carries most of what you need.

**Item 13 said "sentences, refusal rules and the list of keys … are all in
`shared-rules.json`". That was wrong** — four teacher-facing sentences from
this work live only in the mac's Swift, and they are listed under "Sentences
the contract does not carry" below. Corrected 2026-09-01 after adversarial
review; `GUI-IMPROVEMENTS.md` row 388.

**What it does.** A pencil on each folder row in Course Settings opens a sheet
that renames the folder ON DISK — in every section that has one — rewrites the
links that name it, and carries across every `course_config.json` key that
mentioned it. The keys are listed in the contract rather than here, at
`shared-rules.json` → `specialNames.renameFolder.carriesAcross`, and the mac
has a test that FAILS if a key is added to that list and not to the code. Copy
that test; it is the one that catches the failure this feature exists to
prevent (a config naming a folder that is not there).

**Two foot-guns closed in the same change**, and both are yours to mirror:
adding a name now CREATES the folder — it used to write a config entry pointing
at nothing — and removing one now says the folder and everything in it stays on
the teacher's machine, which nobody could tell before. Sentences:
`specialNames.addCreatesTheFolder` and `specialNames.removeLeavesTheFolderOnDisk`.

**Three decisions, with the reasoning, because none is obvious from the code.**

1. **It commits to disk immediately, not at Save.** Your Settings holds edits in
   memory and reverts them on Cancel, exactly as the mac's does. A folder that
   has really moved cannot be un-moved by a Cancel, so a rename that waited for
   Save would let Cancel appear to undo something it cannot. The mac writes the
   rename to a FRESH read of `course_config.json` (`CourseConfiguration.recordOnDisk`)
   so the teacher's other unsaved edits stay unsaved. That type is a mac type;
   the RULE is what to copy.
2. **~~The class folder must keep the word "class" in its new name.~~
   REVERSED the same day — do NOT build this refusal.** It shipped for a few
   hours because `ClassFolder` FOUND that folder by looking for the word.
   Russell's point: that is Plantoir's vocabulary imposed on a teacher's, and
   somebody whose units are Threads and whose classes are Days calls the folder
   "All Days". The lookup was what was at fault. `class_folder` is now a
   recorded key — the thing this entry called "the proper fix, deliberately NOT
   done" — and the rename MATERIALISES it. See "What a course calls its class
   folder" below; the sentence
   `specialNames.renameFolder.problems.classFolderMustSayClass` no longer
   exists.
3. **Nothing moves until every destination has been checked.** A per-section
   rename is several moves, and one that got half way through four sections
   would leave a course nobody could reason about.

**The trap that is yours alone.** Point 3 matters more on Windows than it does
here, because `Directory.Move` refuses a folder with an open handle and both
OneDrive and Obsidian hold them. Check every destination up front, and if a move
still fails, say WHICH section it failed in — the mac's message names the count
moved and the section that stopped it, and a bare exception would leave a
teacher with a course renamed in two sections out of four and no idea which.

**The trail.** Two new events, `folder renamed` and `folder created`, are in
`activityTrail.mustRecord`; the test that pins your `ActivityTrail` against that
list will fail until you add them. What they carry is in the contract — folder
NAMES, never anything from inside the folder.

**One thing the mac learned that changes how risky this looks.** The `TODO`
entry deferred this feature because it feared a rename would strand every
wikilink pointing into the folder, and that is wrong: Obsidian resolves
`[[Quiz 1]]` by searching the vault, so a bare page link survives the folder
moving. Only QUALIFIED links break — `[[Tasks/Quiz 1]]`, a full vault path, and
Obsidian's Markdown link style with its percent-encoded spaces. That is why this
shipped without the undo the deferral assumed it needed, and why you can build
it without one too. `FolderPathRewriter` is about 200 lines; its tests say
exactly which forms must change and which must not, and the "must not" half is
the important one — a rewriter that matched substrings would rename folders the
teacher never touched.

### What a course calls a unit — mac shipped 2026-09-01, and your suite goes RED first

The `TODO.md` item deferred on 2026-08-23. Russell chose the scope on
2026-09-01: **new courses plus configurable parsing, NOT renaming a course
already in use.** Read the "red suite" paragraph before you read anything else
here, because you will meet it before you meet the feature.

**Your suite will fail, and that is the mechanism working.** Three cases were
added to `contracts/class-planning.json` → `pageNaming`, each carrying a new
`term` field. A case WITHOUT that field means the DEFAULT word, "Unit" — so
read `term` with a default rather than treating its absence as a new shape, or
every existing case breaks. The case that matters most is the one where a
Module course must NOT read "Unit 2, Day 3" as a class page.

**What the feature is.** `unit_word` in `course_config.json` (documented in
`file-formats.json`), ABSENT meaning "Unit", so every course in the field is
untouched. A ready-made course holds **84–87** class pages (42 for the two
half-credit courses), not the ~3,000 an earlier draft of this section said —
that is the total across all 38 payloads. Corrections: `GUI-IMPROVEMENTS.md`
rows 388 and 389. The wizard asks "What do you call a unit?" of EVERY course,
ready-made ones included, and the payload is written in that word as it is
poured rather than renamed afterwards.

**Two of the three halves are shared Python and arrive free.**
`scripts/class_pages.py` is the rule — the default, the regexes, and the
rewrite — and `setup_course.py` applies it to the payload. You run both.

**What you owe:** a C# mirror of `ClassPageTerm` and of `UnitDay`'s `term`, a
field in your wizard, and the wizard writing `unit_word` into the config it
creates. Plus the assistant, in BOTH directions — and the input half is the one
that was got wrong here first: the mac's output sentences now say "Module 4 was
published", and `AssistPublishPlanner.unitNamed` now reads the course's word so
that "publish Module 4" is understood at all. Reading only the literal "unit"
meant the whole feature was missing for that course, silently, and it shipped
that way for a few hours. The assistant's unit sentences are hardcoded on both
sides and are not in `assist-wording.json`; they are listed below with the
others.

**Why the parsing half mattered more than the naming half, and why the cheap
option was rejected.** "New courses only, with the parsing left hardcoded" was
on the table and is wrong, for a reason worth carrying: `_is_class_page`
answering "no" does not FAIL. `_pages_the_course_teaches` returns nothing and
the curriculum map falls back to counting every published page — so a Module
course would have got a map that looked healthy and was wrong. That is the same
silent-success failure the whole special-names family exists to end.

**Four decisions, with the reasoning.**

1. **"Day" stays fixed.** A teacher who says "Thread" almost certainly still
   says "Day 3", and a second configurable word would double the migration for
   something nobody asked for.
2. **The word is escaped before it becomes a regex.** It comes from a teacher's
   own configuration; one containing "(" would otherwise match something else
   entirely, or fail to compile in the middle of a build. `Regex.Escape` is
   your equivalent.
3. **A number or a comma in the word is refused by the WIZARD**, which will not
   create the course until it is fixed. The command-line setup does something
   weaker on purpose — it says the name will not work and falls back to "Unit"
   rather than re-asking — because it is a single-pass script with no way back
   to a question. Either way the pages are never written under a name nothing
   can read back: built successfully, and silently outside every feature that
   works on class pages. **The sentences for both are Swift and Python
   respectively and are NOT in the contract** — see "Sentences the contract
   does not carry" below.
4. **The payload rewrite matches "Unit" only when a NUMBER follows.** That is
   what separates a unit reference from the ordinary English word, and it is
   run ONLY over content Plantoir itself ships, on the way into a brand-new
   course. Never let it near a teacher's own writing, where "Unit 3 of the
   textbook" would be a false positive nobody could undo. It deliberately
   catches the ~574 payload files that say "by the end of Unit 3" in prose,
   which would otherwise leave a Module course talking about Units.

**One design detail to copy rather than reinvent:** the word travels ON the
parsed value (`UnitDay.term`) and on the page summary, not looked up per call.
A page read out of a Module course is then written back as a Module page
without every planner needing the course handed to it as well — and the two
halves of a rename cannot disagree about which word they are in.

**What is deliberately NOT built, on either side:** renaming an existing
course's word. It means rewriting every class page's name, its frontmatter
title and every wikilink pointing at it, across every section and shared
folder, and a half-finished pass leaves a broken site with no way back. It
needs its own design pass and its own undo, and it stays in `TODO.md`. Do not
add it to your side alone.

### What a course calls its class folder — mac shipped 2026-09-01

Russell's ask, in his words: *"So we could have 'Thread' instead of 'Unit' and
'Day' instead of 'Class'?"* Yes — and the answer is a recorded key, not a
looser guess.

**`class_folder` in `course_config.json`**, documented in `file-formats.json`.
The recorded name wins when it is set and still one of the per-section folders;
otherwise the OLD GUESS applies unchanged — the first folder whose name
contains "class", else the first folder, else the literal "All Classes". Keep
the guess. Every course made before this key existed depends on it, and this is
additive by design.

**The part that is easy to get wrong: a rename MATERIALISES the key.** Carrying
an existing key across is not enough. A course made from scratch has NO
`class_folder` and `curriculum_folder: null`, so both folders are found by
guessing at their names. Rename `Curriculum` to `Expectations` without WRITING
the key and the guess stops finding it: the map is built from nothing, and
nobody is told — the coverage health check cannot fire, because from its point
of view the folder was never there. Pinned as
`specialNames.renameFolder.materialisesOnRename`, and the same rule covers
`class_folder` and `curriculum_folder` together.

**Six new naming cases and two membership cases** in `class-planning.json` →
`classFolder`, each carrying an optional `classFolder` field. **A case without
that field is a course that never recorded one**, so read it with a default
rather than treating its absence as a new shape — the same trap as `pageNaming`'s
`term`. Two of the cases are worth reading before you implement: a STALE key
(naming a folder no longer in the list) must lose to the guess, or the
next-class button writes into a folder that is not there; and a key differing
only in CASE from the list entry must return the LIST's spelling, because
everything downstream builds file paths out of the answer and a case-sensitive
volume would not find the key's.

**Membership widens, never shrinks.** The recorded folder is counted AND every
class-mentioning folder still is. Dropping the latter would shrink what a
course is seen to teach, which is the direction that produces the wrong map; a
course that had "Class Resources" counting yesterday must not lose it by
recording a class folder today.

**The removal block follows the recorded folder too**, so renaming
"All Classes" no longer leaves a course's class folder removable. The literal
"All Classes" is still blocked as well, for courses that never recorded one.

### Sentences the contract does not carry — write your own, knowingly

`contracts/` holds every sentence it can, and the handoff sections above say so
about the ones it does. These are the exceptions as of 2026-09-01, found by
adversarial review after an earlier draft of item 13 told you "sentences …
are all in `shared-rules.json`", which was not true. Each is teacher-facing,
each lives only in the mac's Swift, and each is one you will have to word
yourself — so word it deliberately rather than discovering the gap:

- **`ClassPageTerm.problem(with:)`** — the two wizard refusals for a unit word
  containing a digit or a comma.
- **`SpecialFolderRenamer.rename`'s half-failure sentence** — "Plantoir renamed
  N of M copies of 'X' and then could not rename the one in section3: …". The
  SHAPE is what matters and is worth copying: the count moved, and the section
  that stopped it. A bare exception here leaves a teacher with a course renamed
  in two sections out of four and no idea which.
- **`CourseSettingsView.renameFolder`'s bookkeeping-failure sentence** — the
  folder moved but the configuration could not be written. Do not report this
  as "the rename failed": it did not, and saying so sends the teacher looking
  for a folder under its old name.
- **The wizard's unit-word caption** — "Class pages will be named '… 1, Day 1'".
- **The assistant's unit sentences**, which item 13 wrongly said were "listed
  below with the others" until this line was added: "{word} N was published",
  "{word} N has already been published", "{word} N is already hidden", "{word} N
  was only partly published", and "I can't find any class pages in {word} N of
  …". They are hardcoded in `AssistToolRunner` and are in NO contract — not
  even `assist-wording.json`, which carries the rest of the assistant's words.
  That is a pre-existing gap this work inherited rather than made, and it is
  named here so you do not go looking for them.

**Three things the contract DOES carry that you must not copy verbatim.**
`specialNames.renameFolder.explanation`,
`specialNames.renameFolder.doneNothingWasThere` and
`specialNames.removeLeavesTheFolderOnDisk.message` all say "on your Mac".
Substitute "on this PC", the same way you already do for `app-rules.json`'s
"this Mac" — `contracts/README.md` documents that substitution. Your contract
test must compare on the substituted form or it will fail on a difference that
is correct.

### `course_config.json` has two writers, and they can erase each other

Fixed on the mac 2026-09-05; **half of it is shared Python you inherit and half
is yours.**

`preflight_update_course_config` reads the configuration, spends a while
scanning the course's folders, and writes what it computed. The APP writes the
same file inside that window — a folder rename does, and it writes at ONCE
rather than at Save, because the folder has really moved and a Cancel could not
undo it. Whoever wrote second won, and said nothing. The state that leaves is
the dead end in the next section: folders moved, configuration naming the old
name.

- **The Python half you get for free.** Preflight now re-reads the file
  immediately before writing and, if it changed, redoes the whole discovery
  against the new contents — bounded at three tries, then it carries on with
  what is there rather than spinning. Redoing is safe because discovery is a
  pure function of (what is on disk, what the config says). It is not add-only
  — an `excluded_items` name is dropped from the copy lists (row 377) — but
  that is a function of the same two inputs, so the argument is unaffected.
  Corrected 2026-09-07; it said "and is add-only" until then.
- **The other writer is yours.** Whatever writes `course_config.json` from the
  Windows app must do the same read-compare-write, or the race is only half
  closed on your side. The mac's is `CourseConfiguration.recordOnDisk`. One
  deliberate asymmetry to copy: preflight backs off, the APP ends by writing
  anyway after three tries — a folder that has MOVED with a configuration that
  does not say so is the worse of the two states, so the app finishes by
  recording the truth rather than by giving up on it.

`scripts/test_config_write_race.py` forces the race with a scan that mutates the
file mid-flight; it runs on your side too if you run the Python suites.

### A rename interrupted after the folders moved was a dead end

**Entirely yours to port** — this exists wherever a rename moves folders before
writing the configuration, which yours will.

The state: the folders are under the new name, the configuration still says the
old one. The next build DISCOVERS the moved folder and appends it, so the list
holds BOTH names — and retrying the rename is then refused as a clash. If the
folder was the class folder it is unremovable as well, so there is no way out
of Settings at all; the teacher has to hand-edit `course_config.json`.

**The rule to copy is: RECORD the rename before moving.** The first version of
this on the mac decided from the disk alone — old folder gone, new one present
— and that was wrong in a way worth understanding, because it looks right. It
is also the state of a configuration entry whose folder was never created (or
was deleted in Obsidian) being renamed onto a genuine SECOND folder. Bypassing
there hands the real folder the phantom entry's attributes, `hidden` among
them, and takes its pages off the next publish with nobody told. The two cases
are indistinguishable on disk, so the disk cannot be the evidence.

So: write a small record before anything moves, delete it once the
configuration has been written, and relax the clash check only when BOTH the
record and the disk agree. The mac keeps it at
`courses/.internal/renames/<CODE>.json` — the `.internal` convention you
already share — and deliberately NOT as a `course_config.json` key, because the
failure being handled is that the configuration write did not happen. Carry the
TARGET in the record, not just a flag, so a teacher who opens the sheet and
types something else gets the ordinary refusal back; filling the field in with
it also makes finishing an interrupted rename one keypress.

Two more details that are not optional:

- **No section may still hold the old folder.** A per-section rename moves
  every section's copy, so a mixture means something other than an interrupted
  rename, and the ordinary refusal must stand.
- **De-duplicate the list when you finish one.** The starting state holds both
  names by definition, so a naive rename leaves the new name in twice — which
  on the mac renders two rows with one identity, and which no later rename can
  undo.

**One more thing your own config writer must not do**, learned the same day:
when it loses the compare-and-swap race enough times to give up and write
anyway, it must recompute from the FRESHEST bytes. The mac's first version fell
through and wrote the computation derived from the read it had just proved
stale, clobbering the other writer's keys — the exact failure the loop exists
to stop.

### Publishing while a preview is running — the race, and the harness that found it

Two defects on 2026-09-05, both in the publish path, both invisible to every
test that does not publish and then LOOK at what came out.

**The race, which is the one that matters.** Killing the preview LAUNCHER does
not stop the preview. On the mac the Python and the node server both live
inside the container, and `_start_public_sync_watcher` keeps mirroring the
SERVE build to the host every second — so a build for publishing lands and the
preview overwrites it within a second, and what gets published is the preview,
live-reload client and all. `kill_existing_quartz` was only ever called from
the SERVE branch, so `--build-only` never stopped anything.

`build_site.py`'s `--build-only` now stops the preview serving THIS SECTION
before building, matched by the section's own build directory.
**That is shared Python and you inherit it.**

**It was written by PORT first, and that was wrong — do not go back to it.**
`kill_existing_quartz(port)` looked like the obvious tool and is the right one
for the SERVE path, where the port is known and leased. A build-only run is
never given a port: `preview.sh` defaults it to 8081 and the app's deploy
passes no `--port` at all. So the first version killed whatever was serving on
8081 — the first section to have previewed in that working folder, which is
usually a DIFFERENT section from the one being published. Measured 2026-09-05
by doing it: previewing section 1 and publishing section 2 printed "Killed
existing process on port 8081" and section 1 stopped answering. A scheduled
overnight deploy would have done the same to any preview left running.

What works instead is the section's BUILD DIRECTORY, which is on the serve
process's command line because the launcher runs the Quartz CLI by absolute
path. It identifies exactly one preview and cannot collide with another. One
detail that is easy to miss: match on the directory plus a trailing separator,
or `section1` also matches `section10`.

Two things to check on your side rather than assume:

- **Your preview is not in a container**, so an orphaned server is a plain
  Windows process. Check that killing your launcher actually stops the node
  server — on the mac it demonstrably does not, and that is exactly the kind of
  difference that is assumed rather than measured.
- **You have already written most of the algorithm — do not write it again.**
  `preview.ps1`'s `--stop` block finds this section's processes by COMMAND
  LINE (this paragraph said WORKING DIRECTORY until 2026-09-05, and that was
  simply wrong — `Win32_Process` exposes no working directory), walks their
  descendants, and its own comment says "not port, … parity: preview.sh". The
  descendant walk is the half you had and the mac did not. What is missing on
  your side is not the algorithm, it is **calling it from the build-only path
  before the build**.

  (The mac could not simply call `preview.sh --stop`, because `build_site.py`
  runs INSIDE the container and `--stop` is a host script — which is why a
  third copy of this rule existed. **Resolved 2026-09-05**: the rule now lives
  once, in `contracts/shared-rules.json` → `stopPreview` and
  `scripts/stop_preview.py`, and item 20 in the outstanding list says what
  this side owes.)

- **What is and is not exposed on your side.** The Windows APP already stops a
  running preview before deploying (`SectionDetailView.xaml.cs`), exactly as
  the mac's does — so the app is safe on both platforms and always was. The
  hole is the COMMAND LINE, on both.

  **And on Windows the command line is still open, because the shared fix
  cannot reach it** (corrected 2026-09-05; this said "in your CONTAINER
  runtime `/proc` exists, so the mac's new code works there unchanged", which
  described a container path Windows no longer has). `preview.ps1` refuses to
  run at all without the bundled native runtime, `read_proc_snapshot()` in `stop_preview.py`
  reads `/proc`, and native Windows has none — so it returns an empty list
  and `stop_preview_serving()` stops nothing. The watcher that
  causes the race, though, runs everywhere: `_start_public_sync_watcher` is
  started unconditionally in the SERVE branch, so a Windows preview mirrors
  over a Windows publish exactly as a mac one does. **The fix is to call
  `preview.ps1`'s own matcher from the build-only path before the build** —
  see item 20 in the outstanding list, which carries the three details worth
  copying rather than re-deciding.

- **The wait is bounded at 30 seconds** (150 × 0.2 s), not the 15 that
  `GUI-IMPROVEMENTS.md` row 392 says — that row predates the change and the log
  is append-only, so this is the current number.

**The other one was a partial fix of mine, and is worth knowing as a shape.**
The first version of the preview guard in `deploy.sh` waited for `index.html`
to lose the live-reload client. Serve mode bakes that client into EVERY page
and the mirror is replaced file by file, so a clean front page can sit in front
of two hundred stale preview pages. Publishing that MIXTURE is worse than
publishing the preview wholesale, because the front page looks fine and nobody
looks further. Wait on the whole tree; `deploy.ps1` already does.

### One rule for stopping a section's preview

New on 2026-09-05, and the closing of a `TODO.md` item. Read
`contracts/shared-rules.json` → `stopPreview` first; this explains why it is
shaped the way it is, and what was rejected.

**What was wrong.** One question — *which processes belong to this section's
preview?* — was answered in three places: `preview.sh --stop` (a `/proc` sweep
by working directory, run inside the container), `preview.ps1 --stop`
(`Win32_Process` by command line, plus a descendant walk, run natively), and
`build_site.py` (command line plus `--serve`, inside the container, written
because both of the others are HOST scripts and it is not). The reason for the
third is sound and has not gone away; the problem was never that it existed,
it was that nothing held the three to the same answer.

**The finding that changed the design, and the reason a straight refactor
would have been wrong.** They were not three copies of one rule. They were
three PARTIAL rules, and each saw something the others could not:

- A **working directory** catches a child launched by a RELATIVE path, which
  carries no directory to match on. `npm install` runs exactly that way, and
  so do the esbuild workers under it.
- A **command line** catches the Python driver. `build_site.py` never calls
  `os.chdir` — it passes `cwd=` to its CHILDREN — so the driver sits in the
  container's `/teaching` for the whole build. Through every in-process phase
  (copying the scaffold, copying content, social cards, the rsync mirror) it
  is the only process there is to find, and the mac's sweep found nothing and
  printed "Stopped 0 process(es)".
- Only **`preview.ps1`** walked descendants — yours, and it was right.

So picking any one of the three as "the" implementation would have shipped
that one's blind spot to both platforms. The rule is a **disjunction of three
evidences, plus a walk down the process tree**, and it stops strictly more
than any of the three did alone.

**Why the cases are process SNAPSHOTS rather than single processes.** The
first design had each case describe one process — name, command line, working
directory — with an expected verdict. That cannot be run on both platforms,
for two independent reasons. `Win32_Process` exposes no working directory at
all, so every cwd case would be unanswerable on your side. And the descendant
walk is not a property of any single process: it is a rule over parent links
across the whole list. A case is therefore a small process TABLE with `pid`,
`ppid`, `name`, `commandLine` and `cwd`, and the expected answer is the list
of pids to stop. A platform that cannot see one kind of evidence must still
reach the same verdict — through the walk — and that is exactly the property
worth testing rather than assuming.

**Two modes, because there are genuinely two questions.** `everything` is the
launcher's `--stop`: reclaim the server, the build, the driver, and everything
under them. `servingOnly` is `build_site.py --build-only`: remove ONLY the
preview server that would otherwise overwrite the publish build a second later
through its own host mirror. A build must never be stopped in that mode,
because the build being protected is itself a build of this section — and the
process asking is the driver the rule would otherwise recognise.

**The version-independence trap, which is the one to carry if you ever adopt
`--match-stdin`.** `preview.sh` pipes the recipe's copy of the rule into the
container over stdin rather than running the copy baked into the image. Stop
mode must never build anything, so it runs against whatever container is
ALREADY there — right after an upgrade, one built from the previous image,
with no such file. Naming a baked path would make `docker exec` fail with a
message nobody sees (both callers send the launcher's output to the null
device and neither checks its exit code) while the build it was asked to stop
carried on burning CPU. This is exactly once per teacher per upgrade, and only
when something was running, which is the only time the mode matters at all.
`verify.sh` section 6d proves it by deleting the file from a running container
and stopping a preview anyway.

**Rejected: making `preview.ps1` call the shared Python.** It would leave one
implementation and two ports, which is better, and the `--match-stdin` entry
point exists so you can. It was not done from here because `--stop` must never
start anything and whether Python is reliably resolvable on that path at that
moment is a question only your machine can answer. Yours to measure; say what
you find.

**Rejected: extracting `preview.ps1`'s matcher into a new `.ps1` file beside
the launchers.** A test could then dot-source it without running the script.
But a new file there has to be added to `ToolchainMirror.Launchers` and
`RecipeRootFiles`, the Dockerfile's `COPY … /opt/export/` and its `unix2dos`
line, `project.yml`, and the mac's own refresh lists — five hand-maintained
lists, which is the precise failure `contracts/toolchain.json` →
`recipeFolders` exists to record. The functions are defined inside
`preview.ps1`'s stop block instead. If you want them dot-sourceable, that is a
real cost to weigh, not a free tidy-up.

**A case a platform may skip, and why that is not a loophole.** One case —
"a process is caught by its working directory alone" — can be decided ONLY
with a working directory, which `Win32_Process` does not expose. Rather than
delete it (it pins the evidence that catches `npm install`) or let it fail on
Windows, cases carry `needsEvidence`, and a runner without that evidence skips
it naming what was missing. The loophole this could obviously become is closed
by a test rather than by discipline: the mac's suite BLINDS every case — takes
the working directories away — and asserts that a marked case's verdict
changes and an unmarked case's does not. It caught a case wearing the marker
that did not need it on the first run, which is exactly the drift the marker
would otherwise invite.

**Three holes the second review found, all in the rule itself, all the same
family as the bug being fixed.** A blank or root build directory was evidence
for EVERY process, because an empty string is a prefix of everything — a
caller that lost track of which section it was asking about would have swept
the whole container rather than failed. A target that is a SUFFIX of a longer
absolute path matched as well, so `/x/tmp/quartz-builds/ADA1O/section1` was
evidence for `/tmp/quartz-builds/ADA1O/section1`. Both are the section1 /
section10 mistake pointed in different directions: one about where a path
ends, one about where it begins, one about whether it is a path at all. The
lesson worth keeping is that fixing a boundary bug in one direction is not
finishing it — check every edge of the match, and check that the thing being
matched is a real value.

**One harness lesson, learned twice in one afternoon.** A process that scans
other processes for a marker string finds ITSELF — the marker is on its own
command line. In `verify.sh` 6d this first inflated a count so that every
check in the section failed while the code under test was correct, and then,
in the cleanup, made the script SIGKILL itself part-way through: it printed
nothing, exited quietly, and left behind the very processes it was written to
collect. The second one was found only by checking the container afterwards
rather than trusting a green run. Exclude your own process id, and treat
"scanning for a string I am myself carrying" as a shape worth recognising —
the same trap that `stop_preview.py` already guards against for the real rule.

**What was measured, not decided.** The two `preview.ps1` prefix bugs were
found by reading, and both are real: `$lower.Contains($sectionNeedle)` with a
needle ending `\section1` matches `\section10`, and
`$lower.Contains('--section=1')` matches `--section=10`. Each was reproduced
as a contract case, and each case was checked by putting the fault back into
the shared Python and watching that case — and only that case — fail. The same
was done for the descendant walk. A green suite proves nothing about a case
that cannot fail.

### `verify-deploy.sh` — the publishing harness, and why it is not in the gate

New on 2026-09-05, at the repository root. It publishes to a folder, to Netlify
and to Cloudflare, and runs all three primary+secondary pairings, then **fetches
every published site back and reads it** — the launcher's own output only
proves the launcher is happy with itself. 42 checks.

**It is deliberately NOT part of `verify.sh`.** The gate must be runnable at any
moment, on any machine, without credentials and without touching anything
outside the repository. This needs a Netlify token, a Cloudflare token and an
account ID, it needs the network, and it CREATES REAL SITES. Build the Windows
equivalent the same way — opt-in, run when the publishing path changes — rather
than folding it into whatever you gate on.

One thing it does NOT cover, stated so nobody assumes otherwise:
`additional_deploy_targets` is not handled by `deploy.sh` at all — the APP loops
and calls the launcher once per destination. The harness exercises the pairings
by running that same sequence, which tests the launcher half; that the app
produces exactly those argument lists is pinned separately by
`app-rules.json` → `deployArguments`, which your suite already runs. Between the
two the pairing is covered; neither half covers it alone.

### The scheduled task NEVER refuses

Russell's call, and the reasoning travels: *"a slightly inaccurate curriculum map
is a paper cut, an unpublished site update a teacher was counting on is a broken
nose."* Pinned as `siteHealth.scheduledDeployPublishesAnyway` and asserted by a
mac test so it cannot be quietly softened later.

So: publish, then stash what was found for the next time somebody is there. You
already have the shape — `ScheduledDeployCompletion.cs` stashes a completion
sentinel exactly this way. Two properties the mac's version has that yours should
too: the record is CONSUMED when read, so a problem is reported once rather than
every time the app opens; and a CLEAN run clears it, so a problem the teacher has
put right stops being reported.

**That second property is harder than it looks, and this section claimed it
before it was true.** launchd opens the scheduled log with O_APPEND and nothing
rotates or truncates it, so reading the whole file re-finds LAST week's marker
lines every night: the sentinel is rewritten with stale findings forever, and the
"nothing wrong this time" branch becomes unreachable the moment a single problem
has ever been logged. A teacher who fixed the folder would have been told about
it every morning until somebody deleted the log.

The mac now records the log's SIZE before the run and reads only from that offset
afterwards. If your task runner captures output per run you may not have this
problem at all — but check rather than assume. And note how it got through: the
test that was supposed to cover it faked the append by rewriting the file, so it
passed against broken code.

One platform difference worth knowing: the mac reads the findings back out of the
scheduled run's LOG FILE rather than from a pipe, because `runScheduled`
deliberately does not capture the child's output — launchd points stdout at that
log and the process inherits it, and an unread pipe is what wedged your own
assistant server. If your task runner already captures output, use what you have;
the log-scrape is a workaround for a constraint you may not share.

### Deploys with several destinations

Take the findings from the FIRST leg only. Every destination publishes the same
built site, so a second leg repeats them.

### Trail event

`FolderProblemFound` is in `ActivityTrail.cs` and in
`contracts/shared-rules.json` → `activityTrail.mustRecord`. The line reads
`found a problem with this course's folders (curriculumCoverageFoundNothing)` —
a sentence a teacher would recognise, carrying the stable check NAME in brackets.
Both halves earn their place: rule 5 wants a line that reads as something that
happened, and the name is what somebody searching the trail months later can
match against the contract, since the product wording will have been reworded by
then.

**The mac suite fails a declared trail event that has no call site** — which is
what forced the front end to be written rather than promised. Worth checking
whether your suite does the same; if not, it is a cheap test to add.

## "Where do the class pages live?" had four answers — and yours was the worst (2026-08-23)

**Action required on your side: build and test. The C# below was written on the
mac, which has no dotnet, so it has compiled nowhere.**

A teacher whose class folder is not called "All Classes" — "Class Pages", say —
used to get a different answer from each of four places:

| Where | What it asked |
|---|---|
| mac `ClassPages.folderURL` | the course's CONFIGURED per-section folders, first containing "class" |
| mac `AssistSectionGraph.isClassPage` | the page's IMMEDIATE parent contains "class" |
| `build_site.py` | any segment of the ABSOLUTE path EQUALS "all classes" or "classes" |
| your `AssistWorkspace.Plan` | the whole ABSOLUTE directory string contains "class" |

Three of those are wrong in ways worth knowing:

- **The build's.** Exact strings, so "Class Pages" matched nothing. When no
  class pages are found, `_pages_the_course_teaches` returns `None` and the
  Curriculum Coverage map falls back from "pages the course teaches" to "every
  published page". The map still renders, still looks healthy, and is wrong —
  the failure this whole piece exists to close.
- **The build's, again — and this is a CORRECTION to what this section said
  first.** An earlier draft claimed the build had been counting pages by their
  file NAME, and named "How This Class Works.md" and ADA1O's "B3. Connections
  Beyond the Classroom.md" as pages it had miscounted. That was wrong. The old
  rule was `part.lower() in ("all classes", "classes")` — membership in a
  tuple, i.e. EQUALITY — so no page was ever counted for its name. The real
  defect in the same line was different and worse: `content_root.rglob` yields
  ABSOLUTE paths, so it walked every segment above the content root too. A
  teacher whose working folder was `~/Documents/All Classes` made every page in
  every course a lesson — the same bug as yours, on the other platform. The
  file-name exclusion is kept as defence in depth for a future change to
  substring matching, and is labelled as such rather than as a fix.
- **Yours.** `Path.GetDirectoryName(pagePath)` is the absolute directory, so a
  teacher whose working folder is `C:\Users\x\Classroom\` makes **every page
  in every course** a class page. Where somebody keeps their files is not a fact
  about their lessons. This is the one that needed fixing most and could not
  have been found from the mac.

**The one rule**, in `contracts/class-planning.json` → `classFolder`:

- *naming* (where a NEW page is written): the first configured per-section
  folder whose name CONTAINS "class" (case-insensitive), else the first entry,
  else the literal "All Classes". Substring is safe here — it is a short list
  the teacher chose.
- *membership* (which folders COUNT): EVERY configured per-section folder whose
  name contains "class", falling back to the single name naming chose. Added
  after review: naming and membership are the same question only when a course
  has one such folder, and a course configured
  `["Class Resources", "All Classes"]` would otherwise resolve to the first for
  both, match zero pages, and drop the coverage map back to "every published
  page" — reintroducing the exact silent failure the rule closes.
- *isClassPage*: not an `index.md`, and one FOLDER segment — never the file
  name — EQUALS that folder's name, case-insensitively, with the path taken
  RELATIVE to the content root.

The asymmetry is deliberate and is the part worth not "simplifying" later:
naming may use a substring because its input is curated; page matching may not,
because its input is arbitrary paths. A classics course's "Classical Studies"
folder must not be mistaken for where its lessons live.

**What changed on your side:**

- new `Plantoir.Core/Models/ClassFolderRule.cs` — `Name(...)` and
  `IsClassPage(relativePath, classFolder)`. It is called `ClassFolderRule`, not
  `ClassFolder`, because `AssistWorkspace` already has a private `ClassFolder`
  method that returns a PATH, and two things with one name returning different
  kinds of answer is how the next bug gets written;
- `AssistWorkspace.Plan` now calls
  `ClassFolderRule.IsClassPage(Relative(pagePath), ClassFolderRule.Names(...))`
  — note `Relative(...)`, which is the fix for the `Classroom` bug. **The rule
  is a pure segment matcher and cannot tell an absolute path from a relative
  one**, so `Relative(...)` is the whole protection: if you ever call
  `IsClassPage` from somewhere else, pass a relative path or you reintroduce
  the bug. The mac learned this the same way — its own `AssistSectionPage` had
  to gain a `pathWithinSection` because `relativePath` is the FULL ABSOLUTE
  PATH whenever `workspaceURL` is nil;
- `ClassFolderRule.Name`/`Names` skip null and empty entries: these lists come
  from JSON, including the contract's own case data, and unguarded LINQ threw
  where Swift and Python coerce;
- `AssistWorkspace.ClassFolder(course, section)` delegates its naming half;
- new `Plantoir.Tests/ClassFolderContractTests.cs`, deserialising the same 5 + 9
  cases the mac suite and `scripts/test_class_folder.py` run.

**Rejected:** unifying on "contains class" everywhere. It reads well and it
reclassifies real shipped pages — see the payload examples above. Segment
EQUALITY for pages, substring only for the configured list, is the distinction
that makes the rule safe.

## The scripts can now read the contract — and it travels differently on Windows (2026-08-23)

`contracts/` used to be readable only by the two test suites. It is now readable
from `scripts/*.py` as well, through `scripts/contracts.py`. This is the spine of
a larger piece (hardening the folder and file names that carry hidden meaning —
`Tasks`, the curriculum folder, `All Classes`, `Media`, `index.md`,
`Key Links.md`), and it matters to you because the rules being hardened live in
`build_site.py`, which is the thing that actually decides what ships. A rule that
lives there and nowhere a test can reach is a third implementation with no gate
on it — the drift the contract exists to prevent, arriving by the back door.

**Why it had to be baked into the image, and what that costs.** The container's
ONLY bind mount is `courses` (see `preview.sh`, `deploy.sh`). The working
folder's `.toolchain/` sits beside `courses/` and is NOT mounted; the app bundle
is on the host. So neither of the two obvious routes can be read from inside the
container, and the contract has to be `COPY`d in by the Dockerfile. The
consequence is deliberate: `contracts/` is not in `toolchain_hash`'s prune list,
so every contract edit mints a new `teaching-quartz:src-<hash>` tag and forces an
image rebuild and container recreate. That is development-time cost on the mac,
paid on every case added, and it was accepted because the alternative was a
shared rule the build cannot see.

**None of that applies to you, and that is the point of this section.** Windows
runs these scripts NATIVELY — no container, no image, no hash. The contract
reaches Python through `PLANTOIR_CONTRACTS_DIR`, exactly the way
`PLANTOIR_SUPPORT_DIR` already reaches `support/`. Five things carry it:

- `ToolchainMirror.RecipeFolders` gained `contracts`, so a working folder's
  `.toolchain/` gets it;
- `Plantoir.csproj` ships `Toolchain\contracts\`;
- `setup.ps1`, `preview.ps1` and `deploy.ps1` set `PLANTOIR_CONTRACTS_DIR`;
- `Vendor/fetch-runtime.ps1` sets it too — a SIXTH env-setting site the first
  pass missed, and the kind that is latent until it is not: it runs
  `setup_course.py` while provisioning the runtime, so the first time a script
  reads a required contract there, it throws `ContractMissing` naming
  `/opt/contracts` on a Windows host. That error names a container path on a
  machine that has no container, which is about as confusing as a message gets.

**If you add another place that runs a `scripts/*.py`, it needs the variable.**
There is no way to make this fail loudly at build time; it fails at run time, in
whatever feature happened to read a contract first.

**A trap that cost real time here, and travels to you unchanged.** The recipe's
folder list existed as FOUR hand-maintained copies: the mac's
`WorkspaceModel.refreshToolchain`, your `ToolchainMirror.RecipeFolders`, the
marketing screenshot harness (`website/shots/capture.py`), and the Dockerfile's
own `COPY` lines. They drifted the moment a fifth folder was added, and the one
that drifted was the harness — whose docstring said, in so many words, "keep them
in step".

The failure mode is worth understanding because it is not the one you would
guess. `capture.py` copies the *Dockerfile* too. So the demo workspace got a
Dockerfile containing `COPY contracts/ /opt/contracts/` with no `contracts/`
beside it. That workspace is not STALE, it is **unbuildable**: `docker buildx
build` fails on the missing `COPY`, and `preview.sh`'s friendly "this folder is
missing the toolchain's build recipe" message cannot fire, because
`resolve_build_context` only checks that the Dockerfile EXISTS — and it does.
A folder list that is merely incomplete produces a hard build failure with a
misleading diagnosis.

The fix, and the pattern worth copying: the list became DATA
(`contracts/toolchain.json` → `recipeFolders`), and `scripts/test_recipe_folders.py`
pins every carrier against it — including your `ToolchainMirror.cs` and
`Plantoir.csproj`, which it reads as TEXT. That is deliberate: one Python test
can pin a Swift list and a C# list, where a C#-only test could only ever check
its own half. The test was verified to actually fail when a copy drifts, which
is the check people skip. **If you add a recipe folder on your side, add it to
`recipeFolders` and let the test tell the mac.**

**Rejected:** leaving the list in code and adding a comment (that is exactly what
was there, and it is what failed); and having each platform's own suite check
only its own copy (two green suites, still drifted).


## A cloud-synced working folder: explain it, never refuse it (2026-09-05)

**The decision, and who made it.** Russell, 2026-09-05, on the question
`TODO.md` had carried since a reliability review found that renaming a
folder reads every page in the course — which on an iCloud-backed vault means
downloading every offloaded page, one blocking read at a time. The question
was whether Plantoir should refuse a working folder that a cloud service
keeps in sync. The answer is **no**: recognise it, say once and in plain
words what it costs, give the teacher the choice, and leave their notes
exactly where they put them. `GUI-IMPROVEMENTS.md` row 399 is the log entry;
`shared-rules.json` → `cloudSyncedFolders` is the specification; this
section is the reasoning.

**Why not refuse.** Three reasons, and each alone would have been enough:

- Teachers keep their vaults in iCloud or OneDrive *on purpose* — it is how
  the notes reach an iPad and a second machine. A refusal tells them to give
  up cross-device access to their own teaching material, and a hard block is
  the one answer they cannot opt out of.
- Detection is unreliable in both directions. A teacher can have a folder
  literally called "Dropbox" that is not one; a folder can be synced by a
  service neither app knows. A false refusal on a hard block is
  unrecoverable for them, whereas a synced folder Plantoir fails to notice
  still works — more slowly.
- **You already rejected refusal, by building something better.** When
  OneDrive locked build output mid-build, the Windows answer was
  `PLANTOIR_BUILD_ROOT` — move the churn out, leave the content in. That
  precedent settled the argument here: the same problem, met once, answered
  by relocating rather than refusing.

**The two moments, and why they are different things.** This was Russell's
own question — shown when a synced folder is suspected, when the working
folder is created, or both? — and the answer is both, as two forms:

- **A folder the teacher just CHOSE, or an empty one about to be set up,
  stops at the folder picker.** This is the one moment the choice is free:
  nothing has been written into the folder yet. The picker shows the
  headline, the five-sentence explanation, and two buttons — "Use This
  Folder Anyway" and "Choose a Different Folder…". Setting up the empty
  folder IS going ahead (the note was beside the button; pressing it is the
  answer). **Neither button is the Return-key default**: a Return pressed
  out of habit must not decide this.
- **A folder the window RESTORED gets a quiet notice inside the window**,
  above the working-folder bar: headline, one-line summary, a way to open
  the full explanation in place, and "Got It". Never a dialog and never a
  sheet, because a folder can become synced *after* it was set up (moved
  into iCloud; Desktop & Documents turned on) and a folder that opens on
  every launch must not interrupt every launch. On the mac this is a strip
  above the path bar with a `.quaternary` background; build yours as an
  InfoBar or the nearest WinUI equivalent — the placement and the
  dismissability are the contract, the control is yours.
- **Going ahead is remembered PER FOLDER**, and neither form is shown for
  that folder again. A second synced folder gets its own note. The mac
  keeps the list in preferences under `acknowledgedSyncedFolders`; keep
  yours wherever you keep per-app preferences, keyed by the folder's path.
- **The check runs on EVERY adoption of a folder**, not only the first —
  folders move into cloud services after they are made, and the check costs
  nothing.

**Detection: markers, never names.** The mac reads three things, and all
three are in `detection.macMarkers`: `~/Library/Mobile Documents` (iCloud
Drive's real location), `~/Library/CloudStorage/<Service>-<Account>/` (where
macOS 12.3+ keeps every File Provider service — OneDrive, Google Drive,
Dropbox, Box — with the service named by the part of the folder name before
the first hyphen), and the item's own `isUbiquitousItem` flag, trusted ONLY
under `~/Desktop` and `~/Documents` — the two folders iCloud syncs in place.
**That flag is not iCloud-specific**: the adversarial review (row 401)
probed a real `~/Library/CloudStorage/Dropbox` and found it set there too,
so trusted anywhere else it would call a Dropbox folder "iCloud Drive".
Whatever Windows exposes for "this item is cloud-managed", assume the same
until proven otherwise. **Symlinks are resolved before any rule runs** —
Dropbox and OneDrive both leave a link at the old place (`~/Dropbox` →
`~/Library/CloudStorage/Dropbox`), and a path arriving through it matched
nothing while the folder behind it matched Dropbox; on Windows, resolve
junctions and reparse points the same way, since Known Folder Move leaves
exactly that indirection. The resolved path is also the acknowledgement's
key, so one folder is one key whichever spelling it arrives by. Your
markers are listed in `detection.windowsMarkers`: the OneDrive roots the
client publishes as `%OneDrive%`, `%OneDriveConsumer%` and
`%OneDriveCommercial%` (a Desktop moved by Known Folder Move physically lives
under one of them, so a prefix rule catches it), Dropbox's `info.json`
(`%APPDATA%\Dropbox\info.json`, `path` entries), and iCloud for Windows
(`%USERPROFILE%\iCloudDrive` by default). A service you cannot see is
allowed — see "why not refuse". **Run the eleven `detection.cases` against
your path function** with `{home}` as `%USERPROFILE%` and the mac's reserved
paths translated to yours; the cases that matter most are the negative ones:
a folder CALLED Dropbox on the Desktop, and the reserved root itself. When
the service is recognisably syncing but not one you name, the contract's
`unknownServiceName` ("your cloud service") is the honest word.

**The sentences, and the one that is not yours.** All in `wording`, word for
word, `{service}` filled in. They name EFFECTS a teacher can recognise —
"building can be slower", "renaming a folder can take a while" — and never
machinery: no "sync client", no "file provider", no "dataless", no "build
root". A mac test forbids those words; write the same test. The ORDER is
part of it (`explanationOrder`): reassurance first, because "kept in sync"
beside a warning reads as "your notes are at risk" and they are not; the
choice last, after the reasons. **`buildFilesAreCopied` applies on the mac
only** (`buildFilesAreCopiedAppliesOn`): it says the built site's thousands
of files are written inside the folder and copied to the cloud, which is
true on the mac today — `.merged_output` still lands in the working folder —
and false on Windows, where row 290 already builds into
`%LOCALAPPDATA%\Plantoir\builds\<id>`. Show the other four. When the mac
moves its output out too (a separate piece; the research is in `TODO.md`
under "Move the mac's build output OUT of a synced working folder", and it
is bigger on the mac because the build runs in a container that mounts only
`courses/`), that field will change and the contract diff is how you will
hear.

**The trail.** Two events, both in `activityTrail.mustRecord` and so already
failing your `ContractTests` until you add them: `synced folder noticed`
(the service and the redacted path — recorded because the effects of a
synced folder arrive weeks later as unrelated reports, and this line is what
connects them) and `synced folder accepted` (which of the two forms, and the
service — because "nobody warned me" is answered by this one, not the
first). The mac's lines read "noticed the working folder is kept in sync
with iCloud Drive — ~/…" and "chose to use the working folder anyway, kept
in sync with iCloud Drive"; say the same things in the same words.

**Rejected, so it is not proposed again:** refusing (above); detecting by
folder name (the case that would catch a real Dropbox folder is the case
that mislabels a teacher's folder called Dropbox); a dialog or sheet on
launch (interrupts every launch of a folder that cannot be un-synced from
inside the app); a single app-wide "don't show again" (a teacher with two
synced folders was told about one). Not measured: nothing here was timed.
The iCloud read-on-download slowness that started the question is real but
was observed, not clocked; if you time a rename on an offloaded OneDrive
folder, write the number here with the hardware.

**What driving it against a real iCloud Drive folder found** (row 400), in
the order you are likely to meet the same things:

- **The notice pushed the whole bottom band of the window off screen**, at
  every window height. The mechanism is SwiftUI's (a text pinned to its
  vertical size answers a minimum-size probe with a word per line — 1,548
  points, measured, whether 700 points or no height at all is proposed;
  the modifier ignores the height either way), but the SHAPE is WinUI's too: a
  wrapping `TextBlock` in a horizontal `StackPanel` gets unbounded width and
  never wraps, or bounded width and grows tall. Measure your InfoBar's
  height with the real sentences at a narrow width before shipping it, and
  measure with a width PROPOSED — the mac's first test asked for the ideal
  size with no width and passed the faulty layout.
- **The path bar cut off the folder's own name.** An iCloud path always runs
  through `~/Library/Mobile Documents/com~apple~CloudDocs/…`, so the last
  crumb — the only one that differs between a teacher's folders — was the
  one lost. Now a contract rule, `workingFolderPathBar.tooLongForTheSpace`:
  a path too long for the space shows its END. Your bar needs the same.
- **The folder must be NAMED before it is explained.** The picker showed the
  five sentences and then the path bar; a teacher reads "this folder" and
  looks for which folder. Path bar first, in both the empty-folder and the
  existing-folder states.
- **Enter still set up the empty folder while the note was showing**, which
  the contract's own `whenShown.chosen` forbids. The set-up button loses its
  default-action status while a decision is pending; make sure yours does.
- **A folder the picker will not take anyway** — neither a working folder
  nor empty — is not asked about. The rule is in the contract's `whenShown`;
  the teacher is about to choose again, and the guidance saying what to
  choose is the message.

**What the adversarial review then found** (row 401), beyond the detection
points folded in above:

- **Finishing a set-up must acknowledge the folder that was SET UP**, not
  whichever folder is current when the copy ends. The copy runs off the
  main thread and the Open Working Folder command stays enabled meanwhile;
  a second synced folder chosen during it has its own decision pending, and
  the first folder's completion must not answer it. Guard on the path.
- **"Synced folder noticed" is recorded by a window only.** The assistant
  and the MCP server adopt folders on models nothing shows; a "noticed" from
  those says the teacher was told something they were not, and on the mac it
  produced six lines for one folder in ten minutes. Your `plantoir-mcp.exe`
  adopts folders too — same rule.
- **One folder, every window.** Got It in one window clears the same
  folder's notice in any other window showing it. Rarer on Windows, where
  one `MainWindow` shows one folder; verify and say so if it cannot happen.
- **Re-choosing the open folder is a restore**, not a new choice
  (`whenShown.reChoosingTheOpenFolder`), or the courses vanish behind the
  picker for a folder the teacher did not change.
- **The acknowledgement list is keyed by resolved path and never pruned.** A
  renamed or moved folder is a new key and is asked again — on purpose,
  since it may have moved INTO a synced location. A deleted folder's key
  stays, harmlessly.
- **Three labels are now in the contract** — `chooseDifferentFolderButton`,
  `showDetailsButton`, `hideDetailsButton` — so nothing on the picker or the
  notice is left for you to word.

## Built websites live outside the working folder (2026-09-05)

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

The consequence is worth knowing on your side too: the LINK syncs, so a teacher
with two Macs receives one naming a home folder that does not exist there. A
link pointing anywhere other than this machine's own builds folder is replaced
before anything builds.

### The finding nobody had listed, and the one that is yours in spirit

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
checking; worth a `MAC-HANDOFF.md` line if it turns out you are already safe,
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
- **If anything other than your app can move build output, it owes the trail
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
one rebuild, which is cheap and visible. **The general rule, which is yours as
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
on your side before you assume you are clear: **what does an OLD
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

The rule that makes it safe is worth stating plainly, because your side will
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
Python, so it does not run on your side, but the STATES it lists are the ones
worth checking on any platform that moves build output.

## The course-code picker is a hand-built combo box — and you probably should NOT build one (2026-08-23)

`GUI-IMPROVEMENTS.md` rows 333–338 describe the new-course wizard's course-code
field being rebuilt over two days: a searchable field with a rich two-line
flyout, a chevron that toggles it, arrow-key navigation, and geometry matched
to a real `NSComboBox` to the pixel. **Read this section before you copy any of
it**, because the central decision does not transfer and following the rows
alone would have you re-derive a lot of behaviour you can get for free.

Nothing here is a contract case. Every part of it is either visual, measured,
or built out of platform focus-and-key mechanics — the categories rule 2 sends
to a handoff rather than to `contracts/`.

### Why the mac hand-built it, and why that reason is probably yours to ignore

A real `NSComboBox` was tried first and reverted twice in one session
(2026-08-22). The blocking reason was **its popup can only display plain
strings**. The flyout has to show, per row, the course code, its formal name on
a second line, and an "Example content" badge for codes that ship with a
ready-made course — and `NSComboBox` simply cannot draw that. A secondary
reason: correcting its auto-widened popup frame proved unreliable two different
ways (deferred a runloop turn it flashed the wrong frame first; made
synchronous it missed the "click the arrow with an empty field" case, because
the popup's child window does not exist yet when `comboBoxWillPopUp` fires).

**WinUI does not have that limitation.** An editable `ComboBox`, or an
`AutoSuggestBox`, takes an `ItemTemplate` and will happily render a two-line
row with a badge in it. If that holds up when you try it — check before
committing, this is written by somebody who cannot run WinUI — then use the
real control and you inherit, at no cost, everything the rows below describe
the mac writing by hand: the dropdown affordance and its toggle, up/down
navigation, Return to commit, Escape to dismiss, scroll-into-view for the
highlighted row, the focus ring, and correct metrics. Do not hand-build a
control to solve a problem you do not have.

The rest of this section is what to know **if** the real control turns out not
to work for you.

### Metrics: measure the platform's control, do not match it by eye

The mac's numbers came from rendering a real `NSComboBox` offscreen at 2x in
both appearances and reading the PNG back pixel by pixel. The harness and the
full findings table are in `research/native-control-metrics/`. The numbers
themselves are Apple's and are useless to you; the **method** is the part worth
copying, and three findings generalise:

- **A framework's "native-style" control is not the native control's
  metrics.** SwiftUI's `.textFieldStyle(.roundedBorder)` renders **26pt** tall
  where the `NSTextField` it stands in for reports **24**. Check what your
  `TextBox` actually measures against the WinUI control it imitates before
  assuming they agree.
- **Constraining the frame does not change what a control draws.**
  `.frame(height: 24)` left the field measuring 26 and merely overflowing its
  box. Getting 24 meant drawing the bezel ourselves.
- **A cell's text rect is not where glyphs land.** `titleRect` reported x=4,
  actual glyphs started at ~5.7pt; the text system adds its own padding inside.
  Measure rendered glyphs, not the API's rectangle, when matching text
  position.

There is also a **corner-radius trap that cost real time**: the radius was
already correct and only *read* wrong because the field was 30pt tall instead of
24. The same radius on a taller box looks squarer. Check the box before you
change the radius.

### If you do hand-build one: four things learned the hard way

1. **One piece of state for "is the flyout showing."** The toggle, the drawing,
   and the animation must all read the same value. Three separate conditions
   let the toggle disagree with what is on screen, and the arrow then needs
   pressing twice.
2. **Key handlers must DECLINE, not swallow.** Up/down/Return are handled only
   when there is a flyout to act on; otherwise they fall through. Swallow them
   unconditionally and you break the arrow keys for someone editing text and the
   default button for someone who typed a code and just wants to press Enter.
3. **Store the highlighted row by its CODE, not its index.** The list re-filters
   on every keystroke, so an index quietly comes to mean a different course.
   Clamp movement at the ends rather than wrapping — a wrap turns one key too
   many into a jump from the bottom of a 40-row list back to the top, which
   reads as the list having moved somewhere else entirely. And make Down with
   the flyout CLOSED reopen it on the first row, or Escape strands a keyboard
   user at the mouse.
4. **Re-check every badge and secondary colour that can land on a highlighted
   row.** The "Example content" badge is an accent-coloured capsule; on an
   accent-filled highlighted row it vanished completely the moment keyboard
   highlighting existed. It now inverts to a white capsule with accent text.
   A passing test did not catch this — looking at a screenshot did.

### The chrome is shared, and that was a trade

All three fields in the wizard's Basics section (course code, course name,
timetable section numbers) now wear one `WizardFieldChrome` modifier, so they
cannot drift apart. The cost, stated rather than buried: two fields that wore a
real AppKit bezel now wear an imitation of one, because that was the only way to
get them to the native 24pt. The imitation is measured against the real control
rather than eyeballed. The alternative — wrapping a real `NSTextField` in an
`NSViewRepresentable` for all three — buys genuine native chrome at the price of
hand-managing first responder and binding updates, and remains open if the
imitation ever starts costing more than it saves.

**If WinUI's own field is already the right height, none of this applies to you
— keep the real control.** The mac ended up here because it had already been
forced off the native control for the flyout's sake; do not inherit that
position by accident.

## Spelling a folder's new name inside a link (2026-09-06)

Renaming a course folder repoints the qualified links that name it, and the
question this section answers is a narrow one: how is the new name SPELLED
once it is inside a link? Getting it wrong does not fail — it writes a broken
link into a teacher's own page and says nothing.

**The defect, which was on both platforms.** `FolderPathRewriter` decided
whether to percent-encode the new name from whether the OLD path segment was
encoded. That is the obvious rule and it is wrong, because a Markdown link's
destination ends at the first SPACE. Renaming `Tasks` to `All Tasks` turned

    [q](Tasks/Quiz%201.md)   into   [q](All Tasks/Quiz%201.md)

which neither Obsidian nor Quartz can follow. The `%20` there belongs to the
FILE name; the folder segment `Tasks` carries no `%` at all, which is what made
it easy to miss by eye. Windows found this by adversarial review on 2026-09-06,
fixed it, and reported it to the mac as a shared defect rather than a port
error — which was the right call, and is why the mac took the rule unchanged:

> In a MARKDOWN link, escape when the NEW name needs it, whatever the old
> segment looked like. In a WIKILINK, keep the plain spelling.

The wikilink half is not an oversight. `[[All Tasks/Quiz 1]]` is exactly how
Obsidian writes a wikilink whose folder has a space in it, so escaping there
would be the mirror-image mistake. Both sides also kept the OLD rule as a
second reason to escape rather than replacing it: a segment that ARRIVED
percent-encoded goes back percent-encoded, in either style, so a link a teacher
already had keeps the shape it had.

### The escaping SET is measured, and `Uri.EscapeDataString` is the wrong tool

This is the part that is new to Windows, and the mac's first plan was to copy
`Uri.EscapeDataString` precisely so the two apps could not drift. An
adversarial review checked that against the real Quartz instead of reasoning
about it, and it would have REGRESSED the mac. The chain, read out of
`quartz/util/path.ts` in the running image on 2026-09-06:

1. `transformInternalLink` calls JavaScript's `decodeURI` on the link.
2. `decodeURI` **deliberately leaves the reserved set `; / ? : @ & = + $ , #`
   still encoded** — that is what distinguishes it from `decodeURIComponent`.
3. `sluggify`, in the same file, then maps `&` to `-and-` and `%` to
   `-percent` when it builds the address.

So a folder called “Tasks & Quizzes”:

| written as | after `decodeURI` | slug | matches the folder? |
|---|---|---|---|
| `Tasks%20&%20Quizzes` | `Tasks & Quizzes` | `Tasks--and--Quizzes` | ✅ |
| `Tasks%20%26%20Quizzes` | `Tasks %26 Quizzes` | `Tasks--percent26-Quizzes` | ❌ 404 |

`Uri.EscapeDataString` keeps only `A-Za-z0-9-._~`, so it produces the second
row. And the failure is the worst kind: Obsidian decodes `%26` perfectly well,
so the teacher's vault looks healthy and only students see the break. “Tests &
Quizzes” and “Q&A” are ordinary folder names, so this is not a corner case.

Measured in the container, not inferred:

    decodeURI("Tasks%20%26%20Quizzes/Quiz.md")  ->  "Tasks %26 Quizzes/Quiz.md"
    decodeURI("Tasks%20&%20Quizzes/Quiz.md")    ->  "Tasks & Quizzes/Quiz.md"
    decodeURI("Work%28new%29/Quiz.md")          ->  "Work(new)/Quiz.md"
    decodeURI("Top%2010%25/Quiz.md")            ->  "Top 10%/Quiz.md"
    decodeURI("Caf%C3%A9%20Notes/Quiz.md")      ->  "Café Notes/Quiz.md"
    decodeURI("C%2B%2B/Quiz.md")                ->  unchanged

The set that survives untouched is therefore what JavaScript's `encodeURI`
leaves alone, minus three — `(` and `)` close a destination, `#` starts a
heading — and minus `/` and `:`, which the rename sheet refuses anyway. It is written into the contract as a literal string rather than
described, so either side can test a character against it:

    contracts/shared-rules.json
      -> specialNames.renameFolder.linkRewriting.escapingSet.leaveUnescaped
      =  ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789;,@&=+$-_.!~*'?

(This line lost its trailing `?` when the correction two paragraphs down
was written, and said the wrong thing for a day. Copy the string from the
contract, never from here — or better, assert against it: Windows'
`TheEscapingSetIsTheContractsCharacterForCharacter` pins the code's copy
against the contract's, which is the only check that catches a character
quietly added to or dropped from either.)

Everything else — the space, `%`, the quotes and brackets, and every non-ASCII
letter — is percent-encoded as UTF-8 **once escaping runs at all**, and
`decodeURI` gives all of it back. That last clause matters more than it looks:
nothing is encoded unless the name needs it, so `Café` goes into a link as
`Café` and only `Café Notes` becomes `Caf%C3%A9%20Notes`. Reading
`leaveUnescaped` as "always encode everything else" is the way the two apps
would write different text for the same rename, so there is a case pinning it.

### Two things this section said first and got wrong

Both were caught by an adversarial review that measured the pipeline instead
of reasoning about `decodeURI` in isolation, and both are kept here because
the correction is the useful part.

- **A lone `%` does NOT need escaping, and `%` is not in the trigger set.**
  The argument for it was `decodeURI("10%/Quiz.md")` throwing. Quartz never
  sees a bare `%`: it parses with `remarkRehype`, and the Markdown parser
  normalises `%` to `%25` on the way to HTML long before the link transformer
  runs. Measured in the container — `[b](Top10%/Quiz.md)` arrives as
  `Top10%25/Quiz.md`, `[a](Top%2010%/Quiz.md)` as `Top%2010%25/Quiz.md`.
  `WouldBreakAMarkdownTarget` on your side is already right; do not add `%`.
- **`?` belongs in `leaveUnescaped`, and this section twice said otherwise.**
  It first claimed a folder named with `#` or `?` loses whichever spelling is
  used — true for `#`, false for `?`, because `sluggify` STRIPS a `?` from the
  real folder's name. It then claimed both apps "escape `?` anyway", which the
  mac's code did not do: `?` is not a trigger, so `Why?` always went in
  unescaped. What that left was a rule where the folder resolved when it was
  called `Why?` and not when it was called `Why Not?` — the escaped
  `Why%20Not%3F` slugs to `Why-Not-percent3F` and 404s, while the real folder
  and the unescaped link both slug to `Why-Not`. `?` is now in the set. It
  cannot arise on Windows, where a folder name may not contain one, but the
  encoder is a pure string transform so the case still runs there.

### What Windows owed — ✅ done 2026-09-07

Kept as it was written, because the reasoning is the point of the section and a
deleted obligation takes its reason with it. Landed on branch
`issue/31-rename-link-escaping`, commit `2bed7c83`: `Spelled` calls a
`PercentEncoded` driven by `leaveUnescaped` in BOTH branches, and
`FolderPathRewriterTests` deserialises every case. 1125 passed, 2 skipped, 0
failed (1031 before).

**A TWELFTH case went in with the fix**, and it is the part worth reading even
now the work is done. `Spelled` has two reasons to escape — the new name would
break a Markdown destination, or the OLD segment arrived percent-encoded — and
NONE of the original eleven reaches the second. Eight take the first (a space or
a bracket in the new name); the other three reach no encoder at all, because
`Assignments` and `Café` need no escaping and the wikilink case is not a
Markdown link. A `Uri.EscapeDataString` left behind in the second branch alone
would have passed all eleven. The new case
(`[q](All%20Tasks/Quiz.md)`, "All Tasks" → `Q&A`, expecting
`[q](Q&A/Quiz.md)`) is the only one that reaches it. It is named in
`MAC-HANDOFF.md`, and it should be green on the mac already.

**What was originally owed, and why:**

**Three** of the eleven cases failed on Windows, and they were a request
rather than damage:

- **“an ampersand is left as it stands”** — `Tasks` → `Tasks & Quizzes`,
  expecting `[q](Tasks%20&%20Quizzes/Quiz.md)`.
- **“a comma is left as it stands”** — `Tasks` → `Unit 1, Day 2`, expecting
  `[q](Unit%201,%20Day%202/Quiz.md)`. **This is the one that will actually
  happen.** `Unit%201%2C%20Day%202` slugs to `Unit-1-percent2C-Day-2` while
  the folder slugs to `Unit-1,-Day-2`, and “Unit 1, Day 2” is this project's
  own naming pattern.
- **“a question mark is left as it stands”** — unreachable on Windows, where a
  folder name may not contain `?`, but the encoder is a pure string transform
  so the case still runs.

All three were ONE change in
`windows-app/Plantoir.Core/Models/FolderPathRewriter.cs`: replace
`Uri.EscapeDataString` in `Spelled` with an encoder driven by `leaveUnescaped`
above — in BOTH of its branches, which is the half that reads as optional and
is not. It keeps only `A-Za-z0-9-._~`, so it over-encodes `&`, `,`, `+`, `'`,
`!` and `*` alike. **Not all eleven break, and this line said they did.** The
ones that 404 are the eight characters `decodeURI` leaves encoded and
`sluggify` then turns into `-percent…`: `; , @ & = + $ ?`. `?` is an ordinary
member of that set and not a special case — `Why%20Not%3F` slugs to
`Why-Not-percent3F` by the same mechanism as the rest. (What IS peculiar to `?`
is why the UNESCAPED spelling works: `sluggify` strips it from the real
folder's name too, so both sides land on `Why-Not`.) `%27`, `%21` and `%2A` decode back to `'`, `!` and
`*` and resolve fine, so over-encoding those three is noise rather than damage.
Corrected 2026-09-07 by an adversarial review of the fix; the encoder is
unchanged by the correction, because the eight that DO break include both of
the ones a teacher will actually type. Nothing else in the rule changes, and the
mac's version of it is `spelled(_:likeThe:in:)` in
`mac-app/QuartzTeachers/Models/FolderPathRewriter.swift`.

**And a second obligation that is easy to miss** — done in the same commit;
the file deserialises `linkRewriting.cases` now, keeps its five as named
anchors, and pins the code's copy of `leaveUnescaped` against the contract's
string directly. That last check is the one worth copying to the mac: a
behavioural walk over the set can only test the characters the CODE has, so a
character quietly ADDED to either app's constant is invisible to it.
`windows-app/Plantoir.Tests/FolderPathRewriterTests.cs` used to retype five
cases of its own rather than deserialising `linkRewriting.cases`, so **nothing
on the Windows side went red on its own** — the three failures above are invisible
there until the cases are wired in. `contracts/README.md`'s own rule is to
deserialise and never retype, and this file was one of the places that did not
— until 2026-09-07.

The per-cent case, “a per-cent sign is escaped” (`Top 10%` →
`[q](Top%2010%25/Quiz.md)`), **passes on Windows already** and is not work:
`Top 10%` triggers escaping on its SPACE, and `EscapeDataString` encodes the
`%` with everything else. It is in the contract to pin what encoding COVERS,
not what triggers it.

### What was rejected, so it is not proposed again

- **Copying `Uri.EscapeDataString` for parity's sake.** Parity with a rule
  that produces a 404 is not worth having; the measurement above is what
  settled it.
- **Escaping wikilinks the same way.** The mirror-image mistake — Obsidian
  writes `[[All Tasks/Quiz 1]]`, plain.
- **Widening the rename sheet's refusals to cover `#` and `?`.** Refusing
  more names is a product decision nobody has made. For `#` neither spelling
  resolves in Quartz anyway (`%23` survives `decodeURI` and slugs through
  `-percent`); for `?` see the correction above.
- **Angle-bracket destinations, `[q](<Tasks/Quiz 1.md>)`.** Neither app matches
  them — the segment reads as `<Tasks` — and neither app has ever matched them.
  Pre-existing on both sides and out of this piece's scope; noted here so it is
  not mistaken for a regression.


## A folder named `index.md`, and why both apps refuse rather than clear the way (2026-09-07)

The bug is yours — you found it porting `SiteHealthRepair` line by line, and
`MAC-HANDOFF.md`'s entry of 2026-09-06 is what this fixes. What follows is the
part that does not travel in a diff: what the mac chose, what it rejected, and
why the two are not interchangeable.

### The bug, stated once

`FileManager.fileExists(atPath:)` — and `File.Exists`, and every other bare
existence test — is answering a question about a NAME, not about a file. On the
mac it returns `true` for a directory. So this:

```swift
if FileManager.default.fileExists(atPath: index.path) { return .alreadyFine }
```

reported `.alreadyFine` for a section whose `index.md` was a FOLDER, and
`outcome(ofRepairing:)` sorts `.alreadyFine` into neither "restored" nor
"failed", so the dialog said **"That is already put right. Nothing needed
changing."** The section still had no front page: `build_site.py` produces no
root `index.html`, so there is no site to publish and the deploy refuses. The
one dialog written to end silence was the thing telling them it was dealt with.

`restoreMedia`, the function DIRECTLY above it, has used the `isDirectory:`
form since it was written, with a comment saying why. And the two were written
in the same sitting — `git log -S` puts both in commit `04dfd0cd`, 2026-08-23 —
so this is not a case of an old habit and a new one. The careful form and the
bare one were typed one function apart, on the same afternoon, by somebody who
had just explained in a comment why the careful one was needed. That is the
useful lesson in it: knowing the rule does not make the next call site obey it,
and a grep for `fileExists` / `File.Exists` with no `isDirectory:` is worth more
than remembering.

### What it does now, and the decision behind it

**Refuse, explain, and touch nothing.** Russell decided this before the work
started, and the alternative was live: move the folder aside and write a proper
front page in its place, so the teacher's next publish just works.

**That was rejected because the folder may hold their pages.** Neither app can
see inside it — this is a teacher's Obsidian vault, and a folder called
`index.md` is most often a sync conflict or a mis-drag, but it can perfectly
well be a folder somebody made on purpose with a term's work in it. A repair
that relocates a teacher's writing to make a warning go away is a worse outcome
than the warning, and it is the kind of thing that gets discovered in May.
Refusing costs one step by hand, in Finder or Explorer, and nothing else.

It also fits the rule the whole health feature is built on
(`siteHealth.checksTheFeatureNotTheFolder`): a fix must restore the FEATURE.
Moving a folder out of the way and writing an empty page satisfies the check
while possibly hiding the teacher's own pages, which is the same failure mode
as recreating an empty curriculum folder, one step further along.

### The sentence, and why it names the course

`contracts/shared-rules.json` → `siteHealth.repair.refusedWhenSomethingIsInTheWay`
carries it. On the mac it is `SiteHealthRepair.folderWhereTheFrontPageBelongs(course:section:)`.

It names the course as well as the section folder, and that was a review
finding rather than a first draft: the outcome dialog shows a headline and one
sentence and NOTHING else — not the course, not the section — so "in your
section1 folder" sends a teacher with two courses to a folder that exists twice.
This is the first teacher-facing sentence on either platform to name a
`section<N>` folder. It is safe to do: that is the on-disk name, it is what
Obsidian's file tree shows, and both apps already offer "Reveal in Finder" on
exactly that folder.

**And the generic explanation is REPLACED, not appended to.** That is
`SiteHealthRepair.couldNotExplanation` on the mac — the one that sends a teacher
to check whether a folder is locked or read-only. It is the right thing to say
about a read-only volume and the wrong thing to say here: permissions are not
what is wrong, and a teacher gets one prompt to act on. When BOTH kinds of failure happen at once — a file where
`Media` belongs and a folder where the front page belongs — both sentences are
said, generic first and specific last. Both orders were read aloud. The other
way round ends the paragraph on the generic explanation's opening clause —
"You can make it yourself in Obsidian" —
immediately after "…and Plantoir can put the front page back", so "it" lands on
the front page — the one thing that cannot be made until the folder in the way
has moved. There is a test on the order
(`testWhenBothKindsOfFailureHappenTheGenericExplanationComesFirst`), because a
comment claiming a paragraph reads well is worth nothing.

### The shape of the answer, which is what you have to copy

`Result` gained a fourth case:

```swift
case blockedByAFolderWhereTheFrontPageBelongs(section: Int)
```

Two things about it are deliberate.

It carries the **section number, not the sentence**. `Result` says how a repair
went — a fact — and `outcome(ofRepairing:in:occasion:)` chooses every word in
that file. Putting the prose in the Result would have split the wording across
two places, and the first adversarial review of the plan caught exactly that.

It is counted as a **failure**: the check's name goes into the failed list, so
"Could not put the front page back." still appears beside anything that did
come back, and `canRebuild` stays false, so the "Preview Again" button is not
offered. There is nothing to look at.

### The trail line

`ActivityTrail.Event.folderProblemNotRepaired` = `"folder problem not
repaired"`, written from the refusal branch with the course and section:

```
ICS3U/1 · found a folder called index.md where the front page belongs, and left it alone
```

Without it the trail shows the problem being FOUND and then nothing at all,
which reads exactly like a teacher who never pressed the button — and the
folder in the way is something they will very likely have moved or deleted by
the time they report anything, so it cannot be looked for afterwards.

**Named for the OUTCOME, not for its one cause, and this is the part worth
copying rather than re-deciding.** Only the directory refusal writes it today.
A repair that simply FAILED — a read-only volume, a permissions problem — still
records nothing, which is a real gap and is left open on purpose: closing it is
a different piece of work, and it belongs to whoever also decides what
`restoreMedia` should say when a FILE is sitting where the `Media` folder
belongs (the same class of problem, still answering `.failed` with the generic
sentence). Naming the event `folder problem repair blocked` would have forced a
rename on both platforms and in the contract the day that gap closes. So: wire
it to the directory branch, not to every failure, and leave the name alone.

### What is still not right in this file, on both platforms

Named here so it is not rediscovered as a puzzle, and NOT fixed by this piece:

- `restoreMedia` answers plain `.failed` when a FILE sits where the `Media`
  folder belongs. Same class of problem, same wrong explanation, no sentence of
  its own. The machinery to give it one is now in place — a second `Result`
  case and a second contract sentence — and nobody has decided the wording.
- `SectionAdder` has the identical bare `fileExists` guard on `index.md` when a
  section is added, so a folder by that name is skipped silently there too.
- ~~`repair(_:in:)` returns `[String: Result]` keyed by check NAME, so two
  findings with the same name collapse — your second finding of 2026-09-06,
  owned by its own piece of work.~~ — ✅ Done 2026-09-07, branch
  `issue/repair-results-keyed-by-name`. It returns `[Attempt]` now, one entry
  per finding, and the rule is contract data both suites can run
  (`siteHealth.repair.reportedOncePerFinding`). See item 34 above.
