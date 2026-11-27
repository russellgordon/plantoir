# #899 W8b-18b: a part-way rename's line and sentence say what the disk shows (2026-11-27)

Base: `origin/issue/899-w8b-18a-rename-record-shape` ef88c963c. Merges of `origin/dev` (8046ca2e8), before proving and before hand-back: already up to date both times, so no merge commits.

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

## For the director

- `contracts/` was not changed (the order file says no for 18b). Two contract sentences are now untrue of Windows and a later contract pass should change them:
  - `shared-rules.json` → `activityTrail.mustRecord` `folder renamed` → `carries`, its last sentence ("On Windows until W8, the one part-way state it records is … ('renamed the folder … but could not write it to this course's settings'); its other part-way stop, a move of some of the copies ('Plantoir renamed m of n copies …'), writes no line."). True now: Windows records a part-way rename as the mac does, with the same three lines.
  - `file-formats.json` → `folderRenameRecord` → `note` (18a's low): "Windows' reader today … takes each with ToString()" and "Windows today writes 'from', 'to' and 'scope' only" are untrue since 18a. True now: Windows reads `from`, `to` and `scope` only as JSON strings and every other key only in its own shape, and writes all five keys (`from`, `to`, `scope`, `moved`, `mayHaveMoved`, the last two left out when empty), as the mac does.
- Nothing parked.
