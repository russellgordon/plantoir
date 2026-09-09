import Foundation

/// What happened to a publish that was set to happen on its own, kept where
/// the app can find it the next time the teacher opens Plantoir.
///
/// A scheduled publish runs at half six in the morning with the app closed.
/// Until this existed, a run that did not get through said so in the section's
/// own log and nowhere else — so "my site did not update on Tuesday and I do
/// not know why" had no answer, and a run that stopped was indistinguishable
/// from one that was never scheduled.
///
/// **Every outcome is recorded, not only the unanswered question.** Russell's
/// decision on 2026-09-09 was that a teacher should learn their overnight
/// publish did not happen whatever the reason — a revoked token, a network
/// that was down, a build that failed — because the silence is the complaint,
/// not the cause. A run that got through is recorded for the same reason read
/// the other way round.
///
/// Where this stands against Windows is compared in ONE place and deliberately
/// not restated here, because a sentence naming what the other app does today
/// is stale the week after it is written: `contracts/shared-rules.json` →
/// `scheduledPublishStopped` → `platformDifferences`.
///
/// The record is per SECTION and holds the FIRST destination that stopped. A
/// course can publish to several places and only one may have gone wrong, so
/// "it published to the folder and not to Netlify" is the shape of the report;
/// overwriting would tell the teacher about the last thing that went wrong
/// rather than the first.
nonisolated enum ScheduledPublishOutcome {

    // MARK: - Types

    /// How a scheduled publish turned out.
    ///
    /// The two FAILURE kinds are the two a launcher can tell apart without
    /// guessing: `deploy.sh` and `deploy.py` exit **3** when a question went
    /// unanswered and **1** for everything else. `buildNeededAnAnswer` splits
    /// the first of those by WHICH LEG stopped, because a scheduled publish
    /// builds before it publishes and the two legs send a teacher to two
    /// different buttons. The list here and the one in
    /// `contracts/shared-rules.json` → `scheduledPublishStopped` → `kinds` are
    /// pinned against each other by a test, so a kind added on one platform
    /// cannot be missed on the other.
    enum Kind: String, Sendable, CaseIterable {

        /// Exit 3 from a DESTINATION — a question was asked of nobody.
        case neededAnAnswer = "needed an answer"

        /// Exit 3 from the BUILD, before any destination was reached.
        ///
        /// Proposed from Windows on 2026-09-09 (GitHub issue #132) and adopted
        /// here the same day. A scheduled publish builds before it publishes,
        /// and `preview.sh` has a question of its own — the 'Open' course-code
        /// guard — so under `--non-interactive` it refuses with the same exit 3
        /// having contacted nothing.
        ///
        /// A SEPARATE kind rather than `neededAnAnswer` with a stand-in
        /// destination, which is what this side did until #132: there is no
        /// destination to name, and telling a teacher that publishing to
        /// Netlify needed an answer when Netlify was never reached sends them
        /// to look in the wrong place. The sentence sends them to **Preview**
        /// instead, because previewing is what asks the question.
        ///
        /// REJECTED, and recorded so it is not proposed again: filling the
        /// destination in with the section's first configured one. It reads
        /// correctly and it is false.
        case buildNeededAnAnswer = "build needed an answer"

        /// Any other non-zero exit.
        case didNotFinish = "did not finish"

        /// It worked.
        ///
        /// Recorded for the same reason the failures are, and the reason is
        /// the same sentence read the other way round: a scheduled publish
        /// that leaves NO trace cannot be told from one that never happened.
        /// A teacher who wonders whether last night's publish went out has
        /// nowhere to look, and "it did" is an answer worth having.
        case succeeded = "succeeded"

        /// Whether this is something the teacher should be chased about.
        ///
        /// All three failures are; a success is news rather than a problem, so it
        /// gets the sentence in the section and NOT a warning badge in the
        /// sidebar. A badge on every section that published fine overnight is
        /// a badge nobody reads by Wednesday.
        var needsAttention: Bool {
            switch self {
            case .neededAnAnswer, .buildNeededAnAnswer, .didNotFinish:
                return true
            case .succeeded:
                return false
            }
        }
    }

    /// One stopped run, as it was written down.
    struct Stopped: Equatable, Sendable {

        // MARK: - Stored properties

        let kind: Kind
        let destination: String
        let when: Date
    }

    // MARK: - Stored properties

    /// The file's first line is the kind, the second the destination. A plain
    /// text file rather than JSON because a shell wrapper writes it at half
    /// six with no interpreter of ours running, and two `echo` lines cannot go
    /// wrong the way a quoted JSON document can.
    static let recordSeparator: String = "\n"

    /// What the record calls the build, when the BUILD is what stopped.
    ///
    /// A scheduled publish builds before it publishes, so a run can stop
    /// before any destination is reached. For a build that failed OUTRIGHT
    /// this stands in for a destination in the teacher's sentence, so it has
    /// to read naturally in "publishing to ___ stopped".
    ///
    /// For `buildNeededAnAnswer` it is written to the record and never shown:
    /// that sentence names no destination, because there was none. The line is
    /// still written so every record has ONE shape — two lines, the kind and
    /// then a name — which is what `stopped(inHomeFolder:course:section:)`
    /// reads and what a person opening the file in TextEdit sees. A record
    /// whose second line was sometimes absent would be a second format for a
    /// shell script to get right at half six in the morning.
    static let buildDestinationName: String = "your website (it could not be built)"

    // MARK: - Functions

    /// Where stopped runs are kept, for a given home folder.
    ///
    /// A pure function of the home folder so a test can point it somewhere
    /// harmless instead of writing into the teacher's real Application
    /// Support — the same reason `BuildOutputLocation.buildsRoot` takes one.
    ///
    /// Named `stopped` where Windows says `unanswered`, because this side
    /// records more than unanswered questions. The paths are platform-local
    /// and were never shared; what is shared is the BEHAVIOUR, which the
    /// contract carries.
    static func directory(inHomeFolder home: URL) -> URL {
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("scheduled")
            .appendingPathComponent("stopped")
    }

    /// The file that stands for one section.
    static func recordURL(inHomeFolder home: URL, course: String, section: Int) -> URL {
        return directory(inHomeFolder: home)
            .appendingPathComponent("\(course)-section\(section).txt")
    }

    /// Write down that a scheduled publish stopped, unless one is already
    /// written for this section.
    ///
    /// The FIRST destination that stopped is the one kept; see the note on the
    /// type. Returns whether anything was written, so a caller can tell "the
    /// first leg failed" from "another leg had already failed".
    @discardableResult
    static func recordStopped(
        _ stopped: Stopped,
        inHomeFolder home: URL,
        course: String,
        section: Int
    ) -> Bool {
        let url: URL = recordURL(inHomeFolder: home, course: course, section: section)
        if FileManager.default.fileExists(atPath: url.path) {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: directory(inHomeFolder: home), withIntermediateDirectories: true
            )
            let body: String = stopped.kind.rawValue + recordSeparator + stopped.destination
            try body.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            // A record that cannot be written must not take the publish down
            // with it: the run has already finished by the time this is
            // called, and losing the note is better than losing the site.
            return false
        }
    }

    /// What is written down for this section, if anything.
    ///
    /// The date comes from the FILE, not from the app: it is when the run
    /// wrote its record, and reading it later must not re-date an overnight
    /// problem to the morning somebody noticed it.
    static func stopped(inHomeFolder home: URL, course: String, section: Int) -> Stopped? {
        let url: URL = recordURL(inHomeFolder: home, course: course, section: section)
        guard let body = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var lines: [String] = []
        for piece in body.components(separatedBy: recordSeparator) {
            lines.append(piece.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard lines.count >= 2, let kind = Kind(rawValue: lines[0]), !lines[1].isEmpty else {
            return nil
        }
        let attributes: [FileAttributeKey: Any]? =
            try? FileManager.default.attributesOfItem(atPath: url.path)
        let when: Date = (attributes?[.modificationDate] as? Date) ?? Date()
        return Stopped(kind: kind, destination: lines[1], when: when)
    }

    /// Forget a stopped run.
    ///
    /// Called from two places, and the second is a decision rather than a
    /// convenience: a run that got all the way through clears it, AND the
    /// teacher can dismiss it by hand. Windows clears only on a successful
    /// run, which leaves the message standing after a teacher has already
    /// fixed the problem themselves — and the next scheduled run that would
    /// clear it could be a week away.
    static func clear(inHomeFolder home: URL, course: String, section: Int) {
        let url: URL = recordURL(inHomeFolder: home, course: course, section: section)
        try? FileManager.default.removeItem(at: url)
    }

    /// Put a stopped run on the breadcrumb trail.
    ///
    /// Called by the RUN — `ScheduledDeploy.runScheduled`, which is Plantoir
    /// itself under `--run-scheduled-deploy` — immediately after the wrapper
    /// finishes. That is why there is no "have I already noted this?" marker:
    /// the run writes the line once because the run happens once.
    ///
    /// An earlier draft had the app note it on opening the section, and it was
    /// wrong three ways at once. It needed a marker written back into the
    /// record, which changed the file's modification date and so made the
    /// notice show the morning the teacher opened it rather than the half six
    /// the run stopped at — the very thing the contract forbids. It skipped
    /// the trail entirely for a teacher who never opened that section, which
    /// is exactly the teacher who reports "my site did not update". And it
    /// rested on a false premise: that nothing of ours is loaded when the
    /// wrapper runs. Plantoir runs the wrapper.
    ///
    /// The line carries the course, the section and which destination stopped.
    /// NEVER the question's own text: that comes from a launcher's console,
    /// and a line naming a credential prompt would put a teacher's own words
    /// on the trail.
    @discardableResult
    static func noteOnTrail(inHomeFolder home: URL, course: String, section: Int) -> Bool {
        guard let stopped = stopped(inHomeFolder: home, course: course, section: section) else {
            return false
        }
        // One `ActivityTrail.note(.event, …)` per branch rather than a
        // variable passed to a single call. ActivityTrailWiringTests scans
        // product code for a visible call site — an event nothing can be seen
        // to record is an event nothing DOES record — and a variable hides it.
        // It also reads better: the branch and the sentence sit together.
        switch stopped.kind {
        case .neededAnAnswer:
            ActivityTrail.note(
                .scheduledPublishNeededAnAnswer,
                "a scheduled publish stopped, publishing to " + stopped.destination,
                course: course, section: section, at: stopped.when
            )
        case .buildNeededAnAnswer:
            // The SAME event as the branch above, deliberately: that event is
            // about a question going unasked, which is what happened. A fourth
            // event would put a distinction on the trail that means nothing to
            // the person reading it. Windows proposed it this way in issue
            // #132 and the reasoning holds here.
            //
            // The line names no destination because none was reached — see
            // `activityTrail.mustRecord` for that event, which says so.
            ActivityTrail.note(
                .scheduledPublishNeededAnAnswer,
                "a scheduled publish stopped — building the pages needed an answer",
                course: course, section: section, at: stopped.when
            )
        case .didNotFinish:
            ActivityTrail.note(
                .scheduledPublishDidNotFinish,
                "a scheduled publish stopped, publishing to " + stopped.destination,
                course: course, section: section, at: stopped.when
            )
        case .succeeded:
            ActivityTrail.note(
                .scheduledPublishFinished,
                "a scheduled publish finished, publishing to " + stopped.destination,
                course: course, section: section, at: stopped.when
            )
        }
        return true
    }

    /// The sentence a teacher reads.
    ///
    /// Every one of these is pinned against
    /// `contracts/shared-rules.json` → `scheduledPublishStopped` → `sentences`
    /// by `SharedRulesContractTests`, so both apps say one thing about one
    /// problem. They are retyped here rather than read from the contract at
    /// run time — the app ships the JSON but does not parse it to speak, and
    /// Windows retypes them too — which is why the test is the gate.
    static func sentence(for stopped: Stopped, course: String, section: Int) -> String {
        switch stopped.kind {
        case .neededAnAnswer:
            return "\(course) Section \(section) was set to publish on its own, and it stopped "
                 + "because publishing to \(stopped.destination) needed an answer nobody was "
                 + "there to give. Publish this section once yourself, answer the question, and "
                 + "it can publish on its own after that."
        case .buildNeededAnAnswer:
            // No destination, on purpose: none was reached. And it sends the
            // teacher to PREVIEW rather than Publish, because previewing is
            // what asks the question.
            return "\(course) Section \(section) was set to publish on its own, and it stopped "
                 + "before it started, because building the pages needed an answer nobody was "
                 + "there to give. Preview this section once yourself, answer the question, and "
                 + "it can publish on its own after that."
        case .didNotFinish:
            return "\(course) Section \(section) was set to publish on its own, and it did not "
                 + "finish — publishing to \(stopped.destination) stopped, so nothing went up "
                 + "there. Publish it yourself to see what happens."
        case .succeeded:
            return "\(course) Section \(section) published on its own to "
                 + "\(stopped.destination). Your students have the new pages."
        }
    }
}
