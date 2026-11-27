# #1055 S1: a class's date is read and written under its own page's key; the site build's date pass is the released one

Brief: `vm-tools/briefs/2026-11-27-1055-S1-a-classs-date-under-its-own-pages-key.md`. Branch `issue/1055-S1-a-classs-date-under-its-own-pages-key`, stacked on M1's pushed head 839bbbce3. Touches `contracts/` (`class-planning.json`, one line of `file-formats.json`) and `scripts/build_site.py`: both gates, and `verify-deploy.sh` (the publishing path), all the director's.

## For PROGRESS

Mac and site build, #1055 S1 (2026-11-27): #1048 and #1048b are removed. Every reader and writer of a class's date uses the key its own page's place calls for, as before #1048; no "first class owns a shared lesson" rule exists on the Mac or in the site build. The released date pass returns: a shared lesson's `createdSection<N>` is again written by every build that dates it. The released never-written-through rule (#275) stays.

## What was restored (every file by `git restore --source=<commit>`)

The check first: for each file, `git log --no-merges <base>..HEAD -- <file>` names only the commits the brief's table allows, and for each product file `git diff <base> <merge> -- <file>` equals `git diff <base> HEAD -- <file>` (by md5).

| File | From | Check |
|---|---|---|
| `ClassPages.swift`, `AssistSectionGraph.swift`, `SectionReDatePlanner.swift`, `AssistPublishPlan.swift`, `CoursePageCopy.swift`, `PageFrontmatter.swift` | `16babfb60` | only #1048 commits; diff equal to #1048's merge `62a9c0ec1` |
| `AssistToolRunnerTests.swift`, `ClassPlanningContractTests.swift`, `SharedRulesContractTests.swift`, `SiteHealthContractTests.swift` | `16babfb60` | only #1048 (`8a38b1faa`); equal to `62a9c0ec1` |
| `contracts/class-planning.json` | `16babfb60` | only #1048 and #1048b commits; diff equal to #1048b's merge `b061be740` (which contains #1048) |
| `LinksChecklistPublisher.swift`, `scripts/build_site.py`, `documentation/05-build-pipeline.md`, `documentation/06-quartz-customizations.md` | `d32d22bda` | only #1048b commits; equal to `b061be740` |
| `scripts/test_dates_follow_the_class.py`, `scripts/test_links_checklist.py` | `d32d22bda` | #1048b and `8046ca2e8` (integration-5, its own commits labelled #1048b: `b676fda91`, `435709ced`, `c940c4fc5`); read: they only move #1048b's owned-lesson case and make #1048b's `linkHolds` laying use `Path(holds)` |
| `ClassInsertionPlanner.swift` | `4f228c923` | U4b3, relink-5, mac-2, #1048 and M1 only |

Afterwards `git diff <from> HEAD -- <file>` is empty for every row (checked by script). No file needed a hand revert.

By hand: `contracts/file-formats.json` `whyValuesMean.datedByTheBuild` back to the `-` side of #1048b's one-line hunk (replaced by script, asserted once; the file still parses; no other line touched).

Deleted whole: `DateKeyByTheTargetsPlaceTests.swift` (M1's remainder), `FirstClassKeepsASharedLessonTests.swift`; then `xcodegen generate`.

Notes kept, each with the top line "Removed by #1055 (2026-11-27): symbolic links in course content are not supported.": `1048-date-key-by-the-targets-place.md`, `1048b-site-build-keeps-the-first-class-date.md`.

`scripts/test_my_progress.py` untouched.

## Greps (done means)

- `dateKey(ofPageAt\|isTheFirstClassLeadingToItsFile\|filesTheNumberedClassesOwn\|ResolvedFile\|reachOfALinkedClass\|isALinkToNothing\|ClassPagePlace\|LinkedClassReach` in `mac-app`: empty.
- `linkedClassPage\|firstClassKeepsASharedLesson\|_owns_its_file\|_files_the_numbered_classes_own\|_pages_a_numbered_class_owns\|_identity_of_the_file\|kept_by_their_class\|_MOST_LINK_HOPS` in `contracts scripts mac-app`: empty.
- `_reaches_the_page_through_a_link\|test_a_page_that_is_a_link_to_a_file_elsewhere_is_never_written_through` in `scripts`: 3 hits in `build_site.py`, 3 in `test_dates_follow_the_class.py` (the released rule stays).

## Windows: nothing edited

- `git grep "linkedClassPage\|firstClassKeepsASharedLesson" -- windows-app/Plantoir.Core windows-app/Plantoir.Tests`: empty.
- By script, `class-planning.json` at M1's head against now: `reachStopsAtAClassPage`, `publishedBeforeIsRecorded` (its `cases` too), `sectionLocalPage`, `courseLevelPage` all equal, so `ClassPlanningContractTests.DatingPagesAClassBrings_FrontmatterKeys_MatchContract` and `FollowingLinksContractTests` read what they read before.
- `datedByTheBuild` is used by `AssistWorkspace.LinksChecklist.cs:90` as a reason code only; no Windows or Mac code reads `whyValuesMean` (grep empty), and none reads the sentence.
- `PythonToolchainTests` runs the shared Python tests natively: cases removed, no file removed, so its floor of 15 files holds. `NamedGapLedger.cs` names no #1048 row (grep of "1048" empty).
- So the Windows suite stays at its six known failures. `scripts/` changed (`build_site.py`, two tests) and Windows runs them: this decides the gate.

## For documentation 12

The PROGRESS lines for Mac #1048 and #1048b (about 2439 to 2440) are to be struck by piece D.

## Runs

- `origin/dev` fetched before proving and again before handing back: both times 99499d6b7, already in M1's base, so no merge commit was needed; M1's head did not move (839bbbce3).
- Mac, one class list through `xlock.sh` with the 15-minute kill (`.dd/run-green.log`): the brief's 24 classes, 570 tests, 0 failures, each of the 24 suites passed. (A first try exited at once with "Unknown build action": zsh did not split the class list; rerun with an array. Nothing ran.)
- Plain Debug build after the test run: BUILD SUCCEEDED (`.dd/run-build.log`).
- Scripts in `quartz-teacher:dev-test` with the worktree's `scripts/` and `contracts/` mounted (Docker was running; the image was not rebuilt): `test_dates_follow_the_class` 16 tests OK (the released `test_a_page_that_is_a_link_to_a_file_elsewhere_is_never_written_through` among them), `test_links_checklist` 8 OK, `test_my_progress` 27 OK, `test_class_folder` 6 OK.
- `python3 scripts/test_my_progress.py` on the Mac's own Python: 27 OK.

## Self-check (COMMON)

1 to 6 (NIGHT3): own classes only, one class list, through `xlock.sh` with the 15-minute kill; no gate, no UI test, no app, no Windows machine, no `verify.sh`; no timed waits; no sentence a teacher reads changed or added (every line is an older commit's); nothing tuned; no ledger change.
7. House style: no line typed by hand in Swift (every Swift file is an older commit's text), so nothing new to grep.
8. No riding lows.
9. The switch is still off; the rename record untouched (no Undo file touched).
10. No new or changed contract row beyond the restore; the removed `class-planning.json` keys were read by no replay but the restored-away Mac tests.

## For the director

No parked question.
