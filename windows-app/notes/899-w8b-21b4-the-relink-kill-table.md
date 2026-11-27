Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# W8b-21b4 (#899, Windows #949): the harness kills every chained link move at every stop point and loses no link

Brief `vm-tools/briefs/2026-11-27-899-w8b-21b4-the-relink-kill-table.md`, with the director's addition (Insert Class at a day whose page is a link). Branch `issue/899-w8b-21b-relink` from 21b3's pushed head 5447b07f4. `origin/dev` 454ef4c6f, already merged in, fetched before proving and again before handing back: unchanged, so no merge commit this piece. No `contracts/` or `mac-app/` change.

## For PROGRESS

- `Plantoir.UndoHarness/W8bRelinkRuns.cs`, mode `w8b-relink-chain-kill <folder> [shapes|all] [in|out|all] [yes|no]` (child `child-w8b-relink-chain`; recovery is 21a5's `child-w8b-handover-recover`). Ten shapes, each laid as Insert Class makes it, highest first, link texts as the mac's table writes them (`Unit 1, Day 2.md`, no separators), the pages Day 1 and Day 2 laid as the files the links lead to:
  - the mac's four `ChainShape`s: `twoChainedRelinks`, `threeChainedRelinks`, `aMoveThenARelinkIntoItsPlace`, `aRelinkThenAMoveIntoItsPlace`;
  - review G's five: `fourChainedRelinks`, `moveRelinkMove`, `relinkMoveRelink`, `twoRelinksWithTheSameTexts`, `twoMovesThenARelink`;
  - the director's: `aRelinkFromADayANewPageFills` (Day 4's link relinked into Day 5 and the new class page written at Day 4, the relink's `from`, staged beside it).
  Each once inside (`in`) and once with Day 2's text a full path to a page outside the working folder (`out`). Each made, undone and redone by a child parked at every stop point (`W8bRelinkRuns.EveryStopPoint`, the mac's `everyStopPoint(swaps:)`), killed, then recovered by a second process. One line per kill (`shape work point: WHOLE|NOT-WHOLE <states>`): WHOLE is the snapshot (section 1 and the folder outside, every link's whole target as text, never followed, 84c7f53be) exactly before or exactly after, nothing staged (`.plantoir-undo-`), and the step settled on that side (after: done; before: failed or rolled back for an apply, undone for an Undo or Redo). The reached count is checked against the mac's formula per shape and work (apply 2 + swaps + 2 x relinks; Undo, Redo 3 + swaps + 2 x relinks) and the run ends with the counts by shape and the done line.
  - A control per shape (inside): the after state with one link given `.\` in front of its text (another text leading to the same page) must read as neither (CAUGHT).
  - The teacher's rows: on `twoChainedRelinks`, while the child is parked at `beforeSwap@0`, a teacher's page (`Teacher's own.`) or link (`Someone's.md`) is laid under the relink's staged `-new` name (label `1-apply`, `1-undo`, `1-redo`) beside Day 6 and Day 5 going forward, Day 4 and Day 5 going back; then the kill and recovery. KEPT is: found exactly once, under a visible name, not Hidden, nothing staged, Day 1 and Day 2 untouched. 12 rows.
- `W8bRuns`: `Snapshot` reads a link through one function (`LinkReading`, its text; `Followed` is the must-fail's following reading), `Staged`, `Child` (with `beforeTheKill`) and `StopAt` (a point without `@` asks index -1) are shared with the new runs.
- **A product fix the kill table proved (the director's brief allowed it; test first, must-fail row).** The first run's teacher's rows: a teacher's page under a relink's staged name beside Day 5 (named by two relinks) was DELETED in all three ways (`NOT-KEPT at=[]`), because `UndoStagedLinks` counted the second relink as "another op naming the place" (a handed-over place), so `UndoSwap.WhoseIsIt` judged the page by its kind and the tidy removed it as a staged copy. Another link's move (a chained relink, a plain link move) stages only links, never a page, so it no longer shares the place (`NamedByAnotherOp` passes over `IsALinksMove` ops); a page there is the teacher's: given back or kept visibly. A file op still shares it, so the director's shape keeps Undo's own staged page by its kind.
- **The director's question, answered: Windows did not have the mac's fault.** `WhoseIsIt` never applied the relink's rule to a staged name beside a place a page op also names (`alone` false: judged by its kind), so Undo's own staged page beside the relink's `from` is removed as a staged copy, never renamed to "(kept by Undo)" nor said. The harness's `aRelinkFromADayANewPageFills` rows are whole at every stop point, and `UndosOwnStagedPageBesideARelinksPlaceIsNeverKeptAsTheTeachers` pins it (green before and after the fix).
- `UndoRelinkTests`: `APageUnderAStagedNameBesideAPlaceOnlyLinkMovesNameIsTheTeachers` (two rows: a second relink, a plain link move), `UndosOwnStagedPageBesideARelinksPlaceIsNeverKeptAsTheTeachers`.

## For documentation 12

Windows' relink kill table (W8b-21b4) is the mac's review F table and review G's five probes, shape for shape, killed in a real child process; on the PC 532 of 532 kills whole (266 with the links inside, 266 with one leading out), every control caught, the 12 teacher's rows kept (run w8b-21b4-b). Add to 21b3's paragraph on `UndoSwap.WhoseIsIt`: a place that only link moves name (chained relinks, a plain link move) is the relink's alone, because a link's move never stages a page; only a file op naming the place makes it shared, and there a staged file is judged by its kind (Undo's own staged page beside a relink's `from`, the mac's sister-piece fault, which Windows never had).

## Must-fail lines

`vm-tools/guest/899-w8b-21b4-mustfail.json` (harness rows, mode `hmustfail`) and `899-w8b-21b4-mustfail-classes.json` (the fix's class row):

1. review D's rule (the FIRST relink that passes, `break` after the first), in the harness: **NOT-RED**, whole 40 of 40 on the two move-chained shapes (w8b-21b4-b) and 108 of 108 on `threeChainedRelinks`, `fourChainedRelinks`, `relinkMoveRelink` (w8b-21b4-c). (Corrected by window E review 2, LOW 1: the explanation first written here, that a real kill can never show the rule, was untrue. 21b3's `AKilledChainRemovesExactlyTheOneLinkTheRuleNames` stops the real door at real stop points and turned 5 rows red under the same rule. The harness missed it for two reasons: its WHOLE accepted either settled side, so a kill settling on the other side but whole read green; and row 1 never ran on `twoChainedRelinks`, the shape of the red rows. Both are fixed below, and row 1 on `twoChainedRelinks` is red there.) The brief's "as the mac's did (9 of 40)" is the mac's second sabotage: review G part 3's 9 kills come from 113b1c77f's rule, which read relinks only. Review D's first-not-last stays caught by the hand-made states of 21b3's `AKilledChainRemovesExactlyTheOneLinkTheRuleNames` (21b3 must-fail 1, 5 of 100).
2. plain link moves left out of the reading (`IsARelink` for `IsALinksMove`), in the harness: **RED, 9 of 40** move-chained kills NOT-WHOLE (w8b-21b4-b), the same nine as the mac's (review G part 3), each `Interrupted`, state NEITHER: `aMoveThenARelinkIntoItsPlace` apply `afterBegin` and `beforeSwap@0`, undo `beforeUndone`, redo `afterRedoing` and `beforeSwap@0`; `aRelinkThenAMoveIntoItsPlace` apply `beforeApplied`, undo `afterUndoing` and `beforeSwap@0`, redo `beforeRedone`.
3. the snapshot following links (`LinkReading` as `Followed`), in the harness: **RED**, the control on `twoChainedRelinks` NOT-CAUGHT (a link given `.\` before its text read as the after state), 26 kills otherwise whole.
4. another link's move counted as sharing a relink's place (the fix reverted), in the classes: **RED, 2 of 2** (`APageUnderAStagedNameBesideAPlaceOnlyLinkMovesNameIsTheTeachers`, both rows, `FileNotFoundException` for Day 5: the teacher's page deleted).

RED 3 of 4 (row 1 NOT-RED, explained above); restored 407 of 407, HEAD-AFTER same, status clean.

## Runs

All on the PC (LENOVO 20QES70500, Intel Core i5-8365U, 16 GB, Windows 11 Pro 26200), outside OneDrive, each under the turn lock, taken when free and released by its own run.

- w8b-21b4-a (ref 5e507fc8e, 08:53 to 08:59): both builds 0 errors; the six classes 404 of 404; harness part `in` with the teacher's rows: 266 of 266 kills whole, every control caught, **3 teacher's rows NOT-KEPT** (a page under the staged name beside Day 5, apply, undo and redo: deleted, `at=[]`). That is the kill that proved the fix.
- w8b-21b4-b (ref a94d01639, red ref 0233ca6f1; 09:01 to 09:13): tests first RED 2 of 82 (`UndoRelinkTests`, the new theory's two rows); both builds 0 errors; the six classes (`UndoRelinkTests`, `UndoRecoveryContractTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`) **407 of 407**; classes must-fail RED 1 of 1, restored 407 of 407; harness **part 1 (`in`, teacher's rows), 3 min 13 s: 266 of 266 whole, 10 of 10 controls caught, 12 of 12 teacher's rows kept, failures 0; part 2 (`out`), 3 min 10 s: 266 of 266 whole, failures 0**; harness must-fail rows 1 to 3 as above.
- w8b-21b4-c (ref a94d01639, 09:14 to 09:23): harness must-fail row 1 on the chained-relink shapes, NOT-RED 0 of 108.

The teacher's rows, each found once, visible, not Hidden, nothing staged, Day 1 and Day 2 untouched: beside Day 6 (apply, redo) and Day 4 (undo), a place only one relink names, the item is given back into that free place (the step then closes `Interrupted`, a teacher's item standing where the step's link would go); beside Day 5, which the other relink's link holds, it is kept as `Unit 1, Day 5 (kept by Undo).md` (step `Failed`, `Done` or `Undone` as its links show).

## Kill counts, Windows beside the mac

Windows' stop points have the mac's names: `afterBegin`, `afterTheCheck`, `afterUndoing`, `afterRedoing`, each `beforeSwap@N`, `relinkStaged@N`, `relinkRenamedIn@N`, `beforeApplied`, `beforeUndone`, `beforeRedone`, `whileDeletingAFolder` (the mac's `UndoKillPoint` cases: the same list, `.beforeSwap(N)` written `beforeSwap@N`). Each is asked of every kill; `whileDeletingAFolder` is never reached (no step here deletes a folder), as on the mac.

| Shape | Windows, in | Windows, out | Mac |
|---|---|---|---|
| twoChainedRelinks | 26 of 26 | 26 of 26 | 26 (review F table) |
| threeChainedRelinks | 35 of 35 | 35 of 35 | 35 |
| aMoveThenARelinkIntoItsPlace | 20 of 20 | 20 of 20 | 20 |
| aRelinkThenAMoveIntoItsPlace | 20 of 20 | 20 of 20 | 20 |
| fourChainedRelinks | 44 of 44 | 44 of 44 | 44 (review G probe) |
| moveRelinkMove | 23 of 23 | 23 of 23 | 23 |
| relinkMoveRelink | 29 of 29 | 29 of 29 | 29 |
| twoRelinksWithTheSameTexts | 26 of 26 | 26 of 26 | 26 |
| twoMovesThenARelink | 23 of 23 | 23 of 23 | 23 |
| aRelinkFromADayANewPageFills | 20 of 20 | 20 of 20 | (the mac's sister piece: 12 kills there) |

Mac table 101 (61 relink, 40 move), review G 145; Windows 266 per lead, 532 in all, every one whole. "x of y" is reached of expected by the mac's formula, so every stop point the mac reaches Windows reaches too, and no other.

## Ledger

No row. `NamedGapLedgerTests` run, green.

## Self-check

1 to 6 (NIGHT3): own classes only on the PC under the turn lock, no UI class, no whole suite; the fix's tests first in their own commit (0233ca6f1), seen red; must-fail recorded; notes written. 7 to 10: no fixture row; writer-scan count unchanged (no writing call added), `UndoWriterScanTests` green; no riding lows; no action step. 11 and 12: no held row, no key added. 13: one function per rule: `UndoSwap.WhoseIsIt`/`UndoStagedLinks` for "is this ours" (the fix is inside it), `UndoOp.IsALinksMove` for "is this a link's move", `UndoLinks.Look` for "is this a link", the harness's `LinkReading` for every snapshot's link. 14: no run left going, the lock taken only when free and released by its own run.

## Left for the next piece

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- 21b5: `UndoActionStep.RelinkLink`.

## For the director

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- The fix touches 21b3's `UndoStagedLinks` (one line and its summary); the mac's `isOurs` should be checked for the same thing: a page under a relink's staged name beside a place only link moves name.
- No lock was removed that this piece did not take.

## Window E review 2 lows

Brief `vm-tools/briefs/2026-11-27-899-w8b-window-e-review-2.md` (CLEAN, five LOWs). `origin/dev` 454ef4c6f was already in the branch, so there was no merge and `NamedGapLedger.cs` was not touched. No `contracts/` or `mac-app/` change.

- **LOW 2, the kill table re-run on the final review-1 code** (run w8b-wer2-a, ref 62382c2dd, 10:29 to 10:36). Part 1 (`in`, teacher's rows): 266 of 266 whole, 10 of 10 controls caught, 13 of 13 teacher's rows kept (21b4's 12 and review 1's `aRelinkIntoADayAPageLeaves` row), failures 0. Part 2 (`out`): 266 of 266 whole, failures 0. So all 532 kills are whole and every shape reaches the mac's count.
- **LOW 1, the harness now says which side each kill settles to.** `W8bRelinkRuns.MustSettleTo` covers `twoChainedRelinks`, `threeChainedRelinks` and `fourChainedRelinks`. A kill there is WHOLE only if it settles to the exact side and phase the rule names:
  - an apply goes back to before. It is `Failed` while no swap has renamed anything in (afterBegin, beforeSwap@0, relinkStaged@0) and `RolledBack` after that;
  - an Undo goes back to after (`Done`);
  - a Redo goes back to before (`Undone`);
  - a kill at the work's close (beforeApplied, beforeUndone, beforeRedone) is finished.
  These agree with 21b3's rows for the same chain, and with all 210 kills of those three shapes in w8b-wer2-a, both leads. The other shapes still accept either settled side. In three of them, an apply killed at relinkRenamedIn@0 settles `Failed`, not `RolledBack`, so the rule does not carry over to them unchanged. Must-fail row 1 (review D's first-that-passes, `break` after the first) was run on `twoChainedRelinks`: see the run below. The correction to row 1's explanation is written in place above.
- **LOW 4:** four test sentences no longer name the VMs as machines that cannot make links. Two are the ones the review named (`UndoLinkCopyTests`, `UndoLinkMoveTests`); two more said the same thing (`UndoCheckContractTests`, `UndoStackContractTests`). All four now say "a machine that cannot make links".
- **LOW 5, a junction relinked.** A junction can be made only through `DeviceIoControl` (`FSCTL_SET_REPARSE_POINT`), and the piece makes links only with `CreateSymbolicLink`. As briefed, no second mechanism was built: a relink of a junction is refused before anything changes, at two points:
  - `UndoActionStep.RelinkLink`, when the step is planned;
  - `UndoSwap.RelinkLink`, for an Undo or Redo that meets one.
  The refusal is `couldNotWrite`, the reason the swap already gives for any link it cannot make (1314). Its sentence ("the disk may be full, or Plantoir may not have permission to write there") names neither real cause. No truer reason exists in the contract, so the wording is for the director to decide (piece 22, where Insert Class first calls this).
  - The check is `UndoLinks.IsAJunction`: the link test `Look`, plus the mount-point reparse tag.
  - Tests: `AJunctionIsNeverRelinkedAsASymbolicLink` and `ARelinkOfAJunctionIsRefusedWhenPlanned`. Both were red first on 6bc055127, 2 of 2: line 741 failed because the swap re-made the junction as a symbolic link, and line 766 failed because no refusal was thrown.
- **LOW 3, left for piece 22.** Windows refuses a write at `to` that was planned BEFORE a two-place relink. The Mac refuses one only where the link stands (`from` is `to`), so Windows is the stricter of the two. Nothing calls `RelinkLink` until 22a. Record the difference in documentation 12, or make the two platforms agree there.
- **Run w8b-wer2-b** (PC: LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200; ref 0c25650eb, red ref 6bc055127; 10:36 to 10:50, under the turn lock, taken when free and released by this run).
  - Tests first: RED 2 of 2.
  - Both builds: 0 errors.
  - `~Plantoir.Tests.Undo`, `NamedGapLedgerTests` and `~Plantoir.Tests.ActivityTrail`: **1583 passed of 1584**, 1 skipped, 0 failed.
  - Classes must-fail: RED 2 of 2. Row 1, the swap's junction refusal removed, fails with `Swapped`. Row 2, the planned refusal removed, fails because no exception was thrown. Restored: 1583 of 1584.
  - Harness part `in` (teacher's rows): 266 of 266 whole, 10 of 10 controls caught, 13 of 13 kept. Part `out`: 266 of 266 whole. Failures 0.
  - Harness must-fail row 1 (review D's first-that-passes) on `twoChainedRelinks`: **RED, 2 of 26 NOT-WHOLE**. The apply at relinkRenamedIn@0 and the apply at relinkRenamedIn@1 both settle `Failed` where the rule names `RolledBack` (`mustSettle=before/RolledBack`). The disk was whole, so the old either-side check read both kills as green.
  - Must-fail files: `vm-tools/guest/899-w8b-window-e-review-2-mustfail.json` and `-mustfail-classes.json`. HEAD-AFTER same, status clean.
