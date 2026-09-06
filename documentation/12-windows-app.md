# 12. The Windows App — Plantoir

[◀ Previous: Release Strategy](11-release-strategy.md) · [Back to index](README.md)

`windows-app/` contains **Plantoir** for Windows: the same product as
[the macOS app](09-mac-app.md), built by somebody who cannot read the Swift,
against the same [shared contracts](../contracts/README.md). It wraps the same
command-line toolchain in a graphical interface — a sidebar of courses and
sections, a settings form mirroring the wizard, an embedded preview, one-click
deploys, a New Course wizard, and the same on-device assistant.

**This page is architecture and platform difference.** For what is BUILT and
what is still missing, read [`windows-app/PROGRESS.md`](../windows-app/PROGRESS.md),
which carries the live parity table; for the reasoning behind decisions,
[`WINDOWS-HANDOFF.md`](../WINDOWS-HANDOFF.md) and
[`MAC-HANDOFF.md`](../MAC-HANDOFF.md). Those three are maintained as work
happens. This page is not a status report and should not be read as one.

---

## The solution

| Project | Role |
|---|---|
| `Plantoir/` | The WinUI 3 app. Unpackaged (`WindowsPackageType: None`), self-contained, Windows App SDK included, `net9.0-windows10.0.19041.0` / `win-x64` — so a teacher installs no runtime. Bundles the toolchain recipe under `Toolchain/` and mirrors it into each working folder's `.toolchain/`. |
| `Plantoir.Core/` | Everything with no UI: configuration round-trip, the build location, port leases, freshness, archiver and restorer, the script runner, failure explanations, catalogs — and the whole assistant under `Assist/`. This is where a rule belongs unless it cannot be expressed without a window. |
| `Plantoir.Tests/` | xUnit, and it runs without Docker or a network: `dotnet test`. Classes touching process-wide state share a serialized collection — see `SharedActivityState`. |
| `PtyDriver/` | A console harness that runs a command under a ConPTY and answers prompts from scripted rules. It exercises the same `ConPtyProcess` the app uses, which is the point: it tests the launchers the way the app drives them. |
| `Plantoir.Mcp/` | A standalone MCP server exposing one working folder to an AI assistant. It SHIPS: `publish.ps1` copies `plantoir-mcp.exe` beside `Plantoir.exe` and signs it. |

The one house-style rule worth stating: **this is ordinary idiomatic C#, LINQ
included, and that is deliberate.** The Swift follows Russell's machine-wide
style rules; the C# does not, because the two apps are written by different
hands in different languages and one style stretched across both would buy
nothing a teacher can see. Do not "bring the C# into line".

---

## The biggest difference: there is no container

The macOS app runs the toolchain inside a Colima/Docker container. **Windows
does not, and has not since the native-runtime rewrite.** `preview.ps1` refuses
outright without the bundled runtime — *"This copy of Plantoir is missing its
website builder. Reinstall Plantoir, then try again."* — and there is no
container branch left to fall back to.

**The runtime travels beside the executable.** `NativeRuntime` resolves
`<the folder Plantoir.exe is in>\runtime` — so a Debug build uses the copy
under `bin\`, not an installed one — and `ScriptRunner` passes it to every
launcher child as `PLANTOIR_RUNTIME`. A launcher run by hand honours that
variable first and only then falls back to
`%LOCALAPPDATA%\Programs\Plantoir\runtime`, which is where the installer puts
it. Either way the folder is recognised by a `manifest.json` INSIDE it, and it
carries its own Python, Node and Quartz.

`Enter-NativeRuntime` in the launchers points the shared Python at it: it sets
environment variables and returns the interpreter's path, and starts nothing,
because `--stop` mode must never start anything.

Three consequences that catch people out:

- **Anything reading `/proc` does nothing here.** The shared rule for stopping
  a section's preview lived behind `/proc` for months, so on Windows it
  silently stopped nothing while a preview's sync watcher overwrote publishes.
  `stop_preview.read_snapshot()` now dispatches to `Get-CimInstance
  Win32_Process` natively. See [the build pipeline](05-build-pipeline.md).
- **`verify.sh` and `verify-deploy.sh` do not run here.** They are bash and
  expect `docker` on PATH. The Windows counterpart is `verify-deploy.ps1`,
  which publishes to every destination and every pairing against real sites
  and fetches each one back. It needs credentials and the network, so it is
  opt-in and wired into nothing.
- **The local model runs natively too**, with Vulkan GPU offload, falling back
  to multi-threaded CPU. Neither platform runs the model in a container, and
  the reason is measured: a 3,411-token prompt took ~175 s in one and a few
  seconds natively.

---

## Where Windows keeps things

Everything the app owns lives under `%LOCALAPPDATA%\Plantoir\`:

| Folder | What |
|---|---|
| `builds\<folder id>\` | Built websites, OUTSIDE the working folder. `<CODE>\section<N>\public` is the built site; `work\<CODE>\section<N>` is the Quartz project a preview serves from. |
| `Logs\` | The activity trail — the breadcrumb file a problem report gathers. |
| `scheduled\` | The wrapper script each scheduled deploy runs. |
| `scheduled\pending\` | Sentinels a finished scheduled deploy leaves for the app to pick up next time it runs. |
| `assist\`, `models\` | The assistant's MCP configuration (`mcp-<CODE>.json`) and the model weights it downloads. |
| `WebView2\` | The embedded preview's user-data folder. |
| `settings.json` | The app's own settings — and, since Windows has no system window restoration, the remembered-windows list IS the restoration mechanism. |

**The folder id is a hash, and it must never be derived twice.** The launcher
computes it as `$WORKDIR_ID` and the app as
`FolderContainers.FolderIdentifier`; the derivation itself is documented at
that method, which is the one place to change it. It hashes the folder's
PHYSICAL path — true on-disk casing with symlinks, junctions and SUBST drives
resolved through `GetFinalPathNameByHandleW`, not `Path.GetFullPath`, which
keeps the caller's casing and the junction.

**Ask `BuildOutputLocation` for a build path; never spell `.merged_output` by
hand.** Builds lived inside the working folder before they moved out, so code
still naming that path is reading somewhere nothing writes to. That is not
hypothetical: the check deciding whether a publish needs to rebuild was doing
exactly this, answering from the old location while the publish came from the
new one. (The launchers' own help text still mentions `.merged_output`; those
are container-era defaults, overwritten once a native runtime is found.)

---

## Credentials

Publishing tokens live in **Windows Credential Manager**, under
`containerized-quartz-netlify`, `containerized-quartz-cloudflare` and
`containerized-quartz-cloudflare-account`.

**A credential written by `cmdkey` is invisible to Plantoir.** The launcher's
`CredApi` reads and writes the credential blob as **UTF-8**; `cmdkey` writes
**UTF-16**. So a credential can show up perfectly in `cmdkey /list` and decode
inside the app into a NUL-riddled string that authenticates nothing — and the
teacher is asked for a token that is already stored, with nothing to say so.
Write through the launcher's own `CredApi`, and never advise `cmdkey` in a
support note.

---

## Running the launchers: ConPTY

The app shells the same `setup.ps1` / `preview.ps1` / `deploy.ps1` a
command-line teacher runs, under a **ConPTY**, so the launchers behave as they
do in a real console — progress markers, prompts and all. `ScriptRunner`
watches the output for progress markers and advances the stage bar as each one
appears.

**Read your own `.ps1` files rather than copying the mac's marker list**, and
note that `markerOrigins` in the contract is the MAC's set — it still lists
markers about containers starting, which nothing here prints. The list this app
actually matches is `TaskMilestones.cs`, and `TaskMilestoneLauncherMarkerTests`
reads the real `.ps1` files so a launcher rewrite that drops a line fails the
suite instead of silently stalling a teacher's progress bar.

That test exists because this failed silently once: four markers had been
copied verbatim from the mac's `.sh` scripts, describing events — a one-time
machine setup, a container starting — that stopped happening here when the
native runtime replaced the container. The first two or three stages of most
progress bars could never be reached, so the bar sat at 0% until a later, real
marker jumped it forward several steps at once.

---

## Scheduled deploys

There is no `launchd`. `TaskScheduling` writes a wrapper script into
`%LOCALAPPDATA%\Plantoir\scheduled\` and registers it with **Task Scheduler**
(`schtasks`). The wrapper fingerprints the section, builds it, deploys to each
destination un-chained (one failing must not stop the others), and writes a
sentinel the app picks up next time it runs.

What it registers is the SHELL: `schtasks /TR` gets
`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File
"<wrapper>"`. (The mac's equivalent lesson — register the job as the APP, or
the operating system announces that "bash" wants to run in the background —
belongs to macOS Background Items and has no counterpart here. It is recorded
in `WINDOWS-HANDOFF.md` as something to weigh, not as something this code
does; do not go looking for app-registration code.)

One rule learned the hard way:

- **Run it `-NonInteractive`.** Nobody answers a question at 6 a.m. Without
  it, a `Read-Host` anywhere in the chain blocks until Task Scheduler's own
  limit and the site is simply never updated, with nothing to say why. Note
  the flag reaches PowerShell's own prompts only: a Python `input()` in
  `deploy.py` is guarded separately, by `sys.stdin.isatty()`, which takes the
  default silently rather than refusing — see [`TODO.md`](../TODO.md).

---

## Publishing: the destination is an argument

`deploy_target` in `course_config.json` is read by the **app**, which turns it
into a `--target` flag. **No launcher reads that key to choose a
destination** — `deploy.ps1`, `deploy.sh` and `deploy.py` all default to
Netlify and change destination only on `--target`. (`build_site.py` does read
it, but for working out a site's domain, not for deciding where to publish.) Anything driving a launcher directly must pass the flag itself;
see [deployment](07-deployment.md), where the failure that sentence caused is
recorded.

---

## Working on this app

**A fresh clone needs the runtime fetched first.** It is roughly 600 MB and is
deliberately not committed — this repository ships recipes, not binaries — and
the build mirrors it beside the executable:

```powershell
cd windows-app
.\Vendor\fetch-runtime.ps1        # REQUIRED once per clone
dotnet build Plantoir/Plantoir.csproj -c Debug
dotnet test  Plantoir.Tests/Plantoir.Tests.csproj
```

Skip the fetch and everything still BUILDS — and then every launcher refuses
with "This copy of Plantoir is missing its website builder", which reads like a
broken install rather than a missing step. (`Vendor/fetch-llama.ps1` is the
same arrangement for the assistant's engine.)

**Stop any running copy before building** — a running app holds
`Plantoir.Core.dll` open and the build fails with `MSB3027 … file is locked
by: "Plantoir"`, which reads like a corrupt build rather than an open window.
A stray `plantoir-mcp.exe` produces the identical error and is the one people
misdiagnose.

**When a round of changes looks done, build for `x64`** so the "PT - Dev"
Desktop shortcut runs it:

```powershell
dotnet build Plantoir/Plantoir.csproj -c Debug -p:Platform=x64
```

A plain `dotnet build` does not write there.

---

## What this page does not cover

Deliberately, so there is one home for each and not two that drift. The macOS
page explains several of these for that platform; the Windows equivalents live
in [`windows-app/PROGRESS.md`](../windows-app/PROGRESS.md), which is maintained
as work happens:

- **The embedded preview** — WebView2, and the `127.0.0.1` question that was
  measured and found to be a no-op here.
- **The assistant's own window**, the model running natively with Vulkan, and
  the second door: `ClaudeCodeLauncher` writes an MCP configuration and starts
  `claude` with `--strict-mcp-config`, so a teacher's own servers are neither
  used nor disturbed. See [the assistant](10-local-ai-assistant.md) for what
  the assistant IS.
- **Window and state restoration**, archived courses, problem reporting, and
  the `WorkLease` protocol that keeps two windows from building the same
  section at once.
- **What is built and what is missing.** `PROGRESS.md` carries the parity
  table; `WINDOWS-HANDOFF.md` carries the numbered list of outstanding work
  and the reasoning behind past decisions.

---

[◀ Previous: Release Strategy](11-release-strategy.md) · [Back to index](README.md)
