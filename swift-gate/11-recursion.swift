// Fragment 11: recursion that never stops
func countUp(_ n: Int) -> Int {
    if n < 0 {
        return 0
    }
    return countUp(n + 1) + 1
}

print("Counting up for ever...")
print(countUp(0))
print("This line is never reached.")
