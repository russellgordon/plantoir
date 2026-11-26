# #899 W7b2-11: W7b1's small lows, and its notes made true

Branch `issue/899-w7b2-11-w7b1-small-lows`, from `origin/dev` a03fecefd (W7b2-10 merged; the director's correction to the brief's base). `origin/dev` was fetched again before the proof and before the hand-back: it had not moved, so there is no merge commit (both times "Already up to date").

## Riding lows

1. **Review 2 L4 (wording retyped).** `TimetableMemory.KeptLead` and `KeptBesideIt` are read from `shared-rules.json` → `undo.wording` (`classDatesKeptLead`, `classDatesKeptBesideIt`) through the new `Plantoir.Core/Undo/UndoContractWording.cs`. The contract is built into `Plantoir.Core` as an embedded resource (`Plantoir.Core.csproj`, `LogicalName="shared-rules.json"`) and read once, lazily, the first time a sentence is asked for; `{place}` and `{kept}` are filled in one pass. `TheSheetsWordsForAKeptTimetableAreTheContracts` stays and is still red on a sabotage (must-fail row 1).
2. **Review 2 L5 (tidy only on a returned refusal).** `UndoSwap.Swap` runs `RemoveTheEmptyFoldersMade` in its `finally` whenever the swap gave no result (an exception) or a `Refused`; a test's kill point (`StoppedByATest`) and a `Swapped` still tidy no folder. Test: `UndoSwapTests.AnExceptionAfterAFolderIsMadeLeavesNoEmptyFolderBehind` (the existing seam `StagingWriteFailsAt` throws, asked just after `MakeTheFolderOf`; no new seam).
3. **Review 3 L1 (a held timetable said as .NET's sentence).** `ApplyReDate` wraps the plan-time `TimetableMemory.PlanInto` and turns an `IOException` into `TimetableMemory.WhyTheClassDatesCouldNotBeRead`: a sharing or lock violation is "the section's class dates are in use by another program."; any other read failure is "the section's class dates could not be read. Windows said: " and `HeldFiles.SystemWords` (the system's words without the path). A permission refusal (`UnauthorizedAccessException`) is untouched and is already `ReasonItStopped`'s plain sentence. The answer is "Nothing was changed: " and that. The wording is PARKED (below). Test: `ReDateTests.AReDateWhoseTimetableIsHeldSaysTheClassDatesAndNoHiddenPath` (the timetable itself held `FileShare.None`; pages and timetable byte for byte as they were; no `.internal`, no `section1.json`, no working-folder path in the sentence).
4. **Review 2 L3 (front page now dated).** Notes only: under "For PROGRESS" and "For documentation 12" below.
5. **Review 3 L2 (the rollover's pin).** Notes only: under "For W7c" below.
6. **The sweep's notes lows.** Checked, nothing to change: the director's fold (8f73b39a4) already rewrote `windows-app/notes/899-w7b-daily-actions.md` down to its unfolded parts (98 lines, not 152), and the first "For PROGRESS" section with "costs only the record (the re-date goes on)" and "is that same step for now" is no longer in it, nor in `PROGRESS.md` (`git grep` on both phrases: no hit outside an unrelated #899 part three line about the kept record of a publish). The two documentation passages: documentation 12 (now about line 8824) already says the replacement ("a refusal says the mac's "Nothing was changed: …"; a step the door left part way says `PublishStoppedPartWay("the section's class dates", …)` naming each kept file. The list "The pages already re-dated:" is gone"), which is true at this head; documentation 10 (about line 4455 to 4459) describes the MAC's re-date before U3 and is followed by "Since #899's U3 neither of those two can happen", which is true. W7b1's notes file is therefore not edited.

## For PROGRESS

- **W7b2-11, W7b1's small lows (#899).** `undo.wording.classDatesKeptLead` and `classDatesKeptBesideIt` are read from the contract built into `Plantoir.Core` (`UndoContractWording`), never retyped. A swap cut short by an exception leaves no empty folder it made (`RemoveTheEmptyFoldersMade` in the `finally`). A re-date or rollover whose hidden timetable file is held by another program says "Nothing was changed: the section's class dates are in use by another program." (wording parked), never .NET's sentence with the `.internal/timetable/…` path.
- **The re-date's front page is now DATED as well as repointed (W7b1 review 2, LOW 3).** It goes through the step's front-page recompute (`RederiveTheFrontPage` → `ApplyIndexChange`, `PointedAndDated`, the mac's `sectionFrontPage` maintainer) where the old code only repointed (`SectionIndex.Repointed`). Right, and the publish rule; but a byte change on the Windows front page after Re-date Classes and Roll Over: its `created` date moves with the section's classes.

## For documentation 12

- In the section on Re-date Classes… as one step: the section's front page is recomputed after the step by its rule (`sectionFrontPage`), so it is repointed AND dated (`PointedAndDated`); before W7b1 Windows only repointed it (`SectionIndex.Repointed`). A teacher's front page therefore changes its date line too after a re-date or rollover, as on the mac.
- A held timetable: the plan-time read of `.internal/timetable/section<N>.json` is said as "the section's class dates are in use by another program." (or "could not be read. Windows said: …" without the path). Note that from the Section menu, and on the first change of an assistant chat, the course's backup reads the timetable first and refuses before this (see "For the director").
- `UndoContractWording`: the first product code on Windows that reads a contract sentence at run time (an embedded copy of `shared-rules.json`, 3.7 MB, parsed once on first use). Everywhere else the wording is a constant pinned by a test.

## For W7c

- When `rollOver` is converted, the timetable file must be added to `WindowsOwnFileInTheStep["rollOver"]` (as `reDateClasses` has it: `courses/ICS3U/.internal/timetable/section1.json`, writeFile, after the recorded files, before the recompute), or that fixture row goes red (W7b1 review 3, LOW 2).

## Must-fail lines (`vm-tools/guest/899-w7b2-11-mustfail.json`)

1. LOW 4, the lead retyped wrongly (`KeptLead => "Another program may have changed this file as it was saved."`): `UndoClassDatesStepTests.TheSheetsWordsForAKeptTimetableAreTheContracts` RED.
2. LOW 5, the `finally` cover removed (`if (result is UndoSwapResult.Refused) …`, the old behaviour): `UndoSwapTests.AnExceptionAfterAFolderIsMadeLeavesNoEmptyFolderBehind` RED.
3. Review 3 LOW 1, the hidden path back (`throw;` in place of the plain `IOException`): `ReDateTests.AReDateWhoseTimetableIsHeldSaysTheClassDatesAndNoHiddenPath` RED.

Rows 2 and 3 are the pre-fix product, so their RED is also the "test failed first" evidence (the tests were written with the fixes, then run against the reverted product by the must-fail run). Row 1's test predates this piece.

## Runs (PC, LENOVO i5-8365U, Windows 11 Pro 26200; `vm-tools/guest/899-w7b2-11-go.ps1`, a copy of `899-w7b2-10-pc-run.ps1`, under the turn lock)

- `899w7b2-11-a1` at ca690ac6b: both builds 0; 171 passed, 1 failed of 172: the new held-timetable test met the backup's refusal first ("ICS3U couldn’t be backed up, so no dates were changed: …"). Must-fail 3 of 3 RED, build 0 each; HEAD the same, status clean. The test now makes the conversation's copy first (86d683f6a).
- `899w7b2-11-a2` at 86d683f6a: both builds 0; **Passed 172, Failed 0, Skipped 0, Total 172** (the brief's nine classes and every class with `UndoSwap` in its name). Must-fail **3 of 3 RED**, build 0 each; restored Passed 172, Failed 0; HEAD the same, status clean; the lock released by the script.

## Left for the next piece

- Nothing of this brief.

## For the director

- **Parked wording (one constant, `TimetableMemory.WhyTheClassDatesCouldNotBeRead`).** A re-date whose hidden timetable is held by another program. `ReasonItStopped` has only a permission sentence (not true of a lock); the mac's re-date says "Nothing was changed: \(error.localizedDescription)" and has no lock case (macOS does not refuse a read for a held file); the v2.0.0 milestone has no ruling (searched "timetable locked", "hidden path", "class dates in use", "in use by another program"). Options: **(A, recommended, built)** "Nothing was changed: the section's class dates are in use by another program." (the door's own fileIsInUse phrase, "is in use by another program", with the place named as the re-date's part-way sentence names it); (B) "Nothing was changed: another program is using the file that keeps the section's class dates."; (C) put a sentence in `assist-wording` on the mac first and read it on both. The other-read case says "the section's class dates could not be read. Windows said: …" in `HeldFiles.NotReadSentence`'s manner; the same choice covers it.
- **Found, not in scope: the backup's refusal carries .NET's message.** From the Section menu (a fresh copy before every change) and on the first change of an assistant chat, a held timetable (or any held file of the course) stops the re-date at `BackUpOnceForThisConversation`, which says `"{code} couldn’t be backed up, so no dates were changed: {error.Message}"` (`AssistWorkspace.cs` about 3127 and 3371), and `error.Message` is .NET's sentence, very likely with the file's full path (the a1 run's output cut it at "no dates "). So review 3 L1's sentence is reached only on a later change of a chat. That sentence predates W7b1; the fix (say a held file plainly, through `HeldFiles`) belongs to whoever owns the backup's wording.
- **Embedding the contract.** `Plantoir.Core.dll` grows by about 3.7 MB (the whole `shared-rules.json`), parsed once (tens of milliseconds) the first time a kept-timetable sentence is said. If that is unwanted, the alternative is a build step that writes only `undo.wording` into the assembly; the constants were otherwise the house pattern.

## Self-check

1 to 6 (NIGHT3-COMMON): one branch from the director's base; only `windows-app/` and `vm-tools/guest/` changed, no `contracts/`, no `mac-app/`, no `documentation/`, no `PROGRESS.md`; no timed waits, no interim states, no invisible controls, no confirmations; tests for lows 1 to 3; only the brief's classes run on the PC under the lock; pushed with `gpush.sh`.
7. No fixture row changes in this piece (no conversion); the ledger is untouched; no `Reason899…` sentence names anything this piece changed.
8. Writer scan: no writing call moved; `UndoWriterScanTests` is not one of this piece's classes and no count changes.
9. Riding lows: all six closed as listed above (1 to 3 with tests, 4 to 6 in these notes; 6 found already done by the fold).
10. No step's file order or plan-time reading changes: the timetable is still read at plan time, after the pages; only the sentence for a failed read changed.
