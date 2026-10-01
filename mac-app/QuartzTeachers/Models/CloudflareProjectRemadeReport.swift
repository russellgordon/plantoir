import Foundation

/// A section's Cloudflare project that was made again because it was not in
/// the Cloudflare account any more (2026-09-30), read from the shared
/// `deploy.py`'s `PLANTOIR_CLOUDFLARE_REMADE:` line so the app can write the
/// trail's `cloudflare project made again` line.
///
/// Why it is on the trail, and why the marker rather than a line written by
/// the script itself: `contracts/shared-rules.json` → `activityTrail.mustRecord
/// ."cloudflare project made again"`. In short, the address can change and a
/// custom domain went with the deleted project, and `deploy.py` runs inside the
/// website builder, where the trail cannot be reached.
struct CloudflareProjectRemadeReport: Equatable {

    // MARK: - Stored properties

    /// The marker `deploy.py` prints. Pinned by the contract's `marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_CLOUDFLARE_REMADE:"

    /// The trail line, pinned by the contract's `line`.
    nonisolated static let line: String =
        "{place} · the Cloudflare project {project} was not in this Cloudflare account, so it was made again; the website is now at {address}"

    /// `COURSE/SECTION`, with the course's one permitted space written "+".
    let place: String

    /// The project's name, as Cloudflare knows it.
    let project: String

    /// The address the website answers at now, a host name.
    let address: String

    // MARK: - Computed properties

    /// The trail line for this report.
    nonisolated var trailSentence: String {
        var sentence: String = CloudflareProjectRemadeReport.line.replacingOccurrences(
            of: "{place}", with: place.replacingOccurrences(of: "+", with: " ")
        )
        sentence = sentence.replacingOccurrences(of: "{project}", with: project)
        sentence = sentence.replacingOccurrences(of: "{address}", with: address)
        return sentence
    }

    // MARK: - Functions

    /// Every report in a stretch of output. A line that is not exactly the
    /// marker's shape reports nothing, so a path or a command can never reach
    /// the trail.
    nonisolated static func reports(in text: String) -> [CloudflareProjectRemadeReport] {
        var found: [CloudflareProjectRemadeReport] = []
        for textLine in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = textLine.range(of: markerPrefix) else {
                continue
            }
            var words: [String] = []
            for word in textLine[prefixRange.upperBound...].split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard words.count == 3 else {
                continue
            }
            guard LeftoverWorkReport.isAPlace(words[0]), words[0] != "setup" else {
                continue
            }
            guard isAName(words[1], allowingDots: false), isAName(words[2], allowingDots: true) else {
                continue
            }
            let report: CloudflareProjectRemadeReport = CloudflareProjectRemadeReport(
                place: words[0], project: words[1], address: words[2]
            )
            if !found.contains(report) {
                found.append(report)
            }
        }
        return found
    }

    /// Notes every report in a stretch of output on the activity trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(.cloudflareProjectMadeAgain, report.trailSentence)
        }
    }

    /// A Pages project name (lower-case letters, digits and hyphens) or, with
    /// dots allowed, a host name. Nothing that could be a path.
    nonisolated static func isAName(_ word: String, allowingDots: Bool) -> Bool {
        if word.isEmpty || word.count > 253 {
            return false
        }
        for character in word.unicodeScalars {
            let isLetterOrDigit: Bool = CharacterSet.alphanumerics.contains(character) && character.isASCII
            let isJoiner: Bool = character == "-" || (allowingDots && character == ".")
            if !isLetterOrDigit && !isJoiner {
                return false
            }
        }
        return true
    }
}
