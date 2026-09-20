---
title: Waves and Sound Practice
publish: true
created: __CREATED__
tags:
  - exercises
  - unit-4
---
**1.** A wave has frequency $250\ \text{Hz}$ and wavelength
$1.4\ \text{m}$. Find its speed and period.

> [!success]- Answer 1
> $v = f\lambda = 350\ \text{m/s}$; $T = 1/f = 4.0 \times 10^{-3}\ \text{s}$.

**2.** You clap and hear the echo from a cliff $1.6\ \text{s}$ later. The
air is at $15^\circ\text{C}$. How far away is the cliff?

> [!success]- Answer 2
> $v = 331 + 0.6(15) = 340\ \text{m/s}$. The sound travelled
> $340 \times 1.6 = 544\ \text{m}$ there and back, so the cliff is
> $272\ \text{m}$ away.

**3.** Two tuning forks, $440\ \text{Hz}$ and $443\ \text{Hz}$, are
struck together. What do you hear?

> [!success]- Answer 3
> Three beats per second — a throbbing at $|443 - 440| = 3\ \text{Hz}$.

**4.** A tube closed at one end resonates with its first resonance at
$0.19\ \text{m}$ under a $440\ \text{Hz}$ fork. Estimate the speed of
sound.

> [!success]- Answer 4
> First resonance is a quarter wavelength, so
> $\lambda = 4(0.19) = 0.76\ \text{m}$ and
> $v = 440 \times 0.76 = 334\ \text{m/s}$.

**5.** Two wave pulses travel toward each other along a taut rope at $2.0\ \text{m/s}$. Pulse A has an amplitude of $+4.5\ \text{cm}$ and Pulse B has an amplitude of $-3.0\ \text{cm}$.
- (a) Using the principle of superposition, determine the resultant displacement at the instant the pulse peaks coincide.
- (b) Two sound sources emit pure tones of $512\ \text{Hz}$ and $517\ \text{Hz}$. Graphically describe how superposition creates the beat envelope and calculate the beat frequency.

> [!success]- Answer 5
> (a) By the principle of superposition, net displacement equals the algebraic sum of individual displacements: $y_{net} = y_A + y_B = (+4.5\ \text{cm}) + (-3.0\ \text{cm}) = +1.5\ \text{cm}$ (destructive interference).  
> (b) As the two waves alternate between constructive alignment (in phase, crest-on-crest) and destructive cancellation (out of phase, crest-on-trough), the wave envelope oscillates periodically in amplitude. $f_{beat} = |f_1 - f_2| = |517 - 512| = 5\ \text{Hz}$ (5 volume pulses per second).

**6.** A $0.85\ \text{m}$ brass air column open at both ends resonates at its fundamental frequency in a room at $20^\circ\text{C}$ ($v = 343\ \text{m/s}$).
- (a) Compute the fundamental frequency and the second harmonic for this open pipe.
- (b) Explain how resonance is intentionally produced in musical wind instruments and how mechanical resonance in bridges and skyscrapers is mitigated through tuned mass dampers.

> [!success]- Answer 6
> (a) For an open-open pipe, the fundamental wavelength is $\lambda_1 = 2L = 2(0.85) = 1.70\ \text{m}$.  
> $f_1 = v / \lambda_1 = 343 / 1.70 = 202\ \text{Hz}$.  
> The second harmonic is $f_2 = 2f_1 = 404\ \text{Hz}$ ($\lambda_2 = L = 0.85\ \text{m}$).  
> (b) In wind instruments, player excitation (reed vibration, lip buzz, air jet) provides a continuous driving frequency; standing waves resonate strongly when the driving frequency matches the acoustic column's natural harmonic modes. In civil engineering, external forces (vortex shedding from wind, seismic ground waves) can drive structures at their resonant frequencies, causing catastrophic oscillations (e.g., Tacoma Narrows). Engineers install tuned mass dampers (heavy suspended pendulums with viscous fluid dampers) that oscillate in antiphase, dissipating vibrational energy through destructive mechanical interference.

**7.** A big brown bat (*Eptesicus fuscus*) emits an ultrasonic echolocation chirp at $40\ \text{kHz}$ in air at $20^\circ\text{C}$ ($v = 343\ \text{m/s}$).
- (a) Compute the wavelength of the chirp and the distance to a flying insect if the echo returns after $0.036\ \text{s}$.
- (b) Explain why bats and medical ultrasound scanners use high ultrasonic frequencies rather than audible frequencies to resolve small targets.

> [!success]- Answer 7
> (a) Wavelength $\lambda = v / f = 343 / (40\ 000) = 8.58 \times 10^{-3}\ \text{m} = 8.6\ \text{mm}$.  
> Total travel distance $2d = v\Delta t = (343)(0.036) = 12.35\ \text{m} \implies d = 6.2\ \text{m}$.  
> (b) Waves diffract (bend) around obstacles whose dimensions are larger than or comparable to their wavelength. High ultrasonic frequencies have sub-centimetre wavelengths ($\le 8\ \text{mm}$), allowing them to reflect clearly off small targets (moths, tissue boundaries) rather than diffracting around them, producing high spatial resolution.

**8.** An industrial workshop exposes workers to an unmitigated noise level of $95\ \text{dB}$.
- (a) Compare the sound intensity of $95\ \text{dB}$ to the maximum continuous safe threshold of $85\ \text{dB}$.
- (b) Assess the physical mechanism and effectiveness of acoustic sound-absorbing wall baffles versus active noise-cancelling (ANC) headsets for protecting hearing.

> [!success]- Answer 8
> (a) Every $10\ \text{dB}$ increase represents a tenfold ($10\times$) increase in sound wave intensity ($I$). A sound level of $95\ \text{dB}$ is $10\times$ more intense than $85\ \text{dB}$, reducing safe allowable exposure time from 8 hours down to under 1 hour to prevent permanent sensorineural hearing loss.  
> (b) Acoustic wall baffles (porous foam, mineral wool) absorb acoustic energy via viscous friction as vibrating air particles move through narrow pores, converting acoustic wave energy into heat. Active noise-cancelling (ANC) headsets use microphones to sample ambient low-frequency sound, inverter circuitry to generate an identical waveform shifted by $180^\circ$ ($\pi$ radians out of phase), and miniature speakers to achieve real-time destructive interference.

%%curriculum-start%%
## Curriculum connection

![[E1.2]]

![[E2.2]]

![[E2.4]]

![[E2.6]]

![[E2.7]]

![[E3.2]]

![[E3.3]]

![[E3.5]]

![[E3.6]]
%%curriculum-end%%
