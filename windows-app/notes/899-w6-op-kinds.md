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
- PC `899w6-c3` (head 400083f60): the Undo classes 665 passed, 1 not run (the `[DenyBitesFact]` that cannot bite over SSH), 0 failed. Must-fail (`vm-tools/guest/899-w6-mustfail.json`, 20 sabotages): all red (`899w6-c1`, and `899w6-c3` for three made real: the contract's link rows and its key-written-twice row pass a reader that follows links or picks the first duplicate only because the content they lead to differs or the read-back refuses, so `AJunctionToTheVeryContentIsStillNeverFollowed` was added and the duplicate sabotage picks the last one). Killed-step harness (`Plantoir.UndoHarness kinds-kill`): 132 runs, every one whole, outside and inside OneDrive: `documentation/12-windows-app.md` → "What Windows has built: W6, the op kinds".

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
  a new value spelled byte for byte as the mac's `JSONSerialization` writes it,
  a key written twice on the path, or a whole number of 2^53 or more, refused.
  Values are compared through doubles as on the mac, not with
  `JsonNode.DeepEquals` (exact decimals would disagree with the mac at 2^53+1).
  Three things were measured on the mac (macOS 26.7.3, 2026-11-20) through the
  mac's own code (`vm-tools/guest/899-w6-mac-editjson-runner.swift`: the mac's
  `UndoJSON`, `UndoJSONMember` and `UndoJSONBytes` verbatim, run as its contract
  runner runs them) and are now contract rows (`undo.editJSONCases`, 8 new, 16
  in all, the mac's `UndoJournalContractTests` green on them and red on a
  changed row):
  - **Key order** (`UndoMacKeyOrder`) is not ordinal: a key is read as pieces
    (a run of digits, or one character); punctuation first in a fixed order (a
    space, then `_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # % ` ^ + < = > | ~ $`),
    then digit runs by their number (9 before 10), then letters ignoring case;
    keys equal so far are told apart at the first piece that differs, a
    lowercase letter before its capital and a run with fewer zeros in front
    first (`1A`, `01a`; `ab`, `aB`, `Ab`). 6,000 random sets of printable ASCII
    keys came out in exactly this order. Rejected: ordinal (`"10","9","B","a"`
    where the mac writes `"9","10","a","B"`). Not pinned: a key with a
    character beyond ASCII.
  - **Numbers** are C's `%.17g` (`UndoJson.SpellNumber`): 0.1 is
    `0.10000000000000001`, 1e-07 `9.9999999999999995e-08`, a whole number below
    2^53 its digits, negative zero `0`. Rejected: .NET's shortest round trip
    (`"R"`), which wrote `0.1` and `1E-07`.
  - **The read-back** goes through the mac's reader, which reads a spelling in
    fixed notation with more than 17 digits (leading zeros of the whole part
    dropped) as an `NSDecimalNumber` whose double is its digits summed in 16-bit
    pieces and then divided by ten once per place (`UndoJson.ReadAsTheMacReads`:
    1,729 of 1,729 such spellings bit for bit, and 4,244 of 4,244 others the
    nearest double). So a member set to 0.0001234 (spelled
    `0.00012339999999999999`, read back there as `0.00012340000000000002`) is
    refused on both platforms, as changed since; 0.08129913717470501 is written.
    A file's numbers are read the same way when a member is judged. Not pinned:
    a spelling with an exponent and more than 17 digits.
- **A file starting with a UTF-8 byte-order mark** is read as the mac reads it
  (Foundation passes over the mark; measured), so its member is judged as on
  the mac (the verdict before a write), and it is never moved, as on the mac,
  whose scanner starts at the mark: refused as changed since. A space before
  the mark is not JSON on either. No contract row can carry it: the mac's
  runner reads each case through `JSONSerialization`, which drops a mark at the
  start of a string (measured), so `UndoOpKindsContractTests` pins it.
- **external.** `preference:<name>` is a member of the app's own settings
  (`UndoAppSettingsPlaces`), read from `settings.json` as it is on the disk now
  (following `--state-dir`), as the app's typed settings read it, never from a
  process's copy, which may be older (`plantoir-mcp.exe` holds its own). A set
  replaces exactly that member with exactly the value (a list or a dictionary
  replaced whole), into the file as it is now: read, the one member changed,
  the result checked to read back as the value, then written whole by a
  temporary `settings.json.undo-writing` and one rename that replaces, so it
  happened or did not; on a mismatch (a number for a text setting) nothing is
  written and the set is refused couldNotWrite, the file byte for byte as it
  was. A file the app's own reader cannot read is never written over. The copy
  the process runs on is then given the same member, so its next save keeps
  it. Rejected (the first review of W6, MEDIUM): `PopulateObject` on
  `AppSettings.Current` and its `Save()`, which appended to lists, merged
  dictionaries, saved before checking, and wrote a process's older copy of
  every other setting over the file. A name the store does not have is cannot
  tell; a typed setting cannot be set to "not set" (refused couldNotWrite).
  **Owed by W8**, which decides which settings a step records: a set made by
  one process is not seen by another process's copy until that process loads
  again, so a set recovery makes in `plantoir-mcp.exe` is undone by the app's
  next save of its own copy unless W8 has the app re-read the member (or keeps
  every external op in the app's process). Nothing writes an external op
  before W8.
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

Settled as, in each place: done 26, undone 22, rolled back 14, failed 4 (no step was left in flight or interrupted). A run's
three processes took 0.5 to 1.3 s end to end. The scratch folders were
removed after the run.

### For W7: shadow leftovers (the first review of W6, LOW 3)

In shadow, recovery never tidies a working folder and `TidyClosedSteps` runs
live only (the mac's rule, unchanged here). So a `removeTree` killed after its
folder went aside leaves the teacher's folder under its staged dot name
(`.<name>.plantoir-undo-<step label>-orig`), which Explorer does NOT hide (a dot name is
not hidden on Windows), and a `-gone` folder half deleted, until the switch
goes on; the same if the step is pruned before a put-back succeeds. Nothing
reaches this before W7, because no teacher action writes a tree op through the
door in shadow yet. Before any teacher action sends a tree op through the door
in shadow, W7 must prove, on the PC's disk and inside OneDrive, with the kill
harness: a take-out killed at every point, in shadow, leaves the teacher's
folder in its place or in a visible place the teacher is told about, never
under a staged name; a `-gone` remnant left in shadow is finished or reported
at the next live recovery; and pruning a shadow step never strands either.
Until W7 proves that (or the rule changes for both apps), tree ops stay out of
shadow writes.

### For W7: the "(kept by Undo)" folder is a real folder (LOW 4)

`<name> (kept by Undo)` (and `(kept by Undo 2)` and on) is an ordinary folder
beside its place, so under `courses/` it is part of the course: a build and a
deploy include its pages. That follows Russell's ruling of 2026-11-19 and the
mac; the director is telling him. No sentence on screen says it yet (the only
sentence is the trail line `undo found a folder set aside`, contract wording);
whatever sentence a teacher is first told about a kept folder (W7 on, with the
mac) must say plainly that it is a real folder that a build and a deploy
include, until a ruling says otherwise.

### For W7: the front page re-derived twice (from W4's re-review)

In shadow the door, not the action, re-derives the front page: a W7 action that
keeps its own front-page write and also routes a `recompute` through the door
writes the page twice. W7 keeps one: the action's own write, or the door's.

### For documentation 12: the owed-pieces table

In "The owed pieces" table (about lines 16931 and 16938 of
`documentation/12-windows-app.md` on `dev` 2ba8490e7):

- the **W4** row is marked BUILT (2026-11-20), as W2a, W2b and W3 are: where the
  list lives (following `--state-dir`), the writer scan, the switch (off), and
  recovery at every launch of the app and of `plantoir-mcp.exe`
  (`UndoAtLaunch.Recover`);
- its promise "`madeBy` from `AssistWorkspace.Surface` (L1)" is not built by W4
  and moves to the **W7** row: the PC's `plans/899-plan.md` puts `madeBy` (a
  `--door menu|builtIn` argument from the helper's role) beside the shadow
  recording of publish and hide, which the plan review's M1 moved to W7;
- "recovery at a windowed launch" is removed from the **W11a** row (W4 calls
  `Recover()` at every launch already).

### Pruning stops at a step it keeps (the final sweep of W3 and W4)

`UndoJournal.Prune` stopped writing for a step left in flight for a
re-deriving recovery (W3's review, LOW 2) but went on with the `pruned` lines
`UndoPruning.Decide` had queued behind it, so newer steps were pruned while an
older one was kept, against "one oldest run only, never a step newer in
sequence than one kept". The run now stops there
(`UndoRecoveryReviewFixesTests.PruningStopsAtAStepLeftForARederivingRecovery`).
The mac has no such hole: its `UndoRecovery.prune` has no arm that keeps a
step, and closes such a step `interrupted` as the contract's limits say. No
contract row covers a kept step (the stack cases have none), so the test pins it.
