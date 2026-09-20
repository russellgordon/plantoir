---
title: Network Types and Topologies
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Before a network is cables and addresses, it is a decision about who
holds the resources and how the connections are laid out. Both choices
are made on paper, and both are drawn — a network you cannot draw is a
network you cannot service.

## Who holds the resources

| Model | How it works | Where it fits | What it costs |
| --- | --- | --- | --- |
| **Peer-to-peer** | Every machine shares its own resources and manages its own accounts | Home, a small shop, a bench of five machines | Accounts multiply: ten users on five machines is fifty passwords |
| **Client–server** | One or more servers hold files, accounts, and services centrally | Schools, offices, anywhere with more than about ten users | A server, its licences, and somebody who maintains it |

The tipping point is administration, not size: the moment the same
person is resetting the same password on four machines, the peer-to-peer
model has already cost more than a server would.

## How the connections are laid out

```mermaid
graph TD
    subgraph Star
        SW["Switch"] --- A1["PC"]
        SW --- A2["PC"]
        SW --- A3["PC"]
    end
```

| Topology | Shape | Strength | Weakness |
| --- | --- | --- | --- |
| **Bus** | Every device on one shared backbone | Cheap, and historically simple | One break takes the whole segment down; you meet it in old industrial wiring |
| **Ring** | Each device connects to two neighbours, traffic circulating | Predictable timing; still used in some industrial and telecom rings | A break splits the ring unless it is a dual ring |
| **Star** | Every device to a central switch | One failed cable affects one device; easy to trace and extend | The switch is a single point of failure |
| **Mesh** | Many redundant paths | Survives failures | Expensive in cable and in configuration |

Modern wired networks are stars, usually stars of stars: switches
connected to switches, with a router at the edge. Wireless is
logically a star too, with the access point at the centre.

## Services provided in client–server architectures

In a client–server network, dedicated servers host specific network services,
each listening on standard well-known transport ports:

- **Web services (HTTP/HTTPS):** Port $80$ (HTTP, unencrypted) and port $443$
  (HTTPS, TLS-encrypted) serve documents, web applications, and intranet pages
  to client browsers.
- **File transfer and storage (FTP/SFTP, SMB):** Port $21$ (FTP) and port $22$
  (SFTP over SSH) handle file uploads and downloads, while SMB ($445$) and
  NFS ($2049$) mount remote storage volumes directly into client file managers.
- **Electronic mail (SMTP, IMAP):** SMTP (port $25$ or $587$) routes and
  transfers outgoing messages between mail servers, while IMAP (port $993$)
  allows clients to synchronise and view mailboxes.
- **Remote administration (SSH, telnet):** Port $22$ (SSH) provides secure,
  encrypted command-line access to network equipment and servers, replacing
  legacy unencrypted telnet (port $23$).
- **Network printing:** Servers manage print queues and spool documents to
  shared network printers (IPP on port $631$).
- **Centralised authentication and login:** Directory services (LDAP on port
  $389$, Active Directory) validate user credentials centrally, so a single
  login works across any authorised client workstation on the network.

## Building and cabling peer-to-peer networks

In smaller settings without a dedicated server, a **peer-to-peer network**
allows computers to share files, local storage, and printers directly:

1. **Hardware selection:** Each computer requires a compatible network
   interface card (NIC) connected to an Ethernet switch, or connected
   directly back-to-back.
2. **Cable construction:** Unshielded twisted pair (UTP Cat 5e or Cat 6)
   cables are constructed using $8\text{P}8\text{C}$ modular connectors and a
   crimping tool:
   - **Straight-through cables:** Wired with the same standard on both ends
     (typically T568B to T568B). Used to connect endpoints to switches.
   - **Crossover cables:** Wired with T568A on one end and T568B on the other,
     swapping the transmit pairs (pins 1 and 2) with the receive pairs (pins
     3 and 6). Historically required to link two computers directly without a
     switch (now largely automated by Auto-MDIX).
3. **Verification:** A cable tester checks all eight conductors for continuity,
   proper pin sequence, and opens or shorts before the cable is deployed.
4. **Configuration:** Each peer is assigned an IP address within the same
   subnet, and OS-level file and printer sharing permissions are configured to
   allow designated folders or devices to be accessed across the workgroup.

## Drawing one properly

A service drawing shows, at minimum: every device with its name and
address, every switch with its port numbers, every run with its length
and label, and where the edge of your responsibility is. Two rules
learned the hard way:

- **Label the drawing and the cable with the same string.** A drawing
  that says "Run 4" and a cable that says nothing is half a diagram.
- **Draw what is there, not what was planned.** The drawing is a
  service document; it is worth exactly as much as it is accurate.

> [!tip] The handover test
> Give your drawing to another bench and ask them to find the machine
> at a stated address, without speaking to you. If they cannot, the
> drawing is not finished — and that is the standard applied in
> [[Build and Test a Network]] and in [[The Client Build]].

%%curriculum-start%%
## Curriculum connection

![[A4.1]]

![[A4.3]]

![[B4.1]]

![[B4.2]]

![[B4.3]]
%%curriculum-end%%
