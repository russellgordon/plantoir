# #899 U4b2-6: rename-sentences-in-contract

Branch `issue/899-u4b2-6-rename-sentences-in-contract`, from `origin/issue/899-u4b2-5-part-way-line-true` e734c495b (which contains `dev` da7474047). `origin/dev` merged before proving and before hand-back: both times already up to date at da7474047 (no merge commit made).

## Must-fail lines

RED 8 of 8; each line is in `windows-app/notes/899-u4b2-6-mustfail.log`:

- S1: a Swift sentence changed by one byte; both pins fail.
- S2: the replace refusal's key dropped; the sequence row fails.
- S3 to S7: one each for L1, L2, L3, L5 and L4.
- S8: the fixture's `.md` put back.

Tests first:

- run-red1: the two pin tests ran against the contract without the new keys. Both failed: :442 XCTUnwrap and :431 dict compare.
- The record tests were written against the new API, so they could not compile against the old code. Their red is S3 to S7, each of which puts back the code before the fix: the fallback, no carry-forward, a joined string, a map-of-strings cast, and "was not renamed".

## Runs

- red1: the two pin tests: 2 failures (above).
- green1: UndoSweepFindingsTests, CourseActivityTests, ReferenceReplacerTests, SharedRulesContractTests, ReferenceShelfTests, UndoWriterScanTests: 134 tests, 0 failures.
- a1: SpecialFolderRenamerTests, UndoRenameFolderStepTests, UndoSweepFindingsTests, FileFormatsContractTests, SharedRulesContractTests, and the readers of `CourseSettingsView.swift` as source text (AccessibilityNamesTests, GradedFolderChoicesTests, SaveEnablesTests, SettingsSaveNoticeTests, TwoWindowSettingsTests), plus UndoWriterScanTests: 250 tests, 0 failures.
- c1: `testEveryDailyActionIsOneStepThroughTheDoor` with `TEST_RUNNER_PLANTOIR_WRITE_UNDO_ACTION_STEPS=1` (writes the file).
- c2: UndoActionStepsTests, UndoJournalContractTests: 36 tests, 0 failures.
- `python3 scripts/make_undo_traces.py` (20 traces, 150 action traces), then `python3 scripts/test_make_undo_traces.py`: 31 OK.
- mf1, mf2, s3 to s8: the sabotages above.

## Left for the next piece

- U4b2-4 review 2, LOW 1 (the replay's two "cannot be stored" calls should check that the two removed blobs sit in different prefix folders): the calls `firstIndexAfterContentGoneAndCannotBeStored` and `secondIndexBeforeContentGoneAndCannotBeStored` are piece 4's, in `origin/issue/899-u4b2-4-kept-line-by-path`, and are not in this branch. It belongs after piece 4 merges, and is a one-line `XCTAssertNotEqual` of the two `deletingLastPathComponent()` paths in the replay.

## For the director

- **Windows' `WindowsOwnJson` entry for `keepClassesDatedLater`** (`origin/issue/899-w7b2-7-sheet-records`, `UndoActionStepsOnWindowsTests.cs` about line 67) ends "where the mac's recorded step names the page with its .md (its fixture's place)". That clause is no longer true once this branch merges: the Mac's recorded `after` now names `section1/All Classes/Unit 1, Day 3`, without `.md`, as Windows does.
  - Its `SameMembers` (`version`, `answeredAt`) does not include `kept`, so its test still passes either way.
  - Only the `Why` sentence should drop that clause.
  - Not changed here (Windows code).
- **The class-dates step's `before` is not reproducible.** Writing `undo-action-steps.json` rewrote another step's `before` `"recorded"` with today's date (2026-11-26 for 2026-11-20).
  - That hunk was put back by hand, so only `keepClassesDatedLater` changed.
  - The compare tolerates the date (c2 is green), but the next writer will meet the same thing.
- `contracts/` changed: `shared-rules.json` (four `undo.wording` keys, its `note`, `folder renamed` → `carries`, one replace sequence case and its `rule`), `file-formats.json` (`folderRenameRecord`), `undo-action-steps.json`, `undo-traces.json`. Both gates.

## Self-check

1. Broke each fix and watched its test fail: S1 to S8, RED 8 of 8.
2. No timed waits added.
3. Every sentence on the failure paths is true:
   - A stopped rename now says "may have been renamed only in part" when it cannot check, never "was not renamed".
   - The `carries` and the record's format say what the Mac does.
   - Windows' behaviour was read in `windows-app/` before it was written down (record writer `SpecialFolderRenamer.cs:160-170`, readers :178-214).
4. `dev` da7474047 was already contained; both merges were up to date.
5. No number tuned.
6. Contract cases run from the JSON (the sequence case, the file-format examples).
7. House style: the grep over added Swift lines is empty. `RenameRecordNote` has a MARK section.
8. Riding lows: each fixed with a red test, except U4b2-4 LOW 1 (above, not in this base).
   - U4b2-5 L1 to L5: S3 to S7. L6: piece 5's notes rewritten.
   - Part eight's L4: the ledger reason.
   - The fixture: S8.
   - U4b2-4 LOW 2: written for documentation 12.
9. The rename record is still written before and cleared after. `undoJournalIsLive` was not touched.
10. Every new row is in the Mac's replay. None is held: no Windows reader exists (above).

HIG: Writing (read 2026-11-26) for the one new sentence: be clear, put the most important information first, use as few words as possible.
