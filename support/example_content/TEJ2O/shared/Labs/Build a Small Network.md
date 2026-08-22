---
title: Build a Small Network
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
Two or more machines, a switch, and cables — some of them yours from
[[Crimp and Test a Cable]] — become a working network today:
addresses assigned, a ping answered, a file moved and confirmed on
arrival. [[Networking Basics]] gave you the ideas; this bench makes
them talk. Everything here feeds [[The Network Job]], where you do it
again for keeps.

> [!danger] Safety notes
> **Cables cross the floor today — route them so nobody does.**
> Along walls, under mats, taped at crossings; a tripped cable takes
> equipment off the bench. **Stack equipment stably** — the switch
> does not perch on a cable spool. **Power adapters plug into the
> bench bar, never daisy-chained**, and running machines stay
> closed, as always under [[Safety in the Lab]].

## What you need

- [ ] Two or more workstations with operating systems installed
- [ ] A network switch and its power adapter
- [ ] Tested cables — one per machine, tester-approved
- [ ] A plan sheet: machine names, addresses, who moves what file

## The work

1. **Plan addresses on paper first.** Every machine matches the
   others in its network portion and differs in its host portion —
   same street, different house numbers.
   [[Network Addressing Practice]] was the warm-up for exactly this.
2. **Cable each machine to the switch and watch for link lights.** A
   link light is the physical layer saying "connected" — no light,
   no point configuring anything above it.
3. **Assign each machine its planned address** — static, by hand.
   The point today is to feel what automatic systems normally hide.
4. **Ping yourself, then ping your neighbour.** Ping is the smallest
   possible conversation — "are you there?", "I am here, and it took
   this long." An answer means cabling and addressing both agree.
5. **Enable file sharing on one machine** and share a single folder,
   deliberately — sharing is a service you switch on, not something
   a network does by default.
6. **Move a file each way, confirm the arrivals**, and note the full
   path in your journal: machine, cable, switch, cable, machine. You
   just witnessed everything [[How Data Travels]] describes.

## What can go wrong

- **No link light.** The problem is physical: cable, port, or plug.
  Swap one thing at a time — cable first — so the fix tells you
  what the fault was.
- **Link lights on, ping fails.** Almost always addressing — two
  machines on different "streets". Recheck the network portion of
  both addresses against the plan sheet.
- **Ping works, the shared folder is invisible.** Reachable machine,
  gated service — sharing off, or a firewall answering the door.
  Layered failures like this are [[Troubleshooting Practice]]'s
  daily bread.

## Level up

Add a third machine cold — no notes, ten minutes — then map the
network on paper so precisely a stranger could rebuild it. That map
is the first artefact [[The Network Job]] will ask you for.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[B3.1]]

![[B3.2]]
%%curriculum-end%%
