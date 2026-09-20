---
title: The Helper Script
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Solo · launched in Unit 1 and handed over three classes later ·
> one short Python program, one named person, one page of notes · your
> first evidence that code can be useful to somebody who is not you

## What you are making

A script that saves **one real person** a small amount of **one
repeated chore**. Not an app. Not a menu system. A script — often
fifteen lines, sometimes fewer — that asks a question or two, does the
arithmetic or the checking that person currently does in their head,
and prints an answer they can use.

Your person is real and you must name them: a parent who works out how
much to buy, a coach who converts times, a sibling who is drilling
vocabulary, a neighbour who splits a bill four ways every month, the
teacher who runs the breakfast program. Ask them. Their words, not
your guesses, define what this does.

Here is a complete example of the right size, written for a teacher who
orders milk based on how many students ate breakfast:

```python
students = int(input("How many students ate today? "))
cartons = students * 2
if cartons > 48:
    print(f"Order {cartons} cartons — that is more than two cases.")
else:
    print(f"Order {cartons} cartons.")
```

That is genuinely small, and it is genuinely a pass — if the teacher
actually uses it. Ambition in this task is spent on *fit*, not on size.

## What must be in it

- **A named person** and, in one sentence, the chore in their words.
- **Input** typed by that person, **processing** you wrote, and
  **output** they can act on — the shape of every program you will
  build this semester.
- **At least one decision**: something the program handles differently
  depending on the answer.
- **Prompts a stranger could follow.** No `ENTER VAL:`. Ask a whole
  question, in whole words.
- **Comments and honest names**, so that the version of you who opens
  this file at the end of the course still knows what it does.

## How to work

1. Ask your person what they do now, step by step, and write it down
   before you imagine any solution. If you find yourself proposing an
   app in the first minute, start again.
2. Write the sentence: *[Name] does [what], and the annoying part is
   [what].* Bring it to class.
3. Start from the skeleton we build in class rather than an empty file:
   the input–process–output shape, with the thinking left to you.
   [[Starting from a Skeleton]]
4. Sketch the conversation on paper — what the program asks, in order,
   and what it says back. Two minutes with a pencil saves twenty at the
   keyboard.
5. Build the shortest thing that answers the question. Run it after
   every few lines rather than at the end.
6. Test it as a stranger: type a word where a number goes and see what
   happens. You are not expected to survive that yet, but you *are*
   expected to know it happens.
7. At the hand-off, a partner runs your script while you say nothing.
   Write down every hesitation. Fix exactly one.

## How this is assessed

The mark follows [[How Marks Work]]: the working period is part of the
task, so what I see you doing in class counts, and so does the trail
you leave in your [[Code Journal]]. Two entries are expected — one
after you talk to your person, one after the hand-off — and the second
one is where the marks actually are, because that is where you write
down what you watched somebody else struggle with.

## Success criteria

| Quality | What it looks like in your script |
| --- | --- |
| A real person served | Your notes name them and quote their chore |
| Input, process, output | The program asks, works, and answers |
| A decision that matters | Different answers produce different advice |
| Written for a stranger | Prompts are whole questions; output is plain |
| Readable at the end of the course | Names say what they hold; comments say why |
| Honest hand-off | You logged what your partner hesitated over |

## Reflect

Write a [[Code Journal]] entry after the hand-off. What did your
partner do that you did not predict? What did your person say that you
almost ignored? And the uncomfortable one: is there any chance this
script sits unused after today — and if so, what would have had to be
different?

> [!question]- If it feels too small to be worth marks
> That reaction is the actual subject of this task. The instinct to
> build something impressive is exactly what makes so much software
> useless — it optimises for the builder's pride rather than the user's
> Tuesday. A fifteen-line script that a real person opens twice a week
> is a better piece of engineering than a two-hundred-line menu system
> that nobody opens twice. Read [[Who Is This For]], then go make
> something small that gets used.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[B2.1]]

![[A2.2]]

![[B1.3]]

![[A4.2]]

![[C3.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 1, Day 18, the hand-off
  The task already sets this up: a partner runs the script while the
  owner says nothing. That silence is the measurement.
  Watch for: who reaches for the keyboard, and who writes down what
  their partner hesitated at. Both scripts may work; only one of these
  students has learned what the hand-off was for.
  Going well: pen moves while the partner struggles.
  Stuck: the owner narrates, or takes over.
  Record: three columns on your day plan — wrote, watched, took over.

TALK — Unit 1, Day 16, during the build from the skeleton
  Ask: "Which part of the skeleton did you keep, and which did you
  throw away?"
  Then: "What went wrong the first time you changed it?"
  A strong answer treats the skeleton as a decision rather than as
  scaffolding to be escaped. That is B2.1 — designing from a template —
  and a finished script that happens to match the skeleton tells you
  nothing about whether the student chose it or never left it.
  Record: one line each; two words is enough.

The product evidence is the script handed in on Day 18.
%%
