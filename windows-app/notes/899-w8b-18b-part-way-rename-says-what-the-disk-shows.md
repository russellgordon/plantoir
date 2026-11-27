# #899 W8b-18b: a part-way rename's line and sentence say what the disk shows (2026-11-27)

Base: `origin/issue/899-w8b-18a-rename-record-shape` ef88c963c. Merges of `origin/dev` (8046ca2e8), before proving and before hand-back: already up to date every time, so no merge commits. Head proved: 5c44ad46d.

## For PROGRESS

- Rename folder's part-way ending is the mac's, in `Plantoir.Core/Models/SpecialFolderRenamer.cs`, called from `SpecialFolderRenamer.Rename`'s catch of `UndoStepLeftPartWayException`. The dialog shows the sentence (through `RenameException`, unchanged in `CourseSettingsView.xaml.cs`) and the same call writes the `folder renamed` trail line, before it throws. The record is kept (17's owner).
  - `FoldersAtTheirNewName` (the mac's `foldersAtTheirNewName`): a place is named as still called the new name only when it BELONGS (a move this run planned, or in the earlier same-rename record's `moved`, `PlacesMoved`) AND SHOWS (a folder by the no-follow look; a link only where this run moved a link; a capitalisation-only rename only when the folder's listing shows the new spelling). A place that belongs but is a link this run did not move, or that an earlier run may have moved (`PlacesAnEarlierRunMayHaveMoved`), is cannot-tell. A look that fails for any reason but "no such file" is unreadable, with the system's reason, never absent. Places compared by `HoldsThePlace` (built on `UndoOp.PartInside`).
  - `PartWayEnding` (the mac's `partWayEnding`) picks one of the three contract sentences and its line, as the brief's invariant says. The line helpers are the mac's `keptBesideWords`, `couldNotTellWords`, `couldNotTellWhoseWords`.
  - `WhatIsAt(path, spelledExactly, out said)` and `UndoLinks.Look(path, out said)` keep the system's message for a refused look or a failed listing; the two-argument forms call them, so "is this a link?" is still one function.
- A rename refused with nothing changed now says `undo.wording.renameFolderNothingWasChanged` around the door's or the system's reason, where the mac says it: a planning failure (a link whose target cannot be read, the settings' plan), and a make refused or failed with nothing changed (after the three changed-since re-plans). The destination-exists refusal stays bare, as on the mac (a `FolderRenameProblem`, said as itself).
- The four sentences are `SpecialNames.RenameFolderNothingWasChanged`, `…StoppedPartWay`, `…RenamedOnlyInPart`, `…MayBeRenamedInPart`, pinned by key to `shared-rules.json` → `undo.wording` (`SpecialFolderRenamerTests.TheRenameSentencesAreTheContractsOwnByKey`), the house way of W7b2-11.
- `HalfFailureMessage` ("Plantoir renamed m of n copies …") is gone with its two tests: no caller since 15b made the rename all or none.
- A test seam, `SpecialFolderRenamer.LookingAtAPlaceFails` (null in the app), lets a test show a refused look: a deny ACE does not stop the PC's SSH account (an administrator's token) looking.

## For documentation 12

- "What W8 owes from U4b2-5" and the "A part-way ending" bullets of "What W4c and W8 owe from U4b2-6": built on Windows (W8b-18b), as written. The bullet "Until W8, Windows' one part-way `folder renamed` line is 'renamed the folder … but could not write it to this course's settings'" is now untrue (15b removed that line; 18b says the three contract lines).
- U4b2-15's "Part-way line" bullet: built (a link counts only where this run moved a link).

## Tests that failed first

At ade58331b (the tests, with stubs that keep today's behaviour so that they build), run `w8b-18b-a`'s red half: 12 of 61 failed in `SpecialFolderRenamerTests`, every new test: `TheRenameSentencesAreTheContractsOwnByKey` and `EachSentenceIsTheContractsWithItsPlaceholdersFilled` ("Strings differ"), `ARefusalThatChangedNothingSaysRenameFolderNothingWasChanged`, `ARefusedFinishKeepsItsRecord`, `AFolderLeftAtTheNewNameIsNamedAndTheRenameSaysOnlyInPart`, `EveryFolderBackButAPageKeptSaysDidNotRename` and `AFinishWhoseRecordDoesNotSayWhatItMovedSaysMayHaveBeenRenamedInPart` ("String start does not match": the door's bare sentence), and `AFolderAtTheNewNameThatDoesNotBelongIsNeverNamed`, `APlaceTheEarlierRecordMovedIsNamed`, `ALinkThisRunDidNotMoveIsCannotTellNeverNamed`, `ACapitalisationOnlyRenameIsNamedOnlyWhereTheListingShowsTheNewSpelling` and `AnUnreadableCheckIsToldWithItsReasonNeverReadAsAbsent` ("Collections differ").

The only-in-part test was wrong twice before it was right (runs `a` to `c`): the step swaps in path order (section 1's move, its Quiz 1, section 1's index, then section 2's move), so the read-only index refuses before section 2 moves. It now blocks section 1's put-back with the `EachRename` seam. The product did not change for it.

## Must-fail lines

`vm-tools/guest/899-w8b-18b-mustfail.json`, run in `w8b-18b-d` at 5c44ad46d: 4 of 4 RED, each built with 0 errors; restored, 342 of 342 passed, HEAD the same, status clean.

1. A place counted by the disk alone (`belongs = true`): 4 failed, among them `APlaceTheEarlierRecordMovedIsNamed` and `ALinkThisRunDidNotMoveIsCannotTellNeverNamed` ("Collections differ") and `AFinishWhoseRecordDoesNotSayWhatItMovedSaysMayHaveBeenRenamedInPart` (the sentence began "“Tasks” was renamed only in part").
2. A link counted that this run did not move (`if (belongs)`): `ALinkThisRunDidNotMoveIsCannotTellNeverNamed`, "Collections differ".
3. An unreadable check read as absent (the unreadable branch only `continue`s): `AnUnreadableCheckIsToldWithItsReasonNeverReadAsAbsent`, "Collections differ".
4. A sentence retyped (`RenameFolderStoppedPartWay` in the trail's words, "could not put everything back: {said}"): `TheRenameSentencesAreTheContractsOwnByKey`, `EachSentenceIsTheContractsWithItsPlaceholdersFilled` ("Strings differ") and `EveryFolderBackButAPageKeptSaysDidNotRename` ("String start does not match").

## Runs

All on the PC, `899-w8b-18b-pc-run.ps1` (a copy of 18a's, its lock owner `899-w8b-18b <label>`) through `899-w8b-18b-launch-<label>.ps1`. Each run took and released its own lock; run `c` queued behind `int-d27-7`'s lock and waited at it.

- `w8b-18b-a` (02:59 to 03:10 EST), `classes,mustfail`, red ref ade58331b, at 6fe68e475: red half above; green half 341 of 342 (the only-in-part test); must-fail 4 of 4 RED.
- `w8b-18b-b` at 4382042b4: the same one test failing.
- `w8b-18b-c` at 3cebedcc3, `SpecialFolderRenamerTests` alone, with the renames tried named in the failure: it showed the swap order.
- `w8b-18b-d` (03:49 to 03:53) at 5c44ad46d, `classes,mustfail`: both builds 0 errors; 342 of 342 passed, 0 skipped, across `SpecialFolderRenamerTests`, `RenameRecordShapeTests`, `FolderRenameApplyTests`, `UndoRenameFolderStepTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests`; must-fail 4 of 4 RED; restored 342 of 342.

## Ledger

No row: no Windows test iterates `undo.wording` (documentation 12, U4b2-6), so nothing was held. `NamedGapLedgerTests` passed.

## Left for the next piece

- Nothing of this invariant. The cancel-while-planning and swap-refused `renameFolderNothingWasChanged` sentences the mac also says come with 20a (Windows has no planning Cancel yet).

## Self-check

- NIGHT3 items: tests first in their own commit (ade58331b), seen red; no interim state (no new control, no new sentence: all four are the contract's); no `contracts/`, `mac-app/`, documentation 12 or PROGRESS change; `undoJournalIsLive` untouched; pushed.
- 7, 8 (fixture row, writer scan): no fixture row; no write was added or moved, `UndoWriterScanTests` passed.
- 9: the riding low (`folderRenameRecord`'s note) is written below, as the brief allows no `contracts/` change.
- 10: the step's order is unchanged.
- 11, 12: no held row, no key added.
- 13: places are compared by `HoldsThePlace` (on `UndoOp.PartInside`), places named by `PlaceInside`; "is this a link?" is `UndoLinks.Look`, now with an overload that keeps the reason, which the old form calls.
- 14: no run left going, every lock released by its run, no other lock touched.

## For the director

- `contracts/` was not changed (the order file says no for 18b). Two contract sentences are now untrue of Windows and a later contract pass should change them:
  - `shared-rules.json` → `activityTrail.mustRecord` `folder renamed` → `carries`, its last sentence ("On Windows until W8, the one part-way state it records is … ('renamed the folder … but could not write it to this course's settings'); its other part-way stop, a move of some of the copies ('Plantoir renamed m of n copies …'), writes no line."). True now: Windows records a part-way rename as the mac does, with the same three lines.
  - `file-formats.json` → `folderRenameRecord` → `note` (18a's low): "Windows' reader today … takes each with ToString()" and "Windows today writes 'from', 'to' and 'scope' only" are untrue since 18a. True now: Windows reads `from`, `to` and `scope` only as JSON strings and every other key only in its own shape, and writes all five keys (`from`, `to`, `scope`, `moved`, `mayHaveMoved`, the last two left out when empty), as the mac does.
- Nothing parked.
