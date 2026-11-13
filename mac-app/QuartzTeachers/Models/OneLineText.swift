import Foundation

/// Text that must stay on one line and read as it is stored: control
/// characters become a space, and the bidirectional controls are removed.
///
/// The rule is `contracts/shared-rules.json` → `courseNameCharacters`, and it
/// works on Unicode SCALARS (code points), never on `Character`s. A
/// `Character` is what a reader sees as one letter, so a line feed after a
/// letter, or a combining mark after a control, would be one `Character`
/// and could not be split from it. Every scalar in the set is in the Basic
/// Multilingual Plane and is not a surrogate, so the Python (`str`) and the
/// Windows app (`char`) see exactly the same thing.
///
/// - C0 controls U+0000 to U+001F (tab, line feed and carriage return
///   included), DEL U+007F, the C1 controls U+0080 to U+009F, and the line
///   and paragraph separators U+2028 and U+2029 each become ONE space. A NUL
///   cuts a label short, a line break splits a trail line in two, and ESC
///   starts a terminal escape sequence.
/// - The bidirectional embeddings, overrides and isolates, U+202A to U+202E
///   and U+2066 to U+2069, are removed. They take up no place in the text,
///   and U+202E makes a name read differently from what is stored.
/// - Everything else is kept, on purpose: the zero-width joiner (emoji need
///   it), the zero-width non-joiner (Persian needs it), the left-to-right,
///   right-to-left and Arabic letter marks, the zero-width space, the soft
///   hyphen, combining marks and every non-breaking space.
///
/// Nothing is trimmed and nothing is collapsed. "Physics" followed by a NUL
/// becomes "Physics " with its space, because the Course Settings field
/// reads and writes the name through this rule on every keystroke, and a
/// rule that trimmed would eat the space a teacher types before "11".
nonisolated enum OneLineText {

    // MARK: - Functions

    /// Whether `scalar` becomes one space.
    static func isSpacedOut(_ scalar: Unicode.Scalar) -> Bool {
        let value: UInt32 = scalar.value
        if value <= 0x1F {
            return true
        }
        if value == 0x7F {
            return true
        }
        if value >= 0x80 && value <= 0x9F {
            return true
        }
        if value == 0x2028 || value == 0x2029 {
            return true
        }
        return false
    }

    /// Whether `scalar` is taken out altogether.
    static func isRemoved(_ scalar: Unicode.Scalar) -> Bool {
        let value: UInt32 = scalar.value
        if value >= 0x202A && value <= 0x202E {
            return true
        }
        if value >= 0x2066 && value <= 0x2069 {
            return true
        }
        return false
    }

    /// `text` with the rule applied.
    ///
    /// `keepingLineBreaks` leaves U+000A alone and cleans everything else.
    /// It is for the one record on the breadcrumb trail that is several lines
    /// on purpose (the assistant's turn: a line for the turn, and a line for
    /// the teacher's sentence behind its marker). A carriage return still
    /// becomes a space there.
    static func cleaned(_ text: String, keepingLineBreaks: Bool = false) -> String {
        var result: String.UnicodeScalarView = String.UnicodeScalarView()
        let space: Unicode.Scalar = " "
        for scalar in text.unicodeScalars {
            if isRemoved(scalar) {
                continue
            }
            if keepingLineBreaks && scalar.value == 0x0A {
                result.append(scalar)
            } else if isSpacedOut(scalar) {
                result.append(space)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }
}

/// A course's name, as every reader of `course_config.json` → `course_name`
/// shows it and every writer stores it (#780).
///
/// One name for the rule at the places that read a course name, so a search
/// for `CourseName.cleaned` finds every one of them; the rule itself is
/// `OneLineText`, which the breadcrumb trail and the unit plans' names use
/// too.
nonisolated enum CourseName {

    // MARK: - Functions

    /// `name` cleaned by `contracts/shared-rules.json` → `courseNameCharacters`.
    static func cleaned(_ name: String) -> String {
        return OneLineText.cleaned(name)
    }
}
