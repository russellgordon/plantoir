// Fragment 12: a list that grows for ever
var numbers: [Int] = []
var next = 0
print("Adding numbers to a list for ever...")
while true {
    numbers.append(next)
    next += 1
}
