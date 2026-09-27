import XCTest
import AppKit
@testable import QuartzTeachers

/// Menu symbols have to exist, or the item silently renders without one.
final class MenuSymbolTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testEverySymbolUsedInAMenuExists() {
        let symbols: [String] = [
            "finder",                 // Show in Finder
            "square.and.pencil", // Open in Obsidian
            "arrow.up.forward.app",   // Open Folder
            "terminal",               // New Terminal at Folder
            "arrow.uturn.backward",   // Restore
            "doc.badge.plus",         // Add Section
            "plus",                   // Add course
            "minus",                  // Remove selected
            "archivebox",             // Archived
            "books.vertical",         // A course
            "doc.richtext",           // A section
            "moon.zzz",               // Get Ready for the Start of the Year (#96)
        ]
        for name in symbols {
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "\(name) is not a symbol this system knows — the menu item would show no icon at all"
            )
        }
    }
}
