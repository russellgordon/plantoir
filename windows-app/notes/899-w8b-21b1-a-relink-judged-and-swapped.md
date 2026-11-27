# W8b-21b1 (#899, Windows #949): a relinking move judged by each side's own text, swapped as make, rename in, remove

Brief `vm-tools/briefs/2026-11-27-899-w8b-21b1-a-relink-judged-and-swapped.md`. Branch `issue/899-w8b-21b-relink` from the pushed head of `issue/899-w8b-21a-handed-over-place` (db430aa41, `origin/dev` 6dc36fcea already merged in; checked before proving and before handing back, no merge needed). The mac's piece: U4b3 relink-1. No `contracts/` or `mac-app/` change.

## Measured first (PC, 2026-11-27)

Windows 11 (NT 10.0.26200), NTFS, .NET 9.0.18, Developer Mode on; a throwaway console probe under the turn lock, in `%TEMP%`, then pinned by `UndoRelinkTests.AForwardSlashTextIsKeptByteForByteButTheSystemDoesNotOpenThroughIt`:

| Text given to `File.CreateSymbolicLink` | `LinkTarget` reads back | Byte for byte | `File.ReadAllText` through it | `ResolveLinkTarget(true)` |
|---|---|---|---|---|
| `../library/Day 4.md` (the mac's spelling) | `../library/Day 4.md` | yes | **fails**: `IOException`, "The filename, directory name, or volume label syntax is incorrect" (ERROR_INVALID_NAME, 123) | `…\library\Day 4.md`, exists (.NET resolves it itself) |
| `..\library\Day 4.md` | `..\library\Day 4.md` | yes | opens, `Four.` | the same file |

So: the text IS kept byte for byte (`LinkHolds` works, a relink is not refused for the separators), but a link holding forward slashes does NOT lead to its file when the system opens it. Nothing is built around the second answer here (the swap never follows a link). Parked for the director, below.

## For PROGRESS

- `UndoOp` gains `LinkShaBefore` and `LinkShaAfter` (in memory only), the factory `UndoOp.RelinkLink(from, to, linkShaBefore, linkShaAfter)` (both in `Blobs`, none of `Sha`, `ListingSha`, `LinkSha`), `IsALinksMove` (`LinkSha` or `LinkShaBefore`), `IsARelink`, `LinkText(isAtFrom)`.
- Every "is this a link's move" site asks `IsALinksMove`: `UndoOp.MoveCarries`, `UndoOp.Handovers` (`ALinkMoves`), `UndoOp.HandsOverAsAMove`, `UndoPlaces.StaysInside(root, relative, op)`, `UndoMoveSides.ReadNamingFoldersLeftOut`, the swap's own-files look (`UndoSwap.Swap`, no walk inside a link's move).
- `UndoMoveSides.Read` / `ReadNamingFoldersLeftOut` take `isAtFrom` (default true; every product caller passes it): `UndoCheck.WholeStateOf` reads `from` with true and `to` with false (the capitalisation-only branch too), the swap's re-check reads the source by `UndoRelink.SourceIsFrom` and the target by its opposite. A link side is read by `ReadALink(op.LinkText(isAtFrom))`, as the link itself, never followed. Both links standing holds the content on both sides: neither state, changed since both ways, nothing removed.
- `UndoCheck.WholeTarget`: a relink's target carries `UndoRelink(SourceText, DestinationText, SourceIsFrom)`, both read from the list by blob (and their hashes checked, as a tree's are); either missing gives null, so content missing, nothing changed. `UndoSwapTarget.Relink` (null for every other change).
- `UndoSwap.RelinkLink(oldFull, oldText, newFull, newText, label, seams)`: a new link holding `newText` made by `MakeALink` (`File.CreateSymbolicLink`, the text as UTF-8, never over anything) under `BesidePath(newFull, label, "new")`, renamed in by `RenameWithRetries(replace: false)` (MoveFileEx without MOVEFILE_REPLACE_EXISTING, the link itself), then the old link removed by `RemoveALink` (opened as the reparse point, `UndoStagedFile.RemoveByName`) only once `LinkHolds(oldFull, oldText)`. If the old changed or will not go, the new link (this call's own, re-read holding `newText`) is removed again and the old left whole. The `MoveHere` case of `SwapAWholeOp` and `Reverse` (the other way round) call it for a relink; a relink is never "followed" as a move (`FollowTheMove` skipped, as the mac's relink branch).
- Refusals: a make that fails is `CouldNotWrite`, a rename-in that fails or an old link changed is `FileIsInUse`, both naming the place the link leaves (`FromRelative`, as every `MoveHere` refusal). A make the system refuses for want of the privilege (Win32 1314, a PC without Developer Mode) is an ordinary failed make: `CouldNotWrite`, any swap already made reversed, nothing retried, no fallback (Russell's Q2 copy is 21b1a's).
- Seams on `UndoSeams`: `RelinkRenameInFails` (the mac's `relinkRenameInFails`) and `MakingALinkAnswers` (a Win32 error instead of the system's, for 1314).
- `TidyLeftovers` already removes a staged `-new` link as the link itself (`Look` says link, `RemoveByName` opens the reparse point); pinned by `AStagedNewLinkIsTidiedAsTheLinkItself`.
- `UndoWriterScanTests`: `UndoSwap.cs` 26 to 27 writing calls (`File.CreateSymbolicLink` in `MakeALink`), reason extended.
- Inert: `ReadOp` reads neither field and `ShapeIsKnown` is unchanged, so a relink from the journal is not readable (`ARelinkFromTheJournalIsStillUnreadable`); 21b2 makes it readable.

## For documentation 12

Windows' `UndoOp` gains `LinkShaBefore` and `LinkShaAfter` (both blobs; an op carrying them carries none of `Sha`, `ListingSha`, `LinkSha`). `UndoCheck.Plan` judges `from` by `LinkShaBefore` and `to` by `LinkShaAfter`, each read as the link itself (`UndoLinks.Look`, `LinkTarget` as stored, never followed); both standing is neither. `UndoSwap.RelinkLink` makes a new link holding the destination's text (from its blob) under the staged `-new` name beside the destination (`File.CreateSymbolicLink`), renames it in without replacing, then removes the old link only once it is re-read holding the source's text; if that fails, removes the link it made. The reversal is the same three steps the other way round. Every "is this a link's move" test asks `UndoOp.IsALinksMove` (`LinkSha` or `LinkShaBefore`), or a relink would be read through, judged leading out, or carry edits. Measured (PC, Windows 11 26200, NTFS): a link text with forward slashes is stored byte for byte, but the system does not open a file through it (ERROR_INVALID_NAME); one with backslashes opens.

## Tests

`UndoRelinkTests` (new; `[SymbolicLinkFact]`/`[SymbolicLinkTheory]` but for the two plain facts), the mac's ten in meaning plus Windows' own:
- `ARelinkIsALinksMoveWithEachSidesOwnTextAndBothTextsAsBlobs` (the factory, the one test, `LinkText`, handover and carrying), `ARelinksPlacesAreJudgedOnTheFoldersAboveThemOnly`, `AForwardSlashTextIsKeptByteForByteButTheSystemDoesNotOpenThroughIt` (the measurement);
- there and back leading inside, out to a file and out to nothing (outside bytes, write and access times untouched, nothing made there); a side holding the other text, a file, a folder or nothing, both ways; both links standing, both ways; a side that cannot be read (`CannotTellNow`, both blobs still in the list); either text missing (`ContentMissing`); a later target failing (relink reversed); the rename-in failing (old link whole, `RelinkRenameInFails`); an old link changed before its removal (left, the new one taken away); a make answered 1314 (`CouldNotWrite` naming Day 4, the earlier file move reversed, asked once); as the leaver and as the filler of a handed-over place, both ways; a staged `-new` link tidied as itself; inert from the journal.

## Must-fail lines (`vm-tools/guest/899-w8b-21b1-mustfail.json`, run w8b-21b1-b)

1. `IsALinksMove` as `LinkSha is not null`: RED, 18 of 27 (`ARelinkIsALinksMove…`, `ARelinksPlacesAreJudgedOnTheFoldersAboveThemOnly`, `ATextMissingFromTheListIsContentMissing` "before: the plan came to ChangedSince", and the swap tests).
2. both links standing read as after (`WholeStateOf`, a relink holding the content on both sides): RED, `BothLinksStandingIsChangedSinceBothWays` both rows ("False: Ready").
3. the old link removed before the new one is renamed in: RED, 13 of 27 (`ARelinkLeavingAHandedOverPlaceGoesBothWays`, `ASideHoldingSomethingElse…`: "refused FileIsInUse … Day 4.md").
4. the old link removed without being re-read: RED, `AnOldLinkChangedBeforeItsRemovalIsLeftAndTheNewLinkTakenAway`.

RED 4 of 4; restored 1492 of 1493, HEAD-AFTER same, status clean.

## Runs

- Measurement probe (PC, under the lock, a throwaway console app in `C:\vm-setup\899-w8b-21b1-probe`, removed after): the table above.
- w8b-21b1-a (PC, ref e4612963f, red ref 0cc403a49): **red 18 of 27** at the tests-first commit (`UndoRelinkTests`; `Assert.True() Failure` throughout: plans ChangedSince or refused where they must be Ready, `IsALinksMove` false); both builds 0 errors; 1491 of 1493 (1 skipped), the one failure mine: the there-and-back row out to a file, at the outside files' access time (`OutsideNow` itself opened the files and moved it). Must-fail RED 4 of 4 (taken again in -b).
- w8b-21b1-b (PC, ref 26ecdba82, the test reading times without opening): both builds 0 errors; **1492 of 1493 passed, 1 skipped** (`~Plantoir.Tests.Undo` with `NamedGapLedgerTests`: `UndoRelinkTests`, `UndoLinkMoveTests`, `UndoHandedOverPlaceTests`, `UndoSwapTests`, `UndoRenameFolderStepTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests` among them); must-fail RED 4 of 4; restored 1492 of 1493; lock released.
- `origin/dev` still 6dc36fcea before proving and before handing back: no merge needed.

## Ledger

No row (inert). `NamedGapLedgerTests` green in -b.

## Self-check

1 to 6 (NIGHT3): own classes only on the PC under the lock, no UI class, no whole suite; red first (18 of 27) and must-fail recorded; notes written. 7 to 10: no fixture row (inert), the writer-scan count true (27), no riding lows, no action step. 11 to 14: no held row this piece; no key added; one function per rule (`UndoOp.IsALinksMove` for a link's move, `UndoLinks.Look` for a link, `UndoOp.LinkText` for a side's text, `UndoSwap.LinkHolds` for a link's text); no run left going, the lock taken only when free (the reviewer's was waited out, never touched) and released by its own run.

## Left for the next piece

- 21b1a: the copy where a link cannot be made. 21b2: `ReadOp`, `ShapeIsKnown`, the seven check rows. 21b3: recovery and the stop points `relinkStaged`, `relinkRenamedIn` (inside `RelinkLink`, between the make and the rename, and between the rename and the removal). 21b5: `UndoActionStep.RelinkLink`.
- `MakeALink` makes a FILE symbolic link (a class page's). A relink of a link to a folder is not a shape anything makes (the mac's relink is for class pages); if one is ever wanted, the make must ask the old link's kind (`UndoLinks` folder-link test).

## For the director

- **Parked (measured, for piece 22 and 21b5): a link holding the mac's forward-slash text does not open on Windows.** Example: `section1/Unit 1, Day 4.md` → `../library/Day 4.md`, made by `File.CreateSymbolicLink`, reads back byte for byte but `File.ReadAllText` through it fails (ERROR_INVALID_NAME); `..\library\Day 4.md` opens. The relink swap is unaffected (it judges and makes by text, never follows). What it touches: which text a link that WINDOWS makes holds (21b5's `RelinkLink` and 22a's re-pointing write a new text), and the contract rows that lay `../../elsewhere/Unit 1, Day 3.md` (order file, director item 9). Options: (a, recommended) a link text Windows itself writes uses backslashes, and one it keeps (a plain move, a relink's old text) is kept byte for byte, so a mac-made link keeps its text and a Windows-made one opens; (b) keep the mac's spelling everywhere and accept that such links do not open on Windows (Obsidian and the builder then cannot read the page); (c) rewrite separators when relinking, which breaks byte-for-byte judging and is rejected. Nothing built for it here.
- No lock was removed that this piece did not take.
