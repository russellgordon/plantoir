---
title: Scatter Plot Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Scatter Plots and Trends]] — you first
plotted real data in class during [[Bungee Drop]] — and one reaches
back to [[Box Plots and Quartiles]], data's other big move.

## Questions

1. Before plotting: a scatter plot will show hours of sleep versus
   reaction time for thirty students. Predict the trend, and say why.
2. Plot these (storeys, stretch in cm) points: $(1, 42)$, $(2, 78)$,
   $(3, 121)$, $(4, 158)$, $(5, 202)$, $(6, 239)$. Describe the
   pattern, draw a line of best fit, predict the stretch for 8
   storeys — and say whether you would trust a prediction for 80.
3. In summer, ice cream sales and sunburn cases rise together. Does
   ice cream cause sunburn? Name the real explanation.
4. Two classes wrote the same quiz. Class A's box plot: minimum 4,
   quartiles 6, 7, 8, maximum 10; Class B's: minimum 2, quartiles 5,
   7, 9, maximum 10. Same median — compare spreads, defend a verdict.
5. **Find the error.** Kai draws the line of best fit exactly through
   the first and last points, ignoring the twenty-eight between.
   Why does that fail at what a best-fit line is for?
6. **Challenge.** Sketch a scatter plot where a line is a poor model
   but the variables are clearly related. What would fit better?
7. Each of these is a wondering rather than a question data could
   answer. Rewrite each as a question you could actually investigate,
   then list exactly what you would have to measure or record, from
   whom, and how many times: (a) "are phones bad for sleep?";
   (b) "is the bus unreliable?"; (c) "does the school recycle enough?"
8. For your rewritten question in 7(a), say which two variables go on
   which axis and why, what a single dot on that plot represents, and
   one thing you would *not* be able to conclude no matter how the
   plot turns out.
9. **Find the error.** A group writes: "Our question is *what is the
   average screen time in our class?* We will make a scatter plot of
   it." Explain why a scatter plot cannot answer that question as
   written, and give two repairs — one that keeps the question and
   changes the display, one that keeps the display and changes the
   question.

## Answers

> [!success]- Answer 1
> Likely *negative*: more sleep, faster (lower) reaction times.
> Predicting first makes the plot a test of your thinking.

> [!success]- Answer 2
> The points climb about 40 cm per storey in a nearly straight
> band — real data wobbles; a real trend shows through anyway. A line
> near $y = 40x$ predicts about $320$ cm at 8 storeys. At 80, trust
> fades: interpolation is borrowing; extrapolation is gambling.

> [!success]- Answer 3
> No — hot sunny weather drives both. A hidden third variable moving
> two others together is why correlation alone never proves
> causation. [[Who Does Data Serve]] pushes on deliberate misuse.

> [!success]- Answer 4
> Same median (7), different spreads: Class A's interquartile range
> is $8 - 6 = 2$; Class B's is $9 - 5 = 4$, with a lower minimum.
> Class A is more consistent; Class B has more strugglers *and* more
> high flyers. "Better" depends on what you value — say which, and why.

> [!success]- Answer 5
> A best-fit line balances the *whole cloud* — roughly as many points
> above as below, as close as possible overall. The endpoints are
> just two observations, often the flakiest. Kai ignored the rest.

> [!success]- Answer 6
> One good sketch: points rising steeply then flattening — height
> versus age. A curve fits better than any line; testing models
> against data is regression's job, and it returns in [[A Data Story]].

> [!success]- Answer 7
> The pattern in all three: a wondering names a *topic*; an investigable question names **two things, a population, and a period**.
>
> **(a)** "Among students in our class, is there a relationship between minutes of screen time in the hour before bed and minutes of sleep that night?" Record, for each student, on each of ten consecutive nights: screen minutes in the final hour before bed, and total sleep minutes. Ten nights, everyone in the class — one night is weather, ten nights is a habit.
>
> **(b)** "Over the next two weeks, how many minutes late is the 7:42 bus at our stop, and does lateness depend on the day of the week?" Record the scheduled time, the actual arrival time, and the weekday, every school day.
>
> **(c)** "What percentage of the material in our classroom bins is recyclable but placed in the waste bin?" Record, for one week, the mass of each bin's contents sorted into correctly-placed and misplaced. This one needs a definition before it needs a measurement: *recyclable* has to mean what the local program accepts, or the number means nothing.
>
> Notice that (c) drifted away from a scatter plot entirely, and that is fine. The question decides the display, never the other way round.

> [!success]- Answer 8
> **Axes:** screen minutes before bed on the horizontal, sleep minutes on the vertical — the convention is that the variable you suspect *explains* goes across, and the one you suspect *responds* goes up. It is a convention rather than a law, but readers expect it, and breaking it silently misleads them.
>
> **One dot:** one student, on one night. Not one student's average — averaging first would hide exactly the night-to-night variation the question is about, and would turn thirty students × ten nights into thirty dots instead of three hundred.
>
> **What you could not conclude, however the plot looks:** that screens *cause* poor sleep. Even a tight negative trend is consistent with a third thing driving both — a student with a heavy assignment load is on a screen late *and* sleeping less because of the assignment. The plot can establish that the two travel together in this class over these ten nights. Causation needs an experiment or knowledge from outside the graph, which is the argument in [[Who Does Data Serve]].

> [!success]- Answer 9
> **Why it cannot work:** a scatter plot displays a relationship between *two* variables, and "average screen time" is a summary of *one*. There is nothing to put on the second axis. A single dot on a scatter plot has to represent a case measured twice, and this question measures each case once.
>
> **Repair 1 — keep the question, change the display.** An average is a one-variable summary, so use a one-variable display: a box plot showing the median and the spread, as in [[Box Plots and Quartiles]], which also answers the more interesting version — *how much do we differ?* — that the average alone conceals.
>
> **Repair 2 — keep the display, change the question.** Make it a two-variable question: "is screen time related to hours of part-time work?" Now every student contributes two numbers, a dot has coordinates, and the scatter plot has something to show.
>
> The general lesson is worth more than either repair: **the question comes first and the display follows from it.** Choosing the graph you like and then bending the question to fit is how a project ends up with a beautiful plot that answers nothing anybody asked.

%%curriculum-start%%
## Curriculum connection

![[D1.2]]

![[D2.2]]

![[D1.3]]
%%curriculum-end%%
