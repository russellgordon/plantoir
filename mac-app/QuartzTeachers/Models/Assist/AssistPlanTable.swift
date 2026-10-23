import Foundation

/// The plan as rows, for the Section menu's plan sheet (#524).
///
/// Built from the SAME `AssistPublishPlan`, in the same plan-twin call, as
/// the card's `describe()` — by `AssistPublishPlan.tabulated` — and never
/// parsed back out of the card's text: titles hold quotes and commas, and a
/// parse would be a second reader of a format that changes.
///
/// Every page the plan is about gets a row, not only the ones that change:
/// the pages an unpublish keeps, the classes a publish left as they are, the pages
/// whose settings have no room for a key, and the pages already the way they
/// were asked to be. The card stopped at fifteen ("…and N more"); the table
/// does not stop. Since #622 the sheet draws `rowsToRead` and folds
/// `rowsAlreadyRight` behind a checkbox (#654); the rows themselves, and the plan
/// they come from, are unchanged.
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
        case staysAsItIs
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
    /// left alone and why, linked classes left as they are, a date move with no
    /// page of its own, names that fit no page — word for word as the card
    /// says them.
    let notes: [String]

    // MARK: - Computed properties

    /// The rows a teacher reads before Go (#622): every page that changes,
    /// and every page that stays for a reason — the pages an unpublish
    /// keeps, the linked classes left as they are, the pages with no room
    /// for a key. Only the pages already the way they were asked to be are
    /// left out, since they say nothing new and grow all year.
    var rowsToRead: [Row] {
        var toRead: [Row] = []
        for row in rows where !AssistPlanTable.isAlreadyRight(row.change) {
            toRead.append(row)
        }
        return toRead
    }

    /// The pages already visible (or already hidden): what the sheet folds
    /// away behind a checkbox, and what the summary counts as "already".
    var rowsAlreadyRight: [Row] {
        var already: [Row] = []
        for row in rows where AssistPlanTable.isAlreadyRight(row.change) {
            already.append(row)
        }
        return already
    }

    // MARK: - Functions

    static func isAlreadyRight(_ change: Change) -> Bool {
        switch change {
        case .alreadyVisible, .alreadyHidden:
            return true
        default:
            return false
        }
    }
}
