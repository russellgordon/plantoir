---
id: code-blocks
checked: 2.0.0
covers:
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
- contracts/shared-rules.json
- documentation/06-quartz-customizations.md
- support/quartz/components/styles/codeLines.scss
keywords:
- code
- code block
- program
- programs
- Python
- Java
- JavaScript
- syntax highlighting
- coloured code
- colored code
- line numbers
- copy code
- text block
- wrap
- long lines
- terminal output
- error message
description: Show a program on a page, coloured by its language, for students to read and copy but not run.
---
A page can show a program exactly as you typed it, coloured by its language, with line numbers. Students read it and copy it. They do not run it. This page gives the form of the block, and of a block of plain text.

For programs that students run on the page, see [Code students can run](page:code).

> [!note]
> The examples on this page stop before the block's last line. Remember the three backticks that close the block.

## Show a program

1. In Obsidian, start a block with three backticks and the name of the language, such as `python`.
2. Type the program.
3. End the block with a line of three backticks.

```text wrap
```python
import random

roll = random.randint(1, 6)
print(roll)
```

The language's name is what colours the program. Some of the names are `python`, `java`, `javascript`, `html`, `css`, `swift`, `cpp`, `sql` and `bash`. A block with no language is shown plain.

Two more forms:

- **A highlighted line.** Type `{2}` after the language's name to highlight line 2.
- **Code inside a sentence.** Put it between single backticks, as in `print()`.

## What students see

{{picture:code-blocks-1}}
alt: A coloured program on a class website, with line numbers down the left and the copy button that shows under the pointer.

- **The program as you typed it**, coloured, with line numbers down the left. The colours follow light or dark mode.
- **Every character as typed.** Two characters are never joined into one symbol, so `!=`, `->` and `<=` look as they do on a keyboard.
- **A copy button**, when the pointer is over the block. It copies the block as you wrote it.
- **A long line scrolls sideways.** A line of a program never wraps, because programs are read by column. The word `wrap` after a language's name does nothing.

On paper, a program keeps its line numbers and has a thin box around it. The numbers carry on across a page break. Long lines wrap on paper.

## Plain text that is not a program

For text that is not a program, name the block `text` and add one more word.

- **`text wrap`** wraps long lines at the width of the window. Each line keeps its number on its first row. Use it for an error message, sample output, a terminal session, and anything students copy, such as a prompt or a commit message. Use it for words students copy even when a screenshot on the page shows the same words.
- **`text nowrap`** keeps each line on one row and scrolls sideways. Use it when the meaning depends on characters lining up. Examples are a drawing made of characters, columns lined up with spaces, and an error report with marks under the faulty place.

```text wrap
```text wrap
TypeError: can only concatenate str (not "int") to str
```

Always type one of the two words, so that a block that does not wrap is one you meant.

- A block named `text` alone scrolls sideways, like `text nowrap`.
- `nowrap` is one word. `no wrap` is read as `wrap`.
- `TEXT`, `txt` and `plaintext` are not `text`.

## Check your work

Preview the section and look at the page. If a preview is already running, choose {{menu:rebuildPreview}}.

Never type two per cent signs together, `%%`, in a block. Text between two such pairs is taken off the page.

## See real ones

Several ready-made courses show programs this way, among them ICS4U, ICD2O and MTH1W. ICS4U's page named What This Site Can Do has a part named Code, coloured and exact.
