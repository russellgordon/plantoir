---
title: What This Site Can Do
publish: true
created: __CREATED__
enableToc: true
tags:
  - reference
---
This page has two audiences. Students: it explains why the notes look
the way they do. Teachers: it is a working reference for everything you
can put in a page, with the source shown beside every example.

Everything below is written in **Markdown** — plain text with a few
marks of punctuation that mean something. If you can write a text
message, you can write this.

---

## Text that carries meaning

You get **bold**, *italic*, ~~struck through~~, and ==highlighted==
text. Highlighting is the one worth knowing: it catches the eye better
than bold when a single phrase such as ==equal rates, not equal
amounts== has to stand out inside a paragraph.

**How that was made:**

```markdown
**bold**, *italic*, ~~struck through~~, ==highlighted==
```

Arrows written as `->` become proper arrows: model -> prediction ->
measurement -> boundary.

Keyboard keys look like keys: press <kbd>⌘</kbd> + <kbd>K</kbd> to
search.

---

## Headings, and the table of contents

Every `##` heading becomes a link in **Navigate this page**, over on the
right. Nothing builds that list by hand — it is assembled from the
headings as the page is built, so it can never fall out of step with the
page it describes.

Deeper headings nest underneath: a `###` sits inside the `##` above it.

**How that was made:** `##` at the start of a line, and `###` for a
sub-heading.

```markdown
## Callouts

### Foldable callouts
```

> [!tip] Write headings for the person skimming
> The table of contents is the first thing many students read.
> "Significant figures for a logarithm" tells them what is there;
> "More on this" does not.

### Turning it off

A short page, or one that is mostly a list, reads better without a
contents panel. One line in the frontmatter:

```yaml
---
enableToc: false
---
```

Every class page in [[All Classes/index|All Classes]] uses this. Open
[[Unit 1, Day 1]] and there is no "Navigate this page" panel, even
though the page has headings that would otherwise appear there — an
agenda of six items does not need navigating.

---

## Callouts

Callouts lift something out of the flow of the page. There are a dozen
kinds, each with its own colour and icon, so students learn to recognise
them at a glance.

> [!note] Note
> Neutral information worth setting apart.

> [!tip] Tip
> A shortcut, a habit, or something that makes the work easier.

> [!important] Important
> The one thing to take away if you take away nothing else.

> [!warning] Warning
> Where people usually go wrong.

> [!danger] Safety
> Used in this course only for physical safety in the lab.

> [!question] Question
> Something to think about rather than something to know.

> [!example] Example
> A worked case.

> [!abstract] At a glance
> Used at the top of task pages for the format and what is due.

**How that was made:** a blockquote with the kind named in brackets.

```markdown
> [!warning] Where people usually go wrong
> The text of the callout goes here.
```

### Foldable callouts

Add a `-` after the kind and the callout starts collapsed, opening when
its title is selected. This is how answers, hints, and worked solutions
stay on the page without giving themselves away.

> [!success]- Answer: what is the pH of a solution in which the hydronium concentration is $3.4 \times 10^{-3}$ mol/L?
> $\text{pH} = -\log(3.4 \times 10^{-3}) = 2.47$ — two decimal places,
> because the concentration had two significant figures. See
> [[Working with Logarithms in Chemistry]].

**How that was made:** the `-` after the kind is the whole difference.

```markdown
> [!success]- Answer: the question goes in the title
> The hidden content.
```

---

## Mathematics and chemistry

Inline maths sits inside a sentence: at 25 °C the ion product of water
is $K_w = 1.0 \times 10^{-14}$, so a solution with
$[\ce{H3O+}] = 1.0 \times 10^{-3}$ mol/L has
$[\ce{OH-}] = 1.0 \times 10^{-11}$ mol/L.

Display maths gets a line of its own, centred:

$$K_c = \frac{[\ce{C}]^c [\ce{D}]^d}{[\ce{A}]^a [\ce{B}]^b} \qquad \text{pH} = -\log[\ce{H3O+}] \qquad Q = mc\Delta T$$

Chemistry is written inside `\ce{...}`. Everything in there is read as
chemistry, so subscripts sit low, charges sit high, states sit in
brackets, and reaction arrows are arrows rather than a hyphen and a
greater-than sign:

$$\ce{N2O4(g) <=> 2NO2(g)}$$

$$\ce{CH3COOH(aq) + H2O(l) <=> CH3COO-(aq) + H3O+(aq)}$$

The double arrow is written `<=>` and it is not
decoration — it is the claim that both directions are running at once,
which is the whole of [[Dynamic Equilibrium]].

Multi-step working goes on a single line, aligned on the equals signs:

$$\begin{aligned} q &= mc\Delta T = (100.0\ \text{g})(4.18\ \text{J/g}^\circ\text{C})(6.4\ ^\circ\text{C}) \\ &= 2.68 \times 10^3\ \text{J} \end{aligned}$$

**How that was made:** single dollar signs keep it in the sentence,
double ones give it a line of its own.

```markdown
Inline: $K_w = 1.0 \times 10^{-14}$

Display: $$\ce{N2O4 <=> 2NO2}$$
```

### Writing chemistry with `\ce{}`

Everything chemical on this site is typed inside `\ce{}`, and it is worth
ten minutes once. You type roughly what you would say aloud; it works out
which digits are subscripts, which are coefficients, and where the
spacing goes.

| What you type | What appears | What it means |
| --- | --- | --- |
| `$\ce{H2O}$` | $\ce{H2O}$ | Digits drop to subscripts |
| `$\ce{2H2O}$` | $\ce{2H2O}$ | A digit in front is a coefficient |
| `$\ce{SO4^2-}$` | $\ce{SO4^2-}$ | A charge, number before sign |
| `$\ce{Ca(OH)2}$` | $\ce{Ca(OH)2}$ | Brackets as you write them |
| `$\ce{CH3COOH(aq)}$` | $\ce{CH3COOH(aq)}$ | A state, typed literally |
| `$\ce{N2 + 3H2 -> 2NH3}$` | $\ce{N2 + 3H2 -> 2NH3}$ | The reaction arrow |
| `$\ce{N2O4(g) <=> 2NO2(g)}$` | $\ce{N2O4(g) <=> 2NO2(g)}$ | The equilibrium arrow |
| `$\ce{Fe^3+ + e- -> Fe^2+}$` | $\ce{Fe^3+ + e- -> Fe^2+}$ | Electrons behave like ions |
| `$\ce{CH3-CH=CH2}$` | $\ce{CH3-CH=CH2}$ | Single and double bonds |
| `$\ce{CuSO4 * 5H2O}$` | $\ce{CuSO4 * 5H2O}$ | The dot in a hydrate |
| `$\ce{->[catalyst]}$` | $\ce{->[catalyst]}$ | A condition above the arrow |
| `$\ce{BaSO4 v}$` | $\ce{BaSO4 v}$ | Precipitate down, gas up |

Two habits worth keeping:

- **Anything chemical goes inside `\ce{}`**, including a formula in the
  middle of a sentence, like $\ce{NaHCO3}$. Outside it, `H_2O` comes out
  in maths italic — the convention for *variables*, which reads wrongly
  for an element.
- **A display equation stays on one physical line.** A `$$` span broken
  across lines, indented four spaces, or spread down a callout hits a
  markdown seam and shatters.

> [!note] For teachers: ICE tables are tables
> The temptation is to typeset an ICE table as an aligned maths block.
> Do not. It is a table of three rows and it should be written as a
> markdown table — it stays readable in the source, it reflows on a
> phone, and the numbers can be copied out of it.

---

## Diagrams

Diagrams are **written, not drawn** — which means they can be edited in
seconds, they never need a graphics program, and a change to one shows
up in a diff.

### Flowchart

```mermaid
graph LR
    A["Question"] --> B["Model, and what it assumes"]
    B --> C["Prediction with a direction"]
    C --> D["Design and run it"]
    D --> E["Data, with units and a temperature"]
    E --> F{"Does it agree, within the uncertainty?"}
    F -->|yes| G["State the result and the model's boundary"]
    F -->|no| H["Which of the two was wrong — you, or the model?"]
```

**How that was made:** not a picture — these lines of text, between two
fence lines that say `mermaid`.

````markdown
```mermaid
graph LR
    A["Question"] --> B["Model, and what it assumes"]
    B --> C["Prediction with a direction"]
    C --> D["Design and run it"]
```
````

`-->` draws an arrow, `["…"]` makes a box, `{"…"}` makes a decision
diamond, and `-->|yes|` labels the arrow. Change a word and the diagram
redraws.

### Processes

```mermaid
graph TD
    C["Concentration, in mol/L"] -->|"take the negative logarithm"| P["pH"]
    P -->|"raise ten to the minus pH"| C
    P -->|"subtract from 14.00 at 25 °C"| O["pOH"]
    O -->|"raise ten to the minus pOH"| H["Hydroxide concentration"]
```

That diagram is most of [[Working with Logarithms in Chemistry]] in four
boxes, which is roughly the point of drawing it.

### Proportions

```mermaid
pie title How the term mark is built
    "Thinking and investigation" : 30
    "Knowledge and understanding" : 25
    "Application" : 25
    "Communication" : 20
```

Those are the four achievement categories, weighted as
[[How Marks Work]] describes.[^1]

---

## Tables

**How that was made:** rows of text separated by `|`, with a line of
dashes under the headings.

| Quantity | Symbol | Depends on temperature? | Where it turns up |
| --- | --- | --- | --- |
| Equilibrium constant | $K_c$ | Yes | [[Dynamic Equilibrium\|what settles, and where]] |
| Acid ionisation constant | $K_a$ | Yes | [[Acids and Bases]] |
| Enthalpy change | $\Delta H$ | Stated at a temperature | [[Enthalpy]] |
| Standard cell potential | $E^\circ_{\text{cell}}$ | Yes, and on concentration | [[Reading a Reduction Potential Table]] |

Maths works inside table cells, and so do links — which matters more
than it sounds, because it means a summary table can be a navigation aid
rather than a dead end.

> [!note] For teachers: escape the pipe inside a table cell
> A wikilink with different display words uses a pipe, and so does the
> table. Inside a table cell, write
> `[[Dynamic Equilibrium\|what settles]]` with a backslash, or the row
> splits into an extra column.

---

## Checklists

**How that was made:** a list where each line starts with `- [ ]`, or
`- [x]` for one already done.

- [ ] Eye protection on
- [ ] Fume hood running, if solvents are open
- [x] Model named and its assumptions written down
- [ ] Prediction recorded before measuring
- [ ] Waste route confirmed — drain, organic, or metal ion
- [ ] Station cleaned

On the site they are read-only — the boxes show what the page says, and
clicking one does nothing. Copied into a notebook, they are useful for
keeping your place during a lab.

---

## Code

**How that was made:** three backticks and the name of a language, the
code, then three backticks to close it.

````markdown
```python
import math

def ph(hydronium_concentration):
    return -math.log10(hydronium_concentration)
```
````

```python
import math

def ph(hydronium_concentration):
    return -math.log10(hydronium_concentration)

print(round(ph(3.4e-3), 2))
```

Syntax colouring follows the language you name after the opening fence
and adapts to light or dark mode. **This course does not ask you to
write any code** — it is here because the site supports it, and a
teacher adapting these pages for a computer science course will want to
know.

---

## Links between pages

This is what makes the site more than a pile of documents.

- A plain link: [[Dynamic Equilibrium]]
- A link with different words:
  [[Le Chatelier's Principle|what a disturbed system does next]]
- A link to a section:
  [[Dynamic Equilibrium#Stopped is the wrong word]]

**How that was made:** double square brackets, with a vertical bar where
the words on the page should differ from the file name. That is how the
accent survives here: the file is named without one so that every
computer can open it, and the bar puts it back for the reader.

```markdown
[[Dynamic Equilibrium]]
[[Le Chatelier's Principle|Le Châtelier's Principle]]
[[Dynamic Equilibrium#Stopped is the wrong word]]
```

### Transclusion — one page inside another

**How that was made:** `![[Page name]]` — a link with an exclamation
mark in front of it. Below, the help-session times are pulled in live
rather than copied:

![[Help Sessions]]

Change the source page and every page that embeds it updates. That is
how a section landing page always shows the current class agenda without
anybody maintaining a second copy of it. It is also how the curriculum
expectations appear at the foot of a concept page — the wording lives in
one file and is quoted everywhere it applies.

### Backlinks

Scroll to the bottom of any page and you will find **Backlinks** — every
page that links *to* this one, gathered automatically. Nobody maintains
that list, which is why linking generously costs nothing and pays off
later.

---

## Hover previews

Hover over [[Buffers and Titration Curves]] without selecting it. The
page appears in a small window. A student checking one definition in the
middle of a calculation does not lose their place — which, in a course
with this much looking-up in it, is the feature they will use most.

---

## Footnotes

**How that was made:** `[^1]` where the marker goes, and a matching
`[^1]:` line anywhere in the page.

[^1]: The remaining 30% of the final mark sits outside the term work
    entirely, in the final assessment — the showcase and the
    examination together. A pie chart of the term mark is therefore a
    true picture of one thing and a misleading picture of another,
    which is a reasonable demonstration of why every chart needs its
    title read as carefully as its slices.

---

## Tags

**How that was made:** a `tags` list in the frontmatter at the very top
of the page.

```yaml
---
tags:
  - equilibrium
  - safety
---
```

Every tag becomes a page listing everything filed under it.

---

## What you cannot see

Two things on this page are invisible in the browser:

1. **Comments.** Text wrapped in `%%` double percent marks `%%` never
   reaches the site. Useful for notes to yourself in a page you are
   still writing.
2. **Holding a page back.** A page with `publish: false` in its
   frontmatter is skipped entirely when the site is built. Write next
   week's lesson today and publish it when you are ready.

%% This sentence is a comment. If you can read it on the
website, something is broken. %%

> [!tip] For teachers reading this
> A shared page can also be published to one section and held back from
> another: look at the top of this page's source and you will find a
> `createdSection1` / `publishForSection1` pair for each of your
> sections. Set one section's key to `false` and the page waits for
> that class — useful when your two classes have drifted a few days
> apart and one of them has not run the titration yet.

---

## The point of all this

None of it is decoration. Each feature removes a reason for a page to go
out of date:

| Feature | The problem it solves |
| --- | --- |
| Transclusion | The same text copied into six places, five of them stale |
| Backlinks | "Where did we use this again?" |
| Diagrams as text | Rebuilding a whole diagram to change one arrow |
| Holding a page back | Keeping unpublished work in some other file somewhere |
| Typeset chemistry | Screenshotting equations out of a document |
| Hover previews | Losing your place to check one constant |

Write it once, link to it everywhere.
