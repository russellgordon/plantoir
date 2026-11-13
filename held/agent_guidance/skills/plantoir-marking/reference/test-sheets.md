# The test feedback sheet

What `scripts/build_test_sheet.py` builds, why it is laid out this way, and what it reads. Everything
here is the default for every teacher, and the teacher may change it: their How I Teach page and
`Marking Settings.md` come first.

## Two sheets per paper

- `Student A - Feedback.pdf`, for the student.
- `Student A - Marks by Question.pdf`, for the teacher: every point, what was seen, the mark, the
  marker's note and the CHECK flags, with the teacher-decides sentence under its title.

Both carry the identifier on their student line, `\studentline{Student A}`. That macro is the one
place `make_named_copies.py` puts a name, at the end, on the teacher's word.

## The order of the student's sheet, and why

1. The title and the student line.
2. A summary: two or three sentences to the student.
3. Strengths: the kit's `strengths`, printed as a concept when every point of every half was earned,
   or as the half that was. Concepts, never a question-by-question account.
4. Issues by question: one table, with a row per part, listing only the questions where a mark was
   lost, and the questions given full marks with the benefit of the doubt, each with its plain-words
   reason. Nothing is listed for a question with full marks and no note.
5. Areas to focus on: at most four, each one block that never splits across a page, the heading kept
   with the first. A focus item may carry a short code or worked example and links to the course pages
   that teach it.
6. Overall comments: one paragraph that names the student's best work again and frames the first focus
   item as within reach.
7. The marks, last: by question and by category. Never a total on the student's sheet.

The marks go last because students read marks first and stop: placed last, the reasons are read first.

## What the builder refuses

- A kit or marks record that does not pass `check_kit.py`.
- A lost mark with no `studentNote`.
- A half mark when `Marking Settings.md` does not say `- Half marks: yes`.
- A marks record with no `closing`, more than four focus items, or a focus topic the kit does not have.
- A heading left alone at the foot of a page.
- A sheet that does not compile: it says the identifier and the first error line.

## Typography on a sheet

- A concept named as a concept is in italics (`*remainder*` in a marks record).
- A keyword, a name in code, an operator or a value is in monospace (`` `return` ``), never italics.
- Double quotes only for what the student actually wrote.
- Links are blue and go to the section's own site, and only links that answered when checked.

## What a teacher often changes

The headings and leads (`ISSUES_TITLE` and the others at the top of the script), the school name and
corners, the paper size, levels in place of marks (add the teacher's scale where `category_marks` is
printed), and which sections the sheet has. Change them in the copy in `Scripts/`, keep the "What must
not change" block, and run `--self-test`.
