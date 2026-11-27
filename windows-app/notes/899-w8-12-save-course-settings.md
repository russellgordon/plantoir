# W8-12: Save of Course Settings as ONE step (#899, Windows #949)

Branch `issue/899-w8-12-save-course-settings`, from piece 11's `issue/899-w8-11-set-school-year` ff2af1e4e (which holds `origin/dev` 96a3d2b73; dev had not moved at the start or at hand-back, so no merge commit was needed). Piece 13 can start from it.

## For PROGRESS

- Course Settings' Save is ONE step through the door: `CourseConfiguration.SaveCourseSettings(course)`, made by `sheet`, action `saveCourseSettings`, held by the course (no section). `PlanWrite` reads the file once, merges this copy's changes over it per key (`WholeOver`, the same merge `Write` makes, so the two-window merge, its kept/replaced report, the `settings saved` trail line and the cleaned course name are as before), then plans one `editJSON` per top-level member whose VALUE changes, keys sorted (ordinal), each moved by the member rule (`UndoJsonMember.Moved`), compact value bytes; a member absent before has no before. A file that is missing, not one JSON object, or that the rule cannot move (or whose moved bytes do not read back as the Save's values) is one `writeFile` of the whole bytes. A Save that changes no value plans nothing: no write, no step.
- A refusal `changedSince` (one of the step's own members changed between plan and make) is planned again from the file, up to three times (four tries); the fourth throws, nothing written, the edits unsaved. The sheet's existing failure line shows it: "Could not save: “course_config.json” was changed by another program while it was being saved." (the door's own `Reason` sentence; no new wording).
- After the make this copy IS the file as read back (`TakeTheFile`, the mac's `finishWrite`), so a member another program changed between plan and make is in memory too; only when it cannot be read back does it take the plan's values.
- A `course_config.json` that is a link is planned at the file it leads to (`CourseConfiguration.FileALinkLeadsTo`, by `UndoLinks.Look` then `File.ResolveLinkTarget(…, returnFinalTarget: true)`, the mac's `fileALinkLeadsTo`); the link stays a link. Set School Year's `PlanMemberWrite` now follows a link the same way (one function for the rule).
- `CourseSettingsView.Save_Click` calls `SaveCourseSettings` in place of `Config.Write`; the held-back Save (#387), the printing snapshot (#496), the other windows' re-read and the after-Save sentences are unchanged. Revert writes nothing (as before).
- Fixture: `saveCourseSettings` is in `Converted` with the mac's edits (`graded_folders` = Tests, `hidden` = Media) in `Run`; its six traces (action-133 to 138) run the real Windows action. No `WindowsOwnJson` entry: Windows' bytes are the mac's recorded after, byte for byte.

## For documentation 12

Under "What W8 copies from U4a": Save of Course Settings is built (W8-12) as above. Only Add folder (W8-13) is left of U4a.

## Must-fail lines

`vm-tools/guest/899-w8-12-mustfail.json`, five rows, test `UndoSaveCourseSettingsStepTests` (row 1 with `UndoActionStepsOnWindowsTests`):

1. one `writeFile` for a Save the member rule can move: RED on `w8-12-a` (6 failed of 41).
2. the befores read at make time: NOT RED on `w8-12-a` (the four-refusal race runs inside the door, after the ops are built); `TheStepsOwnMemberChangedBetweenThePlanAndTheMakeRefusesTheStep` added for it in b29a004fa; RED on `w8-12-b` (1 failed of 10).
3. the memory left as the plan's read: RED (`AnotherMemberChangedBetweenPlanAndMakeIsOnDiskAndInThisCopy`).
4. a fifth try: RED (`AFourthRefusalInARowWritesNothingAndKeepsTheEditsUnsaved`, races 5 for 4).
5. the link not followed: RED (`ASettingsFileThatIsALinkIsSavedThroughTheLinkAndStaysALink`, no applied step).

## Runs

- `w8-12-a`, the PC, 018629d6a: both builds 0; the 12 classes of `899-w8-12-go.ps1` (the brief's nine plus `UndoOpKindsContractTests`, `UndoStackContractTests`, `UndoSetSchoolYearStepTests`): 460 of 460 passed. Must-fail 4 RED of 5 (row 2 not red, above); restored 460 of 460; tree unchanged; lock released by the run.
- `w8-12-b`, the PC, b29a004fa (the row-2 test added): both builds 0; the same 12 classes 461 of 461; must-fail 5 RED of 5; restored 461 of 461; tree unchanged; lock released by the run.

## Left for the next piece

- Add folder (W8-13).

## For the director

- Tests first: the new class was written before the product was run; on the base it does not compile (no `SaveCourseSettings`, `PlanWrite`), so each behaviour is proven red by its must-fail row, as piece 11 did.
- Parked beside piece 11's (not built): a Save step left part way (a one-file swap whose put-back fails, `UndoStepLeftPartWayException`) reaches the sheet's catch and says "Could not save: …" with the door's part-way message, though the file then holds the new settings and its earlier bytes are kept beside it. The mac does the same today (its `save()` shows "Could not save:" for every error). Same options as piece 11's question: (a, recommended) keep the mac's twin now and raise one contract key for a settings part-way sentence on both platforms; (b) a Windows-only sentence.
- The fourth refusal's message is a teacher's sentence (the door's `ChangedSince` reason, naming the file), so nothing was parked for it. It differs from the mac's ("The file “course_config.json” couldn’t be saved."), which is the system's error text on each side; no contract key names it.

## Self-check

1 to 6 (NIGHT3): one teacher action, tests in the shared fixture, no wording, no interim state, no invisible control, pushed. 7: the fixture row is green, the ledger row `saveCourseSettings` is gone, `Reason899W8U4a` now names only Add folder as waiting. 8: `CourseConfiguration.cs` stays 5 writing calls (`Write` still serves Add Section, archive, restore and rename; `RecordOnDisk` Rename folder, W8b); its reason says so. 9: no riding lows. 10: one file, every before read at plan time (row 2). 11: rows cleared, reason rewritten; no other reason named the Save. 12: no key added to a replay's `KeysChecked`. 13: the member rule is `UndoJsonMember.Moved`; "is this a link" is `UndoLinks.Look`. 14: no run left going; each run released its own lock (`LOCK-RELEASED`); no lock removed that was not mine.
