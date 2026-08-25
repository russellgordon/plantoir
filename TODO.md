# To Do

Ideas and deferred work, in no particular order. Add items freely; remove
an item when it ships (finished behaviour is recorded in
[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md), not here).

- **`CourseRenameInterfaceTests` crashes the whole unit run, intermittently —
  and it is PRE-EXISTING, not caused by the special-folders work.** Measured
  2026-08-23 on a clean `origin/dev` worktree with none of that branch's
  changes: **one crash in four full runs**, aborting the run partway
  (`Executed 419 tests` and an exit code of 65 with ZERO failed test CASES).
  The branch's own rate was about the same, one in three.

  **Two wrong diagnoses were recorded here before the right one**, and both are
  worth remembering because each looked convincing:

  1. *Busy-machine flakiness* — plausible because the interface tests host real
     SwiftUI views and adversarial-review agents were running builds at the
     time. Wrong.
  2. *An alert I had just added* — plausible because the crash report names
     `SwiftUI.AppKitDialogBridge.updateExistingAlert` during an `NSAlert` sheet
     close, and `SectionDetailView` had just grown to four `.alert` modifiers.
     Consolidating them to one made three consecutive runs pass, which read as
     confirmation. It was not: the crash came back afterwards, and then
     reproduced on `origin/dev`, which has none of it.

  The lesson is the measurement, not the guess: **a baseline needs SEVERAL runs
  on an unmodified tree, in a separate worktree.** One clean baseline run was
  taken early on and treated as exoneration; it was a coin toss landing the
  other way. And `git checkout <ref> -- path/` does NOT make a baseline — it
  leaves files the ref does not have, which is how the first attempt at this
  produced a build error instead of a measurement.

  What is actually known: `EXC_BAD_ACCESS` / SIGSEGV inside
  `AppKitDialogBridge.updateExistingAlert` → `NSSheetMoveHelper closeSheet`, in
  a suite where `SectionDetailView` and the `TaskProgressView` it embeds carry
  several alerts and a sheet between them. Both crashes named a
  `CourseRenameInterfaceTests` case, but that test hosts a sidebar ROW and is
  most likely the bystander that happened to be running.

  Where to start: `RemovalButtonTests` next door hosts its view differently and
  does not provoke it — the difference between the two is the cheapest lead.

- **Let a teacher rename a special folder from inside Plantoir** — deferred
  2026-08-23, while planning the hardening of the special folder and file names.
  Not `CourseRenamer`, which renames the course CODE and deliberately nothing
  else: this is renaming `Ontario Curriculum`, `Tasks` or `All Classes` in the
  app, so the app is the one performing the rename.

  **What exists today is thinner than it looks.** `StringListEditorView` edits
  the config LIST only — `addNewItem` appends a string, `removeItem` filters one
  out, and neither touches disk (there is no `createDirectory`, `moveItem` or
  `removeItem(at:)` anywhere under `Views/CourseSettings/`). So adding `Tests`
  to shared folders creates a config entry pointing at no folder; removing
  `Tasks` leaves the folder on disk, still full of the teacher's work, now
  unreferenced. Renaming is only possible in Obsidian or Finder — and then
  `preflight_update_course_config` in `scripts/build_site.py` discovers the new
  name and APPENDS it, with no removal path, so the config ends up listing both.

  **Why it was deferred rather than built.** The hardening work originally
  rested on recording each special folder's name in `course_config.json` so a
  check could tell DELETED from RENAMED. It cannot: the app never witnesses a
  rename, and the build's auto-discovery converts one into a duplicate. Rather
  than build the rename affordance as a dependency, the checks were rebased onto
  the FEATURE'S OUTPUT ("the coverage map found no expectations") instead of a
  folder's existence — which needs no recorded name, cannot be satisfied by an
  empty folder, and does not fire on a legitimate Obsidian rename. That made
  this a feature in its own right rather than a prerequisite, and bundling it
  would roughly have doubled the piece.

  **What it would still be worth.** It fixes the two foot-guns above (add
  creates nothing; remove orphans a folder), and it is the one place a rename
  could be observed. It needs its own design pass for what happens to wikilinks
  pointing into a renamed folder, and its own undo.

- **Let a teacher rename the `Unit` keyword** — deferred 2026-08-23, while
  planning the hardening of Plantoir's special folder and file names. Some
  teachers organise by "Module" or "Thread" rather than "Unit", and today the
  word is not a preference but a structural assumption: `_is_class_page` in
  `scripts/build_site.py:1402` matches `^Unit\s+\d+,\s*Day\s+\d+$`, and
  roughly 290 places in the Swift and 208 in the C# name it.

  **It is deferred because of the migration, not the parsing.** The parsing side
  is mechanical — one configured term threaded through the regexes and the
  title generators. The measurements that decided it (taken 2026-08-23):

  - **3,088 files** named `Unit N, Day N` under `support/example_content/`, and
    **3,143 files** containing a `Unit N, Day N` wikilink;
  - **600** skeleton files, which are generated and therefore cheap;
  - `contracts/class-planning.json` is authored end to end in Unit/Day;
  - the local assistant's routing was measured against sentences like "publish
    Unit 4" — a teacher who renamed to Thread will type "publish thread 4".

  **The split that makes it tractable.** Payloads are copied fresh at course
  creation, so a NEW course can pick its term at setup and one rewrite pass
  during the copy handles all 3,000-odd files and their wikilinks at once. That
  is cheap, contained, and delivers most of the value. Renaming an EXISTING
  course is the dangerous half: it means rewriting every wikilink pointing at
  every renamed page, across every shared folder and every section, and a
  half-finished rename leaves a broken site with no obvious way back.
  `WikiLinkRewriter` could do it, but it deserves its own design pass and its
  own undo — not a checkbox in settings.

  **Hold "Day" fixed.** A teacher who says "Thread" almost certainly still says
  "Day 3"; only the first term looks worth making configurable.

  Rejected: a display-only rename (the page would be titled "Thread 2, Day 3"
  while the file stayed `Unit 2, Day 3.md`), because Obsidian is the teacher's
  editor and they would see the old word every time they opened the vault —
  which is the place the rename was supposed to help.

- **The assistant's first turn does not wait for its warm-up** — measured
  2026-08-20, while qualifying the mac for v1.1.0. `AssistSession` sets
  `readiness = .ready` (which is all `canSend` checks) and only THEN awaits
  `warmUp`, so a teacher who types straight away queues behind the
  ~3,400-token priming request on the server's single slot. Same question,
  same model, same Mac: **1.7 s** warm against **3.1 s** racing the warm-up.

  It is an optimisation, not a fix — deliberately left out of 1.1.0 because
  changing it would have made an unchanged mac binary a behaviour change,
  and the failure Windows repaired (a first question ending in silence)
  cannot happen here: the timeout is 180 s, `AssistAgent.think()`'s catch
  surfaces every error as a message and a trail line, and the engine's
  output goes to `nullDevice` so no pipe can wedge. Windows already awaits
  its warm-up; see `MAC-HANDOFF.md` and GUI-IMPROVEMENTS row 295.

  The fix is small: hold `.ready` until the warm-up returns, or gate
  `canSend` on a separate `hasFinishedWarmUp`. **Pin it with a test** that
  a turn cannot start before the warm-up's request has come back — the
  measurement above is the evidence it is worth doing, not a substitute
  for one.

- **A mac problem report can carry nothing the engine said** — found the
  same day. `AssistServerHost` sends `llama-server`'s stdout and stderr to
  `FileHandle.nullDevice`. That is load-bearing (an unread pipe is what
  wedged the Windows server mid-request, and this is why the mac never
  had that bug) but it also means model-load errors, slot warnings and
  timing lines reach nobody — the one place they could matter is a report
  from a teacher whose assistant is misbehaving. Windows added
  `NoteServerLine` for this. Sample a BOUNDED tail into the trail rather
  than piping the firehose, and keep the no-blocking-read property that
  makes the current arrangement safe.

- **A preview's progress bar sits at 100% saying "Opening the preview…"
  for the entire build** — found 2026-08-19, while re-shooting the
  marketing screenshots; the "Building your site…" step is unreachable.

  **✅ Fixed on Windows, 2026-08-23** (`TaskMilestones.cs`, built and tested,
  664/664 green) — see `MAC-HANDOFF.md`'s "Open — what the mac still owes"
  for the full write-up. **Not yet fixed on the mac**: the matching Swift
  edit (`TaskMilestones.swift`) was made on Windows and has not been built,
  tested, or run through `Plantoir --write-contracts` on an actual mac —
  `contracts/app-rules.json`'s `milestones.preview` is still the stale,
  pre-fix readout until that happens. Leave this item here until the mac
  side is verified.

  Two facts combine. First, `build_site.py` prints "🚀 Launching Quartz
  preview on…" (the FINAL preview milestone's marker) *before* it runs
  `npx quartz build --serve`, because build and serve are one command.
  Second, `ScriptRunner.advanceMilestones` deliberately jumps to the
  highest marker seen (so varying output never stalls the bar) — so that
  early line completes every milestone at once. From then until the site
  appears, a teacher watches a full bar captioned "Opening the preview…
  still working… (Ns)". "Building your site…" (marker "Quartz v4") and
  "Preparing components…" (marker "Installing dependencies" — a line that
  no longer prints, since the image ships `/opt/quartz/node_modules` and
  the script copies it instead of running npm) never display at all. The
  old marketing shot showing "Building your site… still working… (4s)"
  dates from when npm install still ran.

  The fix: give the final preview milestone a marker that appears when the
  server is actually up — Quartz prints a "server listening" line once
  serving — instead of the pre-build launch line. **Verify the exact
  string against a real preview's transcript before pinning it**: a marker
  that never matches leaves the bar stuck one step short, which is the
  same defect wearing the other shoe. This is contract-carried data
  (`contracts/app-rules.json` milestone tables, mirrored in the Windows
  app's `TaskMilestones.cs`), so the change means `--write-contracts`, a
  `GUI-IMPROVEMENTS.md` row, and a Windows note — which is why it was
  recorded here rather than folded into the screenshot re-shoot that
  found it. Measured while pinning this down (instrumented 20 Hz polling of the
  milestone text during real previews): every step before "Opening the
  preview…" is gone before a first sample can be taken — the launcher's
  early output arrives in one buffered chunk — and the sentence then sits
  on a FULL bar for the whole build, observed at 100+ seconds. Until the
  fix ships, the marketing `progress` shot photographs that state, because
  it is the only one the app dependably shows;
  `MarketingScreenshotTests.test4Progress` documents the dependency and
  says to re-take the shot when the fix lands. Worth knowing when fixing:
  the label shows the step whose marker has NOT yet printed, so a marker
  is read in practice as "the previous step ended", whatever the struct
  comment says — and the on-screen sentence is the accessibility VALUE of
  `taskMilestoneLabel`; its label is empty.

- **Container recreation can kill live previews** — noted 2026-08-11.
  Every launcher "ensures" the working folder's container, and on a
  toolchain-recipe hash or mount mismatch it recreates it (`docker rm
  -f`) — taking any live preview servers down with it. In steady state
  hashes match and this never triggers; it can bite mid-session only in
  rare cases (e.g. an app update refreshing `.toolchain` while another
  window previews). A thorough fix would make the ensure-container step
  decline (or warn) when the container hosts running previews. Low
  priority — rare, and the next preview self-heals.

- **AI Assist — the rest of it**, updated 2026-08-14 after a full
  live-tested day on the `ai-assist` branch, since folded into `main`
  (not yet in any tagged release). The
  Windows in-app assistant is now **working end to end**: approval gate
  (deploys only), embedded model with a verified once-ever prompt cache,
  the promise card handled as deterministic commands, page edits doing
  stop-edit-offer around the app's own preview, and the whole loop moved
  to `Plantoir.Core` with tests covering every promise —
  [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 2 §10 is the record, and
  `MAC-HANDOFF.md` carries the mac side's pickup entry. What remains:

  **(a) The CSV reschedule — built; what is left is around the edges.**
  It shipped in the plan-then-write shape this item asked for.
  `Plantoir.Core/Assist/Timetable.cs` reads a school's sheet without
  assuming its layout — which row is the header, which column holds dates,
  and how the dates are written are all worked out from the sheet itself —
  and `ReDatePlan.cs` produces the diff table shown before anything is
  written. The MCP surface is `read_timetable` → `plan_re_date_classes` →
  `re_date_classes`, plus `roll_over_section` for a new year, all in
  `Plantoir.Mcp/PlantoirTools.cs`, with tests in
  `Plantoir.Tests/TimetableTests.cs`. §5 of the handoff records 26 classes
  re-dated against a teacher's own spreadsheet, checked by an independent
  parser. Two things are genuinely left:

  * **Only CSV comes off disk.** `TimetableSource` reads a local file as
    plain text, or exports a shared Google Sheet by link. A teacher's
    `.xlsx` sitting in Downloads is neither, so they have to export it
    first — while the tool's own help text says “timetable.xlsx”. Not
    worth fixing — teachers export to CSV without friction, and reading
    `.xlsx` off disk buys little.

  **(b) The shared activity lease, finished.** `WorkLease` files under the
  working folder now let the GUI decline a preview while the assistant
  builds, but the full both-directions story (server honouring the GUI's
  claims across every operation, and the mac app reading the same files)
  is still a shared-design item — agree the remaining shape with the mac
  side first.

  **(c) Re-measure the conversational residue — partially done, 2026-08-24.**
  Re-run against Qwen2.5-1.5B (native, Vulkan) with a two-sentence prompt
  tweak: full write-up and raw runs in
  `research/ai-assist/conversational-residue-results.txt`. The **undo
  over-salience** cluster (a "posted X by mistake" unpublish request
  routed to `undo_last_change`) is fixed, and a related case not in the
  original TODO wording — a hide request declined outright — is fixed as
  a side effect; conversational-only accuracy went from 85% to 91-94%
  across two runs, with no new failures elsewhere. Shipped in
  `AssistAgent.cs` and `AssistAgent.swift` — **the Swift side is written
  but, per the usual constraint of a Windows session, not yet built or
  tested on a mac**; see `MAC-HANDOFF.md`.

  **Still open: the deletion probe's decline never came back.** "Delete
  the Unit 1 folder" still routes to `cancel_scheduled_deploy` instead of
  declining, unchanged across every wording tried. A more explicit
  sentence naming that tool directly was tried and made things worse
  elsewhere (two previously-clean conversational cases regressed) — logged
  in the results file as a rejected option so it isn't retried unmeasured.
  Left for a future pass.

- **A "prepare for start of year" operation, and the audit behind it** —
  deferred 2026-08-13, from a real session on the `ai-assist` branch.

  A teacher asked for "every class past Unit 1, Day 1, and everything those
  link to, into draft". Applied exactly, that rule left **32 course-level
  pages in SNC1W still published** that no class page links to at all — a
  whole unit's concepts, plus unassigned tasks and portfolio pages. The teacher
  spotted one (`Concepts/Astronomical Phenomena`, reachable only from an
  investigation that is itself unreferenced) and the rest fell out of an
  audit script.

  **The lesson: link-reachability is a weak proxy for "not yet taught."** A
  link-following rule cannot see a page no class links to, and those are
  precisely the pages a teacher has written ahead. If Plantoir grows a bulk
  start-of-year operation, base it on unit number, date, or an explicit
  teacher-facing "not yet taught" flag — not on what is reachable.

  The audit half of this shipped, as the read-only `check_section` tool in
  `Plantoir.Mcp/PlantoirTools.cs`. It cross-references a section's pages
  against every wikilink and reports two of the three groups: links on
  visible pages that lead to a hidden one (a student clicks and finds
  nothing), and pages nothing links to — still published, still listed in
  Quartz's explorer, and invisible to any rule that follows links. That
  second group is what proved the *rule* incomplete.

  What is still missing is the third group, **linked-but-missed**: pages a
  class does link to that a bulk change should have caught and did not. Its
  being empty is what proved the job complete, and `check_section` cannot
  say so today. Missing too is the bulk start-of-year operation itself —
  worth having with or without any AI, and per the lesson above it should
  key off unit number, date, or an explicit "not yet taught" flag rather
  than reachability. (`LinkGraph.cs`'s doc comment quotes 50 unreachable
  course-level pages, but for a "sample course" it does not name — a
  different measurement from the 32 above, not a contradiction of it.)

## Docker build cache is never cleared (deliberately, for now)

`docker system df` on the dev mac, 2026-08-23: 1301 build-cache entries,
14.30 GB, 14.25 GB reclaimable — a bigger number than the images that were
leaking beside it (fixed 2026-08-23, `GUI-IMPROVEMENTS.md` 352).

**Not fixed on purpose, and this is the record of why so it does not get
re-proposed:** `docker builder prune` is GLOBAL. There is no per-project or
per-tag filter, so a launcher calling it would throw away the build cache of
every other project sharing this Colima VM (Supabase, among others) — the same
constraint that shaped the image cleanup, but with no narrow form available.
Clearing it stays a by-hand developer job:

```bash
docker builder prune          # global — read the size it offers first
```

A teacher's cache is also a fraction of this: the 14 GB here came from twelve
days of toolchain edits, where a teacher builds on install and then not again.
If this is ever revisited, the thing to find out first is whether BuildKit can
be given a scoped cache per build context — a filtered prune, not a bigger
hammer.

## ✅ Done — Publish stops an active preview itself

Deferred 2026-08-11 as a design problem (the tricky moment being a
build-phase preview — not yet serving — where the console's ownership, the
preview lease, the waiting-for-server state, and publish's own
needs-rebuild decision are all in flight at once). Found already built on
both platforms while checking this list, 2026-08-24, and confirmed by an
adversarial review rather than taken on trust.

Mac: `SectionDetailView.swift`'s `deployAndWait()` sets `isPreparingDeploy`
(disabling the Deploy button and guarding against re-entry), then handles
both cases — `previewRunner.isRunning` for a serving preview, and an `else`
branch awaiting `PreviewStopper.waitForStopsToFinish(...)` for the
build-phase preview the first attempt couldn't handle — before running the
needs-rebuild decision. Windows: `SectionDetailView.xaml.cs`'s
`DeployAsync()` mirrors this with `_isPreparingDeploy`. Contract case
`"deploy with a preview running"` in `contracts/assist-cases.json` is live
(not skipped) and asserts the event order `stopPreview.begins →
stopPreview.ends → deploy`. Shipped across `GUI-IMPROVEMENTS.md` rows 263,
282, 283, 317 and 318 (2026-08-17 through 2026-08-22) — this item just
never got removed from here once it landed.

## ✅ Done — A recreated container publishes pages the teacher HID

Found 2026-08-17 while re-shooting the marketing screenshots; fixed the same
day (commit `9d7db82b`) and ported to the Windows-native runtime path
(`fetch-runtime.ps1`) the same day too — this item stayed on the list only
because nobody had removed it. Confirmed still fixed 2026-08-23, on Windows:
the Dockerfile bakes the `CQ4T-OMIT-ANCHOR` Explorer filter into the image at
build time, `scripts/build_site.py`'s `ensure_quartz_layout_anchor` re-asserts
it on every build and refuses to build rather than warn-and-continue if it
can't restore it, and `verify.sh` §4b asserts it against the built image.

While confirming it, an adversarial review found the checks only did a bare
substring match for the marker string — not that it is actually attached to
a live `omit` Set — so a file could pass every guard while the hidden-page
list was written to a Set nothing consumed. Tightened the same day: `_anchor_
is_structurally_wired()` in `build_site.py` and a matching `verify.sh` grep
now both require the marker's own line to sit directly above `const omit =
new Set`. Not reachable through any writer in this codebase today, but it is
exactly the failure class this fix exists to close. Full write-up, including
what still needs a real mac Docker run to confirm: `MAC-HANDOFF.md`'s "Open"
section.

## ✅ Done on Windows — Assistant replies "deployed" before the deploy finishes

Found 2026-08-19 during the deploy-during-preview adversarial review; fixed
2026-08-23. `SectionDetailView.Deploy_Click`'s body now returns the real
outcome sentence on every exit path — success/partial/all-failed, or
`AssistWording.DeployDidNotFinish` when the deploy never actually ran —
threaded back through `MainWindow.DeployForAsync` to `AssistAgent.RunTool`,
instead of the old unconditional `AssistWording.Deployed`. An adversarial
review agent caught a hang in the first attempt (a single shared completion
field, overwritten by a concurrent busy-branch call, orphaning the first
caller's await with no timeout); rewritten to return the outcome per call
instead, closing the race structurally. Full suite: 667/667. Windows-only
bug — the mac's `deployAndWait()` already awaited the real result, so no mac
work is owed. Full write-up: `GUI-IMPROVEMENTS.md` row 383,
`MAC-HANDOFF.md`'s "Open" section (for awareness only).

## ✅ Done — Write the publishing documentation for plantoir.app

Noted 2026-08-12, once Cloudflare Pages shipped; fixed 2026-08-23.
`website/pages/publishing.html` is a new page explaining all three
destinations properly: which suits whom (Netlify as the default;
Cloudflare Pages for unmetered bandwidth and a free per-section address;
a folder for teachers whose board gives them their own web space), how
to set up each, the exact Cloudflare token permission (Account →
Cloudflare Pages → Edit) and why the app also asks for an Account ID
(a Pages-scoped token can't list its own account), and the 25 MB
per-file limit — which applies to Cloudflare only, not Netlify or a
folder. Added to `site.json`'s nav between "Day to day" and "Support".
Checked against `documentation/07-deployment.md` and the in-app wording
by an adversarial review pass, which caught one overstatement (an
unsourced "no account limits worth worrying about" claim for Netlify,
corrected to the real, documented caveat: the free-tier API can get
rate-limited when a whole staff room publishes at once) and one minor
omission (a local-folder publish also propagates deletions, not just
changed files) — both fixed. `python3 website/build.py --check` passes.
No screenshots added — none of the picker or its detail fields exist in
`shots.json` yet; a future pass could add one. No `contracts/` or
handoff entry — website copy, not app behavior either platform's
teacher-facing suite covers.

## ✅ Done — Nothing verifies that a release actually reached plantoir.app

Noted 2026-08-14; fixed 2026-08-23. `website/netlify_deploy.py` gains
`verify_live()`: after `deploy()` sees Netlify report a deploy "ready", it
fetches `https://plantoir.app` and confirms the version-note line matches
`site.json`'s version, retrying a few times since Netlify reporting "ready"
and its CDN actually serving the new content are not the same instant.
Advisory only — a flaky fetch or lingering propagation lag never turns a
genuinely successful deploy into a reported failure, and a confirmed
mismatch is tracked separately from a fetch/network problem. Comparison
target is deliberately `site.json`'s own version, not the git release tag
(the tag carries a `v` prefix the page text never does). Exposed standalone
as `python3 website/build.py --verify-deploy`, and `cut-release`'s Publish
section now tells the flow to watch and act on the output. Plan and
implementation were each checked by a separate adversarial review before
landing; the implementation review caught a real bug (the CLI's standalone
entry point checked for `--verify` while every doc taught
`--verify-deploy` — a plausible typo would have fallen through into
triggering a real deploy instead of a read-only check). No `contracts/` or
handoff entry — release tooling, not app behavior either platform's
teacher-facing suite covers.

