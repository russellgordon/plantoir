---
title: Soldering a Circuit
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
Breadboards are for experimenting; soldering is how connections become
permanent and reliable. Making a good solder joint is not about melting
glue over a wire — it is about heating the parts so that molten solder
flows across both surfaces to create a clean, low-resistance metallic bond.
[[Electronics Fundamentals]] explains the circuit you are building, and
[[Safety in the Lab]] sets the rules before the iron turns on.

> [!danger] Safety notes
> **The soldering iron tip reaches $350^\circ\text{C}$ ($660^\circ\text{F}$)
> and gives no visual warning that it is hot.** The iron lives in its
> stand whenever it is not in your fingers — never set a hot iron down on
> the bench. **Safety glasses are mandatory** from the moment the station
> powers on until tools are away (spitting flux can cause eye injury).
> **Fume ventilation or extraction must be running** at your bench.
> **Wash hands with soap and water** after handling solder before eating
> or drinking.

## What you need

- [ ] Temperature-controlled soldering station with iron, stand, and damp sponge or brass wool
- [ ] Lead-free rosin-core electronic solder ($0.8\ \text{mm}$ or similar)
- [ ] Safety glasses and active bench fume extractor
- [ ] Prototyping board (perfboard) or copper stripboard
- [ ] Discrete components: one $220\ \Omega$ resistor, one LED, and solid-core connecting wire
- [ ] Wire strippers, flush cutters, and heat-resistant tweezers or pliers
- [ ] Multimeter with continuity mode, journal for sketching

## The work

1. **Mechanical connection first.** Solder is an electrical conductor,
   not structural glue. Insert the component leads through the board,
   bending them slightly on the copper side ($45^\circ$) so the parts
   cannot shift when heated.
2. **Clean and tin the tip.** Wipe the hot iron tip across the damp
   sponge or plunge it into the brass wool to remove oxides, then apply a
   tiny droplet of fresh solder ("tinning"). A shiny tip transfers heat
   instantly; a dull, oxidized tip burns components while heating nothing.
3. **Heat the joint, not the solder.** Touch the wedge of the iron tip to
   **both** the copper pad and the component lead simultaneously. Hold it
   steady for two to three seconds to bring both metals up to soldering
   temperature.
4. **Feed the solder to the joint.** Touch the solder wire to the opposite
   side of the heated joint — **not directly to the iron tip**. When the joint
   is hot enough, the solder melts on contact and flows smoothly around the
   lead and across the pad.
5. **Form the fillet, then remove.** Feed just enough solder to create a
   shiny, concave cone (a "fillet") that covers the pad without bulging.
   Remove the solder wire first, then lift the iron tip away.
6. **Let it cool undisturbed.** Do not blow on the joint or move the lead
   for five seconds while the alloy solidifies. Moving a cooling joint
   causes a fractured "cold joint".
7. **Clip excess leads safely.** With safety glasses on, hold the long end
   of the lead with your finger or pliers so the cut wire cannot fly, and
   trim with flush cutters just above the top of the solder cone.
8. **Inspect and test.** Examine the joint with a magnifier:
   - **Good joint:** Shiny, smooth, concave cone wrapping both lead and pad.
   - **Cold joint:** Dull, grey, grainy surface — re-heat with a touch of fresh solder.
   - **Solder bridge:** Solder spanning across to an adjacent pad — clear it with desoldering braid.
9. **Prove continuity with a multimeter.** Set the meter to continuity/diode
   mode. Probe across the soldered joints to verify low resistance and confirm
   there are no accidental shorts between adjacent tracks before applying power.

## Level up

Solder the complete current-limiting resistor and LED circuit onto the board,
connect the $5\ \text{V}$ supply to the designated power rails, and verify that
the circuit operates reliably under bench vibration.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.2]]

![[D1.1]]
%%curriculum-end%%
