// Fragment 08: enum
enum Command {
    case move(steps: Int)
    case turn(direction: String)
    case say(message: String)
    case unknown(text: String)
}

func read(_ line: String) -> Command {
    let parts = line.split(separator: " ", maxSplits: 1)
    if parts.isEmpty {
        return .unknown(text: line)
    }
    let word = String(parts[0])
    let rest = parts.count > 1 ? String(parts[1]) : ""
    switch word {
    case "move":
        if let steps = Int(rest) {
            return .move(steps: steps)
        }
        return .unknown(text: line)
    case "turn":
        return .turn(direction: rest)
    case "say":
        return .say(message: rest)
    default:
        return .unknown(text: line)
    }
}

print("Type commands for the robot, one per line:")
var position = 0
while let line = readLine() {
    switch read(line) {
    case .move(let steps):
        position += steps
        print("Moved \(steps) steps. Now at \(position).")
    case .turn(let direction):
        print("Turned \(direction).")
    case .say(let message):
        print("The robot says: \(message)")
    case .unknown(let text):
        print("I don't understand \"\(text)\".")
    }
}
print("Finished at position \(position).")
