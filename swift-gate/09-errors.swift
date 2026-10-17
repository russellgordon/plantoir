// Fragment 09: errors
enum TicketError: Error {
    case tooYoung(age: Int)
    case soldOut
    case notANumber(text: String)
}

var ticketsLeft = 2

func buyTicket(ageText: String) throws -> Int {
    guard let age = Int(ageText) else {
        throw TicketError.notANumber(text: ageText)
    }
    guard age >= 13 else {
        throw TicketError.tooYoung(age: age)
    }
    guard ticketsLeft > 0 else {
        throw TicketError.soldOut
    }
    ticketsLeft -= 1
    return 100 + ticketsLeft
}

print("Type the age of each person buying a ticket:")
while let line = readLine() {
    do {
        let seat = try buyTicket(ageText: line)
        print("Ticket bought: seat \(seat).")
    } catch TicketError.tooYoung(let age) {
        print("Sorry, \(age) is too young for this film.")
    } catch TicketError.soldOut {
        print("Sorry, the film is sold out.")
    } catch {
        print("Something went wrong: \(error)")
    }
}
