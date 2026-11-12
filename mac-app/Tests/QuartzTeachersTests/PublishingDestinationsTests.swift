import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Runs `contracts/app-rules.json` → `publishingDestinations` (GitHub #668):
/// a new course deploys to Cloudflare Pages, a file with no destination still
/// deploys to Netlify, the sentences a teacher reads while choosing, when each
/// is shown, and the two halves of the Account ID rule — the new-course window
/// lets a MISSING ID wait, and the first deploy refuses it.
@MainActor
final class PublishingDestinationsTests: XCTestCase {

    // MARK: - The default, and what an absent key means

    func testANewCourseStartsOnTheContractsDefault() throws {
        let block: [String: Any] = try PublishingDestinationsTests.block()
        XCTAssertEqual(PublishingDestinations.newCourseDefault, try XCTUnwrap(block["newCourseDefault"] as? String))
        XCTAssertEqual(PublishingDestinations.newCourseDefault, "cloudflare_pages")

        // What the new-course window WRITES, not just what it holds: the
        // fallback below must only ever reach files written before it.
        let wizard: NewCourseWizardView = NewCourseWizardView(courseCode: "AMU3M", prepopulatesExampleContent: false)
        let written: [String: Any] = wizard.buildConfigurationDictionary(code: "AMU3M", name: "A Course")
        XCTAssertEqual(written["deploy_target"] as? String, "cloudflare_pages",
                       "the new-course window must write the new-course default into every course it makes")
    }

    func testAFileWithNoDestinationStillDeploysToNetlify() throws {
        let block: [String: Any] = try PublishingDestinationsTests.block()
        XCTAssertEqual(PublishingDestinations.whenTheKeyIsAbsent, try XCTUnwrap(block["whenTheKeyIsAbsent"] as? String))
        XCTAssertEqual(PublishingDestinations.whenTheKeyIsAbsent, "netlify")

        for stored in [nil, ""] as [String?] {
            var values: [String: Any] = ["course_code": "ICS3U"]
            if let stored {
                values["deploy_target"] = stored
            }
            let configuration: CourseConfiguration = try PublishingDestinationsTests.roundTripped(values)
            XCTAssertEqual(configuration.deployTarget, "netlify",
                           "a course written before #668 must keep deploying where it always has (stored: \(String(describing: stored)))")
        }
    }

    func testThePickerOffersTheContractsOrder() throws {
        let block: [String: Any] = try PublishingDestinationsTests.block()
        XCTAssertEqual(CourseConfiguration.knownDeployTargetTypes, try XCTUnwrap(block["pickerOrder"] as? [String]))
    }

    // MARK: - The sentences

    func testTheSentencesAreTheContracts() throws {
        let block: [String: Any] = try PublishingDestinationsTests.block()
        let sentences: [String: String] = try XCTUnwrap(block["sentences"] as? [String: String])
        XCTAssertEqual(sentences.count, 6, "a sentence was added to the contract without a Swift twin, or removed")
        XCTAssertEqual(PublishingDestinations.wizardCaption, sentences["wizardCaption"])
        XCTAssertEqual(PublishingDestinations.cloudflareCaption, sentences["cloudflareCaption"])
        XCTAssertEqual(PublishingDestinations.netlifyNote, sentences["netlifyNote"])
        XCTAssertEqual(PublishingDestinations.netlifyScheduleNote, sentences["netlifyScheduleNote"])
        XCTAssertEqual(PublishingDestinations.accountIDCanWait, sentences["accountIDCanWait"])
        XCTAssertEqual(PublishingDestinations.cloudflareSizeNote, sentences["cloudflareSizeNote"])

        // What spends Netlify's allowance is a DEPLOY; publishing marks a
        // page. And no figures: the hosts change them (#668, M2 and M3).
        for (name, sentence) in sentences {
            XCTAssertFalse(sentence.lowercased().contains("publish"), "\(name) says publish for a deploy")
            // The size note's 25 is the one figure kept: Cloudflare's
            // per-file limit is the fact that sentence exists to state (#775).
            for digit in "0123456789" where name != "netlifyNote" && name != "cloudflareSizeNote" {
                XCTAssertFalse(sentence.contains(digit), "\(name) carries a figure")
            }
        }
        // The note's only figure is the year Netlify's plans changed.
        var figuresInTheNote: String = PublishingDestinations.netlifyNote
        figuresInTheNote = figuresInTheNote.replacingOccurrences(of: "September 2025", with: "")
        for digit in "0123456789" {
            XCTAssertFalse(figuresInTheNote.contains(digit), "netlifyNote carries a figure besides its date")
        }
    }

    // MARK: - When each is shown

    func testTheNetlifyNoteAndTheCloudflareCaptionCases() throws {
        let block: [String: Any] = try PublishingDestinationsTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["netlifyNoteCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7, "the contract lost note cases")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let primary: String = try XCTUnwrap(testCase["primary"] as? String)
            let additional: [String] = try XCTUnwrap(testCase["additional"] as? [String])
            XCTAssertEqual(
                PublishingDestinations.showsNetlifyNote(primary: primary, additional: additional),
                try XCTUnwrap(testCase["expectNetlifyNote"] as? Bool), name
            )
            XCTAssertEqual(
                PublishingDestinations.showsCloudflareCaption(primary: primary, additional: additional),
                try XCTUnwrap(testCase["expectCloudflareCaption"] as? Bool), name
            )

            // The schedule sheet asks the same question of the SAVED file.
            var values: [String: Any] = ["course_code": "ICS3U", "deploy_target": primary]
            var entries: [[String: Any]] = []
            for type in additional {
                entries.append(["type": type])
            }
            if !entries.isEmpty {
                values["additional_deploy_targets"] = entries
            }
            let configuration: CourseConfiguration = try PublishingDestinationsTests.roundTripped(values)
            let expectNote: Bool = try XCTUnwrap(testCase["expectNetlifyNote"] as? Bool)
            XCTAssertEqual(
                ScheduleDeploySheet.netlifyNote(for: configuration),
                expectNote ? PublishingDestinations.netlifyScheduleNote : nil,
                "schedule sheet: \(name)"
            )
        }
    }

    // MARK: - The Account ID: the window lets it wait, the deploy refuses

    func testTheNewCourseWindowLetsAMissingAccountIDWait() throws {
        let block: [String: Any] = try PublishingDestinationsTests.block()
        let section: [String: Any] = try XCTUnwrap(block["wizardAccountID"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4, "the contract lost Account ID cases")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let accountID: String = try XCTUnwrap(testCase["accountID"] as? String)
            XCTAssertEqual(
                PublishingDestinations.wizardCreateRefusal(forAccountID: accountID),
                testCase["expectCreateRefusal"] as? String, name
            )
            XCTAssertEqual(
                CourseConfiguration.cloudflareAccountProblem(forID: accountID),
                testCase["expectWarning"] as? String, name
            )
            XCTAssertEqual(
                PublishingDestinations.accountIDIsMissing(accountID),
                try XCTUnwrap(testCase["expectAccountIDCanWait"] as? Bool), name
            )
        }
    }

    /// The window's own Create must go through the rule above for BOTH places
    /// Cloudflare can be — read from the source, because the check sits in a
    /// view's button action that a unit test cannot press.
    func testTheNewCourseWindowAsksTheRuleNotTheValidation() throws {
        let source: String = try String(
            contentsOf: PublishingDestinationsTests.repositoryRoot()
                .appendingPathComponent("mac-app/QuartzTeachers/Views/Wizard/NewCourseWizardView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("CourseConfiguration.cloudflareAccountProblem("),
                       "Create refuses a missing Account ID again; it must ask PublishingDestinations.wizardCreateRefusal")
        XCTAssertEqual(source.components(separatedBy: "PublishingDestinations.wizardCreateRefusal(").count - 1, 2,
                       "the primary and the additional Cloudflare destination are both asked")
        XCTAssertTrue(source.contains("accountIDMayWait: true"),
                      "the window no longer says the ID can wait")
    }

    /// What the view itself decides, with the wizard's own starting state
    /// and with Netlify picked or added — the on-screen check of the
    /// new-course window was not driven in the #668 run, so the view's
    /// computed answers and the placement of each sentence are pinned here.
    func testTheChoiceViewShowsEachSentenceWhereTheRuleSays() throws {
        var additional: [CourseConfiguration.AdditionalDeployTarget] = []
        let additionalBinding: Binding<[CourseConfiguration.AdditionalDeployTarget]> = Binding(
            get: { return additional },
            set: { newValue in additional = newValue }
        )
        let wizardStart: PublishingChoiceView = PublishingChoiceView(
            deployTarget: .constant(PublishingDestinations.newCourseDefault),
            deployFolderPath: .constant(""),
            cloudflareAccountID: "",
            additionalDeployTargets: additionalBinding,
            accountIDMayWait: true
        )
        XCTAssertFalse(wizardStart.showsNetlifyNote, "a new course on Cloudflare is shown Netlify's note")
        XCTAssertEqual(wizardStart.accountProblem, CourseConfiguration.cloudflareAccountProblem(forID: ""),
                       "the orange sentence must stay on screen with no Account ID")
        XCTAssertNil(PublishingDestinations.wizardCreateRefusal(forAccountID: wizardStart.cloudflareAccountID),
                     "Create would be refused for the window's missing ID")

        additional = [CourseConfiguration.AdditionalDeployTarget(type: "netlify", path: "")]
        XCTAssertTrue(wizardStart.showsNetlifyNote, "Netlify switched on as an additional destination shows no note")

        let netlifyPicked: PublishingChoiceView = PublishingChoiceView(
            deployTarget: .constant("netlify"),
            deployFolderPath: .constant(""),
            cloudflareAccountID: "",
            additionalDeployTargets: .constant([])
        )
        XCTAssertTrue(netlifyPicked.showsNetlifyNote)
        XCTAssertNil(netlifyPicked.accountProblem, "Netlify alone asks nothing about Cloudflare")
        XCTAssertFalse(netlifyPicked.accountIDMayWait, "Course Settings must not say the ID can wait")

        let source: String = try String(
            contentsOf: PublishingDestinationsTests.repositoryRoot()
                .appendingPathComponent("mac-app/QuartzTeachers/Views/CourseSettings/PublishingChoiceView.swift"),
            encoding: .utf8
        )
        for needle in [
            "Text(PublishingDestinations.netlifyNote)",
            "ExampleCaption(PublishingDestinations.cloudflareCaption)",
            "Text(PublishingDestinations.accountIDCanWait + \" \")",
            "accountIDMayWait && PublishingDestinations.accountIDIsMissing(cloudflareAccountID)",
            // One block: the ID's problem, the sentence that it can wait
            // right after it, then the 25 MB fact (L5, L4).
            "return built + Text(PublishingDestinations.cloudflareSizeNote)",
        ] {
            XCTAssertTrue(source.contains(needle), "PublishingChoiceView no longer shows: \(needle)")
        }
        XCTAssertEqual(source.components(separatedBy: "NetlifyNote()").count - 1, 2,
                       "the note is placed under the picker AND under the additional Netlify toggle")
    }

    func testTheFirstDeployRefusesAMissingAccountID() throws {
        let block: [String: Any] = try PublishingDestinationsTests.block()
        let section: [String: Any] = try XCTUnwrap(block["deployWithoutAnAccountID"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "the contract lost deploy cases")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var destinations: [CourseConfiguration.DeployDestination] = []
            for type in try XCTUnwrap(testCase["destinations"] as? [String]) {
                destinations.append(CourseConfiguration.DeployDestination(type: type, path: ""))
            }
            let refusal: String? = MultiDestinationDeployRunner.refusalReason(
                destinations: destinations,
                cloudflareAccountID: try XCTUnwrap(testCase["accountID"] as? String)
            )
            let accountID: String = try XCTUnwrap(testCase["accountID"] as? String)
            let opensSettings: Bool = try XCTUnwrap(testCase["expectOpenSettings"] as? Bool)
            if let expected = testCase["expectRefusalStartsWith"] as? String {
                let said: String = try XCTUnwrap(refusal, "\(name): the deploy went ahead")
                XCTAssertTrue(said.hasPrefix(expected), "\(name): \(said)")
                if opensSettings {
                    XCTAssertTrue(said.contains("Settings ▸ Deploying"), "\(name): the refusal no longer says where to fix it")
                }
                XCTAssertEqual(
                    PublishingDestinations.deployRefusalOpensSettings(refusal: said, cloudflareAccountID: accountID),
                    opensSettings, "\(name): Open Settings…"
                )
            } else {
                XCTAssertNil(refusal, name)
                XCTAssertFalse(opensSettings, name)
            }
            XCTAssertEqual(
                ActivityTrail.deployRefusedForTheAccountIDLine(destinations: destinations, cloudflareAccountID: accountID),
                testCase["expectTrailLine"] as? String, "\(name): the trail line"
            )
        }
    }

    /// The refusal's trail event is named on both sides of the contract
    /// (rule 5), and its example line is the one the app writes.
    func testTheRefusalIsOnTheTrail() throws {
        let url: URL = PublishingDestinationsTests.repositoryRoot()
            .appendingPathComponent("contracts/shared-rules.json")
        let rules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(rules["activityTrail"] as? [String: Any])
        let mustRecord: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        var entry: [String: Any]? = nil
        for candidate in mustRecord where candidate["event"] as? String == ActivityTrail.Event.deployRefusedForTheAccountID.rawValue {
            entry = candidate
        }
        let found: [String: Any] = try XCTUnwrap(entry, "mustRecord does not name the refusal's event")
        let line: String = try XCTUnwrap(ActivityTrail.deployRefusedForTheAccountIDLine(
            destinations: [CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")],
            cloudflareAccountID: ""
        ))
        XCTAssertEqual(found["line"] as? String, "ICS3U/1 · " + line)

        // And the window writes it, and offers Open Settings… — read from the
        // source, because both sit in a view's own deploy path and alert.
        let window: String = try String(
            contentsOf: PublishingDestinationsTests.repositoryRoot()
                .appendingPathComponent("mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(window.contains("ActivityTrail.note(.deployRefusedForTheAccountID"),
                      "the Deploy button's refusal no longer reaches the trail")
        XCTAssertTrue(window.contains("PublishingDestinations.deployRefusalOpensSettings("),
                      "the Cannot Deploy Yet alert no longer offers Open Settings…")
        XCTAssertTrue(window.contains("SettingsPane.select(.deploying)"),
                      "Open Settings… no longer opens the Deploying pane")
    }

    // MARK: - Private

    private static func block() throws -> [String: Any] {
        let url: URL = repositoryRoot()
            .appendingPathComponent("contracts")
            .appendingPathComponent(AppRulesContract.fileName)
        let rules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(rules["publishingDestinations"] as? [String: Any])
    }

    private static func roundTripped(_ values: [String: Any]) throws -> CourseConfiguration {
        let data: Data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        let url: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("publishing-destinations-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try CourseConfiguration(contentsOf: url)
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
