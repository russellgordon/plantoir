---
title: Writing Functions
publish: true
codeRunner: true
created: __CREATED__
tags:
  - programs
---
Ms. Roy's practice check-in came back for a second round. She wanted
the week's total, the longest single session, and the number of days
off — and she wanted the totals in hours and minutes, not decimals,
because "3.1 hours" means nothing when you are planning a Tuesday. The
first draft had the hours-and-minutes arithmetic written out three
times. This one has it written once.

## The program

```python run readonly
# Practice-week summary for Ms. Roy, who plans next week from last
# week's minutes. Three small functions, each with one job.

def total_minutes(sessions):
    total = 0
    for minutes in sessions:
        total = total + minutes
    return total


def longest_session(sessions):
    longest = sessions[0]
    for minutes in sessions:
        if minutes > longest:
            longest = minutes
    return longest


def as_hours_and_minutes(minutes):
    hours = minutes // 60
    rest = minutes % 60
    return f"{hours} h {rest} min"


week = [45, 0, 60, 30, 0, 90, 25]

print("Last week's practice")
print(f"Total:    {as_hours_and_minutes(total_minutes(week))}")
print(f"Longest:  {as_hours_and_minutes(longest_session(week))}")
print(f"Days off: {week.count(0)}")
```

```
Last week's practice
Total:    4 h 10 min
Longest:  1 h 30 min
Days off: 2
```

## How it works

Nothing runs when Python reads a `def` — it only remembers the
definition. The program really begins at `week = [...]`, and the three
`print` lines are the whole of it. That is the shape to aim for: a main
part short enough to read aloud, standing on functions with honest
names.

Each function takes what it needs as a **parameter** and hands back an
answer with `return`. None of them prints anything, which is what lets
them be combined:
`as_hours_and_minutes(total_minutes(week))` works because the inner
call is finished and replaced by `250` before the outer call begins.

`as_hours_and_minutes` is the one that earns its keep. `//` gives whole
hours, `%` gives the leftover minutes, and this awkward little pair of
lines now exists in exactly one place. When Ms. Roy asks for `4h10`
instead, you edit one function and every line of output changes.

`week.count(0)` is a reminder that you are not obliged to write
everything yourself — `count` is a method that lists already have, like
`len`, `max`, and `abs`. Reaching for the tool that exists is a skill,
not a shortcut.[^1]

## Change it

1. **One line.** Change `as_hours_and_minutes` to return
   `f"{hours}h{rest:02d}"`, and the total prints as `4h10`. The `:02d`
   pads the minutes to two digits, so five past four is `4h05` rather
   than `4h5`.
2. **A few lines.** Write a fourth function, `days_practised(sessions)`,
   that counts the sessions above zero and returns the count — `5` for
   this week. Then use it instead of `week.count(0)` and say
   "Days practised" in the output, which is the sentence a coach would
   rather read.
3. **A real change.** Add `last_week = [30, 30, 60, 0, 45, 60, 0]` and
   print a summary for both weeks by calling the same three functions
   again with the other list. Nothing inside any function changes —
   that is what "reusable" means, and it is the reason
   [[Decomposition and Design]] treats functions as the unit you design
   in.

The ideas behind this page are in [[Functions]] and
[[Parameters, Returns, and Scope]]; the reps are in
[[Functions Practice]].

[^1]: Every one of these functions is a *subprogram* in the
    curriculum's vocabulary, whether you wrote it or Python did. The
    only difference is who maintains it.

%%curriculum-start%%
## Curriculum connection

![[A3.1]]

![[A3.2]]

![[B2.3]]
%%curriculum-end%%
