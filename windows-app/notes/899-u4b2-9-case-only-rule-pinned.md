# U4b2-9: case-only-rule-pinned (#899)

Branch `issue/899-u4b2-9-case-only-rule-pinned`, from `origin/dev` 24fcbc718. `origin/dev` merged before proving and again before hand-back: both "Already up to date" (dev still 24fcbc718), so no merge commit.

## For PROGRESS

- Mac: whether a path is at or inside a move's `to` is ONE comparison, `UndoOp.partInside` (part by part, without regard to case, the rest spelled as the path spells it). `placesOverlap`, `moveCarries`, the swap's `ownFilesInside` and `followTheMove`, `placeBeforeTheMove`, the plan's carried-page override (`UndoCheck.swift` about line 308) and recovery's `carryingMoveState` call it. Python mirrors it (`part_inside`, `places_overlap`, `place_before_the_move` in `scripts/make_undo_traces.py`).
- The capitalisation-only rows can now fail on the rule they name: `checkCases` "…lists it as `to`, holding something else: changed since" is replaced by "move of a folder between two names that differ only in case, in the last part: the folder lists it as `to`, holding the content: as the step left it"; new row "…the folder lists it under a third spelling, holding the content: changed since" (new `current` key `listedAs`).
- Riding lows: `undo.wording.renameFolderUnderWaySpinner` ("Renaming", the sheet spinner's VoiceOver label); `linksChecklist.wording.pagesYouTicked` ("the pages you ticked"); `folderRenameRecord` examples are the real bytes (Mac `\/`, Windows CRLF) and the Mac's are compared byte for byte; the U4b2-4 replay asserts its two removed blobs sit in different prefix folders; README, `undo.wording.note`, `folderRenameRecord.note` and a ledger comment made true.

## For documentation 12

- **W8's one comparison.** Windows' `UndoOp.PlacesOverlap` (`Plantoir.Core/Undo/UndoFormat.cs` about line 148) is already case-insensitive. When W8 builds the carrying move (opKinds.wholeOps' exception) and the case-only move, every "is this path at or inside that place" must be the same function: whether an edit is carried (`to` against the edit's path), which of the swap's own staged files and kept originals are inside the moved folder (left out of the pair), where they are after the folder moves, and a carried page's place before the move. Compare part by part (split on `/`), each part case-insensitively (`ToLowerInvariant` as `PlacesOverlap` does), and keep the rest as the path spells it. The trap the Mac had: an edit named `Renamed/a.md` under a move to `renamed` counted as carried, but the swap's kept original at `Renamed/.a.md.plantoir-undo-1-undo-orig` was compared as spelled, so it was not followed when the folder moved back and was left inside `media/` after an Undo that otherwise went back.
- **`listedAs` in checkCases.** For a move's `current`: a spelling, neither `from` nor `to`, that the folder lists the item under; what `atTo` describes is made at that spelling instead of at `to`. On NTFS (case-insensitive) that is one item under a third spelling; judged by the spelling listed, that is neither side, so changed since both ways.
- **Which held rows fail on Windows today, and why** (the PC run at the gate must show each FAILING): every case-only `checkCases` row ("move between two names that differ only in case, in the last part: …" ×3 and "move of a folder between two names …") comes to `notReadable` on Windows, because `UndoFormat.cs` about line 674 refuses a move whose `from` and `to` overlap by `PlacesOverlap`, and a case-only pair does; each row expects `canUndo`, `alreadyBack` or `changedSince`, never `notReadable`. (This reads `windows-app/` today: the U4b notes' worry that the "something else" row might PASS on Windows was about W6 reading `move`; readability refuses first. That row is gone anyway.) The three U4b case-only `stackCases` fail because Windows' replay does not know `renameAFolderInCaseOnly`.
- **Record bytes.** Windows writes the rename record with Newtonsoft `Formatting.Indented`, whose line ends are CRLF on Windows, then one LF; `folderRenameRecord`'s first example now says so. When W8 writes the Mac's keys it need not match the Mac's bytes (the Mac escapes `/` as `\/`); both parse alike, and only the Mac compares its own bytes.
- **Windows should read `linksChecklist.wording.pagesYouTicked`** where `UndoLinksChecklistStepTests.cs` (on `issue/899-w7b2-8-links-checklist`, lines about 248 to 252) scrapes "the pages you ticked" out of `LinksChecklistPublisher.swift`.
- **`renameFolderUnderWaySpinner`**: W8's rename sheet's progress ring gets this accessible name.

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
- `JournaledStep.namedPath` and `placeOnDiskNow` (the writer naming a place inside a planned folder move) still compare as spelled; they name places while a step is made and judge no carrying move, so they were left. If a writer ever names an edit with other capitals than its move's `to`, those two should call `partInside` too.
- Review 2 of U4b2-4, LOW 2 (how a "same file name" is compared beyond capitals: canonical equivalence on the Mac) is not in this brief and stays where it was.

## For the director

- `contracts/` changed (`shared-rules.json`, `file-formats.json`, `README.md`): both gates.
- **For the PC run at the gate:** the held rows by name under `Reason899W8U4b` are now "move between two names that differ only in case, in the last part: the folder lists it as `to`, holding the content: as the step left it", "…as `from`, holding the content: as before", "move of a folder between two names that differ only in case, in the last part: the folder lists it as `to`, holding the content: as the step left it" and "move between two names that differ only in case, in the last part: the folder lists it under a third spelling, holding the content: changed since". Each should FAIL on Windows as `notReadable` (readability, `UndoFormat.cs` line 674). The three U4b case-only stack rows fail on the unknown call `renameAFolderInCaseOnly`. The row "…holding something else: changed since" was replaced, so its ledger name is gone; names checked by script against the contract byte for byte.
- **Windows should now read `linksChecklist.wording.pagesYouTicked`** in `UndoLinksChecklistStepTests.cs` instead of scraping the Swift (W7b2-8 review 1, L2). I did not edit the Windows test.
- The brief's must-fail "the spelling rule out of `wholeState`: EVERY case-only row fails" cannot hold for the third-spelling row: without the rule a case-only move's two sides read one item and come to neither, which is exactly `.another`'s answer, so any row whose right answer is "changed since" passes both ways. That row is pinned instead by `.another` folded into `.from` (S2), as the brief's next line asks. The MEDIA stack row turned out to fail under both S1 (the step is never made) and S2, so the review's "the swap's own check refuses it anyway" was not so for S2: it was kept, name and all.
- Merge note: this branch touches `UndoCheck.swift`, `UndoFormat.swift`, `UndoRecovery.swift`, `CourseActivity.swift` (one constant), `StringListEditorView.swift` (one line, the spinner's label), `LinksChecklistWording.swift`, `LinksChecklistPublisher.swift` (one line), and tests. Not the rename sheet's logic, `FolderRenameRun`, `CourseSettingsView` or `AppDelegate`.
- HIG: the spinner's VoiceOver word is unchanged ("Renaming"), only moved into the contract; no interface a teacher sees or hears changed, so no HIG section was needed.

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
