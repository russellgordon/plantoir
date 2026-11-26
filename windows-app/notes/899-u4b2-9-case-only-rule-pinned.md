# U4b2-9: case-only-rule-pinned (#899)

Branch `issue/899-u4b2-9-case-only-rule-pinned`, from `origin/dev` 24fcbc718. `origin/dev` merged before proving and again before hand-back: both "Already up to date" (dev still 24fcbc718), so no merge commit. (Merged on 2026-11-26 in `night25/integration-6`, 5b782bec9, with U4b2-7, -8 and -10 and W7b2-3. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12. Review 1's H1, the Windows test that reads every key of `linksChecklist.wording`, is settled by 7edb554d2 on that branch, which adds the member `LinksChecklistWording.PagesYouTicked`.)

## Must-fail lines

See `windows-app/notes/899-u4b2-9-mustfail.log`. In short: S0 red first (the new `UndoOpKindsTests` case, lines 127 and 131); S1 the spelling rule out of `wholeState`: both old file rows, the new folder row and all three case-only stack rows RED; the third-spelling row passes by construction (without the rule both spellings read one item: neither, which is what `.another` answers) and is pinned by S2; S2 `.another` folded into `.from`: the third-spelling row RED and also the MEDIA stack row (came to undone, MEDIA, old); S3 the comparisons split again: the `UndoOpKindsTests` case RED; S4 Python `is_case_only_move` always false: all seven case-only rows RED; S5 the riding lows' four pins RED. Restored byte for byte each time (`git status` clean).

## Runs

- `run-red1.log`: the two new `UndoOpKindsTests` cases before the change: the carrying-move case FAILED (two lines), `partInside`'s own case passed.
- `run-green1.log`: UndoJournalContractTests 19, UndoFilesContractTests 3, UndoOpKindsTests 26, UndoRenameFolderStepTests 38, UndoWriterScanTests 6 (reads `UndoCheck.swift` and `UndoRecovery.swift` as text): 92 tests, 0 failures.
- `run-lows1.log` (after the lows): SpecialFolderRenamerTests 51, UndoSweepFindingsTests 13, LinksChecklistTests, UndoJournalContractTests 19, and the classes that read a changed file as source text (SectionVerbsTests, NameTableTests, SheetTitleScanTests, AccessibilityNamesTests): 124 tests, 0 failures.
- `python3 scripts/test_make_undo_traces.py`: 31 tests OK; traces not stale (no regeneration; `undo-action-steps.json` not touched, so no date to put back).
- Logs in `/Users/russellgordon/plantoir/wt-899-u4b2-9/.dd/`.

## Left for the next piece

- For pieces 14 and 15 (review 1 of U4b2-6, L3): a moved LINK from an earlier run is neither named nor told. `SpecialFolderRenamer.foldersAtTheirNewName` and `placesAnEarlierRunMayHaveMoved` skip a place in the earlier record's `moved` or `mayHaveMoved` that is a link now (`case .absent, .link, .somethingElse: continue`), because the record keeps no `isALink`. So with a linked special folder `Concepts` moved to `Ideas` by a killed run, a finish run that stops part way says "did not rename"/"was not renamed" while the link sits at `Ideas`. Rare (a linked special folder and two failures); either record which moved places are links, or tell such a place as "cannot tell".
- (Corrected by review 1, L2: the earlier line here said `JournaledStep.placeOnDiskNow` and `namedPath` judge no carrying move. Wrong: `placeOnDiskNow` decides where a planned edit's before is read and whether its swap target is staged after the move. Both now call `partInside`.)
- Review 2 of U4b2-4, LOW 2 (how a "same file name" is compared beyond capitals: canonical equivalence on the Mac) is not in this brief and stays where it was.

## For the director

- `contracts/` changed (`shared-rules.json`, `file-formats.json`, `README.md`): both gates.
- **For the PC run at the gate:** the held rows by name under `Reason899W8U4b` are now "move between two names that differ only in case, in the last part: the folder lists it as `to`, holding the content: as the step left it", "…as `from`, holding the content: as before", "move of a folder between two names that differ only in case, in the last part: the folder lists it as `to`, holding the content: as the step left it" and "move between two names that differ only in case, in the last part: the folder lists it under a third spelling, holding the content: changed since". Each should FAIL on Windows as `notReadable` (readability, `UndoFormat.cs` line 674). The three U4b case-only stack rows fail on the unknown call `renameAFolderInCaseOnly`. The row "…holding something else: changed since" was replaced, so its ledger name is gone; names checked by script against the contract byte for byte.
- **Windows should now read `linksChecklist.wording.pagesYouTicked`** in `UndoLinksChecklistStepTests.cs` instead of scraping the Swift (W7b2-8 review 1, L2). I did not edit the Windows test. (Done: 7edb554d2 on `night25/integration-6` reads the key in `UndoLinksChecklistStepTests.APressLeftPartWaySaysTheChecklistsPartWaySentence` and takes the read of the Swift source out.)
- The brief's must-fail "the spelling rule out of `wholeState`: EVERY case-only row fails" cannot hold for the third-spelling row: without the rule a case-only move's two sides read one item and come to neither, which is exactly `.another`'s answer, so any row whose right answer is "changed since" passes both ways. That row is pinned instead by `.another` folded into `.from` (S2), as the brief's next line asks. The MEDIA stack row turned out to fail under both S1 (the step is never made) and S2, so the review's "the swap's own check refuses it anyway" was not so for S2: it was kept, name and all.
- Merge note: this branch touches `UndoCheck.swift`, `UndoFormat.swift`, `UndoRecovery.swift`, `CourseActivity.swift` (one constant), `StringListEditorView.swift` (one line, the spinner's label), `LinksChecklistWording.swift`, `LinksChecklistPublisher.swift` (one line), and tests. Not the rename sheet's logic, `FolderRenameRun`, `CourseSettingsView` or `AppDelegate`.
- HIG: the spinner's VoiceOver word is unchanged ("Renaming"), only moved into the contract; no interface a teacher sees or hears changed, so no HIG section was needed.

## Review 1 (LOWs; H1 waits for a base not in `dev`)

- L1: `UndoMoveSide.read` matched a step's override keys to the listing as spelled; now by `partInside`, keeping the disk's spelling. Red first: `testAnEditSpelledWithOtherCapitalsBelowTheMovesToIsUndoneAndRedone` (Undo refused `changedSince(courses/TST1O/renamed)`).
- L2: `JournaledStep.placeOnDiskNow` and `namedPath` call `partInside`. Red first: `testTheWriterJudgesACarriedPlaceByTheOneComparison` (read at `Renamed/a.md`; named `courses/TST1O/Renamed/a.md`).
- L3: the case-only branch of `moveCarries` compares only the moved item's own part as spelled (Swift and Python). Red first: `testACaseOnlyMoveTellsItsSidesApartByTheFoldersOwnPart` and Python's `test_a_case_only_move_tells_its_sides_apart_by_the_folders_own_part`. Answers on `dev` unchanged otherwise (a third spelling is still carried, as before).
- L4: Python's `move_state` takes `listed_as` and gives `.another`'s neither itself; the harness passes the key. Must-fail: folded into `from` in the model, the third-spelling row FAILS in Python (`run-r1-mf-python.log`).
- For documentation 12: W8's listing override, its writer's carried place and the case-only side must use the same part-by-part comparison. (Folded into documentation 12.)
- Runs: `run-r1-red.log` (3 red), `run-r1-green.log` (UndoOpKindsTests 29 green), `run-r1-own.log` (95 green), Python 33 OK.

## Self-check

1. Broke each fix and watched its test fail: S0 to S5 above, each failing line named in the log.
2. No timed waits: none added.
3. Every sentence on the failure paths is true: no sentence a teacher reads changed; the contract notes that named Windows were checked against `windows-app/` (`SpecialFolderRenamer.cs` 166 to 214, `UndoActionStepTests.cs:169`, `UndoClassDatesStepTests.cs:191`, `UndoFormat.cs` 148 and 674).
4. `dev` merged before proving: 24fcbc718, already up to date both times.
5. No number tuned by trial.
6. House style and contracts: cases run from the JSON (the new key `listedAs` read by the Mac replay and by Python); nothing outside the brief and its named lows.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added Swift lines: empty; no new type authored.
8. Riding lows: part-two L1 and L2 fixed with tests red first; director's a (four), b L1 and L2 fixed with pins red first, b L3 written above; c fixed (red by S5); d fixed (red by S5).
9. The rename record is still kept; `undoJournalIsLive` untouched (off).
10. Every new or changed contract row is in the Mac's replay (`testCheckCases`) and Python's, and held by exact name on Windows (2 new names; 1 name removed with its row).
