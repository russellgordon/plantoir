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
whose first section says where the app stands, and the open `windows` issues; for the reasoning behind decisions,
the rest of this folder. Those are maintained as work
happens. This page is not a status report and should not be read as one.

---

## Preview and publish mechanics that match the mac (bundle 4, 2026-09-30)

One place for what changed on the preview and publish path in bundle 4, so a
reader of the code finds the reasons. Hardware for every number: Intel Core
i5-8365U, 16 GB, Samsung 980 SSD, Windows 11 Pro 25H2 build 26200.

- **"Closed for a deploy" (#436, v1.4.3).** A serving preview that another
  program's deploy ended reads "Closed for a deploy", not "Something went
  wrong" (`ScriptRunner.EndIsAClosingForADeploy`; the stop's mark here is
  `returned non-zero exit status 15.`, measured — TerminateProcess(15), since
  Windows has no SIGKILL). It asks the leases of OTHER processes only, so a
  deploy of the same course from another window of the SAME Plantoir (one
  process, its own build lease excluded) still ends the preview as "Something
  went wrong". That is deliberate, the safe direction — an end is never hidden
  — not a bug. Once a serving preview ends, the window also gives up its
  `preview` work lease (`WorkLease.LetGoWhenAServingPreviewEnds`), so an
  outside assistant is no longer told a preview is open.
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
  first verdict. `theSiteNeverAnswered`'s sentence is the contract's with its
  `{machine}` filled "PC" (`specialNames.platformWording.machine`, #410/#418;
  since v1.4.3 a fill driven by `machine.usedIn` in `MachineWordContractTests`,
  #438, where it used to be a "your Mac" → "your PC" substitution).
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
| `swift\` | Since v1.8.6 (#570): `6.4.0\` is Swift, about 0.9 GB, fetched by the first preview with a Swift block (`READY.json` says which pins it is); `work\` is the per-block compile folder; `download\` and `staging-*` exist only while getting Swift ready; `fetch.lock` and `fetch.log` beside them. Resolved by the LAUNCHER's Python from `%LOCALAPPDATA%` (`swift_windows_fetch.home()`, `PLANTOIR_SWIFT_HOME` for a test), so `--state-dir` does NOT move it. Uninstalling leaves it. |
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
four settings the command-line switches cannot set: it may start on battery
(`DisallowStartIfOnBatteries` false), is not stopped by going onto battery
(`StopIfGoingOnBatteries` false), starts as soon as possible after a missed
start (`StartWhenAvailable` true), and — since #470 — QUEUES a start that
comes while the earlier run still works (`MultipleInstancesPolicy` `Queue`;
it was `IgnoreNew`, which refused that start and lost the deploy). The
measurements and what was rejected are in 07 → "Set again while the run
works (#409)". The older description here — a task that
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
.\Vendor\fetch-obsidian-addons.ps1   # REQUIRED once per clone (#581): the build refuses without it
dotnet build Plantoir/Plantoir.csproj -c Debug
dotnet test  Plantoir.Tests/Plantoir.Tests.csproj
```

Skip the fetch and everything still BUILDS — and then every launcher refuses
with "This copy of Plantoir is missing its website builder", which reads like a
broken install rather than a missing step. (`Vendor/fetch-llama.ps1` is the
same arrangement for the assistant's engine.) **Re-run it after pulling a
change to its vendor pins**: since #503 (2026-10-15) a runtime made before
`runtime\vendor` existed STOPS the app's build ("predates the page
features … Re-run windows-app\Vendor\fetch-runtime.ps1"), and the re-run
fetches only that folder — "Diagrams and graphs" below. Since #568
(2026-10-22) the same is true of a runtime made before Pyodide joined that
folder: its manifest has no `pyodide` key, the build stops with the same
sentence, and the re-run redoes the whole vendor phase (49 s here) —
"Runnable code (#455)" below.

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
| `--stage-scene <scene> --theme light\|dark --folder <dir> --ready-file <file> [--courses …] [--reference-copy …]` | Stages one of plantoir.app's pictures in a REAL window and holds it open, for `website/shots/app_scenes_windows.py` to photograph whole (#380). See "The pictures on plantoir.app" below. Replaced `--capture-marketing-shots` and `--hero-window`. |
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

### A red that is a clock: the pool starved early in a full run (#543, #427)

Three tests with a real socket or a real process went red one run in N in a
full `dotnet test` and green alone straight after: `PreviewPageStatusTests.
EachStatusIsReadAsTheServerAnsweredIt` ("Expected: 200, Actual: null", 7 s,
11.6 s into the 1.7.1 cut's run), its sibling `AStoppedPreviewEndsTheAsking
RatherThanReadingItAsSilence` ("No exception was thrown", 7 s, 26.8 s into a
run), and `ConPtyRedirectedParentTests.AChildStartedFromARedirectedParent
StillWritesToItsPseudoConsole` (11 s the second time; the first's duration and both messages were not kept).
Seven seconds is the product's 5 s per-try clock (`previewStartPage.
secondsPerAttempt`) plus about two; eleven is the test's 10 s wait plus one.

**What was reproduced** (2026-10-16, Intel i5-8365U, 8 logical CPUs, 16 GB,
Windows 11 Pro 26200), with a scratch harness that was NOT committed: before
each repetition it blocks every pool thread on a `ManualResetEventSlim`
(4 × cores + the pool's current thread count work items, released from a
DEDICATED thread, since a pool timer could not fire), then runs a verbatim
copy of the old and the new test body, ten times each:

| Body | Old | New |
|---|---|---|
| ConPTY, pool held 12 s | **8 of 10 red**, each `exited: True` and an EMPTY transcript, 11.8 s | 10 of 10 green |
| `EachStatus…`, pool held 8 s | 1 of 10 red ("Expected 200, Actual null", 7.8 s) — the first repetition in the process | 10 of 10 green |
| the same, threads handed back one per 60 ms | 1 of 10 red (7.0 s), again the first | 10 of 10 green |
| `AStoppedPreview…`, both release shapes | 0 of 20 red | 20 of 20 green |

The ConPTY shape is the useful one: an EMPTY transcript is starvation (the
pool reader never ran), which is not #155's shape — mode sequences and no
`PTY-OK` — so a red there should be read by its transcript. The harness
proves the tests were VULNERABLE to a starved pool; it does not prove that
is what happened in the recorded runs, whose messages were lost (#427) or
whose sibling was not reproduced (`AStoppedPreview…`, a timer race that
needs the 5 s per-try timer to be serviced before the 200 ms one).
CPU load alone does NOT starve the pool, and the loops say so: each class
run alone 50 times with the NEW bodies gave 50 of 50 green for both
classes, and 50 of 50 again for both while eight busy-loop jobs held every
core (200 runs in all, `dotnet test --no-build`, judged by the totals line).

**What changed** (test code only): `EachStatus…` passes a 30 s per-try clock
on the five answered paths and keeps 300 ms on `/stalls`, the one assert
whose subject is the clock. `AStoppedPreview…` no longer races two timers:
`ServeAsync` completes a `heard` `TaskCompletionSource`
(`RunContinuationsAsynchronously`) when the request arrives, the test then
cancels the preview itself with a one-minute per-try clock, and waits on the
asking with `WaitAsync(30 s)`, so a product that ignored the stop would fail
with a `TimeoutException` rather than pass when its own clock ran out. The
ConPTY test reads on a dedicated `Thread`, as the product's `ScriptRunner`
does, and both of its waits are 30 s. A pass still takes milliseconds.

**Rejected:** `ThreadPool.SetMinThreads` in the test host — it would hide a
starvation a product path could meet, and the tests would then be passing in
a process unlike the app's. Waiting for the listener to accept once before
the first assert (#543's other option) — `listener.Start()` already accepts
at the TCP level (the kernel completes the handshake into the backlog
before `ServeAsync` returns); what starves is the user-mode work on both
sides, the accept loop, the reads and writes, HttpClient's continuations
and the timers, so it would change nothing. A dedicated server thread
instead of `Task.Run` — the client side starves too, so it cures half.

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

**Since 2026-10-15 every entry carries its OWN milestone, and a test holds the
cut to it (#481).** Windows is catching up from 1.4.5 to the mac's 1.7.1 in
batches, and an entry may name work a LATER BATCH owns, on the milestone that
work shipped in on the mac — `Owed(area, issue, milestone, reason, keys…)`, with
`V150` … `V171` spelled exactly as the GitHub milestone titles.
`NamedGapLedgerTests.EveryEntryIsOwedByAMilestoneLaterThanThisBuild` reads
`<Version>` from `Plantoir/Plantoir.csproj` and fails for any entry whose
milestone is not LATER than it — so setting 1.7.1 turns every v1.5.0–v1.7.1
entry still there red, while an entry owed by a genuinely later release
survives the cut. It is "later than this build", not "empty at the cut", on
purpose; a milestone that is not a version fails, because it cannot be
compared. Batch 1 (2026-10-15) also wired four more lists into the ledger, in
the same shape as the ones below: `toolchain.json` → `pins` with a
`windowsRuntimeContains` (`ToolchainContractTests.TheWindowsRuntimeRecipeCarriesTheSamePins`
— the contract-agrees-with-itself check still runs for every pin; pagedjs
against #496, functionPlot and nodeTikzjax against #503, all three closed by
#503's batch 5A the same day),
`course-management.json` → `zipNames.cases` (`ContractTests.CourseManagement_ZipNames_MatchesContract`,
each case on its own; two Section-menu names against #489) and
`backups.pruneCases` (`BackupsContractTests`; one case against #489), and
`assist-cases.json` → `scenarios.cases` (`AssistScenarioTests` — a theory, so a
ledgered scenario must still FAIL, checked per case through
`NamedGapLedger.Holding`/`ClosedMessage`, and
`TheLedgeredScenariosAreStillInTheContract` checks the other direction; three
Deploy-question scenarios against #489). The ledger file is the live list, and
it is **empty**: batch 6 (#514) closed its last two entries the same day, and
mac 1.7.2's sixteen plan-table sentences (#524), held open against #548 on
2026-10-16, landed with #548's plan table that day ("The plan as a table",
below); `NamedGapLedgerTests.TheRuleStillCatchesAnEntryOwedByThisBuildOrByNoVersion`
keeps the rule exercised on made-up entries meanwhile.

**From 2026-09-30 to the v1.4.0 cut the ledger was the parity milestone's
BURN-DOWN LIST** (Russell: no Windows release before parity, so an entry could
name an open issue on "Windows: parity with mac v1.4.0" itself). Bundle 1 of
the parity run widened it from two entries to every debt the suite could name,
so that a red run means something again:

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

**It is opt-in and belongs to no gate.** Every test that drives the window
carries `[UiFact]`, which skips unless `PLANTOIR_UI_TESTS=1`, so a plain
`dotnet test` builds them and runs none of those — only
`AssertAbsentRuleTests`, three plain facts that pin the harness's absence rule
and need no desktop (bundle 11). The project is in the solution so a SOLUTION build compiles it —
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

### Real input goes where the pointer is: click the rectangle, with the window in front (2026-10-03)

Much of the suite acts through UI Automation patterns (Invoke, Toggle,
Select), which reach the app whatever is in front of it. FlaUI's
`element.Click()` and `RightClick()` are different: they send REAL mouse
input to the element's "clickable point", and typed keys follow the focus —
so both go to whatever window is under the pointer and in front.

On 2026-10-03 the suite ran 41 of 44 on this project's Windows PC (Intel i5-8365U, 16 GB, Windows 11 Pro build 26200), reached over a
3840-pixel-wide remote session at 200% scale. All three failures were Copy a
Page tests saying Copy was never offered. What happened, measured by logging
the front window, the pointer and Plantoir's rectangle every 150 ms:
`picker.Click()` moved the pointer to x=3839 (the screen's edge), y=1168, for
a search box whose middle was at y=584 — the element's "clickable point" came
back at TWICE its real coordinates. The click landed on the terminal behind
Plantoir, which took the focus, and "Big", "Ohms" and "Watt" were typed into
it (and, with the terminal minimised, into Windows Search, which opened Edge).
The dialog itself was drawn correctly; the product was not at fault. The same
tests had passed 13 of 13 two days earlier on a smaller desktop.

So: **a test that clicks and then TYPES calls
`DrivenApp.ClickMiddleOf(element)`, never `element.Click()`.** It brings the window to the front first
(`BringToFront`, which joins the input queue of the window that is in front —
Windows refuses a plain `SetForegroundWindow` from a process that is not —
and throws, naming the window in the way, rather than typing into it), then
clicks the middle of the element's bounding rectangle, which is in real
pixels at every scale. Rejected: FlaUI's `Window.SetForeground()` and
`Focus()` (measured: the terminal stayed in front); minimising the terminal
from the runner (the click still went to the doubled point).

**Since #428 item 4 (2026-10-04) no real click in the suite asks for a
clickable point.** At first only the two Copy a Page pickers were changed;
the twenty-odd other `Click()` / `RightClick()` calls (the helpers in
`DrivenApp.cs`, `AllBackupsUiTests`, `AcceleratorUnderDialogUiTests`,
`EndToEnd.cs`, `ReferenceCourseUiTests`, `LinksChecklistUiTests`,
`PanelHeightUnderSqueezeUiTests`, `ImportForReferenceUiTests`,
`CopyAPageDialogUiTests`) had passed 44 of 44 on the same 200% session, but
nothing proved they could not meet the doubled point. Now: a row, the menu
bar or anything else in the window → `ClickMiddleOf` / `RightClickMiddleOf`;
an item of a menu that is already OPEN → `DrivenApp.PressMenuItem` (its
Invoke pattern, else a click in the middle of its box WITHOUT `BringToFront`,
which could dismiss the menu that is already in front); a dialog's button →
`AsButton().Invoke()`. Every one of those real clicks goes through
`DrivenApp.MiddleOf`, which REFUSES (`ClickWouldMissException`) an element
that is off screen, has an empty box (whose middle is 0,0), or — for
anything in the main window — whose middle lies outside the window's box:
the old `element.Click()` threw `NoClickablePointException` in those cases,
and FlaUI clamps neither a row scrolled out of view nor an empty box, so
without the refusal the click would land on the taskbar, the desktop or
another app (the stack review's finding; `ClickRefusalRuleTests`, plain
facts). An open menu's item may lie outside the window, so only the first
two refusals apply to it. `PressRowMenuItem` again skips and retries when
the clickable-point wait runs out. The Ctrl+click in `AllBackupsUiTests` releases Ctrl
in a `finally`, so a failed click cannot leave the key down for the next
test. `grep -n "\.Click()\|\.RightClick()" Plantoir.UiTests/*.cs` should
find only the comment in `DrivenApp.cs` that explains why. Built, NOT run
through the window when this was written (the UI suite needs the whole
machine; the director schedules it).

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
deletes that builds folder; and deletes the run folder with
`DrivenApp.DeleteRunFolder`, which lifts the reference lock first so a
reference course the app locked can go with it. (Before bundle 11 the
reference tests' temporary folders outlived their runs for exactly that
reason, and two still did after the 44-of-44 run of 2026-10-03 — `rmdir`
"Access is denied" on `courses\ICS3U-…\section1\index.md`, removed by hand
with `icacls /reset /T`. Since #428 item 5 the unlock covers the WHOLE run
folder rather than only `workspace\courses` — the import test keeps last
year's working folder in a scratch folder beside it — Dispose waits for the
app's pid to be gone first, and the unlock is asked again between delete
attempts. The two days' leftover was never reproduced, so which of those it
was is not known; `RunFolderTeardownTests`, two plain facts, pin the
behaviour without a desktop.) Rejected: redirecting `LOCALAPPDATA` for the app's children so the
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
  that run without a desktop; the timeout case is the must-fail). It also
  keeps watching for 2 s after the first empty answer, so a control drawn a
  moment late is not declared absent.
- **An id set on a ContentDialog's TEMPLATE button once, at Opened, does not
  always stick**: Copy a Page's Cancel was found as the template's own
  "CloseButton" in 2 of 5 runs (17, 18). The app now re-tags its two buttons
  on every layout pass while the dialog is up, and the tests close it by
  `copyPageClose` only (`EndToEnd.CloseCopyAPage`, which fails when there is
  no dialog or no id) — a "whichever id" fallback had hidden the race.
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

**What a screen reader hears for an icon-only button (#426, v1.4.3).** The same
runs measured the sidebar's Add and Remove with an EMPTY automation Name, so
Narrator said only "button". Every icon-only button in the main window now
carries `AutomationProperties.Name` in the words its tooltip already shows: the
sidebar's Add and Remove, the section toolbar's back, forward, reload, Obsidian
and Open in Browser, Course Settings' Obsidian, and a list row's rename
(`FormBuilders`; the row's ⓘ and the lists' + and − were already named).
Preview and Deploy show text beside their icon and were left to be named by
it — which was WRONG, measured on the v1.4.3 cut (2026-10-07), the first time
the UiFact below ran: a Button whose content is a `StackPanel` (icon plus
`TextBlock`) is not named from that text, so both came back empty. They now
carry their visible words as `AutomationProperties.Name` — "Deploy", and
Preview's set in `SectionDetailView.RefreshChrome` from the same line that
sets its label, so it reads "Stop Preview" while one runs. The same run found
every `ToggleSwitch` in Course Settings and the wizard with NO Name at all
(their On/Off content is empty and the label is a separate `TextBlock`), so a
switch was announced "toggle switch, off" with no word of which setting it
was: `FormBuilders.LabeledRow` now gives its control the label as Name (unless
one is already set) and as `LabeledBy`, which names every switch, combo box
and text box built through it. A reference
course's row SHOWS its code, which is the live course's code too, so its Name is
fuller — `ReferenceCourse.SpokenRowName`, "ICS3U, kept for reference, 2025–26"
(or without the year when none is set) — through `SidebarRow.SpokenName`, which
is the Title for every other row. Windows' own: VoiceOver reads SwiftUI buttons
by their labels, so the mac owes nothing. Pinned by two UiFacts in
`SidebarNamesUiTests` (no Button in the main window with an empty Name, asked on
the sidebar, a course's settings and a section; the reference row's Name) and by
`ReferenceCourseTests.AReferenceRowIsSpokenWithItsYear`. Rejected (reasoned, not
measured): a HelpText on the reference row instead of a fuller Name (the Name is
what is announced first, so the two ICS3U rows would still start identically); naming
Preview/Deploy explicitly because their label changes (to Stop, and to
"Available in a moment") and a static Name would go stale — reversed on the
v1.4.3 cut: only Preview's LABEL changes, and its Name is set beside it; "Available
in a moment" is a tooltip, and Deploy's label is always "Deploy".

**Two harness traps from the same cut (2026-10-07, this PC).** FlaUI's
`element.Name` asks UI Automation NOT to fill in a default, so an element that
nothing names reports the property unsupported and `.Name` THROWS
(`PropertyNotSupportedException`) — the empty-name UiFact crashed on the very
switch it exists to report. A check for "is this named?" reads
`Properties.Name.ValueOrDefault`. And a Ctrl-click sent back to back —
`Keyboard.Press(CONTROL)` then the click — arrived as a PLAIN click in both
runs that reached it, so All Backups' second choice replaced the first ("Delete
1 Backup…"); with 150 ms either side of the click it is a Ctrl-click. Not a
product fault: a teacher's finger holds Ctrl far longer than that.

Measured for the end-to-end tests on this PC: creating MFM2P in the wizard
29–32 s; its first preview served 52–61 s after Preview was pressed;
publishing a one-section course to a folder 1 m 52 s – 3 m 3 s per test (build
included); the end-to-end set of 13 tests 16 m 47 s – 20 m 33 s; the whole
suite of 40, 43 m 38 s – 48 m 43 s (with the PC also busy with other work).
After the harness lessons above and the review's fixes (absences need an
answer; the preview pane's loaded address asserted), and on a tree merged with
bundle 10, the end-to-end set ran 13 of 13 five times in a row (7 m 2 s –
7 m 17 s each on a quiet PC) and the whole suite 44 of 44 (19 m 39 s), with no
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
Since #427 (2026-10-16) the test reads on a dedicated thread with 30 s
waits: a pool reader starved at the start of a full run gave `exited: True`
and an EMPTY transcript — a different shape from the one above — in a
harness that starved the pool ("A red that is a clock", above).

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
   guard. (The recipe copy into `.toolchain` DOES have that guard — once per
   folder per process, owned by `ToolchainReadiness` and run in the background
   since #473 — so a stub written into
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
4. "Save and Continue" sends what you typed: the site Netlify creates carries
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

## Printable pages (#454 on the mac; #496 here, v1.6.0)

The build, the site and the shared Python do everything for a printed page,
and Windows inherits them unchanged (`support/quartz`, `scripts/page_features.py`,
`scripts/print_settings.py`, the skills under `support/agent_guidance`).
Paged.js and Latin Modern are in `runtime\vendor\pagedjs` (since 2026-10-15,
fetched with the figure engines: "Diagrams and graphs" below). The design
and every mac measurement:
[06 → F](06-quartz-customizations.md#f-additions-installed-every-build-printable-pages-454-v200),
[05 → Printable pages](05-build-pipeline.md#printable-pages-what-the-build-does-454-v200),
[09 → Printing](09-mac-app.md#printing-454-v200). What the Windows APP does
(#496, batch 5B of the catch-up to 1.7.1, 2026-10-15):

**Course Settings → Printing**, between Footer and Content Structure, as on
the mac: the school name, three switches (Name, Date, Class #), two pickers
(top left / bottom left / not printed) and a sketch of the corners
(`PrintCorners.Sketch`, the bottom-left corner led by
`courseSettingsWording.printingSampleTitle` since #499). The four keys are
`CourseConfiguration.PrintSchoolName` / `PrintBlanks` / `PrintSchoolNameAt`
/ `PrintCourseCodeAt`. Two rules a reader of the code would not guess:

- **Getters never write, and a setter given what it would read back is a
  no-op.** `HasUnsavedChanges` compares the raw values, so a getter that
  tidied `["seat","class_number","name"]` into the file would open the course
  dirty (`savingSettings.freshOpenCases`, case 9; case 10, a `print_blanks` of
  null, since #537/#551). And WinUI raises
  `TextChanged` for text set in code, LATER, after the handler is attached —
  so "set the value before attaching the handler" is no guarantee for a text
  box, and a stored `"   "` school name would have been removed on open
  (plan review L9). Both are held by `PrintablePagesTests` and
  `CourseSettingsSaveTests.AFreshlyOpenedCourseIsClean`, which reads the four
  getters on every fresh-open case before deciding.
- **A `print_blanks` of JSON null is Name and Date**, because that is what the
  BUILD prints (`print_settings._blanks` reads null as absent). The mac read
  NSNull as no blanks, so its sketch contradicted the paper; the authored
  corners case "blanks of null are the default" now says which is right, and
  the mac owes the fix (a `mac` issue). An empty list is still no blanks.

**The `settings saved` line** says what a Save changed about printing
(`SettingsSavedLine`, unit-tested now; it was built inline in `Save_Click`
and untested): `; printing: school name set|changed|cleared` (never the
name), `blanks Name, Date → Name, Date, Class #`, `school name top left →
not printed`, `course code bottom left → top left`, only the parts that
changed, before compared from the same disk read the Save already made (a
file that could not be read compares with the defaults). The clause sits
where the mac's does, after the course and before what was kept or replaced.
The rest of the Windows line still differs from the mac's (`; kept from
elsewhere: X`, no `— sidebar:` part); that predates #496 and is left alone.

**The guidance for assistants** (`AgentGuidance`, a line-for-line port of
`AgentGuidance.swift`; the rule is `printablePages.agentGuidance`): the
skills in `support\agent_guidance\skills\` mirrored into `.claude\skills\`
and `.agents\skills\` (each skill's folder is the app's whole), and the
managed section in `AGENTS.md` and `CLAUDE.md`. Where it runs and why:

- **After the copy, on a task of its own** — `ToolchainReadiness` starts it
  when a copy of the folder ends, whatever the copy's outcome, and never
  chains it to the copy's task, which `RefusedWhileTheFolderIsGettingReady`
  and `InitializeWorkspace` await. A failure is a startup.log line, the trail
  event `guidance for assistants could not be written` and a closable
  InfoBar (`guidanceNotice`) with `words.couldNotWrite`; the folder's State
  is untouched, so Preview, Deploy and New Course never wait on it
  (`AgentGuidanceTests.AGuidanceFailureNeverHoldsTheFolderBack`, through the
  real hook with a `.claude` that is a FILE). Once per folder per process,
  unless it failed.
- **The notice's reason has no path.** .NET's IO messages carry the full
  path ("Access to the path 'C:\Users\…\CLAUDE.md' is denied."), so the
  notice says `Win32Exception`'s sentence for the error code instead
  ("Access is denied.") — only for a FACILITY_WIN32 code (`0x8007xxxx`:
  `0x80070005` access denied, `0x800700B7` a file where the folder belongs,
  `0x80070020` in use), because for any other `Win32Exception` says "Unknown
  error (0x1620)"; anything else says "could not be written" (plan review
  M6). The trail line keeps the PLACE (`.claude/skills/plantoir-printing`,
  forward slashes, from the working folder down); `LogRedactor` takes the
  account name out of anything else, it does not redact a path.
- **Writes are atomic** (a temporary file moved over the old), as the mac's
  `.atomic` is: the pass runs on its own task, which the quit path does not
  wait for (M7). **A file whose only difference from the current section is
  its line endings is UNCHANGED**, so an editor that saves CRLF does not have
  the section rewritten at every launch. **Files are read with a strict
  UTF-8 decoder**, so a file saved in another encoding is refused, never
  written over (`addCases` "cannot be read again").
- **The skills are whatever `support\agent_guidance\skills\` holds**, five
  today: `plantoir-page-authoring` (#596, the one the root files name FIRST;
  it routes to the four below, `printablePages.agentGuidance.pageAuthoringSkill`),
  `plantoir-printing`, `plantoir-math-graphs`, `plantoir-runnable-code` and
  `plantoir-quizzes` (#563). `AgentGuidance.Write` enumerates the folder, so a
  new skill reaches a Windows working folder with no code. What the quizzes
  skill teaches — the `> [!quiz]` callout and what the site does with it — is
  [06 → J](06-quartz-customizations.md#j-self-check-quizzes-563-v180), and
  what the build does is 05 → "Self-check quizzes: what the build does".
- **The question** is a ContentDialog (`MainWindow.Guidance.cs`): title
  `askTitle`, `askFound` as the explanation under it, `askWhat`,
  `askYoursStays`, an Expander (`showWhatIsAdded`) over a read-only
  monospace box with the section; Add is the default (Enter), Not Now the
  close button (Escape). ONE dialog per window: it is asked only when
  `DialogGate.IsOpen` says none is up, and tried again on activation and
  every 2 s while a file waits. **The quit question takes it DOWN first**
  (WinUI throws on a second ContentDialog — plan review M8), and a question
  taken down that way, or by the window closing, is PUT BACK unanswered:
  closing a window is not a Not Now. From just before the quit question is
  put up until it closes, the question taken down STAYS down and the re-ask
  is the 2 s timer's (the batch 5B review's H-1: putting it back raised
  `GuidanceChanged`, the question came back inside the quit question's
  50 ms waits, the quit question's `ShowAsync` threw, and the close did
  nothing). A question up at launch also makes `UpdatePrompts` and the
  assistant's later-classes question hold back, through the `DialogGate`
  check each already makes. A later pass that succeeds clears the notice an
  earlier failure left, as the mac's `applyGuidance` does, and the bundled
  bodies are read with LF endings, so an autocrlf checkout writes and
  fingerprints the same section as the mac. Each file is asked about in one
  window only, AGENTS.md first. Not Now answers are kept in
  `%LOCALAPPDATA%\Plantoir\agent-guidance-declined.json` (path,
  case-insensitive, → the section's signature), deliberately out of
  `AppSettings`, which other code rewrites whole.
- **This repository is itself a working folder** (`preview.ps1` and
  `courses\` at its root), so opening it in Plantoir writes
  `.claude\skills\plantoir-*` and `.agents\` (all ignored by `.gitignore`;
  the graphs skill's line was missing until this batch) and ASKS about the
  repository's own `CLAUDE.md` and `AGENTS.md`. **The answer in a checkout of
  this repository is always Not Now**: Add would append Plantoir's teacher
  guidance to the file that briefs every session here.

**The preview pane hands pages to the browser** (`PreviewBrowserHandoff`,
the mac's port; the wiring is `SectionDetailView.HandPagesToTheBrowser`):

- **A link that opens a new window** — the page's own PDF among them — is
  handled (`NewWindowRequested`, `Handled = true`) and opened in the
  teacher's DEFAULT browser, `localhost` rewritten to `127.0.0.1` as Open in
  Browser does; any scheme but http, https and mailto is dropped. Unhandled,
  WebView2 opens a bare popup window owned by Plantoir: not the teacher's
  browser, no address bar or bookmarks, gone when the app closes, and unlike
  the mac (the director's decision for batch 5). REJECTED: leaving WebView2's
  popup.
- **Print**: the shared page code (`print.inline.ts`) asks the app when it
  finds `window.webkit.messageHandlers.plantoirPrint`, which WebKit gives the
  mac. Windows INJECTS exactly that shape
  (`PreviewBrowserHandoff.PrintShim`, by `AddScriptToExecuteOnDocumentCreatedAsync`
  and again on every completed navigation) — on the preview's own pages
  only, `location.hostname` `localhost` or `127.0.0.1`, so an outside site
  the pane was taken to never gains a `window.webkit` (the batch 5B
  review's L-3) — forwarding to
  `window.chrome.webview.postMessage({plantoirPrint: …})`; the app accepts
  only a message from the preview's own origin, a mode from
  `printablePages.modes.list` and a paper from `paper.cases` (none =
  portrait), and opens `#plantoir-print=<mode>&paper=<paper>` in the browser.
  No shared file changed (the plan's option (i)). The risk named — page code
  reading `window.webkit` to detect Safari — was checked: nothing in the
  bundled Quartz, its scripts or KaTeX reads it (Mermaid comes from a CDN
  and was not checked). REJECTED for now: option (ii), a hook in
  `print.inline.ts` gated on a Windows-only flag (never on `chrome.webview`
  alone, which every WebView2 host has) — a shared change for no difference
  a teacher could see.
- Each hand-over is one trail line, `preview page opened in the web browser`,
  naming the page the teacher was ON and only the KIND of link (the page's
  own PDF, another page of the site, another site) — never where it led.
- **Ctrl+P in the pane** is WebView2's own print (its browser accelerator
  keys are on by default), the ⌘P path of `modes.commandP`.

**Measured headless** (2026-10-15; Intel i5-8365U, 16 GB, Windows 11 Pro
26200; Edge 155.0.4283.45 headless — the same Chromium build as this PC's
WebView2 Runtime; no Chrome is installed here). The mac's own browser checks
were run unchanged against a native build of the verify fixtures
(`preview.ps1 --build-only` of a scratch course holding verify.sh's
"Printable Fixture" and "Plain Long Page", served from the built `public\`
over HTTP), with the runtime's Node 20.18.1 `--experimental-websocket` for
the WebSocket they expect from Node 22, and poppler 24.08.0 for Windows
(oschwartz10612/poppler-windows, in a scratch folder) for the PDF reading.
This is the mac's own method for its F7–F9 numbers (headless Chromium,
`Page.printToPDF`):

- **`browser-checks/print_handout.mjs`: OK.** Every check the mac runs —
  the print layout ran every time (never the fallback), every piece laid out
  (212/212 questions-only, 23/23 answers-only, 235/235 both), every word,
  answer and code line with its own number on paper, Latin Modern in the
  PDF's fonts, the Curriculum connection nowhere, the menu printing nothing
  until a way is chosen, in the contract's order, the paper remembered.
  Pages: questions only **12** portrait / **14** landscape; answers only **1**
  / **2**; both **13** / **16**. ⌘P: letter, 612 × 792 portrait and 792 × 612
  landscape, the Curriculum connection off paper, no code line number wrong.
- **#501, `browser-checks/print_plain_page.mjs`: OK, light and dark** (dark
  by the same script with `prefers-color-scheme: dark`). Plain Long Page, a
  1512 × 900 window: **4** pages portrait, **5** landscape; 40 of 40
  paragraph sentinels INKED, 0 with no ink, 0 words past the paper's edge, 0
  sidebar lines on paper (of the 6 the screen shows), 0 paragraphs broken.
  Display scale does not enter: a PDF printed by the browser is laid out at
  the paper's CSS width, not the screen's.
- **`printPdf: "WORKSHEET 3.PDF"`** against `Media\Worksheet 3.pdf`
  (`printPdfCases` "spelled in other capitals"): the built page links
  `../Media/Worksheet-3.pdf` — the FOLDER's spelling, as Quartz slugs it —
  and the build reported no `printPdfNotFound`.

**Measured on an unlocked desktop** (2026-10-15, the same PC: Intel
i5-8365U, 16 GB, Windows 11 Pro 26200, WebView2 Runtime and Edge
155.0.4283.45, one 1920 × 1080 screen at 150%; the real x64 Debug app on a
scratch working folder holding the print set's MPM2D, its pane driven over
WebView2's own debugging port, `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`):

- **Ctrl+P in the pane** opens WebView2's own print window INSIDE the pane
  (Chromium's print preview, "Microsoft Print to PDF" by default) on
  *Similar Triangles Practice*: **2 sheets**, the ⌘P path of
  `modes.commandP` — Name and Date top right, "Similar Triangles Practice ·
  MPM2D" bottom left, "Page 1 of 2" bottom right, the answers folded.
  `beforeprint` fires when it opens and `afterprint` when it is cancelled.
  At this window size the print window does not fit the pane: Copies,
  Layout and Pages are reached by scrolling inside it.
- **`window.print()` in the pane BLOCKS** the page's script until the print
  window closes (4.8 s, the time it was left open), with `beforeprint` and
  `afterprint` both fired before it returns.
- **The hidden frame prints there too.** With the injected
  `window.webkit` taken away (so `print.inline.ts` takes its own path),
  Print ▸ Questions only laid the handout out in its frame and WebView2's
  print window showed it: **1 sheet**, the handout's corners (Name, Date;
  "Similar Triangles Practice · MPM2D", "Page 1 of 1"), the triangles drawn.
  `frame.contentWindow.print()` blocked the page (a probe queued behind it
  answered only after Cancel, 29.4 s after the click), `afterprint` fired,
  and the frame was removed. Differences from the browser's: the math was
  drawn in the page's colours in the pane's preview where the browser's is
  black, and the print window is cramped inside the pane.
- **The hand-over survives ShellExecute.** Print ▸ Questions only in the
  pane wrote `preview page opened in the web browser — to print it questions
  only (Exercises/Similar-Triangles-Practice)` on the trail and opened the
  teacher's default browser (Edge) on `127.0.0.1:8081`, which went STRAIGHT
  to its print window: **1 sheet**, the Latin Modern handout, Name and Date,
  the triangle diagram. The address bar then read the page without
  `#plantoir-print=…` — the page's own `history.replaceState` takes the
  fragment off once read (`print.inline.ts`), which is itself the proof it
  arrived. Chrome is not installed here and was not measured.
- **A real mouse click on a `target="_blank"` link in the pane** is handed
  over too (trail: `a link to another page of the site (the front page)`,
  an Edge window on the page). The UI test invokes the link through UI
  Automation instead, because its harness's mouse click missed it on this
  screen (`PrintablePagesUiTests.cs`); the app's path is the same.
- **Not done: the two browser checks in a HEADED Edge.** Both read paper
  through `Page.printToPDF`, which Chromium offers headless only; the
  printing a teacher sees in a headed browser is what the two hand-over
  measurements above looked at by eye.

**What it means for the design (for the director, not decided here):**
WebView2 COULD print the handout itself — the frame path works in the pane,
blocking and `afterprint` included — so the hand-over to the browser is not
forced by the engine, as it is by WebKit on the mac. What the hand-over buys
on Windows is the teacher's own browser: its full-size print window rather
than one squeezed into the pane, black math, and the same behaviour as the
mac. Dropping it would be the plan's option (ii) in reverse (no shim on
Windows) and was NOT done.

The four UI tests owed from batch 5B ran on this desktop on 2026-10-15 and
pass after four fixes to the tests and one to the app (the corner sketch's
ids, which sat on a Border that UI Automation never sees): see
`PrintablePagesUiTests.cs` for what each found.

Tests: `PrintablePagesTests` (the getters, the corners cases, the 13
printing words, the settings-saved clause), `AgentGuidanceTests` (the ten
`rootFileCases` with a second pass each, the three `addCases`, the failure
line and a path-free notice, the skills, Not Now, the hook — and, by skill,
`TheGraphsSkillIsWrittenAndBothRootFilesNameIt`,
`TheQuizzesSkillIsWrittenAndBothRootFilesNameIt` (#571) and
`ThePageAuthoringSkillIsWrittenAndBothRootFilesRouteToItFirst` (#600), each
reading its skill's name from `shared-rules.json`; the runnable-code skill
has no Windows test of its own),
`PreviewBrowserHandoffTests` (modes and papers against the contract, the
message, the trail words, a link's destination never on the trail, the
shim's shape against `print.inline.ts`).

## The sidebar's page dot on Windows (#515, #546)

The dot before each page row inside an open folder of "Navigate this site"
is one stylesheet in `support/quartz` (`06-quartz-customizations.md` → "H.
The sidebar's page marker"); Windows inherits it with the toolchain, no C#
and no contract key. What #546 owed is that it was confirmed on a native
build, in the app's own pane, and under a REAL contrast theme, which the mac
can only emulate.

**Measured 2026-10-16** (Intel i5-8365U, 16 GB, Windows 11 Pro 26200, one
1920 × 1080 screen at 150%, Edge and WebView2 Runtime 155.0.4283.60, the
runtime's Node 20.18.1):

- **The mac's check, unchanged, on a native build.** A scratch working folder
  (`print_set_windows.mirror_toolchain` from this tree, verify.sh's own EXC2O
  copied from `support/example_course`), with verify.sh's four planted files
  written byte for byte (`Discussions/Marker Fixture Long.md`, `Marker
  Fixture Word.md`, `Discussions/Tasks/index.md` and `Marker Fixture Inner
  Page.md`) **plus its `Plain Long Page.md`**: the check needs one page at the
  TOP level of the sidebar ("no page at the top level … the check would prove
  nothing"), EXC2O's own top-level pages are not in the explorer, and in
  verify.sh that page comes from the #501 fixture. `preview.ps1 EXC2O 1
  --build-only --non-interactive` with `PLANTOIR_RUNTIME` set; the built
  `index.css` carries the forced-colours rule (`CanvasText`, one match);
  `public\` served by `python -m http.server` on 127.0.0.1; then
  `node --experimental-websocket browser-checks/sidebar_page_marker.mjs
  "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
  http://127.0.0.1:<port>/Discussions/Marker-Fixture-Long.html
  http://127.0.0.1:<port>/Discussions/index.html Discussions Tasks "Marker
  Fixture Page With A Title Long Enough To Wrap Onto A Second Line"`, verbatim:
  **`OK: light 5.63:1, dark 9.45:1, forced colours 10.41:1`** — the mac's
  forest-moss figures to the hundredth (7 pages marked, 11 folders bare, the
  long title on 3 lines with every line at 12.8 px, the dot at 0).
- **The app's own preview pane.** The x64 Debug build with `--state-dir` on
  that folder, Preview pressed on EXC2O Section 1, the pane read over
  WebView2's debugging port (`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=
  --remote-debugging-port=…`) and photographed. Dark (the system's mode) and
  then light: a dot on every page row of the open Discussions folder and of
  Tasks inside it, none on a folder row; the three-line long title and the
  too-wide "Electroencephalographically…" title both hang, every line
  starting under the first letter; the current page in Quartz's highlight
  colour (rgb(184, 196, 128) light, rgb(210, 221, 158) dark) and, hovered
  (by Chromium input over the debugging port), "Energy Source Debate" took
  the hover colour while its dot kept `--dark`. Two things about the pane at
  this screen size, neither the dot's: at the 900-epx window the pane is
  Quartz's narrow layout (the sidebar behind the menu button), and on a
  maximised window the explorer had been left collapsed, and its folders
  closed, by the earlier narrow visit, so "Navigate this site" had to be
  opened by hand. The photographs were taken with the pane zoomed to 75%
  (Ctrl+−), to fit the folder on a 1080-px screen.
- **High Contrast, the real theme.** Before: `SPI_GETHIGHCONTRAST` flags 126
  (off), `CurrentTheme` `…\Themes\Custom.theme`, AppsUseLightTheme 0,
  SystemUsesLightTheme 0. `SPI_SETHIGHCONTRAST` with `HCF_HIGHCONTRASTON`
  (not elevated) turned on **High Contrast Black** (`hcblack.theme`; it also
  set AppsUseLightTheme to 1). In the still-running app's pane and in a
  headed Edge window on the served build, `matchMedia('(forced-colors:
  active)')` was **true** in both; every page dot (7 of 7 in Edge, the
  nested Tasks page included) computed to **rgb(255, 255, 255)**, CanvasText,
  at the stylesheet's .75 opacity, on Canvas **rgb(32, 32, 32)**: (199, 199,
  199) on (32, 32, 32), **9.64:1**. Seen: a light grey dot on every page row,
  none on folder rows, the long titles hanging, in both. (Edge's window
  photographs blank under the theme, so its picture was taken by Chromium's
  own `Page.captureScreenshot`; the pane photographs normally.) Turned off
  with flags 126: flags, `CurrentTheme`, AppsUseLightTheme and
  SystemUsesLightTheme all read back as before. One residue: Windows now
  remembers "High Contrast Black" as the scheme the NEXT time contrast is
  turned on (`lpszDefaultScheme` read "" before).

The emulated figure (10.41:1, black on white) and the real one (9.64:1, the
dot's .75 opacity over Black's dark Canvas) differ because the emulation's
Canvas is white; both clear 3:1 by a wide margin.

## What this page does not cover

Deliberately, so there is one home for each and not two that drift. The macOS
page explains several of these for that platform; the Windows equivalents live
in [`windows-app/PROGRESS.md`](../windows-app/PROGRESS.md), which is maintained
as work happens:

- **The embedded preview** — WebView2, and the `127.0.0.1` question that was
  measured and found to be a no-op here. (How its navigations are told apart
  for Preview at Last Viewed IS here: "Preview at Last Viewed on Windows".)
- **The assistant's own window**, the model running natively with Vulkan, and
  the OUTSIDE doors: `ClaudeCodeLauncher` writes an MCP configuration and starts
  `claude` with `--strict-mcp-config`, so a teacher's own servers are neither
  used nor disturbed. There are TWO of those doors — Revise With ▸ Claude… and
  Codex… (on Windows since #210, 2026-09-30; inside the Revise With ▸ submenu
  on every row since #491, where they were "Revise with Claude…" and "Revise
  with Codex…" at the top level) — both described as data in
  `contracts/app-rules.json` → `outsideAgents`, read here by
  `CodexLauncherTests` and, for the menu titles, `ContractTests`. See
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
  mechanics that match the mac (bundle 4)" above. #467 (2026-10-08) found two
  bugs that guard had from its first day. Its scheduled half never matched a
  wrapper set since #309, because the name had no folder id. And a course with
  a space never matched, because callers quote it. Both are fixed in the
  shared block below; see 03 → "A section being deployed".
- **A deploy refuses while that section is still being deployed (#467 / mac
  #439).**
  - **The launcher.** `deploy.ps1`, and `preview.ps1 --build-only`, refuse
    before anything changes while the section's scheduled wrapper is running
    in this folder, or another `deploy.ps1` of it is. The block holding this
    is identical in both launchers, with #386's reader moved into it (03 →
    "A section still being deployed is not deployed again").
  - **The app.** The window lifts the launcher's line
    (`FailureExplainer.SectionDeployRefusalOf`). The window's Deploy asks
    `MultiDestinationDeployRunner.AnswerWhenTheBuildDidNotFinish` before
    `Result`. So a refused build leg says `DeployRefusedWhileALaterDeployWorks`
    or `DeployRefusedWhileItsSectionDeploys`, and an ordinary broken build
    now says `CouldNotBuildBeforeDeploying` instead of "did not finish" (mac
    parity: that key existed and was never called). `AssistWorkspace` (in
    `plantoir-mcp`) says the refusal for a refused build leg or for
    all-legs-refused, and keeps its own "The build failed…" message for an
    ordinary failure, because `CouldNotBuildBeforeDeploying` points at a
    window that process does not have.
  - **The other three answers that build (#471, 2026-10-08).** An outside
    assistant's `rebuild_preview`, `publish_pages` (a page or a whole unit)
    and `unpublish_pages` (a whole unit) rebuild with the same
    `--build-only` leg, so they meet the same refusal.
    `AssistWorkspace.RebuildPreview`, `Apply` and `ApplyWholeUnit` said what
    was already done, then the launcher's own line, lifted as the window lifts
    it ("ICS4U section 2 is already being deployed, so it cannot be built until
    that has finished."). Not `DeployRefusedWhileItsSectionDeploys`, which says
    the section "was not deployed again" — false of a rebuild. The lifted line
    is contract data already, and its build flavour exists because a rebuild
    runs that leg. Pinned by `shared-rules.json` →
    `deployWhileItsSectionDeploys.refusedBuildAnswers`, run here by
    `RefusedBuildAnswersTests` through the real `PlantoirTools`. (Since #481,
    below, the line arrives inside `wording.previewDidNotBuildBecause`.)
    - **The cross.** `plantoir-mcp`'s `LauncherRunner` reads the launcher
      without naming an encoding, so the cross arrives as `?` or as three
      characters of mojibake. Detection never cared (the markers are ASCII);
      since these answers SAY the sentence, `SectionDeployRefusalOf` now takes
      off everything before the course code's first letter or digit. The
      runner's encoding was deliberately left alone in this piece.
    - **What was left as it was on 2026-10-08, and closed on 2026-10-15
      (batch 1 of the catch-up to 1.7.1).** Three gaps were recorded here, all
      now closed:
      - **An ordinary build failure (#481).** `Apply` and `ApplyWholeUnit`
        ended it with `WhereTheOutputIs`, a pointer at a window plantoir-mcp
        does not have, and `RebuildPreview` appended `build.Message` whole —
        "(The launcher exited with code 1.)" and "Last output:" handed to an
        outside assistant. The mac added the two headless keys the same day,
        and Windows now declares and says them: `PreviewDidNotBuildHere`
        (which replaced `RefusedWhileItsSectionDeploys`) says
        `wording.previewDidNotBuildBecause` with `FailureExplainer.Explanation`'s
        reason when there is one — the #471 refusal among them, reached through
        `SectionDeployRefusalOf` — and
        `wording.previewDidNotBuildForACallerWithNoWindow` otherwise. A
        rebuild's answer is "Nothing was changed. " and that sentence; a page or
        unit's is what was already done and that sentence. `WhereTheOutputIs`
        is said nowhere in `AssistWorkspace` any more. Accepted, as on the mac:
        `Explanation` can lift a sentence written for a deploy ("… then deploy
        again") into a preview build's answer. Rejected: a Windows-only
        sentence, because a wording key is the mac's to add and it had.
        Tests: `AssistWorkspaceTests.ARebuildThatFailsSaysOneCleanSentence`,
        `ARebuildThatFailsForAReasonSaysTheReason`,
        `AWholeUnitWhoseBuildFailsSaysOneCleanSentence`, and the two older
        tests whose expectations moved.
      - **Exit 3 in `Apply` and `ApplyWholeUnit` (#478).** A question was read
        as a failed build there, while `RebuildPreview` and `Deploy` said
        `PreviewBuildNeedsAnAnswer`/`DeployNeedsAnAnswer`. Both now check
        `NeededAnAnswer` first and say what was done, then
        `PreviewBuildNeedsAnAnswer` (`APublishOrHideWhoseRebuildStopsForAQuestionSaysSo`).
        The mac's own runner had the matching gap one level up — its
        `carryOut` counted the headless failure sentences as "the preview was
        left as it was" but not the question — closed by #522 (2026-10-16):
        the mac now names the preview only when it restarted it in its
        window (`documentation/10-local-ai-assistant.md`). Windows has no
        such sentence, so owes nothing.
      - **Unpublishing single PAGES never rebuilt (#479).** `Apply` returned
        before the build whenever the plan hid pages (`if (!plan.Publishes)`).
        Nothing chose that: since the first commit (b3b7fc040) `Apply` tied
        "build the preview" to "the plan publishes", and the mac rebuilds
        after a hide. The return is gone, so a hide takes the publish's path —
        the window's `preview: false` return (its own visible rebuild covers
        it), `ClaimTheRebuildAfterAWrite`, then `--build-only` — and the
        seventh `refusedBuildAnswers` case runs green with no ledger entry
        (`HidingAPageRebuildsThePreviewAndStopsThere`,
        `HidingWithPreviewFalseBuildsNothing`). Left alone on purpose: a hide
        that changes NOTHING still builds nothing, while a publish that changes
        nothing does (the `ChangesNothing && !Publishes` return); and a hide is
        still not refused up front while Plantoir is building
        (`RefuseIfPlantoirIsBuilding` stays publish-only) — its pages are
        written and only the rebuild is declined, with its note. No new trail
        event: a hide's rebuild meets the existing "build declined, course busy
        elsewhere" and "outside assistant worked while a preview was open"
        lines, whose `carries` already say "a change it made".
    - **No new trail event (rule 5).** The launcher already writes "build
      declined, course busy elsewhere" for the refusal (`launcherLines`).
  - **The kind.** `ScheduledPublishOutcome.Kind.EarlierDeployStillWorking` is
    read and shown, never written.
  - **What is NOT built: the mac's thirty-minute wait.** A re-set leaves the
    working run alone (`ClearIfStillMine`), so there is no leftover run.
  - **The residual.** A run ended mid-deploy by something other than a re-set
    — Task Manager, or the task's `PT72H` limit — leaves its wrapper
    `powershell.exe` working, with leases that now read as stale. The guard
    then refuses other deploys of that section, which is correct. But a later
    run of the section does not wait: its leases look free, its build leg is
    refused, and it is recorded as `buildDidNotFinish`. Rare enough to record
    rather than build.
  - **Measured: a re-set whose moment arrived while the earlier run still
    worked never ran** (Task Scheduler `IgnoreNew`). Fixed by
    [#470](https://github.com/russellgordon/plantoir/issues/470) on
    2026-10-15: the task's policy is `Queue`, the queued start runs 2.1 s
    after the first ends with the newest definition, and the run's own
    checks decide whether it still deploys. The numbers for both are in 07 →
    "Set again while the run works (#409)".
  - **Known limits.** A deploy run inside another process (typed at a prompt,
    or `-Command`) is not seen, and neither is an elevated one; the
    self-relaunch that would see the first was rejected (03).
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
| Downloads checked against a pinned SHA-256 | none | every helper, both kinds of Mac, and the disk | since 2026-10-01 (#356): the Node zip, the Python embeddable zip and the emoji font in `fetch-runtime.ps1` (a build-time fetch, not on a teacher's machine), and since 2026-10-15 (#503) the Paged.js and function-plot tarballs and the Debian Latin Modern package, with the files kept from each checked again; `get-pip.py` deliberately not (below) |
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
- **Updates** (#204, #337): **switched on with v1.4.2, 2026-10-03** — what
  was built, measured and rejected is `11-release-strategy.md` → the Windows
  updater, and the release side is `RELEASING.md` → "The update feed
  (Windows)". What follows is the brief it was built from, kept for its
  reasoning. **NetSparkleUpdater**, not WinSparkle — corrected
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
  added to `activityTrail.mustRecord`. The app gathers the notes of every newer
  feed item itself (`AppUpdates.NotesFor`, #428: NetSparkle hands it the newer
  items but, with no UI of its own here, shows none), so a skipped release's
  warning is not lost; each Windows item carries only its own. (This said
  NetSparkle gathered them until 2026-10-04; with no UI factory it does not.) The mac's reasoning: [`09-mac-app.md`](09-mac-app.md) →
  "Updating itself". (Earlier drafts of this line said WinSparkle with
  `site/appcast-windows.xml`, and before that one shared appcast.) Since
  v1.4.4: an update marked important offers Install and Reopen alone and is
  offered again even when skipped (#453), and the daily check starts once the
  first window is up and never counts an offer nobody saw as an answer
  (#465). Both are in `11-release-strategy.md` → "Updating itself on Windows".

  **The quit an install asks for is carried to the UI thread (#632, v1.8.6).**
  Seen on the 1.7.2 → 1.8.5 proof: Install and Reopen on the DAILY check's
  offer started the installer and left the old window up, so the installer
  met a running `Plantoir.exe` under `/NOCLOSEAPPLICATIONS` and gave up having
  changed nothing; the same answer from File ▸ Check for Updates… installed.
  What was OBSERVED: the quit runs on the thread that STARTED the check. The
  daily check starts from a `System.Threading.Timer`, so `InstallWhenFreeAsync`
  → `UpdatePrompts.QuitForInstall` → `App.QuitForUpdate` → `QuitTime` →
  `Current.Exit()` ran on a pool thread; Check for Updates… starts on the UI
  thread, and its quit ran there. The likely mechanism is the download's async
  continuation (`await InitAndBeginDownload`, then `DownloadFinished`)
  resuming on its caller's context — inferred, not traced: the IL shows
  NetSparkle reading its stored SynchronizationContext only in its worker
  loop, so "it raises `DownloadFinished` through the builder's context" is
  NOT the reason, and an earlier draft of this paragraph said it was.
  `Current.Exit()` off the UI thread **returns having done nothing** — no
  exception, no `MainWindow.Closed`. The red run's startup.log, 2026-10-22:

  ```
  QuitForUpdate on thread 5, UI thread: no
  QuitTime called
  QuitTime: calling Current.Exit
  Current.Exit returned
  ```

  Whether a File ▸ Check for Updates… made in the SAME launch, after a
  daily-check quit that did nothing, would install is unmeasured — the 1.8.5
  proof's retry came after the window was closed by hand. Worth knowing
  besides: `QuitTime` had already written the trail's
  `Plantoir closed — to install a new version` and set
  `WorkspaceViewModel.IsTerminating` before the `Exit()` that did nothing, so
  the window left up was half torn down, and the trail said it had closed.

  The fix is in ONE place, `App.QuitForUpdate`: on the UI thread it calls
  `QuitTime()` directly, as always; from anywhere else it hands it to the UI
  thread's `DispatcherQueue` (the one `OnLaunched` already obtains), and says
  so in startup.log (`UI thread: no, so the quit is handed to it`); a refused
  `TryEnqueue` is logged. Rejected: building the engine or starting the timer
  on the UI thread (fixes this route and leaves the next off-thread caller
  broken), guarding `QuitTime` for every caller (wider than the fault; its
  other callers are UI-thread handlers), and fixing it in `UpdatePrompts`
  (the call into `Exit()` is the one place every route goes through).

  **The test**: `UpdateInstallQuitUiTests` (two `[UiFact]`s — the daily
  check's offer, and Check for Updates… as the control) serves a feed signed
  with a throwaway Ed25519 key from localhost and an "installer" that is a
  `.cmd` writing a marker, so nothing installs and nothing reopens. A Debug
  build has no updater (`AppUpdates.FeedFor(developmentBuild: true)` is null)
  and is never per-user from `bin\`, so the Debug build alone accepts
  `--update-feed-for-tests <url>`, `--update-key-for-tests <base64>` and
  `--update-first-look-for-tests <seconds>` (`AppUpdater.FirstLook`, default
  `FirstRetry`, one minute); a Release build compiles them out. Windows has
  no `PLANTOIR_UPDATE_FEED` at all; the mac's `PLANTOIR_UPDATE_FEED_URL` is
  a build setting written into its Info.plist, not an environment variable.
  Measured on the Lenovo 20QES70500 (i5-8365U), 2026-10-22, x64 Debug: before
  the fix the daily path started the installer 0.7 s after the click and the
  old process was STILL RUNNING 30 s later, while the menu path was gone in
  1.0 s; after it, the daily path is gone 0.9 s after the click and the menu
  path 0.6 s.
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
the Settings dialog's (`AssistantSettingsDialog`, since #491 the Assistant
section of the Settings window, `AssistantSettingsPane`)
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
in `AssistantSettingsDialog.cs` (now `AssistantSettingsPane.cs`, and the
Deploying section's `DeployingSettingsPane.cs` keeps the same gutter), 20px being enough to clear the thumb's hit
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

### The chrome is shared, and that was a trade — reversed by #456

Until 2026-10-08 all three fields in the wizard's Basics section (course
code, course name, timetable section numbers) wore one `WizardFieldChrome`
modifier: an imitation of AppKit's bezel drawn at the native 24pt, measured
against the real control rather than eyeballed, because SwiftUI's
`.roundedBorder` is 26pt and cannot be forced to 24. **#456 reversed that on
purpose** (Russell, 2026-10-07): every other field in Plantoir wears the real
`.roundedBorder` bezel since #374, so the standard is the SwiftUI field, and
the drawn chrome — and the searchable picker's — is deleted; the four fields
are the same height as every other by construction, and text long enough to
reach the course-code chevron runs under it, the accepted trade.

**For this side, the rule is the one this section always gave: keep WinUI's
own text box.** Match whatever ITS standard height is, with every field in
the wizard and in Copy a Page the same height — never 24pt, which this
section used to tell you to match. The `windows` issue from #456 says so.

**Checked on Windows for #483 (2026-10-15): nothing was forced, and the
fields are WinUI's own 32.** No single-line field in the wizard or Copy a Page
sets a `Height` (`NewCourseDialog.cs`, `CopyAPageDialog.cs`, `FormBuilders.cs`
— the one `MinHeight` is the multi-line footer box, 60); the course code is a
real `AutoSuggestBox`, the rest plain `TextBox`es and `ComboBox`es at their
theme height. Measured once through UI Automation's `BoundingRectangle` with
the real app (`--state-dir`, the wizard scrolled through by its own scroll
pattern so each field was on screen; Intel i5-8365U, Windows 11 Pro 26200,
display at 144 dpi, values in the 96-dpi units the test process is given —
the deploy picker's `MinWidth` of 300 reads 300): **the wizard's Course code
32, Course name 32, Timetable section numbers 33, Deploy to 32** (the 33 and
one 31 among ten samples of the picker are rounding of a 150% scale). **Copy a
Page**'s three fields carry their label as a `Header`, so UI Automation's box
includes it: Page 59, Copy into 64, Folder 64, each label 19 high — the edit
parts are the same theme control; the 5-point difference is the header's
spacing in a `ComboBox` against an `AutoSuggestBox`'s, not the field. Nothing
to change; no permanent test was added (a one-off measurement, per the
batch's plan review).

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
  as the SDK's own binder does — `AssistToolRunner.Run` (reached through
  `AssistAgent.RunTool` since #489) sets `preview` on tools
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

**Since #440 (v1.4.4) `unit` and `days` are card-only too**, on `add_next_class`
and `plan_add_next_class` alike: the router had been shown them since the tool
shipped and sent `unit: "next"` — START A NEW UNIT — on 50 of 50 plain "add the
next class" calls (v1.4.3 bundle A, i5-8365U / UHD 620). The server still
DECLARES both, for the same reason it declares `duplicate`: the binder drops an
undeclared key, and the cards ("Start a new unit", "Add three days to Unit 2")
send them. What the router may not send it also may not keep — settler S2
strips `unit` and `days` from every `add_next_class` the MODEL sends
(`AssistAgent.WithoutCardOnlyArguments`), and settler S3 points a sentence
about units or counts at the phrasings that do it (doc 10, "#440"). The local
`add_next_class` now shows course and section only, the mac's shape (the narrowed `add_next_class` equals the contract's local shape exactly; the departures already recorded on four other local tools (`preview` on `publish_class_on`, `publish_pages` and `unpublish_pages`; `scope` and `revise` on `read_remembered_timetable`) stand, so this is a claim about this tool, not the whole surface);
`NextClassUnitsTests.TheLocalModelSeesOnlyCourseAndSection` narrows the REAL
served schema and compares it with the contract's.

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
from a cloud session on Linux (see `windows-app/PROGRESS.md` → "Work done
from a cloud (Linux) session — 2026-09-27" for what such a session can and
cannot build).
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
  restored on a mac, whose `SectionTimetable` reads it just as invariantly.
  The mac adopted the same window on 2026-10-03 (#377,
  `SectionTimetableStore.firstDateThatCannotBeAClassDate`, asked by its
  reader and its writer, run against the eight cases by
  `FileFormatsContractTests.testARememberedTimetableIsBelievedOnlyInsideTheWindow`). The floor is 2000, not
  `ArchiveStamp`'s 2025, because a teacher may keep last year's timetable;
  it is still centuries clear of every wrong reading (2569, 1483, 1448). The
  ceiling is three years, not two days, because future class dates are the
  point of the file. **It leaves a trail line** — `remembered timetable set
  aside` in `shared-rules.json` → `activityTrail.mustRecord`, carrying the
  date it refused — written by the reader, once per read of such a file
  until the teacher answers and the file is replaced. It was
  `appliesOn: ["windows"]` until 2026-10-03, because only this app ever
  wrote such a file; the mac then adopted the line with the window (#377),
  since a file that arrives through a restore or a shared folder is just as
  invisible without it, and the `appliesOn` was dropped.

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
unmerged Windows branch from 2026-09-19 that `WINDOWS-PARITY.md` (deleted
2026-10-04) Phase 5 step 1 said to take up as it stands: the model's dateline (`AssistAgent`
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
`KeyboardAccelerator` declared on `MainWindow.xaml`'s `Root` grid (as it was
when this was written; since #488 every key is on its menu item — see
"Accelerators under a dialog (#191)" and "Menus, the Section menu's functions
and #475 on Windows"); WinUI
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
`FolderActions.QuitObsidianAndWait` polls for up to about eight seconds (since
#581: up to 5 s for Obsidian's windows, then up to 3 s for its processes; it
was five, 50 × 100 ms) with nothing on screen, so the File menu and Ctrl+O are both fully live — and
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
failure it exists to prevent. It also pins the three write sites and the single
registration write, since deleting a capture would otherwise leave every stop a
silent no-op wearing the shape of the fix working. (There were four until the
marketing-shot harness's `StagePreviewForCapture`, which set `_previewUrl` and
so made `hadPreview` true, went with the old `--capture-marketing-shots` mode
when the pictures moved to `--stage-scene` (#380); the test expects three.)

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

**Which folder is protected as the class folder (#431, Russell 2026-10-03:
Windows matches the mac).** With no `class_folder` recorded, only the literal
"All Classes" is protected from removal; with one recorded, that name as well
(`ClassFolderRule.ProtectedName`, the mac's
`ClassFolder.isTheAllClassesFolder(_:configured:)`). Until v1.4.3 Windows
protected `ClassFolderRule.Name`'s GUESS — the first folder whose name says
"class", else the first per-section folder — so the same course file answered
`classFolderBlocked` for "Handouts" here and reached the marks floor on the mac,
and `MarksFloorContractTests` nulled the resolved class folder for F13/F14 to
get round it. Both are gone; the floor cases run through the real resolution.
The New Course wizard matches the mac's too: the literal, plus a club's folder
by the name its row gives (the guess never found "All Meetings").

What did NOT change, on purpose: the guess still decides WHERE a new class page
is written (`class-planning.json → classFolder.naming`, shared with the mac and
`build_site.py`), and what the wizard RECORDS as `class_folder`. Writing needs
an answer for every course; protecting needs certainty, and a guess is not.
Measured before the change (#431's own ask): of the 39 example payloads and 50
skeleton families, NONE records a class folder and none has a first
per-section folder other than "All Classes" (every skeleton lists exactly
`["All Classes"]`), so no course made from them changes. The courses that do
are ones with no `class_folder` key — made before the key existed, or
hand-edited — whose per-section list's guess is not "All Classes": such a
course can now remove that folder, as it always could on a Mac. Rejected:
keeping the guess and asking the mac to adopt it (a first-folder guess would
protect "Handouts" for no reason the teacher can see, and the mac never shipped
it).

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
scan until its schedule is set again. `PLANTOIR_MY_PROGRESS:` (#599) rides the
same three places — the console reader, the record reader and the wrapper's
scan — and a wrapper written before #599 likewise misses it until the
schedule is set again ("My Progress: the trail line and the two readers
(#599)" below).

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
and `NamedGapLedger` has been empty since bundle 9, but for a few hours on
2026-10-16 when mac #524's sixteen plan-table sentences were held against #548
until #548 landed them.)

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
On a reference course's SECTION, the − button, the Delete key and the
section's menu offer no removal at all (− is greyed, Delete does nothing, the
menu has no Remove Section…); the course row's Remove Course… removes it all.
`ArchiveAndRemoveSection` still refuses with `staysAsItIs` for any caller that
skips that rule. (Until batch 3B the footer's Remove there silently removed the
whole course; see "Delete and the − button run the menu's removal (items 5–6)"
under "The HIG sweep, screen by screen, on Windows (#491 part B)".)
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
  `TaskDefinitionTests.TheRegisteredTaskKeepsTheFourSettingsAndCarriesItsToken`
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
`zipNames` format). **Since #489 (2B) the READER takes `-N`** (N ≥ 2): the
mac began writing `<time>-2` for a second copy in one second and reading it,
so the reason above expired in that direction, and a copy the mac made must
be listed and counted here. The WRITER still waits — see "The Section menu's
functions". `ContractTests.CourseManagement_ZipNames` also takes each
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
`courses\<CODE>\section<n>` existing. Unproven on a real click.

**Until #448 (2026-10-04) it never posted at all.** `Program.Main` ran
`ScheduledRun.Execute` and THEN the toast step, which read the job file —
and a run that deploys, or stands down, ends with `ClearIfStillMine` →
`TaskScheduling.Cancel`, which deletes the task AND its job file. The toast
step found no job and returned without a word, so no toast and no trail line,
on every scheduled run since #324. Measured on two real runs (the installed
1.4.2 and a Debug build; i5-8365U, UHD 620, Windows 11 Pro 26200): record
`succeeded`, folder written, task gone, nothing in Notification Center, no
`scheduled publish notification` line. The unit tests had all passed, because
none of them ran the clearing before the toast.

The fix: `ScheduledRunAnnouncement.RunAndAnnounce` reads the job BEFORE
`Execute`, then hands course, section and folder to `Announce`, which reads
the section's record, posts its sentence through an `IPoster`
(`ScheduledPublishNotifier.SystemToasts` in the app; a stand-in in tests) and
writes the contract's `trailSays` line — told, turned off
(`AppNotificationManager.Default.Setting` disabled for the app, the user or by
policy), or could not be sent (a post that throws or returns id 0). Which
endings announce: `Deployed` (the wrapper's record: succeeded, did not finish,
needed an answer) and `StoodDown`. `NoLongerStands` announces nothing — the
teacher cancelled or set it again, this run wrote no record, and the record
lying there is an older run's news — and nor does a record older than the run
(less two seconds), so a wrapper that wrote nothing never replays last week's
notice. A deploy set again while the run worked keeps the new task (the
"not mine any more" path) and still announces THIS run's record: what the
toast names was read before the run, so it never depends on which job file is
there afterwards. `ScheduledRunAnnouncementTests` plays
`notification.announcing` (the `allowed`/`notAllowed` rows, every kind) and
drives real runs through `FakeScheduler`, asserting the job file is gone
before it asserts the post; putting the old order back (reading the job after
`Execute`) turns them red. **Proved for real, 2026-10-04 11:49** (same PC):
a real Task Scheduler run of the fixed x64 Debug build (task action
`Plantoir.exe --run-scheduled-deploy "<task name>" --token …`, set through
the branch's own `plantoir-mcp.exe` with `PLANTOIR_APP_PATH` pointing at
that build) wrote its record, cleared its task, and posted: an entry with tag
`ICS4U-section1.<folder id>`, group `scheduled`, under the app identity whose
display name is "Plantoir" (`HKCU\Software\Classes\AppUserModelId\{GUID}`),
was in the notification database Notification Center reads
(`%LOCALAPPDATA%\Microsoft\Windows\Notifications\wpndatabase.db`), carrying
the record's own sentence, and the trail read `ICS4U/1 · told the teacher how
a scheduled publish went, with a notification`. **Rejected:** keeping the job file until the toast
is posted (moving the clearing out of `Execute`) — the clearing is what makes
the task one-shot and is guarded by the job's token; a second caller in charge
of it is a deploy that can recur.

**Dismissing the band takes the toast down (#464, v1.4.4).** The last of
#212's owed items. The band's Dismiss and its X both go through
`ScheduledRunAnnouncement.TeacherDismissed`: the record first, then
`IPoster.Withdraw(TagFor(section))`, which `SystemToasts` does with
`AppNotificationManager.RemoveByTagAndGroupAsync(tag, ToastGroup)`. The group
is one constant, used by both the post and the withdrawal. A failed withdrawal
goes to `startup.log` and never stops the dismissal. There is no trail line,
as on the mac (`teacherDismissed`). `ScheduledRunAnnouncementTests.TheContractsOnShowCases`
plays all four `notification.onShow` cases, the first Windows reader of them.
The app's own `Register()` and the poster's now share one process-wide flag,
so a withdrawal never registers twice in the app.

**Measured, because a stand-in cannot show it:** the toast is posted by a
DIFFERENT process (the scheduled run) from the one that withdraws it.
`Plantoir.UiTests/ScheduledToastWithdrawalUiTests` runs a job set thirty days
ago with the x64 Debug build, exactly as Task Scheduler would, so it stands
down as too late and posts. It then finds the toast in `wpndatabase.db`,
checks it is still there once the section is open, presses Dismiss, and finds
it gone. Passed twice on 2026-10-08 (i5-8365U, Windows 11 Pro 26200), the
toast filed under `{809579B5-…}`: one `HKCU\Software\Classes\AppUserModelId\{GUID}`
per executable path, so a run and the app of the same copy share an
identity. A toast posted by a DIFFERENT copy (the installed app against a
Debug tree) has another identity, and this copy cannot withdraw it; only a
developer meets that. **Rejected:** removing by tag alone (it would also take
a same-tag toast of another group); clearing the record from the toast's own
click; withdrawing when a later run clears the record (its own post already
replaces the toast by tag).

### Accelerators under a dialog (#191)

**Since #488 (2026-10-15) these keys are on MENU ITEMS, not the root Grid**:
Ctrl+O on File ▸ Open Working Folder…, Ctrl+N on New Window, Ctrl+Shift+R on
Reload Courses, F2 on Course ▸ Rename, and every new menu key besides — F1 on
Help ▸ Plantoir Help since #491, with its own `InlineData` in
`AcceleratorDialogGateTests`. (The sidebar's Delete key, #491 part B, is the
one key that is deliberately NOT on a menu item — there it would take Delete
from every text field — so the tree's `KeyDown` asks `DialogGate.Holds(root,
"Delete")` itself; `AcceleratorDialogGateTests.TheSidebarsDeleteKeyAsksTheDialogGateFirst`.) Each
item's key still asks `DialogGate.Holds(root, "<key>")` before it runs (in
`MainWindow.Invoke`), so the record and the test below are unchanged; what
changed is where WinUI looks for the key. Re-measured with the keys on items,
2026-10-15, verbatim: "Ctrl+Shift+R / F2 / Ctrl+N / Ctrl+O: not delivered
(the dialog kept it); control (no dialog): all four arrived at their
handlers" — and a probe measured the same for an item's Ctrl+Shift+D and a
root-scoped key ("Menus, the Section menu's functions and #475 on Windows",
above). `MenuGreysUnderADialogUiTests` adds Ctrl+Shift+D with the same
control. The history below is what was true of the root-scoped keys.

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
(the dialog kept it) / Ctrl+O: not delivered (the dialog kept it)". That
first reading had NO control — a key missing from the held list could have
meant only that the keystroke went to another window (fix-round review,
ruling W2). So since bundle 11's last round `DialogGate.Holds` records every
ARRIVAL in a `--state-dir` run (`accelerators-arrived.txt`, "<key>
passed|held"), and the test first presses the four keys with NO dialog up and
requires each to arrive (closing the rename dialog, the second window and the
folder picker they open). Measured 2026-10-01 22:28, verbatim:
"Ctrl+Shift+R / F2 / Ctrl+N / Ctrl+O: not delivered (the dialog kept it);
control (no dialog): all four arrived at their handlers". So keys from the
test DO reach the window's handlers, and under a ContentDialog the same four
do not, on this build; the guard is belt and braces, and costs nothing.

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
folder, squeezes the window the same way and measures the Done panel's five
parts — the phase, the folder sentence (given its own id for this), Show in
File Explorer, the render note and Show details — each an element with an
automation peer, a missing one FAILING the test (`%TEMP%\plantoir-214-donepanel.txt`).
Measured 2026-10-01 22:31 (bundle 11, last round), verbatim: "window 900x737;
taskPhaseLabel 33x20 (bottom 167); publishedFolderSentence 631x19 (bottom
209); publishedFolderButton 153x32 (bottom 247); publishedFolderRenderNote
631x32 (bottom 285); taskDetailsDisclosure 655x29 (bottom 328)" — all inside
the window at the narrowest width it allows. Why #214's own two methods do
not apply here: there is no splitter to drag (the sidebar is a fixed 230 px)
and WinUI does not measure a TextBlock at a proposed near-zero width; with a
900 px minimum window the detail column cannot get narrower than about
670 px. Height was not squeezed (737 of a 600 px minimum), and the lowest
part sits at 328 px. (Read since #542: these UI Automation numbers are epx,
not pixels. The test host is not DPI-aware, so it is handed rectangles
virtualised to 96 dpi; "900" was the 900 epx minimum, 1350 px at 150%.)

**Measured, 2026-10-01 13:51 (bundle 11, run 1, same PC), verbatim:**
"window 900x737; notice 631x157 (top 135 below the window's top)". The
resize to 500 px was NOT honoured: the window would go no narrower than 900,
so the squeeze a teacher can make is bounded there, and at that width the
notice is 157 px of a 737 px window, inside it. The test's own wait for the
width to reach 520 times out silently; it should say so if the window's
minimum ever drops (left as it is: the assertion that matters — the notice
stays inside the window — holds at the narrowest width a teacher can reach).
(Since #542 the wait is for the width to SETTLE, which it does at the 900 epx
minimum, rather than for a number it can never reach.)


## The pictures on plantoir.app: real windows, staged by the app (#380, #370)

Every Windows picture on plantoir.app is now ONE real window photographed
whole by Windows.Graphics.Capture (`website/shots/windowshot/`): the window's
own corners and alpha, nothing cropped, masked or drawn, and no shadow of its
own on a single-window shot — the page's stylesheet adds one. That is
Russell's rule for every picture (2026-09-27, repeated 2026-10-04: "Every
screenshot must be windows"), and it ruled out what this app used to do.

**What was rejected, and why.** `--capture-marketing-shots` rendered each
window's CONTENT with `RenderTargetBitmap` into a PNG: no title bar, no
window, square corners, and — for the assistant — the bubbles, the plan text
and its Approve and Cancel buttons were TextBlocks and Buttons typed by hand
into the transcript, words the app never says. `StagePreviewForCapture` laid a
picture of a site (or a hand-built imitation of one) where the preview goes,
with nothing serving it. Both are gone. Cropping a desktop capture to the
window's rectangle was rejected for the reason the mask once existed: it keeps
desktop pixels in the rounded corners.

**How a scene works.** `Plantoir.exe --stage-scene <scene> --theme
light|dark --folder <working folder> --ready-file <file> --state-dir <temp>`
(`Services/MarketingShotCapturer.cs`; the arguments are read by
`Plantoir.Core/Models/MarketingScene.cs`, tested in `MarketingSceneTests`).
The app opens the window through the same paths a teacher's clicks take —
`App.OpenWindow`, the sidebar selection, the New Course panel, the Copy a
Page and Get Ready for the Start of the Year sheets, the section's Schedule
a Deploy sheet, the Preview button — drives it to the state the caption
describes, and writes `staged`, or `refused: <why>`, to the ready file. A
refused scene is never photographed. The Python side photographs the one
window of that process and ends it, and everything still naming the folder
(a preview it built, its tools), and deletes any lease file left behind.

- **Real where it can be.** The preview, the progress (a real preview caught
  14 s in) and the two coverage maps are REAL previews built by the launchers
  (`SectionDetailView.ShowPreviewPageForCaptureAsync` shows a page of the
  preview the view is already serving, scrolled to an anchor and checked).
  The assistant is the real window with Plantoir's real tools: the promise
  card's "Unpublish Unit 2, Day 3" is matched in code
  (`AssistAgent.CardCommand`), so the plan and its Go and Cancel buttons are
  the app's own and no model has to be downloaded or started
  (`AssistWindow.StageForCapture`; a model that answers nothing stands in,
  and is never asked). The schedule's notification is NOT taken yet: two
  real scheduled deploys (the Debug build, then the installed 1.4.2) both
  succeeded and posted nothing, because `ScheduledRun.Execute`'s one-shot
  clearing (`TaskScheduling.Cancel`) deletes the job file before
  `ScheduledPublishNotifier.PostFor` reads it (fixed by #448 on its own
  branch). With that fix the toast appeared (2026-10-04 12:07), and it is
  still not a window Windows.Graphics.Capture can be given: EnumWindows found
  no new, visible or uncloaked window, FindWindowEx by
  `Windows.UI.Core.CoreWindow` and UI Automation's desktop root found no
  notification. Russell's ruling (2026-10-04): Windows' `schedule` picture is
  the sheet alone, with its own alt text (`shots.json` → `windowsAlt`).
- **Staged in one place only:** the hero's middle card is a deploy in
  progress, staged with `ScriptRunner.StageAsRunningForCapture`, because a
  real deploy would put a site online to take a photograph.
- **`--state-dir` on every run**, so no setting, window list or trail line of
  a teacher's is touched; and a fresh settings file has "asks before
  changing" ON, which is what makes the assistant show its plan rather than
  carry it out. (The scheduled deploy's own run is started by Task Scheduler
  without `--state-dir`, so its record and trail lines are written to the
  real state folder of the machine taking the pictures.)
- **The folders are made by the app.** `--stage-scene provision --courses
  "ICS3U:1, 2;ICS4U:1" --reference-copy ICS3U:2025` (both strings built from
  `website/shots/marketing/folders.json` by `demo_folders.provision_courses_argument`
  and `reference_copy_argument` since #459, never written in the script) sets a folder up and makes
  each course through the New Course panel (`AutoCreate`, after the code is
  filled in as typed, so the course gets the name a teacher is offered — the
  first folder made without that was called "Course Website"), then keeps a
  reference copy with Keep a Copy for Reference's own `ReferenceCopier`. The
  College Board scenes use the mac's ICS3U, ICS4U and ICS3U-2025, copied in
  (every picture's path bar shows `~/Desktop/Teaching`, as the mac's do: the
  scene folder's `courses` are swapped into it for the run and back after,
  `app_scenes_windows.ShownAsTeaching` — the folder itself could not be
  renamed while a File Explorer window had it open), because
  their College Board pages come from the Course and Exam Description through
  a macOS-only PDFKit helper (`website/shots/ced_statements.swift`).

**Traps met.** PowerShell 5.1's `Start-Process -ArgumentList` joins its array
with spaces and quotes nothing — "School Web Space" arrived as "School" and
the app set up a folder of that name; each argument now carries its own
quotes. The app must be started through ShellExecute, never with redirected
stdio (the leak `DrivenApp.cs` measured, which hangs course creation).
WinUI's system title bar does NOT follow dark mode on its own: in a dark
picture taken on 2026-10-04 the content is dark and the title bar light,
which is how the app looked to a teacher then, so the pictures show it (a
product question, not a capture one). Fixed on 2026-10-07 — see the next
section; `Dress` now re-syncs the caption after it sets a scene's theme, so
pictures taken after that carry a dark bar in the dark scenes.

**What printing does (`capture_windows.py --print-set`, the 1.7.1
catch-up).** The two print shots are of a PREVIEW, not a published site, so
they have a pass of their own (`website/shots/print_set_windows.py`): a
working folder made by the branch's own `setup.ps1`, a preview built by its
own `preview.ps1` with the bundled runtime, the page taken in an Edge `--app`
window like every class-site shot, and the handout printed by the page itself
in headless Edge (`handout_pdf.mjs` under the runtime's Node 20, which needs
`--experimental-websocket`). Three things met doing it, each measured on
2026-10-15: `setup_course.py`'s colour-scheme picker reads keys through
`msvcrt`, so answering `setup.ps1` through a PIPE hangs there for ever — it
is driven through `PtyDriver` instead, with `q` keeping the scheme the
written config names; Quartz scrolls the page about 300 px down on load, which
puts the Print button above the window, so the page is scrolled back to its
top before the shutter; and Windows.Graphics.Capture sends NO frame for a
window on a locked or disconnected session ("the window sent no frame in 3
seconds"), so the pictures need somebody's desktop even though the course,
the preview and the PDF do not. Text read-back is `windowshot --ocr`
(Windows.Media.Ocr, which does run locked), the counterpart of the mac's
`ocr.swift`: on the mac's own `print-*` pictures it reads every `expectText`
word. `website/SCREENSHOTS.md` → "Windows Capture" is the procedure.

## The title bar follows dark and light mode (ordered 2026-10-07, ships in Windows v1.4.4)

Russell's order: "The title bar should be in dark mode when the computer is in
dark mode." Neither window extends its content into the title bar, so the
caption is drawn by the system — and the system draws it LIGHT unless the
window says otherwise, whatever Windows' colour mode is. In dark mode the
content went dark under a near-white strip.

**What was done.** `Services/WindowTheme.cs` is the one place: `Apply(window)`
sets `AppWindow.TitleBar.PreferredTheme` (Windows App SDK 1.7+; the app
resolves 1.8) to `Dark` or `Light` from the root element's `ActualTheme`
(`RequestedTheme` first when it is set, the application's theme when the
root has not resolved one yet), and re-applies it on the root's
`ActualThemeChanged` and `Loaded`, with `UISettings.ColorValuesChanged`
(marshalled to the window's dispatcher, unhooked on `Closed`) as a backstop for
the live switch. `MainWindow` and `AssistWindow` — the only two `Window`
subclasses; a section opens inside the main window, not in one of its own —
call it right after `InitializeComponent`, and `MarketingShotCapturer.Dress`
calls `WindowTheme.Sync` after setting a scene's theme. `WindowThemeSourceTests`
fails for any `Window` subclass under `windows-app/Plantoir` that does not call
`WindowTheme.Apply(this)`, so a window added later cannot keep the white bar.

**Measured** on this PC (Windows 11 Pro 26200, x64 Debug, `--state-dir`), by
`PrintWindow` captures of the live windows and a pixel read at the caption's
centre: dark mode, main window caption (31, 32, 34) over content (26, 35, 34);
the assistant window (30, 33, 34). Switching Settings to light with the app
open turned the caption to (239, 244, 247) within four seconds, no restart,
and back again. The caption is drawn on the same Mica as the content, so it
reads as one surface rather than a stripe in both modes.

**Rejected.** Hand-set `AppWindow.TitleBar` colours (the twelve
`Background`/`Button*`/`Inactive*` slots): both windows sit on a Mica backdrop
tinted by the wallpaper, so any fixed colour reads as a band against it, and
twelve slots are twelve chances to look unlike Windows' own hover, pressed and
inactive states. `PreferredTheme = UseDefaultAppMode`: it follows the SYSTEM,
not the content, and the marketing capture themes the content directly, so a
dark scene taken on a light PC would get a light bar. `DwmSetWindowAttribute`
with `DWMWA_USE_IMMERSIVE_DARK_MODE`: the same result through P/Invoke, where
the Windows App SDK property already exists. `ExtendsContentIntoTitleBar` with
a custom bar: a redesign of both windows' chrome for a colour fix, and nothing
in the app uses it today. The mac inherits nothing: its title bars already
follow the system.

## Getting a folder ready after an update (#473)

**What was wrong.** Every working folder carries a copy of the app's tools in
`.toolchain\` (the recipe the launchers build from; `ToolchainMirror`). The app
brings it up to date with its own bundled copy the first time it touches a
folder in a run, and after an update that means copying thousands of files.
That copy ran inside `WorkspaceViewModel.Reload()`, which the `MainWindow`
constructor calls through `AdoptRestoredPath` — on the UI thread, before
`App.OpenWindow` could call `Activate()`. So on the first launch after an
update the teacher clicked Plantoir and saw **no window at all** for
**119.7 s and 93.7 s** (two launches, 2026-10-07, installed 1.4.2 → 1.4.3,
Lenovo 20QES70500, Intel Core i5-8365U, Windows 11 Pro 26200, read from the
gap between `App.OnLaunched starting` and `MainWindow.Activate called` in
`%LOCALAPPDATA%\Plantoir\startup.log`). The same freeze followed any window
opened on a folder whose `.toolchain\` was stale. #465 had already moved the
daily update check after the window; the freeze itself is this issue.

**AFTER** (2026-10-08, same PC, the x64 Debug build of this branch, a real
working folder `C:\Users\lenov\Teaching`, read from
`%LOCALAPPDATA%\Plantoir\startup.log`):

| Run | Launch → window | Copy's own duration, then launch → copy finished (Preview usable) |
|---|---|---|
| `.toolchain\` removed entirely (12,753 files to copy) | **2.9 s** (`App.OnLaunched starting` 08:42:02.557 → `MainWindow.Activate called` 08:42:05.489) | 17.4 s; finished 17.9 s after launch (08:42:20.460), in the background, the window usable throughout |
| `.toolchain\` present, every one of its 12,753 files made different (a byte appended, its time moved) | **2.7 s** (08:48:15.140 → 08:48:17.880) | 15.2 s; finished 15.5 s after launch (08:48:30.676) |
| BEFORE, 2026-10-07, the installed 1.4.3 → 1.4.4 first launch | no window for 119.7 s and 93.7 s | the same moment |

The caveat that keeps these honest: both AFTER runs had a WARM disk cache —
the bundle had just been read by the UI tests and by the previous copy —
whereas the first launch after a real install reads 12.7k freshly written
files cold, so 15–17 s is a lower bound on the copy, not a prediction of it.
The number that matters, launch to a usable window, no longer depends on the
copy at all.

For scale, measured while writing the UI test (2026-10-08, same PC, x64 Debug):
deleting the folder's `.toolchain\support\skeletons` (2,389 files) before
launch, the window was shown 2.2 s after the copy started and the copy
finished 3.1 s after that (5.3 s in all); the banner and the disabled buttons
covered exactly that gap. The whole bundled recipe is 12,753 files, 9,829 of
them in `support\example_content`.

### The three questions the issue asked

**1. What the window shows while it waits, and whether Preview and Deploy are
disabled or queued.** DISABLED, with the reason — Russell's decision, and no
dialog. The window appears at once, with its sidebar and every page readable
and editable; what builds from the copied tools waits:

- **Preview and Deploy** in a section are greyed, their tooltip and their
  automation help text (a screen reader reads the second; it does not read a
  tooltip) saying `ToolchainReadiness.GettingReadyMessage`.
- **New Course** (the sidebar's `+`) is greyed the same way, and every other way
  into the wizard (the empty pane's "New Course…" — "Add a Course…" until
  #488 — File ▸ New Course…, the automation hooks) is
  refused by `SidebarPane.OpenNewCourseWizard` with the same sentence. Inside
  the wizard, Create and Add Example Course ask again before the progress view
  replaces the form, and `NewCourseCreator` refuses BEFORE `course_config.json`
  or the `course created` trail line is written — next to its existing
  setup.ps1 check, for the reason that check exists (a half-made course blocks
  a retry).
- **A banner** (`gettingReadyNotice`, an `InfoBar` under the synced-folder
  notice in the same grid row) says `GettingReadyTitle` and
  `GettingReadyMessage`, not closable, informational. It opens only if the copy
  is still running ONE SECOND after the window was shown
  (`ToolchainReadiness.BannerDelay`): the ordinary launch, with nothing to copy,
  still compares every file, about half a second, and a banner for that would
  flash on every launch. **The buttons are disabled for that half second on
  every launch regardless** — a teacher who clicks Preview within half a
  second of the window appearing gets the refusal dialog; nobody has.
- **If the copy cannot finish** (any file that could not be copied or deleted,
  or the copy threw), the banner turns into an error saying
  `ToolchainReadiness.CouldNotGetReady`, which names File → Reload Courses; it
  stays, and so do the disabled buttons, until that reload or a new window on
  the folder tries again.

The words are in `ToolchainReadiness` (rule 1: nothing about tools, scripts or
containers; "Deploy" because that is the button's caption, #443):

| | |
|---|---|
| Banner title | `GettingReadyTitle` — "Getting this folder ready…" |
| Banner, tooltip, refusal while copying | `GettingReadyMessage` — "Plantoir is copying what it needs into this folder. Preview and Deploy will work in a moment." |
| Error banner, tooltip, refusal after a failure | `CouldNotGetReady` — "Plantoir couldn't finish getting this folder ready. Choose Reload Courses from the File menu to try again." |

Quoted here once so a reader can see them; the constants are the truth, and
`ToolchainReadinessTests.TheWordsNameNoMachineryAndCallADeployADeploy` pins
the rule they follow. They are not in the contract: a window's mechanics are
not shared (`contracts/README.md`), and the mac has no such window state.

**Where the refusal is asked.** At every ENTRY POINT, before any lease is
taken and before any question is asked, beside the refusals already there
(`RefusedWhileThisSectionDeploys`, `AnotherProgramStandsInTheWay`), so #406's
order — a preview that is going to be refused is refused with no
today's-class question first — holds: `PreviewOrStop_Click`,
`StartAutomatedPreview`, `DeployAsync` (which hands the assistant the same
sentence as its outcome), `MainWindow.ShowPreviewFor`, `DeployFor` and
`DeployForAsync` (before the selection moves), Course Settings' Preview Again
(before it stops any preview, and before its trail line), and the wizard.
All of them go through `MainWindow.RefusedWhileTheFolderIsGettingReady`, which
shows a dialog titled "Cannot Preview Yet" / "Cannot Deploy Yet".
`ScriptRunner.Run` is a BACKSTOP for a way in nobody thought of: it refuses a
folder that is Copying or Failed — never NotStarted, which is every folder the
unit tests and the marketing captures drive — with the same sentence as
`LaunchProblem`, AND sets `LastExitCode` to -1, so nothing that waits on the
run (the preview's wait for its server, a deploy leg's `WaitUntilFinished`)
waits for a process that never started. A stop (`--stop`) is never refused,
and `PreviewStopper` does not go through `ScriptRunner` anyway.

**2. Whether two windows on the same folder share one copy.** Yes.
`ToolchainReadiness` (Plantoir.Core) keeps one entry per folder, keyed on the
full path case-insensitively (the old `FoldersWithFreshToolchain` set's rule),
under a lock. `Ensure` makes the copy's task INSIDE the lock, so a second
window — or the picker setting a folder up — arriving a moment later finds
Copying and is handed the very same task; it STARTS the task only after
telling every window "started", so nobody can hear "finished" first (a copy
with nothing to do ends in milliseconds, and the first version logged the two
in either order). A folder counted ready is copied again if its
`.toolchain\Dockerfile` has since gone from disk — the mac's own check in
`WorkspaceModel.shouldMirrorToolchain`, one `File.Exists` per reload. A folder is marked ready only
AFTER a pass in which nothing failed. Both halves fix what the old code did:
the set was a plain `HashSet` read and written from whatever thread, filled
BEFORE the copy ran, and `SyncFile` swallowed every exception and answered 0,
so a copy that half failed counted as fresh for the rest of the run.
`SyncFile`/`SyncDirectory` now return a `CopyResult(Changed, Failed,
FirstFailedPath, FirstProblem)` — failed REMOVALS count too, since a stale file
left behind changes the recipe's hash — and the trail line names the first
failure and its error.

A FAILED copy is tried again only on File → Reload Courses
(`WorkspaceViewModel.ReloadTryingAgain`) or when a window is newly pointed at
the folder (`PointAtFolder`) — never on the sidebar's routine reloads (about
fifteen call sites: after a rename, an archive, a restore), or a folder that
cannot be written would be put through a two-minute copy after each of them.
`ToolchainMirror.InitializeWorkspace` (the picker's "set this folder up")
waits for the same `Ensure`, retrying a failed copy, on its background thread.

`Reload()` keeps its exact shape (`SharedRuleContractTests.BodyOfReload` reads
its body): it still refreshes the six launchers synchronously on every reload —
milliseconds; "The new-site dialog" above (reason 4) says what that means for a
stubbed launcher — and now only STARTS the recipe copy.

**Other programs.** `plantoir-mcp` (the Claude/Codex door, and the app's own
assistant window, which talks to it) cannot see the app's memory. For the
length of a copy the app writes
`courses\.internal\activity\toolchain-copying.<pid>` — body
`WorkLease.LeaseBody(withStart: true)` — and deletes it after, failure
included. `LauncherRunner.Run` refuses with `GettingReadyMessage` while a LIVE
marker exists, judged by `WorkLease.OwnerIsAlive` (so a marker left by a killed
Plantoir, or one whose process id now belongs to another process with a
different start time, counts for nothing). Deliberately NOT a `.lease` name:
`WorkLease.Others`, the update gate's `SweepLeasesOf` and reference staging all
read `*.lease`, and this holds no course — the precedent is `BackupDeleter`'s
`<COURSE>.held-backup.<pid>`. The marker is written only when `courses\`
already exists, so it never turns a folder with no courses into one with an
empty list, and writing one sweeps away any left by a Plantoir killed
mid-copy (already ignored; this only stops them piling up) — but never one whose body does not read, which is what a live marker looks like for a moment while a program writes it in place. This app writes its own under a `writing-…tmp` name and moves it into place, so its marker is never seen empty. **The marker
exists only WHILE a copy runs, so plantoir-mcp cannot see a FAILED copy** —
by design: a failed copy is usually a file that could not be written, the
assistant's build then fails on its own with the launcher's own words, and a
marker kept after a failure would need someone to remove it, which a killed
app never does. The app's own window still refuses with `CouldNotGetReady`.

**The app's own robots wait instead of being refused.** The command-line
automation hooks (`--auto-preview`, `--auto-deploy`, `--auto-wizard`,
`--auto-createcourse`, `--auto-select`, `--auto-addsection`, `--auto-course`)
and every marketing-capture scene (`MarketingShotCapturer.OpenMain`, and
`Provision` before it makes courses) used to act after a fixed 1.5 s. They
now await the same `Ensure` — joining their own launch's copy, never starting
another — before pressing anything, so a picture never shows the "Cannot
Preview Yet" dialog; a FAILED copy makes a scene answer `refused: <the
sentence>` and a hook log `automation hook refused: …` and do nothing.

**The scheduled run copies too, since #477 (2026-10-15).** It used to never
mirror `.toolchain\` at all, while its wrapper's fingerprint reads
`.toolchain\scripts` — so after an update a 06:30 run built from the OLD
recipe until the app was opened, and one that fired while a window was
copying built from a mix. Now `ScheduledRun.Execute` waits, inside its
existing ten minutes, while another program's marker is live, and after the
settings decision it calls `ToolchainReadiness.RefreshWorkspace` with the
recipe beside `Plantoir.exe` (`World.BundledToolchainRoot`, set by
`Program.Main`) before it writes the wrapper. The run's copy goes through
`Ensure` and `CopyNow`, so it writes the same marker: `plantoir-mcp` refuses
meanwhile and a window's later copy waits its turn. The order, the reasons,
the stand-down sentence and the measurements are in 07 → "On Windows since
bundle 3: the scheduled run is Plantoir".

**Two copies take turns (#477).** Measured: two copies into one folder at
once fail with sharing violations (36 failures in 5 runs, 0x80070020; a
temp-name-and-rename version failed 855 times with 0x80070005 and left `.tmp`
files behind — 07 has the numbers). So `CopyNow` writes its marker FIRST and
then waits while a live marker written before its own stands
(`ToolchainReadiness.MustWaitFor`: an earlier moment on line 3, or the same
moment and a lower process id; an unreadable moment counts as NOT earlier,
so no two copies can both wait on one marker; never itself). `Markers()` now
reads the moment and `WriteMarker` returns the moment it actually wrote. How
long to wait is the CALLER's (`ToolchainReadiness.TakingTurns`): the window's
`WaitUntilDone` looks every half second and never gives up — the folder
reads Copying, with its banner, meanwhile — and says in startup.log that it
waited and for which process; the scheduled run passes its own `Sleep` and
gives up when its ten minutes, counted from its wait for the course, are up,
leaving `Status.GaveUpWaiting` and writing nothing. `Entry.Writing` is set
only when the copier really starts (#484 waits only for those). A marker from
an older Plantoir (1.4.5 and before) has the same body, so it is waited for;
that program never waits in turn, so copies may still overlap with it, and
nothing deadlocks. `RefreshWorkspace` (Core) does NOTHING when the recipe's
`Dockerfile` is not at the root it is given: the mirror deletes what its
source lacks, so mirroring from a missing bundle would empty the working
folder's tools. `BundledToolchain.RefreshWorkspace` is now the app's thin
wrapper around it, and keeps its name (`Reload()`'s body is pinned).

A NOTE on a near-miss when reading the contract: `workLease`'s
`howToRunACase` ends "On Windows, aBuild and aScheduledPublish also block on
copy (#413)". That `copy` is the backup-zip LEASE (`WorkLease.Copying`, a
course being zipped for an assistant), not this tools marker, which is not a
lease and holds no course.

**3. Whether the mac's equivalent blocks the same way.** It did, and #476
(the mac, 2026-10-08) measured and then matched this design: the copy held
the main actor for 0.9–3.9 s on an M4 Pro with a warm cache (about four
seconds at worst; cold and Intel not measured), and Russell chose the
Windows design anyway. The mac's copy now runs off the main actor through
one `ToolchainReadiness` registry, with Preview, Deploy and New Course greyed
and a banner once a file is written; it marks a folder fresh only after a
copy with nothing failed (the same defect, fixed the same way); its MCP
server and headless rebuilds wait for their own copy; it writes the same
`working folder tools copied` line; and ⌘Q waits for a running copy, which
this side now does too (#484, below). Two differences, both on purpose: no
cross-process marker (every file is written atomically from the same bundle,
so two copies at once write the same bytes), and the banner follows the
first file WRITTEN rather than a timer. `documentation/09-mac-app.md` →
"Getting a folder ready after an update, off the main actor (#476)".

### Closing waits for a copy that is writing (#484)

Since 2026-10-15 (Russell's ruling on #484: wait on close, matching the mac's
#476). Before, closing the last window while the copy ran ended it part-way:
each file is written whole, so nothing was torn, but `.toolchain\` was left
half old and half new until the app next ran — and a launcher typed at a
prompt, or (before #477) a scheduled run, hashed and built from that mix.

**What it does.** `MainWindow.AskBeforeQuittingThroughWork` (the Closing
handler) asks the #231 quit question FIRST, unchanged — Keep Working leaves
everything as it was. Then, when the close quits the app (`App.ClosingThisQuits`:
the last window) and a copy is WRITING (`ToolchainReadiness.AnyCopyIsWriting`),
it cancels the close synchronously, before any await, opens the banner at
once (the one-second delay treated as passed) — the "Getting this folder
ready…" banner when the copy is this window's folder's, and
`ToolchainReadiness.BannerWhileClosing`'s "Finishing getting a folder ready…"
when the copy being waited for is ANOTHER folder's and this one is ready (the
batch 4 implementation review's M2: `RefreshReadiness` read only this
folder's state, so a last window on folder Y waiting for folder X's copy
showed nothing at all) — awaits
`ToolchainReadiness.WhenWritingCopiesFinish()` — every folder's writing copy in
the process, the mac's `waitForAllCopies()` — and closes again; `Closed` then
runs `App.QuitTime()` as before, so a prepared update still installs at quit,
after the copy. The decision is the pure
`ToolchainReadiness.ClosingWaitsForTheCopy(closingQuits, aCopyIsWriting,
systemIsEnding, alreadyWaited)`.

**Three bugs the plan review found in the first design, and what fixed them.**
(H1) the old handler began `if (_quitConfirmed || …) return;`, so Quit Anyway's
own `Close()` skipped any wait: `_quitConfirmed` now skips only the QUESTION.
(H2) a "second close does nothing" guard on `_waitingForCopies` would have
cancelled the handler's own final `Close()`: the flag is cleared before it.
(M3) waiting only for copies already writing could miss one still waiting its
turn behind another program's copy, which then starts and is cut by the exit:
`WhenWritingCopiesFinish` HOLDS BACK every copy not yet writing, under the
same lock a copy takes to mark itself writing, and takes its snapshot again
after each wait. A held-back copy has written nothing; if the close turns out
not to quit, `ReleaseWaitingCopies` lets it go.

**A close that waited and then did not quit releases the hold (the batch 4
implementation review's M1).** The hold is process-wide and nothing else
clears it, so a close that ends without quitting after the wait would leave
every later copy waiting its turn for the life of the process — banner up,
Preview, Deploy and New Course greyed, the folder's marker live so
`plantoir-mcp` refuses and a scheduled run stands down. Three ways that
happens, all handled by `MainWindow.LetHeldCopiesGo` (which also clears
`_copiesWaitedFor`, so a later close waits again): the quit question is
asked AGAIN after the wait (a preview began meanwhile) and the teacher keeps
working; a window was opened meanwhile, so the close no longer quits; or the
handler itself threw. `UpdatePrompts.QuitForInstallAfterTheCopy` releases
it too when the installer does not start. Test:
`ToolchainReadinessTests.AHoldReleasedAfterACloseThatDidNotQuitLetsALaterCopyFinish`.

**A finished copy tries five times to take its marker away** (200 ms apart,
the batch 4 implementation review's L1): a scanner or indexer holding the
file for a moment would otherwise leave a LIVE marker for as long as this
process runs, holding every other program's copy of the folder. The limit
that remains: a marker still undeletable after the fifth try is said in
`startup.log` ("its marker could not be removed after 5 tries") and stands
until this process exits, when it reads as stale and is swept. Test:
`AMarkerHeldOpenForAMomentIsStillTakenAwayAfterTheCopy`.

**What it does not do, and why.**
- **Not while Windows is ending the session** (`SessionEnding.IsEnding`).
  Windows ends the process at sign-out whatever the window does; holding the
  close only produces "this app is preventing shutdown". A Windows-only
  difference from the mac, and a cheaper one since #477: the scheduled run now
  brings the tools up to date itself before it builds.
- **Not for a window that is not the last.** Closing it does not end the
  process, so the copy carries on in the windows that remain.
- **Not twice.** A second X while the window waits does nothing new.
- **The update installer's quit** goes through `Application.Exit()`, which
  raises no window's Closing, and the installer overwrites `{app}\Toolchain` —
  the files the copy READS. So `UpdatePrompts.QuitForInstall` awaits
  `WhenWritingCopiesFinish()` itself before it starts the installer (a
  fire-and-forget helper; `IUpdatePrompts` stays `void`). The menu bar has no
  Exit item (2A), so the window's X / Alt+F4 and the installer are the only
  quits.

**Measured** (i5-8365U, 16 GB, Windows 11 Pro 26200, x64 Debug, 2026-10-15,
`GettingReadyUiTests.ClosingDuringTheCopyWaitsForItThenQuits`, which deletes
`.toolchain\support` — 12,660 files — before launch): window 3.5 s after
launch, closed at 3.6 s, still up and copying 0.7 s later with its banner,
quit at 18.9 s — 15.3 s held open — with every one of the bundle's support
files in place and the trail line ending ", and Plantoir waited for it before
closing". Must-fail: with `ClosingWaitsForTheCopy` forced false, the same test
quit at 5.3 s with the support folder short, and failed.

Tests: `ToolchainReadinessTests.ClosingWaitsOnlyForAWritingCopyWhenItQuits`
(the decision table), `ClosingWaitsForEveryFoldersWritingCopy`,
`ACopyStillWaitingItsTurnIsNotWaitedForAndDoesNotStartOnceTheCloseBegins`
(M3), `ACopyAClosingWindowWaitedForSaysSoOnTheTrail`; the UI test above. H1
(Quit Anyway, then the wait) is window logic no unit test reaches and was
not driven through the window: it needs a build under way and a copy writing
at once.

**Rejected:** quitting anyway after a time limit (the copy is bounded by
itself — seconds warm, about two minutes cold — and a cut copy is the fault);
a dialog asking whether to wait (there is nothing to decide: the copy finishes
on its own and the window says so); and doing nothing and recording the gap,
the other answer #484 allowed — the mac waits, and the difference would have
been one more thing to explain.

### What was rejected

- **Copy into a temporary folder and rename it into place.** Atomic, but it
  rewrites all 12,753 files on every update instead of the few hundred that
  changed — the in-place mirror only writes what differs, and the launchers
  hash the folder, so a whole new tree buys nothing. The residual risk is
  recorded instead: a preview ALREADY RUNNING from another process (a
  command-line launcher) while the app copies can read a mix of old and new
  files. That is unchanged from before #473 — the copy was never atomic — and
  the app's own builds now wait for it; since #477 a scheduled run does too
  (it waits for a live copy and makes its own). Measured on 2026-10-15, a
  temp-name-and-rename per FILE is worse still when two copies meet: 855
  failures in 3 runs (07 → "On Windows since bundle 3: the scheduled run is
  Plantoir").
- **Queueing** Preview and Deploy until the copy finishes. Russell chose
  disabled with a reason: a queued press is invisible work that starts on its
  own minutes later, and a teacher who pressed Deploy and walked away cannot
  tell a queued deploy from a lost one.
- **Gating only in `ScriptRunner.Run`.** One check would cover every path, but
  it fires AFTER the leases are taken, after the running preview was stopped
  for a deploy, and after #406's today's-class question — a refusal that
  arrives after the window has already acted. So the gates are at the entry
  points and `ScriptRunner` is the backstop.
- **A wait in the scheduled run** — rejected in #473 as out of scope, and
  built in #477 (above): the run now waits for a live copy and makes its own.
- **A modal "please wait" dialog.** It would block exactly what the teacher
  can safely do meanwhile (read and edit pages, settings) and is the shape of
  the freeze this fixes.
- **A contract key** for the banner states: window mechanics are not contract
  (`contracts/README.md`). The state → enabled and state → banner mappings are
  pure functions in Core (`ToolchainReadiness.RefusalFor`, `BannerFor`,
  `AutomationStatus`) pinned by `ToolchainReadinessTests`.

### The trail, and measuring it

`working folder tools copied` (`ActivityTrail.Event.WorkingFolderToolsCopied`;
`shared-rules.json` → `activityTrail.mustRecord` — `appliesOn: ["windows"]`
until the mac's #476 wrote it too) is written once per copy that changed or
failed something, never for the ordinary pass:

```
… · got the working folder ready — 2389 files brought up to date in 5.3 s — C:\…\workspace
… · could not finish getting the working folder ready — 2 files could not be copied or removed (first: .toolchain\scripts\build_site.py, <its error>), 40 files brought up to date in 12.3 s; Preview and Deploy wait for Reload Courses — C:\…
```

Since #477 the scheduled run's own copy writes it with the course and
section, "got the working folder ready for a scheduled deploy — …", and a
failure there ends "; the scheduled deploy stood down" (nobody is there to
choose Reload Courses). Since #484 a copy a closing window waited for ends
", and Plantoir waited for it before closing". A copy that waited for another
program's copy says so in `startup.log` ("tools copy for '<folder>' waited
N s for another copy (process P) to finish first", or "did not start" when the
scheduled run gave up), not on the trail: the run's own `scheduled publish
waited for the course` line carries that.

It does not say "after an update": the same copy fills a folder the picker sets
up from nothing, and refreshes any stale one. And a pass that changed NOTHING
but still took more than a second (a slow disk comparing 12,753 files) shows
the banner and writes no line — which is fine: the banner was true while it
was up, and a line saying "0 files" on every slow launch would bury the one
that explains a real copy; the `startup.log` lines below still time it.

For a developer, `startup.log` brackets it: `tools copy started for '<folder>'`
and `tools copy finished for '<folder>': Ready, N changed, M failed, S s`. Time
from launch to window is `App.OnLaunched starting` (or `Program.Main starting`)
to `MainWindow.Activate called`; launch to a usable Preview is the same start to
`tools copy finished`.

### Testing it

`ToolchainReadinessTests` (Core): one copy for sixteen concurrent `Ensure`
calls under two spellings of one folder; not ready until the copy has
finished; one failed file → Failed, not retried by a routine reload, retried
when asked; a copy that throws → Failed with its reason; the real
`SyncDirectory` counting a file it could not write; `InitializeWorkspace`
waiting and leaving the folder Ready; the trail line; the state → buttons and
banner mapping; the backstop refusing Copying and Failed (with
`LastExitCode` set) but never NotStarted or a stop; the wizard's preflight
writing nothing; the marker's lifetime, a dead pid, a recycled pid, and
`plantoir-mcp` refusing on a live one.

`GettingReadyUiTests` (UiFact) makes the copy real: it deletes the fixture's
`.toolchain\support\skeletons` before launch and asserts the window and the
sidebar arrive while the menu bar's ItemStatus says `copying`, that `+`,
Preview and Deploy are disabled with `GettingReadyMessage` as their help text,
that the banner shows, and that everything clears when the status becomes
`ready`. The status is on the MENU BAR because UI Automation needs an element
present from the window's first moment with a peer of its own: a `StackPanel`
has none, and a closed `InfoBar` is not reliably in the tree. Every other UI
test now waits for `ready` in `DrivenApp`'s constructor (up to 90 s): on a
fixture `InitializeWorkspace` has already brought up to date that is the
ordinary half-second pass, and without the wait a test pressing Preview the
moment the sidebar appears would meet the disabled button.

## Menus, the Section menu's functions and #475 on Windows (#488, #489, #483)

The mac's #457 put every action on a course or a section into two persistent
menus, **Course** and **Section**, with keys on menu items only, File ▸ Open
Recent, and context menus that select their row first
([09 → "Mac conventions: the menu bar, keys and text fields (#457)"](09-mac-app.md#mac-conventions-the-menu-bar-keys-and-text-fields-457)).
Windows' catch-up to 1.7.1 lands it in three pieces: **2A** (this part, #488
and #483) is the menu bar, Open Recent, the context menus and the Obsidian
route; **2B** adds the assistant's nine functions to the Section menu (#489
items 1–2) and **2C** the question about classes dated after the next class
at Deploy (#475, the rest of #489). Their parts of this section are written
when they land.

### The menu bar (2A, 2026-10-15)

| Menu | Items (Windows key) |
|---|---|
| File | Open Working Folder… (Ctrl+O), Open Recent ▸, New Window (Ctrl+N), New Course… (Ctrl+Shift+N) · Import Courses for Reference…, Restore from Archive…, Reload Courses (Ctrl+Shift+R) · Settings… (a window of its own since #491 — "The Settings window, Plantoir Help and the Account ID's refusals" below), Check for Updates… (only while the updater has a feed) |
| Course | Add Section…, Copy a Page from This Course… · Save Course Settings (Ctrl+S), Revert Course Settings · Rename (F2) and its reason line, Set School Year…, Keep a Copy for Reference… · Back Up Now, Restore from Backup… · Revise With ▸, Open in Obsidian (Ctrl+Shift+O), Show in File Explorer, Open in Terminal · Delete Backup…, Delete Archive…, Remove Course… |
| Section | Preview / Stop Preview (Ctrl+Shift+P), and since #514 its second item Preview at Last Viewed / Preview (no key; absent while a preview runs — "Preview at Last Viewed on Windows" below), Deploy… (Ctrl+Shift+D), Open in Browser · (2B) Publish Pages…, Hide Pages…, Publish Class for a Date…, Rebuild Preview (Ctrl+Shift+B), Undo Last Change · Add Next Class, Re-date Classes…, Make Room for Classes…, Class Dates… · Schedule Deploy…, Cancel Scheduled Deploy… · Get Ready for the Start of the Year…, Undo Getting Ready for the Start of the Year…, Publish Pages That Links Lead To… · Revise With ▸, Open in Obsidian (Ctrl+Shift+O when a section is selected), Show in File Explorer, Open in Terminal · Remove Section… |
| View | Back (Alt+Left), Forward (Alt+Right) · Reload Page (Ctrl+R) |
| Help | Plantoir Help (F1, since #491) · Publishing and Deploying… · Report a Problem… · About Plantoir |

**One table, in code** (`Plantoir/MainWindow.Menus.cs`): every item is built
by one `Add(…)` that carries its contract item (`SubjectMenuRules.Item`), its
key and its AutomationId, so an item cannot exist without its rule or its id.
The menu bar's XAML holds five empty `MenuBarItem`s and nothing else.

**Which items can be used** is `Plantoir.Core/Models/SubjectMenuRules.cs`, a
port of the mac's `SubjectMenuRules.enabledItems`, run by
`SubjectMenusContractTests` against `shared-rules.json` → `subjectMenus` (21
cases, 51 items, 24 situation keys; the names map both ways by camel-casing
the enum, so "Finder" and "NewTerminalAtFolder" in two names are the mac's
neutral words for Show in File Explorer and Open in Terminal). Items GREY,
never hide — except Revise With ▸ Claude… and Codex…, LEFT OUT when not
installed (`ClaudeCodeLauncher.IsAvailable`, `CodexLauncher.IsAvailable`,
decided when the window is built: a fact about the PC, not the selection).
Local AI Assistant… is always drawn, greyed on a course row.

**What the rule is fed** is `MainWindow.CurrentSituation()`, read from the
owner that already decides each fact, so the menu and the button cannot
disagree: Preview and Deploy from the section window's own buttons
(`SectionDetailView.PreviewButtonIsEnabled`, `DeployButtonIsEnabled`), Save
and Revert from Course Settings' (`SaveIsEnabled`, `RevertIsEnabled`), the
schedule from the sidebar row's clock (`ScheduledDeployShownFor` — the tree
already re-reads Task Scheduler on every refresh, and asking it again per
menu refresh would spawn work on every hover), copying from the work lease
plus this app's own Back Up Now (`SidebarPane.IsZipping`), the dialog from
`DialogGate.IsOpen`. Two facts are gathered the Windows way: **any**
assistant on the course greys all three Revise targets (Windows' #468 hold,
which the context menus already used), and — since 2B — `lastChangeIsHere`
and `verbIsRunning` come from the window's own runner and the in-process
claims ("The Section menu's functions", below). A `mac` issue records the first.

**Each item runs the SAME code as its other routes.** `SidebarPane.Perform`
(`SidebarPane.Menus.cs`) dispatches the row items to the functions the
context menus call (`OpenAddSectionDialog`, `KeepACopy`, `BackUpCourse`,
`ConfirmRestoreBackup`, `AskWhenToDeploy`, …); Section ▸ Preview and Deploy…
press the toolbar's own handlers on its own predicates (so today's-class
question, #406, is asked from the menu too); Save Course Settings presses
Save. Remove Course… and Remove Section… share the footer button's question
(`SidebarPane.ConfirmRemove`, factored out of `Remove_Click`; since #491
`ConfirmRemoveCourse` / `ConfirmRemoveSection`, which the − button, the Delete
key and the rows' new Remove… items reach through `MainWindow.RunFromTheSidebar`).
The selection
is read when the item RUNS, never captured when the menu was drawn.

### WinUI's menu bar has no Opening event — measured, and what fills the gap

Measured with a probe app (MenuBar, three menus, a TextBox and a WebView2;
keys sent with `keybd_event`, the pointer with `SetCursorPos`/`mouse_event`;
two runs, Windows App SDK 1.8.260921001, **Intel i5-8365U, Windows 11 Pro
26200**, 2026-10-15):

| What | Measured |
|---|---|
| An item's key with its menu CLOSED, focus in a TextBox | fires; `Invoked` 11–14 ms after the key-down, then the item's `Click` (2 ms later) unless `Invoked` is marked handled |
| One key on a DISABLED item earlier in the bar and an ENABLED one later | the ENABLED one fires (3–7 ms); the disabled one neither fires nor swallows the key — the OPPOSITE of AppKit, where the disabled item ate it |
| One key on two ENABLED items | the FIRST in the bar fires, the second never |
| The key on a disabled item alone | nothing |
| Ctrl+, (`VirtualKey` 188, the comma) on an item | never fires (both runs) |
| Focus in the WebView2 (given programmatically, or by a real click in the page): Ctrl+Shift+D, Ctrl+Shift+O, Ctrl+R, Alt+Left on items, and Ctrl+Shift+G on the root Grid | NONE fires — the page takes the keys (the WebView2's own browser keys are left on, so Ctrl+R and Alt+Left are its own reload and back; that half was not measured) |
| A ContentDialog up: Ctrl+Shift+D on an item, Ctrl+Shift+G on the root Grid | neither fires |
| Pointer onto a MenuBarItem, then a click | `PointerEntered` at once; `PointerPressed` (handled-events-too) at the press; `Tapped` 26–88 ms later; the flyout's items `Loaded` 3–4 ms after `Tapped` — so everything a refresh can hang on comes BEFORE the flyout draws |
| F10, Right, Down from a TextBox | did not open a menu in the probe |

So enablement is applied AHEAD of time (`ApplyMenuEnablement`) on every change
the window hears — the selection, the folder's state, the section window's
`PreviewChromeChanged`, Course Settings' new `SaveStateChanged`, the tools
getting ready (#473), activation, a sidebar refresh, a backup starting and
ending — and again on `PointerEntered` and `PointerPressed` of each menu
title, on `AppMenuBar.GotFocus`, and on the `Loaded` of each menu's first item
(a flyout opened from the keyboard or by UI Automation). Whatever the menu
showed, `Invoke` asks `DialogGate` and the rule AGAIN at the click; that is the
guard that counts, as the mac's `MenuRoute.run` is.

**Keys live on the menu items, and nowhere else.** The root Grid's seven
accelerators are gone, Course Settings' Save button lost Ctrl+S (now Course ▸
Save Course Settings), and the section window's three view-scoped
accelerators (Ctrl+R, Alt+Left, Alt+Right) are gone too: the measurement shows
no XAML key fires with the page focused, whatever its scope, and with focus
anywhere else the items' keys fire — so the view-scoped copies added nothing.
Every accelerator's `Invoked` is marked handled (an unhandled one goes on to
raise `Click`, which would run the item twice), and asks
`DialogGate.Holds(root, "<key>")`, so the #191 record still notes every
arrival. F2 does nothing while a text field has focus: the key is marked
handled at the accelerator, so it is spent rather than passed to the field
(which gives F2 no meaning of its own) — passing it on would raise the item's
`Click` and rename anyway. **A Rename held back by `Invoke`'s re-check is
silent too** — F2 on a course whose Rename the rule greys (a reference
course, a section row, a course being copied) does nothing and says nothing,
which is what the mac's key on a disabled menu item does. Before #488 F2 opened
the rename dialog and let it explain the refusal; do not restore that route:
the reason is on the greyed Course ▸ Rename's own reason line, and a key that
opens a dialog the menu says cannot be used is the disagreement the one rule
exists to prevent.

**Ctrl+Shift+O sits on ONE Open in Obsidian item** — Course's unless a section
row is selected, then Section's; `ApplyMenuEnablement` moves the accelerator
object between the two items' `KeyboardAccelerators`. WinUI would in fact have
coped with the key on both (the enabled one fires, measured), but the key
would then be DRAWN on both, and one key means one thing.

**Why the keys are these.** Ctrl+O, Ctrl+N, Ctrl+Shift+R and F2 were already
Windows' own; Ctrl+S is Save everywhere on Windows; Alt+Left/Right and Ctrl+R
are every Windows browser's Back, Forward and Reload. Ctrl+Shift+N, P, D and
O follow the mac's ⇧⌘ letters. **Not Ctrl+Alt+anything**: on many European
layouts AltGr IS Ctrl+Alt, so a Ctrl+Alt key fires while a teacher types @,
€ or { — so Add Section… has no key here (the mac's ⌥⌘N). **Not Ctrl+Shift+C**
for Copy a Page: it is the browser's inspect-element key and a teacher who has
used one expects that; Copy a Page has no key. **Settings… lost its "Ctrl+,"
label**: it was drawn with nothing behind it, and a comma key measured above
does not fire. Ctrl+Shift+B was kept free for 2B's Rebuild Preview, which has it now.

### What does NOT exist here: File with no window

The mac's File menu works with no window open. A WinUI menu bar lives INSIDE a
window, and closing the last window quits (`App.ClosingThisQuits`), so there
is no "no window" state to serve. The nearest thing is a window on the folder
picker (`WorkspacePickerView`): there `hasFolder` is false and the contract's
first case holds — Open Working Folder… and Open Recent live, everything else
greyed. Nothing to build; written down so nobody goes looking for it.

### File ▸ Open Recent

`RecentWorkingFolders` (Core) is the rule, run by `OpenRecentContractTests`
(cap 10, the five adding cases for Windows — the mac's case of one folder in
two spellings is `appliesOn: ["mac"]`, and Windows' own form of it, case and
a trailing separator, is pinned beside it — the three title cases and the
wording). The list is kept in `settings.json` → `RecentWorkingFolders`, null
until first read, then seeded from the last working folder and the
remembered windows so the menu is not empty after the update. It is recorded
on OPEN only — `WorkspaceViewModel.ChooseWorkspace` (Open Working Folder…,
Open Recent, the picker) and `AdoptRestoredPath` (the launch-time reopen) —
never on activation, and never by Ctrl+N's window, which inherits a folder.
`OpenRecentList.Changed` is static, so every window's submenu is rebuilt from
the one list (and each window lets go of it on Closed).

Titles join extra parents with "/" exactly as the contract's cases do, on
Windows paths too ("Courses — A/2025"); a folder at the top of a drive is told
apart by its letter ("Courses — C:"), Windows' own case. Choosing a folder
asks `LastWorkingFolder.WhyItCannotBeReopened` first: gone, drive not
connected or unreadable get `OpenRecentWording`'s title and sentence in a
dialog over a window that KEEPS its folder, and the trail says "working folder
not reopened (gone) — a folder chosen from Open Recent, <path>". The mac's
`inTrash` and `privacyDenied` cannot happen on a computer that remembers a
path, so they have no member here. Otherwise the synced-folder question runs
as for a picked folder, and "working folder opened — <path> from File ▸ Open
Recent". Clear Menu writes "recent working folders cleared — N folders".
REJECTED: the taskbar's jump list as the list (a second place to keep in
step, outside the window where the menu is), and recording on activation
(see above).

### Context menus select their row first, and one Obsidian route

Every row menu's item now SELECTS its row before it acts (`SidebarPane.Selecting`,
which sets the selection and the tree's highlight), so what is selected
afterwards is what the item acted on. **Rename too**, unlike the mac: there a
rename field opened in the same turn as a selection change lost focus and
closed (#293); here Rename is a dialog, so nothing is lost. The row's item is
**Rename** (no "Course"), as in the menu bar.

**Open in Obsidian is one route**, `SidebarPane.OpenInObsidian(course,
section)`, called by the section window's toolbar, Course Settings' toolbar,
every row's menu and both menu-bar items: a section reveals the SECTION's
folder, and a course kept for reference gets its calm note first — which the
section window's toolbar used to skip, going straight to
`FolderActions.OpenInObsidian` (the plan's finding 0.9).

**The course row lost its local-assistant item** (then "Revise with local AI
assistant…"; since #491 the rows' Revise items sit in Revise With ▸ as Claude…,
Codex… and Local AI Assistant…, the menu bar's titles): the contract greys
`courseReviseWithLocalAssistant` on a course row, a context menu hides what
does not apply, and the item opened section 1 without saying so. Not a
teacher's only route: every section row offers it, and so does Section ▸
Revise With ▸ Local AI Assistant….

**Two deliberate disagreements with the contract's reasoning, both in the
row, both in the `mac` issue:** the section row keeps **Change Deploy Time
(…)…**, which `subjectMenus` has no item for (the menu bar follows the
contract: Schedule Deploy… greyed while one is set, Cancel live), and a
reference section's row keeps **Cancel Scheduled Deploy…**, which the menu bar
greys, because Windows does not yet turn such a schedule off itself (the
mac's `ScheduledDeployCleanup`) and the row is the teacher's only way to stop
it.

### REJECTED, with the reason

- **XAML for the 50-odd items**: each would need its item, key and id kept in
  step by hand in two files; the code table keeps them in one line.
- **One key on two items** — see Ctrl+Shift+O above.
- **Keeping the view-scoped preview keys "in case"**: measured to add nothing.
- **Greying items in an `Opening` handler**: there is none on `MenuBarItem`.
- **Hiding what does not apply in the menu bar**: the contract's rule; items
  would come and go with every click.
- **A "Change Deploy Time…" in the menu bar** before the contract has the
  item: it would be Windows' private command in a menu the two apps share.

### Testing it

`SubjectMenusContractTests` and `OpenRecentContractTests` (unit, every run).
Through the real window, `[UiFact]`s (2026-10-15, this PC, all passing):
`MenuBarReachUiTests` (Course ▸ Add Section… and Copy a Page…, Section ▸
Schedule Deploy…, Help ▸ Publishing and Deploying… in the contract's words);
`MenuGreysUnderADialogUiTests` (every Course and Section item greyed with a
dialog up; Ctrl+Shift+D's control arrives with no dialog and the deploy
refuses — its folder does not exist — and the same key under that refusal
arrives nowhere); `OpenRecentUiTests` (a second folder opened, listed first;
the first chosen back; the second deleted and chosen, the dialog, the window
keeping its folder, the trail line; Clear Menu and its line). Section ▸ Class
Dates… did not exist yet on that day (it arrived with 2B, below). `AcceleratorUnderDialogUiTests` (#191) still
passes with the keys on items: "Ctrl+Shift+R / F2 / Ctrl+N / Ctrl+O: not
delivered (the dialog kept it); control (no dialog): all four arrived at
their handlers" (2026-10-15). One of three runs that day failed on its own
Ctrl+N control ("the second window would not close") and passed twice since,
alone and paired — recorded as a flake, not chased.
The neighbouring UI tests the change touches (reference courses, Copy a Page,
import for reference, Course Settings' Save, the sidebar's names) ran 13 of
14; `ImportForReferenceUiTests.AnOldWorkingFolderIsImportedShelvedByYearAndLocked`
failed first in the batch ("the import sheet never opened") and passed alone
straight after. **#483** (the wizard's and Copy a Page's field heights) is
measured in "The chrome is shared, and that was a trade — reversed by #456".

### The Section menu's functions (2B, 2026-10-15)

The nine items the mac's #457 batch B put in the Section menu, after Open in
Browser and in two groups: **Publish Pages…, Hide Pages…, Publish Class for a
Date…, Rebuild Preview (Ctrl+Shift+B), Undo Last Change · Add Next Class,
Re-date Classes…, Make Room for Classes…, Class Dates…** (AutomationIds
`sectionPublishPages` … `sectionClassDates`). The section ROW's context menu
carries Publish Pages…, Hide Pages…, Publish Class for a Date… and Add Next
Class, selects the row first, and meets the menu bar's own check at the click
(`MainWindow.RunSectionVerbFromARow`), because a context menu does not
consult the rule when it is drawn. What each item opens is the mac's table
([09 → "The assistant's functions in the Section menu"](09-mac-app.md)); the
deep dive on the third client is
[10 → "The Section menu, a third client"](10-local-ai-assistant.md). This
section is what Windows did differently, and why.

**One runner entry.** `AssistAgent.RunTool`'s body is now
`Plantoir.Core/Assist/AssistToolRunner.cs` — the preview, deploy and
reference rules every client's call meets on this side of the server. Not a
pure move (the plan review's H3): the seams stay on `AssistAgent`, where both
windows and five test classes set them, and are handed to a runner per call;
the runner RETURNS whether the work was handed to the app instead of setting
the agent's flag, and the agent appends exactly one `tool` message for
whatever came back. Gated on `AssistScenarioTests`, `ReferenceRefusalTests`,
`AssistAgentTests`, `PreviewWhileDeployingTests` and
`RelativeDayFreshnessTests` unchanged and green (118 of 118) before anything
else moved. `AssistSurface { Outside, LocalWindow, Menu }` is in Core.

**Behind the runner: one `plantoir-mcp` per main window (Option B).**
`SectionVerbs` (Core) builds each call in code and runs it through
`AssistToolRunner` on the Menu surface; behind it is a server the window
starts on first use, `McpClient.StartForTheMenu(serverPath, folder)` — no
`--course` and no door variable, so it takes NO assist lease
(`Program.cs` takes one only when it holds a course), `PLANTOIR_SURFACE=menu`,
and it is NOT registered in `WindowServers` (that list tells the assistant
window's lease apart from an outside session's, and this server holds none).
The server's request filter — `ReferenceWriteGate`, `OutsideChangeGate` — is
the same entry every client meets. Its undo list is the window's Undo Last
Change; `DropVerbs` stops it when the window opens another folder or closes,
and its undo list goes with it (the mac's decision 4) — once any change
running then has finished, and off the interface thread
(`SectionVerbs.DisposeWhenIdleAsync`): stopping it at once killed the server
three seconds later, mid-write, with `WaitForExit` blocking the window's
thread (2B's implementation review, L4). **Measured cold start**
on this PC (Intel i5-8365U, Windows 11 Pro 26200, Debug x64 build,
2026-10-15): spawn to the `initialize` answer **476–490 ms** over six runs,
`tools/list` answered 20 ms later — so the first menu item of a window's
life pays half a second once, behind the dialog's "Working…".
REJECTED, with the reason:
- **The tools in-process** (`PlantoirTools` inside the app): the app would
  reference the server's executable and the SDK, and the two gates live in
  `Program.cs`'s filter lambda, so a second path would skip them — the mac's
  own reason for one entry.
- **`AssistAgent` with a null model**: drags a conversation, a transcript and
  a system prompt into a menu click, for nothing.
- **Sharing the assistant window's server**: a teacher with no assistant has
  no such window, and it would interleave two undo lists.

**Where the last change was made travels in `_meta`.** `UndoHistory.Entry`
carries files, not a section (a shared page's flag lives in a file no section
owns), so the server records the call's own course and section against each
new top entry (`AssistWorkspace.NoteWhereTheLastChangeWasMade`, called by
`PlantoirTools.AfterCall` from the request filter), and the menu's server
sends `plantoir.app/lastChange` (`"CODE/N"`, or null) and
`plantoir.app/changesToUndo` on every answer, and `plantoir.app/changed`,
whether the call changed anything. `SectionVerbs.LastChange` greys Undo Last
Change everywhere but that section (`lastChangeIsHere`), and `changed`
decides the trail's ending: "carried out" or "changed nothing", and for Undo
Last Change "took the last change back", "took part of the last change back"
or "changed nothing". It was the undo list's DEPTH before and after until 2B's
implementation review (M1) found it wrong twice: Make Room for Classes keeps
no undo entry, on purpose, so a room really made read "changed nothing"; and
`UndoHistory` keeps twenty, so from the twenty-first change the depth stops
growing and every change read the same way. The server knows: a call changed
something when the top of its undo list is a different entry afterwards (a
new one however deep the list, or one taken back), or when the call noted a
write that leaves no new entry (`AssistWorkspace.NoteAChangeWithNoUndoEntry`).
For anything but Undo, the depth is only the fallback for an answer without
the key. None of the three keys is sent to an outside client. Rebuild
Preview's ending is the one that reads a sentence: it compares the answer with
`AssistWording.PreviewIsRebuilding`. Pinned by
`SectionVerbsTests.MakingRoom_IsCarriedOut_ThoughItKeepsNoUndoEntry` and
`TheTwentyFirstChange_IsCarriedOut_ThoughTheListStaysAtTwenty`.

**Writes with no new undo entry, and Undo's three endings (#550, the mac's
#531, 2026-10-16).** Five paths note a write that adds no entry, and each is
pinned:
- **Make Room for Classes**, when it wrote anything. Since #550 a new page
  whose save FAILS is carried past and named, like the renames and the dates
  already were. Until then that one `Save` was not in a try, so a failure
  after the renames threw past the note: the line said "changed nothing" about
  a renamed section, and the teacher was told Guarded's "That couldn’t be
  read". Only the stand-alone call carries it past. `ApplyDuplicateClass`,
  which calls the same insertion, still notes the change and THROWS, because
  carried past, it would find no page of its own and say "the place for the
  copy is still taken" about a plain write failure
  (`InsertClassesTests.MakeRoomWhoseNewPageCouldNotBeSaved_IsCarriedPastAndNotedAsAChange`,
  `ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken`).
- **A partial undo.** `UndoHistory.Undo` keeps the entry when any file was
  left alone (since #564 a file an earlier press already put back no longer
  counts), so `undo_last_change` notes the change exactly when it answers
  `undidPartly`: files both put back and left alone.
- **A publish or hide that wrote and then stopped part way**, both the page
  list (`AssistWorkspace.Apply`) and the whole unit (`ApplyWholeUnit`). The
  recording is abandoned on the throw, so the top entry does not move. Each
  tracks whether a file has been written yet (`wrote`, and the whole unit's
  existing `changedAnything`). On an `IOException` or
  `UnauthorizedAccessException`, `StoppedWhileWriting` notes the change and
  rethrows, so the teacher still hears `PublishStoppedPartWay`.
- **Re-date Classes… that stopped part way** (`ApplyReDate`). After the first
  page is written it notes the change and throws an `AssistRefusal`:
  `PublishStoppedPartWay("the section's class dates", …)` with its way back,
  then "The pages already re-dated:" and the pages, which are the mac's words.
  It is an `AssistRefusal` so that both callers ANSWER it, each through its
  own `catch (AssistRefusal)`: `re_date_classes` and `roll_over_section`.
  Neither goes through `Guarded`. (The plan said the re-date's error reached
  the teacher "through Guarded", and that was wrong. Before #550 both tools
  let an `IOException` escape, and the teacher's assistant got the SDK's
  generic "An error occurred invoking '…'" protocol error. Neither tool ever
  said "That couldn’t be read".) Any OTHER `IOException` in the re-date
  still escapes, for example one from `TimetableMemory.Write`; that predates
  #550. `TimetableMemory.Write` runs BEFORE the loop, so the remembered dates
  have changed even when no page has. That is true on the mac too, and the
  "Nothing was changed" below is about pages.

**A first write that fails says the mac's "Nothing was changed: {reason}"**
(`AssistWorkspace.NothingWasChanged`, with "Plantoir doesn’t have permission
to change one of them." for a permission). That covers a re-date and a
roll-over, and since the director's ruling on review F8 it covers a publish or
hide too: page list, whole unit and `publish_class_on`. Those had said
`PublishStoppedPartWay` for every `IOException`, which is false when nothing
was written. Its trail ending is "changed nothing". `OnlyPartlyDone` and the
re-date now share one composition, `AssistWorkspace.StoppedPartWay`, so the
way back (Backups on the menu, Restore Section in the window, nothing for an
outside assistant) is decided in one place.

**Undo's ending comes from the depth plus `changed`**
(`SectionVerbs.Ending`). The depth went DOWN means the entry came off: "took
the last change back". `UndoHistory.Undo` removes the entry exactly when
nothing was left alone (a file already back does not hold it, #564), so a whole undo lowers the depth by one at any depth; the
cap of twenty trims only when an entry is added. `changed` with the depth
unmoved is "took part of the last change back"; anything else is "changed
nothing". It used to count an answer containing "is put back" as a whole
undo, and `UndidPartlyFromTheMenu` (the twin the menu shows) contains those words too, so
a partial undo read as a whole one. Until #564 a second press after the edit
was undone was partial AGAIN: the file the first press restored no longer
matched what the change wrote, so it was skipped and the entry stayed for
good. Russell ruled on mac [#555](https://github.com/russellgordon/plantoir/issues/555)
(option 2) that a file already holding its BEFORE text is ALREADY BACK, and
since #564 the second press takes the change off ("took the last change
back") — see "Undo: three verdicts, not two (#564)" below. Pinned by `SectionVerbsTests.APartialUndo_TookPartOfTheLastChangeBack`,
`APublishThatStoppedPartWay_IsCarriedOut`,
`AWholeUnitThatStoppedPartWay_IsCarriedOut`,
`APublishWhoseFirstWriteFails_SaysNothingWasChanged`,
`ReDateThatStoppedPartWay_SaysPartWayAndListsThePages`,
`ReDateWhoseFirstWriteFails_SaysNothingWasChanged` and
`TheEnding_PrefersWhatTheServerSays_OverTheDepth`; by
`RolloverWebsiteTests.RollOverThatStoppedPartWay_IsAnsweredNotThrown`,
`RollOverWhoseFirstWriteFails_SaysNothingWasChanged` and
`ReDateWhoseFirstWriteFails_SaysNothingWasChanged`; and by
`PublishStoppedPartWayTests.APublishWhoseFirstWriteFailsSaysNothingWasChanged`.
Thirteen of these were red on the old code (MEASURED). A test that forces a
write to fail holds the page with `FileShare.Read`, never `FileShare.None`:
None also blocks the backup's zip and the plan's read, so the call fails
before the write it exists to exercise (measured by the plan review).
REJECTED: a new `_meta` key for "the entry came off", because the depth
already says it, deterministically. Also REJECTED: one writes-signal from
`UndoHistory.Abandon`. It would be one place instead of four, but it would
miss Make Room and a partial undo, and it would hide which paths are covered,
whereas the mac pins each path.

Since #548 a page plan from the menu's server also carries
`plantoir.app/planTable`, its rows for the plan's table ("The plan as a
table", below).

**One sentence outside the contract, deliberately: `SectionVerbs.CouldNotBeDone`**
("That could not be done just now. Try again in a moment."). It is what a
menu item ends with when this window's `plantoir-mcp` could not be started or
went away under the call — a Windows mechanic (one server process per window,
Option B above) that the mac, whose runner is in-process, cannot meet. A
contract key would be a sentence one platform could never say; the trail's
"ran from a menu … could not be done: <reason>" line carries the reason
(2B's implementation review, L5).

**Pages by folder and name — a server fix (the plan's finding 0.8, review
M3).** The menu sends `section1/All Classes/Unit 2, Day 3` as a JSON array.
`PlanPublish` already read a course-relative path; `AssistWorkspace.Page`
(re-date's and the read tools' lookup) did not — it resolved a slashed name
against the WORKING folder only. It now also resolves it INSIDE the course
(`PagePaths.ResolveInside(course.DirectoryPath, …)`), treats a
`section<M>/` prefix that is not this section as no page, keeps the How I
Teach refusal, and answers only a page this section lists. Pinned by
`SectionMenuServerTests.APageNamedByItsFolderIsTheOneTicked_NotItsDuplicateTemplate`
(a `_DUPLICATE ME` page named by folder) and
`PageByFolder_ResolvesInsideTheCourse_AndRefusesAnotherSectionsPrefix`.
`AssistSurfaceContractTests` and both digests (`scripts/test_tool_surface_digest.py`)
did not move: no schema or description changed.

**The menu's voice, on the server.** `AssistWorkspace.Surface` replaces the
bool `ServesTheLocalWindow`, which stays as the question most callers ask
(`Surface != Outside`); `SpeaksFromTheMenu` picks the twins (helpers in
`AssistWorkspace.Menu.cs`): the undo five in `UndoLastChange`, pages whose
settings cannot be added to (including the plan's own sentence, through
`PublishPlan.FromTheMenu`), new dates not set, pages a change could not
finish, no page / no pages called (by the name TICKED — the part after the
last slash — joined with "and"), no class on a day (`"Monday, 2026-09-14"`,
weekday and ISO day, invariant and Gregorian, `AssistWording.MenuDay`), Make
Room's card line, and `restoreFromBackupPutsItBack` after a publish that
stopped part way. App side, the runner composes two: `sectionIsChangingFromTheMenu`
(the in-app assistant's write refused) and `courseIsBeingCopiedFromTheMenu`
(Rebuild Preview under a copy lease). `changedWhileSavingACopyFromTheMenu` is
declared and has no Windows call site: Windows re-plans after saving a copy
only for Get Ready for the Start of the Year, which the menu does not run
through the tools. The scenario runner's default surface stays OUTSIDE and
`surface: "mcp"` is mapped explicitly (review H2), so no green scenario moved.

**A copy before EVERY change.** On the Menu surface
`BackUpOnceForThisConversation` makes a fresh `_menu-section<N>` zip each
time, under the same `copying` lease as the assistant's, with a "section menu
backed up a course" line, never recorded as held; `PruneBackups` keeps five
of the assistant's and five of the menu's, counted apart. **The same-second
name is now READ, and the writer still waits.** #187 (above) rejected `-N`
because the mac's reader would hide a zip Windows wrote; the mac now writes
`<time>-2` itself and reads it, so that reason has expired in one direction:
`BackupItem.From` reads `-N` (N ≥ 2; `-1` and `-x` still unread) so a copy
the mac made is listed, counted and restorable here. Windows' own writer
keeps waiting for the next second — it never collides, and changing it buys
nothing a teacher sees. Two menu changes in one second measured as two zips a
second apart (`SectionMenuServerTests.EveryChangeSavesItsOwnMenuCopy_AndSaysSoOnTheTrail`).

**The claim is in-process.** `SectionMenuActivity` (Core, static) holds a
section while a menu CHANGE runs (plans only read); the in-app assistant's
write to it is refused before anything is backed up. `AssistActivity.ReportWork`
is set by the assistant window around every turn, approval and decline, and
`verbIsRunning` is this window's runner, any window's claim, or the
assistant working. Both windows are this app, so a static set answers in a
microsecond and needs no file; another program's work is the work leases'.
The menu does not hold the assistant's backups.

**Rebuild Preview really rebuilds — and so does the assistant now (Q1).**
Before, `rebuild_preview` reached `StartPreviewIfIdle`, which returns at once
while a preview serves, and still said "rebuilding" (the plan's finding 0.7).
`SectionDetailView.RebuildPreviewAsync` stops a serving preview and starts it
again; `MainWindow.RebuildPreviewFor` is the seam (`RebuildPreviewInApp`),
used by Section ▸ Rebuild Preview, by the in-app assistant's
`rebuild_preview`, by the fixed phrasing matched as `rebuild_preview`, and
by "rebuild / refresh / update the preview" (plain "preview" and "show me the
preview" still only show one). A behaviour change for the assistant, written
up for the mac as a question (does its `rebuild_preview` restart a serving
preview?). A page change from the menu follows the runner's rule for every
client: a showing preview is stopped, the tool runs with `preview: false`,
and the preview starts again.

**How the shared scenario reaches this seam (#549, 2026-10-16).** The mac's
#528 scenario ("rebuild with a preview serving stops it and starts it
again") expects `stopPreview.begins`, `stopPreview.ends`, `startPreview`.
Here the runner calls `RebuildPreviewInApp` and returns at once, so the
runner never awaits the stop itself; `AssistScenarioTests` wires a fake that
does what `RebuildPreviewAsync` does — await the stop when a preview is up,
then start — and awaits that work before reading the events. The fake can
only mirror the order, and **no test holds the real window's**: the
await-then-start lives in `SectionDetailView.RebuildPreviewAsync` and is held
by reading that code. `SectionVerbsUiTests.RebuildPreviewRebuildsAServingPreview`
(opt-in, part of no gate) proves something narrower — that a serving preview
really ends up showing an edit after Section ▸ Rebuild Preview, with its trail
line — and never sees a stop or the order. REJECTED: making the runner await
`StopPreviewInAppAsync` and then call `ShowPreviewInApp`, so the harness
would only note what the runner calls. `RebuildPreviewFor` is more than stop
and show — it refuses while the folder is getting ready (#473), selects the
section, and will not start a preview in a view replaced during the stop —
and Section ▸ Rebuild Preview shares it, so splitting it into the runner
would move those guards out of the window for both callers.

**The dialog is ONE `ContentDialog`** (`Views/SectionVerbDialog.cs`) moving
through Choose → Plan → Working → Result (Working says "Working…", and "Saving a
copy of ICS3U first…" only while the server's progress line says so — Undo
never saves a copy, and a refusal comes before one; review M2): a stage changes by cancelling the
button's own close and doing the work under its deferral, because WinUI shows
one dialog at a time and refuses a second asked for while the first closes.
The Plan stage is the plan twin's card as text, except for Publish Pages…,
Hide Pages… and Publish Class for a Date…, whose plan is a table since #548
("The plan as a table", below).
While a call runs no button is drawn and Escape does not close it. A plan
twin that refuses ends with its sentence and OK alone. Publish Pages… and
Hide Pages… list classes first (by date), then the rest by folder, two pages
of one title told apart by their folder; Publish Class for a Date… offers the
next class day from the section's dates (tomorrow with none) in a
`CalendarDatePicker`; Make Room… asks the class and 1–10. Class dates first:
Add Next Class, Re-date Classes… and Make Room… open THIS window's
`SectionScheduleDialog` with the reason (`datesForTheNextPage`,
`datesToReDate`, `datesToMakeRoom`, club twins) when none are on file, and
run once they are written; the dialog after it retries while the dates
dialog is still closing, rather than drop the change's answer.

**Trail**: `RanFromAMenu` ("UIVERB/1 · Section ▸ Publish Pages… — carried
out, 1 page ticked"; endings carried out, changed nothing, took the last change
back, took part of the last change back (#550), cancelled at the plan,
rebuilt, not rebuilt, opened) and
`SectionMenuBackedUpACourse`. The second is written by the window's
`plantoir-mcp`, which `--state-dir` does not reach (`AppDataRoot` does not
cross processes), so a UI test's copy line lands in the PC's own trail.

**Testing it**: unit — `SectionVerbsTests` (calls, the runner entry, Undo's
place, the trail, the claim, Rebuild's two answers), `SectionMenuServerTests`
(folder-named pages, a copy per change, the voice, the surface variables),
the wording walk (55 keys declared; the 17 #475 keys were ledgered for 2C,
which declared them).
Through the window (`SectionVerbsUiTests`, 2026-10-15, this PC, both
passing, 2 min 5 s): Publish Pages… → tick → plan → Publish → the flag
changes on disk, one `_menu-section1` zip, Undo Last Change live and putting
the page back; and Rebuild Preview with the REAL launcher — a serving
preview, an edit on disk, Rebuild Preview, and the edit served.

### The plan as a table (#548, the mac's #524)

Section ▸ Publish Pages…, Hide Pages… and Publish Class for a Date… show
their plan stage as the mac has since #524 (`documentation/09-mac-app.md` →
"The plan as a table (#524)", which has the row order, the mac's
measurements and what it rejected): a summary line (`menuPlanSummary` and its
shapes), a read-only table with one row for EVERY page the plan is about —
the changes, the pages an unpublish keeps with their reason, the classes a
publish left as they are, the pages with no room for a key, the pages already
right — and the card's other sentences under it. The card listed 15 changes
and then "…and N more"; the table lists all of them. Re-date Classes… and
Make Room for Classes… keep the text card, and so does the assistant's
Go/Cancel card. Nothing changed in what Publish does, in the model's text, or
on the trail (`ranFromAMenu`: the mac's reasoning, and its rejected count of
pages that would change, hold here too).

**The rows travel in `_meta`, because the plan is in another process.** On
the mac `SectionVerbs` runs the tools in-process and the sheet reads
`AssistToolOutcome.planTable`. Here every menu call goes through the window's
own `plantoir-mcp` (Option B, above), and the dialog never holds the
`PublishPlan`. So the server builds the rows — `PublishPlan.Tabulate`, beside
`Describe()`, from the same stored properties and the same `AssistWording`
pieces — and `PlantoirTools.Proposing(PublishPlan)` sends them as
`plantoir.app/planTable` (`AssistToolAnswer.PlanTableKey`, read by the one
`AssistToolAnswer.FromResult`) ONLY when `workspace.SpeaksFromTheMenu`, beside
the card and never instead of it. The precedent is `plantoir.app/nextClass`
(#440). The text content — what a model or Claude Code reads — is the same
bytes on every surface (`SectionMenuServerTests.TheTextContentIsTheSameWithOrWithoutTheTable`),
and neither the assistant's server nor an outside one sends a table
(`ThePageAndDayPlansCarryATable_OnlyFromTheMenu`). A plan without one — a
whole unit (`WholeUnitPlan` answers with text), or a table that will not
parse (`PlanTable.FromJson` returns null) — shows the text card. REJECTED:
parsing `Describe()` back into rows (titles hold quotes and commas, and a
parse is a second reader of a format that changes — the mac's reason);
putting the rows in the text content (that moves the model's bytes, a
routing change); building the plan in the window with an in-process
`AssistWorkspace` (it would skip the server's reference-course gate and
outside-change hold, which are its request filter — the mac rejected
`SectionVerbs` calling the planner for the same reason); a second tool or
round trip (one call already carries everything).

**The card is built from the same pieces, and did not move.** `Describe()`'s
three inline literals became `AssistWording.PlanNothingWouldChange`,
`PlanWillBecome(visible, withTheDatesOf)` and `PlanStaysVisibleBecause`, and
the selections the table also reads (`ClassesWhoseDatesAreTakenBy`,
`LeftAlonePages`, `OrphanedDateMoves`, the orphan and no-such-page lines)
were extracted, so card and table read one copy. MEASURED with a throwaway
characterisation test (not committed — a golden file would be the
assistant's sentences typed into a test): 1,252 lines of `Describe()` and
`Describe(3)` over 21 branches × publish/hide × menu/not, byte-identical
before and after; one extra space in `PlanStaysVisibleBecause` changed 112
of them, so the run could see a change. The lasting guard is
`PlanTableTests.EveryCellIsTheCardsLineWithoutTheName` (each cell is the
card's line for that page with the name taken off; `Describe(int.MaxValue)`,
because the card stops at fifteen) and `EveryNoteIsALineOfTheCard`.

**How the 16 keys map** (`ContractTests.AssistWording_MatchesContract`):
twelve are constants of the key's own name, compared by value by the walk —
including `menuPlanStaysAsItIsForAMeeting` and `menuPlanSummaryOnePage`,
whose samples vary nothing. `menuPlanSummaryHiding` is a method the
dispatcher `MenuPlanSummary` really returns, the convention
`PagesWhoseSettingsCannotBeAddedTo` → `…NamingSeveral` set. The four methods
have hand-written assertions, the Key Links reason rendered from the
planner's own `AssistWorkspace.KeptBecauseInKeyLinks`. `PlanWillBecome`, the
mac's keyless `planWillBecome(visible:withTheDatesOf:)`, is the one
`WindowsOnlyWording` entry. No `NamedGapLedger` entry: the ledger is for work
a later milestone owes, not a permanent mapping.

**A club's table says "meeting" — and since #556, so does its card.** The table is the
teacher's copy and never the model's, so `Tabulate` takes the course's noun:
the left-alone cell (`menuPlanStaysAsItIsForAMeeting`), its note
(`linkedClass…LeftAloneForAMeeting`) and a kept class's reason ("it is a
meeting of its own", `AssistWorkspace.MeetingOfItsOwn`, rendered with
`PlanStaysVisibleBecause` to the contract's `linkedClassStaysVisibleForAMeeting`)
— as the mac's `stayingVisibleLine(noun:)` does. Until #556 Windows' CARD
did not, so in a club the table and the card under it said "meeting" and
"class" for the same page. Now `PublishPlan.Describe(ClassNoun, int)` is the
teacher's card in the course's noun, and the kept reason goes through
`PublishPlan.ReasonFor`, the ONE expression the card and the table both use;
`Describe(int)` is the class form. The planner still RECORDS the class form
(`AssistWorkspace.ClassOfItsOwn`), because that is what the model reads.
`plan_publish_pages`, `plan_unpublish_pages` and `plan_publish_class_on` all
end in `PlantoirTools.Proposing(PublishPlan)`, which now sends
`Proposing(plan.Describe(), plan.Describe(noun))`: the text content (what the
model and Claude Code read) is the class form byte for byte, and the club's
card travels only in `_meta`, as every other club card does (#274). The
answer for "nothing would change and a name fits no page" can carry the
left-alone line too, so it is `Answering(card, model copy)` as well — the mac
nouns that card (`AssistToolRunner.swift` 1007-1010, 1132-1135, 1173-1176).
Measured rather than assumed: `Describe()` was printed for every branch
(publish and hide, menu or not, nothing changes, declined only, one and two
left alone, unknown names, an orphaned date move, more than fifteen changes
and fifteen kept, a kept page with a folder) before and after the change, and
the two outputs were identical. Pinned by `ClubNounTests` (the three plan
tools and the unknown-name answer in `TheNounNeverReachesWhatTheModelReads`,
and `AClubsPublishCardSaysMeetingForLinkedClasses`) and
`PlanTableTests.AClubsTableSpeaksOfMeetings`. The table's own output did not
move. No trail change: no event records a card.

**Two differences from the mac, kept on purpose so neither side "fixes" them.**
(1) The summary says `planNothingWouldChange` when no page changes, even when
pages were declined; `Describe()` deliberately says nothing there in that case
(#308, `DeclinedPagesAreNamedTests`), because "no page would change" reads as
"already right" about pages it declined. The table's summary is a count, the
declined pages are rows of their own beside it, and the mac accepts the same
difference. (2) The Folder cell is `AssistWorkspace.FolderOf` — the folder
from the course folder, and the COURSE CODE for a page at the course root,
which is the mac's `StartOfYearPageNaming.folder` — while the choosing
stage's `MenuPage.Folder` gives "" for a root page. Left as it is.

**The control: a plain `ListView` of `Grid` rows**, modelled on All Backups:
`SelectionMode = None`, a header `Grid` of sort `Button`s above it (margin
13 = the table's 1-epx border plus the rows' 12 of padding), columns Page 170,
Folder 150, What changes the rest, each cell trimmed with its whole text in a
tooltip (as the mac), each row `sectionVerbPlanRow<plan position>` and named
"title, folder, what changes" for Narrator. No alternating backgrounds
until #634, which banded it (and the picker before it, which since #634 is a
`SelectionMode = Single` table of its own — "The picker as a table, the plan
folds, the dialogs follow the window", below); since #634 too the column
widths are set from the dialog's width rather than fixed. REJECTED: `ItemsView` (no columns or header either, and no precedent here);
a toolkit DataGrid (no toolkit package is in the project, and a dependency
in the self-contained bundle for one read-only list that the app already
draws by hand buys nothing a teacher can see — and would be Russell's call).
**Sorting** is `PlanTableOrder` (plan order first; a new column ascending,
the same one flipped; numbers in a title compared as numbers, "Day 2" before
"Day 10", as the mac's string comparator does; ties by plan order).

**Width: at most 680 epx, pinned at construction for the three items** (the
`ContentDialogMinWidth`/`MaxWidth` resources, the `NewCourseDialog`
precedent), so the dialog is the same width at every stage — the mac rejected
widening mid-flow because the sheet jumps. On a window narrower than 680 + 2 ×
24 epx it takes the window's width less 24 at each side (at 175% and 200% a
1920-pixel screen's default window is about 680 and 595 epx wide). The panel
stretched to it. **Superseded by #634:** the width now follows the window
(680 at its 900-epx minimum, up to 980), carried by a host `Grid` inside the
dialog at every stage, because the template reads those two resources once —
see "The picker as a table, the plan folds, the dialogs follow the window".

**Height: what fits the window — a deliberate departure from the mac's fixed
12 rows.** ContentDialog's content `ScrollViewer` has its vertical scrolling
DISABLED in the template: content taller than the dialog is clipped from
OUTSIDE, where no scroll bar can reach it. A Windows window is often short:
the default window on this PC (Windows 11, 1920 × 1080 at 150%) was 793 × 483
epx when this was written, a XAML root 446 epx tall — since #542 it opens at
its 900 × 600 epx minimum, a root of about 563, and 446 is kept here as
a shorter root the layout is still written to survive. So everything on the plan stage has to fit,
and `PlanTableLayout.For` (Core, unit-tested) decides how much of each part
shows. The NOTES give way first, to keep four rows (`PreferredRows`): their
cap is clamp(min(H, 756) − 230 − 2 − 8 − 4 × 32, 40, 120) epx, and it is the
notes scroller's `MaxHeight`, so a note cut short scrolls into view. Then the
ROWS: clamp(floor((min(H, 756) − 230 − 2 − shown notes − 8) / 32), 2, 12)
(`FewestRows` 2), after which the table scrolls inside itself. 756 is
ContentDialog's own maximum height (since #634 the page dialogs raise it, and a
window taller than 756 gives every further 32 epx to the table as one more
row — `PlanTableLayout.ExtraRows`; under 756 every count here holds); 230 is everything else on the stage
(measured 220–222). The counts are made again on `XamlRoot.Changed` while the
plan shows, so a window resized under the plan does not clip what was counted
for its old size; the handler is on the WINDOW's XamlRoot, so it is attached on
`Opened` and taken off in the dialog's `Closed` (since #634 `SetContent` swaps the
relayout for each stage instead) — a close at the
plan changes neither, and it would otherwise stay for the window's life
(the third review). No unit test reaches that: it is window code.
`PlanTableTests.EverythingFitsWheneverTwoRowsAndTwoLinesOfNotesCan` pins the
layout: whenever the window can hold the chrome, two rows and 40 epx of notes
(a XAML root of 230 + 2 + 64 + 8 + 40 = 344), the whole stage fits; a plan
with no notes or a short one fits lower still (`AShortWindowShowsFewerRowsAndStillFits`,
330). Below that the floor wins and the bottom is clipped while the buttons
still show. By arithmetic, not measured, ON THE PREMISE THIS WAS WRITTEN
UNDER — that the default window is a fixed number of PIXELS, about 724 tall
(483 epx at 150%): at 175% it would be about 414 epx and at 200% about 362,
less about 37 epx of title bar and border — XAML roots of about 377 and 325.
At 175% everything fits; at 200% a plan with long notes is about 19 epx short
and loses the notes' bottom edge. **Since #542 that premise no longer holds:**
the launch size is clamped up to the 900 × 600 epx minimum at every scale, so
the default window no longer makes a short root. The minimum is itself clamped
to the display's work area, so the short-window case now arises only where the
WORK AREA is under 600 epx tall — a 1080p screen at 200% is 540 epx — and
there the 325-ish root above is still the one the layout meets. (This replaced two
earlier versions. The first capped the notes at a fixed 120 and counted the
rows once; the #548 implementation review found it clipped long notes out of
reach at the default window, a floor of 4 rows winning against notes over
about 88 epx. The second kept 4 as the floor for the rows too, which the third
review found still clipped below a root of 408.)

MEASURED through UI Automation, 2026-10-16 (`PlanTableUiTests`; UIA hands the
non-DPI-aware test process 96-dpi coordinates, so these are epx). Row pitch
32 epx (UIA rounds it to 31 or 32). The 19-row fixture with one short note, at
the 793 × 483 window the app opened at when this was written: 5 rows, the table's bottom 157 epx above the window's, the
note's 131, Publish's 49; the chrome measured 220–222 epx against the 230
budgeted. The window resized UNDER the open plan, asked for 300 epx, stopped
at 900 × 600 (XAML root 563), and the table grew from 161 to 290 epx (5 to 9
rows), with everything inside. Whether that minimum is applied in epx or
pixels, and why the default window opens below it, is settled under #542, not
here; these are the numbers this piece saw. The 31-row fixture whose note
named thirty linked classes (112 epx laid out), AT THAT 793 × 483 WINDOW: 4
rows, the notes given 78 epx and their viewport showing 70% of them, scrolled
to 100%, and the notes area inside the window (UI Automation clips a note's
rectangle to the viewport, so the note's own rectangle cannot show more than
that); Publish 35 epx above the window's bottom. **Since #542 the window opens
at its 900 × 600 minimum (XAML root about 563)**, and there a 112-epx note fits
whole beside 5 rows — correct behaviour, and it left
`LongNotesScrollToTheirEndInsideTheWindow` failing on "the notes do not
scroll" in the full UI run of 2026-10-16 on `dev` b0af8d3fd (window 900x600;
notes area 112; note 112 tall). The product was right and the FIXTURE too
short, so it now links seventy classes: a note well past the notes' 120-epx
cap, which scrolls at ANY window height rather than only at the one it was
first measured at. MEASURED at 900 × 600 (root 563), 2026-10-16: a 243-epx
note, the notes capped at 120, their viewport showing 49%, scrolled to 100%;
6 rows shown of 71; Publish 42 epx above the window's bottom. Earlier the same day, over a 200% remote session (window 937 × 625
epx), 10 rows.

**Return and Escape with the table focused — measured, and one key needed
handling.** First built with no key handling and driven with real keys. Escape
with a row focused closed the dialog with nothing written and the trail's
"cancelled at the plan" line — it reached the dialog. Return with a row
focused did nothing for 60 s: the `ListView` kept it. So Return is caught in
the list's `PreviewKeyDown` — tunnelling, before the list sees it, as
`CopyAPageDialog` does for the AutoSuggestBox and Escape — and runs
`Advance()`, the verb button's own body (extracted from `PrimaryPressed`, which
now awaits it). Handled there, the key never reaches the dialog as well:
`ReturnWithTheTableFocusedPublishesEveryPage` publishes the 17 pages with ONE
`_menu-section1` copy and ONE "carried out" line. Reaching into the template
for `PrimaryButton` was rejected (template-dependent). **The focus also had
to be placed:** on the first drive, Tab went round the main window BEHIND the
dialog — the element that had the focus was in the stage just replaced — so
the table takes the focus when it appears (`list.Focus` on `Loaded`). With
`FocusState.Programmatic`, not `Keyboard`. A picture of each, after a Continue
pressed through UI Automation: `Keyboard` drew the focus ring on the first
row; `Programmatic` drew none, because it follows the last input, so a mouse
user is not shown a ring they did not ask for. Not measured: `Programmatic`
after a Continue pressed with a real key. The mac needed neither: its table
takes neither key, and Tab reached it.

**The sort headers stay in the Tab order, after the table** (`TabIndex` 1 for
the table, 2 for the headers), so Tab reaches the rows first; Return on a
focused HEADER sorts, which is what a focused button does on Windows. #548
asks only that Return publishes while the grid has focus. Rejected: taking
the headers out of the Tab order, which would leave a keyboard user unable to
sort. Proven, not assumed (`TabIntoTheTable`): from Cancel, Tab reaches the
table before any header, the next Tab lands on Page's header, and Shift+Tab
goes back to the table. A header's arrow is drawn, so its automation name
says it too: "Sort by Page" until it is pressed, then "Sort by Page, sorted
ascending" (or "descending"), so Narrator hears what a sighted teacher sees.

**Testing it**: unit — `PlanTableTests` (row order publishing and hiding, no
cap past fifteen, the summary's counts, the card/table anti-drift guards, a
club's meeting forms, JSON both ways, the sort, the natural order),
`SectionMenuServerTests` (the table from the menu only, the text content
unmoved, none on an answer that is not a plan), the `ContractTests` block, and
the layout (`PlanTableLayout`: everything fits whenever two rows and two
lines of notes can; long notes scroll at the default window; a tall window
shows 12). Through the window (`PlanTableUiTests`, opt-in, 4 of 4 on this PC,
2 min 20 s): the table, its fit, the last row shown inside the table after
scrolling, the Tab order and Escape; Return; the headers' names and order, and
the rows recounted when the window is resized under the plan; long notes
scrolled to 100% with their area inside the window.
`SectionVerbsUiTests.PublishPagesTicksPlansAndPublishes_…` still reads
`sectionVerbPlan`, which is the summary now.

### Classes dated after the next class, at Deploy (2C, 2026-10-15)

The mac's #475 ([09 → "Classes dated after the next class, at Deploy
(#475)"](09-mac-app.md), [10 → "#475 at the assistants' deploy"](10-local-ai-assistant.md)):
a class page students can see, dated after the NEXT class day, is caught
before it goes out. The rule is `class-planning.json` → `futureDatedClasses`
(`ClassesDatedLater` in Core; `FutureDatedClassesContractTests` runs the 24
cases on real files, which were unrun here until now); where and in what order
the teacher is asked is `shared-rules.json` → `classesDatedLater`; the answer is
remembered in `.publish_state/section<N>.later-classes-kept.json`
(`file-formats.json` → `laterClassesKept`, `LaterClassesKept`, released on
rollover with the links checklist's answer under the same undo entry). This
part is what Windows did differently, and why.

**Two readings that would pass review and are wrong.** The date is the first
ten characters of `created` AS WRITTEN — never `AssistWorkspace.DateOf`, whose
`DateTimeOffset` parse is the same day today but is a moment, not a day, and is
one refactor away from converting. And "today" is never read inside the rule:
`ClassesDatedLater` takes it from the caller, `AssistWorkspace.Today` is
injectable, and the scenario runner pins 2026-10-08 — a fixture laid out around
the real clock is the "Three testing lessons" trap, which turned dev red for a
morning once already.

**The order in `SectionDetailView.DeployAsync`, and why.** Every refusal
first — reference course, the folder still getting ready, another program
building, saved settings that cannot be read, a destination that cannot be
deployed to — then the question, then the saved-settings notice, and only then
the console claimed and the preview stopped. Hiding is a change (a copy of the
course and a write), so a question before a refusal would let a refusal follow
a change; a question after the stop would make Cancel cost the teacher the
preview they were reading. The saved-settings notice and its "deployed using
the saved settings" line moved AFTER the question (the plan review's M4): a
Cancel must not leave either behind. A second Deploy press while the question
is up returns at once (`_isAskingAboutLaterClasses`; `_isPreparingDeploy` is
still false at that point). `ClassesDatedLaterAtDeployTests.TheWindowsDeploy_AsksAfterItsRefusals_AndBeforeItClaimsOrStopsAnything`
reads that order from the source, as `ReferenceRefusalTests` already did for the
reference refusal — the window cannot be built in a unit test.

**`DeployWillBeRefused()` (the plan review's H1).** The in-app assistant asks
BEFORE it presses Deploy, and on this side most of the deploy's refusals live
in the window, not in the runner. So the window offers a side-effect-free
reading of all of them — nothing claimed, shown or written — and
`AskAboutClassesDatedLaterForTheAssistantAsync` asks NOTHING when one will
refuse: the deploy then goes on to its own refusal, which shows its dialog and
is the sentence the assistant relays — and the preview is KEPT. The seam's
record says so (`LaterClassesAtADeploy.WillBeRefused`) and the runner skips its
stop: stopping the preview for a deploy that never starts would cost the
teacher the page they were reading (2C's implementation review, L-1;
`ClassesDatedLaterAtDeployTests.ADeployTheWindowWillRefuse_KeepsThePreview_AndLetsTheRefusalSpeak`).
`IsSectionBusy` counts a deploy being prepared (`_isPreparingDeploy`) as well
as one running. One check comes BEFORE that reading: a window already asking
this question, or with any dialog up, answers `CannotAsk`, refused with
`deployWaitsForAnOpenQuestion` and nothing stopped
(`classesDatedLater.whenTheWindowIsBusy`). `DeployWillBeRefused()` also counts
the open question as a refusal, so read the other way round the window said
"nothing to ask", the runner stopped the preview and the deploy returned at
once — the review's M-A, pinned by a source-order assertion
(`TheAssistantsQuestion_ChecksForAnOpenQuestionBeforeTheRefusals`). When
nothing is flagged the assistant window never asks the section's window, so
that path still stops the preview first, as it did before #475. The alternative — returning the refusal
sentence from the seam — was rejected: the window's dialog would never be
shown, and the window and the assistant would word the same refusal from two
places.

**The answer, in the window.** Every flagged class is listed ticked, and two
buttons always sit beside Cancel: Hide Ticked and Deploy (the default) and
Keep All and Deploy. Hide Ticked records the unticked as kept, then hides the
ticked with Hide Pages…'s OWN call through this window's `plantoir-mcp`
(`MainWindow.HideClassesForTheDeploy` → `SectionVerbs.Perform`) — so it is
backed up as `_menu-section<N>`, Section ▸ Undo Last Change takes it back, and
pages only those classes link to go with them — with NO preview either side:
`AssistToolRunner.PreviewFollowsAChange = false` skips the stop as well as the
restart (the plan review's M1; a hide that failed would otherwise leave the
teacher with no preview for a deploy that never happened). Its "ran from a
menu" line names Hide Pages…, whose call it is, with "N classes dated later,
at Deploy" as its counts — the mac's own line. A ticked class still visible
afterwards stops the deploy, and the teacher is shown what the hide said. The
"asked about…" line is written AFTER the hide, so a hide that left a class
visible is recorded as cancelled rather than as hidden (the mac writes it
before the hide, so its line can count a class as hidden that is not).

**The in-app assistant always gets a window here.** `AssistWindow.MainWindowForBuilds`
opens a main window on the section's folder when none shows it, so
`deployHasClassesDatedLaterAndNoWindow` is reachable only when no window CAN
show the section (it would not open, or the window ended up on another folder);
the seam then returns `LaterClassesAnswer.NoWindow` with the titles, never
throws. The seam is `AssistToolRunner.AskAboutClassesDatedLaterInApp`
(`Func<Task<LaterClassesAtADeploy>>`): a small record rather than the bare
answer, because the no-window sentence names the classes and only the app side
can read them. Nothing flagged: nothing asked, and no window is brought forward
for it. The window's route on the trail is the contract's "the in-app
assistant's deploy", and `StartDeployForAutomationAsync` passes
`alreadyAsked: true`, so the question is never put twice (M4).

**The server's deploy** (`AssistWorkspace.Deploy`), after its own refusals
and before anything runs: an outside assistant is refused with
`deployHasClassesDatedLater` until the window's answer is on file; Plantoir's
own assistant reaches it only with no window seams at all, and is told
`…AndNoWindow`. The trail line is the contract's: "a deploy was held back for
classes dated after the next class — {N} with no answer" — no "by an outside
assistant" (the plan review ruled for the contract; the mac added who asked
until #532, 2026-10-16, and writes the contract's line too since —
`DeployAsksAboutLaterClassesTests.testAHeldBackDeployIsTheContractsLine`). `publish_class_on`, from any client, and the
links checklist's Publish (`PublishAndRemember`) record a later class they
published as kept: a date the teacher named is not a mistake to catch, and
without it the two questions undid each other (the mac's batch B review,
finding 2).

**A scheduled deploy** reads the classes in `ScheduledRun.Execute` after the
settings decision and before the wrapper runs, on the run's own day, and
writes "deployed with classes dated after the next class: …" only when the
wrapper's record is SUCCEEDED and newer than the run. Never on the exit code,
which is 0 either way (the mac measured gating on it writing the line after a
failed deploy). The record's time is its file's write time, so it is compared
with the real clock read just before the wrapper ran — not `World.Now`, which
tests pin to a morning — with a second's slack; both are local time.
`ScheduledRunTests` runs it both ways, and with an earlier night's success
record that must not count.

**Section ▸ Publish Pages…** asks about the ticked classes after the choice
and before the plan, in the same dialog (a `LaterClasses` stage): the ticked
are left out and stay hidden ("Leave N Hidden and Continue", or "Publish Them
All" with none ticked), the unticked are kept, and with nothing left nothing is
published and the dialog closes.

**Testing it**: unit — `FutureDatedClassesContractTests` (24 cases, the
record's shape, the rollover undo), the four `assist-cases.json` scenarios
(green; the three ledgered ones left the ledger), `ClassesDatedLaterAtDeployTests`
(an open dialog not waited on, no window, the hide with no preview, the server's
hold, what is kept, the window's order), `ScheduledRunTests` (both ways), the
wording walk (17 keys declared). Through the window: `LaterClassesAtDeployUiTests`
— Cancel deploys nothing and leaves the preview serving; Hide Ticked hides one
class, keeps the unticked one and deploys to a folder; Keep All and Deploy, then
a second Deploy that asks nothing.

REJECTED, with the reason:
- **Asking before the window's refusals, or after the assistant's stop**: see
  the order above (the contract's own `rejected`).
- **The seam returning the refusal sentence** when the deploy will be refused:
  see `DeployWillBeRefused()` above.
- **Comparing the success record with `World.Now`**: tests pin it to a morning
  that is not the file's clock, and a real run's two clocks agree anyway.

## The Settings window, Plantoir Help and the Account ID's refusals (#491 part A, #490)

Batch 3A of the catch-up to mac 1.7.1 (2026-10-15). What landed, and why.

**File ▸ Settings… is ONE window** (`Views/SettingsWindow.cs`; Russell's
ruling on #491, 2026-10-15): a `NavigationView` with Assistant, Preview
(since #514, batch 6: "Preview at Last Viewed on Windows" below) and
Deploying. It
replaced a `ContentDialog` (`AssistantSettingsDialog`), whose body moved
unchanged into `AssistantSettingsPane`.

*Why a window and not a dialog.* WinUI shows one `ContentDialog` per window.
MEASURED in the batch's spike (i5-8365U, Windows 11 26200, 150%, Windows App
SDK 1.8.260921001): the limit is per XamlRoot, not per thread — a second
window showed its own dialog while the first window's was up, in either
order, and a second dialog in the SAME window threw `COMException 0x80000019`
"Only a single ContentDialog can be open at any time." The new-course wizard
IS a `ContentDialog`, so a Settings dialog could not open from the wizard's
Open Settings… without closing the wizard and losing what was typed; a
modeless window comes forward beside it, and the wizard follows the ID live.
**Rejected**, on #491 with Russell: a Deploying pane inside the assistant's
settings dialog; keeping the field in a course's settings with a "for every
course" label; and Settings as a `ContentDialog` (above). Settings may show
dialogs of its own for the same reason — but the instructions for finding the
ID are INLINE (an `Expander` holding `CredentialRequestPanel.Build(
CredentialRequests.CloudflareAccountIDHelp)`), not a dialog with a second
field and "Use This ID" as the mac's sheet has: the pane's own field already
does that job.

*One at a time, never keeping the app alive.* `SettingsWindow.Show(section)`
brings an open window forward on that section rather than opening a second.
File ▸ Settings… opens on the section last chosen
(`AppSettings.LastSettingsSection`, the mac's `SettingsPane.storageKey`);
Open Settings… beside the ID always opens Deploying. The app still quits when
its last MAIN window closes; `App.QuitTime` calls
`SettingsWindow.NoteBeforeQuit()` first (it also covers `QuitForUpdate`),
because `Application.Exit` may end the process without raising the window's
`Closed`. The "opened Settings — the assistant is set to …" line is written
once per opening, as the dialog wrote it.

**The Account ID is edited in ONE place**, `DeployingSettingsPane` — "Cloudflare
Pages", the field (placeholder "32 letters and digits", AutomationId
`cloudflareAccountField`, which the course form no longer carries), the inline
instructions, a problem line only for a NON-EMPTY invalid ID (an empty one is
not wrong here: a teacher who never deploys to Cloudflare has no reason to
fill it in), and the mac's footer captions. `CloudflareAccountInSettingsTests.OnlyTheDeployingPane_WritesTheId`
reads every `.cs` under `Plantoir/` and allows a write of the ID — an
assignment or `ChangeCloudflareAccountId(` — in that file only. Before #491 a
course's Deploying section and the wizard each wrote it, and typed in one
course it changed silently for every other. No data moved: the value was
always app-wide (`AppSettings.CloudflareAccountId`), so nothing is migrated.

*Saved as typed, recorded on leaving.* Each keystroke calls
`AppSettings.ChangeCloudflareAccountId(text.Trim())`, which saves and raises
the static `AppSettings.CloudflareAccountIdChanged` — so a wizard waiting on
the ID enables Create the moment it is valid. The pane does NOT listen to that
event, so the trimmed value is never echoed back under the teacher's cursor.
The trail line (`Cloudflare account ID changed in Settings`; the mac's three
lines verbatim from `DeployingSettings.TrailLine`, never the ID) is written by
`NoteTheChange()` on Enter, on leaving the field, on switching section, when
the teacher switches to another window, when the window closes and at quit,
comparing with the ID as it was at the last line — one line for a change, none
for a visit. *Switching windows is its own trigger* (3A's implementation
review, M1): Settings is modeless, so a teacher who types an ID and clicks
back into the main window moves no focus INSIDE Settings and raises no
`LostFocus`; until the window's `Activated` with `Deactivated` was added, no
line was written until Settings closed — possibly hours later.

**Three read-only displays** (`PublishingChoiceView`: the primary Cloudflare
block, the additional-destination row; the wizard shares the view): "Kept in
File ▸ Settings ▸ Deploying, for every course that deploys to Cloudflare
Pages." first, then "Cloudflare Account ID" with the value — or "Not set yet"
in the secondary colour — selectable, and Open Settings… beside it
(`cloudflareAccountValue` / `cloudflareAccountOpenSettings`, and
`additional…` for the row). One private builder, as the mac's
`CloudflareDetailFields`. The account-finding sentence left the course's
caption with the field it explains. The view listens to
`CloudflareAccountIdChanged` while LOADED and raises `AccountRefreshed`, NOT
`Changed`: an ID changed in Settings is not an edit to the course. The wizard
re-reads Create on it (with no ID it keeps refusing with the contract's
"Paste your Cloudflare Account ID." beside Open Settings…); Course Settings
listens itself and re-reads Save only (`RefreshDirtyState`, never
`MarkChanged`), so a held-back Save frees itself when a valid ID arrives.

*MEASURED, and why every Unloaded is checked.* Inside the wizard's
`ContentDialog`, the view's `Unloaded` arrived about 70 ms AFTER its `Loaded`
with the view still on screen (`IsLoaded` true, parent unchanged) and no
second `Loaded` followed. Unsubscribing on it left the wizard deaf to
Settings — `SettingsUiTests.TheWizardWaitsForTheIdTypedInSettings` failed
exactly so, twice, before the fix. An `Unloaded` that finds the element still
loaded is ignored; the real one, when the wizard closed, measured `IsLoaded`
false. Course Settings uses the same check.

**The refusals now name the place.** The in-app deploy
(`MultiDestinationDeployRunner.RefusalReason`) says "… Add it in File ▸
Settings ▸ Deploying, then deploy again."; Schedule a Deploy's two
(`ScheduledDeploy`, `cloudflareAccountMissing` and its additional twin) say
"… then schedule this again." Constants in `Core/Models/DeployingSettings.cs`.
The mac's three said "this course's settings" until #534 (2026-10-16); they
now say "Plantoir ▸ Settings ▸ Deploying", where the item is on the mac — the
File ▸ / Plantoir ▸ split below stands.

**The deliberate wording split.** The app's sentences say **File ▸ Settings ▸
Deploying**, where the item IS on Windows. The launchers' non-interactive
refusal (#490) says **Plantoir ▸ Settings ▸ Deploying** in both `deploy.sh` and
`deploy.ps1` — Russell's ruling: one launcher sentence for both platforms.
Do not "fix" either to match the other.

**Display labels, mirrored by hand and contracted on neither side.** The
words around the ID — `DeployingSettings.KeptIn` ("Kept in File ▸ Settings ▸
Deploying, for every course…"), `ShownWhenEmpty` ("Not set yet"), the
"Open Settings…" button, the instructions' `Expander` header, the field's
placeholder ("32 letters and digits") and the pane's two footer captions —
were copied from the mac's `DeployingSettingsView` / `CloudflareDetailFields`
by reading them, and no contract key holds them on either platform. That is
deliberate rather than an oversight: they are labels a teacher reads in
passing, not a rule with inputs and outputs, and `KeptIn` cannot be shared
as one string anyway — it names the place the setting lives, which is File ▸
on Windows and the app menu on the mac. What IS contracted is unchanged: the
problem sentence (`configurationRules.cloudflareAccountID[].expectProblem`)
and the trail event (`activityTrail.mustRecord`). If the mac rewords a
label, nothing here goes red; the way it reaches Windows is the `windows`
issue that rewording owes (CLAUDE.md rule 3).

**#490 in the launchers.** "Add your Cloudflare Account ID in Plantoir ▸
Settings ▸ Deploying, then deploy again." `deploy.ps1` has no byte-order mark
and runs under Windows PowerShell 5.1, which reads it in the system code
page, so a literal ▸ arrives garbled: the line is
`("…Plantoir {0} Settings {0} Deploying…" -f [char]0x25B8)`, the convention the
file already used for · and —. Checked: the file parses under 5.1.26100 with
no errors, and the expression renders the sentence exactly.
`scripts/test_deploy_non_interactive.py` →
`test_both_launchers_point_at_settings_for_the_account_id` pins both (the ps1
in its `-f` form), and `app-rules.json`'s authored `refuse` prose says the
same. The publishing path changed, so `verify-deploy.ps1` runs at the cut
(RELEASING.md), and `./verify-deploy.sh` on the mac before its next release.

**Help ▸ Plantoir Help**, first in Help, with F1 — Windows' Help key —
through `MainWindow.Invoke` like every menu key, so `DialogGate.Holds(…,
"F1")` keeps it from acting under a dialog. It opens
https://plantoir.app/support/ (`Core/Models/PlantoirHelp.cs`, the mac's
address) through `Services/ExternalLinks.Open`, which in a redirected run
(`--state-dir`) appends the address to `links-opened.txt` in the state folder
instead of opening a browser — a UI test reads what WOULD have opened and
never puts a browser in front of the person at the desk. Trail: `opened
Plantoir Help`, "Help ▸ Plantoir Help — opened the support page in the
browser". Both events left the `NamedGapLedger` with this batch.

**Testing it**: unit — `CloudflareAccountInSettingsTests` (the three lines,
nothing-changed, never the ID, the pane's problem rule, "Not set yet", the
one writer by source scan, the refusals), `MultiDestinationDeployRunnerTests`,
`ContractTests`' scheduled-deploy cases, `AcceleratorDialogGateTests` (F1).
Through the window (`[UiFact]`): `SettingsUiTests` — File ▸ Settings… is a
window titled Settings; the ID typed in Deploying reaches the run's
`settings.json`, the trail says "…was changed" without the ID, and a
Cloudflare course shows it read-only with no field; the wizard refuses Create
with no ID, Open Settings… raises Settings on Deploying while the wizard stays
open, and a valid ID typed there enables Create; and (since 3B) a course moved
to Cloudflare with no ID holds Save back until an ID typed in Settings frees
it, after which moving the course back leaves nothing to save or revert — the
ID was not counted as an edit to the course
(`CourseSettingsSaveFollowsTheIdTypedInSettings`). The single-writer scan
reads Plantoir, Core and the MCP server and matches the property on a word
boundary, so an object initialiser counts. `PlantoirHelpUiTests` —
`links-opened.txt` and the line. `DrivenApp.FindTopLevel(automationId)` finds
another top-level window of the run's own process.

## Preview at Last Viewed on Windows (#514, the mac's #504)

Batch 6 of the catch-up to mac 1.7.1 (2026-10-15). The design, the rule and
every case are the mac's: `contracts/shared-rules.json` → `previewStartPage`,
and `09-mac-app.md` → "Opening the preview at the page last viewed (#504)"
for what the mac measured and rejected. This section is what is different
here and why. Code: `Plantoir.Core/Models/PreviewStartPage.cs` (the rules and
`PreviewNavigationLedger`), `LastViewedPages.cs` (the store),
`Views/SectionDetailView.xaml.cs` (`PreviewOrStop_Click` → `PressPreviewAsync`,
`OpenTheSiteAsync`, `NavigateAsAppAsync`, `ReloadAsAppAsync`,
`WatchTheTeachersNavigations`), `MainWindow.Modifier.cs` (Alt),
`MainWindow.Menus.cs` (the second item), `Views/PreviewSettingsPane.cs`.

**What a teacher sees.** File ▸ Settings ▸ **Preview** (Russell's ruling on
#514: the one Settings window, between Assistant and Deploying) asks "When
you press Preview, open" — The site's front page (the default) ○ The page you
last viewed — with `windowsWording.altNote` under it. The toolbar button reads
"Preview" or "Preview at Last Viewed" by the setting, and the OTHER while Alt
is held in that window. **Section ▸ has two items**: the first titled as the
button with no key held (and "Stop Preview" while a preview runs), the second
(`sectionPreviewAlternate`) always the opposite, absent while a preview runs.
Every other start — the assistant, Rebuild Preview, Preview Again, Start of
the Year, a repair, the smoke hook and the marketing capture — opens the
front page.

### Two items, not one re-titled item — a choice, not a constraint

MEASURED in the batch's probe (i5-8365U, 16 GB, Windows 11 Pro 26200, 150%,
Windows App SDK 1.8.260921001; the raw logs were the probe's, not committed):
with a `MenuBarItem` flyout OPEN, Alt down, up or tapped does not dismiss it
and shows no KeyTips; keys pressed in the flyout bubble to the window's root
(Alt's KeyDown arrives unhandled); and changing an item's Text while the
flyout is open re-lays it out (170.7 → 308.0 epx, the flyout 310.7). So live
re-titling inside the menu WOULD have worked. Two items were chosen anyway
(the director's ruling on the plan's Q1): a teacher scanning the menu sees
both choices without knowing a key exists, which is the discoverability the
mac's Option alternate buys with its own convention and WinUI menus have no
convention for. `subjectMenus.rule` says the alternate is the SAME item for
the enablement rule: it is added with `Item.Preview` (so `Invoke` re-checks
the rule when it runs) but `rules: false`, so it does not take the first
item's place in `_ruled`, and it is greyed by hand beside it.

**The second item never stops a preview** (the plan review's M2): a menu drawn
before a preview started elsewhere — the assistant's, say — still shows it,
and the rule's re-check passes (Preview is enabled while running), so
`PressPreview(opposite: true)` refuses when the runner is running and the menu
is redrawn.

**No key on the second item.** The mac's is ⌥⇧⌘P; the counterpart,
Ctrl+Alt+Shift+P, is AltGr+Shift+P on keyboards with an AltGr (Ctrl+Alt is
AltGr to Windows), a character a teacher may be typing. REJECTED for that
reason, as Ctrl+Alt was for #488's keys.

### Alt

MEASURED (same probe): Alt alone, with no `AccessKey` anywhere in the app,
arrives as `VirtualKey.Menu` KeyDown/KeyUp (unhandled), never raises
`AccessKeyManager.IsDisplayModeEnabledChanged` (no KeyTips), sends no
`WM_SYSCOMMAND`/`SC_KEYMENU` to any of the window's HWNDs, and swallows
nothing — a key typed 1 ms after Alt's release arrived. Alt down → click a
Button → Alt up: Click fires. So the subclass dropping `SC_KEYMENU` the plan
held in reserve is NOT needed.

- **The click reads the keyboard** (`InputKeyboardSource.GetKeyStateForCurrentThread`
  for Menu and Control) and that is the authority; the title is a courtesy.
  **Ctrl+Alt is not the modifier** (`PreviewStartPage.ModifierHeld`): it is
  AltGr. The menu items never read the keyboard.
- **The title follows Alt in the ACTIVE window only**: re-read on any Alt or
  Ctrl KeyDown/KeyUp at the window's root (`handledEventsToo`), on
  activation, when a menu closes (the first item's `Unloaded` — measured to
  fire on EVERY close: Escape 2–6 ms, a click outside 21 ms, an item chosen
  6 ms after its Click; the mac's lost release was Option let go inside an
  open menu), and when the pointer reaches the Preview button or it takes
  focus. **Forced off on deactivation**: a release in another window is never
  seen, so the state is cleared rather than left stale.
- The toolbar's title depends on Alt only while no preview runs — when the
  web view is collapsed, so focus is never inside WebView2 (where #488
  measured that no XAML key fires) at the moment it matters.

### Remembering only the teacher's navigations

`CoreWebView2.SourceChanged` is the mac's `url` KVO: it fires for a click,
Back, Forward, and — with `IsNewDocument` false — Quartz's pushState links and
fragment clicks. Every load the APP makes goes through `NavigateAsAppAsync` or
`ReloadAsAppAsync`, which mark it in `PreviewNavigationLedger` before calling
`CoreWebView2.Navigate`/`Reload`; `PreviewNavigationSourceTests` holds every
`.Navigate(`/`.Reload(` to those two and `Preview.Source =` to nowhere.
MEASURED event orders (WebView2 runtime 155.0.4283.45, SDK 1.0.3179.45):

| Navigation | What WebView2 raised |
|---|---|
| The app's load of the root | NavigationStarting → SourceChanged (IsNewDocument true) → ContentLoading (0–2 ms after) → NavigationCompleted |
| `/Concepts` (302 → `/Concepts/`) | NavigationStarting, then NavigationStarting again with IsRedirected and the SAME NavigationId; SourceChanged only for the final address |
| Reload | no SourceChanged |
| GoBack (a new document) | a full load, IsUserInitiated false |
| pushState link, fragment click, Back after a fragment | ONLY SourceChanged (IsNewDocument false) + HistoryChanged — and each silently CONSUMES a NavigationId |
| A 404 | IsSuccess false, status 404; ContentLoading IsErrorPage false |
| A dead port | ContentLoading IsErrorPage true, status 0; Source names the dead address |

So an app load ends at the `ContentLoading` of the NavigationId CAPTURED from
the first `NavigationStarting` after the request — never "the next id", which
pushState consumes — with that id's `NavigationCompleted` as the backstop for
a failure and 15 s when no navigation ever started. Each request captures an
id of its own — the ledger counts requests still waiting for a
`NavigationStarting` — so the first of two app loads back to back cannot end
the second, even when both are asked for in one dispatcher turn before
either has started (`TwoAppLoadsAskedForInOneTurnEachWaitForTheirOwnNavigation`). The cost, chosen over ending a load early: a request WebView2 cancels before
raising any `NavigationStarting` holds the ledger open until the 15 s backstop.
`ContentLoading` is the mac's didCommit: ending at Completed instead would
lose a click made while a page's fonts and KaTeX load (the mac measured a
resource answering after 8 s). An app load's own SourceChanged lands before
its ContentLoading, so it is ignored. `Remember` refuses only an address that is
not the preview's own scheme, host and port — `about:blank`, or a dead port
elsewhere; a dead port at
the preview's OWN address would be remembered, which is why the press gives up
before loading when the preview stopped during the ask.

**CoreWebView2.Navigate, and why — corrected.** The plan said setting
`WebView2.Source` to the address already shown does not navigate. MEASURED,
it does (it reloads, every time: a new Uri, `Source = Source`, or a held
instance). `Navigate` is kept because it gives every app load ONE route
through the ledger, not because of a trap. `WebView2.Source` follows
`CoreWebView2.Navigate` (it always matched `CoreWebView2.Source`, inside
SourceChanged too), so Open in Browser, the test-run `ItemStatus` mirror and
the capture's filter, which read `Preview.Source`, are unchanged.
`EnsureCoreWebView2Async` completed on a COLLAPSED WebView2 in 84 ms (a second
web view in the process; a cold first one not measured), and the trail line
and `RefreshChrome` come BEFORE the navigation is started, so a teardown
during it loses neither.

**A flag, not "the address equals the one asked for"** — the mac's reason
holds: a teacher's own Home click would be ignored, and a redirect never
matches. REJECTED, with `Uri.AbsolutePath` for the path (.NET unescapes some
`%xx` in it; the path is cut from the raw string, as the mac's
`percentEncodedPath`).

### The root, the ask, and where the page is kept

- **`_previewUrl` stays the ROOT** (the opposite naming from the mac's
  `previewRoot`/`previewURL`): the capture resolves pages against it, and the
  remembered path is cut from it. `PreviewNavigationSourceTests` holds its
  assignments to `root` or `null`. Nothing is remembered while it is null —
  during the ask, after a stop.
- **The ask** (`OpenTheSiteAsync`): once the root answers, the build claim is
  released at once (the assistant may build again) but "Preparing the
  preview…" stays while the remembered page's address is asked — a GET,
  redirects followed, 5 s a try, up to 3 tries a second apart, through an
  HttpClient of its own. A stop cancels it and nothing opens or is written;
  the same-run check (`_serverWait == thisWait`, not torn down) guards the
  rest. A stored path whose address would leave the root (`//elsewhere`, an
  address) is read as gone. The address is built with `UriBuilder.Path`, so a
  first segment with a colon stays a path.
- **MEASURED on the real Windows serve handler** (a scratch course previewed
  with `preview.ps1` from the command line, i5-8365U, Quartz v4.5.0 on the
  bundled runtime): `/` 200, `/Concepts/Lesson-Marker` 200, `/Concepts` 302 →
  `/Concepts/` 200, `/No-Such-Page` 404, `/Concepts/No-Such-Page` 404, a query
  200 — 3–7 ms each. 120 requests fired 30 ms apart across three rebuilds
  (Quartz's "Detected change, rebuilding…", 15–28 ms on this two-page site)
  all answered 200, the slowest in 27 ms: none failed and none was read as
  gone. A rebuild long enough to show the WAIT itself was not reproduced on
  so small a site; the mac's handlers.js measurement stands for that.
- **Where the page is kept: `%LOCALAPPDATA%\Plantoir\last-viewed-pages.json`**
  (the state folder, so `--state-dir` moves it), per working folder
  (`WorkingFolder.IsTheSame`), course (any case) and section; a path, never
  an address; written only on a change, through a temporary file; 500 newest
  kept; nothing pruned for a missing folder (#320: it may be on a drive not
  plugged in). REJECTED: `settings.json` — every window rewrites it whole and
  a parse failure resets every setting, so a write on every click would be one
  more writer racing for it. Not a contract format: only this app reads it.

### Toolbar width

"Preview at Last Viewed" roughly doubles the button. The section title's
column is now the star column with `TextTrimming="CharacterEllipsis"`, so a
long title shortens before the buttons are pushed out.

**Measured 2026-10-15** (Intel i5-8365U, Windows 11 Pro 26200, one 1920 ×
1080 screen at 150%, the sidebar at its only width, 230 epx; widths are the
window's outer pixels; **the next sentence, and the table's last row label, were wrong — see the
correction below the table**): the window's minimum is **900 PIXELS, not 900 epx** —
`PreferredMinimumWidth` is in the AppWindow's physical units — so at 150% it
is 600 epx, and dragging the edge stops there.

| Window | "Preview" | "Preview at Last Viewed" (Alt held) |
|---|---|---|
| 1350 px (900 epx) | all fits, title whole | all fits, title whole |
| 1200 px (800 epx) | all fits | title "MP…", every button whole |
| 1100 px (733 epx) | all fits | title gone, the Browser button cut |
| 1000 px (667 epx) | all fits | Deploy cut, the Browser button off the window |
| 900 px (600 epx, the minimum) | title gone, Deploy cut, Browser off | the Preview button cut, Deploy and Browser off |

So at 900 epx nothing clips; the ellipsis does its job down to about 800
epx with the long title; below that the buttons leave the window.

**Corrected 2026-10-16 (#542): the minimum was already 900 epx; the window
OPENED below it.** Measured on the same PC at 150% by
`WindowMinimumUiTests.AtItsNarrowestTheWindowStillShowsPreviewDeployAndBrowser`,
reading the frame both through UI Automation and through `GetWindowRect` on a
thread made per-monitor DPI-aware, against an x64 Debug build of dev
99295805c, "Preview at Last Viewed" seeded:

- **At launch** (first run, no remembered frame): 1190 × 725 px, which UI
  Automation reports as 793 × 483, i.e. **793 × 483 epx** — the first-run size
  is 62% × 72% of the work area (1920 × 1008), set by `AppWindow.Resize` in
  pixels BEFORE the minimum was set, and setting a minimum does not grow a
  window that is already narrower. Every button was whole (Browser's right
  edge 15 epx inside the window), the section title shortened — the "800 epx"
  row above.
- **At its narrowest** (UI Automation asked for 400 × 400): **1350 × 900 px =
  900 × 600 epx**. `PreferredMinimumWidth`/`Height` behave as epx: the
  presenter scales them. Nothing drags below that.

So the table's first sentence ("900 PIXELS, not 900 epx … dragging the edge
stops there") was wrong, and the rows below 900 epx were not reachable by a
drag. Those widths were reached some other way that was not recorded; the
rows still describe what the toolbar does at those widths (they agree with
the launch measurement at 793 epx). In a teacher's hands the app reached
them in two ways: the first-run window above, and a remembered frame — it is
kept in PIXELS, so a 1350 px window remembered on a 150% display and
reopened on a 225% one is 600 epx there.

**What changed.** `MainWindow.ApplyMinimumSize(scale)` sets the minimum
BEFORE the first `Resize` and the launch size (first-run or remembered) is
clamped up to it, so the window opens at no less than 900 × 600 epx (1350 ×
900 px at 150%). A remembered frame is MOVED first, and the scale
(`GetDpiForMonitor` of the monitor it now sits on) and the work area are read
after the move, so a frame reopened on another display is clamped for THAT
display. The minimum is clamped to the work area of the display the
window is on (`DisplayArea.GetFromWindowId(…, Nearest)`), divided by the
scale, because 900 epx is 2025 px at 225% — wider than a 1920 work area, and
a minimum wider than the screen would trap the window. Once the content
loads (from `XamlRoot.RasterizationScale`) and again on `XamlRoot.Changed`
when the scale changes (a monitor move, a display-scale change),
`EnforceMinimumSize` re-applies the minimum AND grows a window left below it,
unless it is maximised or minimised — the minimum alone does not grow one. **What holds
what:** the first-run clamp is held by `WindowMinimumUiTests` (named above), on this one display
at one scale; the re-apply and the grow on a scale change, and the remembered
frame's move between monitors, are held by reading the code, since there is
one screen here and no test changes the display scale; where a remembered
frame is put when its display has gone (#558, below) is held by
`WindowFrameFitTests` (the geometry) and `WindowOnScreenUiTests` (that the
constructor applies it). **On a 1920-wide screen at 225–250% the work-area clamp can still cut
the toolbar**: the window there is narrower than 900 epx (1920 / 2.25 = 853
epx), which is below the width the long title needs — and so is any screen
whose work area is under 900 epx wide, a 1280 × 800 laptop at 150% (853 epx)
among them. After the change the
same UiFact read 1350 × 900 px (900 × 600 epx) at launch and at the
narrowest; maximised (1295 × 687 epx) the buttons were Preview 185, Deploy 89
and Browser 36 epx wide, and at the 900 epx minimum the same, Browser 15 epx
inside the right edge.

**REJECTED:** a minimum of `900 × RasterizationScale`, #542's option 1 as
filed — on the reading that the minimum was in pixels. The presenter already
scales it, so that would have asked for 1350 epx (2025 px) at 150%. And #542's
option 2, toolbar buttons that shrink to their glyphs: the mac does not have
it; on a 1920-wide screen at 200% and below nothing needs it, and where the
work area is under 900 epx (225% and above there, or a smaller screen) it is
the remaining option, not taken. The UiFact's
right-edge check is 8 px × scale inside UI Automation's window rectangle,
because that rectangle includes Windows 11's invisible resize border (7 px a
side at 150%: `GetWindowRect` 1350 against the visible frame's 1332).

**A remembered window whose display is gone (#558).** Before #558 the
constructor moved a remembered frame to where it was and stopped there: #542
fitted the SIZE to the nearest display, never the position. Measured
2026-10-22 on the same PC (Lenovo 20QES70500, i5-8365U, one 1920 × 1080
display at 150%, work area 1920 × 1008) with a frame seeded at X = 5000,
Y = 200, 1400 × 900 and "restore windows on launch" on: the visible frame
opened at (5009, 200), wholly beside the work area — a taskbar button and no
window. A teacher meets this after undocking a laptop, unplugging a second
screen or a projector, or lowering the resolution.

Now `MainWindow.OnADisplay` hands `WindowFrameFit.Fit` (Plantoir.Core) the
remembered frame, every display's work area (`DisplayArea.FindAll()`, read by
`Count` and the indexer — enumerating that projection throws in some Windows
App SDK versions) and the nearest one (`DisplayArea.GetFromRect(…, Nearest)`).
The frame is **kept exactly** when its title-bar strip — its top 32 epx —
overlaps SOME work area by at least 100 epx across and a third of the strip
down, both converted at the nearest display's scale (one scale,
`GetDpiForMonitor` of `MonitorFromRect` on the whole remembered rectangle):
epx, because 100 raster pixels is only 50 epx at 200%. And if any of this
throws (`FindAll`'s projection has thrown on some Windows App SDK versions,
and the package floats on 1.*), the frame opens as remembered and
`startup.log` says so: a frame is re-saved only by a window that opened, so a
throw that stopped the window would have failed every later launch.
Otherwise it is shrunk to no larger than the nearest work area and centred
on it, and centred again after the minimum size has grown it. After the fix
the same seeded frame opened with its visible frame at (269, 54), 1382 × 891,
inside the work area. A frame that is kept takes exactly the old path.

The rule asks for SOME overlap, not the whole strip inside one work area, and
that was a plan-review correction: a window quit maximised is saved a few
pixels outside its display (about (-11, -11) at 150%), a window can straddle
two monitors side by side or stacked, and a top taskbar covers part of a
strip — and each of those is a frame the teacher left on purpose, which a
whole-strip rule would have shrunk and re-centred. `WindowFrameFitTests` has a
case for each, and for the X = 5000 frame, a vanished right-hand monitor, a
frame larger than the work area, a title bar above every display and a
sliver of title bar too narrow to drag. **REJECTED:** always clamping the
frame into the nearest work area (moves every one of those deliberate
frames); clamping only the size (what #542 left, the position still off
screen). **Known limit:** several windows remembered on one vanished
monitor all come back centred on the same display, one exactly over another;
the rule says where a window can be reached, not how to cascade them. A
`startup.log` line (`MainWindow ctor: remembered frame … is on no display`)
records a move; there is no trail line, because nothing a teacher did is
being recorded. Mac: nothing to do — AppKit's frame restore already keeps a
window on a screen. Pinned in the UI suite by
`WindowOnScreenUiTests.ARememberedFrameOffEveryDisplayOpensInsideTheWorkArea`
(opt-in, `DrivenApp(restoreWindows: true)`), red before the fix and green
after, run alone.

### Known limits

The teacher's web browser is not observable (Open in Browser's pages are not
remembered). A click before an app load's content arrives is not
remembered. The first click on an inactive window acts as Alt says but its
title did not swap first. Ctrl+R and Alt+Left inside the page are WebView2's
own, so Chromium's reload counts as the teacher's — harmless, it is the same
page. A Quartz 404 page the teacher visits is remembered and falls back
("gone") on the next press.

### Testing

`PreviewStartPageContractTests` (every block of `previewStartPage`, the press's
own `Decide` through `DecideForCase`), `PreviewStartPageTests` (ledger orders,
including two app loads back to back; addresses; the store; real statuses
from a TCP server), `PreviewNavigationSourceTests`. `[UiFact]`s in
`PreviewStartPageUiTests` (Settings ▸ Preview saves and re-titles the button
and both items; Alt re-titles; Alt+click opens the page last viewed; a
teacher's click is remembered and View ▸ Reload Page is not) — written with
the desktop locked; all four pass on the first unlocked desktop (2026-10-15),
after two fixes to the tests: the link is scrolled into view before the
click (the harness's window is short at 150%), and Alt is held 500 ms past
the Alt+click, because WinUI raises Click after the mouse button is up and
the press reads the keyboard then — released at once, the press read Alt as
up, twice. `DrivenApp` now keeps a
`settings.json` a test's `beforeLaunch` seeded, adding its own two keys.

## The HIG sweep, screen by screen, on Windows (#491 part B)

Batch 3B of the catch-up to mac 1.7.1 (2026-10-15): items 1–9 of #491, the
Windows half of the mac's #457 batch C ([09 → "The HIG sweep, screen by
screen"](09-mac-app.md#the-hig-sweep-screen-by-screen-457-item-4-batch-c)).
WinUI is a different animal, so each item takes the mac's RULE and finds the
WinUI mechanism for it. Measurements are from batch 3's spike (Intel i5-8365U,
Windows 11 Pro 26200, 150% scaling, Windows App SDK 1.8.260921001).

### A button that cannot be pressed never looks like the default (item 2)

**Measured.** A DISABLED button that is still a ContentDialog's default keeps
the accent slab: #BFBFBF with white text in Light (about 1.8:1), #434343 with
#A7A7A7 text in Dark — it still reads as the primary slot, where a disabled
plain button is #F5F5F5 on #F3F3F3 (Light) or #2A2A2A on #202020 (Dark). And a
trap: the same disabled default in a dialog with NO focusable content loses
its accent, initial focus lands on Close, and Enter presses Close — the dialog
dismisses. With a focused text box, a disabled default takes no Enter.

**So enablement, the default and the accent change together.** The rule is
`Plantoir.Core/Models/PrimaryButtonLook.For(enabled, PrimaryKind)`; one helper,
`Views/DialogButtons.EnablePrimary(dialog, enabled, kind)`, applies it:
while disabled the main button is not the default (`DefaultButton` None — only
if it WAS Primary, so a dialog whose default is Close or Secondary keeps it)
and carries no accent style; when it can be pressed it is the default again.
Three kinds: `TakesEnterWhenEnabled` (every ordinary dialog),
`NeverTakesEnter` (the wizard, below — the accent style explicitly, never the
default) and `NotTheDefault` (All Backups' Delete…, destructive beside a Done
that keeps Enter: only enablement changes). `DefaultButtonScanTests` holds
every `IsPrimaryButtonEnabled` write under `Plantoir/` to `DialogButtons.cs`
— object initialisers and bare writes inside a `ContentDialog` subclass
included, which is how All Backups' initialiser was found — so a new dialog
cannot grey its main button by hand. The 21 sites the plan listed, plus 2B's
section-verb dialog, all go through it.

**The wizard's Create Course NEVER takes Enter** — measured on the mac
(2026-10-08): as the default, an Enter typed in the Course code field created
a course named by the code with the rest of the form unread. `DefaultButton`
is None from the start; the button wears the accent while it can be pressed;
the cursor starts in Course code (`Opened` focuses it; the suggestion list
opens only on typing). After the work, its Close is the ordinary kind and
takes Enter — there is nothing left to type.

**Class Dates reads, THEN remembers.** "Read the Dates" (Secondary) and
"Remember These Dates" (Primary), the mac's words. Remember is live only once
dates have been read (`_parsedDates`), so it never sits greyed in the default
slot; the primary handler's own re-read stays as a safety net. Before a read,
Read the Dates is the default — EXCEPT on the typed route, where no button is:
the box needs Enter for a new line. Measured here, Enter in a multi-line box
inserts a line and presses nothing even with a default button, but the rule
is kept (the mac's `isTheDefault: route != .typed`) so it does not depend on
that. A read that fails clears what was read before.

### Escape is never trapped (item 1)

**Measured: an AutoSuggestBox in a ContentDialog TRAPS Escape.** With its list
closed, the inner TextBox marks Escape handled and a second Escape is
swallowed too; with it open, the first closes the list and the second is
swallowed. So Copy a Page — which opens with the cursor in its page field —
and the wizard could not be closed from the keyboard at all. A ComboBox
already behaves (closed: Escape closes the dialog in about 3 ms; open: the
first closes the drop-down, the second the dialog) and is left alone.

`Core/Models/PickerEscape.For(listWasOpen)` is the mac's rule; both
AutoSuggestBoxes (`CopyAPageDialog._picker`, the wizard's `_codeBox`) ask it in
`PreviewKeyDown` — which tunnels, so it runs before the inner TextBox marks the
key handled — and, with no list drawn, mark it handled and `Hide()` the dialog
(the wizard through its Cancel route: a running creation is stopped by the
teacher, as `OnCloseButton` does). With a list drawn, WinUI's own handling
closes it. `PickerEscapeTests` pins the rule and that both pickers route
through it; `CopyAPageEscapeUiTests` and
`NewCourseWizardUiTests.EscapeClosesTheCodeListThenTheWizard` press real
Escapes (list, then dialog), each after `BringToFront` and failing with "the
app did not hold the foreground" rather than blaming the app when another
window has it — the flake `SpecialFoldersHelpUiTests` records.

### One dialog title shape (item 3)

Every title was already a plain string in WinUI's own title style; what
differed was the explanation under it in the five dialogs that carry one — 12
at 70%, 13 at 80%, the default at 70%, and Keep a Copy's at the BOTTOM.
`FormBuilders.DialogExplanation(text)` (14, `TextFillColorSecondaryBrush`,
wrapped at 460, 12 below) is now FIRST in the content of Add Section, Keep a
Copy for Reference (what the copy IS moved to the top; what it leaves behind
and why it never deploys stay below the form), Class Dates, Special Folders
and every credential request (`CredentialRequestPanel`, so the Deploying
pane's inline instructions use it too). Titles stay in sentence case — and
stay as they were: "Add a Section to ICS3U" is the mac's title too.
`DialogTitleScanTests` holds a per-file census of every ContentDialog made (64
on 2026-10-15) the way the mac's `SheetTitleScanTests` censuses sheets, so a
new dialog arrives having been looked at; it also refuses a `TitleTemplate` or
an element as a title, and checks the five call the helper.

### Open in Obsidian locks a reference course again first (item 4)

2A made Open in Obsidian one route (`SidebarPane.OpenInObsidian`, above). The
mac's route also LOCKS the pages again before anything, so a page unlocked
since the folder was read — by hand, by a sync client, by a restore — never
opens editable; `OpenReferenceInObsidian` now runs
`ReferenceLock.EnsureLocked` off the UI thread first (a large course is
thousands of access-rule reads) and writes the existing "reference course
pages locked again" line through `ReferenceCourseUpkeep.TrailLine` when it did
anything; a failure is logged and the teacher may still open. The note is
shown on the sidebar's `XamlRoot` — the sidebar always exists in a window
(there is no collapsed-sidebar state here as on the mac, where the note had to
move to the main window). `ObsidianRouteSourceTests` holds
`FolderActions.OpenInObsidian(` to the sidebar's two branches plus ONE named
exception, Course Settings' How I Teach row, which opens a PAGE of a LIVE
course. Verified by hand once (2026-10-15, a throwaway UI test, Obsidian's
vault registry backed up and restored byte for byte): a page unlocked by hand,
the section toolbar's button, the page locked again BEFORE the note, "locked 1
page of ICS3U again — it is kept for reference" on the trail, Obsidian opened.

### Delete and the − button run the menu's removal (items 5–6)

**The Delete key** on a selected sidebar row runs the item
`shared-rules.json` → `sidebarDeleteKey` names — Remove Course…, Remove
Section…, Delete Backup…, Delete Archive… — through the menu bar's own guard
(`MainWindow.RunFromTheSidebar` → `Invoke`), so it asks the menu's question,
and where the item is greyed (a section of a course kept for reference, a
course being copied) it does NOTHING. **Silently**: the mac beeps, Windows has
no beep for a greyed command, and a dialog explaining why would be a door the
menu says is shut — the same reasoning as F2 on a greyed Rename (above). It is
the tree's `KeyDown`, never a key on the menu item (which would take Delete
from every text field; the filter box is outside the tree), and it asks
`DialogGate.Holds(root, "Delete")` first (`AcceleratorDialogGateTests`).
**Which row**: `Tree.SelectedItem` — measured, arrow keys move it (and focus)
WITHOUT raising `ItemInvoked`, which is how the window's own selection is
normally set — so the row is selected for the window first, and the item acts
on what the teacher sees highlighted. Measured too: Delete reaches
`Tree.KeyDown` unhandled with the item as its source.

**The − button** follows the same rule for removal only
(`Core/Models/SidebarDeleteKey.MinusButtonIsEnabled`, refreshed with the menu
bar's enablement — every trigger `ApplyMenuEnablement` hears — and not greyed
for a dialog, whose overlay covers it anyway): greyed on a backup, an archive
and a section of a course kept for reference. **It used to remove the WHOLE
COURSE there**: `ConfirmRemove` turned a reference section's removal into the
course's, silently. That coercion is now an early `return` — a guard for any
caller that skips the rule — and the "removing the only section removes the
course" branch stays, as on the mac. `ConfirmRemoveCourse` /
`ConfirmRemoveSection` are the entry points.

**Every row menu's removal is last, behind a separator**: course, section and
reference-course rows gained Remove Course… / Remove Section…, greyed by the
rule for THAT row read when the menu opens (`MainWindow.SituationFor(selection)`,
the generalisation of `CurrentSituation`; the section window's and Course
Settings' own buttons are read only for the selected row, and no removal
depends on them). A reference SECTION offers none
(`interface.whatIsWithheld`); backup and archived rows already ended with
their Delete….

`SidebarDeleteKeyContractTests` runs the 6 cases and checks the − button
against every `subjectMenus` case whose row is a course or a section. **No
`minusButtonCases` key was proposed** (decided on the plan review): those
cases already pin it, and the mac implements and tests the same rule
(`SidebarMinusButtonTests`). Through the window: `SidebarDeleteKeyUiTests`
(Delete on ICS3U asks "Remove ICS3U?" and Cancel removes nothing; on a
reference section nothing opens and − is greyed) and
`ReferenceCourseUiTests.AReferenceSectionOffersNoRemoveSection`.

### All Backups (item 7)

A header over the list: **Course**, **Made** and **Size** sort
(`allBackupsSortCourse` / `…Made` / `…Size` — never `allBackups-…`, which
names a row), with ▲/▼ on the sorted one; **Made By** is a label. Newest first
until a header is pressed; a new column sorts ascending, the same one flips;
the selection is kept by file. `Core/Models/AllBackupsOrder` (ties newest
first, an unmeasured size the smallest) is unit-tested. Each row's context
menu: **Restore…** (exactly one chosen), **Show in File Explorer** (one window
per folder; the dialog stays), and **Delete…** last behind a separator; a
right-click on an unselected row selects only it (the menu's `Target`, as in
File Explorer). Delete in the list is Delete…. Restore… and Delete… close All
Backups FIRST and ask once it has gone — WinUI shows one ContentDialog per
window, and their questions are dialogs — through the same
`ConfirmRestoreBackup` / `ConfirmDeleteBackups` as before.
`AllBackupsUiTests.TheListSortsAndOffersAMenu` drives the order, the header's
ids and the menu.

### One name per command (item 8)

The course and section rows' Revise items sit in **Revise With ▸**, titled as
the menu bar's: Claude…, Codex…, Local AI Assistant…. The outside agents'
titles are `ClaudeCodeLauncher.MenuItemTitle` / `CodexLauncher.MenuItemTitle`,
which the menu bar and the rows share, and
`ContractTests.TheOutsideAgentsMenuTitles_AreTheContracts` reads
`app-rules.json` → `outsideAgents.agents[].menuItem` by key — until now
nothing on Windows read it, so the mac's rename turned nothing red. "Rename"
and the empty pane's "New Course…" came with 2A.

### The words (item 9), and a 12 epx floor

- Class Dates: **Choose a File…**, **Day First** / **Month First** (keeping
  the "(…)" example).
- Site health: the dismissing button says **OK** only when it is the only
  answer — **Not Now** beside a repair, **Close** beside Preview Again
  (`SiteHealthRepair.CloseTitle`).
- A backup, restore, deletion or removal problem names its act
  (`Core/Models/BackupProblemTitle`, the mac's words: "Could not back up
  EXC2O", "Could not restore EXC2O", "Could not delete the backup(s)", "Could
  not delete the archive"), plus Windows' own **Removing(code)** — a failed
  removal has a dialog of its own here, the mac's has none.
- Title case on buttons: "Not Now" (the model download prompt), the
  class-dates card's **Enter Class Dates** / **Not Now** — moved to the
  trailing end, commit button first as Windows orders a pair — and **Save and
  Continue**. The assistant's one-time reminder now says where: "…in File ▸
  Settings, under Assistant."
- **Nothing below 12 effective pixels.** Why 12 and not a conversion: 12 is
  Fluent's **Caption**, the smallest style in Windows' type ramp and the size
  the app's captions already use. Points on the mac are logical pixels (body
  13 pt there, 14 epx here), so the mac's "nothing below 10 pt" is about 10–11
  epx — a floor below Windows' own smallest style would have allowed text
  Windows never draws (plan review, M4). Raised: About (11 → 12, three
  places), the wizard's Example content badge (10 → 12 — XAML held in a C#
  string), Class Dates' sharing note (11 → 12). `FontSizeFloorScanTests`
  reads every `.cs` and `.xaml`, XAML inside strings included (an attribute
  belongs to the nearest `<Tag`, an assignment to the innermost open
  `new Type {`); glyphs in a `FontIcon` are icons and exempt. Checked to fail
  on a size put back.

### Not done, and why

- **"Just Do It" / "Keep Checking"** (item 9's list): Windows has no such
  buttons — the assistant appends a line after fifteen accepted plans instead
  of offering the choice — so there is nothing to title-case; the missing
  buttons are a parity gap outside #491's words, recorded rather than built.
- **"Use This ID"**: Windows' Deploying pane edits the ID in place, with the
  instructions inline (3A), so there is no dialog to carry the button.
- **Sentence-case repair buttons** ("Put the Media folder back"): the
  repair's own titles, `SiteHealthRepair.ButtonTitle`, were left as they are —
  #491 named the dismissing button, and the mac's repair titles are the same
  words, left as they were by its sweep.

## Diagrams and graphs (#485 E1, v1.7.0): the runtime carries the engines (#503)

The build's figure pass (`scripts/figures.py`), its helper
(`support/figures/plantoir-figures.mjs`), the site's transformer and the
contract (`figureFences`) are shared and reach Windows unchanged; the Python
half is tested there by `scripts/test_figures.py`, which needs no Node. The
why, the mac's measurements and what was rejected are in
[02](02-docker-image.md#optvendorfunction-plot-and-optvendortikz-engine-485-e1-v170),
[05](05-build-pipeline.md#diagrams-and-graphs-what-the-build-does-485-e1-v170)
and [06 → G](06-quartz-customizations.md#g-diagrams-and-graphs-485-e1-v170).
This section is what Windows does differently, and what it measured.

**What the runtime carries, since 2026-10-15 (#503, the catch-up's batch
5A), and Pyodide since 2026-10-22 (#568).** `fetch-runtime.ps1` has a vendor
phase that mirrors the Dockerfile's `/opt/vendor` into `runtime\vendor`:

| Folder | What | How it is checked |
|---|---|---|
| `pagedjs\` | Paged.js 0.4.3's `paged.min.js` + `LICENSE.md` (#454) | the tarball's SHA-256, then the file's (`fileSha256`) and its 502,617 bytes |
| `pagedjs\fonts\` | Latin Modern's six OTFs + `LICENSE-Latin-Modern.txt` (#499) | the `.deb`'s SHA-256, then each font against `latinModern.files` |
| `function-plot\` | function-plot 1.25.4's `function-plot.js` + `LICENSE` | the tarball's SHA-256, then the file's and its 202,953 bytes |
| `pyodide\` | Pyodide 314.0.7's five runtime files + `README.txt` naming MPL-2.0 (#455, #568) | the tarball's SHA-256 and its 6,757,104 bytes, then each file against `pyodide.files` — "Runnable code (#455)" below |
| `tikz-engine\` | node-tikzjax 1.0.5 from `support\figures\package-lock.json` (`npm ci --omit=dev`) | `npm ls node-tikzjax@1.0.5`, then the three `tex\*.gz` against `nodeTikzjax.files` |

Each URL is written out in full in the script, because
`ToolchainContractTests.TheWindowsRuntimeRecipeCarriesTheSamePins` reads it as
TEXT for every pin's `windowsRuntimeContains` — `latinModern` gained one
(`fonts-lmodern_2.005-1_all.deb`) with this change; nothing on the mac reads
that field. The `NamedGapLedger` entries that held `pagedjs`, `functionPlot`
and `nodeTikzjax` open went in the same commit. Tarballs are unpacked with
`%SystemRoot%\System32\tar.exe` by full path (Git's GNU tar may be first on
PATH, and reads `C:` as a remote host).

**Latin Modern comes from the same Debian package the image installs**,
`fonts-lmodern_2.005-1_all.deb` from deb.debian.org (snapshot.debian.org as
the fallback), SHA-256 `027cd4dd…c58398`, 4,540,004 bytes, measured
2026-10-15 — so the six fonts are byte-for-byte the image's (all six matched
`latinModern.files` on the first run). The `.deb` is an `ar` archive, which
Windows' bsdtar reads; its `data.tar.xz` is unpacked with the runtime's own
Python (`tarfile` + `lzma`) rather than bsdtar. MEASURED: this PC's bsdtar
(3.8.9, liblzma 5.8.3) does read xz — but an older Windows 10's bsdtar is not
known to, and the build PC is the only place this runs, so the dependency
that is certainly there was chosen. REJECTED: GUST's zip (a second network
host, the same reason the image rejects it) and converting to woff2 (the
licence asks a changed font be renamed).

**A runtime made before the vendor folder is brought up to date without
fetching ~600 MB again.** What runs is decided from `manifest.json`'s KEYS,
never from folders (a crashed `npm ci` leaves a `node_modules` that looks
done): no manifest, everything; a manifest whose vendor keys (`pagedjs`,
`latinModern`, `functionPlot`, `nodeTikzjax`, and `pyodide` since #568) are
missing or differ from the pins, `runtime\vendor` is deleted and only the vendor phase runs, against the
node and python already there (both paths set before any phase), and the
manifest is merged. The plan review's M4 found the first draft would have
called `npm.cmd` with an empty `$nodeDir` on that path.

**A run that dies part-way leaves a runtime the build refuses and the next
run repairs** (the 5A implementation review's L1 and L3). Before
`runtime\vendor` is touched, the manifest is rewritten WITHOUT the vendor
keys — on a fresh clone that is the first manifest written, the five base keys
right after the base phases. So a vendor phase that fails (a download, `npm
ci`, a hash) leaves base keys only: `CheckNativeRuntimeManifest` stops the
build, and a re-run takes the vendor-only path instead of trying to move Node
onto a `runtime\node` that is already there. REJECTED: keeping the old
manifest until the end, which is what 5A did — after a pin bump a failed
vendor-only run left every vendor key (old values) beside no `vendor` folder, a
runtime the build accepted and `publish.ps1` shipped without engines; and
checking for the folder in `CheckNativeRuntimeManifest`, which is the "decide
from folders" the script exists to avoid. **A version and its address cannot
part either (L2):** the vendor addresses are literals beside the
`$<Name>Version` variables, the script refuses at start when an address does
not end with its version, and
`ToolchainContractTests.TheWindowsRuntimeRecipesVendorVersionsAreTheContracts`
holds each variable against the contract's pin.

**The build refuses a runtime without them (the plan review's M5).**
`publish.ps1` never runs `fetch-runtime.ps1`, and robocopy `/MIR` copies
whatever `Vendor\runtime` holds — so a build PC with a 2026-08-19 runtime
would have published an installer with no engines, silently.
`Plantoir.csproj` → `CheckNativeRuntimeManifest` now runs before
`CopyNativeRuntime` and `PublishNativeRuntime` and fails the build, saying to
re-run `fetch-runtime.ps1`, when the manifest lacks any of the vendor keys
(four from #503, five since #568 added `pyodide`). Must-fail measured: with
`nodeTikzjax` removed from the manifest the x64 Debug build stopped with that
error; restored, it built. Measured again for `pyodide` on 2026-10-22: the
key removed, the x64 Debug build stopped at `Plantoir.csproj(104,5)` with
"…predates the page features (Paged.js, Latin Modern, function-plot, the
TikZ engine, Pyodide): its manifest.json lacks their keys…"; restored, it
built. No runtime at all is
still allowed, as before (the targets are skipped).

**Installing over an older version.** Inno never removes a file a newer
version drops, and the engine's `node_modules` is a lockfile tree, so
`installer.iss` → `[InstallDelete]` empties
`{app}\runtime\vendor\tikz-engine\node_modules` before `[Files]` puts the
current tree back. `runtime\quartz\node_modules` has always had the same
exposure (its tree has not changed since v4.5.0 was pinned).

**How the build finds them: no new variable.** The launchers set
`PLANTOIR_QUARTZ_DIR` to `<runtime>\quartz` and put `<runtime>\node` first on
PATH (`Enter-NativeRuntime`); `toolchain_paths.VENDOR_DIR` is that folder's
parent + `vendor`; `figures.helper_command` runs `node` from PATH.

**Measured** (i5-8365U, 16 GB, Windows 11 Pro 26200, 2026-10-15; Node
20.18.1, the image's is 20.20.2):

- The vendor phase alone: **42 s** on a fresh run against the existing
  runtime (downloads 1.05 MB + 4.33 MB + 0.19 MB, then `npm ci`).
- `tikz-engine\`: **133 packages, 5,450 files** (5,448 under `node_modules`,
  plus the folder's own `package.json` and lockfile; the mac counted 5,445 in
  the image), **40,838,241 bytes** (38.9 MiB). The whole `vendor\`: 5,461
  files, 42.2 MB. Latin Modern: 631,940 bytes for the six, as the image.
- **memfs's `/tex_files/` works under win32 paths** — the open question in
  #503 (review N7). The contract's triangle (`figureFences.cacheKey.cases[0]`)
  drawn through `plantoir-figures.mjs` in two processes: byte-identical,
  **1,540 bytes, SHA-256 `8c68b085…6827b37`**
  (`8c68b08531cee21b507a3edb31e9346c9294defa63a0a0d04c5dde05a6827b37`). The
  mac has not yet printed its own SHA-256 for the same SVG, so whether Node
  20.18.1 and 20.20.2 draw the same bytes is not known (the `mac` issue from
  this batch asks).
- The engine's load: **1.6 s** the first time after the fetch (Defender
  scanning 5,450 new files was not visible in it), 1.4–1.8 s after; the
  triangle drawn in 0.33–0.45 s. Nowhere near `figures.START_SECONDS` (120 s).
- A build (`preview.ps1 --build-only`, a fresh section, one page with three
  diagrams, a graph and `printable: true`): **19.2 s** first, **5.7 s** again
  with every figure from the cache ("📐 Drew 0 diagrams (4 from before)").
  With one diagram the first build was 18.6 s, so most of the first build is
  the section's Quartz scaffold, not TeX.
- **A runtime under a path with spaces** (`…\Plantoir Runtime With Spaces`,
  a junction to the runtime, given as `PLANTOIR_RUNTIME`): every test below
  passed through it, so `node.exe` and the engine resolve there.
- **A diagram that never ends** (`\def\x{\x}\x`) through `figures.run_jobs`:
  answered `tookTooLong` and the next diagram still drawn, both in **23.5 s**
  — the 20-second clock plus the helper's restart and the engine's second
  load.
- **Path length.** The longest path under `tikz-engine\` is 134 characters
  (`…\@jsonjoy.com\json-pack\lib\nfs\v4\server\operations\node\Nfsv4OperationsNode.js.map`;
  the longest code file is 130). Installed at
  `C:\Users\<name>\AppData\Local\Programs\Plantoir\runtime\vendor\tikz-engine\`,
  that stays under 260 for an account name up to 56 characters. A Debug
  build from a worktree goes past it (149 + 134), and works here because
  this PC has `LongPathsEnabled` = 1 — so this PC cannot show what a
  machine without it does in a deep folder; the installed path is the one
  that matters, and `publish.ps1` compiles through a short subst drive.
- **In the browser** (headless Edge 155.0.4283.45 — the same Chromium build
  as this PC's WebView2 Runtime, 155.0.4283.45 — over HTTP from the built
  site, light and dark): the graph draws, the triangle's lettering is
  Computer Modern (the page fetched `static/tikz/fonts.css`, `cmmi10.ttf` and
  `cmr10.ttf` from the site itself, and `static/function-plot/function-plot.js`;
  nothing from another address), and in dark mode the drawing turns light on
  the dark page. NOT driven inside Plantoir's own preview pane; Print in the
  pane hands the page to the browser since #496 ("Printable pages" above),
  and WebView2's own print measurements are owed there.

Tests: `NativeFiguresTests` (`[NativeVendorFact]`: skipped, with the reason,
on a runtime without `vendor\tikz-engine`) —
`TheContractsTriangleIsDrawnTheSameInTwoProcesses`,
`ADiagramThatNeverEndsIsStoppedAndTheNextOneIsStillDrawn` (the runtime's
Python with `-I -X utf8` and the scripts folder put on `sys.path` by hand:
`-I` drops both), and
`ABuildWithADiagramAGraphAndAPrintablePageCarriesAllThree` (the real launcher,
the section's site read back: `static\pagedjs\paged.min.js`,
`static\function-plot\function-plot.js`, an inline `<svg>` inside
`pl-figure pl-tikz`, `pl-figure pl-functionplot`, none of the fallback
sentences, then a second build from the cache). The helper's `--rules`
argument must be a `figureRules.js` inside a `"type": "module"` package (a
section's Quartz is one); handed the repository's copy directly, Node reads
it as CommonJS and the helper dies before it says it is ready.

## Runnable code (#455) and KaTeX served by the site (#494), v1.8.0: the runtime carries Pyodide (#568)

The mac shipped both in v1.8.0; the shared Python, the page's code and the
skill reach this side unchanged (`page_features.py`, `build_site.py`,
`support/quartz/**`, `support/gated/pyodide/plantoir-worker.js`, the
`plantoir-runnable-code` skill). The manual is
[06 → I](06-quartz-customizations.md#i-runnable-code-455-v180),
[06 → C2-26](06-quartz-customizations.md#c2-applied-on-every-build),
[05 → Runnable code](05-build-pipeline.md#runnable-code-what-the-build-does-455-v180)
and [07 → Runnable code and KaTeX on each host](07-deployment.md#runnable-code-and-katex-on-each-host-455-494-v180).
This section is what Windows does differently, and what it measured
(2026-10-22, Intel Core i5-8365U @ 1.60 GHz, 16 GB, Intel UHD Graphics 620,
Windows 11 Pro 26200, wired Ethernet; Node 20.18.1).

**What landed (#568, 2026-10-22).** `fetch-runtime.ps1`'s vendor phase
fetches `pyodide-core-314.0.7.tar.bz2` from the project's GitHub release,
checks it against the contract's `sha256` and its 6,757,104 bytes, keeps the
five files the image keeps — `pyodide.mjs`, `pyodide.asm.mjs`,
`pyodide.asm.wasm`, `python_stdlib.zip`, `pyodide-lock.json` — each checked
against `pyodide.files`, and writes the Dockerfile's README line byte for
byte (`Pyodide 314.0.7 (MPL-2.0). Source: …/tree/314.0.7`, 83 bytes, one
LF). `pyodide` is the fifth vendor key in `manifest.json`, so a runtime made
before 2026-10-22 takes the vendor-only path (the whole vendor phase again,
**49 s** here, downloads 1.05 + 4.32 + 0.19 + 6.44 MB then `npm ci`), and
`CheckNativeRuntimeManifest` refuses it until then — "Diagrams and graphs"
above, which also has the must-fail measurement. `build_site.py` finds the
folder with no new variable (`toolchain_paths.VENDOR_DIR`), and a build of a
page with a runnable block printed "▶️  This site carries what runs Python
for 2 pages" and carried the five files plus the worker.

**The runtime grows by 13,531,290 bytes** — the five files, 13,531,207 bytes
as the contract's `why` says (pyodide.mjs 17,931; pyodide.asm.mjs 1,250,344;
pyodide.asm.wasm 9,598,218; python_stdlib.zip 2,545,637; pyodide-lock.json
119,077), plus the 83-byte README. `runtime\vendor` went from 42,185,233 to
55,716,523 bytes. A site carries them only when a page students can see has a
runnable block (`codeRunnerBlocks.siteCarriesEngine`).

**Unpacked with the runtime's own Python, not bsdtar.** MEASURED: this PC's
`%SystemRoot%\System32\tar.exe` is bsdtar 3.8.9 with bz2lib 1.0.8, so it
does read bzip2. The script still uses the embeddable Python's `tarfile`
(`r:bz2`; `_bz2.pyd` ships in the embeddable zip), extracting only the five
names and refusing a tarball that lacks one — the same reason the Latin
Modern step gives for xz (an older Windows 10's bsdtar is not known to carry
the library, and the build PC is the only place this runs), and the same
tool the Dockerfile uses (`python3 -m tarfile`). REJECTED: bsdtar, for that
reason; holding the pin open in `NamedGapLedger` instead of fetching (the
fetch was small enough to land with the pin).

**KaTeX: the runtime's lockfile installs 0.16.21, the mac's version.**
`npm ls katex` in `runtime\quartz` gives `katex@0.16.21` (and
`micromark-extension-math`'s copy deduped to it). The three files the
contract pins (`katex.min.css`, `contrib/copy-tex.min.js`, `LICENSE`) match
`katex.files` byte for byte, and the 20 woff2 faces total 259,792 bytes, the
mac's number — so a Windows-built site serves exactly the mac's KaTeX.

**`scripts/test_katex_assets.py` was red on Windows, and the runtime was not
why.** `InstallTests.carried()` listed the copied files with
`str(path.relative_to(...))`, which is `contrib\copy-tex.min.js` here against
the expected `contrib/copy-tex.min.js`; it uses `.as_posix()` now, which is
the same string on the mac. `build_site.install_katex_assets` itself compares
`Path` objects and was right. (Run by hand from a cp1252 console the file
also throws two `UnicodeEncodeError`s on build_site's emoji prints;
`PythonToolchainTests` sets `PYTHONUTF8` and `PYTHONIOENCODING`, so the suite
never sees them.)

**Tests.** `ToolchainContractTests.TheWindowsRuntimeRecipeCarriesTheSamePins`
is green on the `pyodide` pin's `windowsRuntimeContains`;
`TheWindowsRuntimeRecipesVendorVersionsAreTheContracts` holds
`$PyodideVersion`; `TheWindowsRuntimeRecipeChecksPyodidesContractHashes` holds
the recipe's tarball hash and five file hashes against the contract (only
Pyodide's: `nodeTikzjax.sha256` is for the record, `npm ci` checks its own
lockfile); and `TheNativeRuntimeCarriesPyodideAtTheContractsHashes`
(`[NativeRuntimeFact]`, skipped with its reason only where there is no
runtime at all) reads the runtime on the machine back — it FAILS on a
manifest without `pyodide`, as the build does, and on any file or README
that is not the contract's.

### The preview's isolation headers (#591, mac #583): inherited

Windows' preview is Quartz's own server, run from the section's copied
scaffold (`node <builds>\…\section1\quartz\bootstrap-cli.mjs build --serve`,
`cwd` the section), so `build_site._wire_isolation_serve` patches that copy's
`quartz\cli\handlers.js` exactly as on the mac. Two things could have stopped
it and did not: the native-only loopback patch (`fetch-runtime.ps1` rewrites
`server.listen` and the WebSocket server, not the `serve()` anchor), and line
endings (the runtime's `handlers.js` has no CR, and the 8-space
`const release = await buildMutex.acquire()` anchor occurs once). Read back
from a native preview with curl:

| Address | What came back |
|---|---|
| a page with a ```` ```python run ```` block that reads `input()` | `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp` |
| the same with a YouTube `<iframe>` | neither header, and the preview printed `plantoir: note: Lessons/Video Check.md: students type this page's input in a box before Run, because the page also shows a video, a PDF or another web page in a frame - …` (`words.notLiveBecause` + `notLiveFrame`, once per page) |
| the front page | neither header |
| `static/pyodide/*` and `static/swift/*` | `Cross-Origin-Embedder-Policy: require-corp` on every file |
| `pyodide.asm.wasm` / `.mjs` / the workers | `application/wasm` / `application/javascript; charset=utf-8` |
| `static/katex/katex.min.css` / a face | `text/css; charset=utf-8` / `font/woff2` |

**The publish inherits it too**: `deploy.py` → `isolation_headers.py` is
shared, and `verify-deploy.ps1` read the same headers back from Netlify and
Cloudflare Pages (below). Nothing was changed for #591.

### The editor's colours and line numbers (#592, mac #585): carried

`Plantoir.csproj` ships `scripts\**`, `support\**` and `contracts\**` by glob,
and `ToolchainMirror.RecipeFolders` mirrors the same folders into a working
folder's `.toolchain`, so `support\quartz\components\scripts\codeRunnerColour.ts`,
`support\quartz\components\styles\codeLines.scss` and
`scripts\fixtures\runner-colour\` (python.txt, swift.txt) are in the x64
Debug build's `Toolchain\` (checked). Windows does not run
`scripts/check_runner_rules_against_the_site.py` (it needs the image's
Shiki), so #592's item 2 does not apply here.

### Measured in Edge (headless), on a native preview

Headless Edge 155.0.4283.60 through Playwright (`channel="msedge"`, a fresh
profile per context), against the preview above — a section built with
`preview.ps1` from this runtime, served at `http://localhost:8081`. This
PC's WebView2 Runtime is 155.0.4283.62, the same Chromium; the preview pane
itself is measured below ("WebView2"). No Chrome is installed here.

- **Isolation**: `self.crossOriginIsolated` is `true` on the runner page,
  no input box; `false` on the YouTube page, which shows the box and its
  `words.inputAhead` line, and its transcript was `Name? Ada` / `Hi Ada`.
- **Nothing of the engine on load**: 0 requests under `static/pyodide/`
  before Run; Run fetched the worker, `pyodide.mjs`, `pyodide.asm.mjs`,
  `pyodide.asm.wasm`, `python_stdlib.zip` and `pyodide-lock.json`.
- **First Run** (cold, a fresh context each time, empty cache) to the first
  prompt on the page: **2.29–2.42 s, median 2.38 s** (5 runs); the whole
  program with both answers 2.36–2.53 s. **A second Run** on the same page:
  **0.10–0.12 s**.
- **`input()` with two prompts**: Run focused the answer field
  (`plantoir-runner-answer`); `Ada` Return, `blue` Return gave the transcript
  `Name? Ada` / `Colour? blue` / `Hello, Ada who likes blue`, byte for byte
  the box's shape. **Ctrl-D** at the second prompt: `Colour? ` then the
  `EOFError: EOF when reading a line` traceback naming line 2, status
  `Finished with an error.`
- **Stop then Run**: `while True: time.sleep(0.1)` stopped in **0.03 s**
  (`Stopped.`); the next Run reached its first prompt in **2.6–2.9 s**,
  because Stop ends the thread and the next Run starts a new one (a cold
  start from the browser's cache), and ran correctly.
- **One thread after page changes**: 1 worker before, 1 after three round
  trips between the runner page and the YouTube page by the site's own links
  (each crossing the isolation line, so each a whole load) with a run on each
  return.
- **Tab** at the start of a line inserted four spaces; **Shift-Tab** put the
  code back exactly; **Escape then Tab** left the editor.
- **Colours (#592)**, light and dark (`saved-theme`): a line typed into the
  editor (`def f(): return "x" + 42  # note`) was coloured by the tokenizer
  in the same colours as Shiki's static block for the same kinds — `def`
  rgb(215, 58, 73) light / rgb(249, 117, 131) dark, a comment
  rgb(106, 115, 125) in both; the string and number took github-light's and
  github-dark's (rgb(3, 47, 98) / rgb(158, 203, 255), rgb(0, 92, 197) /
  rgb(121, 184, 255)). **Gutter**: 6 numbers for 6 editor lines and 6
  coloured lines, and the copy's text equal to the editor's. **Undo**: each
  Ctrl+Z took one typed character back (Playwright types key by key) and the
  copy and gutter stayed in step after every one. **Hairline**: the
  runnable gutter's `border-right` and a static block's number's
  (`[data-line]::before`) are the same, `1px solid rgb(229, 229, 229)` light
  and `1px solid rgb(57, 54, 57)` dark; `font-variant-ligatures: none`.
- **Maths offline**: with every request not to the preview's own origin
  aborted (the only one asked for was Google Fonts' stylesheet), both
  formulas rendered, `KaTeX_Main`, `KaTeX_Math` and `KaTeX_Size1` loaded from
  `static/katex/fonts/`, and the stylesheet was the site's own.

### WebView2 (the preview pane)

Measured 2026-10-22 on the same PC, unlocked desktop: the x64 Debug app
with `--state-dir` and `--auto-preview PYT1O 1` (the button's own code
path), so the pane showed the app's own preview — Quartz's server at
`http://127.0.0.1:8081`, started by the app from the bundled runtime. The
pane was driven over WebView2's debugging port
(`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=…`), so keys
are Chromium input events, not the OS keyboard. WebView2 Runtime
155.0.4283.62 (user agent `… Chrome/155.0.0.0 … Edg/155.0.0.0`).

- **Isolation in the pane**: `self.crossOriginIsolated` is `true` on the
  runner page (no input box), `false` on the YouTube page (the box shows) —
  the pane is a browser like any other here, and the app adds nothing that
  breaks the headers.
- **First Run to the first prompt**, the cache cleared before each
  (`Network.clearBrowserCache`), 5 runs: **2.17–3.49 s, median 2.27 s** (the
  3.49 s was the first run after the app opened). **A second Run**:
  **0.07–0.08 s**.
- **`input()` with two prompts**: the answer field had the focus at Run; the
  transcript was `Name? Ada` / `Colour? blue` / `Hello, Ada who likes blue`,
  as in Edge. **Ctrl-D** at the second prompt: the EOFError traceback,
  `Finished with an error.`
- **Stop then Run**: stopped in **0.04 s**; the next Run's first prompt
  **2.32 s** (a new thread), and it ran correctly.
- **Tab** inserted four spaces, **Shift-Tab** restored the code exactly,
  **Escape then Tab** left the editor — WebView2 does not take Tab for the
  app's own focus ring while the editor has it.
- **Maths offline**: every request not to the preview's origin aborted —
  both formulas rendered from the site's own KaTeX stylesheet and faces
  (`KaTeX_Main`, `KaTeX_Math`, `KaTeX_Size1`); the only addresses refused
  were Google Fonts' stylesheet and, from the YouTube page being left, one
  YouTube logging call.

### verify-deploy.ps1

Gained the mac's `check_engine` and `check_engine_folder` (#568): each engine
file 200 with a runnable type, a worker CSP that allows wasm, the borrowed
page's runnable block, COOP/COEP on that page and COEP on both engine
folders, none on the front page, KaTeX's stylesheet as `text/css` and a
face, no CSP naming jsdelivr, and the folder publishes' engine and KaTeX
files against the contract's hashes. Swift is checked as
verify-deploy.sh checks it — `static/swift/plantoir-swift-worker.js` and
`plantoir-wasi.mjs` as JavaScript with COEP, the overlay byte for byte, and
since v1.8.6 (#570) the borrowed page's compiled program: the page carries
`data-runner-wasm`, the program answers 200 and starts with `\0asm`, the
folder publishes carry it in `static/swift-wasm/`, and the preview and the
publish that rebuilds say the block is ready (no `plantoir: error:` line,
no `swiftCouldNotBePrepared`). The first run on a PC gets Swift ready
through the preview, the product path (about 2.3 GB, a few minutes). Until
v1.8.6 the program was asserted ABSENT and the not-ready line EXPECTED
(`swift.reasons.notOnWindows`), rather than skipped, so a Windows run could
be the "nothing skipped" run `RELEASING.md` asks for (the #568
implementation review). It also times each Netlify and Cloudflare publish and counts the
bytes sent on the interface the default route uses (route metric plus
interface metric: sorting on the route's alone read a Wi-Fi counter that
never moved beside the wired adapter).

Two runs, 2026-10-22, a scratch course (`PYT1O`: two runnable pages, one
with a YouTube frame, and the borrowed page). The FIRST, from a fresh state
folder and onto new sites: Netlify **19 s** for the first publish with the
engine ("Netlify requires 17 file"), Cloudflare **33 s**; then **11 s**
("8 file") and **20 s** ("Uploaded 7 files (46 already uploaded)") again.
Its byte counts read 0 (the Wi-Fi counter; fixed above), so the number of
bytes a first publish of the engine sends is not measured here. The SECOND
run, onto the same sites: **140 passed, 0 failed, 8 skipped** (the eight
were the Swift program, once per host and folder, then reported as skips;
these totals are from BEFORE the change above, which turns those eight into
asserted passes, so a clean run should now read 148 passed, 0 failed,
0 skipped — the next release run re-measures it); publishes of 10–12 s to
Netlify ("7 file", 182–239 KiB sent) and 20–29 s to Cloudflare ("Uploaded 7
files (46 already uploaded)", 400–709 KiB) on Ethernet.

**What the first run also found, not fixed here:** on a FIRST publish (no
saved surname, a new site) two of the harness's answered prompts failed
`Assert-OnlyExpectedPromptsWereAnswered`, because the line PtyDriver saw
joined the sentence before it with no line break: "…It is saved on this
computer and only asked once.First time setup... what is your last name?
(letters only):" and "…all users across the world.Enter Netlify site name
[pyt1o-s1-2026-testing]:" (and in the log, "Saved teacher last name for
future deploys: testingChoose a Website Address."). The answers were the
right ones and the publishes succeeded; the anchored patterns are what
refused them. It predates this piece (nothing here touches `deploy.py`'s
prompts or PtyDriver) and is #623.

## Runnable Swift on Windows (#570, the mac's #493), v1.8.6

Since v1.8.6 a ` ```swift run ` block built on Windows is a program a student
runs, exactly as one built on a Mac. Until then (v1.8.0–1.8.5, #493 option
(b)) Windows compiled nothing and every block said
`swift.reasons.notOnWindows`; that reason and the 1.8.5 stopgap are gone.
The site's half (the transformer, `SwiftWasmRuntime`, the worker and the
WASI shim in `support/gated/swift/`) was never platform-specific and is
unchanged. The mac compiles in a second container image (05 → Runnable
Swift, 02 → The Swift image); Windows has no container, so what replaced the
image is a one-time fetch of the swift.org **Windows** toolchain, and what
runs `compile.py` is a small wrapper.

### What happens at a preview

`preview.ps1`'s `Invoke-RunnableSwift`, just after "Running the website
builder on this PC" and before `build_site.py`. It is the order of
`preview.sh`'s `prepare_runnable_swift`:

1. **Plan**: `swift_blocks.py plan --course=C --format=lines`, with the
   bundled Python (the shared plan; the cache is
   `%LOCALAPPDATA%\Plantoir\builds\<id>\<CODE>\.swift-cache\<toolchain id>`).
   If nothing is waiting, nothing else happens, so a teacher who never
   writes Swift never downloads Swift.
2. **Get Swift ready**: `swift_windows_fetch.py ensure`, IN THE FOREGROUND,
   as the mac builds its image in the foreground. If Swift is already ready
   it says nothing. If not, it prints `codeRunnerBlocks.swift.windows.printed`
   in this order: `gettingReady`, then `gettingReadyPercent` about every ten
   per cent (the mac goes quiet for its minutes; a school line takes about
   six here), `unpacking`, then `ready`, followed by a `PLANTOIR_SWIFT:`
   line for the trail.
3. **Compile**: `🦅 Making N Swift programs ready to run…`, then
   `swift_windows_compile.py <jobs> <cache> --log=<.swift-cache\logs\compile-<pid>.log>`.
4. **Prepare**: the build, unchanged. It reports `🦅 6 of 7 Swift programs
   on this site ready to run`, a `plantoir: error:` line for each block that
   has no program, and the `swiftCouldNotBePrepared` folder problem.

Exit codes of `ensure` (`windows.ensureExit`), and the `state.json` the
launcher writes for prepare:

| Exit | State | Cause |
|---|---|---|
| 0 | none | Ready. |
| 10 | `noRoom` | Too little room. |
| 11 | `notDownloaded` | Offline, or a download that was not what was pinned. |
| 12 | none, so the build says `notCompiled` | Another installation running, an unpack that failed, or the wait for another launcher gave up. |

The reasons are the mac's own. `notDownloaded`'s
"(the first time downloads about {downloadGigabytes} GB)" is filled per
platform (`swift.downloadGigabytes`: 1.3 on a Mac, 2.3 here), so the mac's
rendered sentence is byte for byte what it was.

**A scheduled publish can do the first fetch unattended.** It runs
`preview.ps1 --build-only`, so it gets Swift ready and compiles too (the
mac's ruling Q4). On a PC where no preview has got Swift ready yet, the
first scheduled publish of a course with a Swift block downloads the 2.3 GB
on its own, typically overnight with nobody watching, and the publish waits
for it (about three minutes here, longer on a slow line). Nobody sees the
percent lines, which go only to the run's log. What the teacher sees later:
- the trail line "Swift got ready on this computer" (or "Swift could not
  be got ready", with the reason), because `TaskScheduling.cs`'s wrapper
  keeps the `PLANTOIR_SWIFT:` line and `ScheduledHealthFindings` records
  it, dated to the run;
- on the published site, every block runnable, or the usual "not ready" for
  each block, with the `swiftCouldNotBePrepared` folder problem waiting at
  the next launch, as for any scheduled build's folder problems.

A scheduled run that fails offline tries again at the next run or preview.
Nothing is downloaded for a course with no Swift.

### What is fetched, where, and how big

Everything is pinned in `contracts/toolchain.json` → `swiftWindows`, and
everything is non-admin. Measured 2026-10-22 on this PC (Lenovo 20QES70500,
i5-8365U, 4 cores / 8 threads, 16 GB, Windows 11 Pro 26200, Ethernet, not
elevated):

1. The swift.org installer,
   `swift-6.4.0-RELEASE-windows10.exe` (2,097,914,680 B). The download
   resumes with HTTP Range. Its SHA-256 is checked, then its Authenticode
   signer: Windows' own `Get-AuthenticodeSignature` must say `Valid`, with
   `CN=Apple Inc.` and `O=Apple Inc.` in the subject. It is the only Windows
   artifact swift.org publishes; there is no checksum entry and no `.sig`.
   So the pinned SHA-256 is the check, and the signature is defence in
   depth.
2. The bundle's payloads sit in ONE solid LZX cabinet attached at byte
   1,312,800. The fetch checks for `MSCF` there, a cbCabinet of
   2,096,591,258 (pinned), and that the cabinet ends inside the file
   (10,622 B before its end, where the signature is). Then it copies the
   cabinet out.
3. Windows' own `expand.exe container.cab -F:<id>` takes out `a1`
   `bld.noasserts.msi`, `a14` `bld.noasserts.cab`, `a10` `rtl.amd64.msi`
   and `a23` `rtl.amd64.cab`. Each is checked against the **SHA-512 in the
   bundle's own Burn manifest** (`Payload/@Hash`, Apple's), so no second
   2.1 GB download was needed to take hashes.
4. `msiexec /a <msi> TARGETDIR=<dir> /qn` (an administrative extraction: no
   UAC, not elevated) for the compiler and the runtime. Exit 1618 (another
   installation running) waits 30 s, three times, then gives up as `busy`.
5. A trim to the measured set (`trim.remove` / `mustKeep`): from
   1,874,323,927 B to 533,231,069 B. The VC++ runtime DLLs from the runtime
   MSI (`trim.vcRuntime`) go beside the tools, because a PC without the
   redistributable lacks VCRUNTIME140, VCRUNTIME140_1 and MSVCP140.
6. The mac's own wasm SDK pin (92,760,992 B), unpacked with `tar.exe`, and
   binaryen version_133 x86_64-windows (111,045,528 B), of which only
   `wasm-opt.exe` is kept, OUTSIDE the toolchain's `bin`.
7. A smoke compile of one tiny program through the real wrapper. An install
   that cannot compile is never marked ready. Then `READY.json` (the pins'
   digest, the bytes kept and the seconds per step) is written, and the
   staging folder is renamed to `%LOCALAPPDATA%\Plantoir\swift\6.4.0`. The
   installer and the tarballs go only then, so a step that fails late
   needs no second download.

**Downloaded:** 2,301,721,200 B (about 2.3 GB). **Kept:** 898,260,086 B
(the toolchain 533,231,069 B, the SDK 354,685,593 B, wasm-opt
10,343,424 B; `swiftWindows.keptBytes`). The measurement's hand trim was
3,268 B smaller, because it also removed `usr/bin/clang-deps-launcher.py`,
a Python script nothing here runs, which `trim.remove` does not name.
`keptBytes` is not part of the install digest, so correcting it fetched
nothing again. **Peak while
unpacking:** 4,817,697,631 B, sampled every 2 s (the installer, the carved
cabinet and the extraction overlap). That is inside the shared
`room.needGigabytes` of 6, which is checked before anything is downloaded.

| Run | Download | Check (hashes + signature) | Expand | msiexec + trim | SDK + wasm-opt | Smoke | Total |
|---|---|---|---|---|---|---|---|
| `ensure` on its own | 21.5 s | 40.1 s | 31.3 s | 56.0 s | 7.6 s | 6.8 s | **164 s** |
| `ensure` resumed after a kill 6 s in (478 MB already there) | 22.7 s | 47.4 s | 15.4 s | 29.0 s | 4.1 s | 6.2 s | **126 s** |
| inside the first `preview.ps1 EXC2O 1 --build-only` | | | | | | | **127 s** (preview 263 s in all, 7 blocks compiled) |

The download ran at about 100 MB/s here. A 50 Mbit/s school line would take
about six minutes, which is why the percent line exists.

**A kill is safe.** Stop Preview ends the fetch with the launcher. The
partial `.part` is resumed with Range the next time (measured above). Once
the next fetch holds the lock it deletes every `staging-*` and `old-*`
folder, and prunes a version folder for other pins, as the mac prunes
superseded images. One fetch at a time per PC: `fetch.lock` is held with
`msvcrt.locking` for the life of the process, so a killed holder releases
it by dying. A second launcher prints `waitingForAnother` and waits up to
1,200 s, the mac's `take_the_swift_build_lock` limit, then
`stillGettingReady`.

**The first real run failed, and that changed two things.** Renaming the
compiler's folder the moment `msiexec` had written it said "Access is
denied" (most likely Defender scanning the new files). With the installer
already deleted, the retry cost a second 2.1 GB download. Now every folder
move is tried again for up to 20 s (`move`, `rename_into_place`), and the
installer is kept until Swift is ready, which makes the measured 4.82 GB
peak about 0.3 GB higher than deleting it after the carve would.

**Uninstalling Plantoir leaves the 0.9 GB** in `%LOCALAPPDATA%\Plantoir\swift`,
as it leaves the assistant's models. Delete the folder to reclaim it; the
next Swift preview fetches again.

### The compile wrapper: compile.py unchanged, adjusted for this PC

`scripts/swift_windows_compile.py` sets `PLANTOIR_SWIFTC`,
`PLANTOIR_SWIFT_SDK` and `PLANTOIR_WASM_OPT` to the install, then imports
`support/swift/compile.py` from the working folder's `.toolchain` without
writing `__pycache__` beside it. It then changes these names, each checked
to exist by `test_swift_windows.py` (`PATCHED`), so a rename in compile.py
fails a test instead of silently going unpatched:

- **`environment()`.** `PATH` is the toolchain's `bin` plus System32, with
  `SystemRoot`, and `TEMP`/`TMP`/`USERPROFILE`/`HOME` in
  `swift\work\tmp`. compile.py's own environment (`…:/usr/bin:/bin`,
  `HOME=/tmp`, no `SystemRoot`) made every block "compile" in 1.8 s as
  `error: permissionDenied`, cached as the code's fault.
- **`CLANG`** is `clang.exe`.
- **`OBJECT_ROOT`** is `%LOCALAPPDATA%\Plantoir\swift\work`, a fixed
  folder per block. Measured: the same code in the same folder gave the same
  bytes (01-greeting compiled again was byte-identical to the preview's
  program). Programs from two different homes differ in 16 bytes, the
  module hash (spike G4). Two previews compiling one block would share its
  folder, so each block is taken under a lock file of its own, and a
  preview that finds the lock held leaves that job to the other.
- **`-nonlib-dependency-scanner`** on both compiles
  (`windows.compile.extraCompileFlags`). Without it, the libSwiftScan
  warning was the first line of every cached diagnostic.
- **`tidy()`** strips the work folder in both separators, and keeps a
  failure's words ONLY when they carry `error:`. The guard is the
  environment fix, plus the preflight below, plus this rule: a failure with
  no `error:` in it goes down compile.py's own "stopped without saying why"
  path and is not cached. `run()` turns a missing program (`OSError`) into
  `NotTheCompilers`, also not cached.
- **`JOB_SECONDS`** is `compile.jobSecondsOnWindows` (600), and at most
  `mostFullAtOnce` (2) full-library compiles run at once. The worker count
  is compile.py's `main`'s local, so the wrapper runs its own loop with one
  worker per CPU and holds a semaphore around the full-library
  `compile_one_way`.
- **A preflight before any job**: the tools, the SDK and one tiny program.
  If it fails, the wrapper exits 3, touches no job and caches nothing.

**The toolchain id on Windows** (`cache.toolchainIdFromOnWindows`) hashes
the four recipe files with their CR LF made LF (this checkout writes CR LF;
the id must not differ by accident), the wrapper, and the canonical JSON of
the pins' HASHES (installer SHA-256, payload SHA-512s, configuration, SDK,
binaryen). A Windows cache and a Mac cache
therefore never share an id, a moved Windows pin compiles everything again,
and a `why` edit compiles nothing. The mac's id is unchanged byte for byte:
its branch normalises nothing, and a test recomputes the old formula.

### Measured: the gate and the product path

- **swift-gate, through the product wrapper.** The 15 fragments compiled in
  **165 s** wall. The measurement's bare loop, eight full-library compiles
  at once, took 153 s; two at a time costs about the same wall time and
  keeps every wasm-opt step near its 50 s alone. The program sizes and
  libraries are the mac's README table exactly (01 = 62,347 embedded,
  05 = 3,453,463 full, 15 = 39,652). `node browser-checks/wasi_run.mjs` on
  an LF copy printed `OK: 15 fragments and the shim's own checks`,
  including the G5 must-fail and live input.
- **A course (EXC2O) with verify.sh's 7-block Swift Playground page.**
  - Getting ready plus the build: 263 s.
  - A preview with the cache emptied took 91 s. Its compile log: embedded
    blocks 4.7–12.5 s each, the full-library block 60.3 s (almost all of it
    wasm-opt), and the broken block's compile error in 3.4 s.
  - The build then said `🦅 6 of 7 Swift programs on this site ready to run`
    and one `plantoir: error: Exercises/Swift Playground.md: swift block 5,
    line 64: Swift found an error in it: cannot find 'nmae' in scope`.
  - **The next preview took 28 s and compiled nothing.**
- **`browser-checks/swift_runner.mjs` in headless Edge 155.0.4283.60**
  (Node 20 with `--experimental-websocket`, against that build):
  `OK: {"embeddedFirstRun":{"ms":70,"bytes":62347},"fullFirstRun":{"ms":123,"bytes":3453463},"stopMs":7}`.
  The WebView2 pane (the same Chromium) was not driven.
- **`verify-deploy.ps1`**, against `~/Desktop/plantoir-deploy-verify` (ICS3U,
  with Swift already ready on the PC), took 14 minutes:
  **148 passed, 0 failed, 0 skipped**. Those are the totals the earlier
  measurement predicted for a clean run once the eight standing Swift skips
  became checks. The page's program (45,844 B) answered HTTP 200 as
  `application/wasm` from Netlify, Cloudflare and both pairings; every folder
  publish carried it in `static/swift-wasm/`; and the preview and the
  publish that rebuilt said nothing was wrong with the block.
- **A trap for whoever runs these here:** with `core.autocrlf=true`,
  swift-gate's `.expected` and `.stdin` are CR LF. `wasi_run.mjs` and
  `swift_runner.mjs` both FAIL on line endings alone (the full-library
  block's output "does not match"). Run them against LF copies of the files.

### The wasm-opt risk

On this i5-8365U a full-library block costs about 50 s, against the mac's
7–10 s. wasm-opt `-Os` is 48.9 s of it: 105.4 s with one thread, 48.1 s with
eight, and identical output every time. The likely cause is that wasm-opt
uses the MSVC CRT's allocator where the Swift tools load mimalloc; that is
unproven. 600 s per step and two at a time leave a slow PC about ten times
the margin. A block that still passes the limit is not cached, so it is
tried again at every preview, and the build says `notCompiled` meanwhile.
The cure for a teacher is the one the skill already gives: a one-argument
`print` stays Embedded (5–12 s). **Not measured:** a slower PC, Windows on
Arm (not pinned: the app is win-x64 only), and the WebView2 pane.

### Where Windows deliberately differs from the mac

| The mac | Windows | Why |
|---|---|---|
| A second container image, built by Docker from `support/swift/Dockerfile` | The swift.org Windows installer, unpacked without elevation | No container on Windows since 2026-08-19 |
| `docker run --network none` isolates the compile | The compile runs as the teacher, with the network there | No container to isolate in; the job is the teacher's own code |
| The image tag hashes `support/swift`; the Docker layer cache holds it | `READY.json` carries the pins' digest; a version folder for other pins is pruned | Nothing is built, so nothing is tagged |
| The image build goes quiet for its minutes | A percent line about every 10% | A 2.3 GB download on a school line |
| `/tmp/plantoir-swift/<key>`, a different `/tmp` per container | `swift\work\<key>`, shared by every preview, under a per-block lock | One host, one folder |
| 1.3 GB downloaded, 2.24 GB kept | 2.3 GB downloaded, 0.9 GB kept | Each platform's smallest working form |
| GPG signature, plus a SHA-256 per tarball | SHA-256 on the installer, Apple's SHA-512 per payload, Authenticode as defence in depth | swift.org publishes no Windows `.sig` |

**Rejected** (`swiftWindows.rejected`):

- Carrying Swift in the installer: 0.9 GB for every teacher.
- `swift sdk install`: it needs MSVC's `link.exe`.
- `installer.exe /layout`: it copies only itself.
- An HTTP Range fetch of just the payloads: one solid LZX folder, measured
  MISMATCH.
- The default asserts toolchain.
- WiX's `wix burn extract`: a .NET tool to ship, where `expand.exe` comes
  with Windows.
- cabinet.dll FDI in-process, to avoid carving: the next step if the peak
  ever matters.
- **A background fetch with a progress banner**: planned first, and
  replaced on plan review by matching the mac (the preview waits). It needed
  a reason the mac never shows, a window, and a status file the app polls,
  for a once-per-PC wait.

### Recorded on the trail

`activityTrail.mustRecord` has two events: **"Swift got ready on this
computer"** (seconds, gigabytes) and **"Swift could not be got ready"**,
with the reason as one of offline, noRoom, damaged, busy, unpack (also
anything unexpected, such as a signature check that hangs past 300 s:
`ensure` turns every exception into one, so the console never shows a
traceback without its marker) or waited (another preview held the fetch for
longer than the 1,200 s wait) (`whyWords`). Every ending of `ensure` but
"already ready" prints the marker. They are read from the `PLANTOIR_SWIFT:` line by
`SwiftGotReady.cs`, in both readers (the console's
`ScriptRunner.RecordHealthFinding`, and the scheduled publish's
`ScheduledHealthFindings`), and in the scheduled wrapper's marker scan
(`TaskScheduling.cs`). A wrapper written before this change keeps no
`PLANTOIR_SWIFT:` line until that deploy is scheduled again, as for
`PLANTOIR_MY_PROGRESS:`. Neither event carries `appliesOn`: the mac has
recorded both since v1.9.0 (#635), from the same `PLANTOIR_SWIFT:` line, which
`preview.sh` prints after building its Swift image (05 → "Recorded on the
trail, on both platforms"). Its bytes and reasons are worked out by
`swift_blocks.py got-ready` against `codeRunnerBlocks.swift.mac`, whose cases
`test_swift_blocks.py` runs here too through `PythonToolchainTests`; nothing
in this app changes for it.

### Shared fix the mac inherits

`swift_blocks.prune` deleted the launcher's `logs\` folder with every older
toolchain's folder, so a compile log never survived its own build. That was
found here, where the first preview's `compile-<pid>.log` was gone.
`LOGS_FOLDER` is now kept; `test_swift_blocks.py` →
`PruneKeepsTheLogsTests` pins it.


## The trail's first and last lines (#565, the mac's #560), v1.8.0

**"Plantoir opened" prints the version a teacher can name.** It was built
from the assembly version as `Major.Minor (Build)`, so `<Version>1.7.2</Version>`
read "Plantoir 1.7 (2)" while the update lines on the same trail said "from
1.7.1 to 1.7.2". `ProblemReportEnvironment.AppVersion` now spells it with
`AppUpdates.Spell` (the updater's own spelling, #465) and adds a build in
brackets ONLY when the assembly carries a revision. Windows has no build
number of its own: `<Version>1.7.2</Version>` makes the assembly 1.7.2.0, so
the line is "Plantoir opened — Plantoir 1.7.2 · pid N · C:\…\Plantoir.exe".
An unused second `NoteLaunch(appVersion, buildNumber, …)` overload, which
printed a third shape, is gone.

**"Plantoir closed — {reason} · pid N"** (`ActivityTrail.Event.AppClosed`,
`mustRecord` → "app closed") is new on both platforms. The reasons, from
`QuitConfirmation.ClosingReasonFor`:

| What happened | Reason on the trail |
|---|---|
| The teacher closed the last window — including with an update ready, which installs as Plantoir quits (`AtQuitGated`): that quit is still theirs, as the mac rules for Install on Quit | quit by the teacher |
| `App.QuitForUpdate`, the updater's own exit after starting the installer | to install a new version |
| `WM_QUERYENDSESSION` / `WM_ENDSESSION` carrying `ENDSESSION_CLOSEAPP` (lParam bit 0x1) — Restart Manager closing this one app, which is how the installer (`installer.iss` `CloseApplications=yes`) closes a running Plantoir | to install a new version |
| The end-of-session messages WITHOUT that bit: a sign-out (`ENDSESSION_LOGOFF`), restart or shut down | asked to close by Windows |

**Where it is written, and why there.** From `App.QuitTime`, after the
update-at-quit decision; and from `SessionEnding`'s window subclass on
`WM_ENDSESSION` with wParam TRUE, BEFORE `DefSubclassProc` returns, because
at the end of a session Windows may end the process before the last window's
`Closed` ever runs. Once per process (every subclassed window hears the
message, and the last window's close may follow it), and only in a process
that wrote its own "Plantoir opened" — the same guard, so a scheduled run or
a marketing capture leaves no unpaired close. The end-of-session path waits
at most 500 ms IN ALL — for this process's own trail lock and the writers'
cross-process lock together (`ActivityTrail.Append` with
`Monitor.TryEnter`) — instead of the usual 5 s for the cross-process lock,
which is about Windows' own kill timeout. A line that cannot get the lock in
that time is dropped rather than holding the session up, and is tried only
once (there is no later moment). The ordinary quit's line waits for the
locks as every line does, and counts as written only once it has reached the
file (`Append` returns whether it did).

**Rejected:** reading "install" from the at-quit install (it fires when the
teacher quits with an update ready — the mac's `willInstallUpdate` trap); a
fourth "asked by another program" reason (a scripted close sends the same
`WM_CLOSE` as the title bar's X). **Not measured:** a real sign-out, restart
or installer run. The reason table is pinned by
`AppOpenedAndClosedTests.TheReasonIsReadFromWhatTheAppKnew`, the once-only
guard by `TheClosedLineIsWrittenOnceAndOnlyAfterTheOpenedLine`.

## My Progress: the trail line and the two readers (#599, the mac's #545), v1.8.2

The page itself is shared toolchain, and Windows inherits it with the build.
What Windows owed:

- **`my progress page built`** (`ActivityTrail.Event.MyProgressPageBuilt`),
  read from the build's `PLANTOIR_MY_PROGRESS:` line by `MyProgressBuilt` —
  the `CoverageMapsBuilt` pattern — in the console reader
  (`ScriptRunner.RecordHealthFinding`, and the 8000-character carry guard),
  the scheduled publish's record reader (`ScheduledHealthFindings`) and the
  wrapper's marker scan (`TaskScheduling.cs`). A scheduled-deploy wrapper
  written before this change has no `PLANTOIR_MY_PROGRESS:` in its scan, so a
  scheduled run's line reaches the trail only once that deploy is scheduled
  again — the same as for `PLANTOIR_MAPS:`. The sentences are
  `myProgressBuilt.trailLine.shapes`, "N page(s)" spelled 1 page / N pages.
- **`include_my_progress` and `success_criteria_headings`**, read-only
  (`CourseConfiguration.IncludesMyProgress(section)`, `SuccessCriteriaHeadings`;
  the switch and the list are #595), run against `myProgress.config.cases`.
  `include_my_progress` is read as the BUILD reads it
  (`build_site._resolve_section_switch`): a map's `sections` entry, then its
  `sectionN`, then its `default`, else on; any other value by Python's truth,
  so the string "false" is on. **A known difference, left alone:**
  `IncludesCurriculumCoverage` here honours only a boolean or
  `sections.sectionN`, while the build also honours the flat and `default`
  forms. Only a hand-edited config can show it — both apps write the
  `sections` form — and it is noted on #595 rather than changed here.

**Measured** (this PC: i5-8365U, Windows 11 Pro 26200; the bundled runtime's
Python 3.11.9 and node 20.18.1; Edge 155.0.4283.60 headless; 2026-10-22): a
native `preview.ps1 EXC2O 1 --build-only` of the example course, with one
"Success criteria" list of three boxes added to a published class, took 37 s,
printed `PLANTOIR_MY_PROGRESS: {"course": "EXC2O", "section": 1, "built":
true, "pages": 1, "reason": "built"}` and wrote `My-Progress.html` (24,405
bytes; the slug, not "My Progress.html") and `progress-manifest.json` (1,324
bytes, the three items under "Unit 3, Day 14"); Key Links links it. In Edge,
on a fresh profile, it read 0 / 3; two ticks on the class made it 2 / 3 under
Unit 3, Day 14, and a reload kept 2 / 3.

## Undo: three verdicts, not two (#564, the mac's #555), v1.8.0

`UndoHistory.Undo` had two outcomes per file, put back or skipped, and kept
the entry while anything was skipped. A file an earlier press had already put
back holds its BEFORE text, so it was skipped too, and a change taken back in
part never came off the list. Russell's ruling on #555 (option 2): such a
file is ALREADY BACK. Each saved file now gets ONE verdict,
`UndoVerdict.Of(path, state)`:

- **alreadyBack** — the disk holds BEFORE: nothing is written, it is not
  counted as put back, and it does not hold the entry. BEFORE is compared
  first, so a row the change left as it found it cannot stick.
- **putBack** — the disk holds AFTER: BEFORE is written back, or the file
  deleted when BEFORE is null. A write that fails is left alone, as on the mac.
- **leftAlone** — anything else.

"Null" means NOTHING at the path: a folder, or a file that is not UTF-8, is
neither copy and is left alone (the old `File.ReadAllText` decoded non-UTF-8
bytes silently and called a folder "no file"). The strict reader drops ONE
leading byte-order mark first, because the saved copies came from
`File.ReadAllText`, which drops it — the mac's `String(contentsOf:encoding:)`
does the same — so a page saved with a mark still matches its copy.

`UndoResult.Answer` picks the sentence: every file back → `undid` (even when
this press found them all already back); written and left → `undidPartly`;
nothing written and something left → `couldNotUndo`; nothing at all →
`nothingToUndo`. No new AssistWording sentence. `NoteAChangeWithNoUndoEntry`
fires exactly on `undidPartly`. The start-of-year undo sheet previews by the
same verdict (`AssistWorkspace.WhatAnUndoWouldDo`): put back under
`undoIntro`, staying under `undoSkipped`, a page already back in neither, and
`startOfYear.wording.undoAllAlreadyBack` when both are empty. (Before this it
listed every written file, with no preview of what stays.)

The preview: `AssistToolRunner` restarts the preview whenever it stopped one
for an edit tool, whatever the tool wrote, so an undo that writes nothing
already put the preview back here. It is pinned now
(`SectionVerbsTests.AnUndoThatFindsEveryPageAlreadyBack_StillRestartsThePreviewItStopped`).
The rows are `assist-cases.json` → `undoFiles`, run by `UndoFilesContractTests`;
by copy-and-restore of the old rule, 5 tests went red.

## The Start of Year sheet as a table (#619, the mac's #589), v1.8.4

`StartOfYearSheet.Make` cuts the plan into what the dialog draws, and
`Views/StartOfYearSheetView` draws it on #548's `PlanTable.Row` and
`PlanTableOrder`:

- **Above the table**, in a scroller: the warnings first (already taught,
  the scheduled deploy, the first class in draft), in the caution colour, then
  the intro.
- **The summary**: the two list headings, unchanged.
- **The table**: Page (`AssistWording.MenuPlanPageColumn`), Folder
  (`MenuPlanFolderColumn`), Why (`StartOfYearWording.ReasonColumn`, the new
  `startOfYear.wording.reasonColumn`); a row for every page going into draft,
  classes first and then pages, in plan order, sortable by a header. The
  title cell has no quotation marks and the folder is always shown. Why is
  `StartOfYearWording.Reason`, the clause the line always carried, word for
  word; it takes the rest of the width and wraps to two lines.
- **Under it**, in a scroller: publishing from now on, the links left
  pointing at hidden pages, and the pages with no room for a key FIRST; then
  already in draft and what stays.

**The no-room note is now said BEFORE Go.** Until #619 it appeared only in
the result. `StartOfYearPagesWithNoRoom` asks the write's own rule
(`StartOfYearDraftEdit`, shared with `PrepareForStartOfYear`), so the sheet
names exactly the pages Go will leave as they are. The MCP text
(`Describe`) is unchanged, and every sentence on the sheet is one it, or the result, says (the no-room note is the result's `AssistWording.PagesWhoseSettingsCannotBeAddedTo`).

**The height rule** (`StartOfYearSheetLayout.For`, pure). The mac's fixed
620 pt budget cannot be copied: this window's minimum height is 600 epx, and
a ContentDialog cannot scroll content it clips. So the budget is the window's
height (at most `ContentDialogMaxHeight`, 756 — since #634 a taller window
gives the table its added height, row by measured row, and the sheet's width
follows the window as the Section menu's does) less the measured chrome, and
the parts give way in an order, each scrolling inside itself rather than
being cut:

1. the ROWS, from five down to two (each counted at its own measured height
   — a Why on two lines makes a taller row than #548's 32 epx pitch);
2. the notes, never below what must be read before Go, nor below the mac's
   120 floor when they are that tall;
3. the intro above, down to the warnings — the warnings are NEVER capped;
4. on a window too short for all of that, the notes down to two lines.

The dialog measures each part at its width, logs the fit to `startup.log`
("Start of Year sheet: …"), reads its real chrome from the laid-out dialog
("Start of Year sheet laid out: …") and refits with it, and refits again
when the window changes size.

**Measured** (this PC: i5-8365U, Windows 11 Pro 26200, 1920 × 1080 at 150%,
2026-10-22; the app's own `--stage-scene start-of-year` on a worst-case
ICS3U section 2: its first class in draft, classes dated before today, a real
scheduled deploy, a page with no room for a key, 175 rows, the links-left
list 30-odd pages long):

| Window (XamlRoot) | Warnings | Above shown | Rows shown | Notes: must-read / all / shown | Dialog |
|---|---|---|---|---|---|
| 700 epx (the scene's window) | 185 | 185 of 249 | 2 (66) | 349 / 474 / 199 | 699 epx |
| 563 epx (the 600 epx minimum, less its title bar) | 184 | 184 of 248 | 2 (66) | 348 / 472 / 63 | 563 epx |

- The chrome measured **250–251 epx** against the layout's 250 (now 251);
  the dialog refits with what it reads.
- **The three warnings are never cut** (184–185 epx); the intro under them
  scrolls in its area in this worst case.
- **Rows are 32 epx on one line and 50 epx when Why wraps to two** (a
  reason naming a 42-character page title). The Why column is 272 epx wide.
- **What does NOT hold in this worst case, said rather than hidden:** the
  must-read notes (348 epx, almost all of it the links-left list) do not fit
  whole at either height, so the notes area scrolls — 199 epx shown at 700,
  63 at the minimum. Everything stays reachable by scrolling inside its own
  area; nothing is clipped out of reach. The mac's 120 pt notes floor cannot
  be kept at the minimum window once the warnings (never capped) and two
  rows are placed: 563 − 251 − 184 − 66 = 62. A short plan (no links left,
  no warnings) shows its notes whole.

**Rejected:** the mac's fixed budget (above); a What-changes column, two
tables, rows for the staying pages, and a table in the MCP text (the mac's
rejections, `09-mac-app.md` → "The pages as a table (#589)"). The
start-of-year picture on plantoir.app is retaken separately.

## The picker as a table, the plan folds, the dialogs follow the window (#634, the mac's #608, #621, #622), v1.8.6

The mac's v1.8.6 changed three things in the Section menu's page sheets
(`documentation/09-mac-app.md` → "The plan as a table (#524)" → "v1.8.6",
which has its measurements and what it rejected). This is what Windows did
with each, and where it could not be the same.

**The wording.** Five keys: `menuPickDateColumn` is the constant
`AssistWording.MenuPickDateColumn`; the other four are ONE mac method,
`menuPlanShowAlready(count:publishing:)`. The contract walk resolves every key
to a member of its own name, so Windows has the dispatcher
`MenuPlanShowAlready(count, publishing)` — what the dialog calls — and the
three members it returns (`MenuPlanShowAlreadyHiding(count)`,
`MenuPlanShowAlreadyOnePage`, `MenuPlanShowAlreadyOnePageHiding`), the shape
`MenuPlanSummary` set. `ContractTests` asserts all five by hand, through the
dispatcher, with the generator's samples. No ledger entry, no contract edit.

### 1. The picker and the later-classes question are tables

`Views/TickTable` draws all three: Publish Pages… and Hide Pages…'s first stage
(Page, Folder, Date) and #475's question at Publish Pages… and at Deploy (Page,
Date). One builder, so the three cannot drift. A `ListView` with
`SelectionMode = Single` — there has to BE a selected row for Space to tick —
1-epx border, a plain header (the mac's picker does not sort, so neither does
this), each row a `CheckBox` whose content IS the title (trimmed, the whole
title in its tooltip), the folder, and the date cell: a class's day as
`AssistWording.LaterClassesDay` says it, empty for a page that is not a class.
Rows are banded (`SubtleFillColorSecondaryBrush` on alternate rows), counted
by the rows SHOWN, so a search or a sort never puts two bands together; the
plan table and Start of Year are banded the same way (the mac's reason: the
two steps of one flow look alike). Ids: the boxes keep `sectionVerbPage<i>` and
`laterClass<i>`, the rows are `sectionVerbPageRow<i>` and `laterClassRow<i>`.

**The tick rules, and how each is made:**

- A click on a box ticks it — and a click on its title, which is the box's
  content (the mac's Xcode-membership shape). Native.
- Selecting a row ticks nothing. Native: `ListView` selection never touches
  the box.
- Space ticks the row with the focus, else the selected row: the list's
  tunnelling `PreviewKeyDown`. A held Space's repeats are ignored
  (`KeyStatus.WasKeyDown`), so holding it ticks once rather than flickering. The plan review (amendment 2) asked whether a
  focused `CheckBox`, which clicks on key-UP, would then flip twice. MEASURED:
  Space after a mouse click on a box flipped it once with a key-up handler,
  and once with that handler's key renamed away — so the handler was taken
  out. (A box whose key-down never arrives has nothing to click on key-up;
  the test did not read where the focus sat after the click, so that part is
  reasoning.)
- Space typed in Find a Page ticks nothing: the field is the list's sibling,
  so its keys never reach the list's handler.
- Return with a row selected reaches Continue — when Continue is live —
  because a `ListView` keeps Return for itself (measured for #548), so the
  table catches it. At Deploy, a plain `ContentDialog`, Return records "the
  main button" and hides the dialog, and the answer is read as Hide Ticked and
  Deploy. Escape needs nothing: it reaches the dialog.
- **Narrator** hears each row's state: `AutomationProperties.ItemStatus`
  "ticked" / "not ticked", set on every change (the plan review's amendment 1).
  A box is named by its title — "title — folder" for two pages of one title —
  and its row "title, folder, date". **The later-classes box was named
  "title — day"** while the day was in its words; it is the title now, and the
  row carries the day.

**The height counts every page offered**, never the search's leftovers, so
the dialog stays still while the teacher types: `PageTableLayout.PickerRows`
— up to 12 (the mac's `mostPickerRowsShown`) within 756 epx, fewer on a short
window, never fewer than two (one for one page), never more than offered — as
a fixed `Height`.

### 2. The plan folds the pages already right

`PlanTable.RowsToRead` (every change, and every page that stays for a reason:
kept by an unpublish, a linked class left as it is, no room for a key),
`RowsAlreadyRight` (already visible, already hidden — those two only),
`FoldsAlreadyRight` (both non-empty, the mac's `foldsAlreadyRight`),
`DrawnRows(open)` and `FoldLabel` are pure and unit-tested. The dialog draws
`DrawnRows(open)` through the ONE sort: one table, one sort. Opened, the
folded rows are drawn in that sort among the rows to read — in plan order
they come where the plan puts them (the pages already right are its last
group), under any other sort mixed among the rest; never a second list. The disclosure is a borderless
`ToggleButton` with a chevron, 4 epx under the table, closed for every new plan
(`sectionVerbPlanAlreadyRight`; its Toggle pattern tells Narrator its state).
REJECTED: `Expander` (a 48-epx header on a card background, with an animation:
a second panel where the mac's is a line of the table's — the plan review).

**Opening it never grows the dialog** (Russell's ruling on the mac): the
table's height is FIXED at `PlanTable.RowsWhenClosed` — the rows to read,
never fewer than five while pages are folded (or every row, when there are
fewer) — within what the window fits, and the opened rows scroll inside.
REJECTED: `MaxHeight`, which #548 used: a short list shrinks to its rows and
grows when the folded ones arrive, which is the mac's measured failure (316 →
484). The window wins over the five-row floor: on a window that holds two
rows, two. `PlanTableLayout.For(…, folds)` reserves the disclosure's line
(`FoldHeight`).

### 3. "Resizable": the window is the dialog's resize handle

A `ContentDialog` has no edge to drag. REJECTED: a drag grip in its corner (no
Windows dialog has one; the dialog is centred, so a corner grip moves at half
the pointer's speed; and it would reach into the template). So the teacher
makes the WINDOW bigger, and the page dialogs — the Section menu's three page
items, the Deploy question and Start of Year — grow with it, while at any
window up to the one they were designed for they are exactly the dialogs they
were: the mac's "opens at its old size, which is its minimum".

- **Width** (`PageTableLayout.DialogWidth`): the old width (680; 548 for the
  Deploy question, ContentDialog's own) at the window's 900-epx minimum, one
  epx of dialog per epx of window past it, **at most 300 more (980 and 848)**,
  never wider than the window less 24 a side. The XAML root is about 14 epx
  narrower than the window's outer edge, so growth starts about 14 epx past the
  900 outer minimum. **The 300-epx cap is a Windows-only choice** — the
  director's ruling of 2026-10-22, pending Russell; the mac's sheets have no
  maximum, but they open at 560 and grow only when dragged, where a maximised
  window here would make a 1,700-epx table. It is one constant,
  `PageTableLayout.MostAdded`.
- **Live**: the template reads `ContentDialogMinWidth`/`MaxWidth` once, so
  they are set wide open and a host `Grid` inside the dialog carries the width,
  every stage drawn in it (so the dialog is one width at every stage, as #548
  wanted), reset on `XamlRoot.Changed`. The plan's notes are re-measured at
  the live width on every fit.
- **Columns**: the plan's Page and What changes share what Folder (150) leaves
  in #548's proportion — exactly 170 / 150 / 262 at 680 — until What changes
  reaches 320 (the mac's cap); past that Page takes every epx. Start of Year
  the same: 170 / 140 / 272 at 680, Why capped at 300. The picker's Folder
  (140) and Date (170) are fixed; Page takes the rest.
- **Height**: every fit is #548's and #619's up to 756 epx, ContentDialog's
  old maximum; a window taller than that gives every further 32 epx to the
  table as one more row (`PlanTableLayout.ExtraRows`; Start of Year row by
  measured row), with `ContentDialogMaxHeight` raised so the dialog can use
  them. Nothing a window up to 756 tall shows has moved
  (`PlanTableTests.UpTo756TheFitIs548s_AndATallerWindowGivesTheTableRows`
  compares every height against #548's formula). On this PC (1920 × 1080 at
  150%) the root is never taller than about 690 epx, so this half is seen only
  at 100–125%.
- **"Grows to a taller stage, never shrinks"**: the first half is free — a
  ContentDialog re-measures at every stage, where the mac's `.fitted` sheet
  never re-fits and needed `SheetGrowsToItsMinimum`. The second half exists on
  the mac to keep a size the TEACHER dragged to, and nobody drags here.
  REJECTED: a `MinHeight` ratchet, which would add jumps nobody asked for.

**Testing it.** Unit: `PageTablesTests` (the fold, its words and its closed
height; the picker's rows; the widths and columns), `PlanTableTests` (the fit
with the disclosure, identical to #548 up to 756), `StartOfYearSheetTests`
(rows above 756), `ContractTests` (the five keys). Through the window
(`PageTablesUiTests`, opt-in): the tick rules, Space in Find a Page and the
table's height across a search, Return and Escape with a row selected, the
fold on a plan of 1 change + 4 already visible (five rows tall, unchanged when
opened), a wider window; `LaterClassesAtDeployUiTests.TheQuestionIsATable_AndSpaceTicksTheSelectedRow`.
The trail is unchanged, as on the mac: this is how the choice is shown, not
what Publish does.

**Measured through the window** (2026-10-22, this PC over a remote session at
200%: the screen 3024 × 1832 pixels, the main window about 937 × 625 epx, a
XAML root of 565–590 epx; `PageTablesUiTests`, which writes its numbers to
`%TEMP%\plantoir-634-measured.txt`):

- **The picker's chrome: 285 epx** against `PageTableLayout.PickerChrome` 300
  (the dialog box 415 epx tall over a 130-epx table of 4 rows, 4 × 32 + 2), so
  the estimate keeps a 15-epx margin and was left.
- **The disclosure: 27 epx tall, 4 epx under the table** — 31 against
  `PlanTableLayout.FoldHeight` 36, a 5-epx margin, left.
- **The width:** at a 900-epx window the plan's dialog is 680 wide; widened by
  400 epx (900 → 1300), the table went from 632 to 932 epx — exactly the
  300-epx cap — and the app's log read "dialog 980 wide".
- **The fold:** a plan of 1 change + 4 already visible draws one row in a
  table five rows tall; opened, five rows, with the table's and Publish's
  rectangles unchanged to the pixel. #548's 19-row fixture: 18 rows to read,
  1 folded, the table 8–9 rows tall at a root of 565–590.
- **Banding**, in light and dark (pictures kept out of the site; the test
  takes them only with `PLANTOIR_634_PICTURES=1`): the
  alternate rows read in both themes; in light the band is faint but visible.
- **Must-fails**, each a one-line change run against its test: Space's key in
  `TickTable`'s `PreviewKeyDown` renamed (Space → Scroll) — "Space on the
  selected row did not tick it"; the plan table's `Height` renamed to
  `MaxHeight` — the table measured 34 epx (one row) instead of five rows'
  worth; the picker's rows counted from the search's leftovers — 34 epx
  against 130.
- **Found on the way:** the sentences above the picker and the question were
  CENTRED in the wider dialog (a `TextBlock` with a `MaxWidth` narrower than
  its panel is centred), so `Words` is left-aligned now; at 680 it had been
  centred by 56 epx since #548. The sentences keep their 520-epx `MaxWidth`
  in every one of these dialogs — the Deploy question's too, which lost it in
  the first cut and had its lines run the dialog's whole width — so they read
  at a book's width even in a 980-epx dialog, and the two later-classes
  questions lay out alike (the implementation review).

**UI totals:** `PageTablesUiTests` 6 of 6; with `PlanTableUiTests` 10 of 10;
`LaterClassesAtDeployUiTests` (3, the new table test among them) and
`SectionVerbsUiTests` passed in the combined run. Two `PlanTableUiTests` were
corrected for the fold: they open the disclosure before reading the page
already visible (`OpenTheFold`, which also checks the table does not move).
UI Automation's Expand does not make the menus re-read what is live (a real
click or Alt does), so the tests open a fresh app per key; and
`RunSectionVerb` now queues one more `ApplyMenuEnablement` after its dialog
has finished closing, since `ShowAsync` returns while the dialog is still a
popup.

## One curriculum test, folder segments only (#615), and a linked curriculum page is not "already visible" (#617, the mac's #607)

**The predicate (#615).** The planner asks one question — is this page
curriculum? — through `PagePaths.IsCurriculum(courseDirectory, fullPath)`, and
`AssistWorkspace.IsCurriculum` now just calls it. The answer is the contract's
(`followingLinks.neverTakenDownByFollowingLinks`, `curriculumRules.isCurriculumPage`)
and the mac's (`AssistCurriculumMentions.isCurriculum(pageAt:in:)`): some
FOLDER between the course and the page has "curriculum" in its name,
case-insensitively. Until #615 `PagePaths.IsCurriculum` read the FILE name
too, so a page called "Curriculum Coverage" (or "Curriculum Notes") in an
ordinary folder was kept up as a curriculum page when the class linking to it
was hidden, where the mac took it down. **The Windows hide side therefore
changes:** a page merely NAMED "Curriculum …" is no longer kept with "it is a
curriculum page."; it goes down with the class like any other page nothing
visible still links to. Pages inside a curriculum folder are kept exactly as
before. The contract case is `followingLinks.unpublishing.cases` → "a page
only NAMED like curriculum is not kept up as a curriculum page" (added by
this piece, green on the mac as it stands).

Three edges the predicate now decides on purpose, pinned in
`CurriculumPredicateTests`:

- **Only folders inside the course count.** A working folder called
  "Curriculum Work" does not make every page curriculum; a page outside the
  course (a path that starts `..` from it, or on another drive) is false.
- **A relative path is false.** `PlannedPage.RelativePath` is relative to the
  WORKING folder, and `Path.GetRelativePath` reads a relative argument against
  the PROCESS's working directory. The hide side's `ReasonToKeep` had been
  passing it raw, which worked only by accident (the `..\..\` path it produced
  still contained the course's own folders) and would have made every page
  curriculum under a process directory with the word in it. It now resolves
  the page with `PagePaths.ResolveInside(_folder, …)` first, through
  `AssistWorkspace.IsCurriculumPage`, and so does the publish side below.
  REJECTED: resolving a relative candidate against the course — the callers
  hold paths relative to the working folder, so that would quietly read the
  wrong place; false makes a missed resolve visible in a test instead.
- **The contract's `isCurriculumPage.cases`** are run through it with a course
  root in front, so the planner and the assistant's list of expectations
  (`CurriculumRules.IsCurriculumPage`) answer alike.

Not changed here: `LinkGraph.IsCurriculum` and `CurriculumRules.IsCurriculumPage`
still test the folders of whatever path they are given (they take no course),
and #614 — a curriculum folder renamed to something without the word, read
from `course_config.json` — is deferred to v1.9.0.

**The publish plan (#617).** What the mac decided and why, including what was
rejected, is `10-local-ai-assistant.md` → "A curriculum page the walk reaches
is not "already visible" (#607)". On Windows it is one line in
`AssistWorkspace.PlanPublish`'s `linked` loop: when publishing, an
already-visible linked page that `IsCurriculumPage` says is curriculum is
skipped rather than added to `AlreadyRight`. `Describe()` (the card, the
reply and the MCP `plan_publish_pages` text: "N pages are already
visible."), `Tabulate()` (the Section menu's rows) and its
`MenuPlanSummary` all read that one list, so they agree by construction. A
HIDDEN linked curriculum page is still a change and goes up; a NAMED one is in
`named` and stays listed; `changes`, the walk, the declined pages and the date
moves are untouched; the hide side's `linked` list is not filtered.

**The harness.** `FollowingLinksContractTests.Lay` now reads the case field
`folder` (a course-level page, `publishForSection1:` / `createdSection1:`,
written to `<course>/<folder>/<title>.md`; a class page carrying one fails the
case) and checks `expectAlreadyRight` against the AlreadyVisible rows of
`Tabulate()` for the same layout, taken before the publish. Until then the
#607 case passed VACUOUSLY here: every non-class page went to
`section1/<title>.md` and nothing read the expected list.

**Measured** (2026-10-22): with the harness changed and the product not, the
#607 case failed "already visible should be [Glossary], was [A1.4,
Glossary]" and the new unpublishing case failed "“Curriculum Coverage” should
be hidden"; with the product fix, both green; with the publishing skip
removed again (copy-and-restore), the #607 case and two
`CurriculumPredicateTests` went red, and restored, green. No trail change: the
trail records what a publish or unpublish WROTE. A publish writes the same
pages as before (#607's reasoning), and an unpublish that now hides one page
more still says truthfully how many it hid.
## A folder added later, and titles YAML can read (#580, #586; the mac's #506, #575), v1.8.0 / v1.8.1

**What a teacher sees.** A folder added in Course Settings ▸ Content Structure
after the course was made now starts like a folder made with the course: an
`index.md`, so the site's sidebar shows it, and a `_DUPLICATE ME.md`, so there
is a page to copy — for a shared folder, and in every section for a
per-section one. The notice ("Plantoir made the folder … for you") is
unchanged. And a course whose name holds `: ` ("Physics: Mechanics") gets a
front page the build can read when a section is added or the front page is put
back. The shared behaviour, what was measured and what was rejected is in
`documentation/04-course-setup.md` → "5. Content structure"; this section is
what is particular to Windows.

**The writer is `Plantoir.Core/Models/FolderScaffold.cs`**, a port of the
mac's `FolderScaffold.swift`, and `SpecialFolderRenamer.CreateFoldersOnDisk`
calls it after making the folders: it now returns a `FolderScaffold.Outcome`
(folders made, index pages, templates) instead of a bool, and writes pages
only into the folders that call made. `CourseSettingsView.CreateFolderForNewEntry`
passes the bundled template, the file names at the top of the PRIMARY
curriculum folder (`CurriculumFolderRule.ForCourse(...).Resolved[0]`, read
from the disk AFTER the folders are made, in the mac's order — so a
"Curriculum" folder added to a course with none is read as empty and its own
template's connection is taken out; `CreateFoldersOnDisk` takes it as a
`Func` for that reason), and writes the trail line `FolderScaffold.FolderCreatedTrailLine`
— the mac's, word for word: ", with its index page and a page to duplicate",
", with its index page" or ", with a page to duplicate", or nothing.

Four things here differ from a straight port, each on purpose:

- **The template is read CRLF → LF** (`FolderScaffold.TemplateFrom`). This
  PC's checkout has `core.autocrlf=true`, so `support/skeletons/**/_DUPLICATE
  ME.md` is CRLF in the working tree, and `Plantoir.csproj` copies
  `support/**` from it into the bundle; the contract's bytes, and every page
  the mac writes, are LF. Without it an installed app would write CRLF
  templates beside LF index pages. Pages are written UTF-8 WITHOUT a
  byte-order mark, with `FileMode.CreateNew` — the mac's `.withoutOverwriting`
  — so a page that appeared in between is never written over.
- **The expectation shape is checked by hand, not by a .NET regex**
  (`IsSpecificExpectationStem`): `\d` there takes every Unicode digit and `$`
  matches before a trailing newline, both wider than setup's
  `^[A-Z]\d+\.\d+$` in Python. File names sort ORDINAL, as Python's
  `sorted(glob)` does, so `B1.10` comes before `B1.2`.
- **The new folders are compared by `Path.GetFullPath`, ignoring case**, as
  NTFS does.
- **The per-section index is not SectionAdder's fallback literal**, which
  ends without a newline; the contract's bytes carry one.

**The title rule is `FolderScaffold.FrontmatterTitle`** (the contract's
`foldersAddedLater.titleQuoting`), used by both index writers, SectionAdder
and SiteHealthRepair. It escapes only C0 control characters, as JSON and the
mac do; DEL makes a name quoted but is written raw — the known limit the
contract's note records, the same on both apps.

**#586: three writers.** `SectionAdder.ReplaceTitleAndCreated` quotes the
title it swaps in — the copied front page and the scaffold from a sibling's
frontmatter both go through it, so one line covers the mac's two swap sites —
and `ScaffoldFrontmatter`'s no-sibling fallback quotes too.
`SectionAdder.SectionTitle` stays PLAIN and first reads a quoted sibling back
(`SectionAdder.PlainTitle`, the mac's `plainTitle(fromValue:)`): double-quoted
is decoded strictly as a JSON string by System.Text.Json, so a value only YAML
could decode (`\x41`) or two strings in one (`"a", "b"`) gives the wizard's
form; single-quoted is stripped with `''` → `'`; a quote that never closes is
taken as written. One difference from the mac, kept: Windows reads only the
FIRST `title:` line of the sibling and stops (the `break`), where the mac's
loop reads on; they differ only for a front page with two title lines, which
no Plantoir writer produces. `SiteHealthRepair.RestoreIndex` quotes the course name it
puts back. Courses already made with a plain colon title are left alone, as on
the mac (a one-click repair is a v1.9.0 follow-on).

**Not on disk, on purpose.** The contract's seventh folder case is `Unit 1:
Kinematics`, and NTFS refuses `:` in a name, so every case runs IN MEMORY
through `FolderScaffold.Pages`; the disk tests use colon-free names that still
need quoting (`'Tis the Season`). A teacher on Windows can never meet the
colon case for a folder; a course NAME with a colon is the case that matters
here, and it is a title, not a path.

**Testing.** `FolderScaffoldContractTests` (all 7 `foldersAddedLater.cases`
as bytes, the 15 `titleQuoting.cases`, the 6 `frontPages` cases twice each
through the real `SectionAdder.AddSection`, every skeleton template against
`templateSource`, and the click's rules on disk) and
`SiteHealthRepairTests.AFrontPagePutBackQuotesACourseNameThatNeedsIt`.
`scripts/test_folder_titles.py` runs whole through `PythonToolchainTests`.
**Must-fail** (copy-and-restore, 2026-10-22): with dev's `SectionAdder.cs` and
`SiteHealthRepair.cs` and a `CreateFoldersOnDisk` that writes nothing inside,
13 of the 62 tests in the two classes failed (four of them only because the
stub `PlainTitle` passed values through); with `FrontmatterTitle` returning
the name unquoted, 7 failed — the folder cases, the title cases, the front
pages, both sibling-title tests, the on-disk quoted folder and the repair.

A trap met on the way, worth knowing: a doc comment reading `support/**`
turned `ActivityTrailWiringTests` red, naming four events in OTHER files as
never recorded. Its scan strips `/* … */` across the concatenated product
source before `//` lines, so a `/*` inside a `///` comment swallows every file
after it up to the next `*/`. The scan now strips each FILE on its own, in one
pass that recognises `//` comments and strings (raw ones included) before a
`/*` can open, and a `/*` that never closes fails the test naming its file —
so the next occurrence reports its real cause rather than four innocent events
(`ActivityTrailWiringTests.TheScanReadsAStarStarInACommentAsAComment`).

## The 1.8.5 measurement sitting (#593, #571 items 2–3, #618, #620, #598, #605)

Six issues asked Windows to measure or confirm site behaviour it inherits
from the shared `support/quartz/` and `scripts/`. Nothing was built for them:
no product code, contract or test changed. This section says what was run,
what came out, and what is still owed.

**Hardware and versions** (2026-10-22): Lenovo 20QES70500, Intel Core
i5-8365U @ 1.60 GHz, 16 GB, Intel UHD Graphics 620, Windows 11 Pro 26200.
Microsoft Edge 155.0.4283.60 (from Playwright's `browser.version` and from
`msedge.exe`'s file version); WebView2 Runtime 155.0.4283.62. The runtime is
Node 20.18.1 and Python 3.11.9 (manifest made 2026-10-22, Pyodide 314.0.7).
The checks' own Python is 3.14.7 with Playwright for Python. Chrome is not
installed, so every `<chrome>` argument below is `msedge.exe`.

### The site everything was measured on

The course is a scratch working folder:

- `website/shots/print_set_windows.mirror_toolchain` copied the launchers and
  `.toolchain\` from this tree.
- `courses\EXC2O` was copied from `support/example_course`.
- verify.sh's own plant blocks (lines 1957–3034 at dev 0df44a5f2) ran
  unchanged under Git Bash, with `python3` pointed at `python`. They planted
  How I Teach, the printable fixtures, Plain Long Page, the marker fixtures,
  the #499 pictures, `#609: Picture Fixture`, figures, runnable code, #505,
  #569, QUIZPLANTS, TASKPLANTS, the #596 authoring examples and Progress
  Fixture.
- One page was added for #620 item 4 (below).

The build was the launcher the app runs, not the window:
`preview.ps1 EXC2O 1 --build-only --non-interactive --full-rebuild`, with
`PLANTOIR_RUNTIME` set to `windows-app\Vendor\runtime`. It read 355 Markdown
files and wrote 454. The first full rebuild took 129 s and the second 63 s.
The site lands in `%LOCALAPPDATA%\Plantoir\builds\<folder id>\EXC2O\section1\public`.
Each browser check below was given a COPY of that `public\` and started its
own server, as on the mac; none used the native preview's address.

**Every planted page is CR LF on this side, twice over.**

- On Windows, Python's `write_text` writes `\n` as `\r\n`, so the planted
  sources are CR LF: Quiz Fixture has 335 CRs, Task Fixture 109, Picture
  Fixture 151.
- The build copies every page in text mode, so even an LF source becomes
  CR LF in the build's `content\`. The LF Quiz Fixture's copy has 335 CRs
  over 335 lines.

For every fixture except the comparison below, this does no harm. It is
the very case Windows owed, and the text hook and the answer reader
normalise CR LF before reading.

### #571 item 2: CR LF and LF read alike

**Method.**

1. After planting, `Quiz Fixture.md`, `Quiz Playground.md` and
   `Quiz Printable.md` were rewritten with `write_bytes`, once as pure LF
   (every `\r\n` made `\n`) and once as pure CR LF.
2. Both versions were counted before building, with `tr -cd '\r' | wc -c`
   and a byte count in PowerShell:

   | Page | LF build: CRs in the source | CR LF build: CRs / LFs in the source |
   |---|---|---|
   | Quiz Fixture | 0 | 335 / 335 |
   | Quiz Playground | 0 | 88 / 88 |
   | Quiz Printable | 0 | 23 / 23 |

3. Build A used the LF pages and build B the CR LF pages. Both were
   `--full-rebuild`, and nothing else in the course changed.
4. verify.sh's 6k check (`QUIZPY`, verbatim) ran against each build's
   `public\` and that build's own log. The log was passed as a Windows path,
   and two assertions were put in front of the check: the log exists, and it
   holds at least one `plantoir: error:` line. Without them, a missing log
   would pass "no `readDifferently`".
5. A second reader recorded each quiz's kind, problem, data,
   `data-quiz-hash` and title text on the four quiz pages.

**Results.**

- **6k passed on both builds.** Each log had 32 `plantoir: error:` lines.
  Eighteen of them were Quiz Fixture's, as the contract's cases expect,
  along with one `quizzesNotReady` finding for "18 self-check questions".
  The other 14 belong to other fixtures and are expected on Windows: 2 are
  Figures Fixture's deliberately broken drawings (functionplot block 3 and
  tikz block 6, `\foo`), and 12 are "Swift programs cannot be made ready"
  lines (Swift Playground 7, Runner Fixture 3, Quiz Playground 2), because
  Windows compiled no Swift then (#570, fixed in v1.8.6).
  Neither log contained the `readDifferently` sentence ("the site and the
  folder check read this question differently…").
- **The two builds read alike, to the byte.** All four pages gave identical
  records: Quiz Fixture's 37 quizzes, Quiz Playground's 9, Quiz Printable's 2
  and Quiz CRLF's 1. Kinds, problems, answers, correct choices and
  `data-quiz-hash` all matched, and so did the `plantoir: error:` lines,
  line for line.
- **A CR LF page renders its nested answer under its title.**
  `Quiz-CRLF.html` is CR LF at the source (11 CRs). Its title holds only
  "Simplify 2³ · 2⁴". The answer is a separate hidden `plantoir-quiz-answer`
  block (`Answer: 2^7`), and the explanation is its own folded `[!explain]`
  callout. `data-quiz` is `{"answers":["$2^7$"]}`. In both builds, no title
  on any of the four pages contained `[!answer]`, `[!explain]`, `> >`,
  "Answer" or "Why".

### #598: no page-view counter, and Mermaid draws under the Netlify policy

**No page-view counter.** `Select-String plausible.io` found nothing in
`public\postscript.js` (172,710 bytes), and nothing across all 454 files in
`public\`. The bare word `plausible` matched twice, both in a rubric's text
("instruments are plausible"): once in `Tasks/Space-Mission-Proposal.html`
and once in the search index. The build's `quartz.config.ts` says
`analytics: null,`.

**Mermaid draws.** This followed verify.sh's recipe:

1. Clone `public\`.
2. On the clone, run `deploy.py`'s own two writers in deploy order:
   `isolation_headers.publish_headers(site, "netlify")`, then
   `netlify_badge.write_netlify_headers_file`.
3. Run
   `node --experimental-websocket browser-checks/mermaid_draws.mjs <edge> <clone> /Printable-Fixture.html`.

It printed **`OK: 2 of 2 diagrams drawn, 0 requests blocked by the policy,
under the policy _headers carries`** (3.8 s).

The site does not carry its own Mermaid. The only Mermaid address in the
built files is Quartz v4.5.0's
`https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.4.0/mermaid.esm.min.mjs`,
and the policy's `script-src` now names `https://cdnjs.cloudflare.com`. That
is #594's design: allow the host rather than carry the engine. The policy
was the one a deploy to Netlify writes, but nothing was deployed; checking
live Netlify is `verify-deploy.ps1`'s job.

Every `.mjs` check in this section ran on the runtime's own Node 20.18.1
(`windows-app\Vendor\runtime\node\node.exe`) with
`--experimental-websocket`, because the checks expect Node 22's built-in
WebSocket. That is the same arrangement as doc 12's earlier browser
measurements.

On Git Bash, run the check with `MSYS_NO_PATHCONV=1`. Without it the
`/Printable-Fixture.html` argument becomes
`C:\Program Files\Git\Printable-Fixture.html`, and the check fails with
"no such page".

### #605: My Progress

`python scripts/test_my_progress.py` ran 27 tests, OK, in 1.4 s, and
`PythonToolchainTests` ran the same file green (see Tests below). There was
nothing to build.

A note for #599's readers: **Alt-click on Windows is the mac's
Option-click**. Each item's words come from the built label, and maths is
listed as 06 → L6 describes.

### #618 and #620: pictures sized in the HTML and laid out before they scroll

**The built text.** verify.sh's `SIZESPY` ran verbatim (exit 0), alongside
a parser over every `<img>`. In `Picture-Fixture.html`:

| Picture | Built `<img>` |
|---|---|
| `plantoir-hazard-wide.png` | `width="600" height="200"`, `data-pl-sized` |
| `plantoir-hazard-tall.png` | `width="400" height="1800"`, `data-pl-sized` |
| `plantoir-hazard-viewbox.svg` | `width="auto" height="auto"`, no marker |

`index.css` carries both `html body img[data-pl-sized]{height:auto}` (#612)
and `html body img{content-visibility:visible}` (#609). So the bundle's copy
of `support/quartz/` carries the transformer, the wiring found its
`PlantoirTasks` anchor, and Node on Windows resolved the course's POSIX file
names to the pictures.

**The reader, by hand (#620 item 4).** Four fixtures from
`scripts/fixtures/picture-sizes/` were copied into `Media\` and embedded
bare on a page of their own, `Picture Sizes Hand`:

| Picture | Built `<img>` |
|---|---|
| `jpeg-hand-II-o6.jpg` | `width="40" height="120"`, `data-pl-sized` |
| `png-exif-o6.png` | `width="40" height="120"`, `data-pl-sized` |
| `named-svg-cm.svg` | `width="302" height="151"`, `data-pl-sized` |
| `named-svg-viewbox-only.svg` | `width="auto" height="auto"`, no marker |

These are the answers the mac's oracle holds the same JavaScript to.

**The browser check.**
`node --experimental-websocket browser-checks/picture_heights.mjs <edge> <public copy>`
takes the site FOLDER and serves it itself. It ran three times, 6.8–7.0 s
each, and printed the same line every time:

> OK: with their bytes held, 600 x 200 and 400 x 1800 px from the page
> alone and unchanged when they arrived (page 11520 px both ways); 3
> pictures laid out before any scroll (200 px tall at 3075 px down, 2400 px
> tall at 4721 px down, 1800 px tall at 8567 px down, window 805 px), the
> page staying 11520 px tall scrolling to each (11520, 11520, 11520); 358 x
> 119 and 358 x 1611 px in a 390 px window

Each of the three phases matches #620's numbers:

- A: 600 × 200 and 400 × 1800.
- B: 3 pictures laid out.
- C: 358 × 119 and 358 × 1611.

This run covers #618 too. Its own expected "2 pictures" line predates
#612's third picture, the viewBox-only SVG, which is now the picture that
proves #609's rule.

`test_quartz_additions_wiring.py` passed 14 tests, OK, both directly and
through `PythonToolchainTests`. That includes
`test_the_print_buttons_component_carries_the_picture_rule` and the #612
wiring cases.

**Not done: the WebKit leg.** It is owed when #597 lands. Edge is Chromium,
where the shift never showed.

### #593: task boxes, and the one-blank line

**The mac's `browser-checks/task_boxes.mjs`, in headless Edge.** Run
unchanged, it got through every section before paper, then stopped at
`pdftotext -bbox`. The only `pdftotext` here is Git for Windows' xpdf 4.06,
which has no `-bbox`, and poppler's `pdftoppm` is not installed. No system
software was installed for this. Instead, a scratch copy was run whose only
change replaced section 9's ink read with "keep the four PDFs". Everything
else ran as written and printed (29 s):

> OK: 29 boxes on the fixture, ticks kept and restored, words, a link, Tab
> and Space, a transcluded copy in step, five round trips and one
> listener, the router's reused box showing its own page, a not-ready quiz
> left alone, storage refused, twins: Twin B reused Twin A's box yes; …;
> handout boxes x__ (the page showed x__); storage refused: handout xx_
> (the page showed xx_)

That covers item 1 — tick, untick, reload, navigation by the site's own
links with the router reusing a box, and transclusion setting its source's
tick — and Tab then Space.

**Ink on paper (item 2), read without poppler.** The four PDFs are
`Page.printToPDF` with `printBackground: false` on US letter: Task Printable
and Task Twin A, each in light and dark. They were read in headless Edge:

1. pdf.js 4.10.38 (legacy build, from jsdelivr) rendered each sheet to a
   canvas at 150 dpi.
2. The canvas was turned to grey with Rec. 601 luma, as `pdftoppm -gray`
   does.
3. Word boxes came from pdf.js's text layer (ascent 0.9 and descent 0.25 of
   the font size). Latin Modern's "fi" ligature has no text there, so
   "first" was matched as "rst".
4. Each box was judged by `task_boxes.mjs`'s own `boxInk` and
   `boxInkThrough`, lifted verbatim from the file, with its own thresholds:
   at least 20 inked pixels in the ticked box, at most 3 in the unticked
   one.

| Paper | Ticked box (inked px, w × h px) | Unticked box |
|---|---|---|
| printable, light | 47, 26 × 16 | 0, 26 × 17 |
| printable, dark | 47, 26 × 16 | 0, 26 × 17 |
| plain (Twin A), light | 62, 25 × 21 | 0, 25 × 20 |
| plain (Twin A), dark | 62, 25 × 21 | 0, 25 × 20 |

All four pass. This re-implements the mac's pixel read rather than running
the mac's tool. The only difference is where the word boxes come from
(pdf.js rather than poppler's `-bbox`); how a box is judged is the same.

**Site data BLOCKED (item 2).** The mac check's "storage refused" replaces
`localStorage` with a getter that throws. Here the browser itself refused
storage:

- A persistent headless Edge profile was started whose `Default\Preferences`
  holds `profile.content_settings.exceptions.cookies` =
  `{"http://127.0.0.1:8765,*": {"setting": 2}}`, Block for that origin. The
  setting was still in place after the run.
- On Task Printable, `localStorage.setItem` threw `SecurityError: Failed to
  read the 'localStorage' property from 'Window': Access is denied for this
  document.`
- Tab reached the first box and Space ticked it: `_x_` became `xx_`.
- Print ▸ Questions only laid out the handout with `xx_`, and the page still
  showed `xx_` afterwards.

**Item 4, the one-blank line.**

- On `Quiz One Blank`, typing "London" and pressing Enter says **"Not quite.
  Try again, or show the answer."** That is exactly what
  `quizCallouts.feedback.blanks` gives for `{count: 1, right: 0}`, which says
  `words.site.notRight`. The check read both from the contract and compared
  them as strings.
- "Paris" says "Right!".
- With two blanks and one right, it says "1 of 2 blanks is right. Try again,
  or show the answer." (case `{2, 1}`).

The same in light and dark, and in `quiz_check.mjs`.

**Item 3 (Narrator): OWED, not passed.** What a screen reader is HANDED was
read from the DOM (below, under #571). That is a proxy for what Narrator
says, not a measurement of it. Narrator itself still has to be listened to
on a desktop.

### #571 item 3: the four kinds in Edge, keyboard only, and paper

**The mac's `browser-checks/quiz_check.mjs`, unchanged** (42 s), printed:

```
FAIL: Swift run in a choice prints its output: {"status":"This program isn't ready to run yet.","output":""}; Swift run in the revealed explanation prints its output: {"status":"This program isn't ready to run yet.","output":""}
```

That is its whole problem list: the two Swift lines and nothing else.
Windows compiled no Swift then (#570, fixed in v1.8.6), and the build reported
`swiftCouldNotBePrepared` for 12 blocks on 3 pages. A copy whose only change
expects those two runs to be "not ready" printed:

```
OK: 9 quizzes, every kind wrong then right, the shuffle in 20 orders over 20 loads, the score kept and cleared, five page changes clean, a transcluded quiz on its own, Swift in a choice and an explanation ("", ""), paper and the handout questions only
```

(40 s.)

**Keyboard only, light and dark.** A Playwright script drove headless Edge
at 1280 × 900, with `color_scheme` and `saved-theme` set to each theme, on
Quiz Playground:

| Kind | Wrong | Right |
|---|---|---|
| Single choice (reached by 27 Tabs from the top) | Space on choice 1, Enter on Check: `notRight` | Shift+Tab back, ArrowDown: `right` |
| Select all | Space on 2 and on 4: `notRight` | Space to tick 5 and untick 4: `right` |
| Short answer | "2^8", Enter: `notRight` | "2^7", Enter: `right` |
| Fill in the blank | "100" / "on the moon": "1 of 2 blanks is right…" | "sea level": `right` |

Enter on a folded quiz's title turned its `aria-expanded` from "false" to
"true", and its content stopped being inert. The feedback text was
rgb(74, 87, 74) on rgb(247, 250, 245) in light, and rgb(207, 224, 201) on
rgb(18, 21, 18) in dark.

**What a screen reader is handed (the proxy).** On the page's second quiz,
the choices are a `FIELDSET` whose `aria-labelledby` resolves to the
question ("Which graph shows y=(x−3)2+2?"). The blanks are labelled
"Blank 1 of 2" and "Blank 2 of 2". Feedback is `role="status"`
`aria-live="polite"`. Real Narrator speech is OWED.

**Ctrl+P's paper and the handout.**

- `page.pdf` of `Quiz Printable` (print media, `print_background=False`,
  letter) is 1 sheet in both themes. Its text (`pdftotext -enc UTF-8 -raw`)
  has both questions and neither `printable-answer-7f3a` nor
  `printable-explain-7f3a`.
- The handout, questions only, was reached by
  `#plantoir-print=questionsOnly&paper=portrait` and read from its frame as
  it printed. In both themes it has the questions and neither sentinel.
- **No answer was revealed before printing**, in my script or in
  `quiz_check.mjs`. Its paper step (8a) runs on a page freshly loaded by the
  twenty shuffle loads before it, and asks that no button, feedback, answer
  or explanation is displayed under print media. So what paper shows after
  a student pressed Show answer, or got a question right and opened its
  explanation, is OWED in Edge as well as in the pane.

**Why 27 Tabs here and 10 in the pane.** The count depends on the window,
not on the quiz. At 1280 px wide, Quartz lays out both sidebars, and their
links (search, the explorer, the page's table of contents) come before the
article in Tab order. In the 984 px pane, Quartz's narrower layout has fewer
of them. The elements were not counted one by one.

### Tests

`dotnet test Plantoir.Tests/Plantoir.Tests.csproj --filter
FullyQualifiedName~PythonToolchainTests`: **Passed 77, Failed 0, Skipped 0,
Total 77** (2 m 49 s). The 77 count FILES, not Python test cases: 75 are the
discovered `scripts/test_*.py` (one `[Theory]` row each), and 2 are the
class's own `[Fact]`s. That run includes `test_my_progress.py`,
`test_quartz_additions_wiring.py`, `test_quizzes.py`,
`test_task_box_contrast.py` and `test_quartz_analytics_off.py`.

Run directly:

| File | Result |
|---|---|
| `test_quizzes.py` | 19 tests, OK |
| `test_task_box_contrast.py` | 4 tests, OK (the tick at least 6.06:1 light, 12.19:1 dark) |
| `test_quartz_analytics_off.py` | 6 tests, OK |
| `test_netlify_badge.py` | 19 tests, OK |

### #571 item 3 in the WebView2 preview pane

Measured 2026-10-22 on the same PC, on an unlocked desktop, in this branch's
own x64 Debug build. The app was started with `--state-dir` pointing at a
scratch state folder whose `settings.json` named the scratch working folder,
plus `--auto-preview EXC2O 1`, which is the Preview button's own code path.
The pane showed the app's own preview, Quartz's server at
`http://127.0.0.1:8081` started by the app from its bundled runtime, about
40 s after launch.

The pane was driven over WebView2's debugging port
(`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9333`,
Playwright `connect_over_cdp`). Its keys are therefore Chromium input events
sent to the page, not the OS keyboard. The user agent was
`… Chrome/155.0.0.0 … Edg/155.0.0.0` (WebView2 Runtime 155.0.4283.62), and
the pane was 984 × 603 CSS px.

Each theme was set with `prefers-color-scheme` and `saved-theme`, and the
pane was photographed in both. The same script steps as in Edge above
passed in light AND dark:

| Quiz | What was done | Feedback |
|---|---|---|
| Single choice | 10 Tabs from the top; Space on the wrong choice, then Shift+Tab back and ArrowDown | `notRight`, then `right` |
| Select all | Space on the boxes | `notRight`, then `right` |
| Short answer | typed, then Enter | `notRight`, then `right` |
| Fill in the blank | typed both blanks, then Enter | "1 of 2 blanks is right. Try again, or show the answer.", then `right` |
| One blank (`Quiz One Blank`) | a wrong answer | exactly `feedback.blanks` {1, 0} = `notRight` |

Other things seen:

- Enter on a folded quiz's title opened it, and its content stopped being
  inert.
- The blanks were labelled "Blank 1 of 2" and "Blank 2 of 2".
- The question labels the choices' `FIELDSET`.
- Feedback was `role="status"` `aria-live="polite"`.
- The feedback colours were Edge's to the value: rgb(74, 87, 74) on
  rgb(247, 250, 245) in light, rgb(207, 224, 201) on rgb(18, 21, 18) in
  dark.

**Paper and the handout in the pane.**

- **⌘P/Ctrl+P's layout.** `Page.printToPDF` is headless-only, so the paper
  was read as the pane lays the page out under print media
  (`Emulation.setEmulatedMedia` print, `body.innerText`). In both themes,
  `Quiz Printable` showed both questions and neither `printable-answer-7f3a`
  nor `printable-explain-7f3a`. Two limits on this:
  - The quizzes were unanswered when it printed; the paper of a quiz whose
    answer the student revealed was not looked at.
  - The 2026-10-15 measurement in "Printable pages" above (WebView2
    155.0.4283.45, a printable page with NO quizzes) shows only that a real
    Ctrl+P in the pane opens WebView2's own print window. It says nothing
    about quizzes.
- **The handout.** The app's print shim was present in the pane
  (`window.webkit.messageHandlers`), so the app's Print ▸ Questions only
  hands the handout to the teacher's browser. The browser half is the Edge
  measurement above. In the pane's own frame, with the shim taken away so
  `print.inline.ts` takes its own path, Print ▸ Questions only laid out a
  handout holding the questions and neither sentinel.

**A real OS Ctrl+P was not sent to the pane.** `WScript.Shell.AppActivate`
reported success but did not bring the app forward on this desktop, so the
one `SendKeys("^p")` went to the terminal in front instead. Nothing visible
happened, and no further keys were sent. A real keystroke in the pane needs
the window brought forward by hand, or by UI Automation as `DrivenApp`
does.

### Still owed after this sitting

- **Narrator** (#593 item 3, #571 item 3): Tab to a box reads its words,
  Space ticks it, and a link in an item still navigates; the question is
  read as the group's label, the blank as "Blank 1 of 2", and feedback is
  announced. Only the proxy above has been measured, in Edge and in the
  pane. Someone has to listen to Narrator itself.
- **A real Ctrl+P in the pane on a quiz page with an answer REVEALED**, and
  the same in Edge: what paper shows after Show answer, or after a right
  answer opens its explanation. Not measured anywhere in this sitting. The
  2026-10-15 measurement covers only that Ctrl+P opens the print window, on
  a page with no quizzes.
- **The WebKit leg** of #618 and #620, once #597 lands.
## Obsidian's add-ons for diagrams and graphs on Windows (#581, the mac's #495)

**What a teacher sees.** The first time Open in Obsidian is pressed on a course
with a ```` ```tikz ```` or ```` ```functionplot ```` fence, and BEFORE
Obsidian opens, Plantoir asks `obsidianAddOnsForFigures.wording.offerTitle`:
Add Them (the default), Not Now, and a "Don't ask again" box that turns Not Now
into no. One yes covers every course. After it, a course gets the add-ons it
uses at Open in Obsidian and, silently, when a section's preview has shown a
fresh build. File ▸ Settings ▸ Obsidian (a section after Preview, as the mac's
pane is) holds the one toggle. Everything else — the cases, the words, the
order — is the contract's, and `documentation/09-mac-app.md` → "Obsidian's
add-ons for diagrams and graphs (#495)" carries the reasoning and what was
rejected; this section says only what Windows does differently and what it
measured.

**The files.** `windows-app/Vendor/fetch-obsidian-addons.ps1` reads every id,
version, size, SHA-256 and address from `obsidianAddOnsForFigures.addOns` (it
carries no pin of its own — `ObsidianFigureAddOnsTests` fails on any 64-hex run
in it), caches by SHA-256 in `%LOCALAPPDATA%\Plantoir-dev\obsidian-addons`
(or `$env:PLANTOIR_ADDONS_CACHE`), installs nothing on one mismatch, and swaps
`Vendor\obsidian-addons\<id>\<file>` in (4.3 s the first time here, 3.6 s when
already in place). The contract is 2.09 MB, past Windows PowerShell 5.1's
`ConvertFrom-Json` limit, so on 5.1 it reads with the serializer that limit
comes from, raised. **Run it once per clone or worktree.** `Plantoir.csproj`
ships the folder as Content (`obsidian-addons\` beside Plantoir.exe, and in
`publish`), and `CheckObsidianAddOns` REFUSES the build when the folder is
missing, holds other than the pinned 7 files, or holds a file whose (id, name,
SHA-256) is not a triple in the contract — not merely "a hash that appears
somewhere": functionplot's licence under tikzjax's name is refused. Each
refusal was seen (missing, 8 files, a flipped byte, the swapped licence).

**The model is in Plantoir.Core, behind `IObsidianWorld`.** The mac's route
lives in its `WorkspaceModel`; Windows' Open in Obsidian lives in the WinUI
project, which the test project does not reference, so the sequence
(`ObsidianOpenRoute`), the decisions (`ObsidianFigureAddOnsOffer`), the pass
(`ObsidianFigureAddOns`), the words and the trail are Core, and
`Plantoir/Views/ObsidianWorld.cs` supplies only FolderActions and the two
ContentDialogs (through `ShowDialogSafelyAsync`, so DialogGate holds the
menus). `ObsidianOpenRouteTests` drives sequence steps 1–8 through a fake world
with no window. The How I Teach row's "open the page" still calls
FolderActions directly, as the mac's does (it opens a page, not Open in
Obsidian).

**Windows' own decisions, each a review finding.**

- **The fence reader is a port of `fenced_blocks`**, not `MarkdownCode`
  (`FigureFenceScan.cs`): lines split on `\n` only, a lone `\r` is text, a
  byte-order mark is a character (decoded with `Encoding.UTF8.GetString`, as
  Python's utf-8 reader keeps it). It agrees with the Python on 2,000 generated
  pages (fixed seed; CR LF, lone CR, BOM, invalid UTF-8, nested containers) and
  on every `figureFences.fences` case. A lone `\r` inside a line is text here
  exactly as it is in the mac's `FigureFenceScan.swift` and the Python (all
  three split on `\n` only) — reviewed, mac-identical, no change.
- **A link is a reparse point with a `LinkTarget`** (junction or symbolic
  link). A OneDrive placeholder folder is a reparse point too; it is a folder
  here, never refused and never skipped. The scan never follows a link (no
  loop, nothing outside the course read). A page is skipped unread when its
  attributes say `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` (0x400000),
  `RECALL_ON_OPEN` (0x40000) or `Offline` — the mac's `SF_DATALESS`. Measured
  on this PC's OneDrive (running, Files On-Demand): the one evicted file reads
  evicted from its attributes without being downloaded; `Documents` and
  `Pictures` (cloud folders) read as folders. No evicted `.md` was available
  and none was made (it would upload to the teacher's account).
- **The list is written by hand** as `JSON.stringify(ids, undefined, 2)` writes
  it: a general serializer escapes non-ASCII and `+<>&'`, and a second pass
  would then change bytes Obsidian wrote (tested with a non-ASCII id).
- **Renames, replaces and deletes retry for about 0.75 s** (Defender, the
  indexer or OneDrive can hold a 7.8 MB file just written); still refused, the
  add-on is `couldNotWrite` with the system's reason.
- **`couldNotWrite` needs a deny-write ACL here**: the read-only attribute does
  not stop writes into a folder on Windows (a test proves it does not). The
  test denies Write/Delete to the current user's SID with `DirectorySecurity`,
  removes it in a `finally`, and sweeps a stale denied folder at start.
- **One `SemaphoreSlim` for every pass**, every course (the mac's actor); 8
  passes at once are seen one at a time.
- **The registry** (`%APPDATA%\obsidian\obsidian.json`) is read with
  `FileShare.ReadWrite`, and paths are compared with either separator and any
  case. `RegisterVault` no longer replaces a registry that EXISTS but could not
  be read with one holding only the new vault (that would have lost every other
  vault).
- **The archiver** (`CourseArchiver.ZipFolder`, every backup and archive)
  leaves out each folder directly under the zipped folder's
  `.obsidian\plugins` that carries the `.plantoir` marker, partial copies
  included; the teacher's own add-ons and the list stay (`backups.cases`, a
  real zip read back).

**"Running" and "quit", changed for every caller.** `FolderActions.ObsidianIsRunning`
is now: an `Obsidian.exe` in THIS Windows session owns a top-level window,
shown or not (`ObsidianProcesses`). Before, any process named Obsidian counted
— another account's, or a crash reporter outliving the windows. And
`QuitObsidianAndWait` now closes EVERY shown Obsidian window (main windows
before owned ones), then `CloseMainWindow` on any process still there after
1.5 s, then waits up to 5 s for the windows — and then up to 3 s more for the
PROCESSES (measured: windows gone at 0.4 s, processes at 0.66 s; a registry
or add-on list written in that gap can be overwritten as Obsidian exits). Any
window left after the wait means "did not close" for all of them: nothing is
written, and a half-closed set is not reopened. Before #581 it called
`CloseMainWindow` on each process, which closed ONE window: an Obsidian with
two vaults open kept running. That was a live fault in the two older callers
too — vault REGISTRATION (Open in Obsidian on a course Obsidian has never
seen) and the course RENAME — which then wrote the registry under a running
Obsidian. **The quit change fixes them only when the quit succeeds**, so
registration now also checks: if Obsidian is still running after the quit, it
writes nothing and opens the link as it is (the course stays unregistered;
nothing false is said). And because Obsidian started by a link does NOT bring
back the other vaults (measured: closing windows one by one unmarks all but
the last), registration now notes the vaults open BEFORE quitting and reopens
them after registering, this course last — the add-ons route's own reopen.
The rename path's reason for not reopening Obsidian afterwards (the vault to
reopen is in the folder just left) is unchanged and still holds; and the
rename now checks too: if Obsidian is still running after the quit, the
folder is not moved and nothing is registered, and the teacher is told "{code}
was not renamed, because Obsidian is still open. Close Obsidian, then rename
the course again." (an inline sentence, like the rename's other words, which
are in no contract). When the windows close but the processes outlive the
3 s wait, the quit says so in `startup.log` (never the trail) and goes on. The vaults to reopen are noted BEFORE anything closes: measured,
closing one vault window of several clears that vault's `"open"` mark in the
registry (the last window to close keeps its mark). Reopening opens the first
vault, waits up to 10 s for a window, then the rest 0.4 s apart, this course
last — rather than racing Electron's single-instance lock.

**Measured live** (2026-10-22, i5-8365U, Windows 11 Pro 26200, 1920 × 1080,
Obsidian **1.14.4** — not the mac's 1.13.7; a temp working folder through
`--state-dir`, Obsidian's registry backed up first and restored byte for byte
after, the temp vaults' window files removed):

- The offer appeared 182 ms after Open in Obsidian, Obsidian not yet started;
  Add Them added TikZJax (marker, list `["obsidian-tikzjax"]` in Obsidian's own
  format) and Obsidian opened 2.3 s later through the registration path.
- **Obsidian's trust question puts focus on "Browse vault in Restricted Mode",
  and Enter chooses it** (the focus ring was on it; Enter closed the question
  and the tikz fence then showed as code). `windowsWording.offerMessage`'s
  "pressing Enter chooses the other button" and `settingFooter`'s Enter
  sentence are TRUE on Windows.
- **After "Trust author and enable plugins", Obsidian 1.14.4 opened its
  Settings ▸ Community plugins in a window of its own** — on a first-time
  trust (a fresh course) and on a trust after Restricted Mode. The contract's
  `wording.note` says Obsidian "does not open its settings (measured on
  1.13.7, #582)", and the offer's sentence telling the teacher to close the
  settings was removed for that reason. Either 1.14 changed it or Windows
  differs; this is a decision for the mac and Russell, not a Windows-only
  wording change, so nothing was changed here.
- The reopen, with two vaults open, one minimised, a pop-out of the other, and
  text typed 1.2 s before Reopen was pressed: every window gone in about 0.4 s,
  every Obsidian process gone at 0.66 s, the add-on written, MCR3U back at
  1.9 s and MPM2D (this course) last at 2.8 s, both registry marks `"open":
  true` again, and the typed text saved. Obsidian did not bring the pop-out
  back (its own restore). On Windows a pop-out is NOT an owned window (no
  `GW_OWNER`), so "main windows before pop-outs" orders nothing there; it costs
  nothing, since all of them close within the same 0.4 s. `didNotClose` never
  fired.
- The registration path's quit (a two-vault Obsidian, Open in Obsidian on a
  never-registered course) closed it in about 0.35 s and opened the new course
  at 2.4 s.
- Both figures drew once trusted (reading view; the course defaults open pages
  in source view, where a fence shows as code).
- Settings ▸ Obsidian: shown as stored (on), off stored `no` and on stored `yes`,
  one trail line each; the footer reads the Windows Enter sentence.
- The scan, headless (`ObsidianFigureAddOns.KindsUsed`): the MPM2D example
  payload, 232 pages, both kinds — 1,872 ms the very first time those files
  were read on this PC, 38 ms in a fresh process after, 19–27 ms warm; TGJ2O
  107 pages 902 ms cold, 16–27 ms after. So a first Open in Obsidian on a course
  never read can wait about 2 s before Obsidian opens (the mac measured 39–63 ms
  cold). The pass: re-hashing the 7 files 42 ms, a full first pass 74 ms, a
  second pass (all `alreadyThere`, no byte or date changed) 87 ms.

**Not measured:** the preview trigger on a real preview (unit-tested through
the route), Obsidian's "Exit Restricted mode" label on 1.14.4 (the footer
quotes the 1.13.7 label), and a OneDrive-evicted `.md`.

**Shared text left for the joint follow-up** (the issue's item 9): the
`plantoir-math-graphs` skill §9 and `figureFences.knownLimits[2]` still say
nothing about Plantoir adding the add-ons; with both platforms adding them now,
they can say so — together with the mac, not from here.
