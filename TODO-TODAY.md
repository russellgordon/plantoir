# TODO — today

Loose ends found on 2026-08-23 while working on the new-course wizard's
course-code field (`issue/course-code-picker`). Neither is caused by that
branch; both want their own piece of work.

## 1. The UI-test stub preview server leaks, and the "fix" for it was dead code

The `setUp`/`tearDown` cleanup I said I'd added to stop the stub server leaking
— it did nothing. The macOS XCUITest runner is sandboxed and cannot spawn a
child process, so `Process` running `pkill` never executed, and the `try?`
swallowed the failure silently. I found this by making the helper write a
marker file that never appeared. I've removed it and left a note in its place
saying why, and what would actually work (`Darwin.kill()` on a pid the stub
records, no process spawn). Dead code that looks like cleanup is worse than
none.

## 2. `testRestartingAPreviewReturnsToTheProgressView` is genuinely failing

And `testRestartingAPreviewReturnsToTheProgressView` is genuinely failing — not
transient like the others. Your traceback is the proof I didn't have: the stub
server hits `Address already in use` when the test restarts the preview, so the
site never loads and `stopPreviewButton` never appears. It fails identically
with every one of my changes stashed, so this branch didn't cause it, and it's
the same mechanism that leaks the orphan. It wants its own piece of work; I'd
rather hand it over than keep restarting previews on your machine.
