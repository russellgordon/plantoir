import Foundation
@testable import QuartzTeachers

/// A stand-in for a section window, which records the ORDER of what the
/// assistant did to it — its preview, and its Deploy.
///
/// The order is the point. Stopping, writing and starting can all happen and
/// still be wrong: a preview stopped after the pages were rewritten was
/// serving a half-changed site in between, and that is exactly the fault the
/// first attempt at this had. So this notes a "write" the moment the watched
/// page changes on disk, and the test reads the three events back as a
/// sequence rather than as a set.
@MainActor
final class FakePreview {

    // MARK: - Stored properties

    static let shared: FakePreview = FakePreview()

    /// What a real window's Deploy answers with, asked of the one place that
    /// sentence is written. A literal here would let the app's wording change
    /// while every test still passed against the old words.
    static let deployedMessage: String = AssistWording.deployed(course: "ICS3U", section: "1")

    private(set) var events: [String] = []
    private var state: SectionWindowControllers.PreviewState = .showing
    private var deployRefusal: String?
    private var watchedURL: URL?
    private var textWhenWatched: String?

    // MARK: - Functions

    /// Pretend a section window is open.
    ///
    /// `running` and `refusingToDeploy` exist because the contract's scenarios
    /// need them: "deploy with no preview running" and "deploy while that
    /// section is already busy" are two of the eight, and a fake that could
    /// only be one thing could only test one of them.
    func register(folderPath: String,
                  courseCode: String,
                  sectionNumber: Int,
                  running previewIsRunning: Bool = true,
                  showing: SectionWindowControllers.PreviewState? = nil,
                  refusingToDeploy refusal: String? = nil,
                  answeringLaterClasses laterClassesAnswer: LaterClassesAnswer = .nothingToAsk) {
        events = []
        // `running` is kept for the callers that only care whether there is
        // something to stop; `showing` is for the tests that care WHICH of the
        // two running states it is in.
        state = showing ?? (previewIsRunning ? .showing : .notRunning)
        deployRefusal = refusal
        watchedURL = nil
        textWhenWatched = nil
        SectionWindowControllers.shared.register(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            controller: SectionWindowControllers.Controller(
                previewState: { [weak self] in self?.state ?? .notRunning },
                startPreview: { [weak self] in
                    self?.noteWriteIfItHappened()
                    self?.state = .showing
                    self?.events.append("start")
                },
                stopPreview: { [weak self] in
                    // Records the stop as two events with a real suspension
                    // between them, so the test can tell "called the stop"
                    // apart from "waited for the stop to finish". The real
                    // one reaches into the container and takes time; a caller
                    // that does not await it starts a rebuild the stop then
                    // kills.
                    self?.noteWriteIfItHappened()
                    self?.events.append("stop-begins")
                    try? await Task.sleep(for: .milliseconds(60))
                    self?.state = .notRunning
                    self?.noteWriteIfItHappened()
                    self?.events.append("stop-ends")
                },
                // The window's Deploy, which the assistant presses rather
                // than running the launcher where nobody can see it. It goes
                // into the same sequence as the preview events, because the
                // order is the whole question: deploying while the preview is
                // still up is what the button in the window will not let a
                // teacher do.
                deploy: { [weak self] in
                    self?.events.append("deploy")
                    // A window that is already busy answers with a sentence
                    // rather than deploying. The event still fires: the
                    // assistant DID press the button — the window is what
                    // declined, which is the real shape of it.
                    if let refusal = self?.deployRefusal {
                        return AssistSiteWorkResult(succeeded: false, message: refusal)
                    }
                    return AssistSiteWorkResult(
                        succeeded: true, message: FakePreview.deployedMessage
                    )
                },
                // #475: the window's question about classes dated after the
                // next class. Recorded only when it is put — a window with
                // nothing to ask records nothing, so every older case's
                // sequence is unchanged.
                askAboutClassesDatedLater: { [weak self] in
                    if laterClassesAnswer != .nothingToAsk {
                        self?.events.append("askAboutClassesDatedLater")
                    }
                    return laterClassesAnswer
                }
            )
        )
    }

    /// Watch a page, so a change to it lands in the sequence as "write".
    func watch(pageAt url: URL) {
        watchedURL = url
        textWhenWatched = try? String(contentsOf: url, encoding: .utf8)
    }

    func forget() {
        SectionWindowControllers.shared.forgetAll()
        events = []
        watchedURL = nil
        textWhenWatched = nil
    }

    // MARK: - Private

    private func noteWriteIfItHappened() {
        guard let watchedURL, events.last != "write" else {
            return
        }
        let now: String? = try? String(contentsOf: watchedURL, encoding: .utf8)
        if now != textWhenWatched {
            textWhenWatched = now
            events.append("write")
        }
    }
}
