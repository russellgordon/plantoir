---
title: Spec Sheet Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Reading a Spec Sheet]], and the judgement
you practise here is exactly what [[The Build Sheet]] will ask of
you for real. Three machines, no brand names, one table:

| Spec | Machine A | Machine B | Machine C |
| --- | --- | --- | --- |
| CPU | 2 cores, 2.0 GHz | 4 cores, 3.2 GHz | 8 cores, 3.6 GHz |
| RAM | 4 GB | 8 GB | 32 GB |
| Storage | 500 GB HDD | 256 GB SSD | 1 TB SSD |
| Graphics | integrated | integrated | dedicated, 8 GB |
| Price | $300 | $650 | $1,500 |

## Questions

1. Which machine has the fastest storage — and how can you tell
   from the table alone?
2. A client writes essays, browses, and streams video — and has a
   tight budget. Which machine do you recommend, and why?
3. A client edits video for a living. Which machine, and which
   three rows of the table make the case?
4. An operating system lists a minimum of 4 GB of RAM. Which
   machines meet it — and why is "meets the minimum" not the same
   as "comfortable"?
5. **Find the error.** A classmate recommends Machine A for gaming
   "because 500 GB is bigger than 256 GB". What has been mixed up?
6. **Explain the terms.** What does GHz measure on the CPU row —
   and does more cores always mean a faster machine?
7. **OS versus application requirements.** A workstation runs an OS
   requiring 2 GB RAM and a 20 GB drive partition. A 3D CAD application
   suite requires 16 GB RAM, a dedicated OpenGL GPU, and 50 GB storage.
   Which machine from the table can successfully install and run both,
   and what happens if you attempt to install the application on
   Machine B?

## Answers

> [!success]- Answer 1
> Machines B and C — SSD beats HDD. An SSD has no moving parts; an
> HDD's spinning platters are slow to find data. Capacity says *how
> much*; the drive type says *how fast*.

> [!success]- Answer 2
> Machine B. Light work needs no eight-core engine, and the SSD is
> the upgrade the client will actually *feel*. Machine A's slow
> drive and thin RAM would grind; C spends $850 nobody needs.

> [!success]- Answer 3
> Machine C. Video editing devours cores (8), RAM (32 GB), and
> graphics power (the only dedicated card on the sheet) — and the
> 1 TB SSD swallows the enormous files. For this client, C is
> thrift, not luxury.

> [!success]- Answer 4
> All three meet it — Machine A *only just*. A minimum is the floor
> below which the system will not run, not a promise it runs well:
> with the operating system holding 4 GB, A has nothing left over
> for actual work.

> [!success]- Answer 5
> Capacity mistaken for capability. 500 GB only means more *room*,
> on a slow HDD at that. Gaming leans on graphics, CPU, and RAM —
> and Machine A is the weakest of the three on all of them.

> [!success]- Answer 6
> GHz is clock speed — billions of ticks per second, the tempo of
> the work. More cores means more workers, which helps only when
> software splits its work among them; a stubborn single-file task
> cares about tempo, not headcount. Read both numbers together.

> [!success]- Answer 7
> Machine C. It exceeds the combined requirements (32 GB RAM vs
> 18 GB total, 1 TB SSD vs 70 GB total, dedicated 8 GB graphics card).
> On Machine B (8 GB RAM, integrated graphics), the installer may warn
> of insufficient memory and lack of a dedicated GPU, resulting in
> severe viewport lag, crashing under complex models, or refusal to
> launch.

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[B1.2]]

![[B4.1]]

![[B4.2]]
%%curriculum-end%%
