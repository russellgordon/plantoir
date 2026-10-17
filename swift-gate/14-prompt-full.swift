// Fragment 14: a prompt on the same line, in a program Embedded Swift cannot print
print("Type three words: ", terminator: "")
let words = (readLine() ?? "").split(separator: " ")
print("You typed \(words.count) words: \(words)")
