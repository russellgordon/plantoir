Its handing-over order removed by #1055 W3; the rest by W4.

# #899 W8b-21a6: an action step hands a link move's old place over (Windows #949)

Brief `vm-tools/briefs/2026-11-27-899-w8b-21a6-action-step-hands-a-place-over.md`. Branch `issue/899-w8b-21a-handed-over-place`, on 02bac1c34 (21a1 to 21a5, 21c, 21c2), `origin/dev` 6dc36fcea already merged in; `git merge origin/dev` was up to date before proving and again before handing back (no merge commit needed). Tests first 441807abe; product ccc292a54.

## For PROGRESS

- `UndoActionStep` (the door for teacher actions) with 21's `MoveLink` now hands the place a link's move leaves over, as the mac's `JournaledStep` does (U4b3 door-6). No teacher action uses it until W8b piece 22. No ledger row.

## What was built (`Plantoir.Core/Undo/UndoActionStep.cs`, `UndoOpKinds.cs`)

- **The left place reads as free** (`IsLeftFreeByALinkMove`, the mac's `isLeftFreeByALinkMove`): a planned link move starts there, none ends there, and nothing is planned there yet. `Exists` is false, `ReadTextIfAny` null, `ReadText` throws `FileNotFoundException`; never read through the leaving link.
- **A write there is a new file** (`Plan`): before null, never read through the link (a Windows link would give the target's bytes, a mac one an `IOException`), named from the folder above it as the caller named it. `RecordableChanges` no longer calls such a place "a link, cannot be named"; the door hands it over (21a1's vet). The plain write writes the place itself, never `PlaceWritten` through the link.
- **The link's new place (same folder) is the file the link leads to** (`PlannedPlace`, the mac's `placeALinkLeadsTo` and `plannedKey`), for `Write`, `WriteBytes`, `EditJson`, `Exists`, `ReadText`, `ReadTextIfAny`, `WasThereWhenPlanned`, even where the step removed the page the link moves over. `Remove` is never redirected (the mac's `remove`, `throughALink: false`). A plan at the new place of a link moved to ANOTHER folder refuses the action, `cannotTellNow`, before anything changes (the mac's `refusesAWrite`).
- **Where a link leads, for a link in the mac's form too**: `UndoLinks.FileALinkLeadsTo` follows link by link (at most 32, the mac's `MAXSYMLINKS`) from the target AS STORED (`LinkTarget`), `/` read as `\`, a relative target taken from the folder above the link, `Path.GetFullPath` (lexical, as the mac's `standardizedFileURL`); nothing is opened. So `../library/Day 2.md`, which Windows does not open, leads to the library file and is read and written there directly. Both test rows run it, recorded, Undo, Redo and unrecorded: green.
- **Handing-over order** (`InHandingOverOrder<T>` and `LaterLeaver`, the mac's `inHandingOverOrder` and `laterLeaver`): a filler goes straight after a later leaver of its place, by `UndoOp.PlaceLeftBy`, `PlaceFilledBy`, `HandsOverAsAMove` and `PartInside`, the pieces of 21a1's `UndoOp.Handovers`. Recorded: `MakeAsOps` orders its whole op list, op by op, after building it (folder moves, the pages in the one page order, trees, recomputes), as the mac's `makeAsOps`. Unrecorded: `WritePlainlyQuietly` orders its swap targets by one op each (a move's own, a file's as one `writeFile`, `WholeFileOp`, the mac's `wholeFileOp`; a tree none), places spelled as slashed full paths. A step with no such pair keeps its order exactly (pinned).

## One function per rule (W8 COMMON self-check 13)

- "At or exactly this place": `UndoOp.PartInside` (`LinkMoveEndingAt`, `LinkMoveStartingAt`, `StaysInItsFolder`, `LaterLeaver`).
- "Is this a link": `UndoLinks.Look` (`FileALinkLeadsTo`, and the existing `RecordableChanges` look).
- Leaver and filler: `UndoOp.PlaceLeftBy` / `PlaceFilledBy` / `HandsOverAsAMove`, the same as `UndoOp.Handovers`.
- `CourseConfiguration.FileALinkLeadsTo` (U4a's Save) still follows with `File.ResolveLinkTarget`, so a settings file that is a mac-form link is planned at the link and refused by the door. Not changed here (it changes Save's behaviour for a link leading nowhere, which `ResolveLinkTarget` refuses and the mac writes); for the director: whether it should call `UndoLinks.FileALinkLeadsTo`.

## Review 1 of window D, folded in

- **LOW 1 done.** `UndoRecovery.FileStates` no longer asks "leads out of the working folder" of a whole op's side its handover judges free (`LeadsOut`): that side is asked only of the folders above it (`UndoPlaces.StaysInsideAbove`). Test `UndoHandedOverPlaceTests.RecoveryJudgesAFilesMoveWhoseHandedOverPlaceALinkLeadingOutNowFillsAfter` (a file's move Day 4 → Day 5, then a link leading out moved Day 3 → Day 4, killed after both swaps): RED at the tests-first commit (`Assert.Equal() Failure: Collections differ`, the file's move `Neither`), green after; must-fail row 5.
- **LOW 2 done.** `Reason899W8bLinkedClassPage` (`NamedGapLedger.cs` 486) no longer says the door is to come: it names the door (21a1 to 21a5, 21c) and the step's handing over (21a6) as built. Its one escaped quote (`\"Never refuse\"`) is a correct C# escape.
- LOW 3 (documentation 12) left to the director. LOW 4 (harness kills) not in this piece.

## For documentation 12

- Under "What W8 owes from U4b3" (the door-6 bullet): Windows' `UndoActionStep` now does what door-6 asks of the action step: the place a link's move leaves read as free until written and written as a new file, the link's new place (same folder) read and written as the file it leads to (`UndoLinks.FileALinkLeadsTo`, from the target as stored, so a link in the mac's form too), a write at a link moved to another folder refused `cannotTellNow`, and the ops, recorded and unrecorded, in handing-over order. What remains of that bullet is piece 22's Insert Class.
- Windows has no `markdownFiles(under:onDisk:)` on the step (the mac's lister that leaves a moved link out at both names); piece 22 must not list the left place or the link's new place through the disk when it walks pages to rewrite `[[links]]`.

## For W8b piece 22 (what 22 must know)

- Plan Insert Class's linked later class as the tests do (`UndoActionStepLinkTests.PlanInsertClassAtALinkedDay3`): highest first, `Write(next)` + `Remove(old)` for a plain class, `MoveLink(old, next)` for a linked one, the date written by `Write(next, …)` AFTER the `MoveLink` (it lands in the file the link leads to, even though the class below's rename removed `next`), the new class `Write` at the place the link left.
- A write at the link's new place planned BEFORE its `MoveLink` is the page there, not the link's file; plan the move first.
- The door's plan and the swap still read a page through a link (21c2); `UndoActionStep` itself no longer does at a link move's two places. Whether `UndoCurrent.Read` can stop following links everywhere is still 22's question (21c2's note).
- `Remove` at a link's new place removes what is at that place, never the file it leads to.

## Must-fail lines (`vm-tools/guest/899-w8b-21a6-mustfail.json`, run w8b-21a6-a)

1. the leaving link's place read through the link (`IsLeftFreeByALinkMove` never true): RED, both `UndoActionStepLinkTests` theories, both rows (`Assert.False() Failure`, `Exists` at Day 3).
2. the write at a left place planned with the link target's before: RED, the same four (Windows row `Assert.False()`, `WasThereWhenPlanned`; mac row `IOException` reading through the link).
3. ops left in planning order, recorded and unrecorded: RED, the same four (the door and the plain swap refuse the step).
4. the link's new place written over the link instead of the file it leads to (`PlannedPlace` redirect removed): RED, the same four (`Assert.True() Failure`, `Exists` at Day 4).
5. review 1 LOW 1, a side judged free resolved through what fills it: RED, `RecoveryJudgesAFilesMoveWhoseHandedOverPlaceALinkLeadingOutNowFillsAfter`.

RED 5 of 5.

## Runs

- w8b-21a6-a (PC, ref ccc292a54, red ref 441807abe): red 6 of 7 (`UndoActionStepLinkTests` both theories at both rows, the other-folder refusal, the LOW 1 row; the no-handover order pin green, as it must be); both builds 0 errors; **1470 of 1471 passed, 1 skipped** (`~Plantoir.Tests.Undo`, `NamedGapLedgerTests`, `ActivityTrailWiringTests`, `ContractTests.SharedRules_ActivityTrailEvents_Exist`; `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoActionStepTests`, `UndoMakeRoomStepTests` among them); must-fail RED 5 of 5; restored 1470 of 1471 (HEAD-AFTER same, status clean); lock released.

## Left for the next piece

- Nothing of this invariant. Insert Class itself is piece 22.

## For the director

- Nothing parked; no `contracts/` or `mac-app/` change.
- Optional: `CourseConfiguration.FileALinkLeadsTo` could call `UndoLinks.FileALinkLeadsTo` (above).

## Self-check

1. Broke each fix and watched it fail: must-fail 5 of 5.
2. No timed waits.
3. Failure paths: a write at a link moved to another folder refuses `cannotTellNow` before anything changes; a step that cannot be ordered (a circle) keeps the order the bound reached and the door refuses it; no new sentence a teacher reads.
4. `dev` merged (up to date, 6dc36fcea).
5. No number tuned by trial (32 hops is the mac's `MAXSYMLINKS`; n² passes is the mac's bound).
6. Scope: `UndoActionStep.cs`, `UndoOpKinds.cs` (`UndoLinks.FileALinkLeadsTo`), `UndoRecovery.cs` (LOW 1), `NamedGapLedger.cs` (LOW 2), two test files, these notes, the must-fail and launch files.
7. No fixture row (no action converted).
8. Writer scan unchanged (no new writing call).
9. Riding lows: LOW 1 and LOW 2 fixed, LOW 1 with a test seen red.
10. Every before is read at plan time; the left place's before is absent by rule.
11. to 12. No held row, no key added.
13. One function per rule: above.
14. No run left going, the lock released by the run that took it.
