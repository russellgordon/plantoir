---
title: Digital Citizenship, Etiquette, and Online Literacy
publish: true
created: __CREATED__
tags:
  - concept
  - ethics
enableToc: true
---
You've just found the fix. A one-line change to your teammate's function
would stop it crashing on an empty list. There are at least three ways to
tell them, and they don't land the same way:

- "your code is broken"
- "hey found a bug, the loop crashes on `[]`, one-line fix if you want it"
- silently fixing it yourself in their file without saying anything

Only one of those is how working programmers actually talk to each other.
This page is about that: not the ethics of the software you build — see
[[Digital Ethics, Open Source, and User Privacy]] for that — but how you
conduct yourself as the person building it, in a course where what you
hand in is supposed to show what *you* can do.

## Citing sources and avoiding plagiarism

If you copy code from a tutorial, a classmate, or a website, say so — a
short comment naming where an idea or a block came from is normal
practice, not an admission of weakness:

```python
# Approach adapted from the Python docs example at
# https://docs.python.org/3/library/statistics.html
```

The line between "learning from an example" and "submitting someone
else's work as your own" is whether you understand what you copied well
enough to explain it and to modify it. If you can't answer "why does this
line use `key=`?" about your own submission, that's the signal to slow
down and actually understand it before handing it in — not just before
the marking, but for you, because the whole point of the exercise was to
build the skill, not produce the file.

## Using an AI coding assistant honestly

AI coding assistants are a normal part of professional programming now,
and pretending otherwise wouldn't be honest either. The distinction that
actually matters in this course is what the assistant is *for*, on a
given task:

- Asking an assistant to explain an error message you're stuck on, or to
  suggest what a confusing built-in function does, is using it as a
  tutor. That's fine, and often a good use of it.
- Asking an assistant to write the function you were assigned to write,
  then submitting that output as your own work, is using it as a ghost
  writer. On an assessment meant to show what *you* can do, that
  undermines the entire point of doing the assessment — you'll have a
  working file and none of the skill the file was supposed to prove you
  have.

The test that holds up under pressure: could you sit down right now,
without the assistant, and rebuild roughly what you just submitted? If
yes, you used the tool well. If the honest answer is no, the work isn't
actually yours yet, whatever the file says. Ask your teacher directly
when a specific task's rules aren't clear — "can I use an AI assistant for
this one" is a completely reasonable question to ask out loud.

## Professional tone in writing about code

The examples at the top of this page apply everywhere you write about
code for another person to read, not only in class:

| Situation | Reads as unprofessional | Reads as professional |
| --- | --- | --- |
| A GitHub issue | "this is broken, fix it" | "clicking Submit with an empty form crashes the app — here's the traceback" |
| An email to a client | "the thing you asked for doesn't really work like that" | "I've built the search feature; one edge case (empty results) still needs a decision from you before I finish it" |
| A code review comment | "why would you write it like this" | "I noticed this loop checks the list twice — could a single pass work instead?" |
| A commit message | "fixed stuff" | "fix crash when sign-in sheet is empty" |

The professional version is not longer for the sake of it — it's more
specific, names the actual problem, and leaves the other person something
they can act on.

## Deciding whether a source is trustworthy

Before you rely on a library, a tutorial, or a Stack Overflow answer, ask
a few quick questions: Is it current, or does it reference a Python
version several years old? Does it come from documentation or a known
maintainer, rather than an anonymous forum post with no explanation? Does
it actually explain *why* the code works, or just present it as a
copy-paste block? A source that only survives the first question is worth
treating with more caution than one that survives all three — and "it
was the first result" is never, on its own, a good enough reason to trust
something.

What counts as acceptable help, and how much explanation a source owes
you, isn't a fixed rule handed down from nowhere — it reflects the values
of the community you're writing for. A course assessing your own
learning, an open-source project that expects contributors to explain
their reasoning, and a workplace that just wants a fast fix can reasonably
draw that line in different places. Part of digital literacy is noticing
which context you're in before you decide how much to lean on a source.

%%curriculum-start%%
## Curriculum connection

![[K1.17]]

![[T1.4]]
%%curriculum-end%%
