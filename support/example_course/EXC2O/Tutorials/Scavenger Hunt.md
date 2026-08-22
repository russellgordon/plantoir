---
title: Scavenger Hunt
createdSection1: 2026-09-08T07:00:00.000-0400
publishForSection1: true
createdSection2: 2026-09-09T07:00:00.000-0400
publishForSection2: true
enableToc: true
tags:
  - tutorials
  - reference
---
Welcome! If you have never used Obsidian or Markdown before, you might wonder why these notes look like plain text and how they turn into a polished website for your students.

Here is the secret: **you already know how to plan great lessons.** Obsidian is just a distraction-free digital notebook stored safely on your computer, and Plantoir is your automated website builder. When you click **Preview** or **Deploy** in Plantoir, your notes are instantly turned into a fast, searchable website with navigation, hover previews, and clean typography.

> [!tip] Opening your course in Obsidian
> - If you have not installed Obsidian yet, download it free from [obsidian.md/download](https://obsidian.md/download).
> - You can open this entire course in Obsidian at any time from Plantoir: simply **right-click (or Control-click) on your class section in Plantoir and choose "Open in Obsidian"**.

You do not need to learn dozens of complex computer tricks. There are just **7 short stations** that give you almost all of the power.

This scavenger hunt takes about 10 minutes. Work through the challenges below right here on this page. Each challenge has a **Goal**, a **Practice Sandbox**, a folded **Hint**, and a folded **Solution** so you can check your work as you go.

---

## Station 1: The Quick Switch

In Obsidian, you write in **plain text** with a few simple punctuation marks. Obsidian lets you view your notes in two ways:

1. **Editing View** — where you type your words and format them.
2. **Reading View** — where Obsidian renders all formatting, highlights, and callouts cleanly.

You can switch between them in a fraction of a second with a single keyboard shortcut:
- **Mac:** Press <kbd>⌘</kbd> + <kbd>E</kbd>
- **Windows:** Press <kbd>Ctrl</kbd> + <kbd>E</kbd>
*(You can also click the small book or pen icon in the top right corner of the note window).*

> [!tip] Try it right now!
> Press <kbd>⌘</kbd> + <kbd>E</kbd> (or <kbd>Ctrl</kbd> + <kbd>E</kbd>) right now. Notice how this callout turns into a smooth coloured box and the solutions below fold up. Press it again to return to editing mode and start Station 2!

---

## Station 2: Text that Teaches

Students rarely read a wall of plain text; they scan for structure and key terms. Markdown lets you format text as quickly as you type:

- `**bold**` draws the eye to important instructions or deadlines.
- `*italics*` adds gentle emphasis or book/play titles.
- `==highlights==` puts a bright yellow highlighter across vocabulary words or key concepts.
- `## Headings` organise your page into sections.

> [!important] Why headings matter in Plantoir
> Every `##` heading you write automatically becomes a clickable link in the **Navigate this page** table of contents on the right side of your published website! You never have to build a table of contents by hand.

### Your Goal
In the practice box below, format the raw draft announcement:
1. Make the first line an `###` sub-heading.
2. Put the due date (`Friday at 3:00 PM`) in **bold**.
3. Highlight the key vocabulary term (`focal point`).
4. Put the reminder note (`submitted via student portfolio`) in *italics*.

### Practice Sandbox 2
*(Edit the text below)*

Unit 1 Project Checkpoint
Please remember that your initial draft is due Friday at 3:00 PM.
All drafts must be submitted via student portfolio before our next class.
Key concept for today: focal point is the area of a composition that first attracts the viewer's attention.

> [!tip]- Need a hint? (click to expand)
> - Add `### ` to the start of the title line.
> - Surround text with `**` for bold: `**Friday at 3:00 PM**` (Shortcut: <kbd>⌘</kbd>/<kbd>Ctrl</kbd> + <kbd>B</kbd>).
> - Surround text with `==` for highlight: `==focal point==`.
> - Surround text with `*` for italics: `*submitted via student portfolio*` (Shortcut: <kbd>⌘</kbd>/<kbd>Ctrl</kbd> + <kbd>I</kbd>).

> [!success]- Solution & Visual Check (click to expand)
> **What you type in editing view:**
> ```markdown
> ### Unit 1 Project Checkpoint
> Please remember that your initial draft is due **Friday at 3:00 PM**.
> All drafts must be *submitted via student portfolio* before our next class.
> Key concept for today: ==focal point== is the area of a composition that first attracts the viewer's attention.
> ```
> 
> **How it looks to your students:**
> > ### Unit 1 Project Checkpoint
> > Please remember that your initial draft is due **Friday at 3:00 PM**.
> > All drafts must be *submitted via student portfolio* before our next class.
> > Key concept for today: ==focal point== is the area of a composition that first attracts the viewer's attention.

---

## Station 3: The Living Web

In traditional word processors, documents sit in isolated files. In Obsidian and Plantoir, your pages connect together like a real web.

To create a link to another page in your course:
1. Type two open square brackets: `[[`
2. Start typing the name of any page in your course (like `Help Sessions` or `Learning Goals`).
3. Obsidian shows a pop-up menu of matching notes. Press <kbd>Return</kbd> or <kbd>Enter</kbd> to select it!

### Custom Display Words (Piped Links)
What if you want to link to a page called `Help Sessions.md`, but you want the sentence to read: "Come to our [[Help Sessions|after-school help clinic]]"? 
Use the vertical bar `|` (called a pipe):
```markdown
[[Target Page Name|Words students read]]
```

> [!tip] Why links are magic in Plantoir
> - **Hover Previews**: On your website, students can hover their cursor over any `[[link]]` to read a pop-up preview of that page without navigating away.
> - **Backlinks**: At the bottom of every page, Quartz gathers an automatic list of every class or assignment that links to it!

### Your Goal
In the practice box below:
1. Add a direct link to `[[Help Sessions]]` on item 2.
2. Add a piped link on item 3 pointing to `Learning Goals` that displays as `our course learning goals`.

### Practice Sandbox 3
*(Edit the lines below)*

1. Warm-up: Review today's agenda.
2. Need extra help? Check our schedule on [insert link to Help Sessions].
3. For homework, review [insert piped link to Learning Goals that reads 'our course learning goals'].

> [!tip]- Need a hint? (click to expand)
> - For item 2: Type `[[Help Sessions]]`.
> - For item 3: Type `[[Learning Goals|our course learning goals]]`. (The `|` pipe key is usually typed with <kbd>Shift</kbd> + <kbd>\</kbd>).

> [!success]- Solution & Visual Check (click to expand)
> **What you type in editing view:**
> ```markdown
> 1. Warm-up: Review today's agenda.
> 2. Need extra help? Check our schedule on [[Help Sessions]].
> 3. For homework, review [[Learning Goals|our course learning goals]].
> ```
> 
> **How it looks to your students:**
> 1. Warm-up: Review today's agenda.
> 2. Need extra help? Check our schedule on [[Help Sessions]].
> 3. For homework, review [[Learning Goals|our course learning goals]].

---

## Station 4: Engaging Callouts

Callouts pull key information out of the flow of the page with friendly colours and icons:
- `> [!tip] Useful Tip` (green / light bulb)
- `> [!note] Lesson Note` (blue / pencil)
- `> [!important] Crucial Rule` (purple / flame)
- `> [!warning] Common Mistake` (orange / triangle)
- `> [!danger] Safety` (red / stop)

### Collapsible (Folded) Callouts
Adding a single hyphen `-` immediately after the bracket makes a callout **collapsible**:
```markdown
> [!question]- Self-Check: What is the shortcut for Reading View? (click to reveal)
> Press **Command-E** (Mac) or **Control-E** (Windows)!
```
On your website, students see a clean question box. When they click on it, the answer expands smoothly. This is perfect for practice questions, reflection prompts, and hints!

### Your Goal
In the practice box below, build a collapsible `[!question]-` callout with a question in the title and a hidden answer inside.

### Practice Sandbox 4
*(Create your callout below)*

> [!question]- Try It Yourself: How do you create an internal link in Obsidian? (click to reveal)
> (Write the answer inside this callout!)

> [!tip]- Need a hint? (click to expand)
> Start every line of the callout with `> `.
> First line: `> [!question]- Your Question Title`
> Second line: `> Your hidden answer text here.`

> [!success]- Solution & Visual Check (click to expand)
> **What you type in editing view:**
> ```markdown
> > [!question]- Quick Quiz: How do you create an internal link in Obsidian? (click to reveal)
> > Type double square brackets: `[[Page Name]]`. Obsidian will even autocomplete it for you!
> ```
> 
> **How it looks to your students:**
> > [!question]- Quick Quiz: How do you create an internal link in Obsidian? (click to reveal)
> > Type double square brackets: `[[Page Name]]`. Obsidian will even autocomplete it for you!

---

## Station 5: Transclusion

In a normal document setup, if your office hours or classroom rules change, you have to edit six different files.

Obsidian has a superpower called **Transclusion** (embedding). Putting an exclamation mark `!` in front of a link embeds that entire page live inside another page:
```markdown
![[Help Sessions]]
```
When you change the date or room in `Help Sessions.md`, every page where you embedded it updates automatically on your website.

### Your Goal
In the practice sandbox below, embed the `Help Sessions` note right into the page.

### Practice Sandbox 5
*(Embed Help Sessions below)*

Below is our current extra help schedule:

(Embed Help Sessions here)

> [!tip]- Need a hint? (click to expand)
> Type `!` followed by `[[Help Sessions]]` on its own line: `![[Help Sessions]]`.

> [!success]- Solution & Visual Check (click to expand)
> **What you type in editing view:**
> ```markdown
> Below is our current extra help schedule:
> 
> ![[Help Sessions]]
> ```
> 
> **How it looks to your students:**
> When rendered, the actual contents of `Help Sessions.md` will appear cleanly framed inside the page!

---

## Station 6: The Teacher's Cloak

You often want to keep notes to yourself (answer keys, pacing reminders for next year, student accommodations) without students ever seeing them.

### 1. In-line Teacher Comments
In Obsidian, wrap any private text in double percent signs: `%` `% private note %` `%.

For example, when writing your lesson notes:
- Public line: `Please complete questions 1 through 5 for tomorrow.`
- Private line: `%` `% Note for next year: Most students struggled with #3; allocate 10 extra minutes. %` `%`

In Obsidian, you will see the comment in grey text while editing. When Plantoir builds your website, these comments are **completely stripped out before the site is generated** — private comments never leave your computer, so they literally do not exist on the website your students see.

### 2. Holding Back a Page (`publish: false`)
At the very top of every file is a header between two lines of dashes `---` (called frontmatter). 
- If you set `publish: true`, the page is included on the website.
- If you set `publish: false`, Plantoir skips that page entirely during the build — it stays strictly on your computer and is never published or uploaded anywhere.

This lets you plan next week's unit or draft a quiz in advance without students stumbling upon it early.

### Your Goal
In the practice box below:
1. Write a public instruction for students.
2. Add a private teacher-only comment wrapped in double percent signs (`%` `%).

### Practice Sandbox 6
*(Add your notes below)*

Students: Please bring your project rough draft to class tomorrow.
(Add a private comment below this line that will never leave your computer)

> [!tip]- Need a hint? (click to expand)
> In Obsidian, wrap your private note in two percent signs before and after:
> `%` `% Remember to prepare the sample rubrics on the front table before period 2. %` `%`

> [!success]- Solution & Visual Check (click to expand)
> **What you type in Obsidian editing view:**
> - Line 1: `Students: Please bring your project rough draft to class tomorrow.`
> - Line 2: `%` `% Reminder to self: Period 2 is running 10 minutes ahead of Period 4. %` `%`
> 
> **How it looks to your students on the published website:**
> > Students: Please bring your project rough draft to class tomorrow.
> 
> *(The private comment is completely stripped out during the build and never exists on the published site!)*

---

## Station 7: The Plantoir Loop

Now for the best part: seeing your work transformed into a real, live website.

### Your Daily Teaching Rhythm
When running a course with Plantoir, your daily routine is simple:
1. **Write in Obsidian**: Open today's class page (or duplicate `_DUPLICATE ME.md` in any folder) and write your agenda with a few links.
2. **Click Preview in Plantoir**: Open the Plantoir desktop app and click the **Preview** button for your class section.
3. **Check Your Browser**: Your default browser will open with your live course website. Keep this browser window side-by-side with Obsidian!
4. **Live Updates**: When you save changes in Obsidian, your preview website refreshes automatically within seconds.

### Your Final Mission
1. Switch to the Plantoir app on your computer.
2. Click **Preview** for Section 1.
3. In the browser tab that opens, click **Scavenger Hunt** at the bottom of **Key Links** (or press <kbd>⌘</kbd> + <kbd>K</kbd> / <kbd>Ctrl</kbd> + <kbd>K</kbd> and search for it).
4. See your completed challenges rendered live on the website, and click your collapsible callouts to test them!
5. **The Final Step — Unpublish This Tutorial**: Now that you have completed the hunt, you don't need students to see this practice page. Scroll to the very top of this file in Obsidian, change `publish: true` to `publish: false`, and save. Switch back to your preview browser — the Scavenger Hunt page is gone from your website, but remains safely in your Obsidian vault whenever you need a quick reminder!

---

## Quick Reference

Keep this table handy whenever you are writing course notes:

| What you want to do | What you type in Obsidian | What it does for your students |
| :--- | :--- | :--- |
| **Link to another page** | `[[Page Name]]` | Clickable link with instant hover pop-up preview |
| **Link with custom text** | `[[Page Name\|Display words]]` | Clickable link showing friendly display words |
| **Embed an entire page** | `![[Page Name]]` | Inserts the live page (write once, updates everywhere) |
| **Callout box** | `> [!tip] Tip Title` | Coloured box with icon to highlight key information |
| **Collapsible self-check** | `> [!question]- Quiz Title` | Box with hidden content that expands on click |
| **Section heading** | `## Topic Title` | Header + automatically added to Table of Contents |
| **Highlight vocabulary** | `==Key term==` | Bright highlight to draw student attention |
| **Private teacher note** | `%` `% Note to self %` `%` | Stripped during build; never leaves your computer |
| **Hold back a draft** | `publish: false` in header | Never published or uploaded until you set to true |

You are now fully equipped to build and run an incredible, connected course website. Whenever you want to create a new page, look for `_DUPLICATE ME.md` in any folder, duplicate it, and start writing!
