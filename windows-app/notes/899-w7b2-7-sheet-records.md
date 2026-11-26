# #899 W7b2-7: a sheet's answer record is ONE step of one file (Windows #949)

Branch `issue/899-w7b2-7-sheet-records`, from `origin/dev` da7474047 (W7b2-6 and W7b2-9 merged; the director's base for the night of 2026-11-25 to 26, in place of the brief's deleted W7b2-6 branch). Merge of `origin/dev` before proving: da7474047, already contained, "Already up to date" (no merge commit). Before hand-back: see "Runs". No `contracts/` change, no `mac-app/` change. (Merged on 2026-11-26 in `night25/integration-5`, c50bc8112, with W7b2-8, -1 and -2. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12. What follows says the ledger and the writer scan as this branch saw them: on the merged tree the `Reason899W7b2` row and reason, and `Reason899W7b2MakeRoomLinkedPage`, are gone, and only `Reason899NoDuplicateAsNextClass` is left of W7b2, for W7b2-3. W7b2-3 merged later the same day, in `night25/integration-6`: that reason and its row are gone too, and no W7b2 action is held.)

## Must-fail lines

`vm-tools/guest/899-w7b2-7-mustfail.json`, run by `899-w7b2-7-go.ps1` (calling `899-w7b2-7-pc-run.ps1`, a copy of `899-w7b2-6-pc-run.ps1`). Each row applied alone, its test run, then restored with `git checkout`.

1. Not Today's record told to today's undo: `UndoSheetRecordStepTests.NotTodayIsNeverToldToTodaysUndo` RED.
2. the kept record told to today's undo: `KeptAtDeployIsNeverToldToTodaysUndo` RED.
3. Not Today's record written outside the step (the old `File.WriteAllText`): `NotTodayIsOneStepOfItsRecordMadeByTheSheet` RED.
4. the answer at Deploy written by the plain `Keep` inside `KeepAtDeploy`: `KeptAtDeployIsOneStepOfItsRecordMadeByTheSheet` RED.
5. the Deploy question back to `LaterClassesKept.Keep(…)`, as before: `TheDeployQuestionKeepsItsAnswerThroughTheStep` RED.
6. `Keep` inside Publish Class for a Date's step making its own second step: `UndoWholeUnitAndByDateStepTests.PublishClassForADateKeepsTheClassItPublishesInTheSameStep` RED.
7. a Not Today that cannot be written throwing at the sheet: `ANotTodayThatCannotBeWrittenCostsOnlyTheRecord` RED.
8. a kept record that cannot be written throwing at the deploy: `AKeptRecordThatCannotBeWrittenCostsOnlyTheRecord` RED.
9. the same Not Today again changing its record: `TheSameNotTodayAgainMakesNoStep` RED.
10. Not Today's measured members including `version`: `UndoActionStepsOnWindowsTests.TheWindowsActionLeavesTheRecordedStep` RED (1 of 25).
11. the kept record's measured members including `kept`: the same, RED (1 of 25).
12. riding LOW 1, `dialog.DefaultButton = ContentDialogButton.Primary;` added to `ShowAlertAsync`: `TodaysClassContractTests.TheSectionWindowOnlyRendersTheKeptAlertsDescription` RED.
13. riding LOW 1, `_ => null` in `ShowAlertAsync` answered as Open Folder: the same, RED.
14. riding LOW 2, `keptGone` saying "File Explorer": `NoKeptAlertSentenceSaysATechnicalWord` RED (run r2; in r1 NOT-FOUND, the JSON's curly quotes read as ANSI by Windows PowerShell; the file is now written with `\u` escapes).

14 RED of 14; RESTORED 269 of 269 after each pass.

## Runs

All on the PC under `C:\vm-setup\wt-compare.lock` (the run script takes it and removes it last; checked free after r2).

- r1 (`899-w7b2-7-r1`, 36b31a031): both builds 0 errors (app x64 Debug 37 warnings, none new). The brief's nine classes (UndoSheetRecordStepTests, TodaysClassContractTests, ClassesDatedLaterAtDeployTests, FutureDatedClassesContractTests, UndoWholeUnitAndByDateStepTests, UndoActionStepsOnWindowsTests, UndoActionTraceContractTests, NamedGapLedgerTests, UndoWriterScanTests): 269 of 269 on first run. Must-fail 13 RED, row 14 NOT-FOUND. HEAD-AFTER the same, tree clean.
- r2 (`899-w7b2-7-r2`, 36b31a031, must-fail row 14 alone): RED; RESTORED 269 of 269.
- No UI class, no harness, no whole suite.
- `origin/dev` merged again before hand-back: still da7474047, already contained.

On "tests first": the new tests call the new `RecordNotToday(…, step)`, `KeepAtDeploy` and `PlanInto`, so they cannot compile against the old code. The old behaviour was proven red by sabotage instead: rows 3, 4 and 5 put back exactly the old plain writes.

## Left for the next piece

- The links checklist's Publish (W7b2-8): `KeepTheClassesItPublished` with no step still calls the plain `LaterClassesKept.Keep`; W7b2-8 plans it into that sheet's own step with `LaterClassesKept.PlanInto`, and then the writer-scan entry for `LaterClassesKept.cs` goes (its reason says so). (Done by W7b2-8: `Keep` and the entry are gone.)

## For the director

1. **Sweep LOW 1, `keptGone` beside Open Folder (note only; it needs a contract change).** The mac's `wording.keptGone` is "“{kept}” is no longer there, so there is nothing to show.", said after Show in Finder, where "show" matches the button. Windows says the same sentence after Open Folder. `TheSentencesAreTheContracts` pins Windows to the contract's `wording`, which is the mac's to say in full, so a Windows sentence needs a third `keptOnWindows` key. Options: (a, recommended) add `keptOnWindows.keptGone`, "“{kept}” is no longer there, so the folder was not opened.", with the next contract change (it brings the Mac gate); (b) leave the mac's sentence, which is true and clear. Not changed here.
2. **Sweep LOW 2, "To see it" after several kept sentences:** not reachable (Show on Front Page's step holds one file). Nothing done.
3. **Sweep LOW 3, `keptOnWindows.why` "awaiting Russell's confirmation":** left, he has not confirmed. Ride the one edit (contract, documentation 12, W7b2-9's notes) with his answer.
4. **W7b2-9 review 2 LOW 2, the contract half:** `todaysClassOnTheFrontPage.plainWordsCheck` says "A name listed in `plainWordsExceptions` is taken out of a sentence before it is checked." without naming the scope; the test now honours `in`. The sentence would read "… is taken out of the sentence its `in` names …". A `contracts/` change, so not made; ride it with item 1 or 3.
5. **For the mac (information):** the mac's recorded `keepClassesDatedLater` names its place as "section1/All Classes/Unit 1, Day 3.md", with `.md`, where `file-formats.json` → `laterClassesKept.keys.kept` says "without .md". The mac's `UndoActionStepsTests` builds the `KeptRecord` by hand, so the product may be right and only the fixture differs. Worth one look on the mac side; Windows names the difference in `WindowsOwnJson`.
6. Start-of-year part-way sentence: parked for a ruling, untouched.

## Self-check

1. Broke each fix and watched its test fail: 14 must-fail rows, each RED (above).
2. No timed waits: none added, in product or test.
3. Failure paths: a refused record returns false and says nothing new (the trail's "left the front page as it was — Not Today" line is still true: the page was left as it was); the deploy goes on, as before. A part-way record returns true (it is written) and has no sentence, as the mac's `try?`; the door's trail line names the kept file. No "couldn't be read", no plain "saved", no `CouldNotSave`.
4. `dev` merged before proving: da7474047 (already contained, no merge commit), and again before hand-back (unchanged).
5. No number tuned by trial.
6. House style and contracts: the recorded steps run from `undo-action-steps.json` by name; the differences are measured in `WindowsOwnJson`, never retyped as the mac's bytes. Nothing outside `windows-app/` changed (and `vm-tools/guest`).
7. Both fixture rows green, out of the ledger; `Reason899W7b2` says W7b2-7 converted them and names only what is left (Make Room, Duplicate Class, the links checklist).
8. Writer scan: `TodaysClassOnTheFrontPage.cs`'s entry is gone (nothing waits); `LaterClassesKept.cs` stays 3, its reason now says they are `Keep`'s plain write for the links checklist, W7b2-8.
9. Riding lows: W7b2-9 review 2 L1 and L2 fixed, each with a must-fail row; sweep LOWs 1 to 3 and the start-of-year sentence noted under "For the director" (contract changes or not reachable).
10. One file each, so the order is trivially the action's; each before is read at plan time by `UndoActionStep.Write` (Not Today) and by `PlanInto`, which reads what is kept through the step (`ReadTextIfAny`) before planning.
