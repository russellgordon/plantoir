---
title: When Code Hurts
publish: true
created: __CREATED__
tags:
  - discussions
---
Nobody writes a line of code that says "work badly for these people."
Grade 11 looked at how the harm gets in anyway: the form that demands
a phone number, the colour-only interface, the name field that
rejects real names. Every one of those was a decision that treated a
group of people as an edge case, and every one was fixable in an
afternoon.

This year the multiplier arrives. The same three doors — data,
design, deployment — but now the program runs a million times a day,
makes the decision itself, and nobody is standing at the counter to
notice that something has gone wrong.

## What scale changes

A human clerk who misreads one form in fifty produces scattered
mistakes. A program that misreads the same category of form produces
the *same* mistake, every time, on the same category of person, until
somebody notices — and the people it lands on are, by definition, the
people who were not in the room when it was tested.

| | A person doing it | A program doing it |
| --- | --- | --- |
| Mistakes | Vary, and cluster around no one | Identical, and cluster around the same group |
| Appeal | Ask the person; they can hear you | Ask whoever still understands the code |
| Noticing | The clerk sees the confused face | Nobody sees anything; the log shows a success |
| Fixing | Explain it once | Find it, change it, test it, redeploy it |
| Volume | Hundreds a year | Millions a year, starting immediately |

The fourth row is why this discussion sits in the same course as
[[Who Maintains This]]. A harm you cannot find in the code is a harm
you cannot stop.

> [!important] Error messages are still where dignity lives or dies
> `INVALID INPUT` tells a user they are the problem. "Please type the
> number of hours using digits, like 12" tells them what to do next.
> That was true last year at the scale of one program and one person.
> At the scale of automation it decides whether a system is something
> people can use or something people are subjected to.

## Automation without a human in it

Three cases, none of them exotic, all of them running somewhere
right now:

- A system that flags accounts as suspicious and freezes them
  automatically. It is right most of the time. The people it is wrong
  about have no way to reach a human, because the whole point of the
  system was that no human had to look.
- A scheduling program that optimises a rota for cost. It is
  perfectly fair by its own measure and it gives the same three
  people every awkward shift, because the measure it was given never
  mentioned them.
- A model trained on records of past decisions. Every pattern in
  those decisions, including the ones nobody would defend out loud,
  is now a rule the program applies faithfully and at speed.

None of these is a crash. Each one runs exactly as written.

Questions worth arguing about:

1. Which of the three cases is most harmful, and to whom? Does
   "nobody meant it" change your answer — and should it matter to the
   person locked out?
2. If an automated system makes fewer mistakes on average than the
   humans it replaced, but its mistakes land on the same group every
   time, is it an improvement? Who gets to decide, and does the
   answer change if you are in that group?
3. Every automated decision should arguably come with a way to reach
   a person. What does that cost, who pays it, and what happens to
   the business case that justified the automation?
4. When a team ships something harmful, where does the
   responsibility actually sit: the programmer who wrote it, the
   reviewer who approved it, the manager who set the deadline, or
   the organisation that deployed it? Can it sit in more than one
   place at once?
5. You are on a team. A teammate's change works and you think it
   quietly disadvantages somebody. How do you say so in a review
   without making it about them? Write the actual sentence.
6. What can you do this term, in your own project? Name three
   habits — and be honest about which ones you skip when the deadline
   is close, because that is when they get skipped.

The habits have addresses. Honest interfaces and honest limits in
[[Writing Code Others Can Read]]. Tests that include the cases you
would rather not think about in [[Writing Tests]]. And the wider
professional picture, including what it means to be the person in the
room who says stop, in
[[Ethics, Security, and the Profession]]. Per [[Our Classroom Norms]],
we argue this with ideas and never at people. The point is to build
better, not to find villains.

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.2]]

![[D4.1]]
%%curriculum-end%%
