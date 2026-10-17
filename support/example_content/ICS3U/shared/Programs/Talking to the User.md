---
title: Talking to the User
publish: true
codeRunner: true
created: __CREATED__
tags:
  - programs
---
Ms. Roy coaches the senior team. On the bus home she gets asked the
same question by four different players — "how much did I actually
practise this week?" — and she works it out on her phone every time.
This program does the arithmetic and says it in a sentence, which is
all she wanted.

## The program

To run it, type a name and a number of minutes on two lines of the
input box — `Priya` and `185`, as in the run below — then press Run.

```python run readonly
# Weekly practice check-in for Ms. Roy, who coaches the senior team.
# She wanted players to see their own week without her doing
# arithmetic on the bus home.

name = input("Player name: ")
answer = input("Minutes practised this week: ")

try:
    minutes = int(answer)
except ValueError:
    print(f"I could not read '{answer}' as a number of minutes.")
    print("Recording zero for now — run me again with a whole number.")
    minutes = 0

hours = minutes / 60
per_day = minutes / 7

print()
print(f"Thanks, {name}.")
print(f"You practised {minutes} minutes — that is {hours:.1f} hours.")
print(f"Across seven days, about {per_day:.0f} minutes a day.")
```

A run, with what the user typed shown after each prompt:

```
Player name: Priya
Minutes practised this week: 185

Thanks, Priya.
You practised 185 minutes — that is 3.1 hours.
Across seven days, about 26 minutes a day.
```

## How it works

`input()` prints its prompt, waits, and hands back whatever was typed —
always as text. `name` can stay as text, because it is only ever
printed. `answer` cannot: `"185" / 60` is meaningless to Python, so
`int()` converts it to a number the program can divide.

That conversion is the fragile line, so it sits inside a `try` block.
If `int()` raises a `ValueError`, the `except ValueError:` block runs
instead of the program stopping, and the run continues with zero
minutes recorded.

The two format instructions do different jobs. `{hours:.1f}` shows one
decimal place — without it you get `3.0833333333333335`, which is
accurate and unusable. `{per_day:.0f}` shows none at all, because
"about 26 minutes a day" is the honest precision for this number.

> [!bug]- What the program does without the try block
> The block above is read-only, so try this in your own copy: delete the
> `try`/`except`, keep only `minutes = int(answer)`, run it and answer
> `seven`:
> ```
> Traceback (most recent call last):
>   File "/home/student/practice.py", line 3, in <module>
>     minutes = int(answer)
> ValueError: invalid literal for int() with base 10: 'seven'
> ```
> Nothing else runs. Ms. Roy is handed a wall of red text on a bus,
> which is a design failure, not a user error — the program invited a
> free-text answer and then punished one.

## Change it

1. **One line.** Rewrite the second prompt so nobody has to guess the
   units or the format: something like
   `Minutes practised this week (a whole number, like 185): `. Prompts
   are the entire interface of this program, and this is the cheapest
   improvement in the file.
2. **A few lines.** Add hours and minutes properly. `minutes // 60`
   gives whole hours and `minutes % 60` gives what is left over, so 185
   can print as `3 h 5 min` — friendlier than `3.1 hours` for somebody
   planning a week.
3. **A real change.** Recording zero for a typo is a poor decision.
   Replace `minutes = 0` in the `except` block with
   `minutes = int(input("Try again, using digits only: "))`. Run it,
   type `seven`, then `185` — it recovers. Now type `seven` twice, and
   watch it crash on the second attempt. Asking "how many chances
   should somebody get?" is what makes [[Repetition]] feel necessary
   rather than academic.

Read the ideas behind this in [[Input and Output]], and practise the
conversions in [[Variables and Types Practice]].

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[B2.5]]

![[B3.3]]
%%curriculum-end%%
