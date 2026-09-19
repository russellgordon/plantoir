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
        // Three forms of the same row, and the FIRST that fits is used.
        //
        // Finder's own answer to a path too long for the space is not an
        // ellipsis and not a scroll: it drops the ancestors' NAMES and keeps
        // their icons and chevrons, so the depth of the path and the folder's
        // own name both survive. Measured against the real Finder at five
        // window widths on 2026-09-09 — it shrinks the middle names first,
        // then goes icon-only from the left, keeping the volume and the last
        // crumb or two named longest.
        //
        // Two things it does are deliberately NOT copied. The intermediate
        // step, where middle names shrink before they vanish, needs
        // per-crumb width negotiation for a state a teacher passes through
        // rather than sits in. And at its narrowest Finder clips the TAIL,
        // losing the folder's own name — which is the exact defect fixed
        // here on 2026-09-05 (an iCloud path cut off before the one crumb
        // that differs between a teacher's folders). So the last resort is
        // this bar's own rule instead: scroll, anchored at the end.
        ViewThatFits(in: .horizontal) {
            pathRow
            collapsedRow
            scrollingCollapsedRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folder location: \(folderURL.path)")
        .accessibilityIdentifier("finderPathBar")
    }

    /// Every crumb named — what a teacher sees whenever there is room.
    ///
    /// Also rendered directly by snapshot tests, where `ScrollView` cannot
    /// lay out offscreen.
    var pathRow: some View {
        return row(namingEveryCrumb: true)
    }

    /// The ancestors as icons and chevrons, with only the folder itself
    /// named: Finder's answer, and no ellipsis anywhere.
    ///
    /// A hidden name is not a lost one — every crumb keeps its tooltip, its
    /// double-click and its context menu, so hovering still says which folder
    /// an icon is.
    var collapsedRow: some View {
        return row(namingEveryCrumb: false)
    }

    /// The last resort, when even icons and chevrons do not fit: the
    /// collapsed row, scrollable, showing its END rather than its start.
    ///
    /// The folder itself is the part a teacher is looking for, and the start
    /// ("Macintosh HD › Users › …") is the same for every folder they own.
    /// Seen first with an iCloud Drive folder, whose real path runs through
    /// ~/Library/Mobile Documents/com~apple~CloudDocs and was cut off before
    /// reaching the folder's own name.
    var scrollingCollapsedRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            collapsedRow
        }
        .defaultScrollAnchor(.trailing)
    }

    /// The icons-chevrons-names row, drawn with every crumb named or with
    /// only the last one named.
    func row(namingEveryCrumb: Bool) -> some View {
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
                    if namingEveryCrumb || index == ancestorPaths.count - 1 {
                        Text(FileManager.default.displayName(atPath: ancestorPaths[index]))
                            .font(.callout)
                    }
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
