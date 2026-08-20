---
title: _DUPLICATE ME
publish: false
created: __CREATED__
tags:
  - template
---
Duplicate this file (right-click → Duplicate) to start a new page in
**Tasks**. Rename the duplicate, delete this note, and write the real page.

## What belongs in Tasks

Evaluated work — the pieces that carry a mark. Both gates in this toolchain
(the linter and the site build) decide what counts as "assessed" by
FOLDER: a page anywhere else that carries a mark is invisible to the
Curriculum Coverage map no matter how real the evaluation is. If it's
graded, it lives here.

## A starting shape

```markdown
---
title: Your Title Here
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
One or two sentences on what this task asks for and why it matters.

## Success criteria

| Quality | What it looks like |
|---|---|
| ... | ... |

## How to work

1. Launch day — link the real class day here.
2. ...

%%curriculum-start%%
## Curriculum connection

![[CODE]]
%%curriculum-end%%

%%
Triangulation block — see below.
%%
```

## Reminders

- **Success criteria in student language**, visible on the day the task
  launches — not expectation text lifted from Curriculum/.
- **A group task names the individually-evaluated element.** A shared
  product is real evidence but never a shared mark — see [[How Marks Work]]
  for why.
- **Evaluated writing is done in class**, on a day the "How to work"
  section names. Ongoing homework is never the evaluated thing itself.
- **Only PUBLISHED curriculum codes this task genuinely asks for.** Read
  each code's verbatim text before transcluding it — if naming it feels
  like a stretch, either change the task so it really does ask for that
  thing, or leave the code off.

## The triangulation block

Every task page ends with a hidden `%%...%%` comment naming where the
teacher can gather evidence beyond the finished product — observation and
conversation are the two kinds a real course loses first. Fill in the
template below with THIS task's real days, checked against `per_section/All
Classes/` — never a plausible-sounding guess:

```
%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — [real day], [what's happening that day]
  Watch for:
  Going well:
  Stuck:
  Record:

TALK — [real day], [a checkpoint the arc already schedules]
  Ask:
  A strong answer:
  Record:

The product evidence is [what], handed in [real day].
%%
```

Six rules, non-negotiable: name real days you've checked against the
schedule; name something visible only in the DOING, invisible in the
finished product; give real questions with what a strong answer sounds
like — never one already printed on the task page itself; say how to
record it in seconds; prefer a slot the arc already has; tie it to a
curriculum code this task already lists, and check the code's own verbatim
text actually matches the evidence your question would produce.

Preview your change (⌘+E in Obsidian toggles Reading view) before you
consider the page finished.
