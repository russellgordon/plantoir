---
title: Ethics, Security, and the Profession
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The hold-list program refuses a duplicate and tells the person at the
desk. Small, correct, kind. Now imagine the same rule running for
every library in a province, with nobody at the desk, deciding by
itself which requests are duplicates — and getting it wrong for people
whose names it does not handle well.

Nothing about the code changed. What changed was the number of people
it touches and the absence of anybody to appeal to. That is the
Grade 12 version of this conversation: not "is hacking bad", but what
follows from writing something that runs at scale, without you in the
room.

## Scale changes the question

A mistake in a program you wrote for one club advisor is a bug. The
same mistake in software used by ten thousand people is ten thousand
bad afternoons, and you will never meet any of them. Three
consequences worth taking seriously:

- **Errors are multiplied, not repeated.** A rule that mishandles one
  case in a thousand is invisible in testing with thirty rows and
  routine at a million.
- **Defaults are decisions.** Whatever your program does when nobody
  chooses is what will happen almost every time. A checkbox that
  starts ticked is a decision made on behalf of everyone who never
  looked.
- **Nobody can see inside.** The people affected cannot read your
  code. They experience its judgement as a fact about themselves —
  "the system says you are not registered".

## When software decides

Automation moves a judgement from a person who can be asked to a
program that cannot. Sometimes that is a straightforward improvement:
the machine is consistent, fast, and does not get tired at 4 p.m.
Sometimes it removes the one thing that made the process bearable —
somebody who could say "that rule was not meant for your situation".

Ask these before automating a judgement, and write the answers down:

1. **What happens when it is wrong?** Not *if*. Who is harmed, how
   badly, and how quickly can it be undone?
2. **Who can appeal, and to whom?** If the answer is "nobody", you
   have built a rule with no exceptions, which no human institution
   has ever managed to be fair with.
3. **Whose data trained the rule, and who is missing from it?** A
   program built from one group's data will work best for that group.
4. **Would you explain this decision to the person affected, in their
   presence?** If not, you already know something.

> [!important] The programmer is in the room
> "I only built what I was asked for" is a sentence with a long
> history and no defenders. You are the only person in the
> conversation who knows what the software can and cannot do — which
> makes saying so your job, early, while changing it is still cheap.
> That is the professional obligation, and it is why the discussion
> [[Should It Exist]] happens before a build, not after.

## Security is care for users, not paranoia

Security in this course is not about attackers in hoodies. It is about
the ordinary duty of care you owe people whose information is in your
program.

- **Collect less.** Data you do not have cannot be leaked, subpoenaed,
  or misused. Every program in this course stores a first name and the
  minimum beside it, on purpose — that decision is made once, in
  design, and [[Encapsulation]] is where it gets enforced.
- **Assume the file will travel.** A file of names *will* end up on a
  memory stick, in an email, or in a repository. Decide what goes in
  it knowing that — and note that version-control history is permanent
  even after you delete the file, as [[Version Control]] warns.
- **Never store a password you could read.** If your program can print
  a user's password, so can anybody who obtains the file. Real systems
  store a one-way transformation instead; you are not writing
  authentication this year, and knowing why it is hard is the point.
- **Validate input as care, not suspicion.** A program that crashes on
  an apostrophe in a surname is not secure; it is careless about
  people called O'Brien.[^names]
- **Least privilege.** Give each part of a program — and each person
  on a team — only the access it needs. It limits the damage from an
  ordinary mistake, which is far more common than an attack.

[^names]: Assumptions about names cause more real-world harm than
    almost any other kind of hidden rule: that everyone has exactly
    two, that they use only ASCII letters, that they never change.
    Every one of those has been coded into software that then told
    somebody they do not exist.

## Codes of ethics, and why a profession has one

Professional bodies — the ACM and the IEEE are the two the curriculum
names — publish codes of ethics for computing professionals. They
differ in wording but agree on the substance: contribute to society
and avoid harm, be honest about your work's limitations, respect
privacy and confidentiality, credit others' work, and take
responsibility for what you build.

Codes exist because software has a specific temptation attached to it.
The person who can write the program is usually the only person who
can tell whether it is doing something it should not — a backdoor, a
hidden logging line, code copied without credit. Nobody else in the
building can check. A profession that cannot be checked from outside
has to state its standards from inside, and hold itself to them.

Those standards translate directly into this classroom:
[[D2.3|the ethical practices expectation]] asks what you actually do
at home, at school, and at work — cite the code you borrowed, tell
your team when you broke the build, do not read data you were given
access to for another purpose, and do not ship a feature you would not
explain to the person it affects.

## Interdisciplinary computing and research frontiers

Modern computer science rarely works in isolation. The most significant
advances happen at the intersection of computing and other disciplines,
as documented in research published by professional bodies like the ACM
and IEEE:

- **Bioinformatics and genomics**: algorithms for sequence alignment,
  phylogenetic tree construction, and deep learning models for protein
  structure prediction (such as AlphaFold) have transformed molecular
  biology and drug discovery.
- **Climatology and earth systems**: high-performance numerical
  simulations, finite-element differential solvers, and carbon
  accounting pipelines enable predictive climate modelling across
  decades.
- **Health informatics and medical imaging**: diagnostic computer vision
  for radiographic scans, privacy-preserving federated learning across
  hospital networks, and real-time clinical telemetry processing.
- **Computational linguistics**: transformer architectures and natural
  language processing models that parse syntactic structures, perform
  multilingual machine translation, and model semantic representations.
- **Economics and mechanism design**: algorithmic game theory, auction
  theory for spectrum allocation, and market-clearing algorithms.

Investigating an emerging technology (`D3.2`) or interdisciplinary research
paper (`D4.1`) requires evaluating primary sources — distinguishing peer-reviewed
methodological rigor from vendor marketing.

## The profession you are joining

The people who write software are not only "programmers". Systems
analysts work out what an organisation actually needs; software
engineers design systems meant to last decades; data specialists,
security specialists, accessibility specialists, technical writers,
and researchers all build the same artefact from different sides. The
usual preparation is a university program in computer science or
software engineering, or a college program in computer programming or
information technology — and there are people doing excellent work who
arrived by other routes entirely.

What every one of those routes has in common is the thing this course
keeps insisting on: the work is done with other people, for other
people, and it outlives you. [[Who Maintains This]] and
[[What Happens When You Leave]] are the discussions where that lands
personally; [[The Handover]] is where you practise it.

Argue the hard cases in [[When Code Hurts]] and [[Whose Code Is It]],
bring one of them to [[Tech Headlines]] with the four questions above
in hand, and keep track of what you actually believe in your
[[Final Reflection]].

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.2]]

![[D2.3]]

![[D3.2]]

![[D4.1]]

![[D4.3]]
%%curriculum-end%%
