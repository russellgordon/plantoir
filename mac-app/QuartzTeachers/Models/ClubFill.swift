import Foundation

/// The words a club uses, or a course (#267).
///
/// A club — a coding club, a debate team — meets rather than holds classes,
/// counts its meetings with one number, and has no curriculum. The New Course
/// wizard's "This is a club" choice fills these in; every one of them can be
/// edited before the course is created, and none is switchable afterwards
/// (Russell, 2026-09-24).
nonisolated struct ClubVocabulary: Equatable {

    // MARK: - Stored properties

    /// The per-section folder the class pages live in.
    let classFolder: String

    /// The word a page is named with: "Week" in "Week 3", "Unit" in
    /// "Unit 2, Day 3".
    let unitWord: String

    /// The heading a section's front page is created with.
    let frontPageHeading: String

    /// What the assistant calls one page when it talks to the teacher.
    let noun: ClassNoun

    // MARK: - Computed properties

    /// A club's words.
    static var club: ClubVocabulary {
        return ClubVocabulary(
            classFolder: "All Meetings", unitWord: "Week",
            frontPageHeading: "Most Recent Meeting", noun: .meeting
        )
    }

    /// A course's words — what every course made before #267 says.
    static var course: ClubVocabulary {
        return ClubVocabulary(
            classFolder: "All Classes", unitWord: ClassPageTerm.standard,
            frontPageHeading: "Most Recent Class", noun: .class
        )
    }
}

/// What the wizard's fields hold, as far as the club choice touches them.
nonisolated struct ClubFillFields: Equatable {

    // MARK: - Stored properties

    var sharedFolders: [String]
    var perSectionFolders: [String]

    /// Which entry of `perSectionFolders` holds the class pages. Recorded as
    /// `class_folder`, never guessed: "All Meetings" has no "class" in it.
    var classFolder: String
    var unitWord: String
    var frontPageHeading: String
    var noun: ClassNoun
}

/// Turning "This is a club" on or off, as a pure function — a SwiftUI
/// `@State` has no backing store off screen, so the rule lives here where a
/// test can reach it, the way `WizardStructure.restoringDefaults` does.
///
/// **A field is changed only while it still holds the value the OTHER choice
/// would have put there.** A teacher who typed "All Gatherings" and then
/// ticks the box off and on again keeps "All Gatherings"; one who never
/// touched a field sees it follow the box. Same rule as the skeleton's
/// restore, for the same reason: a switch that quietly undid typing would be
/// a switch nobody trusted.
///
/// A club has no curriculum (Russell, 2026-09-24: no coverage page, no
/// Curriculum folder), so turning it on also takes every curriculum folder
/// out of the shared folders; turning it off puts the factory one back.
enum ClubFill {

    // MARK: - Stored properties

    /// Every name a curriculum folder is given by the wizard's defaults and
    /// its skeletons.
    static let curriculumFolders: [String] = [
        "Ontario Curriculum", "College Board Curriculum", "Curriculum",
    ]

    // MARK: - Functions

    static func applying(
        isClub: Bool, to fields: ClubFillFields, usesLCSTerminology: Bool
    ) -> ClubFillFields {
        let leaving: ClubVocabulary = isClub ? ClubVocabulary.course : ClubVocabulary.club
        let arriving: ClubVocabulary = isClub ? ClubVocabulary.club : ClubVocabulary.course
        var result: ClubFillFields = fields

        if fields.unitWord == leaving.unitWord {
            result.unitWord = arriving.unitWord
        }
        if fields.frontPageHeading == leaving.frontPageHeading {
            result.frontPageHeading = arriving.frontPageHeading
        }
        if fields.noun == leaving.noun {
            result.noun = arriving.noun
        }

        // The class folder keeps its PLACE in the list, so a teacher's own
        // order survives, and the recorded name follows it.
        if fields.classFolder == leaving.classFolder {
            var folders: [String] = []
            var replaced: Bool = false
            for folder in fields.perSectionFolders {
                if folder == leaving.classFolder && !replaced {
                    folders.append(arriving.classFolder)
                    replaced = true
                } else {
                    folders.append(folder)
                }
            }
            if !replaced && !folders.contains(arriving.classFolder) {
                folders.insert(arriving.classFolder, at: 0)
            }
            result.perSectionFolders = folders
            result.classFolder = arriving.classFolder
        }

        if isClub {
            var kept: [String] = []
            for folder in fields.sharedFolders {
                if !curriculumFolders.contains(folder) {
                    kept.append(folder)
                }
            }
            result.sharedFolders = kept
        } else {
            result.sharedFolders = puttingTheCurriculumFoldersBack(
                into: fields.sharedFolders, usesLCSTerminology: usesLCSTerminology
            )
        }
        return result
    }

    /// The factory curriculum folders, back in their factory places, for a
    /// list that had them taken out.
    private static func puttingTheCurriculumFoldersBack(
        into folders: [String], usesLCSTerminology: Bool
    ) -> [String] {
        let factory: [String] = usesLCSTerminology ? WizardDefaults.lcsSharedFolders : WizardDefaults.sharedFolders
        var result: [String] = folders
        for (index, name) in factory.enumerated() {
            if !curriculumFolders.contains(name) || result.contains(name) {
                continue
            }
            result.insert(name, at: min(index, result.count))
        }
        return result
    }
}
