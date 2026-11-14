---
id: tables-boxes-footnotes
checked: 2.0.0
covers:
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
- contracts/shared-rules.json
- support/example_course/EXC2O/Style/What This Site Can Do.md
keywords:
- table
- tables
- columns
- rows
- align
- callout
- callouts
- box
- boxes
- coloured box
- colored box
- note
- tip
- warning
- folded
- collapsible
- answer box
- footnote
- footnotes
- reference
- citation
description: Type a table, a coloured box that can be folded shut, or a footnote on a page, and see each one in a ready-made course.
---
A table, a coloured box and a footnote are each typed as a few lines of plain text on a page. This page gives the form of each.

## A table

Type each row on one line, with a `|` between the cells. Under the row of headings, type a row of dashes. The row of dashes is what makes it a table.

```text wrap
| Quantity | Symbol | Unit |
| --- | --- | --- |
| Force | F | newton |
| Mass | m | kilogram |
```

- **To align a column**, add colons to its dashes: `---:` for right, `:---:` for centred, `---` for left.
- **Mathematics works in a cell.** See [Mathematics and chemistry notation](page:notation).
- **A `|` inside a cell** is typed with a backslash before it. A link that shows other words needs this:

```text wrap
[[Traditional Structures\|the four structures]]
```

## A coloured box

A box pulls something out of the page: a warning, a tip, a worked answer. Each kind of box has its own colour and icon. The ready-made courses call these boxes callouts.

```text wrap
> [!warning] Where people usually go wrong
> Subtracting a negative: $5 - (-3)$ is $5 + 3$, not $5 - 3$.
```

1. Leave an empty line before the box.
2. Start every line of the box with `>`.
3. On the first line, type the kind in square brackets with `!` before it, then the title. A box with no title is titled with its kind.
4. Leave an empty line after the box.

The kinds are `note`, `abstract`, `info`, `todo`, `tip`, `success`, `question`, `warning`, `failure`, `danger`, `bug`, `example` and `quote`.

Some kinds have other names that give the same box. `hint` gives `tip`. `check` and `done` give `success`. `help` and `faq` give `question`. `error` gives `danger`.

A kind that is not on the list shows as a box in the colour of `note`, with the kind's own name as its title.

### A box that folds

A `-` after the bracket starts the box folded shut. Students click its title to open it. A `+` starts it open, with a button to fold it.

```text wrap
> [!success]- Worked answer
> The slope is 3.
```

Folded boxes suit answers, so that students try before they look.

- **A box inside a box** takes one more `>` for each level, as in `> > [!hint]- Hint`.
- **Three kinds are kept for another use.** `quiz`, `answer` and `explain` make a question students check themselves. See [Questions students check themselves](page:quizzes).
- **On a page that prints**, a folded box whose kind is `success`, `solution` or `answer` goes to the answers page. See [A handout that prints](page:printing).
- **A formula on a centred line**, inside a box, must be typed all on one line.

## A footnote

Type `[^1]` where the marker goes. Anywhere on the page, type a line that starts `[^1]:` and gives the footnote. The footnote is listed at the bottom of the page.

```text wrap
Dalton pictured the atom as a solid sphere.[^1]

[^1]: John Dalton, 1803.
```

Give each footnote its own label, such as `[^1]`, `[^2]` or `[^source]`. A footnote's text may carry on to the next line if that line is indented.

## See them in a ready-made course

Every ready-made course has a page named What This Site Can Do, in its Style folder. It shows tables and boxes with examples from the course's own subject, and in most of the courses footnotes as well. Some of these pages show the text that made each example.

{{picture:tables-boxes-footnotes-1}}
alt: The What This Site Can Do page of a ready-made course on its class website, with a table and a coloured box.

## Check your work

Preview the section and look at the page. If a preview is already running, choose {{menu:rebuildPreview}}.

## If it does not work

- **A table shows as lines of text.** Check that the row of dashes is there, under the headings, and that each row is on one line.
- **A cell breaks where a link is.** Type a backslash before the `|` inside the link.
- **A box has the wrong colour and its kind as its title.** The kind is not one on the list.
