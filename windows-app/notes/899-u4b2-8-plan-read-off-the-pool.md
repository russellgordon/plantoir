# 899 U4b2-8: a rename's planning read stuck on a dead volume holds none of Swift's shared threads (#899)

Branch `issue/899-u4b2-8-plan-read-off-the-pool`, from `origin/issue/899-u4b2-7-planning-rename-holds-nothing` 4df184372 (which contains `dev` 24fcbc718). `origin/dev` was fetched before proving and again before hand-back and was still 24fcbc718, already in the base, so there was nothing to merge and no merge commit was made (either time). (Merged on 2026-11-26 in `night25/integration-6`, 5b782bec9, with U4b2-7, -9 and -10 and W7b2-3. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12.)

## Must-fail lines

Seven rows, all RED, each restored byte for byte (`git diff` of `mac-app/QuartzTeachers` empty afterwards). Full log: `windows-app/notes/899-u4b2-8-mustfail.log`.

1. mf1, the walk in `Task.detached` again (the brief's row): `testRenameThenCancelOnADeadVolumeLeavesTheSharedThreadsFree` fails at line 1428, "round 13's plan never started, with 12 held on a Mac of 12 cores: the stuck reads hold the shared threads". It also fails at line 1425, where round 12's rename does not return after Cancel.
2. mf2, `stopIfThePlanIsHalted` ignores the thread being cancelled. The same test fails at line 1447, "a cancelled plan went on reading pages" (64 against 16). The part-seven test also fails at line 1368, "the cancelled plan went on reading pages" (4 against 1).
3. mf3, `cancelRename` closes the sheet without halting: `testTheRealSheetsCancelHaltsAHeldPlanAndClosesTheSheet` fails at line 1029, "Cancel did not halt the rename in its own turn", and at line 1033, "the sheet's Cancel did not reach the held plan".
4. mf4, Cancel halts inside a fresh `Task`: the same test fails at line 1029, "Cancel did not halt the rename in its own turn".
5. mf5, the list's `.onDisappear` is removed: `testTheRealSheetGoingAwayHaltsAHeldPlan` fails at line 1083, "the sheet going away did not halt the held plan". (Superseded by review 1: the list's `.onDisappear` and that test are gone, replaced by the page and rows mf8 to mf10.)
6. mf6, `answerWhileAQuitGoesAhead` ignores the latch: `testASecondQuitRequestWhileAQuitGoesAheadAsksNothingAndRefusesNothing` fails at line 1144 (nil against `.terminateLater`).
7. mf7, the guard is taken out of `applicationShouldTerminate`: the same test fails at lines 1160 and 1164 ("the delegate does not ask about a quit already going ahead first").

Red before the fix:

- `testRenameThenCancelOnADeadVolumeLeavesTheSharedThreadsFree`, with the old `Task.detached` walk (`run-red2`): RED, line 1227, "round 13's plan never started, with 12 held on a Mac of 12 cores: the stuck reads hold the shared threads". Its first form was `async` and HUNG (`run-red1`): XCTest's async wait needs a pool thread, and all twelve were held. A sample showed twelve cooperative-pool threads in `EveryPlanHold.arrive` and the main thread in `XCTWaiter`. The run was killed by pid, and the test was rewritten synchronous so that its waits spin the main run loop and a starved pool fails it on its bounds.
- `testTheRealSheetGoingAwayHaltsAHeldPlan`, with the list taken away and only the sheet's own `.onDisappear` (`run-new6`, `run-new7`): RED, "the sheet going away did not halt the held plan". A diagnostic line showed the sheet gone and the run's task still live. The fix (the list's own `.onDisappear`) went in after that.
- `testTheRealSheetsCancelHaltsAHeldPlanAndClosesTheSheet` and the LOW-b test passed at once. The view's Cancel was already right, and the LOW-b function did not exist before (the test cannot compile against the old code). Their red proof is rows mf3, mf4, mf6 and mf7.

## Runs

All through `xlock.sh` with the 900 s kill, derived data `.dd/` in the worktree.

- `run-red1`: the pool test, async form, old walk: hung, killed by pid (above).
- `run-red2`: the pool test, synchronous, old walk: RED (above).
- `run-green1`: the pool test with the fix: passed. `U4b2-8 threads: cores 12, rounds 16, before 7, with 16 plans held 23, after they were let go 7`.
- `run-new1` to `run-new8`: the new LOW-a and LOW-b tests while they were being written. Compile errors first, then the in-process accessibility tree, which SwiftUI leaves empty: `SheetHostingView` had 0 children, so the tests use the AX API an assistive app uses. Then the red above, then green.
- `run-own1`: the brief's classes (UndoRenameFolderStepTests, SpecialFolderRenamerTests, CourseActivityTests), every class that reads a changed file as source text (UndoWriterScanTests; AppUpdatesStartTests, PreviewBuildRecordTests, SectionDetailStructureTests, ToolchainFingerprintTests for `AppDelegate.swift`; AccessibilityNamesTests, NameTableTests, SheetTitleScanTests for `StringListEditorView.swift`), QuitConfirmationTests, StringListEditorTests, and the 17 classes that walk the whole source tree: **578 tests, 0 failures, 0 skipped**. Thread line: before 10, with 16 held 26, after 10.
- `run-mf1` to `run-mf7`: the must-fail rows.
- `run-final` (restored tree, after the last test edit): the brief's classes and every source reader of a changed file, with QuitConfirmationTests and StringListEditorTests: 193 tests, 0 failures, 0 skipped.

Measured once (the brief's "measure once"), Mac16,8, 12 active cores. Process threads (`proc_pidinfo` `pti_threadnum`) before, with 16 Rename-then-Cancel rounds held, and after letting go: 7, 23, 7 (`run-green1`) and 10, 26, 10 (`run-own1`). That is one dedicated thread per stuck plan and none of the pool's. The brief said 12 rounds. The test uses cores + 4 (16 here), because 12 only equals this Mac's pool width, and the invariant is about more plans than the pool has threads. The 4 is a margin chosen once, not tuned.

**Which thread a stuck read runs on, and why it costs nothing the app needs.** The walk is a Foundation `Thread` started by `planHaltingAtCancel`, one per plan, named "Plantoir: planning a folder rename", with quality of service `.userInitiated`. It is not a thread of Swift's cooperative pool (`com.apple.root.*.cooperative`) and not the main thread. A read stuck there blocks only that thread: its stack (Foundation's default for a secondary thread is 512 KB, reserved rather than committed) and one kernel thread. Nothing else is scheduled onto it, and every `Task`, every `await` and the main actor go on. The thread ends by itself when the system read returns. It then stops at the next check (it has been cancelled) and delivers into a stream nobody reads.

## Review 1 (`vm-tools/briefs/2026-11-25-899-u4b2-8-review-1.md`)

The dedicated `Thread` stands: the reviewer and the director agree it is the right tool for a read that may never return, because no Swift concurrency form can interrupt a read blocked in the kernel, and a custom executor would still need a thread per stuck plan.

- **M1, fixed structurally.** A list's appearance no longer decides a rename's life. The list-level `.onDisappear` (`StringListEditorView`) is gone. Course Settings owns its two renames in a small `@Observable` model, `CourseSettingsRenames` (`FolderRenameRun.swift`), with one `FolderRenameRun` per folder list, handed to each list as `renameRun`. The page's own `.onDisappear` calls `renames.pageIsGoingAway()`, which halts each through the one `haltIfStillPlanning`. The page (`CourseSettingsView`, drawn by `CourseDetailView` only while Settings is chosen, inside the non-lazy `TabArea`) is the level that is not drawn lazily, and its going away is the real event: Settings left for Planning, the course closed or switched, the window closed. The sheet content's own `.onDisappear` is kept: it is the sheet's, not a row's. New test `testTheRealSettingsPageShrunkOrScrolledKeepsARenameAndLeavingItHalts` hosts the real page, grouped `Form` and all, in an off-screen resizable window. It presses the per-section Tasks row's pencil, types into the sheet's field and presses Rename, all through accessibility, then holds the plan. Made 220 points tall, the row is out of view (its accessibility frame outside the window) and the rename goes on. Scrolled to the form's top and to its bottom, the row is out of view and the rename goes on. Leaving the page halts it, with nothing written.
  - **Red first:** not possible for the shrink and scroll half. The test was run against the first round's code, with the list-level `.onDisappear` (`run-r1diag2`, `run-r1diag3`), and passed: in this harness the grouped `Form` did not unload the row, and no `.onDisappear` fired when it left the visible area. The pencil's frame moved from below the window to above it, and the pencil stayed in the tree. So M1's scenario did not reproduce here, today. The fix makes it impossible whatever a later macOS draws lazily, as the director asked, rather than settling it by this measurement. The leave-the-page half is proved red by rows mf8 to mf10.
- **L1 (notes only).** There is no bound on parked threads: one per stuck Rename-then-Cancel round, about 512 KB of stack reserved each, and the process limit is in the thousands. A cap would add a refusal and an interim state, so none was added.
- **L2.** A thread that never starts (`pthread_create` failing, reachable only after L1's pile-up) leaves the stream unfinished. That is the same state as a walk stuck in a read before its first delivery: the rename waits with its spinner, and Cancel or a quit ends it at once, because the stream's `next()` returns nil on cancellation. It is pinned by the held-plan tests (`testCancelWhileThePlanIsHeldGivesTheCourseBackAndTheHeldPlanChangesNothing`, `testAQuitWhileARenameOnlyPlansHaltsItAndDoesNotWait`), whose plan delivers nothing while held, exactly as a walk that never started. No start-failure detection was added: `Thread.start` reports no failure to its caller.
- **L3 (notes only).** The nested `.terminateLater` answer is safe by reasoning, not measurement (above, "For the director").
- **L4.** The accessibility-driven tests skip by throwing `XCTSkip` (`AccessibilityInspector.skipUnlessTheWindowCanBeRead`), and XCTest reports that as skipped, never passed. Every run here counted 0 skipped.
- **L5, fixed.** `holdThePlanAtItsFirstPage()` (used by the real-sheet Cancel test and the page test) opens the hold in its teardown block, then waits there on `planHasEnded` before `tearDown` clears the hooks, so the released walk never reads a hook while it is being cleared.

Review 1 must-fail rows, all RED, restored byte for byte:

8. mf8, the page's `.onDisappear` is removed: the page test fails at line 1120, "leaving the page did not halt the rename while it planned".
9. mf9, the per-section list is not handed the page's run: the same test fails at line 1120.
10. mf10, `pageIsGoingAway` halts only the shared list: the same test fails at line 1120.

Review 1 runs: `run-r1red` and `run-r1diag` while the test was being written (the window's title is the course code once Course Settings sets it, so windows are matched by the title the window has, not the one the test gave). Then `run-r1diag2` and `run-r1diag3`, the first round's code, which passed (above). Then `run-r1green`, the fix: 2 tests, 0 failures. Then `run-mf8` to `run-mf10`. Then `run-r1own`: the brief's classes, every source reader of each changed file (now including GradedFolderChoicesTests, SaveEnablesTests, SettingsSaveNoticeTests, TwoWindowSettingsTests for `CourseSettingsView.swift`), QuitConfirmationTests, StringListEditorTests and the 17 whole-source scanners: **631 tests, 0 failures, 0 skipped**.

## Left for the next piece

- A real window close while the rename only plans is not driven: `TableHost`'s window keeps its view (`isReleasedWhenClosed = false`). In the app, a window closing tears down its page, and the page's `.onDisappear` then halts. That is not proven by a test.
- `testTheRenameSheetCallsItsRunForEveryWayOut` (the source-text test) is kept. The real-chain tests back its Cancel check (its sheet `.onDisappear` check is now the sheet's alone, with the page holding the real halt), and it still pins Rename's `canStart` wiring and `using: onRename,`, which the real Rename press also exercises.
- Review 1 L3 of piece 7 (a re-plan after `changedSince` keeps its claim swapping) is unchanged and was not in this brief.

## For the director

No parked question.

- **An interface-visible change, small, and found by the new test**, not designed. A rename that is only planning is now also halted when its Course Settings page goes away (after review 1: the page, not the list). Before this piece, the sheet closed with the list and the plan went on (measured, `run-new7`). HIG: I re-read "Sheets" and "Progress indicators" today (developer.apple.com JSON). A sheet's Cancel "dismisses without saving", and "If people can interrupt a process without causing negative side effects, include a Cancel button". Halting a plan loses nothing, so a sheet taken away is treated as Cancel, as the comment on the sheet's `.onDisappear` already said ("However the sheet goes"). No new control, no wording, no key.
- **LOW-b, from Apple's documentation** (read today, developer.apple.com JSON of `NSApplication.TerminateReply.terminateLater`, `applicationShouldTerminate(_:)` and `reply(toApplicationShouldTerminate:)`). `terminateLater`: "Returning this value causes Cocoa to run the run loop in the NSModalPanelRunLoopMode until your app subsequently calls reply(toApplicationShouldTerminate:) with the value true or false. This return value is for delegates that need to provide document modal alerts (sheets) in order to decide whether to quit." That mode takes input (it exists so that sheets work), and none of the three pages says `terminate(_:)` is ignored meanwhile. I therefore treated a second request as possible and made it safe. `AppDelegate.answerWhileAQuitGoesAhead()`, asked first in `applicationShouldTerminate`, answers `.terminateLater` while `FolderRenameRun.quitIsGoingAhead` is set: no question, no halting, no new wait, never `.terminateCancel`. Whichever request AppKit is then waiting on, the first quit's `reply(true)` (or the set-aside update's) ends the process. I did not measure what AppKit actually does with a nested request. The test proves the answer and that the delegate asks it first, but not AppKit's behaviour. Calling the real `applicationShouldTerminate` from a unit test would, without the guard, run `letEverythingGo` in the test host, or put up the work-under-way alert, so the delegate's use of the guard is pinned by reading its first statements with comment lines left out.
- LOW-a: the two real-chain tests use the AX API (`AXUIElementCreateApplication` of this process), as `SaveEnablesTests` does. They skip, by `AccessibilityInspector.skipUnlessTheWindowCanBeRead`, when the screen is locked or the window is on a Space that is not showing. They did not skip in any run here.

## Self-check

1. Broke each fix and watched its test fail: ten rows, all RED (above), plus the two reds before the fix. The shrink and scroll half of the page test could not be red first (review 1, above).
2. No timed waits: none in the product. The tests wait on events (a plan reaching its page, a rename returning, the unrelated task running, every plan ending) with bounds that FAIL: 30 s, copied from the part-seven tests, and 10 s for the unrelated task, which a free pool runs at once. `host.pump(0.3/0.6)` is the existing host's settle for layout, not a wait for the behaviour under test.
3. Failure-path sentences: none changed. A halted rename says nothing (as before), and a second quit request shows nothing.
4. `dev` merged before proving: `origin/dev` 24fcbc718 is already in the base and did not move. No merge commit was needed.
5. No number tuned by trial: rounds = cores + 4, chosen once; the bounds are copied from existing tests. No count was adjusted to pass.
6. House style and contracts: no `contracts/` change. Changed outside `mac-app/`: only documentation 09 and this notes folder.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added lines: empty. New types have MARK sections (`CourseSettingsRenames`, `EveryPlanHold`, `ThreadCount`, `RenameSheetButtons`, `RenameSheetShown`, `ShownWhile`).
8. Riding lows: part eight's L2 is fixed, with a test red first. LOW-a is backed by two real-chain tests, one red first and one by sabotage, and they found and fixed a real gap. LOW-b is answered from Apple's documentation and made safe, with a test proved red by sabotage.
9. The rename record is still kept (not touched). `undoJournalIsLive` is still off (not touched).
10. No new or changed contract row; no ledger row.
