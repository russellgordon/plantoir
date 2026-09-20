import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Cloudflare Pages as a third deploy destination: the setting round-trips
/// through `course_config.json`, the Account ID is validated in plain words,
/// the launcher is asked for the right thing, and nothing on the Cloudflare
/// path ever says "Netlify".
final class CloudflareDeployTests: XCTestCase {

    // MARK: - Functions

    /// A configuration written to disk and read back, the way the app and
    /// the command-line scripts both see it.
    @MainActor
    func roundTripped(_ values: [String: Any]) throws -> CourseConfiguration {
        let data: Data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudflare_config_\(UUID().uuidString).json")
        try data.write(to: fileURL)
        return try CourseConfiguration(contentsOf: fileURL)
    }

    // MARK: - The setting

    @MainActor
    func testCloudflareIsAThirdDestinationAndRoundTrips() throws {
        let configuration: CourseConfiguration = try roundTripped([
            "course_code": "MCV4U",
            "course_name": "Calculus and Vectors",
            "deploy_target": "cloudflare_pages",
        ])

        XCTAssertEqual(configuration.deployTarget, "cloudflare_pages")
        XCTAssertTrue(configuration.deploysToCloudflare)
        XCTAssertFalse(configuration.deploysToLocalFolder)

        // Written back out and read again: the spelling is shared with the
        // Windows app, which reads the same file, so it must survive a trip
        // through this app untouched.
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudflare_rewrite_\(UUID().uuidString).json")
        try configuration.write(to: fileURL)
        let reread: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        XCTAssertEqual(reread.deployTarget, "cloudflare_pages")
        XCTAssertTrue(reread.deploysToCloudflare)
    }

    @MainActor
    func testTheOtherDestinationsAreNotMistakenForCloudflare() throws {
        let netlify: CourseConfiguration = try roundTripped(["course_code": "ICS3U"])
        XCTAssertEqual(netlify.deployTarget, "netlify", "Netlify stays the default")
        XCTAssertFalse(netlify.deploysToCloudflare)

        let folder: CourseConfiguration = try roundTripped([
            "course_code": "ICS3U",
            "deploy_target": "local_folder",
            "deploy_folder_path": NSTemporaryDirectory(),
        ])
        XCTAssertFalse(folder.deploysToCloudflare)
        XCTAssertTrue(folder.deploysToLocalFolder)
    }

    @MainActor
    func testChangingDestinationKeepsEverythingElseInTheFile() throws {
        let configuration: CourseConfiguration = try roundTripped([
            "course_code": "MCV4U",
            "course_name": "Calculus and Vectors",
            "deploy_target": "netlify",
            "some_future_key_the_app_does_not_know": ["keep": "me"],
        ])
        configuration.deployTarget = "cloudflare_pages"

        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudflare_keep_\(UUID().uuidString).json")
        try configuration.write(to: fileURL)
        let reread: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        XCTAssertTrue(reread.deploysToCloudflare)
        XCTAssertNotNil(reread.values["some_future_key_the_app_does_not_know"])
        XCTAssertEqual(reread.courseName, "Calculus and Vectors")
    }

    // MARK: - The Account ID

    @MainActor
    func testAccountProblemsAreNamedInPlainWords() {
        XCTAssertEqual(
            CourseConfiguration.cloudflareAccountProblem(forID: ""),
            "Paste your Cloudflare Account ID."
        )
        XCTAssertEqual(
            CourseConfiguration.cloudflareAccountProblem(forID: "   "),
            "Paste your Cloudflare Account ID."
        )

        // 32 hexadecimal characters, in either case, trimmed.
        XCTAssertNil(CourseConfiguration.cloudflareAccountProblem(forID: "0123456789abcdef0123456789abcdef"))
        XCTAssertNil(CourseConfiguration.cloudflareAccountProblem(forID: "0123456789ABCDEF0123456789ABCDEF"))
        XCTAssertNil(CourseConfiguration.cloudflareAccountProblem(forID: "  0123456789abcdef0123456789abcdef  "))

        XCTAssertNotNil(CourseConfiguration.cloudflareAccountProblem(forID: "0123456789abcdef0123456789abcde"),
                        "31 characters is not an Account ID")
        XCTAssertNotNil(CourseConfiguration.cloudflareAccountProblem(forID: "0123456789abcdef0123456789abcdef0"),
                        "33 characters is not an Account ID")
        XCTAssertNotNil(CourseConfiguration.cloudflareAccountProblem(forID: "0123456789abcdef0123456789abcdez"),
                        "A 'z' is not a hexadecimal digit")
    }

    @MainActor
    func testTheAccountIDIsRememberedForTheTeacherNotTheCourse() {
        let defaults: UserDefaults = TestDefaults.make()
        let settings: AppSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.cloudflareAccountID, "")

        settings.cloudflareAccountID = "0123456789abcdef0123456789abcdef"
        let reopened: AppSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.cloudflareAccountID, "0123456789abcdef0123456789abcdef",
                       "Entered once, and every Cloudflare course uses it")
    }

    // MARK: - What the launcher is asked for

    @MainActor
    func testTheLauncherIsAskedForTheRightDestination() throws {
        let netlify: CourseConfiguration = try roundTripped(["course_code": "ICS3U"])
        XCTAssertEqual(
            DeployCommand.arguments(
                courseCode: "ICS3U", sectionNumber: 1,
                configuration: netlify, cloudflareAccountID: "0123456789abcdef0123456789abcdef"
            ),
            ["ICS3U", "1"],
            "Netlify is deploy.sh's own default, so it passes no target flag at all"
        )

        let cloudflare: CourseConfiguration = try roundTripped([
            "course_code": "MCV4U",
            "deploy_target": "cloudflare_pages",
        ])
        XCTAssertEqual(
            DeployCommand.arguments(
                courseCode: "MCV4U", sectionNumber: 2,
                configuration: cloudflare, cloudflareAccountID: " 0123456789abcdef0123456789abcdef "
            ),
            ["MCV4U", "2", "--target", "cloudflare", "--account", "0123456789abcdef0123456789abcdef"]
        )

        let folder: CourseConfiguration = try roundTripped([
            "course_code": "ICS3U",
            "deploy_target": "local_folder",
            "deploy_folder_path": "/Users/teacher/Sites",
        ])
        XCTAssertEqual(
            DeployCommand.arguments(
                courseCode: "ICS3U", sectionNumber: 1,
                configuration: folder, cloudflareAccountID: ""
            ),
            ["ICS3U", "1", "--to-folder", "/Users/teacher/Sites"]
        )
    }

    @MainActor
    func testEachDestinationIsNamedForTheTeacher() throws {
        let cloudflare: CourseConfiguration = try roundTripped([
            "course_code": "MCV4U", "deploy_target": "cloudflare_pages",
        ])
        XCTAssertEqual(DeployCommand.destinationDescription(for: cloudflare), "Cloudflare Pages")

        let netlify: CourseConfiguration = try roundTripped(["course_code": "ICS3U"])
        XCTAssertEqual(DeployCommand.destinationDescription(for: netlify), "Netlify")

        let folder: CourseConfiguration = try roundTripped([
            "course_code": "ICS3U",
            "deploy_target": "local_folder",
            "deploy_folder_path": "/Users/teacher/Sites",
        ])
        XCTAssertEqual(DeployCommand.destinationDescription(for: folder), "/Users/teacher/Sites")
    }

    /// Cloudflare and Netlify keep separate first-deploy markers, mirroring
    /// each other, so switching destination does not make a section look as
    /// though it has already been deployed to the new one.
    @MainActor
    func testEachDestinationHasItsOwnFirstDeployMarker() throws {
        let courseURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)

        let cloudflare: Course = Course(
            code: "MCV4U",
            directoryURL: courseURL,
            configuration: try roundTripped(["course_code": "MCV4U", "deploy_target": "cloudflare_pages"])
        )
        let netlify: Course = Course(
            code: "MCV4U",
            directoryURL: courseURL,
            configuration: try roundTripped(["course_code": "MCV4U"])
        )

        XCTAssertEqual(
            DeployCommand.firstDeployMarkerURL(forSection: 1, in: cloudflare)?.lastPathComponent,
            "section1.json"
        )
        XCTAssertTrue(
            DeployCommand.firstDeployMarkerURL(forSection: 1, in: cloudflare)?.path
                .contains(".cloudflare_sites") ?? false
        )
        XCTAssertTrue(
            DeployCommand.firstDeployMarkerURL(forSection: 1, in: netlify)?.path
                .contains(".netlify_sites") ?? false
        )

        XCTAssertFalse(DeployCommand.hasDeployedBefore(section: 1, in: cloudflare))

        // A folder deploy asks nothing, so it keeps no marker and is always
        // ready to go.
        let folder: Course = Course(
            code: "MCV4U",
            directoryURL: courseURL,
            configuration: try roundTripped([
                "course_code": "MCV4U",
                "deploy_target": "local_folder",
                "deploy_folder_path": NSTemporaryDirectory(),
            ])
        )
        XCTAssertNil(DeployCommand.firstDeployMarkerURL(forSection: 1, in: folder))
        XCTAssertTrue(DeployCommand.hasDeployedBefore(section: 1, in: folder))
    }

    // MARK: - What the teacher is shown

    @MainActor
    func testCloudflareProgressNeverMentionsNetlify() {
        for list in [TaskMilestones.deployToCloudflare, TaskMilestones.buildAndDeployToCloudflare] {
            XCTAssertFalse(list.isEmpty)
            for milestone in list {
                XCTAssertFalse(milestone.label.contains("Netlify"),
                               "“\(milestone.label)” names the wrong service")
                XCTAssertTrue(milestone.label.hasSuffix("…"), "“\(milestone.label)” must end with an ellipsis")
                XCTAssertLessThanOrEqual(milestone.label.count, 32)
            }
        }

        var labels: [String] = []
        for milestone in TaskMilestones.deployToCloudflare {
            labels.append(milestone.label)
        }
        XCTAssertTrue(labels.contains("Connecting to Cloudflare…"))
    }

    /// Both the create and the reuse path have to move the bar. `deploy.py`
    /// prints "Cloudflare project ready: …" the first time and "Using this
    /// section's existing Cloudflare project: …" every time after, so the
    /// marker is the phrase they share.
    @MainActor
    func testTheCloudflareMarkerMatchesBothFirstAndLaterDeploys() throws {
        var marker: String = ""
        for milestone in TaskMilestones.deployToCloudflare where milestone.label == "Connecting to Cloudflare…" {
            marker = milestone.marker
        }
        XCTAssertFalse(marker.isEmpty)
        XCTAssertTrue(" Cloudflare project ready: mcv4u-s1-2026-gordon".contains(marker))
        XCTAssertTrue(" Using this section's existing Cloudflare project: mcv4u-s1-2026-gordon".contains(marker))
    }

    /// `deploy.py` prints the same "Live URL:" label whichever destination
    /// it used, so the existing parser needed no change.
    @MainActor
    func testTheCloudflareAddressIsReadFromTheSameLabel() {
        let output: String = " Uploading the built site to Cloudflare…\n Live URL: https://mcv4u-s1-2026-gordon.pages.dev\n\n✅ Deploy complete.\n"
        let address: URL? = ScriptRunner.publishedSiteURL(in: output)
        XCTAssertEqual(address?.absoluteString, "https://mcv4u-s1-2026-gordon.pages.dev")
    }

    @MainActor
    func testDeployingWithoutAnAccountIDIsRefusedBeforeAnyBuilding() throws {
        let cloudflare: CourseConfiguration = try roundTripped([
            "course_code": "MCV4U", "deploy_target": "cloudflare_pages",
        ])
        let refusal: String? = SectionDetailView.deployRefusalReason(
            configuration: cloudflare, cloudflareAccountID: ""
        )
        let text: String = try XCTUnwrap(refusal)
        XCTAssertTrue(text.contains("Paste your Cloudflare Account ID."))
        XCTAssertTrue(text.contains("under Deploying"))

        XCTAssertNil(SectionDetailView.deployRefusalReason(
            configuration: cloudflare, cloudflareAccountID: "0123456789abcdef0123456789abcdef"
        ))
    }

    @MainActor
    func testTheChoiceViewGatesSavingOnWhicheverDestinationIsChosen() {
        let held: HeldPublishingChoice = HeldPublishingChoice()
        held.deployTarget = "cloudflare_pages"

        XCTAssertNotNil(held.view.problem)
        XCTAssertNil(held.view.folderProblem, "The folder is irrelevant while Cloudflare is chosen")

        held.cloudflareAccountID = "0123456789abcdef0123456789abcdef"
        XCTAssertNil(held.view.problem)

        // And the folder's own check still applies when it is the choice.
        held.deployTarget = "local_folder"
        XCTAssertNotNil(held.view.problem)
        XCTAssertNil(held.view.accountProblem, "The account is irrelevant while a folder is chosen")

        held.deployFolderPath = NSTemporaryDirectory()
        XCTAssertNil(held.view.problem)
    }
}

/// Somewhere for a `PublishingChoiceView`'s bindings to point while a test
/// changes what the teacher has chosen. A SwiftUI `@State` property has no
/// backing store until the view is on screen, so the values have to live
/// outside the view for this to be testable at all.
@MainActor
final class HeldPublishingChoice {

    // MARK: - Stored properties

    var deployTarget: String = "netlify"
    var deployFolderPath: String = ""
    var cloudflareAccountID: String = ""
    var additionalDeployTargets: [CourseConfiguration.AdditionalDeployTarget] = []

    // MARK: - Computed properties

    var view: PublishingChoiceView {
        return PublishingChoiceView(
            deployTarget: Binding(
                get: { self.deployTarget },
                set: { newValue in self.deployTarget = newValue }
            ),
            deployFolderPath: Binding(
                get: { self.deployFolderPath },
                set: { newValue in self.deployFolderPath = newValue }
            ),
            cloudflareAccountID: Binding(
                get: { self.cloudflareAccountID },
                set: { newValue in self.cloudflareAccountID = newValue }
            ),
            additionalDeployTargets: Binding(
                get: { self.additionalDeployTargets },
                set: { newValue in self.additionalDeployTargets = newValue }
            )
        )
    }
}
