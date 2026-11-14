---
id: geogebra
checked: 2.0.0
covers:
- contracts/shared-rules.json
- scripts/geogebra.py
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
keywords:
- GeoGebra
- geogebra
- applet
- sketch
- ggb
- interactive geometry
- drag points
- material_id
- geogebra.org
- sketch not showing
description: Put a GeoGebra sketch on a page from a .ggb file, from a sketch on geogebra.org, or from commands you type.
---
A page can hold a GeoGebra sketch that students open and move. You type a short block of text on the page, and the block says where the sketch comes from. This page gives the three ways to write it.

## Write the block

1. In Obsidian, start a block with three backticks and the word `geogebra`.
2. Type the settings first, one to a line, each as a name, a colon and a value.
3. Type any GeoGebra commands after the settings, one to a line, as you would type them in GeoGebra's Input Bar.
4. End the block with a line of three backticks.

> [!note]
> The examples on this page stop before the block's last line. Remember the three backticks that close the block.

A block names a file, or names a sketch on geogebra.org, or holds commands alone. It never names both a file and a sketch on geogebra.org.

{{picture:geogebra-1}}
alt: A geogebra block as typed in Obsidian, with its file line and its alt line marked.

## From a file

Save the sketch from GeoGebra as a `.ggb` file. Put the file beside the page, or in the Media folder. Then name it on a `file:` line:

```text wrap
```geogebra
file: Similar Triangles.ggb
alt: Two similar triangles. Dragging a corner of one changes both.
```

Plantoir looks for the file beside the page first, then at the top of the course, then in Media.

## From a sketch on geogebra.org

Give the sketch's id, or its address on geogebra.org, on a `material_id:` line:

```text wrap
```geogebra
material_id: https://www.geogebra.org/m/ID
alt: A circle with a tangent line that students can move.
```

Do not paste the frame that geogebra.org offers for other websites. Use `material_id:` instead.

## From commands alone

With no file and no sketch named, the block needs at least one command:

```text wrap
```geogebra
alt: A parabola with a point marked on it.
f(x) = x^2
A = (1, 1)
```

## The settings

| Setting | What it is for |
|---|---|
| `file` | The name of a `.ggb` file |
| `material_id` | A sketch's id or address on geogebra.org |
| `app` | Which GeoGebra to use: `classic`, `graphing`, `geometry` or `3d` |
| `alt` | A description for students who use a screen reader |
| `caption` | A caption for the sketch |
| `height`, `width` | The sketch's size |

The settings `toolbar`, `algebra` and `version` are also read.

## What students see

On the class website, the sketch starts as a button named **Open the sketch**, followed by the sketch's size. A student presses it, and the sketch opens in place on the page. While it opens, the page says:

{{say:shared-rules#geogebraFences.words.site.loading}}

The first time, it adds:

{{say:shared-rules#geogebraFences.words.site.loadingFirstTime}}

Every sketch carries GeoGebra's reset icon. It puts the sketch back as it was when it opened.

The sketch comes from your class website itself. Students' browsers fetch nothing from geogebra.org.

{{picture:geogebra-2}}
alt: A GeoGebra sketch opened on the class website, with the button that opens it and the reset icon marked.

## Check your work

1. Preview the section and open the page. If a preview is already running, choose {{menu:rebuildPreview}}.
2. Press the button and open the sketch once, to see that it is the sketch you meant.

## If it does not work

- **The page shows your block as a plain block of text.** The block could not be shown as a sketch. The section's {{control:problemsTab}} tab names the page and says why. See [The Problems tab](page:problems).
- **The page says that a numbered line could not run.** GeoGebra refused one of your commands. Correct that line of the block.
- **The page says this:**
  {{say:shared-rules#geogebraFences.words.site.couldNotLoad}}
