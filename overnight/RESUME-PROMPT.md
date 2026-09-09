# Prompts for resuming a batch session

Paste one of these into the session `overnight/resume.sh` opens. Fill the
`<angle brackets>`. The general one covers most cases; the variants below
change only the middle paragraph.

---

## The general one

> You are resuming after the overnight batch finished. You have your full
> context — your plan, the Fable reviews, and what you tried. Do not start
> over, and do not re-read everything: pick up where you stopped.
>
> Three things happened after your session ended that you do not know about.
>
> **One.** The batch driver ran the mac unit suite itself, independently of
> whatever you reported, and used it to decide whether to merge. Your result
> was `<MERGED | TESTS-FAILED | CONFLICT | NO-COMMITS | TIMEOUT>`. <For a red
> suite: the failures are in `overnight/logs/<NN-slug>.tests.log` — read that
> before theorising.>
>
> **Two.** Your branch `issue/<slug>` was pushed to origin either way, so your
> work is safe. <If not merged: `dev` was left untouched.>
>
> **Three.** Other issues ran after yours and some of them merged, so `dev` has
> moved on. Before you do anything else: `git fetch origin`, then merge
> `origin/dev` into your branch and resolve anything that conflicts. Do not
> rebase — the branch is already pushed. Then re-run the suite, because the
> tree you are looking at is not the tree you were working in.
>
> What I want from you now: `<finish the work | fix the failing tests | explain
> what blocked you and what you would need>`.
>
> The rules have not changed. CLAUDE.md still applies, the write-ups
> (`GUI-IMPROVEMENTS.md`, both handoffs, the activity trail, the documentation
> pass) are still part of the work, and any further chunk still gets an
> adversarial Fable review before you call it done. Commit and push your branch
> as you go. **Do not merge into `dev`** — that stays mine.
>
> Finish with the same `BATCH-RESULT:` line as before so I can scan it.

---

## If the tests failed

Replace the "What I want from you now" paragraph with:

> The suite is red and I have not looked at why. Read
> `overnight/logs/<NN-slug>.tests.log`, find the actual cause, and fix it.
> If the failure is in code you did not touch, say so plainly rather than
> fixing around it — it may belong to an issue that merged after yours, and I
> would rather know that than have it papered over. **Do not weaken or delete
> an assertion to get green.** If the honest answer is that your change is
> wrong, say that; reverting is a fine outcome.

---

## If it reported PROPOSED and you now want it built

> You wrote this up as a proposal rather than implementing it, which was what
> the brief told you to do. I have read it and I am choosing:
> `<the decision, in your own words>`.
>
> Implement that now. Keep the reasoning you already wrote — including the
> options you rejected — and record my decision alongside it in the handoff, so
> the next person sees what was chosen and what was not. Where your proposal
> and my decision differ, mine is what ships, but say so if you think I have
> missed something: I would rather hear it now than find it in a teacher's
> course.

---

## If it timed out mid-flight

> You were killed by the batch's 90-minute ceiling, so your last few steps may
> be half-finished. Before continuing, work out what state you actually left
> things in: `git status`, `git log --oneline dev..HEAD`, and a look at the
> files you were editing. Tell me what is complete, what is half-done, and what
> you had not started — then finish it. If the work is genuinely too large for
> one session, say so and propose where to cut it rather than rushing.

---

## If it was blocked

> You stopped and reported `BLOCKED: <reason>`. <Answer to whatever blocked it.>
> Carry on from there. If anything else is unclear, ask me now rather than
> guessing — I am at the keyboard this time, which you did not have overnight.

---

## If you would rather start clean

A session whose context was exhausted, rather than merely stopped, is often
worse to resume than to restart: it will spend its first turns re-deriving what
it already tried and may repeat a dead end. The exact brief it was given is
kept, so a fresh session with the same job is one line:

```bash
claude "$(cat overnight/logs/<NN-slug>.prompt.md)"
```

Add to that: "A previous session attempted this and its work is on
`issue/<slug>`, which is checked out. Read the diff against `dev` before
planning — some of it may be worth keeping."
