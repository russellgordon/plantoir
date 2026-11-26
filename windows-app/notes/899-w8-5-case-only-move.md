# #899 W8-5: a capitalisation-only move (Windows #949), 2026-11-26

Base: `origin/issue/899-w8-4-made-folders-left-out` at d940a6a7a, which holds `origin/dev` 461ee3943. `origin/dev` had not moved when this piece was proven or handed back (461ee3943 both times), so there is no merge commit: dev is already in at the base.

## For PROGRESS

- A capitalisation-only move (`opKinds.move`: `from` and `to` spelled alike but for case, in the last part only, `Media` to `media`) is readable on Windows. `UndoOp.IsCaseOnlyMove` says so. It is built on `UndoOp.PartInside`, which must give "" (the same place, part by part, without regard to case). The parts above the last must then be the same as spelled, and the two must not be one spelling. `UndoFormat.ShapeIsKnown` lets only such a pair through the overlap refusal. A case difference above the last part, or the same spelling twice, stays not readable.
- **The check.** `UndoCheck.WholeStateOf` judges such a move by the spelling the parent folder lists, through `UndoMoveSides.SpellingListed`. When both spellings are one item (the same `UndoFileIdentity.OfPlace`, the volume serial and file index of the place itself, a link never followed), it lists the parent and finds the entry by the item's own part without regard to case. It then tells `to` and `from` apart as spelled. Any other spelling, or no entry, is `Another`, which counts as changed since both ways. When the spellings are not one item, the move is judged as any move. The plan's override sets for such a move (the carried edits taken back, and the step's own staged and kept files) are one set, used for whichever spelling is listed, as on the Mac.
- **The swap.** The swap's last look renames only while the folder lists the spelling it leaves: `From` counts as free, `To` or `Another` as something else, and `CannotRead` as cannot tell. It renames in ONE `MoveFileEx` without `MOVEFILE_REPLACE_EXISTING`.
- **The carried edit.** `UndoOp.MoveCarries` tells the two spellings apart by the moved item's own part alone, as spelled, and the parts above it by `PartInside`. So an edit named `courses/tst1o/media/a.md` is carried by `Media` to `media`, and one named at `courses/TST1O/Media/a.md` is not (it is a barrier).
- A new test seam, `UndoSeams.EachRename`, is called before each rename the swap tries. Nothing in the app sets it.

## For documentation 12

Under "What W8 owes from U4b2-9", the case-only rows are done on Windows (W8-5):

- **Measured on the PC** (NTFS, `C:\vm-setup`, 2026-11-26):
  - `MoveFileExW(Media, media, MOVEFILE_WRITE_THROUGH)` without `MOVEFILE_REPLACE_EXISTING` answers 0, and the parent then lists `media` (`Directory.EnumerateFileSystemEntries`). The same holds for a file (`Page.md` to `page.md`).
  - The same call again, once the folder already lists `media`, ALSO answers 0. That is why the swap decides by the listing and never by the rename's answer.
  - Onto a different item that is there, it answers 183 and replaces nothing.
  - One item: both spellings open (no access, `FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT`) to the same `GetFileInformationByHandle` identity: `8a81f26a:017f00000023b811` for the folder and `8a81f26a:044100000023b824` for the file, before and after the rename.
  - So the parked question ("MoveFileExW refusing a case-only rename") does not arise.
- **Rejected:**
  - Judging "one item" by `Directory.Exists` at both spellings. A case-sensitive folder (`fsutil file setCaseSensitiveInfo`) holds two items, and both would exist. The identity tells the two cases apart, as the Mac's device and inode do.
  - Two renames through a third name. They are not needed (the measurement), and a crash between them leaves a third spelling.

## Must-fail lines

`vm-tools/guest/899-w8-5-mustfail.json`, run on the PC at 9f36ac049 (`899-w8-5-mf`): **5 RED of 5**. Restored afterwards: 571 passed. HEAD-AFTER SAME, status clean, `LOCK-RELEASED`.

1. Every case-only pair refused again (`ShapeIsKnown` without `&& !op.IsCaseOnlyMove`): 9 failed. The first is `UndoCaseOnlyMoveTests.cs:170` (`AnEditNamedAtTheOldSpellingIsNotCarried`, `move.Readable`); `ACaseOnlyMoveInTheLastPartIsReadable` fails at line 78.
2. Judged by `to`, not by the spelling listed (`SpellingListed` answers `To` for any entry): 4 failed. These are the case-only `EveryCheckCase` rows (`UndoCheckContractTests.cs:203`) and the stack rows.
3. `listedAs` ignored by the replay (atTo laid at `to`): 1 failed, the third-spelling `EveryCheckCase` row (`UndoCheckContractTests.cs:203`).
4. The own part compared without regard to case (`MoveCarries`, `OrdinalIgnoreCase`): 5 failed. The first is `UndoCaseOnlyMoveTests.cs:171` (the `from`-spelled edit was carried); the carrying test fails at line 133, and the stack rows fail too.
5. A rename through a third name (`Media` to `Media.case` to `media`): 1 failed, `UndoCaseOnlyMoveTests.cs:149`, the one-rename assertion (`[("media", "Media")]`).

## Runs

All runs were on the PC, under `C:\vm-setup\wt-compare.lock`, with the brief's seven classes (`UndoCaseOnlyMoveTests`, `UndoCarryingMoveTests`, `UndoCheckContractTests`, `UndoStackContractTests`, `UndoFormatTests`, `UndoSwapTests`, `NamedGapLedgerTests`). Both builds answered 0.

- `899-w8-5-measure`: a scratch PowerShell script outside the tree. Its numbers are above.
- `899-w8-5-red` (ref 91b78e903: the tests, the replay and the ledger, on the product as it was, with only the seam added): **12 failed of 571**. The failures:
  - the four case-only `checkCases` rows (each `notReadable`);
  - the three U4b case-only `stackCases`;
  - `ACaseOnlyMoveInTheLastPartIsReadable` (3 cases, `Assert.True(Op(...).Readable)`);
  - `AnEditNamedAtTheOldSpellingIsNotCarried` (`Assert.True(move.Readable)`, its first assertion);
  - `ACaseOnlyMoveCarryingAnEditInsideIsUndoneAndRedoneAndItsKeptOriginalFollowed` (the step is not readable, so `Perform` does not apply it).

  These passed then, as guards: the measured rename and `ACaseDifferenceAboveTheLastPartStaysNotReadable`.
- `899-w8-5-green` (ref 9f36ac049): **571 passed, 0 failed**. HEAD-AFTER SAME, status clean, `LOCK-RELEASED`. This is the head proven; the notes commit after it changes no code.
- `899-w8-5-mf` (ref 9f36ac049): the must-fail run above.

## Left for the next piece

- A case-only rename of a folder that is a link: no row yet (U4b2-15's "Left"), not in scope.
- Recovery of a case-only move killed part way: no `recoveryCases` row names one. Recovery's put-back reaches `WholeStateOf`, and so the listing rule, through `UndoCheck.Plan`, but nothing proves it.

## For the director

No parked questions. No `contracts/` change.

### Self-check

1 to 6 (NIGHT3-COMMON):
- One branch, small commits with `#899`, pushed with `gpush.sh`.
- Tests were red first (`899-w8-5-red`, 12).
- No timed waits, no interim states, nothing a teacher sees.
- Only `windows-app/` changed.
- Both builds 0.
- Only the brief's classes were run.

7. The ledger rows are gone, and `Reason899W8U4b` is rewritten: the case-only clause moved from "still owed" to "since W8-5". No other reason named `caseOnlyFolder`, `listedAs` or the two calls (checked by grep).
8. The writer scan is unchanged. No writing call moved into or out of the door.
9. There were no riding lows.
10. The step's order is kept (the move first going forward, the carried edit before it going back). Every before is read at plan time, as for any carrying move.
11. The four `UndoCheckCases` and three `UndoStackCases` rows pass and are out of the ledger. The reason constant is still used by other rows.
12. The key `caseOnlyFolder` was added to `KeysChecked`. No row still held carries it, or `listedAs`.
13. One function per rule:
    - "alike but for case" and "at or inside" are `UndoOp.PartInside` (in `IsCaseOnlyMove` and `SpellingListed`'s entry match);
    - "one item" is `UndoFileIdentity.OfPlace`;
    - the spelling listed is `UndoMoveSides.SpellingListed`, used by both the check and the swap.
14. No run is left going, every lock was released by its own run (`owner.txt` checked by the script), and no other lock was touched.
