---
title: Learning Journey Log
publish: true
created: __CREATED__
tags:
  - portfolio
  - reflection
---

Programming is a process of continuous learning, failing, and adapting. The Learning Journey Log is a place to document not just *what* code you wrote, but *how* you figured it out.

Professional developers keep engineering journals to track their thought processes, record how they solved obscure bugs, and save useful snippets for the future. 

### How to use this Log

Once a week, or at the end of a major project, create a new entry. Don't just list what you did—analyze your problem-solving process.

### Prompts for your entries

Choose one or two of these to write about in each entry:

- **The Bug Hunt:** Describe a bug that took you more than 15 minutes to solve. What was the error? What did you *think* was happening? How did you trace it? What was the actual fix?
- **The "Aha!" Moment:** What is a concept (like loops, aliasing, or dictionaries) that confused you at first but suddenly clicked? How would you explain it to someone else?
- **Code Review:** Paste a small snippet of your code that you are proud of. Explain line-by-line how it works and why you chose to write it that way.
- **The BC Context:** How could the program you just wrote be adapted to solve a problem in your local community?
- **Frustration Log:** What is the most annoying part of the language or IDE you are currently fighting with? How are you working around it?

### Your unit self-assessment

At the end of every unit, one entry is not optional and is not a bug story: your
self-assessment against [[The Core Competencies]]. It is written in your own words, it is not
scored against a rubric, and it is part of what gets reported about your learning — so it is
worth being specific. Three things, every time:

1. **The competency and the evidence.** Name one competency and the moment in this unit that
   proves it — an hour, a bug, a conversation. "I collaborated well" is not evidence; "on the
   Thursday of the rolling-average work I stopped typing and asked my partner to say the
   algorithm back to me, and we found the off-by-one in a minute" is.
2. **What you can do now** that you could not do when the unit started.
3. **The next goal**, small enough that the next unit can show whether you met it.

### Example Entry

**Date: Unit 2, Day 8**
*Today I spent an hour staring at a `KeyError`. I was building the weather station parser and trying to look up `"vancouver"` in my dictionary. It kept crashing. I used print statements to check my variables and realized my input was `Vancouver` with a capital V. I learned that dictionaries are strictly case-sensitive. I fixed it by adding `.lower()` to my input string. Note to self: ALWAYS sanitize text inputs before using them as keys!*

%%curriculum-start%%
## Curriculum connection

![[D4.5]]

![[K1.2]]

![[D7.4]]

![[S1.2]]
%%curriculum-end%%
