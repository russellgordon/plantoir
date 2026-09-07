import XCTest
@testable import QuartzTeachers

/// Pointing qualified links at a folder's new name — and, just as important,
/// leaving alone the links that need nothing.
@MainActor
final class FolderPathRewriterTests: XCTestCase {

    // MARK: - What must change

    func testAQualifiedWikiLinkFollowsTheFolder() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting("See [[Tasks/Quiz 1]] today.", folderNamed: "Tasks", to: "Assessments"),
            "See [[Assessments/Quiz 1]] today."
        )
    }

    func testATransclusionFollowsTheFolder() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting("![[Tasks/diagram.png]]", folderNamed: "Tasks", to: "Assessments"),
            "![[Assessments/diagram.png]]"
        )
    }

    /// The alias and the heading are the teacher's own words, and a rewriter
    /// that touched them would quietly edit their prose.
    func testAnAliasAndAHeadingAreLeftAlone() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting(
                "[[Tasks/Quiz 1#Marking|the Tasks quiz]]", folderNamed: "Tasks", to: "Assessments"
            ),
            "[[Assessments/Quiz 1#Marking|the Tasks quiz]]"
        )
    }

    /// Obsidian writes a full vault path when a name is ambiguous, so the
    /// folder is not always the first segment.
    func testAFolderDeepInAPathIsFound() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting(
                "[[ICS3U/section1/Tasks/Quiz 1]]", folderNamed: "Tasks", to: "Assessments"
            ),
            "[[ICS3U/section1/Assessments/Quiz 1]]"
        )
    }

    func testAMarkdownLinkFollowsTheFolder() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting(
                "[the quiz](Tasks/Quiz 1.md)", folderNamed: "Tasks", to: "Assessments"
            ),
            "[the quiz](Assessments/Quiz 1.md)"
        )
    }

    /// A percent-encoded segment must come back percent-encoded, or the link
    /// stops resolving — which would be a rename that broke the very links it
    /// set out to keep working.
    ///
    /// This is the case the ONE encoding test used to be, and it starts from
    /// an already-encoded segment, which is exactly why it could not see the
    /// defect the contract cases below catch.
    func testAPercentEncodedSegmentStaysEncoded() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting(
                "[the quiz](Extra%20Tasks/Quiz%201.md)", folderNamed: "Extra Tasks", to: "Extra Assessments"
            ),
            "[the quiz](Extra%20Assessments/Quiz%201.md)"
        )
    }

    /// Obsidian resolves names without regard to case, so a link written
    /// `tasks/` points at the `Tasks` folder and has to follow it.
    func testMatchingIgnoresCase() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting("[[tasks/Quiz 1]]", folderNamed: "Tasks", to: "Assessments"),
            "[[Assessments/Quiz 1]]"
        )
    }

    // MARK: - What must NOT change

    /// The common case, and the reason a folder rename is far less dangerous
    /// than a page rename: Obsidian resolves a bare page name by searching the
    /// vault, so moving the folder leaves the link working.
    func testABarePageLinkIsUntouched() {
        let text: String = "See [[Quiz 1]] today."
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Assessments"), text)
    }

    /// The last segment is the page, so a page that happens to be CALLED
    /// `Tasks` survives a rename of the folder.
    func testAPageNamedAfterTheFolderIsUntouched() {
        let text: String = "[[Handbook/Tasks]]"
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Assessments"), text)
    }

    /// A segment must be the WHOLE name. Rewriting on a substring would rename
    /// a folder the teacher never touched.
    func testAFolderWhoseNameMerelyContainsTheOldOneIsUntouched() {
        let text: String = "[[Extra Tasks/Quiz 1]] and [[Tasks Archive/Old quiz]]"
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Assessments"), text)
    }

    func testPlainProseMentioningTheFolderIsUntouched() {
        let text: String = "Everything in Tasks/ counts for marks."
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Assessments"), text)
    }

    /// Found by adversarial review, not by use, and it was a real bug: the
    /// segment walk is blind to what a path MEANS, so a folder called `Tasks`,
    /// `Resources` or `Notes` used to repoint every external link whose URL
    /// happened to carry that segment.
    func testAWebAddressIsNeverRewritten() {
        let text: String = "See [the handout](https://example.com/Tasks/handout.pdf) and "
                         + "[more](http://school.example/Tasks/x)."
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Assessments"), text)
        XCTAssertEqual(FolderPathRewriter.countReferences(to: "Tasks", in: text), 0)
    }

    func testAnAbsolutePathOnThisMachineIsNeverRewritten() {
        let text: String = "[the file](/Users/teacher/Tasks/notes.md)"
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Assessments"), text)
    }

    /// Tested against the SHAPE of a scheme rather than a list of schemes: the
    /// list is open, and a missed one silently rewrites somebody's link.
    func testOtherSchemesAreLeftAloneToo() {
        let text: String = "[vault](obsidian://open?file=Tasks/x) [f](file:///Tasks/y.md)"
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Assessments"), text)
    }

    /// The guard must not overreach: a relative path is still rewritten, and a
    /// course whose own folders contain a colon is impossible (the rename sheet
    /// refuses one).
    func testARelativePathIsStillRewritten() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting("[q](./Tasks/Quiz 1.md)", folderNamed: "Tasks", to: "Assessments"),
            "[q](./Assessments/Quiz 1.md)"
        )
    }

    func testRenamingToTheSameNameChangesNothing() {
        let text: String = "[[Tasks/Quiz 1]]"
        XCTAssertEqual(FolderPathRewriter.rewriting(text, folderNamed: "Tasks", to: "Tasks"), text)
    }

    // MARK: - How the new name is spelled

    /// The cases both apps run, read from the contract rather than retyped.
    ///
    /// `FolderPathRewriter` used to decide whether to percent-encode the new
    /// name from whether the OLD segment was encoded, which is wrong for a
    /// Markdown link: a destination ends at the first space, so renaming
    /// `Tasks` to `All Tasks` produced `[q](All Tasks/Quiz%201.md)` and broke
    /// every Markdown-style link into the folder. Nothing here could see it,
    /// because the one encoding test above starts from a segment that was
    /// already encoded.
    func testTheNewNameIsSpelledTheWayTheContractSays() throws {
        let rules: [String: Any] = try FolderPathRewriterTests.linkRewritingRules()
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty, "The contract carries no link-rewriting cases")

        for testCase in cases {
            let given: String = try XCTUnwrap(testCase["given"] as? String)
            let oldName: String = try XCTUnwrap(testCase["oldName"] as? String)
            let newName: String = try XCTUnwrap(testCase["newName"] as? String)
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            let why: String = testCase["why"] as? String ?? ""
            XCTAssertEqual(
                FolderPathRewriter.rewriting(given, folderNamed: oldName, to: newName),
                expected,
                "Renaming “\(oldName)” to “\(newName)” in \(given) — \(why)"
            )
        }
    }

    /// The escaping set is measured against Quartz rather than chosen, so the
    /// contract writes it down and this checks the code agrees with it: a
    /// character the contract says survives untouched must come through a
    /// rename untouched.
    ///
    /// The one that matters is `&`. Quartz resolves an internal link with
    /// JavaScript's `decodeURI`, which leaves `%26` alone, and then slugs `&`
    /// to `-and-` and `%` to `-percent` — so an over-encoded `Tasks & Quizzes`
    /// 404s for students while looking perfectly healthy in Obsidian.
    func testEveryCharacterTheContractLeavesAloneSurvivesARename() throws {
        let rules: [String: Any] = try FolderPathRewriterTests.linkRewritingRules()
        let set: [String: Any] = try XCTUnwrap(rules["escapingSet"] as? [String: Any])
        let untouched: String = try XCTUnwrap(set["leaveUnescaped"] as? String)

        for character in untouched {
            // A space forces the escaping to run at all; the character under
            // test then has to come out the other side as itself.
            let newName: String = "New " + String(character)
            let rewritten: String = FolderPathRewriter.rewriting(
                "[q](Tasks/Quiz.md)", folderNamed: "Tasks", to: newName
            )
            XCTAssertEqual(
                rewritten, "[q](New%20" + String(character) + "/Quiz.md)",
                "The contract says “\(character)” is left as it stands"
            )
        }
    }

    /// Anything the contract does NOT list is percent-encoded, and the point
    /// of encoding it is that Quartz gets the real name back.
    func testACharacterOutsideTheSetIsEncoded() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting("[q](Tasks/Quiz.md)", folderNamed: "Tasks", to: "Café Notes"),
            "[q](Caf%C3%A9%20Notes/Quiz.md)"
        )
        XCTAssertEqual(
            FolderPathRewriter.rewriting("[q](Tasks/Quiz.md)", folderNamed: "Tasks", to: "Unit [2]"),
            "[q](Unit%20%5B2%5D/Quiz.md)"
        )
    }

    /// A wikilink keeps the plain spelling whatever the name contains, which
    /// is the mirror-image mistake this rule has to avoid making.
    func testAWikiLinkKeepsAPlainNameWhateverItContains() {
        XCTAssertEqual(
            FolderPathRewriter.rewriting("[[Tasks/Quiz 1]]", folderNamed: "Tasks", to: "Work(new)"),
            "[[Work(new)/Quiz 1]]"
        )
    }

    /// Rewriting the same page twice must produce the same text, because a
    /// rename interrupted between the move and the settings write is resumed
    /// and re-runs the relinking pass over pages it may already have changed.
    func testRelinkingTwiceChangesNothingTheSecondTime() {
        let once: String = FolderPathRewriter.rewriting(
            "[q](Tasks/Quiz.md) and [[Tasks/Quiz 1]]", folderNamed: "Tasks", to: "All Tasks"
        )
        XCTAssertEqual(once, "[q](All%20Tasks/Quiz.md) and [[All Tasks/Quiz 1]]")
        XCTAssertEqual(
            FolderPathRewriter.rewriting(once, folderNamed: "Tasks", to: "All Tasks"), once
        )
    }

    // MARK: - Counting

    func testCountingFindsOnlyQualifiedLinks() {
        let text: String = "[[Tasks/Quiz 1]] [[Quiz 2]] [the third](Tasks/Quiz 3.md) [[Handbook/Tasks]]"
        XCTAssertEqual(FolderPathRewriter.countReferences(to: "Tasks", in: text), 2)
    }

    func testCountingIsZeroWhenNothingPointsIn() {
        XCTAssertEqual(
            FolderPathRewriter.countReferences(to: "Tasks", in: "[[Quiz 1]] and [[Concepts/Loops]]"), 0
        )
    }

    // MARK: - Functions

    /// The contract's rules for spelling a new name inside a link, read from
    /// the file both apps run rather than copied into Swift.
    private static func linkRewritingRules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let specialNames: [String: Any] = try XCTUnwrap(all["specialNames"] as? [String: Any])
        let rename: [String: Any] = try XCTUnwrap(specialNames["renameFolder"] as? [String: Any])
        return try XCTUnwrap(
            rename["linkRewriting"] as? [String: Any],
            "No specialNames.renameFolder.linkRewriting in shared-rules.json"
        )
    }
}
