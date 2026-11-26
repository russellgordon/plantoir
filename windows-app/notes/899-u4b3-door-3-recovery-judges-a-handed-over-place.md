# #899 U4b3 door-3: recovery judges each op of a handed-over place as the other leaves it

Brief: `vm-tools/briefs/2026-11-26-899-u4b3-door-3-recovery-judges-a-handed-over-place.md` (chain: `2026-11-26-899-u4b3-ORDER.md`). Branch `issue/899-u4b3-linked-class-page-moves-its-link`, worktree `wt-899-u4b3`, from door-2's head 9c0f34536. `contracts/` untouched. Inert, as doors 1 and 2 are: no step readable today holds a handed-over place.

## For PROGRESS

- `UndoRecovery.fileStates` now judges every op first, then judges the two ops of each handed-over place together (`UndoCheck.handovers`, door-1's one rule, reused as it stands; it was already a `static func`). The LEAVER is judged again with the place free (a move: `wholeState(..., fromIsHandedOver: true)`; a removal: the place read as `.absent`) once its FILLER stands `.after`. The FILLER is judged again with the place absent (a move: `toIsHandedOver: true`; a new file: `.absent`) while its LEAVER stands `.before`. This repeats until nothing changes, at most once per op, so a chain of places (two links in a row, Insert Class with several linked later classes) settles too. A place holding something neither op recorded gives neither op `.before` or `.after`, so both stay `.neither`.
- A move that hands a place over is judged under its own name, `"from → to"` (`UndoRecovery.placeJudged`). Its `placeName` (its `from`) is the path of the file op it shares the place with, and under one name the two merged, so a part-way shape A (move after, write before) came out `.neither`. `settle` picks the ops to put back by the same name. A part-way shape A, stopped going forward, therefore puts back the link's move ONLY (endPaths holds the move's name, not Day 3), going back through `UndoCheck.plan` on that one op, which door-2 judges from the disk (P free, link at Q: ready). This was checked by reading the code. Every other op keeps its `placeName`, so a step with no handover is judged and settled exactly as before.
- `listHolds`: a kept original at a handed-over place is planned together with the pair's other op, in the step's order, so door-1's and door-2's plan judges the place as handed over. On its own, the write at a place the link stands on again is never `.ready`.
- Door-1's place filled after the link left (`notPutBack`: the link at Day 4, someone's file at Day 3, the staged new page beside it): recovery finds BOTH ops `.neither` (pinned by `testAPlaceFilledSinceTheLinkLeftIsInTheWayForRecovery`). So `settle` has nothing at its end to put back. It closes the step as interrupted (`couldNotPutBack` / in the way) and tidies only staged new content and copies. Nothing is written over the file put at Day 3, and the link is not moved over it. Nothing is lost. The run through `UndoRecovery.run` is door-5's.
- Tests: `UndoHandedOverPlaceTests`, section "Recovery's judgement (door-3)", 7 tests: shape A's table, shape B's table, shape C's first and third rows (all by hand); every shape stopped before every swap, forward and back (`UndoKillPoints.hook`, census never `neither`, part way in between); door-1's filled place; `listHolds`; and inertness (a readable U4b step judged as today).

## For documentation 12

Windows' `UndoRecovery` (the same Windows door piece as doors 1 and 2, which the director adds to the W8 ORDER):

1. Judge every op of the step as today. Then, for each handed-over place (door-1's `handovers`, the same rule the plan uses):
   - if the filler is judged AFTER, judge the leaver again with the place free (a move's origin side free; a removal's page read as absent);
   - if the leaver is judged BEFORE, judge the filler again with the place absent (a move's destination side free; a new file's page read as absent).
   Repeat until nothing changes (at most once per op). A place holding something neither op recorded leaves both "neither".
2. Name a move that hands a place over as "from → to" in recovery's per-place list (never its origin, which is the path of the file op at the same place), and choose the ops to put back by that same name.
3. When testing whether a kept original is an only copy, plan the page's op together with the other op of its handed-over pair, in the step's order.

Truth tables (P handed over, Q the move's other place). Shape A, link P→Q then new file at P: link at P, Q free = before/before; P free, link at Q = after/before; new at P, link at Q = after/after; something else at P = neither/neither. Shape B, removal at P then link Day 2→P: old page at P, link at Day 2 = before/before; P free = after/before; link at P, Day 2 free = after/after; a link with another target at P = neither/neither.

## For documentation 09 (folded by door-4)

"U4b3 door-3: recovery and a handed-over place. Recovery judges the two ops of a handed-over place together: the op that leaves it with the place free once the op that fills it stands done, and the filler with the place empty while the leaver still stands undone, so a step stopped before, between or after their swaps is whole before, part way or whole after, and only something neither op recorded is in the way. A move that hands a place over is judged under its two places, apart from the page at the same place, and a kept original there is tested as an only copy with the pair planned together."

## Must-fail lines

`windows-app/notes/899-u4b3-door-3-mustfail.log`. Each sabotage was built and run, then restored with `git checkout`; `git diff` was clean after each.

- M1 (the leaver judged against the disk again): 13 failures. Shape A's all-after row gave the move `.neither`, and every shape's later swaps were in the way.
- M2 (the filler judged against the disk again): 15 failures. Shape A stopped before swap 0 (all before) had the write in the way.
- M3 (the free side granted whatever the filler shows): 27 failures, including door-1's filled place, where 1 op was in the way, not 2.
- M4 (`listHolds` without the pair's other op): `testTheListHoldsAKeptOriginalAtAHandedOverPlace` failed.

RED 4 of 4.

## Runs

- Red first, with only the new tests in place (the product file stashed): 26 tests, 5 failing, all of them new: the three tables, the stopped-at-every-swap test (every stop in the way) and `listHolds`. Door-1's filled-place test and the inertness test passed, as guards should. M3 and the inertness check are their must-fails.
- Green: `UndoHandedOverPlaceTests` 26 of 26.
- Proof: `UndoHandedOverPlaceTests`, `RestoreRecoveryTests`, `UndoRenameFolderStepTests`, `UndoJournalContractTests`, `UndoFilesContractTests`, `UndoWriterScanTests` (the only class that reads `UndoRecovery.swift` as text): 130 tests, 0 failures. There is no `UndoRecoveryTests` class.
- `origin/dev` 253f8915f was already in the branch at the start and before hand-back: no merge commit either time.

## Left for the next piece

- door-5: a step whose handed-over move is in the way, or cannot be told, is named `"from → to"` in the `interrupted` line's `paths` and in `cannotTellNow(path:)`. This is not a single path. Decide when the end-to-end run lands whether those lines should name the move's `to` (or both places) instead. It is inert until door-4 makes such a step readable.
- door-5: the end-to-end settle of door-1's filled place (closed interrupted, nothing written over the intruder) is asserted here only through `fileStates`/`census`.

## For the director

Nothing parked.

## Self-check

1. Broke each fix and watched it fail: M1 to M4 (log).
2. No timed waits. The kill hook stops the swap on an event.
3. Failure paths: no new sentence.
4. `dev` merged: 253f8915f was already in the branch at both points.
5. No number tuned by trial. The bound on repeats is the op count, which is a proof bound, not a tuned number.
6. Scope: `UndoRecovery.swift`, the test class, these notes and the log. `contracts/` untouched.
7. The grep for `DispatchQueue|.map {|.filter {|.reduce(|$0` over both changed Swift files is empty. The one closure (`sort`) has named parameters. MARK sections are in place.
8. No riding lows.
9. The rename record is still kept and the switch is still off (not touched).
10. No contract row is new or changed.
