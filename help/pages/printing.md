---
id: printing
checked: 2.0.0
covers:
- contracts/shared-rules.json
- contracts/file-formats.json
- mac-app/QuartzTeachers/Views/CourseSettings/PrintSettingsView.swift
- mac-app/QuartzTeachers/Models/CourseSettingsWording.swift
keywords:
- print
- printing
- printable
- handout
- worksheet
- answer key
- answers
- questions only
- school name
- name and date blanks
- portrait
- landscape
- paper
description: Mark a page as printable, write its questions and folded answers, and print it as a handout with or without the answers.
---
A page marked as printable gets a Print button on the class website. The button prints the page as a handout: its questions, its answers, or both. This page says how to write such a page and how it prints.

## Write the page

1. In Obsidian, add this line to the page's settings, at the top of the page:

```text wrap
printable: true
```

2. Write each question under a heading of its own, such as `### Question 3`. On paper the question's number is printed, not the heading's words. A box of the kind `question` is a question as well.
3. Put each answer in a folded box. A box is folded when a hyphen follows its kind:

```text wrap
### Question 1

Solve for x: 2x + 6 = 14

> [!answer]-
> x = 4
```

On paper, folded answers are lifted out of the questions and gathered on a fresh page, under the page's title and the word Answers.

A box counts as an answer when its kind is `answer`, `solution` or `success`, or when its title begins with Answer or Solution. A folded hint is opened where it stands. A box that is not folded prints where it is.

## Set what prints in the corners

Every printed page carries the school's name, blanks for students to fill in, and the course's code in its corners, with a page number.

1. In Plantoir's sidebar, select the course. Its settings appear.
2. Find the part named {{control:printingPart}}.
3. Type the {{control:printingSchoolName}}, and choose the {{control:printingBlanks}}: Name, Date and Class #.
4. Under {{control:printingSchoolNamePrints}} and {{control:printingCourseCodePrints}}, choose Top left, Bottom left or Not printed.
5. Press {{control:saveCourseSettings}}.

{{picture:printing-1}}
alt: The Printing part of a course's settings, with the school name, the blanks to fill in, and a sketch of what prints in each corner.

## Print the handout

1. Preview the section and open the page. The {{control:printButton}} button is on the page's date line, at its right end.
2. Press {{control:printButton}}. A menu opens. {{control:printPaper}} is at its top, with {{control:printPortrait}} and {{control:printLandscape}}. Under it are the three ways of printing: {{control:printQuestionsOnly}}, {{control:printAnswersOnly}} and {{control:printBoth}}. A page with no answers offers {{control:printQuestionsOnly}} alone.
3. Choose a way of printing. Nothing prints until you do.

{{picture:printing-2}}
alt: A printable page on the class website with the Print button's menu open, showing Paper and the three ways of printing.

In Plantoir's own preview, the page first says:

{{say:shared-rules#printablePages.words.openingInBrowser}}

The page then opens in your web browser, and prints from there.

Students find the same button and the same menu on the class website. They see it once the page is published for their section and the section is deployed. Pressing Command-P on the page prints the questions only.

{{picture:printing-3}}
alt: A printed handout, with the questions on one sheet and the answer key on a fresh page.

## What is left off the paper

- A part of the page under the heading Curriculum connection is never printed.
- A question students check themselves prints its question only. See [Questions students check themselves](page:quizzes).

## A PDF of your own instead

A page may name a PDF you made yourself, with a `printPdf` line in its settings. The Print button is then a plain link to that PDF in the Media folder.

## If it does not work

- **The page has no Print button.** Check the line in its settings. Write `printable: true`, with no quotation marks around `true`.
- **The page says this, and nothing prints:**
  {{say:shared-rules#printablePages.words.couldNotPrepare}}
- **The page says this:**
  {{say:shared-rules#printablePages.words.incomplete}}
