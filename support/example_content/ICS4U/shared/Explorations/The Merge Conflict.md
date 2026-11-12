---
title: The Merge Conflict
publish: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
Today you are going to break something on purpose, in front of
everybody, and it is going to be fine.

Two people. One file. The same three lines. Both of you are right, both
of you commit, and then the two versions have to become one version.
The tool does not guess and it does not pick a winner. It stops, marks
the disagreement in the file, and hands it back to the humans — which
is the single most reassuring thing about version control and the thing
students most expect to be a disaster.

## The setup

Everyone starts from the same tiny file. It is the fee rule from the
music room program you met on the first day of this course.

```python
def fee_owing(days_out):
    if days_out <= 14:
        return 0.00
    return 0.25 * (days_out - 14)
```

Commit that, on a branch everyone shares. Then the two partners get
different instructions, and **do not show each other**.

- **Partner A** is told: the office wants the daily rate lowered to ten
  cents.
- **Partner B** is told: the treasurer wants the amount rounded to
  whole cents, because `0.7000000000000001` appeared on a printed
  notice last month.

Both changes are correct. Both changes are wanted. Both changes touch
the same line.

## What the tool says

Commit separately, then merge. This is what actually comes back:

```text wrap
Auto-merging signout.py
CONFLICT (content): Merge conflict in signout.py
Automatic merge failed; fix conflicts and then commit the result.
```

And this is what is now sitting in the file:

```text wrap
def fee_owing(days_out):
    if days_out <= 14:
        return 0.00
<<<<<<< HEAD
    return 0.10 * (days_out - 14)
=======
    return round(0.25 * (days_out - 14), 2)
>>>>>>> rounding
```

Read those markers slowly, because they are not damage and they are not
an error message. They are a sentence:

```text wrap
<<<<<<< HEAD        everything below this line is what YOU had
=======             the divider
>>>>>>> rounding    everything above this line came from that branch
```

The file is not broken. It has been annotated. Nothing has been lost:
both versions are right there, and the history still contains both
commits.

## The task

**Job one — produce the conflict.** Both partners, deliberately.
Nobody is allowed to avoid it by waiting for the other person. Follow
the mechanics in [[Using Version Control]].

**Job two — read it before you touch it.** Write down, in one sentence
each: what did A change, what did B change, and what does the merged
line have to do to satisfy both? Do this on paper, with the markers
still in the file.

**Job three — resolve it.** Delete the markers, leave one correct line,
run the function on 9, 21, and 15 days, and commit the resolution with
a message that says what you decided and why.

**Job four — do it again, worse.** Now both partners rename the same
variable to different names, in the same commit as an unrelated change.
Resolve that one too. Then say which of the two conflicts was harder
and what made it harder — it is almost never the number of lines.

## The count

1. How many people's first instinct was to delete one side entirely?
   Which side, and why that one?
2. Did anybody's resolution lose a change that somebody wanted? How
   would you have found out if the room had not been watching?
3. Job four was worse. Was it worse because of the tool, or because of
   how the two of you decided to commit?
4. What would have prevented the conflict entirely — and is preventing
   it always the right goal?

> [!note]- Facilitation notes
> **Cause the conflict on purpose, publicly, first.** Do the whole
> thing on the projector with one volunteer before pairs try it. The
> markers are frightening precisely once. After a room has watched a
> conflict get resolved calmly in ninety seconds, the fear is gone for
> the rest of the semester — and this is the single highest-value
> ninety seconds in Unit 4.
>
> **Timing in a 70-minute period.** Fifteen minutes on setup and the
> public demonstration. Fifteen on jobs one and two, with paper.
> Fifteen on job three. Fifteen on job four. Ten on the count.
>
> **Insist on paper for job two.** Students who resolve a conflict
> before they can state both sides in words are guessing, and they will
> guess on their project in three weeks when the stakes are a
> partner's data.
>
> **Both changes are wanted — that is the design.** A conflict where
> one side is obviously wrong teaches nothing except "pick the good
> one". Here the resolution has to *combine* two correct changes, and
> the room discovers that resolving is an act of authorship, not an act
> of choosing.
>
> **Talk about the tooling honestly.** Editors and hosting services put
> friendlier interfaces over all of this, and every one of them looks
> different and changes every year. The markers do not. Teach the
> markers; let students find whichever button their own setup offers.
>
> **The vocabulary should be real from today.** Commit, branch, merge,
> conflict, history, message. Do not soften it. Students who leave this
> course knowing what a commit is have something they can carry into
> any team, in any language, for the rest of their working lives.
>
> **The recovery line every student needs.** "A conflict cannot lose
> your work; the commits are still there." Say it, show it with the
> history, and say it again when somebody panics in week two of the
> project — because somebody will.

## What tends to surface

The first thing the room notices is that the tool's refusal is a
courtesy. A version control system that silently picked a winner would
be far more dangerous than one that stops and asks. Being interrupted
is the feature.

The second is social rather than technical. Job four is harder because
of how the two partners worked, not because of anything the tool did:
big commits that mix a rename with a real change, and two people
editing the same function at the same time without saying so. The fix
for most conflicts happens in conversation on Monday, not in the file
on Friday — which is the argument of [[Working in a Team]].

The third is about honesty in the history. A resolution commit whose
message says "fix conflict" tells the next person nothing. A message
that says which two changes were combined, and what was decided, is a
note to a colleague who has not been hired yet.

## Where this goes next

The vocabulary is collected in [[Version Control]] and the mechanics in
[[Using Version Control]]. Reading a change the way a reviewer does is
the routine [[Read the Diff]], and doing it to a teammate's real work,
with a protocol, is [[The Code Review]].

Everything here is load-bearing for [[The Software Project]], where the
history *is* the evidence of who contributed what. And the question of
who owns a file that four people wrote together is
[[Whose Code Is It]].

> [!note] The answer is not on this page
> The resolved line is not printed here — not the rate, not the
> rounding, not the combination. That is your pair's decision and your
> pair's commit message. If you want a hint, notice that both partners
> were asked for something the person who asked still wants after your
> merge.

%%curriculum-start%%
## Curriculum connection

![[B1.7]]

![[B2.1]]
%%curriculum-end%%
