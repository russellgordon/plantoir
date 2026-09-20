---
title: The Engineering Review
publish: true
created: __CREATED__
tags:
  - tasks
  - final-evaluation
enableToc: true
---
> [!abstract] At a glance
> The last class of the course · demonstrate your capstone from
> [[The Engineering Design Project]], defend it against published
> questions, and give three other projects a real critique · handover
> packages in at the end

## What you are doing

Three things, in this order: you show that your device works, you answer
for the decisions inside it, and you give other people's work the kind
of attention you want yours to get.

The defence is the part that is new. Nobody is trying to catch you out —
every question is published below, and you have had them since the
design review in Unit 4. That is deliberate: a professional review is
not an ambush, it is a known standard applied consistently, and being
ready for it is a skill you can practise.

The critique is the part people underestimate. A room of engineers is
worth more than a room of admirers, and giving a useful criticism
kindly, in front of the person who did the work, is genuinely difficult.
We will all practise it today.

## The protocol

Each project gets fifteen minutes, in three parts.

1. **Demonstration, five minutes.** The device does its job in front of
   the room. You show one working run, one measured claim, and one
   honest failure mode — the thing you know it does badly, shown by
   you rather than found by somebody else.
2. **Defence, six minutes.** Three questions, chosen at the time: two
   from the design list below and one from the shorter consequence
   list, answered at your bench with your evidence within reach. "I
   don't know" is an acceptable answer exactly once, and only when
   followed by how you would find out.
3. **Critique, four minutes.** Two peers respond in the fixed form: one
   question, one commendation, one recommendation. In writing, signed,
   handed to the presenter.

## The questions you must be ready for

These are the whole list, both halves of it. Two of the design
questions and one of the consequence questions will be asked.

### The design questions

- What does this device do, in one sentence, and for whom?
- Which requirement was hardest to meet, and how do you know you met
  it?
- Take one component that carries real current: why that part, at that
  rating, and what margin did you leave?
- Show me a calculation you did before you built, and tell me how the
  measurement compared.
- What is the worst environment this device would survive, and what
  fails first past that point?
- What happens if somebody connects it backwards, or unplugs a sensor
  while it is running?
- Which part of this would you not trust in a year, and why that part?
- What did you cut, when did you decide, and what did the decision cost
  you?
- Where in your code would a stranger get lost, and what did you do
  about it?
- If I handed your package to another student, what is the first thing
  they would have to ask you?
- What would you do differently if you started again on Monday?
- What did you learn from a failure that you could not have learned any
  other way?

### The consequence questions

This device does not stop at the edge of the bench. One of these two
will be asked, and they are on the list for the same reason as the
others: so that you can prepare rather than be caught out.

- What is inside this that should never go in a bin, where does it
  actually go instead, and what would have to happen to any storage in
  it first?
- Who is better off because this exists, and who is worse off? Name one
  of each, and say what you would change to shrink the second.

Careers, and why a record is worth keeping current, are deliberately
not in this list. They are in the note below instead, so that every one
of you answers them rather than whoever happens to draw that question.

## Milestones

- [ ] **Handover package complete** before the period starts:
      schematic, code, build log, test results, known limitations.
- [ ] **Demonstration rehearsed** once with a timer, out loud.
- [ ] **One honest failure mode chosen**, and the way you will show it
      decided in advance.
- [ ] **Three critiques written and delivered**, in the fixed form, for
      three different projects.
- [ ] **Career and work-habit note**, one page at the front of your
      handover package, written in class on the portfolio day. Four
      short paragraphs, and everybody writes all four:
      1. Two of the work habits the Ontario Skills Passport lists —
         working safely, teamwork, reliability, organization, working
         independently, initiative, self-advocacy — what each actually
         means in this trade, and the dated entry, log page or commit
         in your own record that shows it.
      2. One essential skill from the same passport that this project
         made you use more than you expected, and where.
      3. The pathway you would take from here — apprenticeship,
         college, university, a certification — the job at the end of
         it, and the one thing on a real posting for that job you
         cannot do yet.
      4. Why keeping this record current matters more than being able
         to build the device again. One paragraph, your own reasoning,
         not mine.
- [ ] **[[Tech Journal]] in**, checked against [[Journal Checklist]],
      with [[Final Reflection]] attached.

## How it is assessed

The criteria table, weighted as [[How Marks Work]] sets out. The
demonstration and the defence are assessed together, because a working
device you cannot account for and an accounted-for device that does not
work are the same kind of incomplete.

Your critiques are assessed too, and they are worth real weight. A
recommendation that names a specific change and a reason outranks a
compliment every time. So does a question that the presenter had not
thought of — that is the most valuable thing one engineer gives another.

## Success criteria

| Quality | What it looks like on the day |
| --- | --- |
| A demonstration that shows the truth | Working run, measured claim, and a failure you chose to show |
| A defence built on evidence | Answers point at logs, traces, and calculations in reach |
| Decisions you can own | You can say why, not just what, including what you cut |
| Honest limits | The failure mode comes from you before it comes from the room |
| A usable handover | Schematic, code, log, results, and limits, all present |
| A package ready before the day | Complete when the period began, rather than assembled during it |
| Critique worth receiving | Specific, kind, and about the work rather than the person |
| An answer beyond the bench | The consequence question is answered with something specific — a material, a person, a place, a step — not a sentiment |
| A note with evidence, not adjectives | Two habits and an essential skill each pointed at a dated piece of your own record |
| A pathway you can name | A route, a job, the thing on that posting you cannot do yet, and why this record is worth keeping current |
| A journal that shows the year | Growth traceable from the first entry to this one |

> [!tip]- How to answer a question you were not expecting
> Say what you know, say what you do not, and say how you would find
> out — in that order, and out loud. "I measured the running current at
> $180\ \text{mA}$ and derated the switch to half its rating, but I did
> not measure the inrush, and I would put a sense resistor in the
> ground return to catch it" is a complete and professional answer. It
> is also better than a confident guess, because a reviewer's job is to
> find out what you actually know, and everybody in the room can tell
> the difference. This is the last thing this course asks of you, and
> it is the habit that will still be useful in ten years.

%%curriculum-start%%
## Curriculum connection

![[B2.2]]

![[D3.3]]

![[D3.4]]

![[D3.5]]

![[C2.1]]

![[C2.2]]

![[D3.1]]

![[C1.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

This is the final evaluation and you will be running the room on the
day, so neither prompt below points at it. Both gather their evidence
in the week before, which is also when it is still useful.

OBSERVE — Unit 4, Day 31, while benches are staged and defences
rehearsed
  By this day the agenda asks for nothing but rehearsal and staging, so
  anybody still assembling a package is behind rather than obedient —
  which is exactly why Day 27 is the wrong day to judge this on, since
  that agenda still asks for ten trials and a soldered board.
  Watch what is on the bench: a package a stranger could pick up, or a
  pile that will be sorted tomorrow morning. The folder handed in on
  Day 32 cannot tell you which of those it was, and the difference is
  precisely what paragraph one of the career and work-habit note
  claims about reliability and organization.
  Going well: a rehearsal running with a timer while the package sits
  finished beside it.
  Stuck: a soldering iron on, or a build log being written from memory.
  Record: one column on the class list, R for ready, A for assembling.
  One pass, and it is what tells you whether that paragraph is a
  description or a hope.

TALK — Unit 4, Day 28, while journals are open for the checklist
  Ask: "Which entry are you deliberately NOT going to use in your
  growth piece, and what makes it the wrong evidence?"
  Then: "Name the work habit you are about to claim in your note. Now
  tell me the week it was at its worst, and what you did about it."
  A strong first answer names a real entry and a real reason — it
  proves the wrong thing, it repeats an earlier one, the numbers in it
  were never checked — which means the student navigated the log rather
  than weighed it, and that is B2.2 tested the only way it can be. A
  strong second answer produces the counter-example the note will never
  contain: the fortnight the habit failed, and what changed after. That
  is the understanding half of D3.4, and a one-page note claiming two
  habits cannot give it to you.
  Record: the entry date and the habit they conceded, one line each.
  Ninety seconds a student, and it is the same room-walk as the
  checklist.

The product evidence is the demonstration, the three critiques, the
handover package with its note, and the journal, all on Day 32. Those
arrive on their own.
%%
