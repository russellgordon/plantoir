---
title: _DUPLICATE ME
publish: false
created: __CREATED__
tags: [template]
---

Duplicate this page to add a new idea to Concepts. A Concepts page names
something students have already met in class — a literary, rhetorical, or
media concept encountered through a text, discussion, or activity — and
states it cleanly once the class has worked with it. Read-first, name-
after: never open a new Concepts page with a bare definition nobody has
seen in action yet.

## Before you start

Ask yourself where in your course this idea is genuinely taught. A
Concepts page needs an honest home: a class page (or a page that class
page links to) that actually uncovers the idea, not a day you are
stapling it to so the link exists. If the idea has no honest home yet,
your course is missing a class, not a page.

## Starting shape

Copy this frontmatter and heading structure, then replace the content:

```
---
title: Your Concept Name
publish: true
created: __CREATED__
tags: [concepts]
enableToc: false
---

Ground the opening paragraph in the actual text, discussion, or activity
that taught this idea. Name what students already noticed before you
name the concept itself.

## First aspect of the idea

## Second aspect, or how it connects to something already named

## Where this returns
```

Set `enableToc: true` only once the page has four or more `##` headings.
Pick one Obsidian feature that genuinely serves this particular page — a
table, a callout, a folded callout, a small mermaid diagram, a footnote,
or a read-only checklist — and use it once. Do not reach for the same
feature every other Concepts page already uses; variety is part of what
keeps this folder worth reading.

## Linking it into the course

Link this page from the class page where the idea is actually taught, or
from a page that class page already links to (a Text or Discussion page,
for instance). A page nothing reaches is an orphan the site linter will
catch — but catching it late costs more time than linking it honestly
the first time.

## Curriculum connection

Optional here, but add it honestly where it genuinely belongs. If this
concept truly teaches a specific Ministry expectation, check the exact
wording in `Curriculum/` before you cite it — a code that only loosely
fits is worse than no code at all. Where it belongs, add it as the very
last thing on the page:

```
%%curriculum-start%%
## Curriculum connection
![[CODE]]
%%curriculum-end%%
```
