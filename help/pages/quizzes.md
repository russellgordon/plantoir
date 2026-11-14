---
id: quizzes
checked: 2.0.0
covers:
- contracts/shared-rules.json
- scripts/build_site.py
keywords:
- quiz
- quizzes
- self-check
- self check
- check your understanding
- multiple choice
- short answer
- fill in the blank
- question
- questions
- answer
- shuffle
- grades
description: Write a question in a quiz box, with choices or an answer, and students check their own answer on the class website.
---
A page can hold questions that students answer and check for themselves on the class website. You write each question as a box of the kind `quiz`. This page gives the forms.

These questions are for self-checking only. A student's answers never leave that student's browser. There are no accounts, nothing is sent over the network, and nothing reaches you. It is never a grade book.

No setting turns this on. The box is all a page needs.

## A question with choices

1. In Obsidian, start a line at the left edge of the page with `> [!quiz]` and the question.
2. Under it, type each choice as a checklist item. Leave the brackets empty for a wrong choice, and put an `x` in them for the right one.

```text wrap
> [!quiz] Which of these conducts electricity?
> - [ ] Glass
> - [x] Copper
> - [ ] Rubber
```

Mark two or more choices as right, and students are told:

{{say:shared-rules#quizCallouts.words.site.selectAll}}

To put the choices in a new order each time the page loads, write `[!quiz|shuffle]`.

## A question with a typed answer

In place of choices, give the answer in a box of the kind `answer` inside the quiz. The answer goes on the line under it:

```text wrap
> [!quiz] What is one half, written as a decimal?
> > [!answer]
> > 0.5
```

- **More than one accepted answer.** Separate them with ` | `, as in `copper | Cu`.
- **Numbers match by value.** A student who types 1/2 matches 0.5.
- **A number that may be a little off.** Give a tolerance, as in `3.14 ± 0.01`. You can type `+-` in place of the sign.
- **Several blanks.** Give one answer line for each blank, in order.

A question has choices or an answer, not both.

## An explanation

Add a box of the kind `explain` inside the quiz. Students see it after they answer:

```text wrap
> [!quiz] Which of these conducts electricity?
> - [ ] Glass
> - [x] Copper
>
> > [!explain]
> > Copper is a metal, and metals conduct.
```

## What students see

{{picture:quizzes-1}}
alt: A quiz box as typed in Obsidian, beside the same question on the class website after a student pressed Check.

A student answers and presses {{control:quizCheck}}. The page answers with one of these:

{{say:shared-rules#quizCallouts.words.site.right}}

{{say:shared-rules#quizCallouts.words.site.notRight}}

{{control:quizShowAnswer}} shows the answer. After the last question on the page, a line counts how many the student got right on the first try.

## Check your work

Preview the section, answer each question, and press {{control:quizCheck}}. If a preview is already running, choose {{menu:rebuildPreview}} first.

## On paper

On a printed page, a quiz prints its question only.

## If it does not work

- **A question says this:**
  {{say:shared-rules#quizCallouts.words.site.notReady}}
  The question is written in a way that cannot be checked. The section's {{control:problemsTab}} tab names the page and says what to change. See [The Problems tab](page:problems).
- **The quiz is inside a list or another box.** A quiz works only by itself, starting at the left edge of the page.
- **No choice is marked as right, and there is no answer.** There is nothing to check. Mark the right choice with `x`, or add an answer.
