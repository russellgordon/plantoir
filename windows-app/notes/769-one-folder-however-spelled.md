# #769 item 1: one folder however it is spelled, in the publish registry and the preview leases

Branch `issue/769a-win-one-folder-however-spelled`, off `dev` 66c9853a8. Writer: Opus, 2026-11-25, Windows VM B.

## Must-fail lines

Each reverted to `==` (or to the plain `Distinct()`) on a local scratch branch, never pushed, run on VM B with `CourseActivityTests|PreviewWhileDeployingTests` (18 tests):

- `IsPublishingSection` back to `==`: 2 of 18 failed. `CourseActivityTests.APublishIsFoundUnderASecondSpellingOfItsFolder` and `PreviewWhileDeployingTests.ADeployUnderOneSpellingRefusesAPreviewAskedUnderAnother`, both "Assert.True() Failure Expected: True Actual: False".
- `IsPreviewing` back to `==`: 1 of 18. `ALeaseIsFoundUnderASecondSpellingOfItsFolder`, "Assert.True() Failure Expected: True Actual: False".
- `UnderWay`'s count back to `_previewBuilds.Distinct().Count()`: 1 of 18. `TwoClaimsOnOneSectionUnderTwoSpellingsCountOnce`, "Assert.Equal() Failure: Values differ Expected: 1 Actual: 2".
- `Take`'s refusal back to `==`: 1 of 18. `ASecondSpellingOfALeasedSectionIsRefusedAndReleasesIt`, "Assert.Throws() Failure: No exception was thrown Expected: typeof(PreviewLeases+LeaseRefusedException)".
- Before any product change (tests only, fd66f51d1): 6 of 18 failed, the five new `CourseActivityTests` facts that need a fold and the new `PreviewWhileDeployingTests` fact; `TheSameSectionInAnotherFolderIsStillAllowed` passed, as it should (two folders still answer independently).
- `IsPublishing`, `ReleaseLeftBehind`, `Release` by folder and the ports line were not reverted one by one; `IsPublishing`'s assertion and `ARowLeftBehindIsSweptUnderASecondSpelling` and the release half of the refusal test were red in the tests-only run.

After the change (e734fa5ef): the app (x64), the unit tests and the UI tests built; `CourseActivityTests`, `PreviewWhileDeployingTests`, `SectionRunsTests` and every class reading a changed file as source text (AssistSurfaceContract, DialogFirstFocus, DialogTitleScan, QuestionDialogScan, and the 18 others the grep found) passed, 318 of 318.
