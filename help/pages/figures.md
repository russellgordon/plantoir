---
id: figures
checked: 2.0.0
covers:
- contracts/shared-rules.json
- scripts/build_site.py
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
keywords:
- diagram
- diagrams
- TikZ
- tikz
- LaTeX
- graph
- graphs
- function plot
- functionplot
- plot a function
- parabola
- alt text
- screen reader
- diagram not drawn
description: Type a tikz block for a drawn diagram or a functionplot block for a graph students can move, each with a description for screen readers.
---
A page can show a diagram drawn from TikZ, and a graph of functions that students can move. You type each as a block of text on the page. This page gives the form of both blocks.

No setting turns this on. The block is all a page needs.

> [!note]
> The examples on this page stop before the block's last line. Remember the three backticks that close the block.

## A drawn diagram

1. In Obsidian, start a block with three backticks and the word `tikz`.
2. On the block's first line, type `% alt:` and a description of the diagram, for students who use a screen reader.
3. Type the TikZ picture, with `\begin{document}` before it and `\end{document}` after it.
4. End the block with a line of three backticks.

```text wrap
```tikz
% alt: A right triangle with sides of 3, 4 and 5 units.
\begin{document}
\begin{tikzpicture}
\draw (0,0) -- (4,0) -- (4,3) -- cycle;
\end{tikzpicture}
\end{document}
```

The diagram is drawn when the website is made, and it is placed in the page as a picture. Students download nothing to see it.

{{picture:figures-1}}
alt: A tikz block as typed in Obsidian, beside the diagram it becomes on the class website.

## A graph students can move

1. Start a block with three backticks and the word `functionplot`.
2. If you want settings, type them first, between two `---` lines. Give the graph a description here, on a line that starts `alt:`.
3. Type one function on each line, such as `y = x^2`.
4. End the block with a line of three backticks.

```text wrap
```functionplot
---
title: Two functions
xLabel: x
yLabel: y
bounds: [-5, 5, -2, 10]
alt: A parabola that opens upward, and a line that crosses it twice.
---
y = x^2
y = x + 2
```

The settings are `title`, `xLabel`, `yLabel`, `bounds`, `disableZoom`, `grid` and `alt`. The four numbers of `bounds` are the least x, the greatest x, the least y and the greatest y. Without it, the graph runs from -10 to 10 each way.

The graph is drawn in the student's own browser. A student drags it to move it. To zoom, they hold Command or Ctrl while they scroll with a trackpad or a mouse. On a touch screen, a drag scrolls the page instead.

{{picture:figures-2}}
alt: A graph of two functions on the class website, which a student can drag to move.

## If you leave the description out

A screen reader then says only this of a diagram:

{{say:shared-rules#figureFences.words.site.untitledDiagram}}

A graph without a description is described from its functions and the range of x it shows.

## Check your work

Preview the section and look at the page. If a preview is already running, choose {{menu:rebuildPreview}}.

A diagram or graph that cannot be drawn shows students one of these sentences in its place:

{{say:shared-rules#figureFences.words.site.diagramCouldNotBeDrawn}}

{{say:shared-rules#figureFences.words.site.graphCouldNotBeDrawn}}

The section's {{control:problemsTab}} tab names the page and gives the reason in plain words. One reason is a diagram that lacks `\begin{document}` and `\end{document}`. A diagram is given 20 seconds to draw. See [The Problems tab](page:problems).

## In Obsidian

Obsidian by itself shows both blocks as text. Two add-ons draw them there: see [See diagrams and graphs in Obsidian too](page:obsidian-addons).

Flow charts and other diagrams written as Mermaid are a different kind of block. See [Diagrams drawn from text](page:diagrams-from-text).
