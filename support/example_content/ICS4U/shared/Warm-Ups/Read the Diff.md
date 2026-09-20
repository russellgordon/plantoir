---
title: Read the Diff
publish: true
created: __CREATED__
tags:
  - warm-ups
---
A change goes on the board in the form version control actually shows
it: a few lines removed, a few lines added, and no explanation. Two
questions. **What does this change do?** And **would you approve
it?** This is the newest routine in the course and the one that most
closely resembles a working day. Somebody on your team is going to
push a change to shared code this week, and somebody is going to have
to read it before it lands.

## How to read a diff

Lines beginning with `-` were removed. Lines beginning with `+` were
added. Everything else is context, printed only so you can see where
the change sits. The `@@` line names the region of the file. Nothing
else is happening.

## Today's board

```text
diff --git a/signin.py b/signin.py
index f6347a3..b6d4e42 100644
--- a/signin.py
+++ b/signin.py
@@ -1,6 +1,13 @@
 def find_member(names, wanted):
     """Return the position of wanted in names, or -1 if absent."""
-    for position in range(len(names)):
-        if names[position] == wanted:
-            return position
+    low = 0
+    high = len(names) - 1
+    while low <= high:
+        middle = (low + high) // 2
+        if names[middle] == wanted:
+            return middle
+        elif names[middle] < wanted:
+            low = middle + 1
+        else:
+            high = middle - 1
     return -1
```

Read it before you read the next paragraph. What changed, and would
you approve it?

The author replaced a linear search with a binary search. The new
code is correct binary search, it is much faster on a long list, and
the docstring is untouched. Plenty of rooms approve it on the spot.

Then somebody runs it on the sign-in sheet as it actually arrives:

```python
sheet = ["Nadia", "Ali", "Rowan", "Bea"]
print(find_member(sheet, "Rowan"))
print(find_member(sheet, "Bea"))
```

```text
2
-1
```

Bea is on the sheet. The program says she is not. Binary search only
works on a **sorted** list, the sign-in sheet is in arrival order,
and nothing in the diff — or in the docstring it left alone —
mentions that. No crash, no warning, and a real person is told she is
not registered.

> [!warning] Fast and wrong is worse than slow and right
> The old version was slower and always correct. Approving this diff
> as written trades a cost nobody was complaining about for a failure
> nobody will notice. That trade is at the heart of
> [[Efficiency and Big-O]]: a faster algorithm brings conditions with
> it, and the conditions are part of the change.

## What a reviewer actually says

The change is not wrong. It is *incomplete*, and there is a version
of it worth approving. A useful review says so, out loud, in that
order:

- [ ] Name what the change does, in your own words, before judging
      it. If you cannot, ask — a question is a legitimate review
      outcome.
- [ ] Say what is good about it. Here: the binary search is
      correctly written, including the boundary that usually gets
      people.
- [ ] State the condition the change now depends on. Here: `names`
      must be sorted.
- [ ] Ask for the smallest thing that would make you comfortable. A
      docstring saying the list must be sorted, and a test with an
      unsorted list that proves the caller's data qualifies.
- [ ] Say what you decided, plainly: approve, approve once the
      docstring lands, or not yet.

> [!important] Review the change, never the author
> "This breaks on an unsorted list" is a review. "You didn't think
> this through" is not, and it makes the next person hide their work
> until it is too late to help them. Everything on this page assumes
> the author was competent and working from information you have not
> got yet — which, in a real team, is nearly always true.

## One variation

Run it backwards. Give the room a bug report and a file, and have
pairs write the diff that fixes it — by hand, in the `-` and `+`
notation. Writing a diff makes you notice how much of a change is
context you did not need to touch.

The mechanics of producing these are in [[Using Version Control]];
the longer version of this conversation, on your own team's code, is
[[The Code Review]].

%%curriculum-start%%
## Curriculum connection

![[A2.3]]

![[B1.7]]
%%curriculum-end%%
