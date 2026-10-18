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

Arrows written as `->` become proper arrows: secant -> secant -> tangent.

Keyboard keys look like keys: press <kbd>⌘</kbd> + <kbd>K</kbd> to search.

---

## Mathematics, typeset properly

This is the feature a calculus course lives on. Inline maths sits in a
sentence: an average speed is a plain fraction, like
$\frac{150 \text{ km}}{2 \text{ h}} = 75$ km/h. Display maths gets its
own centred line — and this course's central definition deserves one:

$$
f'(x) = \lim_{h \to 0} \frac{f(x+h) - f(x)}{h}
$$

Fractions, limits, vectors, and symbols all come out exactly as they
should:

$$
\frac{d}{dx}\sin x = \cos x
\qquad
\vec{u} \cdot \vec{v} = |\vec{u}|\,|\vec{v}|\cos\theta
\qquad
\lim_{x \to 3} \frac{x^2 - 9}{x - 3} = 6
$$

**How that was made:** single dollar signs keep it in the sentence,
double ones give it a line of its own.

```markdown
Inline: $\frac{150 \text{ km}}{2 \text{ h}} = 75$

Display:
$$
f'(x) = \lim_{h \to 0} \frac{f(x+h) - f(x)}{h}
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
def height(t):
    return -4.9 * t ** 2 + 20 * t

print(height(2))   # 20.4
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
> Where people usually go wrong — the calculator quietly left in
> degree mode lives in boxes like this one, and so does the inner
> derivative the chain rule keeps losing.

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
> $\frac{d}{dx}\left(x^2 \sin x\right) = 2x \sin x + x^2 \cos x$ —
> the product rule, each factor's growth scaled by the *other*
> factor's size. The product of the derivatives, $2x \cos x$, is the
> answer to a question nobody asked.

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
    A["Name the quantity to optimize"] --> B["Write it as a function"]
    B --> C["Differentiate and find candidates"]
    C --> D{"Best of all candidates?"}
    D -->|check endpoints too| E["Defend the answer"]
    D -->|a candidate fails| C
```

**How that was made:**

````markdown
```mermaid
graph LR
    A["Name the quantity to optimize"] --> B["Write it as a function"]
    B --> C["Differentiate and find candidates"]
    C --> D{"Best of all candidates?"}
    D -->|check endpoints too| E["Defend the answer"]
    D -->|a candidate fails| C
```
````

Proportions draw themselves too:

```mermaid
pie title One class period, roughly
    "Number talk" : 15
    "Thinking task" : 45
    "Consolidation" : 20
    "Notes and check-in" : 20
```

And history fits on a line:

```mermaid
timeline
    title Where this course's ideas came from
    1665 : Newton : works out his "fluxions" in a plague year
    1684 : Leibniz : publishes calculus with the dy/dx notation
    1821 : Cauchy : puts the limit on rigorous footing
    1843 : Hamilton : carves the seed of vector algebra into a Dublin bridge
    1901 : Gibbs : the modern dot and cross products in print
```

---

## Tables

**How that was made:** rows of text separated by `|`, with a line of
dashes under the headings. Mathematics works inside cells, which matters
more than it sounds.

| Representation | Shows best | Hides |
| --- | --- | --- |
| Components $\langle 3, 4 \rangle$ | Exact arithmetic — adding is just adding | What the arrow looks like |
| Magnitude and direction — 5 units at $53^\circ$ | The physical picture: how far, which way | Clean addition |
| An arrow drawn to scale | Two vectors' sum, tip to tail, at a glance | Exact values |

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

- A plain link: [[The Chain Rule]]
- A link with different words: [[The Limit|the instant, made precise]]
- A link to a section: [[Checking Your Own Work#Estimate first, compare after]]

**How that was made:** double square brackets.

```markdown
[[The Chain Rule]]
[[The Limit|different words for the link]]
[[Checking Your Own Work#Estimate first, compare after]]
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
[[The Derivative]] and its backlinks list every exploration, task, and
practice set that leans on it. Nobody maintains that list.

---

## Hover previews

Hover over [[Getting Unstuck]] without clicking. The page appears in a
small window. Checking one definition mid-problem does not cost you your
place.

---

## Footnotes

**How that was made:** `[^1]` where the marker goes, and a matching
`[^1]:` line anywhere in the page.

The word "calculus" is humbler than the subject.[^1]

[^1]: It is Latin for "small pebble" — the counting stones of Roman
    arithmetic boards. The name stuck to the mathematics of Newton and
    Leibniz because it, too, was a system for calculating — though its
    pebbles turned out to be instants.

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
