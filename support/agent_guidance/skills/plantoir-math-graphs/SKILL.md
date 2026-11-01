---
name: plantoir-math-graphs
description: Use when a Plantoir course page needs a graph of a function, a parabola or line, a linear system, a geometry or similar-triangles diagram, a number line, a probability tree, a circuit, or any drawn figure - anything that would be "graph", "plot", "sketch", "diagram", "TikZ", "triangle", "tree diagram" or "circuit" - and a GeoGebra sketch students drag, a slider, or a .ggb file. Says when to use an interactive functionplot graph, a static TikZ diagram and a GeoGebra sketch, gives complete patterns to paste (parabola with its parent, two lines meeting, labelled similar triangles, a number line, the finite-difference scaffold), how far a graph is drawn and when it has arrowheads (an abstract relation or one in context), the limits, what to avoid, and how a figure that cannot be drawn shows up.
---

# Graphs and diagrams on a Plantoir page

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A page can carry three kinds of figure, each written as a
fenced block of plain text in the page itself - never a picture file, an
embed, Desmos, a geogebra.org link or iframe, or an image from another
website:

- ` ```functionplot ` - an interactive **graph of y = f(x)**. Drawn in the
  student's browser from the site's own files; with a mouse or trackpad a
  student can drag it and zoom with Ctrl/Cmd + scroll (a touch screen just
  scrolls past it). Prints at the bounds you wrote.
- ` ```tikz ` - a **precise static diagram** in LaTeX's TikZ. Plantoir draws
  it once, when the site is built, into a crisp picture that follows the
  site's light or dark theme and prints black on white.
- ` ```geogebra ` - a **GeoGebra sketch** students drag, with sliders and
  points that move: from a `.ggb` file, from GeoGebra commands, or from
  geogebra.org. The class website serves GeoGebra itself; the sketch opens
  when a student taps it, and prints as a picture of it (section 10).

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
| Points or a shape students DRAG, a slider, "what changes and what stays the same" | `geogebra` | the only one students can change |
| A sketch the teacher already made in GeoGebra, or found on geogebra.org | `geogebra` with `file:` or `material_id:` | used as it is |
| A flowchart or a timeline | Mermaid (` ```mermaid `) | not a maths figure |

A GeoGebra sketch costs a student a tap and about 3 to 5 MB the first
time; use one when moving something IS the lesson, and a functionplot
graph or a TikZ diagram when looking is enough.

**Not possible in functionplot or TikZ** - points students drag, a
slider, a graph a student can type into, an animation: those are a
GeoGebra sketch (section 10) - for "y = a(x - 2)^2 with a slider for a",
`a = Slider(-3, 3, 0.5)` then `f(x) = a(x - 2)^2` and `g(x) = x^2`.
Shading between curves is TikZ (`\fill` with a closed path).

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
  `mathtools`, `tkz-euclide`, and the pgfplots libraries `fillbetween` -
  shade with `\fill` and a closed path instead - and `groupplots` - one
  graph per fence instead. Any other package: preview once before relying
  on it. Write units by hand: `$5\,\mathrm{cm}$`.
- **Write these instead (measured):** each of the left-hand forms stops the
  whole drawing on the site, though it works in a LaTeX handout.
  - A dot inside an `axis`: not `\fill (axis cs:1,1) circle (2pt);` - a
    radius in parentheses, `circle (2pt)`, fails inside an axis, with or
    without `axis cs:`. Write `\addplot[only marks, mark=*] coordinates
    {(1,1)};`, or `\fill (axis cs:1,1) circle[radius=2pt];`. Outside an
    axis, `circle (2pt)` draws.
  - A degree sign: not `\textdegree`; write it in maths, `$^{\circ}$`.
  - A dollar sign: not `\$` or `\textdollar`; write the plain character,
    `\char36`.
  - Any other symbol written as TEXT that needs lettering the site does not
    have. Measured: `\$`, `\textdollar`, `\textdegree`, `\S`, `\pounds`,
    `\copyright`, `\textbullet`, `\textmu` and `\textcent` all stop the
    drawing, in any fence and not only in an axis label. Write the symbol
    in maths, or as the plain character. `\textsf`, `\texttt`, `\textsc`,
    `\mathbb` and bold italic draw.

  The build names this problem. Its `plantoir: error:` line (section 7)
  for that figure ends with the sentence Plantoir's contract keeps as
  `figureFences.words.reasons.fontMissing`, which says a symbol written as
  text needs lettering diagrams don't have, and to write it in maths or as
  the plain character.
- Comments with ONE `%`. A `%%` anywhere on a page is removed by the
  website before it reads the page (inside fences too).
- Colours: black and white follow the reader's theme; other colours are
  drawn as written. Prefer `red`, `orange`, `teal` to pure `blue`, which is
  dim on a dark page.
- Use 1 unit = 1 cm and keep a diagram about 6-12 units wide.

## 4. Worked patterns (paste, then change the numbers)

Five patterns: A to D below, and E, the finite-difference scaffold.

**First, how far a graph goes - decide it per graph, by whether the
relation has a context.**

- **An abstract relation** (no context: $y = -x^2 + 6x - 5$, a line, a
  parent parabola) goes on past the points that were plotted, so its graph
  is drawn **to the edge of the grid with an arrowhead at each end**, and
  the plotted points stay on it. In a `tikz` fence with `pgfplots`, put
  `<->, >=latex` on the `\addplot` and give it a `domain` that ends where
  the curve meets the edge of the grid (pattern B) - here a grid from
  $x = -1$ to 7 and $y = -6$ to 5:

  ```latex
  \begin{axis}[axis lines=middle, xmin=-1, xmax=7, ymin=-6, ymax=5, grid=major, width=8cm]
  \addplot[<->, >=latex, domain=-0.16:6.16, samples=50, thick, red] {-x^2 + 6*x - 5};
  \addplot[only marks, mark=*] coordinates {(1,0) (2,3) (3,4) (4,3) (5,0)};
  \end{axis}
  ```

  Measured on the site's own engine (node-tikzjax 1.0.5): `<->, >=latex`
  draws an arrowhead at both ends of an `\addplot` inside an `axis`, as do
  `>=stealth` and `arrows.meta`'s `{Latex}-{Latex}`. Solve the relation
  against **every** edge of the grid - left, right, top and bottom - and
  stop the domain, on each side, at the FIRST edge the curve crosses, so
  both arrowheads stay inside. On this grid the parabola meets the bottom
  edge $y = -6$ at $x = 3 \pm \sqrt{10}$, about -0.16 and 6.16, both inside
  $-1$ to 7. On a grid from -6 to 6 both ways it reaches the right edge
  $x = 6$ first, so the domain ends at 6 there: `-0.16:6.16` on that grid
  draws only the left arrowhead (measured). **Never let the domain run
  past the edge**: the axis clips the curve there and the arrowheads are
  cut off with it (`domain=-1:7` on the grid above draws none).
- **A relation that models a context** (a bridge arch, a ball in flight,
  supply and demand) stops at the end points the situation gives it - the
  arch's two feet, the moment the ball lands - with **no arrowheads**:
  `\addplot[domain=0:40, samples=50, thick, red] {-0.05*(x - 20)^2 + 20};`,
  with a dot on an end point where it matters.
- **functionplot** always draws every curve across the whole window, and
  further as a student drags it; it cannot end a curve at a point or draw
  an arrowhead. That suits an abstract relation explored on screen
  (patterns A and B's interactive graph). A graph that models a context,
  and a graph whose arrowheads should show on paper, is a `tikz` fence.

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
% No context, so each line runs to the edge of the grid with an arrowhead at each end
\addplot[<->, >=latex, domain=-1.5:3, thick, red] {2*x + 1};
\addplot[<->, >=latex, domain=-2:5, thick, teal] {-x + 4};
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

### E. The finite-difference scaffold

The first table of a day that meets first or second differences carries
this figure; later tables that day are plain Markdown tables. A curved arrow
starts at each lower value and points up to the one above it, labelled with
the whole subtraction, lower minus upper, negatives in parentheses; a second
column does the same for second differences. It is the same figure a
printed handout carries (`plantoir-handouts` section 10, whose
`patterns/finite_differences.py` prints this fence for any table with
`--page --alt "..."`). By hand: change the y values in the table nodes, then
each subtraction and its result. In a column holding a negative value (or
whole numbers beside decimals) each value is written
`\inbox{$widest$}{$value$}`: right-aligned in a box as wide as the column's
widest value without its sign, the box centred, so the digits line up and a
minus sign juts out to the left - change the first argument too when the
widest value changes.

````
```tikz
% alt: A table of y = x^2 - 3 for x from -2 to 2, with arrows from each y value up to the one above it labelled with the subtraction: first differences -3, -1, 1, 3 and second differences 2, 2, 2.
\begin{document}
\begin{tikzpicture}[font=\small]
\definecolor{diffcol}{RGB}{0,128,128}
\definecolor{headfill}{RGB}{70,100,170}
\tikzset{num/.style={anchor=center, inner sep=0pt, text height=1.5ex, text depth=0pt},
  dif/.style={anchor=east, inner sep=0pt, text height=1.6ex, text depth=0.45ex, text=diffcol, font=\footnotesize},
  diffarrow/.style={diffcol, thin, -stealth}}
% The table of values: a shaded heading row, a full outer border, one ruled row for each x;
% the x and y columns are one width, and each value is centred in its row
% \inbox{widest}{value}: the value right-aligned in a box as wide as the widest, the box centred
\def\inbox#1#2{\setbox0\hbox{#1}\hbox to\wd0{\hss#2}}
\fill[headfill, fill opacity=0.13] (0,0) rectangle (1.74,-0.75);
\draw (0,0) rectangle (1.74,-3.850);
\draw (0.87,0) -- (0.87,-3.850);
\draw (0,-0.750) -- (1.74,-0.750);
\draw (0,-1.370) -- (1.74,-1.370);
\draw (0,-1.990) -- (1.74,-1.990);
\draw (0,-2.610) -- (1.74,-2.610);
\draw (0,-3.230) -- (1.74,-3.230);
\node at (0.435,-0.375) {$x$};
\node at (1.305,-0.375) {$y$};
% A column with any negative value, or whole numbers beside decimals, is right-aligned in
% its box (\inbox); any other column of numbers is centred
\node[num] at (0.435,-1.060) {\inbox{$2$}{$-2$}};
\node[num] at (0.435,-1.680) {\inbox{$2$}{$-1$}};
\node[num] at (0.435,-2.300) {\inbox{$2$}{$0$}};
\node[num] at (0.435,-2.920) {\inbox{$2$}{$1$}};
\node[num] at (0.435,-3.540) {\inbox{$2$}{$2$}};
\node[num] at (1.305,-1.060) {\inbox{$1$}{$1$}};
\node[num] at (1.305,-1.680) {\inbox{$1$}{$-2$}};
\node[num] at (1.305,-2.300) {\inbox{$1$}{$-3$}};
\node[num] at (1.305,-2.920) {\inbox{$1$}{$-2$}};
\node[num] at (1.305,-3.540) {\inbox{$1$}{$1$}};
% First differences: each arrow starts at the lower value and points up to the one above it;
% beside it, the subtraction: lower value minus the one above it
\node[font=\scriptsize\sffamily\bfseries, align=center, anchor=south] at (3.340,-0.700) {First\\differences};
\draw[diffarrow] (1.810,-1.630) .. controls (2.226,-1.604) and (2.114,-1.370) .. (1.880,-1.110);
\node[dif] at (3.770,-1.370) {$-2 - 1$}; \node[dif, anchor=west] at (3.770,-1.370) {${}= -3$};
\draw[diffarrow] (1.810,-2.250) .. controls (2.226,-2.224) and (2.114,-1.990) .. (1.880,-1.730);
\node[dif] at (3.770,-1.990) {$-3 - (-2)$}; \node[dif, anchor=west] at (3.770,-1.990) {${}= -1$};
\draw[diffarrow] (1.810,-2.870) .. controls (2.226,-2.844) and (2.114,-2.610) .. (1.880,-2.350);
\node[dif] at (3.770,-2.610) {$-2 - (-3)$}; \node[dif, anchor=west] at (3.770,-2.610) {${}= 1$};
\draw[diffarrow] (1.810,-3.490) .. controls (2.226,-3.464) and (2.114,-3.230) .. (1.880,-2.970);
\node[dif] at (3.770,-3.230) {$1 - (-2)$}; \node[dif, anchor=west] at (3.770,-3.230) {${}= 3$};
% Second differences: each arrow starts at the lower value and points up to the one above it;
% beside it, the subtraction: lower value minus the one above it
\node[font=\scriptsize\sffamily\bfseries, align=center, anchor=south] at (6.380,-0.700) {Second\\differences};
\draw[diffarrow] (4.850,-1.916) .. controls (5.266,-1.892) and (5.154,-1.680) .. (4.920,-1.444);
\node[dif] at (6.810,-1.680) {$-1 - (-3)$}; \node[dif, anchor=west] at (6.810,-1.680) {${}= 2$};
\draw[diffarrow] (4.850,-2.536) .. controls (5.266,-2.512) and (5.154,-2.300) .. (4.920,-2.064);
\node[dif] at (6.810,-2.300) {$1 - (-1)$}; \node[dif, anchor=west] at (6.810,-2.300) {${}= 2$};
\draw[diffarrow] (4.850,-3.156) .. controls (5.266,-3.132) and (5.154,-2.920) .. (4.920,-2.684);
\node[dif] at (6.810,-2.920) {$3 - 1$}; \node[dif, anchor=west] at (6.810,-2.920) {${}= 2$};
\node[font=\scriptsize, text=gray, anchor=north, text width=7.34cm, align=center] at (3.795,-3.950) {Each difference is the lower value minus the one above it.};
\end{tikzpicture}
\end{document}
```
````

For first differences only (the first time differences appear in a unit),
leave out the "Second differences" heading and its three arrows and lines,
and move the caption's `at (...)` x to half the new width. Never on a quiz,
test or practice test page.

## 5. Where a fence can go

At the top level, inside a callout (folded or not - every line starting
`> `, e.g. a worked solution in `> [!success]- Answer 2`), or in a list
item, indented under it or opened on the item's own line (`1. ```tikz`)
with the following lines indented to match. The language word is exactly
`tikz`, `functionplot` or `geogebra`, lowercase.

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
  lines, show inequalities, take parameters or sliders. Use TikZ for the
  first four, a GeoGebra sketch for parameters and sliders.

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
- `groupplots`, `\textdegree`, `\$`, `\textdollar` and the other text
  symbols section 3 lists, and a dot drawn as `circle (2pt)` inside an
  `axis` - section 3 says what to write instead.
- In functionplot: `**`, `ln`, `pi`, `e`, `|x|`, `sin x`, `x(x - 1)`,
  settings below the functions, bounds that hide what matters.
- A graph of an abstract relation that stops short of the grid's edge or
  has no arrowheads; a `domain` that runs past the grid's edge (the
  arrowheads are clipped off); arrowheads on a graph that models a context
  (section 4).
- A picture, screenshot or embed of a graph that a fence can draw.
- Promising interactivity functionplot does not have (sliders, points) -
  that is a GeoGebra sketch.
- A geogebra.org `<iframe>` or link: a ` ```geogebra ` block with
  `material_id:` shows the same sketch from the class website.

## 9. In Obsidian

- Obsidian draws a fence only when the add-on for it is installed and
  switched on in that course: **TikZJax** for `tikz`, **Functionplot** for
  `functionplot`. Without it the fence shows as text in Obsidian; the website
  draws it either way, with the same engine for TikZ, so the picture is the
  same.
- **Never install, download or edit anything under `.obsidian` yourself** —
  not an add-on, not `community-plugins.json`, not a setting. Adding
  add-ons is the teacher's choice, not yours.
- The functionplot add-on is no longer in Obsidian's own Browse list, so do
  not tell the teacher to search for it there.
- If the teacher says Obsidian shows a fence as text: the add-on is missing
  from that course or switched off. The first time a course opens with
  add-ons, Obsidian asks whether they trust its author; the answer that turns
  them on is "Trust author and enable plugins". Settings > Community plugins
  in Obsidian shows which add-ons the course has and whether they are on.

## 10. GeoGebra sketches students drag

````
```geogebra
file: Slope Angle Conjecture.ggb
alt: Three right triangles that share one marked angle, set by a slider; points B, E and H resize them.
caption: Drag B, E or H. Then move the angle slider.
```
````

Say which sketch in ONE of three ways:

1. **A file.** `file:` names a `.ggb` saved from GeoGebra, put beside the
   page (or in `Media`); a relative path such as `Unit 4/Slope.ggb` from
   the course folder works too. At most 20 MB.
2. **Commands**, one per line, exactly as typed in GeoGebra's Input Bar,
   after the settings - on their own, or after `file:` or `material_id:`
   to change the sketch it opened:

   ````
   ```geogebra
   alt: The parabola y = a(x - 2)^2 beside y = x^2, with a slider for a.
   a = Slider(-3, 3, 0.5)
   f(x) = a(x - 2)^2
   g(x) = x^2
   SetColor(g, "gray")
   ```
   ````

   `//` starts a line that is only a note. GeoGebra reads the commands
   only in the student's browser, so a mistake shows under the sketch as
   "Line 4 couldn't run: …" in GeoGebra's own words - open the sketch in
   the preview once to check.
3. **A sketch on geogebra.org.** `material_id:` with its id or address
   (`material_id: https://www.geogebra.org/m/ju3f2kbg`). Plantoir keeps a
   copy the FIRST time the site is built and never asks geogebra.org
   again for that block, so students never wait on geogebra.org. To get a
   sketch the teacher has since changed there, change the block - add or
   raise `version: 2` - and the next preview fetches it again. The sketch
   is shown with its author and its licence (CC BY-NC-SA) under it.

Settings, before the commands, one `key: value` per line, in small
letters (a `---` line after them is allowed): `file`, `material_id`,
`alt` (**always** - what a screen reader says instead of the sketch),
`caption` (a line under it), `app` (`classic`, `graphing`, `geometry` or
`3d`), `width` and `height` (pixels; a commands sketch is 800 by 500, a
file keeps its own size, and a wide sketch is scaled down to the page),
`toolbar` and `algebra` (`true` or `false`), and `version` (does nothing
but change the block). Use `file:` or `material_id:`, never both.

- **Where it can go**: anywhere a functionplot fence can (section 5), and
  in a self-check question's QUESTION or EXPLANATION - never inside one
  of its choices (the `plantoir-quizzes` skill).
- **On paper** it prints as a picture of the sketch as the student left
  it (its thumbnail if never opened), with "Made with GeoGebra".
- **`file:` is plain text, not a link.** Renaming the `.ggb` in Obsidian
  does not change the `file:` line, and Copy a Page does not copy the
  file. Keep the name in step, or put the `.ggb` in `Media`, where it is
  found by its name from any page.
- **Obsidian hides `.ggb` files** in its file list until Settings > Files
  and links > "Detect all file extensions" is turned on; the file is
  there either way. Obsidian shows the block as text. A community add-on
  (vanabel/obsidian-geogebra, which reads the same settings) draws it
  inside Obsidian on a computer, loading GeoGebra from geogebra.org; it is
  optional and unreviewed, the website does not need it, and installing
  it is the teacher's choice, not yours.
- **English only**: GeoGebra's own words in a sketch are in English.

A sketch that cannot be shown stays a block of text on the page, and the
preview says which page, which block and which line:

```
plantoir: error: Unit 4/Slope.md: geogebra block 1, line 3: Slope.ggb isn't beside the page, in the course folder or in Media (a renamed file or a copied page keeps the old name here - put the .ggb in Media, or change the file: line)
plantoir: note: Unit 4/Slope.md: geogebra block 2: it has no alt: line, so a screen reader only says “A GeoGebra sketch.”
```
