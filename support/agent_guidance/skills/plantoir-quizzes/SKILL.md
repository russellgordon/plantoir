---
name: plantoir-quizzes
description: Use when a Plantoir course page should have questions students answer and check themselves in the browser - "quiz", "add a 5-question check", "practice questions", "self-check", "check your understanding", "flashcards", "exit ticket", "multiple choice", "fill in the blank", "short answer". Gives the [!quiz] callout for every kind of question with patterns to paste, how answers are checked (alternatives, ± tolerance, number forms), shuffling, graphs and runnable code inside questions, what a folder problem looks like, and how to write good questions.
---

# Self-check quizzes on a Plantoir page

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A `> [!quiz]` callout on any page becomes a question students
answer **on the website**, press **Check**, and see at once whether they were
right - with an explanation afterwards if the teacher wrote one, and **Show
answer** when they are stuck. It works on a laptop, a Chromebook or an iPad,
needs no account, and nothing a student does leaves their browser: it is a
self-check, never a grade, and Plantoir never collects answers.

In Obsidian the teacher sees the whole thing - ticked boxes, answers,
explanations - as ordinary callouts. That is intended: it is their answer
key. On the website the ticks and answers are taken off the page until a
student answers.

This file is managed by Plantoir and is replaced when Plantoir updates; do
not edit it.

## 1. The four kinds

Every quiz is a callout that starts **at the left edge of the page** with
`> [!quiz]` and its question on the same line. Leave an empty line before
and after it.

**Multiple choice** - tick exactly ONE box with `[x]`:

```markdown
> [!quiz] Which point is the vertex of $y = (x-3)^2 + 2$?
> - [ ] $(-3, 2)$
> - [x] $(3, 2)$
> - [ ] $(3, -2)$
> - [ ] $(2, 3)$
```

**Select all that apply** - tick TWO or more; the site adds "Select all that
apply." itself:

```markdown
> [!quiz] Which of these are prime?
> - [x] 2
> - [ ] 9
> - [x] 11
> - [ ] 15
```

**Short answer** - an `[!answer]` callout INSIDE the quiz, with the answer on
the line under its title:

```markdown
> [!quiz] Simplify $2^3 \cdot 2^4$.
> > [!answer]- Answer
> > $2^7$ | 2^7 | 128
```

**Fill in the blank** - write each blank as `` `____` `` (three or more
underscores in backticks), and give one answer line per blank, in order:

```markdown
> [!quiz] Water boils at `____` °C at `____` pressure.
> > [!answer]-
> > 100 ± 1 | one hundred
> > sea level | standard | atmospheric
```

**An explanation**, shown after the student checks or shows the answer, is
an optional `[!explain]` callout inside the quiz, on any kind:

```markdown
> [!quiz] Which is a factor of $x^2 - 5x + 6$?
> - [x] $x - 2$
> - [ ] $x + 2$
> - [ ] $x + 6$
>
> > [!explain]- Why
> > $x^2 - 5x + 6 = (x - 2)(x - 3)$, and $x - 2$ is one of the two factors.
```

Rules that matter:

- Every choice starts with `- [ ]` or `- [x]` **and has words after the
  box** on the same line (`- [ ] Graph A`). A box with nothing after it is
  not a box to the website.
- Keep the choices in ONE list, and a quiz has choices OR an `[!answer]`,
  never both.
- The `[!answer]` and `[!explain]` lines carry two `>` marks (`> >`): one
  for the quiz, one for the callout inside it. Fold them with `-` after
  the `]` so the teacher's own view in Obsidian keeps the answer tucked away.
- A short answer has ONE answer line; put every accepted answer on it,
  separated by ` | `.

## 2. How a typed answer is checked

For short answer and fill in the blank, the student's answer and each
accepted answer are compared after trimming, ignoring capitals, treating
any run of spaces as one, and treating curly quotes as straight ones (iPad
keyboards type curly apostrophes).

- **Alternatives**: separate accepted answers with ` | ` - a bar with a
  space on BOTH sides: `Ottawa | ottawa, ontario`. `a|b` (no spaces) is one
  answer. A literal bar is written `\|`.
- **Numbers**: an answer that is a number accepts any number of the same
  value - `0.5` accepts `.5`, `1/2`, `2/4` and `0.50`; `-3` accepts `−3`.
  Decimals and whole-number fractions only: NOT a decimal comma (`1,5`), a
  thousands separator, scientific notation (`1e3`), a mixed number
  (`1 1/2`) or `½`. Add those as text alternatives if students will type
  them.
- **Tolerance**: `3.14 ± 0.01` (or `3.14 +- 0.01`) accepts every number from
  3.13 to 3.15. Only a number ± a number is a tolerance; `±3` and `x = ±3`
  are ordinary answers (a student can type `+-3`).
- **Formulas**: an answer written wholly as `$...$` is compared as typed
  inside the dollars, so `$2^7$` accepts `2^7` but not `2 ^ 7` and not
  `128`. Always add plain alternatives students might type: `$2^7$ | 2^7 | 128`.
- Answers about wording ("explain why...") cannot be checked: use multiple
  choice, or a short answer with a few accepted forms, and put the reasoning
  in `[!explain]`.

## 3. Shuffling

`> [!quiz|shuffle]` puts the choices in a new order each time the page is
loaded. Print and Obsidian keep the order written. **Never shuffle** a quiz
whose choices refer to their position ("All of the above", "Both A and B",
"None of these").

```markdown
> [!quiz|shuffle] Which is equivalent to $3(x + 4)$?
> - [x] $3x + 12$
> - [ ] $3x + 4$
> - [ ] $x + 12$
> - [ ] $3x + 7$
```

## 4. Graphs, pictures and code inside a question

Anything a page can hold works inside a question, a choice and an
explanation. Put it on the lines under its choice, lined up under the
choice's `[`: after the `> ` that starts every line of the quiz, two more
spaces (`>   ```functionplot`, as below). How to write the graph itself is
in the `plantoir-math-graphs` skill; how to write runnable code - Python (` ```python run `) or Swift
(` ```swift run `) - is in the `plantoir-runnable-code` skill (a runnable
block also needs `codeRunner: true` at the top of the page).

Keep HTML out of the lines between a question and its choices: a line such
as `<img …>` or `<div>` straight before the list makes the website read the
choices as HTML (the quiz then cannot be checked). Leave an empty `>` line
after any HTML, or use a Markdown image instead.

A choice with a graph:

````markdown
> [!quiz] Which is the graph of $y = -x^2$?
> - [ ] Graph A
>   ```functionplot
>   ---
>   alt: a parabola opening upward
>   ---
>   y = x^2
>   ```
> - [x] Graph B
>   ```functionplot
>   ---
>   alt: a parabola opening downward
>   ---
>   y = -x^2
>   ```
````

An explanation with a graph:

````markdown
> [!quiz] Which graph shows $y = (x-3)^2 + 2$?
> - [ ] Vertex at $(-3, 2)$
> - [x] Vertex at $(3, 2)$
>
> > [!explain]- Why
> > $y = x^2$ shifts right 3 and up 2:
> > ```functionplot
> > y = (x-3)^2 + 2
> > y = x^2
> > ```
````

An explanation with code to run (page has `codeRunner: true`):

````markdown
> [!quiz] What does `print(7 // 2)` print?
> - [x] 3
> - [ ] 3.5
> - [ ] 4
>
> > [!explain]- Why
> > `//` divides and drops the remainder. Try it:
> > ```python run
> > print(7 // 2)
> > print(7 / 2)
> > ```
````

Give every graph an `alt:` line: it is what a screen reader says for a
choice that is a graph.

## 5. A five-question check (paste, then change)

````markdown
## Check your understanding

> [!quiz] What is the slope of $y = 3x - 5$?
> - [x] $3$
> - [ ] $-5$
> - [ ] $\frac{1}{3}$
> - [ ] $5$
>
> > [!explain]- Why
> > In $y = mx + b$ the slope is $m$, the number multiplying $x$.

> [!quiz] Which of these lines are parallel to $y = 2x + 1$?
> - [x] $y = 2x - 4$
> - [ ] $y = -2x + 1$
> - [x] $y = 2x$
> - [ ] $y = \frac{1}{2}x + 1$

> [!quiz] What is the $y$-intercept of $y = -4x + 7$?
> > [!answer]-
> > 7 | (0, 7) | +7

> [!quiz] The line through $(0, 1)$ and $(2, 5)$ has slope `____` and $y$-intercept `____`.
> > [!answer]-
> > 2
> > 1

> [!quiz|shuffle] Which is the graph of $y = x - 2$?
> - [ ] Graph A
>   ```functionplot
>   ---
>   alt: a line rising through (0, 2)
>   ---
>   y = x + 2
>   ```
> - [x] Graph B
>   ```functionplot
>   ---
>   alt: a line rising through (0, -2)
>   ---
>   y = x - 2
>   ```
````

After the last quiz the site shows the student's score for the page ("3 of
5 right on the first try") with a **Start again** button. It is kept in that
student's browser only.

## 6. Where a quiz can go

Only at the **left edge of the page**: not inside a list, a numbered
question, or another callout (`[!example]`, `[!note]`...). One there shows
its question with a short note instead of Check, and Plantoir names it as
a folder problem. Put the quiz after the list or callout instead. A quiz
shown on another page by `![[Page]]` still works there.

Use `[!quiz]` when students should check an answer. A plain `[!question]`
callout stays exactly as it was - a question with no Check button.

## 7. How a problem shows up

When a quiz cannot be checked - no ticked box, two lists of choices, more
answer lines than blanks, a `±` with no number after it, a setting other
than `shuffle` - students see the question with a short note instead of
Check, and the next Preview says so in Plantoir's folder problems, and in
the build's output as a line like:

```
plantoir: error: Units/Linear Relations.md: quiz 3, line 41: none of its choices is ticked - mark the right one with [x]
```

`quiz 3` is the third quiz on that page, and the line is in the teacher's
file. Fix the quiz and preview again. After adding or changing quizzes,
**preview the section and answer each one** - right and wrong - before
publishing.

## 8. Writing good questions

- One clearly right answer (or a clearly right set, for select all). If two
  choices could be argued, rewrite one.
- Plausible wrong choices built from real mistakes (a sign error, the
  intercept instead of the slope, forgetting to square), not jokes or
  obviously silly options.
- Choices of similar length and form; avoid "All of the above" and "None of
  the above".
- An `[!explain]` that says WHY the right answer is right - and, where it
  helps, why the tempting wrong one is wrong - not just "the answer is B".
- Match the page: ask about what the page teaches, at the level of the
  course's expectations, using its own words and notation.
- On a page about graphs or figures, make at least one question SHOW one -
  graphs as the choices, or a graph in the explanation (section 4) - so the
  check asks students to read a graph, not only to manipulate an equation.
- Short answers with a few accepted forms; check a numeric answer is not
  rejected for an equivalent form a student would reasonably type.

## 9. Do not

- Do not embed Google Forms, Kahoot, Quizlet or any other quiz service, an
  iframe, or a script in the page. Plantoir's quizzes need none of them and
  work offline once the page is open.
- Do not try to collect, record, email or report students' answers. Quizzes
  are self-checks; nothing leaves the student's browser.
- Do not use a plain `[!question]` callout, or a bulleted list with the
  answer in bold, when the request is for an interactive check.
- Do not put the answer in the question's own words or title, where the
  student sees it before answering.

## 10. On paper

A printed page shows each quiz as its question with empty circles or boxes
for the choices and lines for blanks; the answers and explanations never
print (on a printable page they are in neither the questions nor the answer
key). The `plantoir-printing` skill says more about printable pages.
