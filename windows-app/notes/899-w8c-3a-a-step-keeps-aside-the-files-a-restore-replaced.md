# #899 W8c-3a (Windows #949): a step in flight keeps aside, per file, what a restore replaced

Base `origin/dev` 35b54c40a, brought to 99499d6b7 (fast-forward, before any
proof; the ledger's merge kept dev's `Reason899W8bLinkedClassPage` and
relink row, and dropped only this piece's two rows). Tests first in
6c91d3ad1; product in d546482d7 and ef929a20e (dev's new
`TidyLeftovers(step, root, trail, ...)`). Second merge check before hand-back:
`origin/dev` still 99499d6b7, contained, so no re-run.

## For PROGRESS

- `UndoRestoreSetAside.SetAsideSteps(IReadOnlyList<string> replacedPlaces,
  UndoWorkingFolder workingFolder, UndoJournalWriter writer,
  Action<UndoTrailLine>? trail = null)` (`Plantoir.Core/Undo/UndoRestoreSetAside.cs`),
  the function W8c-3b calls inside the list's lock held across the swap.
  `replacedPlaces` are paths inside the working folder (`courses/<CODE>` or
  a section folder); `workingFolder` is the folder's identifier and the path
  it is at now (where staged files are tidied). Returns the seqs set aside.
- A step in flight made in this working folder (identifier compared without
  regard to case) naming a file at or inside a replaced place
  (`UndoOp.PartInside`, the one comparison): wholly inside, closed
  `interrupted`, phase as it stood, reason `setAsideByARestore`, `paths`
  every file it names, no clearing; partly inside, the new journal event
  `filesReplacedByARestore` (`seq`, `reason`, `paths` the files newly set
  aside), the step stays in flight. Idempotent. An unreadable step is skipped.
  Staged files of the ops set aside tidied, live only, keeping a kept
  original that is the only copy (`UndoSwap.TidyLeftovers`, keepingOnlyCopies).
  The line is made durable (`Sync`) before the tidy.
- Format: `UndoEvent.FilesReplacedByARestore` in `UndoFormat.Events`;
  `UndoLine.Paths`; a line of this event whose `paths` is missing, not an
  array, or holds anything but a non-empty string is unreadable (a barrier),
  never read as naming no file.
- Fold: `UndoFold.Moves` gains the contract's row word for word;
  `UndoFoldedStep.SetAsidePaths` (union, kept by `Copy`); the event moves no
  step and is ignored for a step not in flight.
- Recovery: `UndoRecovery.Settle` judges `UndoRestoreSetAside.StepWithout(SetAsidePaths, step)`;
  a settling ending (applied, undone, redone, failed, rolledBack) becomes
  `interrupted`/`setAsideByARestore` naming the files set aside, no clearing
  (`ClosingWithFilesSetAside`); changedByHand and couldNotPutBack unchanged;
  no redo branch dropped for such a step. The result carries the reduced
  step, so the door's re-derive after the hold never re-derives a set-aside op.
- Trail: `ActivityTrail.Event.UndoSetAsideByARestore`, "undo set aside a
  change a restore replaced", the mac's words (`UndoTrail.SetAsideByARestoreWords`),
  one line per step set aside; written through `UndoTrail.ToTheActivityTrail`'s arm.
- `UndoJournalWriter.Journal` (new accessor): the set-aside reads `IsLive`
  and the process memory from it.

## For documentation 12

- The restore set-aside (list's side): as "For PROGRESS". The
  "could not be reached" trail form is NOT built here (it belongs to the
  restore's caller, W8c-3b, which knows when the lock could not be had).

## Must-fail lines

`vm-tools/guest/899-w8c-3a-mustfail.json`, class `UndoRestoreSetAsideTests`.
All 5 RED (run w8c-3a-b), each restored by `git checkout` after its run;
the restored run passed 429 of 429.

| Sabotage | RED tests |
|---|---|
| (1) recovery judges a set-aside file | `RecoveryNeverWritesARestoredPageAndSettlesTheRest` ("recovery wrote into the restored first.md"), `ARestOfTheStepThatWasMadeIsClosedOffTheListNotApplied` |
| (2) a step partly inside closed whole | `AStepPartlyInsideGetsTheEventAndStaysInFlight`, `RecoveryNeverWrites…`, `ASecondCallSetsAsideNothingNew` |
| (3) the identifier not compared | `AStepOfAnotherWorkingFolderIsUntouched` |
| (4) a clearing written with the closing | `AStepWhollyInsideIsClosedInterruptedWithEveryFileAndNoClearing` (two lines, not one) |
| (5) the event ignored by the fold | `AStepPartlyInside…`, `RecoveryNeverWrites…`, `ARestOfTheStep…` and two more (5 of 10) |

## Runs

- PC, `C:\vm-setup\w8c-3a-a` (d546482d7): did not compile (dev's
  `TidyLeftovers` signature changed under the merge); nothing counted.
- PC, `C:\vm-setup\w8c-3a-b` (ef929a20e, `899-w8c-3a-launch-b.ps1`): tests
  commit 6c91d3ad1 RED (does not compile: `UndoRestoreSetAside` and
  `ActivityTrail.Event.UndoSetAsideByARestore` do not exist,
  `UndoRestoreSetAsideTests.cs` lines 43, 104, 118). Both builds exit 0.
  Classes `UndoRestoreSetAsideTests`, `UndoFoldMovesContractTests`,
  `UndoRecoveryTests`, every `*ContractTests` (UndoRecovery, UndoStack,
  UndoOpKinds, FileFormat, ContractTests and the rest the `~ContractTests`
  filter matches), `ActivityTrailWiringTests`, `NamedGapLedgerTests`,
  `UndoWriterScanTests`: 429 of 429 passed. Must-fail 5 of 5 RED. Lock
  taken and released by the run itself; HEAD unchanged after.

## Left for the next piece

- W8c-3b: call `SetAsideSteps` from the one-section restore inside the
  list's lock across the swap; the "could not be reached" line.
- #873: the staged whole-course restore calls it with `courses/<CODE>`, and
  the settle of a done record sets aside again (`Reason873` says so).

## For the director

- Self-check: tests red first (compile, named above); each sabotage RED;
  no timed waits (the lock's own wait only); nothing a teacher sees (trail
  only, the mac's words); `origin/dev` merged before proving and checked
  before hand-back; no number tuned; contracts read by name, no
  `contracts/` change; no run going, the lock released by the run.
- Ledger: both `Reason899RestoreSetsAsideAStoppedStep` rows cleared, the
  constant gone; `Reason873` now says the staged restore calls
  `UndoRestoreSetAside.SetAsideSteps` inside its lock across the swap, and
  again at the settle of a done record. `UndoFoldMoves` area stays (the
  test still asks the ledger; the table now compares 21 rows, none deferred).

- `UndoRecovery.Interrupted` made internal (was private) so the closing line
  has one builder. Shared-function changes kept to `Settle`'s first lines and
  one line before its write, for a clean merge with W8c-1a's `SettleAtOnce`.
