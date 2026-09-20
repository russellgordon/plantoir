---
title: What Makes a Model Good
publish: true
created: __CREATED__
tags:
  - discussions
---
At the boards, a group fits a line to six points and announces
$r^2 = 0.92$ — ninety-two percent of the variation explained, a
beautiful result. Then someone asks the model to predict three hours
of study, well past the largest value it ever saw, and it confidently
returns a mark of 120%. The line did nothing wrong. It answered
exactly the question it was built to answer, in a place it had no
right to be asked. Between "fits the data" and "tells the truth about
the world" runs the gap this conversation is about — and in a course
about data, that gap is wider and more consequential than in any
course before it, because the points are people.

Now make it real. A school district builds a model to flag students
at risk of not graduating, so that support can reach them early. The
model is 90% accurate. Should it be used? Every question that
matters is still unasked. Accurate at *what* — at catching the
students who struggle, or at not disturbing the ones who do not?
Those are different accuracies, they trade against each other, and
one of them is measured in missed help while the other is measured in
students told, at fifteen, that a computer expects them to fail.
Trained on *whom* — on the students the district has served before,
which encodes every way that district has ever succeeded or failed a
particular kind of student. A model trained on the past is a very
accurate machine for repeating it.

And notice what the model never has to be told. It does not need a
field for family income to find one: postal code, attendance
patterns, and which bus route you take will reconstruct it, because
in real data almost everything is a proxy for almost everything else.
That is why "we removed the sensitive columns" is not an answer, and
why a model can be built entirely from innocent-looking variables and
still sort people along a line nobody would defend out loud.

> [!warning] Data has people in it
> Every row in every dataset you touch this semester is a person who
> did not consent to being in your assignment. Some of them consented
> to nothing at all. Before you use a dataset, be able to say where
> it came from, what the people in it were told, and what could be
> re-identified by joining it to something else — because "anonymous"
> usually means "not obviously named", which is a much smaller
> promise than it sounds.

Questions worth arguing about:

1. What exactly has a high $r^2$ shown, and what has it not? Is
   "explains 92% of the variation" a claim about the world or a claim
   about the line?
2. The risk model above helps some students and labels others. Who
   should decide the trade — the district, the model's author, the
   families, the students? What would you need to know to have an
   opinion worth acting on?
3. A model trained on past decisions reproduces past decisions. Is
   that a bug to be patched, or is it what prediction *is*? If it is
   the second, what follows about where prediction should be
   allowed?
4. "We deleted the sensitive fields" and "the algorithm doesn't know
   your background" are things institutions actually say. Given
   proxies, are those statements false, misleading, or merely
   incomplete — and does the distinction matter to the person on the
   receiving end?
5. "All models are wrong, but some are useful." Prosecute or defend
   this claim — then decide who gets to be the judge of *useful*, and
   whether the people described by the model are in the room.

This stops being talk at [[The Statistical Claim Report]], where you
must say out loud where a real claim stops deserving belief, and at
[[The Culminating Investigation]], where the final section of your
report is not "conclusion" but *limitations* — who is missing from
your data, what your method could not rule out, and what would change
your mind. That section is where the mathematics grows up. The habit
of asking what a picture *claims* starts small, every morning, in
[[Graph Talks]].

%%curriculum-start%%
## Curriculum connection

![[B2.3]]

![[D2.2]]

![[E1.5]]
%%curriculum-end%%
