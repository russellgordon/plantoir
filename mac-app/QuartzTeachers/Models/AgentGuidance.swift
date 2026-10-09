import CryptoKit
import Foundation

/// Guidance for an assistant started at a working folder (#454, decision 12
/// and Russell's P1 rulings of 2026-10-09): the skills under
/// `.claude/skills/` and `.agents/skills/`, and a MANAGED SECTION in
/// `AGENTS.md` and `CLAUDE.md` at the working folder's root that names them.
///
/// The rule for the two root files, which are often the teacher's own
/// (contracts/shared-rules.json → printablePages.agentGuidance.rootFileCases):
/// - no file → write it, holding only Plantoir's section;
/// - Plantoir's markers present → replace what is between them, nothing else;
/// - no markers → ASK first (a sheet naming the file and showing the text),
///   then append the section below the teacher's own text. A "Not Now" is
///   remembered for that file until the section's words change or the file
///   goes; a file is never appended to without a yes.
///
/// Why the ROOT, measured (plan review S1): Codex never found a skill inside a
/// course and found it at the root at once; Claude Code found a per-course
/// skill only after the first page was written. The four runs re-measured
/// with these files in place are in documentation/09-mac-app.md.
///
/// Written AFTER the toolchain copy, on its own outcome: a failure here is
/// logged, recorded on the trail and shown as a quiet notice, and NEVER holds
/// Preview, Deploy or New Course back (implementation review S1).
nonisolated enum AgentGuidance {

    // MARK: - Types

    /// What to do with one root file.
    enum RootFileAction: Equatable {
        /// No file: write this text.
        case write(String)
        /// Plantoir's section is there and out of date: write this text.
        case replace(String)
        /// Plantoir's section is there and current.
        case unchanged
        /// The teacher's own file, no section yet: ask before appending.
        case ask
        /// The teacher said Not Now to this very section.
        case leave
    }

    /// A file waiting for the teacher's answer.
    struct PendingAppend: Equatable, Identifiable, Sendable {

        // MARK: - Stored properties

        /// The file's name, as the sheet says it.
        let fileName: String
        /// Where it is.
        let fileURL: URL
        /// The section's words (between the markers).
        let body: String

        // MARK: - Computed properties

        var id: String {
            return fileURL.path
        }

        /// What would be added, markers included, as the sheet shows it.
        var section: String {
            return AgentGuidance.block(body: body)
        }
    }

    /// What one pass did.
    struct Outcome: Equatable, Sendable {

        // MARK: - Stored properties

        var changed: Int = 0
        /// One line per file that could not be written, with the reason.
        var failures: [String] = []
        /// The first failure's reason alone, for the notice a teacher reads
        /// (no path; the trail line keeps it).
        var firstReason: String? = nil
        /// The teacher's own files, waiting for a yes.
        var pending: [PendingAppend] = []

        // MARK: - Functions

        /// One failure: where, and the system's words.
        mutating func note(_ place: String, _ reason: String) {
            failures.append(place + ": " + reason)
            if firstReason == nil {
                firstReason = AgentGuidance.withoutFinalStop(reason)
            }
        }
    }

    // MARK: - Stored properties

    /// The two lines around Plantoir's section (contract: sectionStart, sectionEnd).
    static let sectionStart: String =
        "<!-- BEGIN PLANTOIR: Plantoir writes and replaces everything between this line and END PLANTOIR. Your own text goes above or below. -->"
    static let sectionEnd: String = "<!-- END PLANTOIR -->"

    /// The root files, in the order they are asked about.
    static let rootFiles: [String] = ["AGENTS.md", "CLAUDE.md"]

    /// Where "Not Now" answers are kept: file path → the section's signature.
    static let declinedDefaultsKey: String = "AgentGuidanceDeclined"

    // MARK: - Functions: the rule

    /// A sentence without its final full stop, to sit inside brackets.
    static func withoutFinalStop(_ text: String) -> String {
        var trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }

    /// The section, markers included.
    static func block(body: String) -> String {
        var trimmed: String = body
        while trimmed.hasSuffix("\n") {
            trimmed.removeLast()
        }
        return sectionStart + "\n" + trimmed + "\n" + sectionEnd
    }

    /// A short fingerprint of the section's words, so a Not Now holds only
    /// until the words change.
    static func signature(of body: String) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: Data(block(body: body).utf8))
        var hex: String = ""
        for byte in digest {
            hex += String(format: "%02x", byte)
        }
        return String(hex.prefix(16))
    }

    /// What to do with a root file holding `existing` (nil: no file).
    static func action(existing: String?, body: String, declinedSignature: String?) -> RootFileAction {
        guard let existing else {
            return .write(block(body: body) + "\n")
        }
        if let replaced = replacingSection(in: existing, body: body) {
            if replaced == existing {
                return .unchanged
            }
            return .replace(replaced)
        }
        if declinedSignature == signature(of: body) {
            return .leave
        }
        return .ask
    }

    /// The file with Plantoir's section replaced, or nil when the file has no
    /// complete section (a start line followed later by an end line).
    static func replacingSection(in existing: String, body: String) -> String? {
        // Anchored on the END line, taking the LAST start line before it: a
        // stray start line above a real section (the shape "Add" leaves after
        // a start line with no end) is the teacher's text, and taking the
        // first start line replaced it on the next launch (fix review).
        guard let firstStart = existing.range(of: sectionStart),
              let end = existing.range(of: sectionEnd, range: firstStart.upperBound..<existing.endIndex),
              let start = existing.range(of: sectionStart, options: .backwards,
                                         range: existing.startIndex..<end.lowerBound) else {
            return nil
        }
        return String(existing[..<start.lowerBound]) + block(body: body) + String(existing[end.upperBound...])
    }

    /// The teacher's file with the section added below their own text, which
    /// is left exactly as it is; one blank line between.
    static func appended(to existing: String, body: String) -> String {
        var joined: String = existing
        if joined.isEmpty {
            return block(body: body) + "\n"
        }
        if !joined.hasSuffix("\n") {
            joined += "\n"
        }
        return joined + "\n" + block(body: body) + "\n"
    }

    // MARK: - Functions: the pass

    /// Writes the skills and settles the root files. `declined` answers the
    /// stored Not Now signature for a file path, if any; `forgetDeclined` is
    /// called when a file has gone, so a new one is written fresh.
    static func write(
        from guidanceURL: URL,
        into workspaceURL: URL,
        declined: (String) -> String?,
        forgetDeclined: (String) -> Void
    ) -> Outcome {
        let fileManager: FileManager = FileManager.default
        var outcome: Outcome = Outcome()
        let skills: [URL] = (try? fileManager.contentsOfDirectory(
            at: guidanceURL.appendingPathComponent("skills"),
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        for skillURL in skills {
            let isFolder: Bool = (try? skillURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isFolder {
                continue
            }
            for home in [".claude", ".agents"] {
                let destination: URL = workspaceURL
                    .appendingPathComponent(home)
                    .appendingPathComponent("skills")
                    .appendingPathComponent(skillURL.lastPathComponent)
                let copied: WorkspaceModel.MirrorOutcome = WorkspaceModel.syncDirectory(from: skillURL, to: destination)
                outcome.changed += copied.changed
                if copied.failed > 0 {
                    outcome.note(home + "/skills/" + skillURL.lastPathComponent,
                                 copied.firstFailure ?? "could not be written")
                }
            }
        }
        for name in rootFiles {
            guard let body = try? String(contentsOf: guidanceURL.appendingPathComponent(name), encoding: .utf8) else {
                continue
            }
            let fileURL: URL = workspaceURL.appendingPathComponent(name)
            var existing: String? = nil
            if fileManager.fileExists(atPath: fileURL.path) {
                guard let read = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    outcome.note(name, "could not be read")
                    continue
                }
                existing = read
            } else {
                forgetDeclined(fileURL.path)
            }
            switch action(existing: existing, body: body, declinedSignature: declined(fileURL.path)) {
            case .write(let text), .replace(let text):
                do {
                    try Data(text.utf8).write(to: fileURL, options: [.atomic])
                    outcome.changed += 1
                } catch {
                    outcome.note(name, error.localizedDescription)
                }
            case .ask:
                outcome.pending.append(PendingAppend(fileName: name, fileURL: fileURL, body: body))
            case .unchanged, .leave:
                break
            }
        }
        return outcome
    }

    /// The teacher said Add: append the section, having read the file again
    /// (it may have changed while the sheet was open). Answers false when the
    /// file could not be written.
    static func appendAfterYes(_ pending: PendingAppend) -> Bool {
        // Only a MISSING file reads as empty. A file that is there and can no
        // longer be read (saved in another encoding, its permissions changed
        // while the sheet was open) is refused: writing would replace the
        // teacher's text with the section alone (fix review).
        var existing: String = ""
        if FileManager.default.fileExists(atPath: pending.fileURL.path) {
            guard let read = try? String(contentsOf: pending.fileURL, encoding: .utf8) else {
                return false
            }
            existing = read
        }
        var text: String = appended(to: existing, body: pending.body)
        if let replaced = replacingSection(in: existing, body: pending.body) {
            text = replaced
        }
        do {
            try Data(text.utf8).write(to: pending.fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Functions: remembered answers

    static func declinedSignature(forPath path: String, in defaults: UserDefaults = .standard) -> String? {
        let stored: [String: String] = (defaults.dictionary(forKey: declinedDefaultsKey) as? [String: String]) ?? [:]
        return stored[path]
    }

    static func rememberDeclined(_ pending: PendingAppend, in defaults: UserDefaults = .standard) {
        var stored: [String: String] = (defaults.dictionary(forKey: declinedDefaultsKey) as? [String: String]) ?? [:]
        stored[pending.fileURL.path] = signature(of: pending.body)
        defaults.set(stored, forKey: declinedDefaultsKey)
    }

    static func forgetDeclined(forPath path: String, in defaults: UserDefaults = .standard) {
        var stored: [String: String] = (defaults.dictionary(forKey: declinedDefaultsKey) as? [String: String]) ?? [:]
        if stored.removeValue(forKey: path) != nil {
            defaults.set(stored, forKey: declinedDefaultsKey)
        }
    }

    // MARK: - Functions: the trail

    /// `asked before adding guidance to a file`: the file's NAME and the answer.
    static func askedLine(fileName: String, added: Bool) -> String {
        return "asked before adding Plantoir's section to " + fileName + " in the working folder — "
            + (added ? "added" : "not now")
    }

    /// `guidance for assistants could not be written`: how many, and the first.
    static func couldNotWriteLine(_ failures: [String]) -> String {
        var line: String = "could not write the guidance for assistants into the working folder: "
            + String(failures.count) + " problem(s)"
        if let first = failures.first {
            line += " — first: " + first
        }
        return line
    }
}

/// What a teacher reads about the guidance (contract:
/// printablePages.agentGuidance.words). Rule 1: no machinery words.
nonisolated enum AgentGuidanceWording {

    // MARK: - Stored properties

    static let showWhatIsAdded: String = "Show what would be added"
    static let add: String = "Add"
    static let notNow: String = "Not Now"
    static let dismiss: String = "Dismiss"

    static let askWhat: String =
        "Plantoir would like to add a short section at the end of it that points them to its guidance for writing pages — for example, how to make a page printable."

    static let askYoursStays: String = "Your own text stays exactly as it is, above the new section."

    // MARK: - Functions

    static func askTitle(file: String) -> String {
        return "Add a section to " + file + "?"
    }

    static func askFound(file: String) -> String {
        return "This working folder already has " + file
            + ", a file that assistants such as Claude Code and Codex read before they start."
    }


    static func couldNotWrite(reason: String) -> String {
        return "Plantoir could not put its guidance for assistants into this folder (" + reason
            + "). Everything else works as usual."
    }
}
