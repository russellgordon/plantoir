import Foundation

/// Which of the two section menus each section item is in, and in what
/// order and groups (#990, Russell's ruling of 2026-11-20: grouping A).
///
/// **Section** holds the website jobs: looking at the site, choosing which
/// pages students see, and sending it. **Classes**, after it in the menu bar,
/// holds the class calendar: adding a class, its dates, and the start of a
/// year. The HIG's first answer to a long menu is "consider dividing it into
/// separate menus" (Menus), and the menu bar mirrors the app's hierarchy
/// (The menu bar: "mailboxes contain messages"): courses hold sections,
/// sections hold classes, so the bar reads Course · Section · Classes.
///
/// `SectionMenu` draws both menus from these lists, so the split is data:
/// `contracts/shared-rules.json` → `subjectMenus.layout` holds the same
/// lists, and `SubjectMenuLayoutTests` checks the two agree and that the
/// real menu bar draws exactly this. Which items can be used is still
/// `SubjectMenuRules`' job; every item here is drawn in every situation and
/// dimmed when it cannot be used, never hidden.
nonisolated enum SubjectMenuLayout {

    // MARK: - Types

    /// The two menus that act on a selected section.
    enum Menu: String, CaseIterable, Sendable {
        case section
        case classes
    }

    /// A submenu inside one of the menus.
    enum Submenu: String, CaseIterable, Sendable {
        case sectionReviseWith
    }

    /// One line of a menu: an item, or a submenu of items.
    enum Entry: Hashable, Sendable {
        case item(SubjectMenuRules.Item)
        case submenu(Submenu)
    }

    // MARK: - Stored properties

    /// Section ▸, group by group. A separator goes between groups.
    ///
    /// The two Undo items stay here, last in the publishing group, until
    /// #899 U7 folds them into Edit ▸ Undo. Change Deploy Time… (#525) will
    /// go between Schedule Deploy… and Remove Scheduled Deploy
    /// (`subjectMenus.layout.reservedPlaces`).
    static let sectionGroups: [[Entry]] = [
        [.item(.preview), .item(.rebuildPreview), .item(.openInBrowser), .item(.stopShowingDeployedFolder)],
        [
            .item(.publishClassForADate), .item(.publishPages), .item(.hidePages), .item(.publishPagesLinksLeadTo),
            .item(.undoLastChange), .item(.undoGettingReady),
        ],
        [.item(.deploy), .item(.scheduleDeploy), .item(.cancelScheduledDeploy)],
        [.submenu(.sectionReviseWith)],
        [.item(.sectionOpenInObsidian), .item(.sectionShowInFinder), .item(.sectionNewTerminalAtFolder)],
        [.item(.removeSection)],
    ]

    /// Classes ▸, group by group.
    static let classesGroups: [[Entry]] = [
        [.item(.addClass)],
        [.item(.classDates), .item(.reDateClasses), .item(.makeRoomForClasses)],
        [.item(.rollOverToANewYear), .item(.getReadyForTheStartOfTheYear)],
    ]

    /// Revise With ▸'s items, in the order the doors are shown everywhere.
    static let sectionReviseWithItems: [SubjectMenuRules.Item] = [
        .sectionReviseWithClaude, .sectionReviseWithCodex, .sectionReviseWithCopilot, .sectionReviseWithLocalAssistant,
    ]

    // MARK: - Functions

    /// The menu's groups.
    static func groups(of menu: Menu) -> [[Entry]] {
        switch menu {
        case .section:
            return sectionGroups
        case .classes:
            return classesGroups
        }
    }

    /// The menu's title in the menu bar.
    static func title(of menu: Menu) -> String {
        switch menu {
        case .section:
            return "Section"
        case .classes:
            return "Classes"
        }
    }

    /// The submenu's title.
    static func title(of submenu: Submenu) -> String {
        switch submenu {
        case .sectionReviseWith:
            return "Revise With"
        }
    }

    /// The submenu's items.
    static func items(of submenu: Submenu) -> [SubjectMenuRules.Item] {
        switch submenu {
        case .sectionReviseWith:
            return sectionReviseWithItems
        }
    }

    /// Which of the two menus holds the item, directly or in a submenu; nil
    /// for an item of File, Course or View.
    static func menu(containing item: SubjectMenuRules.Item) -> Menu? {
        for menu in Menu.allCases {
            for group in groups(of: menu) {
                for entry in group {
                    switch entry {
                    case .item(let held):
                        if held == item {
                            return menu
                        }
                    case .submenu(let submenu):
                        if items(of: submenu).contains(item) {
                            return menu
                        }
                    }
                }
            }
        }
        return nil
    }

    /// "Section or Classes": the two menus' titles in the layout's order, for
    /// a sentence that covers a change from either (#990, Russell's ruling
    /// "name the real menu": "the few sentences that cover both say 'the
    /// Section or Classes menu'").
    static var eitherMenu: String {
        var titles: [String] = []
        for menu in Menu.allCases {
            titles.append(title(of: menu))
        }
        return titles.joined(separator: " or ")
    }

    /// Where an item is, the way a teacher would say it: "Classes ▸ Add
    /// Class…" for `.addClass` and "Add Class…". The menu's title comes from
    /// the layout, so a menu path moves when the item does.
    static func path(of item: SubjectMenuRules.Item, titled title: String) -> String {
        guard let menu = menu(containing: item) else {
            return title
        }
        return SubjectMenuLayout.title(of: menu) + " ▸ " + title
    }
}
