---
title: The Data Digest
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Solo or pairs · launched in Unit 2 and due at the digest gallery
> seven classes later · one program, one pile of data, one page of advice ·
> the first task where the output has to change somebody's mind

## What you are making

A program that reads a pile of data and prints a **digest**: a short,
plain summary that a specific person can act on. Forty numbers are not
useful to anybody. "Empty the bin on Friday after lunch" is.

Bring your own pile — attendance counts, practice times, bus arrivals,
minutes of something, a tally somebody already keeps on paper — or use
one of the sets provided. Forty values is a good size. It must be data
somebody actually collected about something that actually happens.

## Facts are not advice

Here is a program that computes correctly and helps nobody:

```python
items = [3, 11, 4, 9, 12, 2, 10, 5]
total = 0
highest = items[0]
for count in items:
    total = total + count
    if count > highest:
        highest = count
average = total / len(items)
print(f"Days recorded: {len(items)}")
print(f"Average per day: {average:.1f}")
print(f"Busiest day: {highest} items")
```

It prints:

```
Days recorded: 8
Average per day: 7.0
Busiest day: 12 items
```

Every line is true. Not one of them tells the caretaker when to walk
over with the shoebox. Your digest has to take the last step — from
what the numbers *are* to what your person should *do* — and it has to
be honest about how confident that step is.

## What must be in it

- **A named person and their decision.** One sentence: *[Name] has to
  decide [what], and right now they decide it by [how].*
- **Your data, with its source**, and permission if somebody else
  collected it. If the data is about people, it arrives with no names.
- **A list holding the values**, built or read in one place, so that
  more data means more values and not more code.
- **At least three findings** computed by loops over that list — a
  total, a count, an average, a highest or lowest, a search, or a
  grouping. Nested repetition earns its keep if your data has rows and
  columns.
- **A recommendation** in plain language, printed by the program.
- **A "what this does not say" paragraph**, written by you.

## How to work

1. Find your person and their decision before you find your data. Data
   first is how you end up with a beautiful chart nobody needed.
2. Get the pile into a list and print it. Check the count. Data always
   arrives dirtier than promised — a blank, a typo, a day that is
   missing entirely.
3. Compute one finding. Verify it by hand on paper for five values. Do
   not compute a second finding until the first one is provably right.
4. Write the recommendation last, and try it on your person. If they
   say "I knew that already", you have a finding, not advice — go back
   and look for what surprised *you*.
5. Write the "what this does not say" paragraph honestly. Who is
   missing from this pile? What would change your recommendation? Which
   number is doing more work than it should?

## How this is assessed

Per [[How Marks Work]], the working periods count and so does the trail
in your [[Code Journal]]. The gallery is part of the task: you read
three classmates' digests and act on one of them, and what you write
about somebody else's data is assessed alongside your own. The
paragraph about limits carries real weight — a digest that oversells
itself scores below one that says clearly what it cannot support.

## Success criteria

| Quality | What it looks like in your digest |
| --- | --- |
| A decision served | The person and the decision are named up front |
| Data handled properly | Values live in a list; the count is verified |
| Findings that hold up | At least three, each checkable by hand |
| From facts to advice | The output tells them what to do, in plain words |
| Honest limits | You name who or what is missing, without hedging |
| Readable output | A tired person reads it once and understands it |

## Reflect

A [[Code Journal]] entry: which finding surprised you, and what did you
almost round away? Then the harder question, the one
[[When Code Hurts]] keeps asking — whose experience does your average
erase, and would they recognise themselves in your recommendation?

> [!question]- If your data is boring
> Good. Boring data about a real chore beats exciting data about
> nothing. A number that changes what a person does on Friday is worth
> more than a spectacular chart about a topic nobody in the room has
> any power over. And if your pile genuinely says nothing, that is a
> finding too — write the digest that says so, with the evidence, and
> tell your person they can stop collecting it.

%%curriculum-start%%
## Curriculum connection

![[A1.6]]

![[A2.3]]

![[B2.5]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 2, Day 12, the walking-skeleton period
  Watch for: whether the program runs end to end on fake data before
  anything is made correct, or whether the first stage is polished
  while the rest does not exist. By Day 17 both look finished.
  Going well: something runs in the first twenty minutes, badly.
  Stuck: forty minutes on reading the file perfectly.
  Record: a time against each name — when did theirs first run.

TALK — Unit 2, Day 16, at the conferences already on that agenda
  Ask: "Show me the row of your test plan that failed, and what you
  changed because of it."
  Then: "Which of your prompts would confuse somebody who did not
  write this?"
  The second question is B2.5 — designing an interface for a person —
  and the honest answers only ever arrive in conversation, because the
  submitted program's prompts always look deliberate.
  Record: one line per student on the conference sheet.

The product evidence is the digest handed in on Day 17.
%%
