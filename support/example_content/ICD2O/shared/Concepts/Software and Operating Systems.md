---
title: Software and Operating Systems
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
By the time you finished [[Setting Up Python]], you had already met
the two layers this page names: the app you installed, and the
operating system you installed it *into*. Every device works this way
— a stack, with your apps on top and one very busy program
underneath.

## Apps do one job

An app — short for application — is software with a purpose you can
say in a sentence. Browse the web. Edit photos. Play music. Run
Python. Apps are the layer you choose: each one is on your device
because somebody decided to put it there, and each can be removed
without the device caring.

## The operating system does everything else

The OS — Windows, macOS, iOS, Android, Linux — is the program that
runs the machine itself. It decides which app gets the CPU next,
parcels out memory, draws the windows, reads the keyboard, and
guards the files. Apps never touch the hardware from
[[Hardware Inside the Box]] directly — they ask the OS, and the OS
does the touching. That is also why the "same" app on your phone and
your laptop is really two apps: each was written to ask a different
OS.

## File systems and storage organisation

The operating system manages how data is saved to physical and cloud
storage. It structures files into hierarchical folders (directories),
tracks file paths, and enforces access permissions. Good file management
habits — structuring directories by project, maintaining backups, and
knowing whether a file lives locally or in cloud sync — are covered in
[[Files and the Cloud]].

## Researching software and assessing requirements

Before adopting new software tools or recommending programs to a client
(as in [[The Device Recommendation]]), systematic research is required:

- **System and hardware compatibility** — verify whether the software
  supports the user's OS version, processor architecture, and available
  RAM.
- **Consulting authoritative documentation** — review official release
  notes, developer guides, and help documentation (as taught in
  [[Finding Answers Online]]) rather than relying on unverified forum
  opinions.
- **Licensing, privacy, and support** — evaluate whether open-source or
  commercial tools best suit the user's budget and security needs.

## Updates are maintenance, not nagging

All software ships with mistakes in it — all of it, always, which is
why [[Debugging Is the Job]] is a discussion and not a joke. Updates
are how mistakes get fixed after shipping, and some of those
mistakes are security holes that [[Staying Secure Online]] would
rather you not leave open.

> [!tip] The unglamorous truth about updates
> An update notification is a repair crew offering to fix your house
> for free. Scheduling it for a convenient hour is sensible —
> overnight is fine. Postponing it forever mostly protects the bugs.

%%curriculum-start%%
## Curriculum connection

![[B1.3]]

![[B2.1]]

![[B2.2]]

![[B2.3]]
%%curriculum-end%%
