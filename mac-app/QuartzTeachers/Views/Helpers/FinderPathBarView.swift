import AppKit
import SwiftUI

/// Shows a folder's location the way Finder's Path Bar does: each
/// ancestor folder with its real Finder icon and localized name,
/// separated by chevrons (Macintosh HD › Users › … › folder).
struct FinderPathBarView: View {

    // MARK: - Stored properties

    let folderURL: URL

    // MARK: - Computed properties

    /// Every ancestor path from the volume root down to the folder.
    var ancestorPaths: [String] {
        return FinderPathBarView.ancestorPaths(for: folderURL)
    }

    // MARK: - Body

    var body: some View {
        // Two forms of the same row, and the one that FITS is preferred.
        //
        // A scroll view fills whatever width it is given, so on its own it
        // takes the whole bar however short the path is — and with the
        // content anchored at the trailing edge (below), a short path ended
        // up at the far end of the window from the "Working folder:" label
        // that introduces it, with the width of a window in between.
        // Reported from a screenshot 2026-09-09; the folder picker had
        // already met it and wrapped its own copy in a `ViewThatFits`, so
        // the behaviour lives HERE now and both callers get it.
        ViewThatFits(in: .horizontal) {
            pathRow
            scrollingPathRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folder location: \(folderURL.path)")
        .accessibilityIdentifier("finderPathBar")
    }

    /// The row when the space is too narrow for it: scrollable, and showing
    /// its END rather than its start.
    ///
    /// The folder itself is the part a teacher is looking for, and the start
    /// ("Macintosh HD › Users › …") is the same for every folder they own.
    /// Seen first with an iCloud Drive folder, whose real path runs through
    /// ~/Library/Mobile Documents/com~apple~CloudDocs and was cut off before
    /// reaching the folder's own name.
    var scrollingPathRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            pathRow
        }
        .defaultScrollAnchor(.trailing)
    }

    /// The icons-names-chevrons row itself (also rendered directly by
    /// snapshot tests, where ScrollView cannot lay out offscreen).
    var pathRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(ancestorPaths.indices), id: \.self) { index in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 3) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: ancestorPaths[index]))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(FileManager.default.displayName(atPath: ancestorPaths[index]))
                        .font(.callout)
                }
                // Finder's own path bar opens a folder on a double-click and
                // reveals it from the context menu; this one does the same.
                // contentShape makes the gap between icon and name count too.
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    FinderPathBarView.openInFinder(ancestorPaths[index])
                }
                .contextMenu {
                    // Finder's own glyph, as Xcode uses for this action, and
                    // the same symbol wherever this appears in the app.
                    Button("Show in Finder", systemImage: "finder") {
                        FinderPathBarView.revealInFinder(ancestorPaths[index])
                    }
                    // The "opens elsewhere" arrow, as against revealing the
                    // folder inside its parent.
                    Button("Open Folder", systemImage: "arrow.up.forward.app") {
                        FinderPathBarView.openInFinder(ancestorPaths[index])
                    }
                }
                .help(ancestorPaths[index])
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Functions

    /// Opens a folder in Finder, as double-clicking it there would.
    static func openInFinder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Shows a folder inside its parent, selected — what "Show in Finder"
    /// means everywhere else in the app.
    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// "/Users/x/Desktop/Y" → ["/", "/Users", "/Users/x",
    /// "/Users/x/Desktop", "/Users/x/Desktop/Y"].
    static func ancestorPaths(for url: URL) -> [String] {
        let components: [String] = url.standardizedFileURL.pathComponents
        var result: [String] = []
        var currentPath: String = ""
        for component in components {
            if component == "/" {
                currentPath = "/"
            } else if currentPath == "/" {
                currentPath = "/" + component
            } else {
                currentPath = currentPath + "/" + component
            }
            result.append(currentPath)
        }
        return result
    }
}
