// Fragment 15: a whole number too big for Int, which is 32 bits here
var factorial = 1
for n in 1...15 {
    factorial = factorial * n
    print("\(n)! = \(factorial)")
}
print("This line is never reached.")
