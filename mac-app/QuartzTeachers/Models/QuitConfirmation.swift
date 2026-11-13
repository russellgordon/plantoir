import Foundation

/// What ⌘Q does when Plantoir is in the middle of something.
///
/// **Why there is a question at all.** Until 2026-09-19 the quit path could
/// not find the programs it needed, so quitting did nothing to the website
/// builder and there was nothing to interrupt (issue #220). Making it work
/// means a quit can now genuinely stop a publish — and the one case where
/// that hurts is the one a teacher cannot see happening, so they are asked.
///
/// **What counts as "under way", and what deliberately does not.** A publish
/// recorded in `CourseActivity` does, and so — since issue #232 — does a
/// preview still being BUILT; a preview that is merely OPEN does not. The
/// reason is what each fact can actually tell us.
/// `CourseActivity.activePublishes` is process-wide and lasts exactly as long
/// as the publish, so it means what it says; `activePreviewBuilds` is the same
/// kind of record, kept from the press until the preview's page first answers
/// (or the run ends). A preview's LEASE is held for the whole time a preview
/// is open — it cannot tell a section still building from one that finished
/// twenty minutes ago and is sitting there being looked at. Asking on every
/// lease would mean asking almost every quit, which trains a teacher to
/// dismiss the question before reading it. (`CourseActivity.courseIsBusy`
/// folds leases and publishes together, which is right for greying out a menu
/// item and wrong here; asking it the wrong one of those questions has
/// produced a bug in this app before.) Open previews are not left to their
/// fate either: the quit path stops the app's own previews cleanly on the way
/// out rather than asking about them.
///
/// **What is out of reach, and is therefore never asked about.** A scheduled
/// publish, an assistant driving Plantoir over MCP, and a teacher's own
/// Terminal run are all OTHER processes with their own memory of what they
/// are doing. Nothing here can see them — so nothing here asks about them,
/// and the quit script instead refuses to stop anything while a launcher for
/// the folder is running on this Mac.
@MainActor
enum QuitConfirmation {

    // MARK: - Types

    /// Why the app is being asked to go away.
    enum Reason {
        case theTeacherAskedToQuit
        case theMacIsLoggingOutOrShuttingDown
    }

    /// Why Plantoir closed, for the trail's `app closed` line (#560). Finer
    /// than `Reason`, which only needs to know whether a question may be put
    /// up: the trail says WHICH system quit it was, and whether the app was
    /// quitting to install an update.
    nonisolated enum ClosingReason: Equatable, Sendable {
        case quitByTheTeacher
        case toInstallANewVersion
        case theMacIsLoggingOut
        case theMacIsRestarting
        case theMacIsShuttingDown

        // MARK: - Computed properties

        /// The words on the trail, after "Plantoir closed — ".
        var words: String {
            switch self {
            case .quitByTheTeacher:
                return "quit by the teacher"
            case .toInstallANewVersion:
                return "to install a new version"
            case .theMacIsLoggingOut:
                return "because the Mac is logging out"
            case .theMacIsRestarting:
                return "because the Mac is restarting"
            case .theMacIsShuttingDown:
                return "because the Mac is shutting down"
            }
        }
    }

    /// What the teacher answered.
    enum Choice: String {
        case keepWorking
        case quitAnyway
    }

    /// The publishes under way, sorted into deploys and the three kinds of
    /// work the unit plans' launcher does (#863).
    struct Kinds {

        // MARK: - Stored properties

        var deploys: [CourseActivity.PublishRecord] = []
        var shares: [String] = []
        var passwordChanges: [String] = []
        var stops: [String] = []

        // MARK: - Functions

        /// Sorts `publishes`, reading `planWork` for what each plans run is
        /// doing. A plans run with no record of its own is a share, which is
        /// what every run was before the record existed.
        static func of(
            publishes: [CourseActivity.PublishRecord], planWork: [CourseActivity.PlanWorkRecord]
        ) -> Kinds {
            var kinds: Kinds = Kinds()
            for publish in publishes {
                if publish.sectionNumber != PlanSharing.leaseSection {
                    kinds.deploys.append(publish)
                    continue
                }
                var work: CourseActivity.PlanWork = .sharing
                for record in planWork
                where record.courseCode == publish.courseCode && record.folderPath == publish.folderPath {
                    work = record.work
                }
                switch work {
                case .sharing:
                    kinds.shares.append(publish.courseCode)
                case .changingPassword:
                    kinds.passwordChanges.append(publish.courseCode)
                case .stopping:
                    kinds.stops.append(publish.courseCode)
                }
            }
            return kinds
        }

        /// One kind's phrase: its course alone, or how many courses.
        static func phrase(one: String, several: String, courses: [String]) -> String? {
            if courses.count == 1 {
                return one.replacingOccurrences(of: "{course}", with: courses[0])
            }
            if courses.count > 1 {
                return several.replacingOccurrences(of: "{n}", with: String(courses.count))
            }
            return nil
        }

        /// What the question names, deploys first, or nil when nothing is
        /// being deployed or done to unit plans.
        func phrase() -> String? {
            var parts: [String] = []
            if deploys.count == 1 {
                parts.append(QuitConfirmation.deployingOne
                    .replacingOccurrences(of: "{section}", with: String(deploys[0].sectionNumber))
                    .replacingOccurrences(of: "{course}", with: deploys[0].courseCode))
            } else if deploys.count > 1 {
                parts.append(QuitConfirmation.deployingSeveral
                    .replacingOccurrences(of: "{n}", with: String(deploys.count)))
            }
            if let sharing = Kinds.phrase(
                one: QuitConfirmation.sharingOne, several: QuitConfirmation.sharingSeveral, courses: shares
            ) {
                parts.append(sharing)
            }
            if let changing = Kinds.phrase(
                one: QuitConfirmation.changingPasswordOne,
                several: QuitConfirmation.changingPasswordSeveral,
                courses: passwordChanges
            ) {
                parts.append(changing)
            }
            if let stopping = Kinds.phrase(
                one: QuitConfirmation.stoppingOne, several: QuitConfirmation.stoppingSeveral, courses: stops
            ) {
                parts.append(stopping)
            }
            if parts.isEmpty {
                return nil
            }
            return QuitConfirmation.joined(parts)
        }

        /// The message for what is under way, in the same order, or nil
        /// when nothing is being deployed or done to unit plans.
        func message() -> String? {
            var clauses: [String] = []
            if !deploys.isEmpty {
                clauses.append(QuitConfirmation.deployClause)
            }
            if !shares.isEmpty {
                clauses.append(QuitConfirmation.shareClause)
            }
            if !passwordChanges.isEmpty {
                clauses.append(QuitConfirmation.passwordClause)
            }
            if !stops.isEmpty {
                clauses.append(QuitConfirmation.stopClause)
            }
            return QuitConfirmation.message(clauses: clauses)
        }
    }

    /// One button, and what pressing it means.
    ///
    /// The pair travels together for a reason. `NSAlert` has no notion of
    /// which button means what: it reports `.alertFirstButtonReturn` for
    /// whichever title was added first, so a one-line reorder of two
    /// `addButton` calls would silently swap the MEANINGS and make Keep
    /// Working quit. Keeping the title beside its answer, in one ordered
    /// list that the alert and the test both read, is what stops that being
    /// a one-line change with nothing in its way.
    struct Button {

        // MARK: - Stored properties

        let title: String
        let choice: Choice
    }

    // MARK: - Stored properties

    /// The four-character codes macOS sends when the quit is the SYSTEM's
    /// idea rather than the teacher's: log out, restart, shut down, and the
    /// three "are you sure?" variants of the same.
    ///
    /// A modal put up in `applicationShouldTerminate` during a log out blocks
    /// the log out — the Mac sits there until macOS times the app out and
    /// reports it as the one that would not quit. So the question is skipped
    /// entirely and everything is left running instead, which is the same
    /// answer the quit script reaches by itself when it finds work in flight.
    static let systemQuitReasonCodes: [OSType] = [
        OSType(kAELogOut),
        OSType(kAEReallyLogOut),
        OSType(kAEShowRestartDialog),
        OSType(kAERestart),
        OSType(kAEShowShutdownDialog),
        OSType(kAEShutDown)
    ]

    /// What the quit question and its message say about the unit plans'
    /// launcher and about deploys alongside it (#863, Russell 2026-11-13:
    /// sharing gets its own words). Each is a contract key in
    /// `quittingWhileWorkIsUnderWay.whileUnitPlansAreShared.words`, written
    /// with `{course}`, `{section}` and `{n}` so the contract and this app
    /// hold one template. The deploy phrases are the ones the question always
    /// used.
    static let deployingOne: String = "deploying Section {section} of {course}"
    static let deployingSeveral: String = "deploying {n} sections"
    static let sharingOne: String = "sharing the unit plans of {course}"
    static let sharingSeveral: String = "sharing the unit plans of {n} courses"
    static let changingPasswordOne: String = "changing the password for the unit plans of {course}"
    static let changingPasswordSeveral: String = "changing the password for the unit plans of {n} courses"
    static let stoppingOne: String = "stopping sharing the unit plans of {course}"
    static let stoppingSeveral: String = "stopping sharing the unit plans of {n} courses"

    /// The message, with one thing that could be left part way, or several.
    static let messageOne: String = "Quitting now could leave it unfinished, with {clauses}."
    static let messageSeveral: String = "Quitting now could leave them unfinished, with {clauses}."

    /// What each kind of work could leave part way, read off what each one
    /// leaves when it stops early (`unitPlanning.share.interruptionCases`,
    /// `changePasswordCases`, `stopSharing`). A share stopped part way
    /// leaves its marker at `sending` and the next share finishes it; a
    /// Change Password sends nothing and may not have saved the password
    /// yet; a Stop Sharing leaves the address answering until it is done.
    /// None of the three plans' clauses names the class website.
    static let deployClause: String = "the class website part way updated"
    static let shareClause: String = "the plans part way shared until you share them again or stop sharing them"
    static let passwordClause: String = "the new password not saved yet"
    static let stopClause: String = "the plans' address still working until you stop sharing them again"

    static let keepWorkingButton: String = "Keep Working"
    static let quitAnywayButton: String = "Quit Anyway"

    /// The buttons in the order they are put up. The FIRST is the default
    /// one, and the safe answer is the default answer: a teacher who presses
    /// Return without reading keeps their work.
    static let buttonsInOrder: [Button] = [
        Button(title: keepWorkingButton, choice: .keepWorking),
        Button(title: quitAnywayButton, choice: .quitAnyway)
    ]

    // MARK: - Functions

    /// What this app is in the middle of, in the words the teacher is shown —
    /// or nil when it is in the middle of nothing.
    ///
    /// **Reads its own facts, and that is the point.** It used to be handed
    /// `CourseActivity.activePublishes` by the delegate, which left the one
    /// decision worth pinning — publishes count, previews do not — outside
    /// anything a test could reach: the contract's "a preview is open" case
    /// passed for every implementation, and swapping `activePublishes` for
    /// `courseIsBusy` at the call site left the whole suite green. Now the
    /// choice of source is inside the function the contract cases run.
    static func workUnderWay() -> String? {
        return workUnderWay(
            publishes: CourseActivity.activePublishes,
            previews: PreviewLeases.active,
            previewBuilds: CourseActivity.activePreviewBuilds,
            copies: CourseActivity.activeCopies,
            planWork: CourseActivity.activePlanWork
        )
    }

    /// The same decision with every fact handed in, for a test that wants to
    /// build them rather than install them.
    ///
    /// `previews` is taken and deliberately NOT used — a parameter that
    /// exists to say so out loud. A lease is held for as long as a preview is
    /// OPEN, so it cannot tell a section still building from one that
    /// finished twenty minutes ago; asking on every lease would mean asking
    /// almost every quit. A preview still being BUILT is its own fact,
    /// `previewBuilds`, and that one counts.
    ///
    /// **A publish wins.** When both are under way the teacher is asked about
    /// the publish, in the publish's words: it is the one whose loss reaches
    /// the class website, and one question naming two different things would
    /// have to be vaguer about both.
    static func workUnderWay(
        publishes: [CourseActivity.PublishRecord],
        previews: [PreviewLeases.Lease],
        previewBuilds: [CourseActivity.PreviewBuildRecord] = [],
        copies: [CourseActivity.CopyRecord] = [],
        planWork: [CourseActivity.PlanWorkRecord] = []
    ) -> String? {
        _ = previews
        // A run of the unit plans' launcher is held as a publish under
        // section 0, and is named for what it is doing, never counted as a
        // section being deployed (#863).
        let kinds: Kinds = Kinds.of(publishes: publishes, planWork: planWork)
        if let phrase = kinds.phrase() {
            return phrase
        }
        if previewBuilds.count == 1 {
            let only: CourseActivity.PreviewBuildRecord = previewBuilds[0]
            return "building the preview of Section \(only.sectionNumber) of \(only.courseCode)"
        }
        if previewBuilds.count > 1 {
            return "building \(previewBuilds.count) previews"
        }
        // A copy being zipped (#351): a backup, or the archive before a
        // restore or a removal. Asked about because a quit mid-zip leaves a
        // half-written copy, and a restore or removal that never happened.
        if copies.count == 1 {
            return "saving a copy of \(copies[0].displayCode)"
        }
        if copies.count > 1 {
            return "saving \(copies.count) copies"
        }
        return nil
    }

    /// Whether to put the question up at all.
    static func shouldAsk(reason: Reason, workUnderWay: String?) -> Bool {
        if reason == .theMacIsLoggingOutOrShuttingDown {
            return false
        }
        return workUnderWay != nil
    }

    /// Which kind of quit a four-character reason code stands for. No code at
    /// all — the ordinary ⌘Q — is the teacher's own.
    static func reason(forQuitReasonCode code: OSType?) -> Reason {
        guard let code else {
            return .theTeacherAskedToQuit
        }
        for systemCode in systemQuitReasonCodes {
            if systemCode == code {
                return .theMacIsLoggingOutOrShuttingDown
            }
        }
        return .theTeacherAskedToQuit
    }

    /// Why this quit is happening, for the `app closed` line (#560).
    ///
    /// The Apple event's quit reason wins, because it is the system saying
    /// so: the same six codes `systemQuitReasonCodes` lists, split three
    /// ways. Then `installingAnUpdate` — true only once the app itself has
    /// handed the installer the teacher's Install (`AppUpdates.isQuittingToInstall`).
    /// Anything else, the Dock's Quit and a scripted quit included, arrives
    /// as the same request ⌘Q makes and is the teacher's.
    static func closingReason(quitReasonCode code: OSType?, installingAnUpdate: Bool) -> ClosingReason {
        if let code {
            if code == OSType(kAELogOut) || code == OSType(kAEReallyLogOut) {
                return .theMacIsLoggingOut
            }
            if code == OSType(kAEShowRestartDialog) || code == OSType(kAERestart) {
                return .theMacIsRestarting
            }
            if code == OSType(kAEShowShutdownDialog) || code == OSType(kAEShutDown) {
                return .theMacIsShuttingDown
            }
        }
        if installingAnUpdate {
            return .toInstallANewVersion
        }
        return .quitByTheTeacher
    }

    /// The question itself.
    static func question(about workUnderWay: String) -> String {
        return "Plantoir is still \(workUnderWay)."
    }

    /// The sentence under it, for whatever is under way right now.
    ///
    /// Reads its own facts for the same reason `workUnderWay()` does: the
    /// delegate asks one question and gets the sentence that belongs to it,
    /// so the question and its explanation are chosen from the same record
    /// at the same moment. A publish wins here exactly as it does there.
    static func explanation() -> String {
        let kinds: Kinds = Kinds.of(
            publishes: CourseActivity.activePublishes, planWork: CourseActivity.activePlanWork
        )
        if let message = kinds.message() {
            return message
        }
        return explanation(publishing: false)
    }

    /// `parts` joined as a teacher reads a list: one alone, two as "A and
    /// B", more as "A, B and C".
    static func joined(_ parts: [String]) -> String {
        if parts.count <= 1 {
            return parts.first ?? ""
        }
        var text: String = ""
        for index in 0..<(parts.count - 1) {
            if index > 0 {
                text += ", "
            }
            text += parts[index]
        }
        return text + " and " + parts[parts.count - 1]
    }

    /// The message for the clauses that apply, or nil for none.
    static func message(clauses: [String]) -> String? {
        if clauses.isEmpty {
            return nil
        }
        let template: String = clauses.count == 1 ? messageOne : messageSeveral
        return template.replacingOccurrences(of: "{clauses}", with: joined(clauses))
    }

    /// The sentence under the question.
    ///
    /// "Could", not "would", and the difference is measured rather than
    /// cautious — in both directions, which is why this comment is long.
    ///
    /// **A publish.** Plantoir does not END the publish: it is a separate
    /// program, and `ScriptRunner.stopEveryLivePreview` deliberately passes it
    /// over. But it is a program writing to a pseudo-terminal the APP owned,
    /// and `deploy.sh` runs under `set -euo pipefail` (line 3), so when the app
    /// goes its next line of output fails and the publish stops there.
    /// Measured 2026-09-19, twice independently: two children of identical
    /// shape orphaned on a dead pty — the plain one ran to the end, the
    /// `set -euo pipefail` one died at its next `echo`, three ticks in.
    ///
    /// So "could leave it unfinished" is the honest sentence, and neither
    /// "would be stopped" nor "carries on" is. What a teacher loses either way
    /// is the watching: the console is gone and a question the publish asks is
    /// asked of nobody.
    ///
    /// **A preview being built (issue #232).** "Could" again, for the same
    /// two-sided reason: a section window's preview is a live preview and the
    /// quit path ends it, but the assistant's own rebuild (`--build-only`) is
    /// passed over like a publish and `preview.sh` has no `set -e`, so it may
    /// well run to its end on the dead terminal — the plain child in the
    /// measurement above. What is true either way is that nothing a student
    /// can see is touched. It deliberately promises nothing about the next
    /// time: nothing starts a preview when a window opens, so "it is built
    /// again next time" would be a promise the app does not keep.
    static func explanation(publishing: Bool) -> String {
        if publishing {
            return "Quitting now could leave it unfinished, with the class website "
                + "part way updated."
        }
        return "Quitting now could leave it unfinished. Nothing on the class "
            + "website changes."
    }

    /// What the button at a given position means — read from the same list
    /// the alert builds itself from, so the two cannot disagree.
    static func choice(atButtonIndex index: Int) -> Choice {
        if index >= 0 && index < buttonsInOrder.count {
            return buttonsInOrder[index].choice
        }
        // An answer nobody recognises is the safe one.
        return .keepWorking
    }

    /// The line the trail gets, whichever way it went.
    static func trailLine(workUnderWay: String, choice: Choice) -> String {
        let answer: String = choice == .quitAnyway
            ? "chose to quit anyway"
            : "chose to keep working"
        return "asked whether to quit while still \(workUnderWay), and the teacher \(answer)"
    }
}
