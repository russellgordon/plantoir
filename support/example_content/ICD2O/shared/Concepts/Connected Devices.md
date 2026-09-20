---
title: Connected Devices
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
After [[Inside the Box]], you start seeing computers everywhere —
because they are everywhere. Your phone is one, obviously. But so is
your watch, your earbuds, the speaker in the kitchen, the doorbell,
the bus pass reader, and most of the family car. Few of them ever get
called computers. They get called "smart".[^1]

## What a connected device really is

Strip away the marketing and every smart device is the same recipe: a
small computer, some sensors, and a network connection. The speaker
is a microphone plus wifi. The watch is a heart-rate sensor plus
Bluetooth. The doorbell is a camera plus your home network. Nothing
in the box is new — [[Hardware Inside the Box]] covered every part.
What is new is that the parts became cheap enough to put into
everything.

## The sensors around you

A sensor turns something about the physical world into data a program
can use. Right now your phone carries an accelerometer for movement,
a GPS radio for location, a light sensor, several cameras, and more
than one microphone. Your watch may add heart rate and skin
temperature. None of this is sinister by itself — a step counter
needs an accelerometer — but it means "using a device" and
"generating data" are now the same act.

## Connected both ways

The network connection is what makes these devices useful, and it
runs in both directions. Weather comes down; your location goes up.
Music streams in; your listening history flows out. That trade is
often worth making, but it should be a trade you notice.
[[Who Owns Your Data]] takes up where the data goes,
[[Networks and Connectivity]] follows how it travels, and
[[Staying Secure Online]] is about keeping the flow on your terms.

## Assessing requirements for connected devices

Recommending or deploying connected hardware (as in
[[The Device Recommendation]]) requires matching device specifications to
user contexts:

- **Range and wireless protocols** — low-power Bluetooth (BLE) for
  wearables and short-range peripherals; local Wi-Fi for high-bandwidth
  smart-home hubs and cameras; cellular/LPWAN for remote sensors.
- **Power constraints** — battery-operated sensors require efficient
  sleep cycles and minimal transmission frequency.
- **Privacy and data controls** — evaluating whether voice and video data
  are processed on-device (edge computing) or streamed to cloud servers,
  and whether strong encryption and security updates are supported.

[^1]: "Smart" is a marketing word, not a technical one. A smart
    speaker cannot think — it can hear, connect, and follow
    instructions that programmers wrote. "Connected" is the honest
    term, which is why this page prefers it.

%%curriculum-start%%
## Curriculum connection

![[B1.2]]

![[B2.3]]

![[B4.2]]
%%curriculum-end%%
