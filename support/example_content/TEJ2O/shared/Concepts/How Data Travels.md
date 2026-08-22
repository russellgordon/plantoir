---
title: How Data Travels
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
When the tester lit green in [[Crimp and Test a Cable]], it proved
eight wires ran end to end. It said nothing about how a message
actually uses them. Here is the trip.

## Chopped into packets

Nothing travels whole. A file, a page, a video call — each is chopped
into packets of a few hundred to a few thousand bytes, and every
packet carries a label: where it is from, where it is going, and its
place in line. Packets may arrive out of order or not at all; the
receiving machine reorders, notices gaps, and asks for the missing
ones again. This is why one flaky cable makes a network slow before
it makes it dead — the retries paper over the loss.

## Two kinds of address

Every network card has a hardware address (the MAC address), burned
in at the factory and written in the hexadecimal you met in
[[Binary and Number Systems]] — something like `A4:5E:60:D2:19:7B`.
It is like a person's name: permanent, but no help finding them.
The network address (the IP address) is assigned when a machine
joins a network — like a street address, it tells routers where the
machine currently is. Delivery needs both: IP to route the packet
across networks, MAC for the final handoff on the local one.
[[Network Addressing Practice]] makes both formats familiar, and
utilities like `ping` let you check an address answers at all.

## The trip

A message from your bench machine to a faraway server takes the same
route every time in shape, if not in path:

```mermaid
flowchart LR
  A[Your machine] --> B[Switch]
  B --> C[Router]
  C --> D[More routers ...]
  D --> E[Server]
```

The switch delivers within the room, as [[Networking Basics]]
describes; each router passes the packet one network closer; the
server's replies make the same journey back, packet by packet, and
your machine quietly reassembles the answer.

## Transmission media and network hardware in the data path

Packets traverse different physical transmission media and active
hardware devices depending on where they travel:

- **Unshielded twisted-pair (UTP) copper:** Carries electrical
  signals over four colour-coded pairs. Standard for local runs inside
  a room or building up to 100 metres.
- **Fibre-optic cable:** Pulses light through flexible glass strands.
  Immune to electrical interference, with vast bandwidth over tens of
  kilometres — the backbone connecting buildings and cities.
- **Wireless (Wi-Fi and cellular radio):** Modulates radio waves
  through air. Provides mobile access but shares radio frequencies
  and suffers signal loss through walls.

Every workstation connects through a **network interface card (NIC)**,
which turns digital data into physical signals. Inside a local area
network (LAN), **switches** forward data frames directly to the
destination port based on MAC addresses. To reach an external wide area
network (WAN) or web server, **routers** inspect the destination IP
address and choose the next network path.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.3]]

![[A2.4]]
%%curriculum-end%%
