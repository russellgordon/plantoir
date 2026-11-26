# W8-1: a refusal names the place that leads out (#899, Windows #949), 2026-11-26

Base `origin/dev` 0e12bc8ac. Branch `issue/899-w8-1-leaving-place-named`. `origin/dev` had not moved at either merge point (before the proof and before the hand-back: still 0e12bc8ac), so there are no merge commits; `git merge origin/dev` said "Already up to date" both times.

## For PROGRESS

- W8-1 (the Mac's U4b2-2 and its review 1, MEDIUM 1): when an Undo or Redo is refused because a place of an op no longer stays inside the working folder, the refusal names the FIRST of the op's places that leads out, in the order `path`, `from`, `to`, never the other side of a move. One function, `UndoPlaces.FirstPlaceLeadingOut(root, op)` (the Mac's `UndoCheck.placeLeavingTheFolder`), used by `UndoCheck.Plan` (the leaves-the-folder block, which named `op.PlaceName` before) and by both checks `UndoSwap.Swap` makes again just before each change, the staging check and the swap check (which named `target.RelativePath` before), through `UndoSwap.PlaceLeadingOut(target, root)` (the Mac's `UndoSwap.placeLeadingOut`): a `MoveHere` names the first of `move.Op.PathsNamed` that leads out; an external target names nothing; any other change names `target.RelativePath`. `SwapAFile` (one path) is unchanged.
- The stack replay reads `refusalNamed` and knows `moveThePageIntoAFolder`, `moveThePageBetweenFolders` and `linkItsNewFolderOutside`; the six `U4b2-2` stack cases pass and are out of the ledger.

## For documentation 12

- "What W8 owes from U4b2-2" is done by W8-1. The section can say: Windows' `UndoPlaces.FirstPlaceLeadingOut` is the one function; `UndoCheck.Plan` and `UndoSwap.PlaceLeadingOut` (both checks, `UndoSwap.cs` about 309 and 373 on 0e12bc8ac) call it; the four `UndoLeavingPlaceNamedTests` are the twins of the Mac's four `UndoDoorGuardTests` `...AtTheStagingCheck...`/`...AtTheSwapCheck...` tests (the junction made from `UndoSeams.AfterTheCheck` for the staging check, from `StopsHere("beforeSwap", 0)` for the swap check).
- `PlaceLeadingOut` keeps the Mac's fallback for a move: should the swap's two places ever not be the op's own spelling, a place that leads out that the op does not name is still refused, named by `target.RelativePath`.

## Must-fail lines

`vm-tools/guest/899-w8-1-mustfail.json`, run by `vm-tools/guest/899-w8-1-pc-run.ps1` (a copy of `899-w7b2-3-pc-run.ps1` that releases the turn lock only when `owner.txt` names its own run). From the committed tree b1421dd47; each sabotage applied alone, its tests run, restored with `git checkout`.

Run `w8-1-b`: **4 RED of 4**, then restored 489 of 489.

1. The plan names `op.PlaceName` again: RED, 2 failed, the two "only the move's new place" stack rows (Undo and Redo), at `UndoStackContractTests.WalkTheCase`'s `refusalNamed` assertion.
2. The staging check names `target.RelativePath` for a `MoveHere`: RED, 2 failed, `UndoRefusedAtTheStagingCheckNamesTheNewPlaceThatLeadsOut` and `RedoRefusedAtTheStagingCheckNamesTheOldPlaceThatLeadsOut`, at their `Assert.Equal` on the named place.
3. The swap check does the same: RED, 2 failed, `UndoRefusedAtTheSwapCheckNamesTheNewPlaceThatLeadsOut` and `RedoRefusedAtTheSwapCheckNamesTheOldPlaceThatLeadsOut`, likewise.
4. The replay ignores `refusalNamed`: RED, 6 failed, all six `U4b2-2` stack rows at the `refusalNamed` assertion (null against the place).

Row 4 is "the replay ignores refusalNamed" as "never reads the refusal's place after an undo or redo" (`RefusalNamed` never set). Taking the assertion out alone cannot go red while the product is right (the product names the right place, and nothing else then looks); row 1 being RED is what shows the assertion is the only thing in those rows that sees the name.

## Runs

All on the PC (LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200), under the turn lock `C:\vm-setup\wt-compare.lock` (free at each start, taken and released by the script; `LOCK-RELEASED` in each log). Both builds plus `UndoLeavingPlaceNamedTests`, `UndoStackContractTests`, `UndoDoorTests`, `UndoSwapTests`, `UndoCheckContractTests`, `UndoTraceContractTests`, `NamedGapLedgerTests`. No UI class, no harness.

- `w8-1-a-red`, e1064f17c (tests first, product unchanged): both builds exit 0; **10 failed of 489**, as expected:
  - the four `UndoLeavingPlaceNamedTests` at their `Assert.Equal` on the named place (Undo: expected `courses/TST1O/new/b.md`, actual `courses/TST1O/b.md`; Redo: expected `courses/TST1O/old/a.md`, actual `courses/TST1O/a.md`): the old place named, the other side of the move;
  - the six `U4b2-2` stack rows, still held: the two "only the new place" rows at the `refusalNamed` assertion (expected `courses/TST1O/new/b.md`, actual `courses/TST1O/b.md`), the other four as held rows that now play through (their gap closing).
- `w8-1-b`, b1421dd47 (product and ledger): both builds exit 0; **489 of 489**; must-fail 4 RED of 4; restored 489 of 489; the tree clean after (`STATUS` empty, `HEAD-AFTER … SAME`).

## Left for the next piece

Nothing of this piece. The carrying move, `placeAsFound` (piece 2) and links moved as themselves (piece 6) are not in its scope.

## For the director

No question. No `contracts/` change. No `mac-app/` change.

## Self-check

1 to 6 (NIGHT3-COMMON): tests were written first and seen red (above); only `windows-app/` changed (plus the two guest files in `vm-tools/`); no timed waits, no interim states, nothing a teacher sees; both builds and only the brief's classes run; must-fail recorded and restored; notes under the six headings.
7. No fixture row in this piece (no action step); the six ledger rows are gone and `Reason899W8U4b` no longer names `refusalNamed` or the three calls.
8. No writer moved; the writer scan is untouched.
9. Riding low night25-7 LOW 3: `Reason899W8U4b`'s last clause reads "…(UndoFormat.ShapeIsKnown), with the checkCases op key linkTarget, the calls … and the key linkedFolder". Night25-2 LOW 2: the current line numbers were used; nothing to change.
10. No action step; not applicable.
11. The six held rows pass and are out; `Reason899W8U4b` rewritten; no other reason names `refusalNamed` or the calls (grep); the constant is still used by other rows.
12. `refusalNamed` is carried by no row still held (only the six U4b2-2 stack rows carry it, Python over `shared-rules.json`).
13. One function per rule: every leaves-the-folder name comes from `UndoPlaces.FirstPlaceLeadingOut` (plan) or `UndoSwap.PlaceLeadingOut`, which calls it for a move.
14. No run left going, the lock released by the run that took it, no other lock touched.
