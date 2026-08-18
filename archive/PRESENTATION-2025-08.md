# Take Control of Publishing Your Content

> **Archived, and kept as a record.** This is the handout for a workshop
> session run in **August 2025**. It is out of date in ways that matter if you
> follow it today: the software now ships as a macOS and a Windows app (this
> document predates both and sends you to the command line), publishing now has
> three destinations rather than Netlify alone, and — the one that would
> actually mislead — **the claim below that you need to be an Administrator is
> no longer true on macOS.** The launchers install everything they need into
> the app's own space: no Homebrew, no administrator password. Administrator
> rights are still needed once on Windows, to install WSL2.
>
> For current instructions, start at [`../README.md`](../README.md).

> [!NOTE]
> 
> This material was initially shared on Thursday, August 14, 2025 at the [Summer Conference for Computer Studies and Mathematics Educators](https://cemc.uwaterloo.ca/workshops/educator-development/summer-conference-educators), organized by the [Centre for Education in Mathematics and Computing](https://www.cemc.uwaterloo.ca/).
> 
> The original session title and description was:
> 
> > **An Even Faster Workflow for Publishing Teaching Materials**
> >
> > Content management systems such as Edsby, Brightspace, Google Classroom... the list of third-party platforms we depend on as teachers to share information with our students is long. The user interfaces of these systems? Questionable, often requiring a time-consuming series of clicks and selections to publish even the simplest information. Further, it is often difficult to move your valuable content out of these systems. In this session, the presenter will share a pre-configured publishing system that you control, can take away from the conference, and then run on your own computer to build modern, standards-compliant class websites. In the session, optionally complete a series of “quests” to learn how to use this publishing workflow and get assistance from the presenter in setting up your own website on the spot. You will learn how to use Markdown-formatted text files to quickly publish a deeply linked, searchable website, with pages that can include “pretty-print” mathematical formulae and equations, code snippets, diagrams, animations, images, videos, PDF files, or any other type of document.

## Agenda

For this double session, here is the plan:

|Timing|Goals|
|-|-|
|5 minutes|Introduction|
|10 minutes|Example site|
|15 minutes|Install software|
|15 minutes|Install example site|
|45 minutes|Complete quests|
|15 minutes|*Break*|
|60 minutes|Create your own site|
|30 minutes|Share results|

## Introduction

Why might a teacher want to publish our own website?

1. Better experience for students
	- Code blocks are supported
	- "Pretty print" symbolic math
	- Linking to headers within a document
	- Search that actually works
	- Light and dark mode built-in
2. Learning management software is bad
	- Edsby is prone to losing edits 😡
	- Too many clicks required to do much of anything
3. Better workflow
	- Support for shared content and multiple sections of a course
4. Control over your content
	- Moving employers
	- De-coupling from large software providers
5. Future proof
	- Content is nothing more than plain text files [in Markdown format](https://help.obsidian.md/syntax)

Some comments from students from the author's own course feedback survey:

> THE WEBSITE. ITS AWESOME. I miss a lot of days because of practices and this is the best class to catch up in, everything is so easy to find and very well explained. The tutorials are so great.

> Class website! Awesomeness! Using Notion! Awesomeness!

<img width="982" height="495" alt="Pasted image 20250814080547" src="https://github.com/user-attachments/assets/e575ce02-08b2-4fdf-a814-d73ba96373ba" />

## Example site

Before you commit to this double-session – take some time to [explore the type of output](https://exc2o-s1-2024-gordon.netlify.app/) produced by this workflow. Will it fit your needs?

<img width="1366" height="999" alt="Pasted image 20250814081337" src="https://github.com/user-attachments/assets/5f440320-2c19-4a4b-a908-90a1d86e0016" />


## Install software

Please follow [the instructions given here](https://github.com/russellgordon/plantoir?tab=readme-ov-file#-quick-start-for-teachers). 

> [!TIP] 
> 
> You do need to be an Administrator on your computer to complete this installation.

## Install example site

Once you have the workflow scripts available on your computer, it is recommended that you install the example course website:

```
📦 Optional: Install an Example Course
The 'EXC2O' course (stands for 'Example Course') demonstrates how content is organized in Obsidian and how Quartz renders it into a site.
Recommended if you're NEW to this workflow — you can remove it later.

Install the Example Course now? (y/n) [Default: n]:
```

It is helpful to compare the visual appearance of the site:

<img width="1366" height="999" alt="Pasted image 20250814081337" src="https://github.com/user-attachments/assets/6941e3f8-e926-4adc-9557-7dd90e2f34a0" />

... with what the source files in Obsidian look like:

<img width="3024" height="1888" alt="Screenshot 2025-08-14 at 8 15 18 AM" src="https://github.com/user-attachments/assets/20492091-34c4-411d-9b5b-ef064cc0d1f8" />

## Complete quests

Source files are edited in [Obsidian](https://obsidian.md) which is an editing environment that makes it easy to create linked websites and to integrate media such as screenshots and videos to your class website.

Some useful shortcuts for Obsidian are:

|Shortcut|Effect|
|-|-|
|Command-E|Toggle between source and preview modes|
|Command-K|Create a link|
|Shift-Return|Soft line break (stay on current bullet point, for example)|

> [!TIP]
> 
> Are you a macOS user? [Learn how to take screenshots *without* cluttering up your Desktop with screenshot files](https://exc2o-s1-2024-gordon.netlify.app/tutorials/taking-screenshots). You can simply *paste* captured screenshots into Obsidian.

By completing the "quests" below, you will become better versed in how to use Obsidian to change the appearance or structure of a class website.

> [!NOTE]
> 
> Bookmark [this page on Markdown syntax in Obsidian](https://help.obsidian.md/syntax). It's really useful.

### Open a vault

After installing the example site, you will have the example course on your computer.

Open the folder containing these files in Obsidian. This will become your "vault":

<img width="800" height="650" alt="Pasted image 20250814081949" src="https://github.com/user-attachments/assets/b7d3ebec-a7c0-4696-b83f-990b64f5e01c" />

<img width="978" height="464" alt="Pasted image 20250814082047" src="https://github.com/user-attachments/assets/2e4a1904-f160-49fd-813d-14928026750e" />

### Find a file

Navigate the Obsidian interface to find this file:

<img width="1512" height="944" alt="Pasted image 20250814082141" src="https://github.com/user-attachments/assets/853ad4da-629e-4fa8-bc1c-fbf3451fb6e3" />

### Toggle modes

Try viewing this page in preview mode:

<img width="1512" height="944" alt="Pasted image 20250814082318" src="https://github.com/user-attachments/assets/cad95922-406b-4baf-bdc6-77ab57bb5500" />


### Preview multiple sections

What is different when you run this command:

```
./preview.sh EXC2O 1
```

Compared to this command:

```
./preview.sh EXC2O 2
```

### Understand frontmatter tags

Take a careful look at this screenshot – why is **Thread 2, Day 11** missing from the published site?

<img width="1366" height="999" alt="Pasted image 20250814082915" src="https://github.com/user-attachments/assets/c26bebbc-50d8-45e2-a3f2-93a39c67bc51" />

### Add a screenshot

Take a screenshot. Drag and drop it into any file in the example site's Obsidian vault. Preview the page by toggling the source/preview mode using **Command-E**.

### Add a callout

It's helpful to provide tips or important notes to readers, outside the main narrative of a lesson.

Try [adding a callout](https://help.obsidian.md/callouts) to a page.

## Break time

Take a few minutes for a body break.

When you get back, let's get you started on building your own class website.

## Create your own site

You can create a site from scratch, or install the example site and modify it to suit your needs.

The presenter will circulate to help out.

## Share results

Let's do a little show and share to conclude.

As we finish up, are there any more questions?
