---
name: plantoir-math-graphs
description: Use when a Plantoir course page needs a graph of a function, a geometry or probability diagram, a tree diagram, a number line, a circuit, or any drawn figure - anything that would be "graph", "plot", "sketch", "diagram", "TikZ", "triangle", "tree diagram" or "circuit". Says which fence to write (functionplot or tikz), the exact syntax the site draws, the packages that work, the mistakes that stop a figure being drawn, and how to read the build's error lines.
---

# Graphs and diagrams on a Plantoir page

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A page can carry two kinds of drawn figure, each written as a
fenced block of plain text in the page:

- ` ```functionplot ` - an interactive **graph of y = f(x)**. Students can
  drag it (and zoom with Ctrl/Cmd + scroll); it is drawn in their
  browser from the site's own files.
- ` ```tikz ` - a **precise static diagram** in LaTeX's TikZ: geometry,
  number lines, tree diagrams, circuits, labelled axes with pgfplots. Plantoir
  draws it once, when the site is built, into a crisp picture that follows
  the site's light or dark theme.

This file is managed by Plantoir and is replaced when Plantoir updates; do
not edit it.

## 1. Which one to use

| Need | Write |
|---|---|
| The graph of one or more functions, students may explore | `functionplot` |
| A labelled triangle, circle, angle, transformation | `tikz` |
| A probability tree, a number line, a Venn diagram | `tikz` |
| A circuit (`circuitikz`), a chemical structure (`chemfig`), a commutative diagram (`tikz-cd`) | `tikz` |
| Axes with shaded regions, points, asymptotes drawn exactly | `tikz` with `pgfplots` |
| A flowchart or a timeline | Mermaid (` ```mermaid `), not TikZ |

Never embed Desmos, GeoGebra links, an iframe or a picture from another
website for these: the site serves everything itself.

## 2. functionplot

```functionplot
---
title: Two lines
xLabel: x
yLabel: y
bounds: [-5, 5, -5, 5]
alt: Two lines that cross at (1, 3)
---
y = 2x + 1
y = -x + 4
```

- The settings block between `---` lines comes FIRST, then one function per
  line. Every function line needs an `=`: `y = x^2` or `f(x) = x^2` (what is
  drawn is the part after the first `=`).
- Settings (all optional): `title`, `xLabel`, `yLabel`,
  `bounds: [xMin, xMax, yMin, yMax]` (four numbers, smallest first in each
  pair; default `[-10, 10, -10, 10]`), `grid` (default `true`),
  `disableZoom: true` (default `false`), and `alt` - always write `alt`,
  one sentence describing what the graph shows, for students using a screen
  reader (without it they hear "Graph of y = 2x + 1 and y = -x + 4, for x
  from -5 to 5.").
- A setting with a colon in its value needs quotes:
  `alt: "Graph: two lines"`.
- Expression rules, which are the grapher's, not LaTeX's:
  - `^` for powers, never `**`. `2x` and `2sin(x)` work; write `x*(x - 1)`,
    not `x(x - 1)`.
  - `log(x)` is the NATURAL log. Base 10 is `log10(x)`. Base 2 is
    `log(x)/log(2)` - `log(x, 2)` is refused, because the grapher would
    silently ignore the 2.
  - `PI` and `E` in capitals (`E^x`, `sin(PI*x)`); `pi`, `e` and `ln` are not
    understood.
  - Brackets on every function: `sin(x)`, never `sin x` (draws nothing).
  - `abs(x)`, not `|x|`. `sqrt(x)`, `cbrt(x)` (use `cbrt` for cube roots:
    `x^(1/3)` is only drawn for x >= 0). No `sec`, `csc`, `cot`, `arcsin`:
    write `1/cos(x)`, `asin(x)`.
- One graph per fence. Colours are chosen automatically.

## 3. tikz

```tikz
% alt: Two similar triangles; DEF is a 1.5 times enlargement of ABC
\begin{document}
\begin{tikzpicture}
  \draw[thick] (0,0) node[below left]{$A$} -- (3,0) node[below right]{$B$}
    -- (1,2) node[above]{$C$} -- cycle;
  \draw[thick] (5,0) node[below left]{$D$} -- (9.5,0) node[below right]{$E$}
    -- (6.5,3) node[above]{$F$} -- cycle;
\end{tikzpicture}
\end{document}
```

- **First line: `% alt: ...`**, one sentence for a screen reader. It is a
  TeX comment, so Obsidian draws the same picture. Without it students hear
  only "A diagram." and the build prints a `plantoir: note:` line.
- `\usepackage{...}` and `\usetikzlibrary{...}` lines go BEFORE
  `\begin{document}`; the picture goes between `\begin{document}` and
  `\end{document}`. Never write `\documentclass` (it stops the drawing) -
  TikZ is already loaded.
- **One `tikzpicture` per fence**: only the first one is drawn. Two pictures
  need two fences.
- Packages measured to work: `pgfplots` (add `\pgfplotsset{compat=1.16}`),
  `circuitikz`, `chemfig`, `tikz-cd`, `tikz-3dplot`, `amsmath`, `amssymb`,
  `graphicx`; libraries `angles`, `quotes`, `arrows.meta`, `calc`,
  `positioning`, `decorations.markings` (and TikZ's other standard ones).
  NOT available: `siunitx`, `mathtools` - write units by hand
  (`$5\,\mathrm{cm}$`).
- Comments with ONE `%` only. `%%` anywhere in a page is removed by the
  website before it is read, inside a fence too, and that changes the
  drawing.
- Colours: black and white follow the reader's theme (black becomes the
  text colour in dark mode). Other colours (`red`, `blue!60`) are drawn as
  written in both themes; prefer `red`, `orange` or `teal` over pure `blue`,
  which is dim on a dark page.
- Keep it modest: a diagram that takes longer than 20 seconds to draw is
  stopped. A picture taller than a printed page is scaled down to fit one.

## 4. Where a fence can go

Anywhere on a page: at the top level, inside a callout (folded or not, e.g.
inside `> [!example]-`, every line starting `> `), or indented inside a
numbered list item. Backticks or tildes (`~~~tikz`) both work. The language
word must be exactly `tikz` or `functionplot`, lowercase.

## 5. Printing

Diagrams and graphs print on every page, printable or not: black on white
even when the reader is in dark mode, never split across a page, scaled to
the page's width, and graphs at the bounds the teacher wrote whatever a
student zoomed to. A page meant for printing is described by the
`plantoir-printing` skill.

## 6. Check it, and read the errors

Ask the teacher to preview the section in Plantoir. A figure that cannot be
drawn shows students the sentence "This diagram couldn't be drawn." (or
"This graph couldn't be drawn."), and Plantoir tells the teacher which page,
which figure and which line. The build's output carries one line per
problem for you:

```
plantoir: error: Units/Similar Triangles.md: tikz block 2, line 14: \foo isn't a command LaTeX knows here
plantoir: error: Unit 3/Logarithms.md: functionplot block 1, line 9: “ln” isn't something a graph understands - use log for the natural log, log10 for base 10, PI and E
plantoir: note: Unit 2/Trees.md: tikz block 1, line 5: it has no “% alt:” first line, so a screen reader only says “A diagram.”
```

"tikz block 2" is the page's second tikz fence; the line is the line in the
page's file. Fix that line and preview again; a figure that was drawn before
is not drawn again (it is remembered), so previewing is quick.

## 7. In Obsidian

- **TikZ**: the teacher sees the picture in Obsidian only with the
  community plugin **TikZJax** installed and enabled (Settings ->
  Community plugins -> Browse -> "TikZJax"). Plantoir does not install it for
  them yet. Without it the fence shows as text; the website draws it either
  way, with the same engine TikZJax uses, so the picture is the same.
- **functionplot**: the Obsidian plugin that drew these is no longer in
  Obsidian's plugin directory, so in Obsidian the fence shows as plain text.
  The website draws it. Do not tell the teacher to install a plugin for it.
