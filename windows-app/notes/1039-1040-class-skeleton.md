# #1039 and #1040: a new class page's bytes match the Mac's

Rulings: Russell, 2026-11-25, on each issue. Found by Windows Undo W7b1.

## What changed

- **#1040.** `AssistWorkspace.ClassSkeleton` is now `PageTextFromLiteral(ClassSkeletonLiteral(...))`. The raw string literal takes its line ends from the checkout that compiled it; `PageTextFromLiteral` makes it LF (`ReplaceLineEndings("\n")`) at the point the literal becomes a page's text. `.gitattributes` is unchanged. VM A's checkout is `core.autocrlf true` (`i/lf w/crlf` for `AssistWorkspace.cs`), so it is the case the ruling describes.
- **#1039.** A new curriculum block written by `ApplyCurriculumMentions` opens with `## Curriculum connection` (the Mac's `AssistCurriculumMentions.heading`) in place of "Today's work points here:". Existing pages are not rewritten: a block already on a page is found by its `%%curriculum-start%%` / `%%curriculum-end%%` markers whichever line opens it, and new expectations go inside it with that line left as it was.
- **The contract.** `contracts/undo-action-steps.json`, step `addCurriculumMentions`, is written by the Mac's `UndoActionStepsTests` from the real action code, and its `after` carries the Mac's block. The new test reads that case from the JSON and compares Windows' page byte for byte. No contract was added or changed.
- **Readers of the old line.** None. Searching `windows-app` and `scripts/` for "Today's work points here" found only the writer and one test fixture; every reader keys on the markers.

## Other raw string literals in Plantoir.Core

- `AssistWorkspace.ClassSkeletonLiteral`: a class page. Fixed as above.
- `TaskScheduling.TaskXml`: the Task Scheduler definition, written UTF-16 to a temporary file for `schtasks /create /xml`. Not a teacher's page and not compared with the Mac, so left as it is.
- Outside Core (not in scope, listed for completeness): `Plantoir/Views/NewCourseDialog.cs` holds a XAML raw literal that is parsed in memory, never written to a file.

## Runs

Every line below is copied from a log in `vm-tools/runs/1039-1040/` (ignored by git, kept on the main Mac). The first runs, earlier the same day, printed only to the writer's terminal, and the VM's own log (`C:\vm-setup\unit-run.txt`) went when the park restored snapshot 02. So these runs were made again, on 2026-11-25, to leave logs; their results match the first runs.

- **Machine:** VM A (`Windows 11`), dev snapshot 02, behind `vm-tools/runs/VM.lock`; parked and unlocked afterwards.
- **Checkout:** `core.autocrlf` is `true`; `git ls-files --eol` gives `i/lf w/crlf attr/text` for `windows-app/Plantoir.Core/Assist/AssistWorkspace.cs` (`autocrlf.txt`).
- **Head:** `VM A now at 3fbe4eb13 Notes for #1039 and #1040` (`head-sync.txt`); the code is the same as at 0bffb95ca, since 3fbe4eb13 adds only this notes file. `refetch-runtime.ps1` ended `REFETCH-DONE` (`head-refetch.txt`).
- **Builds** (`guest/1027-build.ps1`, `head-build.txt`): `windows-app\Plantoir\Plantoir.csproj` (x64), `windows-app\Plantoir.Tests\Plantoir.Tests.csproj` and `windows-app\Plantoir.UiTests\Plantoir.UiTests.csproj`, each `Build succeeded.`
- **Classes** (`head-suite.txt`), filter `NewClassesTests`, `CurriculumMentionsTests`, `ClubNounTests`, `UndoAcrossToolsTests`: `Passed!  - Failed:     0, Passed:    53, Skipped:     0, Total:    53`; `PASSED - 53 passed, 0 skipped, 53 total.`

## Must-fail lines

Each failing test's name, message and line were printed from the VM's unit log by `vm-tools/guest/1039-1040-failures.ps1` (committed in `vm-tools` at ee0a50b). The scratch branches were local and are deleted.

**Run 1:** scratch commit 063b0be75. `ClassSkeleton` returns `ClassSkeletonLiteral(...)` without `PageTextFromLiteral`, and the new block opens with "Today's work points here:" again. Filter `NewClassesTests`, `CurriculumMentionsTests`. Logs `mustfail-1-sync.txt`, `mustfail-1-suite.txt`, `mustfail-1-failures.txt`. `FAILED - 3 of 27 failed (24 passed, 0 skipped).`

- `NewClassesTests.TheSkeletonFromACrlfCheckoutStillBecomesLfText`: `Assert.Equal() Failure: Strings differ`, `NewClassesTests.cs:line 334`
- `CurriculumMentionsTests.ANewBlockIsTheBlockTheMacWrites`: `Assert.Equal() Failure: Strings differ`, `CurriculumMentionsTests.cs:line 216`
- `NewClassesTests.ANewClassPageIsWrittenWithLfWhateverCheckoutBuiltTheApp`: `Assert.DoesNotContain() Failure: Item found in collection`, `NewClassesTests.cs:line 313`

**Run 2:** scratch commit 257416f57. `PageTextFromLiteral` returns its argument unchanged. Filter `NewClassesTests`. Logs `mustfail-2-sync.txt`, `mustfail-2-suite.txt`, `mustfail-2-failures.txt`. `FAILED - 2 of 16 failed (14 passed, 0 skipped).`

- `NewClassesTests.TheSkeletonFromACrlfCheckoutStillBecomesLfText`: `Assert.DoesNotContain() Failure: Item found in collection`, `NewClassesTests.cs:line 333`
- `NewClassesTests.ANewClassPageIsWrittenWithLfWhateverCheckoutBuiltTheApp`: `Assert.DoesNotContain() Failure: Item found in collection`, `NewClassesTests.cs:line 313`

Line 333 fails on any checkout, because the test puts CRLF into the literal itself. Lines 313 and 334 catch a skipped normalising step only on a CRLF checkout such as VM A's; on an LF checkout they pass either way.
