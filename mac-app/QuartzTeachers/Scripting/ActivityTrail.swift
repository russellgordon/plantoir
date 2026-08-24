import Foundation

/// The breadcrumb trail: what the teacher was doing, in the order they did it.
///
/// A report made of task records alone answers "what did that publish print?"
/// It does not answer the question support actually starts from — **what were
/// you doing when it went wrong?** — and without that, a record is a page of
/// output with no story round it. A teacher who says "it stopped working after
/// I renamed something" is describing a sequence, and this is where the
/// sequence lives.
///
/// Deliberately coarse. Every line here is a thing the teacher would recognise
/// as something they did, not an internal state change: opening a folder, yes;
/// a view redrawing, no. A trail nobody can read is the same as no trail, and
/// the failure mode of logging-everything is that the one line that mattered
/// is on page forty.
nonisolated enum ActivityTrail {

    // MARK: - Types

    /// Everything the trail is required to record.
    ///
    /// Naming an event is what makes the requirement bite. A feature cannot
    /// be added without its author choosing the line it leaves — either an
    /// event that already fits, or a new case here, which the contract then
    /// makes the OTHER platform account for too. Free-text calls would let a
    /// feature ship silently, which is the whole failure this list exists to
    /// stop.
    ///
    /// The raw value is a stable key for the contract, NOT the words written
    /// to the file: the line a teacher reads is a sentence, and sentences get
    /// reworded. Pinning the key instead means rewording is free and dropping
    /// an event is not.
    enum Event: String, CaseIterable, Sendable {
        case appOpened = "app opened"
        case machine = "machine described"
        case helpers = "helpers described"
        case workingFolderOpened = "working folder opened"
        case settingsSaved = "settings saved"
        case settingsCouldNotBeSaved = "settings could not be saved"
        case taskStarted = "task started"
        case taskFinished = "task finished"
        case askedForACredential = "asked for a publishing credential"
        case assistantOpened = "assistant opened"
        case assistantReady = "assistant ready"
        case assistantWouldNotStart = "assistant would not start"
        case assistantEngineSaid = "assistant engine said"
        case assistantAsked = "assistant asked"
        case assistantChoseATool = "assistant chose a tool"
        case assistantCouldNotAnswer = "assistant could not answer"
        case assistantMatchedAFixedPhrase = "assistant matched a fixed phrase"
        case settingsPanelOpened = "app settings opened"
        case assistantModelChosen = "assistant model chosen"
        case assistantModelDownloadStarted = "assistant model download started"
        case assistantModelDownloaded = "assistant model downloaded"
        case assistantModelDownloadFailed = "assistant model download failed"
        case assistantModelDownloadStopped = "assistant model download stopped"
        case assistantModelRemoved = "assistant model removed"
        case assistantConfirmationChanged = "assistant confirmation changed"
        /// Why a section stopped saying " — Edited". Without it, a
        /// teacher reporting "it still says Edited after I published"
        /// leaves nothing to look at: the marker is derived, so its
        /// absence and its presence look identical on disk.
        case sectionContentMarkedPublished = "section content marked published"
        /// A folder a feature depends on was missing, renamed or emptied.
        /// Carries the check's NAME, never its wording: the sentence is
        /// product wording and will be reworded, while the name is what
        /// somebody reading the trail months later can match against the
        /// contract. The finding itself is printed into a build console that
        /// is long gone by the time it is reported, and the condition is
        /// invisible on disk — a renamed folder looks exactly like a folder
        /// that was always called that.
        case folderProblemFound = "folder problem found"
        /// A folder a feature depends on was put back, at the teacher's
        /// request. Separate from `folderProblemFound` because it is a
        /// different event: one records that something is wrong, the other that
        /// somebody acted on it — and a trail that could not tell them apart
        /// would leave "did they ever fix it?" unanswerable.
        case folderProblemRepaired = "folder problem repaired"
        /// A folder or file was removed in Course Settings, excluding it
        /// from previews and deploys.
        case itemExcluded = "item excluded"
        /// A previously excluded folder or file was added back in Course
        /// Settings, returning it to previews and deploys.
        case itemReincluded = "item re-included"
    }

    // MARK: - Stored properties

    /// Where lines go. Replaceable so a test can point it somewhere of its own.
    nonisolated(unsafe) static var store: ProblemReportStore = ProblemReportStore.standard

    // MARK: - Functions

    /// Notes one thing that happened.
    ///
    /// `what` is written for somebody reading the trail months later, so it
    /// says what happened in words rather than naming a function: "started
    /// building the preview", not "runScript(preview.sh)".
    /// `wholeLine` is for an entry that already carries its own timestamp and
    /// shape — the assistant's turn record — so it is not stamped twice.
    static func note(
        _ event: Event,
        _ what: String,
        at moment: Date = Date(),
        wholeLine: Bool = false
    ) {
        if wholeLine {
            store.appendActivityLine(what)
            return
        }
        store.appendActivityLine(line(what, at: moment))
    }

    /// The event keys this app actually emits, for the contract to pin.
    static var eventKeys: [String] {
        var keys: [String] = []
        for event in Event.allCases {
            keys.append(event.rawValue)
        }
        return keys
    }

    /// One line, without writing it — the part a test can check.
    static func line(_ what: String, at moment: Date, timeZone: TimeZone = TimeZone.current) -> String {
        return ActivityTrail.formatter(timeZone: timeZone).string(from: moment) + " · " + what
    }

    /// Notes something about one section, so the trail says which course and
    /// section a line belongs to without every caller remembering to.
    static func note(_ event: Event, _ what: String, course: String, section: Int, at moment: Date = Date()) {
        ActivityTrail.note(event, "\(course)/\(section) · " + what, at: moment)
    }

    static func formatter(timeZone: TimeZone = TimeZone.current) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    /// The line that opens a session, so a trail spanning several launches
    /// says where each one began — and says which BUILD it was, which is the
    /// first thing to check when a report and the code disagree.
    static func noteLaunch() {
        ActivityTrail.note(.appOpened, "Plantoir opened — " + ProblemReportEnvironment.appDescription)
        ActivityTrail.note(.machine, "running on " + ProblemReportEnvironment.systemDescription)
        ActivityTrail.note(.helpers, "using " + ProblemReportEnvironment.helperDescription)
    }
}
