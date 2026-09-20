---
title: Computing's Footprint
publish: true
created: __CREATED__
tags:
  - concepts
---
Your code runs somewhere. At Grade 11 that was a laptop; by the time
anything you write is used by strangers, it is a rack in a building that
draws power continuously and is cooled continuously. The environmental
question stops being about the device on your desk and starts being
about the system you designed.

## Where the cost actually sits

- **Manufacturing.** Most of a device's lifetime carbon is spent before
  it is switched on — mining, refining, assembly, shipping. Which is why
  a repaired five-year-old laptop beats a new efficient one, and why
  "upgrade the fleet to save power" is usually arithmetic that does not
  work.
- **Running the servers.** A request that takes ten times as long costs
  roughly ten times the energy. Efficiency is not only a user-experience
  concern — it is the environmental one, which makes
  [[Efficiency and Big-O]] a sustainability topic as much as a
  performance one.
- **Cooling.** A large fraction of a data centre's power removes heat
  rather than doing computation. Where the building is, and what its
  power comes from, matter as much as what runs inside it.
- **End of life.** Electronics carry lead, mercury, and cadmium. In
  landfill those reach soil and water; in informal recycling abroad,
  people.
- **Human health, at the desk.** Repetitive strain, eye strain, posture,
  sleep disrupted by late screens, and the effects of being permanently
  reachable. These are occupational health issues in this profession,
  not lifestyle advice.

## What a developer can actually change

| Decision | Why it matters |
| --- | --- |
| A better algorithm | The largest lever you personally control; an $O(n \log n)$ solution where an $O(n^2)$ one was doing costs orders of magnitude less energy at scale |
| Cache what does not change | Work not done costs nothing |
| Batch and schedule | Overnight jobs can run when the grid is cleanest |
| Send less | Smaller payloads, fewer round trips, images sized for the screen |
| Do not poll | Waking a device every second to ask "anything yet?" is a battery bug and a server bug |
| Support old devices | Software that forces hardware replacement has an emissions cost you caused |

## Programs and agencies that exist for this

In Ontario, end-of-life equipment has a settled route, and there are
organisations whose whole purpose is to keep working machines working:

- **Recycle My Electronics / EPRA Ontario** — the approved provincial
  electronics recycling program, free to residents at approved depots,
  overseen by the **Resource Productivity and Recovery Authority**.
- **Renewed Computer Technology**, which delivers **Computers for
  Schools Plus** in Ontario — refurbishing donated equipment for
  schools, libraries, non-profits, and low-income households, with paid
  youth internships doing the refurbishment.
- **Municipal hazardous- and electronic-waste depots**, which take what
  retailers will not.
- **Environment and Climate Change Canada** and the **Ontario Ministry
  of the Environment, Conservation and Parks** for the reporting,
  regulation, and data behind any claim you want to make.

Details change — programs are renamed and rules rewritten — so verify
against the current source before you cite any of it, including this
page.

> [!note]- The honest counterweight
> Computing also makes environmental work possible: climate models,
> sensor networks, grid optimisation, precision agriculture, routing
> that removes kilometres. Both things are true at once, and a report
> that gives only one side is not finished. [[The Efficiency Case]] is
> where you have to hold both.

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D1.2]]
%%curriculum-end%%
