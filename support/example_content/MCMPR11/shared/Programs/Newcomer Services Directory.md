---
title: Newcomer Services Directory
publish: true
created: __CREATED__
tags:
  - programs
---

BC settlement agencies like ISSofBC (Immigrant Services Society of BC) —
founded in 1968 and now the largest multicultural immigrant-serving
agency in western Canada — support tens of thousands of newcomers a year,
across dozens of languages, from Punjabi and Cantonese to Tagalog and
Ukrainian. A front-desk worker needs to know, fast, which staff member or
service line can help a client in their own language. This program
models that lookup.

## The program

```python
# Newcomer Services Directory
# Looks up which staff service line can help in a given language

directory = {
    "punjabi": "Settlement Line 2 – Amandeep K.",
    "cantonese": "Settlement Line 4 – Wing-Yan L.",
    "mandarin": "Settlement Line 4 – Wing-Yan L.",
    "tagalog": "Settlement Line 1 – Jasmine R.",
    "ukrainian": "Settlement Line 5 – Oksana P.",
    "spanish": "Settlement Line 3 – Carlos M."
}

print("--- Newcomer Services Directory ---")
print(f"{len(directory)} languages currently covered by in-house staff.")

while True:
    language = input("\nEnter a language (or 'quit' to exit): ").lower()

    if language == "quit":
        break

    if language in directory:
        contact = directory[language]
        print(f"Contact: {contact}")
    else:
        print(f"No in-house staff currently listed for '{language}'.")
        print("Connect the client through the phone interpretation line instead.")

print("Exiting directory.")
```

```
--- Newcomer Services Directory ---
6 languages currently covered by in-house staff.

Enter a language (or 'quit' to exit): Cantonese
Contact: Settlement Line 4 – Wing-Yan L.

Enter a language (or 'quit' to exit): Dari
No in-house staff currently listed for 'dari'.
Connect the client through the phone interpretation line instead.

Enter a language (or 'quit' to exit): quit
Exiting directory.
```

## How it works

The core of this program is a dictionary called `directory`, mapping a
language name to the staff member or service line that covers it.
Dictionaries are the right structure here because a front-desk worker
never needs "the third language on the list" — they need one specific
language, looked up fast, with one specific answer back.

`.lower()` normalizes the input, the same trick used in
[[Community Lexicon Search]], so "Cantonese", "cantonese", and
"CANTONESE" all match the same key.

`if language in directory` checks before the lookup happens. Real
settlement agencies cover dozens of languages between in-house staff and
phone interpretation, but no agency has in-house staff for every language
a client might speak — so the program's "not found" branch isn't an error
case to hide, it's the realistic majority of possible inputs, and it
routes the worker to a real fallback (the interpretation line) instead of
leaving them stuck.

## Change it

1. **One line.** Add `"vietnamese"` to the dictionary with a service
   line of your choice.
2. **A few lines.** Add a counter that tracks how many searches had to
   fall back to the interpretation line, and print that summary when the
   worker quits.
3. **A real change.** Some languages have more than one in-house staff
   member. Make the dictionary's values lists instead of single
   strings — `"cantonese": ["Wing-Yan L.", "Derek T."]` — and when a
   language is found, print every contact available for it, not just
   one.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]
%%curriculum-end%%
