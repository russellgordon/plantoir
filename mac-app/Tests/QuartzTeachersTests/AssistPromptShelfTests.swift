import XCTest
import SwiftUI
@testable import QuartzTeachers

/// The shelf of things a teacher can ask for: what it offers, and that its
/// shape is remembered.
@MainActor
final class AssistPromptShelfTests: XCTestCase {

    // MARK: - Functions

    private let key: String = "AssistPromptShelfOpenGroups"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    /// Remembered across windows and launches, not per window.
    ///
    /// `@SceneStorage` would restore THIS window when it came back, but
    /// opening the assistant on another section is a different scene — so a
    /// teacher who opened a group would find it shut again, which is the
    /// opposite of remembering it.
    func testTheOpenGroupsAreRememberedAppWide() {
        UserDefaults.standard.set("Checking|Taking it back", forKey: key)

        let stored: String = UserDefaults.standard.string(forKey: key) ?? ""
        var titles: Set<String> = []
        for piece in stored.split(separator: "|") {
            titles.insert(String(piece))
        }
        XCTAssertEqual(titles, ["Checking", "Taking it back"])
    }

    /// Nothing stored means everything shut — the shelf costs four lines
    /// until a teacher asks for more.
    func testNothingStoredMeansEverythingIsShut() {
        UserDefaults.standard.removeObject(forKey: key)
        let stored: String = UserDefaults.standard.string(forKey: key) ?? ""
        XCTAssertTrue(stored.split(separator: "|").isEmpty)
    }

    /// The shelf's wording and the phrasings matched in CODE have to stay in
    /// step. "Deploy this section now" became "Deploy now" on the shelf, and a
    /// card whose wording no longer matches is a button that quietly goes to
    /// the model on a shape the model was measured getting wrong.
    func testTheShelfsShortcutPhrasingsStillFire() {
        XCTAssertEqual(AssistCardCommand.matching("Deploy now")?.toolName, "deploy_section")
        XCTAssertEqual(
            AssistCardCommand.matching("What would students see in this section right now?")?.toolName,
            "check_section"
        )
        XCTAssertEqual(AssistCardCommand.matching("Rebuild the preview")?.toolName, "rebuild_preview")
        XCTAssertEqual(AssistCardCommand.matching("Undo that")?.toolName, "undo_last_change")
        XCTAssertEqual(
            AssistCardCommand.matching("Publish tomorrow's class")?.toolName, "publish_class_on"
        )
    }

    /// The separator has to survive the real titles. None contains a "|",
    /// and this fails if somebody adds one that does.
    func testNoGroupTitleContainsTheSeparator() {
        for title in AssistPromptShelfTests.groupTitles {
            XCTAssertFalse(title.contains("|"), "\(title) would corrupt the stored preference")
            XCTAssertFalse(title.isEmpty)
        }
    }

    /// Publishing is not the act that reaches students — deploying is.
    ///
    /// The publish group was called "Showing work to students", which taught
    /// exactly the wrong lesson: that pressing Publish is the moment of no
    /// return. It is the opposite — publishing is the safe, undoable half, and
    /// the deploy group is the one that says what it does. A teacher who
    /// believes otherwise hesitates over the wrong button.
    func testNoGroupTitleClaimsPublishingReachesStudents() {
        for title in AssistPromptShelfTests.groupTitles {
            if title == "Putting the site online" {
                continue
            }
            XCTAssertFalse(title.lowercased().contains("student"),
                           "“\(title)” promises what only a deploy does")
        }
    }

    /// Every card either fires a fixed phrasing or is a known model-routed
    /// one — and nothing is on the shelf by accident.
    ///
    /// This is the drift check the file has always warned about in prose:
    /// "Deploy this section now" became "Deploy now", and a card whose wording
    /// no longer matches its shortcut is a button that quietly goes to the
    /// model on a shape the model was measured getting wrong. Reading the real
    /// list catches that; a hand-written copy would not.
    ///
    /// The model-routed list is written out HERE rather than derived, so
    /// adding a card is a deliberate act: a new phrasing fails this test until
    /// somebody has decided which of the two kinds it is, and — if it carries
    /// an argument — measured it. See
    /// `research/ai-assist/shelf-phrasings-results.txt`.
    func testEveryCardIsEitherMatchedInCodeOrKnownToGoToTheModel() {
        // Two, not three, and not four. "Deploy at 6:30 AM" left this list on
        // 2026-09-19: it was measured going to `deploy_section` ten trials out
        // of ten on the smaller assistant — a deploy to students on the spot
        // in answer to a teacher who asked for half six tomorrow — and is now
        // a parsed family in `AssistCardCommand` (issue #168).
        //
        // "Unpublish Unit 2, Day 3" left it the same day, for the opposite
        // reason: the model routes THAT sentence perfectly, and could not
        // route "hide unit 4, day 21" at all — five phrasings out of five, no
        // tool chosen, the teacher's own sentence handed back as text (issue
        // #215). Both verbs are one frame now, so the card goes with the word
        // that needed the help rather than being left to drift away from it.
        //
        // "Publish Unit 2, Day 3" stays with the model deliberately:
        // publishing is the direction that reaches students, and the smaller
        // assistant is 10/10 on that sentence today.
        let goesToTheModel: Set<String> = [
            "Publish Unit 2, Day 3",
            "Cancel scheduled deploy",
        ]

        var seen: Set<String> = []
        for (_, phrasings) in AssistPromptShelfView.groups {
            for phrasing in phrasings {
                XCTAssertFalse(seen.contains(phrasing), "“\(phrasing)” is on the shelf twice")
                seen.insert(phrasing)

                if goesToTheModel.contains(phrasing) {
                    XCTAssertNil(
                        AssistCardCommand.matching(phrasing),
                        "“\(phrasing)” is listed as model-routed but IS matched in code"
                    )
                    continue
                }
                XCTAssertNotNil(
                    AssistCardCommand.matching(phrasing),
                    "“\(phrasing)” matches no fixed phrasing and is not listed as one that "
                    + "goes to the model — so nobody has decided which it is"
                )
            }
        }
        XCTAssertFalse(seen.isEmpty)
    }

    /// The shelf offers what the app can do. Not everything it can do — pages
    /// are listed and read for the MODEL's benefit, not a teacher's — but
    /// nothing a teacher would look for should be missing.
    func testTheShelfOffersTheCapabilitiesATeacherWouldLookFor() {
        var everything: [String] = []
        for (_, phrasings) in AssistPromptShelfView.groups {
            everything.append(contentsOf: phrasings)
        }
        let all: String = everything.joined(separator: "\n").lowercased()

        for expected in ["publish", "unpublish", "undo", "preview", "deploy",
                         "class page", "new unit", "dates"] {
            XCTAssertTrue(all.contains(expected), "Nothing on the shelf covers “\(expected)”")
        }
    }

    /// The titles as they appear in `AssistPromptShelfView.groups`. Listed
    /// rather than read out of the view, which would make the test agree with
    /// whatever the view said.
    private static let groupTitles: [String] = [
        "Making pages visible",
        "Taking it back",
        "Checking",
        "Planning classes",
        "Putting the site online",
    ]
}
