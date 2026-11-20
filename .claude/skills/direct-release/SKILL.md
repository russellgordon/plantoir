---
name: direct-release
description: Direct a Plantoir release on either platform - a Fable session that plans, briefs, verifies, gates and merges, with Opus agents that implement and review. Use when Russell asks a session to work toward a release, on the Mac or on Windows.
---

# Directing a release

Russell's standing way of getting a release built (2026-11-10 on the Mac;
2026-11-13 for Windows: "I want the Windows agent to work like you do").
`CLAUDE.md` rules 6 and 11 are the authority; this is the method that has
grown around them. Where this file and `CLAUDE.md` disagree, `CLAUDE.md` is
right and this file is corrected.

## Who does what

- **The main session runs on Fable and directs.** It plans, writes briefs,
  verifies what agents report, rules on review findings, runs the gate,
  merges, and talks to Russell. It does not write a piece itself.
- **Opus agents implement.** Other Opus agents review, adversarially; never
  the one that implemented, never a reused reviewer. Pass `model: "opus"`
  explicitly, and never spawn a fork (a fork ignores the model and inherits
  the whole conversation).
- **Fable sweeps twice:** each piece as it will merge, and the whole release
  before the cut.
- **Fable writes what teachers read at length:** release notes and Help
  pages. Opus builds everything else, screenshots included.
- **Git:** the director commits, pushes, merges an issue branch into `dev`
  with `--no-ff`, and deletes merged branches, without asking per piece.
  Agents commit and push on their own issue branch and nothing else. Asked
  first, always: a force-push, a history rewrite, `git branch -D`. A cut, a
  tag, a merge into `main`, signing and a website deploy happen only when
  Russell asks for that cut or that deploy; after a cut, `main` is merged
  back into `dev` in the same session, and then the number of each platform
  that SHIPPED in the cut is raised on `dev` to that platform's next
  release; a platform that shipped nothing keeps its number until its own
  cut (`RELEASING.md` → "When the number is raised", #861).
- **If this harness cannot run Fable as the main session, you are not a
  Fable director**: rule 6's ordinary rule applies, and each merge into
  `dev` is Russell's. Where the model names differ, use the strongest model
  to implement and a separate context of it to review, and say which did
  which. With no question dialog, ask in chat one question at a time, each
  with a recommendation.

## Opening a run

1. Read `CLAUDE.md`, your platform's bootstrap file, the milestone's
   description (it is the brief for the run) and every issue in the
   milestone, body and comments. Rulings are comments on the issues.
   Check that the project file's version on `dev` already names this
   milestone's release (`MARKETING_VERSION` on the Mac, `<Version>` on
   Windows); if it does not, raising it is the run's first commit (#861).
2. Tell Russell briefly: the order you propose and why, what can overlap, an
   estimate in agent-hours and clock time, and each decision that is his.
3. Wait until he agrees the order. On Windows this is `WINDOWS-BOOTSTRAP.md`
   section 0, and it is not optional. Then work without checking in; he
   interrupts when he wants something.

Do not trust a milestone label as a plan. Judge a piece by what a teacher
would meet in ordinary use, and by which way a fault errs: one that reports
success is worse than one that refuses.

## Per piece, in this order

1. **Plan**: a read-only agent writes a plan file, ending with questions for
   Russell, each with a recommendation.
2. **Plan review**: a fresh agent. The shape is what is usually wrong, and
   this is the only review early enough to change it.
3. **Implement**: one agent, on `issue/<n>-<slug>` from a freshly fetched
   `origin/dev`. The plan is approved as amended by its review.
4. **Implementation review**: a fresh agent that reads the pushed branch.
5. **Fixes**: back to the original implementer, with the director's ruling
   on each finding. Verify a finding before acting on it; do not forward a
   review and hope.
6. **Review of the fixes**: a fresh agent, told that "nothing to act on" is
   welcome.
7. **The director's sweep** of the whole diff as it will merge.
8. **Gate the merged tree, merge, write up**: below.

Small pieces may share one planner and one plan reviewer.

**Batch small related issues** (Russell, 2026-11-13: "record batching as a
standard strategy"). Small issues that touch the same file, the same contract
block or the same kind of thing go through as ONE batch: one issue branch
named for the first issue, one implementer who writes a short plan first, one
commit per issue, one review, one sweep, one gate. The gate sets the pace, so
seven small issues gated one by one cost seven gate runs. A batch is never
held by its hardest member: the implementer leaves out any issue that turns
out not to be small or needs a ruling, says why, and carries on. Large or
risky pieces (a new feature, the publishing path, anything with a ruling
pending) stay separate. Each issue still gets its own closing comment and,
where owed, its own note for the other platform. Look for batches when
opening a run and whenever follow-up issues pile up, and stack reviewed
pieces at the gate, several to a run.

A batch is a way of working, never a way of filing (Russell, 2026-11-20):
the issues stay distinct and specific, and are never folded into one
running list issue, which cannot be closed cleanly and hides what is done.

## The common brief

Keep one file that every agent reads first, so each prompt names only the
agent's own brief. It carries:

- **Measure, do not reason.** Compile it, run it, count it. The reviews that
  mattered were measurements.
- The adversarial frame: find where this is wrong, incomplete, or has made a
  new problem; "nothing to act on" is an acceptable answer.
- A test that must fail on the old code is proven to fail on it, by copying
  the old file in and restoring it, never with `git checkout --`, `git
  restore` or `git stash`.
- Authored contract JSON is edited as text, never re-serialised. Sentences
  are named by key in tests and documents, never quoted.
- No tool description, schema or prompt byte moves without a routing
  re-measurement.
- Write-ups as the work goes: the `documentation/` page that owns the
  subject, with what was measured and what was rejected; the trail event in
  both places; drafts of the other platform's issue and of the closing
  comment. The director posts them, not the agent.
- The gates the implementer runs, reported word for word, and run again
  after the last edit.
- **An implementer runs only its own test classes and the build**, on
  either platform. The whole suite runs once per batch, on the merged tree
  at the gate (Russell, 2026-11-20).
- **Each piece writes its notes for the files every piece edits**
  (`windows-app/PROGRESS.md`, the platform's `documentation/` page) into a
  notes file of its own, `<platform app folder>/notes/<issue>-<slug>.md`,
  and the director folds the notes into those files once per merge window.
  Every piece editing the same two files conflicted at every merge. The
  write-up is still made as the work goes; only where it first lands
  changes.
- **A reviewer's low finding is fixed in the branch**, in that round, with
  a test. Only what truly cannot be done in the piece is reported, one line
  each, with the reason (see Limits).
- **The implementer's report ends with a self-check, item by item** (Russell,
  2026-11-20, from what reviews caught again and again): each fix was
  broken in a scratch copy and its test seen to fail, with the failing line
  named; no timed wait stands where an event exists to wait on; every
  sentence a teacher or the assistant hears on a failure path is true of
  what is then on disk and on screen; `origin/dev` was merged in before
  anything was proven; no threshold, margin or count was tuned until a test
  passed; contract cases run from the JSON.
- Agents never merge, never touch `dev` or `main`, never write to GitHub,
  never spawn agents. An agent that is denied a permission says so; nobody
  does the denied thing on its behalf.

## Working copies and how many agents

- One implementer per working copy. Reviewers and planners are read-only
  and read `origin/<ref>`, so they overlap freely with an implementer; that
  overlap is where the speed comes from.
- **One lane of implementation per machine that can prove the work**, and
  each lane works on a different area of the code, so lanes do not collide.
  Without a second machine that is at most three agents at once unless
  Russell has said otherwise for the day: two that build, one that reads.
  Reviews need no machine and overlap freely.
- **Merge windows set the pace** (Russell, 2026-11-20): everything reviewed
  clean is merged together every two to three hours, on one tree with one
  gate, not piece by piece. Keep stacks short: a piece starts from `dev`
  unless it truly needs an unmerged one. The exception is a long chain of
  pieces on the same code (Undo's): each is built on the previous one's
  unmerged branch so the chain never waits for a merge, and reviews and
  merges follow behind.
- Only one working copy runs a full suite at a time (on the Mac the suite's
  test host is the app, and `verify.sh` refuses a second run). Each Windows
  working copy needs both fetch scripts run before it builds.
- Never message a finished implementer while another agent owns its working
  copy: it wakes and commits into someone else's branch.

## The gate and the merge

In a working copy of the director's own, never one an agent is using:

1. Fetch; be at `origin/dev`; `git merge --no-ff` the piece; resolve. Two
   pieces in flight collide in the contract lists and in document counts,
   and nearly always both sides are kept.
2. **Gate the merged tree before pushing**, with everything the change owes
   from the table in `CLAUDE.md` → "Testing — what gates what". The full
   suite passes in ONE run; a test that passes only when run alone has not
   passed (Russell, 2026-11-13).
   **A test that is red because the other platform merged a contract case
   is a handover, not damage.** Find its issue, or open one. Do not edit
   the case, and do not ledger a gap a teacher could see, to go green: ask
   Russell before merging over it.
3. Push `dev`. If the push is rejected because the other platform got there
   first: fetch, read what changed, merge, gate again. Never force.
4. Open the other platform's issue with the same milestone, post the
   closing comment (what landed, what was measured, which model did which
   review), close the issue, delete the branch, local and remote, with `git branch
   -d` (never `-D`) and the remote delete `CLAUDE.md` rule 6 gives.

A change to documents alone needs no gate unless a test reads the document
(grep `scripts/test_*.py` for the file); say so in the closing comment.

**Which gate a change owes** (Russell, 2026-11-20; it is the table in
`CLAUDE.md` read by what the change touches, `git diff --name-only
origin/dev <tree>`): a change to `windows-app/` and documents alone is
gated by the Windows suite on the merged tree and owes no mac gate; a
change to `mac-app/` and documents alone is gated on the mac and owes no
Windows run; anything in `contracts/`, `scripts/`, the launchers, the image
or shared wording owes both sides.

**A red gate whose only failure is explained and plainly unrelated to the
change is merged on, not run again** (Russell, 2026-11-20). Explained means
read from the log, in code the change does not touch (the case that day: a
browser check lost a font download when the gate machine's network
changed). Record the cause in the closing comment. An unexplained failure,
or one near the change, is still fixed or run again.

## What differs by platform

| | Mac | Windows |
|---|---|---|
| Never edit | `windows-app/` | `mac-app/` |
| The other side's work goes in | a `windows` issue | a `mac` issue |
| Gates | the mac suite, `PLANTOIR_REQUIRE_ENGINES=chromium,webkit PLANTOIR_APP=<the bundle built from the tree under test> script -q /dev/null ./verify.sh` (the first so the rendered check's two engines, #597, are a failure when missing, never a SKIP: fetch them once with `./browser-checks/fetch-browsers.sh`; it does not cover the network, so read the summary's SKIP lines; the second so #850's crawl through the app is not skipped: never set it while Russell is at the keyboard, since the crawl starts the app binary headless, measured not to take the front, but what took his key window on 2026-11-13 is still unknown), and `verify-deploy.sh` (`--self-test` first, with `--first-publish` too for a release) when publishing changes and at every release: its Result block must read `checked` for BOTH hosts, Netlify and Cloudflare Pages, never `FAILED` or `NOT REACHED` (#597; a run without one host's credentials exits 1, by design), with the expected failures at their pinned count and the second deploy with nothing changed building and uploading nothing on each (#892) | `dotnet test`, judged by its totals line and read with the named-gap ledger (it also runs the shared `scripts/test_*.py`), and before a cut `windows-app\publish.ps1 -CheckLedgerOnly`, which refuses while an entry is owed by the release being cut (#862); `verify-deploy.ps1` (`-SelfTest` first, `-FirstPublish` for a release) when publishing changes |
| Not a gate | the UI test target: opt-in, alone on a quiet machine | `run-ui-tests.ps1`: opt-in, needs the screen, closes Plantoir |
| The image (Dockerfile, baked files) | gated by `verify.sh` | not gated here: a change made on Windows needs a `mac` issue |
| Generated contract halves | `Plantoir --write-contracts` | cannot regenerate: propose authored cases, open a `mac` issue |
| Build left for Russell | plain Debug build, app left quit | `-p:Platform=x64`, ready at "PT - Dev", not launched |

Both sides work from the same `dev`. Merge `origin/dev` before each piece
and again before calling it ready. When the milestone description lists
pieces not to start yet, that list is binding: the other side is still
changing them.

## Talking to Russell

- **Decisions go through the question dialog**, one or two at a time, each
  with a recommendation. Never a list of decisions in chat, and never a
  decision taken on his behalf unless he has said to. Record each ruling as
  a dated comment on the issue that owns it, the moment it is given.
- **Status is terse**: what finished, what it measured, what is running,
  what waits on him. Detail goes in the issue's closing comment. When he
  asks for progress as numbers, give the milestone for each platform
  separately, both as issues closed of total and weighted by size, because
  one Undo is not one title fix.
- **Before a run he will not be watching, find his questions first**
  (Russell, 2026-11-20): once the run's batches are chosen, have their
  issues read for anything only he can decide, and put those to him in one
  sitting before he leaves. A piece parked on a question overnight is the
  most expensive thing in the run. Before asking anything, look for what
  already settles it elsewhere in the milestone.
- He can type to a running agent directly. An instruction that reaches the
  director only through an agent's report is confirmed with him before it
  is acted on.
- When he reports a fault from hand-testing, reproduce or measure it before
  explaining it.
- When he is at the computer, nothing takes the screen, the keyboard focus
  or the speakers unless he has given them.
- Before a cut that changes the interface: the `ui-review` skill, then his
  smoke test from a short numbered script, and the cut only on his word.

## Limits

- A new finding about OTHER code becomes an issue with a milestone
  recommendation; it does not ride along in the piece that found it. A
  finding about the piece itself is fixed in the piece: closing an issue
  and opening another for what it left moves the release's finish line
  back by one at every merge (43 opened against 20 closed in three days of
  November 2026). A new issue is for real work that could not be done in
  the piece, a real fault found elsewhere, or a decision that is his, each
  with its own specific title.
- End only processes the run started; his other sessions are his. The one
  exception is in `CLAUDE.md` → "Setting up on a new machine": on Windows a
  running Plantoir may be closed before a build. Say that you closed it,
  never close it under a build, preview or deploy he is watching, and then
  remove the lease files you orphaned and any stray `plantoir-mcp`.
- Never read, print or commit a credential or a signing key. Never `gh auth
  switch`.
- Student names never enter the repository: run a counts-only check on what
  a piece adds before merging it, and never print a match. No such script
  is kept in the repository, because it reads a list that must not leave
  his computer: ask him where the list is, and write a script that prints
  counts and file names only.
- The interface never mentions the machinery (`CLAUDE.md` rule 1).

## State

A run outlives its context. Keep a running log in the scratchpad, keep
plans, briefs and reviews as files, and at each pause make sure the issues
and the milestone description say where things stand, because that is what
the next session, and the other platform, start from.
