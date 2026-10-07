# Plantoir for Windows — Progress

## 2026-10-07 — the 1.4.3 release branch

Branch `issue/windows-1.4.3-release`. The Windows version is 1.4.3 (`<Version>` in `Plantoir.csproj`, `AppVersion` in `installer.iss`), and `PlantoirSetup.exe` joins the EXISTING v1.4.3 release, which the mac cut on 2026-10-04 with its DMG — no new tag. It is the first version the Windows updater installs (1.4.2 offers it). `website/updates/windows.xml` gains a 1.4.3 item (built with `--reparse-existing --change-log-path`, notes in `windows-app/release-notes/1.4.3.md`) and the Windows download card is unpinned. `WINDOWS-DIRECTOR-PROMPT.md` is deleted.

What landed on `dev` since 1.4.2, one line each (GUI rows 712–721 have the detail):

- **Bundle A, the assistant** (#432, #430, #436, #424, #411; rows 716–719): "Publish Unit 4, Day 3" in its exact form, "schedule a deploy at 6:30 am" and "cancel that scheduled deploy" are answered in code without the model; "schedule a deploy" with no time asks for one; a reply the smaller assistant is still writing after 30 seconds ends as cut off (measured: it ends 5 of 10 such replies — the other 5 had no line break — so a reply can still run to about 80 s); the Claude door works on every course in the folder; an outside assistant is held back only while a site is being BUILT, and a preview a deploy closed says "Closed for a deploy". #424 stays open for the conversational "don't send it in the morning after all".
- **Bundle B, rules and wording** (#438, #431, #426; rows 712–714): the computer is named by the contract's own `{machine}` sentences; a folder deploy that rebuilds says "deployed"; only "All Classes" or the recorded class folder is protected from removal; a screen reader names every icon-only button and tells a reference course from the live one.
- **Bundle C1, the updater and the feed** (#428 items 1 and 2; row 715): the update offer carries the notes of every newer release; the trail says when Plantoir updated itself; the feed ADDS an item per release, checked by `website/windows_feed.py` in every `build.py` run.
- **#448** (row 720): a scheduled deploy tells the teacher how it went, in a notification, every time.
- **The pictures** (#380, #370, #442, #428 item 6; row 721): every Windows picture on plantoir.app is a real window, photographed whole, staged by `--stage-scene`.

**Moved to v1.4.4 by Russell on 2026-10-07:** the dark title bar fix and the dark pictures.

Gates on this project's Windows PC (Intel i5-8365U, 16 GB, Windows 11 Pro build 26200), at `dev` `581c2f634`:

- `dotnet test`: Failed 0, Passed 2338, Skipped 0, Total 2338 (6 m 19 s).
- UI suite (`run-ui-tests.ps1`): first run Failed 2, Passed 51, Total 53 (23 m 18 s); both failures reproduced alone and were real — a `ToggleSwitch` and the icon-plus-text Preview and Deploy buttons had no accessible name (app fix, GUI row below), and the two-backups test sent its Ctrl-click too fast for the app (test fix). Second run Failed 0, Passed 53, Skipped 0, Total 53 (22 m 35 s). The installer was re-signed after that fix, so the shipped bytes carry it.
- `verify-deploy.ps1`: 37 passed, 0 failed, 0 skipped.
- `NamedGapLedger`: empty.

## 2026-10-03 — the 1.4.2 release branch

Branch `issue/windows-1.4.2-release`. The Windows version is 1.4.2 and its installer joins the v1.4.2 release; #424 moved to milestone v1.4.3. The updater (#337) is switched on: the feed and the public key are set, and `website/updates/windows.xml` is signed and committed. Gates on this project's Windows PC (Intel i5-8365U, 16 GB, Windows 11 Pro build 26200): `dotnet test` Failed 0, Passed 2243, Skipped 0, Total 2243; the UI suite 44 of 44 (20 m 35 s); `verify-deploy.ps1` 37 passed, 0 failed, 0 skipped; `NamedGapLedger` empty. The installer paths `/PLANTOIRUPDATE`, `/RELAUNCH`, `/NOCLOSEAPPLICATIONS` and `/RETURNTO` were run for the first time (documentation/11 has the table). The UI suite's first run was 41 of 44: at 200% display scale the Copy a Page picker gave its clickable point at twice its real coordinates, so three tests clicked the window behind and typed there — a harness fault, fixed in `DrivenApp.ClickMiddleOf` (documentation/12 → "Driving the real interface"). #380: the hero and the two colour figures are whole native window captures (`website/shots/windowshot`). #370: the six availability flags are true and the Windows card is unpinned. Still open on #380: the single-window Windows shots; on #370: Windows scenes for the v1.4.0 pictures.

## 2026-10-01 — bundle 10 ("parity remainder")

Branch `issue/bundle10-parity`. Done: #421 (start of year and the links checklist's Publish name a page whose settings cannot be added to, and count only what was put into draft or published), #422 (make room counts renames and links from what was written, names a write it could not finish — trail `making room did not finish every page`, `appliesOn: ["windows"]` — and matches declined pages by path), #420 step (a) (`includeLinked` gone: publish always takes what a page links to; the `followingLinks` cases run with no flag). #420 step (b), the two held descriptions, was MEASURED (pre-registered; this PC, the smaller assistant) and FAILED — EXC2O 161→150/220, ICS3U 160→123/220, teachers-say 220→210/250, `unpublish_pages` −11 trials, 0 inversions — so the text stays held in `measuredDepartures` — a permanent measured departure by Russell's decision, and #420 closes; the surface that ships (flag gone, text held) is better on EXC2O (161→190/220), level on ICS3U (160→160: `card: plan a publish` gained, `schedule a deploy` LOST 10→0 to `deploy_section`) and 4 points lower on teachers-say (220→210: `ctl cancel_scheduled` 10→0, declined) with, separately, ten turns at the token cap on "next day's lesson" that the score cannot see — those three regressions have their own issue (`research/ai-assist/windows-description-convergence-results.txt`, the dated note). Also (review R5): `PlanPublish` keys pages and links by path, so two pages sharing a file name no longer swap links, and an ambiguous name is asked about, each page named with its folder in the contract's `pageNameInFolder` shape. Also from Russell's answers: a section restore drops blank lines before a shared page's fence, as the mac does (Q8); the installer is per-user only (Q9); the club noun's `_meta` decision is in `file-formats.json` (Q10). `NamedGapLedger` still **empty**.

## 2026-10-01 — bundle 9 ("finish")

Branch `issue/bundle9-finish`. Done: #419 (the robocopy scan reads tracked files), #417 (the watcher's reds were a refused READ, not a partial record — the record is now read sharing ReadWrite|Delete; 30 of 30 runs green), #157 (`noCoursesYet`, `whatPublishingMeans`; `Briefing` retired), #308 (declined pages named on the plan and in every reply), #318 (already wired since bundle 5b; confirmed by a must-fail), #356 (SHA-256 pins in `fetch-runtime.ps1`). `NamedGapLedger` is **empty**. Open by ruling: #191 and #214 (a `[UiFact]` now MAKES each measurement — owed one run on an unlocked desktop), #414 (the one-process re-run found 0; the 856 run's certified count proves it ran a binary no commit contains, but not which part differed, and that is not a reproduction). #352: measured (pre-registered; this PC, the smaller assistant: model-seen 160→161 and 150→160 of 220, teachers-say 210→220 of 250, 0 inversions, 0 cut-offs) and moved — one description per tool, except `publish_pages`/`unpublish_pages`, held for the `includeLinked` behaviour (`research/ai-assist/windows-description-convergence-results.txt`). New: a `windows` issue for `publish_pages`' `includeLinked` (the behaviour #352's check found).

## 2026-10-01 — overnight parity run

Windows parity run, 2026-09-30 to 2026-10-01: eight bundles landed on `dev` in ten merges (every merge `--no-ff`), 106 issues worked. The suite went from **61 red to 0**: baseline `Failed: 61, Passed: 1486, Total: 1547` at `0d040a81`; now `Failed: 0, Passed: 2209, Skipped: 1, Total: 2210` at `0d36bd84` (the skip is the native-build test, which needs a runtime).

| Bundle | dev | Totals after |
|---|---|---|
| 1 plumbing | `cce2ca9e` | 53 / 1509 / 1562 |
| 2 writers | `8f35af79` | 34 / 1576 / 1610 |
| 3 trail, leases, scheduled deploys, quit | `53d22566` | 32 / 1636 / 1668 |
| 4 preview and publish | `84c23dac` | 27 / 1697 / 1724 |
| 5a assistant chain | `9ddf2a7b` | 19 / 1774 / 1793 |
| 5b assistant, the rest | `8752e296` | 17 / 1940 / 1957 |
| 6a course creation | `3d946d0d` | 9 / 2016 / 2025 |
| 6b reference, import, Copy a Page | `ed2da05e` | 7 / 2118 / 2126 |
| 7 clubs and settings | `905a20c3` | 0 / 2159 / 2160 |
| 8 Windows-only UI, runner, updates | `0d36bd84` | 0 / 2209 / 2210 |

- **Handed to the mac** (issues labelled `mac`): #407, #408, #409, #410, #411, #412, #413, #415, #416, #418.
- **`verify-deploy.ps1`** was run three times, after bundles 4, 5b and 6b: 37 passed, 0 failed, 0 skipped each time.
- **UI tests written and UNPROVEN** (the desktop was locked, so none has been seen passing): `ReferenceCourseUiTests`, `CopyAPageDialogUiTests`, `ClubSettingsUiTests`, `CourseSettingsSaveUiTests`, `ListTablesUiTests`, `MarksPoolRemovalUiTests` (updated), the four new `[UiFact]`s in `NewCourseWizardUiTests`, and the toast and All Backups dialog tests from bundle 8. `LinksChecklistUiTests` is the one that was run (passed 1/1, bundle 5b). Their first green run is owed on an unlocked desktop.
- **Leftover worktree folders** that `git worktree remove` could not delete (path too long; git no longer lists them, delete by hand): `plantoir-bundle5a`, `plantoir-bundle5b`, `plantoir-bundle5b-b`, `plantoir-bundle5b-c`, `plantoir-bundle6a`, `plantoir-bundle6b`, `plantoir-bundle6b-copy`, `plantoir-bundle7`, `plantoir-bundle8`, all beside the main clone in `Desktop\Developer`.
- **Still open:** #157 (two wording keys kept against it), #308 and #318 (partly landed), #352 (the #114 half needs a routing measurement), #370 and #380 (website flags and picture retake; no installer cut), #191 and #214 (unmeasured), #414 (Copy a Page fuzz: reproduce or explain the 856), #417 (a timing flake in `ScheduledPublishWatcherTests`).
- **#337 (updates)** was on `dev` but inert on this date (switched on 2026-10-03, above): no feed, no key, no release, and the download stays at 1.1.0. What Russell must do and test before a release is in the closing comment on #337 (key generation, the feed, and the unexercised installer paths `/PLANTOIRUPDATE`, `/RELAUNCH`, `/NOCLOSEAPPLICATIONS`, `/RETURNTO`, the refusal relaunch).

What each project in the solution is, and what state the app is in. First take
built overnight 2026-08-11 by Claude Code, per `WINDOWS-HANDOFF.md` — a file
since absorbed into [`documentation/`](../documentation/README.md) and deleted;
the assist subsystems folded
into `main` on 2026-08-14. Everything below was **verified live on the
maintainer's Windows 11 machine** (WSL2 + Ubuntu-24.04 + Docker Engine 29, no
Docker Desktop) unless marked otherwise.

## Layout

| Project | Role |
|---|---|
| `Plantoir/` | The WinUI 3 app (unpackaged, self-contained Windows App SDK, PerMonitorV2 DPI). Bundles the full toolchain recipe under `Toolchain/` and mirrors it into each working folder's `.toolchain/`. |
| `Plantoir.Core/` | All logic, UI-free: config round-trip, container naming, port leases, build freshness, archiver/restorer, section adder, ConPTY process, transcript builder, script runner, milestones, question parsing, failure explainer, catalogs, workspace/toolchain services — **and the whole assist subsystem** under `Assist/` (18 files): `AssistWorkspace`, `AssistAgent`, the plans (`PublishPlan`, `ReDatePlan`, `SyncPlan`, `InsertPlan`, `NewClassesPlan`, `CurriculumMentionsPlan`), `LinkGraph`, `SectionIndex`, `Timetable` and `TimetableMemory`, `DateAudit`, `UndoHistory`, `ScheduledDeploy` and `TaskScheduling`, and `WorkLease` (`Briefing` was retired on 2026-10-01, #157: `explain_publishing` says `AssistWording.WhatPublishingMeans`). |
| `Plantoir.Tests/` | xUnit suite that runs **without Docker**: `dotnet test`. No count is given here on purpose — it rots. Classes touching process-wide state (preview leases, the publish registry) share a serialized collection — see `SharedActivityState`. |
| `PtyDriver/` | Console harness that drives the launchers under a ConPTY with scripted prompt replies — how the E2E runs below were performed. |
| `Plantoir.UiTests/` | Drives the REAL built app through UI Automation (FlaUI/UIA3), for what a unit test cannot reach — see "Driving the real interface" below. Opt-in: skipped unless `PLANTOIR_UI_TESTS=1`, and compiled by a SOLUTION build (not by the per-project commands used day to day). References `Plantoir.Core` only, never the app project — the Windows App SDK has no business in a test host. |
| `Plantoir.Mcp/` | On `main` (`Plantoir.sln` lists it) and **it ships**: `publish.ps1` publishes it, copies `plantoir-mcp.exe` into the app's own output beside `Plantoir.exe`, and includes it in the signing list. A standalone MCP server exposing one working folder to an AI assistant. Load-bearing at runtime — `Plantoir/Services/ClaudeCodeLauncher.cs` looks for it beside the app, and `Plantoir/Services/McpClient.cs` launches it. See [its README](Plantoir.Mcp/README.md). |

## Where parity stands

> **"item N" in this file means the retired numbered list.** Until 2026-09-08
> outstanding work lived in a numbered list inside `WINDOWS-HANDOFF.md` (a file
> since deleted), and
> prose written before then cites it by number. Those numbers no longer resolve
> to anything: what was still open became [GitHub
> issues](https://github.com/russellgordon/plantoir/issues), and what was done
> is recorded in `GUI-IMPROVEMENTS.md`. The numbers are left in historical
> sentences rather than rewritten, because the sentence around one usually says
> what it was; `git log` has the list itself if a number ever needs chasing.

**The open work is in [GitHub
issues](https://github.com/russellgordon/plantoir/issues?q=is%3Aopen+label%3Awindows),
and this file no longer keeps a second copy of it.** Until 2026-09-08 it did —
a table here mirroring that numbered list — and the two drifted
exactly as often as anybody edited one and not the other. The count in this
section was wrong the last three times it was read, which is what settled the
argument for having one home rather than two.

Five items were open when the cutover happened, and they are now issues #66
and #68–#70 plus #99 (which absorbed the old item 42). Everything else on that
list was struck through as done; the shipped record of it is
`GUI-IMPROVEMENTS.md` and
[`documentation/13-windows-port-archive.md`](../documentation/13-windows-port-archive.md).

```bash
gh issue list --repo russellgordon/plantoir --label windows
```

Two more things worth knowing here:

- **The deploy gate exists, and item 36 decided what runs it (2026-09-07).**
  `verify-deploy.ps1` publishes to every destination and every pairing against
  real sites and fetches each one back: 36 passed, 0 failed on 2026-09-06. It
  needs three credentials, the network and about twenty minutes, and it creates
  real sites that nothing deletes — so **it stays opt-in and no suite runs
  it**, which was the right posture all along; what was missing was anybody
  being told. Now `.githooks/pre-commit` says so when a commit touches the
  publishing path (a warning — it never blocks, because those files change on
  16 of every 22 active days and a blocking hook would be `--no-verify`'d once
  and never fire again), and `RELEASING.md` requires a run with **nothing
  skipped** for a release that changes that path.

  **The bigger find was underneath it.** `verify.sh` runs fifteen shared
  `scripts/test_*.py` files on the mac; Windows ran **none** of them. All
  fifteen pass here, so `PythonToolchainTests` now runs every one inside
  `dotnet test` — 156 tests in about eight seconds, no Docker, no network, no
  credentials. A rejected first design (a stamp file recording when
  `verify-deploy.ps1` last passed, with a unit test reddening when the
  publishing files changed afterwards) is written up in `documentation/07-deployment.md`
  `git log -- WINDOWS-HANDOFF.md`, with the measurements that killed it — that
  write-up went with the retired list rather than into `documentation/`.
- **The unit suite is green**: 911 passed, 0 failed at the time this section
  was written; 945 after the folder-problems front end, and 979 once
  parity-tail was merged into it and the overnight capture was added. `dev` stood
  at 668 passed with 5 failing contract tests before this series; those five
  were each a real gap between what the contract says Windows does and what it
  did. **1,029 passed with 2 skipped** after item 29 wired the contract case
  lists this suite was not reading (2026-09-06), and **1,125 with 2 skipped**
  after item 31 wired the twelfth of them — `linkRewriting`, which item 29's
  audit missed because it was added the same day (2026-09-07); 1,150 with 2
  skipped once items 26, 31, 33 and 34 were all merged; and **1,153 with 1
  skipped** once item 25 made the wizard ask the skeleton question; and **no
  skips at all** once the frontmatter-key divergence was decided in this
  app's favour on 2026-09-07 (item 38) and its test rewritten to assert
  migration.

## Every contract case list is now RUN here (2026-09-06)

Closing the gap the 2026-09-06 contract audit found. Twenty-three lists the mac
suite ran and this one did
not read — none unreachable, each simply a test nobody had written.
`contracts/README.md` now names which class runs which, so the audit does not
have to be repeated.

**What matters for anyone adding to this suite** is the shape those tests
take, because the old ones were the wrong shape rather than absent:

- **Ask each list both ways.** Walking the contract and looking each case up in
  the code cannot notice a case the CODE has and the contract does not. Every
  gap item 29 found came from the reverse direction — an extra credential
  request, twelve extra MCP tools, sixteen extra tool arguments.
- **Assert completeness.** A hand-written mirror answers the cases that existed
  when somebody read the contract, and stays green when the mac adds one. Where
  cases are prose keyed to behaviour, map each to a named test by `nameof` and
  assert nothing is unmapped. Map to NAMES rather than draining a shared set:
  xUnit builds a fresh instance per `[Fact]` and fixes no order, so a set filled
  by ten tests and emptied by an eleventh passes on whatever happened to run,
  and reports nothing under `--filter`.
- **Read the source only against the thing that decides.** Several rules live in
  `Plantoir/` — the wizard, the composer, the report dialog — which this project
  does not reference. Reading their source is legitimate (`ParsingTests` does it
  for the `.ps1` launchers) but must be anchored: bare containment passed with a
  guard moved into a comment, and with it deleted from one of two arrow keys.
- **A new collection, `ProcessEnvironment`**, beside `SharedActivityState`, for
  tests that read or write process-wide environment variables. Same reason:
  `PLANTOIR_BUILD_ROOT` is global, and a class setting it while another calls
  `BuildOutputLocation.BuildsRootFor` is a rare flake that looks exactly like a
  production bug about where built sites go.

## Driving the real interface — what the table points at (2026-09-06)

The Layout table above says "see 'Driving the real interface' below" and, until
now, there was no such section: the prose lives in
[`documentation/12-windows-app.md`](../documentation/12-windows-app.md). Rather
than move it, here is what a session needs to know before running the suite,
and the one thing measurement added.

Run it **from the repository root**, not from `windows-app/`:

```powershell
.\run-ui-tests.ps1                 # all of it, about 4 minutes
.\run-ui-tests.ps1 -Filter "FullyQualifiedName~TheSheetCloses"
```

**Two switches, both added 2026-09-07 with item 35.** `PLANTOIR_UI_KEEP=1`
stops the run deleting its temporary folders — every test's, not just a failed
one's, since the teardown cannot know the outcome — and the runner prints each
path. A test that fails INSIDE the app has almost nothing to say from outside
it, and the evidence (that run's `startup.log`, its trail, its per-run
launcher log, its working folder) was being deleted on the way out. And the
runner now sweeps orphaned `powershell.exe`/`python.exe` children afterwards,
matched on **this run's token** — minted by the runner and folded by
`DrivenApp` into every folder name (`plantoir-ui-<run>-<8 hex>`) — because
matching the folder prefix would kill a parallel run's live launchers and a
developer tailing a kept folder's log. Killing `Plantoir.exe` kills only
`Plantoir.exe`: the whole-tree kill lives in `ConPty.Kill()` and runs when the
APP ends a task, not when the app is ended from outside.

It closes a running Plantoir before it starts, says so, and does not reopen it.
`--state-dir` moves the whole state folder for the run, so nothing of the
teacher's is touched.

**One test is intermittent, and it is worth knowing which.**
`SpecialFoldersHelpUiTests.TheSheetShowsAMarksFolderTickedButNotYetSaved`
failed once in a full run on 2026-09-06 and then passed twice — once alone (30
s) and once in a full run (6/6, 3 m 16 s). It is the test that ticks a marks
folder and waits for the sheet to be rebuilt through the dispatcher, and it
already retries for 20 seconds at half-second intervals. Nothing in that run
had touched the app or the UI project.

**It did it again on 2026-09-07**, on the item 35 branch: one failure in a
full run, then a pass alone (23 s) and a pass in a full run (9/9, 4 m 13 s) —
so roughly one full run in four across two days, on a branch that had touched
neither this test nor the view it drives. Second data point, same conclusion.

**So: if it fails, re-run it alone before believing it.** Recorded because an
intermittent nobody writes down is rediscovered as a regression by the next
session, which then goes looking for a cause that is not there. If it starts
failing in isolation, that is different and is a real finding — the retry is
generous enough that a genuine break would not hide behind it.

## A model layer exists ahead of its UI — four types nothing calls yet (2026-09-06)

`SpecialFolderRenamer`, `FolderPathRewriter`, `CloudSyncedFolder` and
`CloudSyncWording` are built, documented and under test, and **nothing in
`windows-app/Plantoir` calls any of them.** That is deliberate, not an
oversight: items 13 and 18 were taken as far as they could go without
inventing teacher-facing wording and dialogs, so the rules landed first and
the views are what remains.

Grep for callers and you will find none — that is the expected answer, and it
is written here so nobody concludes they have missed a wiring step or deletes
the types as dead code.

## Parity run, bundle 8: test hygiene, backups, the toast, updates (2026-10-01)

Branch `issue/bundle8-windows-ui`. Manual: doc 12 → "Bundle 8"; doc 11 →
"Updating itself on Windows".

- **The unit suite keeps out of the teacher's state** (#285, #179): a
  module-initializer redirect, a per-file source tripwire (Plantoir, Core,
  Mcp; PowerShell-in-strings too), a guard that throws on a real schtasks
  registration, and the wrapper's two run-time folders behind a TEMP-only test
  variable.
- **Backups** (#283, #187, #161): sizes (logical), All Backups with Extended
  selection and one counted button, held backups kept (this app's open
  conversations; an outside assistant's newest via its `assist` lease); a
  same-second backup waits for the next second; zipNames moments read against
  the Gregorian calendar. #101 confirmed by test, no change.
- **The scheduled-publish toast** (#324): posted by the run, a click decided
  from the contract's `onClick` cases. Unproven on a real click.
- **Accelerators** (#191): guarded under a ContentDialog; NOT measured.
  **#302**: the picker path bar's 520 limit dropped; not checked by eye.
  **#214**: not measured. (Bundle 9: both now have a `[UiFact]` that MAKES
  the measurement — `AcceleratorUnderDialogUiTests`,
  `PanelHeightUnderSqueezeUiTests` — owed one run on an unlocked desktop.)
- **The UI-test runner** (#155): startup.log says when stdio is redirected;
  never closes a busy Plantoir; sweeps only the killed pid's leases;
  `ConPtyProcess.Start` zeroes its std handles (measured: leak reproduced, then
  gone).
- **Updates** (#337): the rules, gates, wording, installer flags, the
  NetSparkle engine with our own dialogs, Check for Updates…, and all eight
  trail events. Inactive by design: the feed and key are empty until the
  first release that ships it.

## Parity run, bundle 6a: course creation and the smaller course pieces (2026-09-30)

Issues #169, #250, #252, #349 (the wizard's skeleton: declining the ready-made
pages offers the subject's skeleton and keeps its curriculum, the toggle
restores both ways, "an English skeleton"), #348 (the marks floor counts
folders on disk; Revert records the exclusions it put back), #316 (an
unreadable trail in a problem report), #320 (reopening the last working
folder, or saying why not), #355 + #389 (Get Ready for the Start of the Year:
the rule, the MCP pair, the section menu sheet and its undo; check_section's
third group), #345 (one coverage map per curriculum folder: the code rule,
plural resolution from the disk, protection, checkboxes, the rename, the
folders help, `curriculum maps built`) and #360 (the How I Teach row; every
assistant zip on the trail). The Starting Content decisions moved into Core
(`WizardStructure`, `NewCourseAnswers`) with six goldens from the old rule.
Ledger entries deleted: ten trail events, three wording keys from #355 plus
two from #360, `curriculum_folders`, and the declined-skeleton newCourse case.
Still open from these issues, said in `documentation/12-windows-app.md`: the
start-of-year Go does not stop and restart the preview, the club case waits for
#274, and
`courseIsBeingCopied` (the course is not counted busy while `plantoir-mcp`
zips it).
## Parity run, bundle 6b: reference courses, importing, Copy a Page (2026-10-01)

- **#241 / #298 — courses kept for reference.** Marker read strictly, school
  years, the shelf rule, Keep a Copy (staged, claimed, one failure line), the
  NTFS lock (deny entries; `ReferenceLock`), every deploy door refusing on the
  marker alone (15, tabled in `documentation/12-windows-app.md`), the MCP write
  gate on each tool's own ReadOnly flag, the withheld interface and the
  read-only summary, upkeep on every folder read. The shared build no longer
  publishes a hidden page whose file is read-only (`_writable`).
- **#244 / #245 — Import Courses for Reference….** Modern layout only (the
  older layouts are mac-only by decision). Stream copy with a bytes progress
  bar and Stop; 507 MB in ~5.4 s on this PC.
- **#247 / #258 / #384 — Copy a Page** (see the bundle's ready note).
- **Not measured yet:** OneDrive with locked files, an elevated token, and
  what Obsidian for Windows shows on a locked page (so
  `obsidianOpensThemForReading` is not said here).

## Parity run, bundle 5a: the assistant chain through AssistAgent (2026-09-30)

Branch `issue/bundle5a-assistant-chain` (built on `issue/159-settle-the-day-once`).
Done, in order, all at the seam where `AssistAgent` makes a call: #159 (the day
settled once — reviewed, and #144's four excusals retired), #180 (course and
section bound to the window, another course refused), #196 (`finish_reason`
carried out of `IChatModel.Ask`; stopped or unreadable replies run nothing and
are wound back), #262 (an empty call runs only when the window supplies
everything; `noCourseNamed`), #217 (hide is unpublish; an echoed reply refused
and wound back), #193 + #260 (deploy at a time in code, settled once with DST
handled, scheduled card asks about the moment; `plantoir-mcp` refuses a bare
time), #281 + #288 (asked, or spelled, in the transcript only), #261 (what a
schedule replaces, read by task name). New test classes:
`WindowBindingContractTests`, `CutOffAnswerTests`, `HideAndEchoContractTests`,
`DeployAtATimeContractTests`, `TimeAskedInCodeTests`, `ScheduleReplacesTests`.
The reasoning is in `documentation/10-local-ai-assistant.md` → "The Windows
half of the assistant chain".

## Parity run, bundle 5b: the assistant, the rest (2026-09-30)

Branch `issue/bundle5b-assistant-rest` (with bundle 5a merged in). Done: #350
(a tool the model was not offered is refused), #352's #197 half (a page list
naming no page; whole-unit openings; an open-ended publish refusal Windows never
had), #344 (settings read at the call; the schedule card read the window's
snapshot), #165 (a partial publish answers), #164 (argument names on the
trail), #203/#342 (the walk stops at a class both ways, and says so), #359
(Markdown-style links; check_section names ten), #305 ("What does X link to?"
in code, transcript only), #340 (How I Teach tools), #210 (Codex door; start-up
not measured, Codex not installed). Partly: #114 (needs a routing
measurement), #392/#399/#405 (the links checklist's LOGIC, record and release
are done and contract-tested; the WinUI sheet, the menu item and when it is
shown are not built). Manuals: doc 10's "On Windows" sections; doc 12 → "The
links checklist on Windows".

## Parity run, bundle 4: preview and publish mechanics (2026-09-30)

Branch `issue/bundle4-preview-publish`. Done: #278 (address read by whole
lines), #233 (the quiet after the server line bounded, three outcomes, trail
line), #286 (forty port blocks, the sentence, the launcher trail line),
#386 (no preview of a section being deployed: window, assistant, preview.ps1),
#391 (windowless deploy/rebuild `--non-interactive`, exit 3 named), #395
(Cloudflare remade, from the app's and plantoir-mcp's own runs), #304 (partial
publish folder refused; deploy.ps1 resolves once), #358 (fingerprint rule 2),
#319 and #307 (measured; the re-probe now binds loopback too). Checked, nothing
to change: #393, #401. Then completed on the same branch: #272 (Preview
Again, the saved-settings sentences, both events), #357 (Deploy and the
schedule sheet read the saved file), #395 (the overnight Cloudflare leg is
captured). Measurements and reasons:
`documentation/12-windows-app.md` → "Preview and publish mechanics that match
the mac (bundle 4)" and `documentation/03-launcher-scripts.md` →
"preview.ps1's own port walk…".

## Parity run, bundle 3: the trail, leases, scheduled deploys and quit (2026-09-30)

Branch `issue/bundle3-trail-leases`. The scheduled deploy is Plantoir now, not a
baked PowerShell script, and every rule decided at its moment lives there.

- **The trail keeps every line** (#303): a named mutex round each append.
  Measured two processes × 500 lines: 4,444 of 5,000 kept before, 5,000 after;
  the share-flag fix alone kept 4,512 and was rejected.
- **Leases both ways, take-then-check** (#289): another program's build,
  publish OR preview declines a build (never a write); Deploy claims before it
  stops the preview; `plantoir-mcp` stops its own launcher before leaving.
  `workLeases.declining` (32 since #438; the two `copy` cases
  marked `appliesOn: ["windows"]` run here only), `.liveness` (17 of 19), `workLease.bodyCases` (7).
- **A scheduled task runs `Plantoir.exe --run-scheduled-deploy "<name>"`**
  (#347): the lateness window (#239), a ten-minute wait for the course (#289),
  whether it still stands, the settings as they are now, then the wrapper.
  Verified end to end through the real Task Scheduler on this PC. Old tasks
  drain. `theDestination` (11 of 12), `howLateIsTooLate` (10),
  `storedValueCases` (7), `savingSettings.scheduledDeploys` (5).
- **One task per section per working folder** (#309), found by the folder its
  job names; records filed under the folder id.
- **Removing a course turns its deploys off FIRST** (#239), asked of the
  scheduler, this folder only; the contract's sentences.
- **A failed build is `buildDidNotFinish`** (#297); `whichKind` (6) through the
  real wrapper.
- **The notice arrives while the section is open** (#218): one app-wide
  watcher; records moved in whole (40 of 40 readable at the first event,
  against 18–21 of 40 written in place).
- **Quitting asks** before leaving a publish or preview build (#231), never on
  a log-off; the WSL release is hardened (leases, a launcher scan, docker must
  answer, System32 paths). Both `appliesOn: ["mac"]` keys deleted.
- **Every destination named** (#400, #404); the unpublished-classes note gone.

Not built: #324 (clicking the toast — the toast itself, #212's Windows half, is
first; both built minimally in bundle 8). Manuals: doc 07 → "On Windows since bundle 3"; doc 09 → "On Windows
since bundle 3 (#289)" and "(#231)"; doc 09 → "On Windows: a sharing violation".

## Parity run, bundle 2: frontmatter and page writers (2026-09-30)

Branch `issue/bundle2-writers` (on top of bundle 1). Every writer of a page's
frontmatter now finds the block the way the build does and takes a key's whole
value with it; every link reader and rewriter shares one definition of code.

- **Dates are Gregorian whatever the PC's region** (#144): `DateText`, taken
  from the cloud branch `claude/nifty-mendel-q8ixto` (cherry-picked, not
  re-derived).
- **One fence rule, asymmetric** (#308/#188): the closing fence is column-0
  dashes only; the opening may be indented. **One `ReplaceKeyLine`** (#284) for
  `SetTitle`, `SetCreated` and the section copy and scaffold. **No key goes
  where the block has no column-0 place for it** (#186): `SetDraft` and
  `SetCreated` answer `NoRoomForAKey`. *Not yet*: the plan, re-date and
  make-room callers naming the declined pages (four wording keys still ledgered
  on #308).
- **Adding a section** (#282) finds `----`, a blank line before the fence and a
  trailing space, splices by line, keeps CR LF, and records `section added`.
- **Restoring a section** (#177/#182) uses the shared finder, carries each key
  WITH its lines, and counts and says the pages it had no room on.
- **Duplicating a class** (#200): a forced-hidden copy can be published again
  (B), the guard asks what the insertion created (A), the refusal admits other
  classes may have moved (C); the plan card warns the undo will not help (#346).
- **Renaming the word for a unit** (#158): Course Settings → Rename…, the whole
  feature, off the UI thread. The sheet is compiled, not driven.
- **Links** (#339/#318/#338): `MarkdownCode` (0 disagreements with
  `markdown_code.py` over 12,490 pages), escaped pipes, angle-bracket links in a
  folder rename.
- **The unreadable front page gets its own card** (#300).

Contract lists run here for the first time: `datesAndTitles.writingCases` (16),
`sectionNumbers.addingKeysToAPage` (8), `backups.restoringOneSectionsKeys` (6),
`readingALink.cases` (52), `renamingTheUnitWord.cases` + `.linkCases` (7 + 6).

## Parity run, bundle 1: red means something again (2026-09-30)

The suite pulled on 2026-09-30 (dev `0d040a81`) was **61 failed, 1486 passed**,
every red mapped to an open issue (`plantoir-windows-run\logs\baseline-red-list.md`
on Russell's machine). Bundle 1 (branch `issue/bundle1-plumbing`) was plumbing,
so that "did I break something?" has an answer again:

- **`NamedGapLedger` is the parity milestone's burn-down list** — 58 trail
  events, 140 wording keys, 7 config keys, 3 model requirements and 3 contract
  cases held open BY NAME against their issues; `documentation/12-windows-app.md`
  → "Named gaps" has the table. A green totals line now means "green with the
  debts the ledger names", and the ledger fails the day one is paid.
- **`AssistWording_MatchesContract` walks `assist-wording.json`** by reflection
  in both directions (#157); green since parity bundle 5a (#193's `deployApproval`).
- **`ActivityTrailWiringTests`** is the source scan the mac has: every declared
  event must have a call site. All do; `assistant asked` is written by
  `NotePrompt`, and the scan knows that.
- **`PLANTOIR_DATED:`** is hidden from the console and recorded on the trail,
  from the console and from a scheduled publish's record (#279).
- **A payload course gets its manifest's marks pool** (#317).
- **Five shared Python test files that failed on Windows pass or skip with a
  reason** — one was a real shared bug (`build_site._is_draft` did not read
  CR LF, and the native build writes CR LF copies).

## ONE activity-trail event is declared without an emitter (2026-09-06; six were then, and all six have callers since 2026-09-07)

> **Superseded 2026-09-30:** `ActivityTrailWiringTests` now checks this on
> every run, including `AssistantAsked`'s helper; the paragraph below is kept
> as the history of why the scan exists.

`ActivityTrail.Event` named `folder renamed`, `folder created`,
`synced folder noticed`, `synced folder accepted` — and, found 2026-09-06,
`settings saved` and `settings could not be saved`, which belonged to no
unbuilt view at all: `CourseSettingsView.Save_Click` wrote the config and
recorded nothing, while the mac records both. All six are emitted now: the
settings pair since item 28 (2026-09-07), the synced-folder pair the same day
with item 18's views, and `folder renamed` / `folder created` with item 13's
rename sheet (`CourseSettingsView`, `RenameFolderAsync` and
`CreateFolderForNewEntry`). The one member still without a caller is
`AssistantAsked`, whose line is written by `NotePrompt` without going through
the enum — a recount should not be surprised by it. Check with `grep -c` per
member rather than trusting this paragraph: a green suite that is green on a
promise is exactly the kind of thing a later session should be able to find,
and `ReclaimedProcesses` is the worked example of parsing something out and
putting it on the trail.

**There was a FIFTH, and this section did not name it: `folder problem
repaired`.** Declared when the trail was built, still with no call site on
2026-09-06 — it got one that day, when item 21's front end landed (`Models/
SiteHealthRepair.cs`). It is recorded here because the omission is the
interesting part: this section was written by listing the events somebody
remembered were promised, and a fifth had been dead long enough to stop being
remembered. The honest way to keep this list right is
`grep -c` per enum member, not recollection.

## The subsystems that table does not name

- **A built-in local AI assistant.** `Views/AssistWindow.xaml` holds the
  conversation, `Plantoir.Core/Assist/LocalModel.cs` runs a small model natively on
  the Windows host with Vulkan GPU acceleration (no account and no internet), and
  `Services/McpClient.cs` drives the same `plantoir-mcp` Claude Code drives — one
  tool surface, two front ends.
- **Claude Code integration.** `Services/ClaudeCodeLauncher.cs` writes
  `%LOCALAPPDATA%\Plantoir\assist\mcp-<CODE>.json` and launches `claude` with
  `--mcp-config … --strict-mcp-config`, so a teacher's own MCP servers are
  neither used nor disturbed. Both doors sit on a course's context menu:
  **Revise with Claude…** (only when Claude Code and the server are both
  present) and **Revise with local AI assistant…**.
- **A cross-process lease protocol**, `Plantoir.Core/Assist/WorkLease.cs`.
  Four kinds — `assist`, `preview`, `publish`, `build` — as files under
  `courses/.internal/activity/`, so the app and the server can see each
  other's work. Only a *build* is exclusive; previewing during a conversation
  is the point.
- **Scheduled deploys**, `Assist/ScheduledDeploy.cs` + `TaskScheduling.cs`,
  reached from the sidebar's Schedule Deploy… and from the assistant, sharing
  one refusal path so the two cannot drift.
- **Three publishing destinations**, not one: `deploy.ps1` handles Netlify,
  Cloudflare Pages and a plain folder.
- **Folder-problem checks, surfaced in two of the three places they can
  happen.** The shared Python checks a course's folders during every build and
  prints one `PLANTOIR_HEALTH:` line per problem;
  `Plantoir.Core/Models/SiteHealthFinding.cs` parses them,
  `SiteHealthRepair.cs` puts right the two that can be put right, and
  `Views/FolderProblemsDialog.cs` shows the rest. The app's preview and
  publish are covered, and so is the assistant (`Plantoir.Mcp/
  LauncherRunner.cs` lifts findings out and `SiteHealthFinding.Appending`
  says them). **The scheduled deploy is covered too, differently**: it runs
  with the app closed, so its wrapper captures the build's output per run,
  copies the marker lines into a per-course-and-section record, and the
  section's own view reads that record the next time it is opened — consumed
  as it is read, and cleared by a clean run.

## Proven end to end

Screenshot- or exit-code-verified on real hardware: the launchers
(`setup.ps1 --install-example` built the image locally from the recipe and
installed EXC2O; `preview.ps1 EXC2O 1` served HTTP 200; `deploy.ps1 EXC2O 1`
took its token from Windows Credential Manager and put 233 files live over
https); the app itself (folder picker → sidebar → section view, with Preview
building and embedding the live site in the app's WebView2, and Deploy running
end to end in-app — "Uploading your pages… 25 of 230" at Step 7 of 8, the
count parsed from launcher output); and the wizard's answer pump against the
real `setup_course.py`, exit 0 with a full course scaffolded, using the same
`NewCourseCreator.PumpAnswers` the Create Course button uses.

**Since bundle 11 (2026-10-01) through the real window, by `[UiFact]`s that run
the real launchers** (opt-in, `run-ui-tests.ps1`): the wizard's Create then
Preview, with the served front page read back over HTTP, the preview pane
shown to have loaded that same address (status 200), and Stop silencing it (`WizardToPreviewUiTests`); Import Courses for
Reference… through the Windows folder picker, the course shelved by year and
locked on disk (`ImportForReferenceUiTests`); a course kept for reference —
summary, no Deploy, pages locked, Keep a Copy and its refusal
(`ReferenceCourseUiTests`); Copy a Page through its checklist, both copies
hidden, the published destination without them, and three refusals
(`CopyAPageEndToEndUiTests`); and Deploy to a folder, the published folder
read back (`PublishToFolderUiTests`). Doc 12 → "A test that runs a launcher".

## The hard-won platform lessons (do not relearn these)

1. **ConPTY std-handle hygiene.** A process whose own stdio is redirected leaks
   stale pipe handles into its pseudo-console child; `wsl.exe` then reports
   "the input device is not a TTY". A GUI app is naturally clean; test
   harnesses must get their own console (ShellExecute / `Start-Process`).
2. **ConPTY soft-wrap duplication.** Re-rendered wrapped lines arrive with the
   boundary character doubled — hence the runner's 400-column pseudo console,
   so no real line wraps.
3. **PowerShell 5.1 + `$ErrorActionPreference='Stop'` + wsl stderr.** Any
   redirected call site (`*> $null`) turns wsl's stderr into terminating
   ErrorRecords; the launchers' `docker` wrapper relaxes the preference around
   the wsl call.
4. **Container-name parity.** Everything hashes the folder's PHYSICAL path
   (true on-disk casing via `GetFinalPathNameByHandle`, symlinks resolved)
   plus `"\n"`, SHA-256, first 8 hex — `FolderContainers` in Core and all
   three launchers agree byte for byte.

## Spec coverage

Tracked in one place only: the **Windows status** section of
[`GUI-IMPROVEMENTS.md`](../GUI-IMPROVEMENTS.md) (264 rows as of 2026-08-18,
entries 1–264 assessed). Nothing here duplicates it, because a second copy is
a copy that goes stale — that count itself had been reading "179 rows" for
days after the log passed 250.

**What to do with that assessment** is the open `windows` issues, plus
[`documentation/12-windows-app.md`](../documentation/12-windows-app.md) →
"What is built and what is missing". Much of that page was written by reading
this app's source from the mac, read rather than run — `dotnet` is not
installed there — so treat it as a starting point, and report anything it gets
wrong in a `mac` issue.

## Work done from a cloud (Linux) session — 2026-09-27

The first piece of this port built off the Windows PC: [#144](https://github.com/russellgordon/plantoir/issues/144),
in a Claude Code cloud session (Ubuntu 24.04, no Windows App SDK). What that
kind of session can do, measured on the day and written for the next one:

- `Plantoir.Core`, `Plantoir.Mcp`, `PtyDriver` and `Plantoir.Tests` build and
  run on Linux with the .NET 10 SDK (Microsoft's apt repository no longer
  carries 9.0) plus the .NET 9 runtime from `dotnet-install.sh`. `Plantoir/`
  (WinUI 3) and `Plantoir.UiTests` do not build there at all.
- `dotnet test` on Linux: **1538 tests, 111 red before the change** — every
  red one either a Windows path (`C:\Users\…` expected, `CreateFileW` in
  `FolderContainers`) or a handover the parity plan already lists. The gate
  for a cloud session is therefore **"no NEW red"**, judged by diffing the
  failing-test list before and after, not by the totals line alone.
- The WinUI project's edits (#144: one line in `App.xaml.cs`, one line plus a
  refusal block in `SectionScheduleDialog.cs`) were NOT compiled. The first
  `dotnet build Plantoir/Plantoir.csproj -c Debug -p:Platform=x64` on the PC
  is the check, and "PT - Dev" is stale until then.

## Known rough edges for the next session

- **The native (containerless) toolchain shipped in v1.1.0 — this is no
  longer a branch, and the container path is gone, not merely deprecated.**
  `windows-native-toolchain` merged (`b356a1fc` onward) and the WSL2/Docker
  fallback was deleted outright in `5925e102` — a copy of the app with no
  bundled runtime now fails fast with "This copy of Plantoir is missing its
  website builder. Reinstall Plantoir, then try again." (`setup.ps1`,
  `preview.ps1`, `deploy.ps1`); there is no fallback path left to take. Run
  `windows-app/Vendor/fetch-runtime.ps1` once before building — it fetches
  Node 20, Python 3.11 embeddable, patched Quartz with win-x64 node_modules,
  wrangler and the emoji font into `windows-app/Vendor/runtime/` (~600 MB,
  gitignored), which the build robocopy-mirrors beside the app. The
  launchers run natively whenever `PLANTOIR_RUNTIME` (set by `ScriptRunner`)
  or the installed app's own runtime folder exists — that is now the only
  code path. Builds land in `%LOCALAPPDATA%\Plantoir\builds\<folder-id>`
  (OneDrive-safe). Verified by hand, both before and after an adversarial
  pass (`abb28380`) that found and fixed six real defects (a stop sweep that
  silently did nothing, a preview-port announce race, a course-creation
  failure mode, and stale WSL2/container wording leaking into the trail and
  the UI): native build (57 s cold), serve (HTTP 200), stop (kills the tree,
  frees both ports), Netlify delta deploy — all with no container, and the
  app-driven flow end to end, including the setup wizard's keyboard path
  under ConPTY (auto-answered course creation, no ConPTY stall).
- **The WSL2 auto-install path (`Install-WindowsSubsystem`) described here
  previously is gone, not merely superseded.** It existed to provision WSL2
  + Docker on a fresh PC for the container toolchain; the native runtime
  removed that need entirely, and `Install-WindowsSubsystem` is no longer
  present in the launchers (confirmed by search — no remaining references).
  A fresh PC now needs only the .NET 9 runtime the app is self-contained
  against; there is no VM, no reboot-for-VM-platform-features case, and
  nothing here to verify.
- The toolbar can still truncate at narrow widths. The window minimum **is**
  enforced at 900×600 (`MainWindow.xaml.cs`, `PreferredMinimumWidth` /
  `PreferredMinimumHeight`); the opening size is not 900×600 but a share of
  the display's work area, clamped, so it looks right at any scale.
- The preview accelerators exist — Ctrl+R, Alt+Left, Alt+Right, declared at
  view scope in `Views/SectionDetailView.xaml` and handled in its code-behind.
  ~~What is missing is a **Preview menu-bar item**~~ — added 2026-08-22
  (`MainWindow.xaml`, handoff item 1). Corrected 2026-09-06: this paragraph
  outlived the work by a fortnight, and anyone planning from it would have
  built it twice.
- ~~Two paths proven underneath but never click-driven in-app: the wizard's
  Create button (the `setup.ps1` + answer-pump path ran to completion via
  PtyDriver), and the new-site dialog a BRAND-NEW section's deploy raises —
  the verified deploy was a repeat publish to an existing site.~~ Closed
  2026-09-07 as handoff item 35. The Create button is now click-driven by
  `NewCourseWizardUiTests`; the new-site dialog is a hand-driven check with a
  written procedure (`documentation/12-windows-app.md`), because reaching it
  needs a real saved Netlify token and creates a real site. It was listed as
  item 35 on 2026-09-06 — before that it was written down here and indexed
  nowhere, so no session planning from the numbered list could see it, which
  is the whole reason the audit added it.
- Smoke-test hooks, all driving the real button code paths
  (`MainWindow.xaml.cs`, `RunAutomationHooks`): `--auto-select CODE N`,
  `--auto-preview CODE N`, `--auto-deploy CODE N`, `--auto-course CODE`,
  `--auto-wizard`, `--auto-createcourse CODE [SECTIONS]`,
  `--auto-addsection CODE`.

## Parity run, bundle 7: clubs, Course Settings, today's class (2026-10-01)

- **#274 — clubs.** `ClassPageNaming` on every class-planning path with no
  default; numbered next page after the latest date, make room keeping gaps,
  no whole-unit path, numbered refusals before the dates are asked for; the 60
  class/meeting sentences in the teacher's copy only (`_meta`), the model's
  copy byte-identical (`ClubNounTests`); the meeting card phrasings and the
  numbered make-room family; a club's shelf; "This is a club" in the wizard;
  Course Settings' locked rows and the disabled Rename…; `course created` says
  a club; the front-page pointer found by the class it names (`writtenAs`).
- **#390** — the panel's words follow the box. **#387** — `SettingsSaveState`,
  `settings save held back`, legacy per-section seeding, "Language and region",
  "Standard colours", the label-word scan. **#269** — the lists are tables
  (+/−, Delete) and Hide/Expandable one table. **#406** — Preview offers today's
  class (42 cases), Not Today, two trail events.
- **#392 / #399 remainders** — published-before pages keep their date in the
  assistant's publish; `linksIntoHiddenPagesWillBeOffered` only when the build
  made the checklist; the two laid-out naming cases run.
- Ledger entries deleted: every one owned by #274, #387, #392 and #406
  (3 config keys, 51 wording keys + 1, 3 trail events, 2 case lists).
  [UiFact]s written and UNPROVEN (desktop locked): `ClubSettingsUiTests`,
  `CourseSettingsSaveUiTests`, `ListTablesUiTests`, `MarksPoolRemovalUiTests`
  (updated).
