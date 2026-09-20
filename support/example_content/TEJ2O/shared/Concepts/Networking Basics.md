---
title: Networking Basics
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The moment in [[Build a Small Network]] when a file appeared on the
other machine — that was a network doing the only thing networks do:
moving data between computers that have agreed on how to talk.

## What makes a network

Two or more machines, a shared language, and a medium to carry it —
copper cable like the one from [[Crimp and Test a Cable]], strands of
glass carrying light (fibre optic), or radio (Wi-Fi). Each machine
joins through a network interface card, the part with the RJ45 jack
or the antenna. That is the whole recipe; everything else is scale.

## Switches and routers, in plain terms

A switch connects machines within one network. It learns which
machine hangs off which port and delivers each message only where it
needs to go — a mailroom for one building. A router connects networks
to each other and decides which way traffic should leave — the post
office between buildings. The box at home labelled "router" is
usually both at once, plus a Wi-Fi radio, which is why the names blur
in conversation. At the bench they are separate jobs.

> [!tip] The rack in this room is not a toy
> The switch you plugged into during the lab is the same class of
> device running offices and schools everywhere. Nothing about the
> real thing was hidden from you — it was the real thing.

## Sizes and shapes

A local area network (LAN) lives in one place — this room, one home,
one office. A wide area network (WAN) ties LANs together across
distance; the Internet is the biggest one. Networks also differ in
who is in charge: in the peer-to-peer network you built, every
machine was an equal; the school network is client–server, with
central machines providing accounts, files, and printing to everyone
else. [[How Data Travels]] follows one message through all of this,
and [[The Network Job]] is where you plan a small network for a
client who just wants it to work.

## Comparing network architectures: LAN, WAN, P2P, and client-server

Choosing an architecture means matching technology to the job:

| Architecture | Geographic scope | Typical media | Administration |
| --- | --- | --- | --- |
| LAN | Single room, building, or site | Twisted-pair copper, Wi-Fi | Local administrator |
| WAN | Cities, regions, global | Fibre-optic trunks, satellite, leased lines | Telecommunications carriers |
| Peer-to-peer (P2P) | Small workgroup (2–10 nodes) | Direct cable, small switch | Distributed — each user manages shares |
| Client–server | Enterprise, school, cloud | High-speed switches, routers | Centralised — server controls access |

In a peer-to-peer network, workstations share files and printers
directly without a dedicated central server. This keeps equipment
costs low and setup simple for small studios or home offices. When
an organisation grows, client–server architecture becomes necessary:
a central server authenticates logins, enforces security policies,
and manages backups from one place.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.3]]

![[B3.1]]

![[B3.2]]
%%curriculum-end%%
