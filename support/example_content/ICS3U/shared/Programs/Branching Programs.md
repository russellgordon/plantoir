---
title: Branching Programs
publish: true
codeRunner: true
created: __CREATED__
tags:
  - programs
---
Mr. Whitfield runs the library on his own at lunch, and about a dozen
students take turns helping at the desk. His problem was never the
arithmetic — it was that the same overdue book got four different
reactions depending on who was standing there. This program is his
policy, written down once, in a form that cannot be forgotten at the
end of a long week.

## The program

To run it, press Run, and when it asks, type a title and then a number
of days late — `Fifteen Dogs` and `12`, as in the run below.

```python run readonly
# Return-desk helper for Mr. Whitfield, who wants the same book
# treated the same way every time, whoever is at the desk.

title = input("Title: ")
answer = input("Days past the due date (0 if on time): ")

try:
    days_late = int(answer)
except ValueError:
    print(f"I could not read '{answer}' as a number of days.")
    days_late = 0

print()

if days_late <= 0:
    print(f"{title}: on time. Shelve it and say thanks.")
elif days_late <= 7:
    print(f"{title}: less than a week late. Shelve it, no message.")
elif days_late <= 30:
    print(f"{title}: {days_late} days late. Send the standard reminder.")
else:
    print(f"{title}: {days_late} days late — over a month.")
    print("Ask in person, kindly: it is usually lost, not stolen.")
```

```
Title: Fifteen Dogs
Days past the due date (0 if on time): 12

Fifteen Dogs: 12 days late. Send the standard reminder.
```

## How it works

Exactly one of the four branches runs, and which one depends entirely
on `days_late`:

| `days_late` | Branch that runs | Because |
| --- | --- | --- |
| `0` or less | on time | `days_late <= 0` is the first `True` |
| `1` to `7` | no message | the first test failed, the second passed |
| `8` to `30` | standard reminder | the first two failed |
| `31` or more | speak in person | nothing matched, so `else` catches it |

The order is doing real work. Each `elif` is only ever reached when
every condition above it was `False`, which is why `days_late <= 30`
does not need to also say "and more than 7" — that is already known.
Swap two branches around and the program still runs, still prints
something, and is silently wrong for half its inputs; that is the logic
error described in [[Making Decisions]].

The `try` block came from testing, not from good intentions. The test
plan in [[Testing and Debugging]] includes the row "user types `soon`",
and the first version of this program failed it.

Two things this program deliberately does not do: it does not record
who borrowed the book, and it does not mention fines. Both were
decisions made with Mr. Whitfield, and both are the kind of thing
[[Who Is This For]] exists to make you ask about out loud.

## Change it

1. **One line.** Mr. Whitfield decides that "recently late" means two
   weeks, not one. Change `days_late <= 7` to `days_late <= 14` and
   nothing else — the reminder branch now starts at 15, automatically,
   because it never mentioned 7 in the first place.
2. **A few lines.** Put the day count into the second message, and
   handle the awkward case with a nested `if`: `1 day late`, but
   `4 days late`. It is a small thing that makes a program sound like
   it was written by somebody who cared.
3. **A real change.** Ask a third question — `Is this a course text?
   (yes/no)` — and make a course text under a week late get the
   standard reminder anyway, because somebody else's class is waiting
   for it. You will need a condition with `and` in it, which is the
   whole subject of [[Boolean Logic]]. Then re-run the test plan: three
   of your five rows just changed their expected result.

Practise the branching itself in [[Decisions Practice]].

%%curriculum-start%%
## Curriculum connection

![[A1.4]]

![[A2.2]]

![[B3.1]]
%%curriculum-end%%
