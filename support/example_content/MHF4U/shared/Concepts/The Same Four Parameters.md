---
title: The Same Four Parameters
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Four times this semester you have met the same four letters wearing
different clothes. The coaster profile in Unit 1 was $y = af(k(x-d)) + c$
built on $x^3$ and $x^4$. The dose curve in Unit 2 moved its asymptotes
with $d$ and $c$. The waves in Unit 3 called $a$ *amplitude* and turned
$k$ into a period. The logarithm in Unit 4 did it once more. This page is
the moment those four stories become one story — and then explains the
rule everybody memorises about the inside working backwards.

## One template, five families

$$y = a\,f\big(k(x - d)\big) + c$$

- **$a$** stretches vertically by $|a|$, and reflects in the $x$-axis
  when it is negative. It is the only one of the four that changes how
  *tall* the picture is.
- **$k$** compresses horizontally by a factor of $\frac{1}{|k|}$, and
  reflects in the $y$-axis when it is negative. It changes how *often*
  the picture happens.
- **$d$** slides the whole thing right by $d$.
- **$c$** slides the whole thing up by $c$.

What changes between families is not the rule but the *vocabulary*, and
what each parameter is allowed to move:

| Family | $a$ is called | $k$ decides | What $d$ and $c$ move |
| --- | --- | --- | --- |
| $f(x) = x^3$, $x^4$ | The vertical stretch | The horizontal compression | The whole curve, and with it the zeros |
| $f(x) = \frac{1}{x}$ | The vertical stretch | The horizontal compression | Both asymptotes — $d$ the vertical, $c$ the horizontal |
| $f(x) = \sin x$, $\cos x$ | The amplitude | The period, $\frac{2\pi}{\lvert k\rvert}$ | $d$ is the phase shift, $c$ is the axis |
| $f(x) = \log_{10} x$ | The vertical stretch | The horizontal compression | $d$ moves the vertical asymptote to $x = d$; $c$ cannot touch it |

That last row is worth a minute. A logarithmic graph has one vertical
asymptote and it lives at the edge of the domain, so only a *horizontal*
move can shift it — which is exactly what the predict-and-check round
found when $\log(x-3)$ moved the asymptote and $\log x + 4$ did not.

> [!note] The logarithm's private joke
> Logarithms are the one family where $a$ and $k$ are not independent of
> $c$. Because $\log_{10}(kx) = \log_{10} k + \log_{10} x$, compressing a
> logarithmic graph horizontally is *indistinguishable* from sliding it
> up: $y = \log_{10}(100x)$ and $y = 2 + \log_{10} x$ are the same curve,
> as [[Laws of Logarithms]] proved algebraically. No other family in this
> course can disguise one transformation as another, and the reason is
> the law, not the picture.

## Why the inside works backwards

Everyone memorises that $f(x - 3)$ moves the graph *right*, and almost
everyone finds it perverse. Composition is the explanation, and it makes
the perversity disappear.

Write the transformation as a composition with a linear function. Let
$g(x) = A(x + B)$. Then $f(g(x)) = f\big(A(x + B)\big)$ — and matching
that against the template gives $k = A$ and $d = -B$. So the parameters
you have been calling "inside" are simply the parameters of the linear
function you fed the graph *before* $f$ ever saw it.

Now the reason. $f$ has not changed at all: it still does whatever it
does to whatever number arrives. To make the output that used to appear
at $x = 0$ appear at $x = 3$ instead, the thing arriving at $f$ must
still be $0$ when $x$ is $3$ — so the inside has to *subtract*. The graph
moves right because the input is being sent backwards to fetch it.

Compose the other way round and everything is ordinary again:
$g(f(x)) = A\big(f(x) + B\big)$ is a vertical stretch by $A$ and a
vertical shift, applied to the answer after $f$ has finished. Outside
transformations act on outputs and behave as you expect; inside
transformations act on inputs and appear to run in reverse. Same rule,
two ends of the machine — which is the point
[[Composing Functions]] makes about domains as well.

## Using it

This is the map to redraw from memory before the examination. Given any
equation from any of the five families, you should be able to name the
four parameters, say what each does, and sketch — and given a graph, run
it the other way. That single skill covers a quarter of
[[Final Examination]] on its own, and it is the reason a new family
never takes as long to learn as the first one did.

%%curriculum-start%%
## Curriculum connection

![[A2.3]]

![[B2.4]]

![[C1.6]]

![[D2.8]]
%%curriculum-end%%
