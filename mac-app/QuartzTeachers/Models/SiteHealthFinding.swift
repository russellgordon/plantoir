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

    /// The activity-trail line for this finding, in the shape
    /// `contracts/shared-rules.json` → `activityTrail.mustRecord` →
    /// "folder problem found" → `carries` gives — curly apostrophe included,
    /// which is what that contract and Windows' `TrailSentence` say. It lives
    /// here because TWO places write it: `ScriptRunner`, as a build's output
    /// arrives, and `ScheduledDeploy.recordFolderProblems`, at the end of a
    /// scheduled run. Written out in each, the mac once wrote a straight
    /// apostrophe the contract did not (#153).
    ///
    /// A sentence a teacher would recognise, carrying the stable check NAME in
    /// brackets. Both halves earn their place: rule 5 says a trail line must
    /// read as something that happened rather than as a function name, while
    /// the name is what somebody reading the trail months later can match
    /// against the contract — the product wording will have been reworded by
    /// then.
    nonisolated var trailSentence: String {
        return "found a problem with this course’s folders (\(name))"
    }

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
        for line in linesOf(text) {
            // From the prefix ONWARD, not only a line that starts with it:
            // something else writing half a line into the same terminal glues
            // the marker to its tail ("Building…PLANTOIR_HEALTH: {…}"), and
            // `hasPrefix` then dropped the finding outright — no dialog, no
            // trail line, nothing in the assistant's answer (#153, measured).
            // Windows' `SiteHealthFinding.Parse` reads from `IndexOf` the same
            // way.
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
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

    /// Splits output into lines, on SCALARS rather than Characters.
    ///
    /// This is the bug that driving the real app found, and the codebase warned
    /// about it before I wrote it: Swift folds "\r\n" into ONE Character
    /// (a grapheme cluster), so `split(separator: "\n")` does not split there
    /// at all. `TranscriptBuilder.append(rawText:)` says exactly this in a
    /// comment — "would hide line endings" — and works scalar by scalar for
    /// the same reason.
    ///
    /// Real output comes from a PTY and ends "\r\n", so every marker line was
    /// glued to its neighbours: the resulting "line" CONTAINED the prefix but
    /// did not START with it, `hasPrefix` was false, and every finding was
    /// dropped. Every unit test passed, because they all used "\n".
    nonisolated static func linesOf(_ text: String) -> [String] {
        var lines: [String] = []
        var current: String.UnicodeScalarView = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
                continue
            }
            current.append(scalar)
        }
        lines.append(String(current))
        return lines
    }

    /// Whether a line is one of the machine-readable ones, so the console can
    /// keep it out of what a teacher reads.
    ///
    /// Rule 1: the interface never names the machinery, and a raw JSON blob in
    /// the console is machinery. The human-readable sentence is printed
    /// separately by the toolchain, so hiding this line loses nothing.
    ///
    /// A line CARRYING the prefix anywhere counts, and the WHOLE line goes
    /// (#153). What precedes a glued marker is half a line of progress
    /// chatter, which is not a sentence anybody needs; and a check that only
    /// looked at the start showed the teacher the raw JSON whenever the marker
    /// arrived glued to something else. This is Windows' own rule
    /// (`TranscriptBuilder.CarriesTheHealthMarker`), adopted. It cannot catch
    /// ordinary output by accident: no script contains the prefix as a
    /// literal — `site_health.py` reads it from the contract.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
