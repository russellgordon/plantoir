import AppKit
import XCTest
@testable import QuartzTeachers

/// When a restored window looks for its remembered folder, and when it
/// gives up to the next one by order (#998). This replaced seven retries
/// 150 ms apart; nothing here waits on a clock.
@MainActor
final class WindowClaimRoundTests: XCTestCase {

    // MARK: - Stored properties

    let firstFrame: String = "{{100, 100}, {900, 700}}"
    let secondFrame: String = "{{600, 300}, {1100, 720}}"
    let unmatchedFrame: String = "{{40, 40}, {800, 600}}"

    // MARK: - Functions

    override func tearDown() {
        WindowFolderMemory.reset(with: [])
        super.tearDown()
    }

    /// One window under test: its frame and what it ended up with.
    final class TestWindow {
        var frame: String
        var hasSettled: Bool = false
        var decisions: [String] = []

        init(frame: String) {
            self.frame = frame
        }
    }

    func makeRound(
        for window: TestWindow,
        others: @escaping () -> [String] = { [] },
        restoration: LaunchRestoration,
        decided: XCTestExpectation? = nil
    ) -> WindowClaimRound {
        return WindowClaimRound(
            claimant: WindowFolderClaimant(),
            frame: {
                return window.frame
            },
            windowHasSettled: {
                return window.hasSettled
            },
            otherWindowFrames: others,
            restoration: restoration,
            adopt: { entry, how in
                window.decisions.append(entry.path + " " + how)
                decided?.fulfill()
            },
            settleWithNoEntry: {
                window.decisions.append("none")
                decided?.fulfill()
            }
        )
    }

    func finishedRestoration() -> LaunchRestoration {
        let restoration: LaunchRestoration = LaunchRestoration()
        restoration.restorationFinished()
        return restoration
    }

    // MARK: - LaunchRestoration

    func testWorkWaitsForRestorationToFinishAndThenRunsInOrder() {
        let restoration: LaunchRestoration = LaunchRestoration()
        var ran: [String] = []
        restoration.whenFinished {
            ran.append("first")
        }
        restoration.whenFinished {
            ran.append("second")
        }
        XCTAssertEqual(ran, [], "nothing runs before macOS says restoration is done")

        restoration.restorationFinished()
        XCTAssertEqual(ran, ["first", "second"])

        restoration.whenFinished {
            ran.append("after")
        }
        XCTAssertEqual(ran, ["first", "second", "after"], "after the moment, at once")

        restoration.restorationFinished()
        XCTAssertEqual(ran.count, 3, "said twice, run once")
    }

    /// The app's own record is filled ONLY by AppKit's notification (no
    /// fallback marks it), and the test host is the app: if macOS had not
    /// posted it at this launch, this fails.
    func testTheAppsRecordHeardAppKitSayRestorationFinished() {
        XCTAssertTrue(LaunchRestoration.shared.hasFinished)
    }

    // MARK: - Trying the frame

    /// macOS 15.7.7's order (measured): the window is handed over with its
    /// restored frame BEFORE restoration is said to be finished.
    func testAWindowClaimsAtHandOverEvenBeforeRestorationHasFinished() {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-a", frame: firstFrame)
        ])
        let window: TestWindow = TestWindow(frame: firstFrame)
        makeRound(for: window, restoration: LaunchRestoration()).begin(watching: nil)
        XCTAssertEqual(window.decisions, ["/tmp/998-a matched by frame"])
    }

    /// The window's frame becomes the remembered one only after a later
    /// move, as SwiftUI moves windows on 15: it claims at the move, and
    /// never gives up before restoration has finished.
    func testAFrameThatBecomesRightAfterAMoveIsClaimedAtTheMove() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-sibling", frame: secondFrame),
            WindowFolderMemory.Entry(path: "/tmp/998-mine", frame: firstFrame)
        ])
        let restoration: LaunchRestoration = LaunchRestoration()
        let window: TestWindow = TestWindow(frame: unmatchedFrame)
        let round: WindowClaimRound = makeRound(for: window, restoration: restoration)
        round.begin(watching: nil)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(window.decisions, [], "no give-up while restoration is still going on")

        window.frame = firstFrame
        round.frameChanged()
        XCTAssertEqual(window.decisions, ["/tmp/998-mine matched by frame"], "not the sibling's, which is first by order")

        restoration.restorationFinished()
        await Task.yield()
        XCTAssertEqual(window.decisions.count, 1, "decided once")
    }

    /// The race the retries were there for. Two windows come back in one
    /// pass: the first's frame matches nothing (the screens changed), the
    /// second's matches the entry that is FIRST in order. A first window
    /// that gave up at once would take that entry by order, and the two
    /// windows would swap folders; it must wait for its sibling to look.
    func testAWindowGivesUpByOrderOnlyAfterItsSiblingsHaveTriedTheirFrames() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-second-window", frame: secondFrame),
            WindowFolderMemory.Entry(path: "/tmp/998-other", frame: firstFrame)
        ])
        let restoration: LaunchRestoration = finishedRestoration()
        let first: TestWindow = TestWindow(frame: unmatchedFrame)
        let second: TestWindow = TestWindow(frame: secondFrame)
        let bothDecided: XCTestExpectation = expectation(description: "both windows decided")
        bothDecided.expectedFulfillmentCount = 2

        makeRound(for: first, restoration: restoration, decided: bothDecided).begin(watching: nil)
        XCTAssertEqual(first.decisions, [], "no give-up while a sibling may still match")
        makeRound(for: second, restoration: restoration, decided: bothDecided).begin(watching: nil)

        await fulfillment(of: [bothDecided], timeout: 5)
        XCTAssertEqual(second.decisions, ["/tmp/998-second-window matched by frame"])
        XCTAssertEqual(first.decisions, ["/tmp/998-other fell back to order"], "the first window took what was left, not its sibling's folder")
    }

    /// Two windows handed over in SEPARATE passes: the first gives up before
    /// the second has even looked. The second window already exists with its
    /// frame (AppKit made it), so its entry is reserved and the first cannot
    /// take it by order.
    func testWindowsHandedOverInSeparatePassesDoNotSwap() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-second-window", frame: secondFrame),
            WindowFolderMemory.Entry(path: "/tmp/998-other", frame: firstFrame)
        ])
        let restoration: LaunchRestoration = finishedRestoration()
        let first: TestWindow = TestWindow(frame: unmatchedFrame)
        let second: TestWindow = TestWindow(frame: secondFrame)
        let firstDecided: XCTestExpectation = expectation(description: "first decided")
        makeRound(
            for: first,
            others: {
                return [second.frame]
            },
            restoration: restoration,
            decided: firstDecided
        ).begin(watching: nil)
        await fulfillment(of: [firstDecided], timeout: 5)
        XCTAssertEqual(first.decisions, ["/tmp/998-other fell back to order"], "the sibling's entry was left for it")

        makeRound(for: second, restoration: restoration).begin(watching: nil)
        XCTAssertEqual(second.decisions, ["/tmp/998-second-window matched by frame"])
    }

    /// When the only entries left belong to other open windows, a window
    /// that matches nothing shows the picker rather than take one.
    func testAWindowWhoseOnlyEntriesBelongToOthersShowsThePicker() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-second-window", frame: secondFrame)
        ])
        let first: TestWindow = TestWindow(frame: unmatchedFrame)
        let decided: XCTestExpectation = expectation(description: "decided")
        makeRound(
            for: first,
            others: {
                return [self.secondFrame]
            },
            restoration: finishedRestoration(),
            decided: decided
        ).begin(watching: nil)
        await fulfillment(of: [decided], timeout: 5)
        XCTAssertEqual(first.decisions, ["none"])
        XCTAssertTrue(WindowFolderMemory.hasEntriesToClaim())
    }

    /// Restoration never said to be finished: the window keeps waiting (its
    /// spinner) rather than guess an entry by order.
    func testNoGiveUpUntilRestorationHasFinished() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-a", frame: firstFrame)
        ])
        let window: TestWindow = TestWindow(frame: unmatchedFrame)
        let round: WindowClaimRound = makeRound(for: window, restoration: LaunchRestoration())
        round.begin(watching: nil)
        for _ in 0..<5 {
            await Task.yield()
        }
        XCTAssertEqual(window.decisions, [])
        XCTAssertFalse(round.isOver)
    }

    func testASettledWindowNeverClaimsInTheRound() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-a", frame: firstFrame)
        ])
        let window: TestWindow = TestWindow(frame: firstFrame)
        window.hasSettled = true
        let round: WindowClaimRound = makeRound(for: window, restoration: finishedRestoration())
        round.begin(watching: nil)
        await Task.yield()
        XCTAssertEqual(window.decisions, [])
        XCTAssertTrue(round.isOver)
        XCTAssertTrue(WindowFolderMemory.hasEntriesToClaim(), "the entry is left for its own window")
    }

    /// A window opened once claims have closed gets the picker (or its own
    /// folder) on the next pass, not a second later.
    func testAWindowOpenedAfterClaimsCloseSettlesWithNoEntry() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-a", frame: firstFrame)
        ])
        WindowFolderMemory.claimsOpenUntil = Date(timeIntervalSinceNow: -1)
        let window: TestWindow = TestWindow(frame: firstFrame)
        let decided: XCTestExpectation = expectation(description: "decided")
        makeRound(for: window, restoration: finishedRestoration(), decided: decided).begin(watching: nil)
        await fulfillment(of: [decided], timeout: 5)
        XCTAssertEqual(window.decisions, ["none"])
    }

    /// A real window's moves reach the round, and the round stops watching
    /// once it has claimed.
    func testARealWindowsMoveIsWatched() {
        let nsWindow: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        nsWindow.isReleasedWhenClosed = false
        defer {
            nsWindow.close()
        }
        // Where AppKit actually puts the window for this move (it may keep
        // a window on screen), learnt before the round starts.
        let startingFrame: NSRect = nsWindow.frame
        let movedTo: NSRect = NSRect(x: 300, y: 300, width: 400, height: 300)
        nsWindow.setFrame(movedTo, display: false)
        let movedFrame: String = NSStringFromRect(nsWindow.frame)
        nsWindow.setFrame(startingFrame, display: false)
        XCTAssertNotEqual(NSStringFromRect(nsWindow.frame), movedFrame)
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-moved", frame: movedFrame)
        ])
        var decisions: [String] = []
        let round: WindowClaimRound = WindowClaimRound(
            claimant: WindowFolderClaimant(),
            frame: {
                return NSStringFromRect(nsWindow.frame)
            },
            windowHasSettled: {
                return false
            },
            otherWindowFrames: {
                return []
            },
            restoration: LaunchRestoration(),
            adopt: { entry, how in
                decisions.append(entry.path + " " + how)
            },
            settleWithNoEntry: {
                decisions.append("none")
            }
        )
        round.begin(watching: nsWindow)
        XCTAssertEqual(decisions, [])
        nsWindow.setFrame(movedTo, display: false)
        XCTAssertEqual(decisions, ["/tmp/998-moved matched by frame"], "claimed at the move")
        XCTAssertTrue(round.isOver)
    }

    /// The house rule, held in the files: no timed retry left in the claim.
    func testTheClaimWaitsOnNoTimer() throws {
        let root: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "QuartzTeachers/App/WindowRootView.swift",
            "QuartzTeachers/Models/WindowFolderClaimant.swift",
            "QuartzTeachers/Models/WindowClaimRound.swift",
            "QuartzTeachers/Models/LaunchRestoration.swift"
        ] {
            let source: String = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            for forbidden in ["Task.sleep", "asyncAfter(", "DispatchQueue.main", "attemptsLeft"] {
                XCTAssertFalse(source.contains(forbidden), "\(relativePath) uses \(forbidden)")
            }
        }
    }
}
