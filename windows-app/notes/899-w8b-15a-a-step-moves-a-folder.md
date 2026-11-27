# #899 W8b-15a: an action step moves a folder through the door (Windows #949)

Branch `issue/899-w8b-15a-a-step-moves-a-folder`, built on `origin/day27/integration-3` (d32d22bda: `dev` plus Mac U4b3, W8 pieces 9 to 14 and #1048). `origin/dev` (4f228c923) is already in the base, so no merge commit was needed; checked again before hand-back.

## What landed

- `UndoActionStep.MoveFolder(fromFull, toFull)` plans ONE `move` op `{from, to, listingSha}` (the mac's `JournaledStep.moveFolder`, U4b). The listing hash is taken when planned, from `UndoTreeReading.Read(from).ListingSha`. That is the same listing text `UndoMoveSides` judges with, so there is one listing function. No blob is added for the listing.
- `PlaceOnDiskNow` (private; the mac's `placeOnDiskNow`): a place at or inside a planned move's `to` is read under its `from`. "At or inside" is `UndoOp.PartInside`, applied to the full paths with `/` separators. `Write`, `WriteBytes`, `Remove`, `EditJson`'s folder test, `Exists`, `ReadText` and `ReadTextIfAny` read through it. Every file is still NAMED at the place given, which is the new place. The door reads such a file as carried (`UndoOp.MoveCarries`). `RecordableChanges` looks for a link at the disk place.
- **Ops order** (only in a step that moves a folder): every folder move first, in the order planned. Then the files planned whole, in the one page order. Then the files planned member by member (`editJSON`), in the order planned. Then trees and recomputes, as before. The one page order is `UndoActionStep.ComparePageOrder`: the path lowercased with `ToLowerInvariant` and compared ordinally, then, on a tie, the UTF-8 bytes as spelled. A step with no folder move keeps the order it had (planned order, members in place), so Set School Year, Save Course Settings and Add folder record as before.
- `pageCount` counts each folder move, as the mac's `changedFiles` does.
- **Refusals at plan time.** `MoveFolder` refuses with `cannotTellNow` and changes nothing in three cases:
  - a folder that is a link (`UndoLinks.Look`; W8b-21 owns moving a link);
  - a place that cannot be looked at;
  - a folder that cannot be listed now. This includes a folder with a link inside it, which `UndoTreeReading` reads as `NotATree`.

  The mac's `moveFolder` returns false in these cases instead of throwing. The Windows caller (15b) gets the refusal as an exception, with "“media” could not be read just now." as its words.
- **Unrecorded** (no working folder, or in shadow when the list cannot take the step):
  - `WritePlainlyQuietly` puts each folder move first as the swap's own `UndoSwapChange.MoveHere`. That is the rename the door's swap makes: `MoveFileEx` without `MOVEFILE_REPLACE_EXISTING`, with the listing judged again just before it.
  - Each file inside a moved folder is then a target at its new place, staged at its turn (`StagesAtItsTurn`).
  - `Directory.Move` is never used.
- **One function per rule.**
  - At or inside: `UndoOp.PartInside`, in `PlaceOnDiskNow` and, inside the swap, in `FollowTheMove`.
  - The listing hash: `UndoTreeReading` / `UndoTreeListing.Sha`.
  - A link: `UndoLinks.Look`.
  - Page order: `ComparePageOrder`.
- No writing call was added outside the door. The plain move goes through `UndoSwap.Swap` → `SwapAWholeOp` → `RenameWithRetries`, so `UndoWriterScanTests.Allowed` is unchanged.

## For PROGRESS

- W8b-15a: `UndoActionStep` can move a folder as one `move` by `listingSha`, with its pages read at the old place and named at the new one (`MoveFolder`, `ComparePageOrder`). Nothing calls it yet but `UndoActionStepFolderMoveTests`. Rename folder itself is 15b.

## For documentation 12

- In "What W8 owes from U4b2-11": the one page order now has a Windows function, `UndoActionStep.ComparePageOrder`. The step applies it itself whenever it moves a folder. On the Mac the caller sorts (`ClassPages.isInPathOrder`). On Windows the step sorts, so 15b must not sort a second time by another rule.
- A case-only tie (`B.md` beside `b.md`) cannot be two pages on an ordinary NTFS folder: the step keys files without regard to case, and the volume takes the two names for one file. The tie-break is therefore pinned on the function (`TheOnePageOrderIsTheLowercasedPathThenTheBytesAsSpelled`), not through a step.

## Must-fail lines

`vm-tools/guest/899-w8b-15a-mustfail.json`, run in `w8b-15a-mf` (see "Runs"):

Run in `w8b-15a-d` on c2ac95582: **5 RED of 5**, and restored at 298 of 298.

1. The listing taken at make time instead of plan time. RED in `AFolderEditedByHandBetweenThePlanAndTheMakeRefusesTheStepAndNothingChanges`, line 194: no exception was thrown, and the move went ahead over the hand edit.
2. A page inside the folder named at the OLD place. RED in `AFolderMoveAndAnEditInsideItAreOneStepNamedAtTheNewPlaceAndUndoneAndRedoneByteForByte`, line 108: the door refused the step ("a page could not be saved").
3. The pages in the order planned, not the one page order. RED in `TwoFoldersMoveFirstThenThePagesInTheOnePageOrderThenTheMembersAsPlanned`, line 161: the op list differs at position 2.
4. `FileAttributes.ReparsePoint` in place of `UndoLinks.Look`. RED in `AFolderGoneBeforeThePlanIsRefusedCannotTellNowAndNothingChanges`, line 236: `File.GetAttributes` throws on a folder that is gone, where `Look` answers Nothing. The OneDrive-like case, a reparse point that is not a link, could not be tested on the PC. Measured in `w8b-15a-b` and `w8b-15a-c`: a folder carrying tag 0x80000013 without its filter cannot hold a file and cannot be listed.
5. The plain path using `Directory.Move`. RED in `UnrecordedAFolderEditedByHandBetweenThePlanAndTheMakeIsRefusedAndNothingChanges`, line 280: no exception was thrown, and the folder moved over the hand edit.

## Runs

- `w8b-15a-a` (720c301fd): the test project did not compile. The cause is in the base: `NamedGapLedger.cs(474)` held unescaped `"Never refuse"` (from U4b3, 850fd1c4d). Fixed in its own commit, 8c36fdf20, which changes those two quotes only.
- `w8b-15a-b` (8c36fdf20): 294 of 298. Three tests failed on the door's own `courses/.internal/folder-id` appearing in the tree, and one on the reparse tag. Both were test faults, fixed in eade137af.
- `w8b-15a-c` (eade137af): 297 of 298. A folder with the tag cannot be listed, so that test was replaced by the gone-folder test in c2ac95582.
- `w8b-15a-d` (c2ac95582): both builds 0 errors. **298 passed of 298**, 0 skipped (the symbolic-link test ran). The run covered `UndoActionStepFolderMoveTests` (7), `UndoActionStepTests`, `UndoDoorTests`, `UndoSwapTests`, `NamedGapLedgerTests` and the three scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests`. Must-fail: 5 RED of 5; restored at 298 of 298.
- Lock: each run's own script took and released it. `w8b-15a-c` waited behind the director's `int-d27-4`. I removed no lock that was not mine.

## Left for the next piece

- 15b: call `MoveFolder` for each folder Rename folder moves. Then plan each relinked page at its NEW place, and course_config.json member by member (`EditJson`). The step orders them itself.

## For the director

- Tests first: `b2f406b69` (the tests) comes before `720c301fd` (the product). The new tests did not compile on the product as it was, because `MoveFolder` and `ComparePageOrder` did not exist. Their red is the must-fail rows, as in W8-14.
- Parked: nothing.
- The base did not compile on Windows (`NamedGapLedger.cs:474`, unescaped quotes). The fix is 8c36fdf20, the same as the integration tree's.
- My mistake: a `git commit -a` in `vm-tools` (0141462) also committed and pushed three uncommitted edits from other sessions: `briefs/2026-11-25-899-w7b2-1-make-room.md`, `guest/899-w7b2-4-mustfail.json` and `pc-suite-when-free.sh`. Their contents are as their authors left them. Only the commit they sit in is mine.
- Ledger: no row moved. `NamedGapLedgerTests` is green.
- Self-check:
  - 11: no row was named.
  - 12: I added no key.
  - 13: the at-or-inside comparison is `UndoOp.PartInside`, the listing is `UndoTreeReading`, the link test is `UndoLinks.Look`, and the page order is `ComparePageOrder`.
  - 14: no run is going, no lock is held, and I removed none that was not mine.
