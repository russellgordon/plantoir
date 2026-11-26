# U4b2-1: a linked page is written through its link, switch off (#899)

Branch `issue/899-u4b2-1-linked-page-written-through`, from `origin/dev` a03fecefd (U4b merged).

## For PROGRESS

- Mac: with `undoJournalIsLive` off, a daily action whose page is a symbolic link now writes the file the link leads to, and the link stays a link (Russell's ruling on #899, 2026-11-25). Before, the Mac refused such a page from U3 on. Windows already behaved so; no Windows code owed.

## For documentation 12

- `undo.rule.shadow` now states ONE rule for both platforms: a linked page is written through its link and stays a link; a folder (a link to a folder included) or a file that cannot be read is refused before anything changes; a part-way stop keeps what the file held beside the file the link leads to. Windows' `UndoActionStepTests.WithTheSwitchOffALinkedPageIsWrittenThroughItsLinkAndStaysALink` and `APlainWriteLeftPartWayIsSaidAsPartWayAndNamesTheKeptFile(throughALink: true)` are the twins of the Mac's `UndoSweepFindingsTests` cases.
- Stale line to correct: documentation 12, about line 18033, "2. **Switch-off refusals (finding 3).** `undo.rule.shadow` now says: with the switch off, a daily action whose file is a link, a folder or unreadable is refused before anything changes ..." The link part is no longer true on either platform.
- One difference that stays (shadow only, nothing offered): the Mac NAMES a link to a file inside the working folder in a step, at that file (a shadow record, no trail line); Windows writes every linked page plainly with a `wentAhead` trail line. A link to a file outside the working folder is plain, with a `wentAhead` line, on both. See "For U7".

## Must-fail lines

RED 2 of 2; detail in `windows-app/notes/899-u4b2-1-mustfail.log`.

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

- A link whose target is missing (a dangling link) is now written through: the file is made at the place the link names, as Windows' `File.ResolveLinkTarget` path does. No test pins it either way; say if it should be refused.
- `remove` of a linked page is still refused (not a plain file). Which actions remove a page that could be a link, and whether that should remove the link, belongs with the move pieces (14 and 15).

## For U7

- Live, a link to a file inside the working folder is recorded at that file, so Undo would restore the file, the link untouched. A link to a file outside the working folder still cannot be named in a step, so live refuses it before anything changes. Windows writes every linked page plainly today; when the switch goes live the two platforms must agree whether an inside link is recorded (the Mac's way) or refused.

## For the director

- No parked questions.
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
