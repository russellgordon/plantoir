# #899 W7b2-2: Duplicate Class is ONE step, the room and the copy together (Windows #949)

**This branch and W7b2-1 merge together** (it is built on `issue/899-w7b2-1-make-room` 2e9026e70 and deletes the file-by-file path W7b2-1 kept for it).

Branch `issue/899-w7b2-2-duplicate-class`, from `origin/issue/899-w7b2-1-make-room` 2e9026e70 (which holds `dev` da7474047). Merges of `origin/dev`: none needed at the start (`origin/dev` was da7474047, already in the base: "Already up to date"); MERGE-AT-END.

## For PROGRESS

- Duplicate Class (`ApplyDuplicateClass`, key `duplicateClass`, the assistant's `add_next_class` with `duplicate`) is ONE `UndoActionStep`, all or none: the room is planned into the step by W7b2-1's `PlanTheRoom` (renames as a write and a remove, links, dates, the blank page), the copy is planned into the same step over the blank page the room planned, and the step is made once. The copy's time of day is read through the step (`PlanningThrough`, the mac's `duplicateStep.whilePlanning`).
- #200 A's question ("was MY page created?") is asked of the plan: `RoomPlanned.CreatedPaths` (new) holds the full paths of the blank pages planned into the step; `Created` is its count.
- The copy refused once the room is planned (the place still holds a lesson, or the copy cannot be made certainly hidden): the room alone is made, in the same step under the same key (`MakeTheRoomAlone`), and the answer is as before (`ThePlaceForTheCopyIsStillTaken` / `TheCopyCouldNotBeMadeHidden`, naming the backup). A room-alone step that stops says the part-way sentence with "the classes" (the mac's words there).
- A page that cannot be planned or written changes nothing: "Nothing was changed: …", no step applied, no `UndoHistory` entry. A part-way stop says `wording.publishStoppedPartWay` with "the classes and the copy" (the mac's `saidWhenTheStepStopped` words), naming the kept file. Never `StoppedWhileWriting` and a rethrow.
- Today's in-memory undo (`UndoHistory`) records what it recorded before: an entry only when nothing else moved, holding the copy with no before (the step's files told to it by `MakeTheUndoStep` inside the entry `ApplyDuplicateClass` opens); abandoned when classes moved, the menu's trail line told a file was written (`NoteAChangeWithNoUndoEntry`).
- `InsertClassesFileByFileForDuplicate` and `RewriteLinksFileByFileForDuplicate` are deleted; the link forms' explanation moved onto `RewriteLinks`.
- The fixture row `duplicateClass` is converted (`Converted`, `Run`), out of `HeldButRunnable` (now empty, kept for the next held step that runs there) and out of the `Reason899W7b2` ledger row; its traces run the real action.

## For documentation 12

- Duplicate Class's step: file order is the order first planned, the mac's exactly for its fixture (unit 1, duplicate Day 1): `Unit 1, Day 4.md` (new, the first rename's new name), `Unit 1, Day 3.md` (removed, then the second rename's new name), `Unit 1, Day 2.md` (removed, then the blank page, then the copy: one file), `Unit 2, Day 1.md` (its link, then its date). Four `writeFile`, no recompute. No difference to name.
- A page that cannot be read or written refuses the whole duplicate, where the old path carried a failed write past and then wrote the copy or refused it with the room half made. The #200 A guard still fires when a rename is SKIPPED (its new name taken by a page made after the plan was shown, or a new page's place taken); a page that cannot be read no longer skips a rename (it refuses the step), so `DuplicateClassTests.ALinkRewrittenInsideTheLessonCannotFoolTheGuard` builds the skip with a page of the teacher's own at Day 5 (Days 1-4 and 6 laid, so the plan renames 6, 4 and 3, and only 6 -> 7 happens) instead of the mac's unreadable page.

## Changed tests and sentences

- New class `UndoDuplicateClassStepTests` (six tests): one step in the mac's order with every op's `afterSha` the disk's; the copy refused after the room is planned makes the room alone in one step; a read-only page changes nothing; a part-way stop; an edit made while it plans is never written over; nothing else moving, today's undo records the copy with no before.
- `DuplicateClassTests.ALinkRewrittenInsideTheLessonCannotFoolTheGuard`: the skip built as above; also asserts the room alone is made (Day 7, and the link in Day 3 rewritten).
- `InsertClassesTests.ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken` → `ADuplicateWhoseNewPageCouldNotBeSaved_ChangesNothingAndIsNotStillTaken` (Unit 1, Day 2's copy, so the folder lands on a path no rename touches; "Nothing was changed", never "is still there", nothing written).
- `UndoMakeRoomStepTests.AmongBlankPagesAPageThatComesOutUnchangedIsNotInTheStep` → `AmongPagesThatDifferOnlyInTitleAndDateAPageThatComesOutUnchangedIsNotInTheStep` (W7b2-1 review 2, L2).
- `NamedGapLedger`: `duplicateClass` out of the `Reason899W7b2` row, which now holds exactly `notTodayOnTheFrontPage`, `answerTheLinksChecklist` and `keepClassesDatedLater`; `Reason899W7b2` says "W7b2-2 converted Duplicate Class" and lists Not Today, the links checklist and Classes Dated Later kept at Deploy as still to convert. `Reason899NoDuplicateAsNextClass` (row `duplicateAsTheNextClass`, unchanged) now says W7b2-3 converts it (it said "W7b2 converts it with Duplicate Class").
- `UndoWriterScanTests.Allowed["Plantoir.Core/Assist/AssistWorkspace.cs"]`: count 4 → 2 (`File.WriteAllText` in `Save`, still used by `ApplyIndexChange`, W7b2; `File.Move` of the rollover's marker, W7c); the W7b2-2 clause gone, Duplicate Class among the actions through the door.

## Must-fail lines

File `vm-tools/guest/899-w7b2-2-mustfail.json` (ASCII anchors), run by `899-w7b2-2-go.ps1` with `899-w7b2-2-pc-run.ps1` (a copy of `899-w7b2-1-pc-run.ps1`).

MUSTFAIL-RESULTS

## Runs

RUNS

## Left for the next piece

- Duplicate as Next Class from the menu (W7b2-3, `AssistWorkspace.MenuDuplicate.cs`, row `duplicateAsTheNextClass`).
- W7b2-1 review 1's lows not fixed here (harness work, and the brief asks for no harness run): the kill harness `w7-make-room-kill` never runs pages that differ only in title and date (pinned in the unit test `AmongPagesThatDiffer…` instead, now with must-fail row 5); and in shadow a kill part way through the swap can leave one lesson under two names until the backup is restored (written in W7b2-1's notes for documentation 12; live recovery puts every page one way).

## For the director

- First: W7b2-1 and this branch merge together.
- W7b2-1's must-fail file rows 3 and 5 anchor on `int created = 0;` / `created++;` in `PlanTheRoom`; this piece changed those lines (`var created = new List<string>();`, `created.Add(path);`), so those two rows read NOT-FOUND on this branch. W7b2-1's file is its own record and was not changed; a re-run of it on the merged tree needs those two anchors moved.
- No `contracts/` change. The stash "w7b1 half-written Make Room and Duplicate, 2026-11-21" is untouched (read with `git stash show -p`, never applied, popped or dropped).

## Self-check

SELFCHECK
