import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The synced-folder notice must never demand more height than the window
/// has — and the first version did. A text kept at its vertical size inside
/// an `HStack` wrapped to a word per line, the notice became hundreds of
/// points tall, and the window's path bar and the sidebar's filter bar slid
/// off the bottom of the screen: a responsive window with its bottom band
/// blank, at every window height. Found by driving the real app; pinned
/// here so it is found by the suite next time.
final class CloudSyncNoticeLayoutTests: XCTestCase {

    // MARK: - Functions

    /// Proposes a window-sized space to the view and reports the height
    /// its content claims IN THAT WIDTH.
    ///
    /// Not `fittingSize`, which the progress-view tests use: that asks for
    /// the ideal size with no width proposed, so a sentence never wraps and
    /// the fault this file exists to catch — text wrapping to a word per
    /// line — cannot show up in it. Checked by putting the faulty layout
    /// back and watching this fail.
    @MainActor
    func measuredHeight(of view: some View, width: CGFloat, height: CGFloat) -> CGFloat {
        let controller: NSHostingController = NSHostingController(rootView: AnyView(view))
        return controller.sizeThatFits(in: NSSize(width: width, height: height)).height
    }

    @MainActor
    func makeNotice(isShowingDetails: Bool) -> some View {
        let folder: CloudSyncedFolder = CloudSyncedFolder(
            serviceName: "iCloud Drive",
            folderPath: "/Users/teacher/Library/Mobile Documents/com~apple~CloudDocs/Course Notes"
        )
        return CloudSyncNoticeContentView(
            syncedFolder: folder,
            isShowingDetails: .constant(isShowingDetails),
            dismiss: {}
        )
    }

    /// The notice in the place it actually sits: under a flexible detail
    /// area and above the path bar, in a window of ordinary size. The
    /// whole column must fit the window, or the bar below it is lost.
    @MainActor
    func testTheWindowColumnStillFitsWithTheNoticeShowing() {
        let column: some View = VStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            makeNotice(isShowingDetails: false)
            Text("Working folder: ~/Course Notes")
                .frame(height: 28)
        }
        let measured: CGFloat = measuredHeight(of: column, width: 1400, height: 700)
        XCTAssertLessThanOrEqual(measured, 701, "The column claimed \(measured) points in a 700-point window — the path bar under the notice would be off screen")
    }

    /// The fault itself. A container measures a child's MINIMUM size by
    /// proposing it next to nothing — a narrow width and no height. A text
    /// kept at its vertical size ignores the height it is offered and
    /// answers with every line it would need at that width: wrapped to a
    /// word per line, that is well over a thousand points, which the split
    /// view then takes as the column's minimum and grows the window's
    /// content past the window. A text WITHOUT that modifier respects the
    /// proposal and stays small. Checked by putting the modifier back and
    /// watching this fail: 1,548 points, and the same 1,548 whether 700
    /// points or nothing at all is proposed — the modifier ignores the
    /// height either way, which is the whole fault.
    @MainActor
    func testTheCollapsedNoticeDoesNotBalloonWhenSqueezed() {
        let measured: CGFloat = measuredHeight(of: makeNotice(isShowingDetails: false), width: 120, height: 0)
        XCTAssertLessThanOrEqual(measured, 160, "Squeezed to 120 points wide with no height on offer, the collapsed notice claimed \(measured) points — its text is ignoring the proposal, and the window's path bar will be pushed off screen")
    }

    /// Collapsed, the notice is two lines of text and a row of buttons.
    @MainActor
    func testTheCollapsedNoticeIsAStrip() {
        let measured: CGFloat = measuredHeight(of: makeNotice(isShowingDetails: false), width: 1400, height: 700)
        XCTAssertLessThanOrEqual(measured, 90, "Collapsed, the notice claimed \(measured) points")
    }

    /// Opened out, five sentences on a wide window are five or six lines.
    @MainActor
    func testTheExpandedNoticeFitsAWideWindow() {
        let measured: CGFloat = measuredHeight(of: makeNotice(isShowingDetails: true), width: 1400, height: 700)
        XCTAssertLessThanOrEqual(measured, 260, "Expanded, the notice claimed \(measured) points at 1400 wide")
    }

    /// And on a narrow window the sentences wrap, but to lines — never to
    /// a word each.
    @MainActor
    func testTheExpandedNoticeWrapsSensiblyWhenNarrow() {
        let measured: CGFloat = measuredHeight(of: makeNotice(isShowingDetails: true), width: 640, height: 700)
        XCTAssertLessThanOrEqual(measured, 420, "Expanded, the notice claimed \(measured) points at 640 wide")
    }
}
