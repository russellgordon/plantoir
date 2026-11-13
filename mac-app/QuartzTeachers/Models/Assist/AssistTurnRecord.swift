import Foundation

/// One turn of the assistant, in a form that can be read months later.
///
/// This exists because **routing is the one part of this product with no
/// automated gate at all**. Whether the model still picks the right tool is
/// measured by hand against a local engine; once the app is on a teacher's
/// machine, nothing measures it. A record of what was asked for and what was
/// chosen is the only way a routing mistake in the field ever becomes
/// something anybody can look at.
///
/// What it deliberately does NOT keep is the tool's argument VALUES. A page
/// title is the teacher's work, and knowing that `publish_pages` was called
/// with a `titles` argument answers the routing question completely — which
/// tool, with which arguments filled in — without carrying their content.
nonisolated struct AssistTurnRecord {

    // MARK: - Stored properties

    let at: Date
    let courseCode: String
    let sectionNumber: Int

    /// The tool the model chose, or nil when it answered in words.
    let toolName: String?

    /// The NAMES of the arguments it filled in, never their values.
    let argumentNames: [String]

    /// How long the model took to answer.
    let seconds: TimeInterval

    /// How many tokens it wrote, when the engine said.
    ///
    /// The number worth watching. Thinking being switched back on does not
    /// change what a reply LOOKS like — the engine strips the thinking out
    /// of the content — it changes how long the reply took and how many
    /// tokens it took to get there.
    let completionTokens: Int?

    /// Whether the turn stopped at the approval gate instead of running.
    let stoppedAtGate: Bool

    /// What marks the line carrying the teacher's own words, so that leaving
    /// it out of a report is a matter of dropping lines with this prefix
    /// rather than of parsing anything.
    static let promptMarker: String = "  asked: "

    // MARK: - Computed properties

    /// The record as it is written: one line for the turn, and one for the
    /// sentence behind it.
    var lines: String {
        var parts: [String] = []
        parts.append(AssistTurnRecord.formatter().string(from: at))
        parts.append("\(courseCode)/\(sectionNumber)")
        if let toolName {
            parts.append("chose \(toolName)(\(argumentNames.joined(separator: ", ")))")
        } else {
            parts.append("answered in words")
        }
        parts.append(String(format: "%.1fs", seconds))
        if let completionTokens {
            parts.append("\(completionTokens) tokens")
        }
        if stoppedAtGate {
            parts.append("waited for the button")
        }
        // One line whatever the model wrote (#780): the argument names come
        // from the model's own JSON, and this record is written with its line
        // breaks kept, so a name holding one would otherwise start a line.
        return OneLineText.cleaned(parts.joined(separator: " · "))
    }

    // MARK: - Functions

    /// What the teacher typed, recorded the moment they SEND it.
    ///
    /// Written when the message goes, not when an answer comes back. A model
    /// call that fails, or one still running when the teacher gives up and
    /// closes the window, would otherwise leave no trace of the sentence that
    /// caused the problem — which is the one thing a routing report cannot be
    /// read without.
    ///
    /// It is kept locally and withheld from a report unless the teacher ticks
    /// the box, because their own words are the one thing here unmistakably
    /// theirs to hand over or not.
    ///
    /// The sentence is put on ONE line first (#780). The assistant's field
    /// grows to several lines (`axis: .vertical`), so a sentence can hold a
    /// line break, pasted or typed, and this record is written with its line
    /// breaks kept. A sentence on two lines used to put its second line on
    /// the trail with no marker in front of it, where leaving the prompts out
    /// of a report could not see it. `courseNameCharacters.trailLines`.
    static func askedLines(
        prompt: String,
        courseCode: String,
        sectionNumber: Int,
        at moment: Date,
        timeZone: TimeZone = TimeZone.current
    ) -> String {
        return AssistTurnRecord.formatter(timeZone: timeZone).string(from: moment)
            + " · \(courseCode)/\(sectionNumber) · asked the local AI assistant\n"
            + AssistTurnRecord.promptMarker + OneLineText.cleaned(prompt)
    }

    static func formatter(timeZone: TimeZone = TimeZone.current) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    /// The argument names of a call, in a stable order so that two records of
    /// the same routing decision read the same.
    static func argumentNames(inJSON json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var names: [String] = []
        for (name, _) in object {
            names.append(name)
        }
        names.sort()
        return names
    }
}
