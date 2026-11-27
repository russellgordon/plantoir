Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# W8b-21b5 (#899, Windows #949): `UndoActionStep.RelinkLink` records a link's move that changes its text, or copies the lesson where no link can be made

Brief `vm-tools/briefs/2026-11-27-899-w8b-21b5-action-step-records-a-relink.md`. Branch `issue/899-w8b-21b-relink` from 21b4's pushed head c1776f04e. `origin/dev` 454ef4c6f, already merged in; fetched before proving and again before handing back (see "Runs"). No `contracts/` or `mac-app/` change. Inert: no teacher action calls it until 22a. No ledger row.

## For PROGRESS

- `UndoActionStep.RelinkLink(fromFull, toFull, textAfter)` (the mac's `JournaledStep.relinkLink(_:to:textAfter:)`, relink-4) answers `UndoRelinkPlanned`: `Relinked`, `Moved` (the text unchanged: 21's plain `MoveLink`), `Copied` (21b1a's `CopyTheLessonInsteadOfALink`, where `UndoLinks.CanMakeALink(_plainSeams)` says no; a link leading to no lesson is then moved as itself, `Moved`), or `NotPlanned` (no link at `from` by `UndoLinks.Look`, or its text cannot be read now).
- The text now is read as the link itself by ONE function, `UndoLinks.TextOf` (`FileSystemInfo.LinkTarget`, never `ResolveLinkTarget`); `UndoLinks.LinkSha` now hashes `TextOf`'s text, so the bytes hashed and the bytes kept are one reading.
- The text written is `UndoLinks.TextToWrite(textNow, wanted)`, the director's reading of 21b1's parked point, in ONE function so it can be reversed: where `wanted` differs from the text now only in its last path part (the parts above compared with either separator read as one), the text now is kept byte for byte but that last part; any other text is written with backslashes. Its one caller is `RelinkLink`.
- `_folderMoves` holds both texts (`TextBefore`, `TextAfter`) for a relink, its `LinkSha` the text now, so every "is a link's move" reading (`LinkMoveStartingAt`, `LinkMoveEndingAt`, `PlaceOnDiskNow`, `IsChosenInThisStep`) holds for it, as the mac's `PlannedFolderMove`. `FolderMoveOp` builds `{"kind":"move","from","to","linkShaBefore","linkShaAfter","blobs":[both]}`; `MakeAsOps` adds both texts to the draft's blobs, before the begin with every other blob (a blob that cannot be written is the door's ordinary failure: in shadow one "could not record" line and the step made unrecorded).
- The place left is handed over exactly as for a plain link's move (21a6, unchanged). A plan at a relink's NEW place is refused `cannotTellNow` before anything changes: `RefuseAWriteAtALinkMovedAway` refuses it in the same folder too (`IsARelinkEndingAt`, the mac's `isARelink(endingAt:)`), and `PlannedPlace` never resolves it through the link; a write already planned there when `RelinkLink` is called refuses it too (the mac does not check that order; Windows refuses both orders, so the rule does not depend on the caller's order).
- Unrecorded, `WritePlainlyQuietly` gives the relink's `MoveHere` target its `UndoRelink(textBefore, textAfter, SourceIsFrom: true)` (the mac's `relinkGoingForward`), so it is made as the door makes it (21b1's swap).

## For documentation 12

Add to the W8b relink paragraph: `UndoActionStep.RelinkLink` (W8b-21b5) plans a relink as the mac's `JournaledStep.relinkLink`: the text read now as the link itself (`UndoLinks.TextOf`), the op `{"kind":"move","from","to","linkShaBefore","linkShaAfter","blobs":[both]}`, both texts written to the list before `begin`, the place left handed over as for a plain link's move, a plan at the new name refused `cannotTellNow` whichever is planned first, the unrecorded make by the door's own relink swap. A link text Windows writes uses backslashes, except that where only the last path part changes the rest of the text on disk is kept byte for byte (`UndoLinks.TextToWrite`, the one place this rule lives). Where `UndoLinks.CanMakeALink()` is false, the relink becomes 21b1a's copy of the lesson and answers copied.

## Tests (`UndoRelinkTests`, "Recorded by UndoActionStep")

1. `ARelinkAloneIsRecordedWithBothTextsAndUndoneAndRedone` (inside, out to a file, out to nothing): one op, both shas, no `linkSha`, both blobs by name byte for byte, the new link exactly the new text, nothing at the old; Undo and Redo exact (the working folder compared, links by text); the outside folder's names, lengths, write and access times unchanged, its bytes as laid.
2. `ARelinkWhoseOldPlaceIsFilledInTheSameStepIsOneStep`: Insert Class's shape; one step, one handover at Day 4, `WholeOpsStandAlone`, Undo and Redo exact.
3. `TwoRelinksInARowAreOneStep`: the mac's texts (`../../elsewhere/three.md`, `four.md`, `five.md`), Day 3 to 4 planned before Day 4 to 5: two ops, one handover, exact both ways (the forward slashes kept: only the last part changed).
4. `AWriteAtARelinksNewNameIsRefusedBeforeAnythingChanges` (by text, by the bytes planned from, and planned before the relink): `cannotTellNow`, folder unchanged, the outside target untouched, nothing on the list.
5. `ARelinkWhoseNewTextTheListRefusesGoesAheadUnrecorded`: the new text's blob folder a file; one trail line, the change went ahead, nothing on the list, the new text not in it, the relink made, nothing staged.
6. `WhereNoLinkCanBeMadeTheLessonIsCopiedAndUndoPutsTheLinkBack` (the seam `CanMakeALinkAnswers = false`): answered copied; a plain copy at Day 5, the link set aside under `.Unit 1, Day 4.md.link-kept-by-undo` with its text; Undo puts the link back at Day 4 exactly, Redo exact.
- Windows' own: `ARelinkOfNoLinkPlansNothingAndOfTheSameTextIsAPlainMove` (a plain page and nothing at all answer not planned, nothing planned; the same text a `linkSha` move), and `ALinkTextIsKeptAsStoredWhenOnlyItsLastPartChanges` (six rows of `TextToWrite`, a plain `[Theory]`).

## Must-fail lines (`vm-tools/guest/899-w8b-21b5-mustfail.json`)

RED 4 of 4 (run w8b-21b5-a, ref a20edfa56, each against `UndoRelinkTests`, 99 tests):
1. the texts left out of the step's blobs: RED, 6 of 99 (test 1's three rows, test 2, test 3 and the same-text test's neighbours: the door cannot name the relink's blobs, so nothing is recorded).
2. a write at the new name planned through the link (both `IsARelinkEndingAt` guards removed): RED, 2 of 99 (`AWriteAtARelinksNewNameIsRefusedBeforeAnythingChanges`, `byText` and `byReadBytes`; the `beforeTheRelink` row is still caught by `RelinkLink`'s own check, as designed).
3. the text read through the link (`ResolveLinkTarget(true).FullName` in `UndoLinks.TextOf`): RED, 55 of 99 (the kill table, `ARelinkOfNoLinkPlansNothing…`, every recorded relink: `LinkSha` and the kept text are no longer the stored text).
4. `CanMakeALink` not asked: RED, 1 of 99 (`WhereNoLinkCanBeMadeTheLessonIsCopiedAndUndoPutsTheLinkBack`: a link made where none can be).

Restored 428 of 428, HEAD-AFTER same, status clean.

## Runs

- w8b-21b5-a (PC, LENOVO 20QES70500, Windows 11 Pro 26200, Developer Mode on; ref a20edfa56, red ref 71b0ce501; queued at 09:36 behind the director's int-d27b-2 run, lock taken 09:47 when free, released by its own run 09:55): **red 17 of 99** in `UndoRelinkTests` at the tests-first commit (every new test, `NotImplementedException` from the inert stubs: test 1's three rows, test 4's three, the six `TextToWrite` rows, tests 2, 3, 5, 6 and the no-link test; the class's 82 earlier tests green); both builds 0 errors; **428 of 428 passed** (`UndoRelinkTests`, `UndoLinkCopyTests`, `UndoHandedOverPlaceTests`, `UndoActionStepTests`, `UndoActionStepFolderMoveTests`, `UndoMakeRoomStepTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`); must-fail RED 4 of 4; restored 428 of 428.
- `origin/dev` fetched after the run: still 454ef4c6f, already in this branch, so no merge commit this piece.

## Ledger

No row. `NamedGapLedgerTests` run.

## Self-check

1 to 6 (NIGHT3): own classes only on the PC under the turn lock, no UI class, no whole suite; tests first in their own commit (71b0ce501), seen red; must-fail recorded; notes written. 7 to 10: no fixture row (inert); the writer-scan count unchanged (no writing call added: `TextOf` reads), `UndoWriterScanTests` run; no riding lows; no action step converted. 11 and 12: no held row, no key added. 13: one function per rule: `UndoLinks.TextOf` for a link's text, `UndoLinks.TextToWrite` for the text Windows writes, `UndoLinks.Look` for "is this a link", `UndoLinks.CanMakeALink` for whether one can be made, `UndoOp.PartInside` for every place comparison (`IsARelinkEndingAt` included). 14: no run left going, the lock taken only when free and released by its own run.

## Left for the next piece

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- 22a: call `RelinkLink` from Insert Class, plan it before any write of the file the link leads to (the copy reads it from the disk at plan time), and say copied in 22b's line (`CopiedInsteadOfLinks`).
- A relink whose `from` and `to` are one place (ruling 8; the mac has not built it).

## For the director

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- Nothing parked. Two readings, both small: (1) where no link can be made and the link leads to no lesson (nowhere, or a folder), `RelinkLink` moves it as itself with its old text and answers moved, as 21b1a's summary said its caller would; (2) a write planned at the new name BEFORE the relink is refused too (the mac refuses only a write planned after it). A removal planned there first is allowed, as on the mac (Insert Class removes a page below before a link moves into its place).
