import XCTest
@testable import QuartzTeachers

/// A preview that said its website was up and never appeared — issue #225.
///
/// What a teacher met: three previews in four minutes, each one building
/// correctly, each one served correctly, none of them ever shown, and nothing
/// said or written down about any of it. These pin the three halves of the
/// fix that can be pinned without a Mac in the state that caused it: WHEN
/// Plantoir stops waiting, WHAT it asks before deciding why, and WHICH
/// sentence a teacher gets.
final class PreviewReachabilityTests: XCTestCase {

    // MARK: - Stored properties

    private let start: Date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - How long a preview may say nothing

    /// The clock is on the QUIET, and a run that is still printing keeps
    /// restarting it. This is the whole reason the bound can be 45 seconds
    /// without refusing a first preview, which legitimately takes minutes.
    func testOutputArrivingRestartsTheClock() {
        var silence: PreviewReachability.Silence = PreviewReachability.Silence(
            charactersSoFar: 100, at: start
        )
        XCTAssertFalse(silence.hasGoneQuiet(forSeconds: 45, at: start.addingTimeInterval(44)))
        XCTAssertTrue(silence.hasGoneQuiet(forSeconds: 45, at: start.addingTimeInterval(45)))

        // More was said at +44, so the run is not quiet at +80.
        silence.note(charactersSoFar: 180, at: start.addingTimeInterval(44))
        XCTAssertFalse(
            silence.hasGoneQuiet(forSeconds: 45, at: start.addingTimeInterval(80)),
            "A run that printed something 36 seconds ago has not gone quiet."
        )
        XCTAssertTrue(silence.hasGoneQuiet(forSeconds: 45, at: start.addingTimeInterval(89)))
    }

    /// Nothing new having been said is not the same as nothing having been
    /// heard from: the same character count must not restart the clock.
    func testTheSameOutputDoesNotRestartTheClock() {
        var silence: PreviewReachability.Silence = PreviewReachability.Silence(
            charactersSoFar: 100, at: start
        )
        silence.note(charactersSoFar: 100, at: start.addingTimeInterval(40))
        XCTAssertTrue(silence.hasGoneQuiet(forSeconds: 45, at: start.addingTimeInterval(45)))
        XCTAssertEqual(silence.secondsOfSilence(at: start.addingTimeInterval(45)), 45)
    }

    /// A clock read before it started never reports a negative wait — the
    /// trail line quotes this number.
    func testSecondsOfSilenceIsNeverNegative() {
        let silence: PreviewReachability.Silence = PreviewReachability.Silence(
            charactersSoFar: 0, at: start
        )
        XCTAssertEqual(silence.secondsOfSilence(at: start.addingTimeInterval(-10)), 0)
    }

    // MARK: - What is asked, and of whom

    /// The question goes to the builder about the port INSIDE it. The host
    /// port differs for every working folder after the first (8091 → 8081 on
    /// this development Mac), so asking the builder about the host port asks
    /// it about a site it has never heard of — and the answer, "no", is the
    /// sentence that blames the teacher's pages.
    func testTheBuilderIsAskedAboutItsOwnPort() {
        let command: HelperPrograms.Command = PreviewReachability.askTheBuilderCommand(
            containerName: "teaching-quartz-abcd1234",
            portInsideTheBuilder: 8082,
            inheriting: ["PATH": "/usr/bin:/bin"],
            inHomeFolder: URL(fileURLWithPath: "/Users/someone")
        )
        XCTAssertEqual(command.executablePath, "/bin/sh")
        let script: String = command.arguments.last ?? ""
        XCTAssertTrue(script.contains("docker exec 'teaching-quartz-abcd1234'"), script)
        XCTAssertTrue(script.contains("http://localhost:8082/"), script)
        XCTAssertTrue(script.contains("%{http_code}"), script)
        XCTAssertTrue(script.contains("--max-time 3"), script)
    }

    /// The question carries its own deadline, because it is asked at the one
    /// moment a teacher is already waiting: an engine that never answers must
    /// not become the new way of saying nothing.
    func testTheQuestionCannotHangForEver() {
        let script: String = PreviewReachability.askTheBuilderScript(
            containerName: "teaching-quartz-abcd1234", portInsideTheBuilder: 8081
        )
        XCTAssertTrue(script.contains("sleep 10"), script)
        XCTAssertTrue(script.contains("kill -9"), script)
    }

    /// An app opened from the Dock has `PATH=/usr/bin:/bin:/usr/sbin:/sbin`
    /// and no `docker` on it at all (issue #220). A question asked without
    /// `HelperPrograms`' environment comes back with nothing on every
    /// teacher's Mac, and nothing means the third sentence — Plantoir could
    /// not tell — where the first, useful one was the truth.
    func testTheQuestionIsAskedWhereDockerActuallyIs() {
        let home: URL = URL(fileURLWithPath: "/Users/someone")
        let command: HelperPrograms.Command = PreviewReachability.askTheBuilderCommand(
            containerName: "teaching-quartz-abcd1234",
            portInsideTheBuilder: 8081,
            inheriting: ["PATH": "/usr/bin:/bin"],
            inHomeFolder: home
        )
        XCTAssertEqual(
            command.environment["PATH"],
            HelperPrograms.pathValue(inheriting: "/usr/bin:/bin", inHomeFolder: home)
        )
    }

    /// Three answers, not two — and the third is the one that was missing.
    /// MEASURED with the generated script: a served site prints `200`, a port
    /// with nothing on it prints `000`, and a container that is not there
    /// prints nothing at all (its complaint goes to the error channel, which
    /// is discarded), which is also what a ten-second watchdog leaves behind.
    func testTheThreeAnswersAreToldApart() {
        XCTAssertEqual(PreviewReachability.answer(from: "200"), .theSiteAnswered)
        XCTAssertEqual(PreviewReachability.answer(from: "200\n"), .theSiteAnswered)
        XCTAssertEqual(PreviewReachability.answer(from: "000"), .nothingAnsweredInside)
        XCTAssertEqual(PreviewReachability.answer(from: "404"), .nothingAnsweredInside)
        XCTAssertEqual(PreviewReachability.answer(from: ""), .couldNotFindOut)
        XCTAssertEqual(PreviewReachability.answer(from: "\n"), .couldNotFindOut)
        XCTAssertEqual(
            PreviewReachability.answer(from: "Error response from daemon: No such container"),
            .couldNotFindOut
        )
    }

    /// An answer that never arrived must not be reported as "your website did
    /// not come up": the teacher can read `Started a Quartz server listening
    /// at …` in the console directly above the sentence.
    func testNotFindingOutIsNeverReportedAsAFailedWebsite() {
        XCTAssertEqual(
            PreviewReachability.verdict(for: .couldNotFindOut), .plantoirCouldNotTell
        )
        XCTAssertNotEqual(
            PreviewReachability.sentence(for: .plantoirCouldNotTell),
            PreviewReachability.sentence(for: .theSiteNeverAnswered)
        )
        XCTAssertFalse(
            PreviewReachability.sentence(for: .plantoirCouldNotTell)
                .contains("did not come up"),
            "It did not find out whether the website came up, so it must not say it did not."
        )
    }

    /// An answer that arrives after the teacher has stopped the preview, or
    /// closed the window, or started another one, belongs to nothing that is
    /// still on screen — no alert about it, no line on the trail.
    func testAnAnswerAboutAFinishedRunIsNotActedOn() {
        let ranFrom: Date = start
        XCTAssertTrue(PreviewReachability.isStillTheSameWait(
            startedAt: ranFrom, theRunNowStartedAt: ranFrom,
            theTeacherStoppedIt: false, theRunIsStillGoing: true
        ))
        XCTAssertFalse(PreviewReachability.isStillTheSameWait(
            startedAt: ranFrom, theRunNowStartedAt: ranFrom,
            theTeacherStoppedIt: true, theRunIsStillGoing: false
        ), "The teacher pressed Stop while the builder was being asked.")
        XCTAssertFalse(PreviewReachability.isStillTheSameWait(
            startedAt: ranFrom, theRunNowStartedAt: ranFrom,
            theTeacherStoppedIt: false, theRunIsStillGoing: false
        ), "The run ended by itself while the builder was being asked.")
        XCTAssertFalse(PreviewReachability.isStillTheSameWait(
            startedAt: ranFrom, theRunNowStartedAt: start.addingTimeInterval(5),
            theTeacherStoppedIt: false, theRunIsStillGoing: true
        ), "A DIFFERENT preview is running now — it is running, and nobody stopped it.")
    }

    /// Of the endings above, only one is nobody's doing — the run finished by
    /// itself while the builder was being asked — and that one alone has to
    /// be ended by the question's caller, or the window's wait and ⌘Q's
    /// record of a preview being built outlive the run (issue #232).
    func testOnlyARunThatEndedByItselfIsEndedHere() {
        let ranFrom: Date = start
        XCTAssertTrue(PreviewReachability.theSameRunEndedByItself(
            startedAt: ranFrom, theRunNowStartedAt: ranFrom,
            theTeacherStoppedIt: false, theRunIsStillGoing: false
        ), "The run ended by itself while the builder was being asked.")
        XCTAssertFalse(PreviewReachability.theSameRunEndedByItself(
            startedAt: ranFrom, theRunNowStartedAt: ranFrom,
            theTeacherStoppedIt: true, theRunIsStillGoing: false
        ), "Stop already ended the wait.")
        XCTAssertFalse(PreviewReachability.theSameRunEndedByItself(
            startedAt: ranFrom, theRunNowStartedAt: start.addingTimeInterval(5),
            theTeacherStoppedIt: false, theRunIsStillGoing: false
        ), "A different run: the wait is not this question's to end.")
        XCTAssertFalse(PreviewReachability.theSameRunEndedByItself(
            startedAt: ranFrom, theRunNowStartedAt: start.addingTimeInterval(5),
            theTeacherStoppedIt: false, theRunIsStillGoing: true
        ), "A new run is going, and the wait belongs to it.")
        XCTAssertFalse(PreviewReachability.theSameRunEndedByItself(
            startedAt: ranFrom, theRunNowStartedAt: ranFrom,
            theTeacherStoppedIt: false, theRunIsStillGoing: true
        ), "Still the same wait — the caller goes on to say so, it does not end it here.")
    }

    /// And the view ends the wait on that path, before it returns. A source
    /// read, for the reason the test below gives.
    func testTheViewEndsTheWaitOfARunThatEndedByItself() throws {
        let function: String = try PreviewReachabilityTests.givingUpFunction()
        let checking: Int = try XCTUnwrap(
            function.range(of: "PreviewReachability.theSameRunEndedByItself("),
            "A run that ends by itself during the question leaves the wait, and ⌘Q's record, behind."
        ).lowerBound.utf16Offset(in: function)
        let ending: Int = try XCTUnwrap(
            function.range(of: "previewBuildWait.end()")
        ).lowerBound.utf16Offset(in: function)
        let recording: Int = try XCTUnwrap(
            function.range(of: "ActivityTrail.note(")
        ).lowerBound.utf16Offset(in: function)
        XCTAssertLessThan(checking, ending)
        XCTAssertLessThan(ending, recording, "The wait is ended on the early return, before anything is said")
    }

    /// And the view really consults that before it says or records anything.
    /// A source read, because the order inside one function is the thing
    /// being pinned and nothing else can see it.
    func testTheViewChecksTheRunIsStillTheOneItAskedAbout() throws {
        let function: String = try PreviewReachabilityTests.givingUpFunction()
        let asking: Int = try XCTUnwrap(
            function.range(of: "PreviewReachability.askTheBuilder(")
        ).lowerBound.utf16Offset(in: function)
        let checking: Int = try XCTUnwrap(
            function.range(of: "PreviewReachability.isStillTheSameWait("),
            "Nothing re-checks the run after the question — a Stop pressed during it "
            + "leaves the teacher an alert about a preview they have already ended."
        ).lowerBound.utf16Offset(in: function)
        let recording: Int = try XCTUnwrap(
            function.range(of: "ActivityTrail.note(")
        ).lowerBound.utf16Offset(in: function)
        XCTAssertLessThan(asking, checking)
        XCTAssertLessThan(checking, recording)
    }

    // MARK: - Which sentence a teacher gets

    func testTheBuilderAnsweringMeansThisMacCannotReachIt() {
        XCTAssertEqual(
            PreviewReachability.verdict(for: .theSiteAnswered), .thisMacCannotReachIt
        )
        XCTAssertEqual(
            PreviewReachability.verdict(for: .nothingAnsweredInside), .theSiteNeverAnswered
        )
    }

    /// Rule 1: the machinery is never named to a teacher. These are the
    /// sentences most at risk of it, because the fault IS the machinery.
    ///
    /// WORDS, not substrings: "Report a Problem…" contains "port", and a test
    /// that cannot tell those apart is one that gets weakened rather than
    /// obeyed the first time it is wrong.
    func testNoneOfTheSentencesNamesTheMachinery() {
        let forbiddenWords: [String] = [
            "port", "ports", "container", "containers", "docker", "vm", "forward",
            "forwarding", "localhost", "colima", "lima", "curl", "terminal"
        ]
        let forbiddenPhrases: [String] = ["virtual machine", "127.0.0.1"]
        for verdict in [
            PreviewReachability.Verdict.thisMacCannotReachIt,
            .theSiteNeverAnswered,
            .plantoirCouldNotTell
        ] {
            let sentence: String = PreviewReachability.sentence(for: verdict)
            var words: Set<String> = []
            var word: String = ""
            for character in sentence.lowercased() {
                if character.isLetter || character.isNumber {
                    word.append(character)
                } else {
                    if !word.isEmpty {
                        words.insert(word)
                    }
                    word = ""
                }
            }
            if !word.isEmpty {
                words.insert(word)
            }
            for forbidden in forbiddenWords {
                XCTAssertFalse(
                    words.contains(forbidden),
                    "The sentence for \(verdict) names the machinery: \"\(forbidden)\"."
                )
            }
            for forbidden in forbiddenPhrases {
                XCTAssertFalse(
                    sentence.lowercased().contains(forbidden),
                    "The sentence for \(verdict) names the machinery: \"\(forbidden)\"."
                )
            }
            XCTAssertTrue(
                sentence.contains("Restarting your Mac") || sentence.contains("Press Preview"),
                "Every one of them ends with something the teacher can do."
            )
        }
    }

    /// The two are told apart on the trail, and the seconds travel with them:
    /// "it sat there" and "it took a while" are one sentence from a teacher
    /// and two different faults.
    func testTheTrailLineSaysWhichOfTheThreeAndForHowLong() {
        let unreachable: String = PreviewReachability.trailLine(
            for: .thisMacCannotReachIt, secondsOfSilence: 45
        )
        let neverServed: String = PreviewReachability.trailLine(
            for: .theSiteNeverAnswered, secondsOfSilence: 45
        )
        let couldNotTell: String = PreviewReachability.trailLine(
            for: .plantoirCouldNotTell, secondsOfSilence: 45
        )
        XCTAssertEqual(Set([unreachable, neverServed, couldNotTell]).count, 3)
        for line in [unreachable, neverServed, couldNotTell] {
            XCTAssertTrue(line.contains("45 seconds"), line)
        }
        XCTAssertTrue(unreachable.contains("could not reach"), unreachable)
        XCTAssertTrue(neverServed.contains("nothing was serving"), neverServed)
        XCTAssertTrue(couldNotTell.contains("could not be asked"), couldNotTell)
    }

    // MARK: - Seeing the fault on purpose

    /// The harness Russell runs to see the sentence on a healthy Mac. It is
    /// debug-only AND needs a variable in the environment, which an app
    /// opened from the Dock does not have — so ordinary use cannot reach it.
    func testTheAddressIsOnlyFakedWhenAskedForExplicitly() {
        let announced: URL = URL(string: "http://127.0.0.1:8091/")!
        XCTAssertEqual(
            PreviewReachability.addressToTry(announced: announced, environment: [:]),
            announced
        )
        XCTAssertEqual(
            PreviewReachability.addressToTry(
                announced: announced,
                environment: [PreviewReachability.pretendingVariableName: "0"]
            ),
            announced,
            "Only an explicit 1 asks for the fault."
        )
        #if DEBUG
        XCTAssertEqual(
            PreviewReachability.addressToTry(
                announced: announced,
                environment: [PreviewReachability.pretendingVariableName: "1"]
            ),
            PreviewReachability.anAddressNothingAnswersAt
        )
        #else
        XCTAssertEqual(
            PreviewReachability.addressToTry(
                announced: announced,
                environment: [PreviewReachability.pretendingVariableName: "1"]
            ),
            announced,
            "A released Plantoir has no way to pretend at all."
        )
        #endif
    }

    // MARK: - When no address was announced (GitHub #235)

    /// An announced address is the only thing ever tried.
    func testAnAnnouncedAddressIsWhatIsTried() throws {
        let announced: URL = try XCTUnwrap(URL(string: "http://127.0.0.1:8091/"))
        XCTAssertEqual(
            PreviewReachability.nextStep(announced: announced, theBuilderSaysItsServerStarted: false),
            .tryTheAddress(announced)
        )
        XCTAssertEqual(
            PreviewReachability.nextStep(announced: announced, theBuilderSaysItsServerStarted: true),
            .tryTheAddress(announced)
        )
    }

    /// No address and no server yet: nothing is wrong yet, and nothing is
    /// guessed — there is no case that makes up an address.
    func testNoAddressBeforeTheServerStartsIsWaitedFor() {
        XCTAssertEqual(
            PreviewReachability.nextStep(announced: nil, theBuilderSaysItsServerStarted: false),
            .keepWaiting
        )
    }

    /// No address once the server has started is final: the launcher
    /// announces before it builds, so nothing is still on its way. Waiting on
    /// would end at the ten-minute bound with the run still going.
    func testNoAddressAfterTheServerStartsStopsAtOnce() {
        XCTAssertEqual(
            PreviewReachability.nextStep(announced: nil, theBuilderSaysItsServerStarted: true),
            .stopBecauseNothingWasAnnounced
        )
        XCTAssertEqual(PreviewReachability.verdictWhenNothingWasAnnounced, .plantoirCouldNotTell)
    }

    /// The wait no longer starts from an address made out of the section's
    /// port — the port INSIDE the builder, wrong for every working folder
    /// after the first — and the no-address ending asks the builder nothing,
    /// because its question is about an address.
    func testThePreviewWaitNeverMakesUpAnAddress() throws {
        let source: String = try String(
            contentsOf: PreviewReachabilityTests.repositoryRoot()
                .appendingPathComponent("mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"),
            encoding: .utf8
        )
        let wait: String = try XCTUnwrap(
            source.components(separatedBy: "func waitForPreviewServer").last,
            "waitForPreviewServer has been renamed — the rule still has to hold."
        )
        XCTAssertFalse(
            wait.contains("URL(string: \"http://127.0.0.1:\\(port)"),
            "The preview wait builds an address out of the section's port again."
        )
        XCTAssertTrue(
            wait.contains("PreviewReachability.nextStep("),
            "The preview wait no longer asks what to do when nothing was announced."
        )
        let ending: String = try XCTUnwrap(
            source.components(separatedBy: "func stopBecauseNoAddressWasAnnounced").last
        )
        let body: String = try XCTUnwrap(
            ending.components(separatedBy: "func stopWaitingForThePreview").first
        )
        XCTAssertFalse(body.contains("askTheBuilder"))
        XCTAssertTrue(body.contains("ActivityTrail.note("), "rule 5: the ending leaves a line")
        XCTAssertTrue(body.contains("stopPreview()"))
    }

    /// Its trail line says what happened, not what the silence ending says:
    /// no silence was waited out and nobody was asked anything.
    func testTheNoAddressTrailLineIsItsOwn() {
        let line: String = PreviewReachability.trailLineWhenNothingWasAnnounced
        XCTAssertFalse(line.contains("seconds"))
        XCTAssertFalse(line.contains("could not be asked"))
        XCTAssertNotEqual(
            line,
            PreviewReachability.trailLine(for: .plantoirCouldNotTell, secondsOfSilence: 45)
        )
    }

    /// The contract carries the rule, so Windows matches it rather than
    /// re-deriving it.
    func testTheNoAddressRuleIsWhatTheContractSays() throws {
        let rules: [String: Any] = try PreviewReachabilityTests.readAppRules()
        let ports: [String: Any] = try XCTUnwrap(rules["previewPorts"] as? [String: Any])
        let rule: [String: Any] = try XCTUnwrap(
            ports["whenThePreviewNeverAppears"] as? [String: Any]
        )
        let noAddress: [String: Any] = try XCTUnwrap(
            rule["whenNoAddressWasAnnounced"] as? [String: Any]
        )
        XCTAssertEqual(
            try XCTUnwrap(noAddress["verdict"] as? String),
            String(describing: PreviewReachability.verdictWhenNothingWasAnnounced)
        )
        XCTAssertEqual(try XCTUnwrap(noAddress["builderIsAsked"] as? Bool), false)
        XCTAssertEqual(
            try XCTUnwrap(noAddress["stopsWhen"] as? String),
            PreviewReachability.theBuilderSaysItsServerStarted
        )
        XCTAssertEqual(try XCTUnwrap(noAddress["anAddressIsEverGuessed"] as? Bool), false)
    }

    // MARK: - The contract both apps read

    /// Every number and sentence in the fix is in `app-rules.json` so that
    /// Windows can match the behaviour rather than re-derive it — and so a
    /// reworded sentence here goes red rather than drifting silently.
    func testTheRuleIsWhatTheContractSays() throws {
        let rules: [String: Any] = try PreviewReachabilityTests.readAppRules()
        let ports: [String: Any] = try XCTUnwrap(rules["previewPorts"] as? [String: Any])
        let rule: [String: Any] = try XCTUnwrap(
            ports["whenThePreviewNeverAppears"] as? [String: Any]
        )

        XCTAssertEqual(
            PreviewReachability.secondsOfSilenceBeforeGivingUp,
            try XCTUnwrap(rule["secondsOfSilenceAllowed"] as? Int)
        )
        XCTAssertEqual(
            PreviewReachability.theBuilderSaysItsServerStarted,
            try XCTUnwrap(rule["theClockStartsAt"] as? String)
        )
        XCTAssertEqual(
            PreviewReachability.alertTitle, try XCTUnwrap(rule["alertTitle"] as? String)
        )

        // All THREE outcomes, table-driven off the contract: a fourth verdict
        // with no case here, or a case with no verdict, fails rather than
        // being noticed later.
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        var sentences: [String: String] = [:]
        for entry in cases {
            let verdict: String = try XCTUnwrap(entry["verdict"] as? String)
            sentences[verdict] = try XCTUnwrap(entry["sentence"] as? String)
        }
        let everyVerdict: [PreviewReachability.Verdict] = [
            .thisMacCannotReachIt, .theSiteNeverAnswered, .plantoirCouldNotTell
        ]
        XCTAssertEqual(sentences.count, everyVerdict.count)
        for verdict in everyVerdict {
            XCTAssertEqual(
                PreviewReachability.sentence(for: verdict),
                try XCTUnwrap(sentences[String(describing: verdict)]),
                "The sentence for \(verdict) and the contract's have drifted apart."
            )
        }
    }

    /// The line the clock starts at is Quartz's own, so it is checked against
    /// what the build pipeline actually prints rather than remembered.
    func testTheClockStartsAtALineQuartzReallyPrints() throws {
        let source: String = try String(
            contentsOf: PreviewReachabilityTests.repositoryRoot()
                .appendingPathComponent("documentation/05-build-pipeline.md"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains(PreviewReachability.theBuilderSaysItsServerStarted),
            "Quartz's own line is written down in documentation/05 — if it has changed there, "
            + "the clock in PreviewReachability starts at a line nothing prints."
        )
    }

    // MARK: - The order that cannot be unit-tested any other way

    /// The builder is asked BEFORE the run is stopped. Stopping ends the very
    /// server the question is about, so the two the wrong way round answers
    /// "nothing is serving it" every time — and tells a teacher whose website
    /// was fine that it never came up.
    func testTheBuilderIsAskedBeforeThePreviewIsStopped() throws {
        let function: String = try PreviewReachabilityTests.givingUpFunction()
        let asking: Int = try XCTUnwrap(
            function.range(of: "PreviewReachability.askTheBuilder(")
        ).lowerBound.utf16Offset(in: function)
        let stopping: Int = try XCTUnwrap(
            function.range(of: "stopPreview()")
        ).lowerBound.utf16Offset(in: function)
        XCTAssertLessThan(
            asking, stopping,
            "The builder must be asked before the preview is stopped."
        )
    }

    // MARK: - Helpers

    /// The body of the one function whose ORDER matters and which nothing
    /// else can watch.
    private static func givingUpFunction() throws -> String {
        let source: String = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"),
            encoding: .utf8
        )
        return try XCTUnwrap(
            source.components(separatedBy: "func stopWaitingForThePreview").last,
            "stopWaitingForThePreview has been renamed — these orders still have to hold."
        )
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func readAppRules() throws -> [String: Any] {
        let url: URL = repositoryRoot()
            .appendingPathComponent("contracts")
            .appendingPathComponent("app-rules.json")
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
    }
}
