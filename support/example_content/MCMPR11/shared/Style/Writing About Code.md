---
title: Writing About Code
publish: true
created: __CREATED__
tags:
  - reference
enableToc: true
---
Half of this course happens at a keyboard. The other half happens when
you put technical thinking into words somebody else can follow — in
your [[Learning Journey Log]], in the comments inside your programs, in the
written parts of every task, and eventually in the handover notes a
real client will read without you standing beside them. Writing about
code has one rule that does most of the work:

> [!important] Write for the next person, who might be you
> Every comment, entry, and explanation is addressed to somebody who
> cannot see inside your head — including the version of you who
> returns in three weeks remembering nothing. If it only makes sense
> with you there to narrate it, it is not finished.

## Formatting code in your writing

When you are writing sentences about code, format the code so it looks
like code.

- Use backtick code spans for variable names and small snippets in a sentence: "The `aqhi_index` variable stores the air quality."
- Use code blocks for multi-line examples. This separates the prose from the programming.

## Precision is kindness

Describe what code DOES, not how it looks. Use precise vocabulary: "the loop iterates" not "the loop goes". Describe the specific inputs and expected outputs.

The same moments, described vaguely and then usefully:

| Instead of… | Try… |
| --- | --- |
| "It doesn't work" | "It crashes on line 12 when the input is empty" |
| "I fixed it" | "The loop iterated once too often — `range(4)`, not `range(5)`" |
| "It's done" | "Meets all criteria; known limit: negative AQHI values untested" |
| "The client liked it" | "They used the avalanche tracker twice without asking me anything" |

Every phrase in the right-hand column can be checked by somebody else.

## Trace tables

When explaining a complex algorithm, a trace table is often clearer than a paragraph. List the variables across the top and show how their values change as the program executes step by step.

## Writing for the person who will use it

Handover notes are a different genre from a journal entry, and the
audience is not a programmer. Three things belong in them: what the
program does in one sentence, how to run it step by step on their
machine, and what it will not handle. That last one is not an
admission of failure — a limit stated in advance is a limit somebody
can plan around, while a limit discovered in use is a broken promise.

## Claims about technology need evidence too

When you write about accessibility, bias, or whether a thing should
exist at all, the standard does not soften. Specific beats sweeping,
sources get named, and "I read somewhere" is a bug. Strong writing
about technology sounds like a strong bug report: a claim, the
evidence, and an honest note about what you do not yet know. Ground
your examples in the real world — whether it is the VW emissions
scandal or the CrowdStrike outage.

%%curriculum-start%%
## Curriculum connection

![[K1.14]]
%%curriculum-end%%
