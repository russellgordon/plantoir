# #899 W7b2-7: a sheet's answer record is ONE step of one file (Windows #949)

Branch `issue/899-w7b2-7-sheet-records`, from `origin/dev` da7474047 (W7b2-6 and W7b2-9 merged; the director's base for the night of 2026-11-25 to 26, in place of the brief's deleted W7b2-6 branch). Merge of `origin/dev` before proving: da7474047, already contained, "Already up to date" (no merge commit). Before hand-back: see "Runs". No `contracts/` change, no `mac-app/` change.

## For PROGRESS

- W7b2-7 (#899, Windows #949): Not Today's record (`notTodayOnTheFrontPage`) and the classes dated later kept at Deploy (`keepClassesDatedLater`) are each ONE `UndoActionStep` of that one file, made by `sheet`, never told to today's undo, Windows' own bytes unchanged. Both fixture rows are converted and out of the ledger; their six traces each run the real Windows action. A record that cannot be written costs only the record (false, no throw); the same answer again makes no step.
- `TodaysClassOnTheFrontPage.RecordNotToday` is `internal` and takes the step from `AssistWorkspace.DeclineTodaysClass` (its list and door, `madeBy: "sheet"`); `DeclineTodaysClass` now returns whether the record was written.
- `LaterClassesKept.KeepAtDeploy` (working folder and maker from the caller, as `TimetableMemory.WriteDown`), `LaterClassesKept.PlanInto` (the one planner, also used by `KeepTheClassesItPublished` inside Publish Class for a Date's step, where it makes no step of its own). The plain `Keep` stays for the links checklist's Publish only (W7b2-8).
- Riding lows of W7b2-9 review 2: `ShowAlertAsync` is cut out of the view and pinned whole (L1); the "File Explorer" exception is taken out only of the sentence its `in` names, `keptOnWindows.hiddenItems` (L2).

## For documentation 12

**W7b2-7: the sheets' records.** A record a sheet writes to remember a teacher's answer is one step of that one file, `madeBy` `sheet`, `todaysUndoKeepsIt: false`, as the mac's `NotToday.write` and `KeptRecord.write` (each a `JournaledStep` of its own, `UndoStepMaker.sheet`). Not Today goes `SectionDetailView` → `AssistWorkspace.DeclineTodaysClass` → `TodaysClassOnTheFrontPage.RecordNotToday(…, step)`. The answer at Deploy goes `SectionDetailView.AskAboutClassesDatedLaterAsync` → `LaterClassesKept.KeepAtDeploy(_window.Workspace.WorkspacePath, code, directory, section, keeping)`; the view names the working folder, the record names its maker. Publish Class for a Date keeps planning the record into its own step through `LaterClassesKept.PlanInto` and makes no second step (W7a's `PublishClassForADateKeepsTheClassItPublishesInTheSameStep`). A record that cannot be written returns false and nothing is thrown, as the mac's `try?`: the answer stands and the question is asked once more. A step left part way has written the record and returns true; it has no sentence of its own (the trail's door line names the kept file), as on the mac. Windows' bytes differ from the mac's, measured and named in `WindowsActionsOnTheMacFixture.WindowsOwnJson`:
- Not Today: Newtonsoft indented, `"key": value`, members version, day, class, the computer's line ends and a closing newline; `version` is the string "1" (as `file-formats.json` → `frontPageNotToday.keys.version` writes it), the mac's the number 1. Same members: day, class.
- Kept classes: System.Text.Json indented, members version, answeredAt, kept; each place without `.md` (as `laterClassesKept.keys.kept` says), where the mac's recorded step names the page with `.md`. Same members: version, answeredAt.

The links checklist's Publish still writes the kept record plainly (`LaterClassesKept.Keep`, writer scan 3), for W7b2-8.

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

- The links checklist's Publish (W7b2-8): `KeepTheClassesItPublished` with no step still calls the plain `LaterClassesKept.Keep`; W7b2-8 plans it into that sheet's own step with `LaterClassesKept.PlanInto`, and then the writer-scan entry for `LaterClassesKept.cs` goes (its reason says so).

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
