# #899 W7b2-2: Duplicate Class is ONE step, the room and the copy together (Windows #949)

**This branch and W7b2-1 merge together** (it is built on `issue/899-w7b2-1-make-room` 2e9026e70 and deletes the file-by-file path W7b2-1 kept for it).

Branch `issue/899-w7b2-2-duplicate-class`, from `origin/issue/899-w7b2-1-make-room` 2e9026e70 (which holds `dev` da7474047). Merges of `origin/dev`: none needed at the start (`origin/dev` was da7474047, already in the base: "Already up to date"); before hand-back ff6688645 (merging `origin/dev` 24fcbc718: Mac pieces touching `NamedGapLedger.cs` and contracts; no conflict, both sides kept; the `undo.rule.shadow` clause still carries the three phrases `UndoMakeRoomStepTests` reads). (Merged on 2026-11-26 in `night25/integration-5`, c50bc8112, with W7b2-1, -7 and -8. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12. What follows says the ledger and the writer scan as this branch saw them: on the merged tree the `Reason899W7b2` row and reason, and `Reason899W7b2MakeRoomLinkedPage`, are gone, and only `Reason899NoDuplicateAsNextClass` is left of W7b2, for W7b2-3. W7b2-3 merged later the same day, in `night25/integration-6`: that reason and its row are gone too, and no W7b2 action is held.)

## Changed tests and sentences

- New class `UndoDuplicateClassStepTests` (six tests): one step in the mac's order with every op's `afterSha` the disk's; the copy refused after the room is planned makes the room alone in one step; a read-only page changes nothing; a part-way stop; an edit made while it plans is never written over; nothing else moving, today's undo records the copy with no before.
- `DuplicateClassTests.ALinkRewrittenInsideTheLessonCannotFoolTheGuard`: the skip built as above; also asserts the room alone is made (Day 7, and the link in Day 3 rewritten).
- `InsertClassesTests.ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken` → `ADuplicateWhoseNewPageCouldNotBeSaved_ChangesNothingAndIsNotStillTaken` (Unit 1, Day 2's copy, so the folder lands on a path no rename touches; "Nothing was changed", never "is still there", nothing written).
- `UndoMakeRoomStepTests.AmongBlankPagesAPageThatComesOutUnchangedIsNotInTheStep` → `AmongPagesThatDifferOnlyInTitleAndDateAPageThatComesOutUnchangedIsNotInTheStep` (W7b2-1 review 2, L2).
- `NamedGapLedger`: `duplicateClass` out of the `Reason899W7b2` row, which now holds exactly `notTodayOnTheFrontPage`, `answerTheLinksChecklist` and `keepClassesDatedLater`; `Reason899W7b2` says "W7b2-2 converted Duplicate Class" and lists Not Today, the links checklist and Classes Dated Later kept at Deploy as still to convert. `Reason899NoDuplicateAsNextClass` (row `duplicateAsTheNextClass`, unchanged) now says W7b2-3 converts it (it said "W7b2 converts it with Duplicate Class").
- `UndoWriterScanTests.Allowed["Plantoir.Core/Assist/AssistWorkspace.cs"]`: count 4 → 2 (`File.WriteAllText` in `Save`, still used by `ApplyIndexChange`, W7b2; `File.Move` of the rollover's marker, W7c); the W7b2-2 clause gone, Duplicate Class among the actions through the door.

## Must-fail lines

File `vm-tools/guest/899-w7b2-2-mustfail.json` (ASCII anchors), run by `899-w7b2-2-go.ps1` with `899-w7b2-2-pc-run.ps1` (a copy of `899-w7b2-1-pc-run.ps1`).

Run `899-w7b2-2-b` on ff6688645: **4 RED of 4**, each failing the one test named:

1. The room and the copy as two steps: `UndoDuplicateClassStepTests.TheRoomAndTheCopyAreOneStepInTheMacsFileOrder`.
2. The copy written outside the step (saved after the room's step is made): the same test (the op's `afterSha` is not the disk's).
3. A before read at make time: `AnEditMadeWhileItPlansIsNeverWrittenOver`.
4. The room alone making no step: `TheCopyRefusedAfterTheRoomIsPlannedMakesTheRoomAloneInOneStep`.

A fifth row (W7b2-1 review 2, L1: the step's skip of an unchanged file removed) was NOT-RED in run `a`: the door skips an unchanged file too (`UndoDoor` line 211, `SameBytes`), so no single sabotage in one file shows it. Dropped; L1 stays noted (below). In run `a`, row 4 was RED only because its test was already red; run `b` is the proof.

## Runs

All on the PC (LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200), under the turn lock, both builds plus the brief's classes and every class a grep for `ApplyDuplicateClass`/`duplicate:` finds (ClassPlanningContractTests, ClubNounTests, FileFormatContractTests, NarrowToolsMirrorTests, NextClassUnitsTests, UnofferedToolRefusalTests); no UI class, no harness.

- `899-w7b2-2-a-red`, b70ad2862 (tests only): both builds exit 0; **9 failed of 91**: six of `UndoDuplicateClassStepTests`, `InsertClassesTests.ADuplicateWhoseNewPageCouldNotBeSaved_ChangesNothingAndIsNotStillTaken`, the fixture row `TheWindowsActionLeavesTheRecordedStep(duplicateClass)`, `UndoWriterScanTests.EveryWriterIsTheDoorOrNamedWithAReason` (count 2 before the path was deleted).
- `899-w7b2-2-a`, f44aef12d: 330 of 331; the one red was the room-alone test asserting Day 2's bytes (Make Room re-dates a class whose rename did not happen under its old name, as it always has): the test now reads its lesson and title (6d7fa0fec).
- `899-w7b2-2-b`, ff6688645 (merged `dev` 24fcbc718): both builds exit 0; **331 of 331**; must-fail **4 RED of 4**; restored tree 331 of 331 green.

## Left for the next piece

- Duplicate as Next Class from the menu (W7b2-3, `AssistWorkspace.MenuDuplicate.cs`, row `duplicateAsTheNextClass`).
- W7b2-1 review 1's lows not fixed here (harness work, and the brief asks for no harness run): the kill harness `w7-make-room-kill` never runs pages that differ only in title and date (pinned in the unit test `AmongPagesThatDiffer…` instead, now with must-fail row 5); and in shadow a kill part way through the swap can leave one lesson under two names until the backup is restored (written in W7b2-1's notes for documentation 12; live recovery puts every page one way).

## For the director

- First: W7b2-1 and this branch merge together.
- W7b2-1's must-fail file rows 3 and 5 anchor on `int created = 0;` / `created++;` in `PlanTheRoom`; this piece changed those lines (`var created = new List<string>();`, `created.Add(path);`), so those two rows read NOT-FOUND on this branch. W7b2-1's file is its own record and was not changed; a re-run of it on the merged tree needs those two anchors moved.
- No `contracts/` change. The stash "w7b1 half-written Make Room and Duplicate, 2026-11-21" is untouched (read with `git stash show -p`, never applied, popped or dropped).

## Self-check

1. Broke each fix and watched its test fail: tests-first commit 9 red; must-fail 4 RED of 4 on the merged tree.
2. No timed waits added.
3. Failure-path sentences true: "Nothing was changed" (read-only page, a folder at the new page), part way with "the classes and the copy", the room alone with "the classes"; never `StoppedWhileWriting`, "couldn't be read" or a plain "saved".
4. `dev` merged before the last proof: ff6688645 (24fcbc718).
5. No number tuned by trial.
6. Windows only; no `contracts/` or `mac-app/` change.
7. Fixture row `duplicateClass` green, out of `HeldButRunnable` and the ledger; `Reason899W7b2` true (holds notTodayOnTheFrontPage, answerTheLinksChecklist, keepClassesDatedLater).
8. Writer-scan count for `AssistWorkspace.cs` true at 2.
9. Riding lows: review 2 L2 fixed (test renamed); L1 noted (no single-file sabotage shows it: the door also skips); review 1's harness lows noted (no harness run in this brief).
10. File order is the mac's; every before read at plan time (must-fail row 3).
11. The stash is untouched.
