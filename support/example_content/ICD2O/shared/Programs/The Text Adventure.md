---
title: The Text Adventure
publish: true
created: __CREATED__
tags:
  - programs
---
Two rooms, one key, one locked door — the biggest program in the
folder, where a subprogram, a game loop, nested conditionals, and all
four moves of [[Computational Thinking]] finally meet. This page is
also the official launchpad for [[The Remix Project]].

## The program

```python
def describe(room, has_key):
    if room == "hall":
        print("You are in a dusty hall. A locked door leads north.")
        if not has_key:
            print("A brass key glints on the floor.")
    else:
        print("The vault! Shelves of gold. The exit is south.")

room = "hall"
has_key = False

print("=== THE TWO-ROOM ADVENTURE ===")
print("Commands: take, north, south, quit")

command = ""
while command != "quit":
    describe(room, has_key)
    command = input("> ")
    if command == "take" and room == "hall" and not has_key:
        has_key = True
        print("You pocket the key.")
    elif command == "north" and room == "hall" and has_key:
        room = "vault"
        print("The key turns. The door swings open.")
    elif command == "north" and room == "hall":
        print("The door is locked. Something glints nearby...")
    elif command == "south" and room == "vault":
        room = "hall"
        print("Back to the dust.")
    elif command != "quit":
        print("You cannot do that here.")

print("Thanks for playing. Now remix it.")
```

## Read it before you run it

Predict in writing first — then run the program and grade yourself.

- The entire world lives in `room` and `has_key`. Trace both values
  through the commands `take`, `north`, `south` — in that order.
- Two branches both begin `command == "north" and room == "hall"`.
  Why must the `has_key` one come first — what breaks if they swap?
- Type `take` twice. Which part of which condition quietly refuses
  the second attempt?

## Make it yours

1. **One line.** Put something better than gold in the vault.
2. **A few lines.** Add a secret `xyzzy` command with its own reply.
3. **A real change.** Add a third room past the vault, with something
   worth finding in it — and [[The Remix Project]] has already begun.

%%curriculum-start%%
## Curriculum connection

![[C1.4]]

![[C3.1]]

![[C3.2]]
%%curriculum-end%%
