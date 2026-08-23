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

    /// The trailing chevron — the visual cue that this field is really a
    /// combo box, per the HIG — opens the popup and browses the whole
    /// catalog without the teacher needing to type anything first.
    func testCourseCodeRevealButtonOpensThePopup() throws {
        let application: XCUIApplication = try launchApp()

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 10))
        newCourseButton.click()

        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "The wizard sheet should appear")

        let revealButton: XCUIElement = application.buttons["courseCodeRevealButton"]
        XCTAssertTrue(revealButton.waitForExistence(timeout: 5))
        revealButton.click()

        let suggestionsList: XCUIElement = application.scrollViews["courseCodeSuggestionsList"]
        XCTAssertTrue(suggestionsList.waitForExistence(timeout: 5), "Clicking the chevron should open the popup without typing anything")

        // Browsing (an empty query) lists the whole province catalog
        // alphabetically — ADA1O leads the Ontario list.
        let firstRow: XCUIElement = application.buttons["courseCodeSuggestion-ADA1O"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "The full catalog should be browsable from the chevron")

        // The reveal button must actually sit INSIDE the field's visual
        // background — Russell caught the first attempt rendering it
        // detached, with no fill to show it was even a button. Checked
        // by geometry rather than a screenshot: this machine's screen
        // capture has been unreliable mid-session (grabbing an unrelated
        // window), so frame containment is the trustworthy check here.
        // Against the BACKGROUND container's frame, not the plain
        // `TextField`'s own — that reports its own smaller natural text
        // height (~18pt), not the field's full visual bounds (24pt), so
        // checking against it would fail even when the button is
        // correctly inset inside the actual field.
        // Queried type-agnostically — `.contain` keeps this container
        // from being merged into the `TextField`'s own accessibility
        // element, but which `XCUIElementType` it then reports as is not
        // something to guess (it did not turn out to be `.other`).
        let fieldBackground: XCUIElement = application.descendants(matching: .any).matching(identifier: "wizardCourseCodeFieldBackground").firstMatch
        XCTAssertTrue(fieldBackground.waitForExistence(timeout: 5))
        let fieldFrame: CGRect = fieldBackground.frame
        let buttonFrame: CGRect = revealButton.frame
        XCTAssertTrue(fieldFrame.contains(buttonFrame), "The reveal button should be fully contained within the field's own visual bounds — field: \(fieldFrame), button: \(buttonFrame)")
        XCTAssertGreaterThan(buttonFrame.midX, fieldFrame.midX, "The reveal button should sit on the trailing half of the field")
        XCTAssertLessThan(buttonFrame.height, fieldFrame.height, "The reveal button should leave a visible margin top and bottom, not fill the whole field")
        // An upper bound too, not just containment — a regression that
        // grew the field far beyond the wizard sheet itself would still
        // "contain" the button and still put it on the "trailing half",
        // so containment alone can't catch that. The field legitimately
        // spans the Form row's full width here (measured ~620pt), the
        // same as every sibling field (Course Name, etc.) in this same
        // `Form` — an EARLIER version of this bound (400pt, assuming a
        // compact code-sized box) was wrong about that and failed on
        // correct, unchanged behaviour; this one only catches the field
        // growing past what the 680pt wizard sheet itself could hold.
        XCTAssertLessThan(fieldFrame.width, 700, "The field shouldn't grow past what the wizard sheet itself could hold — frame: \(fieldFrame)")
        XCTAssertLessThan(fieldFrame.height, 40, "The field itself should stay a single compact row — frame: \(fieldFrame)")

        let closeButton3: XCUIElement = application.buttons["wizardCloseButton"]
        closeButton3.click()
    }

    /// The reveal button's actual reason for existing: reopening the
    /// popup when the field is ALREADY focused but Escape just closed
    /// the list — a plain focus change wouldn't trigger that popup again
    /// on its own, since nothing about focus is changing.
    func testCourseCodeRevealButtonReopensAfterEscape() throws {
        let application: XCUIApplication = try launchApp()

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 10))
        newCourseButton.click()

        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "The wizard sheet should appear")
        codeField.click()

        let suggestionsList: XCUIElement = application.scrollViews["courseCodeSuggestionsList"]
        XCTAssertTrue(suggestionsList.waitForExistence(timeout: 5), "Clicking into the field should open the popup")

        codeField.typeKey(.escape, modifierFlags: [])
        let closedExpectation: XCTNSPredicateExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: suggestionsList
        )
        XCTAssertEqual(XCTWaiter().wait(for: [closedExpectation], timeout: 5), .completed, "Escape should close the popup")

        // The field still has focus — Escape doesn't blur it — so a
        // plain focus change wouldn't reopen anything on its own; this
        // is what `onRevealRequested` exists for.
        let revealButton: XCUIElement = application.buttons["courseCodeRevealButton"]
        XCTAssertTrue(revealButton.waitForExistence(timeout: 5))
        revealButton.click()

        XCTAssertTrue(suggestionsList.waitForExistence(timeout: 5), "The reveal button should reopen the popup even though the field never lost focus")

        let closeButton4: XCUIElement = application.buttons["wizardCloseButton"]
        closeButton4.click()
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
