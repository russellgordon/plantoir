# macOS App — Handoff

> **New here? Read [`MAC-BOOTSTRAP.md`](MAC-BOOTSTRAP.md) first.** It says how
> to take work that arrived from Windows, and how to add a feature on this side
> so it reaches them as data rather than as a surprise. This file is the ledger
> it sends you to.

The ledger of work that originated on the **Windows side** and needs — or
deserves a look from — the **macOS app**. The reverse of
[`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md): read this when syncing the mac
after Windows-side sessions.

**Read it top-down and stop when you like.** Everything still owed is in the
first two sections; everything already dealt with is kept below them, in full,
because the reasoning is the point of the file and deleting a finished entry
throws away why the mac does what it does.

| Section | What is in it |
|---|---|
| [Contract cases waiting on the mac](#contract-cases-waiting-on-the-mac) | Cases proposed from Windows that the mac suite is failing on. Read FIRST when a suite goes red. |
| [Open — what the mac still owes](#open--what-the-mac-still-owes) | Work not yet done here. |
| [For awareness — no mac code needed](#for-awareness--no-mac-code-needed) | Things to KNOW, not to do: shared decisions, frozen names, coordination points. |
| [Done — the ledger](#done--the-ledger) | Finished, marked in place with what landed and where. History, and the reasoning behind decisions the code no longer explains. |

Cross-side rebases rewrite commit hashes, so treat hashes as hints from the
moment of writing — file and test names are the durable pointers.

## How to write an entry

The good entries below already do this; it is written down so the next one
does not have to infer it from twenty examples. An entry carries:

1. **A bold title that says what CHANGED**, then `(source, date, commit)` —
   "Windows", "shared", or "Windows + shared" for work in `scripts/`.
2. **What it fixed, and WHY it was done that way.** The why is the half that
   travels: the mac can read a diff, it cannot read a decision. Include what
   was **rejected**, or it gets proposed again and costs the same afternoon
   twice.
3. **Numbers, with the hardware they came from**, for anything measured. This
   side has no way to find out what a Windows teacher's machine does. "The
   Vulkan build was faster" cannot be acted on; "43 tok/s against 11 on CPU,
   Intel Iris Xe" can.
4. **Where the reference implementation lives** — file and test names, which
   outlast commit hashes across rebases.
5. **Whether the mac is expected to match it, or merely to know.** Those are
   different asks, and the second section of this file exists for the latter.

If a teacher can see the change, it also wants a row in
[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — that log is the record of the
product, not of one platform.

## Contract cases waiting on the mac

> **v1.1.0 cut sheet (Windows assets ready, 2026-08-20).** The verified
> Windows artifacts live on the Windows machine and will be uploaded FROM
> there (`gh` is authed there) once the tag exists — so cut the release as a
> DRAFT, tell Russell, and publish after the assets attach. Hashes for the
> notes' SHA-256 table:
> `PlantoirSetup.exe` 224.5 MB
> `9990bcacade548a35cbd5b11f65dbf79d4a0236eeeee4d4d0e5322204c96527e` ·
> `Plantoir-win-x64.zip` 379.9 MB
> `b141c7ac30116c9836334e90472e5a2527fb4e50629c56d4c2f258f437cbb1ba`.
> Built from commit 8e9faab0, proven by five clean-machine smoke tests
> (install → course → preview → assistant → deploy, no .NET/WSL/Docker on
> the machine). The macOS DMG does NOT ship in this cut — see RELEASING.md
> "Two platforms, one version series": the mac joins v1.1.0 after the gate
> list below is green.


**Nothing is outstanding.** Both cases proposed for v1.1.0 were cleared on
2026-08-20 — one implemented, three retired — and the reasoning for each is in
the ledger below under "The teacher-made-link case is implemented, and the
three setup cases are retired".

The mechanism, in one paragraph. `Plantoir --write-contracts` runs on the mac,
so the Windows side cannot regenerate the derived halves of
[`contracts/`](contracts/README.md) — but the **authored** halves (`scenarios`,
`nearMisses`, `promptHistory`, and the case lists in the other files) survive
regeneration untouched. So a behaviour invented on Windows can be proposed as
a case, and **the mac suite then fails until the mac implements it.** That is
the mechanism working, not a break: verified on purpose by adding a case for
an event the mac has no support for, which failed naming the case and the
missing step rather than passing quietly.

When a case is proposed, add a line here naming it, so whoever meets the red
suite reads it as a request:

> - `contracts/assist-cases.json` → `scenarios` → **"<case name>"**, proposed
>   <date>. What it asks for, and why. Reference: `<Windows file>`.

Remove the line when the mac implements it, and mark the matching entry below
`✅ DONE` — the ledger keeps the history, this section keeps only what is
outstanding.

## Open — what the mac still owes

New items go at the TOP of this section, and move to the ledger when done
rather than being deleted.

- ✅ DONE (mac, 2026-08-20). **The assistant warm-up race: it EXISTS here,
  it is measurable, and it cannot produce the Windows symptom.** Answering
  GUI-IMPROVEMENTS row 293's two questions with the real app rather than
  from the code, as that row asked.

  **Q1: does the mac's first turn await its warm-up? No — same as Windows
  before their fix.** `AssistSession.startEngine()` sets `readiness = .ready`
  and only THEN `await warmUp(…)`, and `canSend` asks nothing but
  `readiness == .ready`. The trail shows it plainly: `the assistant was ready
  after 0.5s`, with the ~3,400-token priming request still to run.

  **Measured, small assistant, M-series, 48 GB — the same question twice:**
  - typed after the warm-up had finished: **1.7 s**
  - sent the instant the field enabled, racing it: **3.1 s**

  So the race is real and costs about **1.4 s** on the first question, which
  is the priming request's tail on the server's single slot
  (`--parallel 1`). The question was answered correctly both times; nothing
  was lost.

  **Q2: is a timeout distinguishable from window-close cancellation? Yes —
  the mac has no way to confuse them, because it never classifies errors at
  all.** `AssistAgent.think()`'s catch has one branch: every error becomes a
  visible `.problem` bubble AND an `assistantCouldNotAnswer` trail line.
  There is no "this was a close, say nothing" path for a timeout to fall
  into. Proven by killing `llama-server` mid-session: the teacher saw
  `⚠ Could not connect to the server.` in the conversation and the trail
  recorded `the local AI assistant could not answer — Could not connect to
  the server.`

  **Three independent reasons the Windows chain cannot complete here**, which
  is why this is not a mac bug wearing a Windows coat:
  1. The request timeout is **180 s** (`AssistModelClient.reply`), not a few
     seconds — a warm-up of 2 s (small) or ~12 s (large) cannot exhaust it.
  2. The catch cannot swallow a timeout as a close, per Q2.
  3. **The engine's output goes to `FileHandle.nullDevice`**
     (`AssistServerHost`), so the unread-pipe wedge Windows had to fix by
     draining pipes cannot occur — nothing is ever buffered.

  **What was NOT fixed, and why.** Making the first turn await the warm-up is
  a real improvement worth about 1.4 s, and it is an OPTIMISATION here rather
  than a fix: the teacher-visible defect Windows repaired (silence) does not
  exist on this side. Doing it inside a release qualification would have made
  the mac's v1.1.0 a behaviour change and pushed the cut to 1.1.1 for a
  second and a half. Decided with Russell on 2026-08-20; it belongs in the
  next version with a test that pins "cannot send until the warm-up has
  returned".

  **One diagnostics gap this turned up, for the next session rather than
  this one.** Reason 3 is also a cost: with the engine's output going to
  `/dev/null`, nothing llama-server says can ever reach a problem report —
  no load errors, no slot warnings, no token counts. Windows added
  `NoteServerLine` for exactly this. The mac should sample those lines into
  the trail (a bounded tail, not the firehose) rather than keep discarding
  them; it is a report-quality change, not a hang risk, which is why it is
  not in 1.1.0.

- ✅ DONE (mac, 2026-08-20). **`./verify.sh` passes against the changed
  shared scripts — all nine checks, and the npx question is settled.** Run
  from a clean clone of `dev` with the v1.1.0 tree: image built from the
  working recipe with BuildKit, baked scripts/patches/support files verified
  identical to the tree, the Explorer hide filter present in both Quartz
  copies, then a real `preview.sh EXC2O 1 --full-rebuild --build-only`
  through the launcher — 260 Markdown files parsed in 966 ms, 304 files
  emitted, "Done processing 260 files in 1s". No behaviour on this side
  needed changing, which is what let the mac ship 1.1.0 rather than 1.1.1.

  **The npx question is answered: there is nothing left to check.** The
  entry asked whether the container had quietly been resolving the Quartz
  CLI from the npm registry too. It cannot any more, on either platform,
  because the fix is in the SHARED script — `build_site.py` runs
  `node <abs>/quartz/bootstrap-cli.mjs` at both call sites (build and
  serve), and `deploy.py` mentions npx nowhere at all. The whole verify run
  contains not one npx line. So the question is now unanswerable rather
  than answered — the old behaviour is gone from the code that would have
  produced it — and it does not matter: the pin held either way, because
  Quartz's CLI runs the local patched `quartz/` source from CWD.

  **One nit, deliberately not fixed**: `toolchain_paths.py` still defines
  `NPX` and nothing uses it. Removing it would change the build context and
  therefore the image tag, which costs every teacher on both platforms a
  rebuild — for a dead constant. Fold it into the next change that touches
  that file for a real reason.

  **Two notes for whoever runs `verify.sh` next.** Its fixture,
  `courses/EXC2O`, is gitignored, so a fresh clone has none; the script's
  header says to install it with `./setup.sh`, but that is an interactive
  wizard and `cp -R support/example_course/EXC2O courses/EXC2O` produces the
  same fixture in a second. And the script deliberately LEAVES a container
  running from `quartz-teacher:dev-test`; `docker rm -f teaching-quartz-<hash>`
  puts the folder back on the normal image, which this session did.

  Everything below is the original request, kept for the reasoning.

  **Windows dropped the container entirely — shared scripts changed, run
  `./verify.sh` on the next sync** (Windows + shared, 2026-08-19, branch
  `windows-native-toolchain`). Windows now runs the whole toolchain
  natively: Node 20, Python 3.11, the patched Quartz scaffold and wrangler
  ship inside the app's own folder (built by
  `windows-app/Vendor/fetch-runtime.ps1`, pins mirroring the Dockerfile's),
  and the launchers run the shared Python directly when that runtime is
  present. WHY: WSL2 needs admin rights, Windows feature changes and a
  reboot — school-managed laptops refuse all three, and a teacher hit
  exactly that in front of an audience twice in one day. Rejected: porting
  the Python to C# (kills the shared-scripts contract and invites permanent
  drift); keeping a WSL2 fallback (Russell chose deletion once verified —
  two paths means two test surfaces forever).

  **What the mac must know about the shared files:**
  - `scripts/toolchain_paths.py` is new: every fixed path (`/opt/*`,
    `/teaching/courses`) now routes through it. Container defaults are
    byte-identical to before; the native path overrides via `PLANTOIR_*`
    env vars the mac never sets. The Dockerfile COPYies it — image hash
    changes, so the first mac preview after sync does a one-time rebuild.
  - The 26 `tee` subprocess writes are plain writes now (`write_file`),
    the Media/node_modules/.netlify links go through `link_directory`
    (symlink first — the mac's behaviour is unchanged), and
    `_sync_public_to_host` falls back to an incremental pure-Python mirror
    only when rsync is absent (it never is, in the container).
  - **The Quartz CLI is invoked as `node <abs>/quartz/bootstrap-cli.mjs`
    instead of `npx quartz`** — measured on Windows, `npx` resolved the CLI
    from the npm REGISTRY into its cache (a project's own bin never lands
    in its node_modules/.bin), which needed network and floated off the
    v4.5.0 pin. The container was almost certainly doing the same thing
    quietly; check a container build log for an `npx` cache line if you
    want the confirmation. Correctness held only because Quartz's CLI runs
    the local patched `quartz/` source from CWD.
  - `setup_course.py`'s keyboard reader imports termios where it exists,
    msvcrt where it does not; POSIX behaviour identical.

  Numbers (this machine, Ryzen-class x64, NVMe): first native build of the
  199-page example course **57 s cold** including scaffold staging; Quartz
  parse+emit 5 s; delta deploy to Netlify 117 files, ~40 s. The container
  path's equivalent on this same machine paid a one-time ~8 min image
  build plus WSL2 provisioning before the first build could start.
  Reference: `Enter-NativeRuntime` in the three `.ps1` launchers,
  `scripts/toolchain_paths.py`, `windows-app/Vendor/fetch-runtime.ps1`.

- ✅ DONE (mac, 2026-08-20). **Verified against the real app: the mac writes
  a record for every task, and the one gap in the code is unreachable here.**

  **What was driven.** A scratch working folder, the Example Course in it, a
  real preview that served the site, then `course_config.json` deliberately
  corrupted and Preview pressed again: `preview.sh — failed (exit 1) after
  1.0s`. `~/Library/Logs/Plantoir/runs/2026-08-20-184555-preview.txt` appeared
  with the task, the arguments, the outcome, the whole transcript ending in
  the JSONDecodeError, paths redacted to `/Users/person/…`, and the line
  `Explained nothing recognised — worth a look` — the honest fallback the
  contract's note asks for, doing its job on an unrecognised traceback.

  **It is the same folder the report reads**, checked rather than assumed:
  `ScriptRunner.writeRecordOfRun` → `ProblemReportStore.write` →
  `runsFolderURL`, and `ProblemReportBuilder.assembleFolder` reads
  `store.runFileURLs()` from that same store — the count is what fills in
  "the last N tasks Plantoir ran for you". Windows's failure was these two
  being different folders; here they are one property on one type.

  **A record also exists from the FIRST moment**, which is more than was
  asked for: the still-running preview had a 14 KB record while it was
  serving, outcome "Still running after …". That matters for the commonest
  report of all — "the preview is stuck" — which by definition never reaches
  a finish path.

  **The one gap, and why it is NOT worth fixing.** `ScriptRunner` assigns
  `runScriptName` AFTER `try newProcess.run()`, so a task that failed at
  LAUNCH would write no record and no `taskStarted` line — exactly the
  Windows shape, and exactly what the request asked about. It cannot happen
  here: `executableURL` is always `/bin/bash` and the script is an argument,
  so `run()` can only throw if `/bin/bash` is missing, at which point the
  Mac has bigger problems. Confirmed by experiment — `chmod -x preview.sh`
  and pressing Preview still produced `started preview.sh EXC2O 1 --port
  8081` on the trail and a record, because the executable bit of the script
  is not consulted. **Windows is exposed where the mac is not** because it
  launches the `.ps1` through its own host rather than through a shell that
  always exists. Left as it is deliberately: reordering two lines to guard
  against an unreachable case would be an untested behaviour change in a
  release-qualification pass. Written down so nobody "fixes" the ordering
  believing it is live, and so the asymmetry with Windows is on the record.

  Everything below is the original request, kept for the reasoning.

  **Check that every finished mac task really writes a run transcript**
  (Windows, 2026-08-19, branch `windows-wsl2-auto-install`). A real teacher's
  problem report arrived saying "the last 0 tasks Plantoir ran for you" after
  three failed setups: the Windows report reads `Logs\runs\*.txt`, and
  nothing ever wrote that folder — the reading side was tested against
  hand-made files, so the gap passed every test. Windows now saves every
  finished task's transcript from `ScriptRunner`'s finish path (redacted on
  the way in, pruned to the newest 20, header matching the trail's
  "finished … — outcome" sentence). The ask here is a VERIFICATION, not a
  port: drive one real failing task on the mac and confirm a file appears in
  the folder its report actually reads — the failure mode is precisely that
  the tests cannot see this. Reference:
  `ProblemReportStore.SaveRunTranscript`, `ScriptRunner.NoteTaskFinished`,
  `ProblemReportTests.Store_SavesRunTranscripts_RedactedAndPruned`.

- ✅ DONE (mac, 2026-08-20) — **RETIRED rather than implemented.** The three
  explainer sentences were never added here, and must not be: the same
  session that proposed them deleted the Windows container path, so no
  shipping launcher can print the lines they match. The three cases are gone
  from `contracts/app-rules.json` → `failureExplanations.cases`; Windows's
  own `SetupExplanation` is now unpinned by the contract and should be
  deleted along with the launcher code it reads, not kept as the only
  implementation of a rule nothing tests. See the ledger entry "The
  teacher-made-link case is implemented, and the three setup cases are
  retired". Everything below is the original request, kept for the reasoning.

  **The Windows launchers now install WSL2 themselves — the mac owes only
  the three explainer sentences** (Windows, 2026-08-19, branch
  `windows-wsl2-auto-install`). What it fixed: a teacher on a PC with no
  WSL2 hit "ERROR: WSL is present but no Linux distribution is installed"
  plus an instruction to open an Administrator PowerShell — it failed live
  in front of an audience on 2026-08-19. This was the Windows analogue of
  the mac's zero-prerequisite Colima bootstrap, called for by
  `WINDOWS-HANDOFF.md`'s "Container engine" note (entry 72), and it now
  exists: each `.ps1` launcher's `Install-WindowsSubsystem` runs one
  elevated `wsl --install -d Ubuntu --no-launch` (retrying with
  `--web-download` for Store-blocked school machines), detects
  restart-pending by USABILITY rather than exit code (the exit code is 0 on
  that path), and reports the three non-fault stops in plain words. WHY the
  choices: `--no-launch` because Ubuntu's first-run username wizard would
  otherwise block a non-interactive run forever — the distro runs as root,
  fine for an appliance no teacher opens; UAC is announced first ("Watch
  for a Windows permission prompt") because it is the one step that cannot
  be silent; a distro installed BY the run is provisioned without the
  Docker-engine question (the mac never asks either), while a pre-existing
  distro keeps the question because it belongs to whoever set it up.
  Rejected: DISM feature-enable plus manual distro import (re-implements
  what `wsl --install` already does, and needs the same elevation);
  prompting before the install (the handoff asks for silent, and UAC is
  already the consent); auto-restarting the PC (never — the teacher may
  have unsaved work everywhere). Untested on a truly fresh machine — this
  dev box has WSL — so the restart path is asserted from the launcher's
  printed lines, which is what the contract cases pin. What the mac does:
  the three contract cases above, nothing else — the `.sh` launchers are
  untouched. Reference: `Install-WindowsSubsystem` in `setup.ps1`,
  `preview.ps1` (where stop mode exits before it can ever run), and
  `deploy.ps1`.

- **Build the 1.0.0 DMG only from a tree containing the deploy-flush fix in
  `scripts/build_site.py`** (Windows + shared, 2026-08-19). A Windows release
  smoke hung FOREVER after "Done processing 272 files" with no error: the
  script's post-copy `os.sync()` is a GLOBAL flush that waits on every
  superblock in the kernel, and under WSL2 all distros share one kernel — a
  leaked FUSE superblock (orphaned by WSLg, no live process holding it, so
  nothing could ever answer) blocked it indefinitely. Diagnosed from the
  kernel stack: `ksys_sync → fuse_sync_fs → request_wait_answer`, python
  sleeping at zero CPU. The fix replaces `os.sync()` with `syncfs()` on the
  host output directory's fd — flushing only the filesystem the site was just
  copied to, which is the only one that step has any business waiting on.

  **The mac is exposed to the same class of failure, not just in principle**:
  Colima mounts `$HOME` into its VM via Lima's FUSE-based sshfs, so a global
  sync inside that VM waits on the host mount daemon every time. Deploys
  succeed today because the daemon answers, not by construction. Nothing to
  implement — the script is shared — but the DMG must be built AFTER pulling
  this commit or the two platforms ship different toolchains for 1.0.0. The
  changed script also changes the image hash, so the first preview/deploy
  after the mac app rebuild does a one-time image rebuild (a few minutes of
  "Building your website builder…") — expected, not a fault.

  Rejected: keeping `os.sync()` (it waits on superblocks wholly unrelated to
  Plantoir); fsync-per-file (hundreds of files over a slow VM mount, and the
  copy is rsync's work anyway); dropping the flush entirely (it exists so the
  host-side deploy step never reads a half-written `public/`). Reference:
  `scripts/build_site.py` → `_sync_public_to_host`.

- ✅ DONE (mac, 2026-08-19, commit "Pin the trail as wired, not merely
  declared"). All three events fire on the mac — verified against the REAL
  trail from the 1.0.0 DMG smoke, not just the code: `opened the working
  folder …`, `started setup.sh` → `finished after 15.2s`, preview
  start/stopped-on-purpose, deploy start/finish with duration all appeared.
  The stronger pin now exists:
  `mac-app/Tests/QuartzTeachersTests/ActivityTrailWiringTests.swift` scans
  the product source and fails if any `ActivityTrail.Event` case is
  referenced nowhere outside its declaration — which turns
  declared-but-never-called from a months-later discovery into a red test.
  (It cannot prove a call site is *reached*; `noteLaunch`'s three events are
  additionally verified as firing by running it against a scratch store.)
  Windows should mirror the scan — see `WINDOWS-HANDOFF.md` → "Pinning the
  trail as wired".
  On pollution: the mac suite does NOT write the real trail, and never did —
  `ProblemReportStore.standard` detects XCTest hosting
  (`XCTestConfigurationFilePath`) and returns a throwaway folder, which also
  covers the HOST APP's launch lines written before any test-bundle code
  loads (the case a Windows-style module initializer runs too late for,
  because the mac test target is app-hosted). Verified empirically: the real
  `activity.txt` was byte-identical (same SHA-1) before and after a full
  suite run. That redirect is now pinned by
  `testTheSuiteWritesToAThrowawayTrail` so a refactor of `standard` cannot
  silently lose it.

  Original request follows, kept for the reasoning:
  **Verify the mac actually EMITS the three trail events the contract pins —
  Windows declared them and never called them** (Windows, 2026-08-19). The
  same release smoke left ZERO lines on the Windows activity trail for a
  course creation, a preview and a deploy: `TaskStarted`, `TaskFinished` and
  `WorkingFolderOpened` existed in `ActivityTrail.Event`, so the contract
  test — which compares the ENUM list against `shared-rules.json` →
  `activityTrail.mustRecord` — passed while nothing ever fired. The list pin
  cannot catch a declared-but-never-called event, on either platform. Please
  check the mac's call sites fire for real (drive one preview, read the
  trail), and consider whether a stronger pin is possible. Windows wiring now
  lives in `windows-app/Plantoir.Core/Scripting/ScriptRunner.cs` (start:
  launcher + redacted arguments; finish: outcome distinguishing success /
  failure / stopped-by-teacher / backed-out-at-a-question, plus duration) and
  `WorkspaceViewModel.ChooseWorkspace` / `AdoptRestoredPath`.

  Related, same session: the Windows test suite was writing fixture courses
  (VVH2O) into the REAL trail — phantom lines a genuine problem report would
  gather. Fixed with a module initializer redirecting the trail before any
  test runs (`windows-app/Plantoir.Tests/TestTrailRedirect.cs`). Worth
  checking whether the mac suite pollutes its real
  `~/Library/Logs/Plantoir/activity.txt` the same way.

- ✅ DONE — SUPERSEDED, nothing owed. **Mirror the stop-sweep guard: await
  in-flight `--stop` sweeps before starting any build** (Windows,
  2026-08-19, GUI-IMPROVEMENTS row 282). An adversarial review the same
  night showed the mac needs none of this: its `PreviewStopper` already
  registers each sweep synchronously at the click and `waitForStopsToFinish`
  re-polls a live list — the two properties whose absence made the Windows
  copy racy. The Windows field failure this entry was written to explain
  turned out to be Windows-local anyway: `ScriptRunner.WaitUntilFinished`
  had been given a DEFAULT 5-second timeout that force-killed every deploy's
  build (row 283) — the sweep was never the killer. Windows has since
  adopted the mac's deploy-during-preview flow outright (row 283). Kept for
  the diagnostic reasoning; act on nothing here.
  Stopping a preview runs the launcher's `--stop` mode fire-and-forget, and
  that sweep kills the section's container-side processes BY WORKING
  DIRECTORY — including `/tmp/quartz-builds/<COURSE>/section<N>` — several
  seconds after the click. A deploy started right after stopping (the only
  order the interface allows, since Deploy needs the preview stopped) puts
  the sweep on top of the deploy's own quiet build and kills it before its
  first output flushes. The teacher sees an instant failure whose transcript
  ends at "Starting container if needed …" — nothing to go on at all.

  Windows reproduced this live during presentation prep and fixed it by
  making `PreviewStopper` track every in-flight sweep (each capped at 15 s so
  a wedged stop child can never hold a deploy hostage) and exposing
  `WhenSweepsFinish()`; the deploy path and both preview-start paths await it
  before launching a build. Reference: `windows-app/Plantoir/Services/
  PreviewStopper.cs`, `windows-app/Plantoir/Views/SectionDetailView.xaml.cs`.

  **The mac has the same latent race**: its `PreviewStopper` is the design
  Windows copied (row 105), equally fire-and-forget, and its `--stop` kills
  by the same working directories. Deploys there succeed today by timing —
  Colima's socket answers faster than WSL2, so the sweep usually lands before
  the next build starts — not by construction. Please mirror the guard.

  Rejected on Windows: teaching the sweep to spare "young" processes (the
  sweep cannot tell a leftover preview build from a new deploy build — any
  age cut-off guesses); retrying the killed build once (hides the mechanism
  and doubles the slowest path); having deploy skip the quiet build when a
  sweep is near (the build is needed; the wait is the honest fix). This
  cannot be a contract case: it is process timing on one machine, exactly
  the platform mechanics the contract's coverage table excludes.

- **A contract case for the summary/detail split — the mac already passes it,
  so this is a pin, not a request** (Windows, 2026-08-18, `windows-sync`).
  Windows has just ported `AssistToolOutcome`'s two-audience split, having
  shipped for weeks without it (see the awareness entry below for what that
  looked like). The behaviour is now pinned on this side by
  `windows-app/Plantoir.Tests/ToolAnswerTests.cs`, and it is NOT pinned by
  anything shared — which is how the two apps came to differ on it in the
  first place.

  What is wanted is a case list both suites run: for each of the thirteen
  tools the local model is shown, the sentence a TEACHER reads, against the
  longer answer the model gets. It could not be proposed from here with any
  confidence, and the reason is worth recording rather than re-deriving:
  `scenarios` and `nearMisses` are the authored halves of
  `assist-cases.json`, and both are shaped around the agent LOOP —
  `given` / `when` / `expectReply: "wording.X"` — where this is about what
  ONE tool returns, keyed to a course fixture the two suites do not share. A
  new top-level key would be the honest shape, and whether the generator
  preserves one is knowable only on the mac, where `--write-contracts` runs.
  **Please decide the shape and add it**; the Windows tests will be rewritten
  against whatever lands. The wordings to pin are in the awareness entry
  below.

  Rejected here: proposing it under `scenarios` anyway. A case the generator
  might silently eat is worse than no case, because the next person reads a
  green suite as proof.

## For awareness — no mac code needed

- **plantoir.app now has a Windows hero composite, and `deploy_site_name`
  turned out not to be a key** (Windows, 2026-08-19, commit "Give the Windows
  marketing shots a hero composite, and fix three fixtures").
  - **What changed**: the hero image existed only for the mac, so
    `build.py`'s platform swap served Windows visitors a picture of a Mac.
    `website/shots/hero_windows.py` now produces `hero-windows-light.png` and
    `hero-windows-dark.png` from Obsidian, Plantoir mid-deploy and Edge on
    the published site, through the same `composite.diagonal_hero()` the mac
    uses. Nothing on the mac side changes: `build.py` picks the twin up by
    file name the moment it exists.
  - **The one mechanism worth knowing**, because it is where the two
    platforms genuinely differ: the mac's `screencapture -l <window id>`
    returns a single window with its rounded corners already transparent.
    Windows has no equivalent, so every card is a REGION of the screen —
    the window is placed, raised, and the rectangle `DwmGetWindowAttribute`
    reports as `DWMWA_EXTENDED_FRAME_BOUNDS` is grabbed, then the corners are
    masked. `GetWindowRect` is the wrong rectangle: it includes an invisible
    resize border. **Rejected**: `PrintWindow`, which can capture a window
    bigger than the screen and would have avoided the sizing constraint
    below, but returns black for WinUI 3 surfaces.
  - **Consequence the mac does not have**: the cards are limited by the real
    desktop. This machine is 1920×1080 at 150%, so a work area of 1920×1008
    caps them at 1680×960 real pixels — a wider aspect than the mac's
    1280×800 cards. The finished figures still land at the shared
    `FIGURE_WIDTH` of 1700, so the column edges line up down the page.
  - **A `--hero-window <theme>` mode was added to `Plantoir.exe`** for the
    middle card. **Rejected**: reusing the `RenderTargetBitmap` the other
    Windows shots use — it renders the visual tree, which has no title bar,
    so Plantoir would have been the one card in the cascade with no window
    chrome beside Obsidian's and Edge's.
  - **The `deploy_site_name` question is answered**, and the answer is not
    the one `WINDOWS-HANDOFF.md` anticipated. That file asked this side to
    decide what the capturer's fixtures should write now the demo sites are
    named per section (`<code>-s<n>-2026-gordon`), since the new scheme names
    a SECTION while the key sits in course-level config. The key was never
    real: it appears in no launcher, in no contract —
    `contracts/file-formats.json` lists what `course_config.json` carries and
    it is not there — and nowhere else in either app. **Renaming it would
    have looked like settling the question while changing nothing.** The
    fixtures now write `.netlify_sites/section<n>.json`, the per-section
    marker a real deploy leaves and the one `build_site.py`'s
    `resolve_section_domain` and `deploy.py`'s `load_netlify_marker` actually
    read. Worth a glance on the mac only to confirm nothing there writes the
    invented key either.
  - **A second invented key was found beside it**: the same fixtures wrote
    `section_count`, which nothing reads, so every demo course came up with
    ONE section while the mac's showed two. It is `num_sections` /
    `section_numbers`. Reference:
    `windows-app/Plantoir/Services/MarketingShotCapturer.cs`.
  - **Nothing for the mac to match.** Both harnesses photograph their own
    platform; this is a note so the next mac session is not surprised to find
    a `hero-windows-*` pair in `site/img/`.

- **Deploys ask for the teacher's surname only when NAMING a new site, never
  on a repeat deploy** (Shared Python, 2026-08-19).
  - **What was fixed**: `deploy.py` called `get_or_prompt_teacher_last_name()`
    unconditionally at the top of every deploy. On a machine with no saved
    surname that stopped EVERY deploy for input — including deploys to a
    section whose site already existed and needed no name at all. In the GUI
    the question surfaces as a dialog, but a missed or cancelled dialog read
    as "deploys are broken", and in any non-interactive context the answer
    was silently None anyway. Seen live during Russell's presentation prep:
    a fresh workspace's first app deploy stalled at the surname question and
    never reached site creation.
  - **The fix**: the surname is LOADED silently at the top
    (`load_teacher_last_name()`), and `get_or_prompt_teacher_last_name()`
    runs only at the two places a NEW name is being chosen — the Netlify
    `not site_marker` branch and the Cloudflare no-marker branch. A repeat
    deploy therefore asks nothing anywhere: GUI, MCP, scheduled, or shell.
    Verified live on Windows: repeat deploy with no saved surname and no
    profile.json completed with zero prompts and wrote no profile.
  - **Rejected**: keeping the eager prompt and teaching every caller to
    pre-seed profile.json (fixes one machine at a time — the failure just
    met is exactly that patch not scaling); prompting but defaulting after a
    timeout (a deploy that behaves differently depending on how fast you
    answer is worse than one that never asks).
  - **Mac impact**: shared `deploy.py` — rebuild the mac app so its bundled
    toolchain carries it. The mac's own GUI has the same exposure (its
    launcher runs on a pseudo-terminal, so the eager prompt fired there
    too).

- **Two corrections to the release-packaging sync, made while integrating it
  on Windows** (Windows, 2026-08-19, follows `6326c8c9`/`1117e47c`).
  - **`windows-app/publish.ps1` could not START on Windows.** The new
    installer block used the null-conditional operator (`?.`), which Windows
    PowerShell 5.1 — the interpreter the script's own header prescribes via
    `powershell -File` — cannot parse: the whole file failed with
    "Unexpected token '?.Source'" before running a line. Verified with the
    5.1 parser before and after; now rewritten as a plain `if`. When writing
    PowerShell from the mac, treat 5.1 as the floor: no `?.`, `??`, ternary,
    or pipeline-chain `&&`/`||`.
  - **The Métis skeleton rename would not have survived regeneration.**
    `support/skeletons/` is generated (`generate_skeletons.py`), and
    `1117e47c` renamed a generated file by hand — the next
    `generate_skeletons.py` run would have resurrected the accented filename
    and dropped the alias, silently. The rule now lives in the generator
    (`write()` folds combining marks out of filenames and inserts the
    accented alias after the title) and in `lint_skeletons.py` (title may
    differ from filename only by combining marks, and only with the alias
    kept). Regeneration verified byte-identical to the committed tree.
    Rejected: leaving the hand-edit in place (a generated tree that differs
    from its generator is a time bomb) and ASCII-folding en dashes / ² too
    (single code points do not decompose in a DMG; seven such names ship in
    example_content today and are fine).

- **Netlify uploads now retry on 429 with backoff, at 5 workers not 10**
  (Shared Python, 2026-08-19, follows `e0136437`).
  - **What was fixed**: the parallel-upload optimization (`e0136437`, 10-worker
    `ThreadPoolExecutor`) broke EVERY deploy large enough to matter: Netlify
    rate-limits the per-file upload endpoint, and one 429 aborted the whole
    deploy. Measured live on Windows (WSL2 Docker, home broadband): a fresh
    318-file ICS3U deploy died on the first 429 — reproducibly — where the old
    serial loop had always stayed under the limit. So "optimized" deploys
    failed 100% of the time on any new site; that is why deploys "stopped
    working" the same evening the optimization landed.
  - **The fix** (`scripts/deploy.py` → `_upload_required_files`): each file
    upload retries up to 6 times on 429/500/502/503/504 and on socket
    timeouts, with exponential backoff (1 s doubling, capped 30 s), honouring
    a `Retry-After` header when Netlify sends one; workers reduced 10 → 5.
    A non-retryable API error still fails the deploy immediately.
  - **Rejected**: reverting to serial (throws away a real win once retries
    exist); keeping 10 workers with retries (converges, but spends its time
    backing off — 5 stays mostly under the limit); a global rate limiter
    shared across threads (more machinery than the endpoint's behaviour
    justifies — per-file backoff empties the herd quickly enough).
  - **Mac impact**: `deploy.py` is shared, so the mac had the same broken
    window between `e0136437` and this fix. Nothing to port — but the mac app
    must be REBUILT so its bundled toolchain carries the fix, or every
    working folder it refreshes keeps deploying with the 10-worker version.

- **`Get-ToolchainHash` in the `.ps1` launchers now anchors to the launcher's
  own folder** (Windows launchers only, 2026-08-19). `.sh` launchers are
  unaffected — bash `cd` moves the real process CWD.
  - **What was fixed**: the PowerShell hash function resolved its relative
    context (`./.toolchain`) with .NET path APIs, which use
    `Environment.CurrentDirectory` — and `Set-Location` does NOT update that.
    A launcher invoked from a process whose CWD held a *different* stale
    `.toolchain` (seen live: a terminal session sitting in the repository,
    which had an Aug-11 mirror at its root) hashed the stale folder, matched
    an Aug-11 image tag, and silently ran week-old scripts while `docker
    build`'s context — resolved from the PowerShell location — pointed at the
    fresh folder. Image tag and image contents could disagree.
  - **The fix**: `$fullContext` is now built from `(Get-Location).ProviderPath`
    (the launchers `Set-Location` to their own folder at startup), in
    `deploy.ps1`, `preview.ps1`, and `setup.ps1` alike.
  - **Mac relevance**: know that a Windows image tag from before this fix may
    not describe its contents; if a Windows machine misbehaves after sync,
    recreating the container clears it.

- **Production rebuilds in `deploy.py` delegate to `build_site.py --build-only`**
  (Shared Python, 2026-08-18).
  - **What was fixed**: After Quartz build staging moved to container-internal ext4 storage (`/tmp/quartz-builds/<COURSE>/section<N>`), `deploy.py` failed when rebuilding for production (when detecting preview live-reload scripts in `index.html` or updating `baseUrl` for live site domains). It was calling `npx quartz build` directly in `cwd=section_dir` (`/teaching/courses/<COURSE>/.merged_output/section<N>`), which in the dual workspace architecture contains only `public/` and `course_config.json` rather than the full Quartz scaffold. If `/tmp/quartz-builds` was clean (e.g. freshly created container, or deploy without preview in the same session), `deploy.py` crashed immediately with `Production rebuild failed`.
  - **The fix**: `deploy.py`'s `rebuild_for_production` and `ensure_base_url_and_rebuild` now delegate production rebuilds directly to `build_site.py --course <COURSE> --section <N> --build-only`, which ensures the internal workspace is staged, applies all patches and domain markers, generates the production build without the live-reload websocket, and syncs `public/` cleanly via `_sync_public_to_host`.

- **Whole Unit Publish / Unpublish and MCP Tool Parameter Binding on Windows**
  (Windows, 2026-08-18). Awareness only; Windows now matches macOS behavior for whole unit operations.
  - **What was fixed**:
    1. Prompt shelf and card commands for "Unpublish Unit 4" generated tool calls missing `includeLinked`, causing ModelContextProtocol.NET binding errors on tools with non-optional parameters. Added default values (`includeLinked = false`, `progress = null!`, `cancellation = default`) across MCP tool declarations in `PlantoirTools.cs` and populated defaults in `AssistCardCommand.cs`.
    2. Implemented `PublishPlan.UnitNamed` and `AssistWorkspace.PlanWholeUnit` / `ApplyWholeUnit` matching `AssistToolRunner.swift:598-790`. Whole units step through class pages in order (Day N down to 1 for unpublishing, Day 1 up to N for publishing), batch all file edits into a single undo entry, and trigger a single preview rebuild.
  - **Testing**: Added whole unit unit tests in `ToolAnswerTests.cs` covering plan description, whole unit unpublish, whole unit publish, and whole unit single-step undo. All 522 tests pass.

- **Assist Plan Formatting & Graph Sweep Parity Completed on Windows**
  (Windows, 2026-08-18). Awareness only; Windows was brought into 100% byte-for-byte
  parity with macOS for all assist tool plans and suggestions (`PublishPlan`, `ReDatePlan`,
  `CurriculumMentionsPlan`).
  - **What changed**: Windows was outputting technical mechanical descriptions (file paths,
    frontmatter keys `publishForSection1: false → true`, `(2027-01-15, publish: true → false)`,
    arrows `→`, fake index embed diffs, and Netlify deploy boilerplate). Rewrote `PublishPlan.cs`,
    `ReDatePlan.cs`, and `AssistWorkspace.cs` unpublish sweep algorithm to match
    `AssistPublishPlan.swift` and `SectionReDatePlanner.swift` exactly.
  - **Graph Unpublish Sweep**: Implemented reason-to-keep link traversal (`“Tech Headlines” stays visible, because “Unit 1, Day 15” still links to it.`),
    landing page preservation, Key Links protection, curriculum page preservation, and transitive link following for publishing.
  - **Testing**: Added `AssistPlanParityTests.cs` explicitly validating the ICD2O Section 1 unpublish
    case and plan structures. All 518 unit tests in `Plantoir.Tests` pass.

- **Two `check_section` defects, one teacher report — and the second is the
  one that generalises** (Windows, 2026-08-18, `windows-sync`). Awareness

  only; the mac is right on both counts already.

  Asked what students would see, Windows answered "83 visible pages are linked
  from nowhere" and listed the course's own lessons. **(a)** Class pages were
  counted as orphans. The mac excludes them — `AssistSectionPage.isClassPage`
  — and its comment records hitting exactly this on an 86-period credit that
  reported 84. Windows now excludes them by the course's own
  `per_section_folders` rather than by the mac's "parent folder name contains
  'class'" heuristic; if the mac ever wants the stricter rule, the config is
  the better source. Note the two questions that must NOT be merged: the
  contract's `followingLinks.neverTakenDownByFollowingLinks` is about what
  unpublishing may sweep, and a class page IS swept.

  **(b)** is the one worth knowing over here, because it is a whole CLASS of
  bug this side cannot have. The preview state was read from `PreviewLeases`,
  an in-memory static belonging to the app — but `check_section` runs inside
  `plantoir-mcp`, a different process, where that list is permanently empty.
  So "Nothing is being previewed at the moment" was said every single time,
  whatever was on screen; the trail shows the teacher pressing Preview 32
  seconds before asking. On the mac the assistant and the preview are the same
  process and `sectionWindow(...)?.previewState()` is a method call, so the
  question never arises.

  **The shape of it: an in-memory static read from the wrong process does not
  fail, it answers "nothing".** That is indistinguishable from a true answer,
  which is why it survived. `WorkLease` — the on-disk, format-first registry —
  was already written for precisely this and was simply not being read. If the
  mac ever splits its MCP server out of the app bundle, every `PreviewLeases`
  and `CourseActivity` read becomes this bug at once.

  Two limits, stated because they are real: the leases are per-COURSE rather
  than per-section, so previewing Section 2 while asking about Section 1
  reports the wrong thing; and the build lease is released the moment the
  server answers, which is what makes "building" and "showing" two states
  rather than one.

- **The confirmation setting on Windows was wired to nothing for weeks**
  (Windows, 2026-08-18, `windows-sync`). Awareness only — the mac has had
  this since plan mode shipped — but worth recording because of HOW it went
  unnoticed. `AssistAgent.ConfirmationMode` was set from
  `AppSettings.AssistantAsksBeforeChanging` in `AssistWindow` and then never
  read, so the switch in Settings did nothing; and the discoverability nudge
  after fifteen accepted plans ("The assistant shows what it is about to do
  before doing it. You can change that in Settings.") was firing and
  describing behaviour the app did not have. A setting that is stored,
  displayed and ignored looks exactly like a setting that works.

  Now ported. Two Windows-specific pieces the mac may care about:
  `AssistToolOutcome.isPlan` is an in-process field here and had to become a
  second `_meta` key over MCP (`plantoir.app/isPlan`, sent only when true) so
  the gate can tell a plan from a plan tool's REFUSAL; and
  `AssistAgent.PlanTwins` deliberately omits `re_date_classes` even though the
  contract lists a twin for it, because it is not a tool the local model is
  shown and its twin does not mark its answer.

- **Windows was chatty for one structural reason, and it was not wording**
  (Windows, 2026-08-18, `windows-sync`). Recorded because the mac's own
  design is what fixed it, and because the reasoning behind `AssistToolOutcome`
  is not written anywhere the Windows side could have read it.

  Every Windows tool returned ONE string, and it was shown to the teacher AND
  fed to the model. So "read Unit 2, Day 3" put a lesson's entire Markdown in
  the chat window; "what pages are in this section" put sixty file paths
  there; a publish said "Published 4 pages (A, B, C, D) and rebuilt the
  preview of ICS3U Section 1"; and every plan ended with "Show this to the
  teacher and ask before going ahead" — a sentence addressed to the model,
  directly above the two buttons that ARE the asking. Two earlier attempts at
  this (log rows 263 and 264) shortened individual sentences and fixed the
  turn-taking, and neither touched the split, so the chattiness survived both.

  The mac's teacher-facing lines are now Windows' too, word for word:
  `Read “Unit 2, Day 3”.` · `Found 42 pages in ICS3U Section 1.` ·
  `Nothing matched in ICS3U Section 1.` · `Published 4 pages.` ·
  `Unpublished 2 pages.` · `Published the class on 2026-09-10.` ·
  `It's already been published.` · `Added Unit 2, Day 4, dated 2026-09-14.` ·
  `ICS3U Section 1 meets on 75 recorded days.` ·
  `Scheduled: ICS3U Section 1 deploys to Netlify at Tuesday 9 June, 6:30 AM.`
  Undo now speaks the contract's sentences rather than its own.

  **The one thing the mac may want to know for its own sake**: the split
  costs the mac nothing because its runner is in-process, but Windows drives
  the same `plantoir-mcp` Claude Code drives, so the summary needed a wire.
  It rides in the tool result's `_meta`, under `plantoir.app/teacherSummary`,
  and the text content is untouched — Claude Code sees exactly what it saw
  before. Rejected: a second text content block (Claude Code would read both
  and report the teacher's line as part of the answer), and
  `structuredContent` (it is validated against a declared `outputSchema`, and
  declaring one changes what every client sees of every tool). If the mac's
  MCP server ever wants to hand a summary to a client of its own, that is the
  channel, and `AssistToolAnswer.TeacherSummaryKey` is the frozen key.

  Two smaller things found in the same sweep, both fixed on Windows and
  neither present on the mac: the turn-ending list named `roll_over_course`
  for a tool actually called `roll_over_section` (so that write got the model
  a lap it should not have had, and the teacher a paragraph restating the line
  above it), and `list_recent_changes` ended by telling a teacher that
  "undo_last_change takes the most recent one back" — rule 1, in the one place
  a teacher is most likely to be reading.

- **Anything you build over there now owes a trail line** (mac, 2026-08-16).
  Plantoir keeps a breadcrumb trail so a problem reported next week can be
  looked into without asking the teacher to reproduce it, and the rule binds
  both sides: **every new feature, and every changed behaviour, that a teacher
  can see records an event.** The list lives in
  [`contracts/shared-rules.json`](contracts/shared-rules.json) →
  `activityTrail.mustRecord`, with `lineShape` and `promptMarker` beside it,
  and a test pins it against each app's own event list.

  The direction rule applies as usual and in your favour: **propose an event by
  adding it to `mustRecord`.** The mac suite will go red until this side
  records it — that is the mechanism working, not damage — so name the case in
  "Contract cases waiting on the mac" above and it reads as a request. The
  reasoning, the storage locations and what must never be recorded are in
  `WINDOWS-HANDOFF.md` under "Problem reports"; `CLAUDE.md` rule 5 is the short
  version.

- **A divergence was reported TO Windows, not from them** (mac sweep,
  2026-08-16). The first-deploy marker: this side reads the marker for the
  course's CURRENT destination, `AssistWorkspace.cs` accepts either folder.
  Written up in `WINDOWS-HANDOFF.md`. Nothing to do here — the mac's behaviour
  is the correct one — but if they answer with a reason for their version,
  that answer belongs in `contracts/file-formats.json` beside the rule.



Things to KNOW rather than to do. An item here that grows an ask should move
up to **Open** instead of hiding a to-do in a list nobody reads for work — which
is what happened to the test-race item, sitting here for three days with
"worth ten minutes to check" in the middle of it.


- **WSL2 / Container-Internal ext4 Build Acceleration** (Windows + shared, 2026-08-18, commit `ed868215`).
  Accelerated Quartz site builds on both platforms by eliminating the virtual host mount I/O bottleneck (WSL2 9P DrvFs on Windows, Colima virtiofs/9P on macOS):
  - **The Problem**: Staging the 15,000+ files of Quartz's scaffold and `node_modules` in `courses/<COURSE>/.merged_output/section<N>` meant that all TypeScript transpilation, esbuild bundling, and markdown AST parsing traversed virtual filesystem mount layers. On Windows with WSL2, initial builds took 2–4 minutes; on macOS, clean builds took ~18.7s with 14s burned on `npm install` across the mount boundary.
  - **The Solution**:
    1. Pre-bake `npm install` inside the container image in `/opt/quartz` (`Dockerfile`).
    2. In `scripts/build_site.py`, stage the Quartz workspace on native Linux ext4 storage (`/tmp/quartz-builds/<COURSE>/section<N>`), symlinking `/opt/quartz/node_modules` instantly.
    3. `scripts/build_site.py` runs differential `rsync -a --delete` to mirror `public/` and `course_config.json` back to `/teaching/courses/<COURSE>/.merged_output/section<N>/public/` upon build completion (and via a daemon thread in `--serve` mode), preserving 100% compatibility with `BuildFreshness`, `SectionDetailView`, `ScheduledDeploy`, and `deploy.py`.
    4. Updated `preview.ps1` and `preview.sh` `--stop` scripts so `PreviewStopper` checks `/tmp/quartz-builds/...` PIDs in addition to `.merged_output/...`.
    5. Updated `deploy.py` to support container-internal rebuilds.
  - **Results**:
    - **macOS (Apple Silicon + Colima)**: Full/clean builds dropped from **18.66 s avg** (18.39 s min) down to **5.08 s avg** (4.58 s min) — **3.7× faster**; incremental rebuilds dropped from **4.42 s** to **3.35 s** (1.32× faster) on `EXC2O` (260 Markdown files).
    - **Windows (Intel Core i5 + WSL2)**: Initial scaffold copy dropped from 45s to < 0.1s; `npm install` over 9P dropped to 0s; site builds run at native NVMe/ext4 speeds. All 570 Windows unit tests pass.
  - **✅ DONE (Adopted on macOS & merged to main, 2026-08-18).** All 760 macOS unit tests and `./verify.sh` pass.

- **Arrow-key prompt history navigation in Windows assist chat** (Windows, 2026-08-18).
  Windows now supports Terminal-style Up/Down arrow key history navigation in `AssistWindow.xaml.cs`.
  - **Behavior & Contract**: Follows `contracts/assist-cases.json` → `promptHistory`. Up recalls earlier prompts (newest first), Down recalls later prompts, half-typed draft is preserved and restored when walking back down past newest, Up at oldest or Down when not walking passes the key through to the `TextBox` (letting caret move to start/end), typing/editing ends the walk, and multi-line text passes arrow keys through to allow vertical caret movement.
  - **Persistence**: Added `AssistPromptHistories` dictionary to `AppSettings.cs` (`%LOCALAPPDATA%\Plantoir\settings.json`), keyed per section (`$"AssistPromptHistory-{course.Code}-{section}"`) matching macOS `@AppStorage` convention.
  - **Reference**: `AssistWindow.xaml.cs`, `Plantoir.Core.Assist.AssistPromptHistory`, and unit tests in `Plantoir.Tests.AssistPromptHistoryTests` (514 tests passing).

- **Windows local assistant moved out of WSL2 to host process with Vulkan GPU acceleration** (Windows, 2026-08-17).
  Windows now runs `llama-server.exe` natively on the host instead of running a Linux container in WSL2.
  - **Why**: In WSL2 without GPU pass-through, a 3,400 token prompt prefix took ~175 seconds across 2 virtual CPU cores, necessitating an artificial progress countdown bar, a 98 MB disk prefix cache (`--slot-save-path`), and a background keep-awake hack (`_keepWslAwake`). Moving to a native Windows host process enables Direct3D12/Vulkan GPU acceleration across Intel/AMD/NVIDIA graphics and multi-threaded host CPU fallback.
  - **Vendor fetch & bundling**: Added `windows-app/Vendor/fetch-llama.ps1` downloading pinned build `b10435` (`llama-b10435-bin-win-vulkan-x64.zip`) into `windows-app/Vendor/llama/`. Updated `Plantoir.csproj` to bundle into `llama\` output, and `publish.ps1` to sign `llama-server.exe`.
  - **Hardware Measurements**: Measured on teacher laptop hardware — `Intel Core i5-8365U CPU @ 1.60GHz` (4C/8T), `Intel UHD Graphics 620` (8062 MiB Vulkan device memory), 16 GB RAM:
    - *Vulkan GPU (`-ngl 999 -dev Vulkan0`)*: Prompt processing (`pp512`): **25.82 tok/s**, Generation (`tg128`): **7.83 tok/s**, single turn cold response: **~17.99 s**.
    - *Host CPU fallback (`-ngl 0`)*: Prompt processing (`pp512`): **25.69 tok/s**, Generation (`tg128`): **11.67 tok/s**.
  - **Simplification**: Removed the fake 3-minute progress countdown and disk KV cache files from `AssistWindow.xaml.cs`. Warmup is now a fast, non-blocking background priming call. 464 tests passing in `Plantoir.Tests`.

- **Assist scenario contract runner & confirmation discovery parity on Windows** (Windows, 2026-08-18).
  The Windows side wired `AssistScenarioTests.cs` executing all 17 multi-turn scenario cases from `contracts/assist-cases.json` via parameterized `[Theory]` tests against `AssistAgent`.
  Async preview teardown before deploy was implemented via `PreviewStopper.StopSectionProcessesAsync` and `SectionDetailView.StopPreviewIfRunningAsync`, ensuring container and host preview server ports are fully vacated before `deploy.ps1` runs.
  Confirmation mode (`AppSettings.AssistantAsksBeforeChanging`) and 15-plan discovery milestone tracking (`plansAccepted >= 15` app-wide) were wired into `AssistAgent` and `AssistWindow.xaml.cs`, verified by `ContractTests.cs`. All 488 tests pass.


- **Windows marketing screenshots & platform-conditional serving on plantoir.app** (Windows, 2026-08-17).
  The Windows side implemented autonomous screenshot capture in `MarketingShotCapturer.cs` (`Plantoir.exe --capture-marketing-shots <dir>`) and `website/shots/capture_windows.py`.
  The 5 app-window marketing shots (`courses`, `new-course`, `progress`, `preview`, `assistant`) are captured in Light and Dark mode at 2x HiDPI resolution, optimized with WebP companions into `site/img/`.
  In `website/build.py`, `picture_element` outputs both Mac (`.shot-platform-mac`) and Windows (`.shot-platform-windows`) `<figure>` blocks when Windows variants exist.
  `website/layout/base.html` detects Windows visitors via an inline `<script>` in `<head>` and toggles CSS class `is-windows` so Windows visitors see native Windows WinUI 3 screenshots while macOS visitors continue seeing native macOS SwiftUI screenshots.


- **Cleanup that fails must not fail a test that passed** (Windows,
  2026-08-14, `0479d44`). An intermittent failure that never reproduced turned
  out to be 23 tests ending with a bare
  `finally { Directory.Delete(root, recursive: true); }`. On Windows that
  throws whenever anything still holds a handle in the folder — Defender
  scanning the files the test just wrote, or the Search Indexer. Every
  assertion had passed; the test failed on housekeeping. If the mac's tests
  do the same on a machine with Spotlight indexing, the same shape is
  available. Deleting a temp folder is housekeeping: when it does not work,
  the OS will get to it.


- **The MCP proposal's Phase 0 question is settled** (asked 2026-08-12,
  answered 2026-08-15). The design for letting AI assistants drive Plantoir
  over MCP — "publish the Science courses overnight and un-draft tomorrow's
  class plus everything it links to" — asked the mac side whether to ship
  **one** self-contained .NET binary serving both platforms, or reimplement
  the tool contract in Swift. Both halves are now code rather than a
  question: `windows-app/Plantoir.Mcp/` is built and on `main`, and the mac
  reimplemented the contract in `Models/Assist/AssistMCPServer.swift` — the
  app itself answers `--mcp-stdio <folder>` rather than shipping a second
  binary, off the same `AssistToolSurface` the assistant window uses, so the
  two clients cannot drift. The handshake is recorded in the entry above.
  (The proposal itself is now folded into `research/ai-assist/HISTORY.md`.)


- **The Windows icon derives from `mac-app/Plantoir.icon`** (2026-08-11).
  `windows-app/Plantoir/Assets/make-icon.ps1` turns a full-bleed 1024px
  Icon Composer export into the exe/.ico and About-panel assets, applying
  the macOS rounded-rect silhouette; `site/icon.png` on plantoir.app
  comes from the same export. If the icon art ever changes, tell the
  Windows side so those derived assets are regenerated — nothing updates
  them automatically.


- **Auto-update plans need appcast coordination** (2026-08-12). Windows
  will adopt WinSparkle (paired with an Inno Setup installer, planned
  after v1.0); if/when the mac app adopts Sparkle, BOTH appcasts should
  live on plantoir.app in this repo's `site/` — use per-platform file
  names from the start (`appcast-windows.xml`, `appcast-macos.xml`) so
  the two update feeds never collide, and add the release-time appcast
  edit to the shared checklist in `RELEASING.md` when the
  first one lands.


- **The mac release asset must be named exactly `Plantoir-macOS.zip`**
  (2026-08-11; SPECCED — the mac ships a zip, not a dmg: Safari
  auto-unzips, average users fumble the dmg ritual, and Sparkle handles
  zips natively). plantoir.app now lives in `site/` in this repo
  (Netlify deploys it on push) and its download cards link straight to
  `releases/latest/download/<asset-name>` — GitHub's evergreen URL that
  only works while every release names its assets identically. Windows
  ships `Plantoir-win-x64.zip`; the mac card expects
  `Plantoir-macOS.zip`. The names are frozen: renaming an asset silently
  breaks the site's download button.


- **The release process is shared — read `RELEASING.md`**
  (2026-08-11). The decisions that bind both sides: ONE product version
  series in lockstep (Windows reads `<Version>` in `Plantoir.csproj`;
  keep the mac marketing version matching), ONE GitHub release per
  version carrying BOTH platforms' assets (plantoir.app's download cards
  point at `releases/latest`), tag `v<version>`. Release notes are
  drafted by Claude via the `cut-release` skill
  (`.claude/skills/cut-release/`) — teacher-friendly bullets from the
  commit log plus a SHA-256 downloads table; the mac asset should be
  attached to the same release and hashed into the same table. (The
  `.claude/skills/example-content/` skill has since arrived — the mac
  side un-ignored `.claude/skills/` and committed it.)


- **Course-catalog repairs** (`37dc6c8`): MTH1W read "Mathematics,
  Grade 9, Grade 9, Destreamed" (short name "Math,") and PLF4M had the
  same doubled-grade + trailing-comma pattern; both repaired in
  `support/ontario_secondary_courses.json`. The mac app picks this up by
  rebuilding (bundled support folder). No other entries matched either
  pattern.


- **Toolchain hash changed** (`94e25f8`): `scripts/deploy.py` changed,
  so the next preview/deploy on any machine rebuilds the Docker image
  once.


- **Windows caught up with rows 91–96** (`e7076ae`): Starting Content
  toggles, structure lock, LCS terminology switch, and the neutral
  factory defaults are now mirrored on Windows (including the
  `WizardDefaults` pairing and a Windows `ExampleContentCatalog`).
  Nothing to do on mac — listed so the mac side knows the wizards agree
  and that changes to `DEFAULT_*`/`LCS_*` in `scripts/setup_course.py`
  must now be mirrored in BOTH apps' `WizardDefaults`.


## Done — the ledger

Kept in full, newest first. A finished entry is not deleted: the mac does what
it does BECAUSE of these, and the `✅ DONE` line names what landed here and
where.

- ✅ DONE (mac, 2026-08-20). **Setting up a working folder no longer blocks
  the main thread — the mac catching up to Windows 1.1.0, found by Russell
  while testing the v1.1.0 candidate.**

  **What was wrong.** `WorkspaceModel.initializeWorkspace()` copied the three
  launchers, made `courses/`, and mirrored the whole build recipe
  synchronously, called straight from the "Set Up This Folder" button. The
  recipe is **12,091 files and 65 MB** — `support/` alone is 11,354 of them,
  the example-content payloads and ~1,950 skeletons. Measured here (M-series,
  NVMe): **2.4 s** for a raw `cp -R` of the three folders, **3.7–4.0 s** for
  the real mirror, which also stats both sides of every file and sweeps the
  destination for extras. That is a beachball over a window that says
  nothing, and on an older disk, a USB drive or a folder the system is
  syncing it is tens of seconds.

  **The fix is yours, adopted as-is.**
  `WorkspaceViewModel.InitializeWorkspaceAsync` wraps the mirror in
  `Task.Run` and `Initialize_Click` disables both buttons and sets the label
  to "Setting up…". The mac now has `initializeWorkspaceInBackground()` doing
  the same, with the button showing a small spinner and **"Setting Up…"**.
  Nothing here needs porting — this entry exists because **the direction was
  Windows → mac**, which the ledger should record as readily as the reverse.

  **What the mac had to work out that your version did not face**, and the
  reason it is written down rather than left in the diff: the class is
  main-actor isolated, so moving work off the thread meant deciding what the
  background half is allowed to touch. It touches nothing shared. The copying
  (`copyToolchainFiles`, `setUpFolderOnDisk`) is `nonisolated` and reads only
  the app's own bundle — which cannot change while the app runs — and writes
  into one folder. The once-per-run `foldersWithFreshToolchain` set is
  **cleared before the await and set after it, both on the main actor**.
  Rejected: making that set `nonisolated` (it is shared mutable state across
  every window — the isolation is what makes it safe); passing `self` into
  the detached task (the model belongs to the main actor, and the folder can
  change under it while the copy runs, so only the URL crosses).

  **One trap worth carrying back**, because it is row 279's defect one thread
  over: the tracker must be cleared BEFORE the copy and set only AFTER it
  succeeds. Set it first and a failed setup leaves the folder marked fresh,
  so the next attempt skips the mirror and the folder stays without a
  `Dockerfile` — which is exactly the "missing the toolchain's build recipe"
  failure row 279 fixed. Worth checking `ToolchainMirror.InitializeWorkspace`
  handles a failure the same way.

  **Version note.** This is a behaviour change on the mac and the release
  still ships as **1.1.0**, deliberately: the version names which contracts a
  build passes, Windows 1.1.0 already behaves this way, so the mac not doing
  it was the mac being BEHIND 1.1.0 rather than 1.1.0 meaning something new.
  Shipping it makes the two platforms agree on the number. Decided with
  Russell, 2026-08-20.

  Reference: `WorkspaceModel.initializeWorkspaceInBackground`,
  `WorkspacePickerView`, and
  `WorkspaceInitializationTests.testInitializingInTheBackgroundProducesTheSameWorkspace`
  — which pins the BUTTON's path, since the synchronous form the tests
  previously covered is no longer the one a teacher takes. 764 tests.

- ✅ DONE (mac, 2026-08-20). **The teacher-made-link case is implemented, and
  the three setup cases are retired** — the two contract requests that stood
  between the mac and the v1.1.0 tag.

  **Implemented: the teacher-made-link case.** `FailureExplainer` on this side
  now recognises `untrusted mount point` and says the same sentence Windows
  says, word for word from the contract. It is checked FIRST, matching
  `FailureExplainer.cs`'s order, though nothing here depends on that: no other
  matcher looks at a WinError 448. This output cannot occur on macOS and the
  mapping is here anyway, for the reason the request gave — the two explainers
  stay ONE list of troubles rather than growing a platform switch.

  **Retired: the three one-time-Windows-setup cases.** Removed from
  `contracts/app-rules.json` rather than implemented, taking the branch the
  proposal itself named: `windows-native-toolchain` merged, the container path
  went with it, and no shipping launcher prints "needs to restart to finish
  getting ready", "Windows permission was declined" or "Windows could not add
  the feature this needs" any more. They survive only in 1.0.2, whose
  launchers are frozen and whose app already recognises them.

  **Why retire rather than keep them harmlessly.** A contract case is a claim
  that both apps must behave this way, and a case no launcher can trigger
  teaches the next reader that a dead code path is load-bearing — the same
  failure as stale advice, one file over. Rejected: keeping them "in case the
  container path comes back" (it is deleted, and a case is cheap to re-add
  from this entry); keeping them on the mac only (the whole point of the
  mapping was that the two lists match).

  **What Windows should do with `SetupExplanation`.** It is now unpinned by
  the contract. Delete it when the launcher code it reads goes, rather than
  leaving the only implementation of a rule nothing tests.

  **One difference the sync surfaced and did NOT close**:
  `FailureExplainer.cs` has a `FolderAccessExplanation` ("Plantoir couldn't
  read every file in this working folder…") that the mac has never had and no
  contract case pins. It is left alone deliberately — porting it is a
  behaviour change, no mac teacher has reported the trouble, and doing it
  inside a release-qualification pass would have pushed this cut to 1.1.1 for
  a sentence nobody asked for. It belongs in the contract either way: whoever
  picks it up should propose the case first and let both suites go red.

  Reference here: `mac-app/QuartzTeachers/Scripting/FailureExplainer.swift` →
  `vaultLinkExplanation`, run by `AppRulesContractTests` →
  `testFailuresAreExplainedAsTheContractSays`. 763 tests, 0 failures.

- **Windows app brought into full parity with shared contracts and macOS features**
  (Windows, 2026-08-17, branch `windows-sync`). All 466 tests pass on Windows
  (`dotnet test Plantoir.Tests/Plantoir.Tests.csproj`, 0 failures).
  
  **✅ DONE (Windows, 2026-08-17).**
  1. **All contracts wired and tested in `Plantoir.Tests`**:
     - `AssistCasesContractTests.cs`: runs all `assist-cases.json` scenarios, near misses, and prompt history.
     - `ClassPlanningContractTests.cs`: runs all `class-planning.json` cases (Unit X, Day Y regex parsing, title numbers, next class planner, class insertion renumbering and link rewrites).
     - `ScheduleRulesContractTests.cs`: runs all `schedule-rules.json` cases (Google Sheets CSV URLs, date columns, relative days, ambiguous slash dates).
     - `ContractTests.cs`: runs `app-rules.json`, `assist-wording.json`, `course-management.json`, `file-formats.json`, and `shared-rules.json` (activity trail, model jargon sweeps, curriculum rules, assistant model choice, problem reports, and credential prompts).
  2. **Native Host Local AI Assistant with Vulkan GPU Acceleration**:
     - Pinned `llama.cpp` `b10435` with Vulkan binaries bundled via `windows-app/Vendor/fetch-llama.ps1` and signed in `publish.ps1`.
     - `LocalModel.cs` spawns native host `llama-server.exe` directly on dynamic loopback port with `--n-gpu-layers 999`, `--reasoning off`, `--reasoning-budget 0`, `--jinja`, `--parallel 1`.
     - Removed slow WSL2/container execution (~175s -> ~18s end-to-end on Intel UHD 620). Fast background priming.
  3. **Assistant Choice & Settings Panel (`AssistantSettingsDialog`)**:
     - "Before it changes your pages" toggle + small assistant caution.
     - "Which assistant runs on this PC" (automatic, smaller, larger) with hardware budget memory derivation and cautions.
     - "On this PC" housekeeping list with download status, download trigger, and safe model removal (disabled when any assistant window is open).
     - Connected to `AppSettings` and `MainWindow` menu (`File -> Settings…` / `Ctrl+,`).
  4. **Curriculum Coverage Map & Notes Toggles (Row 130 parity)**:
     - Added `include_curriculum_coverage` and `include_coverage_notes` per-section configuration accessors and `CoverageNotesEnabled` pure rule to `CourseConfiguration.cs`.
     - Added toggle switches with dependent enablement in `CourseSettingsView.xaml.cs` and `NewCourseDialog.cs`.
  5. **LinkGraph Exclusions & Visible Referrer Sweeps (`shared-rules.json` -> `followingLinks`)**:
     - `LinkGraph.cs` excludes landing pages (`index.md`), curriculum pages, and Key Links targets from link sweeps.
     - `VisibleSourcesOf` ensures only visible referrers keep pages published.
  6. **Credentials & Token Dialogs with ActivityTrail Logging (`CredentialRequests.cs`)**:
     - Rich credential dialogs in `TaskProgressView` for Netlify token, Cloudflare token, and Cloudflare Account ID with numbered steps, token links, and PasswordBox/TextBox without auto-opening tabs.
     - "Where do I find this?" link button in `PublishingChoiceView` opening Cloudflare Account ID help dialog.
     - `ActivityTrail` logs `asked for a publishing credential` on prompt and instructions open.
  7. **23 MCP Tools**:
     - Implemented and exposed in `PlantoirTools.cs` / `plantoir-mcp.exe`.
  8. **Prompt Shelf with Collapsible Groups (`AssistPromptShelfView.cs`)**:
     - Pinned at the top of `AssistWindow` with 5 collapsible categories matching macOS verbatim (19 cards).
     - Tapping a card fills the input box for editing. Open/shut state is persisted in `AppSettings.AssistPromptShelfOpenGroups`.
     - Tested in `AssistPromptShelfTests.cs` (473 total tests passing).

- **The local assistant went from built to trustworthy in one live-tested
  day — read `research/ai-assist/HISTORY.md` part 2 §10 before building the mac's**
  (Windows + shared, 2026-08-14, the `ai-assist` branch from `7b18fe6` to
  `1961d07`). The short of it: everything measured, five design decisions
  worth inheriting rather than rediscovering, and the conversation loop is
  now **shared C# in `Plantoir.Core`** — port the window, not the logic.

  **✅ DONE (macOS, 2026-08-15) — read, and mostly inherited.** The design
  decisions were taken across whole: coarse tools, plan_ twins, publish and
  unpublish as separate verbs, nothing destructive, the gate reading the
  server, the card phrasings matched in code, the date APPENDED. Two things
  are deliberately different. **The cache save/restore was not ported** —
  it exists to avoid a 175-second cold read, and natively that read is 2.1
  seconds, so the machinery would be pure failure surface; a background
  warm-up on window open replaces it in a dozen lines. And **there is no 3B
  rung**: measured here, it inverts polarity. See spec entry 144.

  1. **The loop is `Plantoir.Core/Assist/AssistAgent.cs`**, behind
     `IChatModel` (the llama.cpp client) and `IToolServer` (the MCP stdio
     client). The mac app supplies those two and a window; every behaviour
     below comes with the class, already pinned by
     `Plantoir.Tests/AssistAgentTests.cs`, which runs the whole promise
     card in two seconds.
  2. **The promise card's eleven phrasings are COMMANDS, not routing
     questions** (`CardCommand`). Measured word for word, the model
     misrouted five of eleven — every trial — while filling arguments
     perfectly (87 trials, zero wrong courses/dates/types). Fixed shapes
     are matched in code; the model keeps whatever has a story in it.
  3. **Only deploys wait for a button.** Everything else is backed up,
     undoable, and invisible to students until a deploy; a scheduled
     deploy collects its yes at scheduling time. The plan-first system
     prompt is gone (it made undo over-salient — see §10.4's regressions
     before re-wording anything).
  4. **The assistant automates the app, it does not duplicate it.**
     `rebuild_preview`/`deploy_section` never reach the server from the
     window — they press the app's own Preview/Deploy. Page edits run
     with `preview: false` and do what a person would: stop the showing
     preview, edit, OFFER the restart. This matters because the served
     preview is a merged COPY — an edit is invisible to it until rebuilt,
     which on Windows read as "the assistant is stuck".
  5. **The prompt cache is real and once-ever, if you name it honestly**:
     save/restore verified (175 s cold → 30 ms restore → 11.7 s turn),
     file named per course + section + SHA-fingerprint of system prompt
     AND narrowed schemas, empty saves deleted, "Ready"/"picking up"
     only said when true. Reference: `LocalModel.cs` (the WSL parts are
     Windows-only; the colima analogue of "who holds the VM open" is
     yours to check).

  Smaller but shared: MCP progress only flows if the client sends
  `_meta.progressToken` (see `McpClient.Call`) — without it every
  milestone line is silently dropped; `AssistWorkspace.Apply` now narrates
  page-by-page ("Editing “Unit 2, Day 3”…"), which the window grows into
  one work-log bubble; the dateline rides appended on every user turn
  (prepended cost 15 routing points; in the system prompt it would break
  the cache nightly); `NarrowToLocal` rewrites the schemas' example
  course to the window's own, because the model copies examples; and the
  transcript speaks with ONE name, never shows content that rides with a
  tool call, and never shows the dateline.


- **⚠️ Add Section was creating pages in the OLD schema — check yours**
  (Windows, 2026-08-14, `7a66200`). The publish/draft entry below was landed
  and then found INCOMPLETE: `SectionAdder`'s fallback template — the path
  taken when there is no sibling section to copy — was still writing
  `draft: true`. A section added through the app was therefore born in the
  schema everything else had moved off.

  **✅ DONE (macOS, 2026-08-14, `b2a4c0bf`).** Fixed, and the mac had the
  same bug in a second place Windows had not hit: `SectionAdder` also
  COPIED `draftSectionN` from the sibling section, so a course installed
  from a migrated payload would have found no key and published a page the
  teacher had held back. `publishValue(forSection:in:)` now reads either
  key and inverts the legacy one, and
  `testALegacyDraftSectionKeyIsReadAndInverted` pins the inversion.

  It was missed because the TEST agreed with the code: it asserted
  `draft: true` and passed. Worth ten minutes on the mac's own section
  scaffolding for exactly that reason. Two rules: write `publish:` inverted
  (a teacher-eyes-only page is `publish: false`), and only in the FALLBACK —
  when a sibling section exists its frontmatter is copied verbatim, which is
  right, because a course still using `draft:` should get a new section that
  matches its siblings rather than one page speaking a different language.


- **A section remembers when its classes meet** (shared, 2026-08-14,
  `9fa510c`). `courses/<CODE>/.internal/timetable/section<N>.json` holds the
  dates, where they came from in the teacher's words, and when recorded.
  Written when a re-date is applied, and by a new `remember_timetable` tool.

  **Format first, as with `WorkLease`** — the mac should read and write the
  same file rather than the same code:

  ```json
  { "section": 1,
    "dates": ["2026-09-08", "2026-09-10"],
    "source": "timetable.xlsx, block H",
    "recorded": "2026-08-14" }
  ```

  Inside the course, under `.internal/`, so it travels through backup,
  archive and restore — all of which are already careful about that folder. A
  file kept beside the app would come adrift the first time a teacher moved
  their work and be silently WRONG rather than missing. A partial list is
  refused rather than half-stored: a half-remembered timetable gets trusted
  and then dates the wrong classes.

  **✅ DONE (macOS, 2026-08-15)** — `Models/SectionTimetable.swift` reads and
  writes that exact file, the path built from the course directory rather
  than from anywhere beside the app, and the partial list is refused whole
  with nothing written. The three tools (`read_remembered_timetable`,
  `plan_remember_timetable`, `remember_timetable`) are dispatched in
  `Models/Assist/AssistToolRunner.swift`; pinned by
  `Tests/QuartzTeachersTests/SectionTimetableTests.swift`. Spec entry 145.


- **Four new operations, all shared C# in `Plantoir.Core`** (Windows +
  shared, 2026-08-14). Nothing mac-specific except the UI that reaches them;
  the mac inherits the logic if it ports `AssistWorkspace`.

  - **Placeholder class pages** (`638d5d7`) — "add seven days to the next
    unit". Lands on the section's own meeting dates, skipping days an
    existing class already sits on, so a reshuffled course still gets the
    right answer. Pages start `publish: false`. Never overwrites, checked
    twice: at plan time and again at write time, because Obsidian is open in
    the other window. **✅ DONE (macOS, 2026-08-15)** —
    `Models/PlaceholderClassPlanner.swift`, landing on the section's
    remembered meeting dates and skipping days already taken, pinned by
    `Tests/QuartzTeachersTests/ClassPlanningTests.swift`.
  - **Insert a class and push the rest back** (`b913f85`) — the one a teacher
    called "a huge hassle". Later days of the SAME unit are renamed; every
    class after the insertion point, later units included, moves to a later
    meeting day and keeps its name. Renames run **highest day first** or they
    overwrite a real lesson. Titles inside the files follow the file names.
    **Links are rewritten by us, not by Obsidian** — Obsidian only does that
    when Obsidian performs the rename; a rename on disk from another process
    reads to it as a delete plus a create. All wikilink forms are handled
    (`[[P]]`, `[[P|alias]]`, `![[P]]`, `[[P#Heading]]`, `[[P#^block]]`);
    Markdown-style links are NOT, and that is written down rather than
    discovered. **✅ DONE (macOS, 2026-08-15)** —
    `Models/ClassInsertionPlanner.swift` with `Models/WikiLinkRewriter.swift`
    for the five wikilink forms, renaming highest day first, same
    `ClassPlanningTests.swift`.
  - **Curriculum expectations for a page** (`e5a01ed`) — the tools find the
    expectations and read out their full wording; the MODEL decides which fit,
    because that is a judgement about meaning. Transclusions go inside the
    `%%curriculum-start%%` markers, or a course installed without curriculum
    would keep a dangling reference on a live site. **✅ DONE (macOS)** —
    `Models/Assist/AssistCurriculumMentions.swift`, served on the **MCP
    surface only**. The local surface is a MEASUREMENT — routing accuracy was
    counted against exactly the tools a teacher asks for, fifteen of them at
    the time — so the curriculum tools are never added to it. Counted
    2026-08-15: `AssistToolSurface` defines **twenty** tools;
    `AssistToolRunner.definitions` narrows to the **thirteen** the local model
    is shown (the six `plan_` twins are called in code, and
    `remember_timetable` is withheld because a date the model invents silently
    schedules the wrong day); and `AssistToolRunner.mcpTools` is the
    **twenty-three** `AssistMCPServer` serves — the twenty plus three
    MCP-only curriculum tools. The numbers move when something is measured
    again, not casually.
    A page with no markers gets the whole block in the payload shape —
    `%%curriculum-start%%`, `## Curriculum connection`, blank-line separated
    `![[A1.2]]`, `%%curriculum-end%%` — placed before the things-to-do list
    when there is one.
  - **Scheduled deploys** (`935ad9f`, `ad020d3`, `4400f80`) — see the next
    entry; the Windows half is `schtasks`.


- **Scheduled deploys — the mac needs launchd** (Windows, 2026-08-14). "Deploy
  tomorrow's class at 6:30 AM." Windows uses `schtasks` to run
  `deploy.ps1 <CODE> <N>` at a set time; the mac equivalent is a launchd
  agent running `deploy.sh`. The decision of *whether* to schedule, and every
  word the teacher reads, is already in `Plantoir.Core`
  (`ScheduledDeploy.Problem`) — only the last step is platform-specific.

  Points that cost something to learn:

  - **It must fire with nothing of ours running.** Verified: a task fired
    unattended, started WSL from cold, reached Docker, with Plantoir closed.
    The teacher's *Go ahead* consents to setting the alarm, not to the deploy.
  - **No wake timer, deliberately.** Waking depends on hardware and power
    settings and fails SILENTLY; the plan states the conditions instead (on,
    awake, plugged in, lid open). A warning a teacher can act on beats a
    promise that might not be kept.
  - **Refuse what would ASK a question.** A Cloudflare course (needs the
    account ID only the app has) and a section never deployed (`deploy.py`
    asks what to name the site) are both declined AT SCHEDULING TIME.
    Attended, those fail in front of the teacher; scheduled, they wait on a
    prompt at half six with nobody there.
  - **One per section, by construction** — the task name is fixed per section,
    so scheduling replaces. Verified: scheduled twice, still one task.
  - **Visible, or it may as well not exist.** A clock sits beside the section
    in the sidebar with the time in its tooltip, and the context menu offers
    "Schedule Deploy…" or "Cancel Deploy at 6:30 AM…" — one or the other,
    never a greyed-out line teaching teachers to stop reading the menu.
    **Ask the OS, do not keep a note**: the teacher can delete the task
    themselves, and a badge promising a deploy that will never happen is worse
    than no badge.

  **✅ DONE (macOS).** `Models/ScheduledDeploy.swift` writes a launchd user
  agent into `~/Library/LaunchAgents`, loaded with `launchctl bootstrap
  gui/<uid>` and removed with `bootout` — not the deprecated `load`/`unload`.
  Label is `ca.russellgordon.Plantoir.deploy.<CODE>.section<N>`, so two
  sections cannot collide and scheduling replaces rather than stacks. The
  plan/apply pair is `plan` (changes nothing) and
  `scheduleDeploy`/`cancelScheduledDeploy`. Sidebar clock, tooltip and the
  either/or menu item are in `SidebarView`; the picker is
  `Views/Section/ScheduleDeploySheet.swift`.

  Four places the mac differs, deliberately:

  - **No zombie agent.** `StartCalendarInterval` has no year, so a fired
    agent would come round again in twelve months. The job removes its own
    plist FIRST (a Mac restarting mid-deploy comes back with nothing
    pending) and `bootout`s itself LAST. `nextRun` also ignores an agent
    whose moment has passed.
  - **Cloudflare IS schedulable here.** The refusal on Windows is an
    argument-passing limit, not a policy: the plist carries `--account`, so
    the question is asked in the app and answered once. It is still refused
    when the Account ID is missing.
  - **launchd does NOT silently skip a missed job** — it runs it at the next
    wake. So the plan says that, rather than Windows's "nothing happens".
  - **The agent runs `deploy.sh` only**, as on Windows, so what goes out is
    the site as it was last BUILT. The plan says so and asks the teacher to
    preview again after later edits.

    **Superseded (macOS, 2026-08-15) — it builds first now.** The agent
    writes the staleness test (`BuildFreshness.needsRebuild`) out in shell,
    because the app is closed when the alarm fires and cannot be asked, then
    runs `preview.sh <CODE> <N> --build-only` and only then `deploy.sh`
    (`Models/ScheduledDeploy.swift`). This was not a nicety: `deploy.sh`
    never builds and **refuses outright when there is no built site**, so an
    agent running it alone either failed at half six or sent whatever was
    last previewed. **Windows should mirror this** — its `schtasks` job has
    the same gap. Spec entry 146.

  Pinned by `Tests/QuartzTeachersTests/ScheduledDeployTests.swift` (23 tests),
  which never touches the real launchd: the agents folder is redirected to a
  temporary one and `launchctl` is behind `LaunchControlRunning`. **Still
  wanted: one live run** — schedule a section a few minutes out, quit
  Plantoir, and check the site and `~/Library/Logs/Plantoir/<label>.log`.


- **The built-in assistant, and what it cost** (Windows, 2026-08-14). A local
  model in a window of its own, reached from "Revise with AI…" on both the
  course and every section menu. **Read
  [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 2 before building the mac
  equivalent** — it is the full account of what worked and what did not, with
  the measurements. The headlines that will bite whoever ports it:

  **✅ DONE (macOS, 2026-08-15).** Built as `AssistWindowView` +
  `AssistSession` + `AssistAgent`, reached from "Revise with Local AI
  Assistant…" on a
  section's context menu, one window per section. The engine is native
  llama.cpp with Metal rather than a container — 175 s → 2.1 s on the same
  model and prompt. Model tier chosen from the Mac's memory.

  - **Fewer tools is better routing AND a shorter prompt.** 34 tools is 9,032
    tokens; at ~21 tokens/second on two cores that is 430 seconds of reading
    before a first answer. The local model sees 15.
  - **A warm-up must prime the SAME prefix a real turn uses**, system message
    included, or it caches something no conversation asks for. Measured: 1.8s
    versus 29.6s for the identical turn.
  - **Colima may or may not idle out the way WSL2 does.** On Windows a
    detached container dies ~25 seconds after nothing holds the distro open,
    and the app now holds a session open for the conversation's life. Whether
    Colima behaves the same is **unknown and worth checking early** — the
    symptom is an HTTP error that looks like a network fault and is not.
  - **Withholding a tool is not a safety mechanism.** Deploy was trimmed out
    for speed and silently removed a capability the teacher had asked for by
    name. The approval gate — every non-read-only tool waits for a button,
    decided from the server's own `readOnlyHint` — is the safety mechanism.


- **The MCP server must SHIP with the app** (Windows, 2026-08-14, `b211b13`).
  `publish.ps1` never built `Plantoir.Mcp`, so the bundle contained no
  `plantoir-mcp.exe` and the whole feature would have shipped dead — on a
  teacher's machine only. It is now built, copied beside the app and signed
  with it. Keep them separate binaries: Claude Code launches the server
  itself as a stdio subprocess, so it has to stay a plain console app.

  **✅ DONE (macOS, 2026-08-15) — and cannot recur here.** This is exactly
  why the macOS server is the app rather than a second binary: there is no
  packaging step that can forget to build it, and it is signed with the app
  because it IS the app. Worth considering on Windows if `plantoir-mcp.exe`
  ever goes missing from a bundle again.


- **The publication flag is `publish:`, not `draft:`** (Windows +
  shared, 2026-08-13, `ai-assist` branch). Commits `2d6c59a` (the
  toolchain and the app) and `7347d2b` (the example content and the
  course-creation wizard). Same caveat as the AI Assist entry below:
  **this lives on `ai-assist`, not `main`, and is not in 1.0.**

  > **Branch note, verified 2026-08-14 (macOS side):** `ai-assist` is now an
  > ANCESTOR of `origin/main` — `git merge-base --is-ancestor origin/ai-assist
  > origin/main` succeeds, and `Plantoir.Mcp` and the assist documents (now merged into
  > `research/ai-assist/HISTORY.md`) are all present on `main`. The "not on `main`" caveats
  > below were true when written and are not any more; nothing needs merging
  > to reach this work.

  **✅ DONE (macOS + shared, 2026-08-14, `b2a4c0bf`).** Completed across the
  shared content the Windows change had not reached: 5,968 payload pages,
  108 EXC2O course-level pages, 1,944 skeletons, and the skeleton generator
  so a regeneration cannot reintroduce the old key. Two further defects
  came out of it — `per_section_frontmatter` left 493 shared pages UNSPLIT
  because it matched only `created`/`draft`, and the coverage map's own
  `_is_draft()` counted a `publish: false` page as published. The payload
  linter now rejects `draft:` outright. See spec entry 141.

  A page inside `section<N>/` now carries `publish:`; a course-level page
  carries `publishForSection<N>:`. Both are the OPPOSITE polarity from
  the keys they replace — `draft: true` becomes `publish: false`.

  **The shared half is done and the mac inherits it**, so read this
  before assuming the mac has to do anything drastic:

  - `build_site.py` maps `publishForSection<N>` → `publish` for the
    section being built, falls back to the legacy `draftSection<N>` /
    `draft` **inverted**, and strips all four key families from the
    built copy. A course nobody has touched builds exactly as it did.
  - `patches/publish.ts` gives Quartz a `PublishFlag` filter, and
    `build_site.py` rewrites `Plugin.RemoveDrafts()` to `Plugin.PublishFlag()`
    in `quartz.config.ts`. **Do not reach for Quartz's own
    `ExplicitPublish` instead** — it looks like exactly what we want and
    it is a trap. It reads `publish === true`, which flips the DEFAULT,
    and 60 of the sample course's 225 pages carry no flag at all,
    every curriculum page among them. All of them would have vanished
    silently. `PublishFlag` is eight lines that keep the forgiving
    default and change only the word.
  - `setup_course.py` creates new courses in the new schema.

  **What the mac app owes**: the same reading and writing of the new
  keys, in whatever its counterpart to `PageFrontmatter` is. Three rules
  matter, and each one is there because breaking it caused a real bug:

  1. **Read new-then-legacy, and invert the legacy value.** Per-section
     key first, plain key second, then `draftSection<N>`, then `draft`.
     No key at all means PUBLISHED.
  2. **Never write a legacy key.** Writing the new key is the migration,
     and it happens one page at a time as things are edited. There is no
     sweep and no flag day.
  3. **Write the new key in the OLD key's position**, so a migrated page
     shows a one-line diff instead of reordered frontmatter in a file
     Obsidian may have open.

  Watch for the inversion bug, because it is subtle and it bit three
  times here: any variable meaning "is this page hidden" must not be
  fed the raw `publish` value. All three instances were caught by tests
  that already existed — a plan that thought published pages still
  needed publishing, a dangling-link check that found nothing in either
  direction, and a transition line that told the teacher the exact
  reverse of the truth. Reference: `PageFrontmatter.IsDraft` /
  `StoredDraft` / `SetDraft` in
  `windows-app/Plantoir.Core/Models/PageFrontmatter.cs`.

  The example content in `support/` was inverted wholesale (1145 keys
  across 957 files), including the prose that teaches the flag, so the
  mac gets that for free. Verified against a real container build: a
  course with a page for every branch — `publish` true/false/absent/
  quoted-false, legacy `draft` both ways, and per-section keys set
  OPPOSITE for two sections — built correctly in all fourteen cases,
  with section 2's site the exact mirror of section 1's.


- **"Deploy" comes back to the GUI — this REVERSES row 103** (Windows,
  2026-08-13, `ai-assist` branch, commit `ba4889c`). Row 103 had the mac
  drop "Deploy" as jargon and call the button "Publish". That has to be
  undone, and not because row 103 was wrong: it was right when there was
  only one act to name. There are two now. A page is **published** when
  students can see it in the built site (the `publish:` flag above, which
  the assistant changes); the whole site is **deployed** to Netlify,
  Cloudflare, or a folder (the teacher's own act, which the assistant
  never takes). One word for both makes "I published tomorrow's class"
  mean a flag to one party and a live site to the other.

  **✅ DONE (macOS, 2026-08-15).** 24 strings across 14 files, following the
  same rule: the SITE is deployed, a PAGE is published. Internal names kept
  their spelling, including every automation id, so no launcher, config key
  or UI test moved. One judgement beyond the Windows sweep: the Netlify
  failure messages ("Try publishing again" after a failed deploy) were swept
  too, since that sentence is exactly the confusion being fixed — flagged
  here in case Windows wants to match. See spec entry 143.

  On Windows the sweep covered: the toolbar button and its tooltip, the
  No Preview Running invitation, the progress title, the Publishing
  settings group (now "Deploying") and its "Deploy to" picker, the
  Cloudflare and folder problem dialogs, the busy lines in
  `CourseActivity.BusyReason`, and the folder-copy completion note.
  **Internal names deliberately keep their spelling** — `deploy.ps1` /
  `deploy.sh`, `deploy_target`, `deploy_folder_path`, the `deployButton`
  automation id — so nothing in the launchers or the config format
  moves. Also worth copying: the assistant's plan says "Unpublish", not
  "Hide", since hide/unhide is not a teacher's word.


- **AI Assist — an MCP server, on the `ai-assist` branch** (Windows +
  shared, 2026-08-13). Commits `c6b1381` (the feasibility investigation
  and its evidence) and `b3b7fc0` (the server). **Nothing here is on
  `main`, and none of it is in 1.0** (see the branch note above — this is
  no longer accurate) — the branch exists so this can be
  folded into a later release or dropped without touching the impending
  release. Read [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 1 first for the measurements,
  then [`windows-app/Plantoir.Mcp/README.md`](windows-app/Plantoir.Mcp/README.md)
  for the tool surface and the reasoning behind its shape.

  **✅ DONE (macOS, 2026-08-15), by a different route.** Rather than a
  separate executable, the app itself answers `--mcp-stdio <folder>` and
  serves the same `AssistToolSurface` over JSON-RPC. Verified by handshake:
  `initialize` and `tools/list` return `runner.mcpDefinitions` whole, with
  their schemas and `readOnlyHint` annotations — 15 tools when this was first
  verified, 23 when re-counted 2026-08-15. Same surface, two clients, no drift possible
  — and see the note on the entry below for why this route was taken.

  **What exists.** `plantoir-mcp`, a stdio MCP server over one working
  folder, built on the official `ModelContextProtocol` 2.2.0 C# SDK. Eight
  tools: four read-only, two planning tools that change nothing, and two
  writes that back up first. Verified end to end over real JSON-RPC against
  the sample course — including a publish that flipped one section's
  per-section key while leaving the other section's untouched, with the
  backup written first. (Those keys were `draftSection<N>` at the time;
  they are `publishForSection<N>` now — see the publication-flag entry
  at the top of this file.)
  Plan logic is unit-tested against a fake launcher; the suite is at 200.

  **The mac side inherits most of it.** The platform-neutral logic lives in
  `Plantoir.Core` (`Assist/AssistWorkspace.cs`, `Assist/PublishPlan.cs`,
  `Models/PageFrontmatter.cs`, `Models/PagePaths.cs`, `Models/WikiLinks.cs`)
  and the launcher call is abstracted behind `ILauncherRunner`, which picks
  `deploy.ps1` or `deploy.sh` by platform. The csproj already lists
  `osx-arm64` and `osx-x64`. **In principle `dotnet publish -r osx-arm64`
  is the entire mac port.**

  **The Phase 0 question is still open, and it is yours.** Is the mac side
  willing to ship a .NET-published binary beside (or inside) the app? If
  yes, one implementation serves both platforms and every behaviour is
  written and tested once. If no, `Plantoir.Mcp/README.md` is the spec a
  Swift implementation should follow — but please keep the four safety
  rules exactly, because each one is a measured failure and not a
  preference:

  1. *No destructive tool exists.* The model declined "delete the Unit 1
     folder" because it had **no tool for it**, not from judgement.
  2. *Publish and hide are separate tools, never one tool with a boolean.*
     Asked to hide a page, the model called publish with "include linked"
     set — on some runs and not others.
  3. *Every named entity is validated against disk*, and a miss is a
     refusal naming what does exist. Asked to "clean up my course", naming
     no course, it invented `MCV4U`.
  4. *Every write backs the course up first and has a `plan_` twin that
     changes nothing.* Row 106 closing its own loop.

  **Two things the mac side should sanity-check**, because they were
  reasoned from shared code rather than tested on macOS: that
  `Path.GetRelativePath`-based containment behaves as expected on a
  case-insensitive-but-case-preserving APFS volume, and that the launcher
  runner's `/bin/sh` invocation of `deploy.sh` inherits the environment
  Colima needs.

  **A shared-launcher change rode along with this, and it is worth taking
  even if the mac passes on everything else.** `preview.sh` and `deploy.sh`
  used `docker exec -it` unconditionally. `-t` **refuses to start** when
  stdin is not a terminal, so any non-interactive run — a script, CI, an
  MCP server — died at that line, *after* several minutes of Docker build,
  saying only "the input device is not a TTY". (`verify.sh:69-75` has
  refused up front for this reason for ages; that guard is now
  unnecessary.) Both scripts now ask for a terminal only when there is one
  and run Python unbuffered when there is not, so progress still arrives
  line by line instead of in one lump. **The interactive path is
  byte-identical in behaviour**, so the mac GUI — which supplies a terminal
  through `PseudoTerminal.swift` — is unaffected. Verified on Windows end
  to end; the shell edit is the same two-line shape and wants a quick
  confirmation on macOS.

  **Known gap, shared design needed.** The server cannot see the GUI's
  in-flight previews or publishes and vice versa — `CourseActivity` and
  `PreviewLeases` are in-process on both platforms. Overnight this is moot;
  daytime overlap could corrupt a build. The v2 answer is a lease file
  under the working folder that both apps and the server honour, which
  **both sides would have to adopt**. Worth agreeing on the file shape
  before either side writes it.


- **Cloudflare Pages as a third publishing destination** (Windows +
  shared, 2026-08-12). Commits `0306c98` (container side), `4575647`
  (account fallback), `e6611cc` (Windows UI). **The shared half is
  already done and the mac inherits it** — `scripts/deploy.py` and the
  `Dockerfile` are common to both apps. The mac side needs two things:
  `deploy.sh`, and the GUI.

  **What already works, in shared code.** `deploy.py --target cloudflare`
  discovers the account, creates or reuses this section's Pages project,
  hands the built folder to wrangler, and prints `Live URL: https://…` —
  the label both apps' parsers already read, so no parser change was
  needed on either side. Per-section state lives in
  `courses/<CODE>/.cloudflare_sites/section<N>.json`, deliberately
  mirroring the existing `.netlify_sites/` marker.

  **Design decisions, and why — please keep these rather than re-deciding:**

  1. *Publishing rides on wrangler, not a reimplementation.* Cloudflare's
     direct-upload protocol is multi-stage and undocumented: BLAKE3 hashes
     computed over base64-of-contents plus the file extension, a
     short-lived upload JWT that can expire mid-upload on a large site,
     and batched asset uploads. Community write-ups exist, but a
     reimplementation would break teachers' publishing silently whenever
     Cloudflare changed it. wrangler is Cloudflare's own supported
     implementation and already handles those edges.
  2. *wrangler is pinned at 4.80.0 — and pinned BELOW 4.100 on purpose.*
     From 4.100 wrangler requires Node 22; the image ships Node 20 because
     that is what Quartz v4.5.0 is known-good against. Raising Node to
     chase a newer CLI would mean revalidating every teacher's site build.
     Install and `--version` were verified on `node:20-slim` before
     committing. **If you bump Node, revisit this pin — and revalidate
     Quartz first.**
  3. *A token scoped to Pages CANNOT list its own account.* This was
     found by testing a real token: `/user/tokens/verify` reports
     `active`, while `/accounts` returns success with an EMPTY list and
     `/memberships` returns 403. The first cut treated "no accounts" as
     "bad token" and would have sent teachers off to re-mint a perfectly
     good one. **Validity and account lookup are now separate questions**
     — validity against `/user/tokens/verify`, the account by discovery →
     remembered value → asking. Please do not collapse them again.
  4. *Because of (3), the account ID must be collected in the GUI.* The
     app publishes with nothing attached that can answer a console
     prompt, so the launcher's prompt is unreachable from the GUI. On
     Windows it is a field in the Publishing section, validated live (32
     hex characters) with Save/Create gated on it, and passed to the
     launcher as `--account`. It is stored in **app settings, not course
     settings**, because it identifies the teacher rather than the course
     — the same reasoning that puts the token in the OS keychain — so it
     is entered once and used by every course.
  5. *The 25 MB per-file cap is checked before anything uploads.*
     Cloudflare refuses larger files, and the failure otherwise surfaces
     from deep inside the upload as an unhelpful error. `deploy.py` lists
     the offending files by name and suggests compressing the video or
     publishing that section to Netlify, which allows larger files. This
     is the one real functional difference between the destinations and
     is worth saying plainly in the mac UI too.
  6. *Tokens are stored under separate keychain entries.* A teacher
     publishing some courses to Netlify and others to Cloudflare keeps
     both, and `--reset-token --target cloudflare` clears only the
     Cloudflare one (plus its remembered account).

  **What the mac side must write.** `deploy.sh` needs the `--target`
  and `--account` flags, its own keychain entry for the Cloudflare token
  (plus one for the remembered account ID), token validation against
  `/user/tokens/verify`, and the same env hand-off into the container:
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, with
  `--target cloudflare` passed to `deploy.py`. **`deploy.sh` was left
  deliberately untouched on the Windows side** — shipping an edit to a
  launcher that could not be tested here would be worse than shipping
  none. GUI-wise: the third picker option, the account field with live
  validation, the milestone list (never saying "Netlify" — pinned by a
  test on Windows), and a decline path if the account is missing.
  Reference: `windows-app/Plantoir/Views/PublishingChoiceView.cs`,
  `SectionDetailView.xaml.cs` (`Deploy_Click`),
  `Plantoir.Core/Scripting/TaskMilestones.cs`,
  `CourseConfiguration.CloudflareAccountProblem`.

  **Status: PUBLISHED END TO END and working** (Windows, 2026-08-12).
  MCV4U Section 1 from a real workspace went live at
  `mcv4u-s1-2026-gordon.pages.dev` (HTTP 200, correct Quartz title),
  driven from the app's Publish button, not a script. Observed:

  - First publish ~140 s including the one-off toolchain image rebuild;
    a second publish ~23 s, reusing the project rather than creating a
    second one (exactly one project in the account afterwards).
  - The progress bar tracked "Step 8 of 8" through the
    `BuildAndDeployToCloudflare` list, and the completion panel showed
    "Your website is live" with the clickable pages.dev link — the
    Netlify live-link panel works unchanged, because `deploy.py` prints
    the `Live URL:` label the parser already reads.
  - The marker file came out as intended:
    `{name, id, subdomain, account_id}`.

  **The build-counter question is settled, empirically.** The deployment
  record for a Direct Upload reports `deployment_trigger.type: ad_hoc`
  and its stages come back `clone_repo=idle, build=idle, deploy=success`
  — **no Cloudflare build runs**, so the free plan's 500-builds-per-month
  limit does not apply to how Plantoir publishes. A teacher republishing
  many times a day across several classes is in no danger of it. (The
  limit is documented as applying to builds triggered by a git push,
  which this path never does.) Worth not re-investigating on the mac.

  Remaining unknown: behaviour at the 25 MB per-file cap has still only
  been checked by the pre-flight guard in `deploy.py`, not by actually
  pushing an oversized file.

  **Mirror the standing size note too** (`8883ad9`). Whenever Cloudflare
  is the chosen destination, the Publishing section shows a permanent
  orange line — not the validation warning, which comes and goes, but a
  fact about the destination that never hides:

  > One thing to know: Cloudflare won't accept any single file larger
  > than 25 MB. Documents, images, and slide decks are almost always
  > comfortably under that — a long video usually isn't. Most teachers
  > embed video from YouTube or Vimeo rather than uploading it, which
  > avoids the limit entirely.

  This is the one real functional difference between the destinations, so
  a teacher should meet it while choosing rather than when a publish
  fails. The grey caption deliberately no longer repeats it.

  **✅ DONE (macOS).** Both halves the mac owed.

  `deploy.sh` gained `--target netlify|cloudflare` and `--account <ID>`,
  its own Keychain entries (`containerized-quartz-cloudflare` and
  `containerized-quartz-cloudflare-account`, separate from the Netlify one
  so a teacher keeps both), validity against `/user/tokens/verify` kept
  SEPARATE from the account lookup exactly as decision (3) asks, the
  account resolved `--account` → discovery → remembered → ask, and the same
  env hand-off into the container: `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`, `--target cloudflare` to `deploy.py`.
  `--reset-token --target cloudflare` clears only the Cloudflare pair. The
  token now lands at `/tmp/deploy_pat` rather than `/tmp/netlify_pat`,
  since either token rides the same way.

  GUI: `PublishingChoiceView` is now a three-way picker (`netlify` /
  `cloudflare_pages` / `local_folder` — the same spellings Windows writes,
  since the file is shared), with the Account ID field, live 32-hex
  validation via `CourseConfiguration.cloudflareAccountProblem`, and the
  permanent orange 25 MB note. The ID is in `Models/AppSettings.swift`
  (app settings, not course settings), matching the Windows reasoning.
  Save and Create are gated on it; the Deploy button refuses BEFORE any
  building, with the same "under Deploying" wording. Milestones
  `deployToCloudflare` / `buildAndDeployToCloudflare` never say "Netlify",
  and the `Live URL:` parser needed no change, as promised.

  New: `Models/DeployCommand.swift` is now the single place that decides
  what `deploy.sh` is asked to do. Both the Deploy button and the scheduled
  agent read it, so a scheduled deploy cannot quietly go to the wrong
  destination.

  Pinned by `Tests/QuartzTeachersTests/CloudflareDeployTests.swift`.
  **Still wanted: one live Cloudflare deploy from the mac**, the way
  Windows verified MCV4U — nothing here has yet met a real token.


- **`sanitize_last_name` folds accents instead of dropping them**
  (shared, 2026-08-12, commit `0306c98`). Pre-existing bug in
  `scripts/deploy.py`, found while testing Cloudflare project naming: the
  function kept only `a-z`, so a teacher named **Côté** got `ct` in her
  site name and Müller got `mller`. In an Ontario staff list that is not
  an edge case. It now normalises (NFKD) and strips combining marks
  first, so Côté → `cote`. **This affected Netlify site names too**, and
  the mac inherits the fix automatically since `deploy.py` is shared —
  no mac code needed, but worth knowing the suggested names changed.
  Existing sites are pinned by their marker files and are unaffected.

  **✅ DONE (shared).** Already present in `scripts/deploy.py` on this side —
  arrived with the merge and verified: `Côté` → `cote`, not `ct`.


- **About box credits match plantoir.app's footer** (Windows, 2026-08-11).
  The credits section is now: a rounded-rect callout carrying the full
  sponsor message ("Plantoir is a friendly wrapper around [Quartz], which
  Jacky Zhao builds and gives away for free. If you end up using Plantoir
  regularly, please consider [sponsoring him on GitHub] — it is his work
  that makes all of this possible."), then three plain acknowledgement
  lines: "Icon from [Phosphor Icons] (MIT)." / "Designed by
  [Russell Gordon]." / "Made with Claude." — links to quartz.jzhao.xyz
  and github.com/sponsors/jackyzha0 (in the callout), phosphoricons.com,
  russellgordon.ca. No "Built on Quartz" line: the callout already says
  whose work this stands on. (Replaces the old one-line "Please sponsor
  Jacky" credit; plantoir.app's footer matches.) Also: the
  plantoir.app/support row is REMOVED from the Windows About — help is
  coming into the app itself — leaving Email as the only contact row;
  drop the mac About's Support row to match. Mirror in the mac About
  window. Reference: `windows-app/Plantoir/Views/AboutDialog.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 107.


- **Preview builds are never deploy-fresh** (from `94e25f8`, 2026-08-11).
  Deploying right after previewing published the preview's build, whose
  pages carry Quartz's live-reload client (`new WebSocket('ws://localhost:…')`)
  — so the PUBLISHED site knocked on every visitor's localhost and
  Chromium-family browsers prompted "wants to access other apps and
  services on this device" on first load. The shared `scripts/deploy.py`
  now detects the client and re-emits a production build before
  uploading, which already protects the mac app functionally — but the
  mac app's own deploy-freshness check shares the Windows one's blind
  spot (it compares only content dates). Mirror the Windows fix so the
  app's ordinary, visible build-first step runs instead of the silent
  in-deploy rebuild: a built `public/index.html` containing
  `ws://localhost:` is never fresh. Reference:
  `windows-app/Plantoir.Core/Models/BuildFreshness.cs`
  (`BuiltForPreview`) and the `APreviewBuildIsNeverDeployFresh` test in
  `windows-app/Plantoir.Tests/ModelTests.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 108.


- **Font samples show the course's own computed site title** (Windows,
  2026-08-11). The header font sample renders the title the build will
  actually produce — `[Grade X ]Name[, Section N]`, i.e. the course name
  with the grade and section-marker switches applied — in the candidate
  typeface, updating live as the name, code, section numbers, or either
  toggle changes. The "Grade 11 Computer Science" stand-in remains only
  while the form is blank; the body-sentence sample is unchanged. In
  Course Settings each section's sample uses that section's own toggles.
  The compute is `CourseConfiguration.ComputedSiteTitle` (Core),
  mirroring `computed_landing_title` in `scripts/build_site.py` and
  pinned by a six-case theory test. Mirror in the mac wizard's
  FontChoiceEditorView and Course Settings. References:
  `SampleHeaderText()` in `windows-app/Plantoir/Views/NewCourseDialog.cs`
  and `windows-app/Plantoir/Views/CourseSettingsView.xaml.cs`;
  `ComputedSiteTitleMatchesTheBuild` in
  `windows-app/Plantoir.Tests/CourseConfigurationTests.cs`.

  **✅ DONE (macOS, 2026-08-12).** Already on macOS as spec entry 100.


- **Explain a disabled Create button in the wizard** (from `2d10e4c`,
  2026-08-11). On Windows, a filled-in New Course form with a DUPLICATE
  course code left Create greyed with no explanation — the sections
  field explained its problems inline while the code field stayed
  silent. Windows now shows the reason under the code field ("A course
  named ICS4U already exists — choose a different code."), single-sourced
  with the check that gates the button. Worth checking whether the mac
  wizard has the same silent-disable and wants the same inline
  explanation. Reference: `CourseCodeProblem()` / `RefreshCodeValidation()`
  in `windows-app/Plantoir/Views/NewCourseDialog.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 109.

- (Earlier Windows work — About credits + Support-row removal, the
  preview-build deploy-freshness check, the computed-title font samples,
  and the live code-field explanation — was picked up on 2026-08-12;
  spec entries 107–109 record those mirrors.)


- **Worth checking: the same test race may exist on the mac**
  (`3bbb1a7`, 2026-08-13). A Windows test failed about one run in three
  with a baffling null. The cause was not the production code: preview
  leases and the publish registry are **process-wide statics**, the test
  runner runs test classes in parallel, and the lease-tests class reset
  that shared state around every one of its methods — wiping the lease
  another class was mid-assertion on. Fixed by putting both classes in a
  serialized collection. If the mac's tests around `CourseActivity` /
  preview leases share process-wide state and run in parallel, the same
  intermittent failure is possible there; it is the kind that gets
  written off as "flaky CI" for months. Worth ten minutes to check.

  **✅ DONE (macOS, 2026-08-16) — checked, and the mac is not exposed.** The
  test target is `parallelizable = "NO"` in the scheme, so XCTest runs these
  classes one at a time and the shared statics cannot be reset under another
  class mid-assertion. **The safety is a scheme setting, not a property of the
  tests**: `PreviewLeaseTests` and `CourseActivityTests` both call
  `PreviewLeases.reset()` / `CourseActivity.reset()` around individual methods,
  so turning parallel testing ON would introduce exactly the Windows failure —
  one run in three, a baffling null, and months of being written off as flaky.
  If that setting is ever flipped, put these classes in a serialised group
  first.

- **Align Windows Local AI Assistant brevity and concise responses with macOS**
  (Windows, 2026-08-17). Windows assistant responses were adjusted to match the
  crisp, informative single-sentence outputs on macOS.
  1. Removed `plan_` tools from `ForTheLocalModel` narrowing — plan mode is handled
     directly by code rather than by the model schema.
  2. Updated `AssistWorkspace.Summary()` to return clean past-tense sentences ("Published “Unit 2, Day 3”." / "Nothing needed changing.") rather than multi-clause paragraphs.
  3. Set `temperature: 0` in `LocalModel.Ask()` for deterministic tool routing.
  4. Updated tool approval line in `AssistAgent.Run()` to use `AssistWording.DeployApproval` / `AssistWording.DeployQuestion`.
  
  **✅ DONE (Windows, 2026-08-17).** Recorded in GUI improvement log row 263. All 479 tests passing.
