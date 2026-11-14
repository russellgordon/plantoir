---
id: code
checked: 2.0.0
covers:
- contracts/shared-rules.json
- scripts/build_site.py
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
keywords:
- Python
- Swift
- run code
- runnable code
- coding
- programming
- program
- code editor
- codeRunner
- run a program
- input
description: Let students run Python or Swift programs on a page, with a setting on the page and the word run on the block.
---
A page can hold Python or Swift programs that students run on the class website. It takes one line in the page's settings and one word on each block. This page gives both, and says what students see.

To show a program without letting students run it, see [Show code on a page](page:code-blocks).

## Write the page

1. In Obsidian, add this line to the page's settings, at the top of the page:

```text wrap
codeRunner: true
```

2. Start the block with three backticks, then `python` or `swift`, then the word `run`.
3. Type the program.
4. End the block with a line of three backticks.

> [!note]
> The examples on this page stop before the block's last line. Remember the three backticks that close the block.

```text wrap
```python run
name = input("What is your name? ")
print("Hello,", name)
```

A block without the word `run` is left as it is: students read it and cannot run it.

Three more words may follow `run`:

- `readonly`, for Python only, lets students run the program but not change it.
- `autorun` runs the program when the block comes into view on the page, before anyone presses {{control:codeRun}}.
- `stdin` says that the program reads input. Plantoir notices `input()` in Python and `readLine()` in Swift by itself, so this word is needed only for a program that reads its input another way.

## Preview it

Preview the section and open the page. If a preview is already running, choose {{menu:rebuildPreview}}.

Python needs nothing more. Swift programs are made ready when the website is made, so Swift asks more of your {{machine}}:

- The first time you preview a section whose pages hold Swift blocks, Plantoir downloads what it needs to make Swift programs. The download is about 1.3 GB and takes a few minutes. It needs an internet connection and about 6 GB of free space.
- This happens once. If you never write a Swift block, nothing is downloaded.
- Without a connection that first time, the rest of the website is made as usual and the Swift blocks are not ready. Preview again once you are online.

## What students see

{{picture:code-1}}
alt: A Python program on the class website with the Run, Stop and Reset buttons under it and its output below.

- **The program.** Students can change a Python program in place. A Swift program can be run but not changed.
- **{{control:codeRun}}, {{control:codeStop}} and {{control:codeReset}}**, a line that says what is happening, and the program's {{control:codeOutput}}. {{control:codeReset}} puts the program back as you, the teacher, wrote it, and clears the output.

Nothing is fetched until a student presses {{control:codeRun}}. Python programs run in the student's own browser.

One program runs on a page at a time. When a student starts a second, the first says:

{{say:shared-rules#codeRunnerBlocks.words.stoppedForAnother}}

## A program that reads input

A program reads input with `input()` in Python or `readLine()` in Swift. In Plantoir's preview, and on a website deployed to Netlify or Cloudflare Pages, the program stops and asks as it runs. Its question appears in the output. The student types the answer there and presses Return, and the program carries on. There is no separate box for input.

In two cases the page cannot stop to ask. A box then appears between the program and the buttons, and the student types every answer into it before pressing {{control:codeRun}}, one line for each answer. The two cases are:

- a website deployed to a folder;
- a page that also shows a video, a PDF or another web page in a frame, or a picture from another website. Put the program on a page of its own, and students can answer as it asks.

You write the page the same way in every case.

## Students' changes

A student's changes to a program are kept in that student's own browser.

If you later change the program on your page, a student who had changed it sees your new version, with this sentence:

{{say:shared-rules#codeRunnerBlocks.words.teacherChangedIt}}

## If it does not work

- **A block shows as plain text on the website.** Check that the page's settings carry `codeRunner: true`, and that the block's first line ends with `run`.
- **A Swift block is not ready.** The section's {{control:problemsTab}} tab names it. The preview still opens. See [The Problems tab](page:problems).
- **The page says the language runs only when the page is opened from its web address.** The website was opened as a file on a computer. This can happen with a website deployed to a folder. See [Deploy to a folder for your school's web space](page:folder-deploy).
