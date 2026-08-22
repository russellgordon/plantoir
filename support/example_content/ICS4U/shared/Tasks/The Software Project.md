---
title: The Software Project
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Teams of three or four · launched Unit 3, Day 8 and running underneath
> every class of Unit 4 · a real community partner, a version-controlled
> team build, reviewed code, and a handover package somebody else can
> act on · the culminating project of this course

## What you are making

Software for **a real community partner**, built by a team, using
version control, reviewed before it lands, documented for the person
who comes after you, and handed over so it survives your graduation.

Last year, in ICS3U, one student built one small thing for one client.
This year the escalation is not size — it is that **nobody on your team
can hold the whole program in their head**, and that is the point. You
will read code your teammate wrote this morning, disagree about a
design, resolve a merge conflict, review work you did not write, and
hand the result to somebody who was not in the room for any of it.

Your partner is a person or a small organisation who can talk to you
more than once: a teacher who runs a club, a coach, a librarian, an
office administrator, a community garden, a food programme, a
neighbourhood association, a small business somebody's family runs.
Not "students in general". Not the school as an abstraction. Not
hypothetical.

The bar is unchanged from last year and it is still the only bar that
matters: **a month after handover, is it still being used?**

## Your team

Three or four people. Everyone writes code — there are no
non-programming roles in this course — but each person also owns one
responsibility, named in writing, that they answer for:

| Role | Answers for |
| --- | --- |
| Partner liaison | Every conversation with the partner, and consent |
| Integration lead | The shared branch stays working; merges get resolved |
| Test lead | The testing plan exists and somebody ran it |
| Documentation lead | The handover package is real and readable |

Rotate them if you like, but write down when you rotated. Roles are not
a hierarchy: the integration lead does not approve their own code, and
the partner liaison does not get to promise features the team has not
agreed to.

Disagreement is expected and has a protocol — see [[Working in a Team]]
and use it before the argument becomes about people.

## Consent, privacy, and honest scope

This is the craft, not the paperwork.

- **Consent to be named**, in your documentation and at the handover.
  If your partner says no, they are "a community garden coordinator"
  in everything you write, permanently.
- **Consent for the time.** Name the cost in minutes — one interview,
  one testing session, one handover — and keep to it.
- **Collect nothing you do not need.** Initials instead of names, a
  count instead of a list of people. Every field you do not store is a
  risk you did not create.
- **Never collect** contact details, marks, health or financial
  information, or anything about a third party who is not in the
  conversation. If the problem seems to require it, change the design,
  not the rule.
- **Say where the data lives**, what is in it, how to back it up, and
  how to delete it. Your partner must be able to delete it without you.
- **They can stop**, at any point, including after the handover.
- **Name your core**: the one feature that, if nothing else worked,
  would still be worth your partner's time. Build that first, finish
  it, and keep a "deliberately not doing" list from the first week. An
  item you can defend is a decision. An item quietly attempted and
  abandoned is a mess.

## Your team's code of practice

Before any code is written, your team writes **one page** setting out
how you will work and what you will not do. It is not decoration: at
the handover, your partner is told it exists and what is in it.

Ground it in a real professional code — the ACM Code of Ethics and
Professional Conduct, the IEEE Code of Ethics, or the Canadian
Information Processing Society's — and say which one you drew from.
Read the actual document; do not summarise a summary. Your page has
four parts:

1. **What we owe the person we are building for**: honesty about what
   the software does and does not do, and about when we are behind.
2. **What we owe people who are not in the room**: anybody whose data
   passes through this, anybody affected by a decision it makes.
3. **What we will not do**, specifically, even if asked.
4. **Why a profession needs a written code at all** — in your own
   words, two or three sentences. Engineers, doctors, and lawyers have
   one for reasons; programmers now build systems with comparable
   reach and, in most jurisdictions, no licence at all.

Then apply it. When a decision in the build runs into the page — a
shortcut that would collect one extra field, a demo that would overstate
what works — record the decision and what you did. Those records are
marked. A code nobody consulted is a code nobody wrote.

## Milestones

Checked in class, on the day named. Nothing here is a final-week
scramble; a project that reaches Unit 4, Day 9 without a working core
is a project I will help you cut down, not one you should rescue by
staying up.

- [ ] **Unit 3, Day 8 — launched.** Two possible partners per team,
      each with the problem in their own words.
- [ ] **Unit 3, Day 12 — partner, roles, and algorithms agreed.** One
      confirmed partner; roles posted in writing; your search and sort
      choices defended out loud with their costs.
- [ ] **Unit 3, Day 13 — interviewed, with consent and scope in
      writing.** The problem in your partner's own words, their consent
      recorded, and the scope document submitted with its "deliberately
      not doing" list.
- [ ] **Unit 3, Day 16 — the walking skeleton runs**, badly, end to
      end, on invented data — or you say plainly what stopped it.
- [ ] **Unit 4, Day 1 — version control running.** Repository set up,
      at least one commit from every member, and one conflict already
      resolved on purpose.
- [ ] **Unit 4, Day 2 — building on branches.** First feature branch
      open with readable work on it and commit messages a stranger
      could act on.
- [ ] **Unit 4, Day 3 — testing plan, and tests you did not author.**
      Written plan naming who tests what, plus tests over code another
      teammate wrote.
- [ ] **Unit 4, Day 5 — reviewed.** Every member has reviewed a
      teammate's code and had their own reviewed, using the protocol in
      [[The Code Review]]; agreements recorded in the history.
- [ ] **Unit 4, Day 9 — tested by your partner**, in the room, with
      your hands off the keyboard, and what you saw triaged into
      defect, request, or misunderstanding.
- [ ] **Unit 4, Day 11 — feature freeze.** Defects fixed, every test
      re-run. Only repairs and writing after this.
- [ ] **Unit 4, Day 15 — privacy statement**, drafted in that day's
      build period and finished for Day 16's review: what it stores,
      where, and how your partner deletes it, in their language.
- [ ] **Unit 4, Day 16 — reviewed by another team**, against your code
      of practice as well as your code, and the top three comments
      acted on in the same period.
- [ ] **Unit 4, Day 18 — handover rehearsed** on a team who play your
      partner, and whatever they could not follow repaired.
- [ ] **Unit 4, Day 19 — documented and submitted.** Final build, and
      the handover package complete.
- [ ] **Unit 4, Day 20 — handed over.** Your partner runs it in front
      of the room at [[The Handover]] and takes it home.

## The handover package

"Handed over" means your partner can use it next month without you, and
somebody else can change it next year without you. That takes more than
a folder of files. The full contents, and the standard they are judged
against, are set out in [[The Handover]] — read it in Unit 4, Day 1,
not in Unit 4, Day 19.

## How your individual contribution is evidenced

A team mark alone would be a lie about who did what. Your individual
work is assessed from four sources, all of which you create as you go
and none of which can be manufactured at the end:

1. **The history.** Your commits, with messages that say what changed
   and why. A hundred commits saying "update" evidence nothing. This is
   also why the repository must be running from Unit 4, Day 1 — a
   history that begins the night before the deadline documents exactly
   that.
2. **Your review comments.** What you asked of teammates' code, and
   what changed because you asked. Reviewing well is contribution.
3. **Your [[Code Journal]].** An entry at every milestone, including
   the honest ones: what you got wrong, what you rewrote, what you
   argued for and lost. Per [[Journal Checklist]].
4. **Your role.** What you answered for, and whether it held.

Per [[How Marks Work]], the working periods are where two of the three
kinds of evidence come from: what I watch you do, and what you tell me
at the milestone check-ins. This project is judged across five weeks,
not on the last day. [[Judging Your Own Work]] is how you read the
table below before I do — Unit 3, Day 18 is the period set aside for
it, and Days 20 and 21 are where the two rows it names get fixed.

## Success criteria

| Quality | What it looks like in your project |
| --- | --- |
| A real partner | Named or deliberately anonymised, consenting, met twice |
| Their problem, their words | The agreed sentence is theirs, confirmed |
| Honest scope | Finished core plus a defended "not doing" list |
| Defended algorithms | Choices stated with their costs, not copied |
| Version control as practice | Branches, real messages, conflicts resolved |
| Reviewed before merged | Every member reviews and is reviewed |
| Tested, including inherited code | A plan, plus tests over others' work |
| Privacy as craft | Nothing collected that was not needed and agreed |
| A real handover | Package complete and in your partner's hands |
| Visible individual work | History, reviews, and journal all agree |

## Reflect

Two questions, in your [[Final Reflection]]. First: what did your team
build that your partner did not need, and at what point could you have
known? Second — the question this course has been circling since the
first morning, when you were handed a program nobody in the room had
written — what did your team do so that the person who inherits this
does not have the day you had? Then read
[[What Happens When You Leave]] and answer it honestly.

> [!question]- If your team is stuck, at any stage
> Three failures account for nearly all of them. **No partner by
> Unit 3, Day 12**: come to me, I keep a list of people in this
> building and the neighbourhood who have already said yes. **The team
> has stopped talking**: run the disagreement protocol in
> [[Working in a Team]] in a working period, with me present if you
> want. **The scope is too
> big**, which shows up as three half-features and no working core: cut
> it in the working period, tell your partner what they will and will
> not be getting, and finish the smaller thing properly. All three are
> ordinary and all three are recoverable — in week two. In week five,
> only the third one is.

%%curriculum-start%%
## Curriculum connection

![[B1.1]]

![[B1.2]]

![[B1.3]]

![[B1.4]]

![[B1.5]]

![[B1.7]]

![[B2.1]]

![[B2.2]]

![[B2.3]]

![[A4.4]]

![[D2.1]]

![[D2.2]]

![[D2.3]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

This task self-reports more than any other in the course: the history,
the reviews and the journal are all evidence a student creates. Do not
duplicate them. What follows is the one thing none of them records.

OBSERVE — Unit 4, Day 4, the branch-and-merge working period, and
again at Unit 4, Day 14
  Watch for: who is deciding. The history records who typed a line and
  who merged it. It cannot record who was asked what the line should
  be, and on a team of four those are regularly different people — a
  student with a modest commit count can be the one every design
  question gets put to, and their commits alone will undersell them
  badly.
  Going well: a fork in the road argued out loud, then written into a
  branch name, a commit message, or the board.
  Stuck: one person at the keyboard and three watching; or four people
  building four things nobody agreed on.
  Record: one row per team on the day plan, with the initials of
  whoever the questions were addressed to. Doing it twice, ten classes
  apart, is the point — where that changes, you have found either a
  team that matured or a student who stopped being consulted.
  That is B2.1, contributing as a team member to the planning and the
  development, and it corroborates the commit history instead of
  repeating it.

TALK — Unit 4, Day 6, at the conference already on that agenda
  The agenda invites each team to bring one decision they want a
  second opinion on, so take that first and then keep going.
  Ask: "What is on your deliberately-not-doing list that your partner
  still does not know about?"
  Then: "When does that conversation happen, and which of you is
  having it?"
  A strong answer names an item, names the person who will say it, and
  names a date before the handover. A weak one is a promise to tell
  them at the end, which is how a partner finds out on Day 20 in front
  of an audience. That is B1.2 — developing the software so that it
  actually meets the end user's needs within the time available —
  heard as an intention while there is still time to keep it, rather
  than read afterwards in a scope document that was written in Unit 3.
  Record: one line per team on the conference sheet, with the date
  they named. Check it on Day 14.

The product evidence is the repository, the reviews, the journal, and
the final build submitted on Day 19.
%%
