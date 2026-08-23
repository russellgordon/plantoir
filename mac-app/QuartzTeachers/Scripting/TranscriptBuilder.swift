import Foundation

/// Turns raw terminal output into clean display lines.
///
/// The scripts produce terminal control sequences (colours, spinners that
/// redraw the same line with carriage returns, cursor movement). Teachers
/// should see tidy text, so this type strips ANSI escape sequences and
/// treats a carriage return as "start this line over", which collapses
/// spinner animation into its final state.
/// Holds the joined transcript text so reading it mutates nothing.
final class TranscriptTextCache {

    // MARK: - Stored properties

    var text: String?
}

struct TranscriptBuilder {

    // MARK: - Stored properties

    /// Completed lines of output, oldest first.
    var lines: [String] = []

    /// The line currently being assembled (not yet ended with a newline).
    var currentLine: String = ""

    /// True when the previous chunk ended with a carriage return whose
    /// meaning (line ending vs. spinner redraw) depends on what follows.
    var hasPendingCarriageReturn: Bool = false

    /// The most recent lines are all a teacher ever reads, and keeping
    /// every line of a long publish would grow without bound.
    static let maximumRetainedLines: Int = 4000

    /// Cached joined text: `displayText` is read several times per
    /// refresh, and rebuilding it each time is what stalls the UI.
    ///
    /// The cache lives in a REFERENCE box so that reading `displayText`
    /// mutates nothing. This transcript is stored on an observed object
    /// and read from view bodies: a mutating getter would write to
    /// observed state during view evaluation, invalidating the view,
    /// which re-reads, which writes again — an endless loop that freezes
    /// the interface. `append` swaps in a fresh box, so copies of this
    /// struct never share a stale cache.
    private var cache: TranscriptTextCache = TranscriptTextCache()

    // MARK: - Computed properties

    /// The full transcript as one display string (cached).
    var displayText: String {
        if let text = cache.text {
            return text
        }
        var allLines: [String] = lines
        if !currentLine.isEmpty {
            allLines.append(currentLine)
        }
        let text: String = allLines.joined(separator: "\n")
        cache.text = text
        return text
    }

    // MARK: - Functions

    /// The tail of the transcript, without joining every line.
    func recentText(maximumCharacters: Int) -> String {
        var collected: [String] = []
        var characterCount: Int = 0
        if !currentLine.isEmpty {
            collected.append(currentLine)
            characterCount += currentLine.count
        }
        var index: Int = lines.count - 1
        while index >= 0 && characterCount < maximumCharacters {
            let line: String = lines[index]
            collected.append(line)
            characterCount += line.count + 1
            index -= 1
        }
        return collected.reversed().joined(separator: "\n")
    }

    /// Feed a chunk of raw output from the PTY into the transcript.
    ///
    /// A pseudo-terminal turns every "\n" the script prints into "\r\n",
    /// so a carriage return followed by a newline is an ordinary line
    /// ending. Only a LONE carriage return is a spinner redrawing its
    /// line, which is when the current line restarts.
    mutating func append(rawText: String) {
        // A fresh box per mutation: copies of this struct must never
        // share a cache that one of them later fills in.
        cache = TranscriptTextCache()
        let cleaned: String = TranscriptBuilder.strippingControlSequences(from: rawText)
        // Work scalar-by-scalar: Swift groups "\r\n" into a SINGLE
        // Character (grapheme cluster), which would hide line endings.
        let newlineScalar: Unicode.Scalar = "\n"
        let carriageReturnScalar: Unicode.Scalar = "\r"
        for scalar in cleaned.unicodeScalars {
            if hasPendingCarriageReturn {
                hasPendingCarriageReturn = false
                if scalar == newlineScalar {
                    // "\r\n": a normal line ending.
                    lines.append(currentLine)
                    currentLine = ""
                    continue
                }
                // A lone "\r": spinner redraw — restart the line, then
                // process the current scalar normally below.
                currentLine = ""
            }
            if scalar == newlineScalar {
                // The machine-readable health lines are dropped here rather
                // than shown. Rule 1: the interface never names the machinery,
                // and a raw JSON blob is machinery. Nothing is lost — the
                // toolchain prints the teacher-facing sentence separately, and
                // `ScriptRunner.receiveOutput` reads the raw text for findings
                // BEFORE handing it here, precisely so this can drop them.
                if !SiteHealthFinding.isMarkerLine(currentLine) {
                    lines.append(currentLine)
                }
                currentLine = ""
                if lines.count > TranscriptBuilder.maximumRetainedLines {
                    lines.removeFirst(lines.count - TranscriptBuilder.maximumRetainedLines)
                }
            } else if scalar == carriageReturnScalar {
                hasPendingCarriageReturn = true
            } else {
                currentLine.unicodeScalars.append(scalar)
            }
        }
    }

    /// Removes ANSI escape sequences and stray control characters,
    /// keeping newlines, carriage returns, and tabs.
    ///
    /// Operates on Unicode scalars, not Characters, because Swift folds
    /// "\r\n" into one Character and would misclassify it as a control
    /// character to remove.
    static func strippingControlSequences(from text: String) -> String {
        var result: String = ""
        let scalars: [Unicode.Scalar] = Array(text.unicodeScalars)
        let escapeScalar: Unicode.Scalar = "\u{1B}"
        let bellScalar: Unicode.Scalar = "\u{07}"
        var index: Int = 0
        while index < scalars.count {
            let scalar: Unicode.Scalar = scalars[index]
            if scalar == escapeScalar {
                // Escape sequence: skip "ESC [ ... final-letter" (CSI) or
                // "ESC ] ... BEL" (OSC), or a single following scalar.
                let nextIndex: Int = index + 1
                if nextIndex < scalars.count && scalars[nextIndex] == "[" {
                    var scanIndex: Int = nextIndex + 1
                    while scanIndex < scalars.count {
                        let scanned: Unicode.Scalar = scalars[scanIndex]
                        let isFinalLetter: Bool = (scanned >= "A" && scanned <= "Z") || (scanned >= "a" && scanned <= "z")
                        if isFinalLetter {
                            break
                        }
                        scanIndex += 1
                    }
                    index = scanIndex + 1
                    continue
                }
                if nextIndex < scalars.count && scalars[nextIndex] == "]" {
                    var scanIndex: Int = nextIndex + 1
                    while scanIndex < scalars.count {
                        let scanned: Unicode.Scalar = scalars[scanIndex]
                        if scanned == bellScalar {
                            break
                        }
                        scanIndex += 1
                    }
                    index = scanIndex + 1
                    continue
                }
                index = index + 2
                continue
            }
            let isControl: Bool = scalar.value < 32
            let isKeeper: Bool = scalar == "\n" || scalar == "\r" || scalar == "\t"
            if isControl && !isKeeper {
                index += 1
                continue
            }
            result.unicodeScalars.append(scalar)
            index += 1
        }
        return result
    }
}
