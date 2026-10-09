---
name: plantoir-printing
description: Use when writing or changing a Plantoir course page that students will print - a worksheet, handout, practice set, review sheet, quiz, answer key or anything "printable". Says how to mark the page printable, how to write answers so they move to an answer key, how hints and self-checks print, and how to hand out an existing PDF instead.
---

# Making a Plantoir page printable

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A page can print as a handout that looks like a typical LaTeX
worksheet: Latin Modern type, a bold title, numbered questions ("1.", "2.")
with lettered parts ("a)", "b)") side by side in columns, plain text with no
coloured boxes (a worked example keeps a peach box, and code a thin one),
the school name, the blanks a student fills in, and a footer with the page's
title, the course code and "Page 1 of 3". The Print button opens a menu -
Portrait or Landscape, then **Questions only**, **Answers only** or
**Both** (the questions, then the answers on a fresh page, numbered
separately: "Answers 1 of 2"). Nothing prints until one is chosen. This
file is managed by Plantoir and is replaced when Plantoir updates; do not
edit it.

## 1. Mark the page printable

Add `printable: true` to the settings block at the top of the page:

```markdown
---
printable: true
---
```

Write it exactly like that - `true`, not `"true"` or `1`. Leave the page's
other settings (`publish`, `publishForSection1`, dates, tags) as they are.
Nothing else about the page changes on screen except the Print button.

## 2. Number the questions, and put every answer in a FOLDED callout

Write each question under a heading `### Question 3` (or `## Question 3`).
On paper the heading becomes the number "3." in the margin, beside the
question's words - write the question as the text under the heading, not in
the heading. A numbered list directly under a question is its PARTS, lettered
a), b), c); short parts print in two or three columns, as LaTeX's `tasks`
does.

An answer is a callout folded with `-` after the kind. Use `answer`,
`solution` or `success` as the kind, or any kind whose title starts with
"Answer" or "Solution". Leave the title off: the answer key labels it by the
question it belongs to.

```markdown
### Question 3

Simplify.

1. $5x + 2(x - y)$
   > [!answer]-
   >
   > $7x - 2y$
2. $3a - 2b + 4a - 9b$
   > [!answer]-
   >
   > $7a - 11b$
```

That prints "3. Simplify." with a) and b) side by side, and in the answer
key "3. a) 7x - 2y  b) 7a - 11b".

- **Give final answers only**, the way an answer key does: the result, not
  the working, unless the teacher asks for worked solutions.
- **Always leave an empty `>` line after the callout's first line.** Without
  it, a callout inside a list puts its whole body into the title, so the
  answer shows on screen with the callout closed and prints as the label.
- An answer under no question heading is labelled by where it sits: the
  number of its list item ("2."), after the heading above the list when that
  heading is not a question ("Practice · 2."), otherwise the nearest heading,
  otherwise "Answer 1", "Answer 2", ... An answer with a title of its own
  ("Why the loop stops") is labelled by that title.
- Anything after the title like "(click to expand)" is dropped on paper.
- An answer left OPEN (no `-`) prints where it is, on the worksheet. Never
  use that for answers.
- Do not put answers inside tables, or inside another callout: they cannot
  be lifted cleanly.

## 3. Worked examples, hints and self-checks

- A **worked example** is an `example` callout, left open. It is the only
  callout that prints in a box (the LaTeX handouts' peach box); put it just
  before the questions it teaches:

  ```markdown
  > [!example] Substitute and Evaluate
  > Evaluate $3x - 2y + 1$ when $x = 4$ and $y = -3$.
  ```

- Every other callout (note, tip, warning, ...) prints as its title in bold
  and its words as plain text, with no box or icon.
- A folded hint prints in place, opened, on the worksheet:

  ```markdown
  > [!tip]- Need a hint?
  >
  > A difference of squares factors as $(a - b)(a + b)$.
  ```

- A `question` callout is a numbered question too. Folded, its TITLE is the
  question and its body goes to the answer key; open, its title and then its
  body are the question. Titled `Question 4` it takes that number; titled in
  your own words it takes the number after the question before it.

  ```markdown
  > [!question]- Which of these expansions is a perfect square?
  >
  > Questions 1 and 2.
  ```

- A page's `description` in its settings prints under the title in grey, as
  the instructions line of a LaTeX worksheet does.
- Code prints in a thin box, black, with its line numbers; a long program
  continues onto the next page with its numbers counting on.

## 4. Handing out a PDF the teacher already has

Put the PDF in the course's `Media` folder (where Obsidian puts attachments)
and name it by its FILE NAME only - never a path:

```markdown
---
printPdf: "[[Unit 3 Review.pdf]]"
---
```

`printPdf: Unit 3 Review.pdf` works too. The Print button then simply opens
that PDF; it wins over `printable: true`. If the file is missing, is not a
PDF, or is given as a path, Plantoir says so when the site is previewed and
the page falls back to the generated handout (or to no button).

## 5. Pictures and diagrams

Images, Mermaid diagrams, maths and code all print. Images and figures are
never split across pages, are scaled to the page's width, and a picture
taller than a page is scaled down to fit one; diagrams print in light colours
even when the reader uses dark mode. A displayed formula a little too wide is
set smaller to fit, and a much wider one is broken between its terms; it
cannot be split across pages, so keep one shorter than half a page, and never
put one very long `\text{...}` or matrix on a line of its own. A table of
eight columns or more prints in smaller type; keep tables to about ten
columns of short words. If anything would still be cut off, the page refuses
to print and says so plainly rather than printing a handout with something
missing - the teacher can then try the other orientation.

## 6. The Curriculum connection never prints

Many pages end with a section headed `## Curriculum connection` that
transcludes the curriculum expectations the page addresses (`![[A1.1]]`).
It is for the teacher and the course's Curriculum Coverage map, not for
students, so it is NEVER printed: not on the worksheet, not in the answer
key, and not when the page is printed with the browser's own Print (⌘P or
Control-P). It stays on the page on screen. Plantoir leaves off the heading
and everything under it up to the next heading of the same or a higher level.

- Keep that heading as it is ("Curriculum connection" or "Curriculum
  connections", any capitals), so the expectations stay off paper and on the
  coverage map.
- Put nothing students need below it - no questions, answers or
  instructions - unless a new heading of the same level (`##`) comes first.

## 7. Check it

Ask the teacher to preview the section in Plantoir and press Print on the
page, then choose Questions only, Answers only or Both. In Plantoir's own
preview, Print opens the page in their web browser to print. Choose
Landscape in the menu, not in the browser's print dialog: the handout is
laid out before the dialog opens.
