# 899 U4b2-7: a rename that is only planning holds nothing (#899)

Branch `issue/899-u4b2-7-planning-rename-holds-nothing`, from `origin/dev` 24fcbc718. `origin/dev` was fetched again before proving and before hand-back and had not moved (still 24fcbc718), so there was nothing to merge and no merge commit was made.

## For PROGRESS

- Mac, U4b2-7: Command-Q while a Rename folder is only planning no longer waits for it. The quit halts the rename the same way the sheet's Cancel does and gives the course back; it waits only for a rename whose check and swap have begun. Nothing is asked either way. The sheet's rename task and its halting rule moved into a small `@Observable` model, `FolderRenameRun`, so the chain from the sheet's Cancel to the plan is now tested (part eight's L1 and L3). After review 1: once a quit is going ahead, no rename may start and none may begin its swap (one latch, `FolderRenameRun.quitIsGoingAhead`), and every rename sheet's Rename is disabled while it waits.

## For documentation 12

What Windows must do (W8). Today `windows-app/` has no quit wait for a folder rename at all (a grep of `windows-app` for a close or exit path naming the rename finds none), so this is the rule to build when it gets one:

- A Rename folder has two phases. **Planning** reads the course and writes nothing. **Swap** begins at the moment the rename is marked as begun (the same moment Cancel greys), and from then on it moves folders and rewrites pages and settings as one step.
- When the app is closing and the close is going ahead (after any question about work under way has been answered "quit"), every rename that is still planning is halted the same way its dialog's Cancel halts it: its cancellation is signalled, its claim on the course ends, and nothing it planned is ever written. The close does not wait for it.
- The close waits only for a rename whose swap has begun, until it ends. This wait asks nothing and shows nothing new; the rename's own dialog keeps its spinner.
- A close that is called off (the teacher chooses to keep working) halts nothing: a planning rename carries on.
- The safety that makes this race-free: the check "was this rename cancelled?" and the marking of the swap as begun happen together on the UI thread, with nothing awaited between them, so a halt lands either before the swap (the rename then writes nothing) or after it (the halt is refused, the close waits).
- Once the close is going ahead (review 1, M1): from that moment no rename may start (the Rename button of every rename dialog is disabled, in the standard disabled state, with no new sentence), and a rename that reaches the point where its swap would begin is refused there, writing nothing. Use one flag, set on the UI thread in the same step as the close decides, and test it at that one point, together with the rename's own cancellation check. Without it, the windows stay live while the close waits, and a rename pressed then, or a plan the halt did not reach, could begin its swap after the close stopped counting it, and the process would end inside the swap. Nothing clears the flag: it is set only after the question is answered, and a close that has gone ahead is never called off.
- No ledger row: no contract case changed.

## Must-fail lines

Eleven rows in all, all RED. First round, rows 1 to 5, each restored byte for byte (`git status` of `mac-app/QuartzTeachers` empty afterwards). Full log: `windows-app/notes/899-u4b2-7-mustfail.log`.

1. Quit counts every claim again (`anyFolderRenameSwapIsUnderWay` reads `!store.activeFolderRenames.isEmpty`): `testAQuitWhileARenameOnlyPlansHaltsItAndDoesNotWait` fails, line 826, "the quit waits for a rename that only plans".
2. Quit does not halt the run (the `FolderRenameRun.haltEveryRunStillPlanning()` line removed): same test fails, line 833, "the quit did not halt the rename while it planned" (on the 30 s failure bound, hold opened first, no hang).
3. Cancel does not cancel (`renameTask?.cancel()` removed from `haltIfStillPlanning`): `testTheSheetsCancelReachesAHeldPlan` fails, line 908, "the sheet's Cancel did not reach the held plan".
4. `onRename` awaited in a fresh `Task` in `FolderRenameRun.start`: same test, line 908.
5. `renameFromTheSheet` wraps `renameFolder` in a fresh `Task`: same test, line 908.

Red before the fix: the two new tests could not compile against the old code (the model and `renameFromTheSheet` did not exist), so the red-before-fix proof is rows 1 to 5, which put each piece of the old behaviour back in place on top of the committed fix (row 1 is the old quit rule exactly; rows 3 to 5 are the three ways the brief names the wiring could break).

Review 1 rows (6 to 11), all RED, restored byte for byte:

6. `canStart` ignores a quit going ahead: `testARenamePressedWhileAQuitWaitsDoesNotStart` fails, line 881 "Rename stays enabled while a quit is going ahead" and line 899 "a rename started while a quit was going ahead".
7. `FolderRenameRun.swapBegins` ignores a quit going ahead: `testAPlanThatFinishesWhileAQuitWaitsNeverBeginsItsSwap` fails, line 942 "a swap began while a quit was going ahead", with the folders renamed and one step made.
8. The quit decision does not set the latch: the same test fails at line 942.
9. `cancelRename` closes the sheet without halting through the run: `testTheRenameSheetCallsItsRunForEveryWayOut` fails, line 968 "Cancel does not halt through the run".
10. `.onDisappear` no longer halts: same test, line 972.
11. Rename not disabled by `canStart`: same test, line 980.

Red before the fix (review 1): the two behaviour tests were run with the latch and its tests in place but with neither guard (`run-r1red`): both failed with 10 failures, the folders renamed in each. The source-text test passed there, as it should (the view's calls were already right); rows 9 to 11 are its red proof.

## Runs

All through `xlock.sh` with the 900 s kill, derived data `.dd/` in the worktree.

- `run-build1`: build-for-testing, succeeded.
- `run-own1`: UndoRenameFolderStepTests, QuitConfirmationTests, CourseActivityTests, SaveEnablesTests and the classes that read `AppDelegate.swift` or `StringListEditorView.swift` as source (SectionDetailStructureTests, AppUpdatesStartTests, NameTableTests, SheetTitleScanTests, AccessibilityNamesTests, PreviewBuildRecordTests, ToolchainFingerprintTests, StringListEditorTests): 139 tests, 1 failure, in my new test (Save had nothing to enable: the test had made no edit). Fixed in the test (it now edits the course name first, as the part-seven test does).
- `run-own2`: UndoRenameFolderStepTests, 40 tests, 0 failures.
- `run-scan1`: every class that walks the whole source tree (AppRulesContractTests, ActivityTrailWiringTests, AssistSettingsFreshnessTests, CourseNameCharactersTests, ObsidianFigureAddOnsTests, PlanningTabTests, PreviewWhileDeployingTests, QuestionKeysTests, PrintablePagesTests, ReferenceShelfTests, SectionVerbsTests, SectionProblemsTests, SharedRulesContractTests, UserFacingLabelWordsTests, WorkLeaseDecliningTests, WizardStructureTests, WorkingFolderReachTests), because the piece adds a file: 385 tests, 0 failures.
- `run-mf1` to `run-mf5`: the must-fail rows above.
- `run-final` (restored tree): UndoRenameFolderStepTests, QuitConfirmationTests, CourseActivityTests, SaveEnablesTests, StringListEditorTests, AccessibilityNamesTests: 88 tests, 0 failures.

- `run-r1red`: the three review-1 tests before the guards, 10 failures in the two behaviour tests (above).
- `run-r1own`: the brief's classes and the source readers, 142 tests, 0 failures.
- `run-mf6` to `run-mf11`: review-1 must-fail rows.
- `run-r1final` (restored tree, review-1 head): the brief's classes, StringListEditorTests, AccessibilityNamesTests and the 17 whole-source scanners, 476 tests, 0 failures.

## Left for the next piece

- For piece 9 (director's riding low, piece 6 review L1): the sheet spinner's VoiceOver label "Renaming" (`StringListEditorView.swift`, the `ProgressView` in `renameSheet`, about line 514) is a sentence in Swift alone; it belongs in `contracts/`. Not changed here (no `contracts/` change in this piece).
- Review 1 L3, unchanged from `dev`, noted only: a rename planned again after a `changedSince` refusal keeps its claim marked swapping from the first pass, so during that re-plan a quit waits for it and Cancel stays grey, although the refusal put everything back and the re-plan has written nothing; a re-plan stuck on a dead volume would hold the quit. Rare (a page or setting must change between plan and make). Once a quit is going ahead, the re-plan's next pass to the swap is refused (`FolderRenameRun.swapBegins`), so it ends with nothing written. Clearing `isSwapping` before the `continue` would make it a planning claim again; not done here (outside this brief's invariant as worded, and it changes when Cancel greys).
- Nothing else owed from this brief.

## For U7

- With the journal switch on, nothing here changes: a planning rename has no step and no record, so a quit halting it leaves nothing for U7 to offer or recover.

## For the director

No parked question. Interface: I read Apple's HIG today (developer.apple.com JSON of each page): "The menu bar" (the app menu's Quit item: "Quits your app"; nothing about waiting), "Feedback" ("Warn people when they initiate a task that can cause data loss that's unexpected and irreversible", and do not warn where nothing is lost), "Progress indicators" ("When it's feasible, let people halt processing. If people can interrupt a process without causing negative side effects, include a Cancel button") and "Sheets" (Cancel dismisses without saving). The brief and the HIG agree: halting a planning rename loses nothing, so the quit asks nothing and halts it; a swap that has begun cannot be halted without a negative side effect, so the quit waits for it, as before. Nothing visible changed: no new control, no question, no key.

Review 1, interface (L1): re-read "Sheets" today; Apple has no HIG page named "Quitting" (the data URL returns 404), and the app menu's Quit is in "The menu bar", read earlier. A sheet whose rename a waiting quit halted stays open with its Rename disabled in the standard state, driven by the same latch; Cancel stays enabled and closes it as always. No new sentence: the disabled state needs none, and the process ends when the quit's wait does. "Nothing visible changed" in the first round was not quite true for this case (the spinner stops when the quit halts the rename); it is now: spinner stops, Rename greys.

Design notes for the reviewer:

- One rule, one place: `FolderRenameRun.haltIfStillPlanning` is what the sheet's Cancel (`cancelRename`), the sheet going away (`.onDisappear` through `haltARenameStillPlanning`) and a quit (`haltEveryRunStillPlanning`) all call; `canBeHalted` drives Cancel's greying. The view keeps only calls.
- The quit's decision is one function, `AppDelegate.quitWaitsAfterHaltingWhatOnlyPlans`, which `applicationShouldTerminate` and the test both run. It is called only after the work-under-way question, so a quit called off halts nothing.
- `CourseActivity.anyFolderRenameIsUnderWay` became `anyFolderRenameSwapIsUnderWay`, and `waitForAllFolderRenames` became `waitForEveryFolderRenameSwap`; the waiters are resumed when no swapping claim is left. A claim that is still planning when the quit decides not to wait cannot reach its swap afterwards: its task is cancelled, and `renameFolder` checks `Task.isCancelled` and marks the swap begun in the same main-actor turn.
- The existing swap-waits test now starts its rename from a `FolderRenameRun` too, so it also proves the quit's halting leaves a swap that has begun alone (`run.isRenaming` still true after the decision).

## Self-check

1. Broke each fix and watched its test fail: five rows, all RED (above).
2. No timed waits: none added. Tests wait on events (`reached`, `returned`, the quit's wait) with 30 s bounds that FAIL, opening the hold first; the `Task.yield` loops are bounded by turns, not time.
3. Failure-path sentences: none changed. A halted rename says nothing to its sheet (the sheet is gone, or the app is quitting), as part seven's Cancel already did; the trail gets no line, as before for a halted plan.
4. `dev` merged before proving: `origin/dev` 24fcbc718 is the base and did not move; no merge commit needed.
5. No number tuned by trial: the 30 s bounds and 10,000-turn bounds are copied from the part-seven test; none was adjusted to pass.
6. House style and contracts: no `contracts/` change (`grep` of `contracts/` for a quit case naming a rename finds none; `quitConfirmation` asks nothing about a rename, before or after). Nothing outside `mac-app/`, documentation 09 and this notes folder changed.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added lines: empty. `FolderRenameRun` has MARK sections.
8. Riding lows: part eight's L1 (the sheet-chain test) and L3 (the quit) are both fixed, each with a test proved red by sabotage.
9. The rename record is still kept (not touched); `undoJournalIsLive` is still off (not touched).
10. No new or changed contract row; no ledger row.
