# #899 W8-10b: thinning kept copies to one per content (Windows)

Branch `issue/899-w8-10b-thinning-kept-copies`, built on `issue/899-w8-10-content-gone-calls` (d0a7732ee). No `origin/dev` merge was made: the brief names that branch as the base, and pieces 9 and 10 are unmerged on `dev`. No `contracts/` change.

## For PROGRESS

- Undo (#899 W8-10b): after an Undo or Redo through the door, the step's kept copies beside a page are thinned to ONE per content, as the mac's `UndoRecovery.removeSupersededKeptCopies` does. Seven moves with both contents gone from the list and the list taking no new file now leave two files (one per content) beside the page, not eight.

## For documentation 12

- In "What W8 copies from U4a", LOW 4 (b): Windows now thins kept copies (`UndoRecovery.RemoveSupersededKeptCopies`, called in `UndoDoor` after `Finish` and before `SayWhatItKept`, only when the list could not take some outgoing bytes, as the mac's door at `UndoCheck.swift:2249`). The rule, copied: per page, the step's kept originals are read in name order (ordinal); for each content the copy made by this move's label is kept, otherwise the first by name; every other copy of that content is removed by `UndoStagedFile.RemoveByName`; a copy that cannot be read is never touched, and a content held once is never removed. Recovery's own put-back path (`UndoRecovery.cs`, about line 1210) does not call it, because the mac's recovery does not either; only the door does.

## Tests that failed first

- Not watched red before the product change: the product and the tests went into one commit (12f0d2a8f). Must-fail rows 1 to 3 stand in for it: each takes the product back to the state the test was written against (thinning off; the wrong copy kept; an only copy removed) and the test goes RED.

## Must-fail lines

`vm-tools/guest/899-w8-10b-mustfail.json`, runs `899-w8-10b-b` (rows 1 and 2) and `899-w8-10b-c` (row 3, re-anchored: its first anchor occurred twice in `UndoRecovery.cs`, so `-b`'s row 3 did not build and is not counted), at 6bf93c15e:

- Row 1, thinning switched off: RED, 2 failed of 132 (`UndoThinningKeptCopiesTests.UndoAndRedoAgainAndAgainKeepOneCopyPerContent` and the stack (b) row, the only two that move through the door with both contents gone).
- Row 2, the newest copy removed instead of the older one: RED, 1 failed of 2 (`TheNewestCopyIsKeptAndTheOnlyCopyOfAContentIsNeverRemoved`).
- Row 3, the only-copy check broken: RED, 1 failed of 2 (the same test).
- **3 RED of 3.** Each restored byte for byte: restored runs passed, HEAD unchanged, `git status` empty.

## Runs

- `899-w8-10b-a` (PC, 12f0d2a8f): did not build (`UndoSwap.RemoveByName` is `UndoStagedFile.RemoveByName`); nothing counted from it. Lock taken and released by this run.
- `899-w8-10b-b` (PC, 6bf93c15e, classes and must-fail): both builds 0 errors; **276 of 276 passed** (`UndoThinningKeptCopiesTests`, `UndoStackContractTests` with the (b) row run from the JSON, `UndoDoorTests`, `UndoStoreTests`, `UndoRecoveryTests`, `NamedGapLedgerTests`, and the scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests`); must-fail rows 1 and 2 RED. Lock taken and released by this run.
- `899-w8-10b-c` (PC, 6bf93c15e, must-fail row 3 only): RED; restored 2 of 2. Lock taken and released by this run. Nothing left running.

## Left for the next piece

- Nothing of this piece.

## For the director

- Nothing parked.

## Self-check

1-6 (NIGHT3-COMMON): one invariant only (thinning after a door move); no interim state; nothing a teacher sees changed (no new sentence; the kept line names what is left); no timed waits; no invisible controls; committed small, pushed with gpush.
7. The (b) row runs from the JSON and passes; it is out of the ledger; the U3c comment says it went with `Reason899U4aThinning`.
8. Writer scan: `RemoveByName` is the swap's own staged-file removal already used by the door's tidy; `UndoWriterScanTests` passed (run `-b`).
9. No riding lows named in the brief.
10. Not a daily action: no file order or plan-time before involved.
11. Held row passes and is gone; `Reason899U4aThinning` removed (no other use); no other reason named the thinning; the third accepted gap wording ("is not built on Windows yet") is gone from `RunAsTheLedgerSays`, and `CheckTheFilesKeptBesideThePage` is now the plain count.
12. No key added to a `KeysChecked`. Removing the accepted wording could move a still-held stack row that stopped at it: only the (b) row used it (the wording was added by piece 10 for it alone), and the stack class passed with the rest held (see Runs).
13. One function per rule: kept files found by `UndoRecovery.KeptOriginalFiles`, label by `UndoSwap.IsStaged`, content by `UndoCheck.Sha`, read by `UndoCurrent.Read`, removed by `UndoStagedFile.RemoveByName`. No new path comparison.
14. Each run took and released its own lock (owner line checked by the script); no run left going; no lock of another removed.
