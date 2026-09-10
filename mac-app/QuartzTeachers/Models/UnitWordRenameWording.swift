import Foundation

/// What a teacher reads while renaming a course's word for a unit — "Unit"
/// to "Module", say — after the course is already in use.
///
/// Authored in `contracts/shared-rules.json` → `specialNames.renameUnitWord`,
/// beside the folder rename's sentences, because it is the same kind of
/// sentence read in the same place: a sheet in Course Settings that commits
/// to disk straight away. Name these rather than quoting them.
enum UnitWordRenameWording {

    // MARK: - Stored properties

    /// The label beside the current word in Course Settings, and above the
    /// field in the sheet — the wizard's own question, so a teacher meets one
    /// phrase for one idea.
    nonisolated static let fieldLabel: String = "What do you call a unit?"

    /// The button that opens the sheet.
    nonisolated static let renameButton: String = "Rename…"

    nonisolated static let explanation: String =
        "This renames every class page on your Mac, in every section, and points your pages’ links at the new names. It happens straight away, so Cancel in Settings will not undo it. To change it back, rename it again; a backup of the whole course is saved first, as a last resort."

    /// The one thing a teacher would otherwise report as a defect: a page
    /// called "Unit 2 Test", or a sentence saying "by the end of Unit 3",
    /// keeps its word.
    nonisolated static let proseIsLeftAlone: String =
        "Pages and sentences that mention a unit by number, other than the class pages themselves, are left as they are."

    nonisolated static let problemEmpty: String =
        "Type the word this course uses for a unit."

    nonisolated static let problemUnchanged: String =
        "That is already this course’s word."

    /// Shown while the plan is being worked out.
    nonisolated static let lookingOver: String =
        "Looking over the course’s pages…"

    nonisolated static let previewLinksNone: String =
        "No links point at those names, so nothing else needs changing."

    nonisolated static let previewLinksOne: String =
        "One link points at those names and would be updated to match."

    nonisolated static let donePagesNone: String =
        "No class page needed renaming, so only this course’s settings changed."

    nonisolated static let donePagesOne: String =
        "One class page was renamed."

    nonisolated static let doneLinksNone: String =
        "No links needed updating."

    nonisolated static let doneLinksOne: String =
        "One link was updated to match."

    nonisolated static let donePublish: String =
        "Publish each section for its website to use the new names."

    nonisolated static let doneBackup: String =
        "A backup of the whole course was saved first, and is listed under Backups."

    // MARK: - Functions

    nonisolated static func sheetTitle(for word: String) -> String {
        return "Rename “\(word)”"
    }

    /// The caption under the row in Course Settings, in the course's CURRENT
    /// word — a literal "Unit" here would lie the moment a rename landed.
    nonisolated static func rowCaption(word: String) -> String {
        return "Class pages are named “\(word) 1, Day 1”."
    }

    /// A rename that stopped part way must be finished with the SAME word.
    /// Any other word would plan from the old word alone, leave the pages
    /// already moved matching neither, and end with three words in one course.
    nonisolated static func problemMustFinishFirst(target: String) -> String {
        return "Plantoir is part way through renaming to “\(target)”. Finish that first — press Rename with “\(target)” — and then rename again."
    }

    /// The note of a rename under way could not be written, so nothing was
    /// tried — a rename with no note is one that cannot be recognised if it
    /// stops. Its own sentence, because "renamed 0 of 3 and could not rename
    /// Unit 1, Day 1" would blame a page nothing had touched.
    nonisolated static func problemRecordNotWritten(reason: String) -> String {
        return "Plantoir could not write its note of the rename under way (\(reason)), so nothing was renamed. Check that the working folder can be written to, then try again."
    }

    /// Links the rename could not follow because their page could not be
    /// written. Said, because the teacher was shown a count and would
    /// otherwise be told a smaller one with no explanation.
    nonisolated static func doneLinksNotWritten(pages: Int) -> String {
        if pages == 1 {
            return "One page could not be written, so its links still use the old names."
        }
        return "\(pages) pages could not be written, so their links still use the old names."
    }

    nonisolated static func problemPageInTheWay(courseCode: String, sectionNumber: Int, name: String) -> String {
        return "\(courseCode) Section \(sectionNumber) already has a page called “\(name)”, so the pages cannot be renamed. Move or rename that page first."
    }

    nonisolated static func problemPageUnreadable(courseCode: String, sectionNumber: Int, name: String) -> String {
        return "“\(name)” in \(courseCode) Section \(sectionNumber) could not be read, so nothing was renamed. If the course is kept in iCloud Drive, wait for it to finish downloading and try again."
    }

    /// The same shape as restoring a backup uses, because it is the same
    /// situation: a build copies the course's pages, and copying half of a
    /// rename builds a site with two numbering schemes.
    nonisolated static func problemBusy(courseCode: String) -> String {
        return "\(courseCode) is previewing or deploying right now. Stop that first, then rename."
    }

    /// What would be renamed, worded for the number it actually found.
    nonisolated static func previewPages(
        courseCode: String, pages: Int, sections: [Int], old: String, new: String
    ) -> String {
        if pages == 0 {
            return "No class page in \(courseCode) is named “\(old) N, Day N”, so only this course’s settings would change: new class pages will be named “\(new) 1, Day 1” and so on."
        }
        if pages == 1 {
            return "One class page, in \(sectionsPhrase(sections)), would be renamed — “\(old) 1, Day 1” becomes “\(new) 1, Day 1”, and so on."
        }
        return "\(pages) class pages in \(sectionsPhrase(sections)) would be renamed — “\(old) 1, Day 1” becomes “\(new) 1, Day 1”, and so on."
    }

    nonisolated static func previewLinks(count: Int) -> String {
        if count == 0 {
            return previewLinksNone
        }
        if count == 1 {
            return previewLinksOne
        }
        return "\(count) links point at those names and would be updated to match."
    }

    nonisolated static func done(from old: String, to new: String) -> String {
        return "“\(old)” is now “\(new)”."
    }

    nonisolated static func donePages(count: Int) -> String {
        if count == 0 {
            return donePagesNone
        }
        if count == 1 {
            return donePagesOne
        }
        return "\(count) class pages were renamed."
    }

    nonisolated static func doneLinks(count: Int) -> String {
        if count == 0 {
            return doneLinksNone
        }
        if count == 1 {
            return doneLinksOne
        }
        return "\(count) links were updated to match."
    }

    /// The whole sentence a teacher reads after it worked.
    nonisolated static func doneSentence(
        from old: String, to new: String, pages: Int, links: Int, pagesNotWritten: Int = 0
    ) -> String {
        var pieces: [String] = [done(from: old, to: new), donePages(count: pages)]
        // Links are reported whenever any were touched, not only when a page
        // moved: finishing a rename that stopped during its link pass moves
        // nothing and rewrites plenty.
        if pages > 0 || links > 0 || pagesNotWritten > 0 {
            pieces.append(doneLinks(count: links))
            if pagesNotWritten > 0 {
                pieces.append(doneLinksNotWritten(pages: pagesNotWritten))
            }
            pieces.append(donePublish)
        }
        pieces.append(doneBackup)
        return pieces.joined(separator: " ")
    }

    /// Shown in the sheet when a rename got part way and stopped.
    nonisolated static func interruptedRename(from old: String, to new: String) -> String {
        return "Plantoir started renaming “\(old)” to “\(new)” and did not finish — some class pages have the new word, and this course’s settings still use the old one. Press Rename to finish."
    }

    /// The count that moved, and the page that stopped it — a bare error would
    /// leave a teacher with a course half renamed and no idea which half.
    nonisolated static func halfDone(renamed: Int, of total: Int, stoppedAt name: String, reason: String) -> String {
        return "Plantoir renamed \(renamed) of \(total) class pages and then could not rename “\(name)”: \(reason). Press Rename to finish the rest."
    }

    /// The pages HAVE been renamed, so this is not "the rename failed" — it is
    /// a rename whose bookkeeping did not land.
    nonisolated static func settingsNotWritten(new: String, reason: String) -> String {
        return "Every class page now says “\(new)”, but Plantoir could not write the change to this course’s settings: \(reason). Press Rename to finish."
    }

    /// "Section 1", "Sections 1 and 3", "Sections 1, 2 and 4".
    nonisolated static func sectionsPhrase(_ numbers: [Int]) -> String {
        var spelled: [String] = []
        for number in numbers {
            spelled.append("\(number)")
        }
        if spelled.isEmpty {
            return "no section"
        }
        if spelled.count == 1 {
            return "Section \(spelled[0])"
        }
        var allButLast: [String] = []
        for index in 0..<(spelled.count - 1) {
            allButLast.append(spelled[index])
        }
        return "Sections " + allButLast.joined(separator: ", ") + " and " + spelled[spelled.count - 1]
    }
}
