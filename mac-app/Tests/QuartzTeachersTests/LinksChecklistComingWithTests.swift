import XCTest
@testable import QuartzTeachers

/// #398: a row a TICKED class brings is shown ticked and disabled, "comes
/// with …", until the class is unticked. Run from
/// `contracts/shared-rules.json` → `linksChecklist.comingWithAClass`, never
/// retyped; the publish cases iv-j to iv-n run through the sheet in
/// `LinksChecklistFollowingTests`, beside the runner they share.
@MainActor
final class LinksChecklistComingWithTests: XCTestCase {

    // MARK: - Functions

    static func sheet(for testCase: [String: Any], made: AssistFixture.Made) throws -> LinksChecklistSheetModel {
        return LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])),
            answered: nil, occasion: .afterAPreview
        )
    }

    static func row(_ place: String, in model: LinksChecklistSheetModel) throws -> LinksChecklistOffer.Row {
        var found: LinksChecklistOffer.Row?
        for row in model.rows where row.place == place {
            found = row
        }
        return try XCTUnwrap(found, "\(place) is not offered")
    }

    // MARK: - The pure cases

    func testComingWithAClassAsTheContractSays() throws {
        let rule: [String: Any] = try XCTUnwrap(LinksChecklistTests.contract()["comingWithAClass"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12, "The cases cannot pass by running none")
        for testCase in cases {
            let name: String = testCase["name"] as? String ?? "?"
            let rows: [LinksChecklistOffer.Row] = try LinksChecklistFollowingTests.rows(
                from: try XCTUnwrap(testCase["rows"] as? [[String: Any]])
            )
            let brings: [String: [String]] = try XCTUnwrap(testCase["brings"] as? [String: [String]], name)
            var ticked: Set<String> = []
            for row in rows where row.ticked {
                ticked.insert(row.place)
            }
            for step in testCase["steps"] as? [[String: String]] ?? [] {
                // The checkbox's own rule: a step on a row coming with a
                // ticked class at that moment is ignored.
                let now: [String: String] = LinksChecklistGate.comingWith(
                    rows, going: LinksChecklistGate.going(rows, ticked: ticked), brings: brings
                )
                if let place = step["tick"] {
                    ticked = LinksChecklistGate.toggled(ticked, place: place, isOn: true, comingWith: now)
                }
                if let place = step["untick"] {
                    ticked = LinksChecklistGate.toggled(ticked, place: place, isOn: false, comingWith: now)
                }
            }
            let going: Set<String> = LinksChecklistGate.going(rows, ticked: ticked)
            let comingWith: [String: String] = LinksChecklistGate.comingWith(rows, going: going, brings: brings)
            var locked: [String] = []
            for row in rows where LinksChecklistGate.isLocked(row, going: going, comingWith: comingWith) {
                locked.append(row.place)
            }
            let shown: Set<String> = LinksChecklistGate.shownTicked(going: going, comingWith: comingWith)
            XCTAssertEqual(going.sorted(), LinksChecklistFollowingTests.places(testCase["expectGoing"]), "\(name): going")
            XCTAssertEqual(locked.sorted(), LinksChecklistFollowingTests.places(testCase["expectLocked"]), "\(name): locked")
            XCTAssertEqual(comingWith, try XCTUnwrap(testCase["expectComesWith"] as? [String: String], name),
                           "\(name): comes with")
            XCTAssertEqual(shown.sorted(), LinksChecklistFollowingTests.places(testCase["expectShownTicked"]),
                           "\(name): shown ticked")
        }
    }

    // MARK: - Through the model

    /// The checkbox of a row a ticked class brings changes nothing, in either
    /// direction; untick the class and the row is locked again (pure 3b, and
    /// the model's own binding).
    func testTheCheckboxOfARowAClassBringsDoesNothing() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-j.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        _ = try LinksChecklistTests.layOut(testCase, made: made)
        let model: LinksChecklistSheetModel = try LinksChecklistComingWithTests.sheet(for: testCase, made: made)
        model.ticked = []
        let worksheet: LinksChecklistOffer.Row = try LinksChecklistComingWithTests.row("Concepts/Worksheet", in: model)
        let theClass: LinksChecklistOffer.Row = try LinksChecklistComingWithTests.row(
            "section1/All Classes/Unit 3, Day 1", in: model
        )
        XCTAssertTrue(model.isLocked(worksheet), "Under an unticked hub, and no class ticked: locked")
        XCTAssertFalse(model.binding(for: worksheet).wrappedValue)

        model.binding(for: theClass).wrappedValue = true
        XCTAssertFalse(model.isLocked(worksheet))
        XCTAssertTrue(model.isDisabled(worksheet))
        XCTAssertTrue(model.binding(for: worksheet).wrappedValue, "A row the ticked class brings shows unticked")

        model.binding(for: worksheet).wrappedValue = true
        XCTAssertEqual(model.ticked, ["section1/All Classes/Unit 3, Day 1"], "A tick on a brought row was written")
        model.ticked.insert("Concepts/Worksheet")
        model.binding(for: worksheet).wrappedValue = false
        XCTAssertTrue(model.ticked.contains("Concepts/Worksheet"), "An untick on a brought row was written")
        XCTAssertTrue(model.binding(for: worksheet).wrappedValue)

        model.binding(for: theClass).wrappedValue = false
        XCTAssertTrue(model.isLocked(worksheet), "Untick the class, and the row is under its unticked hub again")
        XCTAssertFalse(model.binding(for: worksheet).wrappedValue)
        XCTAssertTrue(model.ticked.contains("Concepts/Worksheet"), "The row's own tick was not kept")
    }

    // MARK: - The sheet brings what Publish writes

    /// For each case: the rows the sheet says each class brings, unioned over
    /// the classes, are exactly the offered rows the press's own plan changes
    /// because a class links them (plan risk R1). The last layout adds a page
    /// the writer declines (M11) and a row whose place the build read in the
    /// decomposed Unicode form (plan review, S2).
    func testTheSheetBringsWhatPublishWrites() throws {
        var layouts: [[String: Any]] = []
        for start in ["iv-j.", "iv-k.", "iv-b."] {
            layouts.append(try LinksChecklistTests.publishCase(start))
        }
        var odd: [String: Any] = try LinksChecklistTests.publishCase("iv-k.")
        var pages: [[String: Any]] = []
        for page in try XCTUnwrap(odd["pages"] as? [[String: Any]]) {
            var changed: [String: Any] = page
            if page["title"] as? String == "Unit 2, Day 5" {
                changed["links"] = ["Class Notes", "Listy", "Révision"]
            }
            pages.append(changed)
        }
        pages.append(["title": "Listy", "kind": "page", "visible": false, "date": "2026-02-01"])
        pages.append(["title": "Révision", "kind": "page", "visible": false, "date": "2026-02-01"])
        odd["pages"] = pages
        var offer: [[String: Any]] = try XCTUnwrap(odd["offer"] as? [[String: Any]])
        let decomposed: String = "Concepts/Révision".decomposedStringWithCanonicalMapping
        // Swift compares Strings by canonical equivalence, so the mac's own
        // lookups would match either form; the scalars prove this row is
        // really spelled the other way, as a file name read as bytes can be.
        XCTAssertNotEqual(decomposed.unicodeScalars.count, "Concepts/Révision".unicodeScalars.count)
        for place in ["Concepts/Listy", decomposed] {
            offer.append(["place": place, "group": "notReachedByAClass", "ticked": false, "step": NSNull(),
                          "claimedBy": NSNull(), "date": "2026-09-08", "why": "datedAsTheFirstClass",
                          "firstUsedIn": NSNull(), "dependsOn": [String]()])
        }
        odd["offer"] = offer
        odd["name"] = "a page the writer declines, and a row read decomposed"
        layouts.append(odd)

        for testCase in layouts {
            let name: String = testCase["name"] as? String ?? "?"
            let made: AssistFixture.Made = try AssistFixture.makeRunner()
            defer { try? FileManager.default.removeItem(at: made.root) }
            let urls: [String: URL] = try LinksChecklistTests.layOut(testCase, made: made)
            if let listy = urls["Listy"] {
                // Hidden, with its settings indented: no column-0 place for a
                // new key, so the writer declines it (#186).
                try "---\n  publish: false\n---\n\nListy.\n".write(to: listy, atomically: true, encoding: .utf8)
            }
            let model: LinksChecklistSheetModel = try LinksChecklistComingWithTests.sheet(for: testCase, made: made)
            var classes: Set<String> = []
            for row in model.classRows {
                classes.insert(row.place)
            }
            XCTAssertFalse(classes.isEmpty, name)
            model.ticked = classes
            var shown: Set<String> = []
            for place in model.comingWith.keys {
                shown.insert(place)
            }

            let graph: AssistSectionGraph = AssistSectionGraph.read(
                forSection: 1, in: made.course, workspaceURL: made.root
            )
            let planned: (plan: AssistPublishPlan, outcome: LinksChecklistPublisher.Outcome) = LinksChecklistPublisher.plan(
                offer: LinksChecklistOffer(course: "ICS3U", section: 1, buildId: "b1",
                                           firstClassPlace: model.offer.firstClassPlace, rows: model.rows),
                ticked: classes, graph: graph,
                classPages: ClassPages.list(forSection: 1, in: made.course),
                forSection: 1, in: made.course, shownComingWith: shown
            )
            var rowByComposedPlace: [String: String] = [:]
            for row in model.rows where row.group != .aClass {
                rowByComposedPlace[row.place.precomposedStringWithCanonicalMapping] = row.place
            }
            var written: Set<String> = []
            var broughtPages: Int = 0
            for change in planned.plan.changes where change.becauseLinked {
                broughtPages += 1
                let place: String = LinksChecklistPublisher.place(of: change.page.fileURL, in: made.course)
                if let rowPlace = rowByComposedPlace[place] {
                    written.insert(rowPlace)
                }
            }
            XCTAssertFalse(written.isEmpty, "\(name): the class brings no row, so this tests nothing")
            XCTAssertEqual(shown, written, "\(name): the sheet shows other rows coming with the class than Publish writes")
            var counted: Int = 0
            for place in classes {
                counted += model.broughtByClass[place] ?? 0
            }
            XCTAssertEqual(counted, broughtPages, "\(name): the class row's count is not what Publish brings")
            XCTAssertEqual(counted, planned.outcome.broughtByClasses, "\(name): the count is not the trail's")

            if urls["Listy"] != nil {
                let listy: LinksChecklistOffer.Row = try LinksChecklistComingWithTests.row("Concepts/Listy", in: model)
                XCTAssertNil(model.comingWith[listy.place], "A page the writer declines is shown coming with the class")
                XCTAssertEqual(planned.outcome.declined, ["Listy"])
                XCTAssertNotNil(model.comingWith[decomposed], "A row read decomposed is not shown coming with its class")
            }
        }
    }

    // MARK: - Cost on opening (plan review, S6)

    /// Twenty hidden classes behind one visible overview, each linking
    /// twenty-two hidden pages and one hub they share: ~460 pages, 20 class
    /// rows, 441 other rows. One planner call when the sheet opens; the time
    /// is printed for the ready note, not asserted.
    func testTwentyClassesAreWorkedOutInOnePlan() throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        var pages: [[String: Any]] = []
        var overviewLinks: [String] = []
        var offer: [[String: Any]] = []
        pages.append(["title": "Unit 1, Day 1", "kind": "class", "visible": true, "date": "2026-09-08",
                      "links": ["Unit Overview"]])
        pages.append(["title": "Shared Hub", "kind": "page", "visible": false, "date": "2026-02-01"])
        offer.append(["place": "Concepts/Shared Hub", "group": "notReachedByAClass", "ticked": false,
                      "why": "datedAsTheFirstClass", "date": "2026-09-08", "dependsOn": [String]()])
        for day in 1...20 {
            let title: String = "Unit 2, Day \(day)"
            overviewLinks.append(title)
            var links: [String] = ["Shared Hub"]
            for item in 1...22 {
                let page: String = "Day \(day) Item \(item)"
                links.append(page)
                pages.append(["title": page, "kind": "page", "visible": false, "date": "2026-02-01"])
                offer.append(["place": "Concepts/\(page)", "group": "notReachedByAClass", "ticked": false,
                              "why": "datedAsTheFirstClass", "date": "2026-09-08", "dependsOn": [String]()])
            }
            pages.append(["title": title, "kind": "class", "visible": false,
                          "date": String(format: "2026-10-%02d", day), "links": links])
            offer.append(["place": "section1/All Classes/\(title)", "group": "class", "ticked": false,
                          "why": "classNeverDated", "dependsOn": [String]()])
        }
        pages.append(["title": "Unit Overview", "kind": "page", "visible": true, "date": "2026-09-08",
                      "links": overviewLinks])
        _ = try LinksChecklistTests.layOut(["pages": pages], made: made)

        let started: Date = Date()
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: offer), answered: nil, occasion: .afterAPreview
        )
        let seconds: TimeInterval = Date().timeIntervalSince(started)
        print("LinksChecklistComingWithTests: \(pages.count) pages, \(model.rows.count) rows, "
              + "\(model.classRows.count) classes — the sheet opened in \(String(format: "%.3f", seconds)) s")

        XCTAssertEqual(model.classRows.count, 20)
        XCTAssertEqual(model.rows.count, 461)
        for row in model.classRows {
            XCTAssertEqual(model.broughtRowsByClass[row.place]?.count, 23, row.place)
            XCTAssertEqual(model.broughtByClass[row.place], 23, row.place)
        }
        model.ticked = ["section1/All Classes/Unit 2, Day 7", "section1/All Classes/Unit 2, Day 3"]
        XCTAssertEqual(model.comingWith.count, 45)
        XCTAssertEqual(model.comingWith["Concepts/Shared Hub"], "section1/All Classes/Unit 2, Day 3",
                       "The shared hub names the first ticked class in the sheet's order")
        XCTAssertEqual(model.publishButtonTitle, LinksChecklistWording.publishButton(
            count: "47", pages: LinksChecklistWording.pageWord(47)
        ))

        // One full redraw: everything the view asks of every row (#398
        // implementation review, finding 1 — this was ~11 s in Debug when the
        // shown state was worked out per row per access).
        let redrawStarted: Date = Date()
        var shownTickedCount: Int = 0
        for group in [LinksChecklistOffer.Group.fromAClass, .notReachedByAClass, .aClass] {
            for shownRow in model.shownRows(in: group) {
                let row: LinksChecklistOffer.Row = shownRow.row
                if model.binding(for: row).wrappedValue {
                    shownTickedCount += 1
                }
                _ = model.isDisabled(row)
                _ = model.rowTitle(for: row)
                _ = model.secondLine(for: row)
                _ = model.secondLine(for: row)
            }
        }
        _ = model.publishButtonTitle
        let redraw: TimeInterval = Date().timeIntervalSince(redrawStarted)
        print("LinksChecklistComingWithTests: one redraw of \(model.rows.count) rows took "
              + "\(String(format: "%.3f", redraw)) s")
        XCTAssertEqual(shownTickedCount, 47)
        XCTAssertLessThan(redraw, LinksChecklistComingWithTests.redrawCeiling,
                          "Drawing every row once took \(redraw) s: the shown state is being worked out per row again")

        // The planner's own answer for THESE two classes, not the whole set
        // (review note 5): the rows it would change because linked are
        // exactly the rows shown coming with them.
        let graph: AssistSectionGraph = AssistSectionGraph.read(forSection: 1, in: made.course, workspaceURL: made.root)
        let planned: (plan: AssistPublishPlan, outcome: LinksChecklistPublisher.Outcome) = LinksChecklistPublisher.plan(
            offer: LinksChecklistOffer(course: "ICS3U", section: 1, buildId: "b1",
                                       firstClassPlace: model.offer.firstClassPlace, rows: model.rows),
            ticked: model.ticked, graph: graph,
            classPages: ClassPages.list(forSection: 1, in: made.course),
            forSection: 1, in: made.course, shownComingWith: []
        )
        var written: Set<String> = []
        for change in planned.plan.changes where change.becauseLinked {
            written.insert(LinksChecklistPublisher.place(of: change.page.fileURL, in: made.course))
        }
        var shownComing: Set<String> = []
        for place in model.comingWith.keys {
            shownComing.insert(place)
        }
        XCTAssertEqual(shownComing, written, "Two of twenty classes: the sheet and Publish disagree")
    }

    /// Generous: one Debug redraw of 461 rows measures in milliseconds once
    /// the shown state is worked out once per tick.
    static let redrawCeiling: TimeInterval = 0.5
}
