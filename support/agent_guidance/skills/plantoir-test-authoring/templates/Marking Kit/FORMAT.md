# The marking kit format (kit 1)

A test's `Marking Kit/` folder holds three files: this format's
`answers.json`, an empty marks record `marks-template.json`, and a
`README.md` for whoever marks. The `plantoir-marking` skill reads the kit
to mark papers and build feedback sheets, so the kit is written in this
format exactly. `answers.json` and `marks-template.json` beside this file
are a worked example (an invented Grade 10 science test with two
versions); copy them and replace every value.

Check a kit before you hand it over:

```text wrap
python3 -B .claude/skills/plantoir-test-authoring/scripts/check_kit.py "<test folder>/Marking Kit/answers.json" --marks "<test folder>/Marking Kit/marks-template.json"
```

It prints `OK` or one line per problem, each ending in the rule it breaks.

## No place for a name, anywhere

No key in any kit file, and no key in any marks record, is `name`,
`student`, `pupil` or `email`, at any depth. A marks record names its
paper by `identifier` (such as `Student A`), never by a name. The reason is
that these files are read by an assistant, and a file with no place for a
name is one nobody fills with one by accident. Where a title is needed (a
category's), the key is `title`.

## answers.json

| Key | What it holds |
|---|---|
| `kit` | `1`, this format's version. |
| `test` | The test's title, as printed. |
| `course` | The course code, in capitals. |
| `categories` | A list of `{key, title}`: the categories marks are counted in, such as `{"key": "K", "title": "Knowledge and Understanding"}`. The teacher's own, in the teacher's order. |
| `parts` | A list of `{key, title, category}`: the parts of the paper. `category` is optional, for a part that is all one category. |
| `questions` | A list of `{id, part, skill, topics}`: every question as students see it. `skill` is a few words on what it tests, for the feedback sheet. `topics` (optional) lists keys of `topics`. |
| `points` | A list of `{id, question, category, meaning, followThrough}`: every mark. See below. |
| `versions` | An object, one entry per version (`"A"`, `"B"`): `{source, solutions, answers}`. `source` and `solutions` are the file names of the version and its solutions. `answers` has one entry per point ID. |
| `strengths` | Optional. A list of `{sentence, halves}`, each half `{points, sentence}`: a concept the feedback sheet names as a strength. See below. |
| `topics` | Optional. An object of `{when, pages}`, each page `{title, path, anchor}`: the course pages a marker may point a student to. See below. |

Keys that start with an underscore (`_about`) are notes, and are ignored.

### Points

- **Every point is one mark.** A category is out of the number of its
  points. A question worth three marks has three points, each saying what
  earns it (`meaning`). This is why a mark can be explained: each lost
  mark has its own reason.
- **Point IDs are the same in every version**: `B1.2` is the second mark of
  Part B, question 1, on every version. Versions are parallel by
  construction, so one marks record and one feedback sheet serve every
  paper, and results compare across versions.
- Every point names a question in `questions` and a category in
  `categories`. Every question names a part in `parts`, and has at least one
  point.
- `followThrough` (optional) lists earlier points of the SAME question that
  this point follows through from: it is earned when the work is right for
  the student's own earlier answer, even if that answer was wrong.
- An ID is any short text. The worked example uses the part letter, the
  question number, a dot and the mark (`B1.2`); a single-mark question is
  just its question ID (`A3`).

### Answers

For each version, `answers` has an entry for EVERY point, and for no point
that is not in `points`:

```json
"B1.3": {"answer": "7 O2: 14 oxygen atoms on each side", "accept": ["3.5 O2 before doubling, if the doubling is then shown"]}
```

- `answer`: what earns the mark, as the solutions give it. For a choice
  question, the letter.
- `accept`: other answers that earn it. An answer that is right in a way the
  kit does not list is a judgement for the teacher.
- `misconceptions` (a choice question): every WRONG option's letter and the
  misconception choosing it suggests. The Marking Guide prints them, and a
  feedback sheet explains a wrong choice from them.

### Strengths

A strength is a concept a student showed, written as the sentence a
feedback sheet prints. It has one or more halves, each a list of points.
When every point of every half was earned, the whole `sentence` is
printed; otherwise each half whose points were all earned prints its own
`sentence`, and a half whose `sentence` is `null` prints nothing alone.

### Topics

A topic is an idea a student may need to revisit, and the course pages
that teach it: `when` says when to choose it, `pages` lists `{title, path,
anchor}`, where `path` is the page's address on the section's website
after the site's address (`Concepts/Balancing-Equations`) and `anchor` a
heading on it, or `""`. The site's address is not in the kit, because each
section has its own; `plantoir-marking` adds it at marking time and checks
the link opens.

## marks-template.json: one marks record

`plantoir-marking` copies it once per paper, names the copy by the
identifier (`Student A.json`), and fills it in. It has every point of
`answers.json`, and nothing else:

| Key | What it holds |
|---|---|
| `kit` | `1`. |
| `identifier` | The paper's identifier, such as `Student A`. Never a name. |
| `section`, `version` | The section, and the version written at the top of the paper. |
| `points` | One entry per point ID: `{earned, seen, note, studentNote}`. `earned` is `null` until marked, then `0` or `1`; `0.5` only where the teacher's marking settings allow a half mark. `seen` is what is on the paper, briefly. `note` is the reason when a mark is withheld or a judgement was made. `studentNote` is one sentence to the student about a lost mark. |
| `voided` | Points the teacher has removed from the count (a question that did not work), each `{reason}`. |
| `checks` | Things for the teacher to look at, each starting with its question. A name seen on a paper is written here only as "NAME VISIBLE page N", never the name. |
| `summary`, `byQuestion`, `strengths`, `focus`, `closing`, `feedback` | What the feedback sheet says, written by the marker; `plantoir-marking` says how. |

Totals are never written: they are counted from `points`.
