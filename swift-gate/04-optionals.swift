// Fragment 04: optionals
let lockerNumbers: [String: Int] = ["Amara": 214, "Ben": 118, "Chloé": 305]

func describe(locker: Int?) -> String {
    guard let number = locker else {
        return "has no locker yet"
    }
    return "has locker \(number)"
}

print("Whose locker do you want to find?")
let name = readLine() ?? ""

if let number = lockerNumbers[name] {
    print("\(name)'s locker is number \(number).")
} else {
    print("There is no locker for \(name).")
}

let fallback = lockerNumbers["Dev"] ?? 0
print("Dev's locker, or 0 if there is none: \(fallback)")

print("Chloé \(describe(locker: lockerNumbers["Chloé"])).")
print("Dev \(describe(locker: lockerNumbers["Dev"])).")
