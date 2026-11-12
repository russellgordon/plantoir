# The installer harness (#700)

`installer.iss` includes `..\installer-running-work.iss`, the check that runs
before the installer changes any file: a preview's server is ended, a build or
a deploy running from the install folder is waited for, and a silent install
refuses (exit code 7, nothing changed) when the wait runs out. This folder
proves that code without touching the real Plantoir.

| File | What it is |
|---|---|
| `harness.iss` | A tiny installer with its OWN AppId (`{D7A92D73-…}`, never Plantoir's), installed per-user into `%LOCALAPPDATA%\Temp\plantoir-installer-harness\app`. It includes the same `installer-running-work.iss` and calls it as `installer.iss` does, and carries the same `[InstallDelete]` lines (the driver and `InstallerRunningWorkTests` refuse a difference). |
| `StandIn.cs` | A few-KB program installed as `node.exe`, `python.exe`, `Plantoir.exe`, `plantoir-mcp.exe` and `llama-server.exe`, so a test can run "a preview serving", "a build" or "work that never ends" from the harness's folder. Built with the .NET Framework's `csc.exe`. |
| `run-harness.ps1` | Builds both, installs harness version 1, starts stand-ins in each shape, runs version 2 with the app's own update arguments, checks the exit code, the tree and the processes, and uninstalls. `-MustFail` breaks one rule at a time in a COPY of the include and checks the case it protects goes wrong. |

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows-app\installer-tests\run-harness.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File windows-app\installer-tests\run-harness.ps1 -MustFail
```

About three minutes for the cases and two for the must-fails on the build PC. Needs Inno Setup 6 (`ISCC.exe`, where `publish.ps1` finds it). Exit 0 when
every case passed, 1 otherwise, 2 when it could not run. Every installer run is
`/VERYSILENT /SUPPRESSMSGBOXES`, so no wizard, no box and no sound. The real
Plantoir's folder and uninstall key are fingerprinted before and after, and the
run fails if either changed.

**Not part of `dotnet test`, deliberately.** It installs and uninstalls a
program, takes minutes, ends processes it started, and uses a fixed folder, so
two runs at once (two agents, two worktrees) would break each other.
`InstallerRunningWorkTests` holds the source (the include is included and
called, the `[InstallDelete]` lines, the sentences); this harness proves what
the code does; `RELEASING.md` step 3a runs it at every Windows cut.

**What it cannot prove**: anything about the real installer's 1.2 GB tree and
real processes (the measured upgrade in `RELEASING.md` step 3a), the
hand-run wizard's Retry box (it makes a sound), and a process that starts in
the gap between the last look at `ssInstall` and `[InstallDelete]`.
`documentation/12-windows-app.md` → "The installer waits for work that is
still running (#700)".

Never use `Start-Process -Wait` here: in Windows PowerShell it waits for every
descendant, and a refused Install and Reopen starts Plantoir, which never
exits; the first run of this driver hung on exactly that.
