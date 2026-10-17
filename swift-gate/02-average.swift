// Fragment 02: average
print("Type your test marks, one per line. Press Return on an empty line to finish.")

var total: Double = 0
var count: Int = 0

while let line = readLine() {
    if line.isEmpty {
        break
    }
    guard let mark = Double(line) else {
        print("\(line) is not a number, so it was skipped.")
        continue
    }
    total += mark
    count += 1
}

if count == 0 {
    print("No marks were entered.")
} else {
    let average = total / Double(count)
    print("You entered \(count) marks.")
    print("Your average is \(average).")
    if average >= 80 {
        print("That is level 4. Well done!")
    } else if average >= 70 {
        print("That is level 3.")
    } else {
        print("Keep practising.")
    }
}
