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

3. **Step 3, the menu's one-section restore** (`CourseRestorer.RestoreSectionFromTheMenu`,
   the mac's `restoreSectionFromTheMenu`): the same staging and swap, now
   over the section folder AND the nine `filesOutsideTheSection` (each
   `fromTheBackup`, `discarded` or `leftAsItIs`; a `fromTheBackup` file the
   backup lacks is removed, kept aside until the swap is good); the
   per-section keys on shared pages as before; a shared page the backup
   lacks hidden from this section unless the build already reads it hidden
   (`HidingAPageMadeSinceTheBackup`, the ordinary `PageFrontmatter.SetDraft`
   with `publishForSection<N>: false`; pages under `private\`, `templates\`,
   `.obsidian\` or any dot folder never touched, `OneSectionRestore.IsPublishable`,
   pinned to `geogebraFences.files.notPublished.folders`); the section-number,
   reference and naming refusals asked again of the live settings and the
   UNPACKED backup (`namingChanged`, `foldersChanged`, `sectionNotInCourse`,
   the mac's `sectionMissingFromBackup` and `archiveUnreadable` sentences);
   the legacy `.netlify_site.json` in the section's build root kept across the
   discarded build; the `Outcome` (`PagesNotPutBack`, `PagesNotSaved`,
   `PagesMadeSinceHidden`, `WebsiteRecordDiffers`, the markers compared as
   parsed JSON); and the Undo seam `keepingWhatWasReplaced`, handed the aside
   folder before it goes (no caller passes it; a test does).
4. **Step 4, the dialog and the order around it.** `ConfirmRestoreBackup`
   reads the zip once per backup (`_backupFacts`, off the interface thread)
   when the dialog is about to open, asks `OneSectionRestore.OfferFor`, and
   for an offered section shows ONE `ContentDialog`: title `wording.title`,
   content `wording.message` (`BackupMaker.DescriptionFor` and
   `WhenDescription`), Restore Section N (primary, `DefaultButton`), Restore
   Whole Course (secondary: today's whole-course restore, unchanged, moved
   into `RestoreWholeCourse`), Cancel (close, Escape). Otherwise today's
   two-button dialog. The click is `MenuSectionRestore.Run`, the mac's
   `restoreOneSection` in its order: the busy refusal (preview or deploy, in
   the mac's words; an assistant's hold; the Section menu or the assistant
   changing THIS section, `wording.busy`) and every offer condition asked
   again (`RefusalAtTheClick`) BEFORE the archive; the whole course archived
   (`ArchiveCourseWithoutRemoving`); the busy refusal asked again; the
   restore; `section restored` (`RestoredOneSectionFromTheMenuLine`, the
   mac's words) and, when pages could not take a key, `page settings left as
   they were`; then `doneTitle` and `done` with its pieces in the one result
   dialog (`ShowError`'s OK dialog, the backup alert's slot). A failure is
   said under `BackupProblemTitle.Restoring` with the restorer's own sentence.
   The busy refusals before the dialog keep their existing Windows titles.

**HIG (Alerts, read 2026-11-21):** the page puts the default button on the
trailing side and Cancel on the leading side, and says never to make Cancel
the default; it gives no three-button macOS rule. Windows' ContentDialog
lays out primary, secondary, close left to right, and every other
three-button question in this app uses that order, so the brief's "the
Windows order the app already uses" decides: Restore Section N (default,
leftmost), Restore Whole Course, Cancel (rightmost, Escape). No control the
Mac lacks; nothing invisible.

**#911's five "Windows owes" bullets: all DONE** (the third button and the
offer rule; the widened one-section restore; the staged swap with a way back
for BOTH routes; the archive first, the `section restored` line and the
`page settings left as they were` count; the finished line in its notice
slot). #911 can close on its own once reviewed.

**The review of steps 1 and 2 (`vm-tools/briefs/2026-11-21-lane-h-review-1.md`), lows fixed here:**
- LOW 3: only WORK a backup leaves out keeps a replaced section aside:
  `CourseRestorer.LeftOutWork` = `.git`, `node_modules`, `dist`, `build`,
  `out` (a project's history, its packages, what its own tools made). The
  rest of `ExcludedFromArchives` is litter made again on its own and never
  keeps anything: `.DS_Store`, `__pycache__`, `.cache`, `.quartz-cache`,
  `.merged_output`. Tests: `ADeeperFolderOfWorkABackupLeavesOutKeepsTheAsideCopy`,
  `SystemLitterDeeperInTheSectionNeverKeepsTheAsideCopy`,
  `TheLeftOutListSplitsIntoWorkAndLitter` (a name added to the list must be
  decided).
- LOW 1: `RestoreKillTests(staged)` (and the unpack kills) assert `section2\`
  byte for byte and no `as-it-was` folder.
- LOW 2: kills part way through the unpack (`unpack:2`, through a new
  `SectionSwapHooks.UnpackedAnEntry`; the staging unpack now extracts entry by
  entry with ExtractToDirectory's outside-the-folder guard), during the moves
  in (assistant `move:5`, `move:6`; menu `move:7`, `move:10`), and during a way
  back started by a REAL refusal (the harness holds `zz notes\n.md` without
  delete sharing; `back:1`, `back:2`), on both routes: 18 kill cases.
- LOW 4: every sweep case asserts what the teacher is told
  (`SectionSwapFixture.AssertToldTruly`): `leftAsItWas` when the way back
  finished, else `stoppedPartWay` naming the kept folder or
  `stoppedPartWayNothingToOpen`, with the archive sentence on the menu's
  route, and the trail line naming that folder.
- LOW 5: the stacked summary tags in `ActivityTrail.cs`.
- LOW 6 (a section on another volume) and LOW 7 (a kill leaves the unpacked
  backup) are the brief's design, unchanged; said here only.

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
- A held `course_config.json` (lane G's `HeldFiles`): the menu route (step 3)
  reads the live settings and the unpacked backup's through
  `CourseConfiguration.Load` (in `CourseRestorer.cs`), and `OfferFor` reads the
  saved live settings the same way; a held live file there is refused as
  "could not be read" today and is lane G's helper's job later. The assistant
  route:
  the assistant route reads only the live settings through
  `CourseConfiguration.Load` (the reference check) and the zip's copy is never
  read here; step 2's `ReadFacts` reads the zip entry's stream. 

### #911, the menu's route and the dialog

- `CourseRestorer.RestoreSectionFromTheMenu` is the assistant route's swap
  with the nine outside files added (`…\as-it-was\outside\<path>`), so one
  staging folder holds both halves; the way back and the keep are the same
  code. The legacy Netlify marker is kept from `BuildOutputLocation.ForSection`
  (`builds\<id>\<CODE>\section<N>\.netlify_site.json`), where Windows'
  launchers put it; the mac's `.merged_output\section<N>` has never held one
  on this platform.
- A page made since is hidden with the per-section key only
  (`publishForSection<N>: false`) and only when `PageFrontmatter.IsDraft`
  reads it published for the section, so a page whose plain `publish:` is
  false is left byte for byte.
- `MenuSectionRestore.Run` holds the click's order outside the view, so a
  unit test can prove a refused click leaves `Archived` as it was; the view
  passes the busy question as a delegate, asked before and after the archive.
- Facts are cached per zip path in the sidebar for the window's life (the
  mac's `backupFactsByPath`): a zip does not change.
- Restore…'s question decides by the explicit answer only (review 2's
  MEDIUM). `AskWhichRestore` returns a `RestoreChoice`: Primary is
  `OneSection`, Secondary is `WholeCourse`, and every other answer (Cancel,
  Escape, a closed dialog, and the `null` of a question that could not be
  shown) is `Nothing`, which restores nothing and says nothing, as a
  cancelled question says nothing. `ConfirmRestoreBackup` runs a restore
  only from a `switch` that names both choices; there is no `else` and no
  `default`.
- From the press to the answer, `SidebarPane.IsAskingWhichRestore` is true
  (a `finally` clears it) and every Restore… is greyed: the menu bar reads it
  as a dialog up (`SheetIsUp`), the backup row's context menu reads it as it
  opens, and the backup pane's Restore… button is drawn again greyed through
  `RestoreAvailabilityChanged` (named `AskingWhichRestoreChanged` until the
  sweep of 2026-11-25; all three now read `RestoreWaits`, below). That covers the gap while the zip is read on
  a worker thread before the question opens. The early return on the flag
  only backs the greying up. The Backups group dialog's Restore… needs
  nothing: that dialog is itself up until it hands over.
- Another dialog taking the one slot in that gap (a problems alert, an
  update offer) cannot be prevented by greying; the question then answers
  `null`, which is `Nothing`.
- Not changed (review 2, lows): "The course settings of X could not be
  read: …" in `CourseRestorer.RestoreSectionFromTheMenu` has no contract key
  and the mac has no such sentence (it lets the decode error through), so it
  stays as Windows' own. The refusals asked before the dialog ("X is busy
  right now", `AssistWording.CourseIsAlreadyBeingRevised`) keep their older
  Windows titles, not the mac's `BackupProblemTitle.restoring`; the click's
  second asking in `MenuSectionRestore.Run` already uses the mac's.
- Searched the Windows app for the same shape (a dialog helper's `null`
  reaching an acting `else`) around restore, archive, delete, replace and
  deploy: none other. Every other confirmation tests `!= Primary` and
  returns; `TaskProgressView`'s Stop question's `else` only cancels;
  `SectionDetailView`'s problems alert maps an unshown dialog to "not
  answered" and names Primary and Secondary explicitly; `UpdatePrompts` maps
  `null` to `NotShown`.
- The two `HarnessSourceRuleTests` facts that fail in the UI project
  (`NoTestSendsAKeyDownWithNoKeyUp`, `EveryKeyATestNamesIsWatched`) fail on
  `StopByKeyboardUiTests.cs`, another lane's file on `dev`, not on anything
  here; `RestoreSectionDialogUiTests` sends only `Keyboard.Type` of ESCAPE and
  RETURN, both watched.

### Sweep of 2026-11-25 (MEDIUM and LOW) and review 3's LOW

- **The course is busy while Restore Section N zips it.** `RestoreOneSection`
  adds the course to `_zipping` before `MenuSectionRestore.Run` (which makes
  the whole-course archive first) and removes it in a `finally`, calling
  `ApplyMenuEnablement` both times, exactly as `BackUpCourse` does: Back Up
  Now, Remove Course and Restore from Backup grey in the menu bar
  (`subjectMenus.situationKeys.copying`) and the assistant is refused
  (`CourseIsBeingCopied`). It returns at the top when a copy is already being
  made, as the mac's `restoreOneSection` returns on `isBeingCopied`.
- **Every Restore… reads one rule, `SidebarPane.RestoreWaits(code)`**: a
  question being asked, or the course being copied (this app's zip or
  another program's `Copying` lease). The menu bar's rule already greyed
  Restore from Backup under copying; the backup row's context menu and the
  backup pane's button now follow it too, and `ConfirmRestoreBackup`'s early
  return backs it up.
- **The result sentence is never dropped.** `ShowError(…, waitForTheSlot:
  true)` goes through `ShowWhenTheSlotIsFree`: while a ContentDialog's popup
  is open in the window, it waits on that popup's own `Closed` event, then
  reads the slot again; no clock. The finished, refused and stopped-part-way
  sentences all go this way (the last is the only place the teacher is told
  where the set-aside files are). Other callers of `ShowError` are unchanged.
- **Keyboard focus comes back to Restore….** The backup pane is drawn again
  whenever `RestoreWaits` changes, which took the focus away with the old
  button. `MainWindow.ShowBackupPane` keeps the `FocusState` the old button
  held, for that backup, while the button is greyed, and gives it to the new
  button on its `Loaded` event once it is enabled; choosing any other row
  forgets it. Microsoft's focus-navigation pages (read 2026-11-25:
  focus-navigation, focus-navigation-programmatic, dialogs) say nothing about
  returning focus after a dialog or a replaced control, so the focus is put
  back where the teacher left it, on the control that replaced it; the
  `FocusState` is the old button's own, so a mouse press does not gain a
  keyboard focus ring. Proved by
  `RestoreSectionDialogUiTests.KeyboardFocusComesBackToRestoreWhenTheQuestionIsCancelled`.

**For documentation 12, the sentence to amend** (`documentation/12-windows-app.md`,
the "Held, 4 entries" paragraph near line 2748, untrue once this merges, because
the branch removes #911's `NamedGapLedger` entry and writes the event): replace

> **Held, 4 entries, all v2.0.0, all `ActivityTrailEvents`.** #911 (1):
> `section restore stopped part way`. Windows' section restore is not staged
> yet, so it has no "stopped part way" outcome to record. #912 (3):

with

> **Held, 3 entries, all v2.0.0, all `ActivityTrailEvents`.** (#911's
> `section restore stopped part way` was held here until Windows' section
> restore was staged; since #911 merged, Windows writes it and the entry is
> gone.) #912 (3):

## Tests added tonight for steps 3 and 4 (first VM: 186 of 186 over the brief's run rule, both builds and the UI test green at b9540f26b, `dev` 8117678f8 merged, 02:33)

- `MenuSectionRestoreTests` (14): every `filesOutsideTheSection` case from
  the JSON against a fixture holding every listed path for Sections 1 and 2;
  a `fromTheBackup` file the backup lacks; the Undo seam handed the aside
  folder; the website record compared as parsed JSON; a page made since
  hidden, one already hidden and a template left byte for byte; no room
  counted; this section's key put back; naming, folders and section refusals
  of the unpacked backup with nothing moved; a held file (real) leaving the
  section and its outside files byte for byte; a way back that did not finish
  saying the archive sentence; `.git` and `node_modules` left in place; the
  built page gone with the legacy marker and the kept copies staying; the sweep.
- `MenuSectionRestoreClickTests` (8): the offer for a menu backup and none for
  a teacher's; a finished click (archive first, the restored section, the
  done title and sentence, the trail line); `page settings left as they were`;
  three refused clicks (busy, the offer rule asked again, not made for this
  section), each with `Archived` the same before and after; busy after the
  archive (archive stays, nothing restored); the offered dialog's source.
- `OneSectionRestoreContractTests` (+3): every dialog, refusal and done
  template from the JSON; `doneJoin` over 54 combinations; the never-published
  folders against `shared-rules.json`.
- `RestoreKillTests`: 18 kill points over both routes (above).
- `RestoreSectionDialogUiTests` (UI Automation, first VM, passed 02:26): the
  three buttons by name, title, left-to-right order; Escape closes it with
  nothing archived and the lesson unchanged; Enter restores Section 1 (the
  finished dialog by its title, the lesson back, one archive).

## Must-fail lines

Each sabotage was a scratch commit on top of the branch (refs `mf911-g1` to
`g7`, never pushed to `origin`), built and run on the first VM with
`vm-tools/guest/911-mustfail.ps1` over `KeptCopiesTests`, `SectionSwapTests`,
`RestoreKillTests` and `OneSectionRestoreContractTests` (26 tests). Several
sabotages share a build only where they hit different tests. Green at the
branch head: 207 of 207 over every class named in the brief's run rule.

| Group | Behaviour reverted | Failed (test, line) |
|---|---|---|
| g1 | `RestoreBackup` back to `DiscardBuilds` (both paths) | `KeptCopiesTests.RestoringOverTheCourse…` :93, `RestoringACourseThatIsGone…` :109 |
| g1 | the kept-copies folder kept even as a link | `KeptCopiesTests.EveryClearTheContractNamesKeepsTheCopiesItShould` (WalkOne :237) |
| g1 | `CourseRenamer` without `MoveBuild` | `RenamingCarriesTheBuildsFolderToTheNewCode` :141, `ABuildsFolderThatIsALinkIsRemovedAsALinkOnRename…` :158 |
| g1 | a shared folder removed since ignored | `OneSectionRestoreContractTests.EveryNamingCaseFindsTheContractsDifference` :95 |
| g1 | `LeftAsItWas` reworded (a comma dropped) | `TheStoppedAndLeftSentencesAreTheContractsTemplates` :27 |
| g2 | no way back (moves never undone) | `SectionSwapTests.AFolderHoldingAnOpenFile…` :68, `WhenEvenTheKeep…` :215, `AWayBack…` :166, the sweep (SweepOne :337) |
| g2 | a deeper left-out name not kept | `ADeeperGitFolderThatWentAside…` :259 |
| g2 | every kept folder said to hold something to open | `WithOnlyHiddenFilesLeftAside…` :194 |
| g2 | `renameUnfinished` ignored by the offer | `EveryOfferCaseGivesTheContractsSection` :73 |
| g2 | links checklist offer `leftAsItIs` instead of `discarded` | `TheFilesOutsideTheSectionAreTheContractsList` :45 |
| g3 | the keep never moves the files to `_backups` | `AWayBack…` :171, `WithOnlyHiddenFilesLeftAside…` :199 |
| g3 | left-out names in the section moved aside like the rest | `AGitFolderAndNodeModulesInTheSectionStayWhereTheyAre` :243 |
| g3 | `restoring` and `.internal` never tidied | `ABackupWithoutTheSectionIsRefusedBeforeAnythingMoves` :86, `ARestoreThatFinishes…` :109, `AFolderHoldingAnOpenFile…` :69 |
| g4 | staging under `%TEMP%` | `RestoreKillTests(setAside)`, `(move:1)`, `(move:3)` :72; `WhenEvenTheKeep…` :220; `ADeeperGit…` :259 |
| g4 | a builds folder that is a link enumerated (clear and rename) | `ABuildsFolderThatIsItselfALinkIsNeverEnumerated` :176, `…RemovedAsALinkOnRename…` :159 |
| g5 | delete first (the old `ReplaceContents` shape) | `RestoreKillTests(setAside)`, `(move:1)`, `(move:3)` :72, the sweep, `AFolderHoldingAnOpenFile…` :68, `AWayBack…` :166 and three more |
| g5 | `ReadFacts` never reads the naming | `TheFactsAreReadFromTheZipsListing…` :109 |
| g6 | the keep deletes the aside folder | the sweep (SweepOne :337), `AWayBack…` :166, `WithOnlyHiddenFilesLeftAside…` :199 |
| g7 | `KeptCopiesFolderName` spelled otherwise | `KeptCopiesTests.TheFolderNameIsTheContracts` :56 |
| g7 | `Restore(ArchivedItem)` keeps the kept copies | `RestoringFromArchivedStillDiscardsEverything` :128 |
| g7 | `AssistSectionRestore` without its `StoppedPartWay` catch | `SectionSwapTests.AWayBackThatDoesNotFinish…` :166 (the window would have said "Nothing was put back:") |
| h1 | the menu route swaps no outside files | `MenuSectionRestoreTests.EveryFileOutsideTheSection…` :104, `AFileTheBackupLacks…` :138, `RestoreKillTests(move:10, menu)` :99 |
| h1 | a page made since never hidden (nor counted) | `ASharedPageMadeSince…` :174, `APageMadeSinceWithNoRoom…` :192, `MenuSectionRestoreClickTests.APageThatCouldNotTakeAKey…` :82 |
| h1 | the click never asks "made for this section" | `AClickOnABackupNotMadeForTheSectionArchivesNothing` :132 |
| h1 | `.DS_Store` counted as work | `SectionSwapTests.SystemLitterDeeperInTheSection…` :288, `TheLeftOutListSplitsIntoWorkAndLitter` :299 |
| h1 | `websiteUnchanged` never joined | `OneSectionRestoreContractTests.TheFinishedSentenceJoins…` :69 |
| h2 | the unpacked backup's naming never asked | `ANamingChangedSinceTheBackup…` :220, `AFolderRemovedSinceTheBackupIsRefused` :234 |
| h2 | the legacy marker not kept | `TheBuiltSiteGoesAndTheLegacyWebsiteMarker…` :353 |
| h2 | busy not asked again after the archive | `MenuSectionRestoreClickTests.BusyAfterTheArchive…` :147 |
| h2 | the offered dialog's default is Restore Whole Course | `TheOfferedDialogDefaultsToRestoreSectionN` :177; the UI test (below) |
| h2 | the menu's stopped sentence without the archive sentence | `AWayBackThatDoesNotFinishOnTheMenusRoute…` :308, the menu sweep (`AssertToldTruly` :169) |
| h3 | busy asked only after the archive | `AClickRefusedAsBusyArchivesNothing` :100 |
| h3 | `Staged` reached after the swap (menu route) | `RestoreKillTests(staged, menu)` :107 (the section changed before the kill) |
| h3 | the unpack never announces an entry | `RestoreKillTests(unpack:2, …)` :99, both routes |
| h3 | the menu route puts back no per-section key | `ThisSectionsKeyOnASharedPage…` :206, `ASharedPageMadeSince…` :174, `BusyAfterTheArchive…` :147 and two more |
| h4 | a way back that did not finish read as finished | both sweeps (`AssertToldTruly` :156), `AWayBackThatDoesNotFinish…` :166 and :302, `WithOnlyHiddenFiles…` :194, `WhenEvenTheKeep…` :215 |
| h4 | the website record compared over the wrong files | passed every test: the gap is closed by `ADifferentWebsiteRecordIsSaidAndTheLiveOneIsKept`, proved by h5 below |
| h5 | the same, on 4162141d4 | `MenuSectionRestoreTests.ADifferentWebsiteRecordIsSaidAndTheLiveOneIsKept` :167 |
| h2 (UI) | the default Restore Whole Course | `RestoreSectionDialogUiTests` failed after its 60 s wait for the finished dialog (1 m 15 s; Enter ran the whole-course restore), first VM 02:30 |

h1 to h4 were built on db6ab3354 and run on the first VM at 02:28 over
`MenuSectionRestoreClickTests`, `MenuSectionRestoreTests`,
`OneSectionRestoreContractTests`, `RestoreKillTests` and `SectionSwapTests`
(60 tests); `vm-tools/guest/911-mustfail.ps1` now prints the failing line of
any test file.

`RestoreKillTests(staged)` passes under every sabotage, by its nature: at
`staged` nothing in the course has moved, so it holds only that staging moves
nothing (it would fail on a restore that touched the course before checking
the backup; none of the sabotages did that). It is kept as that check.
`KeptCopiesTests.RestoringFromArchivedStillDiscardsEverything` passed either
way at first (archiving had already discarded the build); it now plants a
build after the archive and is proved by g7.

### Review 2's MEDIUM (first VM, 02:47 to 02:55)

Head b85971c6e (`dev` 2f50d1fa3 merged): all three builds; 230 of 230 unit
over `MenuSectionRestore`, `OneSectionRestore`, `SubjectMenuRules` and every
class that reads `SidebarPane.xaml.cs`, `MainWindow.xaml.cs` or
`MainWindow.Menus.cs` as source; UI `RestoreSectionDialogUiTests` and
`MenuGreysUnderADialog` 2 of 2. Scratch 231742282 (never pushed) put back
three faults at once, each held by its own test: 3 of 10 failed.

| Sabotage | Test | Failing line |
|---|---|---|
| `else if (answer != ContentDialogResult.None) chosen = RestoreChoice.WholeCourse;` (a `null` restores the whole course) | `TheOfferedDialogDefaultsToRestoreSectionN` | :182, `Assert.Contains("if (answer == ContentDialogResult.Secondary) …")` |
| the `switch`'s `WholeCourse` and `Nothing` cases replaced by `default: await RestoreWholeCourse(item);` | `OnlyAnExplicitChoiceRestores` | :201, `Assert.Matches("case RestoreChoice\\.WholeCourse: …")` |
| `SheetIsUp` without `\|\| Sidebar.IsAskingWhichRestore` (the menu bar not greyed while asking) | `EveryRestoreIsGreyedWhileTheQuestionIsAsked` | :225, `Assert.Contains("SheetIsUp = DialogGate.IsOpen(…) \|\| Sidebar.IsAskingWhichRestore,")` |

The three are source tests, as the dialog's test before them: a question
that cannot be shown (a second dialog in the one slot) is not reproducible
in a UI test without a timed race, so the source pins the structure that
makes the fall-through impossible.

## The double-failure sweep

`SectionSwapTests.EveryDoubleFailureKeepsEveryOriginalAndTheMixesAreCounted`,
the mac's shape (the move seam throws at forward move k and at way-back move
j, every k from 2 and every j below k), on Windows' own fixture of the
ASSISTANT route (no outside files): four live entries (one hidden, one a
folder holding a deeper folder, one made since) and three backup entries, so
seven forward moves and 21 cases. **Every original was kept in all 21**, in
the section or the kept folder (asserted). **3 of 21 left `section2\` a mix**
of original and backup files (first VM, five runs between 01:58 and 02:03,
the same every time).

The MENU route, the mac's shape (`MenuSectionRestoreTests.EveryDoubleFailureOnTheMenusRouteKeepsEveryOriginalAndTheMixesAreCounted`):
the same four live entries and three backup entries plus six outside files
(timetable, the published-pages folder, three `fromTheBackup` records and the
`discarded` checklist), 18 forward moves, 153 cases. **Every original, in the
section and outside it, was kept in all 153**, and every case was told the
true sentence (asserted). **18 of 153 left `section2\` a mix** (first VM,
NTFS, three runs 02:16 to 02:26, the same each time), against the mac's 12 of
91 on its own fixture (four section files, six outside, 14 forward moves):
the same order of rate, about one case in eight to nine, because a mix needs
a backup entry already in and the failing way-back move to be that entry's.

## Where this meets the Undo door

Neither route goes through the door. `RestoreSectionFromTheMenu(…, keepingWhatWasReplaced:)`
is the menu route's seam, passed on to `SwapSectionInPlace`, which takes
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
