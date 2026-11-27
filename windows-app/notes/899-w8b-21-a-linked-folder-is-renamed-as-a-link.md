Removed by #1055 (2026-11-27): symbolic links in course content are not supported; no link is moved as itself.

# #899 W8b-21: a linked folder is renamed as a link (Windows #949)

Branch `issue/899-w8b-21-a-linked-folder-is-renamed-as-a-link`, built on W8b-16's `origin/issue/899-w8b-16-trace-replay-lays-folder-moves` (08aa0bcf6; pieces 15a, 15b and 16, with `origin/dev` 8046ca2e8 merged in), as the director's prompt said (the brief named 15b's branch). `origin/dev` was still 8046ca2e8 at both merge points ("Already up to date" before proving, at a1c8e9e6e, and again before hand-back), so there is no merge commit.

## What landed

- `UndoActionStep.MoveLink(fromFull, toFull)` (the mac's `JournaledStep.moveLink`): plans ONE `move {from, to, linkSha}`, `linkSha` read at plan time by `UndoLinks.LinkSha` (the stored `LinkTarget` as UTF-8, unchanged), never followed. General: a junction, a folder symbolic link or a file symbolic link. A place that is not a link now (`UndoLinks.Look`), or a link whose target cannot be read, refuses `cannotTellNow` before anything changes.
  - It shares the planned-move list with `MoveFolder` (each entry has exactly one of `ListingSha`, `LinkSha`), so the step puts every move first, counts it in `pageCount`, and re-sorts the pages, as for a folder move.
  - `RecordableFolderMoves` names the link's own place (`RelativeOf`, a string relative path, never resolved) and asks `UndoPlaces.FirstPlaceLeadingOut` of the op, so only the folder above a link's move is resolved (W8-6's `StaysInside(root, relative, op)`): a link leading out of the working folder, or nowhere, is recorded like any other.
  - Unrecorded (`WritePlainlyQuietly`) the link is moved by the swap's own `MoveHere` with the same op, so `MoveFileEx` without replace, judged by `linkSha` again.
  - `PlaceOnDiskNow` never maps through a link's move (the mac's maps through every move): reading a place at or inside a link's `to` from its `from` would read what the link leads to. A link's move carries nothing, so nothing should ask.
- `SpecialFolderRenamer`:
  - `IsAPlaceToMove`: a folder, or a place that cannot be looked at, as before; a link (`UndoLinks.Look`) is a place to move when it is a link to a folder by its OWN attributes (`UndoLinks.IsALinkToAFolder`, the new one function: `File.GetAttributes` of the link, `Directory`, never followed, so a link to a folder leading nowhere is still one), or when its target cannot be read (then `MoveLink` refuses `cannotTellNow`). A link to a file is skipped, as a file at the place is.
  - `Rename` plans `MoveLink` for a place `UndoLinks.Look` calls a link, `MoveFolder` otherwise. 15b's walk (`descendsIntoLinks: false`) is unchanged, so no page under the link is relinked.
- `UndoStackContractTests.StackReplay` learns `renameAPerSectionFolderThatIsALink`: it lays W8-6's link fixture (`LayTheLinkToTheLibrary`, now shared with `moveALinkToAFolder`), runs `SpecialFolderRenamer.Rename("media", "renamed", PerSection, courses/TST1O, [1])` on the scribe's live door, clears the rename record as the sheet does, and asserts the one step is exactly `moveALinkToAFolder`'s op (kind, from, to, linkSha, no listingSha). Its rows run under `SymbolicLinkTheory` (`LaysASymbolicLink` now names both calls), so they skip by name where Developer Mode is off.
- Ledger: the two "U4b2-15, …" rows pass and are gone; `Reason899W8U4b2LinkedFolder` is gone (no row used it). No other reason sentence named the call or the linked-place stop (checked: `Reason899W8HandedOverPlace`, `Reason899W8bLinkedClassPage`, `Reason899W8RelinkedLink`).

## For PROGRESS

- W8b-21: Rename folder renames a per-section or shared place of the folder that is a link to a folder (a junction or symbolic link) by moving the LINK as one op of its one step (`move` with `linkSha`, `UndoActionStep.MoveLink`), never what it leads to, wherever it leads (inside the course, outside the working folder, nowhere). A link whose target cannot be read refuses the rename `cannotTellNow`; a link to a file is skipped. The two U4b2-15 stack rows pass.

## For documentation 12

- "What W8 owes from U4b2-15": built in W8b-21 (`UndoActionStep.MoveLink`, `SpecialFolderRenamer.IsAPlaceToMove` and `Rename`). Its "Windows today" bullet is history now: `Directory.Move` and `Directory.Exists` are gone (W8b-15b), and a link is moved by `MoveFileEx` through the swap.
- In the same section, "Pages": the walk skips an entry `UndoLinks.Look` calls a link, never `FileAttributes.ReparsePoint` (W8b-15b's note asked for this correction too).
- New fact: on Windows "a link to a folder" is told by the link's own `Directory` attribute (a junction, or a symbolic link made with `Directory.CreateSymbolicLink`/`mklink /D`), without following it. The mac tells it by following (`fileExists(atPath:isDirectory:)`), see "For the director".

## Tests that failed first

Run `w8b-21-a`, red ref 5e86468cd (the tests, with `MoveLink` a stub that refuses as `MoveFolder` does): **11 failed of 179** (`UndoRenameFolderStepTests`, `UndoActionStepFolderMoveTests`, `UndoStackContractTests`, `NamedGapLedgerTests`):

- `UndoActionStepFolderMoveTests`: `ALinkToAFolderIsOneMoveByItsLinkSha…`, `ALinkToAFileIsMovedAsItself…`, `UnrecordedALinkIsMovedAsItself…` (each refused `cannotTellNow` at `MoveLink`).
- `UndoRenameFolderStepTests`: the junction, the relative symbolic link, the symbolic link leading out (15b's test turned round), the junction leading out, the junction leading nowhere (each a `RenameException` "could not be read just now"), and `ALinkToAFileAtThePlaceIsSkippedAsAFileIs` (the file link reached `MoveFolder` and was refused).
- `UndoStackContractTests.EveryLinkStackCase`: the two U4b2-15 rows (no longer held; the rename refused the link's place).
- Passed there as guards: `ALinkWhoseTargetCannotBeRead…` in both classes (red only under must-fail 1), and `APlaceThatIsAOneDriveStylePlaceholderIsMovedAsTheFolderItIs`, added after the product (commit a1c8e9e6e) as must-fail 4's test; it is red only under that sabotage.

## Must-fail lines

`vm-tools/guest/899-w8b-21-mustfail.json`, run in `w8b-21-a` on a1c8e9e6e from a clean committed tree, each restored by `git checkout` (status clean after). **7 RED of 7**:

1. The link followed, `Directory.Exists` deciding a linked place: RED in `ALinkWhoseTargetCannotBeReadRefusesTheRenameCannotTellNowAndChangesNothing` ("No exception was thrown": the WSL link is skipped). Measured: `Directory.Exists` on a junction whose folder is gone answers true on the PC (the nowhere test stayed green), so it reads the junction's own attributes there; the rename still must not ask it.
2. The link followed, `ResolveLinkTarget` naming `MoveLink`'s from: RED, 8 failed (the link tests of both classes: "“library” could not be read just now", the target is not a link).
3. The target listed, the link planned by `UndoTreeReading.Read` through it: RED, 8 failed ("“notes” was changed by another program": a listing judged against a link).
4. The target hashed after normalising separators: RED, 7 failed (every `linkSha` assertion: "Strings differ").
5. `FileAttributes.ReparsePoint` in place of `UndoLinks.Look` in `Rename`: RED in `APlaceThatIsAOneDriveStylePlaceholderIsMovedAsTheFolderItIs` ("“Tasks” could not be read just now": the placeholder sent to `MoveLink`). The Cloud Files placeholder test ran on the PC.
6. A page under the link relinked (the walk descending into links): RED, 3 failed (`ALinkInsideTheCourseIsNotWalked`, and both leading-out tests: "Expected: 2" pages, and "a page could not be saved").
7. The renamer planning a link's place by `MoveFolder`: RED in both U4b2-15 rows of `UndoStackContractTests.EveryLinkStackCase` ("“media” could not be read just now").

Restored: 509 passed of 509.

## Runs

- `w8b-21-a` (PC, `899-w8b-21-pc-run.ps1`, modes `classes,mustfail` with the red ref, 2026-11-27 01:46 to 01:52), the lock taken and released by the run itself (`LOCK-RELEASED`; no lock was held when it started):
  - Red ref as above.
  - At a1c8e9e6e: both builds 0 errors. **509 passed of 509, 0 skipped**: `SpecialFolderRenamerTests`, `UndoRenameFolderStepTests`, `UndoLinkMoveTests`, `UndoActionStepFolderMoveTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`, `UndoActionStepsOnWindowsTests`, `UndoActionTraceContractTests` (every symbolic-link, reparse-point and placeholder test ran).
  - Must-fail 7 RED of 7; restored 509 of 509; HEAD-AFTER the same, status clean.

## Left for the next piece

- 22 and 21a6 call `UndoActionStep.MoveLink` as it is (a link to a file is tested: `ALinkToAFileIsMovedAsItselfTheFileItLeadsToUntouched`).

## For the director

- **A link to a folder that leads nowhere: Windows renames it, the mac skips it.** Concrete example: section 2's `Tasks` is a junction (or `mklink /D` link) to `D:\Shared\Tasks`, and that folder has been deleted or its drive is not plugged in. Rename folder `Tasks` to `Assessments` on Windows now renames section 2's link to `Assessments` (still pointing at `D:\Shared\Tasks`), and the done sentence counts it. The mac's `SpecialFolderRenamer.plan` asks `fileExists(atPath:isDirectory:)`, which follows the link, finds nothing, and skips the place, so the link keeps the name `Tasks` while the settings say `Assessments`. I built what the brief says (its invariant: "wherever it is (inside the course, outside the working folder, nowhere)"; it lists "a link leading nowhere" as a test), which also matches Russell's "Never refuse" ruling for a class page link leading nowhere (2026-11-26). Recommendation: the mac copies Windows (rename the dangling link, judged by its own `lstat`), since a link left under the old name is a folder the settings no longer list. Not a question for Russell unless the mac's behaviour was meant; no contract row covers a dangling folder link.
- Developer Mode: nothing here makes a link, so a teacher's machine without Developer Mode renames a link exactly as the PC does (`MoveFileEx` on a symbolic link needs no privilege). Only the tests that lay a symbolic link skip there; the junction tests run everywhere.
- Self-check:
  - 1 (broke each fix): the must-fail rows below, each with its failing test.
  - 2 no timed waits; 3 the failure sentences: a refusal is the step's own `cannotTellNow` sentence through `RenameException` ("“Tasks” could not be read just now."), true of the disk (nothing changed, nothing recorded, pinned by `ALinkWhoseTargetCannotBeReadRefusesTheRenameCannotTellNowAndChangesNothing`); 4 dev merged as above; 5 no tuned number; 6 contracts read from the JSON, no `contracts/` change, nothing teacher-facing changed.
  - 7 no fixture row (no action converted; `renameFolder`'s recorded steps unchanged); 8 writer scan: no writing call added (`MoveLink` goes through the door or the swap); 9 no riding lows named; 10 n/a.
  - 11 both U4b2-15 rows pass and are out of the ledger; `Reason899W8U4b2LinkedFolder` gone; no other reason named what I taught.
  - 12 no key added to `KeysChecked` (`linkedFolder` was W8-6's).
  - 13 is it a link: `UndoLinks.Look`; is it a link to a folder: `UndoLinks.IsALinkToAFolder`; the target's hash: `UndoLinks.LinkSha`; stays inside: `UndoPlaces.FirstPlaceLeadingOut`; at or inside: `UndoOp.PartInside` (unchanged).
  - 14 no run going, no lock held, none removed that was not mine.
