# U4b3 part 2, half 7a (#899): Insert Class moves a linked later class as a link

Branch `issue/899-u4b3-linked-class-page-moves-its-link`, from door-6's head 4b7781ae9. `origin/dev` 461ee3943 was already merged in (by door-5) at both checks (before proving and before hand-back), so no new merge commit. **Touches `contracts/`: both gates; the renamed Windows test is proved only by the Windows gate.** This is half 7a of the order file's split (`2026-11-26-899-u4b3-ORDER.md`, "For the director", point 3).

## For PROGRESS

- `ClassInsertionPlanner.apply`, step 1 (the renames): a rename whose `fromURL` is a symbolic link to a file (`isALinkToAFile`: `lstat` says a link, `stat` of its target says a regular file) is planned as `step.moveLink(from, to:, linkSha: UndoTreeReading.linkSha(at:))` and then the retitle written at `rename.toURL`, which door-6 and the first half plan at the file the link leads to. A link whose `linkSha` cannot be read is counted not renamed. Every other rename is unchanged (write, then remove). Steps 2 (the `[[link]]` rewrite) and 3 (the dates) reach the linked file the same way, with no change. No change to `JournaledStep` or the door was needed.
- Insert Class, Make Room and Duplicate Class (through the same code) now go ahead, one step, where they were refused "cannot tell now".
- `undo.rule.shadow`: the removed-or-renamed-away clause rewritten (the Mac moves the link itself; title and date into the file it leads to; the place handed over; a removal of a linked page outright and an un-handed-over new file at a link still refused; Windows' half unchanged until W8b piece 22, naming the renamed Windows test).
- The Windows test renamed and re-pointed (riding low night25-7 LOW 1 fixed).
- Documentation 09: the two earlier sentences that said the Mac still refuses, and the paragraph "U4b3: linked-class-page-moves-its-link" rewritten as one paragraph on what Insert Class now does.

## For documentation 12

- Insert Class on Windows renames a later class that is a link (a symbolic link to a file; decide with `UndoLinks.Look`, never `FileAttributes.ReparsePoint` alone: ruling 7 of 2026-11-26) by moving the link itself through the door (W8 piece 6's link move, `MoveFileEx` on the link, judged by its target string), writing the title and the moved date through it into the file it leads to, never a plain copy, the place it leaves handed over in the same step (the Windows door piece for a handed-over place first). When it lands, the renamed test `UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacMovesTheLink_UntilW8bPiece22` is retired and the clause's Windows half ("On Windows Insert Class still goes ahead outside the door, …, until W8b piece 22 (held by name in …, which reads this clause).") removed, in the same merge; the two held `stackCases` rows (7b's, under `Reason899W8bLinkedClassPage`) clear then too.
- Stale lines in documentation 12 (the director's): about 18085 ("Shadow, a later class that is a symbolic link: …", which names the old test name `…WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15`) and about 18193 ("Insert Class on Windows … goes ahead today when a later class is a link …", which says the Mac refuses). The W8 ORDER (`2026-11-26-899-w8-ORDER.md`) line 92 says piece 22 renames the test: after this piece it does not (it retires the renamed test).
- No ledger row is added by 7a (no contract row is added); 7b adds the two.

## Must-fail lines

`windows-app/notes/899-u4b3-part2-mustfail.log`. Red first: 7 of the 10 new tests refused "cannot tell now" with the loop as on door-6's head, and the Duplicate Class test red under M1 (the same behaviour). M1 (write + remove for a link): 8 tests red. M2 (`moveLink` given the target's path): 8 red. M3 (retitle at the link's old place): 7 red. M4 (the Mac phrase removed from the clause): the substring script reports 0. M5 is 7b's (the Python model). RED 4 of 4.

## Runs

- `.dd/run-p2-red.log`: UndoMakeRoomLinkedPageTests on the old loop: 10 run, 12 failures.
- `.dd/run-p2-green2.log`: UndoMakeRoomLinkedPageTests, 10, 0 failures.
- `.dd/run-p2-proof1.log`: UndoMakeRoomLinkedPageTests, ClassPlanningTests, DuplicateAsNextClassTests, JournaledStepTests, UndoHandedOverPlaceTests, UndoSweepFindingsTests, UndoJournalContractTests, UndoFilesContractTests, UndoRenameFolderStepTests, UndoActionStepsTests, UndoWriterScanTests, SharedRulesContractTests and the 13 other classes that read documentation 09 as text (AboutWindowLinksTests, AlertKeysTests, CloudSyncNoticeLayoutTests, CourseSettingsTeardownTests, DetailTabsLayoutTests, ListTableGoldenTests, ProgressViewSizeTests, RestoreRecoveryTests, TickTableTests, TodaysClassOnTheFrontPageTests, UnsavedSettingsNoticeLayoutTests, UpdateRemindersTests, WorkingFolderSelectionTests): 403 tests, 0 failures.
- `python3 scripts/test_make_undo_traces.py`: 38 tests OK; traces not stale (no undo row changed).
- The substring script (`undo.rule.shadow`, occurrences of each string the renamed Windows test reads):

```text wrap
1 moves the link itself to the new name
1 saving a plain copy at the new name and deleting the link itself, the linked file left untouched
1 held by name in UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacMovesTheLink_UntilW8bPiece22
```

- `grep -rn "UntilU4b2Pieces14And15\|WhereTheMacRefusesBeforeAnythingChanges" windows-app/ contracts/ documentation/` (notes aside): two hits, both in documentation 12 (18085, 18193), named above for the director.
- `grep -n "step.remove(" mac-app/QuartzTeachers`: `ClassInsertionPlanner` (one call, the plain-page rename) and `PublishedPagesRecord` (two) only, still so.

## Left for 7b

Exactly the order file's 7b, none of it started: the two `stackCases` rows ("U4b3, Insert Class renaming a later class that is a link: one step, the link moved as itself; undone, …" and "… undone and redone, …"); the call `makeRoomWithALaterClassThatIsALink` in `stackCasesHow` and the Mac replay (`UndoContractReplayKinds`, `UndoJournalContractTests.testStackCases`); the key `linkedPage` (`new`/`old`/`both`/`neither`, the target string or `notALink`, `retitledAndRedated`/`asLaidDown`/`gone`); the Python model of the call (`scripts/test_make_undo_traces.py`) and M5; the ledger reason `Reason899W8bLinkedClassPage` with both rows held by exact name, checked by script, and the `KeysChecked` confirmation in `UndoStackContractTests.cs`. Nothing of 7b was needed to keep 7a true: the renamed Windows test reads only the clause, and no row was added. The clause deliberately says nothing yet about Undo putting the move and the write back as one step; 7b's undone and redone rows prove it, and 7b may add that sentence with them.

## Left for the next piece

- A DANGLING later-class link (pinned, `testADanglingLinkedLaterClassIsSkippedAsBefore`): `fileExists` follows it and answers false, so its rename is skipped, as before; the class below's rename then finds the place free and writes its lesson THROUGH the dangling link, which makes the file the link names (and the old page is removed). Unchanged by this piece; whether a dangling link should be moved as a link or refused is open.
- A later class that is a link to a FOLDER (pinned): `readText` cannot read it, so it is counted not renamed, the link left as it was.
- A link whose target is another later class of the same run: not built, pinned or run; what happens is unverified (the link would be moved as a link and its retitle planned into the other class's page, which that class's own rename also reads and writes in the same plan). Worth a pin in 7b or after.

## For the director

Nothing parked. No HIG section: no sentence a teacher reads was worded (the existing "Renamed 2, …" sentences are unchanged).

## Self-check

1. Broke each fix and watched it fail: M1 to M4 (log); the new tests red first on the old loop.
2. No timed waits; the recovery loop ends on the first kill point not reached.
3. Failure paths: a link whose target cannot be read is counted not renamed; a folder link and a dangling link pinned as before; a removal of a linked page still refused (UndoSweepFindingsTests, comment corrected); no new sentence a teacher reads.
4. `dev` 461ee3943 already merged, checked before proving and before hand-back; no merge commit.
5. No number tuned by trial.
6. Scope: `ClassInsertionPlanner.swift`, new `UndoMakeRoomLinkedPageTests.swift` (xcodegen generate), the comment in `UndoSweepFindingsTests.swift`, `contracts/shared-rules.json` (the clause only), `windows-app/Plantoir.Tests/UndoMakeRoomStepTests.cs` (the one test's name, message, phrase and summary, as the brief allows), documentation 09, these notes and the log.
7. The grep for `DispatchQueue|.map {|.filter {|.reduce(|$0` over the added Swift lines is empty; MARK sections in the new class.
8. Riding low night25-7 LOW 1: fixed (the test's name and settle message promise W8b piece 22; its phrase is the new clause's). It is a contract-reading test; M4 is its failing proof.
9. The rename record is still kept and the switch is still off (not touched).
10. No contract row added; the changed clause is read on the Mac by no test and on Windows by the renamed test (substrings 1 each); no held row needed for 7a.
