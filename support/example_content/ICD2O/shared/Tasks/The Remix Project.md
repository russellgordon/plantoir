---
title: The Remix Project
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Solo or pairs · six working periods · remixes demoed in a short
> class showcase during the final period · one changed program plus a
> before-and-after write-up that is yours alone

## What you are making

Most professional programming is not writing new code — it is reading
code someone else wrote and changing it, which is why
[[Debugging Is the Job]] is a discussion and not a complaint. This task
makes that real work official: start from any program in the Programs
folder and make it do something **meaningfully new**.

Most people start from [[The Text Adventure]] because it begs to be
extended, but [[Guess My Number]], [[Mad Libs]], [[The Dice Roller]],
[[The Password Checker]], and [[The Chatbot]] are all fair game.
"Meaningfully new" means new behaviour — a rule, a feature, an ability
the original did not have. New strings and renamed variables are a coat
of paint, not a remix.

You hand in the remixed program and a **before-and-after write-up**:
what the original did, what yours does, what you changed, and why.

If you work in a pair the program is shared, but the write-up is
**yours alone** — written separately, in your own words, naming which
changes were yours and which were your partner's. That write-up, and
what you say at the showcase, are what your own mark is built from;
there is no shared mark on this task. Two periods set time aside for
writing it — a slot mid-build and a longer one at the end — so nobody
ends up copying a partner's paragraphs at eleven at night. For a pair,
the three rows below that describe the program — meaningfully new,
still readable, an honest demo — are read against the changes your
write-up claims as yours, not against the file as a whole.

## How to work

1. Choose your base program and read it *completely* before touching
   it. Predict what each part does, [[Predict the Output]]-style, then
   run it and check. Annotate the parts that surprised you.
2. Plan the new behaviour in one sentence, and check the sentence with
   me — this is where "new coat of paint" gets caught early.
3. Change one small thing, run it, repeat — big-bang edits produce
   big-bang errors. When something breaks, and it will,
   [[Debugging Step by Step]] is the way through.
4. Write the before-and-after as you go, including what broke on the
   way; the detours are the most interesting part of the story.
5. Demo at the showcase: original behaviour first, then yours. Most of
   the remixing happens in the working periods, where a stall is
   something I can walk over to — [[How Marks Work]] explains why what
   I watch counts.

## Success criteria

| Quality | What it looks like in your remix |
| --- | --- |
| The original understood | Your write-up explains what the base program did |
| Meaningfully new | The remix does something the original could not do |
| Change with a reason | The write-up says why this change, not just what |
| Errors worked through | One error and its resolution appear in the story |
| Still readable | A stranger could find your changes and follow them |
| An honest demo | The showcase shows before and after, bugs included |
| Your own part named | The write-up says which changes were yours and which were your partner's |

## Reflect

Write a [[Dev Journal]] entry: what did reading someone else's code
teach you that writing your own had not? Name one choice the original
author made that you would have made differently — and one you plan to
steal for your own programs from now on.

> [!success]- If remixing feels like cheating (click to expand)
> It is the opposite — it is the profession. Every programmer you have
> heard of spends most days inside other people's code, and remixing a
> working program teaches you how programs are *organised*, which no
> amount of starting from blank files can. Read boldly; change bravely.

%%curriculum-start%%
## Curriculum connection

![[C3.1]]

![[C3.2]]

![[C2.6]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 3, Day 9, the paired workday on the base program
  Watch for: whether anybody reads the original before touching it.
  The write-up's "what the original did" paragraph can be reconstructed
  from the finished file on the last night, and reads identically
  either way. Day 7's mapping and Day 8's conference show you the same
  thing earlier; this is the last period where the answer can still
  change how somebody works.
  Going well: the navigator reads a block out loud and predicts what
  it does before the driver types anything; a pair scrolls up to a
  subprogram they are not editing.
  Stuck: the file is opened at the bottom and edited immediately, with
  no part of it read aloud before the first keystroke.
  Record: a tick beside each pair on your class list for reading first,
  and a circle round the ones who did not. The circles are who you sit
  with on Day 10.

TALK — Unit 3, Day 8, at the conference the agenda already schedules
  Ask: "If I deleted the subprogram you are not planning to touch,
  what would stop working?"
  Then: "Where in this file will your change break something that is
  nowhere near it?"
  Both are C3.1 heard out loud — analysing existing code for its
  components and outcomes — and neither can be answered from the part
  of the program the student has been living in. A strong first answer
  names the subprogram, what calls it, and what the caller would be
  left holding; a weak one says "nothing, I don't use it". A strong
  second answer names a shared variable, a file, or a value two parts
  both rely on — still C3.1, and the thing that turns a modification
  into a rewrite when nobody sees it coming.
  Record: one line each in your day plan, and circle anybody who
  answered "nothing" — that is the pair to visit first on Day 9.

The product evidence is the remixed program, your own before-and-after
write-up, and the Day 14 showcase.
%%
