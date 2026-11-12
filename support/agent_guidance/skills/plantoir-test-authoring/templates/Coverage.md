# Coverage: Unit 2 Test: Chemical Reactions

<!-- A STARTING POINT, filled in for the worked example. The SECOND reviewer
fills this in, a different agent from the writer and from the reviewer who
re-solved the answers. Change the columns and the wording freely; keep one
row per question, the class each was taught in, and the version-against-
version check. -->

Filled in by the second reviewer. Every question is checked against the
class it was taught in, and Version A against Version B item by item.

## Questions against what was taught

| Question | Points | Taught in | What it tests |
|---|---|---|---|
| A1 | `A1` | Unit 2, Days 3 to 5 (Chemical Formulas and Names) | the formula of an ionic compound from its name |
| A2 | `A2` | Unit 2, Days 7 and 9 (Balancing Equations, conservation of mass) | mass in a sealed container |
| A3 | `A3` | Unit 2, Days 10 and 11 (Types of Chemical Reactions) | naming the type of a reaction |
| A4 | `A4` | Unit 2, Day 12 (Acids and Bases) | comparing two solutions by pH |
| B1 | `B1.1`-`B1.4` | Unit 2, Days 7 to 9 (Balancing Equations); combustion on Days 10 and 11 | balancing a combustion equation |
| B2 | `B2.1`, `B2.2` | Unit 2, Days 9, 15 and 16 (masses before and after) | mass when a gas escapes |
| C1 | `C1.1`-`C1.3` | Unit 2, Days 1 and 2 (Evidence of a Chemical Change) | physical and chemical change |
| D1 | `D1.1`-`D1.3` | Unit 2, Days 10, 11 and 21 (predicting products) | a single displacement, written and balanced |

## Version A against Version B

| Question | Same concept | Same steps | Same size of numbers | Same trap | Same reading load | Right answer | Notes |
|---|---|---|---|---|---|---|---|
| A1 | yes | yes | n/a | yes: a look-alike symbol | yes | b / d | |
| A2 | yes | yes | yes: 12.0 g / 18.5 g | yes | yes | a / b | |
| A3 | yes | yes | n/a | yes | yes | d / a | |
| A4 | yes | yes | yes: 2 steps / 3 steps of pH | yes: reading the scale as linear | yes | c / b | |
| B1 | yes | yes: both need the doubling | yes | yes | yes | | |
| B2 | yes | yes | yes | yes | yes | | |
| C1 | yes | yes | n/a | yes: a sign that looks like evidence | yes | | |
| D1 | yes | yes | n/a | yes: a multivalent metal's name | yes | | |

No number a question gives (a mass, a pH) is reused from one version to the
other: Version A gives 12.0 g, pH 2 and 4, 8.40 g and 5.41 g; Version B
gives 18.5 g, pH 6 and 3, 6.20 g and 3.47 g.

## Wording

No double negatives, no buried "not", no options that differ by one small
word. Checked: none found.

## Computed checks

`Checks/check_answers.py` works out A1, A4, B1.4, B2.1, D1.2 and D1.3
again from what each paper gives, checks every Part A answer letter differs
between the versions, every wrong option has a misconception, and no given
number is reused. Result: OK. C1 and B2.2 are explanations and cannot
be computed; the re-solve was their check.

`check_kit.py` with `--paper A`, `--paper B` and `--guide`: OK, 16 points
(K 4, T 6, C 3, A 3). The marks on each paper, the totals on each front and
the Marking Guide's category table agree with the kit.
