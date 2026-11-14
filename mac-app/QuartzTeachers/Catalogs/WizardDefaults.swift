import Foundation

/// The defaults the setup wizard offers for a brand-new course, mirroring
/// the constants at the top of `scripts/setup_course.py`.
///
/// The factory defaults are school-neutral. Until 2.0.0 a wizard switch
/// offered one school's own folder and file names instead; it was removed
/// (#891), and a course made with it keeps the names in its settings.
enum WizardDefaults {

    // MARK: - Stored properties

    static let sharedFolders: [String] = [
        "Concepts", "Discussions", "Examples", "Exercises",
        "Ontario Curriculum", "Portfolios",
        "Recaps", "Setup", "Style", "Tasks", "Tutorials",
    ]

    static let sharedFiles: [String] = [
        "Extra Help.md", "Learning Goals.md",
    ]

    static let perSectionFolders: [String] = [
        "All Classes",
    ]

    static let perSectionFiles: [String] = [
        "Private Notes.md", "Scratch Page.md", "Key Links.md",
    ]

    /// Hidden by default when a new course has them. Grove Time and SIC
    /// Drop-In Sessions stay listed after #891 removed the switch that
    /// offered them, so a teacher who types either name still gets it hidden
    /// as before; the wizard hides only names the course actually has.
    static let hiddenItems: [String] = [
        "Media", "Curriculum", "Ontario Curriculum", "College Board Curriculum",
        "Extra Help.md", "SIC Drop-In Sessions.md", "Grove Time.md",
        "Learning Goals.md",
        "Private Notes.md", "Scratch Page.md", "Key Links.md",
    ]

    static let expandableItems: [String] = [
        "Concepts", "Discussions", "Examples", "Exercises", "Portfolios",
        "Recaps", "Setup", "Style", "Tasks", "Tutorials",
    ]
}
