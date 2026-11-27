# #1055 W4: Windows moves no link as itself (W8-6, W8b-21, 21a6's link half)

Branch `issue/1055-W4-windows-moves-no-link`, base `origin/issue/1055-W3-windows-hands-no-place-over` 4c4891a62. `origin/dev` f5b2d69c8 merged in before proving (0571d6e26: one script file, `scripts/test_front_page_title_repair.py`); merged again before hand-back (see "Runs").

Russell's rule (#1055, settled): Plantoir reads and writes through a symbolic link and has no other link code. This piece removes Windows' link move and adds no refusal and no sentence. `contracts/` changed: ONE `undo.checkCases` row and one `checkCasesHow` clause, so **both gates** in merge window 3.

## Commits

- f5756a639 tests first (seen RED on the PC, run `1055-W4-red`).
- df720d51c the removal, W3 review LOW 1, the notes' top lines.
- 0571d6e26 merge of `origin/dev`.

## What was removed (each from the commit that brought it)

- `UndoActionStep.cs`: `MoveLink` (3a90282ed, W8b-21); `_folderMoves`' `LinkSha` member, now `(FromFull, ToFull, ListingSha)` as at `3a90282ed^`; `FolderMoveOp`'s link branch; `PlaceOnDiskNow`'s and `WritePlainlyQuietly`'s link skips (3a90282ed); `LinkMoveEndingAt`, `LinkMoveStartingAt`, `StaysInItsFolder`, `IsLeftFreeByALinkMove` and its three uses, `RefuseAWriteAtALinkMovedAway` and its two calls, `PlannedPlace` and `ShownAs` (inlined away: `Path.GetFullPath` and the caller's path, as at `ccc292a54^`), `Plan`'s `throughALink` and its leaving-place branch, `Remove`'s remark, `RecordableChanges`' and the plain write's leaving-place exceptions (ccc292a54, W8b-21a6). The comment "the door hands it over" (W3 review 1, LOW 1) went with `LinkMoveStartingAt`. `MoveFolder`'s summary no longer points at `MoveLink`; its guard is unchanged.
- `UndoFormat.cs`: `UndoOp.LinkSha`, the reader's `linkSha` key, the blob check, the count (a move is "exactly one of `sha` and `listingSha`" again: `(op.Sha is not null) != (op.ListingSha is not null)`, as at fb93fc00b^1), `MoveCarries`' link line and its summary sentence (W8-6, merge fb93fc00b). W2 had already removed `IsALinksMove` and `LinkText`.
- `UndoOpKinds.cs`: `UndoMoveSides`' link branch and `ReadALink` (W8-6); `UndoLinks.LinkSha` (W8-6), `UndoLinks.IsALinkToAFolder` (3a90282ed), `UndoLinks.FileALinkLeadsTo` (ccc292a54; no caller left).
- `UndoPlaces.cs`: `StaysInside(root, relative, op)` and `StaysInsideAbove`; `FirstPlaceLeadingOut` calls `StaysInside(root, place)`. The file is byte for byte fb93fc00b^1's.
- `UndoSwap.cs`: the `moving.Op.LinkSha is null &&` exception and the two three-argument `StaysInside` calls (W8-6).
- `UndoDoor.cs`: the comment on the leads-out check no longer names a link's move.
- `SpecialFolderRenamer.cs`: the plan loop is `step.MoveFolder(move.From, move.To)` for every move; `IsAPlaceToMove` is `3a90282ed^`'s one line (a folder, a link or a place that cannot be looked at); `Rename`'s summary no longer names `MoveLink`; W8b-18b's link half: `planned` is a list of destinations, no `IsALink`, no `movedALinkHere`, so a link at the new name is never counted as this run's (cannot-tell). The 18a comment in `PlacesAnEarlierRunMayHaveMoved` ("a rename moves a linked folder as the link") now says a link there is told as cannot-tell; its code is unchanged.
- Tests: `UndoLinkMoveTests.cs` and `UndoActionStepLinkTests.cs` deleted; `UndoActionStepFolderMoveTests`' four `MoveLink` tests and `ALibraryOutside`; `UndoRenameFolderStepTests`' W8b-21 tests (junction, relative symbolic link, leading out twice, leading nowhere, a link to a file skipped) with `TheStepMovesTheLinkAsItself`, `ALibrary`, `LinkTo`; `UndoCheckContractTests`' `LinkMoveCases`, `LaysALinkWithItsTarget`, the count's `+ LinkMoveCases().Count()`, `OpOf`'s `linkTarget` translation and `PlaceAt`'s `withItsTarget`; `UndoStackContractTests`' `LinkCases`, `LaysASymbolicLink`, the three link calls (`moveALinkToAFolder`, `renameAPerSectionFolderThatIsALink`, `stepEditingInsideALinksMove`: no contract row has any of them), `TheLinksMove`, `LayTheLinkToTheLibrary`, the link constants, and the `linkedFolder` key with `LinkedFolder()` (no contract row carries it; it was in `KeysChecked` only); `SpecialFolderRenamerTests`' moved-link half of the link test (now `ALinkAtTheNewNameIsCannotTellNeverNamed`) and the tuples in its `FoldersAtTheirNewName` calls.
- Lines: 17 files outside the notes, 336 inserted, 1342 deleted (product: 7 files, 74 inserted, 375 deleted).

## What was kept, and why (grep at the head)

- `CourseConfiguration.FileALinkLeadsTo` (`CourseConfiguration.cs` 231, 387, 449, 476, 488): the settings file's write-through, untouched.
- `UndoLinks.Look`, `UndoLinks.What`, `UndoCurrent.ReadWithoutFollowingALink`, `MoveFolder`'s link check (`UndoActionStep.cs` 343), `FirstPlaceLeadingOut` (seven files), `KeepPagesWhosePlaceIsTaken`, `PlanRelinkedPages` (page text), `SymbolicLinkFactAttribute` (now in `SymbolicLinkAttributes.cs` with `SymbolicLinkTheoryAttribute`, `UndoSymbolicLinks`, `ReparsePointFactAttribute` and `UndoReparsePoints`, moved first, unchanged but for the LOW below).
- The leftover walk that never goes through a link (`UndoTestSupport.StagedLeftovers`, 70cb9665b): a guard.
- `HandsOverAsAMove` with its file-move half: the director's ruling from W3 review 1 (it is the mac's shared definition, reached once Windows records a file's own move). Pinned now by `UndoFormatTests.OnlyAFilesOwnMoveLeavesAndFillsAPlace` (W3 review 1, LOW 2): `PlaceLeftBy`/`PlaceFilledBy` name a `sha` move's `from`/`to`, and nothing for a `listingSha` move, a capitalisation-only move or an older build's link move. W3's must-fail row 3 is row 4 here.
- From `UndoLinkMoveTests`, the two `UndoLinks.Look` pins, moved to `UndoKeptPageUnderAVisibleNameTests` (the class that holds `ReadWithoutFollowingALink`'s tests): `AWslStyleLinkIsALinkAndNeverReadThrough` and `AReparsePointThatIsNotANameSurrogateIsAFileNeverALink`, their link-move halves dropped.
- `UndoRenameFolderStepTests`: the destination that is a link (283), the walk that never goes through a link (`AnEntryThatCannotBeLookedAt…`, `ALinkInsideTheCourseIsNotWalked`), both OneDrive placeholder tests (the `move["linkSha"]` null line dropped), and `ALinkWhoseTargetCannotBeReadRefusesTheRename…` (a WSL link: it pins the same general guard, its summary rewritten).
- `UndoActionStepFolderMoveTests.AFolderThatIsALinkIsRefusedCannotTellNowAndNothingChanges` (`MoveFolder`'s guard).
- The done grep's two hits left: `UndoFormatTests.AStepWhoseMoveCarriesALinkShaIsUnreadable` (test 2's name) and `UndoSwap.UndoStagedFile`'s `isALink` parameter (#899 W3, a kept original that is a link, a guard older than the link line). Test 2's `linkSha` key is written `\"linkSha\"` in C# and so does not match `linkSha"`.
- W2 review 1, LOW (the 21b skip sentence): `UndoSymbolicLinks`' skip sentence is back to its words before 6bc055127 ("Developer Mode is off, as in the VMs"), as W2's brief asked; the two other copies went with `LinkMoveCases` and `LinkCases`.

## Rename Folder of a linked folder now

- **Windows:** `IsAPlaceToMove` counts the link, `MoveFolder`'s own guard refuses it `cannotTellNow` before anything changes, and the rename says `SpecialNames.RenameFolderNothingWasChanged` with `UndoActionStep.Reason`'s `cannotTellNow` sentence: "“Tasks” was not renamed, and nothing was changed: “Tasks” could not be read just now." Nothing recorded (`APlaceOfTheFolderThatIsALinkStopsThePlanCannotTellNowAndChangesNothing`, taken back from `5e86468cd^`).
- **Mac** (read from ORDER's re-cut, M2, not re-measured here): `UndoTreeReading.read` uses `lstat`, a link is `.notATree`, and the plan throws; the sheet shows "The file “Tasks” couldn’t be saved." The two sentences differ; nothing makes them agree.
- A section's place that is a link to a FILE is refused the same way on Windows (as before W8b-21), while the mac skips it: ORDER's question 6, parked for Russell; nothing built or pinned for it.

## The contract row

Added after "move naming neither a file's hash nor a folder's listing: not readable" (index 83), the shape row it belongs with: "a move carrying an older build's linkSha (a link's move, gone by #1055): not readable, never acted on, never a reason to clear", op `{"kind": "move", "from": "Tasks", "to": "Notes", "linkSha": "8a6853af…e37a"}` (SHA-256 of `../library`), `current` row 63's shape (`atFrom` absent, `atTo` text), `undo` and `redo` `notReadable`, with the brief's `why`. `checkCasesHow` gained ", and a move's linkSha as the 64-character hash itself (an older build's link move, which no build makes now)" after the listing clause.

Row-count script (base 4c4891a62 against head, by `json` in Python):

```text wrap
checkCases 134 -> 135
undo keys changed: ['checkCases', 'checkCasesHow']
added: ["a move carrying an older build's linkSha (a link's move, gone by #1055): not readable, never acted on, never a reason to clear"] at index 83
others identical: True
outside undo identical: True
```

How each platform read it:
- Mac, no Mac code changed: `UndoJournalContractTests`, `UndoOpKindsTests`, `SharedRulesContractTests` through `xlock.sh`, 125 tests, 0 failures, `** TEST SUCCEEDED **` (with the row in place).
- Python: `python3 scripts/test_make_undo_traces.py`, 38 tests OK (with the row in place).
- Windows: RED on the base, green after (below).

## Runs (the PC, under `C:\vm-setup\wt-compare.lock`)

Hardware: LENOVO 20QES70500, Intel Core i5-8365U @ 1.60GHz, 16 GB, Windows 11 Pro 26200. Script `vm-tools/guest/1055-W4-pc-run.ps1` (a copy of W3's), started by `C:\vm-setup\1055-W4-launch.ps1`, which reads the class filter from a file (the filter's `|` does not survive SSH quoting).

- `1055-W4-red` (ref f5756a639, the tests-first commit, before any product change), RUN_DONE 18:15: `UndoCheckContractTests`, `UndoFormatTests`, `UndoRenameFolderStepTests`, 384 passed, **3 failed, the three new tests and only those**:
  1. `EveryCheckCase("a move carrying an older build's linkSha …")`: `UndoCheckContractTests.cs` line 235 then 204, `Assert.Equal() Failure: Strings differ`, expected `notReadable` (Windows read the move as a link's).
  2. `AStepWhoseMoveCarriesALinkShaIsUnreadable`: `UndoFormatTests.cs` line 168, `Assert.False() Failure` (the step was readable).
  3. `APlaceOfTheFolderThatIsALinkStopsThePlanCannotTellNowAndChangesNothing`: `UndoRenameFolderStepTests.cs` line 323, `Assert.Throws() Failure: No exception was thrown` (the link was renamed).
  `OnlyAFilesOwnMoveLeavesAndFillsAPlace` passed on the base, as a pin of unchanged code should; must-fail row 4 shows it bites.
- `1055-W4-a` (ref 0571d6e26, dev merged), RUN_DONE 18:27: `BUILD-APP-EXIT 0` (0 errors, 37 warnings, none new), `BUILD-TESTS-EXIT 0`; the brief's classes (`UndoCheckContractTests`, `UndoStackContractTests`, `UndoRecoveryContractTests`, `UndoFormatTests`, `UndoSwapTests`, `UndoRecoveryTests`, `UndoDoorTests`, `UndoActionStepTests`, `UndoActionStepsOnWindowsTests`, `UndoActionStepFolderMoveTests`, `UndoRenameFolderStepTests`, `SpecialFolderRenamerTests`, `UndoSaveCourseSettingsStepTests` (the linked settings file's write-through; the brief's `UndoCourseSettingsStepTests` does not exist), `UndoKeptPageUnderAVisibleNameTests`, `UndoThinningKeptCopiesTests`, `UndoMakeRoomStepTests`, `UndoStoppedStepTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`; Windows has no `FileFormatsContractTests`) **927 passed, 0 failed, 0 skipped of 927**, 42 s. Then must-fail and the harness (below). HEAD-AFTER SAME, STATUS clean, LOCK-RELEASED (its own).
- `UndoWriterScanTests` needed no change: it had no allowance for the link move.
- Mac (this Mac, `xlock.sh`, own derived data in the scratchpad): `UndoJournalContractTests`, `UndoOpKindsTests`, `SharedRulesContractTests`, 125 tests, 0 failures. Python: `scripts/test_make_undo_traces.py` 38 OK, run again at the head before hand-back.

## Must-fail (`vm-tools/guest/1055-W4-mustfail.json`, run `1055-W4-a`; each restored with `git checkout`, then 927 of 927 again)

1. The reader takes `linkSha` back (read as the move's content): **RED**, `AStepWhoseMoveCarriesALinkShaIsUnreadable` (`Assert.False() Failure`) and the contract row (`Strings differ`), 2 failed of 136.
2. `MoveFolder`'s link check removed (`Look(from) is Link or CannotLook` → `is CannotLook`): **NOT RED**, 2 of 2 passed (test 3 and 235). Read from the code: `UndoTreeReading.Read` (`UndoOpKinds.cs` 548) looks without following, gives a link no tree, so `ListingSha` is null and the same `cannotTellNow` refusal is thrown by the second half of the same `if`. The link arm is a second check of one rule; nothing was changed for it (the brief keeps the guard). For the director.
3. `IsAPlaceToMove` skips a link: **RED**, test 3 and `ALinkWhoseTargetCannotBeReadRefusesTheRename…` (`No exception was thrown`: the link left unrenamed and the rename said done), 2 failed of 13.
4. W3's owed row, `HandsOverAsAMove` false for a file's move: **RED**, `OnlyAFilesOwnMoveLeavesAndFillsAPlace` (`Strings differ`, expected "Unit 1, Day 2.md").

## Harness (run `1055-W4-a`, outside OneDrive and inside it, OneDrive running)

`w7-plain-kill` 3 of 3, `w7-make-room-kill` 12 of 12, `w8-carrying-move-kill` 36 of 36, failures 0, every result WHOLE, each exit 0 in both places: the same as W3's `1055-W3-b`. Scratch folders removed.

## Self-check (W7b2's list, then W8 COMMON's 11 to 14)

1. Tests first: the three new tests seen RED on the PC at f5756a639 before any product change (lines above). Each change broken: must-fail rows 1, 3, 4 RED; row 2 not red, explained above.
2. No timed waits added; each PC run waited for on its log's `RUN_DONE`.
3. Failure paths: no teacher-facing sentence added or changed; the refusal a linked folder meets is `MoveFolder`'s existing one. Every comment touched says only what the code now does (`MoveFolder`, `PlaceOnDiskNow`, `RecordableFolderMoves`, `MoveCarries`, the move shape, the door's leads-out step, `IsAPlaceToMove`, `FoldersAtTheirNewName`, `PlacesAnEarlierRunMayHaveMoved`).
4. `origin/dev` merged before proving (0571d6e26) and checked again before hand-back (an ancestor).
5. No number tuned by trial.
6. Contract cases run from the JSON: the new row is read by `name` in all three readers; its hash was computed by a script, not typed.
11. No held row was made to pass; no ledger reason named a link move; nothing left the ledger.
12. No key added. The stack replay's `linkedFolder` key was removed with its member: no contract row carries it.
13. One function per rule: no new comparison; "is this a link" stays `UndoLinks.Look`.
14. No run left going, no lock left held, none removed that this piece did not take.

## For documentation 12

Windows moves no link as itself: a journal `move` carrying `linkSha` is unreadable, a barrier, as on the mac after M6 (one `undo.checkCases` row holds it on both). A linked folder's Rename Folder falls to `MoveFolder`'s guard (`cannotTellNow`, "“Tasks” was not renamed, and nothing was changed: “Tasks” could not be read just now."). A linked `course_config.json` is still saved through its link (`CourseConfiguration.FileALinkLeadsTo`).

## Parked

- ORDER's question 6 stands (a section's place that is a link to a file: Windows refuses the rename, the mac skips that section). Not re-parked; the director's readings answer it.
