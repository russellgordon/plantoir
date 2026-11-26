# 899 U4b2-8: a rename's planning read stuck on a dead volume holds none of Swift's shared threads (#899)

Branch `issue/899-u4b2-8-plan-read-off-the-pool`, from `origin/issue/899-u4b2-7-planning-rename-holds-nothing` 4df184372 (which contains `dev` 24fcbc718). `origin/dev` was fetched before proving and again before hand-back and was still 24fcbc718, already in the base, so there was nothing to merge and no merge commit was made (either time).

## For PROGRESS

- Mac, U4b2-8: a Rename folder's planning walk runs on a thread of its own, never on Swift's shared pool of threads. On a dead volume, where a page read can block inside the system and cannot be interrupted, repeated Rename then Cancel used to take one of the pool's threads each round (twelve on this Mac), and once they were all held no other async work in the app could run. A stuck walk now costs only its own thread. Riding lows from U4b2-7 review 2: the real rename sheet is now hosted off screen in two tests that press its own Rename and Cancel through accessibility. They found that the sheet's own "went away" handler is not called when the list that presents it leaves the window, so the list now halts a planning rename as it goes too. A second quit request that arrives while a quit is already going ahead is answered at once, asking nothing and refusing nothing.

## For documentation 12

What Windows must do (W8), with the numbers measured here:

- **The plan walk runs on a dedicated thread**: `new Thread(...) { IsBackground = true }` started per plan, or `Task.Factory.StartNew(..., TaskCreationOptions.LongRunning)`, which gives the delegate its own thread. Never a plain `Task.Run`. The reason is the same as on the Mac. A blocking file read on a vanished network volume or an evicted cloud file cannot be cancelled, and on the shared thread pool each stuck read holds a pool thread until the system gives up. Rename then Cancel repeated on a dead volume would take them one by one. .NET's pool grows slowly (about one thread every half second past its minimum), so everything else the app runs on the pool would crawl. On the Mac (Mac16,8, 12 cores), Swift's pool is exactly 12 threads wide. With the walk on the pool, the 13th held plan never started and an unrelated job never ran. With the walk on its own thread, 16 held plans all started, an unrelated job ran at once, and the process went from 7 threads to 23 while they were held and back to 7 once they were let go. A second run gave 10, 26 and 10.
- **Cancellation is a flag the walk checks**, between folders and before and after each page is read: the dialog's Cancel sets it (a `CancellationToken` is the natural form). The rename does not wait for the walk: it returns at Cancel, gives the course back, and drops whatever the walk delivers later.
- **A dialog that goes away with its list.** When the list that opened the rename dialog leaves the window (the settings closing, say), the rename that is only planning is halted, the same as the dialog's Cancel halts it. Do not rely on the dialog's own closing event alone: on the Mac the dialog closed with its list and its own handler was never called.
- **A second close request during the wait.** The close-wait for a rename's swap (U4b2-7) can be asked again while it waits: a second close, or a sign-out. Once a close is going ahead (the flag U4b2-7 adds), a second request asks nothing and does not refuse: it lets the first close finish the app.
- No ledger row: no contract case changed.

## Must-fail lines

Seven rows, all RED, each restored byte for byte (`git diff` of `mac-app/QuartzTeachers` empty afterwards). Full log: `windows-app/notes/899-u4b2-8-mustfail.log`.

1. mf1, the walk in `Task.detached` again (the brief's row): `testRenameThenCancelOnADeadVolumeLeavesTheSharedThreadsFree` fails at line 1428, "round 13's plan never started, with 12 held on a Mac of 12 cores: the stuck reads hold the shared threads". It also fails at line 1425, where round 12's rename does not return after Cancel.
2. mf2, `stopIfThePlanIsHalted` ignores the thread being cancelled. The same test fails at line 1447, "a cancelled plan went on reading pages" (64 against 16). The part-seven test also fails at line 1368, "the cancelled plan went on reading pages" (4 against 1).
3. mf3, `cancelRename` closes the sheet without halting: `testTheRealSheetsCancelHaltsAHeldPlanAndClosesTheSheet` fails at line 1029, "Cancel did not halt the rename in its own turn", and at line 1033, "the sheet's Cancel did not reach the held plan".
4. mf4, Cancel halts inside a fresh `Task`: the same test fails at line 1029, "Cancel did not halt the rename in its own turn".
5. mf5, the list's `.onDisappear` is removed: `testTheRealSheetGoingAwayHaltsAHeldPlan` fails at line 1083, "the sheet going away did not halt the held plan".
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

## Left for the next piece

- Closing the window a rename sheet hangs from while the rename only plans (rather than the list leaving the window) was not driven here. `TableHost.close` keeps the hosting view alive (`isReleasedWhenClosed = false`), so it fires no `.onDisappear` at all and would not show what a real window close does. In the app, a Course Settings window closing tears its views down, and the list's `.onDisappear` should then fire. That is not proven. Driving it needs a window the test lets AppKit release.
- `testTheRenameSheetCallsItsRunForEveryWayOut` (the source-text test) is kept. The new real-chain tests back its Cancel and going-away checks, and it still pins Rename's `canStart` wiring and `using: onRename,`, which the real Rename press also exercises.
- Review 1 L3 of piece 7 (a re-plan after `changedSince` keeps its claim swapping) is unchanged and was not in this brief.

## For the director

No parked question.

- **An interface-visible change, small, and found by the new test**, not designed. A rename that is only planning is now also halted when the list that presents its sheet leaves the window. Before this piece, the sheet closed with the list and the plan went on (measured, `run-new7`). The list's `.onDisappear` now calls the same `haltARenameStillPlanning`. HIG: I re-read "Sheets" and "Progress indicators" today (developer.apple.com JSON). A sheet's Cancel "dismisses without saving", and "If people can interrupt a process without causing negative side effects, include a Cancel button". Halting a plan loses nothing, so a sheet taken away is treated as Cancel, as the comment on the sheet's `.onDisappear` already said ("However the sheet goes"). No new control, no wording, no key.
- **LOW-b, from Apple's documentation** (read today, developer.apple.com JSON of `NSApplication.TerminateReply.terminateLater`, `applicationShouldTerminate(_:)` and `reply(toApplicationShouldTerminate:)`). `terminateLater`: "Returning this value causes Cocoa to run the run loop in the NSModalPanelRunLoopMode until your app subsequently calls reply(toApplicationShouldTerminate:) with the value true or false. This return value is for delegates that need to provide document modal alerts (sheets) in order to decide whether to quit." That mode takes input (it exists so that sheets work), and none of the three pages says `terminate(_:)` is ignored meanwhile. I therefore treated a second request as possible and made it safe. `AppDelegate.answerWhileAQuitGoesAhead()`, asked first in `applicationShouldTerminate`, answers `.terminateLater` while `FolderRenameRun.quitIsGoingAhead` is set: no question, no halting, no new wait, never `.terminateCancel`. Whichever request AppKit is then waiting on, the first quit's `reply(true)` (or the set-aside update's) ends the process. I did not measure what AppKit actually does with a nested request. The test proves the answer and that the delegate asks it first, but not AppKit's behaviour. Calling the real `applicationShouldTerminate` from a unit test would, without the guard, run `letEverythingGo` in the test host, or put up the work-under-way alert, so the delegate's use of the guard is pinned by reading its first statements with comment lines left out.
- LOW-a: the two real-chain tests use the AX API (`AXUIElementCreateApplication` of this process), as `SaveEnablesTests` does. They skip, by `AccessibilityInspector.skipUnlessTheWindowCanBeRead`, when the screen is locked or the window is on a Space that is not showing. They did not skip in any run here.

## Self-check

1. Broke each fix and watched its test fail: seven rows, all RED (above), plus the two reds before the fix.
2. No timed waits: none in the product. The tests wait on events (a plan reaching its page, a rename returning, the unrelated task running, every plan ending) with bounds that FAIL: 30 s, copied from the part-seven tests, and 10 s for the unrelated task, which a free pool runs at once. `host.pump(0.3/0.6)` is the existing host's settle for layout, not a wait for the behaviour under test.
3. Failure-path sentences: none changed. A halted rename says nothing (as before), and a second quit request shows nothing.
4. `dev` merged before proving: `origin/dev` 24fcbc718 is already in the base and did not move. No merge commit was needed.
5. No number tuned by trial: rounds = cores + 4, chosen once; the bounds are copied from existing tests. No count was adjusted to pass.
6. House style and contracts: no `contracts/` change. Changed outside `mac-app/`: only documentation 09 and this notes folder.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added lines: empty. New types have MARK sections (`EveryPlanHold`, `ThreadCount`, `RenameSheetButtons`, `RenameSheetShown`, `RenameSheetRoot`).
8. Riding lows: part eight's L2 is fixed, with a test red first. LOW-a is backed by two real-chain tests, one red first and one by sabotage, and they found and fixed a real gap. LOW-b is answered from Apple's documentation and made safe, with a test proved red by sabotage.
9. The rename record is still kept (not touched). `undoJournalIsLive` is still off (not touched).
10. No new or changed contract row; no ledger row.
