---
title: Share Files Across the Network
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
A network that carries no traffic proves nothing. Today the cables and
addresses from [[Build a Small Network]] get a job to do: two machines
sharing files on purpose, with permissions you set and can explain.

> [!danger] Safety and shop rules
> Nothing electrical is opened today, but the rules from
> [[Our Classroom Norms]] apply hardest here: you touch only the
> machines and shares assigned to your bench. Wandering into another
> bench's share — even to look — is the thing that ends lab
> privileges, and it is also the thing that ends jobs.

## What you need

- [ ] Two machines on your bench network, addressed and pinging
- [ ] The lab account credentials for both
- [ ] A folder of sample files, and one file over 200 MB
- [ ] Your service binder, open

## The work

1. **Confirm the network first.** Ping each way. A share that will not
   mount is a network fault nine times out of ten, and the ten seconds
   spent here saves twenty minutes later.
2. **Install or enable the sharing service** on the machine that will
   hold the files — the built-in file-sharing role on that operating
   system, enabled deliberately rather than left on.
3. **Create the share**: one folder on the machine that will hold the
   files, named for what it is rather than for who made it, with the
   subfolders you would want a year from now. Moving work onto a
   network drive is the cheapest backup a small office ever gets —
   [[Maintenance Utilities]] has the naming and filing habits.
4. **Set permissions twice**, because most systems have two layers —
   the share permission and the file-system permission. Give your
   partner's account read access first and test it, then read-write and
   test again. Note what changed between the two tests.
5. **Mount it from the second machine** by address and by name, and
   record which worked. If the name failed and the address worked, you
   have just diagnosed a name-resolution problem — write that down, it
   is a real service call.
6. **Move the large file both ways** and time it. Convert to megabits
   per second and compare with the link speed your cable and switch
   should give you.
7. **Break it on purpose.** Unplug the cable mid-transfer, then remove
   the permission and try again. Record the exact error each fault
   produces — an error message you have seen before is worth an hour of
   guessing later.

## Record in your binder

| What | Your entry |
| --- | --- |
| Share name and path | |
| Permissions set, both layers | |
| Access by address / by name | worked / failed |
| Transfer rate, both directions | |
| Error text: cable pulled | |
| Error text: permission denied | |

## Think about it

1. Which is the more useful permission for a shared class folder: every
   account read-write, or read-only with one account able to write?
   Defend it with a scenario, not a preference.
2. Your transfer rate is well below the link speed. Name three
   plausible causes and the order you would check them in.
3. Peer-to-peer sharing sends files directly between machines with no
   server in the middle. Name one situation where that is the right
   choice, and one where it is the reason a network administrator gets
   a phone call.

> [!tip] What to keep for [[The Network Job]]
> The permission table and the two error messages. A binder that tells
> the next technician what "access denied" looked like on this network
> is the difference between a handover and a hand-wave.

%%curriculum-start%%
## Curriculum connection

![[B3.3]]

![[B1.3]]

![[B3.2]]

![[A2.4]]
%%curriculum-end%%
