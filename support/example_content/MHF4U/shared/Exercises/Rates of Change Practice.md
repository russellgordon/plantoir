---
title: Rates of Change Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Rates of Change]] — average rates as secant
slopes, instantaneous rates trapped by shrinking intervals, and the
reading of tangents. No derivative rules exist yet; every answer here
is reasoning you can defend from the definition.

## Average rates

1. Find the average rate of change of $f(x) = x^2$ over the interval
   $1 \le x \le 4$.
2. A ball's height is $h(t) = -5t^2 + 20t$ metres after $t$ seconds.
   Find the average rate of change of height over $0 \le t \le 2$,
   and over $1 \le t \le 3$. Interpret both.
3. A bacterial population follows $P(t) = 100(2)^t$, with $t$ in
   hours. Compare the average rate of change over $0 \le t \le 3$
   with the average rate over $2 \le t \le 3$.

> [!success]- Answer 1
> $\frac{f(4) - f(1)}{4 - 1} = \frac{16 - 1}{3} = 5$. This is the
> slope of the secant through $(1, 1)$ and $(4, 16)$ — nothing more,
> nothing less.

> [!success]- Answer 2
> Over $[0, 2]$: $h(0) = 0$ and $h(2) = -20 + 40 = 20$, so
> $\frac{20 - 0}{2} = 10$ m/s — rising, on average. Over $[1, 3]$:
> $h(1) = 15$ and $h(3) = 15$, so the average rate is $0$ m/s. The
> ball moved plenty — up to its peak at $t = 2$ and back down — but
> it ended the interval at the height it started. An average rate of
> zero means "no net change", not "no motion".

> [!success]- Answer 3
> Over $[0, 3]$: $\frac{800 - 100}{3} = \frac{700}{3} \approx 233$
> bacteria per hour. Over $[2, 3]$: $\frac{800 - 400}{1} = 400$ per
> hour. The later, shorter interval has the *larger* rate — for an
> exponential, the rate of change grows along with the function,
> which is why no single rate summarises it.

## Toward the instantaneous

4. For $f(x) = x^2$, compute the average rate of change over
   $[3, 4]$, $[3, 3.1]$, and $[3, 3.01]$. What are the slopes
   closing in on?
5. A falling object travels $d = 5t^2$ metres in $t$ seconds.
   Estimate its instantaneous speed at $t = 3$ using the interval
   $[3, 3.01]$, and defend your estimate.
6. For the ball in question 2, at what time is the instantaneous
   rate of change of height zero? How do you know without any new
   machinery?

> [!success]- Answer 4
> $[3, 4]$: $\frac{16 - 9}{1} = 7$. $[3, 3.1]$:
> $\frac{9.61 - 9}{0.1} = 6.1$. $[3, 3.01]$:
> $\frac{9.0601 - 9}{0.01} = 6.01$. The secant slopes are settling
> toward $6$ — the slope of the tangent to $y = x^2$ at $x = 3$,
> trapped without ever being computed directly.

> [!success]- Answer 5
> $\frac{5(3.01)^2 - 5(3)^2}{0.01} = \frac{45.3005 - 45}{0.01}
> = 30.05$ m/s, so the instantaneous speed at $t = 3$ is very close
> to $30$ m/s. Defence: the interval is so short that the speed had
> no room to change much inside it, so the average over it can
> barely differ from the value at its left end. A wider interval,
> $[3, 4]$, gives 35 — a worse answer for exactly that reason.

> [!success]- Answer 6
> At the peak, $t = 2$. The parabola's vertex is halfway between the
> zeros $t = 0$ and $t = 4$ — Grade 10 machinery. At the top the
> ball is neither rising nor falling, so the tangent there is
> horizontal: instantaneous rate zero. Before it, tangents tilt up;
> after it, down. (Question 2's second interval already hinted at
> this: the secant from $t = 1$ to $t = 3$ straddles the peak.)

## Interpreting

7. Which does a car's speedometer report — average or instantaneous
   rate of change? When would the two agree over a whole trip?
8. Sketch (roughly) a graph of distance travelled against time for a
   cyclist who rides at a steady speed, slows while climbing a hill,
   then speeds up going down the far side. Where is your graph
   steepest?

> [!success]- Answer 7
> Instantaneous — it reports how fast you are going *now*, the slope
> of the tangent to the distance–time graph at this moment. The two
> agree over a whole trip only when the speed never changes: constant
> speed makes every secant and every tangent the same line.

> [!success]- Answer 8
> Three pieces, all rising — distance travelled never decreases. A
> straight segment first (constant slope, steady speed), then a
> shallower stretch during the climb (still rising, but slowly),
> then the steepest section on the descent. Steepness *is* speed:
> the graph is steepest exactly where the cyclist is fastest, on the
> far side of the hill.

%%curriculum-start%%
## Curriculum connection

![[D1.2]]

![[D1.3]]

![[D1.4]]

![[D1.5]]

![[D1.6]]

![[D1.8]]

![[D1.9]]
%%curriculum-end%%
