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
| `Plantoir.Mcp/` | On `main` (`Plantoir.sln` lists it) and **it ships**: `publish.ps1` publishes it, copies `plantoir-mcp.exe` into the app's own output beside `Plantoir.exe`, and includes it in the signing list. A standalone MCP server exposing one working folder to an AI assistant. Load-bearing at runtime — `Plantoir/Services/ClaudeCodeLauncher.cs` looks for it beside the app, and `Plantoir/Services/McpClient.cs` launches it. See [its README](Plantoir.Mcp/README.md). |

## Four activity-trail events are declared but not yet emitted (2026-09-06)

`ActivityTrail.Event` names `folder renamed`, `folder created`,
`synced folder noticed` and `synced folder accepted`. All four are in
`contracts/shared-rules.json` → `activityTrail.mustRecord`, and
`ContractTests.SharedRules_ActivityTrailEvents_Exist` compares that list
against the enum — so declaring them is what makes the suite green.

**Nothing raises any of them yet**, because the features that would are only
half built: WINDOWS-HANDOFF item 13's rename sheet does not exist (the model
layer — `SpecialFolderRenamer`, `FolderPathRewriter` — does), and item 18's
two views do not exist (the detection and the wording do).

This is written here rather than left in a commit message because a green
suite that is green on a promise is exactly the kind of thing a later session
should be able to find. **When either feature's front end lands, the events
must actually be recorded** — the count and the names are in the contract
entries, and `ReclaimedProcesses` is the worked example of parsing something
out and putting it on the trail.

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
  What is missing is a **Preview menu-bar item**; Back/Forward/Reload are on
  the toolbar only.
- Two paths proven underneath but never click-driven in-app: the wizard's
  Create button (the `setup.ps1` + answer-pump path ran to completion via
  PtyDriver), and the new-site dialog a BRAND-NEW section's deploy raises —
  the verified deploy was a repeat publish to an existing site.
- Smoke-test hooks, all driving the real button code paths
  (`MainWindow.xaml.cs`, `RunAutomationHooks`): `--auto-select CODE N`,
  `--auto-preview CODE N`, `--auto-deploy CODE N`, `--auto-course CODE`,
  `--auto-wizard`, `--auto-createcourse CODE [SECTIONS]`,
  `--auto-addsection CODE`.
