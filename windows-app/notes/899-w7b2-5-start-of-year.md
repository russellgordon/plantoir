# #899 W7b2-5: Get Ready for the Start of the Year is ONE step (Windows #949)

Branch `issue/899-w7b2-5-start-of-year`, from `origin/dev` a03fecefd (W7b2-4 merged; the brief's base branch is deleted, the director's correction of 2026-11-25). No `contracts/` change, no `mac-app/` change.

## Must-fail lines

Recorded in `vm-tools/guest/899-w7b2-5-mustfail.json`, run by `899-w7b2-5-go.ps1` (a copy of `899-w7b-pc-run.ps1`'s caller). Run b, head 65b87b3d5: see "Runs" for each line.

1. written file by file (each page by `Save`): `GoIsOneStepInTheMacsOrderWithTheFrontPageAsARecompute`.
2. written file by file: the fixture row `TheWindowsActionLeavesTheRecordedStep`.
3. the front page written as a file of the step: `GoIsOneStep…`.
4. the recompute missing: `GoIsOneStep…`.
5. a before read at make time (the act's record of each before read after the step is made): `UndoGettingReadyAfterASuccessAnswersAsBefore`.
6. the put-back restored (Undo Getting Ready writing the befores back itself): `UndoWriterScanTests`.
7. a refusal said as the old could-not-finish sentence: `APageThatCannotBeWrittenChangesNothing`.
8. a part-way stop said as Nothing was changed: `APartWayStopSaysThePartWaySentence`.
9. the app's Go made by the workspace's surface: `TheAppsGoIsMadeByTheSheet`.
10. riding low, a wrong reason after "Nothing was saved": `UndoHowITeachStepTests.AStartedPageRefusedForAnotherReasonSaysNothingWasSaved`.

Measured and dropped from the file: removing the step's no-change guard (`UndoActionStep.Make`'s `if (!ChangesAnything)`) leaves `APlanThatChangesNothingMakesNoStep` GREEN (run a, row 10 NOT-RED), because the door refuses a draft with no content op too (`UndoDoor.Perform`, `hasAContentOp`, ChangedNothing). Two guards each hold it alone; a one-file sabotage cannot break both. The test stays as the brief asks (a plan that reaches the step with every page declined makes no step and changes nothing); it is the same with the old code, which made no step at all.

## Runs

- Run a (`899-w7b2-5-a`, fb1d610f7, the PC): both builds 0 errors. 260 of 269 passed; the 9 failures were all one cause, the step's file order (Windows' plan order, classes first, against the mac's sorted paths): the fixture row, the six traces action-091 to 096, and two of the new tests. These were the tests failing first. Fixed in 65b87b3d5.
- Run b (`899-w7b2-5-b`, 65b87b3d5): both builds 0 errors; the eleven classes 269 of 269 passed (UndoStartOfYearStepTests, StartOfYearTests, StartOfYearSheetTests, UndoActionStepsOnWindowsTests, UndoActionTraceContractTests, NamedGapLedgerTests, UndoWriterScanTests, ClubNounTests, DeclinedPagesAreNamedTests, UndoFilesContractTests, UndoHowITeachStepTests). Must-fail 10 RED of 10, each a single failing test (line 2: 1 of 25 rows, getReadyForTheStartOfTheYear; line 6: 1 of 5); RESTORED 269 of 269. HEAD-AFTER the same, tree clean, lock released (the run script removes it last).

## Left for the next piece

Nothing of this action. The rest of W7b2 is as the ledger's `Reason899W7b2` names it.

## For the director

- Tests or sentences that pinned the old put-back: none pinned it. `StartOfYearTests.UndoPutsBackWhatWasWrittenAndLeavesWhatChangedSince` and `UndoFilesContractTests` call `UndoStartOfYear` and pass unchanged (its verdict is `UndoHistory.Undo`'s, the same `UndoVerdict.Of`). One measured difference only when a put-back WRITE fails during Undo Getting Ready: the left list now holds pages in the plan's order, where it held the changed-since pages first and the failed writes after; the count and the sentence are the same.
- The op kinds are the door's and match the mac's (`editLine`, `editLine`, `recompute`): the fixture row checks them.
- Note on the brief: the write at the old line 365 was Undo Getting Ready's put-back, not a put-back when Go stops part way (Go had none; it returned what it had written). Removing it meant routing the sheet's undo through `UndoHistory`, as the mac does; the sheet's sentences are unchanged.

## Self-check

1. Broke each fix and watched its test fail: the must-fail lines above (run b). The one NOT-RED (the no-change guard) is explained and dropped.
2. No timed waits: none added; the PC waits were until-loops on the run's log.
3. Every failure sentence is true: a refusal changes nothing and says "Nothing was changed: <reason>" (test checks the whole sentence and every page and the front page); a part-way names the kept file; neither offers Undo Getting Ready, and neither says "saved" or "couldn't be read".
4. `dev` merged in before proving: the branch starts at `origin/dev` a03fecefd, and `dev` had not moved at hand-back (fetched), so no merge commit was needed.
5. No number tuned by trial.
6. House style and contracts: the step read from the contract by name; nothing changed outside `windows-app/`.
7. The fixture row is green, the ledger row no longer names it, and `Reason899W7b2` says W7b2-5 converted it.
8. The writer-scan count is true: `AssistWorkspace.StartOfYear.cs` holds no writing call and its entry is gone.
9. The riding low (W7b2-4 review 3) is fixed: the test checks the whole sentence, with must-fail line 10.
10. The step keeps the mac's file order (sorted places), the action's reading order is the plan's, and every before is read before the step is made (the planner's text through the step, and the step's own before at each `Write`, both before `Make`).
