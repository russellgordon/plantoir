---
title: Music
codeRunner: true
---
The rendered check's music page (plantoir-rendered-check-679). The first tune plays in flute with its chords on piano, so a press fetches two sounds from the site's own copy. The second has no Play button. The quiz's choices are tunes, drawn without Play. The program at the bottom reads a line, so the page is isolated for live input where the host allows it, and the tunes must play there too.

```abc
% alt: Eight bars in D for flute, with chords on piano (plantoir-rendered-music).
% sound: flute
% chords: piano
X:1
T:A walk in D
M:4/4
L:1/4
Q:1/4=160
K:D
"D"F F G A | "A"A G F E | "D"D D E F | "A"F3/2 E/ E2 |]
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

> [!quiz] Which of these is a D major chord?
> - [x] The first
>   ```abc
>   % alt: The notes D, F sharp and A sounding together.
>   X:3
>   L:1/4
>   K:D
>   [DFA]4 |]
>   ```
> - [ ] The second
>   ```abc
>   % alt: The notes D, G and B sounding together.
>   X:4
>   L:1/4
>   K:D
>   [DGB]4 |]
>   ```

```python run
name = input("Who is there? ")
print("Hello, " + name)
```
