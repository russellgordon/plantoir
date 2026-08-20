---
title: User Experience, Accessibility, and Inclusive Design
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
A program that works perfectly but cannot be used by its intended audience is a failed program. When we build software, we must deliberately design for **all** users, including those with visual impairments, motor difficulties, or those accessing the tool on older hardware.

Consider the FirstVoices platform, a suite of web and mobile tools designed to support the revitalization of Indigenous languages across BC. The interface must be usable by young digital natives in schools, but also by Elders in remote communities who hold the language knowledge but may have visual impairments or minimal tech experience. 

## Key Principles of Accessibility

Accessibility is often guided by the Web Content Accessibility Guidelines (WCAG), but the core ideas apply to everything from terminal scripts to mobile apps.

- [ ] **High Contrast:** Text must clearly stand out from the background. Light grey text on a white background is invisible to someone with cataracts or someone reading a screen in bright BC summer sunlight.
- [ ] **Keyboard Navigable:** Not everyone can use a mouse. A user with motor tremors must be able to navigate your entire application using only the `Tab`, `Arrow`, and `Enter` keys.
- [ ] **Screen Reader Support:** Users with severe vision impairment use software that reads the screen out loud. Interfaces must have clear, semantic text labels, not just icons. A button labelled `[ X ]` should actually say "Close" in the underlying code.
- [ ] **Plain Language:** Use clear, direct language. Avoid unnecessary jargon, complex idioms, or aggressive error messages. "Invalid input" is worse than "Please enter a number between 1 and 10."

## Inclusive Terminal Design

Even in a text-based Python program, accessibility matters. How you ask for input dictates who can use your software.

### Poor Design

```python
# Unclear prompt, no error handling, aggressive failure
x = input("> ")
num = int(x)
print(100 / num)
```

This crashes if the user types a letter or a zero. It offers no guidance on what is expected.

### Inclusive Design

```python
# Clear instructions, graceful recovery, readable spacing
print("Welcome to the Community Air Quality Health Index calculator.")
print("-------------------------------------------------------------")

while True:
    print("\nPlease enter the current PM2.5 reading (e.g., 12.5).")
    print("Or type 'quit' to exit.")
    
    user_input = input("Reading: ").strip().lower()
    
    if user_input == 'quit':
        break
        
    try:
        reading = float(user_input)
        if reading < 0:
            print("Notice: Readings cannot be negative. Please try again.")
            continue
            
        print(f"Thank you. The reading {reading} has been recorded.")
        break
        
    except ValueError:
        print("Notice: That didn't look like a number. Please try again.")
```

This version provides context, handles mistakes gently without crashing, and clearly explains how to exit. Inclusive design is simply good design.

%%curriculum-start%%
## Curriculum connection

![[D2.2]]

![[K1.17]]
%%curriculum-end%%
