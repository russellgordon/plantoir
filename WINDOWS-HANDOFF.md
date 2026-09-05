# Windows App — Handoff

> **New to this side? Read [`WINDOWS-BOOTSTRAP.md`](WINDOWS-BOOTSTRAP.md)
> first.** It says what to read, what to do in what order, and asks you to
> outline the plan before implementing. This file is the reference it sends
> you to.

Read this first when working on the Windows app — `windows-app/`, WinUI 3,
first take built 2026-08-11 — and especially when syncing it after a run of
macOS-side sessions. It gathers everything a Windows implementation needs; the
deep dives it links to are kept current. **Do not work through it top to
bottom.** Start with "Where Windows actually stands" immediately below for the
genuinely outstanding work, and use `GUI-IMPROVEMENTS.md`'s **Windows status**
section for the per-entry detail behind it.

**A large amount of what used to be tracked here has shipped.** This file was
pruned on 2026-08-22 after a code-level pass (not just a read) confirmed that
most of the work an earlier "ordered work list" described as outstanding is
now actually in `windows-app/` — contracts wired into `Plantoir.Tests`, the
deploy-approval wording, the preview-stop-before-deploy await, the activity
trail, the problem report dialog and redactor, `add_next_class` /
`plan_remember_timetable`, the `LinkGraph` exclusions, `assistantConfirmation`,
the `ReDatePlan` overflow fix, the schedule-asking flow, course renaming, the
native (non-container) local model, the assistant-choice Settings panel, the
credential dialogs, `AutoFillCourseName`'s `names.Short` fix, the Curriculum
Coverage explainers toggle, subject skeletons, and `SectionAdder`'s
course-level page extension. Those write-ups have been moved verbatim to
[`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md) — read them
there if you need the reasoning behind something that already shipped; this
file now holds only what is still genuinely open, plus reference material that
was never a task in the first place.

## Where Windows actually stands (read from the code, 2026-08-22)

**Read this before planning.** `WINDOWS-BOOTSTRAP.md` § 0 asks you to write a
plan before touching anything, and a plan needs to start from what is TRUE on
this side rather than from what the rest of this file describes. **If you find
one of the items below already done, or one of the "done" claims above wrong,
that is a defect in this section** — say so in `MAC-HANDOFF.md`, the same way
this side is expected to say so when the contract is wrong.

### What is still genuinely outstanding

1. ~~A Preview item in a menu bar~~ — ✅ Done 2026-08-22. `MainWindow.xaml`
   gained a top-level "Preview" menu (Back / Forward / Reload Page) between
   File and Help, mirroring `mac-app/QuartzTeachers/App/PreviewCommands.swift`.
   It tracks whichever `SectionDetailView` is currently shown in `DetailHost`
   via a `PreviewChromeChanged` event (raised at the end of `RefreshChrome`)
   rather than polling, and enables/disables exactly as the toolbar
   Back/Forward/Reload buttons already did. **The shortcuts are also truly
   global, matching mac's ⌘[/⌘]/⌘R** (a first pass shipped the menu with
   display-only accelerator text and left this as a known gap; fixed the same
   day once flagged): `MainWindow`'s root Grid now declares its own
   `Ctrl+R`/`Alt+Left`/`Alt+Right` `KeyboardAccelerator`s, identical in
   combo to the pre-existing ones scoped to `SectionDetailView`'s own Grid.
   WinUI 3 resolves a duplicated combo by bubbling from the focused element
   up the visual tree and invoking the first one found — confirmed against
   Microsoft's own "Resolving accelerators" documentation, not assumed — so
   the section-scoped accelerator wins whenever focus is inside the preview
   (and no-ops there without marking the event handled when its guard, e.g.
   `Preview.CanGoBack`, is false, letting the root-level one take over), and
   the root-level one fires from anywhere else (sidebar, path bar). No
   duplicate-registration exception, no double `Reload()` from this scoping.
   Two adversarial sub-agent reviews confirmed this in sequence: the first
   pass (build clean, no leaked `PreviewChromeChanged` subscriptions across
   repeated `DetailHost.Content` swaps, no null-ref risk against a torn-down
   `WebView2`, no collision with `Ctrl+Shift+R` for Reload Courses) surfaced
   the shortcut-scope gap; the second, after the fix, verified the bubble-
   resolution claim against Microsoft's documented algorithm rather than
   trusting the code comment. One residual, PRE-EXISTING and unrelated to
   this change: `WebView2` has a known interop quirk
   (`microsoft-ui-xaml` #6231, WebView2Feedback #1884) where an accelerator's
   `Invoked` can fire twice ~100ms apart when focus is literally inside the
   rendered page content — low severity since `Reload()`/`GoBack()` are
   idempotent, but worth a manual smoke test (press Ctrl+R with a click
   actually inside the preview's page, not just its surrounding chrome) once
   at the machine.

2. ~~The " — Edited" title-bar marker~~ — ✅ Done 2026-08-22 for the
   INTERACTIVE deploy path. `Plantoir.Core/Models/SectionPublishState.cs`
   ports the mac's fingerprinting algorithm (exclusion filter, one-hop
   symlink resolution, self-publishing exclusion — case-insensitively, see
   below) and the `.publish_state/section<N>.json` stamp read/write.
   `MultiDestinationDeployRunner.RunAsync` fingerprints before the build and
   records the stamp (and the `section content marked published` trail
   event, newly added to `ActivityTrail.Event`) only when every configured
   destination succeeded, written before `IsRunning` flips to false so a
   listener refreshing on "run finished" never sees a stale stamp.
   `SectionDetailView` has no per-section OS window — one `MainWindow` shows
   one section at a time — so the marker is applied to the in-pane
   `SectionTitle` header instead, which is this app's equivalent of the
   mac's per-section title bar; `TitleText` (bare, no marker) is untouched
   and still used everywhere a sentence NAMES the section. Refreshes on the
   pane being constructed, `MainWindow.Activated`, and either runner's
   `IsRunning` going false, each off the UI thread and guarded by an
   incrementing generation counter so a stale walk can't overwrite a fresh
   one. Contract-driven tests in `SectionPublishStateTests.cs` (15, all
   green) run the same `contracts/app-rules.json` → `publishedFreshness`
   case list the mac suite runs. Two adversarial-review passes: the first
   caught nothing new (ordering, generation guard, exclusion filter, symlink
   one-hop, atomic stamp write all checked out); a second, narrower pass
   found and fixed a genuinely Windows-specific bug the mac's own filesystem
   never surfaces — `SectionPublishState.IsExcluded` compared the
   self-publishing exclusion path case-SENSITIVELY, so a destination folder
   whose on-disk casing differs from what a teacher typed (NTFS is
   case-insensitive but case-preserving) would silently fail to exclude,
   and a self-publishing course could read "— Edited" permanently; now
   `OrdinalIgnoreCase`, with a regression test.

   ~~Still genuinely outstanding, and NOT done: a scheduled deploy never
   writes the stamp.~~ ✅ Done 2026-08-22 (`GUI-IMPROVEMENTS.md` row 323).
   `TaskScheduling.Schedule` now always writes a wrapper `.ps1` (previously
   only for 2+ destinations), which fingerprints the section — via the
   bundled Python, `scripts/section_fingerprint.py`, since no app process is
   alive at the moment a scheduled deploy actually runs — right before
   running any destination's `deploy.ps1`, then writes a sentinel under
   `%LOCALAPPDATA%\Plantoir\scheduled\pending\` only if every destination
   succeeded. **A day later, a real overnight schedule for this still never
   fired at all — see `GUI-IMPROVEMENTS.md` row 325.** Unrelated to the
   fingerprinting work above: the stored `/TR` command had a doubled-
   backslash quoting bug (`\\\"` instead of a real `\"`) that predates this
   row entirely and had broken every scheduled deploy on Windows since the
   feature first shipped — fixed in `TaskScheduling.TaskRunCommand`. Confirm
   against row 325 before assuming a scheduled deploy actually runs;
   `ScheduledDeployCompletion.ConsumePending()`, wired into
   `MainWindow`'s `Activated` handler, applies and deletes any pending
   sentinel the next time the app runs. Fingerprinting at RUN time (not at
   schedule time) was deliberate — see "A scheduled deploy needs its own
   path to the same record" below, which this closes.

3. ~~Sampling the local engine's own stderr/stdout into the activity trail~~
   — ✅ Done 2026-08-23 (`GUI-IMPROVEMENTS.md` row 327). New
   `Plantoir.Core.Assist.AssistEngineLog` ports mac's filter/cap
   (`readsLikeATrouble`, `engineLinesWorthRecording`, the 12-line cap) as
   pure, tested functions checked against the same real llama.cpp fixture
   lines the mac test uses. `LocalModel.LinesSinceLastLook` reads new lines
   out of the existing 60-line ring buffer rather than a file offset — no
   file-backed log was needed because Windows already drains the engine's
   output via `Process` events rather than a blocking pipe, so it never had
   the wedge that made the mac move to a file in the first place.
   `AssistWindow.xaml.cs` wires it at the same points mac's `AssistSession`
   does (both engine-start-failure paths keeping everything, a 15s
   background poll once ready, one last look in `Shutdown()`). New
   `ActivityTrail.Event.AssistantEngineSaid` / `"assistant engine said"`,
   already pinned by the existing generic `ContractTests.cs` check against
   `shared-rules.json`. An adversarial review caught a genuine data race
   Windows has and mac does not — mac's version runs on one actor, Windows
   deliberately moved the watch loop to a background thread — fixed with a
   lock around the shared mark/count state. See `MAC-HANDOFF.md`'s "for
   awareness" section for the full write-up. Full suite: 655/655.

4. ~~The salvaged capture-dialog fixes on `issue/windows-capture-dialog-fixes`
   have not been built or tested on a real Windows machine~~ — ✅ Verified
   2026-08-23, correctly this time. That branch no longer exists — it merged
   as `a5979770` and was deleted per this repo's own convention, and commit
   `15ddf271` (the salvage itself) is on `dev`. `dotnet build` (0 warnings, 0
   errors) and `dotnet test Plantoir.Tests/Plantoir.Tests.csproj` (655/655)
   both pass. All three fixes are confirmed working: populated course-name
   suggestions and a club row, the uncut Language/region row (`MaxHeight`
   680→720), and the real "New Course or Club" title on the New Course
   dialog; the prompt shelf instead of a blank top third on the assistant
   window.

   **A verification detour worth recording, because it nearly produced a bad
   fix.** A first pass captured screenshots by invoking
   `Plantoir.exe --capture-marketing-shots ... --theme light`/`dark` directly,
   without switching the real OS appearance first. That produced a
   new-course-windows-light.png with a Dark dialog card inside an otherwise
   Light window — caught by Russell eyeballing the image, missed by both an
   in-conversation check and an independent adversarial-agent review, because
   both only checked the three claimed content fixes and not the card's
   theme. The instinct was to read that as a fresh product bug and patch
   `MarketingShotCapturer.CaptureNewCourseWindow`'s brush lookups
   (`Application.Current.Resources["SolidBackgroundFillColorBaseBrush"]` etc.)
   to resolve against `Application.Current.Resources.ThemeDictionaries["Light"
   /"Dark"]` explicitly — **that fix was wrong and was reverted**: the app's
   `ThemeDictionaries` isn't keyed that way at the top level, and the "fix"
   crashed the whole capture with a `COMException: Cannot find a resource
   with the given key: Light`.

   The class's own doc comment (`MarketingShotCapturer.cs:45-61`) already
   explains the real mechanism and already-chosen fix: brushes fetched via
   `Application.Current.Resources["..."]` resolve against the theme the APP
   PROCESS LAUNCHED IN, not against `RequestedTheme` set on any element —
   which is why the architecture is one process per REAL OS appearance,
   switched before launch, restored after. `website/shots/capture_windows.py`
   already does exactly this (`hero_windows.write_theme`, switching the
   `HKCU\...\Themes\Personalize` registry keys and broadcasting
   `WM_SETTINGCHANGE` before each themed launch). **The bug was in how the
   verification was run, not in the product** — re-running the exact same
   build with the OS genuinely switched to Light, then genuinely switched to
   Dark (registry flipped, captured, flipped back to the machine's original
   Dark setting afterward, mirroring rule 9's "leave the machine as you found
   it"), produced correctly-themed dialogs in both cases, no code changes
   needed. Lesson for next time: **capture verification must switch the real
   OS theme first, exactly like `capture_windows.py` does — invoking the exe
   directly with just `--theme` is not equivalent and will misreport this
   class of bug.**

   **A second trap, hit the same day, worth its own warning: a plain
   `dotnet publish Plantoir\Plantoir.csproj -c Release -r win-x64` is NOT a
   substitute for `windows-app\publish.ps1`, even for local testing.**
   `publish.ps1` has a manual step bare `dotnet publish` skips: copying
   `Plantoir\bin\Release\...\Plantoir.pri` over BOTH `resources.pri` and
   `Plantoir.pri` in the publish folder. Skip it and the unpackaged Release
   exe crashes on startup — inconsistently, which is what made this
   confusing: one run threw `InvalidCastException` trying to connect a
   `KeyboardAccelerator` in `MainWindow.g.cs` (which briefly looked like a
   real regression in the recent Preview-menu accelerator work, item 1
   above), another threw `XamlParseException: Cannot locate resource from
   'ms-appx:///MainWindow.xaml'` — different symptoms of the same missing
   resource package, not two different bugs, and not a real regression at
   all. Confirmed by elimination: same source, same clean `obj`/`bin`, exe
   published via `publish.ps1` instead — plain launch and the full capture
   flow both work, exit code 0. **Always use `publish.ps1` for a Release
   exe, never a bare `dotnet publish`, even to build a quick throwaway copy
   for a local test.**

5. **Two things to measure, not copy, on real Windows hardware** (see "Two
   things to MEASURE on Windows rather than copy from the mac" below):
   whether the browser needs `127.0.0.1` instead of `localhost` for a preview
   address, and which of the 25 progress markers your own `.ps1`/native
   runtime output actually prints.

   ~~The second half~~ — ✅ Done 2026-08-23 (`GUI-IMPROVEMENTS.md` row 353).
   It was not an unmeasured gap, it was a live bug: `TaskMilestones.cs`'s
   `CourseCreation`/`ExampleCourse`/`Preview`/`Deploy`/`BuildAndDeploy*`
   lists used four markers copy-pasted verbatim from the mac's `.sh`
   scripts — `Setting up this PC`, `Building your website builder`,
   `Ensuring container is running`, `Starting container if needed` — none
   of which have ever appeared in `setup.ps1`/`preview.ps1`/`deploy.ps1`'s
   real output. Root cause, nailed by git history: `setup.ps1` gained its
   "Native toolchain (no container)" rewrite (no WSL2, no Docker, no
   container start at all) the day AFTER `TaskMilestones.cs` was last
   edited, silently orphaning the four markers describing events — a
   one-time machine setup, a container starting — that no longer happen on
   Windows. Confirmed empirically against real `preview.ps1 --build-only`
   and `deploy.ps1 --to-folder` transcripts: neither string appears.
   Practical effect: the first two-to-three stages of most progress bars
   could never be reached by marker match — the bar sat at 0% until a
   later, still-real marker jumped it forward several steps at once,
   exactly the silent failure this section warns about. Fixed by tracing
   each launcher's real early output and substituting real markers:
   `Detected host timezone offset` (setup.ps1), `Running the website
   builder on this PC` (preview.ps1), and `Host timezone offset` + `from
   this PC` (deploy.ps1) — collapsing two-or-three dead stages into one or
   two real ones per list, since the native toolchain genuinely has fewer
   distinct phases than the container one did. New
   `TaskMilestoneLauncherMarkerTests` (`ParsingTests.cs`) reads the actual
   `.ps1` files rather than a hand-typed transcript, so a future launcher
   rewrite that drops one of these lines fails the suite instead of
   silently stalling a teacher's bar again. Caught by adversarial review
   along the way: `MarketingShotCapturer.cs`'s `PreviewTranscript`/
   `DeployTranscript` mock transcripts, whose own doc comments claim to be
   coupled to `TaskMilestones` ("change one there and this stops
   advancing"), still carried the four dead strings — fixed to match, and
   hand-verified against `ScriptRunner.AdvanceMilestones` that each still
   lands the screenshot on its intended stage. Full suite: 656/657 (the one
   failure is the pre-existing, unrelated item 9 course-code-dashes case).

   ~~The first half — the Edge `127.0.0.1` question — remains genuinely
   unmeasured.~~ — ✅ Measured 2026-08-23 (see `MAC-HANDOFF.md`'s "for
   awareness" entry). Tested by hand against a real preview (port 8081):
   `http://localhost:8081` and `http://127.0.0.1:8081` both loaded instantly
   in Edge, repeated more than once, no IPv6-first stall observed. The
   rewrite in `OutputParsers.cs`/`SectionDetailView.xaml.cs` is a harmless
   no-op on Windows as currently shipped — kept in place, not removed, but
   no longer an open question.
6. ~~The working-folder path bar's fuller gesture set~~ — ✅ Done 2026-08-23
   (`ff4d9ee9`, `GUI-IMPROVEMENTS.md` row 328). Double-click-to-open, the
   right-click Show-in-Explorer/Open-Folder menu, and the hover tooltip were
   already in place from an earlier pass; this closed the rest — a plain
   click now does nothing (it had been a redundant reveal-in-Explorer,
   duplicating the right-click menu's own item, matching the mac's own path
   bar per `contracts/shared-rules.json` → `workingFolderPathBar`), and each
   crumb shows its real shell folder icon (new `PathBarCrumb`/`FolderIcons`,
   async-loaded via `StorageFolder.GetThumbnailAsync`, cached, graceful null
   on failure, icon vertical alignment nudged to sit on the text baseline
   rather than its bounding-box center, matching macOS). Found and fixed
   while verifying: the existing `DataTemplate` nested a second
   `BreadcrumbBarItem` inside `BreadcrumbBar.ItemTemplate`, which is
   invalid — `BreadcrumbBar` already generates its own container per
   crumb. That built clean and passed the full suite but broke at runtime,
   silently falling back to the bound object's `ToString()` so every crumb
   showed the literal text "Plantoir.Views.PathBarCrumb"; fixed by having
   the template supply only the container's content, with a defensive
   `ToString()` override on `PathBarCrumb` as a second line of defence. A
   `MAC-HANDOFF.md` awareness entry records the WinUI nesting trap for
   anywhere else an `ItemTemplate` wraps a control-specific item-container
   type. Full suite: 655/655.
7. ~~The first-deploy marker's destination-scoping~~ — ✅ Verified already
   correct 2026-08-23. The divergence this item warned about — `AssistWorkspace.cs`
   accepting either destination's marker rather than only the CURRENT one —
   is not present in the code as it stands: `DeployCommand.HasDeployedBefore`/
   `FirstDeployMarkerPath` (`Plantoir.Core/Models/DeployCommand.cs:99-125`) are
   strictly keyed by `destinationType`, and both callers —
   `ScheduledDeploy.Problem` (`ScheduledDeploy.cs:67,78`) and
   `AssistWorkspace.Deploy` (`AssistWorkspace.cs:1097`) — pass the specific
   destination type for every configured destination, primary and additional,
   never "either folder." `AssistWorkspace.ReleaseSite`
   (`AssistWorkspace.cs:1851-1875`) does loop over both `.netlify_sites` and
   `.cloudflare_sites`, but that is a genuinely different operation — moving
   whatever marker exists aside during a section rollover, independent of the
   CURRENT `deploy_target` — not the "has this destination been deployed"
   question, so it is not this bug in disguise. Checked for other instances:
   none in `Plantoir.Mcp`'s `check_section`/`list_courses`, and mac's own
   `DeployCommand.swift:99-151` uses the identical destinationType-keyed
   design, so there is no platform divergence to close. New regression test,
   `ASwitchedDestinationIsNotConsideredDeployedJustBecauseTheOldOneWas`
   (`Plantoir.Tests/ScheduledDeployTests.cs`), pins the exact scenario this
   item described — a leftover `.netlify_sites` marker on a course now
   configured for Cloudflare must still refuse as "never deployed," not read
   the stale marker as proof — and an independent adversarial review
   confirmed the test reaches the marker check rather than short-circuiting
   on an earlier refusal (the Cloudflare account ID passed is a valid
   32-hex-char value, so `CourseConfiguration.CloudflareAccountProblem`
   passes cleanly first). Full suite: 657/658 (the one failure is the
   pre-existing, unrelated item 9 course-code-dashes case). `contracts/
   file-formats.json`'s `firstDeployMarkers.knownDivergence` field, and the
   "One divergence found by sweeping" section below, are corrected to match.
8. ~~Three deploy-after-preview console races fixed on mac 2026-08-22, not
   yet checked on Windows~~ — ✅ Done 2026-08-23 (`GUI-IMPROVEMENTS.md` row
   354). All three were confirmed present by an investigation agent, fixed,
   and independently checked by a second, adversarial agent before this was
   marked done. None ported mechanically (SwiftUI state races, not shared
   code) — each got its own C# shape:
   - **Row 317** (stale-timestamp panel flash) — `SectionDetailView`'s own
     `showsDeployProgress`-equivalent (`RefreshChrome`'s `showDeploy`) had
     the identical ordering bug: `Deploy_Click` called `StopPreviewAsync()`
     before `_deployRunner.StartedAt` was set (only `RunAsync` set it, deep
     inside the click handler), so the panel-choosing timestamp comparison
     kept favouring the just-stopped preview for a beat. Fixed with
     `MultiDestinationDeployRunner.ClaimConsole()`, called before touching
     the preview runner at all, mirroring the mac's
     `deployRunner.startedAt = Date()` pre-claim in `deployAndWait()`.
   - **Row 318a** (blank console + Deploy re-entrancy) — present, and with a
     LARGER exposure window than mac's ~0.5s: nothing disabled the Deploy
     button for the whole `StopPreviewAsync()` span (up to ~20s on Windows,
     since a stopped preview's container-side sweep takes longer here than
     mac's). Fixed with `_isPreparingDeploy`, a private field on
     `SectionDetailView` (view-local state, like mac's `@State
     isPreparingDeploy` — not a property on the runner), set immediately
     after the refusal-reason check and cleared in a `finally` block so no
     early return or exception can strand it true. `TaskProgressView`
     gained a dedicated `ShowPreparing(title)` placeholder — a plain
     indeterminate bar and "Preparing to deploy…" text with `_runner` set
     to `null` — rather than binding early to either a blank fresh runner
     or the previous deploy's stale outcome, mirroring the mac's own
     `preparingToDeployPlaceholder` view (a dedicated placeholder, not a
     runner-state hack, was the mac's actual choice and is the one that
     ported cleanly).
   - **Row 318b** (false "Done" flash between build and deploy) — present:
     `MultiDestinationDeployRunner.RunAsync` reuses one `ScriptRunner` for
     the build-only run and the leg's own deploy run, and completion
     detection is a 100ms poll (`ScriptRunner.WaitUntilFinished`), so the
     gap between the build's `IsRunning` flipping false and the deploy
     script actually launching on the same runner read to
     `TaskProgressView` as the whole leg finishing. Fixed with
     `ScriptRunner.IsBetweenPhases`, set `true` synchronously right after
     the build launches (long before it can finish) and cleared only by the
     next `Run()` call's own reset (or the cancel/stop/build-failure early
     exits) — `TaskProgressView.Render()` and its tick timer now check
     `IsRunning || IsBetweenPhases` everywhere they previously checked
     `IsRunning` alone, mirroring mac's identical `isBetweenPhases` flag and
     `runner.isRunning || runner.isBetweenPhases` check.

   **One thing the adversarial review caught that is worth naming rather
   than silently having fixed:** an explicit `RefreshChrome()` call
   originally sat between clearing `_isPreparingDeploy` and `await
   _deployRunner.RunAsync(...)`. It was almost certainly never visible
   (everything up to `RunAsync`'s own `Notify(IsRunning)` runs synchronously
   on the UI thread, and WinUI does not paint an intermediate frame
   mid-callstack) but it re-derived the exact stale-`Legs` race the fix
   exists to close, one future `await` inserted in that gap away from
   becoming a real, visible bug. Removed — `RunAsync`'s own synchronous
   prefix (reassign `Legs`, set `IsRunning`, `Notify`) already triggers
   `RefreshChrome` through the constructor's `_deployRunner.PropertyChanged`
   subscription, so no manual call belongs there at all. The general lesson:
   a fix that works only because of synchronous-batching timing is fragile
   even when it currently renders correctly — remove the redundant call
   rather than leave a race that "doesn't fire yet."

   Full suite: 657/658 both before and after this item (the one failure is
   the pre-existing, unrelated item 9 course-code-dashes case, unaffected).
   A pre-existing, UNCHANGED-by-this-fix re-entrancy gap was noted along the
   way and left open rather than folded in here: `Deploy_Click`'s first
   guard runs before `await TheAssistantIsBuilding()`, so a second click
   between that await yielding and `_isPreparingDeploy` being set (several
   lines later, after the refusal-reason check) is not caught — this
   predates the fix (the original single `IsRunning` guard had the
   identical gap, just later in the method) and is narrower now, not wider,
   but was not the shape row 318a described, so it was left rather than
   silently expanded into this item's scope.

9. ~~Course codes with DASHES, and the club heuristic that misreads them~~
   — ✅ Done 2026-08-23 (`GUI-IMPROVEMENTS.md` row 382). Both contract-driven
   fixes below are implemented, plus the picker itself was rebuilt as a real
   WinUI `AutoSuggestBox` (see the cross-linked section below), which the
   dashes/club work otherwise had no reason to touch. Two adversarial review
   passes caught and fixed two real bugs before this was called done: the
   `AutoSuggestBox`'s `SuggestionChosen` event was never wired, so clicking
   or Enter-selecting a dropdown row silently did nothing (WinUI does not
   auto-commit a templated item's text on selection — `TextMemberPath` alone
   only governs the box's own default, non-templated rendering); and
   `CourseConfiguration.IsClub` (used by Course Settings' "Short label"
   field) still carried the old uncatalogued heuristic even after the
   wizard itself was fixed, which would have made a BC course created
   correctly as a non-club read as a club again the moment its Settings
   page opened — both are now `Plantoir.Core.Models.ClubCodeRule`, behind
   one shared `Plantoir.Services.CourseNameCatalogs.Shared` catalog (which
   also now loads British Columbia's names alongside Ontario's — it only
   loaded Ontario before). New `ContractTests.
   CourseManagement_ClubDetection_MatchesContract` runs all 11
   `courseCode.clubDetection` cases. **Follow-up the same day:** a Province
   `ComboBox` ("Ontario" / "British Columbia") was added ahead of the
   course-code row, mirroring the mac's segmented Province picker
   (`GUI-IMPROVEMENTS.md` row 382's addendum) — new `CourseCatalog` (ported
   from the mac's `CourseCatalog.swift`) and `CourseNameCatalogs.
   ForProvince`, narrowing the picker's suggestion list to one province
   without gating typed codes through either catalog. Full suite: 659/659,
   later 664/664 with the province addition's own tests. Two changed rules,
   both already in `contracts/course-management.json`:

   - **`courseCode.problems`** — a dash is now ALLOWED in a course code, and
     both teacher-facing sentences changed with it ("…letters, numbers,
     spaces and dashes" in the wizard, "Letters, numbers, dashes" in the
     sidebar). The old contract case expecting `CS-CLUB` to be refused is
     reversed in place, with its original reasoning kept so the change reads
     as a decision rather than a slip. The reason: 55 of the 117 codes in
     `support/british_columbia_secondary_courses.json` contain a dash
     (MTEL-12, MFMP-10, MMA--09), so the rule was refusing more than half of
     one province's real courses. Deserialise the sentences; do not retype
     them.
   - **`courseCode.clubDetection`** — new section, 11 cases.
     `NewCourseDialog.IsClubCode` (`NewCourseDialog.cs:641`) is
     `code.Length >= 4 && !char.IsDigit(code[3])`, which was the mac's line
     too and carries the identical bug: BC codes put a letter or a dash in
     fourth place, so **every one of BC's 117 courses currently reads as a
     club on Windows**. The visible cost is a club-only "short label" row
     appearing on a real course, and `custom_short_name` being written for
     it at `NewCourseDialog.cs:827`. The fix the mac made is in
     `ClubCodeRule`: ask the course-name CATALOG first and take its answer
     as final; fall back to the fourth-character guess only for a code the
     catalog has never heard of, which is what that guess was always for
     (CODING, ROBOTICS).

   The lesson is worth more than either fix: **a heuristic that reads a
   code's SHAPE encodes one jurisdiction's conventions**, and it stops being
   true the moment a second jurisdiction arrives. Ask the data you already
   have before guessing from the characters.

   **Before touching this field, read "The course-code picker is a hand-built
   combo box — and you probably should NOT build one" below.** Both fixes
   above land in the same New Course wizard field the mac rebuilt into a
   searchable two-line flyout with an "Example content" badge
   (`GUI-IMPROVEMENTS.md` rows 333–338); that section explains why the mac
   hand-built its version (a real `NSComboBox` can only draw plain strings)
   and says plainly that the reason likely does NOT apply to WinUI, whose
   `ComboBox`/`AutoSuggestBox` can take an `ItemTemplate` — try the real
   control first rather than porting the hand-built one. If a dash-containing
   code or a corrected club/non-club badge needs to render correctly in that
   dropdown, the four hard-won lessons there (single state for flyout
   visibility, decline-not-swallow key handling, highlight rows by CODE not
   index, and re-check badge contrast on a highlighted row) apply whether you
   end up hand-building or wiring the real control's template.

10. **Special folders hardening: Graded folders reconciliation and `noGradedFolders` health check (2026-08-24).**
    - **`setup_course.py:graded_folders_for` reconciliation** — When a new
      course is created, `graded_folders_for` now checks the declared pool
      against the actual folder lists (`shared_folders` +
      `per_section_folders`). If declared folders (such as `Tasks`) were removed
      by the teacher during setup, they are dropped from `graded_folders`.
      If no folders remain, explicit `[]` is written to `course_config.json`
      (settled policy: `[]` means asked and answered "nothing counts for
      marks", while omitting the key means unconfigured legacy course).
    - **`noGradedFolders` health check** — Added in `scripts/site_health.py`
      and `contracts/shared-rules.json` → `siteHealth.checks`. Fires when
      `coverage_wanted` is true and curriculum expectation pages are present,
      but no folder on disk matches `graded_folders` (or contains `task` under
      the unconfigured rule). Emits `PLANTOIR_HEALTH:` JSON line. It is
      deliberately unfixable (in `neverOffered.checks`) — an existence fix
      would not assign marks to pages.
    - **Shared Python**: both scripts run on Windows identically. Windows
      receives the finding in the `PLANTOIR_HEALTH:` transcript line and
      displays the contract-authored sentence and detail without re-wording.

11. **Special folders hardening: `excluded_items`, preflight skip, and `index.md` sentinel notes (2026-08-24).**
    - **`excluded_items` key in `course_config.json`** — An object with optional
      `shared` and `per_section` arrays of strings:
      `{"shared": ["Tasks"], "per_section": ["Drafts"]}`. The key is ABSENT
      (not `{}`) when nothing is excluded. Documented in `contracts/file-formats.json`.
    - **Course Settings mutations** — In Course Settings, when a teacher removes
      a folder or file from the list editors, the app adds it to `excluded_items[scope]`
      and logs the `item excluded` event on the activity trail. When a teacher adds
      a previously excluded item back, the app removes it from `excluded_items[scope]`
      (deleting the key when empty) and logs `item re-included`.
    - **Preflight discovery skipping in `scripts/build_site.py`** —
      `preflight_update_course_config` checks `excluded_items`. Discovered items
      present in `excluded_items[scope]` are NOT added to `shared_folders` or
      `per_section_folders`, are NOT un-hidden, and are NOT added to `expandable`.
      Preflight prints console skip lines: `🚫 Skipping excluded <scope> <kind>: <name> (listed in excluded_items)`.
    - **`index.md` sentinel notes** — Preflight checks for existing `index.md` files
      in excluded folders. If present, it idempotently injects the sentinel note
      defined in `contracts/shared-rules.json` → `specialNames.excludedFolderIndexNote`
      between HTML comment delimiters (`<!-- plantoir:excluded-folder-note:start -->` ...
      `<!-- plantoir:excluded-folder-note:end -->`). If the folder is later re-included,
      preflight strips the note from the vault's `index.md`. Preflight NEVER creates
      a new `index.md` file in a teacher's vault.
    - **Content merge stripping** — `process_frontmatter` strips any sentinel blocks
      when copying files into the merged `content/` directory so the note can never
      reach students in `public/`.
    - **Shared Python**: preflight skipping, sentinel note application/removal, and
      content stripping are in shared `build_site.py` and run identically on Windows.
      The Windows app only needs to implement `ExcludedItems` in `CourseConfiguration.cs`
      and wire exclusion/re-inclusion in the Settings list editors with trail events.
    - **Why this shape, and what was rejected (decided 2026-08-24).** An object
      keyed by scope rather than a flat list, because the two scopes are matched by
      different scans (`discover_shared_items` vs `discover_section_items`) and the
      same bare name can legitimately exist in both. Two top-level keys
      (`excluded_shared_items` / `excluded_section_items`) were rejected as one
      concept scattered across keys both apps must remember to write together. A
      per-section-NUMBER exclusion was rejected for now because nothing can set it
      (Course Settings edits one course-wide `per_section_folders` list), but the
      object is additive so a `"sections": {"4": [...]}` key can be added later.
    - **An exclusion does NOT expire** when the folder is deleted and re-created in
      Obsidian. Discovery is name-based, so the build cannot tell "the folder I
      excluded" from "a new folder", and guessing "new" would re-publish something
      the teacher deliberately excluded. It ends only when the teacher adds the
      name back in Course Settings — the `index.md` note exists to make that
      self-explaining.
    - **The mechanism of exclusion is the name's ABSENCE from the copy list**
      (`shared_folders` etc.); `excluded_items` stops preflight putting it back
      AND, since the Piece 2 review, preflight also DROPS any excluded name it
      finds still in a copy list, prints `🚫 Dropped excluded <scope> <kind> from
      the copy list: <name>`, and writes the config back. So the key is
      authoritative and a name in both cannot publish — but the Windows app
      should still do BOTH on removal (take the name out of the list AND record
      the key), because the reconciliation only runs at the next build and a
      teacher reading the list in Settings before then would see it. Record `item re-included` ONLY when the name was actually in
      `excluded_items`; an ordinary add is not a re-inclusion, and a trail line
      that says it was would be believed.

12. **Special folders hardening: The protection model — row states, curriculum resolution, marks floor, and wizard marks control (2026-08-24).**
    - **Item Protection in List Editors & Toggle Lists**:
      Folders and files with special meaning now have protection policies (`ItemProtection` in Swift, `ItemProtection` enum in C#):
      - `Ordinary`: standard direct removal.
      - `Consequential(title, message)`: minus button prompts a confirmation dialog with destructive "Remove" and "Cancel" actions before removing.
      - `Blocked(reason)`: minus button is REPLACED with an info icon (ⓘ). Clicking the info button shows a popover/flyout explaining why removal is forbidden and explicitly naming the switch to turn off first (e.g. "Include the curriculum coverage map").
    - **Settled UX Decisions**:
      - Removal is NEVER silently disabled/greyed out with no explanation, nor does clicking minus auto-flip related switches via dialog. The teacher is given a plain-language explanation of what depends on the folder and which switch to toggle first.
      - In the New Course Wizard, blocking is computed from *effective* switch values (`CourseConfiguration.CurriculumCoverageEnabled(...)`), avoiding disabled-switch deadlocks when parent switches are off.
    - **Protection Rules by Item Kind**:
      - *Resolved Curriculum Folder*:
        - Resolved using `CurriculumFolderRule`: configured `curriculum_folder` if present in candidates, else alphabetically first candidate containing `"curriculum"` (matching `_find_curriculum_folder` from `build_site.py` and `contracts/shared-rules.json` → `specialNames.curriculumFolderResolution`).
        - In Course Settings, when `include_curriculum_coverage` is true: **blocked** (`specialNames.curriculumFolderBlockedByCoverageSetting`).
        - When `include_curriculum_coverage` is false: **consequential** (`removeCurriculumFolderTitle` / `removeCurriculumFolderMessage`).
        - In Wizard, when effective curriculum coverage is true: **blocked** (`specialNames.curriculumFolderBlockedByCoverageMap`). When effective curriculum pages is true: **blocked** (`specialNames.curriculumFolderBlockedByCurriculumPages`). When both false: **consequential**.
      - *Graded Folders (Marks)*:
        - In Course Settings and Wizard, when curriculum coverage is ON and `gradedFolders.count <= 1`: removing or un-ticking the last graded folder is **blocked** (`specialNames.lastGradedFolderBlocked` in Settings, `specialNames.lastGradedFolderBlockedWizard` in Wizard).
        - When more than one graded folder exists or coverage is OFF: removing from shared/per-section list is **consequential** (`removeGradedFolderTitle` / `removeGradedFolderMessage`).
        - *Materialisation on first edit*: If `graded_folders` is `null` (legacy course), mutating the marks toggle list materialises the inferred pool rather than initializing to `[]`.
      - *Per-Section Folders & Classes*:
        - If `perSectionFolders.count <= 1`: removing is **blocked** (`specialNames.lastPerSectionFolderBlocked`). Prevents empty `per_section_folders: []`.
        - The folder named **`All Classes`** (compared case-insensitively — `ClassFolder.isTheAllClassesFolder`, i.e. `ClassFolderRule.FallbackName`) is **blocked** always (`specialNames.classFolderBlocked`), however many per-section folders there are. Every OTHER per-section folder, including other names that mention classes, can be added or removed as before. Russell's decision on 2026-08-24, during the Piece 3 review, replacing the "class folders are consequential when alternatives exist" rule this item first shipped with. The reason: the next-class button and the schedule write pages into that folder, so a confirmation would be asking the teacher to break both. `removeClassFolderConfirmation` was removed from the contract with it.
      - *Section Index File*:
        - Removing `index.md` (case-insensitive) from per-section files is **blocked** (`specialNames.sectionIndexFileBlocked`).
    - **Wizard Marks Control**:
      - For skeleton and from-scratch courses (`!structureComesFromExampleContent`), the Structure step includes the Marks checklist (`MembershipToggleListView`) populated from current folder lists.
      - Selected `graded_folders` are written into `course_config.json` on course creation.
    - **Contract Sentences & Tests**:
      - Deserialise all sentences from `contracts/shared-rules.json` → `specialNames` (do not hardcode).
    - **Review amendments (2026-08-24, row 380)**:
      - *Removal drops the name from the marks pool.* When a folder leaves `shared_folders` or `per_section_folders` in Course Settings, remove it from `graded_folders` too (materialising a `null` pool from the *task*-substring rule first, as a tick would). Without this the consequential dialog's sentence is false and `graded_folders` names a folder `excluded_items` tells the build to skip. The wizard already reconciles on removal (`reconciledGradedFolders`).
      - *The resolver is name-only, and that is fine.* `curriculumFolderResolution` is the name half of `_find_curriculum_folder`; the build additionally requires an expectation-code page inside the folder. The GUI cannot see that from the config, so it may protect a folder the build would skip — never the wrong folder among those it can see. Do not try to replicate the disk check.
      - *`removal blocked` is a trail event* (`activityTrail.mustRecord`): item name, which list, and the sentence shown. Record it where the ⓘ is clicked and where a blocked untick is refused.
      - *The contract holds 5 resolution cases*, not the 10 row 379 claimed.
      - *Size the flyout for the longest sentence.* The mac popover truncated to one line until it was given a fixed width and allowed to wrap; the `lastGradedFolderBlocked` sentence is the longest in `specialNames`, so test the flyout with that one.

13. **Renaming a course folder from inside the app (2026-09-01).** The mac now
    renames a folder on disk, in every section, rewriting the links that name
    it and every config key that mentioned it — plus the two foot-guns behind
    it: Add creates the folder, Remove says the folder stays. Sentences,
    refusal rules and the list of keys a rename must carry across are all in
    `shared-rules.json` → `specialNames`. Two new trail events. **The full
    write-up, including the three decisions and the one trap that is yours
    alone (`Directory.Move` and open handles), is in "Renaming a course folder
    from inside the app" below** — read that rather than this summary.

14. **A section with no front page no longer publishes yesterday's site
    (2026-09-01).** Shared Python, so you inherit the fix; the one thing you
    owe is `MissingFrontPageExplanation` in `FailureExplainer.cs`, asked BEFORE
    `MissingBuildExplanation`, which is already written on this side and is
    pinned by a contract case. See "A section with no index.md cannot be
    PUBLISHED" below.

15. **What a course calls a unit (2026-09-01).** `unit_word` in
    `course_config.json`, absent meaning "Unit". Shared Python does the rule
    and the payload rewrite; you owe the C# mirror, a wizard field, and the
    assistant's sentences. **Three new contract cases will fail your suite
    until you read `pageNaming`'s new `term` field with a default.** Full
    write-up in "What a course calls a unit" below.

16. **What a course calls its class folder (2026-09-01).** `class_folder` in
    `course_config.json`, recorded rather than guessed, materialised by a
    rename along with `curriculum_folder`. Replaces the class-folder refusal
    item 13 described, which no longer exists. **Eight new contract cases will
    fail your suite until `ClassFolderRule.cs` reads the key.** Full write-up
    in "What a course calls its class folder" below.

**Everything else this section used to list as an ordered work plan —
contracts wiring, the approval wording, the deploy/preview race, the activity
trail, the problem report, the 2026-08-16 assistant batch (`add_next_class`,
`plan_remember_timetable`, the `LinkGraph` exclusions, `assistantConfirmation`),
the `ReDatePlan` overflow fix, asking for the schedule, course renaming, the
native local model, the assistant-choice Settings panel, the credential
dialogs, and the two small fixes (`AutoFillCourseName`, the Curriculum
Coverage toggle) — was verified DONE in `windows-app/` on 2026-08-22 and its
write-up now lives in
[`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md).**

### One thing NOT to do

Do not port entry 142 (Colima sizing) or entries 244–245 (`launchd`). They are
macOS mechanics. The transferable half of 244–245 is a single lesson worth
having before you touch `TaskScheduling.cs`: register a scheduled job as the
APP, not as the shell it happens to run, or the operating system tells the
teacher that "bash" — or, on the second attempt here, a person's name — wants
to run in the background.

## Windows no longer runs any of this in a container

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
  container.** It matches `node.exe` / `python.exe` by command line
  (`build_site.py --course=/--section=` for the build, the section's own
  build-root path for the server) and walks parent/child links to catch
  descendants, then kills them with `Stop-Process`. No container, no `docker
  exec`, no engine to stop.

`GUI-IMPROVEMENTS.md` entries 290 and 292 are the log rows for this change;
`MAC-HANDOFF.md` is where its origin and reasoning are written up in full.
The sections below that still described the old Docker/WSL2 container
architecture as current have been corrected to match the above — where the
old material is useful as history (why containers were tried, what WSL2 and
Colima-parity cost, lessons that still generalize), it is kept but labelled
as history, not as what Windows does today.


## What you are building

A native Windows app wrapping the same toolchain the macOS app wraps. The
scripts themselves are **shared and already done**: `scripts/`, `support/`,
and `patches/` (applied to a vendored Quartz clone) all live in this
repository and are shared with the macOS app, which still runs them inside a
Colima container — see the note above for why Windows itself does not. The
PowerShell launchers (`setup.ps1`, `preview.ps1`, `deploy.ps1`) drive that
shared Python natively on Windows; the Windows app's job is the interface:
the same behaviours as the macOS app, driving the `.ps1` launchers instead of
the `.sh` ones.

**The specification is [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md)** — every
numbered entry describes a behaviour the macOS app has, and every one carries
a Windows-porting note. Work through it top to bottom; it is the product of a
great deal of live testing and each entry earned its place.

**This file is kept current as the macOS side changes**, rather than written
once. The macOS working rule is that a change is not finished until its log
entry has a usable Windows note, anything architectural has a section here,
and any guidance the change made WRONG has been corrected. So if something
here contradicts what you find in the repository, the repository is right and
this file has a bug — say so, because that is a defect on the macOS side, not
a judgement call on yours.

## The three load-bearing rules

1. **The GUI never mentions the machinery.** No "toolchain", "script",
   "Docker", "container", or "WSL" in user-facing text. Plain words:
   "Building your website builder…", "Getting this Mac ready…" (yours will
   say "this PC"). **The visible verbs are now BOTH, and they mean different
   things** (entries 140 and 143, reversing entry 103): a PAGE is
   *published* — the `publish:` frontmatter flag deciding whether students
   see it — and the SITE is *deployed* to Netlify, Cloudflare or a folder.
   One word for both makes "I published tomorrow's class" mean a flag to one
   person and a live site to another. Internal names, script file names and
   config keys keep "deploy" throughout.
2. **Use the script logic itself as much as possible.** The app runs the
   real launchers and answers their real prompts; it does not reimplement
   them. Progress comes from parsing their output (milestone markers,
   `#N [k/n]` build steps, "N of M" upload counts, the announced preview
   address).
3. **Free resources whenever possible.** On Windows there is no engine or
   container to stop — the launchers run native processes directly, and
   `preview.ps1 CODE N --stop` kills exactly that section's processes (see
   below). Close a folder's last window → stop that folder's live previews.
   Quit the app → nothing else to release; there is no shared engine.

## Architecture the app must reproduce

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
  that section's `node.exe` / `python.exe` processes by command line and
  working directory (so other sections are safe), walks their descendants,
  and `Stop-Process`es them — and never starts anything itself. Call it
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

## Config is the contract

`course_config.json` is shared between the app, the wizard, and the build.
See [`documentation/08-course-config-reference.md`](documentation/08-course-config-reference.md).
Keys the Windows settings UI must round-trip (per-section maps use
`{"sections": {"sectionN": value}}`):

- `course_code`, `course_name`, `locale`, `section_numbers`, `num_sections`
- `emojis.sections` — header emoji per section (system emoji panel: Win+.)
- `color_schemes` — flat map sectionN → scheme id (`support/colour_schemes.json`)
- `fonts.sections` — header/body/code display names (files in `support/fonts/`,
  name → file by stripping spaces; "Helvetica, Arial" means system default)
- `show_section_marker.sections` — the "S1" in the site header
- `show_grade_in_title.sections` — grade prefix on the landing title
  (legacy: a single course-wide bool; honour it). LITERAL behaviour: the
  switch alone decides; the UI shows an orange warning when the course
  name already contains the grade label, and the teacher resolves it.
- `custom_domains.sections` — the app swaps published-site links' host to
  this domain (path kept, https); entries are normalized (scheme and path
  stripped) on the way in
- `shared_folders`, `shared_files`, `per_section_folders`,
  `per_section_files`, `hidden`, `expandable`, `expandOnFolderClick`,
  `show_reading_time`, `footer_html`
- `deploy_target` ("netlify" default | "cloudflare_pages" | "local_folder") and
  `deploy_folder_path` (entries 101–102) — folder deploys pass
  `--to-folder <path>` to the launcher, which robocopy-mirrors each
  section into `<path>\sectionN`; completion is announced by a
  `PUBLISHED_FOLDER=` line the app turns into a Show-in-Explorer button.
  The Publishing choice appears in BOTH the settings form and the
  new-course wizard (share the control); an empty, missing, or
  unwritable folder blocks save/create with an inline message and is
  checked the moment a folder is chosen; folder-mode progress labels
  never mention Netlify; and the completion adds a note that the pages
  only render properly once uploaded to a web host
- `prepopulate_example_content`, `include_curriculum_pages` (entries
  92–93) — written by the new-course wizard, read by the shared Python
  wizard as its defaults; both forced false when no example content
  exists for the course code
- `use_lcs_terminology` (entry 94) — whether the factory structure
  defaults use LCS's own set-up; the two factory sets live as
  `DEFAULT_*` vs `LCS_*` constants in `scripts/setup_course.py` and the
  Windows equivalent of `WizardDefaults` must mirror them exactly
- `custom_short_name` — the ≤12-character label shown beside the header
  emoji instead of the course code, in club mode. Already implemented on
  Windows (`CourseConfiguration.cs`); listed here because this table is the
  contract and it was missing from it
- `include_curriculum_coverage` and `include_coverage_notes` (entries 125,
  130) — whether the generated `Curriculum Coverage` map page is produced, and
  whether it carries its explanatory sections or the map alone. Read by
  `build_site.py`, both defaulting true. **Implemented on Windows** (verified
  2026-08-22): both keys are read and written in `CourseConfiguration.cs` and
  surfaced as toggles in `NewCourseDialog.cs` and `CourseSettingsView.xaml.cs` —
  this note used to say "not yet implemented" and was stale.
- **Edit keys in place and preserve unknown keys** — the macOS app keeps
  the decoded JSON as a dictionary precisely so future toolchain keys
  survive a settings round-trip. The shared Python wizard does the same in
  the other direction: it copies through every key it does not own, which is
  what lets an app-written setting survive a wizard re-run.

## Example content (entries 92–96)

Ready-made course payloads ship in `support/example_content/<CODE>/` — 37 of
them as of 2026-08-15 and growing, so read the directory rather than any list
written here; detection is by the presence of `manifest.json`, which is what
the code does anyway. (SNC1W is the example course's content converted to
payload form, so a teacher actually teaching Grade 9 science gets it as
starting content; SNC2D is its Grade 10 sequel, and SCH3U/SCH4U carry
chemistry through Grades 11 and 12.) All
the installing, date logic, and curriculum handling is shared Python —
Windows needs exactly three UI behaviours:

- **Detection**: example content exists for a code when the bundled
  `support/example_content/<CODE>/manifest.json` exists; the curriculum
  toggle additionally needs the manifest's `curriculum_folder` to be
  non-empty (reference logic: `ExampleContentCatalog.swift`).
- **Starting Content section** in the new-course wizard: "Pre-populate
  course with example content" (default ON) with "Include Ontario
  curriculum pages" beneath it (default ON, disabled when the first is
  off). When no content exists for the code, this is where the SKELETON
  toggle goes instead (entry 123) — "Start from a <subject> skeleton" —
  and the quiet "empty folders" caption is now the last resort, for a code
  with neither.
- **Structure lock**: when pre-populating, HIDE the folders/files
  editor behind a caption — the payload's manifest is the entire
  structure authority and the Python wizard skips all structure
  prompts.

Authoring new payloads is content work, governed by the repo-local
skill `.claude/skills/example-content/` and checked by its
`lint_payload.py` — no app code changes on either platform. The same skill
holds the skeleton generator and `lint_skeletons.py`; the skeletons are
generated output, so never hand-edit `support/skeletons/`.

Two payload conventions have changed since these entries, both handled by
shared Python: course-level pages now arrive with
`createdSectionN`/`publishForSectionN` (one pair per section — entry 122), and
`Key Links` ends with the site tour (entry 121).

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


## The assistant's division of labour — the rule everything else follows

**The model picks which Swift function to run, and fills in its arguments.
Nothing else.** Every rule about what an action MEANS lives in code. If you
take one thing from this file, take this: it is what makes a small local
model viable, and every problem worth having came from violating it.

The split is measured, not aesthetic. Across the same runs the model:

- **misrouted five of the eleven suggested phrasings in EVERY trial** — it is
  bad at choosing;
- produced **zero wrong courses, zero wrong dates, zero type errors, zero
  invented dates** — it is good at filling in.

So take the choosing away wherever it can be taken, keep the filling in.

Three consequences that follow, each of which cost something to learn:

1. **Tools are coarse.** Given `resolve_links`, `set_publish` and
   `publish_section` separately, and asked to publish tomorrow's class *and
   everything it links to*, the model chose `publish_section` 8 times out of
   8 — skipping the link resolution. Perfectly consistent, and wrong. One
   `publish_class_on` that resolves links itself: right 8 of 8.
2. **Fixed phrasings never reach the model.** The card's unambiguous shapes
   are matched in code. If you reword one, update the matcher too, or the
   shortcut silently stops firing and the phrasing quietly starts being
   routed instead — it will look correct and behave worse.
3. **Absence is the guardrail.** There is no delete tool, so "delete the
   Unit 1 folder" cannot be honoured however confidently it is asked. Not
   judgement — no route.

### Rules belong in the tool, never in an argument

`publish_pages` and `unpublish_pages` used to take an `includeLinked`
boolean with no default, so the MODEL decided. That is the same reasoning
this design exists to keep out of the model, and a boolean is the thing that
inverted polarity on the 3B. It is gone, and the rules are now code:

**Publishing always publishes the pages it links to.** Never publish a page
whose links lead somewhere students cannot see — that is the whole point.

**Unpublishing is NOT the mirror**, and this asymmetry is deliberate:

- unpublish the named page(s);
- also unpublish a linked page **only if that page is linked to ONLY by the
  page(s) being unpublished**. If anything else still links to it, it stays —
  otherwise you create the dead links the publish rule exists to prevent;
- **never** unpublish, whatever the link count: a folder's landing page
  (`index.md` — Concepts, Investigations…), any page in that section's **Key
  Links**, or any **Curriculum** page (detect with `build_site.py`'s own
  rule: any folder segment containing "curriculum").

The plan should say what it **kept** and why — "Ohm's Law stays: Unit 3,
Day 2 still links to it" — not only what it removed. A teacher needs to see
the tool reasoned about it, or they will check by hand and the rule has
bought nothing.

#### Never ask the model for something the window already knows

The tools take `course` and `section` as arguments, and for a long time the
model filled them in. It should never have been asked: the assistant window is
opened FOR one section and its title says so.

The failure this produced is instructive because it is not a stupid one.
**"Unpublish Unit 4, Day 12" was read as section 4**, and the teacher was told
their course has no Section 4 — a perfectly reasonable misreading of a page
name that begins with a number, and one that no amount of describing the
argument would prevent on the next page name that does. It happened more than
once before it was fixed.

So the agent overwrites both arguments with the window's own before anything
runs. It cannot cost routing accuracy, because it changes nothing the model
reads — only what is done with what it said.

**Do this in the agent, not in the tool.** The same tools answer Claude Code
over MCP, where the course and section genuinely ARE the caller's to choose.
It is the window that is about one section, so the window is what binds them.

Worth a sweep of your own surface for the same shape: any argument the
surrounding context already determines should be overwritten on the way in
rather than described more carefully in a schema.

#### A corollary, learned the expensive way: do not fix routing with words

When a probe routes to the wrong tool, the tempting fix is a sentence in the
tool's description telling the model when NOT to use it. **Measure that
before you keep it.** We did, and it was worse.

The case: `publish_pages` takes an optional date range, and a typo'd "publsh
tomorows class … and the stuff it links to" chose it 10/10 with no page named
and an open-ended start date — one lesson turning into the rest of the term.
Adding *"NOT for one day's class — for a single day use publish_class_on"* to
the description fixed that probe and **broke three others**: "Publish Unit 2,
Day 3", a named page with no date in it whatsoever, went to
`publish_class_on` 10 times out of 10, and the window's own suggestion cards
fell from 110/110 to 90/110. A small model reads a sentence naming another
tool as a recommendation rather than a boundary, and it does not reliably
notice which half of a sentence applies to it.

The wording was reverted to the byte and the rule became a conditional in the
tool: an open-ended publish (no pages named, a start date, no end date) is
REFUSED, with a message saying to use `publish_class_on` for one day or to
give both dates for a stretch. Three properties make that better than the
sentence:

- it changes nothing the model reads, so it **cannot** cost routing accuracy
  and needs no re-measurement;
- it is exact, where a description is a hint;
- the refusal comes back as ordinary text, so the model corrects itself on
  the next turn rather than failing at the teacher.

Applied to publishing only. An open-ended UNPUBLISH hides work rather than
exposing it, the same backup undoes it, and a teacher clearing a section back
to a date is a real thing to want.

**The general rule: prompt text is a gamble that has to be re-measured across
the whole suite; a conditional is not.** If you change any description, re-run
every probe, not the one you were fixing — that is the only reason we caught
this instead of shipping a regression that looked like a fix.

#### And when you REMOVE a tool, audit the refusals that pointed at it

Cutting `remember_timetable` from the local list was right — dates the model
supplies are dates it may have invented — but it left three refusals saying
"record them with `remember_timetable` first". The model can no longer see
that tool. **A remedy naming something unreachable is worse than no remedy**,
because the next move available to a model that cannot follow the instruction
is to improvise the dates, which is the exact failure the removal was meant to
prevent.

Two things had to follow the cut, and only one of them was obvious:

1. The messages now name no tool. They say what is missing and that the app is
   asking the teacher — which also stays true over MCP, where the client's
   tool list is different again.
2. **Something else has to actually ask.** On macOS a schedule sheet collects
   dates (typed, from a file, or from a shared sheet link); the tool leaves a
   request and whichever assistant window is showing that section presents it.
   That sheet existed and was already attached to the window — the call that
   sets the request was simply never written, so nothing ever opened it. It
   looked finished from every angle except running it.

So: **if Windows has no equivalent way to ask, `remember_timetable` must stay
on its local list.** The cut is only safe because something else asks. And the
audit worth running after any removal is not "does the surface still route"
but "can every refusal still be acted on by the surface that receives it".

### What the assistant's window must BE — and what it need not look like

Decided 2026-08-16, in answer to "must the bubbles match?" — **no.** The mac's
bubble geometry (13pt insets, 17pt corner radius, Messages' grey and its light
blue selection) was measured against Messages on the same screen, and copying
those numbers onto Windows would produce something that looks like a Mac
application running in the wrong place. **Build a chat that looks at home on
Windows.** WinUI's own type ramp, its own spacing, its own accent colour. Read
the mac's chat sections below for what the arrangement has to achieve, and
ignore the numbers.

What is NOT negotiable is the shape of the interaction, because that is the
product rather than the platform:

1. **It is a CHAT.** Not a form, not a command palette, not a properties panel
   with a text box on it. A teacher types a sentence and gets a sentence back.
2. **Everything goes through the chat — input and output both.** No result
   appears only in a status bar, a toast, a dialog, or a log pane. If the
   assistant did something, the conversation says so, in the conversation.
3. **The one exception is confirming an action**, where buttons appear — as
   they do on the mac for a deploy or a plan. A teacher agreeing to publish to
   students should not have to type "yes" and hope it was understood.
4. **What the teacher chose with a button goes into their chat history**, in
   their own bubble, as though they had typed it. Reading back a conversation
   where the assistant asked, nothing answered, and something plainly happened
   is worse than not being able to read it back at all. The two contract
   scenarios "the deploy card is agreed to" and "the deploy card is cancelled"
   assert exactly this, so your suite can check it rather than your eyes.
5. **A thinking indicator is a MUST.** The local model takes seconds and the
   toolchain takes minutes, and a window that sits still through either one is
   indistinguishable from a window that has crashed. The mac shows one
   indicator for BOTH thinking and running a tool, deliberately: a teacher does
   not care which of the two the assistant is busy with, and two indicators
   invite the question. It hides while a card is waiting for a button — nothing
   is happening then, the teacher is.
6. **Up and Down walk back through what was asked before, as a Terminal
   does — the SAME KEYS as the mac.** Not a per-platform choice: a teacher who
   learns Up on one machine and finds it somewhere else on the other has
   learned nothing. It is also a requirement rather than a nicety — it is how
   somebody re-runs the thing they just ran with one word changed. The
   semantics are in `contracts/assist-cases.json` under `promptHistory`: eight
   step-by-step cases, the key names, and the two situations where the arrows
   must instead do their ordinary job and move the caret (a box holding more
   than one line, and nowhere further to walk — pass the key on rather than
   swallowing it, because a key that silently does nothing reads as a dropped
   keystroke). The two cases that get missed: the half-typed line is put aside
   and handed back rather than lost, and typing ends the walk so Down cannot
   silently replace what was just written.

And the rule that governs all of it, from row 1 of the improvement log: **the
window never names the machinery.** No tool names, no model names, no tokens,
no containers. "The small assistant" and "the larger assistant".

### The parts of those four areas that could NOT be a contract

`shared-rules.json` carries the rules. These are the neighbouring pieces that
are yours, written here because "not in the contract" must never mean "nobody
mentioned it".

**Scheduled deploys — the mechanism, and one refusal that may differ.** Writing
a plist and writing a scheduled task have nothing in common, so only the
refusals are shared. But one of them is a genuine fork: the mac refuses
Cloudflare with no Account ID **because it can pass `--account` in the plist and
therefore has to ask once, up front**. If a Windows scheduled task still cannot
be handed an account, then Cloudflare is not schedulable there at all — and the
right answer is a refusal that SAYS so, not a task that fails at 06:30 in
silence. Check it, and record what you find in `MAC-HANDOFF.md`; the contract
case says which of the two you are looking at.

Two more that stay yours: the plan's own words (the mac's says what has to be
true of the Mac — awake, plugged in, lid open — and yours will say something
different about sleep and Modern Standby), and cancelling, which on the mac is
`launchctl bootout` plus deleting the plist.

**The sidebar filter — the empty state.** The contract says WHAT matches. It
does not say what a teacher sees when nothing does, because that is a view: the
mac shows a short sentence rather than an empty pane, and the rule behind it is
that an empty list looks like a broken app while a sentence looks like an
answer. Say something; the words are yours.

**The transcript — everything except the stripping.** What is stripped is
shared (a colour code is a colour code). How much scrollback is kept, when the
view follows the tail, whether it scrolls on focus — all yours, and all
different in WinUI.

**Curriculum — the plan, not the recognition.** What COUNTS as an expectation
is shared and must be, because `build_site.py` decides what ships and an app
that disagreed would report coverage the site does not have. What a coverage
plan SAYS to a teacher, and how it is offered, is yours.

### The working-folder path bar — reported missing in use, 2026-08-16

The bar under the sidebar that reads "Working folder: … › … › Courses". On the
mac it does four things; on Windows the `BreadcrumbBar` currently does one, and
the difference was found by a teacher using it rather than by any test, which
is the point of writing it down now.

| What | mac | Windows today |
|---|---|---|
| Click a crumb | selects nothing — see below | **reveals it in File Explorer** |
| Double-click a crumb | opens that folder | nothing |
| Right-click a crumb | menu: **Show in Finder** / **Open Folder** | **no menu at all** |
| Hover a crumb | tooltip with the full path | nothing |
| Each crumb shows | the real folder icon + display name | name only |

**The two actions are genuinely different and a teacher wants both.**
*Revealing* opens the folder's PARENT with the folder selected — it answers
"where does this live?". *Opening* opens the folder itself — it answers "what
is in it?". Collapsing them into one gesture loses the other question, and
which one survives is arbitrary. The gestures follow the host file manager
deliberately, so a teacher who has used Finder or Explorer already knows them:
double-click opens, right-click offers both.

**Every crumb is live, not just the last.** That is how a teacher reaches the
folder ABOVE their working folder — to make a sibling, or to see where things
sit — without leaving the app to go and find it.

The testable half is in `contracts/shared-rules.json` → `workingFolderPathBar`:
the crumb list (every ancestor, root first, folder last — on Windows starting
at the drive rather than at `/`), the two actions with each platform's label,
and the gestures. The labels differ on purpose: "Show in Finder" against
"Show in File Explorer".

**The general lesson, which is why this went unnoticed for months.** An
affordance that lives ONLY in a context menu is invisible to everything: no
screenshot shows it, no test on the other side asks for it, and the person
building the other app has no way to know it exists. When a change adds a right
-click menu, a double-click, a hover, or a keyboard shortcut, it needs a line
here **even though nothing on screen changed** — those are exactly the changes
a diff of the UI will not reveal.

### A second: the wizard's own answer keys, and the skeleton question

`course_config.json` carries two GROUPS of keys, and only one of them is the
settings form's. The other three are written once by the wizard, and
`setup_course.py` reads each as the DEFAULT for a question it would otherwise
ask:

| Key | What it decides |
|---|---|
| `use_skeleton` | Whether a course with no ready-made payload starts from its subject's skeleton — folders that suit the subject, four units of class pages to rename, placeholders saying what belongs where — or from nothing at all. |
| `prepopulate_example_content` | Whether one of the 37 ready-made courses is poured in. |
| `include_curriculum_pages` | Whether that payload's Curriculum folder comes with it. |

**`use_skeleton` is not written by the Windows wizard at all** (checked
2026-08-16). The Python then falls back to its own default — `True` — so a
Windows teacher gets a skeleton and is never asked. That is the question MOST
teachers meet, because around 1,900 course codes have a skeleton and no
payload; only 37 have a ready-made course.

**Decided 2026-08-16: match the mac — ask the question and write the answer.**
The alternative was to always start from the skeleton and write
`use_skeleton: true` explicitly, which was defensible; the reason it lost is
that this is a real choice a teacher has, and the two apps should not differ on
whether a teacher gets to make it. Silence was never an option either way,
because the next change to that default in the Python would move Windows and
not the mac.

The mac writes each of these as `capabilityExists && teacherSaidYes` —
`hasSkeleton(code) && startsFromSkeleton` — so a stale `true` in an old config
can never mean anything.

### A divergence flagged by sweeping, 2026-08-16 — checked again 2026-08-23, not present

`deploy.py` writes a marker the first time a section goes out —
`.netlify_sites/section<N>.json` or `.cloudflare_sites/section<N>.json` — and
both apps read it to answer "has this ever been deployed?". That answer decides
whether a scheduled deploy is allowed, because a FIRST deploy asks what to call
the website and nobody is awake at 06:30 to answer.

The mac reads the marker for the destination the course is configured for NOW.
This section originally warned that `AssistWorkspace.cs` accepted EITHER
folder — so a course deployed to Netlify and later switched to Cloudflare
would read as "already deployed" on Windows, letting a teacher schedule the
one deploy guaranteed to stop at a prompt in the dark. **Re-checked 2026-08-23
(item 7 above): that is not how the current code behaves.**
`DeployCommand.HasDeployedBefore`/`FirstDeployMarkerPath` are keyed by the
specific destination type, and every caller passes the CURRENT destination's
type — never both. A regression test
(`ScheduledDeployTests.ASwitchedDestinationIsNotConsideredDeployedJustBecauseTheOldOneWas`)
now pins exactly the switched-destination scenario this section described.

The rule and the paths are in `contracts/file-formats.json` →
`firstDeployMarkers`, including the third case: a folder deploy keeps no
marker at all and counts as always-deployed, because it asks nothing. That
file's `knownDivergence` field, which used to describe this Windows bug, is
now removed.

Worth knowing how this was found: not by a failing test, but by walking
`documentation/07-deployment.md` and asking which of its facts anything
verifies. Several of these contracts came out of reading the documentation
against the code that way.

### Two things to MEASURE on Windows rather than copy from the mac

Both are in the contracts, and both would be wrong to implement by reading the
mac's answer. They are small, and each is an hour that turns into a day when
skipped.

**1. Whether the browser needs `127.0.0.1` instead of `localhost`.**
`app-rules.json` → `linkRules.browserSafe` says the mac rewrites the preview
address before handing it to the browser. The reason is specific to Safari: it
tries IPv6 (`::1`) first for "localhost", the container publishes the port on
IPv4 only, and the failure reads to a teacher as "the server dropped the
connection" — not as anything to do with addresses. **Find out what Edge does**
before deciding you need the same rewrite. Open a preview, then try
`http://localhost:<port>` in Edge by hand. If it connects first time, drop the
rewrite and say so in `MAC-HANDOFF.md` — that is a finding, not an omission,
and the contract should then note that the rule is mac-only. If Edge behaves
the same way, keep it and the contract stays as it is. **Still open as of
2026-08-23** — Windows already applies the rewrite (`OutputParsers.cs`,
`SectionDetailView.xaml.cs`), but with the mac's generic rationale copied into
the comment rather than a recorded Edge test. Low-risk to leave as-is; still
worth doing the hand test and recording the result either way.

**2. Which progress markers you must match, and which are yours to write.**
`app-rules.json` → `markerOrigins` classifies all twenty-five. Seventeen come
from `scripts/*.py`, which both platforms run, and must match to the
character. Seven come from the launchers, which exist separately as `.sh` and
`.ps1` — those you write, and they already differ. One is "elsewhere"
(`Quartz v4`, from the build) and wants a human to look.

**This example is now WRONG and is kept only as a warning: an earlier version
of this section said "the mac watches for 'Setting up this Mac' where
`setup.ps1` prints 'Setting up this PC'."** `setup.ps1` printed that once, but
stopped the day Windows moved to a fully native toolchain (`b356a1f`,
2026-08-19, "Native toolchain (no container)" in `setup.ps1`) — no WSL2, no
Docker, no one-time machine setup, no container to start at all. Nobody
updated `TaskMilestones.cs`'s launcher markers to match, and nothing caught
it for four days: `Setting up this PC`, `Building your website builder`,
`Ensuring container is running`, and `Starting container if needed` all sat
in the milestone lists matching text that could never appear again, so the
first two-to-three stages of most progress bars silently could never be
reached — fixed 2026-08-23, see item 5 above and `GUI-IMPROVEMENTS.md` row
352. **The lesson: "read your own `.ps1` files" is not a one-time
measurement, it is a claim that rots the moment those files are rewritten.**
`TaskMilestoneLauncherMarkerTests` (`ParsingTests.cs`) now reads the actual
`.ps1` files rather than trusting a milestone list frozen in C#, specifically
so the next launcher rewrite fails a test instead of silently stalling a
teacher's progress bar again.

**Do NOT copy the mac's seven launcher markers into your milestone lists.**
Read your own `.ps1` files and match what they actually print. This fails
silently in the worst way: the app does not crash, the progress bar simply
stops advancing part-way and then jumps at the end, which reads as a slow
build rather than as a bug — and the only way to notice is to watch a whole
deploy with the old and new bars side by side.

### Do not re-derive Plantoir's tests — read `contracts/`

**This is the section that saves you a day per sync.** Six JSON files, written
by the macOS binary, meant to be read by `Plantoir.Tests`. It started as the
assistant's contract and is now the whole product's:

| File | What it holds |
|---|---|
| `contracts/assist-wording.json` | Every sentence the assistant says to a teacher — nineteen, with `{course}` and `{section}` where values go. |
| `contracts/assist-cases.json` | The nine phrasings matched in code, the four near misses that must NOT match, the three tool lists with approvals and plan twins, **the full tool SCHEMAS as a client sends them**, eight scenarios as `given` / `when` / `expectEvents` / `expectReply`, and the arrow-key prompt history. |
| `contracts/app-rules.json` | Launcher arguments per configuration, the validation a teacher reads, failure output turned into a sentence, whether a deploy must build first, the progress markers and where each one's text comes from, the preview's ports. |
| `contracts/schedule-rules.json` | Every accepted date form, how an ambiguous `08/09/2026` column is settled or asked about, what a pasted Google Sheet address becomes. |
| `contracts/class-planning.json` | Which titles carry numbers, what the next class is called, and the ORDER renames must run in. |
| `contracts/course-management.json` | The three kinds of zip and how they are told apart, the section number offered next and the refusals, grade labels from a course code. |
| `contracts/file-formats.json` | Every `course_config.json` key with type and default, and the frontmatter that decides who sees a page — `publish:`, the legacy `draft:` that means the opposite, and the per-section keys. |
| `contracts/shared-rules.json` | What a scheduled deploy refuses and in what ORDER, what the sidebar filter shows, what is stripped from the launchers' output, and what counts as a curriculum expectation. |

An xUnit `[Theory]` with a `MemberData` source that deserialises these is the
whole integration. Nothing in them is macOS-specific: the sentences are the
product's and the sequences are the toolchain's.

**Why this exists.** Every wording change on the mac used to reach you as prose
in `GUI-IMPROVEMENTS.md` and a paragraph here, which you then retyped as tests
by hand — a day of it, and the sentences drifted the moment one side edited
without telling the other. They had been living in four places at once, and
three were already wrong: the identical deploy failure said "the output is in
that section's console in Plantoir" from one code path and "…that section's
window in Plantoir" from another, so which sentence a teacher got depended only
on whether a window happened to be open.

**How it stays true.** `Plantoir --write-contracts contracts` writes all three
files from `AssistWording`, `AssistCardCommand`, the tool surface and
`TaskMilestones`, and the contract tests run the same generator in-process and
fail when what is committed disagrees. A changed sentence therefore fails on the mac in the same
run that changed it, and reaches you as a **diff in `contracts/`** in the same
commit as the Swift. Verified by breaking a sentence on purpose: the suite
failed naming the key and the command to regenerate.

**Four things to know before you use them.**

- **Never hand-edit the GENERATED keys** — `cardPhrasings`, `tools`,
  `milestones`. Those are readouts of mac code; the next regeneration
  overwrites your edit and the diff looks like vandalism.
- **Write the entry to the template.** `MAC-HANDOFF.md` opens with "How to
  write an entry" — title and source, what it fixed and WHY (including what
  was rejected), numbers with the hardware they came from, the file and test
  names to look at, and whether the mac must match it or merely know. That
  file also has a **"Contract cases waiting on the mac"** section at the top,
  which is where a proposed case gets named.
- **You CAN propose an authored case.** `scenarios`, `nearMisses`,
  `promptHistory` and the case lists in the other files survive a mac
  regeneration untouched, so a behaviour you invent can be written as a case
  here — and the MAC suite will then fail until the mac implements it. That is
  the mechanism working, and it has been verified by doing it on purpose. Name
  the case so it reads as a proposal and log it in `MAC-HANDOFF.md`, or the
  failure looks like damage rather than a request.
- **`expectEvents` is an ORDER, not a set.** Every incorrect ordering passes a
  test that only checks all three events occurred — which is exactly how the
  mac shipped a preview that stopped after the writes it was meant to protect.
- **The event names are the contract's own**, deliberately not Swift's. Map
  `stopPreview.begins` / `stopPreview.ends` / `deploy` / `write` /
  `startPreview` / `runLauncherDirectly` onto whatever your app calls them.
  Two `given` flags decide the interesting cases: `sectionWindowOpen: false`
  is the headless path (`Plantoir.Mcp`, and a scheduled deploy), and
  `previewRunning: true` is the case Windows currently gets wrong.
- **Replies are NAMED, not quoted** — `wording.deployed`, not the sentence.
  Look them up in the wording file and substitute `{course}` and `{section}`
  yourself. A test that quotes its own copy of a sentence is how this problem
  started.

**What the contract CANNOT do, so you still write these tests yourself.**
The list is short but each item is a real gap, and a gap nobody names is a gap
both sides assume the other is covering:

| Not in the contract | Why not, and what to do instead |
|---|---|
| **Routing accuracy** | Whether the model picks the right tool for a sentence it actually sees is a measurement, not an assertion — it varies by model, quant and context size. Measured against a real `llama-server`; see [`research/`](research/README.md). The contract can say "deploy now" never reaches the model; it cannot say what the model does with a sentence that does. |
| **Anything with platform mechanics** | How a preview is stopped (WSL2, ConPTY, port leases, container naming) is yours. The contract says a stop must FINISH before a deploy begins; it cannot say what finishing means on your side. |
| **That an await is really an await** | This is the subtle one. The ordering assertion only proves anything if your fake preview emits the stop as TWO events with a real suspension between them, as the mac's does (`stopPreview.begins` … `stopPreview.ends`). A fire-and-forget stop that happens to complete quickly will satisfy a single-event fake and ship the bug the ordering was written to catch. |
| **Transcript composition** | The scenarios assert that named lines appear IN ORDER, never that they are adjacent or last. After an approval the tool's own result is the final line on the mac, and your renderer may differ. Order is portable; arrangement is not. |
| **Anything visual** | Bubble geometry, toolbar disabled states, progress headers, window layout. The contract has no vocabulary for these and should not grow one — that is what `GUI-IMPROVEMENTS.md` is for, and what a screenshot settles in a minute. |
| **Launcher arguments** | That a Cloudflare course deploys to Cloudflare is enforced on the mac by one function (`DeployCommand.arguments`) and by a unit test, not by the contract. If your `Plantoir.Mcp` or scheduled task composes its own arguments, write that test on your side — the bug is silent, and the site simply appears on the wrong host. |
| **Plan mode's offer to stop asking** | Tier-dependent (the smaller assistant cannot turn plan mode off at all), so it is a mac measurement and a mac rule until Windows has measured its own tiers. |

If you find yourself wanting to add one of these to the contract, the answer is
usually a second file rather than a stretched first one — `contracts/windows-*.json`
for behaviour only your side has.


### The tool descriptions are measured, so compare against the contract

`assist-cases.json` → `toolSchemas` now carries the tool definitions **exactly
as each client sends them** — name, description and parameter schema, for both
the 13-tool local surface and the 23-tool MCP one.

The descriptions are the part to take seriously. They are measured artifacts,
not commentary: the "TEACHERS SAY:" phrasings came out of the routing suite,
and one added clarifying sentence in `publish_pages`' description took the
promise-card score from 110/110 to 90/110 and broke three probes that had been
perfect. A small model reads a sentence naming another tool as a
recommendation, not a boundary. **Steer with code, never with a description.**

Two things follow for your side. Compare your own schemas against these rather
than against a description of them — a drifted description is a routing change
nobody will attribute to a wording edit. And when you measure routing against
your own backend, take the surface from the contract:

```
python3 research/ai-assist/tools-from-contract.py local > /tmp/real-tools.json
python3 research/ai-assist/shipped-surface-suite.py 8099 10 /tmp/real-tools.json
```

The suites are plain Python over `http://127.0.0.1:<port>/v1/chat/completions`,
so they run anywhere a llama-server does. `routing-suite.py` is marked
HISTORICAL and hand-writes five tools; do not measure the shipping surface with
it.

### The model's list is SHORTER than the server's

Two lists, deliberately. `definitions` is what the local model sees;
`mcpDefinitions` is what Claude Code sees over MCP. Same tools, same runner,
same rules — the model is simply shown fewer.

- **The `plan_` twins are hidden from the model.** Plan mode calls them from
  CODE when the model picks a write, so the model never needs to name one.
  They were about 30% of the prompt buying nothing. Claude Code KEEPS them:
  it has no plan mode and genuinely needs to ask "what would that do?".
- **`remember_timetable` is hidden from the model.** It takes dates as
  strings, so dates the model supplies are dates it may have invented — and
  a wrong one schedules a class on the wrong day silently. The schedule UI
  owns that path. `read_remembered_timetable` stays, because reading is safe.

Result: 20 tools down to **13** for the model — the six `plan_` twins and
`remember_timetable` are the seven taken off the list. (An earlier draft of
this note said 12; the cuts named above come to 13, and the code and its
tests say 13.) The thirteen are `list_pages`, `read_page`, `check_section`,
`publish_class_on`, `publish_pages`, `unpublish_pages`, `rebuild_preview`,
`undo_last_change`, `deploy_section`, `schedule_deploy`,
`cancel_scheduled_deploy`, `read_remembered_timetable`, `add_next_class`.
Worth doing on Windows too — the routing figures were measured at 15, so a
surface that grows past that is spending accuracy, and one that shrinks below
it should be spending less.


## Quartz serves the OLD site before it builds the new one

This one is inside Quartz, so it is yours as much as ours, and it is invisible
until somebody edits a page and looks.

`quartz build --serve` does this, in this order (its own `cli/handlers.js`):

```
server.listen(argv.port)
console.log("Started a Quartz server listening at http://localhost:PORT")
await build(clientRefresh)
```

**It starts serving the existing `public/` before it rebuilds it.** So the
moment a preview launches, the server answers `200` — with the PREVIOUS build.
The fresh one lands seconds later.

Anything that decides "the preview is ready" from the server responding will
therefore show the site as it was BEFORE the teacher's change, with nothing on
screen to suggest it. Ours did, and the symptoms were maddening in a specific
way worth recognising:

- editing a page, previewing, and seeing the old page;
- stopping and starting the preview, and still seeing the old page;
- **doing the same thing slowly and having it work**, because the build had
  quietly finished in the meantime;
- pressing Reload by hand and having it come right.

We suspected three innocent components before finding this — the merge, the
build, and our own web view — and every one of them was provably correct: the
merged content, the built `public/`, and the file timestamps all showed a
current site while the screen showed an old one.

Two rules follow:

1. **Wait for the BUILD, not for the server — and watch the OUTPUT FILE, not
   the console.** Note the time before launching the build, then wait until
   `<section>/public/index.html` is newer than that. It means exactly what has
   to be true before a teacher is shown anything, and unlike Quartz's progress
   lines it cannot be changed by a version bump or swallowed by a spinner. We
   tried matching its emit line first; the file is strictly better.
1b. **Clear the web view's caches before loading, not just its cache policy.**
   A Quartz site is a single-page app: a no-cache policy governs the main HTML
   request while the scripts, styles and the content the page fetches for
   itself still come from the cache — so a fresh index.html can still assemble
   the previous site out of parts. This looked exactly like a build problem
   and was not. Clear disk, memory and fetch caches; leave local storage and
   cookies alone so the preview keeps its light/dark setting.

2. **Reload only when you never saw that line.** We first reloaded
   unconditionally, as cheap insurance, and it was worse than the problem it
   insured against: every preview in the app flickered, for a case that by
   then could not happen. The signal tells you which situation you are in, so
   let it decide — no line, no certainty, so reload; line, so leave the
   teacher's page alone.

Bound the wait (we allow 120 seconds) so a Quartz that never prints the line
cannot leave a teacher watching a spinner: show the preview anyway, and that
is exactly the case the conditional reload covers.

## What the conversation looks like, and why

The assistant window is a CHAT, not a form with a log under it. That was a
deliberate change and it is worth stating why before the numbers: a teacher
asking for something, being told what would happen, and agreeing to it is a
conversation, and a window that looks like one is a window they already know
how to use. Nothing here has to be taught.

**One decision is yours, not ours.** These specs describe macOS Messages,
because that is the chat every Mac teacher already has open. The Windows
equivalent may be better served by looking like Windows — Teams and Phone Link
have their own bubble idiom, and a Mac-shaped chat on Windows can read as
foreign rather than familiar. What must carry across is the STRUCTURE (who is
on which side, what counts as a message, when a turn ends); the exact
curvature is a local decision. If you do choose to mimic your platform's
chat, measure it the way we measured ours — see the last paragraph.

### The two sides

| | Teacher | Assistant |
|---|---|---|
| Side | right | left |
| Fill | blue, RGB **(20, 147, 255)** | dark: **(59, 59, 61)**; light: **#E9E9EB** — flat, never translucent |
| Text | white | the ordinary label colour |

**Do not use the system accent colour for the teacher's side.** We did, and it
is a latent bug rather than a shade being slightly off: the accent is whatever
the user chose in system settings, and set to graphite it makes the teacher's
bubbles the same grey as the assistant's — at which point the left/right,
blue/grey distinction the whole window depends on silently disappears. The
blue is its own constant.

**The assistant's grey is a constant too, not a translucent token.** Ours was
"a system grey at 16% opacity" for a while, and a translucent fill can only
ever be as light as the window behind it allows — measured side by side on
the same backdrop it sat visibly darker than Messages'. Flat colours, both
appearances.

### The bubble

Ten rounds of measuring against the real thing, each round correcting the one
before (`GUI-IMPROVEMENTS.md` rows 177–178 have the blow-by-blow). The final
geometry, in points at 13pt text:

| | |
|---|---|
| Corner radius | **17** — an absolute of the design; it does NOT scale with the font |
| Radius rule | `min(17, height/2, width/2)` — single-line bubbles fall out as capsules, no separate branch |
| Visible text inset, each side | 13 |
| Text inset, top and bottom | 7 |
| Tail size | an absolute, like a pen width — one size on every bubble (`tailScale` = 17) |
| Tail drop BELOW the body | 5.1 (0.30 × tailScale) |
| Corner landing on the bottom line | 0.47 × radius — the one tail number that follows the radius |
| Tail tip, INSIDE the body's edge | 6.5 (0.38 × tailScale) |
| Hook rejoins the bottom edge | 14.5 in (0.85 × tailScale); root width ≈ 6.5 |

The two costliest wrong assumptions, both of which survived several rounds:

- **Nothing scales with the font.** The radius measured the same across two
  text sizes; so did the whole tail. An early pass scaled both down by our
  smaller font and every bubble read as subtly wrong beside Messages. (The
  OLD version of this section said the opposite — "scale the proportions to
  the corner radius". That advice cost us three passes. Constants.)
- **Cross-app constants come only from screenshots with BOTH apps in them.**
  Deriving one from two separate captures needs each capture's
  pixels-per-point; we guessed one wrongly and shipped a tail a fifth too
  large. Same screenshot, same screen — the scale cancels out.

Drawing the outline (still one continuous path, not a rectangle plus a
triangle):

- **The corner-to-tail joint is about the TANGENT.** The silhouette reaches
  its deepest inset exactly at the bottom line while travelling straight
  DOWN. A corner that lands travelling horizontally meets the tail in a cusp
  and the tail reads as a comma stuck under the bubble.
- **The jog into the tail gets exactly the radius of height**, held nearly
  flat for the first half with the dive concentrated in the last (a cubic
  with vertical end-tangents; late control ~0.215 of the span, early ~0.30).
  A longer span drifts early and reads as a diagonal cut into the side; a
  weighting that carries inset early reads as the bubble bulging.
- **No sharp vertices anywhere.** The tip is rounded about 1.5pt across, and
  the hook meets the bottom edge in a small curve, not a corner.
- **The underside of the tail is CONCAVE** — a diagonal with a mild sag
  toward the bubble, not a deep scoop. That curve, not the tip, is what makes
  the shape read as a tail.
- **Draw inside the bounds you are given.** Ours drew past its rect at first
  and was clipped — a clipped tail is severed, not pointed.

### Selecting text in a bubble

Messages pins its selection colours the way it pins its bubble colours:
light-appearance selection blue **(174, 218, 255)** behind the selected run
in BOTH appearances, with the selected glyphs painted in the bubble's own
fill. The system's dark-mode selection colour is a grey-slate that reads as
broken beside it. Two porting notes: our UI toolkit's built-in text selection
drew an unstylable grey and we had to drop to the native text control to
style it at all — check yours early; and the hook that styles selection must
be one that runs when selection machinery actually attaches (ours had a
first attempt that configured a text editor that did not exist yet, and it
failed silently).

### Tails mark turns, not messages

One tail per RUN: on the last thing a participant said before the other one
answered. A tail on every bubble makes three sentences look like three
separate attempts to get a word in — and it is the kind of thing that looks
fine in a screenshot of two messages and wrong in a real conversation.

The newest message always has a tail, since its turn has not been answered
yet. Anything nobody SAID — we have one such item, a note that a restore
happened — wears no tail and does not end anyone's turn; the rule looks past
it to the next thing that was actually said.

### What counts as a message

More things than you would first assume, and this is the part that matters
most for how the window reads:

- **What the assistant says.** Obviously.
- **What the teacher types.** Obviously.
- **Tool results.** "The preview is rebuilding now" is the assistant
  ANSWERING. That it came from a tool is machinery, and the teacher is not the
  audience for machinery. As plain lines with an icon these read as a log
  spliced through a conversation.
- **The plan.** It used to live only in the approval card, so pressing Go or
  Cancel destroyed the description of what had just been agreed to — and with
  it the context for everything after. A conversation you cannot scroll back
  through is not a conversation.
- **The question.** "Shall I go ahead?" / "Shall I deploy?" is its own
  message, which is what lets the card below be nothing but buttons.
- **The teacher's ANSWER.** Pressing Go records "Go" as a teacher message, in
  their bubble on their side. Reading back a conversation where the assistant
  asked, nothing answered, and yet something plainly happened is worse than
  not being able to read it back at all.

The general rule: **anything that is part of the conversation belongs IN the
conversation, and a control that owns text destroys that text when it
resolves.** Leave controls the choice and nothing else.

### The typing indicator

**A THOUGHT bubble, not a speech bubble** — a capsule with two plain circles
stepping down toward the speaker, the comic-strip sign for thinking, shown on
the assistant's side whenever the model is thinking or a tool is running —
both are waits with nothing on screen, and a teacher does not care which.
Ours wore the speech tail for a while and it read as off without anyone
being able to say why: a tailed bubble means SAID, circles mean composing.

Measured from a screen recording of Messages, as ratios of the capsule's
height (which equals a single-line message bubble, so the indicator occupies
the slot of exactly the thing it stands for): capsule ~1.7× as wide as tall;
dots 0.24 of the height with a gap about half a dot; the larger circle 0.41,
poking about two points past the lower corner; the smaller 0.14, below and
outside with a sliver of gap. Each dot lags the one before it (about 0.18s)
so the three read as a wave rather than a blink.

**Draw the capsule and both circles as ONE geometry filled once** (whatever
your platform's path-union is). As separate shapes, any translucency doubles
where they overlap and the join shows as a brighter seam.

### The box you type in

- A rounded field — continuous rounded rectangle, radius 17 — with the send
  button INSIDE its right end, rather than a plain field with a button parked
  beside it.
- **Never disable it to mean "busy".** A disabled field cannot hold keyboard
  focus, so the system moves focus to the next thing it can find; ours landed
  on the first disclosure group in the suggestion shelf, which looks like a
  bug in something else entirely. Typing and SENDING are separate
  permissions: the box stays live so a teacher can write their next message
  while they wait — every messaging app allows this — and only the send waits
  for the run to finish.
- **Focus returns to it after every send.** Two commands in a row should not
  need a click in between. This is also what keeps the arrow-key history
  usable, since that depends on the field having focus.
- Up and Down walk the teacher's own previous messages; see the history rules
  recorded in `GUI-IMPROVEMENTS.md` row 157.

### Two small things that are easy to skip

- **Emphasis has to be rendered.** Plans mark their headings bold, and in
  SwiftUI `Text(someStringVariable)` does not parse markdown at all — only
  string literals do — so it reached the teacher as literal asterisks until
  the text was parsed explicitly. Whatever your toolkit is, check how it
  treats a runtime string; several style literals only.
- **The suggestion chips take the pointing-hand cursor.** A plain button style
  keeps the look and suppresses the cursor, so it has to be put back by hand.

### How to get this right in less time than we did

Measure — and close the loop. Guessing produced wrong shapes; one screenshot
and a twenty-line script that read the pixels produced right ones in minutes.
The full method, each part of which was learned by paying for its absence:

1. **Trace silhouettes, don't eyeball.** Per-row min/max of the fill colour
   gives the exact edge profile; every number in the tables above came out
   that way.
2. **Only same-screenshot comparisons.** Both apps in one capture, or the
   pixels-per-point uncertainty eats the answer.
3. **Render YOUR result and measure it the same way.** The passes that
   shipped wrong all trusted arithmetic about what the code would draw;
   the passes that stuck rendered the real control offscreen and walked its
   pixels against the reference trace. Insets especially: native text
   controls put slack around their glyphs that no spec predicts — our final
   paddings are asymmetric (12 leading, 9 trailing) purely to cancel what
   the label actually draws, and only the render-measure loop could have
   found that.
4. **Expect the reference to correct you more than once.** Ten passes, each
   started by a human eye catching what the previous measurement missed, and
   each ending with the pixels agreeing the eye was right.

## Plan mode, undo, and how often to back up

Three decisions taken on the macOS side on 2026-08-15 that Windows should
match, because they are about how much to trust a local router rather than
about either platform.

### Plan mode: the model says what it heard before it acts

A local router is wrong sometimes. Measured over 290 trials, the small model
puts about **one request in five** on the wrong tool. Plan mode turns that
from something that happens into something a teacher declines: a write runs
its `plan_` twin first, the plan is shown in the twin's own words, and
nothing happens until they press Go.

- **Writes only.** Reads answer immediately. Gating "what do students see
  right now?" makes every question two clicks and teaches people to press Go
  without reading — which costs the gate its whole value.
- **Always on for the small model.** On the 1.5B it cannot be turned off at
  all; 79% is not a rate at which anyone should be handed a "stop asking"
  button. The macOS build ignores a remembered "off" answer when it finds
  itself on that tier, so a teacher who turned it off on a capable machine
  does not inherit that on an 8 GB one.
- **Offered off after five in a row, once, on the capable model only.** Trust
  is earned rather than assumed, and the offer arrives while five correct
  plans are still fresh rather than months later in a settings pane. A Cancel
  RESETS the run: somebody who has just stopped the assistant doing the wrong
  thing must not then be asked whether they would like it to stop asking.
- **Deploys always ask, plan mode or not.** A deploy puts work in front of
  students immediately and cannot be taken back by us.

### Undo is not version control, and it should not pretend to be

Worth stating because it is easy to assume otherwise: **courses are not git
repositories.** Nothing in the toolchain runs `git init`. The undo history is
in-memory before/after snapshots of the files each tool touched, held as a
stack for the life of the conversation, and it is gone when the window
closes.

It has one property worth copying exactly: before restoring a file it
compares what is on disk to what it wrote, and **skips anything the teacher
has edited since**. Publishing a class, then spending ten minutes writing it
in Obsidian, then saying "undo that" must not cost those ten minutes.

### Back up once per conversation, not once per command

The macOS build originally zipped the whole course before EVERY write. On an
Obsidian vault full of images that is slow and large, and a chat with six
commands made six near-identical copies.

It now backs up **lazily, once per conversation**: the first write makes the
zip, later writes reuse it, and a conversation that only reads makes none.
That single zip is also what the assistant's **Restore** offers — putting the
section back to how it was when the chat started, which is the safety net
that makes "just do it" mode reasonable to offer at all.

Two details that make the backups usable rather than merely present:

- **Provenance rides in the file name**, so a teacher choosing among several
  can tell what made each one and why — Plantoir before an assistant chat
  about a particular section, or themselves on purpose. A list of five
  identical-looking timestamps is not a choice anybody can make.
- **Prune only the ASSISTANT's own backups**, keeping its five most recent
  per course. A teacher's backup is a decision — they pressed Back Up because
  they were about to do something they were unsure of — and deleting it on a
  schedule they never agreed to is the app overruling them about their own
  work. The assistant's are different in kind: it saves one per conversation
  whether or not anybody asked, so clearing up after itself is its job. A
  teacher with twenty of their own keeps all twenty, and they never crowd out
  the assistant's five, because the two are counted separately.
- And prune ONLY backups at that: archives and the wizard's own zips live in
  the same folder and their parsers deliberately reject each other's forms.

### Restore is section-scoped, though the zip holds the course

The backup contains the whole course; a conversation is about one section. A
whole-course restore would silently revert work done in a sibling section
while the chat was open — a teacher may well have been editing Section 2 in
Obsidian while talking about Section 1. So Restore puts back only the section
the conversation was about, and says so on the button.

**Section-scoped means more than the section's folder**, and this is the part
easy to get wrong. The assistant can publish or unpublish a COURSE-LEVEL
shared page for one section, and that lives in the shared file's frontmatter
as `publishForSection<N>` — outside the section folder entirely. Restoring
only `section<N>/` would leave that half of the conversation's work in place.

The macOS build restores both: the section folder's contents, and — in every
shared page — only the keys carrying THIS section's number, spliced back from
the backup's own lines rather than re-derived. Copying the lines verbatim has
three consequences worth keeping: the older `draftSection<N>` spelling
survives untouched where a course still uses it, a key the conversation ADDED
is removed again, and every other section's keys plus the whole page body stay
byte for byte.

The section folder is emptied and refilled rather than swapped, for the same
reason `restoreBackup` documents: Obsidian holds the folder open.

**Say the surprising part in the confirmation, not in a doc.** Anything the
teacher changed in that section during the conversation goes back too,
including work done in Obsidian, and Plantoir cannot bring that part back.
That sentence belongs in the alert.


## plantoir.app is generated, and its screenshots are taken by a robot (entry 255)

The marketing site used to be one hand-written `site/index.html`. It is now
four pages — home, features, day to day, support — generated by
`python3 website/build.py` from sources in `website/`. Netlify still deploys
`site/`, unchanged, so nothing about hosting moved.

**Nothing here needs a Windows implementation for the site itself.** It is one
site for one product; a second one built on Windows would be a second product.
What Windows owed it was *pictures* — and that harness is now built and used:
`website/shots/capture_windows.py` and `website/shots/hero_windows.py` capture
every id in `website/shots.json` from a real Windows machine, and
`site/img/` carries the `<id>-windows-light.png` / `<id>-windows-dark.png`
pair for every one of them (`hero`, `assistant`, `courses`, `coverage`,
`colour-schemes`, `light-and-dark`, `new-course`, `preview`, `progress`,
`search`, and all four `site-*` shots) — confirmed 2026-08-22. This section
used to describe the harness as future work owed once the Windows app shipped;
it has shipped and this is done. What follows below is now history — how the
mac's own capture mechanism works and why it could not simply be copied — kept
because the lessons in it are real, not because the task is still open.

### What Windows built

Every image on the site exists twice, `<id>-light.png` and `<id>-dark.png`,
because the pages swap them with `<picture>` and
`media="(prefers-color-scheme: dark)"`. The ids are listed in
`website/shots.json` along with their alt text and captions. Windows captures
a third and fourth file per shot — `<id>-windows-light.png`,
`<id>-windows-dark.png` — using the same ids.

### Why the mac's capture mechanism will not port

Three mac-specific things carry this, and each needs its own Windows answer:

- **The window screenshots are native single-window captures, not test-runner
  screenshots.** The tests drive the app with XCUITest, but the pixels come
  from `screencapture -x -o -l <window-id>` — the programmatic equivalent of
  Command-Shift-4, Space, Option-click — because that is the only capture that
  delivers the window's rounded corners genuinely transparent, with macOS's
  own subpixel anti-aliasing. `window.screenshot()` was used first and bakes
  the desktop into the corner curves; masking the corners off afterwards
  approximates the radius and leaves stray fringe pixels, which is exactly the
  rendering-bug look a marketing page cannot carry (fixed in commit
  `63495853`). Whatever Windows uses (WinAppDriver, an accessibility-driven
  harness, `PrintWindow`) has to produce the window alone with its real alpha
  channel, not a screen crop and not a rectangle that gets its corners shaved
  off in post.
- **The window SIZE is forced, not remembered.** Passing
  `-"NSWindow Frame <autosave-name>" "<frame>"` as a launch argument puts the
  frame in AppKit's argument domain, which outranks the saved value — so every
  capture is 1280×800 regardless of where the window was left. The capture
  script saves and restores the remembered frames around the run, because the
  app writes them back on quit. Windows needs an equivalent: force the size,
  and put the teacher's own window size back afterwards.
- **Appearance is switched machine-wide.** There is no per-app override that a
  SwiftUI app reads, so the run sets the Mac to light, captures, sets it to
  dark, captures, and restores whatever it found — in a context manager, so a
  crash mid-run still puts it back. Windows has a per-user app/system theme
  setting; whatever is used there, restoring it is not optional.

### The trap that cost the most time here

`xcodebuild` does **not** hand its own environment to the test runner process.
Setting `MARKETING_WORKSPACE` and running the tests produced a green run with
one skipped test and no screenshots — success, and nothing to show for it. The
variable has to be passed as `TEST_RUNNER_MARKETING_WORKSPACE`, which arrives
in the test as `MARKETING_WORKSPACE`. Expect the same hop in whatever runner
Windows uses, and check the *count of captured images*, never the exit code.

### Three more traps, met on 2026-08-19, that will port themselves

- **The assistant photograph depends on a Settings toggle.** The picture is of
  the "Shall I go ahead?" card — but that card only appears when "ask before
  changing" is on, and the development machine's own copy may have it turned
  off. With it off the assistant does not fail: it CARRIES OUT the request,
  the capture shows "Unpublished 1 page." instead of a plan, and the demo
  course really has a page hidden in it afterwards — which then poisons the
  *other* appearance's capture with "It's already hidden." The harness must
  stage the setting on for the run and restore the teacher's own value after,
  exactly as it stages window frames (`capture.py` does this now). Windows
  keeps an equivalent setting; `capture_windows.py` photographs the assistant
  and needs the same staging.
- **Photograph progress when a step is NAMED, never after a fixed sleep —
  and know which steps can actually appear.** The progress shot used to
  wait for the progress view to exist and then sleep six seconds; on a
  machine with a warm container the whole build finished inside the sleep,
  and the capture showed the finished site — the same picture as `preview`,
  filed as progress. The test now waits for the milestone text to contain
  "Opening the preview" and shoots the moment it does. That sentence and
  not a prettier one, because instrumented 20 Hz polling showed it is the
  ONLY state a capture can reach: the launcher's early lines arrive in one
  buffered chunk, and the pre-build "Launching Quartz preview" line — the
  final milestone's marker — completes every milestone at once, so every
  earlier step is gone before a test can look. A preview then spends the
  whole build, minutes, on a full bar captioned with its last step — a
  product defect recorded in `TODO.md`, and one Windows shares, since the
  milestone tables and the launcher output are the same on both platforms.
  Two smaller traps inside that finding: the milestone sentence is the
  element's accessibility VALUE, and its label is empty — a wait on the
  label alone never fires while the sentence is plainly on screen — and
  the pointer-parking pause inside the save helper once outlived the very
  step being photographed, so park before waiting, not after. The built output is also cleared before EACH
  appearance pass, not once per run — clearing it once left the dark pass
  photographing the light pass's finished build.
- **Launch with window restoration off.** A capture that dies mid-test kills
  the app with two windows open (main plus assistant); every launch after
  that restores both, and every element query in every test then finds two of
  everything and fails with "multiple matching elements". On the mac the fix
  is the `-ApplePersistenceIgnoreState YES` launch argument; whatever Windows
  session-restore mechanism exists, captures must start from exactly one
  window.

### The demo sites were renamed on 2026-08-19

The published demo sites now follow a per-SECTION scheme —
`<code>-s<n>-2026-gordon.netlify.app`, e.g. `eng2d-s1-2026-gordon` — and
ENG2D has a section 2 site of its own. `capture.py`, `capture_windows.py`
and `website/site.json` carry the new names, but
`windows-app/Plantoir/Services/MarketingShotCapturer.cs` still writes the
OLD per-course names (`{code}-gordon-2026-27`) into its fixture configs'
`deploy_site_name`, in two places. Left for the Windows side to update
rather than edited blind from the mac, because the new scheme names a
SECTION and `deploy_site_name` is course-level config: the right value for
those fixtures — probably the section 1 name — is a judgement about how
that capturer uses them. The authoritative record of what is actually
deployed is the demo working folder itself:
`courses/<CODE>/.netlify_sites/section<n>.json`.

### The demo courses, and why those three

The screenshots are taken against a working folder holding ENG2D, MCV4U and
SCH3U, created through the app's own new-course panel rather than by writing
folders directly — so the pictures show what a teacher's folder actually looks
like, not what a script thinks it should. The three codes were chosen so that
between them the class sites show prose, typeset mathematics, and chemistry
notation, which is most of what anyone doubts a Markdown site can do.

Rejected: hand-made screenshots (they go stale silently, which is how a
marketing site ends up showing an interface that no longer exists), and a
headless browser for the class sites (it approximates macOS type rendering,
scrollbars and window chrome rather than showing them).


## The " — Edited" marker: knowing a section has changed since it published (entry 310)

Russell asked for the thing Pages does — `Untitled 3 — Edited` in the title
bar — for a section window: if any page the section uses, or shares with
other sections, has changed since the last publish, say so. And explicitly:
without impacting performance.

**The first finding was that nothing recorded when a section last
published.** Not in `course_config.json`, not in the trail, nowhere on
either platform. The `.netlify_sites` / `.cloudflare_sites` markers record
that a section has EVER published, not when or with what. So the feature is
half "compare two things" and half "start recording one of them".

### The shared file — match this exactly

`courses/<CODE>/.publish_state/section<N>.json`:

```json
{
  "destinations" : [ "netlify" ],
  "fingerprint" : "9f2c…",
  "publishedAt" : "2026-08-22T13:46:32Z"
}
```

Written by whichever app publishes, read by both.

**Be careful about how far to push that.** The fingerprint embeds each
file's size and modification date, so it holds up when both apps look at
the SAME folder — a working folder on a shared drive, or a USB disk moved
between two machines, where the dates are the file system's and do not
change. It does NOT survive a course folder being copied between machines
by a means that rewrites modification dates, and no algorithm that avoids
reading file contents could. So implement it to match, expect a shared
folder to agree, and do not promise a teacher that a course zipped up on
one machine and unzipped on another keeps its marker: it will read as
edited, and one publish puts it right.

Matching matters, then, wherever the two apps can see the same folder, so
treat the algorithm as a wire format rather than an implementation detail:

1. Walk `courses/<CODE>/`, skipping hidden entries.
2. Keep each regular file whose relative path passes the filter below.
3. For each, one line: `relativePath|sizeInBytes|microsecondsSinceEpoch`,
   where the path uses `/` separators and the microseconds are the
   modification date times 1,000,000, TRUNCATED to an integer.
4. Sort the lines as plain strings, join with `\n`, SHA-256, lowercase hex.

`SectionPublishState.fingerprint` is the reference. Note step 3's separator
and step 4's sort — a `List<string>` sorted with a culture-aware comparer
will not agree with Swift's, so sort ordinally.

### What counts, and why it is NOT read from the configuration

The obvious implementation reads `shared_folders`, `shared_files`,
`per_section_folders` and `per_section_files` out of `course_config.json`
and fingerprints those. It is wrong, and the reason is easy to miss:
`build_site.py` DISCOVERS new top-level folders during its preflight and
appends them to those lists AFTERWARDS. A folder the teacher made this
morning is a genuine input to the site and is not in the configuration
yet — so a configuration-driven fingerprint would be blind to it until the
next publish, which is the exact publish the marker exists to prompt.

So the rule is derived from what is on disk: everything non-hidden under
the course folder, minus

- another section's `section<M>/` folder (`section3` yes, `sections` and
  `section3b` no — those are folders a teacher is free to make),
- `node_modules` and the legacy non-hidden `merged_output`,
- `.DS_Store` / `Thumbs.db`,
- `course_config.backup.json` and any `*.tmp`.

`course_config.json` itself COUNTS — fonts, the sidebar and the coverage map
are inputs to the built site as surely as a page is. `Media/` counts, because
it is symlinked into the build. `hidden_explorer_components*` counts, because
it decides what the sidebar shows.

Two of those exclusions are load-bearing rather than tidy, and both were
found by reading `build_site.py` rather than by testing:

- **`.publish_state` is hidden on purpose.** The stamp is written into the
  course folder at the end of a publish. Counted, every publish would end by
  declaring the section edited — an indicator permanently stuck on.
- **`course_config.backup.json` and `course_config.json.tmp`** are written
  by `_atomic_write_json_with_backup` during the build's own preflight,
  whenever discovery finds something new. Same failure, less often, and
  therefore harder to diagnose.

`contracts/app-rules.json` → `publishedFreshness.filesCounted` runs all
sixteen of these as data. Wire that up before anything else here; it is the
half most likely to drift.

### Symlinks — the defect this shipped with, found by adversarial review

`FileManager`'s directory enumerator neither follows a symlink nor reports
it as a regular file. The first cut of this dropped every such entry, so a
`Media` folder symlinked into the teacher's Obsidian vault — exactly the
arrangement `build_site.py`'s own `_ensure_media_symlink` sets up —
contributed nothing at all, and every change inside it read as "up to
date". `.NET`'s `Directory.EnumerateFiles` has the same shape of trap
(`FileSystemInfo.LinkTarget`, and `EnumerationOptions` does not recurse
into a directory link by default), so do not assume you have escaped it.

The rule now: resolve links by hand, ONE hop.

- A link to a FILE contributes its target's size and date, recorded under
  the LINK's own relative path.
- A link to a FOLDER is walked, with each entry's path prefixed by the
  link's path. Links inside that walk are not followed — one hop is what a
  vault arrangement needs, and refusing the second is what stops a link
  pointing at its own parent from walking forever.
- A BROKEN link contributes where it points, so that repointing or
  removing it is visible rather than silent.

### A course that publishes into itself

Nothing stops a teacher choosing `courses/ICS3U/site` as their "publish to
a folder on this computer" destination — `deployFolderProblem` checks only
that the folder exists and is writable. `deploy.py` then writes the entire
built site there, INSIDE the folder being fingerprinted, so each publish
would differ from the last and the window would say " — Edited"
permanently. Exclude the configured local destination, and everything under
it, whenever it resolves to a path inside the course folder. Contract cases
in `publishedFreshness.selfPublishing`.

### When the stamp is written

In `MultiDestinationDeployRunner.run()`, and only when
`outcome.allSucceeded`. A course publishing to two hosts, one of which
failed, has NOT published, and its marker must stay up — that is the whole
point of having redundant destinations mean something.

**The fingerprint is taken when the FIRST upload begins, not when the last
one ends.** A publish takes minutes; a page the teacher edits while it
uploads did not go out, and stamping the finishing state would mark that
edit as published. That is the one direction this feature must never fail
in: an early marker costs a needless publish, a late one costs a class that
never saw the page.

**It is taken before the BUILD, not merely before the first upload** — the
build is the longest part of a publish and the part that actually reads the
content. The first cut took it after the build and was wrong; the review
caught it against this document's own wording.

The cost of taking it that early is real and was accepted: `build_site.py`'s
preflight appends newly discovered folders to `course_config.json`, so a
publish that discovers one ends with the section still marked edited. That
is true rather than spurious — the teacher did add a folder — and it clears
itself at the next publish, when there is nothing left to discover. The
alternative hides a real edit, and this feature must not fail in that
direction.

### A scheduled deploy needs its own path to the same record

The other half the review found. A scheduled deploy does not go through the
deploy runner at all: launchd runs a generated shell script, so the flagship
"publish tomorrow's class overnight" feature published perfectly and left
the title bar saying " — Edited" until somebody published again by hand.

On the mac the fix was cheap because the agent ALREADY launches the app
binary rather than `/bin/bash` (for an unrelated and much sharper reason —
a bare interpreter has no application identity, so macOS grants it no
access to a working folder on the Desktop). So:

1. The plist's arguments carry `--scheduled-section <workspace> <CODE> <N>`.
2. The app fingerprints the section BEFORE running the script.
3. The script tracks each destination's own result — `ALL_OK`, deliberately
   not `&&`-chaining, since one destination failing must not stop the
   others — and on total success writes a sentinel file naming where it
   went.
4. After the script exits, the app records the publish if the sentinel is
   there, and consumes it either way so tonight's failure cannot read as
   tomorrow's success.

The sentinel exists because the script ends by booting its own launchd
agent out, so the script's exit status belongs to `launchctl` and not to
the deploy. Whatever Windows uses for scheduling (Task Scheduler) needs the
equivalent: something the scheduled run can say "every destination
succeeded" with, that is not its exit code.

**Done on Windows, 2026-08-22** (`GUI-IMPROVEMENTS.md` row 323). Windows'
version of the same shape, adjusted for the one real difference: Task
Scheduler runs `powershell.exe` directly rather than the app binary, so
there is no in-process C# alive at the moment the deploy actually happens
to fingerprint the section from.

1. `TaskScheduling.Schedule` always writes a wrapper `.ps1` now (previously
   only for 2+ destinations) — the wrapper is where all of this lives.
2. The wrapper fingerprints the section itself, before running any
   destination's `deploy.ps1`, via the app's own bundled Python
   (`scripts/section_fingerprint.py` — see that file for why this is a
   THIRD copy of the algorithm rather than reusing the C#). Fingerprinting
   happens at RUN time, not at schedule time, on purpose — see the rejected
   alternative below.
3. Each destination's `deploy.ps1` line is run un-chained (same "redundancy"
   rule as the mac), tracking `$allSucceeded` in the wrapper's own
   PowerShell state rather than an `ALL_OK` file convention — there is no
   equivalent of launchd booting its own agent out here, so the wrapper's
   own exit code would actually be trustworthy, but the sentinel is written
   regardless, to keep the two platforms' shapes matching and because the
   app still needs SOMETHING durable to read on next launch.
4. Only if every destination succeeded, the wrapper writes a JSON sentinel
   under `%LOCALAPPDATA%\Plantoir\scheduled\pending\` — course code, section,
   course directory, fingerprint, destination types/names, and a UTC
   timestamp.
5. `ScheduledDeployCompletion.ConsumePending()` — called from `MainWindow`'s
   `Activated` handler, subscribed before any `SectionDetailView` exists so
   it runs before that view's own marker refresh on the SAME activation —
   applies every pending sentinel (`SectionPublishState.RecordPublish` +
   the `SectionContentMarkedPublished` trail event, reusing the existing
   event rather than adding a new one) and deletes it either way, so a
   sentinel that failed to apply cleanly cannot sit there being reread
   forever, or be mistaken later for a deploy that never happened.

**Rejected: fingerprinting at SCHEDULE time instead of RUN time.** Far
cheaper — the app already has everything it needs in C# the moment the
teacher clicks Schedule, so this could have been a small addition to
`TaskScheduling.Schedule` with no Python involved at all. Rejected because
it is wrong in the direction that lies to the teacher: an edit made to the
section between scheduling it and the overnight run still goes out
correctly (the deploy publishes whatever is on disk at run time), but a
schedule-time fingerprint would stamp the STALE, pre-edit fingerprint —
so the marker would say "— Edited" about content that had, in fact, just
published. Fingerprinting at run time, in the wrapper, right before the
deploy — the same moment the mac's launchd path fingerprints — is the only
version that is correct either way, hence the third Python copy of the
algorithm rather than a cheaper C#-only shortcut.

### One false negative, written down so it is not a surprise

Restoring a page from a backup that preserves its modification date, where
the length happens to be unchanged, reads as UP TO DATE. `cp -p`, `rsync
-a`, unzipping and Time Machine all preserve modification dates. This is
the price of never reading file contents, which is what makes the check
cheap enough to run whenever a window comes to the front, and the cure —
hashing every byte of every page — costs more than the marker is worth.
Publishing is never blocked by the marker, so a teacher who suspects it can
simply publish. It is a contract case (`whenShown`) so that nobody
"discovers" it later and treats it as a bug.

### What is shown

`base` is the existing title (`ICS3U-S1`); the marker appends `" — Edited"`
— em dash, spaces either side, capital E, all of it Pages'. Contract cases
in `publishedFreshness.marker`.

**A section that has never published shows NO marker.** Pages does the
opposite (`Untitled 3 — Edited` on a document never saved), and it was
rejected here on purpose: a marker that is on for every new course from the
moment it is created is a marker teachers learn to ignore, which costs the
one it is for. An unreadable or corrupt stamp is treated identically to no
stamp, so a course predating this feature is quiet rather than shouting.

### One accepted imprecision, so nobody "fixes" it

A course-level page shared by every section marks EVERY section edited —
even though editing only `publishForSection3` in fact changes only section
3's site. Being exact means parsing the frontmatter of every shared page on
every check, which is reading files, which is the cost the whole design
avoids. The wording was chosen to stay true either way: a page this section
uses, or shares, has changed. It is early, not wrong.

### The refresh triggers, and the watcher NOT built

The mac recomputes on four events: the window appearing, the app becoming
active, this window becoming key, and a run finishing. Note that
`NSWindow.didBecomeKeyNotification` fires for EVERY window and panel in the
app — the assistant, a settings sheet, an alert — and app activation fires
alongside it, so several walks really can be in flight at once. Each
refresh therefore carries a generation number and a result is applied only
if it is still the current one; without that, a walk begun before a publish
can land after one begun afterwards and re-assert " — Edited" about a
section that has just gone out. Whatever Windows uses for its own
activation events needs the same guard.

Never on a timer, and never from `body` — a view that recomputed it while rendering
would walk the course folder every time a console line arrived during a
publish. The walk runs off the main thread, so a course on a slow network
volume cannot stutter a window coming to the front.

An FSEvents stream over the course folder was considered and deliberately
NOT built, on either platform. Neither app runs one today, the marker only
matters at the instant somebody looks at the title bar, and a watcher is a
cost paid continuously for an answer wanted occasionally. If the
on-activate refresh ever feels stale in practice, that is the moment to add
one — for the frontmost course only, coalesced — and not before.

Windows owes its own equivalents of the two mac-specific pieces: setting
the window title (WinUI does it on the window, not through a
`navigationTitle` modifier) and the activation events.

### The trail

New event `section content marked published`, in `ActivityTrail.Event` and
in `shared-rules.json` → `activityTrail.mustRecord`. It matters more than a
routine line because the marker is DERIVED: its presence and its absence
look identical on disk, so "it still says Edited after I published" has
nothing to look at without it. The line also records that the publish
succeeded at EVERY destination rather than merely at one.

## What the engine says now reaches a problem report — without a pipe (2026-08-20)

Answering the gap `MAC-HANDOFF.md` recorded the same day. Until now
`AssistServerHost` sent `llama-server`'s stdout and stderr to
`FileHandle.nullDevice`, so a report from a teacher whose assistant was
misbehaving could carry **nothing the engine had said** — no load error, no
slot warning, no timing. Windows already had `NoteServerLine` for this. The
mac now samples too, and the interesting part is what it does INSTEAD of a
pipe, and how narrow the filter is.

**A file, not a pipe, and the pipe is the trap.** `nullDevice` was never
laziness: a redirected pipe nobody drains fills up, and the engine then blocks
on its next log write, mid-request, looking exactly like a hung model. That is
the wedge Windows had to fix by draining both streams, and discarding the
output is precisely why the mac never had it. Swapping in a `Pipe` would have
traded a diagnostics gap for that bug. So both streams now go to ONE FILE in
the temporary directory, and a bounded tail is read **when somebody asks** —
never on the engine's timetable. A write to a file has no reader to wait for.
`AssistEngineLogTests.testTheEnginesOutputIsNeverReadThroughAPipe` pins it by
reading the source for `Pipe(` and `readabilityHandler`, because every other
test in the file would pass with the wedge back in.

`AssistServerHost.lines(in:since:atMost:)` is a free function taking the mark
by reference, so each look reports what arrived SINCE the last one; it reads at
most the recent 64 KB however long the engine has run, drops the part-line that
skipping ahead lands on, and resets a mark left past the end of a file that has
shrunk. `stop()` closes the handle but deliberately LEAVES the file — the
engine-never-became-ready path calls `stop()` before anybody has looked, and
the reason it never became ready is the last thing in there. `discardEngineLog()`
is the separate step, and a sweep on start removes anything older than a day
that a force-kill left behind.

**The filter is narrow, and the narrowness is measured, not guessed.** Driven
against the bundled engine on this Mac (llama.cpp b10435, Qwen2.5-1.5B, 2026-08-20):

- Lines carry a severity letter as their **second field** —
  `0.46.018.667 E srv send_error: …` — so `E` is the signal.
- **Warnings are deliberately NOT recorded.** A perfectly healthy start prints
  **six** of them: five are a CORS block warning that all origins are allowed
  and no API key is set (which cannot matter on a server bound to 127.0.0.1),
  and one is `control-looking token: 128247 '</s>' was not control-type`, a
  quirk of the weights. Recording warnings would have spent the entire budget
  on noise before the teacher asked anything.
- A word test sits beside the severity test as a fallback, matching `error`,
  `exception`, `failed`, `failure`. The severity field is this build's format
  and a future build could drop it; and it is what catches
  `W srv operator(): got exception: …`, the one warning worth having. Verified
  that none of the six healthy-start lines contain any of those words.

Two lines were provoked deliberately and both are caught: a malformed request
body (`got exception: … parse error`) and an over-long prompt
(`E srv send_error: … request (20030 tokens) exceeds the available context size
(8192 tokens), try increasing it`).

**When it samples.** Three moments, all in `AssistSession`:

1. **The engine never became ready** — the tail is taken with the filter OFF,
   because then every line is the diagnosis, ordinary ones included.
2. **Every fifteen seconds while the window is open**, filtered. Sampling only
   at teardown would have been simpler and would have missed the case this is
   FOR: a teacher whose assistant is misbehaving right now, filing a report
   without closing anything. The loop ends itself once the cap is reached, so a
   badly behaved engine costs a fixed amount of work rather than a permanent one.
3. **On `finish()`**, before the log is discarded.

**Capped at twelve lines per conversation.** The trail is deliberately coarse —
it is a record of what the TEACHER did, and its failure mode is that the one
line that mattered ends up on page forty. Twelve is enough for a model that
will not load and nowhere near enough to bury a morning's work. Lines are cut
to 200 characters, and go through `LogRedactor` on the way in like everything
else — which matters here, because the engine prints the model's full path.

**Verified end to end on the real app**, because none of the unit tests can
prove the wiring holds. A healthy conversation left the trail untouched, which
is the result that matters most — the filter is doing its job. An over-long
prompt then produced, about six seconds later:

```
23:23:36 · MCV4U/1 · the local AI assistant could not answer — The assistant's engine answered with an error (400).
23:23:42 · MCV4U/1 · the assistant's engine said: 0.56.869.873 E srv    send_error: task id = 114, error: request (11965 tokens) exceeds the available context size (8192 tokens), try increasing it
```

The first line is what a report carried BEFORE this change, on its own: an HTTP
status and nothing else. The second is the sentence that explains it. That pair
is the whole argument for the feature. The temporary log folder was empty after
quitting, so `discardEngineLog()` does clean up.

### This adds a contract event, and the Windows suite will go red

`contracts/shared-rules.json` → `activityTrail.mustRecord` gained
**`assistant engine said`**, and `ActivityTrail.Event` gained the matching
case. The test that compares the two lists runs on both platforms, so
**`Plantoir.Tests` will fail until `Plantoir.Core`'s event list gains the same
entry.** That is the mechanism working, not damage: it is a request, and it is
written up in `MAC-HANDOFF.md` as one.

The work on your side is small, because the hard half is already there.
`LocalModel.NoteServerLine` and `RecentServerLog` already keep a 60-line ring
buffer of exactly this output. What is missing is that nothing puts any of it
on the trail. Add the event, sample `RecentServerLog` at the three moments
above, and reuse the filter — **but re-measure the healthy-start noise on your
own engine build before trusting the warning rule.** Vulkan and CPU builds
print different startup lines from the Metal one, and the whole reason
warnings are excluded here is a specific set of six lines that may not be your
six. Say what you measured.

One difference worth keeping rather than closing: Windows drains into memory
because it must (a redirected pipe has to be read), while the mac writes to a
file because it can. Do not "bring the mac into line" by switching it to a
pipe — the file is what makes the no-blocking-read property structural rather
than a promise about always having a reader attached.

## Testing

- The **PowerShell launchers are tested on real Windows** — all three have
  been driven end to end through the app: course creation, preview (including
  `--stop` reclaiming native processes), and publishing to all three
  destinations, most recently a live Cloudflare Pages publish. The appendix at
  the end of this file is **doubly historical**: it documents the WSL2/Docker
  Engine architecture the launchers used before the 2026-08-19 move to the
  native runtime (see the note near the top of this file) — read it for the
  reasoning behind that earlier design and the ConPTY/path-translation lessons
  that still generalise, not as a description of what `setup.ps1` /
  `preview.ps1` / `deploy.ps1` do today, and not as a to-do list.
  (An earlier version of this bullet said they were UNTESTED and told you to
  test them first. That was a week out of date and would have sent a session
  down a dead end.)
- `verify.sh` is the toolchain gate on macOS/Linux; a Windows verify
  script should mirror it, including its cross-check that every helper a
  launcher calls is defined in that same launcher file (a missing helper
  is exit 127 at runtime, on the one path nobody tests).
- Mirror the macOS test discipline: the unit suite runs without Docker;
  presentation regressions get press-and-look tests (entry 81's lesson:
  button logic can be perfect while its dialog never shows).

### Pinning the trail as wired, not merely declared (mac, 2026-08-19)

Windows found the gap (2026-08-19, `MAC-HANDOFF.md`): three trail events sat
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

## Documentation map

- [`WINDOWS-HANDOFF-COMPLETED.md`](WINDOWS-HANDOFF-COMPLETED.md) — write-ups
  for handoff items verified DONE in `windows-app/` as of 2026-08-22, moved out
  of this file for length. Read it for the reasoning behind something that has
  already shipped.
- [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — THE spec (179 entries as of
  2026-08-15). Its **Windows status** section is where coverage is tracked.
- [`documentation/`](documentation/README.md) — toolchain deep dives 01–10.
- [`CLAUDE.md`](CLAUDE.md) — the repository's entry point: conventions,
  testing, setup, and the traps that cost time.
- [`RELEASING.md`](RELEASING.md) — cutting a release, both platforms.
- [`research/ai-assist/`](research/README.md) — the assistant's
  measurements, and `HISTORY.md`, which is the feasibility work, the build
  handoff and the original MCP proposal in one place.
- The WSL2/Docker launcher background — history, superseded by the native
  runtime on 2026-08-19 — is the **appendix at the end of this file**.
- [`mac-app/`](mac-app/README.md) — the reference implementation; when an
  entry's Windows note is thin, read the Swift it references.


---

# Appendix — WSL2/Docker background and the original .ps1 test plan (SUPERSEDED)

> **This entire appendix describes an architecture Windows no longer runs.**
> On 2026-08-19 the launchers dropped the Docker-Engine-inside-WSL2 path this
> appendix documents in favour of a native runtime — see "Windows no longer
> runs any of this in a container" near the top of this file, and
> `GUI-IMPROVEMENTS.md` entry 290. There is no `Ensure-ContainerRuntime`, no
> `docker` function, no image tag, and no WSL2 dependency in the current
> `.ps1` files. **Read what follows as history** — why the WSL2/Docker design
> was chosen over plain Docker Desktop, the `ProcessStartInfo`
> token-injection and path-translation lessons (some of which still
> generalise to the native code, some of which no longer apply at all), and
> the shape of a real end-to-end test pass on Windows 11 — never as a
> description of current behaviour or as a to-do list for new work.

*Folded in from the former `WINDOWS-TESTING.md` on 2026-08-15, back when the
WSL2/Docker path below was current. Two facts in it were corrected on the way
in: the token file is `/tmp/deploy_pat` (renamed when Cloudflare support
arrived, since one file now serves both providers), and deploys are no longer
Netlify-only. Both of those facts are themselves now mac-only, since the
token file and its container no longer exist on Windows.*

> **Status (2026-08-13): the launchers are no longer untested.** — true at
> the time, of the WSL2/Docker launchers this appendix describes. All three
> had been exercised repeatedly on real Windows 11 through the app — course
> creation, preview (including `--stop` reclaiming container-side
> processes), and publishing to all three destinations, most recently a live
> Cloudflare Pages publish end to end. Superseded by the same rewrite: the
> current launchers have been re-tested end to end against the native
> runtime (see "Testing" above), and this status line is left in place only
> as part of the historical record, not as a current claim.
>
> One thing it does NOT cover, and worth knowing: `verify.sh`, the
> toolchain gate named in [`CLAUDE.md`](CLAUDE.md), **cannot run
> on Windows** — it is bash and (as originally written) expected `docker` on
> `PATH`. That remains true today, though the reason has changed: there is no
> longer a `docker` to expect on Windows at all, containerized or otherwise.
> Toolchain changes made on Windows are verified by driving a real publish
> through the app instead.

> **Audience:** a Claude Code session running on the maintainer's Windows 11 Pro
> machine. This file gives you the context needed to test (and fix) this
> toolchain's Windows launchers.
> Read this fully before touching anything. If you are building the Windows
> APP, start with [`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md).

### Mission

The toolchain recently **dropped its Docker Desktop requirement**. On
Windows, the PowerShell launchers (`setup.ps1`, `preview.ps1`, `deploy.ps1`)
now provision and use the **Docker Engine inside WSL2** automatically. That
code was written and parse-checked on macOS but has **never executed on a
real Windows machine**. Your job: exercise it end to end on this machine,
find what breaks, fix it, and report.

### Background (5-minute orientation)

- This repo publishes teaching websites from Obsidian vaults using a Docker
  container that wraps a patched Quartz v4.5.0. There is **no registry**:
  the launchers hash the folder's build recipe and build the image locally
  as `teaching-quartz:src-<hash8>` (`Get-BuildContext` / `Get-ToolchainHash`
  / `Build-ImageIfMissing` in the `.ps1` files). Full architecture docs:
  [`documentation/README.md`](documentation/README.md),
  especially [`documentation/03-launcher-scripts.md`](documentation/03-launcher-scripts.md)
  (the section "Container runtime bootstrap" describes exactly what you are testing).
- The teacher-facing flow is: `setup.bat` (interactive course wizard) →
  `preview.bat COURSE SECTION` (build + serve; the launcher prints the
  host address — each working folder gets its own probed port block) →
  `deploy.bat COURSE SECTION` (delta deploy — Netlify by default,
  `--target cloudflare`, or `--to-folder <path>`).
- Each `.bat` is a thin wrapper that runs the `.ps1` beside it.
- The macOS counterpart of this change (Colima) is **already tested and
  working** — treat the `.sh` scripts as the reference for intended behaviour.

### What the new Windows code does

In each of the three `.ps1` scripts, near the top, there is an identical
block: `Ensure-ContainerRuntime` plus helpers. Its intended behaviour:

1. **Fast path:** if a native `docker` (docker.exe) works, use it unchanged.
2. Otherwise require `wsl` + an installed distribution (else print
   `wsl --install` guidance and exit).
3. Probe `wsl -e docker info` as the default user, then as root
   (`$global:WslUserArgs = @('-u','root')`).
4. If the engine is missing inside WSL, offer to install it:
   `apt-get install docker.io` as root, then `usermod -aG docker <user>`.
5. Start it with `wsl -u root -e sh -c "service docker start"` and poll.
6. On success, define `function global:docker { & wsl $global:WslUserArgs -e docker @args }`
   so every later `docker …` call in the script transparently routes through
   WSL. Bind-mount paths are translated with `Get-MountPath` (wslpath →
   `/mnt/c/...`). `deploy.ps1` additionally has two
   `System.Diagnostics.ProcessStartInfo` invocations that bypass PowerShell
   command resolution — these use `$DOCKER_EXE` / `$DOCKER_PREFIX` variables
   instead.

### Environment notes for this machine

- Windows 11 Pro (build 26100), PowerShell 5.1 minimum target (also test
  under `pwsh` 7 if installed).
- Clone/pull this repo; **test the repo's `.ps1` files directly** (in
  production they reach teachers via the app's `.toolchain/` mirror).
- The repo stores files with **LF line endings** (depending on
  `core.autocrlf`, your checkout may or may not have CRLF). PowerShell
  handles LF `.ps1` fine. If a `.bat` misbehaves with LF endings, invoke the
  `.ps1` directly (`powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1`)
  and note the finding — in production, teachers receive CRLF copies (the
  image build runs `unix2dos`).
- The container image is **built locally by the launcher on first run**
  (BuildKit required — `Ensure-Buildx`); expect the first run to take a few
  minutes and to need the network. A changed recipe changes the tag and
  rebuilds.
- `courses/` is gitignored — a fresh clone has no courses. The setup wizard
  offers to install an Example Course (**EXC2O**); say yes and use it as the
  test fixture throughout.

### Test plan (in order)

Work through these scenarios; after each, note PASS/FAIL and any output worth
keeping.

**1. Static review.** Read `Ensure-ContainerRuntime` in all three `.ps1`
files and flag anything that cannot work on PowerShell 5.1 before running
anything.

**2. Specific mechanisms I could not verify from macOS** — test these in an
interactive PowerShell first:
   - Empty-array argument flattening: `$e = @(); wsl $e -e echo hi` — confirm
     no stray empty argument reaches wsl (this pattern underpins
     `Test-WslDockerReady` and the `docker` function).
   - `$env:WSL_UTF8='1'; wsl -l -q` — confirm clean, parseable distro names.
   - `Get-Command docker -CommandType Application` behaves on PS 5.1 when no
     docker.exe exists (should return nothing, not throw).
   - After `usermod -aG docker <user>`, does `wsl -e docker info` work
     without `wsl --shutdown`? (The scripts fall back to root if not — confirm
     the fallback engages.)

**3. Scenario: engine not installed.** If this machine's WSL distro has no
Docker engine (or remove it: `wsl -u root -e sh -c "apt-get remove -y docker.io"`),
run `.\preview.ps1 EXC2O 1 --build-only` (after setup) or `.\setup.ps1` and
confirm the install offer appears, works, and the run continues to success.

**4. Scenario: engine stopped.** `wsl --shutdown`, then run a launcher —
confirm it starts the engine itself and proceeds.

**5. Scenario: engine running (fast path).** Re-run immediately — confirm no
install/start work is repeated.

**6. End-to-end teacher flow.**
   - `.\setup.bat` → install the Example Course (EXC2O).
   - `.\preview.bat EXC2O 1` → confirm the container is created with a
     `/mnt/c/...` mount, the build succeeds, and `http://localhost:8081`
     renders in a Windows browser (WSL2 localhost forwarding).
   - Check interactive fidelity through the `wsl`-routed `docker exec -it`:
     wizard prompts, and especially the arrow-key colour scheme picker if you
     run a full course setup.
   - `.\preview.bat EXC2O 1 --build-only` then, **only if a Netlify token for
     a throwaway account is available**, `.\deploy.bat EXC2O 1`. Deploys
     create real Netlify sites — skip otherwise and note as untested.

**7. Edge cases.**
   - Run from a folder whose path contains spaces (e.g.
     `C:\Users\<me>\Class Websites Test\`) — mount translation and quoting.
   - Move the folder, run again — the container NAME is derived from the
     folder's path hash, so a moved folder gets a brand-new container (and
     the old one is left stopped); confirm the new one mounts the new
     `/mnt/c/...` path.
   - Two working folders at once: confirm each gets its own container
     (`teaching-quartz-<hash>`) and its own host port block (bases 8081,
     8091, …, each with a +1000 websocket block), and that two previews can
     run simultaneously.
   - `.\preview.ps1 EXC2O 1 --port 8082` — the per-preview port flag.
   - After any build, confirm the merged output contains the generated
     social sharing card (`.merged_output/section1/quartz/static/og-image.png`
     should be a title card in the course's colours, not the stock Quartz
     crystal — the card is drawn by `scripts/social_card.py` inside the
     container, so no Windows-side work is involved).
   - `deploy.ps1`'s token-injection steps (the `ProcessStartInfo` ones) — the
     `$DOCKER_PREFIX` quoting through `wsl.exe` is the riskiest untested
     code; verify `/tmp/deploy_pat` arrives in the container intact
     (test with a dummy: pipe text through the same command shape).

### When you find problems

- Fix them in the working tree, keeping the structure parallel across the
  three `.ps1` files (the block is intentionally identical in each) and
  consistent with the `.sh` reference behaviour.
- Commit to a branch named `windows-wsl2-fixes` with clear messages; do not
  push to `main` directly.
- Finish with a summary: scenarios run, PASS/FAIL each, fixes made, and
  anything that remains untested (e.g., a true fresh `wsl --install` if this
  machine already had WSL).

### Ground rules

- Never uninstall WSL or delete existing WSL distros without asking first.
- Images are only ever built locally; there is nothing to publish.
- Netlify deploys are opt-in only (they create public sites).
- The `.sh` files are macOS-only — do not "fix" them on Windows.

---

### Results — 2026-08-11 (Claude Code, maintainer's Windows 11 machine)

Run on Windows 11 Pro 26200, WSL 2.5.10 (no distro pre-installed —
Ubuntu-24.04 installed for the tests), Docker Engine 29.1.3 inside WSL,
PowerShell 5.1. Fixes were committed to **main** at the maintainer's
direction (overriding this brief's branch instruction). Interactive
runs were driven through `windows-app/PtyDriver`, a ConPTY harness that
gives the launchers a real TTY.

**1. Static review — FAIL → fixed.** Beyond parse-checks (clean), five
faults found and repaired: (a) preview.ps1's image resolution was
inverted — every run without `--image` printed "missing the toolchain's
build recipe" and exited 1; (b) a single trailing flag arrived as a
STRING, so `$Flags[0]` indexed characters ("Unknown option: -") — now
always an array; (c) the three scripts hashed different paths for the
container name (setup hashed the invocation directory before its
Set-Location; casing changed the hash) — all three now hash the
folder's physical path via GetFinalPathNameByHandle, after
Set-Location; (d) no exit-code propagation from the final docker exec;
(e) `Ensure-Buildx` guarded WSL work with an always-true null check.
Also: under `$ErrorActionPreference='Stop'`, PS 5.1 turns wsl.exe
stderr into TERMINATING errors at any redirected call site — probes
that legitimately fail (inspecting a not-yet-built image) killed the
script. The global docker wrapper now relaxes the preference around the
wsl call. Two milestone lines the app watches for were added
("Setting up this PC - a one-time step ...", and preview's
"Starting container if needed ...").

**2. Mechanism checks — PASS.** Empty-array flattening (`wsl $e -e
echo hi` → clean), `WSL_UTF8=1` distro names parse, `Get-Command
docker` returns nothing without throwing when no docker.exe exists.
usermod fallback untested (the test distro runs as root by default).

**3. Engine not installed — PASS (command path).** `apt-get install
docker.io` inside WSL (the script's exact command) installed engine
29.1.3; the interactive install-offer prompt itself was not exercised
end-to-end (the engine was installed before the first full run).

**4. Engine stopped — PASS.** `service docker start` + poll brought the
engine up from cold.

**5. Fast path — PASS.** With the engine running, no install/start work
repeats; runs go straight to the container checks.

**6. End-to-end teacher flow — PASS.**
- `setup.ps1 --install-example`: image built locally from the recipe
  (BuildKit via buildx in WSL), container `teaching-quartz-<hash8>`
  created with `/mnt/c/...` mount, EXC2O installed, and
  `EXAMPLE_COURSE_CODE=EXC2O` printed for the app.
- `preview.ps1 EXC2O 1`: "Preview will be available at:
  http://localhost:8081/" announced; page served HTTP 200 with the
  correct title through WSL2 localhost forwarding.
- Interactive fidelity through the wsl-routed `docker exec -it`:
  works under a pseudo console — with one CRITICAL caveat: the process
  that creates the ConPTY must not itself have redirected stdio, or
  the child inherits stale pipe handles and wsl reports "the input
  device is not a TTY". (The Plantoir app, a GUI process, is naturally
  clean.)
- `deploy.ps1 EXC2O 1` with a throwaway token pre-stored in Credential
  Manager: Netlify site created, 233 files uploaded with streaming
  counts, "✅ Deploy complete.", exit 0, site live over https. The
  first-run token-paste prompt was not exercised (token pre-stored);
  `/tmp/deploy_pat` injection via ProcessStartInfo worked — the token
  reached the container intact.

**7. Edge cases.** Two-folder concurrency, moved-folder recreation,
spaces-in-path, and `--port` were NOT yet exercised on this machine
(the per-folder hash and port-block logic are covered by unit tests in
`windows-app/Plantoir.Tests`). The generated social card was verified
present after the build (`.merged_output/section1/quartz/static/
og-image.png`, 28 KB, drawn in-container). Remaining scenarios are the
first candidates for the next session.

**Untested overall:** a true fresh `wsl --install` (WSL itself was
already present), the docker-group/usermod fallback, and pwsh 7 runs
(everything above ran under Windows PowerShell 5.1).

---



## Salvaged capture fixes from a stranded branch need a Windows build/test pass (2026-08-22)

`issue/mac-site-shots-unmerged` sat unmerged since 2026-08-19 while `dev`
independently re-solved most of what it was doing (the Safari
appearance/address-bar verification in `safari.py`, dropping
`mask_window_corners` for `screencapture -l`'s own transparent corners, and
the one-appearance-per-process Windows capture — all landed 2026-08-20,
superseding the branch's older versions of the same ideas). The branch was
not merged and was left to be deleted; see `MAC-HANDOFF.md`'s "Done" ledger
for the full salvage/discard breakdown.

Three of its Windows-only fixes were still real and NOT on `dev`, so they were
hand-ported from a macOS session (no Windows session involved) into
`issue/windows-capture-dialog-fixes`: `NewCourseDialog.StageForCapture` now
calls the same `Refresh*` methods a teacher's own typing would trigger (it
previously left the staged New Course dialog panel looking empty — no
course-name suggestion, no club row); the staged dialog card's `MaxHeight`
went from 680 to 720 (was cutting the Language/region row through its own
control) and now reads `dialog.Title` instead of hardcoding "New Course";
`AssistWindow` gained `ShowPromptShelfForCapture()` so a staged capture shows
the prompt shelf instead of a blank top third. Full row: `GUI-IMPROVEMENTS.md`
#316.

**✅ Verified 2026-08-23, on a real Windows machine, with the OS appearance
actually switched to match each capture** (the way `capture_windows.py`
itself does it — see item 4 in "What is still genuinely outstanding" above
for the full detour: a first verification pass skipped that step, misread
the result as a product bug, and nearly shipped an unnecessary and broken
code change before the real cause was found). `dotnet build` (0 warnings, 0
errors) and `dotnet test Plantoir.Tests/Plantoir.Tests.csproj` (655/655)
both pass, and `--capture-marketing-shots` — run once with the real OS theme
set to Light and once set to Dark — confirms all three edits visually in
both: the New Course dialog shows populated suggestions, an uncut
Language/region row, and the real "New Course or Club" title, with its card
correctly matching the surrounding window's theme; the assistant window
shows the prompt shelf instead of a blank top third.


## Docker images used to leak forever on the mac — and why you inherit nothing (2026-08-23)

Recorded here because the finding sounds like it must apply to both sides, and
it does not. On the mac, the builder image is tagged
`teaching-quartz:src-<hash of the build recipe>`, so every recipe change mints
a new tag and orphans the previous one. Nothing in the repository had ever
removed one: 139 images and 50 GB on this dev machine, ~115 of them
`teaching-quartz` tags. Containers were never the problem — each launcher
already removes its own container by name before recreating it, and the name
is a hash of the working folder, so it is one container per folder replaced in
place.

The mac fix is `prune_superseded_images()` in `setup.sh`, `preview.sh` and
`deploy.sh`: after a build SUCCEEDS, remove every `teaching-quartz:src-*` tag
except the one just built, skipping any a container still references. It keeps
exactly one tag; the "keep the previous one for a cheap downgrade" idea was
rejected because an older Plantoir carries its own bundled recipe and rebuilds
its tag regardless. `docker builder prune` was rejected outright: it is global
with no per-project filter, and this machine's Docker is shared with other
projects.

Three guards on it, each of which an adversarial review found MISSING in the
first version — worth having in writing, because all three look like
over-caution until you see the case:

- **Do nothing unless the tag just built is one of ours.** `--image` lets a
  caller point the image at anything, and "remove everything except the tag I
  was given" then means "remove every real tag on the machine, including every
  other working folder's current one".
- **Do nothing to an image younger than about a day.** The container check is
  a point-in-time read, and a folder that is mid-recreate — container removed,
  replacement not yet started — references nothing for a second or two. A
  build finishing in another folder inside that window would delete the image
  it is about to run, and the teacher would see a registry-pull failure for an
  image that exists on no registry. The same guard stops two folders on
  different recipes from deleting each other's image on every switch.
- **Ask Docker for the age, never compute it.** `docker image inspect
  '{{.Created}}'` returns LOCAL time with an offset, not the UTC `Z` it
  resembles, so comparing it against a UTC cutoff is silently wrong by the
  machine's offset. `{{.CreatedSince}}` from `docker images` is Docker's own
  human age string and has no timezone in it at all.

One correction to the paragraph above, for honesty: **containers are cleaned
up per working folder, but nothing cleans up a DELETED working folder's
container.** That orphan now permanently pins its image against this cleanup —
the one image that can never be reclaimed is the one nobody will ever use
again. Small (an orphan per deleted folder, and a teacher deletes none), noted
so the write-up is not read as "container hygiene is solved".

**Windows has nothing to port.** You dropped Docker on 2026-08-19 for the
native runtime — no image, no tag, no container, nothing to accumulate. (An
earlier `TODO-TODAY.md` note on the mac claimed "their launchers have the same
gap"; that was written without checking the `.ps1` files and is wrong.) Do not
add a cleanup for images that do not exist.

**The question worth asking on that side is the analogous one, not the same
one:** when a teacher installs a new Plantoir, is a superseded
`Vendor/runtime/` — or an old model download under `%LOCALAPPDATA%` — left
behind anywhere it can accumulate across a school year? That is the shape of
the failure the mac hit: a disk filling with something the teacher has never
heard of and cannot connect to this app. Nobody here can see a Windows
machine to answer it, so it is a question rather than a finding.

## Which folders count for marks: absent is not empty (2026-08-23)

The Curriculum Coverage map shows an expectation as ASSESSED — the ring on a
cell, and Ontario's ask that every overall expectation be evaluated at least
once — when a page addressing it lives in a folder that counts for marks. That
used to be hardcoded in `build_site.py` as *any folder whose name contains
"task"*, and a teacher who called theirs "Tests", or renamed "Tasks", silently
lost every assessed mark on the map with nothing said.

It is now `graded_folders` in `course_config.json`, matched by EXACT
folder-segment name at any depth (so `Tasks/Unit 1/Quiz.md` still counts, and a
page is never assessed because of what it is CALLED).

### The one mistake that matters on your side

**`GradedFolders` must distinguish ABSENT from EMPTY.** A plain
`List<string>` that defaults to empty when the key is missing would tell the
build "this teacher has no graded folders", and every course made before this
key existed would lose every assessed mark on its map — silently, because a map
with no rings still renders and still looks finished.

- ABSENT means the teacher has never been asked. The build applies the
  historical substring rule, and the course keeps exactly the marks it had.
- EMPTY (`[]`) means they were asked and cleared it. That is a real answer and
  is honoured.

The mac models it as `[String]?` and REMOVES the key when set to nil
(`CourseConfiguration.swift`). Whatever you use, make the round trip preserve
"no key at all" — and check your serialiser, because both apps write this file
wholesale from an in-memory copy.

### Do not seed existing courses

The obvious migration — write `["Tasks"]` into every course — is wrong, and the
repository proves it rather than the reasoning alone. All 38 payloads use
"Tasks", but the mathematics skeleton family ships **"Thinking Tasks"**: the
substring rule counted it, an exact pool of `["Tasks"]` does not. Seeding would
have quietly stripped that course's assessed marks.

Nothing is written back from a BUILD either. Be precise about why, because the
first version of this paragraph overstated it: both apps DO preserve keys they
do not recognise, so a build's write is not dropped in general. The real risk is
narrower and quite sufficient — an app holding a copy of the file it loaded
BEFORE the build wrote the key overwrites it at the next save, and a teacher
with Settings open while a preview runs is ordinary, not a corner case.

**One thing you will notice immediately: `FileFormats_CourseConfigKeys_MatchesContract`
is RED on your side, deliberately.** `contracts/file-formats.json` now documents
`graded_folders` and `CourseConfiguration.cs` does not read it yet. That is the
contract working as designed (CLAUDE.md rule 4) — a request, not damage. It goes
green when you add the property, and the absent-vs-empty note above is the whole
of what it has to get right.

### What the Settings control does, and why

The mac's is a checklist of the course's folders, under a "Marks" heading. When
the course has never been asked, it shows the folders the build CURRENTLY counts
already ticked, so a teacher sees what is actually happening rather than a blank
list. Nothing is written until they change something — and the moment they do,
the answer is explicit and the historical rule stops applying to that course.

### Content declares its own pool

All 38 payload manifests and all 50 skeleton families now carry
`graded_folders`, and both linters refuse a manifest without one or one naming a
folder the course does not have. `setup_course.py` writes it at creation from
the manifest — shared Python, so you inherit that unchanged.

Declared rather than inferred deliberately: inference is a substring while the
build matches exactly, and those two agree for 88 of the 89 courses here and
disagree for the one that would have been broken by it.

### Where the rules live

`contracts/shared-rules.json` → `gradedFolders` (9 cases, run by
`scripts/test_graded_folders.py` in the image) and `contracts/file-formats.json`
for the key itself.

## Folder problems: the checks, and the four places they have to surface (2026-08-23)

Certain folder and file names carry behaviour — the curriculum folder, the folder
holding class pages, `Media`, a section's `index.md` — and nothing stopped a
teacher deleting or renaming one in Obsidian. The features then failed SILENTLY,
the Curriculum Coverage map worst of all: it still rendered, still looked
healthy, and was wrong.

**The checks are shared Python and you inherit them unchanged.**
`scripts/site_health.py` runs inside `build_site.py`, after the content merge and
before Quartz builds. You run the same file, so there is nothing to reimplement.
What you owe is the front end.

### Where they run, and where they honestly do not

They run in the toolchain rather than in the app because the GUI button is one of
five ways a build starts — the assistant, the MCP server, the launchers and the
scheduled task all bypass it, and the scheduled one runs with the app closed.

**Be careful repeating the "before anything is published" claim**, because an
earlier version of this section overstated it and it was corrected: `deploy.py`
publishes an EXISTING `public/` and only rebuilds when a live preview is
attached, and `deploy.sh --to-folder` never enters the Python at all. So a deploy
of a build made in an earlier session carries no health output of its own. The
findings are recorded when the BUILD happens. That is acceptable; claiming
otherwise is not.

### The sentence is not yours to write

Each finding is printed twice: once as a human sentence, and once as
`PLANTOIR_HEALTH: {json}` carrying `name`, `sentence`, `detail`, `fixable`,
`course`, `section`. **Display the `sentence` and `detail` the line carries.**
Do not compose your own from the `name` — the whole reason the wording travels in
the payload is so that the same problem cannot be worded differently on the two
platforms, and the sentences have one home in
`contracts/shared-rules.json` → `siteHealth.checks`.

A progress marker would not have done: those are matched loosely and getting one
wrong is silent (see `app-rules.json` → `markerOrigins`). A prefixed JSON line is
unambiguous and carries structure a sentence cannot.

### Three traps, all met here

- **Do not read the findings from a tail.** Every other structured-line reader in
  the mac's `ScriptRunner` works from `recentText(maximumCharacters: 8000)`, and
  the health lines print in the MIDDLE of a build. On any real build they are
  long past that window by the end. Collect them as output arrives. The mac test
  floods 400 lines after the finding to prove the point.
- **Hide the marker line from the console a teacher reads.** A raw JSON blob is
  machinery (rule 1). The human sentence is printed separately, so nothing is
  lost. The mac drops it in `TranscriptBuilder`, and reads findings from the raw
  text BEFORE handing it there.
- **Show it once.** The mac holds findings in view state rather than reading them
  off the runner at render time, so a teacher who dismisses the dialog and
  carries on editing does not meet it again on the next redraw. A healthy course
  must see nothing at all — the failure mode for this whole feature is nagging,
  and a warning dismissed by habit is dismissed when it matters.

### Offering to put it right

Two of the five findings are repairable — a missing `Media` folder and a missing
section front page — and three are NOT. The line is the whole design: **a fix
must restore the FEATURE, not merely satisfy the check.** Recreating an empty
curriculum folder would silence "the curriculum map could not be built" and
leave the map missing, because that folder only counts once it holds a page
named for an expectation code. A button that makes a warning go away without
fixing anything is worse than none, since the teacher then believes it is dealt
with.

**Decide from the check's NAME, not from `fixable` alone.** The flag in the
payload means "this kind of thing is repairable"; what has to be true before you
show a button is that YOUR app has a repair for it.

Three things the mac had to learn the hard way, all worth copying:

- **Never overwrite.** Both repairs check first, so pressing twice — or pressing
  after fixing it in Obsidian — changes nothing. The test that matters writes a
  teacher's own front page first and asserts it survives.
- **Report the outcome, including failure.** Both restores can fail (a read-only
  volume, a file sitting where the folder should be). Reporting only success
  made a failed repair indistinguishable from a successful one — the dialog just
  closed either way, which is silence on the failure path in the feature written
  to end silence.
- **Say what has not changed yet, and offer the RIGHT next step.** The folder is
  back on disk; the preview still shows how things were. A teacher who is told
  "put the Media folder back" will go and look at their site next. Offer the
  preview on BOTH occasions — including after a publish, because that is how a
  teacher checks the repair worked. What changes is the SENTENCE: after a
  publish it must name who is still seeing the old site (students) and what
  changes that (publishing again).

  This reversed an earlier decision, and the reasoning is the useful part. The
  preview was withheld after a publish on the grounds that it does not change
  what students see. True, and beside the point: withholding it removed
  something useful in order to prevent a misunderstanding that the words already
  prevent.

  Three things that fell out of widening the offer, all of which apply to you:

  - **The publish sentence must not assert a past publish.** It is shown after a
    FAILED deploy too, and for a section publishing for the first time nothing
    has ever gone out. Say what publishing WILL do, not what it did.
  - **Guard the preview against every publisher, not just your own button.** On
    the mac the assistant publishes the same section in the same process,
    invisible to the view's own deploy runner; the guard had to move to
    `CourseActivity`. While publish-origin findings offered no button this was
    unreachable — widening the offer is what made it a hazard.
  - **A preview build is never deploy-fresh** (`app-rules.json` →
    `buildFreshness`), so previewing after a successful publish means the next
    publish rebuilds. Correct, and largely moot: the repair puts content back,
    which forces a rebuild anyway.

  **Call the button "Preview Again", not "Build Again".** Russell asked what
  "Build Again" meant, which was the answer: the label never said WHAT would be
  built, and the thing on offer already has a name the teacher knows. Note this
  is a CLARITY point, not a rule 1 one — "build" is ordinary vocabulary in this
  product ("Click Preview to build this section's website") and does not need
  hunting down elsewhere.

One mac-specific mechanic that may or may not apply to you: a view presents one
alert at a time, so the outcome is shown from a state change AFTER the first
dialog has gone rather than raised inside its button action — asking for a second
while the first is dismissing loses one of them, and the one lost is the report
the teacher just asked for.

`FolderProblemRepaired` is a separate trail event from `FolderProblemFound`, on
purpose: one records that something is wrong, the other that somebody acted on
it, and a trail that could not tell them apart leaves "did they ever fix it?"
unanswerable. Both are in `contracts/shared-rules.json` → `activityTrail`, and
the repair rules themselves are in `siteHealth.repair`.

### A section with no index.md cannot be PUBLISHED — ✅ FIXED 2026-09-01, in shared Python, so you inherit it

Found while testing the deploy path on the mac; it broke identically on Windows
because it is in `scripts/`. Left open by the special-folders branch as a
separate piece, and closed on 2026-09-01. The reasoning is kept because the
second half of it was never on anybody's list.

**What it was.** `_sync_public_to_host` (`build_site.py`) copies the built site
back to the host only when `public/index.html` exists — and Quartz emits no root
`index.html` without an `index.md`. So the build SUCCEEDED and printed "Static
build complete", the sync was silently skipped, and `deploy.py` then reported
"Built site not found … Build first: ./preview.sh CODE N --build-only",
telling the teacher to do the thing they had just done.

**The guard is still right** — do not publish half a build. What was wrong is
that its answer went nowhere. The sync now RETURNS whether it mirrored a site,
and a `--build-only` run that mirrored nothing prints "Nothing to publish …
it has no front page, so no website was produced" and **exits non-zero**. That
matters more than the sentence: a publish runs `preview.sh --build-only` and
then `deploy`, so failing the build stops the run at the step that KNOWS the
reason. The mac already shows the folder-problem dialog on a failed build, so
the teacher gets **Put them back** → **Preview Again**; check that your own
failed-build path does the same rather than swallowing the findings.

**The half nobody had named, and the worse one.** The skipped sync left the
PREVIOUS build's `public/` on the host, and `deploy.py` uploads whatever it
finds there. So: delete a front page, build, publish — and the teacher is told
the publish succeeded while students get last week's pages. Nothing anywhere
said so. `_clear_stale_host_site` now removes that mirror whenever the merged
tree has no `index.md`, in BOTH preview and build modes, which turns a silent
wrong answer into an honest refusal. Nothing of the teacher's is lost:
`.merged_output` is derived from their notes and every successful build
rewrites it wholesale with `rsync --delete`.

**What you owe.** The Python is shared, so (almost) nothing. The exception is
`FailureExplainer.cs`, which gains `MissingFrontPageExplanation` — already
written on this side — and it must be asked **BEFORE** `MissingBuildExplanation`.
A publish puts both lines in one transcript, and "hasn't been built yet" is the
wrong thing to say to somebody who just watched it build. That ordering is a
contract case (`app-rules.json` → `failureExplanations`, the case whose
`output` carries both lines), so chaining it the other way round fails your
suite rather than shipping quietly.

**One thing to check rather than copy.** `_clear_stale_host_site` calls
`shutil.rmtree` on the host's `public/` — which under `PLANTOIR_BUILD_ROOT` is
outside the working folder, so outside OneDrive, which is the point of that
variable. If a scanner or an open handle makes the removal fail, the build says
so and carries on rather than dying; but the stale-publish risk returns for
that run. Worth one real test on a machine with OneDrive running, and tell the
mac what you find.

The `sectionIndexMissing` health check understated the same thing — "the site
will open on whatever page happens to come first" is true of a PREVIEW, and for
publishing there is no site at all. Its detail in `shared-rules.json` →
`siteHealth.checks` now names both outcomes, so a teacher can tell whether they
may carry on for now or must fix it before they publish.

### Renaming a course folder from inside the app — mac shipped 2026-09-01, Windows still to build

The `TODO.md` item deferred on 2026-08-23 while planning the special-folders
work, built on the mac once Russell chose the full scope. **You do not have it
yet**, and the contract carries most of what you need.

**Item 13 said "sentences, refusal rules and the list of keys … are all in
`shared-rules.json`". That was wrong** — four teacher-facing sentences from
this work live only in the mac's Swift, and they are listed under "Sentences
the contract does not carry" below. Corrected 2026-09-01 after adversarial
review; `GUI-IMPROVEMENTS.md` row 388.

**What it does.** A pencil on each folder row in Course Settings opens a sheet
that renames the folder ON DISK — in every section that has one — rewrites the
links that name it, and carries across every `course_config.json` key that
mentioned it. The keys are listed in the contract rather than here, at
`shared-rules.json` → `specialNames.renameFolder.carriesAcross`, and the mac
has a test that FAILS if a key is added to that list and not to the code. Copy
that test; it is the one that catches the failure this feature exists to
prevent (a config naming a folder that is not there).

**Two foot-guns closed in the same change**, and both are yours to mirror:
adding a name now CREATES the folder — it used to write a config entry pointing
at nothing — and removing one now says the folder and everything in it stays on
the teacher's machine, which nobody could tell before. Sentences:
`specialNames.addCreatesTheFolder` and `specialNames.removeLeavesTheFolderOnDisk`.

**Three decisions, with the reasoning, because none is obvious from the code.**

1. **It commits to disk immediately, not at Save.** Your Settings holds edits in
   memory and reverts them on Cancel, exactly as the mac's does. A folder that
   has really moved cannot be un-moved by a Cancel, so a rename that waited for
   Save would let Cancel appear to undo something it cannot. The mac writes the
   rename to a FRESH read of `course_config.json` (`CourseConfiguration.recordOnDisk`)
   so the teacher's other unsaved edits stay unsaved. That type is a mac type;
   the RULE is what to copy.
2. **~~The class folder must keep the word "class" in its new name.~~
   REVERSED the same day — do NOT build this refusal.** It shipped for a few
   hours because `ClassFolder` FOUND that folder by looking for the word.
   Russell's point: that is Plantoir's vocabulary imposed on a teacher's, and
   somebody whose units are Threads and whose classes are Days calls the folder
   "All Days". The lookup was what was at fault. `class_folder` is now a
   recorded key — the thing this entry called "the proper fix, deliberately NOT
   done" — and the rename MATERIALISES it. See "What a course calls its class
   folder" below; the sentence
   `specialNames.renameFolder.problems.classFolderMustSayClass` no longer
   exists.
3. **Nothing moves until every destination has been checked.** A per-section
   rename is several moves, and one that got half way through four sections
   would leave a course nobody could reason about.

**The trap that is yours alone.** Point 3 matters more on Windows than it does
here, because `Directory.Move` refuses a folder with an open handle and both
OneDrive and Obsidian hold them. Check every destination up front, and if a move
still fails, say WHICH section it failed in — the mac's message names the count
moved and the section that stopped it, and a bare exception would leave a
teacher with a course renamed in two sections out of four and no idea which.

**The trail.** Two new events, `folder renamed` and `folder created`, are in
`activityTrail.mustRecord`; the test that pins your `ActivityTrail` against that
list will fail until you add them. What they carry is in the contract — folder
NAMES, never anything from inside the folder.

**One thing the mac learned that changes how risky this looks.** The `TODO`
entry deferred this feature because it feared a rename would strand every
wikilink pointing into the folder, and that is wrong: Obsidian resolves
`[[Quiz 1]]` by searching the vault, so a bare page link survives the folder
moving. Only QUALIFIED links break — `[[Tasks/Quiz 1]]`, a full vault path, and
Obsidian's Markdown link style with its percent-encoded spaces. That is why this
shipped without the undo the deferral assumed it needed, and why you can build
it without one too. `FolderPathRewriter` is about 200 lines; its tests say
exactly which forms must change and which must not, and the "must not" half is
the important one — a rewriter that matched substrings would rename folders the
teacher never touched.

### What a course calls a unit — mac shipped 2026-09-01, and your suite goes RED first

The `TODO.md` item deferred on 2026-08-23. Russell chose the scope on
2026-09-01: **new courses plus configurable parsing, NOT renaming a course
already in use.** Read the "red suite" paragraph before you read anything else
here, because you will meet it before you meet the feature.

**Your suite will fail, and that is the mechanism working.** Three cases were
added to `contracts/class-planning.json` → `pageNaming`, each carrying a new
`term` field. A case WITHOUT that field means the DEFAULT word, "Unit" — so
read `term` with a default rather than treating its absence as a new shape, or
every existing case breaks. The case that matters most is the one where a
Module course must NOT read "Unit 2, Day 3" as a class page.

**What the feature is.** `unit_word` in `course_config.json` (documented in
`file-formats.json`), ABSENT meaning "Unit", so every course in the field is
untouched. A ready-made course holds **84–87** class pages (42 for the two
half-credit courses), not the ~3,000 an earlier draft of this section said —
that is the total across all 38 payloads. Corrections: `GUI-IMPROVEMENTS.md`
rows 388 and 389. The wizard asks "What do you call a unit?" of EVERY course,
ready-made ones included, and the payload is written in that word as it is
poured rather than renamed afterwards.

**Two of the three halves are shared Python and arrive free.**
`scripts/class_pages.py` is the rule — the default, the regexes, and the
rewrite — and `setup_course.py` applies it to the payload. You run both.

**What you owe:** a C# mirror of `ClassPageTerm` and of `UnitDay`'s `term`, a
field in your wizard, and the wizard writing `unit_word` into the config it
creates. Plus the assistant, in BOTH directions — and the input half is the one
that was got wrong here first: the mac's output sentences now say "Module 4 was
published", and `AssistPublishPlanner.unitNamed` now reads the course's word so
that "publish Module 4" is understood at all. Reading only the literal "unit"
meant the whole feature was missing for that course, silently, and it shipped
that way for a few hours. The assistant's unit sentences are hardcoded on both
sides and are not in `assist-wording.json`; they are listed below with the
others.

**Why the parsing half mattered more than the naming half, and why the cheap
option was rejected.** "New courses only, with the parsing left hardcoded" was
on the table and is wrong, for a reason worth carrying: `_is_class_page`
answering "no" does not FAIL. `_pages_the_course_teaches` returns nothing and
the curriculum map falls back to counting every published page — so a Module
course would have got a map that looked healthy and was wrong. That is the same
silent-success failure the whole special-names family exists to end.

**Four decisions, with the reasoning.**

1. **"Day" stays fixed.** A teacher who says "Thread" almost certainly still
   says "Day 3", and a second configurable word would double the migration for
   something nobody asked for.
2. **The word is escaped before it becomes a regex.** It comes from a teacher's
   own configuration; one containing "(" would otherwise match something else
   entirely, or fail to compile in the middle of a build. `Regex.Escape` is
   your equivalent.
3. **A number or a comma in the word is refused by the WIZARD**, which will not
   create the course until it is fixed. The command-line setup does something
   weaker on purpose — it says the name will not work and falls back to "Unit"
   rather than re-asking — because it is a single-pass script with no way back
   to a question. Either way the pages are never written under a name nothing
   can read back: built successfully, and silently outside every feature that
   works on class pages. **The sentences for both are Swift and Python
   respectively and are NOT in the contract** — see "Sentences the contract
   does not carry" below.
4. **The payload rewrite matches "Unit" only when a NUMBER follows.** That is
   what separates a unit reference from the ordinary English word, and it is
   run ONLY over content Plantoir itself ships, on the way into a brand-new
   course. Never let it near a teacher's own writing, where "Unit 3 of the
   textbook" would be a false positive nobody could undo. It deliberately
   catches the ~574 payload files that say "by the end of Unit 3" in prose,
   which would otherwise leave a Module course talking about Units.

**One design detail to copy rather than reinvent:** the word travels ON the
parsed value (`UnitDay.term`) and on the page summary, not looked up per call.
A page read out of a Module course is then written back as a Module page
without every planner needing the course handed to it as well — and the two
halves of a rename cannot disagree about which word they are in.

**What is deliberately NOT built, on either side:** renaming an existing
course's word. It means rewriting every class page's name, its frontmatter
title and every wikilink pointing at it, across every section and shared
folder, and a half-finished pass leaves a broken site with no way back. It
needs its own design pass and its own undo, and it stays in `TODO.md`. Do not
add it to your side alone.

### What a course calls its class folder — mac shipped 2026-09-01

Russell's ask, in his words: *"So we could have 'Thread' instead of 'Unit' and
'Day' instead of 'Class'?"* Yes — and the answer is a recorded key, not a
looser guess.

**`class_folder` in `course_config.json`**, documented in `file-formats.json`.
The recorded name wins when it is set and still one of the per-section folders;
otherwise the OLD GUESS applies unchanged — the first folder whose name
contains "class", else the first folder, else the literal "All Classes". Keep
the guess. Every course made before this key existed depends on it, and this is
additive by design.

**The part that is easy to get wrong: a rename MATERIALISES the key.** Carrying
an existing key across is not enough. A course made from scratch has NO
`class_folder` and `curriculum_folder: null`, so both folders are found by
guessing at their names. Rename `Curriculum` to `Expectations` without WRITING
the key and the guess stops finding it: the map is built from nothing, and
nobody is told — the coverage health check cannot fire, because from its point
of view the folder was never there. Pinned as
`specialNames.renameFolder.materialisesOnRename`, and the same rule covers
`class_folder` and `curriculum_folder` together.

**Six new naming cases and two membership cases** in `class-planning.json` →
`classFolder`, each carrying an optional `classFolder` field. **A case without
that field is a course that never recorded one**, so read it with a default
rather than treating its absence as a new shape — the same trap as `pageNaming`'s
`term`. Two of the cases are worth reading before you implement: a STALE key
(naming a folder no longer in the list) must lose to the guess, or the
next-class button writes into a folder that is not there; and a key differing
only in CASE from the list entry must return the LIST's spelling, because
everything downstream builds file paths out of the answer and a case-sensitive
volume would not find the key's.

**Membership widens, never shrinks.** The recorded folder is counted AND every
class-mentioning folder still is. Dropping the latter would shrink what a
course is seen to teach, which is the direction that produces the wrong map; a
course that had "Class Resources" counting yesterday must not lose it by
recording a class folder today.

**The removal block follows the recorded folder too**, so renaming
"All Classes" no longer leaves a course's class folder removable. The literal
"All Classes" is still blocked as well, for courses that never recorded one.

### Sentences the contract does not carry — write your own, knowingly

`contracts/` holds every sentence it can, and the handoff sections above say so
about the ones it does. These are the exceptions as of 2026-09-01, found by
adversarial review after an earlier draft of item 13 told you "sentences …
are all in `shared-rules.json`", which was not true. Each is teacher-facing,
each lives only in the mac's Swift, and each is one you will have to word
yourself — so word it deliberately rather than discovering the gap:

- **`ClassPageTerm.problem(with:)`** — the two wizard refusals for a unit word
  containing a digit or a comma.
- **`SpecialFolderRenamer.rename`'s half-failure sentence** — "Plantoir renamed
  N of M copies of 'X' and then could not rename the one in section3: …". The
  SHAPE is what matters and is worth copying: the count moved, and the section
  that stopped it. A bare exception here leaves a teacher with a course renamed
  in two sections out of four and no idea which.
- **`CourseSettingsView.renameFolder`'s bookkeeping-failure sentence** — the
  folder moved but the configuration could not be written. Do not report this
  as "the rename failed": it did not, and saying so sends the teacher looking
  for a folder under its old name.
- **The wizard's unit-word caption** — "Class pages will be named '… 1, Day 1'".
- **The assistant's unit sentences**, which item 13 wrongly said were "listed
  below with the others" until this line was added: "{word} N was published",
  "{word} N has already been published", "{word} N is already hidden", "{word} N
  was only partly published", and "I can't find any class pages in {word} N of
  …". They are hardcoded in `AssistToolRunner` and are in NO contract — not
  even `assist-wording.json`, which carries the rest of the assistant's words.
  That is a pre-existing gap this work inherited rather than made, and it is
  named here so you do not go looking for them.

**Three things the contract DOES carry that you must not copy verbatim.**
`specialNames.renameFolder.explanation`,
`specialNames.renameFolder.doneNothingWasThere` and
`specialNames.removeLeavesTheFolderOnDisk.message` all say "on your Mac".
Substitute "on this PC", the same way you already do for `app-rules.json`'s
"this Mac" — `contracts/README.md` documents that substitution. Your contract
test must compare on the substituted form or it will fail on a difference that
is correct.

### Publishing while a preview is running — the race, and the harness that found it

Two defects on 2026-09-05, both in the publish path, both invisible to every
test that does not publish and then LOOK at what came out.

**The race, which is the one that matters.** Killing the preview LAUNCHER does
not stop the preview. On the mac the Python and the node server both live
inside the container, and `_start_public_sync_watcher` keeps mirroring the
SERVE build to the host every second — so a build for publishing lands and the
preview overwrites it within a second, and what gets published is the preview,
live-reload client and all. `kill_existing_quartz` was only ever called from
the SERVE branch, so `--build-only` never stopped anything.

`build_site.py`'s `--build-only` now stops the preview serving THIS SECTION
before building, matched by the section's own build directory.
**That is shared Python and you inherit it.**

**It was written by PORT first, and that was wrong — do not go back to it.**
`kill_existing_quartz(port)` looked like the obvious tool and is the right one
for the SERVE path, where the port is known and leased. A build-only run is
never given a port: `preview.sh` defaults it to 8081 and the app's deploy
passes no `--port` at all. So the first version killed whatever was serving on
8081 — the first section to have previewed in that working folder, which is
usually a DIFFERENT section from the one being published. Measured 2026-09-05
by doing it: previewing section 1 and publishing section 2 printed "Killed
existing process on port 8081" and section 1 stopped answering. A scheduled
overnight deploy would have done the same to any preview left running.

What works instead is the section's BUILD DIRECTORY, which is on the serve
process's command line because the launcher runs the Quartz CLI by absolute
path. It identifies exactly one preview and cannot collide with another. One
detail that is easy to miss: match on the directory plus a trailing separator,
or `section1` also matches `section10`.

Two things to check on your side rather than assume:

- **Your preview is not in a container**, so an orphaned server is a plain
  Windows process. Check that killing your launcher actually stops the node
  server — on the mac it demonstrably does not, and that is exactly the kind of
  difference that is assumed rather than measured.
- **`/proc` is how the mac finds it**, and you do not have one. The mac's
  version is a no-op wherever `/proc` is absent, so on Windows today NOTHING
  stops an orphaned preview before a build. Finding the equivalent — a process
  whose command line contains the section's build directory — is yours to
  write, and until you do, a publish that rebuilds while a preview is running
  can still lose the race.

**The other one was a partial fix of mine, and is worth knowing as a shape.**
The first version of the preview guard in `deploy.sh` waited for `index.html`
to lose the live-reload client. Serve mode bakes that client into EVERY page
and the mirror is replaced file by file, so a clean front page can sit in front
of two hundred stale preview pages. Publishing that MIXTURE is worse than
publishing the preview wholesale, because the front page looks fine and nobody
looks further. Wait on the whole tree; `deploy.ps1` already does.

### `verify-deploy.sh` — the publishing harness, and why it is not in the gate

New on 2026-09-05, at the repository root. It publishes to a folder, to Netlify
and to Cloudflare, and runs all three primary+secondary pairings, then **fetches
every published site back and reads it** — the launcher's own output only
proves the launcher is happy with itself. 42 checks.

**It is deliberately NOT part of `verify.sh`.** The gate must be runnable at any
moment, on any machine, without credentials and without touching anything
outside the repository. This needs a Netlify token, a Cloudflare token and an
account ID, it needs the network, and it CREATES REAL SITES. Build the Windows
equivalent the same way — opt-in, run when the publishing path changes — rather
than folding it into whatever you gate on.

One thing it does NOT cover, stated so nobody assumes otherwise:
`additional_deploy_targets` is not handled by `deploy.sh` at all — the APP loops
and calls the launcher once per destination. The harness exercises the pairings
by running that same sequence, which tests the launcher half; that the app
produces exactly those argument lists is pinned separately by
`app-rules.json` → `deployArguments`, which your suite already runs. Between the
two the pairing is covered; neither half covers it alone.

### The scheduled task NEVER refuses

Russell's call, and the reasoning travels: *"a slightly inaccurate curriculum map
is a paper cut, an unpublished site update a teacher was counting on is a broken
nose."* Pinned as `siteHealth.scheduledDeployPublishesAnyway` and asserted by a
mac test so it cannot be quietly softened later.

So: publish, then stash what was found for the next time somebody is there. You
already have the shape — `ScheduledDeployCompletion.cs` stashes a completion
sentinel exactly this way. Two properties the mac's version has that yours should
too: the record is CONSUMED when read, so a problem is reported once rather than
every time the app opens; and a CLEAN run clears it, so a problem the teacher has
put right stops being reported.

**That second property is harder than it looks, and this section claimed it
before it was true.** launchd opens the scheduled log with O_APPEND and nothing
rotates or truncates it, so reading the whole file re-finds LAST week's marker
lines every night: the sentinel is rewritten with stale findings forever, and the
"nothing wrong this time" branch becomes unreachable the moment a single problem
has ever been logged. A teacher who fixed the folder would have been told about
it every morning until somebody deleted the log.

The mac now records the log's SIZE before the run and reads only from that offset
afterwards. If your task runner captures output per run you may not have this
problem at all — but check rather than assume. And note how it got through: the
test that was supposed to cover it faked the append by rewriting the file, so it
passed against broken code.

One platform difference worth knowing: the mac reads the findings back out of the
scheduled run's LOG FILE rather than from a pipe, because `runScheduled`
deliberately does not capture the child's output — launchd points stdout at that
log and the process inherits it, and an unread pipe is what wedged your own
assistant server. If your task runner already captures output, use what you have;
the log-scrape is a workaround for a constraint you may not share.

### Deploys with several destinations

Take the findings from the FIRST leg only. Every destination publishes the same
built site, so a second leg repeats them.

### Trail event

`FolderProblemFound` is in `ActivityTrail.cs` and in
`contracts/shared-rules.json` → `activityTrail.mustRecord`. The line reads
`found a problem with this course's folders (curriculumCoverageFoundNothing)` —
a sentence a teacher would recognise, carrying the stable check NAME in brackets.
Both halves earn their place: rule 5 wants a line that reads as something that
happened, and the name is what somebody searching the trail months later can
match against the contract, since the product wording will have been reworded by
then.

**The mac suite fails a declared trail event that has no call site** — which is
what forced the front end to be written rather than promised. Worth checking
whether your suite does the same; if not, it is a cheap test to add.

## "Where do the class pages live?" had four answers — and yours was the worst (2026-08-23)

**Action required on your side: build and test. The C# below was written on the
mac, which has no dotnet, so it has compiled nowhere.**

A teacher whose class folder is not called "All Classes" — "Class Pages", say —
used to get a different answer from each of four places:

| Where | What it asked |
|---|---|
| mac `ClassPages.folderURL` | the course's CONFIGURED per-section folders, first containing "class" |
| mac `AssistSectionGraph.isClassPage` | the page's IMMEDIATE parent contains "class" |
| `build_site.py` | any segment of the ABSOLUTE path EQUALS "all classes" or "classes" |
| your `AssistWorkspace.Plan` | the whole ABSOLUTE directory string contains "class" |

Three of those are wrong in ways worth knowing:

- **The build's.** Exact strings, so "Class Pages" matched nothing. When no
  class pages are found, `_pages_the_course_teaches` returns `None` and the
  Curriculum Coverage map falls back from "pages the course teaches" to "every
  published page". The map still renders, still looks healthy, and is wrong —
  the failure this whole piece exists to close.
- **The build's, again — and this is a CORRECTION to what this section said
  first.** An earlier draft claimed the build had been counting pages by their
  file NAME, and named "How This Class Works.md" and ADA1O's "B3. Connections
  Beyond the Classroom.md" as pages it had miscounted. That was wrong. The old
  rule was `part.lower() in ("all classes", "classes")` — membership in a
  tuple, i.e. EQUALITY — so no page was ever counted for its name. The real
  defect in the same line was different and worse: `content_root.rglob` yields
  ABSOLUTE paths, so it walked every segment above the content root too. A
  teacher whose working folder was `~/Documents/All Classes` made every page in
  every course a lesson — the same bug as yours, on the other platform. The
  file-name exclusion is kept as defence in depth for a future change to
  substring matching, and is labelled as such rather than as a fix.
- **Yours.** `Path.GetDirectoryName(pagePath)` is the absolute directory, so a
  teacher whose working folder is `C:\Users\x\Classroom\` makes **every page
  in every course** a class page. Where somebody keeps their files is not a fact
  about their lessons. This is the one that needed fixing most and could not
  have been found from the mac.

**The one rule**, in `contracts/class-planning.json` → `classFolder`:

- *naming* (where a NEW page is written): the first configured per-section
  folder whose name CONTAINS "class" (case-insensitive), else the first entry,
  else the literal "All Classes". Substring is safe here — it is a short list
  the teacher chose.
- *membership* (which folders COUNT): EVERY configured per-section folder whose
  name contains "class", falling back to the single name naming chose. Added
  after review: naming and membership are the same question only when a course
  has one such folder, and a course configured
  `["Class Resources", "All Classes"]` would otherwise resolve to the first for
  both, match zero pages, and drop the coverage map back to "every published
  page" — reintroducing the exact silent failure the rule closes.
- *isClassPage*: not an `index.md`, and one FOLDER segment — never the file
  name — EQUALS that folder's name, case-insensitively, with the path taken
  RELATIVE to the content root.

The asymmetry is deliberate and is the part worth not "simplifying" later:
naming may use a substring because its input is curated; page matching may not,
because its input is arbitrary paths. A classics course's "Classical Studies"
folder must not be mistaken for where its lessons live.

**What changed on your side:**

- new `Plantoir.Core/Models/ClassFolderRule.cs` — `Name(...)` and
  `IsClassPage(relativePath, classFolder)`. It is called `ClassFolderRule`, not
  `ClassFolder`, because `AssistWorkspace` already has a private `ClassFolder`
  method that returns a PATH, and two things with one name returning different
  kinds of answer is how the next bug gets written;
- `AssistWorkspace.Plan` now calls
  `ClassFolderRule.IsClassPage(Relative(pagePath), ClassFolderRule.Names(...))`
  — note `Relative(...)`, which is the fix for the `Classroom` bug. **The rule
  is a pure segment matcher and cannot tell an absolute path from a relative
  one**, so `Relative(...)` is the whole protection: if you ever call
  `IsClassPage` from somewhere else, pass a relative path or you reintroduce
  the bug. The mac learned this the same way — its own `AssistSectionPage` had
  to gain a `pathWithinSection` because `relativePath` is the FULL ABSOLUTE
  PATH whenever `workspaceURL` is nil;
- `ClassFolderRule.Name`/`Names` skip null and empty entries: these lists come
  from JSON, including the contract's own case data, and unguarded LINQ threw
  where Swift and Python coerce;
- `AssistWorkspace.ClassFolder(course, section)` delegates its naming half;
- new `Plantoir.Tests/ClassFolderContractTests.cs`, deserialising the same 5 + 9
  cases the mac suite and `scripts/test_class_folder.py` run.

**Rejected:** unifying on "contains class" everywhere. It reads well and it
reclassifies real shipped pages — see the payload examples above. Segment
EQUALITY for pages, substring only for the configured list, is the distinction
that makes the rule safe.

## The scripts can now read the contract — and it travels differently on Windows (2026-08-23)

`contracts/` used to be readable only by the two test suites. It is now readable
from `scripts/*.py` as well, through `scripts/contracts.py`. This is the spine of
a larger piece (hardening the folder and file names that carry hidden meaning —
`Tasks`, the curriculum folder, `All Classes`, `Media`, `index.md`,
`Key Links.md`), and it matters to you because the rules being hardened live in
`build_site.py`, which is the thing that actually decides what ships. A rule that
lives there and nowhere a test can reach is a third implementation with no gate
on it — the drift the contract exists to prevent, arriving by the back door.

**Why it had to be baked into the image, and what that costs.** The container's
ONLY bind mount is `courses` (see `preview.sh`, `deploy.sh`). The working
folder's `.toolchain/` sits beside `courses/` and is NOT mounted; the app bundle
is on the host. So neither of the two obvious routes can be read from inside the
container, and the contract has to be `COPY`d in by the Dockerfile. The
consequence is deliberate: `contracts/` is not in `toolchain_hash`'s prune list,
so every contract edit mints a new `teaching-quartz:src-<hash>` tag and forces an
image rebuild and container recreate. That is development-time cost on the mac,
paid on every case added, and it was accepted because the alternative was a
shared rule the build cannot see.

**None of that applies to you, and that is the point of this section.** Windows
runs these scripts NATIVELY — no container, no image, no hash. The contract
reaches Python through `PLANTOIR_CONTRACTS_DIR`, exactly the way
`PLANTOIR_SUPPORT_DIR` already reaches `support/`. Five things carry it:

- `ToolchainMirror.RecipeFolders` gained `contracts`, so a working folder's
  `.toolchain/` gets it;
- `Plantoir.csproj` ships `Toolchain\contracts\`;
- `setup.ps1`, `preview.ps1` and `deploy.ps1` set `PLANTOIR_CONTRACTS_DIR`;
- `Vendor/fetch-runtime.ps1` sets it too — a SIXTH env-setting site the first
  pass missed, and the kind that is latent until it is not: it runs
  `setup_course.py` while provisioning the runtime, so the first time a script
  reads a required contract there, it throws `ContractMissing` naming
  `/opt/contracts` on a Windows host. That error names a container path on a
  machine that has no container, which is about as confusing as a message gets.

**If you add another place that runs a `scripts/*.py`, it needs the variable.**
There is no way to make this fail loudly at build time; it fails at run time, in
whatever feature happened to read a contract first.

**A trap that cost real time here, and travels to you unchanged.** The recipe's
folder list existed as FOUR hand-maintained copies: the mac's
`WorkspaceModel.refreshToolchain`, your `ToolchainMirror.RecipeFolders`, the
marketing screenshot harness (`website/shots/capture.py`), and the Dockerfile's
own `COPY` lines. They drifted the moment a fifth folder was added, and the one
that drifted was the harness — whose docstring said, in so many words, "keep them
in step".

The failure mode is worth understanding because it is not the one you would
guess. `capture.py` copies the *Dockerfile* too. So the demo workspace got a
Dockerfile containing `COPY contracts/ /opt/contracts/` with no `contracts/`
beside it. That workspace is not STALE, it is **unbuildable**: `docker buildx
build` fails on the missing `COPY`, and `preview.sh`'s friendly "this folder is
missing the toolchain's build recipe" message cannot fire, because
`resolve_build_context` only checks that the Dockerfile EXISTS — and it does.
A folder list that is merely incomplete produces a hard build failure with a
misleading diagnosis.

The fix, and the pattern worth copying: the list became DATA
(`contracts/toolchain.json` → `recipeFolders`), and `scripts/test_recipe_folders.py`
pins every carrier against it — including your `ToolchainMirror.cs` and
`Plantoir.csproj`, which it reads as TEXT. That is deliberate: one Python test
can pin a Swift list and a C# list, where a C#-only test could only ever check
its own half. The test was verified to actually fail when a copy drifts, which
is the check people skip. **If you add a recipe folder on your side, add it to
`recipeFolders` and let the test tell the mac.**

**Rejected:** leaving the list in code and adding a comment (that is exactly what
was there, and it is what failed); and having each platform's own suite check
only its own copy (two green suites, still drifted).


## The course-code picker is a hand-built combo box — and you probably should NOT build one (2026-08-23)

`GUI-IMPROVEMENTS.md` rows 333–338 describe the new-course wizard's course-code
field being rebuilt over two days: a searchable field with a rich two-line
flyout, a chevron that toggles it, arrow-key navigation, and geometry matched
to a real `NSComboBox` to the pixel. **Read this section before you copy any of
it**, because the central decision does not transfer and following the rows
alone would have you re-derive a lot of behaviour you can get for free.

Nothing here is a contract case. Every part of it is either visual, measured,
or built out of platform focus-and-key mechanics — the categories rule 2 sends
to a handoff rather than to `contracts/`.

### Why the mac hand-built it, and why that reason is probably yours to ignore

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
real control and you inherit, at no cost, everything the rows below describe
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
