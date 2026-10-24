---
name: plantoir-math-graphs
description: Use when a Plantoir course page needs a graph of a function, a parabola or line, a linear system, a geometry or similar-triangles diagram, a number line, a probability tree, a circuit, or any drawn figure - anything that would be "graph", "plot", "sketch", "diagram", "TikZ", "triangle", "tree diagram" or "circuit" - and a GeoGebra sketch students drag, a slider, or a .ggb file. Says when to use an interactive functionplot graph, a static TikZ diagram and a GeoGebra sketch, gives complete patterns to paste (parabola with its parent, two lines meeting, labelled similar triangles, a number line), the limits, what to avoid, and how a figure that cannot be drawn shows up.
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
- In functionplot: `**`, `ln`, `pi`, `e`, `|x|`, `sin x`, `x(x - 1)`,
  settings below the functions, bounds that hide what matters.
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
