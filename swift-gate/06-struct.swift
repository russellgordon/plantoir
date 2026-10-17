// Fragment 06: struct
struct Rectangle {
    var width: Double
    var height: Double

    var area: Double {
        return width * height
    }

    var perimeter: Double {
        return 2 * (width + height)
    }

    mutating func scale(by factor: Double) {
        width *= factor
        height *= factor
    }
}

print("How wide is the rectangle?")
let width = Double(readLine() ?? "") ?? 1
print("How tall is it?")
let height = Double(readLine() ?? "") ?? 1

var original = Rectangle(width: width, height: height)
var copy = original
copy.scale(by: 2)

print("Original: \(original.width) by \(original.height), area \(original.area), perimeter \(original.perimeter)")
print("Copy: \(copy.width) by \(copy.height), area \(copy.area), perimeter \(copy.perimeter)")
original.width = 10
print("After changing the original, the copy is still \(copy.width) wide.")
