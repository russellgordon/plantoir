---
title: Whose Code Is It
publish: true
created: __CREATED__
tags:
  - discussions
---
Almost nothing you write this year is entirely yours. A pattern from
a tutorial, a function a teammate wrote, a fix an AI assistant
suggested, a whole library somebody released for free — modern
software is assembled as much as it is authored, and that is not
cheating. It is the field. What separates a professional from a
plagiarist is not whether they used other people's work. It is
whether they said so, and whether they were allowed to.

## Four situations that look similar and are not

| Situation | The honest move |
| --- | --- |
| A teammate wrote the function you are editing | Their name stays in the history; your change is a separate commit with your name on it |
| You found a solution on a forum | Name the source in a comment, say which part you changed, and be able to explain every line |
| You used code released under a licence | Read the licence. Some require you to keep a notice; some require your project to be released the same way |
| An AI assistant generated a chunk | Say so in a comment, exactly as [[Our Classroom Norms]] requires, and take responsibility for testing it as if you had written it |

The fourth row is the one people argue about, so be clear about the
standard: the problem is never that you asked for help. The problem
is submitting code you cannot explain, or presenting somebody else's
thinking as your own. Both are visible from the outside — in a
review, in a viva, in the moment somebody asks "why does this line do
that?"

## Licences say what you may do

A licence is the author's answer to "what am I allowed to do with
this?" — and code with no licence at all is not a free-for-all; it is
the case where the author has said nothing, and the safe assumption
is that you may not simply take it. Broadly, permissive licences let
you use the work in almost anything provided you keep the notice, and
copyleft licences let you use it provided anything you build on it is
released on the same terms. Which family a project chose is a
decision with consequences for everybody downstream, and it is
usually stated in one file at the top of the project.[^licence]

> [!warning] "It was on the internet" is not a licence
> Public and free-to-take are different things. A photo, a dataset, a
> snippet, and a font all have owners, and a community partner who
> inherits your project inherits whatever you put in it — including
> anything you had no right to include. That is a problem you would
> be handing to somebody who cannot assess it.

Questions worth arguing about:

1. Where exactly is the line between learning from code and copying
   it? Try to state it as a rule somebody else could apply to your
   work without you present.
2. Your team's project has four authors and one repository. At the
   end, who owns it — the four of you, the school, the community
   partner, or nobody? Does it matter? What would you want the answer
   to be if you were the partner?
3. Somebody spends unpaid evenings maintaining a library that
   thousands of businesses depend on and earns nothing from it. Is
   that a healthy arrangement? What would a fairer one look like, and
   who would pay for it?
4. Is there a moral difference between using an AI assistant trained
   on public code and copying from a person's repository directly?
   Argue both ways, then say where you actually stand.
5. A teammate's commit contains a block you are fairly sure came from
   somewhere else, unattributed. What do you do — and what do you do
   *first*?
6. If you fix a bug in somebody's free software, do you owe them the
   fix? What does it cost you to send it back, and what does it cost
   everyone if nobody does?

The mechanics of credit — commits with your name on them, comments
that name a source, a project file that states the terms — are in
[[Using Version Control]] and [[Writing Code Others Can Read]]. The
companion argument, about what you owe the people who come after you
rather than the people who came before, is
[[What Happens When You Leave]].

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.2]]

![[D2.3]]
%%curriculum-end%%

[^licence]: Projects normally state their terms in a plain text file
    named `LICENSE` or `LICENCE` in the top folder, and often
    summarise it in the README. When your team publishes anything,
    deciding what goes in that file is a real decision with real
    consequences, not paperwork — and it is one your community
    partner may need explained to them in ordinary words.
