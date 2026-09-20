import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Redundancy deploy targets: a course/section can publish to more than one
/// destination — `deployTarget` stays the primary, and up to two more of
/// the three known types can be switched on as ADDITIONAL destinations. A
/// course that never touches this feature must write the exact same
/// `course_config.json` it always has: no new key, byte-identical file.
final class AdditionalDeployTargetsTests: XCTestCase {

    // MARK: - Functions

    /// A configuration written to disk and read back, the way the app and
    /// the command-line scripts both see it.
    @MainActor
    func roundTripped(_ values: [String: Any]) throws -> CourseConfiguration {
        let data: Data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("additional_targets_config_\(UUID().uuidString).json")
        try data.write(to: fileURL)
        return try CourseConfiguration(contentsOf: fileURL)
    }

    // MARK: - The default: nothing changes for a course that never opts in

    @MainActor
    func testACourseThatNeverOptsInHasNoAdditionalTargets() throws {
        let configuration: CourseConfiguration = try roundTripped(["course_code": "ICS3U"])
        XCTAssertTrue(configuration.additionalDeployTargets.isEmpty)
    }

    @MainActor
    func testWritingAnEmptyAdditionalTargetsListOmitsTheKeyEntirely() throws {
        let configuration: CourseConfiguration = try roundTripped(["course_code": "ICS3U"])
        configuration.additionalDeployTargets = []

        XCTAssertNil(configuration.values["additional_deploy_targets"],
                     "An empty list must OMIT the key, not write `[]` — every course that has not "
                     + "opted in must write the exact same file it always has.")
    }

    @MainActor
    func testACourseWithNoAdditionalTargetsWritesTheSameFileAsBefore() throws {
        let configuration: CourseConfiguration = try roundTripped(["course_code": "ICS3U", "deploy_target": "netlify"])
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unchanged_\(UUID().uuidString).json")
        try configuration.write(to: fileURL)

        let written: String = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(written.contains("additional_deploy_targets"))
    }

    // MARK: - Round-tripping a real additional-targets list

    @MainActor
    func testAdditionalTargetsRoundTripThroughDisk() throws {
        let configuration: CourseConfiguration = try roundTripped(["course_code": "MCV4U", "deploy_target": "netlify"])
        configuration.additionalDeployTargets = [
            CourseConfiguration.AdditionalDeployTarget(type: "cloudflare_pages", path: ""),
            CourseConfiguration.AdditionalDeployTarget(type: "local_folder", path: "/Users/teacher/Sites"),
        ]

        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_\(UUID().uuidString).json")
        try configuration.write(to: fileURL)
        let reread: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        let targets: [CourseConfiguration.AdditionalDeployTarget] = reread.additionalDeployTargets
        XCTAssertEqual(targets.count, 2)
        XCTAssertTrue(reread.hasAdditionalDeployTarget(ofType: "cloudflare_pages"))
        XCTAssertTrue(reread.hasAdditionalDeployTarget(ofType: "local_folder"))
        XCTAssertEqual(reread.additionalDeployTargetPath(ofType: "local_folder"), "/Users/teacher/Sites")
        // Cloudflare never carries a path — its credential lives in app
        // settings, not in this file.
        XCTAssertEqual(reread.additionalDeployTargetPath(ofType: "cloudflare_pages"), "")
    }

    @MainActor
    func testAnOlderAppsUnknownKeysArePreservedAlongsideAdditionalTargets() throws {
        // The same guarantee CloudflareDeployTests pins for deploy_target:
        // a key this app version does not know about survives untouched.
        let configuration: CourseConfiguration = try roundTripped([
            "course_code": "MCV4U",
            "some_future_key_the_app_does_not_know": ["keep": "me"],
        ])
        configuration.additionalDeployTargets = [
            CourseConfiguration.AdditionalDeployTarget(type: "cloudflare_pages", path: ""),
        ]

        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preserve_\(UUID().uuidString).json")
        try configuration.write(to: fileURL)
        let reread: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        XCTAssertNotNil(reread.values["some_future_key_the_app_does_not_know"])
        XCTAssertTrue(reread.hasAdditionalDeployTarget(ofType: "cloudflare_pages"))
    }

    // MARK: - Turning targets on and off

    @MainActor
    func testTurningATargetOnThenOffLeavesNoTraceOfItsOldPath() throws {
        let configuration: CourseConfiguration = try roundTripped(["course_code": "ICS3U"])
        configuration.setAdditionalDeployTarget(true, ofType: "local_folder")
        configuration.setAdditionalDeployTargetPath("/Users/teacher/OldFolder", ofType: "local_folder")
        XCTAssertEqual(configuration.additionalDeployTargetPath(ofType: "local_folder"), "/Users/teacher/OldFolder")

        configuration.setAdditionalDeployTarget(false, ofType: "local_folder")
        XCTAssertFalse(configuration.hasAdditionalDeployTarget(ofType: "local_folder"))

        // Re-enabling starts blank — a stale folder from months ago can
        // never come back silently.
        configuration.setAdditionalDeployTarget(true, ofType: "local_folder")
        XCTAssertEqual(configuration.additionalDeployTargetPath(ofType: "local_folder"), "")
    }

    // MARK: - The invariant: a type is never both primary and additional

    @MainActor
    func testAvailableAdditionalTypesExcludesWhicheverIsPrimary() throws {
        let configuration: CourseConfiguration = try roundTripped(["course_code": "ICS3U", "deploy_target": "netlify"])
        XCTAssertEqual(configuration.availableAdditionalDeployTargetTypes(), ["cloudflare_pages", "local_folder"])

        configuration.deployTarget = "cloudflare_pages"
        XCTAssertEqual(configuration.availableAdditionalDeployTargetTypes(), ["netlify", "local_folder"])
    }

    @MainActor
    func testSwitchingThePrimaryOntoAConfiguredAdditionalTargetDropsItFromTheAdditionalList() throws {
        let configuration: CourseConfiguration = try roundTripped(["course_code": "ICS3U", "deploy_target": "netlify"])
        configuration.setAdditionalDeployTarget(true, ofType: "cloudflare_pages")
        XCTAssertTrue(configuration.hasAdditionalDeployTarget(ofType: "cloudflare_pages"))

        // The teacher switches the PRIMARY picker onto Cloudflare — the
        // model's own setter must not let it also stay listed as
        // additional, since deploying to the same destination twice makes
        // no sense.
        configuration.deployTarget = "cloudflare_pages"
        XCTAssertFalse(configuration.hasAdditionalDeployTarget(ofType: "cloudflare_pages"),
                        "A destination can never be both primary and additional at once.")
    }

    // MARK: - PublishingChoiceView's own derived state

    @MainActor
    func testTheViewOffersEveryTypeExceptWhicheverIsPrimary() {
        let held: HeldPublishingChoice = HeldPublishingChoice()
        held.deployTarget = "netlify"
        XCTAssertEqual(held.view.availableAdditionalDeployTargetTypes, ["cloudflare_pages", "local_folder"])
    }

    /// `CourseConfiguration.pruningAdditionalTargets` is the one place both
    /// the model's `deployTarget` setter (for Course Settings, which binds
    /// straight to the model) and `PublishingChoiceView`'s own `onChange`
    /// (for the wizard's plain `@State`, not yet backed by a model) get
    /// this invariant from — a plain function, tested directly rather than
    /// through either caller, so it does not need a live model instance or
    /// a rendered view to verify.
    @MainActor
    func testPruningAdditionalTargetsDropsOnlyTheMatchingType() {
        let targets: [CourseConfiguration.AdditionalDeployTarget] = [
            CourseConfiguration.AdditionalDeployTarget(type: "cloudflare_pages", path: ""),
            CourseConfiguration.AdditionalDeployTarget(type: "local_folder", path: "/Users/teacher/Sites"),
        ]

        let pruned: [CourseConfiguration.AdditionalDeployTarget] =
            CourseConfiguration.pruningAdditionalTargets(targets, ofType: "cloudflare_pages")

        XCTAssertEqual(pruned, [
            CourseConfiguration.AdditionalDeployTarget(type: "local_folder", path: "/Users/teacher/Sites"),
        ])
    }

    @MainActor
    func testPruningAdditionalTargetsIsANoOpWhenTheTypeIsntListed() {
        let targets: [CourseConfiguration.AdditionalDeployTarget] = [
            CourseConfiguration.AdditionalDeployTarget(type: "local_folder", path: "/Users/teacher/Sites"),
        ]

        let pruned: [CourseConfiguration.AdditionalDeployTarget] =
            CourseConfiguration.pruningAdditionalTargets(targets, ofType: "netlify")

        XCTAssertEqual(pruned, targets)
    }

    @MainActor
    func testAdditionalCloudflareNeedsTheSameAccountIDAsPrimaryCloudflareWould() {
        let held: HeldPublishingChoice = HeldPublishingChoice()
        held.deployTarget = "netlify"
        held.additionalDeployTargets = [
            CourseConfiguration.AdditionalDeployTarget(type: "cloudflare_pages", path: ""),
        ]
        held.cloudflareAccountID = ""

        XCTAssertNotNil(held.view.problem, "An additional Cloudflare target with no Account ID must block saving.")

        held.cloudflareAccountID = "0123456789abcdef0123456789abcdef"
        XCTAssertNil(held.view.problem)
    }

    @MainActor
    func testAdditionalLocalFolderNeedsItsOwnValidPath() {
        let held: HeldPublishingChoice = HeldPublishingChoice()
        held.deployTarget = "netlify"
        held.additionalDeployTargets = [
            CourseConfiguration.AdditionalDeployTarget(type: "local_folder", path: ""),
        ]

        XCTAssertNotNil(held.view.problem, "An additional folder target with no path must block saving.")

        held.additionalDeployTargets = [
            CourseConfiguration.AdditionalDeployTarget(type: "local_folder", path: NSTemporaryDirectory()),
        ]
        XCTAssertNil(held.view.problem)
    }

    @MainActor
    func testAllThreeSlotsCanBeFilledAtOnce() {
        // One primary plus both other known types switched on as
        // additional — the maximum this repo's design settles on: one of
        // each known type, never two of the same type. Each non-primary
        // type keeps its own toggle row regardless of whether it is
        // currently on — a toggle that vanished the moment it was turned
        // on would be the one control in this app that behaves that way.
        let held: HeldPublishingChoice = HeldPublishingChoice()
        held.deployTarget = "local_folder"
        held.deployFolderPath = NSTemporaryDirectory()
        held.cloudflareAccountID = "0123456789abcdef0123456789abcdef"
        held.additionalDeployTargets = [
            CourseConfiguration.AdditionalDeployTarget(type: "netlify", path: ""),
            CourseConfiguration.AdditionalDeployTarget(type: "cloudflare_pages", path: ""),
        ]

        XCTAssertEqual(held.view.availableAdditionalDeployTargetTypes, ["netlify", "cloudflare_pages"])
        XCTAssertTrue(held.view.toggleBinding(forType: "netlify").wrappedValue)
        XCTAssertTrue(held.view.toggleBinding(forType: "cloudflare_pages").wrappedValue)
        XCTAssertNil(held.view.problem)
    }
}
