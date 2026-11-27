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

1. review D's rule (the FIRST relink that passes, `break` after the first), in the harness: **NOT-RED**, whole 40 of 40 on the two move-chained shapes (w8b-21b4-b) and 108 of 108 on `threeChainedRelinks`, `fourChainedRelinks`, `relinkMoveRelink` (w8b-21b4-c). Explained, not a weakness of the table: a real kill never leaves two relinks passing at once (review G part 1: at a boundary between swaps none can pass; inside a relink only the one in flight has both links standing and its neighbours consistent), so the first and the last that pass are the same one in every state a process can die in. The brief's "as the mac's did (9 of 40)" is the mac's second sabotage: review G part 3's 9 kills come from 113b1c77f's rule, which read relinks only. Review D's first-not-last stays caught by the hand-made states of 21b3's `AKilledChainRemovesExactlyTheOneLinkTheRuleNames` (21b3 must-fail 1, 5 of 100).
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

- 21b5: `UndoActionStep.RelinkLink`.

## For the director

- The fix touches 21b3's `UndoStagedLinks` (one line and its summary); the mac's `isOurs` should be checked for the same thing: a page under a relink's staged name beside a place only link moves name.
- No lock was removed that this piece did not take.
