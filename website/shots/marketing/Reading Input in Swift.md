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

if name.isEmpty {
    print("You didn't type a name, so I'll call you Friend.")
} else {
    print("Hello, \(name)! Your name has \(name.count) letters.")
}

print("How old are you?")
let ageText = readLine() ?? ""

if let age = Int(ageText) {
    let nextYear = age + 1
    print("Next year you will be \(nextYear).")
    if age >= 16 {
        print("You are old enough to drive in Ontario.")
    } else {
        let yearsToWait = 16 - age
        print("You can learn to drive in \(yearsToWait) years.")
    }
} else {
    print("\"\(ageText)\" is not a whole number.")
}
```

Then try it with no name, and with an age written as a word. Which line
of the program decides what happens each time?

## What to notice

- `readLine() ?? ""` turns "nothing at all" into an empty string, so the
  rest of the program only ever deals with text.
- `Int(ageText)` might fail, so it gives back an optional; `if let` runs
  its block only when the text really was a whole number.
