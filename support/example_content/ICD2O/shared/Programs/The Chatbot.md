---
title: The Chatbot
publish: true
created: __CREATED__
tags:
  - programs
---
A program that appears to hold a conversation — and is doing nothing
of the kind. It hunts for keywords and serves canned replies from two
tidy [[Subprograms and Modules|subprograms]]. This is **not** AI:
there is no understanding anywhere in these 21 lines, which is exactly
what makes it worth reading — see
[[Automation and Artificial Intelligence]] for where the real thing
differs, and [[Talk to the Machine]] for the class version of this game.

## The program

```python
def mentions(message, keyword):
    return keyword in message

def reply_to(message):
    if mentions(message, "homework"):
        return "Homework? I only know about sandwiches."
    elif mentions(message, "hello") or mentions(message, "hi"):
        return "Hello! Ask me anything. I know one thing."
    elif mentions(message, "sandwich"):
        return "Now we are talking. Peanut butter, obviously."
    elif mentions(message, "bye"):
        return "Goodbye! I will forget this instantly."
    else:
        return "Hmm. Try 'hello', 'sandwich', or 'homework'."

print("CHATTERBOT 1.0 - type 'bye' to leave")

message = ""
while not mentions(message, "bye"):
    message = input("You: ").lower()
    print("Bot:", reply_to(message))
```

## Read it before you run it

Predict in writing first — then run the program and grade yourself.

- What does the bot say to `I love HOMEWORK`? Follow the `.lower()`.
- Type `this is fun` and the bot says hello. Find the accidental `hi`
  — and say what that reveals about keyword matching.
- Trace exactly how typing `goodbye` ends the program. `mentions` is
  called in two different places — which one closes the loop?

## Make it yours

1. **One line.** Rewrite any one reply in your own voice.
2. **A few lines.** Teach it a new keyword: one `elif`, one `return`.
3. **A real change.** Ask for the user's name before the loop and
   weave it into every reply. Watch how much *warmer* the bot feels —
   while understanding precisely as little as before.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[C3.1]]

![[C3.3]]
%%curriculum-end%%
