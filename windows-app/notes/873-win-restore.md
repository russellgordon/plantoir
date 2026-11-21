# Lane H, 2026-11-21 night: #805 and #911 (branch `issue/873-win-restore`)

The branch name is the director's; it carries #805 and #911 only. #873 (the
whole-course staged restore) is NOT here: it waits on the mac's #909.

## For PROGRESS

### #805: a restore keeps the kept copies; a rename carries the builds folder

- `BuildOutputLocation.DiscardBuiltSitesFor(buildsRoot, code)` (the mac's
  `discardBuiltSites`): every entry of `builds\<id>\<CODE>` goes except a
  REAL `.geogebra-cache` folder; one that is a file, a junction or a link to
  itself goes with the rest, as a link (never what it points at); a course
  builds folder that is itself a link is removed as a link and never
  enumerated; the workspace `builds\<id>\work\<CODE>` still goes.
- Both `CourseRestorer.RestoreBackup` paths call it (through
  `CourseArchiver.DiscardBuiltSites`) in place of `DiscardBuilds`; nothing
  else in `RestoreBackup` moved. Archiving and `Restore(ArchivedItem)` still
  discard everything.
- `CourseRenamer.Rename` carries `builds\<id>\<OLD>` to `builds\<id>\<NEW>`
  (`BuildOutputLocation.MoveBuild`, the mac's `moveBuild`): built sites and
  kept copies together; a folder already under the new code is replaced, as
  the mac's `removeItem` then `moveItem`; an old folder that is missing moves
  nothing; the old code's build workspace is discarded (it is made again).
  Silent on failure, as the mac's (`try?`, nothing said).
- The one-section restore's discard (`DiscardBuildsFor(root, code, N)`) never
  reaches `.geogebra-cache`, which lives at course level:
  `SectionSwapTests.ARestoreThatFinishesPutsTheSectionBackAndLeavesNoStaging`
  asserts the kept copy byte for byte after a section restore.
- Ported by hand from the unreviewed `issue/873-restoring-from-a-backup`:
  `DiscardBuiltSitesFor`, `MoveBuild`, `DiscardEntry`, `KeptCopiesFolderName`,
  `CourseArchiver.DiscardBuiltSites`/`BuildsRootOf`, `KeptCopiesTests` (the
  gone-course test now also asserts the copy's bytes and the workspace gone).
- **#805's owed items: all done** (the clear in both paths with the workspace
  discarded, the folder name pinned against
  `buildOutputLocation.keptCopiesSurviveTheClear.folder`, the real-folder rule
  over a file, a junction outside and a junction to itself, and the rename
  carry with its test). #805 can close on its own.

### #911: one section from a backup made for it, staged and swapped

Built tonight, each a commit:

1. **Step 1, the assistant window's route, staged** (`CourseRestorer.RestoreSection`):
   unpacked into `courses\.internal\restoring\<GUID>\backup\` (never
   `%TEMP%`), checked, live children of `section<N>\` moved to
   `…\<GUID>\as-it-was\section<N>\`, the backup's moved in, every move undone
   last first on a failure (`wording.leftAsItWas`, which the window shows after
   its usual "Nothing was put back:", true then). A way back that did not
   finish: the aside folder moves to
   `courses\_backups\<CODE>\Section N before a restore <yyyy-MM-dd_HHmmss>`,
   `section restore stopped part way` is written (the #911 ledger entry and
   `Reason911` are gone), and the window says `wording.stoppedPartWay` (or
   `stoppedPartWayNothingToOpen`) WITHOUT "Nothing was put back:"
   (`AssistSectionRestore.StoppedPartWay`). If even that move fails, the files
   stay in `courses\.internal\restoring\<GUID>\as-it-was` and that path is
   said. `restoring` and `.internal` are removed non-recursively when empty.
   The `%TEMP%` unpack, the delete-first `ReplaceContents` and its copy
   fallback are gone. Success says nothing new.
2. **Step 2, the offer and naming rules**, pure functions in
   `OneSectionRestore` (`OfferedSection`, `Naming.DifferenceFromBackup`,
   `RenameIsUnfinished`, `ReadFacts`), run from `offerCases` (8) and
   `namingCases` (12). `ReadFacts` reads the zip's listing and its
   `course_config.json` entry from the entry stream (`CourseConfiguration.FromBytes`);
   an unreadable zip holds nothing. Nothing calls `ReadFacts` yet: the dialog
   (step 4) is where it is asked, once per backup, when the dialog is about to
   open.

**Not built tonight (the stopping rule):**
- Step 3, the menu's one-section restore (`restoreSectionFromTheMenu`): the
  swap over the outside files (the list and the swap's outside-file moves
  exist and the list is pinned to the JSON, but no caller passes it), shared
  pages made since hidden, the naming refusals asked of the unpacked backup,
  the legacy marker kept, the `Outcome` counts, the Undo seam (the swap has
  the `keepingWhatWasReplaced` parameter; nothing passes it).
- Step 4, the dialog (three buttons, the order around it, the finished and
  stopped sentences in the result dialog, the `section restored` line).
- The wording keys steps 3 and 4 need (`title`, `message`, the buttons, the
  done pieces, the refusals) are not yet in `OneSectionRestoreWording`.

**#911's five "Windows owes" bullets:**
- the third button and the offer rule: offer rule DONE (step 2); the button
  NOT DONE (step 4);
- the widened one-section restore: NOT DONE (step 3);
- the staged swap with a way back for BOTH routes: DONE for the assistant
  window's route; the dialog's route waits on step 3;
- the archive first, the `section restored` line and the `page settings left
  as they were` count: NOT DONE (step 4);
- the finished line in its notice slot: NOT DONE (step 4).
So #911 stays open.

## For documentation 12

### #805

The kept copies of geogebra.org sketches survive a restore from a backup on
Windows as on the mac (documentation 05, "The kept copies … survive the clear
(GitHub #789)"): the contract's link-shaped cases are walked against the
clear, on the builds folder each describes (Windows has no `.merged_output`
link, so the link state cannot change the answer); the cases about a built
site moved out of the working folder describe a move Windows never makes and
are counted and left out by that one rule (`KeptCopiesTests.EveryClearTheContractNamesKeepsTheCopiesItShould`).
A rename carries the whole builds folder, as the mac's `moveBuild`, for the
mac's reason: a rename should not cost a teacher their website.

### #911, the assistant window's route

- Layout: `courses\.internal\restoring\<GUID>\backup\` (the unpacked zip) and
  `…\as-it-was\` (`section<N>\`, and `outside\` for the menu route's outside
  files later). The mac uses two separate UUID folders on this route; one
  folder with two inside is the same promise and one place to name.
- **One deliberate difference from the mac's swap:** a child of `section<N>\`
  named in `CourseArchiver.ExcludedFromArchives` (`.git`, `node_modules`,
  `build`, …) is LEFT IN PLACE, never moved aside or deleted (Russell's ruling
  on #909: a restore never deletes a course's `.git`). One of those names
  deeper in the section moves aside with its folder; when the swap is good,
  an aside folder that holds such a name is KEPT in `courses\.internal\restoring\`
  rather than deleted (litter, never loss; no new folder name and no new
  sentence). See the question parked below.
- Where Explorer differs: the "nothing to open" rule is the mac's (no part of
  the path starts with a dot), though Explorer does show dot-named files; kept
  so both apps choose the same sentence for the same folder.
- Measured on the first VM (Windows 11 ARM64 in Parallels, NTFS): see "The
  double-failure sweep" and "Must-fail lines".
- A held `course_config.json` (lane G's `HeldFiles`) does not meet this route:
  the assistant route reads only the live settings through
  `CourseConfiguration.Load` (the reference check) and the zip's copy is never
  read here; step 2's `ReadFacts` reads the zip entry's stream. The menu
  route (step 3) will read the live settings and the unpacked backup's through
  `CourseConfiguration.Load`; a held live settings file there is lane G's
  helper's job.

## Must-fail lines

(Filled in below from the runs.)

## The double-failure sweep

(Filled in below from the run.)

## Where this meets the Undo door

Neither route goes through the door. `SwapSectionInPlace` takes
`Action<string>? keepingWhatWasReplaced`, handed the aside folder after the
swap and before it is removed, as the mac's `restoreSectionFromTheMenu(…keepingWhatWasReplaced:)`;
no caller passes it tonight. When W9 lands, the menu route (step 3) passes it
through and the door's journal takes its snapshot there; the shared pages' key
edits after the swap become its field edits. Nothing here calls into
`Plantoir.Core/Undo/`, and `UndoWriterScanTests` still lists `CourseRestorer.cs`
as `waitsFor: W9` with its count updated.

## Where this meets #873 and #909

- The whole-course swap (#873) can reuse tonight's pieces: `MoveEntry` (a
  rename, never a copy), the staging folder beside the courses and its
  non-recursive tidy-up, the move list with its last-first way back, and
  `KeepTheSetAsideFiles`' shape (a folder name for the whole course is #909's
  contract to fix). `RestoreBackup`, `Extract`, `ZipFolder`'s flush and
  `WorkspaceViewModel.Reload` are untouched.
- From the old `issue/873-restoring-from-a-backup`: PORTED the #805 half
  (above) and the stopped-part-way trail line, `AssistSectionRestore.StoppedPartWay`
  and the window's catch. NOT ported (wait for #909): `StagedRestore.cs` (the
  journal, the owner lease, next-launch recovery `RecoverLeftovers`, the
  incoming count check, the whole-course swap), `ZipFolder`'s `Flush(true)`,
  the `WorkspaceViewModel.Reload` hook, `StagedRestoreTests`. The mac's
  one-section restore has no next-launch recovery on `dev`, so Windows builds
  none: a killed restore leaves its staging folder, which no run deletes
  (`RestoreKillTests`).

## Question parked for Russell (also in the hand-back)

A folder backups leave out (`.git`, `node_modules`, …) DEEPER inside a
section's folder (for example `section2\project\.git`) goes aside with its
parent folder in a one-section restore. Tonight Windows keeps that aside
folder in `courses\.internal\restoring\<id>\` instead of deleting it, so
nothing is lost but nothing tells the teacher either. Options: (1, recommended)
follow #909's rule when it merges: keep it beside the course's backups under
the folder name #909's contract fixes, and say so; (2) put it back in place
inside the restored folder when that folder still exists; (3) leave tonight's
behaviour.
