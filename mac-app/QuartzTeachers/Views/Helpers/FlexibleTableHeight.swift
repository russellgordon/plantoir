import SwiftUI

extension View {

    // MARK: - Functions

    /// A table in a resizable sheet (#621): `height` to open with — the
    /// height it had when the sheet could not be resized — which is also the
    /// least it is ever given, and every point of height the teacher adds
    /// after that, ahead of the words around it. So a sheet opens exactly as
    /// it did, and dragging its bottom edge shows more rows rather than more
    /// empty space under the buttons.
    ///
    /// The minimum is the half that matters. MEASURED (#621): without
    /// `minHeight` the sheet still opens at the same size, but can be made
    /// smaller than it opens (the plan of twenty-one pages to 136 pt where it
    /// opens at 454), which
    /// `PageTablesSheetTests.testEachSheetIsResizableAndOpensAtItsSmallestSize`
    /// catches; without `idealHeight` nothing measurable changes, and it is
    /// kept so the opening height is said in so many words.
    func flexibleTableHeight(_ height: CGFloat) -> some View {
        return self
            .frame(minHeight: height, idealHeight: height, maxHeight: .infinity)
            .layoutPriority(1)
    }
}
