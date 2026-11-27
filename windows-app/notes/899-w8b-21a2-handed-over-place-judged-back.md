# #899 W8b-21a2: going back, the leaver is judged with the handed-over place free

Brief: `vm-tools/briefs/2026-11-27-899-w8b-21a2-handed-over-place-judged-back.md` (COMMON `2026-11-26-899-w8-COMMON.md`, order `2026-11-27-899-w8b-ORDER.md`). Windows' copy of the mac's U4b3 door-2. Branch `issue/899-w8b-21a-handed-over-place` (one branch for 21a1 to 21a6 and 21c), worktree `wt-899-w8b-21a`, built on 21a1's head 3ed3e35ac. `contracts/` untouched. Still inert: no readable step holds a handed-over place (21a4 makes one readable).

## For PROGRESS

- **`UndoCheck.Plan`, going back** (`backward`): the ops are met in reverse, so the filler comes before its leaver. The leaver is judged with the place FREE when its filler is a change of this plan, meaning the filler was not found already back (`opsNotChanged`, the set 21a1 keeps in both directions):
  - a move leaver goes through `WholeStateOf(..., fromIsHandedOver: true)`, the new flag beside `toIsHandedOver`, where its `from` side is `UndoMoveSide.Free` whatever stands there now (the filler's new page, or the link that moved in);
  - a removal taken back starts `original`/`working` at `Absent`, without calling `read`, so Day 3 is never read through the link still standing there. The same line that serves 21a1's new file going forward;
  - a filler skipped as already back leaves the place to be read from the disk as today.
  - `toIsHandedOver` is now passed as `placeIsFree && !backward`, `fromIsHandedOver` as `placeIsFree && backward`, as the mac's plan does.
- **The order going back needed no product change.** 21a1's `Ready.InTheStepsOrder` is true for any step with a handover, in either direction, and `LeadingOps`/`InOrderOps`/`WholeOps` hold each target's place in THIS plan's order, which going back is the step's ops reversed. `UndoDoor.TargetsOf` therefore already orders a backward handover step by the ops reversed (a file target at the first op, in the reversed order, naming its path), stable within one op. A step without a handover keeps files, then whole ops. The new tests pin both, and must-fail 3 proves the order test bites.
- **Leaves the folder going back** is 21a1's code unchanged: `inAHandoverWithALink` is set for a file op in a link's handover in either direction, so shape B's removal taken back is judged on the folders above at the plan and at staging (`HandedOver`).
- **Tests** (`UndoHandedOverPlaceTests`, 15 to 24): shapes A and B each taken back from their after state, the link inside and leading out (4, `SymbolicLinkFact`; shape B asserts Day 3 is never read); the filler already back, the removal judged from the disk (`ALeaverWhoseFillerIsAlreadyBackIsJudgedFromTheDisk`, which asserts Day 3 IS read); an edited new page still refused naming Day 3; a file's move taken back after its filler; a handover step going back in the step's ops reversed (the move, then the removal taken back, which today's order would invert); and today's backward order for a step with no handover.

## For documentation 12

The mac's door-2 "For documentation 12" section (`windows-app/notes/899-u4b3-door-2-handed-over-place-judged-back.md`) is now built on Windows as written. One Windows fact to add: for a MOVE leaver, a filler skipped as already back always leaves the origin free on the disk too (a new page not there, or a move whose `to` is free), so "read the disk" and "count it free" agree there; the skipped case is observable only for a removal taken back, where reading the disk is what decides. The skipped test is therefore written on a removal.

## Must-fail lines

`vm-tools/guest/899-w8b-21a2-mustfail.json`, run by `899-w8b-21a-pc-run.ps1` mode `mustfail` on the committed head ebd308976:

RED 3 of 3 (run `w8b-21a2-a`, 2026-11-27 04:12 to 04:16 on the PC; restored, 732 of 732 again):

- M1, the origin side read from the disk when the filler is taken back in the same plan (the backward `placeIsFree` line removed): 6 failing, among them shape B going back planned "changedSince courses/TST1O/section1/Unit 1, Day 3.md" (the removal read through the link), `AFilesMoveTakenBackAfterItsFillerIsReadyInTheStepsOrderReversed` planned changedSince Day 4 (the move's origin held the new page), and `AHandoverStepGoesBackInTheStepsOrderReversed` changedSince Day 3.
- M2, the origin side free when the filler was skipped (`!opsNotChanged.Contains(handover.FillerIndex)` dropped): `ALeaverWhoseFillerIsAlreadyBackIsJudgedFromTheDisk` failed, `Assert.Contains()` on the places read: the collection was empty (Day 3 never read from the disk).
- M3, the backward order left as files then whole ops for a handover step (`InTheStepsOrder = handovers.Count > 0 && !backward`): 3 failing (both shape B taken back, and `AHandoverStepGoesBackInTheStepsOrderReversed`), `Assert.IsType()` expected `MoveHere` first and found the file target (`Change` null).

## Runs

One PC run under the turn lock, `C:\vm-setup\w8b-21a2-a\run.log`, `899-w8b-21a-pc-run.ps1 -Mode classes,mustfail -RedRef 63ebcbed7` (launcher `vm-tools/guest/899-w8b-21a2-launch-a.ps1`). It took the lock at 04:12:45, released only its own (`LOCK-RELEASED`), and wrote `RUN_DONE` at 04:16:00. `HEAD-AFTER` SAME, `STATUS` empty.

- Red first: on the tests' own commit 63ebcbed7, `UndoHandedOverPlaceTests` failed 6 of 24: the four shape A and B taken-back tests, `AFilesMoveTakenBackAfterItsFillerIsReadyInTheStepsOrderReversed` and `AHandoverStepGoesBackInTheStepsOrderReversed` (each planned changedSince at the handed-over place or the move's `to`). The 3 new tests that passed are the inertness ones (the skipped filler, the edited new page still refused, today's order without a handover); their must-fails are M2 and M3, and the edited-page test is a guard that the free origin never lets a change by hand through.
- Green on ebd308976: both builds exit 0 (the app with 37 warnings, none new). 732 of 732 passed: `UndoHandedOverPlaceTests` 24, `UndoCheckContractTests`, `UndoDoorTests`, `NamedGapLedgerTests`, the three scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests`, and, because the plan and `WholeStateOf` are shared, `UndoSwapTests`, `UndoLinkMoveTests`, `UndoCarryingMoveTests` and `UndoRecoveryContractTests`. The PC has Developer Mode on, so the 8 `SymbolicLinkFact` tests ran there.
- `origin/dev` was 8046ca2e8 at the start and again before hand-back, already an ancestor of the branch, so no merge commit was needed either time.

## Left for the next piece

- 21a3 and later: nothing in the plan still waits for going back. The backward undo after a forward swap is tested on the plan and the swap directly; recovery's judgement of the pairs (door-3) is not built here.
- The `CannotTellNow` of following a mac-style `../library/Day 3.md` file link on NTFS (21a1's note) still stands for 21a6; the fixed backward plan never reads through the link either.

## For the director

Nothing parked.

## Self-check

1. Broke each fix and watched it fail: must-fail 1 to 3 above.
2. No timed waits in product or test.
3. Failure paths: no new sentence; the refusals are the existing `changedSince` and `cannotTellNow`.
4. Merges: `origin/dev` 8046ca2e8 is already an ancestor of the branch at the start and before hand-back, so the merge was "Already up to date" both times.
5. No number tuned by trial.
6. House style: the C# around it; no LINQ in new lines.
7. (W7b2 7) No fixture row moves; `NamedGapLedgerTests` green.
8. (W7b2 8) No writing call moved; `UndoWriterScanTests` green.
9. (W7b2 9) No riding lows named.
10. (W7b2 10) A step without a handover keeps today's backward order (`AStepWithNoHandoverGoesBackInTodaysOrder`).
11. No held row was the brief's to clear: the ledger is untouched.
12. No `KeysChecked` key added.
13. One function per rule: the handover finder stays `UndoOp.Handovers`, judged free by the one `placeIsFree` in `Plan`; the move's sides by `WholeStateOf`'s two flags.
14. No run left going, no lock left held, no lock removed that was not this run's.
