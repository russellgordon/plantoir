# #1055 M3: the door has no relink where the link stands

Branch `issue/1055-M3-no-relink-where-the-link-stands`, base `origin/day27b/integration-5` (28707360c). Touches `contracts/`: both gates (the director's). Merge window 2 with M4, M5 and M6.

## For PROGRESS

- Mac #1055 M3 (2026-11-27): the door knows no relink where the link stands again. A `move` whose `from` and `to` are one place carrying `linkShaBefore`/`linkShaAfter` is `notReadable` (a barrier), as before mac-1. Door files back to `454ef4c6f` plus 28707360c's three comment hunks; mac-1's and mac-2's door tests, rows, trail event, contract sentences and model parts removed. No teacher-visible wording changed (the one trail line removed was never shown).

## What was removed

- Door (`git checkout 454ef4c6f` in the worktree, then `git show 28707360c -- mac-app/QuartzTeachers/Models/Undo | git apply`): `UndoCheck.swift` (`relinkWhereItStands`, `relinksOwnNames`, `settleUnderARelinksStagedName`, `linksOfTheStep` threading, mac-2's `UndoRelinkOutcome` and `UndoSwap` hunks), `JournaledStep.swift`, `JournaledWrite.swift` (`relinkSwapped`, `relinkExchangeBackFails`, the kept-item hook), `UndoFormat.swift` (`isARelinkWhereItStands`, `isOnePathByteForByte` and its comment, the second overlap exception), `UndoOpKinds.swift` (`stateWhereTheLinkStands`), `UndoRecovery.swift`, `UndoStoppedStep.swift`, `UndoAppSeams.swift` (`keptAnItemFoundWhereALinkWasChangedLine`), `ActivityTrail.swift` (`undoKeptAnItemFoundWhereALinkWasChanged`). `SpecialFolderRenamer.swift` untouched (its mac-1 comment about records kept). 000fc990c's only Mac change was the comment on `isOnePathByteForByte`, a removed function: nothing to re-add.
- The one check line: `git diff 454ef4c6f HEAD -- mac-app/QuartzTeachers/Models/Undo mac-app/QuartzTeachers/Scripting/ActivityTrail.swift` is `2 files changed, 5 insertions(+), 4 deletions(-)`, and its hunks are byte for byte 28707360c's three comment hunks (compared with `diff`; only index lines and hunk line numbers differ).
- Tests: `UndoRelinkTests.swift` is `454ef4c6f`'s 16 tests with `dad8bdcbc`'s four hunks that land on them (two of its six hunks were on mac-1 tests and went with them), plus this piece's three tests and the two helpers they use (`layARelinkWhereItStands`, `textsWhereItStands`). `UndoContractReplay.swift`: the `platform` key and its skip, the `inPlace` call, the `relinkSwapped:` stop point, cases counted as `cases.count` again. `UndoContractReplayKinds.swift`: the call `relinkALinkWhereItStands` and its case. `UndoJournalContractTests`: recovery count 85 with `454ef4c6f`'s line. `UndoWriterScanTests`: `UndoCheck.swift` 19 with `454ef4c6f`'s sentence (mac-2 had not changed it).
- `shared-rules.json`: the 11 checkCases "mac-1, a relink where the link stands: …" rows; the 8 recoveryCases rows (4 plain, 4 "on Windows"); the activityTrail event "undo kept an item found where a link was being changed"; `checkCasesHow`'s clause on a relink where the link stands; `recoveryCasesHow`'s "mac-1: inPlace …" sentences to its end; from row "mac-1, a rename that changes both case and Unicode normalisation …"'s `why` the clause "only the one-place test of a relink where the link stands compares bytes". `undo.rule.recovery`, `stagedThenSwapped` and `knownLimits` already read as at `454ef4c6f` (checked by a word diff of every undo string against `454ef4c6f`; every other difference is M1's and M2's and stays).
- `file-formats.json`: `opKinds.move`'s "A second exception (mac-1, #899): a relink where the link stands …" to the end of the field (the guarantee, both mechanisms, the pre-clean rule and the kept-item trail clause are inside it). `wholeOps`' NFC-and-lowercase sentence stays; its clause "only the one-place test of a relink where the link stands, from and to one path, compares bytes" goes, the attribution "(review 2 of mac-1, LOW 1)" kept.
- `contracts/README.md`: nothing. `git diff b1591adcb^1 b1591adcb -- contracts/README.md` holds only W8b's Rename folder lines (pieces 15b and 18b), no relink line.
- Python: `make_undo_traces.py` back to `454ef4c6f` but for the NFC-and-lowercase comparison (`import unicodedata`, `part_inside`, `move_carries`, `is_case_only_move`, comments included); `is_a_relink_in_place`, `SET_ASIDE`, `settle_what_was_set_aside`, the in-place branches of `move_state`, `hands_over_as_a_move`, `stopped_part_way`, `remove_the_links_just_made`, `recover` and `whole_moved` gone. `test_make_undo_traces.py`: `RelinkRecoveryByStateTests`, `readable_op`'s exception, the relink recovery test's `inPlace` branch, its count back to 13. `python3 scripts/test_make_undo_traces.py`: 42 tests OK; it did not say the traces were stale, so none were regenerated.
- Notes: `899-mac-1-a-relink-where-the-link-stands.md` gained the line "Removed by #1055 …"; `899-mac-2-…` already had it from M1.

## Row-count script

```text wrap
checkCases 158 -> 147; the 147 kept are in the same order and byte for byte the same but for row "mac-1, a rename that changes both case and Unicode normalisation …" (its why only)
recoveryCases 93 -> 85; the 85 kept in the same order and byte for byte the same: True
```

## Windows ledger edit (`windows-app/Plantoir.Tests/NamedGapLedger.cs`, the only Windows file edited)

- The `Owed(UndoCheckCases, 899, V200, Reason899W8RelinkedLink, …)` block (7 names) gone whole: the entry before it ends `"),`, the next line is the comment `// ---- U2b …`.
- The `Owed(UndoRecoveryCases, 899, V200, Reason899W8RelinkedLink, …)` block (8 names) gone whole; the comment above it ("U4b3 relink-3 and reviews D and F … went when Windows' W8b-21b3 built …") stays; the next line is the comment `// ---- U3c …`.
- The `Owed(ActivityTrailEvents, …, "undo kept an item found where a link was being changed"),` line and its comment line gone: the entry before ends `"section restore kept files"),`, the next line is blank, then a comment.
- The constant `Reason899W8RelinkedLink` gone: no `.cs` file in `windows-app` uses it. Every line removed was a whole line; no line was edited, so no quote, comma, parenthesis or brace was changed. Floors hold (checkCases 147, recoveryCases 85). `git grep -n "mac-1" -- windows-app/Plantoir.Tests` finds only a comment in `UndoRelinkTests.cs` (542).

## For documentation 12

Windows' `UndoSwap` relink-where-it-stands code (about 1334 and 1524) is dead from now: no contract row reaches it, and the Mac reads the shape `notReadable`. It stays until W2. Windows' suite stays at its six known failures: the removed rows were held, so no Windows test that ran changes.

## Runs

- Red, tests first on the base (2b4b89d9d, 13:57): `testARelinkWhereTheLinkStandsIsAShapeThisVersionCannotRead` failed (8 lines, `windows-app/notes/1055-M3-mustfail.log`); `testACapitalisationAndNormalisationRenameIsStillACapitalisationOnlyMove` and `testATwoPlaceRelinkIsStillReadAndJudgedAsToday` passed. After the red run, test 1 took its after-the-barrier snapshot once the step was written (the raw step writes the folder's identity file), so it compares like with like.
- Test 2 (`testAnUndoLeftPartWayUnderARelinksStagedNameSaysNoKeptItemLine`) is not written: test 1 proves the op is `notReadable`, so a step holding it is a barrier that recovery never settles and the kept-item path cannot be reached.
- Green after the removal (9ab0d5077, 14:04, one run through `xlock.sh`): `UndoRelinkTests` (19), `UndoJournalContractTests`, `UndoFilesContractTests`, `UndoWriterScanTests`, `UndoStoppedStepTests`, `UndoHandedOverPlaceTests` (it holds the kept-page tests), `JournaledStepTests`, `UndoOpKindsTests`, `UndoDoorGuardTests`, `SharedRulesContractTests`, `FileFormatsContractTests`, `ActivityTrailWiringTests` (it pins `activityTrail` against `ActivityTrail.Event`), `ActivityTrailPlaceTests`: 281 tests, 0 failures. Test 1 green, 3 and 4 green both times. Then a plain Debug build: BUILD SUCCEEDED. `python3 scripts/test_make_undo_traces.py`: 42 tests OK.
- `origin/dev` had not taken integration-5 by hand-back (it was at 99499d6b7), so nothing was merged in; the branch is on 28707360c.

## COMMON's self-check

- Switch off; nothing offered; no UI class, never the app; every `xcodebuild` through `xlock.sh` with the 15-minute kill; one class list per run.
- No new Swift beyond three tests: explicit types, no `map`/`filter`/`reduce`, no `$0`, no GCD, no timed waits; MARK section added.
- No teacher-visible wording changed; no new handling or edge case.
- No `rm` with a wildcard; nothing committed in `vm-tools`.

## For the director

- `git grep -n "Reason899W8RelinkedLink" -- windows-app` is not empty: it finds the comment the brief keeps (`NamedGapLedger.cs` 678, "rows held here under Reason899W8RelinkedLink went …"), `PROGRESS.md` and older notes files, all history. No code uses it.
