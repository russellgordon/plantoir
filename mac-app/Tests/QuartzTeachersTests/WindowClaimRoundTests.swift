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

    /// The app's own record is filled at launch: the test host is the app,
    /// and launch has finished by the time any test runs.
    func testTheAppsRecordHasHeardRestorationFinish() {
        XCTAssertTrue(LaunchRestoration.shared.hasFinished)
    }

    // MARK: - The claim round

    func testAWindowDoesNotLookForItsFolderBeforeRestorationHasFinished() {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-a", frame: firstFrame)
        ])
        let restoration: LaunchRestoration = LaunchRestoration()
        var claimed: [String] = []
        WindowClaimRound.begin(
            claimant: WindowFolderClaimant(),
            frame: {
                return self.firstFrame
            },
            windowHasSettled: {
                return false
            },
            restoration: restoration,
            adopt: { entry, how in
                claimed.append(entry.path + " " + how)
            },
            settleWithNoEntry: {
                claimed.append("none")
            }
        )
        XCTAssertEqual(claimed, [], "the frame may not be final yet")

        restoration.restorationFinished()
        XCTAssertEqual(claimed, ["/tmp/998-a matched by frame"], "tried the moment restoration finished, not after a delay")
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
        var claimedByFirst: [String] = []
        var claimedBySecond: [String] = []
        let bothDecided: XCTestExpectation = expectation(description: "both windows decided")
        bothDecided.expectedFulfillmentCount = 2

        // The same pass of the main actor, as macOS hands them over.
        WindowClaimRound.begin(
            claimant: WindowFolderClaimant(),
            frame: {
                return self.unmatchedFrame
            },
            windowHasSettled: {
                return false
            },
            restoration: restoration,
            adopt: { entry, how in
                claimedByFirst.append(entry.path + " " + how)
                bothDecided.fulfill()
            },
            settleWithNoEntry: {
                claimedByFirst.append("none")
                bothDecided.fulfill()
            }
        )
        XCTAssertEqual(claimedByFirst, [], "no give-up while a sibling may still match")
        WindowClaimRound.begin(
            claimant: WindowFolderClaimant(),
            frame: {
                return self.secondFrame
            },
            windowHasSettled: {
                return false
            },
            restoration: restoration,
            adopt: { entry, how in
                claimedBySecond.append(entry.path + " " + how)
                bothDecided.fulfill()
            },
            settleWithNoEntry: {
                claimedBySecond.append("none")
                bothDecided.fulfill()
            }
        )

        await fulfillment(of: [bothDecided], timeout: 5)
        XCTAssertEqual(claimedBySecond, ["/tmp/998-second-window matched by frame"])
        XCTAssertEqual(claimedByFirst, ["/tmp/998-other fell back to order"], "the first window took what was left, not its sibling's folder")
    }

    func testASettledWindowNeverClaimsInTheRound() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-a", frame: firstFrame)
        ])
        var claimed: [String] = []
        WindowClaimRound.begin(
            claimant: WindowFolderClaimant(),
            frame: {
                return self.firstFrame
            },
            windowHasSettled: {
                return true
            },
            restoration: finishedRestoration(),
            adopt: { entry, how in
                claimed.append(entry.path)
            },
            settleWithNoEntry: {
                claimed.append("none")
            }
        )
        await Task.yield()
        XCTAssertEqual(claimed, [])
        XCTAssertTrue(WindowFolderMemory.hasEntriesToClaim(), "the entry is left for its own window")
    }

    /// A window opened once claims have closed gets the picker (or its own
    /// folder) on the next pass, not a second later.
    func testAWindowOpenedAfterClaimsCloseSettlesWithNoEntry() async {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp/998-a", frame: firstFrame)
        ])
        WindowFolderMemory.claimsOpenUntil = Date(timeIntervalSinceNow: -1)
        var claimed: [String] = []
        let decided: XCTestExpectation = expectation(description: "decided")
        WindowClaimRound.begin(
            claimant: WindowFolderClaimant(),
            frame: {
                return self.firstFrame
            },
            windowHasSettled: {
                return false
            },
            restoration: finishedRestoration(),
            adopt: { entry, how in
                claimed.append(entry.path)
                decided.fulfill()
            },
            settleWithNoEntry: {
                claimed.append("none")
                decided.fulfill()
            }
        )
        await fulfillment(of: [decided], timeout: 5)
        XCTAssertEqual(claimed, ["none"])
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
            "QuartzTeachers/Models/LaunchRestoration.swift"
        ] {
            let source: String = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            for forbidden in ["Task.sleep", "asyncAfter(", "DispatchQueue.main", "attemptsLeft"] {
                XCTAssertFalse(source.contains(forbidden), "\(relativePath) uses \(forbidden)")
            }
        }
    }
}
