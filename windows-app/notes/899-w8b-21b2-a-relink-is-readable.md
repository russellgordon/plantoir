# W8b-21b2 (#899, Windows #949): a relinking move is readable from the list

Brief `vm-tools/briefs/2026-11-27-899-w8b-21b2-a-relink-is-readable.md`. Branch `issue/899-w8b-21b-relink` from 21b1a's pushed head 05f829c69. `origin/dev` 454ef4c6f was already merged in (60f80972a, 21b1a's merge); fetched again before proving and before handing back, unchanged, so no merge commit this piece. The mac's piece: U4b3 relink-2. No `contracts/` or `mac-app/` change.

## For PROGRESS

- `UndoFormat.ReadOp` reads `linkShaBefore` and `linkShaAfter` (optional strings; a non-string makes the op unreadable) onto `UndoOp.LinkShaBefore`/`LinkShaAfter`.
- `UndoFormat.ShapeIsKnown`, the `Move` case: exactly one content form, `sha`, `listingSha`, `linkSha`, or the pair counted as ONE, checked by the new `UndoFormat.RelinkShapeIsKnown` (the mac's `UndoOp.relinkShapeIsKnown`, `UndoFormat.swift` 1162): a `move`, never a capitalisation-only one (`moveApart` and `setAside` are kinds this version does not know, so already unreadable), both blob names, different, the op's listed `blobs` exactly the two. Either key alone is unreadable; `linkSha` (or `sha`, `listingSha`) beside the pair is two content forms, unreadable. A relink from `from` to itself fails the existing overlap rule (`IsCaseOnlyMove` is false when the spellings are equal), so the mac's held "relink where the link stands" rows read notReadable here.
- `UndoCheckContractTests`: `OpOf` turns `linkTargetBefore`/`linkTargetAfter` into the two hashes and, unless the case gives its own, `blobs` (deduplicated, so "the two texts the same" carries one); `LaysALinkWithItsTarget` routes cases carrying `linkTarget`, `linkTargetBefore` or `linkTargetAfter` with a link in `current` to the symbolic-link theory, and the same predicate (not `op.LinkSha`) tells `PlaceAt` to lay each side's link with the text the case gives THAT side. `cannotBeRead` on a link side goes through the replay's existing seam (the `unreadable` set handed to `UndoCheck.WholeStateOf` as `cannotRead`), no permission trick. The "one text missing from blobs" row (raw shas, no `linkTarget…`) stays in the plain theory, its link laid as "something else".
- `UndoRelinkTests`: 21b1's inert test turned round (`ARelinkFromTheJournalIsReadable`); `ARelinkOfAnyOtherShapeIsNotReadable` (eleven barriers: texts the same, a text missing from blobs, a third blob, either key alone, `linkSha` beside the pair (Windows' pin of relink-2's "For the director" 1, option a; no shared row), `sha` beside the pair, a text that is not a blob name, a `moveApart`, a capitalisation-only move, a move to its own place); `APlainLinksCapitalisationOnlyMoveIsStillReadable` (the barrier is the relink's own).
- `UndoCheckContractTests.ARelinkBarrierRowIsNotReadableForTheReasonItsNameGives`: the two barrier rows read the pair, and the same row with only its fault mended (a second text; the missing blob) is readable, so each is notReadable by the shape check for the reason its name gives, not because the keys went unread. Written after the product change, as a check (it would have failed before on `Assert.NotNull(op.LinkShaBefore)`).

## For documentation 12

The "What W8 owes from U4b3 relink-2" paragraph can now say it is built: `UndoFormat.ReadOp` reads the pair, `ShapeIsKnown` counts it as one content form through `RelinkShapeIsKnown`, and the check replay lays each side with its own text. Correction to that paragraph's last sentence: the two barrier rows now pass by the shape check (the pair is read), no longer because `ReadOp` ignores the keys.

## Must-fail lines (`vm-tools/guest/899-w8b-21b2-mustfail.json`, run w8b-21b2-a)

1. the pair counted as two content forms (`contents += 2`): RED, 7 of 11 (`ARelinkFromTheJournalIsReadable` "Assert.True() Failure", `EveryLinkMoveCheckCase` rows "Strings differ": notReadable).
2. `linkSha` beside the pair read as readable (`LinkSha` left out of the count when the pair is there): RED, 1 of 11 (`ARelinkOfAnyOtherShapeIsNotReadable`, "linkSha beside the pair").
3. the replay laying the `to` side with the `from` text: RED, 1 of 10 (`EveryLinkMoveCheckCase`, "Strings differ": the new link at its new place read changedSince).

RED 3 of 3; restored 669 of 669, HEAD-AFTER same, status clean.

## Runs

- w8b-21b2-a (PC, ref c1365bd97, red ref d27e15163; lock free, taken 08:17, released by its own run): **red 10 of 344** at the tests-first commit (`UndoRelinkTests`, `UndoCheckContractTests`, `NamedGapLedgerTests`): the seven relink check rows unheld ("Assert.Equal() Failure: Strings differ", notReadable), `ARelinkFromTheJournalIsReadable` (Assert.True, line `Assert.True(read.Readable)`), and the "linkSha beside the pair" barrier (read as a plain link's move). Both builds 0 errors; **669 of 669 passed** (`UndoCheckContractTests`, `UndoFormatTests`, `UndoRelinkTests`, `UndoJournalReadingTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`); must-fail RED 3 of 3; restored 669 of 669.
- w8b-21b2-b (PC, ref c980704ab, the barrier-reason check added): both builds 0 errors; **671 of 671 passed**, the same classes; lock taken and released by its own run.

## Ledger

`UndoCheckCases`: the seven "U4b3 relink, a link's move that changes its text: …" rows pass and leave. `Reason899W8RelinkedLink` stays (13 recovery rows): its sentence no longer says `ShapeIsKnown` finds no content form or that the replay does not know `linkTargetBefore`/`linkTargetAfter`; it says Windows reads, judges and swaps the relink and that 21b3 builds recovery (`withARelink`, `relinkStaged`, `relinkRenamedIn`). No other reason named what this piece taught (`Reason899W8bLinkedClassPage` names the relink only as "Reason899W8RelinkedLink first", still true until 21b3). No key added to any `KeysChecked` (the check replay has none); no check row is still held under a reason carrying the two keys.

## Self-check

1 to 6 (NIGHT3): own classes only on the PC under the turn lock, no UI class, no whole suite; tests first in their own commit (d27e15163), seen red; must-fail recorded; notes written. 7 to 10: no fixture row; writer-scan count unchanged (no writing call added), `UndoWriterScanTests` green; no riding lows; no action step. 11: the seven rows pass and are out of the ledger, the reason sentence rewritten, the constant kept (13 recovery rows use it). 12: no `KeysChecked` key added. 13: one function per rule: `UndoFormat.RelinkShapeIsKnown` for the relink's shape, `UndoOp.IsCaseOnlyMove`/`PlacesOverlap` for the places, `IsBlobName` for names. 14: no run left going, the lock taken only when free, released by its own runs.

## Left for the next piece

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- 21b3: recovery (`withARelink`, the stop points), `Reason899W8RelinkedLink` goes. 21b5: the journal writer for the pair (`UndoActionStep` writes `linkSha` only today).

## For the director

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- Nothing parked.
