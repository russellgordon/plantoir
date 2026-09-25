# Windows parity with mac v1.3.2: the strategy

**Where this sits in the reading order.** `CLAUDE.md` comes first, as its
own list says, and `WINDOWS-BOOTSTRAP.md` is the brief. Read this file when
the bootstrap sends you here, before you work through the open `windows`
issues one by one. It does not replace the bootstrap's rules, and it does not
replace the issues. **The issues stay the source of truth**: where this file
and an issue disagree, the issue wins, and the file should be corrected. This
file gives the ORDER of the work, the reason for that order, and the traps
between the pieces, so that forty-six issues read as one piece of work
instead of a pile.

**This file expires.** It was written for `dev` = `68214a6c` on 2026-09-25,
and it carries perishable state: red lists, counts, and "not touched since".
That kind of state is what made `WINDOWS-HANDOFF.md` rot. **When the
milestone "Windows: parity with mac v1.3.2" closes, delete this file** and the
pointers to it in `WINDOWS-BOOTSTRAP.md` and `CLAUDE.md`. Do not keep it up to
date past that point.

Drafted 2026-09-25 on the mac, read-only, against `origin/dev` = `68214a6c`,
for Russell to approve before a Windows session starts. The facts below were
read from the repository and from GitHub on that day. Where something could
only be inferred, the text says so, and the last section lists what could not
be found out from here at all.

---

## 1. The goal, and how "done" is measured

**The goal.** Everything a teacher can do in the mac app through v1.3.2, a
Windows teacher can do too, and it behaves the same way wherever the contract
says it must. The work is the 46 open issues on the milestone **"Windows:
parity with mac v1.3.2"**, plus the batch-4 pieces still landing on the mac
(section 5), which join the milestone as they land. It is judged against the
shared contract, not against the Swift. Nothing in this plan asks a Windows
session to read Swift. Where an issue points at a Swift file, that is a
reference to check against, not the specification.

**Done means all of these at once:**

1. **Every case list in `contracts/*.json` is accounted for on Windows.** Each
   list has a Windows reader. The only other allowed states are "exempt, with
   the reason written in the census table" or "held in `NamedGapLedger.cs`
   against an open issue that is NOT on this milestone". Re-take the census
   with the walker in `contracts/README.md` → "The census". Do not trust any
   number written in prose. At `68214a6c` the walker counts **187** case
   lists, and the README says **102** of them have a Windows reader. Nearly
   every remaining row in that table names an issue on this milestone. When
   the milestone closes, those rows have to say "run by <class>" instead.
2. **`dotnet test` is green, judged by the TOTALS line** (`Failed: 0`), never
   by the exit code (doc 12 → "Reading a test run"). `NamedGapLedger.cs`
   must hold no entry owned by an issue on this milestone. A green run that
   quietly carries debts from this milestone does not count as done.
3. **`PythonToolchainTests` passes every shared `scripts/test_*.py`.** A file
   may skip only for a reason written inside the file itself (for example,
   no bash). The `NotRunHere` dictionary in `PythonToolchainTests.cs`
   (~:61, "Empty today") stays empty.
4. **The UI tests cover what the contract says must be RENDERED.** For each
   sentence the contract pins that a teacher sees on screen, there is a
   `[UiFact]` in `Plantoir.UiTests` that finds it rendered. Run them with
   `.\run-ui-tests.ps1` from the repository root. The new ones this
   milestone needs are: `noStartingContentNote` and the skeleton-toggle
   sentences (#250), the Save notices and Preview Again (#272), the club rows
   in Course Settings (#274), the All Backups view (#283), and the
   scheduled-publish notice arriving while the section is open (#218).
5. **Every trail event in `activityTrail.mustRecord` without `appliesOn:
   ["mac"]` has a real call site.** Being declared is not enough. Doc 12 →
   "Two testing rules that cost time to learn" asks Windows to mirror the
   mac's `ActivityTrailWiringTests` source scan. Build it in Phase 1, because
   this milestone adds more than twenty events.
6. **`verify-deploy.ps1` has been run with nothing skipped.** This milestone
   changes the publishing path (`deploy.ps1` for #241 and #136, the MCP write
   gate), and `RELEASING.md` requires that run.
7. **Every issue is closed with a closing comment** saying what landed and
   what was measured, on what hardware. Every obligation back to the mac is
   an open `mac` issue (section 9). The x64 build is ready at "PT - Dev".

---

## 2. What Windows inherits FREE from the shared Python

These pieces were built in `scripts/`. **Nothing needs re-implementing.**
**Most rows are on `dev` today (`68214a6c`), so a Windows build from `dev`
already runs them. Three are NOT yet on `dev`: #136, #192 and #234 are batch-4
pieces still landing on the mac.** Their rows are marked *landing*: check
`dev` for the test file before relying on them. What is owed is confirming them:
run `dotnet test`, read `PythonToolchainTests` in the totals, and for each row
write one line on the owning issue saying it was green, and on what machine.

| Mac piece | What arrives free | The test that proves it on Windows | What Windows still owes around it |
|---|---|---|---|
| #275, #276 (pages take their class's date) | `build_site._date_pages_from_their_classes` rewrites the front page's and linked pages' dates in the teacher's files | `test_dates_follow_the_class.py`, which needs **`python-frontmatter` on the test interpreter**. Check that it is installed; do not assume it | #279: hide `PLANTOIR_DATED:`, the trail event, and the pointer's date cases (Phase 0) |
| #192 (setup re-run keeps the marks pool). *Landing: check `dev` before relying on it* | `setup_course.py` writes a saved `graded_folders` back unchanged | the new shared test named in the #192 draft (`test_graded_folders_rerun.py`) | One run on Windows paths (it has never run there), plus one wrong comment in `NewCourseDialog.cs` (~:1348–1361) |
| #136 (a preview's build is detected across the whole tree). *Landing: check `dev` before relying on it* | `deploy.py`'s detection | `test_preview_build_detection.py`. Its two `unreadable` cases skip on Windows | `BuildFreshness.BuiltForPreview` and `deploy.ps1`'s `Test-CarriesLiveReload` (folded into #272) |
| #280 (forty port blocks) | `build_site.first_free_preview_port`, the native re-probe that runs just before the bind | `test_port_blocks.py`. Its `build_site` half runs; its bash halves skip | #286: `preview.ps1`'s early probe and its sentence |
| #280, for the mac launchers | **Nothing for Windows.** The launcher half is `preview.sh`, and Windows' launchers are `.ps1` | none | none |
| #265 (sidebar hide rule v2, build-start marker) | the build never changes `hidden`; filter v2; `ensure_sidebar_hide_rule_current` repairs old sections (**on Windows it runs for real**, because the build tree persists there: the `.ps1` launchers set `PLANTOIR_WORK_DIR` to `%LOCALAPPDATA%\Plantoir\builds\<id>\work`, in `preview.ps1` ~:251, `deploy.ps1` ~:114 and `setup.ps1` ~:155); `.build-started.pending` → `.build-started` | `test_sidebar_hiding.py`, `test_build_started_marker.py` | #272: re-run `Vendor/fetch-runtime.ps1`, `BuildFreshness`, the two-window rule |
| #248, #251 (declined example content) | `starting_point_intro`, `install_curriculum_from_payload`, retargeting the template's `A1.1` embed | `test_starting_content_prompts.py` (25 cases) | #250 and #252: the wizard. **Nothing goes red** to say it is missing |
| #267 (clubs) | numbered page patterns, the club's start pages, refusing to pour a skeleton into a numbered course | `test_club_start.py`, `test_class_pages.py` | #274: everything in the app |
| #206 branch A (reference courses) | `reference_course.py`; `deploy.py` refuses; **`deploy.ps1` already carries its own check** | `test_reference_course.py` (26 marker rows, which include a simulation of `deploy.ps1`'s pattern) | #241: run the rows against the REAL `deploy.ps1`, which the mac cannot start |
| #206 branch B / #245 | every launcher, `.ps1` included, refuses a course argument that starts with a dot | `test_reference_course.py` | none |
| #235 (preview address) | `preview.sh` refuses instead of announcing the container port | `test_preview_address.py` (bash half skips) | #278: the app's capture |
| #234 (probe the forward before building). *Landing: check `dev` before relying on it* | nothing to run: `preview.ps1` has no forward | `test_preview_reach.py`. Its text half must be GREEN | KNOW only |
| #176 (continuation lines) | `setup_course.per_section_frontmatter` steps over a comment at any indent | `CourseLevelSplitterTests` in `test_page_visibility.py` | #190: three stale claims to correct |
| #129 (`deploy.sh` questions) | stdin sent as bytes, so CRLF cannot break it | `test_deploy_sh_questions.py` (answer tests skip; un-gating them is your call) | #134: stale counts |
| #221 (a mount name that splits on a colon) | nothing; `grep -c docker *.ps1` is 0 | none | #230: one failure-explanation case |
| #236 (a scheduled deploy outliving its course) | `deploy.py`'s behaviour. KNOW: a Cloudflare or folder orphan publishes and **reports success** | none | #239 |

**Count the shared test files with `ls scripts/test_*.py`**. There are 29 at
`68214a6c`, and #192, #136 and #234 each add one when they land. Windows' own
`PythonToolchainTests.cs` still says "fifteen" at lines 15 and 39. That is
#134, and it is Windows' file to fix.

---

## 3. Where Windows actually stands, as far as the repository shows

- **`windows-app/` has not been touched since 2026-09-19** (`901beb2b`, #162).
  Every handover since then has arrived and has not been acted on.
- **One Windows branch was pushed and never merged:
  `origin/issue/159-settle-the-day-once`.** It has 4 commits from
  2026-09-19, touches `AssistAgent.cs`, `ScheduledDeploy.cs`,
  `PlantoirTools.cs`, a new `RelativeDayFreshnessTests.cs` (548 lines), doc
  10 and `schedule-rules.json`, and #159 is still open. **Start from that
  branch**, not from nothing (Phase 5, step 1). #180 says it was "being taken
  up in the 2026-09-19 Windows run". There is no such branch on `origin`.
  Either it was never started, or it exists only on the Windows machine (see
  section 11). **The #159 branch merges into `dev` with conflicts in
  `GUI-IMPROVEMENTS.md` and `documentation/10-local-ai-assistant.md` ONLY**
  (checked with `git merge-tree` against `68214a6c`); the `windows-app/` code
  merges cleanly. Merging the finished branch into `dev` is **Russell's
  call**, like every merge.
- **Trail events.** `shared-rules.json` → `activityTrail.mustRecord` has 75
  events, and 70 of them apply to Windows. A string search of
  `ActivityTrail.cs` finds **27 of those 70 missing**, so
  `SharedRules_ActivityTrailEvents_Exist` is red on the first pull:
  `preview started with unsaved settings`, `preview again after settings
  saved`, `course created`, `assistant answer was cut off`, `assistant
  repeated the request back`, `assistant was asked about another course`,
  `class copy not made`, `section added`, `word for a unit renamed`
  (ledgered), `preview did not appear`, `scheduled deploy turned off`,
  `scheduled deploy replaced`, `scheduled deploy could not be set`, `course
  kept for reference`, `reference course school year changed`, `reference
  course pages locked again`, `course imported for reference`, `course
  imported from the older layout`, `course imported from a class website
  folder`, `course could not be imported for reference`, `unfinished import
  for reference tidied away`, `pages copied from another course`, `course
  import for reference stopped`, `pages dated by the build`, `backups
  deleted`, `build declined, course busy elsewhere`, `scheduled publish
  waited for the course`. When #287 lands, a 28th arrives: `course could not
  be kept for reference`.
- **Wording.** `assist-wording.json` has 131 keys. `ContractTests` asserts 39
  of them by name. About 80 have no same-named member in
  `Plantoir.Core/Assist/*.cs`. That is a name heuristic: some of them live
  in `ClassChangeWording` under other names. Either way, #157's walker will
  turn a large number of them red at once. That is why the ledger question
  in section 8 has to be answered before #157 lands.
- **Config keys.** A string search of `CourseConfiguration.cs` does not find
  `class_noun`, `class_page_scheme`, `front_page_heading` (#274),
  `kept_for_reference`, `reference_school_year` (#241) or
  `scheduled_deploy_may_run_late_days` (#239), so
  `FileFormats_CourseConfigKeys_MatchesContract` is red.
  (`include_curriculum_pages`, `prepopulate_example_content` and
  `use_skeleton` are also absent from that file, but none of them is in
  `courseConfigKeys`, so this test never asks for them.)
- **`NamedGapLedger.cs` holds two entries, both stale.** Both belong to #158,
  and both still say milestone `v1.3.0`. #158 is now on this milestone.
- **Other tests the issues name as red on the first pull:**
  `ContractTests.cs:19` (`deployApproval`, #193);
  `CardPhrasings_AllParsedExamplesFromContract_Pass` (#193, #217, #274, and
  #167 when it lands); `AssistScenarioTests` (#193, #217, #260, #281, #288,
  #167); `EveryRequirementOfTheLocalAssistantIsAnsweredOrSaidToBeUnexecutable`
  (#196's two requirements, #262's one; **#262 records "RED today, not held"
  as measured on 2026-09-24**); `ScheduledPublishOutcomeTests.TheKindsAreExactly…`
  (`tooLateToRun` #239, `courseWasBusy` #289);
  `AppRules_FailureExplanations_MatchesContract` (#230);
  `CourseManagement_CourseCode_Normalized_And_Problems_MatchesContract`
  (#241 g); `BuildOutputLocationTests.TheContractsFiveFreshnessRulesAreAllCovered`
  (now six rules, #272); the class-planning runners on every `"scheme":
  "numbered"` case (#274).

So the suite a Windows session pulls **is red in many places for many
reasons**. The first job is to turn that into a list: each red test mapped
to the issue that owns it. Only then does "did I break something?" have an
answer again.

---

## 4. The work, in phases

The phases follow **dependency**, not issue number. The rules that decided
the order:

- a red result has to mean something before anything else is built;
- writers come before the features that write;
- the trail and the leases come before the features that record events and
  claim courses;
- the assistant's shared seam in `AssistAgent` is a chain, done in order;
- the biggest decision-gated features come last.

Phases 2, 3 and 4 barely touch each other and can be interleaved. Phase 5
steps 1–5 are a strict chain.

Legend: **MATCH** means build it so the shared cases pass. **KNOW** means read
it; nothing to build. **CHECK** means measure, then close with the number or
fix. **DECISION** means Russell answers before the work starts.

### Phase 0: baseline, and the one thing that is wrong the moment you rebuild (1 issue)

Pull `dev`, build x64, run `dotnet test`, and write down the totals line and
every red test, each mapped to the issue that owns it (section 3 is the
starting list). Fetch `origin/issue/159-settle-the-day-once` and read it.
Write the plan for Russell (WINDOWS-BOOTSTRAP §0). Then:

| # | What it is | Kind | Where the rule lives |
|---|---|---|---|
| **#279** | The shared build now rewrites dates in teachers' files and prints a `PLANTOIR_DATED:` JSON line. **A Windows build from `dev` shows that raw line in the console on every build that re-dates a page, which happens whenever a newly visible class brings pages with it (rule 1). So this goes in the SAME build that picks up the Python.** Filter it the way `TranscriptBuilder` filters `PLANTOIR_HEALTH:`: the whole line, and while it is still arriving. Record `pages dated by the build`, from the console and from a SCHEDULED publish's output. Run the 7 `dateCases` with a `pointAt` (these should already pass). Check `os.replace` against a file held open without `FILE_SHARE_DELETE`, and OneDrive's re-upload behaviour | MATCH | `shared-rules.json` → `pagesDatedByTheBuild`; `class-planning.json` → `sectionIndexPointer.dateCases`; doc 05 → "Dates: which page carries which, and who writes them" |

### Phase 1: contract plumbing, so red means something (5 issues)

| # | What it is | Kind | Where the rule lives |
|---|---|---|---|
| **#157** | `AssistWording_MatchesContract` asserts 39 keys by hand. Replace that with a walk of every key, resolved by reflection in both directions. This is what makes every later wording handover arrive red. **Needs the ledger answer in section 8 first**, because it will surface dozens of owed keys | MATCH (test) | `assist-wording.json` → `wording`; `ContractTests` |
| **#178** | `toolSchemas.departures.absentHere` is hand-copied into `agreedExtras`. Read it from the file, and split the contract-stated departures from the `notEnumeratedHere` remainder. Keep "exact set in both directions" | MATCH (test) | `assist-cases.json` → `toolSchemas.departures`; `AssistSurfaceContractTests`; census row |
| **#230** | Failure-explanation case 13, `bind source path does not exist`. One matcher, placed LAST, matching narrowly. If the sentence reads as mac-shaped on Windows, say so on the issue instead of forking it | MATCH | `app-rules.json` → `failureExplanations.cases`; doc 03 → "How a folder is NAMED to the container" |
| **#134** | Fix the stale "fifteen" at `PythonToolchainTests.cs:15` and `:39` (leave line 55's dated measurement alone). Confirm `test_deploy_sh_questions.py` is green or skipping, and decide whether to un-gate its answer tests | KNOW + small edit | doc 07 → "Asking once, and the subshell that ate the question" |
| **#190** | Correct three stale claims in `PageVisibilityReadingTests.cs` (`:468`, `:537`, and "54" should now read 56). KNOW: 3 new `writingCases` and 2 new `readingCases`, all expected green | KNOW + edit | `file-formats.json` → `pageVisibility`; doc 08 → "A writer must take a value's CONTINUATION lines with the key" |

In the same phase, with no issue of its own: bring the ledger up to date (the
#158 entries' milestone; the new areas section 8 decides on), and add the
source scan that `ActivityTrailWiringTests` does on the mac (section 1,
item 5).

### Phase 2: frontmatter and page writers (6 issues). Decision gate: #177

| # | What it is | Kind | Where the rule lives |
|---|---|---|---|
| **#144** | `yyyy-MM-dd` without a culture renders in the current culture's CALENDAR, so a th-TH machine writes `created: 2569-…`. There are 66 product sites, and the writing ones are the dangerous ones (`TimetableMemory.Write`, `PageFrontmatter.cs:187`, `ClassSkeleton`). Add one `Dates.Iso` helper and a test under a swapped `CurrentCulture`. **Put first in this phase** because every later piece writes dates. (The brief placed it with the assistant; it belongs here because the writers are here.) | MATCH (the mac is immune by construction) | doc 10 → "Publish tomorrow's class: where a relative day becomes a date" |
| **#284** | `SetTitle`, `SetCreated`, the section copy and the scaffold (FOUR writers) replace only the key's line and leave the continuation lines behind. Ask `ContinuationLines` before rewriting, extend it for an open `"`/`'`/`[`/`{` value at any indent, read a quoted date inside its quotes, remove bottom-up, keep `\r` | MATCH | `file-formats.json` → `datesAndTitles.writingCases` (13, compare BYTES); doc 08 → "The same rule for the DATE and TITLE writers (#199)" |
| **#282** | `SectionAdder` finds the block with the shared fence finder, splices by LINE INDEX, keeps CRLF, and inserts after the last key's continuation lines. Adds the `section added` event. Its seventh case is the acceptance for #181's Windows half; #181 itself is already CLOSED (v1.3.1), so the work lives here | MATCH | `course-management.json` → `sectionNumbers.addingKeysToAPage` (7); doc 08 → "A writer must find the BLOCK the way the reader finds it, too" |
| **#177** | `CourseRestorer.FrontmatterBounds` is strict; the mac's restore is lenient since #140. Presumably adopt `PageVisibilityReader.FenceIndices`, but the issue asks for a decision. Whichever way it goes, never make the MAC strict | **DECISION**, then MATCH | no contract; doc 08; GUI row 489. The adjacent #182 (not on this milestone) touches the same swap |
| **#200** | Duplicating a class. **B is a shipped Windows fault**: the forced-hidden copy can never be published again, while the reply says "Published". Strip the inherited `publishForSection/draftSection/createdSection` keys; do not add a per-section key. A: ask the planner what it created, never compare text. C: the "other classes may already have moved" clause. The abandon refusal. 12 wording keys, `class copy not made`, `expectOtherClassesMoving`, and fix `ClassChangeWording`'s now-false doc comment | MATCH | `class-planning.json` → `duplication`; `assist-wording.json`; doc 10 → "Three things the duplicate did that nothing was watching" |
| **#158** | Rename a course's word for a unit after the course is in use: the whole feature, in the contract's `order`. Enumerate the raw files, not `ClassPages`. Do it off the UI thread. Check that the backup restore discards the build. **After #284**, because the retitle goes through `SetTitle`. Closes both ledger entries | MATCH | `class-planning.json` → `renamingTheUnitWord` (7+3); `shared-rules.json` → `specialNames.renameUnitWord`; doc 09 → "Renaming a course's word for a unit" |

### Phase 3: the trail, leases, scheduled publish and quit (4 issues, plus #238 when it lands)

| # | What it is | Kind | Where the rule lives |
|---|---|---|---|
| **#238** (incoming) | Trail lines are dropped when two processes write at once: `File.AppendAllText` opens with `FileShare.Read`, and an empty `catch` swallows the sharing violation. **Measure first** (kept X of Y, on what hardware), then fix with `FileShare.ReadWrite` plus a single `Write`, or a named `Mutex`. No retry loop. **Not a blocker for anything**: the race loses lines whatever order events are added in, so events added in Phases 0–2 need not wait for it. It sits here, with the rest of the trail work. No Windows issue exists yet; it is opened when the mac piece lands | MATCH in effect | doc 09 → "Two writers at once: the trail never loses a line" |
| **#289** | Take #156's lease rules. Another program's `preview`/`publish` declines a BUILD, but never a write (`RefuseIfPlantoirIsBuilding`'s comment says why). Take, then check, with a line-3/pid tiebreak. The scheduled publish writes `build`+`publish` leases and waits 15 s, up to 10 min, by the wall clock. `plantoir-mcp` stops its own work before leaving. Adds `courseIsBeingBuiltElsewhere`, 2 events and `courseWasBusy`. **Build the `WorkLease` decision seam here**, and run `workLeases.liveness` (19) and `workLease.bodyCases` (7) through it. Their import rows wait for #244 | MATCH | `shared-rules.json` → `workLeases.declining` (29), `.liveness`; `file-formats.json` → `workLease.bodyCases`; doc 09 → "Two programs, one course" |
| **#239** | Removing a COURSE cancels its scheduled deploy FIRST, scoped to the working folder, comparing the sanitised code. Adds `scheduled deploy turned off`, `tooLateToRun`, and preserving `scheduled_deploy_may_run_late_days` on write. **Answer on the issue whether Task Scheduler runs a missed `/SC ONCE` start late.** If it does not, the ten `howLateIsTooLate` cases should be recorded as EXEMPT in the contract | MATCH + CHECK | `shared-rules.json` → `scheduledDeployCancellation` (9+10+7+5); doc 07 → "A scheduled deploy that outlived its course" |
| **#218** | Check that the scheduled-publish notice arrives while the teacher is looking at the section. If it does not: one app-wide watcher on `%LOCALAPPDATA%\Plantoir\scheduled\unanswered`, marshalled to the UI thread; the record assembled OUTSIDE the watched folder and then moved in; hover text on the badge | CHECK, then fix | `shared-rules.json` → `scheduledPublishStopped.whenItIsShown`; doc 07 → "The notice has to arrive while the teacher is looking" |
| **#231** | The quit path. Q3 is live: ask before quitting through a PUBLISH (a preview being merely open is not work under way), and never show a modal on `WM_QUERYENDSESSION`. Delete both `appliesOn: ["mac"]` keys when you adopt it. Q1/Q2 apply only to the dead WSL fallback in `FolderContainers`. Check whether `RunDetached("wsl"/"powershell")` resolves from System32 | **DECISION** (delete the dead fallback?), then MATCH | `shared-rules.json` → `quittingWhileWorkIsUnderWay` (8); doc 09 → "Quitting: what it frees, what it refuses to free, and why"; `contracts/README.md` → the named-gap exception paragraph |

### Phase 4: preview and publish mechanics (4 issues, plus #136 and #189 as they land; #234 and #94 owe nothing, see section 5)

| # | What it is | Kind | Where the rule lives |
|---|---|---|---|
| **#278** | Carry the unfinished line between output chunks (the measurement shows three cut points that capture a WRONG port), drop the `RecentText(8000)` fallback, never start from the container port. When the server starts and no address was ever announced, stop at once, unless the teacher has just pressed Stop. **Windows' capture-as-it-arrives design was the model the mac copied**; this issue is the part that design was missing | MATCH | `app-rules.json` → `previewPorts.announcedAddress`, `.whenThePreviewNeverAppears.whenNoAddressWasAnnounced`; doc 09 → "Where the address comes from"; fixture `mac-app/Tests/Goldens/235-preview-first-build.json` |
| **#233** | Bound the QUIET, not the run: 45 s from `Started a Quartz server`, **re-measured on Windows before you adopt it**. Three verdicts, not two. An honest state after giving up. `preview did not appear`. **After #278**, because they share the wait | MATCH + measure | `app-rules.json` → `previewPorts.whenThePreviewNeverAppears`; doc 09 → "A preview that never appears" |
| **#286** | `preview.ps1` walks 40 blocks (site port plus websocket) from the requested port. It prints the new sentence word for word and exits 1. Adds a launcher trail line. Run only the `hostBlockCases` made of `busyBlocks`. The contract says "this Mac": **propose a Windows line in the contract; do not reword it locally** | MATCH | `app-rules.json` → `previewPorts.hostBlock*`, `.whenNoBlockIsFree`; doc 03 → "How a folder finds its ports, and when it cannot" |
| **#272** (+ #136 folded in) | Freshness compares against the START of the build (the 6th rule, `.build-started`). **Without it, the app reports "up to date" while wrong.** `BuiltForPreview` reads every `*.html` including dot folders, ordinal. `deploy.ps1`'s `Test-CarriesLiveReload` against the 9 cases (a likely throw on an unreadable page, and case-insensitivity). The two-window Save rule (first, measure whether a WinUI window holds its own copy of the settings), Revert reads the file, five sentences, re-running `fetch-runtime.ps1` (no named helper inside `filterFn`), 2 events. **Retitle the issue**: its title still begins "DRAFT" | MATCH | `app-rules.json` → `buildFreshness` (+ `previewBuild`, 9); `shared-rules.json` → `savingSettings` (5), `specialNames`; doc 05 (preflight, Stage 4), 07 → "One rule, six readers", 09 → "Two windows, one course" |

### Phase 5: the assistant (13 issues, plus #167). A chain through `AssistAgent`

Order matters here. Steps 1–5 each build on the seam the step before left.

| Step | # | What it is | Kind | Where the rule lives |
|---|---|---|---|---|
| 1 | **#159** | Settle a relative `date` the MODEL supplies once, in `AssistAgent`, against ONE clock; ask the tool surface which argument is a class day. **Merge `dev` into `origin/issue/159-settle-the-day-once` (conflicts only in `GUI-IMPROVEMENTS.md` and doc 10) and put it through review**; do not rewrite it. Merging it into `dev` afterwards is Russell's call | MATCH | doc 10 → "The mac's half: settled where the call is made, and a clock that is read" |
| 2 | **#180** | (The mac half of the specification is in CLOSED #208; read it, do not skip it because it is closed.) Bind `course`/`section` for any call the model makes in this window, in the AGENT. The card and the plan twin show the bound values. Refuse another course (Russell decided this via #208: refuse; nothing runs). Build a seam that can script a model's tool call, and wire `windowBinding.cases` (8), `assistant was asked about another course`, and the two refusal keys | MATCH | `assist-cases.json` → `windowBinding` |
| 3 | **#196** | Carry `finish_reason` out of `IModel.Ask`. Gate ABOVE the tool-call branch. Refuse unreadable arguments. `answerWasCutOff`, and the event. **Wind the whole TURN back out of the messages sent to the model** (not the transcript, and not on an engine failure). Pin the cap of 512 against `LocalModel.cs:507`. Propose the scripted scenario to the mac as a `mac` issue | MATCH | `app-rules.json` → `modelTiers.requirements`; doc 10 → "Step 1 — What Swift sends", "Step 2 — What comes back" |
| 4 | **#262** | A finished reply that wrote NO arguments runs only when the window supplies everything: a required argument, or a page-changing tool that declares others. `answerLeftOutWhatItWasFor`, `noCourseNamed` | MATCH | `modelTiers.requirements` (14 cases); doc 10 → "A third cause, since #198" |
| 5 | **#217** | The "hide/unpublish unit N[, day M]" frame, whose tolerance is gated on the VERB (publish takes no tolerance). The echo guard (`echoedRequest`, 9), placed below the tool branch and above the append; it compares against the message the turn BEGAN with, and reuses #196's rewind. `didNotFollowThat`, the event. The fixture needs a PUBLISHED `Unit 1, Day 1` | MATCH | `assist-cases.json` → `hideIsUnpublish` (13+20), `echoedRequest`; doc 10 → "'Hide' is 'unpublish', and a reply that is the question again" |
| 6 | **#193** | The "deploy at <time>" family AND its settling step in the same piece. **`PlantoirTools.cs:358` parses `DateTime.TryParse("06:30")` as TODAY, silently.** Clock-free matcher, one clock, an idempotent settler. The settled text must read back through your own `when` parser (DST). `deployApproval`; the trail carries the moment | MATCH | `assist-cases.json` → `deployAtATime.accepted/refused/resolving`, `cardPhrasings` 6th family; `shared-rules.json` → `assistantConfirmation.theImmediateDeployCardSaysItIsImmediate`; doc 10 → "A time is a number, not a judgement" |
| 7 | **#260** | `scheduleQuestion` under a scheduled card, chosen by tool NAME. Do it with #193 | MATCH | `assist-wording.json`; the scenario in `assist-cases.json` |
| 8 | **#281** | "deploy at 6:30" is ASKED about in code through a shared `deployFrame`. It goes to the transcript ONLY; nothing reaches the model | MATCH | `deployAtATime.asked` (25), `wording.morningOrEvening`, 2 scenarios; doc 10 → "'Deploy at 6:30' is ASKED about, in code" |
| 9 | **#288** | The say-it-as spelling for times the family reads but does not set (ten-step rule; compare MOMENTS, never text, for `onlyDifference`). Transcript only | MATCH | `deployAtATime.sayItAs` (45), `.refused` (51), `sayTheTimeAs*`, 2 scenarios; doc 10 → "A time written a way the family cannot set…" |
| 10 | **#261** | Say what a scheduled deploy REPLACES: on the card, in the dialog and in the tool result. Read the existing task machine-wide (the trap is copying the cancel path's folder filter). 2 events; tell apart what a failed set left behind | MATCH | `wording.scheduleReplaces`; doc 07 → "Scheduling a section that already has a deploy set" |
| 11 | **#203** | Wire `followingLinks.stopsAtAClassPage` (3) and `reachStopsAtAClassPage` (2), with "untouched" meaning BYTE-IDENTICAL. The behaviour is already right. Owed: the `linkedClass(es)WasLeftAlone` sentence, said once, only about a class students cannot certainly see | MATCH (sentence), KNOW (behaviour) | `shared-rules.json`, `class-planning.json`; doc 10 → "The walk stops at a class page" |
| 12 | **#167** (incoming) | "What does <page> link to?" answered in code. **`Matching` gains the window's course and section**, the same seam #274 needs. `read_page` with `answer: "links"`, 7 keys, end the turn, `expectModelRequests` in the scenario runner | MATCH | `assist-cases.json` → `linksQuestion`; doc 10 → "'What does this page link to?' is answered in code (#167)" |
| 13 | **#274** | Clubs, the largest single piece. The numbered scheme on every class-planning path, with no default naming. **No whole-unit path in a numbered course** (otherwise "publish Week 1" publishes every meeting). A numbered course orders by DATE. `positionInSentences`. The wizard's `clubToggle` and the locked settings rows. `sectionIndexPointer` (9, which **changes shipped pointer behaviour**). 60 `…ForAMeeting` keys that must **never reach the model's copy or `plantoir-mcp`**. Card phrasings read the window's page word. Needs #157, #158, #279 and #167's seam | MATCH | `class-planning.json` (numbered cases, `wholeUnit`, `insertion.numberedPosition`, `sectionIndexPointer`); `shared-rules.json` → `wizard.clubToggle`; docs 04, 08, 09, 10 |
| 14 | **#210** | The "Revise with Codex…" door (TOML escaping inside `wt.exe`/`cmd`: its own function and a round-trip test through a stub `codex.cmd`). An `outsideAgents` reader. **And the one-line trail note in the EXISTING Claude door**, which has shipped writing nothing: pull that forward into Phase 3 if convenient. Re-measure Codex start-up on Windows | MATCH | `app-rules.json` → `outsideAgents`; doc 10 → "The other doors" |

### Phase 6: course creation, reference courses and import (8 issues). Decision gate: #257, #258

| # | What it is | Kind | Where the rule lives |
|---|---|---|---|
| **#169** | A pure seam (`WizardStructure.RestoringDefaults`/`Adopting`). Run `wizard.skeletonToggle` (17) with a floor. Assert `lists.factory`/`lists.lcs` against `WizardDefaults` | MATCH (seam + test) | `shared-rules.json` → `wizard.skeletonToggle`; doc 04 → step 0b |
| **#250** | `HasSkeleton(code, takingExampleContent)` with NO default; invert `HasSkeletonReturnsFalseWhenExampleContentExists`; make the skeleton block a sibling; restore when the toggle goes back ON; 4+1 sentences; `course created`; an AutomationId per note | MATCH | `shared-rules.json` → `wizard`; doc 04 → §0b |
| **#252** | The `curriculumPagesOffered` rule, the toggles' enabled state, the toggles moved below the skeleton toggle, the trail clause. **Nothing goes red on either platform** if this is left out; that is its trap | MATCH | `file-formats.json` → `include_curriculum_pages`; doc 04 → "A declined payload still gives up its curriculum" |
| **#241** (+ #287 and #255 comments) | Reference courses. Two config keys, read STRICTLY (`1` and `"true"` are not true). The refusal at 15 doors, including `deploy.ps1`'s folder branch against the real launcher. A MCP write gate on `readOnly` across all 37 tools. **DESIGN an NTFS lock**: the read-only attribute does not stop a rename-over, and **the read-only attribute travelling through `shutil.copy2` publishes a hidden page on Windows; test with `draft:`**. Unlock before removing. Withhold controls, do not grey them (Site Health is the trap). Events, including `course could not be kept for reference`, written ONCE from a catch around the whole act. Add-ons left behind | MATCH + DESIGN | `shared-rules.json` → `referenceCourses.*`, `.obsidianAddOns`; docs 03, 07, 08, 09, 10 |
| **#244** (+ #245, #287, #255) | Import Courses for Reference. Never write to the source (prove it with a manifest). Skip a name by not DESCENDING into it. Clear the lock first. Stage, then rename. **Real progress, because NTFS cannot clone** (489 MB is a real copy). One failing course does not take the others. The lease claim rows from #245. A line for every course not imported | MATCH | `referenceCourses.importing.*`, `.oneImportPerCourseAtATime`; doc 09 → "Importing last year's folder" |
| **#247** (+ #258's section-2 keys) | Copy a Page. **Wire `frontmatterCases` (9) and `builderAgreement` (36) FIRST.** The four-step order. **Fuzz against YOUR YAML library**. `FileMode.CreateNew`, never `File.Exists`. NFC only to COMPARE, ordinal string checks. Strip `draftSectionTwo`/`createdForSectionTwo` by their exact names | MATCH | `shared-rules.json` → `copyingAPageBetweenCourses`; doc 09 → "Copying a page from one course into another" |
| **#257** | Import the older folder-per-class layout, if Windows needs it. **If Russell declines it, the honest form is `appliesOn: ["mac"]`** on its trail event (and on the layout's block): a deliberate, permanent difference is what `appliesOn` is for. Not a ledger line, because the issue would then close, and a ledger entry needs an OPEN issue | **DECISION** | `referenceCourses.importing.olderLayout`; doc 09 → "The older layout: a folder per class (#254)" |
| **#258** | Import the 2024–25 website-folder layout, if Windows needs it. If declined, `appliesOn: ["mac"]` on its trail event, as for #257. The Copy a Page half is owed either way, and is done in #247 | **DECISION** | `referenceCourses.importing.quartzCheckoutLayout`; doc 09 → "The 2024–25 layout" |

### Phase 7: Windows-only interface and the UI-test runner (5 issues). Decision gate: #101

| # | What it is | Kind | Where the rule lives |
|---|---|---|---|
| **#283** | Backups: LOGICAL sizes (`FileInfo.Length`), measured off the UI thread, deleting several at once, never the backup an open assistant can restore from, and `backups deleted`. The view is designed in WinUI terms | MATCH (rules) | `course-management.json` → `backups` (3+2+3); doc 09 → "Backups: what they take, and deleting several (#242)" |
| **#191** | Four window-level accelerators with no `ScopeOwner` (F2 is the sharpest). MEASURE with a dialog open first; then add a window-level "a dialog is open" signal | CHECK, then fix | no contract |
| **#214** | Measure the deploy panel and notice at `Measure(new Size(1, ∞))`. Expected to be fine. Close with the number | CHECK | doc 09 → "A blank window" |
| **#155** | The UI-test runner: a `startup.log` line when the app starts with redirected stdio; refuse to kill a BUSY app (live leases); sweep the leases a kill orphans | Windows-only | doc 12 → "Never start the app with its output redirected" |
| **#101** | A course code of "work" collides with the build workspace on Windows only. Reserve the name in both wizards, or accept it deliberately | **DECISION**, then MATCH if reserved | `course-management.json` → `courseCode.problems` if reserved |

**Count: Phase 0: 1 · Phase 1: 5 · Phase 2: 6 · Phase 3: 4 · Phase 4: 4 ·
Phase 5: 13 · Phase 6: 8 · Phase 7: 5 = 46.**

---

## 5. The batch-4 pieces still landing on the mac: where each goes

From the drafts in `scratchpad/drafts/`. Each joins the milestone when it
lands.

| Mac # | What reaches Windows | Where |
|---|---|---|
| #243 | Nothing: the mac's quit-script tests made hermetic. The lesson carries over only if Windows ever scans processes at quit | none |
| #287 | Two COMMENTS, not a new issue: `course could not be kept for reference` (a new event) on #241, and "every course not imported writes a line" on #244 | Phase 6 |
| #263 | A small new issue: reword `deploy.ps1:454` and `:499` ("live-reload script") in plain words, agreed with the mac's follow-up for `deploy.sh:722`/`:798` | Phase 1 |
| #238 | A new issue: the trail write race | Phase 3, first |
| #153 | A new issue: wire `siteHealth.marker.consoleCases` (4) into `SiteHealthContractTests`. KNOW: the overnight trail line is written only if the app later opens the section; moving it into the wrapper is your call | Phase 1 |
| #255 | FOLD into #241 and #244 (Obsidian add-ons left behind; 8 tree cases) | Phase 6 |
| #234 | KNOW only; the recommendation is **no issue** (doc 03 carries it). `test_preview_reach.py`'s text half must be green | none |
| #136 | FOLD into #272 as a comment, and retitle #272 | Phase 4 |
| #192 | A new issue: one `dotnet test` run on Windows paths, plus the stale comment in `NewCourseDialog.cs`. Closable in one session | Phase 1 |
| #189 | A new CHECK issue: one folder, one id, however it is spelled (case; NFC against NFD). Record the ids | Phase 4 |
| #167 | A new issue: the links question | Phase 5, step 12 |
| #94 | **No Windows draft exists.** Container recreation killing live previews is a Docker problem; the Windows preview has no container, so *inferred*: nothing owed | none |
| #249 | **No Windows draft exists.** The mac's accessibility tests are flaky on a Space that is not showing: mac test hygiene. *Inferred*: nothing owed | none |

The milestone for #167 and #238 is unsettled: each issue says v1.3.2 and a
comment on it says v1.4.0. Russell decides.

---

## 6. Open `windows` issues NOT on this milestone that touch the same code

These are not in the 46. Several share files with Phase 2 and Phase 3, so a
session will meet them whether or not they are in scope. **Russell: in or
out?**

- **The same frontmatter family as Phase 2:** #182 (restore orphans a
  continuation line), #186 (inserting into a block whose first line is
  indented), #188 (an indented `---` read as the closing fence), and #246
  (the build PUBLISHES a page it cannot parse; `decision`). All four are
  `mac`+`windows`, on v1.3.2. The mac's half of #181/#182/#186/#188 is on
  `origin/issue/181-visibility-writers-keep-key-with-value`.
- **Scheduled publishing, as Phase 3:** #212 (a scheduled publish finishes
  silently), #237 (two working folders share ONE scheduled task; #239 and
  #261 both work around it), #137 (a failed build still names a destination).
- **Publishing:** #227 (a relative folder with a colon prints "Published"
  into an empty folder).
- **Test hygiene a Windows session will trip over:** #285 and #179 (the unit
  suite reaches the real `%LOCALAPPDATA%\Plantoir`), #161 (zip-stamp cases
  part 2), #187, #164, #165.

---

## 7. The traps

**Building and running**

- **`MSB3027 … file is locked by "Plantoir"`** means a running app, **or** a
  stray `plantoir-mcp.exe` left over from a stdio probe. Stopping them both
  is allowed without asking. Say that you did.
- **Build with `-p:Platform=x64`.** Otherwise the "PT - Dev" shortcut runs
  yesterday's binary. Never relaunch the app for Russell.
- **`Stop-Process` is not Quit.** Delete the leases you orphaned in
  `<working folder>\courses\.internal\activity\*.lease`. A stale lease with a
  recycled pid is the one case the staleness check cannot see through, and
  this milestone makes leases matter more (#289).
- **Read the TOTALS line.** A typo in `--filter` exits 0 having run nothing.
  A dead test host prints no totals line at all.
- **Never start the app with redirected stdio** (ConPTY). The launcher gets
  EOF, or hangs, and it reads exactly like a broken toolchain. `DrivenApp`
  uses `UseShellExecute = true` for this reason.
- **There is no container on Windows, and WSL2 has no host GPU.** The build
  and the model both run natively (Vulkan, falling back to CPU). Do not
  build toward the WSL fallback in `FolderContainers`: #231 asks whether to
  delete it.
- **The test interpreter needs `python-frontmatter`** (#279) and runs with
  `PYTHONUTF8=1`. Temp-folder cleanup must tolerate Defender holding a
  handle. Fixture dates stay in the PAST. Classes that write the trail, the
  leases, or `%LOCALAPPDATA%\Plantoir\scheduled` belong in
  `SharedActivityState`.
- **The repository is LF.** Run `git config core.hooksPath .githooks` once
  per clone. The hook warns on CR (an editor writing CR CR LF once made 7,672
  insertions out of 264 lines).

**The contract**

- **The contract has a direction.** `--write-contracts` is mac-only. Never
  hand-edit a generated key; read which keys are generated from each file's
  own `generated.keys`. You MAY add authored cases. **The mac suite then
  goes red on purpose**, and a `mac` issue opened the same session is what
  makes it read as a request rather than as damage.
- **Name-keyed tests stay GREEN on a new key.** Nothing on Windows
  enumerates the top-level keys of `shared-rules.json`, `app-rules.json` or
  `course-management.json`, or the keys of the wording file (until #157).
  So "green" here does not mean "read". The census walker is the check.
  Deserialise the cases, never retype them. Assert completeness in both
  directions. Put a floor on every case count.
- **The named-gap rule.** A ledger entry is allowed only while an open issue
  on a LATER milestone owns the work, and never for a difference a teacher
  can see. For work Windows OWES, `appliesOn: ["mac"]` is not the way out.
  It is right only for a deliberate, permanent difference, such as a layout
  import Russell declines (#257, #258). The #231 quit exception is the one
  exception, and it ends by deleting both `appliesOn` keys when the work is
  adopted. A scenario cannot be ledgered at all (#260).
- **What the MODEL sees is a routing surface.** Never edit a tool
  description to steer the model (one sentence cost 20 of 110 probes). A
  reply answered in code (#281, #288) goes to the transcript ONLY; appending
  it to the model's conversation passes every wording test and lets the
  model act a turn later. A club's "meeting" wording never enters the model's
  copy or `plantoir-mcp`'s results (#274).

**.NET and Windows defaults that differ from the mac**

- `ToString("yyyy-MM-dd")` renders in the culture's CALENDAR (#144).
  `DateTime.TryParse("06:30")` means today (#193).
  `TimeZoneInfo.ConvertTimeToUtc` throws on a nonexistent DST time, where
  Foundation moves forward (#193).
- String checks must be ORDINAL. The mac's grapheme trap shows up inverted
  here, through culture-sensitive overloads (#247). Normalise to NFC only to
  COMPARE, never to write (#244, #247, #189).
- In PowerShell, `-match` and `Select-String` are case-insensitive by
  default, and `Select-String` under `$ErrorActionPreference = 'Stop'`
  throws on an unreadable file (#241, #136). `EnumerationOptions` skips
  Hidden items by default (#136).
- `File.Copy`/`File.Move` do not refuse a destination that differs only by
  case: use `FileMode.CreateNew` (#247). NTFS has no clone, so every large
  copy needs real progress (#244, #257). The read-only attribute travels
  through `shutil.copy2`, and a native build then publishes a hidden page
  (#241).
- `os.replace` fails over a file held open without `FILE_SHARE_DELETE`, and
  OneDrive may re-upload the result (#279).
- `File.AppendAllText` from two processes drops lines in silence (#238).
  `FileSystemWatcher` does not call back on the UI thread (#218).
- A reparse point (symlink or junction) is a LINK: never followed, never
  copied. Only a real `.lnk` counts as a shortcut (#255, #257, #258).
- `schtasks /SC ONCE` and a missed start: measure it; do not assume
  (#239). Name one task per code and section, machine-wide (#237, #261).

---

## 8. Decisions Russell must make, in the order the phases need them

1. **Before Phase 1: confirm how the ledger is used during this push.**
   `contracts/README.md` → "Named gaps" now carries one sentence on this:
   while no Windows release is being cut, an entry may name an open issue on
   this milestone. The ledger is then the milestone's burn-down list, and the
   milestone cannot close, nor a Windows release be cut, while any such entry
   remains. What Russell confirms: that no Windows release is planned before
   parity. If one is, that release's reds are defects, not gaps. The ledger
   will need areas for `wording` keys, `courseConfigKeys` and
   `modelTiers.requirements`. The alternative is to leave everything red
   until it is built, and then "did I break anything?" cannot be answered
   for weeks.
2. **Phase 2: #177** (labelled `decision`). Should a restore use the lenient shared fence finder
   (as the issue recommends), or stay strict on purpose?
3. **Phase 3: #231.** Delete the dead WSL fallback in `FolderContainers`, or
   harden it? The issue leaves this to "whoever owns that side". It is
   listed here so that somebody actually owns it.
4. **Phase 6: #257 and #258.** Does Windows import Russell's two older
   layouts at all (both labelled `decision`)? If not: `appliesOn: ["mac"]`
   on each layout's trail event and block, because it is a deliberate,
   permanent difference, and the issue closes.
5. **Phase 7: #101** (labelled `decision`). Reserve "work" as a course code in both wizards, or
   accept it. This needs a mac change too if it is reserved.
6. **Scope:** whether #167 and #238 belong to this milestone (the issues and
   their comments disagree), and the issues in section 6.
7. **Wording, which is Russell's:** "this Mac" in #286's sentence (propose a
   Windows line?), #230's home-folder sentence as read on Windows, and #263's
   rewording of two `deploy.ps1` lines, to agree with the mac.

(#155's "zero the std handles in `ConPtyProcess.Start`?" and #272's "does a
WinUI window hold its own copy of the settings?" are the Windows session's to
answer by measuring, not Russell's.)

---

## 9. The rhythm

- **Plan first** (WINDOWS-BOOTSTRAP §0): read, then write the plan for
  Russell, then STOP. Once he agrees, work autonomously. Do this per phase at
  minimum. The plan says where the contract disagrees with what Windows
  actually does. **Say so rather than "fixing" the app to match**: twice the
  contract was the thing that was wrong.
- **One branch per coherent piece**, `issue/<n>-<slug>` off `dev`, committed
  and pushed as you go (`git push -u origin issue/<n>-<slug>`). **Never
  merge into `dev` without Russell saying so in this session, about this
  piece.** After a merge he approves: `--no-ff`, then `git branch -d` and
  `git push origin --delete`.
- **Implement with the strongest model available (Opus in Claude Code). At
  least three independent reviews per piece:** the plan, then the
  implementation, then the fixes. Brief each reviewer adversarially and tell
  it that "nothing to act on" is an acceptable answer. Pass the model
  explicitly. **One final Fable sweep** over the whole finished piece, after
  the rebuild and the documentation pass. Check what a reviewer claims before
  acting on it. Record which model did which review.
- **Obligations back to the mac (rule 4), in the same session:**
  - a **`mac` issue** for anything the mac must DO: a proposed authored case
    (for example #196's cut-off scenario, #193's DST rows, #286's Windows
    sentence line, #239's "exempt" answer) with the case named and what the
    mac must implement; or a fault found here that the mac shares;
  - the **`documentation/` page** that owns the subject, for anything the
    mac need only KNOW (every measurement, with its NUMBERS and the
    HARDWARE; every option rejected, with the reason);
  - a **`GUI-IMPROVEMENTS.md` row** for anything a teacher can see;
  - the **closing comment** on the issue, as the record of what landed.
- **Trail (rule 5):** every feature a teacher can see writes its line, in a
  sentence a teacher would recognise. Never page content, never a
  credential.
- **Finish every piece the same way:** rebuild x64 so "PT - Dev" is current,
  clean up leases and any stray `plantoir-mcp`, bring the terminal back to
  the front, run the documentation pass (grep for what changed; fix doc 12,
  `PROGRESS.md` and the census rows the change made wrong), push, say it is
  ready, and STOP.

---

## 10. A suggested first week

| Session | Work |
|---|---|
| 1 | `git config core.hooksPath .githooks`; check that `python` and `python-frontmatter` are installed; pull `dev`; build x64; `dotnet test`. **Write the red list, with every failing test mapped to its issue.** Re-take the census with the walker. Fetch and read `origin/issue/159-settle-the-day-once`. Check whether any Windows work exists only on the local machine (#180). **Update the doc comment on `NamedGapLedger.cs`'s `Entry`** (the `Milestone` param says "LATER than the release being cut") so it carries the burn-down rule `contracts/README.md` → "Named gaps" now states. That file is Windows'; the mac does not edit `windows-app/`. Write the plan for Russell and put the section 8 questions to him. **Stop.** |
| 2 | Phase 0: #279's console filter, its trail event and its date cases, so the first build from `dev` shows no raw JSON. Then #230 and #134 (one-liners that are red on the first pull), and #190. |
| 3 | Ledger work, as decided. The trail-wiring source scan. #157's walker. #178. The #192 and #153 wiring if they have landed. |
| 4 | #144's `Dates.Iso` helper and the th-TH test. Then #284 (the shared `replacingKeyLine`). |
| 5 | #282 (the same finder and splice), then #200 B, which is the shipped "unpublishable copy". Three reviews each. The Fable sweep at the end of the week, over what is ready to merge. |

After week one, take Phases 2–4 in whatever interleaving keeps each branch
small. #238 comes with the rest of Phase 3's trail work, whenever its issue
has been opened; nothing waits on it. Phase 5 is next, as a chain. Phase 6 waits for #257 and #258.

---

## 11. What could not be determined from the repository

- **The real state of the Windows suite.** macOS cannot build
  `net9.0-windows`. Every red test named in section 3 comes from issue text
  and string searches, not from a run.
- **Which Windows features exist but are not ledgered.** String searches
  find none of the 27 missing trail events and none of the new config keys.
  But a behaviour can exist under another name. The ~80 wording keys are a
  name heuristic. #203 says its behaviour is already right. #169 says
  Windows shipped the restore first.
- **Whether work for #180 (or anything else) exists only on the Windows
  machine**, unpushed. (Whether the #159 branch merges was answerable from
  here: it conflicts only in `GUI-IMPROVEMENTS.md` and doc 10; see section 3.)
- **Every answer that needs Windows hardware:** Task Scheduler's handling of
  a missed start (#239); whether a WinUI window holds its own copy of the
  settings (#272); whether the folder-id pairs agree (#189); what the
  accelerators do with a dialog open (#191); the 45-second bound (#233);
  copy speeds under NTFS and OneDrive (#244, #247); the trail race loss rate
  (#238); OneDrive against the read-only attribute (#241).
- **Whether a Windows release is planned before this milestone closes.**
  This decides how the named-gap rule reads (section 8, item 1).
- **#94 and #249 have no Windows draft.** "Nothing owed" for them is an
  inference from the issue text.
