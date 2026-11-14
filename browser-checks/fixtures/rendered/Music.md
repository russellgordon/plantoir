---
title: Music
codeRunner: true
---
The rendered check's music page (plantoir-rendered-check-679). The first tune plays in flute with its chords on piano, so a press fetches two sounds from the site's own copy. The second has no Play button. The third is written on one long line, so the build draws it again broken into lines the page can show at its own size. The quiz's question holds a tune with Play, which works there; a tune in a choice is refused, and is a recognise case on verify.sh's Quiz Fixture. The program at the bottom reads a line, so the page is isolated for live input where the host allows it, and the tunes must play there too.

```abc
% alt: Four bars in D for flute, with chords on piano (plantoir-rendered-music).
% sound: flute
% chords: piano
X:1
T:Steps and leaps in D
M:4/4
L:1/4
Q:1/4=160
K:D
"D"D2 F A | "G"B2 A G | "A"E F G E | "D"F3/2 E/ D2 |]
```

```abc
% play: no
X:2
T:Rhythm only
M:3/4
L:1/4
K:C
C C C | C2 C | C3 |]
```

```abc
% alt: Twenty-four bars of steps in D written on one line (plantoir-rendered-music-long).
% play: no
X:3
T:One long line
M:4/4
L:1/4
K:D
D E F G | A B c d | c B A G | F E D2 | D E F G | A B c d | c B A G | F E D2 | D E F G | A B c d | c B A G | F E D2 | D E F G | A B c d | c B A G | F E D2 | D E F G | A B c d | c B A G | F E D2 | D E F G | A B c d | c B A G | F E D2 |]
```

> [!quiz] Which chord is drawn here?
> ```abc
> % alt: The notes D, F sharp and A sounding together.
> X:4
> L:1/4
> K:D
> [DFA]4 |]
> ```
> - [x] D major
> - [ ] G major

```python run
name = input("Who is there? ")
print("Hello, " + name)
```
