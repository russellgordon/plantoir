# #899 W8c-1b: a settings change Plantoir could not finish offers Put It Back (Windows #949)

Base: W8c-1a's pushed head b052a2f9f. Stacks on it; merges with it, never alone.

## For PROGRESS

- Each one-file settings caller answers W8c-1a's door as the Mac does. Only "could not
  finish" reaches the teacher as something new: ONE alert, made by ONE call.

| Caller | new value | old value | neither | could not finish |
|---|---|---|---|---|
| Set School Year (`ReferenceCourseUpkeep.SetSchoolYearJudged` / `WriteSchoolYearJudged`, the sheet `SidebarPane.SetSchoolYear`) | `Saved`, silence | retried, then `Refused(couldNotSetSchoolYear)` | `Refused(couldNotSetSchoolYear)`, never retried | `CouldNotFinish(offer)`: "school year", the old year as the picker labels it (`SchoolYear.PickerLabel`: "2026–27", or the picker's "No school year") |
| Save Course Settings (`CourseConfiguration.SaveCourseSettings`, `CourseSettingsView.Save_Click`) | silence | retried, then `CourseConfiguration.SaveFailureLine`: "Could not save: The file couldn’t be saved." (no file name, the Mac's LOW A2) | the same line | `SettingCouldNotFinishException(offer)`: `CourseConfiguration.PutBackOffer`: one changed member named in `SettingsNamedOneAtATime` (`course_name` → "course name", the old value cleaned by the course-name rule and trimmed) with `settingCanBePutBack`, else "course settings" with `settingsCanBePutBack` |
| Rename folder, moving no folder and relinking no page (`SpecialFolderRenamer.Rename`, `CourseSettingsView.RenameFolderAsync`) | renamed, its usual sentence | retried, then "was not renamed, and nothing was changed: …" | the same, never retried | `SettingCouldNotFinishException(offer)`: "folder name", the old name; its offer line under `folder renamed` |

- Core (`Plantoir.Core/Models/SettingPutBack.cs`): `SettingPutBackOffer` (title, text and
  the two button titles, read by key from `ReferenceCourse.Wording` / `WordingLists`),
  `SettingWriteResult`, `SettingCouldNotFinishException`, and `SettingPutBack`:
  `AnswerOnceClosed` (the answer once the alert has closed: Put It Back when its button
  was pressed, whichever order the press and the close come in; a close alone is Not
  Now and writes nothing), `Answer` with its three callers (`AnswerForTheSchoolYear`,
  `AnswerForASave`, `AnswerForARename`): Not Now leaves the step in flight for the next
  launch; Put It Back calls `UndoDoor.PutBackAtOnce(seq)`, reads the settings from the
  file again (`RevertToFile`), and on failure says the caller's own sentence with no
  file name (`couldNotSetSchoolYear`; Save's line; `renameFolderStoppedPartWay` with
  `{said}` "The file couldn’t be saved."). Trail: the Mac's `SettingStopTrail` words,
  one line for the offer and one for each answer (`OfferedLine`, `NotNowLine`,
  `PutItBackLine`); Save's offer line is the Mac's own "could not save the settings
  for … — stopped part way, offered to put back".
- View: `Plantoir/Views/SettingPutBackAlert.AskAsync(offer, show)`, the one alert, a
  `ContentDialog` through the caller's safe show (`SidebarPane.ShowDialogSafelyAsync`;
  `CourseSettingsView.ShowAlertSafelyAsync`, the same shape) and
  `DialogButtons.EnablePrimary`. Put It Back is the Primary and default button, Not Now
  the Close button; both visible, no key caught.
- The rename's alert: a ContentDialog cannot stand over the rename sheet (Microsoft:
  "There can only be one ContentDialog open per window at a time. Attempting to open
  two content dialogs will throw an exception."), so the sheet closes and the alert
  follows it, in place of the sheet's problem line. A failed Put It Back is then said
  in the folder notice (the sheet is gone).
- `ReferenceCourse.Wording` says `settingCouldNotBeChanged`, `settingCanBePutBack`,
  `settingsCanBePutBack`; `ReferenceCourse.WordingLists` says
  `settingCouldNotBeChangedButtons`, compared with the contract as a list in
  `EverySentenceIsTheContracts` (a list's JSON text is never compared as a sentence).
- The Set School Year picker's labels come from `SchoolYear.PickerLabel` (one function
  for the picker and the offer).

## HIG and Microsoft lines followed

- Apple HIG, Alerts: "Always place the default button on the trailing side of a row
  or at the top of a stack. Cancel buttons are typically on the leading side of a
  row"; "Note that you don't want to make a Cancel button the default button";
  "people appreciate using keyboard shortcuts … Pressing Escape (Esc)".
- Microsoft, Dialog controls: "The 'do it' action button(s) should appear as the
  leftmost buttons. The safe, nondestructive action should appear as the rightmost
  button"; CloseButton: "The user presses the ESC button on the keyboard";
  DefaultButton: "The button will respond to the ENTER key automatically"; "There can
  only be one ContentDialog open per window at a time." Windows follows Microsoft's
  order (Put It Back left, accent, Enter; Not Now right, Escape), the Mac its own.
  Put It Back is the default because it is the fix being offered and nothing is lost
  by it; it is an offer, not a confirmation, and nothing else asks.

## For #986 (fields that save as they change)

A field that saves on its own calls `CourseConfiguration.SaveCourseSettings` (or a
one-member write like `WriteMemberAsOneStep`) and, on `SettingCouldNotFinishException`,
`SettingPutBackAlert.AskAsync(offer, …)` then `SettingPutBack.AnswerForASave`. Each
field that should be offered by its own name adds its key and alert name to
`CourseConfiguration.SettingsNamedOneAtATime` (and its old-value rule to
`OldValueAsTheAlertSaysIt` when it has one), as the Mac's "For #986" says.

## For documentation 12

Beside W8c-1a's paragraph: "A settings change Plantoir could not finish offers Put It
Back": the table above, the one Core answer (`SettingPutBack`) and the one view call
(`SettingPutBackAlert.AskAsync`), why the rename sheet closes before the alert, and
the no-file sentence.

## Tests

`Plantoir.Tests/UndoStoppedStepTests.PutItBack.cs` (the class made `partial`): each
caller's four outcomes; the offer's words equal the contract's with placeholders
filled; the answer whichever order the press and the close come in; Not Now writes
nothing and leaves the step; Put It Back writes the old value and closes the step
(school year, course name, folder name); a failed Put It Back says the caller's
sentence with no file name; the three trail lines. `TheContractsStoppedSettingCases`'s
`settingCouldNotBeChanged` row now asserts the alert's title (1a's "For W8c-1b").
`ReferenceCourseTests.EverySentenceIsTheContracts` compares the list as a list.
`UndoSaveCourseSettingsStepTests.AFourthRefusalInARow…` pins Save's line naming no file.
`DialogTitleScanTests` census: `Views/SettingPutBackAlert.cs` = 1.

Tests first: 4fe45d442, red by not compiling on its parent (CS0246 `SettingPutBackAnswer`, `UndoStoppedStepTests.PutItBack.cs` line 113).

## Ledger

`ShelfWording`'s four `Reason899SettingsFinishesItself` rows pass and are gone; the
constant is gone (nothing else used it, and no other reason's sentence named these
keys).

## Must-fail lines

`vm-tools/guest/899-w8c-1b-mustfail.json`, run `w8c-1b-mf1` on the PC at e09ce534e, each
alone, then restored: **5 of 5 RED**.

1. Closing answered as Not Now before the button's action (`&&` for `||` in
   `AnswerOnceClosed`): `TheButtonPressedDecidesTheAnswer` 2 red ("Expected: PutItBack").
2. Save's offer always "course settings": `SaveThatCannotFinishOffersTheCourseNameByName`,
   `SavesPutItBackPutsTheOldNameBackAndAFailedOneNamesNoFile`.
3. The rename's could-not-finish skipped: `ARenameThatCannotFinishOffersTheOldName`,
   `ARenamesAnswersLeaveTheirLinesAndAFailedPutBackNamesNoFile` (not a `SettingCouldNotFinishException`).
4. The title retyped: `TheOffersWordsAreTheContracts` (strings differ at 4).
5. A file name in Save's refusal line: `AFourthRefusalInARowWritesNothingAndKeepsTheEditsUnsaved`,
   `SaveHoldingTheOldValueOrNeitherSaysItsLineNamingNoFile` (2), 4 red.

Restored: 428 of 428.

## Runs

- `w8c-1b-r1` (PC, e09ce534e): red ref 4fe45d442 did not build; both builds 0 errors;
  the 13 classes 428 of 428: UndoStoppedStepTests 45, UndoSetSchoolYearStepTests 10,
  UndoSaveCourseSettingsStepTests 10, CourseSettingsSaveTests 5, UndoRenameFolderStepTests 18,
  SpecialFolderRenamerTests 65, ReferenceCourseTests 14, QuestionDialogScanTests 16,
  DialogTitleScanTests 7, NamedGapLedgerTests 8, UndoWriterScanTests 5,
  UndoOpKindsContractTests 78, UndoStackContractTests 147.
- `w8c-1b-mf1` (PC, e09ce534e): must-fail above.
- `origin/dev` before proving and before hand-back: 35b54c40a both times, already contained (nothing to merge).

## Left for the next piece

- Nothing of this piece.

## For the director

- The rename's old-value ending still names the file ("… nothing was changed: “course_config.json” was changed by another program …"), as on the Mac, whose follow-up parked the same change; left as it was on both.
- Windows has no shelf groups yet (#827), so the no-year value is the picker's own "No school year", not the Mac's no-year group title ("Other"). When #827 lands, `SchoolYear.PickerLabel(null)` is the one place to change.
- Put It Back reads the settings from the file again (`RevertToFile`), which drops any other unsaved edit in Course Settings, as the Mac's `replaceWithTheFile` does.
