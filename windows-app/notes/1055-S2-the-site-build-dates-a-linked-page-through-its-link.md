# #1055 S2: the site build dates a linked page through its link

Branch `issue/1055-S2-site-build-dates-through-a-link` (the name the director's prompt gave; the brief's longer name was not used), worktree `/Users/russellgordon/plantoir/wt-1055-S2`, base `origin/dev` 412053b07.

## What changed, function by function (`scripts/build_site.py`)

- `_reaches_the_page_through_a_link` is gone. Its hard-link half is kept as `_has_a_second_name(source)`: `source.stat().st_nlink > 1`, and an `OSError` still answers True, exactly as released. Its `is_symlink()` test and the walk over the folders between the page and the course folder are removed.
- Both callers (`_write_date_into_the_teachers_page`, and the front page's title repair `#584`) call `_has_a_second_name`. Their outcome for a hard link is still "linked": no new outcome and no new sentence.
- `_replace_the_page_safely` now writes at the file the page leads to. `page_itself = Path(os.path.realpath(source))`. The hidden file is made beside `page_itself`, `copymode` comes from it, and the re-read and the `os.replace` happen at it. A page that is itself a link therefore stays a link with the same target. A page under a linked folder already landed in the real folder; the same resolution covers it.
- The lock: `_HoldingTheCourseDatingLock(source)` is still given the page's own path in the course, not the resolved one. `_the_course_dating_lock` walks up from that path to the folder holding `course_config.json` and keys the lock by it (`.merged_output/.dating.lock`, or a temporary file named by the sha1 of the resolved course path). Not redesigned.
- Docstrings: `_write_date_into_the_teachers_page` ("linked" now means a hard link; a symbolic link is written through), the date pass's `left_linked` comment says the same, and `_replace_the_page_safely` says it writes through the link. `announce_dated_pages` is unchanged; its sentence is true of a hard link.

## Kept (question 3 is open)

Present by grep in `scripts/`: `_has_a_second_name` (definition plus 2 callers), `left_linked` (date pass, `give_date`, `announce_dated_pages`), `test_a_page_with_two_names_is_never_written` (unchanged), `_HoldingTheCourseDatingLock` (class plus its use in `_replace_the_page_safely`). Why: the hard-link half is released #275 behaviour, and question 3 of #1055 has not been answered.

Empty: `git grep -n "_reaches_the_page_through_a_link\|is_never_written_through" -- scripts contracts documentation/05-build-pipeline.md`.

## Tests (`scripts/test_dates_follow_the_class.py`)

- `test_a_page_that_is_a_link_to_a_file_elsewhere_is_dated_through_the_link` replaces 356, with the same way of laying the link. It checks that the file the link leads to carries the class's date under `createdSection1` and that every other byte is unchanged. It also checks that the link and its `readlink` target are unchanged, that `rewritten == ["Exercises/Kept Elsewhere"]`, that `left_linked == []`, and that the site copy is dated. A second build rewrites nothing, and the link is still a link afterwards.
- `test_a_page_inside_a_linked_folder_is_dated_through_the_folder` replaces 382. The fixture's `CourseFolder.build` uses `rglob`, which does not follow a folder that is a link, so it cannot lay a dated class for this shape. The test therefore calls `_write_date_into_the_teachers_page` directly on the page under the linked folder, with no new helper. It checks that the outcome is "written", that the real file holds the date byte for byte, that the folder is still a link, and that nothing is left beside the file. This is RED on the base, so the inverted-asserts fallback was not needed.

## Contract and documentation sentences

`contracts/class-planning.json` → `datingPagesAClassBrings` → `howTheWriteIsMade`:
- Before: "A page that is a link to a file kept elsewhere — the page itself, a folder between it and the course folder, or a second name for the same file — is never written through: two courses sharing one page would overwrite each other's date on alternate builds, and a file outside the course is not the build's to change. The build names such a page in its console instead, and its site copy is still dated."
- After: exactly the brief's sentence ("A page that is a symbolic link, or sits under a folder that is one, is written through the link: … and its site copy is still dated."). The file parses. `contracts/README.md` has no sentence saying a linked page is never written through, so it is unchanged.

`documentation/05-build-pipeline.md`, #275 section:
- Before: "**Links are never written through.** A page that is a symbolic link, one inside a folder that is …, or a file with a second name (a hard link) is left alone: measured, the first version rewrote a file OUTSIDE the course …"
- After: "**A symbolic link is written through; a hard link is not written.**", followed by the contract's wording and the console sentence for a hard link. Nothing else on the page changed.

## Runs

- Docker was running. The `quartz-teacher:dev-test` image was used with the worktree's own `scripts/` and `contracts/` mounted, and was not rebuilt.
  - RED on the base: `test_dates_follow_the_class` had 16 tests and 2 FAILED (the two new tests).
  - After the change: `test_dates_follow_the_class` 16 OK, `test_links_checklist` 8 OK, `test_my_progress` 27 OK, `test_class_folder` 6 OK.
- `python3 scripts/test_my_progress.py` on the Mac's own Python: 27 OK.
- Mac, through `xlock.sh`, 15-minute kill: `ClassPlanningContractTests`, `PagesDatedByTheBuildTests`, `SiteHealthContractTests`, then a plain Debug build. The results are in the "Mac results" section below.

## Red lines (`windows-app/notes/1055-S2-mustfail.log`)

- On the base: the linked-folder test failed with `'linked' != 'written'`. The link test failed with `'2026-09-08T07:00:00.000+0000' != '2026-09-24T07:00:00.000+0000'`.
- Sabotage A, the writer not resolved (`page_itself = source`): the link test failed with "the link was replaced".
- Sabotage B, `is_symlink()` put back into `_has_a_second_name`: the link test failed because the file was not dated.
- Sabotage C, the hard-link half dropped: `test_a_page_with_two_names_is_never_written` failed because the page was dated.
- Each sabotage was restored from a saved copy, and `git diff` showed only the intended change.

## Merges of origin/dev

- Before proving: `git merge origin/dev` reported "Already up to date" (`dev` was still 412053b07), so there was no merge commit.
- Before hand-back: `git merge origin/dev` again "Already up to date" (`dev` still 412053b07); no merge commit.

## Self-check

1. Broke each change and watched a test fail: yes, sabotages A, B and C above, plus the two tests that were RED on the base.
2. Every sentence on the failure paths is true: there is no new sentence. The "Left the date on …" line now fires only for a hard link, where "also lives somewhere else" is still true.
3. Dev merged in: yes, before proving (already up to date), and again before hand-back.
4. Contract cases run from the JSON: `test_dates_follow_the_class.py` reads `atBuildTime` `cases` and `writingCases` from `contracts/class-planning.json`, and all of them pass in the image. `ClassPlanningContractTests` was run on the Mac.
5. House style: no Swift changed. The new Python uses no comprehension.
6. No interim states and no migrations: nothing here is released.
7. No teacher-visible wording added or changed, so no HIG reading was needed.

## Parked

- A symbolic link to a file that has a second name (a hard link) still answers "linked", because `stat` follows the link. A teacher reaches this by linking a page to a file that was itself hard-linked elsewhere. Question: should it be written through, or left as a hard link is?

## Mac results

- `ClassPlanningContractTests` + `PagesDatedByTheBuildTests` + `SiteHealthContractTests`: 40 tests, 0 failures, TEST SUCCEEDED (through `xlock.sh`, `.dd/run-mac.log`).
- Plain Debug build: BUILD SUCCEEDED.
- Not run (director's): both gates, `verify-deploy.sh` (`build_site.py` is on the publishing path).
