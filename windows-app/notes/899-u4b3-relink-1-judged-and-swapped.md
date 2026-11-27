Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# U4b3 relink-1 (#899): a relinking move judged by each side's own text, swapped as make, rename in, remove

Brief `vm-tools/briefs/2026-11-26-899-u4b3-relink-1-judged-and-swapped.md`, from ea0ad5cac on `issue/899-u4b3-linked-class-page-moves-its-link`. `origin/dev` is still 06e067fbe (already merged in, dc161321d); checked before proving and before handing back, no merge needed. `contracts/` not touched.

## For PROGRESS

- `UndoOp` gains `linkShaBefore` and `linkShaAfter` (decoded, encoded), the factory `UndoOp.relinkLink(from:to:linkShaBefore:linkShaAfter:)` (both shas in `blobs`), `isALinksMove` (`linkSha != nil || linkShaBefore != nil`), `isARelink`, and `linkText(isAtFrom:)` (each side's sha; `linkSha` on both sides of a plain link move).
- Every "is a link's move" site asks `isALinksMove`: `UndoCheck.handovers` (`aLinkMoves`), `handsOverAsAMove`, the swap's own-files look (reads nothing through a link), `UndoMoveSide.readNamingFoldersLeftOut`, `UndoPlaces.staysInside(_:_:namedBy:)`, `UndoOp.moveCarries`. `JournaledStep`'s tuple untouched (relink-4).
- `UndoMoveSide.read` / `readNamingFoldersLeftOut` take `isAtFrom` (default true; product callers pass it): `wholeState` reads `from` by `linkShaBefore`, `to` by `linkShaAfter`, both by `lstat` and `readlink`, never followed. Both links standing is `.neither`, so a plan is `changedSince` both ways and removes nothing.
- `UndoCheck.wholeTarget`: a relinking move's target carries `UndoRelink` (source text, destination text, whether the source is `from`), both read from the list by blob; either missing gives nil, so `contentMissing`, nothing changed. `UndoSwapTarget` gains `relink` (nil for every other change).
- `UndoSwap.relinkLink(leaving:holding:onto:holding:label:)`: a new link with the destination's text made by `symlink` under the staged name `-new` beside the destination, renamed in with `RENAME_EXCL`, then the old link `unlink`ed once re-read holding the source's text. If the old link changed or will not go, the new link (this call's own) is unlinked again and the old left whole. The swap's `.moveHere` branch re-reads the pair each side by its own text, then calls it; `reverse()` calls it the other way round. Helpers `makeALink`, `linkHolds`, `removeALink`.
- `removeStaged` on a link: `removeItem` removes the link itself, and the `chflags` retry only touches a regular file (`S_IFREG` check), so a link is never `chflags`ed. Proven by the rename-in-fails test (the staged link is removed, nothing staged left).
- New test seam `UndoKillPoints.relinkRenameInFails` (the rename-in fails as a place taken in that instant would), needed to prove M3.
- `UndoWriterScanTests`: `UndoCheck.swift` 17 to 19 writing calls (`symlink`, `unlink`), reason extended.
- Inert: `UndoOp.shapeIsKnown` is unchanged and refuses the op (none of `sha`, `listingSha`, `linkSha`); `testARelinkFromTheJournalIsStillUnreadable` pins it, and that the JSON carries no `linkSha`.

## Tests

`UndoRelinkTests`, `// MARK: - Judged and swapped (relink-1)`, ten tests: there and back with the texts leading inside, out to a file and out to nothing (outside files' bytes, access and modification times untouched, nothing made there); a side holding the other text, a file, a folder or nothing, both ways; both links standing, both ways; a side that cannot be read (`cannotTellNow`, both blobs still in the list); either text missing (`contentMissing`); a later target failing (relink reversed); the rename-in failing (old link whole); as the leaver and as the filler of a handed-over place, both ways; inert from the journal.

## For documentation 09

(Not written: inert. relink-2 writes it.) "U4b3: a relinking move. A link's move may change the text the link holds (`linkShaBefore` at `from`, `linkShaAfter` at `to`, both texts as blobs, never beside `linkSha`, so an older reader cannot read it rather than Redo it with the old text). Each side is judged by its own text, `lstat` and `readlink`, never followed; both links standing is neither state. It is swapped as: make the new link under a staged name beside its place, rename it in exclusively, then remove the old link once re-read; a later failure reverses it the same way the other way round. Nothing is ever written through either link."

## For documentation 12

Windows' `UndoOp` gains `linkShaBefore` and `linkShaAfter` (both blobs; an op carrying them carries none of `sha`, `listingSha`, `linkSha`). `UndoCheck.Plan` judges `from` by `linkShaBefore` and `to` by `linkShaAfter`, each read as the link itself (never followed); both standing is neither. `UndoSwap` makes a new link holding the destination's text (from its blob) under the staged `-new` name beside the destination, renames it in exclusively, then removes the old link only once it is re-read holding the source's text; if that fails, removes the link it made. The reversal is the same three steps the other way round. Every "is this a link's move" test asks for either sha (`linkSha` or `linkShaBefore`), or a relink would be read through, judged leading out, or carry edits.

## Must-fail lines (RED 4 of 4)

See `899-u4b3-relink-1-mustfail.log`: M1 run-r1-mf1, M2 run-r1-mf2, M3 run-r1-mf3, M4 run-r1-mf4, each restored with `git checkout`, `git diff` clean.

Seen failing first: run-r1-red, the relink paths disabled (`isALinksMove` as `linkSha != nil`, no `linkText` for a relink, no `UndoRelink` in `wholeTarget`: the code as it stood): 8 of 10 failed (the two that passed: both-standing, and cannot-be-read, which the old reading also refused).

## Runs (`.dd/`)

run-r1-red (8 of 10 red), run-r1-green (UndoRelinkTests, UndoHandedOverPlaceTests, UndoRenameFolderStepTests, JournaledStepTests, UndoJournalContractTests, UndoFilesContractTests, UndoDoorGuardTests, UndoWriterScanTests, UndoOpKindsTests, UndoKeptCopiesTests: 228, 2 failures, both mine: a test's expected order and the writer scan's count), run-r1-green2 (UndoRelinkTests and UndoWriterScanTests, 16 of 16), run-r1-mf1 to mf4.

## Left for the next piece

- relink-2: `shapeIsKnown` (exactly `linkShaBefore` and `linkShaAfter`, different, both blob names, both in `blobs`), the contract sentence, `checkCases`, Python.
- relink-3: recovery's reading of the both-standing moment, the stop points `relinkStaged` and `relinkRenamedIn` inside `UndoSwap.relinkLink` (between `makeALink` and the rename, between the rename and the removal). Recovery code that renames a `.moveHere` back (it reads targets of its own) is unchanged here and must learn the relink.
- relink-4: `JournaledStep.relinkLink`.

## For the director

Nothing parked.

## Self-check

1 to 6 (NIGHT3): own classes only through `xlock.sh`, no gate, no Windows, no UI tests; red first and must-fail recorded; notes written. 7: house-style grep over added Swift lines empty; `UndoRelink` and the test class have MARK sections. 8: no riding lows in this brief. 9: switch off, rename record untouched. 10: no contract rows.
