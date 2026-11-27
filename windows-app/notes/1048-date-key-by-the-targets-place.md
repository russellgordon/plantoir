# #1048 (Mac): a linked class page's date is read and written under the key the TARGET's place calls for

Branch `issue/1048-date-key-by-the-targets-place`, from `origin/day27/integration-1` (d334a288e).

## For PROGRESS.md and the documentation

- One rule, one function: `ClassPages.dateKey(ofPageAt:forSection:in:)` (mac-app `Models/ClassPages.swift`). It follows a class page through every link to the FILE it is and returns `createdSection<N>` when that file is a course-level page, plain `created` when it is inside the section's own folder, and nil for a link that leads to nothing (no date read, none written). U4b3's Insert Class decision (asking `AssistPageVisibility.isSectionLocal` of `fileALinkLeadsTo`) moved here; Insert Class now calls it instead of its own copy.
- The first-class rule (Russell on #899, 2026-11-26, "Always"): `ClassPages.isTheFirstClassLeadingToItsFile(_:among:)`. A writer that re-dates several classes in one change writes a shared file only for the class with the lowest unit and day among the section's class pages that lead to it; a later class writes nothing through its link. So the order of writing cannot matter, and the file is written once per step.
- `AssistSectionPage` gained `dateKey` (the date's key, from the shared function); `isSectionLocal` is unchanged and still decides the VISIBILITY key. `ReDatedPage` gained `dateKey` likewise.
- `PageFrontmatter.createdKey` is now `nonisolated` (pure; `CoursePageCopy` builds pages off the main actor).
- contracts: `class-planning.json` → `datingPagesAClassBrings.frontmatterKey` gained `linkedClassPage`, `firstClassKeepsASharedLesson` and `linkedClassPageCases` (six cases). The mac runs the cases from the JSON (`DateKeyByTheTargetsPlaceTests.testTheKeyCasesInTheContract`).
- documentation 09/12: the sentence to add where the date key is described: "a class page that is a link is dated in the file it leads to, under the key that file's place calls for (#1048)".

## Readers and writers of a class's date, found

| Where | Before | Now |
|---|---|---|
| `ClassPages.summary` (the class list; feeds Insert Class, Re-date, Next Class, Classes dated later, the section index pointer, Start of Year, the unit-word rename, placeholders, the sheets) | read plain `created` for every class page, a link included | reads `ClassPages.dateKey`; a broken link has no date. `summary` now takes the course. |
| `AssistSectionGraph.page` (the assistant's reading: Re-date, publishing, Today's class on the front page, the links checklist, the tools) | date key from the LINK's place | `dateKey` from `ClassPages.dateKey`, carried on the page |
| `ClassInsertionPlanner.apply` step 3 (Insert Class, Duplicate Class) | key from the target's place (U4b3), its own copy of the rule; every linked class wrote through | calls `ClassPages.dateKey`; only the first class leading to a file writes it |
| `SectionReDatePlanner.plan` / `apply` (Re-date, Roll Over through it) | wrote the key the LINK's place called for (`move.isSectionLocal`); every class wrote through, the last one winning | writes `move.dateKey`; a later class leading to the same file as an earlier one plans nothing |
| `AssistPublishPlan` date moves (publishing pages a class brings) | key from `page.isSectionLocal` | `page.dateKey` |
| `ClassPages.siblingTimeAndOffset` | reads plain `created` for the time and offset | NOT changed: it reads only the time-of-day convention; a page without the key is skipped, and a stale `created` through a link gives a time, never a date |
| `SectionIndexPointer` (front page date) | writes the section index's own plain `created` from `page.date` | NOT changed: the index is always inside the section's folder; the date it copies now comes from the fixed graph |
| `AssistToolRunner` Duplicate as a new page (4404, 4833) | writes plain `created` into a NEW file inside the section's folder | NOT changed: a new file, never a link |
| `SectionAdder`, `FolderScaffold`, `CoursePageCopier`, `CourseRestorer`, `StartOfYearPlanner` visibility | section-wide key families, visibility | NOT changed: not a class's date through a link |
| `scripts/build_site.py` `_date_for_this_section` | reads `createdSection<N>`, then `created` | NOT changed: already the reading this rule writes for |

## Must-fail log

`windows-app/notes/1048-date-key-mustfail.log`: with the reader key put back to the link's own place in `ClassPages.summary` and `AssistSectionGraph.page` (as d334a288e had it; Re-date and publishing then write that key again) and the first-class rule switched off, 9 of the 9 must-fail tests in `DateKeyByTheTargetsPlaceTests` were RED (class list x2, the graph, Re-date x3, Insert Class x3); the two tests of the new function itself (the table and the contract cases) stay green, as they should, since they do not go through the changed callers. Fixes restored: all 11 green. Insert Class's key was already right on d334a288e (U4b3), so what fails there without this piece is the first-class rule.

## For Windows

Windows must copy the same rule (W8b piece 22 is about to copy Insert Class's): one function deciding a class page's date key from the file the link leads to, used by every reader and writer, and the first-class rule for writers. Places seen: `Plantoir.Core/Assist/AssistWorkspace.cs` (the `FrontmatterKey: PageFrontmatter.CreatedKeyFor(section, sectionLocal)` lines at about 471, 1415, 2709, 2826, 2880, 3329, 4637), `ClassesDatedLater.cs` 155, `TodaysClassOnTheFrontPage.cs` 212, `AssistWorkspace.LinksChecklist.cs` 444 and 466, `AssistWorkspace.MenuDuplicate.cs` 103; `sectionLocal` there is decided from the page's own path (`PagePaths.IsSectionLocal`). The contract cases `linkedClassPageCases` are new; Windows' `DatingPagesAClassBrings_FrontmatterKeys_MatchContract` reads only the two older keys and no Windows test enumerates the new array, so nothing goes red there and no ledger entry was needed (no `Reason1048DateKeyByTarget` added; it would hold nothing). Windows should add a test that runs the six cases.

## For the director

1. What the class list shows for a LATER class linked to the same shared lesson is not ruled. Each linking class shows what the file holds. Example: Unit 1, Day 2 and Unit 1, Day 3 both link to `Shared/Lesson.md`; Re-date onto 8, 10, 14 September writes `createdSection1: 2026-09-10` (Day 2's day). The class list then shows Day 3 on the 10th as well, beside Day 2, not on the 14th. Ask Russell whether that is what he wants to see.
2. Files written by RELEASED builds with plain `created:` through a link to a shared page: if the file has no `createdSection<N>`, the reader falls back to `created` (as the build does), so the teacher sees the same date as before; the next Insert Class or Re-date adds `createdSection<N>` and leaves `created` in place (other sections without a key of their own still read it). If the file also has a `createdSection<N>`, the class list now shows that line (what the site shows) where it used to show `created`. No migration was built.
3. The VISIBILITY key through a link has the same shape of fault (`isSectionLocal` from the link's place, so Re-date's overflow unpublish and publishing write plain `publish:` into a shared file, which the build ignores when `publishForSection<N>` is there). Out of this piece's scope; left as it was. Probably its own issue.
4. Re-date's overflow (classes past the last date): a later class linked to the same file as an earlier one is no longer hidden through the link (its move is not planned). Hiding it would have hidden the earlier class's lesson too.

## Runs

- `DateKeyByTheTargetsPlaceTests` 11, `UndoMakeRoomLinkedPageTests` 27, `ClassPlanningContractTests`, `SharedRulesContractTests`, `SiteHealthContractTests`, `PageVisibilityReadingTests`, `FutureDatedClassesTests`, `UndoActionStepsTests` (which writes `contracts/undo-action-steps.json`: unchanged): 206 of 206 passed. After the merge of `origin/dev` (already up to date at bb19ba187), `SectionVerbsTests`, `RollOverFromTheMenuSafetyTests`, `RollOverFromTheMenuTests`, `PublishPlanTableTests`: 43 of 43 passed. In all 249 of 249.

## Self-check

- Broke each fix and watched the test fail: yes, the readers (summary, graph) and the first-class rule; the log above.
- No timed waits: none added; the tests run synchronously and Undo is awaited (`undoNewestAndRederive`).
- Every sentence on the failure paths is true: no new sentence a teacher reads; a broken link is skipped with no date (as before in Insert Class, now in the readers too).
- `dev` merged in: yes, before proving and before handing back (`git merge origin/dev`).
- No number tuned by trial: none.
- Contract cases run from the JSON: `testTheKeyCasesInTheContract` reads `linkedClassPageCases`.
