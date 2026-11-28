# W8c-3b1: the menu's section restore holds the Undo list across its swap (#899, Windows #949)

Brief: `vm-tools/briefs/2026-11-27-899-w8c-3b1-the-menus-section-restore-holds-the-list.md`. Base `day27c/integration-3` (holds f5b2d69c8); `origin/dev` merged in (it was already contained).

## What was built

- **`UndoRestoreSetAside.SwapHoldingTheList`** (`Plantoir.Core/Undo/UndoRestoreSetAside.cs`), the one function, the mac's `swapHoldingTheList`. It reads the working folder's identifier without making one; with none, the swap runs and the list is never asked for. Otherwise it takes the list's lock (`UndoJournal.WithLock`, waiting the list's `FinishWait`) and runs the swap inside it. When the swap says it replaced files, `SetAsideSteps` runs in the same lock. When the lock is still busy before the swap ran, it throws `TheListIsBusy` and nothing has moved. Any other failure of the list lets the restore run (the swap runs unlocked if it had not yet run). If files were replaced, the trail then gets `UndoTrail.ListNotReachedByARestoreWords`, the mac's `closed: false` line.
- **`UndoListForARestore`** (same file): journal, mode, trail and finish wait. `OfThisProcess()` gives `UndoForThisProcess.Current` with `UndoDoor.FinishWait` (the door's own 10 s, not a new number). A test passes its own list.
- **`CourseRestorer.SwapSectionHoldingTheList`** (private) is what the menu route calls. It works out what was replaced (`ReplacedByASectionRestore`: `courses/<CODE>/section<N>` plus every outside file whose treatment is not `leftAsItIs`; the shared pages whose keys it rewrites are not included). Then it calls the one function, with a closure that runs `SwapSectionInPlace` and then `thenInsideTheLock`. The closure returns true when every move was made or `WayBackDidNotFinish` was thrown, and false when `leftAsItWas` (nothing moved, or everything put back). It keeps its error and rethrows it once the lock is let go. `TheListIsBusy` becomes `wording.leftAsItWas` with `ListBusyReason` ("another change in Plantoir was still being made", the mac's `RestoreSwap.listBusyReason`).
- `RestoreSectionFromTheMenu` has an internal overload that takes `Func<UndoListForARestore>`. The public one passes `OfThisProcess`. The keys are written inside the lock, followed by the new `SwapPoint.PerSectionKeysPutBack`. The `keepingWhatWasReplaced` seam is unchanged (it is still invoked at the end of `SwapSectionInPlace`, now inside the lock).
- `git grep WithLock` in `CourseRestorer.cs` finds **no** call site: the one call is inside the one function in `UndoRestoreSetAside.cs`. No `Thread.Sleep` or `Task.Delay` was added.

## Tests: `UndoRestoreSetAsideSectionTests` (nine, the brief's order)

These run the real restore over the `UndoScribe`'s working folder A and its own live list, with steps stopped by the real door for a gone process. Each named test checks one of the brief's points:

1. `AStepStoppedInTheSectionIsSetAsideAndRecoveryNeverWritesTheRestoredSection`.
2. `AStepPartlyInsideGetsTheEventForTheSectionAndTheOutsideFilesItMoves` (the timetable file counts as an outside file).
3. `AStepOfAnotherCourseSurvivesAndIsStillRecovered`.
4. `AFirstMoveThatFailsSetsNothingAsideAndTheStepIsRecoveredByContent`.
5. `ASwapThatPutsEveryFileBackSetsNothingAsideAndTheStepIsRecoveredByContent`.
6. `ASwapStoppedPartWayWithFilesNotPutBackSetsAside`.
7. `TheLockIsHeldForEveryMoveOfTheSwap`: a second journal over the same folder tries the lock with no wait at every move.
8. `ABusyListRefusesBeforeAnythingMoves`: another list holds the lock past the test's finish wait (200 ms, the door's seam).
9. `ThePerSectionKeysAreWrittenInsideTheLock`.

Tests first: commit 4feecdae9 (only the seams, which do nothing yet). The red check of that commit and the classes run are in `vm-tools/runs/w8c-3b1-writer.proof.txt`: `RED-CHECK 6 failed of 9 at 4feecdae9` (red: 6, the part-way set-aside, the keys inside the lock, the lock across the moves, the busy refusal and two more; cases 3 to 5 pass on the old product too, as they assert what must NOT happen). Classes at 19ed75f52: `CLASSES 312 passed of 313`. The one failure was case 1's own assertion: its step's only file outside the section had been made, so recovery rightly closed the rest as made rather than putting it back (as 3a's `ARestOfTheStepThatWasMadeIsClosedOffTheListNotApplied`). The test now gives the step a second outside file that was not made, `.publish_state/section1.json`, which the restore leaves as it is, so the rest is rolled back by content. **That fix has not been run**: the clerk's standard proof is its first run.

Must-fail rows: `vm-tools/guest/899-w8c-3b1-mustfail.json`, five rows, the brief's five, each naming one test above. They have not been run: the clerk runs them.

## For 3b2

Call the same function. The assistant route builds its own `swap` closure or reuses `SwapSectionHoldingTheList`:

```csharp
internal static IReadOnlyList<long> UndoRestoreSetAside.SwapHoldingTheList(
    IReadOnlyList<string> replacedPlaces, string workingFolderRoot, string course,
    Func<UndoListForARestore> theList, Func<bool> swap)
```

`CourseRestorer.SwapSectionHoldingTheList(sectionNumber, courseDir, payload, outsideFiles, aside, hooks, keepingWhatWasReplaced, theList, thenInsideTheLock)` already does the section's part. `RestoreSection` needs only to call it and to take a `Func<UndoListForARestore>`.

## For #873-8

The same two calls with `courses/<CODE>`: `SwapHoldingTheList(["courses/" + code], workingFolderRoot, code, theList, swap)`. Inside, it calls `UndoRestoreSetAside.SetAsideSteps(["courses/" + code], workingFolder, writer, trail)`. The swap closure returns true once the whole-course swap has replaced files.

## For documentation 12

Nothing here is wrong in documentation 12 as far as this piece reads it; the one-section restore's Undo section can name `SwapHoldingTheList` when 3b2 lands.

## Self-check

- Every sentence on the failure paths is true. The busy refusal is thrown only when the lock was refused before the swap ran. Any other list failure runs the swap and, if files were replaced, writes the trail line. `leftAsItWas` sets nothing aside. A part-way stop sets aside.
- There are no timed waits. The lock wait is the door's `FinishWait`, and the tests use the door's own seam for it.
- `origin/dev` is merged in.
- There are no contract cases here: the piece adds no contract key, and the busy reason sits in the existing `leftAsItWas` slot, as the brief rules.
- One function per rule: every "inside a replaced place" comparison goes through `UndoOp.PartInside` (unchanged, inside `SetAsideSteps`).
- No run was left going, no lock was left held, and no lock that this piece did not take was removed.
