---
title: Evaluating Software Accessibility and Usability
publish: true
created: __CREATED__
tags:
  - exploration
  - evaluation
  - accessibility
  - ui
---

Software is written for people. When we write command-line or terminal applications, we often forget that not every user will interact with the program in the same way. Some users rely on screen readers, some are colour blind, and others might not speak English natively.

In this exploration, you will evaluate a terminal-based text adventure or utility script for accessibility and usability.

### The Evaluation Rubric

Run a text-based Python program (either one you wrote, or a sample provided by your teacher) and evaluate it against this table.

| Criteria | Questions to Ask | Score (1-3) |
|----------|------------------|-------------|
| **Clarity of Output** | Is the text formatted cleanly? Are there too many blank lines or massive blocks of text that would overwhelm a screen reader? | |
| **Input Forgiveness** | If the program asks for "Yes/No", what happens if the user types "y", "YES", or "yeah"? Does it crash, loop forever, or politely ask again? | |
| **Error Messages** | When invalid input is given, does the program yell "INVALID INPUT", or does it constructively explain what is expected? | |
| **Colour Reliance** | If the program uses ANSI terminal colours, is colour the *only* way information is conveyed? (e.g., Red for error). | |
| **Cognitive Load** | Are the instructions clear? Does the user have to remember a long list of commands? | |

### Reflection Prompts

After completing the evaluation, discuss or write about the following:

1. **Screen Reader Experience:** How would a text-to-speech engine read your program's ASCII art or progress bars? (Hint: `[====    ]` is read as "left bracket, equals, equals, equals, equals, space, space, space, space, right bracket"). How could you provide an accessible alternative?
2. **The "Happy Path" Bias:** Programmers usually test the "happy path" — the sequence of inputs that works perfectly. How does focusing only on the happy path exclude certain users?
3. **Inclusive Design:** In BC, software built for public service (like BC Ferries or BC Hydro) must meet WCAG accessibility standards. Why is it a democratic necessity that government digital services are usable by everyone?

### Challenge Activity

Take a piece of code that strictly requires an integer input and crashes on letters. Rewrite it using a `while` loop and `try/except` to trap the error and provide a warm, helpful, human-readable prompt that guides the user back to the right path.

%%curriculum-start%%
## Curriculum connection

![[D2.2]]

![[K1.17]]
%%curriculum-end%%
