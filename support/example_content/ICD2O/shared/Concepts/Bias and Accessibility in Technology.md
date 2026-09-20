---
title: Bias and Accessibility in Technology
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: false
---
The debate in [[Can a Machine Be Biased]] usually ends in the same
place: the machine is just math, but the math learned from us.
Technology inherits the assumptions of whoever built and tested it —
which makes "who was this designed for?" one of the sharpest
questions in this course.

## How bias gets in

Bias rarely arrives on purpose. It arrives through training examples
— an [[Automation and Artificial Intelligence|AI system]] shown
mostly one kind of face gets worse at the others. It arrives through
test groups — a product tested only on people like its designers
works best on people like its designers. And it arrives through old
data — a system trained on past decisions learns past prejudices and
repeats them fluently.

## The evidence is concrete

| Technology       | What went wrong                          |
| ---------------- | ---------------------------------------- |
| Voice assistants | Understood some accents far better       |
| Camera exposure  | Tuned for lighter skin for decades       |
| Motion sensors   | Missed darker skin at taps and doors     |

None of these systems was built by villains. Each was built by teams
who tested on themselves and shipped their blind spots. Spotting bias
therefore starts with a measurement, not an accusation: *does this
work equally well for people unlike its makers?* Every fix in that
table began with someone checking.

## Accessibility is design for everyone

Accessibility means building so that disabled people can actually use
the thing — and the benefits reliably spill over. Captions were built
for deaf users and are now how half the internet watches video on the
bus. Voice control, built for people who cannot use a keyboard, now
runs kitchens. This pattern has a name — the curb-cut effect, after
the sidewalk ramps built for wheelchairs and used by every stroller,
suitcase, and skateboard since.

So when you plan [[The Quiz Machine]] or draft
[[The Innovation Brief]], the question belongs in the plan, not in
the apologies afterward: who might this exclude, and what would
include them? Clear wording, readable output, and no assumption that
everyone sees, hears, or clicks the same way.

## Building inclusive computational artifacts

When authoring your own programs and computational artifacts (such as
[[The Quiz Machine]], [[The Remix Project]], and [[Launch Day]]),
accessibility and inclusion are active implementation choices:

- **Readable text and contrast** — ensure high text contrast in terminal
  and interface displays, avoid using colour alone to convey meaning (such
  as providing clear text labels like `[SUCCESS]` or `[ERROR]`), and format
  output with clean line spacing.
- **Accessible language and cognitive load** — write direct, unambiguous
  prompts, avoid obscure technical jargon, and allow users to read at their
  own pace.
- **Resilient and forgiving input handling** — normalize inputs using
  `.strip().lower()`, accept common synonyms, and provide helpful error
  recovery prompts when an unexpected input is entered so users are never
  stranded by a crash.

Designing with these principles produces computational artifacts that
genuinely accommodate diverse audiences and contexts.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[A2.4]]

![[A2.5]]
%%curriculum-end%%
