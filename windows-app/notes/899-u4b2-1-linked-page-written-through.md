Kept by #1055 (2026-11-27): a page that is a link is written through it (Russell's rule).

# U4b2-1: a linked page is written through its link, switch off (#899)

Branch `issue/899-u4b2-1-linked-page-written-through`, from `origin/dev` a03fecefd (U4b merged).

## Review 1 fixes (1 MEDIUM, 5 LOW)

- MEDIUM 1, fixed: `undo.rule.shadow` now says the rule is for a WRITE: a step that removes a page that is a link, or renames one away (Insert Class renaming a later class that is a link), never follows the link and is refused before anything changes until the pieces that move a link (14 and 15); a new file planned where a link is is refused as there. Behaviour unchanged. Pinned by `testAShadowStepThatRemovesALinkedPageIsRefusedBeforeAnythingChanges` (write the new name, remove the link: refused `cannotTellNow`, "Nothing was changed.", new name not written, linked file and link untouched).
- LOW 1, fixed: a dangling link is written through (`testAShadowStepOnADanglingLinkMakesTheFileTheLinkLeadsTo`, inside: no trail line; outside: `wentAhead`). The refusal added here for a missing folder was reversed in review 2 (MEDIUM A).
- LOW 2, fixed: the contract names the recording difference (Mac names an inside link in a shadow step, no trail line; Windows writes it without the list with a `wentAhead` line; outside links unrecorded on both; which holds live is U7's).
- LOW 3, carried to U7: live, an inside link is now recorded at its file rather than refused. Unreachable while the switch is off; U7 decides it (already under "For U7"; now also in documentation 09).
- LOW 4, fixed: `testEveryWayOfPlanningAndReadingFollowsALink` plans through `write(_:to:plannedFrom:)` and `editJSON` on links inside and outside the working folder, and reads through `readData`, `readTextOrThrow`, `readText`; `fileExists` through a link is pinned in the dangling-link test (the disk says no file there, the plan says one). An end-to-end Publish action test was not added: the rule reaches actions only through `plan` and these entry points, every one now pinned.
- LOW 5, fixed: `// MARK: - Computed properties` before `// MARK: - Functions` in the test class.
- The unreadable-file test (the review's note) is unchanged and still not shown red by a sabotage of its own.

## Review 2 fixes (2 MEDIUM)

- MEDIUM A, fixed by the director's decision: the refusal of a dangling link whose folder is missing is gone. The Mac now makes the folder and writes the file through the link, as Windows does (`UndoSwap.MakeTheFolderOf`, `UndoSwap.cs` about line 336). The contract clause now says so. `testAShadowStepOnADanglingLinkWhoseFolderIsMissingMakesTheFolderAndTheFile` pins it: folder and file made, link still a link, no trail line inside, `wentAhead` outside.
- MEDIUM B, fixed in the contract and held: the removed or renamed-away clause is now marked as the Mac's. It says what Windows does today: `ApplyInsertClasses` saves a plain copy at the new name and deletes the link itself, outside the door. Neither platform's behaviour was changed. In `NamedGapLedger.cs`, `makeRoomForClasses` (UndoActionStepsOnWindows) moves to its own held row with a reason of its own, `Reason899W7b2MakeRoomLinkedPage`. That reason names W7b2's conversion and this linked-page difference, which pieces 14 and 15 settle. The row still fails on Windows: `MakeRoomForClasses` (the call the fixture runs, `UndoActionStepsOnWindowsTests` line 249) still writes file by file through `ApplyInsertClasses`, with no step of its own. The name matches the contract's `undo-action-steps.json` row byte for byte (checked by script). Limit: see "For the director".

## Must-fail lines

RED 9 of 9 standing (two in the first round, five from review 1, two from review 2; review 1's eighth pinned the missing-folder refusal, now reversed); detail in `windows-app/notes/899-u4b2-1-mustfail.log`.

1. Plan at the link's own place: `testAShadowStepOnALinkWritesThroughTheLinkAndTheLinkStaysALink` fails with "XCTAssertNoThrow failed: threw error refused(cannotTellNow ...) - the linked page was refused, outside: false" (and true); the part-way test fails at line 114, "not refused part way".
2. Folder refusal dropped in `writePlainly`: `testAShadowStepOnALinkToAFolderIsStillRefusedBeforeAnythingChanges` fails, "not refused as cannot tell now: refused(changedSince(... Media))".

Tests seen failing before the change (run-first.log): the turned-round test and the part-way test (both iterations). The folder and unreadable cases passed before and after; they pin what did not change, and the folder case is made real by must-fail 2.

## Runs

All on the main Mac, through `xlock.sh`, derived data `.dd/`.

- run-first.log: UndoSweepFindingsTests before the fix: 8 tests, 9 failures (expected).
- run-fix1.log: compile error (`fileALinkLeadsTo` main-actor isolated); fixed by marking it `nonisolated` (it reads no state).
- run-fix2.log: UndoSweepFindingsTests, 8 tests, 0 failures.
- run-mustfail1.log, run-mustfail1b.log, run-mustfail2.log: see above.
- run-own.log: UndoSweepFindingsTests, UndoActionStepsTests, UndoCourseSettingsStepTests, UndoJournalContractTests, UndoFilesContractTests, UndoWriterScanTests, SharedRulesContractTests, JournaledStepTests, and the three classes reading `CourseConfiguration.swift` as source (FileFormatsContractTests, CourseNameCharactersTests, ScheduledDeployCleanupTests): 219 tests, 0 failures, 0 skipped.
- Review 2 round: run-r2-own.log, the eleven classes plus the twelve documentation 09 readers, 318 tests, 0 failures; `test_make_undo_traces.py` OK; `origin/dev` still a03fecefd.
- Review 1 round: run-r1-own.log, the same eleven classes, 223 tests, 0 failures; run-r1-doc09.log, the twelve documentation 09 readers, 95 tests, 0 failures; `test_make_undo_traces.py` OK. `origin/dev` still a03fecefd.
- run-doc09.log: the twelve other classes that read documentation 09 as text (ListTableGoldenTests, DetailTabsLayoutTests, TickTableTests, UnsavedSettingsNoticeLayoutTests, CloudSyncNoticeLayoutTests, AboutWindowLinksTests, TodaysClassOnTheFrontPageTests, ProgressViewSizeTests, AlertKeysTests, WorkingFolderSelectionTests, CourseSettingsTeardownTests, UpdateRemindersTests): 95 tests, 0 failures.
- `python3 scripts/test_make_undo_traces.py`: 31 tests OK (no undo-trace rows changed).
- Merges of `origin/dev`: before proving and before hand-back, `origin/dev` was still a03fecefd, the base; nothing to merge, so no merge commit.

## What changed

- `JournaledStep.plan`, `write(_:to:plannedFrom:)` and `editJSON` plan at `placeALinkLeadsTo(url)` (the last component followed link by link, `CourseConfiguration.fileALinkLeadsTo`, the folders above as named). These are the only three places `plannedURL` is assigned (grep `plannedURL[`), so every daily action gets the rule from the planning; `writePlainly`, `makeWithoutARecord` and `recordableChanges` read the planned place.
- Reads through the plan (`readData`, `readText`, `readTextOrThrow`, `fileExists`) find a planned file by the link too (`plannedKey`).
- `writeNew` and `remove` never follow a link: removing what a link leads to would leave the link dangling, and a new file at a link's place is refused as "there" as before.
- A place carried by a planned folder move (U4b) is not followed: the move decides where it is.
- `undo.rule.shadow` reworded; documentation 09's "What cannot be named in a step" corrected and a "U4b2: linked-page-written-through" paragraph added before "Settings ▸ Other Assistants".
- No interface change, so no HIG section applies.

## Left for the next piece

- A link whose target is missing (a dangling link) is now written through: the file is made at the place the link names, as Windows' `File.ResolveLinkTarget` path does. (Settled since this was written: reviews 1 and 2 pinned it, written through, the folder made too.)
- `remove` of a linked page is still refused (not a plain file). Which actions remove a page that could be a link, and whether that should remove the link, belongs with the move pieces (14 and 15).

## For U7

- Live, a link to a file inside the working folder is recorded at that file, so Undo would restore the file, the link untouched. A link to a file outside the working folder still cannot be named in a step, so live refuses it before anything changes. Windows writes every linked page plainly today; when the switch goes live the two platforms must agree whether an inside link is recorded (the Mac's way) or refused.

## For the director

- The missing-folder refusal is reversed, as decided.
- One limit on the held row for MEDIUM B. On the PC, `makeRoomForClasses` fails today because W7b2 has not converted it. That failure does not come from the linked-page difference. No list Windows already runs can hold an action that is refused: a refused step records no row in `undo-action-steps.json`, and a new row shape would need Windows test code, which this piece may not write. So the PC run proves the row is held, not the difference. The difference travels in the row's reason, which W7b2's writer meets when converting it. Note that `makeRoomForClasses` is now on a line of its own, so a W7b2 branch that edits the old seven-key line will conflict here.
  Options, recommendation first:
  1. Accept this. When W7b2 converts Make Room, it adds a Windows case for a linked later class at the same moment.
  2. Brief a later piece to add a refused-action row shape to `undo-action-steps.json` and Windows' fixture.
- `contracts/` touched (`undo.rule.shadow` text only): both gates. No ledger rows (no new case).

## Self-check

1. Broke each fix and watched its test fail: two sabotages, RED 2 of 2 (above); restored, `git diff` clean.
2. No timed waits added, in product or test.
3. Failure paths: a refused linked folder or unreadable file still says "Nothing was changed." (asserted); a part-way stop names the kept file beside the linked file (asserted); a linked page that goes ahead says "went ahead" when it cannot be named, and nothing when it is recorded (asserted).
4. `dev` merged before proving: `origin/dev` was a03fecefd, the base, throughout.
5. No number tuned by trial.
6. Contract text changed in the JSON only; nothing outside the brief's scope changed (`CourseConfiguration.fileALinkLeadsTo` marked `nonisolated` so the door can call the one copy).
7. House style grep over the changed Swift lines: empty; MARK sections kept (a `// MARK: - Functions` section added to the test class).
8. No riding lows in this piece.
9. The rename record is untouched; the switch is still off.
10. No new contract row; `undo.rule.shadow` is prose, read by SharedRulesContractTests (green).
