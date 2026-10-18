---
title: What This Site Can Do
publish: true
created: __CREATED__
enableToc: true
tags:
  - reference
---
This page exists for two audiences. Students: it shows why the notes look the
way they do. Teachers: it is a working reference for everything you can put in a
page, with the source visible in every example.

Everything below is written in **Markdown** — plain text with a few marks of
punctuation that mean something. If you can write a text message, you can write
this.

---

## Text that carries meaning

You get **bold**, *italic*, ~~struck through~~, and ==highlighted== text.
Highlighting is the one worth knowing: it draws the eye better than bold when
you want a single ==key term== to stand out in a paragraph.

**How that was made:**

```markdown
**bold**, *italic*, ~~struck through~~, ==highlighted==
```

Arrows written as `->` become proper arrows: rehearse -> refine -> perform.

Keyboard keys look like keys: press <kbd>⌘</kbd> + <kbd>K</kbd> to search.

---

## Headings, and the table of contents

Every `##` heading on a page becomes a link in **Navigate this page**, over on
the right. Nothing builds that list by hand — it is made from the headings as
the page is built, so it can never fall out of step with the page.

Deeper headings nest underneath: a `###` sits inside the `##` above it, which
is why "Foldable callouts" appears indented under "Callouts".

**How that was made:** `##` at the start of a line, and `###` for a
sub-heading.

```markdown
## Callouts

### Foldable callouts
```

> [!tip] Write headings for the person skimming
> The table of contents is the first thing many students read. "Rehearsal
> checklist" tells them what is there; "More on this" does not.

### Turning it off

A short page, or one that is mostly a list, reads better without a contents
panel. Add one line to the frontmatter:

```yaml
---
enableToc: false
---
```

Every class page in [[All Classes/index|All Classes]] uses this. Open
[[Unit 1, Day 1]] and you will see no "Navigate this page" panel on the right,
even though the page has headings that would otherwise appear there — an agenda
of six items does not need navigating.

---

## Callouts

Callouts pull something out of the flow of the page. There are a dozen kinds and
each has its own colour and icon, so students learn to recognise them at a
glance.

> [!note] Note
> Neutral information worth setting apart.

> [!tip] Tip
> A shortcut, a habit, or something that makes the work easier.

> [!important] Important
> The one thing to take away if you take away nothing else.

> [!warning] Warning
> Where people usually go wrong.

> [!danger] Safety
> Used in this course for physical and emotional safety — see
> [[Our Ensemble Agreement]].

> [!question] Question
> Something to think about rather than something to know.

> [!example] Example
> A worked case.

> [!abstract] At a glance
> Used at the top of task pages for due dates and format.

**How that was made:** a blockquote with the kind named in brackets.

```markdown
> [!warning] Where people usually go wrong
> The text of the callout goes here.
```

### Foldable callouts

Add a `-` to start a callout collapsed — useful for hints, side-coaching notes,
and anything you do not want an audience to see immediately.

> [!success]- One strong choice for a frozen image (click to expand)
> Put one person on the floor, one at full height, and one in between —
> three levels, and suddenly the picture has somewhere for the eye to go.

**How that was made:** the `-` after the kind is the whole difference.

```markdown
> [!success]- One strong choice (click to expand)
> The hidden content.
```

---

## Diagrams

Diagrams are **written, not drawn** — which means they can be edited in seconds
and never need a graphics program.

### Flowchart

```mermaid
graph LR
    A["Choose a source"] --> B["Explore it in role"]
    B --> C["Shape a scene"]
    C --> D["Rehearse"]
    D --> E{"Does it land with an audience?"}
    E -->|yes| F["Perform it"]
    E -->|no| B
```

**How that was made:** not a picture — these lines of text, between two fence
lines that say `mermaid`.

````markdown
```mermaid
graph LR
    A["Choose a source"] --> B["Explore it in role"]
    B --> C["Shape a scene"]
    C --> D["Rehearse"]
    D --> E{"Does it land with an audience?"}
    E -->|yes| F["Perform it"]
    E -->|no| B
```
````

`-->` draws an arrow, `["…"]` makes a box, `{"…"}` makes a decision diamond,
and `-->|yes|` labels the arrow. Change a word and the diagram redraws — no
graphics program, and the change shows up in a diff.

### Proportions

```mermaid
pie title Where rehearsal time goes
    "Blocking and stage picture" : 30
    "Running lines and cues" : 30
    "Trying alternatives" : 25
    "Polishing transitions" : 15
```

### Sequence

Who says what to whom, in order — here, how a lighting cue gets called:

```mermaid
sequenceDiagram
    participant SM as Stage manager
    participant LX as Lighting operator
    participant A as Actors
    SM->>LX: "LX 12, stand by"
    LX->>SM: "Standing by"
    A->>SM: Line that ends the scene
    SM->>LX: "LX 12, go"
    LX->>A: Lights shift
```

### Timeline

```mermaid
timeline
    title Stages through history
    500 BCE : Greek amphitheatre : chorus and masks
    1600 : Elizabethan thrust stage : audience on three sides
    1870 : Proscenium arch : the "picture frame"
    1960 : Black box : the room itself is flexible
```

---

## Tables

**How that was made:** rows of text separated by `|`, with a line of dashes
under the headings.

| Element | What it asks | A question to test it |
| --- | --- | --- |
| Role | Who am I in this? | What does this person want? |
| Tension | What pulls against what? | What is at stake right now? |
| Focus | Where should the audience look? | What is this moment about? |

---

## Checklists

**How that was made:** a list where each line starts with `- [ ]`, or `- [x]`
for one already done.

- [ ] Space cleared and swept
- [ ] Phones away, voices warm
- [x] Group knows its running order
- [ ] Props set on the prop table

On the site each student can tick them; the ticks stay in their own
browser, nobody else sees them, and changing a line's words clears its
tick. Ticked as you go, they are useful for keeping your place while
setting up a performance.

---

## Links between pages

This is what makes the site more than a pile of documents.

- A plain link: [[Tableau]]
- A link with different words: [[Tableau|a frozen stage picture]]
- A link to a section: [[Tableau#Making one worth looking at]]

**How that was made:** double square brackets.

```markdown
[[Tableau]]
[[Tableau|different words for the link]]
[[Tableau#Making one worth looking at]]
```

### Transclusion — one page inside another

**How that was made:** `![[Page name]]` — a link with an exclamation mark in
front of it.
%%curriculum-start%%
Here is a curriculum expectation, embedded live rather than copied:

![[A2.2]]

Change the source page and every page that embeds it updates. This is how each
task page shows the expectations it addresses without anyone maintaining
duplicates.
%%curriculum-end%%

### Backlinks

Scroll to the bottom of any page and you will find **Backlinks** — every page
that links *to* this one, gathered automatically. Nobody maintains that list.
It is why linking generously costs nothing and pays off later.

---

## Hover previews

Hover over [[Thought Tracking]] without clicking. The page appears in a small
window. Students checking one convention mid-paragraph do not lose their place.

---

## Footnotes

**How that was made:** `[^1]` where the marker goes, and a matching `[^1]:`
line anywhere in the page.

The word "tragedy" reaches us from a Greek word usually translated as "goat
song".[^1]

[^1]: Nobody is entirely sure why — theories involve prizes, sacrifices, and
    costumes. The uncertainty is half the fun.

---

## Tags

**How that was made:** a `tags` list in the frontmatter at the very top of the
page.

```yaml
---
tags:
  - conventions
  - unit-1
---
```

Every tag becomes a page listing everything filed under it.

---

## Mathematics (not used in this course — but here if you need it)

A drama course has no equations, so you will not meet these in our pages. The
site can typeset them anyway, which matters if you also teach a course that
needs them. Inline maths sits in a sentence, like $E = mc^2$; display maths
gets its own centred line:

$$
\text{sightline height} = \frac{\text{stage height} + \text{eye height}}{2}
$$

**How that was made:** single dollar signs keep it in the sentence, double
ones give it a line of its own.

```markdown
Inline: $E = mc^2$

Display:
$$
\text{a fraction} = \frac{\text{top}}{\text{bottom}}
$$
```

## Code (also not used in this course)

The same is true of program code: fence it with three backticks, name the
language, and it comes out coloured and exact — spacing preserved, quotation
marks untouched. Useful in computer science; here, only as proof it works.

```python
def call_cue(number):
    return f"LX {number}, go"
```

---

## What you cannot see

Two things on this page are invisible in the browser:

1. **Comments.** Text wrapped in `%%` double percent marks `%%` never reaches
   the site. Useful for notes to yourself in a page you are still writing —
   side-coaching reminders, casting ideas, next year's fixes.
2. **Holding a page back.** A page with `publish: false` in its frontmatter is
   left out when the site is built. Write next week's lesson today and publish
   it when you are ready. A page with no `publish` line is published, so
   forgetting it can never make your work vanish.

%% This sentence is a comment. If you can read it on the website, something is broken. %%

> [!tip] For teachers reading this
> With more than one section, per-section keys like `publishForSection1` and
> `publishForSection2` let one shared page be published to one class and held
> back from another — useful when your two sections are a few days apart.

---

## The point of all this

None of it is decoration. Each feature removes a reason for a page to be out of
date:

| Feature | The problem it solves |
| --- | --- |
| Transclusion | The same text copied into six places, five of them stale |
| Backlinks | "Where did we use this again?" |
| Diagrams as text | Rebuilding a diagram from scratch to change one arrow |
| Holding a page back | Keeping unpublished work in a separate file somewhere |
| Checklists | The performance-day scramble |

Write it once, link to it everywhere.
