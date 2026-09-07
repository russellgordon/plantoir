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
| `Plantoir.UiTests/` | Drives the REAL built app through UI Automation (FlaUI/UIA3), for what a unit test cannot reach — see "Driving the real interface" below. Opt-in: skipped unless `PLANTOIR_UI_TESTS=1`, and compiled by a SOLUTION build (not by the per-project commands used day to day). References `Plantoir.Core` only, never the app project — the Windows App SDK has no business in a test host. |

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

Everything the app owns lives under `%LOCALAPPDATA%\Plantoir\` — or wherever
`--state-dir` points, since every row below hangs off `AppDataRoot` rather than
computing its own path (see "The flags the app answers"):

| Folder | What |
|---|---|
| `builds\<folder id>\` | Built websites, OUTSIDE the working folder. `<CODE>\section<N>\public` is the built site; `work\<CODE>\section<N>` is the Quartz project a preview serves from. Each `builds\<id>\` also holds `working-folder.txt`, naming the working folder it belongs to; at launch the app deletes any builds folder whose named working folder is under the home folder and the system says is NOT THERE (error 2 or 3) — never one that is merely unreachable. |
| `Logs\` | The activity trail — the breadcrumb file a problem report gathers. |
| `scheduled\` | The wrapper script each scheduled deploy runs. |
| `scheduled\pending\` | Sentinels a finished scheduled deploy leaves for the app to pick up next time it runs. |
| `assist\`, `models\` | The assistant's MCP configuration (`mcp-<CODE>.json`) and the model weights it downloads. |
| `WebView2\` | The embedded preview's user-data folder. |
| `settings.json` | The app's own settings — and, since Windows has no system window restoration, the remembered-windows list IS the restoration mechanism. (`AssistWindowPlacements`, beside it, is deliberately NOT replayed: restoring an assistant window would load a multi-gigabyte model unasked, so it remembers placement only and is a separate type.) |

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
note that `markerOrigins` in the contract classifies markers from BOTH sides —
it still lists ones about containers starting, which nothing here prints. The
list this app actually matches is `TaskMilestones.cs`, and two test classes
hold it to the contract:

- `TaskMilestoneLauncherMarkerTests` reads the real `.ps1` files, so a launcher
  rewrite that drops a line fails the suite instead of silently stalling a
  teacher's progress bar.
- `MilestoneContractTests` runs `markerOrigins` itself. Every marker here that
  the contract calls **shared Python** must still be printed by something under
  `scripts/`; every marker the contract does NOT name must not be printed there
  either, which is what caught the two example-course markers nobody had
  classified; and the shared-Python steps of each mac milestone list must
  appear in this app's list for the same task, in the same order, so a step the
  mac gains is not one this side quietly stops showing. The mac's own launcher
  phrasings — the five in `markerOrigins.knownDivergence.macOnlyLauncherMarkers`
  — are read from the contract rather than copied here, because a hand-kept
  list of the other platform's words goes stale the day that platform changes
  them.

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

## The flags the app answers

None of these is for a teacher; each exists so something can drive the app.

| Flag | What it does |
|---|---|
| `--capture-marketing-shots <dir> [--theme light\|dark]` | Photographs the app's windows for plantoir.app. One appearance per process, with the OS switched into it first. |
| `--hero-window <theme>` | Stages a real window for the hero composite and stops, so the Python harness can photograph it beside Obsidian and Edge. |
| `--state-dir <dir>` | Keeps this run's ENTIRE Plantoir folder somewhere else. |
| `--auto-select CODE N`, `--auto-preview CODE N`, `--auto-deploy CODE N`, `--auto-course CODE`, `--auto-wizard`, `--auto-createcourse CODE [SECTIONS]`, `--auto-addsection CODE`, `--details` | Older test hooks that drive the interface from the command line — select a section, press Preview, open the wizard. |

The `--auto-*` family is read in `MainWindow`'s `RunAutomationHooks`, at WINDOW
construction rather than in `OnLaunched`, which is why they compose with
`--state-dir`: the state is redirected before the first window exists.


**`--state-dir` is what makes a UI test safe to run**, and it is worth knowing
exactly how far it reaches. It moves everything under
`%LOCALAPPDATA%\Plantoir` for that run: settings, the breadcrumb trail, the
startup log, downloaded models, built sites, scheduled-deploy wrappers and
their finished sentinels. It does NOT move Credential Manager, and it does not
reach a CHILD process. **Quote the path**: the raw-argument fallback splits on
spaces.

**The LAUNCHERS are the sharp edge, and they are the exception most likely to
catch somebody out.** `preview.ps1`, `deploy.ps1` and `setup.ps1` compute the
builds root from `$env:LOCALAPPDATA` themselves, and `TaskScheduling` bakes the
same into the wrapper script it registers. So a redirected run that PREVIEWED
would look for its build where the launcher did not put it, and one that
SCHEDULED a deploy would register a REAL Task Scheduler task whose sentinels
land in the teacher's real pending folder. Neither is done by any test, and a
test that drives Preview is the obvious next thing somebody writes — this is
the paragraph they will have read first. `plantoir-mcp.exe` resolves its own
paths too.

**One launcher IS run from a test now**, and the reasons that is safe are
narrower than they look. `NewCourseWizardUiTests` presses the wizard's Create
button, which runs `setup.ps1`. **Two guards, neither enforced by anything:**

1. `setup.ps1` sets `PLANTOIR_BUILD_ROOT` to the real
   `%LOCALAPPDATA%\Plantoir\builds\<id>` like every other launcher — but
   `setup_course.py` never resolves `toolchain_paths.merged_output_root`, so
   the variable is set and the folder it names is never made.
2. `setup_course.py` patches `quartz.layout.ts` and `OverflowList.tsx`, which
   in a native run live inside the **bundled runtime every working folder
   shares**. It is stopped only by `_scaffold_is_bundled_runtime()`, which
   returns true only while `PLANTOIR_RUNTIME` is set — and it is set, by
   `ScriptRunner`. If that ever stopped being true, a UI test would rewrite
   the shared runtime.

Checked rather than assumed, 2026-09-07: after a create there was no new folder
under the real builds root and the real breadcrumb trail was untouched. Check
both again before a test runs a different launcher.

Two things about it are worth more than the flag itself.

**Redirecting `%LOCALAPPDATA%` for the child process does not work**, and was
tried first: `Environment.GetFolderPath` asks Windows for the known folder and
ignores the environment variable entirely.

**It redirects ONE root rather than a list of places.** The first
implementation moved the settings file and the trail — the two things anyone
would think of. It missed that the app consumes pending scheduled-deploy
sentinels on launch and on every activation, and that applying one writes
publish state into the course folder the sentinel names, an absolute path to a
real course. So a test run could have marked a teacher's section as published
while the line explaining it went to the redirected trail, where nobody would
look. Everything now derives from `AppDataRoot`, so the next thing somebody
adds inherits the isolation instead of leaking.

## Driving the real interface

`run-ui-tests.ps1` launches the x64 Debug build and drives it with UI
Automation. It exists for the things a unit test cannot see: that a control can
be REACHED (invoking a button fires it whether or not it is on screen), that
clicking it opens something, that the RENDERED text is what the model said in
the order the contract fixes, that a scrolling list is not cut off at the
bottom, and that a panel follows the course a teacher selected rather than
going stale.

**It is opt-in and belongs to no gate.** Every test carries `[UiFact]`, which
skips unless `PLANTOIR_UI_TESTS=1`, so a plain `dotnet test` builds them and
runs none. The project is in the solution so a SOLUTION build compiles it —
compile-rot is what actually kills a suite nothing builds. Be honest about the
limit, though: the per-project commands used day to day (`dotnet build
Plantoir/Plantoir.csproj`, `dotnet test Plantoir.Tests/...`, `publish.ps1`)
do not build it, so it can still stop compiling without anyone noticing until
the next solution build. It needs a desktop session and
the foreground, takes a few minutes, and CLOSES a running Plantoir (saying so,
and not reopening it — that part is the teacher's).

It does **not** judge anything visual: colour, contrast, dark-mode legibility,
how a long name wraps. That is a screenshot pass, not this.

**Two switches worth knowing.** `PLANTOIR_UI_KEEP=1` leaves a failed run's
temporary folder behind instead of deleting it, and prints the path — a test
that fails INSIDE the app has almost nothing to say from outside it, and the
evidence that matters (the run's own `startup.log`, its breadcrumb trail, its
per-run launcher log under `Logs\runs`, and the working folder) is all in the
folder being thrown away. And `run-ui-tests.ps1` sweeps orphaned launcher
children afterwards: killing `Plantoir.exe` kills only `Plantoir.exe`, because
the whole-tree kill lives in `ConPty.Kill()`, which runs when the APP ends a
task rather than when the app is ended from outside. A test that fails while
`setup.ps1` is mid-run therefore leaves `powershell.exe` and `python.exe`
holding the temporary working folder open, and the folder then survives with
nothing to say where it came from. The sweep matches on a command line naming
one of the suite's own folders (`plantoir-ui-<8 hex>`), which is what makes a
force-kill there safe.

### Never start the app with its output redirected

`ConPtyProcess.Start` already carries this as a CAUTION, and it is repeated
here because the way you MEET it is nothing like the way it is written there.
The rule: the launcher binds to the pseudo console only when the process that
started **Plantoir** has clean std handles — console handles, or none, as a
GUI app started from a shortcut has. A parent whose stdio is redirected to
pipes leaks those handles into the launcher instead.

When that happens the app captures nothing, and what the app sends the
launcher never reaches it. Under `dotnet test` that shows as a task that
"failed (exit code 1) after 1s" with an EMPTY transcript in Show details —
the pipe gives the child EOF, and `input()` in `setup_course.py` dies. With
output redirected to a file it instead HANGS on the first prompt, with the
launcher's output sitting in the redirect target. Both read like a broken
toolchain, and neither is one.

Measured 2026-09-07 (Lenovo 20QES70500, Intel Core i5-8365U @ 1.60 GHz,
16 GB) — three launches of one build, one variable:

| How the app was started | What happened |
|---|---|
| `cmd.exe` in its own window, handles inherited (what `.\Plantoir.exe` at a prompt really gives you) | course made, `setup.ps1` succeeded after 21 s |
| ShellExecute (`Start-Process`, a shortcut, the Start menu) | course made, 21 s |
| the same, with `> out.txt 2>&1` | nothing captured, run hung on the first prompt, no course |

**So an ordinary terminal is fine; redirecting is not.** An earlier version of
this section said the opposite — that any console broke it — which is why the
experiment above is written down rather than the conclusion alone.
`Plantoir.UiTests` is the case that meets it in practice, and `DrivenApp`
launches with `UseShellExecute = true` for exactly this reason. Whether
`ConPtyProcess.Start` should defend itself is in [`TODO.md`](../TODO.md).

### The new-site dialog: a hand-driven check

One first-run path cannot be a `[UiFact]`, and it is the other half of what
handoff item 35 asked for: the dialog a BRAND-NEW section's first publish
raises, where a teacher chooses their website address. Everything verified
until now has been a REPEAT publish to a site that already existed, so this
dialog has never been seen by anybody checking that it works.

**Why it is not automated** — five reasons, checked rather than assumed:

1. **A test would READ a real credential, and this is the one that settles
   it.** `deploy.ps1`'s `$KEY_TARGET` is the hardcoded
   `containerized-quartz-netlify`, with no override, and `--state-dir` does not
   redirect Credential Manager. So whether a test reached the token dialog or
   **published a real website** would depend on whether the machine happened to
   have a token saved. A test whose behaviour forks on developer machine state,
   one fork of which creates a live site, is not a test.
2. **A fake token never reaches the prompt.** `deploy.ps1` validates the token
   against `https://api.netlify.com/api/v1/user` before `deploy.py` starts, and
   clears it and asks again on failure — so a bogus one raises "Connect to
   Netlify", not "Choose a Website Address".
3. **A real token creates a real, globally unique Netlify site**, and the suite
   has no way to delete it afterwards.
4. **A stub `deploy.ps1` does not survive.** `ToolchainMirror.RefreshLaunchers`
   rewrites any launcher that differs byte-for-byte from the bundled copy, and
   it runs on every `WorkspaceViewModel.Reload()` with no once-per-folder
   guard. (`RefreshToolchain` DOES have that guard, so a stub written into
   `.toolchain\scripts` after the first reload would survive — worth knowing
   before anyone reaches for it, but it rescues nothing, because reason 2 stops
   the run before `deploy.py` is reached.)
5. **`verify-deploy.ps1` cannot cover it, by design.** It redirects stdin from
   a file precisely so `sys.stdin.isatty()` is false and `deploy.py` asks
   nothing at all (`verify-deploy.ps1:166-185`).

**What to check, and what NOT to.** Do not eyeball the dialog's title,
explanation or its three steps: those are contract data
(`contracts/app-rules.json` → `credentialRequests.requests.siteName`) and are
asserted by equality in `ContractTests`, so reading them by hand adds nothing.
Check the five things nothing pins:

1. The **surname** dialog comes first, and only once. On a second new section
   it must not appear again.
2. "Choose a Website Address" then appears, with the address field
   **PRE-FILLED** as `<course>-s<section>-<year>-<surname>` — the bracketed
   default `deploy.py` prints, lifted out of the wording by
   `QuestionParser.SeparateDefaultAnswer`.
3. **Cancel cancels**, and does not hang. The run should end as cancelled
   rather than sit waiting on a question nobody can answer.
4. "Save and continue" sends what you typed: the site Netlify creates carries
   **that** address, not the pre-filled one.
5. The breadcrumb trail records the ask — `asked for a publishing credential`,
   with the field named.

**How to run it.** Publish a section that has never published, to Netlify,
with a real token already saved. `--auto-deploy CODE N` presses Publish for
you; the button does the same thing.

**Clean up afterwards, or the check stops checking anything.** Delete the site
on Netlify, and delete `courses/<CODE>/.netlify_sites/section<N>.json` — with
the marker in place the next publish reuses the site and never asks.

Whether this joins the release cut is the same open question as handoff item
36 (`verify-deploy.ps1` is wired into nothing and that is a decision nobody has
made), so it is deliberately not written into `RELEASING.md` here.

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
