# W8-7: recovery of a killed carrying move (#899, Windows #949)

Branch `issue/899-w8-7-recovery-of-a-carrying-move`, from `origin/dev` 06e067fbe (pieces 1 to 6 in). `origin/dev` did not move during the piece (06e067fbe at the start and at hand-back), so there is no merge commit. **Never merges without piece 8.**

## For PROGRESS

- Recovery settles a step that moves a folder and edits a page inside it, killed at any point, whole by content (U4b's recovery, `opKinds.wholeOps`):
  - `UndoRecovery.FileStates` reads a carried edit where its folder is now (`PlaceNow`: under the move's `from` while nothing is at `to`, `IsAtItsOldPlace`, looked at by `UndoLinks.Look`).
  - The carrying move is judged by `CarryingMoveState`: on whichever side the folder is, the step's own staged and kept files inside left out (`UndoSwap.StepsOwnFilesInside`, piece 3's reading), each carried page taken back (last op first) by the plan's own rule (`TakenBack` runs `UndoCheck.Plan` on that one edit), the case-only move with one set of overrides for both spellings (the mac's `carryingMoveState`).
  - The put-back plan passes `ownSeq: step.Seq` (window 1 review, LOW 5).
  - Every recovery tidy uses `UndoStep.PathsToTidy`, `TidyClosedSteps` included (LOW 5's six calls).
  - The kept copies are judged at the folder's old place too: `ListHolds` judges a carried op at its place before the move (`op with { Path = oldPlace }`, the mac's `listHolds`), `KeptOriginalsLeft` walks `PathsToTidy`, `KeptOriginalsOfWhatWasRecorded` looks at both places.
  - Shadow tidies a step of files and moves (`ChangesOnlyFilesAndMoves`, the mac's `changesOnlyFilesAndMoves`, U4b part four's L3; the u4b notes' "Shadow tidy of a killed rename"), in `TidyClosedSteps` and in the shadow `nothingTookEffect` tidy. `ChangesOnlyFiles` had no caller left and is gone.
- One function per rule: at-or-inside is `UndoOp.PartInside` (in `CarryingMoveState`) and `UndoOp.PlaceBeforeTheMove` (which calls it); a link is `UndoLinks.Look`. No new spelling comparison.

## For documentation 12

- Done in this piece (the director's riding low): the paragraph "Which held rows fail on Windows today, and why" (section "What W8 owes from U4b2-9") now says what is true of this tree.

## Tests, red first

- Red ref 45ccde1e7 (the replay taught, the 11 U4b rows out of the ledger, the product as it was), run `899-w8-7-red`: **8 failed of 347**: 7 of the 11 U4b `recoveryCases` rows (`Assert.Equal() Failure: Strings differ` at the `movedFolder` check, and one "first is not before"), and the U4b2-13 `handEdit: second` row, which PASSED on the product as it was and so failed `HeldCaseStillStopsAtItsGap` ("ledgered as not built here yet … it now EXISTS"). The other four U4b rows (nothing took effect, and the like) passed already.
- `UndoShadowClosedStepTidyTests.AShadowStepWithAMoveIsLeftAloneByTheTidy` failed at 35e0d0641 (the new rule removes the staged file): it pinned the old rule. Rewritten as `AShadowStepWithAMoveIsTidied`, plus `AShadowStepWithATreeIsLeftAloneByTheTidy`, which keeps what the old test protected for a step that takes out a folder.
- The replay (`UndoRecoveryContractTests`) knows `withAMovedFolder`, `movedFolder` and `keptCopyLeftInsideTheFolder`. An unknown `handEdit` value fails by name, "a key this replay does not check: handEdit carried" (U4b2-13 LOW 5). The media folder, its move, the edit inside and `movedFolder`'s reading are one set of helpers in `UndoKindsForTheCases`, which the stack replay calls too.

## Ledger

- The eleven U4b `recoveryCases` rows are gone. So is the U4b2-13 `handEdit: second` row, because it passes (lesson 3).
- `Reason899W8U4b` now names only Rename folder's two recorded steps and their twelve traces, and says what W8-7 built. `Reason899W8U4b2HandEditCarried` no longer names `withAMovedFolder`, and it now holds one row, `handEdit: carried` (piece 8).
- Lesson 4: the keys I added carry only the `withAMovedFolder` rows. The one still held stops at the accepted gap text (must-fail 5 shows it RED without that).

## Must-fail lines

`vm-tools/guest/899-w8-7-mustfail.json`, run `899-w8-7-all` from the clean committed 33f5cdaec, each restored by `git checkout` (STATUS clean, HEAD-AFTER SAME). **5 RED of 5**, RESTORED 348 passed:

1. A carried edit read at `to` while the folder is at `from` (`readPath = path`): 3 failed.
2. The move judged with its carried edits as they are (the `TakenBack` line removed): 2 failed.
3. The own files counted in recovery (`overriding` empty): 3 failed.
4. The tidy not looking at the old place (`PathsToTidy` → `Paths` in Settle's five tidies): 1 failed (the `keptCopyLeftInsideTheFolder` row).
5. An unknown `handEdit` skipped silently: 1 failed (the held `carried` row fails with a NullReferenceException, not its gap).

## Runs

The PC (LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200), turn lock taken and released by each run (`LOCK-RELEASED`). The classes run were both builds, plus `UndoRecoveryContractTests`, `UndoRecoveryTests`, `UndoRecoveryReviewFixesTests`, `UndoShadowClosedStepTidyTests`, `UndoCarryingMoveTests`, `NamedGapLedgerTests`, `HarnessSourceRuleTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests` (that last one because its helpers moved).

- `899-w8-7-red`: 45ccde1e7, 8 failed of 347 (above).
- `899-w8-7-green`: 35e0d0641, 1 failed of 347 (the old shadow-tidy test, above).
- `899-w8-7-all`: 33f5cdaec, **348 passed, 0 failed, 0 skipped**; must-fail 5 RED of 5; harness 33 of 36 WHOLE in each place. The three that were not whole are below.
- `899-w8-7-harness`: 01ffc829e (a harness-only change after 33f5cdaec), `w8-carrying-move-kill` **36 of 36 WHOLE outside, 36 of 36 inside OneDrive** (OneDrive running).
  - The run: step, Undo and Redo; killed at the first point, at `beforeSwap@0` to `@3`, and before the end; shadow and live; recovered by a second process.
  - Live: every place one way, as the list says, and nothing staged anywhere inside the folder at either place.
  - Shadow, an Undo killed at `beforeSwap@1` to `@3` (closed interrupted, LeftAlone): the Undo's kept original of a.md stays inside the moved folder. It is the only copy of what a.md held (U3c: a closed step's kept original that differs from its page stays, as beside first and second), and the mac's tidy keeps it the same way. The harness counts it apart (`onlyCopiesInside=1`), allows it only in shadow, and counts it as a failure live. No `-new` file is left anywhere in any run.

## Left for the next piece

- Piece 8: `handEdit: carried` and the hand-edit put-back rule. The one row still held is under `Reason899W8U4b2HandEditCarried`.
- Recovery's put-back takes only the ops whose place is at the end (`endPaths`), as the mac's does. A carried edit put back on its own while its folder is at `from` (only a hand-edit case reaches this) would be read at `to`. That is piece 8's to judge.
- Recovery of a case-only move or a link's move killed part way: still no row (pieces 5 and 6's "Left").

## For the director

- The U4b2-13 `handEdit: second` row passed on the product as it was once the replay knew `withAMovedFolder`, so it left the ledger (lesson 3), and only one row stays held for piece 8. The brief expected two.
- Shadow keeps an only-copy kept original inside the moved folder for an Undo left part way. This is the U3c rule, not a gap (Runs, above). If the brief meant "nothing staged inside the folder" to hold in shadow too, the ruling would have to change on the mac first.

## Self-check

1 to 6 (NIGHT3's): tests first (red above); one invariant; no teacher-facing change; no timed waits (the harness's parked child is the existing `StopAt` pattern, killed by the parent); pushed as I went; no `contracts/` change. 7: replay rows green, ledger rows gone, reason sentences true. 8: no writer-scan change (no writing call moved); `UndoWriterScanTests` green. 9: riding lows done: U4b2-13 LOW 5 (must-fail 5), window 1 review LOW 5 (`ownSeq`, `PathsToTidy`, `TidyClosedSteps` by name), the 5-6 review's L2 (`StagedLeftovers` by `UndoLinks.Look`), and the documentation 12 paragraph. 10: n/a, since no action was converted. 11: done, and both reasons rewritten. 12: done (Ledger, above). 13: `UndoOp.PartInside`, `UndoOp.PlaceBeforeTheMove`, `UndoLinks.Look`, `UndoSwap.StepsOwnFilesInside`. 14: no run going, every lock released by its own run, no other lock touched.
