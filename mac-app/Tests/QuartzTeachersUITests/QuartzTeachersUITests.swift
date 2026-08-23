import XCTest

/// Drives the real app against a fixture working folder (a copy of the
/// repository checkout with the EXC2O example course) supplied via the
/// UITEST_WORKSPACE environment variable.
final class QuartzTeachersUITests: XCTestCase {

    // NOTE — do NOT add `Process`-based cleanup here. An earlier
    // attempt put `pkill -f "http.server 8081"` in `setUp`/`tearDown`
    // to reap the stub preview server that
    // `testRestartingAPreviewReturnsToTheProgressView` leaks (that
    // test hands the app a fake `preview.sh` ending in `exec python3
    // -m http.server 8081`, and the server is a child of the APP, so
    // it outlives an interrupted run and holds the port — a leftover
    // from one day's run was still holding 8081 the next morning and
    // made a real preview fail with `OSError: [Errno 48] Address
    // already in use`, which reads like a broken toolchain rather than
    // like test litter).
    //
    // It looked right and did nothing: the UI-test runner is
    // sandboxed and cannot spawn a child process at all. Verified
    // 2026-08-23 by having the helper write a marker file after
    // `process.waitUntilExit()` — the marker was never written, and
    // the `try?` had been swallowing the failure silently. Anything
    // that needs to kill that server has to do it WITHOUT spawning a
    // process (`Darwin.kill()` on a pid the stub script records would
    // work), or from outside the test run.

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

    /// Takes an `XCUIScreenshotProviding` rather than the application so
    /// a caller can attach ONE WINDOW. `XCUIApplication.screenshot()` on
    /// macOS captures the entire display, which put another app's window
    /// over the thing under test more than once (2026-08-23).
    func saveScreenshot(named name: String, of provider: XCUIScreenshotProviding) {
        let screenshot: XCUIScreenshot = provider.screenshot()
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
        // bounds — Russell caught the first attempt rendering it
        // detached, with no fill to show it was even a button. Checked
        // by geometry rather than a screenshot: this machine's screen
        // capture has been unreliable mid-session (grabbing an unrelated
        // window), so frame containment is the trustworthy check here.
        // Against the background SHAPE's own frame, not `codeField`'s —
        // an `NSTextField`'s reported AX frame reflects the underlying
        // control's own intrinsic content bounds (~18pt tall) regardless
        // of a later `.frame(height:)` giving it more room to sit inside
        // (confirmed identical across two different modifier orderings,
        // 2026-08-23), so it under-reports this field's real 30pt visual
        // height. The `RoundedRectangle` used as the field's
        // `.background` doesn't have that limitation — its own
        // accessibility frame matches its actual laid-out size.
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


    /// The copy of a `Form` row's label that belongs to the row holding
    /// `field` — the one whose vertical centre is closest to the
    /// field's. Needed because the window behind the wizard sheet can
    /// carry a label with the identical text; see the note in
    /// `testCourseCodeFieldMatchesCourseNameFieldsLeadingEdgeAndLabel`.
    func wizardLabel(named text: String, near field: XCUIElement, in application: XCUIApplication) -> XCUIElement {
        let candidates: [XCUIElement] = application.staticTexts.matching(identifier: text).allElementsBoundByIndex
        var closest: XCUIElement = application.staticTexts[text]
        var smallestDistance: CGFloat = .greatestFiniteMagnitude
        for candidate in candidates {
            let distance: CGFloat = abs(candidate.frame.midY - field.frame.midY)
            if distance < smallestDistance {
                smallestDistance = distance
                closest = candidate
            }
        }
        return closest
    }

    /// Course code's field should look and sit like every other field
    /// in the Basics section: a "Course code" label OUTSIDE the field,
    /// in the same leading column as "Course name", with its own field
    /// starting at the same leading edge as Course name's — and typed
    /// text reading from that leading edge rather than pushed against
    /// the trailing one (Russell, 2026-08-23, comparing a screenshot of
    /// the two rows).
    func testCourseCodeFieldMatchesCourseNameFieldsLeadingEdgeAndLabel() throws {
        let application: XCUIApplication = try launchApp()

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 10))
        newCourseButton.click()

        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "The wizard sheet should appear")

        // "Course code" is a real label OUTSIDE the field, in the same
        // leading column as "Course name" — not placeholder text inside
        // it, which is what a `Form` row gives a view of ours that
        // isn't a bare `TextField` (Russell, 2026-08-23, comparing the
        // two rows). `NewCourseWizardView` writes it as an explicit
        // `LabeledContent`; if this stops finding a match, that wrapper
        // was removed or renamed.
        // Both labels are found by their VISIBLE TEXT, then narrowed
        // to the wizard's own copies. Two things forced that shape.
        // First, the course settings pane BEHIND this sheet has a
        // "Course name" label of its own, so an unscoped query matched
        // two elements and the frame comparison below died with
        // "Multiple matching elements found" — but only when an earlier
        // test in the same run had left a course selected, which is why
        // it passed in isolation (2026-08-23). Second, the two obvious
        // fixes both failed: `application.sheets` finds nothing (this
        // sheet isn't reported as one), and giving the labels their own
        // `.accessibilityIdentifier` in `NewCourseWizardView` made the
        // whole `LabeledContent` row merge into a single element, so
        // `wizardCourseCodeField` stopped existing as a `TextField` at
        // all and every later click failed. So: pick the copy that
        // belongs to this sheet by its geometry instead.
        let label: XCUIElement = wizardLabel(named: "Course code", near: codeField, in: application)
        XCTAssertTrue(label.exists, "\"Course code\" should be a label beside the field, the same way \"Course name\" is")
        let nameLabel: XCUIElement = wizardLabel(named: "Course name", near: application.textFields["wizardCourseNameField"], in: application)
        XCTAssertTrue(nameLabel.exists)
        XCTAssertEqual(label.frame.minX, nameLabel.frame.minX, accuracy: 2.0, "The two labels should share a leading edge — code: \(label.frame.minX), name: \(nameLabel.frame.minX)")

        let codeFieldBackground: XCUIElement = application.descendants(matching: .any).matching(identifier: "wizardCourseCodeFieldBackground").firstMatch
        XCTAssertTrue(codeFieldBackground.waitForExistence(timeout: 5))
        let nameField: XCUIElement = application.textFields["wizardCourseNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        // The label sits to the LEFT of both fields now, so a field
        // that still started where the label does would mean the
        // two-column row never formed.
        XCTAssertGreaterThan(nameField.frame.minX, nameLabel.frame.maxX, "Course name's field should sit in the row's trailing column, past its label")

        // Not `codeFieldBackground.frame` — that identifier is bound to
        // a `Shape` used only as decoration, and SwiftUI's
        // accessibility tree hoists a decorative element's identifier
        // onto the nearest "real" ancestor container it merges into,
        // which turns out to be the whole Form ROW (both columns
        // together): confirmed directly, it reported x=1951, width=620
        // — the same leading edge as the row's own label and far wider
        // than the field itself (2026-08-23). The `TextField` elements
        // themselves are the reliable comparison.
        let codeLeadingX: CGFloat = codeField.frame.minX
        let nameLeadingX: CGFloat = nameField.frame.minX
        // 8pt, not a tight match: an `NSTextField`'s AX frame is its
        // TEXT area, and `.roundedBorder` keeps its own inset inside
        // that frame while this field's `.plain` style draws none — so
        // the course-code field spends `textLeadingInset` (4pt,
        // AppKit's own `titleRect` answer) to put its text where Course
        // name's already is, and that shows up here as a difference in
        // reported origin even when the two BOXES line up exactly
        // (measured 2234.0 vs 2229.0, 2026-08-23, with the boxes
        // visually flush in a screenshot).
        XCTAssertEqual(codeLeadingX, nameLeadingX, accuracy: 8.0, "Course code's field should start at the same leading edge as Course name's — code: \(codeLeadingX), name: \(nameLeadingX)")

        // Typed text reads LEADING in all three fields. `Form`'s own
        // label extraction would have made each field's contents the
        // row's trailing-aligned VALUE — Russell saw Timetable section
        // numbers' "1" against the field's right edge (2026-08-23) —
        // and `.multilineTextAlignment(.leading)` alone did not
        // override that; the explicit `LabeledContent` wrappers are
        // what fixed it. Compared by where each field's own text
        // element STARTS relative to its field: near the leading edge,
        // nowhere near the trailing one.
        codeField.click()
        codeField.typeText("SCH3U")
        nameField.click()
        nameField.typeText("Chemistry")

        for (fieldName, field) in [("course code", codeField), ("course name", nameField)] {
            let text: XCUIElement = field.staticTexts.firstMatch
            if text.exists {
                let offsetFromLeading: CGFloat = text.frame.minX - field.frame.minX
                XCTAssertLessThan(offsetFromLeading, 20.0, "The \(fieldName) field's text should start at its leading edge, not float to the right of it — offset: \(offsetFromLeading)")
            }
        }

        saveScreenshot(named: "06-course-code-vs-name-alignment", of: application.windows.firstMatch)

        let closeButton5: XCUIElement = application.buttons["wizardCloseButton"]
        closeButton5.click()
    }

    /// The chevron TOGGLES, the way a real `NSComboBox`'s arrow does:
    /// a second press puts the popup away rather than doing nothing
    /// (Russell, 2026-08-23).
    func testCourseCodeRevealButtonAlsoClosesThePopup() throws {
        let application: XCUIApplication = try launchApp()

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 10))
        newCourseButton.click()

        let revealButton: XCUIElement = application.buttons["courseCodeRevealButton"]
        XCTAssertTrue(revealButton.waitForExistence(timeout: 10))

        revealButton.click()
        let suggestions: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "courseCodeSuggestionsList").firstMatch
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5), "The first press should open the popup")

        revealButton.click()
        // `waitForNonExistence` rather than a bare `exists`: the popup
        // fades out over 0.12s, so an immediate read can still see it.
        XCTAssertTrue(suggestions.waitForNonExistence(timeout: 5), "A second press should close it again")

        revealButton.click()
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5), "A third press should reopen it")

        let closeButton: XCUIElement = application.buttons["wizardCloseButton"]
        closeButton.click()
    }

    /// Down-arrow walks the popup and Return takes the highlighted row,
    /// the way a real `NSComboBox` does (Russell, 2026-08-23).
    func testArrowKeysAndReturnChooseACourseCode() throws {
        let application: XCUIApplication = try launchApp()

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 10))
        newCourseButton.click()

        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10))
        codeField.click()
        codeField.typeText("SCH")

        let sch3uRow: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "courseCodeSuggestion-SCH3U").firstMatch
        XCTAssertTrue(sch3uRow.waitForExistence(timeout: 5), "SCH3U should be among the suggestions for \"SCH\"")

        // What the FIRST row is depends on the catalog's ordering, so
        // read it out of the row's own identifier rather than hard-coding
        // a code — the behaviour under test is "down highlights the
        // first row, Return takes it", not which course happens to sort
        // first for "SCH".
        let rows: [XCUIElement] = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "courseCodeSuggestion-"))
            .allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty, "There should be suggestions to walk")
        let firstRowCode: String = String(rows[0].identifier.dropFirst("courseCodeSuggestion-".count))
        XCTAssertFalse(firstRowCode.isEmpty)

        codeField.typeKey(.downArrow, modifierFlags: [])
        saveScreenshot(named: "07-course-code-keyboard-highlight", of: application.windows.firstMatch)
        codeField.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(
            "\(codeField.value ?? "")".uppercased(),
            firstRowCode.uppercased(),
            "One down-arrow should highlight the first suggestion and Return should take it"
        )

        // And the popup closes on commit, the same as clicking a row.
        let suggestions: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "courseCodeSuggestionsList").firstMatch
        XCTAssertTrue(suggestions.waitForNonExistence(timeout: 5), "Committing with Return should close the popup")

        let closeButton: XCUIElement = application.buttons["wizardCloseButton"]
        closeButton.click()
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
