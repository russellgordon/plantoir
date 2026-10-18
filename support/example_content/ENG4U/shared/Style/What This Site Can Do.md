---
title: What This Site Can Do
publish: true
created: __CREATED__
enableToc: true
---
This page has two audiences. Students: it shows why the notes look the
way they do. Teachers: it is a working reference for everything a page
here can hold, with the source of every example shown beside it.

Everything below is written in **Markdown** — plain text with a few marks
of punctuation that mean something. If you can write a text message, you
can write this.

---

## Text that carries meaning

You get **bold**, *italic*, ~~struck through~~, and ==highlighted== text.
Highlighting is the one worth knowing: it draws the eye better than bold
when you want a single ==key term== to stand out in a paragraph.

**How that was made:**

```markdown
**bold**, *italic*, ~~struck through~~, ==highlighted==
```

Keyboard keys look like keys: press <kbd>⌘</kbd> + <kbd>K</kbd> to
search this site.

---

## Headings, and the table of contents

Every `##` heading becomes a link in **Navigate this page**, on the
right. Nothing builds that list by hand — it is made from the headings as
the page is built, so it cannot fall out of step with the page.

### Turning it off

A short page reads better without a contents panel. One line of
frontmatter does it:

```yaml
---
enableToc: false
---
```

Every class page in [[All Classes/index|All Classes]] uses this.

---

## Callouts

Callouts lift something out of the flow of the page. There are a dozen
kinds, each with its own colour and icon, so students learn to recognise
them at a glance.

> [!note] Note
> Neutral information worth setting apart.

> [!tip] Tip
> A habit or a shortcut that makes the work easier.

> [!important] Important
> The one thing to take away if you take away nothing else.

> [!warning] Warning
> Where people usually go wrong.

> [!question] Question
> Something to think about rather than something to know.

> [!quote] Quote
> Used in this course for epigraphs and for lines worth sitting with.

> [!abstract] At a glance
> Used at the top of task pages for the format, the deadline, and what is
> assessed.

**How that was made:** a blockquote with the kind named in brackets.

```markdown
> [!warning] Where people usually go wrong
> The text of the callout goes here.
```

### Foldable callouts

Add a `-` after the kind to start it collapsed — useful for answers,
hints, and anything a reader should attempt before seeing.

> [!success]- A worked answer (click to expand)
> Offred's narration keeps correcting itself — "I made that up. It didn't
> happen that way." The novel is not unreliable by accident; it is about
> the conditions under which a testimony gets made.

---

## Tables

**How that was made:** rows of text separated by `|`, with a line of
dashes under the headings.

| Device | What it does | Where we meet it |
| --- | --- | --- |
| Simile | Compares using *like* or *as* | *The Handmaid's Tale* |
| Allusion | Points at another text or event | *Hamlet* |
| Juxtaposition | Sets two things side by side to make a point | *Fifteen Dogs* |

---

## Quoting at length

> There is nothing either good or bad,
> but thinking makes it so.

Two lines of *Hamlet*, set as a block quotation because verse
is quoted line by line. Block quotations take no quotation marks — the
indent does that job, and the line break is preserved because in verse
the line break is meaning. The conventions are on
[[Writing About Literature]].

**How that was made:** a `>` at the start of each line.

---

## Checklists

**How that was made:** a list where each line starts with `- [ ]`, or
`- [x]` for one already done.

- [ ] Draft finished
- [x] Read aloud once
- [ ] Checked against the criteria on the task page

On the site each student can tick them; the ticks stay in their own
browser, nobody else sees them, and changing a line's words clears its
tick. Ticked as you go, they are useful for keeping your place.

---

## Diagrams

Diagrams here are **written, not drawn**, which means they can be edited
in seconds and never need a graphics program.

```mermaid
graph LR
    A["Reading"] --> B["Talking about it"]
    B --> C["Writing about it"]
    C --> D["Reading better"]
    D --> A
```

**How that was made:** not a picture — these lines of text, between two
fence lines that say `mermaid`.

````markdown
```mermaid
graph LR
    A["Reading"] --> B["Talking about it"]
```
````

A timeline, which is useful when a course reads across a century:

```mermaid
timeline
    title Four texts, in the order they were published
    1601 : Shakespeare : Hamlet
    1985 : Margaret Atwood : The Handmaid's Tale
    2015 : André Alexis : Fifteen Dogs
    2016 : Katherena Vermette : The Break
```

---

## Transclusion — one page inside another

`![[Page name]]` pulls a whole page in live rather than copying it. Here
is this course's help-session page, embedded:

![[Help Sessions]]

Change the source page and every page that embeds it updates. That is how
each section's landing page always shows the current class, and how every
task page shows the curriculum expectations it addresses without anybody
maintaining two copies.

---

## Backlinks

At the foot of most pages is **When did we do this?** — every page that
links here, gathered automatically. Open [[Narration and Testimony]] and you can
see every class that used the idea, in order, without anybody keeping a
list.

---

## Things this course does not need, which the site can still do

An English course has no equations and no code. The software supports
both, and a teacher moving a different subject onto this site should know
that:

Mathematics, set with the same typesetting system journals use:

$$\text{marks} = \frac{\text{what you can do}}{\text{what was asked}} \times 100\%$$

Code, with the language named so it is coloured properly:

```python
words = open("essay.txt").read().split()
print(len(words), "words")
```

Neither appears anywhere else in this course. They are here because the
question "can it do…?" deserves an answer you can see.

---

## Holding a page back

A page with `publish: false` in its frontmatter is skipped entirely when
the site is built. That is how tomorrow's class page can be written today
and published when the class actually happens.

```yaml
---
publish: false
---
```

---

## What all of this is for

| Feature | The problem it removes |
| --- | --- |
| Transclusion | The same text copied into six places, five of them stale |
| Backlinks | "Where did we do this again?" |
| Callouts | Important things lost in a wall of paragraphs |
| Diagrams as text | Rebuilding a whole diagram to change one arrow |
| Holding a page back | Keeping unpublished plans in some other file somewhere |

Write it once, link to it everywhere.
