---
title: Coding a Scientific Model
createdSection1: 2026-10-01T07:00:00.000-0400
publishForSection1: true
createdSection2: 2026-10-02T07:00:00.000-0400
publishForSection2: true
enableToc: true
tags:
  - skills
  - assessment
---
> [!abstract] At a glance
> Individual or pairs · **two class periods** of work time — Unit 2, Days 5
> and 11 · **Format:** a working program plus a short write-up of what it
> shows and where it lies

If you work in a pair you may share one program. **The written part is
yours alone**, and it is what carries the marks.

## The task

Write a program that models a scientific relationship you have studied, and use
it to answer a question you could not easily answer by hand.

## Starting point

```python
# Model the energy remaining at each trophic level.

def energy_at_levels(starting_energy, transfer_rate, levels):
    # Return the energy available at each trophic level.
    remaining = starting_energy
    results = []
    for level in range(levels):
        results.append(remaining)
        remaining = remaining * transfer_rate
    return results


amounts = energy_at_levels(10000, 0.10, 5)
for index in range(len(amounts)):
    print("Level", index + 1, ":", round(amounts[index], 2), "kJ")
```

## Choose one

| Model | The question it answers |
| --- | --- |
| Energy pyramid | How many trophic levels can an ecosystem support? |
| Ohm's law calculator | What resistance is needed for a given current? |
| Radioactive decay | How much remains after $n$ half-lives? |
| Orbital periods | How does period change with distance? |
| Population growth | What happens when a limit is introduced? |

## Requirements

- [ ] At least one **loop** and one **function**
- [ ] Inputs the user can change without editing the code
- [ ] Output that is readable — labels and units, not bare numbers
- [ ] Comments explaining the **science**, not the syntax
- [ ] A run with at least three different inputs, results recorded

## The written part

1. What relationship does your model represent? Give the equation.
2. What did you learn by changing the inputs that you would not have seen
   otherwise?
3. Where does your model stop being realistic? Every model has a limit — find
   yours and state it.

> [!tip] Do not confuse a calculator with a model
> Computing one answer is arithmetic. A model lets you ask "what if?" repeatedly
> and see a *pattern* in the answers. Aim for the second.

## Success criteria

| Quality | What it looks like in your work |
| --- | --- |
| The science is in the code | Comments say what a quantity means and where the relationship comes from — not what the line of Python does |
| It can be asked more than one question | Inputs change without editing the code, and three different runs are recorded with their results |
| Output somebody else could read | Every printed number carries a label and a unit |
| The relationship is named | The written part states the equation the model stands for, the way you would write it on paper |
| A limit that is genuinely found | One specific input, or range of inputs, where the model stops describing anything real — and the reason |

## Curriculum connection

![[A1.4]]

%%
Triangulation — the evidence you will not have unless you go and get it.

A program that runs is a product that hides almost everything about how it was
made, and a write-up can describe a model the student never actually explored.
Both periods are working periods with you in the room, so both are cheap.

OBSERVE — Unit 2, Day 5, the working period
  Watch for: what happens in the ten seconds after an error message appears.
  This is the first time most of this class has met one. Nothing about it
  survives into the finished program, which runs cleanly by definition.
  Going well: the message is read — out loud, or with a finger on the line
  number — and one thing is changed before it is run again.
  Stuck: the block is deleted and retyped from the top, or the whole file is
  closed without saving.
  Record: three columns on your day plan — read it, deleted it, asked a
  neighbour. Any of the three is fine to see once; the second one twice in a
  period is a student to sit beside.

TALK — Unit 2, Day 11, the write-up period
  The task page already asks where the model stops being realistic, the
  criteria ask them to write that input down, and the agenda spends an item on
  the three ways it is wrong. All of that is spent. Go underneath it.
  Ask: "Is there an input where your program is perfectly happy and the science
  is not? Show me."
  Then: "What is the smallest change to an input that changes the advice you
  would give somebody?"
  A strong first answer separates the two machines: a crash or an impossible
  unit is the program complaining, while a smooth confident number that could
  not happen is the relationship complaining, and they can run one on demand. A
  strong second answer has been looked for rather than guessed — they know
  which input their answer is most sensitive to, because they moved it. That is
  A1.4 heard: coding used to investigate a relationship rather than to
  calculate one. A working program with a paragraph about limits underneath
  looks identical whether or not any of it happened.
  Record: two columns while they type — could run one on demand, or could only
  describe one. One circuit of the room covers the class.

The product evidence is the program and its write-up, handed in at the end of
Unit 2, Day 11.
%%
