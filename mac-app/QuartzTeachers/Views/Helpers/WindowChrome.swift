import SwiftUI

/// Sizes shared by the window's edges, so the sidebar's footer and the
/// path bar below the content are the same height and their dividers line
/// up across the window.
enum WindowChrome {

    // MARK: - Stored properties

    /// How tall a footer's contents are at the standard text size — enough
    /// for a 24pt button with room around it.
    static let footerHeight: CGFloat = 34

    /// The sidebar's footer stops short of the window's bottom edge, because
    /// the split view insets the sidebar; the path bar opposite it sits
    /// flush. The path bar therefore has to be this much taller for the two
    /// rules to meet on one line.
    ///
    /// Measured from screenshots at the standard text size, by finding the
    /// darkest row under each side and closing the gap half a point at a
    /// time — half a point being one device pixel on a 2x display.
    static let sidebarBottomInset: CGFloat = 8

    /// The height of the path bar strip, divider to window edge.
    static let pathBarHeight: CGFloat = footerHeight + sidebarBottomInset

    /// The main window's smallest size (`QuartzTeachersApp`).
    static let minimumWindowWidth: CGFloat = 900
    static let minimumWindowHeight: CGFloat = 600

    /// The sidebar's narrowest, usual and WIDEST widths.
    ///
    /// **The maximum is #213's fix, and it is structural.** A folder
    /// publish's note under a scheduled publish's notice, with "Show
    /// details" open, keeps both its lines at every section column of about
    /// 560 points or more — measured on 2026-09-26, 30 of 30 at the window's
    /// minimum with the sidebar at its ideal or minimum width. It lost a line
    /// only in a column of 400 or less, and with no maximum the sidebar could
    /// be dragged to 700 in a 900-wide window, leaving 200. Capped at 320,
    /// the same drag stops at 328 and leaves 572 (measured with
    /// `window-minimum-probe.swift`). The cost, said plainly: a teacher who
    /// liked a very wide sidebar gets 320 at most; course codes and section
    /// names fit, and long names truncate as they already do at 220.
    ///
    /// REJECTED: letting the console give up its room instead (no minimum
    /// height, lowest layout priority) — measured WORSE at a 560 column (the
    /// note kept its lines 15 times in 30); a smaller console floor, which
    /// only moves the corner; `.fixedSize` on the note, which is #211's
    /// blank window; and a larger window minimum, which costs every teacher
    /// on a small display to fix a corner only a dragged sidebar reached.
    static let sidebarMinimumWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaximumWidth: CGFloat = 320

    /// What the split view takes beside the sidebar that is neither column —
    /// its divider and the sidebar's inset. Measured: a 900-wide window with
    /// the sidebar dragged to its 320 maximum leaves a 572-wide column.
    static let splitViewGutter: CGFloat = 8

    /// The narrowest section column the window allows: its minimum width,
    /// less the widest sidebar and the gutter.
    static var narrowestDetailColumn: CGFloat {
        return minimumWindowWidth - sidebarMaximumWidth - splitViewGutter
    }
}

extension View {

    // MARK: - Functions

    /// The sidebar column's widths — ONE modifier, so the window and the test
    /// that proves its maximum is enforced apply the same thing (#213).
    func plantoirSidebarColumnWidth() -> some View {
        return navigationSplitViewColumnWidth(
            min: WindowChrome.sidebarMinimumWidth,
            ideal: WindowChrome.sidebarIdealWidth,
            max: WindowChrome.sidebarMaximumWidth
        )
    }
}
