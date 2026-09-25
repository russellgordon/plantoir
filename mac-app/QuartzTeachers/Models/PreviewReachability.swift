import Foundation

/// What to do about a preview that said its website was up and then never
/// appeared — and how to tell the two reasons for that apart.
///
/// **The fault this exists for.** A teacher on a second Mac pressed Preview,
/// watched the progress bar fill, read "Started a Quartz server listening at
/// …" in the console, and then watched nothing happen at all. The website was
/// built and it was being served; that Mac had simply stopped passing new
/// addresses through from the website builder, six weeks after the builder
/// was last restarted. Plantoir waited ten minutes, said nothing, wrote
/// nothing on the trail, and left the section looking as though it were still
/// building. Three previews were abandoned that way in four minutes
/// (GitHub issue #225).
///
/// **The question that separates the two reasons is cheap and it is
/// provable.** The website builder can be asked whether the site answers
/// INSIDE it. If it does, and this Mac still cannot reach the same site, then
/// nothing is wrong with the teacher's pages and nothing Plantoir can do will
/// help — the sentence says so and says what does help. If nothing answers
/// anywhere, the site was never served, which is a different sentence.
/// MEASURED on this development Mac, 2026-09-20: one such question costs
/// **0.03 s** (five runs, `docker exec … curl`), and on a healthy Mac the gap
/// between the site answering inside the builder and answering out here is
/// **0.026 s**.
nonisolated enum PreviewReachability {

    // MARK: - Types

    /// What came back when the builder was asked, which is not the same
    /// question as what to tell the teacher.
    ///
    /// **The third case is the one that was missing**, and leaving it out
    /// made the app assert something it had not found out. Everything that is
    /// not a site answering — the programs not being where they were looked
    /// for, the builder no longer being there, an engine that never replied
    /// inside the question's own deadline — came back as "your website did
    /// not come up", which a teacher can read as false with their own eyes:
    /// `Started a Quartz server listening at …` is in the console directly
    /// above the sentence.
    enum Answer {

        /// The site answered inside the builder.
        case theSiteAnswered

        /// The question was asked and got a reply, and the reply was not a
        /// site: nothing is serving it in there.
        case nothingAnsweredInside

        /// The question could not be put, or nothing came back from putting
        /// it. Plantoir does not know, and says so.
        case couldNotFindOut
    }

    /// Which of the three things happened, once the waiting has stopped.
    enum Verdict {

        /// The website builder is serving the site and this Mac cannot reach
        /// it. The teacher's pages are fine; their Mac is not.
        case thisMacCannotReachIt

        /// Nothing answered anywhere — inside the builder either. The site
        /// was never served, so there was nothing to reach.
        case theSiteNeverAnswered

        /// Plantoir stopped waiting and could not find out which of the two
        /// it was.
        case plantoirCouldNotTell
    }

    /// What the preview wait does next, once the build is behind it.
    enum NextStep: Equatable {

        /// Ask this Mac for the site at the address the launcher announced.
        case tryTheAddress(URL)

        /// Nothing to try yet, and nothing has gone wrong yet either.
        case keepWaiting

        /// The builder has said its server is up and no address for it was
        /// ever announced: there is nothing to try, nothing to ask the
        /// builder about, and nothing left to wait for.
        case stopBecauseNothingWasAnnounced
    }

    /// How long a run has been saying nothing.
    ///
    /// A run that is still printing is not stalled, however long it has been
    /// going: a first-ever preview legitimately takes minutes (109 s and
    /// 132 s, measured on the Mac that met issue #225). What cannot be
    /// explained is a run that has announced its server, then says nothing
    /// AND answers nothing. Bounding that quiet, rather than the run, is what
    /// lets the bound be short without ever firing on a slow course.
    struct Silence {

        // MARK: - Stored properties

        /// How much had been said when the run last said something.
        private var charactersWhenItLastSaidSomething: Int

        /// When that was.
        private var whenItLastSaidSomething: Date

        // MARK: - Initializer

        init(charactersSoFar: Int, at moment: Date) {
            charactersWhenItLastSaidSomething = charactersSoFar
            whenItLastSaidSomething = moment
        }

        // MARK: - Functions

        /// Notes how much the run has said by now, which restarts the clock
        /// if that is more than last time.
        mutating func note(charactersSoFar: Int, at moment: Date) {
            if charactersSoFar != charactersWhenItLastSaidSomething {
                charactersWhenItLastSaidSomething = charactersSoFar
                whenItLastSaidSomething = moment
            }
        }

        /// How long the run has said nothing.
        func secondsOfSilence(at moment: Date) -> Int {
            let seconds: Double = moment.timeIntervalSince(whenItLastSaidSomething)
            if seconds < 0 {
                return 0
            }
            return Int(seconds)
        }

        /// Whether it has said nothing for long enough to stop waiting.
        func hasGoneQuiet(forSeconds allowed: Int, at moment: Date) -> Bool {
            return secondsOfSilence(at: moment) >= allowed
        }
    }

    // MARK: - Stored properties

    /// How long a preview may say nothing, and answer nothing, after the
    /// builder has said its server started — before Plantoir stops waiting
    /// and says what it found.
    ///
    /// **Chosen from measurement, not from taste.** Once that line is
    /// printed the server is already listening, so everything left is
    /// Plantoir's own once-a-second polling (at most 2 s) and the hop out of
    /// the builder onto this Mac, MEASURED at 0.026 s on this development Mac
    /// on 2026-09-20. Forty-five seconds is more than twenty times the whole
    /// healthy interval, and it is asked of a run that is ALSO saying
    /// nothing, so a slow course cannot trip it — a course still emitting
    /// pages restarts the clock with every line. It replaces a ten-minute
    /// wait that ended in silence.
    ///
    /// This is an intentional deadline, not a delay waiting for something to
    /// settle: at the end of it a question is asked and answered.
    static let secondsOfSilenceBeforeGivingUp: Int = 45

    /// What the builder prints when its server is up. The words are Quartz's
    /// and they are matched loosely — the version number and the address that
    /// follow are not part of the test.
    static let theBuilderSaysItsServerStarted: String = "Started a Quartz server"

    /// The address used in place of the real one when Plantoir is being shown
    /// this fault on purpose. Port 1 is reserved and nothing listens there.
    static let anAddressNothingAnswersAt: URL = URL(string: "http://127.0.0.1:1/")!

    /// Setting this in the environment makes Plantoir look for the preview at
    /// an address nothing answers at, while the question it puts to the
    /// website builder stays real — which is the fault of issue #225,
    /// reproduced on a healthy Mac.
    ///
    /// **It cannot be reached by accident, twice over.** It is compiled into
    /// debug builds only, so no teacher's copy contains it at all; and an app
    /// opened from the Dock or from Finder normally inherits no such variable
    /// (one would have to be put there deliberately with `launchctl setenv`),
    /// so even a debug build only sees it when somebody starts the binary
    /// from a terminal with the variable set:
    ///
    /// ```
    /// PLANTOIR_PRETEND_THIS_MAC_CANNOT_REACH_THE_PREVIEW=1 \
    ///   ~/Library/Developer/Xcode/DerivedData/Plantoir-euwbmkpykeyuztbpzedmiptcsqsg/Build/Products/Debug/Plantoir.app/Contents/MacOS/Plantoir
    /// ```
    static let pretendingVariableName: String = "PLANTOIR_PRETEND_THIS_MAC_CANNOT_REACH_THE_PREVIEW"

    // MARK: - Functions

    /// Whether this run of Plantoir has been asked to pretend the preview
    /// cannot be reached. Always false in a release build.
    static func isPretendingThisMacCannotReachIt(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG
        return environment[pretendingVariableName] == "1"
        #else
        return false
        #endif
    }

    /// The address this Mac should try — the one the builder announced,
    /// unless Plantoir has been asked to pretend it cannot be reached.
    static func addressToTry(
        announced: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if isPretendingThisMacCannotReachIt(environment: environment) {
            return anAddressNothingAnswersAt
        }
        return announced
    }

    /// The question itself, as a line of `sh`.
    ///
    /// The port is the one INSIDE the builder (the section's leased port),
    /// never the one this Mac was told to use: the two differ for every
    /// working folder after the first, and asking the builder about a host
    /// port would be asking it about a site it has never heard of.
    ///
    /// **It carries its own deadline**, the way the quit script does
    /// (`FolderContainers.quitScript`), and for the same reason: the question
    /// is asked at the one moment a teacher is already waiting, so a `docker`
    /// talking to an engine that is not answering must not become the new way
    /// of saying nothing. `curl` is bounded too, but only `curl` — a client
    /// that never reaches the engine is not.
    static func askTheBuilderScript(
        containerName: String,
        portInsideTheBuilder: Int,
        secondsForTheQuestion: Int = 3,
        secondsBeforeGivingUpOnTheQuestion: Int = 10
    ) -> String {
        var lines: [String] = []
        lines.append(
            "docker exec " + HelperPrograms.shellQuoted(containerName)
            + " curl --silent --output /dev/null --write-out '%{http_code}'"
            + " --max-time \(secondsForTheQuestion)"
            + " http://localhost:\(portInsideTheBuilder)/ & question=$!"
        )
        lines.append(
            "( sleep \(secondsBeforeGivingUpOnTheQuestion); kill -9 \"$question\" 2>/dev/null )"
            + " >/dev/null 2>&1 & guard=$!"
        )
        lines.append("wait \"$question\"")
        lines.append("kill \"$guard\" 2>/dev/null")
        return lines.joined(separator: "\n")
    }

    /// Asking the website builder whether the site answers inside it, as a
    /// value — so a test can read exactly what would be run without anything
    /// being started, the way `PreviewStopper.stopCommand` does.
    ///
    /// `/bin/sh`, with `HelperPrograms.environment()` for the same reason
    /// every other helper here has it: an app opened from the Dock has no
    /// `docker` on its path at all (issue #220), so a question asked without
    /// it could never be PUT on a teacher's Mac — every teacher would get the
    /// "could not tell" sentence, and the one case Plantoir can actually
    /// prove would never be reached.
    static func askTheBuilderCommand(
        containerName: String,
        portInsideTheBuilder: Int,
        inheriting inherited: [String: String] = ProcessInfo.processInfo.environment,
        inHomeFolder homeFolder: URL = RealHome.forFiles
    ) -> HelperPrograms.Command {
        return HelperPrograms.Command(
            executablePath: "/bin/sh",
            arguments: ["-c", askTheBuilderScript(
                containerName: containerName,
                portInsideTheBuilder: portInsideTheBuilder
            )],
            environment: HelperPrograms.environment(basedOn: inherited, inHomeFolder: homeFolder),
            currentDirectoryPath: nil
        )
    }

    /// What came back, read as one of the three things it can mean.
    ///
    /// MEASURED, 2026-09-20, with the generated script against real
    /// containers: a site being served prints `200` (0.03 s); a port with
    /// nothing on it prints `000` (0.04 s), because that is what `curl`
    /// writes when nothing replied; and a container that is not there prints
    /// NOTHING at all, its complaint going to the error channel, which is
    /// discarded. An engine that never answers is the same empty answer,
    /// arriving at the question's own deadline (10.05 s, measured by the
    /// reviewer against a stub). So an empty or unrecognisable answer is
    /// "could not find out" and a three-digit reply is the builder speaking.
    static func answer(from printed: String) -> Answer {
        let trimmed: String = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "200" {
            return .theSiteAnswered
        }
        var digits: Int = 0
        for character in trimmed {
            if character.isNumber {
                digits += 1
            }
        }
        if digits == 3 && digits == trimmed.count {
            return .nothingAnsweredInside
        }
        return .couldNotFindOut
    }

    /// Puts the question to the builder and waits for the answer.
    ///
    /// Off the main actor, because it runs a program and reads its output —
    /// the same `Task.detached` the rest of the app uses for work that
    /// blocks. The script's own watchdog is what guarantees this returns.
    static func askTheBuilder(_ command: HelperPrograms.Command) async -> Answer {
        let answer: String = await Task.detached(priority: .userInitiated) {
            let process: Process = Process()
            process.executableURL = URL(fileURLWithPath: command.executablePath)
            process.arguments = command.arguments
            process.environment = command.environment
            let output: Pipe = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return ""
            }
            let printed: Data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: printed, encoding: .utf8) ?? ""
        }.value
        return PreviewReachability.answer(from: answer)
    }

    /// What the wait does next.
    ///
    /// **There is no road from "no address" to a port.** The wait used to
    /// start from `http://127.0.0.1:<the section's port>/`, and that port is
    /// the one INSIDE the builder: this Mac's own working folder publishes
    /// 8091 for the builder's 8081, so the guess was wrong for every working
    /// folder after the first, and a guess can land on ANOTHER section's
    /// preview and show it as this one (GitHub #235).
    ///
    /// And once the builder has said its server started, a missing address
    /// is final rather than late. The launcher announces the address BEFORE
    /// it starts the build, and output is read in the order it arrives, so
    /// by the time Quartz's line is in, any announcement is already in too.
    /// Waiting on would reach the ten-minute bound with the run still going
    /// — the "still building for ever" state `stopWaitingForThePreview`
    /// exists to prevent.
    ///
    /// **A preview the teacher has just stopped is never reported.** Stop
    /// only signals the run; it is still "running" until it has actually
    /// ended, so a wait that wakes in between would otherwise raise "your
    /// preview did not appear" over a preview they ended themselves (the
    /// review of #235). It waits instead, and the next turn finds the run
    /// over — the same way every other ending of the wait is noticed.
    static func nextStep(
        announced: URL?,
        theBuilderSaysItsServerStarted: Bool,
        theTeacherStoppedIt: Bool
    ) -> NextStep {
        if let announced {
            return .tryTheAddress(announced)
        }
        if theTeacherStoppedIt {
            return .keepWaiting
        }
        if theBuilderSaysItsServerStarted {
            return .stopBecauseNothingWasAnnounced
        }
        return .keepWaiting
    }

    /// What the teacher is told when no address was ever announced.
    ///
    /// The third sentence, not a new one: it is exactly true. Plantoir could
    /// not get the site to appear, and it cannot tell why — the builder is
    /// NOT asked, because the question is about an address and there is none
    /// to ask about.
    static let verdictWhenNothingWasAnnounced: Verdict = .plantoirCouldNotTell

    /// Which of the three things happened.
    static func verdict(for answer: Answer) -> Verdict {
        switch answer {
        case .theSiteAnswered:
            return .thisMacCannotReachIt
        case .nothingAnsweredInside:
            return .theSiteNeverAnswered
        case .couldNotFindOut:
            return .plantoirCouldNotTell
        }
    }

    /// Whether what was just found out still belongs to the run it was found
    /// out about.
    ///
    /// The question takes a moment (0.1 s normally, up to its own ten-second
    /// deadline when nothing replies), and a teacher can press Stop or close
    /// the window inside it. Without this the app puts an alert in front of
    /// them about a preview they have already ended, and writes a line on the
    /// trail for a run that stopped because they asked it to — which is
    /// exactly the misreading the trail line was added to prevent, arriving
    /// from the other direction.
    ///
    /// The run is identified by WHEN IT STARTED, not by whether something is
    /// running now: stopping this preview and starting another leaves a
    /// runner that is running, was not stopped by anybody, and is a different
    /// run.
    static func isStillTheSameWait(
        startedAt: Date?,
        theRunNowStartedAt: Date?,
        theTeacherStoppedIt: Bool,
        theRunIsStillGoing: Bool
    ) -> Bool {
        if theTeacherStoppedIt || !theRunIsStillGoing {
            return false
        }
        return startedAt == theRunNowStartedAt
    }

    /// Whether the run the question was about ENDED ON ITS OWN while the
    /// question was out — the one reason `isStillTheSameWait` says no that
    /// nobody else has dealt with (issue #232).
    ///
    /// Stop, Cancel and a closed window each end the window's wait as they
    /// happen, and a new run begins its own; but a run that simply finished
    /// leaves the wait, and with it ⌘Q's record of a preview being built,
    /// for whoever returns next — and the caller returns next. So the caller
    /// ends the wait when this says yes, and ONLY then: when a new run has
    /// started, the wait belongs to it.
    static func theSameRunEndedByItself(
        startedAt: Date?,
        theRunNowStartedAt: Date?,
        theTeacherStoppedIt: Bool,
        theRunIsStillGoing: Bool
    ) -> Bool {
        if theTeacherStoppedIt || theRunIsStillGoing {
            return false
        }
        return startedAt == theRunNowStartedAt
    }

    /// What the teacher is told.
    ///
    /// Plain words, and none of the machinery (rule 1): no port, no
    /// container, no virtual machine, nothing being forwarded. The first
    /// sentence says what is true of THEIR pages, because that is the thing
    /// they are afraid of; the last says what to do.
    ///
    /// Restarting the Mac is the advice because it is the remedy that was
    /// MEASURED to work on the Mac that met this — a reboot cured it.
    /// REJECTED: offering to restart the website builder from inside
    /// Plantoir. Another window, another copy of Plantoir, or an outside
    /// assistant can be publishing in the same builder without this app
    /// knowing (nothing on the mac records a publish across processes), and
    /// whether restarting it even replaces the stale plumbing underneath was
    /// never measured — so the button would risk somebody else's publish to
    /// deliver a cure nobody had seen work.
    static func sentence(for verdict: Verdict) -> String {
        switch verdict {
        case .thisMacCannotReachIt:
            return "Your website is built, and your website builder is serving it — "
                 + "but this Mac cannot reach it.\n\n"
                 + "Nothing is wrong with your pages. Something on this Mac has stopped "
                 + "passing your website through. Restarting your Mac puts it right."
        case .theSiteNeverAnswered:
            return "Your website did not come up, so Plantoir stopped waiting for it.\n\n"
                 + "Nothing has been lost. Press Preview to try again — and if it "
                 + "happens again, restarting your Mac usually puts it right."
        case .plantoirCouldNotTell:
            return "Plantoir could not get your website to appear, and could not tell why.\n\n"
                 + "Nothing has been lost. Press Preview to try again — and if it happens "
                 + "again, choose “Report a Problem…” from the Help menu so somebody can "
                 + "see what happened."
        }
    }

    /// What the alert above the sentence is called.
    ///
    /// True of all three outcomes, and it does not promise that waiting will
    /// help: the shared "Cannot Preview Yet" title this used to borrow reads
    /// as "wait and it will work" in front of a sentence whose remedy is
    /// restarting the Mac.
    static let alertTitle: String = "Your Preview Did Not Appear"

    /// The line the trail gets: a sentence a teacher would recognise as what
    /// just happened to them, with the thing support needs to know — WHICH of
    /// the three it was, and how long was spent finding out.
    static func trailLine(for verdict: Verdict, secondsOfSilence: Int) -> String {
        let waited: String = "after \(secondsOfSilence) seconds of nothing happening"
        switch verdict {
        case .thisMacCannotReachIt:
            return "the preview never appeared \(waited) — the website builder was "
                 + "serving the site and this Mac could not reach it"
        case .theSiteNeverAnswered:
            return "the preview never appeared \(waited) — nothing was serving the site"
        case .plantoirCouldNotTell:
            return "the preview never appeared \(waited) — and the website builder could "
                 + "not be asked whether it was serving the site"
        }
    }

    /// The trail's line for a preview that never said where it would be.
    ///
    /// Its own line rather than `trailLine(for:secondsOfSilence:)`'s third,
    /// because that one would say two untrue things: nothing waited out any
    /// silence, and nobody tried to ask the builder anything.
    static let trailLineWhenNothingWasAnnounced: String =
        "the preview never appeared — its website started, but no address for it "
        + "was ever announced, so there was nothing to open"
}
