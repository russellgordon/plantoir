// Fragment 07: inheritance
class Shape {
    var name: String

    init(name: String) {
        self.name = name
    }

    func area() -> Double {
        return 0
    }

    func describe() -> String {
        return "\(name) with area \(area())"
    }
}

class Circle: Shape {
    var radius: Double

    init(radius: Double) {
        self.radius = radius
        super.init(name: "Circle")
    }

    override func area() -> Double {
        return 3.14159 * radius * radius
    }
}

class Rectangle: Shape {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
        super.init(name: "Rectangle")
    }

    override func area() -> Double {
        return width * height
    }
}

class Square: Rectangle {
    init(side: Double) {
        super.init(width: side, height: side)
        name = "Square"
    }

    override func describe() -> String {
        return super.describe() + " (all sides equal)"
    }
}

print("What is the circle's radius?")
let radius = Double(readLine() ?? "") ?? 1

let shapes: [Shape] = [Circle(radius: radius), Rectangle(width: 2, height: 3), Square(side: 2)]
var totalArea: Double = 0
for shape in shapes {
    print(shape.describe())
    totalArea += shape.area()
}
print("Total area, rounded: \(totalArea.rounded())")
