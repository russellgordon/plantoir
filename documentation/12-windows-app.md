# 12. The Windows App — Plantoir

[◀ Previous: Release Strategy](11-release-strategy.md) · [Back to index](README.md) · [Next: Archive — the Windows port ▶](13-windows-port-archive.md)

`windows-app/` contains **Plantoir** for Windows: the same product as
[the macOS app](09-mac-app.md), built by somebody who cannot read the Swift,
against the same [shared contracts](../contracts/README.md). It wraps the same
command-line toolchain in a graphical interface — a sidebar of courses and
sections, a settings form mirroring the wizard, an embedded preview, one-click
deploys, a New Course wizard, and the same on-device assistant.

**This page is architecture and platform difference.** For what is BUILT and
what is still missing, read [`windows-app/PROGRESS.md`](../windows-app/PROGRESS.md),
which carries the live parity table; for the reasoning behind decisions,
the rest of this folder. Those are maintained as work
happens. This page is not a status report and should not be read as one.

---

## The solution

| Project | Role |
|---|---|
| `Plantoir/` | The WinUI 3 app. Unpackaged (`WindowsPackageType: None`), self-contained, Windows App SDK included, `net9.0-windows10.0.19041.0` / `win-x64` — so a teacher installs no runtime. Bundles the toolchain recipe under `Toolchain/` and mirrors it into each working folder's `.toolchain/`. |
| `Plantoir.Core/` | Everything with no UI: configuration round-trip, the build location, port leases, freshness, archiver and restorer, the script runner, failure explanations, catalogs — and the whole assistant under `Assist/`. This is where a rule belongs unless it cannot be expressed without a window. |
| `Plantoir.Tests/` | xUnit, and it runs without Docker or a network: `dotnet test`. Classes touching process-wide state share a serialized collection — see `SharedActivityState`. Read the TOTALS line rather than the exit code — see "Reading a test run" below. |
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
  and fetches each one back. It needs three credentials, the network and about
  twenty minutes, and it creates real sites — so it stays opt-in, and no suite
  runs it. What changed on 2026-09-07 is that this is now SAID rather than
  merely true: `.githooks/pre-commit` names it when a commit touches the
  publishing path (a warning; it never blocks), and `RELEASING.md` requires a
  run with nothing skipped for a release that changes that path.

  **The Python half of `verify.sh` does run here now.** Every shared
  `scripts/test_*.py` file executes inside `dotnet test` via
  `PythonToolchainTests` — 156 tests in about eight seconds, no Docker, no
  network, no credentials. (That was fifteen files and 156 tests when measured
  here on 2026-09-07; there are **eighteen** as of 2026-09-09. The runner
  DISCOVERS them rather than listing them, so the number is not something
  either side has to keep in step — count them with `ls` rather than trusting
  this sentence, which is why it no longer names one.) `verify.sh` has always run them on the mac and
  nothing ran them here, so a shared file could be broken from this machine
  with every gate on it green. The runner sets `PYTHONUTF8=1` and
  `PYTHONIOENCODING=utf-8`, which is what the launchers set
  (`deploy.ps1:117-118`); without them `build_site.py`'s emoji `print` raises
  `UnicodeEncodeError` on a cp1252 console and it reads exactly like a broken
  build rather than a console encoding. What still does NOT run here is
  everything of `verify.sh` that needs Docker — the image build and the baked
  file checks.
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
| `scheduled\unanswered\` | One note per section, left when a scheduled publish stopped because it needed an answer nobody was there to give. Its own folder, not `pending\`, because `ScheduledDeployCompletion.ConsumePendingFrom` deletes every file it touches, parsed or not. |
| `scheduled\folder-problems\` | What last night's build found wrong with a course's folders, for the next time there is somebody to tell. |
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
as something to weigh, not as something this code
does; do not go looking for app-registration code.)

Two rules learned the hard way, and they cover different halves of the same
problem — **nobody answers a question at 6 a.m.**

- **Run it `-NonInteractive`.** Without it, a `Read-Host` anywhere in the chain
  blocks until Task Scheduler's own limit and the site is simply never updated,
  with nothing to say why. **This reaches PowerShell's own prompts only.**

- **Pass the deploy legs `--non-interactive`.** PowerShell's flag does not
  reach a Python child, and `deploy.py` is where the question that matters
  lives: what the website should be called. Both ways that ended have been
  seen. With a terminal, `input()` BLOCKS — measured at 45 minutes, the
  launcher and its Python child still waiting at the prompt when they were
  swept up. Without one, `prompt()` returns its DEFAULT silently and a Netlify
  name conflict auto-suffixes, so the site is published to an address nobody
  chose, and on a machine with no saved surname the address has no surname in
  it either.

  Under the flag every question REFUSES instead: it says which question it
  could not ask, says what to do about it, and exits **3** — a code that
  means "a question went unanswered" and nothing else, so a caller can tell it
  from an ordinary failure. Every other exit in `deploy.py` and in both
  launchers is 0 or 1. The wrapper reads it, writes a per-section record under
  `scheduled\unanswered\`, and `SectionDetailView` shows the teacher an InfoBar
  the next time that section is on screen. Nothing changes when the flag is
  absent: a teacher at a keyboard gets every prompt they got before.

  **Three things about that record changed on 2026-09-09 (issue #130), and
  each reverses something this page used to say.**

  It records **four outcomes**, not one: a question went unanswered, the BUILD
  asked a question, it did not finish for some other reason, and it WORKED.
  The last is there for the same reason as the failures read backwards — a
  scheduled publish that leaves no trace cannot be told from one that never
  happened, so the trail could answer *"why did my site not update?"* and
  could not answer *"did it?"*.

  Reading it does **not consume** it, where this page previously described
  "the same consume-on-read, clear-on-clean-run shape the folder problems
  use". The record now stands until a run gets all the way through or the
  teacher dismisses it, which is the only way Dismiss can exist at all — and
  it closes a real hole, since consuming made "not shown" and "shown and read"
  the same state, so a reader that could not get the sentence on screen had
  already destroyed it. It is also read TWICE per launch now: the sidebar
  reads it for the warning badge, the section for the sentence.

  It is an **InfoBar, not a ContentDialog**. A dialog can only be
  acknowledged, and WinUI allows one at a time — so an overnight run that
  produced both a folder problem and a stopped publish told the teacher about
  the first only.

  The **folder keeps the name `unanswered`** though it now holds successes.
  Renaming it was implemented and reverted: a task scheduled before that date
  points at a wrapper `.ps1` already on disk that writes the old path, and
  nothing rewrites that wrapper until the section is scheduled again — so a
  rename costs a second directory read for ever, on pain of the first
  overnight run after an update going silent. A one-line record from such a
  wrapper is still read, as the question it was.

  **The trail line is written by a startup sweep in `App.OnLaunched`**, not by
  this view and not by the wrapper. The contract says the RUN writes it, and
  here the run is PowerShell with nothing of ours alive — so the closest
  honest thing is to sweep every record the moment the app opens, which keeps
  the property that sentence is protecting: a teacher who never opens the
  failed section still gets a line. Writing it from the wrapper was REJECTED:
  it would put the trail line format in generated shell, where nothing tests
  it and `LogRedactor` does not reach. Once per RUN rather than per launch,
  via a `.noted` sidecar — a mark written INTO the record would change its
  modification date, which is what the notice is dated from.

  Two things about the note that look like tidiness and are not. It is written
  only by the FIRST destination that stops, because there is one note per
  section and a course can publish to several — overwriting would report the
  last thing that went wrong rather than the first. And it is cleared only
  AFTER every destination has run: clearing inside the loop looked right and
  was wrong, because a course whose Netlify leg stopped for a question and
  whose folder leg then succeeded would have had the note deleted by the second
  leg, and the teacher would never have been told why the first did not go out.

  The refusal is gated at the one place the situation is KNOWN rather than at
  three scattered prompts: `deploy.py`'s `main()` refuses as soon as it sees
  that a Netlify site is about to be named, and tells the two cases apart —
  a section never published, and one whose saved site no longer exists at the
  other end. `prompt()` and the surname helper refuse too, as a backstop for
  any path nobody has walked.

  **It used to stop at the deploy launcher.** `deploy` shells out to
  `preview.bat --build-only` when the built site is stale, and at the time
  neither `preview.ps1` nor `preview.sh` took the flag — so `preview.ps1`'s
  "Continue anyway?" could still be asked of nobody, in the narrow case where a
  section has been archived out of `course_config.json` while its scheduled
  deploy still exists. `-NonInteractive` does not reach it either, because
  `preview.bat` starts a new `powershell.exe`. That was GitHub issue #124, and
  **both launchers take the flag as of 2026-09-09**, refusing with the same
  exit 3 — `preview.sh` here, `preview.ps1` on the Windows side the same day.
  The mac drives its refusal for real in
  `scripts/test_preview_sh_questions.py`; Windows SCANS `preview.ps1` for an
  unguarded question in `PublishAndLauncherContractTests` but nothing there
  starts the real launcher refusing, which is the piece still worth having.

  `ScheduledDeploy.Problem` already refuses to SCHEDULE a section that has
  never been deployed, so the commonest way into this is closed at the other
  end. What it cannot see is a site DELETED on Netlify after the schedule was
  set, or a token revoked in between — which is how a real harness run hit
  it.

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

## Reading a test run: the exit code cannot tell you what happened

`dotnet test` exits 1 when a test fails. It also exits 1 when the test HOST
dies underneath the run, and when the test project failed to compile. Three
events, three different responses, one exit code — and the middle one is the
expensive one, because it does not look like an infrastructure problem. A test
is NAMED, so the name gets investigated; re-running it passes, so it gets filed
as flaky. On the mac that mistake rejected 3 of 7 pieces of correct work in a
single overnight batch and was raised twice, a fortnight apart, before
anybody noticed the two reports were one defect.

**The honest signal is the TOTALS line, never the exit code.** Measured
2026-09-08 on this machine (Lenovo 20QES70500, Intel Core i5-8365U @ 1.60 GHz,
16 GB; Windows 11 Pro 26200, .NET 9 SDK, xunit 2.9.2, Microsoft.NET.Test.Sdk
17.12.0) by putting each failure in deliberately:

| What happened | Exit | What it prints |
|---|---|---|
| A test failed | 1 | `Failed!  - Failed: 1, Passed: 0, Skipped: 0, Total: 1, Duration: 17 ms` (column-padded in reality, and it ends with the assembly name) |
| The host died | 1 | `The active test run was aborted. Reason: Test host process crashed` and `Test Run Aborted.` — and **no totals line at all** |
| It never compiled | 1 | neither: a build error, and no totals |

`windows-app/TestRunOutcome.ps1` reads that rather than the exit code, and is
shared by `run-tests.ps1`, `run-ui-tests.ps1` and the untracked batch driver,
so all three agree and there is one place to correct if vstest changes its
wording. They share the CAPTURE too (`Invoke-TestRun`), which is the subtler
half: the banner goes to stderr, `2>&1` is a terminating error under
`$ErrorActionPreference = 'Stop'`, and the ErrorRecord has to be flattened back
into a plain line. The batch driver had the first of those wrong, so it could
not have seen the banner even had it been looking — it judged by the exit code
alone.

Its verdicts are `Passed`, `Failed`, `HostCrash`, `RanNothing` and `NoResult`;
`HostCrash` wins over any partial totals, because a partial answer to "did the
suite pass" is not an answer. **The two runner scripts exit 0 only for a
genuine pass** — 3 for a dead host, 8 for a run that executed nothing, and for
no result at all whatever `dotnet` returned, or 4 when even that was 0. The
numbers follow Microsoft.Testing.Platform's published meanings, so they survive
an xunit v3 migration. (2 is deliberately avoided: MTP means
"at least one test failed" by it, which would invert the one distinction this
draws.) Neither a crash nor an empty run is retried: a crash retried until it
passes is a crash nobody measures, and the mac's was fixed only once somebody
counted it.

`RanNothing` is worth knowing about on its own, because it is the case a
green exit code lies about most often. **A filter that matches nothing exits
0** — measured: vstest prints "No test matches the given testcase filter" and
no totals line at all — so before this, a typo'd `--filter` reported success on
a run that executed nothing. It has a third dress too: an opt-in suite whose
switch did not take reports every test *skipped* and a healthy-looking Total.
Run `dotnet test Plantoir.UiTests.csproj` directly and that is what you get
(not through `run-ui-tests.ps1`, which sets `PLANTOIR_UI_TESTS` itself).

**Typing `dotnet test` directly is still correct**, and `run-tests.ps1` is a
convenience rather than a new gate — nothing depends on it. If you type the raw
command, look for the totals line yourself: if it is absent, the test named
above it is a bystander. `--blame` names the bystander properly, writing a
`<guid>_Sequence.xml` under `TestResults\` saying which test was running when
the host died (`run-tests.ps1 -Blame`); `--blame-crash` adds a full process
dump, tens to hundreds of megabytes, which is worth it only once you are
hunting one. Both paths are gitignored.

The reader's own checks run inside `dotnet test`
(`TheTestRunReaderTellsACrashFromAFailure`, which shells out to
`windows-app/test_run_outcome.ps1`). Three of its fixtures are pasted from real
output — a crash, an ordinary failure and a clean gate run — and the rest are
edge cases constructed by editing those, which the file says of itself rather
than implying every line came off a run. **Nothing here has ever been seen to
crash its host**; this exists so that if one ever does, it is read correctly
the first time.

## Driving the real interface

`run-ui-tests.ps1` launches the x64 Debug build and drives it with UI
Automation. It exists for the things a unit test cannot see: that a control can
be REACHED (invoking a button fires it whether or not it is on screen), that
clicking it opens something, that the RENDERED text is what the model said in
the order the contract fixes, that a scrolling list is not cut off at the
bottom, that a panel follows the course a teacher selected rather than
going stale, and that a sentence the contract pins is actually RENDERED where
a teacher can see it rather than merely held in a constant.

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

**It cannot crash its host, and that was measured rather than assumed**
(2026-09-08). The question came from the mac, where the unit suite segfaulted
its own test host about a third of the time because the test bundle is injected
INTO the app, so the app's crash IS the host's crash. Nothing of that shape
exists here: `DrivenApp` launches the real `Plantoir.exe` as a SEPARATE process
and talks to it over UIA3 COM. A throwaway probe killed the driven app
mid-test and then touched its window — the result was an
`InvalidOperationException` after `DrivenApp`'s 30 s patience, an ordinary test
failure, host untouched. **So a flaky UI test here is a flaky assertion, and
re-running it is the right response** — the opposite of the advice a mac host
crash deserves. The suite hosts no window of its own either: the project sets
`UseWPF`/`UseWindowsForms` false and references `Plantoir.Core` only.

**Two switches worth knowing.** `PLANTOIR_UI_KEEP=1` stops the run deleting
its temporary folders — EVERY test's, not just a failed one's, since the
teardown does not know the outcome — and `run-ui-tests.ps1` prints each path.
A test that fails INSIDE the app has almost nothing to say from outside it,
and the evidence that matters (that run's own `startup.log`, its breadcrumb
trail, its per-run launcher log under `Logs\runs`, and its working folder) is
all in what is normally thrown away.

And `run-ui-tests.ps1` sweeps orphaned launcher children afterwards: killing
`Plantoir.exe` kills only `Plantoir.exe`, because the whole-tree kill lives in
`ConPty.Kill()`, which runs when the APP ends a task rather than when the app
is ended from outside. A test that fails while `setup.ps1` is mid-run
therefore leaves `powershell.exe` and `python.exe` holding the temporary
working folder open, and the folder then survives with nothing to say where it
came from. **The sweep matches THIS RUN's token** — `run-ui-tests.ps1` mints
one and `DrivenApp` folds it into every folder it makes
(`plantoir-ui-<run>-<8 hex>`). Matching the folder PREFIX instead was the
first version and is too wide: two runs at once would kill each other's live
launchers, and a developer tailing a kept folder's log has the prefix in their
own command line. Both match the prefix; neither matches the token. Python is
caught by the same match because `setup.ps1` runs it as `python.exe -u
<workspace>\.toolchain\scripts\setup_course.py` — the script path is inside
the temporary folder, so it is on the command line even though the folder is
otherwise only python's working directory.

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
`ConPtyProcess.Start` should defend itself is
[issue #89](https://github.com/russellgordon/plantoir/issues/89).

### The new-site dialog: a hand-driven check

One first-run path cannot be a `[UiFact]`, and it is the other half of what
the first-run UI checks asked for: the dialog a BRAND-NEW section's first publish
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
5. **`verify-deploy.ps1` covers the QUESTIONS now, and still not the dialog.**
   It used to redirect stdin from a file precisely so `sys.stdin.isatty()` was
   false and `deploy.py` asked nothing at all, which left the whole
   first-publish path — surname, site name, the fallback when a saved site
   has been deleted — covered by no automated check. Since 2026-09-09 (issue
   #123) it drives every launcher through `PtyDriver` under a pseudoconsole and
   ANSWERS by prompt text, the way the mac's `verify-deploy.sh` has done through
   `expect` for months.

   What it still cannot reach is what this section is about: the **dialog**.
   The harness answers the launcher's console questions; a teacher meets a
   WinUI sheet. Those are different surfaces and only one of them has a
   pseudoconsole.

   **One deliberate difference from the mac's `expect` block, recorded so it is
   not read as an oversight.** That side ends with a catch-all,
   `-re {\(y/n\): } { send "y\r" }`, which answers YES to any yes/no question.
   This side carries no such rule: nothing in the Windows publish path asks one
   — the only `[Y/n]` is `deploy.ps1`'s course-code guard, which cannot fire
   for a code that does not end in a digit-zero. A catch-all that says yes to
   whatever is asked is a bet that nobody ever adds a destructive question, and
   the failure modes here are asymmetric: a rule that does not match makes the
   run hang and be reported, where a rule that matches too eagerly claims a
   globally unique web address. Few and tight beats broad.

**What to check, and what NOT to.** Do not eyeball the dialog's title,
explanation or its three steps: those are contract data
(the `siteName` entry in `contracts/app-rules.json`'s `credentialRequests.requests`
array) and are asserted by equality in `ContractTests`, so reading them by hand
adds nothing. **The explanation was the exception until 2026-09-07** — the
sweep checked title, field label, secrecy, link and steps, and skipped the
longest thing a teacher reads. Writing this paragraph is what found it; it is
asserted now.
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

**Do it in a working folder made for it, and clean up afterwards, or the check
stops checking anything.** Three pieces of state make a second run silent:

- `courses/<CODE>/.netlify_sites/section<N>.json` — the site marker. With it
  in place the next publish reuses the site and never asks.
- `courses/<CODE>/section<N>/.netlify_site.json` — the LEGACY marker, which
  `deploy.py` migrates back into the stable path if it finds one, so an older
  folder needs both removed.
- `courses/.internal/profile.json` — the saved surname. Nothing removes it,
  which is why **step 1 can only be checked once per working folder**: use a
  fresh one, or accept that you are checking steps 2–5 only and say so.

And delete the site on Netlify, since it is a real one and the address is
globally unique.

**Whether this joins the release cut — answered 2026-09-07, and the answer is
no.** It was left open as the same question as the publishing-gate work, which is now
settled, so this one is too, and separately from it. `RELEASING.md` requires
`verify-deploy.ps1` with nothing skipped for a release that changes the
publishing path, and that script cannot reach this dialog — it answers the
launcher's CONSOLE questions through a pseudoconsole, where the dialog is a
WinUI sheet the app puts up instead. Adding the
hand-check to the cut would mean a release step that creates a real, globally
unique Netlify site that nothing deletes, on top of the ones the verifier
already makes, to check five things that change about once a year. Do it when
the new-site path itself changes — the five checks above say what to look at —
and not on a schedule.

## `x:Bind` freezes a row that is reconciled rather than recreated

Worth knowing before any WinUI work here, not only the case it was found in.
The sidebar's scheduled-deploy badge never appeared when a deploy was scheduled
in an already-open window, and the right-click menu never offered Cancel or
Change either (2026-08-23, `GUI-IMPROVEMENTS.md` row 326). **Two compounding
bugs, and fixing the obvious one alone would have changed nothing on screen.**

1. `ReconcileSections` read the current schedule into `SidebarRow` only when
   CREATING a row. An existing row — the normal case, the window being already
   open — kept whatever had been true the moment it was first shown, forever.
2. Even with that fixed, nothing would have appeared. **`x:Bind` defaults to
   `Mode=OneTime`**, unlike classic `Binding`: it evaluates once when the
   container is created and never again. `SidebarRow` raised no change
   notification and none of the affected bindings asked for `Mode=OneWay`, so
   `Visibility` and `ContextFlyout` were frozen at container-creation time.

**The general rule.** A row or item object that is RECONCILED rather than
recreated needs both halves, every time:

- `Mode=OneWay` in the XAML on every binding whose value can change after the
  container is built, and
- `INotifyPropertyChanged` raised for **the exact property name the binding
  names** — including any DERIVED property XAML binds to directly. `x:Bind`
  subscribes to the literal property path in the binding, not to whatever that
  property is computed from, so here `ScheduledDeploy` changing had to raise
  `BadgeVisibility` and `BadgeTooltip` as well.

`MainWindow`'s `Activated` handler also calls `Sidebar.Refresh()`, so a deploy
scheduled by the assistant or from another window is picked up when this window
next comes to the front — the same refresh-on-activation shape the " — Edited"
marker uses.

**There is no equivalent trap on the mac.** SwiftUI's `@Observable` re-renders
any view that read a changed property, so the "silently stale until the
container happens to be recreated" failure mode does not exist there. Do not go
looking for it in the Swift.

Reference: `Plantoir/Views/SidebarPane.xaml.cs` (`SidebarRow`,
`ReconcileSections`), `Plantoir/Views/SidebarPane.xaml` (the three `Mode=OneWay`
bindings), `Plantoir/MainWindow.xaml.cs`.

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
- **What is built and what is missing.** Outstanding work is in [GitHub
  issues](https://github.com/russellgordon/plantoir/issues) labelled `windows`;
  the rest of this folder carries the reasoning behind past decisions.

## Nothing here runs in a container

**Read this before the architecture sections below.** Windows dropped Docker,
WSL2 and the whole image/container model on 2026-08-19 (`GUI-IMPROVEMENTS.md`
entry 290) in favour of a **native runtime**: `windows-app/Vendor/fetch-runtime.ps1`
fetches pinned, portable pieces — Node 20 (zip, no installer), Python 3.11
(the embeddable distribution plus `python-frontmatter` and `Pillow`), a clone
of Quartz v4.5.0 with this repo's `patches/` applied, wrangler, and the Noto
emoji font — into `windows-app/Vendor/runtime/`, which the app then ships
inside its own bundle the same way it ships the assistant's `llama/` engine.
`setup.ps1` / `preview.ps1` / `deploy.ps1` **do still live at the repository
root** (an earlier draft of this note said otherwise; that was wrong) and are
mirrored into a working folder exactly as before, but their bodies changed:
each now calls `Enter-NativeRuntime`, which points a shared set of
`PLANTOIR_*` environment variables at the bundled runtime and the working
folder, then runs `scripts/setup_course.py` / `build_site.py` / `deploy.py`
directly with the runtime's own `python.exe` — no `docker`, no `wsl`, no
image build, no administrator rights, and no one-time "Setting up this PC"
wait. If a copy is missing its bundled runtime the launcher fails outright
("This copy of Plantoir is missing its website builder... Reinstall
Plantoir") rather than falling back to a container path, because there no
longer is one.

What replaces the old container concepts:

- **No image, no tag, no registry.** There is nothing to hash into a
  `teaching-quartz:src-<hash>` tag any more, and `Get-ToolchainHash` /
  `Get-BuildContext` / `Ensure-ContainerRuntime` do not exist in the current
  `.ps1` files — do not port them, and do not go looking for the batching fix
  described further down this file (below, under "The recipe hash is on the
  hot path") as if it still applies; it was superseded by removing the image
  entirely, not fixed further.
- **Isolation between working folders is a hashed *working-folder ID*, not a
  container name.** All three launchers still compute `$WORKDIR_ID` — the
  first 8 hex characters of SHA-256 over the folder's physical path (via
  `GetFinalPathNameByHandleW`, the same Win32 call as before) plus a
  newline, matching the mac's `pwd -P | shasum -a 256` derivation. A
  `$CONTAINER_NAME = "teaching-quartz-$WORKDIR_ID"` variable is still
  assigned in each script for parity with the mac's naming scheme, but
  nothing native reads it — the real use of `$WORKDIR_ID` today is naming a
  per-folder build directory, `%LOCALAPPDATA%\Plantoir\builds\<WORKDIR_ID>`,
  so two working folders' builds never collide, and it moves build output
  entirely **out of the working folder**, because teachers keep working
  folders in OneDrive and a build's thousands of small files would sync and
  lock in place there.
- **Concurrent previews are still isolated by port, exactly as before.**
  `preview.ps1` still probes a free host port block (8081/8091/8101/8111/8121/8131,
  base..base+3 for the site, base+1000..+1003 for Quartz's live-reload
  websocket) and prints the exact "Preview will be available at:" line the
  app watches for. What changed is only what is listening on that port: a
  Node process running directly on the PC, bound to `127.0.0.1` (patched at
  runtime-build time in `fetch-runtime.ps1`, native-only — see the favicon
  entry below), not a container's forwarded port.
- **`preview.ps1 CODE N --stop` reclaims native processes, not a
  container.** It matches processes by command line
  (`build_site.py --course=/--section=` for the build, the section's own
  build-root path for the server) and walks parent/child links to catch
  descendants, then kills them with `Stop-Process`. No container, no `docker
  exec`, no engine to stop. It narrowed those matches to `node.exe` /
  `python.exe` until 2026-09-05; **that filter is gone**, because it refused
  most of the contract's own fixtures (`python3`, `npm`, `esbuild`, `sh`) and
  a `cmd.exe` running `npm.cmd` with the section's folder on its command
  line. `preview.ps1` now applies no filter on process NAME at all, because
  the shared rule has none — see the comment above
  `Get-SectionProcessesToStop`.

`GUI-IMPROVEMENTS.md` entries 290 and 292 are the log rows for this change;
Its origin and reasoning are written up in full above.
The sections below that still described the old Docker/WSL2 container
architecture as current have been corrected to match the above — where the
old material is useful as history (why containers were tried, what WSL2 and
Colima-parity cost, lessons that still generalize), it is kept but labelled
as history, not as what Windows does today.

## The architecture the app reproduces

- **Working folders**: a folder holding `courses/`, the three launchers,
  and `.toolchain/` (a mirror of `scripts/`, `support/` and the launchers
  themselves, refreshed by the app from its own bundled copy whenever a
  launcher/script file differs — a much smaller mirror than before, now
  that there is no image recipe to carry). The bundled **native runtime**
  (Node, Python, patched Quartz, wrangler, the emoji font — see
  `Vendor/fetch-runtime.ps1`) is separate again: it lives once per Plantoir
  install, not per working folder, and every working folder's launchers
  point at the same copy via `PLANTOIR_RUNTIME`.
- **No image, no tag, no registry.** There is nothing to build or cache
  locally any more — `Get-ToolchainHash` does not exist in the current
  `.ps1` files, and there is no equivalent to reproduce. (History: the old
  container path hashed every file in the build context and tagged
  `teaching-quartz:src-<hash8>`, rebuilding only when the recipe changed —
  see "The recipe hash is on the hot path" below for why that mattered
  while it existed, and note that it no longer does.)
- **Isolation between working folders is a hashed working-folder ID, not a
  container name.** Each launcher computes `$WORKDIR_ID` — the first 8 hex
  characters of SHA-256 over the folder's physical path (via
  `GetFinalPathNameByHandleW`) plus a newline — and uses it to name a
  per-folder build directory, `%LOCALAPPDATA%\Plantoir\builds\<WORKDIR_ID>`,
  outside the working folder entirely (so a working folder kept in OneDrive
  never has its build output synced and locked). A `$CONTAINER_NAME =
  "teaching-quartz-$WORKDIR_ID"` variable is still assigned in each script,
  matching the mac's naming scheme, but nothing native reads it today —
  don't build app logic around a container name existing.
- **Port blocks**: `preview.ps1` still probes a free host port block
  (bases 8081, 8091, 8101, 8111, 8121, 8131): base..base+3 for the preview
  site (four concurrent previews per folder) and base+1000..+1003 for
  Quartz's live-reload websockets. What is listening on those ports is now
  a native Node process bound to `127.0.0.1`, not a container's forwarded
  port. The app leases ports per folder (`PreviewLeases` in the macOS app),
  parses the announced "Preview will be available at:" address rather than
  assuming it, and refuses a duplicate preview of the same section in the
  same folder.
- **Course activity registry** (entry 104): one cross-window record of
  which courses are previewing (the port leases already know) or
  publishing (begin/end records around the publish flow, ended on EVERY
  exit path). "Add Section…" declines while its course is active, with a
  short line naming the blocker ("Available once preview completed").
  Staleness lesson: read the enabled state when the menu OPENS, or make
  registry changes re-render whatever hosts the menu — a state captured
  at an earlier render shows yesterday's answer.
- **Stopping a preview reclaims native processes** (entry 105): killing
  the host-side launcher orphans the build or server process it started
  (an orphaned build burns real CPU). `preview.ps1 CODE N --stop` matches
  that section's processes by COMMAND LINE — never the working
  directory, which `Win32_Process` does not expose at all — walks their
  descendants, and `Stop-Process`es them, and never starts anything
  itself. (Corrected 2026-09-05, and this passage needed correcting
  TWICE over: it said "command line and working directory" for months,
  which is the mac's mechanism rather than this one, and it went on
  naming a `node.exe` / `python.exe` filter that was removed the same
  day — for refusing most of the contract's own fixtures. Fixing half a
  stale sentence and leaving the other half is how a passage keeps
  being believed. The rule both platforms must agree on is written down
  once, in `contracts/shared-rules.json` → `stopPreview`.) Call it
  fire-and-forget — output discarded — wherever a preview ends: stop
  button, navigating away, window close. (History: this used to reclaim
  the container-side processes an orphaned host script would otherwise
  leave running inside Docker; the mechanism moved, the reason for having
  it did not.)
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
- **No engine to bootstrap.** `fetch-runtime.ps1` downloads pinned, portable
  Node/Python/Quartz/wrangler binaries once (run before building the
  Windows app, or shipped inside its bundle to a teacher) — there is no
  WSL2, no Docker Engine, and nothing for the app to start, poll, or stop
  at quit. (History: earlier Windows builds provisioned Docker Engine
  inside WSL2 automatically, mirroring the mac's Colima bootstrap — see the
  appendix at the end of this file. That entire path is gone; do not build
  toward it.)
- **BuildKit, the image tag, and "the legacy builder corrupts a layer" are
  mac-only facts now** — Colima still needs them; native Windows has no
  image and no builder of any kind.

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
  draws the 1200×630 card on every build (inside the container on macOS,
  natively on Windows — see the note above), `patches/Head.tsx`
  wires OpenGraph and Twitter card metadata, and `scripts/build_site.py` / `scripts/deploy.py`
  sync the live site domain into Quartz's `baseUrl` (falling back to `undefined` when unpublished).
  Because the entire flow lives in the shared Python scripts, Windows inherits it automatically
  regardless of which runtime carries them.
- **HISTORY — the recipe hash used to be on the hot path** (entry 118).
  This entry describes a bug that existed only in the old container/image
  architecture and **no longer applies**: Windows dropped the image tag
  entirely on 2026-08-19 (see the note at the top of this file), and
  `Get-ToolchainHash` does not exist in the current `.ps1` files. Kept here
  because the underlying lesson generalises — **keep per-file work out of a
  per-invocation loop** — and because the mac side still hashes something
  comparable for its own image tag. What it used to say: the image tag was
  a SHA-256 over every file in `.toolchain/`, which by 2026-08-15 carried
  **11,378 files** across the example-content payloads and subject
  skeletons; the `.sh` launchers originally spawned one `shasum` process
  per file (36s of a 36.75s preview startup on an M4 Pro) before being
  batched to `find -print0 | sort -z | xargs -0 shasum` (0.16s), and
  `Get-ToolchainHash` in the old `.ps1` files had the same bug in its
  PowerShell dialect — `$combined += (Get-FileHash …).Hash` inside a loop,
  reallocating an immutable string thousands of times — fixed the same way
  by collecting into an array and joining once. If a future Windows change
  reintroduces any per-folder hash (for a future runtime version check, say),
  re-learn this lesson rather than re-discovering it.

## WinUI scroll bars overlay content — always reserve a trailing gutter

Found 2026-08-22, testing the model-in-use guard written up in
(`GUI-IMPROVEMENTS.md` row 421):
`AssistantSettingsDialog`'s
"On this PC" housekeeping rows put a Stop/Remove/Download button flush against
the `ScrollViewer`'s right edge, and the vertical scroll bar drew right over
top of it — reported directly: "the scroll bar goes over the buttons — that
seems a poor UI choice? […] scroll bars should never occlude content on a
lower layer."

**Why it happens.** WinUI's default `ScrollBar` visual (`MouseIndicator` mode)
is an OVERLAY — it takes no layout space of its own and floats over whatever
the `ScrollViewer`'s content places at its trailing edge. A `ScrollViewer`
with no padding gives the scroll bar nothing to float over except the
content itself, so anything docked to that edge — here, a button in the
right-hand column of a two-column `Grid` — sits directly underneath it.

**The fix, and the convention going forward**: give the `ScrollViewer` extra
padding on the trailing side specifically — `Padding = new Thickness(0, 0, 20, 0)`
in `AssistantSettingsDialog.cs`, 20px being enough to clear the thumb's hit
target with room to spare. Not a fix specific to Settings: **any `ScrollViewer`
whose content places an interactive control (a button, a toggle, a link)
flush against the trailing edge needs the same trailing gutter**, checked at
the point that content is designed, not discovered by a teacher clicking
through a scrolled-down dialog. `SectionDetailView.xaml.cs`'s own
`ScrollViewer` already does this by convention (`Padding="36,28,48,28"` —
more on the right than the left), which is what made this fixable by pattern-
matching rather than by inventing a number from nothing.

**Swept the rest of the app for the same shape and found nothing else
wrong**: `NewCourseDialog`'s form scroller and `CourseSettingsView`'s have no
buttons docked to their trailing edge (toggles and text fields, not a
two-column button row), and `AssistWindow`'s transcript scroller holds chat
bubbles, not edge-docked controls. The housekeeping rows were the only place
in the app with this exact shape today — but the rule is the general one
above, not "fix this one dialog."

**For the mac**: SwiftUI's `ScrollView` on macOS behaves differently — its
system scroll bar is also typically an overlay, but AppKit's own controls
already carry enough of their own trailing inset in most list/form contexts
that this specific defect has not been reported there. Worth a quick look if
a similar "button under the scroll bar" report ever comes in on that side,
but this is not a ported behaviour — it is a Windows-specific rendering fact
(the `MouseIndicator` overlay model) with no mac equivalent bug to fix in
lockstep.

## The course-code picker is a hand-built combo box — and probably should not be

`GUI-IMPROVEMENTS.md` rows 333–338 describe the new-course wizard's course-code
field being rebuilt over two days: a searchable field with a rich two-line
flyout, a chevron that toggles it, arrow-key navigation, and geometry matched
to a real `NSComboBox` to the pixel. **Read this section before you copy any of
it**, because the central decision does not transfer and following the rows
alone means re-deriving a lot of behaviour that comes for free.

Nothing here is a contract case. Every part of it is either visual, measured,
or built out of platform focus-and-key mechanics — the categories rule 2 sends
to a handoff rather than to `contracts/`.

### Why the mac hand-built it, and why that reason does not apply here

A real `NSComboBox` was tried first and reverted twice in one session
(2026-08-22). The blocking reason was **its popup can only display plain
strings**. The flyout has to show, per row, the course code, its formal name on
a second line, and an "Example content" badge for codes that ship with a
ready-made course — and `NSComboBox` simply cannot draw that. A secondary
reason: correcting its auto-widened popup frame proved unreliable two different
ways (deferred a runloop turn it flashed the wrong frame first; made
synchronous it missed the "click the arrow with an empty field" case, because
the popup's child window does not exist yet when `comboBoxWillPopUp` fires).

**WinUI does not have that limitation.** An editable `ComboBox`, or an
`AutoSuggestBox`, takes an `ItemTemplate` and will happily render a two-line
row with a badge in it. If that holds up when you try it — check before
committing, this is written by somebody who cannot run WinUI — then use the
real control, which gives, at no cost, everything the rows below describe
the mac writing by hand: the dropdown affordance and its toggle, up/down
navigation, Return to commit, Escape to dismiss, scroll-into-view for the
highlighted row, the focus ring, and correct metrics. Do not hand-build a
control to solve a problem you do not have.

The rest of this section is what to know **if** the real control turns out not
to work for you.

### Metrics: measure the platform's control, do not match it by eye

The mac's numbers came from rendering a real `NSComboBox` offscreen at 2x in
both appearances and reading the PNG back pixel by pixel. The harness and the
full findings table are in `research/native-control-metrics/`. The numbers
themselves are Apple's and are useless to you; the **method** is the part worth
copying, and three findings generalise:

- **A framework's "native-style" control is not the native control's
  metrics.** SwiftUI's `.textFieldStyle(.roundedBorder)` renders **26pt** tall
  where the `NSTextField` it stands in for reports **24**. Check what your
  `TextBox` actually measures against the WinUI control it imitates before
  assuming they agree.
- **Constraining the frame does not change what a control draws.**
  `.frame(height: 24)` left the field measuring 26 and merely overflowing its
  box. Getting 24 meant drawing the bezel ourselves.
- **A cell's text rect is not where glyphs land.** `titleRect` reported x=4,
  actual glyphs started at ~5.7pt; the text system adds its own padding inside.
  Measure rendered glyphs, not the API's rectangle, when matching text
  position.

There is also a **corner-radius trap that cost real time**: the radius was
already correct and only *read* wrong because the field was 30pt tall instead of
24. The same radius on a taller box looks squarer. Check the box before you
change the radius.

### If you do hand-build one: four things learned the hard way

1. **One piece of state for "is the flyout showing."** The toggle, the drawing,
   and the animation must all read the same value. Three separate conditions
   let the toggle disagree with what is on screen, and the arrow then needs
   pressing twice.
2. **Key handlers must DECLINE, not swallow.** Up/down/Return are handled only
   when there is a flyout to act on; otherwise they fall through. Swallow them
   unconditionally and you break the arrow keys for someone editing text and the
   default button for someone who typed a code and just wants to press Enter.
3. **Store the highlighted row by its CODE, not its index.** The list re-filters
   on every keystroke, so an index quietly comes to mean a different course.
   Clamp movement at the ends rather than wrapping — a wrap turns one key too
   many into a jump from the bottom of a 40-row list back to the top, which
   reads as the list having moved somewhere else entirely. And make Down with
   the flyout CLOSED reopen it on the first row, or Escape strands a keyboard
   user at the mouse.
4. **Re-check every badge and secondary colour that can land on a highlighted
   row.** The "Example content" badge is an accent-coloured capsule; on an
   accent-filled highlighted row it vanished completely the moment keyboard
   highlighting existed. It now inverts to a white capsule with accent text.
   A passing test did not catch this — looking at a screenshot did.

### The chrome is shared, and that was a trade

All three fields in the wizard's Basics section (course code, course name,
timetable section numbers) now wear one `WizardFieldChrome` modifier, so they
cannot drift apart. The cost, stated rather than buried: two fields that wore a
real AppKit bezel now wear an imitation of one, because that was the only way to
get them to the native 24pt. The imitation is measured against the real control
rather than eyeballed. The alternative — wrapping a real `NSTextField` in an
`NSViewRepresentable` for all three — buys genuine native chrome at the price of
hand-managing first responder and binding updates, and remains open if the
imitation ever starts costing more than it saves.

**If WinUI's own field is already the right height, none of this applies to you
— keep the real control.** The mac ended up here because it had already been
forced off the native control for the flyout's sake; do not inherit that
position by accident.

## Two macOS mechanics NOT to port

Do not port entry 142 (Colima sizing) or entries 244–245 (`launchd`). They are
macOS mechanics. The transferable half of 244–245 is a single lesson worth
having before you touch `TaskScheduling.cs`: register a scheduled job as the
APP, not as the shell it happens to run, or the operating system tells the
teacher that "bash" — or, on the second attempt here, a person's name — wants
to run in the background.

## Two testing rules that cost time to learn

Windows found the gap (2026-08-19): three trail events sat
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

### A stub launcher must answer every mode the app calls, and must not name a port (mac, 2026-08-23)

The mac's one end-to-end preview test drives the real app against a fake
`preview.sh` that serves a one-page site. It had been failing for days with
`OSError: [Errno 48] Address already in use`, and it leaked an orphan server
that held port 8081 overnight — a leftover once made a REAL preview fail, which
reads like a broken toolchain rather than like test litter. Three separate
faults, and the interesting part is that only the third was the actual cause.
Windows has the same shape of test to write (`preview.ps1` driven by the app),
so all three are worth having before you write it.

- **The stub never implemented `--stop`, and that was the real bug.** Ending a
  preview runs `preview.sh <course> <section> --stop` and the app WAITS for
  that to finish before the next preview starts (mac: `PreviewStopper`). The
  stub ignored its arguments, so `--stop` fell through to "start a server" —
  which never exits. The restart then waited forever on a stop that could not
  complete, and the second server's attempt to bind the port the first one
  still held produced the `Address already in use` line everybody was chasing.
  **The error message named the symptom and hid the cause.** A stub stands in
  for a launcher, so it owes every mode the app invokes; answering only the
  happy path buys a failure that looks like a port problem.
- **A hard-coded port is a test that asserts ownership of a shared machine.**
  The stub asked for 8081. Anything else holding it fails the run for reasons
  that look like a product bug — and on this Mac something did: an unrelated
  `ssh -L` tunnel of Russell's, listening on 8081 all along. The fix costs
  nothing, because the app already scrapes the port out of the launcher's own
  output (`Preview will be available at: http://localhost:<port>/`). The stub
  now binds port 0, lets the kernel choose, and announces what it got — bind
  BEFORE announcing, so there is no window in which the announced port is not
  yet taken. Two runs can now overlap, and a teacher's real preview can be up
  at the same time. **Windows: do not let a stub name 8081**; read the port
  back from the announcement the same way.
- **A sandboxed UI-test runner cannot spawn a process, and fails silently at
  it.** The mac's first attempt at cleanup put `pkill` in `tearDown` behind a
  `try?`. It never ran — XCUITest's runner has no permission to spawn a child
  at all — and the swallowed error made dead code look like working cleanup
  for days. Proved by having it write a marker file that never appeared. The
  reaper is now a raw `kill()` on a pid the stub records before `exec` (which
  preserves the id). Check whether your Windows UI-test host has the same
  restriction before trusting a `Process.Start`-based teardown, and prefer
  `Process.GetProcessById` + `Kill()` on a recorded id, which needs no spawn.
- **Do not oversell the teardown reaper — it does NOT cover an interrupted
  run**, which is the case that actually hurt. An adversarial review caught
  this claim being made here in its first draft. Teardown does not execute
  when a run is killed, and the mac's recorded pid is stranded in a
  per-run `cq4t-fixture-<UUID>` folder that is never handed out again, so no
  later run can find it. **The port change is what makes an interrupted run
  harmless**, because the orphan then holds a kernel-assigned port nobody is
  waiting for rather than the one a real preview needs. The reaper earns its
  place on a narrower case: a server that outlived the test BODY, because the
  test failed before it could stop the preview. If Windows wants genuine
  interrupted-run cleanup, it has to come from outside the run — a known
  fixed pid-file location, or a verify step — not from teardown.
- **Record the pid BEFORE anything slow.** The mac's stub first wrote its pid
  after two `sleep 1` calls, which left a two-second window where a test that
  finished quickly tore down, found no pid file, and leaked the orphan anyway
  — the same review found it. The shell's `$$` is the same value at the top of
  the script as at the bottom, and `exec` preserves it, so there is no reason
  to wait.
- **If the stub kills by pid in more than one place, name-check in ALL of
  them.** The mac's Swift reaper checked the process name and its own shell
  `--stop` path did not, which is the stated invariant broken in one of the
  two places that needed it. Note the two need different matching: the kernel
  reports the short name (`Python`) while `ps -o comm=` reports a full path,
  so one wants a prefix test and the other a substring test.
- **Never reap by process NAME alone.** A pid is reused once its owner is
  reaped, so "something answers to this number" does not justify a kill — that
  is how a test murders an unrelated program of the teacher's. The mac scopes
  the kill to a pid the stub itself wrote, and additionally checks the running
  process's name before signalling. That check has one trap worth stealing:
  Homebrew's `python3` runs through a `Python.app` framework stub, so the
  kernel reports `Python` with a capital P, while `/usr/bin/python3` reports
  `python3` — a case-SENSITIVE test passes on one machine and silently reaps
  nothing on the other. Compare lowercased.
- **What was rejected.** Cleaning up from outside the test run (a wrapper
  script, or a `verify.sh` step) was rejected: it fixes the litter but leaves
  the test itself failing on any busy machine, and it puts the cleanup
  somewhere nobody reads when the test breaks. Keeping a fixed port and simply
  killing whatever holds it first was rejected outright — on a developer's own
  machine that is someone else's process.

One more thing the mac learned here that is NOT about stubs. The app will not
show a preview until the section's built `index.html` has CHANGED, and it
waits up to 120 seconds for that (mac: `waitForPreviewServer` phase 2). A stub
that serves a site from anywhere other than the folder a real build writes into
never trips the check, so the preview arrives two minutes late and the test
times out first — which looks like the server never came up. The stub must
BUILD INTO the watched folder. Whatever Windows' equivalent staleness check
is, its stub owes it the same honesty.

One consequence to know rather than fix: the app still takes a lease from
8081–8084 and still passes `--port <n>`, and the stub now ignores that flag in
favour of what the kernel gives it. That is deliberate — the announcement line
is the contract, and a launcher that could not honour `--port` would still
work — but it does mean this test no longer proves anything about a launcher
HONOURING `--port`, and nothing else covers it on either platform. Do not read
the flag as dead; read it as untested.

## Measured: Edge does not need the `127.0.0.1` rewrite

Measured on Windows, 2026-08-23. The rewrite itself (`OutputParsers.cs`,
`SectionDetailView.xaml.cs`) was applied earlier on the mac's "browsers try
IPv6 first" rationale, without a Windows-side test to back it. Tested by
hand against a real running preview (port 8081, confirmed via `netstat`):
loading `http://localhost:8081` directly in Edge was indistinguishable from
loading `http://127.0.0.1:8081` — both rendered immediately, no perceptible
delay, repeated more than once. No IPv6-first stall observed. Conclusion:
the rewrite is a harmless no-op on Windows as currently shipped, not a fix
for an observed Edge problem — kept in place rather than removed, since it
costs nothing and matches the mac's own defensive posture, but it should no
longer be treated as an open question. No mac change; nothing to port.

- **Windows caught up to the mac's working-folder path bar gestures**
(Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 328, closing
reported from Windows). No mac change — the mac's own path bar is

## The assistant said "deployed" before the deploy finished

Fixed on Windows 2026-08-19; the mac was already correct, so there was
nothing to port. Kept because the REJECTED first fix is a general trap.

The old `TODO.md` entry read: *"Assistant
replies 'deployed' before the deploy finishes (Windows)."* Windows'
`MainWindow.DeployForAsync` used to resolve the instant the click was
dispatched to the UI thread, not when the deploy actually finished, so the
in-app assistant said "is deployed. Students can reach it now." after
every `deploy_section` call regardless of outcome. Fixed by having
`SectionDetailView.Deploy_Click`'s body (now `DeployAsync()`, an
`async Task<string?>`) RETURN the true outcome sentence on every exit path
— success/partial/all-failed via the existing
`MultiDestinationDeployRunner.Result(...)`, `AssistWording.DeployDidNotFinish`
on every early return and the catch block — threaded back through
`MainWindow.DeployForAsync` → `AssistWindow.StartDeployInAppAsync` →
`AssistAgent.RunTool`. Full write-up: `GUI-IMPROVEMENTS.md` row 383.

The mac's `deployAndWait()` already awaits the real result and words it
correctly — this only brought Windows to parity, so there is nothing to
port. Two things worth a mac session's attention, not required, not
blocking anything: (1) whether an equivalent "second deploy request
arrives while one is already running" path exists in
`SectionDetailView.swift`, and if so whether it shares mutable state across
the two in-flight calls the way the first (rejected) fix here did before an
adversarial review caught it — see the "rejected" note in
`GUI-IMPROVEMENTS.md` row 383 for the exact shape of that bug, since it is
a general trap (a single-slot completion field shared across concurrent
callers) worth checking for rather than re-discovering; (2) the Windows
scenario test fixture (`AssistScenarioTests.cs`) never wired
`StartDeployInAppAsync` at all before this — worth checking whether the
mac's own scenario tests exercise the equivalent async production seam or
only a sync stand-in.

## Two testing lessons that recur, and both cost a red branch

**A test proving a date was FRESHENED must compare against a date in the PAST.**
`windows-app/Plantoir.Tests/ModelTests.cs` asserts
`Assert.DoesNotContain("2025-01-01", index)`, and the date being safely in the
past is what makes that a real assertion. The mac's twin used a date that was
"today" when it was written, and on **2026-09-08 the clock reached it**: the
correctly-freshened value became the very string the test checked for the
absence of, so a passing behaviour failed its own test. `dev` was red that
morning for every branch, on a test nobody had touched in three weeks. Fixed on
the mac by moving the fixture to 2020-01-15 (`SectionAdderTests.swift`).
**Do not "modernise" a fixture date to something recent** — the whole point of
that literal is that the clock can never catch up with it, and `2025-01-01` is
already inside the range somebody would be tempted to refresh.

**Cleanup that fails must not fail a test that passed.** An intermittent failure
that never reproduced (Windows, 2026-08-14, `0479d44`) turned out to be 23 tests
ending with a bare `finally { Directory.Delete(root, recursive: true); }`. On
Windows that throws whenever anything still holds a handle in the folder —
Defender scanning the files the test just wrote, or the Search Indexer. Every
assertion had passed; the test failed on housekeeping. Deleting a temp folder is
housekeeping: when it does not work, the operating system will get to it. **The
same shape is available on the mac** with Spotlight indexing, and whether the
mac's suites have it has never been checked.


---

[◀ Previous: Release Strategy](11-release-strategy.md) · [Back to index](README.md)
