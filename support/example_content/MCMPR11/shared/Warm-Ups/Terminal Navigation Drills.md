---
title: Terminal Navigation Drills
publish: true
created: __CREATED__
tags:
  - warmup
  - terminal
  - command-line
---

You have just been handed someone else's project folder and need to find one specific file — without opening a single folder by clicking. This is a normal Tuesday for a programmer: terminals are faster than a mouse once you know a handful of commands.

Here is the folder structure you have to navigate. It is sitting on your Desktop, in a folder called `programming11`.

```
programming11/
├── README.md
├── unit2/
│   ├── warmups/
│   │   └── trace_the_loop.py
│   └── projects/
│       ├── ferry_calculator/
│       │   ├── main.py
│       │   └── data/
│       │       └── fares.csv
│       └── weather_tracker/
│           ├── main.py
│           └── notes.txt
```

You open a terminal, and it starts you on your Desktop. Your mission: **reach `fares.csv` using only the terminal, without typing the whole path in one shot.** Move one folder at a time, checking where you are as you go.

Write out, in order, the exact commands you would type. (Use `ls` for macOS/Linux or `dir` for Windows to list what's in a folder — either is fine.)

> [!success]- Answer 1
> ```
> cd programming11
> ls
> cd unit2
> ls
> cd projects
> ls
> cd ferry_calculator
> ls
> cd data
> ls
> ```
>
> Each `cd <folder>` moves one level deeper — a **relative path**, because it is written relative to wherever you currently are, rather than starting from the very top of the drive. Running `ls` (or `dir`) after each move confirms what is actually inside the folder you just entered, which is exactly how you would explore an unfamiliar project for real. By the last `ls`, `fares.csv` should be sitting right there in the output.

Now, without leaving the `data` folder, answer these three follow-up questions:

1. What single command takes you back up one level, to `ferry_calculator`?
2. What single command takes you all the way back to the Desktop in one shot, using a relative path made of several steps?
3. `weather_tracker/main.py` is a Python program. Once you have navigated into the `weather_tracker` folder, what command actually **runs** it?

> [!success]- Answer 2
> 1. `cd ..` — `..` always means "the parent of where I am now," so this steps up exactly one level.
> 2. `cd ../../../../..` — five parent-steps in a row, each separated by a `/`: out of `data` into `ferry_calculator`, into `projects`, into `unit2`, into `programming11`, and finally out of `programming11` onto the Desktop. It takes five steps because `data` is five folders deep counting the Desktop as the top.
> 3. `python main.py` (on some systems, `python3 main.py`) — this tells the terminal "run the Python interpreter on this file," which is different from just navigating to the file or opening it in an editor.

An **absolute path** would spell out the entire route from the very top every time — something like `/Users/yourname/Desktop/programming11/unit2/projects/ferry_calculator/data`, or `C:\Users\yourname\Desktop\programming11\...` on Windows. Relative paths are shorter to type once you are already nearby, but absolute paths work no matter where the terminal currently is — which is exactly why you will see both used in real projects, and why it is worth being comfortable with each.

%%curriculum-start%%
## Curriculum connection

![[K1.12]]
%%curriculum-end%%
