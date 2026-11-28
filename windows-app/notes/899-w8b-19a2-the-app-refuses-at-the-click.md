# W8b-19a2: while a folder is renamed, the app refuses its course's other work at the click (#899, Windows #949)

Stands on 19a1 (`CourseActivity.BeginFolderRename`, `CourseIsRenamingAFolder`, `FolderRenameIsUnderWay`).

## Built

- **The one refusal function:** `CourseActivity.FolderRenameRefusal(folderPath, courseCode)`. It returns `undo.wording.renameFolderUnderWay` with the course filled in, or null. Every act asks this, never `CourseIsRenamingAFolder` itself. `git grep CourseIsRenamingAFolder` shows only this function and 19a1's own calls.
- **The whole-course restore's refusal table:** `CourseRestorer.FirstWholeCourseRefusal(WholeCourseRefusalFacts)` follows `refusalWhy`'s order (`folderRenameUnderWay`, then `busy`, then `claudeIsRevisingTheCourseRestore`), with `WholeCourseRefusalFactsNow` and `ContractNameOf`. Restore from Backup… now refuses at its click through this table, in that order. Before, it checked a preview or deploy first and then the assistant.
- **`CourseRestorer.RestoreWholeCourse` takes its claim, then asks the one function.** While a rename is under way it throws a `RestoreException` with the sentence and writes nothing. The run is the one Restore from Backup… and Get Ready's Restore Course both use.
- **Get Ready's Restore Course:** `StartOfYearRestoreOffer` now takes the working folder. `RestoreCourseIsPressed` answers `HeldBackByARename`, checked before the deploy check, and `HeldBackSentence` says the rename's sentence. The offer stays open, and the dialog handles it as it handles the deploy hold-back.
- **19a1's review, LOW 1:** `CourseActivity.RenameSwapBegins` now checks for a restore and marks the swap inside one `lock (_gate)`.

## The acts refused at the click (10 entry points, 9 acts of the brief)

1. Course Settings Save: `CourseSettingsView.Save_Click`. The Enter and Ctrl+S path, `SaveFromTheMenu`, runs through it. The refusal shows on Save's own status line, in the failure colour, and nothing is written.
2. Rename Course: `SidebarPane.OpenRenameCourseDialog` ("Course is busy").
3. Add Section: `OpenAddSectionDialog` ("{code} is busy right now").
4. and 5. Removal of the course or a section: `ConfirmRemove` (`BackupProblemTitle.Removing`). Windows has no separate Archive item: Remove is the archive.
6. Restore from Backup…: `AskWhichRestore`, before its question, through the table (`CourseRestorer.BusyTitle`). The one-section run's `BusyRefusal` in `RestoreOneSection` asks first too. Restore from Archived: `ConfirmRestore` (`BackupProblemTitle.Restoring`).
7. Get Ready's Restore Course: `StartOfYearRestoreOffer.RestoreCourseIsPressed`.
8. Preview: `SectionDetailView.PressPreviewAsync` ("Cannot Preview Yet"). Deploy: `DeployAsync` ("Cannot Deploy Yet", and the assistant's hand-back hears the same sentence). Deploy Later: `AskWhenToDeploy` ("That couldn't be scheduled").
9. The section window's structural items: Rename Course and Add Section from the menus reach the same two functions. `BusyReason` itself only greys items (19b's).

Each refusal is shown where that act already shows its busy refusal, under that refusal's own title. No new surface, no new button, no question.

- Microsoft Learn, "Dialog controls": "Use dialogs to notify users of important information or to request confirmation or additional info before an action can be completed." Here the dialog tells the teacher why the act cannot happen, with a single OK.
- Apple HIG, "Alerts": "Use alerts to deliver essential information that people need to act on." These are the existing alerts and the existing status line, with no added choice.

## Tests

`Plantoir.Tests/FolderRenameRefusalTests.cs` (new): the one function while a claim holds and after each ending; the `refusalCases` row read by name and replayed; the facts while a claim holds; the restore run refused and writing nothing; the Restore Course press; and two source-reading tests. The first checks that each of the 10 entry points calls the function before the first thing it asks or writes. The second checks that every view method calling `IsPreviewingOrPublishing` or `AssistHoldRefusal` is in that list, so a new act that is left out goes red.

The tests went in first, as their own commit, with Core stubs (null or no-op), so the class compiles and fails at runtime. Red: `FolderRenameRefusalTests`, every test except `EveryViewMethodThatRefusesForABusyCourseIsAnEntryPointAbove`, which only fails once an entry is missing. The red lines are the `Assert.Equal(Sentence(...))` and the `asked >= 0` checks.

**Owed:** `Plantoir.UiTests/RenameFolderBusyUiTests.cs` and its Debug-only launch argument were not written within the budget.

## For 19a3

- `Plantoir.Mcp` decides a hold from the leases on disk (`WorkLease`, `CourseActivity.IsAssisting` and `IsBuildingElsewhere`). It cannot see the rename claim, which lives in this process's memory, so it needs a route: a lease kind or a file.
- The assistant window runs in this process. It deploys through `SectionDetailView.DeployAsync`, which now refuses, and rebuilds the preview through `RebuildPreviewAsync`, which does not refuse yet.

## For documentation 12

- The Mac's `ReferenceReplacer` refusal (Replace reference course) is Mac only. Nothing was built for it here.
- Windows has no Archive item apart from Remove.

## Self-check

- One function for the rule: `CourseActivity.FolderRenameRefusal`. The grep is clean.
- No ledger row, no `contracts/` change, `undoJournalIsLive` untouched. Every sentence is read by key through `SpecialNames.RenameFolderUnderWay`.
- No new control, no confirmation, no timed wait.
- I left no run going and took or removed no lock.
