import Foundation

/// Something wrong with a course's folders, as the toolchain reported it.
///
/// The build prints one `PLANTOIR_HEALTH: {json}` line per finding, and the
/// SENTENCE a teacher reads travels inside that line rather than being written
/// again here. That is deliberate: the wording has one home
/// (`contracts/shared-rules.json` → `siteHealth.checks`), and re-authoring it
/// on each platform is how the same problem ends up worded two different ways
/// on macOS and Windows.
struct SiteHealthFinding: Equatable, Identifiable {

    // MARK: - Stored properties

    /// The check's name — `curriculumCoverageFoundNothing` and friends. Stable
    /// across rewordings, which is what makes it the thing to record on the
    /// activity trail and the thing to match against the contract.
    let name: String

    /// One line, in a teacher's words. Already has the course and section
    /// filled in.
    let sentence: String

    /// What it means and what to do about it.
    let detail: String

    /// Whether the problem is one Plantoir could put right on request. Nothing
    /// acts on this yet; it is carried so the front end can grow a button
    /// without the toolchain having to change.
    let fixable: Bool

    let course: String
    let section: Int

    // MARK: - Computed properties

    var id: String { return "\(course)/\(section)/\(name)" }

    // MARK: - Functions

    /// The marker the toolchain prints. Pinned by
    /// `contracts/shared-rules.json` → `siteHealth.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_HEALTH:"

    /// Every finding announced in a stretch of output.
    ///
    /// Callers feed this the text as it ARRIVES, not the finished transcript:
    /// the health lines are printed in the middle of a build, and the app's
    /// other structured-line readers work from
    /// `transcript.recentText(maximumCharacters: 8000)` — a TAIL, which on a
    /// real build has long since scrolled past them.
    nonisolated static func findings(in text: String) -> [SiteHealthFinding] {
        var found: [SiteHealthFinding] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            // `.whitespacesAndNewlines` rather than `.whitespaces`, because
            // output arrives from a PTY where lines end "\r\n" and splitting
            // on "\n" leaves the carriage return behind.
            //
            // Belt and braces, NOT a bug fix: this was written believing the
            // trailing "\r" broke the JSON parse, and it does not —
            // JSONSerialization tolerates it, and the test below passes
            // against the old code too. Left in because a control character
            // riding along on a parsed line is worth removing anyway, and
            // labelled honestly so nobody reads it as the cause of something.
            let line: String = String(rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(markerPrefix) else {
                continue
            }
            let payload: String = String(line.dropFirst(markerPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = object["name"] as? String,
                  let sentence = object["sentence"] as? String else {
                continue
            }
            found.append(SiteHealthFinding(
                name: name,
                sentence: sentence,
                detail: (object["detail"] as? String) ?? "",
                fixable: (object["fixable"] as? Bool) ?? false,
                course: (object["course"] as? String) ?? "",
                section: (object["section"] as? Int) ?? 0
            ))
        }
        return found
    }

    /// A run's findings, appended to whatever a caller is about to be told.
    ///
    /// **For callers with no window to put a dialog in** — the assistant, and
    /// `Plantoir --mcp-stdio`. A finding that only produced an alert would
    /// reach nobody there, so the sentence has to travel in the answer itself.
    /// The wording is the toolchain's own, carried in the marker line, which is
    /// what stops the assistant describing the same problem in different words
    /// from the section window.
    static func appending(to message: String, from runner: ScriptRunner) -> String {
        if runner.healthFindings.isEmpty {
            return message
        }
        var parts: [String] = [message]
        for finding in runner.healthFindings {
            parts.append(finding.sentence + " " + finding.detail)
        }
        return parts.joined(separator: "\n\n")
    }

    /// Whether a line is one of the machine-readable ones, so the console can
    /// keep it out of what a teacher reads.
    ///
    /// Rule 1: the interface never names the machinery, and a raw JSON blob in
    /// the console is machinery. The human-readable sentence is printed
    /// separately by the toolchain, so hiding this line loses nothing.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix(markerPrefix)
    }
}
