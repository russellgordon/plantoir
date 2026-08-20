# Windows App — Handoff

> **New to this side? Read [`WINDOWS-BOOTSTRAP.md`](WINDOWS-BOOTSTRAP.md)
> first.** It says what to read, what to do in what order, and asks you to
> outline the plan before implementing. This file is the reference it sends
> you to.

Read this first when working on the Windows app — `windows-app/`, WinUI 3,
first take built 2026-08-11 — and especially when syncing it after a run of
macOS-side sessions. It gathers everything a Windows implementation needs; the
deep dives it links to are kept current. **Do not work through it top to
bottom.** Start with "Where Windows actually stands" immediately below — the
ordered work list, refreshed 2026-08-17 — and use `GUI-IMPROVEMENTS.md`'s
**Windows status** section for the per-entry detail behind it.

## Where Windows actually stands (read from the code, 2026-08-17)

**Read this before planning.** `WINDOWS-BOOTSTRAP.md` § 0 asks you to write a
plan before touching anything, and a plan needs to start from what is TRUE on
this side rather than from what the rest of this file describes. So the mac
read `windows-app/` end to end on 2026-08-17 and wrote down where the code
actually is. The per-entry version is in `GUI-IMPROVEMENTS.md` → Windows
status → "Entries 107–255"; this is the ordered work list that fell out of it.

**Its one limit, stated up front:** it was read, not run. `dotnet` is not
installed on the Mac, so nothing here was built or executed. Every claim below
is "the code says so", which is enough to plan from and not enough to close a
ticket with. **If you find one of them wrong, that is a defect in this
section** — say so in `MAC-HANDOFF.md`, the same way this side is expected to
say so when the contract is wrong.

**What is already good, so you do not re-derive it.** The launchers, the
container naming, the port leases, the milestone parsing, the three publishing
destinations, the per-section `publish:` flags, the Deploy/publish vocabulary,
the archive and restore work, the assistant's tool surface (19 of the
contract's 22 tools exist here) and its work lease are all in place. This side
has also been FIRST on real things — the deploy-after-preview live-reload bug,
the up-front duplicate-code validation, the "still working… (Ns)" timer — and
the mac copied them. The list below is a list of gaps, not a verdict.

### The order, and why it is this order

1. **Wire `contracts/` into `Plantoir.Tests`.** Nothing in `windows-app/`
   references the directory — not a test, not a `.csproj` `Content` include.
   Everything else on this list is a behaviour you would otherwise verify by
   opinion. `WINDOWS-BOOTSTRAP.md` § 2 says how; start with
   `assist-wording.json` and `file-formats.json` because both are pure data.
   Expect a red suite the first time, and expect it to be informative.

2. **Take the machinery out of the approval line.**
   `AssistAgent.AskFirst` (`Plantoir.Core/Assist/AssistAgent.cs:585`) builds
   `I'd like to run **{tool.Replace('_', ' ')}**. Shall I go ahead?` — so a
   teacher is shown "I'd like to run **deploy section**". That is rule 1
   broken at the exact moment the teacher is reading most carefully, and the
   replacement is data you will already have from item 1:
   `wording.deployApproval` followed by `wording.deployQuestion`. Small, and
   first for that reason — it is the shortest path from "contracts wired" to
   "contracts paying".

3. **The two known-failing deploy scenarios**, `assist-cases.json` →
   scenarios *"deploy with a preview running"* and *"deploy while that section
   is already busy"*. The Deploy button in the GUI is now enabled while a
   preview is active or building (`DeployButton.IsEnabled = !DeployIsRunning`).
   When Deploy is triggered — either by a teacher clicking Deploy in the
   window or by the assistant calling `deploy_section` — the deploy routine
   first stops any active or building preview (`preview.ps1 CODE N -Stop`),
   awaits container-side process termination, and only then starts the
   production build and deploy. **Await the stop** — a stop still running when
   the build starts kills the build, and what goes live is the site as it was
   before.

4. **The activity trail** (`CLAUDE.md` rule 5, `shared-rules.json` →
   `activityTrail.mustRecord`). Nothing on this side writes
   `%LOCALAPPDATA%\Plantoir\Logs` at all. It is placed fourth rather than
   later because it is the thing that makes the items below diagnosable when
   a teacher reports them: every feature after this one owes a line, and
   retrofitting a trail across a dozen features is several times the work of
   having it before you start. The rules for what must never be recorded, and
   the redact-on-the-way-IN design, are under "Problem reports" below.

5. **The problem report** (entries 212–218) — the dialog, the support address
   as a link, the redactor, and the "was the local AI assistant involved?"
   question that only appears when it was. This is item 4's payoff and reads
   naturally straight after it.

6. **The 2026-08-16 assistant batch** (entries 220–243), which is the largest
   body of behaviour and the reason the two assistants would otherwise drift
   apart. Everything in it postdates this side's last commit. Within it, four
   are verified missing rather than assumed:
   - `add_next_class` and `plan_add_next_class` exist nowhere here.
     `NewClassesPlan.cs` covers "add five more days to Unit 4"; it does not
     cover "add the next class" or "start a new unit for the next class".
   - `plan_remember_timetable` is likewise absent.
   - `LinkGraph.cs` excludes `index.md` and nothing else. The rule is now:
     a page is kept published by a VISIBLE referrer only, and Key Links'
     targets, All Classes, anything curriculum, and each sidebar folder's own
     index page do not count as referrers. The order in `reasonToKeep` is
     load-bearing — see `shared-rules.json` → `followingLinks`.
   - Confirmation is a SETTING now (`shared-rules.json` →
     `assistantConfirmation`), with a one-time mention after 15 confirmed
     actions, app-wide. `AppSettings.cs` has no field for either.

7. **Re-dating's two corrections** (entries 250–251). `ReDatePlan.cs` exists
   and works; what is missing is the 2026-08-16 change of mind. Refusing when
   a section has more classes than the new year has days READ as careful and
   was the opposite — it left every page on last year's dates, which is the
   state the teacher was trying to leave. Overflow classes now go on the
   FINAL class date, and adding a class stops refusing when the dates run out
   for the same reason.

8. **Asking for the schedule** (entries 246–248): ask "May I ask you for your
   class dates?" with Yes or Cancel before any form appears — a form nobody
   asked for is a demand, and this one arrived on top of the sentence
   explaining why it was there. Plus replacing dates already given, and not
   re-answering the question the preceding line just answered.

9. **Renaming a course code** (entries 205–211) — the Rename item, the
   Obsidian close-rename-reopen dance, Return in the sidebar, the
   12-character limit with single spaces, and uppercase always. The whole
   design is already written up under "Renaming a course (entry 205)" below,
   including three traps that each cost real time here.

10. **The local model, off the container** (entries 144, 147, 180, 196).
    `LocalModel.cs` still runs `ghcr.io/ggml-org/llama.cpp:server` under
    `docker run`. Two separate things: the HOST move (measure on integrated
    graphics, not only on your machine — see "The requirement: pick whatever
    makes it FASTEST on Windows"), and the **two thinking flags**, which are
    absent from the command line today. On Qwen2.5-1.5B they cost nothing,
    because that template does not open a `<think>` block; the moment a Qwen3
    tier is offered they are worth 58 points of routing accuracy (97% with
    thinking off against 39% with it on, identical weights). Add them when
    you add the tier, not after measuring a bad number.

11. **The assistant-choice Settings panel** (entry 219) — which follows item
    10, because there is nothing to choose between until there is a ladder.

12. **The token dialogs** (entries 253–254). Mostly a layout job once item 1
    is done: the sentences are `shared-rules.json` → `credentialRequests`,
    including what expiry to set (Netlify's default of 7 days will stop a
    teacher's publishing without warning) and where Cloudflare's Account ID
    is found.

13. **Two small ones, whenever they are convenient.**
    `NewCourseDialog.AutoFillCourseName()` line 549 sets `names.Formal` and
    wants `names.Short` (entry 252 — the shared Python half is already done).
    And entry 130's switch for the Curriculum Coverage explainers, which
    exists in neither the wizard nor Course Settings here.

14. **Later, and not yet:** plantoir.app (entry 255) is generated from
    `website/` and is SHARED — do not build a second one. What this side will
    owe, once the Windows app is worth photographing, is Windows screenshots.
    The mac's capture harness is AppleScript plus ScreenCaptureKit and will
    not port; the requirement is the picture, not the mechanism.

### One thing NOT to do

Do not port entry 142 (Colima sizing) or entries 244–245 (`launchd`). They are
macOS mechanics. The transferable half of 244–245 is a single lesson worth
having before you touch `TaskScheduling.cs`: register a scheduled job as the
APP, not as the shell it happens to run, or the operating system tells the
teacher that "bash" — or, on the second attempt here, a person's name — wants
to run in the background.

## What you are building

A native Windows app wrapping the same toolchain the macOS app wraps. The
toolchain itself is **shared and already done**: the Docker image recipe
(`Dockerfile`, `patches/`, `scripts/`, `support/`), the Python that runs
inside the container, and the PowerShell launchers (`setup.ps1`,
`preview.ps1`, `deploy.ps1`) all live in this repository. The Windows app's
job is the interface: the same behaviours as the macOS app, driving the
`.ps1` launchers instead of the `.sh` ones.

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
3. **Free resources whenever possible.** Close a folder's last window →
   stop that folder's container. Quit the app → stop the engine only if
   nothing else is using it.

## Architecture the app must reproduce

- **Working folders**: a folder holding `courses/`, the three launchers,
  and `.toolchain/` (the full image recipe, mirrored there by the app from
  its own bundled copy — refresh any launcher/recipe file that differs
  whenever the app works in a folder).
- **Local image builds, no registry**: the launchers hash the recipe
  (every file in the build context, pruning `.git`, `courses`, `mac-app`,
  `node_modules`, `.merged_output`) and tag `teaching-quartz:src-<hash8>`.
  A changed recipe → new tag → rebuild → recreated container. The `.ps1`
  launchers already implement this (`Get-ToolchainHash`).
- **One container per working folder**: named
  `teaching-quartz-<first 8 hex of SHA-256 of the folder's physical path + newline>`.
  The app must derive the identical name the launcher derives — beware
  path canonicalization differences (macOS needed POSIX `realpath`; check
  what PowerShell's `pwd -P` equivalent emits on Windows).
- **Port blocks**: each container publishes a probed host block
  (bases 8081, 8091, 8101, 8111, 8121, 8131): base..base+3 → container
  8081–8084 (four concurrent previews per folder) and base+1000..+1003 →
  9081–9084 (Quartz's live-reload websockets). The app leases ports per
  folder (`PreviewLeases` in the macOS app), parses the announced
  "Preview will be available at:" address rather than assuming it, and
  refuses a duplicate preview of the same section in the same folder.
- **Course activity registry** (entry 104): one cross-window record of
  which courses are previewing (the port leases already know) or
  publishing (begin/end records around the publish flow, ended on EVERY
  exit path). "Add Section…" declines while its course is active, with a
  short line naming the blocker ("Available once preview completed").
  Staleness lesson: read the enabled state when the menu OPENS, or make
  registry changes re-render whatever hosts the menu — a state captured
  at an earlier render shows yesterday's answer.
- **Stopping a preview reclaims the container side** (entry 105): killing
  the host-side launcher orphans the build or server INSIDE the
  container (an orphaned build burns real CPU). `preview.ps1 CODE N
  --stop` kills that section's container-side processes (found by
  working directory, so other sections are safe) and never starts
  anything. Call it fire-and-forget — output discarded — wherever a
  preview ends: stop button, navigating away, window close.
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
- **Container engine**: Docker Engine in WSL2. The macOS zero-prerequisite
  bootstrap (static Colima/Lima/docker/buildx downloads into the app's own
  Application Support folder) needs a Windows analogue — silent WSL2 +
  engine setup, per entry 72's note. Stop-at-quit analogue:
  `wsl --terminate` only when nothing else runs in the distro.
- **BuildKit is mandatory** — the legacy builder corrupts a layer.

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
  `build_site.py`, both defaulting true. **Not yet implemented on Windows**:
  neither key appears anywhere in `windows-app/`, so a teacher who turns the
  map off on a Mac and opens the same course on Windows can silently have it
  turned back on by a settings save
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
  runs inside the container on every build to draw the 1200×630 card. `patches/Head.tsx`
  wires OpenGraph and Twitter card metadata, and `scripts/build_site.py` / `scripts/deploy.py`
  sync the live site domain into Quartz's `baseUrl` (falling back to `undefined` when unpublished).
  Because the entire flow lives in the shared container toolchain, Windows inherits it automatically.
- **The recipe hash is on the hot path** (entry 118) — and it was slow
  on BOTH platforms, for the same reason in two dialects. The image tag
  is a SHA-256 over every file in `.toolchain/`, and the recipe carries
  the eighteen example-content payloads and the fifty subject skeletons:
  **11,378 files** as of 2026-08-15, and still growing — it was 5,694 two days
  earlier, which is the rate that makes this matter. The `.sh`
  launchers spawned one `shasum` process per file (36s of a 36.75s
  preview startup on an M4 Pro); they now pipe
  `find -print0 | sort -z | xargs -0 shasum` and take 0.16s.
  `Get-ToolchainHash` in the three `.ps1` launchers had the quadratic
  version of the same bug: `$combined += (Get-FileHash …).Hash` inside
  the loop, and PowerShell strings are immutable, so every one of those
  thousands of appends reallocated a string heading for a third of a
  megabyte. They now collect into `$hashes` and `-join` once. Measure this
  when you test: on macOS the batched version hashed 5,694 files in 0.25s,
  so anything near a second on Windows means the fix did not take.
  **This change is committed but never executed — there is no PowerShell
  on the Mac it was written on.** Please run it early and confirm two
  things: that a preview still starts promptly, and that the tag it
  prints is UNCHANGED from before the edit. The characters and their
  order are meant to be identical, so the tag should be too; if it is
  not, every Windows teacher takes one needless image rebuild.
  Whatever else changes here, keep any per-file work out of a
  per-invocation loop — this cost half a minute before every preview and
  publish, and it grows with each payload added.

## The toolchain mirror is on a hot path, and it cost seconds (entry 211)

Both apps mirror the bundled build recipe into each working folder's
`.toolchain`, because the launchers hash that folder to name the image. On the
mac that mirror ran inside `reloadCourses()` — after every rename, backup,
restore and archive — and it cost **3.80 seconds with nothing to do**. A
teacher felt it as a pause between pressing Return on a renamed course and the
field going away, and nobody would have attributed it to the mirror, because
the mirror is not what they had just done.

The measurements, from an M4 Pro with everything on an internal SSD:

| | Before | After |
|---|---|---|
| Mirror with nothing to change | 3.80 s | 0.37 s |
| On the rename path | every time | never |

`support/` alone is **61 MB across 11,354 files** — the example content and the
subject skeletons. Three things were wrong, and the first two are easy to
write on any platform:

1. **It read both copies of every file to prove they matched** — about 122 MB
   per pass. A size-and-modification-date check answers the same question for
   almost all of them. The catch: the copy must be **stamped with the
   original's modification date**, or the check never matches and you have
   bought nothing. (The image hash covers file CONTENTS, so restamping cannot
   cause a spurious rebuild — check that is true of your hashing too before
   copying this.)
2. **The removal pass was quadratic**: an 11,354-element array asked
   `contains` once per destination file, around 129 million string
   comparisons. A set makes it nothing.
3. **It ran far too often.** The source is inside the app's own bundle, which
   cannot change while the app is running, so mirroring a given folder more
   than once per launch cannot find anything the first pass missed. It now
   runs once per folder per run. **This is the fix worth copying**, and the
   justification is the same for you.

**One latent bug found on the way, worth checking on your side.** The mirror
worked out each file's place inside the folder by taking a fixed number of
characters off the front of its path. Directory enumeration hands back
RESOLVED paths, so a working folder reached through a symlink produced
nonsense — every destination file looked extraneous, and the mirror deleted
the entire toolchain and copied it back on every pass. A folder on the Desktop
never showed it. If your path arithmetic assumes the prefix it asked for is
the prefix it gets, you have the same bug waiting for the first teacher whose
folder is reached through a link or a mapped drive.

## Renaming a course (entry 205)

A teacher looks a course up by its CODE — it is how the wizard finds
ready-made content — and the code they typed at setup can turn out to be the
wrong one. Until now that meant building the course again, because the code
is the folder name. It is now editable: **Return** on the selected course in
the sidebar, or **Edit ▸ Rename Course**, edits it in place the way Finder
renames a file.

**The rule for what a code may be is now shared, and it is stricter than what
the wizard used to allow.** `CourseCodeRule`: trimmed and upper-cased, ASCII
letters and digits, **single spaces between them**, **at most twelve
characters**, no punctuation, no emoji, and no clash with another course
(compared case-insensitively — a Mac's disk is case-insensitive but
case-preserving, so ICS3U and ics3u cannot both be folders). It moved out of
the wizard because renaming asks the identical question, and a wizard that
accepts a code renaming refuses is a course a teacher can create and then
never re-type. The cases are in `contracts/course-management.json` →
`courseCode`; **deserialise them, do not retype the sentences.**

Twelve rather than six is a decision, not an oversight. Ontario codes are six
characters, but clubs and locally-named courses are named by the teacher, and
refusing ROBOTICS or AP CALC would be refusing real things teachers do. The
space rule has three parts and they matter separately: a single space BETWEEN
letters or numbers is fine; leading and trailing spaces are **trimmed rather
than refused**, so a teacher is never told off for a space they did not mean
to type; two spaces in a row is a typo every time and says so. CS-CLUB is
still refused — punctuation is out because the code is a folder name, a
zip-name prefix and part of a scheduled-publish identifier all at once, and
each of those has its own opinion about what it will carry. CS CLUB, with a
space, is how to write it.

**Every problem has TWO wordings, and both are teacher-facing.** The full
sentence ("A course code can be at most 12 characters.") goes under the New
Course wizard's wide field, where it can afford to explain itself. The sidebar
row renaming in place has room for about twenty-five characters before the
message is cut off mid-word, so it shows a short form instead ("12 characters
at most"). Both come off ONE enum in the code, so they cannot drift into two
different rules, and both are in the contract — `expectProblem` and
`expectShort` on each case. **Inherit both**: a truncated explanation explains
nothing, and it is the kind of thing that only shows up on the narrow layout
nobody tests.

**The in-place editor needs its own background, and this is not a style
preference.** A course is always SELECTED while it is being renamed, so the
row is drawing on the selection colour and everything inside it is tinted to
sit on that: the first version was black-on-blue in the field and red-on-blue
for the message. Painting the field and its message on one card in the
system's semantic text-background colour takes the content off the selection
entirely — and because the colour is semantic it is white in Light Mode and
near-black in Dark with no second code path. Finder does exactly this when it
renames a selected row: blue row, white field, black text, thin border.
Checked in both appearances on a running app.

**A space in a code is safe downstream, and one piece of code already existed
for it**: `ScheduledDeploy.sanitizedCode` is there precisely so that a club
named with a space cannot produce a bad launchd label. Check your equivalent
before turning the rule on — a code with a space reaches your scheduler, your
zip names and your folder paths.

**What renaming touches, and what it deliberately does not.** The full list
is `courseCode.renameEffects` in the contract, with a reason on each; the
short version:

- **Moves the folder** and **rewrites `course_code`** inside
  `course_config.json`. Both, together: your app reads a course's code from
  the FOLDER name while the shared Python's site builder and social-card
  maker read it from the settings, so a pair that disagree give a sidebar
  saying one thing and a published page saying another, with no error
  anywhere. Write the settings FIRST, while the folder is still where it was,
  and put them back if the move then fails — that ordering is what makes a
  failure leave nothing half-done.
- **Leaves the course NAME alone.** `course_name` is the teacher's own
  wording, editable in settings. Rewriting a title they may have hand-written
  because they changed a code is the kind of helpfulness that loses work.
  (Rejected: looking the new code up in `ontario_secondary_courses.json` and
  offering to update the name. It needs a confirmation step, which breaks the
  type-and-press-Return feel, and the teacher can already edit the name.)
- **Leaves backups and archives under the OLD code**, in
  `courses/_backups/<OLD CODE>/`, named as they were made. That is what they
  are: a copy of the course as it stood, when it was called that. (Rejected:
  moving and re-prefixing them. It was mechanically fine — the mac's restorer
  names the restored folder after the ITEM rather than after whatever the zip
  holds inside, so a renamed zip still restores — but a backup is a record of
  a moment, and relabelling it with a name that moment never had makes the
  list lie.)
- **Leaves the published site where it is.** On the mac the Netlify site
  marker lives INSIDE the course folder (`.netlify_sites/section<N>.json`),
  so it travels with the move and the students' address does not change.
  **Check that your equivalent marker is inside the course folder too** — if
  yours is stored anywhere keyed by course code, renaming silently orphans
  the site and the next publish creates a second one.
- **Turns scheduled publishing OFF**, and says so in an alert naming the
  sections. This is the one thing renaming has to break: a scheduled publish
  is an alarm held OUTSIDE the working folder addressed by the old code (on
  the mac, a launchd agent labelled
  `ca.russellgordon.Plantoir.deploy.<CODE>.section<N>`), so after a rename it
  fires at a course that is no longer there. The MECHANISM is yours to
  choose; the decision — cancel rather than orphan, and tell the teacher — is
  shared, and the alert is required. A scheduled publish that quietly stops
  is exactly the failure worth interrupting somebody for.

**Renaming waits while the course is previewing or publishing**, because it
moves the folder the preview is serving out of. Same rule and same words as
"Add Section…", checked twice: once to decide whether the menu item is
dimmed, and again at the moment of commit, because a preview can start while
the field is open.

### Three traps, each of which cost real time here

1. **Return must not be a menu key equivalent.** It is tempting to put the
   shortcut on the Rename menu item and be done. On macOS a bare Return on a
   menu item is matched before the key reaches the focused control, which
   takes Return away from every text field and default button in the window —
   Finder's own Rename item carries no key equivalent for exactly this
   reason. Handle the key in the list instead, and ignore it when a field is
   already open so the field's own Return commits. If your framework has the
   same precedence, do the same; if it does not, say so in `MAC-HANDOFF.md`.

2. **Switching apps is not clicking away.** Clicking elsewhere should commit
   the rename, as Finder does. But a focused field cannot hold focus while
   its application is inactive, so a blur handler that commits or cancels
   fires the instant the teacher looks at Obsidian — and on a Mac where the
   app was never brought to the front, the instant the field opens. Measured
   here: the field appeared and vanished again before anything could be typed
   into it. Guard the handler on the application being active. A code that
   cannot be used reverts on blur rather than raising an alert, since the
   teacher has already moved on; the reason is shown under the field while
   they are still typing, which is also where the New Course wizard puts it.

3. **Accessibility could not see the row, and nearly sent us the wrong way.**
   macOS collapses a sidebar row — a `DisclosureGroup` label inside a `List` —
   into a single element whose value does NOT follow the row's content: an
   unconditional change to the label's text left the reported value
   unchanged. That looked exactly like "the row is not redrawing", and an
   afternoon went into fixing a bug that was not there while the feature
   worked perfectly when driven by hand. The test that finally answered it
   hosts the ROW VIEW on its own and asserts a text field appears in it —
   deterministic, and no accessibility tree involved
   (`CourseRenameInterfaceTests`). If your framework's tree exposes list rows
   honestly, that is worth a line in `MAC-HANDOFF.md`.

### Obsidian: close it, rename, and open the vaults again

Renaming moves the course folder, and that folder **is** the Obsidian vault.
Obsidian's watcher is anchored to a folder's identity, so a vault open on that
course goes on showing files that are no longer there. Obsidian has no way to
close ONE vault, so putting it right means closing Obsidian — which is a big
enough thing to do to somebody else's application that Plantoir asks first,
with two buttons: **Close Obsidian and Rename**, or **Cancel**. There is no
third answer that leaves Obsidian showing the truth, and a teacher who does
not want it closed can close that vault themselves and rename after.

**When the vault is not open, nothing Obsidian-related happens at all.** No
registry writing, no questions. That is a deliberate limit on the blast
radius, not an omission.

The registry is `%APPDATA%/obsidian/obsidian.json` on Windows and
`~/Library/Application Support/obsidian/obsidian.json` on the mac, **the same
JSON shape**, so all three of the following are yours to inherit. Each was
measured on a real machine rather than reasoned about, and the first two would
each have shipped a bug:

1. **`"open": true` is stale in TWO ways, and reading it alone is wrong.**
   Obsidian writes the mark when a vault opens and does not reliably remove it
   afterwards. Both stale cases were found by testing, and each one shipped a
   wrong dialog before it was:

   - **It survives a quit.** A vault here carried the mark for hours with
     Obsidian closed. So pair the mark with "is Obsidian running".
   - **It survives the vault being CLOSED while Obsidian stays running.**
     Measured with every vault closed and Obsidian still up: no windows on
     screen at all, and one vault still marked open. So also require that
     **Obsidian has at least one ordinary window on screen** — through the
     window server's own list, which hands out an owner and a size to anybody.
     A window's TITLE names its vault and would settle everything, but reading
     another application's window titles needs the screen recording
     permission, and asking a teacher for that so a folder can be renamed is
     out of all proportion. Owner and count need no permission.

   Do not assume the mark is exclusive — several vaults carry it at once when
   several are open, which is what makes reopening the whole set possible.

   **What is still imprecise, and it is worth writing down rather than
   discovering:** the marks can over-report while a window IS on screen.
   Closing one of two open vaults cleared its mark here; closing the other did
   not. So with one vault genuinely open and a stale mark beside it, one extra
   vault may be opened again after a rename. An extra window is a small price
   against a permission prompt for every teacher — but know that it is the
   remaining edge, so it is not re-diagnosed as a new bug.

2. **Obsidian does not restore its windows on relaunch.** This file used to
   say it did, in the "Behaviours with platform-specific mechanics" section,
   and that was wrong. With two vaults open, quitting and relaunching through
   `obsidian://open?path=` brought back **only** the vault named in the link;
   the other stayed closed. So every open vault is noted BEFORE the quit — the
   marks survive it — and each is opened again afterwards, the course's own
   one last so it lands in front. The same bug was in "Open in Obsidian",
   which had been closing teachers' other vaults and not reopening them
   whenever it registered a new vault; it is fixed with the same helper.

3. **Repoint the existing registry entry; do not add a second one.** Keeping
   the entry leaves the vault list the length the teacher expects and no dead
   entry pointing at a folder that no longer exists. Verified end to end:
   quit, move the folder, repoint, reopen — the vault comes back with its list
   unchanged and the mark on the right row.

Order matters, and for one reason: a running Obsidian holds its vault list in
memory and writes it back out when it exits, so a registry edited underneath
it is simply lost. Quit first, write after. And if the rename itself fails,
open the vaults again anyway — closing somebody's editor and then not
reopening it because a separate thing went wrong is the worst of both.

### The sidebar could not hold the keyboard, and that is why Return did nothing

Worth reading even though the mechanism is macOS's, because the SHAPE of the
bug is not: a feature that is correct in every unit test and does nothing at
all in the app.

Return was wired to the sidebar and did nothing. The cause was not the key
handling: **the course settings form's first text field takes the window's
keyboard focus whenever a course is selected, and keeps it.** Nothing in the
app asks for that — it is the framework's own initial focus, re-established
every time the detail pane is rebuilt — and the accessibility API reported
that field focused however the list asked for focus instead, including a
deferred ask. So Return was going to the settings form the whole time, and so
were the arrow keys: the sidebar could not be navigated by keyboard at all.

Selecting a course now moves focus to the list explicitly, through AppKit,
which is how a source list behaves everywhere else on the platform. **Check
whether your detail pane does the same thing** — if the first field of your
settings form takes focus on selection, your sidebar has the same silent
problem, and any keyboard feature added to it will appear to be broken.

Two more notes on the key itself, both of which cost time here:

- **Do not give the menu item a bare Return shortcut.** It is matched before
  the key reaches whatever has focus, so it takes Return away from every text
  field and default button in the window — including the rename field the
  feature itself opens. Finder's own Rename item carries no key equivalent.
- **The key is answered by a narrow monitor**: only a bare Return or keypad
  Enter, only in its own window, only while the thing with focus is the
  courses list itself, and never when a text field is being typed into.
  Anything looser renames a course from somewhere the teacher was not
  looking — and a monitor with no window check renames in EVERY open window
  at once.

## Fixed in shared code — nothing to port (entries 111–121)

A run of rendering and content defects was found and fixed on the macOS
side. All of it lives in shared Python or in the payloads, so Windows
inherits it by rebuilding the image. Listed so you are not surprised by
diffs, and so nobody re-fixes them:

- **Mermaid diagram labels were hyphenated mid-word** ("Ca-reers"). Not
  an engine bug: Quartz hyphenates body text and it leaked into diagram
  labels. WebKit acts on it, Chromium ignores it — which is why the same
  site looked right in Chrome and wrong in a preview.
- **Mermaid measured labels before the code font loaded**, sizing every
  box for the fallback so long labels were clipped. It now waits for
  `document.fonts.ready` first. Google Fonts serves the code font with
  `display=swap`, so this is a real race on any platform.
- **Pie chart titles were clipped** — mermaid centres the title on the
  pie, which the legend pushes leftward, and never widens the chart. The
  viewBox is now re-fitted to what was drawn.
- **A pie chart's first slice was drawn in the page background colour**
  and vanished, legend swatch and all: mermaid takes `pie1` from
  `primaryColor`, which Quartz sets to `--light`. The palette is now
  solved per colour scheme at render time, and it must stay that way —
  fractions tuned against one scheme failed 74 of the 86
  scheme-and-mode combinations.
- **The right sidebar's backlinks crowded out the table of contents** on
  much-linked pages. They now share the column, each with its own
  scrollbar.
- **Payload rules now enforced by `lint_payload.py`**: class pages carry
  no curriculum connection (those codes belong on the pages the agenda
  links to), and no page stands on its own — every page must be reachable
  from a class page within two hops, with Key Links not counting. Both
  are in the example-content skill.
- **Chemistry is typeset with mhchem.** `build_site.py` adds
  `import "katex/contrib/mhchem"` to `latex.ts`, so `$\ce{CaCO3(s) <=>
  CaO(s) + CO2(g)}$` renders properly. The three chemistry payloads were
  converted outright — 1,533 spans — and the skill now forbids formulae
  built by hand out of `\text{}`.
- **`What This Site Can Do` is the LAST entry of every payload's
  `Key Links`**, so a teacher evaluating the app meets the site tour from
  the sidebar. Enforced by the linter.
- **Per-section publishing in the installer**: a course-level page now
  arrives with `createdSectionN` / `publishForSectionN` for each section the
  teacher chose, rather than one shared pair. Payloads keep the plain
  sentinel — the split happens at install time, because a payload cannot
  know the section count.

## Two things that DO need porting (entries 122–123)

**1. Subject skeletons in the New Course dialog (entry 123).** Every
Ontario course code that has no example content now starts from a skeleton
shaped for its subject — 50 families over 499 three-letter prefixes, living
in `support/skeletons/` with a `families.json` prefix map. The installer
side is shared Python and comes free, so a course created through the CLI
wizard already gets it. The dialog needs the macOS `SkeletonCatalog`
equivalent: read `families.json`, map the code's first three letters to a
family (falling back to `default`), read that family's `manifest.json`, and
seed the four structure lists from it when the code changes. Show a toggle
naming the subject ("Start from a music skeleton"), and write
`use_skeleton` into `course_config.json` so the wizard's own prompt agrees.
Three rules matter: a code WITH example content is never offered a
skeleton; a folder list the teacher has edited is never overwritten; and
the sidebar is decided structurally rather than by a fixed list — hidden is
`Media` plus the family's own `hidden` entries that the course actually
has, and expandable is every shared folder that is not hidden, so a folder
the teacher invents gets a chevron like any other. Per-section folders
(All Classes) are never expandable. macOS decides all three in two pure
functions, `SkeletonCatalog.structureToAdopt` and `SkeletonCatalog.sidebar`
— those are the pieces worth copying.

**2. Adding a section must extend the course-level pages (entry 122).** The section
folder is only half the job: every page at the course level — the shared
folders and files, everything outside `sectionN/` — carries a
`createdSectionN` / `publishForSectionN` pair per section, and a section added
later needs its own pair or it builds those pages with no date and no
publishing state at all. macOS does this in
`SectionAdder.extendCourseLevelPages`: walk the course folder skipping the
`sectionN` directories, and for each markdown page whose FRONTMATTER
already uses the per-section form, append a fresh
`createdSection<new>` plus a `publishForSection<new>` copied from the
lowest-numbered existing section. Leave pages with a plain `created:`
alone — they already apply to every section — and never read past the
frontmatter, because the site-tour page shows `publish: false` inside a code
block as documentation.

> **The key changed name AND polarity (entries 140/141), so an implementation
> written against the older text of this section would be wrong twice.** The
> flag is `publish:` / `publishForSection<N>:`, and `draft: true` ≡
> `publish: false`. The legacy `draft` spellings are still READ — a course
> nobody has touched behaves exactly as it did — but they are **never
> written**. Read new-then-legacy-inverted, write new only:
> `PageFrontmatter.PublishKeyFor` on the Windows side,
> `SectionAdder.swift` on the mac's.

## The local assistant: run the model natively, not in a container

> **DECIDED, 2026-08-15: Windows should move its model out of the container
> too.** What follows was written as a recommendation with measurements behind
> it; the mac has since shipped the native arrangement, it works well, and the
> Swift implementation is now the reference for how the assistant should be
> built. This is no longer "worth measuring before committing to" — it is the
> direction. Measure your own hardware to size the tiers, not to decide whether
> to move.

**Measured on macOS 2026-08-15, and the numbers are large enough that they are
worth acting on rather than filing.** The feasibility work
(`research/ai-assist/HISTORY.md`, part 2 §2) records the Windows engine's
constraints — 4 GB, 2 cores, no GPU, ~21 tokens/second — and
observes that "21 tokens/second is the number that governs everything." It
does govern everything. It is also an artefact of running the model inside a
container, not a property of the hardware.

The macOS build runs the same model (Qwen2.5-1.5B-Instruct Q4_K_M, byte for
byte the same 1,117,320,736-byte file) natively, with Metal. Same prompt, the
same 3,411-token tool surface:

| | Docker-in-WSL2, 2 cores, no GPU | Native, Metal (M4 Pro) |
|---|---|---|
| Cold prompt read (3,411 tokens) | **175–179 s** | **2.1 s** |
| Generation | **5.5 tok/s** in the assist loop | **158 tok/s** |
| A ~50-token tool call | ~9 s | ~0.3 s |

Two consequences worth having:

1. **The three-minute wait is not inherent.** It is the cost of reading the
   tool definitions on two virtual CPU cores. Given a GPU it is seconds.
2. **The whole disk-cache save/restore mechanism becomes unnecessary.** §10.1
   calls it "the biggest win available" and it is — when the thing being
   avoided costs 175 seconds. When it costs two, the machinery (per-course and
   per-section cache files, tool-schema fingerprints in the file name, an
   empty-save that silently poisons the next session) is more failure surface
   than it is worth. The macOS build does not have it. It warms the prefix in
   the background when the window opens instead, which is a dozen lines.

**Windows can almost certainly have this too.** llama.cpp publishes native
Windows builds beside the macOS one in the same release — as of `b10435`,
`llama-<build>-bin-win-cuda-13.4-arm64.zip`, `win-cpu-arm64`, and Vulkan
builds for AMD and Intel GPUs. Running `llama-server.exe` on the host, out of
WSL2 entirely, should collapse the same two numbers. The rest of the design
does not care where the server is: it is the same OpenAI-shaped HTTP endpoint
either way, so `LocalModel` should need little more than a different way of
starting the process.

A machine with no usable GPU falls back to CPU and lands somewhere between the
two columns; that is worth knowing rather than assuming, and it is what decides
the tier ladder on Windows. But the container is not buying anything here that
a host process does not, and it is costing three minutes.

### The requirement: pick whatever makes it FASTEST on Windows

Stated plainly by the maintainer, 2026-08-16, and it is a requirement rather
than a preference: **choose the design that gives the fastest possible
performance on Windows.** The mac's answer was to take the model out of Colima
and run it on Metal. Yours will not be Metal — it should be whatever Windows
offers that wins, and the only way to know which that is is to measure on real
teacher-grade hardware.

**Why this is worth an afternoon of measurement rather than a default.** The
container costs more than it looks. Same model, same 3,411-token prompt, on an
M4 Pro: **175 seconds inside Colima against 2.1 seconds natively** — 5.5
tokens/second against 158. That is not a tuning difference, it is the
difference between a feature a teacher uses and one they close the window on.
A Linux VM has no access to the host's GPU; the same will be true of yours.

**The candidates, in the order worth trying.** llama.cpp publishes Windows
builds for all of these in the same release as the macOS one, and the server
speaks the same OpenAI-shaped HTTP either way, so `LocalModel` should need
little more than a different way of starting the process:

| Backend | Where it wins | What to check |
|---|---|---|
| **CUDA** | An NVIDIA GPU, which many teacher laptops with discrete graphics have | Needs the right driver; the build is large. Fastest by a distance when present. |
| **Vulkan** | Broadest coverage — AMD, Intel Arc, and NVIDIA without CUDA | The pragmatic default if you ship ONE build. Measure it against CPU on integrated graphics before assuming it wins. |
| **DirectML / ONNX Runtime** | A Windows-native path across vendors | A different runtime and a different model format — only worth it if it measurably beats Vulkan on the machines teachers actually have. |
| **CPU** | The floor, and the fallback that must always work | Measure it. On a modern laptop with a 1.5B model at short context it may be perfectly usable, and it is the only path with no driver story. |

**Do not ship a backend you have not measured on integrated graphics.** The
teacher this feature is for is more likely to have an Intel iGPU than a 4090,
and a design that is fast on the developer's machine and unusable on theirs is
worse than one that is merely adequate everywhere.

**Two rungs, chosen from the hardware — same as the mac.** `app-rules.json` →
`modelTiers` carries the requirements: a smaller assistant and a larger one,
the rung picked by reading the machine rather than by asking the teacher, and
the interface saying only "the small assistant" and "the larger assistant".
The mac's own thresholds (under 16 GB / 16 GB and up) and its models are in
that file marked **macReference — do not copy**. Yours depend on what your
backend needs resident, and on a GPU there is VRAM to account for as well as
system memory, which the mac's unified memory does not have to separate.

**What must NOT change with the backend**, because these were measured and cost
days to find:

- **Zero polarity inversions is a veto**, not a tiebreaker. Two 3B-class models
  were rejected on it alone. Re-run the routing suite whenever the model, the
  quant or the context size changes — a faster model that publishes a page the
  teacher asked to hide is not faster, it is broken.
- **Thinking off takes TWO flags** if you follow the mac to Qwen3
  (`--reasoning off` AND `--reasoning-budget 0`). See the section below; it is
  a 97%-to-39% difference and it looks fine while being wrong.
- **The teacher never learns the model's name.** A faster backend does not buy
  a licence to say "CUDA" or "Qwen" in the interface.

When you have measured, write the numbers into `MAC-HANDOFF.md` — tokens per
second per backend, on named hardware. The mac side has no way to find out what
a Windows teacher's machine does, and those numbers are the only thing that
makes the next decision on either side a measurement rather than a guess.

### What moving out of the container changes, beyond the speed

Six things the mac learned the hard way, each of which applies the moment the
server is a host process:

1. **`--no-mmap` stops being required, and should go.** It exists because
   llama.cpp memory-maps the model and, inside a memory-capped container, the
   page cache for that file counts against the cgroup limit — a 3B model
   appeared to need 4 GB and died at 3 GB with no OOM message. There is no
   cgroup on the host. macOS passes no such flag.
2. **The prompt-cache save/restore machinery can be deleted**, as above: it
   buys 175 seconds in a container and two seconds outside one, and it carries
   real failure surface (an empty save silently poisons the next session).
   Warm the prefix in the background when the window opens instead.
3. **The model file moves to the host** — one file per machine, in the app's
   own data directory, surviving app updates — and you get to verify the
   download by exact byte count, which is worth doing: a captive portal or a
   proxy answers 200 with something that is not a model, and the resulting
   failure surfaces much later and looks like anything but a bad download.
4. **A second executable ships**, and it must be signed with the rest — the
   same lesson `plantoir-mcp.exe` already taught, since an unsigned binary
   beside signed ones is what SmartScreen objects to. Pin the llama.cpp build
   number the way the mac does (`b10435`), because an engine that changes under
   you between two builds makes every measurement meaningless.
5. **Which backend is a real choice, not a detail.** llama.cpp publishes CUDA,
   Vulkan and CPU builds for Windows. The mac has one answer (Metal, every
   layer, `--n-gpu-layers 999`); Windows has to decide what a teacher's Dell
   with integrated graphics actually gets, and whether you ship more than one
   backend or one that degrades. That is the measurement worth running.
6. **If Windows follows the mac to Qwen3, the reasoning flags become
   load-bearing.** `LocalModel` passes neither `--reasoning` nor
   `--reasoning-budget` today, which is CORRECT for Qwen2.5 (no thinking
   template) and would become a 97%-to-39% bug the day the model changes. Two
   flags, `--reasoning off` **and** `--reasoning-budget 0`; the per-request
   equivalent is `chat_template_kwargs {"enable_thinking": false}`. Confirm
   `--reasoning` exists in your build's `--help` — it is newer than the budget
   flag — and check the completion-token count and the clock, not whether a
   tool call came back.

The Swift implementation is the reference for all of this:
`mac-app/QuartzTeachers/Models/Assist/AssistServerHost.swift` (starting and
health-checking the process, and the flag list with its reasons),
`AssistModelTier.swift` (the ladder, the vetoes, and how the tier is chosen
from physical memory when the teacher has not chosen for themselves), and
`AssistModelStore.swift` (download, verification, where the weights live).
Since entry 219 the memory rule is the DEFAULT rather than the whole answer —
a teacher can pick a rung outright in Settings; see "Letting a teacher choose
which assistant runs" below, and note the trap that the engine must be started
with the chosen tier rather than the machine's.

### One assistant at a time, machine-wide

The downloaded model is shared — **one file per machine**, in Application
Support, whatever course or section is being worked on, and it survives app
updates. What is NOT shared is the RUNNING copy: each assistant window starts
its own engine and loads the weights again. Two windows is twice the resident
memory, which on a 16 GB machine is most of it and undoes the point of sizing
the model to the hardware.

So the macOS build allows exactly one assistant window at a time, across the
whole app. The menu item for every other section is **dimmed, with a line
saying which section to close** — "Close the assistant for ICS3U Section 1
first". Dimmed alone tells somebody they cannot do the thing; naming the
holder tells them what to do about it.

Three details worth copying rather than re-deriving:

- **Claim when the WINDOW opens, not when the engine is ready.** A teacher
  three minutes into a 2.5 GB download has the assistant open as far as they
  are concerned, and a second window started meanwhile is exactly what this
  prevents.
- **Release unconditionally on close.** A claim that leaks locks the feature
  out until the app restarts, which is a far worse failure than briefly
  allowing a second window. For the same reason a NEWER claim replaces a
  stale one rather than being refused.
- **The section that already holds it stays enabled**, because choosing it
  brings the existing window forward — which is what a teacher expects from
  a menu item naming a window they can see.

Read the registry during the row's RENDER, not inside the button's closure,
or the menu shows the answer from whenever the row last drew. That is the
same staleness trap `CourseActivity` documents for "Add Section…".

**This governs the built-in assistant only.** Claude Code driving the same
tools over MCP has no engine of its own, so nothing about it multiplies
memory and nothing about it should be blocked.

### Your two findings, re-measured natively — one held, one did not

Both were re-run on macOS against the same suite (3B, 3 trials, results in
`research/ai-assist/macos-native-results.txt`):

- **The date must be appended, not prepended: HELD.** Prepending cost 13–14
  points, against the 15 you measured. Treat this as a property of the model.
- **Rewriting the schema examples to the real course: DID NOT reproduce.** You
  saw `ICS3U` copied out of the examples 9 times out of 9; natively, the 3B
  copied it **0 times in 87 responses** with `ICS3U` still present in 14 places
  in the schema, and accuracy barely moved. **This is not grounds to remove the
  rewriting** — your finding was earned on the 1.5B, which is a different model
  from the one that failed to reproduce it, and the macOS build keeps the
  rewriting for exactly that reason. It is grounds to re-test it on whichever
  model you actually ship.

### And one finding of our own, which matters more than either

**Do not assume a bigger model is a safer one.** Qwen2.5 **3B inverts
polarity**: asked to hide a page it called `publish_pages`, in two of three
trials, and answered three separate hide requests with `undo_last_change`. That
is the one genuinely dangerous failure — the reason publish and unpublish are
separate verbs rather than one tool with a boolean — and the 3B also scored
BELOW the 1.5B on the like-for-like probe set (70% against 81%).

Be precise about WHY it is the dangerous one, because the obvious reason is
wrong and stating it wrongly will lead somebody to weigh it against a score.
A wrong publish does not put anything in front of students: **publishing marks
a page for inclusion, deploying is the separate act that reaches them**, and
undo takes a publish back. The veto is that an inversion is the only failure
that does not announce itself. Every other misroute runs a visibly wrong tool;
this one reports success while leaving the section in the OPPOSITE state to
the one the teacher asked for — and the next deploy then carries that out
faithfully, days later, with nothing to prompt a second look. A model that
will do the opposite of what it was told is not one whose remaining 70% can
be trusted.

The macOS build has no 3B rung as a result; the case was deleted from the enum
rather than marked risky, on the same reasoning as having no delete tool. If
Windows ever offers a model choice, measure each candidate for inversions
specifically, and treat that as a veto rather than a score.

The table below was three trials per probe. It was re-run at **ten** trials on
macOS across ten models on 2026-08-15
(`research/ai-assist/macos-native-10-trial-comparison.txt`), and the veto got
stronger, not weaker:

| Model | Routing (like-for-like) | Inversions |
|---|---|---|
| Qwen2.5 1.5B | 79% | none |
| Qwen2.5 3B | 72% | **9 of 10** |
| **Llama-3.2 3B** | 72% | **10 of 10** |
| Qwen2.5 7B | 94% | none |
| **Qwen3 4B (reasoning off)** | **100%** | **none** |

Two things in that table matter more than the numbers. First, a **second,
unrelated family at the same size inverts on the same sentence** — 'Hide
tomorrow's class again … the page is "Ohm's Law"' — which says the failure
belongs to that generation of 3B models rather than to one vendor. Llama-3.2 3B
also typed `"section": "1"` as a string on essentially every call. Second, it is
**not** a size law: a 2025-era 4B is clean at 100%. So measure the model you
intend to ship; do not reason from parameter count in either direction.

What macOS ships today: **Qwen2.5 1.5B under 16 GB, Qwen3 4B at 16 GB and up**,
no 3B rung, and the 7B dropped because the 4B beat it on accuracy, latency,
download and memory at once. The 8 GB tier is a deliberate hold rather than a
result — Qwen3 4B at 8k context measures 3.87 GB resident, which is 48% of an
8 GB Mac that is also running a container, and that has not been tried on real
8 GB hardware.

### Turning thinking off takes TWO flags, and we shipped the wrong one

**Check this in your launcher before you read any further** — it is one word,
it costs half the assistant's response time, and it is invisible in review.

`llama-server` has two separate settings and only one of them stops the model
thinking:

```
--reasoning [on|off|auto]   whether the chat template thinks at all
                            (default: auto — decided by the template)
--reasoning-budget N        how long it may think once it has started
                            (0 = stop immediately, -1 = unrestricted)
```

The macOS app shipped for several days passing `--reasoning-budget 0` alone,
on the reasonable-sounding belief that a budget of zero meant no thinking. It
does not. Qwen3's template still opened a `<think>` block on every turn and
filled it to the cap. Measured on one prompt against the same tool surface,
same weights, same temperature:

| Flags | Time | Completion tokens | Tool call |
|---|---|---|---|
| `--reasoning-budget 0` | 16.1 s | **512** | correct |
| `--reasoning off` | 8.4 s | **44** | correct |
| both | 8.4 s | 44 | correct |

The useful reply is 44 tokens. The other 468 were thinking nobody sees. Half
the wait, for a flag.

**Why it survived review, which is the transferable part.** The budget flag
does not produce a wrong answer — it produces a slow one, and the two obvious
checks both come back green:

- *"Did a tool call come back?"* Yes. 512 tokens is enough to think AND still
  route correctly on a short prompt.
- *"Is there a `<think>` tag in `message.content`?"* No — because at the
  default `--reasoning-format`, llama.cpp PARSES the thinking out of the
  content into `reasoning_content`. Its absence from the content proves the
  parser ran, not that the model stayed quiet.

The honest check is **the completion-token count and the clock**, not the
text. A router that is thinking looks exactly like a router that is not, only
slower — and "slower" is precisely the complaint that started this whole
piece of work. If the 3-minute Windows wait has any of this in it, this is a
one-word fix.

The 39%-vs-97% figure quoted above is the same fault at its severe end: on a
longer prompt the budget is consumed BEFORE the model reaches the call, and
no tool call arrives at all. Sixteen seconds is the mild end.

We now pass **both**, and a test asserts both for every tier:

```
"--reasoning", "off",           // stops the template thinking at all
"--reasoning-budget", "0",      // catches a template that ignores the above
```

The budget stays deliberately. A future model whose template does not honour
`--reasoning` would otherwise regress silently — which is exactly how this
one shipped. Two caveats for your side: `--reasoning` is NEWER than
`--reasoning-budget`, so confirm it exists in your build's `--help` before
adding it (ours is b10435); and check the flag against your own engine rather
than trusting this table, because the behaviour is the template's, not the
model's.

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

### The assistant presses the app's own buttons — Deploy included

**Windows got here first and the mac has copied it.** `AssistAgent.RunTool`
already intercepts `rebuild_preview` and `deploy_section` and calls
`ShowPreviewInApp` / `StartDeployInApp` instead of the server, for the reason
written in that file: a build nobody can see might as well not have happened.
That is the right design. This section is the mac's version of it, the two
bugs it fixed on the way, and the one half of it Windows is still missing.

On the mac the mechanism is a registry of closures, `SectionWindowControllers`
(renamed from `SectionPreviewControllers` when Deploy joined the preview
there). A section window registers `isPreviewRunning`, `startPreview`,
`stopPreview` and `deploy` while it is on screen; the assistant looks up the
window for the course and section it is about and calls them directly, in
order, on the main actor. A registry rather than a flag a view observes,
because the assistant needs "stop, then write, then start" to MEAN that, and
an observer acts whenever the UI framework next evaluates a body — which may
be after the writes. Your `Action?` properties are the same idea; keep them.

**What was wrong on the mac, and is worth checking on yours.**

1. **A deploy nobody could watch.** `deploy_section` ran `deploy.sh` in a
   script runner the assistant made for itself. It worked — and showed
   nothing. No console, no progress header, no live-site link at the end, for
   a job that takes minutes. The teacher had a spinner in the chat and a
   section window still saying "No Preview Running". You do not have this
   bug; this is the bug your design avoids.
2. **A running preview refused the deploy.** The assistant-side path asked
   `CourseActivity.busyDescription` first, which reports a course busy while
   any of its sections is previewing — so the one moment a teacher most often
   asks to deploy was the one moment it would not. Worse, the refusal was
   that helper's own string, "Available once preview completed": written to
   sit under a greyed-out menu item, and meaningless read out in a
   conversation. **Any string you show in the chat has to be a sentence that
   survives being read on its own** — menu labels, tooltips and button titles
   do not qualify, however true they are.

**What the mac does now, and what Windows still needs.** Both the Deploy
button in the section window and the assistant follow the same rule: **if a
preview is running or building, stop it, await the container cleanup, then
Deploy.** The Deploy button's disabled guard is now `!DeployIsRunning` (not
`!IsBusy`), so a teacher can click Deploy straight from a running or building
preview without having to click "Stop Preview" first. Windows stops the preview
only for page EDITS — `if (edits && PreviewIsShowing?.Invoke() == true) StopPreviewInApp?.Invoke();`
— and never for a deploy. And `StartDeployForAutomation()` calls `Deploy_Click`
directly without stopping the preview. So a Windows teacher who asks the assistant
(or clicks Deploy) while previewing would get a deploy and a preview in the same
container at once.

Two things to get right when you fix it:

- **Await the stop.** `StopPreviewIfRunning()` is `void` today. Stop mode
  finds a section's processes BY WORKING DIRECTORY and so catches builds as
  well as servers — a stop still finishing when the deploy's build begins
  kills the build, and what gets deployed is the last `public/` that was
  allowed to complete: the site as it was before. This is the same finding as
  the preview-staleness work, arriving somewhere new.
- **The approval sentence is written per tool, in the teacher's words, and it
  does not restate the request.** The card is two bubbles:
  `wording.deployApproval`, then `wording.deployQuestion` — the consequence,
  one piece of advice a teacher can act on, and the question. **The sentences
  themselves are in `contracts/assist-wording.json` and are not repeated here**,
  because a document that quotes them becomes wrong the day they change; what
  is here is the reasoning, which does not.

  It was cut down over two passes, and both rejected drafts are worth knowing.
  It began as a label with warnings stapled on — the act, then that this is the
  one thing that changes what students see, that Plantoir cannot take it back
  for you, and that looking the preview over first would be the safer order.
  That announces a limitation of the app to somebody who has already decided,
  and second-guesses the order they work in. The middle draft named the act
  ("OK, I'll deploy … to Netlify.") and read oddly against the question that
  follows: agreeing to do a thing and then asking permission for it. **If your
  card carries its own heading or repeats the act, you will meet the same
  awkwardness.** What it cost: the destination is no longer named in the
  conversation, so a teacher with one course on Netlify and another on
  Cloudflare is told what will happen but not where — the section window's own
  progress names it. `schedule_deploy` DOES still name its destination, because
  that one is agreed to now and runs when nobody is watching.

  `AssistAgent.AskFirst` currently builds "I'd like to run **deploy section**.
  Shall I go ahead?" by underscore-swapping the TOOL NAME, which puts machinery
  in front of a teacher at the exact moment they are agreeing to something.
- **Cancel is answered by kind**: `wording.deployWasCancelled` for a deploy,
  `wording.planWasCancelled` for a plan. The asymmetry is deliberate and is the
  part to understand — a plan described changes to pages, so whether they
  happened is genuinely in doubt and the reassurance IS the answer, while a
  deploy that never started needs no reassuring about. Read which kind is
  pending BEFORE clearing it; that is the one way to get this branch wrong.
  Both are scenarios in `assist-cases.json`, so your suite can simply run them.
- **Do NOT say that the preview stopped.** The mac shipped a sentence for it
  and removed it the same day, on sight: read in place it was three lines of
  machinery after the one line that mattered. `wording.deployed` is the entire
  answer to what was asked. The teacher is looking at the window it happened
  in, and an assistant that explains what it had to do in order to obey is
  talking about itself. The stop still happens; it is simply not narrated.

**One place decides the launcher's arguments.** The mac's assistant path built
its own `deploy.sh` arguments and never passed `--target cloudflare` or
`--account`, so **a Cloudflare course deployed by the assistant went to
Netlify** — no error anywhere, the site simply appeared on the wrong host,
because Netlify is the launcher's default and every course written before
Cloudflare existed relies on that. It now calls `DeployCommand.arguments`,
the same function the Deploy button and the scheduled-deploy alarm call. If
`Plantoir.Mcp` or your scheduled task composes its own arguments anywhere,
that is the same bug waiting. The milestone list has the identical trap: the
assistant's copy had no Cloudflare case, so a Cloudflare deploy narrated
itself as a Netlify one.

**Awaiting the deploy is optional; reporting it honestly is not.** The mac
waits and answers "ICS3U Section 1 is deployed. Students can reach it now."
Windows answers "The section is deploying from Plantoir's main window", which
is a fair answer and ends the turn cleanly. What must not happen is telling a
teacher a section IS deployed while the upload has three minutes left — they
go and look at a site that is not there. If you do start awaiting it, send the
destination refusals (no publishing folder, no Cloudflare account) back as
chat text rather than as a dialog on a window the teacher is not looking at;
the mac keeps the dialog for the button and returns a flag on the result so
the assistant can say the same thing in words.

**The fallback still matters.** With no section window open there is nothing
to press, and the assistant runs the launcher itself. That path is not dead
code — it is what Claude Code over MCP uses, and what a deploy scheduled for
half six in the morning uses. Keep it working, and keep it asking the same
place for its arguments.

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

### The class timetable, and the chore it removes

Stored once per section in `courses/<CODE>/.internal/timetable/section<N>.json`
— dates, where they came from in the teacher's words, when recorded. Under
`.internal/` so it travels through backup, archive and restore. A partial
list is refused whole rather than half-stored: a half-remembered timetable
gets trusted and then dates the wrong classes.

**Parsing lives in Swift, never in the model.** This dissolves the question
of whether a bigger model could accept looser input: the model never sees a
date it did not read from the teacher's own file, so the small local model is
exactly as capable here as any cloud one, and it cannot hallucinate a date.
Sources: a shared Google Sheet link (fetched as CSV), a `.csv`/`.ics` file,
or pasted text.

**Ambiguous day/month ordering is ASKED, not guessed.** Any value with a
number past 12 settles the whole column silently, so most teachers never see
the question. When nothing settles it, quote the teacher's OWN date back —
"Is 08/09/2026 the 8th of September, or the 9th of August?" — apply the
answer to every row, and record the choice in the stored source string. Never
per-row, and a column written both ways round is a corrupt file, not an
ambiguity. Guessing here dates a term months out and nobody notices until a
class page appears on the wrong day.

**`add_next_class` — the chore this is all for.** A teacher finishing a
lesson wants tomorrow's page to exist, numbered and dated, without opening
frontmatter. The rule, and the second half is the part to get right:

- the NAME continues the highest unit, then the highest day inside it:
  Unit 3, Day 2 → Unit 3, Day 3;
- the DATE comes from **position in the timetable, not from the numbering**.
  Count the section's class pages, add one, take that date. Fifteen pages →
  the sixteenth date. A page called "Field Trip" consumes a date without
  moving the numbering, which falls out of counting pages rather than parsing
  names.

Refuse usefully at both edges: no timetable stored ("I don't know when ICS3U
Section 1 meets…"), and a timetable that has run out ("…has 40 class pages
and 40 dates, so there is no date left. Add more class dates."). "Index out
of range" helps nobody.

### The section index follows its newest class — the invariant, and its limit

A section's `index.md` is what a student lands on, and it opens by
transcluding one class page under "Most Recent Class". Every example course
used to carry a note telling the teacher to repoint it by hand after each
lesson. It is now maintained, and the rule is stated as an INVARIANT rather
than as a fix to the case that revealed it:

> **The section index transcludes the most recent class page students can
> see, and carries that class's date.**

Written that way, publishing a newer class is covered by the same sentence as
unpublishing the current one. Written as "unpublishing repoints the index",
the publish direction stays broken and nobody notices until a teacher
publishes tomorrow's class and the front page still shows last week's.

Three implementation points that will bite otherwise:

- **Match the transclusion by class TITLE, not by position.** The same index
  transcludes Help Sessions and Key Links. Repointing one of those at a lesson
  is a far worse bug than the one being fixed.
- **Read "which class is newest now" back from the section on disk**, after
  the pages are written — not from the plan. A second calculation is a second
  thing to get wrong.
- **Write the index inside whatever your undo records.** Ours goes into the
  same change object as the pages, so "Undo that" takes the landing page back
  with them. An undo that restores the lessons and leaves the front page
  pointing at the wrong one is a worse state than either of the two it was
  between.

A section with no dated visible class is left alone rather than pointed
somewhere arbitrary.

#### The road not taken: do NOT do this at build time

The obvious extension is to have the site builder repoint the index, which
would also cover a teacher who edits `publish:` by hand in Obsidian rather
than asking the assistant. **Considered and rejected, deliberately.**

It breaks the contract the whole toolchain rests on: **what is in the vault is
what gets published.** The builder works on a merged COPY, so it would not
rewrite the teacher's files — which sounds like it escapes the objection, and
is actually worse. The published site would then show a page the vault does
not contain, and the teacher would have no way to find where it came from:
they would read their own `index.md`, see it pointing at Unit 4, Day 12, look
at the live site showing Unit 4, Day 19, and have nothing to blame.

So the automation fires only where a teacher can see it fire: when the
assistant changes a class's visibility. Editing frontmatter by hand leaves the
index exactly as written, which is the correct behaviour for a tool whose
promise is that the vault is the truth. **This is a live constraint, not a
historical note** — the same argument applies to any future "the builder could
just fix it up" idea, and there will be more of them.

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

## Problem reports: what a teacher sends back when something breaks (entry 212)

Windows has **no logging of any kind** today — no `ILogger`, no
`Debug.WriteLine`, nothing. This is a from-zero build on that side, and the
design below is worth copying rather than re-deriving, because most of it is
decisions rather than code.

### The problem it solves

A teacher on a released build hits something and emails you. By then the sheet
that showed the output is closed, the app may have been restarted, and the
transcript — which is the entire diagnostic, because almost every real failure
happens BELOW the GUI, in the launchers, the Python, Docker or wrangler — is
gone. The app is a driver; its own state is rarely the interesting part.

### The decision that shapes everything else: automatic, not opt-in

Records are written as every task finishes, whether it succeeded or not. The
tempting alternative — a "turn on detailed logging, then reproduce it" switch —
was rejected outright, and it is worth knowing why, because it will be proposed
again:

- **The bugs that matter here do not reproduce on request.** Colima or WSL2
  state, a port collision, a Cloudflare 429 at 11pm, a stale `.toolchain`. By
  the time a teacher can be asked to turn something on, the conditions have
  moved.
- **A teacher reports a problem after it happened.** Retroactive is the whole
  feature. A switch means the first occurrence is always lost.
- **Nothing is transmitted either way.** Writing to disk is not sending. The
  privacy control is the report step, which is explicit, manual, and shows the
  teacher a file they can read first.

Bounded rather than switched off: **newest 20 task records**, 250,000
characters each (trimmed from the FRONT — a failure is at the end), and the
assistant's own file trimmed to its last 400 lines when it passes 800.

### Redaction is on the WAY IN, and this is the load-bearing decision

Every byte is redacted as the file is written, never as it is sent. Two
reasons, both of which have to survive review:

1. **A report that is only safe when it leaves by the right button leaks the
   first time somebody opens the folder it sits in** — a support person on a
   screen-share, a backup, a synced Documents folder.
2. **It is what makes the file inspectable.** The privacy promise a teacher
   can actually check is not a sentence in a dialog; it is being able to open
   the thing and read it. That only works if what is on disk is already safe.

There is deliberately **no way to switch redaction off for a development
build**. A redactor that is off while it is being worked on is a redactor
nobody has run. It costs nothing: `/Users/person/Documents/Teaching` reads
perfectly well while you are debugging.

### Take the rules from the contract, do not re-derive them

`problemReportRedaction` in [`contracts/shared-rules.json`](contracts/shared-rules.json)
— 14 cases, `input` → `expect`, run by `SharedRulesContractTests` on the mac
and ready for an xUnit `[Theory]`. It also carries `placeholders` (the exact
phrases left behind) and `secretLength`, so nothing has to be copied out of
prose. The mac implements the **Windows** `C:\Users\…` form as well as its own,
on purpose: one case list, identical on both sides, and neither platform has a
rule the other's tests cannot reach.

**Half the cases are things that must NOT be redacted, and they are the half
that gets broken.** A redactor tuned only for what to remove will happily
swallow the image tag, the container name, the `.pages.dev` address and 40-char
git SHAs — and then produce reports that cannot answer the first question
anybody asks of them. The one hex exception is worth stating plainly: a
40-character run that is entirely lowercase hex is a git commit or SHA-1, not a
token, and a real token being all-hex by chance is about a 1-in-10^24 event.

### What each record carries, and why

| Field | Why it is there |
|---|---|
| App version, build, **bundle path, process id** | Not decoration. Two copies of the app can run at once (on the mac, Xcode's Run does not stop a copy it did not start), and when they do they take turns rewriting the same working folder. Two process ids in one folder of records is the fastest way that has ever existed to SEE that. The bundle path answers "am I testing my edit or the old copy?" — the trap that costs the most time in this repository. |
| OS version, OS build, kernel version, architecture, cores, RAM | The assistant runs natively on one architecture and not the other, and the whole toolchain emulates on the wrong one. Exact OS build number (e.g. `25G72` on macOS, `Build 22631.3880` on Windows) and kernel release isolate virtualization, Metal/DirectML, and platform bugs. |
| Helpers (assistant engine & toolchain tools) | Assistant flags and chat template handling depend on the engine build (`llama.cpp b10435`). Helper software versions (Colima, Lima, Docker CLI, Buildx on macOS; WSL2, Docker, .NET runtime, WebView2 runtime on Windows) isolate whether the host is running on expected dependencies. Also emitted as a launch trail event (`helpers described`). |
| Launcher name and arguments | What was actually asked for, as against what the teacher believes they asked for. |
| Outcome | **Stopped on purpose** and **Backed out of a question** are distinguished from **Failed**. Both exit non-zero and neither is a bug; recording them as failures sends somebody hunting a teacher who changed their mind. |
| The failure explanation, INCLUDING when there is none | `FailureExplainer`'s silence is the interesting case — an unrecognised failure is the one worth a person's attention, so the record says "nothing recognised" rather than omitting the line. |
| The whole transcript | The diagnostic. |

Records are named with a sortable timestamp (`2026-08-16-142733-deploy.txt`),
so "keep the newest twenty" is dropping from one end of a name-sorted list —
no file dates involved, and therefore nothing a copy or a restore can disturb.

### A record exists from the START of a task, not only at the end

Written at the end only, this feature had a hole exactly where it was needed
most. **A preview never finishes** — it serves until the teacher stops it — so
"my preview is stuck" and "the site won't load", the likeliest things anybody
reports, were the two cases that left no trace at all. Reported from the real
app within an hour of it being built, by doing nothing more unusual than
building a preview and then asking for a report.

So: the record is written the moment the task starts (outcome **Still
running**), refreshed while it runs, and finalised when it ends. Three details
worth copying:

- **Throttling on output is NOT enough on its own, and this cost a debugging
  session to learn.** The first version refreshed the record whenever output
  arrived, no more than once every 10 seconds. It never once fired. A preview
  with a warm container prints for about **five seconds** and then serves in
  silence for as long as the teacher leaves it open — so output stopped before
  the throttle expired, every refresh declined, and the record kept its opening
  lines and nothing else. Measured from the real app: **19 flushes inside 5.2
  seconds, zero refreshes, a 466-byte record of a preview that had just built a
  whole site.** Reasoning about the code did not find this; instrumenting it and
  reading the log did.
- **So there are two triggers, and you need both.** A 10-second throttle is the
  ceiling for a CHATTY task (one printing steadily for an hour is never more
  than 10 seconds behind), and a **2-second debounce after output goes QUIET**
  catches the tail — which, for anything that ends by going quiet rather than by
  exiting, is the whole record. The invariant to pin in a test: the quiet wait
  must be SHORTER than the throttle, or you have rebuilt the original bug.
- **The file is named after the task's START**, so a refresh replaces the same
  file instead of filling the folder with one record per flush.
- **"Still running" is not a failure**, so it gets no explanation line — see
  the note about stopped tasks above; this is the same trap in another coat.

### The breadcrumb trail — one file, in order

Task records answer "what did that publish print?". They do not answer the
question support actually opens with: **what were you doing when it went
wrong?** A teacher who says "it stopped working after I renamed something" is
describing a sequence, and a pile of records is not one.

`activity.txt` is that sequence — one line per thing the teacher would
recognise as something they did:

```
2026-08-16 15:05:30 · Plantoir opened — Plantoir 1.0 (1) · pid 98183 · /Users/person/…
2026-08-16 15:05:30 · running on macOS 26.6.0 · arm64 · 12 cores · 48 GB
2026-08-16 15:06:02 · opened the working folder /Users/person/Desktop/…
2026-08-16 15:06:31 · started preview.sh COMP 1 --port 8081
2026-08-16 15:07:04 · COMP/1 · opened the assistant (the larger assistant)
2026-08-16 15:07:19 · COMP/1 · the assistant was ready after 14.8s
```

- **ONE file, not one per subject.** The assistant's turns go in here too. Two
  files each holding half a story force whoever reads them to interleave by
  timestamp in their head, and they will get it wrong.
- **Deliberately coarse.** Every line is something the teacher would recognise
  as an action — opening a folder, saving settings, starting a task, the
  assistant answering. Not view redraws, not state changes. The failure mode
  of logging everything is that the one line that mattered is on page forty.
- **Each launch opens with the app version, pid and BUNDLE PATH.** A trail
  spanning several launches then says where each began, and the first
  disagreement between a report and the code is answered without asking.
**The standing requirement — this is the part that outlives the feature.**
Every new feature, and every CHANGED behaviour, that a teacher can see leaves a
line here. On both sides. It is written as CONTRACT DATA rather than as advice,
because advice in a handoff gets read once:

- `contracts/shared-rules.json` → `activityTrail.mustRecord` lists every event
  both apps must record, with what it carries and why. `promptMarker` and
  `lineShape` are there too.
- A test pins that list against the app's own event list
  (`ActivityTrail.Event` on the mac). **Add an event to the contract and the
  mac suite goes red until the mac records it** — which, per the direction rule
  in `CLAUDE.md`, is exactly how Windows proposes one. Say so in
  `MAC-HANDOFF.md` and the red suite reads as a request rather than as damage.
- Name the event; do not write free text at a call site. Naming it is what
  forces the author of a feature to decide what it leaves behind, and what lets
  a test notice when they did not.
- **A changed behaviour changes its line too.** A trail line describing what
  the feature used to do is worse than none, because it will be believed.

- Capped at 1,200 lines, trimmed to the newest 600 — trimmed to HALF rather
  than to the cap, or the file would be rewritten on every single line once it
  filled up.

### The assistant's record is part of the trail, for a reason of its own

**Routing has no automated gate anywhere in this product** — whether the model
still picks the right tool is measured by hand against a local engine, and once
the app is on a teacher's machine nothing measures it at all. One line per turn
is the only trace a routing mistake in the field ever leaves:

```
2026-08-16 07:06:40 · ICS3U/1 · chose publish_pages(course, section, titles) · 2.1s · 44 tokens · waited for the button
  asked: publish tomorrow's class
```

- **Argument NAMES, never values.** Which tool, with which arguments filled in,
  answers the routing question completely. The values are the teacher's page
  titles.
- **The token count is in there deliberately.** This is the number that would
  have caught the thinking-flags bug in days rather than weeks: llama.cpp parses
  the `<think>` block OUT of `message.content`, so an answer with thinking back
  on looks perfectly clean and is merely slow. 44 tokens against 512, same
  question. On Windows, read `usage.completion_tokens` off the chat-completions
  response the same way — the mac added `AssistModelClient.reply(…)` returning
  an `AssistReply` beside the existing `respond(…)` rather than changing the
  return type, which kept the change to about fifteen lines.
- **The teacher's sentence is written locally and left OUT of the report unless
  they tick the box.** Both halves are needed: a routing problem cannot be
  looked into without the sentence that caused it, and the sentence must
  already exist by the time they report the problem — but their own words are
  the one thing in the report that is unmistakably theirs to hand over or not.
  The line is written with a fixed prefix (`  asked: `) so that leaving it out
  is dropping lines by prefix rather than parsing anything.

### Ask only what there is to ask

The checkbox about the teacher's own sentences appears **only when the trail
actually holds any** — and the test is the presence of PROMPT lines, not of
assistant events, because opening the assistant and closing it again leaves
turns behind but nothing they typed.

The report's note has three states to match, and they are three different
things to be told: never used it (say nothing about the assistant at all),
used it and kept it back, used it and sent it. A teacher who has never opened
the assistant must not read a line promising that what they typed to it was
withheld — it invites them to wonder what else the app believes they did,
which is the opposite of what a dialog asking for their trust should do.

Both, plus the exact label and the support address, are contract data:
`shared-rules.json` → `problemReportDialog`.

**Say "the local AI assistant" in full.** Plantoir will grow ways to connect a
teacher's own account to a hosted assistant, and from that day an unqualified
"the assistant" is a question about the wrong thing — answered wrongly, about
where their words have been. Three characters now against a rewording that
would otherwise have to reach both apps at once.

### Record at the moment it HAPPENS, never at the moment it succeeds

The generalisation of a bug reported from the real app, and worth more than
the bug: what the teacher typed to the local AI assistant was written to the
trail only when the model REPLIED. Everything short of a completed answer —
an engine error, a reply still running, the window closed mid-thought — left
no record of the sentence at all. And because the report's checkbox keys off
those lines, it stayed hidden from somebody who had plainly just used the
assistant.

The sentence is now recorded when the message is SENT. **Anything recorded on
the success path is missing from exactly the sessions somebody asks for a
report about**, which inverts the whole point of keeping records.

**It bit a second time, one branch higher, and the second one is the sharper
lesson.** Moving the write to "as the message goes to the model" still missed
every phrasing matched in code — those return from `say()` early and never
reach the model — so an entire class of teacher input left no trace, and the
report's checkbox again hid itself from somebody who had plainly just used the
assistant. Both bugs were reported as "the conditional is broken"; neither was.

So the rule, in the form that survives both: **record what the teacher did
where they did it — above every branch, never at a later point that a branch
can skip.** In practice that means immediately after the input is accepted and
before anything decides what to do with it. And when a branch means the model
was never consulted, say SO on the trail: "why did it not think about what I
said?" has no other answer.

Worth copying too: the two regression tests drive the send path end to end and
were confirmed to FAIL against the old placement before being kept. A test
written after a fix that passes either way is the reason a bug gets reported
three times.

### The teacher-facing half

**Help ▸ Report a Problem…** → a dialog saying what is and is not included,
with one unticked checkbox ("Include what I typed to the assistant") → a save
panel defaulting to the Desktop → a zip, revealed in the file manager. Inside:
`what is in this report.txt` (an IN / NOT IN list, written for the teacher who
is deciding whether to send it), `what you were doing.txt` — the trail, and
the file to read first — and a `tasks/`
folder.

Rule 1 applies here more than anywhere, and it is where it slips: a teacher
being asked to send something is exactly the moment somebody writes "log file"
or "transcript". A mac test asserts that neither those nor "toolchain",
"script", "Docker" or "container" appear in what the teacher reads. **Write
that test on your side too** — the wording is yours, the rule is shared.

Plain text and a plain zip, never a bundle format of our own: a teacher who
cannot open the thing cannot decide whether to send it.

**Three things only driving the real app caught**, all of them in what the
teacher reads — every one passed the unit suite:

- **The emptiness check must come BEFORE the question.** Asking somebody what
  to include, taking them through a save panel, and only then telling them
  there was nothing to send is a small rudeness that costs nothing to avoid.
- **A task stopped on purpose is not a failure and must not be explained.**
  It exits non-zero like a failure does, so the record said "Explained:
  nothing recognised — worth a look" about a preview the teacher had simply
  ended. Keep "was this a failure" as its own recorded fact rather than
  reading the word "Failed" back out of the outcome sentence — that test
  passes until somebody rewords the sentence.
- **Page NAMES are in the report, and the note has to say so.** The first
  wording promised that nothing from the teacher's pages was included; a real
  preview transcript then turned out to list every page the builder emitted
  (`ContentPage -> public/All-Classes/Unit-3,-Day-17.html`). A promise a
  teacher can check and find false is worse than no promise, so the note now
  says the names appear and only what is WRITTEN on them does not.

### Rejected on the mac, and why

- **`log collect` / a `.logarchive` as the support path.** Rejected outright.
  It exports the WHOLE system's unified log — every application's activity,
  network names, URLs — which is a far worse privacy outcome than anything the
  feature was built to avoid. The Windows equivalent temptation is a full Event
  Log export or a `sysdiagnose`-style dump; refuse it for the same reason. OS
  logging stays useful for development and is not what you ask a released user
  for.
- **Recording file CONTENTS on a write.** Course notes are the teacher's work
  and are the one place a student's name could plausibly appear (a class-list
  page). Paths yes, redacted; bodies never. The mac's undo history holds
  before/after copies of whole files and that stays in memory.
- **Redacting the account identifier by SHAPE.** A 32-character hex run is also
  every BLAKE3 and MD5 digest in deploy output. It is removed only in its
  labelled forms (`--account …`, `Account ID: …`), which is where it actually
  appears.

## More to ask for, and the rules under it (entries 233–243)

A run of work on what a teacher can ask the assistant. The commands are the
visible half; the rules under them are what a port gets wrong.

### Commands added

| Phrasing | Tool | Notes |
|---|---|---|
| `Publish Monday's class` … `Sunday's` | `publish_class_on` | Seven fixed shapes; the day resolves in code. |
| `Publish Unit 5` / `Unpublish Unit 4` | `publish_pages` / `unpublish_pages` | A whole unit, one class at a time. |
| `Add five more days to Unit 4` | `add_next_class` | Words or digits. |
| `Start a new unit for the next class` | `add_next_class` | Day starts again at 1. |
| `Duplicate Unit 3, Day 2 as my next class` | `add_next_class` | Shifts later classes when room is needed. |
| `What dates am I teaching?` / `Show me the rest of the dates` | `read_remembered_timetable` | Week first, then the offer. |

All are matched in CODE. Four of them cannot be listed as literals because the
number or title in them is unbounded, so `assist-cases.json` → `cardPhrasings`
now has a **`parsed`** array beside `matches`: each family gives its shape, the
tool, the argument keys it fills, an example, and — the half that matters — a
`notThis` near-miss it must REFUSE. "Publish Unit 4, Day 3" has a comma, is one
page, and belongs to the model. Without the refusals a family swallows requests
that were never its own.

### A whole unit, one class at a time

Unpublish walks the highest day backwards; publish walks Day 1 forwards. The
per-day rules are the ordinary ones, so each step asks "what else still needs
this page?" against the state as it actually is at that moment. Publishing
forwards is also what makes an earlier class claim a shared page's date.

Three things that are easy to get wrong and cheap to get right:

- **Stop the preview ONCE**, not per page. Twenty pages is one act to a teacher.
- **One undo entry**, merged from every file touched — keeping the EARLIEST
  before and the LATEST after for a file written more than once, or undo puts a
  page back the way it was one step ago rather than before the unit was touched.
- **One sentence back**: "Unit 4 was unpublished."

### Duplicating reuses the insertion planner

`Duplicate Unit 3, Day 2 as my next class` makes Unit 3, Day 3 with the
source's content and a date of its own. Making room is the existing insertion
machinery's job rather than a second copy of it: it renames **highest day
first** so nothing is written over, re-dates onto real meeting days, and
rewrites every wikilink pointing at a renamed page. When nothing needs moving
it simply appends.

The copy starts **hidden however the source was** — a duplicate of a published
lesson is a draft of next week's. And it is **undoable only when nothing else
moved**: a partial undo that deleted the new page and left every later class
renamed is worse than no undo, so when classes shuffled the answer points at
the backup instead.

### Following links, in both directions (`shared-rules.json` → `followingLinks`)

**Publishing** takes what it links to, transitively, and the plan names every
page that will become visible.

**Unpublishing** takes a linked page only when nothing else needs it — and "X
still links to it" now counts **only when students can see X**. Counting hidden
referrers left pages visible and reachable from nothing, held up by drafts
nobody had published. Safe in one direction because of the other: publishing is
transitive, so a page taken down comes back the moment anything visible needs it.

**Four kinds are never taken down by following links**, and they are checked
BEFORE the referrer test: a page Key Links points at (and Key Links itself), a
folder's landing page (which is All Classes and every sidebar folder), and
anything with a folder segment containing "curriculum".

> **The order is load-bearing.** Narrowing a sweep rule makes every exclusion
> above it matter more than it did the day before. The exclusions are the thing
> to re-test after any change to what gets swept, and there is now a test that
> sets up exactly the situation the narrowing created — the only page linking to
> each of the four is HIDDEN — confirmed to fail with the exclusions removed.

### Confirmation is a setting now (`shared-rules.json` → `assistantConfirmation`)

"Ask me before changing anything", in Settings, **on by default**. Deploying
always asks regardless — it puts work in front of students and cannot be taken
back.

**Both assistants follow identical rules.** The smaller one used to refuse to be
turned off and was never told the setting existed, on the measured reasoning
that one request in five going wrong is not a rate at which anybody should stop
reading. That withheld a setting from exactly the machine where knowing about it
matters most. The measured number is put in front of the teacher as a caution
instead.

**Discoverability:** after **15** plans agreed to — app-wide, across every
conversation and course — the assistant says once, and only once, that the
setting exists. The old count was five, per conversation, reset by a Cancel, so
a teacher working in short bursts could accept a hundred plans and never be
told. A Cancel no longer resets it either: the number measures how much of the
assistant's work this teacher has READ.

**One stored answer**, read fresh each turn. The settings window and the
assistant are open at the same time.

> A mac test caught the trap here: two settings OBJECTS over one defaults store
> are not the same as one object — each caches what it read at construction, so
> a change through one was invisible to the other. It would have worked in the
> app by luck, because both would have been the shared instance.

### Smaller things worth copying

- **`check_section` says three different things about the preview**, decided by
  a three-way state rather than an "is it running" boolean: building → say when
  the pages will appear; showing → say nothing; neither → offer a preview. The
  boolean stays true while the site is SERVED, so a teacher looking at a
  finished preview was told to wait for a rebuild that had ended minutes ago.
  The honest signal for "on screen" is the loaded URL, not the process.
- **"It's already been published."** Asking to publish something already
  published gets four words, on the plan path too — otherwise plan mode asks a
  teacher to approve a no-op and then reports that nothing happened. The plan
  remembers which pages were NAMED, separately from everything links swept in,
  or "it" counts pages nobody mentioned and comes out plural.

## Starting a new unit, and asking for the schedule (entries 231–232)

### "Start a new unit for the next class"

Which unit a class belongs to is the one judgement `NextClassPlanner`
deliberately refuses to make for a teacher, so it is now asked for outright.
The command reuses that planner whole; only the NUMBER changes.

**Day starts again at 1.** Every course here numbers days within their unit —
ADA1O runs Unit 1, Day 1…18 and then Unit 2, Day 1 — so a new unit begins at
Day 1 however far the previous one ran. It does not continue the old count.

**Unpublished pages still count.** A teacher with Unit 4, Day 12 published and
Days 13 and 14 written but hidden gets **Unit 5, Day 1**, dated to the next
timetable date with no class against it. Publication state has nothing to do
with where the next class goes: that is decided by how many pages exist, which
is the same rule the DATE has always used — count the class pages, take that
many dates into the timetable. Three units of five days are fifteen classes
whatever they are called.

Everything else was already right and is untouched: the page is written by
`PlaceholderClassPlanner.apply`, which starts it `publish: false`, refuses to
write over an existing page, and checks that twice because the teacher has
Obsidian open in the other window.

`unit` is not in the tool's schema — the fixed phrasing passes it, the model
never sees it, and the routing surface is unchanged. Same trick as `when` and
`scope`.

### Every command that needs the schedule now asks for it

The sheet that collects a section's class dates already existed, and was wired
to exactly **two** paths: adding a class, and reading the timetable back. Every
other request that depended on the schedule failed with an explanation and no
way forward.

Publishing a class by day is the one that exposed it. "I can't find a class on
Saturday" is a perfectly good sentence and completely useless to a teacher who
has never given their dates — the thing they need is not a better sentence, it
is the question nobody asked them. All prompting now goes through one
`askForTheTimetable`, and the class-by-day path calls it when, and only when,
no dates are on file.

**Test both directions.** The second test matters as much as the first: it
must NOT prompt when a timetable IS recorded, because then the request failed
for some other reason and a sheet about dates is answering a question nobody
asked. Go through your own tool list and ask, for each one, "what does this do
when the schedule is missing?" — the answer should never be an explanation on
its own.

## The assistant sounds like a person, not a report generator (entries 227–229)

Three changes to how answers READ. None of them changes what the assistant
does, and all three apply to `Plantoir.Core/Assist` unchanged.

### One sentence per page, and no Markdown at all

A plan used to read:

```
2 pages would change:
Unit 4, Day 24  —  publish: hidden → visible
Bananas  —  publishForSection1: hidden → visible  (linked from a page you named)
```

and now reads:

```
2 pages would change:
“Unit 4, Day 24” will become visible.
“Bananas” will become visible.
```

Four pieces of bookkeeping were wearing a page title: the frontmatter KEY the
change lands in, the state it came from, an arrow, and a parenthetical. All
four are true and none of them is how a person says it — `publishForSection1`
especially, which is the name of a line in a file being shown to somebody who
asked to hide a lesson. The pages that stay got the same treatment
(`“Journal Checklist” stays visible, because “Portfolios” still links to it.`).

**Then a second pass went further, and it is the more instructive one.** The
dates a class hands its pages were being reported in a LIST OF THEIR OWN,
under the heading "1 page students have not seen before will take this class's
date", with the page named again and both dates spelled out. Every fact in it
was true and the whole block was too much: a teacher had to hold a page name in
their head across two lists and a blank line to work out that the second was
about the first. It is now a clause on the line that page already has:

```
2 pages would change:
“Unit 4, Day 24” will become visible.
“Bananas” will become visible, with the same date as “Unit 4, Day 24”.
```

No raw dates at all. "The same date as Unit 4, Day 24" is what the teacher
wanted to know; `2026-09-08 → 2027-01-19` is how the app stores it. The rule
worth carrying: **one line per page, and a second fact about a page belongs on
that page's line, not in a second list keyed by name.** `AssistPublishDateMove`
carries `takenFrom` — the class it took the date from — purely so the sentence
can name it.

**No bold, and no Markdown anywhere in what the app writes.** The four headings
were the only `**` any assistant string emitted. The reasoning that put them
there is still true — a plan is scanned for "how much is about to change"
before it is read — but this is a chat, and **a person answering a question does
not reach for typography to make a sentence land.** A heading ending in a colon
with its count as the first word is signal enough. The bubble still PARSES
Markdown, so a model's own reply renders normally.

One bug to check for on your side, because it is the kind that survives review:
`1 page students is seeing for the first time`. A verb had been agreed with the
page COUNT while its actual subject was "students", who are always plural.
Rephrasing removed the trap rather than fixing the one instance.

### "Publish Monday's class"

The card was "Publish the class on Monday". It now reads the way a teacher
says it, and **all seven weekdays are fixed phrasings** — `publish monday's
class` through `publish sunday's class` — so the date is resolved in code and
can never be one the model invented.

`day(named:today:)` learned weekday names: the next occurrence, **counting
today when today is a Monday**, because asked on a Monday for "Monday's class"
a teacher means the class they are about to teach. Forwards only, within seven
days; somebody who means a class already taught has its Unit and Day in front
of them and will say so.

Same shape as the `publish tomorrow's class` card that was already there, and
the same trick: the argument key is `when`, which is **deliberately not in the
tool's schema**. A fixed phrasing may pass keys the model never sees, which is
how a whole behaviour is added without touching the surface routing was
measured against.

The schedule check and the "no class that day" stop already existed. Its
WORDING did not survive reading: it said "Use list_pages to see what classes
there are" — a tool name in a sentence that goes **straight to the teacher**,
because a refusal ends the turn instead of going back to the model. Check every
refusal on your side for the same thing; `noSuchPage` and `openEndedPublish`
still name tools and arguments over here and are worth the same pass.

### "What dates am I teaching?" answers with the week

It used to carry **no dates at all** — a count and two endpoints — so a teacher
asking what they were teaching was told how many days there were and left to go
and look. It now lists the dates falling in the next seven days, one per line
with its weekday, then what the dates are FOR, then an offer of the rest. A
quiet week says "Nothing in the next seven days" rather than printing an empty
heading.

**The offer had to be made answerable, and this is the part to copy.** A prompt
whose answer nothing understands is worse than no prompt. "Show me the rest of
the dates" is matched in code and passes `scope: all` — again a key the schema
does not mention — and a test asserts that the words the answer OFFERS are
words the matcher accepts. Wire that assertion up too: it is the one that stops
a friendly-sounding sentence from being a dead end.

## Dating the pages a class brings with it (entry 226)

The date on a page is what ORDERS it on the site, so a page written weeks early
carried the day its FILE was made — a fact about the teacher's evening, not
about the course. Publishing a class now dates the pages it brings.

**A linked page takes the class's date when both hold:**

1. it is **hidden right now**, so this publish is the first time students will
   see it; and
2. it is **not itself a class page** — a class's date is its position in the
   schedule, and nothing may move it.

A page students can already see keeps its date. It has a place on the site
somebody may have linked to or looked at, and republishing a class must not
shuffle work that was already out.

The key is `created` for a page in the section's own folder and
`createdSection<N>` for a course-level page shared between sections. Writing
the wrong one dates the page for a section the teacher was not talking about.

### The split this exposed, which is the thing to check on your side

`publish_class_on` worked date moves out. `publish_pages` — naming the very
same class page — passed an **empty list**, so it moved nothing. Same teacher,
same class, two different results depending on which sentence they used, and
the by-name route is the one behind the commonest card on the shelf.

Both now call one function. If your side has two code paths into publishing,
that is where to look first; a rule implemented on one route and not the other
is invisible until somebody phrases a request the other way.

### One condition was removed, and it will look like a regression

The rule used to move a page only when no OTHER class linked to it, reasoned as
"a concept page linked from three different lessons belongs to none of them and
is left exactly where it is."

That reasoning is sound for a page already on the site and **beside the point
for one nobody can reach**. A hidden page has no place to be left in — it has
only the day its file was made. Given the choice between "the day this material
first appears" and "the day somebody happened to type it", the first is what a
reader wants, even when three classes share it. So a shared page students have
never seen now moves; a shared page they HAVE seen does not, which is where the
old reasoning still lives.

Where several classes being published in one go share a page, the **earliest**
claims it, ties broken by page title so folder order cannot change the answer.
That is not a new invention: `first_use_dates` in `setup_course.py` already
dates a shared page to the first class that references it, so a pre-populated
course and a hand-published one agree.

### "Never published" is inferred, and you should infer it the same way

Nothing on disk records a page's history, so "never published" means "hidden at
the moment the publish is planned". A page published once and later hidden
therefore counts as never published and would take a new date. Recording the
truth would mean a new frontmatter key on every page, agreed between both apps
and the Python — considered and rejected as costing more than the case is worth.
If you ever need it to be exact, that is the decision to reopen, and it has to
be reopened on both sides at once.

Contract: `class-planning.json` → `datingPagesAClassBrings`, with the
conditions, the key names, the earliest-class rule and the reasoning. Two mac
tests run it; deserialise rather than retyping.

### Non-class pages inherit the date of the first class of the year (Unit 1, Day 1)

Pages that serve the course as a whole — sidebar landing pages (`index.md`),
folder index files (`All Classes/index.md`, `Concepts/index.md`, etc.),
`Key Links.md`, standalone reference or policy pages listed in Key Links but not
linked from any lesson, and Curriculum expectations pages not transcluded in a
lesson — are **non-class pages**.

Previously, curriculum pages synced to the section's latest date during build,
while other non-class pages retained whatever date was generated at course
creation time or file creation time.

Now, all non-class pages inherit the date of the first class of the year
(`Unit 1, Day 1`):
1. **During preview and deploy (`scripts/build_site.py`)**:
   `_sync_non_class_pages_created` scans `content_root`, finds `Unit 1, Day 1`'s
   date (or the earliest class date in the section), performs a BFS traversal
   from all class pages following wikilinks transitively to find all reachable
   content pages, and sets `created:` to the `Unit 1, Day 1` timestamp for all
   remaining non-class pages (excluding the root section landing page
   `content/index.md`, which carries the date of its newest published class).
2. **During course setup (`scripts/setup_course.py`)**:
   `install_example_content` sets `first_class_date` as the default for all
   non-class pages so that new courses created from skeletons or payloads carry
   this date from the start.

Because this logic is implemented in the shared Python scripts
(`scripts/build_site.py` and `scripts/setup_course.py`), the Windows app inherits
the behaviour automatically.

Contract: `contracts/class-planning.json` → `datingNonClassPages`.

## Undo: what it SAYS, what it does to the preview, and what it can take back (entries 221–223)

Three faults, all reported from one real session — "Unpublish Unit 4, Day 23"
followed by "Undo that" — and all three apply to `Plantoir.Core/Assist`.

### A stored clause is not a sentence

The answer read:

> Undid unpublished 2 pages in ADA1O Section 1.

A change stored a past-tense clause and the undo pushed it into `"Undid \(…)."`.
Three things wrong at once, and they are worth separating because each has its
own lesson:

1. **Ungrammatical**, because a clause was dropped into a slot that wanted a
   noun. The fix is not to reword the slot: it is that a clause should only
   ever appear inside a sentence somebody wrote on purpose. `AssistWording`
   now owns whole sentences with a subject and a verb, and the clause is a
   parameter — `undid(_:)` → "Earlier, you unpublished Unit 4, Day 23. Then
   you asked me to undo that, and I have done so."
2. **It counted files.** Hiding ONE class writes TWO files, because the
   section's landing page is repointed inside the same change, so "2 pages"
   was arithmetically right and unrecognisable to somebody who had asked about
   Unit 4, Day 23. A change now names the pages whose visibility moved while
   there are few enough to name, and falls back to a count at three or more.
   The repointed index is bookkeeping, not what was asked for.
3. **One slot served success AND refusal.** When every file had been edited
   since, nothing went back at all — and the code fell through to the same
   "Undid …" sentence. A teacher was told their change had been taken back
   while not one file had moved. There are now three distinct sentences: all
   back, partly back, nothing back.

Seven entries in `assist-wording.json`, carrying a `{change}` placeholder.
Deserialise them; do not concatenate at the call site.

One more: `nothingToUndo` used to say "I have not changed anything in this
conversation yet", which was false after remembering a timetable (writes a
course's settings, touches no page, deliberately not undoable). It now says "I
have not changed any **pages**". Narrowing a claim is usually cheaper than
widening the feature.

### The preview has to come down, and it has to come down FIRST

The undo wrote the files and stopped there, so a teacher watching a preview
saw it go on serving the state they had just asked to leave. The order is
**stop → wait for the stop → write → start**, which is the order
`publish_pages` already used, and the wait is the load-bearing part: stopping
reaches into the container and kills that section's processes, so a stop still
finishing when the next build begins kills the build too, and what gets served
is the site as it was before.

It could not be done at all before, for a structural reason worth checking on
your side: **a change knew only its FILES**, so an undo had no way to say which
section's preview to touch. A change now carries its course code and section
number.

It also carries `rebuildsThePreview`, set to whatever the change ITSELF did.
Publishing and hiding rebuild, so their undo rebuilds. Creating a class page
does not — it arrives unpublished, so nothing the preview shows changes — and
neither does taking it away. A blanket rebuild would make "undo that" the
slowest thing in the window for the one change needing it least.

**Test the ORDER, not the presence.** All four events can fire and still be
wrong. The mac fake records `[stop-begins, stop-ends, write, start]` with a
real suspension inside the stop, so "called the stop" and "waited for the stop"
are distinguishable.

### Taking back a page that was CREATED

"Undo that" after adding a class page answered that the conversation had
changed nothing, while the page sat in the teacher's folder. The undo list
holds a before-and-after copy of each file and a created page has no "before",
so nothing was recorded.

`AssistSavedFile.before` is now **optional, and nil means the change created
the file** — taking it back deletes it. Optional rather than an empty string on
purpose: an empty page and an absent one are different states, and a change
that created a page and left it empty must still be undone by deleting it.

The skip rule needed no change and is worth understanding rather than copying
blindly: the undo compares what is on disk now against what the change LEFT. A
page the teacher has since written in does not match, so it is skipped — their
work is safe. A page the teacher deleted themselves reads back as absent, also
does not match, and is skipped rather than "restored" by deleting something
already gone.

The line telling teachers `"Undo that" does not take away a page it created`
was corrected in the same change. A line describing what a feature used to do
is worse than no line, because it is believed.

## The shelf is a promise, and promises are measured (entry 224)

The list of phrasings the assistant window offers went from nine to twelve.
Five capabilities were on no card at all — listing a section's pages, reading
one back, publishing the class on a named day, adding the next class page, and
reading back the remembered class dates — so they existed and no teacher was
told. **Three of the five stayed; two were measured, passed, and were removed
anyway.** Both halves matter, and the second is the one a port gets wrong:

- **Added:** publish the class on a named day, add the next class page, read
  back the remembered class dates.
- **Measured 10/10 and still removed:** "What pages are in this section?" and
  "Show me Unit 2, Day 3". Not a routing problem — a teacher has the pages in
  front of them in Obsidian and in the app's own sidebar, so a chat bubble is a
  worse way to see a page than the two windows already open.

So a card has to pass TWO tests, and reliability is only the first. The second
is "is this worth asking for?", and it is what keeps the shelf a list of things
worth suggesting rather than an inventory of the tool surface. The surface is
thirteen tools; the shelf is twelve phrasings of a different set, and the gap is
deliberate. `list_pages` and `read_page` are still tools the model uses to look
things up before it acts — that is the job they are good for.

(`list_pages` also stays in the fixed-shape matcher for a teacher who types the
phrasing anyway. The shelf is what is worth SUGGESTING; the matcher is what is
worth MATCHING; they were never the same list.)

**Keep the shelf and the matcher testable against each other.** Over here
`AssistPromptShelfView.groups` is static and a test asserts every card either
fires a fixed phrasing or appears on a hand-written list of the model-routed
ones — so a new card fails the suite until somebody has decided which kind it
is. That is the drift worth guarding: a card whose wording no longer matches
its shortcut is a button that quietly goes to the model on a shape the model
was measured getting wrong, and it looks completely normal. Group TITLES stay
in a hand-written list, because reading those from the view would only make the
test agree with the view.

One more thing the audit turned up, worth copying as a habit: an offer made
only INSIDE an answer is invisible until you have already had that answer.
"Show me the rest of the dates" lived only in the timetable reply, so a teacher
who had never asked the question had no way to know it existed. It is on the
shelf now too.

The rule for adding one:

- **No arguments in the phrasing → match it in code.** It joins the fixed
  shapes, never reaches the model, and is reliable by construction. Seven of
  the twelve cards are in this group.
- **An argument in the phrasing (a page title, a day, a time) → it must go to
  the model, so measure it before offering it.** They are what
  `research/ai-assist/shelf-phrasings-results.txt` is evidence for: routing
  140/140, arguments 60/60, ten trials each, across the fourteen probed before
  two were dropped.

### The measurement trap, which is the useful half

The first run of that suite left `AssistAgent.dateline()` off the user message.
"Publish the class on Monday" routed correctly 10 times out of 10 and then
resolved Monday to a date **a month away**, also 10 out of 10 — because a model
with no idea what day it is has to invent one. The card was within an edit of
being dropped and replaced with a hard-coded calendar date.

The harness was wrong, not the product. `AssistAgent.say` appends "(Today is
2026-08-16, a Sunday.)" to every message, and with it the same phrasing
resolves exactly. **A probe that does not send what the app sends measures
nothing — and the number it produces reads exactly like a fault in the
product.** Check your own harness sends the dateline before believing any
date-shaped result.

(From the older `trimmed-surface-suite.py`: that line must be APPENDED to the
user message. Prepending the identical text cost 15 points of routing. The
position is the finding, so do not tidy it into the system prompt.)

## What a page is CALLED, which is not what its file is called (entry 220)

Reported from a real course. Unpublishing a class printed:

```
4 linked pages stay published:
Journal Checklist  —  “index” still links to it.
Final Reflection   —  “index” still links to it.
```

Every folder in a course has an `index.md`, so "index" names eleven pages and
none of them to a teacher. The page they would go and open is the one the
sidebar calls **Portfolios**. The whole purpose of the "stays published" list
is to send somebody to the page holding a link, and a name that matches every
folder sends them nowhere.

**This is not a mac-shaped bug.** `Plantoir.Core/Assist` reads the same
folders and builds the same page graph; check both halves below.

### Half one: a label is not an identity

A page now carries two names.

- **`title`** — the file name without `.md`. This is the IDENTITY. Wikilinks
  resolve by file name and every lookup in the page graph goes through it, so
  it must never be replaced by something nicer to read. A test asserts a link
  written `[[index]]` still finds the file called `index`.
- **`displayTitle`** — what a teacher sees it called, used everywhere a page is
  named in a sentence they read: the unpublish plan, the pages that stay, date
  moves, `read_page`, `check_section`, curriculum mentions.

The rule is **copied from Quartz's own `quartz/util/fileTrie.ts`** rather than
invented, so what the assistant says and what the site's sidebar shows cannot
drift:

```ts
const nonIndexTitle = this.data?.title === "index" ? undefined : this.data?.title
return displayNameOverride ?? nonIndexTitle ?? this.fileSegmentHint ?? this.slugSegment ?? ""
```

which is, for one page: the frontmatter `title:` **unless it is literally
"index"**, then the FOLDER's name, then the file name. The "unless it is
literally index" guard is Quartz's own and is worth keeping for Quartz's own
reason — it is the one answer never worth showing anybody. The middle step
earns its place even though frontmatter nearly always answers first: a page a
teacher wrote by hand in Obsidian carries no frontmatter title at all, and
without it every folder in the course is called "index" again.

If Quartz's rule ever changes, follow it rather than re-deriving one.

### Half two: fixing only the label makes the output WORSE

This is the part to read twice, because the obvious fix is half of it.

Referrers — "which page still links to this one" — were remembered as NAMES and
looked back up in the page graph. The graph keys pages by file name. Every
folder landing page is called `index`. So the lookup returned **whichever
`index.md` the folder walk happened to reach first**, which is very often not
the one holding the link.

While the answer printed as "index" that was invisible: wrong page, right word.
Print it as a folder name and it becomes a **confidently wrong** answer. In the
regression test, the label-only fix named **Concepts** — a folder that does not
link to the page at all. A teacher sent to Concepts to find a link that lives in
Portfolios concludes the assistant is lying and stops reading the list; "index"
merely told them nothing. Useless beats wrong.

The fix is to carry the PAGE rather than its name, and to de-duplicate
referrers by PATH rather than by name — the name-based de-duplication had its
own version of the same bug, throwing away the second folder index whenever two
of them linked to one page.

**The general rule for your side:** if you key referrers, backlinks, or any set
of pages by name anywhere, `index.md` collapses them all onto one key. Go
looking for that before you touch the label, not after.

### Testing it

New contract section `shared-rules.json` → `pageNaming`: the three-step rule,
five cases drawn from the shapes a real course contains, the word that must
never be shown, and the identity-vs-label rule. Deserialise it rather than
retyping the cases.

Both end-to-end tests on this side were CONFIRMED to fail against the old code
before being kept — one against the label, one against the lookup. Do the same:
a naming test that passes against the old code is testing nothing.

## Letting a teacher choose which assistant runs (entry 219)

Until now the model tier was decided for the teacher and never mentioned:
`AssistHardwareBudget` read physical memory, picked a rung, and that was the
whole conversation. That is still the right DEFAULT and it was a poor
only-option, for two reasons arriving from opposite directions. A teacher on a
16 GB Mac who also keeps a site building, a browser full of tabs and their
notes app open may want the smaller one back — the automatic choice sizes
itself to the machine, not to what else is on it. And a teacher on an 8 GB
machine who has just closed everything may want the better one for an
afternoon of planning. Neither is knowable from `sysctl`.

The mac now has **Plantoir ▸ Settings… (⌘,)** with one pane. Windows should
have the same thing wherever that platform keeps app settings.

### What the panel offers, and the reasoning behind each part

**Three choices, not two.** "Choose for me", "The smaller assistant", "The
larger assistant". Keeping an explicit automatic option is the part most worth
copying, and it is not about politeness:

> **The automatic choice is stored as an INTENT, never resolved and written
> down.** If selecting it wrote "the larger assistant" into preferences the day
> the teacher first opened the panel, then a later change to the ladder — the
> 8 GB reconsideration written up further down this file, say — would reach
> every machine EXCEPT the ones whose teacher had once opened Settings. That is
> exactly backwards: the people who engaged with the setting get the stalest
> behaviour. `AssistModelChoice.automatic` resolves at the point of use.

**Both costs, on every option.** Download size AND memory-while-working, e.g.
"1.12 GB to download, and about 1.75 GB of memory while you are using it."
They are different decisions — disk is what runs out on a small laptop, memory
is what makes the machine feel slow and never appears as a number anywhere —
and neither is guessable from the other: on the mac the larger download is
2.2x the smaller but 2.9x the memory, because most of the difference is the
conversation being held rather than the file being read. Derive both from your
tier table; do not type them into the interface, or they will drift the first
time a quant changes.

**No model is named, anywhere.** Rule one, and the settings panel is where a
name would most naturally leak in, because it is the one screen genuinely ABOUT
the model. `AssistantSettingsTests.testNothingInThePanelNamesAModel` sweeps
every label, detail, caution and summary the panel can produce against a jargon
list; write the equivalent.

**A caution, not a block.** A hand-picked rung whose resident size exceeds a
third of physical memory shows a warning naming BOTH numbers ("This Mac has
8 GB of memory, and the larger assistant needs about 5.04 GB while it is
working…") and stays selectable.

> **Rejected: greying it out with the reason beside it.** That was the obvious
> safe option and it is worse. A teacher who has just quit everything else
> knows something the operating system does not, and a disabled row gives them
> no way to act on what they know. The third-of-memory line is not new — it is
> the same one the automatic ladder has always been held to — which is why
> "Choose for me" can never produce a caution, and a test asserts that.

**Removing one is refused while an assistant window is open**, and the message
names the section to close ("Close the assistant for ICS3U Section 2 before
removing this.") rather than saying it is unavailable — the same shape the
sidebar already uses.

> The guard is deliberately about ANY open assistant, not about whether that
> window is using that particular rung. Working out which file is genuinely
> mapped means tracking state the app does not keep, and getting it wrong
> deletes weights out from under a running engine. One open assistant, no
> removals.

**Removing the one currently in use is allowed**, and the panel then says what
happens next. It is not a broken state — it is the state every machine is in
before its first download — and the alternative traps a teacher who wants their
disk space back behind a choice they did not want to change.

### Four traps, three of them found by driving the real app

The unit tests passed while all three of these were live. They were found by
opening the panel, pressing the buttons, and looking. Budget time for that.

1. **Disk-derived answers are invisible to observation, and the failure is
   PARTIAL.** Everything the panel says about what is downloaded comes from a
   file-system call, which no observation system can see. On the mac a
   `Section`'s content, header and footer each get their own tracking scope —
   so after a removal the ROWS redrew correctly (they read an observable
   download state) while the two summary sentences in the footers went on
   describing a model that had just been deleted. Half a panel updating is far
   more convincing than none of it updating, which is why it survived review.
   The fix is a counter the panel bumps whenever it changes the disk, touched
   by every disk-derived answer. Whatever your framework's rules are, assume
   they do not cover `File.Exists`.

2. **One store per FILE, not one per place that cares.** The panel and every
   assistant window each made their own downloader for the same path. Press
   Download in Settings, then open the assistant while it runs: the second one
   sees an incomplete file, deletes it — which is the right thing to do to a
   part-finished attempt, deliberately, since resuming a mismatched range
   produces a corrupt model that fails much later somewhere less obvious — and
   starts again. Two transfers writing to one destination, on a school
   connection, for gigabytes. The mac now has a process-wide registry keyed by
   tier. Sharing also fixes the quiet half: a download started in one place is
   visible in the other, because both watch the same object.

3. **Closing the assistant window must cancel only ITS OWN download.**
   Cancelling on close is right — a teacher who shuts the window has finished,
   and leaving gigabytes coming down behind their back is not a kindness. But
   once the stores are shared, the download that window can see may have been
   started in Settings, where the entire point was to fetch ahead of time and
   get on with something else. Track who started it. An explicit Stop button is
   honoured wherever the download came from; a window CLOSING is not.

4. **The tier decides the context size, so the engine must be started with the
   CHOSEN tier, not the machine's.** This one is a straight regression the
   moment a choice exists: our server host took the tier off the hardware
   budget, so a teacher on a large machine picking the smaller assistant would
   have got the small model with the LARGE model's context window — several
   times the memory they chose it to save, which is the opposite of what they
   asked for and invisible until the machine starts swapping. Grep your own
   code for every place the tier is derived from hardware rather than passed
   in.

Also worth knowing: macOS HIDES a settings window rather than destroying it,
so the view and its state outlive every visit — a panel opened in the morning
would describe the morning's disk for the rest of the day without an explicit
look-again when the window comes forward. Check what your platform does.

### The trail

Seven new events, all in `shared-rules.json` → `activityTrail.mustRecord`, so
your suite will redden until you record them — as designed:
`app settings opened`, `assistant model chosen`, `assistant model download
started`, `assistant model downloaded`, `assistant model download failed`,
`assistant model download stopped`, `assistant model removed`.

Two of them are there for reasons worth restating. **`assistant model chosen`
carries BOTH the button pressed and the assistant it resolved to** — "chose
automatic" does not answer the question anybody asks months later, because the
answer depends on the machine and on a rule that can change. And **the stopped
line exists so that a start with no ending MEANS something**: without it,
"started downloading, nothing after" is ambiguous between a cancel and a
hang, and a hang is what somebody would go looking for.

## Asking for a Netlify or Cloudflare token (entry 253)

The first publish of a section stops on one line from the launcher:

```
Paste Netlify token:
```

Until now that line WAS the question a teacher was asked. Both apps watch the
running launcher for a prompt and put it in a dialog with a text field — so a
teacher who has never heard of an access token was shown its name, a box, and a
Send button, with nothing about where one comes from. Reported as "too terse",
and it is: the dialog contained no information the teacher did not already lack.

**What replaced it.** `CredentialRequest` (mac: `QuartzTeachers/Scripting/`)
recognises the three prompts the launchers can stop on, and each carries the
whole dialog: a title, one short paragraph saying what the credential is for
and that it is asked only once, numbered steps that produce one, a link to the
page that makes it, the field's label, and whether the answer is a secret.
`CredentialRequestSheet` renders it; `TaskProgressView` shows that sheet
instead of the plain alert whenever `ScriptRunner.pendingCredentialRequest` is
set.

**The sentences are DATA, so do not retype them.**
`contracts/app-rules.json` → `credentialRequests.requests` is a generated
readout of all three, field for field. Deserialise it into the WinUI dialog and
the two apps say the same thing forever; retype it and they diverge on the
first wording fix.

**The authored half is `credentialPrompts`**, and it is what fails when the
matching drifts:

- `cases` — six prompts and the request each produces (three real ones, three
  ordinary questions that must produce none, so a match that grew too greedy is
  caught). Windows already parses prompts in `QuestionParser.cs`; the matching
  itself is three `Contains` checks on the lowered line.
- `matchedOnWordsNotWholeLine` — match on `netlify token`, `cloudflare token`,
  `cloudflare account id`, never on the whole line. The two launchers word
  these prompts differently and are free to keep doing so.
- `whyNoBrowserOpens` — see below.

**No app and no launcher may open the token page by itself.** Both launchers
used to do it the moment they asked: `open` in `deploy.sh`, `Start-Process` in
`deploy.ps1`, three calls each. A browser tab arriving unasked, over the app the
teacher was looking at, reads as something going WRONG rather than as help —
that is the report that prompted this entry, in those words ("disconcerting").
Those six calls are already deleted, `deploy.ps1` included, and a mac test
greps both launchers for them so they cannot come back. In the dialog the
address is a `HyperlinkButton` the teacher clicks when they are ready; in a
terminal it is printed in the steps. **Do not add a "helpfully open it for
them" convenience to the WinUI dialog.** The printed instructions in both
launchers were rewritten to the same steps as the dialog, so a teacher at a
console gets the same explanation.

**Two details that are easy to get backwards.**

- A token is a secret and goes in a `PasswordBox`; a Cloudflare **Account ID is
  not**, and goes in a plain `TextBox`. Hiding the ID costs the teacher the one
  check available to them — that what they pasted is what they copied — and
  showing a token puts a live credential on a screen a class can see.
  `credentialPrompts.everyRequest` pins both, with each request's link.
- **Trim the pasted value.** A code copied out of a dashboard often carries a
  trailing space or newline, which is invisible and rejected, and the teacher is
  told their token is wrong when it is not.

**Two things in the steps that are load-bearing, not padding (entry 254).**
Both were added after a teacher walked through the real pages:

- **Expiry.** Netlify's expiry box starts at **7 days**, and an expired token
  announces nothing — publishing simply stops working a week later, which gets
  reported as the app breaking. Both token requests now tell the teacher to set
  a date after the end of their school year (next July), or "No expiration"
  where Netlify offers it. Cloudflare's `TTL` section is the same trap and gets
  the same advice.
- **Cloudflare's Account Resources.** A custom token needs `Include` + the
  teacher's own account chosen by name, in the section below the three
  permission dropdowns. A token that names no account cannot publish, and what
  comes back does not mention accounts at all — so this cannot be left to the
  teacher to infer. Verified against the live Create Custom Token page: the
  dropdowns read Account / Cloudflare Pages / Edit, then Account Resources,
  then TTL.

Both notes are in `credentialPrompts.expiryAdviceIsLoadBearing`, and a mac test
asserts the strings "7 days", "school year", "TTL" and "Account Resources"
survive in the steps — so a future tidy-up cannot quietly drop them.

**The Account ID also has a button, and it needs the same one on Windows
(entry 254).** The Cloudflare Account ID field — in Course Settings AND in the
new-course wizard, which on the mac is one shared view — now has a **"Where do
I find this?"** link button under it, opening the same kind of dialog on
purpose rather than mid-publish. Three things about it:

- It is a SECOND request, `cloudflareAccountIDHelp`, sharing **one** list of
  steps with the launcher-driven `cloudflareAccountID` and differing only in
  the explanation. Copy the steps into two places and they drift; the mac keeps
  them in `CredentialRequest.accountIDSteps` and a test pins the two equal.
- **It must never be returned by the prompt matching** — see
  `credentialPrompts.theHelpVariantIsNeverMatched`. It can be opened by
  somebody who has not made a token yet, so its twin's "the token you just
  made" would be a lie; equally, its calm "you enter it once here" is wrong
  when a publish is paused waiting for an answer.
- What the teacher types in the dialog is **written back into the form field**,
  so a teacher who has just fetched the code does not have to close the dialog
  and find the field again. The accept button is labelled "Use this ID" rather
  than "Continue", because nothing is waiting on it.

The grey caption under that field is GONE, not reworded: it carried the
dashboard directions in four lines of small text under a field that wants one
code, shown whether or not anybody had a question, and the button answers the
same question on request. The two ORANGE notes stay — what is wrong with the ID
that was typed, and Cloudflare's 25 MB per-file limit — because one says why the
course will not save and the other is the single real functional difference
between the destinations. The button carries a `safari` symbol to the LEFT of
its text, the same mark the dialogs put on their links, so anything that leaves
the app looks the same everywhere. On WinUI: a `HyperlinkButton` with the
equivalent glyph under the Account ID `TextBox`, the same dialog, the value
written back on accept — and, still, nothing that opens a browser by itself.

**The trail.** `asked for a publishing credential` is in
`contracts/shared-rules.json` → `activityTrail.mustRecord`, so the Windows
pinning test fails until that enum case exists. It records WHICH credential was
asked for and never the answer. It is there because a first publish waiting
behind a dialog nobody noticed is reported as a publish that "never finished",
and this line is the difference between reading that as a hang and reading it
as a question waiting. The same event covers a teacher opening the Account ID
instructions from the button — the line says which credential they went looking
for, which is the same question being answered a different way round.

**Teacher Surname & Site Name Dialogs (entry 260).**
The same `CredentialRequest` model and `CredentialRequestSheet` dialog are used
when `scripts/deploy.py` asks for the teacher's surname on first deploy or when
choosing a Netlify/Cloudflare subdomain:

- `teacherSurname` (`isSecret: false`, `linkAddress: null`): explains why the surname
  is needed (to create recognizable website addresses like `mcv4u-s1-2026-gordon`
  and prevent collisions across classes), saved once on the machine. Matched on
  prompts containing `"last name"` or `"surname"`.
- `siteName` (`isSecret: false`, `linkAddress: null`): explains that website addresses
  on Netlify and Cloudflare Pages are shared globally and must be unique. Outlines
  suggested naming patterns (`<course>-s<section>-<year>-<surname>`, `<school>-...`).
  Matched on prompts containing `"enter netlify site name"`, `"netlify site name"`,
  or `"website name"`.
- `siteNameConflict` (`isSecret: false`, `linkAddress: null`): presented when a chosen
  address is already taken, guiding the teacher to append a numeric suffix or school initials.
  Matched on prompts containing `"choose a different netlify site name"`.
- **Pre-filling suggested answers**: `TaskProgressView` passes `runner.suggestedAnswer`
  (e.g., extracted from brackets `[mcv4u-s1-2026-gordon]`) as `initialAnswer` into the dialog,
  so the teacher can accept the recommendation with a single press or edit it.
- **Link button visibility**: `CredentialRequestSheet` only renders the link button if
  `linkAddress` is present and `linkTitle` is non-empty.

All requests are serialized in `contracts/app-rules.json` → `credentialRequests.requests`.

## Task cancellation and duration explanation in TaskProgressView (entry 271)

Previewing and deploying can take significant time on first run (building the local engine image, installing dependencies, performing full compilations, or uploading initial sites). Teachers can now cancel a preview or deploy mid-flight from the GUI, and see a plain-language explanation of why a task might take a while.

### 1. Cancel button & avoiding orphan processes

- **UI Placement**: A bordered `Cancel` button sits in the bottom-trailing corner of `TaskProgressView`, below the progress bar and step description. It is visible only while `runner.isRunning` and `!runner.wasCancelled`.
- **Signal Handling (Control-C)**: Rather than abruptly killing the shell process (which would orphan child commands like `docker buildx` or `wrangler`), `cancelByUser()` writes `\x03` (`Control-C`) into the pseudo-terminal (`PseudoTerminal` on macOS, `ConPTY` / `PtyDriver` on Windows). This delivers `SIGINT` to the foreground process group and lets scripts run their cleanup traps.
- **Safety Timeout**: If the process has not terminated within 2 seconds of the interrupt, direct process termination is invoked.
- **Container Cleanup**: `cancelPreview()` and `cancelDeploy()` call `PreviewStopper.stopSectionProcesses(...)` (`preview.ps1 CODE N -Stop` on Windows), which finds and terminates any container processes running in `.merged_output/sectionN`.
- **Outcome Status**: Cancelling marks `wasCancelled = true` and `wasStoppedByUser = true`. `TaskProgressView` shows the orange `Cancelled` badge and `"<Title> was cancelled."`, and the run is not reported as an error.

### 2. "Why might this take a while?" popover

Below the milestone label on the leading side, a subtle `Why might this take a while?` button with a `questionmark.circle` icon opens a popover / flyout displaying four plain-language bullet points (strictly adhering to Rule 1 — no "Docker", "container", "Colima", "toolchain", "Node", or "npm" jargon):
- **First-time setup**: Getting everything ready for the first time takes a couple of minutes to set up your website builder. Future previews and deploys will be much faster (usually just a few seconds).
- **First-time publishing**: Uploading your entire website for the first time takes a bit longer. Future publishes only upload the pages you’ve changed.
- **Photos and attachments**: Courses with many images, documents, or media files take extra time to prepare and upload.
- **Internet connection**: When publishing online, upload speed depends on your current internet connection.

On Windows: implement as a WinUI `Flyout` or `TeachingTip` triggered by a `HyperlinkButton` or subtle button with a matching question mark icon.

## plantoir.app is generated, and its screenshots are taken by a robot (entry 255)

The marketing site used to be one hand-written `site/index.html`. It is now
four pages — home, features, day to day, support — generated by
`python3 website/build.py` from sources in `website/`. Netlify still deploys
`site/`, unchanged, so nothing about hosting moved.

**Nothing here needs a Windows implementation.** The site is one site for one
product; a second one built on Windows would be a second product. What Windows
owes it is *pictures*, and only once that app ships.

### What Windows will owe

Every image on the site exists twice, `<id>-light.png` and `<id>-dark.png`,
because the pages swap them with `<picture>` and
`media="(prefers-color-scheme: dark)"`. The ids are listed in
`website/shots.json` along with their alt text and captions.

When the Windows app is released, the pages should be able to show a teacher
what it looks like on *their* machine. The plan is a third and fourth file per
shot — `<id>-windows-light.png`, `<id>-windows-dark.png` — captured from a
Windows machine using the same ids, with `build.py` taught to offer both. That
is a small change here and a real piece of work there, so it is written down
now rather than discovered later.

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

## The hide filter belongs to the IMAGE, not to a running container

Fixed 2026-08-17. **Shared Python and a shared Dockerfile, so Windows inherits
the fix with nothing to port** — but read this anyway, because the shape of the
bug is one that can be reintroduced from either side.

A teacher marks pages hidden — Private Notes, Curriculum, Learning Goals — and
the Explorer honours that through a `filterFn` in `quartz.layout.ts` carrying a
`CQ4T-OMIT-ANCHOR` marker. `build_site.py` only ever rewrites the CONTENTS of
the `omit` Set inside that filter. It cannot create the filter.

The filter used to be established in exactly one place: `setup_course.py`
patching `/opt/quartz/quartz.layout.ts` **in the running container**, at
course-creation time. That made it container state. And a container is
recreated whenever the recipe hash changes — which is the documented design
after most toolchain updates. So:

1. Teacher's courses work; the container carries the patch.
2. An update changes the recipe. New image tag, container recreated.
3. Next preview copies a pristine `/opt/quartz` scaffold. No filter.
4. `build_site.py` warned twice and **carried on**, injecting a bare
   `const omit = new Set([])` "to unblock the build". The Set was then
   populated and nothing consumed it.
5. Build succeeded. Everything the teacher had hidden went up on the class
   site.

Verified rather than reasoned about: `docker run --rm <image> grep -c
CQ4T-OMIT-ANCHOR /opt/quartz/quartz.layout.ts` returned **0** before the fix
and **2** after.

### What changed

- **The Dockerfile bakes it in**, right after `scripts/` is copied, by calling
  `setup_course.ensure_quartz_explorer_anchor()` — the same function setup
  uses, imported rather than copied so the two cannot drift — then asserting
  the marker is present and mirroring the result into `/opt/quartz-site`. A
  container now has the filter from birth.
- **`build_site.py` repairs instead of papering over.** If the marker is
  missing it injects the real anchored Explorer block (again the same function),
  so containers predating the fix self-heal on the next build.
- **A build that cannot establish the filter now REFUSES.** `sys.exit(1)`, with
  a sentence saying why: anything hidden would otherwise be published. The old
  behaviour — warn, continue, publish — is the thing that made this invisible
  for as long as it was.

### The rule worth keeping

**Anything that decides whether students can see something belongs in the
image, and its absence must stop a build.** Not in container state, which
disappears; and never behind a warning, because the failure is silent and the
consequence is a teacher's private notes on a public site. If a future change
adds another such guard, it goes in the Dockerfile and it fails closed.

## Every built site wears the Plantoir icon, not Quartz's

Added 2026-08-20. **Shared Python, a shared Dockerfile and shared assets, so
Windows inherits the whole thing with nothing to port** — but two parts of it
are worth knowing, because one is a trap and one is an asymmetry you cannot fix
from your side.

Until this, every class site a teacher published showed **Quartz's logo** in the
browser tab. Quartz ships `quartz/static/icon.png` and its `Head` links that as
the favicon; nobody had replaced it. A teacher who publishes four sections had
four tabs wearing somebody else's mark.

### What is in the site now

`support/favicon/` holds four generated files, baked into the image by the
existing `COPY support/ /opt/support/`, and `build_site.py`'s
`install_favicon()` copies them on **every** build (not only a full rebuild, so
folders built before this heal themselves):

| File | Where it goes | Who reads it |
|---|---|---|
| `icon.svg` | `public/static/` | Every current browser. Sharp at any size. |
| `favicon.ico` | `public/static/` **and `public/`** | Older Safari; Windows shortcuts. 16/32/48, BMP entries. |
| `apple-touch-icon.png` | `public/static/` | iOS "Add to Home Screen". 180x180, square, opaque. |
| `icon.png` | `public/static/` | Nothing links it. It overwrites Quartz's, so the site carries no Quartz logo even unlinked. |

`patches/Head.tsx` links the first three, in that order, with paths relative to
the page (`baseDir`) so a site served from a subfolder still finds them. Order
is load-bearing: a browser takes the LAST icon it understands, so the `.ico`
goes first and the SVG wins wherever it is supported.

### The trap: there are two emitters, and only one can write to the root

`favicon.ico` is installed **twice**, and the second copy is not redundant.

- Quartz's **Static** emitter copies `quartz/static/` to `public/static/`. That
  is where the `<link>` tags point, and it covers every browser that reads the
  page.
- Nothing that emitter can do puts a file at `public/favicon.ico`. The only
  route to the site ROOT is the **Assets** emitter, which copies every
  non-Markdown file out of `content/` into `public/` unchanged. So
  `install_favicon()` also drops `favicon.ico` into the content root — which is
  why the call sits AFTER the content folder is rebuilt from scratch, not in
  the ALWAYS block above it. A copy made any earlier is deleted a few lines
  later and the failure is invisible: the page still looks right, and only the
  implicit `GET /favicon.ico` that feed readers, link unfurlers and older
  browsers make (without reading the page at all) comes back 404.

`verify.sh` now asserts both halves separately — the four files exist, the root
`favicon.ico` and `static/icon.png` are byte-identical to `support/favicon/`,
and `index.html` links all three. A site can have every file and still show the
Quartz logo if `patches/Head.tsx` did not make it into the image, so
`check_baked patches/Head.tsx` was added at the same time (it had never been
checked).

### The asymmetry: the favicon can only be regenerated on the mac

The artwork's source of truth is `mac-app/Plantoir.icon` — the Icon Composer
bundle, mac-only. `scripts/brand_images.py` reads the plant's SVG path straight
out of it and draws every image that carries the mark, the favicon included, so
the mark cannot drift between the social card, the profile avatars and the
browser tab. It needs only Pillow, but it needs that `.icon` folder, so
**a Windows session cannot regenerate the set** — the same direction as
`--write-contracts`. Treat `support/favicon/*` as data you receive. If the app
icon changes, that is a mac task, and the Windows `.ico`
(`windows-app/Plantoir/Assets/make-icon.ps1`) is a separate regeneration from a
1024 export, exactly as it is today.

### The favicon IS the app icon, and that was a decision

Not a reinterpretation of it. The raster sizes are literally `icon_tile()` —
the same function that draws the tile on plantoir.app's social card — so the
favicon cannot come to disagree with the icon in the Dock: same ramp, same
0.703 glyph scale, same viewBox centring, same drop shadow, same
regular-weight outline with the leaf counters open. `favicon_svg()` is that
tile written out as vector, reading the same constants rather than typing the
numbers again.

**This was tried the other way first, and reverted on Russell's call.** The
first version used the **fill** weight of the same glyph — `plant.svg` is three
subpaths (the silhouette, then the two leaf counters), so dropping the last two
gives a solid plant for free. The argument was legibility: at 16 physical
pixels the outline's leaf midribs land on the outline and the mark goes muddy,
which is measured rather than assumed. The argument that beat it is simpler —
**looking like the app icon is the point of the app icon.** Record that
direction, because the legibility case is genuinely tempting and will be made
again.

If it ever does need revisiting, two dials exist and one trap:

- `render_glyph`'s **`bold_units`** thickens the outline in viewBox units
  without changing the drawing. The Instagram avatar already uses it (3.0) for
  exactly this reason — it is stored at 320 and shown at 32.
- The **`.ico` can carry a different drawing per size**, since each entry is a
  separate bitmap, and `write_favicons` already renders each size natively.
- The trap: **`icon.svg` cannot.** Browsers that support it render THAT at
  whatever size they choose, so a per-size tactic that only touches the `.ico`
  leaves Chrome and Firefox unaffected. And 16 physical pixels is a Windows tab
  at 100% scaling — any Retina Mac asks for 32.

One thing rejected outright: **darkening the green for contrast.** The brand
green on the cream tile is about 3:1. The answer to a thin stroke is a thicker
stroke, not a different colour, and the colour is not ours to change here.

There is deliberately **no web manifest and no 192/512 PWA icon set**. That is
Android home-screen and installable-app territory, not a favicon, and the
teacher's site is neither.

## Testing

- The **PowerShell launchers are tested on real Windows** — all three have
  been driven end to end through the app: course creation, preview (including
  `--stop` reclaiming container-side processes), and publishing to all three
  destinations, most recently a live Cloudflare Pages publish. The WSL2
  background and the original test plan are the appendix at the end of this
  file; read it for *why* the launchers look as they do, not as a to-do list.
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

- [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — THE spec (179 entries as of
  2026-08-15). Its **Windows status** section is where coverage is tracked.
- [`documentation/`](documentation/README.md) — toolchain deep dives 01–10.
- [`CLAUDE.md`](CLAUDE.md) — the repository's entry point: conventions,
  testing, setup, and the traps that cost time.
- [`RELEASING.md`](RELEASING.md) — cutting a release, both platforms.
- [`research/ai-assist/`](research/README.md) — the assistant's
  measurements, and `HISTORY.md`, which is the feasibility work, the build
  handoff and the original MCP proposal in one place.
- The WSL2 launcher background is the **appendix at the end of this file**.
- [`mac-app/`](mac-app/README.md) — the reference implementation; when an
  entry's Windows note is thin, read the Swift it references.


---

# Appendix — WSL2 background and the original .ps1 test plan

*Folded in from the former `WINDOWS-TESTING.md` on 2026-08-15. Read it for **why** the
launchers look the way they do — the WSL2 container-runtime reasoning, the
`ProcessStartInfo` token injection, the path translation — not as a to-do list.
The launchers have since been driven end to end on real Windows 11, including a
live Cloudflare Pages publish. Two facts in it were corrected on the way in: the
token file is `/tmp/deploy_pat` (renamed when Cloudflare support arrived, since
one file now serves both providers), and deploys are no longer Netlify-only.*

> **Status (2026-08-13): the launchers are no longer untested.** All three
> have been exercised repeatedly on real Windows 11 through the app —
> course creation, preview (including `--stop` reclaiming container-side
> processes), and publishing to all three destinations, most recently a
> live Cloudflare Pages publish end to end. Treat this file as **the WSL2
> background and the original test plan**, not as a to-do list: the
> historical detail on the Docker-Engine-in-WSL2 path, port blocks, and
> line-ending traps is still the best explanation of *why* the Windows
> launchers look the way they do.
>
> One thing it does NOT cover, and worth knowing: `verify.sh`, the
> toolchain gate named in [`CLAUDE.md`](CLAUDE.md), **cannot run
> on Windows** — it is bash and expects `docker` on `PATH`, where here it
> lives inside WSL2. Toolchain changes made on Windows are verified by
> driving a real publish through the app instead.

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
