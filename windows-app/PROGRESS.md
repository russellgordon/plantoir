# Plantoir for Windows — Progress

What each project in the solution is, and what state the app is in. First take
built overnight 2026-08-11 by Claude Code, per
[`WINDOWS-HANDOFF.md`](../WINDOWS-HANDOFF.md); the assist subsystems folded
into `main` on 2026-08-14. Everything below was **verified live on the
maintainer's Windows 11 machine** (WSL2 + Ubuntu-24.04 + Docker Engine 29, no
Docker Desktop) unless marked otherwise.

## Layout

| Project | Role |
|---|---|
| `Plantoir/` | The WinUI 3 app (unpackaged, self-contained Windows App SDK, PerMonitorV2 DPI). Bundles the full toolchain recipe under `Toolchain/` and mirrors it into each working folder's `.toolchain/`. |
| `Plantoir.Core/` | All logic, UI-free: config round-trip, container naming, port leases, build freshness, archiver/restorer, section adder, ConPTY process, transcript builder, script runner, milestones, question parsing, failure explainer, catalogs, workspace/toolchain services — **and the whole assist subsystem** under `Assist/` (18 files): `AssistWorkspace`, `AssistAgent`, the plans (`PublishPlan`, `ReDatePlan`, `SyncPlan`, `InsertPlan`, `NewClassesPlan`, `CurriculumMentionsPlan`), `LinkGraph`, `SectionIndex`, `Timetable` and `TimetableMemory`, `DateAudit`, `UndoHistory`, `ScheduledDeploy` and `TaskScheduling`, `Briefing`, and `WorkLease`. |
| `Plantoir.Tests/` | xUnit suite that runs **without Docker**: `dotnet test`. No count is given here on purpose — it rots. Classes touching process-wide state (preview leases, the publish registry) share a serialized collection — see `SharedActivityState`. |
| `PtyDriver/` | Console harness that drives the launchers under a ConPTY with scripted prompt replies — how the E2E runs below were performed. |
| `Plantoir.UiTests/` | Drives the REAL built app through UI Automation (FlaUI/UIA3), for what a unit test cannot reach — see "Driving the real interface" below. Opt-in: skipped unless `PLANTOIR_UI_TESTS=1`, and compiled by a SOLUTION build (not by the per-project commands used day to day). References `Plantoir.Core` only, never the app project — the Windows App SDK has no business in a test host. |
| `Plantoir.Mcp/` | On `main` (`Plantoir.sln` lists it) and **it ships**: `publish.ps1` publishes it, copies `plantoir-mcp.exe` into the app's own output beside `Plantoir.exe`, and includes it in the signing list. A standalone MCP server exposing one working folder to an AI assistant. Load-bearing at runtime — `Plantoir/Services/ClaudeCodeLauncher.cs` looks for it beside the app, and `Plantoir/Services/McpClient.cs` launches it. See [its README](Plantoir.Mcp/README.md). |

## Where parity stands (2026-09-06)

`WINDOWS-HANDOFF.md`'s numbered list is the index, and it was corrected on this
date after drifting in both directions — item 5 had been finished since August
with its headline still reading as open work. **Thirty-six of its forty
items are done**, counted 2026-09-07; items 21, 23, 24 and 29 landed on
2026-09-06 (the folder-problems front end, the same findings reaching the assistant,
the overnight run's findings being captured and reported the next morning, and
the contract case lists this suite was not reading); items 33 and 34 — the
refusal of a folder named `index.md`, and the per-finding repair report as
contract cases — struck on 2026-09-07, along with 13, 17, 18, 19, 25, 26, 27, 28, 30, 31, 32,
35 and 38 the same day. Items 35–37 were added the same day by an audit of
these two documents (`556646e2`, a Windows session, 2026-09-06 — the numbers
have shifted since). **Four are open as of 2026-09-07: 36, 37, 39 and 40.**
36 and 37 are decisions rather than code, 39 is a check and a re-read, and
**40 is the only one that is code**. 37, 39 and 40 all wait on the mac; only 39
and 40 came FROM it, 36 and 37 having been raised by that Windows audit.
Neither 39 nor 40 had a row in the table below until they were added here —
item 39 was written up at 09:33 on 2026-09-07 and given no row for twelve
hours, which is exactly the drift the rule below exists to stop.

**Count them rather than trusting this line.** It read "sixteen of its
twenty-four" on a list that had grown to 32 items with eleven of them open,
seven of which this table did not name at all. These two commands count it, run
from the repository root — a plain `grep` over the whole file also counts every
other numbered list in it, of which there are many:

```bash
awk '/^### What is still genuinely outstanding/,/^## Windows no longer runs/' WINDOWS-HANDOFF.md | grep -c '^[0-9]\+\. '
awk '/^### What is still genuinely outstanding/,/^## Windows no longer runs/' WINDOWS-HANDOFF.md | grep -c '^[0-9]\+\. ~~'
```

The first is the total; the second is how many are struck, which is how many
are done.

**Striking an item in `WINDOWS-HANDOFF.md` means striking its row here too**,
in the same session. This table is the second place the same fact lives, and a
second place is only worth having if both are updated together — the whole
reason the count above went wrong is that one of them was.

What is genuinely left, smallest first:

| Item | What is left | Size |
|---|---|---|
| ~~19~~ | ✅ Done 2026-09-07 — `working-folder.txt` is written by the app and adopted retroactively; the launch-time sweep removes only builds whose working folder the system says is not there. | — |
| ~~30~~ | ✅ Done 2026-09-07 — Delete beside Restore in the detail panes, the picker's breadcrumbs with the main bar's affordances, and Rename Course in the File menu with F2. | — |
| ~~32~~ | ✅ Done 2026-09-07 — the folders-help jargon sweep scans only what the product writes, keeps the four fixed names, and reaches the no-curriculum-folder branch. | — |
| ~~28~~ | ✅ Done 2026-09-07 — the scheduled-deploy dialog names the unpublished classes, the main window comes forward for an assistant build when hidden, settings saves reach the trail, and the assistant window remembers its placement per section. | — |
| ~~31~~ | ✅ Done 2026-09-07 — `Uri.EscapeDataString` replaced by a contract-driven encoder in both branches of `Spelled`; `FolderPathRewriterTests` deserialises every `linkRewriting` case. | — |
| ~~36~~ | ✅ Done 2026-09-07 — decided: `verify-deploy.ps1` stays opt-in (it makes real sites), `.githooks/pre-commit` warns when a commit touches the publishing path, `RELEASING.md` requires a nothing-skipped run for a release that changes it, and the real win — all fifteen shared `scripts/test_*.py` now run inside `dotnet test`, which nothing here did before. | — |
| ~~37~~ | ✅ Done 2026-09-07 — Russell chose WINDOWS' wording, not the mac's, and it is now `shared-rules.json` → `specialNames.contentStructureTip`: the literal is gone from `CourseSettingsView.xaml.cs`, `SpecialNames.ContentStructureTip` is the single source, and three facts pin it. "on this page" became "here" (matching `removeLeavesTheFolderOnDisk` in the same view) and "folders" became "folders and files" — the caption sits under four lists, two of them FILE lists, and both apps had promised only the folder half of what `build_site.py` actually does. The mac owes the adoption and is not red meanwhile; it is at the top of `MAC-HANDOFF.md`'s "Open". | — |
| 41 | Shared Python, found here 2026-09-07: `_dropping_excluded_items` matches `excluded_items` case-insensitively while every other consumer matches exactly, so `build_site.py` gives two answers in one file. **Do not fix it by case-folding the live path** — exact matching is the deliberate rule (`gradedFolders.choices.walk.excludedItems`, reasoned in `GUI-IMPROVEMENTS.md` row 412), and case-folding breaks that case and re-introduces the app/build disagreement 412 rejected. Full write-up in `TODO.md`; `WINDOWS-HANDOFF.md` item 41. Gateable here now that `dotnet test` runs the shared Python. | Small |
| 39 | From the mac, after its test host stopped segfaulting: check whether `Plantoir.UiTests` can CRASH its host rather than fail an assertion (the shape to look for is a modal torn down inside a layout pass; the honest signal is the test TOTALS, never the exit code), and re-read `shared-rules.json` → `siteHealth.repair.oneAlertAtATime`, whose reason has been strengthened. Added to `WINDOWS-HANDOFF.md` on 2026-09-07 and never given a row here. | Small |
| 40 | Code, from the mac: `TheRowsAreTheContractsRowsInTheContractsOrder` builds ONE course, which has a curriculum folder, so the retired placeholder sentence could come back unguarded. Loop `specialFoldersHelp.cases` instead — the mac's fix ports line for line, traps included. | Small |
| ~~18~~ | ✅ Done 2026-09-07 — the choice at the folder picker and the dismissable notice for a restored folder both exist, and `synced folder noticed` / `synced folder accepted` are emitted. | — |
| ~~17~~ | ✅ Done 2026-09-07 — `CourseConfiguration.RecordOnDisk` (a fresh-read recorder beside an untouched `Write`) and the interrupted-rename record under `courses/.internal/renames`. | — |
| ~~27~~ | ✅ Done 2026-09-07 — “Restore Section N…” puts a section back to how it was when the conversation started; the assistant now saves one copy per conversation rather than one per change. | — |
| ~~26~~ | ✅ Done 2026-09-06 — the marks checklist offers folders nested up to four levels deep (`GradedFolderChoices`), and the frozen pool is fed from the same list. | — |
| ~~25~~ | ✅ Done 2026-09-07 — the wizard asks the skeleton question with the mac's sentences, writes `use_skeleton`, and the structure editor shows the skeleton's folders. | — |
| ~~35~~ | ✅ Done 2026-09-07 — the Create button is three `[UiFact]` cases in `NewCourseWizardUiTests` (suite 6 → 9, green in 4 m 12 s); the new-site dialog became a written hand-check, because `deploy.ps1`'s Credential Manager target is hardcoded and `--state-dir` does not redirect it. Found on the way: started with `UseShellExecute = false` the app is handed the `dotnet test` host's PIPE std handles, which leak into the ConPTY child — every launcher then fails in one second with an empty transcript. `ConPtyProcess.Start`'s own CAUTION had already said so. | — |
| ~~13~~ | ✅ Done 2026-09-07 — the rename sheet, the apply method, every key carried across and `class_folder`/`curriculum_folder` materialised; Add creates the folder, Remove says it stays. | — |
| ~~22~~ | ✅ Done 2026-09-06 — the "Folders Plantoir uses" sheet, now shared as `shared-rules.json` → `specialFoldersHelp` rather than living inside a view. Two cases proposed back to the mac. | — |

Two more things, one of which is now ON that list:

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
  publishing files changed afterwards) is written up in `WINDOWS-HANDOFF.md`
  item 36 with the measurements that killed it.
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

WINDOWS-HANDOFF item 29. Twenty-three lists the mac suite ran and this one did
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

## ONE activity-trail event is declared without an emitter (2026-09-06; six were then, and all six have callers since 2026-09-07)

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

**What to do with that assessment** is the ordered list in
[`WINDOWS-HANDOFF.md`](../WINDOWS-HANDOFF.md) → "Where Windows actually
stands", written 2026-08-17 by reading this app's source from the mac. It was
read rather than run — `dotnet` is not installed there — so treat it as a
plan to start from, and report anything it gets wrong in `MAC-HANDOFF.md`.

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
