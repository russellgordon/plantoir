---
title: The Toolbox
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Solo · launched in Unit 3 and due nine classes later · six named
> working days, one module of reusable functions, one demonstration program, one usage note · the
> dress rehearsal for the culminating project

## What you are making

A **module** — one Python file of well-named functions that solve small
problems you keep meeting — plus a second file that imports it and
proves it works. The functions must be useful to somebody who did not
write them, which for once is a testable claim: a classmate will import
your toolbox and use it from your notes alone, without asking you a
single question.

At least one of your tools must read from or write to a file, because a
tool that forgets everything the moment the program closes is not much
of a tool.

```python
def read_lines(file_name):
    """Return every line of a text file, without the newline characters."""
    lines = []
    with open(file_name) as file:
        for line in file:
            lines.append(line.strip())
    return lines
```

And, in a separate file, the proof that it is genuinely reusable:

```python
from toolbox import read_lines

names = read_lines("names.txt")
print(f"{len(names)} names loaded")
print(names[0])
```

Note what the function does *not* do: it does not print, it does not
ask the user anything, and it does not care why you want the lines.
That is what makes it a tool rather than a fragment.

## What must be in it

- **At least four functions**, each doing one job, each named for what
  it gives you rather than how it works.
- **Parameters in, values returned.** A function that prints is a
  function that can only ever do one thing.
- **At least one that reads a file and one that writes one.**
- **A short docstring or comment** per function: what it takes, what it
  hands back, and what it assumes.
- **A demonstration program** that imports the module and uses every
  function at least once.
- **A usage note** — half a page — saying what the toolbox is for, how
  to run the demonstration, and what each tool expects.
- **A sensible folder**, with the module, the demo, the data files, and
  the note in one place, named so that a stranger can tell what is
  what. Keep a backup somewhere that is not the machine you are typing
  on.

## How to work

1. Look back through Units 1 and 2 for the thing you wrote three times.
   That is your first tool. Do not invent tools you have never needed.
2. Write the function's *call* first — the line you wish you could
   write — then make it true. Naming before building keeps the job
   honest.
3. Test each tool the moment it exists, on its own, with a value you
   worked out by hand. Four tested tools beat nine hopeful ones.
4. Move the file work last. Files add the failure modes: missing file,
   empty file, a stray blank line at the end. Meet them now, on your
   own terms, rather than in Unit 4 in front of your client.
5. Swap toolboxes with a classmate in the last working period. They
   import yours from the usage note alone; you import theirs. Every
   question they have to ask you is a defect in your note, not in them.
6. Fix the note. Then back the whole folder up.

## How this is assessed

Per [[How Marks Work]], the working periods and your
[[Code Journal]] are part of the mark. The swap is the moment that
matters most: I am watching whether a stranger can use your work, which
is precisely what [[The Community App]] will demand of you for the rest
of the course, except that the stranger will be a person who does not
program at all. Treat this as the rehearsal it is — the habits you
build here are the ones you will have under pressure later.

## Success criteria

| Quality | What it looks like in your toolbox |
| --- | --- |
| One job per function | Each name describes exactly one thing |
| Genuinely reusable | Tools return values; nothing prints or prompts |
| Data that survives | One tool reads a file, another writes one |
| Documented enough | A classmate used it without asking you anything |
| Tested deliberately | Each tool was checked against a hand-worked value |
| Organised and safe | Sensible folder, sensible names, a real backup |

## Reflect

A [[Code Journal]] entry: which function did you have to rename before
it made sense, and what did the new name teach you about what it
actually did? Then note the question your classmate asked during the
swap — that question is the first line your usage note was missing.

> [!question]- If four functions feels thin
> The count is not the point; the reuse is. A toolbox of four functions
> that another person imported successfully has cleared a bar that most
> student code never approaches, while nine clever functions nobody can
> call are a private diary written in Python. If you want more
> ambition, aim it at the usage note — the shortest note that still
> lets a stranger succeed is a genuinely hard piece of writing, and
> [[Writing Code Others Can Read]] is where that craft lives.

%%curriculum-start%%
## Curriculum connection

![[A3.2]]

![[B2.3]]

![[C2.1]]

![[C2.3]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 3, Day 13, the rehearsal swap
  Watch for: what the owner does when a neighbour cannot import their
  toolbox from the note alone. Answering out loud patches the problem
  and hides it; writing the answer into the note fixes it.
  Going well: the note is being edited while the neighbour is stuck.
  Stuck: a conversation that ends with "oh, you just have to…".
  Record: two columns — edited the note, explained instead.

TALK — Unit 3, Day 11, at the conference already on that agenda
  The agenda already announces that the conference is about which four,
  so open past it. Ask: "What does each one need handed to it, and what
  does it hand back?"
  Then: "Which of the four did you have to change the shape of once you
  started writing it?"
  A strong answer is in parameters and return values. A weak one says
  what each function is for. That is A3.2 — writing subprograms with
  parameter passing and sensible scope — and the code cannot separate a
  student who chose the interface from one who wrote it and hoped.
  Record: one line each, on the conference sheet.

The product evidence is the toolbox handed in on Day 17.
%%
