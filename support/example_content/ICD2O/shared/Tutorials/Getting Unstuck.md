---
title: Getting Unstuck
publish: true
created: __CREATED__
tags:
  - tutorials
---
Stuck is a normal working condition — [[Getting Help]] says so, and
professionals live there daily. But there are two kinds of stuck.
**Stuck-and-thinking** is generating hypotheses and testing them; it
looks slow and is actually progress. **Spinning** is re-running the
same code unchanged, hoping the computer changes its mind. It will
not. These moves convert spinning back into thinking:

1. **Re-read the line out loud.** Not what you meant — what it *says*.
   A startling number of bugs die at this step: the missing colon, the
   `=` that should be `==`, the variable named `scroe`.
2. **Shrink the program.** Comment out everything after the last part
   that worked, run, then bring lines back one at a time. The bug is
   in the first line whose return breaks it — now it is cornered.
3. **Print the values.** You *believe* `total` is 10. Add
   `print(total)` right before the crash and check. The gap between
   what you believe and what prints is exactly where the bug lives.
4. **Explain it to the duck.** Rubber-duck debugging is a real
   professional technique with a silly name: explain your program,
   line by line, to a duck or any patient object. Saying "and then
   this adds one to the score — wait." *is* the technique working.
   The bug hides in the step you were about to skip over.
5. **Step away.** Ten minutes, water, a walk. The brain keeps working
   without the screen glare, and the bug you could not see at 2:10 is
   often obvious at 2:20. This is a debugging move, not giving up.
6. **Consult authoritative technical documentation.** When inspecting
   your code hits a wall, search official Python documentation or
   language reference guides (as taught in [[Finding Answers Online]])
   for the exact function syntax, parameter requirements, or error type.

## Knowing which stuck you are in

Honest test: *when did you last change something on purpose?* If the
answer is "three runs ago", you are spinning — pick a move above, or
escalate up the ladder in [[Getting Help]]. Twenty minutes of genuine
stuck-and-thinking is time well spent; twenty minutes of spinning is
just suffering with extra steps, and nobody is marking you on
suffering.

The full method for error messages specifically is
[[Debugging Step by Step]]; the reason none of this should embarrass
you is [[Debugging Is the Job]].

%%curriculum-start%%
## Curriculum connection

![[B2.2]]

![[C2.6]]
%%curriculum-end%%
