import Foundation

/// The plan as rows, for the Section menu's plan sheet (#524).
///
/// Built from the SAME `AssistPublishPlan`, in the same plan-twin call, as
/// the card's `describe()` — by `AssistPublishPlan.tabulated` — and never
/// parsed back out of the card's text: titles hold quotes and commas, and a
/// parse would be a second reader of a format that changes.
///
/// Every page the plan is about gets a row, not only the ones that change:
/// the pages an unpublish keeps, the classes a publish left hidden, the pages
/// whose settings have no room for a key, and the pages already the way they
/// were asked to be. The card stopped at fifteen ("…and N more"); the table
/// does not stop.
///
/// `nonisolated`: a plain value carried on `AssistToolOutcome`.
nonisolated struct AssistPlanTable: Sendable, Equatable {

    // MARK: - Types

    /// What happens to one page, for a test to ask about without reading
    /// the cell's words.
    enum Change: Sendable, Equatable {
        case willBecomeVisible
        case willBecomeHidden
        case staysVisible
        case staysHidden
        case staysExactlyAsItIs
        case alreadyVisible
        case alreadyHidden
    }

    /// One page.
    struct Row: Identifiable, Sendable, Equatable {

        // MARK: - Stored properties

        /// Where the page comes in the plan: the table's first order, and
        /// its identity.
        let position: Int

        /// What the teacher sees the page called, without quotation marks:
        /// a cell, not a sentence.
        let title: String

        /// Where it is, as the sheet's choosing rows say it
        /// (`StartOfYearPageNaming.folder`) — what tells two pages with one
        /// title apart.
        let folder: String

        let change: Change

        /// The cell: the same `AssistWording` piece the card's line is made of.
        let whatChanges: String

        // MARK: - Computed properties

        var id: Int {
            return position
        }
    }

    // MARK: - Stored properties

    /// The line above the table (`AssistWording.menuPlanSummary`).
    let summary: String

    let rows: [Row]

    /// The card's sentences that are not one page and one change — pages
    /// left alone and why, linked classes left hidden, a date move with no
    /// page of its own, names that fit no page — word for word as the card
    /// says them.
    let notes: [String]
}
