Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# U4b3 door-6 (#899): JournaledStep reads a link move's old place as free and makes its ops in a handing-over order

Branch `issue/899-u4b3-linked-class-page-moves-its-link`, from door-5's head bf6f9b229. `origin/dev` 461ee3943 was already merged in (by door-5) at both points this piece checked, so no new merge commit. No `contracts/` change.

## For PROGRESS

- `JournaledStep` now plans a step that hands a place over: the place a planned `moveLink` leaves reads as free through the plan (`fileExists` false, `readText`/`readData` nil, `readTextOrThrow` throws, not in `markdownFiles`) until something is planned there (`isLeftFreeByALinkMove`).
- A write there is planned at the place itself (`placeALinkLeadsTo` no longer follows a leaving link), its before `.absent`, and named from the folder above (`namedPath`), so it is recorded as a `writeFile` with `beforeSha` null. `refusesAWrite`'s first clause is gone; its another-folder clause stays.
- A link's new place (`to`, same folder) is read and written as the file it leads to even when the step also removes the page there (`plannedKey`, `plan`), and it is listed once by `markdownFiles` at its new name. A removal planned at a link's `to` reads its before at the place itself, never through `placeOnDiskNow`.
- One order function, `JournaledStep.inHandingOverOrder(_:opsOf:)`, built on the door's own finder pieces (`UndoCheck.placeFilled`, `placeLeft`, `handsOverAsAMove`, the `partInside` comparison): an item that fills a place goes straight after a later item that leaves it, until none does. `makeAsOps` (the recorded ops), `makeWithoutARecord` (the swap targets, file targets at a link's place marked `handedOver`) and `writePlainly` use it. A step with no such pair keeps its order exactly (the function moves nothing). Bounded by n² passes, so a circle of places stops and the door refuses it.
- A link moved onto a page the step keeps: nothing checks it at planning; the door refuses it `changedSince` and nothing changes (pinned by test).

## For documentation 12

- Windows' door (`UndoDoor`) must, for W8b piece 22's Insert Class: read the place a link's planned move leaves as free (no file, no text, not listed) until a write is planned there; plan such a write as a new file at that place (before absent, never followed through the leaving link, named from the folder above it); read and write a link's new place (same folder) as the file the link leads to, even where the step removes the page the link moves over; and order a step's ops, recorded or unrecorded, so each leaver precedes its filler, using the same leaver/filler definition as its handover finder (door-1's). A step with no handed-over place keeps its order. No ledger row is held by this piece.

## Must-fail lines

`windows-app/notes/899-u4b3-door-6-mustfail.log`. Red first: 5 of 6 new tests failed on door-5's head (the sixth pins the unchanged `changedSince` refusal). M1 (`fileExists` follows the leaving link): shape A and shape B fail. M2 (before read from disk at the link's `from`): five tests fail, refused `cannotTellNow` (the brief expected "could not record"; the unrecorded path refuses a `notAFile` before, so the step is refused instead; the test fails either way). M3 (today's order): shape B and shape C `notReadable`, unrecorded `changedSince`. M4 (another-folder clause removed): the another-folder test fails. RED 4 of 4.

## Runs

- `.dd/run-d6-red.log`: JournaledStepTests on door-5's sources plus the new tests: 21 run, 16 failures (5 tests).
- `.dd/run-d6-green1.log`: JournaledStepTests, 21, 0 failures.
- `.dd/run-d6-proof1.log`: JournaledStepTests, UndoHandedOverPlaceTests, UndoWriterScanTests, UndoRenameFolderStepTests, ClassPlanningTests, DuplicateAsNextClassTests, UndoActionStepsTests: 176 tests, 0 failures. No class reading documentation 09 as text reads the Undo sections (grep of the 14 readers for U4b3/Undo: none).
- `.dd/run-d6-M1.log` to `-M4.log`: the must-fail runs.

`grep -n "step.remove(" mac-app/QuartzTeachers`: still `ClassInsertionPlanner` (one call) and `PublishedPagesRecord` (two) only.

## Left for the next piece

- Part 2 (`ClassInsertionPlanner`): its rename loop writes the next class then removes the old; for a linked class it now calls `moveLink` (highest first). A retitle of the moved link is planned by writing at the link's new name (resolves to the target), also after a removal at that name. Nothing of this piece is half done.

## For the director

Nothing parked.

## Self-check

1. Broke each fix and watched it fail: M1 to M4 (log).
2. No timed waits.
3. Failure paths: a link moved onto a kept page refuses `changedSince`; a write through a link moved to another folder still refuses "cannot tell now"; no new sentence a teacher reads.
4. `dev` already merged (461ee3943, unchanged).
5. No number tuned by trial (the n² bound is the most moves an insertion order needs).
6. Scope: `JournaledStep.swift`, `JournaledStepTests.swift`, documentation 09 (door paragraph sentence added, first half's paragraph corrected), these notes and the log.
7. The grep for `DispatchQueue|.map {|.filter {|.reduce(|$0` over the added Swift lines is empty; MARK sections in place.
8. No riding lows.
9. The rename record is still kept and the switch is still off (not touched).
10. No contract row added or changed.
