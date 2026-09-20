---
title: Networks and Protocols
publish: true
created: __CREATED__
tags:
  - concepts
---
Two machines in [[Build and Test a Network]] were cabled together, both
switched on, both with link lights, and neither could see the other. The
cable was fine. The addressing was not — and the difference between those
two diagnoses, made in the right order, is what this page is for.

## Addresses: two of them, doing different jobs

Every network interface has a **MAC address** burned into it: 48 bits,
written as twelve hexadecimal digits, unique to that piece of hardware
and unchanged wherever you take it. It is how machines on the same local
segment identify each other, and it does not travel — a router does not
forward MAC addresses beyond the local network.

Every interface also has an **IP address**, which is assigned rather than
built in, and which encodes *where* the machine is rather than *what* it
is. That is the address routing works on. The hex-versus-binary reading
skill you built in
[[Binary and Hexadecimal#Where you actually meet these]] is exactly what
these two formats are asking of you.

An IPv4 address on its own is not enough. It comes with a **subnet mask**
that splits the address into a network part and a host part.

| | Dotted decimal | Binary |
| --- | --- | --- |
| Address | 192.168.1.10 | 11000000.10101000.00000001.00001010 |
| Mask | 255.255.255.0 | 11111111.11111111.11111111.00000000 |
| Network | 192.168.1.0 | the part the mask covers |
| Host | .10 | the part the mask leaves free |

Where the mask has ones, the bits belong to the network; where it has
zeros, they identify a host on it. So this machine lives on network
192.168.1.0, the all-zeros host is the network's own name, the all-ones
host 192.168.1.255 is the broadcast address, and the 254 addresses from
.1 to .254 are the ones you can actually assign. A mask of 255.255.255.0
is written `/24` in shorthand, because 24 of its bits are ones.

That gives you the single most useful test in networking: **two machines
can talk directly only if they have the same network part.** Apply the
mask to both addresses and compare. 192.168.1.10 and 192.168.1.50 with a
/24 mask share the network 192.168.1.0, so they talk. 192.168.1.10 and
192.168.2.15 do not, and every packet between them has to go through the
**default gateway** — the router's address on your own network, which is
where a machine sends anything it cannot deliver itself. A machine with
no gateway configured can reach its neighbours and nothing else, which is
a symptom worth recognising on sight.

## What the network carries, and how fast

**Bandwidth** is the capacity the link is rated at. **Throughput** is
what you actually get, after protocol overhead, collisions, retries, and
whatever else is sharing the wire. They are never equal and the gap is
information: a link rated for a gigabit that delivers a tenth of that is
telling you something is wrong.

Do the arithmetic in bits, always, since links are rated in bits per
second and files are measured in bytes. A 50 MB file across a link
managing 40 Mbit/s of throughput takes

$$t = \frac{50 \times 8\ \text{Mbit}}{40\ \text{Mbit/s}} = 10\ \text{s}$$

and if it takes forty, you have measured a real 10 Mbit/s and should go
find out why.

**Duplex** describes direction. Half duplex means the medium carries
traffic one way at a time — like a single-lane bridge, with a collision
if both ends start at once. Full duplex means simultaneous traffic in
both directions. A mismatch, where one end is set full and the other
half, is a classic fault: the link works, and performance is dreadful in
one direction only.

Servers offer **services**, each waiting on its own well-known port so
that one machine can run many at once: HTTP for web pages, FTP for file
transfer, SMTP for sending mail, plus the file sharing, printing, and
login services that make a small office network worth building. DNS turns
names into addresses and DHCP hands out addresses automatically — two
services you will only notice when they stop.

## Diagnosing in the right order

Work outward from the machine in front of you, and stop at the first step
that fails, because everything past it will fail too.

1. **Is the interface configured?** `ipconfig` (or `ifconfig`/`ip addr`)
   shows the address, mask, and gateway. An address starting 169.254
   means the machine asked for a DHCP lease and never got one — the
   problem is upstream, not here.
2. **Can it reach itself?** Ping the loopback address 127.0.0.1. Failure
   here means the network stack, not the network.
3. **Can it reach its own gateway?** If not, the fault is local: cable,
   port, mask, or the gateway address itself.
4. **Can it reach something beyond the gateway, by address?** Success
   proves routing works.
5. **Can it reach something beyond the gateway, by name?** If step 4
   worked and this does not, the fault is name resolution — DNS — and
   nothing else.
6. **Where does it stop?** `tracert` shows each hop in turn, and the hop
   where the trail goes cold is where to look. `arp` shows which MAC
   addresses your machine has matched to local IP addresses, which is how
   you catch two devices claiming the same address.

> [!tip] The order is the skill
> Anybody can run these six commands. The professional habit is running
> them in sequence and *stopping* at the first failure instead of
> collecting six results and guessing. Halving the problem — is it this
> side of the gateway or that side? — is the same technique
> [[Debugging Hardware and Software Together]] uses on a circuit, and
> [[Getting Unstuck]] uses on everything else.

Build the addressing fluency in [[Networking Practice]], then wire and
prove a real one in [[Build and Test a Network]].

%%curriculum-start%%
## Curriculum connection

![[A4.1]]

![[A4.2]]

![[A4.3]]

![[B4.4]]
%%curriculum-end%%
