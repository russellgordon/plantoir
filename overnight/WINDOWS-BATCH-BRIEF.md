# Brief for the Windows agent building the same overnight batch

Paste the section below to the Windows session. It is written to be
self-contained: it carries the DESIGN and the REASONS, not the bash, because
the reasons are the half that does not survive being re-derived.

---

The mac side has just built an overnight batch runner for its outstanding
handoff items — one Claude session per issue, unattended, overnight. You are
building the same thing for Windows. What follows is not "copy the script": it
is the set of decisions that shaped it and why each one was made, so you can
reach the same shape in PowerShell without paying for the same mistakes.
Where a decision is genuinely platform-bound, I say so and you should decide it
yourself.

## The shape

One PowerShell driver. A shared preamble file. One brief file per issue,
named `NN-slug.md`, where the slug IS the branch name (`issue/<slug>`). The
driver concatenates preamble + brief and runs `claude -p` once per issue, with
`--model opus` and permissions bypassed, sequentially.

Sequential, not parallel. Every issue branches off `dev`, so parallel sessions
would race on the same base and conflict on merge.

## The one decision most likely to be got wrong: who merges

**The driver merges, not the session.** The session commits, pushes its own
branch, and stops. The driver then runs the test suite ITSELF — independently
of anything the session claimed — and merges into `dev` only if that is green.

The reason is that every issue branches off `dev`. A session that merges broken
work poisons every issue after it, and by morning you are unpicking a dozen
branches instead of one. With the gate in the driver, a session cannot merge by
*claiming* success, and a bad session costs one branch rather than the night.
Push the branch either way, so nothing is ever lost; a refused merge is one
`git merge` away once a human has looked.

**Keep every branch, merged or not.** Russell wants them for stitching the
Windows and macOS work back together. Do not delete on merge, which is the
normal rule here.

## What each session is told to do

The preamble makes every session follow CLAUDE.md rule 11: plan, have **Fable**
review the plan adversarially, implement, have Fable review the implementation,
fix, have Fable review the fixes. Three reviews minimum. Brief the reviewer to
find where the work is wrong and tell it explicitly that "nothing to act on" is
acceptable, or it invents findings to justify itself. Tell the session to
VERIFY what a review claims rather than acting on it.

It also gets, in the preamble: it is on a branch already and must not create or
switch branches; it must not merge to `dev`; it must not touch the batch's own
directory; it must not drive the GUI (it steals focus and nobody is there to
put it back); write-ups are part of the work, not a follow-up; and the
documentation pass comes last.

## The status line — the only thing parsed

Every session must end its final message with exactly one of:

```
BATCH-RESULT: DONE — <what landed>
BATCH-RESULT: NO-CHANGE-NEEDED — <what you verified instead>
BATCH-RESULT: PROPOSED — <what you wrote up for a human to decide>
BATCH-RESULT: BLOCKED — <what stopped you>
```

The driver greps for that and records it beside its own verdict. Nothing else
in the output is parsed. Log the full stream to a file per issue and render the
assistant text out of it for a readable transcript.

## Ask Russell the decisions BEFORE the batch runs

This is the highest-value thing in the whole exercise and it is easy to skip.

Go through every issue and find the points where the session would have to make
a PRODUCT decision — what a teacher sees, what gets refused, which of two
defensible behaviours ships. Put those to Russell as concrete multiple-choice
questions with a recommendation, before you arm anything. Then write his answers
into the briefs **as instructions, with the options he rejected and the reason
each was rejected**, so the sessions record the reasoning for the other platform
instead of it being re-derived in a month.

On the mac this converted most of the "propose only" items into finished work.
The ones that survived as proposals were the ones where the answer genuinely
needed reading first — and those briefs say so, and tell the session to bring
back a recommendation with evidence rather than a guess.

Two rules that came out of it and are worth copying verbatim:

- **A session may not invent product behaviour unattended.** Where a brief is a
  decision rather than a defect, the deliverable is a written recommendation
  plus the contract case or handoff entry that makes it actionable — not a
  guessed behaviour shipped at 3am. Implement only the uncontroversially
  mechanical part, and label which is which.
- **New teacher-facing wording is allowed, on conditions.** It goes in
  `contracts/` so both platforms share one sentence; it follows the existing
  voice (rule 1 — no machinery words); and every new or changed sentence is
  listed verbatim in the session's final message so a human can read them
  together in the morning. Without this permission several issues stall short
  of finishing; with it, wording stays reviewable.

If an issue is too risky to do unattended, **drop it from the batch rather than
softening it**. One was dropped on the mac: a large mechanical reordering of a
4,586-line handoff file with no test behind it. The brief was kept in a
`skipped/` folder with a header saying why, for a session with somebody
watching.

## Things that cost real time, learned building it

- **Never edit the driver script while it is running.** Shells read a script
  incrementally by byte offset; editing it mid-run can corrupt execution. Add a
  new file instead.
- **Preflight and refuse early.** Dirty working tree, missing prerequisites,
  unreachable `origin` — all better as a refusal in ten seconds than a failure
  four hours in.
- **A per-session wall-clock ceiling.** A session that hangs must be killed,
  recorded as a timeout, and the batch must carry on. On the mac this needed a
  hand-rolled watchdog because macOS has no `timeout`; PowerShell has
  `Start-Job` / `Wait-Job -Timeout`, which is cleaner — use it.
- **Skip an issue whose branch already exists**, so a re-run resumes rather
  than colliding.
- **Refresh from `origin` before each issue**, so each one builds on the merges
  before it.

## A resume path, because some sessions will need a human

Build a companion script that picks one issue back up. Two things make it work:

1. **Check out that issue's branch BEFORE resuming the session.** The agent's
   memory is of a working tree on that branch; resuming while `dev` is checked
   out hands it files it does not recognise, and it reasons confidently about
   the wrong tree.
2. **Send an opening briefing carrying the three things it cannot know**: that
   the driver ran the suite independently after it finished and what the result
   was; whether its branch merged; and that `dev` has moved on since, so it
   must merge `origin/dev` in and re-test before trusting anything it
   remembers. That third point matters most — a stale mental model produces
   confident wrong conclusions rather than obvious errors.

Have the script ask which shape the work should take (finish it / fix the
failing tests / explain what blocked you / implement a decision I have now
made / recover from a timeout), defaulting to the likely one based on what was
recorded. Session ids are in the streamed log.

## What is yours to decide, because the mac cannot

- **The gate.** On the mac it is the unit suite. Yours is
  `dotnet test Plantoir.Tests\Plantoir.Tests.csproj`. Decide whether the
  solution build belongs in it too — it is the only thing that compiles
  `Plantoir.UiTests`, so without it those can rot unnoticed.
- **The UI tests are probably NOT in the overnight gate.** They need a desktop
  session and the foreground, take minutes each, and close a running Plantoir.
  Judge it, and say what you decided and why.
- **Stopping a running Plantoir.** You may close it without asking (standing
  instruction, 2026-08-18) and the build fails with `MSB3027 … file is locked
  by: "Plantoir"` if you do not. But a force-kill skips the app's own tidying:
  delete orphaned `*.lease` files and leave no `plantoir-mcp` running, or the
  next build fails with the same lock error for a different reason.
- **Rebuild at the end for `x64`** so Russell's "PT - Dev" shortcut runs it —
  a plain `dotnet build` does not write there. Leave it QUIT; relaunching
  steals focus and that launch is his.
- **`verify.sh` does not run on Windows.** If an issue touches the toolchain,
  the brief must say plainly that no automated gate covers it rather than
  implying coverage that does not exist.
- **The commit trailer** must name the agent that did the work. If you are an
  Antigravity or Gemini session, use `Co-Authored-By: Antigravity
  <noreply@google.com>` — never `antigravity@google.com`, which credits a
  stranger's account. Check `git config --get core.hooksPath` is `.githooks`;
  the hook that enforces this is committed but not installed by cloning.

## Where your issue list comes from

The mac's batch works `MAC-HANDOFF.md`'s open sections. Yours is
`WINDOWS-HANDOFF.md`'s numbered "What is still genuinely outstanding" list.

Before you build briefs from it, **audit it the way the mac's list was
audited** — the mac's list of five turned out to cover about a third of what
was actually open, because it had been assembled by reading the top of a long
file and stopping. Enumerate the section completely, check each claim against
the CODE rather than the prose, and rank by what a teacher would notice first.
Where the handoff and the code disagree, the code wins and the handoff gets
corrected as part of the work.

Expect to find items that are already done but never marked, and say so rather
than working them.
