import Foundation

/// The launchers' two reports about the website builder's first run (GitHub
/// #312), as they printed them: which helper programs were installed and
/// where from, and how the website builder was created and how long it took.
///
/// The Mac app carries its own copies of the four helper programs and of the
/// website builder's starting disk (`contracts/app-rules.json` →
/// `helperBootstrap`). When that copy is broken or does not fit this Mac, the
/// launchers quietly download instead and the first run still works, only
/// slower — a failure that reports success. These lines are how a report can
/// tell the difference. The launcher prints one `PLANTOIR_HELPERS_INSTALLED:`
/// line per install and one `PLANTOIR_BUILDER_CREATED:` line per first start;
/// this reads them so the app writes the trail line — from the console of a
/// run it started (`ScriptRunner`) and from the log of a publish launchd ran
/// (`ScheduledDeploy`), the two readers `WorkspaceInUseReport` has for the
/// same reason. The lines are machinery: the console a teacher reads leaves
/// them out (`TranscriptBuilder`).
///
/// Read by the app rather than written onto the trail by the launcher, so
/// each event has ONE writer for its words and a real call site. The cost,
/// stated in the contract: a run typed at the command line prints the line
/// and leaves no trail line.
struct HelperBootstrapReport: Equatable {

    // MARK: - Stored properties

    /// The two markers the launchers print. Pinned by each event's
    /// `marker.prefix` in `contracts/shared-rules.json`.
    nonisolated static let installedMarkerPrefix: String = "PLANTOIR_HELPERS_INSTALLED:"
    nonisolated static let createdMarkerPrefix: String = "PLANTOIR_BUILDER_CREATED:"

    /// The lines, pinned by the contract's `lineWhen…` fields.
    nonisolated static let lineWhenBundled: String =
        "set up {programs} for the website builder from inside Plantoir — {why}"
    nonisolated static let lineWhenDownloaded: String =
        "downloaded {programs} for the website builder — {why}; Plantoir's own copy was not used because {whyNot}"
    nonisolated static let lineWhenSeeded: String =
        "created the website builder from the starting disk inside Plantoir in {seconds} s"
    nonisolated static let lineWhenCreatedByDownloading: String =
        "created the website builder in {seconds} s, downloading its starting disk"
    nonisolated static let lineWhenSeedRefused: String =
        "created the website builder in {seconds} s, downloading its starting disk because the copy inside Plantoir was refused as damaged"
    nonisolated static let lineWhenSeedFailed: String =
        "created the website builder in {seconds} s, downloading its starting disk because starting from the copy inside Plantoir failed"

    /// The words for each reason, pinned by the contract's `whyWords`.
    nonisolated static let whyWords: [String: String] = [
        "missing": "not yet on this Mac",
        "different": "replacing other versions",
        "damaged": "replacing a damaged copy",
        "unrecorded": "replacing copies set up before Plantoir kept a record of them"
    ]

    /// Why the app's own copy was not used, pinned by the contract's
    /// `whyNotWords`.
    nonisolated static let whyNotWords: [String: String] = [
        "none-in-app": "this Plantoir does not carry one",
        "other-arch": "it is for another kind of Mac",
        "bundle-check-failed": "it did not pass its check"
    ]

    /// The programs in the order a line names them, each with the key its
    /// version travels under and the name a person would recognise.
    nonisolated static let programOrder: [(marker: String, pin: String, name: String)] = [
        (marker: "colima", pin: "colima", name: "Colima"),
        (marker: "limactl", pin: "lima", name: "Lima"),
        (marker: "docker", pin: "docker", name: "Docker CLI"),
        (marker: "buildx", pin: "buildx", name: "Buildx")
    ]

    /// Which of the two events this is.
    let event: ActivityTrail.Event

    /// The line the trail is given.
    let trailSentence: String

    // MARK: - Functions

    /// Every report in a stretch of output, read line by line as it arrives.
    /// A line that does not have a marker's exact shape reports nothing.
    nonisolated static func reports(in text: String) -> [HelperBootstrapReport] {
        var found: [HelperBootstrapReport] = []
        for line in SiteHealthFinding.linesOf(text) {
            // From the prefix onward, so a marker glued to the tail of
            // somebody else's half line is still read (#153).
            if let prefixRange = line.range(of: installedMarkerPrefix) {
                if let report = installedReport(from: words(of: String(line[prefixRange.upperBound...]))) {
                    found.append(report)
                }
            } else if let prefixRange = line.range(of: createdMarkerPrefix) {
                if let report = createdReport(from: words(of: String(line[prefixRange.upperBound...]))) {
                    found.append(report)
                }
            }
        }
        return found
    }

    /// Notes every report in a stretch of output on the activity trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(report.event, report.trailSentence)
        }
    }

    /// Whether a line is one of these machine-readable ones, so the console
    /// can keep it out of what a teacher reads (rule 1). A line CARRYING a
    /// prefix anywhere is hidden whole, and never offered as a question —
    /// the rule #153 set for every marker.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(installedMarkerPrefix) || line.contains(createdMarkerPrefix)
    }

    /// "Colima v0.10.3", "Lima 2.2.0 and Docker CLI 29.7.2",
    /// "Colima v0.10.3, Lima 2.2.0 and Docker CLI 29.7.2".
    nonisolated static func programsPhrase(which: [String], versions: [String: String]) -> String? {
        var named: [String] = []
        for program in programOrder {
            if which.contains(program.marker) {
                guard let version = versions[program.pin], !version.isEmpty else {
                    return nil
                }
                named.append(program.name + " " + version)
            }
        }
        if named.isEmpty || named.count != which.count {
            return nil
        }
        if named.count == 1 {
            return named[0]
        }
        var phrase: String = ""
        for (index, name) in named.enumerated() {
            if index == 0 {
                phrase = name
            } else if index == named.count - 1 {
                phrase += " and " + name
            } else {
                phrase += ", " + name
            }
        }
        return phrase
    }

    private nonisolated static func words(of payload: String) -> [String] {
        var words: [String] = []
        for word in payload.split(separator: " ", omittingEmptySubsequences: true) {
            words.append(String(word))
        }
        return words
    }

    /// `bundled <why> <which> <pins>` or `downloaded <why> <which> <pins> <why-not>`.
    private nonisolated static func installedReport(from words: [String]) -> HelperBootstrapReport? {
        guard words.count == 4 || words.count == 5,
              let why = whyWords[words[1]] else {
            return nil
        }
        var which: [String] = []
        for program in words[2].split(separator: ",") {
            which.append(String(program))
        }
        var versions: [String: String] = [:]
        for pair in words[3].split(separator: ",") {
            let halves: [Substring] = pair.split(separator: "=", maxSplits: 1)
            if halves.count == 2 {
                versions[String(halves[0])] = String(halves[1])
            }
        }
        guard let programs = programsPhrase(which: which, versions: versions) else {
            return nil
        }
        var sentence: String = ""
        if words[0] == "bundled" && words.count == 4 {
            sentence = lineWhenBundled
        } else if words[0] == "downloaded" && words.count == 5, let whyNot = whyNotWords[words[4]] {
            sentence = lineWhenDownloaded.replacingOccurrences(of: "{whyNot}", with: whyNot)
        } else {
            return nil
        }
        sentence = sentence.replacingOccurrences(of: "{programs}", with: programs)
        sentence = sentence.replacingOccurrences(of: "{why}", with: why)
        return HelperBootstrapReport(event: .helperProgramsInstalled, trailSentence: sentence)
    }

    /// `<seeded|downloaded|seed-refused-then-downloaded|seed-failed-then-downloaded> <seconds>`.
    private nonisolated static func createdReport(from words: [String]) -> HelperBootstrapReport? {
        guard words.count == 2, let seconds = Int(words[1]), seconds >= 0 else {
            return nil
        }
        var sentence: String = ""
        switch words[0] {
        case "seeded":
            sentence = lineWhenSeeded
        case "downloaded":
            sentence = lineWhenCreatedByDownloading
        case "seed-refused-then-downloaded":
            sentence = lineWhenSeedRefused
        case "seed-failed-then-downloaded":
            sentence = lineWhenSeedFailed
        default:
            return nil
        }
        sentence = sentence.replacingOccurrences(of: "{seconds}", with: String(seconds))
        return HelperBootstrapReport(event: .websiteBuilderCreated, trailSentence: sentence)
    }
}
