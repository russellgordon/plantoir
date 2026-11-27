# The two new Windows failures on `day27/integration-4` (2026-11-27)

Branch `issue/day27-4-windows-two-failures` from `origin/day27/integration-4` (db336f587).

## 1. `ContractTests.SharedRules_ActivityTrailEvents_Exist`

- Cause: the mac's U4b3 added `"undo kept a page under a visible name"` to `shared-rules.json` → `activityTrail.mustRecord`; Windows has no `ActivityTrail.Event` for it (W8b piece 21c owes it).
- Change: `NamedGapLedger.cs` holds it as `Owed(ActivityTrailEvents, 899, V200, Reason899W8HandedOverPlace, "undo kept a page under a visible name")`. No new reason constant: `Reason899W8HandedOverPlace` already names this trail line and piece 21c. The event is not built; no `appliesOn` was added; no `contracts/` change.
- Diff of the contract's events (those for Windows) against `ActivityTrail.cs` and the ledger: this was the ONLY event missing. No other event held.

## 2. `PythonToolchainTests` → `test_links_checklist.py`

- Cause, measured on the PC with the runtime's Python 3.14: `lay_out` made each class-page link with `source.symlink_to(holds)`, `holds` being the contract's text `"../../Shared/Lesson.md"`, forward slashes. Windows stores a relative link's text as given and cannot follow a relative link holding `/`: opening it fails with `OSError [Errno 22] Invalid argument`. The same link made from `Path("../../Shared/Lesson.md")` (backslashes on Windows) reads fine. Probe on the PC, both links in one temp folder: the string one `ERR [Errno 22]`, the `Path` one read its target. Not the target's existence (targets are written first) and not `target_is_directory` (a file link).
- Change: `scripts/test_links_checklist.py` makes the link from `Path(holds)`, as `test_dates_follow_the_class.py` (`Path(page["linkHolds"])`) and `test_my_progress.py` already do. The arrangement is the same on every system; only the separator differs. No case is skipped anywhere.
- Where a link cannot be made (Developer Mode off and no SeCreateSymbolicLinkPrivilege, as on the VMs and a teacher's machine): `symlink_to` raises WinError 1314 and the cases ERROR, by design, as `test_site_files.py` does; the repository's CLAUDE.md and `WINDOWS-BOOTSTRAP.md` §6 already name Developer Mode as a requirement of the suite. This test does not skip there (the brief: never skip on Windows).
- The brief's premise that `build_site.py` runs in the container on Windows is NOT right: Windows has no container (`documentation/12-windows-app.md` → "Nothing here runs in a container"); the build runs natively on the bundled Python, so it DOES read links on the Windows side: `is_symlink` at `build_site.py:4585` and `:4593`, and `os.readlink` when following a class page's link chain (`build_site.py:5363`ff, which joins a relative text to the link's folder through `Path`, so either separator in the text it reads is joined correctly). A link a teacher makes with Windows' own tools holds backslashes and is followed; one holding forward slashes cannot be opened by Windows at all, by the build or anything else. Reading links needs no privilege; only making them does, and the build makes none of the teacher's.
- Other shared Python files #1048b touched (`test_dates_follow_the_class`, `test_my_progress`, the class-folder reading): see Runs; none needed a change.
- Mac: `test_links_checklist.py` in `quartz-teacher:dev-test` with the worktree's `scripts/` and `contracts/`: 8 of 8.

## 3. The Mac gate: `test_my_progress.py` → `AnOwnedLessonStaysUnderItsClass` (added by the director, same branch)

- Cause: NOT the `/var/folders` → `/private/var/folders` link. Run with `TMPDIR` set to the resolved temp folder it fails the same way, and the owner rule compares files by identity (`lstat`/`stat`), never by spelling. The cause is that `test_my_progress.py` is stdlib only by design (its docstring: "the grouping cases need python-frontmatter for the build's date pass and run in the image's check instead"), and `verify.sh:807` runs it on the Mac's own Python, which has no `frontmatter`. #1048b put a test that runs the build's date pass into it: there `build_site.frontmatter` is None, `_read_pages_for_linking` catches the failed `frontmatter.load` for every page, no page is read, no class claims the lesson, and `first_class_of` is empty (the `None` in the log). In the image and on Windows' runtime (both have `frontmatter`) it passes. The product is right; only the test's home was wrong.
- Change: the class moves, unchanged but for a `_quietly` helper and a `_load()` in its `setUp` (it points `toolchain_paths.CONTRACTS_DIR` at the repository's contract, which `test_my_progress.py` did at import; without it, on Windows, where there is no `/opt/contracts`, `_prepare_my_progress` caught "Cannot read the contract file" and wrote no plan, FileNotFoundError on `plantoir_progress.json`, the first PC run of b676fda91), to `test_dates_follow_the_class.py`, which needs `frontmatter`, says so and exits 77 on a Python without it, and which `verify.sh` runs in the image (line 1492) and Windows' `PythonToolchainTests` runs on the runtime. Nothing is skipped: the case runs at both gates.
- This Mac directly: `test_my_progress.py` 27 of 27 OK; `test_dates_follow_the_class.py` and `test_links_checklist.py` exit 77 ("needs the module frontmatter", the documented not-run; neither can run on a Python without it). In `quartz-teacher:dev-test`: `test_my_progress.py` 27 of 27, `test_dates_follow_the_class.py` 19 of 19 (18 plus the moved case, which passes), `test_links_checklist.py` 8 of 8.

## Runs

- PC, c940c4fc5 (fixes 1 and 2), `ContractTests.`, `PythonToolchainTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`: both builds 0 errors, 406 of 406 passed, 13 m 8 s. Every shared Python file passed on Windows, so `test_dates_follow_the_class`, `test_my_progress` and the class-folder reading needed nothing for Windows.
- PC, b676fda91 (fix 3, test files only), `PythonToolchainTests`: 145 of 146: the moved case ERRORED (no contract folder natively, above). Fixed in the next commit; that file run alone on the PC's runtime Python 19 of 19, `test_links_checklist.py` 8 of 8, `test_my_progress.py` 27 of 27.
- PC, final head, `PythonToolchainTests`: 435709ced, both builds 0 errors, 146 of 146, 12 m 56 s; lock taken and released by this run.

## For the director

- The trail event is held under #899 (W8b 21c); the hold goes when 21c lands.
- The brief's container claim is wrong for Windows (above); nothing to act on, but a brief that relies on it should be corrected.
