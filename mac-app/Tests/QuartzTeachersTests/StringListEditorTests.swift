import XCTest
@testable import QuartzTeachers

/// The naming rules behind the folder/file list editors: ".md" is hidden
/// from teachers but preserved in the stored configuration.
final class StringListEditorTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testFileNamesGainMarkdownExtensionWhenAdded() {
        let normalized: String? = StringListEditorView.normalizedItemName("Field Trips", appendingMarkdownExtension: true)
        XCTAssertEqual(normalized, "Field Trips.md")
    }

    @MainActor
    func testTypedExtensionIsNotDoubled() {
        let normalized: String? = StringListEditorView.normalizedItemName("Key Links.md", appendingMarkdownExtension: true)
        XCTAssertEqual(normalized, "Key Links.md")
    }

    @MainActor
    func testFolderNamesAreStoredAsTyped() {
        let normalized: String? = StringListEditorView.normalizedItemName("  Projects ", appendingMarkdownExtension: false)
        XCTAssertEqual(normalized, "Projects")
    }

    @MainActor
    func testEmptyAndReservedNamesAreRejected() {
        XCTAssertNil(StringListEditorView.normalizedItemName("   ", appendingMarkdownExtension: false))
        XCTAssertNil(StringListEditorView.normalizedItemName("Media", appendingMarkdownExtension: false))
        // Case-insensitively: the filesystem is, so "media" typed here was
        // accepted and then collided with the folder Plantoir links in — two
        // names in the config for one directory on disk.
        for spelling in ["media", "MEDIA", "MeDiA", "  media  "] {
            XCTAssertNil(
                StringListEditorView.normalizedItemName(spelling, appendingMarkdownExtension: false),
                "\(spelling) is the Media folder under another spelling"
            )
        }
    }

    @MainActor
    func testDisplayNamesHideTheExtensionOnlyForFileLists() {
        XCTAssertEqual(
            StringListEditorView.displayName(for: "Learning Goals.md", hidingMarkdownExtension: true),
            "Learning Goals"
        )
        XCTAssertEqual(
            StringListEditorView.displayName(for: "Concepts", hidingMarkdownExtension: true),
            "Concepts"
        )
        XCTAssertEqual(
            StringListEditorView.displayName(for: "Learning Goals.md", hidingMarkdownExtension: false),
            "Learning Goals.md"
        )
    }
}
