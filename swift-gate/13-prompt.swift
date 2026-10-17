// Fragment 13: a prompt on the same line as the answer
print("What is your name? ", terminator: "")
let name = readLine() ?? ""
print("Nice to meet you, \(name).")
print("How many pets do you have? ", terminator: "")
let pets = Int(readLine() ?? "") ?? 0
if pets == 1 {
    print("One pet. Lovely!")
} else {
    print("\(pets) pets. Lovely!")
}
