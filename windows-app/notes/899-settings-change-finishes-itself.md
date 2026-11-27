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
Save Course Settings (`CourseSettingsView.save`) is NOT wired here.

## For the director

- A stop whose file holds neither value (another program changed it) is
  closed by recovery's settle as `interrupted`; the door then offers Put It
  Back, which refuses (member at neither value) and the save's failure
  sentence is shown. Judged the honest reading; check it.
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
- The old value is the picker's label, "2026\u201327", not "2026\u20132027"
  as the ruling's example writes it: PARKED for Russell.
- `dev` merged in (already contained). No number tuned. The contract's
  three words run from the JSON (`testTheOfferSaysTheContractsWords`); no
  recoveryCases array was added (parked).
- Tests run: UndoStoppedStepTests 6/6, UndoCourseSettingsStepTests and
  ReferenceCourseTests 37/37 (first run, same tree but the test file).
