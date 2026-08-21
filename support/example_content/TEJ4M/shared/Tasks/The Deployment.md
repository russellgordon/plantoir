---
title: The Deployment
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Benches of two or three · six periods across Unit 4 · one working
> deployment, one purchasing recommendation, one handover package ·
> assessed on all four categories

## The brief

A small organisation — a clinic, a design studio, a community centre,
a machine shop — is replacing everything at once. They have a budget, a
mixed set of needs, and no technical staff. Your bench specifies, builds,
configures, secures, documents, and defends the whole deployment.

Grade 11 built a client a machine. This is the same discipline at the
scale where the decisions have consequences somebody else pays for.

## What you deliver

1. **A requirements document** derived from the brief, in the form
   [[Writing a Specification]] sets out — measurable, testable, and
   agreed before anything is bought.
2. **A purchasing recommendation** against the criteria in
   [[Buying, Recycling, and Responsibility]]: fitness, total cost of
   ownership, repairability, support window, supply-chain reporting, and
   end of life. Where the responsible choice costs more, say so and say
   why it is worth it.
3. **One machine built to that specification**, with the storage choice
   argued from [[Storage Systems and Arrays]] — including whether an
   array is justified and what it does *not* protect against.
4. **Firmware and system configuration**, per
   [[Firmware and System Optimisation]]: versions recorded, every
   setting you changed listed with one line saying what that setting
   actually does, and a before-and-after measurement for every
   optimisation you claim.
5. **The network**: cabled, addressed and proven end to end from the
   second machine, then documented per [[Addressing at Scale]] — what
   is static, what is reserved, what is dynamic, and where the subnet
   boundaries fall.
6. **At least three services**, configured as in
   [[Stand Up a Service]], with users, privileges, and a permission
   matrix tested row by row.
7. **The security position**, per [[Security by Design]]: what is
   allowed through, who holds administrative access, what is encrypted,
   and what you deliberately left out and why.
8. **A reuse and disposal plan** for the equipment being replaced: what
   is repaired, redeployed, donated, or recycled; how drives are wiped;
   and how each unit's destination is recorded.
9. **A handover package** a stranger can act on, to the standard in
   [[Writing Documentation Somebody Can Build From]].

## The defence

Fifteen minutes with the client — played by another bench and by me.
Expect: "why is this more expensive than the quote we were given?",
"what happens when a drive fails?", "who can see the staff folder?", and
"what do we do with the old machines?" Answer from your documentation,
and answer for **your own area** — the questions are sorted so that each
of you takes the ones about the part you wrote. A bench that has quietly
been one person doing everything finds that out here, and so do I.

## What is marked as yours

A bench of two or three cannot each build the whole deployment, and
nobody here receives a mark for work somebody else did. So the first
eight deliverables divide into three areas at launch, and you write
your area's pages yourself, under your own name:

- **The buy** — the requirements document, the purchasing
  recommendation, and the reuse and disposal plan.
- **The box** — the machine build, the storage argument, and the
  firmware and system configuration.
- **The network** — addressing, the services and the permission matrix,
  and the security position.

On a bench of two, one of you takes two areas and you say which at
launch. The handover package is assembled together and its cover page
names who wrote what. On the client day each of you answers the
client's questions about your own area — which is why an area you did
not do is an area you cannot bluff.

## Success criteria

All four kinds of thinking in [[How Marks Work]] are in play here, and
this is what each one looks like in what you hand over.

| Quality | What it looks like in the handover |
| --- | --- |
| Requirements before purchases | Every requirement is testable, and it was settled before anything was bought |
| A bill you can defend | Every line has a reason, and where the responsible choice cost more the figure is named |
| Consequences named on both sides | Who gains from this deployment and who pays for it, written down rather than implied |
| A machine that fits the requirement | Components and storage follow from the document, including what an array does not protect against |
| Measured, not asserted | Every optimisation has a before and an after in numbers, and every changed firmware setting has a line saying what it does |
| A network that runs, on a plan a stranger can follow | Proven end to end from the second machine; static, reserved and dynamic separated, boundaries drawn and reasoned |
| A matrix that was actually tested | Every row attempted from the second machine, with the exact refusal recorded |
| A security position with its limits | What is allowed, who holds administrative access, and what you left out on purpose |
| An end for the old equipment | Each unit's destination recorded, with the wipe standard and the record that it was done |
| A defence that answers the question | Answers point at your documentation, and "we did not do that" arrives before it is found |
| Your area, under your name | The deliverables you own, written by you, and defended by you on the client day |

> [!tip] The failure mode of this task
> Benches that build first and document last always run out of time and
> always lose marks in two categories at once. The requirements document
> is not a warm-up for the deployment; it is the deployment, written
> down before it exists.

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A2.2]]

![[A2.3]]

![[A4.3]]

![[A4.4]]

![[B1.1]]

![[B4.1]]

![[B2.1]]

![[B4.3]]

![[B4.4]]

![[C1.2]]

![[C2.1]]

![[C2.2]]

![[D2.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 4, Day 16, while benches configure services and test the
matrix
  This is the group task, so the thing to watch is whose hands are on
  the work. Not teamwork — that is reported separately and is none of
  the mark's business. Attribution: the network area is marked as one
  student's, and a signed page cannot tell you whether that student
  configured it or watched somebody else configure it while they wrote
  the page.
  Going well: the keyboard moves when the area changes, and the person
  whose area it is is the one being asked questions by the other two.
  Stuck: one driver for the whole period; or an owner who has to ask
  what the machine's address is.
  Record: initials of whoever was driving, twice in the period, twenty
  minutes apart. If the same initials come up in someone else's area
  both times, say so to that bench on the spot and again before the
  client defence on Day 18 — not after the areas have been marked.

TALK — Unit 4, Day 17, while benches finish the security position
  Ask: "Somebody here is leaving on Friday. Walk me through everything
  you would have to touch, in order, and then tell me the one you would
  forget."
  Then: "Which of your three services would you be least willing to
  restart at ten in the morning, and what would you want in place first?"
  A strong first answer goes past the login: group membership, folder
  ownership, the service account whose password that person also knows,
  and it names the item that appears on no list — which is B4.4 held as
  a live system rather than as a completed screen. A strong second
  answer knows which of their services has state or people attached, and
  asks for a backup or a verified restore before touching it.
  Record: one line per student, naming the item they said they would
  forget. Ninety seconds each.

The product evidence is the handover package and the client defence on
Day 18. Those arrive on their own.
%%
