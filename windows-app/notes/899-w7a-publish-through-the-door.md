# #899 W7a: a daily action is one step through the door, starting with publishing

Branch `issue/899-w7a-publish-through-the-door`, from W4c (2e10771f6) with `origin/dev` c446f5f64 merged in (3dc806224).

## For PROGRESS

## 2026-11-21 — Undo and Redo, W7a (part): the step for a daily action, and Publish Pages and Hide Pages through it (#899, #949)

- `UndoActionStep` (`Plantoir.Core/Undo/UndoActionStep.cs`, the mac's `JournaledStep`): an action plans each file (`Write`), reads through the plan (`ReadText`), names the front page as a `recompute` (`KeepsTheFrontPageTrue`), and `Make()` hands ONE draft to `UndoDoor.Perform(UndoStepDraft)`: key, `pageCount`, `madeBy`, `class: A`, course, section, `holds`. Each before is read when the file is FIRST planned. A step that cannot be named (no `courses\` above the folder, a path out through a link, a target that is a link) is staged and swapped in together without the list in shadow, with one trail line; live, refused before anything is written. A target that is a folder, or a file unreadable at plan time, stops the action before anything is written.
- Refusals: `UndoStepRefusedException` (nothing written: the caller says "Nothing was changed: …") and `UndoStepLeftPartWayException` (a file could not be put back: the message names each kept original with `undo.wording.keptBesideIt`; the caller says `publishStoppedPartWay`). `UndoOutcome.LeftPartWay` is new on the door.
- Publish Pages and Hide Pages (`AssistWorkspace.Apply(PublishPlan …)`): one step, keys `publishPages` / `hidePages`; the front page is re-derived once after the step by the door (never a file of the step), or by the step itself when the door made none. `UndoHistory` is told each file's before and after as `Save` told it, the re-derived front page included.
- `madeBy` from `AssistWorkspace.Surface`: `menu`, `builtInAssistant:<id>`, `outsideAssistant::<id>`; the id is one GUID per workspace (the window's conversation, or the `plantoir-mcp.exe` session).
- "undo could not record a step" (`ActivityTrail.Event.UndoCouldNotRecordAStep`, `UndoTrail.CouldNotRecordWords`, the mac's `couldNotRecordLine`): written by the door when the list cannot take a step given as files (went ahead, nothing was changed, stopped part way), and by the step for a step it cannot name. Its ledger row and `Reason899` are gone.

## Fix round one (review 1 of W7a part one, NOT CLEAN; and W4c review 1's lows), 2026-11-21

- **M1, measured** (PC LENOVO i5-8365U, Windows 11 Pro 26200, desktop session by `schtasks /it`, "Show hidden files" off: `Hidden=2`; script `vm-tools/guest/899-w7a-explorer-measure.ps1`, result `C:\vm-setup\899w7a-explorer\result.txt`). A kept `-orig` made as the door makes it (a hard link to the page, the page then replaced by rename) has attributes `Archive` only, link count 1 after the rename; a copy the same. Outside OneDrive and inside it (OneDrive running): File Explorer LISTS both dot files and SELECTS each, by `explorer.exe /select` and by `SHOpenFolderAndSelectItems` (hr 0), read back through `Shell.Application.Windows()` (`Document.SelectedItems()`, `Document.Folder.Items()`). A copy marked Hidden is not listed and nothing is selected, by either call. So a leading dot hides nothing on Windows. The director's call (Windows imitates the Mac; to be confirmed with Russell): the swap marks every kept original Hidden once the page's rename is in (`UndoSwap.HideTheKeptFile`, after `wentIn`, so a hard link never hides the live page), and shows it again before a put-back renames it onto the page (`ShowTheKeptFile`; only an attribute the swap set: a page the teacher hid stays hidden). Every kept file is made by `SwapAFile` (the door, the plain write, recovery's put-backs), so this is the one place. Enumeration in recovery and the tidies uses `Directory.Enumerate*` without options (`EnumerationOptions.Compatible`, hidden included). Consequence for W7b's alert: with "Show hidden files" off, a Show in File Explorer button cannot show the kept file.
- **M2:** `ARecordedStepLeftPartWayIsSaidAsPartWayAndNamesTheKeptFile`, `AnUnrecordedStepLeftPartWayIsSaidAsPartWayWithItsTrailLine` (a read-only second page, the first page's put-back failing by seam).
- **M3:** `UndoHistory.FileState.BeforeBytes`; `MakeTheUndoStep` gives today's undo each page's bytes, written back as they were; `TextOf` reads as `File.ReadAllText` (byte-order marks). `AUtf16PageComesBackByteForByteAtTodaysUndo`.
- **M4:** the door's `Rederive` and the step's `RederiveTheFrontPages` catch whatever a re-derivation throws after the swap. `AFrontPageThatThrowsAfterTheSwapIsNeverSaidAsNothingChanged`.
- Lows done: couldNotWrite said "(the disk may be full, or Plantoir may not have permission to write there)"; a plain write names its page by full path, so the read-only sentence finds it; doc comments moved back; a test's stop (`StoppedByATest`) is an `InvalidOperationException`, never "Nothing was changed"; `KeepsTheFrontPageTrue` once per page. The doubled phrase in `editJSONCasesHow` is gone with W6's move of the rows to `contracts/undo-json-cases.json` (merged in); this branch's net `contracts/` change is W4c's README line only.
- W4c review 1: LOW 1 (`TakeTree` takes the next free kept name), LOW 2 (every kept name taken is couldNotWrite, folder and page), LOW 3 (`LeftNewestWords` names the list's content when the refusal has no path), LOW 5 (`PruningsTidyRemovesAKeptOriginalThatIsACopyOfItsPage`). Tests in `UndoSwapTests`, `UndoTrailWordsContractTests`, `UndoDoorTests`.
- B: pruning's tidy passes `onAside` (`UndoJournal.Prune(writer, trail)`, from `RecoverThenPrune`): `PruningsTidyWritesTheLineForAFolderItKeepsVisibly`.
- Must-fail: `vm-tools/guest/899-w7a-mustfail-2.json` (12 sabotages). Merged `origin/issue/899-w6-op-kinds` (6437a9b89) and `origin/dev` da5af161e (3aee10d3c).

### Not done in this round (left for the next writer)

- C (`ApplyWholeUnit`, Publish Class for a Date through the step): not started. Plan: an `UndoActionStep? _planningThrough` field read by the planners' eleven `File.ReadAllText` calls (lines 388, 444, 474, 727, 1187, 1276, 1398, 1453, 1501, 1519, 1531 at 13d66f531), set for the unit's loop; one `KeepsTheFrontPageTrue` instead of `ApplyIndexChange` per class. Publish Class for a Date today is `Apply(plan)` then `KeepTheClassesPublishedByTheirDate` (MCP `PlantoirTools.cs` ~1900): `LaterClassesKept.Keep` must write through the step.
- D (killed publish by the harness, W4c LOW 6) and E (`actionTraces` replay, `rule.recovery`'s U3 sentence): not started.
- Review 1 lows not done: unrecorded `shadow` swaps never tidied after a kill; a front page through a link out of the folder makes the step unrecordable; kept names found by comparing the folder before and after; stale remark in `PublishStoppedPartWayTests`; the workspace test's weak `NotEqual`.

## For documentation 12

### What Windows has built: W7a, the step for a daily action (#899, #949)

The bullets above, plus: the door is the product's through `UndoForThisProcess.Current.Door()` (the list under `AppDataRoot.Current\undo`, following `--state-dir`); `AssistWorkspace.UndoList` is a test's seam only. With the switch off, every page Publish and Hide write is the same text as before (`File.WriteAllText`'s UTF-8 without a byte-order mark); the only change a teacher can see is that a failure is now all or none.

## For W7b

- Entry points: `AssistWorkspace.NewUndoStep(key, course, section)`, then `step.ReadText` / `step.Write` / `step.KeepsTheFrontPageTrue`, then `MakeTheUndoStep(step)` inside the action's `UndoHistory.Record`, and in its `catch (IOException or UnauthorizedAccessException)` `StoppedWhileWriting(error is UndoStepLeftPartWayException, error)`.
- Still to go through it (writer scan entries still `waitsFor: W7`, counts unchanged since `Save` remains for them): `ApplyWholeUnit` and Publish Class for a Date (see "Not done" below), and every action W7b lists.
- The planners (`PlanPublish`, `IndexChangeFor`, `ClassPages`) read the DISK, not the step: an action that plans one class after another inside one step (a whole unit) must plan each class seeing the classes before it, so either the planner reads through the step or the action plans from the step's view. This is why `ApplyWholeUnit` was not converted here.

## Not done in this piece

- `ApplyWholeUnit` (one step for a unit, each class planned seeing the ones before it) and Publish Class for a Date with `later-classes-kept.json`: not converted (the planner reads the disk; budget).
- `actionTraces` replay (120 daily traces through the door, 12 rollover traces held under `Reason899W7U3b`): not written. No ledger row holds them and no Windows class reads them, as before this piece.
- `rule.recovery`'s U3 sentence on a closed shadow step: not checked.
- The prune-time tidy's "undo found a folder set aside": not built (the change is one `onAside` argument and a trail sink on `UndoJournal`, but its test needs a pruned unsettled tree step with a folder aside, which was not written; a change without a test that fails was not left in).
- Killed-step proof of a publish (injected and by the harness): not run.
- The File Explorer measurement of the kept file: not done; the alert's keys stay held.
- W4c review 1 lows: LOW 4 done (`contracts/shared-rules.json` `editJSONCasesHow`: "only for a row that platform holds by name as not yet measured"). LOWs 1, 2, 3, 5 and 6 not done (budget).

## Changed tests (the failure is now all or none)

`PublishStoppedPartWayTests.APageThatCannotBeWrittenIsAnsweredAndTheCopyIsNamedOnlyInTheWindow` (the page-list rows), `SectionVerbsTests.APublishThatStoppedPartWay_IsCarriedOut` and `UndoAcrossToolsTests.AnOperationThatThrewPartWayLeavesNothingOpenToSwallowTheNext` asserted the old file-by-file part-way outcome. A publish of pages is now one step, so a page that cannot be written leaves every page as it was, and the sentence is "Nothing was changed: …". The whole-unit rows still go part way: `ApplyWholeUnit` is not converted yet.

## Runs (PC, LENOVO i5-8365U, Windows 11 Pro 26200)

- `899w7a-c2` at 338ba328e: both builds 0; classes (Undo, ledger, trail, `Publish*`, `UndoHistory`) 1069 passed, 1 failed, 1 skipped. The failure is `PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel`, which also fails without this piece (W4c review 1, `int-n4-2`).
- Must-fail (`vm-tools/guest/899-w7a-mustfail.json`, 5 sabotages): all RED. A publish written file by file: 4 of 6 failed. A before read at make time: 1 of 6. The front page planned inside the step: 1 of 6. The trail line not written: 1 of 6. Today's in-memory undo not told: 1 of 6. After the restore, the same single unrelated failure; HEAD SAME.
