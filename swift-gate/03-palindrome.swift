// Fragment 03: palindrome
print("Type a word or a phrase:")
let phrase = readLine() ?? ""

var letters: [Character] = []
for character in phrase.lowercased() {
    if character.isLetter {
        letters.append(character)
    }
}

let backwards = Array(letters.reversed())
if letters == backwards {
    print("\"\(phrase)\" is a palindrome.")
} else {
    print("\"\(phrase)\" is not a palindrome.")
}

if phrase.lowercased().contains("a") {
    print("It contains the letter a.")
}

if phrase.lowercased().contains("canal") {
    print("It mentions a canal.")
}

print("In capitals: \(phrase.uppercased())")

if phrase.hasPrefix("A") {
    print("It starts with a capital A.")
}
