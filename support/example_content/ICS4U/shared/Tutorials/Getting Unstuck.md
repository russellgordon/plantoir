---
title: Getting Unstuck
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
Stuck is a normal working condition — [[Getting Help]] says so, and
professionals live there daily. The Grade 11 distinction still holds:
**stuck-and-thinking** is generating hypotheses and testing them, and
looks slow while being progress; **spinning** is re-running unchanged
code hoping the computer changes its mind. The five moves that
convert one into the other still work, and are still worth doing
first:

1. **Re-read the line out loud.** Not what you meant — what it says.
2. **Shrink the program.** Cut away everything that is not needed to
   reproduce the problem.
3. **Print the values.** The gap between what you believe and what
   prints is where bugs live.
4. **Explain it to the duck.** Line by line, out loud. The bug hides
   in the step you were about to skip.
5. **Step away.** Ten minutes. This is a debugging move, not giving
   up.

What follows is the three kinds of stuck that Grade 11 did not have.

## Stuck in code you did not write

The instinct is to read harder. It does not work, and it burns an
hour. Run the experiments instead:

- **Run it and change one thing.** Any thing. A wrong prediction
  teaches you more per minute than a correct read.
- **Ask the history why.** When a line makes no sense, the commit
  that introduced it usually explains itself in one sentence.
  `git log` on the file, then read the messages — see
  [[Using Version Control]].
- **Write a test that describes what you think it does.** If it
  passes, you understood it. If it fails, you have learned something
  precise for free, and you now own a test that did not exist.
- **Follow exactly one path end to end and ignore everything else on
  purpose.** Trying to hold the whole program in your head is what
  made you stuck.

The full method is [[Reading Somebody Else's Code]], and when the
program is crashing rather than merely confusing,
[[Reading a Traceback in Someone Else's Code]] is the faster route.

## Stuck because the tool is stuck

Version control produces its own species of stuck, and it has a
distinct feeling: the code is fine and the *repository* is not. Three
things to know.

First, git tells you what to do next in almost every message. Read
the parenthetical suggestions in `git status` rather than searching
the internet for a command to paste.

Second, an incomplete merge is a state you can leave. A conflict you
have made worse can be abandoned with `git merge --abort`, which puts
you back where you started, and nothing is lost.

Third — and this is the one that saves evenings:

> [!warning] Never paste a git command you cannot explain
> The internet is full of confident advice involving forceful
> commands, and some of it will genuinely delete your team's work. If
> a suggested fix contains a word like `force`, `hard`, or `clean`
> and you cannot say precisely what it will do, stop and ask.
> Copy the whole error message and bring it to a help session. Almost
> every git problem is recoverable; the exceptions are nearly all
> caused by the panic fix.

## Stuck because your team is stuck

Sometimes you are not blocked by the code. You are waiting on
somebody, or two of you disagree and nothing has moved for a day, or
you do not want to admit you have not started. All three feel
personal and none of them is:

- **Waiting on a teammate.** Say it at the standup, in slot three,
  the day it starts. That is what slot three is for — see
  [[Working in a Team]].
- **A disagreement that has stalled.** Run the protocol: restate the
  other position, look for evidence that could settle it, then decide
  and record it. Do not let it sit; the code is not getting written
  while it does.
- **Falling behind quietly.** This is the one that grows in the dark.
  A team that hears "I am two days behind on the export" on Tuesday
  can help. A team that finds out on Friday cannot. Nobody in this
  course has ever got in trouble for saying it early.

> [!important] Twenty minutes, then say something
> Alone: twenty minutes of genuine stuck-and-thinking, then take a
> move from the list or ask. On a team the number is smaller, because
> your stuck is now costing other people time. Being stuck is free.
> Being stuck silently is what gets expensive.

## Stuck on the problem, not the code

The program runs, nothing is broken, and you do not know what to
build next. That one is never solved by staring at the editor. Go
back to the person you are building for: one question to your
community partner dissolves more design paralysis than an afternoon
of thinking about it alone. If the partner is slow to reply, build
the smallest version of what you already know they need — a working
small thing is also a question, and a better one than most emails.

The reason none of this should embarrass you: everybody in the room
is stuck on something right now, and the ones who look like they are
not are simply further into the twenty minutes.

%%curriculum-start%%
## Curriculum connection

![[A4.1]]
%%curriculum-end%%
