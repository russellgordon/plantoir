import XCTest
@testable import QuartzTeachers

/// The local assistant should do the same thing pressing Deploy or Preview
/// would — not run silently just because no section window happened to be
/// open at that moment. `openMainWindow` is the capability that makes this
/// possible, present only for the local in-app assistant (never MCP, never
/// a scheduled deploy — see `AssistToolRunner`'s own doc comments).
///
/// The full flow (opening a brand-new window, waiting for a real
/// `SectionDetailView` to mount and register itself) needs an actual
/// SwiftUI render pass a unit test cannot produce — that is press-and-look
/// territory, verified by hand against the real app. What IS unit-tested
/// here: the decision logic that does not depend on a real window ever
/// appearing.
@MainActor
final class AssistRevealsSectionOnScreenTests: XCTestCase {

    override func tearDown() {
        SectionWindowControllers.shared.forgetAll()
        FakePreview.shared.forget()
        super.tearDown()
    }

    // MARK: - openWindowModel(forFolderPath:)

    func testFindsAnAlreadyOpenWindowOnTheSameFolder() {
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.workspaceURL = URL(fileURLWithPath: "/Users/teacher/Class Websites")
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }

        let found: WorkspaceModel? = AssistToolRunner.openWindowModel(
            forFolderPath: "/Users/teacher/Class Websites"
        )
        XCTAssertTrue(found === model)
    }

    func testFindsNothingForAFolderNoWindowIsOpenOn() {
        XCTAssertNil(AssistToolRunner.openWindowModel(forFolderPath: "/nowhere/at/all"))
    }

    // MARK: - revealSectionOnScreen: nil capability (MCP, scheduled deploy)

    /// `openMainWindow` is nil for every caller except the local assistant
    /// — MCP and a scheduled deploy must get exactly the old, silent
    /// fallback, never an attempt to touch a window that cannot exist in
    /// their process.
    func testWithNoOpenMainWindowCapabilityItReturnsFalseImmediately() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let succeeded: Bool = await made.runner.revealSectionOnScreen(
            course: made.course, sectionNumber: 1,
            pollInterval: .milliseconds(1), maxAttempts: 1
        )
        XCTAssertFalse(succeeded)
    }

    // MARK: - revealSectionOnScreen: an already-open window is reused, never re-opened

    /// The common case — the assistant is almost always opened FROM an
    /// already-open window's sidebar. Reusing it, rather than opening a
    /// second one, is the whole point of checking first.
    func testAnAlreadyOpenWindowOnTheSameFolderIsReusedNotReopened() async throws {
        let made = try AssistFixture.makeRunner(openMainWindow: {
            XCTFail("A matching window is already open — openMainWindow must not be called.")
        })
        defer { try? FileManager.default.removeItem(at: made.root) }

        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.workspaceURL = URL(fileURLWithPath: made.root.path)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }

        // No real SectionDetailView ever mounts in a unit test, so this
        // still ends up returning false after its (short, injected) poll —
        // what matters here is that openMainWindow was never invoked.
        _ = await made.runner.revealSectionOnScreen(
            course: made.course, sectionNumber: 1,
            pollInterval: .milliseconds(1), maxAttempts: 2
        )

        // Reusing the window means its selection was moved to the section
        // that was asked for, exactly as clicking it in the sidebar would.
        XCTAssertEqual(model.selection, SidebarSelection.section("ICS3U", 1))
    }

    // MARK: - deploySection never calls openMainWindow when a window IS already open

    func testDeployingWithAWindowAlreadyOpenNeverCallsOpenMainWindow() async throws {
        let made = try AssistFixture.makeRunner(
            hasDeployedBefore: true,
            registeringPreview: true,
            openMainWindow: { XCTFail("A section window is already open — openMainWindow must not be called.") }
        )
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "deploy_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertEqual(outcome.summary, FakePreview.deployedMessage)
    }

    // MARK: - Helpers

    private func call(_ name: String, arguments: [String: Any] = [:]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(decoding: encoded, as: UTF8.self)
            )
        )
    }
}
