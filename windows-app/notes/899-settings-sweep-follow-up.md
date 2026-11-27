# #899 (Mac): the settings sweep's follow-up

Base `origin/day27/integration-6` (846783593). Fix list: the final sweep of
integration-6 (1 MEDIUM, 5 LOW) and the restore trace it could not make.

## The MEDIUM: Rename folder in Course Settings is the third caller

A rename that moves no folder and relinks no page (a per-section folder no
section has yet) is the settings file alone, so the door judges it at once.
Now, by the same ruling ("Plantoir finishes it, and if it can't, Plantoir
offers to automatically put it back"):

| File after the stop | What happens |
|---|---|
| new name | `.applied`: renamed, its usual sentence and trail line. Silence about the stop is right. |
| old name | `.refused`: retried up to three times as any changed-since refusal; then the existing "“Labs” was not renamed, and nothing was changed: …". Nothing in flight. True. |
| neither (a third name, half the bytes) | `.notMade`: the same existing sentence, never retried, no offer. Nothing in flight. True: Plantoir changed nothing it can put back. |
| unreadable, or the lock not got | `.couldNotFinish`: `RenameResult.couldNotFinish(offer)`; the sheet stays open and shows the SAME alert (`.settingPutBackAlert`, the one call), "The folder name could not be changed." / "Plantoir can put it back to Labs." Put It Back: `CourseSettingsView.answerARenameOffer` → `putBackAtOnce`, the settings read again from the file; if it fails too, the rename's existing `renameFolderStoppedPartWay` sentence with no file name. Not Now: left for the next launch. |

The rename record: `RenameRecordClaim.stepWasNotMade` now keeps the record
on `.couldNotFinish` as on `.leftPartWay` (no record is written for a rename
that moves nothing, so this is for safety only).

### Every caller of the door that can make a one-file step

The at-once judgement runs only in `JournaledWrite.perform(ops:)` for ops
that are all `editJSON` on one file. `editJSON` ops come only from
`JournaledStep.editJSON(at:)`, called only by
`CourseConfiguration.planWrite` and `planRecordOnDisk`:

1. Set School Year (`writeAsOneStep`): new → silence; old → retried, then
   `couldNotSetSchoolYear`; neither → `couldNotSetSchoolYear`, no offer;
   unreadable → the alert. Right; wired before this piece.
2. Save Course Settings (`writeAsOneStep`, also ⌘S, the same `save()`):
   new → silence; old → retried, then "Could not save: The file couldn’t be
   saved." (no file name since this piece, LOW A2); neither → the same; no
   offer; unreadable → the alert. Right; wired before this piece.
3. Rename folder (`planRecordOnDisk`), the table above. Wired here.

Nothing else plans `editJSON`: the unit-word rename, Get Ready, Insert
Class, Re-date, the timetable, the front page and the assistant write whole
files through the files door (`JournaledWrite.perform(_:)`), which never
judges at once; a rename that moves a folder or relinks a page is not one
file. Undo and Redo do not go through `perform(ops:)`. Nothing parked.

## The lows

- A2: Save Course Settings says "Could not save: The file couldn’t be
  saved." for every refused step (the file is the course's settings file
  every time); the trail keeps the full sentence. The test pinning the old
  wording (`testAFourthRefusalInARowWritesNothingAndKeepsTheEditsUnsaved`)
  now pins the new one.
- A3: `settingCouldNotBeChangedNote` rewritten: the three callers, what
  `{setting}` and `{value}` are for each, when `settingsCanBePutBack` is
  said, the picker's label "2026–27", and each caller's own failure
  sentence for old / neither / a failed Put It Back.
- A4: `SettingStopTrail` (beside the alert): one line for the offer and
  one for each answer, left by all three callers (Set School Year now
  leaves the offer line too; Save and Set School Year leave Not Now and Put
  It Back lines; the rename leaves all three). Put It Back that had nothing
  to write back leaves the "put back as it was" line; one that wrote also
  leaves recovery's rolled-back line.
- B1: Restore Course is checked and answered in the press's own turn
  (`StartOfYearSheetModel.restoreCourseIsPressed`), then restored with
  `restoreCourse(from:)`, which does not ask again where no one could see
  the answer: a deploy begun in the gap is refused by the whole-course
  restore itself, with its own alert in the main window.
  `restoreCourse()` keeps its old shape for the tests.
- AB1: Help lines: `start-of-year.md` (the sheet says it stopped part way:
  Restore Course or Leave As It Is), `school-year.md` and
  `course-settings.md` (the alert: Put It Back, Not Now).

## The restore and Get Ready's in-flight step (traced)

`WorkspaceModel.restoreBackup` → `CourseRestorer.restoreBackup` →
`RestoreSwap` replaces the course in place. None of them reads or writes the
Undo list (U5's seam is marked, unbuilt). So after Restore Course the
step Get Ready left in flight is STILL in flight, over a course that now
holds the backup (Go's own backup, made just before the step: every file
at the step's before).

- The next change in this session is NOT refused: only a dead process's
  step that keeps a file true (`deadStepThatKeepsAFileTrue`) refuses, and
  this one's process is alive.
- At the next launch recovery settles it by content. Usually every file
  holds its before, so it is closed as put back and nothing is written.
- The fault: after the restore, the teacher presses Go again (the same
  section, the same plan), it finishes, and Plantoir quits. At the next
  launch the old step's files hold its after bytes again (the second Go
  wrote the same content), so recovery closes the OLD step as made, a
  second "Get Ready" on the list for one change; where the second Go wrote
  only some of the same files, recovery's mixed branch puts those back,
  undoing part of the second Go's work in the restored course with nothing
  said. Also, a page edited by hand after the restore makes recovery close
  the step by the hand-edit rule and clear the Undo list.
- The right place: the restore itself settles the course's in-flight steps
  of this process (judge by content, as `UndoStoppedStep.judgeAtOnce` does,
  right after the swap: every file at its before closes the step as put
  back), or sets them aside. PARKED, not fixed in this piece (budget): no
  failing test written yet. Owed: a test that stops Get Ready part way,
  restores, runs Go again, then runs recovery as at a launch and sees the
  second Go's files untouched and one Get Ready on the list.

## Contract and Windows

- No new sentence: the rename's alert uses `settingCouldNotBeChanged` and
  `settingCanBePutBack`; its failures use existing rename sentences. Only
  the note `settingCouldNotBeChangedNote` changed (already in
  `ReferenceCourseTests.EverySentenceIsTheContracts`' `notSentences` set on
  Windows), so `NamedGapLedger.cs` is unchanged.
- For Windows: the same three callers; the rename's one-file stop offers
  the alert with "folder name" and the old name; Save's refusal names no
  file; the three trail lines.

## Must-fail log

See the hand-back's numbers; each break listed with its RED test.

## Self-check

- Tests first in their own commit (5acdf28ad), RED on the base by not
  compiling (`RenameResult.couldNotFinish`,
  `CourseSettingsView.answerARenameOffer` do not exist there) and by the
  Save wording assertion.
- No GCD, no timed waits, no `map`/`filter`/`reduce`, no closure
  shorthand; explicit types; `// MARK: -` on the new enum.
- Every sentence on the rename's failure paths true; none names a file.
- `origin/dev` (8046ca2e8) already contained.
