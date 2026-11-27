Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# U4b3 (#899): Insert Class renames a later class that is a link by moving the link

Base `origin/dev` 253f8915f (the brief's 0e12bc8ac or later). Branch `issue/899-u4b3-linked-class-page-moves-its-link`.

**Stopped at its first half, by COMMON's "a piece that grows past its brief stops".** The step's half is built and proven; Insert Class itself is unchanged and still refuses a linked later class. The reason is a door rule the brief did not foresee, parked below under "For the director".

## For PROGRESS

U4b3 first half: `JournaledStep` plans a write at a link move's `to` (same folder) at the file the link leads to, and refuses "cannot tell now" before anything changes a write at a link move's `from` or through a link moved to another folder. Insert Class unchanged (still refuses a linked later class); the door rule it needs is parked.

## Why the piece stopped (the blocker)

Insert Class renames highest day first: Day 3 (the link) to Day 4, then Day 2 to Day 3, then the new class at Day 2. With the link moved as itself (`moveLink`), the place it LEAVES (Day 3) is filled in the same step by the class below it (or, when the insertion is at Day 3, by the new class). That always happens: the lowest renamed class's old name is where the new class goes.

The door does not judge a place a move leaves as free:

- Forward, `UndoCheck.plan` reads a `writeFile` op's place from the disk (`UndoItem.read(at: root/path)`, about line 379), where the link still is: `.notAFile`, so a `before: absent` write is "cannot tell" or "changed since". The `carriers` rule (U4b) only covers a place at or inside a move's `to`.
- A move that carries no edit goes into `wholeTargets`, swapped AFTER the files, so even a write judged absent would be swapped in while the link is still there.
- Backward, the move back (Day 4 to Day 3) is judged by `UndoOpKinds.wholeState` against the page the step wrote at Day 3: its `from` side is not free, so "changed since".
- `JournaledStep.plan` reads `plannedBefore` at the place as it is now (the link), so the step cannot even be recorded: `recordableChanges` is nil.

Making that work is a door change in both directions, a sentence in `undoJournal.opKinds.wholeOps`, the Python model, kill-recovery proof, and both gates: past this brief's budget (115k estimate, 150k cap) on its own.

## What landed

`mac-app/QuartzTeachers/Models/Undo/JournaledStep.swift`:

- `placeALinkLeadsTo`: a place that is exactly a planned link move's `to`, within the same folder, is `CourseConfiguration.fileALinkLeadsTo(from)`: the file the link leads to, the same before and after the move (the brief's "trap": never the link's new place, which would be an edit inside a link's `to`). This is the ONE place; `ClassInsertionPlanner` is unchanged.
- `refusedBeforeMaking` (new): a write planned at a link move's `from`, or at the `to` of a link moved to another folder, plans nothing and makes `make()` throw `refused(.cannotTellNow)` before anything changes. The first is the blocker above, held safely: without it the write at Day 3 would follow the leaving link and land in the linked file.
- `plannedLinkMove(endingAt:)`, `plannedLinkMove(startingAt:)`, `staysInItsFolder`, `refusesAWrite(at:)`.

Tests (`JournaledStepTests`, section "a write after a link's move (U4b3)"):

- `testAWriteAtALinkMovesNewPlaceIsPlannedAtTheFileItLeadsTo`
- `testAWriteThroughALinkMovedToAnotherFolderIsRefusedBeforeAnythingChanges`
- `testAWriteAtThePlaceALinkMoveLeavesIsRefusedBeforeAnythingChanges`

`documentation/09-mac-app.md`: paragraph "U4b3: linked-class-page-moves-its-link".

Not done (all of the brief's Done-means items 1 to 6 that depend on Insert Class moving the link): the Insert Class and Duplicate Class tests, the recovery kill test, the `undo.rule.shadow` clause, the `stackCases` row and `linkedPage` key, the Python model, the Windows test rename, the ledger reason, the documentation 12 notes. Each would be false while the Mac still refuses; in particular the Windows test's new name `..._WhereTheMacMovesTheLink_...` and its phrase "moves the link itself to the new name" must wait for the Mac to do it. The riding low (night25-7 sweep LOW 1) is therefore not fixed: the test's name still promises pieces 14 and 15, which landed without settling it; it should now promise the door piece below.

## For documentation 12

Nothing yet: Windows is unchanged and no contract row was added. When the door piece lands, Windows' door needs the same rule (a place an earlier move of the step leaves is judged free for a later op of the same step, the move swapped first going forward, and judged free once the step's own op there is taken back going backward).

## Must-fail lines

See `windows-app/notes/899-u4b3-mustfail.log`.

## Runs

Through `xlock.sh`, base 253f8915f (origin/dev unchanged at hand-back, so no merge commit was needed: the branch is based on the current dev).

- run-1: JournaledStepTests, UndoRenameFolderStepTests, ClassPlanningTests, DuplicateAsNextClassTests, UndoWriterScanTests, UndoSweepFindingsTests: 128 tests, 0 failures.
- run-mustfail, run-mustfail2: see the must-fail log.
- run-final: the six above plus the fourteen classes that read documentation 09 (AboutWindowLinksTests, AlertKeysTests, CloudSyncNoticeLayoutTests, DetailTabsLayoutTests, CourseSettingsTeardownTests, ListTableGoldenTests, RestoreRecoveryTests, ProgressViewSizeTests, TodaysClassOnTheFrontPageTests, SharedRulesContractTests, TickTableTests, UpdateRemindersTests, WorkingFolderSelectionTests, UnsavedSettingsNoticeLayoutTests): 310 tests, 0 failures.
- No Python run: `contracts/` untouched.

## Self-check

1. Each new test broken and seen failing: M1, M2, M3 (log). The tests cannot be run on the base (they read `refusedBeforeMaking`, new here).
2. No timed waits added.
3. Failure paths: a refused write says "cannot tell now" naming the file, before anything changes (tests assert link, target and pages unchanged). No teacher-facing sentence changed; Insert Class's sentences unchanged.
4. dev: based on origin/dev 253f8915f, which had not moved at hand-back.
5. No number tuned.
6. `contracts/` untouched; scope: JournaledStep, its tests, documentation 09, these notes.
7. House style grep empty on both Swift files; MARK sections present (new test section).
8. Riding low (night25-7 LOW 1) not fixed: renaming the Windows test to say the Mac moves the link would be false while the Mac refuses (see above).
9. Rename record kept, switch off: untouched.
10. No contract row added or changed; no ledger row.

## Left for the next piece

- The door rule above (parked), then U4b3 as briefed, with every item of its Done-means.
- `grep -n "step.remove(" mac-app/QuartzTeachers`: `ClassInsertionPlanner` and `PublishedPagesRecord` only, still so.

## For the director

**Parked: may the door judge a place a move of the same step leaves as free?** Insert Class cannot rename a linked later class as one step without it (see "Why the piece stopped").

- (a, recommended) A door piece first (U4b3a, Mac): in `UndoCheck.plan`, a file op at a place an EARLIER whole op of the same step moves away from is judged with that place absent going forward, and that move is swapped before it (a leading target, as a move that carries edits is); going backward, the move back is judged with its `from` free once the step's own op there has been taken back. `JournaledStep.plan` records `.absent` as the `before` of a write at a planned link move's `from` (replacing this piece's refusal). A sentence in `undoJournal.opKinds.wholeOps`; the Python model; a kill test after every swap; both gates. Then U4b3 as briefed, on top.
- (b) Leave Insert Class refusing a linked later class on the Mac until W8b, and say so in `undo.rule.shadow`.
