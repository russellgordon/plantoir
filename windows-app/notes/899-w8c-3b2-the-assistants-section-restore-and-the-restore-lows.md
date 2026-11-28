# W8c-3b2: the assistant window's section restore holds the list; the restore lows (#899, Windows #949)

Brief: `vm-tools/briefs/2026-11-27-899-w8c-3b2-the-assistants-section-restore-and-the-restore-lows.md`. Base: 3b1's head 208ba06cf; `origin/dev` already in it.

## Built

- `CourseRestorer.RestoreSection` (the assistant window's route) has an internal overload taking `Func<UndoListForARestore>`; the public one passes `UndoListForARestore.OfThisProcess`. It now calls 3b1's `SwapSectionHoldingTheList` with no outside files and `keepingWhatWasReplaced: null`, and writes the per-section keys (`RestorePerSectionKeys`) in its `thenInsideTheLock`, then reaches `SwapPoint.PerSectionKeysPutBack`, as the Mac's `CourseRestorer.swift` 436 to 450 does. What it replaces is `courses/<CODE>/section<N>` alone. There is no second lock-taking site: `WithLock` is called only inside `UndoRestoreSetAside.SwapHoldingTheList`.
- `AssistSectionRestore.Restore` has the same internal overload. A busy list's `RestoreException` (`wording.leftAsItWas` with 3b1's reason) reaches the window through the existing `catch (CourseRestorer.RestoreException error) { throw new Problem(error.Message); }`. There is no new sentence.
- 3b1's review LOW 3: `theList()` is now called inside the `try` of `SwapHoldingTheList`. A list that cannot be made therefore runs the restore unlocked, as the "cannot be had" ruling says. No trail line is written, because a list that was never made gives no trail.

## Tests first (ce2b52316)

The red commit had the overloads only (the list ignored). Expected red on the product as it was:
- `TheAssistantsRestoreSetsAsideAStepInTheSectionAndRecoveryNeverWritesIt`: no set-aside (`Assert.Contains(DayOne, step.SetAsidePaths)`).
- `TheAssistantsRestoreRefusesABusyListBeforeAnythingMoves`: no refusal, so `Assert.Throws` fails.
- `TheAssistantsRestoreHoldsTheLockForEveryMove` and `TheAssistantsPerSectionKeysAreWrittenInsideTheLock`: the lock was not held.
- `AListThatCannotBeMadeLetsTheRestoreRun`: the throw came out of `theList()`.
- `ARestoreThatThrowsStillStartsEachStoppedPreviewOnce`: no `start 1`.

Green on the old product too, and caught by a must-fail row: `TheAssistantsFirstMoveThatFailsSetsNothingAside` (row 2) and `ARestOfTheStepThatWasMadeLeavesAnEarlierStepsRedoOffered` (row 3). `AListThatCannotBeWrittenLetsTheRestoreRunAndWritesTheTrailLine` (3b1's review LOW 1) covers behaviour that was already there. The clerk's `--red ce2b52316` is the run that proves which tests are red. I did not run the tests before the code, because there is no dotnet on this Mac and the piece's shape allows one VM run.

## Lows

1. 3a L1: `TheDeferredRowsAreKeyedAsTheTableIs` is renamed `TheRestoresRowIsKeyedAsTheTableIs`, with a summary saying what it checks. The comment in `TheTableIsTheContracts` now says that no row is deferred. `UndoFold`'s summary names `UndoRestoreSetAsideTests.TheFoldRowAddsThePathsToAStepInFlightAndMovesNothing` for the `in flight` rows.
2. 3a L2: `UndoRestoreSetAsideTests.ARestOfTheStepThatWasMadeLeavesAnEarlierStepsRedoOffered`, with must-fail row 3.
3. 3a L3: one bullet in documentation 12, "What #909 owes Windows", saying the whole-course set-aside stays owed.
4. 2b L2: `StartOfYearRestoreOffer.RestoreCourseAsync` now restarts the previews in a `finally` (`StartTheStoppedPreviewsAgain`). The test is in `StartOfYearTests.StoppedPartWay.cs`, with must-fail row 4.
5. 2b L3: a comment in `StartOfYearDialog`'s `PrimaryButtonClick` says why running Go inside the handler is safe.
6. 2b L4: the held-back `TextBlock` raises `LiveRegionChanged` from `FrameworkElementAutomationPeer.CreatePeerForElement(busy)` on `Loaded`, which comes after the content is set. The Microsoft line I followed is in the `AutomationProperties.LiveSettingProperty` reference: "The LiveSetting property indicates the "politeness" level that a client should use to notify the user of changes to the live region." The "Accessibility overview" page, as published today, has no "Live regions" section, and neither does "Expose basic accessibility information". The Apple HIG "Accessibility" page has no announcement line either; the nearest is "Describe your app's interface and content for VoiceOver." `StartOfYearRestoreOfferUiTests` was NOT run: UI classes are out of scope for `win-proof.sh`. It is the clerk's.
7. day27c-3 L1: documentation 12's #1055 "Nothing else." bullet now says that the one `checkCases` row holds only `linkSha`, and that the before-and-after shape is held by each platform's own test.
8. day27c-3 L2: documentation 12 gives the test its present name (`…_WhereTheMacRefusesBeforeAnythingChanges`, checked at `UndoMakeRoomStepTests.cs` 290). Every line naming `Reason899W8bLinkedClassPage` now says that the constant was removed by #1055: the four lines in 12 plus the one in 09 (about 23907), which the done-check grep also covers.
9. day27c-3 L3: documentation 09's Rename Folder bullet now quotes "A folder whose content cannot be read". The comment wraps "cannot be judged as a / pair" across two lines, so a search would not find the old quote.

## Must-fail rows

`vm-tools/guest/899-w8c-3b2-mustfail.json`, 4 rows. Each old string was checked to occur once.

## Self-check

- `git grep -n "WithLock"` in `CourseRestorer.cs` and `AssistSectionRestore.cs` finds nothing. The one call is in 3b1's function in `UndoRestoreSetAside.cs`, as 3b1's review LOW 4 explains.
- The documentation grep is empty apart from lines saying that the constant was removed.
- One function per rule: the comparison "inside a replaced place" is still `UndoOp.PartInside`, inside `SetAsideSteps`.
- No contract change, no new wording, no timed wait. No run left going, no lock held.
- 3b1's must-fail row 1 matches text that this piece changed (`theList()` moved inside the `try`). That row is for 3b1's branch, not this one.
