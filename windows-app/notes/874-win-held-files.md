# #953 and #874: a file another program holds for a moment (Windows, lane G, 2026-11-21)

Branch `issue/874-win-held-files`. Windows only; nothing under `mac-app/`, `contracts/` or `scripts/` changed.

## For PROGRESS

### #953 (a write by rename refused silently)

- New `Plantoir.Core/Models/HeldFiles.cs`: ONE bounded retry (`Pauses` 50, 100, 200, 400 ms, about 0.75 s, the shape `ObsidianFigureAddOns.Retrying` already uses, #1016 row 45), a delete-access probe (`IsHeld`), a three-way read (`ReadBytes`: Read, NotThere, CouldNotReadNow), `TemporaryBeside` (hidden, unique, `.tmp`) and `FileInUseException` (message `HeldFiles.InUseSentence`, HResult the sharing violation). The pause is a parameter; `PausingWith` sets a test's pause for its own async flow only.
- `AgentGuidance.WriteAtomically` renames through `HeldFiles.Replace`; still held after the bound it throws `FileInUseException`, the file unchanged and its temporary removed. `SystemReason` then gives the system's sentence for a sharing violation ("The process cannot access the file because it is being used by another process."), not "Access is denied.".
- `LastViewedPages.Load` and `AgentGuidanceDeclined.Load` read three ways. After "could not read just now": `PageFor` and `SignatureFor` answer null; `Remember`, `Forget` write nothing and answer false. `AgentGuidanceDeclined.Remember` and `Forget` now return whether they wrote (`ToolchainReadiness` passes `Forget` through a lambda; `Answer` otherwise unchanged).
- A file that is there but not valid JSON keeps today's behaviour: it reads as nothing remembered and is replaced on the next write.
- Owed items: the bounded retry in `WriteAtomically` DONE; `Load` telling "could not read" from "empty" DONE (both files); the root-file write and `AppendAfterYes` report as before through `ApplyGuidance`, now with the true reason, DONE. The other renames: surveyed below, none changed (next piece of #953).
- Not done: a trail line for a refused save of the app's own records (parked as a question for Russell: no `mustRecord` event says it truly).

### #874 (the app's readers and writer of course_config.json)

- `CourseConfiguration.ReadBytes(path)` is the one reader of the file's bytes (through `HeldFiles.ReadBytes`). `Load` throws `FileNotFoundException` (not there), `FileInUseException` (held past the bound) or a JSON / `InvalidDataException` (not valid JSON).
- `Write`: a held merge read REFUSES the Save (`FileInUseException`, message "course_config.json is in use by another program, so it was not changed."); not valid JSON keeps the whole-object write. The fixed `path + ".tmp"` became a hidden temporary of its own (`ReplaceWith`), removed on every failure; the rename asks again; still held, it throws the same sentence with the file unchanged. `RecordOnDisk` reads through the one reader and replaces through `ReplaceWith`; its three-tries compare-and-swap is unchanged in meaning.
- `RevertToFile` now returns bool: false on a held file, the window's copy (edits included) kept; `CourseSettingsExclusions.Revert` returns false then and writes no `exclusions reverted` line. `ReferenceCourseUpkeep.SetSchoolYear` discards its own year change when the revert is refused, as it did before. `RereadIfNothingUnsaved` answers false on a held file without touching the copy.
- `Workspace.DiscoverCourses(path, previous)`: a held course keeps its earlier `Course` from `previous`; `WorkspaceViewModel.Reload` passes its current `Courses`. On a folder's FIRST read there is no earlier copy and a course held past the bound is not listed until the next read (the Core half; showing it with no settings would need a "not read" course through every view, which is more than `Workspace.cs` and the reload).
- `ScheduledRun`'s course read went from `File.ReadAllBytes` to `CourseConfiguration.Load`. Every other listed reader already called `Load` and now asks again: `SavedSettings.Read` (refuses with its "could not be read just now" sentence), `DeployedFolderOffer.LookUp` (absent), `ReferenceCourse.KeptOnDisk` (ordinary; the launcher's refusal is the backstop), `ReferenceImport.Measure` (settings could not be read), `ReferenceCopier.MakeIntoAReferenceCourse` (the exception goes up, with the sentence), `CoursePageCopy` (falls back to the window's sections), `Plantoir.Mcp/ReferenceWriteGate` (refuses as cannot tell).
- `CourseRestorer.cs:173` (restore's `Load`) is left for the restore batch (#873, #805, #911); it gets the retry through `Load` already and was not otherwise read for behaviour.
- `CourseSettingsView.xaml.cs:1324` (the Save's before-read, `File.ReadAllBytes`) is NOT changed (the view belongs to #986 tonight); it is excepted by name in the source-text test. It only chooses what the trail compares with; the Save itself goes through `Write`, which refuses truly.
- #874's "left" list: the C# readers retry and never take a hold as "no settings" DONE; the access-denied open during a build's replace: retried when the probe sees the hold (a sharing violation on the delete-access open), otherwise said as a permission; a delete-pending file (ERROR_ACCESS_DENIED with STATUS_DELETE_PENDING) is not told apart and not measured; the app's writes against a build reading DONE (a reader with `FileShare.Read` in a second process, refused past the bound, landing when released); every Windows C# reader asks again DONE.

## For documentation 12

### #953

On Windows a rename onto a file another program has open without delete sharing is refused (access denied); with no sharing at all a read is refused too (a sharing violation). `HeldFiles` is the one place that asks again: a sharing or lock violation, or an access-denied rename whose target (or temporary) cannot be opened for delete access with full sharing because of a sharing violation, is a hold; anything else (a deny rule, a read-only file, a reference lock) is a permission and is said at once, never retried. The bound is the one already accepted (`ObsidianFigureAddOns.Retrying`), not tuned. The guidance notice keeps the contract's `couldNotWrite` with the system's own sentence for the hold, and the file is named on the trail line. A refused read is its own answer, never "empty", and nothing that follows it writes.

### #874

`CourseConfiguration.ReadBytes` is the one reader of `course_config.json`; a source-text test (`CourseSettingsHeldFileTests.EveryReaderOfTheSettingsGoesThroughTheOneReader`) fails on any `File.ReadAll*` of a settings path elsewhere in product code (CourseRestorer.cs and CourseSettingsView.xaml.cs excepted by name). A Save whose merge read is refused by a hold is refused, rather than writing the window's whole copy over what a build may just have written; the sentence is `HeldFiles.InUseSentence`, the Undo line's "is in use by another program". Measured with a real second PowerShell process holding the file (`FileShare.None` and `FileShare.Read`).

## Every place that shows the sentence

The sentence is `HeldFiles.InUseSentence(name)` = "{name} is in use by another program, so it was not changed." ("it" is the file; "nothing was changed" was rejected because after a folder rename something HAS changed.) Where a `FileInUseException` from these calls reaches words:

- `CourseSettingsView.xaml.cs` Save: status line "Could not save: course_config.json is in use by another program, so it was not changed."; trail `settings could not be saved` "could not save the settings for ICS3U — course_config.json is in use by another program, so it was not changed."
- `CourseSettingsView.xaml.cs` folder rename (RecordOnDisk): "“Tasks” was renamed to “Assignments”, but Plantoir could not write the change to this course's settings: course_config.json is in use by another program, so it was not changed." The folder HAS moved, which is why the sentence says the FILE "was not changed" rather than "nothing was changed": it must read truly after every caller's lead-in.
- `UnitWordRenamer` (RecordOnDisk): `UnitWordRenameWording.SettingsNotWritten(to, message)`.
- `CourseRenamer.cs:105`: "The course's settings could not be saved: course_config.json is in use by another program, so it was not changed."
- `ReferenceCopier.MakeIntoAReferenceCourse` (Load and Write): the exception goes to its caller's existing message path.
- `CourseArchiver.cs:276`, `SectionAdder.cs:90`: the exception goes to their callers as before, with the new message instead of .NET's.
- The guidance notice: `couldNotWrite` with "The process cannot access the file because it is being used by another process" (the system's words, as the contract says); trail line "…first: AGENTS.md: The process cannot access…".
- `Revert` in Course Settings: returns false and the view (not changed tonight, #986) shows nothing; the window keeps its edits. #986's rewrite should show the sentence.

## The rename survey (#953)

Every other `File.Move(…, overwrite: true)` in `Plantoir.Core` and `Plantoir` outside `Undo/` and `CourseRestorer.cs`:

| Place | File it writes | Who else may hold it | Asks again | A refusal |
|---|---|---|---|---|
| `LaterClassesKept.cs:94` | the later-classes record in the course's `.internal` | a scanner, another window | no | `return false` (caller told, teacher not) |
| `LinksChecklist.cs:317` | moves a fragment back into the checklist record | a scanner | no | throws to the undo's caller |
| `ScheduledPublishOutcome.cs:279` | a scheduled run's outcome record | the window's watcher reading it | no | caught, temporary removed, swallowed |
| `ScheduledPublishOutcome.cs:793-794` | sweeps outcome records | the watcher | no | swallowed ("left for the next sweep") |
| `TaskScheduling.cs:52` | puts the kept job file back | Task Scheduler | no | swallowed |
| `ReferenceCopier.cs:197` | `.obsidian/app.json` (fixed `.tmp`) | OBSIDIAN, which the teacher has open | no | `return false` |
| `ReferenceStaging.cs:166` | a staging lease | another window | no | swallowed (in-app set still holds) |
| `SectionPublishState.cs:402` | a section's publish state | a build, the watcher | no | `return false` |
| `ToolchainMirror.cs:361` | `.toolchain/` files | a running launcher, a scanner | no | throws (counted as Failed) |
| `ToolchainReadiness.cs:713` | the readiness marker | a scanner | its own marker retry elsewhere | `(null, null)` |
| `ProblemsAcknowledgements.cs:117` | acknowledgements | a scanner | yes, `Patiently` (IOException only) | swallowed |
| `ObsidianFigureAddOns.cs:487` | the add-ons' files | Obsidian | yes, `Retrying` | reported (couldNotWrite) |

None was changed tonight. The next piece of #953: `ReferenceCopier.cs:197` first (a file a teacher's Obsidian holds, with a fixed `.tmp`), then `SectionPublishState` and `LaterClassesKept`. Shapes that should fold onto `HeldFiles` then: `ObsidianFigureAddOns.Retrying`, `ProblemsAcknowledgements.Patiently`, `ToolchainReadiness`'s marker retry and `UndoJournal`'s.

## Where this meets the Undo door

`UndoWriterScanTests` lists `AgentGuidance.cs` and `CourseConfiguration.cs` as `waitsFor: W8` (the Windows mirror of the mac's U4: settings, renames, New Course). When W8 routes those writes through `UndoDoor`, the door's staged swap and its `fileIsInUse` refusal take over the final rename. At that point the door should use this lane's held-file test (`HeldFiles.IsHeld`, the delete-access probe, and `HeldFiles.Replace`'s bound), or the two become one in whichever place the door's owner chooses; and the teacher's sentence for a held settings file (`HeldFiles.InUseSentence`) and the door's "is in use by another program" must stay the same words. Nothing tonight calls into `Undo/`, and the merge, the per-key rule and the trail lines stay where they were. Counts changed in `UndoWriterScanTests`: `CourseConfiguration.cs` 6 → 5 (the two writes now share `ReplaceWith`, which adds the temporary's removal), `HeldFiles.cs` new at 1 (the probe opens for delete access; it writes nothing).

## Must-fail lines

(filled in below from the VM runs)
