import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The links checklist (#379): the sentences, the marker, when it is offered,
/// and what Publish writes — run from `contracts/shared-rules.json` →
/// `linksChecklist` rather than retyped.
///
/// The rule that CHOOSES the pages is the build's, and its cases run in
/// `scripts/test_links_checklist.py`; these are the app's half: reading the
/// offer, checking it again, and writing the ticked pages.
@MainActor
final class LinksChecklistTests: XCTestCase {

    // MARK: - Types

    struct MissingCase: Error {

        // MARK: - Stored properties

        let start: String
    }

    // MARK: - Functions

    static func contract() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("contracts/shared-rules.json")
        let object: Any = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let rules: [String: Any] = try XCTUnwrap(object as? [String: Any])
        return try XCTUnwrap(rules["linksChecklist"] as? [String: Any])
    }

    static func publishCase(_ start: String) throws -> [String: Any] {
        let cases: [[String: Any]] = try XCTUnwrap(contract()["publishCases"] as? [[String: Any]])
        for candidate in cases {
            if let name = candidate["name"] as? String, name.hasPrefix(start) {
                return candidate
            }
        }
        // A FAILURE, not a skip: a renamed case must not pass silently as one
        // more skipped test (plan-review note 8).
        XCTFail("No publish case starts “\(start)”")
        throw LinksChecklistTests.MissingCase(start: start)
    }

    /// Lays out a case's pages in section 1 of a fresh course, with a front
    /// page showing the first class, and returns each page's file by title.
    static func layOut(_ testCase: [String: Any], made: AssistFixture.Made) throws -> [String: URL] {
        let course: Course = made.course
        var urls: [String: URL] = [:]
        for page in try XCTUnwrap(testCase["pages"] as? [[String: Any]]) {
            let title: String = try XCTUnwrap(page["title"] as? String)
            let visible: Bool = page["visible"] as? Bool ?? true
            let date: String = try XCTUnwrap(page["date"] as? String)
            var body: String = "About \(title)."
            for target in page["links"] as? [String] ?? [] {
                body += "\n\nSee [[\(target)]]."
            }
            let url: URL
            let text: String
            if page["kind"] as? String == "class" {
                url = ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md")
                text = "---\ntitle: \(title)\npublish: \(visible)\ncreated: \(date)T07:00:00.000-0400\n---\n\n\(body)\n"
            } else {
                url = course.directoryURL.appendingPathComponent("Concepts").appendingPathComponent(title + ".md")
                text = "---\ntitle: \(title)\npublishForSection1: \(visible)\n"
                    + "createdSection1: \(date)T07:00:00.000-0400\n---\n\n\(body)\n"
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            urls[title] = url
        }
        let index: URL = SectionIndexPointer.indexURL(forSection: 1, in: course)
        try "---\ntitle: Home\npublish: true\n---\n\n![[Unit 1, Day 1]]\n"
            .write(to: index, atomically: true, encoding: .utf8)
        urls["index"] = index
        return urls
    }

    static func offer(from rows: [[String: Any]]) throws -> LinksChecklistOffer {
        var pages: [[String: Any]] = []
        for row in rows {
            var filled: [String: Any] = [:]
            for (key, value) in row {
                filled[key] = value
            }
            filled["title"] = LinksChecklistOffer.name(ofPlace: row["place"] as? String ?? "")
            filled["linkedFrom"] = row["linkedFrom"] ?? ["Concepts/How Marks Work"]
            pages.append(filled)
        }
        let object: [String: Any] = [
            "version": 1, "course": "ICS3U", "section": 1, "buildId": "b1",
            "firstClass": ["place": "section1/All Classes/Unit 1, Day 1", "date": "2026-09-08"],
            "pages": pages
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(LinksChecklistOffer.decode(data))
    }

    static func visible(_ url: URL) throws -> Bool {
        let text: String = try String(contentsOf: url, encoding: .utf8)
        return AssistPageVisibility.answer(in: text, forSection: 1) != .hidden
    }

    static func day(_ url: URL, isClass: Bool) throws -> String? {
        let text: String = try String(contentsOf: url, encoding: .utf8)
        let key: String = isClass ? "created" : "createdSection1"
        return PageFrontmatter.createdDay(in: text, key: key)?.text
    }

    // MARK: - The sentences

    func testTheWordingIsTheContractsWording() throws {
        let wording: [String: String] = try XCTUnwrap(LinksChecklistTests.contract()["wording"] as? [String: String])
        let ours: [String: String] = [
            "menuItem": LinksChecklistWording.menuItem,
            "sheetTitle": LinksChecklistWording.sheetTitle(course: "{course}", section: "{section}"),
            "intro": LinksChecklistWording.intro,
            "fromAClassHeading": LinksChecklistWording.fromAClassHeading,
            "notReachedHeading": LinksChecklistWording.notReachedHeading,
            "classesHeading": LinksChecklistWording.classesHeading,
            "datedLike": LinksChecklistWording.datedLike(name: "{name}"),
            "alreadyDatedLike": LinksChecklistWording.alreadyDatedLike(name: "{name}"),
            "keepsItsDate": LinksChecklistWording.keepsItsDate,
            "keepsTheDateItHas": LinksChecklistWording.keepsTheDateItHas,
            "datedAsTheFirstClass": LinksChecklistWording.datedAsTheFirstClass(name: "{name}"),
            "firstUsedIn": LinksChecklistWording.firstUsedIn(name: "{name}"),
            "classRow": LinksChecklistWording.classRow,
            "comesWith": LinksChecklistWording.comesWith(count: "{count}", pages: "{pages}"),
            "linkedFrom": LinksChecklistWording.linkedFrom(name: "{name}"),
            "linkedFromSeveral": LinksChecklistWording.linkedFromSeveral(name: "{name}", count: "{count}"),
            "linkedFromRow": LinksChecklistWording.linkedFromRow(name: "{name}"),
            "linkedFromSeveralRows": LinksChecklistWording.linkedFromSeveralRows(
                name: "{name}", count: "{count}", pages: "{pages}"
            ),
            "comesWithAClass": LinksChecklistWording.comesWithAClass(name: "{name}"),
            "rowInFolder": LinksChecklistWording.rowInFolder(page: "{page}", folder: "{folder}"),
            "frontPageStaysPut": LinksChecklistWording.frontPageStaysPut,
            "nothingChangesUntilYouDeploy": LinksChecklistWording.nothingChangesUntilYouDeploy,
            "publishButton": LinksChecklistWording.publishButton(count: "{count}", pages: "{pages}"),
            "publishNothingTicked": LinksChecklistWording.publishNothingTicked,
            "notNow": LinksChecklistWording.notNow,
            "deployUnderWay": LinksChecklistWording.deployUnderWay(course: "{course}"),
            "needsAPreviewFirst": LinksChecklistWording.needsAPreviewFirst(course: "{course}", section: "{section}"),
            "nothingLeftToPublish": LinksChecklistWording.nothingLeftToPublish,
            "pageChangedSince": LinksChecklistWording.pageChangedSince(name: "{name}"),
            "published": LinksChecklistWording.published(count: "{count}", pages: "{pages}")
        ]
        for (key, sentence) in ours {
            XCTAssertEqual(sentence, wording[key], key)
        }
        for key in wording.keys where key != "fill" && key != "machineryCheck" {
            XCTAssertNotNil(ours[key], "The contract has “\(key)” and the app does not say it")
        }
    }

    /// Rule 1, and the list the contract itself gives.
    func testNoSentenceNamesTheMachinery() throws {
        let wording: [String: String] = try XCTUnwrap(LinksChecklistTests.contract()["wording"] as? [String: String])
        let words: [String] = ["file", "script", "build step", "walk", "frontmatter", "link graph", "offer",
                               "json", "marker", "toolchain", "docker", "container", "workspace"]
        for (key, sentence) in wording where key != "fill" && key != "machineryCheck" {
            for word in words {
                XCTAssertFalse(sentence.lowercased().contains(word), "\(key) says “\(word)”: \(sentence)")
            }
        }
    }

    // MARK: - The marker

    func testTheMarkerIsTheContractsAndIsRead() throws {
        let marker: [String: Any] = try XCTUnwrap(LinksChecklistTests.contract()["marker"] as? [String: Any])
        XCTAssertEqual(LinksChecklistMarker.markerPrefix, marker["prefix"] as? String)
        let example: String = try XCTUnwrap(marker["example"] as? String)
        let found: [LinksChecklistMarker] = LinksChecklistMarker.markers(in: "🔨 Building…" + example + "\n")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.buildId, "20260929T233000Z-1a2b3c4d")
        XCTAssertEqual(found.first?.pages, 11)
        XCTAssertTrue(BuildMarkerLine.isMachineLine(example), "The marker would reach the console")
    }

    // MARK: - Where the finding goes

    func testTheFindingGoesToTheChecklistOnlyWhenThisBuildWroteTheOffer() throws {
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(from: [
            ["place": "Concepts/Worksheet", "group": "fromAClass", "ticked": true, "why": "dated", "date": "2026-09-08"]
        ])
        let this: LinksChecklistMarker = LinksChecklistMarker(course: "ICS3U", section: 1, buildId: "b1", pages: 1)
        let earlier: LinksChecklistMarker = LinksChecklistMarker(course: "ICS3U", section: 1, buildId: "b0", pages: 1)
        let empty: LinksChecklistMarker = LinksChecklistMarker(course: "ICS3U", section: 1, buildId: "b1", pages: 0)

        XCTAssertEqual(LinksChecklistRouting.route(
            marker: this, offer: offer, isKeptForReference: false, buildHasFinished: true), .checklist)
        XCTAssertEqual(LinksChecklistRouting.route(
            marker: this, offer: offer, isKeptForReference: true, buildHasFinished: true), .alert,
            "A course kept for reference keeps the alert")
        XCTAssertEqual(LinksChecklistRouting.route(
            marker: nil, offer: offer, isKeptForReference: false, buildHasFinished: false), .waitForTheBuild,
            "The finding is announced before the offer is written: wait for the build's word")
        XCTAssertEqual(LinksChecklistRouting.route(
            marker: nil, offer: offer, isKeptForReference: false, buildHasFinished: true), .alert,
            "A builder older than the app never says: the alert is the floor")
        XCTAssertEqual(LinksChecklistRouting.route(
            marker: earlier, offer: offer, isKeptForReference: false, buildHasFinished: true), .alert,
            "The offer on disk is another build's")
        XCTAssertEqual(LinksChecklistRouting.route(
            marker: empty, offer: offer, isKeptForReference: false, buildHasFinished: true), .alert)
        XCTAssertEqual(LinksChecklistRouting.route(
            marker: this, offer: nil, isKeptForReference: false, buildHasFinished: true), .alert)
    }

    func testAnUnwatchedPublishsFindingLeavesTheAlertOnlyWhenTheChecklistIsShown() {
        let links: SiteHealthFinding = SiteHealthFinding(
            name: "linksIntoHiddenPages", sentence: "s", detail: "d", fixable: false, course: "ICS3U", section: 1
        )
        let media: SiteHealthFinding = SiteHealthFinding(
            name: "mediaFolderMissing", sentence: "s", detail: "d", fixable: true, course: "ICS3U", section: 1
        )
        XCTAssertEqual(LinksChecklistRouting.findingsForTheAlert([links, media], checklistWillBeShown: true), [media])
        XCTAssertEqual(LinksChecklistRouting.findingsForTheAlert([links, media], checklistWillBeShown: false),
                       [links, media])
    }

    func testAStaleOfferIsNotShown() {
        let written: Date = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(LinksChecklistGate.isFresh(writtenAt: written, newestContentChange: Date(timeIntervalSince1970: 900)))
        XCTAssertFalse(LinksChecklistGate.isFresh(writtenAt: written, newestContentChange: Date(timeIntervalSince1970: 1_100)),
                       "A page changed after the build: the offer may name a link that is gone")
    }

    // MARK: - What Publish writes

    func runPublishCase(_ start: String) throws -> (urls: [String: URL], indexBefore: String, testCase: [String: Any]) {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase(start)
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: made.root)
        }
        let urls: [String: URL] = try LinksChecklistTests.layOut(testCase, made: made)
        let indexBefore: String = try String(contentsOf: try XCTUnwrap(urls["index"]), encoding: .utf8)
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(
            from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])
        )
        var ticked: Set<String> = []
        for place in testCase["tick"] as? [String] ?? [] {
            ticked.insert(place)
        }
        let result: LinksChecklistPublisher.Result = LinksChecklistPublisher.publish(
            offer: offer, ticked: ticked, course: made.course, sectionNumber: 1, workspaceURL: made.root,
            shownComingWith: []
        )
        guard case .published = result else {
            XCTFail("Publish did not publish: \(result)")
            return (urls, indexBefore, testCase)
        }
        return (urls, indexBefore, testCase)
    }

    func checkExpectations(_ run: (urls: [String: URL], indexBefore: String, testCase: [String: Any])) throws {
        let expect: [String: [String: Any]] = try XCTUnwrap(run.testCase["expect"] as? [String: [String: Any]])
        for (title, wanted) in expect {
            let url: URL = try XCTUnwrap(run.urls[title], title)
            let isClass: Bool = url.path.contains("/All Classes/")
            XCTAssertEqual(try LinksChecklistTests.visible(url), wanted["visible"] as? Bool, "\(title): visible")
            XCTAssertEqual(try LinksChecklistTests.day(url, isClass: isClass), wanted["date"] as? String, "\(title): date")
        }
        if run.testCase["expectFrontPageUnchanged"] as? Bool == true {
            let after: String = try String(contentsOf: try XCTUnwrap(run.urls["index"]), encoding: .utf8)
            XCTAssertEqual(after, run.indexBefore, "The front page moved (ruling F1)")
        }
    }

    func testTickedPagesArePublishedWithTheOffersDates() throws {
        try checkExpectations(try runPublishCase("iv-a."))
    }

    func testATickedClassBringsItsPagesAndItsDateWins() throws {
        try checkExpectations(try runPublishCase("iv-b."))
    }

    /// Ticking only a class publishes the row it brings; that row is not
    /// "left hidden" on the trail or in the answered file (review S1).
    func testARowATickedClassBringsIsNotLeftHidden() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-d.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let urls: [String: URL] = try LinksChecklistTests.layOut(testCase, made: made)
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(
            from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])
        )
        var ticked: Set<String> = []
        for place in testCase["tick"] as? [String] ?? [] {
            ticked.insert(place)
        }
        let result: LinksChecklistPublisher.Result = LinksChecklistPublisher.publish(
            offer: offer, ticked: ticked, course: made.course, sectionNumber: 1, workspaceURL: made.root,
            shownComingWith: []
        )
        guard case .published(let outcome) = result else {
            return XCTFail("Publish did not publish: \(result)")
        }
        let expected: [String] = (testCase["expectLeftHidden"] as? [String] ?? []).sorted()
        XCTAssertEqual(outcome.leftUntickedPlaces.sorted(), expected)
        XCTAssertEqual(outcome.leftUnticked, expected.count)
        XCTAssertFalse(LinksChecklistPublisher.publishedLine(outcome).contains("\(expected.count + 1) left unticked"))
        let answered: LinksChecklistAnswered = try XCTUnwrap(
            LinksChecklistAnswered.read(courseDirectory: made.course.directoryURL, section: 1)
        )
        XCTAssertEqual(answered.leftUnticked.sorted(), expected,
                       "The answered file says a page was left hidden that came with its class")
        for (title, wanted) in try XCTUnwrap(testCase["expect"] as? [String: [String: Any]]) {
            let url: URL = try XCTUnwrap(urls[title], title)
            XCTAssertEqual(try LinksChecklistTests.visible(url), wanted["visible"] as? Bool, "\(title): visible")
        }
    }

    func testAPageMadeVisibleSinceIsDropped() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-c.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let urls: [String: URL] = try LinksChecklistTests.layOut(testCase, made: made)
        for title in testCase["madeVisibleSince"] as? [String] ?? [] {
            let url: URL = try XCTUnwrap(urls[title])
            let text: String = try String(contentsOf: url, encoding: .utf8)
            try text.replacingOccurrences(of: "publishForSection1: false", with: "publishForSection1: true")
                .write(to: url, atomically: true, encoding: .utf8)
        }
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])),
            answered: nil, occasion: .afterAPreview
        )
        var offered: [String] = []
        for row in model.rows {
            offered.append(row.place)
        }
        XCTAssertEqual(offered.sorted(), (testCase["expectOffered"] as? [String] ?? []).sorted())
    }

    /// The defaults: the offer's own ticks — a class never ticked, a page a
    /// later class uses first unticked — and the line each row shows.
    func testTheSheetStartsWithTheOffersTicks() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-a.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        _ = try LinksChecklistTests.layOut(testCase, made: made)
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])),
            answered: nil, occasion: .afterAPreview
        )
        XCTAssertEqual(model.ticked, ["Concepts/Published Once"])
        let worksheet: LinksChecklistOffer.Row = try XCTUnwrap(model.fromAClassRows.first)
        XCTAssertTrue(model.secondLine(for: worksheet).hasPrefix(
            LinksChecklistWording.firstUsedIn(name: StartOfYearWording.pageName(page: "Unit 2, Day 5"))
        ))
        model.ticked.insert(worksheet.place)
        XCTAssertTrue(model.secondLine(for: worksheet).hasPrefix(
            LinksChecklistWording.datedLike(name: StartOfYearWording.pageName(page: "Unit 1, Day 1"))
        ),
                      "Ticked anyway, the row says the date it will take")
        let classRow: LinksChecklistOffer.Row = try XCTUnwrap(model.classRows.first)
        model.ticked.insert(classRow.place)
        XCTAssertTrue(model.secondLine(for: classRow).contains(
            LinksChecklistWording.comesWith(count: "2", pages: "pages")),
            model.secondLine(for: classRow))
    }

    func testAnAnsweredSetIsNotOfferedAgainUntilAPageJoinsIt() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("v.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        _ = try LinksChecklistTests.layOut(testCase, made: made)
        let rows: [[String: Any]] = try XCTUnwrap(testCase["offer"] as? [[String: Any]])
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(from: rows)
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: offer, answered: nil, occasion: .afterAPreview
        )
        for place in testCase["untick"] as? [String] ?? [] {
            model.ticked.remove(place)
        }
        model.notNow()
        let answered: LinksChecklistAnswered? = LinksChecklistAnswered.read(
            courseDirectory: made.course.directoryURL, section: 1
        )
        XCTAssertNotNil(answered)
        XCTAssertEqual(LinksChecklistGate.holdsSomethingNew(offer, answered: answered),
                       testCase["expectOfferedAgainBeforeTheNewPage"] as? Bool)
        var grown: [[String: Any]] = rows
        grown.append(try XCTUnwrap(testCase["thenOfferAlso"] as? [String: Any]))
        let grownOffer: LinksChecklistOffer = try LinksChecklistTests.offer(from: grown)
        XCTAssertEqual(LinksChecklistGate.holdsSomethingNew(grownOffer, answered: answered),
                       testCase["expectOfferedAgainAfter"] as? Bool)
        for place in testCase["expectStartsUnticked"] as? [String] ?? [] {
            var found: LinksChecklistOffer.Row?
            for row in grownOffer.rows where row.place == place {
                found = row
            }
            XCTAssertFalse(LinksChecklistGate.startsTicked(try XCTUnwrap(found), answered: answered),
                           "\(place) was unticked last time and starts ticked again")
        }
    }

    // MARK: - The sheet fits on the screen

    /// A hundred rows: the sheet is at most 620 pt (the Copy a Page rule,
    /// #365) and its list is really there (at least the cap).
    func testAHundredRowsFitOnTheScreen() throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        var rows: [[String: Any]] = []
        for index in 1...100 {
            let title: String = "Worksheet \(index)"
            try ("---\ntitle: \(title)\npublishForSection1: false\n---\n\nAbout it.\n").write(
                to: made.course.directoryURL.appendingPathComponent("Concepts/\(title).md"),
                atomically: true, encoding: .utf8
            )
            rows.append(["place": "Concepts/\(title)", "group": "notReachedByAClass", "ticked": true,
                         "why": "datedAsTheFirstClass", "date": "2026-09-08"])
        }
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: rows), answered: nil, occasion: .afterAPreview
        )
        XCTAssertEqual(model.rows.count, 100)
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(LinksChecklistSheet(model: model)))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 2000)
        hostingView.layoutSubtreeIfNeeded()
        let height: CGFloat = hostingView.fittingSize.height
        XCTAssertLessThanOrEqual(height, CopyPageChecklist.tallestSheet, "The checklist is \(height) pt tall")
        XCTAssertGreaterThanOrEqual(height, LinksChecklistSheet.tallestList + 60, "The list is not showing: \(height) pt")
    }
}
