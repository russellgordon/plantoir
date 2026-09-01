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
}
