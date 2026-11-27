# #899: a settings change stopped part way finishes itself (Mac)

## For PROGRESS.md and the documentation

- The door (`JournaledWrite.perform(ops:)`) now judges a ONE-FILE `editJSON`
  step that came back `notPutBack` at once, live, with recovery's own
  `UndoRecovery.settle` on that one in-flight record
  (`UndoStoppedStep.judgeAtOnce`). Holds the new value: closed `applied`, on
  the list, the door answers `.applied`. Holds the old value: closed
  `failed`/`rolledBack`, the door answers `.refused` (nothing changed).
  Cannot read the file or cannot close the step: left in flight, the door
  answers the new `.couldNotFinish(seq:, refusal)`, thrown as
  `JournaledStepError.couldNotFinish(seq:, fileName:)`.
- `UndoStoppedStep.putBackAtOnce(seq:in:)` is Put It Back: under the lock,
  each `editJSON` member found at its after value is planned backward and
  swapped (`<seq>-recover` label) as recovery would; the step is closed
  `rolledBack` (or `failed` when every member already held its old value);
  staged leftovers tidied keeping only copies. A member at neither value or
  unreadable refuses, writing nothing.
- One call per field: `.settingPutBackAlert(offer:answer:)`
  (`Views/Helpers/SettingPutBackAlert.swift`) with a `SettingPutBackOffer`
  (seq, the setting's name in lower case, the old value as read). Wired:
  Set School Year (`SetSchoolYearSheet.writeJudged`, `putBack`).
- Documentation 09 (Undo, U4a) should gain a paragraph: "a one-file settings
  step stopped part way is judged at once" (the two bullets above). Not
  written in this piece (budget); the director's to place.

## HIG lines followed (Alerts)

The live HIG page did not render to a fetch (client-side). The lines below
are the Alerts text as read and quoted in this repository by #987
(`QuitConfirmation.swift`, `OtherAssistantsSettingsView.swift`,
`DeployTokenRows.swift`):

- "Cancel buttons are typically on the leading side of a row." Not Now leads.
- "Always place the default button on the trailing side of a row." Put It
  Back trails and is the default (`.keyboardShortcut(.defaultAction)`): it
  is the fix offered, nothing is lost by it.
- "Note that you don't want to make a Cancel button the default button."
  Not Now has the cancel role and `.cancelAction` (Escape), not the default.
- Titles: "Aim for a one- or two-word title that describes the result of
  selecting the button": "Put It Back", "Not Now" (Russell's choice).
- No invisible controls: both keys are on visible buttons.

## Must-fail log

- The door's judgement turned off (`if false && isOneFileJSONStep` in
  `perform(ops:)`): `testSetSchoolYearStoppedWithTheNewYearSavesAndSaysNothing`,
  `testSetSchoolYearThatCannotFinishOffersPutItBack` and
  `testNotNowLeavesTheStepForRecovery` RED (3 of 3 that go through the door);
  restored, 6 of 6 green. The two tests that call `judgeAtOnce` directly
  were not broken separately (budget): owed.

## For Windows

- The same judgement at the door, after a swap that could not be put back,
  for a step whose ops are all `editJSON` on one file: run recovery's settle
  on that record now, live, instead of leaving it in flight.
- The alert: message `shared-rules.json` → `settingCouldNotBeChanged`
  ({setting} "school year"), informative `settingCanBePutBack` ({value} the
  old year label), buttons `settingCouldNotBeChangedButtons` (Not Now:
  cancel/Escape, leading; Put It Back: default/Return, trailing). Put It
  Back that fails, and a stop judged put back, say `couldNotSetSchoolYear`.
- Ledger: `Reason899SettingsFinishesItself` for the three new wording keys
  (not added in this piece: no Windows code touched).

## For #986

When each Course Settings field saves as it changes, the field calls its
write, and on `JournaledStepError.couldNotFinish(seq, _)` sets a
`SettingPutBackOffer(seq:, setting: "<field name>", valueBefore: "<old value
as shown>")` on the view, and the view carries
`.settingPutBackAlert(offer:answer:)`; Put It Back calls
`UndoStoppedStep.putBackAtOnce(seq:in:)` then reloads the configuration.
Save Course Settings (`CourseSettingsView.save`) was NOT wired in the first round; it is since fix round one (below).

## For the director

- (Superseded by fix round one: a stop whose file holds neither value is
  now `.notMade`, with no offer.)
- A one-file stop in the real app comes only from a swap that could not be
  put back (a race with another program plus a failed put-back); the kill
  points are test stops, judged by calling `judgeAtOnce` directly.

## Self-check

- Broke the fix and watched the tests fail: the door branch, yes (3 of 3);
  `judgeAtOnce` itself, not done.
- No timed waits: none added; the lock waits are the door's own.
- Every sentence on the failure paths true: a stop judged put back and a
  failed Put It Back say `couldNotSetSchoolYear` ("could not be saved. Try
  again in a moment."), true there; the offer says only the ruled words.
- The old value is the picker's label, "2026\u201327": decided by the
  director in fix round one, no longer parked.
- `dev` merged in (already contained). No number tuned. The contract's
  three words run from the JSON (`testTheOfferSaysTheContractsWords`); no
  recoveryCases array was added (parked).
- Tests run: UndoStoppedStepTests 6/6, UndoCourseSettingsStepTests and
  ReferenceCourseTests 37/37 (first run, same tree but the test file).

## Fix round one (2026-11-27, night; review 1: 1 HIGH, 3 MEDIUM, 5 LOW)

### What changed

- HIGH 1, the alert. `SettingPutBackAlert` now follows the app's usual
  pattern (`SidebarView.removalRequestIsPresented`): closing the alert only
  clears the offer (`alertClosed()`), and each button acts on the offer the
  alert was handed (`answered(_:with:)`, the `presenting:` value), so Put It
  Back works whichever order SwiftUI closes the alert and runs the action.
  The answer closure takes `(answer, offer)`; `SetSchoolYearSheet.answer(_:to:course:)`
  is the sheet's handler, static so a test drives it.
- MEDIUM 1, neither value. `judgeAtOnce` answers the new `.notMade` when
  recovery's settle closed the step by its rule for a file changed by hand
  (`interrupted`, `changedByHand`, list cleared): a third year another
  program wrote, or a half-written file (a member that does not parse reads
  as neither). The door answers `.notMade(seq:)`, thrown as
  `JournaledStepError.notMade`, which `writeAsOneStep` does NOT retry (it
  retries only `refused(.changedSince)`), so nothing is written over what
  the file holds, and no Put It Back is offered (it could not succeed).
  Nothing is left in flight; the next change is not blocked. The sentence
  is the existing, true `referenceCourses.wording.couldNotSetSchoolYear`:
  "{course}'s school year could not be saved. Try again in a moment." True
  here: the year was not saved, and nothing blocks a second try. No new
  sentence for this branch.
- MEDIUM 2, Save Course Settings. `CourseSettingsView.save` catches
  `couldNotFinish(seq:)` and shows the same alert (`.settingPutBackAlert`,
  one call). Exactly one setting changed and named in
  `CourseSettingsView.settingsNamedOneAtATime` (today `course_name` →
  "course name"), with a readable old value: "The course name could not be
  changed." / "Plantoir can put it back to <old name>." Several settings,
  or one not in that table: "The course settings could not be changed." /
  `settingsCanBePutBack` (new, PARKED below). Put It Back:
  `CourseSettingsView.putBack` (putBackAtOnce, then the settings reloaded
  from the file); if that fails, "Could not save: The file couldn't be
  saved." (no file name). `couldNotFinish` and `notMade` never carry the
  file's name in `errorDescription` any more.
- The settings the door now judges at once: EVERY one-file `editJSON` step
  that comes back `notPutBack` live: Set School Year, Save Course Settings,
  and any other one-file settings write that goes through
  `writeAsOneStep` / `JournaledStep.make(ops:)` with ops on one JSON file
  (the unit-word rename and folder renames are many-file and keep
  `leftPartWay`). Wired with the alert: Set School Year and Save Course
  Settings. Any other caller of `writeAsOneStep` that catches every error
  generically now shows CocoaError's "The file couldn't be saved." with no
  file name on these two paths.
- MEDIUM 3, Windows. `NamedGapLedger.cs`: `Reason899SettingsFinishesItself`
  and `Owed(ShelfWording, 899, V200, …)` for `settingCouldNotBeChanged`,
  `settingCanBePutBack`, `settingsCanBePutBack`,
  `settingCouldNotBeChangedButtons`. `settingCouldNotBeChangedNote` went
  into `ReferenceCourseTests.EverySentenceIsTheContracts`'s `notSentences`
  set (that is where the other notes, "rule", "machineryCheck", are held).
  No string in the edit holds a double quote. UNBUILT: Windows cannot be
  built here. The new `referenceCourses.settingStoppedCases` array and its
  note are outside `wording`, which is all that Windows test walks.
- LOW 1: the "not in flight" branch looks at how the step was closed:
  closed as made → `.finished`; otherwise `.notMade` (no offer, nothing
  written). The lock branch stays `.couldNotFinish`: the step is still in
  flight and Put It Back takes the lock again, so the offer can succeed.
  `putBackAtOnce` now puts back only a step still in flight; one closed
  meanwhile is never swapped without a line on the list.
- LOW 2: `putBackAtOnce` leaves recovery's `rolledBackLine` on the trail.
  It still has its own put-back core (no pre-plan tidy, no kept-original
  source): for a one-file `editJSON` step both values travel in the op, so
  nothing it needs comes from a kept original. Sharing the core with
  `settle`'s mixed branch is left (see For the director).
- LOW 3, LOW 4: for the director, below.
- LOW 5: the no-year value. The picker itself lists the no-year group by
  its title ("Other" until the teacher renames it) as one of its values,
  so "Plantoir can put it back to Other." names the value as the picker
  shows it. Kept.
- From the first hand-back: the old value is shown in the picker's own
  label (`SchoolYear.label`, "2026–27"): decided, no longer parked.

### Contract cases

`shared-rules.json` → `referenceCourses.settingStoppedCases` (and
`settingStoppedCasesNote`): five rows, the file holding the new value, the
old value, a third value, half the bytes, or unreadable, each with what the
teacher reads, whether the step is left in flight and what Undo offers.
Run from the JSON by `UndoStoppedStepTests.testTheContractsStoppedSettingCases`
through Set School Year. Windows does not run them yet (For Windows).

### For the documentation

Documentation 09 (Undo), beside U4a: "A one-file settings step that stops
part way is judged at once. When the door gets `notPutBack` for a step
whose ops all edit one JSON file, it runs recovery's own settle on that
record while the app is open, instead of leaving it in flight until the
next launch. The file holds the new value: the step is closed as made and
is on the list, and the teacher reads nothing. It holds the old value: the
step is closed as put back and the teacher reads the save's own failure
sentence. It holds neither (another program wrote it, or it is half
written): the rule for a file changed by hand closes it and clears the
list, nothing is offered and nothing is retried, so nothing is written over
it. It cannot be read, or the list's lock cannot be got: the step stays in
flight and the alert offers Put It Back, which writes the old value back
through the door, closes the step and leaves recovery's trail line; Not Now
leaves the step to the next launch's recovery."

### For Windows (added)

- The same five outcomes as `settingStoppedCases`; wire a test that reads
  them. The verdict for a file holding neither value is closed with no
  offer and no retry.
- `settingCouldNotBeChangedButtons` is an array; when Windows comes to say
  it, `EverySentenceIsTheContracts` compares `pair.Value.ToString()` (JSON
  text) with a string, so the array needs its own comparison then.
- The ledger entries go when Windows says the four keys.

### For #986 (replaces the line above)

Save Course Settings IS wired now (one alert for the Save). When a field
saves as it changes, add its `course_config.json` key and its lower-case
name to `CourseSettingsView.settingsNamedOneAtATime` (and give it a value
label if its stored value is not plain text: today only a string member is
offered by its old value), and carry `.settingPutBackAlert` on that field's
view with `CourseSettingsView.putBackOffer` / `putBack`.

### For the director

- PARKED: `referenceCourses.wording.settingsCanBePutBack`, "Plantoir can put
  them back as they were." Said as the informative text when a Save of
  several settings at once stopped part way and could not be finished,
  under "The course settings could not be changed." Example: the teacher
  changes the course name and the short label, presses Save, the file
  cannot be read as the save ends. No single "put it back to {value}"
  sentence is true for two values.
- LOW 3: "Try again in a moment" (`couldNotSetSchoolYear`) after a failed
  Put It Back is not true until the next launch: that step stays in flight
  and every change in this session is refused. The honest words are about
  the next time Plantoir opens, which are new words: for Russell. (After
  Not Now nothing is said; after a stop whose file holds the old value or
  neither, nothing is in flight, so a second try does work.)
- LOW 4: a stop judged put back answers `.refused(refusal)`, usually
  `changedSince`, which `writeAsOneStep` retries up to three times, so it
  often ends saved with nothing said. True, but the "told the year was not
  changed" sentence is then rarely reached. Not changed; for him to rule.
- LOW 2: Put It Back keeps its own small put-back core (pinned by the
  tests here, not by a shared contract case with recovery's mixed branch).
