// Fragment 05: arrays
print("Type some whole numbers separated by spaces:")
let line = readLine() ?? ""

var numbers: [Int] = []
for piece in line.split(separator: " ") {
    if let value = Int(piece) {
        numbers.append(value)
    } else {
        print("Skipping \(piece) because it is not a whole number.")
    }
}

print("You entered \(numbers.count) numbers: \(numbers)")

let sortedNumbers = numbers.sorted()
print("Sorted: \(sortedNumbers)")

var total = 0
var largest = numbers[0]
for index in 0..<numbers.count {
    total += numbers[index]
    if numbers[index] > largest {
        largest = numbers[index]
    }
}

var doubled: [Int] = []
for number in numbers {
    doubled.append(number * 2)
}
print("Doubled: \(doubled)")
print("Total: \(total)")
print("Largest: \(largest)")
