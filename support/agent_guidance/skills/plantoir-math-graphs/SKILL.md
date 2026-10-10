---
name: plantoir-math-graphs
description: Use when a Plantoir course page needs a graph of a function, a parabola or line, a linear system, a geometry or similar-triangles diagram, a number line, a probability tree, a circuit, or any drawn figure - anything that would be "graph", "plot", "sketch", "diagram", "TikZ", "triangle", "tree diagram" or "circuit". Says when to use an interactive functionplot graph and when a static TikZ diagram, gives complete patterns to paste (parabola with its parent, two lines meeting, labelled similar triangles, a number line), the limits, what to avoid, and how a figure that cannot be drawn shows up.
---

# Graphs and diagrams on a Plantoir page

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A page can carry two kinds of drawn figure, each written as a
fenced block of plain text in the page itself - never a picture file, an
embed, Desmos, GeoGebra links, an iframe or an image from another website:

- ` ```functionplot ` - an interactive **graph of y = f(x)**. Drawn in the
  student's browser from the site's own files; with a mouse or trackpad a
  student can drag it and zoom with Ctrl/Cmd + scroll (a touch screen just
  scrolls past it). Prints at the bounds you wrote.
- ` ```tikz ` - a **precise static diagram** in LaTeX's TikZ. Plantoir draws
  it once, when the site is built, into a crisp picture that follows the
  site's light or dark theme and prints black on white.

This file is managed by Plantoir and is replaced when Plantoir updates; do
not edit it.

## 1. Which one to use

| The teacher wants | Write | Why |
|---|---|---|
| The graph of one or more functions students can explore | `functionplot` | interactive, axes and grid for free |
| A function compared with its parent (transformations) | `functionplot`, both functions | the two curves on one set of axes |
| Two lines meeting (a linear system), read off a graph | `functionplot` | the crossing is visible; put the point in `alt` and the text |
| The SAME, with the intersection point marked and labelled | `tikz` with `pgfplots` | functionplot cannot mark or label a point |
| Labelled triangles, angles, circles, transformations on a grid | `tikz` | exact positions and labels |
| A number line, an inequality, a probability tree, a Venn diagram | `tikz` | |
| A circuit (`circuitikz`), a molecule (`chemfig`), a commutative diagram (`tikz-cd`) | `tikz` | |
| A flowchart or a timeline | Mermaid (` ```mermaid `) | not a maths figure |

**Not possible** - say so plainly and offer the nearest thing: an
animation, a graph a student can type into, shading between curves, or
points on a functionplot graph. A slider is for GeoGebra, which Plantoir
adds in its next release: say so, and offer the nearest static thing now -
for "y = a(x - 2)^2 with a slider for a", two or three curves with chosen
values of `a` on one functionplot graph, beside the parent `y = x^2`.

## 2. functionplot: the fence

````
```functionplot
---
title: Two lines
xLabel: x
yLabel: y
bounds: [-5, 5, -5, 5]
alt: The lines y = 2x + 1 and y = -x + 4, which cross at (1, 3)
---
y = 2x + 1
y = -x + 4
```
````

- The settings block between `---` lines comes FIRST, then one function per
  line, each with an `=`: `y = x^2` or `f(x) = x^2` (what is drawn is the
  part after the first `=`).
- Settings, all optional: `title`, `xLabel`, `yLabel`,
  `bounds: [xMin, xMax, yMin, yMax]` (four numbers, smallest first in each
  pair; default `[-10, 10, -10, 10]`), `grid` (default `true`),
  `disableZoom: true`, and **`alt`, always** - one sentence a screen reader
  says instead of the graph. Without it a student hears "Graph of y = 2x + 1
  and y = -x + 4, for x from -5 to 5."
- A value with a colon in it needs quotes: `alt: "Graph: two lines"`.
- Choose `bounds` that show what the lesson is about - the vertex, the
  intercepts, the crossing - with a little room around it.
- The grapher's rules, not LaTeX's:
  - `^` for powers, never `**`. `2x` and `2sin(x)` work; write
    `x*(x - 1)`, not `x(x - 1)`.
  - `log(x)` is the NATURAL log; `log10(x)` base 10; base 2 is
    `log(x)/log(2)`. `log(x, 2)` is refused (the base would be ignored).
  - `PI` and `E` in capitals (`E^x`, `sin(PI*x)`). `pi`, `e`, `ln` fail.
  - Brackets on every function: `sin(x)`, never `sin x`.
  - `abs(x)`, not `|x|`; `sqrt(x)`; `cbrt(x)` for cube roots (`x^(1/3)`
    draws only x >= 0); `1/cos(x)` for sec; `asin(x)` for arcsin.
- Colours are chosen for you; at most three or four curves stay readable.

## 3. tikz: the fence

````
```tikz
% alt: Triangle ABC with AB = 6 and BC = 8, beside the larger similar triangle DEF with DE = 9
\begin{document}
\begin{tikzpicture}
  ...
\end{tikzpicture}
\end{document}
```
````

- **First line: `% alt: ...`**, one sentence for a screen reader (a TeX
  comment, so Obsidian draws the same picture). Without it a student hears
  only "A diagram." and the build prints a `plantoir: note:` line.
- `\usepackage{...}` and `\usetikzlibrary{...}` go BEFORE
  `\begin{document}`; the picture between `\begin{document}` and
  `\end{document}`. **Never `\documentclass`** - it stops the drawing.
- **One `tikzpicture` per fence**: only the first is drawn.
- Packages that work (measured): `pgfplots` (add
  `\pgfplotsset{compat=1.16}`), `circuitikz`, `chemfig`, `tikz-cd`,
  `tikz-3dplot`, `amsmath`, `amssymb`, `graphicx`; libraries `angles`,
  `quotes`, `arrows.meta`, `calc`, `positioning`, `decorations.markings`
  and TikZ's other standard ones. **Not available (measured):** `siunitx`,
  `mathtools`, `tkz-euclide`, and the pgfplots library `fillbetween` - shade
  with `\fill` and a closed path instead. Any other package: preview once
  before relying on it. Write units by hand: `$5\,\mathrm{cm}$`.
- Comments with ONE `%`. A `%%` anywhere on a page is removed by the
  website before it reads the page (inside fences too).
- Colours: black and white follow the reader's theme; other colours are
  drawn as written. Prefer `red`, `orange`, `teal` to pure `blue`, which is
  dim on a dark page.
- Use 1 unit = 1 cm and keep a diagram about 6-12 units wide.

## 4. Worked patterns (paste, then change the numbers)

### A. A transformed parabola beside its parent

The student gets one graph with two curves - the parent `y = x^2` and the
transformed parabola - so the stretch, flip and slide are visible at once.

````
```functionplot
---
title: y = -2(x - 1)^2 + 3 and its parent
bounds: [-4, 5, -6, 10]
alt: The parent parabola y = x^2 and y = -2(x - 1)^2 + 3, which opens down, is narrower, and has its vertex at (1, 3)
---
y = x^2
y = -2(x - 1)^2 + 3
```
````

For "several values of a", add one line per value
(`y = 0.5(x - 2)^2`, `y = (x - 2)^2`, `y = 3(x - 2)^2`) and say in the text
which is which: the curves are coloured, not labelled.

### B. A linear system: two lines and where they meet

Interactive, the point described in words:

````
```functionplot
---
bounds: [-2, 5, -2, 7]
alt: The lines y = 2x + 1 and y = -x + 4 cross at the point (1, 3)
---
y = 2x + 1
y = -x + 4
```
````

Static, with the point marked and labelled:

````
```tikz
% alt: The lines y = 2x + 1 and y = -x + 4 cross at the marked point (1, 3)
\usepackage{pgfplots}
\pgfplotsset{compat=1.16}
\begin{document}
\begin{tikzpicture}
\begin{axis}[axis lines=middle, xlabel=$x$, ylabel=$y$, xmin=-2, xmax=5, ymin=-2, ymax=7, grid=major, width=8cm]
\addplot[domain=-1.5:3, thick, red] {2*x + 1};
\addplot[domain=-2:5, thick, teal] {-x + 4};
\node[red, left] at (axis cs:2.4,5.8) {$y = 2x + 1$};
\node[teal, above right] at (axis cs:2.6,1.4) {$y = -x + 4$};
\addplot[only marks, mark=*] coordinates {(1,3)} node[right] {$(1, 3)$};
\end{axis}
\end{tikzpicture}
\end{document}
```
````

### C. Similar triangles with labelled sides

````
```tikz
% alt: Triangle ABC with AB = 6 and BC = 8, beside the similar triangle DEF, 1.5 times larger, with DE = 9 and EF unknown
\begin{document}
\begin{tikzpicture}
  \draw[thick] (0,0) node[below left]{$A$} -- (3,0) node[below right]{$B$} -- (1,2) node[above]{$C$} -- cycle;
  \node[below] at (1.5,0) {$6$};
  \node[above right] at (2,1) {$8$};
  \draw[thick] (5,0) node[below left]{$D$} -- (9.5,0) node[below right]{$E$} -- (6.5,3) node[above]{$F$} -- cycle;
  \node[below] at (7.25,0) {$9$};
  \node[above right] at (8,1.5) {$?$};
\end{tikzpicture}
\end{document}
```
````

Draw corresponding sides in the same positions, so students can match
them by eye; one similar pair is enough per figure.

### D. A number line for an inequality

````
```tikz
% alt: A number line from -5 to 5 with an open circle at -2 and a shaded arrow to the right, showing x > -2
\usetikzlibrary{arrows.meta}
\begin{document}
\begin{tikzpicture}
  \draw[{Stealth}-{Stealth}] (-5.5,0) -- (5.5,0);
  \foreach \x in {-5,...,5} \draw (\x,0.15) -- (\x,-0.15) node[below] {$\x$};
  \draw[very thick, red, -{Stealth}] (-2,0) -- (5.4,0);
  \draw[red, thick, fill=white] (-2,0) circle (0.12);
\end{tikzpicture}
\end{document}
```
````

A closed circle (`x >= -2`) is `fill=red` instead of `fill=white`.

## 5. Where a fence can go

At the top level, inside a callout (folded or not - every line starting
`> `, e.g. a worked solution in `> [!success]- Answer 2`), or in a list
item, indented under it or opened on the item's own line (`1. ```tikz`)
with the following lines indented to match. The language word is exactly
`tikz` or `functionplot`, lowercase.

## 6. Limits

- A diagram that takes longer than **20 seconds** to draw is stopped (it is
  tried again at the next preview). Keep `samples` modest (40-60) and avoid
  loops that build hundreds of objects.
- **On paper** every figure prints whole, black on white, scaled to the
  page's width and to at most about **8 in tall on portrait paper and 6 in
  on landscape** - a tall, narrow diagram prints small, so draw it wider
  rather than taller. Graphs print at the `bounds` written, whatever a
  student zoomed to. Printing a page is the `plantoir-printing` skill.
- functionplot cannot: label or mark points, shade regions, draw vertical
  lines, show inequalities, take parameters or sliders. Use TikZ for those.

## 7. How a problem shows up

Ask the teacher to preview the section in Plantoir. A figure that cannot be
drawn shows students one line - "This diagram couldn't be drawn." or "This
graph couldn't be drawn." - and Plantoir tells the teacher which page,
which figure and which line. The build's output carries a line per problem
for you:

```
plantoir: error: Units/Similar Triangles.md: tikz block 2, line 14: \foo isn't a command LaTeX knows here
plantoir: error: Unit 3/Logarithms.md: functionplot block 1, line 9: “ln” isn't something a graph understands - use log for the natural log, log10 for base 10, PI and E
plantoir: note: Unit 2/Trees.md: tikz block 1, line 5: it has no “% alt:” first line, so a screen reader only says “A diagram.”
```

"tikz block 2" is the page's second tikz fence; the line is the line in the
page's file. Fix that line and preview again; figures already drawn are
remembered, so it is quick.

## 8. Avoid

- `\documentclass`, `\usepackage{tikz}` (harmless but pointless), two
  pictures in one fence, `%%`, `siunitx`.
- In functionplot: `**`, `ln`, `pi`, `e`, `|x|`, `sin x`, `x(x - 1)`,
  settings below the functions, bounds that hide what matters.
- A picture, screenshot or embed of a graph that a fence can draw.
- Promising interactivity functionplot does not have (sliders, points).

## 9. In Obsidian

- **TikZ**: the teacher sees the picture in Obsidian only with the
  community plugin **TikZJax** installed and enabled (Settings ->
  Community plugins -> Browse -> "TikZJax"); Plantoir does not install it
  for them yet. Without it the fence shows as text; the website draws it
  either way, with the same engine, so the picture is the same.
- **functionplot**: the Obsidian plugin that drew these is no longer in
  Obsidian's plugin directory, so in Obsidian the fence shows as plain text.
  The website draws it. Do not tell the teacher to install a plugin for it.
