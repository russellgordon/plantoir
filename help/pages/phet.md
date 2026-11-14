---
id: phet
checked: 2.0.0
covers:
- contracts/shared-rules.json
- contracts/app-rules.json
- scripts/phet.py
- scripts/kept_downloads.py
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
- mac-app/QuartzTeachers/Models/SectionProblemsWording.swift
keywords:
- PhET
- phet
- simulation
- simulations
- science simulation
- sim
- interactive
- physics
- chemistry
- gas properties
- projectile motion
- phet.colorado.edu
- simulation not showing
- was not built
- no internet
- offline
- new computer
- moved folder
factsChecked: 2026-11-13
authority: https://phet.colorado.edu/en/licensing
description: Put a PhET science simulation on a page by naming it in a short block. The class website carries its own copy, which Plantoir downloads once.
---
A page can hold a PhET simulation that students open and use. PhET Interactive Simulations, at the University of Colorado Boulder, makes simulations for science and mathematics. You name one in a short block of text, and the class website carries its own copy of it.

## Write the block

1. On phet.colorado.edu, open the simulation you want. Look at its address. The simulation's name is the last part of the address, such as `gas-properties`. It is not the title shown on PhET's page.
2. In Obsidian, start a block with three backticks and the word `phet`.
3. Type a `sim:` line with the name, and an `alt:` line that says what the simulation lets a student do.
4. End the block with a line of three backticks.

```text wrap
```phet
sim: gas-properties
alt: Pump gas into a box and watch the pressure, temperature and volume change.
```

> [!note]
> The example stops before the block's last line. Remember the three backticks that close the block.

{{picture:phet-1}}
alt: A phet block as typed in Obsidian, with its sim line and its alt line marked.

5. Preview the section while this {{machine}} is connected to the internet. The part below says why.

Obsidian shows the block as plain text. The simulation appears only on the class website.

## The settings

- `sim:` is needed. Give the name, or paste the simulation's whole address from phet.colorado.edu.
- `alt:` is the description on the simulation's card, and what a screen reader says. Always write one.
- `locale:` sets the language, such as `fr` or `fr-CA`. Leave it out and the simulation uses the language of the course, from {{control:languageAndRegion}} in the course's settings. A simulation with no version in that language shows in English.
- `screens:` shows only some of the simulation's screens, by number as PhET numbers them, such as `1, 2`. Leave it out for every screen.

Nothing else can be set. The simulation takes its own shape at the width of the page.

## The first preview downloads the simulation

The first time a preview or a deploy meets a simulation, Plantoir downloads it from PhET onto this {{machine}} and keeps it. That takes an internet connection. Every later preview and deploy uses the copy that was kept, and needs no connection for it.

- **Preview once, connected, after you add a simulation.** Do it before you schedule a deploy. A scheduled deploy that meets a new simulation with no connection stops at its hour, with nobody there to see it.
- **One copy serves the whole working folder.** Two sections, or two courses, that use the same simulation share it.
- **The kept copies stay with this working folder on this {{machine}}.** After you move or rename the working folder, or copy it to a new computer, nothing is kept yet. Preview each section once with the internet.
- **A copy unused for about 90 days is cleared away.** A course left alone over the summer needs the internet for its first preview in September.

## When there is no internet

A preview or a deploy that needs a simulation it has not kept yet, and cannot reach PhET, stops. No website is made, and the last one you deployed is left as it was. Plantoir says the section was not built, and names the page and the simulation that were not downloaded.

Connect to the internet, then preview or deploy again.

## What students see

{{picture:phet-2}}
alt: A simulation's card on the class website, with its picture, title, description, the button that opens it and PhET's credit line.

- **A card**, with the simulation's picture, its title, your description, and a button that gives the simulation's size.
- **The simulation opens in the page** when the student presses the button. The first time, that can take up to a minute.
- **It comes from the class website's own copy.** A student's browser asks nothing of PhET or of anyone else, and nothing a student does in the simulation is sent anywhere.
- **PhET's credit line is under every card.** Plantoir writes it. Do not add one, and do not take it out. It is in English, in a French course too.
- **A simulation's sounds play** once a student has touched it. Nothing on the page turns them off.
- **On paper**, the card prints as the simulation's picture, with a line saying it can be used on the class website.

PhET's simulations are free for teaching. Their licence allows any use by students and teachers that is not commercial, and asks that the credit line stay with the simulation.

## In a question students check themselves

A simulation works in the question, above the choices, and in the explanation. It is refused inside a choice, where a tap on the simulation would pick that choice. See [Questions students check themselves](page:quizzes).

## A page that already shows PhET's own frame

A page with the frame that phet.colorado.edu offers for other websites keeps working. That frame reports to PhET and to Google from every student's browser. A `phet` block shows the class website's own copy instead, and reports to nobody.

## If it does not work

- **The page shows the block's lines as you typed them.** The block could not be shown. The section's {{control:problemsTab}} tab has a row of the kind {{control:problemsTabKindScienceSimulation}}. The row names the page, the block and the line, and says what is wrong. Most often the name is misspelt, and the row gives the closest names PhET has. See [The Problems tab](page:problems).
- **The preview stopped and Plantoir says the section was not built.** A simulation has not been downloaded yet. Connect to the internet and preview again.
- **It stopped the same way while connected.** A school network can send its sign-in page in place of the download. Sign in to the network, or try from another network.
- **Plantoir says a simulation could not be made ready on this computer.** Preview again. If it stops the same way, choose {{menu:helpReportAProblem}}. See [Send a problem report](page:report).
- **The simulation shows in English in a French course.** That simulation has no French version yet.
- **A line of the block seems to be ignored.** Only the four settings above are read. Any other line is left out.
