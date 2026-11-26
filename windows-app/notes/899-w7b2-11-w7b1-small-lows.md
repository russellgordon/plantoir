# #899 W7b2-11: W7b1's small lows, and its notes made true

Branch `issue/899-w7b2-11-w7b1-small-lows`, from `origin/dev` a03fecefd (W7b2-10 merged; the director's correction to the brief's base). `origin/dev` was fetched again before the proof and before the hand-back: it had not moved, so there is no merge commit (both times "Already up to date").

## Riding lows

1. **Review 2 L4 (wording retyped).** Closed the house way, by the director's decision on review 1 (LOW 1): `TimetableMemory.KeptLead` and `KeptBesideIt` stay RETYPED, as `UndoActionStep.KeptSentence` is in the same `undo.wording` block, and are pinned against `shared-rules.json` → `undo.wording` (`classDatesKeptLead`, `classDatesKeptBesideIt`) by `UndoClassDatesStepTests.TheSheetsWordsForAKeptTimetableAreTheContracts`, which reads the contract and goes red when the constant is retyped wrongly (must-fail row 1). The first round's run-time read (`UndoContractWording.cs` and the embedded `shared-rules.json` in `Plantoir.Core.csproj`) is removed; the doc comments now name the pinning test.
2. **Review 2 L5 (tidy only on a returned refusal).** `UndoSwap.Swap` runs `RemoveTheEmptyFoldersMade` in its `finally` whenever the swap gave no result (an exception) or a `Refused`; a test's kill point (`StoppedByATest`) and a `Swapped` still tidy no folder. Test: `UndoSwapTests.AnExceptionAfterAFolderIsMadeLeavesNoEmptyFolderBehind` (the existing seam `StagingWriteFailsAt` throws, asked just after `MakeTheFolderOf`; no new seam).
3. **Review 3 L1 (a held timetable said as .NET's sentence). PARTLY CLOSED.** `ApplyReDate` wraps the plan-time `TimetableMemory.PlanInto` and turns an `IOException` into `TimetableMemory.WhyTheClassDatesCouldNotBeRead`, said after "Nothing was changed: ":
   - a sharing or lock violation: Russell's ruled sentence (2026-11-25), exactly "Nothing was changed: another program, such as a syncing service, is using this section's class dates. Try again in a moment.";
   - a read Windows refused for another reason: "this section's class dates could not be read. Windows said: " and `HeldFiles.SystemWords` (the system's words without the path);
   - Plantoir's own refusal, which carries no Windows error (a folder where the file belongs): "this section's class dates could not be read.", with no "Windows said" (review 1, LOW 2);
   - a permission refusal (`UnauthorizedAccessException`) is untouched and is already `ReasonItStopped`'s plain sentence.

   Tests: `ReDateTests.AReDateWhoseTimetableIsHeldSaysTheClassDatesAndNoHiddenPath` (the timetable held `FileShare.None`; the exact ruled sentence; no `.internal`, no `section1.json`, no working-folder path; pages and timetable byte for byte as they were) and `ReDateTests.AReDateWhoseTimetableIsAFolderQuotesNoWindowsWords`.

   **Why only partly:** this sentence is reached only on the SECOND and later change of an assistant chat (built-in or outside). Before any planning `ApplyReDate` backs the course up, and the zip opens every file of the course, the timetable included. From the Section menu a fresh copy is made before every change, and in a chat on its first change, so a held timetable there stops the re-date at the backup, which says `"{code} couldn’t be backed up, so no dates were changed: {error.Message}"` (`AssistWorkspace.cs` about 3127, and 3371 for Bring Pages into Date) with .NET's sentence and the full hidden path. (A rollover from the menu says `StartOfYearNeedsABackup`, which is plain.) That backup message is OLDER than W7b1 (2026-08-13), is shared by every caller of `BackUpOnceForThisConversation`, fires for any held file of the course, and is being filed as its own issue by the director; this piece does not change it. The test reaches the new path by making the chat's copy first through reflection on the private `BackUpOnceForThisConversation` (review 1, LOW 5: kept, since a rename or signature change fails the test loudly, and making the method internal for a test was not worth a product change).
4. **Review 2 L3 (front page now dated).** Notes only: under "For PROGRESS" and "For documentation 12" below.
5. **Review 3 L2 (the rollover's pin).** Notes only: under "For W7c" below.
6. **The sweep's notes lows.** Closed in review 1's round (its M1; the first round wrongly said nothing was needed). The fold (8f73b39a4) had already carried the superseded sentence into `windows-app/PROGRESS.md`, twice: the W7b1 Class Dates bullet ended "costs only the record (the re-date goes on)". With the director's leave this round edits PROGRESS: the duplicate W7b1 and #1039/#1040 sections (old lines 83 to 130, byte-identical to 35 to 82) are removed, and the remaining bullet now says a file that cannot be written costs only the record in the Class Dates sheet and `remember_timetable`, while in a re-date or rollover the timetable is a file of the re-date's own step, so one that cannot be written refuses the whole re-date. `git grep "re-date goes on"` finds it only in these notes; "is that same step for now" is nowhere. W7b1's own notes file (98 lines after the fold) no longer holds the first "For PROGRESS" section, so it is not edited. The two documentation passages: documentation 12 (about line 8824) already says the replacement and is true at this head; documentation 10 (about 4455 to 4459) describes the MAC's re-date before U3 and is followed by "Since #899's U3 neither of those two can happen", which is true.

## For PROGRESS

- **W7b2-11, W7b1's small lows (#899).** `undo.wording.classDatesKeptLead` and `classDatesKeptBesideIt` stay retyped and are pinned against the contract by `TheSheetsWordsForAKeptTimetableAreTheContracts`. A swap cut short by an exception leaves no empty folder it made (`RemoveTheEmptyFoldersMade` in the `finally`). On the second and later change of an assistant chat, a re-date or rollover whose hidden timetable is held by another program says "Nothing was changed: another program, such as a syncing service, is using this section's class dates. Try again in a moment.", never .NET's sentence with the `.internal/timetable/…` path. From the Section menu, and on a chat's first change, the course backup refuses first with .NET's message and the full path: an older fault, its own issue (the director's).
- **The re-date's front page is now DATED as well as repointed (W7b1 review 2, LOW 3).** It goes through the step's front-page recompute (`RederiveTheFrontPage` → `ApplyIndexChange`, `PointedAndDated`, the mac's `sectionFrontPage` maintainer) where the old code only repointed (`SectionIndex.Repointed`). Right, and the publish rule; but a byte change on the Windows front page after Re-date Classes and Roll Over: its `created` date moves with the section's classes.

## For documentation 12

- In the section on Re-date Classes… as one step: the section's front page is recomputed after the step by its rule (`sectionFrontPage`), so it is repointed AND dated (`PointedAndDated`); before W7b1 Windows only repointed it (`SectionIndex.Repointed`). A teacher's front page therefore changes its date line too after a re-date or rollover, as on the mac.
- A held timetable: the plan-time read of `.internal/timetable/section<N>.json` is said as "Nothing was changed: another program, such as a syncing service, is using this section's class dates. Try again in a moment." (Russell's ruling, 2026-11-25); another refused read as "this section's class dates could not be read. Windows said: …" without the path; a folder in its place without "Windows said". This is reached only on the second and later change of an assistant chat: from the Section menu, and on a chat's first change, the course backup reads the timetable first and refuses with .NET's message (its own issue).

## For W7c

- When `rollOver` is converted, the timetable file must be added to `WindowsOwnFileInTheStep["rollOver"]` (as `reDateClasses` has it: `courses/ICS3U/.internal/timetable/section1.json`, writeFile, after the recorded files, before the recompute), or that fixture row goes red (W7b1 review 3, LOW 2).

## Must-fail lines (`vm-tools/guest/899-w7b2-11-mustfail.json`)

1. LOW 4, the lead retyped wrongly (`KeptLead = "Another program may have changed this file as it was saved."`): `UndoClassDatesStepTests.TheSheetsWordsForAKeptTimetableAreTheContracts` RED.
2. LOW 5, the `finally` cover removed (`if (result is UndoSwapResult.Refused) …`, the old behaviour): `UndoSwapTests.AnExceptionAfterAFolderIsMadeLeavesNoEmptyFolderBehind` RED.
3. Review 3 LOW 1, the hidden path back (`throw;` in place of the plain `IOException`): `ReDateTests.AReDateWhoseTimetableIsHeldSaysTheClassDatesAndNoHiddenPath` RED.
4. Review 1 LOW 2, "Windows said" quoted for Plantoir's own refusal (a folder): `ReDateTests.AReDateWhoseTimetableIsAFolderQuotesNoWindowsWords` RED.
5. The ruled sentence said otherwise (the first round's "the section's class dates are in use by another program."): `ReDateTests.AReDateWhoseTimetableIsHeldSaysTheClassDatesAndNoHiddenPath` RED.

Tests first (review 1, LOW 4): the new tests were written with their fixes, not seen failing first; rows 2, 3 and 4 run them against the pre-fix product, which stands in for that. Row 1's test predates this piece and reads the contract, so the retyped constant can drift only by going red.

## Runs (PC, LENOVO i5-8365U, Windows 11 Pro 26200; `vm-tools/guest/899-w7b2-11-go.ps1`, a copy of `899-w7b2-10-pc-run.ps1`, under the turn lock)

- `899w7b2-11-a1` at ca690ac6b: both builds 0; 171 passed, 1 failed of 172: the new held-timetable test met the backup's refusal first ("ICS3U couldn’t be backed up, so no dates were changed: …"). Must-fail 3 of 3 RED, build 0 each; HEAD the same, status clean. The test now makes the conversation's copy first (86d683f6a).
- `899w7b2-11-a2` at 86d683f6a: both builds 0; **Passed 172, Failed 0, Skipped 0, Total 172** (the brief's nine classes and every class with `UndoSwap` in its name). Must-fail **3 of 3 RED**, build 0 each; restored Passed 172, Failed 0; HEAD the same, status clean; the lock released by the script.
- `899w7b2-11-b1` at df9c4acc2 (review 1's round): both builds 0; **Passed 173, Failed 0, Skipped 0, Total 173**. Must-fail **5 of 5 RED**, build 0 each; restored Passed 173, Failed 0; HEAD the same, status clean; the lock released.

## Left for the next piece

- Nothing of this brief.

## For the director

- **The held-timetable wording is ruled** (Russell, 2026-11-25) and built exactly: "Nothing was changed: another program, such as a syncing service, is using this section's class dates. Try again in a moment.". Nothing is parked.
- **The backup's refusal** (`"{code} couldn’t be backed up, so no dates were changed: {error.Message}"`, `AssistWorkspace.cs` about 3127 and 3371, and every other caller of `BackUpOnceForThisConversation`) carries .NET's message with the full path for any held file of the course. Older than W7b1; the director is filing it as its own issue. Not changed here.
- **Review 1's LOW 3** (the in-use sentence true on every path that reaches it) and the point on the `finally` (safe) need nothing.

## Self-check

1 to 6 (NIGHT3-COMMON): one branch from the director's base; only `windows-app/` and `vm-tools/guest/` changed, no `contracts/`, no `mac-app/`, no `documentation/`; `PROGRESS.md` edited only in review 1's round, with the director's leave (M1); no timed waits, no interim states, no invisible controls, no confirmations; tests for lows 1 to 3; only the brief's classes run on the PC under the lock; pushed with `gpush.sh`.
7. No fixture row changes in this piece (no conversion); the ledger is untouched; no `Reason899…` sentence names anything this piece changed.
8. Writer scan: no writing call moved; `UndoWriterScanTests` is not one of this piece's classes and no count changes.
9. Riding lows: 1, 2, 4, 5 and 6 closed (1 and 2 with tests; 6 by the PROGRESS edit); 3 PARTLY closed, with two tests, the backup's older refusal answering first from the menu and on a chat's first change (its own issue).
10. No step's file order or plan-time reading changes: the timetable is still read at plan time, after the pages; only the sentence for a failed read changed.
