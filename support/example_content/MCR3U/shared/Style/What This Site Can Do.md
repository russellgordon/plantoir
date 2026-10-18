---
title: What This Site Can Do
publish: true
created: __CREATED__
enableToc: true
tags:
  - reference
---
This page exists for two audiences. Students: it shows why the notes look
the way they do. Teachers: it is a working reference for everything you
can put in a page, with the source visible in every example.

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

Arrows written as `->` become proper arrows: estimate -> refine -> check.

Keyboard keys look like keys: press <kbd>⌘</kbd> + <kbd>K</kbd> to search.

---

## Mathematics, typeset properly

This is the feature a mathematics course lives on. Inline maths sits in
a sentence: the growth factor is $b = 1.05$, so each year the balance
keeps all of itself and adds five percent. Display maths gets its own
centred line:

$$
A = P\left(1 + i\right)^n = 500(1.05)^{10} \approx 814.45
$$

Fractions, exponents, roots, and symbols all come out exactly as they
should:

$$
8^{2/3} = \left(\sqrt[3]{8}\right)^2 = 4
\qquad
\sin 60^\circ = \frac{\sqrt{3}}{2}
\qquad
f(x) = a \sin(k(x - d)) + c
$$

**How that was made:** single dollar signs keep it in the sentence,
double ones give it a line of its own.

```markdown
Inline: $b = 1.05$

Display:
$$
A = P(1 + i)^n
$$
```

No more screenshotting equations out of a document — edit the text and
the mathematics re-typesets itself.

---

## Code (not used in this course — but here if you need it)

This course has no coding expectations, so you will not meet program
code in our pages. The site can carry it anyway — coloured, exact,
spacing preserved — which matters if you also teach a course that codes:

```python
def compound(principal, rate, years):
    return principal * (1 + rate) ** years

print(compound(500, 0.05, 10))   # 814.45
```

**How that was made:** three backticks and the language name, the code,
then three backticks to close it.

---

## Headings, and the table of contents

Every `##` heading on a page becomes a link in **Navigate this page**,
over on the right — built automatically from the headings, so it can
never fall out of step with the page. Deeper headings nest underneath.

A short page reads better without a contents panel; one frontmatter line
(`enableToc: false`) turns it off. Every class page in
[[All Classes/index|All Classes]] does this — an agenda of six items does
not need navigating.

---

## Callouts

Callouts pull something out of the flow of the page, each kind with its
own colour and icon:

> [!note] Note
> Neutral information worth setting apart.

> [!tip] Tip
> A shortcut, a habit, or something that makes the work easier.

> [!important] Important
> The one thing to take away if you take away nothing else.

> [!warning] Warning
> Where people usually go wrong — the $f(x - d)$ sign trap lives in
> boxes like this one.

> [!question] Question
> Something to think about rather than something to know.

> [!abstract] At a glance
> Used at the top of task pages for format and timing.

**How that was made:** a blockquote with the kind named in brackets.

```markdown
> [!warning] Where people usually go wrong
> The text of the callout goes here.
```

### Foldable callouts

Add a `-` to start a callout collapsed. Every practice set in
[[Exercises/index|Exercises]] hides its worked answers this way — try
before you peek, but the peek is always there:

> [!success]- Worked answer
> $8^{2/3} = \left(8^{1/3}\right)^2 = 2^2 = 4$ — root first, then
> power, because small numbers are kinder.

```markdown
> [!success]- Worked answer
> The hidden solution.
```

---

## Diagrams

Diagrams are **written, not drawn** — edited in seconds, never needing a
graphics program.

```mermaid
graph LR
    A["Plot the data"] --> B["Choose a function family"]
    B --> C["Tune the parameters"]
    C --> D{"Deserves belief?"}
    D -->|yes| E["Predict with it"]
    D -->|no| B
```

**How that was made:**

````markdown
```mermaid
graph LR
    A["Plot the data"] --> B["Choose a function family"]
    B --> C["Tune the parameters"]
    C --> D{"Deserves belief?"}
    D -->|yes| E["Predict with it"]
    D -->|no| B
```
````

Proportions draw themselves too:

```mermaid
pie title A first paycheque
    "Spending" : 55
    "Saving" : 20
    "Transit" : 15
    "Everything else" : 10
```

And history fits on a line:

```mermaid
timeline
    title Where our notation came from
    1637 : Descartes : x, y, and the coordinate plane
    1673 : Leibniz : first uses the word "function"
    1734 : Euler : writes f(x) for the first time
    1748 : Euler : ties sine to the circle, not the triangle
```

---

## Tables

**How that was made:** rows of text separated by `|`, with a line of
dashes under the headings. Mathematics works inside cells, which matters
more than it sounds.

| Representation | Shows best | Hides |
| --- | --- | --- |
| Table of values | Exact pairs | The overall shape |
| Graph | Shape and trend | Exact values |
| Equation $y = ab^x$ | The rule itself | What it feels like |

---

## Checklists

**How that was made:** a list where each line starts with `- [ ]`, or
`- [x]` for one already done.

- [ ] Estimate before calculating
- [x] Units carried through the whole solution
- [ ] Answer sentence written
- [ ] Someone else could follow this page

On the site each student can tick them; the ticks stay in their own
browser, nobody else sees them, and changing a line's words clears its
tick. Ticked as you go, they are how [[Showing Your Thinking]] turns from
advice into habit.

---

## Links between pages

This is what makes the site more than a pile of documents.

- A plain link: [[Sinusoidal Functions]]
- A link with different words: [[Sinusoidal Functions|the mathematics of tides]]
- A link to a section: [[Checking Your Own Work#Check the units]]

**How that was made:** double square brackets.

```markdown
[[Sinusoidal Functions]]
[[Sinusoidal Functions|different words for the link]]
[[Checking Your Own Work#Check the units]]
```

### Transclusion — one page inside another

**How that was made:** `![[Page name]]` — a link with an exclamation mark
in front of it. Here is the help-session schedule, embedded live rather
than copied:

![[Help Sessions]]

Change the source page and every page that embeds it updates. This is
how task pages show the curriculum expectations they address, and how
one schedule stays correct everywhere it appears, without anyone
maintaining duplicates.

### Backlinks

Scroll to the bottom of any page and you will find **Backlinks** — every
page that links *to* this one, gathered automatically. Open
[[The Exponential Function]] and its backlinks list every exploration,
task, and practice set that leans on it. Nobody maintains that list.

---

## Hover previews

Hover over [[Getting Unstuck]] without clicking. The page appears in a
small window. Checking one definition mid-problem does not cost you your
place.

---

## Footnotes

**How that was made:** `[^1]` where the marker goes, and a matching
`[^1]:` line anywhere in the page.

The word "sine" is the result of a translation accident.[^1]

[^1]: The Sanskrit *jya* (bowstring) became the Arabic *jiba*, which a
    medieval translator misread as *jayb* (bay or fold) and rendered
    into Latin as *sinus*. Every sine curve in this course carries a
    twelfth-century typo in its name.

---

## Tags

**How that was made:** a `tags` list in the frontmatter at the very top
of the page.

```yaml
---
tags:
  - concepts
  - unit-2
---
```

Every tag becomes a page listing everything filed under it.

---

## What you cannot see

Two things on this page are invisible in the browser:

1. **Comments.** Text wrapped in `%%` double percent marks `%%` never
   reaches the site. Useful for notes to yourself in a page you are
   still writing — tomorrow's hint, next year's fix.
2. **Holding a page back.** A page with `publish: false` in its
   frontmatter is skipped entirely when the site is built. Write next
   week's lesson today and publish it when you are ready.

%% This sentence is a comment. If you can read it on the website, something is broken. %%

> [!tip] For teachers reading this
> With more than one section, per-section keys like `publishForSection1`
> and `publishForSection2` let one shared page be published to one class
> and held back from another — useful when your two sections sit a few
> days apart.

---

## The point of all this

None of it is decoration. Each feature removes a reason for a page to be
out of date:

| Feature | The problem it solves |
| --- | --- |
| Typeset maths | Screenshotted equations nobody can edit |
| Transclusion | The same text copied into six places, five stale |
| Backlinks | "Where did we use this again?" |
| Folded answers | Solutions that spoil the attempt |
| Holding a page back | Next week's lesson in a separate file somewhere |

Write it once, link to it everywhere.
