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

## Preview and publish mechanics that match the mac (bundle 4, 2026-09-30)

One place for what changed on the preview and publish path in bundle 4, so a
reader of the code finds the reasons. Hardware for every number: Intel Core
i5-8365U, 16 GB, Samsung 980 SSD, Windows 11 Pro 25H2 build 26200.

- **The address (#278).** `ScriptRunner.CapturePreviewAddress` reads COMPLETE
  lines only: the unfinished tail waits for the next piece, colour codes come out
  per line, the carry is flushed when the run ends, and nothing is read back off
  the end of the transcript. Chunk-wise parsing (the old code) takes the wrong
  port when a piece ends after `:8`, `:81` or `:810` — the must-fail reproduced
  `:810`. The wait never starts from the lease's port.
- **The wait (#233).** `PreviewReachability.NextStep` decides each tick; the
  view only acts. The run is never bounded (a first build here: server line at
  43.6 s); the QUIET after `Started a Quartz server` is (45 s, restarted by
  output). Server line to site answering, measured: 0.60 s first build, 0.40 s
  and 0.38 s warm. No announced address when the server starts: give up at once.
  Giving up stops the run the Stop way (so the trail's `task finished` line says
  "stopped by the teacher" right after the `preview did not appear` line that
  explains it — accepted rather than adding a third stop path), then the alert.
  Only a connection REFUSED by this PC is `theSiteNeverAnswered`; a timeout or
  anything else is `plantoirCouldNotTell`. There is no builder to ask, so no
  first verdict. Sentences say "your PC" for "your Mac" (proposed to the mac).
- **A typed publish folder (#304, review L1).** `deploy.ps1`'s
  `Resolve-PublishFolder` takes a plain relative name from the working folder
  (deploy.sh's rule), a fully qualified or UNC path as is, and REFUSES a
  drive-relative (`C:foo`) or root-relative (`\out`) one: `IsPathRooted`
  calls both rooted and `GetFullPath` then resolves them against the PROCESS
  directory (verified: `C:\Windows\foo` with that working directory).
  Rejected: refusing every relative name as the app does — the command line
  and deploy.sh accept one, and #304 asked for it resolved once.
- **Freshness (#272).** `.build-started` beside `public\` is written natively,
  so one clock stamps it and the Save. `BuiltForPreview` reads bytes; the
  `SearchOption.AllDirectories` overload does not skip Hidden items (a default
  `EnumerationOptions` does — the must-fail proved it once the test gave the
  dot folder the Hidden attribute, which NTFS does not do by itself). A
  folder under `public\` that cannot be LISTED answers "rebuild" (review L2):
  its pages were never looked at, and the throw used to escape NeedsRebuild
  and fail the Deploy. Case-sensitivity is pinned by a proposed 16th case
  (the tag in capitals).
- **Two windows (#272).** Measured by reading and then by test before writing:
  Ctrl+N opens a second window on the same folder and each `WorkspaceViewModel`
  loads its own `CourseConfiguration`, so the whole-file `Write` lost the other
  window's Save exactly as on the mac. `Write` now merges per top-level key and
  returns what it kept or replaced; `WorkspaceViewModel.OtherCopiesReread`
  re-reads every other unchanged copy; Revert reads the file. After a Save,
  Course Settings says `settingsSaveReplacedSidebarChange` first, then
  `settingsSavedWhilePublishing` or `settingsSavedWhilePreviewing` with a
  Preview Again button (stops and restarts every open preview of the course,
  in whichever window; `settingsPreviewAgainNothingOpen` and the button
  disabled once none is open); a preview started with unsaved edits in ANY
  window says `previewUsesSavedSettings`. Events: `preview started with
  unsaved settings`, `preview again after settings saved`.
- **The acts read the saved file (#357 / mac #335).** `SavedSettings.Read` at
  the Deploy press (and the assistant pressing it) and in the schedule sheet
  (on open and again at the press); unreadable refuses with
  `settingsCouldNotBeReadToDeploy`, never the window's copy. Unsaved edits
  anywhere: `deployUsesSavedSettings` / `schedulingUsesSavedSettings` and
  `deploy used the saved settings` (kinds only). The section's notices have
  their own InfoBar, never cleared by a preview's end (the mac's F3 trap).
- **Overnight Cloudflare remake (#395).** The wrapper runs a Cloudflare leg
  captured (Start-Process redirection, as the build leg) and appends any
  `PLANTOIR_CLOUDFLARE_REMADE:` line to the section's record; the app writes
  `cloudflare project made again` when it reads it. Every leg's exit is
  `$legExit`.
- **Windowless work (#391, #386).** `AssistWorkspace` runs every leg
  `--non-interactive`; `LaunchOutcome.ExitCode` 3 becomes the contract's
  sentences. The window refuses a preview while `CourseActivity.IsPublishingSection`
  (this process's own Deploys, any window); the in-app assistant asks the same
  record. On Windows the in-app assistant's DEPLOY runs in plantoir-mcp.exe, a
  separate process, so it is the work leases (#289) that refuse a window's
  preview of it — not the in-process record — and the contract's window case for
  that deployer is skipped by name in `PreviewWhileDeployingTests`.
- **The '— Edited' rule 2 (#358).** C#, the wrapper (`--rule 2`, and the rule
  written into its sentinel so an old wrapper's value is recorded as rule 1) and
  the stamp moved together. Found on the way: `section_fingerprint.py` could not
  import `how_i_teach` under the bundled EMBEDDABLE Python (its `._pth` replaces
  `sys.path`), so every scheduled publish recorded no fingerprint; it now adds
  its own folder, as `build_site.py` does.
- **One folder, one id (#307).** A case variant gives the same id (`3566e628`
  both ways) and compares equal; NTFS does not normalise Unicode, so an NFD
  spelling of an NFC-named folder is another (nonexistent) folder — ids
  `b7e56301` / `bbdbaf32` — and there is no second spelling to disagree about.

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

There is no `launchd`. `TaskScheduling` registers a task with **Task Scheduler**
(`schtasks /Create /XML`), and since parity bundle 3 (#347, #289, #239) what
the task starts is PLANTOIR: `Plantoir.exe --run-scheduled-deploy "<task
name>"`, with no window, like the mac's launchd job. `ScheduledRun` decides at
the moment itself (too late to be worth doing, another program building the
course, whether the task still stands, where the course deploys NOW) and only
then writes the wrapper script into `%LOCALAPPDATA%\Plantoir\scheduled\` from
the settings as they are at that moment and runs it. The wrapper fingerprints
the section, builds it, deploys to each destination un-chained (one failing
must not stop the others), and writes a record the app picks up.

The task is registered from XML (`TaskScheduling.TaskXml`) so that it carries
three settings the command-line switches cannot set: it may start on battery
(`DisallowStartIfOnBatteries` false), is not stopped by going onto battery
(`StopIfGoingOnBatteries` false) and starts as soon as possible after a missed
start (`StartWhenAvailable` true). The older description here — a task that
runs `powershell.exe -File "<wrapper>"` — is how a task set before bundle 3
still runs until it drains; do not read it as the current design.

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
  (Eight since 2026-09-30, bundle 3: a build that failed outright is
  `buildDidNotFinish`, naming no destination, and a run that stood down is
  `tooLateToRun`, `courseWasBusy` or `couldNotRunAsSetNow` — the run is
  Plantoir itself now; see 07-deployment → "On Windows since bundle 3".)
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
same into the wrapper script it registers. So a redirected run that PREVIEWS
builds into the REAL `%LOCALAPPDATA%\Plantoir\builds\<folder id>` while the
app's own idea of that folder is under the state directory (so
`BuildFreshness` always says "build", harmlessly), and one that SCHEDULED a
deploy would register a REAL Task Scheduler task whose sentinels land in the
real pending folder. **No test schedules a deploy.** `plantoir-mcp.exe`
resolves its own paths too.

**Previewing and publishing from a test ARE done, since bundle 11
(2026-10-01).** Until then this paragraph said neither was, and that a test
which drove Preview "would NOT be safe". Russell lifted that rule — "I don't
care if you have real build folders. We need to test this. End to end." —
because course import, reference courses, Copy a Page, preview and publishing
had never been proven through the window, and this PC holds no teacher's real
work. What remains is hygiene, and it is `DrivenApp.Dispose`'s job, so it runs
when a test fails as well: see "Driving the real interface" → "A test that
runs a launcher".

**`setup.ps1` was the first launcher run from a test**, and the reasons it
was safe even before that ruling are narrower than they look.
`NewCourseWizardUiTests` presses the wizard's Create button, which runs
`setup.ps1`. **Two guards, neither enforced by anything:**

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
under the real builds root and the real breadcrumb trail was untouched. The
preview and deploy launchers DO make a folder under the real builds root (it is
deleted afterwards, see below), and they write to the REAL trail
(`%LOCALAPPDATA%\Plantoir\Logs\activity.txt`) only on their refusals — "the
preview stopped before building…", "every address … was taken" — which no
end-to-end test provokes; bundle 11 measured the trail's size before and after
its runs (the ready note has the numbers).

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

**The mac has the same flag, by the same name, on purpose (#154) — worth
KNOWING, nothing to do.** One word should mean the same thing to a harness on
either platform. Its root is different: the mac's state is spread across four
`~/Library` folders, so `--state-dir` there stands in for the whole HOME
folder rather than one app folder, and preferences need a door of their own
because macOS's preferences daemon ignores a moved home. The same sharp edge
applies there (children, the launchers, take the real home), and the mac
refuses `launchctl`, notifications, the quit-time container stop and its
updater under the flag; a malformed flag exits 64. Doc 09 → "Testing: the UI
target keeps its state in `--state-dir`". The mac also now drives the
new-site DIALOG through the real window (`NewSiteDialogUITests`, with a
stubbed `deploy.sh`) — the test this platform ruled out, its reason 4 being
that `ToolchainMirror.RefreshLaunchers` replaces a stub launcher on every
`Reload()`. The mac's `refreshLaunchersIfNeeded` leaves launchers alone under
test (a four-line guard; doc 09 → "The first-publish path"), and the same
guard here would make the same test possible. Optional, and not an issue: if
Russell wants it, it becomes one.

**AppKit's frame autosave under test (mac #361, v1.4.1) — worth KNOWING,
nothing owed.** On the mac, AppKit and SwiftUI save window frames and
split-view positions straight into the app's real preferences whatever store
the app picks, so the unit gate and UI runs were moving the teacher's real
main window; a run a test drives now puts those keys back the moment they
change (`AppKitBookkeepingGuard`, doc 09 → "AppKit's own bookkeeping is put
back"). Windows has no analogue: WinUI has no frame autosave, the main window
sizes itself from `App.Settings`, and the assistant's placements live in
`AppSettings.AssistWindowPlacements` — all inside the folder `--state-dir`
moves. No issue, and nothing to mirror.

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

### And when the failure IS real: a red contract test is a handover

Everything above is about telling a genuine failure from a crash or an empty
run. This is the case where the totals line is honest, the named test really
did fail, and it is still not what it looks like.

`AssistCardCommandTests`, `AssistSurfaceContractTests` and `ContractTests`
deserialise `contracts/*.json` and run what they find. Those files are written
on the mac, so **a failure in one of them usually means the mac moved and this
side has not followed yet** — not that somebody broke something here this
afternoon. The mac opens a GitHub issue labelled `windows` in the session it
changes a contract (`CLAUDE.md` rule 3), so there is already a page naming what
moved and what this app owes.

**Read the open `windows` issues before filing a new one — and then check,
because "usually" is not "always".** On 2026-09-09 a session mid-way through
unrelated work met four of these and filed
[#146](https://github.com/russellgordon/plantoir/issues/146) reporting them as
one thing: a contract had moved with nobody told. They were four different
things, and the run is worth knowing as a set.

- **Two had an issue and an unreadable failure.**
  [#70](https://github.com/russellgordon/plantoir/issues/70) had been open since
  19:52 the previous evening, naming the phrasings and the failure itself —
  *"Three more card phrasings will make your suite red"*, and separately the
  parsed make-room family the second test actually failed on. The assertions
  said `Assert.NotNull() Failure: Value is null` and gave the reader nothing to
  search for. They name the phrasing, the tool and the handover now, which is
  the durable half of the fix: a session that meets one is told where to look
  without having to remember this page.
- **One had a perfect failure and no issue at all.**
  `AssistSurfaceContractTests` reported exactly that `back_up_course`'s
  arguments had moved — *"must require exactly the arguments the contract says
  it does"* — and nothing on either platform explained it. Not carelessness: the
  tool was built matching this app's, a review fix twenty minutes later gave it
  a `section`, and the issue written after that described the feature rather
  than the fix. **So when you look and genuinely find nothing, you have found a
  real gap**: say so, and open an issue labelled `mac`.
- **One was this app's own** — a test that had retyped a contract value into a
  literal, so it failed when the contract GREW. No issue elsewhere could have
  named it.

The fourth thing a red contract test can be is a case proposed FROM here, which
turns the MAC's suite red on purpose and is a request rather than damage;
[`contracts/README.md`](../contracts/README.md) covers both directions.

**And a fifth: a handover that has arrived and whose fix is NOT in the release
being cut.** Met 2026-09-18. The mac's unit-word rename moved
`shared-rules.json` — one `activityTrail.mustRecord` event, one
`specialNames.platformWording` key — and the Windows half is
[#158](https://github.com/russellgordon/plantoir/issues/158), milestoned
v1.3.0. `ContractTests.SharedRules_ActivityTrailEvents_Exist` and
`SpecialFolderRenamerTests.EverySentenceTheContractCallsPlatformWordedSaysThisPc`
were red with nothing anybody was meant to do about them yet, which makes
"did anything break?" unanswerable for every other run in the meantime.

Those two are now NAMED GAPS: `windows-app/Plantoir.Tests/NamedGapLedger.cs`
holds one entry per key, carrying the key, the issue, the milestone and the
reason. Everything else is asserted exactly as before, and the ledger fails
both ways — if a ledgered thing starts existing here (saying to delete the
entry) and if it stops being in the contract. **So a green totals line on this
suite can mean "green, with the debts the ledger names"**, and the ledger file is the
one place that says which. `contracts/README.md` → "Named gaps" carries the
boundary: a named gap is allowed only while an open issue milestoned LATER
than the release being cut owns the work, and never for a difference a teacher
can see at the current milestone. Softening the contract instead — an
`appliesOn: ["mac"]` that would be untrue and, having no mend-check, permanent
— was rejected there and the reasoning is worth reading before proposing it
again.

**Since 2026-09-30 the ledger is the parity milestone's BURN-DOWN LIST**
(Russell: no Windows release before parity, so an entry may name an open issue
on "Windows: parity with mac v1.4.0" itself; `contracts/README.md` → "Named
gaps"). Bundle 1 of the parity run widened it from two entries to every debt
the suite could name, so that a red run means something again:

| Area | What is held open | Wired into |
|---|---|---|
| `activityTrail.mustRecord` | 58 events this app does not declare yet, each against the issue carrying its mac piece | `ContractTests.SharedRules_ActivityTrailEvents_Exist` |
| `specialNames.platformWording.keys` | `renameUnitWord.explanation` (#158) | `SpecialFolderRenamerTests` |
| `assist-wording.json` → `wording` | 140 keys with no same-named member on `AssistWording` or `ClassChangeWording` — 34 of them sentences this app says today in words built inline, owned by #157's remaining half (hoist them), the rest by their features' issues | `ContractTests.AssistWording_MatchesContract` |
| `courseConfigKeys` | 7 keys `CourseConfiguration.cs` did not name (#345, #274, #239, #241) when bundle 1 took the count; `curriculum_folders` (#345) left with bundle 6a, the three club keys (#274) with bundle 7 | `ContractTests.FileFormats_CourseConfigKeys_MatchesContract` |
| `modelTiers.requirements` | none since parity bundle 5a (2026-09-30), which answered #196's and #262's three; the area stays so the next mac requirement can be held by name | `AssistSurfaceContractTests.EveryRequirementOfTheLocalAssistantIsAnsweredOrSaidToBeUnexecutable` |
| `sectionIndexPointer.dateCases` | none since parity bundle 7 (the club front-page case runs) | `PagesDatedByTheBuildTests.ThePointerFollowsTheContractsDateCases` |
| `gradedFolders.newCourse.cases` | none since parity bundle 7: the club case runs through `NewCourseAnswers.ForAClub`, the declined-skeleton case (#250) since bundle 6a | `GradedFoldersNewCourseContractTests` |

Bundle 5a (2026-09-30) paid five of those events (`assistant was asked about
another course`, `assistant answer was cut off`, `assistant repeated the request
back`, `scheduled deploy replaced`, `scheduled deploy could not be set`) and
eleven wording keys (#180, #196, #262, #217, #260, #261, #281, #288); the counts
in the table are the ones bundle 1 took, and the ledger file is the live list.

The event-to-issue mapping was made from each event's own `#` references in
the contract, matched to the open `windows` issue that names that mac piece;
where two issues could own one, the choice is the entry's to change. An entry
goes when its issue lands, and the mend-check says so.

**`AssistWording_MatchesContract` walks the file now (#157).** Every key of
`assist-wording.json` → `wording` is resolved by reflection to a public static
member of the same name (first letter upper-cased) on `AssistWording`, then on
`ClassChangeWording`; a constant is compared WHOLE, and the methods keep their
hand-written calls because their example values live in the file, not in a
signature. In the other direction every member of `AssistWording` must have a
key, except the three multi-destination sentences this app words differently
(`WindowsOnlyWording` in the test, mend-checked both ways; owed on #165).
REJECTED: resolving only against `AssistWording` (seven duplicate-and-copy
sentences live in `ClassChangeWording` and would have been ledgered as absent
while being said); a reverse check over `ClassChangeWording` too (it carries
three helpers with no key by design, and the issue asked for the file to be
the list, not for a second allow-list); searching the whole codebase for each
sentence's text (a sentence built inline from pieces cannot be found by its
text, and a text search would call a stale copy present).

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

**One of them now reads a FILE rather than the screen**, and it is worth
knowing why that belongs here. `MarksPoolRemovalUiTests` removes a folder in
Course Settings — the row's own button, the confirmation, Save — and then
asserts that the written `course_config.json` still has no `graded_folders`
key. The RULE is pinned by the unit suite against the contract's seven cases
([#142](https://github.com/russellgordon/plantoir/issues/142), plus the
case-insensitive seventh that Windows proposed and the mac adopted on
2026-09-19, [#172](https://github.com/russellgordon/plantoir/issues/172));
what no unit
test here can reach is that the gesture a teacher makes arrives at that rule
at all, with the confirmation agreeing and Save writing what the rule decided.
Mutation-measured: restoring the pre-fix body fails it with
`graded_folders: ["Thinking Tasks"]` in the file, which is the damage itself,
while the old pool arithmetic over a CORRECT walk leaves it green — so what
it guards is the ORDER reaching the file. It drives no launcher, so the
`--state-dir` caveat above does not bite, and it writes its own one-course
fixture rather than joining `CourseFixtures.WriteBoth`, which every other
suite here reads.

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

### A test that runs a launcher (bundle 11, 2026-10-01)

Until bundle 11 the suite drove no Preview and no Deploy, so course import,
courses kept for reference, Copy a Page, preview and publishing had never been
proven through the window. Russell lifted the rule against it — "I don't care
if you have real build folders. We need to test this. End to end." — and five
classes now run the real launchers:

| Class | What it drives | What it reads back |
|---|---|---|
| `WizardToPreviewUiTests` | the wizard's Create, a line added to the front page, Preview, Stop | the SERVED front page over HTTP (the marker line), the address the window's preview pane LOADED (equal to it, status 200), the build in the real builds root, the address going quiet after Stop; the pane's page text is reported, not asserted |
| `ImportForReferenceUiTests` | File › Import Courses for Reference…, the Windows folder picker, the sheet, Import; the open folder and an empty folder | the done screen's contract sentences, the row under Reference Courses › 2025–26, the copied config's marker and year, the page LOCKED on disk, `.merged_output` left behind, the source untouched |
| `ReferenceCourseUiTests` | the summary, a reference section, Keep a Copy for Reference… twice, Copy a Page from both kinds of row | the contract sentences, Deploy absent/present, pages locked on disk, `codeAlreadyInThatYear` beside a greyed button, `thereIsNoCourseToCopyInto` |
| `CopyAPageEndToEndUiTests` | Copy a Page through its checklist, then Deploy of the destination to a folder; the three refusals | both copies `publishForSection1: false` + `publish: false`, the backup zip, the PUBLISHED folder without either copy, each refusal's contract sentence (the deploying one with a real publishing lease held by the test process) |
| `PublishToFolderUiTests` | Deploy to a folder | the published folder: front page and visible page in, the hidden page nowhere (pages or search index) |

**What a test that runs a launcher owes, and where it is done.** The launchers
build into the REAL `%LOCALAPPDATA%\Plantoir\builds\<id of the test's temp
working folder>` (`DrivenApp.RealBuildsRoot`) whatever `--state-dir` says. So
`DrivenApp.Dispose` — which runs when a test FAILS too — after killing the app:
runs `preview.ps1 CODE N --stop` for every section the test declared with
`WillServe` (the launcher's own sweep, by the directories the build and serve
work in); ends any process whose command line still names the run's
temporary folder or that builds folder (a deploy's launcher, its python);
deletes that builds folder; and unlocks the working folder's courses so a
reference course the app locked can be deleted with it. (Before bundle 11 the
reference tests' temporary folders outlived their runs for exactly that
reason.) Rejected: redirecting `LOCALAPPDATA` for the app's children so the
launchers would build under the state folder — it would have stopped the
tests exercising the real path the ruling asked for, and node and npm resolve
caches from the same variable.

**Still never done from a test:** scheduling a deploy (it registers a REAL
Task Scheduler task), and publishing to Netlify or Cloudflare (a real token, a
real globally unique site — `verify-deploy.ps1` owns those).

**What the first unlocked runs taught (bundle 11, 2026-10-01, this PC: Intel
i5-8365U, 16 GB, Windows 11 26200).** Eleven tests written while the desktop
was locked had never run; the first whole run failed 9 of 33, and every one of
these is now written into the harness rather than left to be rediscovered:

- **A ContentDialog is a `Window` of class `Popup`, named by its title.** There
  is no "ContentDialog" class in the UIA tree, and an empty `Popup` sits beside
  it; `DrivenApp.OpenDialog` tells them apart by the dialog's own buttons.
- **A panel has no automation peer.** An `AutomationId` set on a `StackPanel`
  or a `UserControl` never reaches the tree (`clubLockedRows`,
  `referenceSummary` — the latter moved to its `ScrollViewer`). A test that
  asserts such an element ABSENT passes whatever the screen shows.
- **A folded TreeView item has no children in the tree.** The sidebar's
  Backups group starts folded; unfold it (ExpandCollapse) before asserting a
  backup row is there or gone.
- **`AutomationProperties.AutomationId` replaces `x:Name`, case-sensitively.**
  `DeployButton` matched nothing; the id is `deployButton`.
- **`SetScrollPercent(-1, 100)` on Course Settings' form stuck at 2.8 %**; a
  `LargeIncrement` walk reaches the bottom.
- **An empty `TextBlock` has no Name** (`PropertyNotSupportedException`), and a
  UIA query can time out (`COMException 0x80131505`) while the app draws a
  dialog — both mean "nothing yet", not a fault, for something AWAITED
  (`FindOrNull`). Never for an absence: a negative check built on
  `FindOrNull` passed whenever every query timed out, so negative checks use
  `DrivenApp.AssertAbsent`, which says "absent" only when the tree ANSWERED
  empty and fails when it never answers (`AssertAbsentRuleTests`, plain facts
  that run without a desktop; the timeout case is the must-fail).
- **Click a control only once it has a clickable point**; a dialog opened
  straight after another closed is still arriving (`NoClickablePointException`).
- **WebView2's page text** arrives through UIA lazily, sometimes as Text and
  sometimes as another element's name — and in 3 of 8 runs it did not arrive
  in time (once 0 named elements for 120 s, focused or not). That is Chromium's
  accessibility tree, not the app's, so `WizardToPreviewUiTests` REPORTS it.
  What it ASSERTS is the address the preview pane loaded: in a `--state-dir`
  run the app writes "loaded 200 <address>" into Open in Browser's ItemStatus
  on every completed navigation (the WebView2's own peer drops an ItemStatus
  set on it — measured empty), and the test compares it with the address it
  read the page from (must-fail: a wrong port in it turns the test red). It
  also asserts the served page over HTTP carries the
  teacher's line, and the web view is on screen with a size.
- **A closing dialog's smoke layer** leaves the sidebar with no clickable
  point for a moment; `PressRowMenuItem` waits for one.

Three PRODUCT faults the same runs found, all fixed in bundle 11: Keep a Copy
for Reference… (and Import, same shape) closed the app on its first progress
report — a `Progress<T>` made inside `Task.Run` reports on a pool thread
(`ProgressMadeOnTheInterfaceThreadTests` now refuses the shape); choosing a
folder and then Netlify again in Course Settings left Revert on
(`CourseConfiguration.DeployTarget` now restores the saved spelling); and
every sidebar row's accessible name was "Plantoir.Views.SidebarRow".

Measured for the end-to-end tests on this PC: creating MFM2P in the wizard
29–32 s; its first preview served 52–61 s after Preview was pressed;
publishing a one-section course to a folder 1 m 52 s – 3 m 3 s per test (build
included); the end-to-end set of 13 tests 16 m 47 s – 20 m 33 s; the whole
suite of 40, 43 m 38 s – 48 m 43 s. After the harness lessons above, the whole
suite ran 40 of 40 and the end-to-end set 13 of 13 twice more in a row, with no
launcher left running, no new folder under the real builds root and the real
trail untouched.

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
launches with `UseShellExecute = true` for exactly this reason. Whether `ConPtyProcess.Start` should defend itself was
[issue #89](https://github.com/russellgordon/plantoir/issues/89), and it now does:

**Since bundle 8 (#155), `ConPtyProcess.Start` defends itself.** It zeroes
this process's three std handles around `CreateProcessW`, under one
process-wide lock (`s_stdHandleGate`), and puts them back in `finally`.
Measured 2026-10-01 on this machine (Windows 11 Pro build 26200, 8 logical
CPUs), from the `dotnet test` host, whose stdout and stderr are pipes:
`ConPtyRedirectedParentTests` started `cmd.exe /c echo PTY-OK`. **Before**:
the child exited and the transcript held only ConPTY's two mode sequences
(`ESC[?9001h ESC[?1004h`), no `PTY-OK`, within 10 s. **After**: `PTY-OK`
arrives; both tests together took 118 ms. Rejected: `FreeConsole` (it detaches
the whole process) and the per-instance `_ptyGate` (it would not serialise two
Starts). The cost: while the lock is held, another thread writing to
`Console` loses that output — the GUI app writes none. Launching harnesses
with ShellExecute is still the better habit, and `DrivenApp` keeps doing it.

The app also says so now: when it starts with stdout, stderr or stdin
redirected to a pipe or a file, `startup.log` gets one line
(`StdioState.Describe`), after the `--state-dir` redirect so it lands in the
run's own log. It is for a developer; it is not a trail event.

**The UI-test runner will not close a busy Plantoir.** Busy is
`MachineWork.WhyBusy` (Plantoir.Core, shared with the updater): any live lease
of another process, of any kind, in a working folder the REAL settings name
(read from the unredirected path, never through `AppDataRoot`), or any running
`plantoir-mcp` at all. `DrivenApp` applies it in full and throws "… Not
closing it; run again when it finishes."; `run-ui-tests.ps1` applies the half
it can see without a second copy of the liveness rule — a lease named for a
process that is running right now, or any `plantoir-mcp` — and exits 2. After
a kill, only `*.<killed pid>.lease` is swept, never `*.lease`. Known limit: a
folder opened only through an outside assistant or under `--state-dir` is not
a known folder.

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
  the OUTSIDE doors: `ClaudeCodeLauncher` writes an MCP configuration and starts
  `claude` with `--strict-mcp-config`, so a teacher's own servers are neither
  used nor disturbed. There are TWO of those doors on the mac since 2026-09-19
  — "Revise with Claude…" and "Revise with Codex…" — and this app has only the
  first; both are described as data in `contracts/app-rules.json` →
  `outsideAgents`, which nothing here reads yet. See
  [the assistant](10-local-ai-assistant.md) for what the assistant IS, and
  [its "other doors" section](10-local-ai-assistant.md#the-other-doors-handing-a-course-to-an-assistant-the-teacher-already-has)
  for what each door launches, what was measured and what was rejected.
- **Window and state restoration**, archived courses, problem reporting, and
  the `WorkLease` protocol that keeps two programs from building the same
  course at once — since bundle 3 the mac's rules both ways, take-then-check
  (09-mac-app → "On Windows since bundle 3 (#289)").
- **What is built and what is missing.** Outstanding work is in [GitHub
  issues](https://github.com/russellgordon/plantoir/issues) labelled `windows`;
  the rest of this folder carries the reasoning behind past decisions.

## Nothing here runs in a container

**Read this before the architecture sections below.** Windows dropped Docker,
WSL2 and the whole image/container model on 2026-08-19 (`GUI-IMPROVEMENTS.md`
entry 290) in favour of a **native runtime**: `windows-app/Vendor/fetch-runtime.ps1`
fetches pinned, portable pieces — Node 20 (zip, no installer), Python 3.11
(the embeddable distribution plus `python-frontmatter==1.3.0`,
`PyYAML==6.0.3` and `Pillow==12.3.0`, pinned there since 2026-09-19 and held
against `contracts/toolchain.json` → `pins` by
`ToolchainContractTests.TheWindowsRuntimeRecipeCarriesTheSamePins`; PyYAML is
named explicitly because it is what decides whether a teacher's `publish: no`
hides a page — see
[08 → Whether students see a page](08-course-config-reference.md#whether-students-see-a-page)),
a clone
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
  newline, matching the mac's `/bin/pwd -P | shasum -a 256` derivation. A
  `$CONTAINER_NAME = "teaching-quartz-$WORKDIR_ID"` variable is still
  assigned in each script for parity with the mac's naming scheme, but
  nothing native reads it — the real use of `$WORKDIR_ID` today is naming a
  per-folder build directory, `%LOCALAPPDATA%\Plantoir\builds\<WORKDIR_ID>`,
  so two working folders' builds never collide, and it moves build output
  entirely **out of the working folder**, because teachers keep working
  folders in OneDrive and a build's thousands of small files would sync and
  lock in place there.

  **One folder, one spelling — what the mac learned, for Windows to KNOW
  (GitHub #189, 2026-09-25).** The mac found that its launchers and its app
  named one working folder two ways: bash's built-in `pwd -P` keeps the TYPED
  case and Unicode form (é as one character or as e + accent), while the app
  asked the disk — so a folder reached in the wrong case, or with an accented
  name stored the Terminal way, had two containers and two builds folders
  that cleared each other's builds. The fix there is `cd "$(/bin/pwd -P)"` in
  each launcher and one Swift function (`FolderIdentity.canonicalPath`) used
  for the hash AND every comparison of two folder paths; the reasoning is in
  [03](03-launcher-scripts.md) → "One folder, one spelling" and
  [09](09-mac-app.md) → "One folder, however it is spelled". **Windows has no
  `pwd -P` to get wrong**: `GetFinalPathNameByHandleW` already returns the
  disk's own casing, and NTFS is case-insensitive, so it is the Windows twin
  of `/bin/pwd` and nothing needs to change on the strength of this note.
  The trap, if a new derivation of a folder id or a new folder comparison is
  ever written on that side: take the OS's own name for the folder, never the
  string that was typed or passed on a command line — and use the same
  function for the id and for the comparison, so they cannot disagree. (Git
  Bash's and WSL's `pwd -P` are bash's built-in and keep the typed case.)
  Whether the two already agree on one spelling is a check, not a change; the
  `windows` issue opened with #189 asks for it.

  **A remake never ends live work — what the mac learned, for Windows to KNOW
  (GitHub #94, 2026-09-25).** The mac's launchers used to remove a folder's
  container to remake it (after an update, for a new mount, for a stale
  connection) without looking at what ran inside it, which killed an open
  preview or a publish half-way through its upload. They now wait for a build
  or publish, refuse while a preview whose launcher is still running is open,
  and remove by id ([03](03-launcher-scripts.md) → "Before a workspace is
  remade"). **Nothing is owed here**: Windows builds natively, so there is no
  container to remake, and `contracts/app-rules.json` →
  `previewPorts.whenTheWorkspaceIsInUse` and the `workspace was in use` trail
  event are both `appliesOn: ["mac"]`, permanently. The trap, if Windows ever
  gains something long-lived that is shared by a folder's runs and replaced
  when it goes stale (a warm builder process, a per-folder server): look at
  what is using it before replacing it, and tell a live user from an orphan by
  whether the program that started it is still running — an orphan counted as
  live refuses for ever.

  **Work left behind by a program that closed is ENDED, not waited on — for
  Windows to KNOW, and one thing to OWE (GitHub #378, 2026-09-29).** A
  Revise with Claude session was closed while a deploy it had started sat at
  a question inside the mac's container; every later preview waited ten
  minutes and refused, until the Mac was restarted. The mac's launchers now
  prove each piece of work's OWNER from the live process table (a launcher
  whose own command line names the same course and section; never a
  remembered pid), end work whose owner has gone with the remake's own stop,
  name what they wait for in the status line (`PLANTOIR_WAITING_FOR:`), and
  record `left-over work stopped` ([03](03-launcher-scripts.md) → "Work left
  behind, and proving its owner has gone"). **None of that is owed here**:
  no container, so nothing to wait for and nothing left inside one; the
  contract block and both trail events are `appliesOn: ["mac"]`,
  permanently, and no shared Python changed. **What IS owed** is the cause:
  the mac's MCP deploys and rebuilds were not `--non-interactive`, so a
  `deploy.py` question (a site name, the surname, a token) waited for ever on
  a pseudo-terminal nobody read — `deploy.py`'s own header records the
  Windows twin, a `python.exe` waiting 45 minutes at the site-name prompt.
  `plantoir-mcp.exe`'s deploy and rebuild should pass `--non-interactive`
  and turn exit 3 into `wording.deployNeedsAnAnswer` /
  `deployNeedsAnAnswerAt` / `previewBuildNeedsAnAnswer`; the window's Deploy
  must NOT (its dialog is the feature). The proposed contract case is
  `assist-cases.json` → `scenarios` → "deploy with no section window open,
  which meets a question". ([10](10-local-ai-assistant.md) → "A deploy from
  another app refuses at a question".)

  **A preview cannot start while its own section is being deployed — what
  Windows OWES (GitHub #381, 2026-09-29).** Russell's decision 4 on #378: a
  preview of a section cannot start AT ALL while that same section is being
  deployed, whoever started the deploy. Unlike the remake above this is NOT
  mac-only: `contracts/shared-rules.json` → `previewWhileItsSectionDeploys`
  is `appliesOn: ["mac", "windows"]`, with one case per deployer. The mac
  found two gaps by reading its code, and Windows should check for the same
  two before assuming it has neither: (1) the window's preview asked other
  PROGRAMS' work leases only, never this program's own publishes, so another
  window of the app — or the in-app assistant's windowless deploy — deploying
  the same section did not refuse; (2) `preview.sh` started by hand checked
  nothing, and a bare `deploy.sh` writes no lease. The mac's fixes, to match
  in rule and not in mechanism: a check at the top of the one function every
  window preview goes through, reading the in-process publish record; and a
  check in the launcher, on serving runs only and before anything is changed,
  that reads the LIVE process table for `deploy C S` working in the same
  folder or a deploy set for later of C/S. Three details that are easy to get
  wrong: a `--build-only` run is NOT a deploy (it is also the assistant's
  "rebuild the preview", and counting it refuses every preview with a false
  sentence); a process table that cannot be read lets the preview THROUGH
  (the opposite of the remake's rule, and why is in
  [03](03-launcher-scripts.md) → "A section being deployed cannot be
  previewed (#381)"); and never a remembered process id. Built in bundle 4
  (#386, 2026-09-30): `preview.ps1`'s `Test-SectionIsBeingDeployed` and the
  window's `CourseActivity.IsPublishingSection` — see "Preview and publish
  mechanics that match the mac (bundle 4)" above.
- **Concurrent previews are still isolated by port, exactly as before.**
  `preview.ps1` probes a free block — since bundle 4 (#286) forty of them,
  8081 … 8471 in steps of 10, as the mac launchers do (`Find-FreePreviewPort`;
  `contracts/app-rules.json` → `previewPorts.hostBlockCases`, and 03 → "How a
  folder finds its ports, and when it cannot"). Natively a block is the site
  port and its websocket (+1000). Whose listeners the probe sees (#319) was
  measured in bundle 4: SYSTEM and NETWORK SERVICE listeners yes; a second
  signed-in account was NOT measured (03 → "preview.ps1's own port walk…").
  It prints the exact "Preview will be available at:" line the app watches for. What changed is only what is listening on that port: a
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
- **Port blocks**: `preview.ps1` walks forty blocks (8081 … 8471, since
  bundle 4 / #286, matching the mac's walk from GitHub #280 and
  `build_site.py`'s own native re-probe, which also binds `127.0.0.1` since
  #319): base..base+3 for the preview
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
  zips, never listed). The `<timestamp>` is `yyyy-MM-dd_HHmmss` in the
  **Gregorian** calendar on every machine, which on this side is already
  true by construction — `CourseArchiver.cs` writes and `ArchivedItem.cs`
  parses with `CultureInfo.InvariantCulture`. The mac reached the same
  place on 2026-09-10 ([issue #160](https://github.com/russellgordon/plantoir/issues/160));
  the moment each name is read as is now contract data
  (`contracts/course-management.json` → `zipNames`, the `moment` per case). Backups get their own sidebar group above
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

### What each platform downloads and carries, like for like (mac #312)

Since #312 the Mac app carries its own helper programs and the Linux
virtual machine's starting disk, as Windows has always carried its runtime.
Windows has nothing to DO about it (the contract key
`app-rules.json → helperBootstrap` and the trail events "helper programs
installed" and "website builder created" are `appliesOn: ["mac"]`); these are
the two things it should KNOW. Mac figures measured 2026-09-26 on an M4 Pro;
Windows figures are the v1.1.0 release assets.

| | macOS v1.3.1 | macOS after #312 | Windows (v1.1.0, latest with an installer) |
|---|---|---|---|
| Installer | DMG 58.8 MB | DMG ~410 MB (LZMA; 410,488,446 B at the rehearsal) | PlantoirSetup.exe 235 MB; zip 398 MB |
| Carried inside | app, llama.cpp (25 MB), the build recipe | + Colima, Lima, Docker CLI, buildx, the Ubuntu disk (Apple silicon) | app, llama.cpp, `plantoir-mcp.exe`, the native runtime (Node 20, Python 3.11 and packages, patched Quartz and its node_modules, wrangler, the emoji font) |
| Downloaded on a first run, for building | ~857 MB | ~390 MB (the website builder's image build) | none |
| Update delivery | download the DMG by hand | Sparkle, a delta of 0.1–3.7 MB for a Swift-only release (measured) from the release after v1.4.0 | installer by hand |
| Downloads checked against a pinned SHA-256 | none | every helper, both kinds of Mac, and the disk | since 2026-10-01 (#356): the Node zip, the Python embeddable zip and the emoji font in `fetch-runtime.ps1` (a build-time fetch, not on a teacher's machine); `get-pip.py` deliberately not (below) |
| When the building downloads happen (bundle B) | at the first preview | in the BACKGROUND at first launch, and again when the recipe changes (`setup.sh --prepare-builder`; one sidebar line, four trail events) | nothing to get ready: `builderWarmUp` and its trail events are `appliesOn: ["mac"]` |
| The image itself (#334, bundle B) | full Quartz history, a spare scaffold copy, base tag unpinned | Quartz at depth 1 (≈342 MB first download), no `/opt/quartz-site`, base pinned by digest | no image; the runtime is bundled |

Bundle B's two rows are KNOW, not DO: Windows owes nothing for the warm-up
or the image, because it downloads and builds nothing for building. (The
bundle's brief assumed otherwise, from a stale line in `CLAUDE.md`, corrected
the same day.)

1. **The mac installer is now almost twice Windows'**, because the mac still
   needs a Linux virtual machine and Windows does not.
2. **The mac now checks every helper download against a pinned SHA-256**
   (the launchers' shared first-run block). **`fetch-runtime.ps1` now does
   the same for the three FIXED downloads (#356, 2026-10-01)** — the Node zip,
   the Python embeddable zip and the emoji font — and refuses (deleting the
   file) on a mismatch. The pins were measured on the build PC (i5-8365U,
   Windows 11 26200), not copied: Node's equals nodejs.org's own
   `SHASUMS256.txt` for v20.18.1; the Python zip's `python.exe` and
   `python311.dll` are byte-identical to the runtime that has shipped; the font
   equals the shipped font. Proven by running the script's own `Fetch` (lifted
   out of the file by its syntax tree, against a `file://` copy): the right pin
   keeps the file, one wrong hex digit refuses it and leaves nothing behind.
   **`get-pip.py` is NOT hashed, deliberately**: `bootstrap.pypa.io` serves one
   moving file with no versioned URL, so a hash would break the build on pip's
   next release while protecting nothing the exact package versions (fetched by
   pip from PyPI over TLS) do not. **Also rejected:** hashing the Quartz clone
   (it is a tag on GitHub fetched by git, which checks its own objects) and
   wrangler (`npm install` of an exact version; npm checks each package
   against the registry's own integrity hash). It runs when the Windows app is BUILT, not on a teacher's PC;
   the reason to do it anyway is that the build PC is where a swapped file
   would enter every installer.
3. **What #356 asked Windows to confirm, confirmed (2026-10-01):**
   `scripts/test_helper_bootstrap.py` SKIPS here (`python
   scripts\test_helper_bootstrap.py`: 5 tests, OK, skipped=5) and
   `ContractTests.SharedRules_ActivityTrailEvents_Exist` is green with the two
   mac-only events filtered by `appliesOn`.

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
  The scenario test suite in the macOS app is the porting spec. **Since #311
  the FOLDER comes back whatever happens to the window set** — the first
  window reopens the last working folder (the one last in FRONT, not last
  chosen), and a failed reopen says why in one sentence and is kept:
  `contracts/shared-rules.json` → `reopeningTheLastWorkingFolder`, whose
  `launchCases` and `folderCases` are the acceptance list; the reasoning is
  in [`09-mac-app.md`](09-mac-app.md) → "Reopening on the last working
  folder (#311)". **The
  other half of that — what a window lets GO of when it is pointed at a
  different folder** — is `contracts/shared-rules.json` →
  `workingFolderSelection`, and since 2026-09-19 all four of its cases run
  here too: both adoption routes go through one funnel,
  `WorkspaceViewModel.PointAtFolder` → `WindowFolderState.PointAt`. The
  reasoning is in [`09-mac-app.md`](09-mac-app.md) → "What a window lets go
  of when it changes working folder"; what is Windows' about it — the state
  having to move into Core before any test could reach it, which folder a
  teardown names, and the one notion of "the same folder" — is at the foot of
  this page.
- **New windows** (entry 84): inherit the folder of the window that was
  key when the command ran; with no windows open, show the folder picker.
  Decide the folder BEFORE first paint or the picker flashes.
- **Updates** (#204): **NetSparkleUpdater**, not WinSparkle — corrected
  2026-09-25, when the mac shipped Sparkle and the Windows half was drafted as
  its own `windows` issue (milestone v1.4.0). NetSparkle reads the same feed
  format and can run the per-user Inno installer silently
  (`PrivilegesRequired=lowest`, so no administrator prompt — unlike a standard
  account on a Mac). Its OWN feed, `https://plantoir.app/updates/windows.xml`
  (never a GitHub release asset, never shared with the mac's
  `updates/macos.xml`), signed with its OWN key, with NetSparkle's separate
  `.signature` file beside it. What is owed is the promise, not the mechanism:
  `contracts/shared-rules.json` → `appUpdates` (ask first; once a day; never
  install while this app is publishing or building a preview, or a scheduled
  publish of this install is running — Task Scheduler's run is the counterpart
  of the mac's launchd one; never refuse a quit), and the eight trail events it
  added to `activityTrail.mustRecord`. NetSparkle gathers the notes of every
  newer release itself, so a skipped release's warning is not lost the way it
  would be on the mac without the cumulative notes; each Windows item carries
  only its own. The mac's reasoning: [`09-mac-app.md`](09-mac-app.md) →
  "Updating itself". (Earlier drafts of this line said WinSparkle with
  `site/appcast-windows.xml`, and before that one shared appcast.)
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

## Reading a page's visibility: four .NET defaults that get it wrong

The rule itself — what the BUILT SITE does with a `publish:` line, and why
that is not what reading the line suggests — belongs to
[08 → Whether students see a page](08-course-config-reference.md#whether-students-see-a-page),
and `Plantoir.Core/Models/PageVisibilityReader.cs` is the same rule as
`scripts/page_visibility.py` and the mac's Swift file of the same name. What
is worth writing down HERE is the part that is about C#, because a
transliteration of either reference is wrong in four places and every one of
them is silent (issue #140, 2026-09-19):

- **`Trim()`, `TrimEnd()` and `char.IsWhiteSpace` strip the non-breaking
  space.** YAML's whitespace is a space and a tab and nothing else, so
  `publish: false<NBSP>` is the string "false " and the page is
  PUBLISHED. Trimming it calls a live page hidden — the one direction that
  must never be wrong. `Block.IndexOf` used both of these. Trim space and tab
  by hand. (The single exception is the DRAFT family's final compare, which
  mirrors Python's `str(value).strip()` inside `build_site._as_bool` and so
  *should* strip it.)
- **`StartsWith`, `EndsWith`, `IndexOf(string)` and `Contains(string)` are
  CULTURE-SENSITIVE by default**, and a culture-sensitive compare matches
  across characters it considers ignorable. Every one of them in this reader
  passes `StringComparison.Ordinal` explicitly. `string ==` is already
  ordinal, but it is written as `string.Equals(..., Ordinal)` where the answer
  turns on it, so nobody has to remember which operators are which.
- **`ToLower()` is not `ToLowerInvariant()`.** In Turkish, `I` lowercases to a
  dotless `ı`, so `TRUE` would stop being `true`.
- **`string.Split('\n')` is right and `splitlines()`-style splitting is not.**
  Both references split on `"\n"` alone and strip a trailing `\r` per line;
  splitting on every Unicode line break would find boundaries inside a
  teacher's value.

Two faults found here were in the WRITER rather than the reader, and both are
worth knowing because they are the shape a writer goes wrong in: `ReplaceValue`
looked for an inline comment with `IndexOf('#')`, so hiding a
`publish: "false # why"` page left an unbalanced quote in the teacher's file;
and `Block.Parse` demanded exactly `---` on line 0 while accepting `...` as a
close, where python-frontmatter's boundary is `^-{3,}\s*$` for both — so a page
fenced with `----` got a second block PREPENDED and the teacher's real
frontmatter became body text on the student's site.

One fence finder and one key matcher now serve the reader and every
writer. Until 2026-09-30 two finders were hand-rolled and strict here:
`CourseRestorer.FrontmatterBounds`, which a restore used — lenient on the mac
since #140, so a restore reached different pages on the two platforms
([issue #177](https://github.com/russellgordon/plantoir/issues/177), decided
2026-09-19: adopt the shared finder) — and `SectionAdder.FrontmatterLines`,
whose strictness was measured on the mac (#175) to PUBLISH a page hidden in
section 1 into a newly added section. Parity bundle 2 removed
`FrontmatterBounds` and pointed both at `PageVisibilityReader.FenceIndices`
(#177/#308 with #182's carry-the-value-lines restore; #282 with the splice by
line), and since the fix round a per-section key is named by ONE helper,
`SectionAdder.PerSectionKey`, which accepts the quoted spelling too — see
`documentation/08-course-config-reference.md` → "A writer must find the BLOCK".
`AssistWorkspace.BodyAfterFrontmatter` is still hand-rolled (it trims and
accepts `...`); the #188 rule is what it should agree with if it is touched.
Only `BodyAfterFrontmatter` is still its own finder here (the mac keeps
several). Check which one you are looking at before "tidying" any of them.

A third fault was shared with the mac and **was fixed here first, on
2026-09-19; the mac followed the same day.**
Both writers replaced a key's line and orphaned the indented CONTINUATION
line below it onto the new value, so **hiding** a page whose value is a block
scalar left it PUBLISHED — the failure that reports success, and reached by
the very rule #140 introduced ("on `cannot tell`, write the flag out in
full"), so it could not ship as a known issue. `PageFrontmatter
.ContinuationLines` takes those lines with the key in both of `SetDraft`'s
branches, following `setup_course.per_section_frontmatter`'s loop —
stepping over blank lines and `# note`s **at any indent**, so a complete
value's note stays where the teacher wrote it and a column-0 note between a
key and its value does not end the walk. That second half was got wrong here
first (the sweeper stepped over indented comments only, orphaned the value and
stopped the build) and it was still wrong in the shared Python until the mac's
half landed; `setup_course.per_section_frontmatter` now steps the same way.

**And the half of it a sweep cannot reach, which is the part worth carrying
away.** `publish: false` with an indented `false` under it is the string
`"false false"` on the site and the page is PUBLISHED — but the reader called
it hidden, and called it CONFIDENTLY, so `SetDraft`'s "already right, change
nothing" gate returned before the writer ran at all. Hiding the page was a
no-op the teacher was told had worked. A sweep in the writer is no use
against a request the writer never receives: `PageVisibilityReader.ReadScalar`
had to stop trusting the key's own line, and it now answers `cannot tell`
whenever the first line that could be a value is indented. **The lesson
generalises past this bug** — when a reader and a writer are fixed in the same
piece, check which of them the guard clause runs in.

[Issue #176](https://github.com/russellgordon/plantoir/issues/176) carries the
measured table and both halves. It was taken on Windows first even though a
one-sided fix in this field is normally a silent divergence, because the
divergence was Windows being right; the mac took it the same day and
implemented this design unchanged, so the two apps agree at the THREE-WAY
level again. What landed with the mac's half and reaches this side:
`contracts/file-formats.json` gained two `readingCases` (the two continuation
forms the SITE publishes, where each app's reporting answer agrees with it —
`PageFrontmatter.IsDraft` is `Answer(...) == Hidden` and `ReadScalar` already
answers `CannotTell`, so both pass here unchanged) and three `writingCases`
for the sweep, which `FileFormatContractTests
.TheWritingCasesInTheContractAreFollowed` now runs. Those three were derived
from `ReplaceValue` and `ContinuationLines` by reading rather than by running
— macOS cannot build `net9.0-windows` — and checked against a transliteration
calibrated on the ten cases already in the list; if one is red on this side it
is a real difference and worth an issue back, saying which case and what
Windows produced. The reasoning lives in
`documentation/08-course-config-reference.md` → "A writer must take a value's
CONTINUATION lines with the key".

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
  **Mirrored on Windows 2026-09-30** as
  `Plantoir.Tests/ActivityTrailWiringTests.cs`: every `ActivityTrail.Event`
  member must be referenced as `Event.X` on a non-comment line of product
  source (`windows-app/` minus the test projects and build output) other than
  its `KeyFor` arm, with a floor of 100 files so a moved folder fails. One
  event is written through a helper rather than `Note(Event.X, …)` —
  `assistant asked`, by `ActivityTrail.NotePrompt` — and is listed with its
  helper, which must itself be called. An event the contract names that this
  app has not DECLARED is the other test's business
  (`SharedRules_ActivityTrailEvents_Exist`, or a ledger entry), so together
  they say: every event the contract asks of Windows is declared and
  referenced, or ledgered by name. On the day it was written every declared
  event was referenced.
- **Its honest limit, so nobody oversells it**: the scan proves a call site
  EXISTS, not that it is reached. The mac additionally runs `noteLaunch()`
  and `noteHelpers(_:)` (split since #222, because the helpers line waits for
  the programs to be asked) against a scratch store and counts the three lines. Full runtime coverage
  of every event would mean driving every feature in unit tests; REJECTED as
  disproportionate — the failure Windows actually shipped was
  zero-references, which the scan catches outright.
- **The suite-pollution fix differs by platform for a reason.** Windows'
  `[ModuleInitializer]` redirect (`TestTrailRedirect.cs`) is right for xUnit,
  where tests run in their own process. The mac CANNOT use that shape: its
  test target is app-hosted (`TEST_HOST`), so the host app writes its launch
  lines before any test-bundle code loads. Instead the redirect lives in the
  product (`ProblemReportStore.standard` returns a throwaway folder when
  XCTest is loaded in the process — `RealHome.isInsideTestBundle` since
  #264; it read `XCTestConfigurationFilePath` from the environment before),
  and
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
waits up to 120 seconds for that (mac: `waitForPreviewServer` phase 2 — which
since 2026-09-20 also breaks out early when the run has announced its server
and then gone quiet for 45 seconds, so the late arrival is now about 45 s
rather than two minutes; the cap itself is unchanged). A stub
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

**(2) is now settled on this side**, 2026-09-09: the scenario fixture wires
`StartDeployInAppAsync` and nothing else, so every deploy scenario goes
through the production seam. The mac's own fake window has always returned
a result from its `deploy` closure (`FakePreview.swift`), so it never had
the sync-only gap. See "The scenario runner runs the REAL tools" below.

## Three testing lessons that recur, and each cost a red branch

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

**The shared state a class must be serialised against is not always a static —
it can be a folder on the machine.** `SharedActivityState` was created for
process-wide statics (preview leases, the publish registry) and its name still
says so, but the question it answers is *what does this class touch that
outlives it*. Two things beyond statics now qualify, both learned from a real
red run:

- **The activity trail's log path.** Five classes redirect it to a scratch file
  and then assert on what is in that file, so a class merely WRITING trail lines
  — `ScheduledHealthFindings.Take` leaves a `folder problem found` line — can
  drop them into somebody else's fixture mid-assertion. Writing them is enough
  to belong in the collection; redirecting is not the only way in.
- **`%LOCALAPPDATA%\Plantoir\scheduled`.** The generated wrapper resolves
  `$healthDir` and `$pendingDir` from `$env:LOCALAPPDATA` at RUN time, which is
  why `ScheduledWrapperRunTests` and `ScheduledPublishOutcomeTests` can
  substitute the baked OUTCOME folder and cannot substitute that one. Both run
  wrappers for ICS3U section 1; a stub build that finds nothing takes the
  wrapper's nothing-found branch and DELETES the folder-problems record for that
  section — the record the other class has just written and is about to read. It
  showed as one red `AWorkingFolderWithSpacesInItsNameStillBuilds` on
  2026-09-18 (`Assert.Single` on an empty list), green alone and on re-run.
  Both classes are in the collection since 2026-09-19. **That fixes the two
  classes against each other and nothing against the MACHINE**: xUnit cannot
  serialise the suite against a real scheduled publish for a course called
  ICS3U running at half six, which would write and consume the same file — and
  `Take` consumes the record, so a genuine overnight finding cleared by a
  test's stub build is never noticed. Making those directories injectable is
  [issue #179](https://github.com/russellgordon/plantoir/issues/179).

The general rule, and the cheap check when a test fails once and cannot be
reproduced: **ask what the class writes that another class can see** — a static,
a process-wide setting, a real per-user folder, a scheduled task — and look for a
second class writing the same thing with the same key. `--state-dir` and a
substituted literal move SOME of it; neither moves what a child process resolves
from the environment.

## The scenario runner runs the REAL tools

`windows-app/Plantoir.Tests/AssistScenarioTests.cs` runs the cases in
`contracts/assist-cases.json`. Until 2026-09-09 it answered every tool call
with the string `"Done."`, and it read neither `given.saying` nor
`expectTranscriptContains` — the only two keys the three rollover cases carry.
Each of those ran a single turn with every assert block skipped, so they passed
having checked nothing whatever (issue #141). **That is the failure the shared
contract exists to prevent, wearing the contract's own colours: a case both
platforms believe the other one is covering.**

**A fixture that invents its own answers cannot assert the product's
sentences.** The rollover cases name `wording.rolloverWebsiteQuestion` and
`wording.rolloverWebsiteNotDecided`, which only `PlantoirTools.ReDate` can
produce. So the fixture stopped inventing them: `RealTools` dispatches to the
real `PlantoirTools` against a course in a temp folder, which is the shape
`AssistFixture.makeRunner` has had on the mac since the scenario suite shipped.

Five things about it are decisions rather than details.

- **The launcher is the only seam**, as `AssistSiteWork` is on the mac.
  `FakeLauncher` records what it was asked to run and reports success, so
  `AssistWorkspace.Deploy` runs for real above it — every refusal it checks,
  every destination, and the real `AssistWording.Deployed` at the end. A deploy
  scenario would otherwise build a Docker image. The mac asserts
  `siteWork.deploys == 1` where this asserts one `deploy` run on the launcher;
  the contract's own name for that is `runLauncherDirectly`.
- **Reflection over `PlantoirTools`, not a `plantoir-mcp` process.** Driving the
  server over stdio works and leaves a process holding `Plantoir.Core.dll` open
  if anything goes wrong, which fails the NEXT build with a lock error reading
  "the app is open" when the app is not open at all. `AssistSurfaceContractTests`
  made the same trade. The binder drops an argument the tool does not declare,
  as the SDK's own binder does — `AssistAgent.RunTool` sets `preview` on tools
  that do not all take it — but everything else about it fails LOUDLY, because
  a runner that quietly drops an argument is #141 again: a declared argument
  that cannot be converted throws, a required one nobody sent throws rather
  than binding `null`, and names are matched case-SENSITIVELY, since the
  object the server really receives is a case-sensitive JSON object and a case
  sending `Course` must not pass here while failing on the wire.
- **A "write" is noted when the watched page changes ON DISK**, not when the
  tool is called. `FakeSectionWindow` mirrors the mac's `FakePreview`: the order
  is the assertion, and stopping, writing and starting can all happen and still
  be wrong. A preview stopped *after* the pages were rewritten was serving a
  half-changed site in between, which is the fault the case exists for. Recording
  "write" at call time would assert the order the fixture chose rather than the
  order that happened.
- **`schtasks` is stubbed** through `TaskScheduling.SchtasksForTests`, and the
  class is therefore in the `SharedActivityState` serialized collection. Without
  it, a rollover that cuts a section loose runs `schtasks /Delete /F` against
  whoever's Task Scheduler is running the suite. `RolloverWebsiteTests` reached
  the same conclusion first.
- **`sectionWindowOpen` defaults to FALSE**, as on the mac. It defaulted to true
  here, which quietly gave every card scenario a section window it had not asked
  for and answered its deploy by pressing a button instead of running a launcher.

**Verify a scenario runner by falsification, never by a green run** — green is
exactly what the broken one was. Each of these was run against a temporary edit
to `PlantoirTools.cs` and reverted: reintroducing the #120 answer-turn no-op
fails case 2 on `rolloverIsOnANewWebsite`; making the bare rollover say nothing
about the website fails case 3; making it propose rather than answer fails case
3 on the card that `when: "say"` forbids; and moving the website sentences into
the model's half only — the exact defect the case's own `why` describes — fails
all three. A case that cannot be made to fail is not testing anything.

## A fixed phrasing reaches a tool no model is shown — and inherits none of the model's guardrails

Added 2026-09-09 with issue #70's five card phrasings and the parsed
`make room for <count> class|classes at unit <U>, day <D>` family.

**The idea is worth more than the five sentences.** A card phrasing is matched
in `AssistCardCommand` and never reaches a model, so adding one costs the
router nothing — the measured 13-tool local surface is what routing accuracy
was measured against, and it is untouched. That means MCP-only is a statement
about what the MODEL is SHOWN, not about what a teacher may ask for. Anything
MCP-only is a candidate.

**What it does NOT inherit is every check that hangs off being routed**, and
that is where the afternoon went. Four defects, each invisible until a
phrasing made a teacher the caller:

- **`AssistAgent.PlanTwins` is a hand-written map**, and it was written
  against "writes the local model can reach". `make_room_for_classes` is
  MCP-only, so it was not in it — and it is the most far-reaching tool on the
  surface, renaming pages a teacher's links point at. Without the entry it
  would have been the ONE card that ran with nothing shown first. If you add a
  card phrasing, check that map by hand. (This used to say the mac could not
  have the hole because `planTwinName` DERIVES the twin. It had its own:
  `add_curriculum_mentions` derived `plan_add_curriculum_mentions`, which does
  not exist, so the mac's gate ran that write with no plan — reachable only by
  a model naming a tool it was not offered, which the mac also did not refuse.
  Both closed in #327: an explicit `irregularPlanTwins` map, and a refusal for
  any tool the model was not offered — see doc 10, Part 6. `tools.planTwins`
  now carries the pair.)
- **A plan twin that returns a bare `string` cannot say it is a plan.** The
  mark is `_meta["plantoir.app/isPlan"]`, set only by `PlantoirTools.Proposing`,
  and `AssistAgent.ShowPlan` reads an unmarked answer as a REFUSAL: it prints
  the words and never offers Go. `plan_make_room_for_classes` shipped that way
  and nothing noticed, because Claude Code reads the words either way and so
  does every test that asserts on the plan's TEXT. Adding it to `PlanTwins`
  would have made the tool unrunnable from the app — a plan a teacher could
  read and never accept. `AssistSurfaceContractTests.EveryPlanTwinTheGateRunsCanSayItIsAPlan`
  now checks the RETURN TYPE of every twin the gate runs, which is the thing
  that makes the mark possible; it unwraps `Task<>`, since an async tool marks
  just as well. (The mac pins the same property by RUNNING every `plan_` tool
  on a happy path, since its return type is always `AssistToolOutcome` — #150,
  doc 10 → "A plan has to be able to SAY it is a plan". Since #150 the
  contract also DECLARES "make room for a class at Unit 3, Day 4" in
  `cardPhrasings.parsed`, so `InsertClassesTests`' local pin of the article
  form can read the contract instead — optional, not owed.)
- **A sentence written for a model becomes a sentence a teacher reads.**
  `explain_publishing`'s second answer said "Don't repeat it — carry on with
  what the teacher asked", which was harmless while a model was the only
  caller. A tool result renders as an ordinary assistant bubble; there is no
  channel here only a model sees. The mac made and corrected this same
  mistake, and the contract pins the replacement (`publishingAlreadyExplained`).
  `back_up_course` had the same shape: it answered with a path on disk, which
  rule 1 of `CLAUDE.md` keeps out of what a teacher reads, and the contract's
  `backedUpCourse` was already the sentence to say.
- **Suppression that suits a model does not suit a teacher.** `Briefing` wrote
  a marker file under `courses/.internal/assist/`, so a section briefed once
  was never briefed again in that folder. Defensible for a model: it is the
  model the repetition would bore, and a session cannot repeat itself after it
  has ended anyway. Once a teacher can TYPE the question, a file on disk means
  the answer arrives once per working folder, ever — and answering a question
  with "I explained that before" is refusing to answer it. It is now
  `AssistWorkspace.NoteExplainedThisConversation`, beside `_conversationBackups`
  and living exactly as long: one assistant window, or one `plantoir-mcp`
  process. Old `.explained` files are inert and are not cleaned up; nothing
  reads them.
- **The first answer is now the mac's sentence (#157, 2026-10-01).**
  `explain_publishing` said this app's own three paragraphs (`Briefing.Words`,
  which named the course's destination) while the mac said
  `wording.whatPublishingMeans`; `list_courses` in an empty folder said "This
  working folder has no courses yet." where the mac says `wording.noCoursesYet`,
  which also says what to do next. Both are teacher-visible through the fixed
  phrasings, so they were matched rather than ledgered: `AssistWording` carries
  both constants, the wording walker compares them with the contract, and
  `Briefing` is gone. What was given up on purpose: naming the destination in
  that answer. The mac's sentence names none, so it cannot promise a place the
  deploy does not go — which was the only reason the old answer looked it up.
  The unknown-course refusal still ends "This working folder has no courses
  yet." — a clause in a different sentence, with no contract key of its own.

### Two more the same pass turned up

**`back_up_course` credited the teacher with a copy they never made.**
`AssistWorkspace.BackUp` called `CourseArchiver.BackUpCourse` with no
`BackupMaker`, so it recorded `DefaultTeacher`. Two consequences, and the
second is the one that bites: the Backups list says "made by you", and
`PruneBackups` deliberately skips anything that is not the assistant's — so a
session following the tool's own advice to back up "before any bulk editing"
would write a whole-course zip every time and none would ever be cleared, with
`MostBackupsKept` never applying. The tool now takes the `section` the contract
has required of it since it arrived, and attributes to `BackupMaker.Assistant`.

**`add_classes` and `plan_add_classes` took a `firstDay` the caller could get
wrong.** It defaulted to 1 and was described as "1 unless the earlier days
already exist" — a question answerable only by going and looking at the
section. Measured: "add five more days to Unit 4" on a unit already holding
Days 1–3 planned Days 1–5, reported three as already there, and created **two**
pages for a teacher who asked for five. `AssistWorkspace.DayToCarryOnFrom`
works it out from the pages on disk, published or NOT — a class a teacher has
written and not yet shown anybody is still a day of the course, and numbering
over it would collide with a real file. The logic already existed inside
`PlanAddNextClass`; it was only the tools that asked. This closes the
divergence issue #70 described, in the direction it suggested: an argument
nobody can get wrong beats one with a sensible default.

### A stamp that cannot be true never decides what gets deleted

Added 2026-09-19 for [issue #161](https://github.com/russellgordon/plantoir/issues/161),
which arrived from the mac. It belongs beside the two above because it is the
same kind of fault — a rule that is right about the common case and silently
destructive about one it never considered — and because `PruneBackups` is the
code the `back_up_course` fix above was about.

`CourseArchiver.PruneBackups` sorts the assistant's backups by the date parsed
out of their file names and deletes everything past the fifth. **This app has
always written that stamp correctly**: `CourseArchiver.TimestampedName` and
both readers (`ArchivedItem.From`, `BackupItem.From`) are pinned to
`InvariantCulture`, so no Windows machine has ever written its own calendar
into a name. The mac did, until 2026-09-10 — a `DateFormatter` with a format
and no locale renders `yyyy` in whatever calendar the Mac is set to — and a
working folder moves between machines. So a folder carried from a pre-fix Thai
Mac holds `ICS3U_backup_2569-08-09_141530_assistant-section1.zip`, invariant
parsing reads that cleanly as the year **2569**, it sorts as the newest thing
in the folder, it takes one of the five kept places, and a real backup is
deleted. Nothing reports a fault.

`Plantoir.Core/Models/ArchiveStamp.cs` is the answer, matching the mac's type
of the same name:

- **`EarliestPossible` = 2025-01-01.** The floor is "before Plantoir could have
  written one", not a round number — the archive feature was written
  2026-08-09, so no zip of this kind is older than that. It is set a year and a
  half earlier so no real name is ever refused (a machine whose clock is a few
  months out still writes a name this accepts), and it still clears the nearest
  wrong reading — Ethiopic `2018-12-03` — by six years. Any floor between the
  two works; one in the middle is wrong in neither direction.
- **`FutureAllowance` = 2 days.** Not one. The stamp is local wall time on BOTH
  ends, so a zip written this morning in Kiritimati (UTC+14) and read the same
  morning on Baker Island (UTC−12) is 26 hours ahead of `DateTime.Now` — absurd
  as travel, ordinary as a folder in OneDrive — and two days also absorbs a
  daylight-saving step. The extra day costs nothing: no wrong reading of any
  calendar lands within a year of the ceiling.
- **Both bounds inclusive, local time, never `UtcNow`.** A parsed stamp comes
  back through `TryParseExact` as `DateTimeKind.Unspecified` and means what the
  clock said where it was written; measuring it against a UTC now would refuse
  real names for up to half a day at either end of the world. `now` is
  injectable so a test's answer cannot change between one assertion and the
  next; nothing in the app passes it.

The guard itself is one `continue` in the COLLECTION loop, which is the part
that matters: a refused backup is **neither counted toward the five nor
deleted**, and it stays LISTED. Its date is the only thing about it known to be
wrong, and a teacher may still want to restore it or delete it themselves.

**No sentence and no trail line**, both deliberately, both matching the mac.
Nothing a teacher can see changes — the zip they had is the zip they still have
— so there is no wording to add; and a new `activityTrail.mustRecord` key would
turn the mac's suite red for a line the mac chose not to write. A prune line
answers a question about a COUNT, not about a moment.

**The accepted cost, written down here so it is not rediscovered as a bug.** A
PC whose clock is badly wrong — a dead CMOS battery reading 2009 or 1601, or a
machine days fast — stamps *every* assistant backup implausibly. None is ever
counted, so none is ever pruned: one zip per conversation, for ever, on a course
that may be hundreds of megabytes. That is the right trade, because the two
failures are not symmetrical. A disk filling slowly is visible, complained
about, and recoverable by deleting backups from the list; a deleted backup is
none of those things. It is worth naming on this side in particular: a dead RTC
on a desktop PC is commoner than the mac's write-up weighed, and this is the
platform where the folder is most likely to have travelled.

**One sentence it makes approximately false, and why it was left alone.**
`BackupItem.KeptDescription` tells the teacher "The assistant made this one; its
five most recent are kept" about a zip that will now never be pruned. The mac's
`BackupItem` says exactly the same thing, it is not contract data, and neither
side changed it — so the two still match, and this is a shared decision rather
than something each platform finds separately. Changing it would mean saying
"unless its date is implausible" to a teacher who has no idea their folder came
from a Thai Mac, which is rule 1's problem rather than a fix.
**The same is true of one sentence in `documentation/10-local-ai-assistant.md`,
and it is NOT left alone — it is fixed on the mac's branch.** "Prune only the
ASSISTANT's own backups, keeping its five most recent per course" is now
approximately false in exactly the way `KeptDescription` is: the five kept are
the five most recent PLAUSIBLE ones, and an implausible zip is kept beside them
for ever. (It would be fair to say the guard makes the sentence's INTENT truer
— a 2569 zip was stealing one of the five — but the sentence as written still
describes something the code no longer does, and that is the kind of
almost-right line that gets believed.) It is not corrected here, because 10 is a
shared page and `origin/issue/160-archive-stamp-calendar` already rewrites that
bullet with the caveat and a pointer to `09-mac-app.md` for what it costs;
editing it from this side would conflict with that branch for no gain. **When
#160 merges, check that bullet reads correctly for both platforms** — the mac's
wording says "since 2026-09-10", which is its date, not this one's.

**Tests** are in `CourseBackupTests` (`ModelTests.cs`) — a plain temp-folder
class, nothing process-wide, so it stays out of `SharedActivityState`. The one
worth copying is `PruneBackups_ABackupWhoseStampCannotBeTrue_IsNeitherCountedNorDeleted`:
it asserts the number of surviving REAL backups, not merely that the 2569 zip is
still there, because a guard that worked by refusing to PARSE the name would
pass the weaker assertion while still deleting two real copies instead of one.
`PruneBackups_AStampPastTheCeiling_CountsOnceTheClockCatchesUp` is the reason
`PruneBackups` takes a `now`: the ceiling is half the rule and nothing on disk
exercises it, since whether a stamp is past it depends on when the suite runs.
It asks about ONE file twice with the clock in two places — three days ahead of
`now` it is uncounted and undeleted; with `now` moved forward two days it is
counted, and being the newest it keeps its place while the oldest real backup
goes. Without that test the parameter was dead plumbing described by a comment
that was not true, which a review caught.
Three mutations were run: removing the `continue` reddens the 2569 and
below-floor tests; making either bound exclusive reddens
`CouldHaveBeenStamped_IsInclusiveAtBothBounds`; dropping `, now` where
`PruneBackups` calls the guard reddens the ceiling test.

**Part 2 of #161 is deliberately not done, and the issue stays open.** The mac
turned these bounds into contract data — `contracts/course-management.json` →
`zipNames` → `couldHaveBeenStamped`, ten cases plus the two bounds, and a
`moment` on each recognised `zipNames` case. That block was on the unmerged
`issue/160-archive-stamp-calendar` branch when this was written and **reached
`dev` on 2026-09-19 with #160** (mac GUI row 498), so nothing blocks part 2 any
more; nothing here touched that file either way. Windows now runs the ten cases
and pins both bounds
against `ArchiveStamp`, and `CouldHaveBeenStamped_BoundsAreTheOnesTheMacUses` —
the one test here holding the literals, marked as such in its own comment —
goes away. Take the `moment` apart with a Gregorian calendar and compare the
pieces; do not re-spell it with `CourseArchiver.TimestampedName`, because a
round trip stays green while the writer and the reader are wrong together, which
is exactly the state the mac was found in.

**Found while in this code, filed rather than fixed:**
[issue #187](https://github.com/russellgordon/plantoir/issues/187) — the
same-second collision name `CourseArchiver.Archive` writes
(`ICS3U_2026-09-19_120000-2.zip`, or `…_assistant-section1-2.zip` for a backup)
is readable by neither parser, so such a zip is invisible to both sidebar lists
and to pruning; for a whole-course archive, `ArchiveAndRemoveCourse` then
deletes the course folder and the only copy never appears in Archives. The mac
has no collision retry at all, so it is Windows-only and no `zipNames` case
covers the form. **Fixed in bundle 8**: the retry now waits for the next
second instead of adding `-N` (below, "Same-second backups wait for the next second").

### The check that found the one still open — and how it was closed

`TheCardsArgumentsReachTheToolThatReadsThem` walked only `cardPhrasings.matches`
— the LITERAL phrasings. It now walks `cardPhrasings.parsed` as well, which is
the half where an argument is most easily misnamed, because it is built in code
from a number rather than written out beside the sentence. It found a live
defect on its first run: `add_next_class` declared no `duplicate` parameter, so
"duplicate Unit 3, Day 2 as my next class" — a sentence `AssistPromptShelf`
OFFERS — had the argument dropped by the binder and quietly made a **blank**
page. It was recorded in `KnownToBeDropped` naming issue #149, the way #116
was carried there until it was fixed.

**Fixed 2026-09-18, and the entry is gone** — the mend-check at the bottom of
that test fails on a pair that is listed and has started arriving, so deleting
it is not optional. Both halves of `add_next_class` now declare `duplicate`;
the pair moved to `agreedExtras` with the binder reason, since the mac needs
no such argument (its card and tool runner share a process). What the feature
does is in [`10-local-ai-assistant.md`](10-local-ai-assistant.md) → "Which
tools record an undo entry, and which deliberately do not".

**The two places this was stricter than the mac are no longer two.** Both —
the undo keyed on renames AND date moves, and the plan card counting the
union of the two lists — were proposed from here as
`contracts/class-planning.json` → `duplication` and implemented on the mac in
[#163](https://github.com/russellgordon/plantoir/issues/163) on 2026-09-19,
along with three faults that side found in the same path while doing it. Two
of those three are faults Windows shares, and the same section says which and
gives the construction that reaches them: the text comparison in
`AssistWorkspace.ApplyDuplicateClass` does not stop a lesson being written
over when the planner rewrote a link inside it, and the duplicate's refusal
there leaves no line on the trail.

**One thing to know before adding another card-only argument.**
`add_next_class` IS one of the thirteen tools the local model routes to, so an
argument on its schema is an argument the router can invent — here, a page
title for a request that named none. `AssistAgent.CardOnlyArguments` strips it
from `properties` and `required` in the narrowed schema, and
`NarrowToolsMirrorTests` pins that `research/ai-assist/narrow-tools.py` strips
it too, because a routing score measured through a surface the app does not
ship is worse than no score. The alternative — leaving it visible and writing
a sentence in the description telling the model not to use it — is the thing
CLAUDE.md warns about: one clarifying sentence in `publish_pages`' description
once took a probe suite from 110/110 to 90/110.

**The general lesson**: a silent drop is invisible to any test that does not go
looking, and "the tool ran and returned something sensible" is exactly what it
looks like.

### A generated contract can only describe what the generating side declared

`cardPhrasings` is a GENERATED key — `contracts/README.md` says so, and
`AssistContract.generatedCaseKeys` rebuilds it wholesale from the mac's
`AssistCardCommand`. A case added to it from here is deleted by the next
`Plantoir --write-contracts`, with nothing to say it has gone. The authored
halves are `scenarios`, `nearMisses` and `promptHistory`; a near miss proposed
from Windows survives, a parsed FAMILY does not.

That is not only a rule about where to type. The parsed family for make-room
described its count as "a number — words up to twelve are understood", and the
mac's matcher also takes the article: `"a": 1` sits in its spelled table and is
in none of its output. So **"make room for a class at Unit 3, Day 4" — the
sentence issue #70 uses as its example, and the tool's own `TEACHERS SAY`
clause — was the one form this app did not match**, and the contract test
stayed green because its example says "two classes". A form one side supports
and does not DECLARE is invisible to the other. If a family here accepts
something the contract's `shape` does not spell out, that is a case to propose,
not a detail to leave in the code.

## Dates are written in the Gregorian calendar, by one helper (#144)

Added 2026-09-27 for [issue #144](https://github.com/russellgordon/plantoir/issues/144),
from a cloud session on Linux (see "Working from a cloud session" in
`WINDOWS-DIRECTOR-PROMPT.md` for what such a session can and cannot build).
The mac needs nothing from this and owes nothing back; it is written up here
because the REASON is what a future reader of the C# needs, and the reason
cannot be read off the code.

**The fault.** `date.ToString("yyyy-MM-dd")` and `$"{date:yyyy-MM-dd}"` render
the year in the current culture's DEFAULT CALENDAR. The `-` is a literal and
is safe; the `yyyy` is not. On a Windows 11 PC whose regional format is Thai
(default calendar Buddhist), 2026-09-09 renders as `2569-09-09`, measured in
the issue; under `ar-SA` (Umm al-Qura) the same day is `1448-03-27`. Sixty-six
sites in this app's product code formatted a date that way and none passed a
culture. Most only DISPLAY a sentence — wrong once, and not corrupting. The
ones that mattered WROTE:

| Writer | What it wrote on a Thai PC | What read it back |
|---|---|---|
| `TimetableMemory.Write` | `"dates": ["2569-09-08", …]`, `"recorded": "2569-09-09"` | `TimetableMemory.Read`, which was ALREADY invariant — so every remembered class landed 543 years out, "when are my next classes?" answered from a list matching nothing, and `add_next_class` continued from a date no teacher gave it. Symmetric-looking, broken in one file, nothing reported |
| `PageFrontmatter.SetCreated` and `AssistWorkspace.ClassSkeleton` | `created: 2569-09-09T07:00:00.000-0400` into every re-dated and every new class page | The build, which sorts and dates the site by it |
| `ProblemReportStore.SaveRunTranscript` | the transcript's FILE NAME, `2569-09-19 120000 setup.ps1.txt`, and its "Started" line | `RunFilePaths` and `PruneRuns`, which sorted by name ordinally and deleted past twenty |
| `ActivityTrail.Note`, `ProblemReportBuilder.Stamp` / `About`, `AssistWorkspace.ReleaseSite` | every trail timestamp, the report's folder name and "Made on" line, the released-marker stamp | A person reading a problem report |

**A second column had the same fault.** The `:` in a custom format is the
culture's TIME SEPARATOR, so a bare `HH:mm:ss` renders `14.15.30` on a
Finnish or Danish machine. Every trail line and every transcript carried it.
Found by the plan review, not by the issue.

**The shape of the fix: one helper, `Plantoir.Core/Models/DateText.cs`**, and
every product site goes through it — `Iso(DateOnly)` for the ISO day,
`Stamp(DateTime)` for the trail's `yyyy-MM-dd HH:mm:ss`, `Invariant(…, format)`
for the four other shapes that exist (`yyyy-MM-dd_HHmmss`, `yyyy-MM-dd HHmmss`,
`yyyy-MM-dd 'at' HH.mm.ss`, `yyyy-MM-dd HH:mm:ss zzz`), and `TryReadDay` for
the reader half. The issue proposed the name `Dates`; three classes
(`TimetableMemory`, `ReDatePlan`, `ScheduleReading`) already have a `Dates`
property, which shadowed the type inside exactly the files that needed it
most, so it is `DateText`. The mac is immune by construction (`CalendarDay.text`
is three integers through `String(format:)`) and this is how the C# reaches the
same place. Two decisions inside the helper, both from the plan review:

- **No `Iso(DateTime)`.** It would drop the time silently, and the next site
  written as `DateText.Iso(DateTime.Now)` would be exactly the kind of call
  that looks right and is not. A caller with a moment says which shape it
  wants.
- **`TryReadDay` is EXACT, not lenient.** A lenient invariant parse reads
  `09/08/2026` as September the 8th — US order — while the cultural parse it
  replaced read it as the 9th of August on a Canadian or British machine.
  Switching the two `remember_timetable` readers to lenient-invariant would
  have silently swapped day and month for those teachers. The tools ask for
  `YYYY-MM-DD` by name and refuse anything else by name, so exact is what
  they meant. (Under `ar-SA` the old bare parse did not misread the app's own
  spelling; it FAILED outright, so every date was refused on such a machine.)

**Two things the fix itself would have broken, and what was done about them.**
A fixed writer beside an unchanged reader can be worse than the old state,
and this piece had two of those:

- **The runs folder becomes MIXED on every affected machine** — twenty old
  transcripts named `2569-…` beside the new `2026-…` ones — and ordinally the
  old names win, so `PruneRuns` would have kept the old twenty for ever and
  deleted each new transcript on arrival, with the problem report showing the
  twenty oldest runs and never the one being reported. The second comment on
  the issue had judged this reachable only after a locale change; the fix
  reaches it on day one. Both readers now order by the file's write time
  (`File.GetLastWriteTimeUtc`, name descending as the tie-break), which has
  no calendar. **This reverses a mac decision on purpose**: the mac's
  `runFileURLs` (`ProblemReport.swift`) sorts by NAME so that "nothing a copy
  or a restore from a backup could disturb" is involved. That reason does not
  hold here, because this folder never travels — `ProblemReportStore.LogsDirectory`
  is `%LOCALAPPDATA%\Plantoir\Logs`, not the working folder — while the
  mixed-calendar folder is real on the day the fix lands. Two consequences
  worth knowing: the order is by when a task FINISHED (the file is written
  once, at the end), so a long preview started earlier lists above a short
  task that ended after it; and a file deleted between the listing and the
  sort reads as 1601-01-01 and drops to the bottom, harmless. Rejected:
  skipping implausible names the way `ArchiveStamp` does — a name is only a
  label here, and the write time is what "the last twenty tasks" means anyway.
- **A timetable already remembered in the other calendar** is still on that
  teacher's disk, and the invariant reader takes `2569-09-08` as the year
  2569. `TimetableMemory.Read` now returns null — "not remembered" — when any
  date is before `EarliestBelievable` (2000-01-01) or more than
  `YearsAheadBelievable` (3) years past today, the same shape as
  `ArchiveStamp`: a date that cannot be true does not get to decide anything.
  The assistant asks for the timetable again, and the next `Write` replaces
  the file with one it can read. **`Write` refuses the same list**
  (`TimetableMemory.Unbelievable` is the one rule both consult), because the
  implementation review found what a reader-only guard does: `remember_timetable`
  saved the file, read it back for its reply, and dereferenced the null —
  a crash after the write, where before there had been a working tool. The
  two MCP tools and the section-schedule dialog now refuse first, naming the
  date. The window is contract data since this piece —
  `contracts/file-formats.json` → `sectionTimetable.believable` (the two
  bounds and eight cases, run here by `DateTextTests`) — because a working
  folder travels, so a file written by a pre-#144 Windows on a Thai PC can be
  restored on a mac, whose `SectionTimetable` reads it just as invariantly;
  the `mac` issue opened with this piece says so. The floor is 2000, not
  `ArchiveStamp`'s 2025, because a teacher may keep last year's timetable;
  it is still centuries clear of every wrong reading (2569, 1483, 1448). The
  ceiling is three years, not two days, because future class dates are the
  point of the file. **It leaves a trail line** — `remembered timetable set
  aside`, `appliesOn: ["windows"]` in `shared-rules.json` → `activityTrail.mustRecord`,
  carrying the date it refused — written by the reader, once per read of
  such a file until the teacher answers and the file is replaced. Windows
  only because only this app ever wrote such a file; the mac's guard, when
  it adopts one, meets a file that arrived rather than one it wrote, and
  can decide its own line then.

**What is deliberately left in the machine's culture**, so nobody "fixes"
it: `TaskScheduling.All` parses the `Next Run Time` column of `schtasks /Query
/FO CSV` that Windows wrote in its own culture (since bundle 3 `Schedule`
registers from XML with an invariant StartBoundary, so no date format is
guessed any more) — that program
accepts nothing else. `BackupItem.Subtitle` and `ArchivedItem.Subtitle` show
a month by name to the teacher and say `CurrentCulture` out loud. Sentences
of the shape `dddd d MMMM, h:mm tt` (no year) are read by a person in their
language and carry nothing a calendar can shift. Worth knowing, not fixed:
`/ST when.ToString("HH:mm")` in `TaskScheduling.Schedule` renders `14.15` on
a Finnish machine, and whether `schtasks` takes that is unmeasured.

**Five sites were left to `origin/issue/159-settle-the-day-once`**, the
unmerged Windows branch from 2026-09-19 that `WINDOWS-PARITY.md` Phase 5
step 1 says to take up as it stands: the model's dateline (`AssistAgent`
:610), the "deploy tomorrow at" card's moment (:704), that card's reader
(:815), and the two `DateTime.TryParse(when)` readers in `PlantoirTools`
(`plan_scheduled_deploy`, `schedule_deploy`), which #159 routes through one
reader, `ScheduledDeploy.ReadTheMoment`. Changing them here would have put
the same lines in conflict for no gain. **The order matters**: once this
piece is on `dev`, tool output the model reads is Gregorian while the
dateline and the `when` readers are still cultural, so on a Thai PC a model
echoing `2026-09-20 06:30` into `schedule_deploy` is refused as "already
passed" (the cultural reader takes it as 1483). #159 merges first, or the two
merge together; on a Gregorian machine neither order changes anything.
**Whichever lands second needs one follow-up commit**: if #159 is already on
`dev`, this branch's five `DeliberatelyCultural` entries excuse lines that
no longer exist, and #159's `ReadTheMoment` carries a cultural FALLBACK that
the source scan will flag — one entry to add, five to remove. (And #159's
middle step, an invariant LENIENT parse, is the very `09/08/2026` month/day
swap `TryReadDay` rejects; a comment on #159 says so.)

**What keeps it fixed** is `DateTextTests`, and the two tests that matter are
not the ones about the helper:

- `NoProductSourceRendersOrReadsAYearInTheMachinesCalendar` walks every `.cs`
  under `Plantoir.Core`, `Plantoir.Mcp` and `Plantoir` (never `bin/` or
  `obj/`, never a `//` line) and fails on any line that renders a year
  (`ToString("…yyyy`, `{x:yyyy…}`, `.ToString(format)`) or parses a date
  (`DateTime`/`DateOnly`/`DateTimeOffset` `.Parse`/`.TryParse`/`…Exact(`)
  without `InvariantCulture` or an explicit `CurrentCulture` on the same line,
  or `string.Create(CultureInfo.InvariantCulture, …)` on the line before
  (#159's shape). `DeliberatelyCultural` excuses one line per entry, by file
  name and a substring of the line, with the reason; the five #159 lines are
  in it until that branch lands, when its `ReadTheMoment` will want an entry
  of its own for its cultural FALLBACK. Its blind spot is a format passed
  through a variable, which is why `TaskScheduling`'s `when.ToString(format)`
  is matched by name. Three more, none with a site today: a second bare
  `yyyy` on a line that also says `InvariantCulture` gets through; the line
  after a `string.Create(CultureInfo.InvariantCulture, …)` is skipped
  whatever it holds; and `{x:MMMM d, yyyy}` is missed because the pattern
  wants `yyyy` right after the colon. A bare `{date}`, `ToString("d")` or
  `ToShortDateString()` is not scanned at all, and the greps found none.
- `EveryExcuseStillExcusesALineThatExists` fails the moment an entry matches
  nothing, so a dead excuse cannot one day excuse a new site by accident. The
  #159 entries are exempt from it, for the reason above.
- Every culture test FIRST asserts that the bare rendering really does shift
  under the swapped culture on this machine (`2569` under `th-TH`, `14.15.30`
  under `fi-FI`). A machine running with invariant globalization would
  otherwise pass every assertion while proving nothing. Measured on Linux
  with ICU 74 and on Windows 11 alike: `new CultureInfo("th-TH")` has the
  Buddhist calendar as its default on both.

## What a window lets go of when its working folder changes

Issue [#162](https://github.com/russellgordon/plantoir/issues/162), the
Windows half of the mac's [#93](https://github.com/russellgordon/plantoir/issues/93).
The reported defect: with a course selected, choosing another working folder
left the selection naming a course that folder had never had, so the detail
pane greeted the teacher with "Course Not Found" about a folder they had only
just arrived in. The rule itself is in
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`workingFolderSelection`, and `documentation/09-mac-app.md` explains it; what
follows is only what is Windows'.

### The state had to move into Core before anything could be tested

`SidebarSelection` and the folder lived in `Plantoir/ViewModels/WorkspaceViewModel.cs`.
`Plantoir.Tests` targets plain `net9.0` and references Core and Mcp only, so
**no test in this repository could reach the rule at all** — which is the real
reason the defect arrived here with every Windows gate green rather than red.
Both now live in `Plantoir.Core/Models/WorkingFolderSelection.cs`:
`SidebarSelection` unchanged (no XAML names it, and `Serialized`/`Parse`
already delegated to Core's `WindowMemoryCodec`, so the strings
`App.RememberOpenWindows` persists are byte-for-byte what they were), plus a
new `WindowFolderState` holding the folder, the selection and the sidebar
memory that survives a change. The precedent is `FolderRemoval`, moved the same
way for [#142](https://github.com/russellgordon/plantoir/issues/142).

`WorkspaceViewModel` keeps every public member it had and delegates; both
`ChooseWorkspace` and `AdoptRestoredPath` go through one private
`PointAtFolder` → `WindowFolderState.PointAt`. What is route-specific stays
with its caller — the trail line, `Settings.Save`, `ReleaseFolderIfUnused`,
`NoteBecameKey` — because a restored window must not record "working folder
opened" twice.

Two things are easy to drop and neither fails loudly:

- **`Notify(nameof(Selection))` after the reload.** `MainWindow` subscribes to
  it twice over: once to re-render the pane, and once to call
  `App.RememberOpenWindows()`. Without the second, the remembered frame still
  names the old folder's course and the whole defect returns on the next
  launch — invisible until then. It fires only when a folder was actually left
  behind, because the first adoption runs mid-construction, before the window
  has finished building itself.
- **The kept half.** `ExpandedCourseCodes`, `IsShowingArchived` and
  `IsShowingBackups` are seeded by `MainWindow`'s constructor BEFORE the folder
  is adopted, so clearing them in the funnel would silently break window
  restoration rather than anything to do with this rule.

### `alsoCleared` reduces to the selection here — a finding, not an omission

The mac also lets go of five pending confirmations and four alerts, which it
holds as FIELDS. On Windows every one of those is an awaited modal
`ContentDialog` (`SidebarPane.xaml.cs`'s archive, restore, delete and rename
confirmations): the state is a continuation on the stack, with no field to
clear, and the folder it acts on is read INSIDE that continuation rather than
pinned when the dialog went up. Inventing fields to clear would mean inventing
the state to go with them.

**What the modality does not close, and this is the part worth knowing.** The
MENU route to the folder picker is genuinely shut while a dialog is up:
`MainWindow.OpenWorkingFolder_Click` is a `MenuFlyoutItem`, and the dialog's
overlay covers the menu bar. **Ctrl+O is not obviously shut.** It is a
`KeyboardAccelerator` declared on `MainWindow.xaml`'s `Root` grid; WinUI
searches for accelerators window-wide unless a `ScopeOwner` narrows them, none
is set, and `OpenWorkingFolderAccelerator` has no guard of its own. Whether the
key actually reaches it under a modal dialog cannot be settled by reading —
that needs a run, and it is
[issue #191](https://github.com/russellgordon/plantoir/issues/191), along with
the other three that are unguarded the same way: Ctrl+N
(`NewWindowAccelerator`), Ctrl+Shift+R (`ReloadCoursesAccelerator`) and **F2**
(`RenameCourseAccelerator`, `MainWindow.xaml:14`). F2 is the sharpest of the
four — it is the only one that would raise a SECOND `ContentDialog` on top of
the modal one, which WinUI refuses and swallows, so the key would appear to do
nothing at all.

**So the confirmations were made safe whether it fires or not**, which is the
honest delivery of `alsoCleared` here. Every confirmation in `SidebarPane`
captures the working folder BEFORE its dialog goes up and, after the await,
does nothing at all if `WorkingFolder.IsTheSame(captured, live)` is false —
`TheFolderMovedUnderThisConfirmation`, one helper so the **twelve** check sites
read identically. Silently void, like the mac's cleared confirmation: no
sentence, because a teacher who has just moved to another folder is not waiting
to hear about the one they left.

Eleven of the twelve follow a dialog. **The twelfth follows a wait that is not
a dialog at all**, and it is the widest window in the file: inside the rename,
`FolderActions.QuitObsidianAndWait` polls for up to five seconds (50 × 100 ms)
with nothing on screen, so the File menu and Ctrl+O are both fully live — and
everything after it reads the LIVE workspace, down to setting the selection to
the renamed code. A check before a wait says nothing about what is true after
it.

**What the void path leaves behind, decided rather than overlooked:** Obsidian
has been quit by then and is not reopened, and nothing tells the teacher so.
Nothing on disk is half-done — the rename does not run at all — so the cost is
an editor to open again. Reopening it was rejected because the vault to reopen
is in the folder they have just LEFT: Plantoir would pull them back to a folder
they deliberately moved away from, and the folder they are now in may have no
vault of that name. Saying it was rejected for the same reason the whole rule
exists — a sentence about the old folder is what `alsoCleared` forbids.

What that prevents is specific rather than theoretical. Each confirmation names
its course, archive or backup by a path taken before the dialog, and finishes
by asking the window where it is NOW. Answer a backup restore after a folder
switch and `Workspace.CoursesDirectory()` is the NEW folder's while
`item.FilePath` is still the OLD folder's zip: the new folder's course of that
code is archived and overwritten from a backup belonging to a folder nobody is
looking at, and it reports success and shows the result. The two deletes remove
the old folder's file while the window shows the new one.

`Plantoir.Tests/ConfirmationFolderGuardTests` gates this with **two** scans of
`SidebarPane.xaml.cs`. The first: every awaited dialog must be followed by the
check before the next await or the end of the method, or carry a
`// folder-check: not needed — …` comment saying why (three do: the helper
itself, the error reporter, and the "is backed up" notice). The second covers
waits that are not dialogs — in a method that captured a folder, a
`Workspace.Reload()` or a `Workspace.Selection =` after any `await` must have
the check between them. A new confirmation written with neither fails.

**What the scans cannot see** is written in their own comments and repeated
here, because a guard believed to cover more than it does is worse than none.

- **They read ONE file.** `CourseSettingsView`'s folder-rename sheet finishes
  inside a `Closing` deferral against a course captured at construction, so it
  acts on the right folder's files — a milder case, left alone;
  `TaskProgressView`'s runner questions belong to a task rather than a folder;
  `MainWindow`'s own dialogs act on no course.
- **Nothing scans `MainWindow`'s hand-backs at all.** `StopPreviewFor`,
  `StopPreviewForAsync` and `MainWindowForBuilds` take the SECTION's folder
  from the assistant window that asked, rather than reading the main window's —
  see "The assistant's hand-backs name a section, not a window" below. That is
  held by reading, not by a test.
- **The dialog scan is LINEAR, not brace-aware.** A confirmation in an `if`
  branch is satisfied by a check sitting in the `else` branch below it, and the
  forward search stops at the first closing brace at method indentation, so an
  unusually shaped method ends it early. An opt-out is read on the site line or
  the two above it, so write one ON the site line — a comment two lines up is
  one reflow away from being out of reach.
- **The non-dialog scan watches two writes only**, sees only methods spelling
  `string? askedIn =`, matches the word `await` lexically (so one in a comment
  arms it), and reads a write inside a lambda declared after an await as a
  write in the continuation. Those failures all point toward crying wolf rather
  than toward silence, which is the right way round.

A C# parser inside a test was rejected for both: what actually happens is a new
confirmation written with no check at all, and both scans catch that.

### The assistant's hand-backs name a section, not a window

`AssistWindow` hands building, deploying and stopping back to the main window's
own controls rather than running them again behind the chat — the design
Windows led on. Each hand-back knew a course code and a section number, and
found the window to use as `_main`, the window the conversation was opened
beside.

**That window can move.** Nothing closes an assistant window when the main
window is pointed at a different working folder, so `_main` outlives the folder
it was opened for, and every hand-back then acts in a window showing something
else: the stop swept the container and released the lease of the folder the
teacher had just arrived IN — another window's running preview of that course
and section — while the section's own preview leaked; and it selected a course
code into a sidebar that had never had one, which is this issue's own defect
arriving by a side door. Worse than the dialog case, because the assistant is
where a teacher is *least* watching the main window.

So every hand-back now names `_folder`, the section's own:

- `StopPreviewFor` / `StopPreviewForAsync` take it as an argument. **Both**
  paths run `PreviewStopper.StopSectionProcesses…` and
  `PreviewLeases.Release(sectionFolder, …)` OUTSIDE the window check, so the
  section's preview is reclaimed either way; the parts that touch the WINDOW —
  selecting the section, and stopping the detail pane's preview — run only
  while that window is still showing that folder. The synchronous one is the
  fallback `AssistAgent` uses where no async wiring is set, before a deploy
  hand-back and before a page edit, and both callers rely on the same thing:
  that nothing is still serving or building out of the section's output folder
  by the time they rewrite the pages or start a build into it. The two differ
  only in whether they WAIT for the processes to go.

  **The unconditional sweep is load-bearing in the showing branch too**, which
  is easy to miss. Selecting the section REPLACES `DetailHost.Content`
  synchronously, so the view that `StopPreviewIfRunning()` is then asked to
  stop is a freshly built one with no preview in it, while the instance that
  owns the running preview is only unloaded a dispatcher tick later. Relying on
  that unload would make the stop's completion a matter of timing. Both calls
  are safe to run twice.
- `MainWindowForBuilds` now prefers `_main` only while it still shows
  `_folder`, falling back to `App.WindowFor(_folder)` and then to opening one.
  A build or a deploy therefore always happens in a window showing the
  section's folder, so no sentence had to be invented for a hand-back that
  could not find its window — it can.
- `SectionIsBusy` asks a window showing that folder, because "busy" is read off
  a detail pane and another folder's pane answers about another folder's
  section.
- `App.WindowFor` compares with `WorkingFolder.IsTheSame` like everything else,
  rather than its own `Path.GetFullPath` spelling.

The capture cannot be taken at the top of the dispatcher lambda either: the
lambda runs when the dispatcher reaches it, not when the assistant asked.

### Which folder a teardown names

The second defect, and the one that had to land FIRST. `SectionDetailView`
used to read `_window.Workspace.WorkspacePath` inside `StopPreview`,
`StopPreviewAsync`, `CancelPreview`, `CancelDeploy` and `ReleaseLease`, and
`Unloaded` calls `StopPreview()`.

Clearing the selection replaces `DetailHost.Content`, and WinUI DISPATCHES
`Unloaded` — it runs a layout pass later, with the window already pointing at
the new folder. The stop would then run `preview.ps1 --stop` against folder B
and remove B's lease row: inert if nothing is previewing there, and **harmful
if something is**, because it stops another window's preview of that course and
section while the folder being left carries on serving with nothing left to
stop it. Today `Unloaded` never fires on a folder change, so the bug is inert;
**clearing the selection without the captures is what would make it live**, and
that is why the two are separate commits in that order.

The fix is structural, and two notes rather than one:

- `_folderThisSectionWorksIn` — written where a folder is DECIDED: the two
  preview starts, and the deploy only AFTER its own preview stop, so that stop
  still names the preview's folder. Read by every stop.
- `_folderThisSectionRegisteredIn` — written once, `readonly`, at
  construction, and read only by `ReleaseLease`'s folder-keyed sweep. Kept
  apart from the work folder because a deploy starting in the one render pass
  between the folder change and the teardown moves the work folder, and a
  registration riding along with it would strand the old folder's lease row.
  That was the mac's own finding on review of #93.

`PreviewLeases.Lease` already carries its `FolderPath`, so `Release(lease)` was
right all along; only the folder-keyed sweep beside it had to change.

**It is gated by a source scan, and the shape of the scan matters.** No
`SectionDetailView` mounts in a unit test, and when this was written CLAUDE.md
forbade a `[UiFact]` that drives Preview (lifted in bundle 11, 2026-10-01; a
UI test still does not switch a window's working folder under a running preview,
which is what this guards), so `SectionDetailTeardownSourceTests` reads the file and
asserts **zero** reads of the window's live folder between two marker comments
— not a list of the five known sites. `ReleaseLease` alone has six callers
(`AbandonWait` among them, which no earlier inventory named), and a test naming
today's sites stays green the moment somebody adds a sixth, which is the whole
failure it exists to prevent. It also pins the four write sites and the single
registration write, since deleting a capture would otherwise leave every stop a
silent no-op wearing the shape of the fix working. (Four, not three: the
marketing-shot harness `StagePreviewForCapture` sets `_previewUrl`, which makes
`hadPreview` true, and a staged view must not answer the teardown's question
differently from a real one.)

**That scan is LEXICAL, and one exception is named rather than tidied away.**
Every teardown path ends in `RefreshChrome()`, which is defined outside the
region and does read the live folder — correctly, because what a teacher may
click next is a question about the folder now on screen, and it stops and
releases nothing. A second test asserts that `RefreshChrome` is the **only**
method called from the region whose own body reads the live folder, so another
cannot arrive under cover of the first. Neither test can see past this file.

### One notion of "the same folder"

Found while wiring the above, pre-existing and teacher-visible on its own.
`MainWindow.IsTheOpenFolder` resolved and compared case-insensitively;
`ChooseWorkspace` asked `previous != path` and `ReleaseFolderIfUnused` asked
`m.WorkspacePath == path`, both **ordinal**. The OS folder picker hands back
the true on-disk casing, and a stored path carries whatever casing it was saved
with — so re-choosing the folder already open was "the same" to one and "a
change" to the other. The change path then found no window holding the old
spelling and stopped that folder's container: the container of the folder still
on screen, with the teacher's preview inside it. The contract says re-choosing
the open folder "costs the teacher nothing".

`Plantoir.Core/Models/WorkingFolder.cs` is the one rule now, and every
folder-equality test in those classes asks it, including
`Workspace.FolderForNewWindow` — which also hands back the OPEN window's
spelling rather than the remembered one, since inheriting a second spelling is
how one folder comes to look like two.

**What it deliberately does not resolve.** `Path.GetFullPath`, trailing
separators trimmed, `OrdinalIgnoreCase` — and nothing more. No junctions, no
symlinks, no deciding that `Z:\Courses` and `\\server\share\Courses` are one
folder. Those answers need a handle open: `FolderContainers.PhysicalPath` does
exactly that with `GetFinalPathNameByHandle`, which is right for NAMING a
container (it must agree byte for byte with what `preview.ps1` derives) and
wrong here. This question is asked on the UI thread, on every folder change and
every window close, often about a folder that has just been unplugged, renamed
or deleted, where a handle open blocks or fails. **Rejected for that reason:**
an extra container stop costs a second and starts again by itself; losing the
window costs the teacher their work.

**And one case where it is wrong the other way, accepted knowingly.** Windows
can mark a directory case-SENSITIVE per folder (`fsutil file
setCaseSensitiveInfo`, which is what WSL does to the folders it creates), and
inside one of those `Work` and `work` are two real sibling folders that this
compares as equal — so a container could be stopped for a sibling, or a folder
change read as no change. Recoverable (the next preview starts the container
again), and closing it would mean asking the filesystem per comparison, which
is the handle open rejected just above. A teacher's working folder living
inside a WSL-created case-sensitive directory is a shape nobody has met:
Plantoir's folders are chosen from the ordinary Windows picker.

**No new trail event is owed.** `working folder opened` already records the
act, its line is still true, and a selection being let go is not something a
teacher DID — it is the consequence of what they did, recorded one line up.

## Course creation and the smaller course pieces (parity bundle 6a)

Bundle 6a (2026-09-30) brought eleven mac pieces across: the wizard's skeleton
rules (#169, #250, #252, #349), the marks floor (#348), the problem report's
unreadable trail (#316), reopening the last working folder (#320), Get Ready
for the Start of the Year (#355, #389), one coverage map per curriculum folder
(#345) and the How I Teach row (#360). The rules are contract data and the
rows in `GUI-IMPROVEMENTS.md` (666–672) say what a teacher sees; this section
is the Windows MECHANICS — what had to change shape here, what differs from the
mac on purpose, and what was rejected.

### The view could not be pinned, so the decisions moved into Core

`NewCourseDialog` is a `ContentDialog` in the WinUI project, which
`Plantoir.Tests` cannot reference (different target framework, and a
`ContentDialog` cannot be built off a XAML thread). Three pure seams now carry
what the dialog decides, and the dialog is thin call sites around them:

- `WizardStructure` — `Adopting(family)` and `RestoringDefaults(current,
  adopted, useLcs)`, the restore that used to be private to
  `RestoreGenericStructure`. `wizard.skeletonToggle` runs against it.
- `NewCourseAnswers.Decide` — the five structure lists, the sidebar, the three
  starting-point keys and the marks pool, i.e. everything the Starting Content
  answers decide in `course_config.json`.
- `CourseSettingsProtection` / `CourseSettingsExclusions` — the context Course
  Settings protects its rows with, and the click recorders and Revert.

**Goldens before the fix, the mac's technique.** Before a line of #250 was
written, a throwaway test ran the OLD rule over `NewCourseAnswers` for ADA1O,
MCV4U, MCMPR11 and ICS4U with the pages taken, and AMU3M with the skeleton on
and off, and wrote `Plantoir.Tests/Goldens/*.json`. `NewCourseAnswersTests`
asserts those bytes afterwards: a teacher TAKING the ready-made pages must get
exactly what they got before. The throwaway test was deleted in the same
commit; the goldens are what it leaves.

**One behaviour changed that no case asked for, and why it was taken.** Windows
wrote `include_curriculum_coverage` from the raw switch, so a course with no
curriculum pages to draw from was made with the map ON (the comment beside it
called this "deliberately left alone" and raised it as a product question).
#252's rule answers that question: the mac writes the map on only where the
pages are offered and kept (`curriculumCoverageEnabled`), and the two apps must
write the same file for the same clicks. Windows now does too. Rejected:
keeping the raw switch for courses with no payload — it would be the one key
the two apps disagree on for ~1,900 codes.

### The marks floor walks the disk twice, on purpose

`gradedFolders.floor` depends on which pooled folders exist on disk, so Course
Settings walks the course ONCE per drawing (`GradedFolderChoices.WalkedFolders`,
every occurrence kept with its course-level folder and the folder directly
inside a section) and shares it between the checklist and the three lists — and
walks AGAIN at the click (`StringListEditor` / `MembershipToggleList` gained a
`protectionWhenActedOn`; the wizard passes none and its drawing rule is asked
again). Whether to ASK is decided at the click too: the old editor decided
"confirm or not" from the drawing, and a folder deleted in Explorer while
Settings was open would then ask about the wrong thing. Rejected: a walk per
row (the mac measured 53 ms per walk on a 400-folder course, ten-plus rows per
drawing).

One difference the runner absorbs rather than hides: with no `class_folder`
recorded, Windows protects the first per-section folder as the class folder
(`ClassFolderRule.Name`'s guess), where the mac protects only the literal "All
Classes" or a recorded name. `floor`'s per-section fixtures say none of their
folders is the class folder, so `MarksFloorContractTests` sets the resolved
class folder to null for those cases. Whether the two apps should agree on
which folder an unrecorded course protects is a separate question and was not
taken here.

### Reopening the last working folder: a path, not a bookmark

Windows remembers the PATH. A folder moved on the same disk therefore reads as
`gone`, which is honest; the mac's bookmark follows it. `unreadable` is said
ONLY where listing the folder threw `UnauthorizedAccessException` —
`Directory.Exists` cannot tell a denied folder from a missing one in every
case, and the contract's one hard rule is that a denied folder is never called
gone. `driveNotConnected` is the path's drive root not existing (an unplugged
USB disk, an unmapped network letter). The Trash, privacy and outside-home
reasons are `appliesOn: ["mac"]`. `AppSettings.Load` no longer nulls a
`WorkspacePath` it cannot reach — that silent prune was the bug — and
`NoteBecameKey` writes it, so "last" is the folder last in front. A Ctrl+N
window goes through `AdoptInheritedPath`, which writes no trail line.

### Get Ready for the Start of the Year: what the app's Go does NOT do yet

The rule, the MCP pair and the sheet MATCH (`StartOfYearPlan`,
`AssistWorkspace.PrepareForStartOfYear`, `StartOfYearDialog`). One part of the
mac's app-side behaviour is not built here, and is said so rather than
implied:

- **Go does not stop and restart the preview.** The pages are written; a
  preview that is showing keeps showing the old state until the next build.

The undo ends at the next deploy started from THIS app (`SectionDetailView`
ends it as the publish begins), at a scheduled deploy — the one set at the time
of the act reaching its moment, or the section's outcome record showing a run
since (`StartOfYearSessionUndo.EndedByAScheduledDeploy`, read when the undo
sheet opens) — at the next change to the section's pages from anywhere (the
section's plan code no longer matches the one taken after the write), and at
quit (it lives in memory only).

The plan code is SHA-256 over every page of the section, path and bytes, eight
hex digits. Rejected: a code over the plan's own entries only — a page the plan
does not touch can change what step 3 decides (a link added to a leftover page
keeps it), and the code exists to say "the section is the one you were shown".

The MCP write takes a FRESH backup for the act through the same door as every
other assistant zip (`AssistantBackup`), then works the plan out AGAIN after
the copy and refuses with `changedWhileSavingACopy` when it no longer matches
or can no longer be made. The app's Go uses the teacher's own backup
(`BackupMaker.Teacher`), since the teacher pressed the button.

### One coverage map per folder: decided from the disk, in Core

`CurriculumFolderRule` is plural (`Resolve(declared, folders, withPages,
withLetterFirstPages)`) and `FoldersWithPages` reads which SHARED folders hold
an expectation page, recursively — the same thing the build reads. Course
Settings reads it once per drawing and again at the click, like the walk. The
wizard has no disk, so it counts the payload's declared folder while the
curriculum pages are being installed (the old `null` at the protection's call
site was the gap the issue named). A rename reads the pages BEFORE the move —
afterwards the old name is not on disk — and passes them to
`SpecialFolderRenamer.Renaming`, which writes `curriculum_folders` and the
legacy `curriculum_folder` naming the primary.

`PLANTOIR_MAPS:` is read from the console (`ScriptRunner`) and from a scheduled
publish's record (`ScheduledHealthFindings`); the scheduled wrapper's
`Select-String` marker scan gained `PLANTOIR_MAPS:`, without which the second
reader would never see the line. A wrapper written before this keeps its old
scan until its schedule is set again.

The build prints the line from the contract's own prefix
(`build_site.announce_coverage_maps` reads `coverageMapsBuilt.marker.prefix`
through `contracts.section`), which is why a search of `scripts/` for the
literal string finds only the tests — a review of this bundle read that as
"the build never prints it", and it was checked and found false.

### The How I Teach row, and the CHECK items of #360

The row writes with `FileMode.CreateNew` and opens THE PAGE
(`FolderActions.OpenInObsidian` gained a `page` argument), never the vault.
`HowITeachSettingsRowTests.ACreatedPageNeverWritesOverOneMadeAMomentEarlier`
injects a page between the look and the write through a test-only overload.

The CHECK items, answered by reading this app rather than measuring the mac's
numbers onto it: Windows' assistant window drives its tools through
`plantoir-mcp` (`McpClient`), so the zip runs in that process and never on the
app's UI thread — the mac's 9.7 s main-thread zip has no analogue, and nothing
was measured holding the window. Every assistant zip now leaves an `assistant
backed up a course` line with its seconds, which is how that claim will be
checked against a real course. (This said counting the course busy while
the zip runs in `plantoir-mcp` was not built and that `courseIsBeingCopied`
stayed in the ledger against #360. It was built in parity bundle 6a —
`AssistWording.CourseIsBeingCopied`, `WorkLease`, `CourseBeingCopiedTests` —
and `NamedGapLedger` has been empty since bundle 9.)

---

[◀ Previous: Release Strategy](11-release-strategy.md) · [Back to index](README.md)

## The links checklist on Windows (#392, #399, #405)

The mac's sheet (documentation/09-mac-app.md → "The links checklist (#379)") is,
on this side, split in two, and only the first half is built.

**Built and contract-tested** — everything that decides what a press WRITES:
`Plantoir.Core/Assist/LinksChecklist.cs` (offer reader, the pure gate, the
answered file, the record release), `LinksChecklistWording.cs`, and
`AssistWorkspace.LinksChecklist.cs` (`OpenLinksChecklist`, `PublishLinksChecklist`,
`PublishAndRemember`, `NotNow`, the trail lines). Runners:
`LinksChecklistGateContractTests` (followingARow 10, comingWithAClass 12),
`LinksChecklistPublishContractTests` (publishCases 15, through the sheet model),
`LinksChecklistWordingContractTests`, `PublishedPagesRecordTests`.

Three decisions worth knowing before changing any of it:

- **A page a ticked class brings is dated by THAT class, directly.** The
  assistant's `InheritedDates` picks the earliest class anywhere that can reach
  a page, and in the contract's fixture a visible "Unit 1, Day 1" reaches the
  worksheet through "How Marks Work", so iv-b, iv-d, iv-j, iv-k and iv-m were
  dated 2026-09-08 instead of the ticked class's 2026-10-20. The publisher
  walks each ticked class's own reach (stopping at classes) and dates the
  pages the class plan changes; the first class in the sheet's order wins.
- **"Locked" is "has a parent row, NONE of which goes".** A row under a row
  that goes, with its own tick off, is simply unticked (followingARow case 7);
  reading locked as "has a parent and does not go" fails it.
- **Places are compared in composed form (Form C)** on both sides, the trap
  #405 names: C#'s string equality is ordinal, Swift's is canonical.

**Not built** — the WinUI sheet (grouped checkboxes over `LinksChecklistSheet`,
`ShownOrder` for the indent, `SecondLine` for each row's second line), showing
it after a watched build when the `PLANTOIR_LINKS_CHECKLIST:` marker's buildId
equals the file's (holding the #333 finding until then), on section open for
an unwatched publish when the offer is fresh and holds something new
(`LinksChecklist.HoldsSomethingNew`), the menu item, and
`linksIntoHiddenPagesWillBeOffered` in the assistant. `NoteOffered` has no
caller until the sheet exists. (Superseded: bundle 5b built the sheet; parity
bundle 7 added the rest — the assistant says `linksIntoHiddenPagesWillBeOffered`
only when the SAME build printed the marker, the offer is that build's and holds
something new, `plantoir-mcp`'s `LauncherRunner` now keeping the marker on
`LaunchOutcome.LinksChecklist`; the assistant's publish keeps the date of a page
in the published-pages record, `LinksChecklist.PublishedPlaces`; and
`linksChecklist.naming`'s two laid-out cases run in
`LinksChecklistNamingContractTests`.)

**The folder deploy's record.** `deploy.ps1`'s `Record-PublishedPages` (between
BEGIN/END markers so the test runs it as written) reads `.build-id` and
`.visible-pages.json` from `PLANTOIR_BUILD_ROOT\<CODE>\section<N>\` — no
`.merged_output` level on this platform — and records only when the list's
buildId is the site's. **Every rollover** (same website or new, not only
`ReleaseSite`) moves the fragments to `.published-pages.previous-<stamp>/`,
keeps the folder, removes the answered file, and records it all in the undo
history.

## Courses kept for reference on Windows (#241, #244, #245, #298)

The rule is the contract's (`shared-rules.json → referenceCourses`) and the
mac's write-up is `09-mac-app.md` → "A reference course, and what FROZEN
means on disk". This section is what Windows does DIFFERENTLY, and why.
Code: `Plantoir.Core/Models/Reference*.cs`, `ObsidianAddOns.cs`,
`SchoolYear.cs`, `Plantoir.Mcp/ReferenceWriteGate.cs`,
`Plantoir/Views/SidebarPane.Reference.cs`, `ReferenceSummaryView.cs`.
Tests: `ReferenceCourseTests`, `ReferenceLockTests`, `ReferenceRefusalTests`,
`ReferenceMarkerAgreementTests`, `ReferenceCopierTests`, `ReferenceImportTests`,
`ReferenceInterfaceTests`, `ReferenceBuildKeepsHiddenPagesHiddenTests`,
`scripts/test_build_keeps_a_readonly_hidden_page_hidden.py`, and the UI tests
`ReferenceCourseUiTests`.

### The lock is deny entries, not the read-only attribute (design A5)

NTFS has no `uchg`. Measured on this PC (i5-8365U, 16 GB, Samsung 980 NVMe,
Windows 11 26200) before anything was written:

| | Read-only attribute | Deny on the file only | **Deny on the file + deny delete-child on its folder (chosen)** |
|---|---|---|---|
| write in place | refused | refused | refused |
| rename-over (`File.Replace`, `os.replace`) | refused | refused | refused |
| rename | allowed | allowed | refused |
| delete, `Remove-Item -Force`, Explorer | allowed (they clear the bit first) | allowed (the parent's inherited FILE_DELETE_CHILD wins) | refused |
| add a new file beside it | allowed | allowed | allowed |
| replace the UNLOCKED `course_config.json` from a `.tmp` | n/a | n/a | allowed |
| make and remove the `.merged_output` junction | n/a | n/a | allowed |
| does a COPY carry it? | **yes** (`File.Copy`, `shutil.copy2`) | no | no |

So: on every content file an explicit DENY of `WriteData, AppendData,
WriteExtendedAttributes, WriteAttributes, Delete` for this account, and on
every folder holding a locked file a DENY of `DeleteSubdirectoriesAndFiles`
for that folder only — never inherited by its contents, which would stop the
preview's link and Obsidian's `workspace.json` (the mac's "never lock the
directories" finding again).

**Rejected: the read-only attribute.** It TRAVELS. The native build copies
each page with `shutil.copy2`, the copy is read-only, the frontmatter rewrite
fails, the copy keeps `draft: true`, and the page the teacher HID is
published. Reproduced end to end with a real native build
(`ReferenceBuildKeepsHiddenPagesHiddenTests`; must-fail: without the fix
below, the hidden page is in `public/`). **Rejected: a lock file** that
Plantoir's own writers check — Obsidian, Explorer and editors never read it,
and the marker already is the in-app gate.

**Belt and braces in the shared build.** `build_site._writable` makes the
BUILD's own copy writable before every write it makes to a page
(`process_frontmatter`, the dating write, the unreadable page's hide, the
wikilink rewrite). A no-op on the mac. A read-only page can still reach any
course from OneDrive, a zip, or another tool.

**Never-locked names**: the contract's six, plus `desktop.ini` and
`Thumbs.db` (Windows' twins of `.DS_Store`), plus anything ending `.tmp`.

**Unlock matches the SHAPE, whoever it names** (bundle-6 ruling 3). Windows
MERGES two deny entries for one account into one (measured: a teacher's own
`ReadData` deny plus ours came back as a single entry carrying both), so
Unlock takes OUR bits out of any explicit deny entry that carries all of
them and leaves the rest of that entry — a teacher's own rule survives. A
course carried from another account, whose entries name a SID that is not
this user, still unlocks.

**Cost, .NET 9 ACL API**, 1,200 files: lock 808–820 ms (every file read back,
plus the census), a pass with nothing to do 113–129 ms, unlock 409–473 ms.
The planner's PowerShell 5.1 probe: 607 / 209 / 397 ms. The mac: 59.5 ms and
23 ms. So every pass runs off the UI thread, on folder read and on an act,
never on a timer.

**The census** is a separate plain listing (recursive, links skipped)
classified by the never-locked rule alone, so a walk that skipped a folder
cannot agree with itself (the mac's 842-of-934 fault).

**Honest limits, never in the GUI.** New files can be added. The owner can
remove the entries (Properties → Security). An entry does not sync, so the
lock is per-machine. Another account is not denied. **`robocopy /SEC`,
`/COPYALL` and `/COPY:…S` CARRY the lock — and then stall on it**, retrying
a file whose attributes it cannot set (by default a million times at 30 s;
measured by the plan review). `Copy-Item`, Explorer and a zip do not carry
it. Nothing in this repository may use those flags:
`ReferenceLockTests.NoRobocopyInThisRepositoryCopiesSecurity` (must-fail:
`/SEC` on deploy.ps1's mirror turns it red). Since #419 (2026-10-01) it reads
the files git TRACKS (`git ls-files`) rather than walking the folder: the walk
reached the gitignored `courses/`, where an old build output held a WSL
symlink (reparse tag `0xa000001d`) Windows cannot open, and the test threw
`IOException` about a teacher's leftover folder rather than this repository's
code (reproduced through a junction to that tree: old code red, new green; a
STAGED file carrying `/SEC` still turns it red). A teacher's own script that
does is answered by Unlock, which matches the shape. **And the refusal to
deploy never depends on any of it**: every door asks the marker.

**Not measured, owed:** OneDrive with locked files under it (whether its
client keeps the entries, and whether a deny on `WriteAttributes`/`Delete`
stops it dehydrating or syncing — the fallback is to drop `WriteAttributes`);
an elevated token (the deny is by user SID, so it should still apply); and
what Obsidian for Windows shows on a page it cannot save — which is why
`referenceCourses.wording.obsidianOpensThemForReading`, a macOS measurement,
is NOT said on Windows yet.

### A byte-order mark used to hide a course

`CourseConfiguration.FromBytes` kept a BOM as U+FEFF and Newtonsoft refused
it, so a settings file saved by Notepad made its course vanish from the
sidebar — and a reference course with one was not a course at all
(`markerAgreement`, "a byte-order mark at the head of the file"). The BOM is
stripped before parsing now.

### The fifteen doors on Windows

| # | Door | Windows chokepoint | Test |
|---|---|---|---|
| 1 | section window's Deploy | `SectionDetailView.DeployAsync`, first check (and the button is not drawn) | `TheDeployButtonsFlowRefusesFirst`, UI `AReferenceCourseHasNoDeployButtonAndNoRepairButton` |
| — | the runner behind it | `MultiDestinationDeployRunner.RunAsync`, before the first destination | `TheMultiDestinationRunnerRefusesBeforeTheFirstDestination` |
| 2–4 | local assistant's deploy and its card's Go | `AssistAgent`: no card for such a course; the hand-back refuses BEFORE any preview stop | `TheLocalAssistantsDeployIsRefusedBeforeThePreviewIsStopped`, `TheApprovalCardsGoIsRefusedToo` |
| 3 | headless deploy | `AssistWorkspace.Deploy`, first | `TheHeadlessDeployRefusesFirst` |
| 5, 7 | MCP `deploy_section`, `schedule_deploy` | plantoir-mcp's call-tool filter, `ReferenceWriteGate` | `TheWriteGateRefusesEveryWriteAndSaysWhichKind`, `TheGateIsChosenByEachToolsOwnReadOnlyFlag` |
| 6, 8, 10 | assistant scheduling, the Schedule Deploy… dialog, `plan_scheduled_deploy` | `ScheduledDeploy.Problem`, first — before "that time has already passed" | `TheScheduleSheetRefusesWhateverTimeWasAsked`, `PlanningAScheduledDeployRefusesToo` |
| 9, 11, 12, 13 | an alarm firing, `deploy.bat` by hand, `--to-folder` | `deploy.ps1`'s host-side check | `ReferenceMarkerAgreementTests` — all 26 rows against the REAL launcher (must-fail: the check off, and "the marker, plainly" goes past it) |
| 14 | `deploy.py` | inherited | `scripts/test_reference_course.py` |
| 15 | `verify-deploy.ps1` | inherits the above | opt-in, not run by bundle 6b |

**The MCP write gate** reads each tool's OWN `ReadOnly` flag off its
`[McpServerTool]` attribute, over all 42 tools plantoir-mcp serves (not the
mac's 22), and takes the three exemptions from the contract. A test adds a
fake write tool and sees it gated without being named. `undo_last_change` is
the only write tool with no course argument and is gated by the course its
newest recorded change touched. The local window is told nothing about a
reference course in `list_courses`; an outside session is told its folder,
code, kind and year. A bare code with no live course is refused naming the
candidates.

### Staging and the claim (#245)

As the mac: `courses/.plantoir-importing-<FOLDER>`, renamed into place last.
Two Windows choices: the folder is made with `CreateDirectoryW`, which refuses
an existing folder atomically (`Directory.CreateDirectory` does not), and the
in-app key is the courses folder's `GetFinalPathNameByHandle` spelling folded
to upper case (NTFS is case-insensitive). The import lease carries line 4 —
the owner's start, the mac's spelling — and an import lease with no name line
is judged as written by Plantoir.

### The import

The copy is a 1 MB-chunk STREAM copy, never `File.Copy` from the source
(which carries the read-only bit and alternate streams; CopyFileEx was
rejected for the same reason). Opened read-only with ReadWrite|Delete
sharing; only attributes and times are read. The walk is our own, one folder
at a time, hidden and system entries INCLUDED, and never lists what it leaves
behind. **Every reparse point is left behind**: the mac copies a symlink as a
link, but making one needs a privilege a teacher lacks (WinError 1314) and a
junction cannot be copied faithfully; the only link in a modern course is
`.merged_output`, left behind by name anyway. A `.lnk` is an ordinary file
and comes.

**Measured** end to end through `ReferenceImport.ImportCourses` (walk, copy,
clear, settings, lock, rename): a generated course of 507 MB in 605 files
(4 × 110 MB, 300 × 150 KB, 300 pages) beside a 110 MB `.merged_output` that is
skipped — **5.21 s and 5.63 s, 97 and 90 MB/s**, 24–31 progress reports, on
the NVMe above with Defender on and freshly written random data. The
planner's warm-cache probe of the bare copy was 431 MB/s by stream and
670 MB/s by `File.Copy`; the gap is the lock pass and the scanner reading new
files. A cold USB disk is estimated at 20–100 MB/s, so the bar is in BYTES,
reports at most every 100 ms, and Stop answers within one chunk. The trail's
"course imported" line carries the size and the seconds, so real speeds come
back in problem reports.

The import's CLEAR step (unlock, drop read-only bits) is a guard: a stream
copy carries neither today, which a test asserts directly
(`AStreamCopyCarriesNeitherTheBitNorTheLock`); the must-fail (switch to
`File.Copy` and drop the clear) turns it and
`ImportFromAFolderHoldingAReferenceCourse` red.

### What the interface withholds

Hidden, never greyed, on a reference course: the Deploy button, Schedule
Deploy…, Rename (the File menu item, F2 and the context menu all ask
`CourseThatCanBeRenamed`), Add Section…, Keep a Copy…, every Revise item,
the Site Health REPAIR button (and `SiteHealthRepair.OutcomeOfRepairing`
refuses on its own), and the Course Settings form, replaced by
`ReferenceSummaryView`. Cancel Scheduled Deploy… stays (gate by direction).
The footer's Remove on a reference course's section removes the whole course;
`ArchiveAndRemoveSection` refuses with `staysAsItIs` for any other caller.
Import Courses for Reference… is on the File menu, beside Restore from
Archive…. The calm note is shown before Obsidian opens, once per course,
remembered in the state folder.
## Copy a Page on Windows: exclusive creates, accent twins, and a Python oracle (#247, #384)

What a Windows implementer needs that the mac's write-up cannot give; the
rules and the reasoning are in `documentation/09-mac-app.md` → "Copying a page
from one course into another", and its "On Windows" subsection has the numbers.

- **"Already here" is an HResult, not a check.** Every page and picture is
  written by stream into `new FileStream(path, FileMode.CreateNew, …)`. An
  `IOException` whose `HResult` is `0x80070050` (`ERROR_FILE_EXISTS`) — or
  `0x800700B7` — is the ordinary skip, in the index's words. `File.Exists` then
  `File.WriteAllText` has a window; `File.Copy` carries the read-only attribute.
- **NTFS creates an NFD twin of an NFC name** (and refuses a case twin). The
  name index (`CoursePageCopy.Fold`: `Normalize(FormC)` then
  `ToUpperInvariant`, ordinal) is therefore the only guard, and it is updated
  after every successful write. Run every comparison ordinally:
  `string.Contains(string)` is ordinal; `IndexOf(string)` without a
  `StringComparison` is culture-sensitive and is what would fuse a combining
  mark with the space after a colon — Swift's trap, inverted.
- **The guard is fuzzed against the real build, in one Python pool.**
  `Plantoir.Tests/BuildFrontmatterOracle.cs` writes the pages to a temp folder
  and runs a `multiprocessing.Pool` that imports `scripts/build_site.py`, calls
  `frontmatter.load` and the real `process_frontmatter` for sections 1–4, and
  reads `publish` as `patches/publish.ts` does. It caches
  `_get_excluded_note_config` (which re-reads the contracts on every call) and
  nothing else. Single-process it took 78 s for 2,017 pages × 4 sections on this
  PC — every file open pays for Defender — and 30 s across the pool. Set
  `PLANTOIR_FUZZ_N` to go bigger; **One 80-minute run (PLANTOIR_FUZZ_N=1000000, seed 20260930, sources 0-999,999) reported 856 pages certified hidden that the build would publish; two later half-range runs (0-399,999 and 400,000-999,999, same seed) reported 0.** **Re-run 2026-10-01 (bundle 9, #414) over the ORIGINAL range in ONE process, seed 20260930, on dev `684993aa`: 399,417 certified, 600,583 refused, 0 certified-and-not-hidden, 1 h 8 m** (this PC, i5-8365U, 16 GB, Windows 11 26200; failing-page dump empty). **What differed is the binary, not the luck:** the generator is seeded and the guard deterministic, so the certified count is a fingerprint of the code — and the 856 run certified 401,096. Every committed state gives 399,417 (measured compose-only at `9f788524`, the very commit that recorded the 856, and at dev; the 400,000-999,999 tail at dev gives 239,722, exactly the clean tail run's count), and nothing the guard reads changed between them. So the 856 came from a binary no commit contains. WHICH part of it differed is NOT known: the guard, the generator, or both on the C# side (the count proves one of them did), and possibly an oracle from before `20adc020` (23:22, "the build oracle's workers share one temp folder"), which falls inside the window the run started in. If the difference was a wider generator, the committed guard may never have been tested on the inputs that failed. Not reproducible, so not explained; the issue stays open on that ruling. The read-back guard - a page not certainly hidden after it is written is deleted - is the safety net either way. Set PLANTOIR_FUZZ_DUMP to a path to write failing pages out, and PLANTOIR_FUZZ_SKIP to run part of the seeded sequence.
- **The dialog** is a `ContentDialog` whose primary button cancels its own
  close (`args.Cancel = true` under a deferral) so one dialog walks the three
  stages; the picker is an `AutoSuggestBox` fed only on
  `AutoSuggestionBoxTextChangeReason.UserInput`, so nothing opens on focus.

## Clubs, Course Settings and today's class on Windows (parity bundle 7: #274, #390, #387, #269, #406)

What the mac's pieces became here, and the seams a later reader needs. The
rules are the contract's; this is where they live in the C#.

### One naming value, with no default on any path that writes a page (#274)

`ClassPageNaming` (`Plantoir.Core/Models/ClassPageNaming.cs`) is word AND
scheme together, read from `CourseConfiguration.Naming`. Every parse site that
used to pass `UnitWord` beside a title now asks the naming
(`Naming.Parse(title)`), and every title is built by `Naming.Title(unit, day)`.
`InsertPlan` and `NewClassesPlan` carry a `required Naming`, so a plan cannot
be made without saying whose naming it uses — the mac's #267 plan review found
that with a default a missed site writes "Week 1, Day 10" and every test stays
green. A numbered page is held as unit 1 with the number as its day; nothing
may treat that unit as a real one:

- `PublishPlan.UnitNamed(raw, naming)` returns null in a numbered course, so
  "publish Week 1" goes to the page path (`wholeUnit`). The mac measured 4 of 4
  meetings published from that sentence before its fix.
- `PlanAddNextClass` refuses "start a new unit" and "add N days to Unit M" with
  `NextClassPlanner.NoUnitsInANumberedCourse` BEFORE the timetable is read.
- `PlanAddClasses` dates a numbered course's next page on the first class day
  after the LATEST dated page; `PlanInsertClasses` reads the frozen
  `unit`/`atDay` through `NumberedPosition` and plans with
  `PlanNumberedInsert` (renames only the run the new numbers land on; a later
  page moves only when its date collides; an undated page is placed by its
  number and never given a date).

**"meeting" never reaches the model.** The `…ForAMeeting` sentences
(`AssistWording.Meetings.cs`) are rendered only into the TEACHER's copy:
`Describe(ClassNoun)` on the plans, the start-of-year `TeacherText`, and in
`plantoir-mcp` the `_meta` teacher summary (`Proposing(forModel, forTeacher)`).
The text content — what the in-app model and Claude Code read — is the class
form byte for byte; `ClubNounTests` flips `class_noun` and compares. Refusals
are one string for both and keep the ordinary wording. Whether "never in
plantoir-mcp's results" was meant to include `_meta` was asked of Russell
(bundle 7, ruling 4) and DECIDED on 2026-10-01: it was not — the teacher's
summary is the teacher's copy. The in-app window's only channel is that result,
so the teacher's meeting card travels there; Claude Code ignores `_meta`. The
decision is written into the contract as `file-formats.json` →
`courseConfigKeys` → `class_noun.whatTheModelReads` (parity bundle 10).

### The wizard and Course Settings (#274, #390, #387)

`ClubFill.Applying` (Core) is the fill rule; the dialog calls it when the box
moves, after giving up an adopted skeleton, and `AdoptSkeletonStructure` does
nothing while the box is ticked. `NewCourseAnswers.ForAClub` turns off
example content, skeleton and curriculum for a club, so the wizard and
`GradedFoldersNewCourseContractTests` take the same path. Every word that
follows the box comes from `WizardWording.Panel(IsClub)` — never from
`ClubCodeRule`, which only pre-ticks the box until the teacher touches it.

Course Settings: `ClubSettingsRows.Shown` (locked rows only when recorded),
Rename… disabled with `renameLockedNumbered` for a numbered course, and
`SettingsSaveState.Decide` for Save. Measured/decided: the old
`dirty && Problem is null` held Save back for a course whose folder is missing
on THIS PC even for a colour scheme; now only an edit that moves
`deploy_target`, `deploy_folder_path` or `additional_deploy_targets` (compared
with the file as last read or written, a missing key equal to an empty one)
is held back, with `courseSettingsWording.saveHeldBack` in the Save status
line and `settings save held back` on the trail once per visit. The legacy
course-wide `show_grade_in_title`/`include_curriculum_coverage` Bool is SEEDED
into every section before one is changed (it was replaced by an empty map,
the mac's finding 10, and Windows had the same shape). The emoji field now
compares with the stored value's FIRST emoji, so a hand-edited "📚🔬" is not
written back when focus passes through it.

The label scan (`CourseSettingsSaveTests.NoLabelNamesTheMachinery`) reads
EVERY string literal under `Plantoir/Views` and `Plantoir/*.cs` rather than the
mac's "literal passed to a label call", and sets aside space-free paths and
file names and lines that MATCH output (`Contains`/`StartsWith`…). Measured
2026-10-01: the two #369 labels were the only hits, plus the About credit.
REJECTED: a list of label-setting calls (WinUI sets text through property
initialisers as often as calls, so a call list misses most labels).

### The lists as tables (#269)

`FormBuilders.StringListEditor` is a single-selection `ListView` with +/− at
its lower left; + opens a flyout with the old add rules; − and Delete share
`RemoveSelected`, which asks the protection again at the moment of acting, and
a blocked row explains itself (and records `removal blocked`) rather than
having a disabled −. A disabled list ignores both keys, asked in the handler
(the mac found `.disabled` did not stop its keys). Hide and Expandable are
`FormBuilders.SidebarVisibilityTable`, de-duplicated by exact name. Unproven on
screen: `ListTablesUiTests`, `MarksPoolRemovalUiTests` (now select-then-−).

### The front page's class line, and today's class (#274, #406)

`SectionIndex.Repointed(text, Pointer)` replaces `WithMostRecent`: the line is
found by the CLASS PAGE it names, outside code and `%%` comments
(`MarkdownCode.NotALinkRanges`, UTF-16 offsets on both sides), below the
frontmatter, and rewritten in place by position in the form the teacher wrote
(`writtenAs`). `Pointer` carries the section's class titles, the class's place
INSIDE the course folder (`AssistWorkspace.PointerFor`) and the course's
recorded `front_page_heading`, which only the insert fallback reads: Windows
still INSERTS under `#… <heading>` (absent → "Most Recent Class") when no line
names a class — the contract's `expectBodyOnWindows`. A "Help Sessions" embed
directly under the heading is no longer replaced (it was, until this bundle).

`TodaysClassOnTheFrontPage` (Core) decides and writes; the section window's
`PreviewOrStop_Click` is its only asker, after the deploy/other-program
refusals and before any lease is taken, and the preview starts after the
question has gone. Findings and the links checklist wait while it is up.
`OnlyThePreviewButtonAsks` pins the callers by source. The day is the first
ten characters of `created` as written; `cannotTell` visibility is not offered;
a front page that is a reparse point or read-only, or a course kept for
reference, is not asked about.

## Bundle 8: test hygiene, backups, the toast, accelerators, updates (2026-10-01)

Windows-only pieces of the parity run, on `issue/bundle8-windows-ui`. Each
says what was measured and what was rejected; the update design is in
[`11-release-strategy.md`](11-release-strategy.md) → "Updating itself on
Windows".

### The unit suite keeps its state in a scratch folder (#285, #179)

`Plantoir.Tests/TestAppDataRedirect.cs` is a `[ModuleInitializer]`: before any
test runs, `AppDataRoot.RedirectTo(%TEMP%\plantoir-tests-<pid>)`. Settings,
models, builds and scheduled-publish state a test touches land there, not in
the teacher's `%LOCALAPPDATA%\Plantoir`. Per process id, so two worktrees'
suites do not share a settings file. `AppDataRedirectTests` pins it. The redirect has one documented limit: during
a redirected UI test the launchers (`preview.ps1:512`) still write their trail
lines to the real `Logs` folder, because they resolve it themselves.

Two things the redirect cannot see, and what covers each:

- **Code that computes a per-user folder for itself.**
  `RealStateTripwireTests` scans `Plantoir`, `Plantoir.Core` and
  `Plantoir.Mcp` for `Environment.GetFolderPath(`, `SpecialFolder.`,
  `GetEnvironmentVariable("LOCALAPPDATA"|"APPDATA"|"USERPROFILE")`,
  `ExpandEnvironmentVariables`, and — because #179's leak was PowerShell text
  inside a C# string — `$env:LOCALAPPDATA`, `$env:APPDATA`, `%LOCALAPPDATA%`,
  `%APPDATA%`. Comment lines are skipped. Every hit outside `AppDataRoot.cs`
  must be on an allow-list counted per file and per occurrence, each with its
  reason, and an allowance larger than what the scan finds fails too, so the
  list cannot rot into a blanket pass.
- **A real Task Scheduler registration.** The initializer also sets
  `TaskScheduling.RealSchtasksGuardForTests`, which throws on any real
  `schtasks.exe` call other than `/Query`. It caught one on its first run:
  `TaskDefinitionTests.TheRegisteredTaskKeepsTheThreeSettingsAndCarriesItsToken`
  registers a real probe task ON PURPOSE (ruling 7 of an earlier bundle) and
  now lifts the guard for itself, by name.

**The scheduled wrapper (#179).** `$healthDir` and `$pendingDir` resolve
`$env:LOCALAPPDATA` at RUN time, so a test that ran the wrapper wrote into the
teacher's real `scheduled\folder-problems`. Both now come from
`TaskScheduling.StateDirExpression`: `PLANTOIR_TEST_WRAPPER_STATE_DIR` when it
is set AND inside `$env:TEMP`, else exactly the old path. The name is chosen
not to read like `--state-dir` (which moves the app's state; this moves only
two folders of a child script), and the TEMP condition means a variable left
set system-wide cannot send a teacher's 6 a.m. records somewhere the app
never looks. The suite sets it only on the CHILD `powershell.exe`, to the
redirected `AppDataRoot.Current`, so the app-side reader and the wrapper agree.
Rejected: baking the paths at write time — cheaper, but a teacher's wrapper is
then only right while the baked path stays right.
`ScheduledWrapperRunTests.ARunUnderTheSuiteLeavesTheRealFolderProblemsFolderAlone`
runs the wrapper for real and compares the real folder before and after; with
the override disabled it went red naming the file it leaked (that one file was
deleted). Two orphans from 2026-09-09 (`Plantoir-wraprun-a093729a…`) were left
on Russell's machine for him to remove.

### Same-second backups wait for the next second (#187)

Two backups stamped in one second used to get `…_221530-2.zip`, a name
neither reader parses: invisible in the Backups list, uncounted by pruning,
and invisible on the mac reading the same folder. `CourseArchiver.Archive` now
waits for the next second (at most three tries) and stamps again. Rejected:
teaching both readers a `-N` suffix (the mac's reader would hide a zip Windows
wrote until it learned it too), and a millisecond stamp (it changes the frozen
`zipNames` format). `ContractTests.CourseManagement_ZipNames` also takes each
case's `moment` apart field by field against `GregorianCalendar` (#161 part 2);
re-formatting with our own writer would stay green while both halves were
wrong.

### Backups: what they take, and deleting several (#283)

The mac's design (09 → "Backups: what they take") in WinUI terms. What
differs, and why:

- **All Backups is a dialog**, opened from the Backups group's context menu,
  not a sidebar row with its own pane. A `ListView` with
  `SelectionMode="Extended"` (Ctrl- and Shift-click) and columns course /
  when / who / size; the dialog's one primary button carries the count
  ("Delete 2 Backups…") and is disabled at zero. The confirmation is a second
  dialog, because WinUI shows one `ContentDialog` at a time.
- **The total is on the group's tooltip**, and each backup's size on its own
  row's tooltip (`SidebarRow.Tooltip` became a notifying property for this).
- **Sizes are `FileInfo.Length`** — the end of file, never the allocation —
  measured off the UI thread and applied only if no newer measurement began
  (`MeasurementGeneration`). The contract's sparse case is made with
  `FSCTL_SET_SPARSE` then `SetLength(467 MB)`; counted by allocation
  (`GetCompressedFileSizeW`) it read 0 bytes, which is the must-fail. It needs
  NTFS and FAILS, naming why, anywhere else rather than skipping.
- **An unreadable size is left out of the total**, shown as
  `backupSizeCouldNotBeReadShort`, and counted in a sentence beside the total.
- **What is held** (`HeldBackups`): each open assistant window holds the zip
  its conversation made, from the moment it exists until the window closes.
  An outside assistant (`plantoir-mcp`) leaves no record of which zip it made,
  so while another process holds a live `assist` lease on a course, the
  NEWEST assistant-made backup of that course is held too — it can hold one
  too many, never let the one it made go (bundle-8 ruling 4). The hold is read
  again at the moment of deleting.
- **After a delete**, every other window on the same folder re-reads its
  Backups list only (`WorkspaceViewModel.ReloadBackupsOnly`), not its courses.

Trail: `backups deleted` (`BackupDeleter.TrailLine`). The UI test
`AllBackupsUiTests` compiles and has never run (the desktop was locked).

### The scheduled-publish toast (#324)

#212's Windows half had not been built, so the toast is built minimally:
the scheduled run (Plantoir.exe started by Task Scheduler with no window)
posts ONE toast when it finishes, whatever happened, whose text is the
section's own sentence (`ScheduledPublishOutcome.Sentence`) — no new words.
Its launch argument is `section=<CODE>/<n>&folder=<escaped path>`, the tag is
the section-per-folder record name, so a later run replaces it. A click is
decided by `ScheduledPublishToast.Decide`, played from the 14 non-mac
`onClick` cases; `App.OnLaunched` registers `NotificationInvoked` (a click
while running, marshalled to the UI thread) and reads
`AppInstance.GetActivatedEventArgs()` for a click that started Plantoir.
Approximations, said plainly: an inactive app has no key window, so "front to
back" is newest window first; "the section is still in the folder" is
`courses\<CODE>\section<n>` existing. The announcing cases (`notification.announcing`)
are still #212's. Unproven on a real click.

### Accelerators under a dialog (#191)

Ctrl+O, Ctrl+N, Ctrl+Shift+R and F2 now return at once while a
`ContentDialog` is open (`Services/DialogGate`: the open popups whose child
IS a ContentDialog, so a context menu or tooltip does not block Ctrl+O).
Rejected: a counter every `ShowAsync` call site increments — right only while
all of them remember. **Whether WinUI delivers the keys under a dialog at all
was NOT measured** (locked desktop); `AcceleratorUnderDialogUiTests` is that
measurement. The guard costs nothing if they do not fire.

**How the measurement is made, with the guard in place (bundle 9,
2026-10-01).** The handlers ask `DialogGate.Holds(root, "<key>")` — `IsOpen`
plus a record: in a run whose state is redirected (`--state-dir`, which only
the UI tests pass) every key it holds is appended to
`accelerators-held-under-a-dialog.txt` in that state folder. The UiFact puts
the Back Up Now confirmation on screen, presses all four keys (Ctrl+O last,
because a failed guard would open the native picker over everything), and
reports per key "DELIVERED under the dialog (the guard held it)" or "not
delivered (the dialog kept it)" — in the test output and in
`%TEMP%\plantoir-191-measurement.txt` — while ASSERTING the behaviour either
way: no rename dialog, no new top-level window, the confirmation still up.
**Rejected:** removing the guard for one run to see whether the keys act (a
test that must be edited to measure is not one Russell can run from the
script), an automation property carrying a count (a screen reader would
announce it), and a trail line (a teacher-visible record of a key that did
nothing, with a contract entry and a mac issue for a measurement aid). A
teacher's run never redirects, so it never writes the file.

**Measured, 2026-10-01 13:40 (bundle 11, run 1, unlocked desktop, Intel
i5-8365U, Windows 11 26200), verbatim:** "F2: not delivered (the dialog kept
it) / Ctrl+Shift+R: not delivered (the dialog kept it) / Ctrl+N: not delivered
(the dialog kept it) / Ctrl+O: not delivered (the dialog kept it)". The test
passed in every whole-suite run after. So WinUI does not deliver the window's
four accelerators while a ContentDialog is up, on this build; the guard is
belt and braces, and costs nothing.

### A wrapping panel squeezed narrow (#214, the mac's #211)

Read, not measured: `TaskProgressView.xaml`'s Done panel and the section's
`ScheduledPublishNotice` (an `InfoBar`) are wrapping `TextBlock`s in Auto rows
and StackPanels, with no construct that makes a text's height rigid — so
nothing was changed (bundle 9 ruling P1: change layout only if the XAML shows
an unbounded height by reading). WinUI measures a wrapping `TextBlock` at the
width its column ACTUALLY has, not at the near-zero width SwiftUI's
`NavigationSplitView` PROPOSED while measuring the mac's; but a teacher can
still squeeze the window until the content column is narrow (the sidebar
column keeps `MinWidth="180"`), and how tall the notice gets then is exactly
what reading cannot settle. `PanelHeightUnderSqueezeUiTests` is
the measurement: it writes a scheduled-publish SUCCESS record naming a long
folder path and Netlify into the run's own state folder, opens the section,
squeezes the window to 500 px and reports the notice's height against the
window's (`%TEMP%\plantoir-214-measurement.txt`), asserting the notice stays
inside it. Until bundle 11 the folder publish's Done panel was left
unmeasured because putting it on screen needs a real publish; tests may run one
since then (see "A test that runs a launcher"), so a second fact,
`TheFolderPublishsDonePanelStaysInsideASqueezedWindow`, publishes a course to a
folder with a long path, squeezes the window the same way and measures every
part of the Done panel against it (`%TEMP%\plantoir-214-donepanel.txt`).

**Measured, 2026-10-01 13:51 (bundle 11, run 1, same PC), verbatim:**
"window 900x737; notice 631x157 (top 135 below the window's top)". The
resize to 500 px was NOT honoured: the window would go no narrower than 900,
so the squeeze a teacher can make is bounded there, and at that width the
notice is 157 px of a 737 px window, inside it. The test's own wait for the
width to reach 520 times out silently; it should say so if the window's
minimum ever drops (left as it is: the assertion that matters — the notice
stays inside the window — holds at the narrowest width a teacher can reach).
