---
title: Network Addressing Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[How Data Travels]] and the network you
assembled in [[Build a Small Network]] — over cables you made
yourself in [[Crimp and Test a Cable]].

## Questions

1. Look at the address `192.168.1.20`. How many numbers make it up,
   and what is the smallest and largest each one can be?
2. In our lab setup, the first three numbers name the network. Which
   of these pairs are on the same network: (a) `192.168.1.20` and
   `192.168.1.57`; (b) `192.168.1.20` and `192.168.2.20`?
3. In the lab, four devices hold `192.168.1.1`, `192.168.1.30`,
   `192.168.1.57`, and `192.168.1.58`. One is the router, one is a
   printer, two are laptops. Which address is almost certainly the
   router, and why?
4. Every network card actually answers to *two* addresses — one
   burned in at the factory, one assigned by the network. Name each
   kind, and say which is physical and which is logical.
5. **Find the error.** Two workstations on the lab network have both
   been configured with `192.168.1.42`. What goes wrong, and what is
   the fix?
6. You have just cabled two machines together and want proof they
   can talk. Which utility do you reach for, and what does a good
   result look like?
7. **Compare network scopes.** State two key differences between a
   Local Area Network (LAN) and a Wide Area Network (WAN) in terms of
   geographic coverage, transmission media, and ownership.
8. **Network roles and hardware.** Contrast a peer-to-peer (P2P) network
   with a client–server network, and describe the specific job of a
   network interface card (NIC), a switch, and a router.

## Answers

> [!success]- Answer 1
> Four numbers, each from 0 to 255 — and 255 should ring a bell:
> each number is one byte, and 255 is the most a byte can say. Even
> addresses are binary underneath.

> [!success]- Answer 2
> Pair (a) shares a network — both begin `192.168.1`; the final
> numbers just tell the machines apart. Pair (b) does not: the third
> number differs, and the matching final 20 means nothing. Street
> name first, house number last.

> [!success]- Answer 3
> `192.168.1.1`. By convention the router — the network's door to
> everywhere else — takes the first usable address. A habit, not a
> law, but a near universal one.

> [!success]- Answer 4
> The MAC address is physical — burned into the card, unique for
> life. The IP address is logical — assigned by the network and
> changeable. One is who the card *is*; the other is where it
> currently *lives*.

> [!success]- Answer 5
> An address collision: replies meant for one machine reach the
> other, and connections misbehave for both. The fix is to give one
> workstation a different unused address — every device on a network
> needs its own.

> [!success]- Answer 6
> `ping` — it sends a small "are you there?" and counts the replies.
> A good result is a string of responses timed in milliseconds;
> silence sends you back to check cables and addresses.

> [!success]- Answer 7
> A LAN covers a limited local space (a room, home, or office building)
> using privately owned copper cables or Wi-Fi, with high bandwidth
> and low latency. A WAN spans wide geographical distances (across
> cities, countries, or globally like the Internet), relying on
> leased telecommunications infrastructure, fibre-optic trunks, and
> public routing systems.

> [!success]- Answer 8
> In a P2P network, every connected workstation acts as both client and
> server with equal authority, sharing files directly without central
> management. In a client–server network, dedicated servers provide
> centralised services (authentication, file storage, printing) to
> client workstations. Hardware roles:
> - **NIC:** Connects a device to the network medium and handles
>   physical/logical signalling.
> - **Switch:** Connects devices within a LAN and directs data frames
>   to specific ports using MAC addresses.
> - **Router:** Forwards data packets between different networks using
>   IP addresses to determine the optimal route.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.4]]

![[B3.1]]
%%curriculum-end%%
