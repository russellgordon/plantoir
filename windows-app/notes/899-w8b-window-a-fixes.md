# #899 W8b window A fixes (pieces 15a, 15b, 16, 21), fix round one

Branch `issue/899-w8b-window-a-fixes`, built on `origin/issue/899-w8b-21-a-linked-folder-is-renamed-as-a-link` (8b2a4d8e5). `origin/dev` merged before proving: already contained (8046ca2e8 is in the base; `git merge origin/dev` said up to date), and again before hand-back (see "Runs"). No `contracts/` change, no `mac-app/` change. The findings are `vm-tools/briefs/2026-11-27-899-w8b-window-a-review-1.md`.

## What was fixed

- **M1 (15b).** `PlanRelinkedPages` keeps each page's read and plans it with `UndoActionStep.WriteBytes(place, rewritten, plannedFrom: read)` (new; the mac's `write(_:to:plannedFrom:)`). It shares one body, `PlanFrom`, with `EditJson`, the same shape W8-11 to 14 used for the whole-file fallback (`CourseConfiguration.PlanWhole` → `EditJson(path, read, [], whole)`). A page edited or removed after the walk's read is now `changedSince` at the door, and the rename's three-attempt loop plans it again. The seam is `SpecialFolderRenamer.PlanReadAPage` (tests only, null in the app), called after each page's read and before the step is planned from it.
  - **The same double read elsewhere in the window: none found.** `editJSON` (`CourseConfiguration.PlanRecordOnDisk`) already passes its own read to `EditJson`, and its whole fallback to `PlanWhole` (the same read). `MoveFolder` takes its listing once, at plan time, as the op's `listingSha`, and the door judges the folder by it at the make. `MoveLink` reads `LinkSha` once, at plan time, the same way. `Moves()` reads no content.
- **L2 (15b): the case did not reproduce; the change is kept for one function per rule.** On the PC a junction leading nowhere at the destination was ALREADY refused with `RenameProblemDestinationExists` before the fix: .NET's `Directory.Exists` reads the link's own attributes on Windows and does not follow it (the test passed at the red ref, and must-fail row 3 stays green). `WhyTheMovesCannotBeMade` now asks `UndoLinks.Look(move.To) != Nothing`, so a link of any kind at the destination, one leading nowhere included, is a destination taken, refused with `RenameProblemDestinationExists`.
- **L3 (15b).** The walk that never goes through a link (`descendsIntoLinks: false`) no longer goes into an entry `Look` answers `CannotLook`. It is **skipped, as the mac does**: the mac's `markdownPages` walks with `FileManager.enumerator`, which descends only into what it reads as a plain folder and silently passes over what it cannot read. The decision is one function, `PagePaths.WalksInto`. A folder that moves and holds such an entry is still refused `cannotTellNow` by `MoveFolder`'s listing (`UndoTreeReading`), so no page behind one is moved unjudged.
- **L4 (15a).** `InTheStepsOrder` sorts only the pages (`.md`) planned whole into the one page order; every other file, a settings file planned whole included, keeps the order it was planned in, after the pages, as the mac keeps it.
- **L5 (15b).** The class comment no longer says a moved folder cannot be un-moved or that the rename ships without an undo, and neither it nor `WhyTheMovesCannotBeMade` gives `Directory.Move` as the reason: both describe the one step and the swap's `MoveFileEx`, all or none.
- **L6 (15a, 15b).** 15a's row 4 sabotage (`FileAttributes.ReparsePoint` in place of `Look` in `MoveFolder`) is re-run against `APlaceThatIsAOneDriveStylePlaceholderIsMovedAsTheFolderItIs`, which goes red because the placeholder is refused, not because a gone folder throws. A door-level rename of case only is tested (`ACapitalisationOnlyRenameThroughTheDoorIsOneStepAndUndoPutsTheOldCaseBack`).
  - **What the placeholder tests prove, and what they do not.** `AOneDriveStylePlaceholderFolderIsWalkedAsTheFolderItIs` and `APlaceThatIsAOneDriveStylePlaceholderIsMovedAsTheFolderItIs` prove that a fully populated, in-sync Cloud Files placeholder folder (`IO_REPARSE_TAG_CLOUD`, under the test's own sync root, with placeholders exposed so the reparse attribute shows) is a `Folder` to `Look`: it is walked, its page is relinked, and as a place it is moved by its listing, never as a link. They do not prove anything about online-only (dehydrated) files, which `UndoTreeReading` hashes at plan time and at the check (on real OneDrive that downloads them, and offline it refuses `cannotTellNow`), nor about the real OneDrive filter driver, nor about the app's default placeholder mode.
- **L1** is not mine (see "For the director").

## Tests that failed first

At the tests' own commit 442e68b54, on the PC (run `w8b-afix-a`, 4 failed of 31):
- `ASettingsFilePlannedWholeKeepsItsPlannedPlaceAfterThePages`: collections differ (the settings sorted before the pages).
- `AnEntryThatCannotBeLookedAtIsNotWalkedByTheWalkThatNeverGoesThroughALink`: `Assert.False` on `WalksInto(CannotLook, false)`.
- `APageEditedBetweenTheWalksReadAndThePlanIsPlannedAgainAndTheEditIsKept`: values differ (no re-plan: reads of the index 1, expected 2; the edit was lost).
- `APageRemovedBetweenTheWalksReadAndThePlanIsPlannedAgainAndNotBroughtBack`: "a page removed during the walk is not brought back" (it was).
- Not red, as expected for coverage: `ACapitalisationOnlyRenameThroughTheDoorIsOneStepAndUndoPutsTheOldCaseBack` (the product was already right). Not red, unexpectedly: `ADestinationThatIsALinkLeadingNowhereIsTakenAndTheRenameIsRefusedWithItsSentence` (see L2).

## Must-fail lines

`vm-tools/guest/899-w8b-afix-mustfail.json`, run by `899-w8b-afix-pc-run.ps1` (a copy of 21's). **5 RED of 6; row 3 NOT-RED, explained (L2 did not reproduce).**
1. (M1a) `WriteBytes(place, rewritten)` without `plannedFrom`: RED, `APageEditedBetween…` "Values differ, Expected: 2".
2. (M1b) the same sabotage: RED, `APageRemovedBetween…` "a page removed during the walk is not brought back".
3. (L2) `Directory.Exists || File.Exists` back: NOT-RED, 1 passed (see L2).
4. (L3) `CannotLook` walked: RED, `AnEntryThatCannotBeLookedAt…` `Assert.False() Failure`.
5. (L4) every whole file sorted: RED, `ASettingsFilePlannedWhole…` "Collections differ (pos 1)".
6. (15a row 4, re-pointed) `FileAttributes.ReparsePoint` in `MoveFolder`: RED, `APlaceThatIsAOneDriveStylePlaceholderIsMovedAsTheFolderItIs`, "“Tasks” could not be read just now." (the placeholder refused, the right reason).

## Runs

- `w8b-afix-a` (PC, `899-w8b-afix-pc-run.ps1` via `899-w8b-afix-launch-a.ps1`, modes `classes,mustfail`, red ref 442e68b54, 2026-11-27 02:06 queued behind `int-d27-6`'s lock, lock taken 02:20, done 02:25; the run took and released its own lock):
  - Red ref: as in "Tests that failed first".
  - At 5ec404151: both builds 0 errors. **544 passed of 544, 0 skipped**: `UndoRenameFolderStepTests`, `UndoActionStepFolderMoveTests`, `SpecialFolderRenamerTests`, `FolderRenameApplyTests`, `UndoLinkMoveTests`, `UndoActionStepTests`, `UndoActionStepsOnWindowsTests`, `UndoActionTraceContractTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`, `NamedGapLedgerTests` (the placeholder, junction and symbolic-link tests ran).
  - Must-fail as above; restored 544 of 544; HEAD-AFTER the same, status clean.

## For documentation 12

- Rename folder: each relinked page's before is the bytes the walk read and rewrote, never a second read (`WriteBytes(…, plannedFrom:)`), so an edit or a removal during the walk is `changedSince` and is planned again.
- The destination check reads with `UndoLinks.Look`: a link of any kind there is taken.
- The page walk that never goes through a link also skips an entry it cannot look at, as the mac's walk does.
- In a step that moves a folder, only the pages planned whole are put in the one page order; every other file keeps its planned order, after them.

## For the director

- **`renameFolderNothingWasChanged` has no owning piece** (review 1, L1): a rename refused with nothing changed shows the bare door reason on Windows; the mac wraps it in `undo.wording.renameFolderNothingWasChanged`. 18b's brief should gain this key beside its three part-way keys. Not built here.
- The folder-holding-a-link wording ("could not be read just now" for a permanent refusal) is a both-platforms wording question, from review 1 L1; not built here.
