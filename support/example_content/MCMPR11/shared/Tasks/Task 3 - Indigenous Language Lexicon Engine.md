---
title: "Task 3 - FirstVoices Lexicon Engine & Indigenous Language Indexer"
publish: true
created: __CREATED__
tags:
  - tasks
  - summative
enableToc: true
---
> [!abstract] At a glance
> Solo or pairs · launched in Unit 3, Day 16 and due Unit 3, Day 20 · dictionary indexing, morphological lookup, and spaced-repetition pronunciation engine for Indigenous languages of British Columbia · dictionaries, key-value modeling, Unicode diacritics, and OCAP® data sovereignty.

## What you are making

A software application designed to support Indigenous language revitalization in British Columbia, modeled after community initiatives such as the **First Peoples' Cultural Council** and the **FirstVoices** digital language platform.

British Columbia is home to over **34 distinct Indigenous languages** across 7 language families—more than half of all Indigenous languages in Canada. These languages include **Hul'q'umi'num'** and **Skwxwú7mesh sníchim** (Coast Salish), **Secwepemctcín** and **Nłeʔkepmxcín** (Interior Salish), **Kwak'wala** (Wakashan), and **Haida** (X̱aayda Kil).

Building language software for BC First Nations presents unique computational and cultural challenges:
1. **Complex Orthographies & Unicode Diacritics:** BC Indigenous languages utilize specialized phonetic characters, combining diacritics, and glottal stops (e.g. `ʔ`, `x̌`, `ł`, `č`, `’`, `á`, `é`). Standard ASCII string operations fail completely on these alphabets.
2. **Polysynthetic Word Formation:** Words frequently incorporate prefixes, suffixes, and root morphemes that express complete sentences.
3. **Indigenous Data Sovereignty:** Language data belongs to the sovereign First Nations communities who speak it. Software developers must follow **OCAP® principles** (Ownership, Control, Access, and Possession).

```
======================================================================
FIRSTVOICES LEXICON ENGINE — HUL'Q'UMI'NUM' LANGUAGE PORTAL
Language Family: Coast Salish | Orthography: Standard Hul'q'umi'num'
======================================================================
[1] English to Hul'q'umi'num' Search
[2] Hul'q'umi'num' to English Search (with Diacritic Normalization)
[3] Morphological Category Browser (Animals, Land, Family, Actions)
[4] Daily Spaced-Repetition Vocabulary Drill
[5] Language Data Sovereignty & Stewardship Statement
[6] Exit Portal

Enter selection (1-6): 2
Enter search term: x̌wiqw
Found 1 exact match and 2 related morphological roots:

Term:          x̌wíqw
Phonetic:      [xʷiːqʷ]
Part of Speech: Noun
Meaning:       Crested Grebe / Water Bird
Cultural Note: Recorded in Cowichan Bay marine ecosystem stories.
Audio Reference: 'audio/hulq_xwiqw.ogg'
Related Terms:
  - x̌wíqw'əm (To dive deep underwater)
  - shx̌wíqw'els (Diving duck species)

----------------------------------------------------------------------
Drill this term in today's spaced-repetition queue? (y/n): y
[+] Added 'x̌wíqw' to Level 1 review queue (Next review: Tomorrow).
======================================================================
```

## Computational Requirements

Your program must implement:

1. **Dictionary & Key-Value Modeling:**
   - Model the lexicon using nested dictionaries where words are indexed by both primary language identifiers and English translations.
   - Store metadata for each entry: root term, phonetic pronunciation, English gloss, grammatical category, dialect community, and cultural context notes.
2. **Diacritic & Character Normalization:**
   - Write a dedicated string normalization function that handles Unicode characters gracefully.
   - Allow users to search using standard keyboard approximations (e.g. searching `xwiqw` or `x̌wíqw` should resolve to the same lexicon record using Unicode normalization `unicodedata.normalize`).
3. **Inverted Indexing & Category Filtering:**
   - Construct inverted index dictionaries mapping English keywords and grammatical categories back to list of language terms for $O(1)$ fast lookup.
4. **Spaced-Repetition Review Algorithm (Leitner Box Model):**
   - Implement a lightweight flashcard study schedule: words start in Box 1 (daily). Correct answers promote words to Box 2 (every 3 days), then Box 3 (weekly). Incorrect answers reset words back to Box 1.
   - Save the student's study progress to a local JSON file so reviews persist across sessions.
5. **Accessible & Respectful User Experience:**
   - Provide clear, high-contrast console typography.
   - Include audio cue placeholders and Elder attribution notes.

## Cultural Ethics & Indigenous Data Sovereignty (OCAP®)

In computer science, open data is often celebrated without nuance. However, when working with Indigenous cultural heritage, traditional ecological knowledge, and endangered languages, the **First Nations Principles of OCAP®** must govern software design:

- **Ownership:** The community owns its cultural data collectively. A tech company or programmer does not own language data simply because they wrote the database.
- **Control:** First Nations communities have the right to control all aspects of research and software development that affects them.
- **Access:** First Nations have the right to manage and decide who can access their collective information, including keeping sacred stories or ceremonial vocabulary restricted to community members.
- **Possession:** Physical control of the data. Language archives must not be locked inside proprietary commercial clouds where access can be revoked.

Discuss in your submission:
- How does your software architecture respect OCAP® principles?
- Why is it vital that the dictionary database can be exported in human-readable JSON formats that the community can maintain independently of your code?

## Success Criteria

| Quality | What strong work looks like | What it looks like when it is not there yet |
| --- | --- | --- |
| **Dictionary Data Structures** | Elegant use of nested dictionaries, sets, and inverted lookup tables; $O(1)$ search efficiency. | Linear scanning of unindexed lists; clumsy data organization. |
| **Unicode & String Handling** | Flawless normalization of combining diacritics, glottal marks, and accented vowels; search tolerates keyboard approximations. | Crashes on special characters; fails to match accented search terms. |
| **Spaced-Repetition Logic** | State transitions between study intervals function smoothly; state correctly serializes to and from JSON. | Study queue resets unexpectedly; progress does not persist. |
| **Cultural & Ethical Integrity** | Thoughtful integration of OCAP® principles, Elder attributions, and data sovereignty safeguards in documentation. | Treats cultural data as generic text strings without acknowledging community sovereignty. |

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D2.2]]

![[D3.3]]

![[D4.1]]

![[D7.2]]

![[K1.4]]

![[K1.7]]

![[K1.8]]

![[K1.13]]

![[T1.4]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 3, Day 17, during the work period on Unicode diacritic normalization and the instructor check-in on normalization helpers
  Watch for: what a student does the first time a search fails on an accented term — reads the term, or guesses at the code.
  Going well: keeps a real term with a diacritic to hand and pastes it in after every change; asks what the community's own spelling is instead of quietly inventing a simpler one.
  Stuck: edits the normalization function several times without running anything in between; starts deleting the accented characters as though they were damage.
  Record: tick the seating chart for who tested with a real accented term without being told to, and note who needed the idea of normalization explained a second time.

TALK — Unit 3, Day 18, at the milestone check on search query performance, and again Unit 3, Day 21 during the OCAP® stewardship review
  Ask, on Day 18: "Why does your inverted index find a word faster than looking through every entry in the lexicon?"
  A strong answer describes the structure rather than the speed: the index is a dictionary whose keys are the English words, so a lookup lands on the matching terms instead of walking the whole lexicon — and it says what that costs, because the index has to be built and kept in step when an entry changes. A weak answer repeats "O(1)" without being able to say what the key is.
  Then, on Day 21: "Are there entries a lexicon app should refuse to show at all — and who decides which ones?"
  A strong answer separates the mechanism from the authority: a restricted field or a community-only export is a morning's work, but the decision about what goes in it is not the developer's to make. Listen for a named decision-maker — the community, an Elder, the language authority — and for where that decision would live in their own program. A weak answer argues that all data should be open, or that none of it should be shared, with nobody deciding.
  The first is K1.4 and K1.8 heard out loud: whether the student can explain the structures inside their own code, and the loop the index replaced, rather than only having typed them.
  The second is T1.4: applying Indigenous data sovereignty — Control and Access in particular — to decisions inside the software.
  Record: two sentences per student in the unit conferencing notes.

The product evidence is the Python lexicon engine code, persistent JSON study state, and OCAP data stewardship statement in the Learning Journey Log.
%%
