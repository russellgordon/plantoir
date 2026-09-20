---
title: Community Lexicon Search
publish: true
created: __CREATED__
tags:
  - programs
---
FirstVoices and other community-led language projects rely on robust dictionary
lookups. This program implements a simple searchable lexicon mapping English terms
to a local Indigenous language (for example, SENĆOŦEN or hən̓q̓əmin̓əm̓).

## The program

```python
# Community Lexicon Search
# Allows users to look up words and safely handles missing terms

lexicon = {
    "water": "QO,",
    "bear": "SPÁEṮ",
    "raven": "SḰAÚE",
    "eagle": "YEXÁ,",
    "salmon": "SĆOŦEN"
}

print("--- Lexicon Search ---")
print(f"Loaded {len(lexicon)} terms.")

while True:
    search_term = input("\nEnter English word (or 'quit' to exit): ").lower()
    
    if search_term == "quit":
        break
        
    if search_term in lexicon:
        translation = lexicon[search_term]
        print(f"Result: {translation}")
    else:
        print(f"'{search_term}' is not in the current dictionary.")
        print("Would you like to contribute it? Contact the community center.")

print("Exiting search. HÍSW̱ḴE (Thank you).")
```

```
--- Lexicon Search ---
Loaded 5 terms.

Enter English word (or 'quit' to exit): raven
Result: SḰAÚE

Enter English word (or 'quit' to exit): deer
'deer' is not in the current dictionary.
Would you like to contribute it? Contact the community center.

Enter English word (or 'quit' to exit): quit
Exiting search. HÍSW̱ḴE (Thank you).
```

## How it works

The core of this program is a dictionary called `lexicon`. Dictionaries are optimized for exact-match lookups. 

The `while True:` loop creates an interactive prompt. It uses `.lower()` on the input so that if a user types "Raven", it still matches the lowercase key `"raven"`.

Before retrieving a value, the program checks `if search_term in lexicon`. This prevents a `KeyError` from crashing the program if the user searches for a missing word.

## Change it

1. **One line.** Add `"cedar"` to the dictionary with an appropriate placeholder or real translation.
2. **A few lines.** Add a counter that tracks how many successful searches the user makes during their session, and print that summary when they quit.
3. **A real change.** Make the dictionary two-way. Instead of just strings, store lists: `"water": ["QO,", "noun"]`. When a word is found, print both the translation and its part of speech.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]
%%curriculum-end%%
