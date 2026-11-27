# #1046, #1050, #1052: test reliability (2026-11-27)

One branch, `issue/1046-1050-1052-test-reliability`, three distinct issues, one
commit each. Mac only: no product behaviour a teacher can see changed, so no
HIG section applies and nothing goes in `contracts/`.

## #1046: `WebPreviewControllerTests.testShowFreshBuildLoadsEvenWhenTheAddressWasAlreadyRequested`

**Cause.** The test judged the controller's decision to load by waiting, on a
fixed 5 s poll and two 6 s `wait(for:)`s, for WebKit to begin each navigation.
A load from `WebPreviewController` reaches WebKit only in the completion of
`websiteDataStore.removeData(ofTypes:modifiedSince:)` (the caches are emptied
first, by design), and that completion is a round trip to WebKit's own
process, delivered on the main thread. Anything that holds either back for
six seconds, such as another build running on the same Mac (gate `g-d26-2`),
failed the test at its first wait with nothing wrong in the preview. Nothing
in the product is racy: whether to load is the controller's decision alone,
made synchronously, and the test was measuring how fast WebKit answered.

**Change.** `WebPreviewController` counts the loads it asks for
(`appLoadsAskedFor`, `@ObservationIgnored`, incremented in
`loadIgnoringEverythingCached` beside `ledger.appLoadBegan()`), and the test
asserts the count after each call: first request 1, repeated request still 1,
`showFreshBuild` 2, the mounting view's `loadIfNeeded` after it still 2. No
wait of any kind remains; the old `pollUntil` (which used
`DispatchQueue.main.asyncAfter`) and `NavigationStartRecorder` are gone.

**Proof.** Not reproduced by load: 20 runs under 36 busy loops, 30 runs and 8
whole-class runs beside a looping clean build plus 4 busy loops, all green on
the old test. Reproduced by a forced ordering: the main actor held for 6.5 s
just after the first `loadIfNeeded` (`Task { @MainActor in usleep(6_500_000) }`)
failed the old test 3 of 3 with the gate's own line, "Asynchronous wait
failed ... first navigation". The same hold on the new test: 3 of 3 green.
Then 30 of 30 green in a row (see "Runs").

**Windows.** No same test or fault: Windows' preview tests are source tests
(`PreviewNavigationSourceTests.cs`) and nothing there waits on WebView2. No
follow-up.

## #1050: `LayoutAndSmallBehaviourTests.testTheBoxInTheVerbSheetTakesTheFocusAndTabLeavesIt`

**Cause.** `SheetHost` (the test host that presents a SwiftUI view as a real,
off-screen sheet) set `presentation.isShown = true` and then turned the run
loop for a fixed 0.6 s, after which the test read `window.attachedSheet`.
SwiftUI hangs the sheet on a later turn of the run loop, and how much later
depends on what else the main thread has queued. In gate `g-d27-1` (4375
tests, the screen in use) it took longer than 0.6 s once, and the test found
no sheet: it failed at 1.53 s, the length of a normal run, which is the fixed
pump running out, not a hang. No earlier test in the class leaves anything
behind that stops the sheet: each `SheetHost` makes its own parent window,
and the same test passed every time it ran alone or with its whole class.

**Change.** `SheetHost.init` now waits for the event itself: it turns the run
loop in short slices until `window.attachedSheet` is there, then gives the
same 0.6 s settle as before so the other ten `SheetHost` users (#621 sizing,
`PageTablesSheetTests`) see exactly what they saw. A 30 s bound only stops a
sheet that never opens from holding the suite; the caller's
`XCTUnwrap(host.sheet)` then fails. It prints how long the sheet took
("SheetHost: the sheet was hung from its window 0.09 s after it was asked
for"), so a slow one is visible in a gate log. The product (`SectionVerbSheet`,
`ClassDatesTextView`) was not at fault and is unchanged.

**Proof.** Not reproduced by load (same runs as #1046, the verb-sheet test in
each, all green). Reproduced by a forced ordering: a main-actor hold of 0.7 s
just after `isShown = true` failed the old host 1 of 3 with the gate's own
line, "XCTUnwrap failed ... the verb sheet did not open". Deterministically:
the sheet asked for 0.8 s late (a run-loop `Timer` setting `isShown`) failed
the old host and passed the new one (see "Runs"). Then 30 of 30 green in a
row.

**Windows.** No same test or fault: Windows has no off-screen sheet host; its
dialogs are not tested this way. No follow-up.

## #1052: `verify.sh` ran a written list of Python tests

**Cause.** Step 0.5 ran each `scripts/test_*.py` by name; nothing noticed a
file that was not named, so 14 files ran on Windows only, and six more
(`test_marking_*.py`) were named only through a loop variable. The gate was
green on a tree where `test_make_undo_traces.py` failed.

**Change.** At the end of step 0.5 a discovery runs every `scripts/test_*.py`
whose file name is not written on a non-comment line of `verify.sh` (the
file reads its own text, so a test run by name anywhere, the image runs
included, keeps its own pass line and is not run twice). Each one found must
pass; a file needing python-frontmatter exits 77 on a Mac without it and
fails there on purpose, since it belongs in the image's runs. The marking
loop now names its files whole. `not_run_on_this_mac`, the named skip list
with a reason beside each entry (as Windows' `NotRunHere`), is empty: every
file passed on this Mac. The header no longer says the list is written by
hand.

**Proof.** Step 0.5 alone (the lock and terminal check left out, nothing
else changed): 141 pass, 0 fail; the discovery ran 17 files, but only 14 were
named nowhere (3 were duplicates; corrected in fix round one) (test_make_undo_traces.py among them), all green; the six
marking files ran by name. Must-fail: a planted `scripts/test_zz_mustfail_1052.py`
that exits 1 gave "FAIL scripts/test_zz_mustfail_1052.py, found by the
discovery of every scripts/test_*.py (#1052)" and `FAILED=true`; removed, the
discovery was green again. The whole `verify.sh` was not run (COMMON: a
writer never runs it); the director's gate does.

**Windows.** Nothing to do: Windows already discovers the files.

## Runs

- `run-repro1.log`: old code, the two tests 20 times each under 36 busy loops: 40 of 40 green.
- `run-repro2.log`: old code, 30 times each beside a looping clean build and 4 busy loops: 60 of 60 green.
- `run-repro3.log`: old code, both whole classes 8 times beside the build: 168 of 168 green.
- `run-forced-old.log`: old code, main actor held 6.5 s in #1046's test: RED 3 of 3, line 50 "Asynchronous wait failed".
- `run-forced-old-1050.log`: old host, main actor held 0.7 s after `isShown`: RED 1 of 3, line 301 "the verb sheet did not open".
- `run-forced-new.log`: new code, the same two holds: 6 of 6 green.
- `run-forced-old-1050-late.log`: old host, the sheet asked for 0.8 s late by a run-loop `Timer`: RED 3 of 3, "the verb sheet did not open". `run-forced-new-1050.log`: new host, same: 3 of 3 green (the sheet hung 0.88 to 0.91 s after it was asked for).
- `run-final-30.log`: committed fix, both tests 30 times in a row: 60 of 60 green.
- `run-classes.log`: WebPreviewControllerTests, LayoutAndSmallBehaviourTests, PageTablesSheetTests (the other SheetHost user), PreviewStartPageTests (reads WebPreviewController.swift as source): 59 tests, 0 failures.
- Merges of `origin/dev`: before proving, already up to date (base 35b54c40a); before handing back, again up to date (origin/dev still 35b54c40a).

## For the director

- `contracts/` not touched; `scripts/` not touched (only `verify.sh` at the root).
- Self-check: no `DispatchQueue`, `map`, `filter`, `reduce` or `$0` in the
  changed Swift (the one `DispatchQueue` that was there, in the old test, is
  removed); MARK sections kept; no timed wait added (the 0.6 s settle in
  `SheetHost` is the one that was there, now after the event).

## Fix round one (review 1, 2026-11-27)

Merged `origin/dev` before proving and before handing back: up to date both
times (still 35b54c40a).

**#1046 (MEDIUM 1, LOW 1).** The test now guards the real hand-off.
`WebPreviewController` counts `appLoadsHandedToWebKit` only where
`webView.load` returns a navigation, in the completion after the caches are
emptied (and where `reloadFromOrigin` returns one, Reload's other branch,
which is now counted in `appLoadsAskedFor` too; both doc comments say what
is counted). Each count calls `whenALoadIsHandedToWebKit`; the test sets it,
before each call, to fulfil an `XCTestExpectation`, and waits on that with a
60 s bound that only ends a hung test. The instant decision assertions stay.
A further hand-off after `showFreshBuild` is an `XCTFail`.

**#1050 (MEDIUM 2, LOW 2, LOW 3).** `SheetHost` registers an
`XCTNSNotificationExpectation` for `NSWindow.willBeginSheetNotification`
(object: its window) BEFORE `isShown = true`, and if `attachedSheet` is
still nil waits on it with `XCTWaiter` (30 s bound, failure only). Measured,
not guessed: at the notification `attachedSheet` is still nil, and the call
stack shows AppKit posting it from inside `-[NSWindow _attachSheetWindow:]`
under SwiftUI's `SheetBridge`, all inside the waiter's run-loop turn, so the
waiter cannot return before the sheet is attached (it was, every run). KVO
on `attachedSheet` (`XCTKVOExpectation`, options `.new`) never fired: the
property is not KVO-compliant, so it is not used. `await` is not used
because the host's initializer is synchronous and every caller would change.
The 0.6 s settle after the event is removed (nothing after attachment
needed it: the four classes are green without it) and so is the `print`.

**#1052 (MEDIUM 3, LOW 4, LOW 5).** "Run by name" now comes from ONE list
the runs write themselves: every named run hands its file to `python3`
through `ran_by_name`, which appends the name to
`/tmp/verify_ran_by_name.list` and prints it (116 run lines, the marking
loop and the #835 stem loop included). The discovery reads that list, never
the script's text, so a name in a message or comment can neither hide nor
double a file. Files run by name only after step 0.5 (the image runs, and
two `--site` runs) are written in `tests_run_by_name_later`; at the end of
the run a check fails the gate if that list and what those steps named
through `ran_by_name` differ either way. The discovery prints once
"N run by name in this script, M found and run by the discovery", and for a
discovered file whose unittest skipped cases, one line with the number
skipped (not a failure). Two shared tests read `verify.sh`'s run lines
as text and lost them to the new form (seen red in the first step 0.5 run of
this round): `scripts/test_image_only_tests_say_so.py` (`IMAGE_RUN`,
`HOST_RUN`) and `scripts/test_image_runs_find_their_modules.py`
(`RUN_SCRIPT`). Their patterns now also read `"$(ran_by_name test_x.py)"`;
checked by script against the old `verify.sh`: the same 14 image runs, the
same 101 host runs and the same mounted-script runs found as before. So
`scripts/` changed in this round (it did not in the first). Windows: nothing
to do (it discovers the files and does not read `verify.sh`). Not done: the stale docstring in
`scripts/test_build_keeps_a_readonly_hidden_page_hidden.py` (not a file
changed here).

### Must-fail and runs (fix round one)

| Check | Sabotage | Result | Log |
|---|---|---|---|
| #1046 hand-off | `webView.load(...)` in the completion replaced by `nil` | RED 3 of 3 (line 66 "Asynchronous wait failed", line 67 count 0) | `run-fix1-sabotage.log` |
| #1052 discovery | planted `scripts/test_zz_mustfail_1052.py` (exit 1) with its name echoed in a message line | "FAIL scripts/test_zz_mustfail_1052.py, found by the discovery ..." and `FAILED=true`: a name in a message no longer hides a file; file removed | `mustfail-1052.log` |
| #1050 late sheet | `isShown` set by a run-loop `Timer` 0.8 s late | green 3 of 3 | `run-fix1-sabotage.log` |

- `run-fix1-30.log`: both tests, 30 iterations each, restored code: 60 of 60 green.
- `run-fix1-classes.log`: WebPreviewControllerTests, LayoutAndSmallBehaviourTests, PageTablesSheetTests, PreviewStartPageTests: 59 tests, 0 failures (PageTablesSheetTests 30.7 s, was 40.3 s with the settle).
- `run-fix1-kvo.log`: the KVO attempt, timed out every time (why KVO is not used).
- Step 0.5 alone (lines 1 to 109 and step 0.5 of `verify.sh`, the terminal check and lock left out; `.dd/step05-fix1b.log`): **PASS 138, FAIL 0, `FAILED=false`** (141 before, less the 3 duplicate runs). Printed: "119 run by name in this script, 14 found and run by the discovery"; `test_handout_starters.py` "skipped 1 of its own test case(s)". Checked by script against the run's own list and log: each of the 133 `scripts/test_*.py` ran exactly once in step 0.5, or is in `tests_run_by_name_later` (image runs) and ran zero times there. The first run of this round (`step05-fix1.log`) was 136 and 2, the two readers above; fixed.
- The end-of-run check of `tests_run_by_name_later` sits before the summary and was not run (it needs the image steps; the director's gate runs it). It would go red if a later step that names a listed file is ever made conditional and skipped.


## Fix round two (review 2, 2026-11-27)

Merged `origin/dev` before proving and before handing back.

**#1046 (MEDIUM 1).** The test now sees ORDER. Right after the two
`loadIfNeeded` calls it asserts `appLoadsHandedToWebKit` is still 0, and
right after `showFreshBuild` that it is still 1, each before its wait.
`removeData`'s completion comes on a later turn of the main run loop, so
when the load is handed over in that completion the count cannot have
moved yet; a load handed to WebKit before the caches are emptied moves it
at once and goes red. No timed wait, no poll, no GCD.

**#1046 (LOW 1).** The fresh-build test's address is back to
`http://127.0.0.1:8081/`, as on `dev`. Round one's move to `localhost` was
not needed: nothing in the test depends on the host name, and the restored
test is green 20 of 20 with it.

**#1052 (LOW 3).** At the start of step 0.5, `verify.sh` reads itself and
fails if any line that is not a comment, `echo`, `printf`, `pass` or `fail`
hands `python3` a `test_*.py` (as `scripts/test_x.py`,
`/opt/scripts/test_x.py`, or bare inside `cd scripts`) without
`ran_by_name`. Such a line would be missing from the list, and the
discovery would run that file a second time. It reads itself by its own
base name, since it has already moved into its folder, and fails if it
cannot. Proved on copies: the real `verify.sh` PASS; with a planted
`(cd scripts && python3 -B test_planted_bare.py)` line FAIL, naming line
301; with a planted image-style `python3 /opt/scripts/test_planted_bare.py`
line FAIL too.

**#1050 (LOW 2), noted only.** The 0.6 s settle after the sheet attaches is
removed, and that removal is shown only by green runs (59 of 59 across the
four classes in round one), not by an event. If a sizing test that reads
`sheet.frame`, a table width or a row count right after `SheetHost.init`
is ever reported flaky, look here first.

**LOW 4** (the stale docstring in
`scripts/test_build_keeps_a_readonly_hidden_page_hidden.py`) stays out of
this branch, as in round one.

### Must-fail and runs (fix round two)

| Check | Sabotage | Result | Log |
|---|---|---|---|
| #1046 order | load handed to WebKit before `removeData`, nothing in its completion | RED 3 of 3 (line 69: 1 is not 0; line 79: 2 is not 1) | `run-fix2-sabotage.log` |
| #1052 bare run line | planted bare `python3` run lines (two forms) in copies of `verify.sh` | FAIL, naming the line, both times; real file PASS | by hand, in the scratchpad |

- `run-fix2-20.log`: WebPreviewControllerTests, 20 iterations, restored
  code: 60 tests, 0 failures (the fresh-build test passed 20 of 20).
- Step 0.5 alone (lines 1 to 109 and step 0.5 of `verify.sh`, the terminal
  check and lock left out; `.dd/step05-fix2b.log`): **PASS 139, FAIL 0,
  `FAILED=false`** (round one's 138 plus the new check). Printed "119 run by
  name in this script, 14 found and run by the discovery";
  `test_handout_starters.py` "skipped 1 of its own test case(s)". A first
  run (`step05-fix2.log`) was 138 and 1: the one FAIL was round one's
  `scripts/__pycache__` (written at 12:19, before that run began), which was
  removed before the second run; this change writes none.
