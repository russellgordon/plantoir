// Fragment 01: greeting
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
