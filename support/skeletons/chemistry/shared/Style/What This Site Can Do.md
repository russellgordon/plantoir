---
title: What This Site Can Do
publish: true
created: __CREATED__
enableToc: true
tags:
  - reference
  - style
---
This page has two audiences. Students: it explains why the notes look the
way they do. Teachers: it is a working reference for everything you can put
in a page, with the source shown beside every example.

Everything below is written in **Markdown** — plain text with a few marks of
punctuation that mean something. If you can write a text message, you can
write this.

---

## Text that carries meaning

You get **bold**, *italic*, ~~struck through~~, and ==highlighted== text.
Highlighting is the one worth knowing: it catches the eye better than bold
when a single ==important phrase== has to stand out inside a paragraph.

**How that was made:**

```markdown
**bold**, *italic*, ~~struck through~~, ==highlighted==
```

Arrows written as `->` become proper arrows, and keyboard keys look like
keys: press <kbd>⌘</kbd> + <kbd>K</kbd> to search.

---

## Headings, and the table of contents

Every `##` heading becomes a link in **Navigate this page**, over on the
right. Nothing builds that list by hand — it is assembled from the headings
as the page is built, so it can never fall out of step with the page it
describes.

**How that was made:** `##` at the start of a line, and `###` for a
sub-heading.

### Turning it off

A short page reads better without a contents panel. One line in the
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
kinds, each with its own colour and icon.

> [!note] Note
> Neutral information worth setting apart.

> [!tip] Tip
> A shortcut, a habit, or something that makes the work easier.

> [!important] Important
> The one thing to take away if you take away nothing else.

> [!warning] Warning
> Where people usually go wrong.

> [!example] Example
> A worked case.

**How that was made:** a blockquote with the kind named in brackets.

```markdown
> [!warning] Where people usually go wrong
> The text of the callout goes here.
```

### Foldable callouts

Add a `-` after the kind and the callout starts collapsed. Clicking the
title opens it. This is how answers and hints stay on the page without
giving themselves away.

> [!success]- Answer: click this line
> The hidden content sits here, out of sight until it is wanted.

```markdown
> [!success]- Answer: click this line
> The hidden content.
```

---

## Mathematics

Inline maths sits inside a sentence: the slope between two points is
$m = \frac{y_2 - y_1}{x_2 - x_1}$.

Display maths gets a line of its own, centred:

$$\begin{aligned} (a + b)^2 &= a^2 + 2ab + b^2 \\ &= a^2 + b^2 + 2ab \end{aligned}$$

**How that was made:** single dollar signs keep it in the sentence, double
ones give it a line of its own.

```markdown
Inline: $m = \frac{y_2 - y_1}{x_2 - x_1}$

Display: $$E = mc^2$$
```

> [!warning] For teachers: display maths stays on ONE physical line
> A `$$` span broken across lines, indented four spaces, or spread down a
> callout hits a markdown seam and shatters. Multi-step working goes on one
> line inside `\begin{aligned} … \end{aligned}`.

---

## Chemistry

Chemistry is written inside `\ce{...}`. Everything in there is read as
chemistry, so subscripts sit low, charges sit high, states sit in brackets,
and reaction arrows are arrows:

$$\ce{CaCO3(s) <=> CaO(s) + CO2(g)}$$

| What you type | What appears | What it means |
| --- | --- | --- |
| `$\ce{H2O}$` | $\ce{H2O}$ | Digits drop to subscripts |
| `$\ce{2H2O}$` | $\ce{2H2O}$ | A digit in front is a coefficient |
| `$\ce{SO4^2-}$` | $\ce{SO4^2-}$ | A charge, number before sign |
| `$\ce{NaCl(aq)}$` | $\ce{NaCl(aq)}$ | A state, typed literally |
| `$\ce{2H2 + O2 -> 2H2O}$` | $\ce{2H2 + O2 -> 2H2O}$ | The reaction arrow |
| `$\ce{AgCl v}$` | $\ce{AgCl v}$ | Precipitate down, gas up |

---

## Diagrams

Diagrams are **written, not drawn** — which means they can be edited in
seconds, they never need a graphics program, and a change to one shows up
in a diff.

```mermaid
graph LR
    A["A question"] --> B["Something you try"]
    B --> C["What you noticed"]
    C --> D["What you would do differently"]
```

**How that was made:** not a picture — those lines of text, between two
fence lines that say `mermaid`.

````markdown
```mermaid
graph LR
    A["A question"] --> B["Something you try"]
```
````

---

## Tables

| Column | Column | Column |
| --- | --- | --- |
| Rows of text | separated by | vertical bars |
| with a line of | dashes under | the headings |

Maths works inside table cells, and so do links — which matters more than
it sounds, because a summary table can then be a navigation aid rather than
a dead end.

> [!note] For teachers: escape the pipe inside a table cell
> A wikilink with different display words uses a pipe, and so does the
> table. Inside a cell, write `[[Page\|the words shown]]` with a backslash,
> or the row splits into an extra column.

---

## Checklists

- [ ] A line that starts with `- [ ]`
- [x] One already done, written `- [x]`

On the site each student can tick them; the ticks stay in their own
browser, nobody else sees them, and changing a line's words clears its
tick. Ticked as you go, they are useful for keeping your place.

---

## Links between pages

This is what makes the site more than a pile of documents.

- A plain link: [[How This Site Is Organised]]
- A link with different words:
  [[How This Site Is Organised|where everything lives]]

```markdown
[[How This Site Is Organised]]
[[How This Site Is Organised|different words for the link]]
```

### Transclusion — one page inside another

`![[Page name]]` pulls a whole page in live rather than copying it. Below,
the help-session times are pulled in:

![[Help Sessions]]

Change the source page and every page that embeds it updates. That is how
a section's landing page always shows the current class without anybody
maintaining a second copy of it.

### Backlinks

Scroll to the bottom of any page and you will find **Backlinks** — every
page that links *to* this one, gathered automatically. Nobody maintains
that list, which is why linking generously costs nothing.

---

## Hover previews

Hover over [[Using This Site]] without clicking. The page appears in a
small window, so checking one thing does not cost you your place.

---

## Footnotes

**How that was made:** `[^1]` where the marker goes, and a matching `[^1]:`
line anywhere in the page.[^1]

[^1]: Like this. Footnotes collect at the bottom no matter where you write
    them, so you can put the note next to the sentence it belongs to.

---

## Tags

```yaml
---
tags:
  - reference
  - setup
---
```

Every tag becomes a page listing everything filed under it.

---

## What you cannot see

Two things on this page are invisible in the browser:

1. **Comments.** Text wrapped in `%%` double percent marks `%%` never
   reaches the site. Useful for notes to yourself in a page you are still
   writing.
2. **Holding a page back.** A page with `publish: false` in its
   frontmatter is skipped entirely when the site is built. Write next
   week's lesson today and publish it when you are ready.

%% This sentence is a comment. If you can read it on the website,
something is broken. %%

> [!tip] For teachers reading this
> A shared page can be published to one section and held back from another
> using per-section `publishForSection1` / `publishForSection2` keys in the
> frontmatter — useful when two classes have drifted a few days apart.

---

## The point of all this

None of it is decoration. Each feature removes a reason for a page to go
out of date:

| Feature | The problem it solves |
| --- | --- |
| Transclusion | The same text copied into six places, five of them stale |
| Backlinks | "Where did we use this again?" |
| Diagrams as text | Rebuilding a whole diagram to change one arrow |
| Drafts | Keeping unpublished work in some other file somewhere |
| Hover previews | Losing your place to check one thing |

Write it once, link to it everywhere.
