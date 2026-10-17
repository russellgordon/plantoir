---
title: Reading the Documentation
publish: true
codeRunner: true
created: __CREATED__
tags:
  - tutorials
---
The single ability that separates a programmer who can keep going from
one who stalls is reading the manual for something they have never
used. It is a learnable skill with a shape.

## Where the answer actually is

- **The official documentation** for the language or library. For
  Python, `docs.python.org` — the library reference for what a function
  does, the tutorial for how a whole idea works.
- **`help()` and the editor's hover.** `help(str.split)` inside Python
  prints the same reference without leaving the program.
- **Your editor's autocomplete**, which lists what a thing can do at
  the moment you need it.
- **A forum answer**, last. It is somebody's memory of the
  documentation, occasionally out of date, occasionally wrong.

## How to read a function's entry

Take `str.split(sep=None, maxsplit=-1)`. Four questions, in order:

1. **What does it give back?** A list of strings. Knowing this decides
   what you can do with the result.
2. **What must I give it?** Nothing — both parameters have defaults.
3. **What do the defaults do?** `sep=None` splits on any run of
   whitespace, which is not the same as splitting on a single space.
4. **What is the example?** Documentation examples are short and true;
   run one before adapting it.

Then try it on one line of your own data, in isolation, before putting
it inside your program:

```python run
line = "Priya,  17, Kingston"
print(line.split(","))       # ['Priya', '  17', ' Kingston']
```

Note the surviving spaces. Reading the entry told you it splits on the
separator; running it told you it does not tidy up afterwards. Both
steps were necessary, and the second took four seconds.

> [!tip] When the documentation is dense
> Read the examples first, then the description, then the parameter
> list. Reference documentation is written to be exhaustively correct,
> not welcoming — starting at the top is the slow way in.

Working from documentation is how you will write programs nobody
taught you to write, which is the point of the culminating project and
most of what comes after this course.

%%curriculum-start%%
## Curriculum connection

![[C3.2]]

![[A4.3]]
%%curriculum-end%%
