---
title: Reading Input in Swift
publish: true
codeRunner: true
tags:
  - programs
---
Last year's programs read their input in Python. Swift reads a line the
same way, with one difference worth meeting early: `readLine()` might give
back nothing at all, so Swift makes you say what to do then.

## Ask, then answer

Type your name and your age on two lines of the input box under the
program, then press **Run**.

```swift run
print("What is your name?")
let name = readLine() ?? ""
print("How old are you?")
let ageText = readLine() ?? ""

if let age = Int(ageText) {
    print("Hello, \(name)! Next year you will be \(age + 1).")
} else {
    print("Hello, \(name)! \"\(ageText)\" is not a whole number.")
}
```

Then try it with an age written as a word. Which line of the program
decides what happens?

## What to notice

- `readLine() ?? ""` turns "nothing at all" into an empty string, so the
  rest of the program only ever deals with text.
- `Int(ageText)` might fail, so it gives back an optional; `if let` runs
  its block only when the text really was a whole number.
