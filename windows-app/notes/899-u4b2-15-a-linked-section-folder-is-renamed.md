# U4b2-15: a-linked-section-folder-is-renamed (#899)

Branch `issue/899-u4b2-15-a-linked-section-folder-is-renamed`, from piece 14's pushed head c64e741ef (holds `dev` 811c956ce, pieces 9, 10, 14). `origin/dev` merged before proving and again before hand-back: both "Already up to date" (`dev` still 811c956ce), so no merge commit.

## The old code's answers (read before writing, `5cf38d656`)

1. Pages INSIDE the linked folder's target were not walked through the link: `markdownPages` is a `FileManager` enumerator, which does not descend into a symbolic link (checked by a scratch script: it lists the link, never its contents). A target elsewhere in the course had its pages walked and relinked at their own place; a target outside the course was never touched.
2. A link leading out of the working folder was renamed like any other: `fileExists(atPath:isDirectory:)` follows the link (a folder), then `moveItem` renames the link itself.

Neither answer writes outside the working folder, so nothing is parked for that case: every case is built to its final state.

## For PROGRESS

- Mac: Rename folder renames a per-section or shared folder that is itself a symbolic link by moving the LINK, in the one step, as before U4b. `SpecialFolderRenamer.plan` reads a link (by `lstat`, after the following `fileExists` test found a folder) with `UndoTreeReading.linkSha(at:)` (new: the one function for "SHA-256 of `readlink`'s bytes"; `UndoMoveSide.readLink` now judges by it too). `FolderRenamePlan.Move.listingSha` is now `sha` (a listing's or a link's). `apply` plans a link with `JournaledStep.moveLink(_:to:linkSha:)` (new); `plannedFolderMoves` carries `listingSha?`/`linkSha?`, one op builder `JournaledStep.folderMoveOp`. The step names a link's `from` from the folder above it (`relativePath` resolves a link to its target; must-fail S5).
- Pages: walked exactly as before (never through a link); a page in the target, when the target is inside the course, is relinked at its own place, so no edit sits inside a link's `to` (a link's move carries none, piece 14).
- Riding L3 (`2026-11-25-899-u4b2-6-review-1.md`): a link at the new name this run did not move there, at a place an earlier run's record names (`moved`) or may have moved (`mayHaveMoved`, or the fallback for a record without `moved`), is now told as `cannotTellWhose` ("could not tell whether this rename moved these: …"; the sheet's "may have been renamed only in part"), never dropped and never named "still called". Why not a new record key (`movedLinks`): the record would need a new field in `folderRenameRecord`, its readers on both platforms and a Windows test of the field list, to tell apart a case (two failures over a linked special folder) that "cannot tell" states truthfully.
- Per-course (shared) folders that are links take the same code path: one test, a shared `Concepts` linking OUT of the working folder (renamed, the outside folder and its page byte for byte unchanged, Undo puts the link back).
- Contract (prose only, no row, no key): `shared-rules.json` → `activityTrail.mustRecord` `folderRenamed.carries` (the link clause), `undo.rule.shadow` (the promise "until the pieces that move a link (14 and 15) settle it" replaced, below); `file-formats.json` → `folderRenameRecord.fields.mayHaveMoved.why` ("a folder, or a link"), `undoJournal.opKinds.move` (Rename folder records a link move). No Windows test reads any changed words (checked: `UndoMakeRoomStepTests` reads three other substrings of `undo.rule.shadow`, all unchanged; `folderRenamed.carries` has no reader but the event key).
- Recorded steps: unchanged. The `renameFolder` and `renameFolderPerSection` fixtures in `undo-action-steps.json` hold no link, so their ops are the same; nothing to regenerate at the merge with pieces 11 to 13.

## For documentation 12

- **W8's Rename folder moves a linked folder as a link.** For each place of the folder (one per section, or the course's own), when the place is a reparse point (symbolic link / junction) to a folder: plan a `move` with `linkSha` (SHA-256 of the UTF-8 bytes of the stored `LinkTarget`, as piece 14's paragraph says), `from` the link's own path named from the folder above it (never `ResolveLinkTarget`, which would name the target), `to` the same folder with the new name. Never list, read or move what it leads to, wherever it is (inside the course, outside the working folder, nowhere). A link whose target cannot be read refuses the rename "cannot tell now", nothing changed. A link to something that is not a folder is skipped, as a file at that place is today.
- **Pages:** walk the course without descending into a link. Windows' walk today, `PagePaths.MarkdownPages` (`Plantoir.Core/Models/PagePaths.cs` about 165), recurses into any entry whose attributes have `FileAttributes.Directory`, which a link to a folder has too (with `ReparsePoint`), so it DOES walk through a link: for Rename folder's step it must skip an entry with `FileAttributes.ReparsePoint`. A page inside the target is relinked only where the walk finds it at its own place inside the course. Planning a page under a link's `to` makes the step one no reader can read (a link's move carries no edit).
- **Part-way line:** a link at the new name counts as "still called" only where this run moved a link there; any other link at a place the earlier record names or may have moved is "could not tell whether this rename moved these".
- **Windows today:** `Plantoir.Core/Models/SpecialFolderRenamer.cs` (about 274) moves each place with `Directory.Move` outside the door, and finds the places with `Directory.Exists`, which follows a link; what `Directory.Move` does to a link to a folder on NTFS is not measured here (W8 should check it moves the link, not the target), and its page walk goes through the link (above).

## Must-fail lines

`windows-app/notes/899-u4b2-15-mustfail.log`. Red first: the six new or changed tests, 6 of 6. S1 the plan's link branch refusing again: the four step tests RED (`:719`). S2c the move made on the link's target: RED at `:723`/`:724`, the target-untouched assertions. S3, S4 (L3): RED at `SpecialFolderRenamerTests:900` and `:982`. S5 the link's `from` resolved: RED (refused by the door). 5 of 5 RED, restored each time.

What each new test proves: `testAPerSectionFolderThatIsALinkIsRenamedByMovingTheLink` (live): one step, the link's op is `move` with `linkSha` and the link's own `from`, the target untouched, the pages relinked as the old code would, settings changed, Undo and Redo move the link back and forth; `testWithTheSwitchOffAPerSectionFolderThatIsALinkIsRenamedAsBeforeU4b` (shadow, the app today): renamed as before U4b; `testALinkedSectionsRenameKilledBeforeAnyOfItsSwapsIsWholeAfterRecovery`: killed before each swap, recovery leaves every place whole before or whole after (the link back at `Tasks` or at the new name, same target); `testASharedFolderThatIsALinkOutOfTheWorkingFolderIsRenamedAndWhatItLeadsToIsUntouched`: the shared path and the out-of-folder case.

## Runs

- `run-green1.log`: UndoRenameFolderStepTests, SpecialFolderRenamerTests, UndoJournalContractTests: 113, 0 failures.
- `run-red1.log`: the product at c64e741ef with the new tests: 6 tests red (29 assertion failures).
- `run-mf-S1`, `S2`, `S2b`, `S2c`, `S3`, `S4`, `S5`.
- `run-own.log`: UndoRenameFolderStepTests, SpecialFolderRenamerTests, UndoJournalContractTests, UndoWriterScanTests (reads the three changed product files as text), SharedRulesContractTests, FileFormatsContractTests, UndoSweepFindingsTests (comment changed), UndoOpKindsTests (`readLink` now calls `linkSha`): 250, 0 failures.
- `python3 scripts/test_make_undo_traces.py`: 33 OK; traces not stale.
- Logs in `/Users/russellgordon/plantoir/wt-899-u4b2-15/.dd/`.

## Left for the next piece

- A case-only rename (`Tasks` to `tasks`) of a folder that is a link is not exercised; the door's case-only move of a link is piece 14's and has no row.
- A link whose target is another of the same rename's places (`section2/Tasks` → `../section1/Tasks`) is renamed with its target kept as written, so after the rename it leads to the old name, as before U4b. Not told.
- The plan's destination test is `fileExists` (follows): a dangling link at the new name is not refused by the plan; the door then refuses the move (`to` not free). As before; unchanged.

## For the director

- **`undo.rule.shadow` changed.** "Removing a page that is a link, or renaming one away, still differs until the pieces that move a link (14 and 15) settle it:" is now "Removing a page that is a link, or renaming one away, still differs, and no piece yet settles it: the door moves a link as itself (U4b2-14) and Rename folder uses that for a folder that is itself a link (U4b2-15), but no writer of a page does:". The Windows test `UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15` reads only three substrings, all still present byte for byte: "never follows the link and is refused before anything changes", "saving a plain copy at the new name and deleting the link itself, the linked file left untouched", "held by name in UndoMakeRoomStepTests.<its name>". So the PC stays green with no Windows change. Its name and its `settle` message still say "U4b2-14 and 15"; renaming it would need the clause's "held by name" text changed in the same merge: if you rename the test to `…_WhereTheMacRefusesBeforeAnythingChanges`, the clause must then contain "held by name in UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges".
- **Parked: which piece settles a linked PAGE renamed away or removed (Insert Class renaming a later class that is a link)?** Nothing in v2.0.0 names one (searched the milestone; the digest's rulings do not settle it). Options: (a, recommended) a small Mac piece, U4b3, after this merge: Insert Class renames a later class that is a link by moving the link (`JournaledStep.moveLink`, as Rename folder now does), and W8 does the same, replacing Windows' plain copy plus deleted link (which loses the teacher's link); (b) Windows' behaviour on both: a plain copy at the new name and the link deleted; (c) leave the Mac refusing until U7 decides. (a) keeps the teacher's link and its file exactly as they were, which is what Rename folder now does for a folder.
- `contracts/` changed: both gates (taken with piece 14 anyway). No new row, no new key, no held row.
- HIG: nothing a teacher sees changed (a refused rename now goes ahead with the existing sentences; the part-way sentences are existing ones); no section read.

## Self-check

1. Broke each fix and watched its test fail: red first 6 of 6; S1, S2c, S3, S4, S5 all RED with the line named; restored each time.
2. No timed waits: none added (the kill test is event-driven by kill points).
3. Every sentence on the failure paths is true: a link that cannot be read refuses "cannot tell now", nothing changed; a link at the new name not this run's is told "could not tell whether this rename moved these", never "still called" and never dropped (the old "did not rename" for that case is gone, S3).
4. `dev` merged before proving and before hand-back: 811c956ce, already up to date both times.
5. No number tuned by trial: the kill test's "at least four swaps" is the step's shape.
6. Contracts: prose only; no row retyped; nothing outside the brief (one stale test comment in `UndoSweepFindingsTests` corrected).
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added Swift lines: empty; no new type authored (functions added to `JournaledStep`, `UndoTreeReading`, test helpers in their MARK sections; a new MARK section in the test class).
8. Riding L3 fixed with two tests that failed first (S3, S4).
9. The rename record is still written before the step and cleared after; `undoJournalIsLive` untouched (off).
10. No new or changed contract row; nothing to hold.
