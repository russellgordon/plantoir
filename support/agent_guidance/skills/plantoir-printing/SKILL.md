---
name: plantoir-printing
description: Use when writing or changing a Plantoir course page that students will print - a worksheet, handout, practice set, review sheet, quiz, answer key or anything "printable". Says how to mark the page printable, how to write answers so they move to an answer key, how hints and self-checks print, and how to hand out an existing PDF instead.
---

# Making a Plantoir page printable

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A page can print as a worksheet: a Print button on the page makes a
handout with the answers gathered at the end on a fresh page, the school
name, the blanks a student fills in and the course code in the corners of
every page, and the questions and the answers numbered separately ("Page 1
of 3", then "Answers 1 of 2"). This file is managed by Plantoir and is
replaced when Plantoir updates; do not edit it.

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

## 2. Put every answer in a FOLDED callout

An answer is a callout folded with `-` after the kind. Use `success`,
`solution` or `answer` as the kind, or any kind whose title starts with
"Answer" or "Solution":

```markdown
### Question 3

Factor $x^2 - 9$ completely.

> [!success]- Answer 3
>
> $(x - 3)(x + 3)$
```

- **Always leave an empty `>` line after the callout's first line.** Without
  it, a callout inside a list puts its whole body into the title, so the
  answer shows on screen with the callout closed and prints as the label.
- **Number the questions** with headings (`### Question 3`) or a numbered
  list (`1.`, `2.`, ...). An answer with no title of its own, or one titled
  just "Answer" or "Solution", is labelled in the answer key by where it
  sits: "Question 3" for the third item of a numbered list (after the
  heading above the list, if there is one: "Practice · Question 3"; under a
  heading that is itself a question, the items are its parts: "Question 3,
  part 1"),
  otherwise the nearest heading above it, otherwise "Answer 1", "Answer 2", ...
- Anything after the title like "(click to expand)" is dropped on paper.
- An answer left OPEN (no `-`) prints where it is, on the worksheet. Use that
  for worked examples, never for answers.
- Do not put answers inside tables, or inside another callout: they cannot
  be lifted cleanly.

## 3. Hints and self-checks

- A folded hint prints in place, opened, on the worksheet:

  ```markdown
  > [!tip]- Need a hint?
  >
  > A difference of squares factors as $(a - b)(a + b)$.
  ```

- A folded `question` callout keeps its TITLE on the worksheet as the
  question and moves its body to the answer key:

  ```markdown
  > [!question]- Which of these expansions is a perfect square?
  >
  > Questions 1 and 2.
  ```

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
never split across pages and are scaled to the page width; diagrams print in
light colours even when the reader uses dark mode. Keep each figure a
reasonable size - a figure taller than a page cannot avoid a break.

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
page. In Plantoir's own preview, Print opens the page in their web browser
to print.
