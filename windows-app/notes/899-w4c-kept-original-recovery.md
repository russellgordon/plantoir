# #899 W4c: a kept original puts a page back; nothing that is an only copy is deleted

Branch `issue/899-w4c-kept-original-recovery`, on W6 (`origin/issue/899-w6-op-kinds` 368e5377d) with `origin/dev` 5cf38d656 merged in (merge commit a32ee10de; the ledger's two conflicting hunks resolved by keeping W6's built rows out and every U3b and U3c hold).

## For PROGRESS

- W4c (the Mac's U3c on Windows) is built: recovery and the door's Undo and Redo put a page back from the step's own kept original (`-orig`, `-<n>-orig`) when its SHA-256 is exactly the journal's, write both of the page's contents back into the list inside the lock before the swap, keep beside the page what the list will not take, and answer "cannot tell now" (list kept) for a kept original that cannot be read just now. Every tidy (recovery's first, the settled one, a could-not-put-back closing, a closed step's, pruning's) keeps a kept original that is the only copy of what it holds. A swap never removes, overwrites or reuses a kept name: it takes the next free `-<n>-orig`, kept exclusively.
- Four trail events: "undo could not put back a change that stopped", "undo kept what a page held", "undo kept what it replaced", "undo refused for a change left part way".
- The ledger: the 4 `ActivityTrailEvents`, 12 `UndoStackCases` ("U3c: …") and 10 `UndoRecoveryCases` held under `Reason899W4c` now run from the JSON; the reason is gone. Still held: `Reason899W4cWithW7` (2 rows, W7's rollover calls) and `Reason899W4cKeptAlert` (`keptTitle`, `kept`, `showKept`).

## For documentation 12

### W4c: kept originals (the Mac's U3c)

- `UndoCheck.Plan(keptOriginal:, keptOriginalUsed:)`: for a `writeFile` whose blob the list no longer holds, `UndoRecovery.KeptOriginal` looks through the step's own kept originals beside that page (any label: apply, undo, redo, `-recover`) and gives the bytes of the first whose SHA-256 is the one wanted. Never by name or file times. One that cannot be read now (`UndoCurrent.CannotReadNow`: a permission, another program holding it, a OneDrive placeholder) is reported; the door and recovery then answer `cannotTellNow`, the list kept.
- `UndoRecovery.StoreWhatKeptOriginalsGive` (inside the lock, before the swap): the kept bytes as their blob, and what the page holds as the other direction's blob when it hashes to the recorded sha. It answers `UndoWhatTheListCouldNotTake`: `OutgoingOf` (the swap keeps those pages' originals: `UndoSwap.Swap(keepingTheOriginalsOf:)`), and `KeptOriginalsHolding` (no tidy removes a kept original with those bytes: `TidyLeftovers(keepingCopiesHolding:)`).
- `UndoSwap.TidyLeftovers(keepingOnlyCopies:, unlessTheListHolds:, keepingCopiesHolding:)`: a kept original FILE goes only when its bytes are its page's (`IsACopyOfItsPlace`) or exactly what the list gives for its page undone or redone from what the page holds now (`UndoRecovery.ListHolds`).
- Settle's order: the first tidy keeps every kept original that differs from its page; the plan; at a ready plan, the tidy with `ListHolds`, then the store, then the put-back's swap (keeping originals only for an undo or a redo, which stay on the list); after the step is written, the settled tidy and, for any kept original left, "undo kept what a page held" with "because it differs from what the list recorded" or "because the list no longer holds a copy of it". A could-not-put-back closing writes "undo could not put back a change that stopped", naming the kept originals read after its tidy.
- The swap's keep: `-orig`, then `-2-orig` and on, the first name `UndoLinks.Look` finds empty; `UndoStagedFile.Keep` never copies over a name a hard link was refused for (80 or 183), and its copy is exclusive.
- `UndoTrailLine` carries `Kept` and `NoLongerInTheList` so a test matches the line against the disk.
- Test seams: `UndoSeams.PutBackFailsAt` (the Mac's `putBackFailsAt`). The replays' `contentCannotBeStored` and `beforeContentGoneAndCannotBeStored` put a real deny entry (create files and folders) on the list's content folder or one prefix folder; `makeTheKeptOriginalUnreadable` and `keptOriginalUnreadable` deny reading the kept file (`UndoDenials`, removed before the checks).

### Where W7 connects

Today's class's "Show on Front Page" does not go through the door on Windows yet (W7). The part-way outcome W7 needs is the door's `Refused` with `LeftPartWay`, then recovery, whose "undo kept what a page held" line names the kept file. The alert keys `keptTitle`, `kept` and `showKept` stay held until W7 wires the action and the alert is built from the measurement below.
