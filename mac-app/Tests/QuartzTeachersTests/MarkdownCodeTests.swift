import XCTest
@testable import QuartzTeachers

/// Where a page's code is, and that nothing written inside it is read or
/// rewritten as a link (#313). The contract's cases are walked through both
/// section-graph readers by `SharedRulesContractTests`; this file holds what
/// they cannot show: the offsets line up with `NSRegularExpression`'s on text
/// that is not ASCII, a count agrees with its rewrite, and the copy's own
/// reader skips code in all three of its shapes.
final class MarkdownCodeTests: XCTestCase {

    // MARK: - Functions

    func testAnEmptyPageAndAPageThatIsOneFence() {
        XCTAssertEqual(MarkdownCode.ranges(in: ""), [])
        XCTAssertEqual(MarkdownCode.ranges(in: "```"), [NSRange(location: 0, length: 3)])
        XCTAssertEqual(
            MarkdownCode.ranges(in: "```\n[[A]]\n```\n"),
            [NSRange(location: 0, length: 14)]
        )
    }

    /// The mask is in UTF-16 code units, the unit `NSRegularExpression`
    /// reports. Computed in `Character`s or scalars, an emoji or a decomposed
    /// accent before the span would shift it, and a link would read as code
    /// or code as a link. The contract's cases are all ASCII, so they could
    /// not catch this.
    func testOffsetsLineUpAfterAnEmojiAndADecomposedAccent() {
        let text: String = "Cafe\u{301} 🙂 `[[Code Example]]` then [[Real Page]]."
        XCTAssertEqual(AssistSectionGraph.linksAsWritten(in: text), ["Real Page"])
        let ranges: [NSRange] = MarkdownCode.ranges(in: text)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual((text as NSString).substring(with: ranges[0]), "`[[Code Example]]`")
    }

    /// A page written on Windows: `"\r\n"` is ONE `Character` in Swift.
    func testWindowsLineEndingsEndLines() {
        let text: String = "```\r\n[[Fenced]]\r\n```\r\n\r\nSee [[Real Page]].\r\n"
        XCTAssertEqual(AssistSectionGraph.linksAsWritten(in: text), ["Real Page"])
    }

    /// The number a rename plan reports is exactly what the rewrite moves,
    /// on every contract case, and a rewrite never touches code.
    @MainActor
    func testACountAgreesWithItsRewriteOnEveryContractCase() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("readingALink")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        for oneCase in cases {
            let name: String = try XCTUnwrap(oneCase["name"] as? String)
            let text: String = try XCTUnwrap(oneCase["text"] as? String, name)

            // Every name the raw pattern finds, code included.
            var everyName: [String] = []
            let expression: NSRegularExpression = try XCTUnwrap(WikiLinkRewriter.expression)
            let whole: NSRange = NSRange(location: 0, length: text.utf16.count)
            for match in expression.matches(in: text, range: whole) {
                let target: String = (text as NSString).substring(with: match.range(at: 2))
                everyName.append(target.trimmingCharacters(in: .whitespaces))
            }
            let expected: [String] = try XCTUnwrap(oneCase["expect"] as? [String], name)
            for written in expected {
                everyName.append(written)
            }
            var renames: [String: String] = [:]
            for oneName in everyName {
                renames[oneName] = "RENAMED"
            }

            let counted: Int = WikiLinkRewriter.countLinks(to: everyName, in: text)
            let rewritten: String = WikiLinkRewriter.rewriting(text, renamedPages: renames)
            XCTAssertEqual(
                rewritten.components(separatedBy: "RENAMED").count - 1, counted,
                "\(name): the count and the rewrite disagree"
            )
            XCTAssertEqual(counted, WikiLinkRewriter.linkMatches(in: text).count, name)
            for range in MarkdownCode.ranges(in: text) {
                let code: String = (text as NSString).substring(with: range)
                XCTAssertTrue(rewritten.contains(code), "\(name): code was rewritten: \(code)")
            }
        }
    }

    /// The copy's reader skips code in all three of its shapes — not only
    /// wikilinks — and inline code as well as fences.
    func testThePageReferencesInsideCodeAreNotRead() {
        let text: String = "Use `<img src=\"Media/a.png\">`, `[x](Media/c.png)` or `![[d.png]]`.\n"
            + "> ```\n> ![[e.png]]\n> ```\n"
            + "![[b.png]]\n"
        var names: [String] = []
        for reference in PageReferences.references(in: text) {
            names.append(reference.lastComponent)
        }
        XCTAssertEqual(names, ["b.png"])
    }

    /// A rewrite of the copy's references leaves a page written on Windows
    /// byte for byte, apart from the one reference renamed.
    func testThePageReferencesRewriteKeepsWindowsLineEndings() {
        let text: String = "```\r\n![[a.png]]\r\n```\r\n![[a.png]]\r\n"
        let renamed: String = PageReferences.rewriting(
            text, renaming: [ExactName(bytes: Array("a.png".utf8)).comparisonKey: ExactName(bytes: Array("b.png".utf8))]
        )
        XCTAssertEqual(renamed, "```\r\n![[a.png]]\r\n```\r\n![[b.png]]\r\n")
    }

    /// A page embedded only as an example is not brought along by a copy.
    func testAnEmbedShownInsideCodeBringsNothing() {
        let text: String = "Embed one with `![[Note]]`.\n\n```\n![[Other]]\n```\n![[Third]]\n"
        XCTAssertEqual(CoursePageCopySource.pagesEmbeddedIn(text), ["third"])
    }
}
