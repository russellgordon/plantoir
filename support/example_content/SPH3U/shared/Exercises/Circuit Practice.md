---
title: Circuit Practice
publish: true
created: __CREATED__
tags:
  - exercises
  - unit-5
---
**1.** A $12\ \text{V}$ supply drives $0.40\ \text{A}$ through a
resistor. Find its resistance and the power it dissipates.

> [!success]- Answer 1
> $R = V/I = 30\ \Omega$; $P = IV = 4.8\ \text{W}$.

**2.** Two resistors, $10\ \Omega$ and $15\ \Omega$, in series across
$9.0\ \text{V}$. Find the current and the voltage across each.

> [!success]- Answer 2
> $R_{total} = 25\ \Omega$, so $I = 0.36\ \text{A}$ everywhere.
> $V_{10} = 3.6\ \text{V}$, $V_{15} = 5.4\ \text{V}$ — and they add to
> the supply, as they must.

**3.** The same two resistors in parallel across $9.0\ \text{V}$. Find
the total resistance and the total current.

> [!success]- Answer 3
> $1/R = 1/10 + 1/15$, so $R = 6.0\ \Omega$ — less than either branch.
> $I = 9.0/6.0 = 1.5\ \text{A}$.

**4.** A kettle draws $12.5\ \text{A}$ at $120\ \text{V}$. What power,
and what does it cost to run for 10 minutes at 13 cents per kWh?

> [!success]- Answer 4
> $P = IV = 1500\ \text{W}$. In 10 minutes that is $0.25\ \text{kWh}$,
> so about 3 cents.

**5.** A current-carrying solenoid with 250 turns is connected to a DC power supply.
- (a) Using the right-hand rule for a coil, describe how the direction of the magnetic field inside the solenoid is determined.
- (b) Compare the three-dimensional magnetic field of the energized solenoid with that of a permanent bar magnet.

> [!success]- Answer 5
> (a) Grasp the solenoid with the right hand so that curved fingers wrap around the coils in the direction of conventional current ($+ \rightarrow -$); the extended right thumb points toward the solenoid's magnetic north pole. Inside the solenoid, field lines are dense, uniform, and parallel.  
> (b) Both generate identical external dipole field shapes (field lines emerging from the north pole and curving around to enter the south pole). Unlike electric field lines which terminate on charges, magnetic field lines form continuous closed loops that pass completely through the interior of the magnet or solenoid from south to north, demonstrating that isolated magnetic monopoles do not exist.

**6.** A generating station delivers $120\ \text{MW}$ of electrical power over a transmission line with total resistance $R = 6.0\ \Omega$.
- (a) Calculate the transmission line current and thermal power loss ($P_{loss} = I^2R$) when power is transmitted at an un-stepped voltage of $12\ \text{kV}$.
- (b) A step-up transformer steps the voltage up to $240\ \text{kV}$ ($N_s/N_p = 20$). Re-calculate the current and power loss.
- (c) Explain safety precautions related to high-voltage transmission lines (overhead conductor clearance, transformer substation security, "Call Before You Dig" underground locate rules).

> [!success]- Answer 6
> (a) At $12\ \text{kV}$: $I = P / V = (1.20 \times 10^8\ \text{W}) / (1.2 \times 10^4\ \text{V}) = 10\ 000\ \text{A}$.  
> Power loss: $P_{loss} = I^2R = (10\ 000)^2(6.0) = 6.0 \times 10^8\ \text{W} = 600\ \text{MW}$ (exceeds total generated power; power would be entirely dissipated as heat).  
> (b) At $240\ \text{kV}$: $I = P / V = (1.20 \times 10^8) / (2.40 \times 10^5) = 500\ \text{A}$.  
> Power loss: $P_{loss} = I^2R = (500)^2(6.0) = 1.5 \times 10^6\ \text{W} = 1.5\ \text{MW}$ (only $1.25\%$ power loss, saving hundreds of millions of watts).  
> (c) High voltages can ionize air and cause dangerous electrical flashover arcs; safety requires elevated clearances on steel pylons, perimeter fencing at step-down substations, and underground cable mapping ("Call Before You Dig") to prevent severe electrocution and transformer explosions.

**7.** Magnetic levitation (Maglev) transit trains and Magnetic Resonance Imaging (MRI) medical scanners are major applications of electromagnetism.
- (a) Explain how electromagnets produce the levitation and propulsion forces in a Maglev system.
- (b) Analyse the social and economic benefits and trade-offs of deploying superconducting electromagnetic technologies.

> [!success]- Answer 7
> (a) Maglev uses superconducting electromagnets along the train chassis and track guideway. Like magnetic poles repel to levitate the train above the track (eliminating mechanical rolling friction $\mu_k = 0$), while alternating linear induction fields along the guideway pull and push the train forward.  
> (b) Benefits: high operational speeds ($>500\ \text{km/h}$), low energy consumption per passenger-km, zero direct emissions, and high-resolution non-invasive soft-tissue medical diagnosis in MRI. Trade-offs: high capital infrastructure costs, reliance on specialized liquid helium cryogenic cooling, and the need for electromagnetic shielding against high stray fields.

**8.** Ontario generates electricity from a diverse grid mix including hydroelectric, nuclear, wind, solar, and natural gas.
- (a) Compare the energy conversion efficiency and greenhouse gas lifecycle emissions of hydroelectric generation ($>85\%$ mechanical-to-electrical efficiency) versus thermal nuclear generation ($33\text{--}35\%$ thermal-to-electrical Carnot efficiency).
- (b) Propose two technological or policy strategies to improve the long-term sustainability of electrical energy production.

> [!success]- Answer 8
> (a) Hydroelectric generation converts gravitational potential energy ($mgh$) directly into turbine kinetic energy and electrical energy with minimal thermal losses, achieving $>85\%$ efficiency and near-zero operational emissions (though reservoir flooding causes initial methane release). Nuclear fission is a thermal thermodynamic cycle limited by the Carnot efficiency of steam turbines ($33\text{--}35\%$), requiring large cooling water heat sinks, but produces steady baseload power with zero carbon emissions.  
> (b) Strategies: (1) Grid-scale energy storage (pumped hydro and battery storage) to capture surplus nighttime wind/nuclear generation for daytime peak demand; (2) Upgrading transmission lines with high-temperature superconducting cables to eliminate $I^2R$ grid losses.

%%curriculum-start%%
## Curriculum connection

![[F1.1]]

![[F1.2]]

![[F2.3]]

![[F2.4]]

![[F2.5]]

![[F3.1]]

![[F3.4]]

![[F3.5]]

![[F3.6]]

![[F3.9]]
%%curriculum-end%%
