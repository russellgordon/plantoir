import Foundation

/// A launcher's report that this working folder's workspace WAS made again,
/// and why (GitHub #684), read from its `PLANTOIR_FOLDER_SET_UP_AGAIN:` line
/// so the app can write the trail line — in the same two places, for the same
/// reason, as `WorkspaceInUseReport`: `ScriptRunner` from a run it started,
/// and `ScheduledDeploy` from the log of a publish launchd ran.
///
/// A remake throws away the warm website builder, so the next preview takes
/// about two minutes instead of seconds, and "why was my first preview this
/// morning so slow?" is asked days later. Until #684 only a WAIT before a
/// remake reached the trail, so the commonest remake of all — after an
/// update — left nothing.
///
/// The words are `contracts/shared-rules.json` → `activityTrail.mustRecord.
/// "folder set up again"`. The launcher prints only a reason word and a
/// place; a reason this app has no words for writes the line without one,
/// never a wrong one.
struct FolderSetUpAgainReport: Equatable {

    // MARK: - Stored properties

    /// The marker the launchers print. Pinned by the contract's `marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_FOLDER_SET_UP_AGAIN:"

    /// The trail line, pinned by the contract's `line`.
    nonisolated static let line: String = "{place} · set this folder up again — {why}"

    /// The trail line for a reason with no words, pinned by `lineWithoutAReason`.
    nonisolated static let lineWithoutAReason: String = "{place} · set this folder up again"

    /// Why, by the word the launcher prints. Pinned by the contract's `whyWords`.
    nonisolated static let whyWords: [String: String] = [
        "update": "Plantoir had been updated",
        "thisMacOnly": "its previews could be opened from other computers on the network",
        "severalPreviews": "it could show only one preview at a time",
        "buildsOutside": "built websites are now kept outside the course folder",
        "coursesNotFound": "the website builder could not find the courses",
        "otherFolder": "it had been set up for a folder somewhere else",
        "coursesJustMade": "'courses/' had just been created",
        "couldNotSave": "the website builder could not save into 'courses/'",
        "lostConnection": "Plantoir had lost its connection to the website builder",
        "addressTaken": "something else was using its preview addresses",
    ]

    /// The reason word the launcher printed, such as `update`.
    let reason: String

    /// Where the run was for: `COURSE/SECTION` (a space written `+`), or `setup`.
    let place: String

    // MARK: - Computed properties

    /// The trail line for this report.
    nonisolated var trailSentence: String {
        let readablePlace: String = place.replacingOccurrences(of: "+", with: " ")
        guard let why = FolderSetUpAgainReport.whyWords[reason] else {
            return FolderSetUpAgainReport.lineWithoutAReason.replacingOccurrences(of: "{place}", with: readablePlace)
        }
        var sentence: String = FolderSetUpAgainReport.line.replacingOccurrences(of: "{place}", with: readablePlace)
        sentence = sentence.replacingOccurrences(of: "{why}", with: why)
        return sentence
    }

    // MARK: - Functions

    /// Every report in a stretch of output. A line that does not have the
    /// marker's shape — two words, a reason made of letters and a place —
    /// reports nothing, so a path or a command can never reach the trail.
    nonisolated static func reports(in text: String) -> [FolderSetUpAgainReport] {
        var found: [FolderSetUpAgainReport] = []
        for textLine in SiteHealthFinding.linesOf(text) {
            // From the prefix onward, so a marker glued to the tail of
            // somebody else's half line is still read (#153).
            guard let prefixRange = textLine.range(of: markerPrefix) else {
                continue
            }
            var words: [String] = []
            for word in textLine[prefixRange.upperBound...].split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard words.count == 2,
                  isAReason(words[0]),
                  LeftoverWorkReport.isAPlace(words[1]) else {
                continue
            }
            found.append(FolderSetUpAgainReport(reason: words[0], place: words[1]))
        }
        return found
    }

    /// Notes every report in a stretch of output on the activity trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(.folderSetUpAgain, report.trailSentence)
        }
    }

    /// One word of ASCII letters, at most 32 of them.
    nonisolated static func isAReason(_ word: String) -> Bool {
        if word.isEmpty || word.count > 32 {
            return false
        }
        for character in word.unicodeScalars {
            let isLetter: Bool = (character.value >= 65 && character.value <= 90)
                || (character.value >= 97 && character.value <= 122)
            if !isLetter {
                return false
            }
        }
        return true
    }
}
