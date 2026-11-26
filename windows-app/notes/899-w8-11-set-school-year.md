# W8-11: Set School Year as ONE step, and member steps in the replay (#899, Windows #949)

Branch `issue/899-w8-11-set-school-year`, from `origin/dev` 06e067fbe. Pieces 12 and 13 start from it.

## For PROGRESS

- Set School Year is ONE step through the door: one `editJSON` on `reference_school_year` in the course's `course_config.json`, made by `sheet`, held by the course (no section), all or none. Its before is the member as the file held it when the step was planned (none when absent); its bytes move by the member rule; a file that is missing, not one JSON object, or that the member rule cannot move is one `writeFile` of today's whole bytes; a choice that changes nothing writes nothing, makes no step and leaves no trail line. A step refused because the member itself changed between plan and make is planned again from the file, up to three times (the mac's `writeAsOneStep`).
- `UndoActionStep` has a member form (`EditJson`, `UndoMemberChange`) and a `WriteBytes`; a step holding a member-planned file is made through `UndoDoor.Perform(UndoOpsDraft)` (`MakeAsOps`, the mac's `makeAsOps`), which plans forward from the disk at the make, so a member another window changed meanwhile is kept. In shadow a list that cannot take such a step leaves one trail line and the files go in as planned; live it is refused before anything changes.
- `CourseConfiguration.WriteMemberAsOneStep` / `PlanMemberWrite` (the writer that takes its step from its caller, as `TimetableMemory` does); `Write`'s whole-file merge is now `WholeOver`, shared with the member writer's whole case. After the make this copy follows the file as it is (`FollowTheFile`, the mac's `finishWrite`).
- `ReferenceCourseUpkeep.WriteSchoolYear` is the sheet's write (the mac's `SetSchoolYearSheet.write`); `SetSchoolYear` keeps its guards and calls it.
- The action-trace replay makes a step with `members` as its recorded `editJSON` ops through the door (`MembersDraft`); the recorded-step fixture checks each `editJSON` op against the recorded member (path, key path, before, after). The guard now names `moves`, `folderMoves`, `trees`.

## For documentation 12

Under "What W8 copies from U4a": Set School Year is built (W8-11) as above; the replay makes member steps as their recorded ops; `saveCourseSettings`' six traces (action-133 to 138) pass on the recorded ops though Windows' Save is not converted yet (W8-12). The part-way question below.

## Must-fail lines

See "Runs".

## Runs

- `w8-11-a`, the PC, bfb94e4bd (before the merge), both builds and the 15 classes of `899-w8-11-go.ps1`: 550 of 550 passed. That includes action-133 to 138 and 145 to 150, and the fixture row `setSchoolYear`.
- Merge of origin/dev 96a3d2b73 (W8 pieces 7 and 8): 48a25006c. In `NamedGapLedger.cs`, dev's `Reason899W8U4b` was kept and its "hold members" clause changed to folderMoves.
- `w8-11-b`, the PC, 48a25006c, classes and the 4 must-fail rows: running at hand-back (`C:\vm-setup\w8-11-b\run.log`).

## Left for the next piece

- Save of Course Settings (W8-12) can use `PlanMemberWrite`'s shape, widened to every top-level member whose value the Save changes (keys sorted). Beware Newtonsoft's default date parsing if values are compared through `JToken`.
- Add folder (W8-13).

## For the director

- Tests first: the new tests were written before the product; on the base they did not compile (no `WriteSchoolYear`, `PlanMemberWrite`), and each new behaviour is proven red by its must-fail row rather than by a separate red run of the base.
- Parked (wording, the brief's "not in scope"): a Set School Year step left part way (a one-file swap whose put-back fails) answers `ReferenceCourse.CouldNotSetSchoolYear` ("could not be saved"), as the mac's `SetSchoolYearSheet.write` does for every error, though the file then holds the new year and its earlier bytes are kept beside it. Options: (a, recommended) keep the mac's twin now and raise a contract key for a settings part-way sentence on both platforms; (b) say `undo.wording.keptBesideIt` after it on Windows alone. Not built.

## Self-check

Items 7 and 8 green on `w8-11-a`. Item 9: no riding lows. Item 10: one file, its before read at plan time (must-fail row 2). Item 11: rows cleared, reasons rewritten, including U4b's. Item 12: no key added to a replay's `KeysChecked`. Item 13: the member rule is `UndoJsonMember.Moved`. Item 14: `w8-11-b` was still running at hand-back, and its lock is released by the run itself.
