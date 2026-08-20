---
title: _DUPLICATE ME
publish: false
created: __CREATED__
tags: [template]
---

Duplicate this page to start a new Media Studies activity. Delete this
paragraph and everything below it that you do not need, then fill in your
own.

## What belongs in this folder

A Media Studies page is an activity or a how-to that a small group or an
individual student can actually run — not a lecture about media theory.
Give a concrete process: what to bring, what to do first, what to produce
by the end of the period. Look at the other pages already in this folder
for the shape.

## Frontmatter to copy

```
---
title: Your Activity Title
publish: true
created: __CREATED__
tags: [media-studies]
---
```

Set `enableToc: true` only if the finished page has four or more `##`
headings — most activity pages land around three and do not need it.

If your title needs a colon or a question mark, the filename cannot carry
it (Windows will not allow `<>:"|?*` in a filename, and a repository with
one refuses to check out there). Swap the colon for ` -` in the filename
and put the real title, punctuation included, in the `title:` field — the
pattern already used in this folder for "News Bias: Comparing Two
Headlines" and "Podcast Basics: Writing for the Ear". Link to a page like
that with a piped alias: `[[Filename - Without Colon|Title: With Colon]]`.

## One Obsidian feature, used honestly

Pick ONE feature that genuinely serves this page — a table (a
technique/example table, a template students fill in), a callout (a
worked example, a warning), or a footnote (a source or an aside that would
interrupt the main text). Do not stack two or three features onto one page
just to show them off.

## Curriculum connection

Every published activity page ends with a curriculum block, near the end
of the page, in this exact shape — plain codes only, no other text inside
the markers:

```
%%curriculum-start%%
## Curriculum connection
![[D1.5]]
%%curriculum-end%%
```

Check the code against the Curriculum folder before using it, and make
sure the page genuinely does what the expectation describes — not just
something in the same general area.

## Reachability

This page has to be reachable from a class page (`Unit N, Day M`), either
directly or through one page that class page links to. Add the link from
the real class day before you consider the page finished, and add this
page to `Media Studies/index.md` alongside the other activities.

## Before you publish

Preview the built site and open this page for real — check the table,
callout, or footnote renders the way you expect, and that every link
resolves.
