import XCTest

/// Drives the real app against a fixture working folder (a copy of the
/// repository checkout with the EXC2O example course) supplied via the
/// UITEST_WORKSPACE environment variable.
final class QuartzTeachersUITests: XCTestCase {

    // MARK: - Functions

    /// Launches the app pointed at a fixture workspace: the one supplied
    /// via UITEST_WORKSPACE, or a fresh disposable one built from the test
    /// bundle's resources — so plain Cmd-U needs no setup.
    func launchApp() throws -> XCUIApplication {
        let application: XCUIApplication = XCUIApplication()
        let environment: [String: String] = ProcessInfo.processInfo.environment
        if let fixturePath = environment["UITEST_WORKSPACE"] {
            application.launchEnvironment["UITEST_WORKSPACE"] = fixturePath
        } else {
            let fixtureURL: URL = try FixtureWorkspace.materialize()
            application.launchEnvironment["UITEST_WORKSPACE"] = fixtureURL.path
        }
        application.launch()
        return application
    }

    func saveScreenshot(named name: String, of application: XCUIApplication) {
        let screenshot: XCUIScreenshot = application.screenshot()
        let attachment: XCTAttachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSidebarShowsExampleCourse() throws {
        let application: XCUIApplication = try launchApp()

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10), "The EXC2O course should appear in the sidebar")

        saveScreenshot(named: "01-sidebar", of: application)
    }

    func testEditingAndSavingCourseSettings() throws {
        let application: XCUIApplication = try launchApp()

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()

        let nameField: XCUIElement = application.textFields["courseNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "The settings form should appear")

        saveScreenshot(named: "02-settings-form", of: application)

        // Toggle the reading-time setting and save.
        let readingTimeToggle: XCUIElement = application.descendants(matching: .any).matching(identifier: "readingTimeToggle").firstMatch
        XCTAssertTrue(readingTimeToggle.waitForExistence(timeout: 5))
        readingTimeToggle.click()

        let saveButton: XCUIElement = application.buttons["saveButton"]
        XCTAssertTrue(saveButton.isEnabled, "Save should enable after an edit")
        saveButton.click()

        let savedLabel: XCUIElement = application.staticTexts["savedConfirmation"]
        XCTAssertTrue(savedLabel.waitForExistence(timeout: 5), "Saving should confirm")

        saveScreenshot(named: "03-after-save", of: application)
    }

    func testWizardSuggestsCourseNameFromCode() throws {
        let application: XCUIApplication = try launchApp()

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 10))
        newCourseButton.click()

        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "The wizard sheet should appear")
        codeField.click()
        codeField.typeText("ICS3U")

        // Typing a known Ontario code should auto-fill the SHORT name.
        let nameField: XCUIElement = application.textFields["wizardCourseNameField"]
        let expectedName: String = "Intro to Comp Sci"
        let autoFilled: NSPredicate = NSPredicate(format: "value == %@", expectedName)
        let expectation: XCTNSPredicateExpectation = XCTNSPredicateExpectation(predicate: autoFilled, object: nameField)
        let waitResult: XCTWaiter.Result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(waitResult, .completed, "The course name should auto-fill from the code; value was: \(String(describing: nameField.value))")

        // The formal-name suggestion button should switch the name.
        let formalNameButton: XCUIElement = application.buttons["suggestedFormalNameButton"]
        XCTAssertTrue(formalNameButton.waitForExistence(timeout: 5))
        formalNameButton.click()
        XCTAssertEqual("\(nameField.value ?? "")", "Introduction to Computer Science, Grade 11, U")

        saveScreenshot(named: "05-wizard-name-suggestions", of: application)

        let closeButton: XCUIElement = application.buttons["wizardCloseButton"]
        closeButton.click()
    }

    /// The course-code field's popup: typing narrows a floating list of
    /// rich rows (code, example-content badge, formal name), and picking
    /// one sets both the code and — via the existing auto-fill — the
    /// course name in one action.
    func testCourseCodePopupShowsRichSuggestionsAndSelectionFillsBothFields() throws {
        let application: XCUIApplication = try launchApp()

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 10))
        newCourseButton.click()

        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "The wizard sheet should appear")
        codeField.click()
        codeField.typeText("SCH")

        let suggestionsList: XCUIElement = application.scrollViews["courseCodeSuggestionsList"]
        XCTAssertTrue(suggestionsList.waitForExistence(timeout: 5), "The popup should appear while typing")

        let sch3uRow: XCUIElement = application.buttons["courseCodeSuggestion-SCH3U"]
        XCTAssertTrue(sch3uRow.waitForExistence(timeout: 5), "SCH3U should be a suggestion for \"SCH\"")

        saveScreenshot(named: "06-course-code-popup", of: application)

        sch3uRow.click()

        // Selecting a row sets the code…
        let codeSettled: NSPredicate = NSPredicate(format: "value == %@", "SCH3U")
        let codeExpectation: XCTNSPredicateExpectation = XCTNSPredicateExpectation(predicate: codeSettled, object: codeField)
        XCTAssertEqual(XCTWaiter().wait(for: [codeExpectation], timeout: 5), .completed, "Selecting the row should set the code field to SCH3U")

        // …and the popup should close (the field now holds an exact code).
        XCTAssertFalse(suggestionsList.exists, "The popup should close once a code is chosen")

        // …and auto-fills the course name.
        let nameField: XCUIElement = application.textFields["wizardCourseNameField"]
        let nameSettled: NSPredicate = NSPredicate(format: "value == %@", "Chem")
        let nameExpectation: XCTNSPredicateExpectation = XCTNSPredicateExpectation(predicate: nameSettled, object: nameField)
        XCTAssertEqual(XCTWaiter().wait(for: [nameExpectation], timeout: 5), .completed, "Selecting a suggestion should auto-fill the course name; value was: \(String(describing: nameField.value))")

        let closeButton2: XCUIElement = application.buttons["wizardCloseButton"]
        closeButton2.click()
    }

    func testSidebarContextMenuOffersFolderActions() throws {
        let application: XCUIApplication = try launchApp()

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.rightClick()

        let showInFinder: XCUIElement = application.menuItems["Show in Finder"]
        XCTAssertTrue(showInFinder.waitForExistence(timeout: 5), "The context menu should offer Show in Finder")
        let newTerminal: XCUIElement = application.menuItems["New Terminal at Folder"]
        XCTAssertTrue(newTerminal.exists, "The context menu should offer New Terminal at Folder")

        saveScreenshot(named: "07-context-menu", of: application)

        // Close the menu without opening Finder or Terminal windows.
        application.typeKey(.escape, modifierFlags: [])
    }

    /// Restarting a preview after one has been shown must return cleanly
    /// to the progress view (this is the sequence that used to leave the
    /// progress header mis-positioned under the window's toolbar).
    ///
    /// Note: this checks BEHAVIOUR, not geometry. XCUITest reports frames
    /// for this SwiftUI content that place it outside its own window, so
    /// frame-sampling assertions here are not trustworthy — the visual
    /// result needs a human eye.
    func testRestartingAPreviewReturnsToTheProgressView() throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()

        let siteURL: URL = fixtureURL.appendingPathComponent("stub-site")
        try FileManager.default.createDirectory(at: siteURL, withIntermediateDirectories: true)
        try "<html><body><h1>Stub site</h1></body></html>".write(
            to: siteURL.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )

        let stubScript: String = """
        #!/bin/bash
        echo "Starting container if needed"
        sleep 1
        echo "Copying shared folders"
        sleep 1
        echo "Launching Quartz preview on http://localhost:8081"
        cd "\(siteURL.path)" && exec python3 -m http.server 8081 --bind 127.0.0.1
        """
        let stubURL: URL = fixtureURL.appendingPathComponent("preview.sh")
        try stubScript.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)

        let application: XCUIApplication = XCUIApplication()
        application.launchEnvironment["UITEST_WORKSPACE"] = fixtureURL.path
        application.launch()

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10))
        sectionRow.click()

        // First preview: the stub site takes over the detail area.
        application.buttons["previewButton"].click()
        let webView: XCUIElement = application.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 90), "The stub site should appear in the preview")

        // Stop, then start again — the transition that used to glitch.
        application.buttons["stopPreviewButton"].click()
        let previewButtonAgain: XCUIElement = application.buttons["previewButton"]
        XCTAssertTrue(previewButtonAgain.waitForExistence(timeout: 15))
        previewButtonAgain.click()

        let milestoneLabel: XCUIElement = application.staticTexts["taskMilestoneLabel"]
        XCTAssertTrue(milestoneLabel.waitForExistence(timeout: 15), "Progress should be shown again while the next preview builds")
        XCTAssertTrue(application.buttons["taskDetailsDisclosure"].exists, "The details toggle should be available")

        saveScreenshot(named: "08-preview-restarted", of: application)

        if application.buttons["stopPreviewButton"].exists {
            application.buttons["stopPreviewButton"].click()
        }
    }

    /// Publishing must leave the interface intact. A stub publisher
    /// reproduces the shape of a real deploy — a burst of output, then a
    /// prompt it never answers — and the sidebar must still be there.
    func testInterfaceSurvivesPublishing() throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()

        // A built site so publishing does not trigger a rebuild first.
        let publicURL: URL = fixtureURL
            .appendingPathComponent("courses/EXC2O/.merged_output/section1/public")
        try FileManager.default.createDirectory(at: publicURL, withIntermediateDirectories: true)
        try "<html></html>".write(to: publicURL.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        let stubDeploy: String = """
        #!/bin/bash
        echo "Ensuring container is running"
        echo "Deploying from local build"
        for step in $(seq 1 300); do
          echo "  …uploaded $step/300 required files to the site"
        done
        echo "Netlify site created"
        echo "Enter Netlify site name [exc2o-s1-2026-gordon]: "
        sleep 30
        """
        let stubURL: URL = fixtureURL.appendingPathComponent("deploy.sh")
        try stubDeploy.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)

        let application: XCUIApplication = XCUIApplication()
        application.launchEnvironment["UITEST_WORKSPACE"] = fixtureURL.path
        application.launch()

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10))
        sectionRow.click()

        application.buttons["deployButton"].click()

        // Give the burst of output time to land, then check the app is
        // still showing its interface.
        Thread.sleep(forTimeInterval: 8)
        saveScreenshot(named: "09-during-publish", of: application)

        XCTAssertTrue(application.outlines.staticTexts["EXC2O"].exists, "The sidebar should still list the course while publishing")
        XCTAssertTrue(application.staticTexts["taskMilestoneLabel"].exists, "Progress should still be shown while publishing")
    }

    func testCancelRevertsEdits() throws {
        let application: XCUIApplication = try launchApp()

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()

        let readingTimeToggle: XCUIElement = application.descendants(matching: .any).matching(identifier: "readingTimeToggle").firstMatch
        XCTAssertTrue(readingTimeToggle.waitForExistence(timeout: 10))
        let initialValue: String = "\(readingTimeToggle.value ?? "")"

        readingTimeToggle.click()

        let revertButton: XCUIElement = application.buttons["revertButton"]
        XCTAssertTrue(revertButton.isEnabled, "Revert should enable after an edit")
        revertButton.click()

        let restoredValue: String = "\(readingTimeToggle.value ?? "")"
        XCTAssertEqual(initialValue, restoredValue, "Cancel should revert the toggle")
    }
}
