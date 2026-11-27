Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# #899 U4b3 door-2: going back, a handed-over place is judged free for its leaver

Brief: `vm-tools/briefs/2026-11-26-899-u4b3-door-2-handed-over-place-judged-back.md` (chain: `2026-11-26-899-u4b3-ORDER.md`). Branch `issue/899-u4b3-linked-class-page-moves-its-link`, worktree `wt-899-u4b3`, from door-1's head bdd04fa63. `contracts/` untouched. Inert, as door-1 is: no step readable today holds a handed-over place.

## For PROGRESS

- `UndoCheck.plan` now finds a step's handovers (`UndoCheck.handovers`, door-1) in BOTH directions. Each op carries two indices. `stepIndex` is its place in the step, as `handovers` and `opsNotChanged` name it. `opIndex` is its place in this plan's order (the step's order going forward, reversed going back) and orders the targets.
- Going back, the LEAVER of a handed-over place is judged with the place FREE when its filler's taking-back is a change of this plan (the filler is not in `opsNotChanged`; going back the filler always comes first). A move leaver goes through `UndoCheck.wholeState(..., fromIsHandedOver: true)` (new, `UndoOpKinds.swift`), where its `from` side is `.free`. A removal taken back starts from `.absent` and is never read through the link standing at the place. When the filler was skipped as already back, the disk is read as before. Going forward is door-1's rule, unchanged, under one flag (`placeIsFree`: the second op of the pair in this plan's order, when the first is a change).
- Order: a step with a handed-over place goes through door-1's `targetsInTheStepsOrder` going back too, keyed by `opIndex`, so the targets follow the step's ops reversed: each leaver's change goes in after its filler's. Shape B back: Day 2's new page taken back, the link moved Day 3 → Day 2, Day 3's page written again, Day 4's removed (pinned by `testShapeBGoesBackInTheStepsOrderReversed`). Every other step keeps today's order (door-1's inertness tests still pass).
- `UndoSwapTarget.handedOver` is set going back as going forward: a file op in a handover with a link's move (shape B's Day 3, written again while the link still stands there at staging) is judged on the folders above only at the plan and at staging. `UndoSwap.swap`'s `.moveHere` last look is unchanged: it reads the place at the moment of the change, after the filler's taking-back, as the shapes prove.
- Tests: `UndoHandedOverPlaceTests`, section "Going back (door-2)", 9 tests. Shapes A, B and C, inside and leading out, each made forward, undone, redone, undone again, and checked byte for byte against the folder before the step, every link by its target, the folder outside untouched and nothing staged left (6). Shape B's backward order (1). Two refusals (2): shape A with Day 3's new page edited by hand is refused `changedSince` Day 3 only (others 0) and nothing changes; shape B with the link moved by hand away from Day 3 and a plain file put there is refused `changedSince` Day 3 and nothing changes.

## For documentation 12

Windows' `UndoCheck.Plan` going back, in a step with a handed-over place (door-1's definition):

1. Find the handovers on the step's ops as written (forward indices) in either direction.
2. Going back the ops are taken in reverse, so the filler comes before its leaver. When the leaver is judged and its filler's taking-back is a change of the same plan (not skipped as already back), a move leaver's ORIGIN side counts as free whatever stands there now, and a removal taken back starts from "absent" instead of reading the disk (never through the link that still stands there). When the filler was skipped, read the disk as today.
3. Order such a step's targets by the step's ops reversed (a file target at the first op, in the reversed order, that names its path), keeping the given order within one op. Every other step keeps today's backward order (files, then whole ops).
4. The leaves-the-folder look at the plan and at staging for a file op paired with a link's move works as door-1 says, going back too.

The same Windows door piece as door-1's, which the director adds to the W8 ORDER. No contract row changes, so nothing is held.

## For documentation 09 (folded by door-4)

"U4b3 door-2: a handed-over place, going back. Going back the filler of a handed-over place is taken back first; the op that left the place (a link moving home, a page written again) is then judged with the place free, provided the filler's taking-back is a change of the same plan, and such a step's changes go in its ops' reverse order. A page edited by hand at the place, or something else put there, is refused `changedSince`, naming the place, before anything changes. Every step readable before door-4 is planned as before."

## Must-fail lines

`windows-app/notes/899-u4b3-door-2-mustfail.log`. M1 (the move back judged against the disk): 15 failures, every shape refused at the plan. M2 (the removal taken back read from the disk): shape B refused changedSince Day 3. M3 (today's backward order): shape B's targets came files then the move, and the swap was refused at Day 3. RED 3 of 3, the file restored byte for byte after each.

## Runs

- Red first, on door-1's sources (only the new tests in place): 19 tests, 15 failures, 8 of the 9 new tests failing. Shape A was refused `changedSince` Day 4, shapes B and C `changedSince` Day 3, and the edited-page refusal named Day 3 with others 1 (Day 4 as well). The ninth new test, the plain file put where the link was, is a refusal that already holds on door-1's head: it guards the new freeing from reaching too far, and it stayed green under every sabotage.
- Green: `UndoHandedOverPlaceTests` 19 of 19.
- Proof: `UndoHandedOverPlaceTests`, `UndoRenameFolderStepTests`, `JournaledStepTests`, `UndoJournalContractTests`, `UndoFilesContractTests`, `UndoDoorGuardTests`, `UndoWriterScanTests`, `UndoOpKindsTests` (`wholeState` changed): 177 tests, 0 failures.
- `origin/dev` was 253f8915f at the start and before hand-back, already in the branch: no merge commit either time.

## Left for the next piece

- door-3 (recovery): recovery's put-back calls the plan going back and now gets this judgement. How recovery judges each op of a handed-over pair, and door-1's `testAPlaceFilledSinceTheLinkLeftIsRefused` (`notPutBack`), are door-3's.

## For the director

Nothing parked.

## Self-check

1. Broke each fix and watched it fail: M1 to M3 (log).
2. No timed waits.
3. Failure paths: no new sentence; the refusals are the existing `changedSince`, naming the handed-over place.
4. `dev` merged: 253f8915f already in the branch at both points.
5. No number tuned by trial.
6. Scope: `UndoCheck.swift`, `UndoOpKinds.swift`, the test class, these notes. `contracts/` untouched.
7. The grep for `DispatchQueue|.map {|.filter {|.reduce(|$0` over the added lines is empty. The new test struct `LaidStep` has MARK sections.
8. No riding lows.
9. The rename record is still kept and the switch is still off (not touched).
10. No contract row is new or changed.
