# #899 W8c-2b (Windows #949): Get Ready stopped part way offers Restore Course in the sheet

Branch `issue/899-w8c-2b-get-ready-offers-restore-course`, from W8c-2a's 6e60765ed. `origin/dev` merged in at 635953b4c (before proving). No `contracts/` change, no `mac-app/` change.

## For PROGRESS

- `StartOfYearDialog.OfferAsync` runs Go inside the sheet's own primary-button press. A part-way outcome (`StartOfYearOutcome.StoppedPartWay`) cancels the close (`args.Cancel`) and turns the same dialog into the offer: `stoppedPartWay`, then `restoreOffer`; Restore Course is the primary button and the default, Leave As It Is the close button. No second dialog. Every other outcome closes the sheet and is said by `SidebarPane.SayAfterStartOfYear` as before. The part-way outcome never shows `outcome.Message` (2a review LOW 3: no per-file kept sentence).
- `Plantoir.Core/Assist/StartOfYearRestoreOffer.cs`: the answer logic. `RestoreCourseIsPressed()` decides in the press's own turn (deploy running: `HeldBackByADeploy`, the offer stays open with both buttons and shows the restore's busy sentence; otherwise `Closes`; a second press `AlreadyAnswered`). `LeaveAsItIs()` answers and changes nothing. `RestoreCourseAsync(answers)` runs only when Restore Course was the answer, once: stops every running preview of the course (awaited), runs the whole-course restore with the backup Go made, then starts each stopped preview again once if the restored course still has that section and it is not already running.
- The one whole-course restore: `CourseRestorer.RestoreWholeCourse(item, current, coursesDirectory)` (archive first, `RestoreBackup`, the trail line) is now the core of `SidebarPane.RestoreWholeCourse`, and Restore Course calls `SidebarPane.RestoreWholeCourse` itself through `SidebarPane.RestoreCourseAnswers` (reload, select the course, `BackupProblemTitle.Restoring` on failure). The busy sentence moved to `CourseRestorer.BusyTitle`/`BusyMessage`; `AskWhichRestore` uses them, same words.
- Previews: stopped through `MainWindow.StopPreviewForAsync` and started again through `MainWindow.ShowPreviewFor`, the pair Course Settings' Preview Again uses.
- Test seam: `--start-of-year-stops-part-way-for-tests` (App, `#if DEBUG` only, the update-feed seam's pattern) sets `AssistWorkspace.StopsPartWayForUiTests` (also `#if DEBUG`): the contract's first case's door. Compiled out of Release.

## For documentation 12

- Get Ready, failure paths: the part-way offer is the Go dialog itself (WinUI allows one ContentDialog per window). Button order differs from the Mac by platform rule: Restore Course left (primary), Leave As It Is right (close). The contract's `howToRunAStoppedPartWayCase` says "leading"/"trailing" in the Mac's terms; on Windows the primary is leftmost by Microsoft's guidance.
- Starting a preview again on Windows selects that section in its window (`ShowPreviewFor`), so after a Restore Course that restarted a preview the window shows the section, not the course the restore selected. On the Mac the preview lives in its own section window, so selection is untouched.
- A deploy holding Restore Course back writes no trail line on Windows (the Mac writes the restore's did-not-go-ahead line); Windows' whole-course restore has no refusal trail line to copy (its busy refusal in `AskWhichRestore` writes none either).
- `restoreOffer` checked on Windows: "moves to Archived, at the bottom of the sidebar" is true (`ArchiveCourseWithoutRemoving`, the sidebar's Archived group, the same words as Remove Course's message); "Put These into Draft" is `StartOfYearWording.GoButton`. Every clause true.

## HIG lines followed (read 2026-11-27)

- Apple, Sheets: "Display only one sheet at a time from the main interface." "If something people do within a sheet results in another sheet appearing, close the first sheet before displaying the new one."
- Apple, Alerts: "Always place the default button on the trailing side of a row"; "you don't want to make a Cancel button the default button"; "Aim for a one- or two-word title that describes the result of selecting the button"; Escape cancels.
- Apple, Buttons ▸ Role: "Assign the primary role to the button people are most likely to choose. When a primary button responds to the Return key, it makes it easy for people to quickly confirm their choice." "Don't assign the primary role to a button that performs a destructive action": Restore Course is not destructive (Archived keeps the course).
- Microsoft, Dialog controls: "There can only be one ContentDialog open per window at a time." "The 'do it' action button(s) should appear as the leftmost buttons. The safe, nondestructive action should appear as the rightmost button." CloseButton: "The user presses the ESC button on the keyboard." DefaultButton: "The button will respond to the ENTER key automatically … If the user has placed Keyboard Focus on a control that handles ENTER, the Default Button will not respond", so the offer puts the focus on Restore Course itself.
- No invisible controls: Enter and Escape are the visible buttons' own (DefaultButton, CloseButton). The Go page keeps Q-B's no default.

## Must-fail lines

RED 5 of 5 (finishing round, VM A, from 516b06ecc), rows in `vm-tools/guest/899-w8c-2b-mustfail.json`, lines in `windows-app/notes/899-w8c-2b-mustfail.log`: (1) a second dialog over Go: `StartOfYearRestoreOfferUiTests` 2 of 2 red (WinUI refuses the second ContentDialog, so the app falls over: `Win32Exception 0x80000019`); (2) a question first: `EnterIsRestoreCourseAndRestoresWithNoSecondQuestion` ("Enter did not restore the course"); (3) restore during a deploy: `ADeployHoldsRestoreCourseBackAndTheOfferStillWorksAfter`; (4) a preview never started again: `TheOfferIsAnsweredOnceAndAPreviewIsStartedAgainOnce` and two more; (5) Leave As It Is writing: `StoppedPartWayCasesAsTheContractSays` (`Assert.Empty`, a restore recorded). Earlier, one real fault was caught red by the new tests during the work: `RestoreCourseAsync` gated on "answered" rather than "Restore Course chosen", so the `leaveAsItIs` case restored (`StoppedPartWayCasesAsTheContractSays`, `Assert.Empty(recorder.Restored)`), fixed in ba8570ae5.

## Runs (VM A, `Windows 11`, under `vm-tools/runs/VM.lock`, parked and released after)

- a75e5839f: the nine unit classes, 283 of 285 (the leave-gate fault above; a test of mine that started section 2 in a one-section course).
- ba8570ae5: `StartOfYearTests`, `StartOfYearSheetTests`, `UndoStartOfYearStepTests`, `QuestionDialogScanTests`, `DialogTitleScanTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`: 285 of 285. Both builds (the unit build and the UI run's x64 Debug app build) green.
- ba8570ae5: `StartOfYearRestoreOfferUiTests` 2 of 2 (one dialog, both sentences in order, two buttons in Microsoft's order, Escape leaves it as it is, Enter restores with no second question), 2.3 minutes.
- Finishing round, 516b06ecc after `git fetch` and `git merge origin/dev` (already up to date): the nine unit classes 285 of 285 (`vm-tools/runs/w8c-2b-unit-4.log`); `StartOfYearRestoreOfferUiTests` 2 of 2 with the x64 Debug app build (`vm-tools/runs/w8c-2b-ui-2.log`). The UI build needs `refetch-runtime.ps1` after every park (#965 runtime).

## Left for the next piece

- The tests were committed before the product (b639477f5 before 2fdfa2d59) but were not run red on the product as it was: they reference the new types, so on the product before they do not compile.
- (Done in the finishing round: the must-fail run, and the second `dev` merge, which was already up to date at 16:20.)

## For the director

- Ledger: no row (W8c-2a cleared them). `NamedGapLedgerTests` green.
- 2a's three LOWs: LOW 3 fixed here (the dialog never shows `outcome.Message` for a part-way stop). LOW 2 holds now that 2b shows the offer. LOW 1 (PROGRESS line 2442) is the director's fold-in; with 2b the line should say the outcome, the words and the offer are built (W8c-2a, 2b).
- 2a's two parked questions are left parked.

## Self-check

1. Broke each change and watched a test fail: yes. The leave gate was red before its fix, and the brief's five must-fail rows are RED 5 of 5 (`899-w8c-2b-mustfail.log`); each restored byte for byte (`git diff` empty).
2. No timed waits where an event exists: none added; the preview stop is awaited, the UI test waits on conditions.
3. Every sentence on the failure paths true: the offer's two sentences from the contract by key, the busy sentence the restore's own, a restore failure the restore's own error.
4. `dev` merged in: at 635953b4c before proving; fetched and merged again in the finishing round (already up to date), and the classes re-run after it.
5. No number tuned by trial: none.
6. Contract cases run from the JSON: `stoppedPartWayCases`, with the two `then` halves now run to their end.
7. Fixture row / ledger: no row in this piece.
8. Writer-scan count: `UndoWriterScanTests` green; no new write site (the restore's writes moved from SidebarPane into `CourseRestorer.RestoreWholeCourse` beside `RestoreBackup`).
9. Riding lows: 2a LOW 3 fixed with the UI test and `TheOfferSaysTheTwoSentencesInOrderAndNamesNoHiddenFile`.
11 to 14: no held rows; no key added; one function per rule (one whole-course restore, `CourseRestorer.RestoreWholeCourse`); no run left going, VM A suspended, lock released (it was mine); the same in the finishing round (lock `w8c-2b-finish`, taken and released by it).
