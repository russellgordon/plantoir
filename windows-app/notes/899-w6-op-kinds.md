# #899 W6: the Mac's U2b op kinds, on Windows

Notes for the director to fold into `windows-app/PROGRESS.md` and
`documentation/12-windows-app.md` at the merge window (NIGHT3-COMMON: writers
do not edit either file). Plan: `vm-tools/reference/899-w6-plan.md`.

## For PROGRESS

## 2026-11-20 — Undo and Redo, W6: the six op kinds U2b defines (#899, #949)

Branch `issue/899-w6-op-kinds` (on W4 with its review fixes, `dev` 2ba8490e7 in it). Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH. Nothing a teacher sees changed; the switch stays off; no action goes through the door yet (W7 on).

- Reader (`UndoFormat`): `replaceText`, `editJSON`, `move`, `createTree`, `removeTree`, `external` read with the mac's shapes (`shapeIsKnown`), `opKinds.wholeOps` on the step, places compared without case, `element` and `heldBy` unreadable, a listing's hash among the blobs kept, a step of external ops alone needs no working folder.
- `UndoJson.cs` (any JSON, compared as the contract says, exactness beyond 2^53, the compact spelling), `UndoOpKinds.cs` (`UndoHunk`, `UndoJsonMember` with its byte scanner, `UndoTreeListing`/`UndoTreeReading`, `UndoLinks`, move sides, `IUndoExternalPlaces` and the app's `UndoAppSettingsPlaces`).
- Check, plan, swap and recovery for each kind (`UndoCheck.WholeStateOf`, `UndoSwapChange`, `UndoSwap.SwapAWholeOp`, `TidyLeftovers` putting a folder set aside back or keeping it as `<name> (kept by Undo)`, `-gone` before a delete, `UndoRecovery.FoldersKeptAside`, the `undo found a folder set aside` trail line).
- Contract from the JSON: all 110 `checkCases` (move sides, trees, links, preferences placed on the disk), the 5 `listingCases` and 8 `editJSONCases` (new, `UndoOpKindsContractTests`), U2's 19 `stackCases`, the 15 traces holding a `move`, U2's 21 `recoveryCases`. Every W6 entry left `NamedGapLedger`, `undo found a folder set aside` with them.
- PC `899w6-b2`: the Undo classes 664 passed, 1 not run (the `[DenyBitesFact]` that cannot bite over SSH), 0 failed. Must-fail: `vm-tools/guest/899-w6-mustfail.json`. Killed-step harness (`Plantoir.UndoHarness kinds-kill`): 132 runs, every one whole, outside and inside OneDrive: `documentation/12-windows-app.md` → "What Windows has built: W6, the op kinds".

## For documentation 12

### What Windows has built: W6, the op kinds (#899, #949)

Piece W6 (branch `issue/899-w6-op-kinds`, on W4, 2026-11-20) reads, checks,
moves and recovers every op kind the mac's U2b gave the journal. Nothing a
teacher sees changed: the switch is off, and no action writes these kinds
before W7 (U3) and W8 (U4).

- **Whole ops.** A move, a tree and an external op are judged and changed as
  a whole against the disk, never folded into another op's file
  (`opKinds.wholeOps`); a step where two ops share a place is a barrier. A
  move is judged as a PAIR: an undo after a deploy wrote a new marker where a
  rollover's was takes nothing back and keeps both. A move is one
  `MoveFileEx` WITHOUT `MOVEFILE_REPLACE_EXISTING`, the pair re-read just
  before it. A move that changes only case (`a.json` to `A.json`) is a step
  this version cannot read, because places compare without case: NTFS would
  otherwise see both places as one.
- **Links on Windows.** The mac's `lstat` is three questions here
  (`UndoLinks`): a reparse point whose tag is a NAME SURROGATE (a junction,
  a symbolic link, WSL's links) is a link, never followed, "something
  else"; a reparse point that is not (OneDrive's Files On Demand files and
  folders) is the teacher's own and is read like any other, so a folder in
  OneDrive is not a change since merely for being in OneDrive (rejected: any
  `FILE_ATTRIBUTE_REPARSE_POINT` as a link, which would have read every
  OneDrive folder as changed and cleared the list). A placeholder whose
  content is not on the disk fails its read, which is cannot tell.
- **Trees.** A folder to make is built beside its place under its staged
  `-new` name and renamed in, never over anything. A folder to take out is
  renamed aside to `-orig` FIRST and its listing checked there, then, once
  every change is in, renamed to `-gone` and deleted, so a delete cut short is
  finished by recovery and never put back half emptied. Files inside are
  removed by handle with the read-only attribute ignored (a file may be a hard
  link to a page elsewhere). A folder with a file another program holds open
  cannot be renamed on Windows: taking it out is refused `fileIsInUse`, the
  folder whole in its place, the list kept (`UndoOpKindsContractTests`).
- **A folder set aside by a stopped step** is never deleted: put back when its
  place is free, otherwise kept as `<name> (kept by Undo)`, `(kept by Undo 2)`
  and on, the trail line `undo found a folder set aside` written just before
  the rename. A pruning hold has no trail sink, so a folder it puts back says
  nothing there; recovery and the closed-step tidy say it.
- **editJSON** changes only the member's bytes (the mac's byte scanner, ported):
  a new value spelled compactly with keys sorted ordinally, a whole number
  without a point, any other in its shortest round-trip spelling; a key
  written twice on the path, or a whole number of 2^53 or more, refused.
  Values are compared through doubles as on the mac, not with
  `JsonNode.DeepEquals` (exact decimals would disagree with the mac at 2^53+1).
- **external.** `preference:<name>` is a member of the app's own settings
  (`UndoAppSettingsPlaces`, through `AppSettings.Current`, saved at once). A
  name the store does not have is cannot tell; a typed setting cannot be set
  to "not set" (refused couldNotWrite). Which settings a step records, and
  under what names, is W8's. Nothing writes an external op before then.
- **The front page's runner** (`UndoSectionFrontPage`, from W4's review)
  serves the recovery cases' re-derivations.

**Measured, `899w6-b2`, Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro
26200).** One step of every kind (two pages' lines, a hunk, a member, a
preference in a file store, a folder removed, a folder made, a marker moved:
8 swaps), its apply, its undo and its redo, each made by a child process
killed at every step (its begin, before each of the 8 swaps, while a folder
taken out was being deleted, before its closing: 33 points), then recovered
by a second process, and again with that recovery killed before its first
put-back swap (42 of the 66 were killed there) and a third recovering:

| Place | Runs | Every place wholly before or after, all one way, as the list says | Nothing staged left | A and B agree |
|---|---|---|---|---|
| `C:\vm-setup\…\scratch` | 66 | 66 | 66 | 33 of 33 |
| `%OneDrive%\plantoir-w6-scratch-…` (OneDrive running) | 66 | 66 | 66 | 33 of 33 |

Settled as: Done 52, Undone 44, RolledBack 28, Failed 8 (per place). A run's
three processes took 0.5 to 1.3 s end to end. The scratch folders were
removed after the run.
