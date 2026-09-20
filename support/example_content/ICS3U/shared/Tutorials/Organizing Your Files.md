---
title: Organizing Your Files
publish: true
created: __CREATED__
tags:
  - tutorials
---
Fifteen minutes now saves an hour at the end of the course, and it saves it
on the worst possible day — the one where the project is due and the file is
called `final2 copy (1).py`.

## The shape to build today

```
ICS3U/
├── Unit 1 — Foundations/
│   ├── temperature.py
│   └── ticket_price.py
├── Unit 2 — Data/
│   ├── readings.txt
│   └── averages.py
├── Tasks/
│   └── The Toolbox/
│       ├── toolbox.py
│       ├── demo.py
│       └── usage note.md
└── Journal/
```

Three rules keep it working:

1. **The folder says where you are; the file says what it is.** Inside
   `Unit 2 — Data`, a file called `averages.py` is clear. `unit2.py` is
   not, anywhere.
2. **Data sits with the program that reads it.** A program that opens
   `readings.txt` will only find it if they are in the same place —
   which is the single most common reason a program that worked
   yesterday does not today.
3. **No spaces at the start, no dates in the name.** Let the computer
   track dates; it is better at it than you are.

## Doing it on your machine

Use the operating system's file manager — Finder on macOS, File
Explorer on Windows, Files on most Linux desktops. Make the folders
first, then move things in. Editors will happily save into whatever
folder they used last, so tell yours where your work lives once, and
check the first time you save.

If you work on a shared or network drive at school, the same shape
applies, with one addition: know which folder is yours and which is
shared. Anything you can edit, somebody else may be able to edit too —
and a shared folder is not a backup, because a file deleted there is
deleted for everyone.

> [!tip] The test that this worked
> Close everything, take a two-minute break, then find the program you
> wrote last Thursday in under ten seconds without searching. If you
> had to search, the names are wrong, not your memory.

Then read [[Backing Up Your Work]] — organised and backed up are
different problems, and only one of them survives a lost laptop.

%%curriculum-start%%
## Curriculum connection

![[C2.1]]
%%curriculum-end%%
