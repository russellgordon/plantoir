---
title: Number Systems Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Binary and Hexadecimal]] and the four-minute rounds of
[[Binary Bites]]. Conversions first, then the places these numbers
actually turn up — addresses, colours, and the raw output of a converter.
Do them by hand; the point is to stop needing a tool for a byte.

## Conversions

1. Convert the byte `10110101` to decimal and to hexadecimal.
2. Convert decimal 201 to binary and to hexadecimal.
3. Convert `0x2F` to decimal and to binary, written as a full eight-bit
   byte.
4. How many distinct values can 12 bits represent, and what is the
   largest unsigned number among them?
5. Express decimal −37 in eight-bit two's complement, in binary and in
   hexadecimal.

## Where the bits are doing a job

6. The colour `#1E90FF` is three bytes. Give the red, green, and blue
   values in decimal, and state how many distinct colours this scheme can
   represent.
7. Write the IPv4 address 192.168.1.10 in binary, one octet at a time.
8. A MAC address is written as twelve hexadecimal digits. How many bits
   is that, and roughly how many distinct addresses does it allow?
9. **Explain.** Why does one hexadecimal digit correspond to exactly four
   bits, and why does that make hex more useful than, say, base 10 for
   writing binary data?
10. A 10-bit analog-to-digital converter with a 3.3 V reference reports a
    reading of 683. What voltage is at its input, and what is the
    smallest voltage difference it could possibly detect?
11. A display runs at $1080\text{p}$ ($1920 \times 1080$ pixels) with 24-bit
    true colour ($3\ \text{bytes}$ per pixel) at $60\ \text{Hz}$. How much
    uncompressed memory does a single frame buffer require in megabytes, and
    what raw data transfer rate in gigabits per second is needed to refresh
    the screen at $60\ \text{Hz}$? How do these figures change for a $4\text{K}$
    UHD ($3840 \times 2160$) display?
12. Trace the capacity and throughput scaling of storage media across
    generations: A CD-ROM stores $700\ \text{MB}$ with an $8\times$ transfer rate
    of $1.2\ \text{MB/s}$. A DVD stores $4.7\ \text{GB}$ with an $8\times$ rate
    of $11.08\ \text{MB/s}$. A Blu-ray disc stores $25\ \text{GB}$ at an $8\times$
    rate of $36\ \text{MB/s}$. A modern $2\ \text{TB}$ PCIe 4.0 NVMe SSD transfers
    data at $7000\ \text{MB/s}$.
    (a) How many CD-ROMs of data fit onto a single $2\ \text{TB}$ SSD?
    (b) How long does it take to read $25\ \text{GB}$ of data from a Blu-ray
    disc versus from the NVMe SSD?

## Answers

> [!success]- Answer 1
> Place values from the left are 128, 64, 32, 16, 8, 4, 2, 1. The ones sit at 128, 32, 16, 4, and 1: $128 + 32 + 16 + 4 + 1 = 181$.
>
> For hex, split into nibbles instead of adding anything: `1011` is 11,
> which is B, and `0101` is 5. So `0xB5`.
>
> Check the two against each other: $\text{B} \times 16 + 5 = 11 \times 16 + 5 = 181$. They agree.

> [!success]- Answer 2
> Subtract the largest power of two that fits, repeatedly. 128 fits,
> leaving 73. 64 fits, leaving 9. 32 and 16 do not. 8 fits, leaving 1.
> 4 and 2 do not. 1 fits, leaving 0.
>
> Bits set at 128, 64, 8, and 1: `11001001`.
>
> Nibbles: `1100` is 12, which is C, and `1001` is 9. So `0xC9`.
>
> Check: $12 \times 16 + 9 = 201$.

> [!success]- Answer 3
> $\text{0x2F} = 2 \times 16 + 15 = 32 + 15 = 47$.
>
> Binary by nibbles: 2 is `0010`, F is `1111`, so `00101111`. Keep the
> leading zero — a byte is eight bits whether or not the top one is set,
> and dropping it is how address arithmetic goes wrong.

> [!success]- Answer 4
> $2^{12} = 4096$ distinct values. Counting from zero, they run 0 to 4095, so the largest unsigned value is **4095**, not 4096.
>
> That off-by-one is the same one every time: $n$ bits give $2^n$
> patterns, and the largest is $2^n - 1$ because one pattern is spent
> representing zero.

> [!success]- Answer 5
> Write the magnitude, invert every bit, add one.
>
> 37 in eight bits is `00100101`. Inverting gives `11011010`. Adding one
> gives `11011011`.
>
> In hex, `1101` is D and `1011` is B, so `0xDB`.
>
> Check with the shortcut: the pattern for $-x$ in an eight-bit field is the pattern for $256 - x$, and $256 - 37 = 219$. Is `11011011` equal to 219? $128 + 64 + 16 + 8 + 2 + 1 = 219$. Yes.

> [!success]- Answer 6
> Take the six hex digits in pairs. Red is `1E` $= 1 \times 16 + 14 = 30$. Green is `90` $= 9 \times 16 + 0 = 144$. Blue is `FF` $= 15 \times 16 + 15 = 255$.
>
> So (30, 144, 255) — a strong blue with a fair amount of green in it.
>
> Each channel has 8 bits, so 256 levels, and the three are independent: $256^3 = 16\,777\,216$ distinct colours. That is where "16.7 million colours" on a display specification comes from, and now you can derive it rather than recite it.

> [!success]- Answer 7
> Convert each octet separately to eight bits.
>
> 192 is $128 + 64$, so `11000000`.
>
> 168 is $128 + 32 + 8$, so `10101000`.
>
> 1 is `00000001`.
>
> 10 is $8 + 2$, so `00001010`.
>
> The whole address: `11000000.10101000.00000001.00001010`. This is the
> form you need before a subnet mask makes any sense — see
> [[Networking Practice]].

> [!success]- Answer 8
> Each hex digit is four bits, so twelve digits is $12 \times 4 = 48$ bits.
>
> That allows $2^{48}$ distinct addresses, which is 281 474 976 710 656 —
> a little over 281 trillion. Enough that every network interface ever
> manufactured can have its own, which is the entire design goal.

> [!success]- Answer 9
> Because $16 = 2^4$. One hex digit has sixteen possible values and four
> bits have exactly sixteen possible patterns, so the mapping between
> them is one to one with nothing left over. Converting is therefore
> pure lookup — no arithmetic, no carries, no borrowing across digit
> boundaries.
>
> Ten is not a power of two, so decimal digits do not line up with bit
> groups at all. Converting 181 to decimal required adding five numbers;
> converting it to hex required reading two nibbles. When you are staring
> at a memory dump or a packet capture, that difference is the whole
> reason hex won.

> [!success]- Answer 10
> A 10-bit converter produces $2^{10} = 1024$ codes, numbered 0 to 1023, with 1023 representing full scale.
>
> $V = \frac{683}{1023} \times 3.3\ \text{V} \approx 2.20\ \text{V}$.
>
> The smallest detectable difference is one code step, $\frac{3.3\ \text{V}}{1024} \approx 0.0032\ \text{V}$, about 3.2 mV. No amount of decimal places in your `print` statement improves on that — the resolution is set by the hardware, and reporting a reading as 2.2032 V claims a precision the converter does not have.

> [!success]- Answer 11
> **$1080\text{p}$ Frame buffer size:**
> $1920 \times 1080 = 2\,073\,600\ \text{pixels}$.
> $2\,073\,600 \times 3\ \text{bytes} = 6\,220\,800\ \text{bytes} \approx 6.22\ \text{MB}$ per uncompressed frame.
>
> **$1080\text{p}$ Data transfer rate at $60\ \text{Hz}$:**
> $6\,220\,800\ \text{bytes/frame} \times 60\ \text{frames/s} \times 8\ \text{bits/byte} = 2\,985\,984\,000\ \text{bits/s} \approx 2.99\ \text{Gbps}$.
>
> **$4\text{K}$ UHD comparison:**
> $3840 \times 2160 = 8\,294\,400\ \text{pixels}$ — exactly $4\times$ the pixels of $1080\text{p}$.
> Frame buffer: $8\,294\,400 \times 3\ \text{bytes} = 24\,883\,200\ \text{bytes} \approx 24.88\ \text{MB}$ per frame.
> Bandwidth: $2.986\ \text{Gbps} \times 4 \approx 11.94\ \text{Gbps}$.
> This quadrupling in data rate explains why high-resolution displays forced interfaces to advance from HDMI 1.4 ($10.2\ \text{Gbps}$) to HDMI 2.0 ($18\ \text{Gbps}$) and DisplayPort 1.4/2.0 ($32.4\text{--}80\ \text{Gbps}$).

> [!success]- Answer 12
> **(a) Capacity comparison:**
> $2\ \text{TB} = 2\,000\,000\ \text{MB}$.
> $\frac{2\,000\,000\ \text{MB}}{700\ \text{MB/CD}} \approx 2857\ \text{CDs}$.
> A single M.2 drive smaller than a finger stores the equivalent of nearly three thousand CD-ROMs.
>
> **(b) Read time for $25\ \text{GB}$ ($25\,000\ \text{MB}$):**
> Optical Blu-ray disc: $t = \frac{25\,000\ \text{MB}}{36\ \text{MB/s}} \approx 694.4\ \text{s} \approx 11.6\ \text{minutes}$.
> NVMe M.2 SSD: $t = \frac{25\,000\ \text{MB}}{7000\ \text{MB/s}} \approx 3.57\ \text{seconds}$.
> The NVMe drive reads the same payload nearly $200\times$ faster, illustrating why solid-state storage displaced optical media as the primary storage and software distribution standard.

Take these to where they bite: [[Logic Gates Practice]] treats the bits
as decisions, and [[Networking Practice]] treats them as addresses.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[A5.1]]

![[A5.2]]
%%curriculum-end%%
