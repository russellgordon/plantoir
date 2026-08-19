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

- **The fresh-PC path is verified in place; only the restart-pending
  variant is not.** The launchers' `Install-WindowsSubsystem` (branch
  `windows-wsl2-auto-install`, 2026-08-19) was driven end to end on this
  machine after removing its WSL package and distro: stub state detected,
  WSL + Ubuntu installed on one UAC click, engine provisioned silently,
  image built, container mounted — stopping only at the wizard's TTY, which
  the app provides. Not driven: the restart-pending branch (this machine's
  VM-platform features were already enabled, so no reboot was demanded);
  it is asserted from its printed lines, which the contract cases pin.
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
