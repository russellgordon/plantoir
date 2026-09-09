# The overnight batch

Works the 18 outstanding items from `MAC-HANDOFF.md`, **one Claude session per
issue**, sequentially, each on its own branch off `dev`.

```bash
chmod +x overnight/run.sh        # once
DRY_RUN=1 ./overnight/run.sh     # see the plan, run nothing
./overnight/run.sh               # the real thing
```

Leave it running. It gives the terminal back when it finishes.

## What one issue looks like

1. The driver refreshes `dev` from `origin` and branches `issue/<slug>` off it.
2. A fresh `claude -p` session starts on Opus with that issue's brief and no
   knowledge of the other seventeen. It plans, has **Fable** review the plan
   adversarially, implements, has Fable review the implementation, fixes, has
   Fable review the fixes — the three reviews CLAUDE.md rule 11 asks for.
3. The session runs the mac suite, does its write-ups (`GUI-IMPROVEMENTS.md`,
   the two handoffs, the activity trail, the documentation pass), rebuilds the
   app, commits, and pushes its branch.
4. **The driver then runs the mac suite itself** and merges `--no-ff` into
   `dev` only if that is green, pushing `dev` afterwards.
5. The branch is kept, merged or not.

## Why the driver holds the merge gate

You asked for each session to merge itself. It does not, and this is the one
place the batch departs from your description.

Every issue branches off `dev`. A session that merges broken work poisons every
issue after it, and by morning you would be unpicking seventeen branches
instead of one. The driver runs the suite independently, so a session cannot
merge by *claiming* success — and a red suite costs you one branch rather than
the night. The branch is pushed either way, so nothing is ever lost; a refused
merge is `git merge` away once you have looked at it.

## Branches are left intact, all 18

Nothing is deleted, which is deliberate: you wanted them for stitching the
Windows and macOS work back together. `git branch --list 'issue/*'` at the end
prints them, and the summary says which merged.

## Watching it, and stopping it

```bash
tail -f overnight/logs/run-*.log                 # the driver's own commentary
tail -f overnight/logs/04-*.txt                  # one session's output as it goes
column -t -s $'\t' overnight/logs/summary-*.tsv  # the scoreboard
```

Ctrl-C stops the driver between sessions. Killing it mid-session leaves that
branch checked out; `git checkout dev` puts you back.

## Statuses in the summary

| Status | Meaning |
|---|---|
| `MERGED` | Tests green, merged into `dev`, both pushed. |
| `TESTS-FAILED` | Work exists and is pushed; `dev` untouched. Look at `logs/NN-*.tests.log`. |
| `CONFLICT` | Merged cleanly nowhere — the merge was aborted, `dev` untouched. |
| `NO-COMMITS` | The session decided there was nothing to do, or got nowhere. Read its `.txt`. |
| `SKIPPED` | The branch already existed, or `dev` would not fast-forward. |
| `MERGED-NOT-PUSHED` | Merged locally, `git push` failed. `dev` is ahead of `origin`. |

The `verdict` column is the session's own last line — `DONE`,
`NO-CHANGE-NEEDED`, `PROPOSED`, `BLOCKED`, `TIMEOUT` or `UNKNOWN`.

## The 18, in the order they run

Ranked by importance, so if the night is cut short you have lost the least.

| # | Issue | Kind |
|---|---|---|
| 01 | Folder rename to a name with a space breaks Markdown links | implement |
| 02 | Folders sheet names the raw curriculum key, not the resolved folder | implement |
| 03 | Retire the placeholder's second sentence | verify (02 does it) |
| 04 | 12 MCP tools on Windows the mac lacks; nothing catches drift | decide |
| 05 | `deploy` has no `--non-interactive` | decide + implement |
| 06 | A directory named `index.md` reported "already put right" | implement |
| 07 | Repair results keyed by finding name collapse duplicates | implement |
| 08 | Wizard exact-matches graded folders; Python and Windows do not | implement |
| 09 | "Item excluded" trail line survives a Revert | decide |
| 10 | `stopPreview` contract prose describes a closed gap | implement |
| 11 | Summary/detail split still has no contract shape | decide |
| 12 | No `platformWorded` marker on "on your Mac" sentences | implement |
| 13 | Does a course code of "work" need reserving? | decide |
| 14 | A Course Settings tip sentence is in neither contract | implement |
| 15 | Wizard may write the coverage flag from the raw switch | verify |
| 16 | No test that advice names the toggle a teacher can see | implement |
| 17 | Five handoff items marked owed are already done | housekeeping |
| ~~18~~ | ~~`MAC-HANDOFF.md`'s own ordering rules have broken~~ | **dropped — see decisions above** |

**Issues 02 and 03 are one edit** — opposite branches of the same `if`/`else`,
four lines apart. 02 is briefed to do both; 03 is briefed to verify and report
a no-op. That keeps your 18 slots without doing the work twice.

## Decisions already made, 2026-09-06

Four forks were put to Russell before the batch was armed, and his answers are
written into the briefs as instructions rather than suggestions — with the
rejected options and their reasons, so the sessions write those down for
Windows instead of re-deriving them.

| Issue | Decided | Rejected, and why |
|---|---|---|
| 04 MCP tools | **Propose only, build nothing.** The escape hatch to implement a "trivial" one is explicitly withdrawn. | Attempting parity — twelve features in one night, and anything reaching `localTools` is a routing change measurable only by hand. |
| 05 deploy prompts | **Implement only the unambiguous ones, propose the rest**, labelling which is which. | Blanket refuse-loudly, and safe-defaults-everywhere: both decide prompts the session has not read yet. |
| 06 `index.md` directory | **Refuse and explain, touch nothing.** | Moving the folder aside and writing an index page — it relocates a folder that may hold the teacher's pages, unasked, sight unseen. |
| 09 excluded-item trail | **Record the revert as its own event.** | Recording on commit (a crash before saving would leave no trace at all), and leaving the quirk documented (a line saying something happened when it did not is the exact failure rule 5 exists to prevent). |
| 13 course code "work" | **Reserve it in both wizards**, refusing at creation only; an existing course by that name must keep working. | Accepting and documenting it (the mac stops being safe the moment anything adopts a `work` sibling), and reserving on Windows only (two wizards taking different codes reads as a bug later). |
| 18 handoff reorder | **Dropped from the batch.** | A large mechanical edit to a 4,586-line file with no test behind it, unattended, risks the only record of what Windows asked for. The brief is kept in `skipped/` for a session with somebody watching. |
| New wording | **Sessions may write teacher-facing sentences** — into `contracts/`, in the existing voice, listed verbatim in their final message. | Proposing all new copy, which would have stalled 06, 09, 13 and 14 short of finishing. |

Four more were settled without asking, because the repo answers them: **01** and
**11** choose their own contract key (Windows said the tests will be rewritten
against whatever lands); **08** aligns the mac to the Python and Windows rather
than the reverse; **15** and **16** fix what they find rather than reporting it.

**Only 04 now ends as a proposal by design.** 03 and 15 are verify-first and may
correctly report `NO-CHANGE-NEEDED`; everything else is expected to produce
code.

## What it will not do

No `main`, no tags, no release, no deploy, no `colima stop`, no force-push, no
GUI driving (it steals focus and nobody is there to put it back). The app is
rebuilt at the end so the Dock icon points at something runnable, and left
**quit** — launching it is yours.

## Editing the briefs

`issues/NN-slug.md` is a plain brief; `preamble.md` is prepended to every one.
Change either and the next run picks it up. The filename is the branch name:
`02-help-sheet-resolved-curriculum-folder.md` becomes
`issue/help-sheet-resolved-curriculum-folder`.

## Knobs

```bash
SESSION_TIMEOUT_SECONDS=7200 ./overnight/run.sh   # default 5400 (90 min)
./overnight/run.sh 6                              # from issue 06 to the end
./overnight/run.sh 6 9                            # issues 06 through 09
```

A session that hits the ceiling is killed, recorded `TIMEOUT`, and the batch
moves on.

## Before you start it

- Working tree clean (the driver refuses otherwise, ignoring `overnight/`).
- `mac-app/Vendor/llama` present, or `xcodegen` fails — `cd mac-app &&
  ./Vendor/fetch-llama.sh`.
- Quit Plantoir. The driver quits it for you, because `xcodebuild test` would
  terminate it anyway.
- 18 sessions × (work + a full mac suite) is a real number of hours and a real
  number of tokens. Starting with `./overnight/run.sh 1 3` on the first night
  is a reasonable way to find out what one costs.
