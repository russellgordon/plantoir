# #899 W8-6: a link moved as itself, judged by its target's bytes

Branch `issue/899-w8-6-link-moved-as-itself`, base `origin/issue/899-w8-5-case-only-move` 0b7ce258a (holds `origin/dev` 461ee3943). `origin/dev` had not moved at either merge point (461ee3943 both times), so there is no merge commit: dev is already in.

## For PROGRESS

- A `move` with `linkSha` (opKinds.move, U4b2-14) is readable on Windows and moves a junction or symbolic link (a name-surrogate reparse point, `UndoLinks.Look`) as itself: one `MoveFileExW` on the link, without `MOVEFILE_REPLACE_EXISTING`.
- Each side is judged by `UndoMoveSides.ReadALink`: a link whose stored target (`FileSystemInfo.LinkTarget`, never `ResolveLinkTarget`), as UTF-8 unchanged, hashes to `linkSha` holds the content; absent is free; a folder, a file (a OneDrive placeholder included) or a link with another target is something else; a link whose target cannot be read (WSL's own) is cannot tell now. The one hashing function is `UndoLinks.LinkSha`.
- `UndoFormat.ShapeIsKnown`: a move needs exactly one of `sha`, `listingSha`, `linkSha`; `linkSha` must be a blob's name and is never a blob.
- `UndoOp.MoveCarries` is false for a link's move, so a step with an edit at or inside its `to` is not readable (`UndoStep.WholeOpsStandAlone`), from its shape.
- Stays inside: `UndoPlaces.StaysInside(root, relative, op)` (the mac's `staysInside(_:_:namedBy:)`) resolves only the folder above a link move's `from` and `to`. `FirstPlaceLeadingOut` (plan, swap's last look), the swap's fallback, recovery's whole-op state and the door's vetting at make all ask it, so a link leading out of the working folder, or nowhere, is moved like any other.
- The swap never walks a link move's `from` for the step's own files (`StepsOwnFilesInside` is not asked for one).

## For documentation 12

Under "What W8 owes from U4b2-14": done in W8-6. Measured on the PC (Windows 11, NTFS, Developer Mode on), as tests in `UndoLinkMoveTests`:

- A junction made by `mklink /J <place> <full path>`: `LinkTarget` is the full path as given, no `\??\` (`AJunctionHoldsItsFullTargetAndOneRenameMovesTheJunctionAlone`).
- A folder symbolic link made by `Directory.CreateSymbolicLink(place, "../library")`, unelevated: made, and `LinkTarget` is `../library`, forward slash kept, so its `linkSha` is the mac's (`ASymbolicLinkHoldsItsTargetAsWrittenAndOneRenameMovesTheLinkAlone`).
- `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING` on either moves the link alone: the folder it leads to keeps its listing and the file identity (volume, index) of itself and every file (both tests).
- **Windows cannot follow a symbolic link whose relative target uses `/`**: enumerating through `section1/media -> ../library` throws `IOException` "The filename, directory name, or volume label syntax is incorrect" (ERROR_INVALID_NAME). A mac-made link is therefore held and moved correctly but leads nowhere on Windows; nothing in the door follows it. The test scribe's `StagedLeftovers` walked through links and met this; it now skips reparse points.
- Separators are NOT normalised: the target is hashed as `LinkTarget` gives it. A link made on one platform and judged on the other (`..\library` against `../library`) is changed since, which is safe.
- No WSL on the PC, so no real WSL link: the "cannot tell now" test sets an `IO_REPARSE_TAG_LX_SYMLINK` reparse point by `FSCTL_SET_REPARSE_POINT` on an empty file (a name surrogate .NET does not read: `LinkTarget` is null). The "not a link" test sets `IO_REPARSE_TAG_DEDUP` (no name surrogate) as OneDrive's stand-in. Both skip, saying why, where the volume refuses the FSCTL.
- On a machine without Developer Mode (the VMs), every test that lays a symbolic link with a target as written is SKIPPED with the reason (`SymbolicLinkFact`, `SymbolicLinkTheory`): `UndoCheckContractTests.EveryLinkMoveCheckCase` (three rows), `UndoStackContractTests.EveryLinkStackCase` (two rows), and two `UndoLinkMoveTests`. A junction holds only an absolute target, so it cannot stand in. The junction tests run everywhere.

## Tests that failed first

Red ref 3561fcd60 (this branch's tests, the product as it was with only the `LinkSha` member and a `LinkSha` stub returning null), run `899-w8-6-red2`: **14 failed of 587**:

- `UndoCheckContractTests`: the four link rows (`notReadable` where `canUndo`, `changedSince`, `changedSince`, `alreadyBack` were expected).
- `UndoStackContractTests.EveryLinkStackCase`: the two `moveALinkToAFolder` rows (`redo` expected 1, was null: the step was refused).
- `UndoLinkMoveTests`: `ALinksMoveIsReadable…` (line 116, `Readable`), `AnEditInsideALinksNewPlace…` (line 144), the junction moved, another target, a plain folder, a junction leading out and the symbolic link moved (each `Applied` expected, `Refused`), `ALinkWhoseTargetCannotBeRead…` (`CannotRead` expected, `HoldsSomethingElse`).
- Passed there as guards: the two measurements, `AReparsePointThatIsNotALinkIsSomethingElse` (red only under must-fail 6), and the stack row "U4b2-14, review 1" (a link move with no `linkSha` reader is unreadable anyway; red only under must-fail 4).

The first red ref, 1d310ccf1, did not compile (a local named `link` twice in `UndoCheckContractTests.PlaceAt`); fixed at 717d3f17f.

## Must-fail lines

`vm-tools/guest/899-w8-6-mustfail.json`, run `899-w8-6-green2` from a clean committed tree (70cb9665b), each restored by `git checkout` (status clean after). All 7 RED:

1. The link followed (`ResolveLinkTarget(returnFinalTarget: true)?.FullName` for `LinkTarget`): 5 failed: `ASymbolicLinkKeepsItsTargetAsWrittenAndIsMovedAsItself`, check rows "judged by the target it names" and "a link leading out", both `moveALinkToAFolder` stack rows.
2. The target hashed after normalising (`/` to `\`): the same 5.
3. `linkSha` taken with `listingSha` (`contents >= 1`): `ALinksMoveIsReadableWithExactlyOneContentAndItsLinkShaIsNoBlob`.
4. A link move allowed to carry an edit (the `LinkSha` guard in `MoveCarries` dropped): `AnEditInsideALinksNewPlaceIsAStepThatCannotBeRead` and the stack row "U4b2-14, review 1".
5. The link resolved in the stays-inside check (`StaysInside(root, relative, op)` always following): `AJunctionLeadingOutIsMovedLikeAnyOtherWhatItLeadsToNeverTouched`. (The check row "a link leading out" stays green under it, because Windows cannot follow its `../../../..` target at all: see the measurement above.)
6. The bare `FileAttributes.ReparsePoint` in place of `UndoLinks.Look` in `ReadALink`: `AReparsePointThatIsNotALinkIsSomethingElse`.
7. (W8-4 review LOW 1) `Reverse` drops `else FollowTheMove(...)`: `ARedoRefusedAtItsCarriedPageLetsGoOfItsStagedFileAndMovesTheFolderBack`.

## Runs

All on the PC under `C:\vm-setup\wt-compare.lock`, classes `UndoLinkMoveTests`, `UndoCheckContractTests`, `UndoStackContractTests`, `UndoFormatTests`, `UndoSwapTests`, `UndoDoorTests`, `NamedGapLedgerTests`, `UndoCarryingMoveTests`, `UndoWriterScanTests` (the only class a grep for `MakeALink` finds is `UndoCheckContractTests`). Both builds 0 every time. Started after the director's int-d26-3 whole-suite run released the lock (waited, not removed).

- `899-w8-6-red`: 1d310ccf1, test build failed (above).
- `899-w8-6-red2`: 3561fcd60 (pushed as `scratch/899-w8-6-red`, deleted after), 14 failed of 587, 0 skipped.
- `899-w8-6-green`: 717d3f17f, 2 failed of 587: the two link stack rows, at the scribe's `StagedLeftovers` (the walk through the `../library` link, above). Fixed at 70cb9665b.
- `899-w8-6-green2`: 70cb9665b, **587 passed, 0 failed, 0 skipped**; then must-fail **7 RED of 7**, RESTORED 587 passed; HEAD-AFTER SAME, status clean, `LOCK-RELEASED`. This is the head proven; the notes commit after it changes no code.

## The writer scan (the director's addition)

`UndoWriterScanTests.EveryWriterIsTheDoorOrNamedWithAReason` failed on the merged W8 tree because `UndoSwap.cs` holds 26 writing calls against `Allowed`'s 24. The two are W8-4's (d940a6a7a): `UndoSwap.RemoveAFolderLeftOut`, `File.Delete(entries[0])` (a lone regular `.DS_Store`) and `Directory.Delete(folder, recursive: false)`, UndoSwap.cs about lines 683 and 685. They are the door's own machinery (a folder the step's carried edit made, removed by the swap once every swap is in), so the entry is now 26 with that named in its reason (commit 9c91a0463). Counted per piece: 24 at pieces 1 to 3, 26 from piece 4; `UndoOpKinds.cs` stays 11 (W8-6 adds no writing call).

## Riding lows

- Sweep LOW 1, the `PlaceName` comment (UndoFormat.cs about 109): rewritten; it now says only recovery and "content missing" use it, and names `PlaceAsFound` and `FirstPlaceLeadingOut` for a move's other refusals.
- Sweep LOW 2, the superseded bullet in the W8-2 notes: marked "Superseded" with why.
- Sweep LOW 3, the function name in documentation 12's new W8 section: NOT in this tree (it is on `origin/day26/integration-3`, and `origin/dev` is still 461ee3943), so left, as the brief says.
- Sweep LOW 4, plan and swap differing on which moves leave own files out: recorded, not made to agree. Making the plan leave them out for every move would loosen it; making the swap leave them out only for a carrying move could refuse a move whose earlier swap left a staged file inside. One comment in `UndoCheck.Plan` (beside `carriesEdits && ownSeq`) now says the plan is the stricter on purpose and why the two stay apart.
- W8-4 review LOW 1: must-fail row 7 drops `else FollowTheMove(...)` in `Reverse`; its test is `ARedoRefusedAtItsCarriedPageLetsGoOfItsStagedFileAndMovesTheFolderBack`. `ARedoRefusedAfterItsCarryingMoveIsReversedWhole` is kept as a named guard (no handle inside the folder when the reversal runs, so no sabotage of the let-go turns it red).

## Left for the next piece

- Rename folder of a linked section folder (W8b 21, the two U4b2-15 rows, still held under `Reason899W8U4b2LinkedFolder`, which no longer names the key `linkedFolder`; both now stop at the unknown call `renameAPerSectionFolderThatIsALink` behind the taught key).
- Windows' `UndoPlaces.StaysInside` on a link that leads NOWHERE at a place it does follow (any op other than a link's move): the final path of the leaf cannot be opened, so it falls back to the folder above and answers inside. The mac refuses ("a link that leads nowhere: refused rather than guessed at"). Not this piece's invariant; for the director.
- Recovery (pieces 7 and 8) reaches the link's move through `UndoCheck.Plan` and `FirstPlaceLeadingOut`, but no recovery row names a link's move.

## For the director

- Lesson 4: the key `linkedFolder` added to `KeysChecked`; the only rows still held that carry it are the two U4b2-15 rows, and they stop at "a call this replay does not know: renameAPerSectionFolderThatIsALink" (green runs, `HeldCaseStillStopsAtItsGap`).
- No `contracts/` change. Nothing a teacher sees changed.

## Self-check

1-6 (NIGHT3): tests first (red ref above); one invariant; no timed wait; no interim state; nothing teacher-visible; notes written.
7. No fixture row (no action converted); the four check rows and three stack rows are out of the ledger; `Reason899W8U4b` and `Reason899W8U4b2LinkedFolder` rewritten.
8. Writer scan: UndoSwap 26 (W8-4's two), UndoOpKinds 11, true.
9. Riding lows: above, each done or recorded with why.
10. n/a (no action's file order).
11. Every held row the brief names passes and is gone; both reason sentences rewritten; no constant left unused.
12. `linkedFolder` checked against the two rows still held.
13. One function per rule: "is it a link" is `UndoLinks.Look`; the target's hash is `UndoLinks.LinkSha`; stays inside is `UndoPlaces.StaysInside(root, relative, op)` through `FirstPlaceLeadingOut`; no new spelling comparison.
14. Every run waited for to RUN_DONE; each released only its own lock (`LOCK-RELEASED`); none removed that was not mine.
