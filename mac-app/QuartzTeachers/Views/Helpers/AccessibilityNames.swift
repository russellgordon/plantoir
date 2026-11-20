import Foundation

/// The names VoiceOver reads for controls whose visible title is empty,
/// hidden, or only a symbol (#993, the Mac HIG review's findings D16 to
/// D20, D40 and D41).
///
/// Apple's VoiceOver guidance: "Provide alternative labels for all key
/// interface elements." A control with a visible title or a printed label
/// beside it is named by those words, passed where it is drawn; the names
/// here are for controls that show no words at all. Each is a plain one-
/// to three-word label in sentence case, like the app's printed field
/// labels ("Course name", "Folder name"): the HIG's Writing page asks for
/// one style per kind of element ("Choose a style for each UI element type
/// and use it consistently"), and Apple's accessibility programming guide
/// asks that a label begin with a capitalized word, not end with a period,
/// and not name the control's kind ("button", "pop-up"), which VoiceOver
/// says by itself. Kept in one place so the wording review (#1001) can
/// read them all together.
nonisolated enum AccessibilityNames {

    // MARK: - Stored properties

    /// The assistant composer's arrow button (D17), which VoiceOver read
    /// as "Arrow Up Circle", the symbol's own name.
    static let send: String = "Send"

    /// The smiley button beside an emoji field (D18), which VoiceOver read
    /// as "face.smiling". Its tooltip's words, shortened.
    static let chooseEmoji: String = "Choose emoji"

    /// Publish Class for a Date: the date field (D18).
    static let classDate: String = "Class date"

    /// Make Room: which class to make room before (D18).
    static let makeRoomClass: String = "Class"

    /// Make Room: how many classes of room (D18). VoiceOver reads the
    /// number as the stepper's value after this name.
    static let makeRoomHowMany: String = "Number of classes"

    /// Add Class: the radio group of ways (D18).
    static let addClassWay: String = "Way to add"

    /// Roll Over: the new-or-same website radio group (D18).
    static let rollOverWebsite: String = "Website"

    /// Add a Section: the number field, named by the words printed beside
    /// it, "Section number:" (D18). Its stepper is not given this name: the
    /// stepper's own title already says it, and a second name made
    /// VoiceOver read "Section number, Section number".
    static let sectionNumber: String = "Section number"

    /// The spinner a restored window shows before its folder opens (D18).
    static let openingFolder: String = "Opening folder"

    /// The Class Dates sheet's typing area (D41).
    static let classDates: String = "Class dates"

    /// The assistant's composer (#1012): its placeholder's words, without
    /// the ellipsis, as the sidebar's Filter field is named by its own.
    static let askAboutThisSection: String = "Ask about this section"

    /// Class Dates' Google Sheet link (#1012), whose placeholder is an
    /// address rather than words: the words of the sentence above it ("Paste
    /// the sheet's address") and of the route it sits under ("A Google
    /// Sheet").
    static let googleSheetAddress: String = "Google Sheet address"

    /// The console's answer box and the question alert's field (#1012): the
    /// words of the alert's own placeholder, which the console's placeholder
    /// ends with ("type your answer here").
    static let yourAnswer: String = "Your answer"

    /// The console's spinner while a task runs (#1012), the state that
    /// "Finished" replaces in the same place.
    static let running: String = "Running"

    /// Publish Pages, Hide Pages and the other page pickers: the table of
    /// pages to tick (D41).
    static let pagesTable: String = "Pages"

    /// The table of what a sheet will change, in a section sheet and in
    /// Get Ready (D41).
    static let planTable: String = "Changes"

    /// Add Class as a copy: the table of classes to copy from (D41).
    static let sourceTable: String = "Classes"

    /// Deploy's later-classes table (D41).
    static let laterClassesTable: String = "Later classes"

    /// The multi-destination deploy checklist, one state per destination
    /// (D19): before this, the state was only a coloured symbol.
    static let destinationWaiting: String = "Waiting"
    static let destinationDeploying: String = "Deploying"
    static let destinationDone: String = "Done"
    static let destinationFailed: String = "Failed"
}
