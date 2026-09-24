import XCTest
@testable import QuartzTeachers

/// Issue #265: what Course Settings says after a Save that a running preview
/// or publish cannot see, what a preview says when it starts with unsaved
/// settings, and the contract both apps read those sentences and the
/// two-window rule from.
final class SettingsSaveNoticeTests: XCTestCase {

    // MARK: - Functions

    /// The folder a lease or publish record names, as the section view
    /// writes it.
    let folder: String = "/Users/teacher/Class Websites"

    @MainActor
    func testASaveWithAPreviewOpenOffersPreviewAgainForThatSection() {
        let leases: [PreviewLeases.Lease] = [
            PreviewLeases.Lease(port: 8081, folderPath: folder, courseCode: "ICS4U", sectionNumber: 2),
            PreviewLeases.Lease(port: 8082, folderPath: folder, courseCode: "MPM2D", sectionNumber: 1),
            PreviewLeases.Lease(port: 8083, folderPath: "/Users/teacher/Other", courseCode: "ICS4U", sectionNumber: 1),
        ]
        let notice: SettingsSaveNotice? = SettingsSaveNotice.afterSave(
            folderPath: folder + "/", courseCode: "ICS4U", previewLeases: leases, publishes: []
        )
        XCTAssertEqual(notice?.sentences, [SpecialNames.settingsSavedWhilePreviewing])
        XCTAssertEqual(notice?.sectionsToPreviewAgain, [2])
    }

    @MainActor
    func testASaveWithNothingRunningSaysNothing() {
        XCTAssertNil(SettingsSaveNotice.afterSave(
            folderPath: folder, courseCode: "ICS4U", previewLeases: [], publishes: []
        ))
    }

    /// A3: a publish takes precedence and no Preview Again is offered, since
    /// a preview is refused while that course publishes.
    @MainActor
    func testASaveDuringAPublishSaysThePublishUsesTheEarlierSettings() {
        let leases: [PreviewLeases.Lease] = [
            PreviewLeases.Lease(port: 8081, folderPath: folder, courseCode: "ICS4U", sectionNumber: 1),
        ]
        let publishes: [CourseActivity.PublishRecord] = [
            CourseActivity.PublishRecord(folderPath: folder, courseCode: "ICS4U", sectionNumber: 2),
        ]
        let notice: SettingsSaveNotice? = SettingsSaveNotice.afterSave(
            folderPath: folder, courseCode: "ICS4U", previewLeases: leases, publishes: publishes
        )
        XCTAssertEqual(notice?.sentences, [SpecialNames.settingsSavedWhilePublishing])
        XCTAssertEqual(notice?.sectionsToPreviewAgain, [])
    }

    @MainActor
    func testAPreviewStartedWithUnsavedSettingsSaysSo() {
        XCTAssertEqual(
            SettingsSaveNotice.whenPreviewStarts(settingsHaveUnsavedChanges: true),
            SpecialNames.previewUsesSavedSettings
        )
        XCTAssertNil(SettingsSaveNotice.whenPreviewStarts(settingsHaveUnsavedChanges: false))
    }

    /// The trail line names what the Save hid and showed, what it kept from
    /// elsewhere, and what was running — the line that would have settled
    /// #265 in one read.
    @MainActor
    func testTheTrailLineSaysWhatTheSaveDidAndWhatWasRunning() {
        var result: CourseConfiguration.WriteResult = CourseConfiguration.WriteResult()
        result.keptFromElsewhere = ["shared_folders"]
        let notice: SettingsSaveNotice = SettingsSaveNotice(
            sentences: [SpecialNames.settingsSavedWhilePreviewing], sectionsToPreviewAgain: [1]
        )
        let line: String = SettingsSaveNotice.trailLine(
            courseCode: "ICS4U",
            hiddenBefore: ["Media", "Concepts"],
            hiddenAfter: ["Media", "Tasks"],
            result: result,
            notice: notice
        )
        XCTAssertTrue(line.hasPrefix("saved the settings for ICS4U"))
        XCTAssertTrue(line.contains("hid Tasks"))
        XCTAssertTrue(line.contains("showed Concepts"))
        XCTAssertTrue(line.contains("shared_folders"))
        XCTAssertTrue(line.contains("a preview was open (section 1)"))

        let plain: String = SettingsSaveNotice.trailLine(
            courseCode: "ICS4U", hiddenBefore: ["Media"], hiddenAfter: ["Media"],
            result: CourseConfiguration.WriteResult(), notice: nil
        )
        XCTAssertEqual(plain, "saved the settings for ICS4U")
    }

    // MARK: - The contract

    /// `contracts/shared-rules.json`, one top-level section of it.
    func sharedRulesSection(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in shared-rules.json")
    }

    /// The three sentences are the contract's, word for word, and none of
    /// them carries a `reason` key: Windows' `NoBlockedSentenceInTheContractIsUnusedHere`
    /// sweeps every `reason` under `specialNames` expecting a flyout sentence,
    /// so one here would turn their suite red for nothing.
    func testTheSentencesMatchTheContractAndAreNotBlockedSentences() throws {
        let section: [String: Any] = try sharedRulesSection("specialNames")
        let expected: [String: String] = [
            "settingsSavedWhilePreviewing": SpecialNames.settingsSavedWhilePreviewing,
            "settingsSavedWhilePublishing": SpecialNames.settingsSavedWhilePublishing,
            "previewUsesSavedSettings": SpecialNames.previewUsesSavedSettings,
        ]
        for (key, sentence) in expected {
            let entry: [String: Any] = try XCTUnwrap(section[key] as? [String: Any], "specialNames.\(key) is missing")
            XCTAssertEqual(entry["message"] as? String, sentence, "specialNames.\(key) and SpecialNames disagree")
            XCTAssertNil(entry["reason"], "specialNames.\(key) must use `message`, never `reason`")
        }
    }

    /// No teacher-facing sentence names the machinery (rule 1).
    func testTheSentencesNameNoMachinery() {
        let sentences: [String] = [
            SpecialNames.settingsSavedWhilePreviewing,
            SpecialNames.settingsSavedWhilePublishing,
            SpecialNames.previewUsesSavedSettings,
        ]
        let forbidden: [String] = ["toolchain", "script", "docker", "container", "symlink", "vault", "config", "json", "build"]
        for sentence in sentences {
            for word in forbidden {
                XCTAssertFalse(sentence.lowercased().contains(word), "“\(sentence)” names “\(word)”")
            }
        }
    }

    /// The views DRAW the constants: a contract test alone stays green if the
    /// line that renders one is deleted.
    func testTheViewsDrawTheSentencesFromTheirOneHome() throws {
        let productFolderURL: URL = ActivityTrailWiringTests.productSourceFolderURL()
        var noticeSource: String = ""
        var sectionSource: String = ""
        var settingsSource: String = ""
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: productFolderURL) {
            if fileURL.lastPathComponent == "SettingsSaveNotice.swift" {
                noticeSource = try String(contentsOf: fileURL, encoding: .utf8)
            }
            if fileURL.lastPathComponent == "SectionDetailView.swift" {
                sectionSource = try String(contentsOf: fileURL, encoding: .utf8)
            }
            if fileURL.lastPathComponent == "CourseSettingsView.swift" {
                settingsSource = try String(contentsOf: fileURL, encoding: .utf8)
            }
        }
        XCTAssertTrue(noticeSource.contains("SpecialNames.settingsSavedWhilePreviewing"))
        XCTAssertTrue(noticeSource.contains("SpecialNames.settingsSavedWhilePublishing"))
        XCTAssertTrue(noticeSource.contains("SpecialNames.previewUsesSavedSettings"))
        XCTAssertTrue(settingsSource.contains("SettingsSaveNotice.afterSave("), "Course Settings no longer asks what to say after a Save")
        XCTAssertTrue(settingsSource.contains("Text(sentence)"), "Course Settings no longer draws the after-Save sentences")
        XCTAssertTrue(settingsSource.contains("Button(\"Preview Again\")"), "Course Settings lost its Preview Again button")
        XCTAssertTrue(
            settingsSource.contains("reloadIfNothingUnsaved(url:"),
            "Course Settings no longer reads the file again when opened, so a folder the build discovered is not offered"
        )
        XCTAssertTrue(sectionSource.contains("SettingsSaveNotice.whenPreviewStarts("), "Starting a preview no longer asks about unsaved settings")
        XCTAssertTrue(sectionSource.contains("Text(unsavedSettingsNotice)"), "The section no longer draws the unsaved-settings sentence")
    }

    /// `savingSettings.cases`: the two-window rule as data, run against the
    /// one merge every Save goes through.
    @MainActor
    func testEverySavingSettingsCaseMergesAsTheContractSays() throws {
        let section: [String: Any] = try sharedRulesSection("savingSettings")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for testCase in cases {
            let name: String = testCase["name"] as? String ?? "?"
            let base: [String: Any] = try XCTUnwrap(testCase["base"] as? [String: Any])
            let onDisk: [String: Any] = try XCTUnwrap(testCase["onDisk"] as? [String: Any])
            let mine: [String: Any] = try XCTUnwrap(testCase["mine"] as? [String: Any])
            let written: [String: Any] = try XCTUnwrap(testCase["written"] as? [String: Any])
            var result: CourseConfiguration.WriteResult = CourseConfiguration.WriteResult()
            let merged: [String: Any] = CourseConfiguration.merged(mine: mine, base: base, onDisk: onDisk, result: &result)
            XCTAssertTrue((merged as NSDictionary).isEqual(to: written), "case “\(name)”: wrote \(merged)")
            XCTAssertEqual(result.keptFromElsewhere, testCase["keptFromElsewhere"] as? [String], "case “\(name)”")
            XCTAssertEqual(
                result.replacedChangesFromElsewhere,
                testCase["replacedChangesFromElsewhere"] as? [String],
                "case “\(name)”"
            )
        }
    }
}
