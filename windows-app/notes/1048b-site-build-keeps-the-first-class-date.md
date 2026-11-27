# #1048b: the site build keeps the first class's date on a shared lesson (shared script, both platforms)

Branch `issue/1048b-site-build-keeps-the-first-class-date`, from `origin/day27/integration-3` (d32d22bda). Fixes the day27-3 sweep's MEDIUM 1. Its LOW 1 (documentation names the build nowhere) is documentation, not the script or its tests: the sentence for it is below. LOWs 2 and 3 are Windows documentation and `PROGRESS.md`, not this piece.

## For PROGRESS.md and the documentation

- `scripts/build_site.py`, `_date_pages_from_their_classes` step 2 (and the links checklist's `datedByTheBuild`, which uses the same claim): a page whose teacher's file one of the section's NUMBERED class pages owns is never dated by the build (step 2 skips it); since fix round one it is still claimed, by its OWNER (`_first_linking_classes(..., kept_by_their_class={page: owner})`), for My Progress and the links checklist (see "Fix round one"). The owner rule is the contract's `firstClassKeepsASharedLesson` sentence, coded as the Mac's `ClassPages.isTheFirstClassLeadingToItsFile` / `filesTheNumberedClassesOwn`: `_owns_its_file`, `_files_the_numbered_classes_own`, `_pages_a_numbered_class_owns`, files compared by identity (`lstat` for a link's place, `stat` for the file it leads to), hops walked as `reachOfALinkedClass` does (at most 32). The section's class pages are its own pages inside a class folder of the build; the build now records its class folders beside the unit word (`set_class_folders`, in `build_section_site`).
- A shared lesson only an unnumbered page of the class folder leads to (or a numbered class whose link passes through one) is dated by the build exactly as before.
- contracts: `class-planning.json` → `datingPagesAClassBrings.frontmatterKey` gained `firstClassKeepsASharedLessonCases` (seven cases) and `firstClassKeepsASharedLessonCasesLayout`. Run from the JSON by `scripts/test_dates_follow_the_class.py` (`test_a_file_a_numbered_class_owns_keeps_that_classs_date`), each case built for every section, then built again (the second build changes no file). `firstClassKeepsASharedLesson` itself is unchanged: it is now true of the build.
- Documentation 09 (about 24107) and `windows-app/PROGRESS.md` (about 2439), the sixth writer (sweep LOW 1): "The site build's date pass (`scripts/build_site.py`, `_date_pages_from_their_classes`) is a sixth writer: it never dates a file one of the section's numbered classes owns by this rule (#1048b); every other page a class brings it dates as before."

## Must-fail log

Tests first, in their own commit (b8671a358), on d32d22bda's `build_site.py`: 5 of the 7 cases RED (two classes; three classes; a later class only mentions it; the chain; two sections). The two unnumbered cases are green there by design (the build's behaviour for them does not change) and were proven RED by breaking the fix (2 below). With each part of the fix broken on the fixed code, then restored:

1. The skip in `_first_linking_classes` removed: the same 5 cases RED.
2. The numbered check removed (every class-folder page protected): "only an unnumbered page of the class folder links to the lesson" and "a numbered class's link passes through an unnumbered page" RED.
3. The class's own reach check removed: "passes through an unnumbered page" RED.
4. Hops never compared with the class pages' places: "passes through an unnumbered page" RED.

Restored: 17 of 17 in `test_dates_follow_the_class.py`. Not separately provable in the build: the two halves of the rule that only choose WHICH numbered class owns a file (the plain class page that is the file; an earlier link that reaches it directly). Either way a numbered class owns it and the build writes nothing, so no build outcome tells them apart; they are kept so the rule is the Mac's, sentence for sentence.

## Runs

In the image `quartz-teacher:dev-test`, with the worktree's `scripts/` and `contracts/` copied over the image's (not `verify.sh`): `test_dates_follow_the_class.py` 17 of 17, `test_links_checklist.py` 8 of 8, `test_class_folder.py` 6 of 6, `test_my_progress.py` 27 of 27; after merging `origin/dev` (already contained), the same 58 of 58. `test_coverage_tab.py`: 49 of 53, the 4 errors are `/opt/deploy.sh`, `/opt/preview.sh`, `/opt/setup.sh` not present in this ad-hoc run (verify.sh mounts them); the same 4 on d32d22bda.

## For the director

1. A teacher whose RELEASED build already wrote a later (or earlier) class's date into a shared lesson: the released build rewrote `createdSection<N>` on every build to the date of the earliest visible class that says `[[Lesson]]`. After this change the build stops writing it, so the file keeps that last-written value: the class list, through the link, shows the owning class (say Unit 1, Day 2) on that other class's day (Day 1's, 8 September) until a Re-date or Insert Class writes Day 2's own date through its link; from then on no build moves it. Nothing is migrated. Whether Re-date should be suggested is Russell's call.
2. `scripts/build_site.py` is on the publishing path: the commit hook asks for `verify-deploy.sh` before the work is called done; not run (no gate, no publishing from this piece).
3. The Mac does not yet run `firstClassKeepsASharedLessonCases` (it runs `linkedClassPageCases`); a Mac test that builds the same folders and asks `filesTheNumberedClassesOwn` would pin both to one table. Not built: no `xcodebuild` in this piece. Windows likewise (`DatingPagesAClassBrings_FrontmatterKeys_MatchContract` does not walk the array; nothing goes red).
4. `linkedClassPageCases` are not run by the script: the build never writes a class page's date (it reads `_date_for_this_section`, and a class page that is a link is never written through), so there is no build function deciding that key to run them against.

## Self-check

- Broke each fix and watched the test fail: yes, four breaks above, each RED; restored, green.
- No timed waits where an event exists: none added; the tests run synchronously.
- Every sentence on the failure paths is true: no new sentence a teacher reads; a link that leads to nothing owns nothing and protects nothing (`_identity_of_the_file` None), and such a page is still never written through (`left_linked`, unchanged).
- `dev` merged in: yes, before proving and before handing back (`origin/dev` already contained).
- No number tuned by trial: the one number, 32 hops, is the Mac's `reachOfALinkedClass` bound.
- Contract cases run from the JSON: `firstClassKeepsASharedLessonCases`, by `test_a_file_a_numbered_class_owns_keeps_that_classs_date`; `linkedClassPageCases` cannot be (point 4).

## Fix round one (review 1: 1 HIGH, 1 MEDIUM, 4 LOW)

The first round protected an owned lesson by leaving it OUT of every claim, and two readers of the same claim changed by accident. Now: a lesson a numbered class owns is still a dated lesson, its date the owner's, and it is never written over.

- **HIGH 1, links checklist (done).** `_links_checklist_offer`: a page in `_pages_a_numbered_class_owns` is offered `why: "datedByTheBuild"`, `date: null` (what the base offered, and true: nothing is to be written), `claimedBy` the OWNING class, however it is reached (step 1, step 2 or the other group). No new `why` value: an unknown one drops the row on the Mac and Windows, and Windows code is not changed here. Contract: `file-formats.json` → `linksChecklistOffer.whyValuesMean.datedByTheBuild` and `class-planning.json` → `fromTheLinksChecklist.rule` (2) say so; cases r and s (`linkHolds`, new in the layout). Mac: `LinksChecklistPublisher.plan` skips the date move (and the "dated from a class" count) for any row whose page is one of `ClassPages.filesTheNumberedClassesOwn(among: classPages)`, so a stale offer cannot write one either (`FirstClassKeepsASharedLessonTests.testPublishingFromTheChecklistNeverWritesAnotherClassesDateIntoAnOwnedLesson`).
- **MEDIUM 1, My Progress (done).** `_first_linking_classes` takes `{page: owner}`: an owned page is claimed by its owner when the owner is visible and dated (so `firstClassOf` names Day 2, not Day 1 and not nothing), otherwise by the first class linking it as before; the date pass skips owned pages either way. `test_my_progress.py` → `AnOwnedLessonStaysUnderItsClass`. Not a contract change to `myProgress`; the grouping sentence is in `class-planning.json` → `firstClassKeepsASharedLessonCasesLayout` and documentation 06.
- **LOWs 1 to 3 (done).** `_class_pages_of_the_section(section)` lists the class pages from the TEACHER's folder as the Mac's `ClassPages.list` does: `section<N>/<class folder>/**.md` with the class folder directly in the section folder, every page whether its settings read or not, no dot file or folder, no `index.md`, lowercased-path order. Contract cases "a class's link passes through a hidden folder inside the class folder" and "a folder named like the class folder elsewhere in the section holds no class"; `test_the_class_pages_are_the_section_class_folders_pages_as_the_mac_lists_them` for the unreadable page (not observable as a date: a hop is a link, so it reads as the file it leads to).
- **LOW 4 (done).** Every `firstClassKeepsASharedLessonCases` case carries `ownedByANumberedClass` and `owningClass` ({section: class page}); ten cases now (added: hidden folder, nested folder, a hidden lesson whose owner is hidden too). The script asserts them through `_owners_of_the_files_the_numbered_classes_own`; the Mac through `filesTheNumberedClassesOwn` / `isTheFirstClassLeadingToItsFile` (`FirstClassKeepsASharedLessonTests.testTheContractsOwnerCasesAreTheMacsRule`).

### For Windows

- `windows-app/Plantoir.Core/Assist/AssistWorkspace.LinksChecklist.cs` about 467 to 472: publishing a ticked row writes `row.Date` with no owner guard, the write the Mac's publisher now refuses for a file a numbered class owns. The build no longer offers a date for one, so only an offer file from an older build reaches it; Windows owes the guard through its copy of the owner rule. Same file about 448: a page a ticked class brings is dated with the class's day with no owner guard (the Mac's `AssistPublishPlan` has one, `filesTheNumberedClassesOwn`).
- Windows owes its copy of the owner rule and a test that runs `firstClassKeepsASharedLessonCases` from the JSON through it, asserting `ownedByANumberedClass` and `owningClass` (and the nine `linkedClassPageCases`, already owed). Nothing goes red there today.

### Must-fail log (fix round one)

Tests first in 842d585e3, on c7c97ddd6's code: script 12 RED (test_dates_follow_the_class 10: the owner assertion on all nine cases then present, the hidden-folder case on its DATE as well, the class-page list; test_links_checklist 1, case r: `claimedBy` Day 1, `why` dated, date 2026-09-08; test_my_progress 1: `firstClassOf` empty). Mac 2 RED in `testPublishingFromTheChecklistNeverWritesAnotherClassesDateIntoAnOwnedLesson` (the lesson moved to 2026-09-08; counted as dated from a class); the Mac's contract-case test was green on the Mac's rule from the start, as it should be. Each part of the fix broken on the fixed code, then restored (script, in the image):

1. Date pass skip of owned pages removed: case "the lesson is hidden…" RED.
2. Offer's owned-page `datedByTheBuild` removed: case s RED.
3. Offer's claimant not the owner: cases r and s RED.
4. Owner claim in `_first_linking_classes` removed: My Progress RED.
5. Hidden folders walked: hidden-folder case and the list test RED.
6. A class folder at any depth counted: nested-folder case and the list test RED.
7. Pages with unreadable settings dropped from the list: the list test RED.
8. Mac: the publisher guard is the fix the RED above proves (the test fails without it on c7c97ddd6 and passes with it).

### Runs (fix round one)

In `quartz-teacher:dev-test` with the worktree's `scripts/` and `contracts/` over the image's: `test_dates_follow_the_class.py` 18 of 18, `test_links_checklist.py` 8 of 8, `test_my_progress.py` 28 of 28, `test_class_folder.py` 6 of 6. Mac, through `xlock.sh`: `FirstClassKeepsASharedLessonTests`, `LinksChecklistTests`, `LinksChecklistComingWithTests`, `LinksChecklistFollowingTests`, `DateKeyByTheTargetsPlaceTests` 62 of 62. `origin/dev` merged before proving and before handing back (no new commits).

### For the director (fix round one)

- The parked sentence (point 1 above) also covers an offer file an earlier build wrote: on the Mac the publisher now refuses its date for an owned lesson; on Windows it would still write it (For Windows).
- What a deploy publishes beyond the key: `firstClassOf` in `quartz/plantoir_progress.json` names the owning class again (as before #1048b, but the owner rather than the first class saying the name), and the offer file's owned rows carry `claimedBy` the owner.
