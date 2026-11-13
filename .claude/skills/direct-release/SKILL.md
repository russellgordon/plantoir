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
  Russell asks for that cut or that deploy.

## Opening a run

1. Read `CLAUDE.md`, your platform's bootstrap file, the milestone's
   description (it is the brief for the run) and every issue in the
   milestone, body and comments. Rulings are comments on the issues.
2. Tell Russell briefly: the order you propose and why, what can overlap, an
   estimate in agent-hours and clock time, and each decision that is his.
3. Then work without checking in. He interrupts when he wants something.

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
- Agents never merge, never touch `dev` or `main`, never write to GitHub,
  never spawn agents. An agent that is denied a permission says so; nobody
  does the denied thing on its behalf.

## Working copies and how many agents

- One implementer per working copy. Reviewers and planners are read-only
  and read `origin/<ref>`, so they overlap freely with an implementer; that
  overlap is where the speed comes from.
- At most three agents at once unless Russell has said otherwise for the
  day: two that build, one that reads.
- **The gate sets the pace.** No new implementation starts while reviewed
  pieces wait to be merged. Keep stacks short: a piece starts from `dev`
  unless it truly needs an unmerged one.
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
3. Push `dev`. If the push is rejected because the other platform got there
   first: fetch, read what changed, merge, gate again. Never force.
4. Open the other platform's issue with the same milestone, post the
   closing comment (what landed, what was measured, which model did which
   review), close the issue, delete the branch.

A change to documents alone needs no gate; say so in the closing comment.

## What differs by platform

| | Mac | Windows |
|---|---|---|
| Never edit | `windows-app/` | `mac-app/` |
| The other side's work goes in | a `windows` issue | a `mac` issue |
| Gates | the mac suite, `verify.sh`, `verify-deploy.sh` | `dotnet test` judged by its totals line, `run-ui-tests.ps1`, `verify-deploy.ps1` |
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
  what waits on him. Detail goes in the issue's closing comment.
- When he reports a fault from hand-testing, reproduce or measure it before
  explaining it.
- When he is at the computer, nothing takes the screen, the keyboard focus
  or the speakers unless he has given them.
- Before a cut that changes the interface: the `ui-review` skill, then his
  smoke test from a short numbered script, and the cut only on his word.

## Limits

- A new finding becomes an issue with a milestone recommendation; it does
  not ride along in the piece that found it.
- End only processes the run started. His own Plantoir and his other
  sessions are his.
- Never read, print or commit a credential or a signing key. Never `gh auth
  switch`.
- Student names never enter the repository: run a counts-only check on what
  a piece adds before merging it, and never print a match.
- The interface never mentions the machinery (`CLAUDE.md` rule 1).

## State

A run outlives its context. Keep a running log in the scratchpad, keep
plans, briefs and reviews as files, and at each pause make sure the issues
and the milestone description say where things stand, because that is what
the next session, and the other platform, start from.
