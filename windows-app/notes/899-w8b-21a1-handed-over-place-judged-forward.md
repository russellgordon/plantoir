Removed by #1055 (2026-11-27): symbolic links in course content are not supported; no step hands a place over.

# #899 W8b-21a1: going forward, a handed-over place is judged free for its filler

Brief: `vm-tools/briefs/2026-11-27-899-w8b-21a1-handed-over-place-judged-forward.md` (COMMON `2026-11-26-899-w8-COMMON.md`, order `2026-11-27-899-w8b-ORDER.md`). Windows' copy of the mac's U4b3 door-1. Branch `issue/899-w8b-21a-handed-over-place` (one branch for 21a1 to 21a6 and 21c), worktree `wt-899-w8b-21a`. Base `origin/day27/integration-7` 6b71fb803 (`dev` 8046ca2e8 plus 15a, 15b, 16, 21), as the director's prompt said instead of the brief's `origin/dev`. `contracts/` untouched. Inert: no readable step holds a handed-over place.

## For PROGRESS

- **One finder, `UndoOp.Handovers(ops)`** (`UndoFormat.cs`), returning `UndoHandover(LeaverIndex, FillerIndex, Place, ALinkMoves)` in the step's order. The leaver is `UndoOp.PlaceLeftBy` (a handing-over move's `from`, or a `writeFile` with a before-hash and no after-hash), the filler `UndoOp.PlaceFilledBy` (a handing-over move's `to`, or a `writeFile` with no before-hash and an after-hash). The filler comes later. The place is compared by `UndoOp.PartInside(place, filled) is ""`, the one comparison (COMMON lesson 6). At least one of the two is `UndoOp.HandsOverAsAMove`: `Kind == move`, no `listingSha`, not `IsCaseOnlyMove`, and `sha` or `linkSha`. `moveApart` and `setAside` are other kinds, so they never count. Each leaver hands its place to the FIRST filler after it. `ALinkMoves` is `linkSha` on either op. 21a2 to 21a5, the format check and recovery call this finder; none of them may write a second one.
- **`UndoCheck.Plan`, going forward** (`!backward`):
  - A filler is judged with the place FREE when its leaver is a change of this plan, meaning the leaver was not found already as wanted. `opsNotChanged` records an op's place in the step at `AlreadyBack`/`AlreadyRedone` for a whole op, and at `state != wantedFrom` for a file op.
    - A file filler's `original`/`working` start as `Absent`, without calling `read`.
    - A move filler goes through `WholeStateOf(..., toIsHandedOver: true)`, where its `to` side is `UndoMoveSide.Free`.
    - A leaver skipped as already done leaves the place to be read from the disk as before.
  - The order: `Ready.InTheStepsOrder` is true only for a step with a handover. `UndoDoor.TargetsOf` then calls `UndoCheck.TargetsInTheStepsOrder` over `Leading`, the files and `Whole`, each with the op it comes from (`LeadingOps`, `InOrderOps` from the first op that names the file's path, and `WholeOps`, by its place in this plan's order). The sort is stable within one op. Every other step keeps today's order exactly (leading, files as met, whole).
  - Leaves the folder: a file op (never a whole op) in a handover where either op is a link's move goes through `UndoPlaces.FirstPlaceLeadingOut(root, op, judgedOnTheFoldersAbove: true)`, which calls `UndoPlaces.StaysInsideAbove`. That function is factored out of `StaysInside(root, relative, op)`'s link branch, so one function judges a link's own place and a handed-over file place. Its path goes into `Ready.HandedOver`, and `TargetsOf` sets `UndoSwapTarget.HandedOver`.
- **`UndoSwap`:** the look before STAGING is `PlaceLeadingOut(target, root, atStaging: true)`. It judges a `HandedOver` file target (`Change` null) by `StaysInsideAbove` only. The look before each CHANGE is unchanged (`SwapAFile`'s `StaysInside(root, RelativePath)`) and judges the place whole: by then the leaver has gone.
- **Windows reads no file mode when it stages** (`StageAFile` writes a new file and copies nothing from the place). The brief's "never read the place's file mode through the link at staging" therefore needs no change on Windows. `CopyTheLookOf` (attributes, creation time) runs only when the swap REPLACES a file it found at its change, and a handed-over filler finds none.
- **Why `toIsHandedOver` and not an `overridingTo` entry at "":** `overridingTo` names paths inside a moved folder and what U4b's carried edits leave there. An entry at "" would read as a carried file at the move's own place. This is the mac's reason, kept.
- **Tests:** `UndoHandedOverPlaceTests`, 15. The finder has 9 rows: shapes A and B, a filler spelled in another case, first filler only, two writes with no move, a folder move, a case-only move, and `moveApart` and `setAside` as a theory. The plan and swap have 4 shape tests (A and B, each with the link inside and leading out; `SymbolicLinkFact`). There is one test of today's order for a step with no handover, and one test that only a file op in a handover with a LINK carries `HandedOver`.

## For documentation 12

The mac's door-1 "For documentation 12" section (`windows-app/notes/899-u4b3-door-1-handed-over-place-judged-forward.md`) is now built on Windows as written, with two Windows facts to add:

1. Windows' staging reads no file mode, so the mode clause of step 4 does not apply. Nothing is read from the place at staging (`StageAFile`).
2. The order is applied in `UndoDoor.TargetsOf`, the one place that turns a plan into swap targets, so the door, recovery's put-back (`UndoRecovery` 1219) and every later caller get it alike.

## Must-fail lines

`vm-tools/guest/899-w8b-21a1-mustfail.json`, run by `899-w8b-21a-pc-run.ps1` mode `mustfail` on the committed head 1567029fd (each sabotage alone, built, `UndoHandedOverPlaceTests` run, then `git checkout` restore):

RED 4 of 4 (run `w8b-21a1-a`, 2026-11-27 04:03 to 04:07 on the PC; restored, 723 of 723 again):

- M1, a filler read from the disk at its place: 3 failing. Shape A inside was planned `CannotTellNow` (the read went through the link). Shape A leading out and `OnlyAFileOpInAHandoverWithALink…` were not `Ready`.
- M2, the targets left in today's order for a handover step: 3 failing. `Assert.Equal` on `[Day 4, Day 3]` differed at position 0, and the shape A swaps were not `Swapped`.
- M3, `listingSha` counted as a move that hands over: `AFoldersMoveNeverHandsOver` failed. It found `UndoHandover { 0, 1, courses/TST1O/section1/media, False }`.
- M4, the staging look resolving the place through the link: `ShapeAWithTheLinkLeadingOutIsNeverRefusedAtThePlanOrAtStaging` failed. "shape A was swapped refused ChangedSince courses/TST1O/section1/Unit 1, Day 3.md".

## Runs

One PC run under the turn lock, `C:\vm-setup\w8b-21a1-a\run.log`, `899-w8b-21a-pc-run.ps1 -Mode classes,mustfail -RedRef 79d80003e`. It took the lock at 04:03:05, released it, and wrote `RUN_DONE` at 04:07:13.

- Red first: on the tests' own commit 79d80003e (`Handovers` stubbed to return none, `HandedOver` a plain property), `UndoHandedOverPlaceTests` failed 9 of 15. The 5 finder rows that find a handover failed with `Assert.Single()`: the collection was empty. Shape A inside was planned `CannotTellNow`. Shape A leading out was `changedSince` Day 3 (the plan's leaves-the-folder look through the link). Both shape B tests were `changedSince` Day 2 (the move's destination was not free). `OnlyAFileOp…` was not `Ready`. The 6 that passed are the never-hands-over and today's-order rows, as inertness tests should; their must-fails are M2 and M3.
- Green on 1567029fd: both builds exit 0 (the app with 37 warnings, none new). 723 of 723 passed: `UndoHandedOverPlaceTests` 15, `UndoCheckContractTests` 304, `UndoSwapTests` 24, `UndoDoorTests` 14, `NamedGapLedgerTests` 8, `UndoWriterScanTests` 5, `UndoOpKindsContractTests` 78, `UndoStackContractTests` 147, and, because the plan, `TargetsOf` and `StaysInside` are shared, `UndoLinkMoveTests` 11, `UndoCarryingMoveTests` 30 and `UndoRecoveryContractTests` 87. The PC has Developer Mode on, so the 4 `SymbolicLinkFact` shape tests ran there; on the VMs they skip, saying why.
- `origin/dev` was 8046ca2e8 at the start and again before hand-back. It is already an ancestor of the base, so no merge commit was needed either time.

## Left for the next piece

- 21a2 (going back): `placeIsFree` is set for `!backward` only. Going back it must be set for the LEAVER when its filler is a change of this plan (the mac's `fromIsHandedOver`). `WholeStateOf` has `toIsHandedOver` only. 21a2 adds `fromIsHandedOver` beside it, and the absent-start for a file leaver (a removal taken back). `opsNotChanged` and `stepIndex` already work in both directions. `TargetsInTheStepsOrder` already uses this plan's order (reversed going back), as the mac's does.
- The shapes' Undo after a forward swap is not tested here (door-2's).
- On the red run, shape A with the link INSIDE was planned `CannotTellNow`, not `changedSince`. Reading `Unit 1, Day 3.md` through a file symbolic link holding `../library/Day 3.md` with a forward slash could not be read now on NTFS. The fixed plan never reads through it. The library page itself is read by its own path in the test. 21a6, which reads a link move's old place as free in `UndoActionStep`, should know this: a file link holding a mac-style relative target with `/` may not resolve when Windows follows it.

## For the director

Nothing parked.

## Self-check

1. Broke each fix and watched it fail: M1 to M4 above.
2. No timed waits in product or test.
3. Failure paths: no new sentence; the refusals are the existing `changedSince`.
4. Merges: `origin/dev` was 8046ca2e8 at the start, already in the base (integration-7), so the merge said "Already up to date". The same before hand-back (see Runs).
5. No number tuned by trial.
6. House style: the C# of the files around it. LINQ is not used in the new lines. Nothing outside the brief's scope changed.
7. (W7b2 7) No fixture row moves; `NamedGapLedgerTests` green.
8. (W7b2 8) No writing call moved; `UndoWriterScanTests` green.
9. (W7b2 9) No riding lows named.
10. (W7b2 10) Every step without a handover keeps today's order (`AStepWithNoHandoverKeepsTodaysOrder`, must-fail 2 for the other way).
11. No held row was the brief's to clear: the ledger is untouched.
12. No `KeysChecked` key added.
13. One function per rule: the handover finder is `UndoOp.Handovers`, its place comparison `UndoOp.PartInside`, the folders-above judgement `UndoPlaces.StaysInsideAbove` (now also behind the link branch of `StaysInside(root, relative, op)`), "is a link's move" the existing `LinkSha is not null`.
14. No run left going and no lock left held. The run released only its own lock (`LOCK-RELEASED`).
