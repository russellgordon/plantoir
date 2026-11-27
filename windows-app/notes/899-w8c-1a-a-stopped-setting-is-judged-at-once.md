# #899 W8c-1a: a one-file settings step stopped part way is judged at once (Windows #949)

## For PROGRESS

- `UndoDoor.MakeTheStep`: when the swap comes back `Refused { LeftPartWay: true }`,
  the door is live and the step's ops are all `editJSON` on one file
  (`UndoStoppedStep.IsOneFileJsonStep`, the mac's `isOneFileJSONStep`), the
  door judges it at once (`ClosedAtOnce` → `JudgeAtOnce(seq)`): under the
  lock (the closing's wait), recovery's OWN settle on that one record
  (`UndoRecovery.SettleAtOnce`, a thin entry to the private `Settle`, which
  also forgets the refused-swap and abandoned notes as `Run` does). No
  second copy of the rules.
- Answers: new value: `Applied` (re-derived as a made step is), the caller
  says nothing; old value: `Refused` with the swap's refusal (a
  `changedSince` is retried by `WriteMemberAsOneStep` and
  `SaveCourseSettings` as today); neither: new `UndoOutcomeKind.NotMade`
  (closed `interrupted`, list cleared), thrown as `UndoStepNotMadeException`,
  never retried; unreadable or in use, lock not had, closing not written:
  new `UndoOutcomeKind.CouldNotFinish` with the seq, thrown as
  `UndoStepCouldNotFinishException(Seq, Refusal)`, left in flight (and noted
  abandoned, so the next recovery settles it). Neither exception names a file.
- `UndoDoor.PutBackAtOnce(seq)` (Put It Back), live only: under the lock,
  only a step in flight is swapped; each `editJSON` member at its after value
  is planned backward (`UndoCheck.Plan`, `ownSeq`) and swapped through
  `UndoSwap.Swap` with label `<seq>-recover`; closed `rolledBack`
  (`partlyTookEffect`) or `failed` (`nothingTookEffect`) by recovery's
  `Write`; recovery's rolled-back trail line; `TidyLeftovers` keeping only
  copies unless the list holds them. A member at neither value or unreadable
  refuses, writing nothing. A closed step is never swapped: put back only
  when the file already holds every old value.
- Shadow keeps today's behaviour (left part way, in flight).
  Many-file steps are unchanged.
- Writer scan: no new writing call (Put It Back's swap is the door's
  `UndoSwap.Swap`; `UndoStoppedStep.cs` is in `Plantoir.Core/Undo`).

## For documentation 12

A paragraph beside U4a's: "A one-file settings step stopped part way is
judged at once" — the five outcomes above, `JudgeAtOnce` calling
`UndoRecovery.SettleAtOnce`, and `PutBackAtOnce`. The door's two new
outcome kinds and the step's two new exceptions.

## Tests

`Plantoir.Tests/UndoStoppedStepTests.cs` (new), every mac door and put-back
test of `UndoStoppedStepTests.swift` that is not the alert's or a caller's
(those are W8c-1b's), plus: Save Course Settings never retries a not made;
Put It Back of an unreadable member refuses; shadow left part way; and
`TheContractsStoppedSettingCases`, the five `referenceCourses.settingStoppedCases`
rows from the JSON through `ReferenceCourseUpkeep.WriteSchoolYear` with a
live door stopped after its swap (`said`, `leftInFlight`, `undoOffers`).

The stop (`StopTheSwapPartWay`): `BetweenKeepingAndRenaming` edits the file
in place (the kept hard link sees it, so the swap refuses `changedSince`)
and rewrites the staged `-new` to the old year, a third year, or half the
bytes; `PutBackFailsAt` fails the reversal. "Cannot be read now" is the test
holding the settings file open with no sharing from inside `PutBackFailsAt`
(after the new content is in), so the settle's read is a sharing violation
(in use: tried again, the step left): test assembly only, no product seam.

The `settingCouldNotBeChanged` row: W8c-1b says the alert's words. Here
`WriteSchoolYear` still answers its catch-all sentence for it, so the row
asserts it is not said as saved, that the step is left in flight, and that
`PutBackAtOnce(2)` puts the old year back. **For W8c-1b:** sharpen that
branch to the alert's sentence once Set School Year answers the door.

Tests first: afbcdee9f, red by not compiling on its parent (the verdicts,
the exceptions, `JudgeAtOnce` and `PutBackAtOnce` do not exist there).

## Must-fail lines

`vm-tools/guest/899-w8c-1a-mustfail.json`, run `w8c-1a-mf1` on the PC at
73fd9a4f9, each alone, then restored: **5 of 5 RED**.

1. Judgement skipped: 10 of 19 red, e.g.
   `SetSchoolYearStoppedWithTheNewYearSavesAndSaysNothing` ("holds the new
   value: ICS3U's school year could not be saved"), `TheContractsStoppedSettingCases`.
2. Neither answered as could not finish: 4 red, e.g.
   `AStepWhoseFileHoldsNeitherValueIsNotMadeAndNeverRetried` (expected
   `UndoStepNotMadeException`), `JudgedDirectlyAThirdValueIsNotMade`.
3. Not made thrown as changedSince (retried): 4 red,
   `SaveCourseSettingsNeverRetriesANotMade`, the contract cases ("half
   written: left in flight").
4. Put It Back swapping a closed step: `PutItBackNeverSwapsAStepClosedMeanwhile`
   (expected `CouldNotPutBack`).
5. Judgement in shadow too: `ShadowLeavesTheStepPartWayAsToday` (no
   part-way exception).

Restored: 326 of 326.

## Runs

- `w8c-1a-r2` (PC, 73fd9a4f9): red ref afbcdee9f did not build (CS0246
  `UndoStoppedStepVerdict`, CS1061 `JudgeAtOnce`, `UndoStoppedStepTests.cs`
  line 220); both builds 0 errors; the ten classes 326 of 326 (19
  `UndoStoppedStepTests`), `NamedGapLedgerTests`, `UndoWriterScanTests`,
  `UndoOpKindsContractTests`, `UndoStackContractTests` among them.
- `origin/dev` merged before proving and before hand-back: 35b54c40a both
  times, nothing to merge (already contained).

## Left for the next piece

- W8c-1b: Set School Year, Save Course Settings and a one-file Rename
  folder answering `NotMade` / `CouldNotFinish`; the alert; the four wording
  rows; the contract row's `settingCouldNotBeChanged` assertion above.

## For the director

- Nothing parked. `UndoRecovery.Write` became `internal` (Put It Back
  closes the step with recovery's own writer).
- Ledger: no row moved, as the brief said.
