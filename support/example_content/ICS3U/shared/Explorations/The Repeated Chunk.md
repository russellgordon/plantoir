---
title: The Repeated Chunk
publish: true
codeRunner: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
A teacher-advisor prints a one-page progress slip for each student
before conferences: three terms and a final mark, each shown as a
number and a letter. She wrote the program herself, years ago, and it
works. You are inheriting it this morning.

Open the file. Here is the part that turns term one's mark into a
letter:

```python run
term1 = 78

if term1 >= 80:
    term1_letter = "A"
elif term1 >= 70:
    term1_letter = "B"
elif term1 >= 60:
    term1_letter = "C"
else:
    term1_letter = "R"

print(f"Term 1: {term1} ({term1_letter})")
```

Scroll down. The same eight lines of grading appear again for `term2`,
again for `term3`, and again for `final_mark`. Four copies, identical
except for the name of the mark being graded.

## The task

Two jobs, in this order, and no skipping ahead.

**Job one — read it.** Before touching anything, write down what the
program does, in your own words, in three sentences. Then predict its
output for a student with marks of 78, 64, 81, and 74. Run it and check
your prediction.

**Job two — the change request.** The advisor emails at 8:40am:

> The department moved the B cutoff. It is 72 now, not 70. Can you have
> it ready for period one?

Make the change. Time yourself. Then trade programs with another pair
and grade *their* change with a mark of exactly 71 in every position.

## The count

Hands up, honestly:

1. How many places did you have to edit?
2. How many pairs got all four? How many got three?
3. If the advisor asks tomorrow for a D band between C and R, how many
   edits is that — and how sure are you of your own number?

The pair that got three out of four did not make a careless mistake.
They made the mistake this program is *designed* to produce.

> [!note]- Facilitation notes
> **Hand it out broken-ready, not broken.** The starting program must
> work perfectly. The whole force of the day comes from a correct
> program becoming incorrect through an ordinary, reasonable change.
>
> **Timing in a 70-minute period.** Ten minutes to read and predict;
> ten for the change request, sprung at a moment when everyone is
> comfortable; ten to cross-grade with a mark of 71; ten on the count
> and the discussion below; the remaining half-hour to build a
> function together, from the room's own words, and to fold the four
> copies into one.
>
> **Plant the near-miss.** Include a fifth mark somewhere far down the
> file — a "mid-year estimate" printed in a summary section — with its
> own copy of the grading block. About a third of the class will miss
> it entirely. Do not point it out until the count; let the cross-grade
> at 71 find it.
>
> **The sentence to wait for.** "Can we not write it once and use it
> four times?" Put it on the board with the student's name. Everything
> after that is naming what they already asked for.
>
> **The pay-off to save for the end.** Once the grading lives in one
> place, ask for the D band. It is one edit, in one place, and it takes
> forty seconds in front of the whole room. That demonstration is worth
> more than any explanation of why functions exist.

## What tends to surface

The room usually starts by blaming itself — "I should have used find
and replace", "I should have been more careful". Push back on that. The
bug was not in anybody's attention span and it was not in any single
line of code. It was in having four copies at all. A program with four
copies of an idea has four chances to disagree with itself, and it will
take them.

The second discovery is about reading. Four near-identical blocks make
the program *look* long and feel complicated, when it actually contains
one small idea repeated. Programs that are honest about how many ideas
they contain are easier to change, which is the beginning of design
rather than merely coding.

## Where this goes next

What you invented this morning is named, with the same example, in
[[Functions]]. You will read and change somebody else's in
[[Writing Functions]] and drill the mechanics in [[Functions Practice]].
Once the thinking has names, whole programs can be built out of named
parts — [[Decomposition and Design]] — and a set of parts good enough
to reuse becomes your next task, [[The Toolbox]].

> [!note] The answer is not on this page
> The one-copy version is not printed here. Your class writes it, on
> the board, from the sentence somebody says out loud when the
> cross-grading reveals the miss. The syntax takes four minutes to
> learn; the reason it exists takes one very annoying email.

%%curriculum-start%%
## Curriculum connection

![[A3.2]]

![[B2.3]]
%%curriculum-end%%
