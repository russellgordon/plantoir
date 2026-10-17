// Fragment 10: out of range
let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

print("Which school day do you want (0 to 4)?")
let choice = Int(readLine() ?? "") ?? 0
print("You asked for day \(choice).")
print("That day is \(days[choice]).")
print("This line is never reached.")
