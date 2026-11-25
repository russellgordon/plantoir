# #769 item 2: the assistant window's busy answer does not depend on what is on screen

## Must-fail lines

Each break was made on a local scratch branch, never pushed and deleted afterwards. All runs were on VM B (`dev` 66c9853a8 and K2's 3a3f0bc31 merged in).

- `DeployIsUnderWay` asks only the run (`Find(...) is { } run && (run.IsUnderWayHere || run.IsAsking)`, `CourseActivity` dropped), and line 578 put back as it was (`MainWindowShowingThisSection()?.IsSectionBusy(...) == true`), in one scratch commit: 3 of 40 in `SectionRunsTests` plus `AssistSurfaceContractTests` failed. `WithNoViewEverOpened_APublishRecordIsUnderWay`: "the publish record, with no run". `OnceThePublishRecordIsDisposed_TheDeployIsNotUnderWay`: "Assert.True() Failure Expected: True Actual: False". `TheAssistantAsksTheSectionsDeployStateAppWide`: "Assert.Contains() Failure: Sub-string not found", the line `SectionIsBusy = () => MainWindowShowingTh…` without `SectionRuns.DeployIsUnderWay(_folder, _co…`.
- `DeployIsUnderWay` always `true`: 3 of 25 in `SectionRunsTests` failed, `WithNothingRunning_…`, `AnotherSectionOfTheFolder_…` and `OnceThePublishRecordIsDisposed_…`, each "Assert.False() Failure".

After the change (f995c9616): the app (x64), the unit tests and the UI tests built. `SectionRunsTests`, `AssistSurfaceContractTests`, `AssistScenarioTests` and every class that names `AssistWindow`, `MainWindow` or `SectionDeployRun` source files (23 classes): 324 of 325 passed. The one failure was `ToolchainReadinessTests.ACopyStillWaitingItsTurnIsNotWaitedForAndDoesNotStartOnceTheCloseBegins`, "The process cannot access the file … toolchain-copying.12280 because it is being used by another process" on its marker delete. Run alone, that class failed a different test (`ACopyWaitsForAnEarlierCopyByAnotherProgram`) the same way. The class reads `MainWindow.Menus.cs`, not a file changed here, and tests toolchain-copy marker files that this change does not touch. It is unrelated and was not re-run further.

## Self-check

1. Broke each fix: both must-fail lines above, plus an always-true body for the three false-asserting tests.
2. No timed waits added.
3. Failure paths: in the newly caught case (deploy running, no window on the section) the assistant hands to the window's Deploy and says the existing `AssistWording.SectionIsBusy`. The hand-to path is unchanged (`StartDeployInApp` finds or opens a window, whose Deploy refuses or shows the running deploy), so what is said matches what is on screen. In code, only `NoWindowKeepsItsOwnBusyAnswer` still names `IsSectionBusy` (grep). Documentation 12 still names it in four present-tense lines, listed above for the fold-in, because this piece does not edit documentation 12.
4. `dev` 66c9853a8 and K2's 3a3f0bc31 were in before proving and are still current at hand-back.
5. Nothing tuned.
6. Only the files this brief names, plus `SectionDeployRunSourceTests`, whose test read the removed `IsSectionBusy`. No contract, Mac, script or wording changes.
