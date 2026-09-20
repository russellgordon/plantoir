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
    /// `HelperPrograms`' environment is answered "no" on every teacher's Mac,
    /// and "no" here means telling them their website never came up.
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

    /// Only a 200 is the site answering itself. Everything else — a curl that
    /// timed out, a container that is not there, nothing at all — is not.
    func testOnlyAnAnsweringSiteCounts() {
        XCTAssertTrue(PreviewReachability.theBuilderCanSeeItsOwnSite(fromAnswer: "200"))
        XCTAssertTrue(PreviewReachability.theBuilderCanSeeItsOwnSite(fromAnswer: "200\n"))
        XCTAssertFalse(PreviewReachability.theBuilderCanSeeItsOwnSite(fromAnswer: "000"))
        XCTAssertFalse(PreviewReachability.theBuilderCanSeeItsOwnSite(fromAnswer: "404"))
        XCTAssertFalse(PreviewReachability.theBuilderCanSeeItsOwnSite(fromAnswer: ""))
    }

    // MARK: - Which sentence a teacher gets

    func testTheBuilderAnsweringMeansThisMacCannotReachIt() {
        XCTAssertEqual(
            PreviewReachability.verdict(theBuilderCanSeeItsOwnSite: true),
            .thisMacCannotReachIt
        )
        XCTAssertEqual(
            PreviewReachability.verdict(theBuilderCanSeeItsOwnSite: false),
            .theSiteNeverAnswered
        )
    }

    /// Rule 1: the machinery is never named to a teacher. This is the
    /// sentence most at risk of it, because the fault IS the machinery.
    func testNeitherSentenceNamesTheMachinery() {
        let forbidden: [String] = [
            "port", "container", "Docker", "docker", "virtual machine", "VM",
            "forward", "localhost", "127.0.0.1", "Colima", "Lima", "curl"
        ]
        for verdict in [PreviewReachability.Verdict.thisMacCannotReachIt, .theSiteNeverAnswered] {
            let sentence: String = PreviewReachability.sentence(for: verdict)
            for word in forbidden {
                XCTAssertFalse(
                    sentence.contains(word),
                    "The sentence for \(verdict) names the machinery: \"\(word)\"."
                )
            }
            XCTAssertTrue(
                sentence.contains("Mac"),
                "Both sentences say what to do with the teacher's Mac."
            )
        }
    }

    /// The two are told apart on the trail, and the seconds travel with them:
    /// "it sat there" and "it took a while" are one sentence from a teacher
    /// and two different faults.
    func testTheTrailLineSaysWhichOfTheTwoAndForHowLong() {
        let unreachable: String = PreviewReachability.trailLine(
            for: .thisMacCannotReachIt, secondsOfSilence: 45
        )
        let neverServed: String = PreviewReachability.trailLine(
            for: .theSiteNeverAnswered, secondsOfSilence: 45
        )
        XCTAssertNotEqual(unreachable, neverServed)
        XCTAssertTrue(unreachable.contains("45 seconds"), unreachable)
        XCTAssertTrue(neverServed.contains("45 seconds"), neverServed)
        XCTAssertTrue(unreachable.contains("could not reach"), unreachable)
        XCTAssertTrue(neverServed.contains("nothing was serving"), neverServed)
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

        let sentences: [String: String] = try XCTUnwrap(rule["sentences"] as? [String: String])
        XCTAssertEqual(
            PreviewReachability.sentence(for: .thisMacCannotReachIt),
            try XCTUnwrap(sentences["thisMacCannotReachIt"])
        )
        XCTAssertEqual(
            PreviewReachability.sentence(for: .theSiteNeverAnswered),
            try XCTUnwrap(sentences["theSiteNeverAnswered"])
        )
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
        let source: String = try String(
            contentsOf: PreviewReachabilityTests.repositoryRoot()
                .appendingPathComponent("mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"),
            encoding: .utf8
        )
        let function: String = try XCTUnwrap(
            source.components(separatedBy: "func stopWaitingForThePreview").last,
            "stopWaitingForThePreview has been renamed — this order still has to hold."
        )
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
