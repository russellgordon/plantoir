import SwiftUI
import XCTest
@testable import QuartzTeachers

/// #385: a row reached only through another offered row is listed under it
/// and goes only with it; and the sheet names pages the way #362 does. Run
/// from `contracts/shared-rules.json` → `linksChecklist.followingARow`,
/// `.naming` and `publishCases` iv-e onwards, never retyped.
@MainActor
final class LinksChecklistFollowingTests: XCTestCase {

    // MARK: - Functions

    /// A row as the pure cases give it, read through the app's own decoder so
    /// a `dependsOn` it failed to read would fail here too.
    static func rows(from entries: [[String: Any]]) throws -> [LinksChecklistOffer.Row] {
        var pages: [[String: Any]] = []
        for entry in entries {
            let group: String = try XCTUnwrap(entry["group"] as? String)
            pages.append([
                "place": try XCTUnwrap(entry["place"] as? String),
                "group": group,
                "ticked": try XCTUnwrap(entry["ticked"] as? Bool),
                "why": group == "class" ? "classNeverDated" : "datedAsTheFirstClass",
                "date": group == "class" ? NSNull() : "2026-09-08",
                "dependsOn": try XCTUnwrap(entry["dependsOn"] as? [String])
            ])
        }
        let object: [String: Any] = ["course": "ICS3U", "section": 1, "buildId": "b1", "pages": pages]
        let offer: LinksChecklistOffer = try XCTUnwrap(
            LinksChecklistOffer.decode(try JSONSerialization.data(withJSONObject: object))
        )
        XCTAssertEqual(offer.rows.count, entries.count, "A row was not read")
        return offer.rows
    }

    static func places(_ list: Any?) -> [String] {
        return ((list as? [String]) ?? []).sorted()
    }

    static func flipToVisible(_ url: URL) throws {
        let text: String = try String(contentsOf: url, encoding: .utf8)
        let changed: String = text
            .replacingOccurrences(of: "publishForSection1: false", with: "publishForSection1: true")
            .replacingOccurrences(of: "publish: false", with: "publish: true")
        XCTAssertNotEqual(changed, text, "\(url.lastPathComponent) was not hidden")
        try changed.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - followingARow: the pure cases

    func testFollowingARowAsTheContractSays() throws {
        let rule: [String: Any] = try XCTUnwrap(LinksChecklistTests.contract()["followingARow"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10, "The cases cannot pass by running none")
        for testCase in cases {
            let name: String = testCase["name"] as? String ?? "?"
            let rows: [LinksChecklistOffer.Row] = try LinksChecklistFollowingTests.rows(
                from: try XCTUnwrap(testCase["rows"] as? [[String: Any]])
            )
            var ticked: Set<String> = []
            for row in rows where row.ticked {
                ticked.insert(row.place)
            }
            for step in testCase["steps"] as? [[String: String]] ?? [] {
                if let place = step["tick"] {
                    ticked = LinksChecklistGate.toggled(ticked, place: place, isOn: true, comingWith: [:])
                }
                if let place = step["untick"] {
                    ticked = LinksChecklistGate.toggled(ticked, place: place, isOn: false, comingWith: [:])
                }
            }
            let going: Set<String> = LinksChecklistGate.going(rows, ticked: ticked)
            var locked: [String] = []
            for row in rows where LinksChecklistGate.isLocked(row, going: going, comingWith: [:]) {
                locked.append(row.place)
            }
            XCTAssertEqual(going.sorted(), LinksChecklistFollowingTests.places(testCase["expectGoing"]), "\(name): going")
            XCTAssertEqual(locked.sorted(), LinksChecklistFollowingTests.places(testCase["expectLocked"]), "\(name): locked")
            if let expectShown = testCase["expectShown"] as? [[Any]] {
                var wanted: [String] = []
                for pair in expectShown {
                    wanted.append("\(pair[0]) \(pair[1])")
                }
                var shown: [String] = []
                for entry in LinksChecklistGate.shownOrder(rows) {
                    shown.append("\(entry.row.place) \(entry.depth)")
                }
                XCTAssertEqual(shown, wanted, "\(name): shown")
            }
        }
    }

    /// The model's own checkbox is the contract's `toggled`: ticking the top
    /// row through the BINDING leaves the row under it as it was (case 7's
    /// shape, through the code path the view uses).
    func testTheCheckboxChangesOnlyItsOwnRow() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-e.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        _ = try LinksChecklistTests.layOut(testCase, made: made)
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])),
            answered: nil, occasion: .afterAPreview
        )
        model.ticked = ["Concepts/Glossary"]
        var hub: LinksChecklistOffer.Row?
        var worksheet: LinksChecklistOffer.Row?
        for row in model.rows {
            if row.place == "Concepts/Hub" {
                hub = row
            }
            if row.place == "Concepts/Worksheet" {
                worksheet = row
            }
        }
        let hubRow: LinksChecklistOffer.Row = try XCTUnwrap(hub)
        let worksheetRow: LinksChecklistOffer.Row = try XCTUnwrap(worksheet)
        XCTAssertTrue(model.isLocked(worksheetRow))
        model.binding(for: hubRow).wrappedValue = true
        XCTAssertEqual(model.ticked, ["Concepts/Glossary", "Concepts/Hub"], "Ticking the hub ticked what is under it")
        XCTAssertFalse(model.binding(for: worksheetRow).wrappedValue)
        XCTAssertFalse(model.isLocked(worksheetRow))
        model.binding(for: worksheetRow).wrappedValue = true
        model.binding(for: hubRow).wrappedValue = false
        XCTAssertTrue(model.ticked.contains("Concepts/Worksheet"), "Unticking the hub cleared the tick under it")
        XCTAssertFalse(model.binding(for: worksheetRow).wrappedValue, "A locked row shows ticked")
        XCTAssertTrue(model.isLocked(worksheetRow))
    }

    // MARK: - publishCases from iv-e: through the sheet

    struct SheetRun {

        // MARK: - Stored properties

        let testCase: [String: Any]
        let urls: [String: URL]
        let made: AssistFixture.Made
        let model: LinksChecklistSheetModel
        let outcome: LinksChecklistPublisher.Outcome
        let trail: String
    }

    func runThroughTheSheet(_ start: String) throws -> SheetRun {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase(start)
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: made.root)
        }
        let urls: [String: URL] = try LinksChecklistTests.layOut(testCase, made: made)
        let offerRows: [[String: Any]] = try XCTUnwrap(testCase["offer"] as? [[String: Any]])
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(from: offerRows)
        var anyDependsOn: Bool = false
        for row in offer.rows where !row.dependsOn.isEmpty {
            anyDependsOn = true
        }
        // A #385 case whose rows carry no dependsOn tests nothing (plan risk
        // 4) — unless it is a #398 case, which tests the rows a class brings.
        let isAComingWithCase: Bool = testCase["expectComesWith"] != nil
        XCTAssertTrue(anyDependsOn || isAComingWithCase,
                      "A #385 case whose rows carry no dependsOn tests nothing (plan risk 4)")
        for title in testCase["deletedSince"] as? [String] ?? [] {
            try FileManager.default.removeItem(at: try XCTUnwrap(urls[title]))
        }
        for title in testCase["madeVisibleSince"] as? [String] ?? [] {
            try LinksChecklistFollowingTests.flipToVisible(try XCTUnwrap(urls[title]))
        }
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: offer, answered: nil, occasion: .afterAPreview
        )
        if let expectOffered = testCase["expectOffered"] {
            var offered: [String] = []
            for row in model.rows {
                offered.append(row.place)
            }
            XCTAssertEqual(offered.sorted(), LinksChecklistFollowingTests.places(expectOffered), "\(start) offered")
        }
        model.ticked = Set(testCase["tick"] as? [String] ?? [])
        var locked: [String] = []
        for row in model.rows where model.isLocked(row) {
            locked.append(row.place)
        }
        XCTAssertEqual(locked.sorted(), LinksChecklistFollowingTests.places(testCase["expectLocked"]), "\(start) locked")
        if let expectComesWith = testCase["expectComesWith"] as? [String: String] {
            XCTAssertEqual(model.comingWith, expectComesWith, "\(start) comes with")
            for row in model.rows where expectComesWith[row.place] != nil {
                XCTAssertTrue(model.isDisabled(row), "\(start): \(row.place) comes with a class and can be changed")
                XCTAssertTrue(model.binding(for: row).wrappedValue, "\(start): \(row.place) comes with a class and shows unticked")
            }
        }
        try LinksChecklistFollowingTests.checkSecondLines(model, testCase, start: start)
        if let count = testCase["expectPublishCount"] as? Int {
            let wanted: String = count == 0
                ? LinksChecklistWording.publishNothingTicked
                : LinksChecklistWording.publishButton(count: String(count), pages: LinksChecklistWording.pageWord(count))
            XCTAssertEqual(model.publishButtonTitle, wanted, "\(start) button")
        }
        for title in testCase["madeVisibleAfterOpening"] as? [String] ?? [] {
            try LinksChecklistFollowingTests.flipToVisible(try XCTUnwrap(urls[title]))
        }

        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("links-checklist-trail-\(UUID().uuidString)")
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = store
        defer {
            ActivityTrail.store = previous
            try? FileManager.default.removeItem(at: folderURL)
        }
        model.publish()
        guard case .done(let outcome) = model.stage else {
            XCTFail("\(start): Publish did not publish: \(model.stage)")
            throw LinksChecklistTests.MissingCase(start: start)
        }
        let trail: String = store.activityText(includingPrompts: false)
        return SheetRun(testCase: testCase, urls: urls, made: made, model: model, outcome: outcome, trail: trail)
    }

    /// `expectSecondLines` / `expectSecondLinesLack` (#398): parts a row's
    /// second line must, or must not, contain.
    static func checkSecondLines(_ model: LinksChecklistSheetModel, _ testCase: [String: Any], start: String) throws {
        let keys: [(key: String, mustContain: Bool)] = [("expectSecondLines", true), ("expectSecondLinesLack", false)]
        for entry in keys {
            for (place, parts) in testCase[entry.key] as? [String: [[String: String]]] ?? [:] {
                var found: LinksChecklistOffer.Row?
                for row in model.rows where row.place == place {
                    found = row
                }
                let line: String = model.secondLine(for: try XCTUnwrap(found, "\(start): \(place) is not offered"))
                for part in parts {
                    let name: String = StartOfYearWording.pageName(page: try XCTUnwrap(part["name"]))
                    let wanted: String
                    switch part["wording"] {
                    case "comesWithAClass":
                        wanted = LinksChecklistWording.comesWithAClass(name: name)
                    case "firstUsedIn":
                        wanted = LinksChecklistWording.firstUsedIn(name: name)
                    case "linkedFromRow":
                        wanted = LinksChecklistWording.linkedFromRow(name: name)
                    case "datedLike":
                        wanted = LinksChecklistWording.datedLike(name: name)
                    default:
                        XCTFail("The harness does not know \(part["wording"] ?? "nil")")
                        wanted = "?"
                    }
                    if entry.mustContain {
                        XCTAssertTrue(line.contains(wanted), "\(start) \(place): “\(line)” lacks “\(wanted)”")
                    } else {
                        XCTAssertFalse(line.contains(wanted), "\(start) \(place): “\(line)” says “\(wanted)”")
                    }
                }
            }
        }
    }

    func checkTheSheetRun(_ run: SheetRun) throws {
        let name: String = run.testCase["name"] as? String ?? "?"
        if let changed = run.testCase["expectChangedSince"] as? [String] {
            var wanted: [String] = []
            for title in changed {
                wanted.append(StartOfYearWording.pageName(page: title))
            }
            XCTAssertEqual(run.outcome.changedSince.sorted(), wanted.sorted(), "\(name): changed since")
        }
        if let count = run.testCase["expectCameWithAClass"] as? Int {
            XCTAssertEqual(run.outcome.cameWithAClass, count, "\(name): rows that came with a class")
        }
        for (title, wanted) in try XCTUnwrap(run.testCase["expect"] as? [String: [String: Any]]) {
            let url: URL = try XCTUnwrap(run.urls[title], title)
            let isClass: Bool = url.path.contains("/All Classes/")
            XCTAssertEqual(try LinksChecklistTests.visible(url), wanted["visible"] as? Bool, "\(name) — \(title): visible")
            XCTAssertEqual(try LinksChecklistTests.day(url, isClass: isClass), wanted["date"] as? String,
                           "\(name) — \(title): date")
        }
        var leftHidden: [String] = run.outcome.leftUntickedPlaces
        for place in run.outcome.leftWithTheirPagePlaces {
            leftHidden.append(place)
        }
        XCTAssertEqual(leftHidden.sorted(), LinksChecklistFollowingTests.places(run.testCase["expectLeftHidden"]),
                       "\(name): left hidden")
        XCTAssertEqual(run.outcome.leftWithTheirPagePlaces.sorted(),
                       LinksChecklistFollowingTests.places(run.testCase["expectLeftWithTheirPage"]),
                       "\(name): left with their page")
        XCTAssertEqual(run.outcome.leftWithTheirPage, run.outcome.leftWithTheirPagePlaces.count)
        let remembered: [String] = LinksChecklistFollowingTests.places(run.testCase["expectRememberedUnticked"])
        XCTAssertEqual(run.outcome.leftUntickedPlaces.sorted(), remembered, "\(name): left unticked")
        let answered: LinksChecklistAnswered = try XCTUnwrap(
            LinksChecklistAnswered.read(courseDirectory: run.made.course.directoryURL, section: 1)
        )
        XCTAssertEqual(answered.leftUnticked.sorted(), remembered,
                       "\(name): the answered file remembers a row the teacher did not untick")
        let total: Int = leftHidden.count
        let setAside: String = LinksChecklistPublisher.setAsideLine(
            notNow: false, count: total, withTheirPage: run.outcome.leftWithTheirPage
        )
        if total > 0 {
            XCTAssertTrue(run.trail.contains(setAside), "\(name): the trail lacks “\(setAside)”:\n\(run.trail)")
        } else {
            XCTAssertFalse(run.trail.contains(ActivityTrail.Event.linksChecklistSetAside.rawValue),
                           "\(name): nothing was left, and the trail says pages were")
        }
    }

    func testAPageUnderAnUntickedPageIsLeftWithIt() throws {
        let run: SheetRun = try runThroughTheSheet("iv-e.")
        try checkTheSheetRun(run)
    }

    func testAPageTickedWithThePageItComesUnderGoesWithIt() throws {
        try checkTheSheetRun(try runThroughTheSheet("iv-f."))
    }

    func testAPageIsFreedWhenItsPageIsMadeVisibleBeforeTheSheetOpens() throws {
        try checkTheSheetRun(try runThroughTheSheet("iv-g."))
    }

    func testAPageIsDroppedWhenItsPageIsGone() throws {
        try checkTheSheetRun(try runThroughTheSheet("iv-h."))
    }

    func testARowShownLockedIsNotPublishedWhenItsPageIsMadeVisibleWhileTheSheetIsOpen() throws {
        try checkTheSheetRun(try runThroughTheSheet("iv-i."))
    }

    // MARK: - publishCases from iv-j: rows a ticked class brings (#398)

    func runAComingWithCase(_ start: String) throws -> SheetRun {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase(start)
        let comesWith: [String: String] = try XCTUnwrap(testCase["expectComesWith"] as? [String: String], start)
        XCTAssertFalse(comesWith.isEmpty, "\(start): a #398 case that shows nothing coming with a class tests nothing")
        XCTAssertNotNil(testCase["expectCameWithAClass"], "\(start) does not pin the trail's count")
        let run: SheetRun = try runThroughTheSheet(start)
        try checkTheSheetRun(run)
        return run
    }

    func testARowUnderAnUntickedPageThatAClassBringsIsShownComingWithIt() throws {
        _ = try runAComingWithCase("iv-j.")
    }

    func testARowAClassBringsThroughAnotherPageTakesTheClasssDate() throws {
        _ = try runAComingWithCase("iv-k.")
    }

    func testARowShownComingWithAClassMadeVisibleWhileOpenIsNamedNotRemembered() throws {
        _ = try runAComingWithCase("iv-l.")
    }

    // MARK: - An offer from an older builder

    func testAnOfferFromAnOlderBuilderReadsAsBefore() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-a.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        _ = try LinksChecklistTests.layOut(testCase, made: made)
        let rows: [[String: Any]] = try XCTUnwrap(testCase["offer"] as? [[String: Any]])
        for row in rows {
            XCTAssertNil(row["dependsOn"], "iv-a is meant to be an offer written before #385")
        }
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(from: rows)
        XCTAssertEqual(offer.rows.count, rows.count, "A row without dependsOn was not read")
        for row in offer.rows {
            XCTAssertEqual(row.dependsOn, [])
        }
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: offer, answered: nil, occasion: .afterAPreview
        )
        XCTAssertFalse(model.rows.isEmpty)
        XCTAssertEqual(model.going, model.ticked, "With nothing under anything, what goes is what is ticked (#379)")
        for shown in LinksChecklistGate.shownOrder(model.rows) {
            XCTAssertEqual(shown.depth, 0)
            XCTAssertEqual(shown.group, shown.row.group)
        }
    }

    // MARK: - Naming (#385's notes, #362's builder)

    /// Lays out a naming case the way `startOfYear.howToRunACase` defines its
    /// keys: `folder`, `shownAs`, and a `folderIndex` written with NO title.
    static func layOutForNaming(_ testCase: [String: Any], made: AssistFixture.Made) throws {
        let course: Course = made.course
        for page in try XCTUnwrap(testCase["pages"] as? [[String: Any]]) {
            let title: String = try XCTUnwrap(page["title"] as? String)
            let visible: Bool = page["visible"] as? Bool ?? true
            var body: String = "About \(title)."
            for target in page["links"] as? [String] ?? [] {
                body += "\n\nSee [[\(target)]]."
            }
            let url: URL
            let text: String
            switch page["kind"] as? String {
            case "class":
                url = ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md")
                text = "---\ntitle: \(title)\npublish: \(visible)\ncreated: 2026-09-08T07:00:00.000-0400\n---\n\n\(body)\n"
            case "folderIndex":
                url = course.directoryURL.appendingPathComponent(title).appendingPathComponent("index.md")
                text = "---\npublishForSection1: \(visible)\n---\n\n\(body)\n"
            default:
                let folder: String = page["folder"] as? String ?? "Concepts"
                let shownAs: String = page["shownAs"] as? String ?? title
                url = course.directoryURL.appendingPathComponent(folder).appendingPathComponent(title + ".md")
                text = "---\ntitle: \(shownAs)\npublishForSection1: \(visible)\n---\n\n\(body)\n"
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let index: URL = SectionIndexPointer.indexURL(forSection: 1, in: course)
        try "---\ntitle: Home\npublish: true\n---\n\n![[Unit 1, Day 1]]\n"
            .write(to: index, atomically: true, encoding: .utf8)
    }

    static func expectedTitle(_ wanted: [String: Any]) throws -> String {
        if let plain = wanted["plain"] as? String {
            return plain
        }
        XCTAssertEqual(wanted["wording"] as? String, "rowInFolder")
        return LinksChecklistWording.rowInFolder(
            page: try XCTUnwrap(wanted["page"] as? String), folder: try XCTUnwrap(wanted["folder"] as? String)
        )
    }

    func checkRowTitles(_ model: LinksChecklistSheetModel, _ wanted: [String: [String: Any]]) throws {
        var byPlace: [String: LinksChecklistOffer.Row] = [:]
        for row in model.rows {
            byPlace[row.place] = row
        }
        for (place, expectation) in wanted {
            let row: LinksChecklistOffer.Row = try XCTUnwrap(byPlace[place], "\(place) is not offered")
            let expected: String = try LinksChecklistFollowingTests.expectedTitle(expectation)
            XCTAssertEqual(model.rowTitle(for: row), expected, place)
            if expected != row.title {
                XCTAssertNotEqual(model.rowTitle(for: row), row.title, "\(place) is shown by its file name")
            }
        }
    }

    func testRowsAreNamedAsTheContractSays() throws {
        let naming: [String: Any] = try XCTUnwrap(LinksChecklistTests.contract()["naming"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(naming["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 2)
        for testCase in cases {
            let made: AssistFixture.Made = try AssistFixture.makeRunner()
            defer { try? FileManager.default.removeItem(at: made.root) }
            try LinksChecklistFollowingTests.layOutForNaming(testCase, made: made)
            var offerRows: [[String: Any]] = []
            for row in try XCTUnwrap(testCase["offer"] as? [[String: Any]]) {
                var filled: [String: Any] = row
                filled["linkedFrom"] = testCase["linkedFrom"]
                offerRows.append(filled)
            }
            let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
                course: made.course, sectionNumber: 1, workspaceURL: made.root,
                offer: try LinksChecklistTests.offer(from: offerRows), answered: nil, occasion: .afterAPreview
            )
            XCTAssertEqual(model.rows.count, offerRows.count, "A row was dropped: \(model.rows)")
            if let titles = testCase["expectRowTitles"] as? [String: [String: Any]] {
                try checkRowTitles(model, titles)
            }
            for (place, parts) in testCase["expectSecondLines"] as? [String: [[String: String]]] ?? [:] {
                var found: LinksChecklistOffer.Row?
                for row in model.rows where row.place == place {
                    found = row
                }
                let line: String = model.secondLine(for: try XCTUnwrap(found, "\(place) is not offered"))
                for part in parts {
                    let name: String = StartOfYearWording.pageName(page: try XCTUnwrap(part["name"]))
                    let wanted: String
                    switch part["wording"] {
                    case "firstUsedIn":
                        wanted = LinksChecklistWording.firstUsedIn(name: name)
                    case "linkedFromRow":
                        wanted = LinksChecklistWording.linkedFromRow(name: name)
                    default:
                        XCTFail("The harness does not know \(part["wording"] ?? "nil")")
                        wanted = "?"
                    }
                    XCTAssertTrue(line.contains(wanted), "\(place): “\(line)” lacks “\(wanted)”")
                }
            }
            for row in model.rows {
                let line: String = model.secondLine(for: row)
                for wanted in testCase["expectSecondLinesContain"] as? [[String: String]] ?? [] {
                    XCTAssertEqual(wanted["wording"], "pageName")
                    let name: String = StartOfYearWording.pageName(page: try XCTUnwrap(wanted["page"]))
                    XCTAssertTrue(line.contains(name), "\(row.place): “\(line)” lacks \(name)")
                }
                for unwanted in testCase["expectSecondLinesNeverContain"] as? [String] ?? [] {
                    XCTAssertFalse(line.contains(unwanted), "\(row.place): “\(line)” says \(unwanted)")
                }
            }
            // A row gone from the sheet: the title is still shared across the
            // SECTION, so the other row keeps its folder.
            if let without = testCase["thenWithout"] as? String {
                var fewer: [[String: Any]] = []
                for row in offerRows where row["place"] as? String != without {
                    fewer.append(row)
                }
                XCTAssertEqual(fewer.count, offerRows.count - 1)
                let second: LinksChecklistSheetModel = LinksChecklistSheetModel(
                    course: made.course, sectionNumber: 1, workspaceURL: made.root,
                    offer: try LinksChecklistTests.offer(from: fewer), answered: nil, occasion: .afterAPreview
                )
                try checkRowTitles(second, try XCTUnwrap(testCase["expectRowTitlesThen"] as? [String: [String: Any]]))
            }
        }
    }

    /// A page gone since the sheet showed it is named by the build's title,
    /// not its file name (plan-review note 6).
    func testAPageGoneSinceIsNamedByItsTitle() throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let graph: AssistSectionGraph = AssistSectionGraph(courseCode: "ICS3U", sectionNumber: 1, pages: [])
        let rows: [LinksChecklistOffer.Row] = try LinksChecklistFollowingTests.rows(from: [
            ["place": "Concepts/notes-v2", "group": "notReachedByAClass", "ticked": true, "dependsOn": []]
        ])
        let row: LinksChecklistOffer.Row = rows[0]
        let titled: LinksChecklistOffer.Row = LinksChecklistOffer.Row(
            place: row.place, title: "Class Notes", group: row.group, ticked: row.ticked, step: nil,
            claimedBy: nil, date: row.date, why: row.why, firstUsedIn: nil, linkedFrom: [], dependsOn: []
        )
        let naming: LinksChecklistNaming = LinksChecklistNaming(
            graph: graph, pagesByPlace: [:], rows: [titled],
            courseDirectoryURL: made.course.directoryURL, courseCode: made.course.code
        )
        XCTAssertEqual(naming.name(ofPlace: "Concepts/notes-v2"), StartOfYearWording.pageName(page: "Class Notes"))
        XCTAssertEqual(naming.name(ofPlace: "Concepts/Elsewhere"), StartOfYearWording.pageName(page: "Elsewhere"))
    }

    // MARK: - The trail

    /// Each of the three lines, filled from the contract's own template.
    static func template(_ event: ActivityTrail.Event) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("contracts/shared-rules.json")
        let object: Any = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let rules: [String: Any] = try XCTUnwrap(object as? [String: Any])
        let trail: [String: Any] = try XCTUnwrap(rules["activityTrail"] as? [String: Any])
        for entry in try XCTUnwrap(trail["mustRecord"] as? [[String: Any]]) where entry["event"] as? String == event.rawValue {
            let line: String = try XCTUnwrap(entry["line"] as? String)
            let prefix: String = "{course}/{section} · "
            XCTAssertTrue(line.hasPrefix(prefix))
            return String(line.dropFirst(prefix.count))
        }
        XCTFail("No mustRecord entry for \(event.rawValue)")
        return ""
    }

    /// Fills `{N}`-style placeholders in order.
    static func fill(_ template: String, _ values: [(placeholder: String, value: String)]) -> String {
        var filled: String = template
        for pair in values {
            guard let range = filled.range(of: pair.placeholder) else {
                XCTFail("\(pair.placeholder) is not in “\(filled)”")
                continue
            }
            filled.replaceSubrange(range, with: pair.value)
        }
        return filled
    }

    func testTheTrailLinesAreTheContracts() throws {
        // Offered: iv-e's sheet with Worksheet's own tick on but locked, so
        // "ticked" is 1 (Glossary), not 2.
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-e.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        _ = try LinksChecklistTests.layOut(testCase, made: made)
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])),
            answered: nil, occasion: .afterAPreview
        )
        model.ticked = ["Concepts/Glossary", "Concepts/Worksheet"]
        let offered: String = LinksChecklistFollowingTests.fill(
            try LinksChecklistFollowingTests.template(.linksChecklistOffered),
            [("{occasion}", LinksChecklistGate.Occasion.afterAPreview.rawValue),
             ("{N}", "2"), ("{N}", "1"), ("{N}", "0"), ("{N}", "1"), ("{N}", "1")]
        )
        XCTAssertEqual(LinksChecklistPublisher.offeredLine(model: model), offered)

        // Published and set aside: iv-e's press.
        let run: SheetRun = try runThroughTheSheet("iv-e.")
        let published: String = LinksChecklistFollowingTests.fill(
            try LinksChecklistFollowingTests.template(.pagesPublishedFromLinksChecklist),
            [("{N pages}", "1 page"), ("{N}", "1"), ("{N}", "0"), ("{N}", "0"), ("{N classes}", "0 classes"),
             ("{N}", "0"), ("{N}", "0"), ("{N}", "1"), ("{N}", "1"), ("{places}", "Concepts/Glossary")]
        )
        XCTAssertEqual(LinksChecklistPublisher.publishedLine(run.outcome), published)
        XCTAssertTrue(run.trail.contains(published), run.trail)
        let setAside: String = LinksChecklistFollowingTests.fill(
            try LinksChecklistFollowingTests.template(.linksChecklistSetAside),
            [("{Not Now|some unticked}", "some unticked"), ("{N pages}", "2 pages"), ("{N}", "1")]
        )
        XCTAssertTrue(run.trail.contains(setAside), "“\(setAside)” is not on the trail:\n\(run.trail)")

        // #398: iv-j's press, whose class brought one row of the list.
        let brought: SheetRun = try runThroughTheSheet("iv-j.")
        let broughtLine: String = LinksChecklistFollowingTests.fill(
            try LinksChecklistFollowingTests.template(.pagesPublishedFromLinksChecklist),
            [("{N pages}", "2 pages"), ("{N}", "0"), ("{N}", "0"), ("{N}", "0"), ("{N classes}", "1 class"),
             ("{N}", "1"), ("{N}", "1"), ("{N}", "1"), ("{N}", "0"),
             ("{places}", "Concepts/Worksheet, section1/All Classes/Unit 3, Day 1")]
        )
        XCTAssertEqual(LinksChecklistPublisher.publishedLine(brought.outcome), broughtLine)
        XCTAssertTrue(brought.trail.contains(broughtLine), brought.trail)
        XCTAssertEqual(LinksChecklistPublisher.setAsideLine(notNow: true, count: 3, withTheirPage: 0),
                       LinksChecklistFollowingTests.fill(
                        try LinksChecklistFollowingTests.template(.linksChecklistSetAside),
                        [("{Not Now|some unticked}", "Not Now"), ("{N pages}", "3 pages"), ("{N}", "0")]
                       ))
    }

    // MARK: - The sheet fits on the screen

    /// A hundred rows, each under the one before: the indent is capped, and
    /// the sheet stays within 620 pt (#365's rule).
    func testAHundredDeepChainFitsOnTheScreen() throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        var rows: [[String: Any]] = []
        for index in 1...100 {
            let title: String = "Worksheet \(index)"
            try ("---\ntitle: \(title)\npublishForSection1: false\n---\n\nAbout it.\n").write(
                to: made.course.directoryURL.appendingPathComponent("Concepts/\(title).md"),
                atomically: true, encoding: .utf8
            )
            var row: [String: Any] = ["place": "Concepts/\(title)", "group": "notReachedByAClass", "ticked": true,
                                      "why": "datedAsTheFirstClass", "date": "2026-09-08"]
            row["dependsOn"] = index == 1 ? [] : ["Concepts/Worksheet \(index - 1)"]
            rows.append(row)
        }
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: rows), answered: nil, occasion: .afterAPreview
        )
        XCTAssertEqual(model.rows.count, 100)
        XCTAssertEqual(model.going.count, 100)
        let shown: [LinksChecklistGate.ShownRow] = model.shownRows(in: .notReachedByAClass)
        XCTAssertEqual(shown.count, 100)
        XCTAssertEqual(shown.last?.depth, 99)
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(LinksChecklistSheet(model: model)))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 2000)
        hostingView.layoutSubtreeIfNeeded()
        let height: CGFloat = hostingView.fittingSize.height
        XCTAssertLessThanOrEqual(height, CopyPageChecklist.tallestSheet, "The checklist is \(height) pt tall")
        XCTAssertLessThanOrEqual(hostingView.fittingSize.width, 560 + 1, "The indent pushed the sheet wider")
    }
}
