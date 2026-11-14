---
id: notation
checked: 2.0.0
covers:
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
- documentation/06-quartz-customizations.md
- support/example_course/EXC2O/Style/What This Site Can Do.md
- scripts/build_site.py
keywords:
- equation
- equations
- formula
- formulas
- maths
- math
- mathematics
- LaTeX
- chemistry
- chemical equation
- chemical formula
- dollar sign
- money
- price
- currency
- percent
description: Type mathematics and chemical formulas between dollar signs, and write an amount of money so that its dollar sign does not start mathematics.
---
A page can show mathematics and chemical formulas, typeset as in a textbook. You type them between dollar signs. This page gives the forms, and says how to write an amount of money, which also uses a dollar sign.

## Mathematics

- **In a sentence.** Put the mathematics between single dollar signs: `$x^2 + y^2 = 25$`.
- **On a centred line of its own.** Put it between double dollar signs, each pair on a line of its own:

```text wrap
$$
A = \pi r^2
$$
```

Three things to watch:

- **No space inside a single dollar sign.** Type `$x + 1$`, not `$ x + 1 $`. The class website typesets both, but Obsidian shows the second as plain text.
- **A per cent sign inside mathematics** is typed `\%`.
- **Inside a coloured box**, keep a formula on a centred line all on one line of the page: `$$ A = \pi r^2 $$`. Spread down the box, it breaks. [Tables, boxes and footnotes](page:tables-boxes-footnotes) describes the boxes.

Mathematics also works inside a cell of a table.

{{picture:notation-1}}
alt: A formula between dollar signs as typed, beside the same formula typeset on the class website.

## Chemistry

Type a chemical formula or equation between dollar signs as well, inside `\ce{` and `}`:

```text wrap
$\ce{2H2 + O2 -> 2H2O}$
```

Subscripts and coefficients are set for you. Some other forms:

- `\ce{Ca^2+}` gives an ion with its charge.
- `\ce{NaCl(aq)}` gives a state.
- `\ce{->[light]}` gives an arrow with a condition written on it.
- `$\ce{CaCO3(s) <=> CaO(s) + CO2(g)}$` gives an equilibrium.

The example course has a page named What This Site Can Do, in its Style folder. It holds a table of these forms, each one shown as typed and as drawn. See [Look around with the example course](page:example-course).

{{picture:notation-2}}
alt: Chemical formulas and an equation, typeset on a page of the example course's website.

## An amount of money

A dollar sign starts mathematics. Two dollar amounts in one paragraph are read as mathematics between them, and the words between them come out wrong.

Type a backslash before the dollar sign of a price:

```text wrap
A ticket costs \$14 and the trip costs \$2.3 million.
```

Inside a formula, a backslash and a dollar sign do not work. Type `\textdollar` there, as in `\textdollar 14`.

Several ready-made courses show this on their own What This Site Can Do page. The Business one, BOH4M, has it under the heading Money and numbers.

## Where it is typeset

Mathematics and chemistry are typeset when the website is made. A student's browser downloads nothing more to show them.

Obsidian draws mathematics between dollar signs itself. To see a page as students will, chemistry and prices included, preview the section. If a preview is already running, choose {{menu:rebuildPreview}}.

## If it does not work

- **The rest of a sentence has turned into mathematics.** A price in it has a dollar sign with no backslash before it.
- **A formula shows as plain text in Obsidian.** Take out the space after the first dollar sign and before the last.
- **A formula in a box is broken.** Put the whole of it, with both pairs of dollar signs, on one line.
- **Words have vanished from the page.** Text between two pairs of per cent signs, `%%`, is taken off the page. Do not type two per cent signs together.
