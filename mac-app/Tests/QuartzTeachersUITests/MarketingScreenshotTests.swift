import AppKit
import XCTest

/// Screenshots for plantoir.app.
///
/// These are not tests of behaviour — they exist so the marketing site can be
/// rebuilt from the real app rather than from images somebody remembered to
/// retake. `website/shots/capture.py` runs them twice, once with the Mac in
/// light appearance and once in dark, and exports the attachments into
/// `site/img/`. Each attachment's name is the shot id in
/// `website/shots.json`; renaming one here without renaming it there leaves a
/// placeholder on a published page.
///
/// They need a demo working folder with the ENG2D, MCV4U and SCH3U courses in
/// it, supplied as `MARKETING_WORKSPACE`. `DemoWorkspaceProvisioning` below
/// builds one.
class MarketingScreenshotCase: XCTestCase {

    // MARK: - Stored properties

    /// A window big enough to read in a screenshot and small enough to sit on
    /// a page. Points; the capture is taken at the display's own resolution.
    static let windowWidth: CGFloat = 1280
    static let windowHeight: CGFloat = 800

    /// The autosave name AppKit gives the app's main window. Passing a frame
    /// under this key as a launch argument puts it in the argument domain,
    /// which outranks the saved value — so every capture is the same size
    /// regardless of where the window was left last time.
    static let mainWindowFrameKey: String =
        "NSWindow Frame SwiftUI.ModifiedContent<QuartzTeachers.WindowRootView, SwiftUI._FlexFrameLayout>-1-AppWindow-1"

    /// The assistant keeps its own window frame under its own key and applies
    /// it by hand — SwiftUI owns the autosave name and overwrites anything put
    /// there, which is why `AssistWindowPlacement` stopped using one. So this
    /// is that key, and the value is an NSRect string rather than AppKit's
    /// frame format.
    static let assistantFrameKey: String = "AssistantWindowFrame-ENG2D-1"
    static let assistantWidth: CGFloat = 560
    static let assistantHeight: CGFloat = 760

    // MARK: - Functions

    /// The demo working folder, or a skipped test explaining what is missing.
    func demoWorkspacePath() throws -> String {
        let environment: [String: String] = ProcessInfo.processInfo.environment
        guard let path = environment["MARKETING_WORKSPACE"] else {
            throw XCTSkip("Set MARKETING_WORKSPACE to a working folder holding the demo courses. `python3 website/shots/capture.py` does this for you.")
        }
        return path
    }

    /// The frame string AppKit stores for a window: the window's own frame
    /// followed by the frame of the screen it was on.
    static func frameArgument(width: CGFloat, height: CGFloat) -> String {
        let screen: CGRect = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let x: CGFloat = 40
        let y: CGFloat = 60
        return "\(Int(x)) \(Int(y)) \(Int(width)) \(Int(height)) "
            + "\(Int(screen.minX)) \(Int(screen.minY)) \(Int(screen.width)) \(Int(screen.height)) "
    }

    /// An NSRect written the way NSStringFromRect writes it.
    static func rectArgument(width: CGFloat, height: CGFloat) -> String {
        let screen: CGRect = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let x: CGFloat = (screen.width - width) / 2
        let y: CGFloat = (screen.height - height) / 2
        return "{{\(Int(x)), \(Int(y))}, {\(Int(width)), \(Int(height))}}"
    }

    func launchApp(workspacePath: String) -> XCUIApplication {
        let application: XCUIApplication = XCUIApplication()
        application.launchEnvironment["UITEST_WORKSPACE"] = workspacePath
        application.launchArguments = [
            // Never restore windows from the previous session. A capture that
            // dies mid-test leaves the app killed with two windows open, and
            // every launch after that restores BOTH — at which point every
            // element query in every test finds two of everything and fails
            // with "Multiple matching elements found".
            "-ApplePersistenceIgnoreState", "YES",
            "-" + MarketingScreenshotCase.mainWindowFrameKey,
            MarketingScreenshotCase.frameArgument(
                width: MarketingScreenshotCase.windowWidth,
                height: MarketingScreenshotCase.windowHeight
            ),
            "-" + MarketingScreenshotCase.assistantFrameKey,
            MarketingScreenshotCase.rectArgument(
                width: MarketingScreenshotCase.assistantWidth,
                height: MarketingScreenshotCase.assistantHeight
            ),
        ]
        application.launch()
        return application
    }

    /// Saves one window as an attachment named for its entry in shots.json.
    ///
    /// The pointer is parked somewhere harmless first. Left where a click put
    /// it, it hovers a toolbar button long enough for the tooltip to appear —
    /// and a screenshot with "Stop previewing this section" floating over the
    /// toolbar looks like a mistake nobody noticed.
    /// Pass ``alreadyParked`` when the pointer was parked ahead of time —
    /// a capture racing a short-lived label cannot afford the 1.2 s park
    /// here, which once outlived the very step being photographed.
    func save(_ window: XCUIElement, as name: String, alreadyParked: Bool = false) {
        if !alreadyParked {
            parkPointer(in: window)
        }

        // ONE way of taking a picture, and this is it: `screencapture -o -l`,
        // the programmatic form of Command-Shift-4, Space, Option-click. It
        // asks CoreGraphics for the WINDOW, so what comes back has the real
        // rounded corners already transparent and antialiased, whatever is in
        // front of it and whatever is behind it.
        //
        // **There is deliberately no fallback.** There used to be: any
        // stumble here — no window number, the process throwing, the PNG not
        // decoding — fell through to `window.screenshot()`, XCUITest's own
        // capture. That is a RECTANGLE: it bakes the corner curves against
        // whatever was behind them, which arrives as opaque black specks,
        // invisible on a dark page and obvious on a light one. It happened
        // silently, so a run could file a mix of good and bad shots with
        // nothing to say which was which, and `mask_window_corners` grew in
        // the Python to paper over the difference.
        //
        // A marketing screenshot is not worth having if it is the wrong
        // picture, so a failure here stops the run and says why. The remedy
        // is always the same: the window was not where the test thought it
        // was, so fix the frame rather than accept a lesser capture.
        guard let windowNumber: Int = windowNumber(matching: window.frame, forOwner: "Plantoir") else {
            XCTFail(
                "No Plantoir window matches \(window.frame) for the \"\(name)\" shot, so it cannot be "
                + "photographed the only way this harness photographs. Nothing was saved."
            )
            return
        }

        let temporaryURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plantoir-shot-\(UUID().uuidString).png")
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", "\(windowNumber)", temporaryURL.path]
        // Its own words, kept: "status 1" alone sent one investigation looking
        // at window numbers when the answer was a permission.
        let complaints: Pipe = Pipe()
        process.standardError = complaints
        do {
            try process.run()
        } catch {
            XCTFail("Could not run screencapture for the \"\(name)\" shot: \(error.localizedDescription)")
            return
        }
        let said: String = String(
            data: complaints.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            XCTFail(
                "screencapture failed (status \(process.terminationStatus)) for the \"\(name)\" shot"
                + " — window \(windowNumber), it said: \(said.isEmpty ? "nothing" : said)"
            )
            return
        }
        guard let data: Data = try? Data(contentsOf: temporaryURL),
              let image: NSImage = NSImage(data: data) else {
            XCTFail("screencapture wrote nothing readable for the \"\(name)\" shot.")
            return
        }
        try? FileManager.default.removeItem(at: temporaryURL)

        let attachment: XCTAttachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Parks the pointer over the empty part of the sidebar, below the last
    /// course: the only large area of the window with nothing under it to
    /// explain itself. The bottom edge was tried first and hovers the
    /// working-folder path, which has a tooltip of its own.
    func parkPointer(in window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.75)).hover()
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// Looks up the layer-0 window for a given application name whose bounds
    /// match the window being photographed.
    ///
    /// Matched on FRAME, not taken as "the largest": the owner name covers
    /// every process called Plantoir, and one capture photographed a stray
    /// Settings window instead of the panel the test had just filled in.
    /// The XCUIElement's frame and CGWindowList bounds share the same
    /// top-left-origin screen coordinates, so the right window is the one
    /// whose edges line up.
    func windowNumber(matching frame: CGRect, forOwner owner: String) -> Int? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        var bestNumber: Int?
        var bestMismatch: Double = .infinity
        for window in windows {
            guard let name = window[kCGWindowOwnerName as String] as? String, name == owner else {
                continue
            }
            let layer: Int = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let number = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double,
                  let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else {
                continue
            }
            let mismatch: Double = abs(x - frame.minX) + abs(y - frame.minY)
                + abs(width - frame.width) + abs(height - frame.height)
            if mismatch < bestMismatch {
                bestMismatch = mismatch
                bestNumber = number
            }
        }
        // A window that is nowhere near the one asked for is somebody else's;
        // better the XCUITest fallback below than a picture of the wrong thing.
        guard bestMismatch < 40 else {
            return nil
        }
        return bestNumber
    }

    /// Opens a course's section in the sidebar and returns the main window.
    @discardableResult
    func openSection(_ sectionNumber: Int, ofCourse code: String, in application: XCUIApplication) -> XCUIElement {
        let courseRow: XCUIElement = application.outlines.staticTexts[code]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 30), "\(code) should be in the sidebar")
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])

        let sectionRow: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "sidebar-\(code)-section\(sectionNumber)")
            .firstMatch
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 20), "Section \(sectionNumber) of \(code) should be in the sidebar")
        sectionRow.click()
        return application.windows.firstMatch
    }

    /// Opens a course's settings and returns the main window.
    ///
    /// Selecting a SECTION shows the preview area, which is empty until a
    /// preview runs — four fifths of the window saying "No Preview Running",
    /// which is a poor picture of a product. Selecting the COURSE shows the
    /// settings form, which is full of the thing being described.
    @discardableResult
    func openCourse(_ code: String, in application: XCUIApplication) -> XCUIElement {
        let courseRow: XCUIElement = application.outlines.staticTexts[code]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 30), "\(code) should be in the sidebar")
        courseRow.click()
        XCTAssertTrue(
            application.textFields["courseNameField"].waitForExistence(timeout: 20),
            "The settings form for \(code) should appear"
        )
        return application.windows.firstMatch
    }

    /// Scrolls the settings form until a named control is on screen.
    ///
    /// The scroll is dispatched at the WINDOW, not at a scroll view found by
    /// query: asking for `application.scrollViews.firstMatch` returned
    /// something that swallowed every scroll silently, and the capture came
    /// back showing the top of the form as though nothing had been asked for.
    @discardableResult
    func scrollSettings(in application: XCUIApplication, to identifier: String) -> Bool {
        let window: XCUIElement = application.windows.firstMatch
        let target: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: identifier).firstMatch
        for _ in 0..<25 {
            if target.exists && target.isHittable && window.frame.contains(target.frame) {
                return true
            }
            // swipeUp rather than scroll(byDeltaX:deltaY:): the delta form
            // is accepted and does nothing on these SwiftUI scroll views, so
            // the capture came back showing the top of the form as though
            // nothing had been asked for.
            window.swipeUp()
            Thread.sleep(forTimeInterval: 0.35)
        }
        return target.exists && target.isHittable
    }

    /// True when the Mac is set to dark appearance.
    ///
    /// Read from the global domain rather than from this process's own
    /// appearance: the test runner is a different application from the one
    /// being photographed, and only the setting is shared. The key is absent
    /// entirely when the Mac is light.
    func systemIsDark() -> Bool {
        let style: String = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
        return style.lowercased().contains("dark")
    }

    /// Make the class site inside the preview match the app around it.
    ///
    /// The site chooses its own colours, and the embedded web view does not
    /// report a light preference — so a light app came back holding a dark
    /// website, which reads as a rendering fault rather than as a choice.
    ///
    /// The site's own toggle offers exactly one of two controls, and WHICH one
    /// says what theme it is in: a light site offers "Dark mode", a dark site
    /// offers "Light mode". So the label names the destination, and asking for
    /// the destination we want is both the test and the fix.
    func matchSiteToSystemAppearance(in application: XCUIApplication) {
        let wantDark: Bool = systemIsDark()
        let destination: String = wantDark ? "Dark mode" : "Light mode"

        // Matched on TITLE as well as label. Inside a web view the control is
        // a Button carrying its accessible name in `title` — matching only on
        // `label`, as this did at first, found nothing and silently skipped
        // the toggle, so a light app kept coming back holding a dark site.
        let named: NSPredicate = NSPredicate(
            format: "title == %@ OR label == %@ OR value == %@",
            destination, destination, destination
        )
        let toggle: XCUIElement = application.descendants(matching: .any)
            .matching(named).firstMatch

        // Present only when the site is in the OTHER mode. Absent means the
        // site already matches, and there is nothing to do.
        if toggle.waitForExistence(timeout: 10) && toggle.isHittable {
            toggle.click()
            settle(2.5)
        }
    }

    /// A pause long enough for a view to settle before it is photographed.
    /// Screenshots are the one place where "it exists" is not the same as
    /// "it has finished drawing".
    func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

/// The captures themselves. Named in order because XCTest runs a class's
/// tests alphabetically, and the slow ones (which need a container) belong
/// last so a failure there still leaves the quick ones captured.
final class MarketingScreenshots: MarketingScreenshotCase {

    // MARK: - Functions

    /// The whole product in one picture: three courses in the sidebar, and
    /// one of them open beside them.
    func test1Courses() throws {
        let application: XCUIApplication = launchApp(workspacePath: try demoWorkspacePath())
        let window: XCUIElement = openCourse("ENG2D", in: application)
        settle(2.0)
        save(window, as: "courses")
    }

    /// Adding a course: the panel filled in for a code that has ready-made
    /// material, before anything is created.
    func test2NewCourse() throws {
        let application: XCUIApplication = launchApp(workspacePath: try demoWorkspacePath())
        let window: XCUIElement = application.windows.firstMatch
        XCTAssertTrue(application.outlines.staticTexts["ENG2D"].waitForExistence(timeout: 30))

        application.buttons["addCourseButton"].click()
        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 15), "The new course panel should open")
        codeField.click()
        codeField.typeText("SBI3U")

        // The name fills itself in from the code; give it a moment to land.
        settle(2.0)

        let sectionNumbers: XCUIElement = application.textFields["wizardSectionNumbersField"]
        if sectionNumbers.exists {
            sectionNumbers.click()
            sectionNumbers.typeKey("a", modifierFlags: .command)
            sectionNumbers.typeText("1, 2")
        }
        settle(1.5)
        save(window, as: "new-course")

        application.buttons["wizardCloseButton"].click()
    }

    /// Plantoir in the middle of deploying, showing the deployment progress.
    func test3Deploying() throws {
        let workspacePath: String = try demoWorkspacePath()
        let application: XCUIApplication = launchApp(workspacePath: workspacePath)
        let window: XCUIElement = openSection(1, ofCourse: "ENG2D", in: application)

        let deployButton: XCUIElement = application.buttons["deployButton"]
        XCTAssertTrue(deployButton.waitForExistence(timeout: 20), "Deploy button should exist")

        // Parked before the click, and saved the moment a step is described,
        // with no settle: a warm delta deploy of unchanged content finishes
        // in a few seconds, and a two-second settle here once outlived the
        // whole thing — the capture showed "Done" instead of a deploy under
        // way.
        parkPointer(in: window)
        deployButton.click()

        let milestone: XCUIElement = application.staticTexts["taskMilestoneLabel"]
        XCTAssertTrue(milestone.waitForExistence(timeout: 60), "Progress should be described while the site deploys")

        // Prefer a step past the first: on a set-up Mac the opening
        // milestone reads "Getting this Mac ready…", which is a confusing
        // sentence to put under a "Deploying" title on the front page. But
        // wait no more than a few seconds — a warm delta deploy can finish
        // in four, and waiting it out captures "Done" instead of a deploy.
        // The sentence is the element's VALUE; its label is empty.
        let betterStepBy: Date = Date().addingTimeInterval(4)
        while Date() < betterStepBy {
            if !milestone.exists {
                break
            }
            let described: String = (milestone.value as? String) ?? ""
            if !described.isEmpty && !described.contains("Getting this Mac ready") {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        save(window, as: "hero-plantoir", alreadyParked: true)

        let cancelButton: XCUIElement = application.buttons["taskCancelButton"]
        if cancelButton.exists {
            cancelButton.click()
        }
    }

    /// Progress, described in words while a site is built.
    ///
    /// Section 2 on purpose: section 1 has been built and published already,
    /// so its preview comes back almost at once — the first attempt at this
    /// photographed the finished site twice and called one of them progress.
    func test4Progress() throws {
        let application: XCUIApplication = launchApp(workspacePath: try demoWorkspacePath())
        let window: XCUIElement = openSection(2, ofCourse: "ENG2D", in: application)

        let previewButton: XCUIElement = application.buttons["previewButton"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 20))
        previewButton.click()

        let milestone: XCUIElement = application.staticTexts["taskMilestoneLabel"]
        XCTAssertTrue(milestone.waitForExistence(timeout: 60), "Progress should be described while the site builds")

        // Photograph a NAMED step rather than sleeping a fixed six seconds.
        // On a warm machine the whole build finished inside that sleep, and
        // the capture showed the finished site: the same picture as
        // `preview`, filed as progress.
        //
        // The step waited for is "Opening the preview…", and the choice is
        // not free: it is the only state a capture can dependably reach.
        // Instrumented polling at 20 Hz showed every earlier step already
        // gone by the first sample — the launcher's early lines arrive in
        // one buffered chunk, and the pre-build "Launching Quartz preview"
        // line (the final step's marker) completes every milestone at once,
        // after which this sentence sits on screen for the whole build,
        // minutes at a time. That a preview spends those minutes on a full
        // bar captioned with its LAST step is a real milestone defect,
        // recorded in TODO.md, not a capture problem; when it is fixed,
        // this wait should move to the step that replaces it, and the shot
        // should be re-taken.
        //
        // A hand-rolled poll, not XCTNSPredicateExpectation: the
        // expectation form is not dependable against attributes other than
        // existence. Reading `label` directly takes a fresh snapshot every
        // pass, and each read costs an accessibility snapshot anyway, so
        // the loop polls about as fast as XCUITest can.
        // Parked NOW, not inside save(): the park costs 1.2 s, and the step
        // being photographed can be over in less.
        parkPointer(in: window)

        let namedStepBy: Date = Date().addingTimeInterval(300)
        var namedStepSeen: Bool = false
        // Every distinct sentence the label showed, kept so a failure names
        // what WAS on screen instead of inviting another guess.
        var observedLabels: Set<String> = []
        while Date() < namedStepBy {
            if milestone.exists {
                // The sentence lives in the VALUE. Reading only `label`,
                // as the first three attempts did, sees an empty string
                // whatever the view shows — which reads exactly like the
                // step never happening.
                let text: String = milestone.label
                let value: String = (milestone.value as? String) ?? ""
                observedLabels.insert("label=\(text) value=\(value)")
                if text.contains("Opening the preview") || value.contains("Opening the preview") {
                    namedStepSeen = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(namedStepSeen,
                      "A named step should be described while the site builds. "
                      + "Observed: \(observedLabels.sorted())")
        save(window, as: "progress", alreadyParked: true)

        if application.buttons["stopPreviewButton"].exists {
            application.buttons["stopPreviewButton"].click()
        }
    }

    /// The finished site, inside the app, before anyone else has seen it.
    func test5Preview() throws {
        let application: XCUIApplication = launchApp(workspacePath: try demoWorkspacePath())
        let window: XCUIElement = openSection(1, ofCourse: "ENG2D", in: application)

        let previewButton: XCUIElement = application.buttons["previewButton"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 20))
        previewButton.click()

        let webView: XCUIElement = application.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 900), "The built site should appear in the window")
        settle(8.0)
        matchSiteToSystemAppearance(in: application)
        save(window, as: "preview")

        if application.buttons["stopPreviewButton"].exists {
            application.buttons["stopPreviewButton"].click()
        }
    }

    /// The assistant, holding a plan and waiting to be told to go ahead.
    func test6Assistant() throws {
        let application: XCUIApplication = launchApp(workspacePath: try demoWorkspacePath())
        openSection(1, ofCourse: "ENG2D", in: application)

        let sectionRow: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "sidebar-ENG2D-section1")
            .firstMatch
        sectionRow.rightClick()

        let assistantItem: XCUIElement = application.menuItems["Revise with Local AI Assistant…"]
        XCTAssertTrue(assistantItem.waitForExistence(timeout: 15), "The section menu should offer the assistant")
        assistantItem.click()

        // Existing is not ready. The window opens immediately and says it is
        // starting; the box is DISABLED and the shelf of phrasings is not
        // there at all until the assistant has finished loading, which takes
        // a while the first time. Every earlier failure here — "no keyboard
        // focus", "the shelf should offer its groups" — was this one fact
        // wearing a different hat.
        let input: XCUIElement = application.textFields["assistInputField"]
        XCTAssertTrue(input.waitForExistence(timeout: 120), "The assistant window should open")

        let readyBy: Date = Date().addingTimeInterval(600)
        while Date() < readyBy && !input.isEnabled {
            Thread.sleep(forTimeInterval: 2.0)
        }
        XCTAssertTrue(input.isEnabled, "The assistant should finish starting before it is asked for anything")
        settle(1.5)

        let assistantWindow: XCUIElement = assistantWindowIn(application)

        // Typed, now that waiting for the box to be ENABLED has made that
        // dependable. The first attempts failed with "neither element nor any
        // descendant has keyboard focus" — not because focus is hard, but
        // because the box was still disabled while the assistant loaded, and
        // a disabled field cannot take focus.
        //
        // The shelf of ready-made phrasings was tried as a way round it and
        // rejected: its groups are DisclosureTriangles that do not expand
        // from a synthesized click, so the suggestion inside one is never
        // reachable. Typing needs no disclosure to open.
        //
        // Pasted rather than typed. `typeText` synthesizes one event per
        // character, and each waits for the app to go quiescent first; twice
        // now the wait timed out mid-sentence ("Failed to synthesize event")
        // with the model resident and the window busy settling. A paste is a
        // single chord, so there is one quiescence wait instead of
        // twenty-three. The pasteboard is system-wide, so the runner can set
        // it for the app — and the teacher's own clipboard is put back after.
        let pasteboard: NSPasteboard = NSPasteboard.general
        let previousClipboard: String? = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString("Unpublish Unit 2, Day 3", forType: .string)

        input.click()
        settle(1.0)
        application.typeKey("v", modifierFlags: .command)
        settle(0.8)

        pasteboard.clearContents()
        if let previousClipboard {
            pasteboard.setString(previousClipboard, forType: .string)
        }

        let send: XCUIElement = application.buttons["assistSendButton"]
        XCTAssertTrue(send.isEnabled, "Send should light up once there is something to send")
        send.click()

        // The reply is a plan with a button to approve it; that is the moment
        // worth photographing, because it is the promise the product makes.
        let approve: XCUIElement = application.buttons["assistApproveButton"]
        XCTAssertTrue(approve.waitForExistence(timeout: 300), "The assistant should answer with something to approve")
        settle(2.0)

        save(assistantWindow, as: "assistant")

        if application.buttons["assistDeclineButton"].exists {
            application.buttons["assistDeclineButton"].click()
        }
    }

    /// The assistant lives in its own window; find it by the field only it has.
    func assistantWindowIn(_ application: XCUIApplication) -> XCUIElement {
        let windows: XCUIElementQuery = application.windows
        for index in 0..<windows.count {
            let candidate: XCUIElement = windows.element(boundBy: index)
            if candidate.textFields["assistInputField"].exists {
                return candidate
            }
        }
        return windows.firstMatch
    }
}

/// Builds the demo working folder by driving the app's own new-course panel.
///
/// Not part of the capture run: it takes minutes, needs a container, and the
/// folder it produces is reused by every capture afterwards. Kept separate so
/// a re-shoot costs nothing.
final class DemoWorkspaceProvisioning: MarketingScreenshotCase {

    // MARK: - Functions

    func testCreateDemoCourses() throws {
        let workspacePath: String = try demoWorkspacePath()
        let application: XCUIApplication = launchApp(workspacePath: workspacePath)

        // A brand-new folder needs the launchers put into it first.
        let initialize: XCUIElement = application.buttons["initializeFolderButton"]
        if initialize.waitForExistence(timeout: 10) {
            initialize.click()
        }

        let wanted: [(code: String, sections: String)] = [
            ("ENG2D", "1, 2"),
            ("MCV4U", "1"),
            ("SCH3U", "1"),
        ]

        for course in wanted {
            if application.outlines.staticTexts[course.code].waitForExistence(timeout: 5) {
                continue
            }
            try createCourse(code: course.code, sections: course.sections, in: application)
        }

        for course in wanted {
            XCTAssertTrue(
                application.outlines.staticTexts[course.code].waitForExistence(timeout: 60),
                "\(course.code) should have been created"
            )
        }
    }

    func createCourse(code: String, sections: String, in application: XCUIApplication) throws {
        let addButton: XCUIElement = application.buttons["addCourseButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 60), "The sidebar should offer to add a course")
        addButton.click()

        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 20))
        codeField.click()
        codeField.typeText(code)
        Thread.sleep(forTimeInterval: 2.0)

        let sectionNumbers: XCUIElement = application.textFields["wizardSectionNumbersField"]
        if sectionNumbers.exists {
            sectionNumbers.click()
            sectionNumbers.typeKey("a", modifierFlags: .command)
            sectionNumbers.typeText(sections)
        }

        application.buttons["createCourseButton"].click()

        // Creating a course runs the real setup script, which builds the site
        // builder on a cold machine. Minutes, not seconds — so this waits a
        // long time, but watches for the failure panel as well as for success.
        // Waiting only for success turned a folder misconfigured in one second
        // into a test that sat there for half an hour saying nothing.
        let closeButton: XCUIElement = application.buttons["wizardCloseActionButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 60), "The panel should show a Close button while it works")

        let failure: XCUIElement = application.staticTexts["failureExplanation"]
        let deadline: Date = Date().addingTimeInterval(1800)
        var finished: Bool = false
        while Date() < deadline {
            if failure.exists {
                XCTFail("Creating \(code) failed: \(failure.label)")
                return
            }
            // Close is present throughout and enabled only when work ends.
            if closeButton.isEnabled {
                finished = true
                break
            }
            Thread.sleep(forTimeInterval: 3.0)
        }
        XCTAssertTrue(finished, "Creating \(code) did not finish")

        // The sidebar is reloaded BY the Close button, not by the script
        // finishing — so the course cannot appear until the panel is shut.
        // Waiting for the row first is a wait that never ends.
        closeButton.click()

        let created: XCUIElement = application.outlines.staticTexts[code]
        XCTAssertTrue(created.waitForExistence(timeout: 180), "\(code) should appear in the sidebar once the panel closes")
        Thread.sleep(forTimeInterval: 2.0)
    }
}
