import XCTest
@testable import QuartzTeachers

/// The copy's reader of pictures and files, for #97's third link style: a
/// Markdown destination in angle brackets, `![](<one pic.png>)` (#325).
///
/// `copyingAPageBetweenCourses.cases` pins what is carried; its `expect`
/// does not carry page text, so what the rewritten page SAYS is pinned here.
final class PageReferencesTests: XCTestCase {

    // MARK: - Functions

    private func renaming(_ oldName: String, to newName: String) -> [String: ExactName] {
        return [ExactName(bytes: Array(oldName.utf8)).comparisonKey: ExactName(bytes: Array(newName.utf8))]
    }

    /// Read ONCE, as the whole name. Before #325 the plain pattern read `<one`
    /// here, which named nothing; without its `(?!<)` it would read the link
    /// a second time alongside the angle-bracket pattern.
    func testAnAngleBracketedDestinationIsReadOnceAsTheWholeName() {
        let references: [PageReferences.Reference] = PageReferences.references(in: "![](<one pic.png>)\n")
        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.kind, .angleBracketed)
        XCTAssertEqual(references.first?.lastComponent, "one pic.png")
    }

    /// The new name goes in PLAIN inside the brackets, #97's rule, and the
    /// brackets stay.
    func testARenameWritesTheNamePlainInsideTheBrackets() {
        let renamed: String = PageReferences.rewriting(
            "![](<one pic.png>) and ![](<Media/one pic.png>)\n",
            renaming: renaming("one pic.png", to: "one pic (from ICS4U-2025).png")
        )
        XCTAssertEqual(
            renamed,
            "![](<one pic (from ICS4U-2025).png>) and ![](<Media/one pic (from ICS4U-2025).png>)\n"
        )
    }

    /// A name holding `>` would end the brackets, so it goes in encoded.
    func testANameHoldingAClosingBracketIsEncoded() {
        let renamed: String = PageReferences.rewriting(
            "![](<a.png>)", renaming: renaming("a.png", to: "a>b.png")
        )
        XCTAssertEqual(renamed, "![](<a%3Eb.png>)")
    }

    /// The site's reader resolves `<a%20b.png>` and `<a b.png>` to the same
    /// address, so both name `a b.png`; an old segment that arrived encoded
    /// is written back encoded.
    func testAnEncodedNameInsideBracketsIsDecoded() {
        let references: [PageReferences.Reference] = PageReferences.references(in: "![](<a%20b.png>)")
        XCTAssertEqual(references.first?.lastComponent, "a b.png")
        let renamed: String = PageReferences.rewriting(
            "![](<a%20b.png>)", renaming: renaming("a b.png", to: "c d.png")
        )
        XCTAssertEqual(renamed, "![](<c%20d.png>)")
    }

    /// An unterminated `](<one pic.png` is plain text to every Markdown
    /// reader, so it names nothing.
    func testAnUnterminatedDestinationNamesNothing() {
        XCTAssertEqual(PageReferences.references(in: "![](<one pic.png\n").count, 0)
    }

    /// The plain shape still reads and still re-encodes as it did.
    func testThePlainShapeIsUnchanged() {
        let references: [PageReferences.Reference] = PageReferences.references(in: "[x](Media/a%20b.pdf)")
        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.kind, .encoded)
        XCTAssertEqual(references.first?.lastComponent, "a b.pdf")
    }
}
