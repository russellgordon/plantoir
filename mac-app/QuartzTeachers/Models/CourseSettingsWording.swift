import Foundation

/// The sentences Course Settings says in its own voice (#369, #364/#373):
/// labels and captions that used to be string literals in the view.
///
/// Every one is pinned against `contracts/shared-rules.json` →
/// `courseSettingsWording`, so the Windows app reads the same words rather
/// than retyping them, and none of them may name the machinery
/// (`userFacingLabelWords.forbidden`, CLAUDE.md rule 1).
enum CourseSettingsWording {

    // MARK: - Stored properties

    /// The locale picker's label, in Course Settings AND in the wizard, so the
    /// setting has one name wherever it is chosen. It said "Language / region
    /// (Quartz locale)" from v1.1.0 to v1.4.0: the site builder's name in a
    /// label a teacher reads (#369).
    nonisolated static let localeLabel: String = "Language and region"

    /// Under the locale picker: what the choice actually changes. The locale
    /// sets the words the website's own pages use (search, table of
    /// contents, "read time") and how dates are written — nothing else.
    nonisolated static let localeCaption: String =
        "Used for dates and the words on your website’s own pages."

    /// The colour-scheme picker's entry for a section that has no scheme
    /// chosen. It said "Quartz default (none chosen)" (#369's second site,
    /// found by the label scan).
    nonisolated static let colourSchemeNoneChosen: String = "Standard colours (none chosen)"

    // MARK: Printing (#454) - Course Settings' Printing section

    nonisolated static let printingHeader: String = "Printing"
    nonisolated static let printingSchoolName: String = "School name"
    nonisolated static let printingBlanks: String = "Blanks to fill in"
    nonisolated static let printingBlankName: String = "Name"
    nonisolated static let printingBlankDate: String = "Date"
    nonisolated static let printingBlankClassNumber: String = "Class #"
    nonisolated static let printingSchoolNameGoes: String = "School name prints"
    nonisolated static let printingCourseCodeGoes: String = "Course code prints"
    nonisolated static let printingTopLeft: String = "Top left"
    nonisolated static let printingBottomLeft: String = "Bottom left"
    nonisolated static let printingNotPrinted: String = "Not printed"
    nonisolated static let printingCaption: String =
        "Used on pages whose settings say printable: true, when a student or you press Print."

    // MARK: - Functions

    /// The words for one print place (`CourseConfiguration.printPlaces`).
    nonisolated static func printingPlace(_ place: String) -> String {
        if place == "header_left" {
            return printingTopLeft
        }
        if place == "footer_left" {
            return printingBottomLeft
        }
        return printingNotPrinted
    }

    /// The words for one blank (`CourseConfiguration.printBlankOrder`).
    nonisolated static func printingBlank(_ blank: String) -> String {
        if blank == "name" {
            return printingBlankName
        }
        if blank == "date" {
            return printingBlankDate
        }
        return printingBlankClassNumber
    }

    /// Beside Save, when this window's changes cannot be saved because they
    /// changed where the course publishes and that destination has a
    /// problem (#373). `reason` is the destination's own sentence
    /// (`CourseConfiguration.deployFolderProblem` /
    /// `cloudflareAccountProblem`), already a contract sentence. Without
    /// this, Save simply stayed grey and nothing near it said why.
    nonisolated static func saveHeldBack(reason: String) -> String {
        return "Save is held back until Deploying is fixed: " + reason
    }
}
