---
title: The Buffer Design
publish: true
created: __CREATED__
enableToc: true
tags:
  - chemistry
  - equilibrium
  - task
---
Add one drop of dilute acid to a beaker of distilled water and the pH
falls off a cliff. Add the same drop to a well-designed buffer and it
barely moves.

Nothing has been neutralised. Nothing has been removed. The acid is
still in there. What has changed is that the solution had a reservoir
ready, and an equilibrium sitting in the middle of its range with room to
move in both directions.

You are going to design one, on paper, to a pH **you** specify. Then you
are going to make it and find out whether it does what you said it
would.

## The situation

A great many things only work inside a narrow band of pH, and outside it
they fail — sometimes gradually, sometimes all at once.

A freshwater aquarium. A shampoo that has to match skin. A cell culture
medium. A swimming pool. An electroplating bath. A medication that has to
stay stable in the bottle and dissolve in the right place. In every case
somebody specified a pH, and somebody else had to make a solution that
would hold it while things were added to it.

**Pick one of those contexts, or bring me another.** Your target pH has
to come from that context and has to be defensible — you will be asked
where the number came from.

## Who it is for

Write your Parts 1 and 2 as a **specification sheet** for whoever is
going to make and use this solution. They need to know what to weigh
out, what to dissolve it in, what pH to expect, how much abuse it will
take before it stops working, and what to do when it does.

They do not need a lecture on equilibrium. They need the number, the
recipe, and the honest limits.

## Who does what

You work in **pairs** at the bench — a titration wants one person on the
tap and one on the probe, and a buffer challenge run against a water
control at the same time wants four hands.

**Everything on paper is yours alone.** One buffer is made and one set
of readings is taken, and the two of you may hand in the same numbers.
Your specification sheet, your prediction with its working, and your
account of the gap between predicted and measured are written by you,
and they are what your mark rests on. Two identical analyses are one
analysis handed in twice, and I will treat them that way.

## Part 1 — The design

**a) State your target pH**, to two decimal places, and say where the
number came from. A range is acceptable if the context has one; give the
range and then pick a point inside it to aim at.

**b) Choose a conjugate acid–base pair** from the school's stock:

| Weak acid | Its conjugate base | Where to find its $K_a$ |
| --- | --- | --- |
| Ethanoic acid | Sodium ethanoate | Data booklet |
| Sodium dihydrogen phosphate | Disodium hydrogen phosphate | Data booklet, second ionisation of phosphoric acid |
| Ammonium chloride | Aqueous ammonia | Data booklet — you will need $K_a$ of the ammonium ion |
| Sodium hydrogen carbonate | Sodium carbonate | Data booklet, second ionisation of carbonic acid |

**Work out $\text{p}K_a$ for each pair yourself** from the booklet, and
put them in a table. Then justify your choice with the rule that
matters:

> A buffer works best when $\text{p}K_a$ is **close to the target pH** —
> within about one unit. That is where both members of the pair are
> present in comparable amounts, so the solution has a reservoir to
> absorb added acid **and** a reservoir to absorb added base. Push the
> ratio far from 1 and one of those reservoirs runs low, and the buffer
> becomes lopsided long before it fails outright.

Say why you rejected the other three. "Its $\text{p}K_a$ is 2.5 units
above my target, so I would need a ratio of about 300 to 1 and the
solution would have almost no capacity against added base" is the shape
of the answer.

**c) Calculate the ratio** you need, using the
Henderson–Hasselbalch equation:

$$\text{pH} = \text{p}K_a + \log\frac{[\ce{A-}]}{[\ce{HA}]}$$

> [!example]- The shape of the calculation, with illustrative numbers
> These are not your numbers and the $K_a$ is not from any particular
> booklet — the point is the route.
>
> Suppose the target is pH 5.00 and the chosen pair has
> $K_a = 1.8 \times 10^{-5}$.
>
> $\text{p}K_a = -\log(1.8 \times 10^{-5}) = 4.74$
>
> $5.00 = 4.74 + \log\frac{[\ce{A-}]}{[\ce{HA}]}$
>
> $\log\frac{[\ce{A-}]}{[\ce{HA}]} = 0.26 \quad \Rightarrow \quad \frac{[\ce{A-}]}{[\ce{HA}]} = 10^{0.26} = 1.8$
>
> So the conjugate base has to be present at about **1.8 times** the
> concentration of the weak acid. Notice how close to 1 that ratio is
> for a target only a quarter of a unit above $\text{p}K_a$ — and notice
> what it would have to be for a target two units above. That is the
> whole argument for choosing a pair whose $\text{p}K_a$ is near your
> target.
>
> Then turn the ratio into a recipe. Choose a **total** concentration
> — a few tenths of a mole per litre is sensible for a school buffer,
> and you should be able to say why more capacity costs more reagent —
> split it in the ratio above, and convert each concentration into a
> mass or a volume you can actually measure out.

**d) Produce the recipe.** Masses to the resolution of the balance,
volumes to the resolution of the glassware, and a stated total volume.
Somebody should be able to follow it without asking you a question.

## Part 2 — The prediction, written before you make anything

Four numbers, committed in advance and dated:

1. **The pH of your buffer as prepared.** You calculated it; now predict
   what the probe will read, and say how far off you would accept before
   you concluded something was wrong.
2. **The pH after adding a stated small amount of strong acid** — decide
   the amount and the concentration now, and keep it the same for
   part 3. Show the calculation: how many moles of $\ce{H3O+}$
   you are adding, which member of the pair absorbs it, what the new
   ratio is, and what pH that gives.
3. **The pH after adding the same amount of strong base**, by the same
   route.
4. **The same three numbers for an equal volume of distilled water**,
   which is your control. This is the comparison that shows what the
   buffer bought you, and it is the one people forget to plan.

## Part 3 — Make it and test it

**a) Titrate to confirm what you actually have.** Take a sample of your
weak acid solution and titrate it against standardised sodium hydroxide,
recording pH against volume added. From that curve, report:

- **The equivalence point volume**, and the concentration of the weak
  acid it implies. Compare with the concentration you thought you had.
- **The pH at the equivalence point.** Say whether it is above, below,
  or at 7, and explain that from what is in the flask at that moment.
- **The pH at the half-equivalence point**, which is $\text{p}K_a$ read
  straight off the graph. Compare with the booklet value you designed
  with. If they disagree, that disagreement propagates into everything
  else you predicted, and saying so is worth a great deal.

**b) Make the buffer** to your recipe.

**c) Measure and challenge it.** Calibrate the probe first and record
which standards you calibrated against. Measure the fresh buffer, then
add your stated portion of strong acid and measure again, then repeat
with strong base on a fresh sample. Run the identical challenge on
distilled water alongside, in identical glassware, at the same time.

**d) Find the limit.** Keep adding acid in measured portions to one
sample until the pH breaks away and starts moving quickly. Record the
total amount added at that point. **That number is your buffer
capacity**, measured rather than asserted, and it is the most useful
line on your specification sheet.

> [!danger] Sodium hydroxide, ammonia, and one combination that is never made
> - **Sodium hydroxide is the reagent that does not warn you.** Dilute
>   acid stings, so a splash announces itself. Sodium hydroxide feels
>   soapy or slippery instead — that sensation is the solution attacking
>   the fats in your skin — and it keeps working while it does not hurt.
>   A base burn of the same strength penetrates **deeper** than an acid
>   burn, precisely because nothing made you pull away. **Rinse any
>   suspected contact for at least 15 minutes under running water**,
>   whether or not it hurts, and tell me. In an eye it is an emergency:
>   eyewash at once, hold the lid open, and somebody else comes for me
>   while you stay at the eyewash.
> - **Fill the buret below eye level.** Take it out of the stand or
>   lower the stand, and use a funnel. Filling a buret above your head
>   means pouring sodium hydroxide over your own face if the funnel
>   slips, and it is entirely avoidable.
> - **Add acid to water, never water to acid.** Every dilution you do
>   for this task follows that rule. The heat has somewhere to go when
>   the water is already there; poured the other way it concentrates in
>   a few drops that can boil and spit acid back at you.
> - **If you choose the ammonia pair, it is used in the fume hood.**
>   Ammonia solution gives off a pungent, irritating vapour that goes
>   for your eyes and airways. **Waft, never sniff**, keep the bottle
>   closed between uses, and tell me if you can smell it strongly at
>   your bench.
> - **Nothing containing ammonia goes anywhere near anything containing
>   hypochlorite**, and no bleach or household product of any kind comes
>   into this room. Those two make a toxic gas, immediately, with no
>   warning — which is the concrete reason behind the standing rule that
>   you **combine only what your approved procedure lists**. The rule is
>   absolute rather than a matter of judgement because there is no way
>   to tell by looking.
> - **School reagents only, at the concentrations supplied.** Nothing
>   from home, no concentrated acids or bases, and no substituting a
>   stronger reagent because your buffer resisted.
> - **Eye protection from the first move to the last of the cleanup.**
>   Hair back, sleeves secured, closed-toe shoes.
> - **Never pipette by mouth.** Bulb or pump, every liquid, every time.
> - **The pH probe is fragile and expensive.** It is rinsed with
>   distilled water between solutions, never wiped hard, never used as a
>   stirring rod, and it goes back into its storage solution.
> - **Nothing returns to a stock bottle. Nothing is tasted.** Check the
>   pH of your waste before disposal and follow the route I give you —
>   a mixture you assumed was neutral usually is not.
> - **Know where the eyewash, shower, extinguisher, blanket, and spill
>   kit are before you start**, and **report every incident
>   immediately**, however small.

## Part 4 — Where this matters outside the room

About a page, answering both halves:

**a) Optimal conditions for one equilibrium process** in nature or in
industry — what conditions are chosen, and why those. Water treatment
and sedimentation, the control of an industrial synthesis, or a process
in the body all work.

**b) The impact of an equilibrium process on a biological, biochemical,
or technological system.** The curriculum's own examples are worth
starting from: remediation in areas of heavy metal contamination, the
development of gallstones, buffering in medications, and the use of
barium sulfate in medical diagnosis. Blood's own carbon dioxide buffer
is another, and it is the one your carbon dioxide experiment in
[[Disturbing an Equilibrium]] was a model of.

Two sources at minimum, of appropriate kinds, cited in the format in
[[Writing About Chemistry]]. Every figure traceable. If you cannot find
a reliable one, **write that you could not** — see
[[What Counts as Evidence]].

## What to hand in

**1. The specification sheet** — target pH, chosen pair with the
justification, the ratio calculation, and the recipe. Written for
somebody who has to make it.

**2. The prediction**, dated before any data, with all four numbers and
the working behind them.

**3. The titration curve**, plotted, with the equivalence point and the
half-equivalence point marked and read.

**4. The test results**, as a table, buffer beside water, with the
measured buffer capacity.

**5. The comparison and analysis** — predicted against measured, with
every gap accounted for and each account given a **direction**.

**6. Part 4**, about a page, with references.

Before you hand in, check every one of these:

- [ ] The target pH has a stated origin, not just a number
- [ ] All four $\text{p}K_a$ values are worked out, and three pairs are
      explicitly rejected with reasons
- [ ] The Henderson–Hasselbalch working is shown, not just the ratio
- [ ] The recipe is followable by somebody who was not there
- [ ] The prediction is dated before the data and unedited
- [ ] Distilled water was run as a control, in identical glassware
- [ ] The probe calibration standards are recorded
- [ ] The equivalence point pH is explained, not just reported
- [ ] The half-equivalence $\text{p}K_a$ is compared with the booklet's
- [ ] Buffer capacity is a **measured** number with a unit
- [ ] Every gap between predicted and measured has a direction attached
- [ ] Part 4 answers both halves, with sources

## How it will be judged

| What I am looking for | Level 3 sounds like | Level 4 sounds like |
| --- | --- | --- |
| Target pH | A stated target | A target justified from the context, with a tolerance |
| Choice of pair | The right pair chosen | The right pair, with the others rejected quantitatively |
| The calculation | Correct ratio and recipe | Correct, with the total concentration chosen deliberately for capacity |
| Prediction | pH values predicted | All four predicted **with working**, including the water control |
| Titration | A curve, with equivalence marked | Both key points read, and $\text{p}K_a$ compared with the booklet |
| Equivalence pH | Reported | Explained from what is in the flask, with the indicator implication drawn |
| The test | Measurements taken carefully | Control run alongside, calibration recorded, capacity measured |
| Analysis | Differences noted | Each difference diagnosed with a **direction** |
| Limits | Mentioned | Capacity stated as a number, and what happens past it described |
| Part 4 | A real process, correctly described | Conditions explained by equilibrium, and the impact specific |

## What sinks an otherwise good design

- **"A buffer keeps the pH constant."** It does not. It makes the pH
  change **slowly**, and only within a finite capacity. A report that
  claims constancy has not understood the thing it built, and your own
  part 3(d) data disproves it.
- **No water control.** Without it you have a solution whose pH did not
  move much, and no evidence that this is remarkable. The control is
  half the experiment.
- **A ratio calculated and never turned into a recipe.** "1.8 to 1" is
  not something anybody can weigh out.
- **Using the booklet $\text{p}K_a$ and ignoring your own measured
  one.** You measured it at half-equivalence. If it disagrees with the
  booklet, that is a finding about your solutions — most often that a
  concentration was not what the label said — and it explains your other
  gaps.
- **A prediction adjusted after the measurement.** It shows.
- **Ignoring dilution.** Adding acid adds volume. If your predicted pH
  treated the total volume as unchanged, say so and say which way it
  pushed your prediction.
- **"Sources of error: the probe was inaccurate."** A probe you
  calibrated has a known accuracy. Name what you did about it, and if
  you did not calibrate, name the direction that pushes your results.
- **Part 4 written as a description of buffers in general.** Name the
  system, name the conditions, name what fails when the pH leaves its
  band.

Where the chemistry came from: [[Buffers and Titration Curves]],
[[Acids and Bases]], and [[Dynamic Equilibrium]]. The arithmetic:
[[Acids and Bases Practice]] — question 7 in particular is this task in
miniature. Logarithms: [[Working with Logarithms in Chemistry]].
Reading the booklet's tables: [[Reading an Equilibrium Table]].

%%curriculum-start%%
## Curriculum connection

![[E1.1]]

![[E1.2]]

![[E2.5]]

![[E3.8]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 4, Day 12, the bench period, during the titration
  Watch for: when the decision about spacing gets made. Both of the
  numbers this task rests on come out of how densely the points sit
  where the pH is moving fastest, and the curve you get back shows the
  spacing without telling you whether it was planned or noticed halfway
  up the jump — by which time the equivalence volume has been passed
  once already. This is the one slot in the task where two minutes of
  watching can still fix a reading rather than only account for it
  afterwards.
  Going well: the tap slowed the moment the pH starts climbing between
  readings; a stated plan for the last few millilitres before the first
  drop goes in; the tip rinsed into the flask.
  Stuck: one increment from start to finish, leaving three points in the
  region that decides both readings; the jump crossed in a single
  addition and then approached again from the other side.
  Record: a cross on your class list beside any pair whose curve is
  going to be unreadable, and go back to them before they start making
  the buffer. That is not E2.5 itself — E2.5 is the solving, and it is
  in the report — but it decides whether there is anything worth solving
  from.

TALK — Unit 4, Day 13, while they work on the comparison and the analysis
  Ask: "You read a value off the graph at half equivalence. What did you
  have to assume about your acid for that reading to mean anything at
  all?"
  Then: "Suppose I told you the buret had been reading two per cent high
  all afternoon. Which of the two numbers you took off that curve
  changes, and which does not?"
  A strong first answer gets to one ionisation operating in the region
  they read — which, for the phosphate and the hydrogencarbonate pairs,
  means the second one and not the first — and notices that the
  concentration drops out of the arithmetic there, which is why the
  reading is worth having and also why it is fragile. A strong second
  answer sees that every volume scales, so the equivalence volume and
  the concentration it implies both move, while the pH at half
  equivalence is read off the other axis at the same physical point and
  does not. Both are E2.5 reasoned rather than executed, and a report
  can carry two correct readings without either thought having happened.
  Record: nothing written down. Note the pairs who reached the second
  answer, and ask one of them to put it on the board in the last five
  minutes.

The product evidence is the whole package on Day 14, and the titration
curve inside it.
%%
