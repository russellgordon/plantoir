// The editor's colours (#585): Swift beyond the example content.
// Scored against the image's Shiki by scripts/check_runner_rules_against_the_site.py.

import Foundation

// A struct with a computed property
struct Point: Equatable {
    var x: Double
    var y: Double
    let label: String = "P"

    var length: Double {
        return (x * x + y * y).squareRoot()
    }

    mutating func scale(by factor: Double) {
        x *= factor
        y *= factor
    }
}

/* A block comment
   over two lines */
enum Direction: String, CaseIterable {
    case north, south
    case east = "E"
}

class Animal {
    private(set) var name: String
    weak var friend: Animal?
    init(name: String) { self.name = name }
    func speak() -> String { "..." }
}

final class Dog: Animal {
    override func speak() -> String {
        return "Woof from \(name), \(name.count) letters"
    }
}

@discardableResult
func greet(_ person: String, times: Int = 2) throws -> [String] {
    guard times > 0 else { throw NSError(domain: "x", code: 1) }
    var lines: [String] = []
    for i in 0..<times where i % 2 == 0 {
        lines.append("Hello, \(person)! #\(i + 1)")
    }
    let message = """
        Multi-line "string"
        with \(times) lines
        """
    print(message)
    let hex = 0xFF, bin = 0b1010, big = 1_000_000, f = 3.14e-2
    print(hex, bin, big, f, true, false, nil as Int?)
    let doubled = lines.map { line in line + line }
    if let first = doubled.first, !first.isEmpty {
        print(first)
    }
    switch times {
    case 1...3: print("few")
    default: break
    }
    return lines
}

while let line = readLine() {
    let numbers = line.split(separator: " ").compactMap { Int($0) }
    print(numbers.reduce(0, +))
}
let raw = #"a raw "string" \n"#
var dict: [String: Int] = ["a": 1]
dict["b", default: 0] += 1
repeat { break } while false
defer { print("bye") }

let name = "Ann"
print("Hello, \(name)! You are \(age + 1) and \(f("x"))")
let s = "tab\tnew\n quote \" uni \u{1F600}"

let poem = """
    Roses are \(colour)
    "quoted" text
    """
let after = 1

@main
struct App {
    @State private var count = 0
    @discardableResult
    func go() -> Int { return 1 }
}
@available(iOS 17, *)
func f() {}

import Foundation
guard let x = y else { return }
for i in 0..<10 where i % 2 == 0 { continue }
switch v {
case .a, .b: break
default: fallthrough
}
let c = { (a: Int) -> Int in a * 2 }
let d = nums.map { $0 * 2 }
var opt: Int? = nil
if case let .some(v) = opt { print(v) }
do { try f() } catch { print(error) }
let k = \Person.name
#if DEBUG
print(#line)
#endif

let a = 1_000_000
let b = 0xFF
let c = 3.14e-2
let d = 0b1010
let e = 0o17
let f = -5
let g = 1.5

class Dog: Animal, CustomStringConvertible {
    init(name: String) { self.name = name; super.init() }
    var description: String { "Dog" }
    static func make<T: Equatable>(_ x: T) -> [T] { [x] }
}
enum Suit: String, CaseIterable { case hearts }
protocol P { associatedtype Item }
extension Int { func sq() -> Int { self * self } }

// line comment TODO
/* block /* nested */ still */
let x = 1 /// doc
/// - Parameter a: thing

import Foundation
enum Direction { case north, south }
let d: Direction = .north
let n = nums.count + nums.first! + s.isEmpty.description
func greet(_ name: String, from place: String = "here") -> String { return "hi" }
greet("A", from: "B")
let xs = [1, 2, 3].map { x in x * 2 }.filter { $0 > 2 }
struct P<T: Equatable> where T: Hashable { let v: T }
var dict: [String: Int] = [:]
let o: Int? = nil ?? 3
for (i, v) in xs.enumerated() { print(i, v, terminator: "") }
x += -5 &+ 2
let big = Int.max
override init() { super.init() }
let s = "a\tb\u{1F600}\(x)"
let r = try? JSONDecoder().decode(T.self, from: data)
if #available(iOS 17, *) { }
let tuple = (a: 1, b: 2)
print(tuple.a, tuple.0)

let y = a > 0 ? "pos" : "neg"
let _ = f()
for _ in 1...3 { }
guard let n = Int(readLine()!) else { fatalError("bad") }
typealias Score = Int
protocol Shape { func area() -> Double; var name: String { get } }
struct S { private(set) var v = 0; mutating func bump() { v += 1 } }
var total: Int = 0 { willSet { print(newValue) } didSet { } }
func swap2(_ a: inout Int, _ b: inout Int) throws -> Bool { true }
let d = ["a": 1, "b": 2]
switch x {
case 1...5: print("low")
case let n where n > 5: print(n)
default: break
}
if let x = y, x > 0 { }
let c = a?.b?.count ?? 0
let i = v as? Int; let j = v as! Int; let k = v is Int
let arr = Array<Int>(); let arr2 = [Int]()
print("\(a) and \(b.count)", terminator: "")
let sorted1 = names.sorted { $0 < $1 }
let sorted2 = names.sorted(by: <)
for i in stride(from: 0, to: 10, by: 2) { }
repeat { n -= 1 } while n > 0
defer { cleanup() }
outer: for i in 0..<3 { break outer }
let ch: Character = "a"
let up = name.uppercased().lowercased()
let count = items.count
var names = [String]()
names.append("x"); names.insert("y", at: 0); names.remove(at: 0)
let m = max(1, 2); let mn = min(a, b); let ab = abs(-3)
let e = Double(n) / 2.0
let t = String(repeating: "-", count: 5)
class Animal { var name: String; init(name: String) { self.name = name } }
class Dog: Animal { override func speak() -> String { "Woof" } }
let s2 = """
  Hi \(name)
  """
let pt = CGPoint(x: 1, y: 2)
let r = 1...10
let doubled = nums.map { (n: Int) -> Int in n * 2 }
let isEven = n % 2 == 0 && !flag || other
print(nums[0], nums[1...])
