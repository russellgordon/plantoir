---
title: What This Site Can Do
createdSection1: 2026-09-08T07:00:00.000-0400
publishForSection1: true
createdSection2: 2026-09-09T07:00:00.000-0400
publishForSection2: true
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

Arrows written as `->` become proper arrows: producers -> consumers ->
decomposers.

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
> The table of contents is the first thing many students read. "Worked
> example" tells them what is there; "More on this" does not.

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
> Used in this course only for physical safety in the lab.

> [!question] Question
> Something to think about rather than something to know.

> [!example] Example
> A worked case.

> [!abstract] At a glance
> Used at the top of assignment pages for due dates and format.

**How that was made:** a blockquote with the kind named in brackets.

```markdown
> [!warning] Where people usually go wrong
> The text of the callout goes here.
```

### Foldable callouts

Add a `-` to start a callout collapsed — useful for answers, hints, and solutions
you do not want a student to see immediately.

> [!success]- Answer to the practice question (click to expand)
> $I = \frac{V}{R} = \frac{12\ \mathrm{V}}{4.0\ \Omega} = 3.0\ \mathrm{A}$

**How that was made:** the `-` after the kind is the whole difference.

```markdown
> [!success]- Answer (click to expand)
> The hidden content.
```

---

## Mathematics

Inline maths sits in a sentence: the resistance is $R = 12\ \Omega$, giving a
current of $I = 0.50\ \mathrm{A}$.

Display maths gets its own line and is centred:

$$
\text{efficiency} = \frac{E_{\text{useful}}}{E_{\text{total}}} \times 100\%
$$

It handles anything a science course needs — fractions, subscripts,
superscripts, and Greek:

$$
\rho = \frac{m}{V} \qquad E = mc^2 \qquad \Delta T = T_f - T_i
$$

**How that was made:** single dollar signs keep it in the sentence, double
ones give it a line of its own.

```markdown
Inline: $R = 12\ \Omega$

Display:
$$
\rho = \frac{m}{V}
$$
```

### Writing chemistry with `\ce{}`

Chemistry goes inside `\ce{...}`, and it is worth ten minutes once. You
type roughly what you would say aloud, and it works out which digits drop
to subscripts, which are coefficients, and where the spacing belongs.

| What you type | What appears | What it means |
| --- | --- | --- |
| `$\ce{H2O}$` | $\ce{H2O}$ | Digits drop to subscripts |
| `$\ce{2H2O}$` | $\ce{2H2O}$ | A digit in front is a coefficient |
| `$\ce{Ca^2+}$` | $\ce{Ca^2+}$ | A charge — number first, then the sign |
| `$\ce{Ca(OH)2}$` | $\ce{Ca(OH)2}$ | Brackets as you write them |
| `$\ce{NaCl(aq)}$` | $\ce{NaCl(aq)}$ | A state, typed literally |
| `$\ce{2H2 + O2 -> 2H2O}$` | $\ce{2H2 + O2 -> 2H2O}$ | The reaction arrow |
| `$\ce{->[light]}$` | $\ce{->[light]}$ | A condition above the arrow |

That last row is how the photosynthesis equation on [[Photosynthesis]] is
written — one line of typing:

$$
\ce{6CO2 + 6H2O ->[light] C6H12O6 + 6O2}
$$

Two habits worth keeping:

- **Anything chemical goes inside `\ce{}`**, including a formula in the
  middle of a sentence, like $\ce{NaHCO3}$. Outside it, `H_2O` comes out
  in maths italic — the convention for *variables*, which reads wrongly
  for an element.
- **A display equation stays on one physical line.** A `$$` span broken
  across lines, indented four spaces, or spread down a callout hits a
  markdown seam and shatters.

---

## Diagrams

Diagrams are **written, not drawn** — which means they can be edited in seconds
and never need a graphics program.

### Flowchart

```mermaid
graph LR
    A["Question"] --> B["Hypothesis"]
    B --> C["Experiment"]
    C --> D["Data"]
    D --> E{"Does it support the hypothesis?"}
    E -->|yes| F["Report it"]
    E -->|no| B
```

**How that was made:** not a picture — these lines of text, between two fence
lines that say `mermaid`.

````markdown
```mermaid
graph LR
    A["Question"] --> B["Hypothesis"]
    B --> C["Experiment"]
    C --> D["Data"]
    D --> E{"Does it support the hypothesis?"}
    E -->|yes| F["Report it"]
    E -->|no| B
```
````

`-->` draws an arrow, `["…"]` makes a box, `{"…"}` makes a decision diamond,
and `-->|yes|` labels the arrow. Change a word and the diagram redraws — no
graphics program, and the change shows up in a diff.

### Cycles

```mermaid
graph TD
    ATM["Atmospheric CO2"] -->|photosynthesis| PLANT["Producers"]
    PLANT -->|respiration| ATM
    PLANT -->|death| SOIL["Decomposers"]
    SOIL -->|decomposition| ATM
```

### Proportions

```mermaid
pie title Composition of dry air
    "Nitrogen" : 78
    "Oxygen" : 21
    "Argon and everything else" : 1
```

### Sequence

```mermaid
sequenceDiagram
    participant S as Sun
    participant E as Earth
    participant A as Atmosphere
    S->>E: Visible light arrives
    E->>A: Surface radiates infrared
    A->>E: Some re-radiated downward
    A->>S: Some escapes to space
```

### Timeline

```mermaid
timeline
    title Models of the atom
    1803 : Dalton : solid sphere
    1897 : Thomson : plum pudding
    1911 : Rutherford : nucleus
    1913 : Bohr : shells
```

---

## Tables

**How that was made:** rows of text separated by `|`, with a line of dashes
under the headings.

| Quantity | Symbol | Unit | Instrument |
| --- | --- | --- | --- |
| Current | $I$ | ampere (A) | Ammeter |
| Potential difference | $V$ | volt (V) | Voltmeter |
| Resistance | $R$ | ohm ($\Omega$) | Ohmmeter |

Maths works inside table cells, which matters more than it sounds.

---

## Checklists

**How that was made:** a list where each line starts with `- [ ]`, or `- [x]`
for one already done.

- [ ] Goggles on
- [ ] Circuit checked by the teacher
- [x] Data table drawn before starting
- [ ] Station cleaned

On the site they are read-only — the boxes show what the page says, and
clicking one does nothing. Copied into a notebook, they are useful for
keeping your place during a lab.

---

## Code

**How that was made:** three backticks and the name of the language, the code,
then three backticks to close it.

````markdown
```python
def resistance(voltage, current):
    return voltage / current
```
````

```python
def resistance(voltage, current):
    return voltage / current

print(resistance(12.0, 3.0), "ohms")
```

```javascript
const efficiency = (useful, total) => (useful / total) * 100
console.log(efficiency(60, 1200))
```

Syntax colouring follows the language you name after the opening fence, and
adapts to light or dark mode.

---

## Links between pages

This is what makes the site more than a pile of documents.

- A plain link: [[Ohm's Law]]
- A link with different words: [[Ohm's Law|the relationship between V, I, and R]]
- A link to a section: [[Ohm's Law#Worked example]]

**How that was made:** double square brackets.

```markdown
[[Ohm's Law]]
[[Ohm's Law|different words for the link]]
[[Ohm's Law#Worked example]]
```

### Transclusion — one page inside another

**How that was made:** `![[Page name]]` — a link with an exclamation mark in
front of it. Here is another page of this site, embedded live rather than
copied:

![[Help Sessions]]

Change the source page and every page that embeds it updates. This is how each
class page shows the current expectation without anyone maintaining duplicates.

### Backlinks

Scroll to the bottom of any page and you will find **Backlinks** — every page
that links *to* this one, gathered automatically. Nobody maintains that list.
It is why linking generously costs nothing and pays off later.

---

## Hover previews

Hover over [[Photosynthesis]] without clicking. The page appears in a small
window. Students checking one definition mid-paragraph do not lose their place.

---

## Footnotes

**How that was made:** `[^1]` where the marker goes, and a matching `[^1]:`
line anywhere in the page.

Ontario's grid is unusually low-carbon compared with most of North America.[^1]

[^1]: Roughly 90% of Ontario's electricity comes from sources that emit little
    or no carbon dioxide while operating — mostly nuclear and hydroelectric.

---

## Tags

**How that was made:** a `tags` list in the frontmatter at the very top of the
page.

```yaml
---
tags:
  - biology
  - climate
---
```

Every tag becomes a page listing everything filed under it.

---

## What you cannot see

Two things on this page are invisible in the browser:

1. **Comments.** Text wrapped in `%%` double percent marks `%%` never reaches
   the site. Useful for notes to yourself in a page you are still writing.
2. **Holding a page back.** A page with `publish: false` in its frontmatter
   is skipped entirely when the site is built. Write next week's lesson today
   and publish it when you are ready.

%% This sentence is a comment. If you can read it on the website, something is broken. %%

> [!tip] For teachers reading this
> The per-section keys `publishForSection1` and `publishForSection2` let one
> shared page be published to one class and held back from another — useful
> when your two sections are a few days apart. Every Concepts page in this
> course uses them.

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
| Maths | Screenshotting equations from a document |

Write it once, link to it everywhere.
