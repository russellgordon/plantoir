---
title: Diagrams
---
The rendered check's diagrams page (plantoir-rendered-check-597). A diagram, a formula and a drawing.

```mermaid
graph LR
  A[Start] --> B[Add the numbers]
  B --> C[Finish]
```

A formula in a line, $a^2 + b^2 = c^2$, and one on its own:

$$\frac{19 + 23}{2} = 21$$

```tikz
% alt: A right triangle with sides 3, 4 and 5 (plantoir-rendered-tikz)
\begin{document}
\begin{tikzpicture}
  \draw[thick] (0,0) -- (4,0) -- (4,3) -- cycle;
  \node at (2,-0.4) {$4$};
  \node at (4.4,1.5) {$3$};
  \node at (1.7,1.9) {$5$};
\end{tikzpicture}
\end{document}
```
