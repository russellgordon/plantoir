import Foundation

/// The names VoiceOver reads for controls whose visible title is empty,
/// hidden, or only a symbol (#993, the Mac HIG review's findings D16 to
/// D20, D40 and D41).
///
/// Apple's VoiceOver guidance: "Provide alternative labels for all key
/// interface elements." Each name is the control's visible title where it
/// has one, or a plain two- or three-word label, and never the control's
/// kind ("button", "pop-up"), which VoiceOver says by itself. Kept in one
/// place so the wording review (#1001) can read them all together.
nonisolated enum AccessibilityNames {

    // MARK: - Stored properties

    /// A section's Website | Coverage | Problems bar (D16).
    static let sectionTabs: String = "Section View"

    /// A course's Settings | Planning bar (D16).
    static let courseTabs: String = "Course View"

    /// The assistant composer's arrow button (D17), which VoiceOver read
    /// as "Arrow Up Circle", the symbol's own name.
    static let send: String = "Send"

    /// The smiley button beside an emoji field (D18), which VoiceOver read
    /// as "face.smiling". The same words as its tooltip, in title case.
    static let chooseEmoji: String = "Choose Emoji"

    /// Publish Class for a Date: the date field (D18).
    static let classDate: String = "Class Date"

    /// Make Room: which class to make room before (D18).
    static let makeRoomClass: String = "Class"

    /// Make Room: how many classes of room (D18). VoiceOver reads the
    /// number as the stepper's value after this name.
    static let makeRoomHowMany: String = "Number of Classes"

    /// Add Class: the radio group of ways (D18).
    static let addClassWay: String = "Way to Add"

    /// Roll Over: the new-or-same website radio group (D18).
    static let rollOverWebsite: String = "Website"

    /// Add a Section: the number field and its stepper, named by the words
    /// printed beside them, "Section number:" (D18).
    static let sectionNumber: String = "Section number"

    /// The Class Dates sheet's typing area (D41).
    static let classDates: String = "Class dates"

    /// Publish Pages, Hide Pages and the other page pickers: the table of
    /// pages to tick (D41).
    static let pagesTable: String = "Pages"

    /// The table of what a sheet will change, in a section sheet and in
    /// Get Ready (D41).
    static let planTable: String = "Changes"

    /// Add Class as a copy: the table of classes to copy from (D41).
    static let sourceTable: String = "Classes"

    /// Deploy's later-classes table (D41).
    static let laterClassesTable: String = "Later Classes"

    /// The Copy a Page sheet's problem line, said before the sentence so
    /// it is not told apart by its orange alone (D19).
    static let warning: String = "Warning"

    /// The multi-destination deploy checklist, one state per destination
    /// (D19): before this, the state was only a coloured symbol.
    static let destinationWaiting: String = "Waiting"
    static let destinationDeploying: String = "Deploying"
    static let destinationDone: String = "Done"
    static let destinationFailed: String = "Failed"
}
