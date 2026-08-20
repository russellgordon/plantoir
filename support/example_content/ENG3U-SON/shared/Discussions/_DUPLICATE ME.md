---
title: _DUPLICATE ME
publish: false
created: __CREATED__
tags:
  - template
---
Duplicate this file (right-click → Duplicate) to start a new page in
**Discussions**. Rename the duplicate, delete this note, and write the real
page.

## What belongs in Discussions

One page per seminar or discussion circle, anchored to a single class
period. Each page names the real, specific question or questions a teacher
actually runs that period from — never "discuss the theme" or "share your
thoughts." A student should be able to open the page the night before and
know exactly what tomorrow's class is going to ask of them.

## A starting shape

```markdown
---
title: Your Title Here
publish: true
created: __CREATED__
tags:
  - discussions
---
One or two sentences setting up what the class has read or seen, and what
today's seminar is actually deciding or arguing about.

## The questions

1. A real, specific question — not "what did you notice?"
2. A second question that asks for something different in kind from the
   first (an explanation, a judgement, a prediction, a close-listening
   observation — not the same shape wearing a different topic)
3. Optional third and fourth questions

What a strong answer to one of these sounds like — a sentence or two, or a
short quoted example, showing what real evidence-based thinking looks like
here, not just "a good answer would be detailed."

## Curriculum connection
```

## Vary the question type

If you write several of these pages back to back, read your opening
questions back as a bare list, topics stripped out. If more than two or
three reduce to the same shape — "what did you notice," dressed in a new
noun — rewrite some. A prediction, a disagreement with a character's
reasoning, an explanation of a choice, a question about who's affected, a
close-listening or close-reading prompt: these ask for different kinds of
thinking, and a course that only ever asks one of them is teaching a
narrower skill than it thinks it is.

## If the title needs a colon or a question mark

Filenames cannot contain `?`, `:`, or the other characters Windows forbids
(`<>:"|?*`) — it breaks that platform's checkout entirely. If your title
needs one, give the FILE a different name (swap `:` for ` -`, or just drop
a trailing `?`) and keep the real title, punctuation and all, in the
frontmatter `title:` field. Then link to the page everywhere with a piped
alias so the reader still sees the real title: `[[Filename|Real Title?]]`,
escaped as `[[Filename\|Real Title?]]` inside a table cell.

## Reminders

- **Link it from a class page**, directly or through one page a class page
  already links to — nothing on this site stands alone.
- Cross-link to the Texts page the discussion is anchored to, where one
  exists — a student rereading before the seminar should be one click from
  the text itself.
- If this page uses a format the class hasn't seen before (fishbowl,
  close-listening circle, structured debate), briefly explain the format
  itself, not just the questions — a student new to it needs to know how
  the room is going to work, not only what it's going to talk about.
- Add the curriculum connection block only for the specific expectations
  this exact seminar genuinely evidences.

Preview your change (⌘+E in Obsidian toggles Reading view) before you
consider the page finished.
