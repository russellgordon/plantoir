# #769 item 1: one folder however it is spelled, in the publish registry and the preview leases

Branch `issue/769a-win-one-folder-however-spelled`, off `dev` 66c9853a8. Writer: Opus, 2026-11-25, Windows VM B.

## For PROGRESS

- #769 item 1: `CourseActivity` (`IsPreviewing`, `IsPublishing`, `IsPublishingSection`) and `PreviewLeases` (`Take`'s same-section refusal, `Take`'s same-folder ports, `ReleaseLeftBehind`, `Release` by folder) compare working folders through `WorkingFolder.IsTheSame`, never `==`; `UnderWay()` counts preview builds once per `SectionKey`, so two claims on one section under two spellings count once. The two view lease questions (`SectionDetailView.xaml.cs` repair's "open in another window", `AssistWindow.xaml.cs` `PreviewIsShowing`) ask it as `MainWindow.Verbs.cs` already did. The stored spelling is unchanged. The issue's own case: a section deploying under `C:\x` now refuses a preview asked as `C:\X\`, with the existing sentence. Tests: `CourseActivityTests` (five new facts, `Respelled` = upper case plus a trailing separator) and `PreviewWhileDeployingTests.ADeployUnderOneSpellingRefusesAPreviewAskedUnderAnother`.
- The two view lines have no unit test of their own; they ask the same comparison as `MainWindow.Verbs.cs` line 86.
- Not folded, by design: a mapped drive (`Z:\` for `\\server\share`) is not folded by `WorkingFolder.Resolved`, so it is still two folders here, as everywhere else in the app; `Resolved` was not extended.
- Not changed: course code case. `IsPreviewing`, `IsPublishing` and `IsPublishingSection` compare the code with `==`; `SectionKey`, `ReleaseLeftBehind` and `Release` by folder compare it case-insensitively. Each line kept what it had.
- Grep after the change of `windows-app/Plantoir.Core` and `windows-app/Plantoir` for `FolderPath ==`, `== folderPath`, `== _folder`, `== workspacePath`: no hits remain, so there are no other comparisons to name.

## For documentation 12

The publish registry (`CourseActivity`) and the preview leases (`PreviewLeases`) compare working folders as the rest of the app does since #162 and #728 (`SectionKey`, `SectionRuns`): every folder comparison goes through `WorkingFolder.IsTheSame`, which folds what `WorkingFolder.Resolved` folds (case, a trailing separator, a relative or `..` path), and the quit question's count of previews being built is distinct by `SectionKey`. The stored spelling stays as given, because it names the container and the port; only the comparisons fold it. This is the Mac's rule (`FolderIdentity.isSameFolder` in `CourseActivity.coursePublishIsRunning` and `sectionPublishIsRunning`, #189). Before #769, a section deploying under one spelling did not refuse a preview of it asked under another, and a second window could take a second lease on the same section. A mapped drive is not folded (`Resolved` does not resolve it), so it remains a different folder.

## Must-fail lines

Each reverted to `==` (or to the plain `Distinct()`) on a local scratch branch, never pushed, run on VM B with `CourseActivityTests|PreviewWhileDeployingTests` (18 tests):

- `IsPublishingSection` back to `==`: 2 of 18 failed. `CourseActivityTests.APublishIsFoundUnderASecondSpellingOfItsFolder` and `PreviewWhileDeployingTests.ADeployUnderOneSpellingRefusesAPreviewAskedUnderAnother`, both "Assert.True() Failure Expected: True Actual: False".
- `IsPreviewing` back to `==`: 1 of 18. `ALeaseIsFoundUnderASecondSpellingOfItsFolder`, "Assert.True() Failure Expected: True Actual: False".
- `UnderWay`'s count back to `_previewBuilds.Distinct().Count()`: 1 of 18. `TwoClaimsOnOneSectionUnderTwoSpellingsCountOnce`, "Assert.Equal() Failure: Values differ Expected: 1 Actual: 2".
- `Take`'s refusal back to `==`: 1 of 18. `ASecondSpellingOfALeasedSectionIsRefusedAndReleasesIt`, "Assert.Throws() Failure: No exception was thrown Expected: typeof(PreviewLeases+LeaseRefusedException)".
- Before any product change (tests only, fd66f51d1): 6 of 18 failed, the five new `CourseActivityTests` facts that need a fold and the new `PreviewWhileDeployingTests` fact; `TheSameSectionInAnotherFolderIsStillAllowed` passed, as it should (two folders still answer independently).
- `IsPublishing`, `ReleaseLeftBehind`, `Release` by folder and the ports line were not reverted one by one; `IsPublishing`'s assertion and `ARowLeftBehindIsSweptUnderASecondSpelling` and the release half of the refusal test were red in the tests-only run.

After the change (e734fa5ef): the app (x64), the unit tests and the UI tests built; `CourseActivityTests`, `PreviewWhileDeployingTests`, `SectionRunsTests` and every class reading a changed file as source text (AssistSurfaceContract, DialogFirstFocus, DialogTitleScan, QuestionDialogScan, and the 18 others the grep found) passed, 318 of 318.
