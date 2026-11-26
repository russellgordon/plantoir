# #899 W7b2-3: the menu's Duplicate as Next Class is ONE step (Windows #949)

Branch `issue/899-w7b2-3-duplicate-as-next-class`, from `origin/night25/integration-5` c50bc8112 (`dev` 24fcbc718 + W7b2-7, -8, -1, -2). Merges of `origin/dev`: at the start "Already up to date" (`origin/dev` was 24fcbc718, in the base); before hand-back: "Already up to date" again (`origin/dev` still 24fcbc718), so no merge commit was made either time. (Merged on 2026-11-26 in `night25/integration-6`, 5b782bec9, with U4b2-7, -8, -9 and -10. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12.)

Commits: 194b40668 (tests first, with two stubs so they compile: `RefusalForAMenuCopyThatStopped` answering as the old path did, and `RefusalForAPressThatStopped(error, sheet, planning)` delegating to the old one), 5cb93ba7c (the product), cf11637e7 and aff3a9356 (test fixes from run `a`, below).

## Changed tests and sentences

- New class `UndoMenuDuplicateStepTests` (four tests): one step made by the menu holding the mac's one file, bytes and `afterSha` the disk's, today's sentence, no `UndoHistory` entry; a page that appeared at the new name in the last instant before its swap (`UndoSeams.BeforeEachSwap`) refused with `MenuTheNextPageIsAlreadyThere` and never written over (`BeforeTheBegin` is not called on a file step's path, run `a`); a page that cannot be written (staging refused) changes nothing, "Nothing was created: …"; the part-way sentence.
- New class `UndoUnchangedFileSkipTests` (W7b2-2 review 1, L2; W7b2-1 review 2, L1): the door's `SameBytes` skip pinned alone (a draft handed an unchanged file directly is never swapped: its last-write time is unchanged; the begin line alone cannot show it, since `UndoLineOps.ForAFile` names no op for identical bytes either way, run `a` row 4 NOT-RED), and the step's skip pinned alone (an unchanged planned file outside the working folder, which no step can name, is left out, so the changed page is still a recorded step; without the skip the whole step is written plainly). Must-fail rows 4 and 5.
- `UndoDuplicateClassStepTests.AnEditMadeWhileItPlansIsNeverWrittenOver` now checks the sentence: "Nothing was changed: “Unit 2, Day 1.md” was changed by another program while it was being saved." (W7b2-2 review 1, L4).
- `UndoLinksChecklistStepTests`: `PublishIsOne…` pins the pages in the plan's order, the order the ticked class's own publish plan (`PlanPublish`, asked before the press) names them, instead of sorted (L4; "the sheet's order" was not usable: Class Notes is brought by the class and is no row); new `APageChangedSinceItWasCheckedIsNamedAsTheSheetNamesIt` (Worksheet changed in the instant before its swap) and `AnUnreadablePageIsSaidAsTheMacSaysIt` (L1).
- Fixture: `duplicateAsTheNextClass` in `Converted` and `Run` (`DuplicateAsTheNextClassFromTheMenu(Course, 1, "section1/All Classes/Unit 1, Day 1.md", planning: false)`, the mac's `SectionVerbs.duplicateAsNextClass` arguments); its traces run the real action. `WindowsOwnJson["answerTheLinksChecklist"]` names the list order (L3).
- `NamedGapLedger`: the `duplicateAsTheNextClass` row and `Reason899NoDuplicateAsNextClass` are gone; `Reason899NoDuplicateAsNextClass` was the last W7b2 row. `Reason899MenuCopy` stays held and now says the copy is the journal step since W7b2-3 and Edit ▸ Undo is W11b's.
- `UndoWriterScanTests.Allowed`: the `AssistWorkspace.MenuDuplicate.cs` entry is gone (0 writing calls). `AssistWorkspace.cs`'s reason made true (W7b2-2 review 1, L1): `Save`'s one caller is `ApplyIndexChange`, reached only from `RederiveTheFrontPage`, the door's `sectionFrontPage` maintainer, so it waits for no W7b2 piece; count 2 unchanged.
- W7b2-1's must-fail rows 3 and 5 (`vm-tools/guest/899-w7b2-1-mustfail.json`) re-anchored on `var created = new List<string>();` / `created.Add(path);` (riding low c).

## Must-fail lines

File `vm-tools/guest/899-w7b2-3-mustfail.json` (ASCII anchors), run by `899-w7b2-3-go.ps1` with `899-w7b2-3-pc-run.ps1` (a copy of `899-w7b2-2-pc-run.ps1`).

**6 RED of 6** on aff3a9356 (rows 1 and 3 to 6 in run `b`, row 2 in run `c`), each failing the one test named; restored trees green (255 of 255; 4 of 4).

1. The copy written outside the step (a plain `File.WriteAllText`): `UndoMenuDuplicateStepTests.TheCopyIsOneStepMadeByTheMenu`.
2. The exclusive-create refusal removed: an expected-absent target passes both of the swap's guards (`Holds` and the kept-original check after the rename, L4), so a taken name is overwritten: `APageThatAppearedAtTheNewNameIsNeverWrittenOver`. With `Holds` alone sabotaged it was NOT-RED in run `b` (the L4 check still refused and reversed), so the row edits both lines; `899-w7b2-3-pc-run.ps1` now takes a row of several edits in one file (`edits`).
3. The wrong `madeBy` (`sheet`): `TheCopyIsOneStepMadeByTheMenu`.
4. Riding low: the door's unchanged-file skip removed: `UndoUnchangedFileSkipTests.TheDoorNamesNoOpForAFileHandedToItUnchanged`.
5. Riding low: the step's unchanged-file skip removed: `UndoUnchangedFileSkipTests.TheStepLeavesOutAnUnchangedFileItCouldNotName`.
6. Riding low (W7b2-8 L1): a page changed since said as "Nothing was changed" again: `UndoLinksChecklistStepTests.APageChangedSinceItWasCheckedIsNamedAsTheSheetNamesIt`.

W7b2-1's file, re-anchored (riding low c), on 5cb93ba7c (run `a-w7b2-1`): **9 RED of 9**, rows 3 and 5 among them; restored 31 of 31 (UndoMakeRoomStepTests, InsertClassesTests).

## Runs

All on the PC (LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200), under the turn lock, queued behind the director's suite: both builds plus the brief's classes (`UndoMenuDuplicateStepTests`, `AddClassContractTests`, `UndoActionStepsOnWindowsTests`, `UndoActionTraceContractTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `ContractTests.AssistWording_MatchesContract`, the one `ContractTests` method a grep for `MenuDuplicate` finds) and the riding lows' classes (`UndoUnchangedFileSkipTests`, `UndoLinksChecklistStepTests`, `UndoDuplicateClassStepTests`, `UndoMakeRoomStepTests`, `InsertClassesTests`). No UI class, no harness.

- `w7b2-3-a-red`, 194b40668 (tests first): both builds exit 0; **10 failed of 57**: four of `UndoMenuDuplicateStepTests` (five cases), the fixture row `TheWindowsActionLeavesTheRecordedStep(duplicateAsTheNextClass)`, `UndoWriterScanTests.EveryWriterIsTheDoorOrNamedWithAReason`, `UndoLinksChecklistStepTests` `AnUnreadablePage…`, `APageChangedSince…` and `PublishIsOne…`. The last was a fault of the test (it expected Class Notes to be a sheet row), fixed in cf11637e7.
- `w7b2-3-a`, 5cb93ba7c: both builds exit 0; 252 of 256: `PublishIsOne…` (above), the menu theory's `beforeTheBegin` case and `APageChangedSince…` (the `BeforeTheBegin` seam is not called on a file step's path, so nothing changed), and the theory's `beforeTheSwap` case (refused right, the test's file-list filter wrong). Fixed in aff3a9356. Must-fail 5 RED, row 4 NOT-RED (see above); then W7b2-1's file 9 RED of 9.
- `w7b2-3-b`, aff3a9356: both builds exit 0; **255 of 255**; must-fail 5 RED, row 2 NOT-RED (one guard of two sabotaged); restored 255 of 255.
- `w7b2-3-c`, aff3a9356: must-fail row 2 with both guards: RED; restored 4 of 4.
- The lock was held by the director's `int-n25-5` at the start; every run queued behind it through the lock and released it.

## Left for the next piece

- W7b2-8 review 1, L2 (a contract key for "the pages you ticked", read from the Swift source today): waits for the next `contracts/` change that already brings back the Mac gate. Not changed. (Done since: U4b2-9 added `linksChecklist.wording.pagesYouTicked`, and Windows reads it there since 7edb554d2, `LinksChecklistWording.PagesYouTicked`; `AssistWorkspace.PagesThePressTicked` and the read of the Swift source are gone.)
- The mapping of a door `cannotTellNow` on a really unreadable file to the unreadable-page sentence is pinned on `RefusalForAPressThatStopped` with a constructed refusal and a file held with no sharing, not through the door: the door reports a file held that way as `fileIsInUse` (error 32), and an access-denied read cannot be made in a test without changing the file's permissions.

## For the director

- No `contracts/` change, no `mac-app/` change.
- Every W7b2 row is now out of the ledger's `UndoActionStepsOnWindows`; nothing of this action is still held there. `Reason899MenuCopy` (the old in-memory list, `MenuCopyUndoEntries`) stays held by design.
- Must-fail rows 4 to 6 are the riding lows' proofs, beyond the brief's three.

## Self-check

1. Broke each fix and watched its test fail: tests-first commit 10 red; must-fail 6 RED of 6; W7b2-1's file 9 RED of 9 on this tree.
2. No timed waits added (the seams run synchronously).
3. Failure-path sentences true: already there, "changed while saving a copy", "Nothing was created: …", part way with "the copy of the class"; never `StoppedWhileWriting`, "couldn't be read" or a plain "saved". The checklist's three sentences are the mac's.
4. `dev` merged before the last proof: "Already up to date" at both points (24fcbc718).
5. No number tuned by trial.
6. Windows only; no `contracts/` or `mac-app/` change.
7. Fixture row `duplicateAsTheNextClass` green, its traces run the real action; its ledger row and `Reason899NoDuplicateAsNextClass` gone; `Reason899MenuCopy` true.
8. Writer scan: `AssistWorkspace.MenuDuplicate.cs` out (0 calls); `AssistWorkspace.cs` 2 with a true reason.
9. Riding lows: a L1, L3, L4 fixed with tests (L2 noted, waits for a contract change); b (1) to (4) fixed, (2) with must-fail rows 4 and 5, (3) in the notes; c re-anchored and run.
10. File order is the mac's (one file); its before is read at plan time (must-fail row 2).
